# AWS S3 File Gateway - Demo Deployment Script
# This is a single-file Terraform deployment for quick demo/POC setup
# NOT for production use - optimized for speed and simplicity

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

# Variables for quick customization
variable "demo_name" {
  description = "Name prefix for demo resources"
  type        = string
  default     = "smc-gateway-demo"
}

variable "s3_bucket_name" {
  description = "S3 bucket name for file gateway"
  type        = string
  default     = "smc-gateway-bucket-test-001"
}

variable "key_pair_name" {
  description = "EC2 key pair name for instances"
  type        = string
  default     = "smc-dev-aws-keyz"
}

variable "allowed_cidr" {
  description = "CIDR block allowed to access NFS share"
  type        = string
  default     = "0.0.0.0/0"  # Demo only - restrict in production
}

# Data sources
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "storage_gateway" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["aws-storage-gateway-*"]
  }
}

data "aws_ami" "windows_server" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
}

# S3 bucket for file gateway
resource "aws_s3_bucket" "gateway_bucket" {
  bucket        = var.s3_bucket_name
  force_destroy = true  # Demo only - allows easy cleanup

  tags = {
    Name        = "${var.demo_name}-bucket"
    Environment = "demo"
    Purpose     = "FileGateway"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "gateway_bucket_encryption" {
  bucket = aws_s3_bucket.gateway_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Security group for Storage Gateway
resource "aws_security_group" "storage_gateway" {
  name        = "${var.demo_name}-storage-gateway-sg"
  description = "Security group for Storage Gateway"
  vpc_id      = data.aws_vpc.default.id

  # Storage Gateway activation (port 80)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NFS access
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Demo only
  }

  # ICMP for ping
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.demo_name}-storage-gateway-sg"
  }
}

# IAM role for Storage Gateway
resource "aws_iam_role" "storage_gateway_role" {
  name = "${var.demo_name}-storage-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "storagegateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "storage_gateway_policy" {
  name = "${var.demo_name}-storage-gateway-policy"
  role = aws_iam_role.storage_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketNotification",
          "s3:PutBucketNotification",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          aws_s3_bucket.gateway_bucket.arn,
          "${aws_s3_bucket.gateway_bucket.arn}/*"
        ]
      }
    ]
  })
}

# EC2 instance for Storage Gateway
resource "aws_instance" "storage_gateway" {
  ami                    = data.aws_ami.storage_gateway.id
  instance_type          = "m5.xlarge"
  key_name               = var.key_pair_name
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.storage_gateway.id]

  # User data for initial setup
  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Configure Storage Gateway
    echo "Storage Gateway instance starting up..."
    
    # Wait for network to be ready
    sleep 30
    
    # Create activation script
    cat > /tmp/activate_gateway.sh << 'SCRIPT'
    #!/bin/bash
    echo "To activate this gateway:"
    echo "1. Get the activation key from: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)?activationRegion=us-west-2"
    echo "2. Use the activation key in the AWS Console or AWS CLI"
    echo "3. Configure as FILE_S3 gateway type"
    SCRIPT
    
    chmod +x /tmp/activate_gateway.sh
    /tmp/activate_gateway.sh > /tmp/activation_info.txt
    EOF
  )

  tags = {
    Name = "${var.demo_name}-storage-gateway"
  }
}

# EBS volume for cache
resource "aws_ebs_volume" "cache_disk" {
  availability_zone = aws_instance.storage_gateway.availability_zone
  size              = 150
  type              = "gp3"
  encrypted         = false

  tags = {
    Name = "${var.demo_name}-cache-disk"
  }
}

resource "aws_volume_attachment" "cache_disk_attachment" {
  device_name = "/dev/sdb"
  volume_id   = aws_ebs_volume.cache_disk.id
  instance_id = aws_instance.storage_gateway.id
}

# Security group for Windows demo instance
resource "aws_security_group" "windows_demo" {
  name        = "${var.demo_name}-windows-sg"
  description = "Security group for Windows demo instance"
  vpc_id      = data.aws_vpc.default.id

  # RDP access
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Demo only
  }

  # SMB/CIFS access
  ingress {
    from_port   = 445
    to_port     = 445
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  # ICMP for ping
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.demo_name}-windows-sg"
  }
}

# Windows EC2 instance for demo
resource "aws_instance" "windows_demo" {
  ami                    = data.aws_ami.windows_server.id
  instance_type          = "t3.medium"
  key_name               = "${var.key_pair_name}-rsa"  # RSA key for Windows
  vpc_security_group_ids = [aws_security_group.windows_demo.id]
  subnet_id              = data.aws_subnets.default.ids[0]

  user_data = base64encode(<<-EOF
    <powershell>
    # Install NFS Client
    Enable-WindowsOptionalFeature -Online -FeatureName ServicesForNFS-ClientOnly -All
    
    # Create demo directory
    New-Item -ItemType Directory -Path "C:\StorageGatewayDemo" -Force
    
    # Create demo script
    $script = @"
# Storage Gateway Demo Script
Write-Host "Storage Gateway Demo Commands" -ForegroundColor Green
Write-Host "=============================" -ForegroundColor Green
Write-Host ""
Write-Host "Gateway IP: ${aws_instance.storage_gateway.private_ip}" -ForegroundColor Cyan
Write-Host "S3 Bucket: ${var.s3_bucket_name}" -ForegroundColor Cyan
Write-Host ""
Write-Host "NFS Mount Command:" -ForegroundColor Yellow
Write-Host "mount -o anon \\${aws_instance.storage_gateway.private_ip}\${var.s3_bucket_name} Z:" -ForegroundColor White
Write-Host ""
Write-Host "To activate gateway, visit:" -ForegroundColor Yellow
Write-Host "http://${aws_instance.storage_gateway.public_ip}?activationRegion=us-west-2" -ForegroundColor White
"@
    
    $script | Out-File -FilePath "C:\StorageGatewayDemo\demo-commands.ps1" -Encoding UTF8
    
    # Create desktop shortcut
    $WshShell = New-Object -comObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("C:\Users\Administrator\Desktop\Storage Gateway Demo.lnk")
    $Shortcut.TargetPath = "powershell.exe"
    $Shortcut.Arguments = "-ExecutionPolicy Bypass -File C:\StorageGatewayDemo\demo-commands.ps1"
    $Shortcut.Save()
    </powershell>
    EOF
  )

  tags = {
    Name = "${var.demo_name}-windows"
  }
}

# Outputs for easy access
output "deployment_summary" {
  value = <<-EOF
    
    ==========================================
    AWS S3 File Gateway Demo Deployment Complete!
    ==========================================
    
    NEXT STEPS:
    1. Activate Storage Gateway:
       - Visit: http://${aws_instance.storage_gateway.public_ip}?activationRegion=us-west-2
       - Choose "FILE_S3" gateway type
       - Use bucket: ${var.s3_bucket_name}
       - Use IAM role: ${aws_iam_role.storage_gateway_role.name}
    
    2. Create NFS File Share (via AWS Console):
       - Gateway: Use the activated gateway
       - S3 bucket: ${var.s3_bucket_name}
       - IAM role: ${aws_iam_role.storage_gateway_role.arn}
       - Client access: ${var.allowed_cidr}
    
    3. Connect to Windows demo instance:
       - RDP to: ${aws_instance.windows_demo.public_ip}:3389
       - Get password: aws ec2 get-password-data --instance-id ${aws_instance.windows_demo.id} --priv-launch-key ${var.key_pair_name}-rsa.pem
       - Run demo script from desktop shortcut
    
    RESOURCES CREATED:
    - Storage Gateway Instance: ${aws_instance.storage_gateway.id}
    - Windows Demo Instance: ${aws_instance.windows_demo.id}
    - S3 Bucket: ${var.s3_bucket_name}
    - IAM Role: ${aws_iam_role.storage_gateway_role.name}
    
    CLEANUP:
    - Run: terraform destroy
    
    EOF
}

output "activation_url" {
  description = "URL to activate the Storage Gateway"
  value       = "http://${aws_instance.storage_gateway.public_ip}?activationRegion=us-west-2"
}

output "storage_gateway_ip" {
  description = "Storage Gateway IP address"
  value       = aws_instance.storage_gateway.private_ip
}

output "windows_rdp_info" {
  description = "Windows RDP connection information"
  value       = "RDP: ${aws_instance.windows_demo.public_ip}:3389"
}

output "s3_bucket_name" {
  description = "S3 bucket name for file gateway"
  value       = aws_s3_bucket.gateway_bucket.bucket
}

output "nfs_mount_command" {
  description = "NFS mount command for Linux/Windows"
  value       = "mount -o anon \\\\${aws_instance.storage_gateway.private_ip}\\${var.s3_bucket_name} Z:"
}
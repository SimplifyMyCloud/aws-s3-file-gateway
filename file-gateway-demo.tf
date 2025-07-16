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

# Data source for S3 bucket
data "aws_s3_bucket" "_gateway_bucket" {
  bucket = "smc-gateway-bucket-test-001"
}

# S3 bucket
resource "aws_s3_bucket" "gateway_bucket" {
  bucket        = "smc-gateway-bucket-test-001"
  force_destroy = false

  tags = {
    Name        = "smc-gateway-bucket-test-001"
    Environment = "test"
    Purpose     = "StorageGateway"
  }
}

# S3 bucket encryption (AES256)
resource "aws_s3_bucket_server_side_encryption_configuration" "gateway_bucket_encryption" {
  bucket = aws_s3_bucket.gateway_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Storage Gateway
resource "aws_storagegateway_gateway" "file_gateway" {
  gateway_name     = "smc-gateway-test-001"
  gateway_timezone = "GMT-8:00"
  gateway_type     = "FILE_S3"
  activation_key   = "IMPORTED-GATEWAY-KEY" # Placeholder for imported gateway

  tags = {
    Name        = "smc-gateway-test-001"
    Environment = "test"
  }

  # These are only needed for initial activation, not for imported resources
  lifecycle {
    ignore_changes = [
      activation_key,
      gateway_ip_address,
      smb_file_share_visibility
    ]
  }
}

# EC2 instance (Storage Gateway host)
resource "aws_instance" "storage_gateway" {
  ami                    = "ami-0ade39029d5e5d2f6" # Storage Gateway AMI
  instance_type          = "m5.xlarge"
  subnet_id              = "subnet-b484d5cd" # Default subnet us-west-2b
  vpc_security_group_ids = ["sg-0a2367153a35ce4ab"]
  key_name               = "smc-dev-aws-keyz"

  tags = {
    Name = "storagegateway-wizard 428c405b"
  }

  # Ignore changes to wizard-generated tags
  lifecycle {
    ignore_changes = [
      tags["storagegateway:wizard:date"],
      tags["storagegateway:wizard:id"],
      tags["storagegateway:wizard:user"],
      user_data_replace_on_change
    ]
  }
}

# EBS volume (cache disk)
resource "aws_ebs_volume" "cache_disk" {
  availability_zone = "us-west-2b" # Matches actual AZ
  size              = 150
  type              = "gp3"
  encrypted         = false # Matches actual encryption status

  tags = {
    Name        = "storagegateway-wizard 428c405b" # Matches actual name
    Environment = "test"
  }

  # Ignore changes to wizard-generated tags
  lifecycle {
    ignore_changes = [
      tags["storagegateway:wizard:date"],
      tags["storagegateway:wizard:id"],
      tags["storagegateway:wizard:user"]
    ]
  }
}

# volume attachment
resource "aws_volume_attachment" "cache_disk_attachment" {
  device_name = "/dev/sdb"
  volume_id   = aws_ebs_volume.cache_disk.id
  instance_id = aws_instance.storage_gateway.id
}

# NFS file share
resource "aws_storagegateway_nfs_file_share" "nfs_share" {
  client_list  = ["0.0.0.0/0"] # Currently open to all - should be restricted
  gateway_arn  = aws_storagegateway_gateway.file_gateway.arn
  location_arn = aws_s3_bucket.gateway_bucket.arn
  role_arn     = "arn:aws:iam::288782039514:role/service-role/StorageGatewayBucketAccessRole17526444934170.04348896652349399"

  default_storage_class   = "S3_STANDARD"
  file_share_name         = "smc-gateway-bucket-test-001"
  guess_mime_type_enabled = true
  read_only               = false
  requester_pays          = false
  object_acl              = "bucket-owner-full-control" # Matches actual setting

  nfs_file_share_defaults {
    directory_mode = "0777"
    file_mode      = "0666"
    group_id       = 65534
    owner_id       = 65534
  }

  # Ignore bucket_region as it's computed
  lifecycle {
    ignore_changes = [
      bucket_region
    ]
  }
}

# Outputs for  resources
output "_gateway_arn" {
  description = "ARN of the  Storage Gateway"
  value       = aws_storagegateway_gateway.file_gateway.arn
}

output "_s3_bucket_name" {
  description = "Name of the  S3 bucket"
  value       = aws_s3_bucket.gateway_bucket.bucket
}

output "_nfs_file_share_arn" {
  description = "ARN of the  NFS file share"
  value       = aws_storagegateway_nfs_file_share.nfs_share.arn
}

output "_instance_id" {
  description = "ID of the  Storage Gateway EC2 instance"
  value       = aws_instance.storage_gateway.id
}

# Get the latest Windows Server AMI
data "aws_ami" "windows_server" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group for Windows instance
resource "aws_security_group" "windows_demo" {
  name        = "smc-gateway-windows-demo-sg"
  description = "Security group for Windows demo instance"
  vpc_id      = "vpc-93884feb" # Default VPC

  # RDP access
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Open for demo - restrict in production
  }

  # SMB/CIFS access
  ingress {
    from_port   = 445
    to_port     = 445
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"] # VPC CIDR
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "smc-gateway-windows-demo-sg"
    Environment = "test"
    Purpose     = "Demo"
  }
}

# Windows EC2 instance for SMB demo
resource "aws_instance" "windows_demo" {
  ami                    = data.aws_ami.windows_server.id
  instance_type          = "t3.medium"            # Minimum for Windows
  key_name               = "smc-dev-aws-keyz-rsa" # RSA key pair for Windows password decryption
  vpc_security_group_ids = [aws_security_group.windows_demo.id]
  subnet_id              = "subnet-b484d5cd" # Same subnet as Storage Gateway

  user_data = <<-EOF
    <powershell>
    # Enable PowerShell execution policy
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force
    
    # Install NFS Client (for testing both NFS and SMB)
    Enable-WindowsOptionalFeature -Online -FeatureName ServicesForNFS-ClientOnly -All
    
    # Create demo directories
    New-Item -ItemType Directory -Path "C:\StorageGatewayDemo" -Force
    New-Item -ItemType Directory -Path "C:\StorageGatewayDemo\NFS" -Force
    New-Item -ItemType Directory -Path "C:\StorageGatewayDemo\SMB" -Force
    
    # Create demo script
    $script = @"
# Storage Gateway Demo Script
Write-Host "Storage Gateway Demo Commands" -ForegroundColor Green
Write-Host "============================" -ForegroundColor Green
Write-Host ""
Write-Host "NFS Mount (if NFS client installed):" -ForegroundColor Yellow
Write-Host "mount -o anon \\172.31.30.248\smc-gateway-bucket-test-001 Z:" -ForegroundColor White
Write-Host ""
Write-Host "SMB Mount (create SMB share manually via console first):" -ForegroundColor Yellow
Write-Host "net use S: \\172.31.30.248\[SMB_SHARE_NAME] /persistent:no" -ForegroundColor White
Write-Host "Manual SMB Setup: AWS Console -> Storage Gateway -> File shares -> Create" -ForegroundColor Magenta
Write-Host ""
Write-Host "Storage Gateway IP: 172.31.30.248" -ForegroundColor Cyan
Write-Host "S3 Bucket: smc-gateway-bucket-test-001" -ForegroundColor Cyan
"@
    
    $script | Out-File -FilePath "C:\StorageGatewayDemo\demo-commands.ps1" -Encoding UTF8
    
    # Create desktop shortcut
    $WshShell = New-Object -comObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("C:\Users\Administrator\Desktop\Storage Gateway Demo.lnk")
    $Shortcut.TargetPath = "powershell.exe"
    $Shortcut.Arguments = "-ExecutionPolicy Bypass -File C:\StorageGatewayDemo\demo-commands.ps1"
    $Shortcut.WorkingDirectory = "C:\StorageGatewayDemo"
    $Shortcut.Save()
    
    Write-Host "Windows instance setup complete!" -ForegroundColor Green
    </powershell>
    EOF

  tags = {
    Name        = "smc-gateway-windows-demo"
    Environment = "test"
    Purpose     = "Demo"
  }
}

# Additional S3 bucket for SMB share (Storage Gateway doesn't allow overlapping locations)
resource "aws_s3_bucket" "smb_demo_bucket" {
  bucket        = "smc-gateway-smb-bucket-test-001"
  force_destroy = true # For demo purposes

  tags = {
    Name        = "smc-gateway-smb-bucket-test-001"
    Environment = "test"
    Purpose     = "StorageGateway-SMB-Demo"
  }
}

# S3 bucket encryption for SMB bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "smb_bucket_encryption" {
  bucket = aws_s3_bucket.smb_demo_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

output "nfs_mount_command" {
  description = "Command to mount the  NFS share"
  value       = "sudo mount -t nfs -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 172.31.30.248:/smc-gateway-bucket-test-001 /mnt/nfs"
}

output "windows_instance_id" {
  description = "ID of the Windows demo instance"
  value       = aws_instance.windows_demo.id
}

output "windows_public_ip" {
  description = "Public IP of the Windows demo instance"
  value       = aws_instance.windows_demo.public_ip
}

output "windows_rdp_command" {
  description = "RDP connection info for Windows instance"
  value       = "Connect via RDP to ${aws_instance.windows_demo.public_ip}:3389 - Get password with: aws ec2 get-password-data --instance-id ${aws_instance.windows_demo.id} --priv-launch-key smc-dev-aws-keyz-rsa.pem"
}

output "smb_bucket_name" {
  description = "Name of the S3 bucket for SMB share"
  value       = aws_s3_bucket.smb_demo_bucket.bucket
}

output "smb_mount_command_windows" {
  description = "Command to mount SMB share on Windows (create SMB share manually first)"
  value       = "net use S: \\\\172.31.30.248\\[SMB_SHARE_NAME] /persistent:no"
}

output "smb_mount_command_linux" {
  description = "Command to mount SMB share on Linux (create SMB share manually first)"
  value       = "sudo mount -t cifs //172.31.30.248/[SMB_SHARE_NAME] /mnt/smb -o guest"
}

output "manual_smb_setup" {
  description = "Instructions for manually creating SMB share"
  value       = "To create SMB share: 1) Go to AWS Console -> Storage Gateway -> sgw-93C3A8FA -> File shares -> Create file share -> SMB -> Use bucket: smc-gateway-smb-bucket-test-001 -> GuestAccess"
}
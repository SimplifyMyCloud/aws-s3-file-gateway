# Provider configuration - Oregon region
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

# Variables
variable "vpc_id" {
  description = "VPC ID where the Storage Gateway will be deployed"
  type        = string
}

variable "subnet_id" {
  description = "Private subnet ID for the Storage Gateway EC2 instance"
  type        = string
}

variable "key_pair_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name to be accessed via NFS"
  type        = string
}

variable "gateway_name" {
  description = "Name for the Storage Gateway"
  type        = string
  default     = "file-gateway"
}

variable "instance_type" {
  description = "EC2 instance type for Storage Gateway"
  type        = string
  default     = "m5.xlarge"
}

variable "cache_disk_size" {
  description = "Size of the cache disk in GB"
  type        = number
  default     = 150
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Data sources
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Get the latest Storage Gateway AMI
data "aws_ami" "storage_gateway" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["aws-storage-gateway-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Security Group for Storage Gateway
resource "aws_security_group" "storage_gateway" {
  name        = "${var.gateway_name}-sg"
  description = "Security group for Storage Gateway"
  vpc_id      = var.vpc_id

  # NFS traffic
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  # Storage Gateway activation
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  # Storage Gateway management
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  # SSH access (optional, for troubleshooting)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  # Storage Gateway internal communication
  ingress {
    from_port   = 1026
    to_port     = 1028
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  ingress {
    from_port   = 1031
    to_port     = 1031
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.gateway_name}-sg"
    Environment = var.environment
  }
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

# IAM Role for Storage Gateway EC2 instance
resource "aws_iam_role" "storage_gateway_role" {
  name = "${var.gateway_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Storage Gateway
resource "aws_iam_role_policy" "storage_gateway_policy" {
  name = "${var.gateway_name}-policy"
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
          "s3:ListAllMyBuckets",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "storagegateway:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "storage_gateway_profile" {
  name = "${var.gateway_name}-profile"
  role = aws_iam_role.storage_gateway_role.name
}

# EBS volume for cache - Oregon region AZ
resource "aws_ebs_volume" "cache_disk" {
  availability_zone = "${data.aws_region.current.name}a"  # us-west-2a
  size              = var.cache_disk_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name        = "${var.gateway_name}-cache"
    Environment = var.environment
  }
}

# EC2 Instance for Storage Gateway
resource "aws_instance" "storage_gateway" {
  ami                    = data.aws_ami.storage_gateway.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.storage_gateway.id]
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.storage_gateway_profile.name

  # Disable source/destination check
  source_dest_check = false

  # User data for initial configuration
  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    region = data.aws_region.current.name
  }))

  tags = {
    Name        = var.gateway_name
    Environment = var.environment
  }

  # Ensure the instance is created before attaching the cache disk
  lifecycle {
    create_before_destroy = true
  }
}

# Attach cache disk to the instance
resource "aws_volume_attachment" "cache_disk_attachment" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.cache_disk.id
  instance_id = aws_instance.storage_gateway.id
}

# Storage Gateway
resource "aws_storagegateway_gateway" "file_gateway" {
  gateway_name     = var.gateway_name
  gateway_timezone = "GMT"
  gateway_type     = "FILE_S3"

  # Use the EC2 instance's private IP for activation
  activation_key = aws_storagegateway_gateway.file_gateway.activation_key
  gateway_ip_address = aws_instance.storage_gateway.private_ip

  depends_on = [
    aws_instance.storage_gateway,
    aws_volume_attachment.cache_disk_attachment
  ]
}

# Configure cache disk
resource "aws_storagegateway_cache" "cache" {
  disk_id     = aws_ebs_volume.cache_disk.id
  gateway_arn = aws_storagegateway_gateway.file_gateway.arn

  depends_on = [aws_volume_attachment.cache_disk_attachment]
}

# S3 Bucket for Storage Gateway
resource "aws_s3_bucket" "gateway_bucket" {
  bucket = var.s3_bucket_name

  tags = {
    Name        = var.s3_bucket_name
    Environment = var.environment
    Purpose     = "StorageGateway"
  }
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "gateway_bucket_versioning" {
  bucket = aws_s3_bucket.gateway_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "gateway_bucket_encryption" {
  bucket = aws_s3_bucket.gateway_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "gateway_bucket_pab" {
  bucket = aws_s3_bucket.gateway_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "gateway_bucket_lifecycle" {
  bucket = aws_s3_bucket.gateway_bucket.id

  rule {
    id     = "storage_gateway_lifecycle"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# S3 Bucket Notification Configuration (optional - for monitoring)
resource "aws_s3_bucket_notification" "gateway_bucket_notification" {
  bucket = aws_s3_bucket.gateway_bucket.id

  # Optional: Add CloudWatch Events or SNS notifications here
  depends_on = [aws_s3_bucket.gateway_bucket]
}

# NFS File Share
resource "aws_storagegateway_nfs_file_share" "nfs_share" {
  client_list  = [data.aws_vpc.selected.cidr_block]
  gateway_arn  = aws_storagegateway_gateway.file_gateway.arn
  location_arn = aws_s3_bucket.gateway_bucket.arn
  role_arn     = aws_iam_role.storage_gateway_role.arn

  default_storage_class = "S3_STANDARD"
  file_share_name       = "nfs-share"
  guess_mime_type_enabled = true
  read_only               = false
  requester_pays          = false

  nfs_file_share_defaults {
    directory_mode = "0755"
    file_mode      = "0644"
    group_id       = 65534
    owner_id       = 65534
  }

  depends_on = [
    aws_storagegateway_cache.cache
  ]
}

# Outputs
output "gateway_ip" {
  description = "Private IP address of the Storage Gateway"
  value       = aws_instance.storage_gateway.private_ip
}

output "gateway_public_ip" {
  description = "Public IP address of the Storage Gateway (if assigned)"
  value       = aws_instance.storage_gateway.public_ip
}

output "nfs_mount_command" {
  description = "Command to mount the NFS share"
  value       = "sudo mount -t nfs -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 ${aws_instance.storage_gateway.private_ip}:/${aws_storagegateway_nfs_file_share.nfs_share.file_share_name} /mnt/nfs"
}

output "gateway_arn" {
  description = "ARN of the Storage Gateway"
  value       = aws_storagegateway_gateway.file_gateway.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.gateway_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.gateway_bucket.arn
}

output "s3_bucket_region" {
  description = "Region of the S3 bucket"
  value       = aws_s3_bucket.gateway_bucket.region
}

output "nfs_file_share_arn" {
  description = "ARN of the NFS file share"
  value       = aws_storagegateway_nfs_file_share.nfs_share.arn
}

output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}
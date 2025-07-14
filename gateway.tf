# Provider configuration - Oregon region
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

# Variables
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for subnets"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

variable "key_pair_name" {
  description = "EC2 Key Pair name for SSH access (optional)"
  type        = string
  default     = ""
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

# VPC Resources
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.gateway_name}-vpc"
    Environment = var.environment
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.gateway_name}-igw"
    Environment = var.environment
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.gateway_name}-public-${count.index + 1}"
    Environment = var.environment
    Type        = "Public"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name        = "${var.gateway_name}-private-${count.index + 1}"
    Environment = var.environment
    Type        = "Private"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name        = "${var.gateway_name}-nat-eip"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateway
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name        = "${var.gateway_name}-nat"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.main]
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.gateway_name}-public-rt"
    Environment = var.environment
  }
}

# Route Table for Private Subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name        = "${var.gateway_name}-private-rt"
    Environment = var.environment
  }
}

# Route Table Associations - Public
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route Table Associations - Private
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# VPC Endpoints for S3 (reduces NAT Gateway costs)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name        = "${var.gateway_name}-s3-endpoint"
    Environment = var.environment
  }
}

# VPC Endpoint for Storage Gateway (reduces internet egress costs)
resource "aws_vpc_endpoint" "storagegateway" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.storagegateway"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.gateway_name}-sg-endpoint"
    Environment = var.environment
  }
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoint" {
  name        = "${var.gateway_name}-vpc-endpoint-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.gateway_name}-vpc-endpoint-sg"
    Environment = var.environment
  }
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
  vpc_id      = aws_vpc.main.id

  # NFS traffic
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Storage Gateway activation
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Storage Gateway management
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # SSH access (optional, for troubleshooting)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Storage Gateway internal communication
  ingress {
    from_port   = 1026
    to_port     = 1028
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
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
  id = aws_vpc.main.id
}

# Data sources
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
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
  availability_zone = "${data.aws_region.current.name}a" # us-west-2a
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
  ami                         = data.aws_ami.storage_gateway.id
  instance_type               = var.instance_type
  key_name                    = var.key_pair_name != "" ? var.key_pair_name : null
  vpc_security_group_ids      = [aws_security_group.storage_gateway.id]
  subnet_id                   = aws_subnet.public[0].id # Temporarily public for activation
  associate_public_ip_address = true                    # Assign public IP
  iam_instance_profile        = aws_iam_instance_profile.storage_gateway_profile.name

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

# IAM Role for Bastion Host (SSM access)
resource "aws_iam_role" "bastion_role" {
  name = "${var.gateway_name}-bastion-role"

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

# Attach SSM managed policy to bastion role
resource "aws_iam_role_policy_attachment" "bastion_ssm_policy" {
  role       = aws_iam_role.bastion_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance Profile for Bastion
resource "aws_iam_instance_profile" "bastion_profile" {
  name = "${var.gateway_name}-bastion-profile"
  role = aws_iam_role.bastion_role.name
}

# Bastion Host for accessing private resources
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  key_name                    = var.key_pair_name != "" ? var.key_pair_name : null
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.bastion_profile.name

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y curl
  EOF
  )

  tags = {
    Name        = "${var.gateway_name}-bastion"
    Environment = var.environment
  }
}

# Security Group for Bastion Host
resource "aws_security_group" "bastion" {
  name        = "${var.gateway_name}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = aws_vpc.main.id

  # SSH access from anywhere (restrict this in production)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.gateway_name}-bastion-sg"
    Environment = var.environment
  }
}

# Get Amazon Linux AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
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

    filter {
      prefix = ""
    }

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

# Storage Gateway - Will be activated manually after deployment
# Note: Replace ACTIVATION_KEY_HERE with fresh key from curl command
resource "aws_storagegateway_gateway" "file_gateway" {
  gateway_name     = var.gateway_name
  gateway_timezone = "GMT"
  gateway_type     = "FILE_S3"
  activation_key   = "ACTIVATION_KEY_HERE" # Replace with fresh key tomorrow

  depends_on = [
    aws_instance.storage_gateway,
    aws_volume_attachment.cache_disk_attachment
  ]
}

# Configure cache disk
resource "aws_storagegateway_cache" "cache" {
  disk_id     = "/dev/xvdf"
  gateway_arn = aws_storagegateway_gateway.file_gateway.arn

  depends_on = [
    aws_volume_attachment.cache_disk_attachment,
    aws_storagegateway_gateway.file_gateway
  ]
}

# NFS File Share
resource "aws_storagegateway_nfs_file_share" "nfs_share" {
  client_list  = [var.vpc_cidr]
  gateway_arn  = aws_storagegateway_gateway.file_gateway.arn
  location_arn = aws_s3_bucket.gateway_bucket.arn
  role_arn     = aws_iam_role.storage_gateway_role.arn

  default_storage_class   = "S3_STANDARD"
  file_share_name         = "nfs-share"
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
# resource "aws_storagegateway_cache" "cache" {
#   disk_id     = "/dev/xvdf"  # Update to match the attached device
#   gateway_arn = aws_storagegateway_gateway.file_gateway.arn
#
#   depends_on = [
#     aws_volume_attachment.cache_disk_attachment,
#     aws_storagegateway_gateway.file_gateway
#   ]
# }

# NFS File Share - Uncomment after gateway is activated
# resource "aws_storagegateway_nfs_file_share" "nfs_share" {
#   client_list  = [var.vpc_cidr]
#   gateway_arn  = aws_storagegateway_gateway.file_gateway.arn
#   location_arn = aws_s3_bucket.gateway_bucket.arn
#   role_arn     = aws_iam_role.storage_gateway_role.arn
#
#   default_storage_class = "S3_STANDARD"
#   file_share_name       = "nfs-share"
#   guess_mime_type_enabled = true
#   read_only               = false
#   requester_pays          = false
#
#   nfs_file_share_defaults {
#     directory_mode = "0755"
#     file_mode      = "0644"
#     group_id       = 65534
#     owner_id       = 65534
#   }
#
#   depends_on = [
#     aws_storagegateway_cache.cache
#   ]
# }

# Outputs
output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ip" {
  description = "Public IP of the NAT Gateway"
  value       = aws_eip.nat.public_ip
}

output "bastion_ip" {
  description = "Public IP of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "gateway_ip" {
  description = "Private IP address of the Storage Gateway"
  value       = aws_instance.storage_gateway.private_ip
}

output "manual_activation_steps" {
  description = "Steps to manually activate the Storage Gateway"
  value       = <<-EOF
    1. SSH to bastion host: ssh -i ~/.ssh/${var.key_pair_name != "" ? var.key_pair_name : "your-key"}.pem ec2-user@${aws_instance.bastion.public_ip}
    2. Get activation key: curl "http://${aws_instance.storage_gateway.private_ip}/?activationRegion=us-west-2"
    3. Use the activation key in AWS console or uncomment the gateway resource in Terraform
    
    Storage Gateway IP: ${aws_instance.storage_gateway.private_ip}
    Region: us-west-2
  EOF
}

output "gateway_public_ip" {
  description = "Public IP address of the Storage Gateway (if assigned)"
  value       = aws_instance.storage_gateway.public_ip
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.gateway_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.gateway_bucket.arn
}

output "nfs_mount_command" {
  description = "Command to mount the NFS share"
  value       = "sudo mount -t nfs -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 ${aws_instance.storage_gateway.private_ip}:/${aws_storagegateway_nfs_file_share.nfs_share.file_share_name} /mnt/nfs"
}

output "gateway_arn" {
  description = "ARN of the Storage Gateway"
  value       = aws_storagegateway_gateway.file_gateway.arn
}

output "nfs_file_share_arn" {
  description = "ARN of the NFS file share"
  value       = aws_storagegateway_nfs_file_share.nfs_share.arn
}

output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}
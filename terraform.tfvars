# Example terraform.tfvars file for Oregon region (us-west-2)
# Copy this to terraform.tfvars and update with your values

# Network Configuration
vpc_cidr           = "10.0.0.0/16"                # VPC CIDR block
availability_zones = ["us-west-2a", "us-west-2b"] # AZs for subnets

# EC2 Configuration
key_pair_name   = "{{insert key name}}" # Leave empty if no SSH access needed
instance_type   = "m5.xlarge"        # Adjust based on performance needs
cache_disk_size = 150                # Cache disk size in GB

# Storage Gateway Configuration
gateway_name   = "oregon-file-gateway"
s3_bucket_name = "my-oregon-storage-gateway-bucket-12345" # Must be globally unique

# Environment
environment = "dev" # dev, staging, prod
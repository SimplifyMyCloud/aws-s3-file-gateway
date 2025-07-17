# AWS Storage Gateway File Gateway - Oregon Region

This Terraform configuration deploys an AWS Storage Gateway File Gateway in the Oregon region (us-west-2) with a dedicated S3 bucket for NFS access.

## Architecture

```
Oregon Region (us-west-2)
├── VPC (10.0.0.0/16)
│   ├── Public Subnets (10.0.0.0/24, 10.0.1.0/24)
│   │   ├── Internet Gateway
│   │   └── NAT Gateway
│   ├── Private Subnets (10.0.10.0/24, 10.0.11.0/24)
│   │   └── EC2 Instance (Storage Gateway)
│   │       ├── Security Group (NFS, HTTP, HTTPS)
│   │       └── EBS Cache Volume (150GB)
│   ├── VPC Endpoints
│   │   ├── S3 Gateway Endpoint
│   │   └── Storage Gateway Interface Endpoint
│   └── S3 Bucket (Oregon)
│       ├── Server-side Encryption
│       ├── Versioning Enabled
│       ├── Public Access Blocked
│       └── Lifecycle Rules
└── NFS File Share
    └── Accessible from VPC CIDR (10.0.0.0/16)
```

## Prerequisites

1. **AWS CLI configured** with appropriate credentials
2. **Terraform installed** (version 1.0+)
3. **EC2 Key Pair** created in Oregon region
4. **Proper IAM permissions** for creating VPC and Storage Gateway resources

## Features

### **Complete Infrastructure**
- **VPC with public/private subnets** across multiple AZs
- **NAT Gateway** for internet access from private subnets
- **VPC Endpoints** for S3 and Storage Gateway (reduced egress costs)
- **Security Groups** with least-privilege access

### **Cost Optimization**
- **VPC Endpoints** reduce NAT Gateway data transfer costs
- **S3 Lifecycle rules** automatically tier data to cheaper storage
- **Intelligent subnet design** minimizes cross-AZ traffic

## S3 Bucket Features

The S3 bucket is configured with enterprise-grade features:

- **Server-side encryption** (AES256)
- **Versioning enabled** for data protection
- **Public access blocked** for security
- **Lifecycle rules** to optimize costs:
  - 30 days → Standard-IA
  - 90 days → Glacier
  - 365 days → Deep Archive
- **Automatic cleanup** of old versions after 90 days

## Quick Start

1. **Clone/download** the Terraform files
2. **Copy example variables:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```
3. **Edit terraform.tfvars** with your values
4. **Deploy:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## Configuration Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `availability_zones` | AZs for subnets | `["us-west-2a", "us-west-2b"]` |
| `key_pair_name` | EC2 Key Pair name | Required |
| `s3_bucket_name` | S3 bucket name (globally unique) | Required |
| `gateway_name` | Storage Gateway name | `file-gateway` |
| `instance_type` | EC2 instance type | `m5.xlarge` |
| `cache_disk_size` | Cache disk size in GB | `150` |
| `environment` | Environment tag | `dev` |

## Instance Sizing Recommendations

| Use Case | Instance Type | Cache Size | Notes |
|----------|---------------|------------|-------|
| Development | `m5.large` | 150GB | Minimal workload |
| Production | `m5.xlarge` | 300GB | Balanced performance |
| High Performance | `m5.2xlarge` | 500GB+ | Heavy workload |

## Security Configuration

- **VPC-only access**: No public internet access
- **Security Group**: Restricts access to VPC CIDR
- **IAM Role**: Minimal required permissions
- **EBS Encryption**: All volumes encrypted
- **S3 Security**: Public access blocked

## NFS Mount Instructions

After deployment, use the provided mount command:

```bash
# Linux/Unix systems
sudo mount -t nfs -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 \
  <gateway-ip>:/nfs-share /mnt/nfs

# Windows (with NFS Client feature enabled)
mount -o rsize=1048576,wsize=1048576 \\<gateway-ip>\nfs-share Z:
```

## Monitoring & Troubleshooting

### CloudWatch Metrics
The Storage Gateway automatically publishes metrics to CloudWatch:
- `CacheHitPercent`
- `CachePercentUsed`
- `ReadBytes`/`WriteBytes`
- `FilesFailingUpload`

### Common Issues
1. **Gateway not activating**: Check security group rules
2. **Poor performance**: Increase cache disk size or instance type
3. **Connection issues**: Verify NFS client configuration

## Cost Optimization

- **S3 Lifecycle rules** automatically move data to cheaper storage
- **Cache sizing**: Right-size based on working set
- **Instance scheduling**: Stop non-production instances when not needed

## Cleanup

To destroy all resources:
```bash
terraform destroy
```

⚠️ **Warning**: This will delete the S3 bucket and all data. Ensure you have backups.

## Support

For AWS Storage Gateway specific issues, refer to:
- [AWS Storage Gateway User Guide](https://docs.aws.amazon.com/storagegateway/)
- [AWS Storage Gateway Troubleshooting](https://docs.aws.amazon.com/storagegateway/latest/userguide/troubleshooting-common.html)

## Regional Considerations

This configuration creates a complete infrastructure stack in Oregon region (us-west-2):
- **Multi-AZ deployment** for high availability
- **VPC Endpoints** to minimize internet egress costs
- **S3 bucket** created in us-west-2 for optimal performance
- **NAT Gateway** for secure internet access from private subnets
- **Optimized for west coast latency** and AWS Oregon region features

```
# Alternative approach - Create gateway without auto-activation
# Uncomment this section if automatic activation continues to fail

# resource "aws_storagegateway_gateway" "file_gateway" {
#   gateway_name       = var.gateway_name
#   gateway_timezone   = "GMT"
#   gateway_type       = "FILE_S3"
#   
#   # Manual activation - get key from instance after it's running
#   # activation_key = "ACTIVATION_KEY_HERE"  # Get this manually
#   
#   depends_on = [
#     aws_instance.storage_gateway,
#     aws_volume_attachment.cache_disk_attachment
#   ]
# }

# Manual activation steps (if needed):
# 1. Wait for instance to be running
# 2. Get activation key: 
#    curl "http://${INSTANCE_IP}/?activationRegion=us-west-2"
# 3. Add the activation key to the resource above
# 4. Run terraform apply again
```

---

# AWS Storage Gateway Deployment Guide

## Pre-Flight Checklist ✈️

### Prerequisites Confirmed ✅
- AWS CLI configured with `smc-dev-aws-keyz` key pair
- Session Manager plugin installed via Homebrew
- Terraform files ready in current directory
- Region: Oregon (us-west-2)

## Step-by-Step Deployment

### 1. Initial Infrastructure Deployment
```bash
# Clean start
terraform init
terraform plan
terraform apply --auto-approve
```

**Expected time:** ~8-10 minutes

### 2. Wait for Storage Gateway Initialization
```bash
# Give the Storage Gateway time to fully boot
echo "Waiting 10 minutes for Storage Gateway to initialize..."
sleep 600
```

### 3. Get Activation Key via Session Manager
```bash
# Connect to bastion
BASTION_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=*bastion*" "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text)

aws ssm start-session --target $BASTION_ID
```

From bastion session:
```bash
# Get Storage Gateway IP
GATEWAY_IP=$(terraform output -raw gateway_ip)

# Test connectivity
ping -c 3 $GATEWAY_IP

# Get activation key (look for redirect URL with activationKey parameter)
curl -v "http://$GATEWAY_IP/?activationRegion=us-west-2"
```

### 4. Update Terraform with Activation Key
```bash
# Exit bastion session
exit

# Edit the terraform file to replace ACTIVATION_KEY_HERE with actual key
# Example: QA1VN-R96QT-FPQ10-FJU7L-OH79G
```

### 5. Complete Storage Gateway Setup
```bash
# Apply with activation key
terraform apply --auto-approve
```

### 6. Verify NFS Mount Command
```bash
# Get mount command for Windows
terraform output nfs_mount_command
```

## Key Files Status ✅

### Terraform Configuration
- ✅ **VPC with public/private subnets** across 2 AZs
- ✅ **NAT Gateway** for internet access
- ✅ **VPC Endpoints** (S3 Gateway, Storage Gateway Interface)
- ✅ **Bastion host** with SSM access in public subnet
- ✅ **Storage Gateway** in private subnet with cache disk
- ✅ **S3 bucket** with encryption, versioning, lifecycle rules
- ✅ **Security groups** with appropriate access
- ✅ **IAM roles** with minimal required permissions

### Variables Configured
```hcl
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-west-2a", "us-west-2b"]
key_pair_name      = "smc-dev-aws-keyz"
gateway_name       = "oregon-file-gateway"
s3_bucket_name     = "my-oregon-storage-gateway-bucket-12345"
instance_type      = "m5.xlarge"
cache_disk_size    = 150
environment        = "dev"
```

## Expected Outputs After Completion

```bash
bastion_ip                = "XX.XX.XX.XX"
deployment_region         = "us-west-2"
gateway_arn              = "arn:aws:storagegateway:us-west-2:ACCOUNT:gateway/sgw-XXXXXXXX"
gateway_ip               = "10.0.X.X"
manual_activation_steps   = "SSH and curl instructions"
nat_gateway_ip           = "XX.XX.XX.XX"
nfs_file_share_arn       = "arn:aws:storagegateway:us-west-2:ACCOUNT:share/share-XXXXXXXX"
nfs_mount_command        = "sudo mount -t nfs ..."
private_subnet_ids       = ["subnet-XXXXX", "subnet-XXXXX"]
public_subnet_ids        = ["subnet-XXXXX", "subnet-XXXXX"]
s3_bucket_arn           = "arn:aws:s3:::my-oregon-storage-gateway-bucket-12345"
s3_bucket_name          = "my-oregon-storage-gateway-bucket-12345"
vpc_cidr                = "10.0.0.0/16"
vpc_id                  = "vpc-XXXXX"
```

## Troubleshooting Quick Reference

### If Storage Gateway not responding:
```bash
# Wait longer (up to 15 minutes for cold start)
# Check instance status
aws ec2 describe-instance-status --instance-ids $GATEWAY_ID

# Restart if needed
aws ec2 reboot-instances --instance-ids $GATEWAY_ID
```

### If activation key invalid:
- Keys expire in ~10 minutes
- Get fresh key with same curl command
- Update terraform and apply immediately

### If Session Manager fails:
- Check bastion has SSM role attached
- Wait 5 minutes and retry
- Restart bastion if needed

## Success Criteria ✅

After completion, you should have:
1. ✅ VPC with proper networking
2. ✅ Storage Gateway activated and healthy
3. ✅ NFS share accessible from VPC
4. ✅ S3 bucket with files appearing when written to NFS
5. ✅ Working mount command for Windows server

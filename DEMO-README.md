# AWS S3 File Gateway - Demo Deployment

Quick deployment script for AWS S3 File Gateway demo/POC environments.

## Quick Start

1. **Configure AWS CLI**: `aws configure`
2. **Customize settings**: `cp terraform.tfvars.example terraform.tfvars` and edit
3. **Deploy**: `./deploy.sh`
4. **Follow the output instructions** to activate the gateway and create file shares

## What Gets Deployed

- **Storage Gateway EC2 instance** (m5.xlarge) with 150GB cache disk
- **Windows demo instance** (t3.medium) with NFS client pre-installed
- **S3 bucket** with encryption for file storage
- **Security groups** allowing NFS, RDP, and SSH access
- **IAM roles** for Storage Gateway S3 access

## Usage

```bash
# Deploy everything
./deploy.sh

# Check what will be created
terraform plan

# Deploy manually
terraform apply

# Destroy everything
terraform destroy
```

## Manual Steps After Deployment

1. **Activate Storage Gateway**:
   - Visit the activation URL from the output
   - Choose "FILE_S3" gateway type
   - Use the S3 bucket name from output

2. **Create NFS File Share**:
   - AWS Console → Storage Gateway → Your Gateway → File shares → Create
   - Use the S3 bucket from deployment
   - Use the IAM role from deployment

3. **Connect to Windows Instance**:
   - RDP to the Windows instance IP
   - Get password using the command from output
   - Run the demo script from desktop shortcut

## Configuration

Edit `terraform.tfvars`:

```hcl
demo_name = "your-demo-name"
s3_bucket_name = "your-unique-bucket-name"
key_pair_name = "your-ec2-key-pair"
allowed_cidr = "0.0.0.0/0"  # Restrict for security
```

## Security Notes

⚠️ **This is for demo/POC only!** 
- Uses default VPC
- Opens NFS to 0.0.0.0/0 by default
- RDP open to internet
- No VPC endpoints or advanced security

## Cleanup

```bash
terraform destroy
```

## Files

- `deploy-file-gateway.tf` - Main Terraform configuration
- `deploy.sh` - Deployment script
- `terraform.tfvars.example` - Configuration template

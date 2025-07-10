# AWS Storage Gateway File Gateway - Oregon Region

This Terraform configuration deploys an AWS Storage Gateway File Gateway in the Oregon region (us-west-2) with a dedicated S3 bucket for NFS access.

## Architecture

```
VPC (us-west-2)
├── Private Subnet
│   └── EC2 Instance (Storage Gateway)
│       ├── Security Group (NFS, HTTP, HTTPS)
│       └── EBS Cache Volume (150GB)
├── S3 Bucket (Oregon)
│   ├── Server-side Encryption
│   ├── Versioning Enabled
│   ├── Public Access Blocked
│   └── Lifecycle Rules
└── NFS File Share
    └── Accessible from VPC CIDR
```

## Prerequisites

1. **AWS CLI configured** with appropriate credentials
2. **Terraform installed** (version 1.0+)
3. **Existing VPC and private subnet** in Oregon region
4. **EC2 Key Pair** created in Oregon region
5. **Proper IAM permissions** for creating Storage Gateway resources

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
| `vpc_id` | VPC ID in Oregon region | Required |
| `subnet_id` | Private subnet ID | Required |
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

This configuration is specifically designed for Oregon region (us-west-2):
- S3 bucket created in us-west-2
- EC2 instance in us-west-2a availability zone
- Optimized for west coast latency
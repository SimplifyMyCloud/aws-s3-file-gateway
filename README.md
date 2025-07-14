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
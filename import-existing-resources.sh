#!/bin/bash

# Script to import existing AWS resources into Terraform state
# Run this script after reviewing the existing-resources.tf file

echo "Starting import of existing AWS resources..."

# Import S3 bucket
echo "Importing S3 bucket..."
terraform import aws_s3_bucket.gateway_bucket smc-gateway-bucket-test-001

# Import S3 bucket encryption
echo "Importing S3 bucket encryption..."
terraform import aws_s3_bucket_server_side_encryption_configuration.gateway_bucket_encryption smc-gateway-bucket-test-001

# Import Storage Gateway
echo "Importing Storage Gateway..."
terraform import aws_storagegateway_gateway.file_gateway arn:aws:storagegateway:us-west-2:288782039514:gateway/sgw-93C3A8FA

# Import NFS file share
echo "Importing NFS file share..."
terraform import aws_storagegateway_nfs_file_share.nfs_share arn:aws:storagegateway:us-west-2:288782039514:share/share-43F1D627

# Import EC2 instance
echo "Importing EC2 instance..."
terraform import aws_instance.storage_gateway i-08d75b4932af35755

# Import EBS volume
echo "Importing EBS volume..."
terraform import aws_ebs_volume.cache_disk vol-0706eb089af70796f

# Import volume attachment
echo "Importing volume attachment..."
terraform import aws_volume_attachment.cache_disk_attachment /dev/sdb:vol-0706eb089af70796f:i-08d75b4932af35755

echo "Import completed. Please run 'terraform plan' to see any configuration drift."
echo ""
echo "Note: You may need to update the existing-resources.tf file with actual AMI IDs and other details."
echo "Run 'aws ec2 describe-instances --instance-ids i-08d75b4932af35755' to get the actual AMI ID."
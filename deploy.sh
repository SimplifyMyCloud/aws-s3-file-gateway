#!/bin/bash

# AWS S3 File Gateway Demo Deployment Script
# This script automates the deployment of an AWS S3 File Gateway for demo/POC purposes

set -e

echo "=========================================="
echo "AWS S3 File Gateway Demo Deployment"
echo "=========================================="
echo ""

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "Error: Terraform is not installed. Please install Terraform first."
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo "Error: AWS CLI is not configured. Please run 'aws configure' first."
    exit 1
fi

echo "✓ Terraform found"
echo "✓ AWS CLI configured"
echo ""

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo "Creating terraform.tfvars from example..."
    cp terraform.tfvars.example terraform.tfvars
    echo "⚠️  Please edit terraform.tfvars with your specific values (especially key_pair_name)"
    echo "   Then run this script again."
    exit 0
fi

echo "✓ terraform.tfvars found"
echo ""

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

echo ""
echo "Planning deployment..."
terraform plan -out=deployment.tfplan

echo ""
echo "=========================================="
echo "Ready to deploy! This will create:"
echo "- Storage Gateway EC2 instance (m5.xlarge)"
echo "- Windows demo EC2 instance (t3.medium)"
echo "- S3 bucket with encryption"
echo "- Security groups and IAM roles"
echo "- EBS volume for cache (150GB)"
echo "=========================================="
echo ""

read -p "Continue with deployment? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Deploying infrastructure..."
    terraform apply deployment.tfplan
    
    echo ""
    echo "=========================================="
    echo "Deployment completed successfully!"
    echo "=========================================="
    echo ""
    echo "Next steps will be displayed in the output above."
    echo "Look for the 'deployment_summary' output for detailed instructions."
    echo ""
    echo "To destroy this demo environment later, run:"
    echo "  terraform destroy"
    echo ""
else
    echo "Deployment cancelled."
    rm -f deployment.tfplan
fi
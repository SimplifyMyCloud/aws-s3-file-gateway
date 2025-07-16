#!/bin/bash
# User data script for Storage Gateway EC2 instance

# Update system
yum update -y

# Set timezone
timedatectl set-timezone GMT

# Configure Storage Gateway
# The Storage Gateway AMI will handle most of the configuration automatically
# Additional configuration can be done through the AWS Console or CLI after activation

# Log startup
echo "Storage Gateway instance started at $(date)" >> /var/log/storage-gateway-startup.log

# Wait for network to be ready
sleep 30

# The gateway will be activated via Terraform using the activation key
echo "Gateway ready for activation" >> /var/log/storage-gateway-startup.log
#!/bin/bash
echo "Getting fresh activation key..."
BASTION_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=*bastion*" "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].InstanceId' --output text)

# Get activation key via Session Manager
echo "Connect to bastion and run: curl http://10.0.0.153/"
echo "Then paste the activation key here:"
read -p "Activation Key: " ACTIVATION_KEY

# Update terraform file
sed -i.bak "s/activation_key.*=.*/activation_key = \"$ACTIVATION_KEY\"/" gateway.tf

# Apply immediately
terraform apply --auto-approve

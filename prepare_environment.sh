#!/bin/bash

# Create directory for SSH keys if it doesn't exist
mkdir -p ./ssh_keys
# Generate SSH key if it doesn't exist
if [ ! -f "./ssh_keys/docker_rsa" ]; then
    ssh-keygen -t rsa -b 4096 -f ./ssh_keys/docker_rsa -q -N ""
    echo "SSH keys generated."
else
    echo "SSH keys already exist."
fi

# UFW configuration
# Note: Make sure Docker's default forwarding policy is set to DROP to prevent bypassing UFW rules.
# sudo nano /etc/default/docker and ensure that DOCKER_OPTS="--iptables=false" is set.

# Allow SSH (if not already allowed)
sudo ufw allow 22/tcp # Allow SSH
# sudo ufw allow 22
# Custom ports for NGINX to avoid conflict with the existing server
sudo ufw allow 80
sudo ufw allow 443
sudo ufw allow 8080
sudo ufw allow 8443
# For VNC access - adjust the port range as needed
# sudo ufw allow 5900
sudo ufw allow 5900:5910/tcp # Allow VNC

# Reload UFW to apply changes
sudo ufw reload
echo "UFW has been configured to allow necessary ports."

# VNC password setup should be handled individually in Dockerfiles or via Docker secrets for security.

echo "Environment preparation completed."

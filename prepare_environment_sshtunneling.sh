#!/bin/bash

# Prompt the user to specify which server is being set up
echo "Is this the Remote Server or the Main Server? (Enter 'Remote' or 'Main')"
read SERVER_TYPE

# Convert user input to lowercase for consistency
SERVER_TYPE=$(echo "$SERVER_TYPE" | tr '[:upper:]' '[:lower:]')

if [ "$SERVER_TYPE" == "main" ]; then
    # Main server setup

    # Step 1: Install and configure SSH server on the Main server

    # Install SSH server if not already installed
    echo "Checking if SSH server is installed..."
    if ! dpkg -l | grep -q openssh-server; then
        echo "SSH server not found. Installing openssh-server..."
        sudo apt-get update
        sudo apt-get install -y openssh-server
    else
        echo "SSH server is already installed."
    fi

    # Ensure SSH server is running
    echo "Ensuring SSH server is running..."
    sudo systemctl enable ssh
    sudo systemctl start ssh

    # No further action needed on the Main server in this script

elif [ "$SERVER_TYPE" == "remote" ]; then
    # Remote server setup

    # Configure SSH for key-based authentication (Optional but recommended)
    # Generate SSH key pair on the Remote server (if not already generated)
    echo "Generating SSH key pair for secure communication..."
    if [ ! -f ~/.ssh/id_rsa ]; then
        ssh-keygen -q -N "" -f ~/.ssh/id_rsa
        echo "SSH key pair generated."
    else
        echo "SSH key pair already exists."
    fi

    # Prompt for the Main server's IP address
    echo "Enter the Main server's IP address:"
    read MAIN_SERVER_IP

    # Copy the public key to the Main server
    echo "Copying public key to the Main server for passwordless authentication..."
    ssh-copy-id user@$MAIN_SERVER_IP

    # Step 2: Set up the SSH tunnel from the Remote server to the Main server
    # This forwards port 80 on the Remote server to port 8000 on the Main server
    echo "Setting up reverse SSH tunnel..."
    SSH_TUNNEL_PORT=8000  # Replace with actual tunnel port if different
    SSH_REMOTE_PORT=80    # Replace with actual remote port if different
    ssh -R ${SSH_TUNNEL_PORT}:localhost:${SSH_REMOTE_PORT} user@$MAIN_SERVER_IP

    # Install autossh for automatic SSH tunnel maintenance
    echo "Installing autossh for automatic SSH tunnel maintenance..."
    sudo apt-get install -y autossh

    # Run autossh to maintain the SSH tunnel in the background
    echo "Running autossh to maintain SSH tunnel..."
    autossh -M 0 -f -N -R ${SSH_TUNNEL_PORT}:localhost:${SSH_REMOTE_PORT} user@$MAIN_SERVER_IP

else
    echo "Invalid input. Please run the script again and enter 'Remote' or 'Main'."
    exit 1
fi

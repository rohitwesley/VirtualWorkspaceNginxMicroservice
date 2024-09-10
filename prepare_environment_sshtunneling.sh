#!/bin/bash

# Prompt the user to specify which server is being set up
echo "Is this the Remote Server or the Main Server? (Enter 'Remote' or 'Main')"
read SERVER_TYPE

# Convert user input to lowercase for consistency
SERVER_TYPE=$(echo "$SERVER_TYPE" | tr '[:upper:]' '[:lower:]')
NGINX_CONF="nginx.conf"

if [ "$SERVER_TYPE" == "main" ]; then
    # Main server setup

    # Step 1: Check and install SSH server
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
    # sudo systemctl enable ssh
    # sudo systemctl start ssh

    # List all available users
    echo "Available users on the system:"
    cut -d: -f1 /etc/passwd | sort

    # Ask user to select one of the existing users or create a new one
    echo "Enter the username to use for SSH access or type 'new' to create a new user:"
    read SSH_USER

    if [ "$SSH_USER" == "new" ]; then
        echo "Enter new username for SSH access:"
        read NEW_SSH_USER
        sudo adduser --disabled-password --gecos "" $NEW_SSH_USER
        SSH_USER=$NEW_SSH_USER
        echo "New user created for SSH access: $SSH_USER"
    else
        if grep -q "^$SSH_USER:" /etc/passwd; then
            echo "Using existing user: $SSH_USER"
        else
            echo "User does not exist. Exiting script."
            exit 1
        fi
    fi

    # Automatically fetch the public IP address of the main server
    MAIN_SERVER_IP=$(curl -s http://icanhazip.com)
    echo "Detected Main Server IP: $MAIN_SERVER_IP"
    
    # Completion message
    echo "Main server setup complete. Use SSH user info '$SSH_USER@$MAIN_SERVER_IP' for setting up the remote server."
    echo "Proceed to configure the remote server. Use the SSH user information where required to establish the SSH tunnel."

    echo "Are you ready to continue with the docker build bang the keyboard and hit Enter."
    read

    # Ask for the custom route for SSH tunneling
    echo "Enter the route to handle SSH tunneling (e.g., '/mobile/'): "
    read SSH_ROUTE

    echo "Enter the Local Port on the Main server to forward to (e.g., 8080):"
    read LOCAL_FORWARD_PORT

    # Update NGINX configuration
    sed -i "/# DO NOT REMOVE THIS COMMENT script inserts ssh tunelling here/a \\
        location \/$SSH_ROUTE\/ { \\
            proxy_pass http://localhost:$LOCAL_FORWARD_PORT\/; # Forward to SSH tunnel local port \\
            proxy_set_header Host \$host; \\
            proxy_set_header X-Real-IP \$remote_addr; \\
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; \\
            proxy_set_header X-Forwarded-Proto \$scheme; \\
        }" $NGINX_CONF
    echo "NGINX configuration updated to include SSH tunneling."

    # Restart NGINX Docker container
    echo "Restarting NGINX Docker container..."
    # docker compose up -d --build
    docker compose build --no-cache && docker compose up --force-recreate -d

    # Restart NGINX to apply the new certificate
    echo "Restart NGINX to apply the new certificate"
    docker cp $NGINX_CONF nginx-microserver:/etc/nginx/nginx.conf
    docker compose restart nginx

    echo "Setup complete. NGINX is running on ports $NGINX_PORT_HTTP and $NGINX_PORT_HTTPS for domain $DOMAIN_NAME with SSL."
    echo "NGINX setup for HTTPS is complete. Verify by accessing https://${DOMAIN_NAME}."

elif [ "$SERVER_TYPE" == "remote" ]; then
    # Remote server setup

    # Check and install SSH client if it's not installed
    echo "Checking if SSH client is installed..."
    if ! command -v ssh >/dev/null 2>&1; then
        echo "SSH client not found. Installing openssh-client..."
        sudo apt-get update
        sudo apt-get install -y openssh-client
    else
        echo "SSH client is already installed."
    fi

    # Generate SSH key pair on the Remote server (if not already generated)
    echo "Generating SSH key pair for secure communication..."
    if [ ! -f ~/.ssh/id_rsa ]; then
        ssh-keygen -q -N "" -f ~/.ssh/id_rsa
        echo "SSH key pair generated."
    else
        echo "SSH key pair already exists."
    fi

    # Prompt for the Main server's IP address
    echo "Enter the IP address of the Main server:"
    read MAIN_SERVER_IP

    # Prompt for the username on the Main server for SSH access
    echo "Enter the username for SSH access on the Main server:"
    read MAIN_SERVER_USER

    # Copy the public key to the Main server for passwordless authentication
    echo "Copying public key to the Main server for passwordless authentication..."
    ssh-copy-id $MAIN_SERVER_USER@$MAIN_SERVER_IP

    # Set up the SSH tunnel from the Remote server to the Main server
    # Ask for the Remote NGINX server port
    echo "Enter the Remote NGINX server port (e.g., 80):"
    read REMOTE_NGINX_PORT

    echo "Enter the Local Port on the Main server to forward to (e.g., 8080):"
    read LOCAL_FORWARD_PORT

    echo "Setting up reverse SSH tunnel from Remote NGINX port $REMOTE_NGINX_PORT to local port $LOCAL_FORWARD_PORT on the Main server..."
    ssh -f -N -T -R $LOCAL_FORWARD_PORT:localhost:$REMOTE_NGINX_PORT $MAIN_SERVER_USER@$MAIN_SERVER_IP

    # Install autossh for automatic SSH tunnel maintenance
    echo "Installing autossh for automatic SSH tunnel maintenance..."
    sudo apt-get install -y autossh

    # Run autossh to maintain the SSH tunnel in the background
    echo "Running autossh to maintain SSH tunnel..."
    autossh -M 0 -f -N -R $LOCAL_FORWARD_PORT:localhost:$REMOTE_NGINX_PORT $MAIN_SERVER_USER@$MAIN_SERVER_IP

else
    echo "Invalid input. Please run the script again and enter 'Remote' or 'Main'."
    exit 1
fi

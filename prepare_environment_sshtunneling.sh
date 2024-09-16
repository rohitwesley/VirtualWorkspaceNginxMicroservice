#!/bin/bash

# Function to detect the operating system
detect_os() {
    OS=$(uname)
    case "$OS" in
        Linux*)
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                OS_TYPE=$ID
            else
                OS_TYPE="unknown"
            fi
            ;;
        Darwin*)
            OS_TYPE="macos"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            OS_TYPE="windows"
            ;;
        *)
            OS_TYPE="unknown"
            ;;
    esac
}

# Function to install packages based on OS
install_package() {
    PACKAGE_NAME=$1
    case "$OS_TYPE" in
        ubuntu|debian)
            if ! dpkg -l | grep -q "$PACKAGE_NAME"; then
                echo "$PACKAGE_NAME not found. Installing..."
                sudo apt-get update
                sudo apt-get install -y "$PACKAGE_NAME"
            else
                echo "$PACKAGE_NAME is already installed."
            fi
            ;;
        fedora|centos|rhel)
            if ! rpm -qa | grep -q "$PACKAGE_NAME"; then
                echo "$PACKAGE_NAME not found. Installing..."
                sudo dnf install -y "$PACKAGE_NAME" || sudo yum install -y "$PACKAGE_NAME"
            else
                echo "$PACKAGE_NAME is already installed."
            fi
            ;;
        macos)
            if ! brew list "$PACKAGE_NAME" >/dev/null 2>&1; then
                echo "$PACKAGE_NAME not found. Installing..."
                brew install "$PACKAGE_NAME"
            else
                echo "$PACKAGE_NAME is already installed."
            fi
            ;;
        windows)
            echo "Package installation on Windows is not automated in this script. Please install $PACKAGE_NAME manually."
            ;;
        *)
            echo "Unsupported OS. Please install $PACKAGE_NAME manually."
            ;;
    esac
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect the operating system
detect_os

# Load environment variables from .env file
set -a
source .env
set +a

NGINX_CONF="nginx.conf"

# Prompt the user to specify which server is being set up
echo "Is this the Remote Server or the Main Server? (Enter 'Remote' or 'Main')"
read SERVER_TYPE

# Convert user input to lowercase for consistency
SERVER_TYPE=$(echo "$SERVER_TYPE" | tr '[:upper:]' '[:lower:]')

if [ "$SERVER_TYPE" == "main" ]; then
    # Main server setup

    # Step 1: Check and install SSH server
    echo "Checking if SSH server is installed..."
    case "$OS_TYPE" in
        ubuntu|debian|fedora|centos|rhel)
            install_package "openssh-server"
            ;;
        macos)
            echo "Enabling SSH server on macOS..."
            sudo systemsetup -setremotelogin on
            ;;
        windows)
            echo "SSH server setup on Windows is not automated in this script. Please enable OpenSSH manually."
            ;;
        *)
            echo "Unsupported OS. Please install SSH server manually."
            exit 1
            ;;
    esac

    # Ensure SSH server is running
    echo "Ensuring SSH server is running..."
    case "$OS_TYPE" in
        ubuntu|debian|fedora|centos|rhel)
            sudo systemctl enable ssh
            sudo systemctl start ssh
            ;;
        macos)
            # SSH server is managed via systemsetup on macOS
            echo "SSH server should now be enabled on macOS."
            ;;
        windows)
            echo "SSH server management on Windows is not automated in this script."
            ;;
        *)
            echo "Unsupported OS. Please ensure SSH server is running."
            ;;
    esac

    # List all available users (Linux only)
    if [[ "$OS_TYPE" == "ubuntu" || "$OS_TYPE" == "debian" || "$OS_TYPE" == "fedora" || "$OS_TYPE" == "centos" || "$OS_TYPE" == "rhel" ]]; then
        echo "Available users on the system:"
        cut -d: -f1 /etc/passwd | sort
    elif [ "$OS_TYPE" == "macos" ]; then
        echo "Available users on the system:"
        dscl . list /Users | sort
    fi

    # Ask user to select one of the existing users or create a new one
    echo "Enter the username (e.g., 'wesley') to use for SSH access or type 'new' to create a new user:"
    read SSH_USER
    SSH_USER=${SSH_USER:-wesley}

    if [ "$SSH_USER" == "new" ]; then
        echo "Enter new username for SSH access:"
        read NEW_SSH_USER
        case "$OS_TYPE" in
            ubuntu|debian|fedora|centos|rhel)
                sudo adduser --disabled-password --gecos "" "$NEW_SSH_USER"
                ;;
            macos)
                sudo sysadminctl -addUser "$NEW_SSH_USER" -disabledPassword
                ;;
            windows)
                echo "User creation on Windows is not automated in this script. Please create the user manually."
                exit 1
                ;;
            *)
                echo "Unsupported OS. Please create the user manually."
                exit 1
                ;;
        esac
        SSH_USER=$NEW_SSH_USER
        echo "New user created for SSH access: $SSH_USER"
    else
        if [[ "$OS_TYPE" == "ubuntu" || "$OS_TYPE" == "debian" || "$OS_TYPE" == "fedora" || "$OS_TYPE" == "centos" || "$OS_TYPE" == "rhel" ]]; then
            if grep -q "^$SSH_USER:" /etc/passwd; then
                echo "Using existing user: $SSH_USER"
            else
                echo "User does not exist. Exiting script."
                exit 1
            fi
        elif [ "$OS_TYPE" == "macos" ]; then
            if dscl . -read /Users/"$SSH_USER" >/dev/null 2>&1; then
                echo "Using existing user: $SSH_USER"
            else
                echo "User does not exist. Exiting script."
                exit 1
            fi
        fi
    fi

    # Completion message
    echo "Main server setup complete. Use SSH user info '$SSH_USER@$DOMAIN_NAME' for setting up the remote server."
    echo "Proceed to configure the remote server. Use the SSH user information where required to establish the SSH tunnel."

    echo "Are you ready to continue with the docker build? If so, press Enter."
    read

    # Ask for the custom route for SSH tunneling
    echo "Enter the route to handle SSH tunneling (e.g., '/mobile/'): "
    read SSH_ROUTE
    SSH_ROUTE=${SSH_ROUTE:-mobile}

    echo "Enter the Local Port on the Main server to forward to (e.g., 8080):"
    read LOCAL_FORWARD_PORT
    LOCAL_FORWARD_PORT=${LOCAL_FORWARD_PORT:-8080}

    # Update NGINX configuration
    # Handle macOS sed compatibility
    if [ "$OS_TYPE" == "macos" ]; then
        sed -i '' "/# DO NOT REMOVE THIS COMMENT script inserts ssh tunelling here/a \\
            location \/$SSH_ROUTE\/ { \\
                proxy_pass http://$SSH_TUNNEL_HOST:$LOCAL_FORWARD_PORT\/; # Forward to SSH tunnel local port \\
                proxy_set_header Host \$host; \\
                proxy_set_header X-Real-IP \$remote_addr; \\
                proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; \\
                proxy_set_header X-Forwarded-Proto \$scheme; \\
            }" "$NGINX_CONF"
    else
        sed -i "/# DO NOT REMOVE THIS COMMENT script inserts ssh tunelling here/a \\
            location \/$SSH_ROUTE\/ { \\
                proxy_pass http://$SSH_TUNNEL_HOST:$LOCAL_FORWARD_PORT\/; # Forward to SSH tunnel local port \\
                proxy_set_header Host \$host; \\
                proxy_set_header X-Real-IP \$remote_addr; \\
                proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; \\
                proxy_set_header X-Forwarded-Proto \$scheme; \\
            }" "$NGINX_CONF"
    fi
    echo "NGINX configuration updated to include SSH tunneling."

    # Restart NGINX Docker container
    echo "Restarting NGINX Docker container..."
    # docker compose up -d --build
    docker compose build --no-cache && docker compose up --force-recreate -d

    # Restart NGINX to apply the new certificate
    echo "Restarting NGINX to apply the new certificate..."
    docker cp "$NGINX_CONF" nginx-microserver:/etc/nginx/nginx.conf
    docker compose restart nginx

    echo "Setup complete. NGINX is running on ports $NGINX_PORT_HTTP and $NGINX_PORT_HTTPS for domain $DOMAIN_NAME with SSL."
    echo "NGINX setup for HTTPS is complete. Verify by accessing https://${DOMAIN_NAME}."

elif [ "$SERVER_TYPE" == "remote" ]; then
    # Remote server setup

    # Check and install SSH client if it's not installed
    echo "Checking if SSH client is installed..."
    if ! command_exists ssh; then
        echo "SSH client not found. Installing..."
        case "$OS_TYPE" in
            ubuntu|debian|fedora|centos|rhel)
                install_package "openssh-client"
                ;;
            macos)
                install_package "openssh"
                ;;
            windows)
                echo "SSH client on Windows is typically available via PowerShell or can be installed through other means."
                ;;
            *)
                echo "Unsupported OS. Please install SSH client manually."
                exit 1
                ;;
        esac
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
    ssh-copy-id "$MAIN_SERVER_USER@$MAIN_SERVER_IP"

    # Ask for the Remote NGINX server port
    echo "Enter the Remote NGINX server port (e.g., 80):"
    read REMOTE_NGINX_PORT

    echo "Enter the Local Port on the Main server to forward to (e.g., 8080):"
    read LOCAL_FORWARD_PORT
    LOCAL_FORWARD_PORT=${LOCAL_FORWARD_PORT:-8080}

    echo "Setting up reverse SSH tunnel from Remote NGINX port $REMOTE_NGINX_PORT to local port $LOCAL_FORWARD_PORT on the Main server..."
    ssh -f -N -T -R "$LOCAL_FORWARD_PORT:localhost:$REMOTE_NGINX_PORT" "$MAIN_SERVER_USER@$MAIN_SERVER_IP"

    # Install autossh for automatic SSH tunnel maintenance
    echo "Installing autossh for automatic SSH tunnel maintenance..."
    install_package "autossh"

    # Run autossh to maintain SSH tunnel
    echo "Running autossh to maintain SSH tunnel..."
    autossh -M 0 -f -N -R "$LOCAL_FORWARD_PORT:localhost:$REMOTE_NGINX_PORT" "$MAIN_SERVER_USER@$MAIN_SERVER_IP"

else
    echo "Invalid input. Please run the script again and enter 'Remote' or 'Main'."
    exit 1
fi

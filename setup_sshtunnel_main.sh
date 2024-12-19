#!/bin/bash

# File: setup_sshtunnel_main.sh

set -e

# Load environment variables from .env file
set -a
source .env
set +a

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

# Detect the operating system
detect_os

# Validate required environment variables
: "${DOMAIN_NAME:?Missing DOMAIN_NAME}"

# Step 1: Install and configure SSH server
echo "Setting up SSH server on the main server..."

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
        exit 1
        ;;
    *)
        echo "Unsupported OS. Please install SSH server manually."
        exit 1
        ;;
esac

# Ensure SSH server is running
echo "Ensuring SSH server is running..."
case "$OS_TYPE" in
    ubuntu|debian)
        sudo systemctl enable ssh
        sudo systemctl start ssh
        ;;
    fedora|centos|rhel)
        sudo systemctl enable sshd
        sudo systemctl start sshd
        ;;
    macos)
        echo "SSH server should now be enabled on macOS."
        ;;
    windows)
        echo "SSH server management on Windows is not automated in this script."
        ;;
    *)
        echo "Unsupported OS. Please ensure SSH server is running."
        ;;
esac

# List all available users (Linux and macOS)
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
echo "SSH server setup complete. Use SSH user info '$SSH_USER@$DOMAIN_NAME' for setting up the remote server."

# Prompt to proceed with SSH tunneling setup
echo "Are you ready to proceed with setting up SSH tunneling? (yes/no)"
read PROCEED
if [[ "$PROCEED" != "yes" ]]; then
    echo "Exiting script."
    exit 0
fi

# Ask for the custom route for SSH tunneling
echo "Enter the route to handle SSH tunneling (e.g., 'mobile' or 'in'): "
read SSH_ROUTE
SSH_ROUTE=${SSH_ROUTE:-mobile}

# Ask for the Local Port on the Main server to forward to
echo "Enter the Local Port on the Main server to forward to (e.g., 8080):"
read LOCAL_FORWARD_PORT
LOCAL_FORWARD_PORT=${LOCAL_FORWARD_PORT:-8080}

# Update NGINX configuration to include the reverse proxy for SSH-tunneled services
echo "Updating NGINX configuration to include reverse proxy for SSH-tunneled services..."

# Use a temporary file to avoid issues with inline editing
TEMP_CONF=$(mktemp)
awk -v route="$SSH_ROUTE" -v port="$LOCAL_FORWARD_PORT" '
    /# DO NOT REMOVE THIS COMMENT script inserts ssh tunnelling here/ {
        print;
        print "        location /" route "/ {";
        print "            proxy_pass http://localhost:" port "/;";
        print "            proxy_set_header Host \$host;";
        print "            proxy_set_header X-Real-IP \$remote_addr;";
        print "            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;";
        print "            proxy_set_header X-Forwarded-Proto \$scheme;";
        print "        }";
        next;
    }
    { print }
' nginx.conf > "$TEMP_CONF"

# Replace the original nginx.conf with the updated one
mv "$TEMP_CONF" nginx.conf

echo "NGINX configuration updated to include reverse proxy for /$SSH_ROUTE."

# Rebuild and restart Docker containers to apply the new configuration
echo "Rebuilding and restarting Docker containers to apply new NGINX configuration..."
docker compose up -d --build
docker compose restart nginx

echo "Nginx restarted with updated reverse proxy configuration."
echo "SSH tunneling setup on the main server is complete."

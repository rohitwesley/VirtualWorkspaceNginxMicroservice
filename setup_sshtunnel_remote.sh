#!/bin/bash

# File: setup_sshtunnel_remote.sh

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect the operating system
detect_os

# Validate required environment variables
: "${DOMAIN_NAME:?Missing DOMAIN_NAME}"
: "${SSH_ROUTE:?Missing SSH_ROUTE}"
: "${LOCAL_FORWARD_PORT:?Missing LOCAL_FORWARD_PORT}"

# Variables
NGINX_CONF="nginx.conf"

# Ask for the Main server's IP address
echo "Enter the IP address of the Main server:"
read MAIN_SERVER_IP

# Ask for the username on the Main server for SSH access
echo "Enter the username for SSH access on the Main server:"
read MAIN_SERVER_USER

# Ensure SSH client is installed
echo "Ensuring SSH client is installed..."
if ! command_exists ssh; then
    echo "SSH client not found. Installing..."
    install_package "openssh-client"
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

# Copy the public key to the Main server for passwordless authentication
echo "Copying public key to the Main server for passwordless authentication..."
ssh-copy-id "$MAIN_SERVER_USER@$MAIN_SERVER_IP"

# Ask for the Remote NGINX server port
echo "Enter the Remote NGINX server port (e.g., 80):"
read REMOTE_NGINX_PORT

# Establish reverse SSH tunnel using autossh
echo "Installing autossh for automatic SSH tunnel maintenance..."
install_package "autossh"

echo "Setting up reverse SSH tunnel from Remote NGINX port $REMOTE_NGINX_PORT to local port $LOCAL_FORWARD_PORT on the Main server..."
autossh -M 0 -f -N -R "$LOCAL_FORWARD_PORT:localhost:$REMOTE_NGINX_PORT" "$MAIN_SERVER_USER@$MAIN_SERVER_IP"

echo "Reverse SSH tunnel established and autossh is maintaining the connection."

echo "SSH tunneling setup on the remote server is complete."

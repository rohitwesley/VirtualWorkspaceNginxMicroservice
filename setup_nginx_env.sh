#!/bin/bash

# File: setup_nginx_env.sh

set -e

# Load environment variables from .env file
set -a
source .env
set +a

# Validate required environment variables
: "${DOMAIN_NAME:?Missing DOMAIN_NAME}"
: "${DOMAIN_EMAILID:?Missing DOMAIN_EMAILID}"
: "${NGINX_PORT_HTTP:?Missing NGINX_PORT_HTTP}"
: "${NGINX_PORT_HTTPS:?Missing NGINX_PORT_HTTPS}"
: "${SSL_PATH:?Missing SSL_PATH}"
: "${ML_PORT:?Missing ML_PORT}"
: "${RUST_PORT:?Missing RUST_PORT}"
: "${MEDIA_PORT:?Missing MEDIA_PORT}"

LETSENCRYPT_DIR="$SSL_PATH/letsencrypt"

# Ensure directories exist
mkdir -p "$SSL_PATH"
mkdir -p "$LETSENCRYPT_DIR"

# Function to prompt user for overwriting files
prompt_overwrite() {
    local file="$1"
    if [ -f "$file" ]; then
        while true; do
            read -p "File '$file' already exists. Do you want to overwrite it? (y/n): " yn
            case $yn in
                [Yy]* ) return 0;;
                [Nn]* ) echo "Skipping overwrite of '$file'."; return 1;;
                * ) echo "Please answer yes or no.";;
            esac
        done
    else
        return 0
    fi
}

# Create minimal nginx.conf for ACME challenge
NGINX_CONF_FILE="nginx.conf"
if prompt_overwrite "$NGINX_CONF_FILE"; then
    cat <<EOL > "$NGINX_CONF_FILE"
events {
    worker_connections 1024;
}

http {
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;

    server {
        listen ${NGINX_PORT_HTTP};
        server_name ${DOMAIN_NAME};

        # Serve ACME challenge for Let's Encrypt
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
    }
}
EOL

    echo "Minimal ACME challenge '$NGINX_CONF_FILE' generated."
else
    echo "Using existing '$NGINX_CONF_FILE'."
fi

# Create Dockerfile.nginx for a base image with Certbot
DOCKERFILE_NGINX="Dockerfile.nginx"
if prompt_overwrite "$DOCKERFILE_NGINX"; then
    cat <<EOL > "$DOCKERFILE_NGINX"
FROM nginx:latest
RUN apt-get update -y && apt-get -y upgrade && apt-get -y install python3 python3-pip python3-venv libaugeas0
RUN python3 -m venv /opt/certbot/ && /opt/certbot/bin/pip install --upgrade pip
RUN /opt/certbot/bin/pip install certbot certbot-nginx && ln -s /opt/certbot/bin/certbot /usr/bin/certbot

COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE ${NGINX_PORT_HTTP} ${NGINX_PORT_HTTPS}
EOL

    echo "'$DOCKERFILE_NGINX' for base NGINX + Certbot created."
else
    echo "Using existing '$DOCKERFILE_NGINX'."
fi

# Ensure the Docker network exists
echo "Ensuring Docker network 'vw-network-cluster' exists..."
docker network inspect vw-network-cluster >/dev/null 2>&1 || docker network create vw-network-cluster

# Build and run the minimal environment
echo "Building and starting Docker containers with minimal NGINX configuration..."
docker compose up -d --build

echo "Minimal NGINX environment with ACME challenge support is up."

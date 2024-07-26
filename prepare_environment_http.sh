#!/bin/bash

# Load environment variables from .env file
set -a
source .env
set +a

# Variables
NGINX_HOST=$NGINX_HOST # Replace with your actual public IP
NGINX_PORT_HTTP=80
NGINX_PORT_HTTPS=443
SSL_PATH=$SSL_PATH  # Path for SSL files accessible by microservices and Docker setup
LETSENCRYPT_DIR="$SSL_PATH/letsencrypt"
SSL_PASS=$SSL_PASS
SSL_KEY="$SSL_PATH/$SSL_KEY"
SSL_CERT="$SSL_PATH/$SSL_CERT"
NGINX_CONF="nginx.conf"
DOCKERFILE="Dockerfile.nginx"

# Check for required environment variables
if [ -z "$DOMAIN_EMAILID" ] || [ -z "$NGINX_PORT_HTTP" ] || [ -z "$NGINX_PORT_HTTPS" ] || [ -z "$SSL_PATH" ]; then
    echo "Required environment variables are missing in the .env file."
    exit 1
fi

# Create SSL directories if they don't exist
mkdir -p "$SSL_PATH"
mkdir -p "$LETSENCRYPT_DIR"

# Generate NGINX configuration file for HTTP only
cat <<EOL > $NGINX_CONF
events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;

    server {
        listen ${NGINX_PORT_HTTP};
        server_name ${NGINX_HOST};

        location / {
            root /usr/share/nginx/html;
            index index.html index.htm;
        }

        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        location /streams {
            proxy_pass http://${STREAMS_HOST}:${STREAMS_PORT};
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        location /ml {
            proxy_pass http://${ML_HOST}:${ML_PORT};
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
}
EOL

# Create Dockerfile for NGINX
cat <<EOL > $DOCKERFILE
FROM nginx:latest
RUN apt-get update && apt-get install -y certbot python3-certbot-nginx
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE $NGINX_PORT_HTTP $NGINX_PORT_HTTPS
EOL

# Ensure the Docker network exists
docker network inspect vw-network-cluster >/dev/null 2>&1 || docker network create vw-network-cluster

# Build and run Docker container using docker-compose
docker-compose up -d --build

echo "NGINX setup for HTTP only is complete. Verify by accessing http://${NGINX_HOST}."

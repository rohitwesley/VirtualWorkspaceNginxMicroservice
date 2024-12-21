#!/bin/bash

# File: finalize_nginx_remote.sh

set -e

# Load environment variables from .env file
set -a
source .env
set +a

# Validate required environment variables
: "${NGINX_HOST:?Missing NGINX_HOST}"
: "${NGINX_PORT_HTTP:?Missing NGINX_PORT_HTTP}"
: "${LOCAL_HOST:?Missing LOCAL_HOST}"
: "${ML_PORT:?Missing ML_PORT}"
: "${MEDIA_PORT:?Missing MEDIA_PORT}"

# NGINX_STATIC_DIR="http://${LOCAL_HOST}:${STREAMS_PORT}/public/"
NGINX_STATIC_DIR="http://${LOCAL_HOST}:${ML_PORT}/public/"

# Create the nginx.conf without SSL
cat <<EOL > nginx.conf
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

        # Default NGINX location serving index.html
        location / {
            root /usr/share/nginx/html;
            index index.html;
        }
        
        # -----------------------------------
        # Reverse Proxy for Media Microserver
        # -----------------------------------
        
        # Reverse proxy for Media API
        location /media/ {
            proxy_pass http://${LOCAL_HOST}:${MEDIA_PORT}/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
 
        # -----------------------------------
        # Reverse Proxy for ML Microserver
        # -----------------------------------
        
        # Reverse proxy for ML API
        location /ml/ {
            proxy_pass http://${LOCAL_HOST}:${ML_PORT}/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # DO NOT REMOVE THIS COMMENT script inserts ssh tunneling here
    }
}
EOL

echo "Final NGINX configuration without SSL created for remote server."

# Create Dockerfile.nginx if it doesn't exist
if [ ! -f Dockerfile.nginx ]; then
    cat <<EOL > Dockerfile.nginx
FROM nginx:latest

# Copy the nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Expose port 80
EXPOSE 80
EOL
    echo "Dockerfile.nginx created."
else
    echo "Dockerfile.nginx already exists."
fi

# Ensure the Docker network exists (assuming it's shared with main server)
docker network inspect vw-network-cluster >/dev/null 2>&1 || docker network create vw-network-cluster

# Build and deploy the NGINX container
echo "Building and deploying NGINX container without SSL..."
docker compose up -d --build

echo "Nginx restarted with final configuration on remote server."

echo "Remote NGINX setup without SSL is complete. Verify by accessing http://${NGINX_HOST}."
echo "Access microservices at http://${NGINX_HOST}/ml/ and http://${NGINX_HOST}/streams/."

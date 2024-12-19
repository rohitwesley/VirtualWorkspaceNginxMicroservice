#!/bin/bash

# File: finalize_nginx_remote.sh

set -e

# Load environment variables from .env file
set -a
source .env
set +a

# Validate required environment variables
: "${DOMAIN_NAME:?Missing DOMAIN_NAME}"
: "${NGINX_PORT_HTTP:?Missing NGINX_PORT_HTTP}"
: "${ML_PORT:?Missing ML_PORT}"
: "${STREAMS_PORT:?Missing STREAMS_PORT}"

# Optional: Set a unique identifier for the remote server if needed
REMOTE_SERVER_ID=${REMOTE_SERVER_ID:-remote1}

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
        server_name ${DOMAIN_NAME};

        # Default NGINX location serving index.html
        location / {
            root /usr/share/nginx/html;
            index index.html;
        }

        # Reverse proxy for ML services
        location /${REMOTE_SERVER_ID}/ml/ {
            proxy_pass http://localhost:${ML_PORT}/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # Reverse proxy for Streams services
        location /${REMOTE_SERVER_ID}/streams/ {
            proxy_pass http://localhost:${STREAMS_PORT}/;
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

echo "Remote NGINX setup without SSL is complete. Verify by accessing http://${DOMAIN_NAME}."
echo "Access microservices at http://${DOMAIN_NAME}/${REMOTE_SERVER_ID}/ml/ and http://${DOMAIN_NAME}/${REMOTE_SERVER_ID}/streams/."

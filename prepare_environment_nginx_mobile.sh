#!/bin/bash

# Load environment variables from .env file
set -a
source .env
set +a

# Variables
DOMAIN_NAME=$DOMAIN_NAME
DOMAIN_EMAILID=$DOMAIN_EMAILID
NGINX_HOST=$NGINX_HOST # Replace with your actual public IP
NGINX_PORT_HTTP=$NGINX_PORT_HTTP
NGINX_PORT_HTTPS=$NGINX_PORT_HTTPS
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

# Generate NGINX configuration file from template for HTTP only
cat <<EOL > $NGINX_CONF
events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;

    # Server for HTTP traffic
    server {
        listen ${NGINX_PORT_HTTP};
        server_name ${NGINX_HOST};

        # Handle NGINX Default server location for testing (/nginx)
        # Serve static files at /nginx
        location /nginx/ {
            alias /usr/share/nginx/html/;
            index index.html index.htm;
            
            # Optional: Enable autoindex if you want to list files
            autoindex on;
        }
        # Optional: Handle exact /nginx without trailing slash
        location = /nginx {
            return 301 /nginx/;
        }
        # Handle dashboard website reverse proxy (/dashboard)
        location / {
            proxy_pass http://${NGINX_HOST}:${MEDIA_PORT}/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # Reverse proxy for the dashboard microserver (e.g., for streaming)
        location /streams/ {
            proxy_pass http://${NGINX_HOST}:${MEDIA_PORT}/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # Reverse proxy for the machine learning microserver
        location /ml/ {
            proxy_pass http://${NGINX_HOST}:${ML_PORT}/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

    }
}
EOL

echo "Generated NGINX configuration file for Remote Server(HTTP)"

# Create Dockerfile for NGINX
cat <<EOL > $DOCKERFILE
FROM nginx:latest
RUN apt-get update && apt-get install -y certbot python3-certbot-nginx curl iputils-ping
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE $NGINX_PORT_HTTP $NGINX_PORT_HTTPS
EOL

echo "Created Dockerfile for NGINX"

# Ensure the Docker network exists
docker network inspect vw-network-cluster >/dev/null 2>&1 || docker network create vw-network-cluster

echo "Building Docker Container"
# Build and run Docker container using docker compose
docker compose build --no-cache && docker compose up --force-recreate -d

echo "Waiting for nginx-microserver to initialize..."
sleep 30
    
# Prompt user for building and running Docker containers
read -p "Do you want to test the Docker containers now? (y/n): " build_and_run
if [[ "$build_and_run" == "y" ]]; then
    echo "Testing connectivity to microservices..."
    docker exec -it nginx-microserver /bin/bash -c "
        echo 'Pinging dashboard-microserver...'
        ping -c 4 dashboard-microserver
        echo 'Pinging python-microserver...'
        ping -c 4 python-microserver
        echo 'Curl to dashboard-microserver...'
        curl http://dashboard-microserver:${MEDIA_PORT}
        echo 'Curl to python-microserver...'
        curl http://python-microserver:${ML_PORT}
    "

    docker logs nginx-microserver

else
    echo "Docker containers setup is complete. You can build and run them later using docker compose commands."
fi

echo "NGINX setup for HTTP only is complete. Verify by accessing http://${NGINX_HOST}:${NGINX_PORT_HTTP}."


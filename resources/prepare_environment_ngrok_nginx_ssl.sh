#!/bin/bash

# Load environment variables from .env file
set -a
source .env
set +a

# Variables
DOMAIN_NAME=$DOMAIN_NAME
DOMAIN_EMAILID=$DOMAIN_EMAILID
NGINX_PORT_HTTP=$NGINX_PORT_HTTP
NGINX_PORT_HTTPS=$NGINX_PORT_HTTPS
NGROK_AUTH_TOKEN=$NGROK_AUTH_TOKEN
NGROK_PORT_HTTP=$NGROK_PORT_HTTP
STREAMS_HOST=$STREAMS_HOST
STREAMS_PORT=$STREAMS_PORT
ML_HOST=$ML_HOST
ML_PORT=$ML_PORT

# Check for required environment variables
if [ -z "$DOMAIN_EMAILID" ] || [ -z "$NGINX_PORT_HTTP" ] || [ -z "$NGINX_PORT_HTTPS" ] || [ -z "$NGROK_AUTH_TOKEN" ] || [ -z "$NGROK_PORT_HTTP" ] || [ -z "$STREAMS_HOST" ] || [ -z "$STREAMS_PORT" ] || [ -z "$ML_HOST" ] || [ -z "$ML_PORT" ]; then
    echo "Required environment variables are missing in the .env file."
    exit 1
fi

# Create NGINX configuration file for HTTP and reverse proxying
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

# Create Dockerfile for Nginx
cat <<EOL > Dockerfile.nginx
# Use the official Nginx image as a base
FROM nginx:latest

# Install any necessary dependencies (optional)
RUN apt-get update && apt-get install -y \\
    wget \\
    jq \\
    && rm -rf /var/lib/apt/lists/*

# Copy the Nginx configuration file
COPY nginx.conf /etc/nginx/nginx.conf

# Ensure the directories exist for SSL certificates (optional, as Ngrok handles SSL)
RUN mkdir -p /etc/nginx/ssl /var/www/certbot

# Optionally copy any additional files needed (e.g., web content)
# COPY your-web-content /usr/share/nginx/html
EOL

# Create Dockerfile for Ngrok
cat <<EOL > Dockerfile.ngrok
# Use an official Alpine Linux as a base image
FROM alpine:latest

# Set environment variables
ENV NGROK_VERSION=3.2.0
ENV NGROK_REGION=us

# Install dependencies
RUN apk update && apk add --no-cache curl

# Download and install Ngrok
RUN curl -sSL https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-v${NGROK_VERSION}-linux-amd64.zip -o /tmp/ngrok.zip && \\
    unzip /tmp/ngrok.zip -d /usr/local/bin && \\
    rm /tmp/ngrok.zip

# Create the Ngrok configuration directory
RUN mkdir -p /root/.ngrok2

# Expose the port Ngrok will use
EXPOSE 4040

# Run Ngrok with a configuration file
CMD ["sh", "-c", "echo 'authtoken: ${NGROK_AUTH_TOKEN}' > /root/.ngrok2/ngrok.yml && ngrok http -config /root/.ngrok2/ngrok.yml -region=${NGROK_REGION} ${NGROK_PORT_HTTP}"]
EOL

# Ensure the Docker network exists
docker network inspect vw-network-cluster >/dev/null 2>&1 || docker network create vw-network-cluster

# Build and run Docker containers
docker-compose up -d --build

# Increase wait time to 20 seconds
echo "Waiting for Ngrok to initialize..."
sleep 20

# Fetch the Ngrok URL (HTTPS version)
NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[] | select(.proto=="https") | .public_url')

# Check if Ngrok URL is working
if [ -z "$NGROK_URL" ]; then
    echo "Ngrok URL could not be obtained. Exiting."
    docker logs ngrok-container
    exit 1
fi

echo "NGINX setup with Ngrok is complete. Access your services via ${NGROK_URL}."

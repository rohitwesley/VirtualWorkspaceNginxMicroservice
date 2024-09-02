#!/bin/bash

# Load environment variables from .env file
set -a
source .env
set +a

# Variables
NGROK_AUTH_TOKEN=$NGROK_AUTH_TOKEN
NGROK_REGION=$NGROK_REGION
NGROK_PORT_HTTP=$NGROK_PORT_HTTP

# Check for required environment variables
if [ -z "$NGROK_AUTH_TOKEN" ] || [ -z "$NGROK_PORT_HTTP" ]; then
    echo "Required environment variables are missing in the .env file."
    exit 1
fi

# Create Dockerfile for Ngrok
cat <<EOL > Dockerfile.ngrok
# Use an official Alpine Linux as a base image
FROM alpine:latest

# Set environment variables
ENV NGROK_VERSION=3.2.0
ENV NGROK_REGION=${NGROK_REGION}

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

# Prompt user for building and running Docker containers
read -p "Do you want to build and run the Docker containers now? (y/n): " build_and_run
if [[ "$build_and_run" == "y" ]]; then
    docker-compose down
    docker-compose build --no-cache
    docker-compose up --force-recreate -d
else
    echo "Docker containers setup is complete. You can build and run them later using docker-compose commands."
fi

# Increase wait time to 20 seconds
echo "Waiting for Ngrok to initialize..."
sleep 30

# Check if Ngrok configuration file exists
if [ -f /root/.ngrok2/ngrok.yml ]; then
    cat /root/.ngrok2/ngrok.yml
else
    echo "Ngrok configuration file not found!"
fi

# Fetch the Ngrok URL (HTTPS version)
NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[] | select(.proto=="https") | .public_url')

# Check if Ngrok URL is working
if [ -z "$NGROK_URL" ]; then
    echo "Ngrok URL could not be obtained. Exiting."
    docker logs ngrok-container
    exit 1
else
    echo "NGINX setup with Ngrok is complete. Access your services via ${NGROK_URL}."
    docker logs ngrok-container
    exit 1
fi


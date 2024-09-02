#!/bin/bash

# Load environment variables from .env file
set -a
source .env
set +a

# Variables
CONDA_ENV_NAME=$CONDA_ENV_NAME
ML_HOST=$ML_HOST
ML_PORT=$ML_PORT
SSL_VOL=$SSL_VOL
SSL_PATH=$SSL_PATH
SSL_CERT=$SSL_CERT
SSL_KEY=$SSL_KEY
NGINX_PORT_HTTP=$NGINX_PORT_HTTP
NGINX_PORT_HTTPS=$NGINX_PORT_HTTPS
NGROK_AUTH_TOKEN=$NGROK_AUTH_TOKEN
NGROK_PORT_HTTP=$NGROK_PORT_HTTP

# Check for required environment variables
if [ -z "$ML_HOST" ] || [ -z "$ML_PORT" ] || [ -z "$SSL_VOL" ] || [ -z "$SSL_PATH" ] || [ -z "$SSL_CERT" ] || [ -z "$SSL_KEY" ]; then
    echo "Required environment variables are missing in the .env file."
    exit 1
fi

# Prompt user for NGINX and/or Ngrok server setup
echo "Do you want to include an NGINX server, Ngrok server, or both in the Docker Compose setup?"
echo "1) NGINX server"
echo "2) Ngrok server"
echo "3) Both"
read -p "Enter your choice (1/2/3): " server_choice

nginx_service=""
ngrok_service=""

case $server_choice in
    1)
        nginx_service=$(cat <<EOL
  nginx:
    build:
      context: .
      dockerfile: Dockerfile.nginx
      args:
        - CONDA_ENV_NAME=${CONDA_ENV_NAME}
    container_name: nginx-microserver
    image: "vw-nginx-microservice"
    ports:
      - "${NGINX_PORT_HTTP}:${NGINX_PORT_HTTP}"
      - "${NGINX_PORT_HTTPS}:${NGINX_PORT_HTTPS}"
    volumes:
      - ${MEDIA_PATH}:${MEDIA_VOL}
      - ${SSL_PATH}:${SSL_VOL}
      - ${SSL_PATH}/letsencrypt:/etc/letsencrypt
      - ${SSL_PATH}/letsencrypt:/var/www/certbot
    env_file:
      - .env
    restart: always
    networks:
      - vw-network-cluster
EOL
)
        ;;
    2)
        if [ -z "$NGROK_AUTH_TOKEN" ] || [ -z "$NGROK_PORT_HTTP" ]; then
            echo "Ngrok environment variables are missing in the .env file."
            exit 1
        fi
        ngrok_service=$(cat <<EOL
  ngrok:
    image: ngrok/ngrok:latest
    container_name: ngrok-container
    network_mode: "host"
    environment:
      - NGROK_AUTHTOKEN=${NGROK_AUTH_TOKEN}
    command: "http ${NGROK_PORT_HTTP}"
    restart: always
EOL
)
        ;;
    3)
        nginx_service=$(cat <<EOL
  nginx:
    build:
      context: .
      dockerfile: Dockerfile.nginx
      args:
        - CONDA_ENV_NAME=${CONDA_ENV_NAME}
    container_name: nginx-microserver
    image: "vw-nginx-microservice"
    ports:
      - "${NGINX_PORT_HTTP}:${NGINX_PORT_HTTP}"
      - "${NGINX_PORT_HTTPS}:${NGINX_PORT_HTTPS}"
    volumes:
      - ${MEDIA_PATH}:${MEDIA_VOL}
      - ${SSL_PATH}:${SSL_VOL}
      - ${SSL_PATH}/letsencrypt:/etc/letsencrypt
      - ${SSL_PATH}/letsencrypt:/var/www/certbot
    env_file:
      - .env
    restart: always
    networks:
      - vw-network-cluster
EOL
)
        if [ -z "$NGROK_AUTH_TOKEN" ] || [ -z "$NGROK_PORT_HTTP" ]; then
            echo "Ngrok environment variables are missing in the .env file."
            exit 1
        fi
        ngrok_service=$(cat <<EOL
  ngrok:
    image: ngrok/ngrok:latest
    container_name: ngrok-container
    network_mode: "host"
    environment:
      - NGROK_AUTHTOKEN=${NGROK_AUTH_TOKEN}
    command: "http ${NGROK_PORT_HTTP}"
    restart: always
EOL
)
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

# Create Docker Compose file
cat <<EOL > docker-compose.yml
services:
$nginx_service
$ngrok_service
networks:
  vw-network-cluster:
    external: true
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

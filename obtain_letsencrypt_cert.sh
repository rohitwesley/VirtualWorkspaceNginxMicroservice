#!/bin/bash

# File: obtain_letsencrypt_cert.sh

set -e

# Load environment variables from .env file
set -a
source .env
set +a

# Validate required environment variables
: "${DOMAIN_NAME:?Missing DOMAIN_NAME}"
: "${DOMAIN_EMAILID:?Missing DOMAIN_EMAILID}"
: "${SSL_PATH:?Missing SSL_PATH}"

LETSENCRYPT_DIR="$SSL_PATH/letsencrypt"

echo "Waiting 10 seconds to ensure NGINX is ready..."
sleep 10

echo "Obtaining Let's Encrypt certificate using Certbot..."
docker compose run --rm \
    -v ${SSL_PATH}/letsencrypt:/var/www/certbot \
    nginx certbot certonly --webroot -v \
    --webroot-path=/var/www/certbot \
    -d ${DOMAIN_NAME} \
    --non-interactive \
    --agree-tos \
    --email ${DOMAIN_EMAILID}

# Check if Let's Encrypt files were created successfully
echo "Checking if Let's Encrypt certificate was obtained successfully..."
if [ ! -d "$LETSENCRYPT_DIR/live/$DOMAIN_NAME" ]; then
    echo "Error: Let's Encrypt certificate was not obtained successfully."
    echo "Check Certbot logs at /var/log/letsencrypt/letsencrypt.log for details."
    exit 1
fi

echo "Let's Encrypt certificate successfully obtained."

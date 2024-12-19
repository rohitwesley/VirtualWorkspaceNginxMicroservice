#!/bin/bash

# Load environment variables from .env file
set -a
source .env
set +a

# Variables
: "${DOMAIN_NAME:?Missing DOMAIN_NAME}"
: "${DOMAIN_EMAILID:?Missing DOMAIN_EMAILID}"
: "${NGINX_PORT_HTTP:?Missing NGINX_PORT_HTTP}"
: "${NGINX_PORT_HTTPS:?Missing NGINX_PORT_HTTPS}"
: "${SSL_PATH:?Missing SSL_PATH}"
: "${ML_PORT:?Missing ML_PORT}"
: "${RUST_PORT:?Missing RUST_PORT}"
: "${MEDIA_PORT:?Missing MEDIA_PORT}"

DOMAIN_SERVERID=$DOMAIN_SERVERID
NGINX_HOST=$NGINX_HOST

SSL_VOL=$SSL_VOL
LETSENCRYPT_DIR="$SSL_PATH/letsencrypt"

# Ensure directories exist
mkdir -p "$SSL_PATH"
mkdir -p "$LETSENCRYPT_DIR"

DOCKERFILE="Dockerfile.nginx"

# --- PHASE 1: Minimal NGINX Config for ACME Challenge ---
# This config listens only on HTTP and does NOT redirect to HTTPS.
# It serves the ACME challenge directory for Let's Encrypt validation.
cat <<EOL > nginx.conf
events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;

    # Minimal server for ACME challenge
    server {
        listen ${NGINX_PORT_HTTP};
        server_name ${DOMAIN_NAME};
        
        # Serve ACME challenge files
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        # Temporarily, no redirects or SSL
        # No reverse proxying yet - just enough to prove domain ownership
    }
}
EOL

echo "Generated minimal NGINX configuration (HTTP-only) for ACME challenge."

# Create a Dockerfile that does not rely on password-protected keys or self-signed certs
cat <<EOL > $DOCKERFILE
FROM nginx:latest
RUN apt-get update -y && apt-get -y upgrade && apt-get -y install python3 python3-pip python3-venv libaugeas0
RUN python3 -m venv /opt/certbot/ && /opt/certbot/bin/pip install --upgrade pip
RUN /opt/certbot/bin/pip install certbot certbot-nginx && ln -s /opt/certbot/bin/certbot /usr/bin/certbot

# Copy the minimal config initially
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE $NGINX_PORT_HTTP $NGINX_PORT_HTTPS
EOL

echo "Created Dockerfile for NGINX with Certbot (no password-protected keys)."

# Ensure the Docker network exists
echo "Ensure the Docker network exists"
docker network inspect vw-network-cluster >/dev/null 2>&1 || docker network create vw-network-cluster

echo "Building and starting Docker Container (Minimal config)"
docker compose up -d --build

# Wait for NGINX to start
echo "Sleeping for 10 seconds to allow NGINX to start..."
sleep 10

# --- PHASE 2: Obtain Let's Encrypt Certificate ---
echo "Obtain SSL certificate with Certbot using the webroot method..."
docker compose run --rm \
    -v ${SSL_PATH}/letsencrypt:/var/www/certbot \
    nginx certbot certonly --webroot -v \
    --webroot-path=/var/www/certbot \
    -d ${DOMAIN_NAME} \
    --non-interactive \
    --agree-tos \
    --email ${DOMAIN_EMAILID}

# Check if Let's Encrypt files were created successfully
echo "Checking if Let's Encrypt files were created successfully..."
if [ ! -d "$LETSENCRYPT_DIR/live/$DOMAIN_NAME" ]; then
    echo "Error: Let's Encrypt files were not created successfully."
    echo "Check logs and ensure domain name is correctly pointed to this server."
    exit 1
fi

echo "Certificates obtained successfully."

# --- PHASE 3: Final HTTPS NGINX Config ---
# Now that we have the certificates in /etc/letsencrypt/live/$DOMAIN_NAME inside the container (mounted from host),
# we can enable HTTPS, redirect HTTP to HTTPS, and set up reverse proxies.

cat <<EOL > nginx.conf
events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;

    # HTTP server that redirects to HTTPS
    server {
        listen ${NGINX_PORT_HTTP};
        server_name ${DOMAIN_NAME};
        return 301 https://\$host\$request_uri;
    }

    # HTTPS server with reverse proxy setups
    server {
        listen ${NGINX_PORT_HTTPS} ssl;
        server_name ${DOMAIN_NAME};

        # Use the certs obtained by certbot
        ssl_certificate /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem;

        # ACME challenge location for future renewals
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        # Reverse proxy for dashboard
        location / {
            proxy_pass http://dashboard-microserver:${MEDIA_PORT}/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # Reverse proxy for streams
        location /$DOMAIN_SERVERID/streams/ {
            proxy_pass http://dashboard-microserver:${MEDIA_PORT}/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # Reverse proxy for ML services
        location /$DOMAIN_SERVERID/ml/ {
            proxy_pass http://python-microserver:${ML_PORT}/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # Reverse proxy for Rust services
        location /$DOMAIN_SERVERID/rust/ {
            proxy_pass http://rust-microserver:${RUST_PORT}/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # DO NOT REMOVE THIS COMMENT script inserts ssh tunneling here
    }
}
EOL

echo "Generated final NGINX configuration with HTTPS and reverse proxies."

# Just restart NGINX service to apply final config
docker compose restart nginx

echo "Setup complete. NGINX is running on ports $NGINX_PORT_HTTP (HTTP->HTTPS redirect) and $NGINX_PORT_HTTPS (HTTPS) for domain $DOMAIN_NAME."
echo "Verify by accessing https://${DOMAIN_NAME}."

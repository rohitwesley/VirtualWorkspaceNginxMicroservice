#!/bin/bash

# File: finalize_nginx_https.sh

set -e

# Load environment variables from .env file
set -a
source .env
set +a

# Validate required environment variables
: "${DOMAIN_NAME:?Missing DOMAIN_NAME}"
: "${NGINX_PORT_HTTP:?Missing NGINX_PORT_HTTP}"
: "${NGINX_PORT_HTTPS:?Missing NGINX_PORT_HTTPS}"
: "${ML_PORT:?Missing ML_PORT}"
: "${RUST_PORT:?Missing RUST_PORT}"
: "${MEDIA_PORT:?Missing MEDIA_PORT}"

DOMAIN_SERVERID=$DOMAIN_SERVERID

# Create final nginx.conf with HTTPS and reverse proxies
cat <<EOL > nginx.conf
events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;

    # Redirect all HTTP to HTTPS
    server {
        listen ${NGINX_PORT_HTTP};
        server_name ${DOMAIN_NAME};
        return 301 https://\$host\$request_uri;
    }

    # HTTPS server with proxying
    server {
        listen ${NGINX_PORT_HTTPS} ssl;
        server_name ${DOMAIN_NAME};

        ssl_certificate /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem;

        # ACME challenge for renewals
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        # Default NGINX location serving index.html
        location / {
            root /usr/share/nginx/html;
            index index.html;
        }

        # -----------------------------------
        # Reverse Proxy for Media Microserver
        # -----------------------------------
        
        # Reverse proxy for Media API
        location /${DOMAIN_SERVERID}/media/ {
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
        location /${DOMAIN_SERVERID}/ml/ {
            proxy_pass http://${LOCAL_HOST}:${ML_PORT}/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # DO NOT REMOVE THIS COMMENT script inserts ssh tunnelling here
    }
}
EOL

echo "Final NGINX configuration with HTTPS and local reverse proxies created."

# Restart NGINX to apply final config
# docker compose up -d --build
docker compose down && docker compose build --no-cache && docker compose up --force-recreate -d
docker compose restart nginx

echo "Nginx restarted with final HTTPS configuration."
echo "Final NGINX setup is complete. Verify by accessing https://${DOMAIN_NAME}."

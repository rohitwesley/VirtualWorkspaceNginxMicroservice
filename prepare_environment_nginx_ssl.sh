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
NGINX_CONF_TEMPLATE="nginx.conf.template"
NGINX_CONF="nginx.conf"
NGINX_CONF_TEMP="nginx.temp.conf"
DOCKERFILE="Dockerfile.nginx"

# Check for required environment variables
if [ -z "$DOMAIN_NAME" ] || [ -z "$DOMAIN_EMAILID" ] || [ -z "$NGINX_PORT_HTTP" ] || [ -z "$NGINX_PORT_HTTPS" ] || [ -z "$SSL_PATH" ]; then
    echo "Required environment variables are missing in the .env file."
    exit 1
fi

# Create SSL directories if they don't exist
mkdir -p "$SSL_PATH"
mkdir -p "$LETSENCRYPT_DIR"

# Generate or update SSL key and certificate if not already present
if [ ! -f "$SSL_KEY" ] || [ ! -f "$SSL_CERT" ]; then
    openssl genpkey -algorithm RSA -aes256 -pass pass:$SSL_PASS -out "$SSL_KEY" || exit 1
    openssl req -new -key "$SSL_KEY" -passin pass:$SSL_PASS -out "$SSL_PATH/request.csr" -subj "/CN=$DOMAIN_NAME" || exit 1
    openssl x509 -req -days 365 -in "$SSL_PATH/request.csr" -signkey "$SSL_KEY" -passin pass:$SSL_PASS -out "$SSL_CERT" || exit 1
fi

# Generate temporary NGINX configuration file for Certbot challenge
cat <<EOL > $NGINX_CONF_TEMP
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        server_name ${DOMAIN_NAME};

        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
    }
}
EOL

# Generate NGINX configuration file from template
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
        server_name ${DOMAIN_NAME};
        return 301 https://$host$request_uri;
    }

    server {
        listen ${NGINX_PORT_HTTPS} ssl;
        server_name ${DOMAIN_NAME};

        ssl_password_file /etc/nginx/ssl-password.pass;
        ssl_certificate ${SSL_VOL}/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem;
        ssl_certificate_key ${SSL_VOL}/letsencrypt/live/${DOMAIN_NAME}/privkey.pem;

        location / {
            proxy_pass http://${STREAMS_HOST}:${STREAMS_PORT};
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        
        location /ca/streams {
            proxy_pass http://${STREAMS_HOST}:${STREAMS_PORT};
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        location /ca/ml {
            proxy_pass http://${ML_HOST}:${ML_PORT};
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
}
EOL

# Create Dockerfile for NGINX with Certbot
cat <<EOL > $DOCKERFILE
FROM nginx:latest
RUN apt-get update && apt-get install -y certbot python3-certbot-nginx
COPY nginx.conf /etc/nginx/nginx.conf
RUN echo $SSL_PASS >> /etc/nginx/ssl-password.pass
EXPOSE $NGINX_PORT_HTTP $NGINX_PORT_HTTPS
EOL

# Ensure the Docker network exists
docker network inspect vw-network-cluster >/dev/null 2>&1 || docker network create vw-network-cluster

# Build and run Docker container using docker compose
docker compose up -d --build
# docker compose build --no-cache && docker compose up --force-recreate -d

# Temporarily use the temp configuration to serve the challenge
docker cp nginx.temp.conf nginx-microserver:/etc/nginx/nginx.conf
docker compose restart nginx

# Obtain SSL certificate with Certbot, using a volume for Let's Encrypt
# docker compose run --rm nginx certbot certonly --webroot --webroot-path=/usr/share/nginx/html -d ${DOMAIN_NAME} --non-interactive --agree-tos --email ${DOMAIN_EMAILID}
docker compose run --rm -v ${SSL_PATH}/letsencrypt:/var/www/certbot nginx certbot certonly --webroot --webroot-path=/var/www/certbot -d ${DOMAIN_NAME} --non-interactive --agree-tos --email ${DOMAIN_EMAILID}

# Check if Let's Encrypt files were created successfully
if [ ! -d "$LETSENCRYPT_DIR/live/$DOMAIN_NAME" ]; then
    echo "Error: Let's Encrypt files were not created successfully."
    exit 1
fi

# Copy Let's Encrypt files to the Docker SSL directory
cp -r "$LETSENCRYPT_DIR/live/$DOMAIN_NAME" "$SSL_PATH/"
cp -r "$LETSENCRYPT_DIR/archive/$DOMAIN_NAME" "$SSL_PATH/"
cp -r "$LETSENCRYPT_DIR/renewal/$DOMAIN_NAME.conf" "$SSL_PATH/"

# Restart NGINX to apply the new certificate
docker cp $NGINX_CONF nginx-microserver:/etc/nginx/nginx.conf
docker compose restart nginx

echo "Setup complete. NGINX is running on ports $NGINX_PORT_HTTP and $NGINX_PORT_HTTPS for domain $DOMAIN_NAME with SSL."
echo "NGINX setup for HTTPS is complete. Verify by accessing https://${DOMAIN_NAME}."

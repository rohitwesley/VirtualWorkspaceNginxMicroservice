#!/bin/bash

# Load environment variables from .env file
set -a
source .env
set +a

# Variables
DOMAIN_NAME=$DOMAIN_NAME
DOMAIN_EMAILID=$DOMAIN_EMAILID
DOMAIN_SERVERID=$DOMAIN_SERVERID
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

    # Handle http request forwarding them to the https server (may need to get commented out for certbot)
    server {
        listen ${NGINX_PORT_HTTP};
        server_name ${DOMAIN_NAME};
        return 301 https://$host$request_uri;
    }

    # Handle https request
    server {
        listen ${NGINX_PORT_HTTPS} ssl;
        listen ${REDIS_PORT};
        # Uncomment this line when recertifying because certbot needs to listen on HTTP
        # listen ${NGINX_PORT_HTTP};

        server_name ${DOMAIN_NAME};

        # Handle ssl certificate
        ssl_password_file /etc/nginx/ssl-password.pass;
        ssl_certificate ${SSL_VOL}/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem;
        ssl_certificate_key ${SSL_VOL}/letsencrypt/live/${DOMAIN_NAME}/privkey.pem;

        # Handle ssl cerbot authentication
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        # Handle dashboard website reverse proxy (/dashboard)
        location / {
            proxy_pass http://dashboard-microserver:${STREAMS_PORT}/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
        
        # Handle streams node reverse proxy (/serverid/streaams)
        location $DOMAIN_SERVERID/streams/ {
            proxy_pass http://dashboard-microserver:${STREAMS_PORT}/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # Handle ml python reverse proxy (/serverid/ml)
        location $DOMAIN_SERVERID/ml/ {
            proxy_pass http://python-microserver:${ML_PORT}/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # Handle rust microserver reverse proxy (/serverid/rust)
        location $DOMAIN_SERVERID/rust/ {
            proxy_pass http://rust-microserver:${RUST_PORT}/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # DO NOT REMOVE THIS COMMENT script inserts ssh tunelling here
    }
}
EOL

echo "Generated NGINX configuration file for Main Server(HTTPS)"

# Create Dockerfile for NGINX with latest up-to-date cerbot
cat <<EOL > $DOCKERFILE
FROM nginx:latest
RUN apt-get update -y && apt-get -y upgrade && apt-get -y install python3 python3-pip python3-venv libaugeas0
RUN python3 -m venv /opt/certbot/ && /opt/certbot/bin/pip install --upgrade pip
RUN /opt/certbot/bin/pip install certbot certbot-nginx && ln -s /opt/certbot/bin/certbot /usr/bin/certbot
COPY nginx.conf /etc/nginx/nginx.conf
RUN echo $SSL_PASS >> /etc/nginx/ssl-password.pass
EXPOSE $NGINX_PORT_HTTP $NGINX_PORT_HTTPS
EOL

echo "Created Dockerfile for NGINX with Certbot"

# Ensure the Docker network exists
echo "Ensure the Docker network exists"
docker network inspect vw-network-cluster >/dev/null 2>&1 || docker network create vw-network-cluster

echo "Building Docker Container"
# Build and run Docker container using docker compose
docker compose up -d --build
# docker compose build --no-cache && docker compose up --force-recreate -d

# Temporarily use the temp configuration to serve the challenge
echo "Temporarily use the temp configuration to serve the challenge"
docker cp nginx.conf nginx-microserver:/etc/nginx/nginx.conf
docker compose restart nginx

echo "Sleeping for 10 seconds to give time for nginx to boot up and accept requests..."
sleep 10
# Obtain SSL certificate with Certbot, using a volume for Let's Encrypt
echo "Obtain SSL certificate with Certbot, using a volume for Let's Encrypt"
# docker compose run --rm nginx certbot certonly --webroot --webroot-path=/usr/share/nginx/html -d ${DOMAIN_NAME} --non-interactive --agree-tos --email ${DOMAIN_EMAILID}
docker compose run --rm -v ${SSL_PATH}/letsencrypt:/var/www/certbot nginx certbot certonly --webroot -v --webroot-path=/var/www/certbot -d ${DOMAIN_NAME} --non-interactive --agree-tos --email ${DOMAIN_EMAILID}

# Check if Let's Encrypt files were created successfully
echo "Check if Let's Encrypt files were created successfully"
if [ ! -d "$LETSENCRYPT_DIR/live/$DOMAIN_NAME" ]; then
    echo "Error: Let's Encrypt files were not created successfully."
    exit 1
fi

# Copy Let's Encrypt files to the Docker SSL directory
echo "Copy Let's Encrypt files to the Docker SSL directory"
cp -r "$LETSENCRYPT_DIR/live/$DOMAIN_NAME" "$SSL_PATH/"
cp -r "$LETSENCRYPT_DIR/archive/$DOMAIN_NAME" "$SSL_PATH/"
cp -r "$LETSENCRYPT_DIR/renewal/$DOMAIN_NAME.conf" "$SSL_PATH/"

# Restart NGINX to apply the new certificate
echo "Restart NGINX to apply the new certificate"
docker cp $NGINX_CONF nginx-microserver:/etc/nginx/nginx.conf
docker compose restart nginx

echo "Setup complete. NGINX is running on ports $NGINX_PORT_HTTP and $NGINX_PORT_HTTPS for domain $DOMAIN_NAME with SSL."
echo "NGINX setup for HTTPS is complete. Verify by accessing https://${DOMAIN_NAME}."

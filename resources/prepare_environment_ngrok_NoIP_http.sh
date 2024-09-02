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

NOIP_USERNAME=$NOIP_USERNAME
NOIP_PASSWORD=$NOIP_PASSWORD
NOIP_HOSTNAME=$NOIP_HOSTNAME

NGROK_AUTH_TOKEN=$NGROK_AUTH_TOKEN

# Check for required environment variables
if [ -z "$DOMAIN_EMAILID" ] || [ -z "$NGINX_PORT_HTTP" ] || [ -z "$NGINX_PORT_HTTPS" ] || [ -z "$SSL_PATH" ] || [ -z "$NOIP_USERNAME" ] || [ -z "$NOIP_PASSWORD" ] || [ -z "$NOIP_HOSTNAME" ] || [ -z "$NGROK_AUTH_TOKEN" ]; then
    echo "Required environment variables are missing in the .env file."
    exit 1
fi

# Create SSL directories if they don't exist
mkdir -p "$SSL_PATH"
mkdir -p "$LETSENCRYPT_DIR"

# Detect the operating system
OS=""
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    if command -v apt-get &> /dev/null; then
        PACKAGE_MANAGER="apt-get"
    elif command -v yum &> /dev/null; then
        PACKAGE_MANAGER="yum"
    else
        echo "Unsupported Linux package manager. Please install the required packages manually."
        exit 1
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="mac"
    if command -v brew &> /dev/null; then
        PACKAGE_MANAGER="brew"
    else
        echo "Homebrew not found. Please install Homebrew or the required packages manually."
        exit 1
    fi
elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    OS="wsl"
    if command -v apt-get &> /dev/null; then
        PACKAGE_MANAGER="apt-get"
    else
        echo "Unsupported WSL package manager. Please install the required packages manually."
        exit 1
    fi
else
    echo "Unsupported OS. Please run this script on Linux, macOS, or Windows WSL."
    exit 1
fi

# Install jq if not installed
if ! command -v jq &> /dev/null; then
    echo "jq could not be found. Do you want to install jq? (y/n)"
    read -r install_jq
    if [[ "$install_jq" == "y" ]]; then
        if [[ "$PACKAGE_MANAGER" == "apt-get" ]]; then
            sudo apt-get update
            sudo apt-get install -y jq
        elif [[ "$PACKAGE_MANAGER" == "yum" ]]; then
            sudo yum install -y jq
        elif [[ "$PACKAGE_MANAGER" == "brew" ]]; then
            brew install jq
        fi
    else
        echo "jq is required for the script to run. Exiting."
        exit 1
    fi
fi

# Install wget if not installed
if ! command -v wget &> /dev/null; then
    echo "wget could not be found. Do you want to install wget? (y/n)"
    read -r install_wget
    if [[ "$install_wget" == "y" ]]; then
        if [[ "$PACKAGE_MANAGER" == "apt-get" ]]; then
            sudo apt-get update
            sudo apt-get install -y wget
        elif [[ "$PACKAGE_MANAGER" == "yum" ]]; then
            sudo yum install -y wget
        elif [[ "$PACKAGE_MANAGER" == "brew" ]]; then
            brew install wget
        fi
    else
        echo "wget is required for the script to run. Exiting."
        exit 1
    fi
fi

# Function to handle Ngrok installation
install_ngrok() {
    echo "Installing ngrok..."
    wget -qO- https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip | funzip > ngrok
    chmod +x ngrok
    sudo mv ngrok /usr/local/bin/ngrok
    ngrok authtoken $NGROK_AUTH_TOKEN
}

# Function to uninstall Ngrok
uninstall_ngrok() {
    echo "Uninstalling ngrok..."
    sudo pkill ngrok
    NGROK_PATH=$(which ngrok)
    if [ -n "$NGROK_PATH" ]; then
        sudo rm -f "$NGROK_PATH"
    fi
    sudo rm -rf ~/.ngrok2
    echo "Ngrok uninstalled."
}

# Function to handle No-IP DUC installation
install_noip() {
    echo "Installing No-IP DUC..."
    wget http://www.noip.com/client/linux/noip-duc-linux.tar.gz
    tar xf noip-duc-linux.tar.gz
    cd noip-2.1.9-1/
    sudo make
    sudo make install
    cd ..
    rm -rf noip-2.1.9-1/ noip-duc-linux.tar.gz
    echo "$NOIP_USERNAME
$NOIP_PASSWORD
" | sudo noip2 -C
}

# Function to uninstall No-IP DUC
uninstall_noip() {
    echo "Uninstalling No-IP DUC..."
    sudo pkill -f noip2
    NOIP_PATH=$(which noip2)
    if [ -n "$NOIP_PATH" ]; then
        sudo rm -f "$NOIP_PATH"
    fi
    sudo rm -f /usr/local/etc/no-ip2.conf
    echo "No-IP DUC uninstalled."
}

# Function to handle NGINX setup
setup_nginx() {
    # Generate NGINX configuration file for HTTP and reverse proxying
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
        server_name ${NGINX_HOST};

        location / {
            root /usr/share/nginx/html;
            index index.html index.htm;
        }

        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        location /redis/ {
            proxy_pass http://redis:6379/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        location /node/ {
            proxy_pass http://nodejs:3000/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        location /python/ {
            proxy_pass http://python:8000/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
}
EOL

    # Create Dockerfile for NGINX with Ngrok and No-IP DUC
    cat <<EOL > $DOCKERFILE
FROM nginx:latest

# Install required packages
RUN apt-get update && apt-get install -y \\
    wget \\
    jq \\
    cron \\
    curl \\
    gcc \\
    make \\
    unzip

# Install Ngrok
RUN wget -qO- https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip | funzip > ngrok && \\
    chmod +x ngrok && \\
    mv ngrok /usr/local/bin/ngrok

# Install No-IP DUC
RUN wget http://www.noip.com/client/linux/noip-duc-linux.tar.gz && \\
    tar xf noip-duc-linux.tar.gz && \\
    cd noip-2.1.9-1 && \\
    make && \\
    make install && \\
    cd .. && \\
    rm -rf noip-2.1.9-1 noip-duc-linux.tar.gz

# Copy NGINX configuration file
COPY nginx.conf /etc/nginx/nginx.conf

# Copy the update script
COPY update_noip.sh /usr/local/bin/update_noip.sh

# Make the update script executable
RUN chmod +x /usr/local/bin/update_noip.sh

# Add crontab file in the cron directory
COPY crontab /etc/cron.d/noip-update

# Give execution rights on the cron job
RUN chmod 0644 /etc/cron.d/noip-update

# Create the log file to be able to run tail
RUN touch /var/log/cron.log

# Run the command on container startup
CMD cron && tail -f /var/log/cron.log
EOL

    # Create the update_noip.sh script
    cat <<EOL > update_noip.sh
#!/bin/bash

# Get the Ngrok URL
NGROK_URL=\$(curl -s http://127.0.0.1:4040/api/tunnels | jq -r .tunnels[0].public_url)
NOIP_USERNAME="$NOIP_USERNAME"
NOIP_PASSWORD="$NOIP_PASSWORD"
NOIP_HOSTNAME="$NOIP_HOSTNAME"

# Update No-IP DNS
curl -s "http://dynupdate.no-ip.com/nic/update?hostname=\$NOIP_HOSTNAME&myip=\${NGROK_URL#http://}" \\
     --user "\$NOIP_USERNAME:\$NOIP_PASSWORD"
EOL

    # Create the crontab file
    cat <<EOL > crontab
*/5 * * * * root /usr/local/bin/update_noip.sh >> /var/log/cron.log 2>&1
EOL

    # Ensure the Docker network exists
    docker network inspect vw-network-cluster >/dev/null 2>&1 || docker network create vw-network-cluster

    # Build and run Docker container using docker-compose
    docker-compose up -d --build

    # Verify NGINX setup
    echo "NGINX setup for HTTP only is complete. Verify by accessing http://${NGINX_HOST}."
}

# Function to uninstall NGINX setup
uninstall_nginx() {
    echo "Uninstalling NGINX setup..."
    docker-compose down
    sudo rm -f $NGINX_CONF
    sudo rm -f $DOCKERFILE
    sudo rm -f /usr/local/bin/update_noip.sh
    sudo rm -f /etc/cron.d/noip-update
    echo "NGINX setup uninstalled."
}

# Check if Ngrok is installed
if command -v ngrok &> /dev/null; then
    echo "Ngrok is already installed."
    read -p "Do you want to (u)ninstall, (r)einstall, or (s)kip? " choice
    case $choice in
        u|U ) uninstall_ngrok;;
        r|R ) uninstall_ngrok; install_ngrok;;
        s|S ) echo "Ngrok installation skipped.";;
        * ) echo "Invalid choice. Skipping Ngrok installation.";;
    esac
else
    echo "Ngrok is not installed. Do you want to install Ngrok? (y/n)"
    read -r install_ngrok_choice
    if [[ "$install_ngrok_choice" == "y" ]]; then
        install_ngrok
    else
        echo "Ngrok is required for the script to run. Exiting."
        exit 1
    fi
fi

# Re-check if Ngrok is uninstalled properly
if command -v ngrok &> /dev/null; then
    echo "Ngrok uninstallation failed. Please check manually."
    exit 1
fi

# Check if No-IP DUC is installed only if Ngrok is installed
if ! command -v ngrok &> /dev/null; then
    echo "Ngrok installation failed or Ngrok is not installed. Skipping No-IP DUC installation."
    exit 1
fi

if command -v noip2 &> /dev/null; then
    echo "No-IP DUC is already installed."
    read -p "Do you want to (u)ninstall, (r)einstall, or (s)kip? " choice
    case $choice in
        u|U ) uninstall_noip;;
        r|R ) uninstall_noip; install_noip;;
        s|S ) echo "No-IP DUC installation skipped.";;
        * ) echo "Invalid choice. Skipping No-IP DUC installation.";;
    esac
else
    echo "No-IP DUC is not installed. Do you want to install No-IP DUC? (y/n)"
    read -r install_noip_choice
    if [[ "$install_noip_choice" == "y" ]]; then
        install_noip
    else
        echo "No-IP DUC is required for the script to run. Exiting."
        exit 1
    fi
fi

# Only proceed with NGINX setup if both Ngrok and No-IP DUC are installed successfully
if command -v ngrok &> /dev/null && command -v noip2 &> /dev/null; then
    # Check if NGINX is set up
    if docker-compose ps | grep -q nginx-microserver; then
        echo "NGINX is already set up."
        read -p "Do you want to (u)ninstall, (r)einstall, or (s)kip? " choice
        case $choice in
            u|U ) uninstall_nginx;;
            r|R ) uninstall_nginx; setup_nginx;;
            s|S ) echo "NGINX setup skipped.";;
            * ) echo "Invalid choice. Skipping NGINX setup.";;
        esac
    else
        setup_nginx
    fi

    # Start Ngrok to tunnel the NGINX port
    ngrok http $NGINX_PORT_HTTP &

    # Wait for Ngrok to initialize and get the public URL
    sleep 5
    NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | jq -r .tunnels[0].public_url)

    # Check if Ngrok URL is working
    if [ -z "$NGROK_URL" ]; then
        echo "Ngrok URL could not be obtained. Exiting."
        exit 1
    fi

    # Verify No-IP credentials
    NOIP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://dynupdate.no-ip.com/nic/update?hostname=$NOIP_HOSTNAME&myip=${NGROK_URL#http://}" --user "$NOIP_USERNAME:$NOIP_PASSWORD")

    if [ "$NOIP_RESPONSE" != "200" ]; then
        echo "No-IP credentials are incorrect or No-IP update failed. Exiting."
        exit 1
    fi

    # Update No-IP DNS with the new Ngrok URL
    curl -s "http://dynupdate.no-ip.com/nic/update?hostname=$NOIP_HOSTNAME&myip=${NGROK_URL#http://}" --user "$NOIP_USERNAME:$NOIP_PASSWORD"

    echo "NGINX setup with Ngrok and No-IP is complete. Access your services via http://$NOIP_HOSTNAME."
else
    echo "Ngrok or No-IP DUC installation failed. Skipping NGINX setup."
fi

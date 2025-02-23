#!/bin/bash

# Function to prompt for input if variable is not set
prompt_if_not_set() {
    local var_name="$1"
    local prompt_message="$2"
    if [[ -z "${!var_name}" ]]; then
        read -p "$prompt_message" input
        if [[ -z "$input" ]]; then
            echo "Error: $var_name cannot be empty!" >&2
            exit 1
        fi
        eval "$var_name=\"$input\""
    fi
}

# Prompt for DOMAIN, BACKEND_SERVER, and EMAIL if not set
prompt_if_not_set DOMAIN "Enter your domain: "
prompt_if_not_set BACKEND_SERVER "Enter backend server URL (e.g., http://127.0.0.1:8080): "
prompt_if_not_set EMAIL "Enter your email for SSL certificate registration: "

# Update packages and install Nginx
echo "Updating packages and installing Nginx..."
sudo apt update
sudo apt install -y nginx || { echo "Failed to install Nginx"; exit 1; }

# Install Certbot
echo "Installing Certbot..."
sudo apt install -y certbot python3-certbot-nginx || { echo "Failed to install Certbot"; exit 1; }

# Configure Nginx as a reverse proxy
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
echo "Configuring Nginx for $DOMAIN..."
sudo tee $NGINX_CONF > /dev/null <<EOL
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass $BACKEND_SERVER;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

# Create symbolic link to sites-enabled
echo "Creating symbolic link for site configuration..."
sudo ln -s $NGINX_CONF /etc/nginx/sites-enabled/

# Validate Nginx configuration and reload
echo "Validating and reloading Nginx..."
sudo nginx -t && sudo systemctl reload nginx || { echo "Nginx configuration error"; exit 1; }

# Obtain and configure SSL certificate using Certbot
echo "Obtaining SSL certificate for $DOMAIN..."
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL || { echo "Failed to obtain SSL certificate"; exit 1; }

echo "Setup completed successfully!"

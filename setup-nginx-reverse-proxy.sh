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
prompt_if_not_set BACKEND_SERVER "Enter backend server URL (e.g., http://hidden-server-ip:port): "
prompt_if_not_set EMAIL "Enter your email for SSL certificate registration: "

# Ensure BACKEND_SERVER starts with http:// or https://
if [[ ! "$BACKEND_SERVER" =~ ^https?:// ]]; then
    BACKEND_SERVER="http://$BACKEND_SERVER"
    echo "Added 'http://' to BACKEND_SERVER: $BACKEND_SERVER"
fi

# Update packages and install Nginx
echo "Updating packages and installing Nginx..."
sudo apt update
sudo apt install -y nginx || { echo "Failed to install Nginx"; exit 1; }

# Install Certbot
echo "Installing Certbot..."
sudo apt install -y certbot python3-certbot-nginx || { echo "Failed to install Certbot"; exit 1; }

# Initial Nginx config (port 80 only, no SSL yet)
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
echo "Configuring Nginx for $DOMAIN on port 80 (initial setup)..."
sudo tee $NGINX_CONF > /dev/null <<EOL
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        return 200 "Temporary config for Certbot.";
    }
}
EOL

# Create symbolic link to sites-enabled
echo "Creating symbolic link for site configuration..."
sudo ln -s $NGINX_CONF /etc/nginx/sites-enabled/

# Validate and reload Nginx (initial setup, container-friendly)
echo "Validating and reloading Nginx (initial)..."
sudo nginx -t || { echo "Initial Nginx syntax error"; exit 1; }
sudo service nginx restart || { echo "Failed to start Nginx"; exit 1; }

# Obtain SSL certificate using Certbot
echo "Obtaining SSL certificate for $DOMAIN..."
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL || { echo "Failed to obtain SSL certificate. Check /var/log/letsencrypt/letsencrypt.log for details."; exit 1; }

# Update Nginx config with SSL on 8443
echo "Updating Nginx config for $DOMAIN: 80 -> 8443 with SSL..."
sudo tee $NGINX_CONF > /dev/null <<EOL
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host:8443\$request_uri;
}

server {
    listen 8443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location /sub/ {
        proxy_pass $BACKEND_SERVER;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        # add_header moved-permanently-to "https://newdomain.com/sub/new-id";
    }

    location / {
        return 404;
    }
}
EOL

# Final validation and reload (container-friendly)
echo "Final validation and reload of Nginx..."
sudo nginx -t || { echo "Final Nginx syntax error"; exit 1; }
sudo service nginx restart || { echo "Failed to restart Nginx"; exit 1; }

echo "Setup completed successfully! Nginx redirects 80 to 8443, leaving 443 free."

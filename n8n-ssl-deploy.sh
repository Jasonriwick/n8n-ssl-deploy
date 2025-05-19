#!/bin/bash

# -----------------------------------------
# 🚀 n8n One-Click Install Script (SSL + Backup)
# -----------------------------------------
# Tested on Ubuntu 24.04 LTS - 1GB RAM / 20GB disk
# Author: Jasonriwick (https://github.com/Jasonriwick)
# -----------------------------------------

DOMAIN="thesamelife.click"
EMAIL="your-email@example.com"
N8N_DIR="/opt/n8n"
BACKUP_DIR="/opt/n8n/backup"

echo "🔧 Updating system..."
apt update && apt upgrade -y

echo "📦 Installing dependencies..."
apt install -y curl gnupg2 ca-certificates lsb-release apt-transport-https software-properties-common fail2ban ufw nginx docker.io docker-compose certbot python3-certbot-nginx

echo "🔐 Setting up firewall..."
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

echo "📁 Creating N8N directory..."
mkdir -p "$N8N_DIR" "$BACKUP_DIR"

echo "🧾 Creating docker-compose.yml..."
cat <<EOF > "$N8N_DIR/docker-compose.yml"
version: '3'
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n
    container_name: n8n
    ports:
      - "5678:5678"
    volumes:
      - ./n8n_data:/home/node/.n8n
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=securepassword123
      - N8N_HOST=$DOMAIN
      - N8N_PORT=5678
      - WEBHOOK_URL=https://$DOMAIN/
      - TZ=Asia/Shanghai
    restart: always
EOF

echo "▶️ Starting n8n container..."
cd "$N8N_DIR"
docker compose up -d

echo "🌐 Configuring Nginx reverse proxy..."
cat <<EOF > /etc/nginx/sites-available/n8n
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -s /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

echo "🔐 Obtaining SSL certificate..."
certbot --nginx -d "$DOMAIN" --agree-tos --redirect --email "$EMAIL" --non-interactive

echo "📅 Setting up daily backup..."
cat <<EOF > /usr/local/bin/n8n-backup.sh
#!/bin/bash
tar -czf "$BACKUP_DIR/n8n-\$(date +%F).tar.gz" "$N8N_DIR/n8n_data"
EOF

chmod +x /usr/local/bin/n8n-backup.sh
echo "0 3 * * * root /usr/local/bin/n8n-backup.sh" >> /etc/crontab

echo "✅ Deployment complete! Access n8n at: https://$DOMAIN"

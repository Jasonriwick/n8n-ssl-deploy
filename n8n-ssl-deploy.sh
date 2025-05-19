#!/bin/bash

echo "🔧 启动 N8N + SSL 自动部署..."

read -p "🌐 请输入你的域名 (如 thesamelife.click): " DOMAIN
read -p "📧 请输入用于 SSL 的邮箱: " EMAIL

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
  echo "❌ 域名和邮箱不能为空，脚本终止。"
  exit 1
fi

# 安装必要工具
apt update && apt install -y curl gnupg2 ca-certificates lsb-release apt-transport-https   software-properties-common ufw nginx docker.io docker-compose certbot python3-certbot-nginx

# 配置防火墙
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

# 启动 Docker
systemctl enable docker
systemctl start docker

# 创建挂载目录
mkdir -p /home/n8n/n8n
mkdir -p /home/n8n/n8ndata
mkdir -p /home/n8n/backups
chmod -R 777 /home/n8n

# 写入 docker-compose.yml
cat > /home/n8n/docker-compose.yml <<EOF
version: "3.7"
services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=admin123
      - N8N_HOST=$DOMAIN
      - N8N_PORT=443
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://$DOMAIN/
      - TZ=Asia/Shanghai
    volumes:
      - /home/n8n/n8n:/home/node/.n8n
      - /home/n8n/n8ndata:/data
EOF

# 启动 n8n 服务
cd /home/n8n
docker compose up -d

# Nginx 配置
cat > /etc/nginx/sites-available/n8n <<EOF
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

# SSL 证书签发
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

# 写入备份脚本
cat <<EOF > /home/n8n/backup.sh
#!/bin/bash
DATE=\$(date +%F_%T)
tar czf /home/n8n/backups/n8n_backup_\$DATE.tar.gz -C /home/n8n/n8n . -C /home/n8n/n8ndata .
EOF

chmod +x /home/n8n/backup.sh

# 设置每日凌晨2点自动备份
(crontab -l 2>/dev/null; echo "0 2 * * * /home/n8n/backup.sh") | crontab -

echo ""
echo "✅ 部署完成！你现在可以访问: https://$DOMAIN"
echo "🔐 用户: admin / 密码: admin123"
echo "📁 数据目录: /home/n8n/n8n"
echo "📁 工作流目录: /home/n8n/n8ndata"
echo "📦 备份目录: /home/n8n/backups"

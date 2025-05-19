#!/bin/bash

echo "🔧 开始 N8N + Nginx + SSL 一键部署..."

read -p "🌐 请输入你的域名 (如 thesamelife.click): " DOMAIN
read -p "📧 请输入用于 SSL 的邮箱: " EMAIL

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
  echo "❌ 域名和邮箱不能为空，脚本终止。"
  exit 1
fi

echo "📦 正在安装依赖..."

apt update && apt install -y \
  curl gnupg2 ca-certificates lsb-release apt-transport-https \
  software-properties-common ufw nginx docker.io docker-compose \
  certbot python3-certbot-nginx

# Docker 服务启动并加入开机启动
systemctl enable docker
systemctl start docker

# 添加 docker compose 别名（兼容新版）
if ! command -v docker-compose >/dev/null 2>&1 && command -v docker compose >/dev/null 2>&1; then
  ln -s $(which docker) /usr/local/bin/docker-compose
fi

echo "🧱 清理旧容器、端口和网络..."
docker stop n8n >/dev/null 2>&1
docker rm n8n >/dev/null 2>&1
PID=$(lsof -t -i:5678)
[ -n "$PID" ] && kill -9 $PID
docker network rm n8n-network >/dev/null 2>&1
docker network create n8n-network

echo "📁 创建数据目录..."
mkdir -p /home/n8n/n8n
mkdir -p /home/n8n/n8ndata
mkdir -p /home/n8n/backups
chmod -R 777 /home/n8n

echo "⚙️ 配置防火墙..."
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

echo "📝 写入 docker-compose.yml..."
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
      - WEBHOOK_URL=https://$DOMAIN/
      - GENERIC_TIMEZONE=Asia/Shanghai
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - N8N_PROXY_HOPS=1
    networks:
      - n8n-network
    volumes:
      - /home/n8n/n8n:/home/node/.n8n
      - /home/n8n/n8ndata:/data
networks:
  n8n-network:
    external: true
EOF

echo "🚀 启动 n8n 容器..."
cd /home/n8n
docker compose up -d

echo "🌐 配置 Nginx..."

cat > /etc/nginx/sites-available/n8n <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://localhost:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

echo "🔐 申请 Let's Encrypt SSL..."
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

echo "💾 写入备份脚本..."
cat <<EOF > /home/n8n/backup.sh
#!/bin/bash
DATE=\$(date +%F_%T)
tar czf /home/n8n/backups/n8n_backup_\$DATE.tar.gz -C /home/n8n/n8n . -C /home/n8n/n8ndata .
EOF
chmod +x /home/n8n/backup.sh
(crontab -l 2>/dev/null; echo "0 2 * * * /home/n8n/backup.sh") | crontab -

echo ""
echo "✅ n8n 已成功部署并启用 SSL！"
echo "🔗 访问地址: https://$DOMAIN"
echo "🔐 用户名: admin"
echo "🔑 密码: admin123"
echo "📂 数据目录: /home/n8n/n8n"
echo "📂 工作流: /home/n8n/n8ndata"
echo "📦 备份目录: /home/n8n/backups"

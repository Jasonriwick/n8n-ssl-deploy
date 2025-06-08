#!/bin/bash

echo "🔧 开始 N8N + Nginx + SSL 一键部署..."

read -p "🌐 请输入你的域名 (如 thesamelife.click): " DOMAIN
read -p "📧 请输入用于 SSL 的邮箱: " EMAIL

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
  echo "❌ 域名和邮箱不能为空，脚本终止。"
  exit 1
fi

echo "📦 安装依赖..."
apt update && apt install -y \
  curl gnupg2 ca-certificates lsb-release apt-transport-https \
  software-properties-common ufw nginx docker.io docker-compose \
  certbot python3-certbot-nginx unzip

# Docker 服务
systemctl enable docker
systemctl start docker

# Docker Compose 命令兼容处理
if ! command -v docker-compose >/dev/null 2>&1 && command -v docker compose >/dev/null 2>&1; then
  ln -s $(which docker) /usr/local/bin/docker-compose
fi

# 清理旧容器
docker stop n8n >/dev/null 2>&1
docker rm n8n >/dev/null 2>&1
PID=$(lsof -t -i:5678)
[ -n "$PID" ] && kill -9 $PID
docker network rm n8n-network >/dev/null 2>&1
docker network create n8n-network

# 创建目录
mkdir -p /home/n8n/n8n
mkdir -p /home/n8n/n8ndata
mkdir -p /home/n8n/backups
chmod -R 777 /home/n8n

# 防火墙
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

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

cd /home/n8n
docker compose up -d

# 写入 Nginx 配置（带 WebSocket 支持）
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

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# 软链 + 清理冲突
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n
nginx -t && systemctl reload nginx

# SSL 签发
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

# 写入备份脚本
cat <<EOF > /home/n8n/backup.sh
#!/bin/bash
DATE=\$(date +%F_%T)
tar czf /home/n8n/backups/n8n_backup_\$DATE.tar.gz -C /home/n8n/n8n . -C /home/n8n/n8ndata .
EOF
chmod +x /home/n8n/backup.sh
(crontab -l 2>/dev/null; echo "0 2 * * * /home/n8n/backup.sh") | crontab -

# 写入升级脚本
cat <<EOF > /home/n8n/upgrade-n8n.sh
#!/bin/bash

echo "🔄 开始升级 n8n 到最新版..."

cd /home/n8n || { echo "❌ 目录 /home/n8n 不存在！"; exit 1; }

echo "📦 拉取 n8n 最新版镜像..."
docker pull n8nio/n8n:latest

echo "🛑 停止当前 n8n 容器..."
docker compose down

echo "🚀 启动新版 n8n 容器..."
docker compose up -d

echo "✅ n8n 升级完成！当前版本："
docker ps --filter name=n8n
EOF

chmod +x /home/n8n/upgrade-n8n.sh

echo ""
echo "✅ n8n 部署完成！访问地址: https://$DOMAIN"
echo "🔐 用户：admin / 密码：admin123"
echo "📂 数据目录: /home/n8n/n8n"
echo "📂 工作流目录: /home/n8n/n8ndata"
echo "📦 备份目录: /home/n8n/backups"
echo "⬆️ 以后升级 n8n 请运行：/home/n8n/upgrade-n8n.sh"

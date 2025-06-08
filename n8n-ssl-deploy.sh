#!/bin/bash

echo "🔧 开始 N8N + OpenResty (Nginx+Lua) + SSL + 自定义登录页 + 安全强化版一键部署..."

# 检测系统信息
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
  VERSION_ID=${VERSION_ID%%.*}
else
  echo "❌ 无法检测操作系统信息，退出。"
  exit 1
fi

echo "🔍 检测到系统: $OS $VERSION_ID"

# 系统版本兼容检测
case "$OS" in
  ubuntu)
    if [ "$VERSION_ID" -lt 20 ]; then
      echo "❌ Ubuntu 版本太旧，要求 20.04 或更高版本。"
      exit 1
    fi
    ;;
  *)
    echo "❌ 不支持的系统: $OS。仅支持 Ubuntu 20.04+。"
    exit 1
    ;;
esac

# 用户输入
read -p "🌐 请输入你的域名 (如 thesamelife.click): " DOMAIN
read -p "📧 请输入用于 SSL 的邮箱: " EMAIL

read -p "👤 请输入登录用户名（留空默认 admin）: " BASIC_USER
BASIC_USER=${BASIC_USER:-admin}

read -s -p "🔒 请输入登录密码（留空默认 admin123）: " BASIC_PASSWORD
BASIC_PASSWORD=${BASIC_PASSWORD:-admin123}
echo ""

read -p "🤖 是否开启 N8N 自动更新？(yes/no): " AUTO_UPDATE

# 🚨 检查并卸载系统自带 Nginx，防止冲突
if systemctl list-units --type=service | grep -q nginx; then
  echo "⚠️ 检测到系统已安装 Nginx，准备卸载..."
  systemctl stop nginx
  systemctl disable nginx

  if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt purge -y nginx nginx-common nginx-core
    apt autoremove -y
  elif [[ "$OS" == "centos" || "$OS" == "rocky" || "$OS" == "almalinux" || "$OS" == "rhel" ]]; then
    yum remove -y nginx nginx-common nginx-core
  elif [[ "$OS" == "amzn" ]]; then
    yum remove -y nginx
  fi

  rm -rf /etc/nginx
  echo "✅ 已卸载系统自带 Nginx，继续安装 OpenResty..."
fi

# 安装依赖
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y curl wget ca-certificates gnupg2 lsb-release apt-transport-https \
  software-properties-common sudo unzip ufw cron docker.io docker-compose jq \
  certbot python3-certbot-nginx fail2ban openssl gnupg gnupg2 gnupg-agent

# 安装 OpenResty
wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
codename=$(lsb_release -sc)
echo "deb http://openresty.org/package/ubuntu $codename main" | sudo tee /etc/apt/sources.list.d/openresty.list
apt update
apt install -y openresty

# 启动 OpenResty
systemctl enable openresty
systemctl start openresty

# 启动 Docker
systemctl enable docker
systemctl start docker

# 防火墙开放 22, 80, 443
ufw allow 22/tcp
ufw allow 80,443/tcp
ufw --force enable

# 启用 Swap
if [ $(free -m | awk '/^Mem:/{print $2}') -lt 2048 ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# 写入 n8n 的 Nginx 配置，基于 OpenResty（带 Lua）
cat > /usr/local/openresty/nginx/conf/conf.d/n8n.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location /login.html {
        root /home/n8n-auth/;
    }

    location /login.css {
        root /home/n8n-auth/;
    }

    location / {
        access_by_lua_file /home/n8n-auth/auth.lua;
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

# 保存 Nginx 配置完成后，申请 SSL
certbot certonly --webroot -w /var/www/html -d $DOMAIN --email $EMAIL --agree-tos --non-interactive

# 写 HTTPS 配置，强制跳转 HTTPS
cat > /usr/local/openresty/nginx/conf/conf.d/n8n-ssl.conf <<EOF
server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location /login.html {
        root /home/n8n-auth/;
    }

    location /login.css {
        root /home/n8n-auth/;
    }

    location / {
        access_by_lua_file /home/n8n-auth/auth.lua;
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

server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
EOF

# 保存账号密码
HASHED_USER=$(echo -n "$BASIC_USER" | openssl dgst -sha256 | awk '{print $2}')
HASHED_PASS=$(echo -n "$BASIC_PASSWORD" | openssl dgst -sha256 | awk '{print $2}')
echo "$HASHED_USER:$HASHED_PASS" > /home/n8n-auth/.credentials
echo "$DOMAIN" > /home/n8n-auth/.domain
echo "$BASIC_USER" > /home/n8n-auth/.basic_user
echo "$BASIC_PASSWORD" > /home/n8n-auth/.basic_password

# Docker Compose 配置 n8n
cat > /home/n8n/docker-compose.yml <<EOF
version: "3.8"
services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports: []
    environment:
      - N8N_BASIC_AUTH_ACTIVE=false
      - N8N_HOST=$DOMAIN
      - WEBHOOK_URL=https://$DOMAIN/
      - GENERIC_TIMEZONE=Asia/Shanghai
    volumes:
      - /home/n8n/n8n:/home/node/.n8n
      - /home/n8n/n8ndata:/data
networks:
  default:
    external:
      name: n8n-network
EOF

# 启动 Docker 容器
docker network create n8n-network || true
cd /home/n8n
docker compose up -d

# 启动 OpenResty (Nginx)
systemctl enable openresty
systemctl restart openresty

# 备份脚本 backup.sh
cat > /home/n8n/backup.sh <<'EOF'
#!/bin/bash
DATE=$(date +%F_%T)
tar czf /home/n8n/backups/n8n_backup_$DATE.tar.gz -C /home/n8n/n8n . -C /home/n8n/n8ndata .
EOF
chmod +x /home/n8n/backup.sh

# 自动清理 14 天前备份 clean-backups.sh
cat > /home/n8n/clean-backups.sh <<'EOF'
#!/bin/bash
find /home/n8n/backups/ -name "*.tar.gz" -type f -mtime +14 -exec rm -f {} \;
EOF
chmod +x /home/n8n/clean-backups.sh

# 自动检测新版本 check-update.sh
cat > /home/n8n/check-update.sh <<'EOF'
#!/bin/bash
LATEST=$(curl -s https://hub.docker.com/v2/repositories/n8nio/n8n/tags | jq -r '.results[0].name')
CURRENT=$(docker inspect n8n --format '{{ index .Config.Image }}' | cut -d: -f2)
if [ "$LATEST" != "$CURRENT" ]; then
  echo "UPDATE_AVAILABLE" > /home/n8n/update.flag
else
  rm -f /home/n8n/update.flag
fi
EOF
chmod +x /home/n8n/check-update.sh

# 自动升级脚本 auto-upgrade.sh
cat > /home/n8n/auto-upgrade.sh <<'EOF'
#!/bin/bash
if [ -f /home/n8n/update.flag ]; then
  bash /home/n8n/backup.sh
  docker pull n8nio/n8n
  docker compose down
  docker compose up -d
  rm -f /home/n8n/update.flag
fi
EOF
chmod +x /home/n8n/auto-upgrade.sh

# 手动升级脚本 upgrade-n8n.sh
cat > /home/n8n/upgrade-n8n.sh <<'EOF'
#!/bin/bash
bash /home/n8n/backup.sh
docker pull n8nio/n8n
docker compose down
docker compose up -d
EOF
chmod +x /home/n8n/upgrade-n8n.sh

# 回滚脚本 restore-n8n.sh
cat > /home/n8n/restore-n8n.sh <<'EOF'
#!/bin/bash
BACKUP_DIR="/home/n8n/backups"
N8N_DIR="/home/n8n/n8n"
N8NDATA_DIR="/home/n8n/n8ndata"

echo "📦 可用备份列表："
ls -1t $BACKUP_DIR/*.tar.gz | nl

read -p "请输入要回滚的备份编号（如 1）: " CHOICE
SELECTED_BACKUP=$(ls -1t $BACKUP_DIR/*.tar.gz | sed -n "${CHOICE}p")

if [ -z "$SELECTED_BACKUP" ]; then
  echo "❌ 无效选择，退出。"
  exit 1
fi

read -p "⚠️ 确定要回滚吗？这将覆盖当前数据！(yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "❌ 已取消回滚。"
  exit 1
fi

echo "📦 回滚前正在备份当前数据..."
bash /home/n8n/backup.sh

echo "🧹 清空现有数据..."
docker compose down
rm -rf $N8N_DIR/*
rm -rf $N8NDATA_DIR/*

echo "🔄 正在恢复备份..."
tar -xzf $SELECTED_BACKUP -C $N8N_DIR --strip-components=1
tar -xzf $SELECTED_BACKUP -C $N8NDATA_DIR --strip-components=1

docker compose up -d
echo "✅ 回滚完成！n8n 已恢复到选定备份版本。"
EOF
chmod +x /home/n8n/restore-n8n.sh

# 重置账号密码 reset-credentials.sh
cat > /home/n8n-auth/reset-credentials.sh <<'EOF'
#!/bin/bash
read -p "👤 新用户名: " NEW_USER
read -s -p "🔒 新密码: " NEW_PASS
echo ""
HASHED_USER=$(echo -n "$NEW_USER" | openssl dgst -sha256 | awk '{print $2}')
HASHED_PASS=$(echo -n "$NEW_PASS" | openssl dgst -sha256 | awk '{print $2}')
echo "$HASHED_USER:$HASHED_PASS" > /home/n8n-auth/.credentials
echo "$NEW_USER" > /home/n8n-auth/.basic_user
echo "$NEW_PASS" > /home/n8n-auth/.basic_password
openresty -t && systemctl reload openresty
echo "✅ 账号密码重置成功！"
EOF
chmod +x /home/n8n-auth/reset-credentials.sh

# 查看账号密码 view-credentials.sh
cat > /home/n8n-auth/view-credentials.sh <<'EOF'
#!/bin/bash
echo "当前登录信息（加密）:"
cat /home/n8n-auth/.credentials
EOF
chmod +x /home/n8n-auth/view-credentials.sh

# 查看部署信息 n8n-show-info.sh
cat > /home/n8n-auth/n8n-show-info.sh <<'EOF'
#!/bin/bash
DOMAIN_FILE="/home/n8n-auth/.domain"
USER_FILE="/home/n8n-auth/.basic_user"
PASS_FILE="/home/n8n-auth/.basic_password"

if [ ! -f "$DOMAIN_FILE" ] || [ ! -f "$USER_FILE" ] || [ ! -f "$PASS_FILE" ]; then
  echo "❌ 无法找到部署信息文件。"
  exit 1
fi

DOMAIN=$(cat $DOMAIN_FILE)
BASIC_USER=$(cat $USER_FILE)
BASIC_PASSWORD=$(cat $PASS_FILE)

echo ""
echo "✅ n8n 自定义登录部署信息"
echo "🌐 访问地址: https://$DOMAIN"
echo "📝 当前登录用户名: $BASIC_USER"
echo "📝 当前登录密码: $BASIC_PASSWORD"
echo "🚀 自定义登录页面已启用，首次访问输入账号密码后进入 n8n。"
echo "🔧 重置账号密码脚本: /home/n8n-auth/reset-credentials.sh"
echo "🔍 查看当前账号密码脚本: /home/n8n-auth/view-credentials.sh"
echo "📦 手动备份脚本: /home/n8n/backup.sh"
echo "💡 手动回滚脚本: /home/n8n/restore-n8n.sh"
echo "🚀 手动升级脚本: /home/n8n/upgrade-n8n.sh"
EOF
chmod +x /home/n8n-auth/n8n-show-info.sh

# Crontab 定时任务
(crontab -l 2>/dev/null; echo "0 2 * * * /home/n8n/backup.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * * /home/n8n/clean-backups.sh") | crontab -
if [ "$AUTO_UPDATE" == "yes" ]; then
  (crontab -l 2>/dev/null; echo "0 8,12,20 * * * /home/n8n/check-update.sh") | crontab -
  (crontab -l 2>/dev/null; echo "0 4 * * * /home/n8n/auto-upgrade.sh") | crontab -
fi

# 重启 OpenResty
openresty -t && systemctl reload openresty

# 输出部署总结
echo ""
echo "✅ n8n 自定义登录部署完成！访问地址: https://$DOMAIN"
echo "📝 当前登录用户名: $BASIC_USER"
echo "📝 当前登录密码: $BASIC_PASSWORD"
echo "🚀 自定义登录页面已启用，首次访问输入账号密码后进入 n8n。"
echo "🔧 重置账号密码脚本: /home/n8n-auth/reset-credentials.sh"
echo "🔍 查看当前账号密码脚本: /home/n8n-auth/view-credentials.sh"
echo "📦 手动备份脚本: /home/n8n/backup.sh"
echo "🗑️ 自动清理14天前备份脚本: /home/n8n/clean-backups.sh"
echo "💡 手动回滚脚本: /home/n8n/restore-n8n.sh"
echo "🚀 手动升级脚本: /home/n8n/upgrade-n8n.sh"
echo "🔎 查看部署信息脚本: /home/n8n-auth/n8n-show-info.sh"

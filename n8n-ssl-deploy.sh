#!/bin/bash
set -e

LOG_FILE="/var/log/n8n-deploy.log"
echo "🔧 启动 N8N 一键部署（SSL + 登录认证 + 动效页）..." | tee -a "$LOG_FILE"

# docker compose fallback 函数
docker_compose() {
  if command -v docker compose &>/dev/null; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}

# 添加定时任务去重函数
add_cron() {
  (crontab -l 2>/dev/null | grep -v "$1"; echo "$1") | crontab -
}

# 检测系统信息
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
  VERSION_ID=${VERSION_ID%%.*}
else
  echo "❌ 无法检测系统，退出。" | tee -a "$LOG_FILE"
  exit 1
fi

echo "🔍 检测系统: $OS $VERSION_ID" | tee -a "$LOG_FILE"

case "$OS" in
  ubuntu)   [ "$VERSION_ID" -lt 20 ] && echo "❌ Ubuntu需20+" && exit 1 ;;
  debian)   [ "$VERSION_ID" -lt 10 ] && echo "❌ Debian需10+" && exit 1 ;;
  centos|rocky|almalinux|rhel) [ "$VERSION_ID" -lt 8 ] && echo "❌ CentOS需8+" && exit 1 ;;
  amzn)     echo "✅ Amazon Linux 2 通过" ;;
  *)        echo "❌ 不支持的系统: $OS" && exit 1 ;;
esac

# 用户输入
read -p "🌐 输入域名 (如 n8n.example.com): " DOMAIN
read -p "📧 输入邮箱 (用于SSL): " EMAIL
read -p "👤 登录用户名 (默认admin): " BASIC_USER
BASIC_USER=${BASIC_USER:-admin}
read -s -p "🔒 登录密码 (默认admin123): " BASIC_PASSWORD
BASIC_PASSWORD=${BASIC_PASSWORD:-admin123}
echo ""
read -p "🤖 是否开启自动更新？(yes/no): " AUTO_UPDATE

# 安装依赖函数
install_dependencies() {
  echo "📦 安装系统依赖..." | tee -a "$LOG_FILE"
  if command -v apt &>/dev/null; then
    apt update -y && apt install -y \
      curl wget gnupg2 ca-certificates sudo unzip jq lsof \
      nginx certbot python3-certbot-nginx ufw \
      nodejs npm cron software-properties-common
  elif command -v yum &>/dev/null; then
    yum install -y curl wget gnupg2 ca-certificates sudo unzip jq lsof \
      nginx certbot python3-certbot-nginx ufw \
      nodejs npm cronie epel-release
  elif command -v dnf &>/dev/null; then
    dnf install -y curl wget gnupg2 ca-certificates sudo unzip jq lsof \
      nginx certbot python3-certbot-nginx ufw \
      nodejs npm cronie
  fi

  systemctl enable nginx && systemctl start nginx
}

# 安装 Docker 函数
install_docker() {
  echo "🐳 安装 Docker..." | tee -a "$LOG_FILE"
  if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | bash
  fi
  if ! docker compose version &>/dev/null && ! docker-compose version &>/dev/null; then
    mkdir -p ~/.docker/cli-plugins
    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) \
      -o ~/.docker/cli-plugins/docker-compose
    chmod +x ~/.docker/cli-plugins/docker-compose
  fi

  systemctl enable docker && systemctl start docker
}

# 开始安装
install_dependencies
install_docker

# 创建必要目录
mkdir -p /home/n8n/n8n /home/n8n-auth/public /home/n8n/backups

# 生成 docker-compose.yml
cat <<EOF > /home/n8n/docker-compose.yml
version: "3.7"
services:
  n8n:
    image: n8nio/n8n
    container_name: n8n-n8n-1
    restart: always
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$BASIC_USER
      - N8N_BASIC_AUTH_PASSWORD=$BASIC_PASSWORD
      - N8N_HOST=$DOMAIN
      - WEBHOOK_TUNNEL_URL=https://$DOMAIN
      - N8N_PORT=5678
      - NODE_ENV=production
    volumes:
      - /home/n8n/n8n:/home/node/.n8n
    networks:
      - n8n_default
networks:
  n8n_default:
    driver: bridge
EOF

# 写入认证服务 server.js
cat <<EOF > /home/n8n-auth/server.js
const express = require("express");
const app = express();
const basicAuth = require("express-basic-auth");
const path = require("path");

app.use(
  basicAuth({
    users: { "${BASIC_USER}": "${BASIC_PASSWORD}" },
    challenge: true,
  })
);
app.use(express.static(path.join(__dirname, "public")));
app.listen(80, () => console.log("Auth page running on port 80"));
EOF

# 写入登录动效页面 login.html
cat <<EOF > /home/n8n-auth/public/login.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Welcome to n8n</title>
  <style>
    body {
      margin: 0;
      background: radial-gradient(#2c3e50, #000);
      color: white;
      font-family: sans-serif;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
      animation: fadeIn 2s ease-in-out;
    }
    h1 {
      font-size: 3rem;
      animation: float 3s infinite alternate;
    }
    @keyframes float {
      0% { transform: translateY(0); }
      100% { transform: translateY(-20px); }
    }
    @keyframes fadeIn {
      from { opacity: 0; }
      to { opacity: 1; }
    }
  </style>
</head>
<body>
  <h1>Welcome to n8n 🚀</h1>
</body>
</html>
EOF

# 安装 Node.js 依赖
cd /home/n8n-auth
npm init -y
npm install express express-basic-auth

# 创建 systemd 启动文件
cat <<EOF > /etc/systemd/system/n8n-auth.service
[Unit]
Description=Custom Login Page for n8n
After=network.target

[Service]
ExecStart=/usr/bin/node /home/n8n-auth/server.js
Restart=always
User=root
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable n8n-auth
systemctl start n8n-auth

# 写入 Nginx 配置
cat <<EOF > /etc/nginx/conf.d/n8n.conf
server {
  listen 80;
  server_name $DOMAIN;

  location / {
    return 301 https://\$host\$request_uri;
  }
}

server {
  listen 443 ssl;
  server_name $DOMAIN;

  ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

  gzip on;
  gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

  location / {
    proxy_pass http://localhost:5678;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF

# 获取 SSL 证书
certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos --non-interactive
systemctl reload nginx

# 自动备份脚本
cat <<EOF > /home/n8n/backup.sh
#!/bin/bash
TIMESTAMP=\$(date +"%Y%m%d-%H%M%S")
tar -czf /home/n8n/backups/n8n_backup_\$TIMESTAMP.tar.gz -C /home/n8n/n8n .
ln -sf /home/n8n/backups/n8n_backup_\$TIMESTAMP.tar.gz /home/n8n/backups/n8n_backup_latest.tar.gz
EOF
chmod +x /home/n8n/backup.sh

# 清理旧备份脚本（保留10天）
cat <<EOF > /home/n8n/clean-backups.sh
#!/bin/bash
find /home/n8n/backups/ -name "*.tar.gz" -type f -mtime +10 -exec rm {} \;
EOF
chmod +x /home/n8n/clean-backups.sh

# 拉取镜像检查脚本
cat <<EOF > /home/n8n/check-update.sh
#!/bin/bash
docker pull n8nio/n8n >> /var/log/n8n-update.log 2>&1
EOF
chmod +x /home/n8n/check-update.sh

# 自动升级脚本（含备份）
cat <<EOF > /home/n8n/auto-upgrade.sh
#!/bin/bash
/home/n8n/backup.sh
docker_compose down
docker pull n8nio/n8n
docker_compose up -d
EOF
chmod +x /home/n8n/auto-upgrade.sh

# 手动升级脚本
cat <<EOF > /home/n8n/upgrade-n8n.sh
#!/bin/bash
/home/n8n/auto-upgrade.sh
EOF
chmod +x /home/n8n/upgrade-n8n.sh

# 添加定时任务（去重）
add_cron "0 3 * * * /home/n8n/backup.sh"
add_cron "0 4 * * * /home/n8n/clean-backups.sh"
add_cron "0 5 * * * /home/n8n/check-update.sh"

if [[ "$AUTO_UPDATE" == "yes" ]]; then
  add_cron "0 6 * * * /home/n8n/auto-upgrade.sh"
fi

# 启动所有服务
cd /home/n8n
docker_compose up -d
systemctl restart nginx
sleep 2
systemctl restart n8n-auth

# 输出完成信息
AUTO_STATUS=$( [[ "$AUTO_UPDATE" == "yes" ]] && echo "已启用" || echo "未启用" )

cat <<EOM

✅ n8n 已部署成功！

🌍 访问地址: https://$DOMAIN
🔐 登录账号: $BASIC_USER
🔑 登录密码: $BASIC_PASSWORD

📦 自动备份脚本: /home/n8n/backup.sh
🧹 清理旧备份脚本: /home/n8n/clean-backups.sh
🔍 镜像更新检测: /home/n8n/check-update.sh
🚀 自动升级脚本: /home/n8n/auto-upgrade.sh
🔧 手动升级脚本: /home/n8n/upgrade-n8n.sh
📅 自动更新状态: $AUTO_STATUS

📁 数据目录: /home/n8n/n8n
🎨 登录页面: https://$DOMAIN/login.html
🛡️ 登录认证服务已启用 (systemd)

⚡ Powered by John Script - 安全 · 自动化 · 稳定

EOM

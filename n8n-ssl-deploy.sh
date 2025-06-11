#!/bin/bash

set -e

LOG_FILE="/var/log/n8n-deploy.log"
echo "🔧 开始 John 一键部署版 N8N (Docker + Nginx + SSL + 登录认证 + 动效登录页) ..." | tee -a "$LOG_FILE"

# 检测系统信息
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
  VERSION_ID=${VERSION_ID%%.*}
else
  echo "❌ 无法检测操作系统信息，退出。" | tee -a "$LOG_FILE"
  exit 1
fi

echo "🔍 检测到系统: $OS $VERSION_ID" | tee -a "$LOG_FILE"

# 系统版本兼容检测
case "$OS" in
  ubuntu)
    if [ "$VERSION_ID" -lt 20 ]; then
      echo "❌ Ubuntu 版本太旧，要求 20.04 或更高版本。" | tee -a "$LOG_FILE"
      exit 1
    fi
    ;;
  debian)
    if [ "$VERSION_ID" -lt 10 ]; then
      echo "❌ Debian 版本太旧，要求 10 或更高版本。" | tee -a "$LOG_FILE"
      exit 1
    fi
    ;;
  centos|rocky|almalinux|rhel)
    if [ "$VERSION_ID" -lt 8 ]; then
      echo "❌ RedHat 系列版本太旧，要求 8 或更高版本。" | tee -a "$LOG_FILE"
      exit 1
    fi
    ;;
  amzn)
    echo "✅ 检测到 Amazon Linux 2，继续。" | tee -a "$LOG_FILE"
    ;;
  *)
    echo "❌ 不支持的系统: $OS。建议使用 Ubuntu, Debian, CentOS 8+。" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac

# 用户输入
read -p "🌐 请输入你的域名 (如 example.com): " DOMAIN
read -p "📧 请输入用于 SSL 的邮箱: " EMAIL
read -p "👤 请输入登录用户名（留空默认 admin）: " BASIC_USER
BASIC_USER=${BASIC_USER:-admin}
read -s -p "🔒 请输入登录密码（留空默认 admin123）: " BASIC_PASSWORD
BASIC_PASSWORD=${BASIC_PASSWORD:-admin123}
echo ""
read -p "🤖 是否开启 N8N 自动更新？(yes/no): " AUTO_UPDATE

# 日志函数
debug_log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$LOG_FILE"
}

# 健康检测函数
health_check() {
  local retries=3
  local success=false
  for ((i=1; i<=retries; i++)); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN || echo "000")
    if [[ "$STATUS" == "200" || "$STATUS" == "302" ]]; then
      echo "✅ 第 $i 次检测成功，网站状态：$STATUS" | tee -a "$LOG_FILE"
      success=true
      break
    else
      echo "⚠️ 第 $i 次检测失败，状态码：$STATUS" | tee -a "$LOG_FILE"
      sleep 5
    fi
  done

  if [ "$success" = false ]; then
    echo "❌ 多次检测失败，开始自修复..." | tee -a "$LOG_FILE"
    nginx -t || echo "⚠️ Nginx 配置异常" | tee -a "$LOG_FILE"
    systemctl restart nginx || true
    docker compose down || docker-compose down
    docker compose up -d || docker-compose up -d
    sleep 5
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN || echo "000")
    if [[ "$STATUS" == "200" || "$STATUS" == "302" ]]; then
      echo "✅ 修复成功！状态码：$STATUS" | tee -a "$LOG_FILE"
    else
      echo "🚨 修复失败，尝试回滚至最近备份..." | tee -a "$LOG_FILE"
      if [ -f /home/n8n/backups/n8n_backup_latest.tar.gz ]; then
        docker compose down || docker-compose down
        tar -xzf /home/n8n/backups/n8n_backup_latest.tar.gz -C /home/n8n/n8n
        docker compose up -d || docker-compose up -d
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN || echo "000")
        if [[ "$STATUS" == "200" || "$STATUS" == "302" ]]; then
          echo "✅ 回滚成功！网站恢复正常。" | tee -a "$LOG_FILE"
        else
          echo "🚫 回滚失败，请手动排查，日志参考: $LOG_FILE" | tee -a "$LOG_FILE"
        fi
      else
        echo "❌ 未找到备份，无法回滚，请手动检查服务配置。" | tee -a "$LOG_FILE"
      fi
    fi
  fi
}

# 安装 Node.js（如未安装）
install_nodejs() {
  if ! command -v node &>/dev/null; then
    echo "🧩 正在安装最新 LTS 版 Node.js ..." | tee -a "$LOG_FILE"
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    apt-get install -y nodejs || yum install -y nodejs || dnf install -y nodejs
  else
    echo "🟢 已检测到 Node.js，跳过安装。" | tee -a "$LOG_FILE"
  fi
}

# 安装 Docker & Docker Compose（支持新版与旧版兼容）
install_docker() {
  echo "📦 安装 Docker 和 Docker Compose ..." | tee -a "$LOG_FILE"
  if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | bash
  fi
  if ! docker compose version &>/dev/null && ! docker-compose version &>/dev/null; then
    echo "🔄 安装 Docker Compose 插件" | tee -a "$LOG_FILE"
    mkdir -p ~/.docker/cli-plugins
    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) \
      -o ~/.docker/cli-plugins/docker-compose
    chmod +x ~/.docker/cli-plugins/docker-compose
  fi
}

# 环境准备
prepare_environment() {
  echo "🔧 准备系统依赖环境 ..." | tee -a "$LOG_FILE"
  apt-get update && apt-get install -y \
    curl wget gnupg2 ca-certificates sudo unzip jq lsof \
    nginx certbot python3-certbot-nginx ufw \
    cron software-properties-common || \
  yum install -y curl wget gnupg2 ca-certificates sudo unzip jq lsof \
    nginx certbot python3-certbot-nginx ufw \
    cronie epel-release || \
  dnf install -y curl wget gnupg2 ca-certificates sudo unzip jq lsof \
    nginx certbot python3-certbot-nginx ufw \
    cronie

  systemctl enable nginx
  systemctl start nginx
  systemctl enable docker
  systemctl start docker
}

# 安装部分执行
prepare_environment
install_nodejs
install_docker

# 创建目录
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

# 登录认证 Node.js 服务
cat <<EOF > /home/n8n-auth/server.js
const express = require("express");
const app = express();
const basicAuth = require("express-basic-auth");
const path = require("path");

app.use(
  basicAuth({
    users: { "$BASIC_USER": "$BASIC_PASSWORD" },
    challenge: true,
  })
);
app.use(express.static(path.join(__dirname, "public")));
app.listen(80, () => console.log("Auth page running on port 80"));
EOF

# 登录动画 HTML 页面
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

# 安装认证服务依赖
cd /home/n8n-auth
npm init -y
npm install express express-basic-auth

# systemd 启动文件
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

# 生成 Nginx 配置文件
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

  # 可选：启用 gzip 压缩提升性能
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

# 获取 HTTPS 证书
certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos --non-interactive

# 创建自动备份脚本
cat <<EOF > /home/n8n/backup.sh
#!/bin/bash
TIMESTAMP=\$(date +"%Y%m%d-%H%M%S")
tar -czf /home/n8n/backups/n8n_backup_\$TIMESTAMP.tar.gz -C /home/n8n/n8n .
ln -sf /home/n8n/backups/n8n_backup_\$TIMESTAMP.tar.gz /home/n8n/backups/n8n_backup_latest.tar.gz
EOF
chmod +x /home/n8n/backup.sh

# 清理旧备份脚本（保留最近 10 天）
cat <<EOF > /home/n8n/clean-backups.sh
#!/bin/bash
find /home/n8n/backups/ -name "*.tar.gz" -type f -mtime +10 -exec rm {} \;
EOF
chmod +x /home/n8n/clean-backups.sh

# 自动更新检查脚本（只拉取镜像）
cat <<EOF > /home/n8n/check-update.sh
#!/bin/bash
docker pull n8nio/n8n && echo "✅ n8n 镜像更新检查完成"
EOF
chmod +x /home/n8n/check-update.sh

# 自动升级脚本（含备份）
cat <<EOF > /home/n8n/auto-upgrade.sh
#!/bin/bash
/home/n8n/backup.sh
docker compose -f /home/n8n/docker-compose.yml down || docker-compose -f /home/n8n/docker-compose.yml down
docker pull n8nio/n8n
docker compose -f /home/n8n/docker-compose.yml up -d || docker-compose -f /home/n8n/docker-compose.yml up -d
EOF
chmod +x /home/n8n/auto-upgrade.sh

# 手动升级脚本
cat <<EOF > /home/n8n/upgrade-n8n.sh
#!/bin/bash
/home/n8n/auto-upgrade.sh
EOF
chmod +x /home/n8n/upgrade-n8n.sh

# 设置定时任务（每天定时运行）
(crontab -l 2>/dev/null; echo "0 3 * * * /home/n8n/backup.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 4 * * * /home/n8n/clean-backups.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 5 * * * /home/n8n/check-update.sh") | crontab -

# 若开启自动更新，再添加升级任务
if [[ "$AUTO_UPDATE" == "yes" ]]; then
  (crontab -l 2>/dev/null; echo "0 6 * * * /home/n8n/auto-upgrade.sh") | crontab -
fi

# 启动所有服务
cd /home/n8n && docker compose up -d || docker-compose up -d
systemctl restart nginx
sleep 2
systemctl restart n8n-auth

# 最终提示输出
cat <<EOM

✅ n8n 自定义登录部署完成！访问地址: https://$DOMAIN
📝 登录用户名: $BASIC_USER
📝 登录密码: $BASIC_PASSWORD
📆 自动备份脚本: /home/n8n/backup.sh
🧹 自动清理脚本: /home/n8n/clean-backups.sh
🚀 自动更新检测脚本: /home/n8n/check-update.sh
🚀 自动升级脚本: /home/n8n/auto-upgrade.sh
🔧 手动升级脚本: /home/n8n/upgrade-n8n.sh
🗓 定时任务已设置：每天自动备份 + 清理 + 镜像更新
🔄 自动更新: $( [[ "$AUTO_UPDATE" == "yes" ]] && echo "已启用" || echo "未启用" )
🔐 登录认证服务 systemd 已安装并自启动
🌐 登录页面: https://$DOMAIN/login.html
⚡ Powered by John 一键部署！🚀

EOM

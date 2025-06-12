#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

LOG_FILE="/var/log/n8n-deploy.log"
echo "🔧 启动 N8N 一键部署..." | tee -a "$LOG_FILE"

# fallback 兼容 docker compose / docker-compose
docker_compose() {
  if command -v docker compose &>/dev/null; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}

# 添加定时任务（避免重复）
add_cron() {
  (crontab -l 2>/dev/null | grep -v "$1"; echo "$1") | crontab -
}

# 检测系统信息
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
  VERSION_ID=${VERSION_ID%%.*}
else
  echo "❌ 无法检测系统信息，退出。" | tee -a "$LOG_FILE"
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

# 用户输入部分
read -p "🌐 输入域名 (如 n8n.example.com): " DOMAIN
DOMAIN=$(echo "$DOMAIN" | tr -d '\r\n' | xargs)
read -p "📧 输入邮箱 (用于SSL): " EMAIL
read -p "👤 登录用户名 (默认admin): " BASIC_USER
BASIC_USER=${BASIC_USER:-admin}
read -s -p "🔒 登录密码 (默认admin123): " BASIC_PASSWORD
BASIC_PASSWORD=${BASIC_PASSWORD:-admin123}
echo ""
read -p "🤖 是否开启自动更新？(yes/no): " AUTO_UPDATE

# 检查 Node.js 并升级
echo "🧪 检查 Node.js 版本..." | tee -a "$LOG_FILE"
NODE_VERSION=$(node -v 2>/dev/null | sed 's/v//')
NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
LATEST_MAJOR=$(curl -s https://nodejs.org/dist/index.json | jq '.[0].version' | sed 's/"v\([0-9]*\).*/\1/')

if [ -z "$NODE_VERSION" ] || [ "$NODE_MAJOR" -lt "$LATEST_MAJOR" ]; then
  echo "🧹 发现旧版 Node.js（当前: v${NODE_VERSION:-none}, 最新: v$LATEST_MAJOR），准备清除并安装最新版…" | tee -a "$LOG_FILE"

  apt purge -y nodejs npm libnode-dev || yum remove -y nodejs npm || dnf remove -y nodejs npm || true
  dpkg -r --force-all libnode-dev >/dev/null 2>&1 || true
  apt autoremove -y || true

  curl -fsSL https://deb.nodesource.com/setup_current.x | bash -
  if command -v apt &>/dev/null; then
    apt install -y nodejs
  elif command -v yum &>/dev/null; then
    yum install -y nodejs
  elif command -v dnf &>/dev/null; then
    dnf install -y nodejs
  else
    echo "❌ 无法安装 Node.js，请手动安装！" | tee -a "$LOG_FILE"
    exit 1
  fi
else
  echo "✅ Node.js 已是最新版，当前版本：v$NODE_VERSION" | tee -a "$LOG_FILE"
fi

# 验证 Node.js 是否可用
if ! command -v node &>/dev/null; then
  echo "❌ Node.js 安装失败，请检查服务器环境。" | tee -a "$LOG_FILE"
  exit 1
fi

# 输出版本信息
echo "✅ 当前 Node.js: $(node -v)" | tee -a "$LOG_FILE"
echo "✅ 当前 npm: $(npm -v)" | tee -a "$LOG_FILE"


# 安装通用依赖项
echo "📦 安装通用依赖…" | tee -a "$LOG_FILE"
if command -v apt &>/dev/null; then
  apt update -y
  apt install -y curl wget gnupg2 ca-certificates sudo unzip jq lsof \
    nginx certbot python3-certbot-nginx ufw cron software-properties-common
elif command -v yum &>/dev/null; then
  yum install -y curl wget gnupg2 ca-certificates sudo unzip jq lsof \
    nginx certbot python3-certbot-nginx ufw cronie epel-release
elif command -v dnf &>/dev/null; then
  dnf install -y curl wget gnupg2 ca-certificates sudo unzip jq lsof \
    nginx certbot python3-certbot-nginx ufw cronie
else
  echo "❌ 无支持的包管理器，请手动安装依赖。" | tee -a "$LOG_FILE"
  exit 1
fi

# 自动安装 Docker & Compose（如未安装）
if ! command -v docker &>/dev/null; then
  echo "🐳 未检测到 Docker，正在安装..."
  curl -fsSL https://get.docker.com | bash
  systemctl enable docker
  systemctl start docker
else
  echo "✅ 已检测到 Docker"
fi

if ! docker compose version &>/dev/null && ! command -v docker-compose &>/dev/null; then
  echo "📦 未检测到 docker compose，正在安装插件版本..."
  apt install -y docker-compose-plugin || yum install -y docker-compose-plugin || dnf install -y docker-compose-plugin
else
  echo "✅ docker compose 可用"
fi

# 启动并设置 Nginx 开机自启
systemctl enable nginx
systemctl start nginx

# 创建所需目录
mkdir -p /home/n8n /home/n8n-auth/public /home/n8n/backups

# 编写登录认证服务 server.js（监听 3000 端口）
cat <<EOF > /home/n8n-auth/server.js
const express = require("express");
const app = express();
const basicAuth = require("express-basic-auth");
const path = require("path");
const cookieParser = require("cookie-parser");

app.use(cookieParser());

const users = { "$BASIC_USER": "$BASIC_PASSWORD" };

app.use((req, res, next) => {
  if (req.cookies.auth === "true") return next();
  if (req.path === "/login" || req.path === "/login.html" || req.path === "/login-submit") return next();
  res.redirect("/login.html");
});

app.use(express.urlencoded({ extended: true }));

app.post("/login-submit", (req, res) => {
  const { username, password } = req.body;
  if (users[username] === password) {
    res.cookie("auth", "true", { httpOnly: true });
    return res.redirect("/");
  }
  return res.redirect("/login.html");
});

app.use(express.static(path.join(__dirname, "public")));

app.listen(3000, () => console.log("🔐 Auth server running on port 3000"));
EOF

# 写入登录页面 login.html（根据你的设计）
cat <<EOF > /home/n8n-auth/public/login.html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <title>欢迎使用 John 一键部署版 N8N</title>
  <style>
    body {
      margin: 0;
      background: radial-gradient(circle at center, #1e2746, #0f1626);
      height: 100vh;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial;
      display: flex;
      align-items: center;
      justify-content: center;
      color: #fff;
    }
    .card {
      background: rgba(255,255,255,0.05);
      padding: 40px;
      border-radius: 12px;
      box-shadow: 0 4px 30px rgba(0,0,0,0.2);
      backdrop-filter: blur(5px);
      width: 320px;
      text-align: center;
    }
    .card h2 {
      margin-bottom: 20px;
      font-size: 1.4em;
    }
    .card input {
      width: 100%;
      padding: 10px;
      margin: 8px 0;
      border: none;
      border-radius: 6px;
    }
    .card button {
      width: 100%;
      padding: 10px;
      background-color: #0b5ed7;
      border: none;
      border-radius: 6px;
      color: #fff;
      font-weight: bold;
      cursor: pointer;
    }
    .card small {
      display: block;
      margin-top: 10px;
      color: #aaa;
      font-size: 0.8em;
    }
  </style>
</head>
<body>
  <form class="card" method="POST" action="/login-submit">
    <h2>欢迎使用 John 一键部署版 N8N</h2>
    <input type="text" name="username" placeholder="用户名" required />
    <input type="password" name="password" placeholder="密码" required />
    <button type="submit">登录</button>
    <small>Powered by JOHN</small>
  </form>
</body>
</html>
EOF

# 安装认证服务依赖
cd /home/n8n-auth
npm init -y
npm install express express-basic-auth cookie-parser

# 设置 systemd 启动服务
cat <<EOF > /etc/systemd/system/n8n-auth.service
[Unit]
Description=Custom Login Page for n8n
After=network.target

[Service]
ExecStart=/usr/bin/node /home/n8n-auth/server.js
Restart=always
Environment=NODE_ENV=production
User=root

[Install]
WantedBy=multi-user.target
EOF

# 启动认证服务
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable n8n-auth
systemctl start n8n-auth

# 生成 docker-compose.yml（不包含版本字段）
cat <<EOF > /home/n8n/docker-compose.yml
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: always
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=false
      - N8N_HOST=$DOMAIN
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://$DOMAIN/
    volumes:
      - /home/n8n/.n8n:/home/node/.n8n
    networks:
      - n8n-network

networks:
  n8n-network:
    driver: bridge
EOF

# 启动 n8n 服务
cd /home/n8n
docker_compose up -d

# 写入 Nginx 配置文件
cat <<EOF > /etc/nginx/conf.d/n8n.conf
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 302 http://localhost:3000;
    }
}
EOF

# 创建用于验证 SSL 的路径
mkdir -p /var/www/html/.well-known/acme-challenge

# 停止 nginx 临时防止占用 80 端口
systemctl stop nginx

# 申请 Let's Encrypt 证书
certbot certonly --webroot -w /var/www/html -d $DOMAIN --email $EMAIL --agree-tos --non-interactive

# 重新写入 Nginx 配置（强制走登录认证服务）
cat <<EOF > /etc/nginx/conf.d/n8n.conf
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# 重启 nginx 应用新配置
systemctl start nginx

# 创建备份脚本 backup.sh
cat <<EOF > /home/n8n/backup.sh
#!/bin/bash
TIMESTAMP=\$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/home/n8n/backups"
DATA_DIR="/home/n8n"
mkdir -p \$BACKUP_DIR
tar -czf \$BACKUP_DIR/n8n_backup_\$TIMESTAMP.tar.gz -C \$DATA_DIR . --exclude backups
echo "✅ 备份已创建: \$BACKUP_DIR/n8n_backup_\$TIMESTAMP.tar.gz"
EOF
chmod +x /home/n8n/backup.sh

# 创建清理脚本 clean-backups.sh（保留最近 5 个备份）
cat <<EOF > /home/n8n/clean-backups.sh
#!/bin/bash
cd /home/n8n/backups
ls -1tr | grep '^n8n_backup_.*\.tar\.gz$' | head -n -5 | xargs -d '\n' rm -f --
echo "🧹 旧备份清理完成（保留5个）"
EOF
chmod +x /home/n8n/clean-backups.sh

# 创建自动更新脚本 check-update.sh
cat <<EOF > /home/n8n/check-update.sh
#!/bin/bash
LATEST=\$(docker pull docker.n8n.io/n8nio/n8n:latest | grep 'Downloaded newer image')
if [ -n "\$LATEST" ]; then
  echo "⬆️ 发现新版本，准备更新 n8n..."
  /home/n8n/backup.sh
  docker_compose -f /home/n8n/docker-compose.yml down
  docker_compose -f /home/n8n/docker-compose.yml up -d
  echo "✅ n8n 已升级并重启"
else
  echo "✅ n8n 已是最新版本"
fi
EOF
chmod +x /home/n8n/check-update.sh

# 创建查看账号密码脚本 show-login.sh
cat <<EOF > /home/n8n/show-login.sh
#!/bin/bash
echo "👤 当前登录用户名: $BASIC_USER"
echo "🔒 当前登录密码:   $BASIC_PASSWORD"
EOF
chmod +x /home/n8n/show-login.sh

# 创建重置账号密码脚本 reset-login.sh
cat <<EOF > /home/n8n/reset-login.sh
#!/bin/bash
read -p "👤 输入新用户名: " NEW_USER
read -s -p "🔒 输入新密码: " NEW_PASS
echo ""

sed -i "s|const users = {.*}|const users = { \\"\$NEW_USER\\": \\"\$NEW_PASS\\" };|" /home/n8n-auth/server.js
systemctl restart n8n-auth

echo "✅ 用户名密码已更新，新用户名: \$NEW_USER"
EOF
chmod +x /home/n8n/reset-login.sh

# 若选择自动更新则写入 crontab
if [[ "$AUTO_UPDATE" == "yes" ]]; then
  add_cron "0 3 * * * /home/n8n/check-update.sh >> /var/log/n8n-update.log 2>&1"
fi

# 设置每日备份与清理计划
add_cron "0 2 * * * /home/n8n/backup.sh"
add_cron "0 4 * * * /home/n8n/clean-backups.sh"

# 防火墙规则
if command -v ufw &>/dev/null; then
  ufw allow 80
  ufw allow 443
  ufw allow 3000
  ufw allow 5678
  ufw --force enable
  echo "✅ 防火墙已配置: 允许 80, 443, 3000, 5678"
fi

# 创建帮助命令脚本 n8n-helper.sh
cat <<EOF > /home/n8n/n8n-helper.sh
#!/bin/bash

echo ""
echo "📌 N8N 部署常用命令参考"
echo "──────────────────────────────"
echo "🔄 重启认证服务:      systemctl restart n8n-auth"
echo "🔄 重启 Nginx:         systemctl restart nginx"
echo "🔄 重启 N8N 服务:      docker_compose -f /home/n8n/docker-compose.yml up -d"
echo ""
echo "📂 查看备份目录:      ls /home/n8n/backups/"
echo "📦 手动备份:          bash /home/n8n/backup.sh"
echo "🧹 清理旧备份:        bash /home/n8n/clean-backups.sh"
echo ""
echo "⬆️ 手动检查更新:      bash /home/n8n/check-update.sh"
echo "👤 查看账号密码:      bash /home/n8n/show-login.sh"
echo "🔐 重置账号密码:      bash /home/n8n/reset-login.sh"
echo ""
echo "🚀 启动登录认证服务:  systemctl start n8n-auth"
echo "🛑 停止认证服务:      systemctl stop n8n-auth"
echo "🔍 查看认证状态:      systemctl status n8n-auth"
echo ""
echo "📋 更多信息请参考项目 README 或联系管理员"
echo ""
EOF
chmod +x /home/n8n/n8n-helper.sh

# 启动服务
echo "🔍 正在检查服务状态..."
systemctl restart nginx
systemctl restart n8n-auth
docker_compose -f /home/n8n/docker-compose.yml up -d

# 最终提示
echo ""
echo "🚀 部署完成！🎉"
echo "🌐 访问地址: https://$DOMAIN"
echo ""
echo "🛡️ 登录信息（用于访问自定义登录页）："
echo "👤 用户名: $BASIC_USER"
echo "🔒 密码: $BASIC_PASSWORD"
echo ""
echo "📂 数据目录: /home/n8n/"
echo "📁 备份目录: /home/n8n/backups/"
echo ""
echo "📖 可用命令速查: bash /home/n8n/n8n-helper.sh"
echo "✅ 查看登录信息: bash /home/n8n/show-login.sh"
echo "🔁 重置账号密码: bash /home/n8n/reset-login.sh"
echo "📦 手动备份: bash /home/n8n/backup.sh"
echo "⬆️ 手动升级: bash /home/n8n/check-update.sh"
echo ""
echo "⚠️ 请妥善保存以上信息。若遗忘账号密码，请使用 reset-login.sh 脚本重置。"
echo ""

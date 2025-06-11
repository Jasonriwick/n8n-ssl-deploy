#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

LOG_FILE="/var/log/n8n-deploy.log"
echo "🔧 启动 N8N 一键部署..." | tee -a "$LOG_FILE"

# docker compose fallback 函数
docker_compose() {
  if command -v docker compose &>/dev/null; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}

# 添加定时任务（去重）
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

# 用户交互
read -p "🌐 输入域名 (如 n8n.example.com): " DOMAIN
DOMAIN=$(echo "$DOMAIN" | tr -d '\r\n' | xargs)
read -p "📧 输入邮箱 (用于SSL): " EMAIL
read -p "👤 登录用户名 (默认admin): " BASIC_USER
BASIC_USER=${BASIC_USER:-admin}
read -s -p "🔒 登录密码 (默认admin123): " BASIC_PASSWORD
BASIC_PASSWORD=${BASIC_PASSWORD:-admin123}
echo ""
read -p "🤖 是否开启自动更新？(yes/no): " AUTO_UPDATE

# 检查并升级 Node.js
echo "🧪 检查 Node.js 版本..." | tee -a "$LOG_FILE"
NODE_VERSION=$(node -v 2>/dev/null | sed 's/v//')
NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)

# 最新版本主版本号（根据 Node.js 当前官网 LTS/Current 变动也可替换为 dynamic 检测）
LATEST_MAJOR=$(curl -s https://nodejs.org/dist/index.json | jq '.[0].version' | sed 's/"v\([0-9]*\).*/\1/')

if [ -z "$NODE_VERSION" ] || [ "$NODE_MAJOR" -lt "$LATEST_MAJOR" ]; then
  echo "🧹 发现旧版 Node.js（当前: v$NODE_VERSION, 最新: v$LATEST_MAJOR），准备清除并安装最新版..." | tee -a "$LOG_FILE"
  apt remove -y nodejs npm || yum remove -y nodejs npm || dnf remove -y nodejs npm || true
  curl -fsSL https://deb.nodesource.com/setup_current.x | bash -
  apt install -y nodejs || yum install -y nodejs || dnf install -y nodejs
else
  echo "✅ Node.js 已是最新版 v$NODE_VERSION" | tee -a "$LOG_FILE"
fi

# 显示版本
echo "✅ 当前 Node.js: $(node -v)" | tee -a "$LOG_FILE"
echo "✅ 当前 npm: $(npm -v)" | tee -a "$LOG_FILE"

# 安装通用依赖（根据系统类型自动跳过确认）
echo "📦 安装依赖..." | tee -a "$LOG_FILE"
if command -v apt &>/dev/null; then
  apt update -y && apt install -y \
    curl wget gnupg2 ca-certificates sudo unzip jq lsof \
    nginx certbot python3-certbot-nginx ufw cron software-properties-common
elif command -v yum &>/dev/null; then
  yum install -y curl wget gnupg2 ca-certificates sudo unzip jq lsof \
    nginx certbot python3-certbot-nginx ufw cronie epel-release
elif command -v dnf &>/dev/null; then
  dnf install -y curl wget gnupg2 ca-certificates sudo unzip jq lsof \
    nginx certbot python3-certbot-nginx ufw cronie
fi

# 启动并设置 Nginx 自启动
systemctl enable nginx
systemctl start nginx

# 安装 Docker（如未安装）
echo "🐳 安装 Docker..." | tee -a "$LOG_FILE"
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | bash
fi

# 安装 Docker Compose（如未安装 v2+ 或 legacy）
if ! docker compose version &>/dev/null && ! docker-compose version &>/dev/null; then
  mkdir -p /usr/local/lib/docker/cli-plugins
  curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi

# 启动 Docker 服务
systemctl enable docker
systemctl start docker

# 创建目录结构
mkdir -p /home/n8n/n8n /home/n8n-auth/public /home/n8n/backups

# 生成 docker-compose.yml 文件
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

# 创建认证登录页服务 server.js
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

# 登录页 HTML 动效
cat <<EOF > /home/n8n-auth/public/login.html
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>Welcome to n8n</title>
<style>body{margin:0;background:radial-gradient(#2c3e50,#000);color:#fff;
font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;
animation:fadeIn 2s ease-in-out}h1{font-size:3rem;animation:float 3s infinite alternate}
@keyframes float{0%{transform:translateY(0)}100%{transform:translateY(-20px)}}
@keyframes fadeIn{from{opacity:0}to{opacity:1}}</style></head>
<body><h1>Welcome to n8n 🚀</h1></body></html>
EOF

# 安装 Node.js 登录服务依赖
cd /home/n8n-auth
npm init -y
npm install express express-basic-auth --yes

# 配置 systemd 启动登录认证服务
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

# 启用认证服务
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable n8n-auth
systemctl start n8n-auth

# 写入初始 HTTP 配置，仅监听 80 端口（申请 SSL 前使用）
cat <<EOF > /etc/nginx/conf.d/n8n.conf
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

# 创建 Certbot 临时验证路径
mkdir -p /var/www/html

# 测试配置，确保没有语法错误
nginx -t && systemctl reload nginx

# 使用 Certbot 自动申请 SSL 证书（静默模式）
certbot certonly --webroot -w /var/www/html -d $DOMAIN --email $EMAIL --agree-tos --non-interactive

# 检查证书路径是否生成成功
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
  echo "❌ SSL 证书申请失败，请检查域名是否正确解析至本服务器。" | tee -a "$LOG_FILE"
  exit 1
fi

# 替换完整的 SSL 配置（443 启用，80 强制跳转）
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

# 再次 reload 确认 HTTPS 配置生效
nginx -t && systemctl reload nginx

# 创建备份脚本
cat <<EOF > /home/n8n/backup.sh
#!/bin/bash
TIMESTAMP=\$(date +"%Y%m%d-%H%M%S")
tar -czf /home/n8n/backups/n8n_backup_\$TIMESTAMP.tar.gz -C /home/n8n/n8n .
ln -sf /home/n8n/backups/n8n_backup_\$TIMESTAMP.tar.gz /home/n8n/backups/n8n_backup_latest.tar.gz
EOF
chmod +x /home/n8n/backup.sh

# 清理10天前的备份
cat <<EOF > /home/n8n/clean-backups.sh
#!/bin/bash
find /home/n8n/backups/ -name "*.tar.gz" -type f -mtime +10 -exec rm {} \;
EOF
chmod +x /home/n8n/clean-backups.sh

# 镜像检查脚本
cat <<EOF > /home/n8n/check-update.sh
#!/bin/bash
docker pull n8nio/n8n >> /var/log/n8n-update.log 2>&1
EOF
chmod +x /home/n8n/check-update.sh

# 自动升级脚本
cat <<EOF > /home/n8n/auto-upgrade.sh
#!/bin/bash
/home/n8n/backup.sh
docker compose down || docker-compose down
docker pull n8nio/n8n
docker compose up -d || docker-compose up -d
EOF
chmod +x /home/n8n/auto-upgrade.sh

# 手动升级快捷方式
echo -e "#!/bin/bash\n/home/n8n/auto-upgrade.sh" > /home/n8n/upgrade-n8n.sh
chmod +x /home/n8n/upgrade-n8n.sh

# 添加定时任务（去重避免重复添加）
add_cron "0 3 * * * /home/n8n/backup.sh"
add_cron "0 4 * * * /home/n8n/clean-backups.sh"
add_cron "0 5 * * * /home/n8n/check-update.sh"
[[ "$AUTO_UPDATE" == "yes" ]] && add_cron "0 6 * * * /home/n8n/auto-upgrade.sh"

# 启动 n8n 服务容器
cd /home/n8n
docker_compose up -d

# 重启 Nginx 和认证服务
systemctl restart nginx
sleep 2
systemctl restart n8n-auth

# 输出部署信息
AUTO_STATUS=$( [[ "$AUTO_UPDATE" == "yes" ]] && echo "已启用" || echo "未启用" )
cat <<EOM

✅ n8n 已部署成功！

🌍 访问地址: https://$DOMAIN
🔐 登录账号: $BASIC_USER
🔑 登录密码: $BASIC_PASSWORD

📦 自动备份: /home/n8n/backup.sh
🧹 清理旧备份: /home/n8n/clean-backups.sh
🚀 自动升级: /home/n8n/auto-upgrade.sh
🔧 手动升级: /home/n8n/upgrade-n8n.sh
📅 自动更新状态: $AUTO_STATUS

🖼 登录页: https://$DOMAIN/login.html
🛡️ 登录认证服务已启用 (systemd)

⚡ Powered by John Script - 稳定 • 安全 • 自动化

EOM

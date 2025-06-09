#!/bin/bash

set -e

echo "🔧 开始 N8N + Docker Nginx + SSL + 自定义登录页 (Node.js Express认证) 安全强化版一键部署..."

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
  debian)
    if [ "$VERSION_ID" -lt 10 ]; then
      echo "❌ Debian 版本太旧，要求 10 或更高版本。"
      exit 1
    fi
    ;;
  centos|rocky|almalinux|rhel)
    if [ "$VERSION_ID" -lt 8 ]; then
      echo "❌ RedHat 系列版本太旧，要求 8 或更高版本。"
      exit 1
    fi
    ;;
  amzn)
    echo "✅ 检测到 Amazon Linux 2，继续。"
    ;;
  *)
    echo "❌ 不支持的系统: $OS。建议使用 Ubuntu, Debian, CentOS 8+。"
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

# 安装基础依赖
export DEBIAN_FRONTEND=noninteractive
if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
  apt update
  apt install -y curl wget ca-certificates gnupg2 lsb-release apt-transport-https \
    software-properties-common sudo unzip ufw cron jq certbot python3-certbot-nginx nginx \
    fail2ban openssl nodejs npm lsof
  ufw allow 22/tcp
  ufw allow 80,443/tcp
  ufw --force enable
elif [[ "$OS" == "centos" || "$OS" == "rocky" || "$OS" == "almalinux" || "$OS" == "rhel" ]]; then
  yum update -y
  yum install -y epel-release
  yum install -y curl wget ca-certificates gnupg2 lsb-release unzip firewalld jq \
    certbot python3-certbot-nginx nginx fail2ban openssl nodejs npm lsof
  systemctl enable firewalld
  systemctl start firewalld
  firewall-cmd --permanent --add-service=http
  firewall-cmd --permanent --add-service=https
  firewall-cmd --permanent --add-port=22/tcp
  firewall-cmd --reload
elif [[ "$OS" == "amzn" ]]; then
  yum update -y
  amazon-linux-extras enable nginx1 docker
  yum install -y docker unzip certbot python3-certbot-nginx nginx jq fail2ban openssl nodejs npm lsof
fi

# 检测 Docker 是否需要安装
INSTALL_DOCKER=false
if ! command -v docker &> /dev/null; then
  INSTALL_DOCKER=true
else
  DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
  DOCKER_MAJOR_VERSION=$(echo "$DOCKER_VERSION" | cut -d'.' -f1)
  if [ "$DOCKER_MAJOR_VERSION" -lt 20 ]; then
    INSTALL_DOCKER=true
  fi
fi

if [ "$INSTALL_DOCKER" = true ]; then
  echo "🚀 安装最新 Docker..."
  if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt remove -y docker docker-engine docker.io containerd runc || true
    apt update
    apt install -y ca-certificates curl gnupg lsb-release
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  fi
  systemctl enable docker
  systemctl start docker
fi

# 检测 docker compose
if docker compose version &> /dev/null; then
  DOCKER_COMPOSE_CMD="docker compose"
else
  if ! command -v docker-compose &> /dev/null; then
    echo "🛠️ 安装旧版 docker-compose..."
    curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
  fi
  DOCKER_COMPOSE_CMD="docker-compose"
fi

echo "✅ Docker Compose 命令: $DOCKER_COMPOSE_CMD"

# nginx 配置
mkdir -p /var/www/html/.well-known/acme-challenge
cat > /etc/nginx/conf.d/n8n.conf <<EOF
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
EOF

systemctl enable nginx
systemctl start nginx
nginx -t && systemctl reload nginx

# 申请 SSL 证书
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

# Node.js 登录认证服务
mkdir -p /home/n8n-auth
chmod -R 777 /home/n8n-auth
cat > /home/n8n-auth/server.js <<'EOF'
const express = require('express');
const bodyParser = require('body-parser');
const cookieParser = require('cookie-parser');
const crypto = require('crypto');
const app = express();

const user = process.env.N8N_USER;
const passwordHash = process.env.N8N_PASSWORD;

function sha256(text) {
  return crypto.createHash('sha256').update(text).digest('hex');
}

app.use(bodyParser.urlencoded({ extended: true }));
app.use(cookieParser());

app.post('/auth', (req, res) => {
  const { username, password } = req.body;
  if (sha256(username) === user && sha256(password) === passwordHash) {
    res.cookie('n8n_auth', 'valid', { httpOnly: true, secure: true });
    res.redirect('/');
  } else {
    res.status(401).send('用户名或密码错误！');
  }
});

app.listen(3000, () => {
  console.log('认证服务已启动，监听 3000 端口');
});
EOF

cd /home/n8n-auth
npm init -y
npm install express body-parser cookie-parser

# systemd 启动认证服务
cat > /etc/systemd/system/n8n-auth.service <<EOF
[Unit]
Description=N8N Login Auth Service
After=network.target

[Service]
Type=simple
Environment="N8N_USER=$(echo -n "$BASIC_USER" | openssl dgst -sha256 | awk '{print $2}')"
Environment="N8N_PASSWORD=$(echo -n "$BASIC_PASSWORD" | openssl dgst -sha256 | awk '{print $2}')"
WorkingDirectory=/home/n8n-auth
ExecStart=/usr/bin/node /home/n8n-auth/server.js
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable n8n-auth
systemctl start n8n-auth

# 登录页面
mkdir -p /var/www/html
chmod -R 777 /var/www/html
cat > /var/www/html/login.html <<'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>N8N 登录</title>
<link rel="stylesheet" href="/login.css">
</head>
<body>
<div class="login-container">
  <h1>Welcome to N8N</h1>
  <form method="post" action="/auth">
    <input type="text" name="username" placeholder="用户名" required>
    <input type="password" name="password" placeholder="密码" required>
    <button type="submit">登录</button>
  </form>
  <div class="footer">
    <a href="https://github.com">Powered by N8N</a>
  </div>
</div>
</body>
</html>
EOF

cat > /var/www/html/login.css <<'EOF'
body {
  background: linear-gradient(135deg, #1a1a2e, #16213e);
  color: white;
  font-family: Arial, sans-serif;
}
.login-container {
  width: 300px;
  margin: 10% auto;
  padding: 30px;
  background: rgba(255, 255, 255, 0.1);
  border-radius: 10px;
  text-align: center;
}
input {
  width: 90%;
  padding: 10px;
  margin: 10px 0;
  border: none;
  border-radius: 5px;
}
button {
  width: 100%;
  padding: 10px;
  background: #0f3460;
  border: none;
  border-radius: 5px;
  color: white;
  font-weight: bold;
}
.footer {
  margin-top: 20px;
  font-size: 12px;
}
a {
  color: #4dd0e1;
  text-decoration: none;
}
EOF

# Nginx 更新配置
cat > /etc/nginx/conf.d/n8n.conf <<EOF
server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location /auth {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /login.html {
        root /var/www/html;
    }

    location /login.css {
        root /var/www/html;
    }

    location / {
        if (\$cookie_n8n_auth != "valid") {
          return 302 /login.html;
        }
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

nginx -t && systemctl reload nginx

# n8n docker compose
mkdir -p /home/n8n/n8n /home/n8n/n8ndata /home/n8n/backups
chmod -R 777 /home/n8n

cat > /home/n8n/docker-compose.yml <<EOF
version: '3.8'
services:
  n8n:
    image: n8nio/n8n
    restart: always
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

docker network create n8n-network || true

cd /home/n8n
$DOCKER_COMPOSE_CMD up -d

# 备份 + 自动更新脚本
cat > /home/n8n/backup.sh <<'EOF'
#!/bin/bash
DATE=$(date +%F_%T)
tar czf /home/n8n/backups/n8n_backup_$DATE.tar.gz -C /home/n8n/n8n . -C /home/n8n/n8ndata .
EOF
chmod +x /home/n8n/backup.sh

cat > /home/n8n/clean-backups.sh <<'EOF'
#!/bin/bash
find /home/n8n/backups/ -name "*.tar.gz" -type f -mtime +14 -exec rm -f {} \;
EOF
chmod +x /home/n8n/clean-backups.sh

cat > /home/n8n/check-update.sh <<'EOF'
#!/bin/bash
LATEST=$(curl -s https://hub.docker.com/v2/repositories/n8nio/n8n/tags | jq -r '.results[0].name')
CURRENT=$(docker inspect $(docker ps -q --filter ancestor=n8nio/n8n) --format '{{ index .Config.Image }}' | cut -d: -f2)
if [ "$LATEST" != "$CURRENT" ]; then
  echo "UPDATE_AVAILABLE" > /home/n8n/update.flag
else
  rm -f /home/n8n/update.flag
fi
EOF
chmod +x /home/n8n/check-update.sh

cat > /home/n8n/auto-upgrade.sh <<'EOF'
#!/bin/bash
if [ -f /home/n8n/update.flag ]; then
  bash /home/n8n/backup.sh
  $DOCKER_COMPOSE_CMD pull
  $DOCKER_COMPOSE_CMD down
  $DOCKER_COMPOSE_CMD up -d
  rm -f /home/n8n/update.flag
fi
EOF
chmod +x /home/n8n/auto-upgrade.sh

# Crontab
(crontab -l 2>/dev/null; echo "0 2 * * * /home/n8n/backup.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * * /home/n8n/clean-backups.sh") | crontab -
if [ "$AUTO_UPDATE" == "yes" ]; then
  (crontab -l 2>/dev/null; echo "0 8,12,20 * * * /home/n8n/check-update.sh") | crontab -
  (crontab -l 2>/dev/null; echo "0 4 * * * /home/n8n/auto-upgrade.sh") | crontab -
fi

# 成功提示
echo ""
echo "✅ n8n 自定义登录部署完成！访问地址: https://$DOMAIN"
echo "📝 登录用户名: $BASIC_USER"
echo "📝 登录密码: $BASIC_PASSWORD"
echo "📦 自动备份脚本: /home/n8n/backup.sh"
echo "🧹 自动清理脚本: /home/n8n/clean-backups.sh"
echo "🚀 自动更新检测脚本: /home/n8n/check-update.sh"
echo "🚀 自动升级脚本: /home/n8n/auto-upgrade.sh"
echo "🔧 手动升级脚本: /home/n8n/upgrade-n8n.sh"
echo "📅 定时任务已设置：每天自动备份+清理+更新检查"
echo "🔐 登录认证服务 systemd 已安装并自启动"
echo "🌐 登录页面: https://$DOMAIN/login.html"

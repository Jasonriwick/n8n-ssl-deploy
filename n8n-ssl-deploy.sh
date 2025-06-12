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

read -p "🤖 是否启用 SSL? (yes/no): " ENABLE_SSL

if [[ "$ENABLE_SSL" == "yes" ]]; then
  read -p "📧 输入邮箱 (用于申请 SSL 证书): " EMAIL
fi

read -p "👤 登录用户名 (默认admin): " BASIC_USER
BASIC_USER=${BASIC_USER:-admin}

read -s -p "🔒 登录密码 (默认admin123): " BASIC_PASSWORD
BASIC_PASSWORD=${BASIC_PASSWORD:-admin123}
echo ""

read -p "🤖 是否开启自动更新？(yes/no): " AUTO_UPDATE

# 安装 curl wget unzip 等依赖
echo "📦 安装基础依赖..." | tee -a "$LOG_FILE"
case "$OS" in
  ubuntu|debian)
    apt update -y
    apt install -y curl wget unzip sudo gnupg2 ca-certificates lsb-release software-properties-common
    ;;
  centos|rocky|almalinux|rhel)
    yum install -y epel-release
    yum install -y curl wget unzip sudo gnupg2 ca-certificates lsb-release
    ;;
  amzn)
    yum install -y curl wget unzip sudo
    ;;
esac

# 安装 Node.js 18
if ! command -v node &>/dev/null || [[ $(node -v) != v18* ]]; then
  echo "⬇️ 安装 Node.js 18..." | tee -a "$LOG_FILE"
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  case "$OS" in
    ubuntu|debian) apt install -y nodejs ;;
    centos|rocky|almalinux|rhel|amzn) yum install -y nodejs ;;
  esac
fi

# 安装 Docker
if ! command -v docker &>/dev/null; then
  echo "🐳 安装 Docker..." | tee -a "$LOG_FILE"
  curl -fsSL https://get.docker.com | sh
  systemctl start docker
  systemctl enable docker
fi

# 安装 Docker Compose (支持 v2 命令)
if ! command -v docker compose &>/dev/null && ! command -v docker-compose &>/dev/null; then
  echo "🧩 安装 Docker Compose..." | tee -a "$LOG_FILE"
  curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
fi

# 设置防火墙（开放 80, 443, 5678）
if command -v ufw &>/dev/null; then
  echo "🛡️ 配置防火墙..." | tee -a "$LOG_FILE"
  ufw allow ssh
  ufw allow 80
  ufw allow 443
  ufw allow 5678
  ufw --force enable
fi

# 创建部署目录
mkdir -p /home/n8n
mkdir -p /home/n8n-auth/public
mkdir -p /var/www/html/.well-known/acme-challenge

# 写入登录认证页面 HTML
cat >/home/n8n-auth/public/login.html <<EOF
<!DOCTYPE html>
<html lang="zh">
<head>
  <meta charset="UTF-8" />
  <title>登录验证</title>
  <style>
    body {
      margin: 0;
      background: #1a2b4c;
      font-family: sans-serif;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
    }
    .card {
      background: white;
      padding: 40px;
      border-radius: 20px;
      box-shadow: 0 8px 20px rgba(0,0,0,0.2);
      width: 300px;
      text-align: center;
    }
    .card h2 {
      margin-bottom: 20px;
      color: #1a2b4c;
    }
    input {
      width: 100%;
      padding: 10px;
      margin: 10px 0;
    }
    button {
      width: 100%;
      padding: 10px;
      background: #1a2b4c;
      color: white;
      border: none;
      cursor: pointer;
      border-radius: 5px;
    }
    .footer {
      margin-top: 20px;
      font-size: 12px;
      color: #999;
    }
  </style>
</head>
<body>
  <div class="card">
    <h2>欢迎使用 John 一键部署版 N8N</h2>
    <form method="POST" action="/login">
      <input type="text" name="username" placeholder="用户名" required />
      <input type="password" name="password" placeholder="密码" required />
      <button type="submit">登录</button>
    </form>
    <div class="footer">Powered by JOHN</div>
  </div>
</body>
</html>
EOF

# 写入认证服务 Node.js 后端
cat >/home/n8n-auth/server.js <<EOF
const express = require('express')
const path = require('path')
const bodyParser = require('body-parser')
const cookieParser = require('cookie-parser')
const app = express()

const PORT = 5678
const USER = "${BASIC_USER}"
const PASS = "${BASIC_PASSWORD}"
const USE_SSL = process.env.ENABLE_SSL === 'yes'; // ✅ 添加这一行

app.use(bodyParser.urlencoded({ extended: true }))
app.use(cookieParser())
app.use(express.static(path.join(__dirname, 'public')))

app.use((req, res, next) => {
  if (req.path === '/login' || req.cookies.auth === 'yes') {
    next()
  } else {
    res.redirect('/login.html')
  }
})

app.post('/login', (req, res) => {
  const { username, password } = req.body
  if (username === USER && password === PASS) {
    res.cookie('auth', 'yes', { maxAge: 86400000 })

    const protocol = USE_SSL ? 'https://' : 'http://'
    const port = USE_SSL ? ':443' : ''
    res.redirect(protocol + req.hostname + port) // ✅ 修改后的跳转
  } else {
    res.redirect('/login.html')
  }
})

EOF

# 写入 systemd 服务文件（如果不存在）
cat >/etc/systemd/system/n8n-auth.service <<EOF
[Unit]
Description=Custom Login Auth for N8N
After=network.target

[Service]
ExecStart=/usr/bin/node /home/n8n-auth/server.js
Restart=always
Environment=NODE_ENV=production
User=root

[Install]
WantedBy=multi-user.target
EOF

# 注册并启用 n8n-auth 服务
systemctl daemon-reload
systemctl enable n8n-auth

# 写入 Nginx 配置文件（根据是否启用 SSL 决定）
if [[ "$ENABLE_SSL" == "yes" ]]; then
cat >/etc/nginx/conf.d/n8n.conf <<EOF
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
else
cat >/etc/nginx/conf.d/n8n.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
fi


# 写入 .env 环境变量
cat >/home/n8n/.env <<EOF
GENERIC_TIMEZONE="Asia/Shanghai"
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=${BASIC_USER}
N8N_BASIC_AUTH_PASSWORD=${BASIC_PASSWORD}
N8N_HOST=${DOMAIN}
WEBHOOK_TUNNEL_URL=https://${DOMAIN}/
ENABLE_SSL=${ENABLE_SSL}
EOF

# 写入 docker-compose.yml
cat >/home/n8n/docker-compose.yml <<EOF
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: always
    ports:
      - "5679:5678"
    env_file:
      - .env
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - n8n-network

networks:
  n8n-network:
    external: true

volumes:
  n8n_data:
EOF

# 写入工具脚本
cat >/home/n8n/backup.sh <<'EOF'
#!/bin/bash
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="/home/n8n/backups"
mkdir -p "$BACKUP_DIR"
docker exec n8n tar -czf - /home/node/.n8n > "$BACKUP_DIR/n8n-backup-$DATE.tar.gz"
EOF
chmod +x /home/n8n/backup.sh

cat >/home/n8n/clean-backups.sh <<'EOF'
#!/bin/bash
find /home/n8n/backups/ -name "*.tar.gz" -type f -mtime +7 -delete
EOF
chmod +x /home/n8n/clean-backups.sh

cat >/home/n8n/check-update.sh <<'EOF'
#!/bin/bash
echo "🔍 检查 n8n 镜像更新..."
docker pull docker.n8n.io/n8nio/n8n
EOF
chmod +x /home/n8n/check-update.sh

cat >/home/n8n/auto-upgrade.sh <<'EOF'
#!/bin/bash
/home/n8n/check-update.sh
docker compose -f /home/n8n/docker-compose.yml down
docker compose -f /home/n8n/docker-compose.yml up -d
EOF
chmod +x /home/n8n/auto-upgrade.sh

cat >/home/n8n/upgrade-n8n.sh <<'EOF'
#!/bin/bash
echo "⬆️ 正在升级 n8n..."
/home/n8n/auto-upgrade.sh
EOF
chmod +x /home/n8n/upgrade-n8n.sh

cat >/home/n8n/show-login.sh <<EOF
#!/bin/bash
echo "👤 用户名: $BASIC_USER"
echo "🔒 密码: $BASIC_PASSWORD"
EOF
chmod +x /home/n8n/show-login.sh

cat >/home/n8n/reset-login.sh <<'EOF'
#!/bin/bash
read -p "👤 新用户名: " NEW_USER
read -s -p "🔒 新密码: " NEW_PASS
echo ""
sed -i "s|^const USER = .*|const USER = \"${NEW_USER}\"|" /home/n8n-auth/server.js
sed -i "s|^const PASS = .*|const PASS = \"${NEW_PASS}\"|" /home/n8n-auth/server.js
systemctl restart n8n-auth
echo "✅ 登录信息已更新"
EOF
chmod +x /home/n8n/reset-login.sh

# 创建备份目录
mkdir -p /home/n8n/backups/

# 添加定时任务
add_cron "0 3 * * * bash /home/n8n/backup.sh"
add_cron "0 4 * * * bash /home/n8n/clean-backups.sh"
if [[ "$AUTO_UPDATE" == "yes" ]]; then
  add_cron "30 4 * * * bash /home/n8n/auto-upgrade.sh"
fi

# 启动所有服务
echo "🔍 正在检查服务状态..."

# 确保 n8n-network 存在，否则创建
if ! docker network inspect n8n-network >/dev/null 2>&1; then
  echo "🛠️ 未检测到 n8n-network，正在创建..."
  docker network create n8n-network
else
  echo "✅ n8n-network 已存在，跳过创建"
fi

systemctl restart nginx
systemctl restart n8n-auth
docker_compose -f /home/n8n/docker-compose.yml up -d


# 提示信息
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
echo "⬆️ 手动升级: bash /home/n8n/upgrade-n8n.sh"
echo ""
echo "⚠️ 请妥善保存以上信息。若遗忘账号密码，请使用 reset-login.sh 脚本重置。"
echo ""

#!/bin/bash

set -e

echo "🔧 开始 N8N + Docker Nginx + SSL + 自定义登录页 + 安全强化版一键部署..."

# 1. 检测系统信息
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
  VERSION_ID=${VERSION_ID%%.*}
else
  echo "❌ 无法检测操作系统信息，退出。"
  exit 1
fi

echo "🔍 检测到系统: $OS $VERSION_ID"

# 2. 系统版本兼容检测
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

# 3. 用户输入
read -p "🌐 请输入你的域名 (如 example.com): " DOMAIN
read -p "📧 请输入用于 SSL 的邮箱: " EMAIL
read -p "👤 请输入登录用户名（留空默认 admin）: " BASIC_USER
BASIC_USER=${BASIC_USER:-admin}
read -s -p "🔒 请输入登录密码（留空默认 admin123）: " BASIC_PASSWORD
BASIC_PASSWORD=${BASIC_PASSWORD:-admin123}
echo ""
read -p "🤖 是否开启 N8N 自动更新？(yes/no): " AUTO_UPDATE

# 4. 安装依赖
export DEBIAN_FRONTEND=noninteractive
if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
  apt update
  apt install -y curl wget ca-certificates gnupg2 lsb-release apt-transport-https \
    software-properties-common sudo unzip ufw cron docker.io docker-compose jq \
    certbot python3-certbot nginx fail2ban openssl lsof lua-nginx-module
  systemctl enable docker
  systemctl start docker
  ufw allow 22/tcp
  ufw allow 80,443/tcp
  ufw --force enable

elif [[ "$OS" == "centos" || "$OS" == "rocky" || "$OS" == "almalinux" || "$OS" == "rhel" ]]; then
  yum update -y
  yum install -y epel-release
  yum install -y curl wget ca-certificates gnupg2 lsb-release unzip firewalld docker jq \
    certbot python3-certbot nginx fail2ban openssl lsof lua-nginx-module
  systemctl enable docker
  systemctl start docker
  systemctl enable firewalld
  systemctl start firewalld
  firewall-cmd --permanent --add-service=http
  firewall-cmd --permanent --add-service=https
  firewall-cmd --permanent --add-port=22/tcp
  firewall-cmd --reload

elif [[ "$OS" == "amzn" ]]; then
  yum update -y
  amazon-linux-extras enable nginx1 docker
  yum install -y docker unzip certbot python3-certbot nginx jq fail2ban openssl lua-nginx-module
  systemctl enable docker
  systemctl start docker
fi

# 启用 Swap
if [ $(free -m | awk '/^Mem:/{print $2}') -lt 2048 ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# 配置 Fail2ban 防止暴力破解
cat > /etc/fail2ban/jail.d/nginx-http-auth.conf <<'EOF'
[nginx-http-auth]
enabled = true
filter  = nginx-http-auth
port    = http,https
logpath = /var/log/nginx/error.log
maxretry = 5
findtime = 600
bantime  = 1800
EOF
systemctl enable fail2ban
systemctl start fail2ban

# Nginx Gzip 配置优化
cat > /etc/nginx/nginx.conf <<'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    gzip on;
    gzip_disable "msie6";
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    include /etc/nginx/conf.d/*.conf;
}
EOF

# 生成必要目录
mkdir -p /home/n8n-auth
mkdir -p /var/www/html
mkdir -p /home/n8n/n8n
mkdir -p /home/n8n/n8ndata
mkdir -p /home/n8n/backups
chmod -R 777 /home/n8n

# 保存 Basic Auth 登录信息
HASHED_USER=$(echo -n "$BASIC_USER" | openssl dgst -sha256 | awk '{print $2}')
HASHED_PASS=$(echo -n "$BASIC_PASSWORD" | openssl dgst -sha256 | awk '{print $2}')
echo "$HASHED_USER:$HASHED_PASS" > /home/n8n-auth/.credentials
echo "$DOMAIN" > /home/n8n-auth/.domain
echo "$BASIC_USER" > /home/n8n-auth/.basic_user
echo "$BASIC_PASSWORD" > /home/n8n-auth/.basic_password

# 登录页面 login.html
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

# 登录样式 login.css
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

# 登录验证 Lua 脚本 auth.lua
cat > /home/n8n-auth/auth.lua <<'EOF'
function sha256(input)
    local digest = ngx.sha256_bin(input)
    return (string.gsub(digest, ".", function(c) return string.format("%02x", string.byte(c)) end))
end

local function is_authorized(user, pass)
    local file = io.open("/home/n8n-auth/.credentials", "r")
    if not file then
        return false
    end
    local line = file:read("*l")
    file:close()
    local stored_user, stored_pass = line:match("([^:]+):([^:]+)")
    if stored_user == sha256(user) and stored_pass == sha256(pass) then
        return true
    else
        return false
    end
end

if ngx.req.get_method() == "POST" then
    ngx.req.read_body()
    local args = ngx.req.get_post_args()
    if is_authorized(args.username, args.password) then
        ngx.header["Set-Cookie"] = {"logged_in=true; Path=/;"}
        return ngx.redirect("/")
    else
        ngx.say("用户名或密码错误！")
        return ngx.exit(401)
    end
else
    if ngx.var.cookie_logged_in == "true" then
        return
    else
        return ngx.exec("/login.html")
    end
end
EOF

# Nginx 反代配置 n8n.conf
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

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location /auth {
        content_by_lua_file /home/n8n-auth/auth.lua;
    }

    location /login.html {
        root /var/www/html;
    }

    location /login.css {
        root /var/www/html;
    }

    location / {
        content_by_lua_file /home/n8n-auth/auth.lua;
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

nginx -t && systemctl reload nginx

# 6. 配置 Docker Compose 文件
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
docker compose up -d

# 7. 签发 SSL 证书
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

# 8. 备份脚本 backup.sh
cat > /home/n8n/backup.sh <<'EOF'
#!/bin/bash
DATE=$(date +%F_%T)
tar czf /home/n8n/backups/n8n_backup_$DATE.tar.gz -C /home/n8n/n8n . -C /home/n8n/n8ndata .
EOF
chmod +x /home/n8n/backup.sh

# 9. 自动清理备份 clean-backups.sh
cat > /home/n8n/clean-backups.sh <<'EOF'
#!/bin/bash
find /home/n8n/backups/ -name "*.tar.gz" -type f -mtime +14 -exec rm -f {} \;
EOF
chmod +x /home/n8n/clean-backups.sh

# 10. 检查更新脚本 check-update.sh
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

# 11. 自动升级脚本 auto-upgrade.sh
cat > /home/n8n/auto-upgrade.sh <<'EOF'
#!/bin/bash
if [ -f /home/n8n/update.flag ]; then
  bash /home/n8n/backup.sh
  docker-compose pull
  docker-compose down
  docker-compose up -d
  rm -f /home/n8n/update.flag
fi
EOF
chmod +x /home/n8n/auto-upgrade.sh

# 12. 手动升级脚本 upgrade-n8n.sh
cat > /home/n8n/upgrade-n8n.sh <<'EOF'
#!/bin/bash
bash /home/n8n/backup.sh
docker-compose pull
docker-compose down
docker-compose up -d
EOF
chmod +x /home/n8n/upgrade-n8n.sh

# 13. 手动回滚脚本 restore-n8n.sh
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
docker-compose down
rm -rf $N8N_DIR/*
rm -rf $N8NDATA_DIR/*

echo "🔄 正在恢复备份..."
tar -xzf $SELECTED_BACKUP -C $N8N_DIR --strip-components=1
tar -xzf $SELECTED_BACKUP -C $N8NDATA_DIR --strip-components=1

docker-compose up -d
echo "✅ 回滚完成！n8n 已恢复到选定备份版本。"
EOF
chmod +x /home/n8n/restore-n8n.sh

# 14. 密码重置脚本 reset-credentials.sh
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
nginx -t && systemctl reload nginx
echo "✅ 账号密码重置成功！"
EOF
chmod +x /home/n8n-auth/reset-credentials.sh

# 15. 查看账号密码脚本 view-credentials.sh
cat > /home/n8n-auth/view-credentials.sh <<'EOF'
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
EOF
chmod +x /home/n8n-auth/view-credentials.sh

# 16. Crontab 定时任务
(crontab -l 2>/dev/null; echo "0 2 * * * /home/n8n/backup.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * * /home/n8n/clean-backups.sh") | crontab -

if [ "$AUTO_UPDATE" == "yes" ]; then
  (crontab -l 2>/dev/null; echo "0 8,12,20 * * * /home/n8n/check-update.sh") | crontab -
  (crontab -l 2>/dev/null; echo "0 4 * * * /home/n8n/auto-upgrade.sh") | crontab -
fi

# 17. 重启 Nginx 结束部署
nginx -t && systemctl reload nginx

# 18. 最终提示信息
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

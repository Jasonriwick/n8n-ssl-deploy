#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# 日志文件路径
LOG_FILE="/var/log/n8n-deploy.log"
echo "🔧 启动 N8N 一键部署..." | tee -a "$LOG_FILE"

# docker compose 调用函数（兼容新版和旧版命令）
docker_compose() {
  if command -v docker compose &>/dev/null; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}

# 添加定时任务（自动去重）
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

# 系统版本兼容判断
echo "🔍 检测系统: $OS $VERSION_ID" | tee -a "$LOG_FILE"
case "$OS" in
  ubuntu)   [ "$VERSION_ID" -lt 20 ] && echo "❌ Ubuntu需20+" && exit 1 ;;
  debian)   [ "$VERSION_ID" -lt 10 ] && echo "❌ Debian需10+" && exit 1 ;;
  centos|rocky|almalinux|rhel) [ "$VERSION_ID" -lt 8 ] && echo "❌ CentOS需8+" && exit 1 ;;
  amzn)     echo "✅ Amazon Linux 2 通过" ;;
  *)        echo "❌ 不支持的系统: $OS" && exit 1 ;;
esac

# === 用户输入区 ===
read -p "🌐 输入域名 (如 n8n.example.com): " DOMAIN
DOMAIN=$(echo "$DOMAIN" | tr -d '\r\n' | xargs)

read -p "🤖 是否启用 SSL? (yes/no): " ENABLE_SSL

if [[ "$ENABLE_SSL" == "yes" ]]; then
  read -p "📧 输入邮箱 (用于申请 SSL 证书): " EMAIL
fi

read -p "👤 登录用户名 (默认 admin): " BASIC_USER
BASIC_USER=${BASIC_USER:-admin}

read -s -p "🔒 登录密码 (默认 admin123): " BASIC_PASSWORD
BASIC_PASSWORD=${BASIC_PASSWORD:-admin123}
echo ""

read -p "🛠️ 是否开启自动更新？(yes/no): " AUTO_UPDATE

# ===============================
# 📦 检查并安装系统依赖组件
# ===============================

echo "🔍 检查并安装必要依赖组件..." | tee -a "$LOG_FILE"

# 安装基础依赖（自动跳过已安装的）
install_base_packages() {
  if [[ "$OS" =~ ^(ubuntu|debian|amzn)$ ]]; then
    apt-get update -y && apt-get install -y curl wget gnupg2 ca-certificates lsb-release software-properties-common unzip
  elif [[ "$OS" =~ ^(centos|rocky|almalinux|rhel)$ ]]; then
    yum install -y curl wget unzip ca-certificates lsb-release gnupg2
  fi
}

install_base_packages

# ----------------------------
# Node.js 安装（使用 NodeSource）
# ----------------------------

if command -v node &>/dev/null; then
  NODE_VERSION=$(node -v | sed 's/v//;s/\..*//')
  if [ "$NODE_VERSION" -ge 18 ]; then
    echo "✅ 检测到 Node.js 版本 >= 18，无需安装"
  else
    echo "⚠️ Node.js 版本过旧，升级至最新 LTS..."
    if [[ "$OS" =~ ^(centos|rocky|almalinux|rhel)$ ]]; then
      curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash -
      yum install -y nodejs
    else
      curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
      apt-get install -y nodejs
    fi
  fi
else
  echo "📦 安装 Node.js 最新 LTS..."
  if [[ "$OS" =~ ^(centos|rocky|almalinux|rhel)$ ]]; then
    curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash -
    yum install -y nodejs
  else
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y nodejs
  fi
fi



# ----------------------------
# Docker 安装（官方方式）
# ----------------------------

if command -v docker &>/dev/null; then
  echo "✅ Docker 已安装"
else
  echo "📦 安装 Docker..."
  curl -fsSL https://get.docker.com | bash
  systemctl enable docker
  systemctl start docker
fi

# ----------------------------
# Docker Compose 检查（支持 v2 或 v1）
# ----------------------------

if docker compose version &>/dev/null || docker-compose version &>/dev/null; then
  echo "✅ Docker Compose 已安装"
else
  echo "📦 安装 Docker Compose v2（附带 Docker CLI）..."
  DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f 4)
  curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
fi

# ----------------------------
# Nginx 安装
# ----------------------------

if command -v nginx &>/dev/null; then
  echo "✅ Nginx 已安装"
else
  echo "📦 安装 Nginx..."
  if [[ "$OS" =~ ^(ubuntu|debian|amzn)$ ]]; then
    apt-get install -y nginx
  elif [[ "$OS" =~ ^(centos|rocky|almalinux|rhel)$ ]]; then
    yum install -y nginx
  fi
  systemctl enable nginx
  systemctl start nginx
fi

# ===============================
# 📁 创建所需目录与配置文件（第三部分）
# ===============================

echo "📁 正在创建服务目录与配置文件..." | tee -a "$LOG_FILE"

# 创建目录
mkdir -p /home/n8n /home/n8n-auth/public /home/n8n/backups

# 写入 login.html 页面
cat > /home/n8n-auth/public/login.html <<EOF
<!DOCTYPE html>
<html lang="zh">
<head>
  <meta charset="UTF-8">
  <title>登录 N8N</title>
  <link rel="stylesheet" href="/style.css">
  <script src="https://cdnjs.cloudflare.com/ajax/libs/gsap/3.12.2/gsap.min.js" integrity="sha512-JaYZ25HVJhEiMRYTLJ+wA4PKaEpECObAzmXn4CVynb2mBQtGeYhvcohYfZ1DjRkBiMnmYzXEOKpO6l3W7xGpZg==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
</head>
<body>
  <canvas id="bg-canvas"></canvas>
  <div class="login-container">
    <h2>欢迎使用 John 一键部署版 N8N</h2>
    <form method="POST" action="/login">
      <input type="text" name="username" placeholder="用户名" required />
      <input type="password" name="password" placeholder="密码" required />
      <button type="submit">登录</button>
    </form>
    <div class="footer">Powered by JOHN</div>
  </div>
  <script>
    // 星点线线背景
    const canvas = document.getElementById('bg-canvas');
    const ctx = canvas.getContext('2d');
    let w = window.innerWidth;
    let h = window.innerHeight;
    canvas.width = w;
    canvas.height = h;
    let stars = Array.from({length: 80}, () => ({
      x: Math.random() * w,
      y: Math.random() * h,
      r: Math.random() * 1.5 + 0.5,
      vx: (Math.random() - 0.5) * 0.3,
      vy: (Math.random() - 0.5) * 0.3
    }));

    function draw() {
      ctx.clearRect(0, 0, w, h);
      for (let i = 0; i < stars.length; i++) {
        let p = stars[i];
        p.x += p.vx;
        p.y += p.vy;
        if (p.x < 0 || p.x > w) p.vx *= -1;
        if (p.y < 0 || p.y > h) p.vy *= -1;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, 2 * Math.PI);
        ctx.fillStyle = '#ffffffaa';
        ctx.fill();

        for (let j = i + 1; j < stars.length; j++) {
          let q = stars[j];
          let dx = p.x - q.x;
          let dy = p.y - q.y;
          let dist = Math.sqrt(dx * dx + dy * dy);
          if (dist < 100) {
            ctx.beginPath();
            ctx.moveTo(p.x, p.y);
            ctx.lineTo(q.x, q.y);
            ctx.strokeStyle = `rgba(255,255,255,${1 - dist / 100})`;
            ctx.stroke();
          }
        }
      }
      requestAnimationFrame(draw);
    }
    draw();

    // 动态输入框 GSAP 演练
    gsap.from("input", {opacity: 0, y: 30, stagger: 0.2, duration: 1});
    gsap.from("button", {opacity: 0, y: 30, delay: 0.6, duration: 1});
  </script>
</body>
</html>
EOF

# 写入样式文件 style.css
cat > /home/n8n-auth/public/style.css <<EOF
html, body {
  margin: 0;
  padding: 0;
  width: 100%;
  height: 100%;
  overflow: hidden;
  font-family: "Helvetica Neue", sans-serif;
  background: linear-gradient(135deg, #101e2e, #1c2f44);
}
#bg-canvas {
  position: fixed;
  top: 0;
  left: 0;
  z-index: 0;
}
.login-container {
  position: fixed;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  background-color: rgba(31, 45, 61, 0.95);
  padding: 40px;
  border-radius: 16px;
  text-align: center;
  box-shadow: 0 0 20px rgba(0, 0, 0, 0.4);
  z-index: 1;
  min-width: 320px;
  max-width: 90vw;
  backdrop-filter: blur(10px);
}
.login-container h2 {
  margin-bottom: 24px;
  color: #fff;
  font-size: 20px;
}
input {
  padding: 12px;
  margin: 10px 0;
  width: 100%;
  border-radius: 6px;
  border: none;
  box-sizing: border-box;
  transition: box-shadow 0.3s ease;
}
input:focus {
  outline: none;
  box-shadow: 0 0 5px #1890ff;
}
button {
  padding: 12px 30px;
  background-image: linear-gradient(135deg, #1890ff, #0050b3);
  color: white;
  border: none;
  border-radius: 6px;
  cursor: pointer;
  width: 100%;
  margin-top: 10px;
  font-weight: bold;
  transition: background 0.3s, transform 0.2s;
}
button:hover {
  transform: scale(1.03);
  background-image: linear-gradient(135deg, #40a9ff, #096dd9);
}
.footer {
  margin-top: 20px;
  font-size: 12px;
  color: #ccc;
  opacity: 0.6;
}
EOF

# 写入认证服务 Node.js 后端
cat > /home/n8n-auth/server.js <<EOF
const express = require('express')
const bodyParser = require('body-parser')
const cookieParser = require('cookie-parser')
const path = require('path')
const app = express()

const PORT = 3000
const USER = '${BASIC_USER}'
const PASS = '${BASIC_PASSWORD}'

app.use(bodyParser.urlencoded({ extended: true }))
app.use(cookieParser())
app.use(express.static(path.join(__dirname, 'public')))

app.use((req, res, next) => {
  if (req.path === '/login' || req.cookies.loggedIn) return next()
  return res.redirect('/login.html')
})

app.post('/login', (req, res) => {
  const { username, password } = req.body
  if (username === USER && password === PASS) {
    res.cookie('loggedIn', true, { maxAge: 86400000, httpOnly: false })
    return res.redirect('/')
  }
  return res.redirect('/login.html')
})

app.listen(PORT, () => {
  console.log(\`🔒 登录认证服务运行在端口 \${PORT}\`)
})
EOF

echo "📢 注意：本地登录认证服务将监听端口 3000，如已被其他服务占用，请在 server.js 中修改端口号。" | tee -a "$LOG_FILE"

# 写入 systemd 服务配置
cat > /etc/systemd/system/n8n-auth.service <<EOF
[Unit]
Description=Custom N8N Login Service
After=network.target

[Service]
ExecStart=/usr/bin/node /home/n8n-auth/server.js
WorkingDirectory=/home/n8n-auth
Restart=always
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

# 写入 .env 环境变量（SSL 判断）
if [[ "$ENABLE_SSL" == "yes" ]]; then
  WEBHOOK_URL="https://${DOMAIN}"
  SECURE_COOKIE=true
else
  WEBHOOK_URL="http://${DOMAIN}"
  SECURE_COOKIE=false
fi

cat > /home/n8n/.env <<EOF
GENERIC_TIMEZONE=Asia/Shanghai
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=${BASIC_USER}
N8N_BASIC_AUTH_PASSWORD=${BASIC_PASSWORD}
N8N_HOST=${DOMAIN}
WEBHOOK_TUNNEL_URL=${WEBHOOK_URL}
VUE_APP_URL=${WEBHOOK_URL}
N8N_SECURE_COOKIE=${SECURE_COOKIE}
EOF

# 写入 docker-compose 配置
cat > /home/n8n/docker-compose.yml <<EOF
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: always
    ports:
      - "5679:5678"
    env_file:
      - .env
    volumes:
      - /home/n8n:/home/node/.n8n
    networks:
      - n8n-network

networks:
  n8n-network:
    name: n8n-network
EOF

# ===============================
# 📦 安装认证服务依赖（Express 等）
# ===============================

echo "📦 安装认证服务依赖..." | tee -a "$LOG_FILE"

cd /home/n8n-auth
if [ ! -f package.json ]; then
  npm init -y
fi

npm install express body-parser cookie-parser



# ===============================
# 🌐 配置 Nginx 反向代理与访问规则（第四部分）
# ===============================

echo "🌐 配置 Nginx ..." | tee -a "$LOG_FILE"

# 创建 Nginx 配置目录（如果不存在）
mkdir -p /etc/nginx/conf.d

# 根据 SSL 开关写入对应配置
if [[ "$ENABLE_SSL" == "yes" ]]; then
  cat > /etc/nginx/conf.d/n8n.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    # 自动跳转至 HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://localhost:5679;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /login.html {
        proxy_pass http://localhost:3000/login.html;
    }

    location /style.css {
        proxy_pass http://localhost:3000/style.css;
    }

    location /login {
        proxy_pass http://localhost:3000/login;
    }
}
EOF

else
  cat > /etc/nginx/conf.d/n8n.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://localhost:5679;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /login.html {
        proxy_pass http://localhost:3000/login.html;
    }

    location /style.css {
        proxy_pass http://localhost:3000/style.css;
    }

    location /login {
        proxy_pass http://localhost:3000/login;
    }
}
EOF
fi

# 测试并重启 Nginx（防止未安装时报错）
if command -v nginx &>/dev/null; then
  nginx -t && systemctl restart nginx
fi

# ===============================
# 🔐 自动申请 SSL（仅启用 SSL 时执行）
# ===============================
if [[ "$ENABLE_SSL" == "yes" ]]; then
  echo "🔐 准备申请 SSL 证书..." | tee -a "$LOG_FILE"

  # 配置验证目录
  mkdir -p /var/www/html/.well-known/acme-challenge

  # 安装 acme.sh 脚本
  curl https://get.acme.sh | sh -s email=${EMAIL}
  export PATH="$HOME/.acme.sh":$PATH

  # 优先使用 Let's Encrypt
  ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
  ~/.acme.sh/acme.sh --issue -d ${DOMAIN} --webroot /var/www/html || \
  (
    echo "⚠️ Let's Encrypt 失败，尝试使用 ZeroSSL" | tee -a "$LOG_FILE"
    ~/.acme.sh/acme.sh --set-default-ca --server zerossl
    ~/.acme.sh/acme.sh --register-account -m ${EMAIL} --agree-tos
    ~/.acme.sh/acme.sh --issue -d ${DOMAIN} --webroot /var/www/html
  )

  # 安装证书至标准路径
  ~/.acme.sh/acme.sh --install-cert -d ${DOMAIN} \
    --key-file /etc/letsencrypt/live/${DOMAIN}/privkey.pem \
    --fullchain-file /etc/letsencrypt/live/${DOMAIN}/fullchain.pem \
    --reloadcmd "systemctl reload nginx"

  # 设置自动续签
  ~/.acme.sh/acme.sh --upgrade --auto-upgrade
fi

# ===============================
# 🚀 启动登录认证服务 + docker 容器
# ===============================

echo "🚀 启动认证服务与 N8N 容器..." | tee -a "$LOG_FILE"

# 启动认证服务
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now n8n-auth

# ===============================
# 📥 拉取最新版 n8n 镜像
# ===============================
echo "📥 拉取 n8n 官方镜像..." | tee -a "$LOG_FILE"
docker pull docker.n8n.io/n8nio/n8n


# 启动 n8n 容器
docker_compose -f /home/n8n/docker-compose.yml up -d

if [[ "$AUTO_UPDATE" == "yes" ]]; then
  echo "🔄 添加每日自动更新任务..." | tee -a "$LOG_FILE"
  cat > /home/n8n/auto-upgrade.sh <<'EOL'
#!/bin/bash
cd /home/n8n
docker pull docker.n8n.io/n8nio/n8n
docker compose -f docker-compose.yml down
docker compose -f docker-compose.yml up -d
EOL
  chmod +x /home/n8n/auto-upgrade.sh
  add_cron "0 3 * * * /home/n8n/auto-upgrade.sh >> /var/log/n8n-upgrade.log 2>&1"
fi


# ===============================
# 🛡️ 配置 UFW 防火墙（可选）
# ===============================

if command -v ufw &>/dev/null; then
  echo "🛡️ 配置 UFW 防火墙..." | tee -a "$LOG_FILE"
  ufw allow 22
  ufw allow 80
  ufw allow 443
  ufw allow 3000
  ufw allow 5679
  ufw --force enable
fi

# ===============================
# ✅ 安装完成提示
# ===============================

if [[ "$ENABLE_SSL" == "yes" ]]; then
  echo -e "\n✅ 安装完成！请访问：\e[32mhttps://${DOMAIN}/\e[0m"
else
  echo -e "\n✅ 安装完成！请访问：\e[32mhttp://${DOMAIN}/\e[0m"
fi

echo -e "🔐 默认登录账号：\e[33m${BASIC_USER}\e[0m"
echo -e "🔐 默认登录密码：\e[33m${BASIC_PASSWORD}\e[0m"
echo -e "📁 服务路径：\e[36m/home/n8n/\e[0m"
echo -e "🔒 登录认证服务：\e[36mhttp://${DOMAIN}:3000/login.html\e[0m"

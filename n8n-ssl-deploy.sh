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
    docker compose down && docker compose up -d || true
    sleep 5
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN || echo "000")
    if [[ "$STATUS" == "200" || "$STATUS" == "302" ]]; then
      echo "✅ 修复成功！状态码：$STATUS" | tee -a "$LOG_FILE"
    else
      echo "🚨 修复失败，尝试回滚至最近备份..." | tee -a "$LOG_FILE"
      if [ -f /home/n8n/backups/n8n_backup_latest.tar.gz ]; then
        docker compose down
        tar -xzf /home/n8n/backups/n8n_backup_latest.tar.gz -C /home/n8n/n8n
        docker compose up -d
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

# Docker & nginx 启动检测后执行健康检查
systemctl restart docker || echo "⚠️ Docker 重启失败" | tee -a "$LOG_FILE"
systemctl restart nginx || echo "⚠️ Nginx 重启失败" | tee -a "$LOG_FILE"

# Docker compose 尝试恢复失败后日志分析
docker compose up -d || {
  echo "❌ docker compose 启动失败，分析日志..." | tee -a "$LOG_FILE"
  docker compose logs >> "$LOG_FILE"
  echo "⚠️ 日志分析建议: 检查权限、端口占用、挂载路径。" | tee -a "$LOG_FILE"
  docker system prune -f
  docker compose down && docker compose pull && docker compose up -d || {
    echo "🚨 所有恢复方式失败，建议手动排查！" | tee -a "$LOG_FILE"
    exit 1
  }
}

health_check

cat <<EOM
✅ n8n 自定义登录部署完成！访问地址: https://$DOMAIN
📝 登录用户名: $BASIC_USER
📝 登录密码: $BASIC_PASSWORD
📦 自动备份脚本: /home/n8n/backup.sh
🧹 自动清理脚本: /home/n8n/clean-backups.sh
🚀 自动更新检测脚本: /home/n8n/check-update.sh
🚀 自动升级脚本: /home/n8n/auto-upgrade.sh
🔧 手动升级脚本: /home/n8n/upgrade-n8n.sh
📅 定时任务已设置：每天自动备份+清理+更新检查
🔐 登录认证服务 systemd 已安装并自启动
🌐 登录页面: https://$DOMAIN/login.html
⚡ Powered by John 一键部署！🚀
EOM

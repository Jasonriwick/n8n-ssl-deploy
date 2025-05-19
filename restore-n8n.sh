#!/bin/bash
echo "📦 正在恢复 N8N 配置和数据..."

read -p '🗂 请输入备份文件路径（例如 /home/n8n/backups/n8n_backup_2024-05-18.tar.gz）: ' BACKUP_PATH

if [ ! -f "$BACKUP_PATH" ]; then
  echo "❌ 找不到该备份文件。"
  exit 1
fi

echo "🧹 清空现有数据..."
rm -rf /home/n8n/n8n/*
rm -rf /home/n8n/n8ndata/*

echo "📦 解压备份数据..."
tar -xzf "$BACKUP_PATH" -C /home/n8n/n8n --strip-components=0

echo "✅ 恢复完成。请重新启动 n8n："
echo "cd /home/n8n && docker compose up -d"

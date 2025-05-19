
# 🚀 n8n-ssl-deploy 一键部署脚本

本项目提供一个 **一键部署脚本**，可帮助你在任意 Ubuntu 服务器（推荐 22.04+ / 24.04）上快速搭建 [n8n](https://n8n.io) 自动化工作流系统，并配置 HTTPS 访问（使用 Let’s Encrypt 免费证书）。

---

## ✅ 功能亮点

- 自动安装 **Docker** 和 **Docker Compose**
- 使用 `docker compose` 启动 n8n 服务，绑定指定域名
- 自动配置 **Nginx** 反向代理（监听 80 / 443）
- ✅ **支持 WebSocket 代理**，防止 Connection lost 报错
- 自动申请并配置 **SSL 证书**（Let's Encrypt）
- 数据持久化至指定 VPS 目录，防止丢失
- 自动生成每日备份（打包为 `.tar.gz`）
- 支持用户交互：首次运行会提示输入 **域名** 和 **邮箱**
- 支持一键恢复备份数据

---

## 📁 默认路径说明

| 类型       | VPS 挂载路径            | 容器内路径              |
|------------|-------------------------|--------------------------|
| 配置数据   | `/home/n8n/n8n`         | `/home/node/.n8n`        |
| 工作流数据 | `/home/n8n/n8ndata`     | `/data`（n8n 扩展目录）  |
| 备份文件   | `/home/n8n/backups`     | N/A                      |

---

## 📦 使用方法

### ✅ 1. 上传或下载脚本

```bash
curl -O https://raw.githubusercontent.com/yourusername/n8n-ssl-deploy/main/n8n-ssl-deploy.sh
chmod +x n8n-ssl-deploy.sh
```

### ✅ 2. 运行脚本

```bash
./n8n-ssl-deploy.sh
```

脚本将提示你输入：

- 绑定的域名（需已解析到该 VPS）
- 用于 SSL 申请的邮箱（接收证书续期提醒）

---

## 🌐 部署完成后访问方式

访问你的域名即可使用 n8n：

```
https://你的域名
```

默认登录凭证：

- 用户名：`admin`
- 密码：`admin123`

> ⚠️ 建议部署完成后立即登录后台，修改默认密码！

---

## 🧩 附加功能

### 🔁 自动备份（每日凌晨 2 点执行）

备份文件将保存到 `/home/n8n/backups/`，格式如下：

```
n8n_backup_2025-05-19_02:00:00.tar.gz
```

### 🔄 一键恢复脚本（如你实现）

```bash
bash restore-n8n.sh
```

---

## 🧱 系统环境要求

- 系统：Ubuntu 22.04 / 24.04
- 内存：建议 ≥ 1GB（脚本自动启用 Swap）
- 端口：必须开放 80 和 443
- 域名：已解析到 VPS 公网 IP

---

## 🔐 安全建议

- 修改默认密码后再对外开放接口
- 配置防火墙（脚本已自动启用 UFW）
- 可结合 Fail2ban / 日志分析增强安全性
- 建议绑定防火墙规则或部署在私有 VPN 内

---

## ❓ 常见问题

### ❌ 1. 证书申请失败怎么办？

请确认域名已经正确解析，并且端口 80 没有被其他服务占用（如 Apache）。

### ❌ 2. 启动后访问提示 Connection lost？

请确认 Nginx 配置中包含以下 WebSocket 设置：

```nginx
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

### 💡 3. 想迁移到新 VPS？

只需打包 `/home/n8n` 整个目录，拷贝到新机后运行：

```bash
docker compose up -d
```

---

## ✨ 授权协议

本脚本开源，MIT 协议，可自由使用和二次开发。如有建议欢迎提 Issue 或 PR。

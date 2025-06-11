# 🚀 John N8N VPS 一键部署脚本 (自定义登录页 + 自动更新 + 自动备份 + 安全防护)

快速、一键式部署 n8n 自动化流程平台，内置自定义登录认证、HTTPS 加密、防暴力破解、自动备份与更新，全面提升稳定性、安全性与性能。

适合个人开发者、中小型团队、自建自动化平台用户。

<p align="center">
  <img src="https://neveitaliafurniture.com/wp-content/uploads/2025/06/微信图片_20250609153913.png" alt="John N8N 部署示意图" width="1200">
</p>

---

## 📚 目录

- [✅ 项目亮点](#项目亮点)
- [🧐 设计理念](#设计理念)
- [⚙️ 安装部署指南](#安装部署指南)
- [📁 文件与目录结构](#文件与目录结构)
- [🌐 使用与访问](#使用与访问)
- [🛆 功能与管理](#功能与管理)
- [⚠️ 注意事项](#注意事项)
- [❓ 常见问题-FAQ](#常见问题-faq)
- [✨ 开源协议](#开源协议)
- [👨‍💻 关于作者](#关于作者)

---

## ✅ 项目亮点

| 功能模块 | 描述 |
|:--|:--|
| 🔒 自定义登录认证 | 专属登录界面 + SHA256 密码加密 |
| 🛆 自动数据备份 | 每日定时备份，防止数据丢失 |
| 🧹 自动清理旧备份 | 自动清理 10 天前旧备份，节省空间 |
| 🔄 自动检测与更新 | 自动检测新版本，备份后无缝升级 |
| 🔧 账号密码加密管理 | 强制加密存储，防止账号泄露 |
| 📝 部署信息管理 | 自动生成管理脚本，方便查询、修改 |
| 🔥 Fail2ban 防暴力破解 | 自动封禁爆破 IP，增强访问安全 |
| 📈 Nginx 性能优化 | 启用 HTTP/2 与 GZIP，提升访问速度 |
| 🎨 支持界面自定义 | 自定义登录页面、CSS 样式，美观易用 |
| 🌍 多系统兼容 | 支持 Ubuntu 20+/Debian 10+/CentOS 8+/Amazon Linux 2 |
| 🧠 自修复机制 | 自动修复 Docker、Node.js、Compose 等环境冲突或异常 |
| 🧪 环境预检测 | 部署前自动检测系统环境是否兼容，预警不支持系统 |
| 🧼 自动卸载旧组件 | 清除系统中旧版或冲突服务（如 Nginx、Certbot） |
| 🔁 回滚保障 | 脚本遇错自动中止，无破坏性操作保障原系统安全 |
| 🧾 日志追踪系统 | 所有安装与执行日志记录至 `/var/log/n8n-deploy.log` |
| 🗂 精简结构 | `/home/n8n` 与 `/home/n8n-auth` 独立部署，清晰易迁移 |
| 🔄 自动绑定 SSL | 使用 Certbot 申请 Let’s Encrypt 证书并自动续期 |

---

## 🧐 设计理念

- **安全优先**：HTTPS 加密、自定义登录认证、防暴力破解机制
- **稳定可靠**：每日自动备份、版本更新前先备份、错误即中断保障
- **性能优化**：启用 HTTP/2 和 GZIP 提升页面加载与交互速度
- **低运维成本**：一次安装，自动续期证书、自动维护，几乎零维护负担
- **专业体验**：定制品牌化登录界面，提升企业或团队形象
- **灵活可控**：配置清晰，结构简洁，支持手动或自动升级与维护

---

## ⚙️ 安装部署指南

### 系统要求

- 操作系统：Ubuntu 20.04+/Debian 10+/CentOS 8+/Amazon Linux 2
- 内存要求：最低 2GB，推荐 4GB+
- 网络配置：需开放 80（HTTP）与 443（HTTPS）端口
- 域名解析：已将你的域名解析到本机 IP

### 快速部署命令

```bash
# 下载脚本
curl -O https://raw.githubusercontent.com/Jasonriwick/n8n-ssl-deploy/main/n8n-ssl-deploy.sh

# 添加执行权限
chmod +x n8n-ssl-deploy.sh

# 执行部署脚本
./n8n-ssl-deploy.sh
```

安装过程中将提示输入：

- 🌐 你的域名（如：n8n.example.com）
- 📧 用于申请 SSL 的邮箱
- 👤 登录用户名（默认 admin）
- 🔒 登录密码（默认 admin123）
- 🔁 是否开启自动更新（yes / no）

建议首次部署完毕后，手动修改账号密码提升安全性。

---

---

## 📁 文件与目录结构

```text
/home/n8n/
├── docker-compose.yml          # 主服务配置文件
├── .env                        # 环境变量配置（包含端口、数据库路径等）
├── backup.sh                   # 手动触发备份脚本
├── clean-backups.sh            # 清理旧备份的脚本（默认保留10天）
├── check-update.sh             # 拉取镜像检查是否有新版
├── auto-upgrade.sh             # 自动升级 + 自动备份整合脚本
├── upgrade-n8n.sh              # 手动执行升级脚本
├── backups/                    # 所有备份文件目录
│   └── YYYY-MM-DD.tar.gz       # 每日打包备份文件
└── n8n/                        # n8n 主数据、配置与数据库所在目录
    └── ...

/home/n8n-auth/
├── server.js                   # 登录认证 Node 服务入口文件
└── public/
    └── login.html              # 自定义登录界面（支持自行美化与替换）
```

所有脚本路径和数据均分离部署，方便未来迁移或单独维护。

---

## 🌐 使用与访问

部署完成后，浏览器访问：

```
https://你的域名
```

输入你设定的登录账号密码，即可进入 n8n 自动化平台主界面。

⚙️ 登录前端基于 Node.js 实现认证拦截，可自定义页面与逻辑。

---

---

## 🛆 功能与管理

### 📦 服务控制命令

```bash
# 重启 Nginx 反向代理服务
systemctl restart nginx

# 重启登录认证前端
systemctl restart n8n-auth

# 查看 Docker 服务状态（确认 n8n 是否正常运行）
docker compose ps
```

### 🧪 测试访问与诊断

```bash
# 测试 HTTPS 是否可访问
curl -I https://yourdomain.com

# 查看日志输出（排查错误）
tail -n 100 /var/log/n8n-deploy.log
```

### 🔄 手动触发备份或升级

```bash
# 立即备份
bash /home/n8n/backup.sh

# 清理旧备份
bash /home/n8n/clean-backups.sh

# 检查是否有新版本
bash /home/n8n/check-update.sh

# 手动升级 n8n（含自动备份）
bash /home/n8n/upgrade-n8n.sh
```

系统会自动每日备份并保留最近 10 天的数据，升级时也会执行备份防止数据丢失。

---

## ⚠️ 注意事项

- 🛡 部署完成后 **请务必更改默认密码**，避免安全隐患。
- 💾 确保 `/home/n8n/backups/` 有足够磁盘空间，避免备份失败。
- 🔐 SSL 证书由 Certbot 自动申请与续期，请保证 80/443 端口畅通。
- 🌐 若更换域名，请重新部署或手动签发新证书。
- ⚠️ 不建议手动修改 Nginx 配置，若修改后请执行：
  
```bash
nginx -t && systemctl reload nginx
```

---

## ❓ 常见问题 - FAQ

### Q1: SSL 证书续期失败怎么办？

```bash
certbot renew --force-renewal
systemctl reload nginx
```

建议定期运行 `certbot renew --dry-run` 验证自动续期配置是否成功。

---

### Q2: 如何更改默认登录账号或密码？

编辑服务文件：

```bash
sudo nano /etc/systemd/system/n8n-auth.service
```

修改 `ExecStart` 中的环境变量或配置路径后，执行：

```bash
systemctl daemon-reexec
systemctl restart n8n-auth
```

---

### Q3: 如何迁移到新服务器？

只需将以下目录完整拷贝至新服务器：

```text
/home/n8n/
/home/n8n-auth/
```

然后重新执行安装脚本即可恢复环境和数据。

---

### Q4: 如果脚本运行失败，会破坏原系统吗？

不会。脚本内置检测机制，失败自动中止，**不会修改现有服务或覆盖系统组件**。

---

---

## ✨ 开源协议

本项目基于 **MIT License** 协议开源，允许用户自由复制、修改、再发布与商用。

完整协议可参考：[LICENSE](https://github.com/Jasonriwick/n8n-ssl-deploy/blob/main/LICENSE)

---

## 👨‍💻 关于作者

- 作者：**John**
- GitHub: [github.com/Jasonriwick](https://github.com/Jasonriwick)
- 项目主页：[n8n-ssl-deploy](https://github.com/Jasonriwick/n8n-ssl-deploy)
- 联系方式：请通过 GitHub 提交 issue 或 fork 本项目参与开发

---

📝 **即刻部署，开启你的 n8n 自动化之旅！**

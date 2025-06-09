
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

| 功能模块                         | 描述                            |
| :--------------------------------- | :---------------------------------- |
| 🔒 自定义登录认证         | 专属登录界面 + SHA256 密码加密 |
| 🛆 自动数据备份         | 每日定时备份，防止数据丢失    |
| 🧹 自动清理旧备份        | 自动清理 14 天前旧备份               |
| 🔄 自动检测与更新         | 自动检测新版本，备份后无缝升级      |
| 🔧 账号密码加密管理       | 强制加密存储，防止账号泄露        |
| 📝 部署信息管理         | 自动生成管理脚本，方便查询、修改     |
| 🔥 Fail2ban 防暴力破解 | 自动封禁爆破 IP，增强访问安全    |
| 📈 Nginx 性能优化      | 启用 HTTP/2 与 GZIP，提升访问速度    |
| 🎨 支持界面自定义        | 自定义登录页面、CSS样式      |
| 🌍 多系统兼容           | 支持 Ubuntu 20+/Debian 10+/CentOS 8+/Amazon Linux 2 |

---

## 🧐 设计理念

- **安全优先**: HTTPS 加密、认证保护、防暴力破解
- **稳定可靠**: 自动备份、自动更新、异常恢复机制
- **性能优化**: HTTP/2 与 GZIP 加速访问
- **低运维费用**: 一键式安装，基本零维护
- **专业体验**: 品牌定制登录界面，提升信任感
- **自由定制**: 支持界面、自定义 CSS 全面修改

---

## ⚙️ 安装部署指南

### 系统要求

- 操作系统: Ubuntu 20.04+/Debian 10+/CentOS 8+/Amazon Linux 2
- 硬件配置: 最低 2GB 内存（推荐 4GB+）
- 基础条件: 域名已解析到服务器 IP
- 网络要求: 80 、443 端口开放

### 快速部署

```bash
# 下载脚本
curl -O https://raw.githubusercontent.com/Jasonriwick/n8n-ssl-deploy/main/n8n-ssl-deploy.sh

# 添加执行权限
chmod +x n8n-ssl-deploy.sh

# 运行部署
./n8n-ssl-deploy.sh
```

安装过程将提示输入：

- 🌐 域名
- 📧 SSL 邮箱
- 👤 登录用户名 (admin)
- 🔒 登录密码 (admin123)
- 🤖 是否开启自动更新 (yes/no)

---

## 📁 文件与目录结构

```
/home/n8n/
├── n8n/                        
│   ├── docker-compose.yml       
│   ├── .env                     
│   ├── data/                    
│   │   ├── .n8n/                
│   │   └── database.sqlite      
│   ├── nginx/                   
│   │   ├── nginx.conf           
│   │   └── ssl/                 
│   ├── custom/                  
│   │   ├── static/              
│   │   └── views/               
├── backup/                      
└── logs/                         
```

### 📂 关键自定义路径

| 路径 | 描述 |
|:---|:---|
| `/home/n8n/n8n/custom/views/login.html` | 登录页面 HTML 模板 |
| `/home/n8n/n8n/custom/static/custom.css` | 自定义 CSS 样式文件 |
| `/home/n8n/n8n/.env` | 账户名、密码、环境变量设置位置 |
| `/home/n8n/backup/` | 自动备份存放目录 |
| `/home/n8n/n8n/data/database.sqlite` | 主数据库文件 |
| `/home/n8n/n8n/nginx/ssl/` | SSL证书存放位置 |
| `/home/n8n/logs/` | 日志输出目录 |

---

## 🌐 使用与访问

浏览器访问：

```text
https://你的域名
```

登录 John N8N 平台，输入安装时设置的用户名和密码即可。

---

## 🛆 功能与管理

### 🔍 查看部署信息

```bash
bash /home/n8n-auth/n8n-show-info.sh
```

### 📝 账号密码管理

- 查看加密账号密码

```bash
bash /home/n8n-auth/view-credentials.sh
```

- 重置账号密码

```bash
bash /home/n8n-auth/reset-credentials.sh
```

### 🛆 数据备份与恢复

- 手动备份数据

```bash
bash /home/n8n/backup.sh
```

- 查看备份文件

```bash
ls -lh /home/n8n/backups/
```

- 手动清理旧备份

```bash
bash /home/n8n/clean-backups.sh
```

- 恢复指定备份

```bash
bash /home/n8n/restore-n8n.sh
```

### 🚀 n8n 更新管理

- 手动升级

```bash
bash /home/n8n/upgrade-n8n.sh
```

- 自动更新

每日 3 次检测新版本，次日凌晨4点自动备份并升级。

### 🔥 防暴力破解 (Fail2ban)

- 查看 Fail2ban 状态

```bash
fail2ban-client status nginx-http-auth
```

系统自动封禁爆破 IP。

### 📈 性能优化 (HTTP/2 + GZIP)

Nginx 已默认启用：

- HTTP/2 提升访问效率
- GZIP 压缩页面资源

---

## ⚠️ 注意事项

- 建议部署后立即修改默认密码
- 关注硬盘空间，确保备份正常
- SSL 证书自动续期
- 建议配合 CDN/WAF 增强安全
- 更换域名需重新签发证书

---

## ❓ 常见问题-FAQ

### 1. 如何更换域名？

需重签证书并更新 Nginx 配置，推荐重新部署。

### 2. 服务器迁移？

迁移 `/home/n8n` 和 `/home/n8n-auth` 目录到新服务器，重新启动即可。

### 3. 停止自动更新？

```bash
crontab -e
# 删除 check-update.sh 和 auto-upgrade.sh 定时任务
```

---

## ✨ 开源协议

本项目基于 **MIT License** 开源，允许自由使用、修改、分发与商用。

---

## 👨‍💻 关于作者

- 作者: **John**
- 项目地址: [https://github.com/Jasonriwick/n8n-ssl-deploy](https://github.com/Jasonriwick/n8n-ssl-deploy)

---

📝 **即刻部署，开启你的 n8n 自动化之旅！**

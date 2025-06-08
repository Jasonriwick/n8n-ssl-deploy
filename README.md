# 🚀 John N8N 一键部署脚本 ( 自定义登录 + 自动更新 + 自动备份 + 安全防护 )

一键安装 `n8n` 自动化流程工具，内置自定义登录界面、安全认证、自动数据备份与清理、自动检测升级、防暴力破解、性能优化等功能。
适合中小团队、自用、自建自动化工具平台。

---

## 📚 目录

* [✅ 项目亮点](#-项目亮点)
* [🧠 设计理念](#-设计理念)
* [⚙️ 安装部署指南](#️-安装部署指南)
* [🌐 部署完成后访问方式](#-部署完成后访问方式)
* [📚 使用说明](#-使用说明)

  * [🔍 查看部署信息](#-查看部署信息)
  * [📝 账号密码管理](#-账号密码管理)
  * [📦 数据备份与管理](#-数据备份与管理)
  * [🚀 n8n 升级管理](#-n8n-升级管理)
  * [🔥 防暴力破解 (Fail2ban)](#-防暴力破解-fail2ban)
  * [📈 性能优化 (HTTP2 + GZIP)](#-性能优化-http2--gzip)
* [⚠️ 注意事项](#️-注意事项)
* [❓ 常见问题 FAQ](#-常见问题-faq)
* [✨ 开源许可](#-开源许可)
* [👨‍💻 作者信息](#-作者信息)

---

## ✅ 项目亮点

| 功能模块                          | 描述                                                |
| :---------------------------- | :------------------------------------------------ |
| 🔒 自定义登录界面                    | 替代传统 Basic Auth，提升体验，隐藏后台地址                       |
| 📦 自动数据备份                     | 每天定时备份，防止数据丢失                                     |
| 🧹 自动清理旧备份                    | 每天自动清理 14 天前旧备份，防止磁盘占满                            |
| 🔄 自动检测与更新                    | 定时检测 n8n 镜像版本，发现更新后自动备份并升级                        |
| ⏳ 一键回滚功能                      | 支持历史备份选择回滚，防止升级失败或误操作                             |
| 🔧 账号密码加密管理                   | 账号密码使用 SHA256 加密，提升安全性                            |
| 📝 部署信息查看                     | 随时查询域名、用户名、密码、管理脚本路径                              |
| 🔥 Fail2ban 防暴力破解             | 自动封禁暴力破解 IP，增强系统防护                                |
| 📈 Nginx 性能优化 (HTTP/2 + GZIP) | 开启 HTTP/2 和 GZIP，提升响应速度与访问体验                      |
| 🌍 多系统兼容                      | 支持 Ubuntu 20+/Debian 10+/CentOS 8+/Amazon Linux 2 |

---

## 🧠 设计理念

* ✅ **安全优先**：账号密码加密、Fail2ban 封禁、HTTPS 加密
* ✅ **稳定可靠**：自动备份、自动更新、自动清理旧备份
* ✅ **性能极致**：HTTP/2 提升应急，GZIP 加速网页访问
* ✅ **低综合维护成本**：一键部署，部署后基本无需运维
* ✅ **好用易上手**：自定义登录界面，专业简洁

---

## ⚙️ 安装部署指南

### 1. 系统要求

* 操作系统：Ubuntu 20.04+ / Debian 10+ / CentOS 8+ / Amazon Linux 2
* 内存：≥ 1GB（脚本自动创建 Swap）
* 域名：绑定到服务器公网 IP，且解析生效
* 端口：80 (HTTP)，443 (HTTPS) 开放

### 2. 下载并赋权

```bash
curl -O https://github.com/Jasonriwick/n8n-ssl-deploy.sh
chmod +x n8n-ssl-deploy.sh
```

### 3. 运行部署脚本

```bash
./n8n-ssl-deploy.sh
```

部署过程需填写：

* 🌐 绑定域名
* 📧 SSL 邮箱
* 👤 登录用户名（默认 admin）
* 🔒 登录密码（默认 admin123）
* 🤖 是否开启自动更新 (yes/no)

脚本自动完成：

* 安装 Docker, Nginx, Certbot
* 签发 SSL 证书
* 配置 Fail2ban 防护
* 配置 HTTP/2 + GZIP 性能优化
* 启动 n8n Docker 服务
* 部署自定义登录界面

---

## 🌐 部署完成后访问方式

浏览器访问：

```text
https://你的域名
```

输入部署时设置的用户名和密码登录 n8n 后台。

---

## 📚 使用说明

### 🔍 查看部署信息

```bash
bash /home/n8n-auth/n8n-show-info.sh
```

### 📝 账号密码管理

* 查看加密存储账号密码

```bash
bash /home/n8n-auth/view-credentials.sh
```

* 重置账号密码

```bash
bash /home/n8n-auth/reset-credentials.sh
```

### 📦 数据备份与管理

* **手动备份**

```bash
bash /home/n8n/backup.sh
```

* **查看已有备份**

```bash
ls -lh /home/n8n/backups/
```

* **手动清理 14 天前旧备份**

```bash
bash /home/n8n/clean-backups.sh
```

* **回滚到指定备份**

```bash
bash /home/n8n/restore-n8n.sh
```

### 🚀 n8n 升级管理

* **手动升级**

```bash
bash /home/n8n/upgrade-n8n.sh
```

* **自动升级**

每天 3 次检测镜像更新，次日凌晨 4:00 自动备份并升级（若有新版本）。

### 🔥 防暴力破解 (Fail2ban)

* 查看 Fail2ban 状态

```bash
fail2ban-client status nginx-http-auth
```

* 立即封禁暴力破解 IP，30 分钟自动解封。

### 📈 性能优化 (HTTP/2 + GZIP)

* **HTTP/2** 提升连接效率
* **GZIP 压缩** 加快页面加载速度，减少带宽占用

Nginx 配置已默认开启。

---

## ⚠️ 注意事项

* **务必修改默认密码！**
* **每天确认备份正常，磁盘空间充足。**
* **SSL 证书由 Certbot 自动续期。**
* **建议配合 Cloudflare WAF / CDN 增强安全性。**
* **如需更换域名请重新部署或重新申请证书。**

---

## ❓ 常见问题 FAQ

### 1. 更换域名？

需重新签发证书和修改 Nginx 配置，建议重新部署。

### 2. 迁移到新服务器？

迁移 `/home/n8n` 和 `/home/n8n-auth` 目录后，执行：

```bash
docker compose up -d
```

### 3. 停止自动更新？

```bash
crontab -e
# 删除 check-update.sh 和 auto-upgrade.sh 定时任务
```

### 4. 查看封禁 IP？

```bash
fail2ban-client status nginx-http-auth
```

---

## ✨ 开源许可

本项目基于 **MIT License** 开源，允许自由使用、修改、商用。

---

## 👨‍💻 作者信息

* 作者: **John**
* 项目地址: [https://github.com/Jasonriwick/n8n-ssl-deploy](https://github.com/Jasonriwick/n8n-ssl-deploy)

---

📝 **部署完成后，开启你的 n8n 自动化之旅！稳定、高效、安全，简单易用！**

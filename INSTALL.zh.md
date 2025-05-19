# n8n 自动安装部署脚本说明（中文）

该脚本支持一键安装 n8n 服务，并自动配置 HTTPS SSL 证书。安装完成后可通过您自己的域名访问 n8n 的 Web 界面。

## 💡 功能

- 自动安装 Docker 和 Docker Compose
- 使用 Docker Compose 部署 n8n
- 使用 NGINX 配置反向代理
- 自动签发并配置 Let's Encrypt 免费 SSL 证书
- 配置自动续期（通过 Certbot + cron）
- 安装过程提示输入域名和邮箱

## 🖥 运行环境要求

- 系统：Ubuntu 22.04 / 24.04
- 内存：推荐至少 1GB RAM（建议 2GB+）
- 域名：一个已解析到服务器公网 IP 的域名
- 端口：需开放 80 和 443 端口

## 🚀 安装命令

在终端中运行以下命令：

```bash
bash <(curl -s https://raw.githubusercontent.com/Jasonriwick/n8n-ssl-deploy/main/n8n-ssl-deploy.sh)
```

执行后将提示输入域名和邮箱地址。

## 📁 安装完成后文件目录结构

```
~/n8n/
├── docker-compose.yml
├── .env
└── nginx/
    └── n8n.conf
```

## 🧩 n8n 默认访问地址

部署完成后，你可以通过以下地址访问 n8n：

```
https://你的域名
```


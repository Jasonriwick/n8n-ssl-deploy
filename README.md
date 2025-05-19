# n8n-ssl-deploy

One-click shell script for installing n8n with Docker, Nginx, and Let's Encrypt SSL.

## Features

- Auto installs Docker and Docker Compose
- Installs n8n via Docker Compose
- Sets up NGINX reverse proxy
- Automatically issues HTTPS SSL certificate with Let's Encrypt using Certbot
- Includes auto-renew cron job
- Prompts user for domain and email

## Usage

```bash
bash <(curl -s https://raw.githubusercontent.com/Jasonriwick/n8n-ssl-deploy/main/n8n-ssl-deploy.sh)
```


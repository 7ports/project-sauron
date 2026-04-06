---
layout: default
title: Setup Guide
nav_order: 3
---

# Setup Guide

## Prerequisites

- AWS account with Route53 hosted zone for your domain (or ability to create one via Terraform)
- AWS CLI configured (SSO or IAM user)
- Terraform >= 1.6 installed
- SSH key pair for EC2 access (generate with `ssh-keygen -t rsa -b 4096`)
- A registered domain with access to update nameservers at your registrar
- Docker (for local validation)

---

## Step 1: Clone the Repository

```bash
git clone https://github.com/7ports/project-sauron.git
cd project-sauron
```

---

## Step 2: Configure Terraform

```bash
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
project_name  = "project-sauron"
aws_region    = "us-east-1"
instance_type = "t3.small"

# Paste contents of your SSH public key (cat ~/.ssh/your-key.pub)
ec2_public_key = "ssh-rsa AAAA..."

# Your IP only — keep Prometheus and SSH locked down
ssh_allowed_cidrs     = ["YOUR.IP.HERE/32"]
grafana_allowed_cidrs = ["0.0.0.0/0"]

# Set AFTER you update nameservers at registrar (see Phase 1 → DNS below)
enable_dns = false

# Static IP of your WordPress/Lightsail instance if you're preserving DNS records
wordpress_lightsail_ip = "x.x.x.x"
```

---

## Step 3: Provision AWS Infrastructure

> **If using AWS SSO**, export credentials first:
> ```bash
> eval "$(aws configure export-credentials --format env)"
> ```

```bash
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
```

Note the outputs:
- `elastic_ip` — your server's public IP
- `route53_ns_records` — nameservers to set at your domain registrar
- `ssh_command` — SSH connection command

---

## Phase 1: DNS Setup

### 1a. Update Nameservers at Registrar

Copy the 4 nameservers from `route53_ns_records` output and paste them into your domain registrar's DNS settings. Propagation takes 1–48 hours.

Verify propagation:
```bash
nslookup -type=NS yourdomain.com 8.8.8.8
```

### 1b. Enable DNS Records in Terraform

Once nameservers are confirmed propagated, update `terraform.tfvars`:
```hcl
enable_dns = true
```

Then apply:
```bash
terraform apply
```

This creates the `sauron.yourdomain.com` A record pointing to your Elastic IP.

Verify:
```bash
nslookup sauron.yourdomain.com 8.8.8.8
```

---

## Step 4: Deploy the Monitoring Stack

SSH into the EC2 instance:

```bash
ssh -i ~/.ssh/your-key ec2-user@<elastic_ip>
```

Clone the repo on EC2:

```bash
sudo git clone https://github.com/7ports/project-sauron.git /opt/project-sauron
sudo chown -R ec2-user:ec2-user /opt/project-sauron
```

Set up environment variables:

```bash
cd /opt/project-sauron
cp .env.example .env
nano .env
```

Fill in:

```bash
GRAFANA_ADMIN_PASSWORD=<generate: openssl rand -base64 18>
DOMAIN=sauron.yourdomain.com
CERTBOT_EMAIL=you@yourdomain.com
PUSH_BEARER_TOKEN_SAURON=<generate: openssl rand -base64 32>
LOKI_RETENTION_HOURS=168
```

---

## Step 5: Bootstrap TLS Certificate (First-Time Only)

Before starting nginx, obtain a Let's Encrypt certificate using certbot standalone (this temporarily binds port 80):

```bash
cd /opt/project-sauron

docker run --rm -p 80:80 \
  -v monitoring_certbot_certs:/etc/letsencrypt \
  certbot/certbot certonly --standalone \
  -d sauron.yourdomain.com \
  --email you@yourdomain.com \
  --agree-tos --non-interactive
```

> **Note:** Port 80 must be reachable from Let's Encrypt servers. The EC2 security group allows this by default.

---

## Step 6: Start the Full Stack

Run all `docker compose` commands from the **project root** (`/opt/project-sauron`), not from the `monitoring/` subdirectory. This ensures the `.env` file at the project root is loaded correctly.

```bash
cd /opt/project-sauron
docker compose -f monitoring/docker-compose.yml up -d
```

Verify all 9 containers are running:

```bash
docker compose -f monitoring/docker-compose.yml ps
```

Expected containers: `prometheus`, `grafana`, `loki`, `node-exporter`, `blackbox-exporter`, `cloudwatch-exporter`, `pushgateway`, `nginx`, `certbot`

---

## Step 7: Verify HTTPS Access

```bash
curl -sI https://sauron.yourdomain.com
# Expected: HTTP/1.1 302 Found  (Grafana redirects to /login)

curl -sL -o /dev/null -w "%{http_code}" https://sauron.yourdomain.com/login
# Expected: 200
```

Open `https://sauron.yourdomain.com` in your browser.

- Username: `admin`
- Password: the value of `GRAFANA_ADMIN_PASSWORD` from your `.env`

Dashboards are pre-provisioned in the **Project Sauron** folder.

---

## Step 8: Configure Monitoring Targets

Edit `monitoring/prometheus/prometheus.yml` and replace placeholder URLs with your real project endpoints:

```yaml
- targets:
    - https://your-frontend.com
    - https://api.your-backend.com
```

Commit and push — GitHub Actions will deploy automatically. Or reload manually:

```bash
ssh ec2-user@<elastic_ip> "curl -s -X POST http://localhost:9090/-/reload"
```

---

## Step 9: Set Up GitHub Actions (CI/CD)

Add these secrets to your GitHub repository (`Settings > Secrets and variables > Actions`):

| Secret | Value |
|---|---|
| `EC2_HOST` | Your Elastic IP |
| `EC2_SSH_KEY` | Contents of your private SSH key (`cat ~/.ssh/your-key`) |
| `EC2_USER` | `ec2-user` |

Future pushes to `main` (touching `monitoring/` or `infrastructure/`) auto-deploy to EC2.

---

## Access Prometheus (Internal Only)

Prometheus is not exposed publicly. Use an SSH tunnel:

```bash
ssh -L 9090:localhost:9090 -i ~/.ssh/your-key ec2-user@<elastic_ip>
```

Then open `http://localhost:9090`.

---

## Adding New Projects to Monitor

To monitor a new HTTP endpoint via Blackbox Exporter:

1. Edit `monitoring/prometheus/prometheus.yml` — add the URL to the `blackbox_http` targets list
2. Push to `main` (auto-deploys) or reload manually:
   ```bash
   curl -s -X POST http://localhost:9090/-/reload
   ```
3. The endpoint appears automatically in the **Web Traffic & Uptime** dashboard.

To push metrics from an application via Prometheus remote_write:

```yaml
# In your app's prometheus.yml or alloy config
remote_write:
  - url: https://sauron.yourdomain.com/metrics/push
    authorization:
      type: Bearer
      credentials: <PUSH_BEARER_TOKEN_SAURON value>
```

---

## Certificate Renewal

Certbot renewal runs automatically inside the `certbot` container (checks every 12 hours).

To force a manual renewal:

```bash
ssh ec2-user@<elastic_ip>
cd /opt/project-sauron
docker compose -f monitoring/docker-compose.yml exec certbot certbot renew --webroot -w /var/www/certbot
docker compose -f monitoring/docker-compose.yml exec nginx nginx -s reload
```

---

## Updating the Stack

```bash
# On the EC2 instance (or via GitHub Actions push):
cd /opt/project-sauron
git pull
docker compose -f monitoring/docker-compose.yml pull
docker compose -f monitoring/docker-compose.yml up -d
```

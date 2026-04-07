---
layout: default
title: Setup Guide
nav_order: 3
---

# Sauron Setup Guide

> **Claude Code users:** This guide is written so Claude Code can execute it autonomously.
> If you are an AI agent, read the entire guide before starting, then execute each phase sequentially.
> Phases 1–2 require manual steps (account access, DNS) that cannot be automated. All other phases
> can be executed without human intervention once prerequisites are in place.

---

## Prerequisites

The following must be in place before you begin. These cannot be automated.

| Requirement | Notes |
|---|---|
| AWS account with IAM user | Must have: `ec2:*`, `route53:*`, `iam:CreateRole`, `iam:AttachRolePolicy`, `ec2:AssociateIamInstanceProfile` |
| AWS CLI configured | Run `aws sts get-caller-identity` to verify. SSO or static IAM credentials both work. |
| Terraform >= 1.6 | `terraform -version` to check |
| SSH key pair | `ssh-keygen -t rsa -b 4096 -f ~/.ssh/sauron` if you don't have one |
| Registered domain | You need access to update nameservers at your domain registrar |
| Docker (local) | For local validation only — `docker --version` to check |
| Git | `git --version` to check |
| GitHub account | With the [project-sauron](https://github.com/7ports/project-sauron) repo forked or cloned |

### GitHub Repository Secrets

Set these in **Settings → Secrets and variables → Actions** before Phase 5.

| Secret Name | Value | Description |
|---|---|---|
| `EC2_HOST` | Your Elastic IP (from Terraform output) | SSH target for the deploy workflow |
| `EC2_SSH_KEY` | Contents of your private key (`cat ~/.ssh/sauron`) | Used by `appleboy/ssh-action` |
| `EC2_USER` | `ec2-user` | Default user for Amazon Linux 2023 |

---

## Phase 1: Infrastructure (Terraform)

### 1.1 — Clone and configure

```bash
git clone https://github.com/7ports/project-sauron.git
cd project-sauron
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

| Variable | Description | Example |
|---|---|---|
| `project_name` | Name prefix for all AWS resources | `project-sauron` |
| `aws_region` | AWS region to deploy into | `us-east-1` |
| `instance_type` | EC2 instance type | `t3.small` |
| `ec2_public_key` | Contents of your public SSH key | `ssh-rsa AAAA... your@email.com` |
| `ssh_allowed_cidrs` | CIDRs allowed to SSH (restrict to your IP) | `["203.0.113.1/32"]` |
| `grafana_allowed_cidrs` | CIDRs allowed to reach HTTPS (port 443) | `["0.0.0.0/0"]` |
| `enable_dns` | Whether to create Route53 A records | `false` (set true in Phase 2) |
| `wordpress_lightsail_ip` | Static IP of existing WordPress site (to preserve DNS) | `3.97.39.115` or `""` |

Get your current public IP for `ssh_allowed_cidrs`:
```bash
curl -s ifconfig.me
```

### 1.2 — Provision AWS infrastructure

> If using AWS SSO, export credentials first:
> ```bash
> eval "$(aws configure export-credentials --format env)"
> ```

```bash
# Still in infrastructure/terraform/
terraform init
terraform plan
terraform apply
```

Type `yes` when prompted. Apply takes 2–3 minutes.

### 1.3 — Record Terraform outputs

```bash
terraform output
```

Note these values — you will need them in later phases:

| Output | What it is |
|---|---|
| `elastic_ip` | Your server's public IP (never changes) |
| `route53_ns_records` | 4 nameservers to set at your domain registrar |
| `ssh_command` | Pre-built SSH command |

### 1.4 — Verify

```bash
# SSH into the instance
$(terraform output -raw ssh_command)
# Expected: you are now logged into the EC2 instance as ec2-user
exit
```

---

## Phase 2: DNS Configuration

### 2.1 — Update nameservers at your registrar

Copy the 4 nameserver values from `route53_ns_records` and set them at your domain registrar (e.g. Namecheap, Google Domains, GoDaddy). This delegates DNS control to Route53.

> **Important:** If you have an existing WordPress site at `yourdomain.com`, set `wordpress_lightsail_ip`
> in `terraform.tfvars` before this step. Terraform will create an A record preserving it automatically.

### 2.2 — Wait for propagation

Propagation takes 15 minutes to 48 hours. Check:

```bash
# Replace yourdomain.com with your actual domain
nslookup -type=NS yourdomain.com 8.8.8.8
# Expected: the 4 Route53 NS records you just set
```

### 2.3 — Enable DNS records in Terraform

Once nameservers are confirmed, update `terraform.tfvars`:

```hcl
enable_dns = true
```

Apply:

```bash
cd infrastructure/terraform
terraform apply
```

This creates the `sauron.yourdomain.com` A record pointing to your Elastic IP.

### 2.4 — Verify DNS

```bash
nslookup sauron.yourdomain.com 8.8.8.8
# Expected: returns your Elastic IP
```

---

## Phase 3: Initial Server Bootstrap

SSH into the EC2 instance:

```bash
ssh -i ~/.ssh/sauron ec2-user@<elastic_ip>
```

### 3.1 — Clone the repository

```bash
sudo git clone https://github.com/7ports/project-sauron.git /opt/project-sauron
sudo chown -R ec2-user:ec2-user /opt/project-sauron
cd /opt/project-sauron
```

### 3.2 — Install Docker

Amazon Linux 2023 needs Docker installed:

```bash
sudo dnf install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user
newgrp docker
```

Install Docker Compose plugin:

```bash
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
docker compose version
```

### 3.3 — Create the `.env` file

```bash
cp .env.example .env
nano .env  # or vi .env
```

Fill in every value:

| Variable | Description | How to get it |
|---|---|---|
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password | Generate: `openssl rand -base64 18` |
| `AWS_ACCESS_KEY_ID` | AWS key for CloudWatch exporter | IAM console — or leave blank if using instance profile |
| `AWS_SECRET_ACCESS_KEY` | AWS secret for CloudWatch exporter | IAM console — or leave blank if using instance profile |
| `AWS_REGION` | AWS region | `us-east-1` (or your region) |
| `EC2_PUBLIC_IP` | Server's public IP | From Terraform output `elastic_ip` |
| `DOMAIN` | Full subdomain for Sauron | `sauron.yourdomain.com` |
| `CERTBOT_EMAIL` | Email for Let's Encrypt alerts | `you@yourdomain.com` |
| `PUSH_BEARER_TOKEN_SAURON` | Auth token for Sauron's push endpoint | Generate: `openssl rand -base64 32` |
| `LOKI_RETENTION_HOURS` | How long to keep logs | `168` (7 days) |
| `SAURON_METRICS_URL` | Prometheus remote-write endpoint | `https://sauron.yourdomain.com/metrics/push` |
| `SAURON_LOKI_URL` | Loki push endpoint | `https://sauron.yourdomain.com/loki/api/v1/push` |
| `CLIENT_NAME` | Label for self-monitoring | `sauron` |
| `CLIENT_ENV` | Environment label | `production` |

> **Never commit `.env` to git.** It is in `.gitignore`.

### 3.4 — Bootstrap the TLS certificate (first-time only)

This step runs certbot in standalone mode (temporarily binds port 80) before nginx starts.
Port 80 must be open — the EC2 security group allows it by default.

```bash
# Run from /opt/project-sauron
docker run --rm -p 80:80 \
  -v monitoring_certbot_certs:/etc/letsencrypt \
  certbot/certbot certonly --standalone \
  -d sauron.yourdomain.com \
  --email you@yourdomain.com \
  --agree-tos --non-interactive
```

> The volume name `monitoring_certbot_certs` is referenced as external in `docker-compose.yml`.
> Docker creates it automatically when you run the certbot command above.

Verify the certificate was issued:

```bash
docker run --rm \
  -v monitoring_certbot_certs:/etc/letsencrypt:ro \
  certbot/certbot certificates
# Expected: Certificate found for sauron.yourdomain.com, VALID, expires in ~90 days
```

### 3.5 — Start the stack

Always run `docker compose` from the **project root** (`/opt/project-sauron`), not from `monitoring/`. This ensures `.env` at the project root is loaded.

```bash
cd /opt/project-sauron

docker compose \
  -f monitoring/docker-compose.yml \
  -f monitoring/docker-compose.monitoring.yml \
  up -d
```

Wait 15 seconds, then verify all containers are running:

```bash
docker compose \
  -f monitoring/docker-compose.yml \
  -f monitoring/docker-compose.monitoring.yml \
  ps
```

Expected containers (10 total): `prometheus`, `grafana`, `loki`, `node-exporter`, `blackbox-exporter`, `cloudwatch-exporter`, `pushgateway`, `nginx`, `certbot`, `alloy`

---

## Phase 4: Verify the Stack

### Checklist

- [ ] **HTTPS loads:** `curl -sI https://sauron.yourdomain.com` returns `HTTP/1.1 302 Found`
- [ ] **Grafana login works:** `curl -sL -o /dev/null -w "%{http_code}" https://sauron.yourdomain.com/login` returns `200`
- [ ] **Prometheus targets are UP:** SSH tunnel to `:9090/targets` (see below)
- [ ] **Loki receiving logs:** Query `{client="sauron"}` in Grafana Explore

Open `https://sauron.yourdomain.com` in your browser.
- Username: `admin`
- Password: value of `GRAFANA_ADMIN_PASSWORD` from your `.env`

Dashboards are pre-provisioned in the **Project Sauron** folder.

### Access Prometheus (internal only)

Prometheus is bound to `127.0.0.1:9090` and not exposed publicly. Use an SSH tunnel:

```bash
ssh -L 9090:localhost:9090 -i ~/.ssh/sauron ec2-user@<elastic_ip>
```

Then open `http://localhost:9090/targets` in your browser.
All targets should show status `UP`.

### Verify Alloy (self-monitoring) is pushing

```bash
# On EC2 — check the client label exists in Prometheus
curl -s http://localhost:9090/api/v1/label/client/values
# Expected: {"status":"success","data":["sauron"]}
```

In Grafana → Explore → select Loki datasource → run `{client="sauron"}` → confirm log lines appear.

---

## Phase 5: GitHub Actions CI/CD

### 5.1 — Set repository secrets

In GitHub → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value | Where to get it |
|---|---|---|
| `EC2_HOST` | Your Elastic IP | `terraform output elastic_ip` |
| `EC2_SSH_KEY` | Private key contents | `cat ~/.ssh/sauron` |
| `EC2_USER` | `ec2-user` | Hardcoded for Amazon Linux 2023 |

### 5.2 — Trigger a manual deploy

```bash
# From your local machine
gh workflow run deploy.yml --repo 7ports/project-sauron
```

Or push any change to a file under `monitoring/` or `infrastructure/`:

```bash
echo "# trigger" >> monitoring/prometheus/prometheus.yml
git add monitoring/prometheus/prometheus.yml
git commit -m "chore: trigger first CI deploy"
git push origin main
```

### 5.3 — Verify the deploy succeeded

```bash
gh run list --workflow=deploy.yml --limit=3
```

Expected: most recent run shows `✓ completed — success`.

---

## Certificate Renewal

The `certbot` container checks for renewal every 12 hours automatically.

To force a manual renewal:

```bash
ssh ec2-user@<elastic_ip>
cd /opt/project-sauron

docker compose -f monitoring/docker-compose.yml exec certbot \
  certbot renew --webroot -w /var/www/certbot

docker compose -f monitoring/docker-compose.yml exec nginx nginx -s reload
```

---

## Updating the Stack

```bash
# Push to main — GitHub Actions deploys automatically.
# Or manually on EC2:
cd /opt/project-sauron
git pull
docker compose \
  -f monitoring/docker-compose.yml \
  -f monitoring/docker-compose.monitoring.yml \
  pull
docker compose \
  -f monitoring/docker-compose.yml \
  -f monitoring/docker-compose.monitoring.yml \
  up -d
```

---

## Adding New Projects to Monitor

To monitor an HTTP endpoint via Blackbox Exporter:

1. Edit `monitoring/prometheus/prometheus.yml` — add the URL to the `blackbox_http` targets list
2. Push to `main` (auto-deploys via GitHub Actions)

To onboard a full project (custom dashboard, alert rules, Alloy agent), use the [Helldiver pipeline](helldiver.md).

---

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---|---|---|
| `nginx -s reload` fails in deploy | nginx container not running | `docker compose up -d nginx` first |
| Grafana datasource shows red / UID mismatch | Dashboard JSON references wrong datasource UID | In Grafana → Connections → Data sources → Prometheus — copy the UID and update dashboard JSON `uid` fields to match |
| `.env` variables not loaded | `docker compose` run from wrong directory | Always run from `/opt/project-sauron`, not from `monitoring/` |
| SSH timeout from GitHub Actions | Security group missing inbound rule on port 22 | Add `0.0.0.0/0` → port 22 to the EC2 security group (or restrict to GitHub Actions IP ranges) |
| certbot fails: port 80 already in use | nginx running before certbot bootstrap | Stop nginx: `docker compose stop nginx` then re-run certbot command |
| Prometheus target `DOWN` for node-exporter | Container not on `monitoring` network | `docker network inspect monitoring_monitoring` — ensure `node-exporter` is listed |
| Alloy container exits immediately | Missing env var in `.env` | Check `docker logs alloy` — look for `env(): variable not found` |
| Push returns `401 Unauthorized` | Bearer token mismatch | Verify `PUSH_BEARER_TOKEN_SAURON` in `.env` matches the token nginx validates. Restart nginx after `.env` change: `docker compose restart nginx` |

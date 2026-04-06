---
layout: default
title: Setup Guide
nav_order: 3
---

# Setup Guide

## Prerequisites

- AWS account with programmatic access (for Terraform)
- AWS CLI configured (`aws configure`)
- Terraform >= 1.6 installed
- SSH key pair (generate with `ssh-keygen -t ed25519`)
- Docker (for local testing)

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
- Paste your SSH public key into `ec2_public_key`
- Set `ssh_allowed_cidrs` to your IP (`curl ifconfig.me`)
- Adjust `aws_region` if needed

---

## Step 3: Provision AWS Infrastructure

```bash
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
```

Note the outputs:
- `elastic_ip` — your server's IP
- `grafana_url` — Grafana dashboard URL
- `ssh_command` — SSH connection command

---

## Step 4: Deploy the Monitoring Stack

SSH into the EC2 instance:

```bash
ssh -i ~/.ssh/your-key.pem ec2-user@<elastic_ip>
```

Set up environment variables:

```bash
cd /opt/project-sauron
cp .env.example .env
nano .env  # Fill in GRAFANA_ADMIN_PASSWORD, AWS credentials
```

Start the stack:

```bash
cd monitoring
docker compose up -d
```

Verify all containers are running:

```bash
docker compose ps
```

---

## Step 5: Configure Monitoring Targets

Edit `monitoring/prometheus/prometheus.yml` and replace the placeholder URLs with your real project URLs:

```yaml
- targets:
    - https://your-frontend.com
    - https://api.your-backend.com
```

Reload Prometheus (without restart):

```bash
curl -X POST http://localhost:9090/-/reload
```

---

## Step 6: Access Grafana

Open `http://<elastic_ip>:3000` in your browser.

- Username: `admin`
- Password: the value of `GRAFANA_ADMIN_PASSWORD` from your `.env`

Dashboards are pre-provisioned and will appear in the **Project Sauron** folder.

---

## Step 7: Set Up GitHub Actions (CI/CD)

Add the following secrets to your GitHub repository (`Settings > Secrets and variables > Actions`):

| Secret | Value |
|---|---|
| `EC2_HOST` | Your Elastic IP |
| `EC2_SSH_KEY` | Contents of your private SSH key |
| `EC2_USER` | `ec2-user` |

Future pushes to `main` (touching `monitoring/` or `infrastructure/`) will auto-deploy to the EC2 instance.

---

## Step 8: Access Prometheus (Optional)

Prometheus is internal-only. Use an SSH tunnel to access it locally:

```bash
ssh -L 9090:localhost:9090 -i ~/.ssh/your-key.pem ec2-user@<elastic_ip>
```

Then open `http://localhost:9090` in your browser.

---

## Adding New Projects to Monitor

To add a new HTTP endpoint to monitor:

1. Edit `monitoring/prometheus/prometheus.yml`, add the URL to the `blackbox_http` targets list
2. Reload Prometheus: `curl -X POST http://localhost:9090/-/reload`
3. The endpoint will appear automatically in the **Web Traffic & Uptime** dashboard

---

## Updating the Stack

```bash
# On the EC2 instance:
cd /opt/project-sauron
git pull
cd monitoring
docker compose pull
docker compose up -d
```

Or simply push to `main` — GitHub Actions will handle the deployment automatically.

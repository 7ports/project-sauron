# Project Sauron

> *One stack to see them all.*

A self-hosted observability platform providing comprehensive monitoring for all personal projects — web traffic, API health, host metrics, and AWS services — in a single Grafana interface.

**Live docs:** [7ports.github.io/project-sauron](https://7ports.github.io/project-sauron)

---

## Stack

| Component | Purpose |
|---|---|
| **Prometheus** | Metrics collection & time-series storage |
| **Grafana** | Dashboards & visualization |
| **Node Exporter** | EC2 host metrics (CPU, memory, disk) |
| **Blackbox Exporter** | HTTP uptime & SSL certificate monitoring |
| **CloudWatch Exporter** | AWS service metrics (EC2, Lambda, S3) |
| **Terraform** | AWS infrastructure as code |
| **Docker Compose** | Container orchestration on EC2 |

---

## Dashboards

| Dashboard | Monitors |
|---|---|
| Web Traffic & Uptime | Frontend uptime, response time, SSL cert expiry |
| API & Host Overview | Backend API health, EC2 CPU/memory/disk |
| AWS Overview | CloudWatch: EC2, Lambda, S3 metrics |

---

## Architecture

```
Your Projects (HTTP) ──► Blackbox Exporter ──┐
EC2 Host             ──► Node Exporter    ──┤──► Prometheus ──► Grafana
AWS CloudWatch       ──► CW Exporter      ──┘
```

All services run on a single `t3.small` EC2 instance via Docker Compose. Prometheus is internal-only; Grafana is accessible at `http://<elastic-ip>:3000`.

---

## Quick Start

**Prerequisites:** AWS CLI, Terraform >= 1.6, SSH key pair

```bash
# 1. Clone
git clone https://github.com/7ports/project-sauron.git
cd project-sauron

# 2. Provision infrastructure
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your SSH key and IP
terraform init && terraform apply

# 3. SSH in and start the stack
ssh -i ~/.ssh/your-key.pem ec2-user@<elastic-ip>
cd /opt/project-sauron
cp .env.example .env && nano .env  # Set your passwords
cd monitoring && docker compose up -d

# 4. Open Grafana
open http://<elastic-ip>:3000
```

See the [full setup guide](https://7ports.github.io/project-sauron/setup) for detailed instructions.

---

## Repository Structure

```
project-sauron/
├── .github/workflows/   # CI/CD: auto-deploy to EC2, GitHub Pages
├── .claude/agents/      # Voltron AI agents (devops, planner, scrum-master)
├── docs/                # GitHub Pages documentation
├── infrastructure/
│   └── terraform/       # EC2, VPC, IAM, Elastic IP
└── monitoring/
    ├── docker-compose.yml
    ├── prometheus/       # Scrape configs & alert rules
    ├── grafana/          # Provisioning & dashboards
    └── exporters/        # Blackbox & CloudWatch configs
```

---

## Adding a Project to Monitor

Edit `monitoring/prometheus/prometheus.yml` and add your URL to the `blackbox_http` targets:

```yaml
- targets:
    - https://your-project.com
    - https://api.your-project.com
```

Then reload Prometheus:

```bash
curl -X POST http://localhost:9090/-/reload
```

---

## CI/CD

Pushes to `main` trigger:
- **Deploy workflow** (changes to `monitoring/` or `infrastructure/`): SSH to EC2 → `git pull` → `docker compose up -d`
- **Docs workflow** (changes to `docs/`): Jekyll build → deploy to GitHub Pages

Required GitHub secrets: `EC2_HOST`, `EC2_SSH_KEY`, `EC2_USER`

---

## AI Agent Support

This project is scaffolded with [Project Voltron](https://github.com/7ports/project-voltron) agents. Invoke them in Claude Code:

- `@agent-devops-engineer` — Terraform, Docker Compose, GitHub Actions changes
- `@agent-project-planner` — Architecture research and planning
- `@agent-scrum-master` — Work breakdown and task coordination

---

## License

MIT

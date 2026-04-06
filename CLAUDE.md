# CLAUDE.md — Project Context

> This file is automatically loaded by Claude Code at session start.
> Keep it up to date as your project evolves. Agents read this before acting.

---

## Project Identity

**Project Name:** Project Sauron
**Type:** Observability Platform (Infrastructure / DevOps)
**Language / Framework:** YAML, HCL (Terraform), Docker Compose, Shell
**Status:** Alpha — initial scaffold

**GitHub:** https://github.com/7ports/project-sauron
**Docs:** https://7ports.github.io/project-sauron

---

## Purpose

Project Sauron provides comprehensive observability for all of Rajesh's personal projects. It runs Grafana + Prometheus on a single AWS EC2 instance (Docker Compose), monitoring:

- **Frontend / Web Traffic** — HTTP uptime, response time, status codes (via Blackbox Exporter)
- **Backend APIs** — request rates, error rates, latency (scraped from API services)
- **AWS Services** — EC2 host metrics, CloudWatch metrics (EC2, Lambda, S3)

---

## Repository Layout

```
project-sauron/
├── .claude/
│   ├── agents/                  # Voltron agent definitions
│   │   ├── scrum-master.md
│   │   ├── project-planner.md
│   │   └── devops-engineer.md
│   └── settings.json            # Voltron auto-update hook
├── .github/
│   └── workflows/
│       ├── deploy.yml           # SSH to EC2, docker compose up -d
│       └── docs.yml             # Build & deploy GitHub Pages
├── docs/                        # GitHub Pages (Jekyll, Cayman theme)
│   ├── _config.yml
│   ├── index.md
│   ├── architecture.md
│   ├── setup.md
│   └── dashboards.md
├── infrastructure/
│   └── terraform/               # EC2, VPC, security groups, IAM, Elastic IP
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
├── monitoring/
│   ├── docker-compose.yml       # All containers: Prometheus, Grafana, exporters
│   ├── prometheus/
│   │   ├── prometheus.yml       # Scrape configs
│   │   └── rules/
│   │       ├── alerting.yml
│   │       └── recording.yml
│   ├── grafana/
│   │   ├── provisioning/
│   │   │   ├── datasources/prometheus.yml
│   │   │   └── dashboards/dashboard.yml
│   │   └── dashboards/          # Pre-built dashboard JSON files
│   │       ├── web-traffic.json
│   │       ├── api-overview.json
│   │       └── aws-overview.json
│   └── exporters/
│       ├── cloudwatch-exporter.yml
│       └── blackbox.yml
├── scripts/
│   └── voltron-run.sh           # Voltron Docker launcher
├── Dockerfile.voltron           # Voltron agent runtime
├── .env.example                 # Required environment variables
└── README.md
```

---

## Key Dependencies

| Component | Version | Notes |
|---|---|---|
| Prometheus | latest | Time-series metrics store |
| Grafana | latest | Visualization & dashboards |
| node-exporter | latest | EC2 host metrics (CPU, mem, disk) |
| blackbox-exporter | latest | HTTP probing for frontend/API endpoints |
| cloudwatch-exporter | latest | AWS CloudWatch metrics bridge |
| Terraform | >= 1.6 | AWS infrastructure as code |
| Docker Compose | v2 | Local container orchestration on EC2 |

---

## Deployment Target

- **Provider:** AWS
- **Compute:** EC2 `t3.small` with Elastic IP
- **Ports:** 22 (SSH), 3000 (Grafana — public), 9090 (Prometheus — internal only)
- **IAM:** Instance role with CloudWatch read permissions
- **Region:** `us-east-1` (default, configurable in tfvars)

---

## Secrets & Environment Variables

Never commit secrets. See `.env.example` for required variables. On the EC2 instance, copy `.env.example` to `.env` and fill in values. GitHub Actions uses repository secrets.

Required secrets:
- `GRAFANA_ADMIN_PASSWORD`
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (for CloudWatch exporter)
- `AWS_REGION`
- `EC2_PUBLIC_IP`
- `EC2_HOST` / `EC2_SSH_KEY` (for GitHub Actions deploy)

---

## Verification Commands

```bash
# Validate docker-compose syntax
docker compose -f monitoring/docker-compose.yml config

# Validate Terraform
cd infrastructure/terraform && terraform init && terraform validate

# Check Prometheus config syntax
docker run --rm -v $(pwd)/monitoring/prometheus:/etc/prometheus \
  prom/prometheus --config.file=/etc/prometheus/prometheus.yml --check-config

# Start the stack locally (for testing)
cd monitoring && docker compose up -d
```

**Definition of done for any task:**
1. Docker Compose stack starts without errors
2. Prometheus targets are UP (visible at :9090/targets)
3. Grafana dashboards load without errors
4. Terraform plan produces no errors
5. Changes committed with a descriptive message

---

## Active Work

**Current goal:** Initial scaffold — get the stack running on EC2

**In progress:**
- [ ] Provision EC2 via Terraform
- [ ] Configure monitoring targets (replace placeholder URLs)
- [ ] Deploy stack to EC2

**Recently completed:**
- [x] Repository scaffolded
- [x] Docker Compose stack defined
- [x] Grafana dashboards provisioned
- [x] Terraform infrastructure defined
- [x] GitHub Pages docs created
- [x] CI/CD workflows created

**Known issues / tech debt:**
- Placeholder target URLs in `monitoring/prometheus/prometheus.yml` — update with real endpoints
- No alertmanager configured yet — alerts defined but not routed

---

## Agent Team Roles

| Agent | File | Purpose |
|---|---|---|
| `scrum-master` | `.claude/agents/scrum-master.md` | Work breakdown, task assignment, sprint coordination |
| `project-planner` | `.claude/agents/project-planner.md` | Architecture research, design, project planning |
| `devops-engineer` | `.claude/agents/devops-engineer.md` | Terraform, Docker, GitHub Actions, AWS |

**Invoke with:** `@agent-scrum-master`, `@agent-project-planner`, `@agent-devops-engineer`

---

## Docker Execution

The scrum-master launches specialist agents inside Docker containers automatically via the `run_agent_in_docker` MCP tool. Each agent runs with `--dangerously-skip-permissions` for fully autonomous execution.

**Prerequisites:**
- Docker must be installed and running
- `Dockerfile.voltron` must exist in the project root

---

## Important Project Decisions

| Date | Decision | Reason |
|---|---|---|
| 2026-04-05 | EC2 + Docker Compose over ECS/EKS | Simpler, lower cost for personal projects |
| 2026-04-05 | t3.small instance | Balance of cost and capacity for observability workloads |
| 2026-04-05 | Blackbox Exporter for frontend | No code changes needed in monitored apps |
| 2026-04-05 | CloudWatch Exporter for AWS metrics | Unified Grafana view across all signal types |

---

## MCP Tools Available

- **git** — version control operations
- **github** — PR/issue management
- **memory** — persist decisions and patterns across sessions
- **fetch** — docs, changelogs, API references
- **alexandria** — tooling setup guides; **mandatory** — call `quick_setup` before installing any tool

---

## Session Closeout Protocol

```
mcp__project-voltron__submit_reflection({
  project_name: "project-sauron",
  project_type: "general",
  session_summary: "[what was accomplished]",
  agents_used: ["list", "of", "agents", "invoked"],
  agent_feedback: [{ agent: "...", needs_improvement: "...", suggested_change: "..." }],
  overall_notes: "..."
})
```

---

## Things Claude Should Never Do

- Commit secrets, credentials, or API keys
- Delete files without explicit user confirmation
- Make changes outside the project scope
- Skip tests when modifying existing functionality
- Modify `.env` files (only `.env.example`)

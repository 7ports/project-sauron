# Project Plan: Project Sauron + Project Helldiver

> **Generated:** 2026-04-06
> **Status:** Ready for scrum-master decomposition
> **Supersedes:** Previous single-project scaffold plan

---

## Overview

This plan covers two complementary projects that together form a personal observability platform and AI-powered onboarding engine.

**Project Sauron** is an **installable, self-hosted observability platform** — a Prometheus + Grafana + Loki stack on EC2 (Docker Compose + Terraform) that anyone can clone and deploy as their own monitoring hub. The repo is the platform; each deployment is an independent instance. Rajesh's personal instance runs at `sauron.7ports.ca`, but any deployer can point it at their own domain by setting `DOMAIN=yourdomain.com` in their `.env` and `terraform.tfvars`. All instance-specific values (domain, credentials, AWS account, Route53 zone) are gitignored and never committed. A running Sauron instance accepts metrics via Prometheus remote_write and logs via Loki's push API from Grafana Alloy agents running on each client project.

> **Platform vs. instance:** The `7ports/project-sauron` GitHub repo is the platform. `sauron.7ports.ca` is one instance of it. This is the same model as project-voltron: anyone can install their own instance, configure it for their domain, and deploy it to their own AWS account.

**Project Helldiver** is the onboarding squad — a specialized team of AI agents that analyzes any arbitrary project, determines what to instrument, configures a Sauron hub instance to receive its telemetry, generates Grafana dashboards, and validates the integration end-to-end. Helldiver inherits Voltron's infrastructure (Docker orchestration, Alexandria integration, reflection pipeline) and adds domain-specific observability agents.

---

## Architecture Decisions

| Decision | Choice | Rationale | Alternatives Considered |
|---|---|---|---|
| Logging backend | **Loki (monolithic)** | Built-in Grafana datasource (no plugin required), native Alloy integration, same Grafana Labs ecosystem as Prometheus/Grafana. Monolithic mode supports ~20GB/day — far beyond personal project needs. With Docker `mem_limit: 400m`, fits on t3.small. | VictoriaLogs: 50–150MB RAM (better fit), but requires community Grafana plugin, smaller ecosystem. Graylog/OpenSearch: require 4–8GB RAM — non-starter on t3.small. |
| Log shipping agent | **Grafana Alloy** | Single agent handles both metrics push (remote_write) and log push (Loki). Official successor to Promtail (EOL March 2026) and Grafana Agent (EOL Nov 2025). One Docker service per client instead of two. Built-in `prometheus.exporter.unix` eliminates separate node_exporter for dev machines. | Promtail: EOL — do not use. Fluent Bit: better memory profile but separate agent from metrics, more config overhead. |
| Metrics push protocol | **Prometheus remote_write** (native receiver) | Hub Prometheus accepts pushes via `--web.enable-remote-write-receiver` (stable since v2.33). No extra infrastructure. Clients scrape themselves locally and push upstream; no inbound firewall rules needed at client. | Federation: requires hub to reach client `/federate` endpoint — breaks for NAT'd dev machines. Mimir/Thanos: multi-tenant, overkill for personal use. |
| Client connectivity (dev machines) | **Push over HTTPS + Bearer token** | Dev machines are NAT'd — hub cannot scrape inbound. Clients push to `https://sauron.7ports.ca`. Bearer token in Alloy config authenticates the push. Simple, no VPN required. | Tailscale: excellent security but requires installing Tailscale on every dev machine and EC2; adds operational dependency. mTLS: strongest but requires CA management. |
| TLS + reverse proxy | **nginx + Certbot (Let's Encrypt)** in Docker | Free cert auto-renewal, no ALB cost (~$16/mo). nginx handles: HTTPS termination, redirect :80→:443, proxy to Grafana:3000, auth validation on push endpoints. | AWS ACM + ALB: adds cost and complexity. Direct Grafana TLS: harder cert management, no push endpoint protection. |
| Push endpoint security | **Bearer token via nginx `auth_request`** | nginx validates `Authorization: Bearer <token>` header before proxying to Prometheus remote_write and Loki push. Token stored as `PUSH_BEARER_TOKEN` secret. Simple, stateless, works from any client. | Basic auth: works but base64-encoded credentials in config files are awkward. IP allowlist: fragile with dynamic IPs. |
| Loki multi-tenancy | **Single tenant (`auth_enabled: false`)** | All personal projects can share one Loki tenant. Grafana queries with no tenant header. Add `X-Scope-OrgID` via nginx if multi-tenant ever needed. | Multi-tenant mode: adds X-Scope-OrgID header management, no benefit for personal use. |
| Loki storage | **Local filesystem** | t3.small has 20GB gp3 volume. With 7-day log retention and personal project volumes (<100MB/day), local storage is sufficient. No S3 cost or complexity. | S3: better for production, unnecessary here. |
| Pushgateway | **Included** | Handles metrics from ephemeral/serverless jobs (Cloudflare Workers, Lambda invocations, cron scripts) that can't be scraped. Standard Prometheus pattern. | Not included: would leave serverless metrics with no path to Sauron. |
| Distributed tracing | **Deferred** | Tempo/Jaeger add 512MB+ RAM overhead. Personal projects rarely have >2 internal service hops. Revisit if any monitored project spans multiple services with latency budgets. | Tempo (Grafana-native): good fit but memory cost not justified yet. |
| DNS | **Route53 hosted zone + A record via Terraform** | `7ports.ca` has no Route53 hosted zone (confirmed via AWS research — only `yyz.live` exists). Terraform creates `aws_route53_zone.root` for `7ports.ca`, outputs NS records for registrar update, then creates `sauron.7ports.ca` A record. IaC for repeatability. **Migration note:** WordPress site on Lightsail also uses `7ports.ca`; its apex/www records must be added to the new Route53 zone before nameserver migration at the registrar. | Manual console: not repeatable. Cloudflare DNS: fine but adds another provider. |
| Bearer token model | **One token per client** | Per-client tokens allow revoking one client's access without affecting others. Helldiver generates and stores tokens during onboarding. | Shared token: simpler but one compromised client exposes all. |
| Helldiver inheritance model | **Fork Voltron scaffold** | Helldiver inherits Dockerfile.voltron, voltron-run.sh, Alexandria integration, auto-update hook, and reflection pipeline. Agent team is domain-specific (observability) but uses identical orchestration. | Standalone repo with no Voltron infrastructure: loses agent orchestration, Alexandria knowledge, reflection pipeline. |

---

## project-sauron Architecture

### Hub Component Map

```
Internet
  │
  ├─ :443 (HTTPS) ──► nginx ──────────────────────────────────────────────────────┐
  │                            │                                                   │
  │                     auth_request (Bearer token check)                         │
  │                            │                                                   │
  │                   ┌────────┼────────────────────────┐                         │
  │                   ▼        ▼                        ▼                         │
  │              Grafana    Prometheus              Loki                           │
  │              :3000      :9090/api/v1/write      :3100/loki/api/v1/push        │
  │              (proxy)    (remote_write recv)     (log push recv)                │
  │                   │        │                                                   │
  │                   │        ├─ scrapes ──► node-exporter :9100                 │
  │                   │        ├─ scrapes ──► blackbox-exporter :9115             │
  │                   │        ├─ scrapes ──► cloudwatch-exporter :9106           │
  │                   │        ├─ scrapes ──► pushgateway :9091                   │
  │                   │        └─ scrapes ──► prometheus self :9090               │
  │                   │                                                            │
  │                   └─ datasources ──► Prometheus + Loki (internal Docker net)  │
  │                                                                                │
  └─ :80 (HTTP) ───► nginx (redirect → HTTPS)                                     │
                                                                                   │
DNS:  sauron.7ports.ca  A  →  EC2 Elastic IP  (Route53, managed by Terraform)     │
Security Group: 22 (SSH), 80 (HTTP), 443 (HTTPS) only — all other ports internal  ┘
```

### Client Telemetry Ingestion Model

```
Client Type          Metrics                                    Logs
──────────────────── ──────────────────────────────────────── ────────────────────────────────────────
Dev laptop/desktop   Alloy → remote_write → sauron:443/push   Alloy → loki.write → sauron:443/loki
Production EC2/VPS   Alloy → remote_write → sauron:443/push   Alloy → loki.write → sauron:443/loki
Fly.io app           Alloy → remote_write → sauron:443/push   Alloy → loki.write → sauron:443/loki
Cloudflare Worker    Worker → Pushgateway → sauron:443/push   Worker → loki push → sauron:443/loki
Static S3/CloudFront Blackbox probing (hub probes outbound)   N/A (no server-side logs)
```

**Push model rationale:** All real client types are either NAT'd (dev machines) or push-friendly (serverless). Using push from every client simplifies the security model — Sauron exposes one HTTPS+Bearer endpoint, no VPN or per-client firewall rules required.

### Minimal Client Agent Set

Every client project runs **one Docker service** added to its existing `docker-compose.yml`:

```yaml
# docker-compose.monitoring.yml  (override, not replacing existing compose)
services:
  alloy:
    image: grafana/alloy:latest
    restart: unless-stopped
    volumes:
      - ./monitoring/alloy/config.alloy:/etc/alloy/config.alloy:ro
      - /var/log:/var/log:ro
    environment:
      - SAURON_URL=https://sauron.7ports.ca
      - SAURON_TOKEN=${SAURON_PUSH_TOKEN}
      - CLIENT_NAME=${CLIENT_NAME}   # e.g. "my-api", "portfolio-site"
    command: run /etc/alloy/config.alloy
```

The `config.alloy` file:
- Discovers and ships log files from `/var/log` and Docker container logs
- Collects host metrics (CPU, mem, disk, net) via built-in `prometheus.exporter.unix`
- Tags all metrics and logs with `client=<CLIENT_NAME>` for filtering in Grafana
- Pushes metrics to `${SAURON_URL}/metrics/push` with Bearer token header
- Pushes logs to `${SAURON_URL}/loki/api/v1/push` with Bearer token header

### Per-Client Sauron Resources

Each onboarded client gets a dedicated set of files committed to the sauron repo:

| File | Location | Purpose |
|---|---|---|
| Prometheus label filter | `prometheus.yml` scrape_configs entry | Accepts `client=<name>` remote_write streams |
| Alert rules | `prometheus/rules/<client-name>.yml` | Client-specific alert thresholds |
| Grafana dashboard | `grafana/dashboards/<client-name>.json` | Pre-built panels for that stack |
| Log stream config | `grafana/provisioning/datasources/loki.yml` | No change needed — Loki datasource is global |

---

## project-helldiver Architecture

### Repo Structure

```
project-helldiver/
├── .claude/
│   ├── agents/
│   │   ├── recon-agent.md             # Stack fingerprinting
│   │   ├── instrumentation-engineer.md # Exporter/agent selection
│   │   ├── sauron-config-writer.md     # Hub-side config generation
│   │   ├── dashboard-generator.md      # Grafana dashboard JSON
│   │   ├── client-onboarding-agent.md  # Client-side Alloy config
│   │   ├── validation-agent.md         # Config syntax + smoke test
│   │   └── docs-agent.md              # Runbook + CLAUDE.md updates
│   └── settings.json                  # Voltron auto-update hook (identical to sauron's)
├── .github/
│   └── workflows/
│       └── docs.yml                   # GitHub Pages deploy
├── docs/                              # GitHub Pages (Jekyll, Cayman theme)
│   ├── _config.yml
│   ├── index.md
│   ├── agents.md                      # Agent team docs
│   └── onboarding-guide.md
├── scripts/
│   └── voltron-run.sh                 # Identical to Voltron's launcher
├── Dockerfile.voltron                 # Identical to Voltron's
├── .env.example
├── CLAUDE.md
└── README.md
```

### Voltron Inheritance Model

Helldiver does **not** re-implement agent orchestration — it inherits Voltron's entire runtime:

| Inherited Component | How Inherited | Helldiver Customization |
|---|---|---|
| `Dockerfile.voltron` | Copied verbatim | None — same Claude Code agent runtime |
| `scripts/voltron-run.sh` | Copied verbatim | Mounts Helldiver workspace |
| `.claude/settings.json` | Copied and updated | `project_name: "project-helldiver"` |
| Alexandria integration | Via MCP in CLAUDE.md | Helldiver agents call `mcp__alexandria__*` |
| Reflection pipeline | `submit_reflection` at session end | `project_name: "project-helldiver"` |
| Scrum-master agent | Defined in `.claude/agents/scrum-master.md` | Helldiver-specific task context |

---

## Helldiver Agent Team

The onboarding workflow is a **linear pipeline with one parallel fork**:

```
recon-agent
    │
    ▼
instrumentation-engineer
    │
    ├──────────────────────────────────┐
    ▼                                  ▼
sauron-config-writer          client-onboarding-agent
    │                                  │
    ▼                                  │
dashboard-generator                   │
    │                                  │
    └──────────────┬───────────────────┘
                   ▼
           validation-agent
                   │
                   ▼
             docs-agent
```

---

### Agent 1: `recon-agent`

**Role:** Analyze a target project repository and produce a structured fingerprint.

**Inputs:**
- GitHub repo URL (or local path mounted into Docker)
- Optional: existing monitoring config paths to avoid duplication

**Process:**
1. Clone/read the repo
2. Detect: primary language(s), framework(s), runtime
3. Detect: deployment target (Docker Compose, Fly.io, plain process, Lambda, Cloudflare Workers)
4. Detect: existing monitoring (Prometheus scrape endpoint? OpenTelemetry? Existing Alloy/Promtail?)
5. Scan for: log file locations, Docker service names, exposed ports
6. Detect: database type (Postgres, Redis, MySQL) for exporter selection
7. Check if project already has a Sauron dashboard (idempotency guard)

**Output:** `fingerprint.json`
```json
{
  "project_name": "my-api",
  "repo_url": "https://github.com/7ports/my-api",
  "language": ["python"],
  "framework": ["fastapi"],
  "runtime": "docker-compose",
  "deploy_target": "fly.io",
  "databases": ["postgresql", "redis"],
  "log_paths": ["/var/log/app/*.log"],
  "existing_metrics_endpoint": "/metrics",
  "existing_monitoring": false,
  "already_onboarded": false
}
```

**Handoff:** Passes `fingerprint.json` to `instrumentation-engineer`.

---

### Agent 2: `instrumentation-engineer`

**Role:** Map the project fingerprint to a concrete set of exporters, Alloy components, and instrumentation requirements.

**Inputs:** `fingerprint.json`

**Process:**
1. Consult Alexandria for known exporter patterns for detected stack
2. Select Prometheus exporters needed (e.g., `postgres_exporter` for Postgres, `redis_exporter` for Redis)
3. Determine if app exposes `/metrics` natively (FastAPI + prometheus-fastapi-instrumentator pattern)
4. Select Alloy source components needed (`loki.source.file`, `loki.source.docker`, `prometheus.scrape`)
5. Determine which metrics labels to add (`client`, `env`, `service`)
6. Flag any code changes needed (e.g., "add prometheus-fastapi-instrumentator to requirements.txt")

**Output:** `instrumentation-plan.md`
- Table of exporters to add with their Docker images and config
- Alloy component list with configuration notes
- Required environment variables for client `.env`
- Any code-level instrumentation needed (flagged as optional or required)
- Loki label strategy for this project's log streams

**Handoff:** Passes to `sauron-config-writer` AND `client-onboarding-agent` (parallel).

---

### Agent 3: `sauron-config-writer`

**Role:** Write all Sauron-side configuration for the new client.

**Inputs:** `fingerprint.json`, `instrumentation-plan.md`

**Process:**
1. Clone/checkout the `project-sauron` repo (or operate on a local copy)
2. Write a new Prometheus scrape job section for this client (if app exposes `/metrics`)
3. Write `monitoring/prometheus/rules/<client-name>.yml` with stack-appropriate alert rules
4. Update `monitoring/prometheus/prometheus.yml` to include the new rules file
5. Ensure the Loki datasource covers the new `{client="<name>"}` label (no config change needed — labels are on push)
6. Stage changes but **do not commit** — validation-agent commits after passing

**Output:** Modified files in the sauron repo:
- `monitoring/prometheus/prometheus.yml` (updated)
- `monitoring/prometheus/rules/<client-name>.yml` (new)

**Handoff:** Passes to `dashboard-generator`.

---

### Agent 4: `dashboard-generator`

**Role:** Generate a Grafana dashboard JSON tailored to the detected stack.

**Inputs:** `fingerprint.json`, `instrumentation-plan.md`

**Process:**
1. Start from the appropriate base template (web-app, API, worker, database-heavy)
2. Customize panels for detected stack: FastAPI → HTTP request rate/latency/errors; Postgres → query time, connections, cache hit ratio; etc.
3. Add standard panels present on all client dashboards: log stream panel (Loki), host CPU/mem/disk
4. Set Grafana variables: `$client` filter, `$interval`
5. Output valid Grafana dashboard JSON (schema version compatible with Grafana latest)

**Output:** `monitoring/grafana/dashboards/<client-name>.json`

**Handoff:** Passes to `validation-agent`.

---

### Agent 5: `client-onboarding-agent`

**Role:** Generate all client-side files needed to wire the project into Sauron.

**Inputs:** `instrumentation-plan.md`, `fingerprint.json`

**Process:**
1. Generate `config.alloy` with the components identified by instrumentation-engineer
2. Generate `docker-compose.monitoring.yml` as a Compose override (adds `alloy` service + any exporters)
3. Generate `.env.monitoring` with required variables and placeholder values
4. Generate a `ONBOARDING.md` checklist: steps the project owner takes to activate monitoring

**Output:**
- `config.alloy` (complete Alloy config for this project)
- `docker-compose.monitoring.yml` (Compose override)
- `.env.monitoring.example` (new env vars needed)
- `ONBOARDING.md` (human-readable activation steps)

**Handoff:** Passes output paths to `validation-agent`.

---

### Agent 6: `validation-agent`

**Role:** Syntactically and semantically validate all generated configurations.

**Inputs:** All files from sauron-config-writer, dashboard-generator, client-onboarding-agent

**Process:**
1. Run `docker compose -f docker-compose.monitoring.yml config` → validates YAML + interpolation
2. Run `promtool check config prometheus.yml` (Docker) → validates Prometheus config
3. Run `promtool check rules <client-name>.yml` → validates alert rule PromQL
4. Run `alloy fmt config.alloy` → validates Alloy config syntax
5. Validate Grafana dashboard JSON against known schema (panel types, datasource refs)
6. Check for placeholder values left unreplaced (e.g., `<CLIENT_NAME>`, `example.com`)
7. Verify the dashboard references only existing Prometheus/Loki label names

**Output:** `validation-report.md`
```markdown
## Validation Report: my-api

| Check | Status | Notes |
|-------|--------|-------|
| docker-compose.monitoring.yml syntax | PASS | |
| prometheus.yml syntax | PASS | |
| alert rules PromQL | PASS | |
| alloy config syntax | PASS | |
| dashboard JSON schema | PASS | |
| No placeholders remaining | WARN | .env.monitoring.example has 2 unfilled values |
```

If all required checks pass: commits staged changes to sauron repo, hands off to docs-agent.
If any required check fails: returns structured error list to the calling scrum-master for human review.

**Handoff:** Passes `validation-report.md` and commit SHA to `docs-agent`.

---

### Agent 7: `docs-agent`

**Role:** Generate human-readable onboarding documentation and update project records.

**Inputs:** `fingerprint.json`, `instrumentation-plan.md`, `validation-report.md`, `ONBOARDING.md`

**Process:**
1. Generate a `docs/clients/<client-name>.md` page for the Sauron GitHub Pages site
2. Append a row to the "Monitored Projects" table in Sauron's `docs/index.md`
3. Update Sauron's `CLAUDE.md` "Active Work" section to record the onboarded client
4. Submit a Voltron reflection: `submit_reflection` with what was onboarded, what agents ran, any issues encountered

**Output:**
- `docs/clients/<client-name>.md` (new page in Sauron docs)
- Updated `docs/index.md`
- Updated `CLAUDE.md` in sauron repo
- Voltron reflection submitted

**Handoff:** Pipeline complete. Returns summary to scrum-master.

---

## Phase 0: Manual Prerequisites

**Goal:** Establish the infrastructure, credentials, and DNS foundation that automated agents cannot create.

**Deliverables:**

1. **Terraform: Route53 hosted zone for `7ports.ca`** — `aws_route53_zone.root` resource added to `infrastructure/terraform/main.tf` (Phase 1 devops-engineer task, but listed here as a prerequisite step because the NS records must be updated at the registrar before Phase 5 DNS works)

2. **EC2 instance provisioned** via `terraform apply` (using existing `infrastructure/terraform/`)
   - Elastic IP assigned and noted as `EC2_PUBLIC_IP`

3. **Route53 zone setup (manual sequence):**
   a. Run `terraform apply` — this creates the `7ports.ca` hosted zone and outputs 4 NS records
   b. **Identify WordPress Lightsail static IP:** Go to AWS Console → Lightsail → Static IPs, note the IP attached to the WordPress instance
   c. **Migrate DNS records to Route53 (before nameserver update):**
      - Add A record: `7ports.ca` → Lightsail static IP (preserves WordPress apex)
      - Add A record: `www.7ports.ca` → Lightsail static IP (or CNAME if WordPress uses `www.`)
      - Add any other records from the current registrar (MX, TXT, etc.) to Route53
   d. **Update nameservers at registrar:** Point `7ports.ca` to the 4 Route53 NS records from `terraform output`
   e. Allow 24–48h for propagation; verify WordPress still loads at `7ports.ca` before proceeding

4. **GitHub Actions secrets added** to `7ports/project-sauron` repo:
   - `EC2_HOST` — EC2 public DNS or IP
   - `EC2_USER` — `ec2-user`
   - `EC2_SSH_KEY` — private key matching the `ec2_public_key` tfvar
   - `EC2_PUBLIC_IP` — Elastic IP
   - `GRAFANA_ADMIN_PASSWORD`
   - `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_REGION`

5. **Per-client bearer tokens:** Generate one unique token per client project using `openssl rand -base64 32`. Store in EC2 `.env` as `PUSH_BEARER_TOKEN_<CLIENT_NAME>` and in GitHub secrets for CI use. Initial token for sauron self-monitoring: `PUSH_BEARER_TOKEN_SAURON`.

**Agent Assignments:** None — all manual steps by Rajesh.

**Dependencies:** None — first phase.

**Definition of Done:**
- `terraform output elastic_ip` returns a stable IP
- `terraform output route53_ns_records` returns 4 NS records
- SSH to EC2 as `ec2-user` succeeds
- GitHub Actions secrets are set in the `7ports/project-sauron` repo
- WordPress loads at `https://7ports.ca` after nameserver migration (verify before Phase 5)
- `dig NS 7ports.ca` returns Route53 nameservers

---

## Phase 1: project-sauron Core Stack Upgrade

**Goal:** Add Loki, nginx/TLS, and Prometheus remote_write receiver to the existing Docker Compose stack; the hub is ready to receive telemetry from remote clients.

**Deliverables:**

1. **`monitoring/docker-compose.yml`** — add services:
   - `loki` (grafana/loki:latest, monolithic mode, `mem_limit: 400m`, filesystem storage, port 3100 internal only)
   - `nginx` (nginx:alpine, ports 80 and 443 exposed, replaces direct :3000 Grafana exposure)
   - `certbot` (certbot/certbot, shares `certbot_certs` volume with nginx for auto-renewal)
   - `pushgateway` (prom/pushgateway:latest, port 9091 internal only)
   - Remove direct `3000:3000` port mapping from `grafana` service (nginx proxies it)

2. **`monitoring/loki/loki.yml`** — Loki monolithic config:
   - `target: all`
   - `auth_enabled: false`
   - Filesystem storage under `/loki`
   - Retention: 7 days (`retention_period: 168h`)
   - `limits_config.ingestion_rate_mb: 4` (conservative for t3.small)

3. **`monitoring/nginx/nginx.conf`** — nginx config:
   - `:80` → redirect to HTTPS
   - `:443` with Let's Encrypt certs from `certbot_certs` volume
   - `/` → proxy to `grafana:3000` (no auth — Grafana has its own login)
   - `/metrics/push` → validate Bearer token header, proxy to `prometheus:9090/api/v1/write`
   - `/loki/api/v1/push` → validate Bearer token header, proxy to `loki:3100/loki/api/v1/push`

4. **`monitoring/nginx/scripts/certbot-renew.sh`** — renewal cron script (runs `certbot renew` + `nginx -s reload`)

5. **`monitoring/prometheus/prometheus.yml`** — add `--web.enable-remote-write-receiver` to Prometheus command args in compose; add scrape jobs for `pushgateway` and `loki` self-metrics

6. **`monitoring/grafana/provisioning/datasources/loki.yml`** — new Loki datasource pointing to `http://loki:3100`

7. **`monitoring/grafana/provisioning/grafana.ini`** (or env vars) — update `GF_SERVER_ROOT_URL` to `https://sauron.7ports.ca` (can stay as env var for now, updated in Phase 5)

8. **`infrastructure/terraform/main.tf`** — add:
   - Security group ingress rules for `:80` and `:443`
   - `aws_route53_zone.root` resource for `7ports.ca` (creates the zone; NS records output via `outputs.tf`)
   - `aws_route53_record.sauron` for `sauron.7ports.ca` → Elastic IP (with `enable_dns` toggle variable, defaults to `false` until Phase 5)
   - `aws_route53_record.wordpress_apex` for `7ports.ca` → Lightsail static IP
   - `aws_route53_record.wordpress_www` for `www.7ports.ca` → Lightsail static IP
   - `outputs.tf`: add `route53_ns_records` output (the 4 NS records to set at the registrar)

9. **`.env.example`** — add:
   - `PUSH_BEARER_TOKEN_<CLIENT_NAME>` (one per client — pattern, not a literal variable)
   - `LOKI_RETENTION_HOURS=168`
   - `DOMAIN=your.domain.com`
   - `CERTBOT_EMAIL=your@email.com`

10. **`monitoring/nginx/nginx.conf`** — use `$DOMAIN` env variable in `server_name` directive (nginx will substitute from Docker env)

**Agent Assignments:** `devops-engineer`

**Certbot email:** `raj@7ports.ca` — pass as `CERTBOT_EMAIL` env var in `.env`; certbot command in certbot service: `certbot certonly --webroot -w /var/www/certbot -d ${DOMAIN} --email ${CERTBOT_EMAIL} --agree-tos --non-interactive`

**Dependencies:** Phase 0 complete (EC2 running, secrets set).

**Definition of Done:**
- `docker compose config` exits 0 with no errors
- `docker compose up -d` starts all 9 services without errors
- `curl -k https://localhost/` returns Grafana login page
- `curl -k -H "Authorization: Bearer $PUSH_BEARER_TOKEN" -X POST https://localhost/loki/api/v1/push -H "Content-Type: application/json" -d '{"streams":[{"stream":{"test":"true"},"values":[["'$(date +%s%N)'","hello loki"]]}]}'` returns HTTP 204
- Prometheus `/targets` shows `loki` and `pushgateway` targets UP
- Grafana datasource "Loki" shows as Connected

---

## Phase 2: project-helldiver Repository Scaffold

**Goal:** Create the `7ports/project-helldiver` GitHub repo with complete Voltron-inherited scaffolding and stub agent definitions ready for Phase 4 implementation.

**Deliverables:**

1. **GitHub repo** `7ports/project-helldiver` created (public)

2. **`Dockerfile.voltron`** — identical to `project-sauron/Dockerfile.voltron`

3. **`scripts/voltron-run.sh`** — identical to `project-sauron/scripts/voltron-run.sh`

4. **`.claude/settings.json`** — auto-update hook, `project_name: "project-helldiver"`

5. **`.claude/agents/`** — 7 stub agent `.md` files (name, role, placeholder instructions):
   - `recon-agent.md`
   - `instrumentation-engineer.md`
   - `sauron-config-writer.md`
   - `dashboard-generator.md`
   - `client-onboarding-agent.md`
   - `validation-agent.md`
   - `docs-agent.md`
   - `scrum-master.md` (same as project-sauron's scrum-master)

6. **`CLAUDE.md`** — Helldiver project context: purpose, agent team table, Sauron connection details, Voltron inheritance model, session closeout protocol

7. **`.env.example`** — required variables: `SAURON_URL`, `SAURON_PUSH_TOKEN`, `GITHUB_TOKEN`, `TARGET_REPO`

8. **`docs/`** — Jekyll GitHub Pages stub: `_config.yml`, `index.md`, `agents.md`, `onboarding-guide.md`

9. **`.github/workflows/docs.yml`** — identical to sauron's docs workflow, pointing at `7ports/project-helldiver`

10. **`README.md`** — project overview, quick-start, link to GitHub Pages

**Agent Assignments:** `devops-engineer`

**Dependencies:** Phase 0 (GitHub access, secrets). Phase 1 not required — parallel.

**Definition of Done:**
- `https://github.com/7ports/project-helldiver` is publicly accessible
- GitHub Pages site deploys successfully at `https://7ports.github.io/project-helldiver`
- All 7 agent stub files exist under `.claude/agents/`
- `scripts/voltron-run.sh` runs without error against the repo root

---

## Phase 3: project-sauron Hub Readiness (Self-Onboarding Demo)

**Goal:** Validate the hub end-to-end by onboarding Sauron itself as its first client — Sauron monitors Sauron. This produces the canonical example Alloy config that Helldiver will use as a template.

**Deliverables:**

1. **`monitoring/alloy/config.alloy`** — canonical client Alloy config:
   - `prometheus.exporter.unix` → host metrics collection
   - `prometheus.scrape` → scrapes all local exporters
   - `prometheus.remote_write` → pushes to `${SAURON_URL}/metrics/push` with Bearer token
   - `loki.source.file` targeting `/var/log/*.log` and Docker container logs
   - `loki.write` → pushes to `${SAURON_URL}/loki/api/v1/push` with Bearer token
   - `client` and `env` labels applied to all metrics and logs

2. **`monitoring/docker-compose.monitoring.yml`** — canonical Compose override adding the `alloy` service (this file IS the self-monitoring addition AND the template for client projects)

3. **`monitoring/prometheus/rules/sauron-self.yml`** — alert rules for Sauron's own health

4. **`monitoring/grafana/dashboards/sauron-self.json`** — dashboard showing Sauron's own metrics AND logs side-by-side

5. **Docs:** `docs/clients/sauron.md` — first entry in the monitored clients section

**Agent Assignments:** `devops-engineer` (writes configs), verified by manual smoke test.

**Dependencies:** Phase 1 complete (Loki and nginx running).

**Definition of Done:**
- Alloy container starts without errors: `docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up alloy`
- Prometheus `/targets` shows `alloy`-pushed metrics arriving with `client="sauron"` label
- Grafana Explore → Loki: `{client="sauron"}` returns recent log lines
- `sauron-self.json` dashboard loads with data in all panels
- No OOM events on the EC2 instance (check `docker stats`)

---

## Phase 4: project-helldiver Agent Implementation

**Goal:** Implement all 7 Helldiver agents with complete, production-quality instructions, then run a live test onboarding against a second real project.

**Deliverables:**

1. **Full agent instructions** for all 7 `.claude/agents/*.md` files in `project-helldiver`:
   - Each agent file contains: role description, mandatory first steps (Alexandria), input/output contract, step-by-step process, handoff instructions, definition of done, error handling
   - Agents reference the canonical Alloy config from Phase 3 as their template source

2. **Test onboarding runs** — Helldiver's scrum-master coordinates agents to onboard two real projects:
   - **Test 1:** `7ports/project-hammer` — Cloudflare Workers + S3/CloudFront static site (ferries.yyz.live). Tests serverless/static path: Blackbox probing + Pushgateway pattern.
   - **Test 2:** `7ports/project-alexandria` — Node.js MCP server (stdio transport, no HTTP). Tests the "no scrape endpoint" path: GitHub Pages HTTP probing only + Alloy for host metrics if deployed on EC2.
   - Both tests must complete autonomously end-to-end before Phase 4 is marked done.

3. **Generated artifacts committed** to `project-sauron`:
   - `monitoring/prometheus/rules/<test-client>.yml`
   - `monitoring/grafana/dashboards/<test-client>.json`
   - Updated `monitoring/prometheus/prometheus.yml`

4. **Client-side artifacts** delivered to the test project repo:
   - `config.alloy`, `docker-compose.monitoring.yml`, `.env.monitoring.example`, `ONBOARDING.md`

5. **Helldiver CLAUDE.md** updated with lessons learned from test run

**Agent Assignments:** 
- `scrum-master` (Helldiver) → decomposes and delegates
- `recon-agent` → fingerprints test project
- `instrumentation-engineer` → selects exporters
- `sauron-config-writer` + `client-onboarding-agent` → generate configs in parallel
- `dashboard-generator` → generates dashboard
- `validation-agent` → validates everything
- `docs-agent` → generates docs + submits reflection

**Dependencies:** Phase 2 complete (Helldiver repo), Phase 3 complete (canonical Alloy template exists).

**Definition of Done:**
- All 7 agent instructions are complete (not stubs)
- Test onboarding completes without human intervention (fully autonomous)
- `validation-agent` report shows all checks PASS
- Test project's metrics appear in Grafana with correct `client` label
- Test project's logs appear in Loki Explore with correct stream selector
- Helldiver reflection submitted to Voltron pipeline

---

## Phase 5: Custom Domain and Docs

**Goal:** Sauron is accessible at `https://sauron.7ports.ca` with a valid Let's Encrypt certificate, and both projects have polished GitHub Pages documentation.

**Deliverables:**

1. **Route53 A record activation** via `infrastructure/terraform/main.tf`:
   - Set `enable_dns = true` in `terraform.tfvars` to activate `aws_route53_record.sauron` (the record was defined in Phase 1 but toggled off)
   - At this point `7ports.ca` nameservers must already point to Route53 (confirmed in Phase 0 step 3d)
   - Run `terraform apply` — `sauron.7ports.ca` A record goes live immediately
   - Confirm with `dig A sauron.7ports.ca` returning EC2 Elastic IP

2. **nginx config updated** for `sauron.7ports.ca`:
   - `server_name sauron.7ports.ca`
   - Certbot obtains cert for `sauron.7ports.ca` on first `docker compose up`
   - Auto-renewal script validated

3. **Grafana env vars updated** (use `$DOMAIN` from `.env` — not hardcoded):
   - `GF_SERVER_ROOT_URL=https://${DOMAIN}`
   - `GF_SERVER_DOMAIN=${DOMAIN}`

4. **`docs/` refresh for project-sauron**:
   - `architecture.md` updated with Phase 1–3 additions (Loki, nginx, Alloy, Pushgateway)
   - `setup.md` updated with end-to-end setup steps including Terraform + certbot
   - `dashboards.md` updated with Loki/log panels
   - `clients/` directory with one page per onboarded project

5. **`docs/` completion for project-helldiver**:
   - `agents.md` — full description of all 7 agents with data flow diagram
   - `onboarding-guide.md` — how to run Helldiver against a new project

**Agent Assignments:** `devops-engineer` (Terraform + nginx), `docs-agent` (documentation refresh)

**Dependencies:** Phase 1 (nginx/TLS stack running), Phase 4 (Helldiver agents complete).

**Definition of Done:**
- `curl https://sauron.7ports.ca` returns Grafana login page (200 OK, valid TLS cert)
- `curl http://sauron.7ports.ca` returns 301 redirect to HTTPS
- `terraform plan` shows no pending changes for DNS
- Let's Encrypt cert valid for `sauron.7ports.ca`, expiry >60 days out
- GitHub Pages for both projects build without errors

---

## Open Questions

All open questions resolved (2026-04-06).

| # | Question | Resolution |
|---|---|---|
| 1 | **Loki vs VictoriaLogs memory risk** | ✅ **Proceed with Loki** (`mem_limit: 400m`). Monitor `docker stats` after Phase 1 deployment; swap to VictoriaLogs only if headroom < 500MB. |
| 2 | **Tailscale vs HTTPS+token** | ✅ **HTTPS+Bearer token** — simpler, no VPN dependency. |
| 3 | **Push token strategy** | ✅ **One token per client** — more secure; Helldiver generates tokens during onboarding. Revoke individual clients without affecting others. |
| 4 | **Log retention** | ✅ **7 days default** (`LOKI_RETENTION_HOURS=168`). Helldiver documents retention per client in onboarding runbook. |
| 5 | **Phase 4 test projects** | ✅ **project-hammer** (Cloudflare Workers + CloudFront) and **project-alexandria** (Node.js MCP server). Both must complete autonomously. |
| 6 | **Alertmanager** | ✅ **Use Grafana Alerting** (built-in). Add Alertmanager only if PagerDuty/OpsGenie routing needed. |
| 7 | **Let's Encrypt email** | ✅ **`raj@7ports.ca`** — stored as `CERTBOT_EMAIL` in `.env`. |
| 8 | **Route53 / `7ports.ca` DNS** | ✅ **Create new Route53 hosted zone via Terraform** (`7ports.ca` has no existing zone). Migrate WordPress on Lightsail apex/www records to new zone before nameserver update at registrar. Nameserver migration is a Phase 0 manual step. |
| 9 | **WordPress on Lightsail** | ✅ **Preserve WordPress** — add `7ports.ca` (apex) and `www.7ports.ca` A records pointing to Lightsail static IP into the new Route53 zone. Validate WordPress loads before proceeding to Phase 5. |

---

## Summary of Changes by File

### project-sauron — New Files

| File | Phase | Description |
|---|---|---|
| `monitoring/loki/loki.yml` | 1 | Loki monolithic config |
| `monitoring/nginx/nginx.conf` | 1 | nginx reverse proxy + TLS + Bearer token auth |
| `monitoring/nginx/scripts/certbot-renew.sh` | 1 | Let's Encrypt renewal helper |
| `monitoring/alloy/config.alloy` | 3 | Canonical client Alloy config (template) |
| `monitoring/docker-compose.monitoring.yml` | 3 | Compose override adding Alloy (client template + self-monitoring) |
| `monitoring/prometheus/rules/sauron-self.yml` | 3 | Sauron self-monitoring alert rules |
| `monitoring/grafana/dashboards/sauron-self.json` | 3 | Sauron self-monitoring dashboard |
| `docs/clients/sauron.md` | 3 | First monitored client page |
| `docs/clients/<test-client>.md` | 4 | Helldiver-generated client page |

### project-sauron — Modified Files

| File | Phase | Change |
|---|---|---|
| `monitoring/docker-compose.yml` | 1 | Add loki, nginx, certbot, pushgateway services; update grafana port mapping |
| `monitoring/prometheus/prometheus.yml` | 1, 3 | Add `--web.enable-remote-write-receiver`; add pushgateway and loki scrape jobs; add client rules includes |
| `monitoring/grafana/provisioning/datasources/prometheus.yml` | 1 | No change expected |
| `monitoring/grafana/provisioning/datasources/loki.yml` | 1 | New file: add Loki datasource |
| `infrastructure/terraform/main.tf` | 1, 5 | Add :80/:443 security group ingress; add Route53 A record |
| `infrastructure/terraform/variables.tf` | 5 | Add `enable_dns` toggle variable |
| `.env.example` | 1 | Add PUSH_BEARER_TOKEN_<CLIENT_NAME> pattern, DOMAIN, LOKI_RETENTION_HOURS, CERTBOT_EMAIL |
| `CLAUDE.md` | 1, 3, 4 | Update Active Work, Known Issues, add monitored clients |
| `docs/architecture.md` | 5 | Update diagrams for full Phase 1-3 stack |
| `docs/setup.md` | 5 | End-to-end setup instructions |
| `docs/dashboards.md` | 5 | Document Loki log panels |

### project-helldiver — All New (Phase 2)

| File | Description |
|---|---|
| `Dockerfile.voltron` | Voltron agent runtime (inherited) |
| `scripts/voltron-run.sh` | Voltron Docker launcher (inherited) |
| `.claude/settings.json` | Auto-update hook |
| `.claude/agents/recon-agent.md` | Phase 2: stub → Phase 4: full instructions |
| `.claude/agents/instrumentation-engineer.md` | Phase 2: stub → Phase 4: full instructions |
| `.claude/agents/sauron-config-writer.md` | Phase 2: stub → Phase 4: full instructions |
| `.claude/agents/dashboard-generator.md` | Phase 2: stub → Phase 4: full instructions |
| `.claude/agents/client-onboarding-agent.md` | Phase 2: stub → Phase 4: full instructions |
| `.claude/agents/validation-agent.md` | Phase 2: stub → Phase 4: full instructions |
| `.claude/agents/docs-agent.md` | Phase 2: stub → Phase 4: full instructions |
| `.claude/agents/scrum-master.md` | Helldiver scrum-master (same role, Helldiver context) |
| `CLAUDE.md` | Helldiver project context |
| `.env.example` | SAURON_URL, SAURON_PUSH_TOKEN (client-specific token generated by Helldiver), GITHUB_TOKEN, TARGET_REPO |
| `docs/_config.yml` | Jekyll config |
| `docs/index.md` | Homepage |
| `docs/agents.md` | Agent team documentation |
| `docs/onboarding-guide.md` | How to run Helldiver |
| `.github/workflows/docs.yml` | GitHub Pages deploy |
| `README.md` | Project overview |

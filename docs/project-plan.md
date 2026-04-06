# Project Plan: Project Sauron — Phase 2 Expansion

> **Generated:** 2026-04-06
> **Status:** Ready for scrum-master decomposition

---

## Overview

Project Sauron is a self-hosted observability platform running Grafana + Prometheus on a single AWS EC2 `t3.small` instance via Docker Compose. The Phase 1 scaffold (EC2, VPC, Terraform, Docker Compose stack, three generic dashboards, GitHub Actions CI/CD) is complete. Phase 2 expands coverage to four real projects, adds a custom domain with HTTPS, builds per-project dashboards, and delivers a complete alerting suite.

---

## Architecture Decisions

| Decision | Choice | Rationale | Alternatives Considered |
|---|---|---|---|
| Custom domain HTTPS | nginx reverse proxy + Let's Encrypt (Certbot) in Docker | Free, no ALB cost (~$16/mo), standard for single-instance setups, auto-renews certs | HTTP-only (insecure, rejected); AWS ACM + ALB (overkill + cost); Cloudflare proxy (adds external dependency) |
| Grafana port exposure | nginx on 80/443, Grafana on internal 3000 only | Best practice: don't expose app port directly, terminate TLS at proxy | Direct port 443 on Grafana (Grafana supports TLS natively but cert management is harder) |
| Route53 DNS | Terraform `aws_route53_record` A record | Existing hosted zone `7ports.ca` in same AWS account; IaC consistency | Manual console entry (not repeatable) |
| MCP server monitoring (alexandria, voltron) | Blackbox HTTP probe of GitHub Pages only | Both servers run as local stdio processes — no deployed HTTP endpoint exists to probe | Custom heartbeat/push mechanism (too invasive, not warranted for personal projects) |
| project-voltron Cloudflare Worker monitoring | Blackbox HTTP probe of Worker URL | Worker is a public HTTPS endpoint; simple GET probe confirms availability | None |
| project-hammer monitoring | Blackbox HTTP for frontend (ferries.yyz.live) + API health endpoint (Fly.io /api/health) | Frontend is S3+CloudFront; backend has explicit `/api/health` on Fly.io | CloudWatch for S3/CloudFront (possible enhancement, not required for MVP) |
| Alertmanager | Deferred to future phase | No notification channel defined yet; rules exist, routing is not configured | PagerDuty, email SMTP, Slack webhooks |

---

## Target Architecture

```
                         ┌──────────────────────────────────────┐
                         │         EC2 t3.small (us-east-1)     │
                         │  ┌──────────────────────────────────┐ │
Internet ──:80/:443 ────►│  │  nginx (reverse proxy + TLS)     │ │
(sauron.7ports.ca)       │  └─────────────┬────────────────────┘ │
                         │                │ :3000 (internal)      │
                         │  ┌─────────────▼────────────────────┐ │
                         │  │  Grafana :3000                   │ │
                         │  └─────────────┬────────────────────┘ │
                         │                │ queries               │
                         │  ┌─────────────▼────────────────────┐ │
                         │  │  Prometheus :9090 (127.0.0.1)    │ │
                         │  │  ┌──────────────────────────────┐│ │
                         │  │  │  scrape targets:             ││ │
                         │  │  │  - node-exporter :9100       ││ │
                         │  │  │  - blackbox-exporter :9115   ││ │
                         │  │  │  - cloudwatch-exporter :9106 ││ │
                         │  │  └──────────────────────────────┘│ │
                         │  └──────────────────────────────────┘ │
                         └──────────────────────────────────────┘

Blackbox Exporter probes (outbound from EC2):
  ┌─ https://7ports.github.io/project-alexandria/
  ├─ https://7ports.github.io/project-voltron/
  ├─ https://voltron-chat.<account>.workers.dev  (Cloudflare Worker)
  ├─ https://ferries.yyz.live                    (project-hammer frontend)
  └─ https://project-hammer-api.fly.dev/api/health (project-hammer backend)

Route53 (7ports.ca hosted zone):
  sauron.7ports.ca  A  →  EC2 Elastic IP
```

---

## Prometheus Scrape Job Design

All new targets use the existing `blackbox_http` mechanism with per-project labels for dashboard filtering.

```yaml
# Proposed new scrape jobs (additions to existing prometheus.yml)
- job_name: 'blackbox_project_docs'
  # GitHub Pages docs sites (project-alexandria, project-voltron)

- job_name: 'blackbox_project_hammer'
  # ferries.yyz.live frontend + /api/health backend

- job_name: 'blackbox_project_voltron_worker'
  # Cloudflare Worker health probe

- job_name: 'blackbox_tls_project_hammer'
  # SSL cert expiry for ferries.yyz.live
```

Each target gets a `project` label via `relabel_configs` to enable per-project dashboard filtering.

---

## Grafana Dashboard Design Standards

Each project dashboard must include:

| Section | Panels |
|---|---|
| **Header row** | Stat: current uptime %, last check time, response time |
| **Availability** | Time series: `probe_success` over time; Stat: 24h/7d uptime % |
| **Performance** | Time series: `probe_duration_seconds`; threshold lines at 1s/2s |
| **SSL / TLS** | Stat: days until cert expiry; alert threshold at 30 days |
| **Project info** | Text panel: description, links to GitHub + docs |

Dashboard JSON files go in `monitoring/grafana/dashboards/` and are provisioned automatically via the existing `dashboard.yml` provisioner config.

---

## Phase 0: Manual Prerequisites

> **Owner: Human (Rajesh) — no agent involvement**
> These steps must be completed before any agent work begins.

### Goal
All pre-conditions are confirmed and credentials are in place for automated work to proceed.

### Actions Required

**AWS / Terraform:**
- [ ] Run `terraform apply` in `infrastructure/terraform/` to confirm EC2 instance and Elastic IP are provisioned
- [ ] Note the Elastic IP output (`terraform output elastic_ip`) — needed for DNS and `.env`
- [ ] Confirm the Route53 hosted zone ID for `7ports.ca` in AWS Console (Hosted Zones → `7ports.ca` → copy Zone ID)
- [ ] Add `hosted_zone_id` to `terraform.tfvars` (will be needed in Phase 1)

**EC2 Setup:**
- [ ] SSH into the EC2 instance: `ssh ec2-user@<ELASTIC_IP>`
- [ ] Clone repo if not present: `git clone https://github.com/7ports/project-sauron.git /opt/project-sauron`
- [ ] Copy `.env.example` to `.env` and fill in all values:
  - `GRAFANA_ADMIN_PASSWORD` — choose a strong password
  - `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` — IAM user with CloudWatch read
  - `AWS_REGION=us-east-1`
  - `EC2_PUBLIC_IP` — the Elastic IP

**GitHub Actions Secrets** (Settings → Secrets → Actions):
- [ ] `EC2_HOST` — Elastic IP address
- [ ] `EC2_SSH_KEY` — contents of the EC2 private key (PEM file)
- [ ] `EC2_USER` — `ec2-user`
- [ ] `GRAFANA_ADMIN_PASSWORD` — same as `.env`

**project-voltron Cloudflare Worker:**
- [ ] Find the exact Worker URL: either check the Cloudflare dashboard or run `npx wrangler whoami` / `npx wrangler deployments list` from `docs/` in the project-voltron repo
- [ ] The URL pattern is `https://voltron-chat.<YOUR_CF_ACCOUNT>.workers.dev`
- [ ] Record this URL — it goes into `prometheus.yml` as a blackbox target in Phase 2

**project-hammer confirmation:**
- [ ] Confirm `https://ferries.yyz.live` is live (open in browser)
- [ ] Confirm backend health check responds: `curl https://project-hammer-api.fly.dev/api/health`
- [ ] Note the AIS data source URL used by the backend (check Fly.io env or repo config) — optional for monitoring

### Dependencies
None — this is the entry point.

### Definition of Done
- EC2 instance is running with Elastic IP assigned
- `.env` is filled in on the EC2 instance
- All GitHub Actions secrets are set
- Cloudflare Worker URL is known
- ferries.yyz.live and project-hammer-api.fly.dev/api/health both respond

---

## Phase 1: Infrastructure & DNS

> **Owner: devops-engineer agent**

### Goal
Serve Grafana at `https://sauron.7ports.ca` with a valid TLS certificate via nginx + Let's Encrypt, managed through Terraform for DNS.

### Architecture

```
Internet → sauron.7ports.ca:80   → nginx (redirect to HTTPS)
Internet → sauron.7ports.ca:443  → nginx (TLS termination) → Grafana :3000
```

Nginx runs as a Docker container in the existing `monitoring/docker-compose.yml`. Certbot runs as a companion container that renews certs via a cron-style renewal loop.

### Deliverables

**1. Terraform — Route53 A record (`infrastructure/terraform/main.tf`)**

New resource to add:
```hcl
variable "route53_zone_id" {
  description = "Route53 hosted zone ID for 7ports.ca"
  type        = string
}

resource "aws_route53_record" "sauron" {
  zone_id = var.route53_zone_id
  name    = "sauron.7ports.ca"
  type    = "A"
  ttl     = 300
  records = [aws_eip.sauron.public_ip]
}
```

Add `route53_zone_id` to `terraform.tfvars.example`.

Also add Security Group ingress rules for port 80 and 443:
```hcl
ingress {
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  description = "HTTP (nginx, redirects to HTTPS)"
}

ingress {
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  description = "HTTPS (nginx + Let's Encrypt)"
}
```

Change existing Grafana ingress rule to restrict to internal-only (remove `0.0.0.0/0` on port 3000, or keep as fallback).

**2. nginx config (`monitoring/nginx/nginx.conf`)**

```nginx
server {
    listen 80;
    server_name sauron.7ports.ca;
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name sauron.7ports.ca;
    ssl_certificate     /etc/letsencrypt/live/sauron.7ports.ca/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/sauron.7ports.ca/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass http://grafana:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**3. Docker Compose additions (`monitoring/docker-compose.yml`)**

Add nginx and certbot services:
```yaml
  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - ./certbot/conf:/etc/letsencrypt:ro
      - ./certbot/www:/var/www/certbot:ro
    depends_on:
      - grafana
    networks:
      - monitoring

  certbot:
    image: certbot/certbot
    container_name: certbot
    volumes:
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"
```

Update Grafana environment in docker-compose:
```yaml
- GF_SERVER_ROOT_URL=https://sauron.7ports.ca
- GF_SERVER_DOMAIN=sauron.7ports.ca
```

Change Grafana ports to internal-only:
```yaml
    ports:
      - "127.0.0.1:3000:3000"
```

**4. Initial cert issuance script (`scripts/init-letsencrypt.sh`)**

One-time script to bootstrap the first certificate before the stack starts (standard Certbot/nginx bootstrap procedure):
- Generates dummy certs to allow nginx to start
- Runs `certbot certonly --webroot` to get real cert
- Reloads nginx

**5. `.env.example` additions**
```
DOMAIN=sauron.7ports.ca
CERTBOT_EMAIL=your-email@example.com
```

### Agent Assignment
`devops-engineer`

### Dependencies
- Phase 0 complete: EC2 running, Elastic IP known, Route53 zone ID known
- `terraform apply` run after Terraform changes to create the A record

### Key Decisions Needed Before Starting
- Confirm email address for Let's Encrypt registration (for expiry notifications)
- Confirm the Route53 zone ID (from Phase 0)

### Definition of Done
- `terraform plan` shows `aws_route53_record.sauron` to be created
- `https://sauron.7ports.ca` loads Grafana with valid TLS certificate (no browser warning)
- HTTP redirects to HTTPS
- Certificate auto-renewal confirmed (`certbot renew --dry-run` succeeds)

---

## Phase 2: Project Integrations (Monitoring Targets)

> **Owner: devops-engineer agent**

### Goal
Add Prometheus scrape configs and blackbox probes for all three projects so that uptime, response time, and SSL cert data flows into Prometheus.

### Monitored Endpoints Per Project

| Project | Endpoint | Type | Notes |
|---|---|---|---|
| **alexandria** | https://7ports.github.io/project-alexandria/ | HTTP + SSL | GitHub Pages docs only — no server process |
| **voltron** (docs) | https://7ports.github.io/project-voltron/ | HTTP + SSL | GitHub Pages docs |
| **voltron** (worker) | https://voltron-chat.`<ACCOUNT>`.workers.dev | HTTP | Cloudflare Worker; URL confirmed in Phase 0 |
| **hammer** (frontend) | https://ferries.yyz.live | HTTP + SSL | S3 + CloudFront |
| **hammer** (backend) | https://project-hammer-api.fly.dev/api/health | HTTP | Fly.io health endpoint |

### Deliverables

**1. `monitoring/prometheus/prometheus.yml` — new scrape jobs**

```yaml
  # GitHub Pages docs monitoring (alexandria + voltron)
  - job_name: 'blackbox_docs'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - https://7ports.github.io/project-alexandria/
          - https://7ports.github.io/project-voltron/
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - source_labels: [__param_target]
        regex: 'https://7ports\.github\.io/(project-[^/]+)/.*'
        target_label: project
        replacement: '$1'
      - target_label: __address__
        replacement: blackbox-exporter:9115

  # Cloudflare Worker (project-voltron chat backend)
  - job_name: 'blackbox_voltron_worker'
    metrics_path: /probe
    params:
      module: [http_2xx_no_body]  # Worker may return 200 on GET /
    static_configs:
      - targets:
          - https://voltron-chat.PLACEHOLDER.workers.dev  # Replace with real URL from Phase 0
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: project
        replacement: 'project-voltron'
      - target_label: __address__
        replacement: blackbox-exporter:9115

  # project-hammer: frontend + backend API health
  - job_name: 'blackbox_hammer'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - https://ferries.yyz.live
          - https://project-hammer-api.fly.dev/api/health
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: project
        replacement: 'project-hammer'
      - target_label: __address__
        replacement: blackbox-exporter:9115

  # SSL certificate expiry for all custom domains
  - job_name: 'blackbox_ssl'
    metrics_path: /probe
    params:
      module: [tls_check]
    static_configs:
      - targets:
          - sauron.7ports.ca:443
          - ferries.yyz.live:443
          - 7ports.github.io:443
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115
```

**2. `monitoring/exporters/blackbox.yml` — new module**

```yaml
  # For endpoints that may return non-2xx on GET / but are alive
  http_2xx_no_body:
    prober: http
    timeout: 10s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200, 204, 301, 302]
      method: GET
      follow_redirects: true
      preferred_ip_protocol: ip4

  # TLS-only check (for SSL cert expiry)
  tls_check:
    prober: tcp
    timeout: 10s
    tcp:
      tls: true
      tls_config:
        insecure_skip_verify: false
```

**3. `.env.example` — add Cloudflare Worker URL placeholder**
```
VOLTRON_WORKER_URL=https://voltron-chat.PLACEHOLDER.workers.dev
```

### Agent Assignment
`devops-engineer`

### Dependencies
- Phase 0: Cloudflare Worker URL confirmed
- Phase 1: Stack is deployed (Prometheus reachable to validate configs)

### Key Decisions Needed
- Cloudflare Worker URL (from Phase 0) — must replace `PLACEHOLDER` before deploying
- Whether to probe the Worker URL with a GET (may return 4xx if no route defined at `/`) — may need to adjust `valid_status_codes`

### Definition of Done
- `docker run --rm ... prom/prometheus --check-config` passes on updated `prometheus.yml`
- All 5 new targets appear at Prometheus `:9090/targets` with state `UP` (or `UNKNOWN` for Cloudflare Worker until URL is confirmed)
- `probe_success{job=~"blackbox_.*"}` shows `1` for all live endpoints

---

## Phase 3: Custom Grafana Dashboards

> **Owner: devops-engineer agent**

### Goal
Replace placeholder/generic dashboards with fully comprehensive, per-project dashboards and a master overview dashboard.

### Dashboards to Create

All files go in `monitoring/grafana/dashboards/` and use UIDs that won't conflict with existing dashboards.

---

#### Dashboard 1: `sauron-host.json` — Sauron EC2 Host

| Row | Panels |
|---|---|
| **Overview** | Stat: uptime, CPU %, memory %, disk % |
| **CPU** | Time series: CPU usage by mode (user, system, iowait); Gauge: current % |
| **Memory** | Time series: used/available/cached; Stat: total RAM |
| **Disk** | Time series: disk read/write bytes/s; Gauge: disk % used on `/` |
| **Network** | Time series: bytes in/out per interface |
| **Prometheus** | Stat: scrape targets UP vs DOWN; Time series: Prometheus memory usage |

---

#### Dashboard 2: `project-alexandria.json` — Project Alexandria

| Row | Panels |
|---|---|
| **Project Info** | Text: description ("Shared tooling knowledge base MCP server"), links to GitHub + docs |
| **GitHub Pages Health** | Stat: current probe_success; Time series: uptime over 7d |
| **Response Time** | Time series: probe_duration_seconds; Gauge: current latency |
| **SSL Certificate** | Stat: days until cert expiry (GitHub Pages cert); threshold: warning at 30d |

**Note on MCP server:** The MCP server runs as a local stdio process — no HTTP endpoint exists. This dashboard covers what is observable: the documentation site. A text panel explains this architecture.

---

#### Dashboard 3: `project-voltron.json` — Project Voltron

| Row | Panels |
|---|---|
| **Project Info** | Text: description ("AI agent templates MCP server + chat widget"), links to GitHub + docs |
| **GitHub Pages Health** | Stat + Time series: docs site uptime |
| **Cloudflare Worker Health** | Stat: worker availability; Time series: response time |
| **Response Times** | Time series: both endpoints side-by-side |
| **SSL** | Stat: cert expiry for github.io |

---

#### Dashboard 4: `project-hammer.json` — Project Hammer (Toronto Ferry Tracker)

| Row | Panels |
|---|---|
| **Project Info** | Text: description ("Real-time Toronto Island Ferry tracker"), links to GitHub + live site |
| **Frontend (ferries.yyz.live)** | Stat: uptime; Time series: probe_success + response time |
| **Backend API (Fly.io)** | Stat: /api/health availability; Time series: response time |
| **SSL** | Stat: cert expiry (ferries.yyz.live); threshold at 30d |
| **Availability Summary** | Stat: 24h uptime %, 7d uptime % for each endpoint |

---

#### Dashboard 5: `overview.json` — All Projects Overview (Home Dashboard)

A single-pane-of-glass view across all monitored endpoints.

| Row | Panels |
|---|---|
| **Host Health** | Stat row: CPU %, memory %, disk %, node-exporter up |
| **All Endpoints** | Table: instance, project, probe_success, response time, last check |
| **Uptime Summary** | Stat: 24h uptime per endpoint (colored: green ≥99%, yellow ≥95%, red <95%) |
| **SSL Expiry** | Table: domain, days remaining (colored: red <14d, yellow <30d, green ≥30d) |
| **Response Time Trends** | Time series: all endpoints overlaid |

Set this as the home dashboard in docker-compose:
```yaml
- GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/var/lib/grafana/dashboards/overview.json
```

### Grafana Dashboard JSON Standards

All dashboards must:
- Set `"schemaVersion": 39` (Grafana latest)
- Use `"refresh": "1m"` default auto-refresh
- Set meaningful `"uid"` values (e.g., `"sauron-host"`, `"project-hammer"`)
- Use `"__inputs"` and `"__requires"` for portability
- Prometheus datasource referenced as `"${DS_PROMETHEUS}"` via `"templating"` variable
- Include a `"project"` template variable where applicable for filtering

### Agent Assignment
`devops-engineer`

### Dependencies
- Phase 2 complete: all scrape targets are UP so data exists to build panels against
- Prometheus query patterns validated (metrics actually exist)

### Definition of Done
- All 5 dashboard JSON files present in `monitoring/grafana/dashboards/`
- Grafana loads all dashboards without errors after `docker compose up -d` (or config reload)
- Overview dashboard is set as home dashboard
- Each dashboard shows real data (not "No data") for at least the current time range

---

## Phase 4: Alerting Suite

> **Owner: devops-engineer agent**

### Goal
Deliver a complete set of Prometheus alerting rules covering host health, endpoint uptime, SSL expiry, and per-project availability, organized into per-concern rule files.

### Rule File Organization

```
monitoring/prometheus/rules/
├── host.yml          # EC2 host metrics (replaces/extends existing alerting.yml)
├── endpoints.yml     # All HTTP endpoint uptime + latency
├── ssl.yml           # SSL cert expiry for all domains
└── project-hammer.yml # project-hammer-specific thresholds
```

The existing `alerting.yml` is split into focused files. `recording.yml` remains unchanged.

---

### `host.yml` — EC2 Host Alerts

```yaml
groups:
  - name: host
    interval: 30s
    rules:
      - alert: HostDown
        expr: up{job="node"} == 0
        for: 1m
        labels: { severity: critical, team: infra }
        annotations:
          summary: "EC2 host unreachable"
          description: "node-exporter has not reported for > 1 minute"

      - alert: HostHighCPU
        expr: 100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
        for: 5m
        labels: { severity: warning, team: infra }
        annotations:
          summary: "High CPU on {{ $labels.instance }}"
          description: "CPU at {{ $value | printf \"%.1f\" }}% (threshold: 85%)"

      - alert: HostCriticalCPU
        expr: 100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 95
        for: 2m
        labels: { severity: critical, team: infra }
        annotations:
          summary: "Critical CPU on {{ $labels.instance }}"

      - alert: HostLowMemory
        expr: node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100 < 15
        for: 5m
        labels: { severity: warning, team: infra }
        annotations:
          summary: "Low memory on {{ $labels.instance }}"
          description: "Only {{ $value | printf \"%.1f\" }}% available"

      - alert: HostCriticalMemory
        expr: node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100 < 5
        for: 2m
        labels: { severity: critical, team: infra }
        annotations:
          summary: "Critical memory on {{ $labels.instance }}"

      - alert: HostDiskWarning
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 20
        for: 5m
        labels: { severity: warning, team: infra }
        annotations:
          summary: "Low disk space on {{ $labels.instance }}"
          description: "{{ $value | printf \"%.1f\" }}% remaining on /"

      - alert: HostDiskCritical
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 10
        for: 5m
        labels: { severity: critical, team: infra }
        annotations:
          summary: "Critical disk space on {{ $labels.instance }}"

      - alert: HostHighNetworkErrors
        expr: rate(node_network_receive_errs_total[5m]) + rate(node_network_transmit_errs_total[5m]) > 10
        for: 5m
        labels: { severity: warning, team: infra }
        annotations:
          summary: "Network errors on {{ $labels.instance }}"

      - alert: HostReboot
        expr: node_boot_time_seconds > (time() - 300)
        labels: { severity: info, team: infra }
        annotations:
          summary: "Host {{ $labels.instance }} recently rebooted"
```

---

### `endpoints.yml` — HTTP Endpoint Availability

```yaml
groups:
  - name: endpoints
    interval: 30s
    rules:
      - alert: EndpointDown
        expr: probe_success == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.instance }} is DOWN"
          description: "HTTP probe failing for > 2 minutes (job: {{ $labels.job }})"

      - alert: EndpointHighLatency
        expr: probe_duration_seconds > 3
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High latency: {{ $labels.instance }}"
          description: "Response time {{ $value | printf \"%.2f\" }}s (threshold: 3s)"

      - alert: EndpointSlowResponse
        expr: probe_duration_seconds > 1
        for: 10m
        labels:
          severity: info
        annotations:
          summary: "Slow response: {{ $labels.instance }}"
          description: "Response time {{ $value | printf \"%.2f\" }}s for > 10 minutes"

      - alert: PrometheusTargetDown
        expr: up == 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Prometheus target {{ $labels.job }}/{{ $labels.instance }} down"
```

---

### `ssl.yml` — SSL Certificate Expiry

```yaml
groups:
  - name: ssl
    interval: 1h
    rules:
      - alert: SSLCertExpiringCritical
        expr: probe_ssl_earliest_cert_expiry - time() < 86400 * 14
        for: 1h
        labels:
          severity: critical
        annotations:
          summary: "SSL cert expiring in < 14 days: {{ $labels.instance }}"
          description: "Certificate expires in {{ $value | humanizeDuration }}"

      - alert: SSLCertExpiringWarning
        expr: probe_ssl_earliest_cert_expiry - time() < 86400 * 30
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "SSL cert expiring in < 30 days: {{ $labels.instance }}"
          description: "Certificate expires in {{ $value | humanizeDuration }}"

      - alert: SSLCertExpired
        expr: probe_ssl_earliest_cert_expiry - time() <= 0
        labels:
          severity: critical
        annotations:
          summary: "SSL cert EXPIRED: {{ $labels.instance }}"
```

---

### `project-hammer.yml` — Project-Specific Alerts

```yaml
groups:
  - name: project-hammer
    interval: 60s
    rules:
      - alert: HammerFrontendDown
        expr: probe_success{instance="https://ferries.yyz.live"} == 0
        for: 2m
        labels:
          severity: critical
          project: project-hammer
        annotations:
          summary: "Toronto Ferry Tracker frontend is DOWN"
          description: "ferries.yyz.live has been unreachable for > 2 minutes"

      - alert: HammerAPIDown
        expr: probe_success{instance="https://project-hammer-api.fly.dev/api/health"} == 0
        for: 2m
        labels:
          severity: critical
          project: project-hammer
        annotations:
          summary: "project-hammer backend API is DOWN"
          description: "Fly.io health endpoint failing for > 2 minutes"

      - alert: HammerAPIHighLatency
        expr: probe_duration_seconds{instance="https://project-hammer-api.fly.dev/api/health"} > 2
        for: 5m
        labels:
          severity: warning
          project: project-hammer
        annotations:
          summary: "project-hammer API slow response"
          description: "API health check taking {{ $value | printf \"%.2f\" }}s"
```

### Agent Assignment
`devops-engineer`

### Dependencies
- Phase 2 complete: scrape jobs and labels exist for alert expressions to match against
- `recording.yml` reviewed to ensure recording rules don't conflict with new alert names

### Key Decisions Needed
- Alertmanager routing: no Alertmanager is configured yet. All rules will fire but not route to any notification channel. This is acceptable for now — Alertmanager setup (email/Slack) is a future phase.
- Confirm whether to delete/supersede the existing `alerting.yml` or keep it alongside the new files

### Definition of Done
- `docker run --rm ... prom/prometheus --check-config` passes with all 4 rule files
- Prometheus `:9090/rules` shows all rule groups as `active`
- Test alert fires correctly: temporarily set a low threshold, confirm it appears in `:9090/alerts`
- No duplicate rule names across files

---

## Open Questions

> These require human input before or during implementation.

| # | Question | Required By | Impact |
|---|---|---|---|
| 1 | **Cloudflare Worker URL** — What is the exact URL for `voltron-chat`? Pattern: `https://voltron-chat.<CF_ACCOUNT>.workers.dev` | Phase 2 | Without this, the voltron-worker scrape job cannot be deployed |
| 2 | **Let's Encrypt email** — What email address should be used for cert registration (receives expiry warnings from LE)? | Phase 1 | Required for `certbot certonly` command |
| 3 | **Route53 Zone ID** — What is the hosted zone ID for `7ports.ca`? | Phase 1 | Required in `terraform.tfvars` before `terraform apply` |
| 4 | **Cloudflare Worker probe behavior** — Does `GET /` on the voltron-chat worker return 200, or a non-2xx? | Phase 2 | Determines `valid_status_codes` in blackbox config |
| 5 | **Alertmanager future** — When should Alertmanager be configured with a notification channel (Slack, email)? | Future phase | Currently all alerts fire silently; routing is deferred |
| 6 | **project-hammer AIS data source** — Is monitoring the external AIS data source (aisstream.io?) desired? | Phase 2 | Could add an additional blackbox probe for the AIS stream endpoint |
| 7 | **Grafana port 3000 access** — After nginx+TLS is in place, should port 3000 be removed from the EC2 security group entirely (more secure), or kept as fallback? | Phase 1 | Security posture decision |

---

## Summary of Changes by File

| File | Action | Phase |
|---|---|---|
| `infrastructure/terraform/main.tf` | Add `aws_route53_record`, port 80/443 SG rules, `route53_zone_id` variable | 1 |
| `infrastructure/terraform/variables.tf` | Add `route53_zone_id` variable | 1 |
| `infrastructure/terraform/terraform.tfvars.example` | Add `route53_zone_id`, `certbot_email` examples | 1 |
| `monitoring/docker-compose.yml` | Add nginx + certbot services; update Grafana env + port binding | 1 |
| `monitoring/nginx/nginx.conf` | New file — nginx reverse proxy config | 1 |
| `scripts/init-letsencrypt.sh` | New file — one-time cert bootstrap script | 1 |
| `.env.example` | Add `DOMAIN`, `CERTBOT_EMAIL`, `VOLTRON_WORKER_URL` | 1+2 |
| `monitoring/prometheus/prometheus.yml` | Add 4 new scrape jobs with project labels | 2 |
| `monitoring/exporters/blackbox.yml` | Add `http_2xx_no_body` and `tls_check` modules | 2 |
| `monitoring/grafana/dashboards/sauron-host.json` | New dashboard — EC2 host metrics | 3 |
| `monitoring/grafana/dashboards/project-alexandria.json` | New dashboard — alexandria docs uptime | 3 |
| `monitoring/grafana/dashboards/project-voltron.json` | New dashboard — voltron docs + worker health | 3 |
| `monitoring/grafana/dashboards/project-hammer.json` | New dashboard — ferry tracker frontend + API | 3 |
| `monitoring/grafana/dashboards/overview.json` | New dashboard — all-projects home | 3 |
| `monitoring/prometheus/rules/host.yml` | New — comprehensive host alerts | 4 |
| `monitoring/prometheus/rules/endpoints.yml` | New — endpoint uptime + latency alerts | 4 |
| `monitoring/prometheus/rules/ssl.yml` | New — SSL cert expiry alerts | 4 |
| `monitoring/prometheus/rules/project-hammer.yml` | New — project-specific alerts | 4 |
| `monitoring/prometheus/rules/alerting.yml` | Replace with redirect/note pointing to new files | 4 |

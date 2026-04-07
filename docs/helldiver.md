---
layout: default
title: Helldiver — Onboarding Projects
nav_order: 5
---

# Deploying Helldiver Squadrons

> **Claude Code users:** This guide explains how to trigger Helldiver to onboard a new project into Sauron.
> Read the entire guide before starting. Identify the project type (HTTP API, MCP server, or static site),
> gather the required inputs, then invoke the squadron. All steps after invocation are autonomous —
> no human intervention required until the "What you need to do after" section.

---

## What Helldiver Does

Helldiver is an agentic pipeline that onboards a client project into Project Sauron. A single invocation:

1. **Recon** — clones the client repo, reads the codebase, identifies tech stack, endpoints, and deployment method
2. **Instrumentation** — adds metrics collection (Alloy config for HTTP projects; prom-client for MCP/Node.js projects)
3. **Config** — adds the client's endpoints to `monitoring/prometheus/prometheus.yml` and alert rules to `monitoring/prometheus/rules/<client>.yml`
4. **Dashboard** — generates a Grafana dashboard JSON in `monitoring/grafana/dashboards/<client>.json`
5. **Validation** — verifies the new Prometheus targets come UP; checks the dashboard loads without errors
6. **Docs** — creates `docs/clients/<client>.md` documenting what was onboarded and how to verify it

```
Helldiver invocation
        │
        ▼
  ┌─────────────┐    ┌──────────────┐    ┌───────────────┐
  │  Recon      │───►│  Instrument  │───►│  Config       │
  │  (read repo)│    │  (alloy/prom)│    │  (prometheus) │
  └─────────────┘    └──────────────┘    └───────┬───────┘
                                                  │
        ┌─────────────────────────────────────────┘
        ▼
  ┌─────────────┐    ┌──────────────┐    ┌───────────────┐
  │  Dashboard  │───►│  Validation  │───►│  Docs         │
  │  (grafana)  │    │  (targets UP)│    │  (clients/)   │
  └─────────────┘    └──────────────┘    └───────────────┘
```

---

## Prerequisites

- Running Sauron instance at `https://sauron.yourdomain.com` (see [setup.md](setup.md))
- Prometheus targets endpoint reachable at `http://localhost:9090` (via SSH tunnel or on-host)
- Target project is on GitHub (public, or private with a GitHub token available)
- You know:
  - `GITHUB_OWNER` — GitHub username or org (e.g. `7ports`)
  - `GITHUB_REPO` — repository name (e.g. `project-hammer`)
  - `CLIENT_LABEL` — short identifier, lowercase, hyphens only (e.g. `hammer`, `alexandria`)

### Client label rules

| Rule | Example |
|---|---|
| Lowercase only | `hammer` ✓, `Hammer` ✗ |
| Hyphens, no underscores | `my-api` ✓, `my_api` ✗ |
| Short — used in file names and Prometheus labels | `hammer` ✓, `project-hammer-ferry-tracker` ✗ |
| Must not conflict with existing labels | Check `docs/clients/` — each `.md` filename is a taken label |

---

## Standard Projects (HTTP APIs, Web Apps, Docker on EC2)

This covers any project with one or more HTTP endpoints and/or a Docker-based deployment.

**Examples:**
- React SPA on S3/CloudFront + Node.js API on Fly.io (Project Hammer)
- Express backend on EC2 + static frontend on Vercel
- Any service with a `/health` or `/api/health` endpoint

### Invoke the squadron

```
@scrum-master Onboard a new project into Sauron via Helldiver.

Project details:
  GITHUB_OWNER: <YOUR_GITHUB_OWNER>
  GITHUB_REPO: <YOUR_GITHUB_REPO>
  CLIENT_LABEL: <YOUR_CLIENT_LABEL>

Instructions:
  1. Clone the client repo and read the codebase to identify:
     - All HTTP endpoints worth monitoring (health check, main URL, API base)
     - Deployment method (Fly.io, EC2, Vercel, CloudFront, etc.)
     - Whether a Docker Compose setup exists (Alloy can run as sidecar)
  2. Add the client's endpoints to monitoring/prometheus/prometheus.yml (blackbox_http targets)
  3. Create monitoring/prometheus/rules/<CLIENT_LABEL>.yml with alert rules:
     - <ClientLabel>Down — probe_success == 0 for 2m — critical
     - <ClientLabel>HighLatency — probe_duration_seconds > 2 for 5m — warning
  4. Create monitoring/grafana/dashboards/<CLIENT_LABEL>.json — dashboard with:
     - Uptime stat panels (one per endpoint)
     - Response time time-series panel
     - HTTP status code stat panel
     - Dashboard UID: "<CLIENT_LABEL>-overview"
     - Tags: ["helldiver", "<CLIENT_LABEL>"]
  5. If the project runs Docker Compose on EC2: generate the Alloy client config
     (copy monitoring/docker-compose.monitoring.yml as a template)
  6. Create docs/clients/<CLIENT_LABEL>.md documenting what was onboarded
  7. Commit all changes to a branch, open a PR against 7ports/project-sauron
  8. Verify: SSH to EC2, curl -s -X POST http://localhost:9090/-/reload, confirm new targets UP
```

### What happens automatically

1. Scrum-master spawns a devops-engineer agent in Docker to do the work
2. Devops-engineer reads the client repo to identify endpoints and deployment type
3. Prometheus config updated — new `blackbox_http` targets added under the client label
4. Alert rules file created at `monitoring/prometheus/rules/<client>.yml`
5. Grafana dashboard JSON created at `monitoring/grafana/dashboards/<client>.json`
6. If Docker Compose on EC2: Alloy sidecar instructions generated for the client
7. Client documentation created at `docs/clients/<client>.md`
8. All changes committed and a pull request opened against `project-sauron`
9. PR merged → GitHub Actions deploys to EC2 → Prometheus reloaded → targets verified

### What you need to do after

**For Blackbox-only projects (CDN, Fly.io, Vercel):**

Nothing. After the PR merges and deploys, the endpoints appear in Prometheus automatically.

Verify:
```bash
# SSH tunnel to Prometheus
ssh -L 9090:localhost:9090 -i ~/.ssh/sauron ec2-user@<elastic_ip>
# Open http://localhost:9090/targets — look for job="blackbox_http", instance="https://your-endpoint"
```

**For Docker on EC2 projects (Alloy sidecar):**

On the client's EC2 instance, add the following to the project's `.env` file:

| Variable | Value | Description |
|---|---|---|
| `SAURON_METRICS_URL` | `https://sauron.yourdomain.com/metrics/push` | Prometheus remote-write endpoint |
| `SAURON_LOKI_URL` | `https://sauron.yourdomain.com/loki/api/v1/push` | Loki push endpoint |
| `PUSH_BEARER_TOKEN` | *(secret — get from Sauron operator)* | Bearer token for push auth |
| `CLIENT_NAME` | `<CLIENT_LABEL>` | Label for this project's metrics |
| `CLIENT_ENV` | `production` | Environment label |

Then start Alloy alongside the project's existing stack:

```bash
# From the client project's root directory
docker compose \
  -f docker-compose.yml \
  -f docker-compose.monitoring.yml \
  up -d alloy
```

Verify Alloy is shipping metrics:

```bash
# On Sauron's EC2 — check client label exists
curl -s http://localhost:9090/api/v1/label/client/values
# Expected: {"status":"success","data":["sauron","<CLIENT_LABEL>"]}
```

---

## MCP Server Projects (stdio transport)

MCP servers communicate via stdin/stdout — they have no HTTP port. Prometheus cannot scrape them
directly, and Alloy cannot attach to them as a sidecar.

**What Helldiver does instead:**
- Instruments the Node.js server with `prom-client` to collect internal metrics
- Wires a timer that pushes metrics to the Sauron Pushgateway every 30 seconds
- Creates a Blackbox probe on any GitHub Pages docs site the project has
- Creates a dashboard and alert rules scoped to Pushgateway metrics

**Example:** Project Alexandria — `mcp-server/index.js` runs via stdio. It has no HTTP surface.
Sauron monitors its GitHub Pages docs site via Blackbox, and (if instrumented) receives pushed
metrics via Pushgateway.

### How Helldiver detects MCP servers

Helldiver reads the target repo looking for these signals:
- `package.json` with `@modelcontextprotocol/sdk` as a dependency
- Server entry file using `StdioServerTransport` (from `@modelcontextprotocol/sdk/server/stdio`)
- No `fly.toml`, no `Dockerfile` with `EXPOSE`, no listening port in main entry file
- A `mcp-server/` subdirectory (conventional layout)

If all four are present: MCP stdio project. Helldiver uses the MCP instrumentation path.

### What gets instrumented

Helldiver adds a `monitoring/metrics.js` module to the MCP server project with:

**7 standard metrics (all MCP servers):**

| Metric | Type | Description |
|---|---|---|
| `mcp_requests_total` | Counter | Total tool/resource requests, labeled by `tool` and `status` |
| `mcp_request_duration_seconds` | Histogram | Request latency, labeled by `tool` |
| `mcp_errors_total` | Counter | Total errors, labeled by `tool` and `error_type` |
| `mcp_active_connections` | Gauge | Active stdio connections |
| `mcp_uptime_seconds` | Gauge | Server uptime |
| `process_cpu_seconds_total` | Counter | Node.js process CPU (from `prom-client` default) |
| `process_resident_memory_bytes` | Gauge | Node.js process RSS (from `prom-client` default) |

**Domain-specific metrics** (derived from reading the codebase — examples):
- For a knowledge base: `guide_reads_total{guide_name}`, `guide_write_total{guide_name}`
- For a data pipeline: `records_processed_total{stage}`, `pipeline_lag_seconds`

### How to wire the push timer

In the MCP server's entry file, add:

```javascript
import { startMetricsPush } from './monitoring/metrics.js';

// Start pushing metrics to Sauron Pushgateway every 30 seconds
startMetricsPush({
  url: process.env.SAURON_PUSHGATEWAY_URL,
  token: process.env.PUSH_BEARER_TOKEN,
  clientName: process.env.CLIENT_NAME || 'my-project',
  clientEnv: process.env.CLIENT_ENV || 'production',
  intervalMs: 30_000,
});
```

### Required env vars to set

Set these wherever the MCP server process starts (`.env` file, shell profile, or process manager config):

| Variable | Example | Description |
|---|---|---|
| `SAURON_PUSHGATEWAY_URL` | `https://sauron.yourdomain.com/metrics/gateway` | Sauron Pushgateway endpoint (via nginx) |
| `PUSH_BEARER_TOKEN` | *(secret)* | Bearer token — get from Sauron operator |
| `CLIENT_NAME` | `alexandria` | Identifies this project in Prometheus labels |
| `CLIENT_ENV` | `production` | Environment label |

> These env vars must be set in the environment where the MCP server **process** runs —
> not just where Claude Code runs. For Claude Code extensions: set them in your shell profile
> (`.bashrc`, `.zshrc`) or in the Claude Code extension's environment settings.

### Verify metrics are flowing

```bash
# Check Pushgateway has received metrics for this client
curl -s http://localhost:9091/metrics | grep 'client="<CLIENT_LABEL>"'
# Expected: metric lines with client label

# In Grafana → Explore → Prometheus
# Run: {job="pushgateway", client="<CLIENT_LABEL>"}
# Expected: metric series with recent timestamps
```

---

## Static Sites / GitHub Pages

For projects with only a static docs site (no backend, no Docker), Helldiver does Blackbox-only onboarding.

**What Helldiver does:**
- Adds the GitHub Pages URL to `blackbox_http` targets in `prometheus.yml`
- Creates alert rules: site down for 2m (critical), high latency for 5m (warning)
- Creates a minimal dashboard: uptime stat, response time graph, HTTP status code
- Documents the monitoring strategy in `docs/clients/<client>.md`

**What Helldiver does NOT do:**
- No Alloy agent (no server to attach to)
- No Pushgateway instrumentation (no Node.js process to add prom-client to)
- No host metrics (GitHub Pages is managed infrastructure)

**Invoke exactly the same as Standard Projects** — Helldiver will detect the static site
pattern (no Dockerfile, no Fly.io, no EC2, GitHub Pages URL in README) and use the
Blackbox-only path automatically.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Dashboard shows "No data" | Prometheus targets not scraped yet | Wait 30–60 seconds after deploy, then reload Prometheus: `curl -s -X POST http://localhost:9090/-/reload` |
| Dashboard shows "No data" even after reload | Datasource UID mismatch in dashboard JSON | In Grafana → Connections → Data sources → Prometheus → copy the UID → update every `"uid"` field in the dashboard JSON to match |
| Alloy not connecting to Sauron | Wrong `PUSH_BEARER_TOKEN` | Check `docker logs alloy` for `401` errors. Verify the token in the client `.env` matches `PUSH_BEARER_TOKEN_SAURON` in Sauron's `.env` |
| Alloy not connecting to Sauron | Wrong `SAURON_METRICS_URL` | Verify the URL is reachable: `curl -I https://sauron.yourdomain.com/metrics/push` — expect `401` (auth challenge), not connection refused |
| MCP metrics not appearing in Prometheus | Env vars not set when MCP server starts | Verify: `echo $SAURON_PUSHGATEWAY_URL` in the shell that starts Claude Code or the MCP server. If empty, add to shell profile and restart. |
| MCP metrics not appearing | Push timer not started | Check that `startMetricsPush()` is called in the server entry file. Add `console.error('metrics push started')` to confirm execution. |
| Prometheus target shows `DOWN` | Endpoint unreachable from Sauron's EC2 | Test from EC2: `curl -I <TARGET_URL>` — if it fails, the URL may be wrong, the service may be down, or a firewall is blocking Sauron's IP |
| PR conflicts on `prometheus.yml` | Another Helldiver run happened concurrently | Merge conflicts manually — each client gets its own block under `blackbox_http` targets, no structural changes needed |

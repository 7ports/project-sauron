---
layout: default
title: Project Alexandria — MCP Knowledge Base
nav_order: 5
---

# Project Alexandria — MCP Knowledge Base

**Repository:** [7ports/project-alexandria](https://github.com/7ports/project-alexandria)
**Docs site:** [https://7ports.github.io/project-alexandria/](https://7ports.github.io/project-alexandria/)
**Onboarded:** 2026-04-07 (Helldiver Squadron Beta)

---

## What is Project Alexandria?

Project Alexandria is a collaboratively maintained knowledge base of tooling setup guides.
It runs as a **stdio MCP server** (`mcp-server/index.js`) that Claude Code instances
connect to for tool setup guidance. All guide content is stored as Markdown files and
served via the Model Context Protocol.

---

## What Is Monitored

| Signal | Source | Target |
|---|---|---|
| HTTP uptime | Blackbox Exporter | `https://7ports.github.io/project-alexandria/` |
| Response time | Blackbox Exporter | `https://7ports.github.io/project-alexandria/` |
| HTTP status code | Blackbox Exporter | `https://7ports.github.io/project-alexandria/` |
| TLS certificate expiry | Blackbox Exporter | `https://7ports.github.io/project-alexandria/` |

**Probe interval:** 15 seconds (Prometheus global scrape interval)

---

## Why Docs-Site Probing?

The Alexandria MCP server runs via **stdio transport** — it communicates with Claude Code
through stdin/stdout and exposes no HTTP port. This means:

- Prometheus cannot scrape a `/metrics` endpoint (none exists)
- Blackbox Exporter cannot probe the server directly (no TCP/HTTP address)
- Alloy agent cannot be deployed (no persistent host — the server is a subprocess)
- Container logs are not accessible (no Docker container)

The **GitHub Pages documentation site** is the only publicly reachable HTTP surface.
Monitoring it confirms that the project's guide library is accessible and that the GitHub
Pages publishing pipeline is functioning. It serves as the best available external proxy
for project health.

---

## Dashboard

| Field | Value |
|---|---|
| Dashboard UID | `alexandria-overview` |
| Dashboard title | Project Alexandria — MCP Knowledge Base |
| Tags | `helldiver`, `alexandria` |
| Access | [https://sauron.7ports.ca](https://sauron.7ports.ca) → Dashboards → Browse |

### Panels

1. **GitHub Pages Uptime** — UP/DOWN stat indicator (green/red background)
2. **Avg Response Time** — current response time in seconds
3. **HTTP Status Code** — last observed HTTP status code
4. **Response Time History** — time-series graph (1-hour window, 30s refresh)
5. **About This Dashboard** — text panel explaining the stdio architecture and monitoring strategy

---

## Alert Rules

Defined in `monitoring/prometheus/rules/alexandria.yml`:

| Alert | Expression | Duration | Severity |
|---|---|---|---|
| `AlexandriaDocsDown` | `probe_success == 0` for the docs URL | 2 minutes | Critical |
| `AlexandriaDocsHighLatency` | `probe_duration_seconds > 2` for the docs URL | 5 minutes | Warning |

---

## Extending Monitoring

If Alexandria gains an HTTP interface (e.g., a web UI, REST API, or Fly.io deployment),
re-run the Helldiver onboarding pipeline to add:

- **Alloy agent** — host metrics + container logs
- **Additional Blackbox probes** — for new HTTP endpoints
- **Custom alert rules** — tailored to the new service

Open an issue on [project-sauron](https://github.com/7ports/project-sauron) to request
a re-onboarding run.

---

## Onboarding Files

| File | Location | Purpose |
|---|---|---|
| `ONBOARDING.md` | [project-alexandria root](https://github.com/7ports/project-alexandria/blob/main/ONBOARDING.md) | Explains monitoring setup to project contributors |

No client-side agent files were generated (Path B — hub-side monitoring only).

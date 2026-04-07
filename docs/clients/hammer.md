---
layout: default
title: Project Hammer — Ferry Tracker
nav_order: 4
---

# Project Hammer — Toronto Island Ferry Tracker

**Onboarded:** 2026-04-07
**Monitoring method:** Blackbox HTTP probing
**Client label:** `hammer`

---

## What is Monitored

Project Hammer is a real-time Toronto Island Ferry Tracker. Sauron monitors it via external Blackbox HTTP probing — no client-side agent is required.

| Endpoint | URL | Probe Interval |
|---|---|---|
| Frontend SPA | `https://ferries.yyz.live` | 30s |
| Backend health | `https://project-hammer-api.fly.dev/api/health` | 30s |

### Infrastructure

- **Frontend:** React 18 + Vite PWA, hosted on AWS S3 + CloudFront (ca-central-1)
- **Backend:** Node.js 20 + Express 5, deployed to Fly.io (region: `yyz` — Toronto)
- **No client-side Alloy agent** — CDN + Fly.io managed infra; external probing covers all SLOs

---

## Dashboard

View the live dashboard at:

**[https://sauron.7ports.ca](https://sauron.7ports.ca)** → Dashboards → **Project Hammer — Ferry Tracker Overview**

Dashboard UID: `hammer-overview`

### Panels

| Panel | Type | What it shows |
|---|---|---|
| Frontend Uptime | Stat (UP/DOWN) | `probe_success` for `ferries.yyz.live` |
| Backend Uptime | Stat (UP/DOWN) | `probe_success` for `/api/health` |
| Response Time | Time-series | `probe_duration_seconds` for both targets |
| HTTP Status Codes | Stat | `probe_http_status_code` for both targets |

---

## Alert Rules

File: `monitoring/prometheus/rules/hammer.yml`

| Alert | Expression | For | Severity |
|---|---|---|---|
| `HammerFrontendDown` | `probe_success{instance="https://ferries.yyz.live"} == 0` | 2m | critical |
| `HammerBackendDown` | `probe_success{instance="...fly.dev/api/health"} == 0` | 2m | critical |
| `HammerHighLatency` | `probe_duration_seconds{...} > 3` | 5m | warning |

> **Note:** Alertmanager routing is not yet configured — alerts fire in Prometheus UI but are not yet delivered via notification channel.

The latency threshold is **3s** (not the default 2s) to account for Fly.io `auto_stop_machines` cold starts.

---

## Adding Endpoints

To add a new endpoint for Project Hammer to Sauron monitoring, open an issue in [7ports/project-sauron](https://github.com/7ports/project-sauron) or edit `monitoring/prometheus/prometheus.yml` directly and add the URL to the `blackbox_http` static_configs.

---
layout: default
title: "Sauron Self-Monitoring"
parent: Clients
nav_order: 1
---

# Sauron Self-Monitoring

## Overview

Project Sauron monitors itself. The EC2 instance running the Sauron observability stack is also the first monitored client, making it a complete end-to-end validation of the platform.

**Why this exists:**
- Validates the full Alloy → nginx (Bearer auth) → Prometheus/Loki push pipeline end-to-end
- Serves as the canonical Alloy River config template for onboarding future clients
- Provides visibility into the health of the observability stack itself (meta-monitoring)

**Client labels applied to all metrics and logs:**

| Label | Value |
|---|---|
| `client` | `sauron` |
| `env` | `production` |

---

## What is Monitored

| Signal | Source | Collection Method |
|---|---|---|
| Host CPU / Memory / Disk | EC2 node-exporter (`:9100`) | Alloy `prometheus.scrape` → remote_write |
| Container logs | Docker daemon (socket) | Alloy `loki.source.docker` → Loki push |
| System logs | `/var/log/*.log` | Alloy `loki.source.file` → Loki push |
| Prometheus self-metrics | `localhost:9090/metrics` | Alloy `prometheus.scrape` → remote_write |
| Loki self-metrics | `loki:3100/metrics` | Alloy `prometheus.scrape` → remote_write |

---

## Architecture

Grafana Alloy runs as a sidecar container on the same EC2 instance as the rest of the Sauron stack, defined in `monitoring/docker-compose.monitoring.yml`. It is added via Docker Compose override so the core stack remains unchanged.

```
EC2 Instance (52.6.78.46)
│
├── docker-compose.yml          ← Core stack (Prometheus, Grafana, Loki, nginx, …)
└── docker-compose.monitoring.yml  ← Alloy sidecar (compose override)
      │
      └── alloy (container)
            ├── scrapes node-exporter → prometheus.scrape
            ├── scrapes localhost:9090 → prometheus.scrape
            ├── scrapes loki:3100     → prometheus.scrape
            ├── tails /var/log/*.log  → loki.source.file
            └── reads Docker socket  → loki.source.docker
                  │
                  ├── remote_write → https://sauron.7ports.ca/metrics/push
                  │                  (nginx Bearer token auth → Prometheus)
                  └── loki push   → https://sauron.7ports.ca/loki/api/v1/push
                                     (nginx Bearer token auth → Loki)
```

Alloy pushes through nginx (HTTPS) even though it is co-located on the same machine. This is intentional — it exercises the full authentication path used by all remote clients, ensuring the self-monitoring case validates the same code path.

---

## Configuration Files

| File | Purpose |
|---|---|
| `monitoring/alloy/config.alloy` | Alloy River config — scrape, log collection, remote_write, Loki push |
| `monitoring/docker-compose.monitoring.yml` | Compose override adding the Alloy sidecar container |
| `monitoring/prometheus/rules/sauron-self.yml` | Prometheus alert rules scoped to `client="sauron"` |
| `monitoring/grafana/dashboards/sauron-self.json` | Grafana dashboard — "Sauron Self-Monitoring" |

---

## Deployment

```bash
# From the project root /opt/project-sauron:

# 1. Ensure .env has all required variables set (see table below)

# 2. Start the full stack including Alloy:
docker compose -f monitoring/docker-compose.yml \
               -f monitoring/docker-compose.monitoring.yml \
               up -d

# 3. Or start just Alloy if the main stack is already running:
docker compose -f monitoring/docker-compose.yml \
               -f monitoring/docker-compose.monitoring.yml \
               up -d alloy
```

> **Note:** Always run `docker compose` from `/opt/project-sauron` (the project root). The `-f` flags must reference paths relative to the working directory.

---

## Required Environment Variables

Add these to `/opt/project-sauron/.env` on the EC2 instance. Never commit `.env` to the repository.

| Variable | Example Value | Description |
|---|---|---|
| `PUSH_BEARER_TOKEN_SAURON` | *(secret)* | Bearer token for Sauron's nginx-protected push endpoints |
| `SAURON_METRICS_URL` | `https://sauron.7ports.ca/metrics/push` | Prometheus remote_write endpoint (via nginx) |
| `SAURON_LOKI_URL` | `https://sauron.7ports.ca/loki/api/v1/push` | Loki push endpoint (via nginx) |
| `CLIENT_NAME` | `sauron` | Label applied to all metrics and logs |
| `CLIENT_ENV` | `production` | Environment label |

---

## Verification

### 1. Check Alloy is running

```bash
docker ps | grep alloy
```

Expected: one container named `alloy` with status `Up`.

### 2. Check Prometheus targets

Navigate to Prometheus internally on the EC2 instance:

```
http://localhost:9090/targets
```

Look for targets with `job="alloy-*"` or `client="sauron"` — all should be `UP`.

### 3. Confirm `client` label is present in Prometheus

```bash
curl -s http://localhost:9090/api/v1/label/client/values
```

Expected response includes `"sauron"` in the values array:

```json
{"status":"success","data":["sauron"]}
```

### 4. Check Loki logs are flowing

In Grafana (https://sauron.7ports.ca):

1. Navigate to **Explore**
2. Select the **Loki** datasource
3. Run the query: `{client="sauron"}`
4. Confirm log lines are appearing with recent timestamps

### 5. View the dashboard

In Grafana → **Dashboards** → search for **"Sauron Self-Monitoring"**

The dashboard should show panels for:
- CPU usage
- Memory usage
- Disk usage
- Container log volume
- Prometheus target health

---

## Alert Rules

Alert rules are defined in `monitoring/prometheus/rules/sauron-self.yml`, all scoped with `client="sauron"`.

| Alert | Condition | Severity |
|---|---|---|
| `SauronContainerDown` | Any container in the stack exits unexpectedly | critical |
| `SauronHighMemoryUsage` | EC2 memory usage > 85% for 5m | warning |
| `SauronDiskSpaceLow` | Disk free < 15% on any mount for 10m | warning |
| `SauronHighCPU` | CPU usage > 90% for 10m | warning |
| `SauronPrometheusTargetDown` | Any Prometheus scrape target reports DOWN for 5m | critical |
| `SauronLokiIngestionError` | Loki ingestion error rate > 0 for 5m | warning |

> Alertmanager routing is not yet configured. These rules fire in Prometheus but notifications are not delivered until alertmanager is wired up. See [Known Issues / Tech Debt](#known-limitations--notes).

---

## Known Limitations / Notes

- **Redundant node-exporter scrape:** Alloy scrapes node-exporter separately from Prometheus's existing scrape job. This is intentional — the Alloy scrape adds the `client="sauron"` label via remote_write, while the Prometheus-direct scrape does not. Both exist in parallel to test the full push path.

- **HTTPS for local push:** Alloy pushes metrics and logs through nginx (HTTPS) even though Alloy and Prometheus/Loki are on the same machine. This is intentional — it validates the same Bearer-token auth path that remote clients use, making this a true end-to-end test of the platform.

- **Alertmanager not wired:** Alert rules are defined but Alertmanager routing is not yet configured. No notifications will be sent until `monitoring/prometheus/prometheus.yml` is updated with an `alertmanager_configs` block and Alertmanager is added to the Compose stack.

- **Dashboard requires Loki datasource:** The `sauron-self.json` dashboard uses both Prometheus and Loki datasources. Ensure both are provisioned before loading the dashboard.

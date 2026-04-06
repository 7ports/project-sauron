---
layout: default
title: Architecture
nav_order: 2
---

# Architecture

## Overview

Project Sauron uses a pull-based metrics architecture: Prometheus scrapes exporters on a 15-second interval, stores metrics in a local time-series database (30-day retention), and Grafana queries Prometheus to render dashboards.

All services run as Docker containers on a single EC2 `t3.small` instance, orchestrated by Docker Compose. This minimizes cost and operational complexity for a personal observability stack.

---

## Component Descriptions

### Prometheus
- **Role:** Metrics store and scrape engine
- **Port:** 9090 (internal only — not exposed to the internet)
- **Config:** `monitoring/prometheus/prometheus.yml`
- **Retention:** 30 days of metrics
- **Access:** Via SSH tunnel (`ssh -L 9090:localhost:9090 ec2-user@<ip>`)

### Grafana
- **Role:** Visualization, dashboarding, and alerting UI
- **Port:** 3000 (public, protected by admin password)
- **Config:** Provisioned automatically from `monitoring/grafana/provisioning/`
- **Datasource:** Prometheus (auto-provisioned)
- **Dashboards:** Auto-provisioned from `monitoring/grafana/dashboards/`

### Node Exporter
- **Role:** Exposes EC2 host metrics (CPU, memory, disk, network) to Prometheus
- **Port:** 9100 (internal only)
- **Metrics:** All standard Linux host metrics

### Blackbox Exporter
- **Role:** Probes HTTP/HTTPS endpoints from the outside, measuring uptime, response time, and SSL certificate health
- **Port:** 9115 (internal only)
- **Modules:** `http_2xx`, `tcp_connect` (TLS cert expiry)

### CloudWatch Exporter
- **Role:** Bridges AWS CloudWatch metrics into Prometheus
- **Port:** 9106 (internal only)
- **Metrics:** EC2 CPU, network; Lambda invocations, errors, duration; S3 bucket size
- **Auth:** IAM role attached to EC2 instance (no static credentials needed on EC2)

---

## Data Flow

```
External Endpoints (HTTP)
        │
        ▼
Blackbox Exporter ──────────────────────────┐
                                            │
EC2 Host ──► Node Exporter ─────────────────┤
                                            ▼
AWS CloudWatch ──► CloudWatch Exporter ──► Prometheus ──► Grafana ──► Browser
                                            │
                                     Rules Engine
                                    (Alert evaluation)
```

---

## Security Model

| Resource | Access |
|---|---|
| Grafana (:3000) | Public internet (password protected) |
| Prometheus (:9090) | Internal only — SSH tunnel required |
| Node Exporter (:9100) | Internal only |
| Blackbox (:9115) | Internal only |
| CloudWatch (:9106) | Internal only |
| SSH (:22) | Restricted to your IP via security group |

---

## Infrastructure

| Resource | Value |
|---|---|
| Provider | AWS |
| Region | us-east-1 (configurable) |
| Instance | EC2 t3.small |
| AMI | Amazon Linux 2023 (latest) |
| Storage | 20 GiB gp3 EBS (encrypted) |
| IP | Elastic IP (stable across reboots) |
| IAM | EC2 role with CloudWatch read-only |

---

## Alerting

Alert rules are defined in `monitoring/prometheus/rules/alerting.yml`. Configured alerts include:

- Host CPU > 80% for 5 minutes
- Host memory < 15% available
- Host disk < 20% available
- Any monitored endpoint down for 2+ minutes
- Endpoint response time > 2s
- SSL certificate expiring within 30 days
- Prometheus target missing

**Note:** Alertmanager is not yet configured. Alerts are evaluated but not routed. To add notifications, add an Alertmanager service to `docker-compose.yml` and configure receivers (email, Slack, PagerDuty).

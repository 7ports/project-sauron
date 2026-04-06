---
layout: default
title: Dashboards
nav_order: 4
---

# Dashboards

All dashboards are pre-provisioned and available in Grafana under the **Project Sauron** folder immediately after first launch.

---

## Web Traffic & Uptime

**UID:** `web-traffic-sauron` | **Refresh:** 1 minute | **Default time range:** Last 24 hours

Monitors the availability and performance of all frontend and web properties.

### Panels

| Panel | Description |
|---|---|
| **Endpoint Status** | Current UP/DOWN state for all monitored URLs |
| **Response Time** | HTTP probe duration over time, with mean and max |
| **Uptime (5m avg)** | Rolling 5-minute availability percentage per endpoint |
| **SSL Certificate Expiry** | Days until SSL certificate expires — turns red at < 30 days |

### Key Metrics

- `probe_success` — 1 if the HTTP probe succeeded, 0 if it failed
- `probe_duration_seconds` — how long the probe took
- `probe_ssl_earliest_cert_expiry` — Unix timestamp of the earliest cert expiry
- `endpoint:probe_success:rate5m` — recording rule: 5-minute uptime ratio

---

## API & Host Overview

**UID:** `api-overview-sauron` | **Refresh:** 30 seconds | **Default time range:** Last 6 hours

The default home dashboard. Shows API endpoint health alongside the EC2 host resource utilization.

### Panels

| Panel | Description |
|---|---|
| **API Status** | UP/DOWN state for API endpoints specifically |
| **Host CPU** | Current CPU utilization % of the EC2 instance |
| **Host Memory** | Current memory utilization ratio |
| **Host Disk** | Current disk utilization ratio for `/` |
| **API Response Time** | Probe duration for API endpoints, with mean and P95 |
| **Host CPU Over Time** | CPU utilization trend |

### Key Metrics

- `instance:node_cpu_utilisation:rate5m` — recording rule: CPU %
- `instance:node_memory_utilisation:ratio` — recording rule: memory ratio
- `instance:node_disk_utilisation:ratio` — recording rule: disk ratio
- `node_network_receive_bytes_total` — network receive bytes

---

## AWS Overview

**UID:** `aws-overview-sauron` | **Refresh:** 5 minutes | **Default time range:** Last 6 hours

CloudWatch metrics bridged via the CloudWatch Exporter. Covers EC2, Lambda, and S3.

### Panels

| Panel | Description |
|---|---|
| **EC2 CPU Utilization** | CloudWatch EC2 CPU % per instance |
| **EC2 Network I/O** | Inbound and outbound network throughput |
| **Lambda Invocations** | Invocation count per function |
| **Lambda Errors** | Error count per function |
| **Lambda Duration** | Average execution duration per function |

### Notes

- CloudWatch metrics have a 1-minute resolution (Prometheus scrapes every 60s)
- Lambda function names appear automatically as dimensions once data flows
- S3 metrics are daily — they won't appear on sub-24h time ranges

---

## Adding Custom Dashboards

To add a new dashboard:

1. Build it in the Grafana UI
2. Export as JSON (`Dashboard settings > JSON Model`)
3. Save the JSON file to `monitoring/grafana/dashboards/`
4. Commit and push — the dashboard will auto-provision on next restart

Or use `allowUiUpdates: true` in the provisioning config to save changes directly from the UI (changes persist to the Docker volume but won't be in git).

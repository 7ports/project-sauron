---
layout: default
title: Home
nav_order: 1
---

# Project Sauron

> *One stack to see them all.*

Project Sauron is a self-hosted observability platform that provides comprehensive monitoring for all personal projects. It runs **Grafana** and **Prometheus** on a single AWS EC2 instance via Docker Compose, giving a unified view of web traffic, API health, host metrics, and AWS service performance.

---

## What It Monitors

| Signal | Source | Dashboard |
|---|---|---|
| Frontend uptime & response time | Blackbox Exporter (HTTP probing) | Web Traffic & Uptime |
| Backend API health & latency | Blackbox Exporter | API & Host Overview |
| EC2 host metrics (CPU, memory, disk) | Node Exporter | API & Host Overview |
| AWS CloudWatch metrics (EC2, Lambda, S3) | CloudWatch Exporter | AWS Overview |

---

## Architecture

```
                  ┌─────────────────────────────────────────┐
                  │          AWS EC2 (t3.small)              │
                  │                                          │
  Your Projects   │  ┌─────────────┐   ┌─────────────────┐  │
  ─────────────►  │  │  Prometheus  │──►│     Grafana     │  │◄── Browser
  (HTTP probed)   │  │  :9090      │   │     :3000       │  │
                  │  └──────┬──────┘   └─────────────────┘  │
                  │         │                                 │
                  │  ┌──────▼──────────────────────────────┐ │
                  │  │            Exporters                 │ │
                  │  │  node-exporter  :9100               │ │
                  │  │  blackbox       :9115               │ │
                  │  │  cloudwatch     :9106               │ │
                  │  └─────────────────────────────────────┘ │
                  └─────────────────────────────────────────┘
                                    │
                            AWS CloudWatch
                         (EC2, Lambda, S3 metrics)
```

---

## Quick Links

- [GitHub Repository](https://github.com/7ports/project-sauron)
- [Setup Guide](setup.md)
- [Architecture Details](architecture.md)
- [Dashboards](dashboards.md)
- [Helldiver — Onboarding Projects](helldiver.md)

---

## Stack

| Component | Version | Purpose |
|---|---|---|
| Prometheus | latest | Metrics collection and storage |
| Grafana | latest | Visualization and alerting |
| Node Exporter | latest | EC2 host metrics |
| Blackbox Exporter | latest | HTTP endpoint probing |
| CloudWatch Exporter | latest | AWS service metrics |
| Terraform | >= 1.6 | Infrastructure as code |
| Docker Compose | v2 | Container orchestration |

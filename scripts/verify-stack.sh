#!/usr/bin/env bash
# verify-stack.sh — Post-deploy health check for Project Sauron
# Runs all checks, accumulates failures, exits 1 if any check failed.
# Usage: bash scripts/verify-stack.sh [--json]

set -uo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
COMPOSE_FILES="-f monitoring/docker-compose.yml -f monitoring/docker-compose.monitoring.yml"
REQUIRED_CONTAINERS=(prometheus grafana nginx pushgateway loki alloy blackbox node-exporter)
JSON_OUTPUT=false

for arg in "$@"; do
  [[ "$arg" == "--json" ]] && JSON_OUTPUT=true
done

# ---------------------------------------------------------------------------
# State tracking
# ---------------------------------------------------------------------------
declare -A CHECK_STATUS   # PASS | FAIL
declare -A CHECK_DETAIL   # human-readable detail string
FAILURES=0

pass() { CHECK_STATUS["$1"]="PASS"; CHECK_DETAIL["$1"]="${2:-}"; }
fail() { CHECK_STATUS["$1"]="FAIL"; CHECK_DETAIL["$1"]="${2:-}"; (( FAILURES++ )) || true; }

# ---------------------------------------------------------------------------
# Check 1: Required containers running
# ---------------------------------------------------------------------------
check_containers() {
  local label="containers"
  local missing=()

  # Get names of running containers from compose ps
  local running
  running=$(docker compose $COMPOSE_FILES ps --format "{{.Name}}" 2>/dev/null | tr '[:upper:]' '[:lower:]') || true

  for svc in "${REQUIRED_CONTAINERS[@]}"; do
    # Match service name as substring of container name (handles prefix like "monitoring_")
    if ! echo "$running" | grep -q "$svc"; then
      missing+=("$svc")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    pass "$label" "all required containers running"
  else
    fail "$label" "missing containers: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# Check 2: Prometheus ready
# ---------------------------------------------------------------------------
check_prometheus_ready() {
  local label="prometheus_ready"
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:9090/-/ready 2>/dev/null) || true
  if [[ "$http_code" == "200" ]]; then
    pass "$label" "HTTP $http_code"
  else
    fail "$label" "HTTP $http_code (expected 200)"
  fi
}

# ---------------------------------------------------------------------------
# Check 3: Prometheus has targets
# ---------------------------------------------------------------------------
check_prometheus_targets() {
  local label="prometheus_targets"
  local body
  body=$(curl -sf --max-time 5 http://localhost:9090/api/v1/targets 2>/dev/null) || true
  local count
  count=$(echo "$body" | grep -o '"activeTargets":\[[^]]*\]' | grep -o 'scrapeUrl' | wc -l 2>/dev/null) || count=0
  # Simpler check: any "scrapeUrl" key in response means at least one target
  if echo "$body" | grep -q '"scrapeUrl"'; then
    pass "$label" "at least one active target found"
  else
    fail "$label" "no active targets returned from /api/v1/targets"
  fi
}

# ---------------------------------------------------------------------------
# Check 4: Grafana health
# ---------------------------------------------------------------------------
check_grafana() {
  local label="grafana_health"
  local body
  body=$(curl -sf --max-time 5 http://localhost:3000/api/health 2>/dev/null) || true
  if echo "$body" | grep -q '"database":"ok"'; then
    pass "$label" "database: ok"
  else
    fail "$label" "unexpected response: ${body:0:120}"
  fi
}

# ---------------------------------------------------------------------------
# Check 5: nginx serving
# ---------------------------------------------------------------------------
check_nginx() {
  local label="nginx_serving"
  local http_code
  http_code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 --location https://localhost 2>/dev/null) || true
  if [[ "$http_code" == "200" || "$http_code" == "302" ]]; then
    pass "$label" "HTTP $http_code"
  else
    fail "$label" "HTTP $http_code (expected 200 or 302)"
  fi
}

# ---------------------------------------------------------------------------
# Check 6: Pushgateway responsive
# ---------------------------------------------------------------------------
check_pushgateway() {
  local label="pushgateway"
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:9091/metrics 2>/dev/null) || true
  if [[ "$http_code" == "200" ]]; then
    pass "$label" "HTTP $http_code"
  else
    fail "$label" "HTTP $http_code (expected 200)"
  fi
}

# ---------------------------------------------------------------------------
# Run all checks (each catches its own errors via || true patterns inside)
# ---------------------------------------------------------------------------
check_containers
check_prometheus_ready
check_prometheus_targets
check_grafana
check_nginx
check_pushgateway

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
ALL_CHECKS=(containers prometheus_ready prometheus_targets grafana_health nginx_serving pushgateway)

if [[ "$JSON_OUTPUT" == "true" ]]; then
  echo "{"
  echo "  \"overall\": \"$([ $FAILURES -eq 0 ] && echo PASS || echo FAIL)\","
  echo "  \"failures\": $FAILURES,"
  echo "  \"checks\": {"
  last_idx=$(( ${#ALL_CHECKS[@]} - 1 ))
  for i in "${!ALL_CHECKS[@]}"; do
    key="${ALL_CHECKS[$i]}"
    comma=$([[ $i -lt $last_idx ]] && echo "," || echo "")
    echo "    \"$key\": {\"status\": \"${CHECK_STATUS[$key]:-UNKNOWN}\", \"detail\": \"${CHECK_DETAIL[$key]:-}\"}${comma}"
  done
  echo "  }"
  echo "}"
else
  echo "========================================"
  echo " Project Sauron — Stack Verification"
  echo "========================================"
  for key in "${ALL_CHECKS[@]}"; do
    status="${CHECK_STATUS[$key]:-UNKNOWN}"
    detail="${CHECK_DETAIL[$key]:-}"
    if [[ "$status" == "PASS" ]]; then
      echo "  [PASS] $key — $detail"
    else
      echo "  [FAIL] $key — $detail"
    fi
  done
  echo "----------------------------------------"
  if [[ $FAILURES -eq 0 ]]; then
    echo "  RESULT: ALL CHECKS PASSED"
  else
    echo "  RESULT: $FAILURES CHECK(S) FAILED"
  fi
  echo "========================================"
fi

# Exit 1 if any check failed
exit $FAILURES

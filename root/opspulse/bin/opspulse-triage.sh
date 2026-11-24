#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/root/opspulse"
cd "$BASE_DIR"
TS=$(date +%Y%m%d_%H%M%S)
REPORT="$BASE_DIR/reports/incident_report_${TS}.txt"

{
  echo "=========================================================="
  echo " OPSPULSE INCIDENT TRIAGE REPORT | $TS"
  echo "=========================================================="
  echo "Working Directory : $(pwd)"
  echo "Kernel Info       : $(uname -srm)"
  echo ""
  echo "--- 1. HOST IDENTITY (hostnamectl) ---"
  hostnamectl | grep -E "Static hostname|Operating System|Kernel|Architecture" || true

  echo ""
  echo "--- 2. TOOLCHAIN & PATH VERIFICATION (command -v, which, type) ---"
  for tool in jq awk sed grep systemctl; do
    echo "Tool: $tool | command -v: $(command -v $tool) | which: $(which $tool) | type: $(type -t $tool)"
  done

  echo ""
  echo "--- 3. ARTIFACT INTEGRITY & CONFIG BACKUP (cp, file, ls) ---"
  cp "$BASE_DIR/config/worker.conf" "$BASE_DIR/config/worker.conf.bak"
  file "$BASE_DIR/config/worker.conf" "$BASE_DIR/api/cluster-health.json"
  ls -lh "$BASE_DIR/config/"

  echo ""
  echo "--- 4. SYSTEMD SERVICE & JOURNAL FORENSICS (systemctl, journalctl) ---"
  echo "Service Active State : $(systemctl is-active opspulse-worker.service || true)"
  echo "Service Failed State : $(systemctl is-failed opspulse-worker.service || true)"
  echo "Recent Journal Logs  :"
  journalctl -u opspulse-worker.service -n 6 --no-pager

  echo ""
  echo "--- 5. LOG ERROR ANALYSIS & TOKEN SANITIZATION (grep, cut, tr, sed, awk) ---"
  echo "Total HTTP 5xx Errors: $(grep -E '\|50[0-9]\|' "$BASE_DIR/logs/app-gateway.log" | wc -l)"
  echo "Top Offending Client IPs (cut + awk):"
  grep -E '\|50[0-9]\|' "$BASE_DIR/logs/app-gateway.log" | cut -d'|' -f2 | awk '{count[$1]++} END {for (ip in count) print "  " ip " -> " count[ip] " failures"}'
  echo "Sanitized Error Lines (sed masking secrets + tr uppercase severity):"
  grep -E '\|50[0-9]\|' "$BASE_DIR/logs/app-gateway.log" \
    | sed -E 's/sk_live_[A-Za-z0-9]+/[REDACTED_TOKEN]/g' \
    | tr 'a-z' 'A-Z'

  echo ""
  echo "--- 6. KUBERNETES / API JSON HEALTH TRIAGE (jq) ---"
  jq -r '.services[] | select(.status != "healthy") | "ALERT: Service \(.name) is \(.status | ascii_upcase) (Restarts: \(.restarts), Latency: \(.latency_ms)ms)"' "$BASE_DIR/api/cluster-health.json"

} | tee "$REPORT"

# Archive a copy for post-mortem retention (mv)
cp "$REPORT" "$BASE_DIR/archive/"
mv "$BASE_DIR/config/worker.conf.bak" "$BASE_DIR/archive/worker.conf.${TS}.bak"
echo ""
echo "[OK] Report archived to: $BASE_DIR/archive/incident_report_${TS}.txt"

#!/usr/bin/env bash
# Minimal post-deploy smoke test: the endpoint users hit must answer,
# fast, and with the expected shape. Fails the pipeline (and thereby
# triggers rollback attention) on any miss.
set -euo pipefail

BASE_URL=$1

for i in {1..10}; do
  code=$(curl -s -o /tmp/smoke.json -w '%{http_code}' -m 5 "${BASE_URL}/status")
  if [[ "$code" == "200" ]] && grep -q '"status":"ok"' /tmp/smoke.json; then
    echo "smoke OK (attempt $i)"
    exit 0
  fi
  sleep 5
done

echo "smoke FAILED against ${BASE_URL}"
exit 1

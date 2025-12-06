#!/bin/sh
set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Error: FLOW_ID, API_KEY arguments are required!" >&2
  exit 1
fi

FLOW_ID=$1
API_KEY=$2

LANGFLOW_URL="http://langflow:7860"
JSON_PAYLOAD='{"input_value": "benchmark_test", "input_type": "chat", "output_type": "chat", "tweaks": {}}'

REPLICA_STEPS="1 2 4 8 16"

start_monitoring() {
  echo "   [MONITOR] Starting DB metrics collection..."
  while true; do
    PG_POD=$(kubectl get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$PG_POD" ]; then
        STATS=$(kubectl exec "$PG_POD" -- sh -c "psql -U postgres_user -d langflow_db -tA -c \"SELECT count(*) FROM pg_stat_activity WHERE state='active';\"" 2>/dev/null)
        WAITING=$(kubectl exec "$PG_POD" -- sh -c "psql -U postgres_user -d langflow_db -tA -c \"SELECT count(*) FROM pg_stat_activity WHERE wait_event_type IS NOT NULL;\"" 2>/dev/null)

        PGB_MSG=""
        PGB_POD=$(kubectl get pod -l app=pgbouncer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$PGB_POD" ]; then
             PGB_WAIT=$(kubectl exec "$PGB_POD" -- sh -c "export PGPASSWORD='password'; psql -U postgres_user -d pgbouncer -p 6432 -tA -c 'SHOW POOLS;' | grep langflow_db | awk -F'|' '{print \$4}'" 2>/dev/null)
             PGB_MSG="| PGB-Wait: ${PGB_WAIT:-0}"
        fi

        echo "   [DB-STAT] Active: $STATS | Waiting: $WAITING $PGB_MSG"
    fi
    sleep 5
  done
}

echo "========================================================================"
echo "🚀 STARTING CITUS STRESS TEST (Pod Scaling Mode)"
echo "   Target: $LANGFLOW_URL"
echo "   Flow ID: $FLOW_ID"
echo "========================================================================"

for replicas in $REPLICA_STEPS; do
  echo ""
  echo "------------------------------------------------------------------------"
  echo "👉 STEP: Testing with $replicas Langflow Replica(s)"
  echo "------------------------------------------------------------------------"

  echo "Scaling Langflow deployment to $replicas replicas..."
  kubectl scale deployment langflow --replicas=$replicas

  echo "Waiting for pods to be ready..."
  kubectl rollout status deployment/langflow --timeout=180s 2>&1 | grep -v "reflector" || true

  echo "Stabilizing (15s)..."
  sleep 15

  # --- MONITORING ---
    start_monitoring &
    MONITOR_PID=$!
  # ------------------

  CONCURRENCY=$((replicas * 50))

  echo "🔥 Firing load: $CONCURRENCY concurrent users for 30 seconds..."

  RESULT=$(hey -z 30s -c $CONCURRENCY -t 60 \
    -H "x-api-key: $API_KEY" \
    -H "Content-Type: application/json" \
    -m POST -d "$JSON_PAYLOAD" \
    "$LANGFLOW_URL/api/v1/run/$FLOW_ID?stream=false")

  # --- MONITORING STOP ---
  kill $MONITOR_PID 2>/dev/null || true
  wait $MONITOR_PID 2>/dev/null || true
  echo "   [MONITOR] Stopped."
  # -----------------------

  echo ""
  echo "--- Full 'hey' command output: ---"
  echo "$RESULT"
  echo "------------------------------------"

  RPS=$(echo "$RESULT" | grep "Requests/sec" | awk '{print $2}')
  ERRORS=$(echo "$RESULT" | grep "Status code distribution" -A 10 | grep "\[5" | awk '{sum+=$2} END {print sum+0}')

  if [ "$ERRORS" -gt 0 ]; then
      echo "⚠️  WARNING: High error rate detected! System might be overloaded."
  fi
done

echo ""
echo "========================================================================"
echo "✅ BENCHMARK COMPLETED."
echo "========================================================================"
kubectl scale deployment langflow --replicas=1

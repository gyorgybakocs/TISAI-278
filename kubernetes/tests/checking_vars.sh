#!/bin/bash

# Simple checker for Postgres & PgBouncer runtime config values
# Matches the keys used in configure_resources.sh

echo "==========================================================="
echo "🔎 CHECKING RUNTIME DB CONFIG VALUES"
echo "==========================================================="

# ----------------- POSTGRES -----------------
echo
echo "🐘 POSTGRES CONFIG (/etc/postgresql/postgresql.conf)"
POSTGRES_POD=$(kubectl get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POSTGRES_POD" ]; then
  echo "  ❌ No Postgres pod found with label app=postgres"
else
  echo "  -> Pod: $POSTGRES_POD"
  PG_CONF_PATH="/etc/postgresql/postgresql.conf"

  PG_PARAMS=(
    "max_connections"
    "max_prepared_transactions"
    "shared_buffers"
    "effective_cache_size"
    "work_mem"
    "maintenance_work_mem"
    "max_worker_processes"
    "max_parallel_workers"
  )

  kubectl exec "$POSTGRES_POD" -- sh -c "if [ ! -f '$PG_CONF_PATH' ]; then echo '  ❌ Postgres config file not found at $PG_CONF_PATH'; exit 0; fi"

  for p in "${PG_PARAMS[@]}"; do
    echo -n "  - $p = "
    kubectl exec "$POSTGRES_POD" -- sh -c "grep -E '^$p\s*=' '$PG_CONF_PATH' || echo '<NOT SET>'"
  done
fi

# ----------------- PGBOUNCER -----------------
echo
echo "🎯 PGBOUNCER CONFIG (/etc/pgbouncer/pgbouncer.ini)"
PGBOUNCER_POD=$(kubectl get pod -l app=pgbouncer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$PGBOUNCER_POD" ]; then
  echo "  ❌ No PgBouncer pod found with label app=pgbouncer"
else
  echo "  -> Pod: $PGBOUNCER_POD"
  PGB_CONF_PATH="/etc/pgbouncer/pgbouncer.ini"

  PGB_PARAMS=(
    "pool_mode"
    "max_client_conn"
    "default_pool_size"
  )

  kubectl exec "$PGBOUNCER_POD" -- sh -c "if [ ! -f '$PGB_CONF_PATH' ]; then echo '  ❌ PgBouncer config file not found at $PGB_CONF_PATH'; exit 0; fi"

  for p in "${PGB_PARAMS[@]}"; do
    echo -n "  - $p = "
    kubectl exec "$PGBOUNCER_POD" -- sh -c "grep -E '^$p\s*=' '$PGB_CONF_PATH' || echo '<NOT SET>'"
  done
fi

echo
echo "✅ Config check finished."

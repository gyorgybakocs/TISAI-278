#!/bin/bash
set -e

echo "==============================================="
echo "🧪 TESTING CITUS SHARDING & DISTRIBUTION"
echo "==============================================="

PG_POD=$(kubectl get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}')

if [ -z "$PG_POD" ]; then
    echo "❌ Postgres pod not found!"
    exit 1
fi

echo "Target Pod: $PG_POD"
echo "-----------------------------------------------"

run_sql() {
    kubectl exec "$PG_POD" -- bash -c "export PGPASSWORD='password'; psql -U postgres_user -d langflow_db -tA -c \"$1\""
}

echo -n "1️⃣  Checking Citus Extension... "
VERSION=$(run_sql "SELECT citus_version();")
if [[ $VERSION == *"Citus"* ]]; then
    echo "✅ OK ($VERSION)"
else
    echo "❌ FAILED (Citus extension not found or not active)"
    exit 1
fi

echo "-----------------------------------------------"
echo "2️⃣  Verifying Distributed Tables (Sharding)"

DIST_TABLES=$(run_sql "SELECT table_name || ' (' || distribution_column || ')' FROM citus_tables WHERE table_name IN ('transaction', 'message');")

echo "   Found distributed tables:"
echo "$DIST_TABLES" | sed 's/^/      -> /'

if echo "$DIST_TABLES" | grep -q "transaction" && echo "$DIST_TABLES" | grep -q "message"; then
    echo "✅ OK: Both 'transaction' and 'message' are distributed."
else
    echo "❌ FAILED: One or more tables are NOT distributed!"
    exit 1
fi

if echo "$DIST_TABLES" | grep "message" | grep -q "(id)"; then
    echo "✅ OK: 'message' table is sharded by 'id' (Safe Mode)."
else
    echo "⚠️  WARNING: 'message' table sharding key is NOT 'id'. Check your configuration!"
fi

echo "-----------------------------------------------"
echo "3️⃣  Checking Shard Metadata (pg_dist_shard)"
SHARD_COUNT=$(run_sql "SELECT count(*) FROM pg_dist_shard WHERE logicalrelid::regclass::text IN ('transaction', 'message');")

echo "   Total shards managed: $SHARD_COUNT"
if [ "$SHARD_COUNT" -gt 0 ]; then
    echo "✅ OK: Shards exist."
else
    echo "❌ FAILED: No shards found! Tables might be empty or not distributed correctly."
    exit 1
fi

echo "-----------------------------------------------"
echo "🎉 CITUS TEST PASSED! System is fully sharded."
echo "==============================================="

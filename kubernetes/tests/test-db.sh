#!/bin/bash
set -e

echo "==============================================="
echo "🧪 TESTING POSTGRES & PGBOUNCER FLOW"
echo "==============================================="

CLIENT_POD=$(kubectl get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}')
DB_NAME="langflow_db"
TEST_VALUE="InitTest_$(date +%s)"

echo "Client Pod: $CLIENT_POD"

echo "-----------------------------------------------"
echo "🔍 DIAGNOSTICS: Listing Databases & Tables"
echo "-----------------------------------------------"

# 1. Listázza az összes adatbázist
echo "Available Databases:"
kubectl exec $CLIENT_POD -- bash -c "
    export PGPASSWORD=\"\$POSTGRES_PASSWORD\";
    psql -U \"\$POSTGRES_USER\" -d postgres -c '\l'
"

# 2. Listázza a táblákat a cél adatbázisban (langflow_db)
echo "-----------------------------------------------"
echo "Tables in $DB_NAME:"
kubectl exec $CLIENT_POD -- bash -c "
    export PGPASSWORD=\"\$POSTGRES_PASSWORD\";
    psql -U \"\$POSTGRES_USER\" -d $DB_NAME -c '\dt' || echo '⚠️  Database $DB_NAME does not exist or is not accessible.'
"

echo "-----------------------------------------------"
echo "1️⃣  Writing via PGBOUNCER (Service: pgbouncer, Port: 6432)"
kubectl exec $CLIENT_POD -- bash -c "
    export PGPASSWORD=\"\$POSTGRES_PASSWORD\";
    psql -U \"\$POSTGRES_USER\" -h pgbouncer -p 6432 -d $DB_NAME -c \"
        CREATE TABLE IF NOT EXISTS smoke_test (id SERIAL PRIMARY KEY, val TEXT);
        INSERT INTO smoke_test (val) VALUES ('$TEST_VALUE');
    \"
"
if [ $? -eq 0 ]; then echo "✅ Write via PgBouncer success."; else echo "❌ Write failed."; exit 1; fi

echo "-----------------------------------------------"
echo "2️⃣  Reading directly from POSTGRES (Localhost, Port: 5432)"
READ_VAL=$(kubectl exec $CLIENT_POD -- bash -c "
    export PGPASSWORD=\"\$POSTGRES_PASSWORD\";
    psql -U \"\$POSTGRES_USER\" -h localhost -p 5432 -d $DB_NAME -tA -c \"
        SELECT val FROM smoke_test WHERE val = '$TEST_VALUE';
    \"
")

echo "   -> Wrote: $TEST_VALUE"
echo "   -> Read:  $READ_VAL"

if [ "$READ_VAL" == "$TEST_VALUE" ]; then
    echo "✅ Data consistency verified!"
else
    echo "❌ Data mismatch! Persistence failed."
    exit 1
fi

echo "-----------------------------------------------"
echo "🧹 Cleaning up test table..."
kubectl exec $CLIENT_POD -- bash -c "
    export PGPASSWORD=\"\$POSTGRES_PASSWORD\";
    psql -U \"\$POSTGRES_USER\" -h pgbouncer -p 6432 -d $DB_NAME -c \"DROP TABLE smoke_test;\"
" > /dev/null
echo "✅ Cleanup done."

echo "==============================================="
echo "🎉 DATABASE FLOW TEST PASSED!"
echo "==============================================="

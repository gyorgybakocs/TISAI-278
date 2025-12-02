#!/bin/bash

echo "--- 🔵 Live PgBouncer Pool Monitor (Press Ctrl+C to stop) ---"

PSQL_POD=$(kubectl get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}')

if [ -z "$PSQL_POD" ]; then
    echo "❌ Postgres (psql client) pod not found."
    exit 1
fi

echo "Connecting to PgBouncer via pod: $PSQL_POD"
echo "Target: pgbouncer-service:6432"
echo "------------------------------------------------------------------------------------------------"
echo " DATABASE      | CL_ACTIVE | CL_WAITING | SV_ACTIVE | SV_IDLE | MAXWAIT(s)"
echo "------------------------------------------------------------------------------------------------"

kubectl exec -it $PSQL_POD -- bash -c "
    export PGPASSWORD=\"\$POSTGRES_PASSWORD\";
    while true; do
        psql -U \"\$POSTGRES_USER\" -d 'pgbouncer' -h 'pgbouncer' -p 6432 -tA -c 'SHOW POOLS;' 2>/dev/null \
        | awk -F'|' '{ printf \" %-13s | %-9s | %-10s | %-9s | %-7s | %s\n\", \$1, \$3, \$4, \$5, \$7, \$10 }'

        echo '------------------------------------------------------------------------------------------------'
        sleep 2
    done
"

#!/bin/bash

echo "--- 🟢 Live Postgres Connection Monitor (Press Ctrl+C to stop) ---"

PG_POD=$(kubectl get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}')

if [ -z "$PG_POD" ]; then
    echo "❌ Postgres pod not found."
    exit 1
fi

echo "Pod: $PG_POD"
echo "---------------------------------------------------------------"
echo "TIME     | DB NAME       | STATE      | COUNT"
echo "---------------------------------------------------------------"

kubectl exec -it $PG_POD -- bash -c "
    export PGPASSWORD=\"\$POSTGRES_PASSWORD\";
    while true; do
        psql -U \"\$POSTGRES_USER\" -d postgres -tA -c \"
            SELECT to_char(now(), 'HH24:MI:SS') || ' | ' ||
                   d.datname || ' | ' ||
                   COALESCE(a.state, '---') || ' | ' ||
                   count(a.pid)
            FROM pg_database d
            LEFT JOIN pg_stat_activity a ON d.datname = a.datname AND a.pid <> pg_backend_pid()
            WHERE d.datistemplate = false
            GROUP BY d.datname, a.state
            ORDER BY d.datname;\"
        echo '---------------------------------------------------------------'
        sleep 2
    done
"

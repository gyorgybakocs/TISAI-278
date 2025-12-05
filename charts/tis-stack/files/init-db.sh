#!/bin/bash
set -e

echo "========================================================================"
echo "=> Starting dynamic database initialization & Citus Activation..."
echo "   Target Databases: $DB_LIST"
echo "========================================================================"

export PGPASSWORD="$POSTGRES_PASSWORD"

for db in $DB_LIST; do
    echo "   -> Checking/Creating database: $db"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
        SELECT 'CREATE DATABASE "$db"'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$db')\gexec
EOSQL

    echo "   -> ⚡ Activating Citus extension in: $db"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" <<-EOSQL
        CREATE EXTENSION IF NOT EXISTS citus;
EOSQL
done

echo "========================================================================"
echo "=> Initialization complete. / Citus is ready."
echo "========================================================================"

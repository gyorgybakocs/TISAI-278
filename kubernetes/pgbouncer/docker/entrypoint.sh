#!/bin/sh
set -e

# Set default values if not provided (useful for local testing)
export DB_HOST=${DB_HOST:-postgres-db}
export DB_PORT=${DB_PORT:-5432}
export DB_USER=${DB_USER:-postgres_user}
export DB_PASSWORD=${DB_PASSWORD:-password}
export DB_NAME=${DB_NAME:-langflow_db}
export LISTEN_PORT=${LISTEN_PORT:-6432}

# Substitute variables in templates to generate actual config files
# We explicitly output to the final configuration paths
envsubst < /etc/pgbouncer/userlist.txt.template > /etc/pgbouncer/userlist.txt
envsubst < /etc/pgbouncer/pgbouncer.ini.template > /etc/pgbouncer/pgbouncer.ini

# Start PgBouncer
exec "$@"

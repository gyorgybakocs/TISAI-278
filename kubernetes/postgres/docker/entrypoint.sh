#!/bin/sh
set -e

# Set default values if not provided (useful for local testing)
export MAX_CONNECTIONS=${MAX_CONNECTIONS:-150}
export MAX_PREPARED_TRANSACTIONS=${MAX_PREPARED_TRANSACTIONS:-150}
export SHARED_BUFFERS=${SHARED_BUFFERS:-8GB}
export EFFECTIVE_CACHE_SIZE=${EFFECTIVE_CACHE_SIZE:-24GB}
export WORK_MEM=${WORK_MEM:-24MB}
export MAINTENANCE_WORK_MEM=${MAINTENANCE_WORK_MEM:-1GB}
export MAX_WORKER_PROCESSES=${MAX_WORKER_PROCESSES:-16}
export MAX_PARALLEL_WORKERS=${MAX_PARALLEL_WORKERS:-16}

# Substitute variables in templates to generate actual config files
# We explicitly output to the final configuration paths
envsubst < /etc/postgresql/postgresql.conf.template > /etc/postgresql/postgresql.conf

# Start Postgres
# Hand off to the original Postgres docker entrypoint
exec /usr/local/bin/docker-entrypoint.sh "$@"

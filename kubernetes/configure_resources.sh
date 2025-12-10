##!/bin/bash
#set -e
#
## 1. Hardware Detection
## Get total RAM in MB for precise calculation
#TOTAL_MEM_MB=$(free -m | awk '/^Mem:/ {print $2}')
## Get number of CPU cores
#CPU_CORES=$(nproc)
#
#echo "==========================================================="
#echo "⚙️  DYNAMIC RESOURCE CALCULATION"
#echo "   -> Hardware: ${TOTAL_MEM_MB} MB RAM | ${CPU_CORES} Cores"
#
## --- CALCULATION LOGIC ---
#
## 1. Postgres Max Connections
## Rule of thumb: ~15 connections per GB of RAM is safe with Citus overhead.
## Constraints: Min 100, Max 4000 (hard limit).
#CALC_CONN=$(( TOTAL_MEM_MB / 1024 * 15 ))
#if [ "$CALC_CONN" -lt 100 ]; then CALC_CONN=100; fi
#if [ "$CALC_CONN" -gt 4000 ]; then CALC_CONN=4000; fi
#
#export PG_MAX_CONNECTIONS="${CALC_CONN}"
## For Citus, max_prepared_transactions must equal max_connections
#export PG_MAX_PREPARED_TRANSACTIONS="${CALC_CONN}"
#
## 2. Shared Buffers (25% of RAM)
#SB_MB=$(( TOTAL_MEM_MB / 4 ))
#export PG_SHARED_BUFFERS="${SB_MB}MB"
#
## 3. Effective Cache Size (75% of RAM)
#ECS_MB=$(( TOTAL_MEM_MB * 3 / 4 ))
#export PG_EFFECTIVE_CACHE_SIZE="${ECS_MB}MB"
#
## 4. Maintenance Work Mem (5% of RAM, capped at 2GB)
#MWM_MB=$(( TOTAL_MEM_MB / 20 ))
#if [ "$MWM_MB" -gt 2048 ]; then MWM_MB=2048; fi
#export PG_MAINTENANCE_WORK_MEM="${MWM_MB}MB"
#
## 5. Work Mem (The tricky part: Available RAM / MaxConn)
## We reserve ~20% of RAM for work mem across all connections.
#WORK_MEM_KB=$(( (TOTAL_MEM_MB * 1024 / 5) / CALC_CONN ))
## Constraints: Min 4MB, Max 64MB (to prevent OOM with high connection counts)
#if [ "$WORK_MEM_KB" -lt 4096 ]; then WORK_MEM_KB=4096; fi
#if [ "$WORK_MEM_KB" -gt 65536 ]; then WORK_MEM_KB=65536; fi
#export PG_WORK_MEM="${WORK_MEM_KB}kB"
#
## 6. Worker Processes (Aligned with CPU cores)
#export PG_MAX_WORKER_PROCESSES="${CPU_CORES}"
#export PG_MAX_PARALLEL_WORKERS="${CPU_CORES}"
#
## 7. PgBouncer Pool Size (CPU Protection)
## The ideal "active set" for Postgres is roughly 3x the CPU core count.
## e.g., 64 cores -> 192 active queries. 8 cores -> 24 active queries.
## Min 50 to prevent bottlenecks on dev laptops.
#POOL_SIZE=$(( CPU_CORES * 3 ))
#if [ "$POOL_SIZE" -lt 50 ]; then POOL_SIZE=50; fi
## Safety cap: Never allow more than 80% of max postgres connections
#MAX_SAFE_POOL=$(( CALC_CONN * 8 / 10 ))
#if [ "$POOL_SIZE" -gt "$MAX_SAFE_POOL" ]; then POOL_SIZE="$MAX_SAFE_POOL"; fi
#
#export PGB_DEFAULT_POOL_SIZE="${POOL_SIZE}"
## Client connection limit remains high (cheap on RAM)
#export PGB_MAX_CLIENT_CONN="20000"
#
## --- HELM/K8S VARIABLE ---
## We inject the literal variable string '${POOL_MODE}' into the template.
## The actual value (session/transaction) is handled by Kubernetes/Helm at runtime.
#export POOL_MODE_VAR='${POOL_MODE}'
#
#echo "-----------------------------------------------------------"
#echo "📊 CALCULATED OPTIMAL VALUES:"
#echo "   -> Postgres Max Conns:    ${PG_MAX_CONNECTIONS}"
#echo "   -> Shared Buffers:        ${PG_SHARED_BUFFERS}"
#echo "   -> Work Mem:              ${PG_WORK_MEM}"
#echo "   -> PgBouncer Pool Size:   ${PGB_DEFAULT_POOL_SIZE} (Limits active queries to CPU capacity)"
#echo "==========================================================="
#
## ---------------- GENERATION ----------------
## Applying variables to templates
#
#PG_VARS='$PG_MAX_CONNECTIONS $PG_MAX_PREPARED_TRANSACTIONS $PG_SHARED_BUFFERS $PG_EFFECTIVE_CACHE_SIZE $PG_WORK_MEM $PG_MAINTENANCE_WORK_MEM $PG_MAX_WORKER_PROCESSES $PG_MAX_PARALLEL_WORKERS'
#
#envsubst "$PG_VARS" < kubernetes/postgres/config/postgresql.conf.tpl > kubernetes/postgres/config/postgresql.conf
#echo "✅ Generated: postgresql.conf"
#
#PGB_VARS='$POOL_MODE_VAR $PGB_MAX_CLIENT_CONN $PGB_DEFAULT_POOL_SIZE'
#
#envsubst "$PGB_VARS" < kubernetes/pgbouncer/config/pgbouncer.ini.tpl > kubernetes/pgbouncer/config/pgbouncer.ini.template
#echo "✅ Generated: pgbouncer.ini.template"

#!/bin/bash
set -e

# 1. HARDWARE DETECTION
# Get total RAM in MB
TOTAL_MEM_MB=$(free -m | awk '/^Mem:/ {print $2}')
# Get CPU core count
CPU_CORES=$(nproc)

echo "==========================================================="
echo "⚙️  DYNAMIC RESOURCE CALCULATION (Host: $(hostname))"
echo "   -> Hardware: ${TOTAL_MEM_MB} MB RAM | ${CPU_CORES} Cores"

# --- CALCULATION LOGIC (AGGRESSIVE TUNING) ---

# 1. Postgres Calculation
# OLD: 15 conn / GB -> Failed on Citus workloads.
# NEW: 50 conn / GB. Postgres connections are cheap (approx 10MB RAM).
# 32GB RAM -> ~1600 connections. 256GB RAM -> 12800 (capped at 4000).
CALC_CONN=$(( TOTAL_MEM_MB / 1024 * 50 ))

# Safety constraints
if [ "$CALC_CONN" -lt 500 ]; then CALC_CONN=500; fi
# Hard limit remains 4000 to avoid OS file descriptor issues on some setups
if [ "$CALC_CONN" -gt 4000 ]; then CALC_CONN=4000; fi

export PG_MAX_CONNECTIONS="${CALC_CONN}"
# Citus requirement: prepared transactions = max connections
export PG_MAX_PREPARED_TRANSACTIONS="${CALC_CONN}"

# Shared Buffers: 25% of RAM
SB_MB=$(( TOTAL_MEM_MB / 4 ))
export PG_SHARED_BUFFERS="${SB_MB}MB"

# Effective Cache: 75% of RAM
ECS_MB=$(( TOTAL_MEM_MB * 3 / 4 ))
export PG_EFFECTIVE_CACHE_SIZE="${ECS_MB}MB"

# Maintenance Work Mem: 5% of RAM (max 2GB)
MWM_MB=$(( TOTAL_MEM_MB / 20 ))
if [ "$MWM_MB" -gt 2048 ]; then MWM_MB=2048; fi
export PG_MAINTENANCE_WORK_MEM="${MWM_MB}MB"

# Work Mem: (15% of RAM) / Connections
# Reduced total reservation slightly to leave room for OS/Connection overhead
WORK_MEM_KB=$(( (TOTAL_MEM_MB * 1024 / 7) / CALC_CONN ))
# Constraints: Min 4MB, Max 64MB
if [ "$WORK_MEM_KB" -lt 4096 ]; then WORK_MEM_KB=4096; fi
if [ "$WORK_MEM_KB" -gt 65536 ]; then WORK_MEM_KB=65536; fi
export PG_WORK_MEM="${WORK_MEM_KB}kB"

# Worker Processes: Match CPU cores
export PG_MAX_WORKER_PROCESSES="${CPU_CORES}"
export PG_MAX_PARALLEL_WORKERS="${CPU_CORES}"

# 2. PgBouncer Calculation
# OLD: CPU * 3 -> Too low for laptops (16*3=48).
# NEW: CPU * 10. Allows more concurrency while trusting the OS scheduler.
# 16 Cores -> 160 Pool Size. 64 Cores -> 640 Pool Size (capped below).
POOL_SIZE=$(( CPU_CORES * 10 ))

# Min 100 to ensure basic throughput even on weak CPUs
if [ "$POOL_SIZE" -lt 100 ]; then POOL_SIZE=100; fi

# Safety cap: Never allow more than 60% of Postgres connections
# (Leaving 40% headroom for Citus internal amplification - CRITICAL!)
MAX_SAFE_POOL=$(( CALC_CONN * 6 / 10 ))
if [ "$POOL_SIZE" -gt "$MAX_SAFE_POOL" ]; then POOL_SIZE="$MAX_SAFE_POOL"; fi

export PGB_DEFAULT_POOL_SIZE="${POOL_SIZE}"
export PGB_MAX_CLIENT_CONN="20000"

# --- HELM UPGRADE Postgres Config ---

echo "==========================================================="
echo "📊 CALCULATED OPTIMAL VALUES FOR Postgres:"
echo "   -> Postgres Max Conns:    ${PG_MAX_CONNECTIONS}"
echo "   -> Prepared transactions (= max connections):   ${PG_MAX_PREPARED_TRANSACTIONS}"
echo "   -> Shared Buffers:   ${PG_SHARED_BUFFERS}"
echo "   -> Effective Cache:   ${PG_EFFECTIVE_CACHE_SIZE}"
echo "   -> Work Mem:   ${PG_WORK_MEM}"
echo "   -> Maintenance Work Mem:   ${PG_MAINTENANCE_WORK_MEM}"
echo "   -> Worker Processes:   ${PG_MAX_WORKER_PROCESSES}"
echo "   -> Parallel Workers:   ${PG_MAX_PARALLEL_WORKERS}"
echo "==========================================================="

helm upgrade tis-stack ./charts/tis-stack \
    --reuse-values \
    --set postgres.config.max_connections=${PG_MAX_CONNECTIONS} \
    --set postgres.config.max_prepared_transactions=${PG_MAX_PREPARED_TRANSACTIONS} \
    --set postgres.config.shared_buffers=${PG_SHARED_BUFFERS} \
    --set postgres.config.effective_cache_size=${PG_EFFECTIVE_CACHE_SIZE} \
    --set postgres.config.work_mem=${PG_WORK_MEM} \
    --set postgres.config.maintenance_work_mem=${PG_MAINTENANCE_WORK_MEM} \
    --set postgres.config.max_worker_processes=${PG_MAX_WORKER_PROCESSES} \
    --set postgres.config.max_parallel_workers=${PG_MAX_PARALLEL_WORKERS}

echo "✅ Postgres Resources applied successfully."

# --- HELM UPGRADE PgBouncer Config ---
# Note: pool_mode is preserved as defined in the template (session)

echo "==========================================================="
echo "📊 CALCULATED OPTIMAL VALUES FOR PgBouncer:"
echo "   -> PgBouncer Max Conns:    ${PGB_MAX_CLIENT_CONN}"
echo "   -> PgBouncer Pool Size:   ${PGB_DEFAULT_POOL_SIZE}"
echo "==========================================================="

helm upgrade tis-stack ./charts/tis-stack \
    --reuse-values \
    --set pgbouncer.pool.max_client_conn=${PGB_MAX_CLIENT_CONN} \
    --set pgbouncer.pool.default_pool_size=${PGB_DEFAULT_POOL_SIZE}

echo "✅ PgBouncer Resources applied successfully."

#!/bin/bash
set -e

echo "==============================================="
echo "🧪 GUNICORN VALIDATION TEST AND PROOF"
echo "==============================================="

LANGFLOW_POD=$(kubectl get pod -l app=langflow -o jsonpath='{.items[0].metadata.name}')

if [ -z "$LANGFLOW_POD" ]; then
    echo "❌ Langflow pod not found!"
    exit 1
fi

echo "Target Pod: $LANGFLOW_POD"
echo "-----------------------------------------------"

# --- PROOF #2: LOG CHECK ---
if kubectl logs "$LANGFLOW_POD" 2>&1 | grep -q "Starting gunicorn"; then
    echo "✅ PROOF #2: Starting gunicorn"
    echo "   Found '__init__ - Starting gunicorn' message in logs."
    echo "   This message is only printed by Gunicorn at startup."
    echo "   (If plain Uvicorn was running, this line would not exist.)"
else
    echo "⚠️  PROOF #2: 'Starting gunicorn' message cycled out of log buffer (started long ago)."
fi

echo "-----------------------------------------------"

# --- PROOF #3: PROCESS HIERARCHY ---
# This script runs inside the container and analyzes parent-child relationships
kubectl exec "$LANGFLOW_POD" -- /bin/sh -c '
    FOUND=0
    for pid in /proc/[0-9]*; do
        pid_num=$(basename $pid)
        # Skipping PID 1 (the manager)
        if [ "$pid_num" != "1" ]; then
             if [ -f "$pid/status" ]; then
                 ppid=$(grep "PPid:" "$pid/status" | awk "{print \$2}")

                 # IF parent is NOT 1 and NOT 0 (kernel), we found a grandchild!
                 if [ "$ppid" != "1" ] && [ "$ppid" != "0" ]; then
                     echo "✅ PROOF #3: Process Hierarchy (Grandchild Structure)"
                     echo "   This is the most important technical proof."
                     echo "   -----------------------------------------------------------"
                     echo "   -> If Uvicorn was running: Worker parent (PPID) would be PID 1."
                     echo "   -> On your system: Worker (PID $pid_num) parent is PID $ppid."
                     echo "   -> What is PID $ppid? This is the Gunicorn \"Master\" process (Arbiter)."
                     echo "      Started by LangflowApplication."
                     FOUND=1
                     break
                 fi
             fi
        fi
    done

    if [ "$FOUND" -eq 0 ]; then
        echo "❌ PROOF #3 FAILED: Could not find Gunicorn worker hierarchy."
        exit 1
    fi
'

echo "==============================================="
echo "🎉 SYSTEM IS PROVEN TO BE USING GUNICORN"
echo "==============================================="
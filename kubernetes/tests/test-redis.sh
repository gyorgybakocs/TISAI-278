#!/bin/bash
set -e

echo "==============================================="
echo "🧪 TESTING REDIS FUNCTIONALITY"
echo "==============================================="

REDIS_POD=$(kubectl get pod -l app=redis -o jsonpath='{.items[0].metadata.name}')

if [ -z "$REDIS_POD" ]; then
    echo "❌ Redis pod not found!"
    exit 1
fi

echo "Target Pod: $REDIS_POD"

echo -n "-> Writing key 'smoke_test_key' ... "
kubectl exec $REDIS_POD -- redis-cli -a redissecret set smoke_test_key "WORKS_PERFECTLY" > /dev/null
echo "✅ OK"

echo -n "-> Reading key 'smoke_test_key' ... "
RESULT=$(kubectl exec $REDIS_POD -- redis-cli -a redissecret get smoke_test_key)

if [ "$RESULT" == "WORKS_PERFECTLY" ]; then
    echo "✅ OK (Value: $RESULT)"
else
    echo "❌ FAILED (Expected: WORKS_PERFECTLY, Got: $RESULT)"
    exit 1
fi

echo -n "-> Deleting key ... "
kubectl exec $REDIS_POD -- redis-cli -a redissecret del smoke_test_key > /dev/null
echo "✅ OK"

echo "-----------------------------------------------"
echo "🎉 REDIS TEST PASSED!"
echo "==============================================="

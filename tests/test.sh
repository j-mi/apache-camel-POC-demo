#!/usr/bin/env bash
# Smoke tests for /process and /users.
# Usage:
#   BASE=http://localhost:8080 ./tests/test.sh           # default mode, JSONMOCKDB off
#   JSONMOCKDB=true ./tests/test.sh                       # also exercise the gate
set -u
BASE="${BASE:-http://localhost:8080}"
PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "PASS  $name (http $actual)"
    PASS=$((PASS+1))
  else
    echo "FAIL  $name — expected $expected, got $actual"
    FAIL=$((FAIL+1))
  fi
}

echo "Target: $BASE"
echo "JSONMOCKDB client-side override: ${JSONMOCKDB:-unset}"
echo

# ----- core /process tests -----
code=$(curl -s -o /tmp/r1.json -w "%{http_code}" -X POST "$BASE/process" \
  -H "Content-Type: application/json" \
  -d '{"name":"Teemu","city":"Turku"}')
if [[ "${JSONMOCKDB:-false}" == "true" ]]; then
  check "JSONMOCKDB on: Teemu/Turku unregistered -> 404" "404" "$code"
else
  check "happy path Turku" "200" "$code"
  echo "      body: $(cat /tmp/r1.json)"
fi

code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/process" \
  -H "Content-Type: application/json" \
  -d '{"name":"Teemu"}')
check "missing city -> 400" "400" "$code"

code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/process" \
  -H "Content-Type: application/json" \
  -d '{"name":"","city":"Turku"}')
check "empty name -> 400" "400" "$code"

# Unknown city only behaves as fallback when the gate isn't blocking
if [[ "${JSONMOCKDB:-false}" != "true" ]]; then
  code=$(curl -s -o /tmp/r4.json -w "%{http_code}" -X POST "$BASE/process" \
    -H "Content-Type: application/json" \
    -d '{"name":"Pekka","city":"Atlantis"}')
  check "unknown city -> 200 (fallback)" "200" "$code"
fi

# ----- /users tests -----
code=$(curl -s -o /tmp/u1.json -w "%{http_code}" -X POST "$BASE/users" \
  -H "Content-Type: application/json" \
  -d '{"name":"Teemu","city":"Turku"}')
check "register user Teemu/Turku" "200" "$code"
echo "      body: $(cat /tmp/u1.json)"

code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/users" \
  -H "Content-Type: application/json" \
  -d '{"name":""}')
check "register invalid -> 400" "400" "$code"

code=$(curl -s -o /tmp/u2.json -w "%{http_code}" "$BASE/users")
check "list users" "200" "$code"
echo "      body: $(cat /tmp/u2.json)"

# ----- gate behaviour -----
if [[ "${JSONMOCKDB:-false}" == "true" ]]; then
  code=$(curl -s -o /tmp/g1.json -w "%{http_code}" -X POST "$BASE/process" \
    -H "Content-Type: application/json" \
    -d '{"name":"Teemu","city":"Turku"}')
  check "JSONMOCKDB on: Teemu/Turku now registered -> 200" "200" "$code"
  echo "      body: $(cat /tmp/g1.json)"
fi

# ----- platform endpoints -----
code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/health")
check "health" "200" "$code"

code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/openapi.json")
check "openapi spec" "200" "$code"

echo
echo "Result: $PASS passed, $FAIL failed"
exit $FAIL

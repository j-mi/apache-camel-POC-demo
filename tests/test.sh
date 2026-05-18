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

# Assert that $file contains a JSON key like  "<field>":  with a value present.
has_field() {
  local label="$1" file="$2" field="$3"
  if grep -Eq "\"$field\"[[:space:]]*:[[:space:]]*[^,}[:space:]]" "$file"; then
    check "$label body has '$field'" "yes" "yes"
  else
    check "$label body has '$field'" "yes" "no"
  fi
}

# Assert that the numeric JSON value for $field in $file is "close to" $expected (within $tolerance).
# Only meaningful for /process responses where we control the input city.
near_number() {
  local label="$1" file="$2" field="$3" expected="$4" tolerance="$5"
  # grep out: "field": 60.45...  (capture the number)
  local val
  val=$(grep -Eo "\"$field\"[[:space:]]*:[[:space:]]*-?[0-9]+\.?[0-9]*" "$file" | grep -Eo '\-?[0-9]+\.?[0-9]*$' | head -1)
  if [[ -z "$val" ]]; then
    check "$label '$field' ~= $expected" "ok" "missing"
    return
  fi
  # awk: |val - expected| <= tolerance
  if awk -v v="$val" -v e="$expected" -v t="$tolerance" 'BEGIN{ d=v-e; if (d<0) d=-d; exit !(d<=t) }'; then
    check "$label '$field' ~= $expected (got $val)" "ok" "ok"
  else
    check "$label '$field' ~= $expected (got $val)" "ok" "out-of-tolerance"
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
  # Combined response must include location AND weather
  has_field "happy path Turku" /tmp/r1.json latitude
  has_field "happy path Turku" /tmp/r1.json longitude
  has_field "happy path Turku" /tmp/r1.json currentTemperature
  has_field "happy path Turku" /tmp/r1.json time
  has_field "happy path Turku" /tmp/r1.json requestId
  has_field "happy path Turku" /tmp/r1.json timestamp
  # Geocoded coords for Turku land around (60.45, 22.27)
  near_number "happy path Turku" /tmp/r1.json latitude  60.45 0.2
  near_number "happy path Turku" /tmp/r1.json longitude 22.27 0.2
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
    -d '{"name":"Ghost","city":"AsdfQwertyXyz"}')
  check "unknown city -> 200 (Helsinki fallback)" "200" "$code"
  # Fallback should yield Helsinki coordinates
  has_field "fallback" /tmp/r4.json latitude
  has_field "fallback" /tmp/r4.json longitude
  near_number "fallback" /tmp/r4.json latitude  60.17 0.2
  near_number "fallback" /tmp/r4.json longitude 24.94 0.2
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
  has_field "JSONMOCKDB pass" /tmp/g1.json latitude
  has_field "JSONMOCKDB pass" /tmp/g1.json longitude
  has_field "JSONMOCKDB pass" /tmp/g1.json currentTemperature
fi

# ----- platform endpoints -----
code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/health")
check "health" "200" "$code"

code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/openapi.json")
check "openapi spec" "200" "$code"

echo
echo "Result: $PASS passed, $FAIL failed"
exit $FAIL

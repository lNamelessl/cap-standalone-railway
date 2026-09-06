#!/usr/bin/env bash
# Fresh-deploy N times: new Railway project, valkey + cap images, volume, domain,
# then prove the widget round-trip (login -> create site key -> challenge/solve/redeem/verify).
set -u
WS=95648bee-39e6-4d34-a968-01e18ac0a348
N=${1:-1}
export MSYS_NO_PATHCONV=1

for i in $(seq 1 "$N"); do
  NAME="cap-fresh-$i-$(date +%s)"
  echo "=== fresh deploy $i: $NAME ==="
  railway init --name "$NAME" --workspace "$WS" >/dev/null 2>&1 || { echo "init FAIL"; exit 1; }
  sleep 5
  PROJID=$(railway status 2>/dev/null | grep -oE 'Project ID:\s+[0-9a-f-]{36}' | grep -oE '[0-9a-f-]{36}')
  [ -n "$PROJID" ] || { echo "FAIL: no project id"; exit 1; }

  printf '\n\n\n' | railway add -s valkey -i valkey/valkey:9-alpine -v VALKEY_DATA=/data >/dev/null 2>&1
  AK=$(openssl rand -hex 24)
  printf '\n\n\n' | railway add -s cap -i tiago2/cap:3.1.11 -v ADMIN_KEY="$AK" -v REDIS_URL=redis://valkey.railway.internal:6379 >/dev/null 2>&1

  railway link -p "$PROJID" -s valkey >/dev/null 2>&1
  railway volume add -m /data >/dev/null 2>&1

  railway link -p "$PROJID" -s cap >/dev/null 2>&1
  CAPID=$(railway status 2>/dev/null | grep -oE 'service ID:\s+[0-9a-f-]{36}' | grep -oE '[0-9a-f-]{36}' | head -1)
  ENVID=$(railway status --json 2>/dev/null | grep -oE '"id": *"[0-9a-f-]{36}"' | head -1 | grep -oE '[0-9a-f-]{36}')
  [ -n "$CAPID" ] && railway api "mutation { serviceInstanceUpdate(serviceId: \"$CAPID\", environmentId: \"$ENVID\", input: { healthcheckPath: \"/\", healthcheckTimeout: 300 }) }" >/dev/null 2>&1

  railway domain --service cap >/dev/null 2>&1
  DOMID=$(railway domain list --service cap 2>/dev/null | grep -oE '[0-9a-f-]{36}' | head -1)
  railway domain update "$DOMID" --port 3000 --service cap >/dev/null 2>&1
  DOMAIN=$(railway domain list --service cap 2>/dev/null | grep -oE '[a-z0-9-]+\.up\.railway\.app' | head -1)
  echo "domain: $DOMAIN"
  [ -n "$DOMAIN" ] || { echo "FAIL: no domain"; exit 1; }

  ok=0
  for t in $(seq 1 40); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/" 2>/dev/null)
    [ "$code" = "200" ] && { ok=1; break; }; sleep 10
  done
  [ "$ok" = 1 ] || { echo "deploy $i FAIL: dashboard never returned 200"; exit 1; }

  BASE="https://$DOMAIN"
  LOGIN=$(curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' -d "{\"admin_key\":\"$AK\"}")
  ST=$(echo "$LOGIN" | grep -oE '"session_token":"[^"]*"' | cut -d'"' -f4)
  HT=$(echo "$LOGIN" | grep -oE '"hashed_token":"[^"]*"' | cut -d'"' -f4)
  AUTH=$(printf '{"token":"%s","hash":"%s"}' "$ST" "$HT" | base64 -w0)
  KEYS=$(curl -s -X POST "$BASE/server/keys" -H "Authorization: Bearer $AUTH" -H 'Content-Type: application/json' -d '{"name":"fresh-deploy-check"}')
  SK=$(echo "$KEYS" | grep -oE '"siteKey":"[^"]*"' | cut -d'"' -f4)
  SEC=$(echo "$KEYS" | grep -oE '"secretKey":"[^"]*"' | cut -d'"' -f4)
  if [ -z "$SK" ] || [ -z "$SEC" ]; then echo "deploy $i FAIL: site key creation failed: $KEYS"; exit 1; fi

  if node scripts/roundtrip.mjs "$BASE" "$SK" "$SEC"; then
    echo "=== fresh deploy $i PASS ==="
  else
    echo "=== fresh deploy $i FAIL: round-trip ==="; exit 1
  fi
done
echo "ALL $N FRESH DEPLOYS PASSED"

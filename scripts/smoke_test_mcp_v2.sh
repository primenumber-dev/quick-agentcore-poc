#!/usr/bin/env bash
# Smoke test for the MCP protocol v2 (2026-07-28) spike (feature/mcp-protocol-v2-spike).
# Verifies both legacy (2025-11-25, `initialize` handshake) and modern
# (2026-07-28, `_meta` envelope) clients are served by the same
# createMcpHandler endpoint, plus the auth gate and legacy GET/DELETE 405s.
#
# Prerequisites: server running locally against LocalStack DynamoDB, e.g.
#   docker compose up -d localstack
#   AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws dynamodb put-item \
#     --table-name quick-mcp-poc-users --endpoint-url http://localhost:4566 --region ap-northeast-1 \
#     --item '{"PK":{"S":"USER#smoke-test-sub"},"services":{"M":{"quick":{"M":{"plan":{"S":"standard"}}}}}}'
#   cd server && DYNAMODB_ENDPOINT_URL=http://localhost:4566 npm run dev
#
# Usage: MCP_BASE_URL=http://localhost:8000 MCP_TEST_SUB=smoke-test-sub ./scripts/smoke_test_mcp_v2.sh

set -euo pipefail

BASE_URL="${MCP_BASE_URL:-http://localhost:8000}"
SUB="${MCP_TEST_SUB:-smoke-test-sub}"
FAIL=0

jwt() {
  python3 -c "
import base64, json
def b64url(d):
    return base64.urlsafe_b64encode(json.dumps(d).encode()).rstrip(b'=').decode()
print(f\"{b64url({'alg':'none','typ':'JWT'})}.{b64url({'sub':'$SUB'})}.sig\")
"
}

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name (HTTP $actual)"
  else
    echo "FAIL: $name (expected HTTP $expected, got $actual)"
    FAIL=1
  fi
}

JWT="$(jwt)"

status=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/health")
check "GET /health" 200 "$status"

status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}')
check "POST /mcp without auth -> 401" 401 "$status"

status=$(curl -s -o /dev/null -w '%{http_code}' -X GET "$BASE_URL/mcp")
check "GET /mcp -> 405 (legacy session op unsupported)" 405 "$status"

status=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$BASE_URL/mcp")
check "DELETE /mcp -> 405 (legacy session op unsupported)" 405 "$status"

body=$(curl -s -X POST "$BASE_URL/mcp" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"legacy-smoke-client","version":"1.0.0"}}}')
if echo "$body" | grep -q '"protocolVersion":"2025-11-25"'; then
  echo "PASS: legacy initialize handshake (2025-11-25)"
else
  echo "FAIL: legacy initialize handshake — got: $body"
  FAIL=1
fi

body=$(curl -s -X POST "$BASE_URL/mcp" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}')
if echo "$body" | grep -q '"name":"get_quote"'; then
  echo "PASS: legacy tools/list returns get_quote"
else
  echo "FAIL: legacy tools/list — got: $body"
  FAIL=1
fi

body=$(curl -s -X POST "$BASE_URL/mcp" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: tools/list" \
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}')
if echo "$body" | grep -q '"name":"get_quote"'; then
  echo "PASS: modern (2026-07-28) _meta-envelope tools/list returns get_quote"
else
  echo "FAIL: modern tools/list — got: $body"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  echo "--- SMOKE TEST FAILED ---"
  exit 1
fi
echo "--- ALL SMOKE TESTS PASSED ---"

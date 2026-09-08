"""MCP基本機能の自動テストスイート。

quick-mcp-poc PoCの4つのホスティング環境(ECS/AgentCore Runtime × MCP SDK v1/v2)に対して、
initialize・tools/list・tools/call・エラーハンドリング・MCPプロトコルv2形式(_metaエンベロープ)
対応状況を横断的に検証する。docs/16-weekly-verification-report-week3.md・
docs/17-environment-resource-map.mdの検証内容を、再現可能な自動テストとして固定化したもの。

使い方:
  export MCP_ECS_TOKEN='<pattern4向けclient_credentialsトークン>'
  export MCP_AGENTCORE_TOKEN='<agentcore-mcp-pool向けclient_credentialsトークン>'
  python3 scripts/mcp_functional_tests.py

トークンの取得方法は、それぞれ以下を参照:
  - ECS側(pattern4): POST https://2a5r57wfoa.execute-api.ap-northeast-1.amazonaws.com/register
    でDCR自己登録し、DynamoDB quick-mcp-poc-usersにUSER#<client_id>を追加(admin承認)した上で
    client_credentialsトークンを取得する(web-demoのDCRデモと同じ手順)
  - AgentCore側: quick-mcp-poc-m2m-testクライアント(既存、USER#レコード登録済み)の
    client_credentialsトークン

対象:
  - v1-ECS:  pattern4 API Gateway経由、quick-mcp-poc-cluster/app(v1 SDK)
  - v2-ECS:  quick-mcp-poc-v2-sdk-demoサービスへの直接アクセス(v2 SDK、テスト専用)
  - v1-AgentCore: quickMcpPocLatencyLab Runtime(v1 SDK)
  - v2-AgentCore: quickMcpPocV2SdkDemo Runtime(v2 SDK)
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

CLOUDFRONT_BASE = "https://d22imwd0soxmb2.cloudfront.net"
LATENCY_LAB_ARN = "arn:aws:bedrock-agentcore:ap-northeast-1:883660531246:runtime/quickMcpPocLatencyLab-uC4Wd7EOWj"
V2_SDK_DEMO_ARN = "arn:aws:bedrock-agentcore:ap-northeast-1:883660531246:runtime/quickMcpPocV2SdkDemo-lxkNuS7moU"
ECS_API_GATEWAY_BASE = "https://2a5r57wfoa.execute-api.ap-northeast-1.amazonaws.com"
ECS_V2_DIRECT_BASE = os.environ.get("MCP_ECS_V2_DIRECT_BASE", "http://43.206.152.174:3000")

EXPECTED_TOOLS = {
    "get_quote",
    "get_price_history",
    "get_intraday_history",
    "get_ranking",
    "search_news",
    "search_stocks",
}


def http_post(url, headers, body_dict, timeout=30):
    payload = json.dumps(body_dict).encode()
    req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            text = resp.read().decode()
            return resp.status, text, dict(resp.headers)
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        return e.code, text, dict(e.headers)
    except Exception as e:  # noqa: BLE001 - want to surface connection errors as test failures, not crashes
        return None, str(e), {}


def parse_mcp_body(text):
    """SSE形式("event: message\\ndata: {...}")と素のJSONの両方に対応してパースする。"""
    if text is None:
        return None
    data_line = next((line for line in text.split("\n") if line.startswith("data: ")), None)
    json_text = data_line[len("data: "):] if data_line else text
    try:
        return json.loads(json_text)
    except (json.JSONDecodeError, TypeError):
        return None


class Target:
    def __init__(self, name, base_url_or_arn, token, kind):
        self.name = name
        self.base_url_or_arn = base_url_or_arn
        self.token = token
        self.kind = kind  # "agentcore" or "http"

    def call(self, method, params, session_id=None, modern=False, auth=True):
        headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
        if auth:
            headers["Authorization"] = f"Bearer {self.token}"
        if session_id:
            headers["Mcp-Session-Id"] = session_id
        if modern:
            headers["MCP-Protocol-Version"] = "2026-07-28"
            headers["Mcp-Method"] = method
            params = {
                **params,
                "_meta": {
                    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
                    "io.modelcontextprotocol/clientCapabilities": {},
                },
            }

        if self.kind == "agentcore":
            encoded_arn = urllib.parse.quote(self.base_url_or_arn, safe="")
            url = f"{CLOUDFRONT_BASE}/runtimes/{encoded_arn}/invocations?qualifier=DEFAULT"
        else:
            url = f"{self.base_url_or_arn}/mcp"

        status, text, resp_headers = http_post(url, headers, {"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
        body = parse_mcp_body(text)
        return {
            "status": status,
            "raw_text": text,
            "body": body,
            "session_id": resp_headers.get("mcp-session-id"),
        }


class TestResult:
    def __init__(self, name):
        self.name = name
        self.passed = None
        self.detail = ""

    def ok(self, detail=""):
        self.passed = True
        self.detail = detail
        return self

    def fail(self, detail=""):
        self.passed = False
        self.detail = detail
        return self


def test_unauthenticated(target):
    r = target.call("tools/list", {}, auth=False)
    if r["status"] in (401, 403):
        return TestResult("unauthenticated_rejected").ok(f"HTTP {r['status']}")
    return TestResult("unauthenticated_rejected").fail(f"expected 401/403, got HTTP {r['status']}: {r['raw_text'][:200]}")


def test_initialize_classic(target):
    r = target.call(
        "initialize",
        {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "mcp-functional-tests", "version": "1.0.0"}},
    )
    body = r["body"]
    if body and "result" in body and body["result"].get("serverInfo", {}).get("name"):
        return TestResult("initialize_classic").ok(f"serverInfo.name={body['result']['serverInfo']['name']}, protocolVersion={body['result'].get('protocolVersion')}")
    return TestResult("initialize_classic").fail(f"HTTP {r['status']}: {r['raw_text'][:300]}")


def test_tools_list_classic(target):
    r = target.call("tools/list", {})
    body = r["body"]
    if not body or "result" not in body:
        return TestResult("tools_list_classic").fail(f"HTTP {r['status']}: {r['raw_text'][:300]}")
    names = {t["name"] for t in body["result"].get("tools", [])}
    missing = EXPECTED_TOOLS - names
    if missing:
        return TestResult("tools_list_classic").fail(f"missing tools: {missing} (got {names})")
    no_schema = [t["name"] for t in body["result"]["tools"] if not t.get("inputSchema")]
    if no_schema:
        return TestResult("tools_list_classic").fail(f"tools without inputSchema: {no_schema}")
    return TestResult("tools_list_classic").ok(f"{len(names)} tools, all with inputSchema")


def test_tools_call_invalid_args(target):
    r = target.call("tools/call", {"name": "get_quote", "arguments": {"QCs": [], "ECs": ["NOT_A_VALID_EC"]}})
    body = r["body"]
    if body and "result" in body and body["result"].get("isError") is True:
        return TestResult("tools_call_invalid_args").ok("isError=true with validation message")
    if body and "error" in body:
        return TestResult("tools_call_invalid_args").ok(f"top-level JSON-RPC error: {body['error'].get('message', '')[:100]}")
    return TestResult("tools_call_invalid_args").fail(f"expected a validation failure, got HTTP {r['status']}: {r['raw_text'][:300]}")


def test_tools_call_unknown_tool(target):
    r = target.call("tools/call", {"name": "this_tool_does_not_exist", "arguments": {}})
    body = r["body"]
    if body and "result" in body and body["result"].get("isError") is True:
        return TestResult("tools_call_unknown_tool").ok("isError=true (result-level)")
    if body and "error" in body:
        return TestResult("tools_call_unknown_tool").ok(f"top-level JSON-RPC error code={body['error'].get('code')}")
    return TestResult("tools_call_unknown_tool").fail(f"expected a failure signal, got HTTP {r['status']}: {r['raw_text'][:300]}")


def test_unknown_method(target):
    r = target.call("this/method/does/not/exist", {})
    body = r["body"]
    if body and "error" in body and body["error"].get("code") == -32601:
        return TestResult("unknown_method").ok("JSON-RPC -32601 Method not found")
    if body and "error" in body:
        return TestResult("unknown_method").ok(f"JSON-RPC error (code={body['error'].get('code')}, not -32601 but still an error)")
    return TestResult("unknown_method").fail(f"expected a JSON-RPC error, got HTTP {r['status']}: {r['raw_text'][:300]}")


def test_ping(target):
    r = target.call("ping", {})
    body = r["body"]
    if body and "result" in body:
        return TestResult("ping").ok("result received")
    if body and "error" in body:
        return TestResult("ping").fail(f"ping returned an error: {body['error']}")
    return TestResult("ping").fail(f"HTTP {r['status']}: {r['raw_text'][:200]}")


def test_modern_request(target, expect_supported):
    r = target.call("tools/list", {}, modern=True)
    body = r["body"]
    succeeded = bool(body and "result" in body and body["result"].get("tools"))
    if succeeded == expect_supported:
        label = "supported as expected" if expect_supported else "rejected as expected"
        return TestResult("modern_v2_request").ok(f"{label} (HTTP {r['status']})")
    detail = f"expected supported={expect_supported}, got succeeded={succeeded} (HTTP {r['status']}): {r['raw_text'][:300]}"
    return TestResult("modern_v2_request").fail(detail)


def run_all(target, expect_modern_supported):
    tests = [
        test_unauthenticated(target),
        test_initialize_classic(target),
        test_tools_list_classic(target),
        test_tools_call_invalid_args(target),
        test_tools_call_unknown_tool(target),
        test_unknown_method(target),
        test_ping(target),
        test_modern_request(target, expect_modern_supported),
    ]
    return tests


def main():
    ecs_token = os.environ.get("MCP_ECS_TOKEN")
    agentcore_token = os.environ.get("MCP_AGENTCORE_TOKEN")
    if not ecs_token or not agentcore_token:
        sys.exit("環境変数 MCP_ECS_TOKEN と MCP_AGENTCORE_TOKEN を設定してください(スクリプト冒頭のdocstring参照)")

    targets = [
        (Target("v1-ECS(pattern4, API Gateway経由)", ECS_API_GATEWAY_BASE, ecs_token, "http"), False),
        (Target("v2-ECS(quick-mcp-poc-v2-sdk-demo, 直接)", ECS_V2_DIRECT_BASE, ecs_token, "http"), True),
        (Target("v1-AgentCore(quickMcpPocLatencyLab)", LATENCY_LAB_ARN, agentcore_token, "agentcore"), False),
        (Target("v2-AgentCore(quickMcpPocV2SdkDemo)", V2_SDK_DEMO_ARN, agentcore_token, "agentcore"), True),
    ]

    all_results = {}
    for target, expect_modern in targets:
        print(f"\n=== {target.name} ===")
        results = run_all(target, expect_modern)
        all_results[target.name] = results
        for r in results:
            status = "PASS" if r.passed else "FAIL"
            print(f"  [{status}] {r.name}: {r.detail}")

    print("\n\n=== サマリ(行=テスト、列=環境) ===")
    test_names = [r.name for r in next(iter(all_results.values()))]
    header = "test".ljust(28) + "".join(name[:20].ljust(22) for name in all_results.keys())
    print(header)
    for i, tn in enumerate(test_names):
        row = tn.ljust(28)
        for target_name in all_results:
            mark = "PASS" if all_results[target_name][i].passed else "FAIL"
            row += mark.ljust(22)
        print(row)

    total = sum(len(v) for v in all_results.values())
    passed = sum(1 for v in all_results.values() for r in v if r.passed)
    print(f"\n{passed}/{total} tests passed across {len(all_results)} targets")
    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()

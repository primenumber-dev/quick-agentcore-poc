"""DCR(RFC 7591)/ 認可サーバーメタデータ(RFC 8414)/ 保護リソースメタデータ(RFC 9728)/
MCP Authorization 仕様に対する準拠性テスト。

Claude Code / Claude.ai の内部挙動に依存せず、標準に沿った独立クライアントとして
pattern4(ECS + API Gateway)のDCR実装を検査する。各テストは
docs/20-internal-production-readiness-checklist.md の固定ID(7591-01 等)に対応し、結果を
チェックリストへ転記できるJSONで出力する。

使い方:
  # discovery + DCR正常系/異常系(ブラウザ不要、AWS書き込みはDCR登録のみ)
  python3 scripts/dcr_conformance_tests.py --report docs/evidence/$(date +%F)-dcr.json

  # 作成したテストクライアントを削除して終了(AWS CLI、playgroundプロファイル)
  python3 scripts/dcr_conformance_tests.py --cleanup

  # 認可コード + PKCE フロー(ブラウザでログインが必要。resource/aud/iss/scope を記録)
  python3 scripts/dcr_conformance_tests.py --auth-code --report ...

  # 期限切れトークンでの応答コード確認(MCP-04)
  MCP_EXPIRED_TOKEN='<1時間以上前のアクセストークン>' python3 scripts/dcr_conformance_tests.py --id MCP-04

  # 登録連打(7591-11、レート制限)。作成したクライアントは --cleanup で削除する
  python3 scripts/dcr_conformance_tests.py --id 7591-11 --flood 10

判定の種類:
  PASS / FAIL: 要件に対する合否
  INFO: 合否ではなく現状値の記録(既定値の判断事項など)
  SKIP: 前提が満たされず未実施
"""
import argparse
import base64
import hashlib
import http.server as httpserver
import json
import os
import secrets
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

DEFAULT_BASE = "https://2a5r57wfoa.execute-api.ap-northeast-1.amazonaws.com"
DEFAULT_USER_POOL_ID = "ap-northeast-1_XrU8FcC1w"
DEFAULT_TABLE = "quick-mcp-poc-users"
DEFAULT_PROFILE = "quick-agentcore-poc-playground"
FORBIDDEN_PROFILE = "quick-agentcore-poc"
CREATED_PATH = os.path.join(os.environ.get("TMPDIR", "/tmp"), "dcr_conformance_created_clients.json")
CLAUDE_REDIRECT = "https://claude.ai/api/mcp/auth_callback"


# ---------------------------------------------------------------- HTTP helpers

def http(url, method="GET", headers=None, data=None, timeout=30):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode(), {k.lower(): v for k, v in resp.headers.items()}, time.time() - t0
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(), {k.lower(): v for k, v in e.headers.items()}, time.time() - t0
    except Exception as e:  # noqa: BLE001
        return None, str(e), {}, time.time() - t0


def get_json(url):
    status, text, headers, elapsed = http(url)
    try:
        body = json.loads(text)
    except (json.JSONDecodeError, TypeError):
        body = None
    return status, body, headers, elapsed, text


def decode_jwt_payload(token):
    try:
        part = token.split(".")[1]
        part += "=" * (-len(part) % 4)
        return json.loads(base64.urlsafe_b64decode(part))
    except Exception:  # noqa: BLE001
        return None


# ---------------------------------------------------------------- result model

class Result:
    def __init__(self, cid, title):
        self.id = cid
        self.title = title
        self.status = "SKIP"
        self.detail = ""
        self.evidence = {}

    def set(self, status, detail="", **evidence):
        self.status = status
        self.detail = detail
        self.evidence = evidence
        return self

    def to_dict(self):
        return {"id": self.id, "title": self.title, "status": self.status, "detail": self.detail, "evidence": self.evidence}


class Ctx:
    def __init__(self, args):
        self.base = args.base.rstrip("/")
        self.resource = f"{self.base}/mcp"
        self.invoke_scope = f"{self.resource}/invoke"
        self.args = args
        self.created = []
        self.as_meta = None
        self.prm = None
        self.results = []

    def register(self, payload):
        status, text, headers, elapsed = http(
            f"{self.base}/register", "POST", {"content-type": "application/json"}, json.dumps(payload).encode()
        )
        try:
            body = json.loads(text)
        except (json.JSONDecodeError, TypeError):
            body = None
        if status == 201 and body and body.get("client_id"):
            self.created.append(body["client_id"])
        return status, body, headers, elapsed, text

    def add(self, result):
        self.results.append(result)
        mark = result.status.ljust(4)
        print(f"  [{mark}] {result.id:<9} {result.title}: {result.detail}")


# ---------------------------------------------------------------- discovery tests

def test_discovery(ctx):
    print("\n== Discovery (RFC 9728 / RFC 8414)")
    status, prm, headers, elapsed, raw = get_json(f"{ctx.base}/.well-known/oauth-protected-resource/mcp")
    ctx.prm = prm
    r = Result("9728-01", "PRM(パス付き)が200で resource / authorization_servers を持つ")
    if status == 200 and prm and prm.get("resource") == ctx.resource and prm.get("authorization_servers"):
        r.set("PASS", f"resource={prm['resource']}, elapsed={elapsed:.2f}s", body=prm)
    else:
        r.set("FAIL", f"HTTP {status}: {raw[:200]}", body=prm)
    ctx.add(r)

    r = Result("9728-03", "PRM scopes_supported に invoke スコープを含む")
    scopes = (prm or {}).get("scopes_supported")
    if scopes and ctx.invoke_scope in scopes:
        r.set("PASS", f"scopes_supported={scopes}")
    else:
        r.set("FAIL", f"scopes_supported={scopes} (期待: {ctx.invoke_scope} を含む)")
    ctx.add(r)

    r = Result("9728-04", "PRM bearer_methods_supported / resource_name")
    bm = (prm or {}).get("bearer_methods_supported")
    r.set("PASS" if bm else "FAIL", f"bearer_methods_supported={bm}, resource_name={(prm or {}).get('resource_name')}")
    ctx.add(r)

    status, root_prm, _, _, raw = get_json(f"{ctx.base}/.well-known/oauth-protected-resource")
    r = Result("9728-06", "PRM(パス無しルート)も応答する(Claudeの第2プローブ)")
    r.set("PASS" if status == 200 and root_prm else "FAIL", f"HTTP {status}: {raw[:120]}")
    ctx.add(r)

    status, text, headers, _ = http(
        f"{ctx.base}/mcp", "POST",
        {"content-type": "application/json", "accept": "application/json, text/event-stream"},
        json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}).encode(),
    )
    r = Result("9728-05", "未認証POST /mcp が401かつ WWW-Authenticate に resource_metadata を含む")
    www = headers.get("www-authenticate")
    if status == 401 and www and "resource_metadata" in www:
        r.set("PASS", f"WWW-Authenticate: {www}")
    elif status == 401:
        r.set("FAIL", f"401 だが WWW-Authenticate 無し(現行MCP仕様ではwell-known経路で代替可、scopeヒント不可)", headers=headers)
    else:
        r.set("FAIL", f"HTTP {status}: {text[:120]}", headers=headers)
    ctx.add(r)

    status, meta, headers, elapsed, raw = get_json(f"{ctx.base}/.well-known/oauth-authorization-server")
    ctx.as_meta = meta
    checks = [
        ("8414-01", "issuer が well-known 構築元(API GW URL)と一致", lambda m: m.get("issuer") == ctx.base, lambda m: f"issuer={m.get('issuer')}"),
        ("8414-03", "jwks_uri を公開", lambda m: bool(m.get("jwks_uri")), lambda m: f"jwks_uri={m.get('jwks_uri')}"),
        ("8414-04", "AS scopes_supported に invoke スコープを含む", lambda m: ctx.invoke_scope in (m.get("scopes_supported") or []), lambda m: f"scopes_supported={m.get('scopes_supported')}"),
        ("8414-05", "code_challenge_methods_supported に S256", lambda m: "S256" in (m.get("code_challenge_methods_supported") or []), lambda m: f"{m.get('code_challenge_methods_supported')}"),
        ("8414-06", "registration_endpoint を公開", lambda m: bool(m.get("registration_endpoint")), lambda m: f"{m.get('registration_endpoint')}"),
        ("8414-07", "token_endpoint_auth_methods_supported に none", lambda m: "none" in (m.get("token_endpoint_auth_methods_supported") or []), lambda m: f"{m.get('token_endpoint_auth_methods_supported')}"),
        ("8414-08", "revocation_endpoint を公開", lambda m: bool(m.get("revocation_endpoint")), lambda m: f"{m.get('revocation_endpoint')}"),
    ]
    if status != 200 or not meta:
        for cid, title, _, _ in checks:
            ctx.add(Result(cid, title).set("FAIL", f"AS metadata取得失敗 HTTP {status}: {raw[:120]}"))
    else:
        for cid, title, pred, show in checks:
            ctx.add(Result(cid, title).set("PASS" if pred(meta) else "FAIL", show(meta), body=meta if cid == "8414-01" else None))
        r = Result("8414-11", "CIMD(client_id_metadata_document_supported)の広告状況")
        r.set("INFO", f"client_id_metadata_document_supported={meta.get('client_id_metadata_document_supported')} (方針判断: CL-07)")
        ctx.add(r)
        r = Result("8414-02", "authorization_response_iss_parameter_supported の広告(RFC 9207、issuer不一致の時限リスク)")
        r.set("INFO", f"authorization_response_iss_parameter_supported={meta.get('authorization_response_iss_parameter_supported')}; 実際のコールバックの iss 有無は --auth-code で確認")
        ctx.add(r)

    status, oidc, _, _, raw = get_json(f"{ctx.base}/.well-known/openid-configuration")
    r = Result("8414-10", "/.well-known/openid-configuration ミラー")
    r.set("PASS" if status == 200 and oidc else "FAIL", f"HTTP {status}: {raw[:120]}")
    ctx.add(r)


# ---------------------------------------------------------------- DCR tests

def rfc_error(body):
    return isinstance(body, dict) and "error" in body and isinstance(body["error"], str)


def test_registration_positive(ctx):
    print("\n== DCR 正常系 (RFC 7591)")
    status, body, headers, elapsed, raw = ctx.register({"redirect_uris": [CLAUDE_REDIRECT]})
    r = Result("7591-01", "最小リクエスト(redirect_urisのみ)で201と client_id")
    if status == 201 and body and body.get("client_id"):
        r.set("PASS", f"client_id={body['client_id']}, elapsed={elapsed:.2f}s", response=body, headers=headers)
    else:
        r.set("FAIL", f"HTTP {status}: {raw[:200]}", headers=headers)
    ctx.add(r)
    first = body if status == 201 else None

    r = Result("CL-04", "登録応答が10秒以内(Anthropicのタイムアウト)")
    r.set("PASS" if elapsed < 10 else "FAIL", f"elapsed={elapsed:.2f}s (コールドスタート込みの初回)")
    ctx.add(r)

    r = Result("7591-04", "token_endpoint_auth_method 省略時の既定値(RFC既定は client_secret_basic)")
    if first:
        method = first.get("token_endpoint_auth_method")
        r.set("INFO", f"既定値={method}, client_secret発行={'あり' if first.get('client_secret') else 'なし'} (判断事項: RFC既定に合わせるか逸脱を文書化するか)")
    ctx.add(r)

    r = Result("7591-07", "client_secret_expires_at は secret 発行時のみ返す")
    if first:
        has_secret = "client_secret" in first
        has_exp = "client_secret_expires_at" in first
        ok = has_secret or not has_exp
        r.set("PASS" if ok else "FAIL", f"client_secret={'あり' if has_secret else 'なし'}, client_secret_expires_at={'あり' if has_exp else 'なし'}")
    ctx.add(r)

    r = Result("7591-10", "登録応答に Cache-Control: no-store / Pragma: no-cache")
    if first:
        cc = headers.get("cache-control", "")
        r.set("PASS" if "no-store" in cc else "FAIL", f"cache-control={cc!r}, pragma={headers.get('pragma')!r}")
    ctx.add(r)

    r = Result("7592-01", "registration_access_token と registration_client_uri を返す")
    if first:
        ok = bool(first.get("registration_access_token")) and bool(first.get("registration_client_uri"))
        r.set("PASS" if ok else "FAIL", f"registration_client_uri={first.get('registration_client_uri')}")
    ctx.add(r)

    r = Result("7592-02", "registration_client_uri への GET が有効(Bearer=registration_access_token)")
    if first and first.get("registration_client_uri"):
        s, t, h, _ = http(first["registration_client_uri"], "GET", {"authorization": f"Bearer {first.get('registration_access_token')}"})
        r.set("PASS" if s == 200 else "FAIL", f"HTTP {s}: {t[:120]}")
    else:
        r.set("SKIP", "registration_client_uri 未提供(7592-01 FAIL)")
    ctx.add(r)

    claude_code_like = {
        "client_name": "Claude Code (conformance)",
        "redirect_uris": ["http://localhost:53195/callback", "http://127.0.0.1:53195/callback"],
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
        "token_endpoint_auth_method": "none",
        "application_type": "native",
        "software_id": "conformance-suite",
        "software_version": "1.0",
        "client_uri": "https://example.invalid/client",
        "contacts": ["ops@example.invalid"],
    }
    status, body, headers, elapsed, raw = ctx.register(claude_code_like)
    r = Result("7591-02", "未知メタデータ(software_id, client_uri, contacts 等)を無視して201")
    r.set("PASS" if status == 201 else "FAIL", f"HTTP {status}: {raw[:160]}", response=body)
    ctx.add(r)
    r = Result("7591-14", "application_type(MCP 2026-07-28でクライアントMUST送信)を受理")
    r.set("PASS" if status == 201 else "FAIL", f"HTTP {status}")
    ctx.add(r)
    r = Result("7591-03", "登録済みメタデータをレスポンスで返す(client_name, redirect_uris, grant_types, response_types, scope)")
    if status == 201 and body:
        missing = [k for k in ("client_name", "redirect_uris", "grant_types", "response_types", "scope", "token_endpoint_auth_method") if k not in body]
        echoed = [k for k in ("client_uri", "contacts", "software_id") if k in body]
        name_ok = body.get("client_name") == claude_code_like["client_name"]
        r.set("PASS" if not missing and name_ok else "FAIL", f"missing={missing}, client_name一致={name_ok}, 追加メタデータの返却={echoed or 'なし'}")
    else:
        r.set("SKIP", "登録失敗のため未評価")
    ctx.add(r)

    status, body, headers, elapsed, raw = ctx.register({
        "client_name": "confidential-conformance",
        "grant_types": ["client_credentials"],
        "token_endpoint_auth_method": "client_secret_basic",
    })
    r = Result("CL-09", "client_credentials(M2M)登録の扱い(Claude非対応。非Claude顧客向けに残すかは方針判断)")
    if status == 201 and body:
        r.set("INFO", f"201, scope={body.get('scope')}, client_secret={'あり' if body.get('client_secret') else 'なし'}", response={k: v for k, v in body.items() if k != "client_secret"})
    else:
        r.set("INFO", f"HTTP {status}: {raw[:120]}")
    ctx.add(r)


def test_registration_negative(ctx):
    print("\n== DCR 異常系 (RFC 7591 §3.2.2 のエラー形式、500化しないこと)")
    cases = [
        ("7591-05", "response_types: [token] は invalid_client_metadata", {"redirect_uris": [CLAUDE_REDIRECT], "response_types": ["token"]}, (400,), "invalid_client_metadata"),
        ("7591-06", "フラグメント付き redirect_uri は invalid_redirect_uri(500にしない)", {"redirect_uris": [CLAUDE_REDIRECT + "#frag"]}, (400,), "invalid_redirect_uri"),
        ("7591-09a", "129文字の client_name は400のRFC形式または受理(500にしない。RFC 7591に長さ上限はない)", {"redirect_uris": [CLAUDE_REDIRECT], "client_name": "x" * 129}, (400, 201), None),
        ("7591-09b", "101件の redirect_uris は400のRFC形式", {"redirect_uris": [f"http://localhost:{p}/cb" for p in range(40000, 40101)]}, (400,), None),
        ("7591-09c", "非JSONボディは400 invalid_client_metadata", b"not json", (400,), "invalid_client_metadata"),
        ("7591-09d", "client_credentials + none は400(Cognitoの400を500にしない)", {"grant_types": ["client_credentials"], "token_endpoint_auth_method": "none"}, (400,), None),
        ("7591-12a", "許可外ホストの redirect_uri は invalid_redirect_uri", {"redirect_uris": ["https://evil.example/cb"]}, (400,), "invalid_redirect_uri"),
        ("7591-12b", "claude.ai のサブドメイン偽装(claude.ai.evil.example)は拒否", {"redirect_uris": ["https://claude.ai.evil.example/api/mcp/auth_callback"]}, (400,), "invalid_redirect_uri"),
        ("7591-12c", "http の非localhost redirect は拒否", {"redirect_uris": ["http://claude.ai/api/mcp/auth_callback"]}, (400,), "invalid_redirect_uri"),
        ("7591-12d", "未対応 grant_types(implicit)は invalid_client_metadata", {"redirect_uris": [CLAUDE_REDIRECT], "grant_types": ["implicit"]}, (400,), "invalid_client_metadata"),
        ("7591-12e", "refresh_token のみの grant_types は拒否", {"redirect_uris": [CLAUDE_REDIRECT], "grant_types": ["refresh_token"]}, (400,), "invalid_client_metadata"),
        ("7591-12f", "private_key_jwt は unsupported として400", {"redirect_uris": [CLAUDE_REDIRECT], "token_endpoint_auth_method": "private_key_jwt"}, (400,), "invalid_client_metadata"),
        ("7591-12g", "authorization_code で redirect_uris 無しは invalid_redirect_uri", {"grant_types": ["authorization_code"]}, (400,), "invalid_redirect_uri"),
    ]
    for cid, title, payload, expected, err in cases:
        if isinstance(payload, bytes):
            status, text, headers, _ = http(f"{ctx.base}/register", "POST", {"content-type": "application/json"}, payload)
            try:
                body = json.loads(text)
            except (json.JSONDecodeError, TypeError):
                body = None
            raw = text
        else:
            status, body, headers, _, raw = ctx.register(payload)
        r = Result(cid, title)
        if status in expected and rfc_error(body) and (err is None or body["error"] == err):
            r.set("PASS", f"HTTP {status} error={body['error']}: {body.get('error_description', '')[:80]}")
        elif status == 201 and 201 in expected:
            r.set("PASS", f"HTTP 201 受理(client_id={body.get('client_id')})")
        elif status == 201:
            r.set("FAIL", f"受理されてしまった(201, client_id={body.get('client_id')})", response=body)
        else:
            r.set("FAIL", f"HTTP {status} body={raw[:160]} (期待: {expected} かつ RFC形式 error={err or '任意'})")
        ctx.add(r)

    r = Result("7591-01b", "GET /register は 405 または 404(認証要求の401にはしない)")
    s, t, _, _ = http(f"{ctx.base}/register", "GET")
    r.set("INFO", f"HTTP {s}: {t[:80]} (現状は ANY /{{proxy+}} に落ちて Authorizer が処理)")
    ctx.add(r)


def test_flood(ctx, n):
    print(f"\n== DCR レート制限 (7591-11): 連続 {n} 回登録")
    statuses = []
    t0 = time.time()
    for i in range(n):
        s, body, _, _, _ = ctx.register({"client_name": f"flood-{i}", "redirect_uris": [CLAUDE_REDIRECT]})
        statuses.append(s)
    r = Result("7591-11", "連続登録で429(スロットル)が返り、無制限に登録できない")
    got429 = statuses.count(429)
    created = statuses.count(201)
    r.set("PASS" if got429 > 0 else "FAIL", f"{n}回 in {time.time() - t0:.1f}s: 201={created}, 429={got429}, other={[s for s in statuses if s not in (201, 429)]}", statuses=statuses)
    ctx.add(r)


# ---------------------------------------------------------------- authorization code flow

class _CallbackHandler(httpserver.BaseHTTPRequestHandler):
    captured = {}

    def do_GET(self):  # noqa: N802
        qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        _CallbackHandler.captured = {k: v[0] for k, v in qs.items()}
        self.send_response(200)
        self.send_header("content-type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write("ログイン完了。ターミナルに戻ってください。".encode())

    def log_message(self, *a):  # silence
        return


def test_auth_code(ctx):
    print("\n== 認可コード + PKCE フロー(ブラウザ操作が必要)")
    meta = ctx.as_meta or {}
    authz = meta.get("authorization_endpoint", f"{ctx.base}/authorize")
    token_ep = meta.get("token_endpoint", f"{ctx.base}/token")

    port = 53195
    redirect = f"http://localhost:{port}/callback"
    status, reg, _, _, raw = ctx.register({
        "client_name": "conformance-authcode",
        "redirect_uris": [redirect],
        "grant_types": ["authorization_code", "refresh_token"],
        "token_endpoint_auth_method": "none",
    })
    if status != 201:
        ctx.add(Result("MCP-02", "認可コードフロー").set("SKIP", f"登録失敗 HTTP {status}: {raw[:120]}"))
        return
    client_id = reg["client_id"]

    verifier = base64.urlsafe_b64encode(secrets.token_bytes(32)).rstrip(b"=").decode()
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    state = secrets.token_urlsafe(16)
    requested_scope = " ".join((ctx.prm or {}).get("scopes_supported") or (meta.get("scopes_supported") or ["openid"]))
    params = {
        "response_type": "code", "client_id": client_id, "redirect_uri": redirect, "state": state,
        "code_challenge": challenge, "code_challenge_method": "S256", "scope": requested_scope,
    }
    if not ctx.args.no_resource:
        params["resource"] = ctx.resource
    url = f"{authz}?{urllib.parse.urlencode(params)}"

    server = httpserver.HTTPServer(("127.0.0.1", port), _CallbackHandler)
    th = threading.Thread(target=server.handle_request, daemon=True)
    th.start()
    print(f"  ブラウザで開きます(開かない場合は手動で): {url}")
    print(f"  要求scope(PRM/ASのscopes_supportedに基づく)= {requested_scope!r}")
    webbrowser.open(url)
    th.join(timeout=300)
    server.server_close()
    cb = _CallbackHandler.captured
    if not cb:
        ctx.add(Result("MCP-02", "認可コードフロー").set("SKIP", "5分以内にコールバックを受信できず(ログイン画面が出ない場合は CL-03 ブランディング問題の疑い)"))
        return

    r = Result("CL-03", "DCRクライアントで Managed Login が表示されコールバックが返る")
    if "code" in cb:
        r.set("PASS", "code を受信")
    else:
        r.set("FAIL", f"コールバック error={cb.get('error')} {cb.get('error_description')}", callback=cb)
    ctx.add(r)
    r = Result("8414-02b", "認可レスポンスに iss パラメータが含まれるか(RFC 9207)")
    r.set("INFO", f"iss={'あり: ' + cb['iss'] if 'iss' in cb else 'なし'}; メタデータissuer={meta.get('issuer')}")
    ctx.add(r)
    if "code" not in cb:
        return

    form = {
        "grant_type": "authorization_code", "code": cb["code"], "redirect_uri": redirect,
        "client_id": client_id, "code_verifier": verifier,
    }
    if not ctx.args.no_resource:
        form["resource"] = ctx.resource
    s, t, h, _ = http(token_ep, "POST", {"content-type": "application/x-www-form-urlencoded"}, urllib.parse.urlencode(form).encode())
    r = Result("MCP-02", "トークンエンドポイントが resource パラメータ付きの要求を受理する")
    try:
        tok = json.loads(t)
    except (json.JSONDecodeError, TypeError):
        tok = {}
    if s == 200 and tok.get("access_token"):
        r.set("PASS" if not ctx.args.no_resource else "INFO", f"HTTP 200 (resource {'無し' if ctx.args.no_resource else '付き'})")
    else:
        r.set("FAIL", f"HTTP {s}: {t[:160]}")
    ctx.add(r)
    if not tok.get("access_token"):
        return

    payload = decode_jwt_payload(tok["access_token"]) or {}
    r = Result("MCP-03a", "アクセストークンの aud / scope / iss / client_id (audience検証の前提)")
    r.set("INFO", f"aud={payload.get('aud')}, scope={payload.get('scope')}, iss={payload.get('iss')}, client_id={payload.get('client_id')}, exp-iat={(payload.get('exp') or 0) - (payload.get('iat') or 0)}s",
          claims={k: payload.get(k) for k in ("aud", "scope", "iss", "client_id", "token_use", "exp", "iat")})
    ctx.add(r)
    r = Result("MCP-05", "リフレッシュトークンが発行される(ローテーション設定は DescribeUserPoolClient で確認)")
    r.set("INFO", f"refresh_token={'あり' if tok.get('refresh_token') else 'なし'}")
    ctx.add(r)

    s, t, h, _ = http(
        f"{ctx.base}/mcp", "POST",
        {"content-type": "application/json", "accept": "application/json, text/event-stream", "authorization": f"Bearer {tok['access_token']}"},
        json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}).encode(),
    )
    r = Result("CL-06", "取得トークンで tools/list(未承認ユーザーは403 User not found、承認済みは200)")
    r.set("INFO", f"HTTP {s}: {t[:160]}")
    ctx.add(r)

    with open(os.path.join(os.environ.get("TMPDIR", "/tmp"), "dcr_conformance_last_token.json"), "w", encoding="utf-8") as f:
        json.dump({"access_token": tok["access_token"], "obtained_at": int(time.time()), "client_id": client_id}, f)
    print("  アクセストークンを保存しました(60分後に MCP_EXPIRED_TOKEN として --id MCP-04 で使用可)")


def test_expired(ctx):
    print("\n== 期限切れトークンの応答コード (MCP-04)")
    tok = os.environ.get("MCP_EXPIRED_TOKEN")
    r = Result("MCP-04", "期限切れ/無効トークンには 401 を返す(403ではない。Claudeは401でのみリフレッシュ)")
    if not tok:
        saved = os.path.join(os.environ.get("TMPDIR", "/tmp"), "dcr_conformance_last_token.json")
        if os.path.exists(saved):
            d = json.load(open(saved, encoding="utf-8"))
            if time.time() - d["obtained_at"] > 3600:
                tok = d["access_token"]
    if not tok:
        ctx.add(r.set("SKIP", "MCP_EXPIRED_TOKEN 未設定(--auth-code 実行から60分後に再実行)"))
        return
    s, t, h, _ = http(
        f"{ctx.base}/mcp", "POST",
        {"content-type": "application/json", "accept": "application/json, text/event-stream", "authorization": f"Bearer {tok}"},
        json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}).encode(),
    )
    r.set("PASS" if s == 401 else "FAIL", f"HTTP {s}: {t[:120]} www-authenticate={h.get('www-authenticate')}")
    ctx.add(r)
    s, t, h, _ = http(
        f"{ctx.base}/mcp", "POST",
        {"content-type": "application/json", "accept": "application/json, text/event-stream", "authorization": "Bearer this.is.garbage"},
        json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}).encode(),
    )
    ctx.add(Result("MCP-04b", "不正な形式のトークンにも 401").set("PASS" if s == 401 else "FAIL", f"HTTP {s}"))


# ---------------------------------------------------------------- authorizer: deny-on-missing

def test_deny_on_missing(ctx):
    """AUTHZ-01/02: CLIENT# レコードを失ったクライアントのトークンは即時拒否される(401)。
    client_credentials クライアントを登録 → トークン取得 → /mcp 呼び出し(CLIENT# あり)→ CLIENT# を削除 →
    同じトークンで再呼び出し(401 を期待)。AWS CLI(playground プロファイル)で DynamoDB を操作する。"""
    print("\n== Authorizer deny-on-missing (AUTHZ-01 / AUTHZ-02)")
    status, reg, _, _, raw = ctx.register({
        "client_name": "conformance-deny-on-missing",
        "grant_types": ["client_credentials"],
        "token_endpoint_auth_method": "client_secret_basic",
    })
    r = Result("AUTHZ-02", "CLIENT# 削除直後に同一アクセストークンが拒否される(deny-on-missing)")
    if status != 201:
        ctx.add(r.set("SKIP", f"登録失敗 HTTP {status}: {raw[:120]}"))
        return
    token_ep = (ctx.as_meta or {}).get("token_endpoint", f"{ctx.base}/token")
    basic = base64.b64encode(f"{reg['client_id']}:{reg['client_secret']}".encode()).decode()
    s, t, _, _ = http(token_ep, "POST", {"content-type": "application/x-www-form-urlencoded", "authorization": f"Basic {basic}"},
                      urllib.parse.urlencode({"grant_type": "client_credentials", "scope": ctx.invoke_scope}).encode())
    try:
        tok = json.loads(t).get("access_token")
    except (json.JSONDecodeError, TypeError):
        tok = None
    if not tok:
        ctx.add(r.set("SKIP", f"トークン取得失敗 HTTP {s}: {t[:120]}"))
        return
    mcp_headers = {"content-type": "application/json", "accept": "application/json, text/event-stream", "authorization": f"Bearer {tok}"}
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}).encode()
    s_before, t_before, _, _ = http(f"{ctx.base}/mcp", "POST", mcp_headers, body)
    res = subprocess.run(["aws", "--profile", ctx.args.profile, "--region", "ap-northeast-1", "dynamodb", "delete-item",
                          "--table-name", ctx.args.table, "--key", json.dumps({"PK": {"S": f"CLIENT#{reg['client_id']}"}})],
                         capture_output=True, text=True)
    if res.returncode != 0:
        ctx.add(r.set("SKIP", f"CLIENT# 削除に失敗: {res.stderr[:120]}"))
        return
    s_after, t_after, _, _ = http(f"{ctx.base}/mcp", "POST", mcp_headers, body)
    detail = f"CLIENT#あり: HTTP {s_before} ({t_before[:60]!r}) → CLIENT#削除後: HTTP {s_after} ({t_after[:60]!r})"
    # 削除前はAuthorizerを通過してECS側のテナント未承認(403 User not found)になるのが正常。削除後は401。
    r.set("PASS" if s_after == 401 and s_before != 401 else "FAIL", detail, before=s_before, after=s_after)
    ctx.add(r)
    ctx.add(Result("AUTHZ-01", "CLIENT# レコードが存在しないクライアントは拒否される").set("PASS" if s_after == 401 else "FAIL", f"HTTP {s_after}"))


# ---------------------------------------------------------------- cleanup / report

def cleanup(args):
    if args.profile == FORBIDDEN_PROFILE:
        sys.exit("refusing to run against the production-equivalent profile")
    if not os.path.exists(CREATED_PATH):
        print("削除対象なし")
        return
    ids = json.load(open(CREATED_PATH, encoding="utf-8"))
    for cid in ids:
        for cmd in (
            ["cognito-idp", "delete-user-pool-client", "--user-pool-id", args.user_pool_id, "--client-id", cid],
            ["dynamodb", "delete-item", "--table-name", args.table, "--key", json.dumps({"PK": {"S": f"CLIENT#{cid}"}})],
            # 登録数上限カウンタ(COUNTER#dcr)は「現在のクライアント数」を表すので削除時に減算する
            ["dynamodb", "update-item", "--table-name", args.table, "--key", json.dumps({"PK": {"S": "COUNTER#dcr"}}),
             "--update-expression", "ADD #c :m", "--condition-expression", "#c > :zero",
             "--expression-attribute-names", json.dumps({"#c": "count"}),
             "--expression-attribute-values", json.dumps({":m": {"N": "-1"}, ":zero": {"N": "0"}})],
        ):
            res = subprocess.run(["aws", "--profile", args.profile, "--region", "ap-northeast-1", *cmd], capture_output=True, text=True)
            if res.returncode != 0 and "ResourceNotFoundException" not in res.stderr and "ConditionalCheckFailedException" not in res.stderr:
                print(f"  warn: {cmd[1]} {cid}: {res.stderr.strip()[:120]}")
        print(f"  deleted {cid}")
    os.remove(CREATED_PATH)


def save_created(ctx):
    existing = json.load(open(CREATED_PATH, encoding="utf-8")) if os.path.exists(CREATED_PATH) else []
    with open(CREATED_PATH, "w", encoding="utf-8") as f:
        json.dump(sorted(set(existing + ctx.created)), f)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", default=os.environ.get("MCP_ECS_BASE", DEFAULT_BASE))
    ap.add_argument("--id", action="append", help="実行するチェックリストIDの接頭辞(複数可、例: --id 7591 --id 9728)")
    ap.add_argument("--report", help="結果JSONの出力先")
    ap.add_argument("--flood", type=int, default=0, help="7591-11: 連続登録回数")
    ap.add_argument("--auth-code", action="store_true", help="認可コード+PKCEフローを実行(ブラウザ)")
    ap.add_argument("--no-resource", action="store_true", help="--auth-code で resource パラメータを付けない(差分比較用)")
    ap.add_argument("--cleanup", action="store_true", help="作成したテストクライアントを削除して終了")
    ap.add_argument("--profile", default=DEFAULT_PROFILE)
    ap.add_argument("--user-pool-id", default=DEFAULT_USER_POOL_ID)
    ap.add_argument("--table", default=DEFAULT_TABLE)
    args = ap.parse_args()

    if args.cleanup:
        cleanup(args)
        return

    ctx = Ctx(args)
    want = args.id or []

    def selected(prefixes):
        return not want or any(p.startswith(w) or w.startswith(p) for w in want for p in prefixes)

    print(f"target: {ctx.base}")
    if selected(["9728", "8414", "MCP", "CL"]):
        test_discovery(ctx)
    if selected(["7591", "7592", "CL"]):
        test_registration_positive(ctx)
        test_registration_negative(ctx)
    if args.flood and selected(["7591-11"]):
        test_flood(ctx, args.flood)
    if args.auth_code:
        if ctx.as_meta is None:
            test_discovery(ctx)
        test_auth_code(ctx)
    if selected(["MCP-04"]):
        test_expired(ctx)
    if selected(["AUTHZ"]):
        test_deny_on_missing(ctx)

    save_created(ctx)

    counts = {}
    for r in ctx.results:
        counts[r.status] = counts.get(r.status, 0) + 1
    print(f"\n== サマリ: {counts}  (作成したクライアント {len(ctx.created)} 件、--cleanup で削除)")
    if args.report:
        os.makedirs(os.path.dirname(args.report) or ".", exist_ok=True)
        with open(args.report, "w", encoding="utf-8") as f:
            json.dump({"target": ctx.base, "run_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "summary": counts,
                       "results": [r.to_dict() for r in ctx.results], "created_client_ids": ctx.created}, f, ensure_ascii=False, indent=2)
        print(f"report: {args.report}")
    sys.exit(0 if counts.get("FAIL", 0) == 0 else 1)


if __name__ == "__main__":
    main()

"""Cognitoの認可コード+PKCEフローでBearerトークンを取得し、AgentCore Runtimeの
Custom JWT Authorizerエンドポイントに素のHTTPS(boto3/SigV4不使用)でMCPリクエストを送る
簡易クライアント。Claude Code/Claude.aiに依存せず汎用MCPクライアントとの互換性を確認する用途。

Runtime version 6以降(IAM認証は排他のため invoke_agentcore_mcp.py は使用不可)を前提とする。

使い方:
  export MCP_TEST_PASSWORD='<quick-mcp-poc-verifyのパスワード>'
  python3 scripts/invoke_agentcore_mcp_jwt.py tools/list '{}'
  python3 scripts/invoke_agentcore_mcp_jwt.py tools/call '{"name":"get_quote","arguments":{"QCs":["7203/T"],"ECs":["NAME"]}}'

トークンをキャッシュして再利用したい場合(コールドスタート計測など)は --reuse-token を指定する
(初回はログインし、以降は $TMPDIR/agentcore_mcp_jwt_tokens.json のアクセストークンを使い回す)。

応答時間チューニング検証(docs/08 §3)向けの追加オプション:
  --runtime-arn <ARN>   デフォルトのquickMcpPocVerificationではなく別Runtime(quickMcpPocLatencyLab等)を叩く
  --session-id <ID>     Mcp-Session-Idリクエストヘッダーを付与して送る(セッション再利用/treatment群)
                         省略時はヘッダーなし(毎回新規セッション相当/control群)
  --initialize          本呼び出しの前にinitializeハンドシェイクを送る(往復レイテンシは計測結果に含まれない、
                         Mcp-Session-Id取得だけが目的)
出力にはレスポンスヘッダー(mcp-session-id/x-amzn-bedrock-agentcore-runtime-session-id)も含まれる。
"""
import argparse
import base64
import hashlib
import json
import os
import re
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

REGION = "ap-northeast-1"
USER_POOL_ID = "ap-northeast-1_WSvFtGhlV"
COGNITO_DOMAIN = "agentcore-mcp-883660531246.auth.ap-northeast-1.amazoncognito.com"
CLIENT_ID = "f9b41piv9irn56d49d16i9shc"
REDIRECT_URI = "http://localhost:3030/callback"
SCOPE = "openid mcp/invoke"
AGENT_RUNTIME_ARN = "arn:aws:bedrock-agentcore:ap-northeast-1:883660531246:runtime/quickMcpPocVerification-Aoo0d23yyj"
AWS_PROFILE = "quick-agentcore-poc-playground"

TOKEN_CACHE_PATH = os.path.join(os.environ.get("TMPDIR", "/tmp"), "agentcore_mcp_jwt_tokens.json")


def make_pkce_pair():
    verifier = base64.urlsafe_b64encode(secrets.token_bytes(32)).rstrip(b"=").decode()
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    return verifier, challenge


def fetch_client_secret():
    out = subprocess.run(
        [
            "aws", "cognito-idp", "describe-user-pool-client",
            "--user-pool-id", USER_POOL_ID,
            "--client-id", CLIENT_ID,
            "--profile", AWS_PROFILE,
            "--region", REGION,
        ],
        capture_output=True, text=True, check=True,
    )
    return json.loads(out.stdout)["UserPoolClient"]["ClientSecret"]


def login_and_get_tokens(username, password):
    verifier, challenge = make_pkce_pair()
    state = secrets.token_urlsafe(16)
    query = urllib.parse.urlencode({
        "response_type": "code",
        "client_id": CLIENT_ID,
        "redirect_uri": REDIRECT_URI,
        "scope": SCOPE,
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    })
    authorize_url = f"https://{COGNITO_DOMAIN}/oauth2/authorize?{query}"

    cookie_jar = urllib.request.HTTPCookieProcessor()
    opener = urllib.request.build_opener(cookie_jar)

    login_page = opener.open(authorize_url).read().decode()
    csrf_match = re.search(r'name="_csrf" value="([^"]*)"', login_page)
    action_match = re.search(r'<form action="([^"]*)"[^>]*name="cognitoSignInForm"', login_page)
    if not csrf_match or not action_match:
        raise RuntimeError("ログインフォームの解析に失敗(Cognito側のUI変更の可能性)")
    csrf = csrf_match.group(1)
    login_url = f"https://{COGNITO_DOMAIN}{action_match.group(1).replace('&amp;', '&')}"

    login_body = urllib.parse.urlencode({
        "_csrf": csrf,
        "username": username,
        "password": password,
        "cognitoAsfData": "",
    }).encode()

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **kw):
            return None

    no_redirect_opener = urllib.request.build_opener(cookie_jar, NoRedirect)
    try:
        login_resp = no_redirect_opener.open(urllib.request.Request(login_url, data=login_body, method="POST"))
        location = login_resp.headers.get("Location", "")
    except urllib.error.HTTPError as e:
        location = e.headers.get("Location", "")
    code_match = re.search(r"code=([^&]+)", location)
    if not code_match:
        raise RuntimeError(f"ログインに失敗、または想定外のリダイレクト先: {location}")
    code = code_match.group(1)

    client_secret = fetch_client_secret()
    basic = base64.b64encode(f"{CLIENT_ID}:{client_secret}".encode()).decode()
    token_body = urllib.parse.urlencode({
        "grant_type": "authorization_code",
        "client_id": CLIENT_ID,
        "code": code,
        "redirect_uri": REDIRECT_URI,
        "code_verifier": verifier,
    }).encode()
    token_req = urllib.request.Request(
        f"https://{COGNITO_DOMAIN}/oauth2/token",
        data=token_body,
        headers={
            "Authorization": f"Basic {basic}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        method="POST",
    )
    with urllib.request.urlopen(token_req) as resp:
        tokens = json.loads(resp.read())
    tokens["obtained_at"] = time.time()
    with open(TOKEN_CACHE_PATH, "w") as f:
        json.dump(tokens, f)
    os.chmod(TOKEN_CACHE_PATH, 0o600)
    return tokens


def call_mcp(access_token, method, params, spoof_sub=None, runtime_arn=None, session_id=None, req_id=1):
    endpoint = (
        "https://bedrock-agentcore.ap-northeast-1.amazonaws.com/runtimes/"
        + urllib.parse.quote(runtime_arn or AGENT_RUNTIME_ARN, safe="")
        + "/invocations?qualifier=DEFAULT"
    )
    payload = json.dumps({"jsonrpc": "2.0", "id": req_id, "method": method, "params": params}).encode()
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    }
    if spoof_sub:
        # security probe (docs/08-weekly-verification-plan.md §1): checks whether
        # AgentCore Runtime passes this header through uninspected, the way ECS's
        # API Gateway does *not* (it overwrites it with the JWT-verified sub).
        headers["x-cognito-sub"] = spoof_sub
    if session_id:
        # session-id-reuse hypothesis (docs/08-weekly-verification-plan.md §3):
        # AgentCore Runtime may route requests carrying the same Mcp-Session-Id
        # to the same warm microVM, skipping the ~3.9s container boot cost.
        headers["Mcp-Session-Id"] = session_id
    req = urllib.request.Request(
        endpoint,
        data=payload,
        headers=headers,
        method="POST",
    )
    start = time.monotonic()
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read()
            elapsed = time.monotonic() - start
            resp_headers = {
                "mcp-session-id": resp.headers.get("mcp-session-id"),
                "x-amzn-bedrock-agentcore-runtime-session-id": resp.headers.get(
                    "x-amzn-bedrock-agentcore-runtime-session-id"
                ),
            }
            return json.loads(body), elapsed, resp_headers
    except urllib.error.HTTPError as e:
        elapsed = time.monotonic() - start
        resp_headers = {
            "mcp-session-id": e.headers.get("mcp-session-id"),
            "x-amzn-bedrock-agentcore-runtime-session-id": e.headers.get(
                "x-amzn-bedrock-agentcore-runtime-session-id"
            ),
        }
        return {"http_error": e.code, "body": e.read().decode()}, elapsed, resp_headers


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("method", nargs="?", default="tools/list")
    parser.add_argument("params", nargs="?", default="{}")
    parser.add_argument("--username", default=os.environ.get("MCP_TEST_USERNAME", "quick-mcp-poc-verify"))
    parser.add_argument("--reuse-token", action="store_true", help="既存のトークンキャッシュを再利用する(再ログインしない)")
    parser.add_argument("--spoof-sub", default=None, help="セキュリティ検証用: x-cognito-subヘッダーを指定値で付与する(docs/08 §1)")
    parser.add_argument("--runtime-arn", default=None, help="デフォルトのquickMcpPocVerification以外のRuntime ARNを指定")
    parser.add_argument("--session-id", default=None, help="Mcp-Session-Idリクエストヘッダーを付与する(セッション再利用検証)")
    parser.add_argument("--initialize", action="store_true", help="本呼び出しの前にinitializeハンドシェイクを送りMcp-Session-Idを取得する")
    args = parser.parse_args()

    tokens = None
    if args.reuse_token and os.path.exists(TOKEN_CACHE_PATH):
        tokens = json.load(open(TOKEN_CACHE_PATH))
    if tokens is None:
        password = os.environ.get("MCP_TEST_PASSWORD")
        if not password:
            sys.exit("環境変数 MCP_TEST_PASSWORD にテストユーザーのパスワードを設定してください")
        tokens = login_and_get_tokens(args.username, password)

    session_id = args.session_id
    if args.initialize:
        init_result, init_elapsed, init_headers = call_mcp(
            tokens["access_token"], "initialize",
            {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "latency-lab-client", "version": "1.0.0"}},
            runtime_arn=args.runtime_arn, session_id=session_id, req_id=0,
        )
        session_id = init_headers.get("mcp-session-id") or session_id
        print(f"initialize elapsed_seconds={init_elapsed:.3f} session_id={session_id}", file=sys.stderr)

    result, elapsed, resp_headers = call_mcp(
        tokens["access_token"], args.method, json.loads(args.params),
        spoof_sub=args.spoof_sub, runtime_arn=args.runtime_arn, session_id=session_id,
    )
    print(f"elapsed_seconds={elapsed:.3f}")
    print(f"response_headers={json.dumps(resp_headers)}")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

"""pattern4(ECS + API Gateway、playground)向けの検証用トークンを取得するヘルパー。

DCRで client_credentials クライアントを自己登録し、DynamoDBに USER#<client_id> を投入して
テナント承認した上で、Cognito の /oauth2/token から client_credentials トークンを取得する。
scripts/mcp_functional_tests.py の docstring に手順として書かれていた作業を自動化したもの。
WAF攻撃テスト(scripts/waf_attack_tests.py)や回帰テストで使う。

使い方:
  # 登録 + 承認 + トークン取得(client_id/secret は $TMPDIR/pattern4_token_state.json に保存)
  eval "$(python3 scripts/pattern4_token.py bootstrap)"
  echo $MCP_ECS_TOKEN

  # 保存済みクライアントでトークンだけ再取得
  eval "$(python3 scripts/pattern4_token.py token)"

  # 後片付け(Cognitoアプリクライアント削除 + CLIENT#/USER# 削除)
  python3 scripts/pattern4_token.py cleanup

前提: AWS CLI が quick-agentcore-poc-playground プロファイルでログイン済み。
本番相当プロファイル(quick-agentcore-poc)では絶対に実行しないこと(書き込み厳禁)。
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_BASE = "https://2a5r57wfoa.execute-api.ap-northeast-1.amazonaws.com"
DEFAULT_COGNITO_HOST = "https://quick-mcp-poc-pattern4-verify.auth.ap-northeast-1.amazoncognito.com"
DEFAULT_USER_POOL_ID = "ap-northeast-1_XrU8FcC1w"
DEFAULT_TABLE = "quick-mcp-poc-users"
DEFAULT_PROFILE = "quick-agentcore-poc-playground"
FORBIDDEN_PROFILE = "quick-agentcore-poc"
STATE_PATH = os.path.join(os.environ.get("TMPDIR", "/tmp"), "pattern4_token_state.json")


def aws(profile, *args):
    cmd = ["aws", "--profile", profile, "--region", "ap-northeast-1", *args]
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout


def http_json(url, method="GET", headers=None, data=None):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, resp.read().decode(), dict(resp.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(), dict(e.headers)


def register(base):
    body = json.dumps({
        "client_name": "pattern4-token-helper",
        "grant_types": ["client_credentials"],
        "token_endpoint_auth_method": "client_secret_basic",
    }).encode()
    status, text, _ = http_json(f"{base}/register", "POST", {"content-type": "application/json"}, body)
    if status != 201:
        sys.exit(f"DCR registration failed: HTTP {status} {text}")
    return json.loads(text)


def approve(profile, table, client_id):
    item = json.dumps({
        "PK": {"S": f"USER#{client_id}"},
        "services": {"M": {"quick": {"M": {"plan": {"S": "standard"}}}}},
        "note": {"S": "pattern4_token.py verification account"},
    })
    aws(profile, "dynamodb", "put-item", "--table-name", table, "--item", item)


def fetch_token(cognito_host, client_id, client_secret, scope):
    basic = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    data = urllib.parse.urlencode({"grant_type": "client_credentials", "scope": scope}).encode()
    status, text, _ = http_json(
        f"{cognito_host}/oauth2/token",
        "POST",
        {"content-type": "application/x-www-form-urlencoded", "authorization": f"Basic {basic}"},
        data,
    )
    if status != 200:
        sys.exit(f"token request failed: HTTP {status} {text}")
    return json.loads(text)["access_token"]


def load_state():
    if not os.path.exists(STATE_PATH):
        sys.exit(f"state file not found: {STATE_PATH} (run 'bootstrap' first)")
    return json.load(open(STATE_PATH, encoding="utf-8"))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["bootstrap", "token", "cleanup"])
    ap.add_argument("--base", default=os.environ.get("MCP_ECS_BASE", DEFAULT_BASE))
    ap.add_argument("--cognito-host", default=DEFAULT_COGNITO_HOST)
    ap.add_argument("--user-pool-id", default=DEFAULT_USER_POOL_ID)
    ap.add_argument("--table", default=DEFAULT_TABLE)
    ap.add_argument("--profile", default=DEFAULT_PROFILE)
    args = ap.parse_args()

    if args.profile == FORBIDDEN_PROFILE:
        sys.exit("refusing to run against the production-equivalent profile (write-protected)")

    scope = f"{args.base}/mcp/invoke"

    if args.command == "bootstrap":
        reg = register(args.base)
        approve(args.profile, args.table, reg["client_id"])
        state = {"client_id": reg["client_id"], "client_secret": reg["client_secret"], "base": args.base}
        with open(STATE_PATH, "w", encoding="utf-8") as f:
            json.dump(state, f)
        os.chmod(STATE_PATH, 0o600)
        token = fetch_token(args.cognito_host, reg["client_id"], reg["client_secret"], scope)
        print(f"export MCP_ECS_TOKEN='{token}'")
        print(f"export MCP_ECS_CLIENT_ID='{reg['client_id']}'")
        print(f"# state saved to {STATE_PATH}", file=sys.stderr)
    elif args.command == "token":
        state = load_state()
        token = fetch_token(args.cognito_host, state["client_id"], state["client_secret"], scope)
        print(f"export MCP_ECS_TOKEN='{token}'")
        print(f"export MCP_ECS_CLIENT_ID='{state['client_id']}'")
    else:
        state = load_state()
        cid = state["client_id"]
        aws(args.profile, "cognito-idp", "delete-user-pool-client", "--user-pool-id", args.user_pool_id, "--client-id", cid)
        for pk in (f"CLIENT#{cid}", f"USER#{cid}"):
            aws(args.profile, "dynamodb", "delete-item", "--table-name", args.table, "--key", json.dumps({"PK": {"S": pk}}))
        os.remove(STATE_PATH)
        print(f"deleted client {cid} and its CLIENT#/USER# records", file=sys.stderr)


if __name__ == "__main__":
    main()

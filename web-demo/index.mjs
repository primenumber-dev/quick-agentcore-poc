import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand, UpdateCommand, DeleteCommand } from "@aws-sdk/lib-dynamodb";
import { CognitoIdentityProviderClient, DeleteUserPoolClientCommand } from "@aws-sdk/client-cognito-identity-provider";

const COGNITO_DOMAIN = "agentcore-mcp-883660531246.auth.ap-northeast-1.amazoncognito.com";
const CLIENT_ID = process.env.CLIENT_ID;
const SCOPE = "openid mcp/invoke";
const MCP_ENDPOINT_BASE = "https://d22imwd0soxmb2.cloudfront.net"; // WAF検証で構築したCloudFront経由(§4)
const AGENT_RUNTIME_ARN =
  "arn:aws:bedrock-agentcore:ap-northeast-1:883660531246:runtime/quickMcpPocVerification-Aoo0d23yyj";

// 応答時間デモ(セッションID再利用、docs/16 §1)向けの設定
const LATENCY_LAB_RUNTIME_ARN =
  "arn:aws:bedrock-agentcore:ap-northeast-1:883660531246:runtime/quickMcpPocLatencyLab-uC4Wd7EOWj";
const M2M_CLIENT_ID = process.env.M2M_CLIENT_ID;
const M2M_CLIENT_SECRET = process.env.M2M_CLIENT_SECRET;

// MCPプロトコルv2 SDKデモ(docs/12 §7)向けの設定。V1_RUNTIME_ARNは現行デプロイ(v1 SDK)と
// 同一イメージ系統のLatencyLab Runtimeを流用、V2_RUNTIME_ARNはfeature/mcp-protocol-v2-spike
// ブランチのイメージを動かす専用Runtime。
const SDK_DEMO_V1_RUNTIME_ARN = LATENCY_LAB_RUNTIME_ARN;
const SDK_DEMO_V2_RUNTIME_ARN =
  "arn:aws:bedrock-agentcore:ap-northeast-1:883660531246:runtime/quickMcpPocV2SdkDemo-lxkNuS7moU";

// DCRデモ(docs/15 §1)向けの設定(pattern4環境)
const PATTERN4_API_BASE = "https://2a5r57wfoa.execute-api.ap-northeast-1.amazonaws.com";
const PATTERN4_COGNITO_DOMAIN = "quick-mcp-poc-pattern4-verify.auth.ap-northeast-1.amazoncognito.com";
const PATTERN4_USER_POOL_ID = "ap-northeast-1_XrU8FcC1w";
const PATTERN4_SCOPE = `${PATTERN4_API_BASE}/mcp/invoke`;
const USERS_TABLE_NAME = "quick-mcp-poc-users";

// WAFデモ(docs/15 §4)向けの攻撃パターン
const WAF_PROBES = [
  { key: "benign", label: "正常なリクエスト", query: "?q=7203" },
  { key: "xss", label: "XSS攻撃パターン", query: "?q=%3Cscript%3Ealert(1)%3C%2Fscript%3E" },
  { key: "sqli", label: "SQLインジェクション攻撃パターン", query: "?id=1%27%20OR%20%271%27%3D%271" },
];

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const cognitoAdmin = new CognitoIdentityProviderClient({});

function html(redirectUri) {
  return `<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8" />
<title>quick-mcp-poc 疎通検証アプリ</title>
<style>
  body { font-family: -apple-system, sans-serif; max-width: 780px; margin: 40px auto; padding: 0 16px; color: #1a1a1a; }
  button { font-size: 14px; padding: 8px 14px; margin: 4px 4px 4px 0; cursor: pointer; }
  pre { background: #f5f5f5; padding: 12px; overflow-x: auto; white-space: pre-wrap; word-break: break-all; }
  #status { font-weight: bold; }
  .ok { color: #0a7d2c; }
  .err { color: #c0392b; }
  section { margin-top: 40px; padding-top: 24px; border-top: 1px solid #ddd; }
  table { border-collapse: collapse; width: 100%; margin: 12px 0; }
  th, td { border: 1px solid #ddd; padding: 8px 10px; text-align: left; font-size: 14px; }
  th { background: #f0f0f0; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 12px; font-weight: bold; }
  .badge.pass { background: #d4edda; color: #0a7d2c; }
  .badge.block { background: #f8d7da; color: #c0392b; }
  .step-list { list-style: none; padding: 0; }
  .step-list li { padding: 8px 0; border-bottom: 1px solid #eee; }
  .compare-grid { display: flex; gap: 16px; margin: 16px 0; }
  .compare-col { flex: 1; padding: 16px; border-radius: 8px; }
  .compare-col.before { background: #fdecea; }
  .compare-col.after { background: #e8f5e9; }
  .compare-col h3 { margin: 0 0 8px 0; font-size: 14px; }
  .compare-col .big-number { font-size: 32px; font-weight: bold; margin: 8px 0; }
  .compare-col.before .big-number { color: #c0392b; }
  .compare-col.after .big-number { color: #0a7d2c; }
  .compare-label { font-size: 13px; color: #555; margin: 0; }
  .compare-summary { font-size: 15px; text-align: center; }
</style>
</head>
<body>
<h1>quick-mcp-poc 疎通検証アプリ</h1>
<p>OAuth 2.0(Authorization Code + PKCE)でCognitoにログインし、AgentCore Runtime(CloudFront+WAF経由)へMCPリクエストを送る、boto3/Claude Code/Claude.aiに依存しない検証用Webアプリです。</p>
<p id="status">未接続</p>
<button id="loginBtn">Cognitoでログイン</button>
<button id="listBtn" disabled>tools/list</button>
<button id="callBtn" disabled>tools/call (get_quote)</button>
<pre id="output">(ここに結果が表示されます)</pre>

<section id="latency-demo">
<h2>応答時間デモ: 先週までの挙動 vs 今回可能になった高速化</h2>
<p>AgentCore Runtimeは毎回のリクエストで新しいコンテナを起動するため約6秒かかっていた(先週までの挙動)。今回、レスポンスヘッダーの<code>Mcp-Session-Id</code>を次回リクエストで再送すると同じコンテナが再利用され高速化することを実機で確認した(<a href="https://github.com/primenumber-dev/quick-agentcore-poc/blob/main/docs/16-weekly-verification-report-week3.md">今週の検証レポート §1</a>参照)。1回のボタン操作で両方を実測し、左右に並べて比較します。ログイン不要で実行できます。</p>
<button id="latencyBtn">デモを実行(約10秒)</button>
<div class="compare-grid">
  <div class="compare-col before">
    <h3>先週までの挙動</h3>
    <p class="compare-label">セッションID再利用なし(毎回新規コンテナ起動)</p>
    <div class="big-number" id="latencyBefore">-</div>
  </div>
  <div class="compare-col after">
    <h3>今回できるようになったこと</h3>
    <p class="compare-label">セッションID再利用(コンテナ再利用)</p>
    <div class="big-number" id="latencyAfter">-</div>
  </div>
</div>
<p class="compare-summary" id="latencySummary"></p>
</section>

<section id="dcr-demo">
<h2>DCRデモ: 動的クライアント登録の自己登録〜失効フロー</h2>
<div class="compare-grid">
  <div class="compare-col before">
    <h3>先週までの認識</h3>
    <p>DCR(動的クライアント登録)を実現するには、AgentCore Runtime単体では不可能で、ECS+Lambda Authorizer相当の追加実装が必須と考えられていた</p>
  </div>
  <div class="compare-col after">
    <h3>今回判明したこと</h3>
    <p>AgentCore Runtimeの認可設定を<code>allowedScopes</code>のみに変更するだけで、追加のLambda実装なしにDCRが成立することを実機で確認した(<a href="https://github.com/primenumber-dev/quick-agentcore-poc/blob/main/docs/15-ecs-production-readiness-gaps.md">課題整理レポート §2</a>参照)</p>
  </div>
</div>
<p>以下は既存のECS環境(pattern4)で、利用者が自分でクライアントを登録し(<code>POST /register</code>)、承認されるまではアクセスできず、承認後にアクセス可能になり、失効後は即座にアクセスできなくなる一連の流れを実演するデモです。ログイン不要で実行できます。実行後、作成したテスト用クライアントは自動的に削除されます。</p>
<button id="dcrBtn">デモを実行(約15秒)</button>
<ul id="dcrResult" class="step-list"></ul>
</section>

<section id="waf-demo">
<h2>WAFデモ: 不正パターンの遮断</h2>
<p>CloudFront+WAFv2経由で、正常なリクエストは通過し、既知の攻撃パターン(XSS)は403でブロックされる一方、現状のルールセットではSQLインジェクションパターンが素通りすることを実演する(<a href="https://github.com/primenumber-dev/quick-agentcore-poc/blob/main/docs/15-ecs-production-readiness-gaps.md">課題整理レポート §4</a>参照)。ログイン不要で実行できます。</p>
<button id="wafBtn">デモを実行</button>
<table id="wafResult"></table>
</section>

<section id="sdk-demo">
<h2>MCPプロトコルv2 SDKデモ: 新世代クライアントへの対応</h2>
<p>MCPプロトコルには2026-07-28版(v2)があり、旧世代クライアント(<code>initialize</code>ハンドシェイクを使う)とは別に、ハンドシェイクを省略して自己申告形式で通信する新世代クライアントが今後登場してくる。現行デプロイ済みのサーバー(v1 SDK)と、今回試験的に作成したv2 SDK版サーバーの両方に、新世代クライアント形式のリクエストを実際に送って比較する(<a href="https://github.com/primenumber-dev/quick-agentcore-poc/blob/main/docs/12-mcp-protocol-v2-upgrade-impact.md">v2移行影響調査レポート §7</a>参照)。ログイン不要で実行できます。</p>
<button id="sdkBtn">デモを実行(約15秒)</button>
<div class="compare-grid" id="sdkResult">
  <div class="compare-col before">
    <h3>現行サーバー(v1 SDK)</h3>
    <ul class="step-list" id="sdkBefore"><li>-</li></ul>
  </div>
  <div class="compare-col after">
    <h3>v2 SDKアップデート後(試験実装)</h3>
    <ul class="step-list" id="sdkAfter"><li>-</li></ul>
  </div>
</div>
</section>

<script>
const REDIRECT_URI = ${JSON.stringify(redirectUri)};
const CLIENT_ID = ${JSON.stringify(CLIENT_ID)};
const COGNITO_DOMAIN = ${JSON.stringify(COGNITO_DOMAIN)};
const SCOPE = ${JSON.stringify(SCOPE)};

function b64url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/, '');
}
async function sha256(str) {
  const data = new TextEncoder().encode(str);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return b64url(new Uint8Array(digest));
}
function randomString() {
  const arr = new Uint8Array(32);
  crypto.getRandomValues(arr);
  return b64url(arr);
}
function setStatus(text, ok) {
  const el = document.getElementById('status');
  el.textContent = text;
  el.className = ok === undefined ? '' : (ok ? 'ok' : 'err');
}
function out(obj) {
  document.getElementById('output').textContent =
    typeof obj === 'string' ? obj : JSON.stringify(obj, null, 2);
}

async function startLogin() {
  const verifier = randomString();
  const challenge = await sha256(verifier);
  sessionStorage.setItem('pkce_verifier', verifier);
  const params = new URLSearchParams({
    response_type: 'code',
    client_id: CLIENT_ID,
    redirect_uri: REDIRECT_URI,
    scope: SCOPE,
    code_challenge: challenge,
    code_challenge_method: 'S256',
  });
  window.location.href = 'https://' + COGNITO_DOMAIN + '/oauth2/authorize?' + params.toString();
}

async function handleCallback(code) {
  const verifier = sessionStorage.getItem('pkce_verifier');
  setStatus('トークン交換中...');
  const resp = await fetch('/api/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code, code_verifier: verifier, redirect_uri: REDIRECT_URI }),
  });
  const data = await resp.json();
  if (!resp.ok) {
    setStatus('トークン交換に失敗: ' + JSON.stringify(data), false);
    return;
  }
  sessionStorage.setItem('access_token', data.access_token);
  window.history.replaceState({}, '', REDIRECT_URI);
  setStatus('接続済み(トークン取得成功)', true);
  document.getElementById('listBtn').disabled = false;
  document.getElementById('callBtn').disabled = false;
}

async function callMcp(method, params) {
  const token = sessionStorage.getItem('access_token');
  if (!token) { setStatus('未接続', false); return; }
  setStatus('リクエスト送信中...');
  const start = performance.now();
  const resp = await fetch('/api/mcp', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ access_token: token, method, params }),
  });
  const elapsed = ((performance.now() - start) / 1000).toFixed(3);
  const data = await resp.json();
  setStatus('応答受信(' + elapsed + '秒)', resp.ok);
  out(data);
}

document.getElementById('loginBtn').addEventListener('click', startLogin);
document.getElementById('listBtn').addEventListener('click', () => callMcp('tools/list', {}));
document.getElementById('callBtn').addEventListener('click', () =>
  callMcp('tools/call', { name: 'get_quote', arguments: { QCs: ['7203/T'], ECs: ['NAME'] } })
);

const urlParams = new URLSearchParams(window.location.search);
if (urlParams.get('code')) {
  handleCallback(urlParams.get('code'));
} else if (sessionStorage.getItem('access_token')) {
  setStatus('接続済み(トークン保持中)', true);
  document.getElementById('listBtn').disabled = false;
  document.getElementById('callBtn').disabled = false;
}

// --- 応答時間デモ ---
document.getElementById('latencyBtn').addEventListener('click', async () => {
  const btn = document.getElementById('latencyBtn');
  const beforeEl = document.getElementById('latencyBefore');
  const afterEl = document.getElementById('latencyAfter');
  const summaryEl = document.getElementById('latencySummary');
  btn.disabled = true;
  beforeEl.textContent = '計測中...';
  afterEl.textContent = '計測中...';
  summaryEl.textContent = '';
  try {
    const resp = await fetch('/api/latency-demo', { method: 'POST' });
    const data = await resp.json();
    if (!resp.ok) { summaryEl.innerHTML = '<span class="err">デモ実行に失敗: ' + JSON.stringify(data) + '</span>'; return; }
    const baseline = data.results[0].elapsedSeconds;
    const treatment = data.results[1].elapsedSeconds;
    const control = data.results[2].elapsedSeconds;
    const beforeAvg = (baseline + control) / 2;
    beforeEl.textContent = beforeAvg.toFixed(2) + ' 秒';
    afterEl.textContent = treatment.toFixed(2) + ' 秒';
    const speedup = (beforeAvg / treatment).toFixed(1);
    summaryEl.innerHTML =
      'セッションID再利用により約 <b>' + speedup + '倍</b> 高速化しました。' +
      '(実測値: ベースライン ' + baseline.toFixed(2) + '秒、再利用時 ' + treatment.toFixed(2) + '秒、比較用の新規セッション ' + control.toFixed(2) + '秒。' +
      'この効果は数分以上経過すると失われることが判明しています。詳細は<a href="https://github.com/primenumber-dev/quick-agentcore-poc/blob/main/docs/16-weekly-verification-report-week3.md">週次レポート §1</a>参照)';
  } catch (e) {
    summaryEl.innerHTML = '<span class="err">エラー: ' + e.message + '</span>';
  } finally {
    btn.disabled = false;
  }
});

// --- DCRデモ ---
document.getElementById('dcrBtn').addEventListener('click', async () => {
  const btn = document.getElementById('dcrBtn');
  const el = document.getElementById('dcrResult');
  btn.disabled = true;
  el.innerHTML = '<li>実行中...</li>';
  try {
    const resp = await fetch('/api/dcr-demo', { method: 'POST' });
    const data = await resp.json();
    if (!resp.ok) { el.innerHTML = '<li class="err">デモ実行に失敗: ' + JSON.stringify(data) + '</li>'; return; }
    el.innerHTML = data.steps.map(s =>
      '<li><span class="badge ' + (s.pass ? 'pass' : 'block') + '">' + s.httpStatus + '</span> ' + s.description + '</li>'
    ).join('');
  } catch (e) {
    el.innerHTML = '<li class="err">エラー: ' + e.message + '</li>';
  } finally {
    btn.disabled = false;
  }
});

// --- WAFデモ ---
document.getElementById('wafBtn').addEventListener('click', async () => {
  const btn = document.getElementById('wafBtn');
  const el = document.getElementById('wafResult');
  btn.disabled = true;
  el.innerHTML = '<tr><td>実行中...</td></tr>';
  try {
    const resp = await fetch('/api/waf-demo', { method: 'POST' });
    const data = await resp.json();
    if (!resp.ok) { el.innerHTML = '<tr><td class="err">デモ実行に失敗: ' + JSON.stringify(data) + '</td></tr>'; return; }
    const rows = data.results.map(r =>
      '<tr><td>' + r.label + '</td><td>' + r.httpStatus + '</td><td><span class="badge ' + (r.blocked ? 'block' : 'pass') + '">' + (r.blocked ? '遮断' : '通過') + '</span></td></tr>'
    ).join('');
    el.innerHTML = '<tr><th>パターン</th><th>HTTPステータス</th><th>結果</th></tr>' + rows;
  } catch (e) {
    el.innerHTML = '<tr><td class="err">エラー: ' + e.message + '</td></tr>';
  } finally {
    btn.disabled = false;
  }
});

// --- MCPプロトコルv2 SDKデモ ---
function renderSdkColumn(el, r) {
  el.innerHTML =
    '<li><span class="badge ' + (r.classic ? 'pass' : 'block') + '">' + (r.classic ? '成功' : '失敗') + '</span> 従来形式のリクエスト(initializeハンドシェイクを使う旧世代クライアント相当)</li>' +
    '<li><span class="badge ' + (r.modern ? 'pass' : 'block') + '">' + (r.modern ? '成功' : '失敗') + '</span> 新形式のリクエスト(ハンドシェイクを省略する新世代クライアント相当)</li>';
}
document.getElementById('sdkBtn').addEventListener('click', async () => {
  const btn = document.getElementById('sdkBtn');
  const beforeEl = document.getElementById('sdkBefore');
  const afterEl = document.getElementById('sdkAfter');
  btn.disabled = true;
  beforeEl.innerHTML = '<li>実行中...</li>';
  afterEl.innerHTML = '<li>実行中...</li>';
  try {
    const resp = await fetch('/api/sdk-demo', { method: 'POST' });
    const data = await resp.json();
    if (!resp.ok) {
      beforeEl.innerHTML = '<li class="err">デモ実行に失敗: ' + JSON.stringify(data) + '</li>';
      afterEl.innerHTML = '';
      return;
    }
    renderSdkColumn(beforeEl, data.v1);
    renderSdkColumn(afterEl, data.v2);
  } catch (e) {
    beforeEl.innerHTML = '<li class="err">エラー: ' + e.message + '</li>';
    afterEl.innerHTML = '';
  } finally {
    btn.disabled = false;
  }
});
</script>
</body>
</html>`;
}

async function exchangeToken(code, codeVerifier, redirectUri) {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: CLIENT_ID,
    code,
    redirect_uri: redirectUri,
    code_verifier: codeVerifier,
  });
  const resp = await fetch(`https://${COGNITO_DOMAIN}/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });
  const data = await resp.json();
  return { ok: resp.ok, data };
}

async function callMcpEndpoint(runtimeArn, accessToken, method, params, sessionId) {
  const encodedArn = encodeURIComponent(runtimeArn);
  const url = `${MCP_ENDPOINT_BASE}/runtimes/${encodedArn}/invocations?qualifier=DEFAULT`;
  const headers = {
    Authorization: `Bearer ${accessToken}`,
    "Content-Type": "application/json",
    Accept: "application/json, text/event-stream",
  };
  if (sessionId) headers["Mcp-Session-Id"] = sessionId;
  const resp = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  const text = await resp.text();
  return { status: resp.status, text, sessionId: resp.headers.get("mcp-session-id") };
}

// v2(2026-07-28)の"新世代クライアント"形式: initializeハンドシェイクを行わず、
// 各リクエストの_metaでプロトコルバージョンを自己申告する(docs/12 §7参照)。
async function callMcpEndpointModern(runtimeArn, accessToken, method, params) {
  const encodedArn = encodeURIComponent(runtimeArn);
  const url = `${MCP_ENDPOINT_BASE}/runtimes/${encodedArn}/invocations?qualifier=DEFAULT`;
  const resp = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
      "MCP-Protocol-Version": "2026-07-28",
      "Mcp-Method": method,
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method,
      params: {
        ...params,
        _meta: {
          "io.modelcontextprotocol/protocolVersion": "2026-07-28",
          "io.modelcontextprotocol/clientCapabilities": {},
        },
      },
    }),
  });
  const text = await resp.text();
  return { status: resp.status, text };
}

// --- MCPプロトコルv2 SDKデモ ---
function isSuccessfulMcpResponse(status, text) {
  if (status < 200 || status >= 300) return false;
  // SSE形式("event: message\ndata: {...}")で返ることがあるため、data:行を抽出してからJSON化する
  const dataLine = text.split("\n").find((line) => line.startsWith("data: "));
  const jsonText = dataLine ? dataLine.slice("data: ".length) : text;
  const parsed = safeJsonParse(jsonText);
  return typeof parsed === "object" && parsed !== null && "result" in parsed;
}

async function runSdkDemo() {
  const token = await getM2mToken();
  const [v1Classic, v1Modern, v2Classic, v2Modern] = await Promise.all([
    callMcpEndpoint(SDK_DEMO_V1_RUNTIME_ARN, token, "tools/list", {}),
    callMcpEndpointModern(SDK_DEMO_V1_RUNTIME_ARN, token, "tools/list", {}),
    callMcpEndpoint(SDK_DEMO_V2_RUNTIME_ARN, token, "tools/list", {}),
    callMcpEndpointModern(SDK_DEMO_V2_RUNTIME_ARN, token, "tools/list", {}),
  ]);
  return {
    v1: {
      classic: isSuccessfulMcpResponse(v1Classic.status, v1Classic.text),
      modern: isSuccessfulMcpResponse(v1Modern.status, v1Modern.text),
    },
    v2: {
      classic: isSuccessfulMcpResponse(v2Classic.status, v2Classic.text),
      modern: isSuccessfulMcpResponse(v2Modern.status, v2Modern.text),
    },
  };
}

// --- 応答時間デモ: client_credentialsでトークン取得しLatencyLab Runtimeを呼ぶ ---
async function getM2mToken() {
  const basic = Buffer.from(`${M2M_CLIENT_ID}:${M2M_CLIENT_SECRET}`).toString("base64");
  const body = new URLSearchParams({ grant_type: "client_credentials", scope: "mcp/invoke" });
  const resp = await fetch(`https://${COGNITO_DOMAIN}/oauth2/token`, {
    method: "POST",
    headers: { Authorization: `Basic ${basic}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });
  const data = await resp.json();
  if (!resp.ok) throw new Error(`m2m token取得に失敗: ${JSON.stringify(data)}`);
  return data.access_token;
}

// --- DCRデモ ---
async function dcrSelfRegister() {
  const resp = await fetch(`${PATTERN4_API_BASE}/register`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      client_name: `web-demo-dcr-${Date.now()}`,
      grant_types: ["client_credentials"],
      token_endpoint_auth_method: "client_secret_basic",
      scope: "mcp/invoke",
    }),
  });
  const data = await resp.json();
  if (!resp.ok) throw new Error(`register失敗: ${JSON.stringify(data)}`);
  return data;
}

async function dcrGetToken(clientId, clientSecret) {
  const basic = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
  const body = new URLSearchParams({ grant_type: "client_credentials", scope: PATTERN4_SCOPE });
  const resp = await fetch(`https://${PATTERN4_COGNITO_DOMAIN}/oauth2/token`, {
    method: "POST",
    headers: { Authorization: `Basic ${basic}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });
  const data = await resp.json();
  if (!resp.ok) throw new Error(`token取得失敗: ${JSON.stringify(data)}`);
  return data.access_token;
}

async function dcrInvokeMcp(accessToken) {
  const resp = await fetch(`${PATTERN4_API_BASE}/mcp`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
    },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }),
  });
  return resp.status;
}

async function runDcrDemo() {
  const steps = [];
  const reg = await dcrSelfRegister();
  steps.push({ description: `自己登録: POST /register → client_id発行(${reg.client_id})`, httpStatus: 201, pass: true });

  const token = await dcrGetToken(reg.client_id, reg.client_secret);

  const status1 = await dcrInvokeMcp(token);
  steps.push({
    description: "登録直後にMCP呼び出し → 未承認のためアクセス拒否(登録=即座にフルアクセスにはならない設計)",
    httpStatus: status1,
    pass: status1 !== 200,
  });

  await ddb.send(new PutCommand({
    TableName: USERS_TABLE_NAME,
    Item: { PK: `USER#${reg.client_id}`, services: { quick: { plan: "standard" } } },
  }));
  steps.push({ description: "管理者操作: サービスアカウントとして承認(DynamoDBにレコード追加)", httpStatus: 200, pass: true });

  const status2 = await dcrInvokeMcp(token);
  steps.push({ description: "承認後に同じトークンで再度呼び出し → 成功", httpStatus: status2, pass: status2 === 200 });

  await ddb.send(new UpdateCommand({
    TableName: USERS_TABLE_NAME,
    Key: { PK: `CLIENT#${reg.client_id}` },
    UpdateExpression: "SET #s = :revoked",
    ExpressionAttributeNames: { "#s": "status" },
    ExpressionAttributeValues: { ":revoked": "revoked" },
  }));
  steps.push({ description: "管理者操作: クライアントを失効(status=revoked)", httpStatus: 200, pass: true });

  const status3 = await dcrInvokeMcp(token);
  steps.push({
    description: "失効後、同じ(暗号学的に有効な)トークンで再度呼び出し → 即座にアクセス拒否",
    httpStatus: status3,
    pass: status3 !== 200,
  });

  // クリーンアップ(デモ環境を汚さない)
  await Promise.allSettled([
    cognitoAdmin.send(new DeleteUserPoolClientCommand({ UserPoolId: PATTERN4_USER_POOL_ID, ClientId: reg.client_id })),
    ddb.send(new DeleteCommand({ TableName: USERS_TABLE_NAME, Key: { PK: `CLIENT#${reg.client_id}` } })),
    ddb.send(new DeleteCommand({ TableName: USERS_TABLE_NAME, Key: { PK: `USER#${reg.client_id}` } })),
  ]);

  return steps;
}

// --- WAFデモ ---
async function runWafDemo() {
  const results = [];
  for (const probe of WAF_PROBES) {
    const resp = await fetch(`${MCP_ENDPOINT_BASE}/${probe.query}`);
    results.push({ label: probe.label, httpStatus: resp.status, blocked: resp.status === 403 });
  }
  return results;
}

export const handler = async (event) => {
  const path = event.rawPath || "/";
  const method = event.requestContext?.http?.method || "GET";
  const origin = `https://${event.requestContext.domainName}`;

  try {
    if (method === "POST" && path === "/api/token") {
      const body = JSON.parse(event.body || "{}");
      const { ok, data } = await exchangeToken(body.code, body.code_verifier, body.redirect_uri);
      return { statusCode: ok ? 200 : 400, headers: { "Content-Type": "application/json" }, body: JSON.stringify(data) };
    }

    if (method === "POST" && path === "/api/mcp") {
      const body = JSON.parse(event.body || "{}");
      const result = await callMcpEndpoint(AGENT_RUNTIME_ARN, body.access_token, body.method, body.params || {});
      return {
        statusCode: 200,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ upstream_status: result.status, body: safeJsonParse(result.text) }),
      };
    }

    if (method === "POST" && path === "/api/latency-demo") {
      const token = await getM2mToken();

      let t0 = Date.now();
      const baseline = await callMcpEndpoint(LATENCY_LAB_RUNTIME_ARN, token, "tools/list", {});
      const baselineElapsed = (Date.now() - t0) / 1000;

      t0 = Date.now();
      const treatment = await callMcpEndpoint(LATENCY_LAB_RUNTIME_ARN, token, "tools/list", {}, baseline.sessionId);
      const treatmentElapsed = (Date.now() - t0) / 1000;

      t0 = Date.now();
      const control = await callMcpEndpoint(LATENCY_LAB_RUNTIME_ARN, token, "tools/list", {});
      const controlElapsed = (Date.now() - t0) / 1000;

      return {
        statusCode: 200,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          results: [
            { label: "ベースライン(新規コンテナ起動)", elapsedSeconds: baselineElapsed, sessionReused: false },
            { label: "同一セッションID再送(コンテナ再利用)", elapsedSeconds: treatmentElapsed, sessionReused: true },
            { label: "新規セッション相当(比較用)", elapsedSeconds: controlElapsed, sessionReused: false },
          ],
        }),
      };
    }

    if (method === "POST" && path === "/api/dcr-demo") {
      const steps = await runDcrDemo();
      return { statusCode: 200, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ steps }) };
    }

    if (method === "POST" && path === "/api/waf-demo") {
      const results = await runWafDemo();
      return { statusCode: 200, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ results }) };
    }

    if (method === "POST" && path === "/api/sdk-demo") {
      const result = await runSdkDemo();
      return { statusCode: 200, headers: { "Content-Type": "application/json" }, body: JSON.stringify(result) };
    }
  } catch (e) {
    return { statusCode: 500, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: e.message }) };
  }

  return {
    statusCode: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" },
    body: html(origin + "/"),
  };
};

function safeJsonParse(text) {
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

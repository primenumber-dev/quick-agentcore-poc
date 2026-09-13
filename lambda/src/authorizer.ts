import type { APIGatewaySimpleAuthorizerWithContextResult, APIGatewayRequestAuthorizerEventV2 } from "aws-lambda";
import { CognitoJwtVerifier } from "aws-jwt-verify";
import { getClientRecord } from "./shared/db.js";

// DCRで動的に増えるclient_idに対応するため、JWT型Authorizerの固定audienceリストを
// 廃止しこのLambda Authorizerに置き換えた(docs/08-weekly-verification-plan.md §2.1)。
// clientId: null によりCognitoプールに属する任意のクライアントのアクセストークンを受理し、
// 失効管理はDynamoDBのCLIENT#レコードで個別に行う。
const verifier = CognitoJwtVerifier.create({
  userPoolId: process.env.USER_POOL_ID!,
  tokenUse: "access",
  clientId: null,
});

// セキュリティレビュー(2026-09-02)で指摘: clientId:null はプール内の任意のクライアントの
// トークンを受理するため、scopeクレームも合わせて確認しないと「MCP呼び出し用に発行された
// わけではないトークン」まで通ってしまう(confused deputy)。invokeスコープの保有を必須にする。
const REQUIRED_SCOPE = process.env.REQUIRED_SCOPE!;

// MCP-03: MCPサーバーはトークンが自分宛か(audience)を MUST 検証する。Cognito は認可コードフローの
// resource パラメータ(RFC 8707)で aud を付与する(docs/19 §2.1 F1)。client_credentials トークンには
// aud が付かないため、aud が無い場合は client_id + CLIENT# の照合で代替する。
const RESOURCE_SERVER_IDENTIFIER = process.env.RESOURCE_SERVER_IDENTIFIER ?? "";
// resource 付きトークンを必須にするか(true にすると aud 無しの authorization_code トークンも拒否)。
// Claude が実際に resource を送るかを E2E で確認するまでは false。
const REQUIRE_AUDIENCE_FOR_USER_TOKENS = (process.env.REQUIRE_AUDIENCE_FOR_USER_TOKENS ?? "false") === "true";

// MCP-04: 無効・期限切れトークンには 401 を返す必要がある(Claude は 401 でのみリフレッシュする)。
// HTTP API の Lambda Authorizer(simple response)は isAuthorized:false を 403 にするため、
// DENY_MODE=throw では例外を投げて API Gateway 側の応答コードを観測する(docs/19 §2.4-a の試行)。
const DENY_MODE = process.env.DENY_MODE ?? "deny";

type Context = { sub: string; clientId: string };

const DENY: APIGatewaySimpleAuthorizerWithContextResult<Context> = {
  isAuthorized: false,
  context: { sub: "", clientId: "" },
};

function deny(reason: string): APIGatewaySimpleAuthorizerWithContextResult<Context> {
  console.log(JSON.stringify({ decision: "deny", reason }));
  if (DENY_MODE === "throw") throw new Error("Unauthorized");
  return DENY;
}

export async function handler(
  event: APIGatewayRequestAuthorizerEventV2
): Promise<APIGatewaySimpleAuthorizerWithContextResult<Context>> {
  const authHeader = event.headers?.authorization ?? event.headers?.Authorization;
  if (!authHeader?.startsWith("Bearer ")) return deny("missing_bearer");
  const token = authHeader.slice("Bearer ".length);

  let payload;
  try {
    payload = await verifier.verify(token);
  } catch (e) {
    return deny(`jwt_invalid:${(e as Error).name}`);
  }

  const clientId = payload.client_id as string;
  if (!clientId) return deny("missing_client_id");

  const scopes = ((payload.scope as string) ?? "").split(" ");
  if (!scopes.includes(REQUIRED_SCOPE)) return deny("missing_scope");

  // audience 検証(MCP-03)。aud は文字列または配列で来る可能性がある。
  const aud = payload.aud as string | string[] | undefined;
  if (aud !== undefined) {
    const auds = Array.isArray(aud) ? aud : [aud];
    if (RESOURCE_SERVER_IDENTIFIER && !auds.includes(RESOURCE_SERVER_IDENTIFIER)) return deny("aud_mismatch");
  } else if (REQUIRE_AUDIENCE_FOR_USER_TOKENS && payload.sub) {
    return deny("aud_missing");
  }

  // AUTHZ-01: deny-on-missing。CLIENT# レコードが無いクライアント(管理外)は拒否する。
  // 静的クライアントには source:"static" の CLIENT# を投入しておく(docs/19 §2.4-d)。
  const record = await getClientRecord(clientId);
  if (!record || record.status !== "active") return deny(record ? `client_${record.status}` : "client_unknown");

  // client_credentialsトークンにsubクレームは無いため、
  // 00-handoff.md「追加調査 2026-08-26」のM2Mパターン通りclient_idで代替する。
  const sub = (payload.sub as string) ?? clientId;

  return { isAuthorized: true, context: { sub, clientId } };
}

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

type Context = { sub: string; clientId: string };

export async function handler(
  event: APIGatewayRequestAuthorizerEventV2
): Promise<APIGatewaySimpleAuthorizerWithContextResult<Context>> {
  const deny: APIGatewaySimpleAuthorizerWithContextResult<Context> = {
    isAuthorized: false,
    context: { sub: "", clientId: "" },
  };

  const authHeader = event.headers?.authorization ?? event.headers?.Authorization;
  if (!authHeader?.startsWith("Bearer ")) return deny;
  const token = authHeader.slice("Bearer ".length);

  let payload;
  try {
    payload = await verifier.verify(token);
  } catch {
    return deny;
  }

  const clientId = payload.client_id as string;
  if (!clientId) return deny;

  const record = await getClientRecord(clientId);
  if (record && record.status === "revoked") return deny;

  // client_credentialsトークンにsubクレームは無いため、
  // 00-handoff.md「追加調査 2026-08-26」のM2Mパターン通りclient_idで代替する。
  const sub = (payload.sub as string) ?? clientId;

  return { isAuthorized: true, context: { sub, clientId } };
}

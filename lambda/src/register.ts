import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from "aws-lambda";
import {
  CognitoIdentityProviderClient,
  CreateUserPoolClientCommand,
  DeleteUserPoolClientCommand,
} from "@aws-sdk/client-cognito-identity-provider";
import { putClientRecord, deleteClientRecord } from "./shared/db.js";

const cognito = new CognitoIdentityProviderClient({});
const USER_POOL_ID = process.env.USER_POOL_ID!;
const RESOURCE_SERVER_IDENTIFIER = process.env.RESOURCE_SERVER_IDENTIFIER!;
const ALLOWED_REDIRECT_HOSTS = (process.env.ALLOWED_REDIRECT_HOSTS ?? "")
  .split(",")
  .map((h) => h.trim())
  .filter(Boolean);

const AUTH_METHODS = new Set(["none", "client_secret_basic", "client_secret_post"]);
const GRANT_TYPES = new Set(["authorization_code", "refresh_token", "client_credentials"]);

function json(status: number, body: unknown): APIGatewayProxyResultV2 {
  return { statusCode: status, headers: { "content-type": "application/json" }, body: JSON.stringify(body) };
}

function isAllowedRedirect(uri: string): boolean {
  try {
    const u = new URL(uri);
    if (u.protocol === "http:" && (u.hostname === "localhost" || u.hostname === "127.0.0.1")) return true;
    if (u.protocol !== "https:") return false;
    return ALLOWED_REDIRECT_HOSTS.includes(u.hostname);
  } catch {
    return false;
  }
}

export async function handler(event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> {
  let req: Record<string, unknown>;
  try {
    req = JSON.parse(event.body ?? "{}");
  } catch {
    return json(400, { error: "invalid_client_metadata", error_description: "body must be JSON" });
  }

  const clientName = typeof req.client_name === "string" ? req.client_name : "dcr-client";
  const redirectUris = Array.isArray(req.redirect_uris) ? (req.redirect_uris as string[]) : [];
  const tokenEndpointAuthMethod =
    typeof req.token_endpoint_auth_method === "string" ? req.token_endpoint_auth_method : "none";
  const grantTypes = Array.isArray(req.grant_types) ? (req.grant_types as string[]) : ["authorization_code"];

  if (!AUTH_METHODS.has(tokenEndpointAuthMethod)) {
    return json(400, { error: "invalid_client_metadata", error_description: "unsupported token_endpoint_auth_method" });
  }
  if (!grantTypes.every((g) => GRANT_TYPES.has(g))) {
    return json(400, { error: "invalid_client_metadata", error_description: "unsupported grant_types" });
  }
  const isClientCredentials = grantTypes.includes("client_credentials");
  const isAuthCode = grantTypes.includes("authorization_code");
  if (!isClientCredentials && !isAuthCode) {
    return json(400, { error: "invalid_client_metadata", error_description: "grant_types must include authorization_code or client_credentials" });
  }
  if (isAuthCode) {
    if (redirectUris.length === 0) {
      return json(400, { error: "invalid_redirect_uri", error_description: "redirect_uris required for authorization_code" });
    }
    if (!redirectUris.every(isAllowedRedirect)) {
      return json(400, { error: "invalid_redirect_uri", error_description: "redirect_uri host not allowed" });
    }
  }

  const allowedOAuthFlows: string[] = [];
  if (isAuthCode) allowedOAuthFlows.push("code");
  if (isClientCredentials) allowedOAuthFlows.push("client_credentials");

  const allowedOAuthScopes = isClientCredentials
    ? [`${RESOURCE_SERVER_IDENTIFIER}/invoke`]
    : ["openid", "email", "profile", `${RESOURCE_SERVER_IDENTIFIER}/invoke`];

  const generateSecret = tokenEndpointAuthMethod !== "none";
  const safeSuffix = Math.random().toString(16).slice(2, 10);

  let clientId: string;
  let clientSecret: string | undefined;
  try {
    const created = await cognito.send(
      new CreateUserPoolClientCommand({
        UserPoolId: USER_POOL_ID,
        ClientName: `dcr-${clientName.replace(/[^a-zA-Z0-9._-]/g, "-").slice(0, 40)}-${safeSuffix}`,
        GenerateSecret: generateSecret,
        AllowedOAuthFlows: allowedOAuthFlows as never,
        AllowedOAuthFlowsUserPoolClient: true,
        AllowedOAuthScopes: allowedOAuthScopes,
        SupportedIdentityProviders: ["COGNITO"],
        CallbackURLs: isAuthCode ? redirectUris : undefined,
        ExplicitAuthFlows: isClientCredentials ? undefined : ["ALLOW_REFRESH_TOKEN_AUTH"],
        EnableTokenRevocation: true,
        PreventUserExistenceErrors: "ENABLED",
      })
    );
    clientId = created.UserPoolClient!.ClientId!;
    clientSecret = created.UserPoolClient!.ClientSecret;
  } catch (e) {
    console.error("CreateUserPoolClient failed", e);
    return json(500, { error: "server_error", error_description: "failed to create client" });
  }

  const nowIso = new Date().toISOString();
  try {
    await putClientRecord({
      PK: `CLIENT#${clientId}`,
      clientName,
      redirectUris,
      tokenEndpointAuthMethod,
      grantTypes,
      createdAt: nowIso,
      status: "active",
      source: "dcr",
    });
    // セキュリティレビュー(2026-09-02)で指摘: 以前はここで client_credentials 登録に
    // USER#<clientId> を自動作成し、他の招待済みテナントと同じ "standard" プランの
    // サービスアクセスを無審査で即座に付与していた。resolveAuthorization()
    // (server/src/auth.ts) はUSER#レコードの有無だけでアクセスを許可し、
    // services.plan の値自体はツール登録(registerQuickTools)では一切参照されないため、
    // 実質「登録した瞬間に無審査でフルアクセスを付与する」ことと同義だった。
    // クライアント登録(このLambda)とテナントとしての利用許可(invite-user相当の
    // 人手の審査)を分離し、USER#レコードの作成は引き続き admin 操作のみとする。
  } catch (e) {
    console.error("DynamoDB provisioning failed, rolling back Cognito client", e);
    try {
      await deleteClientRecord(clientId);
      await cognito.send(new DeleteUserPoolClientCommand({ UserPoolId: USER_POOL_ID, ClientId: clientId }));
    } catch (rollbackErr) {
      console.error("Rollback also failed — orphaned client", clientId, rollbackErr);
    }
    return json(500, { error: "server_error", error_description: "failed to provision client" });
  }

  return json(201, {
    client_id: clientId,
    ...(clientSecret ? { client_secret: clientSecret } : {}),
    client_id_issued_at: Math.floor(Date.now() / 1000),
    client_secret_expires_at: 0,
    client_name: clientName,
    redirect_uris: redirectUris,
    token_endpoint_auth_method: tokenEndpointAuthMethod,
    grant_types: grantTypes,
    response_types: isAuthCode ? ["code"] : [],
    scope: allowedOAuthScopes.join(" "),
  });
}

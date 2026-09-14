import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from "aws-lambda";
import {
  CognitoIdentityProviderClient,
  CreateUserPoolClientCommand,
  CreateManagedLoginBrandingCommand,
  DeleteManagedLoginBrandingCommand,
  DeleteUserPoolClientCommand,
} from "@aws-sdk/client-cognito-identity-provider";
import {
  putClientRecord,
  deleteClientRecord,
  incrementRegistrationCounter,
  decrementRegistrationCounter,
  incrementIpCounter,
  LimitExceeded,
  type ClientRecord,
} from "./shared/db.js";

// RFC 7591 Dynamic Client Registration。準拠性チェックリスト(docs/20 §3)の各IDに対応する箇所を
// コメントで示す。修正の経緯は docs/19-weekly-verification-plan-week5.md §2。

const cognito = new CognitoIdentityProviderClient({});
const USER_POOL_ID = process.env.USER_POOL_ID!;
const RESOURCE_SERVER_IDENTIFIER = process.env.RESOURCE_SERVER_IDENTIFIER!;
const ALLOWED_REDIRECT_HOSTS = (process.env.ALLOWED_REDIRECT_HOSTS ?? "")
  .split(",")
  .map((h) => h.trim())
  .filter(Boolean);
// 7591-04: RFC 7591 の既定は client_secret_basic。Claude Code / Claude.ai が実際に
// token_endpoint_auth_method を明示送信するかを E2E で確認するまでは、既存挙動(none)を既定にする。
const DEFAULT_AUTH_METHOD = process.env.DEFAULT_TOKEN_ENDPOINT_AUTH_METHOD ?? "none";
const MAX_DCR_CLIENTS = Number(process.env.MAX_DCR_CLIENTS ?? "200");
const MAX_REGISTRATIONS_PER_IP_PER_MINUTE = Number(process.env.MAX_REGISTRATIONS_PER_IP_PER_MINUTE ?? "5");
const ACCESS_TOKEN_VALIDITY_MINUTES = Number(process.env.ACCESS_TOKEN_VALIDITY_MINUTES ?? "60");
const APPLY_MANAGED_LOGIN_BRANDING = (process.env.APPLY_MANAGED_LOGIN_BRANDING ?? "true") === "true";

const AUTH_METHODS = new Set(["none", "client_secret_basic", "client_secret_post"]);
const GRANT_TYPES = new Set(["authorization_code", "refresh_token", "client_credentials"]);
const MAX_REDIRECT_URIS = 100; // Cognito CallbackURLs の上限
const MAX_CLIENT_NAME_LENGTH = 128; // Cognito ClientName の上限

// 7591-10: 資格情報を含む応答はキャッシュさせない(RFC 7591 §3.2.1、RFC 6749 §5.1)
const NO_STORE_HEADERS = {
  "content-type": "application/json",
  "cache-control": "no-store",
  pragma: "no-cache",
};

function json(status: number, body: unknown, extraHeaders: Record<string, string> = {}): APIGatewayProxyResultV2 {
  return { statusCode: status, headers: { ...NO_STORE_HEADERS, ...extraHeaders }, body: JSON.stringify(body) };
}

// 7591-09: RFC 7591 §3.2.2 のエラー形式。定義済みコードのみ使う。
function rfcError(status: number, error: "invalid_redirect_uri" | "invalid_client_metadata" | "server_error", description: string, extraHeaders: Record<string, string> = {}) {
  return json(status, { error, error_description: description }, extraHeaders);
}

function isAllowedRedirect(uri: string): boolean {
  try {
    const u = new URL(uri);
    // 7591-06: フラグメント付きは RFC 6749 §3.1.2 で禁止。Cognito に投げる前に拒否する。
    if (u.hash) return false;
    if (u.protocol === "http:" && (u.hostname === "localhost" || u.hostname === "127.0.0.1")) return true;
    if (u.protocol !== "https:") return false;
    return ALLOWED_REDIRECT_HOSTS.includes(u.hostname);
  } catch {
    return false;
  }
}

function stringArray(v: unknown): string[] | undefined {
  return Array.isArray(v) && v.every((x) => typeof x === "string") ? (v as string[]) : undefined;
}

function optionalString(v: unknown, max = 2048): string | undefined {
  return typeof v === "string" && v.length <= max ? v : undefined;
}

// Cognito の例外を RFC 7591 のエラーに翻訳する(7591-09: 400 系を 500 にしない)
function translateCognitoError(e: unknown): APIGatewayProxyResultV2 {
  const name = (e as { name?: string }).name ?? "";
  const message = (e as { message?: string }).message ?? "";
  if (name === "InvalidParameterException" || name === "InvalidOAuthFlowException" || name === "ScopeDoesNotExistException") {
    const isRedirect = /callback|redirect|logout url/i.test(message);
    return rfcError(400, isRedirect ? "invalid_redirect_uri" : "invalid_client_metadata", message.slice(0, 200));
  }
  if (name === "LimitExceededException" || name === "TooManyRequestsException") {
    return rfcError(429, "invalid_client_metadata", "registration temporarily unavailable, retry later", { "retry-after": "60" });
  }
  console.error("CreateUserPoolClient failed", e);
  return rfcError(500, "server_error", "failed to create client");
}

export async function handler(event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> {
  let req: Record<string, unknown>;
  try {
    req = JSON.parse(event.body ?? "{}");
    if (typeof req !== "object" || req === null || Array.isArray(req)) throw new Error("not an object");
  } catch {
    return rfcError(400, "invalid_client_metadata", "body must be a JSON object");
  }

  const sourceIp = event.requestContext?.http?.sourceIp ?? "unknown";

  // --- メタデータの読み取りと検証(RFC 7591 §2) ---
  const clientNameRaw = typeof req.client_name === "string" ? req.client_name : "dcr-client";
  if (clientNameRaw.length > MAX_CLIENT_NAME_LENGTH) {
    return rfcError(400, "invalid_client_metadata", `client_name must be at most ${MAX_CLIENT_NAME_LENGTH} characters`);
  }
  const clientName = clientNameRaw;

  const redirectUris = stringArray(req.redirect_uris) ?? [];
  if (req.redirect_uris !== undefined && !Array.isArray(req.redirect_uris)) {
    return rfcError(400, "invalid_redirect_uri", "redirect_uris must be an array of strings");
  }
  if (redirectUris.length > MAX_REDIRECT_URIS) {
    return rfcError(400, "invalid_redirect_uri", `at most ${MAX_REDIRECT_URIS} redirect_uris are supported`);
  }

  const tokenEndpointAuthMethod =
    typeof req.token_endpoint_auth_method === "string" ? req.token_endpoint_auth_method : DEFAULT_AUTH_METHOD;
  if (!AUTH_METHODS.has(tokenEndpointAuthMethod)) {
    return rfcError(400, "invalid_client_metadata", "unsupported token_endpoint_auth_method");
  }

  const grantTypes = stringArray(req.grant_types) ?? ["authorization_code"];
  if (grantTypes.length === 0 || !grantTypes.every((g) => GRANT_TYPES.has(g))) {
    return rfcError(400, "invalid_client_metadata", "unsupported grant_types");
  }
  const isClientCredentials = grantTypes.includes("client_credentials");
  const isAuthCode = grantTypes.includes("authorization_code");
  if (!isClientCredentials && !isAuthCode) {
    return rfcError(400, "invalid_client_metadata", "grant_types must include authorization_code or client_credentials");
  }
  // 7591-09d: Cognito は client_credentials に secret を要求する。Cognito の 400 を待たずに拒否する。
  if (isClientCredentials && tokenEndpointAuthMethod === "none") {
    return rfcError(400, "invalid_client_metadata", "client_credentials requires client_secret_basic or client_secret_post");
  }

  // 7591-05: response_types と grant_types の整合性(RFC 7591 §2.1)。authorization_code ⇔ code のみ対応。
  const responseTypes = stringArray(req.response_types) ?? (isAuthCode ? ["code"] : []);
  if (req.response_types !== undefined && stringArray(req.response_types) === undefined) {
    return rfcError(400, "invalid_client_metadata", "response_types must be an array of strings");
  }
  if (isAuthCode && !(responseTypes.length === 1 && responseTypes[0] === "code")) {
    return rfcError(400, "invalid_client_metadata", "response_types must be [\"code\"] for authorization_code");
  }
  if (!isAuthCode && responseTypes.length > 0) {
    return rfcError(400, "invalid_client_metadata", "response_types must be empty without authorization_code");
  }

  if (isAuthCode) {
    if (redirectUris.length === 0) {
      return rfcError(400, "invalid_redirect_uri", "redirect_uris required for authorization_code");
    }
    if (!redirectUris.every(isAllowedRedirect)) {
      return rfcError(400, "invalid_redirect_uri", "redirect_uri host not allowed, or fragment present");
    }
  }

  // 7591-12: 任意メタデータは自己申告として保存のみ(同意画面には出せない)。RFC 7591 §5 のホスト一致は警告ログ。
  const extra = {
    clientUri: optionalString(req.client_uri),
    logoUri: optionalString(req.logo_uri),
    tosUri: optionalString(req.tos_uri),
    policyUri: optionalString(req.policy_uri),
    contacts: stringArray(req.contacts)?.slice(0, 10),
    softwareId: optionalString(req.software_id, 256),
    softwareVersion: optionalString(req.software_version, 64),
  };
  for (const [k, v] of Object.entries({ client_uri: extra.clientUri, logo_uri: extra.logoUri, tos_uri: extra.tosUri, policy_uri: extra.policyUri })) {
    if (!v) continue;
    try {
      const host = new URL(v).hostname;
      const redirectHosts = redirectUris.map((r) => new URL(r).hostname);
      if (redirectHosts.length > 0 && !redirectHosts.includes(host)) console.warn(`metadata ${k} host ${host} differs from redirect_uris hosts`, redirectHosts);
    } catch {
      return rfcError(400, "invalid_client_metadata", `${k} must be a valid URL`);
    }
  }

  // --- 乱用対策(RFC 7591 §5、docs/19 §2.4-d) ---
  try {
    await incrementIpCounter(sourceIp, MAX_REGISTRATIONS_PER_IP_PER_MINUTE);
  } catch (e) {
    if (e instanceof LimitExceeded) return rfcError(429, "invalid_client_metadata", "too many registrations from this address", { "retry-after": "60" });
    console.error("ip counter failed (continuing)", e);
  }
  let counted = false;
  try {
    await incrementRegistrationCounter(MAX_DCR_CLIENTS);
    counted = true;
  } catch (e) {
    if (e instanceof LimitExceeded) return rfcError(429, "invalid_client_metadata", "registration limit reached, contact the operator", { "retry-after": "3600" });
    console.error("registration counter failed (continuing)", e);
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
  let brandingId: string | undefined;
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
        // OAuth 認可コードフローのリフレッシュは /oauth2/token 経由で行われ ExplicitAuthFlows を要しない。
        // Cognito はリフレッシュトークンローテーション有効時に ALLOW_REFRESH_TOKEN_AUTH の併用を拒否する
        // (2026-09-13 実機: "ALLOW_REFRESH_TOKEN_AUTH is not a permitted ExplicitAuthFlow when refresh token rotation is enabled")。
        ExplicitAuthFlows: undefined,
        EnableTokenRevocation: true,
        PreventUserExistenceErrors: "ENABLED",
        AccessTokenValidity: ACCESS_TOKEN_VALIDITY_MINUTES,
        TokenValidityUnits: { AccessToken: "minutes" },
        // MCP-05: 公開クライアントのリフレッシュトークンは MUST ローテーション(MCP Authorization、RFC 9700 §2.2.2)
        RefreshTokenRotation: !isClientCredentials ? { Feature: "ENABLED", RetryGracePeriodSeconds: 30 } : undefined,
      })
    );
    clientId = created.UserPoolClient!.ClientId!;
    clientSecret = created.UserPoolClient!.ClientSecret;
  } catch (e) {
    if (counted) await decrementRegistrationCounter().catch(() => undefined);
    return translateCognitoError(e);
  }

  const rollback = async (reason: string, err: unknown) => {
    console.error(`${reason}, rolling back Cognito client`, err);
    try {
      await deleteClientRecord(clientId);
      if (brandingId) {
        await cognito.send(new DeleteManagedLoginBrandingCommand({ UserPoolId: USER_POOL_ID, ManagedLoginBrandingId: brandingId })).catch(() => undefined);
      }
      await cognito.send(new DeleteUserPoolClientCommand({ UserPoolId: USER_POOL_ID, ClientId: clientId }));
      if (counted) await decrementRegistrationCounter();
    } catch (rollbackErr) {
      console.error("Rollback also failed - orphaned client", clientId, rollbackErr);
    }
  };

  // CL-03: CreateUserPoolClient で作ったクライアントには Managed Login のブランディングが割り当てられず、
  // 割り当てるまで Hosted UI が表示されない(Cognito API 仕様)。認可コードフローのクライアントには
  // Cognito 既定スタイルを適用する。
  if (isAuthCode && APPLY_MANAGED_LOGIN_BRANDING) {
    try {
      const branding = await cognito.send(
        new CreateManagedLoginBrandingCommand({ UserPoolId: USER_POOL_ID, ClientId: clientId, UseCognitoProvidedValues: true })
      );
      brandingId = branding.ManagedLoginBranding?.ManagedLoginBrandingId;
    } catch (e) {
      await rollback("CreateManagedLoginBranding failed", e);
      return rfcError(500, "server_error", "failed to provision login page for client");
    }
  }

  const nowIso = new Date().toISOString();
  const record: ClientRecord = {
    PK: `CLIENT#${clientId}`,
    clientName,
    redirectUris,
    tokenEndpointAuthMethod,
    grantTypes,
    responseTypes,
    createdAt: nowIso,
    status: "active",
    source: "dcr",
    registrationIp: sourceIp,
    ...Object.fromEntries(Object.entries(extra).filter(([, v]) => v !== undefined)),
  };
  try {
    await putClientRecord(record);
    // セキュリティレビュー(2026-09-02)で指摘: 以前はここで client_credentials 登録に
    // USER#<clientId> を自動作成し、無審査でサービスアクセスを付与していた。
    // クライアント登録(このLambda)とテナントとしての利用許可(invite-user相当の人手の審査)を
    // 分離し、USER#レコードの作成は引き続き admin 操作のみとする(docs/18 §1.1、CL-06)。
  } catch (e) {
    await rollback("DynamoDB provisioning failed", e);
    return rfcError(500, "server_error", "failed to provision client");
  }

  // 7591-03: 登録済みメタデータ(サーバーが置換した値を含む)をすべて返す。
  // 7591-07: client_secret_expires_at は secret を発行したときのみ。
  return json(201, {
    client_id: clientId,
    ...(clientSecret ? { client_secret: clientSecret, client_secret_expires_at: 0 } : {}),
    client_id_issued_at: Math.floor(Date.now() / 1000),
    client_name: clientName,
    redirect_uris: redirectUris,
    token_endpoint_auth_method: tokenEndpointAuthMethod,
    grant_types: grantTypes,
    response_types: responseTypes,
    scope: allowedOAuthScopes.join(" "),
    ...(extra.clientUri ? { client_uri: extra.clientUri } : {}),
    ...(extra.logoUri ? { logo_uri: extra.logoUri } : {}),
    ...(extra.tosUri ? { tos_uri: extra.tosUri } : {}),
    ...(extra.policyUri ? { policy_uri: extra.policyUri } : {}),
    ...(extra.contacts ? { contacts: extra.contacts } : {}),
    ...(extra.softwareId ? { software_id: extra.softwareId } : {}),
    ...(extra.softwareVersion ? { software_version: extra.softwareVersion } : {}),
  });
}

import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  DeleteCommand,
  UpdateCommand,
} from "@aws-sdk/lib-dynamodb";

// テーブル名は環境変数で注入する(docs/19 §2.1 F12: 3コンポーネント + IAM で同じ名前を使う)。
// 既定値は後方互換のため従来のハードコード値。
const TABLE_NAME = process.env.TABLE_NAME ?? "quick-mcp-poc-users";

export const docClient = DynamoDBDocumentClient.from(new DynamoDBClient({}));

export interface ClientRecord {
  PK: string;
  clientName: string;
  redirectUris: string[];
  tokenEndpointAuthMethod: string;
  grantTypes: string[];
  responseTypes?: string[];
  createdAt: string;
  status: "active" | "revoked";
  // dcr: /register で自己登録、static: terraform 管理の固定クライアント(deny-on-missing 対応で投入)
  source: "dcr" | "static";
  // RFC 7591 §2 の任意メタデータ。同意画面には出せないが監査・管理用に保存する。
  clientUri?: string;
  logoUri?: string;
  tosUri?: string;
  policyUri?: string;
  contacts?: string[];
  softwareId?: string;
  softwareVersion?: string;
  registrationIp?: string;
}

export async function getClientRecord(clientId: string): Promise<ClientRecord | null> {
  const result = await docClient.send(
    // ConsistentRead: 失効直後の読み取りが古いレプリカに当たらないようにする
    // (セキュリティレビュー2026-09-02、Authorizerキャッシュ短縮とあわせて対応)
    new GetCommand({ TableName: TABLE_NAME, Key: { PK: `CLIENT#${clientId}` }, ConsistentRead: true })
  );
  return (result.Item as ClientRecord) ?? null;
}

export async function putClientRecord(record: ClientRecord): Promise<void> {
  await docClient.send(
    new PutCommand({
      TableName: TABLE_NAME,
      Item: record,
      ConditionExpression: "attribute_not_exists(PK)",
    })
  );
}

export async function deleteClientRecord(clientId: string): Promise<void> {
  await docClient.send(new DeleteCommand({ TableName: TABLE_NAME, Key: { PK: `CLIENT#${clientId}` } }));
}

export class LimitExceeded extends Error {}

/**
 * 登録数の上限カウンタ(COUNTER#dcr)。上限に達していれば LimitExceeded を投げる。
 * RFC 7591 §5 / docs/19 §2.4-d: 無制限登録による Cognito クォータ枯渇を防ぐ。
 */
export async function incrementRegistrationCounter(max: number): Promise<void> {
  try {
    await docClient.send(
      new UpdateCommand({
        TableName: TABLE_NAME,
        Key: { PK: "COUNTER#dcr" },
        UpdateExpression: "ADD #c :one",
        ConditionExpression: "attribute_not_exists(#c) OR #c < :max",
        ExpressionAttributeNames: { "#c": "count" },
        ExpressionAttributeValues: { ":one": 1, ":max": max },
      })
    );
  } catch (e) {
    if ((e as { name?: string }).name === "ConditionalCheckFailedException") throw new LimitExceeded("registration limit reached");
    throw e;
  }
}

export async function decrementRegistrationCounter(): Promise<void> {
  await docClient.send(
    new UpdateCommand({
      TableName: TABLE_NAME,
      Key: { PK: "COUNTER#dcr" },
      UpdateExpression: "ADD #c :minus",
      ExpressionAttributeNames: { "#c": "count" },
      ExpressionAttributeValues: { ":minus": -1 },
    })
  );
}

/**
 * 送信元IP単位のレート制限(RATE#<ip>#<分>)。HTTP API では WAF を /register に当てられないため
 * (docs/19 §2.1 F11)、Lambda 内で分単位カウンタを持つ。TTL 属性 expiresAt で自動削除する。
 */
export async function incrementIpCounter(ip: string, maxPerMinute: number): Promise<void> {
  const minute = Math.floor(Date.now() / 60000);
  try {
    await docClient.send(
      new UpdateCommand({
        TableName: TABLE_NAME,
        Key: { PK: `RATE#${ip}#${minute}` },
        UpdateExpression: "ADD #c :one SET expiresAt = if_not_exists(expiresAt, :ttl)",
        ConditionExpression: "attribute_not_exists(#c) OR #c < :max",
        ExpressionAttributeNames: { "#c": "count" },
        ExpressionAttributeValues: { ":one": 1, ":max": maxPerMinute, ":ttl": (minute + 2) * 60 },
      })
    );
  } catch (e) {
    if ((e as { name?: string }).name === "ConditionalCheckFailedException") throw new LimitExceeded("too many registrations from this address");
    throw e;
  }
}

export async function putServiceAccountUser(clientId: string): Promise<void> {
  await docClient.send(
    new PutCommand({
      TableName: TABLE_NAME,
      Item: {
        PK: `USER#${clientId}`,
        services: { quick: { plan: "standard" } },
      },
      ConditionExpression: "attribute_not_exists(PK)",
    })
  );
}

export async function deleteServiceAccountUser(clientId: string): Promise<void> {
  await docClient.send(new DeleteCommand({ TableName: TABLE_NAME, Key: { PK: `USER#${clientId}` } }));
}

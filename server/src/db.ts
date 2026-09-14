import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand } from "@aws-sdk/lib-dynamodb";

function createClient(): DynamoDBDocumentClient {
  const endpoint = process.env.DYNAMODB_ENDPOINT_URL;
  if (endpoint) {
    return DynamoDBDocumentClient.from(
      new DynamoDBClient({
        endpoint,
        region: "ap-northeast-1",
        credentials: { accessKeyId: "test", secretAccessKey: "test" },
      })
    );
  }
  return DynamoDBDocumentClient.from(new DynamoDBClient({}));
}

const docClient = createClient();

// テーブル名は環境変数で注入する(docs/19 §2.1 F12)。既定値は後方互換のため従来のハードコード値。
const TABLE_NAME = process.env.TABLE_NAME ?? "quick-mcp-poc-users";

export interface UserRecord {
  PK: string;
  services: Record<string, { plan: string }>;
}

export async function getUser(sub: string): Promise<UserRecord | null> {
  const t0 = process.env.LOG_TIMING ? performance.now() : 0;
  const result = await docClient.send(
    new GetCommand({
      TableName: TABLE_NAME,
      Key: { PK: `USER#${sub}` },
    })
  );
  if (process.env.LOG_TIMING) {
    console.log(
      JSON.stringify({
        timing: "getUser",
        durationMs: Math.round(performance.now() - t0),
      })
    );
  }
  return (result.Item as UserRecord) ?? null;
}

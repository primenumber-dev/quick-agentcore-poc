import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";

// テーブル名は環境変数で注入する(docs/19 §2.1 F12)。既定値は後方互換のため従来のハードコード値。
const TABLE_NAME = process.env.TABLE_NAME ?? "quick-mcp-poc-users";

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

export const docClient = createClient();
export { TABLE_NAME };

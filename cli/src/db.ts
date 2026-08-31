import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";

const TABLE_NAME = "quick-mcp-poc-users";

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

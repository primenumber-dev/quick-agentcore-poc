import {
  CognitoIdentityProviderClient,
  ListUserPoolClientsCommand,
} from "@aws-sdk/client-cognito-identity-provider";
import { ScanCommand } from "@aws-sdk/lib-dynamodb";
import { docClient, TABLE_NAME } from "./db.js";

export async function listClients(userPoolId: string): Promise<void> {
  const cognito = new CognitoIdentityProviderClient({});

  const [dynamoResult, cognitoResult] = await Promise.all([
    docClient.send(
      new ScanCommand({
        TableName: TABLE_NAME,
        FilterExpression: "begins_with(PK, :prefix)",
        ExpressionAttributeValues: { ":prefix": "CLIENT#" },
      })
    ),
    cognito.send(new ListUserPoolClientsCommand({ UserPoolId: userPoolId, MaxResults: 60 })),
  ]);

  const records = dynamoResult.Items ?? [];
  const knownIds = new Set(records.map((r) => (r.PK as string).replace("CLIENT#", "")));

  console.log("=== DCR登録済みクライアント(DynamoDB) ===");
  for (const r of records) {
    const clientId = (r.PK as string).replace("CLIENT#", "");
    console.log(`${clientId}\t${r.clientName}\t${r.status}\t${r.grantTypes?.join(",")}\t${r.createdAt}`);
  }

  console.log("\n=== Cognito側に存在するがDynamoDBにレコードが無いクライアント(静的 or ロールバック漏れ) ===");
  for (const c of cognitoResult.UserPoolClients ?? []) {
    if (c.ClientId && !knownIds.has(c.ClientId)) {
      console.log(`${c.ClientId}\t${c.ClientName}`);
    }
  }
}

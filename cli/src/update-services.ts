import { UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { docClient, TABLE_NAME } from "./db.js";

export async function updateServices(params: {
  sub: string;
  services: Record<string, string>;
}): Promise<void> {
  const services: Record<string, { plan: string }> = {};
  for (const [svc, plan] of Object.entries(params.services)) {
    services[svc] = { plan };
  }

  await docClient.send(
    new UpdateCommand({
      TableName: TABLE_NAME,
      Key: { PK: `USER#${params.sub}` },
      UpdateExpression: "SET services = :s",
      ExpressionAttributeValues: { ":s": services },
    })
  );
}

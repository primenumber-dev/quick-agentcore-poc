import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, PutCommand, DeleteCommand } from "@aws-sdk/lib-dynamodb";

const TABLE_NAME = "quick-mcp-poc-users";

export const docClient = DynamoDBDocumentClient.from(new DynamoDBClient({}));

export interface ClientRecord {
  PK: string;
  clientName: string;
  redirectUris: string[];
  tokenEndpointAuthMethod: string;
  grantTypes: string[];
  createdAt: string;
  status: "active" | "revoked";
  source: "dcr";
}

export async function getClientRecord(clientId: string): Promise<ClientRecord | null> {
  const result = await docClient.send(
    new GetCommand({ TableName: TABLE_NAME, Key: { PK: `CLIENT#${clientId}` } })
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

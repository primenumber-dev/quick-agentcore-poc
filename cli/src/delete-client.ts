import {
  CognitoIdentityProviderClient,
  DeleteUserPoolClientCommand,
} from "@aws-sdk/client-cognito-identity-provider";
import { GetCommand, DeleteCommand } from "@aws-sdk/lib-dynamodb";
import { docClient, TABLE_NAME } from "./db.js";

export async function deleteClient(params: {
  userPoolId: string;
  clientId: string;
}): Promise<void> {
  const cognito = new CognitoIdentityProviderClient({});

  const record = await docClient.send(
    new GetCommand({ TableName: TABLE_NAME, Key: { PK: `CLIENT#${params.clientId}` } })
  );

  await cognito.send(
    new DeleteUserPoolClientCommand({ UserPoolId: params.userPoolId, ClientId: params.clientId })
  );

  await docClient.send(new DeleteCommand({ TableName: TABLE_NAME, Key: { PK: `CLIENT#${params.clientId}` } }));

  if (record.Item?.grantTypes?.includes("client_credentials")) {
    await docClient.send(new DeleteCommand({ TableName: TABLE_NAME, Key: { PK: `USER#${params.clientId}` } }));
  }
}

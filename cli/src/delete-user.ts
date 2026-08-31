import {
  CognitoIdentityProviderClient,
  AdminGetUserCommand,
  AdminDeleteUserCommand,
} from "@aws-sdk/client-cognito-identity-provider";
import { DeleteCommand } from "@aws-sdk/lib-dynamodb";
import { docClient, TABLE_NAME } from "./db.js";

export async function deleteUser(params: {
  userPoolId: string;
  email: string;
}): Promise<{ sub: string }> {
  const cognito = new CognitoIdentityProviderClient({});

  const getUser = await cognito.send(
    new AdminGetUserCommand({
      UserPoolId: params.userPoolId,
      Username: params.email,
    })
  );
  const sub = getUser.UserAttributes?.find((a) => a.Name === "sub")?.Value;
  if (!sub) throw new Error("Failed to get sub from Cognito");

  await docClient.send(
    new DeleteCommand({
      TableName: TABLE_NAME,
      Key: { PK: `USER#${sub}` },
    })
  );

  await cognito.send(
    new AdminDeleteUserCommand({
      UserPoolId: params.userPoolId,
      Username: params.email,
    })
  );

  return { sub };
}

import {
  CognitoIdentityProviderClient,
  AdminCreateUserCommand,
  AdminGetUserCommand,
  AdminDeleteUserCommand,
} from "@aws-sdk/client-cognito-identity-provider";
import { PutCommand } from "@aws-sdk/lib-dynamodb";
import { docClient, TABLE_NAME } from "./db.js";

export async function inviteUser(params: {
  userPoolId: string;
  email: string;
  services: Record<string, string>;
}): Promise<{ sub: string }> {
  const cognito = new CognitoIdentityProviderClient({});

  await cognito.send(
    new AdminCreateUserCommand({
      UserPoolId: params.userPoolId,
      Username: params.email,
      UserAttributes: [
        { Name: "email", Value: params.email },
        { Name: "email_verified", Value: "true" },
      ],
    })
  );

  const getUser = await cognito.send(
    new AdminGetUserCommand({
      UserPoolId: params.userPoolId,
      Username: params.email,
    })
  );
  const sub = getUser.UserAttributes?.find((a) => a.Name === "sub")?.Value;
  if (!sub) throw new Error("Failed to get sub from Cognito");

  const services: Record<string, { plan: string }> = {};
  for (const [svc, plan] of Object.entries(params.services)) {
    services[svc] = { plan };
  }

  try {
    await docClient.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: {
          PK: `USER#${sub}`,
          email: params.email,
          services,
        },
      })
    );
  } catch (e) {
    console.error("DynamoDB write failed. Rolling back Cognito user...");
    await cognito.send(
      new AdminDeleteUserCommand({
        UserPoolId: params.userPoolId,
        Username: params.email,
      })
    );
    throw e;
  }

  return { sub };
}

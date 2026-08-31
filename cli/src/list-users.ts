import {
  CognitoIdentityProviderClient,
  ListUsersCommand,
} from "@aws-sdk/client-cognito-identity-provider";

export async function listUsers(userPoolId: string): Promise<void> {
  const cognito = new CognitoIdentityProviderClient({});
  const result = await cognito.send(
    new ListUsersCommand({ UserPoolId: userPoolId })
  );

  for (const user of result.Users ?? []) {
    const sub = user.Attributes?.find((a) => a.Name === "sub")?.Value;
    const email = user.Attributes?.find((a) => a.Name === "email")?.Value;
    console.log(`${sub}\t${email}\t${user.UserStatus}`);
  }
}

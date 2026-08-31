import { getUser } from "./db.js";
import { resolveTools } from "./tools/registry.js";

export interface UserContext {
  sub: string;
  allowedTools: string[];
}

export async function resolveAuthorization(
  sub: string
): Promise<UserContext> {
  const user = await getUser(sub);
  if (!user) {
    throw new Error("User not found");
  }

  const allowedTools = resolveTools(user.services);
  return { sub, allowedTools };
}

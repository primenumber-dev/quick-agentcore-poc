import { inviteUser } from "./invite-user.js";
import { deleteUser } from "./delete-user.js";
import { updateServices } from "./update-services.js";
import { listUsers } from "./list-users.js";
import { listClients } from "./list-clients.js";
import { deleteClient } from "./delete-client.js";

const command = process.argv[2];
const args = process.argv.slice(3);

switch (command) {
  case "invite-user": {
    const poolId = process.env.COGNITO_USER_POOL_ID;
    if (!poolId) {
      console.error("COGNITO_USER_POOL_ID is required");
      process.exit(1);
    }
    if (args.length < 2) {
      console.error("Usage: cli invite-user <email> '<services_json>'");
      process.exit(1);
    }
    const [email, servicesJson] = args;
    const services = JSON.parse(servicesJson) as Record<string, string>;
    const result = await inviteUser({ userPoolId: poolId, email, services });
    console.log(`User created successfully!`);
    console.log(`  Email: ${email}`);
    console.log(`  Sub:   ${result.sub}`);
    break;
  }

  case "delete-user": {
    const poolId = process.env.COGNITO_USER_POOL_ID;
    if (!poolId) {
      console.error("COGNITO_USER_POOL_ID is required");
      process.exit(1);
    }
    if (args.length < 1) {
      console.error("Usage: cli delete-user <email>");
      process.exit(1);
    }
    const [email] = args;
    const result = await deleteUser({ userPoolId: poolId, email });
    console.log(`User deleted successfully!`);
    console.log(`  Email: ${email}`);
    console.log(`  Sub:   ${result.sub}`);
    break;
  }

  case "update-services": {
    if (args.length < 2) {
      console.error("Usage: cli update-services <sub> '<services_json>'");
      process.exit(1);
    }
    const [sub, servicesJson] = args;
    const services = JSON.parse(servicesJson) as Record<string, string>;
    await updateServices({ sub, services });
    console.log(`Services updated for ${sub}`);
    break;
  }

  case "list-users": {
    const poolId = process.env.COGNITO_USER_POOL_ID;
    if (!poolId) {
      console.error("COGNITO_USER_POOL_ID is required");
      process.exit(1);
    }
    await listUsers(poolId);
    break;
  }

  case "list-clients": {
    const poolId = process.env.COGNITO_USER_POOL_ID;
    if (!poolId) {
      console.error("COGNITO_USER_POOL_ID is required");
      process.exit(1);
    }
    await listClients(poolId);
    break;
  }

  case "delete-client": {
    const poolId = process.env.COGNITO_USER_POOL_ID;
    if (!poolId) {
      console.error("COGNITO_USER_POOL_ID is required");
      process.exit(1);
    }
    if (args.length < 1) {
      console.error("Usage: cli delete-client <client_id>");
      process.exit(1);
    }
    const [clientId] = args;
    await deleteClient({ userPoolId: poolId, clientId });
    console.log(`Client deleted: ${clientId}`);
    break;
  }

  default:
    console.error(
      "Commands: invite-user, delete-user, update-services, list-users, list-clients, delete-client"
    );
    process.exit(1);
}

import express from "express";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { resolveAuthorization } from "./auth.js";
// import { registerEarthquakeTools } from "./tools/earthquake.js";
// import { registerCryptoTools } from "./tools/crypto.js";
import { registerQuickTools } from "./tools/quick/index.js";

const app = express();
app.use(express.json());

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

function extractSub(req: express.Request): string | undefined {
  const header = req.headers["x-cognito-sub"];
  if (typeof header === "string") return header;

  const auth = req.headers.authorization;
  if (!auth?.startsWith("Bearer ")) return undefined;
  try {
    const payload = JSON.parse(
      Buffer.from(auth.split(".")[1], "base64url").toString()
    );
    return payload.sub;
  } catch {
    return undefined;
  }
}

app.get("/mcp", (_req, res) => {
  res.status(405).json({ error: "SSE not supported in stateless mode" });
});

app.delete("/mcp", (_req, res) => {
  res.status(200).json({ message: "Session terminated" });
});

app.post("/mcp", async (req, res) => {
  const sub = extractSub(req);
  if (!sub) {
    res.status(401).json({ error: "Missing user identity" });
    return;
  }

  try {
    const userContext = await resolveAuthorization(sub);

    const server = new McpServer({
      name: "quick-mcp-poc",
      version: "1.0.0",
    });

    // registerEarthquakeTools(server, userContext.allowedTools);
    // registerCryptoTools(server, userContext.allowedTools);
    registerQuickTools(server);

    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined,
      enableJsonResponse: true,
    });

    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);

    res.on("close", () => {
      transport.close();
      server.close();
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Internal server error";
    res.status(403).json({ error: message });
  }
});

const port = parseInt(process.env.PORT ?? "8000", 10);
app.listen(port, "0.0.0.0", () => {
  console.log(`MCP server listening on port ${port}`);
});

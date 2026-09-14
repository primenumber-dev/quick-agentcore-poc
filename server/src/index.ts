import { randomUUID } from "node:crypto";
import express from "express";
import { createMcpHandler, McpServer } from "@modelcontextprotocol/server";
import { toNodeHandler } from "@modelcontextprotocol/node";
import { resolveAuthorization } from "./auth.js";
// import { registerEarthquakeTools } from "./tools/earthquake.js";
// import { registerCryptoTools } from "./tools/crypto.js";
import { registerQuickTools } from "./tools/quick/index.js";

// LOG_TIMING instrumentation for the "6-second response" latency
// investigation (docs/08-weekly-verification-plan.md §3). bootId is
// generated once per process: identical bootId values across requests
// prove the same container/process served both (microVM reuse via
// Mcp-Session-Id stickiness), rather than a fresh cold start each time.
const bootId = randomUUID();
let reqSeq = 0;
if (process.env.LOG_TIMING) {
  console.log(JSON.stringify({ timing: "boot", bootId }));
}

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

// v2 SDK: MCP protocol 2026-07-28. `legacy: "stateless"` (the default) keeps
// serving 2025-era clients over the same per-request stateless idiom as
// before (sessionIdGenerator: undefined equivalent), and answers legacy
// GET/DELETE on /mcp with 405 automatically — no hand-rolled stubs needed.
const mcpHandler = createMcpHandler(() => {
  const server = new McpServer({
    name: "quick-mcp-poc",
    version: "1.0.0",
  });

  // registerEarthquakeTools(server, userContext.allowedTools);
  // registerCryptoTools(server, userContext.allowedTools);
  registerQuickTools(server);

  return server;
});

const nodeHandler = toNodeHandler(mcpHandler);

app.all("/mcp", async (req, res) => {
  const t0 = process.env.LOG_TIMING ? performance.now() : 0;
  const reqSeqId = ++reqSeq;
  if (process.env.LOG_TIMING) {
    console.log(
      JSON.stringify({
        timing: "request_received",
        bootId,
        reqSeqId,
        incomingMcpSessionId: req.headers["mcp-session-id"] ?? null,
        method: req.body?.method ?? null,
      })
    );
  }

  // Only POST performs an actual invocation; GET/DELETE fall through to the
  // v2 handler's own legacy-mode routing (405) without an auth check, same
  // as the v1 stub behavior.
  if (req.method === "POST") {
    const sub = extractSub(req);
    if (!sub) {
      res.status(401).json({ error: "Missing user identity" });
      return;
    }
    try {
      await resolveAuthorization(sub);
    } catch (e) {
      const message = e instanceof Error ? e.message : "Internal server error";
      res.status(403).json({ error: message });
      return;
    }
  }

  await nodeHandler(req, res, req.body);

  if (process.env.LOG_TIMING) {
    console.log(
      JSON.stringify({
        timing: "request_complete",
        bootId,
        reqSeqId,
        durationMs: Math.round(performance.now() - t0),
      })
    );
  }
});

const port = parseInt(process.env.PORT ?? "8000", 10);
app.listen(port, "0.0.0.0", () => {
  console.log(`MCP server listening on port ${port}`);
});

import { z } from "zod";
import { McpServer } from "@modelcontextprotocol/server";

const BASE_URL = "https://api.coingecko.com/api/v3";

export function registerCryptoTools(
  server: McpServer,
  allowedTools: string[]
): void {
  if (allowedTools.includes("get_crypto_price")) {
    server.registerTool(
      "get_crypto_price",
      {
        description: "Get current price of a cryptocurrency",
        inputSchema: {
          id: z.string().describe("Coin ID (e.g. bitcoin, ethereum)"),
          currency: z.string().default("usd").describe("Target currency (e.g. usd, jpy)"),
        },
      },
      async ({ id, currency }) => {
        const res = await fetch(`${BASE_URL}/simple/price?ids=${id}&vs_currencies=${currency}&include_24hr_change=true`);
        const data = await res.json();
        return {
          content: [{ type: "text" as const, text: JSON.stringify(data) }],
        };
      }
    );
  }

  if (allowedTools.includes("get_crypto_markets")) {
    server.registerTool(
      "get_crypto_markets",
      {
        description: "Get top cryptocurrencies by market cap",
        inputSchema: {
          currency: z.string().default("usd").describe("Target currency (e.g. usd, jpy)"),
          limit: z.number().default(10).describe("Number of results"),
        },
      },
      async ({ currency, limit }) => {
        const res = await fetch(`${BASE_URL}/coins/markets?vs_currency=${currency}&order=market_cap_desc&per_page=${limit}&page=1`);
        const data = await res.json();
        return {
          content: [{ type: "text" as const, text: JSON.stringify(data) }],
        };
      }
    );
  }

  if (allowedTools.includes("get_crypto_history")) {
    server.registerTool(
      "get_crypto_history",
      {
        description: "Get price history of a cryptocurrency",
        inputSchema: {
          id: z.string().describe("Coin ID (e.g. bitcoin, ethereum)"),
          days: z.number().default(7).describe("Number of days (1, 7, 30, 365)"),
          currency: z.string().default("usd").describe("Target currency (e.g. usd, jpy)"),
        },
      },
      async ({ id, days, currency }) => {
        const res = await fetch(`${BASE_URL}/coins/${id}/market_chart?vs_currency=${currency}&days=${days}`);
        const data = await res.json();
        return {
          content: [{ type: "text" as const, text: JSON.stringify(data) }],
        };
      }
    );
  }
}

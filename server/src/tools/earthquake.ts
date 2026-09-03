import { z } from "zod";
import { McpServer } from "@modelcontextprotocol/server";

const BASE_URL = "https://earthquake.usgs.gov/earthquakes/feed/v1.0";

export function registerEarthquakeTools(
  server: McpServer,
  allowedTools: string[]
): void {
  if (allowedTools.includes("get_recent_earthquakes")) {
    server.registerTool(
      "get_recent_earthquakes",
      {
        description: "Get earthquakes from the past day",
        inputSchema: {
          minMagnitude: z.enum(["significant", "4.5", "2.5", "1.0", "all"]).default("4.5").describe("Minimum magnitude filter"),
        },
      },
      async ({ minMagnitude }) => {
        const feed = minMagnitude === "significant" ? "significant" : `${minMagnitude}`;
        const res = await fetch(`${BASE_URL}/summary/${feed}_day.geojson`);
        const data = await res.json() as { features: { properties: Record<string, unknown> }[] };
        const quakes = data.features.slice(0, 10).map((f) => f.properties);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(quakes) }],
        };
      }
    );
  }

  if (allowedTools.includes("get_earthquake_detail")) {
    server.registerTool(
      "get_earthquake_detail",
      {
        description: "Get detailed information about a specific earthquake by event ID",
        inputSchema: {
          eventId: z.string().describe("Earthquake event ID (e.g. us7000n123)"),
        },
      },
      async ({ eventId }) => {
        const res = await fetch(`https://earthquake.usgs.gov/earthquakes/feed/v1.0/detail/${eventId}.geojson`);
        const data = await res.json();
        return {
          content: [{ type: "text" as const, text: JSON.stringify(data) }],
        };
      }
    );
  }

  if (allowedTools.includes("search_earthquakes")) {
    server.registerTool(
      "search_earthquakes",
      {
        description: "Search earthquakes by location and time range",
        inputSchema: {
          latitude: z.number().describe("Latitude"),
          longitude: z.number().describe("Longitude"),
          maxRadiusKm: z.number().default(500).describe("Search radius in km"),
          minMagnitude: z.number().default(3).describe("Minimum magnitude"),
        },
      },
      async ({ latitude, longitude, maxRadiusKm, minMagnitude }) => {
        const res = await fetch(
          `https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&latitude=${latitude}&longitude=${longitude}&maxradiuskm=${maxRadiusKm}&minmagnitude=${minMagnitude}&limit=10`
        );
        const data = await res.json() as { features: { properties: Record<string, unknown> }[] };
        const quakes = data.features.map((f) => f.properties);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(quakes) }],
        };
      }
    );
  }
}

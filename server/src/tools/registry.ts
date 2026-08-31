const TOOL_MAP: Record<string, Record<string, string[]>> = {
  earthquake: {
    lite: ["get_recent_earthquakes"],
    standard: ["get_recent_earthquakes", "get_earthquake_detail", "search_earthquakes"],
  },
  crypto: {
    lite: ["get_crypto_price"],
    standard: ["get_crypto_price", "get_crypto_markets", "get_crypto_history"],
  },
};

export function resolveTools(
  services: Record<string, { plan: string }>
): string[] {
  return Object.entries(services).flatMap(
    ([serviceId, { plan }]) => TOOL_MAP[serviceId]?.[plan] ?? []
  );
}

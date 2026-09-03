import { McpServer } from "@modelcontextprotocol/server";
import { registerGetQuote } from "./get_quote.js";
import { registerGetPriceHistory } from "./get_price_history.js";
import { registerGetIntradayHistory } from "./get_intraday_history.js";
import { registerSearchNews } from "./search_news.js";
import { registerGetRanking } from "./get_ranking.js";
import { registerSearchStocks } from "./search_stocks.js";

export function registerQuickTools(server: McpServer): void {
  registerGetQuote(server);
  registerGetPriceHistory(server);
  registerGetIntradayHistory(server);
  registerSearchNews(server);
  registerGetRanking(server);
  registerSearchStocks(server);
}

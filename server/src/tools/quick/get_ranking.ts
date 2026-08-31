import { z } from "zod";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { callQuickApi } from "./client.js";

// ----------------------------------------------------------------------------
// II（ランキング情報群ID）
// ----------------------------------------------------------------------------
const II_CODES = [
  "RE@0020001", // 値上がり率（東証プライム）
  "RE@0021001", // 値下がり率（東証プライム）
  "RE@0030001", // 売買高（東証プライム）
  "RE@0060001", // 時価総額（東証プライム）
  "RE@0020002", // 値上がり率（東証スタンダード）
  "RE@0021002", // 値下がり率（東証スタンダード）
  "RE@0030002", // 売買高（東証スタンダード）
] as const;

// ----------------------------------------------------------------------------
// Element コード
// ----------------------------------------------------------------------------
const ELEMENT_CODES = [
  "!RANK",   // ランク番号（同率時は同じ値で複数行）
  "!RANK_S", // シリアル番号（連番）
  "QCD",     // 銘柄コード（例: 7203/T）
  "NAME",    // 銘柄名
  "RDPP",    // 現在値（円）
  "RDWP",    // 前日比（円）
  "RDRP",    // 前日比（%）
  "DJ",      // 売買代金（円）
  "MKCN",    // 時価総額（円）— 本番提供予定。開発環境ではECNDs行き
] as const;

// ----------------------------------------------------------------------------
// Input schema
// ----------------------------------------------------------------------------
const inputSchema = {
  II: z
    .enum(II_CODES)
    .describe(
      [
        "ランキング情報群ID。",
        "  RE@0020001 = 値上がり率（東証プライム）",
        "  RE@0021001 = 値下がり率（東証プライム）",
        "  RE@0030001 = 売買高（東証プライム）",
        "  RE@0060001 = 時価総額（東証プライム）",
        "  RE@002000{2|3}/RE@002100{2|3}/RE@003000{2|3} = スタンダード/グロース等",
      ].join("\n")
    ),

  R: z
    .number()
    .int()
    .positive()
    .max(500)
    .default(30)
    .describe(
      "取得上位件数。例: 30 で TOP30。" +
        "同率ランクが含まれる場合（特に値下がり率など）は RL の行数が R を超えることがある。"
    ),

  ECs: z
    .array(z.enum(ELEMENT_CODES))
    .min(1)
    .optional()
    .describe(
      [
        "取得したい要素コードの配列。省略時はAPI側のデフォルト要素が返る（RP='0'）。",
        "  !RANK    = ランク番号（同率は同値、複数行になる）",
        "  !RANK_S  = シリアル連番",
        "  QCD/NAME = 銘柄コード/名",
        "  RDPP     = 現在値（円）",
        "  RDWP     = 前日比（円）、RDRP = 前日比（%）",
        "  DJ       = 売買代金（円）",
        "  MKCN     = 時価総額（円）— 本番環境で提供予定。開発環境では ECNDs 行きで取れない",
        "ECs 指定時は内部で RP='1' を設定する。",
        "なお !RANK / !RANK_S は ECs に含めなくても通常 ECOKs に入って返る。",
      ].join("\n")
    ),
};

// ----------------------------------------------------------------------------
// Output schema
// ----------------------------------------------------------------------------
const outputSchema = {
  S: z.string().describe("応答全体ステータス。空文字=正常。"),
  OD: z.string().describe("レスポンス日時（'YYYY/MM/DD hh:mm:ss'）"),
  D: z
    .object({
      MS: z.string().describe("ステータス。'A00'=正常。"),
      D: z.string().describe("基準日（'YYYYMMDD'）。"),
      T: z.string().describe("基準時刻（'hhmm'）。"),
      ECOKs: z
        .array(z.string())
        .describe(
          "実際に提供された要素コード配列。RL各行の列順とこれが一致する。" +
            "通常 ['!RANK','!RANK_S', ...] のようにランク列が先頭に入る。"
        ),
      ECNDs: z
        .array(z.string())
        .describe(
          "未提供の要素コード配列（例: ['MKCN']）。RL の列にも含まれない。"
        ),
      RL: z
        .array(z.array(z.string()))
        .describe(
          "ランキングデータの2次元配列。各行は ECOKs の順序に対応する文字列配列。" +
            "同率の場合は同じ '!RANK' 値で複数行が返り、'!RANK_S' で連番が付く。"
        ),
    })
    .optional(),
  ErrR: z.array(z.string()).optional().describe("エラーメッセージ配列。"),
};

// ----------------------------------------------------------------------------
// Tool registration
// ----------------------------------------------------------------------------
const description =
  "QUICK historicalRank.do APIを叩き、株式ランキング（値上り率/値下り率/売買高/時価総額 等）を取得する。" +
  "II でランキング種別、R で件数、ECs で取得項目を指定する（ECs 省略時はデフォルト要素）。" +
  "レスポンスの RL は **2次元配列**で、列順は ECOKs に従う。" +
  "JS/Python では `dict(zip(ECOKs, row))` のようにマッピングして使う想定。" +
  "MKCN（時価総額）は本番提供予定で開発環境では ECNDs 行き。" +
  "同率ランクがあると RL の行数が R を超えることがある。";

export function registerGetRanking(server: McpServer): void {
  server.registerTool(
    "get_ranking",
    {
      title: "株式ランキング取得",
      description,
      inputSchema,
      outputSchema,
    },
    async ({ II, R, ECs }) => {
      const payload: Record<string, unknown> = {
        II,
        R,
        RP: ECs && ECs.length > 0 ? "1" : "0",
      };
      if (ECs && ECs.length > 0) payload.ECs = ECs;

      const result = await callQuickApi<Record<string, unknown>>(
        "historicalRank.do",
        payload
      );
      return {
        content: [{ type: "text", text: JSON.stringify(result) }],
        structuredContent: result,
      };
    }
  );
}

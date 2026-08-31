import { z } from "zod";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { callQuickApi } from "./client.js";

// ----------------------------------------------------------------------------
// Element コード
// ----------------------------------------------------------------------------
const ELEMENT_CODES = [
  "DPP", // そのバーの終値（現値）
  "DOP", // 始値
  "DHP", // 高値
  "DLP", // 安値
  "DV",  // 出来高（為替は空文字）
] as const;

// ----------------------------------------------------------------------------
// Input schema
// ----------------------------------------------------------------------------
const inputSchema = {
  QC: z
    .string()
    .describe(
      "銘柄コード（Quoteコード）。例: 7974/T (任天堂)、101/T (日経平均)、XJPY/4 (USD/JPY)。"
    ),

  ECs: z
    .array(z.enum(ELEMENT_CODES))
    .min(1)
    .describe(
      "取得したい項目の配列。" +
        "DPP=そのバーの終値(現値), DOP=始値, DHP=高値, DLP=安値, DV=出来高。" +
        "為替は DV が空文字で返ることに注意（ECOKsには入る）。" +
        "DJ・DYWP/DYRP 等は分足/TICKでは取得不可（指定するとAPIエラー、または空配列で返る可能性あり）。"
    ),

  RT: z
    .enum(["1", "2"])
    .describe(
      [
        "時間軸（Record Type）。",
        "  1 = TICK（約定単位）— LSN（論理通番）が有効",
        "  2 = 日中足（分足）— MT パラメータ必須",
        "日足以上は本ツールではなく get_price_history を使うこと。",
      ].join("\n")
    ),

  MT: z
    .enum(["1", "3", "5", "10", "15", "30", "45", "60"])
    .optional()
    .describe(
      "分足の分数。RT='2' のとき必須。" +
        "1/3/5/10/15/30/60 が公式ガイド掲載値、45 は仕様リファレンス記載（環境により可否）。" +
        "60=1時間足。RT='1'(TICK) では指定不可。"
    ),

  RD: z
    .enum(["0"])
    .default("0")
    .describe("基準日方向。'0'=負方向（過去）固定。"),

  RN: z
    .number()
    .int()
    .positive()
    .describe(
      "取得日数（バーの本数ではない点に注意）。例えば RT=2/MT=5 で RN=1 なら、" +
        "1日分の5分足バー（午前場・後場合わせて最大約60本）が返る。" +
        "実際のバー本数は DIs[].HDs.length で確認する。"
    ),

  SD: z
    .string()
    .regex(/^\d{8}$/)
    .default("00000000")
    .describe("開始日（'YYYYMMDD'8桁）。'00000000'=最新日。"),

  LSN: z
    .string()
    .optional()
    .describe(
      "TICK の開始論理通番。RT='1' のときのみ有効。" +
        "前回レスポンスの最後の LSN を渡してページングする用途。"
    ),
};

// ----------------------------------------------------------------------------
// Output schema
// ----------------------------------------------------------------------------
const barSchema = z.object({
  Vs: z
    .array(z.string())
    .describe("各Elementの値。順序は所属する DIs[].ECOKs と一致。"),
  T: z
    .string()
    .describe(
      "時刻（'hhmm'形式、4文字）。先頭ゼロあり。" +
        "**そのバーの終端時刻**（5分足の '0905' = 9:00〜9:05のバー）。"
    ),
  LSN: z
    .string()
    .describe("論理通番。日中足は空文字、TICK は通番文字列。"),
  PF: z
    .string()
    .describe(
      "事象フラグ。'0'=通常、'1'=特別気配 等。"
    ),
});

const dayBlockSchema = z.object({
  RD: z.string().describe("対象日（'YYYYMMDD'）。"),
  S1S: z.string().describe("前場開始時刻（'HH:MM'）。"),
  S1E: z.string().describe("前場終了時刻。"),
  S2S: z.string().describe("後場開始時刻。"),
  S2E: z.string().describe("後場終了時刻。"),
  S3S: z.string().describe("第3セッション開始時刻（通常は空文字）。"),
  S3E: z.string().describe("第3セッション終了時刻。"),
  DTI: z
    .string()
    .describe("タイムゾーンオフセット（例: '+09:00'）。海外市場は現地時刻基準。"),
  EX: z
    .record(z.string(), z.string())
    .describe(
      "拡張情報。NOQ=当日注文件数、NOPV=当日PV数（QUICK社内統計）など。"
    ),
  ECOKs: z
    .array(z.string())
    .describe("取得できたElementコード配列。HDs[].Vs の列順と一致。"),
  ECND: z.record(z.string(), z.string()).describe("取得できなかったElement。"),
  HDs: z
    .array(barSchema)
    .describe("足データ配列。**T昇順（古い時刻が先頭）**。"),
});

const outputSchema = {
  S: z.string().describe("応答全体ステータス。空文字=正常。"),
  OD: z.string().describe("データ取得日時（JST、'YYYY/MM/DD hh:mm:ss'）"),
  D: z
    .object({
      MS: z.string().describe("メッセージステータス。'A00'=正常。"),
      DIs: z
        .array(dayBlockSchema)
        .describe(
          "日付ごとのデータ配列。RN で指定した日数分。各日の足は HDs に入る。"
        ),
    })
    .optional()
    .describe("レスポンス本体。エラー時は省略。"),
  ErrR: z.array(z.string()).optional().describe("エラーメッセージ配列。"),
};

// ----------------------------------------------------------------------------
// Tool registration
// ----------------------------------------------------------------------------
const description =
  "QUICK historicalIntraday.do APIを叩き、銘柄1本の日中時系列（TICK / 分足）を取得する。" +
  "1リクエスト1銘柄。日足以上は get_price_history、現在値スナップショットは get_quote を使うこと。" +
  "RT='2'（分足）では MT で分数（1/3/5/10/15/30/60、45は環境依存）を指定。" +
  "RT='1'（TICK）は LSN でページング可能。" +
  "RN は『日数』であってバーの本数ではない（5分足RN=1なら1日分≒最大60本）。" +
  "値はすべて文字列。為替は DV が空文字。" +
  "HDs は T昇順（古い時刻が先頭）で、historical.do の D1降順とは並びが逆である点に注意。";

export function registerGetIntradayHistory(server: McpServer): void {
  server.registerTool(
    "get_intraday_history",
    {
      title: "日中時系列取得（TICK / 分足）",
      description,
      inputSchema,
      outputSchema,
    },
    async ({ QC, ECs, RT, MT, RD, RN, SD, LSN }) => {
      const payload: Record<string, unknown> = { QC, ECs, RT, RD, RN, SD };
      if (MT !== undefined) payload.MT = MT;
      if (LSN !== undefined) payload.LSN = LSN;

      const result = await callQuickApi<Record<string, unknown>>(
        "historicalIntraday.do",
        payload
      );
      return {
        content: [{ type: "text", text: JSON.stringify(result) }],
        structuredContent: result,
      };
    }
  );
}

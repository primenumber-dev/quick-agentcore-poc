import { z } from "zod";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { callQuickApi } from "./client.js";

// ----------------------------------------------------------------------------
// Element コード
// ----------------------------------------------------------------------------
const ELEMENT_CODES = [
  "DPP",  // 終値
  "DOP",  // 始値
  "DHP",  // 高値
  "DLP",  // 安値
  "DV",   // 出来高（為替は空文字、指数は東証全体値）
  "DJ",   // 売買代金（為替は空文字、指数は東証全体値）
  "DYWP", // 前日比（円）— 週足/月足/年足ではECNDに'Azz'で振り分け
  "DYRP", // 前日比率（%）— 同上
] as const;

// ----------------------------------------------------------------------------
// Input schema
// ----------------------------------------------------------------------------
const inputSchema = {
  QC: z
    .string()
    .describe(
      [
        "銘柄コード（Quoteコード）。get_quote と同じ形式・資産クラスをサポート。",
        "  - 国内株式: 数字4桁/T (例: 7974/T)",
        "  - 国内指数: 数字3桁/T (例: 101/T = 日経平均、151/T = TOPIX)",
        "  - 為替: X通貨/4 (例: XJPY/4 = USD/JPY) ※ DV/DJ は空文字で返る",
        "  - 海外指数: @@シンボル/市場 (例: @@INDU/U)",
        "  - 先物: 数字.数字/O (例: 101.1/O)",
        "  - 国内債券・海外債券（時系列価格は限定的）",
      ].join("\n")
    ),

  ECs: z
    .array(z.enum(ELEMENT_CODES))
    .min(1)
    .describe(
      [
        "取得したい時系列項目の配列（必須）。",
        "  DPP=終値, DOP=始値, DHP=高値, DLP=安値, DV=出来高, DJ=売買代金,",
        "  DYWP=前日比(円), DYRP=前日比率(%)。",
        "週足(RT=4)/月足(RT=5)/年足(RT=6) では DYWP/DYRP は取得不可で",
        "ECND に 'Azz' として振り分けられ、Vs配列にも含まれない。",
        "ECOKs と Vs の要素数は常に一致する（ECND分は除外済み）。",
        "為替は DV/DJ が空文字（''）で返る ※ ECOKs には入るが ECND には入らない。",
        "指数(101/T,151/T) の DV/DJ は東証全体の値（銘柄個別ではない）。",
        "F=1（不連続修正あり）の場合、修正境界となる日は DYWP/DYRP が空文字で返る。",
      ].join("\n")
    ),

  RT: z
    .enum(["3", "4", "5", "6"])
    .describe(
      [
        "時間軸（Record Type）。",
        "  3 = 日足",
        "  4 = 週足（DYWP/DYRP は取得不可）",
        "  5 = 月足（同上）",
        "  6 = 年足（同上）",
        "TICK や分足は本ツールではなく get_intraday_history を使うこと。",
      ].join("\n")
    ),

  F: z
    .enum(["0", "1"])
    .default("1")
    .describe(
      "不連続修正フラグ。0=なし / 1=あり（株式分割等を遡及調整、推奨）。" +
        "F=1 の場合、不連続修正の境界日では DYWP/DYRP が空文字で返ることがある。"
    ),

  RD: z
    .enum(["0", "1", "2"])
    .default("0")
    .describe(
      [
        "基準日方向。",
        "  0 = 負方向（過去側、SD から RN 本さかのぼる）",
        "  1 = 正方向（未来側）",
        "  2 = 期間指定（SD〜ED の範囲、ED必須）",
      ].join("\n")
    ),

  RN: z
    .number()
    .int()
    .positive()
    .optional()
    .describe(
      "取得本数（足数）。RD=0または1のとき必須。RD=2（期間指定）では無視される。"
    ),

  SD: z
    .string()
    .regex(/^\d{8}$/)
    .default("00000000")
    .describe(
      "開始日（'YYYYMMDD'8桁）。'00000000' で最新日基準（RD=0なら最新からRN本過去）。"
    ),

  ED: z
    .string()
    .regex(/^\d{8}$/)
    .optional()
    .describe("終了日（'YYYYMMDD'8桁）。RD=2（期間指定）のとき必須。"),
};

// ----------------------------------------------------------------------------
// Output schema
// ----------------------------------------------------------------------------
const barSchema = z.object({
  Vs: z
    .array(z.string())
    .describe(
      "各Elementの値（文字列配列）。順序は ECOKs と一致する。" +
        "値は数値も日付も常に文字列。'' (空文字) の場合あり" +
        "（例: F=1での不連続修正境界日のDYWP、為替のDV/DJ）。"
    ),
  D1: z
    .string()
    .describe(
      "対象日付。日足=当日、週足=週初(月曜)、月足=月初、年足=年初。'YYYYMMDD'形式。"
    ),
  D2: z
    .string()
    .describe(
      "終端日付。日足=空白8文字 '        '、週足=週末(金曜)、月足=月末、年足=年末。"
    ),
});

const outputSchema = {
  S: z.string().describe("応答全体ステータス。空文字=正常。"),
  OD: z.string().describe("データ取得日時（JST、'YYYY/MM/DD hh:mm:ss'）"),
  D: z
    .object({
      MS: z.string().describe("メッセージステータス。'A00'=正常。"),
      ECOKs: z
        .array(z.string())
        .describe(
          "実際に取得できたElementコード配列。HDs[].Vs の各列の意味と順序がこれに一致する。"
        ),
      ECND: z
        .record(z.string(), z.string())
        .describe(
          "取得できなかったElementとESコードのマップ（例: {\"DYWP\":\"Azz\"}）。" +
            "週足/月足/年足の DYWP/DYRP がここに振り分けられる。"
        ),
      HDs: z
        .array(barSchema)
        .describe(
          "足データ配列。**新しい日付が先頭（D1降順）** で並ぶ。" +
            "Vs の要素数は ECOKs と一致する（ECND行きの項目は列に存在しない）。"
        ),
    })
    .optional()
    .describe("レスポンス本体。エラー時は省略される。"),
  ErrR: z.array(z.string()).optional().describe("エラーメッセージ配列。"),
};

// ----------------------------------------------------------------------------
// Tool registration
// ----------------------------------------------------------------------------
const description =
  "QUICK historical.do APIを叩き、銘柄1本の時系列価格（日足/週足/月足/年足）を取得する。" +
  "1リクエスト1銘柄（複数銘柄が必要なら複数回呼ぶ）。" +
  "TICK・分足は本ツールではなく get_intraday_history を、現在値スナップショットは get_quote を使うこと。" +
  "値はすべて文字列。週足以上では DYWP/DYRP が ECND に振り分けられて返らない点、" +
  "F=1（不連続修正あり）の境界日は DYWP/DYRP が空文字で返る点、" +
  "為替は DV/DJ が空文字で返る点に注意。" +
  "チャート/騰落率計算には F=1 推奨。HDs は新しい日付が先頭。";

export function registerGetPriceHistory(server: McpServer): void {
  server.registerTool(
    "get_price_history",
    {
      title: "時系列価格取得（日足/週足/月足/年足）",
      description,
      inputSchema,
      outputSchema,
    },
    async ({ QC, ECs, RT, F, RD, RN, SD, ED }) => {
      const payload: Record<string, unknown> = { QC, ECs, RT, F, RD, SD };
      if (RN !== undefined) payload.RN = RN;
      if (ED !== undefined) payload.ED = ED;

      const result = await callQuickApi<Record<string, unknown>>(
        "historical.do",
        payload
      );
      return {
        content: [{ type: "text", text: JSON.stringify(result) }],
        structuredContent: result,
      };
    }
  );
}

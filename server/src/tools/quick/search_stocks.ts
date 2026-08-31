import { z } from "zod";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { callQuickApi } from "./client.js";

// ----------------------------------------------------------------------------
// Input schema
// ----------------------------------------------------------------------------
const inputSchema = {
  KW: z
    .array(z.string())
    .min(1)
    .describe(
      [
        "検索キーワードの配列。複数指定時はAND条件。",
        "銘柄コード（数字）も渡せる（例: ['7974']）。",
        "候補一般検索（COR='1' & UON='0'）の場合は最大5個まで。",
      ].join("\n")
    ),

  COR: z
    .enum(["0", "1"])
    .default("1")
    .describe("候補/関連の区分。'1'=候補銘柄（通常の検索）、'0'=関連銘柄。"),

  UON: z
    .enum(["0", "1"])
    .default("0")
    .describe("対象範囲。'0'=一般銘柄、'1'=取扱銘柄。"),

  LM: z
    .number()
    .int()
    .positive()
    .max(51)
    .default(20)
    .describe("応答件数（最大51）。"),

  STR: z
    .number()
    .int()
    .positive()
    .default(1)
    .describe(
      "応答開始位置（1始まり）。ページネーション時に STR=LM*(page-1)+1 で指定。"
    ),

  EXD: z
    .enum(["0", "1"])
    .default("1")
    .describe("上場廃止銘柄。'1'=除外、'0'=含む。"),

  STJ: z
    .enum(["0", "1", "2"])
    .optional()
    .describe("国内/海外フィルタ。'1'=国内のみ、'0'=海外含む、'2'=海外のみ。"),

  STE: z
    .array(z.string())
    .optional()
    .describe("取引所コード配列（例: ['T']=東証）。"),

  SC: z
    .array(z.string())
    .optional()
    .describe(
      "所属部コード配列。'01'=東証1部、'13'=スタンダード、'14'=グロース、'51'=プライム など。"
    ),

  IT: z
    .array(z.string())
    .optional()
    .describe("業種コード配列（4桁、例: ['3700']）。"),

  MKW: z
    .enum(["0", "1"])
    .optional()
    .describe("手入力キーワード。'0'=除く、'1'=含む。"),

  FRO: z
    .enum(["0", "1"])
    .optional()
    .describe("同一階層表示。'0'=階層別、'1'=同一階層（既定 '0'）。"),
};

// ----------------------------------------------------------------------------
// Output schema
// ----------------------------------------------------------------------------
const marketSchema = z.object({
  MKC: z.string().describe("市場コード。"),
  MKN: z.string().describe("市場名称（日本語）。"),
  MKE: z.string().describe("市場名称（英語）。"),
  MQC: z
    .string()
    .describe(
      "当該市場の Quote コード。他APIに渡す場合は MQC をそのまま使う（既に '/' を含むことがある）。"
    ),
  OPR: z.string().optional().describe("オプション関連値（実態は付随情報）。"),
  OPD: z.string().optional().describe("オプション関連値（実態は付随情報）。"),
});

const stockSchema = z.object({
  DTN: z.string().describe("代表名称（日本語）。"),
  DTE: z.string().describe("代表名称（英語）。"),
  QCD: z.string().describe("証券コード（例: '7203'）。"),
  QCS: z.string().describe("銘柄種別。'1'=株式。"),
  PRE: z.string().describe("主市場コード。'T'=東京、'M'=名古屋、'U'=米国 など。"),
  PRN: z.string().describe("主市場名称（日本語）。"),
  PEN: z.string().describe("主市場名称（英語）。"),
  AMN: z.string().optional().describe("時価総額（百万円）。"),
  AMD: z.string().optional().describe("時価総額（ドル）。"),
  OPR: z.string().optional(),
  OPD: z.string().optional(),
  LST: z
    .string()
    .describe(
      "上場ステータス。'0'=上場予定、'1'=上場中、'6'=FACTSETのみ、'8'=上場中止、'9'=上場廃止。"
    ),
  SC: z.string().optional().describe("所属部コード。"),
  IT: z.string().optional().describe("業種コード。"),
  HDF: z.string().optional().describe("取扱銘柄フラグ。'1'=取扱、'0'=その他。"),
  HST: z
    .string()
    .optional()
    .describe("取扱ステータス。'0'=予定、'1'=取扱中、'9'=終了、'10'=その他。"),
  UA1: z.string().optional(),
  UA2: z.string().optional(),
  UA3: z.string().optional(),
  UA4: z.string().optional(),
  UA5: z.string().optional(),
  MK: z
    .array(marketSchema)
    .optional()
    .describe("複数市場上場時の市場情報配列。"),
});

const outputSchema = {
  S: z.string().describe("応答全体ステータス。空文字=正常。"),
  OD: z.string().describe("データ取得日時（'YYYY/MM/DD hh:mm:ss'）。"),
  D: z
    .object({
      RD: z.object({
        MSS: z.string().describe("メッセージステータス。'N00'=正常。"),
        THT: z
          .string()
          .describe(
            "検索条件にヒットした全体件数（文字列）。ページングの要否判定に使う。"
          ),
        HTS: z.string().describe("今回応答の件数（≦ LM、文字列）。"),
        SRD: z.object({
          ST: z.array(stockSchema).describe("銘柄データ配列。"),
        }),
        D: z.string().describe("'MultiDataList' 固定。"),
        QRS: z.string().describe("クエリステータス。'0'=正常。"),
      }),
    })
    .optional(),
  ErrR: z.array(z.string()).optional().describe("エラーメッセージ配列。"),
};

// ----------------------------------------------------------------------------
// Tool registration
// ----------------------------------------------------------------------------
const description =
  "QUICK QrdspWebMulti.do APIの銘柄検索（サービス: ReqLstStk）。" +
  "キーワード（社名・略称・銘柄コード等）から株式銘柄を検索し、QCD（証券コード）と PRE（主市場コード）を取得する。" +
  "他のQUICKツール（get_quote / get_price_history / get_intraday_history 等）に渡す銘柄コードは " +
  "`QCD + '/' + PRE`（例: '7203/T'）に組み立てる。" +
  "1回の最大応答件数は51件で、それ以上は STR を更新してページング。" +
  "固定パラメータ PDC='QR1' / SHC='QIKA' / D='MultiDataList' は本ツールが自動付与する。";

export function registerSearchStocks(server: McpServer): void {
  server.registerTool(
    "search_stocks",
    {
      title: "銘柄検索",
      description,
      inputSchema,
      outputSchema,
    },
    async ({ KW, COR, UON, LM, STR, EXD, STJ, STE, SC, IT, MKW, FRO }) => {
      const SPM: Record<string, unknown> = {
        SN: "ReqLstStk",
        COR,
        UON,
        KW,
        STR: String(STR),
        LM: String(LM),
        EXD,
        SHC: "QIKA",
      };
      if (STJ !== undefined) SPM.STJ = STJ;
      if (STE !== undefined && STE.length > 0) SPM.STE = STE;
      if (SC !== undefined && SC.length > 0) SPM.SC = SC;
      if (IT !== undefined && IT.length > 0) SPM.IT = IT;
      if (MKW !== undefined) SPM.MKW = MKW;
      if (FRO !== undefined) SPM.FRO = FRO;

      const payload = {
        RP: {
          D: "MultiDataList",
          PDC: "QR1",
          OCF: true,
          SPM,
        },
      };

      const result = await callQuickApi<Record<string, unknown>>(
        "QrdspWebMulti.do",
        payload
      );
      return {
        content: [{ type: "text", text: JSON.stringify(result) }],
        structuredContent: result,
      };
    }
  );
}

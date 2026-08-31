import { z } from "zod";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { callQuickApi } from "./client.js";

// ----------------------------------------------------------------------------
// VGC（ニュースジャンルコード）
// ----------------------------------------------------------------------------
const VGC_CODES = [
  "QT",  // QUICK独自ニュース（NWHプレフィックス: <TECH>）
  "QE",  // QUICK経済・企業ニュース（<QEC>）
  "NQN", // NQN（日経クイックニュース）（<NQN>）
  "QEC", // QUICK経済（QEのサブジャンル）
  "NN",  // NQN国内
  "NS",  // NQN株式
  "NSX", // NQN株式詳細
  "FNS", // NQN先物
  "XBA", // 業績・決算ニュース
] as const;

// ----------------------------------------------------------------------------
// Input schema
// ----------------------------------------------------------------------------
const inputSchema = {
  VGC: z
    .array(z.enum(VGC_CODES))
    .min(1)
    .describe(
      [
        "検索対象のニュースジャンルコードの配列。",
        "公式ガイド掲載の主要3つ（推奨）:",
        "  QT  = QUICK独自ニュース（タイトル先頭タグ <TECH>）",
        "  QE  = QUICK経済・企業ニュース（<QEC>）",
        "  NQN = 日経クイックニュース（<NQN>）",
        "補助的なサブジャンル指定（記事側VGCで返るコードを検索条件に使う想定）:",
        "  QEC                  = QUICK経済のサブ",
        "  NN / NS / NSX / FNS  = NQN国内 / 株式 / 株式詳細 / 先物",
        "  XBA                  = 業績・決算",
        "※ 検索条件のVGCと、レスポンス各記事のVGCフィールドは別物。",
        "  特にNQNを ['NQN'] で検索しても各記事のVGCは ['NN','NS',...] のように",
        "  サブジャンルが入って返る点に注意。",
      ].join("\n")
    ),

  LMT: z
    .number()
    .int()
    .positive()
    .max(500)
    .default(100)
    .describe("取得件数の上限。"),

  BDO: z
    .enum(["0", "1"])
    .default("1")
    .describe("本文取得フラグ。0=タイトルのみ、1=本文(NWT)も含む。"),

  KW: z
    .array(z.string())
    .optional()
    .describe("キーワード絞り込み。空配列を渡すと検索条件にならない。"),

  LO: z
    .enum(["1", "2"])
    .optional()
    .describe(
      "KW複数指定時の論理演算子。1=AND, 2=OR。KWが1件以下なら省略可。"
    ),

  EXK: z.array(z.string()).optional().describe("除外キーワード。"),

  DTF: z
    .string()
    .regex(/^\d{12}$/)
    .optional()
    .describe("日時From（'YYYYMMDDhhmm'12桁）。"),

  DTT: z
    .string()
    .regex(/^\d{12}$/)
    .optional()
    .describe("日時To（'YYYYMMDDhhmm'12桁）。"),

  QC: z
    .array(z.string())
    .optional()
    .describe(
      "銘柄コードによる絞り込み。get_quote/get_price_history と異なり、" +
        "**サフィックス（/T 等）を外した数字部分のみ**で指定する（例: ['7974'], ['7974','7203']）。"
    ),
};

// ----------------------------------------------------------------------------
// Output schema
// ----------------------------------------------------------------------------
const newsItemSchema = z.object({
  NVI: z
    .string()
    .describe(
      "ニュースID（11文字）。本文を newsArticle.do で個別取得する場合は NC11=1 を指定する。"
    ),
  NWH: z
    .string()
    .describe(
      "タイトル。先頭に <TECH>/<QEC>/<NQN> 等のジャンル表示タグが入る。"
    ),
  NWT: z
    .string()
    .optional()
    .describe("本文テキスト。BDO='1' を指定したときのみ含まれる。"),
  DST: z.string().describe("表示用日時（'YYYYMMDDhhmm'）。"),
  NWD: z.string().describe("ニュース日時（'YYYYMMDDhhmm'）。"),
  CTS: z.string().describe("コンテンツタイムスタンプ（'YYYYMMDDhhmmss'）。"),
  VGC: z
    .array(z.string())
    .describe(
      "この記事が属するジャンルコードの配列。検索指定の VGC とは別物" +
        "（NQNなら ['NN','NS','NSX',...] のように複数入ることがある）。"
    ),
  NTF: z.string().describe("ニュースタイプフラグ。"),
  UPG: z.string().describe("更新フラグ。'0'=通常、'1'=更新あり。"),
  IMM: z.string().describe("重要フラグ。' '=通常、'*'=重要。"),
});

const outputSchema = {
  S: z.string().describe("応答全体ステータス。空文字=正常。"),
  OD: z.string().describe("データ取得日時（'YYYY/MM/DD hh:mm:ss'）"),
  D: z
    .object({
      RD: z
        .object({
          MSS: z
            .string()
            .describe(
              "メッセージステータス。'N00'=正常、'N1B'=エラー（TG省略・ジャンル不正等）。"
            ),
          IRF: z.string().describe("削除ありフラグ。'0'=削除なし。"),
          TNC: z
            .string()
            .describe(
              "検索条件にヒットした総件数（文字列）。LMT より多くてもレスポンスに入るのは LMT 件まで。"
            ),
          HTS: z
            .string()
            .describe("今回のレスポンスに含まれる件数（≦ LMT、文字列）。"),
          NWS: z.array(newsItemSchema).describe("ニュース配列。"),
        })
        .describe("レスポンス本体。"),
    })
    .optional(),
  ErrR: z.array(z.string()).optional().describe("エラーメッセージ配列。"),
};

// ----------------------------------------------------------------------------
// Tool registration
// ----------------------------------------------------------------------------
const description =
  "QUICK QrdspWebMulti.do APIを叩き、QUICK / NQN ニュースを検索する（サービス: ReqLstNws）。" +
  "ジャンル(VGC)・キーワード(KW)・期間(DTF/DTT)・銘柄(QC)で絞り込み可能。" +
  "BDO='1' で本文(NWT)も取得できる。" +
  "内部的に必須の SPM.TG='2' / SOO='1' / TAO='1' は本ツールが自動付与する（TG省略はMSS=N1Bエラー）。" +
  "QC は **数字のみ**（例: '7974'）で指定する点が他のQUICKツールと異なるので注意。" +
  "本文を個別取得したい場合は NVI（11文字ID）を newsArticle.do に NC11=1 で渡す（本ツールでは未対応）。";

export function registerSearchNews(server: McpServer): void {
  server.registerTool(
    "search_news",
    {
      title: "ニュース検索",
      description,
      inputSchema,
      outputSchema,
    },
    async ({ VGC, LMT, BDO, KW, LO, EXK, DTF, DTT, QC }) => {
      const SPM: Record<string, unknown> = {
        SN: "ReqLstNws",
        TG: "2", // 必須。省略すると MSS=N1B
      };
      if (KW !== undefined && KW.length > 0) SPM.KW = KW;
      if (LO !== undefined) SPM.LO = LO;
      if (EXK !== undefined && EXK.length > 0) SPM.EXK = EXK;
      if (DTF !== undefined) SPM.DTF = DTF;
      if (DTT !== undefined) SPM.DTT = DTT;
      if (QC !== undefined && QC.length > 0) SPM.QC = QC;

      const payload = {
        RP: {
          D: "MultiNewsList",
          VGC,
          BDO,
          SOO: "1", // タグ上限解除（固定）
          TAO: "1", // タグ全件応答（固定）
          LMT: String(LMT),
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

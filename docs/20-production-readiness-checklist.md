# 本番運用チェックリスト(WAF・DCR・運用): 継続更新用

> この章で分かること
> ECS(API Gateway)アーキテクチャで商用リモートMCPサーバーを本番運用するために、WAF・DCR(動的クライアント登録)・運用の3領域で満たすべき要件を固定IDで一覧化し、検証方法・現在の状態・証跡を1行ずつ管理する。単発の実機確認で終わらせず、terraform変更時・月次・MCP新版リリース時に同じ表を再評価する。要件の根拠と検証手順は[19-weekly-verification-plan-week5.md](./19-weekly-verification-plan-week5.md)に記載する。

作成日: 2026-09-10 | 対象: ECS + API Gateway構成(pattern4)のみ。AgentCore Runtimeは対象外(ホスティング方式として不採用、[00-handoff.md §16.1](./00-handoff.md))

---

## TL;DR

| # | 論点 | 結論 |
|---|---|---|
| 1 | チェックリストの位置づけ | WAF(`WAF-NN`)、DCR(仕様番号+連番)、運用(`OPS-NN`)を同一スキーマで管理する。自動テスト(`scripts/waf_attack_tests.py`、`scripts/dcr_conformance_tests.py`)の結果IDと1対1で対応させ、表の「状態」「最終実施」「証跡」列のみを更新する運用にする(§1) |
| 2 | 2026-09-14時点の状態 | WAF: CloudFront + WAFをplaygroundに構築しBlockモードで45パターンを実行、35件がBLOCK・誤検知ゼロ。全ルート保護(WAF-01)と真のクライアントIP(WAF-02)を確認。DCR: 最小スコープ修正後の再検証で合格33・不合格2(残りは`WWW-Authenticate`とRFC 7592)。Claude Code / Claude.aiからの自己登録E2Eは未実施(§2、§3) |
| 3 | 再評価のトリガー | `terraform/`または`terraform-playground-pattern4/`のWAF・API Gateway・Lambda関連ファイル変更時、月次、MCPプロトコル新版リリース時、Anthropicコネクタ仕様変更時(§5) |

---

## 1. スキーマと運用ルール

| 列 | 内容 |
|---|---|
| ID | 固定ID。WAFは`WAF-NN`、DCRは`7591-NN` / `7592-NN` / `8414-NN` / `9728-NN` / `MCP-NN` / `9700-NN` / `CL-NN`(Claude固有)、運用は`OPS-NN` |
| 要件 | 仕様の規範文(MUST / SHOULD)または「MCP JSON-RPCボディ内のSQLiを遮断する」のような具体要件 |
| 根拠 | 公式ドキュメント、RFC、FISC安全対策基準 / 金融庁ガイドラインの項番、内部docsの節 |
| 検証方法 | 自動テストのID、手動手順、terraform属性の確認コマンド |
| 重要度 | 必須(相互運用性または商用運用に不可欠)/ 推奨 |
| 状態 | 未着手 / 検証中 / 合格 / 不合格 / 例外承認(期限付き)/ 要確認(仕様の解釈が未確定) |
| 最終実施 | 日付と環境(playground / 本番) |
| 証跡 | `docs/evidence/`配下のJSON、CloudWatch Logs Insightsクエリ、画面キャプチャへのリンク |

運用ルール:

1. 自動テストはIDごとに結果を出力し、この表の行と1対1で対応させる。
2. 再評価のトリガー(§5)ごとに全行を再実行し、状態・最終実施・証跡の3列だけを更新する。要件・根拠・検証方法の変更は仕様変更として履歴(§6)に記録する。
3. 不合格および例外承認は[00-handoff.md](./00-handoff.md)にも転記する。
4. 例外承認は§4の例外台帳に、対象ID・理由・承認者・期限を必ず記録する。

---

## 2. WAF(`WAF-NN`)

攻撃パターンID(A01〜A25)の詳細と注入方法は[19-weekly-verification-plan-week5.md §1.4](./19-weekly-verification-plan-week5.md)を参照。

### 2.1 保護範囲・配置

| ID | 要件 | 根拠 | 検証方法 | 重要度 | 状態 | 最終実施 | 証跡 |
|---|---|---|---|---|---|---|---|
| WAF-01 | `/mcp`だけでなく`/register`・`/token`・`/authorize`・`/.well-known`の全ルートがWAFの検査対象になる | 18番 §2.3(ALBアタッチでは無認証経路が未保護) | ハーネスをルート別に実行しBlockを確認(S1) | 必須 | 合格: `/register`のSQLi(A02r)と`/token`のXSS(A01t)もWAFログ上BLOCK。ALBアタッチ構成では到達しない経路が保護された | 2026-09-14 playground | [2026-09-14-waf-cloudfront-block.json](./evidence/2026-09-14-waf-cloudfront-block.json) |
| WAF-02 | WAFが評価する送信元IPが真のクライアントIPである(VPC Link ENIに集約されない) | 19番 §1.1 D2 | WAFログ`httpRequest.clientIp`と検証端末の公開IPを比較(S2) | 必須 | 合格: WAFログ`clientIp`が検証端末の公開IP(Geoラベル JP)。ALBアタッチ構成ではVPC Link ENIの10.0.11.94に集約され不合格([2026-09-13-waf-alb-count.json](./evidence/2026-09-13-waf-alb-count.json)) | 2026-09-14 playground | [2026-09-14-waf-cloudfront-block.json](./evidence/2026-09-14-waf-cloudfront-block.json) |
| WAF-03 | CloudFrontを経由しないexecute-apiへの直アクセスが全ルートで拒否される(バイパス対策) | 19番 §1.3 | 秘密ヘッダ無しで各ルートを直接呼び出し401/403(S10) | 必須 | 未着手 | - | - |
| WAF-04 | Cognito Hosted UIおよび`/oauth2/token`がWAFで保護される | 19番 §1.1 D9 | Cognito User PoolへのWeb ACL関連付けをterraformとコンソールで確認 | 必須 | 未着手 | - | - |
| WAF-05 | カスタムドメインでissuer・エンドポイントURLが固定され、経路変更時に登録済みDCRクライアントが無効化されない | 19番 §1.1 D5 | カスタムドメイン経由でClaude Codeの再接続が成立(S7) | 必須 | 未着手 | - | - |

### 2.2 攻撃パターン遮断

| ID | 要件 | 根拠 | 検証方法 | 重要度 | 状態 | 最終実施 | 証跡 |
|---|---|---|---|---|---|---|---|
| WAF-10 | JSON-RPCボディ内のXSSを遮断する(A01) | AWS Managed Rules CommonRuleSet | `waf_attack_tests.py --pattern A01` | 必須 | 合格: `CrossSiteScripting_BODY`および`CrossSiteScripting_QUERYARGUMENTS`でBLOCK | 2026-09-14 playground | [2026-09-14-waf-cloudfront-block.json](./evidence/2026-09-14-waf-cloudfront-block.json) |
| WAF-11 | JSON-RPCボディ内のSQLiを遮断する(A02) | AWS Managed Rules SQLiRuleSet | `--pattern A02` | 必須 | 合格: `SQLi_BODY`でBLOCK(`/mcp`・`/register`の両方) | 2026-09-14 playground | [2026-09-14-waf-cloudfront-block.json](./evidence/2026-09-14-waf-cloudfront-block.json) |
| WAF-12 | Log4j/JNDI・Javaデシリアライズ等の既知の悪性入力を遮断する(A03、A04) | KnownBadInputsRuleSet | `--pattern A03,A04` | 必須 | 不合格: Log4j/JNDIは`Log4JRCE_BODY`/`_HEADER`/`_QUERYSTRING`でBLOCKするが、**JSON文字列値に埋めたBase64のJavaシリアライズ列(A04)はBLOCKもCOUNTもされない**。カスタムルールの要否を判断する | 2026-09-14 playground | [2026-09-14-waf-cloudfront-block.json](./evidence/2026-09-14-waf-cloudfront-block.json) |
| WAF-13 | パストラバーサル・LFI・SSRF(EC2メタデータ)を遮断する(A05〜A07) | CommonRuleSet、LinuxRuleSet | `--pattern A05,A06,A07` | 必須 | 合格: `GenericLFI_BODY`・`EC2MetaDataSSRF_BODY`でBLOCK。URIのトラバーサル(A05)はWAF評価前にCloudFrontが400で拒否 | 2026-09-14 playground | [2026-09-14-waf-cloudfront-block.json](./evidence/2026-09-14-waf-cloudfront-block.json) |
| WAF-14 | RFI・Host異常・禁止メソッド・悪性UAを遮断する(A08〜A11) | CommonRuleSet、KnownBadInputsRuleSet | `--pattern A08,A09,A10,A11` | 推奨 | 合格: `UserAgent_BadBots_HEADER`・`Host_localhost_HEADER`・`PROPFIND_METHOD`でBLOCK。`GenericRFI_BODY`(A08)は正当な引数のURLを誤検知するため意図的にcount上書き | 2026-09-14 playground | [2026-09-14-waf-cloudfront-block.json](./evidence/2026-09-14-waf-cloudfront-block.json) |
| WAF-15 | 巨大ボディを遮断し、WAF検査上限とサーバー側上限(100KB)の整合が取れている(A12、A13) | AWS WAF oversize handling | `--pattern A12,A13` | 必須 | 合格: 70KB・200KBのボディをカスタムルール`body-over-64kb`でBLOCK。`SizeRestrictions_BODY`(8KB)はcount上書き。ボディ検査上限は16KB→64KBへ引き上げ済み | 2026-09-14 playground | [2026-09-14-waf-cloudfront-block.json](./evidence/2026-09-14-waf-cloudfront-block.json) |
| WAF-16 | 不正JSON・JSON-RPCバッチ・プロトコルバージョン異常でWAFが誤動作せずサーバーが400を返す(A14、A15、A23) | MCP仕様(バッチ非対応) | `--pattern A14,A15,A23` | 推奨 | 合格: JSON-RPCバッチ(A15)をカスタムルール`jsonrpc-batch`でBLOCK。不正JSON(A14)・未知のプロトコル版数(A23a)はWAFが誤検知せずサーバーが400を返す | 2026-09-14 playground | [2026-09-14-waf-cloudfront-block.json](./evidence/2026-09-14-waf-cloudfront-block.json) |
| WAF-17 | IP単位およびクライアント単位のフラッディングを遮断する(A16) | AWS WAF rate-based rule | `--pattern A16`(専用低閾値ルールで実施) | 必須 | 検証中: 60リクエストのバーストでは設定閾値(IP 2000/5分、Authorization 1000/5分)に到達せず未発火。本番相当の負荷での検証が必要 | 2026-09-14 playground | [2026-09-14-waf-ratelimit.json](./evidence/2026-09-14-waf-ratelimit.json) |
| WAF-18 | `/register`乱用と`/token`ブルートフォースを遮断する(A17、A18) | RFC 7591 §5、19番 §1.5 | `--pattern A17,A18` | 必須 | 合格: `/register`は60回中55回が429(Lambda内IP別カウンタ+APIGWスロットル)。`/token`は閾値を一時的に10/60秒へ下げ、40リクエスト全件を`rate-ip-auth-endpoints`がBLOCK(検証後に50/300秒へ復帰済み) | 2026-09-14 playground | [2026-09-14-waf-ratelimit.json](./evidence/2026-09-14-waf-ratelimit.json) |
| WAF-19 | Geo・IPレピュテーション・匿名IP・ボット制御のルールが正規クライアント(Claude.ai等のクラウド発信)を遮断しない(A19〜A21) | 19番 §1.1 D3 | Countモードでラベル観測、正規クライアントのラベルを記録 | 必須 | 検証中: Geoラベル(`awswaf:clientip:geo:country:JP`)の付与を確認。`AnonymousIpList`は恒久count、Geoはcount運用。Anthropic egress(160.79.104.0/21)での観測は未実施 | 2026-09-14 playground | [2026-09-14-waf-cloudfront-block.json](./evidence/2026-09-14-waf-cloudfront-block.json) |
| WAF-20 | `x-cognito-sub`なりすましヘッダを送っても、サーバーはAuthorizer由来のsubで認可判定する(A24) | 09番、19番 §1.1 D8 | `--pattern A24`+ECSログ確認(S4) | 必須 | 検証中(基準線取得、WAF未適用) | 2026-09-13 playground | [2026-09-13-waf-baseline.json](./evidence/2026-09-13-waf-baseline.json) |
| WAF-21 | 正常系コーパス(6ツール×長文・URL・SQL風・記号・日本語)が全件200になる(A25) | 19番 §1.1 D4 | `--pattern A25`(S3) | 必須 | 合格: 正常系コーパス13件(日本語・長文12KB・URL・SQL風語句・記号)が全件200。ボディ検査上限を64KBへ引き上げたことで長文の誤検知が解消 | 2026-09-14 playground | [2026-09-14-waf-cloudfront-block.json](./evidence/2026-09-14-waf-cloudfront-block.json) |

### 2.3 ログ・監視・運用

| ID | 要件 | 根拠 | 検証方法 | 重要度 | 状態 | 最終実施 | 証跡 |
|---|---|---|---|---|---|---|---|
| WAF-30 | WAFログがCloudWatch Logsに90日保持され、`Authorization`ヘッダが秘匿されている | 05番 §5、AWS WAF logging | ロググループ設定と`redacted_fields`を確認 | 必須 | 未着手 | - | - |
| WAF-31 | WAFログ・API Gatewayアクセスログが改ざん防止付きストレージ(S3 Object Lock)に到達し、削除操作が拒否される | 05番 §5(FISC: ログの完全性) | 削除試行が拒否されることを確認(S8) | 必須 | 未着手 | - | - |
| WAF-32 | `BlockedRequests`・`CountedRequests`急増のアラームが発報する | 19番 §1.5 | ハーネス実行でアラーム発報(S9) | 必須 | 未着手 | - | - |
| WAF-33 | 全ルールCount運用からBlockへの切り替え手順と例外(scope-down / count上書き)が文書化され、例外台帳に記録されている | 19番 §1.5 | terraform `locals.mode`と§4例外台帳のレビュー | 必須 | 未着手 | - | - |
| WAF-34 | マネージドルールの更新追従・月次Countレビュー・四半期ハーネス再実行が運用手順に含まれる | 19番 §1.5 | 手順書レビュー | 推奨 | 未着手 | - | - |

---

## 3. DCR(動的クライアント登録)と認可

各行の現状(コード上の根拠)と修正方針は[19-weekly-verification-plan-week5.md §2](./19-weekly-verification-plan-week5.md)を参照。自動テストは`scripts/dcr_conformance_tests.py --id <ID>`。

### 3.1 RFC 7591(登録)

| ID | 要件 | 根拠 | 検証方法 | 重要度 | 状態 | 最終実施 | 証跡 |
|---|---|---|---|---|---|---|---|
| 7591-01 | 登録エンドポイントはTLS上の`application/json` POST | RFC 7591 §3 | `--id 7591-01` | 必須 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-postfix.json](./evidence/2026-09-13-dcr-postfix.json) |
| 7591-02 | 理解しないクライアントメタデータは無視する | RFC 7591 §2 | `--id 7591-02`(`software_id`等を送信) | 必須 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-postfix.json](./evidence/2026-09-13-dcr-postfix.json) |
| 7591-03 | 登録済みの全メタデータ(サーバーが置換した値を含む)をレスポンスで返す | RFC 7591 §3.2.1 | `--id 7591-03`(`client_name`とCognito側の名称の関係を文書化) | 推奨 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-postfix.json](./evidence/2026-09-13-dcr-postfix.json) |
| 7591-04 | `token_endpoint_auth_method`省略時の既定値が`client_secret_basic`である、または逸脱理由が文書化されている | RFC 7591 §2 | `--id 7591-04` | 推奨 | 要確認: 既定値=none, client_secret発行=なし (判断事項: RFC既定に合わせるか逸脱を文書化するか) | 2026-09-13 playground | [2026-09-13-dcr-postfix.json](./evidence/2026-09-13-dcr-postfix.json) |
| 7591-05 | `response_types`を受理し`grant_types`との整合性を検証する | RFC 7591 §2.1 | `--id 7591-05`(`response_types: ["token"]`で400) | 推奨 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-postfix.json](./evidence/2026-09-13-dcr-postfix.json) |
| 7591-06 | `redirect_uris`を検証し、フラグメント付きURIを400で拒否する | RFC 7591 §2、RFC 6749 §3.1.2 | `--id 7591-06` | 必須 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-postfix.json](./evidence/2026-09-13-dcr-postfix.json) |
| 7591-07 | `client_secret_expires_at`はsecret発行時のみ返す | RFC 7591 §3.2.1 | `--id 7591-07` | 推奨 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-postfix.json](./evidence/2026-09-13-dcr-postfix.json) |
| 7591-09 | エラーは400と`error`/`error_description`のRFC形式で返し、Cognito起因の400相当を500にしない | RFC 7591 §3.2.2 | `--id 7591-09`(129文字name、101件URI) | 必須 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-postfix.json](./evidence/2026-09-13-dcr-postfix.json) |
| 7591-10 | レスポンスに`Cache-Control: no-store`と`Pragma: no-cache`を付ける | RFC 7591 §3.2.1(規範か例示かは要確認) | `--id 7591-10` | 推奨 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-postfix.json](./evidence/2026-09-13-dcr-postfix.json) |
| 7591-11 | オープン登録に対するレート制限・登録数上限がある | RFC 7591 §5 | `--id 7591-11`(連続POSTで429)、`--flood` | 必須 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-postfix.json](./evidence/2026-09-13-dcr-postfix.json) |
| 7591-12 | メタデータを自己申告として扱い、`logo_uri`等の偽装対策方針が文書化されている | RFC 7591 §5 | コードレビュー | 推奨 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-postfix.json](./evidence/2026-09-13-dcr-postfix.json) |

### 3.2 RFC 7592(クライアント構成管理)

| ID | 要件 | 根拠 | 検証方法 | 重要度 | 状態 | 最終実施 | 証跡 |
|---|---|---|---|---|---|---|---|
| 7592-01 | 登録レスポンスに`registration_access_token`と`registration_client_uri`を返す | RFC 7592 §2 | `--id 7592-01` | 推奨(翌週以降) | 不合格: registration_client_uri=None | 2026-09-13 playground | [2026-09-13-dcr-postfix.json](./evidence/2026-09-13-dcr-postfix.json) |
| 7592-02 | `registration_client_uri`へのGET/PUT/DELETEをBearer照合で提供する | RFC 7592 §2.1〜2.3 | `--id 7592-02` | 推奨(翌週以降) | 未着手 | 2026-09-13 playground | [2026-09-13-dcr-postfix.json](./evidence/2026-09-13-dcr-postfix.json) |

### 3.3 RFC 8414(認可サーバーメタデータ)

| ID | 要件 | 根拠 | 検証方法 | 重要度 | 状態 | 最終実施 | 証跡 |
|---|---|---|---|---|---|---|---|
| 8414-01 | `issuer`がwell-known URL構築元の識別子と一致する | RFC 8414 §3.3 | `--id 8414-01` | 必須 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-mcp04.json](./evidence/2026-09-13-dcr-mcp04.json) |
| 8414-02 | メタデータの`issuer`とトークンの`iss`の不一致が方針として文書化され、RFC 9207の`iss`パラメータ有無が監視されている | RFC 8414、RFC 9207 | `--id 8414-02`(認可レスポンスの`iss`有無を記録) | 必須 | 要確認: authorization_response_iss_parameter_supported=None; 実際のコールバ | 2026-09-13 playground | [2026-09-13-dcr-mcp04.json](./evidence/2026-09-13-dcr-mcp04.json) |
| 8414-03 | `jwks_uri`を公開する | RFC 8414 §2 | `--id 8414-03` | 推奨 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-mcp04.json](./evidence/2026-09-13-dcr-mcp04.json) |
| 8414-04 | `scopes_supported`にAuthorizerが要求する`invoke`スコープが含まれる | RFC 8414 §2、Anthropicコネクタ仕様 | `--id 8414-04` | 必須 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-mcp04.json](./evidence/2026-09-13-dcr-mcp04.json) |
| 8414-05 | `code_challenge_methods_supported`に`S256`を含む | MCP Authorization | `--id 8414-05` | 必須 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-mcp04.json](./evidence/2026-09-13-dcr-mcp04.json) |
| 8414-06 | `registration_endpoint`を公開する | RFC 8414 §2 | `--id 8414-06` | 必須 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-mcp04.json](./evidence/2026-09-13-dcr-mcp04.json) |
| 8414-07 | `token_endpoint_auth_methods_supported`に`none`を含む | Anthropicコネクタ仕様 | `--id 8414-07` | 必須 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-mcp04.json](./evidence/2026-09-13-dcr-mcp04.json) |
| 8414-08 | `revocation_endpoint`を公開する | RFC 8414 §2 | `--id 8414-08` | 推奨 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-mcp04.json](./evidence/2026-09-13-dcr-mcp04.json) |
| 8414-10 | `/.well-known/openid-configuration`ミラーを提供する | MCP Authorization(第2フォールバック) | `--id 8414-10` | 推奨 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-mcp04.json](./evidence/2026-09-13-dcr-mcp04.json) |
| 8414-11 | CIMD(`client_id_metadata_document_supported`)対応の要否が判断・文書化されている | MCP 2026-07-28 | 方針レビュー | 推奨 | 要確認: client_id_metadata_document_supported=None (方針判断: CL-07) | 2026-09-13 playground | [2026-09-13-dcr-mcp04.json](./evidence/2026-09-13-dcr-mcp04.json) |

### 3.4 RFC 9728(保護リソースメタデータ)と発見経路

| ID | 要件 | 根拠 | 検証方法 | 重要度 | 状態 | 最終実施 | 証跡 |
|---|---|---|---|---|---|---|---|
| 9728-01 | `resource`がwell-known構築元と一致し、`authorization_servers`を含む | RFC 9728 §3.3 | `--id 9728-01` | 必須 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-mcp04.json](./evidence/2026-09-13-dcr-mcp04.json) |
| 9728-03 | `scopes_supported`に`invoke`スコープを含む(Claudeのスコープ選択根拠) | RFC 9728 §2、Anthropicコネクタ仕様 | `--id 9728-03` | 必須 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-mcp04.json](./evidence/2026-09-13-dcr-mcp04.json) |
| 9728-04 | `bearer_methods_supported`・`resource_name`を含む | RFC 9728 §2 | `--id 9728-04` | 推奨 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-mcp04.json](./evidence/2026-09-13-dcr-mcp04.json) |
| 9728-05 | 401応答に`WWW-Authenticate: Bearer resource_metadata=...`を含む、またはwell-known経路で発見できる | MCP 2026-07-28(択一MUST) | `--id 9728-05` | 推奨 | 不合格: 401 だが WWW-Authenticate 無し(現行MCP仕様ではwell-known経路で代替可、scopeヒン | 2026-09-13 playground | [2026-09-13-dcr-mcp04.json](./evidence/2026-09-13-dcr-mcp04.json) |
| 9728-06 | パス無しの`/.well-known/oauth-protected-resource`も応答する | Anthropicコネクタ仕様(第2プローブ) | `--id 9728-06` | 推奨 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-mcp04.json](./evidence/2026-09-13-dcr-mcp04.json) |

### 3.5 MCP Authorization / OAuth 2.1 / RFC 9700

| ID | 要件 | 根拠 | 検証方法 | 重要度 | 状態 | 最終実施 | 証跡 |
|---|---|---|---|---|---|---|---|
| MCP-01 | PKCE S256を必須とし、メタデータで広告する | MCP Authorization | `--id MCP-01` | 必須 | 未着手(コード上は準拠) | - | - |
| MCP-02 | 認可・トークン両エンドポイントで`resource`パラメータを受理する | RFC 8707、MCP Authorization | `--id MCP-02`(`/token`での受理は要確認) | 必須 | 要確認 | - | - |
| MCP-03 | Authorizerがトークンの`aud`を検証する(`aud`が無いclient_credentialsトークンは`client_id`+`CLIENT#`で代替) | MCP Authorization(MUST)、RFC 9700 §2.3 | `--id MCP-03`(`--no-resource`で拒否) | 必須 | 未着手 | - | - |
| MCP-04 | 無効・期限切れトークンには401を返す(403ではない) | MCP Authorization、Anthropicのリフレッシュ挙動 | `--id MCP-04`(期限切れトークン) | 必須 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-mcp04.json](./evidence/2026-09-13-dcr-mcp04.json) |
| MCP-05 | 公開クライアントのリフレッシュトークンをローテーションする | MCP Authorization(MUST)、RFC 9700 §2.2.2 | `DescribeUserPoolClient`で`RefreshTokenRotation` | 必須 | 未着手 | - | - |
| MCP-06 | アクセストークンの有効期間が短命(商用値を決定) | MCP Authorization(SHOULD) | `DescribeUserPoolClient` | 推奨 | 未着手 | - | - |
| MCP-07 | redirect URIの完全一致(localhostのポートは除外可) | RFC 9700 §2.1、RFC 8252 | E2E(Claude Codeの動的ポート) | 必須 | 未着手(コード上は準拠) | - | - |
| MCP-11 | 受け取ったトークンを上流へ転送しない(token passthrough禁止) | MCP Security Best Practices | コードレビュー(`x-cognito-sub`のみ転送) | 必須 | 未着手(コード上は準拠) | - | - |
| 9700-07 | implicit grantが無効 | RFC 9700 §2.1.2 | `DescribeUserPoolClient` | 必須 | 未着手(コード上は準拠) | - | - |

### 3.6 Authorizer・失効・監査

| ID | 要件 | 根拠 | 検証方法 | 重要度 | 状態 | 最終実施 | 証跡 |
|---|---|---|---|---|---|---|---|
| AUTHZ-01 | `CLIENT#`レコードが存在しないクライアントは拒否する(deny-on-missing) | 19番 §2.3 B1 | 未登録client_idのトークンで403(DS7) | 必須 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-authz.json](./evidence/2026-09-13-dcr-authz.json) |
| AUTHZ-02 | クライアント削除・失効直後に既発行トークンが拒否される | 19番 §2.3 B4 | `cli delete-client`直後に403(DS7) | 必須 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-authz.json](./evidence/2026-09-13-dcr-authz.json) |
| AUTHZ-03 | サーバー側の`extractSub()`がJWT未検証デコードのフォールバックに依存しない | 09番、19番 §1.1 D8 | コードレビュー | 必須 | 未着手 | - | - |
| AUTHZ-04 | API Gatewayアクセスログに送信元IP・ルート・ステータス・Authorizerエラーが残る | 05番 §5、19番 §2.3 B6 | ステージ設定とログ確認(DS9) | 必須 | 未着手 | - | - |
| AUTHZ-05 | DCRクライアント数の上限と未使用クライアントの掃除方針がある | Anthropicコネクタ仕様(接続ごとに登録)、Cognitoクォータ | `--flood`で429、方針レビュー | 必須 | 未着手 | - | - |
| AUTHZ-06 | DynamoDBテーブル名がハードコードされず、terraform管理のテーブル名が3コンポーネント(Lambda / server / cli)とIAMで一致する | 19番 §2.1 F12 | コードレビュー、`terraform plan` | 必須 | 未着手 | - | - |

### 3.7 Claude固有

| ID | 要件 | 根拠 | 検証方法 | 重要度 | 状態 | 最終実施 | 証跡 |
|---|---|---|---|---|---|---|---|
| CL-01 | Claude Codeから人手のログイン以外の操作なしで自己登録・認可・`tools/list`が成立する | Anthropicコネクタ仕様 | E2E(DS1) | 必須 | 未着手 | - | - |
| CL-02 | Claude.aiカスタムコネクタで同上 | 同上 | E2E(DS2) | 必須 | 未着手 | - | - |
| CL-03 | DCRで作成したクライアントでCognito Managed Loginの画面が表示される(ブランディング適用) | Cognito `CreateUserPoolClient`仕様 | E2E(19番 §2.3 A1) | 必須 | 要確認 | - | - |
| CL-04 | discovery・registration・tokenの各応答が10秒以内 | Anthropicコネクタ仕様 | CloudWatch Duration | 必須 | 合格 | 2026-09-13 playground | [2026-09-13-dcr-postfix.json](./evidence/2026-09-13-dcr-postfix.json) |
| CL-05 | 60分経過後もClaude Codeが再認可なしで継続利用できる(401によるリフレッシュ) | Anthropicコネクタ仕様 | E2E(DS5) | 必須 | 未着手 | - | - |
| CL-06 | DCR(登録)とテナント認可(`USER#`による人手承認)が分離され、未承認ユーザーは403、承認後200 | 18番 §1.1 | E2E(DS3) | 必須 | 未着手 | - | - |
| CL-07 | 商用ディレクトリ公開時の認証方式(DCR継続 / CIMD / `oauth_anthropic_creds`)の選択が判断・文書化されている | Anthropicコネクタ仕様、MCP 2026-07-28 | 方針レビュー | 推奨 | 未着手 | - | - |

---

## 3.8 運用(`OPS-NN`)

[21-commercial-remote-mcp-operations-research.md §6](./21-commercial-remote-mcp-operations-research.md)で提案した行。根拠はAgentCore Gatewayの標準挙動、AWS参照アーキテクチャ、MCP仕様、Anthropicコネクタ仕様。

| ID | 要件 | 根拠 | 検証方法 | 重要度 | 状態 | 最終実施 | 証跡 |
|---|---|---|---|---|---|---|---|
| OPS-01 | 401応答に`WWW-Authenticate: Bearer resource_metadata="...", scope="..."`を付与する | 21番 §2.2、§4.3 | `dcr_conformance_tests.py --id 9728-05` | 推奨 | 不合格: CloudFront Functionsでは401に付与できない(viewer-response関数が起動しない)。Lambda@Edge origin-responseまたはREST API移行が必要(19番 §1.10) | 2026-09-14 playground | [2026-09-13-dcr-postfix.json](./evidence/2026-09-13-dcr-postfix.json) |
| OPS-02 | トークン無効(401)とスコープ不足(403 + `error="insufficient_scope"`)を区別する | 21番 §2.2 | 不足スコープのトークンで`curl -i` | 推奨 | 未着手 | - | - |
| OPS-03 | 認可イベント(拒否理由、`sub`、`client_id`)をログに残し、`sub`をPII相当として保持・アクセス制御を定める | 21番 §2.4 | ログ設定レビュー | 必須 | 検証中: API Gatewayアクセスログに`authorizerSub`・`authorizerClient`・拒否理由を出力するよう設定済み。保持ポリシーの定義は未着手 | 2026-09-13 playground | - |
| OPS-04 | オリジン保護の秘密ヘッダ(`X-Origin-Verify`)をSecrets Managerで管理しローテーションする | 21番 §3.2 | terraformレビュー、ローテーション手順の実施 | 必須 | 未着手: 現在は`random_password`でterraform stateに保持し、Authorizerは観測モード | 2026-09-14 playground | - |
| OPS-05 | Anthropic egress `160.79.104.0/21`をMCPサーバーおよびIdP前段のWAF許可リストに含める | 21番 §4.3 | Countモードのラベル観測、許可リストのterraform | 必須 | 未着手 | - | - |
| OPS-06 | DCRで増える登録クライアント数を監視し、上限・掃除・方式選択の判断基準を持つ | 21番 §4.3 | `COUNTER#dcr`のアラーム、月次レビュー | 必須 | 検証中: 上限(`MAX_DCR_CLIENTS`=200)とIP別レート制限(5/分)を実装し、登録・削除でカウンタが増減することを確認。アラームは未設定 | 2026-09-14 playground | [2026-09-14-waf-ratelimit.json](./evidence/2026-09-14-waf-ratelimit.json) |
| OPS-07 | discovery / registration / tokenの応答を10秒以内(目標3秒以内)に保つ | 21番 §4.3 | CloudWatch Duration、`--id CL-04` | 必須 | 合格: 登録応答2.17秒(コールドスタート込み) | 2026-09-13 playground | [2026-09-13-dcr-postfix.json](./evidence/2026-09-13-dcr-postfix.json) |
| OPS-08 | 公開URL(issuer、`resource`、redirect登録先)をカスタムドメインで固定する | 21番 §3.2、19番 D5 | カスタムドメイン経由のE2E(S7) | 必須 | 未着手: 現在はCloudFront既定ドメインで検証しており、PRMの`resource`はAPI Gateway URLのまま不一致 | - | - |
| OPS-09 | WAFは全ルールCountで観測し、誤検知ゼロを確認したルールから段階的にBlockへ切り替える | 21番 §3.2 | terraform `locals.waf_mode`と例外台帳 | 必須 | 合格: Countで観測 → 誤検知2件(`SizeRestrictions_BODY`、`GenericRFI_BODY`)をcount上書きし例外台帳に登録 → Blockへ切替 | 2026-09-14 playground | [2026-09-14-waf-cloudfront-block.json](./evidence/2026-09-14-waf-cloudfront-block.json) |
| OPS-10 | MCPプロトコル新版リリース時にWAFの版数許可リストとサーバー側の対応版を同時に更新する手順を持つ | 21番 §2.3 | 手順書レビュー | 推奨 | 未着手 | - | - |

---

## 4. 例外台帳

| 対象ID | 例外内容 | 理由 | 承認者 | 期限 | 記録日 |
|---|---|---|---|---|---|
| WAF-14 | `AWSManagedRulesCommonRuleSet`の`GenericRFI_BODY`をBlockではなくCountで運用する | ニュース検索・銘柄検索の引数に正当なURLが含まれうるため。Blockにすると正常系コーパス(A25-04)が遮断される | 未承認(検証段階の暫定) | 本番適用前に再判断 | 2026-09-14 |
| WAF-15 | `AWSManagedRulesCommonRuleSet`の`SizeRestrictions_BODY`(8KB超)をCountで運用し、遮断はカスタムルール`body-over-64kb`が担う | 日本語の長文引数(UTF-8で3バイト/文字)が8KBを容易に超えるため。正常系コーパス(A25-07、12KB相当)が遮断される | 未承認(検証段階の暫定) | 本番適用前に再判断 | 2026-09-14 |
| WAF-19 | `AWSManagedRulesAnonymousIpList`の`HostingProviderIPList`を恒久的にCountで運用する | Claude.ai等の正規MCPクライアントはクラウド(Anthropic egress `160.79.104.0/21`)から発信するため、Blockにすると正規利用を遮断する | 未承認(検証段階の暫定) | 恒久(方針として維持) | 2026-09-14 |
| WAF-12 | JSON文字列値内のBase64 Javaシリアライズ列を遮断しない | `AWSManagedRulesKnownBadInputsRuleSet`が検知しないことを実測。カスタムルールの費用対効果を未評価 | 未承認(リスク受容の可否は要判断) | 本番適用前に判断 | 2026-09-14 |

---

## 5. 再評価のトリガーと手順

| トリガー | 再評価範囲 |
|---|---|
| `terraform/`・`terraform-playground-pattern4/`のWAF・API Gateway・Lambda・Cognito関連ファイルの変更 | 変更に関係する領域(WAFまたはDCR)の全行 |
| 月次 | WAF §2.2・§2.3(Count結果レビューを含む) |
| 四半期 | 全行 |
| MCPプロトコル新版リリース | DCR §3.5、WAF-16(プロトコルバージョン許可リスト) |
| Anthropicコネクタ仕様の変更 | DCR §3.7 |

手順: (1)`scripts/waf_attack_tests.py --report`と`scripts/dcr_conformance_tests.py --report`を実行し`docs/evidence/YYYY-MM-DD-*.json`を保存、(2)結果を本表の状態・最終実施・証跡列に転記、(3)不合格・例外を[00-handoff.md](./00-handoff.md)に転記。

---

## 6. 変更履歴

| 日付 | 変更 |
|---|---|
| 2026-09-10 | 初版作成。全行を未着手または要確認で登録。WAF-10・WAF-11のみ18番の実機結果(ALB一時アタッチ)を転記 |
| 2026-09-14 | CloudFront + WAFのBlockモード検証を反映([2026-09-14-waf-cloudfront-block.json](./evidence/2026-09-14-waf-cloudfront-block.json)、[2026-09-14-waf-ratelimit.json](./evidence/2026-09-14-waf-ratelimit.json))。新発見: JSON文字列値内のBase64 Javaシリアライズ列がKnownBadInputsで検知されない(WAF-12)。CloudFrontはURIトラバーサルとTRACEをWAF評価前に拒否する |
| 2026-09-13 | DCR最小スコープ修正後の再検証([2026-09-13-dcr-postfix.json](./evidence/2026-09-13-dcr-postfix.json)、[2026-09-13-dcr-mcp04.json](./evidence/2026-09-13-dcr-mcp04.json)、[2026-09-13-dcr-authz.json](./evidence/2026-09-13-dcr-authz.json))を反映。合格33・不合格2 |
| 2026-09-13 | DCR基準線([2026-09-13-dcr-baseline.json](./evidence/2026-09-13-dcr-baseline.json))とWAF基準線([2026-09-13-waf-baseline.json](./evidence/2026-09-13-waf-baseline.json))を`scripts/update_checklist.py`で反映。新発見: フラグメント付きredirect_uri・101件redirect_uris・client_credentials+noneでCognitoの400が500化(7591-06、7591-09)、`response_types: [token]`受理(7591-05)、JSON-RPCバッチ50件を200で全処理(WAF-16、A15) |

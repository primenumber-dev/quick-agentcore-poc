# セッション引き継ぎメモ(2026-09-16時点)

> **この章で分かること**
> 前回セッションで何をどこまでやったか、次に何をすべきか、そして再開する上で最初につまずきそうな点(PATH、SSOトークン、サンドボックス制限)を先回りしてまとめる。次回セッションはまずこのファイルを読んでから作業を再開すること。
>
> **最新の状況(2026-09-16時点)は末尾の「20. docs命名のinternal/external化と納品ヒアリング準備」を先に読むこと。** それより前の記述は過去時点の状態を含む(誤りではないが、一部は後続セクションで更新・訂正されている)。特に §18.4 の納品ブロッカー一覧は §19.2 で3件を訂正しており、以降は [docs/fde/DELIVERY-BLOCKERS.md](./fde/DELIVERY-BLOCKERS.md) を正とする。**さらに、§19以前の本文中に残る`docs/NN-xxx.md`形式のリンクの一部は§20のリネームで`internal-`/`external-`が挿入されている(リンク自体は追随済みで切れていないが、ファイル名の見た目が変わっている点に注意)。**

## 1. 状況サマリー

来週水曜のクライアント報告に向けて、quick-mcp-poc MCPサーバーを (3) AgentCore Runtime単体、(4) API Gateway + ECS(既存構成) の2パターンでホストし、比較検証している。

**追加スコープ(2026-08-17に合意)**: このサービスは単発PoCではなく、**金融機関向けに課金制で外販するリモートMCPサービス**として展開する狙いがある。そのため通常のエンタープライズ向けリモートMCPより難易度が高く、マルチテナント分離・ネットワーク閉域性(PrivateLink)・監査ログ・コンプライアンス認定(FISC安全対策基準等)を重点的に比較検証する追加タスクを実施した → [05-internal-security-compliance-verification.md](./05-internal-security-compliance-verification.md)

**現時点で完了しているもの**(すべて`docs/`配下に成果物あり):

- [x] パターン3(AgentCore Runtime)のデプロイ・疎通検証 → [03-internal-agentcore-runtime-verification.md](./03-internal-agentcore-runtime-verification.md)
- [x] パターン4(API Gateway + ECS)の稼働確認(既存本番相当環境、新規デプロイ不要だった) → [04-internal-ecs-apigateway-verification.md](./04-internal-ecs-apigateway-verification.md)
- [x] 両パターンの構成図(AWS公式アイコン)・Mermaidシーケンス図・プロコン比較 → [01-internal-architecture-comparison.md](./01-internal-architecture-comparison.md)
- [x] コストシミュレーション(月額試算・損益分岐点) → [02-internal-cost-simulation.md](./02-internal-cost-simulation.md)
- [x] 金融グレード外販サービスとしてのセキュリティ・コンプライアンス比較検証(マルチテナント分離・閉域網・監査ログ・コンプライアンス認定・FISC対応) → [05-internal-security-compliance-verification.md](./05-internal-security-compliance-verification.md)。机上調査中心+一部実機確認(playgroundのRuntime設定スキーマ、terraformコードレビュー)で実施。**重要な発見: 現状構成はAgentCore・ECSどちらもPrivateLink/VPCエンドポイント未対応であり「閉域網」を訴求するには追加実装が必要**。ユーザーの指示により、この検証は現状判明している範囲で完了とし、実機でのPrivateLink疎通検証等は次回以降のフォローアップ扱い
  - 「字ばかりで頭に入らない、オライリー本のように図表を多用してほしい」とのフィードバックを受け、TL;DR、AWS構成図2種(`docs/images/pattern3-vpc-privatelink-target.png`, `docs/images/pattern4-vpc-endpoint-target.png`、いずれも未検証の構想図)、Mermaid図(テナント分離フロー、コンプライアンスgantt、パッチ責任分界点、FISC構造)を追加する全面改訂を実施
  - その後「絵文字禁止・出典に本文中インラインリンクを・査読と修正はサブエージェント分離で」というフィードバックを受け、**査読専用エージェント(Explore、編集不可)→修正専用エージェント(general-purpose)の2段階構成**で対応。査読エージェントは1回目mermaid-cliインストールで600秒スタックし失敗、制約を明確化して再実行し成功。発見した問題: `subgraph AgentCore Runtime`のクォート漏れ(Mermaid構文エラーで図が描画不能)、エッジラベル内`\n`(Mermaid非対応)、ganttのtitle行のコロン(パース破損リスク)、quadrantChartのGitHub描画崩れ懸念、絵文字36箇所以上、本文中の出典インラインリンク不足17箇所。修正エージェントが全て適用し、絵文字ゼロ・subgraph修正・quadrantChart削除・出典リンク追加を確認済み(自分でも`grep`と全文読み直しで再確認済み)
  - **学び**: サブエージェントにMermaid検証をさせる際は「一時ファイル作成もダメ」と厳格に指示すると`mmdc`インストールで無限に粘って失敗することがある。「$TMPDIRへの一時ファイル作成は可、対象ファイルの編集のみ禁止」のように制約を具体的に切り分けると成功する

**未着手・今後の課題**(ユーザーへの確認が必要な場合あり):

- [ ] パターン1・2(AgentCore Gateway経由)の検証 — 今回スコープ外として合意済み。着手するかはユーザー確認が必要
- [x] **パターン3のレイテンシ実測(コールドスタートの影響)**(2026-08-21実施)。詳細は[03-internal-agentcore-runtime-verification.md](./03-internal-agentcore-runtime-verification.md)。**意外な発見: アイドル0秒〜16分(セッションタイムアウト超過後)まで一貫して約6秒で、コールドスタートによる有意な差は観測できなかった**。約6秒はAWS側のコンテナ起動待ちではなく、MCPサーバー実装がリクエストごとに新しいセッションを生成する設計による可能性が高い(推測、コード側の詳細プロファイリングは未実施)
- [ ] パターン3のスケーラビリティ実測(同時リクエスト負荷試験)
- [x] パターン3の本番グレード認証(Custom JWT Authorizer導入)の検証 → 下記の通り完了
- [x] **Claude Code経由でのOAuthリモートMCP接続検証**(2026-08-18実施)。ECS+API Gatewayとの詳細比較・構成図・シーケンス図・認証フロー差分・接続手順・6つのハマりどころを整理した独立ドキュメント → [06-internal-agentcore-oauth-claude-code-verification.md](./06-internal-agentcore-oauth-claude-code-verification.md)。作業ログの詳細は本ファイル末尾「9. Claude.ai連携のためのCustom JWT Authorizer設定」を参照
- [x] **Claude.ai Web版での疎通確認**(2026-08-20、ユーザーが実機で確認済み)。Runtime version 6での`allowedScopes`追加(§9末尾の追記参照)が功を奏した。Claude Desktopでの疎通はまだ未確認
- [x] **クライアント(QUICK様)向けレポートの作成・査読・PDF化**(2026-08-19〜20実施)。詳細は本ファイル「10. クライアント向けレポートの作成とPDF化」を参照 → [06-external-agentcore-oauth-claude-code-verification.md](./06-external-agentcore-oauth-claude-code-verification.md) / 同PDF
- [x] **汎用MCPクライアント(boto3/Claude Code/Claude.aiに非依存)からの疎通検証**(2026-08-21実施)。詳細は[03-internal-agentcore-runtime-verification.md](./03-internal-agentcore-runtime-verification.md)。Cognito認可コード+PKCEフローのみで`invocations`エンドポイントを直接HTTPS呼び出しし、MCPプロトコル層・JWT認証・DynamoDB認可チェックまで正常動作することを確認
- [x] **コスト再検討(実測レイテンシを踏まえた見直し)**(2026-08-21実施)→ [02-internal-cost-simulation.md](./02-internal-cost-simulation.md)。壁時計レイテンシ(約6秒)とAgentCore課金対象の「アクティブCPU時間」は別物である旨を明記し、既存の保守的な試算(1リクエスト=1秒)は変更せず維持。正確な値はAWS Cost Explorerでの実測を推奨。VPCモード(閉域網対応)にする場合のECR Interfaceエンドポイント追加コストも明記
- [x] **WAF導入可否の実機検証**(2026-08-21実施)→ [05-internal-security-compliance-verification.md §4.5](./05-internal-security-compliance-verification.md)。AgentCore Runtime自体への直接アタッチは不可だが、CloudFront+WAFv2の代替構成をplaygroundに実機構築し、正常リクエストの通過・悪意あるパターンの403ブロックの両方を確認
- [x] **本日の検証内容をまとめたレポート作成**(2026-08-21実施、06番と同フォーマット)→ エンジニア向け[07-internal-vpc-waf-cost-verification.md](./07-internal-vpc-waf-cost-verification.md) / クライアント向け[07-external-vpc-waf-cost-verification.md](./07-external-vpc-waf-cost-verification.md)。査読専用エージェント(Explore、編集不可)→修正専用エージェント(general-purpose)の2段階レビューで、Mermaid構文(`\n`→`<br/>`未変換、`<JWT>`のHTMLタグ誤認識リスク)、太字の乱用、表記ゆれ(壁時計レイテンシ/Interfaceエンドポイント)、クライアント向け版の文体不統一(敬体/常体混在)・「実機」という不自然な表現を修正済み
- [x] **追加検証5項目の実施**(2026-08-25実施): (1)疎通検証Webアプリ(Lambda Function URL、`quick-mcp-poc-web-demo`)、(2)ECS+API Gatewayをplaygroundに複製し応答時間を実測(約0.2〜0.3秒、AgentCore Runtimeの約6秒より約20倍速い)→**本番相当terraformのJWT Authorizer`audience`設定に、正当なトークンでも常に401になる不具合を発見・修正案を実機確認**(要本番共有、最優先課題)、(3)VPCモードのTerraformコード例(`docs/terraform-examples/agentcore-vpc-mode/main.tf`)、(4)VPCモード+WAF込みの1ヶ月コスト試算(損益分岐点が約610万→約77万リクエスト/月に低下)、(5)DCR移行の手順・コスト試算。両レポートの文章も「クライアント担当者(kekekenta氏)から」等の人物名を削除し「問いに対する検証」という位置づけに統一
- [x] **AWSインフラ図の追加**(awsdac、2026-08-25実施): `docs/images/agentcore-vpc-mode-verified.png`(VPCモード実機構成)、`docs/images/agentcore-waf-cloudfront.png`(WAF/CloudFront構成)、`docs/images/agentcore-webdemo-architecture.png`(疎通検証Webアプリ構成)を新規作成し両レポートに埋め込み。既存の`pattern4-architecture.png`もECS比較セクションで再利用
- [x] **PDF化パイプラインをリポジトリに永続化**([scripts/render-pdf.sh](../scripts/render-pdf.sh))。前回セッションではscratchpad依存で消えていたが、今回`npm install mermaid`のESMバンドル(`mermaid.esm.min.mjs`)をfile://経由でChromeに読み込ませる方式で再構築し、スクリプト化した。**注意点**: Chromeで`file://`オリジンからESモジュールをimportするには`--allow-file-access-from-files`フラグが必須(無いとCORSエラーで失敗する、無言でmermaidが生テキスト表示になるだけで気づきにくい)。クライアント向け版のPDFを[docs/07-external-vpc-waf-cost-verification.pdf](./07-external-vpc-waf-cost-verification.pdf)として保存済み(pdftoppmで複数ページを目視確認済み)
- [x] **検証リソースへのリンク集を両レポートに追加**。エンジニア向けはAWSコンソールの深リンク一式、クライアント向けは疎通検証Webアプリの公開URLのみ(クライアントはplaygroundアカウントにログインできないため)
- [x] **「次週の検証アクションプラン」章を両レポートの最後に追加**(本番audienceバグの共有を最優先、PrivateLink実機検証・WAF運用体制・コスト実測・DCR判断が続く)

### 追加調査(2026-08-26実施)

- [x] **`client_credentials`グラント(人手を介さないM2M接続)の実機検証**。新規Cognito App Client(`quick-mcp-poc-m2m-test`、client_id: `7gtknlcn9imrhihetq3aauojaj`、confidential、`allowed_oauth_flows=client_credentials`、scope=`mcp/invoke`)を作成し、Runtimeの`allowedClients`に追加(version 9)。**認可レイヤー(Custom JWT Authorizer)は問題なく通過するが、アプリ層(DynamoDB認可チェック)は`sub`=クライアントID自体に対応するレコードが無いため403になる**ことを確認。DynamoDBに`USER#7gtknlcn9imrhihetq3aauojaj`のレコードを追加(サービスアカウント扱い)したところ解消し、正常動作を確認済み。本番展開時はこの「サービスアカウント登録」運用が必要になる
- [x] **6秒の内訳を実機で特定**。CloudWatch Logs(`/aws/bedrock-agentcore/runtimes/quickMcpPocVerification-Aoo0d23yyj-DEFAULT`)を調査し、**リクエストごとに新しいコンテナが起動している**ことを確認(1ストリーム=1回の起動ログのみ)。ストリーム作成〜起動完了ログまでの間隔は約30サンプルで3.78〜4.07秒(平均約3.9秒)と非常に安定。6秒のうち約65%はこのコンテナ起動コストと推定([07-internal-vpc-waf-cost-verification.md §2.2.1](./07-internal-vpc-waf-cost-verification.md)参照)
- [x] **VPCモード切り替え後、CloudWatch Logsへのログ配信が完全停止していることを発見**(2026-08-21 08:37の切り替え以降、新規ログストリームが0件)。`com.amazonaws.<region>.logs`のVPCエンドポイントを作成していないためと推定。**未対応**、次のフォローアップ課題
- [x] **AWS Cost Explorerでの実コスト確認を試みたが、playgroundアカウント全体(他の検証者のAgentCoreエージェント含む)の合算しか取得できず、本Runtime単体を分離できないと判明**。代わりにCloudWatchメトリクス(`AWS/Bedrock-AgentCore`名前空間、dimensionに`Resource=<RuntimeのARN>`を指定)で本Runtime単体の`CPUUsed-vCPUHours`/`MemoryUsed-GBHours`/`Invocations`/`Duration`が取得できることを確認。ただし2026-08-17〜26の期間で総呼び出し回数が**6,414回**(想定より大幅に多い。Claude Code等のMCPクライアントによるバックグラウンドの定期接続が疑われるが未確定)、Duration最大値が130.6秒という外れ値もあり、**この実測値は今回レポートには反映せず**、契約情報として保留(ユーザー判断)。単価自体(vCPU $0.0895/時間、メモリ$0.00945/時間)は確定値と一致することを確認済み
- [x] `docs/02-internal-cost-simulation.md`に「内訳の算出根拠(サービス別)」を追加。既存試算が「0.25vCPU/0.5GBを1秒間」という仮定(Fargateと同サイズ)に基づくことを逆算で確認し、サービスごとの単価根拠を明記
- [x] **AgentCore RuntimeのVPCモード切り替えの実機検証**(2026-08-21実施)。詳細は[05-internal-security-compliance-verification.md §4.1.1](./05-internal-security-compliance-verification.md)。**インバウンド(`invocations`エンドポイント)への影響なし、アウトバウンド(DynamoDB Gateway経由のVPC内リソースアクセス)は正常動作**を確認。クライアント(kekekenta氏)からの「AgentCore RuntimeはVPCに配置できないのでは」という質問への回答の裏付けが取れた
- [ ] `com.amazonaws.<region>.bedrock-agentcore`のPrivateLinkインターフェースエンドポイント経由でのインバウンド呼び出し自体の実機検証(VPC内部からの完全閉域アクセス。上記で作成済みのVPCを使って次に実施可能)
- [ ] `InvokeAgentRuntime`(データプレーン)がCloudTrailデータイベントとして記録されるかの実機確認
- [ ] ログの改ざん防止・長期保存(S3 Object Lock等)の実装検証
- [ ] FISC安全対策基準(現行第14版)の正確な条文番号の裏取り(基準書は有償頒布のため、AWSの「AWS FISC安全対策基準対応リファレンス」最新版取得を推奨。今回は第9版ベースの資料までしか参照できていない)
- [ ] git commit(下記「6. Gitの状態」参照。現状コミットは一切していない)

## 2. プロジェクトの場所

```
~/projects/quick-agentcore-poc/
```

ダウンロードフォルダのZIP(`quick-mcp-poc-main 2-....zip`)から展開したTypeScript製MCPサーバー一式。`git init`済みだが**コミットは未実施**(全ファイルが`git add`でステージされたまま)。

## 3. 使用しているAWSアカウント(重要)

2つのAWSアカウントを使い分けている。混同しないこと。

| プロファイル名 | アカウントID | アカウント名 | 権限 | 用途 |
|---|---|---|---|---|
| `quick-agentcore-poc` | 620369151795 | professional_services_quick_poc | AWSPowerUserAccess(**IAM作成不可**) | パターン4(既存本番相当環境)が稼働中。**実クライアントデータ(Cognito/DynamoDB に41ユーザー)を含むため、書き込みは一切禁止** |
| `quick-agentcore-poc-playground` | 883660531246 | systemN_playground | AWSAdministratorAccess | パターン3(AgentCore Runtime)の検証用に今回新規構築。個人サンドボックスなので自由に操作してよい |

**SSOトークンは数時間で失効する。** 再開時にコマンドが`Token has expired`で失敗したら:
```bash
aws sso login --profile quick-agentcore-poc              # 本番相当アカウント用
aws sso login --profile quick-agentcore-poc-playground    # 検証用アカウント
```

## 4. playgroundアカウントに作成済みのAWSリソース

ユーザーの指示で**削除せず残してある**(2026-08-17時点)。

| リソース | 識別子 |
|---|---|
| IAM実行ロール | `arn:aws:iam::883660531246:role/quick-mcp-poc-agentcore-execution-role` |
| ECRリポジトリ | `883660531246.dkr.ecr.ap-northeast-1.amazonaws.com/quick-mcp-poc-agentcore-verification:verification-1` |
| DynamoDBテーブル | `quick-mcp-poc-users`(テストユーザー1件: `USER#agentcore-verification-user`) |
| AgentCore Runtime | `arn:aws:bedrock-agentcore:ap-northeast-1:883660531246:runtime/quickMcpPocVerification-Aoo0d23yyj`(version 10、`networkMode: VPC`、ステータス: READY。2026-08-31に`requestHeaderAllowlist`からの`x-cognito-sub`除去でversion 10に更新、[08番§1](./08-internal-weekly-verification-plan.md)参照) |
| 検証用VPC | `quick-mcp-poc-verification-vpc`(`vpc-0df861e536fad4aab`, `10.99.0.0/24`)。2026-08-21、VPCモード検証のために新規作成。private subnet ×2(`subnet-0c56f317a1a50a6f4`, `subnet-004618218ccfed812`)、SG(`sg-04798ee8dda54dfc3`、自己参照443許可)、route table(`rtb-05c946adb3e34e90b`) |
| VPCエンドポイント | S3 Gateway・DynamoDB Gateway・ECR API Interface・ECR DKR Interface(いずれも上記VPCに作成。詳細は[05-internal-security-compliance-verification.md §4.1.1](./05-internal-security-compliance-verification.md)参照) |
| WAF検証用CloudFront + WAFv2 | Distribution `E3IBSB361TGZEQ`(`d22imwd0soxmb2.cloudfront.net`、オリジン=`bedrock-agentcore.ap-northeast-1.amazonaws.com`)+ Web ACL `quick-mcp-poc-verification-webacl`(us-east-1、`AWSManagedRulesCommonRuleSet`)。2026-08-21、WAF代替構成検証のために新規作成。詳細は05番ドキュメント参照 |

**2026-08-21、ユーザー判断により、上記VPC/CloudFront/WAF検証リソースは削除せず残置(PrivateLink実機検証等の次のフォローアップで再利用する方針)。Runtimeも`networkMode: VPC`(version 8、後述の疎通検証Webアプリ用client_id追加で8に更新)のまま維持することとした**(PUBLICへの切り戻しは行わない)。時間課金が発生するリソース(ECR Interfaceエンドポイント×2、CloudFront、WAFv2)が稼働し続けている点は認識しておくこと。

### 追加リソース(2026-08-25実施、追加検証)

| リソース | 識別子 |
|---|---|
| 疎通検証Webアプリ(Lambda) | 関数名`quick-mcp-poc-web-demo`、Function URL(AuthType NONE、ユーザー承認済み): `https://ldqokcn33yxb2lspfudhahj2we0pgfqa.lambda-url.ap-northeast-1.on.aws/`。実行ロール`quick-mcp-poc-web-demo-lambda-role` |
| Webアプリ用Cognito App Client | `quick-mcp-poc-web-demo`(client_id: `54cjhrb2bmba52upo8tfem4jlq`、public/PKCE専用)。AgentCore Runtimeの`allowedClients`に追加済み |
| ECS+API Gateway playground複製一式 | `terraform-playground-pattern4/`(本番相当`terraform/`とは別state・別ディレクトリ、production backendには一切触れていない)。VPC(`vpc-04703dc42d1f7fef8`)、ECSクラスター`quick-mcp-poc-cluster`、API Gateway `https://2a5r57wfoa.execute-api.ap-northeast-1.amazonaws.com`、Cognito User Pool `ap-northeast-1_XrU8FcC1w`(ドメイン`quick-mcp-poc-pattern4-verify`)、DynamoDBテーブル`quick-mcp-poc-pattern4-verify-users`(未使用、後述の理由で実際はAgentCore検証と共用の`quick-mcp-poc-users`テーブルを参照) |
| ECS用テストユーザー | Cognito: `pattern4-verify-user@example.com`(このために新規作成したプール内、実クライアントデータとは無関係)。DynamoDB `quick-mcp-poc-users`テーブルにレコード追加済み(`services.quick.plan=standard`) |

### 追加リソース(2026-08-31実施、DCR実装)

| リソース | 識別子 |
|---|---|
| DCR Register Lambda | `quick-mcp-poc-dcr-register`(`terraform-playground-pattern4/lambda.tf`) |
| DCR Authorizer Lambda | `quick-mcp-poc-dcr-authorizer`(同上)。`terraform-playground-pattern4`のJWT型Authorizerを置き換え済み |
| `POST /register`ルート | `https://2a5r57wfoa.execute-api.ap-northeast-1.amazonaws.com/register` |

詳細は[10-internal-dcr-implementation.md](./10-internal-dcr-implementation.md)参照。**注意**: この変更により`terraform-playground-pattern4`の認可方式はJWT型AuthorizerからLambda Authorizerに変わっている。次回セッションでこの環境を触る際は、`aws_apigatewayv2_authorizer.cognito`はもう存在しない前提で作業すること。

**重要な発見**: playground複製環境で実機検証したところ、本番相当`terraform/apigateway.tf`のJWT Authorizer`audience`設定(`aws_cognito_resource_server.mcp.identifier`を指定)は、Cognitoが実際に発行するトークンの`aud`/`client_id`(App Client ID)と一致せず、**正当な認証済みトークンでも常に401になる**ことが判明した。`audience`を`aws_cognito_user_pool_client.mcp.id`に変更したところ解消した。本番環境自体は書き込み禁止のため未確認だが、同一ロジックのため本番でも同様の可能性が高い。詳細は[07-internal-vpc-waf-cost-verification.md §2.4](./07-internal-vpc-waf-cost-verification.md)参照。**本番担当者への早期共有を推奨**。

**後片付けについて**: 上記のplayground複製一式(ECS/ALB/NAT×2/API Gateway/Cognito/DynamoDB/KMS等、59リソース)は継続的に時間課金が発生する(ECS Fargate常時起動、ALB、NATインスタンス×2等で月額約$46相当、02-cost-simulation.md参照)。**2026-08-25、ユーザー判断により「しばらく残す」こととした**(追加の確認・再検証に使う可能性があるため)。削除する場合は`cd terraform-playground-pattern4 && aws ecs delete-service --cluster quick-mcp-poc-cluster --service app --force --profile quick-agentcore-poc-playground --region ap-northeast-1 && terraform destroy`の順で実施すること。

IAMポリシーの元ファイルは `docs/agentcore-iam/*.json` に保存済み。本番アカウント(620369151795)への適用時は、アカウントIDとECRリポジトリ名を置換する必要がある(詳細は各JSONファイル、および[01-internal-architecture-comparison.md](./01-internal-architecture-comparison.md)参照)。

疎通確認スクリプト:
- `scripts/invoke_agentcore_mcp.py` / `scripts/invoke_agentcore_no_auth.py`: boto3+SigV4(IAM認証)方式。**Runtimeが現在Custom JWT Authorizer方式のため使用不可**(参考用に残置)
- `scripts/invoke_agentcore_mcp_jwt.py`(2026-08-21新規作成): Cognitoの認可コード+PKCEフローでBearerトークンを取得し、boto3を使わず素のHTTPSで`invocations`エンドポイントを呼ぶ汎用MCPクライアント。使い方は同スクリプトのdocstring参照。実行には環境変数`MCP_TEST_PASSWORD`(テストユーザー`quick-mcp-poc-verify`のパスワード。2026-08-21にユーザー許可のもと`admin-set-user-password`で再設定済み、値はこのファイルには記録しない)が必要

## 5. ローカル環境の状態

- **Homebrew, AWS CLI, Docker Desktop, Node.js, pnpm, Python 3.12, awsdac** はすべてインストール済み(グローバル環境)。シェルで`brew`/`aws`等が`command not found`になる場合は、新しいシェルでPATHが通っていないだけなので `eval "$(/opt/homebrew/bin/brew shellenv)"` を実行すること。
- **LocalStack(Docker)が起動したままの可能性がある**(`quick-agentcore-poc-localstack-1`、DynamoDBローカルスタブ用)。不要なら `docker compose -f ~/projects/quick-agentcore-poc/compose.yml down` で停止してよい。
- **GitHub CLI(`gh`)は未認証**。必要になったら `gh auth login`(対話操作が必要)。
- `awsdac`はClaude CodeにMCPサーバーとして登録済み(`claude mcp add awsdac ...`)。**このセッションでは反映されなかった**(MCP登録は次回セッション起動時から有効)。今回はCLI(`awsdac <file>.yaml -o <file>.png -f`)で直接生成した。

## 6. Gitの状態

`git init`は実行済みだが、**一度もコミットしていない**。`git status`で全ファイルが`A`(ステージ済み)または`??`(未追跡: `docs/`, `server/pnpm-workspace.yaml`)になっている。コミットするかはユーザーの明示的な指示を待つこと(このセッションでは指示が無かったため未実施)。

## 7. アプリコードへの変更点(元のZIPからの差分)

- `server/src/index.ts`: `PORT`のデフォルト値を`3000`→`8000`に変更(AgentCore Runtime要件対応。他のロジック変更なし)
- `server/Dockerfile`: `ENV PORT`と`EXPOSE`を`8000`に変更
- `server/pnpm-workspace.yaml`: 新規追加。`allowBuilds: { esbuild: true }`(非対話環境でesbuildのビルドスクリプト承認を通すため)

## 8. サンドボックス関連の注意

このツール環境のBashサンドボックスは`~/.aws/`へのアクセスをブロックする。AWS CLI・Docker・pnpm installなど、認証情報やグローバル環境に触れるコマンドは`dangerouslyDisableSandbox: true`が必要になることが多い(ユーザーには事前承認を得た上で使用してきた)。

## 9. Claude.ai連携のためのCustom JWT Authorizer設定(2026-08-18実施)

### 背景

これまでの疎通検証(03番ドキュメント)はboto3 + SigV4署名 + `x-cognito-sub`自己申告ヘッダーという簡易構成だった。「Claude.aiのWeb版からMCPツールとして直接疎通したい」という要望を受け、AgentCore RuntimeをCustom JWT Authorizer方式に切り替えた。

### 調査で判明した重要事実

- AgentCore Runtimeの`authorizerConfiguration.customJWTAuthorizer`を設定すると、SigV4署名不要で**`Authorization: Bearer <JWT>`ヘッダーのみの生HTTPS呼び出し**が可能になる。エンドポイントは`https://bedrock-agentcore.{region}.amazonaws.com/runtimes/{URLエンコードされたARN}/invocations?qualifier=DEFAULT`
- 未認証リクエストには**RFC9728準拠のOAuth Protected Resource Metadata**を`WWW-Authenticate`ヘッダー経由で自動的に返す(`.../invocations/.well-known/oauth-protected-resource`)。実機で200 OK・正しいJSON返却を確認済み
- IAM(SigV4)とJWTは同一Runtimeで排他。今回IAM設定からJWT設定に切り替えたため、**boto3スクリプト(`scripts/invoke_agentcore_*.py`)は今後使えなくなった**
- Cognitoは**Dynamic Client Registration(RFC7591)非対応**。Claude.aiは代替として「Advanced settings」でOAuth Client ID/Secretを手動入力する機能を持つ(公式ヘルプで確認済み: [Get started with custom connectors using remote MCP](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp))
- アプリコード(`server/src/index.ts`の`extractSub()`)は既に「`x-cognito-sub`ヘッダーが無ければ`Authorization`のJWTペイロードから`sub`を直接デコードする」フォールバックを実装済みだったため、**コード変更は一切不要**だった

### 実施した変更

playgroundアカウント(883660531246)に**既存の**Cognitoリソースを発見し、ユーザー確認の上で再利用した(quick-mcp-poc開始前の別セッションで構築されたものと思われる):

| リソース | 識別子 |
|---|---|
| Cognito User Pool | `agentcore-mcp-pool` (`ap-northeast-1_WSvFtGhlV`) |
| Cognito Domain | `agentcore-mcp-883660531246` |
| App Client | `claude-web` (`f9b41piv9irn56d49d16i9shc`)。コールバックURLに`https://claude.ai/api/mcp/auth_callback`・`https://claude.com/api/mcp/auth_callback`を含む。**Client Secretあり**(confidential client) |
| Resource Server | `mcp`(スコープ`invoke`) |

実施した変更:
1. `update-agent-runtime`でRuntime(`quickMcpPocVerification-Aoo0d23yyj`)をversion 2に更新。`authorizerConfiguration.customJWTAuthorizer.discoveryUrl`を`https://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_WSvFtGhlV/.well-known/openid-configuration`、`allowedClients`を`["f9b41piv9irn56d49d16i9shc"]`に設定
2. DynamoDBテーブル`quick-mcp-poc-users`に、Cognitoの既存ユーザー`tester`(sub: `37a44a68-f0d1-7002-4327-ee469975112e`)と、新規作成したテストユーザー`quick-mcp-poc-verify`(sub: `4774eac8-20b1-709b-5547-ff2637be17d6`、パスワードは新規設定・permanent)のレコードを追加(`services.quick.plan = standard`)

### 検証結果 → **最終的にエンドツーエンドで疎通成功(2026-08-18)**

Claude.ai Web版へのカスタムコネクタ追加はOrganizationがTeam/Enterpriseプランのため権限上できなかった(Ownerのみ追加可能)ので、**Claude Codeの`claude mcp add`(ローカルのMCP設定、claude.aiのConnectors管理とは別系統)経由で検証**した。最終的に`✔ connected · 6 tools`で疎通に成功した。

#### 最終的に機能した設定(Runtime version 5)

```bash
aws bedrock-agentcore-control update-agent-runtime \
  --agent-runtime-id quickMcpPocVerification-Aoo0d23yyj \
  --agent-runtime-artifact '{"containerConfiguration":{"containerUri":"883660531246.dkr.ecr.ap-northeast-1.amazonaws.com/quick-mcp-poc-agentcore-verification:verification-1"}}' \
  --role-arn arn:aws:iam::883660531246:role/quick-mcp-poc-agentcore-execution-role \
  --network-configuration '{"networkMode":"PUBLIC"}' \
  --protocol-configuration '{"serverProtocol":"MCP"}' \
  --request-header-configuration '{"requestHeaderAllowlist":["x-cognito-sub","Authorization"]}' \
  --authorizer-configuration '{"customJWTAuthorizer":{"discoveryUrl":"https://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_WSvFtGhlV/.well-known/openid-configuration","allowedClients":["f9b41piv9irn56d49d16i9shc"]}}' \
  --profile quick-agentcore-poc-playground --region ap-northeast-1
```

**ポイント**: `allowedAudience`は**設定しないこと**(下記参照)。`requestHeaderAllowlist`に**`Authorization`を含めること**(必須)。

Claude Code側の`~/.claude.json`のMCPサーバー設定(該当プロジェクトの`mcpServers.quick-mcp-poc-agentcore`):
```json
{
  "type": "http",
  "url": "https://bedrock-agentcore.ap-northeast-1.amazonaws.com/runtimes/arn%3Aaws%3Abedrock-agentcore%3Aap-northeast-1%3A883660531246%3Aruntime%2FquickMcpPocVerification-Aoo0d23yyj/invocations?qualifier=DEFAULT",
  "oauth": {
    "clientId": "f9b41piv9irn56d49d16i9shc",
    "callbackPort": 3030,
    "authServerMetadataUrl": "https://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_WSvFtGhlV/.well-known/openid-configuration",
    "scopes": "openid mcp/invoke"
  }
}
```
(Client Secretはこのファイルには入らず、macOSキーチェーンに保存される。`claude mcp add --client-secret`で対話入力)

#### ハマった6つの問題(すべて解決済み)

疎通までに独立した6つの問題を1つずつ切り分けて解決した。今後同じ構成を再現する際の参考に記録する。

| # | 問題 | レイヤー | 原因と対応 |
|---|---|---|---|
| 1 | 長い1行コマンドがターミナルへのコピペ時に途中で改行され実行が壊れる(`zsh: no matches found`等) | ローカル環境 | チャットのコードブロックの折り返し表示がコピー時に改行として混入。対応: 変数に分けて短い行に分割してから最後にまとめる |
| 2 | `claude mcp add $OPTS ...`で`error: unknown option`(OPTS文字列全体が1引数扱い) | シェル(zsh) | zshは未クォートの変数展開でも単語分割しない(bashと異なる)。対応: 配列`OPTS=(...)` + `"${OPTS[@]}"`を使う |
| 3 | ブラウザが`https://bedrock-agentcore.../authorize`という誤ったホストにリダイレクトされ「Invalid api path」 | Claude CodeのOAuth自動検出 | CognitoがRFC8414の`/.well-known/oauth-authorization-server`を提供せず(`openid-configuration`のみ)、Claude Codeの自動検出がリソースサーバー自身をフォールバック先にしてしまった。対応: `~/.claude.json`の`oauth.authServerMetadataUrl`にCognitoのdiscovery URLを明示指定 |
| 4 | Cognitoログイン画面で`invalid_request: invalid_scope` | Cognito | `authServerMetadataUrl`設定後、Claude CodeがCognito discoveryの`scopes_supported`(`openid, email, phone, profile`)を丸ごとリクエストしたが、実際のApp Client(`claude-web`)は`openid`と`mcp/invoke`しか許可していなかった。対応: `~/.claude.json`の`oauth.scopes`に`"openid mcp/invoke"`を明示指定 |
| 5 | 認証後の再接続時にAgentCoreが401(`Claim 'aud' value mismatch with configuration`) | AgentCore Custom JWT Authorizer | 良かれと思って追加した`authorizerConfiguration.allowedAudience`が原因。**Cognitoのアクセストークンは`aud`クレームを持たない仕様**(`client_id`クレームのみ)のため、`allowedAudience`を設定すると必ず不一致でリジェクトされる。対応: `allowedAudience`を削除し`allowedClients`のみにする |
| 6 | AgentCoreの認可自体は通る(200)が、コンテナ内アプリが401(`Missing user identity`)を返す(JSON-RPCエラー`-32010`として包まれる) | AgentCore Runtime → コンテナ間のヘッダー転送 | 認可済みの`Authorization`ヘッダーは、`requestHeaderConfiguration.requestHeaderAllowlist`に明示的に含めない限りコンテナに転送されない仕様。対応: allowlistに`Authorization`を追加 |

**特に5・6はAgentCore Custom JWT AuthorizerとCognitoの組み合わせ特有の、ドキュメントに明記されていない挙動**であり、本番展開時にも同じ罠に注意が必要(05番ドキュメントに追記推奨)。原因の切り分けには、Cognitoの認可コード+PKCEフローをPythonでプログラム的に再現し(ブラウザ操作なしで)、AgentCoreの生レスポンスを直接確認する手法が有効だった(`docs`配下にスクリプト化はしていないが、手順はこのセッションの会話ログに残っている)。

#### playgroundに新規追加したリソース

- DynamoDBテーブル`quick-mcp-poc-users`に、Cognitoの既存ユーザー`tester`(sub: `37a44a68-f0d1-7002-4327-ee469975112e`)と新規作成テストユーザー`quick-mcp-poc-verify`(sub: `4774eac8-20b1-709b-5547-ff2637be17d6`)のレコードを追加(`services.quick.plan = standard`)
- Cognitoに新規ユーザー`quick-mcp-poc-verify`を作成(permanent password設定済み)

#### 未解決の課題(優先度低)

- [ ] Cognito `InitiateAuth`(USER_PASSWORD_AUTH直接ログイン、非ブラウザ)で`UserNotFoundException`が出る原因は依然未特定。ただし実際に使うブラウザ/Claude Code経由のOAuthコードフローは正常動作するため実害なし
- [ ] IAM/SigV4方式に戻したい場合は`update-agent-runtime`で`authorizer-configuration`を外せばよい(が、その場合Claude.ai/Codeからの直接接続は不可に戻る)

### 追記(2026-08-18・同日): Claude.ai Web版/Claude Desktopで疎通できないとの報告 → 原因仮説と対策(Runtime version 6)

ユーザーが別の担当者にClaude.ai Web版・Claude Desktopからの接続を試してもらったところ、Runtime version 5の状態では**疎通できなかった**との報告があった。Claude Codeでは疎通済みだったため、原因はサーフェス間の違いにあると推測し、Anthropic公式ドキュメント[Authentication for connectors](https://claude.com/docs/connectors/building/authentication)を調査した。

**分かったこと**:
- Claude.ai Web/Desktop/mobile/CowworkはAnthropicの**クラウド側**でOAuthフローを実行し、コールバックURLは固定の`https://claude.ai/api/mcp/auth_callback`。Claude Codeのようにローカルの`~/.claude.json`で`oauth.scopes`や`oauth.authServerMetadataUrl`を手動上書きする手段がWeb/Desktopには**存在しない**
- 公式ドキュメント曰く「401レスポンスの`WWW-Authenticate`ヘッダーに`scope`パラメータが無い場合、Claudeはprotected resource metadataの`scopes_supported`を要求する」。今回のRuntimeは`scope`を明示しておらず、Claude Codeで発生した`invalid_scope`(Cognitoのdiscoveryが返す`openid, email, phone, profile`を丸ごと要求してしまう問題)が、**手動回避策を持たないWeb/Desktopでも再現している可能性が高い**と判断

**実施した対策**: `authorizerConfiguration.customJWTAuthorizer`に`allowedScopes: ["openid", "mcp/invoke"]`を追加(`update-agent-runtime`、Runtime version 6)。実機で`WWW-Authenticate`ヘッダーに`scope="openid mcp/invoke"`が明示的に付与されるようになったことを確認済み。これはAnthropic公式ドキュメントが明記する「Claudeがリクエストするスコープを制御する方法」そのもの。

**現在の最終設定(version 6)**:
```
authorizer-configuration: customJWTAuthorizer.discoveryUrl + allowedClients + allowedScopes(["openid","mcp/invoke"])
```
(`allowedAudience`は含めない、`requestHeaderAllowlist`に`Authorization`を含める、という既存のポイントは変更なし)

詳細な仮説・根拠・切り分け手順は[06-internal-agentcore-oauth-claude-code-verification.md § 7](./06-internal-agentcore-oauth-claude-code-verification.md)に記載。

**次にやるべきこと**(2026-08-20時点で更新):
- [x] ~~Web/Desktopのテスターに、version 6の状態で再度接続を試してもらう~~ → **2026-08-20、Claude.ai Web版での疎通をユーザーが確認済み**。version 6の`allowedScopes`追加が仮説通り原因であったことが裏付けられた(詳細な再現手順・エラー文言の記録は今回は取得していない。必要であれば次回テスターに改めて確認)
- [ ] Claude Desktopでの疎通確認(Web版は確認済みだが、Desktop版は未確認のまま)
- [ ] それでも将来的に別の失敗が出る場合は、06ドキュメント§7.3の副次仮説(OAuthディスカバリーのホスト解決バグ)を調査する

## 10. クライアント向けレポートの作成とPDF化(2026-08-19〜20実施)

### 背景

06番ドキュメント(`06-internal-agentcore-oauth-claude-code-verification.md`)はエンジニア向け(再現・引き継ぎ用)に書かれていたため、QUICK様への説明に使うにはそのままでは不適切という判断から、読者をクライアントに絞った別版を作成する指示を受けた。

### 実施内容

1. **クライアント向け版を新規作成**: `docs/06-external-agentcore-oauth-claude-code-verification.md`。エンジニア向けの元ファイルは引き継ぎ・再現用としてそのまま残し、上書きはしていない。用語解説(MCP/OAuth/JWT/Cognito/スコープ等)を追加し、「ハマった6つの問題」のような内輪向けの言い回しを対外報告らしい表現に調整。`docs/README.md`のドキュメント一覧には**まだ追記していない**(次回セッションでの対応候補)。
2. **PDF化パイプライン**: pandoc(`-f gfm -t html5 --standalone`)→ Python後処理(mermaidブロックの`<code>`タグ除去、画像相対パスを`file://`絶対パスに変換、`mermaid.initialize`スクリプト注入)→ ヘッドレスChrome(`--headless=new --print-to-pdf`)、という既存パイプラインを流用。**このパイプラインの中間ファイル(`header.html`・後処理スクリプト)はセッション専用のスクラッチパッド(`/private/tmp/claude-501/.../scratchpad/pdf/`)に置いており、次回セッションでは消えている。** 再現する場合は本セクションの記述を元に組み直すこと(pandocコマンド・後処理内容は上記の通り。ヘッダー用CSSは日本語フォント指定+テーブル/コードブロックの見た目調整のみで特別な工夫はない)。
3. **クライアントから「AI生成だとバレる」との指摘**: 1回目のPDFで、`**「実際にAIクライアントから安全に接続できるか」**`のように太字記号がそのまま文字として表示される箇所があった。原因はCommonMarkの仕様で、`**`の直後/直前が全角カッコ「」などの記号だと太字として解釈されない(flanking rule)ため。この指摘を受けて査読・修正プロセスをサブエージェント化して実施:
   - **査読専用サブエージェント**(編集不可、`general-purpose`)に全文を読ませ、同種の太字崩れが他に3箇所残っていること、mermaid図の丸数字(④⑤⑥⑦)と本文表の番号(1〜4)の不一致、"実機"という浮いた専門用語(サーバーレス構成なのに"実機"は不自然)、用語の表記ゆれ(検証専用の環境/インスタンス/プール/認証基盤が混在)、太字の乱用(25箇所、平均10行に1回)などを洗い出させた
   - **修正専用サブエージェント**(別プロセス、`general-purpose`)に、指摘ごとの具体的な直し方(削除/言い換え/統一する用語)を指示して反映させた
   - 自分でも実際にpandoc変換したHTMLを正規表現でスキャンし、「太字が`<strong>`化されず`**`のまま残っていないか」を全数チェック(0件)。mermaidブロック内の崩れやすい記号(`<...>`のような角カッコ)も再スキャンし問題なしを確認
4. PDF再生成、1ページ目を画像で目視確認して完了 → `docs/06-external-agentcore-oauth-claude-code-verification.pdf`(13ページ)

### 学び(次回以降のPDF作成・査読作業に活用)

- **査読(read-only)と修正(edit可)は必ず別々のサブエージェントに分離する**。1つのエージェントに両方させると、指摘の見落としを自分でごまかしてしまうリスクがある。これは05番ドキュメントの査読でも踏襲した方針(本ファイル1章の学び参照)で、今回も有効だった
- CommonMarkの太字は、日本語の全角カッコ・句読点が`**`の内側に隣接すると崩れることがある。**査読の際は「太字構文自体が存在するか」ではなく「実際にpandoc等でレンダリングした結果に`**`が残っていないか」を機械的に検証するのが最も確実**(サブエージェントの目視レビューだけに頼らない)
- ヘッドレスChromeでの`--print-to-pdf`はこのサンドボックス環境だと素の状態では失敗する(`Failed to create socket directory`等、crashpadのソケット作成権限エラー)。`--user-data-dir`に書き込み可能な独自ディレクトリ(スクラッチパッド配下)を指定し、かつ`dangerouslyDisableSandbox: true`が必要だった。スクリーンショット系のコマンド(`--screenshot`)は同条件でもタイムアウトしやすく、PDF生成自体は成功していても`--screenshot`での目視検証は諦めることが多かった → 検証は「1ページ目をqlmanageでサムネイル化」+「pandoc出力HTMLの機械的スキャン」の組み合わせで代替するのが実用的
- PDF生成コマンドが2分のタイムアウトで打ち切られたように見えても、実際にはファイルが正常に書き出されていることがある(Chromeプロセスの終了処理が長引くだけ)。`ls -la`で生成物のタイムスタンプ・サイズを確認してから再実行の要否を判断すること

### 未着手・次回への申し送り

- [x] `docs/README.md`のドキュメント一覧・読み方フローチャートに、クライアント向け版(`06-external-agentcore-oauth-claude-code-verification.md`)への言及を追加する(2026-08-21実施。あわせて新規作成した07番ドキュメント一式も追記)
- [ ] **【次回最優先】今週の追加検証3点(2026-08-31合意、詳細は「12. 今週の追加検証計画」参照)**: (1) DCR実装(選択肢B、カスタムDCR/CIMDプロキシを実際に構築)、(2) 応答時間の深掘り・チューニング(まず「セッションID使い回しで起動コストを回避できないか」という未検証の仮説から試す)、(3) インタラクティブなコストシミュレーター(Artifact)の作成。**スコープ合意のみで実作業は未着手**
- [ ] クライアント向けPDFは1ページ目のみ目視確認済み。全ページ(特にmermaid図のページ)の見た目は未確認のため、ユーザー側での最終確認を待っている状態
- [ ] PDF化パイプラインをスクラッチパッド任せにせず、リポジトリ内(例: `scripts/render-pdf.sh`等)に永続化しておくと、次回以降のPDF再生成が楽になる(今回はユーザーから明示的な指示が無かったため未実施)

## 11. DCR(Dynamic Client Registration)/CIMD机上調査(2026-08-21実施)

### 背景

クライアント担当者(kekekenta氏)から「VPC・ALB・NATインスタンス・API Gatewayが新方式では不要になる。逆にAgentCore RuntimeはVPCに配置できないのでは?」という質問を受けたのを機に、今週の検証タスクの1つとして「DCRを用いた構成での検証」を計画。まず机上調査のみ実施(ユーザー確認済みのスコープ)。

**VPC配置に関する回答**: 前半(4要素不要)は正しい。後半(VPCに配置できない)は不正確で、AgentCore Runtimeは`networkConfiguration.networkMode: VPC`でVPC内にENI配置可能。ただし本PoCでは`PUBLIC`モードのみ検証済みで、VPCモードの実機疎通は今週の検証タスク(項目3)として別途実施予定。

### DCR/CIMD調査で判明した重要事実(Anthropic公式ドキュメント[Authentication for connectors](https://claude.com/docs/connectors/building/authentication) [Lazy authentication](https://claude.com/docs/connectors/building/lazy-authentication)より)

- Claudeは認可サーバーがDCR(`registration_endpoint`を公開)を持たない場合、3つの代替を提示している: (1) `registration_endpoint`を実装する、(2) CIMD(`client_id_metadata_document_supported: true`かつ`token_endpoint_auth_methods_supported`に`"none"`を含む)に対応する、(3) `oauth_anthropic_creds`(Anthropicに事前登録済みのclient_id/secretを預ける方式)に切り替える
- **CIMDは技術的にCognitoでは実現不可能に近い**: CIMDは`client_id`自体がURLで、認可サーバー(`/authorize`エンドポイント)がそのURLを都度フェッチしてクライアントメタデータ(self-referential検証、redirect_uris検証)を検証する必要がある。これはCognitoのマネージド`/oauth2/authorize`では実装できないカスタムロジックであり、対応するには**Cognitoの手前(または代わり)にカスタムOAuth Authorization Serverを新規構築する**必要がある。これはDCR用プロキシを作るのとほぼ同等の工数
- **`oauth_anthropic_creds`が最も工数が低い代替案**: これは「事前に発行済みのclient_id/secretをAnthropicに預け、Anthropicがユーザーの同意後にトークン交換を代行する」方式。**Cognito側の変更は一切不要**(既存の`claude-web` App Client のclient_id/secretをそのまま`mcp-review@anthropic.com`宛に送るだけで済む可能性がある)。ただし、これは「Directory connector」(Anthropicの公開ディレクトリに掲載され、複数組織が共通のOAuthアプリ経由で接続する形態)向けの仕組み
- **現状の運用(Claude.aiのAdvanced settingsでClient ID/Secretを手動入力)は、実は正式にサポートされた「Custom connector」の標準フローそのものだった**: 公式ドキュメントに「管理者が独自のOAuth Client credentialsを接続時に入力できる。これはDCRを完全に回避でき、その組織専用にスコープされた安定したOAuthクライアントを持てる良い方法」と明記されている。つまり**「回避策」ではなく正式な仕様どおりの運用**であり、単一〜少数の金融機関向けにそれぞれ個別コネクタとして提供する分には、追加のDCR/CIMD対応は不要という結論になる

### 結論・ユーザーへの提示内容

DCR/CIMD対応が必要になるかどうかは、**外販サービスの提供形態**に依存する:

| 提供形態 | 対応方針 |
|---|---|
| 金融機関ごとに個別コネクタとして提供(各社の管理者がClient ID/Secretを個別入力) | **現状のCognito構成のままで対応済み**(公式のCustom connectorフロー)。追加実装不要 |
| Anthropicの公開ディレクトリに掲載し、複数組織が共通導線でセルフサービス追加できるようにする | `oauth_anthropic_creds`(既存Cognito client_id/secretをAnthropicに登録するだけ、コード変更不要)が最有力。真のDCR/CIMD実装(カスタムAuthorization Server新規構築)は工数に対して正当化しにくい |

**次のアクション(ユーザー判断済み、2026-08-21)**: 今週のDCRタスクはこの机上調査で完了とする。実際のDCR対応アーキテクチャの実装検証は、今週の他タスク(簡易アプリ接続テスト・コールドスタート測定・VPC内配置検証・コスト比較・WAF検証)がすべて完了した後、**新規ブランチを切って**着手する。現状リポジトリはコミット0件のため、ブランチを切るには先に初回コミットが必要になる(§6参照、コミットはユーザー明示指示待ちのまま)。

## 12. 今週の追加検証計画(2026-08-31合意、**未着手**)

> このセクションはスコープ合意のみで終わったセッションの記録。次回セッションはここから着手する。

**追記(2026-08-31・同日、プランニング実施)**: 本セクションで合意した3項目について、実装前の設計・見積もり検証を実施した。結論を[08-internal-weekly-verification-plan.md](./08-internal-weekly-verification-plan.md)にまとめた。要点:

- **【重大・確認済み・修正済み】クロステナントなりすまし脆弱性を発見し即日修正(2026-08-31)**: AgentCore Runtimeの`requestHeaderConfiguration.requestHeaderAllowlist`に`x-cognito-sub`が含まれており、クライアントが送った値がそのままコンテナに転送されていた(ECS経路のような`overwrite:`保護がAgentCore経路には無かった)。実際に、正当なJWTを持ちながら`x-cognito-sub`ヘッダーで他テナントのsubを騙り、そのテナントとして認可される(成功レスポンスを得る)ことを実機で確認した。**対応**: `requestHeaderAllowlist`を`["Authorization"]`のみに変更(Runtime version 9→10、`update-agent-runtime`のみでコード変更・再デプロイ不要)。修正後、同じ手法でのなりすましが失敗する(Bearerトークンの`sub`に正しくフォールバックする)ことを再検証済み。詳細な経緯・図解は[09-internal-cross-tenant-impersonation-finding.md](./09-internal-cross-tenant-impersonation-finding.md)、要約は[08-internal-weekly-verification-plan.md §1](./08-internal-weekly-verification-plan.md)
- **12.1 DCR実装の見積もり改訂**: 3-5人日→**7-9人日**。現在のJWT Authorizerは`audience`に固定値しか設定できず、DCRで動的に増えるclient_idに対応するには**Lambda Authorizerへの置き換えが必須**と判明(当初見積もりに未反映)。ユーザー確認の上、この見積もりを受け入れて選択肢Bを継続する方針(詳細は08番§2)
- **12.2 応答時間チューニングのスコープ変更**: AWS公式ドキュメントにより、ステートレスMCPサーバーのままでも`Mcp-Session-Id`によるmicroVMスティッキーロイティングが機能することが判明。**サーバーのステートフル化(大改修)は不要**で、検証スクリプト(`scripts/invoke_agentcore_mcp_jwt.py`)がこのヘッダーを再送していないことが既存の実測結果の説明として十分。大改修(Phase 2)は今回のスコープから外し、Phase 0(スクリプト修正+計測ログ)のみ実施する方針(詳細は08番§3)。あわせて、既存の「AgentCoreはECSの約20倍遅い」という比較([07-internal-vpc-waf-cost-verification.md §2.4](./07-internal-vpc-waf-cost-verification.md))が非対称な計測だった可能性を記録
- **12.3 コストシミュレーター**: **実装・公開済み(2026-08-31)**。既存の`02-internal-cost-simulation.md`の数値を逆算する過程で、ALB LCU・CloudFront平均レスポンスサイズという2つの未記載パラメータ、DynamoDB/Logsコストの非対称計上、損益分岐点の簡略化式という3点を新規発見。インタラクティブなArtifactとして実装し、既存ドキュメントの14個の掲載数値を許容誤差$0.5以内で再現することを確認済み(詳細は08番§4.5)
- **12.1 DCR実装(2026-08-31実施)**: タスク1〜6(Lambda Authorizer実装・Register Lambda実装・discoveryメタデータ・乱用対策の一部・CLI管理コマンド)を`terraform-playground-pattern4`に実装し、実機で(a)既存静的クライアントの回帰確認、(b)DCR新規登録→client_credentialsでのMCP呼び出し成功、(c)DynamoDB失効フラグによる即時アクセス遮断、の3点を確認済み。詳細・詰まりどころは[10-internal-dcr-implementation.md](./10-internal-dcr-implementation.md)。残タスク: Claude Code/Claude.aiからの実際の自己登録によるE2E確認(Cognito Managed Login UI v2がブラウザ操作前提のため簡易スクリプトでは代替できず)、セキュリティレビュー、本番相当`terraform/`への移植(書き込み禁止のためapply自体はユーザー判断)
- 12.2(応答時間チューニングPhase 0、約3人日)は**未着手**。次回セッションは08番ドキュメントの「§5 実施順序」の残タスクから着手する

ユーザーから今週の検証項目として次の3点が提示され、スコープを確認した。**実際の作業は未着手**(SSOトークン確認の直後にセッションを次回に持ち越すことになったため)。

### 12.1 DCR(動的クライアント登録)の実装

- スコープ: **選択肢B(カスタムDCR/CIMDプロキシを実際に構築)を採用**。§11.2で比較した「選択肢A: `oauth_anthropic_creds`申請」ではなく、Cognitoの手前に立つ独自のOAuth Authorization Server(DCR `/register`エンドポイント、または CIMD の `client_id` URL検証ロジック)を実際に実装する方針
- 前提条件: §11末尾の通り、**新規ブランチを切るには先に初回git commitが必要**(現状コミット0件)。次回セッション開始時、まずこの初回コミットの実施可否をユーザーに確認すること
- 参考: §11.2のコスト試算では選択肢Bは「DCRのみなら3〜5人日、CIMD対応まで含めると1〜2週間」と見積もっていた。実装にあたってはこの見積りとのズレも記録すること

### 12.2 応答時間の深掘り検証・チューニング

- 背景: [07-internal-vpc-waf-cost-verification.md §2.4](./07-internal-vpc-waf-cost-verification.md)で、ECS+API Gateway(約0.2〜0.3秒)がAgentCore Runtime(約6秒)より約20倍速いという結果が出ており、ユーザーは「現状ECSの方が有利に見えるので、AgentCore Runtime側をチューニングまたはアーキテクチャ最適化して同等以上の速度を目指せないか」を検証したいとのこと
- スコープ確認済み: **アプリコード(`server/src/*`)を変更し、再デプロイしながら検証してよい**(ユーザー承認済み)
- **次回最初に試すべき、最も安価な仮説(未検証)**: §2.4の実測で判明した「リクエストごとに新しいコンテナが起動し、起動に約3.9秒かかる」という現象について、AgentCore Runtimeのレスポンスヘッダーに`mcp-session-id`・`x-amzn-bedrock-agentcore-runtime-session-id`というセッションIDが含まれていることを2026-08-21のCloudFront経由テストで確認済み(未活用のまま)。**同一セッションID を2回目以降のリクエストで使い回すと、コンテナが再利用され約3.9秒の起動コストを回避できるのではないか、という仮説がある**。これはアプリコード変更なしで検証でき(クライアント側でセッションIDヘッダーを送るだけ)、成立すれば「アーキテクチャ最適化でECSと同等以上の速度を実現する」という目標に直結する、最優先で試すべき仮説
- その他の検証候補: サーバー実装(`server/src/index.ts`)の`sessionIdGenerator: undefined`(ステートレスStreamable HTTP)設定を、実際のセッションID発行に変更した場合の挙動変化。Node.js起動時間の削減(依存関係の遅延ロード等)
- 前提: [07-internal-vpc-waf-cost-verification.md §3.2の詰まった点4](./07-internal-vpc-waf-cost-verification.md)で判明した「VPCモードにするとCloudWatch Logsへのログ配信が止まる」問題が未解決のため、**タイミング計測ログを仕込んでも現在はログが見えない**。チューニング検証を始める前に、`com.amazonaws.<region>.logs`のVPCエンドポイントを追加するか、一時的に`networkMode: PUBLIC`に戻すかの判断が必要
- playground用ECRイメージの再ビルド・pushの手順は[07-internal-vpc-waf-cost-verification.md §2.4](./07-internal-vpc-waf-cost-verification.md)や本ファイル§4のterraform-playground-pattern4の手順を参考にできる

### 12.3 コストシミュレーターの作成

- 背景: [02-internal-cost-simulation.md](./02-internal-cost-simulation.md)に「内訳の算出根拠(サービス別)」の表を追加済みだが、ユーザーからは「現在の約$50〜60ではよく分からないので、コストモデルを整理しながらシミュレーターを作ってほしい」との要望
- スコープ確認済み: **インタラクティブなWebページ形式**(トラフィック量・VPCモード有無・WAF有無等をスライダー/チェックボックスで調整でき、サービス別内訳と合計がリアルタイムに表示される)。Artifactとして公開する想定
- 材料は揃っている: [02-internal-cost-simulation.md](./02-internal-cost-simulation.md)の単価表(vCPU $0.0895/時間、メモリ$0.00945/時間、Fargate/ALB/NAT/APIGW単価、VPCエンドポイント$0.014/時間/AZ、WAFv2 $5/月+$1/ルール等)をそのままロジックに落とし込める
- 実装時の注意: Artifactを書く前に`artifact-design`スキルを読み込むこと(このセッションでは未実施)

### 進め方の推奨(次回セッション向け)

1. まずSSOログイン状態を確認(このセッションでは失効していた)
2. 12.2の「セッションID使い回し仮説」はコード変更不要で最も安く検証できるため最初に試す
3. 12.3のコストシミュレーターはAWSアクセス不要で並行して進められる
4. 12.1のDCR実装は初回git commitの合意が前提になるため、着手前にユーザーに確認する

---

## 13. セッション完了サマリー(2026-09-02〜09-03実施)

> このセクションが本ファイルの最新状態。§12までの記述と矛盾する場合はこちらを優先すること。

### 13.1 リポジトリのGitHub化(今セッション最初に実施)

- 初回git commit・GitHub push を完了。**`https://github.com/primenumber-dev/quick-agentcore-poc`(private)**
- コミット署名(SSH署名)必須のリポジトリルールがあり、`~/.ssh/id_ed25519_signing`鍵を新規作成してGitHubにSigning Keyとして登録済み。ローカルのgit設定(`gpg.format=ssh`, `commit.gpgsign=true`, `user.signingkey`)は`.git/config`に反映済み(リポジトリ固有設定、他リポジトリには影響しない)
- commit時の`user.email`は`mamoru_1992@outlook.jp`(GitHub検証済みメール)。`mamoru.ishino@primenumber.co.jp`ではないので注意
- `node_modules`・`.terraform`・`tfstate`が誤ってコミットされていないことを確認済み。秘密情報のスキャンも実施し問題なし

### 13.2 §12の今週の検証3項目の実施結果

| 項目 | 状態 |
|---|---|
| DCR実装(選択肢B) | **完了**(タスク1〜6+セキュリティレビュー)。`terraform-playground-pattern4`に実装、実機確認済み。詳細は[10-internal-dcr-implementation.md](./10-internal-dcr-implementation.md) |
| コストシミュレーター | **完了**。[Artifact公開済み](https://claude.ai/code/artifact/8f9d8cfc-aec8-4eb2-8970-6e3e1947f8c3)、既存資料の14数値を再現することを検証済み |
| 応答時間チューニング(Phase 0) | **未着手**。次回セッション最優先。手順は[08-internal-weekly-verification-plan.md §3](./08-internal-weekly-verification-plan.md)に整理済み。あわせて§3.5・[13-internal-weekly-verification-report.md §7.4](./13-internal-weekly-verification-report.md)に「コンテナ起動オーバーヘッド自体を縮められるかもしれない」という追加候補(ウォームプール検証・コードデプロイモード比較)も次回検証項目として記録済み |

### 13.3 スコープ外で見つかった重大な追加成果

- **【最重要・修正済み】x-cognito-subヘッダーによるクロステナントなりすまし脆弱性**: AgentCore Runtime経路で発見・実機確認・即日修正(設定変更のみ、コード変更不要)。詳細は[09-internal-cross-tenant-impersonation-finding.md](./09-internal-cross-tenant-impersonation-finding.md)。**AgentCore Runtimeは現在version 10**(修正反映済み)
- **DCR実装後のセキュリティレビュー**: 4件の候補中3件を確定・修正(無審査アクセス付与、スコープ未検証、失効の最大5分遅延)。1件は誤検知として除外。詳細は[10-internal-dcr-implementation.md §4.5](./10-internal-dcr-implementation.md)
- **Cognito→Auth0移行の机上見積もり**: [11-internal-cognito-to-auth0-migration-estimate.md](./11-internal-cognito-to-auth0-migration-estimate.md)。技術的に成立しそうだが月額$800〜の新規コストとデータレジデンシー懸念あり
- **【次回最優先で試すべき、Auth0移行よりはるかに安い代替仮説(未検証)】**: AgentCore Runtimeの`allowedClients`を外し`allowedScopes`のみで運用すれば、Cognitoのままpattern3でもDCRが成立する可能性がある。また、pattern4もAPI Gateway REST API(v1)のネイティブ`COGNITO_USER_POOLS`オーソライザー(client ID指定が任意)に置き換えれば、自作Lambda Authorizerが不要になる可能性がある。詳細は[10-internal-dcr-implementation.md §0.5](./10-internal-dcr-implementation.md)、[08-internal-weekly-verification-plan.md §2.9](./08-internal-weekly-verification-plan.md)
- **MCPプロトコルv2(2026-07-28)移行の影響調査**: [12-internal-mcp-protocol-v2-upgrade-impact.md](./12-internal-mcp-protocol-v2-upgrade-impact.md)。**重要な訂正**: 当初「v2 SDKは現状ベータ版」と誤って結論づけたが、追加確認で**v2は仕様と同時に2026-07-28に既にGA済み**と判明し訂正済み。「GAを待つ」という判断根拠は無くなっている
- **Step1仕様確認シートへの回答**: [14-internal-step1-spec-confirmation-answers.md](./14-internal-step1-spec-confirmation-answers.md)。特にx-cognito-subヘッダーに関する質問は、上記の脆弱性発見と直結する内容だった
- **今週の統合レポート**: [13-internal-weekly-verification-report.md](./13-internal-weekly-verification-report.md)(PDF化済み: `docs/13-internal-weekly-verification-report.pdf`)。既存の06/07番と同フォーマット(TL;DR・AWS構成図・Mermaidシーケンス図・図の解説・出典)で、この週の全内容を1本のレポートに統合

### 13.4 PDF化パイプラインの重要な修正(次回以降に影響)

`scripts/render-pdf.sh`に、**複数のMermaid図を含む文書でSVGが誤った位置に重なって描画される既知のバグ**を発見・修正した。

- 原因: Mermaidの一括処理API(`mermaid.run()`)が、1ページに複数の図が並ぶ文書で、図同士の描画位置を取り違えることがある
- 対応: `mermaid.render(id, definition)`を図ごとに明示的なユニークIDで個別呼び出しし、結果を該当のプレースホルダー要素にだけ差し込む方式に変更済み(スクリプトは修正済み、今後生成するPDFはこの修正が自動的に反映される)
- 図が2〜3個程度の文書では発生しにくく、[13-internal-weekly-verification-report.md](./13-internal-weekly-verification-report.md)のように図が10個を超えるあたりから顕在化した。**今後、複数図を含む長いレポートをPDF化する際は、生成後に必ず全ページを目視確認すること**(`pdftoppm`で1ページずつPNG化して確認する手順が確立済み)

### 13.5 現在のAWSリソース状態(playgroundアカウント、883660531246)

§4の記載から以下が更新されている。

| リソース | 状態 |
|---|---|
| AgentCore Runtime(`quickMcpPocVerification-Aoo0d23yyj`) | **version 10**(§13.3のセキュリティ修正反映済み、`requestHeaderAllowlist`は`["Authorization"]`のみ) |
| `terraform-playground-pattern4` | DCR実装(Lambda Authorizer + DCR Register Lambda)を追加。JWT型AuthorizerからLambda型に切替済み。認可結果のキャッシュTTLは0秒に短縮済み。既存の静的クライアント(`quick-mcp-poc-mcp-client`)は`invoke`スコープも許可済み |
| `lambda/`(新規ディレクトリ) | DCR用の2 Lambda(`authorizer.ts`, `register.ts`)のソース一式。ビルド成果物(`dist/`)は`.gitignore`対象 |

テスト用に作成したDCRクライアント・DynamoDBレコードはすべて検証後にクリーンアップ済み(playground環境を汚していない)。

### 13.6 次回セッションの優先順位(推奨)

1. **AWS SSOログイン状態を確認**(`quick-agentcore-poc-playground`プロファイル。本セッションでも複数回失効した)
2. **§13.3の「Auth0移行より安い代替仮説」を先に検証**(`allowedScopes`単独運用、REST API Gatewayネイティブオーソライザー)。Auth0移行の意思決定はこの結果を見てから行う
3. 応答時間チューニングPhase 0(セッションID使い回し検証)に着手。CloudWatch LogsのVPCエンドポイント追加が前提
4. DCRのタスク7(Claude Code/Claude.aiからの実際の自己登録E2E確認)は、Cognito Managed Login UI v2のブラウザ操作制約が壁になっている。回避策の検討が必要
5. 本番相当`terraform/`へのDCR実装の移植は、書き込み禁止のためapply自体はユーザー判断待ち

### 13.7 学び(次回以降に活かすべき点)

- **`terraform apply -target`で多数の新規リソースを部分適用する際は、IAMポリシー・ポリシーアタッチメントまで含めて対象を列挙すること**。Terraformの依存関係は「参照」からしか自動導出されないため、Lambda関数本体だけを`-target`に含めても、アタッチされた権限ポリシーは別リソースとして扱われ、対象から漏れやすい(今回2段階で同じミスを踏んだ)
- **Authorizerの結果キャッシュ(`authorizer_result_ttl_in_seconds`)がある場合、修正の検証は必ず新しいトークン・新しい認可対象で行うこと**。同じトークンでの再試行はキャッシュの影響を切り分けられず誤診断につながる
- **セキュリティ関連のなりすまし検証では、「成功する」ことより「失敗するはずのケースが失敗すること」を確認する方が確実**。今回の`x-cognito-sub`検証も、DCRの失効検証も、この「否定的なテスト」のアプローチで確証を得た
- **PDF化で複数のMermaid図を扱う場合、`mermaid.run()`の一括処理に頼らず、図ごとに明示的なIDで`mermaid.render()`すること**(§13.4参照)
- **AWS公式ドキュメントの「ベータ版」情報は鵜呑みにせず、日付が新しい一次情報(仕様サイト・GitHubリリースページ)で裏を取ること**。MCPプロトコルv2のGA時期を一度誤って報告した(§13.3参照)
- **セキュリティレビューやコストの数字は、ユーザーの要望に応じて「言い回し」を調整してよいが、事実(何を発見し、何を直したか)は変えないこと**。今回「クロステナントなりすまし」という表現を「x-cognito-subヘッダー処理の修正」に和らげたが、技術的内容自体は変更していない

## 14. セッション完了サマリー(2026-09-03実施)

> このセクションが本ファイルの最新状態。§13までの記述と矛盾する場合はこちらを優先すること。

### 14.1 今週の検証4項目の実施結果

ユーザーから提示された4項目すべてに着手し、完了した。

| 項目 | 状態 |
|---|---|
| MCPプロトコルv2への載せ替え検証 | **完了(スパイクとして)**。`feature/mcp-protocol-v2-spike`ブランチで実装、LocalStackで動作確認済み。**mainには未マージ**(意図的にスパイク止まりの方針)。詳細は[12-internal-mcp-protocol-v2-upgrade-impact.md §7](./12-internal-mcp-protocol-v2-upgrade-impact.md) |
| ECS(WAF・DCR)本番化検証・課題整理 | **完了**。既存`terraform-playground-pattern4`でのDCRデモ実演に加え、[10-internal-dcr-implementation.md §0.5](./10-internal-dcr-implementation.md)で未検証だった2つの仮説(AgentCore Runtime`allowedScopes`単独運用、ECS側REST APIネイティブ`COGNITO_USER_POOLS`オーソライザー)を実機で初検証し、いずれも成立を確認。WAFのSQLi未対応も新規発見。詳細は[15-internal-ecs-production-readiness-gaps.md](./15-internal-ecs-production-readiness-gaps.md) |
| 応答時間チューニング(6秒問題) | **完了(Phase 0)**。セッションID再利用で約10倍高速化(6秒→0.5〜0.6秒)することを実機確認したが、効果の持続時間は30秒〜5分の間で失われることも判明(設定上の`idleRuntimeSessionTimeout`15分より短い) |
| 今週の検証レポート作成 | **完了**。社内向け[16-internal-weekly-verification-report-week3.md](./16-internal-weekly-verification-report-week3.md)・クライアント向け[16-external-weekly-verification-report-week3.md](./16-external-weekly-verification-report-week3.md)(PDF化済み)を作成 |

### 14.2 本番相当terraformのaudienceバグ修正パッチ

[07-internal-vpc-waf-cost-verification.md §2.4](./07-internal-vpc-waf-cost-verification.md)で発見済みだった本番`terraform/apigateway.tf`の`audience`バグ(正当なトークンでも401になる)について、`fix/production-audience-config-proposal`ブランチとして修正パッチを用意した(`terraform validate`まで確認、本番へは未適用)。**次回セッション最優先で本番担当者への共有を推奨**。

### 14.3 Gitブランチの状態(重要、mainには何もマージされていない)

今回のセッションで作成した3つのブランチは、いずれも**mainにマージ・GitHubへのpushはしていない**(ユーザーへの確認なしに実施することを避けた)。次回セッション、またはユーザー自身の判断でマージ/push/PRを検討すること。

| ブランチ | 内容 | 状態 |
|---|---|---|
| `feature/mcp-protocol-v2-spike` | MCPプロトコルv2への書き換え一式(`server/`)、`docs/12`§7への実機検証結果追記 | スパイクとして完結。mainへの反映は要判断 |
| `fix/production-audience-config-proposal` | `terraform/apigateway.tf`の`audience`バグ修正(1行) | レビュー待ちの提案。本番担当者の確認後、mainへのマージ・本番適用を検討 |
| `latency-tuning/session-id-reuse` | `LOG_TIMING`計装(`server/src/index.ts`, `db.ts`)、`scripts/invoke_agentcore_mcp_jwt.py`拡張、`docs/12`§7の復元(cherry-pick)、`docs/15`・`docs/16`(+client版・PDF) | 現在のHEAD。LOG_TIMING計装は既存挙動に影響しない(環境変数ガード付き)ため、mainへのマージは比較的低リスク |

### 14.4 今回新規作成したAWSリソース(playgroundアカウント、883660531246)

| リソース | 識別子 | 状態 |
|---|---|---|
| CloudWatch Logs VPCエンドポイント | `vpce-046556344264018d0`(`com.amazonaws.ap-northeast-1.logs`、検証用VPC`vpc-0df861e536fad4aab`に追加) | 稼働中、継続課金(月額約$20)。VPCモード切替後にログ配信が止まっていた問題への対処 |
| 応答時間検証専用Runtime | `quickMcpPocLatencyLab-uC4Wd7EOWj`(`LOG_TIMING=1`、既存デモ用Runtimeとは完全に分離) | 稼働中(READY)。次回のコンテナ保持時間の境界特定(30秒〜5分の間)等の追加検証にそのまま再利用可能 |

検証専用に一時作成したリソース(`quickMcpPocDcrScopeTest` Runtime、DCR仮説検証用Cognitoクライアント複数、スタンドアロンREST API、DCRデモ用クライアント)はすべて検証後に削除済み。playgroundアカウントを汚していない。

### 14.5 学び(次回以降に活かすべき点)

- **`git checkout <branch>`でブランチを切り替えると、Dockerイメージのビルドに使う`node_modules`(pnpm install済みの依存関係)は自動的に追従しない**。v1系SDKブランチとv2系SDKブランチを行き来する際、`pnpm install`をブランチ切り替えのたびに実行し直す必要があった(型チェックエラーの原因を数分探ってようやく気づいた)
- **1つのAWSアカウントを複数の検証で共有する場合、`list-agent-runtimes`等で既存リソースを確認し、自分のプロジェクトと無関係なリソース(今回は`trocco`・`mcplatency_latencymcp`等、他プロジェクトのものと判明)に触れないよう名前でスコープを判別すること**。特に紛らわしい名前(`mcplatency_latencymcp`)のリソースは、作成日時やECRリポジトリ名・IAMロール名を確認して他人のものと判断した
- **AWS SSOトークンの失効は、ユーザーに別ターミナルでの`aws sso login`実行を依頼する以外に解決策が無い**(ブラウザ認証が必要なため)。ログイン待ちの間もAWS非依存の作業(コードのスパイク実装、ローカル検証、terraformの`validate`)を並行して進めることで手待ちを減らせた
- **`dangerouslyDisableSandbox`を使う際は`$TMPDIR`の値がサンドボックス有無で変わる**ことに注意。サンドボックス無効化コマンドで書いたファイルを、サンドボックス有効なコマンドの`$TMPDIR`から参照しようとすると`No such file or directory`になる(このセッションで複数回踏んだ)。同一コマンドブロック内で完結させるか、常に同じサンドボックス設定を使うことで回避できる
- **AWS CLIの複数行出力を`read A B C`で複数変数に読み込む際、値が複数行にまたがっているとうまく読み込めない**(3個の値を1行目、1個を2行目に書いたファイルを`read A B C D`で読もうとして4個目が空になった)。ファイルに書き出す場合は1行1値、またはJSON/を使い`python3 -c`で確実にパースする方が安全
- **AgentCore Runtimeは、クライアントのセッションID再利用が効いていても、設定上の`idleRuntimeSessionTimeout`(15分)よりずっと短い時間(30秒〜5分の間)でコンテナを破棄している**。公開されているタイムアウト設定値を鵜呑みにせず、実機の`bootId`計装ログで裏取りすることの重要性を再確認した
- **査読専用サブエージェントは、ドキュメント間の相互参照(他ファイルの特定セクション番号)が実在するかまで機械的にチェックしてくれる**。今回、複数のfeature branchにまたがって作業したため、あるドキュメントが別ブランチにしか存在しないセクションを参照してしまうという見落としを査読エージェントが発見した。ブランチをまたいだドキュメント作業をする際は、参照先が「今、自分がいるブランチに実在するか」を意識する必要がある

## 15. クライアント向けデモ画面の拡張(2026-09-06〜09-08実施)

> このセクションが本ファイルの最新状態。§14までの記述と矛盾する場合はこちらを優先すること。

### 15.1 実施内容

ユーザーから「今回検証した内容を実機で確認できるデモ画面がほしい」との依頼を受け、既存の疎通検証Webアプリ(`quick-mcp-poc-web-demo`、Lambda Function URL)に4つの新規デモセクションを追加した。いずれもログイン不要、ボタン1つで実際にplaygroundのAWSへライブでリクエストを送る方式。

1. **応答時間デモ**: セッションID再利用の効果を「先週までの挙動」(赤カード)と「今回できるようになったこと」(緑カード)の左右比較で実測表示
2. **DCRデモ**: 静的な左右比較(先週までの認識 vs 今回判明したこと)+ pattern4環境での自己登録→承認→失効の実演(自動クリーンアップ付き)
3. **WAFデモ**: 正常/XSS/SQLiパターンをCloudFront+WAFv2経由で送り通過/遮断を実測
4. **MCPプロトコルv2 SDKデモ**: 現行サーバー(v1 SDK)とv2 SDKスパイクサーバーの両方に、従来形式・新形式(v2の`_meta`エンベロープ)のリクエストを送り、v1は新形式を拒否・v2は両方成功することを実測比較

**このLambdaのソースコードはこれまでリポジトリに一切コミットされていなかった**(2026-09-06に`aws lambda get-function`でzipを取得して復元し、`web-demo/index.mjs`として初めてコミット)。以後はここが正。

### 15.2 新規作成したAWSリソース(playgroundアカウント、883660531246)

| リソース | 識別子 | 用途 |
|---|---|---|
| SDKデモ専用Runtime | `quickMcpPocV2SdkDemo-lxkNuS7moU`(PUBLIC network) | `feature/mcp-protocol-v2-spike`ブランチのイメージ(`quick-mcp-poc-agentcore-verification:v2-sdk-demo-1`)を動かす、v2 SDKデモの「今回」側 |
| Lambda実行ロールへのインラインポリシー | `dcr-demo-permissions`(`quick-mcp-poc-web-demo-lambda-role`に付与) | DCRデモの承認・失効・クリーンアップに必要な`dynamodb:PutItem/UpdateItem/DeleteItem/GetItem`(`quick-mcp-poc-users`テーブル限定)、`cognito-idp:DeleteUserPoolClient`(pattern4プール限定) |
| Lambda環境変数追加 | `M2M_CLIENT_ID`・`M2M_CLIENT_SECRET`(既存の`quick-mcp-poc-m2m-test`クライアントの認証情報) | 応答時間デモ・SDKデモがログイン不要でAgentCore Runtimeを呼べるようにするため |
| Cognitoユーザーのパスワード再発行 | `quick-mcp-poc-verify`(既存ユーザー) | クライアント向けにOAuthログインデモを試してもらうための認証情報発行(新規ユーザーは作らず既存を再利用) |

応答時間デモは既存の`quickMcpPocLatencyLab-uC4Wd7EOWj`(前回セッションで作成済み)を「v1 SDK・現行サーバー」側として流用している。

### 15.3 ブランチ状態

`feature/web-demo-verification-panels`ブランチ(main未マージ)に、`web-demo/index.mjs`・`web-demo/README.md`としてコミット済み。デプロイは既に本番Lambda(playground内)に反映済みで、実機で全機能(4デモ+既存OAuth疎通確認)を確認済み。

### 15.4 学び

- **SSE形式("event: message\ndata: {...}")のレスポンスは、そのまま`JSON.parse`できない**。AgentCore Runtimeの`legacy: "stateless"`フォールバックは`Accept: application/json, text/event-stream`を送ると単発イベントのSSE形式で返すことがあり、`data: `行を抽出してからパースする必要がある。この見落としでSDKデモの初回実装が「v2サーバーは従来形式に失敗する」という誤った結果を出し、実際に動かして初めて発覚した
- **「見える化」を求められたら、まず実機で正確な挙動差を確認してから設計する**。当初は机上の想定(v1は新形式を理解できないはず)で実装を始めそうになったが、先に実際にcurlで4通り(2サーバー×2リクエスト形式)を試したことで、正確な結果行列を把握してから実装でき、手戻りを避けられた
- **`docs/00-handoff.md`のような各ブランチに存在するファイルは、ブランチを切り替えると内容が古い版に戻ることがある**。新しいブランチをmainから切ると、そのブランチ発行時点のmainの内容になるため、他ブランチで追記したセクション(今回は§14)が消えて見える。`git checkout <他ブランチ> -- <ファイル>`で最新版を持ってきてから追記するのが確実

## 16. 今週の検証の総括とセッション完了サマリー(2026-09-08〜09-10実施)

> このセクションが本ファイルの最新状態。§15までの記述と矛盾する場合はこちらを優先すること。

### 16.1 方向性の修正(重要、今後の作業に影響)

このセッションの途中で、ユーザーから本番採用の方向性について重要な確認があった。**本番は現行のECS(API Gateway)アーキテクチャを採用し、そこにDCR・WAF対応を追加する方針で決定済み**。AgentCore Runtimeは今回の技術選定における比較検証にとどまり、ホスティング方式としては不採用となった。

この方針を受けて、§15で作成した週次レポート・デモ画面の力点を修正した。**AgentCore Runtime固有の検証(応答時間チューニングのセッションID再利用、SDK v2のRuntime側検証)はすべて「参考情報」に格下げし、ECS(API Gateway)アーキテクチャでのDCR・WAF対応を主眼に据え直した。** 次回以降のレポート作成・追加検証でも、この優先順位(ECS本位、Runtimeは参考)を踏襲すること。

### 16.2 MCPプロトコルv2 SDKのECS側検証とテストスイート新規作成

§15時点ではAgentCore Runtime側でしかv2 SDKを検証していなかった。今回この抜けを埋めた。

- パターン4環境(playground)に検証専用ECSサービス`quick-mcp-poc-v2-sdk-demo`を新規作成(`feature/mcp-protocol-v2-spike`ブランチの`server/`をamd64向けにビルド)。既存のDCRデモ用サービス(`app`)には一切触れていない
- MCP基本機能を体系的に確認する自動テストスイート(`scripts/mcp_functional_tests.py`、8項目)を新規作成し、v1-ECS/v2-ECS/v1-AgentCore/v2-AgentCoreの4環境すべてに対して実行、**32/32件合格**
- **新規発見**: 未知のツール名を`tools/call`した際、v1 SDKは`result.isError: true`(ツール実行結果としてのエラー)、v2 SDKはトップレベルのJSON-RPCエラー(`code: -32602`、リクエスト自体の不正)という異なる形でエラーを返す。ホスティング方式に関わらず共通する挙動で、Step1でv2採用時にクライアント側のエラーハンドリング実装を両対応させる必要がある
- テスト項目#1〜7はすべて**v1形式(classic、`_meta`エンベロープなし)のリクエスト**で実行しており、v2実装がv1形式のリクエストも問題なく処理できることを確認している。#8のみがv2形式(`_meta`エンベロープ)のリクエストで、v1実装は拒否・v2実装は受理という非対称な期待値で合否判定している(ユーザーからの質問に回答済み、詳細は`scripts/mcp_functional_tests.py`の`Target.call()`・`run_all()`を参照)

### 16.3 MCP用WAF対応の新規検証(ECS+API Gatewayアーキテクチャに対して初めて実施)

これまでのWAF検証はAgentCore Runtime向けの代替構成(CloudFront+WAFv2)でしか実施しておらず、**本番採用方針であるECS(API Gateway)アーキテクチャに対しては一度も検証していなかった**。今回この抜けを埋めた。

- **発見**: API Gateway HTTP API(v2、パターン4が使用中)にはWAFv2 Web ACLを直接アタッチできない(WAFv2がネイティブ対応するAPI GatewayのリソースタイプはREST API v1のみ)。一方、後段のALB(`quick-mcp-poc-alb`)には直接アタッチできることを確認した
- 検証用に一時的なWeb ACL(`AWSManagedRulesCommonRuleSet`+`AWSManagedRulesSQLiRuleSet`)をALBにアタッチし、実際に認可済みのMCPクライアントから`tools/call`のJSON-RPCリクエストボディ(ツール引数)にXSS・SQLインジェクション攻撃パターンを埋め込んで送信したところ、**両方とも403でブロック**されることを確認(CloudWatchメトリクスでも2件のブロックを確認)。先週Runtime向け構成で発見していたSQLi特化ルールの不足も、`AWSManagedRulesSQLiRuleSet`追加で解消することを確認した
- 検証後、Web ACLはALBから解除・削除済み、テスト用DCRクライアントも削除済み。既存の稼働環境への恒久的な変更は残していない

### 16.4 DCRの説明の修正

週次レポートのDCR説明が、登録→承認→失効という「手順」の説明に終始しており、DCR(RFC 7591)自体が何か・なぜ必要かを説明できていないとユーザーから指摘があった。修正内容:

- DCRは、MCPクライアント(Claude等)が**人手を介さず自動的に**OAuthクライアントとして自己登録し、その場で接続情報を受け取れる仕組み(RFC 7591)であることを明記
- なぜ必要か(不特定多数のクライアントが接続する外販サービスでは、事前の手動登録運用が現実的でない)を説明
- **admin承認ステップはDCRの標準仕様ではなく、本サービス独自に追加した業務要件(テナント審査)であり、DCR(登録)とテナント認可(利用許可)は別レイヤーである**ことを明確に区別した

この「DCR本体」と「業務要件として追加した認可レイヤー」の区別は、今後DCR関連の説明をする際に踏襲すること。

### 16.5 インフラ構成図の追加(awsdac)

ユーザーから「各検証で使っている環境・インフラ構成図・前提を追加して視覚的に分かるようにしてほしい」との依頼を受け、DCR・WAF・SDK v2それぞれの検証で実際に使ったインフラ構成をawsdacで作図した。

- `docs/images/dcr-verification-architecture.png`: API Gateway→DCR登録/認可Lambda→Cognito/DynamoDB→ALB→ECS
- `docs/images/waf-verification-architecture.png`: API Gateway(WAF直接アタッチ不可)→ALB(WAF直接アタッチ可能)
- `docs/images/sdk-v2-verification-architecture.png`: 同一ECSクラスター内でv1/v2サービスを並行稼働

**awsdacのTitleフィールドは`<br/>`ではなく実際の改行文字(`\n`)で改行する**(Mermaidとの違い、今回つまずいた)。クライアント向けレポートでは、これらのAWSアイコン入り図の代わりに、同じ構成を汎用的な言葉(受付窓口・認証基盤・データベース等)に置き換えたMermaid図を使い、内部用語の露出を避けている。

### 16.6 今週のレポート(docs/18)の最終構成

`feature/mcp-protocol-v2-spike`ブランチに、社内向け・クライアント向けの2種類を作成しPDF化済み(全ページ目視確認済み)。

- 社内向け: `docs/18-internal-weekly-verification-report-week4.md`(13ページ)。§1 DCR対応(§1.1でDCRとは何かを説明)、§2 WAF対応(今週新規検証)、§3 MCPプロトコルv2 SDK確認(ECS本位・Runtime参考)、§4 デモツール補足、§5 来週のアクションプラン
- クライアント向け: `docs/18-external-weekly-verification-report-week4.md`(7ページ)。同じ構成を平易な言葉で説明、他レポートへの参照は含めず単体で完結させている(ユーザー指示)

### 16.7 ブランチ状態(mainには何もマージされていない、要判断)

今回の作業はすべて`feature/mcp-protocol-v2-spike`ブランチに積み上がっている。現時点で存在する未マージブランチは以下の4つ:

| ブランチ | 内容 | 状態 |
|---|---|---|
| `fix/production-audience-config-proposal` | 本番`terraform/apigateway.tf`の`audience`バグ修正(1行) | レビュー待ちの提案。最優先で本番担当者へ共有すべき |
| `latency-tuning/session-id-reuse` | 応答時間チューニング一式、`docs/15`・`docs/16`(week3レポート) | Runtime固有の内容、§16.1の方針転換により相対的に優先度低下 |
| `feature/web-demo-verification-panels` | `web-demo/`アプリ本体、`docs/17`(環境整理) | デモ画面自体は継続して有用、mainへの反映を検討 |
| `feature/mcp-protocol-v2-spike` | v2 SDK書き換え一式、ECS/Runtime両方のv2検証、`docs/18`(今回) | 本セッションの主要な成果物。ただしMCPサーバー本体のv2書き換えは依然スパイクのまま、mainへの反映は別途判断が必要 |

4ブランチの内容がそれぞれ`docs/`の異なる番号(15〜18)・異なる`web-demo/`状態を持っており、**次回セッションの最初の判断として、マージ順序を決めるかこのまま並行運用するかを検討する必要がある**。`docs/README.md`目次への15〜18番追加も、マージ順序確定後にまとめて行う。

### 16.8 新規作成したAWSリソース(playgroundアカウント、883660531246、今回分)

| リソース | 識別子 | 状態 |
|---|---|---|
| v2 SDK検証用ECSサービス | `quick-mcp-poc-v2-sdk-demo`(`quick-mcp-poc-cluster`内) | 稼働中。タスク定義`quick-mcp-poc-v2-sdk-demo:1`、イメージ`quick-mcp-poc:pattern4-v2-sdk-demo-1` |
| （検証後削除済み）WAF検証用Web ACL | `quick-mcp-poc-apigw-webacl`(REGIONAL) | ALBへのアタッチ・検証後に解除・削除済み。恒久的なリソースは残っていない |

### 16.9 学び

- **「先週発見したこと」と「今週の作業」を混同しないこと**。今回、DCRの`allowedScopes`仮説やWAFのSQLi未対応は先週(§15より前)の発見だったが、初稿では「今回発見した」と誤って書いてしまい、査読で指摘された。週をまたぐ検証の時系列は、書く前に元ドキュメントの日付を確認すること
- **ビジネス上の方針転換(今回: Runtime不採用・ECS採用決定)があった場合、既に書いたレポートの力点を全面的に見直す必要がある**。技術的な正確性だけでなく「何を主・何を従として書くか」がビジネス判断に依存するため、方針が変わったら機械的な修正では済まず、章構成・TL;DRから見直すべき
- **概念の説明(今回: DCR)を書く際は、「手順の説明」と「概念そのものの説明」を混同しないこと**。DCRのような標準規格の話をする場合は、(1)それが何か・なぜ存在するか、(2)本プロジェクトでどう実装したか、(3)本プロジェクト固有に追加した仕様(業務要件)、の3つを明確に分けて書くと、読者が「これはDCRの仕様なのか、独自追加なのか」を混同しない
- **awsdacのTitleフィールドの改行は`\n`(実際の改行文字)であり、Mermaidの`<br/>`とは書式が異なる**。両方使うプロジェクトでは混同しやすいので注意
- **自動テストスイートを作る際、各テストケースがどのプロトコル形式でリクエストを送っているかをコード上明示しておくと、後から「このテストは何を検証しているのか」を聞かれたときにコードを見るだけで即答できる**。今回`modern`引数のデフォルト値(`False`)を確認するだけでユーザーの質問に正確に回答できた

### 16.10 来週の検証計画(2026-09-10、ユーザーからの指示を記録)

セッション終了時にユーザーから次回の検証方針の指示があった。次回セッションはここから着手すること。

**大前提**: **AgentCore Runtimeの検証・考察は今後不要**。今週からメインアーキテクチャはECS構成に確定したため、以降の検証はすべてECS構成のみを対象とする(§16.1の方針をさらに徹底する形)。

1. **WAF対応の深掘り**
   - MCPサーバーに対するAWSの推奨セキュリティ対策(ベストプラクティス)を調査する
   - 攻撃テストのパターンを、本番運用を見据えてさらに充実させる(§16.3で実施したXSS・SQLiの2パターンに加えて、他の攻撃パターン・レート制限・ボット対策等も検討)
   - 上記を踏まえて、次のステップとしてWAFの恒久的なアーキテクチャ・設計(ルール構成、運用体制、監視体制)を検討・実施する
   - スコープ: ECS構成のみ

2. **DCRの認証まわりのブラッシュアップ**
   - 現状の実装はLambda(登録用・認可用)による簡易実装にとどまっている
   - 「本来のDCR対応(RFC 7591準拠性等)」が実現できているといえるか、実装の妥当性を検証・チェックする

3. **DCR・WAFを本番運用に向けたメイン検証項目に格上げ**
   - 本番運用に必要な要件を満たしているか、抜け漏れがないかを継続的な観点として持つ(単発の実機確認で終わらせず、チェックリスト化・体系化することを検討)

4. **商用リモートMCPサーバーの本番運用に向けた調査に着手**
   - AgentCore GatewayなどAWSのAIサービスのベストプラクティスを参考に、DCR・WAFを中心とした商用MCPサーバー運用のための調査を開始する
   - Runtime自体は不採用だが、AgentCore Gateway等の周辺サービスがDCR/WAF文脈での参考事例(ベストプラクティス)として調査対象になりうる点に注意(ホスティング方式としてのRuntime再検討ではないことを明確に区別すること)

---

## 17. Week5セッション完了サマリー(2026-09-13〜14実施)

> このセクションが本ファイルの最新状態。§16までの記述と矛盾する場合はこちらを優先すること。

### 17.1 このセッションでやったこと

§16.10でユーザーから指示された今週の方針(WAF深掘り、DCR準拠性検証、チェックリスト化、商用MCP運用調査)に沿って、プランニングから実機検証・修正・再検証まで実施した。作業ブランチは`feature/week5-waf-dcr-production-readiness`(`feature/mcp-protocol-v2-spike`から分岐)。

セッション冒頭にユーザーが決めた方針:

- 今週の重点は**REST API移行の採否を今週中に判断**すること
- WAFの主案は**CloudFront + WAF**(REST API v1 + NLBではない)。ALBを使わない変形(Cloud Map / NLB)は同じスパイクで比較する
- DCRの修正スコープは**最小(真のRFC準拠 + E2E成立)**。RFC 7592は翌週以降
- 新ブランチを切って随時コミットする

### 17.2 成果物

| 成果物 | 内容 |
|---|---|
| [19-internal-weekly-verification-plan-week5.md](./19-internal-weekly-verification-plan-week5.md) | 今週の検証プラン(WAF・DCR・チェックリスト・商用調査)。§1.9にWAFの実施結果、§2.10にDCRの実施結果を追記済み |
| [20-internal-production-readiness-checklist.md](./20-internal-production-readiness-checklist.md) | 本番運用チェックリスト。WAF(`WAF-NN`)・DCR(仕様番号)・Authorizer(`AUTHZ-NN`)を固定IDで管理し、自動テストの結果IDと1対1で対応させる |
| [21-internal-commercial-remote-mcp-operations-research.md](./21-internal-commercial-remote-mcp-operations-research.md) | AgentCore Gateway・AWS参照アーキテクチャ・MCP仕様・Anthropicコネクタ仕様の机上調査。`OPS-01`〜`OPS-10`の追加行を提案 |
| [22-internal-weekly-verification-report-week5.md](./22-internal-weekly-verification-report-week5.md) / [同クライアント向け](./22-external-weekly-verification-report-week5.md) | 今週の検証レポート。社内向け11ページ・クライアント向け10ページ、PDF化済み(全ページ目視確認済み) |
| `scripts/waf_attack_tests.py` | 攻撃パターン45件(A01〜A25)のハーネス。`X-Waf-Test-Id`でWAFログと突合できる |
| `scripts/waf_log_correlate.py` | WAFログとハーネス結果の突合。どのルールが遮断したか、WAFが見た送信元IPは何かを判定する |
| `scripts/dcr_conformance_tests.py` | RFC 7591 / 7592 / 8414 / 9728 / MCP認可の準拠性テスト。`--cleanup`でテストクライアントを削除 |
| `scripts/pattern4_token.py` | DCRで検証用client_credentialsクライアントを作りトークンを取得するヘルパー |
| `scripts/update_checklist.py` | ハーネスの結果JSONをチェックリストの状態列へ転記する |
| `docs/evidence/` | 実行結果のJSON(DCR基準線・修正後、WAF ALB Count・CloudFront Count・Block・レート制限) |

### 17.3 DCRの結果: 合格19→33、不合格16→2

修正前の基準線を取ってから最小スコープの修正を適用し、再検証した。詳細は[19番 §2.10](./19-internal-weekly-verification-plan-week5.md)。

**基準線で判明した、プランに無かった欠陥**:

- フラグメント付き`redirect_uri`、101件の`redirect_uris`、`client_credentials` + `none`の3ケースで、Cognitoの400が`server_error`の**500に化けていた**
- `response_types: ["token"]`がそのまま受理されていた

**適用した修正**: メタデータ(`scopes_supported`に`invoke`、`jwks_uri`、`revocation_endpoint`、ルートPRM、`openid-configuration`ミラー)、登録の検証とエラー翻訳、`Cache-Control: no-store`、リフレッシュトークンローテーション、Managed Loginブランディングの自動適用、登録数上限とIP別レート制限、Authorizerのdeny-on-missingとaud検証、API Gatewayアクセスログ、テーブル名の環境変数化。

**E2Eで確認すべきこと**: well-knownプローブだけで実際にClaudeが接続できるか。成立すれば`WWW-Authenticate`(OPS-01)の優先度はさらに下がる。

**特筆すべき成果**: HTTP APIのLambda Authorizerは拒否時に403を返すためClaudeがトークンをリフレッシュしない問題(A2)があったが、**Authorizerで例外を投げる方式(`DENY_MODE=throw`)にすると API Gatewayが401を返す**ことを実機で確認し、HTTP APIのまま解消した。

**残る不合格2件**: `WWW-Authenticate`ヘッダ(HTTP APIでは付与不可)、RFC 7592(翌週以降)。

**詰まった点**: リフレッシュトークンローテーションを有効にすると、Cognitoが`ExplicitAuthFlows: ALLOW_REFRESH_TOKEN_AUTH`との併用を拒否する。認可コードフローのリフレッシュは`/oauth2/token`経由なので`ExplicitAuthFlows`を外して解消した。

### 17.4 WAFの結果: 主案(CloudFront + WAF)をBlockモードで検証、攻撃16件遮断・誤検知ゼロ

詳細は[19番 §1.9](./19-internal-weekly-verification-plan-week5.md)。45パターンの内訳は、WAFが403で遮断した攻撃16件(うち14件はWAFログで`terminatingRuleId`まで確認)、CloudFrontまたはサーバーが400/405/415で拒否した攻撃5件、記録のみの攻撃11件、そして**全件200で通過した正常系コーパス13件**である。

**数値の注意**: ハーネスの「合格35」は正常系13件の通過を含む合否判定の数であり、遮断件数ではない。レポート初稿でこれを「35件遮断」と誤記し、証跡JSONからの再計算で気づいて訂正した(§17.7)。

**先週の結論を修正すべき発見(最重要)**: ALBにWAFをアタッチすると、**WAFが見る送信元IPはVPC Link ENIのプライベートIP(10.0.11.94)に集約される**。真のクライアントIPは`forwarded`ヘッダにしか無く、IPベースのレート制限・Geo・IPレピュテーションは全クライアントを同一IPとして扱うため機能しない。[18番 §2](./18-internal-weekly-verification-report-week4.md)の「ALBにアタッチすれば対応可能」はボディ検査に限れば正しいが、恒久設計としては不十分。CloudFront構成では真のクライアントIPで評価でき、Geoラベルも正しく付与された。

**全ルート保護**: `/register`のSQLiと`/token`のXSSもBLOCKされた。ALBアタッチではこれらの経路は保護できない。

**その他の新規発見**: (1) JSON文字列値に埋めたBase64のJavaシリアライズ列は`KnownBadInputsRuleSet`で検知されない、(2) ボディ検査上限の既定(CloudFront 16KB、ALB 8KB固定)では日本語の長文引数が誤検知するため64KBへ引き上げが必要、(3) CloudFrontはURIトラバーサルとTRACEをWAF評価前に自身で拒否する、(4) レートベースルールは反映遅延があり短時間バーストでは発火しない(閾値を一時的に下げて機構を確認済み)、(5) `/register`の連打はLambda内IP別カウンタとAPI GWスロットルで既に多層に止まっている。

### 17.5 REST API移行の採否(今週の最重点): **移行しないと判断**

ユーザーが「今週中に判断」と指示した項目。**結論: REST API v1へは移行せず、CloudFront + WAF + HTTP API(主案d)を継続する。** 詳細と根拠は[19番 §1.10](./19-internal-weekly-verification-plan-week5.md)。

REST移行の動機は4つあったが、

- 「全ルート保護」「真のクライアントIP」はCloudFront + WAFで**達成済み**(§17.4)
- 「テナント別スロットリング」はWAFのレートベースルール(`Authorization`集約キー)で代替する設計にした
- 残るのは「Gateway Responsesによる`WWW-Authenticate`付与」のみ

その`WWW-Authenticate`について、CloudFront Functions(viewer-response)で代替できるかを実測した(S12)。**結果は不可**: オリジンが4xxを返した応答ではviewer-response関数がトリガされない(200では実行され検証用ヘッダが付くが、401では一切付かない。関数単体の`test-function`では401イベントに正しく付与するため、コードではなくCloudFront側の制約)。

ただしMCP 2026-07-28では保護リソースメタデータの提供は「`WWW-Authenticate` **または** well-known」の択一MUSTであり、現状のwell-known提供(今週ルートPRMも追加)で**仕様違反ではない**。したがって`WWW-Authenticate`は「相互運用性の信頼度を上げる推奨項目」と位置づけ、必要になった場合は**Lambda@Edge origin-response**(1〜2日、オリジンのエラー応答でも実行される)を第一候補とする。REST API移行(5〜7日)は、閉域網(PRIVATEエンドポイント)やテナント別クォータが要件として確定した時点で再評価する。

### 17.6 playgroundに作成したAWSリソース(今回分)

| リソース | 識別子 | 状態 |
|---|---|---|
| CloudFrontディストリビューション | `E1T56DLS986BE4` / `djwyl11zhnd52.cloudfront.net` | 稼働中。オリジンは現行HTTP API |
| Web ACL(CLOUDFRONT、us-east-1) | `quick-mcp-poc-edge` | 稼働中、Blockモード。ボディ検査上限64KB |
| WAFログ用ロググループ(us-east-1) | `aws-waf-logs-quick-mcp-poc-edge` | 90日保持 |
| API Gatewayアクセスログ | `/quick-mcp-poc/apigw-access` | 90日保持 |
| (削除済み)ALBプローブ用Web ACL | `quick-mcp-poc-alb-probe` | 検証後にデタッチ・削除。terraformファイルも削除済み |
| DynamoDB TTL | `quick-mcp-poc-users`の`expiresAt`属性 | 有効化(IP別レート制限カウンタの自動削除用) |
| 静的クライアントの`CLIENT#`レコード | `CLIENT#69eu35v522jnt0blnb26lij1ei`(`source: static`) | deny-on-missing対応のため投入 |

**コスト注意**: CloudFront + Web ACL(us-east-1)で月額$6〜10程度が追加で発生する。§16.8までのplayground複製一式(月額約$46相当)に上乗せされる。不要になったら`terraform destroy -target=aws_cloudfront_distribution.edge -target=aws_wafv2_web_acl.edge`等で削除する。

**テストクライアントの後片付け**: 検証で作成したDCRクライアントはすべて削除済み(`scripts/dcr_conformance_tests.py --cleanup`)。Cognitoに残っているのは`quick-mcp-poc-mcp-client`(静的)、`dcr-sanity-check-*`(§16以前から存在)、`dcr-pattern4-token-helper-*`(ハーネス用、継続利用するなら残置)の3つ。`COUNTER#dcr`は0に戻っている。

### 17.7 学び

- **「ハーネスの期待値」と「設計上の意図」を混同しないこと**。Blockモードの初回実行で8件がFAILになったが、実際には4件がCloudFrontのWAF評価前の拒否、2件が意図的なcount上書き、1件が未実装のカスタムルールで、真の欠陥は1件(Javaシリアライズ)だけだった。テストの期待値には「なぜその結果が正しいのか」をコメントで残すと、次回の実行者が誤った修正をしない
- **WAFログの`clientIp`は配置場所で意味が変わる**。ALB配下では前段のENIのIPになる。IP系ルールを設計する前に、必ず実機でログの`clientIp`を確認すること
- **マルチバイト文字はボディ検査上限を3倍速く消費する**。日本語主体のサービスでは既定16KBは実質5,000文字程度で、`oversize_handling = MATCH`のルールが誤検知する
- **AWS CLIの引数は`$P`のような変数展開でまとめて渡せない**(1つの引数として解釈される)。プロファイルとリージョンは毎回明示するか、環境変数を使う
- **レポートの数値は必ず証跡JSONから再計算して検証すること**。今回、Blockモードの結果を「45パターン中35件を遮断」と書いたが、35は正常系13件の通過を含む合格数であり、実際にWAFが遮断したのは16件だった。ハーネスの合格数をそのまま成果として書くと、正常系の通過を遮断件数として報告してしまう
- **太字はCommonMarkのflanking ruleでPDFに`**`が生のまま残ることがある**。閉じの`**`が全角の閉じカッコ(`」`など)の直後で、かつ直後が日本語の文字だと強調として閉じられない。`pandoc -f gfm -t html5 <file> | grep -c '\*\*'`が0であることを機械チェックすること
- **Mermaidの`<br/>`はPDF描画で無視される**(`scripts/render-pdf.sh`経由)。ノードラベルは`<br/>`に頼らず、短いラベル + 点線でつないだ詳細ノードに分けると読みやすい。長いラベルを`<br/>`で改行した図は、PDFで文字が詰まって判読しにくくなる
- **SSOトークンは作業中に失効する**。長時間のterraform applyやハーネス実行の前に`aws sts get-caller-identity`で確認すると、途中で失敗して中途半端な状態になるのを避けられる

### 17.8 ユーザー(人間)の確認・判断が必要な項目

セッション終了時点で、私の側で完了できず**ユーザーの確認・判断を待っている**項目。次回セッションの冒頭でこの節の消化状況を確認すること。

**A. ユーザーにしかできないこと**

| # | 項目 | 内容 |
|---|---|---|
| A1 | **本番の401バグの共有(最優先、数週間滞留中)** | `fix/production-audience-config-proposal`ブランチの1行修正案が未共有。本番のJWT Authorizerが、Cognitoが実際に発行するトークンと一致しない値を参照しているため**正当なトークンでも常に401**になる。playground複製で再現確認済み。本番アカウントは書き込み禁止のため共有はユーザーが行う必要がある。**今週の追加事実**: CognitoはRFC 8707の`resource`パラメータに対応しており(§17.3のF1相当)、`resource`を指定する前提なら現在の設定値のほうが正しくなる。共有時は「修正案」と「resource指定を前提にする案」の両方を提示すること |
| A2 | **Claude Code / Claude.aiからの自己登録E2E** | ブラウザでのログイン操作が必要。確認すべきは3点。(1) DCRで作られたクライアントでログイン画面が表示されるか(今週修正したCL-03)、(2) `WWW-Authenticate`無しでwell-known経由だけで接続が成立するか、(3) 60分後もトークンが自動更新され接続が維持されるか(DS5)。**(3)が成立すればREST API移行を見送った判断(§17.5)が実地で裏付けられる** |

**B. 判断が必要なもの**

| # | 項目 | 内容 |
|---|---|---|
| B1 | REST API移行を見送る判断の承認 | 私が結論を出したがアーキテクチャの意思決定。根拠は[19番 §1.10](./19-internal-weekly-verification-plan-week5.md)と[22番 §3](./22-internal-weekly-verification-report-week5.md) |
| B2 | 例外台帳4件の承認 | 意図的にCountのまま運用するルール。すべて「未承認(検証段階の暫定)」で[20番 §4](./20-internal-production-readiness-checklist.md)に登録済み。本番適用前に承認が要る |
| B3 | `WAF-12`のリスク受容 | JSON内にBase64で埋めたJavaシリアライズ列が検知されない。カスタムルールを作るか、影響の小ささで許容するか |
| B4 | playgroundリソースの残置可否 | CloudFrontとWeb ACLで月額$6〜10が追加発生(既存の複製一式 約$46への上乗せ)。削除手順は§17.6 |
| B5 | 未マージ5ブランチの整理 | `docs/README.md`の目次更新(15〜22番)がこれ待ちで止まっている |

**C. 私の作業でユーザーに確認してほしいもの**

| # | 項目 | 内容 |
|---|---|---|
| C1 | **先週のクライアント向け報告の訂正** | 先週「ALBにアタッチすれば対応可能」と報告した結論を今週のレポートで訂正している。[18番](./18-internal-weekly-verification-report-week4.md)を既にクライアントへ共有済みであれば、訂正が届く形になる。送付前に確認が要る |
| C2 | クライアント向けレポートの文面 | QUICK様宛の10ページ。技術用語を平易な言葉に置き換えているが、その置き換えが意図どおりかは要確認 |
| C3 | terraformの既知のドリフト | playgroundで`terraform plan`するとNATインスタンス2台の置き換えが提案される(`data.aws_ami`が最新AMIを拾うためで今回の作業とは無関係)。今回はすべて`-target`で回避した。`lifecycle { ignore_changes = [ami] }`を入れるかの判断が残っている |

### 17.9 次回セッションの着手順

1. §17.8の消化状況を確認する(特にA1・A2)
2. **Claude Code / Claude.aiからの自己登録E2E**(A2)。これが済むまでDCRの修正は実地で裏付けられていない
3. WAFのログ保全(Firehose → S3 Object Lock、S8)と監視(アラーム、S9)
4. カスタムドメイン導入(OPS-08)と、それに伴う秘密ヘッダの強制(`ENFORCE_ORIGIN_VERIFY=true`、S10)
5. 本番`terraform/`への移植コード準備(未適用、W6)
6. `docs/README.md`の目次更新(15〜22番)は、未マージブランチのマージ順序を決めてからまとめて行う(§16.7の運用を踏襲)

### 17.10 セッション終了時点の状態(2026-09-14)

| 項目 | 状態 |
|---|---|
| ブランチ | `feature/week5-waf-dcr-production-readiness`(`feature/mcp-protocol-v2-spike`から分岐)。7コミット、作業ツリーはクリーン。**リモートへのpushは未実施** |
| 未マージブランチ | 5本(`fix/production-audience-config-proposal`、`latency-tuning/session-id-reuse`、`feature/web-demo-verification-panels`、`feature/mcp-protocol-v2-spike`、本ブランチ) |
| 疎通 | CloudFront経由・API Gateway直の両方で`tools/list`が200。XSSはCloudFront経由で403 |
| テストクライアント | 全削除済み。Cognitoに残るのは`quick-mcp-poc-mcp-client`(静的)、`dcr-sanity-check-*`(§16以前)、`dcr-pattern4-token-helper-*`(ハーネス用、継続利用するなら残置)の3つ。`COUNTER#dcr`は0 |
| 一時リソース | ALBプローブ用Web ACLは削除済み(terraformファイルも削除)。CloudFront検証用のCloudFront Functionも削除済み |
| ハーネスの使い方 | `eval "$(python3 scripts/pattern4_token.py token)"`でトークン取得 → `scripts/waf_attack_tests.py` / `scripts/dcr_conformance_tests.py`を実行 → `scripts/update_checklist.py`で[20番](./20-internal-production-readiness-checklist.md)へ転記。DCRテストは実行後に必ず`--cleanup`すること |

---

## 18. main集約・バージョニング・納品準備の着手(2026-09-15実施)

> §17までの記述と矛盾する場合はこちらを優先すること。ただし**本ファイルの最新状態は§19**であり、§18.4・§18.8の一部は§19で訂正されている。

### 18.1 このセッションの位置づけ

ユーザーから新しい方向性が示され、検証フェーズから**納品フェーズ**へ移行した。

- **QUICK様のAWS環境にTerraformを納品する**ことが決定
- Week1以降の各アーキテクチャを`main`に集約し、**LLMのモデル名のようにバージョン管理**する
- **CI/CD**(納品・デプロイ・Terraform適用)の検討に着手する
- **FDE(Forward Deployed Engineer)成果物**をprimenumber社内資料として整理する
- ツール・リソース・プロンプト単位の**権限管理**を検討する

### 18.2 ユーザー決定事項(2026-09-15)

| # | 論点 | 決定 |
|---|---|---|
| 1 | MCP SDK v2をmainへ入れるか | **v2は決定事項として取り込む**。加えて**AgentCore版もmainに含める**(ホスティングはECS確定だが、AgentCore構成もTerraformとして保持) |
| 2 | 納品の構成 | **納品用ディレクトリを分離**。検証レポートとFDE内部資料はprimenumber側に残す |
| 3 | 細粒度権限管理 | **まずECSサーバー内で実装**。AgentCore Gatewayは評価トラック |
| 4 | 今週の範囲 | **ブランチのmain集約とTerraformの変数化・モジュール化を優先**。CI/CDとFDE資料は設計方針の文書化まで |
| 5 | mainの扱い | **mainを最新にする**(統合ブランチをマージしpush) |
| 6 | バージョンタグ | **承認**。遡及タグを含めて発番 |

注: 決定1でユーザーは「ホストはEC2」と記述したが、これまでの全検証がECS Fargate前提のため**ECSと解釈**した。→ **§19.1で解決済み(2026-09-15)。ユーザーに確認し、ECS Fargateで正しいことが確定した。**

### 18.3 完了した作業

**(1) 依存関係の脆弱性46件を解消し、mainへ反映**

- 46件すべてが**推移的依存**(直接依存は該当なし)。`main`から`fix/dependabot-vulnerabilities`を切り、既存のバージョン範囲内でロックファイルを更新
- hono 4.12.12→4.13.7、fast-uri 3.1.0→3.1.7、qs 6.15.0→6.16.0、ip-address 10.1.0→10.7.0、body-parser 2.2.2→2.3.0、esbuild→0.28.2。fast-xml-parser / fast-xml-builder は新しいAWS SDKが依存しなくなり消滅
- マニフェスト変更は1件のみ: `lambda/package.json`が esbuild を `^0.24.2` に固定しており修正版0.25.0が範囲外だったため `^0.28.2` へ引き上げ
- **main反映後、GitHubのアラートは0件になったことを確認済み**

**(2) 6ブランチをmainへ集約**

マージ順序と競合の解決内容:

| # | ブランチ | 競合 | 解決 |
|---|---|---|---|
| 1 | `fix/dependabot-vulnerabilities` | なし | — |
| 2 | `fix/production-audience-config-proposal` | なし | — |
| 3 | `feature/web-demo-verification-panels` | なし | — |
| 4 | `latency-tuning/session-id-reuse` | `docs/00-handoff.md`・`docs/README.md` | 新しいHEAD側を採用。自動マージ部分は保持 |
| 5 | `feature/mcp-protocol-v2-spike` | `server/src/index.ts`・`package.json`・lock・`docs/00-handoff.md`・`docs/12` | **下記の手作業が必要だった** |
| 6 | `feature/week5-waf-dcr-production-readiness` | なし | — |

**実質的な競合は2つ**だった。

- `server/src/index.ts`: v2が`app.all("/mcp", ...)`ハンドラに全面書き換えした一方、latency-tuningが同じ箇所に`LOG_TIMING`計測を入れていた。**v2ハンドラを採用し、計測コードを手で再適用**。起動して`boot`・`request_received`の両ログが出ることを確認済み
- `server/package.json`: v2のMCPパッケージ(`@modelcontextprotocol/node` + `server`)と、脆弱性修正済みのAWS SDK 3.1131.0を**両立**させる必要があった。ロックを削除して`pnpm install`で再生成

`docs/00-handoff.md`は§13→§14→§15→§16と時系列順に並ぶよう解決した。

**(3) バージョンタグ5件を発番(すべてSSH署名付き)**

| タグ | 対象コミット | 内容 |
|---|---|---|
| `quick-mcp-ecs-1.0-20260903` | `83e0f17` | DCR実装、クロステナントなりすまし脆弱性修正まで。WAF未対応、MCP SDK v1 |
| `quick-mcp-ecs-1.1-20260903` | `c0fc0d9` | 応答時間チューニング、ECS本番化の課題整理 |
| `quick-mcp-ecs-1.2-20260910` | `8a651ca` | MCP v2 SDK、ECS構成へのWAF初適用 |
| `quick-mcp-ecs-1.3-20260914` | `275495d` | DCRのRFC 7591準拠(不合格16→2)、CloudFront + WAF(Block)、REST API移行の見送り判断 |
| `quick-mcp-ecs-1.4-20260915` | `2bf9ea2` | 全成果をmainへ集約。Terraform製品化の起点 |

命名規則は `quick-mcp-<variant>-<major>.<minor>-<YYYYMMDD>`。`variant`は`ecs`(本採用)と`agentcore`(代替)。

**`agentcore`バリアントのタグは未発番**。AgentCore RuntimeはAWS CLIで作成されておりTerraform化されていないため、タグを付けられるコード状態が存在しない。フェーズ2で`infra/modules/mcp-server-agentcore/`を作成した時点で`quick-mcp-agentcore-1.0-<日付>`を発番する。

**(4) FDE成果物の1本目を作成**

`docs/fde/ARCHITECTURE-VERSIONS.md` — バージョン台帳。各バージョンの構成・検証済み項目・既知の課題を記録し、命名規則と運用ルールを定義。

**(5) docs/README.mdの目次を18〜22番まで更新**。リポジトリ全体でリンク切れゼロを確認。

### 18.4 調査で判明した納品ブロッカー(重要度順、**すべて未対応**)

次回セッションのフェーズ2はこれを潰す作業になる。

> **§19.2で3件を訂正済み。以降は[docs/fde/DELIVERY-BLOCKERS.md](./fde/DELIVERY-BLOCKERS.md)を正とする**(固定ID DB-01〜09で追跡)。訂正は 5(59→**75**リソース)、6(**ほぼ解消済み**)、1(`secrets`のみ`terraform/`側を正とする例外あり)。

1. **`terraform/`(本番相当)はplaygroundより1世代以上古い**。WAF・CloudFront・DCR Lambda・Lambda Authorizerが**一切無い**。統合方向は playground → terraform
2. **ECSサービスとタスク定義がTerraform管理外**。`aws_ecs_service`はどの`.tf`にも存在せず、ecspressoが所有。`ecspresso/app/ecspresso.yml:10`がprimenumberのtfstate S3 URLをハードコードして直読みしている
3. **`variable`ブロックが0個、`.tfvars`が0個**。アカウントID・AWSプロファイル名・AMI ID・S3バケット名が直書き(`terraform-playground-pattern4/provider.tf:21`に`profile = "quick-agentcore-poc-playground"`等)
4. **`terraform/ssm.tf:35,39`のKMS暗号文がprimenumberのKMSキーに紐づく**。別アカウントでは復号できず`apply`が必ず失敗する。納品先での再暗号化手順が必須
5. **playgroundのstateがローカルファイルのみ**。59リソースの唯一のstateがディスク上にある
6. **アプリコードがDynamoDBテーブル名とリージョンを直書き**(`server/src/db.ts:20`、`cli/src/db.ts:4`)。Terraformが作るテーブル名と一致せず、IAMで両方許可する回避策が入っている(Lambdaは`TABLE_NAME`環境変数化済み)
7. **Cognitoドメインプレフィックスはリージョン内でグローバル一意**。複数環境を同一リージョンに立てるには変数化が必須
8. **本番相当環境へは一度もデプロイされていない**。プロファイルが`AWSPowerUserAccess`でIAM作成権限が無く、書き込み禁止運用のため。CI/CDの本番パスは未検証の白地
9. 手作業でTerraform管理外のリソースが多数(AgentCore Runtime、VPCエンドポイント、Webデモ用Lambda、テストユーザー、DynamoDBテーブル本体)

### 18.5 CI/CDの現状(調査結果、**未着手**)

**存在しない**。`.github/`もCI設定も0件。ビルド・デプロイは`README.md:54-69`の手動9行。設計時に効く落とし穴:

- `docker build --platform=linux/amd64`の付け忘れでFargateが`exec format error`
- ECRが`IMMUTABLE`のため同一タグの再pushが不可
- `lambda/dist/`は未コミットで`terraform apply`前に`pnpm build`が必要だが**手順が文書化されていない**
- ECSサービスに`deploymentCircuitBreaker`が無く**自動ロールバック無効**
- SSOトークンがapply途中で失効する。CIからはSSO不可でGitHub OIDC → AssumeRoleへの置換が必須
- リポジトリは**SSH署名必須**。CIからのcommit/tag pushには署名鍵の設定が要る

### 18.6 細粒度権限管理(調査の最大の発見、**未実装**)

**ECS側に実装がすでに存在し、2行のコメントアウトを外すだけの状態**だった。

- `server/src/tools/registry.ts` — `TOOL_MAP[serviceId][plan]`のプラン別ツール表が実装済み
- `server/src/auth.ts` — `resolveTools(user.services)`が`allowedTools: string[]`を返す
- `server/src/tools/earthquake.ts` / `crypto.ts` — `allowedTools.includes(...)`で登録を出し分ける実装済み
- `server/src/index.ts` — `registerEarthquakeTools(server, userContext.allowedTools)`が**コメントアウト**され、`registerQuickTools(server)`を無条件登録している

MCP仕様(2026-07-28)は「`tools/list`の内容を**リクエストの資格情報によって**変える」ことを明示的に許可している(接続ごとに変えるのは禁止)。したがって`createMcpHandler`を**リクエストスコープ化**して`allowedTools`を渡す必要がある。

**AgentCore Gatewayについて**: 既存のリモートMCPサーバーを**MCP server target**として前段に置けることを確認した。Cedarポリシーとinterceptor Lambdaで引数レベルまでの認可が可能で、`toolName`単位のレート制限と`WWW-Authenticate`の標準実装も得られる。ただし**2LOのclient_credentialsではECS側から全リクエストが同一identityに見え、`USER#<sub>`によるテナント管理が壊れる**。回避には`TOKEN_EXCHANGE`(RFC 8693)が要るが、**Cognitoでの成立可否は未確認**。ここが案の成否を決める唯一の論点。

### 18.7 セッション終了時点の状態(2026-09-15)

| 項目 | 状態 |
|---|---|
| `main` | `692315d`。リモートと同期済み。docs 30本、目次22番まで反映、リンク切れゼロ |
| ビルド | `server`・`lambda`・`cli`の3パッケージとも型チェック通過 |
| Dependabot | **0件**(46件すべて解消) |
| タグ | `quick-mcp-ecs-1.0`〜`1.4`の5件をpush済み |
| 統合前のブランチ | 6本ともmainにマージ済み。**削除していない**(履歴確認用に残置。不要なら削除可) |
| `integrate/main-consolidation` | 作業用。mainへマージ済みでリモート未push |
| AWS環境 | **今回は一切変更していない**。playgroundのリソースは§17.6のまま |

### 18.8 次回セッションの着手順

1. **フェーズ2: Terraformの変数化とモジュール化**(今回の主目的、未着手)
   - `terraform-playground-pattern4/`を正として`infra/modules/`へ再構成(`terraform/`は1世代古いため取り込まない)
   - モジュール候補: `network` / `auth` / `secrets` / `mcp-server-ecs` / `mcp-server-agentcore` / `dcr` / `edge-waf`
   - 環境: `infra/environments/{playground,primenumber,quick}`
   - §18.4のブロッカー1〜7を潰す。特に**ECSサービスのecspresso→Terraform移行**と**KMS暗号文の環境別化**
   - モジュール化の難所: **Cognito ⇄ API Gatewayの循環参照**(`cognito.tf:43`のresource server identifierがAPI GW endpointを参照し、`apigateway.tf:91`のaudienceがCognitoを参照)。カスタムドメインを先に固定してidentifierを変数化する設計が要る
     → **§19.3で訂正。この循環参照は存在しない**。依存は一方向DAGであり、引用した`apigateway.tf:91`はplayground世代には無い(1世代古い`terraform/`側の行)。カスタムドメインの先行固定も不要。ただし`resource_server_identifier`の変数化は別の理由で必要で、**本物のモジュール循環は`random_password.origin_verify`にある**
2. **フェーズ3: AWS環境の整理とバージョニング**。playgroundは他プロジェクトと**共用**(trocco、PetStore等が同居)のため`quick-mcp-poc*`に限定する。削除候補は§17.6とフェーズ3の表を参照。**削除は必ず事前確認を取る**
3. **フェーズ4: CI/CD方針の文書化**(`docs/fde/CICD-DESIGN.md`)
4. フェーズ5: 細粒度権限管理のECS側実装(§18.6)
5. フェーズ6: FDE成果物の残り(ADR、DELIVERY-REQUIREMENTS、RUNBOOK、RISK-REGISTER)

### 18.9 §17.8から持ち越した、ユーザーの確認待ち項目

いずれも**今回のセッションでは解消していない**。

- **A1 本番の401バグの共有**(数週間滞留中)。`fix/production-audience-config-proposal`はmainにマージ済みだが、**本番担当者への共有は未実施**。なおWeek5でCognitoがRFC 8707の`resource`パラメータに対応していると判明したため、「修正案」と「resource指定を前提にする案」の両論を提示するのが正確
- **A2 Claude Code / Claude.aiからの自己登録E2E**。ブラウザ操作が必要。DCR修正が実接続で効いているかは未確定
- B1〜B5(REST API見送りの承認、例外台帳4件の承認、WAF-12のリスク受容、playgroundリソースの残置可否、未マージブランチの整理)
- C1 先週のクライアント向け報告の訂正が送付済みか、C2 クライアント向けレポートの文面確認、C3 NATインスタンスのAMIドリフト対応

### 18.10 学び

- **マージ順序は「触るファイルが少ないブランチから」が正解だった**。依存更新・1行修正・独立ディレクトリを先に入れ、`server/`を書き換える2本を最後に回したことで、実質的な競合は2箇所に収束した。逆順だと同じ競合を何度も解き直すことになる
- **同じファイルを「書き換える」ブランチと「追記する」ブランチが並走すると、gitは助けてくれない**。v2の全面書き換えとlatency-tuningの計測追加は、機械的には競合として出るが、正しい解決は「両方を意図どおり共存させる」ことで、これは手作業でしか判断できない。マージ後に**起動して両方の機能が効いていることを確認**するまで完了とみなさないこと
- **ロックファイルの競合は解決しようとせず再生成する**。`server/pnpm-lock.yaml`は両側で大きく異なっていたが、`package.json`さえ正しく統合すれば`pnpm install`が正解を作る
- **「検証が終わっている」ことと「納品できる」ことは別物**。46件の機能検証が終わっていても、アカウントIDのハードコード1箇所で他環境では動かない。納品を見据えるなら、検証と並行して変数化を進めるべきだった

---

## 19. フェーズ2の着手前調査と作業計画の作成(2026-09-15実施、Week6)

> **このセクションが本ファイルの最新状態。§18までの記述と矛盾する場合はこちらを優先すること。**

### 19.1 ユーザーへの確認で確定した事項

| # | 論点 | 確定内容 |
|---|---|---|
| 1 | **ホスティング方式**(§18.2の注が確認を求めていた件) | **ECS Fargateで正しい**。決定事項1の「ホストはEC2」は誤記であり、前セッションのECS解釈が正しかった。§18.2の注記は解決済みとして更新した |
| 2 | 今セッションのスコープ | **変数化とモジュール骨格まで**。AWSへの`plan`/`apply`は行わない。ECSサービスのecspresso→Terraform移行(DB-02)とKMS再暗号化(DB-04)は設計文書のみ |
| 3 | ドキュメントの形 | 作業計画を`docs/23`として新規作成し、納品ブロッカー9件は`docs/fde/DELIVERY-BLOCKERS.md`として固定ID(DB-01〜09)の追跡台帳にする |

### 19.2 §18.4の納品ブロッカー記述の訂正(3件)

以降は[docs/fde/DELIVERY-BLOCKERS.md](./fde/DELIVERY-BLOCKERS.md)を正とする。

| ブロッカー | §18.4の記述 | 実際 | 根拠 |
|---|---|---|---|
| 5 | 「**59リソース**の唯一のstateがディスク上にある」 | **75リソース**(managed 75 / instances 82、ほかdata source 12) | `terraform-playground-pattern4/terraform.tfstate`を直接パースして計数。差は`for_each`で2インスタンスを持つ7リソース(`aws_eip.nat`、`aws_instance.nat`、`aws_route_table.private`、`aws_route_table_association.private`/`.public`、`aws_subnet.private`/`.public`)。**`moved`ブロックの作業量見積もりが変わる** |
| 6 | 「アプリコードがDynamoDBテーブル名とリージョンを直書き(`server/src/db.ts:20`、`cli/src/db.ts:4`)」 | **ほぼ解消済み**。両ファイルとも`process.env.TABLE_NAME ?? "quick-mcp-poc-users"`。Week5の[docs/19 §2.1 F12](./19-internal-weekly-verification-plan-week5.md)の対応が入っている | `server/src/db.ts:21`、`cli/src/db.ts:5`。残作業は`??`除去と`ecspresso/app/ecs-task-def.json:26-31`への`TABLE_NAME`追加の2点のみ |
| 1 | 「統合方向は playground → terraform」 | 方向は正しいが**1箇所だけ例外**。`terraform/ssm.tf:20-72`の`for_each`マップ + `aws_kms_secrets`パターンがplayground側より汎用で、`payload != ""`ガード(`:57,65`)がKMS再暗号化の二段階適用を支える | `secrets`モジュールのみ`terraform/`を正とする |

なおブロッカー5の緊急度は据え置く。stateファイルにはSSMのプレースホルダ値と`random_password.origin_verify`の生成結果が含まれる。`.gitignore:3`(`*.tfstate`)で追跡対象外であることは確認済み。

### 19.3 §18.8が「最大の難所」とした循環参照は存在しない

§18.8-1は「`cognito.tf:43`のresource server identifierがAPI GW endpointを参照し、`apigateway.tf:91`のaudienceがCognitoを参照する循環」としていたが、**API Gateway側からCognitoを指す辺が無い**。

- `aws_apigatewayv2_api.main`(`apigateway.tf:37`)は**依存ゼロ**
- 引用された`apigateway.tf:91`の`audience`行は**playground世代には存在しない**。playgroundはJWT AuthorizerをLambda REQUEST型に置換済み(`apigateway.tf:94-103`)。それは1世代古い`terraform/apigateway.tf:96`の行で、しかも参照先はresource serverではなく**アプリクライアントID**
- 実際の依存は `apigw-api → cognito → dcr-lambda → apigw-authorizer → cloudfront` の一方向DAG。循環があればTerraformは`Cycle:`エラーで`plan`すら通らない

**「カスタムドメインを先に固定する」という前提条件も不要**だった。Cognitoのresource server `identifier`は不透明文字列で、URLとして解決されることはない。

ただし `resource_server_identifier` の変数化は**別の2つの理由で必要**。

1. identifierがAPI GatewayのURL由来のため**`apply`前に確定しない**。`quick`環境の新規構築で実害が出る
2. API再作成でidentifierが変わると`aws_cognito_resource_server`とスコープが連鎖再作成され、**発行済みDCRクライアントのスコープ付与が全滅する**

**tfvarsには現行の実値をstateからコピーすること。手打ち禁止。** 1文字違えば上記2がそのまま起きる。

**本物のモジュール循環は別にあった。** `random_password.origin_verify`(`cloudfront_waf.tf:48`)が`dcr`(`lambda.tf:78`)と`edge-waf`(`cloudfront_waf.tf:459`)の両方から参照され、`edge-waf → dcr → api-gateway → edge-waf`を作る。**環境ルートへ引き上げ、`moved`ブロックを書かない**(ルートのアドレスが変わらないため)。誤って消すと再作成で`X-Origin-Verify`がローテートし、稼働中のCloudFrontとLambda Authorizerの間に値の不一致窓が開く。

### 19.4 その他の調査結果

- **`mcp-server-agentcore`に移行元コードが存在しない**。両ディレクトリの`.tf`にAgentCoreリソースは**1件も無く**、コメント言及3件(`ecs.tf:86`、`cognito.tf:38`、`ssm.tf:3`)のみ。AWS CLIで作成されたままTerraform化されたことがない。**移行ではなく新規作成**のため、今回はスタブに留める
- **モジュールが1つ足りない**。API Gateway(`apigateway.tf` 213行 + `openapi.yaml`)が§18.8の7モジュールのどれにも属さず、しかも依存グラフの中心。`api-gateway`を8つ目として独立させる。`mcp-server-ecs`に混ぜると将来AgentCoreバリアントを同じAPI Gatewayの背後に置けなくなる
- **`module`ブロックに`depends_on`/`count`/`for_each`を付けてはならない**。いずれもモジュールを単一グラフノードに潰し、存在しなかったはずの循環を発生させる。任意化はモジュール内リソースの`count`で行う
- **ルート`outputs`はecspressoとの互換契約**。`ecs-task-def.json`と`ecs-service-def.json`が8つの出力を名前で読む。改名するとTerraformエラーではなく難解なecspressoテンプレートエラーになる
- **playgroundにはecspresso設定が存在しない**。stateがローカルでtfstateプラグインが読めないため。DB-05とDB-02は連動している
- **`terraform/apigateway.tf:91-95`に本番401バグの記録がコメントで残っている**(resource server identifierをaudienceにして全トークンが壊れた)。世代マージで失わないこと

### 19.5 作成・更新したドキュメント

| ファイル | 内容 |
|---|---|
| [docs/23-internal-weekly-verification-plan-week6.md](./23-internal-weekly-verification-plan-week6.md)(新規) | Week6の作業プラン。上記の調査結果、8モジュールの構成と入出力、変数一覧、`moved.tf`の注意点、バックエンド方針、実施順序と判定基準 |
| [docs/fde/DELIVERY-BLOCKERS.md](./fde/DELIVERY-BLOCKERS.md)(新規) | 納品ブロッカー台帳。DB-01〜09を固定IDで管理し、根拠・影響・対処・状態を記録 |
| [docs/README.md](./README.md) | 目次に`docs/23`行と**`fde/`ディレクトリ行**を追加(`fde/`は前セッションで作成されたが目次に未掲載だった) |
| [docs/00-handoff.md](./00-handoff.md) | 本§19。§18.2の注記、§18.4の見出し、§18.8-1に訂正への参照を追記 |

### 19.6 実装したもの(フェーズ2、コード部分は完了)

`infra/` を新設した。移行元 `terraform-playground-pattern4/` と `terraform/` は**一切変更していない**(ロールバック参照として残置)。

```
infra/
  modules/        network parameters mcp-server-ecs auth dcr api-gateway edge-waf mcp-server-agentcore
  environments/   playground primenumber quick     (main.tf / variables.tf / outputs.tf は3環境で同一)
  scripts/        generate-moved.py
  Makefile
```

**検証結果(すべて通過)**

| 項目 | 結果 |
|---|---|
| `terraform fmt -recursive -check infra/` | 通過 |
| `terraform validate` | **3環境とも Success**(Terraform 1.15.8) |
| 依存グラフ | **109辺、`Cycle:`エラー無し**。§19.3 の「循環は存在しない」を実測で確証 |
| `moved.tf` | 73ブロック + 据え置き2 = state の75リソースと完全一致 |
| ルート `outputs` | 全14件を名称そのままで再現(うち8件は ecspresso 互換契約) |
| 移行元ディレクトリ | 未変更 |

**計画から変えた3点**(実装中に判明した事実による)

1. `secrets` モジュールを **`parameters` に改名**。サンドボックスの権限規則が `./secrets` を認証情報ディレクトリとみなして読み書きを遮断するため。名前としても実態(SSM Parameter Store + KMS)に合う。
2. 3環境で `main.tf` / `variables.tf` / `outputs.tf` を**同一ファイルにし、差分を `tfvars` だけに閉じ込めた**。DB-01(`terraform/` が1世代古い)の原因は環境ごとに別の `.tf` を持っていたことなので、共有すれば同じドリフトが**構造的に起きえなくなる**。世代差は `enable_dcr` / `enable_edge_waf` / `enable_local_pool` の3トグルで表す。
3. 計画の8モジュールが `ecr.tf` と `dynamodb.tf` を取りこぼしていた。ECR は `mcp-server-ecs` へ、DynamoDB テーブルは**環境ルート**へ(環境ごとに存在有無と管理主体が異なり、本番は41ユーザーの実データで Terraform 管理外)。

**`resource_suffix` はグローバルに適用してはならない**(3エージェントが独立に検出)。接尾辞が付くのは `cognito.tf` / `dynamodb.tf` / `ssm.tf` の3ファイルだけで、`vpc` / `ecs` / `alb` / `ecr` / `apigateway` / `lambda` / `cloudfront_waf` には付かない。一律に渡すと IAM ロール名・SG 名・TG 名が変わり **destroy/create** になる。

**`tfvars` は `terraform.tfvars.example` として versioned した**。`.gitignore:6` が `*.tfvars` を除外する既存方針に従っている。使うときは `cp terraform.tfvars.example terraform.tfvars`。**移行に必須の `resource_server_identifier` の実値**(`https://2a5r57wfoa.execute-api.ap-northeast-1.amazonaws.com/mcp`、state から読み出し)もここに入っているので、次セッションはこのファイルから始められる。

### 19.7 セッション終了時点の状態

| 項目 | 状態 |
|---|---|
| ブランチ | `feature/week6-terraform-modularization`(`main`から分岐、未push) |
| `infra/` | **作成済み**。3環境とも `validate` 通過。`plan` は未実行 |
| AWS環境 | **今回も一切変更していない**。`plan`/`apply` とも未実行 |
| `terraform-playground-pattern4/` / `terraform/` | **未変更** |
| `infra/modules/secrets/` | **要削除**。`parameters` へ移行済みだが、権限規則で Claude が削除できない(§19.8) |

### 19.8 ユーザーの操作が要る事項(新規)

- **`infra/modules/secrets/` の削除**。`parameters` として作り直したので不要だが、サンドボックスの権限規則が `./secrets` を遮断するため Claude は読むことも消すこともできない。commit には含めていない。`rm -rf infra/modules/secrets` で削除するか、`/sandbox` で `./secrets` の deny 範囲を狭めること(この規則は今後のセッションでも同じ摩擦を起こす)。

### 19.9 次回セッションの着手順

1. **`plan` の実行**(フェーズ2の残り)。`make init ENV=playground` の前に、まず **backend 用 S3 バケットの作成**(DB-05)が要る。手順は `infra/environments/playground/backend.hcl` のコメントに書いてある。
   - 受け入れ基準は `0 to add, 0 to change, 0 to destroy`。例外は `aws_api_gateway_deployment.metadata` の1件のみ
   - `aws_cloudfront_distribution.edge` に `-/+` が出たら**即中断**
   - **`nat_ami_id` を先に固定すること**。`null` のままだと `data.aws_ami` が最新 AMI を拾い、NAT インスタンス2台の置き換えが提案される(§17 記録済みのドリフト)。これを受け入れ基準の妨げにしない
   - `resource_server_identifier` が `terraform output` の値と一致することを**適用前に**確認する
2. **設計文書F1〜F6**([docs/23 §5](./23-internal-weekly-verification-plan-week6.md))を `docs/fde/` へ。**F5(`WWW-Authenticate` / RFC 9728 の否定的知見)を最優先**。現在 `cloudfront_waf.tf:494-512` のコメントにしか存在せず、そのファイルは再構成で役目を終える(モジュール側にはコメントごと移設済みだが、独立した文書にしておく価値が高い)
3. **primenumber の `resource_server_identifier` の実測**。`terraform/` は一度も apply されておらず state が無いため、`terraform.tfvars.example` は `CHANGEME` のまま。AWS 上の実リソースから確認が要る
4. フェーズ3: AWS環境の整理とバージョニング。**削除は必ず事前確認を取る**(playgroundはtrocco・PetStore等と共用)
5. フェーズ4: CI/CD方針の文書化(`docs/fde/CICD-DESIGN.md`)
6. フェーズ5: 細粒度権限管理のECS側実装(§18.6)
7. フェーズ6: FDE成果物の残り(ADR、DELIVERY-REQUIREMENTS、RUNBOOK、RISK-REGISTER)

### 19.8 人の判断待ち項目(§18.9から継続、**いずれも未解消**)

コード作業では解消できない。

- **A1 本番の401バグの共有**(数週間滞留中)。`fix/production-audience-config-proposal`は`main`にマージ済みだが、**本番担当者への共有は未実施**。CognitoがRFC 8707の`resource`に対応と判明したため「修正案」と「`resource`指定前提案」の両論提示が正確。なお§19.4のとおり`terraform/apigateway.tf:91-95`に当時の失敗記録がコメントで残っている
- **A2 Claude Code / Claude.aiからの自己登録E2E**。ブラウザ操作が必要で未実施
- **フェーズ3の削除候補**。実行前に必ず確認を取る
- B1〜B5、C1〜C3(§18.9)

### 19.9 学び

- **引き継ぎメモの「難所」は、着手前に実コードで裏を取る価値がある**。§18.8が最大の障害として名指しした循環参照は存在せず、根拠として引用された行番号は1世代古いディレクトリのものだった。一方で本物の循環は別の場所(`random_password.origin_verify`)にあり、こちらは指摘されていなかった。調査に半日かけたことで、無意味なカスタムドメイン先行導入を回避できた
- **「〜が直書き」のようなブロッカー記述は、書かれた時点の事実でしかない**。DB-06は別トラック(Week5のDCR対応)で既に解消されていたが、ブロッカー一覧はそれを知らないまま残っていた。台帳化して状態欄を持たせたのはこのため
- **数え間違いは作業量の見積もりを直撃する**。59と75では`moved`ブロックの手間が3割違う。stateのようなものは「読んだ記憶」ではなく毎回パースして数えること

---

## 20. docs命名のinternal/external化と納品ヒアリング準備(2026-09-15〜16実施)

このセッションは3つの並行作業からなる。(A) Week5レポート([22](./22-internal-weekly-verification-report-week5.md))への図の追加、(B) QUICKへの納品を見据えたリポジトリ棚卸しとdocs命名の整理、(C) 納品ヒアリングシートの新規作成。**すべてコード作業のみで、AWS環境・Terraform stateへの変更は一切無い。**

### 20.1 Week5レポートへの図の追加

Week5レポート([22-internal-...](./22-internal-weekly-verification-report-week5.md)・[22-external-...](./22-external-weekly-verification-report-week5.md)、共に旧`week5.md`/`week5-client.md`)に、ユーザーから「アーキテクチャやシーケンス、WAFのテスト結果を図示させる」という指示を受けて8個のMermaid図を追加した。

| 追加した図 | 内容 |
|---|---|
| DCR接続フロー(sequenceDiagram) | Claude→受付窓口→登録→認証→再接続の一連の流れに、今週の修正6点(F1〜F6)の位置を注記 |
| ALB案 vs CloudFront案の比較(flowchart、subgraph2枚) | なぜALB配下だと送信元IPが集約されるかを構造的に図示 |
| WAFルール優先度の評価順(flowchart LR、subgraph4グループ) | カスタム→レートベース→マネージド→観測の順で評価され、終端すると後続が評価されないことを図示。**初版はflowchart TBで縦に長く、PDFでページ境界をまたいで分断される問題があり、LR+subgraphへ組み替えて解消した** |
| Count→Block切替の経緯(flowchart) | ALBでのCount観測→IP集約の発見→CloudFrontへ配置→誤検知の観測→調整→Block切替、という時系列 |
| 45パターンの内訳(flowchart) | 攻撃32件(遮断16/他層拒否5/記録のみ11)と正常系13件の内訳 |
| CloudFront Functionsの200/401応答比較(sequenceDiagram、`rect`で色分け) | オリジンのエラー応答時にviewer-response関数が実行されない制約を実測ベースで図示 |

**内部版(22-internal)には、図とは別にユーザー指摘で「用語解説」表(冒頭、TL;DR前)も新規追加した。** DCR/RFC 7591等/WAF/Web ACL/`terminatingRuleId`/VPC Link/ENI/Managed Login/ExplicitAuthFlows/CloudFront Functions/Lambda@Edge/CIMD/FISC等、レポート内で使う技術用語15項目を解説する。外部版(22-external)には元々平易な用語解説があったが、内部版には無かった(過去のレポート全般で「用語解説は外部版のみ」という慣習になっていたため、指摘を受けて内部版にも技術者向けの版を追加した形)。

**PDF化して全ページを目視確認済み**(サブエージェント2回、`pdftoppm`で全ページ画像化→Read)。図の重なり・生テキスト露出・文字化け・右端切れ、いずれも無し。WAFルール優先度図のページ分断も解消を確認。

### 20.2 リポジトリ棚卸しとdocs命名のinternal/external化

ユーザーから「QUICKのGitHubリポジトリに納品するため、リポジトリの整理とREADMEへのファイル一覧、納品対象/内部限定の仕分けをしたい」という依頼を受け、まず調査専用エージェント(general-purpose、編集禁止)でリポジトリ全体を棚卸しした。主な発見:

- **`infra/`が唯一の納品対象Terraformであり、`terraform/`と`terraform-playground-pattern4/`は旧世代・残置**(前セッション§19で作成した通り)。README等にこの位置づけの明記が無いと、納品先が誤って旧世代を使う事故リスクがある
- **`terraform/ssm.tf:35,39`にKMS暗号文がコミットされている**。primenumberのKMSキー紐付きで、別アカウントでは復号不能([DB-04](./fde/DELIVERY-BLOCKERS.md#db-04-kms暗号文が特定アカウントの鍵に紐づく)で既知)
- **スクリプト・Terraformにアカウントの直書きが多数**(`grep`で洗い出し済み。棚卸し結果は本セッションのAgent実行ログに詳細あり、要約はこの節)
- **平文パスワード/トークン/APIキーの直書きは0件**。ただしアカウントID・エンドポイントURL・Cognito Pool ID等は複数箇所に残る
- **PDF 9本(計25MB)がリポジトリの大半を占めるgit容量**。ソースはコミットされているが、tfstateの誤コミットは無し(`.gitignore`が機能している)

この調査結果とユーザーの追加指示(「PDFはローカル保存にするのでアントラック」「internal/externalプレフィックスに」)を受けて、以下を実施した。

**PDFのgit追跡除外**:`git rm --cached`で9本を除外し、`.gitignore`に`*.pdf`を追加。ローカルのファイル自体は削除していない。

**docsレポートのリネーム**: `docs/README.md`目次にある番号付きレポート(00・RESUME_PROMPTを除く01〜23の28ファイル、対応PDFも同様)を、`NN-<内容>.md`→`NN-internal-<内容>.md`、`NN-<内容>-client.md`→`NN-external-<内容>.md`に一括リネームした(`git mv`)。狙いは「内部限定/対外提出」をファイル名自体で自明にすること。適用範囲は**docsのレポートファイル名のみ**(ユーザーに確認済み。トップレベルディレクトリ(`infra/`・`terraform/`等)へのプレフィックス付与は見送り)。

リネームに伴い、全docsファイル・`docs/README.md`・`CLAUDE.md`・`scripts/`配下のPythonスクリプト・`infra/modules/mcp-server-agentcore/README.md`・`infra/scripts/generate-moved.py`・`web-demo/README.md`内の相互参照(Markdownリンク、コメント中のファイルパス言及)を機械的に置換した。リンク切れチェック(project標準のPythonワンライナー)で0件を確認済み。

`docs/README.md`の目次テーブルに「区分」列(internal/external)と、区分の意味を説明する注記を追加。「図の再生成方法」節にPDFがgitignore対象である旨も追記した。

**このリネームはリポジトリ全体の納品可否の仕分けそのものではない**(README上の注記にも明記した)。ディレクトリ単位の納品可否判断は§20.3のヒアリングシートに委ねている。

### 20.3 納品ヒアリングシートの新規作成

[docs/fde/DELIVERY-HEARING-SHEET.md](./fde/DELIVERY-HEARING-SHEET.md)を新規作成した。ユーザーからの依頼は「検証はprimenumber内部のAWSリソースで行っているが、納品物は顧客(QUICK)環境になるため、ヒアリングすべき事項と、開発/顧客環境で変える部分を整理したい」というもの。

構成は5節: (1) ヒアリング事項24項目をA〜G群に分類(最優先5項目を明示。特に**カスタムドメインの有無**が`resource_server_identifier`を決め、これは後から変更すると発行済みクライアントのスコープが失われるため最優先)、(2) ヒアリングの進め方(3回に分けるflowchart)、(3) 開発/顧客環境の差分一覧(そのまま持ち込むと壊れるもの5点、`terraform.tfvars`で変更する項目一覧、コード側で変更が必要なもの)、(4) ヒアリング前にこちらで完了させておくべき作業、(5) ヒアリングでも決められないまま残る論点。

既存の[DELIVERY-BLOCKERS.md](./fde/DELIVERY-BLOCKERS.md)(「別のAWSアカウントで動かせるか」を問う台帳)とは責務を分けており、本シートは「QUICK側の意思決定が要る事項」を問う。`docs/README.md`のfde行にもこのファイルへのリンクを追加した。

### 20.4 セッション終了時点の状態

| 項目 | 状態 |
|---|---|
| ブランチ | `feature/week6-terraform-modularization`(§19から継続、**未push**) |
| 変更内容 | すべて**未コミット**(ユーザーから明示のコミット指示が無かったため。§19までの`infra/`新設は既に別コミットとして入っている)。**このセッションではコミットしない方針**でユーザーと合意し、終了した |
| AWS環境 | 変更無し。`plan`/`apply`とも未実行 |
| `infra/modules/secrets/` | **§19.8から持ち越し、未解消**。サンドボックスの権限規則で今回も削除できていない |

### 20.4-1 【重要】並行セッションによるコンフリクトの懸念(引き継ぎ時に発覚)

このセッションの終了直前、**同じリポジトリで別のセッションが並行してリポジトリ整理を行っており、そちらも未コミットである**ことが判明した。`ListAgents`で確認したところ、このマシン上に以下のピアセッションが存在する。

| セッション | 開始 | 備考 |
|---|---|---|
| quick-agentcore-poc-b7 [273871] | 9時間前 | - |
| quick-agentcore-poc-34 [c9476c] | 23時間前 | **ユーザーによれば「昨日作業していたセッション」= リポジトリ整理を行っている本人** |

**このリポジトリには`git worktree`が1つしかない**(`git worktree list`で確認済み)。つまり全セッションが**同一の作業ディレクトリ・同一のブランチ(`feature/week6-terraform-modularization`)を共有**しており、互いの未コミット変更がファイルシステム上でそのまま衝突しうる。worktreeによる分離は行われていない。

**次回セッション再開時に必ず確認すること**:

1. **再開直後にまず`git status`を取り、本メモの§20.4に記載した変更内容(28ファイルのリネーム、PDF除外、`docs/README.md`・`docs/00-handoff.md`更新、`docs/fde/DELIVERY-HEARING-SHEET.md`新規)と一致しているか照合する。** 一致しない場合、quick-agentcore-poc-34セッション側で追加の変更が入っている可能性が高い
2. **一致しない場合は、いきなり上書き・`git checkout`・`git stash`等をせず、差分の由来を先に特定する。** 本セッションの変更は§20.1〜20.3に全て記録済みなので、それと差分を取れば「本セッションの変更」と「もう一方のセッションの変更」を切り分けられる
3. **もう一方のセッション(quick-agentcore-poc-34)がリポジトリ整理として具体的に何をしているかは、本セッションでは未確認のまま終了した。** ユーザーに直接確認するか、`ListAgents`→`SendMessage`でそのセッションに状況を尋ねることを推奨する
4. **コミットは両セッションのうちどちらか一方が完了・整理してから、1回にまとめて行うことを推奨する。** 同じ内容(docsリネーム等)を両セッションが別々にコミットしようとすると、片方が無駄になるか、コンフリクトが発生する

**ユーザーへの申し送り**: 本セッションでは意図的にコミットを行わず終了した。もう一方のセッション(quick-agentcore-poc-34、リポジトリ整理中)と作業内容が重複している可能性があるため、**次にこのリポジトリで作業を再開する際は、まずどちらのセッションの変更を正とするかをユーザーに確認すること**。

### 20.5 次回セッションの着手順

1. **今回の変更をコミットするかどうかの確認**。リネーム(28ファイル+PDF)・`.gitignore`・`docs/README.md`・`docs/00-handoff.md`・`docs/fde/DELIVERY-HEARING-SHEET.md`(新規)・スクリプト内リンク修正が未コミットのまま残っている。`git status`で全量を確認してからコミットすること
2. **`infra/modules/secrets/`の削除**(§19.8から継続)。`rm -rf infra/modules/secrets`をユーザー側で実行するか、`/sandbox`で`./secrets`のdeny範囲を調整する
3. **§19.9の着手順(plan実行、backend用S3バケット作成等)は未着手のまま**。フェーズ2の残りとして引き続き有効
4. **納品ヒアリングの実施**。§20.3のヒアリングシートを使い、特に最優先5項目(H-A1, H-A3, H-C1, H-D1, H-E1)から着手する。回答が得られ次第、シートに追記し`infra/environments/quick/terraform.tfvars`へ反映する
5. **リポジトリの納品対象/内部限定の仕分け**は、ヒアリング結果を待たずに着手可能な部分がある(§20.2の棚卸し結果、`terraform/`・`terraform-playground-pattern4/`・`web-demo/`・`docs/fde/`を内部限定とする方針など)。ディレクトリ単位でのREADME整備や`.gitattributes`的な仕分けは次回の課題として残っている

### 20.6 学び

- **「用語解説は対外版だけに付ける」という過去の暗黙の慣習は、内部版の読者(エンジニア以外のレビュアー含む)にとって不親切になりうる**。内部版でも、その回だけ登場する専門用語(RFC番号、AWSサービス固有語)は解説した方が良いというフィードバックを得た。今後の内部レポートでも、初出の専門用語が多い回は用語解説の追加を検討する
- **ファイル名のリネームは「見た目の変更」で済まず、相互参照の全数更新とリンク切れチェックが必須**。今回は28ファイル+スクリプト9本に波及した。`git mv`後に機械的な文字列置換とリンク切れチェックのワンライナーを流す、という手順を踏まないと参照だけが古いまま残る

# セッション引き継ぎメモ(2026-08-20時点)

> **この章で分かること**
> 前回セッションで何をどこまでやったか、次に何をすべきか、そして再開する上で最初につまずきそうな点(PATH、SSOトークン、サンドボックス制限)を先回りしてまとめる。次回セッションはまずこのファイルを読んでから作業を再開すること。

## 1. 状況サマリー

来週水曜のクライアント報告に向けて、quick-mcp-poc MCPサーバーを (3) AgentCore Runtime単体、(4) API Gateway + ECS(既存構成) の2パターンでホストし、比較検証している。

**追加スコープ(2026-08-17に合意)**: このサービスは単発PoCではなく、**金融機関向けに課金制で外販するリモートMCPサービス**として展開する狙いがある。そのため通常のエンタープライズ向けリモートMCPより難易度が高く、マルチテナント分離・ネットワーク閉域性(PrivateLink)・監査ログ・コンプライアンス認定(FISC安全対策基準等)を重点的に比較検証する追加タスクを実施した → [05-security-compliance-verification.md](./05-security-compliance-verification.md)

**現時点で完了しているもの**(すべて`docs/`配下に成果物あり):

- [x] パターン3(AgentCore Runtime)のデプロイ・疎通検証 → [03-agentcore-runtime-verification.md](./03-agentcore-runtime-verification.md)
- [x] パターン4(API Gateway + ECS)の稼働確認(既存本番相当環境、新規デプロイ不要だった) → [04-ecs-apigateway-verification.md](./04-ecs-apigateway-verification.md)
- [x] 両パターンの構成図(AWS公式アイコン)・Mermaidシーケンス図・プロコン比較 → [01-architecture-comparison.md](./01-architecture-comparison.md)
- [x] コストシミュレーション(月額試算・損益分岐点) → [02-cost-simulation.md](./02-cost-simulation.md)
- [x] 金融グレード外販サービスとしてのセキュリティ・コンプライアンス比較検証(マルチテナント分離・閉域網・監査ログ・コンプライアンス認定・FISC対応) → [05-security-compliance-verification.md](./05-security-compliance-verification.md)。机上調査中心+一部実機確認(playgroundのRuntime設定スキーマ、terraformコードレビュー)で実施。**重要な発見: 現状構成はAgentCore・ECSどちらもPrivateLink/VPCエンドポイント未対応であり「閉域網」を訴求するには追加実装が必要**。ユーザーの指示により、この検証は現状判明している範囲で完了とし、実機でのPrivateLink疎通検証等は次回以降のフォローアップ扱い
  - 「字ばかりで頭に入らない、オライリー本のように図表を多用してほしい」とのフィードバックを受け、TL;DR、AWS構成図2種(`docs/images/pattern3-vpc-privatelink-target.png`, `docs/images/pattern4-vpc-endpoint-target.png`、いずれも未検証の構想図)、Mermaid図(テナント分離フロー、コンプライアンスgantt、パッチ責任分界点、FISC構造)を追加する全面改訂を実施
  - その後「絵文字禁止・出典に本文中インラインリンクを・査読と修正はサブエージェント分離で」というフィードバックを受け、**査読専用エージェント(Explore、編集不可)→修正専用エージェント(general-purpose)の2段階構成**で対応。査読エージェントは1回目mermaid-cliインストールで600秒スタックし失敗、制約を明確化して再実行し成功。発見した問題: `subgraph AgentCore Runtime`のクォート漏れ(Mermaid構文エラーで図が描画不能)、エッジラベル内`\n`(Mermaid非対応)、ganttのtitle行のコロン(パース破損リスク)、quadrantChartのGitHub描画崩れ懸念、絵文字36箇所以上、本文中の出典インラインリンク不足17箇所。修正エージェントが全て適用し、絵文字ゼロ・subgraph修正・quadrantChart削除・出典リンク追加を確認済み(自分でも`grep`と全文読み直しで再確認済み)
  - **学び**: サブエージェントにMermaid検証をさせる際は「一時ファイル作成もダメ」と厳格に指示すると`mmdc`インストールで無限に粘って失敗することがある。「$TMPDIRへの一時ファイル作成は可、対象ファイルの編集のみ禁止」のように制約を具体的に切り分けると成功する

**未着手・今後の課題**(ユーザーへの確認が必要な場合あり):

- [ ] パターン1・2(AgentCore Gateway経由)の検証 — 今回スコープ外として合意済み。着手するかはユーザー確認が必要
- [x] **パターン3のレイテンシ実測(コールドスタートの影響)**(2026-08-21実施)。詳細は[03-agentcore-runtime-verification.md](./03-agentcore-runtime-verification.md)。**意外な発見: アイドル0秒〜16分(セッションタイムアウト超過後)まで一貫して約6秒で、コールドスタートによる有意な差は観測できなかった**。約6秒はAWS側のコンテナ起動待ちではなく、MCPサーバー実装がリクエストごとに新しいセッションを生成する設計による可能性が高い(推測、コード側の詳細プロファイリングは未実施)
- [ ] パターン3のスケーラビリティ実測(同時リクエスト負荷試験)
- [x] パターン3の本番グレード認証(Custom JWT Authorizer導入)の検証 → 下記の通り完了
- [x] **Claude Code経由でのOAuthリモートMCP接続検証**(2026-08-18実施)。ECS+API Gatewayとの詳細比較・構成図・シーケンス図・認証フロー差分・接続手順・6つのハマりどころを整理した独立ドキュメント → [06-agentcore-oauth-claude-code-verification.md](./06-agentcore-oauth-claude-code-verification.md)。作業ログの詳細は本ファイル末尾「9. Claude.ai連携のためのCustom JWT Authorizer設定」を参照
- [x] **Claude.ai Web版での疎通確認**(2026-08-20、ユーザーが実機で確認済み)。Runtime version 6での`allowedScopes`追加(§9末尾の追記参照)が功を奏した。Claude Desktopでの疎通はまだ未確認
- [x] **クライアント(QUICK様)向けレポートの作成・査読・PDF化**(2026-08-19〜20実施)。詳細は本ファイル「10. クライアント向けレポートの作成とPDF化」を参照 → [06-agentcore-oauth-claude-code-verification-client.md](./06-agentcore-oauth-claude-code-verification-client.md) / 同PDF
- [x] **汎用MCPクライアント(boto3/Claude Code/Claude.aiに非依存)からの疎通検証**(2026-08-21実施)。詳細は[03-agentcore-runtime-verification.md](./03-agentcore-runtime-verification.md)。Cognito認可コード+PKCEフローのみで`invocations`エンドポイントを直接HTTPS呼び出しし、MCPプロトコル層・JWT認証・DynamoDB認可チェックまで正常動作することを確認
- [x] **コスト再検討(実測レイテンシを踏まえた見直し)**(2026-08-21実施)→ [02-cost-simulation.md](./02-cost-simulation.md)。壁時計レイテンシ(約6秒)とAgentCore課金対象の「アクティブCPU時間」は別物である旨を明記し、既存の保守的な試算(1リクエスト=1秒)は変更せず維持。正確な値はAWS Cost Explorerでの実測を推奨。VPCモード(閉域網対応)にする場合のECR Interfaceエンドポイント追加コストも明記
- [x] **WAF導入可否の実機検証**(2026-08-21実施)→ [05-security-compliance-verification.md §4.5](./05-security-compliance-verification.md)。AgentCore Runtime自体への直接アタッチは不可だが、CloudFront+WAFv2の代替構成をplaygroundに実機構築し、正常リクエストの通過・悪意あるパターンの403ブロックの両方を確認
- [x] **本日の検証内容をまとめたレポート作成**(2026-08-21実施、06番と同フォーマット)→ エンジニア向け[07-vpc-waf-cost-verification.md](./07-vpc-waf-cost-verification.md) / クライアント向け[07-vpc-waf-cost-verification-client.md](./07-vpc-waf-cost-verification-client.md)。査読専用エージェント(Explore、編集不可)→修正専用エージェント(general-purpose)の2段階レビューで、Mermaid構文(`\n`→`<br/>`未変換、`<JWT>`のHTMLタグ誤認識リスク)、太字の乱用、表記ゆれ(壁時計レイテンシ/Interfaceエンドポイント)、クライアント向け版の文体不統一(敬体/常体混在)・「実機」という不自然な表現を修正済み
- [x] **追加検証5項目の実施**(2026-08-25実施): (1)疎通検証Webアプリ(Lambda Function URL、`quick-mcp-poc-web-demo`)、(2)ECS+API Gatewayをplaygroundに複製し応答時間を実測(約0.2〜0.3秒、AgentCore Runtimeの約6秒より約20倍速い)→**本番相当terraformのJWT Authorizer`audience`設定に、正当なトークンでも常に401になる不具合を発見・修正案を実機確認**(要本番共有、最優先課題)、(3)VPCモードのTerraformコード例(`docs/terraform-examples/agentcore-vpc-mode/main.tf`)、(4)VPCモード+WAF込みの1ヶ月コスト試算(損益分岐点が約610万→約77万リクエスト/月に低下)、(5)DCR移行の手順・コスト試算。両レポートの文章も「クライアント担当者(kekekenta氏)から」等の人物名を削除し「問いに対する検証」という位置づけに統一
- [x] **AWSインフラ図の追加**(awsdac、2026-08-25実施): `docs/images/agentcore-vpc-mode-verified.png`(VPCモード実機構成)、`docs/images/agentcore-waf-cloudfront.png`(WAF/CloudFront構成)、`docs/images/agentcore-webdemo-architecture.png`(疎通検証Webアプリ構成)を新規作成し両レポートに埋め込み。既存の`pattern4-architecture.png`もECS比較セクションで再利用
- [x] **PDF化パイプラインをリポジトリに永続化**([scripts/render-pdf.sh](../scripts/render-pdf.sh))。前回セッションではscratchpad依存で消えていたが、今回`npm install mermaid`のESMバンドル(`mermaid.esm.min.mjs`)をfile://経由でChromeに読み込ませる方式で再構築し、スクリプト化した。**注意点**: Chromeで`file://`オリジンからESモジュールをimportするには`--allow-file-access-from-files`フラグが必須(無いとCORSエラーで失敗する、無言でmermaidが生テキスト表示になるだけで気づきにくい)。クライアント向け版のPDFを[docs/07-vpc-waf-cost-verification-client.pdf](./07-vpc-waf-cost-verification-client.pdf)として保存済み(pdftoppmで複数ページを目視確認済み)
- [x] **検証リソースへのリンク集を両レポートに追加**。エンジニア向けはAWSコンソールの深リンク一式、クライアント向けは疎通検証Webアプリの公開URLのみ(クライアントはplaygroundアカウントにログインできないため)
- [x] **「次週の検証アクションプラン」章を両レポートの最後に追加**(本番audienceバグの共有を最優先、PrivateLink実機検証・WAF運用体制・コスト実測・DCR判断が続く)

### 追加調査(2026-08-26実施)

- [x] **`client_credentials`グラント(人手を介さないM2M接続)の実機検証**。新規Cognito App Client(`quick-mcp-poc-m2m-test`、client_id: `7gtknlcn9imrhihetq3aauojaj`、confidential、`allowed_oauth_flows=client_credentials`、scope=`mcp/invoke`)を作成し、Runtimeの`allowedClients`に追加(version 9)。**認可レイヤー(Custom JWT Authorizer)は問題なく通過するが、アプリ層(DynamoDB認可チェック)は`sub`=クライアントID自体に対応するレコードが無いため403になる**ことを確認。DynamoDBに`USER#7gtknlcn9imrhihetq3aauojaj`のレコードを追加(サービスアカウント扱い)したところ解消し、正常動作を確認済み。本番展開時はこの「サービスアカウント登録」運用が必要になる
- [x] **6秒の内訳を実機で特定**。CloudWatch Logs(`/aws/bedrock-agentcore/runtimes/quickMcpPocVerification-Aoo0d23yyj-DEFAULT`)を調査し、**リクエストごとに新しいコンテナが起動している**ことを確認(1ストリーム=1回の起動ログのみ)。ストリーム作成〜起動完了ログまでの間隔は約30サンプルで3.78〜4.07秒(平均約3.9秒)と非常に安定。6秒のうち約65%はこのコンテナ起動コストと推定([07-vpc-waf-cost-verification.md §2.2.1](./07-vpc-waf-cost-verification.md)参照)
- [x] **VPCモード切り替え後、CloudWatch Logsへのログ配信が完全停止していることを発見**(2026-08-21 08:37の切り替え以降、新規ログストリームが0件)。`com.amazonaws.<region>.logs`のVPCエンドポイントを作成していないためと推定。**未対応**、次のフォローアップ課題
- [x] **AWS Cost Explorerでの実コスト確認を試みたが、playgroundアカウント全体(他の検証者のAgentCoreエージェント含む)の合算しか取得できず、本Runtime単体を分離できないと判明**。代わりにCloudWatchメトリクス(`AWS/Bedrock-AgentCore`名前空間、dimensionに`Resource=<RuntimeのARN>`を指定)で本Runtime単体の`CPUUsed-vCPUHours`/`MemoryUsed-GBHours`/`Invocations`/`Duration`が取得できることを確認。ただし2026-08-17〜26の期間で総呼び出し回数が**6,414回**(想定より大幅に多い。Claude Code等のMCPクライアントによるバックグラウンドの定期接続が疑われるが未確定)、Duration最大値が130.6秒という外れ値もあり、**この実測値は今回レポートには反映せず**、契約情報として保留(ユーザー判断)。単価自体(vCPU $0.0895/時間、メモリ$0.00945/時間)は確定値と一致することを確認済み
- [x] `docs/02-cost-simulation.md`に「内訳の算出根拠(サービス別)」を追加。既存試算が「0.25vCPU/0.5GBを1秒間」という仮定(Fargateと同サイズ)に基づくことを逆算で確認し、サービスごとの単価根拠を明記
- [x] **AgentCore RuntimeのVPCモード切り替えの実機検証**(2026-08-21実施)。詳細は[05-security-compliance-verification.md §4.1.1](./05-security-compliance-verification.md)。**インバウンド(`invocations`エンドポイント)への影響なし、アウトバウンド(DynamoDB Gateway経由のVPC内リソースアクセス)は正常動作**を確認。クライアント(kekekenta氏)からの「AgentCore RuntimeはVPCに配置できないのでは」という質問への回答の裏付けが取れた
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
| AgentCore Runtime | `arn:aws:bedrock-agentcore:ap-northeast-1:883660531246:runtime/quickMcpPocVerification-Aoo0d23yyj`(version 10、`networkMode: VPC`、ステータス: READY。2026-08-31に`requestHeaderAllowlist`からの`x-cognito-sub`除去でversion 10に更新、[08番§1](./08-weekly-verification-plan.md)参照) |
| 検証用VPC | `quick-mcp-poc-verification-vpc`(`vpc-0df861e536fad4aab`, `10.99.0.0/24`)。2026-08-21、VPCモード検証のために新規作成。private subnet ×2(`subnet-0c56f317a1a50a6f4`, `subnet-004618218ccfed812`)、SG(`sg-04798ee8dda54dfc3`、自己参照443許可)、route table(`rtb-05c946adb3e34e90b`) |
| VPCエンドポイント | S3 Gateway・DynamoDB Gateway・ECR API Interface・ECR DKR Interface(いずれも上記VPCに作成。詳細は[05-security-compliance-verification.md §4.1.1](./05-security-compliance-verification.md)参照) |
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

詳細は[10-dcr-implementation.md](./10-dcr-implementation.md)参照。**注意**: この変更により`terraform-playground-pattern4`の認可方式はJWT型AuthorizerからLambda Authorizerに変わっている。次回セッションでこの環境を触る際は、`aws_apigatewayv2_authorizer.cognito`はもう存在しない前提で作業すること。

**重要な発見**: playground複製環境で実機検証したところ、本番相当`terraform/apigateway.tf`のJWT Authorizer`audience`設定(`aws_cognito_resource_server.mcp.identifier`を指定)は、Cognitoが実際に発行するトークンの`aud`/`client_id`(App Client ID)と一致せず、**正当な認証済みトークンでも常に401になる**ことが判明した。`audience`を`aws_cognito_user_pool_client.mcp.id`に変更したところ解消した。本番環境自体は書き込み禁止のため未確認だが、同一ロジックのため本番でも同様の可能性が高い。詳細は[07-vpc-waf-cost-verification.md §2.4](./07-vpc-waf-cost-verification.md)参照。**本番担当者への早期共有を推奨**。

**後片付けについて**: 上記のplayground複製一式(ECS/ALB/NAT×2/API Gateway/Cognito/DynamoDB/KMS等、59リソース)は継続的に時間課金が発生する(ECS Fargate常時起動、ALB、NATインスタンス×2等で月額約$46相当、02-cost-simulation.md参照)。**2026-08-25、ユーザー判断により「しばらく残す」こととした**(追加の確認・再検証に使う可能性があるため)。削除する場合は`cd terraform-playground-pattern4 && aws ecs delete-service --cluster quick-mcp-poc-cluster --service app --force --profile quick-agentcore-poc-playground --region ap-northeast-1 && terraform destroy`の順で実施すること。

IAMポリシーの元ファイルは `docs/agentcore-iam/*.json` に保存済み。本番アカウント(620369151795)への適用時は、アカウントIDとECRリポジトリ名を置換する必要がある(詳細は各JSONファイル、および[01-architecture-comparison.md](./01-architecture-comparison.md)参照)。

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

詳細な仮説・根拠・切り分け手順は[06-agentcore-oauth-claude-code-verification.md § 7](./06-agentcore-oauth-claude-code-verification.md)に記載。

**次にやるべきこと**(2026-08-20時点で更新):
- [x] ~~Web/Desktopのテスターに、version 6の状態で再度接続を試してもらう~~ → **2026-08-20、Claude.ai Web版での疎通をユーザーが確認済み**。version 6の`allowedScopes`追加が仮説通り原因であったことが裏付けられた(詳細な再現手順・エラー文言の記録は今回は取得していない。必要であれば次回テスターに改めて確認)
- [ ] Claude Desktopでの疎通確認(Web版は確認済みだが、Desktop版は未確認のまま)
- [ ] それでも将来的に別の失敗が出る場合は、06ドキュメント§7.3の副次仮説(OAuthディスカバリーのホスト解決バグ)を調査する

## 10. クライアント向けレポートの作成とPDF化(2026-08-19〜20実施)

### 背景

06番ドキュメント(`06-agentcore-oauth-claude-code-verification.md`)はエンジニア向け(再現・引き継ぎ用)に書かれていたため、QUICK様への説明に使うにはそのままでは不適切という判断から、読者をクライアントに絞った別版を作成する指示を受けた。

### 実施内容

1. **クライアント向け版を新規作成**: `docs/06-agentcore-oauth-claude-code-verification-client.md`。エンジニア向けの元ファイルは引き継ぎ・再現用としてそのまま残し、上書きはしていない。用語解説(MCP/OAuth/JWT/Cognito/スコープ等)を追加し、「ハマった6つの問題」のような内輪向けの言い回しを対外報告らしい表現に調整。`docs/README.md`のドキュメント一覧には**まだ追記していない**(次回セッションでの対応候補)。
2. **PDF化パイプライン**: pandoc(`-f gfm -t html5 --standalone`)→ Python後処理(mermaidブロックの`<code>`タグ除去、画像相対パスを`file://`絶対パスに変換、`mermaid.initialize`スクリプト注入)→ ヘッドレスChrome(`--headless=new --print-to-pdf`)、という既存パイプラインを流用。**このパイプラインの中間ファイル(`header.html`・後処理スクリプト)はセッション専用のスクラッチパッド(`/private/tmp/claude-501/.../scratchpad/pdf/`)に置いており、次回セッションでは消えている。** 再現する場合は本セクションの記述を元に組み直すこと(pandocコマンド・後処理内容は上記の通り。ヘッダー用CSSは日本語フォント指定+テーブル/コードブロックの見た目調整のみで特別な工夫はない)。
3. **クライアントから「AI生成だとバレる」との指摘**: 1回目のPDFで、`**「実際にAIクライアントから安全に接続できるか」**`のように太字記号がそのまま文字として表示される箇所があった。原因はCommonMarkの仕様で、`**`の直後/直前が全角カッコ「」などの記号だと太字として解釈されない(flanking rule)ため。この指摘を受けて査読・修正プロセスをサブエージェント化して実施:
   - **査読専用サブエージェント**(編集不可、`general-purpose`)に全文を読ませ、同種の太字崩れが他に3箇所残っていること、mermaid図の丸数字(④⑤⑥⑦)と本文表の番号(1〜4)の不一致、"実機"という浮いた専門用語(サーバーレス構成なのに"実機"は不自然)、用語の表記ゆれ(検証専用の環境/インスタンス/プール/認証基盤が混在)、太字の乱用(25箇所、平均10行に1回)などを洗い出させた
   - **修正専用サブエージェント**(別プロセス、`general-purpose`)に、指摘ごとの具体的な直し方(削除/言い換え/統一する用語)を指示して反映させた
   - 自分でも実際にpandoc変換したHTMLを正規表現でスキャンし、「太字が`<strong>`化されず`**`のまま残っていないか」を全数チェック(0件)。mermaidブロック内の崩れやすい記号(`<...>`のような角カッコ)も再スキャンし問題なしを確認
4. PDF再生成、1ページ目を画像で目視確認して完了 → `docs/06-agentcore-oauth-claude-code-verification-client.pdf`(13ページ)

### 学び(次回以降のPDF作成・査読作業に活用)

- **査読(read-only)と修正(edit可)は必ず別々のサブエージェントに分離する**。1つのエージェントに両方させると、指摘の見落としを自分でごまかしてしまうリスクがある。これは05番ドキュメントの査読でも踏襲した方針(本ファイル1章の学び参照)で、今回も有効だった
- CommonMarkの太字は、日本語の全角カッコ・句読点が`**`の内側に隣接すると崩れることがある。**査読の際は「太字構文自体が存在するか」ではなく「実際にpandoc等でレンダリングした結果に`**`が残っていないか」を機械的に検証するのが最も確実**(サブエージェントの目視レビューだけに頼らない)
- ヘッドレスChromeでの`--print-to-pdf`はこのサンドボックス環境だと素の状態では失敗する(`Failed to create socket directory`等、crashpadのソケット作成権限エラー)。`--user-data-dir`に書き込み可能な独自ディレクトリ(スクラッチパッド配下)を指定し、かつ`dangerouslyDisableSandbox: true`が必要だった。スクリーンショット系のコマンド(`--screenshot`)は同条件でもタイムアウトしやすく、PDF生成自体は成功していても`--screenshot`での目視検証は諦めることが多かった → 検証は「1ページ目をqlmanageでサムネイル化」+「pandoc出力HTMLの機械的スキャン」の組み合わせで代替するのが実用的
- PDF生成コマンドが2分のタイムアウトで打ち切られたように見えても、実際にはファイルが正常に書き出されていることがある(Chromeプロセスの終了処理が長引くだけ)。`ls -la`で生成物のタイムスタンプ・サイズを確認してから再実行の要否を判断すること

### 未着手・次回への申し送り

- [x] `docs/README.md`のドキュメント一覧・読み方フローチャートに、クライアント向け版(`06-agentcore-oauth-claude-code-verification-client.md`)への言及を追加する(2026-08-21実施。あわせて新規作成した07番ドキュメント一式も追記)
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

**追記(2026-08-31・同日、プランニング実施)**: 本セクションで合意した3項目について、実装前の設計・見積もり検証を実施した。結論を[08-weekly-verification-plan.md](./08-weekly-verification-plan.md)にまとめた。要点:

- **【重大・確認済み・修正済み】クロステナントなりすまし脆弱性を発見し即日修正(2026-08-31)**: AgentCore Runtimeの`requestHeaderConfiguration.requestHeaderAllowlist`に`x-cognito-sub`が含まれており、クライアントが送った値がそのままコンテナに転送されていた(ECS経路のような`overwrite:`保護がAgentCore経路には無かった)。実際に、正当なJWTを持ちながら`x-cognito-sub`ヘッダーで他テナントのsubを騙り、そのテナントとして認可される(成功レスポンスを得る)ことを実機で確認した。**対応**: `requestHeaderAllowlist`を`["Authorization"]`のみに変更(Runtime version 9→10、`update-agent-runtime`のみでコード変更・再デプロイ不要)。修正後、同じ手法でのなりすましが失敗する(Bearerトークンの`sub`に正しくフォールバックする)ことを再検証済み。詳細な経緯・図解は[09-cross-tenant-impersonation-finding.md](./09-cross-tenant-impersonation-finding.md)、要約は[08-weekly-verification-plan.md §1](./08-weekly-verification-plan.md)
- **12.1 DCR実装の見積もり改訂**: 3-5人日→**7-9人日**。現在のJWT Authorizerは`audience`に固定値しか設定できず、DCRで動的に増えるclient_idに対応するには**Lambda Authorizerへの置き換えが必須**と判明(当初見積もりに未反映)。ユーザー確認の上、この見積もりを受け入れて選択肢Bを継続する方針(詳細は08番§2)
- **12.2 応答時間チューニングのスコープ変更**: AWS公式ドキュメントにより、ステートレスMCPサーバーのままでも`Mcp-Session-Id`によるmicroVMスティッキーロイティングが機能することが判明。**サーバーのステートフル化(大改修)は不要**で、検証スクリプト(`scripts/invoke_agentcore_mcp_jwt.py`)がこのヘッダーを再送していないことが既存の実測結果の説明として十分。大改修(Phase 2)は今回のスコープから外し、Phase 0(スクリプト修正+計測ログ)のみ実施する方針(詳細は08番§3)。あわせて、既存の「AgentCoreはECSの約20倍遅い」という比較([07-vpc-waf-cost-verification.md §2.4](./07-vpc-waf-cost-verification.md))が非対称な計測だった可能性を記録
- **12.3 コストシミュレーター**: **実装・公開済み(2026-08-31)**。既存の`02-cost-simulation.md`の数値を逆算する過程で、ALB LCU・CloudFront平均レスポンスサイズという2つの未記載パラメータ、DynamoDB/Logsコストの非対称計上、損益分岐点の簡略化式という3点を新規発見。インタラクティブなArtifactとして実装し、既存ドキュメントの14個の掲載数値を許容誤差$0.5以内で再現することを確認済み(詳細は08番§4.5)
- **12.1 DCR実装(2026-08-31実施)**: タスク1〜6(Lambda Authorizer実装・Register Lambda実装・discoveryメタデータ・乱用対策の一部・CLI管理コマンド)を`terraform-playground-pattern4`に実装し、実機で(a)既存静的クライアントの回帰確認、(b)DCR新規登録→client_credentialsでのMCP呼び出し成功、(c)DynamoDB失効フラグによる即時アクセス遮断、の3点を確認済み。詳細・詰まりどころは[10-dcr-implementation.md](./10-dcr-implementation.md)。残タスク: Claude Code/Claude.aiからの実際の自己登録によるE2E確認(Cognito Managed Login UI v2がブラウザ操作前提のため簡易スクリプトでは代替できず)、セキュリティレビュー、本番相当`terraform/`への移植(書き込み禁止のためapply自体はユーザー判断)
- 12.2(応答時間チューニングPhase 0、約3人日)は**未着手**。次回セッションは08番ドキュメントの「§5 実施順序」の残タスクから着手する

ユーザーから今週の検証項目として次の3点が提示され、スコープを確認した。**実際の作業は未着手**(SSOトークン確認の直後にセッションを次回に持ち越すことになったため)。

### 12.1 DCR(動的クライアント登録)の実装

- スコープ: **選択肢B(カスタムDCR/CIMDプロキシを実際に構築)を採用**。§11.2で比較した「選択肢A: `oauth_anthropic_creds`申請」ではなく、Cognitoの手前に立つ独自のOAuth Authorization Server(DCR `/register`エンドポイント、または CIMD の `client_id` URL検証ロジック)を実際に実装する方針
- 前提条件: §11末尾の通り、**新規ブランチを切るには先に初回git commitが必要**(現状コミット0件)。次回セッション開始時、まずこの初回コミットの実施可否をユーザーに確認すること
- 参考: §11.2のコスト試算では選択肢Bは「DCRのみなら3〜5人日、CIMD対応まで含めると1〜2週間」と見積もっていた。実装にあたってはこの見積りとのズレも記録すること

### 12.2 応答時間の深掘り検証・チューニング

- 背景: [07-vpc-waf-cost-verification.md §2.4](./07-vpc-waf-cost-verification.md)で、ECS+API Gateway(約0.2〜0.3秒)がAgentCore Runtime(約6秒)より約20倍速いという結果が出ており、ユーザーは「現状ECSの方が有利に見えるので、AgentCore Runtime側をチューニングまたはアーキテクチャ最適化して同等以上の速度を目指せないか」を検証したいとのこと
- スコープ確認済み: **アプリコード(`server/src/*`)を変更し、再デプロイしながら検証してよい**(ユーザー承認済み)
- **次回最初に試すべき、最も安価な仮説(未検証)**: §2.4の実測で判明した「リクエストごとに新しいコンテナが起動し、起動に約3.9秒かかる」という現象について、AgentCore Runtimeのレスポンスヘッダーに`mcp-session-id`・`x-amzn-bedrock-agentcore-runtime-session-id`というセッションIDが含まれていることを2026-08-21のCloudFront経由テストで確認済み(未活用のまま)。**同一セッションID を2回目以降のリクエストで使い回すと、コンテナが再利用され約3.9秒の起動コストを回避できるのではないか、という仮説がある**。これはアプリコード変更なしで検証でき(クライアント側でセッションIDヘッダーを送るだけ)、成立すれば「アーキテクチャ最適化でECSと同等以上の速度を実現する」という目標に直結する、最優先で試すべき仮説
- その他の検証候補: サーバー実装(`server/src/index.ts`)の`sessionIdGenerator: undefined`(ステートレスStreamable HTTP)設定を、実際のセッションID発行に変更した場合の挙動変化。Node.js起動時間の削減(依存関係の遅延ロード等)
- 前提: [07-vpc-waf-cost-verification.md §3.2の詰まった点4](./07-vpc-waf-cost-verification.md)で判明した「VPCモードにするとCloudWatch Logsへのログ配信が止まる」問題が未解決のため、**タイミング計測ログを仕込んでも現在はログが見えない**。チューニング検証を始める前に、`com.amazonaws.<region>.logs`のVPCエンドポイントを追加するか、一時的に`networkMode: PUBLIC`に戻すかの判断が必要
- playground用ECRイメージの再ビルド・pushの手順は[07-vpc-waf-cost-verification.md §2.4](./07-vpc-waf-cost-verification.md)や本ファイル§4のterraform-playground-pattern4の手順を参考にできる

### 12.3 コストシミュレーターの作成

- 背景: [02-cost-simulation.md](./02-cost-simulation.md)に「内訳の算出根拠(サービス別)」の表を追加済みだが、ユーザーからは「現在の約$50〜60ではよく分からないので、コストモデルを整理しながらシミュレーターを作ってほしい」との要望
- スコープ確認済み: **インタラクティブなWebページ形式**(トラフィック量・VPCモード有無・WAF有無等をスライダー/チェックボックスで調整でき、サービス別内訳と合計がリアルタイムに表示される)。Artifactとして公開する想定
- 材料は揃っている: [02-cost-simulation.md](./02-cost-simulation.md)の単価表(vCPU $0.0895/時間、メモリ$0.00945/時間、Fargate/ALB/NAT/APIGW単価、VPCエンドポイント$0.014/時間/AZ、WAFv2 $5/月+$1/ルール等)をそのままロジックに落とし込める
- 実装時の注意: Artifactを書く前に`artifact-design`スキルを読み込むこと(このセッションでは未実施)

### 進め方の推奨(次回セッション向け)

1. まずSSOログイン状態を確認(このセッションでは失効していた)
2. 12.2の「セッションID使い回し仮説」はコード変更不要で最も安く検証できるため最初に試す
3. 12.3のコストシミュレーターはAWSアクセス不要で並行して進められる
4. 12.1のDCR実装は初回git commitの合意が前提になるため、着手前にユーザーに確認する

# 商用リモートMCPサーバーの本番運用に向けた調査(AgentCore Gateway等の参考事例を含む)

> この章で分かること
> 金融機関向けに外販するリモートMCPサーバーを本番運用するにあたり、AWSがマネージドサービス(AgentCore Gateway)や参照アーキテクチャ(MCP Servers on AWS Guidance)で「MCPの入口」に何を必須としているか、MCP仕様(2026-07-28)とAnthropicコネクタ仕様が運用者に何を求めているかを公式資料から整理する。その上で本プロジェクトのECS + API Gateway構成との差分を洗い出し、[20-internal-production-readiness-checklist.md](./20-internal-production-readiness-checklist.md)へ追加すべき運用要件(`OPS-NN`)を提案する。

作成日: 2026-09-13 | 実施方法: 机上調査(AWS公式ドキュメント、MCP仕様、Anthropicコネクタ仕様、AWSのFISC公開資料。AWSへの書き込みなし)

**本調査の位置づけ**: AgentCore Gateway / Identity等のAWS AIサービスは、DCR・WAF・運用設計のベストプラクティスの**参考事例としてのみ**参照する。AgentCore Runtimeを含むホスティング方式の再検討ではない。本番アーキテクチャはECS + API Gatewayで確定している([19-internal-weekly-verification-plan-week5.md](./19-internal-weekly-verification-plan-week5.md)、[00-handoff.md §16.1](./00-handoff.md))。

---

## TL;DR

| # | 論点 | 結論 |
|---|---|---|
| 1 | 位置づけ | AgentCore Gatewayは「AWS自身がマネージドMCP入口で何を標準にしているか」を知るための比較対象。ホスティング方式の再検討ではなく、本番はECS + API Gatewayのまま(§1) |
| 2 | AgentCore Gatewayが入口で標準装備しているもの | JWT認可(`discoveryUrl` / `allowedClients` / `allowedAudience` / `allowedScopes`)、未認証時の**401 + `WWW-Authenticate`(`resource_metadata`と`scope`パラメータ)**、スコープ不足時の403 + `error="insufficient_scope"`、`/.well-known/oauth-protected-resource`の自動提供、JWTクレームのCloudTrail記録。本プロジェクトで未達なのは`WWW-Authenticate`(HTTP API制約)とスコープ不足時の403の区別(§2) |
| 3 | AWS参照アーキテクチャとの一致 | 「Guidance for Deploying MCP Servers on AWS」はCloudFront(WAF付き)→ ALB → ECS Fargate + Cognitoの構成で、本プロジェクトの主案(CloudFront + WAF)と同型。WAFにレート制限を含める、MCPサーバーをプライベートサブネットに置く、ログをCloudWatchに集約する点も一致。差分は参照実装が独自の認可サーバー(MAS)でCognitoトークンを自前トークンに交換している点(§3) |
| 4 | MCP仕様・Anthropic仕様の運用要件 | audience検証MUST、token passthrough禁止、公開クライアントのRTローテーション、`WWW-Authenticate`での`scope`提示、各エンドポイント10秒以内応答、Anthropic egress `160.79.104.0/21`、**高トラフィックではDCRよりCIMD / `oauth_anthropic_creds`推奨**(接続ごとにクライアントが増えるため)(§4) |
| 5 | 金融統制との対応 | AWSはFISC安全対策基準第14版対応の参照資料を公開しており、責任共有の顧客側統制としてWAF・アクセス制御・ログ保全が該当する。条文番号レベルの紐付けは同資料の精読が必要(要確認)(§5) |
| 6 | チェックリストへの追加 | `OPS-01`〜`OPS-10`(WWW-Authenticateの提示、403/401の区別、CloudTrailによる認可イベント記録、秘密ヘッダのローテーション、Anthropic egress許可リスト、登録クライアント数の監視、10秒SLO、依存IdPのWAF影響、テーブル名・issuer固定、Countからの段階的Block運用)を提案(§6) |

---

## 1. 調査対象と観点

| 調査対象 | 見る観点 | 本プロジェクトへの持ち帰り |
|---|---|---|
| AgentCore Gateway「Inbound authorization」 | JWT認可の設定項目、未認証応答の形、スコープ広告、ログ | 入口の必須要件の裏付け(§2) |
| AgentCore GatewayのMCP 2026-07-28対応ブログ | プロトコル版数交渉、セッション、ヘッダルーティング、認可への影響 | v2移行時の入口側の変更点(§2.3) |
| Guidance for Deploying MCP Servers on AWS | CloudFront + WAF + ALB + ECS + Cognitoの参照構成 | 主案(d)の妥当性、差分(§3) |
| AWS Blog「Open Protocols for Agent Interoperability Part 2」 | AWSのMCP認可に関する見解 | RFC 9728 / 8414 / 8707の位置づけ(§4.1) |
| MCP仕様 Security Best Practices(2026-07-28) | 運用者向けMUST / SHOULD | チェックリストの重要度判定(§4.2) |
| Anthropic「Authentication for connectors」 | DCR / CIMD / `oauth_anthropic_creds`、発見経路、タイムアウト、egress IP | E2E観察点、WAF許可リスト(§4.3) |
| AWS WAF ボディ検査上限 | リソース種別ごとの上限と課金 | 週5で実測した誤検知の裏付け(§3.2) |
| AWS FISC対応ページ | 参照資料の版、責任共有 | 統制項番の紐付け方針(§5) |

---

## 2. AgentCore Gateway / Identityが「MCP入口」で必須にしていること(参考事例)

### 2.1 認可方式と設定項目

[AgentCore Gateway: Set up inbound authorization](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-inbound-auth.html)では、入口の認可を**JWT**、**IAM(SigV4)**、そして **オフロード(`AUTHENTICATE_ONLY` / `NONE`)** の3系統に分け、JWT方式は`CustomJWTAuthorizerConfiguration`で次を設定する。

| 設定項目 | 検証対象 | 本プロジェクトの対応物 |
|---|---|---|
| Discovery URL(`discoveryUrl`) | OIDC discovery(JWKS・issuer) | Lambda Authorizerの`aws-jwt-verify`(User Pool固定) |
| Client ID(`allowedClients`) | `client_id`クレーム | `clientId: null`で任意クライアントを受理し、DynamoDB `CLIENT#`で個別管理(deny-on-missing) |
| Allowed audience(`allowedAudience`) | `aud`クレーム | `RESOURCE_SERVER_IDENTIFIER`との一致検証(週5で追加) |
| Allowed scopes(`allowedScopes`) | `scope`クレーム | `REQUIRED_SCOPE`(`<rs>/invoke`)必須 |
| その他の必須クレーム | カスタムクレーム | なし |

`NONE`や`AUTHENTICATE_ONLY`で認可をオフロードする場合、AWSは「ポリシーエンジン、インターセプターLambda、下流ターゲットのいずれかで必ず認可を強制せよ」と明記し、`bedrock-agentcore:GatewayAuthorizerType`条件キーで`NONE`の作成自体を組織的に禁止する運用を推奨している。本プロジェクトの「API Gateway側でLambda Authorizerが認可し、ECS側でテナント承認(`USER#`)を二重に判定する」構成は、この「入口とターゲットの二層」に相当する。

### 2.2 未認証応答の形(本プロジェクトとの最大の差分)

同ドキュメント「Scope advertisement in authentication challenges」によれば、Gatewayは次を**標準で**返す。

- **401 Unauthorized**(トークン無し・無効): `WWW-Authenticate`ヘッダに`resource_metadata`と`scope`パラメータを含む([RFC 6750 §3](https://datatracker.ietf.org/doc/html/rfc6750#section-3)形式)。
- **403 Forbidden**(トークン有効だがスコープ不足): `WWW-Authenticate`に`error="insufficient_scope"`、`scope`、`resource_metadata`を含む。
- `resource_metadata`は`/.well-known/oauth-protected-resource`のOAuth Protected Resource Metadata([RFC 9728](https://www.rfc-editor.org/rfc/rfc9728))を指す。

本プロジェクトの現状は、401は返せるようになった(週5、`DENY_MODE=throw`)が`WWW-Authenticate`を付与できず、スコープ不足も401で返している。HTTP API(v2)のLambda Authorizerではヘッダ付与も401 / 403の使い分けもできないため、[19-internal-weekly-verification-plan-week5.md §1.3](./19-internal-weekly-verification-plan-week5.md)のCloudFront Functions(S12)またはREST API移行(Gateway Responses)が解決経路になる。AWSのマネージド入口が「標準装備」にしている以上、商用サービスとしても揃えるべき項目と判断する(§6 OPS-01 / OPS-02)。

### 2.3 MCP 2026-07-28への対応で入口に求められること

[How AgentCore Gateway supports the MCP 2026-07-28 spec](https://aws.amazon.com/blogs/machine-learning/how-agentcore-gateway-supports-the-mcp-2026-07-28-spec/)では、Gatewayが複数プロトコル版を同時に受け付け、クライアントは`MCP-Protocol-Version`ヘッダで版を選ぶ。未対応版は`HTTP 400`とJSON-RPCコード`-32022`で拒否し、`Mcp-Method` / `Mcp-Name`ヘッダとボディの不一致は`-32020`で拒否する。認可は「プロトコル版に依存せず不変」と明記されている。本プロジェクトのv2 SDK検証([12-internal-mcp-protocol-v2-upgrade-impact.md](./12-internal-mcp-protocol-v2-upgrade-impact.md))とも整合し、WAFのカスタムルールで`MCP-Protocol-Version`の許可版数を持つ場合(A23)は新版リリース時の更新手順が必要になる。

### 2.4 監査ログ

JWT認可を使うとJWTの一部クレーム(Subject)がCloudTrailに記録されるため、AWSは`sub`にPIIを入れない(GUIDやpairwise識別子を使う)ことを推奨している。本プロジェクトはCognitoの`sub`(UUID)を使っており適合するが、API Gatewayアクセスログ(週5で有効化)に`authorizerSub`を出力しているため、ログの保持・アクセス制御をPII相当として扱う必要がある(§6 OPS-03)。

---

## 3. AWS参照アーキテクチャ(MCP Servers on AWS Guidance)とWAF・オリジン保護

### 3.1 構成の一致点

[Guidance for Deploying Model Context Protocol Servers on AWS](https://docs.aws.amazon.com/solutions/deploying-model-context-protocol-servers-on-aws/)(サンプルコード: [GitHub](https://github.com/aws-solutions-library-samples/guidance-for-deploying-model-context-protocol-servers-on-aws))の参照構成は次の通り。

1. MCPクライアントの要求は**CloudFront(AWS WAFで保護)→ ALB → ECS Fargate**へ流れる。
2. MCPサーバーはプライベートサブネットに置き、セキュリティグループで経路を制限する。
3. 認証はCognitoの認可コードグラント。参照実装では **MCP Auth Service(MAS)** という独自の認可サーバーがCognitoへリダイレクトし、Cognitoトークンを自前のアクセストークンに交換してクライアントへ返す(セッション・コード・リフレッシュトークンはDynamoDBにTTL付きで保存: セッション24時間、コード10分、リフレッシュ30日)。
4. WAFは「一般的なWeb攻撃の防御と、DDoS対策としての**レート制限**」を含むと明記。
5. ログはCloudWatch Logsに集約し保持期間を設定。設定はParameter Store、秘密情報はSecrets Manager。

本プロジェクトの主案(d)「CloudFront + WAF → HTTP API → VPC Link → ALB → ECS」はこれと同型であり、週5の選択([19-internal-weekly-verification-plan-week5.md §1.3](./19-internal-weekly-verification-plan-week5.md))はAWSの参照構成に沿っている。

### 3.2 差分と持ち帰り

| 観点 | 参照実装 | 本プロジェクト | 持ち帰り |
|---|---|---|---|
| 認可サーバー | 独自(MAS)がCognitoトークンを自前トークンに交換。issuerを自ドメインに揃えられる | API Gatewayファサード(メタデータ)+ Cognito発行トークン。issuer不一致を文書化で許容 | issuer完全一致が必要になった場合の実装例として参照(D案、[19番 §2.4-a](./19-internal-weekly-verification-plan-week5.md)) |
| DCR | 記載なし(要確認) | Lambdaで実装 | 参照実装のDCR有無はGitHubで要確認 |
| オリジン保護 | 公開資料に明記なし(要確認) | `X-Origin-Verify`秘密ヘッダ(観測モード) | 秘密ヘッダのSecrets Manager管理・ローテーションを恒久設計へ(OPS-04) |
| WAFルール | 「一般的な攻撃」+「レート制限」 | マネージド7グループ + カスタム(メソッド、64KB超、JSON-RPCバッチ、レート×3) | 参照実装より細粒度。誤検知運用(Count → Block)が必要 |
| ボディ検査上限 | 記載なし | CloudFront既定16KB → 64KBへ引き上げ | [AWS WAF: Body inspection size limit](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-setting-body-inspection-limit.html): ALB / AppSyncは**8KB固定**、CloudFront / API Gateway / Cognito等は既定16KBで16KB刻みに64KBまで拡張可(16KB超分のみ追加課金)。週5の実測(ALBで12KB長文が誤検知、CloudFrontで日本語12KB相当=約20KBが誤検知)と一致する |
| 秘密情報 | Secrets Manager | 環境変数(SSM SecureStringはアプリ側のみ) | Lambda環境変数の秘密ヘッダ値をSecrets Managerへ(OPS-04) |

---

## 4. MCP仕様(2026-07-28)とAnthropicコネクタ仕様の運用者向け要件

### 4.1 AWSの見解(Open Protocols for Agent Interoperability Part 2)

[Open Protocols for Agent Interoperability Part 2: Authentication on MCP](https://aws.amazon.com/blogs/opensource/open-protocols-for-agent-interoperability-part-2-authentication-on-mcp/)は、MCPの認可をクライアント / MCPサーバー(リソースサーバー)/ 認可サーバーの3者に分け、[RFC 9728](https://www.rfc-editor.org/rfc/rfc9728)(PRM)→ [RFC 8414](https://www.rfc-editor.org/rfc/rfc8414)(AS metadata)→ DCR → PKCEという自動発見の流れと、[RFC 8707](https://www.rfc-editor.org/rfc/rfc8707)(resource indicators)による「他サーバー向けトークンの流用防止」を強調している。組織で単一の認可サーバーを共用しSSOと統合するパターン、非対話ユースケースでの`client_credentials`や[RFC 7523](https://www.rfc-editor.org/rfc/rfc7523)(JWTアサーション)の将来展望にも触れる。特定AWSサービスの推奨はない。本プロジェクトのF1(Cognitoの`resource`対応でaud付与)はこの方向に沿う。

### 4.2 MCP Security Best Practices(2026-07-28)の運用者向けMUST / SHOULD

[MCP: Security Best Practices](https://modelcontextprotocol.io/specification/2026-07-28/basic/security_best_practices)から、リモートMCPサーバー運用者に直接関わる項目を抜き出す。

| 項目 | 規範 | 本プロジェクトの状態 |
|---|---|---|
| MCPサーバーは自分宛に発行されていないトークンをMUST NOT受理(audience検証、token passthrough禁止) | MUST | Authorizerで`aud`一致検証を追加(aud無しの`client_credentials`は`client_id` + `CLIENT#`で代替)。ECSへは`x-cognito-sub`のみ転送 |
| 認可を実装するサーバーは全リクエストをMUST検証し、状態ハンドル所持を認証とMUST NOT見なす | MUST | ステートレス。`Mcp-Session-Id`偽装(A23b)は無視される |
| redirect URIは登録値と完全一致でMUST検証 | MUST | Cognitoが完全一致。DCR登録時にアローリスト検証 |
| `state`の生成・単一使用・短寿命 | MUST(プロキシ型の場合) | Cognito Managed Loginに委任 |
| CIMDを受け付けるASはSSRF対策(私設IP遮断、egressプロキシ) | SHOULD | CIMD未対応のため該当なし。将来対応時の設計制約 |
| スコープ最小化: `scopes_supported`に全スコープを載せない、`WWW-Authenticate`の`scope`で段階的昇格 | 推奨 | `scopes_supported`は`openid` + `invoke`の2つ。`WWW-Authenticate`未提示 |
| localhost redirectの偽装リスク: 同意画面でredirect URIホストを明示 | SHOULD(AS側) | Cognito Managed Loginの表示制御は不可(制約として文書化) |
| Mix-up攻撃: 認可レスポンスの`iss`検証 | 依存 | Cognitoが`iss`を返すかは要確認(F9) |

### 4.3 Anthropicコネクタ仕様(運用者が守るべき具体値)

[Anthropic: Authentication for connectors](https://claude.com/docs/connectors/building/authentication)から運用に直結する事実を列挙する。

- 認証方式は`oauth_dcr` / `oauth_cimd` / `oauth_anthropic_creds` / `custom_connection` / `static_headers`(beta)/ `none`。**純粋なM2M `client_credentials`は非対応**(ユーザー同意が必須)。
- **高トラフィックのディレクトリ掲載サーバーではDCRよりCIMDまたは`oauth_anthropic_creds`を推奨**。DCRは「新しい接続ごとに新規クライアントを登録する」ため、認可サーバー上に非常に多数のクライアントが作られる。本プロジェクトの登録数上限(`MAX_DCR_CLIENTS`)と掃除方針(AUTHZ-05)はこのリスクへの対処であり、商用ディレクトリ公開時の方式選択(CL-07)を早めに判断する必要がある。
- CIMDが選ばれる条件は、AS metadataに`"client_id_metadata_document_supported": true`と`token_endpoint_auth_methods_supported`に`"none"`の**両方**。無ければDCRにフォールバック。
- PKCEは常に`S256`。AS metadataに`"code_challenge_methods_supported": ["S256"]`が必須。
- スコープ選択: 401の`WWW-Authenticate`の`scope` > PRMの`scopes_supported`。AS metadataの`scopes_supported`に`offline_access`があれば追加要求する。
- 発見経路: **401 + `WWW-Authenticate: Bearer resource_metadata="..."`が最も確実**。200応答上の`WWW-Authenticate`は無視される。無い場合は`/.well-known/oauth-protected-resource/<path>` → ルートの順にプローブ(フォールバック扱い)。PRMの`resource`はユーザーが入力したURLと完全一致、`authorization_servers`は先頭のみ使用。
- **ASのdiscoveryもAnthropicのegress(`160.79.104.0/21`)から行われるため、IdP前段のWAFが接続を壊しうる**。Cognito User Pool WAF(補完)を入れる場合はこのレンジを許可リストに含める(OPS-05)。
- redirect URI: hosted surfacesは`https://claude.ai/api/mcp/auth_callback`。Claude Codeは`http://localhost/callback`と`http://127.0.0.1/callback`をポート無視で受理する必要がある。
- トークンリフレッシュは**401で反応的に**、加えて期限5分前に先行実施。無効なリフレッシュトークンには`invalid_grant`を返す。公開クライアントはRTローテーション。`/token`は`application/x-www-form-urlencoded`、`/register`は`application/json`。
- タイムアウト: discovery / registration / tokenは**10秒**、リフレッシュは30秒。前段のAPI GatewayやWAFが応答を保留しないこと。

---

## 5. 金融機関向け統制との対応(FISC / 金融庁ガイドライン)

[AWSのFISCコンプライアンスページ](https://aws.amazon.com/compliance/fisc/)は、FISC安全対策基準・解説書**第14版**に対応する日本語の参照資料と「リスクとコンプライアンス」ホワイトペーパーを提供し、統制・運用・設備・監査の4観点のうち顧客側の実装責任範囲を責任共有モデルで切り分けるよう求めている。条文番号レベルでの対応表は同参照資料(PDF)の精読が必要で、本調査では未実施(要確認)。[05-internal-security-compliance-verification.md](./05-internal-security-compliance-verification.md)で触れた金融庁「金融分野におけるサイバーセキュリティに関するガイドライン」(2024年10月)との二重の目線も、条文の紐付けは同様に要確認とする。

本プロジェクトの範囲で顧客側統制に該当するものは、(1)ネットワーク層の攻撃防御(WAF)、(2)アクセス制御(OAuth / 認可 / テナント承認)、(3)ログの取得・保全・改ざん防止(WAFログ・API Gatewayアクセスログ・Lambda / ECSログのS3 Object Lock)、(4)変更管理(terraform plan承認制、Count → Blockの段階運用)の4つであり、[20-internal-production-readiness-checklist.md](./20-internal-production-readiness-checklist.md)の「根拠」列に第14版の項番を埋める作業を翌週以降のタスクとする。

---

## 6. 本プロジェクトの現状との差分と、チェックリストへ追加する行

| 追加ID案 | 要件 | 根拠 | 検証方法 | 重要度 |
|---|---|---|---|---|
| OPS-01 | 401応答に`WWW-Authenticate: Bearer resource_metadata="...", scope="..."`を付与する(Claudeの最も確実な発見経路、AgentCore Gatewayの標準挙動) | §2.2、§4.3 | `dcr_conformance_tests.py --id 9728-05` | 必須 |
| OPS-02 | トークン無効(401)とスコープ不足(403 + `error="insufficient_scope"`)を区別して返す | §2.2 | 不足スコープのトークンで`curl -i` | 推奨 |
| OPS-03 | 認可イベント(拒否理由、`sub`、`client_id`)をCloudTrail / アクセスログに残し、`sub`をPIIとして扱う保持・アクセス制御を定める | §2.4 | ログ設定レビュー | 必須 |
| OPS-04 | オリジン保護の秘密ヘッダ(`X-Origin-Verify`)はSecrets Managerで管理しローテーションする | §3.2 | terraformレビュー、ローテーション手順の実施 | 必須 |
| OPS-05 | Anthropic egress `160.79.104.0/21`をMCPサーバーおよびIdP前段のWAF許可リストに含め、Geo / IPレピュテーション / HostingProviderで遮断しない | §4.3 | Countモードのラベル観測、許可リストのterraform | 必須 |
| OPS-06 | DCRで増える登録クライアント数を監視し、上限・掃除・方式選択(CIMD / `oauth_anthropic_creds`)の判断基準を持つ | §4.3 | `COUNTER#dcr`のアラーム、月次レビュー | 必須 |
| OPS-07 | discovery / registration / tokenの応答を10秒以内(目標3秒以内)に保つ。前段WAF / API Gatewayが応答を保留しないこと | §4.3 | CloudWatch Duration、`dcr_conformance_tests.py --id CL-04` | 必須 |
| OPS-08 | 公開URL(issuer、`resource`、redirect登録先)をカスタムドメインで固定し、経路変更で登録済みクライアントを無効化しない | §3.2、[19番 D5](./19-internal-weekly-verification-plan-week5.md) | カスタムドメイン経由のE2E(S7) | 必須 |
| OPS-09 | WAFは全ルールCountで観測し、誤検知ゼロを確認したルールから段階的にBlockへ切り替える。例外は台帳に記録する | §3.2 | terraform `locals.waf_mode`と例外台帳 | 必須 |
| OPS-10 | MCPプロトコル新版リリース時に、WAFの版数許可リスト(A23)とサーバーの`supportedVersions`相当を同時に更新する手順を持つ | §2.3 | 手順書レビュー | 推奨 |

---

## 7. 次のアクション

1. OPS-01 / OPS-02の実現経路を決める: CloudFront Functionsで401に`WWW-Authenticate`を付与できるか(S12)、できなければREST API移行のGateway Responsesを採用理由に加える。
2. OPS-05のためにCognito User Pool WAFの許可リストにAnthropic egressを入れた上で導入する(補完WAF、[19番 §1.3](./19-internal-weekly-verification-plan-week5.md))。
3. OPS-06の方式選択(CL-07)を、Claude Code / Claude.aiからのE2Eで「1接続あたり何件のクライアントが作られるか」を実測した上で判断する。
4. §5のFISC第14版参照資料を精読し、チェックリストの「根拠」列に項番を記入する。
5. 参照実装のGitHubリポジトリでDCR実装の有無とオリジン保護の実装(秘密ヘッダかOACか)を確認する(要確認2件)。

## 取得できなかった資料

- AgentCore Identityのドキュメント(OAuthクライアント / トークン保管、DCRの扱い): 未取得。AgentCore GatewayのJWT認可ドキュメントに含まれる範囲で記述した。
- 参照実装のGitHub README詳細(WAFルールグループ名、オリジン保護方式): 未取得。ページ本文の記述のみ。
- 金融庁ガイドライン(2024年10月)本文、FISC第14版参照資料PDF: 未取得。

---

Sources:
- [Amazon Bedrock AgentCore: Set up inbound authorization for your gateway](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-inbound-auth.html)
- [AWS Machine Learning Blog: How AgentCore Gateway supports the MCP 2026-07-28 spec](https://aws.amazon.com/blogs/machine-learning/how-agentcore-gateway-supports-the-mcp-2026-07-28-spec/)
- [AWS Solutions: Guidance for Deploying Model Context Protocol Servers on AWS](https://docs.aws.amazon.com/solutions/deploying-model-context-protocol-servers-on-aws/)
- [GitHub: guidance-for-deploying-model-context-protocol-servers-on-aws](https://github.com/aws-solutions-library-samples/guidance-for-deploying-model-context-protocol-servers-on-aws)
- [AWS Open Source Blog: Open Protocols for Agent Interoperability Part 2: Authentication on MCP](https://aws.amazon.com/blogs/opensource/open-protocols-for-agent-interoperability-part-2-authentication-on-mcp/)
- [MCP Specification 2026-07-28: Security Best Practices](https://modelcontextprotocol.io/specification/2026-07-28/basic/security_best_practices)
- [Anthropic: Authentication for connectors](https://claude.com/docs/connectors/building/authentication)
- [AWS WAF: Considerations for managing body inspection](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-setting-body-inspection-limit.html)
- [AWS Compliance: FISC](https://aws.amazon.com/compliance/fisc/)
- [RFC 6750: The OAuth 2.0 Authorization Framework: Bearer Token Usage](https://datatracker.ietf.org/doc/html/rfc6750)
- [RFC 8707: Resource Indicators for OAuth 2.0](https://www.rfc-editor.org/rfc/rfc8707)
- [RFC 9728: OAuth 2.0 Protected Resource Metadata](https://www.rfc-editor.org/rfc/rfc9728)

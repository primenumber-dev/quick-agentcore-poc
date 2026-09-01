# Step1 仕様確認シートへの回答(MCP・基盤アーキテクチャ設計)

> この章で分かること
> Step1(本番サービス化)に向けた仕様確認シートで提起された、AgentCore Runtime移行に関する7件の質問に、本プロジェクトのこれまでの実機検証結果を根拠に回答する。特に「リクエストヘッダーの扱いについて」は今週発見・修正した重大なセキュリティ脆弱性([09](./09-cross-tenant-impersonation-finding.md))と直結する。

作成日: 2026-09-02 | 回答の根拠: 本プロジェクトの実機検証結果(docs/00〜13)。一部、Step1固有の要件(ドメイン単位のID数制限、Client Credentialsのローテーション等)は本PoCでは未検証・未実装のため、その旨を明記する。

---

## 回答一覧

### Q1. AgentCore Runtimeを使用した場合のOAuth検証エンドポイントについて(優先度: 低)

> PoCのソースを確認するとAPI Gatewayのmock統合で`.well-known/*`を静的に返してます。AgentCore Runtimeを使用した場合は自身のCustom JWT AuthorizerがCognitoのdiscoveryUrlを直接参照する方式に変わるため、独自実装は不要になりますか。

**回答**: メタデータの種類によって結論が異なる。

| メタデータ | 独自実装の要否 |
|---|---|
| JWT検証用の`discoveryUrl`(`.well-known/openid-configuration`) | **不要**。Custom JWT AuthorizerがCognitoのdiscoveryUrlを直接参照するため、API Gatewayでのプロキシは不要 |
| `.well-known/oauth-protected-resource`(RFC9728、Protected Resource Metadata) | **不要**。AgentCore Runtimeが未認証リクエストへの応答として自動的に返す(`WWW-Authenticate`ヘッダー経由)。実機で200 OK・正しいJSON返却を確認済み([00-handoff.md §9](./00-handoff.md)) |
| `registration_endpoint`等の追加メタデータ(DCR等) | **実装不可**。AgentCore Runtimeには`.well-known`のような任意ルートを追加できる層が存在しないため(詳細はQ6と関連、[10-dcr-implementation.md §0](./10-dcr-implementation.md)参照) |

---

### Q2. AgentCore Runtimeを使用した場合の呼び出しプロトコルについて(優先度: 低)

> PoCではAPI Gatewayを使用した素のHTTPの構成で作成している認識です。AgentCore Runtimeに変更した場合、いただいた資料では`serverProtocol: MCP`で標準HTTP+JWTのまま接続でき、既存の`claude mcp add --transport http`がそのまま使えたとのことですが、Web版・Desktop版では何か考慮することがありますでしょうか。

**回答**: Claude CodeとClaude.ai Web版/Desktop版で、OAuthフローの扱いに違いがあり、Web/Desktop版特有の考慮点がある(Claude Codeでの疎通確認時に実機で踏んだ問題、[06-agentcore-oauth-claude-code-verification.md §7](./06-agentcore-oauth-claude-code-verification.md)参照)。

1. **OAuthディスカバリーの手動上書きができない**: Claude Codeは`~/.claude.json`でOAuthメタデータURL・scopeを手動指定できるが、Claude.ai Web/Desktop/Cowork/mobileはAnthropicのクラウド側でOAuthフローを実行し、コールバックURLも固定(`https://claude.ai/api/mcp/auth_callback`)で、ローカル設定による上書き手段が無い。CognitoのRFC8414 discoveryが不完全だと、Web/Desktop版では回避策が取れない
2. **要求スコープの明示が必須**: 401応答の`WWW-Authenticate`ヘッダーに`scope`パラメータを含めないと、Web/Desktop版はProtected Resource Metadataの`scopes_supported`を丸ごと要求してしまう(実機で確認済みの障害モード)。AgentCore Runtimeの`authorizerConfiguration.allowedScopes`を明示的に設定する必要がある(本PoCではversion 6で対応済み)
3. **組織のプラン制約**: Claude.aiのカスタムコネクタ追加は組織のOwner権限が必要(Team/Enterpriseプランの場合)。これは技術設定ではなく運用上の制約として認識しておく必要がある

なお、Desktop版固有の追加検証は本プロジェクトでは未実施(Web版・Claude Codeのみ実機確認済み)。Step1でDesktop版のサポートが要件になる場合は別途実機検証を推奨する。

---

### Q3. ShimとOpenAPI準拠のロジックについて(優先度: 中)

> PoCではOpenAPI準拠に対応していないAPIのため、Shimを使ってAPIをラップして提供しています。ShimはECS内で処理していたためAgentCore Runtimeに変更してもそのまま使用できると思いますが、OpenAPI準拠のAPIはAPI Gatewayのmock統合を使用して実装している認識です。AgentCore Runtimeを利用する場合はCustom JWT Authorizerなどで、OpenAPI準拠のAPIを指定するなどの対応を行う必要がありますでしょうか。

**回答**: 2つの論点を分けて回答する。

1. **Shim(アプリケーションロジック)について**: ご認識の通り対応不要。Shimはコンテナ内(アプリケーションコード)で処理しているロジックであり、ECS/AgentCore Runtimeのどちらでホストしてもコンテナの中身が同じであれば同一に動作する。実際、本PoCでもAgentCore Runtime向けの変更はポート番号(8000固定)のみで、アプリロジックには一切手を入れていない([00-handoff.md §7](./00-handoff.md))
2. **「API Gatewayのmock統合=OpenAPI準拠API提供」という認識について**: ここは前提の訂正が必要。PoCでmock統合を使っているのは、OpenAPI準拠APIをクライアントに公開するためではなく、**OAuthのディスカバリーメタデータや`/authorize`・`/token`をCognitoにプロキシするため**(`terraform/apigateway.tf`, `openapi.yaml`)。つまり「クライアントに公開するAPI仕様」の話ではなく、認可フローの配線の話である

Custom JWT Authorizerは「JWTの検証方法」を設定するものであり、「対応するAPI仕様」を指定する機能は持たない。したがって、**Custom JWT Authorizerで"OpenAPI準拠APIを指定する"という対応は不要**(そのような設定項目自体が存在しない)。Q1の回答の通り、mock統合で担っていたOAuthメタデータの一部はAgentCore Runtime移行で不要になるが、それ以外の独自エンドポイント追加は物理的に不可能になる点に注意されたい。

---

### Q4. AgentCore Runtimeを使用した場合のリクエストヘッダーの扱いについて(優先度: 中)【要最優先対応】

> PoCではAPI Gatewayを使用していたため、リクエストヘッダー`x-cognito-sub`があれば無条件に信頼する作りになっております。AgentCore Runtimeを使用した場合は何かしら対処が必要になるのでしょうか。

**回答: はい、対処が必須です。** これはまさに今週、応答時間チューニングの調査中に発見し、実機で確証を取った重大な脆弱性そのものです。詳細な図解・実機確認手順は[09-cross-tenant-impersonation-finding.md](./09-cross-tenant-impersonation-finding.md)を参照。

**なぜPoC(API Gateway経由)では安全だったか**: API Gatewayの統合設定に`overwrite:header.x-cognito-sub = $context.authorizer.jwt.claims.sub`という**強制上書き**が入っており、クライアントが送ってきた同名ヘッダーの値は必ず検証済みの値で上書きされる。つまり「ヘッダーを信頼する」設計が安全なのは、API Gatewayという前段の保護機構あってこそだった。

**AgentCore Runtimeにはこの保護機構が存在しない**。`requestHeaderConfiguration.requestHeaderAllowlist`は「どのヘッダーをコンテナに転送するか」を決めるだけで、値を検証済みのものに強制上書きする機能は持たない。

**実機で確認した攻撃**: playground環境で、有効な自分のJWTを持つ利用者が`x-cognito-sub`ヘッダーに別テナントのsubを指定してAgentCore Runtimeを呼び出したところ、**そのテナントとして認可され、成功レスポンスが返ってきた**(クロステナントなりすまし)。

**対処方法(実機確認済み)**: AgentCore Runtimeの`requestHeaderConfiguration.requestHeaderAllowlist`から`x-cognito-sub`を除外し、`Authorization`のみを許可する。アプリコード(`extractSub()`)は元々「ヘッダーが無ければBearerトークンのpayloadから`sub`を導出する」フォールバックを持っていたため、**アプリコードの変更は一切不要**、AgentCore Runtime側の設定変更のみで修正できた。修正後、同じ手法でのなりすましが失敗する(正しくBearerトークンの`sub`にフォールバックする)ことを再検証済み。

**Step1設計への提言**: 上記の設定対応に加え、`extractSub()`の現在の実装(署名検証なしでJWTペイロードをbase64デコードするだけ)を、Cognito JWKSに対する実署名検証に強化することを推奨する。AgentCore Custom JWT Authorizerが前段で検証済みという前提に全面的に依存する設計は、多層防御の観点で脆弱性を残す。

---

### Q5. AgentCore Runtime の利点について(優先度: 中)

> AgentCore Runtime の利点の一つとしてセッション単位の隔離と状態保持(セッションごとに専用のマイクロVM、長時間実行)の機能があると思いますが、MCPサーバとして動作させる場合にステートレスのため、この機能自体は不要だと認識していますが、相違ないでしょうか?

**回答**: 半分は正しいが、修正が必要な認識も含まれる。

「ステートレスMCPサーバーとして動かす場合、アプリケーション側で状態保持の実装(セッションマップ等)をする必要はない」という点は正しい。本PoCのMCPサーバーもステートレス実装(`sessionIdGenerator: undefined`)のままで問題なく動作している。

一方、「マイクロVM単位のセッション隔離機能自体が不要」と言い切るのは不正確。AWS公式ドキュメントによれば、**AgentCore RuntimeはステートレスなMCPサーバーであっても、`Mcp-Session-Id`ヘッダーによるmicroVMスティッキーロイティングに対応している**([08-weekly-verification-plan.md §3](./08-weekly-verification-plan.md))。具体的には、プラットフォーム側が`Mcp-Session-Id`を自動生成してクライアントに返し、クライアントがこれを次回リクエストで再送すると同じmicroVMにルーティングされる(コンテナのコールドスタートを回避できる可能性がある)。アプリケーション側はこのヘッダーを「拒否せず受け入れる」以外、特別な実装は不要。

つまり、より正確な認識は「マイクロVM単位の状態保持機能は、**アプリケーションの実装としては不要**(ステートレスのままでよい)だが、**レイテンシ最適化の観点では活用可能な機能**」というもの。実測では約6秒のレイテンシのうち約65%がコンテナ起動コストと推定されており([07-vpc-waf-cost-verification.md §2.2.1](./07-vpc-waf-cost-verification.md))、この仕組みを活用できれば起動コストを削減できる可能性がある。**ただし本セッション時点ではこの活用効果は未検証**(検証手順は整理済みだが、次回セッションに持ち越し)。

---

### Q6. AgentCore RuntimeのInboundについて(優先度: 中)

> AgentCore Runtimeを使用した場合にInboundは公開エンドポイント(インターネットに面する形)となる認識。OutboundはVPCに閉じれるが、閉域網の要件が出てきたときにネックになると考えられる。

**回答**: 前半(Outbound閉域化)は正しいが、後半の懸念は妥当性があるものの、いくつか補足が必要。

AgentCore Runtimeは`networkConfiguration.networkMode: VPC`を指定することで、Runtime自体をVPC内にENI配置できる。playgroundアカウントで実際にVPCモードへ切り替え、次を実機確認済み([05-security-compliance-verification.md §4.1.1](./05-security-compliance-verification.md)):

- **Inbound(`invocations`エンドポイント)への影響なし**: VPCモードに切り替えても、外部からの呼び出しは引き続き正常動作する
- **Outbound(DynamoDB等VPC内リソースへのアクセス)も正常動作**

ただし重要な補足として、「Inboundは公開エンドポイントのまま」という点は**VPCモードにしても変わらない**。AgentCore Runtimeの`invocations`エンドポイントは`bedrock-agentcore.<region>.amazonaws.com`というAWSの共通(パブリック)エンドポイントであり、VPCモードはRuntimeの実行環境をVPC内に置く機能であって、Inboundの通信経路自体をプライベートにする機能ではない。

真に閉域化されたインバウンド(VPC内部からのみ到達可能にする)を実現するには、`com.amazonaws.<region>.bedrock-agentcore`のPrivateLinkインターフェースエンドポイントが必要と考えられるが、**これは本プロジェクトでもまだ実機検証できていない**([00-handoff.md 未着手事項](./00-handoff.md)に記録済み)。したがって、「閉域網要件が出てきたときにネックになる」というご懸念は的確であり、閉域網要件が具体化した時点でPrivateLink経由の完全な閉域インバウンドの実現可否・追加コスト・レイテンシ影響を優先的に実機検証すべき。

---

### Q7. Step1で想定しているMCPクライアントについて(優先度: 高)

> Step1で考えているMCPクライアントは以下の想定です。(PoC構成①、Step1サービス②③)

このご質問はアーキテクチャの技術的な正否確認というより、Step1の要件案そのものへのレビュー依頼と理解して回答する(**スクリーンショットの説明文が途中で切れているため、①〜③以降に続きがある場合は原文を追送いただきたい**)。

**①PoC構成(Claude等がMCPクライアントとして接続、ブラウザログイン、2回目以降はパスワード+MFA)について**: この部分は本PoCで実機確認済みの範囲と一致する。Cognitoの認可コード+PKCEフローによるブラウザログイン、Refresh Token失効後の再ログインは、いずれも本プロジェクトの検証内容と整合する。

**②Step1サービス(社内テスト用・お客様向け、ドメインチェック・ドメイン毎ID数制限)について**:
- 「お客様向けにはPoCと同じでよいか」という点について: 前回セッションのDCR/CIMD机上調査([00-handoff.md §11](./00-handoff.md))で、「金融機関ごとに個別コネクタとして提供し、各社の管理者がClient ID/Secretを個別入力する」運用は、Anthropic公式ドキュメントが定める「Custom connector」の正規フローそのものであり、追加のDCR対応なしで成立するという結論が出ている。したがって、お客様向けもPoCと同様の構成(個別コネクタ)で問題ないと考えられる
- **「メールドメインチェック」「ドメイン毎のID数制限」は、本PoCでは未検証・未実装**。Cognitoにはこれらを直接サポートする機能は無く、実装する場合はCognitoのPre-Sign-up Lambdaトリガー等でカスタムロジックを組む必要がある。今回のDCR実装で`/register`エンドポイントのredirect_uriアローリスト([10-dcr-implementation.md §2.3](./10-dcr-implementation.md)相当)を自作した際と同様の設計パターンが応用できると考えられるが、これはStep1向けの新規開発項目として計画に織り込む必要がある

**③ソリューション案件(証券会社毎の接続、AIエージェント、Client Credentials方式)について**: この要件は、今回のセッションで実装・検証したDCRのclient_credentialsフローと直接合致する。実機で次を確認済み([10-dcr-implementation.md §4](./10-dcr-implementation.md)):
- `client_credentials`グラントでの登録→トークン取得→MCPツール呼び出しがブラウザ操作なしでエンドツーエンドに成功すること
- クライアント単位の失効(DynamoDBの失効フラグ)が機能すること

ただし2点、Step1設計で検討が必要な項目がある。
1. **証券会社ごとのクライアント割り当ては「審査済みB2Bオンボーディング」であるべき**: 今回セッションのセキュリティレビューで、匿名の自己登録(DCR)がそのまま正規テナントと同じアクセス権を無審査で付与してしまう問題を発見・修正した([10 §4.5](./10-dcr-implementation.md))。証券会社という限定された取引先を想定する③のユースケースでは、開放型のDCR(`POST /register`を誰でも叩ける)よりも、**管理者が明示的にクライアントを発行する専用のadmin操作**(`cli invite-user`と同様のパターン)の方が適切と考えられる
2. **「Client Credentialsのローテーション」は本PoCで未検証**。Cognitoの`UpdateUserPoolClient`でシークレットの再生成は可能と考えられるが、ローテーション運用(有効期限管理、無停止での切替手順)自体は本プロジェクトで検証していない新規の調査項目であり、Step1計画に別途組み込む必要がある

---

## 未回答・要追加確認の項目まとめ

| # | 項目 | 状態 |
|---|---|---|
| Q2 | Desktop版固有の追加検証 | 未実施(Web版・Claude Codeのみ確認済み) |
| Q5 | `Mcp-Session-Id`活用によるレイテンシ改善効果 | 未検証(次回セッション予定、[08 §3](./08-weekly-verification-plan.md)) |
| Q6 | PrivateLink経由の完全閉域インバウンド | 未検証 |
| Q7-② | メールドメインチェック・ドメイン毎ID数制限の実装方式 | 未検証・未実装。Step1向け新規開発項目 |
| Q7-③ | 証券会社向けクライアント発行方式(DCR自己登録 vs admin発行) | 設計判断が必要。本PoCのDCR実装は自己登録前提のためStep1要件との適合性を要検討 |
| Q7-③ | Client Credentialsのローテーション運用 | 未検証・未実装 |

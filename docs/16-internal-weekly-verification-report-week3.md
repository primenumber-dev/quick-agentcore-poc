# 今週の検証レポート(2026-09-03実施)

> この章で分かること
> 今週ユーザーから提示された4項目(MCPプロトコルv2への載せ替え検証、ECS(WAF・DCR)本番化に向けた課題点整理、AgentCore Runtimeの応答時間チューニング、週次レポート作成)について、実施した内容と結果を一本化してまとめる。応答時間チューニングでは、セッションID再利用による最大10倍の高速化と、その効果が持続する時間の範囲(30秒〜5分の間のどこか)を実機で確認した。

作成日: 2026-09-03 | 検証方法: 実機検証(playgroundアカウント883660531246)+ローカル検証(LocalStack)。本番アカウント(620369151795)には一切書き込みなし。

---

## TL;DR

| # | 項目 | 結論 |
|---|---|---|
| 1 | 応答時間チューニング(セッションID再利用) | **効果あり、ただし持続時間に上限がある**。`Mcp-Session-Id`を再送すると約6秒→約0.5〜0.6秒(約10倍)に短縮される。ただしこの効果は30秒後には持続しているが、5分後には失われる(実機で新しいコンテナへの切り替わりを確認)。設定上の`idleRuntimeSessionTimeout`(15分)とは無関係に、より短い時間でコンテナが再利用されなくなる |
| 2 | ECS(WAF・DCR)本番化課題 | DCRの自己登録〜失効フローを実演。あわせてAgentCore Runtime側`allowedScopes`単独運用・ECS側REST APIネイティブオーソライザーという2つの安価なDCR代替仮説を実機で確認、いずれも成立。WAFはSQLi特化ルールが未導入という新規課題を発見。詳細は[15-internal-ecs-production-readiness-gaps.md](./15-internal-ecs-production-readiness-gaps.md) |
| 3 | MCPプロトコルv2への載せ替え | スパイクブランチ(`feature/mcp-protocol-v2-spike`)で実装・ローカル動作確認まで完了。既存6ツールは無修正で動作、認可ゲートも維持。本番`main`への反映は今回未実施(意図的にスパイク止まり)。詳細は[12-internal-mcp-protocol-v2-upgrade-impact.md §7](./12-internal-mcp-protocol-v2-upgrade-impact.md) |
| 4 | 来週へのアクションプラン | 本番`audience`バグの共有・適用判断、DCR本番移植の要否判断、AgentCore Runtime側`allowedScopes`単独運用への切り替え判断、v2移行の本格着手判断の4点がユーザー確認待ち(詳細は§4) |

---

## 1. 応答時間チューニング(セッションID再利用の実機検証)

### 背景

[07-internal-vpc-waf-cost-verification.md §2.2.1](./07-internal-vpc-waf-cost-verification.md)で、AgentCore Runtimeへのリクエストは毎回新しいコンテナが起動し、起動コストが約6秒のうち大半を占めることが判明していた。[08-internal-weekly-verification-plan.md §3](./08-internal-weekly-verification-plan.md)で、AgentCore Runtimeがレスポンスヘッダーに付与する`Mcp-Session-Id`を次回リクエストで再送すれば、同じmicroVM(コンテナ)にルーティングされ起動コストを回避できるのではないか、という仮説が立てられていたが未検証のまま残っていた。

### 実施内容

1. 検証専用の新規Runtime`quickMcpPocLatencyLab`を作成(既存のデモ用Runtimeには一切触れていない)
2. 検証用VPCに`com.amazonaws.ap-northeast-1.logs`のInterface VPCエンドポイントを追加し、CloudWatch Logsへのログ配信を復旧(VPCモード化以降ログが止まっていた問題への対処)
3. `server/src/index.ts`・`server/src/db.ts`に`LOG_TIMING`環境変数ガード付きの計装ログ(`bootId`: プロセスごとに一意なUUID、`reqSeqId`: リクエスト連番)を追加し、latency-labイメージとして再ビルド・デプロイ
4. `scripts/invoke_agentcore_mcp_jwt.py`を拡張し、`--session-id`(`Mcp-Session-Id`ヘッダーの送信)・`--runtime-arn`(対象Runtime切り替え)オプションを追加
5. 単一タイムラインで以下を実施: t=0秒でベースラインセッションを確立し、t=0/30秒/5分/20分の各チェックポイントで、同じセッションIDを再送する「treatment」群と、毎回新規セッション相当の「control」群を1回ずつ呼び出し、応答時間を計測

### 結果

| チェックポイント | treatment(セッションID再送) | control(新規セッション相当) |
|---|---|---|
| 0秒 | 0.540秒 | 35.317秒(注1、通常時は約6秒) |
| 30秒 | 0.608秒 | 6.005秒 |
| 5分 | 6.085秒 | 5.948秒 |
| 20分 | 6.059秒 | 5.959秒 |

(注1) t=0秒のcontrol呼び出しのみ35.317秒という大きな外れ値になった。原因の詳細な切り分けは実施していないが、treatment呼び出しと近接したタイミングで新規コンテナ起動が重なったことによるリソース競合が有力な仮説として考えられる。他の3チェックポイントのcontrol値(約6秒)とは明確に異なる単発の事象であり、以降の考察では通常値の約6秒を基準とする。

CloudWatch Logsで`bootId`を突き合わせたところ、0秒・30秒のtreatment呼び出しは同一の`bootId`(同一コンテナ)によって処理されていた。しかし5分後のtreatment呼び出しでは、そのわずか0.8秒前に新規起動した別の`bootId`のコンテナが処理しており、**同じ`Mcp-Session-Id`を送っているにもかかわらず、コンテナは既に入れ替わっていた**ことを確認した。

```mermaid
flowchart LR
    T0["t=0秒<br/>コンテナA起動<br/>(約6秒)"] -->|"同一Mcp-Session-Id"| T30["t=30秒<br/>コンテナA再利用<br/>(約0.6秒)"]
    T30 -.->|"コンテナAが破棄される<br/>(正確な時刻は30秒〜5分の間)"| Gap["?"]
    Gap -->|"同一Mcp-Session-Idを送信しても再利用できず"| T300["t=5分<br/>コンテナB新規起動<br/>(約6秒)"]
    T300 --> T1200["t=20分<br/>コンテナC新規起動<br/>(約6秒)"]
```

### 図の解説

セッションID再利用によるコンテナ再利用は30秒後までは機能しているが、5分後には既に別のコンテナに切り替わっている。正確な破棄タイミングは30秒〜5分の間のどこかとしか特定できていない(この間の計測点を追加すればさらに絞り込める)。重要なのは、これが設定値である`idleRuntimeSessionTimeout: 900`秒(15分)とは一致しないという点で、AgentCore Runtimeの実際のコンテナ保持時間は、公開されている設定値より短い可能性が高い。

### 結論と評価

セッションID再利用は、**短い間隔での連続呼び出し(数十秒以内)には非常に有効**(約10倍の高速化、6秒→0.5〜0.6秒)だが、**数分以上間隔が空くケースには効果が無い**。これは実際のMCPクライアントの利用パターン(ツール呼び出しの間隔)次第で実利用上の効果が変わることを意味する。連続してツールを呼び出すユースケースでは大きな改善が見込めるが、「久しぶりに使う」「1回だけ呼ぶ」といったパターンでは今回の対策の恩恵を受けられない。

なお、treatment群の最速値(約0.5〜0.6秒)であっても、[07-internal-vpc-waf-cost-verification.md §2.4](./07-internal-vpc-waf-cost-verification.md)で計測したECS+API Gateway構成(約0.2〜0.3秒)にはまだ及ばない。この差は、アプリケーションコード自体の起動オーバーヘッド(Node.jsプロセスの初期化、ツール登録処理など)によるものと推測されるが、今回はその内訳の切り分けまでは実施していない。

### 未実施・来週以降の課題

- コンテナ保持時間の境界(30秒〜5分の間)をより細かい計測点で絞り込む
- [08-internal-weekly-verification-plan.md §3.5](./08-internal-weekly-verification-plan.md)で申し送られていたウォームプール(10台)の実測との不整合、同時多重リクエストでの検証
- コードデプロイモード(2〜3秒目安)との比較
- treatment群の0.5〜0.6秒とECSの0.2〜0.3秒の差の内訳分析(Node.js起動時間、DynamoDB呼び出し時間等)

---

## 2. ECS(WAF・DCR)本番化に向けた課題点整理

DCRの自己登録〜承認〜失効までの一連のフローを既存のplayground環境で実演し、あわせてAgentCore Runtime側の`allowedScopes`単独運用・ECS側のREST APIネイティブ`COGNITO_USER_POOLS`オーソライザーという2つの安価なDCR代替仮説を実機で初めて検証した。WAF代替構成についても再検証し、SQLインジェクション特化のルールセットが導入されていないという新規の課題を発見した。詳細な実施内容・実機ログ・図解は[15-internal-ecs-production-readiness-gaps.md](./15-internal-ecs-production-readiness-gaps.md)にまとめた。

要点のみ再掲する。

- DCRの自己登録は無審査だが、テナントとしての利用許可には別途admin操作が必要という設計を実演で再確認した
- AgentCore Runtime側で`allowedClients`を使わず`allowedScopes`のみを運用すれば、Cognitoのままでも(Auth0移行不要で)DCRが成立することを実機で確認した
- ECS側でREST API(v1)のネイティブ`COGNITO_USER_POOLS`オーソライザーに切り替えれば、自作のLambda Authorizerの認可判定部分は不要にできる可能性があるが、個別クライアントの即時失効機能は別途設計が必要
- WAFの現行ルールセット(`AWSManagedRulesCommonRuleSet`のみ)ではSQLインジェクションパターンが素通りすることを確認した

---

## 3. MCPプロトコルv2への載せ替え検証

`feature/mcp-protocol-v2-spike`ブランチで、`@modelcontextprotocol/sdk`(v1系)から`@modelcontextprotocol/server`+`@modelcontextprotocol/node`(v2系、GA済み)への置き換えを実施し、ローカル環境(LocalStack)で動作確認まで完了した。ユーザーとの合意により、**今回はスパイク検証に留め、本番`main`ブランチへの反映は行っていない**。

主な結果:

- `server/src/index.ts`の書き換えは局所的で、ツール定義(6ツール)は無修正のまま動作した(`registerTool`のプレーンオブジェクト形式は`@deprecated`だが後方互換オーバーロードとして残っている)
- 既存の認可ゲート(Cognito sub抽出+DynamoDB認可チェック)もそのまま流用できた
- 旧世代クライアント(`initialize`ハンドシェイク)・新世代クライアント(`_meta`エンベロープ)の両方が同一エンドポイントで正しく処理されることを、新規作成したスモークテストスクリプト(`scripts/smoke_test_mcp_v2.sh`)で確認した

詳細な変更点・検証手順・新世代クライアントに必要な具体的ヘッダー/フィールドの発見事項は[12-internal-mcp-protocol-v2-upgrade-impact.md §7](./12-internal-mcp-protocol-v2-upgrade-impact.md)にまとめた。

---

## 4. 来週へのアクションプラン

| # | アクション | 担当・確認事項 |
|---|---|---|
| 1 | 本番`terraform/apigateway.tf`の`audience`バグ修正パッチ(`fix/production-audience-config-proposal`ブランチ)を本番担当者に共有し、適用可否を判断してもらう | 最優先。正当なトークンでも常に401になる実害があるため |
| 2 | DCR実装の本番`terraform/`への移植要否を判断する | [15-internal-ecs-production-readiness-gaps.md §5](./15-internal-ecs-production-readiness-gaps.md)の課題1参照 |
| 3 | AgentCore Runtime側`allowedScopes`単独運用への切り替えを、既存のデモ用Runtime(`quickMcpPocVerification`)に適用するかどうかを判断する | Auth0移行より低コストな代替経路として有力。ただし個別クライアント失効の仕組みが別途必要 |
| 4 | MCPプロトコルv2移行を本番`main`へ反映するか、Step1新規開発でv2から書き始めるかを判断する | [12-internal-mcp-protocol-v2-upgrade-impact.md §7.4](./12-internal-mcp-protocol-v2-upgrade-impact.md) |
| 5 | 応答時間チューニングの続き(コンテナ保持時間の境界特定、ウォームプール実測、コードデプロイモード比較) | §1の「未実施・来週以降の課題」参照 |

---

Sources: 本レポートの内容はすべて内部ドキュメントの参照および今回の実機検証によるもので、外部情報源の引用はなし。

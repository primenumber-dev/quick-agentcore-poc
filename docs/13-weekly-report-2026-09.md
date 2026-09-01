# 今週の検証レポート(2026-08-31〜09-02): セキュリティ脆弱性修正・DCR実装・コストシミュレーター・関連調査

> この章で分かること
> [00-handoff.md §12](./00-handoff.md)で合意した今週の3項目(DCR実装・応答時間チューニング・コストシミュレーター)を中心に実施した検証・実装の全体像をまとめる。個別の詳細は[08](./08-weekly-verification-plan.md)〜[12](./12-mcp-protocol-v2-upgrade-impact.md)番の各ドキュメントを参照し、本レポートはその統合サマリーとして位置づける。

実施期間: 2026-08-31〜2026-09-02 | 検証環境: playgroundアカウント(883660531246)、`terraform-playground-pattern4`

---

## TL;DR

| # | 項目 | 状態 | 結果概要 |
|---|---|---|---|
| 1 | 【最重要】クロステナントなりすまし脆弱性 | ✅ 発見・修正・再検証済み | AgentCore Runtime経路で、有効なJWTを持つ任意の利用者が`x-cognito-sub`ヘッダーを書き換えるだけで他テナントになりすませる脆弱性を実機確認。設定変更のみ(コード変更・再デプロイ不要)で即日修正([09](./09-cross-tenant-impersonation-finding.md)) |
| 2 | DCR(動的クライアント登録)実装 | ✅ 実装・実機動作確認済み | RFC 7591準拠の`POST /register`とLambda Authorizerを`terraform-playground-pattern4`に実装。登録→認可→失効までエンドツーエンドで確認([10](./10-dcr-implementation.md)) |
| 3 | DCRセキュリティレビュー | ✅ 完了・3件修正済み | 実装直後にセキュリティレビューを実施し、High 2件・Medium 1件を確定・修正(無審査アクセス権付与、スコープ未検証、失効の最大5分遅延)([10 §4.5](./10-dcr-implementation.md)) |
| 4 | インタラクティブなコストシミュレーター | ✅ Artifact公開済み | AgentCore vs ECSの月額コストをリクエスト数・VPC・WAF条件で試算。既存ドキュメントの14数値を再現することを検証済み([08 §4.5](./08-weekly-verification-plan.md)) |
| 5 | Cognito→Auth0移行見積もり | ✅ 机上調査完了 | AgentCore RuntimeホスティングのままDCRを実現する代替経路として調査。技術的に成立する見込みだが、月額$800〜の新規コスト・データレジデンシー懸念あり([11](./11-cognito-to-auth0-migration-estimate.md)) |
| 6 | MCPプロトコルv2(2026-07-28)影響調査 | ✅ 机上調査完了 | 実在する仕様と確認。新SDKはデフォルトで旧クライアントとの両対応を提供する設計だが、現状ベータ版のため今すぐの移行は時期尚早([12](./12-mcp-protocol-v2-upgrade-impact.md)) |
| 7 | 応答時間チューニング(Phase 0) | ❌ 未着手 | セッションID使い回し仮説の検証は次回以降に持ち越し |

---

## 1. 【最重要】クロステナントなりすまし脆弱性の発見・修正

応答時間チューニングの設計調査中に、AgentCore Runtime経路のアプリコード(`extractSub()`)が`x-cognito-sub`ヘッダーを無条件に信頼していることに気づいた。ECS経路ではAPI Gatewayが検証済みの値で強制上書きする保護があるが、**AgentCore Runtime経路には同等の保護が存在しなかった**。

実機で検証したところ、有効な自分のJWTを持ちながら`x-cognito-sub`ヘッダーに別テナントのsubを指定するだけで、そのテナントとして認可されることを確認した(クロステナントなりすまし)。原因はAgentCore Runtimeの`requestHeaderConfiguration.requestHeaderAllowlist`に`x-cognito-sub`が含まれていたこと。**`update-agent-runtime`でこのヘッダーを許可リストから外すだけで、コード変更・再デプロイ不要で修正**でき、修正後は同じ手法でのなりすましが失敗することを再検証した。

詳細な構造比較図・攻撃シナリオ図は[09-cross-tenant-impersonation-finding.md](./09-cross-tenant-impersonation-finding.md)を参照。

## 2. DCR(動的クライアント登録)実装

[00-handoff.md §12.1](./00-handoff.md)で合意した選択肢B(Cognitoの手前に立つ自作DCRプロキシ)を、`terraform-playground-pattern4`(ECS+API Gateway)に実装した。

**なぜAgentCore Runtimeではなくpattern4で実装したか**: AgentCore Runtimeには`/register`を追加できる層が存在せず、認可方式(`allowedClients`固定リスト)もLambda Authorizerに差し替え不可能なため、現時点の仕様ではDCRを実装できないと判明した([10 §0](./10-dcr-implementation.md))。

**実装内容**: 既存のJWT型AuthorizerをLambda(REQUEST型)Authorizerに置き換え、RFC 7591準拠の`POST /register`エンドポイントを新設。実機で次を確認した。

- 既存の静的クライアントの回帰確認(切替後も無停止)
- DCRでの新規クライアント登録(authorization_code・client_credentials両方)
- 登録したclient_credentialsクライアントでのMCP呼び出し成功
- DynamoDBの失効フラグによる即時アクセス遮断

## 3. DCRセキュリティレビューと修正

実装直後に`/security-review`スキルでレビューし、4件の候補を独立エージェントによる誤検知フィルタリングにかけた結果、3件を確定・修正した。

| 重大度 | 内容 | 修正 |
|---|---|---|
| High | `POST /register`が匿名でclient_credentials登録を受け付け、無審査で正規テナントと同じアクセス権を即座に付与していた | 自動プロビジョニングを廃止。アクセス許可には別途admin操作が必要に |
| High | Lambda Authorizerがscopeクレームを検証しておらず、invokeスコープを持たないクライアントでも`/mcp`が通ってしまう | scope検証を追加 |
| Medium | Authorizerの結果が5分キャッシュされ、失効操作が最大5分遅延して反映される | キャッシュTTLを0に短縮 |

いずれも実機で修正・再検証済み。詳細は[10-dcr-implementation.md §4.5](./10-dcr-implementation.md)。

## 4. インタラクティブなコストシミュレーター

AgentCore Runtime vs ECS+API Gatewayの月額コストを、リクエスト数・VPC・WAF条件に応じて試算するArtifactを実装・公開した([AgentCore vs ECS コスト比較](https://claude.ai/code/artifact/8f9d8cfc-aec8-4eb2-8970-6e3e1947f8c3))。設計段階で、既存の`02-cost-simulation.md`の数値を逆算したところ、ALB LCU・CloudFront平均レスポンスサイズという2つの未記載パラメータや、既存の損益分岐点が簡略化式によるものだったことが判明し、これらを踏まえたモデルで実装した。既存ドキュメントの14個の掲載数値を許容誤差$0.5以内で再現することを確認済み。詳細は[08-weekly-verification-plan.md §4](./08-weekly-verification-plan.md)。

## 5. Cognito→Auth0移行見積もり(派生調査)

DCR実装の過程で「AgentCore Runtimeでは構造的にDCRができない」ことが判明した際、根本原因が実はAgentCore Runtime自体ではなく**Cognitoが`aud`クレームを発行しない仕様**にあることが分かった。DCR対応かつ`aud`を正しく発行するIdP(Auth0等)に乗り換えれば、AgentCore Runtimeの`allowedAudience`を固定運用でき、Runtimeホスティングのままでも DCR が成立する可能性がある。この経路のコスト・移行リスクを机上で見積もった。

- エンジニアリング工数: 約7〜10人日
- **追加コスト**: Auth0のDCR機能はProfessionalプラン以上必須で、月額$800〜(B2B)。エンタープライズSSO接続は5件までしか含まれず、6社目以降は月額$10,000超のプランが必要になる崖がある
- データレジデンシー(Auth0は米国企業SaaS)・本番41ユーザーの移行リスクは要検討

詳細は[11-cognito-to-auth0-migration-estimate.md](./11-cognito-to-auth0-migration-estimate.md)。

## 6. MCPプロトコルv2(2026-07-28)影響調査(派生調査)

新規開発(Step1以降)でMCPプロトコルバージョン「2026-07-28」を採用する方針を受け、対応SDKへのアップグレードが既存クライアントとの互換性にどう影響するかを調査した。「2026-07-28」は実在する正式な仕様改訂で、`Mcp-Session-Id`ヘッダーのプロトコルコアからの除外を含む大きな変更を伴う。新SDK(v2、現状ベータ)は旧世代クライアントとの両対応をデフォルトでサポートする設計だが、単純なバージョンアップではなく新APIサーフェスへの移行が必要。AgentCore Runtime側は既に追随済みでリスクは低いと判断。詳細は[12-mcp-protocol-v2-upgrade-impact.md](./12-mcp-protocol-v2-upgrade-impact.md)。

## 7. 未着手: 応答時間チューニング(Phase 0)

[00-handoff.md §12.2](./00-handoff.md)で合意していた「セッションID使い回しでコールドスタートを回避できるか」の検証は、今週は着手できなかった。次回セッションの優先課題として持ち越す。手順は[08-weekly-verification-plan.md §3](./08-weekly-verification-plan.md)に整理済み。

## 参考リンク

- [08-weekly-verification-plan.md](./08-weekly-verification-plan.md) — 実装前プラン・見積もり改訂の詳細
- [09-cross-tenant-impersonation-finding.md](./09-cross-tenant-impersonation-finding.md) — セキュリティ脆弱性の詳細レポート
- [10-dcr-implementation.md](./10-dcr-implementation.md) — DCR実装の詳細・セキュリティレビュー結果
- [11-cognito-to-auth0-migration-estimate.md](./11-cognito-to-auth0-migration-estimate.md) — Auth0移行見積もり
- [12-mcp-protocol-v2-upgrade-impact.md](./12-mcp-protocol-v2-upgrade-impact.md) — MCPプロトコルv2影響調査
- [コストシミュレーター(Artifact)](https://claude.ai/code/artifact/8f9d8cfc-aec8-4eb2-8970-6e3e1947f8c3)

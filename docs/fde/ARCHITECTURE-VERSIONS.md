# アーキテクチャバージョン台帳

> この章で分かること
> quick-mcp-poc の MCP 基盤を、LLM のモデル名と同じ「バリアント + バージョン + 日付」で管理するための台帳。各バージョンに何が含まれ、何が検証済みで、何が未解決かを一覧する。git タグと AWS リソースタグに同じ文字列を貫通させ、「今動いているのはどのバージョンか」を一意に特定できるようにする。

作成日: 2026-09-15 | 対象: primenumber 内部資料(FDE 成果物)

---

## 命名規則

```
quick-mcp-<variant>-<major>.<minor>-<YYYYMMDD>
例: quick-mcp-ecs-1.4-20260915
```

| 要素 | 意味 |
|---|---|
| `variant` | ホスティング方式。`ecs`(本採用)と `agentcore`(代替構成) |
| `major.minor` | 構成の世代。マイナーは週次の検証サイクルごとに繰り上げる |
| `YYYYMMDD` | そのバージョンを確定した日 |

同一の文字列を次の 5 箇所に貫通させる。

| 適用先 | 形式 | 現状 |
|---|---|---|
| git タグ | `quick-mcp-ecs-1.4-20260915` | 適用済み(SSH 署名付き) |
| AWS リソースタグ | `McpBaseVersion` | 未適用(フェーズ2で `provider` の `default_tags` に追加) |
| ECR イメージタグ | 同上(コミットハッシュと併記) | 未適用 |
| ECS タスク定義 family | `quick-mcp-ecs-1-4` | 未適用 |
| MCP サーバーの `serverInfo.version` | `1.4.0` | 未適用(`server/src/index.ts` は `1.0.0` 固定) |

---

## バージョン一覧(ecs バリアント)

| バージョン | 日付 | MCP SDK | 認可 | エッジ防御 | 主な検証内容 |
|---|---|---|---|---|---|
| `quick-mcp-ecs-1.0-20260903` | 2026-09-03 | v1 | Lambda Authorizer + DCR | なし | AgentCore Runtime と ECS の比較、DCR 実装、クロステナントなりすまし脆弱性の発見と修正 |
| `quick-mcp-ecs-1.1-20260903` | 2026-09-03 | v1 | 同上 | なし | 応答時間チューニング(セッション ID 再利用による microVM 再利用)、ECS 本番化の課題整理 |
| `quick-mcp-ecs-1.2-20260910` | 2026-09-10 | **v2** | 同上 | ALB に一時アタッチ(検証のみ) | MCP プロトコル v2 への書き換えと機能テスト 32 項目合格、ECS 構成への WAF 適用を初検証 |
| `quick-mcp-ecs-1.3-20260914` | 2026-09-14 | v2 | 同上 + aud 検証 + deny-on-missing | **CloudFront + WAF(Block)** | DCR の RFC 7591 準拠性(不合格 16→2)、攻撃 16 件遮断・誤検知ゼロ、REST API 移行の見送り判断 |
| `quick-mcp-ecs-1.4-20260915` | 2026-09-15 | v2 | 同上 | 同上 | 全成果を main へ集約、依存脆弱性 46 件を解消。Terraform 製品化の起点 |

### agentcore バリアント

Week1〜2 で AgentCore Runtime を検証したが、リソースは AWS CLI で作成されており **Terraform 化されていない**ため、現時点でタグ付けできるコード状態が存在しない。フェーズ2で `infra/modules/mcp-server-agentcore/` を作成した時点で `quick-mcp-agentcore-1.0-<日付>` を発番する。

検証結果そのものは [03-internal-agentcore-runtime-verification.md](../03-internal-agentcore-runtime-verification.md) と [07-internal-vpc-waf-cost-verification.md](../07-internal-vpc-waf-cost-verification.md) に残っている。

---

## 各バージョンの既知の課題

| バージョン | 未解決事項 |
|---|---|
| 1.0 | 本番相当の JWT Authorizer に `audience` バグ(正当なトークンでも常に 401)。WAF 未対応 |
| 1.1 | 同上。ECS 本番化の課題 5 件が未着手 |
| 1.2 | WAF は ALB への一時アタッチのみで恒久設定なし。DCR の RFC 準拠性は未検証 |
| 1.3 | `WWW-Authenticate` 未対応(HTTP API の制約)、RFC 7592 未実装、Claude からの自己登録 E2E が未実施 |
| 1.4 | Terraform が特定アカウント前提のままで納品不可。ECS サービスが Terraform 管理外(ecspresso 所有)。CI/CD なし |

現在の詳細な充足状況は [20-internal-production-readiness-checklist.md](../20-internal-production-readiness-checklist.md) を参照。

---

## 運用ルール

1. 週次の検証サイクルが完了したらマイナーを繰り上げ、`main` に署名付きタグを打つ。
2. タグのメッセージには「何が検証済みか」を書く。コミットメッセージの繰り返しにしない。
3. AWS リソースへは `McpBaseVersion` タグで同じ文字列を付与し、`aws resourcegroupstaggingapi get-resources` で環境とバージョンの対応を引けるようにする。
4. 納品時は、QUICK 様環境へ適用したバージョンを本台帳に記録する。

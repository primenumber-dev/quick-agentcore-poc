# `mcp-server-agentcore`(スタブ)

## このモジュールが空である理由

**空なのは作業喪失ではなく、未着手である。**

`terraform/` と `terraform-playground-pattern4/` の全 `.tf` を検索した結果、**AgentCore 関連のリソース定義は 1 件も存在しなかった**。ヒットしたのは次の 3 件のコメントと、プロファイル名 `quick-agentcore-poc-playground` の部分一致だけである([docs/23-internal-weekly-verification-plan-week6.md §2.1](../../../docs/23-internal-weekly-verification-plan-week6.md))。

| 該当 | 内容 |
|---|---|
| `terraform-playground-pattern4/ecs.tf:86` | 実際に読まれるのは AgentCore Runtime 検証で作成済みのテーブルである旨の注記 |
| `terraform-playground-pattern4/cognito.tf:38` | `scripts/invoke_agentcore_mcp_jwt.py` 等を参照せよという注記 |
| `terraform-playground-pattern4/ssm.tf:3` | AgentCore Runtime 側の検証と同様である旨の注記 |

AgentCore Runtime は **`scripts/invoke_agentcore_mcp*.py` を起点に AWS CLI で作成されており、一度も Terraform 化されたことがない**。したがって本モジュールは「移行」ではなく **新規作成** であり、他の 7 モジュールのように移行元コードを変数化したものではない。[docs/fde/ARCHITECTURE-VERSIONS.md](../../../docs/fde/ARCHITECTURE-VERSIONS.md) の「タグ付けできるコード状態が存在しない」という記述と整合する。

## 現在の内容

- `variables.tf` — **想定インタフェースの宣言のみ**。すべて既定値付きで、どの変数も現時点では使われていない。
- `outputs.tf` — `agentcore_runtime_arn` と `invoke_endpoint` の 2 出力。参照先リソースが無いため **値は `null` のプレースホルダ**である。
- `main.tf` は存在しない。リソースを 1 件も作らないため、このモジュールを呼び出しても plan には何も現れない。

## 参考実装

[`docs/terraform-examples/agentcore-vpc-mode/main.tf`](../../../docs/terraform-examples/agentcore-vpc-mode/main.tf)(263 行)が関連する参考実装である。ただしこれは **VPC モード検証専用の別物**であり、そのまま本モジュールの中身にはならない。リポジトリ内で唯一 `variable` ブロックを持つ Terraform コードでもある。

## 実装時にやること

1. 参考実装と `scripts/invoke_agentcore_mcp*.py` が実際に発行している AWS CLI 呼び出しを突き合わせ、稼働中の Runtime 設定を確定させる。
2. 稼働中の Runtime を新規作成ではなく `import` する(再作成するとエンドポイントが変わる)。
3. `quick-mcp-agentcore-1.0-<日付>` のタグを発番する。発番は実装時に行うことになっている。

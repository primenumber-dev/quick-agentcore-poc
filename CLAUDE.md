# quick-mcp-poc: AgentCore Runtime移行検証

このリポジトリは、MCPサーバー(TypeScript, `server/`)を Amazon Bedrock AgentCore Runtime にデプロイし、既存のAPI Gateway + ECS構成と比較検証するためのプロジェクト。

**作業を再開する場合は、まず [`docs/00-handoff.md`](./docs/00-handoff.md) を読むこと。** 前回セッションの状況、使用しているAWSアカウント2つの使い分け、作成済みAWSリソース、既知のはまりどころがまとまっている。

技術文書一式は [`docs/README.md`](./docs/README.md) を起点に参照する。

## 最重要の注意点

- AWSアカウントを2つ使い分けている。**`quick-agentcore-poc`プロファイル(本番相当、620369151795)には実クライアントデータがあるため書き込み厳禁**。検証・実験は`quick-agentcore-poc-playground`プロファイル(883660531246)で行うこと。
- シェルで`brew`/`aws`等が見つからない場合は `eval "$(/opt/homebrew/bin/brew shellenv)"` を実行する。

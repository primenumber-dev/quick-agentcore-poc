---
name: resume
description: Resume work on quick-agentcore-poc at the start of a new session by reading the handoff memo and checking environment/AWS state before doing anything else. Use this whenever the user asks to continue this project, says "作業を再開", "続きから", or opens a new session on this repo without other context.
---

# quick-agentcore-poc セッション再開スキル

新しいセッションでこのプロジェクトの作業を再開する際に使う。前回セッションの状況を把握しないまま作業を始めると、既に発見済みの問題を再発見したり、書き込み禁止のアカウントを誤って触るリスクがある。

## 手順

1. **`CLAUDE.md`を読む**(プロジェクトルート)。特にAWSアカウントの使い分け(2つのプロファイル)を再確認する。
2. **`docs/00-handoff.md`を読む**。末尾に最新の「セッション完了サマリー」セクションがあるはずなので、まずそこを読む(冒頭の日付が古い場合、末尾ほど新しい追記がある構成になっている)。
3. **`docs/README.md`**でドキュメント一覧・読み方フローチャートを確認し、直近の番号のドキュメント(最新の検証レポート)にも目を通す。
4. **AWS SSOトークンの有効性を確認する**(両プロファイルとも高頻度で失効するため、まずここでつまずく):
   ```bash
   aws sts get-caller-identity --profile quick-agentcore-poc-playground
   aws sts get-caller-identity --profile quick-agentcore-poc  # 本番相当、書き込み禁止
   ```
   失効していたら、ユーザーに`aws sso login --profile <profile>`の実行を依頼する(ブラウザ操作が必要なため代行できない)。
5. **git状態を確認する**:
   ```bash
   git status --short
   git log --oneline -5
   git fetch origin && git status -sb   # ahead/behind の確認
   ```
   未pushコミットが残っていないか、作業ツリーに未コミットの変更が残っていないかを確認する。
6. **ローカル環境の残留プロセスを確認する**(Docker/LocalStack起動しっぱなしの可能性):
   ```bash
   docker compose -f compose.yml ps 2>/dev/null
   ```

## 再開後の第一声で必ず伝えること

- 完了済み/未着手の項目(handoffの最新サマリーから)
- SSOトークンの状態(失効していれば再ログインを依頼)
- 次に何をするか、ユーザーの指示を待つ

## 絶対に守ること(CLAUDE.mdより再掲)

- `quick-agentcore-poc`プロファイル(本番相当、620369151795)には**実クライアントデータがあるため書き込み厳禁**。検証・実験は`quick-agentcore-poc-playground`プロファイル(883660531246)のみで行う。
- シェルで`brew`/`aws`等が見つからない場合は`eval "$(/opt/homebrew/bin/brew shellenv)"`を実行する。
- `~/.aws`・`~/.ssh`等はサンドボックスで読み書き保護されている。AWS CLI・git署名関連の操作は`dangerouslyDisableSandbox: true`が必要になることが多い(ユーザーの事前承認を得た上で使用する)。

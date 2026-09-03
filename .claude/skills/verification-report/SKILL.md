---
name: verification-report
description: Create or update a quick-agentcore-poc verification report following the project's established format (TL;DR table, AWS/Mermaid diagrams with explanations, no emoji, cited sources) and render it to PDF via scripts/render-pdf.sh. Use whenever the user asks to "検証レポートを作成", "レポートにまとめて", "PDFにして", or wants a new numbered docs/NN-*.md report.
---

# quick-agentcore-poc 検証レポート作成スキル

このリポジトリ(`docs/00-handoff.md`が起点)で新しい検証レポートを作成する、または既存レポートをPDF化する際に使う。既存の`docs/06`〜`docs/13`が参照実装。

## レポートの標準フォーマット

```markdown
# <タイトル: 何を検証・調査したか>

> この章で分かること
> <2〜4文。何のために・何を・どう調べて・何が分かったか>

作成日: YYYY-MM-DD | 検証方法: <実機検証(playgroundアカウント名/リソース) or 机上調査(参照した公式ドキュメント等)>

---

## TL;DR

| # | 論点 | 結論 |
|---|---|---|
| 1 | ... | ... |

---

## 1. <セクション>
...
### 図の解説
必ずMermaid図の直後に「**図の解説**: ...」という説明文を1段落つける。図だけで終わらせない。

---

Sources:  (Web検索/公式ドキュメントを根拠にした場合のみ。内部docsへの参照は本文中インラインリンクで良い)
- [タイトル](URL)
```

## 厳守事項

- **絵文字は一切使わない**(✅❌⚠️等も含む)。状態は「確認済み」「未実施」等の日本語で表現する。作成後に必ず機械チェックする:
  ```bash
  grep -c '[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]' docs/NN-*.md
  ```
  0件であること。
- **本文中の出典は逆参照ではなくインラインリンク**(`[06-xxx.md](./06-xxx.md)`)。文末に「参照」とだけ書かない。
- Mermaidは`flowchart`/`sequenceDiagram`を使う。`quadrantChart`はGitHub上で崩れるリスクがあるため避ける。エッジラベル内の改行は`<br/>`(生の`\n`は非対応)。`subgraph`名に日本語・記号を含む場合は`subgraph id["表示名"]`の形でクォートする。
- AWSアーキテクチャ図(コンポーネント構成図)が必要な場合は`mcp__awsdac__generateDiagramToFile`を使い、`docs/images/<name>.png`に保存して`![説明](./images/<name>.png)`で埋め込む。**Mermaidで手書きしない**(公式アイコンでの構成図が本プロジェクトの標準)。
- 作成後、`docs/README.md`の目次テーブルに1行追加し、[リンク切れチェック](#リンク切れチェック)を実行する。

## リンク切れチェック

```bash
python3 - <<'EOF'
import re, os, glob
md_files = ["README.md"] + glob.glob("docs/**/*.md", recursive=True)
broken = []
for md in md_files:
    base = os.path.dirname(md)
    content = open(md, encoding="utf-8").read()
    for m in re.finditer(r'!?\[[^\]]*\]\(([^)]+)\)', content):
        link = m.group(1)
        if link.startswith(("http://", "https://", "#", "mailto:")):
            continue
        link_path = link.split("#")[0]
        if not link_path:
            continue
        target = os.path.normpath(os.path.join(base, link_path))
        if not os.path.exists(target):
            broken.append((md, link, target))
print("BROKEN:" if broken else "No broken links.")
for b in broken: print(b)
EOF
```

## PDF化(scripts/render-pdf.sh)

```bash
./scripts/render-pdf.sh docs/NN-your-report.md
# 生成物: docs/NN-your-report.pdf
```

前提: `pandoc`・Google Chromeがインストール済みであること。`dangerouslyDisableSandbox: true`が必要(pandoc/npm/Chromeの実行に伴うファイルアクセスのため)。

**既知の注意点**:
1. コマンドが2分でタイムアウト表示になっても、実際にはバックグラウンドで生成が完了していることが多い。`ls -la docs/NN-*.pdf`のタイムスタンプで確認してから再実行を判断すること。
2. **Mermaid図が複数(目安10個超)ある文書では、図同士が誤った位置に重なって描画されるバグが過去にあった**(2026-09-02修正済み)。原因は`mermaid.run()`の一括処理。`scripts/render-pdf.sh`は既に「図ごとに`mermaid.render(id, definition)`を個別呼び出しする」方式に修正済みなので通常は発生しないが、**生成後は必ず全ページを目視確認すること**:
   ```bash
   pdfinfo docs/NN-your-report.pdf | grep Pages
   pdftoppm -png -f <page> -l <page> -r 150 docs/NN-your-report.pdf /tmp/out/pageN
   # Readツールで画像を確認
   ```
   特にMermaid図を含むページは重点的に確認する。
3. 太字(`**text**`)の直前・直後が全角カッコ「」等だとCommonMarkのflanking ruleで`<strong>`化されず`**`が生テキストのまま残ることがある。pandoc変換後のHTMLを`grep '\*\*'`で機械チェックすると確実。

## レビュー体制(絵文字・出典・Mermaid構文などを厳密にチェックしたい場合)

過去のセッションで有効だった手法: **査読専用エージェント(Explore、編集不可)→修正専用エージェント(general-purpose、編集可)の2段階**に分離する。1つのエージェントに両方させると指摘の見落としを自分でごまかすリスクがあるため。査読エージェントには「一時ファイル作成は`$TMPDIR`配下なら可、対象ファイルの編集のみ禁止」のように制約を具体的に切り分けて指示すること(曖昧に禁止すると`mmdc`インストール等で無限に粘って失敗することがある)。

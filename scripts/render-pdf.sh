#!/bin/bash
# docs/配下のMarkdownレポートをPDF化するスクリプト。
# Mermaid図はChromeのfile://オリジンからESモジュールとして読み込むため、
# --allow-file-access-from-files が必須(無いとCORSでモジュール読み込みに失敗する)。
#
# 使い方:
#   ./scripts/render-pdf.sh docs/07-vpc-waf-cost-verification-client.md
#
# 前提:
#   - pandoc, Google Chrome がインストールされていること
#   - npm install mermaid が実行済みであること(本スクリプトが自動実行する)
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "使い方: $0 <docs配下のMarkdownファイル>" >&2
  exit 1
fi

MD_FILE="$1"
MD_BASENAME=$(basename "$MD_FILE" .md)
DOCS_DIR=$(cd "$(dirname "$MD_FILE")" && pwd)
IMAGES_DIR="$DOCS_DIR/images"

WORKDIR="${TMPDIR:-/tmp}/render-pdf-$$"
mkdir -p "$WORKDIR"

if [ ! -d "$WORKDIR/node_modules/mermaid" ]; then
  (cd "$WORKDIR" && npm install mermaid --silent)
fi
MERMAID_MJS="$WORKDIR/node_modules/mermaid/dist/mermaid.esm.min.mjs"

cat > "$WORKDIR/header.html" <<'EOF'
<meta charset="utf-8">
<style>
  @import url('https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@400;500;700&display=swap');
  body {
    font-family: "Noto Sans JP", "Hiragino Sans", "Yu Gothic", sans-serif;
    line-height: 1.75; color: #1a1a1a; max-width: 900px; margin: 0 auto; padding: 24px; font-size: 15px;
  }
  h1, h2, h3 { line-height: 1.4; margin-top: 1.6em; margin-bottom: 0.6em; }
  h1 { font-size: 24px; border-bottom: 3px solid #0a7463; padding-bottom: 8px; }
  h2 { font-size: 19px; border-bottom: 1px solid #ddd; padding-bottom: 4px; }
  h3 { font-size: 16px; color: #0a7463; }
  table { border-collapse: collapse; width: 100%; margin: 1em 0; font-size: 13px; }
  th, td { border: 1px solid #ccc; padding: 6px 10px; text-align: left; vertical-align: top; }
  th { background: #f0f7f5; }
  code { background: #f5f5f5; padding: 1px 4px; border-radius: 3px; font-size: 0.9em; }
  pre:not(.mermaid) { background: #f5f5f5; padding: 12px; border-radius: 6px; overflow-x: auto; font-size: 12px; }
  pre.mermaid { text-align: center; background: white; }
  blockquote { border-left: 4px solid #0a7463; margin-left: 0; padding-left: 1em; color: #444; background: #fafafa; }
  img { max-width: 100%; display: block; margin: 1em auto; }
  a { color: #0a7463; }
  hr { border: none; border-top: 1px solid #ddd; margin: 2em 0; }
</style>
EOF

cat > "$WORKDIR/postprocess.py" <<'PYEOF'
import html
import re
import sys

src_path, dst_path, images_dir_abs, mermaid_mjs_abs = sys.argv[1:5]

with open(src_path, "r", encoding="utf-8") as f:
    content = f.read()

def replace_mermaid(m):
    return f'<pre class="mermaid">\n{html.unescape(m.group(1))}\n</pre>'

content = re.sub(
    r'<pre[^>]*class="[^"]*mermaid[^"]*"[^>]*>\s*<code[^>]*>(.*?)</code>\s*</pre>',
    replace_mermaid,
    content,
    flags=re.DOTALL,
)

def replace_img(m):
    filename = m.group(2).split("/")[-1]
    return f'src="file://{images_dir_abs}/{filename}"'

content = re.sub(r'src="(\./)?images/([^"]+)"', replace_img, content)

mermaid_script = f'''
<script type="module">
  import mermaid from "file://{mermaid_mjs_abs}";
  mermaid.initialize({{ startOnLoad: true, theme: "default" }});
  await mermaid.run();
</script>
</body>'''
content = content.replace("</body>", mermaid_script)

with open(dst_path, "w", encoding="utf-8") as f:
    f.write(content)
PYEOF

pandoc -f gfm -t html5 --standalone \
  --metadata title="$MD_BASENAME" \
  -H "$WORKDIR/header.html" \
  -o "$WORKDIR/report_raw.html" \
  "$MD_FILE"

python3 "$WORKDIR/postprocess.py" \
  "$WORKDIR/report_raw.html" \
  "$WORKDIR/report_final.html" \
  "$IMAGES_DIR" \
  "$MERMAID_MJS"

OUTPUT_PDF="$DOCS_DIR/$MD_BASENAME.pdf"

"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new \
  --disable-gpu \
  --no-sandbox \
  --allow-file-access-from-files \
  --user-data-dir="$WORKDIR/chrome-profile" \
  --print-to-pdf="$OUTPUT_PDF" \
  --print-to-pdf-no-header \
  --virtual-time-budget=20000 \
  --no-pdf-header-footer \
  "file://$WORKDIR/report_final.html"

echo "生成完了: $OUTPUT_PDF"

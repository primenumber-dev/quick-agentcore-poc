"""ハーネスの結果JSONから docs/20-production-readiness-checklist.md の状態列を更新する。

docs/20 の各行は固定ID(WAF-10、7591-01 等)を持つ。本スクリプトは
scripts/dcr_conformance_tests.py / scripts/waf_attack_tests.py の --report 出力を読み、
IDが対応する行の「状態」「最終実施」「証跡」列だけを書き換える(要件・根拠・検証方法は触らない)。

使い方:
  python3 scripts/update_checklist.py docs/evidence/2026-09-13-dcr-baseline.json --env playground
  python3 scripts/update_checklist.py docs/evidence/2026-09-13-waf-baseline.json --env playground \
      --label "基準線(WAF未適用)"

  --label を付けると、合否ではなく「検証中(<label>)」として記録する(基準線取得など、
  合否判定の前提が揃っていない実行に使う)。

対応規則:
  - DCR: 結果ID "7591-09a" は行 "7591-09" に集約される(末尾の英字を除いた一致)。
    複数結果がある場合、FAIL が1つでもあれば不合格、全て PASS なら合格、INFO のみなら要確認。
  - WAF: 攻撃パターンID(A01 等)は下記 WAF_MAP で WAF-1x 行に集約される。
"""
import argparse
import json
import re
import sys

CHECKLIST = "docs/20-production-readiness-checklist.md"

WAF_MAP = {
    "WAF-01": ["A02r", "A01t", "A05w", "A01a"],
    "WAF-10": ["A01"],
    "WAF-11": ["A02"],
    "WAF-12": ["A03", "A04"],
    "WAF-13": ["A05", "A06", "A07"],
    "WAF-14": ["A08", "A09", "A10", "A11"],
    "WAF-15": ["A12", "A13"],
    "WAF-16": ["A14", "A15", "A23"],
    "WAF-17": ["A16"],
    "WAF-18": ["A17", "A18"],
    "WAF-19": ["A19", "A20", "A21"],
    "WAF-20": ["A24"],
    "WAF-21": ["A25"],
}

STATUS_JA = {"PASS": "合格", "FAIL": "不合格", "INFO": "要確認", "SKIP": "未着手"}


def waf_row_for(result_id):
    for row, prefixes in WAF_MAP.items():
        for p in prefixes:
            if result_id == p or (result_id.startswith(p) and not result_id[len(p):].isalpha() and not result_id[len(p):][:1].isdigit()):
                return row
            if result_id.startswith(p) and p in ("A25",) and result_id[len(p):].startswith("-"):
                return row
    return None


def dcr_row_for(result_id):
    return re.sub(r"[a-z]$", "", result_id)


def aggregate(statuses):
    if "FAIL" in statuses:
        return "FAIL"
    if "PASS" in statuses:
        return "PASS"
    if "INFO" in statuses:
        return "INFO"
    return "SKIP"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("report")
    ap.add_argument("--env", default="playground")
    ap.add_argument("--label", help="合否ではなく「検証中(<label>)」として記録する")
    ap.add_argument("--checklist", default=CHECKLIST)
    args = ap.parse_args()

    data = json.load(open(args.report, encoding="utf-8"))
    run_date = data.get("run_at", "")[:10]
    is_waf = "run_id" in data
    per_row = {}
    for r in data["results"]:
        row = waf_row_for(r["id"]) if is_waf else dcr_row_for(r["id"])
        if not row:
            continue
        per_row.setdefault(row, []).append(r)

    lines = open(args.checklist, encoding="utf-8").read().split("\n")
    updated = []
    for i, line in enumerate(lines):
        m = re.match(r"^\| ([A-Z0-9]+-\d+) \|", line)
        if not m or m.group(1) not in per_row:
            continue
        row_id = m.group(1)
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 8:
            continue
        results = per_row[row_id]
        agg = aggregate([r["status"] for r in results])
        if args.label:
            state = f"検証中({args.label})"
        else:
            state = STATUS_JA[agg]
        if agg in ("FAIL", "INFO") and not args.label:
            worst = next((r for r in results if r["status"] == agg), results[0])
            state += f": {worst['detail'][:60]}".replace("|", "/")
        cells[5] = state
        cells[6] = f"{run_date} {args.env}"
        cells[7] = f"[{args.report.split('/')[-1]}](./evidence/{args.report.split('/')[-1]})"
        lines[i] = "| " + " | ".join(cells) + " |"
        updated.append((row_id, state))

    open(args.checklist, "w", encoding="utf-8").write("\n".join(lines))
    for row_id, state in updated:
        print(f"  {row_id:<9} -> {state}")
    print(f"{len(updated)} rows updated in {args.checklist}")
    if not updated:
        sys.exit(1)


if __name__ == "__main__":
    main()

"""WAF ログ(CloudWatch Logs)と scripts/waf_attack_tests.py の結果を X-Waf-Test-Id で突合する。

各リクエストに付与した `X-Waf-Test-Id: <run-id>-<A##>` を WAF ログの httpRequest.headers から拾い、
パターンごとに action(ALLOW/BLOCK/COUNT)、terminatingRuleId、付与ラベル、clientIp を集約する。
WAF-02(真のクライアントIPか VPC Link ENI か)と WAF-1x(どのルールが反応したか)の証跡になる。

使い方:
  python3 scripts/waf_log_correlate.py --log-group aws-waf-logs-quick-mcp-poc-alb-probe \
      --report docs/evidence/2026-09-13-waf-alb-count.json --my-ip $(curl -s https://checkip.amazonaws.com)

  --report を渡すと、その JSON の run_id を使ってログを絞り込み、結果に waf_log フィールドを書き戻す。
  --run-id で直接指定してもよい。--minutes は検索範囲(既定 60 分)。

前提: AWS CLI(playground プロファイル)。WAF ログは数十秒〜数分遅れて到着するため、テスト直後は少し待つ。
"""
import argparse
import json
import os
import subprocess
import sys
import time

DEFAULT_PROFILE = "quick-agentcore-poc-playground"


REGION = "ap-northeast-1"


def aws(profile, *args):
    return json.loads(subprocess.run(["aws", "--profile", profile, "--region", REGION, "--output", "json", *args],
                                     check=True, capture_output=True, text=True).stdout or "{}")


def fetch_events(profile, log_group, run_id, minutes):
    """filter-log-events で run_id を含む生ログを全ページ取得する(Logs Insights は取り込み遅延で取りこぼすことがある)。"""
    end = int(time.time() * 1000)
    start = end - minutes * 60 * 1000
    events = []
    token = None
    while True:
        args = ["logs", "filter-log-events", "--log-group-name", log_group, "--start-time", str(start), "--end-time", str(end),
                "--filter-pattern", f'"{run_id}"', "--limit", "1000"]
        if token:
            args += ["--next-token", token]
        res = aws(profile, *args)
        events.extend(e["message"] for e in res.get("events", []))
        token = res.get("nextToken")
        if not token:
            break
    return events


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--log-group", required=True)
    ap.add_argument("--report", help="waf_attack_tests.py の結果JSON(run_id を読み、結果を書き戻す)")
    ap.add_argument("--run-id")
    ap.add_argument("--minutes", type=int, default=60)
    ap.add_argument("--my-ip", help="検証端末の公開IP(WAF-02 判定用)")
    ap.add_argument("--profile", default=DEFAULT_PROFILE)
    ap.add_argument("--region", default="ap-northeast-1", help="CLOUDFRONT スコープの WAF ログは us-east-1")
    args = ap.parse_args()
    global REGION
    REGION = args.region

    report = json.load(open(args.report, encoding="utf-8")) if args.report else None
    run_id = args.run_id or (report or {}).get("run_id")
    if not run_id:
        sys.exit("--run-id または --report が必要です")

    # ヘッダ名の大文字小文字は WAF ログで送信時のまま残るため、run_id の文字列一致で生ログを取り Python 側で解析する
    raw_rows = fetch_events(args.profile, args.log_group, run_id, args.minutes)
    rows = []
    labels_by_test = {}
    counted_by_test = {}
    for msg in raw_rows:
        try:
            m = json.loads(msg)
        except (json.JSONDecodeError, TypeError):
            continue
        req = m.get("httpRequest", {})
        tid = next((h.get("value") for h in req.get("headers", []) if str(h.get("name", "")).lower() == "x-waf-test-id"), None)
        if not tid or run_id not in tid:
            continue
        rows.append({
            "testId": tid, "action": m.get("action"), "terminatingRuleId": m.get("terminatingRuleId"),
            "terminatingRuleType": m.get("terminatingRuleType"), "clientIp": req.get("clientIp"),
            "uri": req.get("uri"), "method": req.get("httpMethod"), "country": req.get("country"),
            "@timestamp": m.get("timestamp"),
        })
        labels_by_test.setdefault(tid, set()).update(l.get("name") for l in m.get("labels", []) if isinstance(l, dict))
        counted_by_test.setdefault(tid, set()).update(
            f"{x.get('ruleId')}({x.get('action')})" for x in m.get("nonTerminatingMatchingRules", []) if isinstance(x, dict)
        )
        for g in m.get("ruleGroupList", []) or []:
            gid = str(g.get("ruleGroupId", "")).split("/")[-1]
            for x in g.get("nonTerminatingMatchingRules", []) or []:
                counted_by_test[tid].add(f"{gid}:{x.get('ruleId')}({x.get('action')})")
            if g.get("terminatingRule"):
                counted_by_test[tid].add(f"{gid}:{g['terminatingRule'].get('ruleId')}(TERMINATING)")
    rows.sort(key=lambda x: x.get("@timestamp") or 0)

    by_test = {}
    for r in rows:
        tid = r.get("testId")
        by_test.setdefault(tid, []).append(r)

    print(f"run_id={run_id}  matched log rows={len(rows)}")
    ips = set()
    for tid in sorted(by_test):
        r = by_test[tid][-1]
        ips.add(r.get("clientIp"))
        pat = tid.split("-", 2)[-1] if tid.count("-") >= 2 else tid
        print(f"  {pat:<8} {r.get('action'):<6} rule={r.get('terminatingRuleId'):<28} ip={r.get('clientIp'):<16} "
              f"counted={sorted(counted_by_test.get(tid, []))[:4]} labels={sorted(labels_by_test.get(tid, []))[:4]}")

    verdict = None
    if args.my_ip:
        import ipaddress
        public = [i for i in ips if i and not ipaddress.ip_address(i).is_private]
        verdict = ("真のクライアントIP" if (args.my_ip in ips or public) else "VPC Link ENI 等に集約") + f"({sorted(i for i in ips if i)})"
        print(f"\nWAF-02: WAF が見た送信元IP = {sorted(i for i in ips if i)} / 検証端末 = {args.my_ip} → {verdict}")

    if report is not None:
        for res in report["results"]:
            tid = res.get("test_header")
            if tid in by_test:
                last = by_test[tid][-1]
                res["waf_log"] = {
                    "action": last.get("action"), "terminatingRuleId": last.get("terminatingRuleId"),
                    "clientIp": last.get("clientIp"), "country": last.get("country"),
                    "labels": sorted(labels_by_test.get(tid, [])), "counted": sorted(counted_by_test.get(tid, [])),
                }
        report["waf_log_summary"] = {"log_group": args.log_group, "client_ips_seen": sorted(i for i in ips if i),
                                     "my_ip": args.my_ip, "waf02_verdict": verdict, "matched_rows": len(rows)}
        with open(args.report, "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
        print(f"written back to {args.report}")


if __name__ == "__main__":
    main()

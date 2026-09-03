#!/usr/bin/env python3
"""claude-code-actionのexecution_fileを読み、BigQueryのraw_executionsテーブルに記録する。

execution_fileは`claude -p --output-format json`相当のJSON実行ログ。
複数ターンにわたる場合はJSON Lines形式になりうるため、両方に対応する。
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone

from google.cloud import bigquery


def load_records(execution_file: str) -> list[dict]:
    with open(execution_file, encoding="utf-8") as f:
        content = f.read().strip()

    if not content:
        return []

    lines = [line for line in content.splitlines() if line.strip()]
    records = []
    try:
        for line in lines:
            records.append(json.loads(line))
    except json.JSONDecodeError:
        records = [json.loads(content)]
    return records


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execution-file", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--issue-number", type=int, default=None)
    parser.add_argument("--pr-number", type=int, default=None)
    parser.add_argument("--project", required=True)
    parser.add_argument("--dataset", default="claude_usage")
    parser.add_argument("--table", default="raw_executions")
    args = parser.parse_args()

    records = load_records(args.execution_file)
    if not records:
        print(f"execution_fileが空です: {args.execution_file}", file=sys.stderr)
        return 1

    result_record = next(
        (r for r in reversed(records) if r.get("type") == "result"), records[-1]
    )
    total_cost_usd = result_record.get("total_cost_usd")
    payload = records[0] if len(records) == 1 else records

    row = {
        "run_id": args.run_id,
        "executed_at": datetime.now(timezone.utc).isoformat(),
        "issue_number": args.issue_number,
        "pr_number": args.pr_number,
        "total_cost_usd": total_cost_usd,
        # JSON型カラムには生のオブジェクトを渡す。事前にjson.dumps()で文字列化すると
        # 文字列として二重にエンコードされてしまう。
        "payload": payload,
    }

    client = bigquery.Client(project=args.project)
    table_id = f"{args.project}.{args.dataset}.{args.table}"
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
    )
    load_job = client.load_table_from_json([row], table_id, job_config=job_config)
    load_job.result()

    print(f"usageを記録しました: run_id={args.run_id}, total_cost_usd={total_cost_usd}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

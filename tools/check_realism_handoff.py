#!/usr/bin/env python3
"""Check shared EXP20 sources/evidence without requiring a map download or Godot."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RECORD = ROOT / "data/reports/realism_rework/20261017/summary.json"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepared", action="store_true", help="Also require ignored, regenerated runtime inputs")
    args = parser.parse_args()
    summary = json.loads(RECORD.read_text())
    failures, deferred = [], []
    checked = 0
    for row in summary["files"]:
        if row["kind"] == "generated_runtime_input" and not args.prepared:
            deferred.append(row["path"])
            continue
        path = ROOT / row["path"]
        if not path.is_file():
            failures.append({"path": row["path"], "reason": "missing"})
        elif hashlib.sha256(path.read_bytes()).hexdigest() != row["sha256"]:
            failures.append({"path": row["path"], "reason": "different_from_recorded_snapshot"})
        checked += 1
    for report in summary["acceptance_reports"]:
        data = json.loads((ROOT / report["path"]).read_text())
        if data.get("result") != "PASS" or data.get("summary", {}).get("failed") != 0:
            failures.append({"path": report["path"], "reason": "not_a_passed_report"})
    print(json.dumps({"result": "FAIL" if failures else "PASS", "files_checked": checked,
                      "acceptance_reports": len(summary["acceptance_reports"]),
                      "recorded_engine_checks": summary["engine_checks"],
                      "prepared_inputs_deferred": deferred, "failures": failures,
                      "scope": "Stored payload integrity only; does not rerun engine tests, establish current terrain integration, or accept another Mac's rendering/performance."},
                     ensure_ascii=False))
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()

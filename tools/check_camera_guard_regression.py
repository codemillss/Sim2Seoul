#!/usr/bin/env python3
"""Actual engine regression: remove final corner-overlap guard in a disposable copy."""
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from check_camera_contract import FILES, ROOT
from check_camera_evidence import audit


def main():
    output = ROOT/"data/cache/camera_guard"
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=output)
    parser.add_argument("--engine", type=Path, default=Path("/Applications/Godot.app/Contents/MacOS/Godot"))
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="sim2seoul-p03-guard-") as tmp:
        game = Path(tmp)/"game"
        for name in FILES:
            target = game/name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT/"game"/name, target)
        path = game/"scripts/player/camera_rig.gd"
        source = path.read_text()
        predicate = "if _overlaps_at(current_distance):"
        if source.count(predicate) != 1:
            raise ValueError("Camera guard changed; review this targeted regression")
        path.write_text(source.replace(predicate, "if false and _overlaps_at(current_distance):"))
        result = output/"guard_disabled.json"
        cmd = ["/usr/bin/sandbox-exec", "-f", str(ROOT/"tests/game/offline.sb"), str(args.engine),
               "--headless", "--fixed-fps", "60", "--path", str(game), "--script", str(ROOT/"tests/game/check_camera_test.gd"),
               "--log-file", str(output/"guard_disabled.log"), "--", "--automatic-probe", "--result="+str(result)]
        ran = subprocess.run(cmd, capture_output=True, text=True, timeout=40)
        log = re.sub(r"\x1b\[[0-9;]*m", "", ran.stdout+ran.stderr)
        if ran.returncode or "ERROR:" in log or "SCRIPT ERROR" in log or not result.exists():
            raise ValueError("Guard fault did not produce measurements: "+log[:1600])
        record = json.loads(result.read_text())
        scored = audit(record)
        failed = [c["name"] for c in scored["checks"] if not c["passed"]]
        report = {"task": "P03", "case": "actual_guard_source_disabled", "passed": not scored["passed"]
                  and "corner_orbit.all_tick_stats" in failed, "checker_passed": scored["passed"], "failed_checks": failed,
                  "actual_source_change": predicate+" -> if false and ... in copied rig only",
                  "source_sha256": hashlib.sha256(source.encode()).hexdigest(),
                  "mutated_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                  "original_unchanged": (ROOT/"game/scripts/player/camera_rig.gd").read_text()==source,
                  "scope": "offline accelerated engine; actual source fault, no original or P02 change"}
        report["passed"] = report["passed"] and report["original_unchanged"]
        for name, value in [("guard_disabled_check.json", scored), ("guard_regression.json", report)]:
            (output/name).write_text(json.dumps(value, separators=(",", ":"), allow_nan=False)+"\n")
        print(f"P03 actual guard regression: passed={report['passed']}, failed checks={failed}")
        return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

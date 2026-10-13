#!/usr/bin/env python3
"""P03 offline actual engine observations in a minimal copied game (stdlib only)."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from check_camera_evidence import audit
from check_movement_contract import FILES as P02_FILES

ROOT = Path(__file__).resolve().parents[1]
FILES = [*P02_FILES, "scenes/player/camera_rig.tscn", "scripts/player/camera_rig.gd",
         "scenes/tests/camera_test.tscn", "scripts/camera_test.gd"]
MUTATIONS = {"mask_disabled": "contract.mask", "self_exclusion_removed": "self_exclusion.explicit",
             "wrong_player_camera": "contract.player_camera", "unclamped_pitch": "clamps.limits",
             "menu_capture_leak": "menu_input.pause"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def put(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)+"\n")


def main(engine, output, mode):
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    checks, mutants = [], []
    sources = {name: sha(ROOT/"game"/name) for name in FILES}

    def check(name, ok, **details):
        checks.append({"name": name, "passed": bool(ok), **details})

    check("engine.version", subprocess.check_output([str(engine), "--version"], text=True).strip()
          == "4.7.2.stable.official.ed1daf0bf")
    with tempfile.TemporaryDirectory(prefix="sim2seoul-p03-") as tmp:
        game = Path(tmp)/"game"
        for name in FILES:
            target = game/name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT/"game"/name, target)
        check("copy.authored_only", not (game/"resources").exists() and not (game/"data").exists()
              and not (game/".godot").exists(), file_count=len(FILES))

        def run(label, case="normal", gpu=False, fps=60):
            result = output/(label+".json")
            log_file = output/(label+".log")
            result.parent.mkdir(parents=True, exist_ok=True)
            cmd = ["/usr/bin/sandbox-exec", "-f", str(ROOT/"tests/game/offline.sb"), str(engine)]
            if not gpu:
                cmd += ["--headless", "--fixed-fps", "60"]
            cmd += ["--path", str(game), "--script", str(ROOT/"tests/game/check_camera_test.gd"),
                    "--log-file", str(log_file), "--", "--automatic-probe", "--result="+str(result),
                    "--suite="+("gpu" if gpu else "full"), "--case="+case, "--render-fps="+str(fps)]
            if gpu and fps==60:
                cmd += ["--capture-prefix="+str(output/"view")]
            ran = subprocess.run(cmd, capture_output=True, text=True, timeout=180 if gpu else 40)
            log = re.sub(r"\x1b\[[0-9;]*m", "", ran.stdout+ran.stderr)
            if ran.returncode or "SCRIPT ERROR" in log or "ERROR:" in log or not result.exists():
                raise ValueError(f"P03 engine measurement failed ({label}): {log[:2000]}")
            record = json.loads(result.read_text())
            scored = audit(record)
            put(output/(label+"_check.json"), scored)
            print(f"P03 {label}: {len(scored['checks'])} checks, passed={scored['passed']}", flush=True)
            return record, scored

        if mode == "contract":
            normal, scored = run("headless_engine")
            check("normal.full", scored["passed"], checks=len(scored["checks"]))
            repeated, scored = run("repeat_engine")
            check("repeat.full", scored["passed"])
            check("repeat.contract", normal["contract"] == repeated["contract"])
            by_name = lambda r: {c["name"]: c for c in r["cases"]}
            a, b = by_name(normal), by_name(repeated)
            check("repeat.camera_paths", all(a[n]["samples"] == b[n]["samples"] for n in
                  ["open_idle", "follow_walk", "follow_run", "wall_orbit", "corner_orbit", "lintel_orbit"]))
            for case, expected in MUTATIONS.items():
                _, scored = run("regression/"+case, case=case)
                failed = [c["name"] for c in scored["checks"] if not c["passed"]]
                check("regression."+case, not scored["passed"] and expected in failed)
                mutants.append({"case": case, "checker_passed": scored["passed"], "expected_failure": expected,
                                "failed_checks": failed, "evidence": "regression/"+case+".json"})
        else:
            for fps in (30, 60):
                _, scored = run(f"gpu_{fps}_engine", gpu=True, fps=fps)
                check(f"actual_gpu.{fps}", scored["passed"], checks=len(scored["checks"]))
        check("authored_inputs_unchanged", sources == {name: sha(ROOT/"game"/name) for name in FILES})
    report = {"task": "P03", "mode": mode, "passed": all(c["passed"] for c in checks), "checks": checks,
              "actual_mutations": mutants, "sources": sources,
              "probe_sha256": sha(ROOT/"tests/game/check_camera_test.gd"),
              "checker_sha256": sha(ROOT/"tools/check_camera_evidence.py"), "orchestrator_sha256": sha(Path(__file__)),
              "network": "deny network*", "scope": "13 authored files, no maps/runtime/cache/extra packages; current M1",
              "headless_capture": "simulated intent only; native mode remains visible, real capture required by GPU suite",
              "not_tested": ["human handling", "OS-driven focus loss", "Seoul collision/Daehanmun", "M4", "city performance"]}
    put(output/(mode+"_check.json"), report)
    print(f"P03 {mode}: passed={report['passed']}, checks={len(checks)}", flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, default=Path("/Applications/Godot.app/Contents/MacOS/Godot"))
    parser.add_argument("--output", type=Path, default=ROOT/"data/cache/camera_contract")
    parser.add_argument("--mode", choices=["contract", "gpu"], default="contract")
    args = parser.parse_args()
    raise SystemExit(main(args.engine, args.output, args.mode))

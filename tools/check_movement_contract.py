#!/usr/bin/env python3
"""P02 actual offline engine cases in a fresh authored-only game copy.

contract: accelerated physics, repeat process and actual faulty configuration.
gpu: real 30/60 render conditions and 60-second idle. Standard Python only.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from check_movement_evidence import audit

ROOT = Path(__file__).resolve().parents[1]
FILES = ["project.godot", "scenes/player/player.tscn", "scenes/tests/player_fixture.tscn",
         "scripts/player/idle_support.gd", "scripts/player_fixture.gd", "scripts/input_router.gd",
         "scenes/tests/movement_test.tscn", "scripts/player/movement_controller.gd", "scripts/movement_test.gd"]
MUTATIONS = {"speed_wrong": "walk.speed", "gravity_zero": "gravity_drop.gravity", "turn_zero": "turn_left.rotation",
             "mask_disabled": "contract.mask", "door_blocked": "door.count", "spawn_unsupported": "contract.spawn"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False)+"\n")


def main(engine, output, mode):
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    sources = {name: sha(ROOT/"game"/name) for name in FILES}
    checks, mutations = [], []

    def check(name, passed, **details):
        checks.append({"name": name, "passed": bool(passed), **details})

    version = subprocess.check_output([str(engine), "--version"], text=True).strip()
    check("engine.version", version == "4.7.2.stable.official.ed1daf0bf")
    with tempfile.TemporaryDirectory(prefix="sim2seoul-p02-") as temporary:
        game = Path(temporary)/"game"
        for name in FILES:
            target = game/name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT/"game"/name, target)
        check("copy.authored_only", not (game/"data").exists() and not (game/"resources").exists()
              and not (game/".godot").exists(), files=FILES)

        def run(label, suite="full", case="normal", gpu=False, fps=60, captures=False):
            result = output/(label+".json")
            log_file = output/(label+".log")
            result.parent.mkdir(parents=True, exist_ok=True)
            command = ["/usr/bin/sandbox-exec", "-f", str(ROOT/"tests/game/offline.sb"), str(engine)]
            if not gpu:
                command += ["--headless", "--fixed-fps", "60"]
            command += ["--path", str(game), "--script", str(ROOT/"tests/game/check_movement_test.gd"),
                        "--log-file", str(log_file), "--", "--result="+str(result), "--suite="+suite,
                        "--case="+case, "--render-fps="+str(fps)]
            if captures:
                command += ["--capture-prefix="+str(output/"view")]
            ran = subprocess.run(command, capture_output=True, text=True, timeout=100 if gpu else 35)
            log = re.sub(r"\x1b\[[0-9;]*m", "", ran.stdout+ran.stderr)
            if ran.returncode or "SCRIPT ERROR" in log or "ERROR:" in log or not result.is_file():
                raise ValueError(f"P02 actual engine did not finish ({label}): {log[:2000]}")
            evidence = json.loads(result.read_text())
            scored = audit(evidence)
            write(output/(label+"_check.json"), scored)
            print(f"P02 {label}: {len(scored['checks'])} checks, passed={scored['passed']}", flush=True)
            return evidence, scored

        if mode == "contract":
            normal, scored = run("headless_engine")
            check("normal.full", scored["passed"], checks=len(scored["checks"]))
            repeat, repeated = run("repeat_engine")
            check("repeat.full", repeated["passed"])
            a = {c["name"]: c for c in normal["cases"]}
            b = {c["name"]: c for c in repeat["cases"]}
            check("repeat.contract", normal["contract"] == repeat["contract"])
            check("repeat.distances", all(abs(a[n]["horizontal_distance_m"]-b[n]["horizontal_distance_m"]) < 1e-5
                  for n in ["walk", "run", "diagonal_walk", "diagonal_run"]))
            for case, expected in MUTATIONS.items():
                evidence, scored = run("regression/"+case, case=case)
                failed = [c["name"] for c in scored["checks"] if not c["passed"]]
                check("regression."+case, not scored["passed"] and expected in failed)
                mutations.append({"case": case, "expected_failed_check": expected, "checker_passed": scored["passed"],
                                  "failed_checks": failed, "evidence": "regression/"+case+".json"})
        else:
            for fps in (30, 60):
                _, scored = run(f"gpu_{fps}_engine", suite="timing", gpu=True, fps=fps, captures=fps==60)
                check(f"actual_gpu.timing_{fps}", scored["passed"], checks=len(scored["checks"]))
            _, scored = run("gpu_idle_engine", suite="idle", gpu=True)
            check("actual_gpu.idle_60_seconds", scored["passed"], checks=len(scored["checks"]))
        check("authored_inputs_unchanged", sources == {name: sha(ROOT/"game"/name) for name in FILES})
    report = {"task": "P02", "mode": mode, "passed": all(c["passed"] for c in checks), "checks": checks,
              "actual_mutations": mutations, "sources": sources,
              "probe_sha256": sha(ROOT/"tests/game/check_movement_test.gd"),
              "orchestrator_sha256": sha(Path(__file__)), "checker_sha256": sha(ROOT/"tools/check_movement_evidence.py"),
              "network": "deny network*", "scope": "authored-only copied project; existing M1, installed Godot; no map/cache/Python packages",
              "not_tested": ["human keyboard feel", "P03 orbit/occlusion", "Seoul collision/Daehanmun", "M4", "city performance"]}
    write(output/(mode+"_check.json"), report)
    print(f"P02 {mode}: passed={report['passed']}, checks={len(checks)}", flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, default=Path("/Applications/Godot.app/Contents/MacOS/Godot"))
    parser.add_argument("--output", type=Path, default=ROOT/"data/cache/movement_contract")
    parser.add_argument("--mode", choices=["contract", "gpu"], default="contract")
    args = parser.parse_args()
    raise SystemExit(main(args.engine, args.output, args.mode))

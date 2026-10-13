#!/usr/bin/env python3
"""P01 actual engine regression in a tiny authored game copy, with networking denied.

--fixed-fps runs 60 seconds of physics quickly; real 60s GPU observation is separate.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from check_player_fixture import audit

ROOT = Path(__file__).resolve().parents[1]
FILES = ["project.godot", "scenes/player/player.tscn", "scenes/tests/player_fixture.tscn",
         "scripts/player/idle_support.gd", "scripts/player_fixture.gd"]
CASES = {"player_scaled":"player_capsule_visual_and_contact", "collision_height":"player_capsule_visual_and_contact",
         "visual_offset":"player_capsule_visual_and_contact", "mask_disabled":"player_capsule_visual_and_contact",
         "collider_disabled":"player_capsule_visual_and_contact", "floor_disabled":"seven_static_boxes_and_opening",
         "spawn_below_floor":"initial_placement", "door_blocked":"seven_static_boxes_and_opening",
         "step_height_wrong":"seven_static_boxes_and_opening"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def put(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False)+"\n")


def main(engine,output):
    output=output.resolve()
    output.mkdir(parents=True,exist_ok=True)
    checks,variants=[],[]
    before={name:sha(ROOT/"game"/name) for name in FILES}

    def check(name,passed,**details):
        checks.append({"name":name,"passed":bool(passed),**details})

    check("engine.version",subprocess.check_output([str(engine),"--version"],text=True).strip()=="4.7.2.stable.official.ed1daf0bf")
    with tempfile.TemporaryDirectory(prefix="sim2seoul-p01-contract-") as temporary:
        game=Path(temporary)/"game"
        for name in FILES:
            target=game/name
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(ROOT/"game"/name,target)
        check("copy.authored_only",not (game/"data").exists() and not (game/"resources").exists() and not (game/".godot").exists())
        for case in ["normal",*CASES]:
            result=output/("headless_engine.json" if case=="normal" else "regression/"+case+".json")
            result.parent.mkdir(parents=True,exist_ok=True)
            log_file=output/("headless.log" if case=="normal" else "regression/"+case+".log")
            command=["/usr/bin/sandbox-exec","-f",str(ROOT/"tests/game/offline.sb"),str(engine),
                     "--headless","--fixed-fps","60","--path",str(game),"--script",str(ROOT/"tests/game/check_player_fixture.gd"),
                     "--log-file",str(log_file),"--","--result="+str(result),"--case="+case]
            ran=subprocess.run(command,capture_output=True,text=True,timeout=30)
            log=re.sub(r"\x1b\[[0-9;]*m","",ran.stdout+ran.stderr)
            if ran.returncode or "SCRIPT ERROR" in log or "ERROR:" in log:
                raise ValueError(f"Actual engine case failed to record ({case}): {log[:1800]}")
            record=json.loads(result.read_text())
            scored=audit(record)
            if case=="normal":
                put(output/"headless_check.json",scored)
                check("normal.engine_passed",scored["passed"],checks=len(scored["checks"]))
                normal_measurements=record["measurements"]
                # Same source scene rebuilt in a new engine process for reproducibility.
                command[command.index("--result="+str(result))]="--result="+str(Path(temporary)/"repeat.json")
                command[command.index(str(log_file))]=str(Path(temporary)/"repeat.log")
                repeated=subprocess.run(command,capture_output=True,text=True,timeout=30)
                if repeated.returncode:raise ValueError("P01 repeat process failed")
                other=json.loads((Path(temporary)/"repeat.json").read_text())
                check("normal.repeat_measurements",normal_measurements==other["measurements"])
                check("normal.repeat_stability",audit(other)["passed"])
            else:
                failed=[c["name"] for c in scored["checks"] if not c["passed"]]
                detected=not scored["passed"] and any(CASES[case].lower() in name.lower() for name in failed)
                check("regression."+case,detected)
                variants.append({"case":case,"engine_exit":ran.returncode,"checker_passed":scored["passed"],
                                 "expected_failure_keyword":CASES[case],"failed_checks":failed,
                                 "measurement_file":str(result.relative_to(output)),"sha256":sha(result)})
            print(f"P01 actual engine: {case} checked",flush=True)
    check("authored_inputs_unchanged",before=={name:sha(ROOT/"game"/name) for name in FILES})
    report={"task":"P01","passed":all(c["passed"] for c in checks),"checks":checks,"actual_mutations":variants,
            "sources":before,"checker_sha256":sha(Path(__file__)),"independent_checker_sha256":sha(ROOT/"tools/check_player_fixture.py"),
            "scope":"actual offline engine processes; 60 physics seconds accelerated with fixed-fps; existing M1 engine; no map/generated data",
            "not_tested":["60 real wall seconds in this accelerated run","keyboard movement","door passage","step traversal","camera control","Seoul collision","M4"]}
    put(output/"contract_check.json",report)
    print(f"P01 contract: {len(checks)} checks, passed={report['passed']}")
    return 0 if report["passed"] else 1


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine",type=Path,default=Path("/Applications/Godot.app/Contents/MacOS/Godot"))
    parser.add_argument("--output",type=Path,default=ROOT/"data/cache/player_contract")
    args=parser.parse_args()
    raise SystemExit(main(args.engine,args.output))

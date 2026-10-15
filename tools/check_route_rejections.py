#!/usr/bin/env python3
"""Replay N01 in-memory corruption cases and retain compact source snapshots.

No generator, engine, network call, dependency installation or prior-stage
regeneration is performed.  Mutation operations and exact snapshot hashes make
each rejection reproducible without retaining fifteen duplicate documents.
"""
from __future__ import annotations

import argparse
import copy
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = {"npc": "data/processed/npc_routes.json", "vehicle": "data/processed/vehicle_routes.json"}
CASES = [
    ("reversed_vehicle", "Reverse the southbound route's coordinate order.",
     [{"op": "reverse", "path": "/vehicle/routes/0/xz"}]),
    ("shifted_route", "Move an interior northbound point 0.1 m east.",
     [{"op": "add_number", "path": "/vehicle/routes/1/xz/3/0", "value": .1}]),
    ("nonfinite", "Replace a vehicle coordinate with nonfinite NaN.",
     [{"op": "nonfinite", "path": "/vehicle/routes/0/xz/0/0", "value": "NaN"}]),
    ("missing_source_hash", "Remove the retained G02 feature-file hash.",
     [{"op": "remove", "path": "/vehicle/provenance/data~1processed~1features.json"}]),
    ("missing_crossing", "Omit all southbound route crossing conflicts.",
     [{"op": "replace", "path": "/vehicle/routes/0/conflicts", "value": []}]),
    ("late_stop", "Place the stop station 0.1 m after body-contact entry.",
     [{"op": "copy_plus", "from": "/vehicle/routes/0/conflicts/0/enter_s_m",
       "path": "/vehicle/routes/0/conflicts/0/stop_s_m", "value": .1}]),
    ("wrong_stop_position", "Move the retained stop position to x=1000 m.",
     [{"op": "replace", "path": "/vehicle/routes/0/conflicts/0/stop_xz/0", "value": 1000.0}]),
    ("wrong_lane", "Reverse the authored right-side lane offset sign.",
     [{"op": "replace", "path": "/vehicle/routes/0/source_binding/right_offset_m", "value": -1.6}]),
    ("forged_road_domain", "Substitute the actor sweep for the source road domain.",
     [{"op": "copy", "from": "/vehicle/routes/0/swept_geometry", "path": "/vehicle/routes/0/road_domain"}]),
    ("crossing_removed_common", "Remove one of the three retained W03 crossings.",
     [{"op": "remove", "path": "/vehicle/crossings/2"}]),
    ("unsafe_unknown_policy", "Allow entry when occupancy is unknown.",
     [{"op": "replace", "path": "/vehicle/policy/unknown_occupancy", "value": "go"}]),
    ("controller_claim", "Claim that a runtime controller is implemented.",
     [{"op": "replace", "path": "/vehicle/scope/runtime_controller_implemented", "value": True}]),
    ("npc_outside_support", "Move a palace pedestrian point to x=1000 m.",
     [{"op": "replace", "path": "/npc/routes/0/xz/0/0", "value": 1000.0}]),
    ("npc_changed_repeat", "Replace the pedestrian ping-pong policy with teleportation.",
     [{"op": "replace", "path": "/npc/routes/0/repeat", "value": "teleport"}]),
    ("undersized_vehicle_sweep", "Shrink the actor sweep radius below the full body.",
     [{"op": "replace", "path": "/vehicle/actor/swept_radius_m", "value": .1}]),
]


def sha_bytes(raw):
    return hashlib.sha256(raw).hexdigest()


def node_at(documents, pointer):
    value = documents
    for component in pointer.lstrip("/").split("/"):
        key = component.replace("~1", "/").replace("~0", "~")
        value = value[int(key)] if isinstance(value, list) else value[key]
    return value


def parent_at(documents, pointer):
    before, last = pointer.rsplit("/", 1)
    parent = node_at(documents, before)
    key = last.replace("~1", "/").replace("~0", "~")
    return parent, int(key) if isinstance(parent, list) else key


def apply_operations(documents, operations):
    """Apply the small recorded JSON-pointer operation vocabulary."""
    for operation in operations:
        parent, key = parent_at(documents, operation["path"])
        kind = operation["op"]
        if kind == "remove":
            del parent[key]
        elif kind == "reverse":
            parent[key].reverse()
        elif kind == "replace":
            parent[key] = copy.deepcopy(operation["value"])
        elif kind == "add_number":
            parent[key] += operation["value"]
        elif kind == "nonfinite":
            if operation["value"] != "NaN":
                raise ValueError("Unsupported nonfinite mutation")
            parent[key] = float("nan")
        elif kind in ("copy", "copy_plus"):
            parent[key] = copy.deepcopy(node_at(documents, operation["from"]))
            if kind == "copy_plus":
                parent[key] += operation["value"]
        else:
            raise ValueError("Unknown mutation operation: " + kind)


def check(root=ROOT, output=None):
    root = Path(root).resolve()
    output = Path(output) if output else root / "data/reports/n01/rejections.json"
    if not output.is_absolute():
        output = root / output
    checker = root / "tools/check_routes.py"
    checker_hash = sha_bytes(checker.read_bytes())
    module_spec = importlib.util.spec_from_file_location("n01_independent_route_checker", checker)
    module = importlib.util.module_from_spec(module_spec)
    # Executing this module imports no generator and its __main__ CLI stays idle.
    module_spec.loader.exec_module(module)
    raw = {mode: (root / path).read_bytes() for mode, path in FILES.items()}
    documents = {mode: json.loads(payload) for mode, payload in raw.items()}
    originals = {path: sha_bytes(raw[mode]) for mode, path in FILES.items()}
    baseline = module.audit(root, documents["npc"], documents["vehicle"])
    if not baseline["passed"]:
        raise AssertionError("Normal route snapshots must pass before rejection tests: " +
                             ", ".join(c["name"] for c in baseline["checks"] if not c["passed"]))
    rows = []
    for name, description, operations in CASES:
        mutated = copy.deepcopy(documents)
        apply_operations(mutated, operations)
        verdict = module.audit(root, mutated["npc"], mutated["vehicle"])
        failures = [c["name"] for c in verdict["checks"] if not c["passed"]]
        rows.append({"name": name, "description": description, "operations": operations,
                     "rejected": not verdict["passed"], "rejected_by": failures})
    unchanged = (checker_hash == sha_bytes(checker.read_bytes()) and
                 all((root / path).read_bytes() == raw[mode] for mode, path in FILES.items()))
    output.parent.mkdir(parents=True, exist_ok=True)
    snapshots = []
    plan_dir = output.parent / "plans"
    plan_dir.mkdir(parents=True, exist_ok=True)
    for mode, source_path in FILES.items():
        target = plan_dir / (Path(source_path).name + ".gz")
        compressed = gzip.compress(raw[mode], compresslevel=9, mtime=0)
        target.write_bytes(compressed)
        assert gzip.decompress(target.read_bytes()) == raw[mode]
        snapshots.append({"source": source_path, "snapshot": str(target.relative_to(root)) if target.is_relative_to(root) else str(target),
                          "source_sha256": originals[source_path], "snapshot_sha256": sha_bytes(compressed),
                          "uncompressed_bytes": len(raw[mode])})
    report = {
        "schema_version": 1, "task": "N01", "passed": unchanged and all(r["rejected"] and r["rejected_by"] for r in rows),
        "checker": "tools/check_routes.py", "checker_sha256": checker_hash,
        "runner_sha256": sha_bytes(Path(__file__).read_bytes()), "original_output_sha256": originals,
        "baseline": {"passed": baseline["passed"], "check_count": len(baseline["checks"])},
        "source_provenance": documents["vehicle"]["provenance"], "snapshots": snapshots,
        "source_outputs_and_checker_unchanged": unchanged, "cases": rows,
        "scope": "Fifteen in-memory planning-snapshot corruptions only; no engine/controller acceptance, network, dependency reinstall, source-map acquisition or full predecessor regeneration",
    }
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    assert report["passed"], "At least one route mutation was accepted or retained input changed"
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = check(args.root, args.output)
    print(json.dumps({"task": "N01", "passed": report["passed"], "baseline_checks": report["baseline"]["check_count"],
                      "rejections": len(report["cases"]), "snapshots": len(report["snapshots"])}, ensure_ascii=False))


if __name__ == "__main__":
    main()

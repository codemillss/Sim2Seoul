#!/usr/bin/env python3
"""Independent, fail-closed P02 engine-evidence audit (no Godot execution)."""
import argparse
import json
import math
from pathlib import Path


def audit(record):
    checks = []

    def check(name, condition, details=None):
        item = {"name": name, "passed": bool(condition)}
        if details is not None:
            item["details"] = details
        checks.append(item)

    def number(value):
        return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)

    def vec(value):
        return isinstance(value, list) and len(value) == 3 and all(number(v) for v in value)

    def norm(value):
        return math.sqrt(sum(v * v for v in value)) if vec(value) else math.inf

    def near(value, target, tolerance):
        return number(value) and abs(value - target) <= tolerance

    def near_array(value, target, tolerance=1e-6):
        return isinstance(value, list) and len(value) == len(target) and all(near(v, t, tolerance) for v, t in zip(value, target))

    def wrapped_angle(value):
        return math.atan2(math.sin(value), math.cos(value))

    def actual_clock(c, name):
        check(name + ".actual_physics_clock", abs(c["wall_s"]-c["duration_s"]) <= .02*c["duration_s"],
              {"fields": ["cases." + name + ".wall_s", "cases." + name + ".duration_s"],
               "wall_s": c["wall_s"], "physics_s": c["duration_s"], "relative_limit": .02})

    def finite_tree(value, path="$", failures=None):
        failures = [] if failures is None else failures
        if isinstance(value, float) and not math.isfinite(value):
            failures.append(path)
        elif isinstance(value, dict):
            for key, child in value.items():
                finite_tree(child, path + "." + str(key), failures)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                finite_tree(child, f"{path}[{index}]", failures)
        return failures

    if not isinstance(record, dict):
        check("schema", False, {"field": "$", "error": "object required"})
        return {"passed": False, "checks": checks}
    invalid = finite_tree(record)
    check("finite_values", not invalid, {"invalid_fields": invalid})
    suite = record.get("suite")
    check("schema", record.get("schema_version") == 1 and record.get("task") == "P02"
          and suite in ("full", "timing", "idle") and isinstance(record.get("case"), str)
          and "scope" in record, {"fields": ["schema_version", "task", "suite", "case", "scope"]})
    engine = record.get("engine", {})
    contract = record.get("contract", {})
    if not isinstance(engine, dict):
        engine = {}
    if not isinstance(contract, dict):
        contract = {}
    check("engine", all(key in engine for key in ("version", "display", "renderer", "driver", "physics_hz", "render_cap_fps"))
          and near(engine.get("physics_hz"), 60, 0), {"field": "engine"})
    expected = {"walk_mps": 1.4, "run_mps": 3.5, "gravity_mps2": 9.8,
                "height": 1.7, "radius": .3, "layer": 2, "mask": 1,
                "physics_hz": 60, "static_count": 12}
    for key, target in expected.items():
        check("contract." + key, near(contract.get(key), target, 1e-6),
              {"field": "contract." + key, "expected": target, "actual": contract.get(key)})
    check("contract.turn", number(contract.get("turn_radians_per_second")) and contract["turn_radians_per_second"] > 0,
          {"field": "contract.turn_radians_per_second"})
    check("contract.spawn", near_array(contract.get("spawn"), [-2, .08, 2]) and contract.get("spawn_valid") is True,
          {"fields": ["contract.spawn", "contract.spawn_valid"]})
    check("contract.fixture", contract.get("camera_fixed") is True and contract.get("ramp_substitution") is True
          and near_array(contract.get("distance_floor_size"), [80, .2, 40]), {"field": "contract"})
    raw_cases = record.get("cases", [])
    valid_cases = isinstance(raw_cases, list) and all(isinstance(c, dict) and isinstance(c.get("name"), str) for c in raw_cases)
    names = [c["name"] for c in raw_cases] if valid_cases else []
    check("cases.structure", valid_cases and len(names) == len(set(names)), {"field": "cases"})
    cases = {c["name"]: c for c in raw_cases} if valid_cases else {}

    def get(name):
        c = cases.get(name)
        check(name + ".present", c is not None, {"field": "cases." + name})
        return c or {}

    def segment(c, name):
        required = ("duration_s", "wall_s", "ticks", "frames", "horizontal_distance_m", "path_m", "floor_ticks",
                    "min_y", "max_y", "max_abs_vy_mps", "max_xz_drift_m", "recoveries", "max_penetration_m",
                    "visual_yaw_start", "visual_yaw_end", "root_yaw")
        ok = all(number(c.get(k)) for k in required) and all(vec(c.get(k)) for k in ("start", "end", "final_velocity"))
        ok = ok and isinstance(c.get("input"), list) and isinstance(c.get("path_samples"), list) and len(c.get("path_samples", [])) >= 2
        samples = c.get("path_samples", [])
        if isinstance(samples, list):
            ok = ok and all(isinstance(s, dict) and number(s.get("t")) and vec(s.get("p"))
                            and isinstance(s.get("floor"), bool) and number(s.get("vy")) and number(s.get("yaw")) for s in samples)
        check(name + ".fields", ok, {"field": "cases." + name})
        if not ok:
            return False
        check(name + ".physical_time", c["duration_s"] > 0 and near(c["ticks"] / 60, c["duration_s"], .034)
              and 0 <= c["floor_ticks"] <= c["ticks"] and c["wall_s"] > 0 and c["frames"] >= 0
              and c["min_y"] <= c["max_y"] and c["path_m"] >= c["horizontal_distance_m"] - .001
              and c["horizontal_distance_m"] >= 0 and c["recoveries"] >= 0,
              {"field": "cases." + name})
        check(name + ".samples", all(samples[i]["t"] <= samples[i+1]["t"] for i in range(len(samples)-1))
              and samples[-1]["t"] - samples[0]["t"] >= c["duration_s"] - .1,
              {"field": "cases." + name + ".path_samples"})
        measured_xz = math.hypot(c["end"][0]-c["start"][0], c["end"][2]-c["start"][2])
        check(name + ".distance_consistency", near(c["horizontal_distance_m"], measured_xz, .005),
              {"field": "cases." + name + ".horizontal_distance_m", "computed_m": measured_xz})
        check(name + ".penetration", 0 <= c["max_penetration_m"] <= .005,
              {"field": "cases." + name + ".max_penetration_m", "actual": c["max_penetration_m"], "limit_m": .005})
        return True

    if suite in ("idle", "timing"):
        check("actual_gpu", str(engine.get("display", "")).lower() not in ("", "headless")
              and str(engine.get("renderer", "")).lower() not in ("", "headless"), {"field": "engine"})
    if suite in ("full", "idle"):
        c = get("idle")
        if segment(c, "idle"):
            check("idle.stability", c["duration_s"] >= 60-1e-6 and c["ticks"] >= 3600 and c["floor_ticks"] == c["ticks"]
                  and c["max_y"]-c["min_y"] <= .001 and c["max_xz_drift_m"] <= .001
                  and c["max_abs_vy_mps"] <= .001 and c["recoveries"] == 0,
                  {"field": "cases.idle"})
            # Root is the foot point; settled root Y independently checks contact.
            check("idle.foot_contact", abs(c["min_y"]) <= .002 and abs(c["max_y"]) <= .002,
                  {"fields": ["cases.idle.min_y", "cases.idle.max_y"]})
            if suite == "idle":
                check("idle.actual_time", c["wall_s"] >= 59, {"field": "cases.idle.wall_s"})
                actual_clock(c, "idle")
    if suite in ("full", "timing"):
        speed_names = ("walk", "run", "diagonal_walk", "diagonal_run") if suite == "full" else ("walk", "run")
        for name in speed_names:
            c = get(name)
            if segment(c, name):
                speed = 3.5 if "run" in name else 1.4
                check(name + ".speed", near(c["duration_s"], 10, .034)
                      and abs(c["horizontal_distance_m"] - speed*c["duration_s"]) <= .02*speed*c["duration_s"]
                      and c["recoveries"] == 0 and c["floor_ticks"] == c["ticks"],
                      {"field": "cases." + name, "expected_m": speed*c["duration_s"], "actual_m": c["horizontal_distance_m"]})
                if suite == "timing":
                    actual_clock(c, name)
                    cap = engine.get("render_cap_fps")
                    check(name + ".actual_fps", cap in (30, 60) and c["wall_s"] >= 9.5
                          and abs(c["frames"]/c["wall_s"] - cap) <= .2*cap,
                          {"field": "cases." + name, "observed_fps": c["frames"]/c["wall_s"]})
    if suite == "full":
        c = get("physical_key_dispatch")
        check("physical_key_dispatch.input", near_array(c.get("w_intent"), [0, -1])
              and near_array(c.get("arrow_intent"), [1, 0]) and c.get("shift_fast") is True,
              {"field": "cases.physical_key_dispatch"})
        for name in ("turn_left", "turn_right", "camera_relative", "gravity_drop", "step_up", "step_down", "slope_up", "slope_down"):
            c = get(name)
            if not segment(c, name):
                continue
            check(name + ".no_recovery", c["recoveries"] == 0 and near(c["root_yaw"], 0, .0001), {"field": "cases." + name})
            if name.startswith("turn_"):
                yaw = c.get("expected_yaw")
                check(name + ".rotation", near(c["duration_s"], 1, .034) and number(yaw)
                      and abs(math.atan2(math.sin(c["visual_yaw_end"]-yaw), math.cos(c["visual_yaw_end"]-yaw))) <= .05
                      and abs(c["visual_yaw_end"] - c["visual_yaw_start"]) > .1 and vec(c.get("end_direction")),
                      {"field": "cases." + name})
                rate = contract.get("turn_radians_per_second")
                smooth_ok = number(yaw) and number(rate) and rate > 0
                bad_samples = []
                if smooth_ok:
                    target_delta = wrapped_angle(yaw-c["visual_yaw_start"])
                    sign = 1 if target_delta >= 0 else -1
                    for i, sample in enumerate(c["path_samples"]):
                        expected = c["visual_yaw_start"] + sign*min(rate*sample["t"], abs(target_delta))
                        observed_delta = sign*wrapped_angle(sample["yaw"]-c["visual_yaw_start"])
                        if abs(wrapped_angle(sample["yaw"]-expected)) > .01 or not (-1e-6 <= observed_delta <= abs(target_delta)+1e-6):
                            bad_samples.append(i)
                check(name + ".smooth_rotation", smooth_ok and not bad_samples,
                      {"field": "cases." + name + ".path_samples", "invalid_samples": bad_samples,
                       "angle_tolerance_rad": .01, "overshoot_tolerance_rad": 1e-6})
            elif name == "camera_relative":
                expected_direction = c.get("expected_direction")
                delta = [c["end"][i]-c["start"][i] if i != 1 else 0 for i in range(3)]
                check(name + ".direction", vec(expected_direction) and norm(delta) > .1 and norm(expected_direction) > .1
                      and sum(a*b for a,b in zip(delta,expected_direction))/(norm(delta)*norm(expected_direction)) >= .99,
                      {"field": "cases.camera_relative.expected_direction"})
            elif name == "gravity_drop":
                check(name + ".gravity", near(c["start"][1], 2, .01) and c["max_abs_vy_mps"] > 1
                      and c["min_y"] < .01 and c["floor_ticks"] > 0, {"field": "cases.gravity_drop"})
                airborne = [s for s in c["path_samples"] if s["floor"] is False]
                observed_gravity = None
                if len(airborne) >= 2 and airborne[1]["t"] > airborne[0]["t"]:
                    observed_gravity = -(airborne[1]["vy"]-airborne[0]["vy"])/(airborne[1]["t"]-airborne[0]["t"])
                check(name + ".acceleration", number(observed_gravity) and near(observed_gravity, 9.8, .098),
                      {"field": "cases.gravity_drop.path_samples", "observed_mps2": observed_gravity,
                       "expected_mps2": 9.8, "relative_limit": .01})
            else:
                height = .3 if name.startswith("step") else 1
                upward = name.endswith("up")
                check(name + ".traversal", c["max_y"]-c["min_y"] >= height-.03
                      and (c["end"][1]-c["start"][1])*(1 if upward else -1) >= height-.03
                      and c["floor_ticks"] >= .9*c["ticks"] and c["min_y"] >= -.01,
                      {"field": "cases." + name})
        for angle in ("front", "oblique", "corner"):
            for speed in ("walk", "run"):
                name = f"wall_{angle}_{speed}"
                c = get(name)
                if segment(c, name):
                    check(name + ".contact", number(c.get("solid_contact_ticks")) and c["solid_contact_ticks"] > 0
                          and near(c["duration_s"], 3, .034) and c["recoveries"] == 0, {"field": "cases." + name})
        c = get("door_passages")
        passages = c.get("passages", [])
        check("door.count", c.get("forward_passes") == 10 and c.get("reverse_passes") == 10
              and c.get("completed") == 20 and isinstance(passages, list) and len(passages) == 20,
              {"field": "cases.door_passages"})
        if isinstance(passages, list):
            for i,p in enumerate(passages):
                name = f"door_passages.passages[{i}]"
                if isinstance(p, dict) and segment(p, name):
                    expected_z = (-2, -6) if p.get("direction") == "forward" else (-6, -2)
                    check(name + ".crossing", p.get("direction") in ("forward", "reverse")
                          and near(p["start"][2], expected_z[0], .1) and near(p["end"][2], expected_z[1], .1)
                          and p["recoveries"] == 0, {"field": "cases." + name})
                else:
                    check(name + ".structure", False, {"field": "cases." + name})
            check("door.directions", sum(p.get("direction") == "forward" for p in passages if isinstance(p,dict)) == 10
                  and sum(p.get("direction") == "reverse" for p in passages if isinstance(p,dict)) == 10,
                  {"field": "cases.door_passages.passages"})
        for name in ("fall_return", "outside_return", "manual_return"):
            c = get(name)
            pos = c.get("position_after")
            check(name + ".spawn", vec(c.get("position_before")) and vec(pos)
                  and norm([pos[i]-[-2, .08, 2][i] for i in range(3)]) <= .01
                  and c.get("spawn_valid") is True and c.get("floor_regained") is True
                  and c.get("reason") == c.get("expected_reason") and isinstance(c.get("reason"), str)
                  and c.get("recovery_count_delta") == 1 and near(c.get("visual_yaw_after"), 0, .001)
                  and norm(c.get("velocity_after")) <= .001, {"field": "cases." + name})
            check(name + ".input_latch", c.get("latched_after") is True and number(c.get("held_drift_m"))
                  and c["held_drift_m"] <= .001 and number(c.get("release_then_move_m")) and c["release_then_move_m"] > .1,
                  {"field": "cases." + name})
        c = get("edge_return")
        check("edge_return.recovery", isinstance(c.get("reason"), str) and bool(c["reason"])
              and c.get("recovery_count_delta") == 1 and c.get("spawn_valid") is True, {"field": "cases.edge_return"})
        c = get("menu_pause")
        check("menu_pause.freeze", c.get("paused") is True and c.get("actor_can_process") is False
              and c.get("ticks_during_pause") == 0 and near(c.get("paused_displacement_m"), 0, .001)
              and norm(c.get("velocity_when_paused")) <= .001, {"field": "cases.menu_pause"})
        check("menu_pause.input_latch", near(c.get("held_drift_after_close_m"), 0, .001)
              and number(c.get("release_then_move_m")) and c["release_then_move_m"] > .1, {"field": "cases.menu_pause"})
        c = get("invalid_spawn_guard")
        check("invalid_spawn_guard.reject", c.get("recovery_accepted") is False and c.get("position_unchanged") is True,
              {"field": "cases.invalid_spawn_guard"})
    return {"passed": all(c["passed"] for c in checks), "checks": checks}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        result = audit(json.loads(args.input.read_text(encoding="utf-8")))
    except (OSError, ValueError, TypeError, KeyError, IndexError) as exc:
        result = {"passed": False, "checks": [{"name": "read_or_schema", "passed": False, "details": str(exc)}]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

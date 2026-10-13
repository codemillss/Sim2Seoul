#!/usr/bin/env python3
"""Audit measured P01 geometry and idle support; no locomotion claims."""
import argparse
import json
import math
from pathlib import Path


IDENTITY = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
START = [-2, 0.08, 2]
BOXES = {
    "Floor": ([24, 0.2, 20], [0, -0.1, 0]),
    "Wall": ([3, 3, 0.25], [-7, 1.5, -4]),
    "DoorLeft": ([2.4, 3, 0.25], [-1.8, 1.5, -4]),
    "DoorRight": ([2.4, 3, 0.25], [1.8, 1.5, -4]),
    "DoorLintel": ([1.2, 0.8, 0.25], [0, 2.6, -4]),
    "Step015": ([2, 0.15, 2], [4, 0.075, 2]),
    "Step030": ([2, 0.3, 2], [6, 0.15, 2]),
}


def number(value):
    if type(value) not in (int, float) or not math.isfinite(value):
        raise ValueError("expected finite number, excluding bool")
    return value


def integer(value):
    value = number(value)
    if value != int(value):
        raise ValueError("expected integral count or bitmask")
    return int(value)


def vector(value):
    if not isinstance(value, list) or len(value) != 3:
        raise ValueError("expected three-number vector")
    return [number(x) for x in value]


def close(actual, expected, tolerance=1e-5):
    if isinstance(expected, list):
        if not isinstance(actual, list) or len(actual) != len(expected):
            raise ValueError("array dimensions differ")
        return all(close(a, b, tolerance) for a, b in zip(actual, expected))
    return abs(number(actual) - expected) <= tolerance


def transform(value, origin=None):
    vector(value["origin"])
    return close(value["basis"], IDENTITY) and (origin is None or close(value["origin"], origin))


def bounds(value, size, center):
    lo, hi = vector(value["min"]), vector(value["max"])
    return (integer(value["vertices"]) > 0
            and close(value["size"], size)
            and close(lo, [c - s / 2 for c, s in zip(center, size)])
            and close(hi, [c + s / 2 for c, s in zip(center, size)])
            and transform(value["transform"], center))


def finite_tree(value):
    if type(value) in (int, float):
        number(value)
    elif isinstance(value, dict):
        for child in value.values():
            finite_tree(child)
    elif isinstance(value, list):
        for child in value:
            finite_tree(child)


def audit(record, require_seconds=60.0, require_real_time=False):
    """Return a JSON-safe report; malformed records fail instead of raising."""
    checks = []

    def check(name, operation):
        try:
            passed = bool(operation())
            detail = "ok" if passed else "contract mismatch"
        except (KeyError, TypeError, ValueError, IndexError, AttributeError, OverflowError) as error:
            passed, detail = False, str(error)
        checks.append({"name": name, "passed": passed, "detail": detail})

    def schema():
        if not isinstance(record, dict):
            return False
        finite_tree(record)
        return (number(require_seconds) > 0 and type(require_real_time) is bool
                and record["task"] == "P01"
                and all(isinstance(record[k], str) and record[k] for k in
                        ("case", "engine", "display_server", "renderer", "driver", "scope")))

    check("schema_and_finite_numbers", schema)
    check("physics_rate", lambda: integer(record["physics_ticks_per_second"]) == 60)
    check("initial_placement", lambda: close(record["initial_position"], START)
          and close(record["initial_velocity"], [0, 0, 0])
          and number(record["settle_seconds"]) >= 1 - 1e-6)

    def parents():
        m = record["measurements"]
        return all(transform(m[k], [0, 0, 0]) for k in
                   ("fixture_transform", "fixtures_transform", "actors_transform"))

    check("unscaled_parents", parents)

    def player():
        p = record["measurements"]["player"]
        root = vector(p["root_transform"]["origin"])
        center = [root[0], root[1] + 0.85, root[2]]
        return (p["class"] == "CharacterBody3D" and p["collision_class"] == "CapsuleShape3D"
                and p["collision_disabled"] is False and p["floor"] is True
                and integer(p["layer"]) == 2 and integer(p["mask"]) == 1
                and close(p["height"], 1.7) and close(p["radius"], 0.3)
                and close(p["gravity_mps2"], 9.8) and close(p["safe_margin"], 0.001)
                and transform(p["root_transform"])
                and close([root[0], root[2]], [-2, 2]) and abs(root[1]) <= 0.002
                and all(abs(x) <= 0.001 for x in vector(p["velocity"]))
                and transform(p["collision_transform"], center)
                and bounds(p["visual"], [0.6, 1.7, 0.6], center))

    check("player_capsule_visual_and_contact", player)

    def fixtures():
        items = record["measurements"]["fixtures"]
        if not isinstance(items, list) or len(items) != len(BOXES):
            return False
        by_name = {item["name"]: item for item in items}
        if set(by_name) != set(BOXES):
            return False
        for name, (size, center) in BOXES.items():
            item = by_name[name]
            if not (item["type"] == "StaticBody3D" and item["disabled"] is False
                    and integer(item["layer"]) == 1 and integer(item["mask"]) == 2
                    and close(item["shape_size"], size)
                    and transform(item["shape_transform"], center)
                    and bounds(item["visual"], size, center)):
                return False
        left, right, lintel = [by_name[n] for n in ("DoorLeft", "DoorRight", "DoorLintel")]
        gap = (right["shape_transform"]["origin"][0] - right["shape_size"][0] / 2
               - left["shape_transform"]["origin"][0] - left["shape_size"][0] / 2)
        return (close(gap, 1.2)
                and close(lintel["shape_transform"]["origin"][1] - lintel["shape_size"][1] / 2, 2.2)
                and all(close(by_name[n]["shape_transform"]["origin"][1]
                              + by_name[n]["shape_size"][1] / 2, height)
                        for n, height in (("Step015", 0.15), ("Step030", 0.3))))

    check("seven_static_boxes_and_opening", fixtures)
    check("metre_reference_geometry", lambda:
          bounds(record["measurements"]["ruler"], [10, 0.025, 0.05], [0, 0.03, 6])
          and bounds(record["measurements"]["height_bar"], [0.03, 2, 0.03], [-1.2, 1, 2]))

    def queries():
        m = record["measurements"]
        expected = {"door_clear": [], "door_left": ["DoorLeft"], "door_right": ["DoorRight"],
                    "door_lintel": ["DoorLintel"], "wall": ["Wall"],
                    "step015": ["Step015"], "step030": ["Step030"]}
        return (all(m["queries"][key] == value for key, value in expected.items())
                and m["spawn_overlap"] == [] and m["spawn_support"] == "Floor"
                and close(m["spawn_xyz"], START)
                and close(m["spawn_support_position"], [-2, 0, 2]))

    check("actual_physics_queries_and_separate_spawn", queries)

    def observation():
        o = record["observation"]
        seconds, ticks = number(o["physics_seconds"]), integer(o["ticks"])
        low, high = number(o["min_y"]), number(o["max_y"])
        return (seconds >= number(require_seconds) - 1e-6
                and number(o["requested_seconds"]) >= require_seconds - 1e-6
                and ticks >= math.ceil(require_seconds * 60 - 1e-6)
                and close(seconds, ticks / 60, 1e-5)
                and integer(o["on_floor_ticks"]) == ticks
                and -0.002 <= low <= high <= 0.002 and high - low <= 0.001
                and 0 <= number(o["max_vertical_speed_mps"]) <= 0.001
                and 0 <= number(o["max_horizontal_drift_m"]) <= 0.001
                and number(o["wall_seconds"]) >= 0)

    check("all_tick_idle_summary", observation)

    def samples():
        o = record["observation"]
        items = o["samples_1hz"]
        ticks = integer(o["ticks"])
        expected_times = [1 / 60] + [t / 60 for t in range(60, ticks + 1, 60)]
        if not isinstance(items, list) or len(items) != len(expected_times):
            return False
        for sample, second in zip(items, expected_times):
            pos = vector(sample["position"])
            vy = abs(number(sample["velocity_y"]))
            if not (sample["floor"] is True and close(sample["physics_seconds"], second)
                    and abs(pos[1]) <= 0.002
                    and number(o["min_y"]) - 1e-6 <= pos[1] <= number(o["max_y"]) + 1e-6
                    and math.hypot(pos[0] + 2, pos[2] - 2) <= 0.001
                    and vy <= 0.001 and vy <= number(o["max_vertical_speed_mps"]) + 1e-6):
                return False
        return bool(items)

    check("one_hz_idle_samples", samples)
    if require_real_time:
        check("real_time_observation", lambda: number(record["observation"]["wall_seconds"])
              >= max(0, number(require_seconds) - 0.5))
    return {"passed": all(item["passed"] for item in checks), "checks": checks,
            "require_seconds": require_seconds if type(require_seconds) in (int, float)
            and math.isfinite(require_seconds) else None,
            "require_real_time": bool(require_real_time),
            "scope": "P01 synthetic fixture geometry and idle support only",
            "limitations": ["Capsule height is total height, including both caps.",
                            "Geometry and overlap queries do not prove door passage, walking, step traversal, third-person camera, or Seoul collision.",
                            "GPU appearance requires separate visual inspection; this audit consumes engine measurements."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--require-real-time", action="store_true")
    args = parser.parse_args()
    try:
        record = json.loads(args.input.read_text(encoding="utf-8"))
        report = audit(record, require_real_time=args.require_real_time)
    except (OSError, ValueError, RecursionError) as error:
        report = {"passed": False, "checks": [{"name": "input_read", "passed": False,
                                               "detail": str(error)}]}
    try:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
                               encoding="utf-8")
    except OSError as error:
        print(f"Cannot write audit report: {error}")
        return 1
    print("P01 audit: " + ("PASS" if report["passed"] else "FAIL"))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

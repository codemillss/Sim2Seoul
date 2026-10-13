#!/usr/bin/env python3
"""Independent fail-closed P03 evidence audit; does not execute Godot.

Recomputes geometry from retained 10Hz samples. Every-tick extrema/counts
come from the engine producer and bound gaps; they are not retained raw paths.
"""
import argparse
import json
import math
from pathlib import Path


def audit(record):
    checks = []

    def check(name, condition, details=None):
        result = {"name": name, "passed": bool(condition)}
        if details is not None:
            result["details"] = details
        checks.append(result)

    def num(v):
        return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)

    def vec(v, size=3):
        return isinstance(v, list) and len(v) == size and all(num(x) for x in v)

    def near(v, target, tol=1e-6):
        return num(v) and abs(v-target) <= tol

    def length(v):
        return math.sqrt(sum(x*x for x in v))

    def delta(a, b):
        return [x-y for x, y in zip(a, b)]

    def distance(a, b):
        return length(delta(a, b))

    def angle(a, b):
        return abs(math.atan2(math.sin(a-b), math.cos(a-b)))

    def finite(v):
        if isinstance(v, float):
            return math.isfinite(v)
        if isinstance(v, dict):
            return all(finite(x) for x in v.values())
        if isinstance(v, list):
            return all(finite(x) for x in v)
        return True

    if not isinstance(record, dict):
        return {"passed": False, "checks": [{"name": "schema.object", "passed": False}]}
    check("finite_values", finite(record))
    suite = record.get("suite")
    check("schema", record.get("schema_version") == 1 and record.get("task") == "P03"
          and suite in ("full", "gpu") and record.get("case") in
          ("normal", "fault", "mask_disabled", "self_exclusion_removed", "wrong_player_camera", "unclamped_pitch", "menu_capture_leak"))
    engine = record.get("engine", {})
    contract = record.get("contract", {})
    check("engine", isinstance(engine, dict) and all(k in engine for k in
          ("version", "display", "renderer", "driver", "physics_hz", "render_cap_fps"))
          and near(engine.get("physics_hz"), 60, 0))
    if not isinstance(contract, dict):
        contract = {}
    expected = {"walk_mps": 1.4, "run_mps": 3.5, "height": 1.7, "radius": .3,
                "pivot_height": 1.3, "sensitivity": .0025, "pitch_min": math.radians(-55),
                "pitch_max": math.radians(15), "min_distance": 2, "max_distance": 6,
                "default_distance": 4.5, "expansion_mps": 6, "mask": 1,
                "probe_radius": .2, "margin": .08, "near": .05, "fov": 65,
                "player_priority": 0, "arm_priority": 1, "rig_priority": 2}
    for key, value in expected.items():
        check("contract."+key, near(contract.get(key), value), {"expected": value, "actual": contract.get(key)})
    check("contract.player_camera", contract.get("player_camera_path_matches") is True)
    fixtures = record.get("fixtures")
    fixture_ok = isinstance(fixtures, list) and bool(fixtures) and all(isinstance(b, dict)
        and isinstance(b.get("name"), str) and vec(b.get("lo")) and vec(b.get("hi"))
        and all(a < z for a, z in zip(b["lo"], b["hi"])) for b in fixtures)
    check("fixtures", fixture_ok)
    boxes = fixtures if fixture_ok else []
    check("fixtures.unique", fixture_ok and len({b["name"] for b in boxes}) == len(boxes))
    raw = record.get("cases")
    structure = isinstance(raw, list) and all(isinstance(c, dict) and isinstance(c.get("name"), str) for c in raw)
    check("cases.structure", structure and len({c["name"] for c in raw}) == len(raw) if structure else False)
    cases = {c["name"]: c for c in raw} if structure else {}

    def get(name):
        check(name+".present", name in cases)
        return cases.get(name, {})

    if suite == "gpu":
        check("actual_gpu", isinstance(engine, dict) and str(engine.get("display", "")).lower() not in ("", "headless")
              and str(engine.get("renderer", "")).lower() not in ("", "headless")
              and engine.get("render_cap_fps") in (30, 60))

    def snapshot(s, name):
        r = s.get("rig", {}) if isinstance(s, dict) else {}
        fields = isinstance(s, dict) and isinstance(r, dict) and num(s.get("t")) and vec(s.get("player"))
        fields = fields and vec(s.get("velocity")) and isinstance(s.get("floor"), bool) and isinstance(s.get("visible_body"), bool)
        fields = fields and all(vec(r.get(k)) for k in ("pivot", "camera")) and all(num(r.get(k)) for k in
            ("yaw", "pitch", "requested_distance", "distance", "hit_length", "follow_ticks", "observed_ticks", "near", "fov", "aspect", "probe_radius", "mask", "mouse_mode"))
        fields = fields and isinstance(r.get("input_enabled"), bool) and isinstance(r.get("basis"), list) and len(r["basis"]) == 3 and all(vec(x) for x in r["basis"])
        corners = s.get("near_corners", []) if isinstance(s, dict) else []
        fields = fields and isinstance(corners, list) and len(corners) == 4 and all(vec(x) for x in corners)
        fields = fields and all(isinstance(s.get(k), list) for k in ("camera_overlap", "near_ray_hits"))
        fields = fields and all(vec(s.get(k), 2) for k in ("player_head_pixel", "player_feet_pixel"))
        if not fields:
            check(name+".fields", False)
            return False
        check(name+".pose", distance(r["pivot"], [s["player"][0], s["player"][1]+1.3, s["player"][2]]) <= .002
              and r["follow_ticks"] == r["observed_ticks"] and r["follow_ticks"] >= 0)
        check(name+".arm", 0 <= r["distance"] <= r["hit_length"]+.002 <= r["requested_distance"]+.004
              and 2-1e-6 <= r["requested_distance"] <= 6+1e-6
              and near(distance(r["camera"], r["pivot"]), r["distance"], .002))
        check(name+".orientation", math.radians(-55)-1e-6 <= r["pitch"] <= math.radians(15)+1e-6
              and all(near(length(col), 1, .002) for col in r["basis"])
              and all(abs(sum(x*y for x, y in zip(r["basis"][i], r["basis"][j]))) <= .002 for i, j in ((0,1),(0,2),(1,2))))
        expected_camera = [r["pivot"][i]+r["basis"][2][i]*r["distance"] for i in range(3)]
        check(name+".axis", distance(expected_camera, r["camera"]) <= .002)
        check(name+".query", near(r["mask"], 1, 0) and near(r["probe_radius"], .2)
              and near(r["near"], .05) and near(r["fov"], 65) and r["aspect"] > 0
              and not s["camera_overlap"] and not s["near_ray_hits"]
              and r["input_enabled"] is True and r["mouse_mode"] == (2 if suite == "gpu" else 0))
        sphere_pen = []
        corner_in = []
        for b in boxes:
            gap = length([max(b["lo"][i]-r["camera"][i], 0, r["camera"][i]-b["hi"][i]) for i in range(3)])
            if gap < .2-.002:
                sphere_pen.append(b["name"])
            for corner in corners:
                if all(b["lo"][i]+.002 < corner[i] < b["hi"][i]-.002 for i in range(3)):
                    corner_in.append(b["name"])
        check(name+".independent_clearance", not sphere_pen and not corner_in, {"sphere_boxes": sphere_pen, "corner_boxes": corner_in})
        radius = max(distance(c, r["camera"]) for c in corners)
        check(name+".near_plane_fits_probe", radius <= .2+1e-6 and radius >= .05)
        offsets = [delta(c, r["camera"]) for c in corners]
        local = [[sum(v*x for v,x in zip(offset, col)) for col in r["basis"]] for offset in offsets]
        half_width = max(abs(p[0]) for p in local)
        half_height = max(abs(p[1]) for p in local)
        expected_fov_half = r["near"]*math.tan(math.radians(r["fov"])/2)
        signs = {(1 if p[0] > 0 else -1, 1 if p[1] > 0 else -1) for p in local}
        check(name+".near_plane_geometry", len(signs) == 4 and half_width > 0 and half_height > 0
              and all(near(p[2],-r["near"],.0001) and near(abs(p[0]),half_width,.0001)
                      and near(abs(p[1]),half_height,.0001) for p in local)
              and near(half_width/half_height,r["aspect"],.002)
              and (near(half_width,expected_fov_half,.0001) or near(half_height,expected_fov_half,.0001)))
        return True

    segments = ["open_idle", "follow_walk", "follow_run", "wall_orbit", "corner_orbit", "lintel_orbit",
                "wall_still", "clear_expansion", "step_camera", "slope_camera"]
    segments += [f"door_{direction}_{i}" for direction in ("forward", "reverse") for i in range(10)]
    for name in segments:
        c = get(name)
        samples = c.get("samples", [])
        ok = all(num(c.get(k)) for k in ("duration_s", "wall_s", "ticks", "frames", "recoveries"))
        ok = ok and all(vec(c.get(k)) for k in ("start", "end")) and isinstance(samples, list) and len(samples) >= 2
        check(name+".fields", ok)
        if not ok:
            continue
        check(name+".clock", c["duration_s"] > 0 and c["wall_s"] > 0 and c["frames"] >= 0
              and near(c["ticks"]/60, c["duration_s"], .034) and c["ticks"] > 0 and c["recoveries"] == 0
              and len(samples) >= math.ceil(c["ticks"]/6) and len(samples) <= c["ticks"]+1)
        stats = c.get("all_tick_stats", {})
        stats_fields = ("ticks", "max_camera_overlap_count", "max_near_hit_count", "max_follow_error_m",
                        "max_length_excess_m", "max_tick_mismatch", "floor_ticks", "min_distance", "max_distance",
                        "min_player_y", "max_player_y", "camera_max_step_m")
        stats_ok = isinstance(stats,dict) and all(num(stats.get(k)) for k in stats_fields)
        check(name+".all_tick_stats", stats_ok and stats["ticks"] == c["ticks"]
              and stats["max_camera_overlap_count"] == 0 and stats["max_near_hit_count"] == 0
              and 0 <= stats["max_follow_error_m"] <= .002 and 0 <= stats["max_length_excess_m"] <= .002
              and stats["max_tick_mismatch"] == 0 and 0 <= stats["floor_ticks"] <= c["ticks"]
              and 0 <= stats["min_distance"] <= stats["max_distance"] <= 6.002
              and stats["min_player_y"] <= stats["max_player_y"] and stats["camera_max_step_m"] >= 0, stats)
        valid = [snapshot(s, name+f".sample[{i}]") for i, s in enumerate(samples)]
        if not all(valid):
            continue
        times = [s["t"] for s in samples]
        check(name+".sample_clock", all(0 < b-a <= .11 for a, b in zip(times, times[1:]))
              and 0 <= times[0] <= .02 and near(times[-1],c["duration_s"],.0001)
              and times[-1]-times[0] >= c["duration_s"]-.02)
        if stats_ok:
            check(name+".stats_enclose_samples", all(stats["min_distance"]-.002 <= s["rig"]["distance"] <= stats["max_distance"]+.002
                  and stats["min_player_y"]-.002 <= s["player"][1] <= stats["max_player_y"]+.002 for s in samples))
        check(name+".endpoints", distance(c["start"], samples[0]["player"]) <= .07
              and distance(c["end"], samples[-1]["player"]) <= .002)
        if suite == "gpu":
            check(name+".actual_clock", abs(c["wall_s"]-c["duration_s"]) <= .02*c["duration_s"])
            check(name+".actual_render", abs(c["frames"]/c["wall_s"]-engine.get("render_cap_fps", 0)) <= .2*engine.get("render_cap_fps", 0))
        if name == "open_idle":
            check(name+".duration", c["duration_s"] >= (60 if suite == "full" else 2)-1e-6)
            check(name+".stable_visible", all(s["visible_body"] and s["floor"] for s in samples)
                  and max(distance(s["player"], samples[0]["player"]) for s in samples) <= .001
                  and all(near(s["rig"]["distance"], 4.5, .002) for s in samples)
                  and stats_ok and stats["floor_ticks"] == c["ticks"]
                  and stats["max_player_y"]-stats["min_player_y"] <= .001)
        elif name in ("follow_walk", "follow_run"):
            speed = 1.4 if name == "follow_walk" else 3.5
            travelled = math.hypot(c["end"][0]-c["start"][0], c["end"][2]-c["start"][2])
            check(name+".speed", near(c["duration_s"], 10, .034) and abs(travelled-speed*c["duration_s"]) <= .02*speed*c["duration_s"])
            check(name+".visible", all(s["visible_body"] for s in samples))
        elif name in ("wall_orbit", "corner_orbit", "lintel_orbit", "wall_still"):
            check(name+".obstruction", near(c["duration_s"], 3, .034)
                  and any(s["rig"]["distance"] < s["rig"]["requested_distance"]-.1 for s in samples))
            if name == "wall_still":
                lengths = [s["rig"]["distance"] for s in samples]
                check(name+".jitter", max(lengths)-min(lengths) <= .005
                      and stats_ok and stats["max_distance"]-stats["min_distance"] <= .005)
            else:
                check(name+".rotation", max(angle(s["rig"]["yaw"], samples[0]["rig"]["yaw"]) for s in samples) > .1)
        elif name == "clear_expansion":
            lengths = [s["rig"]["distance"] for s in samples]
            check(name+".recovery", near(c["duration_s"], 2, .034) and near(lengths[-1], 4.5, .002)
                  and all(-.002 <= b-a <= 6*(tb-ta)+.002 for a,b,ta,tb in zip(lengths,lengths[1:],times,times[1:]))
                  and stats_ok and stats["camera_max_step_m"] <= 6/60+.002)
        elif name.startswith("door_"):
            forward = name.startswith("door_forward_")
            check(name+".crossing", c["ticks"] == 172 and
                  ((c["start"][2] > -3.875 and c["end"][2] < -4.125) if forward else
                   (c["start"][2] < -4.125 and c["end"][2] > -3.875)))
            check(name+".concurrent_rotation", max(angle(s["rig"]["yaw"], samples[0]["rig"]["yaw"]) for s in samples) > .1)
        elif name in ("step_camera", "slope_camera"):
            check(name+".traversal", near(c["duration_s"], 3.7 if name == "step_camera" else 4.5, .034)
                  and abs(c["end"][1]-c["start"][1]) >= (.27 if name == "step_camera" else .97))

    c = get("mouse_orbit")
    ok = all(num(c.get(k)) for k in ("start_yaw", "start_pitch", "end_yaw", "end_pitch", "dx", "dy", "yaw_after_discard", "pitch_after_discard"))
    check("mouse_orbit.dispatch", ok and c.get("discarded_first") is True and near(c.get("dx"),120) and near(c.get("dy"),40)
          and near(c.get("yaw_after_discard"),c.get("start_yaw")) and near(c.get("pitch_after_discard"),c.get("start_pitch")) if ok else False)
    check("mouse_orbit.delta", ok and angle(c["end_yaw"],c["start_yaw"]-.3) <= 1e-5
          and near(c["end_pitch"], c["start_pitch"]-.1, 1e-5) if ok else False)
    c = get("clamps")
    check("clamps.limits", near(c.get("pitch_low"), math.radians(-55)) and near(c.get("pitch_high"), math.radians(15))
          and near(c.get("zoom_near"),2) and near(c.get("zoom_far"),6))
    c = get("self_exclusion")
    check("self_exclusion.explicit", near(c.get("mask_used"),3,0) and near(c.get("requested_distance"),4.5)
          and near(c.get("length_with_exclusion"),4.5,.002) and c.get("excluded_registered") is True)
    c = get("menu_input")
    check("menu_input.pause", c.get("paused") is True and c.get("actor_ticks") == 0 and c.get("rig_ticks") == 0
          and c.get("mouse_open") == 0 and c.get("mouse_closed") == (2 if suite == "gpu" else 0)
          and c.get("capture_open") is False and c.get("capture_closed") is True)
    check("menu_input.freeze", all(near(c.get(k),0,.001) for k in ("paused_drift", "paused_yaw_drift", "paused_pitch_drift", "held_drift")))
    check("menu_input.resume", num(c.get("release_move_m")) and c["release_move_m"] > .1 and c.get("recapture_first_ignored") is True)
    c = get("focus_loss")
    check("focus_loss.release", c.get("paused") is True and c.get("mouse_mode") == 0 and c.get("stays_paused_on_focus_return") is True)
    c = get("fall_camera_return")
    check("fall_camera_return.reset", c.get("reason") == "fall" and vec(c.get("position")) and distance(c["position"],[-2,.08,2]) <= .01
          and near(c.get("yaw"),0) and near(c.get("pitch"),math.radians(-15)) and near(c.get("distance_requested"),4.5) and c.get("latched") is True)
    c = get("eye_clearance")
    check("eye_clearance.radius", num(c.get("max_near_corner_radius")) and .05 <= c["max_near_corner_radius"] <= .2)
    return {"passed": bool(checks) and all(c["passed"] for c in checks), "checks": checks}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = audit(json.loads(args.input.read_text(encoding="utf-8")))
    except (OSError, ValueError, TypeError, KeyError, IndexError, AttributeError, ZeroDivisionError) as exc:
        result = {"passed": False, "checks": [{"name": "read_or_schema", "passed": False, "details": str(exc)}]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

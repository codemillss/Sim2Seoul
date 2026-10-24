#!/usr/bin/env python3
"""Derived inspection sheets/phase-sampled loops from native identity captures.

Never edits raw PNGs. GIFs repeat four observed phase samples; they are not a
continuous video, frame interpolation, or evidence of full-motion smoothness.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw

VIEWS = ["front", "left_profile", "right_profile", "front45_left",
         "front45_right", "rear", "rear45_left", "rear45_right"]
LIGHTS = ["soft_studio", "side_rim"]
MODELS = ["SeoulResident_M01", "SeoulResident_F01"]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_path(value: str, repository: Path) -> Path:
    if value.startswith("res://"):
        return (repository / "game" / value.removeprefix("res://")).resolve()
    path = Path(value)
    return path if path.is_absolute() else repository / path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--no-gifs", action="store_true")
    args = parser.parse_args()
    report = args.report.resolve()
    repository = Path(__file__).resolve().parents[1]
    data = json.loads(report.read_text())
    captures = data["captures"]
    if data.get("task") != "EXP34_AUTHORED_CHARACTER_IDENTITY_PORTRAIT_AND_MOTION":
        raise ValueError("Expected the identity portrait/motion report")
    if len(captures) != 64:
        raise ValueError(f"Expected64 raw images; found{len(captures)}")
    checked = []
    for capture in captures:
        path = source_path(capture["file"], repository)
        if not path.is_file() or sha(path) != capture["sha256"]:
            raise ValueError(f"Raw capture missing/changed: {path}")
        asset = source_path(capture["actual_glb_path"], repository)
        if not asset.is_file() or sha(asset) != capture["actual_glb_sha256"]:
            raise ValueError(f"Native source asset missing/changed: {asset}")
        checked.append({"file": str(path), "sha256": capture["sha256"]})
    destination = (args.output_dir or report.with_name(report.stem + "_review")).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    outputs = []

    def sheet(name: str, selected: list[dict], columns: int, title: str) -> None:
        width, height, margin = 480, 300, 24
        rows = (len(selected) + columns - 1) // columns
        canvas = Image.new("RGB", (columns * width, 30 + rows * (height + margin)), (237, 240, 244))
        draw = ImageDraw.Draw(canvas)
        draw.text((12, 5), title, fill=(15, 15, 15))
        inputs = []
        for index, capture in enumerate(selected):
            path = source_path(capture["file"], repository)
            with Image.open(path) as raw:
                image = raw.convert("RGB")
                image.thumbnail((width, height))
            x, y = (index % columns) * width, 30 + (index // columns) * (height + margin)
            canvas.paste(image, (x + (width - image.width) // 2, y))
            label = capture["view"]
            if capture["kind"] == "actual_controller_head_motion":
                label += f" phase{capture['sample_index']} observed{capture['actual_stride_phase_radians']:.2f}rad"
            draw.text((x + 8, y + height + 3), label, fill=(20, 20, 20))
            inputs.append({"file": str(path), "sha256": capture["sha256"]})
        output = destination / name
        canvas.save(output)
        outputs.append({"file": str(output), "sha256": sha(output), "kind": "contact_sheet",
                        "inputs": inputs, "transformation": "Whole raw PNG fit into480x300; labels outside image, no retouch."})

    for model in MODELS:
        model_rows = [capture for capture in captures if capture["model_id"] == model]
        for lighting in LIGHTS:
            found = {capture["view"]: capture for capture in model_rows
                     if capture["kind"] == "static_portrait" and capture["lighting"]["name"] == lighting}
            if set(found) != set(VIEWS):
                raise ValueError(f"Incomplete static angle matrix: {model}/{lighting}")
            sheet(f"{model}_{lighting}_portraits.png", [found[view] for view in VIEWS], 4,
                  f"{model} / {lighting} / actual native eight-angle portraits")
        moving = [capture for capture in model_rows if capture["kind"] == "actual_controller_head_motion"]
        ordered = []
        for gait in ("walk_1_4mps", "run_3_5mps"):
            for view in ("head_front", "head_right"):
                group = sorted((capture for capture in moving
                                if capture["gait_label"].endswith(gait) and capture["view"] == view),
                               key=lambda capture: capture["sample_index"])
                if len(group) != 4:
                    raise ValueError(f"Expectedfour actual motion phases: {model}/{gait}/{view}")
                ordered.extend(group)
                if args.no_gifs:
                    continue
                # Source physical-frame differences supply the sampled spacing.
                # Last-to-first duration uses the median preceding interval;
                # the repeated boundary is explicitly synthetic phase playback.
                frames = []
                for capture in group:
                    with Image.open(source_path(capture["file"], repository)) as raw:
                        frames.append(raw.convert("RGB"))
                hz = float(data["physics_hz"])
                durations = [max(40, round(1000 * (b["physics_frame"] - a["physics_frame"]) / hz))
                             for a, b in zip(group, group[1:])]
                durations.append(sorted(durations)[len(durations) // 2])
                output = destination / f"{model}_{gait}_{view}_sampled_loop.gif"
                frames[0].save(output, save_all=True, append_images=frames[1:],
                               duration=durations, loop=0, optimize=False)
                outputs.append({"file": str(output), "sha256": sha(output), "kind": "four_phase_sampled_loop",
                                "frame_durations_ms": durations,
                                "inputs": [{"file": capture["file"], "sha256": capture["sha256"]} for capture in group],
                                "scope": "Four actual phase samples, no generated in-between frames. Repeated boundary is sampled playback, not continuous video or smoothness acceptance."})
        sheet(f"{model}_moving_head_phases.png", ordered, 4,
              f"{model} / walk front,walk side,run front,run side / four observed phases each")
    manifest = {"task": "EXP34_DERIVED_IDENTITY_INSPECTION", "source_report": str(report),
                "source_report_sha256": sha(report), "raw_images_hash_checked": checked,
                "outputs": outputs, "visual_review_status": "PENDING actual inspection of these files",
                "scope": "Derived QA presentation only. No source geometry/material edits. Captures and numeric PASS do not establish attractive faces, realism or natural continuous motion."}
    (destination / "contact_sheet_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"raw_images": len(captures), "derived_outputs": len(outputs),
                      "manifest": str(destination / "contact_sheet_manifest.json")}))


if __name__ == "__main__":
    main()

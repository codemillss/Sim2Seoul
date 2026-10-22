#!/usr/bin/env python3
"""Arrange verified native gait PNGs for independent review; originals unchanged.

This creates inspection artifacts, never generated/reconstructed character art.
Run with a completed check_human_gait_views.gd report and Pillow available.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def font(size):
    for path in ("/System/Library/Fonts/Supplemental/Arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size=size)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--outdir", type=Path)
    args = parser.parse_args()
    report = args.report.resolve()
    data = json.loads(report.read_text())
    if data.get("task") != "EXP29_ACTUAL_HUMAN_GAIT_VIEWS":
        raise ValueError("Expected an actual native gait-view report")
    if data.get("display") == "headless":
        raise ValueError("A headless report is not native image evidence")
    outdir = (args.outdir or report.with_name(report.stem + "_contact_sheets")).resolve()
    outdir.mkdir(parents=True, exist_ok=True)
    groups = defaultdict(list)
    images = {}
    for capture in data["captures"]:
        path = Path(capture["file"])
        if not path.is_absolute():
            path = report.parent / path
        path = path.resolve()
        actual = sha(path)
        if actual != capture["sha256"]:
            raise ValueError("Native original SHA changed: " + str(path))
        images[str(path)] = actual
        gait = next((v["gait"] for v in data["views"] if any(p["file"] == capture["file"] for p in v["phase_observations"])), None)
        if gait is None:
            # A bounded timeout can leave a partly captured view unfinalized.
            # Keep those real images available, explicitly as partial evidence.
            gait = path.stem.removeprefix(report.stem + "_").removesuffix(f"_{capture['view']}_{int(capture['sample_index']):02d}") + "_partial"
        groups[(gait, capture["view"])].append((capture, path))
    sheets = []
    for (gait, view), rows in groups.items():
        rows.sort(key=lambda pair: pair[0]["sample_index"])
        cols = 2 if view == "rear_hip_close" else 4
        width, height, caption, margin, top = 512, 320, 62, 12, 82
        count_rows = math.ceil(len(rows) / cols)
        sheet = Image.new("RGB", (cols * (width + margin) + margin, top + count_rows * (height + caption + margin) + margin), (24, 29, 34))
        draw = ImageDraw.Draw(sheet)
        draw.text((margin, 12), f"{gait} | {view} | {len(rows)} actual native frames", fill=(244, 246, 249), font=font(24))
        draw.text((margin, 46), "Resize + outside-image labels only. Numeric integrity PASS does not approve gait naturalness.", fill=(194, 203, 211), font=font(18))
        cells = []
        for slot, (capture, path) in enumerate(rows):
            with Image.open(path) as original:
                reduced = original.convert("RGB")
                reduced.thumbnail((width, height), Image.Resampling.LANCZOS)
                source_size = list(original.size)
            x = margin + (slot % cols) * (width + margin)
            y = top + (slot // cols) * (height + caption + margin)
            sheet.paste(reduced, (x + (width - reduced.width) // 2, y + (height - reduced.height) // 2))
            fraction = float(capture["actual_stride_phase_radians"]) / (2 * math.pi)
            label = f"#{int(capture['sample_index']):02d}  actual cycle {fraction:.4f}  physics {capture['physics_frame']}"
            draw.text((x, y + height + 5), label, fill=(236, 240, 244), font=font(19))
            draw.text((x, y + height + 31), f"target {float(capture['target_stride_phase_radians']) / (2*math.pi):.4f}  render fraction {float(capture['render_interpolation_fraction']):.3f}", fill=(179, 194, 205), font=font(18))
            cells.append({"slot": slot, "source": str(path), "source_sha256": capture["sha256"], "source_size": source_size, "display_size": list(reduced.size), "actual_stride_phase_radians": capture["actual_stride_phase_radians"], "physics_frame": capture["physics_frame"], "process_frame": capture["process_frame"]})
        target = outdir / f"{gait}_{view}.png"
        sheet.save(target, optimize=True)
        sheets.append({"gait": gait, "view": view, "file": str(target), "sha256": sha(target), "bytes": target.stat().st_size, "size": list(sheet.size), "cells": cells})
    for path, expected in images.items():
        if sha(path) != expected:
            raise ValueError("Original changed during contact-sheet generation: " + path)
    manifest = {"task": "HUMAN_GAIT_NATIVE_CONTACT_SHEETS", "report": str(report), "report_sha256": sha(report), "source_report_result": data.get("result"), "source_summary": data.get("summary"), "script_sha256": sha(__file__), "original_files_verified_unchanged": len(images), "operations": ["Read source PNGs and verify report SHA", "Resize only in derived inspection sheet", "Add phase and frame labels outside native-image rectangle", "Save derived lossless PNG contact sheet", "Recheck every original PNG SHA"], "scope": "Review aid from actual native frames. No synthetic pose/image generation, pixel repair, source-frame modification or visual acceptance is performed by this tool.", "sheets": sheets}
    (outdir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"report": str(report), "sheets": len(sheets), "originals_verified": len(images), "outdir": str(outdir)}, indent=2))


if __name__ == "__main__":
    main()

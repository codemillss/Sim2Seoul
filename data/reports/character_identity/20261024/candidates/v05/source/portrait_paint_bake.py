"""Sample original generated portrait paints onto authored head coordinates.

The two immutable PNGs are image_gen paint REFERENCES, not 3D game renders,
photographs, scans or lighting-free measured albedo. This helper reads them;
it never edits or rewrites them. A manually declared thin-plate spline aligns
eyes, nose, lips and chin to the project's existing head coordinates. Skin
colour differences are transferred relative to skin swatches, with bounded
luminance and exclusions for painted eyes/brows. Geometry still supplies the
actual shape, eyelids, mouth, occlusion and live highlights.

Public RGB is sRGB. Pass the BODY skin reference, not the numerical module's
already-pigmented face/lip result. The generator converts vertex RGB once.
Pure Python standard library; decoded source/warp/swatch data are cached.
"""
from __future__ import annotations

import argparse
import functools
import hashlib
import json
import math
import statistics
import struct
import zlib
from pathlib import Path

VERSION = "original_portrait_paint_bake_v1"
REPOSITORY = Path(__file__).resolve().parents[2]
SOURCE_DIRECTORY = Path("game/assets/original/seoul_resident/portrait_sources")
SOURCES = {
    False: ("portrait_albedo_m01_v01.png", "cb52bc58189849120d5f781d61543d686fd3d9e1014f23f997c577f20727bc2a"),
    True: ("portrait_albedo_f01_v01.png", "071c642ba1cdf7e8dc4f25fdc311c98eea433576e2bd3c57aeaf0e234581c740"),
}
PROMPT_RECORD = Path("data/reports/character_identity/20261024/imagegen_paint_sources.json")
SKIN_REFERENCES = {False: (.69, .48, .36), True: (.77, .56, .44)}
TRANSFER_STRENGTH = .78
LUMINANCE_WEIGHTS = (.2126, .7152, .0722)
PASSTHROUGH_FEATURES = frozenset(("head_back", "back", "neck", "ear", "ear_inner", "eye", "hair", "brow"))
SKIN_FEATURES = frozenset(("face", "eyelid", "lip", "lip_upper", "lip_lower", "mouth"))


def _clamp(value, low=0., high=1.):
    return max(low, min(high, float(value)))


def _smooth(low, high, value):
    t = _clamp((value-low)/(high-low))
    return t*t*(3.-2.*t)


def _landmarks(female):
    """Manual locations read from the actual unmodified 1254-square paints.

    Target x is original head X/.069; y=(original head Y-1.458)/.184.
    These are fictional art alignment points, not measured human landmarks.
    Source coordinates are pixel centres, top-left origin, x right/y down.
    """
    ex, ey, ny, my = (.420, .636, .451, .288) if female else (.406, .620, .424, .250)
    source = {
        "chin": (628, 1018) if female else (626, 1024),
        "mouth": (628, 817) if female else (626, 813),
        "nose": (627, 662) if female else (626, 659),
        "eye_l": (489, 505) if female else (493, 493),
        "eye_r": (762, 505) if female else (759, 493),
        "brow_l": (491, 428) if female else (493, 425),
        "brow_r": (761, 428) if female else (759, 425),
    }
    points = [
        ("chin", (0., 0.), source["chin"]),
        ("mouth", (0., my), source["mouth"]),
        ("nose", (0., ny), source["nose"]),
        ("eye_l", (-ex, ey), source["eye_l"]),
        ("eye_r", (ex, ey), source["eye_r"]),
        ("brow_l", (-ex, ey+.145), source["brow_l"]),
        ("brow_r", (ex, ey+.145), source["brow_r"]),
        ("mouth_l", (-.30, my), (532, 817) if female else (531, 813)),
        ("mouth_r", (.30, my), (723, 817) if female else (721, 813)),
        ("cheek_l", (-.64, .43), (411, 687)),
        ("cheek_r", (.64, .43), (840, 687)),
        ("jaw_l", (-.57, .11), (456, 951)),
        ("jaw_r", (.57, .11), (796, 951)),
        ("temple_l", (-.94, .74), (332, 410)),
        ("temple_r", (.94, .74), (921, 410)),
        ("forehead", (0., 1.), (626, 300)),
        ("crown", (0., 1.30), (626, 38)),
    ]
    return points


def _paeth(left, up, upper_left):
    p = left+up-upper_left
    a, b, c = abs(p-left), abs(p-up), abs(p-upper_left)
    return left if a <= b and a <= c else up if b <= c else upper_left


def _decode_png(payload):
    """Read RGB/RGBA8 non-interlaced PNG with all five standard filters."""
    if payload[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("portrait source must be a PNG")
    offset, packed, header = 8, bytearray(), None
    while offset < len(payload):
        count = struct.unpack_from(">I", payload, offset)[0]
        tag = payload[offset+4:offset+8]
        data = payload[offset+8:offset+8+count]
        crc = struct.unpack_from(">I", payload, offset+8+count)[0]
        if zlib.crc32(tag+data)&0xffffffff != crc:
            raise ValueError("portrait PNG CRC mismatch")
        if tag == b"IHDR":
            header = struct.unpack(">IIBBBBB", data)
        elif tag == b"IDAT":
            packed.extend(data)
        offset += count+12
        if tag == b"IEND":
            break
    if header is None:
        raise ValueError("portrait PNG has no header")
    width, height, depth, kind, compression, filtering, interlace = header
    if depth != 8 or kind not in (2, 6) or compression or filtering or interlace:
        raise ValueError("portrait source must be RGB/RGBA8 without interlace")
    channels = 3 if kind == 2 else 4
    stride = width*channels
    raw = zlib.decompress(packed)
    if len(raw) != height*(stride+1):
        raise ValueError("portrait PNG decoded length mismatch")
    pixels, previous = bytearray(), bytearray(stride)
    for y in range(height):
        start = y*(stride+1)
        filter_kind = raw[start]
        row = bytearray(raw[start+1:start+1+stride])
        if filter_kind > 4:
            raise ValueError("invalid portrait PNG row filter")
        for i in range(stride):
            left = row[i-channels] if i >= channels else 0
            up = previous[i]
            corner = previous[i-channels] if i >= channels else 0
            prediction = (0 if filter_kind == 0 else left if filter_kind == 1 else
                          up if filter_kind == 2 else (left+up)//2 if filter_kind == 3 else
                          _paeth(left, up, corner))
            row[i] = (row[i]+prediction)&255
        if channels == 3:
            pixels.extend(row)
        else:
            for i in range(0, stride, 4):
                if row[i+3] != 255:
                    raise ValueError("portrait paint must be opaque")
                pixels.extend(row[i:i+3])
        previous = row
    return width, height, bytes(pixels)


def _kernel(dx, dy):
    squared = dx*dx+dy*dy
    return .5*squared*math.log(squared) if squared > 1e-20 else 0.


def _solve(matrix, rhs):
    # Small two-output TPS system solved once per immutable source identity.
    n = len(matrix)
    a = [list(row)+list(value) for row, value in zip(matrix, rhs)]
    for column in range(n):
        pivot = max(range(column, n), key=lambda row: abs(a[row][column]))
        if abs(a[pivot][column]) < 1e-12:
            raise ValueError("portrait landmark system is singular")
        a[column], a[pivot] = a[pivot], a[column]
        divisor = a[column][column]
        a[column] = [value/divisor for value in a[column]]
        for row in range(n):
            if row == column:
                continue
            factor = a[row][column]
            if factor:
                a[row] = [v-factor*p for v, p in zip(a[row], a[column])]
    return [row[n:] for row in a]


def _pixel(image, x, y):
    width, height, rgb = image
    x, y = _clamp(x, 0., width-1.), _clamp(y, 0., height-1.)
    ix, iy = int(x), int(y)
    jx, jy = min(ix+1, width-1), min(iy+1, height-1)
    tx, ty = x-ix, y-iy
    result = []
    for channel in range(3):
        a = rgb[(iy*width+ix)*3+channel]*(1.-tx)+rgb[(iy*width+jx)*3+channel]*tx
        b = rgb[(jy*width+ix)*3+channel]*(1.-tx)+rgb[(jy*width+jx)*3+channel]*tx
        result.append((a*(1.-ty)+b*ty)/255.)
    return tuple(result)


@functools.lru_cache(maxsize=2)
def _source(female):
    filename, expected = SOURCES[bool(female)]
    path = REPOSITORY/SOURCE_DIRECTORY/filename
    payload = path.read_bytes()
    actual = hashlib.sha256(payload).hexdigest()
    if actual != expected:
        raise ValueError("portrait source bytes changed: "+str(path))
    image = _decode_png(payload)
    landmarks = _landmarks(bool(female))
    targets = [point for _, point, _ in landmarks]
    n = len(targets)
    matrix, rhs = [], []
    for _, (x, y), (sx, sy) in landmarks:
        matrix.append([_kernel(x-a, y-b) for a, b in targets]+[1., x, y])
        rhs.append((float(sx), float(sy)))
    matrix.extend([[1.]*n+[0.]*3, [p[0] for p in targets]+[0.]*3,
                   [p[1] for p in targets]+[0.]*3])
    rhs.extend([(0., 0.)]*3)
    weights = _solve(matrix, rhs)
    # These patches avoid brows, iris, lips, nostrils and source background.
    # Use their channel medians so one remaining source-light/shadow patch
    # cannot globally darken or recolour the body skin reference.
    swatches = [(455, 635), (795, 635), (548, 318), (704, 318), (559, 927), (694, 927)]
    sampled = [_pixel(image, x+dx, y+dy) for x, y in swatches
               for dx in (-8, 0, 8) for dy in (-8, 0, 8)]
    baseline = tuple(statistics.median(p[c] for p in sampled) for c in range(3))
    return {"image": image, "targets": targets, "weights": weights,
            "baseline": baseline, "sha256": actual, "path": str(SOURCE_DIRECTORY/filename),
            "swatches": swatches, "source_size": image[:2]}


def _map_pixel(x, y, female=False):
    source = _source(bool(female))
    basis = [_kernel(x-a, y-b) for a, b in source["targets"]]+[1., x, y]
    return tuple(sum(value*weight[c] for value, weight in zip(basis, source["weights"])) for c in range(2))


def _transfer_mask(x, y, female, front):
    # Fade before neck/back and silhouette; the side/rear head never receives
    # frontal photograph lighting. Actual eye/brow geometry owns those marks.
    mask = (_smooth(.025, .18, y)*(1.-_smooth(1.03, 1.20, y))*
            (1.-_smooth(.65, .98, abs(x)))*_smooth(.35, .90, front))
    ex, ey = (.420, .636) if female else (.406, .620)
    for side in (-1., 1.):
        eye_distance = math.hypot((x-side*ex)/.255, (y-ey)/.045)
        brow_distance = math.hypot((x-side*ex)/.30, (y-ey-.145)/.050)
        mask *= _smooth(1., 1.45, eye_distance)*_smooth(1., 1.50, brow_distance)
    return mask


def sample_portrait(base_rgb, x_normalized, y, female=False, feature="face", front=1.):
    """Return aligned, tone-corrected sRGB for skin vertices only.

    Pass the unmodified body skin reference. Hair, eyes, brows, ear/back/neck
    are passthroughs; retain the existing numeric fallback for those parts.
    Original PNGs are never written. No source catchlight or dark eyebrow is
    applied to a geometric eyeball, brow or hair surface.
    """
    base = tuple(float(c) for c in base_rgb[:3])
    if len(base) != 3 or not all(math.isfinite(c) and 0. <= c <= 1. for c in base):
        raise ValueError("base_rgb must contain three finite sRGB channels")
    x, y, front = float(x_normalized), float(y), float(front)
    if not all(math.isfinite(v) for v in (x, y, front)):
        raise ValueError("portrait coordinates must be finite")
    if feature in PASSTHROUGH_FEATURES:
        return base
    if feature not in SKIN_FEATURES:
        raise ValueError("unknown portrait paint feature: "+str(feature))
    if not -1.25 <= x <= 1.25 or not -.2 <= y <= 1.4:
        return base
    female, front = bool(female), _clamp(front)
    mask = _transfer_mask(x, y, female, front)
    if mask <= 1e-9:
        return base
    source = _source(female)
    sx, sy = _map_pixel(x, y, female)
    # A small sample footprint smooths isolated source pores at vertex scale,
    # while preserving local lip/cheek pigmentation instead of a flat tint.
    samples = [_pixel(source["image"], sx+dx, sy+dy) for dx, dy in
               ((0, 0), (-1.1, -.7), (1.1, .7), (-.7, 1.1), (.7, -1.1))]
    rgb = tuple(sum(p[c] for p in samples)/len(samples) for c in range(3))
    delta = tuple(a-b for a, b in zip(rgb, source["baseline"]))
    luminance = sum(v*w for v, w in zip(delta, LUMINANCE_WEIGHTS))
    mouth_y = .288 if female else .250
    lip_distance = math.hypot(x/.39, (y-mouth_y)/.082)
    lip = 1.-_smooth(.75, 1.45, lip_distance)
    # Generated paint retains some directional shadows despite its prompt.
    # Clamp their intensity and preserve restrained chroma separately. Lips
    # get a larger tissue-colour range; nostrils never become black decals.
    nose = math.exp(-.5*((x/.23)**2+((y-(.451 if female else .424))/.13)**2))
    lower = -.075-.065*lip+.035*nose*(1.-lip)
    upper = .075-.020*lip
    bounded_luma = _clamp(luminance, lower, upper)
    chroma_limit = .065+.035*lip
    offsets = tuple(bounded_luma+_clamp(d-luminance, -chroma_limit, chroma_limit) for d in delta)
    return tuple(_clamp(c+TRANSFER_STRENGTH*mask*d) for c, d in zip(base, offsets))


def paint_contract():
    """Manifest-ready provenance, immutable input hashes and exact alignment."""
    rows = []
    for female in (False, True):
        source = _source(female)
        rows.append({"identity": "f01" if female else "m01", "path": source["path"],
                     "sha256": source["sha256"], "size_px": list(source["source_size"]),
                     "skin_swatch_median_srgb": list(source["baseline"]),
                     "skin_swatches_px": source["swatches"],
                     "landmarks": [{"name": name, "target_normalized_xy": xy, "source_px": px}
                                   for name, xy, px in _landmarks(female)]})
    prompt_path = REPOSITORY/PROMPT_RECORD
    return {"version": VERSION, "used": True, "source_kind": "Original image_gen fictional adult skin-paint references; NOT game screenshots or measured diffuse albedo.",
            "sources": rows, "prompt_record": str(PROMPT_RECORD),
            "prompt_record_sha256": hashlib.sha256(prompt_path.read_bytes()).hexdigest(),
            "alignment": "Manually declared eye/nose/mouth/chin/contour landmarks; exact thin-plate spline, skin-only bilinear sampling.",
            "coordinate_contract": "x=original head X/.069; y=(original head Y-1.458)/.184; sRGB output converted once by generator.",
            "body_tone": "Subtract source skin-swatch channel medians, add bounded relative colour to unchanged BODY reference; no whole-face multiplicative darkening.",
            "strength": TRANSFER_STRENGTH, "luminance_bounds_srgb": {"skin": [-.075, .075], "lip": [-.140, .055], "nose_min_at_center": -.040},
            "passthrough_features": sorted(PASSTHROUGH_FEATURES),
            "fade": {"neck_y": [.025, .18], "side_abs_x": [.65, .98], "front_cosine": [.35, .90], "upper_head_y": [1.03, 1.20]},
            "painted_eyes_and_brows_excluded": True, "png_modified": False,
            "scope": "Candidate skin-colour mapping only. Generated paint contains residual lighting; bounded transfer is not photogrammetry, anatomy or native-art acceptance."}


def _self_check():
    checks, examples = [], []
    def check(name, ok, evidence=None):
        checks.append({"name": name, "passed": bool(ok), "evidence": evidence or {}})
    for female in (False, True):
        identity, base = ("f01" if female else "m01"), SKIN_REFERENCES[female]
        source = _source(female)
        errors = [math.dist(_map_pixel(*xy, female), px) for _, xy, px in _landmarks(female)]
        check(identity+".immutable_original_png_hash_and_size", source["sha256"] == SOURCES[female][1] and source["source_size"] == (1254, 1254))
        check(identity+".actual_landmark_alignment_is_subpixel", max(errors) < 1e-6, {"maximum_error_px": max(errors), "landmarks": len(errors)})
        check(identity+".body_neck_side_back_and_non_skin_are_unchanged", all(sample_portrait(base, .2, .5, female, feature) == base for feature in PASSTHROUGH_FEATURES) and sample_portrait(base, 0., 0., female) == base and sample_portrait(base, 1., .5, female) == base and sample_portrait(base, 0., .5, female, front=0.) == base)
        ex, ey = (.420, .636) if female else (.406, .620)
        check(identity+".painted_eyeballs_catchlights_and_brows_are_excluded", all(sample_portrait(base, side*ex, y, female) == base for side in (-1., 1.) for y in (ey, ey+.145)))
        samples = [(x/20., y/30., sample_portrait(base, x/20., y/30., female)) for x in range(-20, 21) for y in range(34)]
        changes = [max(abs(a-b) for a, b in zip(rgb, base)) for _, _, rgb in samples]
        check(identity+".skin_values_are_finite_bounded_and_spatially_varied", all(math.isfinite(c) and 0. <= c <= 1. for _, _, rgb in samples for c in rgb) and len(set(rgb for _, _, rgb in samples)) > 300)
        check(identity+".transfer_is_visible_but_has_no_unbounded_shadow_bake", .045 < max(changes) < .20, {"maximum_srgb_channel_change": max(changes), "median_change": statistics.median(changes)})
        for name, x, y in (("cheek", -.56, .44), ("nose", 0., .451 if female else .424), ("lip", 0., .288 if female else .250), ("forehead", .16, .94)):
            sx, sy = _map_pixel(x, y, female)
            examples.append({"identity": identity, "region": name, "target_xy": [x, y], "actual_source_pixel": [sx, sy], "raw_paint_srgb": _pixel(source["image"], sx, sy), "base_body_srgb": base, "result_srgb": sample_portrait(base, x, y, female), "source_sha256": source["sha256"]})
    check("sources_and_warps_are_shared_cached_without_repeated_decode", _source(False) is _source(False) and _source(True) is _source(True))
    return {"task": "EXP34_ORIGINAL_PAINT_ALIGNMENT", "result": "PASS" if all(c["passed"] for c in checks) else "FAIL", "passed": sum(c["passed"] for c in checks), "total": len(checks), "checks": checks, "sampled_examples": examples, "contract": paint_contract(), "scope": "Source/format/alignment/colour bounds only; no engine run or game-art acceptance."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = _self_check()
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n")
    print(json.dumps({key: result[key] for key in ("result", "passed", "total")}))
    raise SystemExit(0 if result["result"] == "PASS" else 1)

"""Project-authored colour fields and UV textures for two fictional portraits.

No photo, scan, character, body dataset or third-party texture is loaded. These
small numerical fields supply colour variation; geometry and real scene lights
must supply shape, occlusion and highlights. All public RGB values and PNGs are
sRGB. The existing Mesh.vertex writer converts vertex colour to linear ONCE.
PNG albedo is decoded as sRGB by the material importer, not pre-linearised here.

The skin material is shared with the body. Consequently face-specific colour
is authored in vertices, while its tiled texture stays neutral. Eye geometry
uses white vertices and a separate eye albedo texture. Hair UV U is across an
individual lock, V is root to tip. There are no painted white catchlights.
"""
from __future__ import annotations

import argparse
import functools
import hashlib
import json
import math
import struct
import zlib
from pathlib import Path

VERSION = "original_portrait_materials_v1"
SKIN_REFERENCES = {False: (.69, .48, .36), True: (.77, .56, .44)}
HAIR_REFERENCES = {False: (.083, .061, .045), True: (.073, .052, .039)}
EYE_DIAMETER_M = .032
IRIS_RADIUS_M = .0052
PUPIL_RADIUS_M = .0020
TAU = math.tau


def _clamp(value, low=0., high=1.):
    return max(low, min(high, float(value)))


def _smooth(low, high, value):
    t = _clamp((value-low)/(high-low))
    return t*t*(3.-2.*t)


def _gauss(value, center, width):
    return math.exp(-.5*((value-center)/width)**2)


def _mix(a, b, amount):
    return tuple(_clamp(x+(y-x)*amount) for x, y in zip(a, b))


def _linear_channel(value):
    return value/12.92 if value <= .04045 else ((value+.055)/1.055)**2.4


def face_color(base_skin, x, y, female=False, feature="face", front=1.):
    """Return sRGB from normalised face x[-1,1], chin0 to forehead1.

    Geometry agreement: y=(original_Y-1.458)/.184. ``feature`` may be face,
    eyelid, lip_upper/lip_lower, mouth, ear/ear_inner, or head_back. Base skin
    remains the generator's existing reference; colour controls can retain
    their current relative skin gain. Neither key lighting nor eye sockets
    are painted as fixed black shadows.
    """
    base = tuple(float(c) for c in base_skin[:3])
    if len(base) != 3 or not all(math.isfinite(c) and 0. <= c <= 1. for c in base):
        raise ValueError("base_skin must have three finite sRGB channels")
    if not all(math.isfinite(float(v)) for v in (x, y, front)):
        raise ValueError("face coordinates must be finite")
    x, y, front = float(x), float(y), _clamp(front)
    if feature in ("head_back", "back", "neck"):
        return base
    if feature in ("lip", "lip_upper", "lip_lower"):
        # Muted living-tissue colour, not lipstick or a black mouth decal.
        pigment = (.57, .31, .28) if female else (.49, .27, .235)
        amount = .53 if feature == "lip_upper" else .43
        return _mix(base, pigment, amount)
    if feature == "mouth":
        return _mix(base, (.27, .13, .115), .64)
    if feature in ("ear", "ear_inner"):
        amount = .18 if feature == "ear_inner" else .085
        return _mix(base, (_clamp(base[0]+.08), base[1]*.80, base[2]*.84), amount)
    if feature == "eyelid":
        return _mix(base, (.63, .38, .32) if female else (.56, .33, .275), .105)
    if feature != "face":
        raise ValueError("unknown portrait skin feature: " + str(feature))
    # Fade regional pigmentation at the neck and rear-side island boundary.
    mask = front*_smooth(.045, .20, y)*(1.-_smooth(.75, 1., abs(x)))
    cheek = (_gauss(x, -.53, .23)+_gauss(x, .53, .23))*_gauss(y, .40, .10)
    nose = _gauss(x, 0., .16)*_gauss(y, .40, .15)
    lower_lid = (_gauss(x, -.38, .21)+_gauss(x, .38, .21))*_gauss(y, .57, .036)
    temple = _gauss(abs(x), .71, .12)*_gauss(y, .68, .14)
    jaw = _gauss(x, 0., .56)*_gauss(y, .15, .08)
    blush = 1. if female else .68
    # Fine, low-amplitude chromatic variation is not an albedo pore shadow.
    variation = .0012*math.sin(31.*x+17.*y)*math.sin(23.*y-11.*x)
    delta = (
        .025*blush*cheek+.012*nose-.006*lower_lid-.003*temple+variation,
        -.007*blush*cheek-.004*nose-.006*lower_lid-.002*temple+variation*.5,
        -.008*blush*cheek-.005*nose-.002*lower_lid+.003*temple+variation*.3,
    )
    if not female:
        # This character has a clean-shaven, slightly cooler lower face.
        delta = (delta[0]-.003*jaw, delta[1]-.001*jaw, delta[2]+.002*jaw)
    return tuple(_clamp(channel+mask*offset) for channel, offset in zip(base, delta))


def hair_color(u, v, female=False, feature="lock"):
    """Dark natural umber, with root depth and small per-lock variation.

    This deliberately replaces the earlier near-zero cap vertex colours.
    Runtime custom hair must derive its source reference from the original
    source mask, not the old hard-coded linear red .00048.
    """
    if not all(math.isfinite(float(c)) for c in (u, v)):
        raise ValueError("hair coordinates must be finite")
    u, v = float(u), _clamp(v)
    reference = HAIR_REFERENCES[bool(female)]
    if feature not in ("lock", "scalp", "brow"):
        raise ValueError("unknown hair feature")
    gain = .94+.045*_smooth(.05, .45, v)+.015*math.sin(TAU*(3.*u+.15*v))
    if feature == "scalp":
        gain *= .82
    elif feature == "brow":
        gain *= .87
    return tuple(_clamp(c*gain) for c in reference)


def eye_uv(local_x, local_y, diameter=EYE_DIAMETER_M):
    """Isotropic 32mm atlas coordinates about the actual eye centre.

    Use physical local x/y offsets, NOT rectangular normalisation of each
    almond-shaped row. The latter would distort a circular iris near the lids.
    """
    if not math.isfinite(diameter) or diameter <= 0.:
        raise ValueError("eye atlas diameter must be positive and finite")
    if not all(math.isfinite(float(c)) for c in (local_x, local_y)):
        raise ValueError("eye offsets must be finite")
    return .5+float(local_x)/diameter, .5+float(local_y)/diameter


def eye_color(u, v, female=False):
    """Opaque sclera/iris/pupil albedo; wet reflections belong to PBR.

    Eye white vertices and baseColorFactor must stay white. One curved eye
    surface samples this atlas: no stacked dark iris/pupil stickers are needed.
    """
    dx, dy = (float(u)-.5)*.032, (float(v)-.5)*.032
    radius, angle = math.hypot(dx, dy), math.atan2(dy, dx)
    # Mild warm-grey sclera, with tiny vessels restricted to peripheral white.
    white = (.89, .885, .865)
    peripheral = _smooth(.0070, .0145, radius)
    vessel = 0.
    for line, phase in ((.0038, .7), (-.0049, 2.1), (.0064, 3.6)):
        curve = line+.00045*math.sin(dx*470.+phase)+.00025*math.sin(dx*910.+phase)
        vessel += _gauss(dy, curve, .000075)
    vessel = min(1., vessel)*peripheral*.045
    sclera = _mix(white, (.76, .46, .42), vessel)
    if radius > IRIS_RADIUS_M+.00015:
        return sclera
    radial = _clamp((radius-PUPIL_RADIUS_M)/(IRIS_RADIUS_M-PUPIL_RADIUS_M))
    # Radial fibres, interrupted crypts and a soft collarette; no baked glint.
    fibre = .5+.5*math.sin(43.*angle+3.2*math.sin(11.*angle)+radial*13.)
    fine = math.sin(91.*angle-radial*21.)*math.sin(29.*angle+radial*9.)
    crypt = (max(0., math.sin(17.*angle+radial*19.))**6)*_gauss(radial, .45, .26)
    collarette = _gauss(radius, .00285, .00035)
    iris_base = (.285, .172, .100) if female else (.315, .198, .112)
    iris = (
        iris_base[0]+.050*(fibre-.5)+.015*fine+.024*collarette-.025*crypt,
        iris_base[1]+.034*(fibre-.5)+.010*fine+.017*collarette-.019*crypt,
        iris_base[2]+.018*(fibre-.5)+.005*fine+.006*collarette-.010*crypt,
    )
    limbus = _smooth(IRIS_RADIUS_M-.00042, IRIS_RADIUS_M, radius)
    iris = _mix(iris, (.14, .093, .058), limbus*.55)
    edge = _smooth(IRIS_RADIUS_M-.00012, IRIS_RADIUS_M+.00015, radius)
    iris = _mix(iris, sclera, edge)
    pupil_amount = 1.-_smooth(PUPIL_RADIUS_M-.00010, PUPIL_RADIUS_M+.00012, radius)
    return _mix(iris, (.022, .016, .012), pupil_amount)


def _skin_texture_color(u, v):
    # Neutral multiplication near1: keep original skin reference and avoid
    # doubling the existing vertex pigmentation with another brown texture.
    grain = math.sin(TAU*(37.*u+19.*v))*math.sin(TAU*(23.*v-13.*u))
    pore = max(0., math.sin(TAU*(61.*u+7.*v))*math.sin(TAU*(59.*v-11.*u)))**14
    value = _clamp(.997+.0018*grain-.005*pore, .988, 1.)
    return value, value, value


def _hair_texture_color(u, v, female):
    # Narrow strands bend along the lock. There is no broad pale helmet band.
    bend = (.015 if female else .026)*math.sin(TAU*v)*math.sin(TAU*u)
    phase = u+bend
    strand = math.sin(TAU*(71.*phase+.15*math.sin(TAU*v)))
    bundles = math.sin(TAU*(23.*phase+.10*math.sin(TAU*(v+u))))
    grain = math.sin(TAU*(127.*u+37.*v))*math.sin(TAU*(61.*v-19.*u))
    value = _clamp(.963+.017*strand+.009*bundles+.003*grain, .93, .995)
    return value, value, value


def _png_chunk(kind, content):
    return struct.pack(">I", len(content))+kind+content+struct.pack(">I", zlib.crc32(kind+content)&0xffffffff)


@functools.lru_cache(maxsize=24)
def texture_png(kind, female=False, size=256):
    """Return an original RGB PNG; no file IO and no external dependencies.

    ``skin``/``hair`` are neutral tint-preserving multiplication textures;
    ``eye`` is absolute sRGB albedo on white eye vertices. Eye256 covers32mm,
    so the10.4mm iris spans83texels. Identical identity/size calls share bytes.
    """
    if kind not in ("skin", "hair", "eye"):
        raise ValueError("portrait texture kind must be skin,hair or eye")
    if isinstance(size, bool) or not isinstance(size, int) or not 32 <= size <= 1024:
        raise ValueError("texture size must be an integer in32..1024")
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            u, v = (x+.5)/size, (y+.5)/size
            color = (_skin_texture_color(u, v) if kind == "skin" else
                     _hair_texture_color(u, v, female) if kind == "hair" else
                     eye_color(u, v, female))
            raw.extend(round(_clamp(channel)*255.) for channel in color)
    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n"+_png_chunk(b"IHDR", header)+
            _png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))+_png_chunk(b"IEND", b""))


def material_contract():
    """Small manifest payload; integration remains the generator's job."""
    return {
        "version": VERSION,
        "source_assets_read": [],
        "provenance": "Original numerical colour fields and PNGs;no photos,scans,game textures or third-party assets.",
        "color_space": "Public RGB and PNG sRGB;convert vertex RGB once in Mesh.vertex;do not pre-linearise PNG.",
        "skin_reference_m": list(SKIN_REFERENCES[False]),
        "skin_reference_f": list(SKIN_REFERENCES[True]),
        "skin_texture": "Neutral microvariation only;regional face/ear/lid/lip colour is vertex-authored,so shared body material gets no painted face.",
        "eye": {"atlas_diameter_m": EYE_DIAMETER_M, "iris_radius_m": IRIS_RADIUS_M,
                "pupil_radius_m": PUPIL_RADIUS_M, "vertex_color": [1, 1, 1, 1],
                "base_color_factor": [1, 1, 1, 1], "kind": "eye",
                "material_semantic": "Resident_Original_Eye", "baked_catchlights": False,
                "requires_separate_atlas_from_skin": True},
        "hair": {"uv": "U across one lock,Vroot-to-tip;scalp is separate geometry.",
                 "reference_srgb_m": list(HAIR_REFERENCES[False]),
                 "reference_srgb_f": list(HAIR_REFERENCES[True]),
                 "reference_red_linear_m": _linear_channel(HAIR_REFERENCES[False][0]),
                 "reference_red_linear_f": _linear_channel(HAIR_REFERENCES[True][0]),
                 "customization_requires_source_reference": "Derive median original hair-mask vertex red per source;do not retain legacy .00048 divisor.",
                 "baked_specular_bands": False},
        "runtime": "No runtime code changed by this module. Existing skin/hair/eye roles remain;roughness,SSS and live highlights belong to the existing PBR helper.",
        "scope": "Material authoring,not a realistic-human acceptance result. Geometry,UVintegration,lighting,allvariants and runtime controls need actual native review.",
    }


def _self_check():
    """Independent format/range/semantic checks;not a native appearance test."""
    checks, outputs = [], {}
    def check(name, ok, evidence=None):
        checks.append({"name": name, "passed": bool(ok), "evidence": evidence or {}})
    for female in (False, True):
        identity = "f" if female else "m"
        base = SKIN_REFERENCES[female]
        samples = [face_color(base, x/10., y/10., female) for x in range(-10, 11) for y in range(11)]
        check(identity+".face_finite_in_range", all(math.isfinite(c) and 0 <= c <= 1 for rgb in samples for c in rgb))
        check(identity+".neck_and_side_boundaries_keep_exact_base", all(face_color(base, x, 0., female) == base for x in (-1., 0., 1.)) and all(face_color(base, x, .5, female) == base for x in (-1., 1.)))
        check(identity+".regional_colour_is_subtle_not_uniform_repaint", max(abs(c-b) for rgb in samples for c, b in zip(rgb, base)) < .035 and len(set(samples)) > 100)
        check(identity+".iris_is_detailed_brown_and_not_pupil_black", all(eye_color(.5+math.cos(t)*.0038/.032, .5+math.sin(t)*.0038/.032, female)[0] > .20 for t in (0., 1., 2., 3.)))
        check(identity+".sclera_and_pupil_are_separate_opaque_albedo", min(eye_color(.90, .5, female)) > .80 and max(eye_color(.5, .5, female)) < .03)
        for kind in ("skin", "hair", "eye"):
            payload = texture_png(kind, female, 128)
            pointer, compressed, crc_ok = 8, bytearray(), True
            while pointer < len(payload):
                count = struct.unpack(">I", payload[pointer:pointer+4])[0]
                tag = payload[pointer+4:pointer+8];data = payload[pointer+8:pointer+8+count]
                crc = struct.unpack(">I", payload[pointer+8+count:pointer+12+count])[0]
                crc_ok &= crc == zlib.crc32(tag+data)&0xffffffff
                if tag == b"IDAT":compressed.extend(data)
                pointer += count+12
            decoded = zlib.decompress(bytes(compressed))
            pixel_bytes = [c for row in range(128) for c in decoded[row*385+1:(row+1)*385]]
            check(identity+"."+kind+".png_decodes_and_crc_matches", crc_ok and struct.unpack(">II", payload[16:24]) == (128, 128) and len(decoded) == 128*385)
            if kind == "skin":check(identity+".skin_texture_is_neutral_and_near_white", min(pixel_bytes) >= 250 and max(pixel_bytes) <= 255 and all(decoded[row*385+1+i] == decoded[row*385+2+i] == decoded[row*385+3+i] for row in range(128) for i in range(0, 384, 3)))
            if kind == "hair":check(identity+".hair_texture_has_no_white_shine_band", min(pixel_bytes) >= 235 and max(pixel_bytes) <= 254)
            outputs[identity+"_"+kind] = {"size": 128, "bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()}
    check("uv_retains_actual_physical_iris_scale", eye_uv(0., 0.) == (.5, .5) and abs((eye_uv(.0052, 0.)[0]-.5)*.032-.0052) < 1e-12)
    check("cached_texture_is_byte_identical", texture_png("eye", False, 128) is texture_png("eye", False, 128))
    return {"task": "EXP34_ORIGINAL_PORTRAIT_MATERIAL_FIELDS", "result": "PASS" if all(c["passed"] for c in checks) else "FAIL", "passed": sum(c["passed"] for c in checks), "total": len(checks), "checks": checks, "textures": outputs, "contract": material_contract(), "scope": "Pure authoring format/range/semantic checks only;no native appearance,anatomy,attractiveness or runtime acceptance claim."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--preview-directory", type=Path)
    args = parser.parse_args()
    result = _self_check()
    if args.preview_directory:
        args.preview_directory.mkdir(parents=True, exist_ok=True)
        for female in (False, True):
            for kind in ("skin", "hair", "eye"):
                (args.preview_directory/(("f" if female else "m")+"_"+kind+".png")).write_bytes(texture_png(kind, female, 256))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n")
    print(json.dumps({key: result[key] for key in ("result", "passed", "total")}))
    raise SystemExit(0 if result["result"] == "PASS" else 1)

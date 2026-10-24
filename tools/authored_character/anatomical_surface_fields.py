"""Continuous, project-authored surface anatomy for the Seoul resident.

Coordinates are metres, +Y up, +Z anterior. These numbers are game-art design
choices, not scans, medical measurements or a population/sex body standard.
No mesh, image, anatomical diagram or third-party body data is loaded. General
anatomical relationships were consulted in the OpenStax pages in PROVENANCE.
This module moves presentation vertices only. It never edits the skeleton,
rest joints, skin weights, connectivity, UVs, hands or foot contact geometry.
"""
from __future__ import annotations

import math
from typing import Iterable, Sequence

PROFILES = ("standard", "soft", "athletic")
PROVENANCE = (
    "https://openstax.org/books/anatomy-and-physiology/pages/11-6-appendicular-muscles-of-the-pelvic-girdle-and-lower-limbs",
    "https://openstax.org/books/anatomy-and-physiology/pages/11-4-axial-muscles-of-the-abdominal-wall-and-thorax",
    "https://openstax.org/books/anatomy-and-physiology-2e/pages/8-3-the-pelvic-girdle-and-pelvis",
)


def _smooth(a: float, b: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def _g(x: float, center: float, width: float) -> float:
    return math.exp(-0.5 * ((x - center) / width) ** 2)


def _lobe(x: float, y: float, cx: float, cy: float,
          sx: float, sy: float) -> float:
    return _g(x, cx, sx) * _g(y, cy, sy)


def _ridge(x: float, y: float, a: tuple[float, float],
           b: tuple[float, float], width: float) -> float:
    """A tapered attachment-to-attachment ridge, rather than repeated spheres.

    A C1 endpoint envelope makes the feature merge into its origin/insertion.
    Its width is perpendicular to the long axis in this two-dimensional plane.
    """
    vx, vy = b[0] - a[0], b[1] - a[1]
    t = ((x - a[0]) * vx + (y - a[1]) * vy) / (vx * vx + vy * vy)
    if t <= 0.0 or t >= 1.0:
        return 0.0
    cx, cy = a[0] + vx * t, a[1] + vy * t
    perpendicular = math.hypot(x - cx, y - cy)
    envelope = math.sin(math.pi * t) ** 2
    return envelope * _g(perpendicular, 0.0, width)


def _segment_distance(p: tuple[float, float, float],
                      a: tuple[float, float, float],
                      b: tuple[float, float, float]) -> float:
    ab = tuple(bi - ai for ai, bi in zip(a, b))
    ap = tuple(pi - ai for ai, pi in zip(a, p))
    t = max(0.0, min(1.0, sum(v * w for v, w in zip(ap, ab)) /
                         sum(v * v for v in ab)))
    return math.sqrt(sum((pi - ai - v * t) ** 2
                         for pi, ai, v in zip(p, a, ab)))


def _protection_gate(p: tuple[float, float, float]) -> float:
    # Shoes/bare soles/toes and the 19 mm wrist bridge retain their exact
    # source positions. The hand capsule includes the spread thumb/fingers.
    x, y, z = p
    gate = _smooth(0.145, 0.215, y) * (1.0 - _smooth(1.415, 1.450, y))
    for side in (-1.0, 1.0):
        distance = _segment_distance(
            p, (side * 0.259, 0.855, 0.006),
            (side * 0.268, 0.700, 0.010))
        gate *= _smooth(0.065, 0.110, distance)
    return gate


def _arm_axis(y: float) -> tuple[float, float]:
    # The immutable rig's upper arm and forearm form different oblique axes.
    # Blend through the elbow instead of giving the whole arm a cylinder axis.
    fore_t = max(0.0, min(1.0, (y - 0.849) / 0.249))
    upper_t = max(0.0, min(1.0, (y - 1.098) / 0.287))
    blend = _smooth(1.060, 1.135, y)
    fore_x, upper_x = 0.259 - 0.027 * fore_t, 0.232 - 0.054 * upper_t
    return fore_x * (1.0 - blend) + upper_x * blend, 0.006 * (1.0 - fore_t)


def _leg_axis(y: float) -> tuple[float, float]:
    t = max(0.0, min(1.0, (y - 0.111) / 0.814))
    return 0.098 - 0.005 * t, 0.005 + 0.007 * _g(y, 0.515, 0.125)


def displacement(position: Sequence[float], profile: str = "standard",
                 female: bool = False) -> tuple[float, float, float]:
    """Return a bounded continuous offset, without modifying ``position``.

    It is one coordinate field for skin, clipped swimwear, seams and clothing.
    Bone names are deliberately absent: adjoining surfaces at the same point
    get the same anatomical offset, regardless of material or dominant bone.
    Head/hand/foot influence protection is additionally enforced by the batch
    API, but these geometric windows already fade before those shared joins.
    """
    if profile not in PROFILES:
        raise ValueError("unknown authored body profile: " + str(profile))
    if len(position) != 3 or not all(math.isfinite(float(v)) for v in position):
        raise ValueError("a finite three-dimensional position is required")
    x, y, z = (float(v) for v in position)
    p = (x, y, z)
    protected = _protection_gate(p)
    if protected == 0.0:
        return (0.0, 0.0, 0.0)
    soft, athletic = profile == "soft", profile == "athletic"
    definition = 0.26 if soft else 1.65 if athletic else 1.0
    muscular = 1.0 if athletic else 0.30 if soft else 0.48
    dx = dy = dz = 0.0

    # Thorax and pelvic bowl have different sagittal inclinations. Features
    # are evaluated in these two local anatomical frames, not a global scale.
    rib_y = y + 0.105 * (z + 0.005)
    hip_y = y - 0.145 * (z + 0.005)
    front = _smooth(-0.015, 0.065, z)
    rear = 1.0 - _smooth(-0.065, 0.015, z)
    side_width = 0.175 + 0.030 * _g(y, 1.300, 0.100)
    side_shell = math.exp(-0.5 * (x / side_width) ** 4)
    core = side_shell * _smooth(0.820, 0.965, y) * (1.0 - _smooth(1.390, 1.450, y))
    ribs = _g(rib_y, 1.285, 0.102)
    waist = _g(y, 1.095, 0.085)
    pelvis = _g(hip_y, 0.940, 0.090)
    # A broad elliptical rib cage resolves into a narrower, softer waist.
    # Posterior rib plane is shallower than its anterior sternocostal arch.
    dx += x * (0.035 * ribs - 0.042 * waist) * core
    dz += ((-0.055 * (rib_y - 1.285)) * ribs +
           (0.080 * (hip_y - 0.940)) * pelvis) * core
    dz += (0.0038 * ribs * front - 0.0025 * ribs * rear) * core

    if athletic:
        dx += x * (0.152 * ribs - 0.035 * waist) * core
        dz += (0.010 * ribs * front - 0.006 * ribs * rear) * core
    elif soft:
        # Lower abdomen, flanks and posterior waist do not grow equally.
        # The lower ventral pad sags slightly; the rib cage remains legible.
        belly = _g(y, 1.050, 0.112)
        dx += x * (0.270 * belly + 0.105 * pelvis) * core
        dz += (0.031 * belly * _g(x, 0.0, 0.118) * front +
               z * 0.115 * belly - 0.013 * _g(y, 1.035, 0.100) * rear) * core
        dy -= 0.008 * _g(y, 1.025, 0.082) * _g(x, 0.0, 0.115) * front * core

    # Rectus forms two long columns; the external oblique runs down and
    # inward to the iliac region. No checkerboard six-pack grid is inserted.
    dz += 0.0035 * definition * (_lobe(x, y, -0.027, 1.135, 0.022, 0.087) +
                                 _lobe(x, y, 0.027, 1.135, 0.022, 0.087)) * front * core
    dz -= 0.0014 * definition * _g(x, 0.0, 0.010) * _g(y, 1.140, 0.095) * front * core
    dz -= 0.0015 * definition * _g(y, 1.072, 0.012) * _g(x, 0.0, 0.014) * front * core
    # Rib margin is an oblique arch, gradually hidden by subcutaneous fat.
    costal_y = 1.182 + 0.34 * abs(x)
    dz += 0.0024 * definition * _g(y, costal_y, 0.014) * _g(x, 0.0, 0.150) * front * core

    for side in (-1.0, 1.0):
        u = side * x
        # Two pectoral heads fan from sternum/clavicle towards the humeral
        # insertion; the lower border rises into the axilla laterally.
        pec_upper = _ridge(u, rib_y, (0.010, 1.367), (0.165, 1.325), 0.032)
        pec_lower = _ridge(u, rib_y, (0.012, 1.235), (0.162, 1.319), 0.038)
        pec = (0.55 * pec_upper + pec_lower) * front * side_shell
        dz += (0.0045 + 0.0100 * muscular) * pec
        dz -= 0.0020 * definition * _ridge(u, rib_y, (0.023, 1.222), (0.151, 1.287), 0.010) * front
        # Female surface contour is a modest soft tissue overlay, not a
        # different skeleton or exaggerated rigid sphere on the rib cage.
        if female:
            dz += (0.0060 if not soft else 0.0080) * _lobe(u, rib_y, 0.075, 1.279, 0.046, 0.047) * front
        clavicle = _ridge(u, y, (0.016, 1.409), (0.173, 1.386), 0.009)
        dz += 0.0035 * definition * clavicle * front
        dy += 0.0014 * definition * clavicle * front
        # Acromion is a small lateral shelf; deltoid wraps over it and
        # narrows down to its upper-arm insertion instead of a shoulder ball.
        acromion = _lobe(u, y, 0.178, 1.383, 0.022, 0.016) * _g(z, -0.001, 0.038)
        dx += side * 0.0030 * definition * acromion
        dy += 0.0017 * definition * acromion
        # Scapular medial border, inferior angle and broad latissimus plane.
        scapula = _ridge(u, y, (0.048, 1.390), (0.102, 1.287), 0.021)
        dz -= 0.0038 * definition * scapula * rear
        lat = _ridge(u, y, (0.158, 1.340), (0.104, 1.125), 0.052)
        dz -= (0.002 + 0.005 * muscular) * lat * rear
        dx += side * 0.0040 * muscular * lat * _g(z, -0.055, 0.065)
        trapezius = _ridge(u, y, (0.027, 1.450), (0.177, 1.382), 0.028)
        dz -= 0.0030 * definition * trapezius * rear
        oblique = _ridge(u, y, (0.146, 1.231), (0.099, 1.004), 0.031)
        dx += side * 0.0030 * definition * oblique * _g(z, 0.020, 0.080)
        dz += 0.0025 * definition * oblique * front
        iliac = _ridge(u, hip_y, (0.153, 0.976), (0.086, 1.014), 0.015)
        dx += side * 0.0025 * definition * iliac
        dz += 0.0023 * definition * iliac * front
        if soft:
            flank = _lobe(u, y, 0.132, 1.048, 0.052, 0.102)
            dx += side * 0.010 * flank * _g(z, -0.015, 0.105)
            dz -= 0.008 * flank * rear

        # Pelvis/gluteal mass continues down into the proximal thigh. Two
        # broad posterior lobes and a curved lower fold replace a boxy ledge.
        glute = _lobe(u, hip_y, 0.080, 0.923, 0.061, 0.068) * rear
        dz -= (0.009 if not athletic and not soft else 0.018 if athletic else 0.027) * glute
        dx += side * (0.004 if not soft else 0.010) * _lobe(u, hip_y, 0.142, 0.917, 0.040, 0.078) * _g(z, -0.035, 0.075)
        fold_y = 0.861 + 0.13 * (u - 0.060)
        dz += 0.0023 * definition * _g(y, fold_y, 0.013) * _g(u, 0.082, 0.050) * rear

        # Arm: three deltoid directions, anterior biceps, longer posterior
        # triceps, epicondyles/olecranon, then an oblique radial forearm ridge.
        ax, az = _arm_axis(y)
        local_x = x - side * ax
        radial = math.hypot(local_x, z - az)
        arm = _g(radial, 0.040, 0.035) * _smooth(0.875, 0.970, y) * (1.0 - _smooth(1.375, 1.445, y))
        arm_side = _smooth(0.115, 0.200, u)
        arm *= arm_side
        nx, nz = local_x / max(0.020, radial), (z - az) / max(0.020, radial)
        arm_front = _smooth(-0.010, 0.024, z - az)
        arm_rear = 1.0 - _smooth(-0.024, 0.010, z - az)
        upper = _g(y, 1.239, 0.083)
        deltoid = _g(y, 1.335, 0.054)
        soft_arm = 0.0080 if soft else 0.0
        bulge = ((0.0030 + 0.0070 * muscular) * deltoid +
                 (0.0015 + 0.0070 * muscular) * upper + soft_arm * _g(y, 1.215, 0.117)) * arm
        dx += nx * bulge
        dz += nz * bulge
        biceps = _g(y, 1.235, 0.076) * _g(local_x, -side * 0.004, 0.037)
        triceps = _g(y, 1.252, 0.099) * _g(local_x, side * 0.005, 0.039)
        dz += (0.0020 + 0.0060 * muscular) * biceps * arm_front * arm
        dz -= (0.0015 + 0.0055 * muscular) * triceps * arm_rear * arm
        # Front/lateral deltoid insertions run toward the humeral shaft.
        delt_ridge = _ridge(side * local_x, y, (0.036, 1.370), (0.004, 1.228), 0.020)
        dx += side * 0.004 * muscular * delt_ridge * arm
        elbow = _g(y, 1.098, 0.025)
        dz -= 0.0027 * definition * elbow * arm_rear * arm
        dz -= 0.0018 * definition * elbow * arm_front * arm
        dx += nx * 0.0025 * definition * elbow * _g(z - az, 0.0, 0.025) * arm
        forearm = _g(y, 1.015, 0.065)
        dx += nx * (0.0010 + 0.0035 * muscular + 0.0035 * soft) * forearm * arm
        dz += nz * (0.0005 + 0.0020 * muscular + 0.0030 * soft) * forearm * arm
        radial_ridge = _ridge(side * local_x, y, (0.029, 1.085), (0.012, 0.910), 0.014)
        dx += side * 0.0025 * definition * radial_ridge * arm
        dz += 0.0015 * definition * radial_ridge * arm_front * arm
        ulna = _g(local_x, -side * 0.009, 0.012) * _g(y, 0.984, 0.070)
        dz -= 0.0015 * definition * ulna * arm_rear * arm

        # Leg: the anterior quadriceps fan converges on a small patellar
        # region, while hamstrings descend posteriorly. Medial vastus is
        # lower than lateral vastus; calf heads also have different heights.
        lx, lz = _leg_axis(y)
        leg_x = x - side * lx
        leg_radius = math.hypot(leg_x, z - lz)
        leg = _g(leg_radius, 0.055, 0.043) * _smooth(0.145, 0.235, y) * (1.0 - _smooth(0.900, 1.000, y))
        leg *= _smooth(0.014, 0.045, abs(x))
        # Softly reject the opposite leg rather than a discontinuous sign(x).
        leg *= _smooth(-0.015, 0.055, u)
        lnx, lnz = leg_x / max(0.022, leg_radius), (z - lz) / max(0.022, leg_radius)
        leg_front = _smooth(-0.010, 0.034, z - lz)
        leg_rear = 1.0 - _smooth(-0.034, 0.010, z - lz)
        thigh = _g(y, 0.755, 0.127)
        calf = _g(y, 0.348, 0.090)
        bulk = ((0.0030 + 0.0090 * muscular + 0.0100 * soft) * thigh +
                (0.0010 + 0.0050 * muscular + 0.0045 * soft) * calf) * leg
        dx += lnx * bulk
        dz += lnz * bulk
        rectus = _ridge(side * leg_x, y, (-0.004, 0.882), (0.002, 0.558), 0.027)
        lateralis = _ridge(side * leg_x, y, (0.052, 0.846), (0.020, 0.567), 0.030)
        medialis = _lobe(side * leg_x, y, -0.024, 0.591, 0.023, 0.050)
        dz += (0.0025 * definition * rectus + 0.0038 * muscular * lateralis +
               0.0035 * definition * medialis) * leg_front * leg
        dx += side * 0.0045 * muscular * lateralis * leg
        hamstring = (_ridge(side * leg_x, y, (-0.020, 0.862), (-0.016, 0.555), 0.023) +
                     0.85 * _ridge(side * leg_x, y, (0.026, 0.851), (0.021, 0.551), 0.022))
        dz -= 0.0032 * definition * hamstring * leg_rear * leg
        if soft:
            # Blend posterior hip fat into the upper thigh without a second
            # rigid ring at the waistband or a symmetric series of balls.
            dx += side * 0.007 * _g(y, 0.850, 0.115) * _g(z, -0.020, 0.100) * leg
            dz -= 0.010 * _g(y, 0.854, 0.095) * leg_rear * leg
        patella = _lobe(leg_x, y, 0.0, 0.522, 0.025, 0.030)
        dz += 0.0032 * definition * patella * leg_front * leg
        # Popliteal hollow and tibial tuberosity are different surfaces.
        dz += 0.0030 * definition * _g(y, 0.505, 0.026) * leg_rear * leg
        dz += 0.0018 * definition * _lobe(leg_x, y, 0.0, 0.471, 0.017, 0.024) * leg_front * leg
        dx += lnx * 0.0018 * definition * _g(y, 0.515, 0.022) * leg
        medial_calf = _lobe(side * leg_x, y, -0.016, 0.330, 0.030, 0.071)
        lateral_calf = _lobe(side * leg_x, y, 0.018, 0.365, 0.027, 0.067)
        dz -= (0.0025 + 0.0040 * muscular) * (medial_calf + 0.72 * lateral_calf) * leg_rear * leg
        tibial_crest = _ridge(side * leg_x, y, (-0.004, 0.460), (-0.002, 0.165), 0.012)
        dz += 0.0021 * definition * tibial_crest * leg_front * leg
        tibialis = _ridge(side * leg_x, y, (0.022, 0.429), (0.008, 0.189), 0.018)
        dz += 0.0018 * definition * tibialis * leg_front * leg
        achilles = _g(leg_x, 0.0, 0.011) * _g(y, 0.202, 0.060)
        dz -= 0.0014 * definition * achilles * leg_rear * leg

    # A shallow spinal groove is flanked by long erector planes, not beads.
    back_core = rear * core * _g(y, 1.245, 0.140)
    dz += 0.0018 * definition * _g(x, 0.0, 0.012) * back_core
    dz -= 0.0017 * definition * (_g(x, -0.028, 0.019) + _g(x, 0.028, 0.019)) * back_core
    # Smooth saturation bounds a sum of overlapping features without clipping
    # vertices onto a plane or creating a hard ring at a fixed maximum radius.
    length = math.sqrt(dx * dx + dy * dy + dz * dz)
    maximum = 0.078 if soft else 0.052 if athletic else 0.030
    limit = maximum * math.tanh(length / maximum) / length if length else 1.0
    return (dx * protected * limit, dy * protected * limit, dz * protected * limit)


def deform_points(vertices: Iterable[Sequence[float]],
                  joints: Sequence[Sequence[int]],
                  weights: Sequence[Sequence[float]],
                  bone_names: Sequence[str], profile: str = "standard",
                  female: bool = False, garment: bool = False
                  ) -> list[tuple[float, float, float]]:
    """Return equally many new coordinates and preserve all input arrays.

    ``garment`` deliberately has no geometric effect. At a clipped swimsuit
    boundary a skin point and textile point must receive identical offsets.
    Fabric materials/normal maps can soften detail without splitting a seam.
    Protected native head/hand/finger/foot/toe influences remain exactly still.
    """
    if profile not in PROFILES:
        raise ValueError("unknown authored body profile: " + str(profile))
    points = list(vertices)
    if len(points) != len(joints) or len(points) != len(weights):
        raise ValueError("vertex/joint/weight row counts must match")
    names = [str(name) for name in bone_names]
    result: list[tuple[float, float, float]] = []
    for p, ids, values in zip(points, joints, weights):
        original = tuple(float(v) for v in p)
        if len(original) != 3 or not all(math.isfinite(v) for v in original):
            raise ValueError("non-finite or malformed source position")
        if len(ids) != len(values):
            raise ValueError("joint and weight influence counts must match")
        preserve = False
        for bone, amount in zip(ids, values):
            index, value = int(bone), float(amount)
            if index < 0 or index >= len(names) or not math.isfinite(value) or value < 0.0:
                raise ValueError("invalid native bone influence")
            if value <= 1e-8:
                continue
            title = names[index]
            if (title == "Bip01 Head" or " Finger" in title or
                    title.endswith(" Hand") or title.endswith(" Foot") or
                    title.endswith(" Toe0")):
                preserve = True
        if preserve:
            result.append(original)
        else:
            delta = displacement(original, profile, female)
            result.append(tuple(v + d for v, d in zip(original, delta)))
    return result


def design_contract() -> dict:
    return {
        "version": "authored_anatomical_surface_field_v1",
        "coordinates": "+Y up; +Z anterior; metres; immutable native skeleton",
        "profiles": list(PROFILES),
        "method": "shared continuous coordinate displacement; tilted rib and pelvic frames; directed muscle attachments; distributed soft tissue",
        "preserved": ["skeleton", "rest bones", "indices", "weights", "UVs", "protected head/hand/finger/foot/toe positions"],
        "garment_and_skin_geometry_field_identical": True,
        "references": list(PROVENANCE),
        "reference_use": "General surface relationships only; no image, diagram, mesh or measured data is copied or loaded.",
        "scope": "Project-authored game anatomy and fat distribution. Not a medical/anthropometric model, body scan, photorealism or completed visual acceptance.",
    }

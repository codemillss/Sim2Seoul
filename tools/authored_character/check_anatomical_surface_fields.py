#!/usr/bin/env python3
"""Independent input/protection/seam and coordinate-gradient helper checks.

This stencil is not an emitted-mesh, visual-quality or medical acceptance.
The existing native skin/triangle fixture must still exercise all body poses.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import time
import anatomical_surface_fields as anatomy


def determinant(j):
    return (j[0][0] * (j[1][1] * j[2][2] - j[1][2] * j[2][1])
            - j[0][1] * (j[1][0] * j[2][2] - j[1][2] * j[2][0])
            + j[0][2] * (j[1][0] * j[2][1] - j[1][1] * j[2][0]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, required=True)
    opts = parser.parse_args()
    if opts.report.exists():
        parser.error('preserve prior evidence: choose a fresh report path')
    started = time.monotonic()
    checks, observations = [], {}

    def check(name, passed, evidence=None):
        checks.append({'name': name, 'passed': bool(passed), 'evidence': evidence or {}})

    names = ['Bip01 Pelvis', 'Bip01 Head', 'Bip01 L Hand',
             'Bip01 R Finger11', 'Bip01 L Foot', 'Bip01 R Toe0', 'Bip01 Neck']
    points = [(0.10, 1.30, 0.07), (-0.09, 0.94, -0.11),
              (0.24, 1.02, 0.03), (0.0, 1.08, 0.09)]
    weights = [[1.0, 0.0, 0.0, 0.0] for _ in points]
    joints = [[0, 0, 0, 0] for _ in points]
    original = json.dumps([points, joints, weights, names])
    for profile in anatomy.PROFILES:
        out = anatomy.deform_points(points, joints, weights, names, profile=profile)
        check(profile + '.row_count_and_no_mutation', len(out) == len(points)
              and json.dumps([points, joints, weights, names]) == original)
        check(profile + '.garment_skin_identical', out == anatomy.deform_points(
            points, joints, weights, names, profile=profile, garment=True))
        for index in range(1, 6):
            check(profile + '.protected_native_bone_' + str(index),
                  anatomy.deform_points([points[0]], [[index]], [[1.0]], names,
                                        profile=profile) == [points[0]])
        for p in [(0, 0, 0), (0.098, 0.111, 0.005), (0.098, 0.041, 0.150),
                  (0.259, 0.849, 0.006), (0.268, 0.720, 0.010), (0, 1.685, -0.01)]:
            check(profile + '.protected_contact_' + str(p),
                  anatomy.displacement(p, profile) == (0.0, 0.0, 0.0))
        minimum, maximum, max_length, worst = math.inf, 0.0, 0.0, None
        for ix in range(9):
            for iy in range(22):
                for iz in range(9):
                    p = (-0.30 + ix * 0.075, 0.16 + iy * 0.060, -0.18 + iz * 0.045)
                    d = anatomy.displacement(p, profile)
                    max_length = max(max_length, math.sqrt(sum(v * v for v in d)))
                    j = []
                    for axis in range(3):
                        lo, hi = list(p), list(p)
                        lo[axis] -= 0.0005
                        hi[axis] += 0.0005
                        dl, dh = anatomy.displacement(lo, profile), anatomy.displacement(hi, profile)
                        j.append([(1.0 if row == axis else 0.0) + (dh[row] - dl[row]) / 0.001
                                  for row in range(3)])
                    value = determinant(j)
                    if value < minimum:
                        minimum, worst = value, p
                    maximum = max(maximum, value)
        observations[profile] = {
            'grid_samples': 1782, 'minimum_numeric_jacobian_determinant': minimum,
            'maximum_numeric_jacobian_determinant': maximum, 'minimum_location_m': worst,
            'maximum_sampled_displacement_m': max_length}
        check(profile + '.finite_nonfolding_coordinate_stencil',
              math.isfinite(minimum) and minimum > 0.10 and maximum < 5.0,
              observations[profile])
    report = {
        'task': 'EXP34_independent_numeric_anatomical_field_contract',
        'scope': 'Input immutability/protected contacts/skin-garment equality and independent finite differences in a coordinate stencil. Not actual mesh triangles, natural body appearance, medical accuracy or final runtime acceptance. Emitted 12GLB/516-pose deformation and native shape review remain required.',
        'source_sha256': {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in [Path(__file__), Path(anatomy.__file__)]},
        'checks': checks, 'observations': observations,
        'passed': sum(c['passed'] for c in checks), 'total': len(checks),
        'wall_seconds': time.monotonic() - started, 'design_contract': anatomy.design_contract()}
    opts.report.parent.mkdir(parents=True, exist_ok=True)
    opts.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['passed', 'total', 'wall_seconds', 'observations']}))
    return 0 if report['passed'] == report['total'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

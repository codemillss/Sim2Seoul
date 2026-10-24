#!/usr/bin/env python3
"""Audit real generated pre-sculpt joins, without writing or replacing assets.

Rebuilds the two actual bare base surfaces, then checks all body fields against
protected/nonprotected mesh edges and shared skin/cloth coordinates. This is
helper-boundary evidence, separate from emitted GLB/native visual acceptance.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import time
import anatomical_surface_fields as anatomy
import build_seoul_resident as generator


def protected(ids, weights, names):
    for index, amount in zip(ids, weights):
        if amount <= 1e-8:
            continue
        name = names[index]
        if (name == 'Bip01 Head' or ' Finger' in name or name.endswith(' Hand')
                or name.endswith(' Foot') or name.endswith(' Toe0')):
            return True
    return False


def distance(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, required=True)
    opts = parser.parse_args()
    if opts.report.exists():
        parser.error('choose a fresh report path')
    source_paths = [Path(__file__), Path(anatomy.__file__), Path(generator.__file__)]
    bindings = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in source_paths}
    started = time.monotonic()
    checks, observations = [], []
    for female in (False, True):
        # Exactly the production pre-sculpt build order, stopping before the
        # helper and profile-specific face/neck and soft-support postprocess.
        person = generator.Resident(female=female, swim=True, profile='standard')
        person.body()
        person.face()
        person.hair()
        person.hands()
        person.feet()
        person.bathing_suit()
        names = [b[0] for b in person.bones]
        for profile in anatomy.PROFILES:
            shared, mixed_count, max_mixed_nominal = {}, 0, 0.0
            maximum_protected_move, maximum_shared_separation = 0.0, 0.0
            mixed_examples = []
            for surface, mesh in enumerate(person.meshes):
                output = anatomy.deform_points(mesh.v, mesh.j, mesh.w, names,
                                               profile=profile, female=female,
                                               garment=surface in (0, 4, 5, 6))
                mask = [protected(j, w, names) for j, w in zip(mesh.j, mesh.w)]
                for index, (source, target) in enumerate(zip(mesh.v, output)):
                    if mask[index]:
                        maximum_protected_move = max(maximum_protected_move, distance(source, target))
                    key = tuple(round(v, 8) for v in source)
                    shared.setdefault(key, []).append((surface, source, target, mask[index]))
                edges = set()
                for at in range(0, len(mesh.i), 3):
                    triangle = mesh.i[at:at + 3]
                    for a, b in zip(triangle, triangle[1:] + triangle[:1]):
                        key = tuple(sorted((a, b)))
                        if key in edges or mask[a] == mask[b]:
                            continue
                        edges.add(key)
                        mixed_count += 1
                        protected_index = a if mask[a] else b
                        nominal = math.sqrt(sum(v * v for v in anatomy.displacement(
                            mesh.v[protected_index], profile, female)))
                        max_mixed_nominal = max(max_mixed_nominal, nominal)
                        if nominal > 1e-7 and len(mixed_examples) < 8:
                            mixed_examples.append({'surface': surface,
                                'protected_point': mesh.v[protected_index],
                                'other_point': mesh.v[b if mask[a] else a],
                                'ignored_nominal_displacement_m': nominal})
            repeated, cross_material, mixed_duplicates = 0, 0, 0
            for rows in shared.values():
                if len(rows) < 2:
                    continue
                repeated += 1
                cross_material += len({r[0] for r in rows}) > 1
                mixed_duplicates += len({r[3] for r in rows}) > 1
                for row in rows[1:]:
                    maximum_shared_separation = max(maximum_shared_separation,
                                                     distance(row[2], rows[0][2]))
            observation = {'female': female, 'profile': profile,
                'actual_source_vertices': sum(len(m.v) for m in person.meshes),
                'protected_nonprotected_triangle_edges': mixed_count,
                'maximum_nominal_field_at_protected_edge_endpoint_m': max_mixed_nominal,
                'mixed_endpoint_examples': mixed_examples,
                'maximum_actual_protected_vertex_move_m': maximum_protected_move,
                'repeated_source_coordinate_groups': repeated,
                'cross_material_shared_coordinate_groups': cross_material,
                'mixed_protection_shared_coordinate_groups': mixed_duplicates,
                'maximum_post_helper_shared_coordinate_separation_m': maximum_shared_separation}
            observations.append(observation)
            for suffix, passed in [
                ('protected_coordinates_exact', maximum_protected_move == 0.0),
                ('cross_material_shared_coordinates_preserved', cross_material > 100
                 and maximum_shared_separation < 1e-6),
                ('spatial_gate_precedes_actual_protected_edge', mixed_count > 0
                 and max_mixed_nominal < 1e-7)]:
                checks.append({'name': ('female' if female else 'male') + '.' + profile + '.' + suffix,
                               'passed': passed, 'evidence': observation})
    changes = [str(p) for p in source_paths
               if hashlib.sha256(p.read_bytes()).hexdigest() != bindings[str(p)]]
    checks.append({'name': 'audited_sources_unchanged', 'passed': not changes,
                   'evidence': {'changes': changes}})
    report = {'task': 'EXP34_actual_generated_anatomy_binding_and_material_boundary_audit',
        'passed': sum(c['passed'] for c in checks), 'total': len(checks),
        'checks': checks, 'observations': observations, 'source_sha256': bindings,
        'wall_seconds': time.monotonic() - started,
        'scope': 'Production pre-sculpt male/female bare meshes and all three helper fields. Verifies actual mesh binding boundaries and shared skin/cloth coordinates. Stops before separately authored facial/neck profile treatment and soft-support weight postprocessing. Does not establish every possible input weight field, emitted GLB deformation, natural appearance or medical accuracy.'}
    opts.report.parent.mkdir(parents=True, exist_ok=True)
    opts.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'passed': report['passed'], 'total': report['total'],
                      'observations': observations, 'wall_seconds': report['wall_seconds']}))
    return 0 if report['passed'] == report['total'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

#!/usr/bin/env python3
"""Independent L04 retained-geometry and runtime-summary audit.

No generator or production code is imported. Retained samples are independently
checked against frozen source-mesh prisms; every-tick extrema are runtime evidence.
View selection and visual judgement are deliberately outside this checker.
"""
import argparse
import gzip
import json
import math
from pathlib import Path

from check_daehanmun_evidence import number, vector, near, sub, norm, volume_bounds
from check_palace_evidence import polygons, volume_from_mesh
from check_public_evidence import polygon_inside, indexed_penetration


def finite(value):
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, dict):
        return all(finite(v) for v in value.values())
    if isinstance(value, list):
        return all(finite(v) for v in value)
    return True


def near_plane_ok(sample, volumes, bounds):
    """Reconstruct the near rectangle from camera basis and actual corner points."""
    rig = sample['rig']
    camera = rig['camera']
    pivot = rig['pivot']
    corners = sample['near_corners']
    basis = rig['basis']
    if not (len(corners) == 4 and len(basis) == 3
            and all(vector(v) for v in corners + basis)):
        return False
    local = [[sum(a*b for a, b in zip(sub(corner, camera), col))
              for col in basis] for corner in corners]
    hw = max(abs(v[0]) for v in local)
    hh = max(abs(v[1]) for v in local)
    fhalf = rig['near'] * math.tan(math.radians(rig['fov']) / 2)
    rectangle = (
        all(near(norm(col), 1, .002) for col in basis)
        and all(abs(sum(a*b for a, b in zip(basis[j], basis[k]))) <= .002
                for j, k in ((0, 1), (0, 2), (1, 2)))
        and near([pivot[j]+basis[2][j]*rig['distance'] for j in range(3)], camera, .002)
        and max(norm(sub(corner, camera)) for corner in corners) <= .200001
        and len({(1 if v[0] > 0 else -1, 1 if v[1] > 0 else -1) for v in local}) == 4
        and all(near(v[2], -rig['near'], .0001) and near(abs(v[0]), hw, .0001)
                and near(abs(v[1]), hh, .0001) for v in local)
        and hh > 0 and near(hw/hh, rig['aspect'], .002)
        and (near(hw, fhalf, .0001) or near(hh, fhalf, .0001))
        and near(rig['near'], .05, 1e-6) and near(rig['fov'], 65, 1e-6))
    corner_hit = any(
        bottom < corner[1] < top and xmin < corner[0] < xmax
        and zmin < corner[2] < zmax and polygon_inside([corner[0], corner[2]], poly)
        for corner in corners
        for (poly, bottom, top), (xmin, xmax, zmin, zmax) in zip(volumes, bounds))
    return rectangle and not corner_hit


def audit(record, baseline, public, world, w01, plan):
    """Return explicit checks; malformed or missing evidence fails closed."""
    checks = []

    def ck(name, passed, details=None):
        row = {'name': name, 'passed': bool(passed)}
        if details is not None:
            row['details'] = details
        checks.append(row)

    try:
        ck('schema', record['schema_version'] == 1 and record['task'] == 'L04'
           and public['task'] == 'W03' and world['task'] == 'E03'
           and w01['task'] == 'W01')
        ck('finite_values', all(finite(v) for v in (record, baseline, public, world, w01, plan)))
        inv = baseline['inventory']
        ck('baseline.census', inv['created_body_count'] == 692 and inv['active_body_count'] == 687)
        ck('inventory.before_exact_baseline', record['inventory_before'] == inv)
        ck('inventory.after_exact_baseline', record['inventory_after'] == inv)
        ck('actor.exact_baseline', record['actor'] == baseline['actor'])
        engine = record['engine']
        gpu = engine['display'].lower() != 'headless'
        ck('engine', engine['physics_hz'] == 60 and engine['render_fps'] == 60
           and (not gpu or engine['renderer'].lower() not in ('', 'headless')))

        # Source geometry, rather than the observer's obstacle list, defines solids.
        disabled = set(w01['disabled_source_ids'])
        selected = [m for m in world['meshes']
                    if m['role'] in ('Buildings', 'Barriers') and m['id'] not in disabled]
        volumes = [volume for mesh in selected for volume in volume_from_mesh(mesh)]
        for obstacle in w01['volume_obstacles']:
            volumes.extend((poly, obstacle['bottom'], obstacle['top']) for poly in obstacle['rings'])
        support = public['support']
        volumes.extend((poly, support['bottom_y_m'], support['top_y_m'])
                       for poly in polygons(support['geometry']))
        bounds = volume_bounds(volumes)
        movement = public['movement_rings']
        ck('independent_geometry.nonempty', bool(selected) and bool(volumes) and bool(movement))

        rows = record['cases']
        cases = {c['name']: c for c in rows}
        ck('case_names_unique', bool(rows) and len(cases) == len(rows))
        specs = plan.get('cases')
        if specs is not None:
            ck('plan.case_coverage', isinstance(specs, list) and bool(specs)
               and [s['name'] for s in specs] == [c['name'] for c in rows])
            specs_by_name = {s['name']: s for s in specs}
        else:
            specs_by_name = {}

        for c in rows:
            name = c['name']
            purpose = c['purpose']
            spec = specs_by_name.get(name, {})
            ck(name+'.purpose', purpose in ('walk', 'orbit')
               and ('purpose' not in spec or purpose == spec['purpose']))
            samples = c['samples']
            stats = c['all_tick_stats']
            ws = c['W03_stats']
            ticks = c['ticks']
            duration = c['duration_s']
            ck(name+'.clock', type(ticks) is int and ticks > 0
               and near(ticks/60, duration, .0001) and c['wall_s'] > 0
               and type(c['frames']) is int and c['frames'] >= 0 and c['recoveries'] == 0)
            expected_ticks = sorted({1, ticks, *range(6, ticks+1, 6)})
            ck(name+'.sample_clock', len(samples) == len(expected_ticks)
               and all(near(s['t'], tick/60, .0001) for s, tick in zip(samples, expected_ticks))
               and near(c['start'], samples[0]['player'], .07)
               and near(c['end'], samples[-1]['player'], .002))
            if 'first_physics_tick' in c or 'last_physics_tick' in c:
                ck(name+'.physics_clock', c['last_physics_tick']-c['first_physics_tick']+1 == ticks
                   and all(s['global_physics_tick'] == c['first_physics_tick']+tick-1
                           for s, tick in zip(samples, expected_ticks)))
            if gpu and duration >= 1:
                ck(name+'.real_clock', abs(c['wall_s']-duration) <= .02*duration
                   and abs(c['frames']/c['wall_s']-60) <= 12,
                   {'duration_s': duration, 'wall_s': c['wall_s'], 'frames': c['frames']})

            stats_fields = ('ticks', 'max_camera_overlap_count', 'max_near_hit_count',
                            'max_follow_error_m', 'max_length_excess_m', 'max_tick_mismatch',
                            'floor_ticks', 'min_distance', 'max_distance', 'min_player_y',
                            'max_player_y', 'camera_max_step_m')
            ws_fields = ('ticks', 'max_player_penetration_m', 'max_camera_penetration_m',
                         'floor_support_ticks', 'outside_movement_ticks', 'solid_contact_ticks')
            ck(name+'.all_ticks', all(number(stats[k]) for k in stats_fields)
               and all(number(ws[k]) for k in ws_fields)
               and ws['ticks'] == stats['ticks'] == ticks
               and 0 <= ws['max_player_penetration_m'] <= .005
               and 0 <= ws['max_camera_penetration_m'] <= .005
               and ws['floor_support_ticks'] == stats['floor_ticks'] == ticks
               and ws['outside_movement_ticks'] == 0 and ws['first_outside_point'] == []
               and stats['max_camera_overlap_count'] == stats['max_near_hit_count'] == stats['max_tick_mismatch'] == 0
               and 0 <= stats['max_follow_error_m'] <= .005
               and 0 <= stats['max_length_excess_m'] <= .005
               and 0 <= stats['min_distance'] <= stats['max_distance'] <= 6.005
               and -.005 <= stats['min_player_y'] <= stats['max_player_y'] <= .005
               and stats['camera_max_step_m'] >= 0)

            bad = []
            worstp = worstc = 0.
            for i, s in enumerate(samples):
                p = s['player']
                rig = s['rig']
                camera = rig['camera']
                pivot = [p[0], p[1]+1.3, p[2]]
                pp = indexed_penetration([p[0], p[1]+.85, p[2]], volumes, bounds, .3, .55)
                pc = indexed_penetration(camera, volumes, bounds, .2)
                worstp = max(worstp, pp)
                worstc = max(worstc, pc)
                okay = (
                    vector(p) and vector(camera) and abs(p[1]) <= .005
                    and s['inside_movement'] is True
                    and any(polygon_inside([p[0], p[2]], poly) for poly in movement)
                    and pp <= .005 and pc <= .005
                    and near(s['player_penetration_m'], pp, .0001)
                    and near(s['camera_penetration_m'], pc, .0001)
                    and ws['max_player_penetration_m']+.0001 >= pp
                    and ws['max_camera_penetration_m']+.0001 >= pc
                    and s['floor'] is True and s['floor_id'] == 'W03_support'
                    and near(s['floor_normal'], [0, 1, 0], .002)
                    and s['camera_overlap'] == [] and s['near_ray_hits'] == []
                    and near(rig['pivot'], pivot) and rig['mask'] == 1
                    and near(rig['probe_radius'], .2, 1e-6)
                    and rig['follow_ticks'] == rig['observed_ticks']
                    and 0 <= rig['distance'] <= rig['hit_length']+.005
                    and rig['hit_length'] <= rig['requested_distance']+.005
                    and 2 <= rig['requested_distance'] <= 6
                    and near(norm(sub(camera, pivot)), rig['distance'], .005)
                    and rig['input_enabled'] is True and rig['mouse_mode'] == (2 if gpu else 0)
                    and math.radians(-55)-1e-6 <= rig['pitch'] <= math.radians(15)+1e-6
                    and stats['min_distance']-.002 <= rig['distance'] <= stats['max_distance']+.002
                    and stats['min_player_y']-.002 <= p[1] <= stats['max_player_y']+.002
                    and near_plane_ok(s, volumes, bounds))
                if not okay:
                    bad.append(i)
            ck(name+'.independent_samples', not bad,
               {'failed_sample_indices': bad, 'max_player_penetration_m': worstp,
                'max_camera_penetration_m': worstc})
            ck(name+'.sample_step_bound', all(
                norm(sub(b['player'], a['player'])) <= 3.5*(b['t']-a['t'])+.005
                for a, b in zip(samples, samples[1:])))
            distance = norm(sub(samples[0]['player'], c['start'])) + sum(
                norm(sub(b['player'], a['player'])) for a, b in zip(samples, samples[1:]))
            if purpose == 'walk':
                expected = spec.get('expected_end_xz', c.get('expected_end_xz'))
                if expected is not None:
                    ck(name+'.walk_endpoint', vector(expected, 2)
                       and norm(sub(c['end'][::2], expected)) <= .08
                       and ('expected_end_xz' not in c or near(c['expected_end_xz'], expected, 1e-8)))
                ck(name+'.actual_walk_distance', duration <= 1 or distance > .001,
                   {'retained_distance_m': distance})
            elif purpose == 'orbit':
                yaws = [s['rig']['yaw'] for s in samples]
                yaw_change = sum(math.atan2(math.sin(b-a), math.cos(b-a))
                                 for a, b in zip(yaws, yaws[1:]))
                drift = max(norm(sub(s['player'], c['start'])) for s in samples)
                ck(name+'.actual_orbit', duration >= 6-1e-4 and abs(yaw_change) >= 5.9
                   and drift < .01 and norm(sub(c['end'], c['start'])) < .01,
                   {'unwrapped_yaw_change_rad': yaw_change, 'max_retained_player_drift_m': drift})
    except (KeyError, TypeError, ValueError, IndexError, ZeroDivisionError, OverflowError) as exc:
        ck('evidence_structure', False, {'error': type(exc).__name__+': '+str(exc)})
    return {'schema_version': 1, 'task': 'L04', 'passed': bool(checks) and all(c['passed'] for c in checks),
            'checks': checks, 'scope': 'Retained geometry independently checked; every-tick extrema are runtime summaries; visual judgement and human operation are separate.'}


def read(path):
    opener = gzip.open if str(path).endswith('.gz') else open
    with opener(path, 'rt') as stream:
        return json.load(stream)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('record', 'baseline', 'public', 'world', 'w01', 'plan'):
        parser.add_argument('--'+name, required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = audit(*(read(getattr(args, name)) for name in ('record', 'baseline', 'public', 'world', 'w01', 'plan')))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False)+'\n')
    print(json.dumps({'passed': result['passed'], 'checks': len(result['checks']), 'output': str(args.output)}))
    raise SystemExit(0 if result['passed'] else 1)


if __name__ == '__main__':
    main()

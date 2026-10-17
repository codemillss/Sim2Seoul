#!/usr/bin/env python3
"""Conforming refinement for thin EXP21 terrain triangles.

A narrow triangle sampled from a curved, continuous height reference can have a
large artificial cross-slope. Project its third vertex onto its longest edge,
query the reference there, and split every triangle sharing that edge. Existing
vertices, source pads and area are retained. The new edge point is shared, so the
operation introduces neither deleted faces nor a height clamp.
"""
from collections import defaultdict
import heapq
import math

GRADE_TRIGGER = 5.0
ASPECT_TRIGGER = 50.0
SPLIT_BUDGET = 256


def _metrics(triangle):
    a, b, c = triangle
    cx, cy, cz = (c[i]-a[i] for i in range(3))
    bx, by, bz = (b[i]-a[i] for i in range(3))
    nx, ny, nz = cy*bz-cz*by, cz*bx-cx*bz, cx*by-cy*bx
    double_area = abs(ny)
    squared_edges = [(triangle[(i+1)%3][0]-triangle[i][0])**2 +
                     (triangle[(i+1)%3][2]-triangle[i][2])**2 for i in range(3)]
    longest = max(range(3), key=squared_edges.__getitem__)
    return (math.hypot(nx, nz)/max(double_area, 1e-30),
            squared_edges[longest]/max(double_area, 1e-30),
            longest, double_area/2., ny)


def _edge_key(a, b):
    left = (round(a[0], 7), round(a[2], 7))
    right = (round(b[0], 7), round(b[2], 7))
    return (left, right) if left <= right else (right, left)


def condition_triangles(faces, cell_offsets, exterior_y):
    """Return new flat faces, cumulative per-cell offsets and explicit evidence.

    ``exterior_y(x,z)`` must use the same continuous terrain/pad reference as the
    input builder. All incident owners of the *same original XZ edge* receive
    the same inserted XYZ. The original owner cell is retained after splitting.
    Refine only when the proposed split improves the target grade by5percent.
    Steep reference gaps that cannot improve remain unchanged and are reported;
    this procedure does not flatten actual terrain or infer walk permission.
    """
    if len(faces) % 9:
        raise ValueError('Terrain faces must contain complete XYZ triangles')
    count = len(faces)//9
    if not cell_offsets or cell_offsets[0] != 0 or cell_offsets[-1] != count:
        raise ValueError('Cell offsets must start at zero and cover every face')
    if any(a > b for a, b in zip(cell_offsets, cell_offsets[1:])):
        raise ValueError('Cell offsets must be monotonic')
    triangles = [tuple(tuple(float(v) for v in faces[i+j:i+j+3]) for j in (0,3,6))
                 for i in range(0, len(faces), 9)]
    cells = [0]*count
    for cell, (start, end) in enumerate(zip(cell_offsets, cell_offsets[1:])):
        cells[start:end] = [cell]*(end-start)
    active = [True]*count
    edge_owners = defaultdict(set)
    pending = []
    area_before = []
    max_before = 0.

    def register(index):
        triangle = triangles[index]
        for j in range(3):
            edge_owners[_edge_key(triangle[j], triangle[(j+1)%3])].add(index)
        grade, aspect, _, area, _ = _metrics(triangle)
        if grade > GRADE_TRIGGER and aspect > ASPECT_TRIGGER:
            heapq.heappush(pending, (-grade, index))
        return grade, area

    for index in range(count):
        grade, area = register(index)
        max_before = max(max_before, grade)
        area_before.append(area)

    splits = []
    rejected_projection = []
    one_owner = 0
    multi_owner = 0
    split_faces = 0
    unimproved = []
    while pending and len(splits) < SPLIT_BUDGET:
        _, index = heapq.heappop(pending)
        if not active[index]:
            continue
        triangle = triangles[index]
        grade, aspect, longest, _, _ = _metrics(triangle)
        a, b, c = triangle[longest], triangle[(longest+1)%3], triangle[(longest+2)%3]
        dx, dz = b[0]-a[0], b[2]-a[2]
        denominator = dx*dx+dz*dz
        fraction = ((c[0]-a[0])*dx+(c[2]-a[2])*dz)/denominator
        if not 1e-6 < fraction < 1.-1e-6:
            rejected_projection.append({'triangle': index, 'fraction': fraction,
                                        'grade': grade, 'aspect': aspect})
            continue
        x, z = a[0]+fraction*dx, a[2]+fraction*dz
        point = (round(x, 7), round(float(exterior_y(x,z)), 7), round(z, 7))
        if not all(math.isfinite(v) for v in point):
            raise ValueError('Nonfinite inserted reference height')
        key = _edge_key(a, b)
        owners = sorted(i for i in edge_owners[key] if active[i])
        plans = []
        malformed_child = False
        target_after_grade = math.inf
        for owner in owners:
            old = triangles[owner]
            position = next(j for j in range(3) if _edge_key(old[j],old[(j+1)%3]) == key)
            aa, bb, cc = old[position], old[(position+1)%3], old[(position+2)%3]
            children = []
            for child in [(aa,point,cc),(point,bb,cc)]:
                if _metrics(child)[4] < 0.:
                    child = (child[0],child[2],child[1])
                if _metrics(child)[3] <= 1e-15:
                    malformed_child = True
                children.append(child)
            if owner == index:
                target_after_grade = max(_metrics(child)[0] for child in children)
            plans.append((owner,old,children))
        # A genuine narrow wall gap already carries steep reference heights.
        # Refining such a face cannot improve it; repeated near-endpoint
        # projections would only create smaller numerical slivers. Keep it and
        # expose the unresolved physical/reference steepness for journey review.
        if malformed_child or target_after_grade >= .95*grade:
            unimproved.append({'triangle': index, 'before_grade': grade,
                               'candidate_grade': target_after_grade,
                               'degenerate_candidate': malformed_child,
                               'reason': 'Reference projection does not improve conditioning by5percent; original face retained'})
            continue
        one_owner += len(owners) == 1
        multi_owner += len(owners) > 2
        for owner,old,children in plans:
            active[owner] = False
            for j in range(3):
                edge_owners[_edge_key(old[j],old[(j+1)%3])].discard(owner)
            for child in children:
                triangles.append(child)
                cells.append(cells[owner])
                active.append(True)
                register(len(triangles)-1)
            split_faces += 1
        splits.append({'trigger_triangle': index, 'before_grade': grade,
                       'before_aspect': aspect, 'edge_fraction': fraction,
                       'inserted_xyz': list(point), 'incident_triangles_split': len(owners)})

    ordered = sorted((i for i in range(len(triangles)) if active[i]),
                     key=lambda i: (cells[i], i))
    new_faces = []
    counts = [0]*(len(cell_offsets)-1)
    areas_after = []
    max_after = 0.
    remaining_bad = 0
    for index in ordered:
        triangle = triangles[index]
        grade, aspect, _, area, _ = _metrics(triangle)
        max_after = max(max_after, grade)
        remaining_bad += grade > GRADE_TRIGGER and aspect > ASPECT_TRIGGER
        areas_after.append(area)
        for point in triangle:
            new_faces.extend(point)
        counts[cells[index]] += 1
    new_offsets = [0]
    for cell_count in counts:
        new_offsets.append(new_offsets[-1]+cell_count)
    before_area, after_area = math.fsum(area_before), math.fsum(areas_after)
    stats = {
        'method': 'Conforming longest-edge projection with reference height; all incident owners split; owner cells retained',
        'grade_trigger': GRADE_TRIGGER, 'aspect_trigger': ASPECT_TRIGGER,
        'split_budget': SPLIT_BUDGET, 'edge_splits': len(splits),
        'incident_triangles_split': split_faces,
        'input_triangles': count, 'output_triangles': len(ordered),
        'maximum_triangle_grade_before': max_before,
        'maximum_triangle_grade_after': max_after,
        'remaining_bad_thin_triangles': remaining_bad,
        'budget_exhausted': bool(pending and len(splits) >= SPLIT_BUDGET),
        'one_owner_edges_split': one_owner, 'more_than_two_owner_edges_split': multi_owner,
        'projection_rejections': rejected_projection, 'unimproved_reference_candidates': unimproved,
        'area_xz_before_m2': before_area, 'area_xz_after_m2': after_area,
        'area_xz_change_m2': after_area-before_area,
        'original_vertices_moved': 0, 'source_pad_vertices_moved': 0,
        'faces_deleted_without_replacement': 0,
        'refinements': splits,
        'scope': 'Numerical conditioning only. Remaining steep terrain, inaccessible wall gaps and actual player journeys require separate review.'}
    if abs(after_area-before_area) > .001:
        raise ValueError(f'Conditioning changed projected surface area: {after_area-before_area}')
    return new_faces, new_offsets, stats

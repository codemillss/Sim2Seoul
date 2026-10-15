#!/usr/bin/env python3
"""L03 independently authored display meshes inside retained city envelopes.

This module only returns meshes. It creates no collision, routes, source data,
files, materials or runtime permissions. Ratios and spacing are visual choices,
not measured architectural dimensions.
"""

import math

from shapely import constrained_delaunay_triangles, orient_polygons
from shapely.geometry import LineString, Polygon, shape
from shapely.ops import unary_union

from prepare_palace_landmarks import Model, polygonal, surface_mesh
from prepare_world import mesh_polygon


PALETTE = frozenset(("glass", "frame", "stone", "window", "roof", "grass", "paving"))


def _ratio(recipe, key, default, low, high):
    value = float(recipe.get(key, default))
    if not math.isfinite(value) or not low <= value <= high:
        raise ValueError(f"Invalid authored ratio {key}: {value}")
    return value


def _metadata(item, **extra):
    return {
        "authorship": "independently authored manual simplification",
        "dimension_basis": "retained source footprint and existing vertical envelope only",
        "details_basis": "authored colour, curvature, proportions and repeated spacing; not a survey",
        "source_feature_id": item.get("feature_id"),
        "collision_generated": False,
        "runtime_permission": None,
        "external_media_imported": False,
        **extra,
    }


def _clip(model, geometry):
    parts = polygonal(geometry.intersection(model.footprint))
    return unary_union(parts) if parts else Polygon()


def _height(model, fraction):
    return model.bottom + model.height * fraction


def _add(model, name, material, geometry, low, high, role):
    model.add(name, material, geometry, max(model.bottom, low), min(model.top, high), role)


def _variable_shell(model, name, material, geometry, lower, upper, role):
    """Closed display shell with clipped caps and perimeter, including holes."""
    geometry = _clip(model, geometry)
    if geometry.is_empty:
        return
    geometry = orient_polygons(geometry)
    vertices, normals = [], []

    def append_mesh(mesh, reverse=False):
        vs, ns = mesh["vertices"], mesh["normals"]
        if reverse:
            for index in range(0, len(vs), 9):
                for offset in (6, 3, 0):
                    vertices.extend(vs[index + offset:index + offset + 3])
                    normals.extend(-v for v in ns[index + offset:index + offset + 3])
        else:
            vertices.extend(vs)
            normals.extend(ns)

    # Explicit grid breaks show the authored shallow curve instead of relying
    # on arbitrary triangulation diagonals across the whole cap.
    for index in range(12):
        u1 = model.umin + (model.umax - model.umin) * index / 12
        u2 = model.umin + (model.umax - model.umin) * (index + 1) / 12
        patch = geometry.intersection(model.rectangle(u1, model.vmin - 1, u2, model.vmax + 1))
        append_mesh(surface_mesh(patch, upper))
        append_mesh(surface_mesh(patch, lower), reverse=True)
    for poly in polygonal(geometry):
        for ring in (poly.exterior, *poly.interiors):
            coords = list(ring.coords)
            for a, b in zip(coords, coords[1:]):
                length = math.dist(a, b)
                if length <= 1e-10:
                    continue
                normal = ((b[1] - a[1]) / length, 0.0, -(b[0] - a[0]) / length)
                al, ah = (a[0], lower(*a), a[1]), (a[0], upper(*a), a[1])
                bl, bh = (b[0], lower(*b), b[1]), (b[0], upper(*b), b[1])
                for triangle in ((al, bh, ah), (al, bl, bh)):
                    for point in triangle:
                        vertices.extend(round(value, 6) for value in point)
                        normals.extend(round(value, 9) for value in normal)
    if vertices:
        model.components.append({"id": model.item["id"] + "_" + name,
                                 "material": material, "feature_role": role,
                                 "vertices": vertices, "normals": normals})


def _curved_front(model, depth, inset=0.0):
    """A faceted south/+Z bow; it is clipped, never an outward extension."""
    points = [model.world(model.umin - 1, model.vmin - 1),
              model.world(model.umax + 1, model.vmin - 1)]
    for index in range(17):
        u = model.umax - (model.umax - model.umin) * index / 16
        across = (u - model.uc) / max(model.hu, 1e-6)
        v = model.vmax - inset - depth * across * across
        points.append(model.world(u, v))
    return _clip(model, Polygon(points))


def _profile_patch(model, name, material, role, u1, u2, low_y, high_y,
                   front_low, front_high, offset=0.0):
    """One planar facet of a south-facing height/depth section.

    Intersecting the complete projected patch before triangulation preserves
    source holes and concave corners, including for relief in front of glass.
    """
    a, b = front_low(u1) + offset, front_low(u2) + offset
    c, d = front_high(u1) + offset, front_high(u2) + offset
    delta = (c + d - a - b) / 2
    if abs(delta) < 1e-8:
        raise ValueError("Authored front section must have nonzero depth change")
    patch = Polygon([model.world(u1, a), model.world(u2, b),
                     model.world(u2, d), model.world(u1, c)])
    patch = _clip(model, patch)

    def height(x, z):
        u, v = model.local(x, z)
        baseline = a + (b - a) * (u - u1) / (u2 - u1)
        fraction = max(0.0, min(1.0, (v - baseline) / delta))
        return low_y + (high_y - low_y) * fraction

    mesh = surface_mesh(patch, height)
    if not mesh["vertices"]:
        return
    if delta > 0:
        # The default graph normal points upward; on an outward-sloping front
        # its public-facing side is the reverse, toward south and slightly down.
        vertices, normals = [], []
        for index in range(0, len(mesh["vertices"]), 9):
            for offset_index in (6, 3, 0):
                vertices.extend(mesh["vertices"][index + offset_index:index + offset_index + 3])
                normals.extend(-n for n in mesh["normals"][index + offset_index:index + offset_index + 3])
        mesh = {"vertices": vertices, "normals": normals}
    model.components.append({"id": model.item["id"] + "_" + name,
                             "material": material, "feature_role": role, **mesh})


def _section_side(model, name, u, profile, front, sign):
    """Close the side of the authored profile on a source-clipped vertical line."""
    path = LineString([model.world(u, model.vmin - 1), model.world(u, model.vmax + 1)])
    cut = path.intersection(model.footprint)
    lines = [cut] if cut.geom_type == "LineString" else list(getattr(cut, "geoms", ()))
    section = Polygon([(model.vmin - 1, _height(model, profile[0][0]))]
                      + [(front(u, setback), _height(model, fraction)) for fraction, setback in profile]
                      + [(model.vmin - 1, _height(model, profile[-1][0]))])
    vertices, normals = [], []
    desired = (model.u[0] * sign, 0, model.u[1] * sign)
    for segment in lines:
        if segment.geom_type != "LineString":
            continue
        values = [model.local(x, z)[1] for x, z in segment.coords]
        clip = Polygon([(min(values), model.bottom), (max(values), model.bottom),
                        (max(values), model.top), (min(values), model.top)])
        for poly in polygonal(section.intersection(clip)):
            for triangle in constrained_delaunay_triangles(poly).geoms:
                points = [(model.world(u, v)[0], y, model.world(u, v)[1])
                          for v, y in list(triangle.exterior.coords)[:3]]
                a, b, c = points
                ab, ac = [b[k] - a[k] for k in range(3)], [c[k] - a[k] for k in range(3)]
                normal = (-(ab[1] * ac[2] - ab[2] * ac[1]),
                          -(ab[2] * ac[0] - ab[0] * ac[2]),
                          -(ab[0] * ac[1] - ab[1] * ac[0]))
                if sum(normal[k] * desired[k] for k in range(3)) < 0:
                    points.reverse()
                for point in points:
                    vertices.extend(round(value, 6) for value in point)
                    normals.extend(round(value, 9) for value in desired)
    if vertices:
        model.components.append({"id": model.item["id"] + "_" + name,
                                 "material": "glass", "feature_role": "curved_glass_mass",
                                 "vertices": vertices, "normals": normals})


def _city_hall(model, recipe):
    if model.v[1] <= 0:
        raise ValueError("City Hall authored front must face south/+Z")
    depth = model.height * _ratio(recipe, "front_curve_depth_ratio", .24, .14, .34)
    bow = min(1.8, model.hu * .04)
    # Eight independently authored height/depth sections make the glass recede
    # in the middle and sweep forward under the long upper eave. The setback
    # is deliberately visible at the review camera; it is not a measured wall.
    profile = [(.055, depth * .48), (.20, depth * .72), (.40, depth * .94),
               (.58, depth), (.75, depth * .70), (.88, depth * .33),
               (.96, .55), (.985, .25)]

    def front(u, setback):
        across = (u - model.uc) / max(model.hu, 1e-6)
        return model.vmax - setback - bow * across * across

    _add(model, "stone_foot", "stone", model.footprint, model.bottom, _height(model, .055), "base")
    backing = _curved_front(model, bow, inset=depth + .12)
    _add(model, "recessed_closed_backing", "glass", backing,
         _height(model, .055), _height(model, .985), "curved_glass_mass")
    columns = int(recipe.get("front_grid_columns", 18))
    if not 6 <= columns <= 36:
        raise ValueError("front_grid_columns must be between 6 and 36")
    for section, ((f1, d1), (f2, d2)) in enumerate(zip(profile, profile[1:])):
        low_y, high_y = _height(model, f1), _height(model, f2)
        lower, upper = lambda u, d=d1: front(u, d), lambda u, d=d2: front(u, d)
        for index in range(16):
            u1 = model.umin + (model.umax - model.umin) * index / 16
            u2 = model.umin + (model.umax - model.umin) * (index + 1) / 16
            _profile_patch(model, f"front_glass_{section}_{index}", "glass", "curved_glass_mass",
                           u1, u2, low_y, high_y, lower, upper)
        for index in range(1, columns):
            u = model.umin + (model.umax - model.umin) * index / columns
            # A 28 cm visible face sits 14 cm in front of the glass. Complete
            # projected clipping keeps even the outermost relief inside source.
            _profile_patch(model, f"curved_mullion_{section}_{index}", "frame", "glass_grid",
                           u - .14, u + .14, low_y + .015, high_y - .015,
                           lower, upper, offset=.14)
        for rail, fraction in enumerate((.20, .40, .58, .75, .88)):
            low = max(low_y, _height(model, fraction) - .13)
            high = min(high_y, _height(model, fraction) + .13)
            if high - low < .01:
                continue
            dlow = d1 + (d2 - d1) * (low - low_y) / (high_y - low_y)
            dhigh = d1 + (d2 - d1) * (high - low_y) / (high_y - low_y)
            for index in range(16):
                u1 = model.umin + (model.umax - model.umin) * index / 16
                u2 = model.umin + (model.umax - model.umin) * (index + 1) / 16
                _profile_patch(model, f"curved_rail_{section}_{rail}_{index}", "frame", "glass_grid",
                               u1, u2, low, high,
                               lambda u, d=dlow: front(u, d), lambda u, d=dhigh: front(u, d), offset=.16)
    for sign, u in ((-1, model.umin + .42), (1, model.umax - .42)):
        _section_side(model, f"profile_side_{sign}", u, profile, front, sign)
    outer = _curved_front(model, bow, inset=.25)
    inner = _curved_front(model, bow, inset=2.75)
    eave = outer.difference(inner)
    _variable_shell(model, "long_front_eave", "roof", eave,
                    lambda x, z: _height(model, .973), lambda x, z: model.top, "long_eave")
    _variable_shell(model, "roof_cap", "roof", outer.difference(eave),
                    lambda x, z: _height(model, .985), lambda x, z: model.top, "roof")


def _library(model, recipe):
    if model.v[1] <= 0:
        raise ValueError("Library authored front must face south/+Z")
    _add(model, "stone_base", "stone", model.footprint, model.bottom, _height(model, .075), "base")
    backing = model.footprint.buffer(-.28, join_style="mitre")
    _add(model, "low_stone_mass", "stone", backing, _height(model, .075), _height(model, .88), "low_stone_mass")
    _add(model, "flat_roof", "roof", model.footprint.buffer(-.16, join_style="mitre"),
         _height(model, .88), _height(model, .92), "roof")
    for index, fraction in enumerate((.075, .84)):
        _add(model, f"stone_cornice_{index}", "stone", model.footprint,
             _height(model, fraction), _height(model, fraction) + .22, "stone_bands")
    pitch = float(recipe.get("window_pitch_m", 4.6))
    if not math.isfinite(pitch) or pitch <= 0:
        raise ValueError("window_pitch_m must be finite and positive")
    model.facade_rows("window", role="vertical_window_rhythm", storeys=3, pitch=pitch)
    _, front = model.edge_point(model.uc, 1, inset=.30)
    width = model.hu * _ratio(recipe, "central_facade_width_ratio", .23, .12, .34)
    central = model.rectangle(model.uc - width, front - .75,
                              model.uc + width, front + .12)
    _add(model, "central_stone_rise", "stone", central,
         _height(model, .83), model.top, "central_facade")
    # Paired narrow relief members emphasize the central entrance axis while
    # retaining the closed original collision and adding no portal or steps.
    for index, u in enumerate((model.uc - width * .82, model.uc + width * .82)):
        _, side_front = model.edge_point(u, 1, inset=.06)
        strip = model.rectangle(u - .27, side_front - .38, u + .27, side_front + .04)
        _add(model, f"central_pilaster_{index}", "stone", strip,
             _height(model, .075), _height(model, .88), "central_facade")


def _merge(item, components):
    merged = {}
    for component in components:
        material, role = component["material"], component["feature_role"]
        if material not in PALETTE:
            raise ValueError("Unsupported city material: " + material)
        if not component["vertices"]:
            continue
        key = material, role
        target = merged.setdefault(key, {
            "id": f"{item['id']}_{material}_{role}", "material": material,
            "feature_role": role, "vertices": [], "normals": [],
            "metadata": _metadata(item, merged_member_ids=[]),
        })
        target["vertices"].extend(component["vertices"])
        target["normals"].extend(component["normals"])
        target["metadata"]["merged_member_ids"].append(component["id"])
    return list(merged.values())


def build_authored(item, recipe):
    """Return display-only components for city_hall, library or plaza.

    ``item`` is one L01 landmark specification entry. Recipes may override the
    documented visual ratios; neither recipes nor this module change source
    geometry, heights or collision. Components are merged by material and role.
    """
    identifier = item["id"]
    binding = item["spatial_binding"]
    footprint = shape(binding["geometry"])
    if footprint.is_empty or not footprint.is_valid or not polygonal(footprint):
        raise ValueError("Invalid source footprint")
    if identifier == "plaza":
        # A land-reference mesh is a single existing plane; top=None does not
        # authorize extrusion, landscaping paths or an added walkable surface.
        level = binding["current_top_y_m"]
        if level is None:
            level = binding["current_bottom_y_m"]
        grass = footprint.buffer(-.6, join_style="mitre")
        paving = footprint.difference(grass)
        components = []
        for material, geometry in (("grass", grass), ("paving", paving)):
            if geometry.is_empty:
                continue
            mesh = mesh_polygon(geometry, level)
            components.append({"id": f"plaza_{material}_surface", "material": material,
                               "feature_role": f"{material}_surface", **mesh,
                               "metadata": _metadata(
                                   item, surface_y_m=level,
                                   landscape_status="dated coarse land reference; not exact 2026 landscape",
                                   paving_border_width_m=.6,
                                   border_basis="authored inside-footprint material contrast; not a surveyed paving width",
                                   internal_paths_generated=False)})
        return components
    if identifier not in ("city_hall", "library"):
        raise ValueError("Unsupported authored city landmark: " + identifier)
    bottom, top = binding["current_bottom_y_m"], binding["current_top_y_m"]
    if bottom is None or top is None or not all(math.isfinite(v) for v in (bottom, top)) or top <= bottom:
        raise ValueError("Missing or invalid retained building envelope")
    visual_recipe = dict(recipe)
    visual_recipe.update({"eave_ratio": .88, "podium_ratio": .075, "backing_inset_m": .16})
    model = Model(item, visual_recipe, {})
    if identifier == "city_hall":
        _city_hall(model, visual_recipe)
    else:
        _library(model, visual_recipe)
    return _merge(item, model.components)

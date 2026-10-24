"""Original EXP35 Blender rig for the editable 1.78m study cage.

Blender4.5LTS, metres, +Z up, front -Y, character left +X. No previous
52-bone rest, imported body, mocap or external armature is read. This module
never changes topology. Call assign_rig on the final welded cage/parts.
"""
from __future__ import annotations

import math
import bpy
from mathutils import Matrix, Quaternion, Vector

VERSION = "exp35_study_rig_v2_evaluated_support"
POSE_KEYS = ("a_pose", "arm_raise", "deep_squat", "single_support")
FPS = 24
POSE_FRAME = 24
END_FRAME = 36
CORRECTIVES = ("StudyShoulderSupport", "StudyHipCompression", "StudyKneeCompression")
_SOLE_SAMPLES = {}


def _smooth(a, b, value):
    t = max(0., min(1., (value-a)/(b-a)))
    return t*t*(3.-2.*t)


def _v(value):
    return Vector(tuple(float(c) for c in value))


def _defaults():
    result = {"pelvis": (0., 0., .945), "spine": (0., 0., 1.040),
              "chest": (0., 0., 1.230), "neck": (0., 0., 1.530),
              "head": (0., 0., 1.600)}
    for side, sign in (("L", 1.), ("R", -1.)):
        result.update({"shoulder."+side: (sign*.205, 0., 1.445),
                       "elbow."+side: (sign*.332, -.012, 1.165),
                       "wrist."+side: (sign*.445, -.025, .915),
                       "hip."+side: (sign*.095, 0., .925),
                       "knee."+side: (sign*.100, -.018, .515),
                       "ankle."+side: (sign*.105, 0., .105)})
    return result


def _anchors(info):
    result = {key: _v(value) for key, value in _defaults().items()}
    # The body author may supply additional semantic anchors. Only explicit
    # matching anchors override this new rest; no nearest old rig is fitted.
    for key, value in info.get("landmarks", {}).items():
        if key in result and isinstance(value, (list, tuple)) and len(value) == 3:
            result[key] = _v(value)
    return result


def _bone_specs(anchors):
    rows = [("root", (0., 0., 0.), (0., 0., .15), None),
            ("pelvis", anchors["pelvis"], anchors["spine"], "root"),
            ("spine", anchors["spine"], anchors["chest"], "pelvis"),
            ("chest", anchors["chest"], anchors["neck"], "spine"),
            ("neck", anchors["neck"], anchors["head"], "chest"),
            ("head", anchors["head"], (0., 0., 1.755), "neck")]
    for side, sign in (("L", 1.), ("R", -1.)):
        shoulder, elbow, wrist = (anchors[key+"."+side] for key in ("shoulder", "elbow", "wrist"))
        hand_end = wrist+(wrist-elbow).normalized()*.095
        hip, knee, ankle = (anchors[key+"."+side] for key in ("hip", "knee", "ankle"))
        toe = Vector((ankle.x, -.175, .062))
        rows.extend([("clavicle."+side, (0., 0., 1.470), shoulder, "chest"),
                     ("upper_arm."+side, shoulder, elbow, "clavicle."+side),
                     ("forearm."+side, elbow, wrist, "upper_arm."+side),
                     ("hand."+side, wrist, hand_end, "forearm."+side),
                     ("thigh."+side, hip, knee, "pelvis"),
                     ("shin."+side, knee, ankle, "thigh."+side),
                     ("foot."+side, ankle, toe, "shin."+side),
                     ("toe."+side, toe, (ankle.x, -.245, .052), "foot."+side)])
    return [(name, _v(head), _v(tail), parent) for name, head, tail, parent in rows]


def _region(point, named):
    if named:
        return named
    if point.z >= 1.57:
        return "head"
    if point.z >= 1.49 and abs(point.x) < .09:
        return "neck"
    side = "L" if point.x >= 0. else "R"
    if point.z < .19:
        return "foot."+side
    if abs(point.x) > .415 and point.z < 1.04:
        return "hand."+side
    if point.z < .93:
        return "leg."+side
    if abs(point.x) > .23 and point.z > .86:
        return "arm."+side
    return "torso"


def _weights(point, region, anchors):
    if region == "head":
        return {"head": 1.}
    if region == "neck":
        amount = _smooth(1.535, 1.605, point.z)
        return {"neck": 1.-amount, "head": amount}
    if region.startswith("hand."):
        return {region: 1.}
    if region.startswith("foot."):
        side = region[-1]
        toe = 1.-_smooth(-.205, -.145, point.y)
        return {"foot."+side: 1.-toe, "toe."+side: toe}
    if region.startswith("arm."):
        side = region[-1]
        shoulder, elbow, wrist = (anchors[key+"."+side] for key in ("shoulder", "elbow", "wrist"))
        direction = (elbow-shoulder).normalized()
        distance = (point-shoulder).dot(direction)
        upper_length, lower_length = (elbow-shoulder).length, (wrist-elbow).length
        lower = _smooth(upper_length-.055, upper_length+.055, distance)
        hand = _smooth(upper_length+lower_length-.035, upper_length+lower_length+.025, distance)
        proximal = 1.-_smooth(.015, .085, distance)
        return {"chest": .20*proximal, "clavicle."+side: .25*proximal,
                "upper_arm."+side: (1.-lower)*(1.-.45*proximal),
                "forearm."+side: lower*(1.-hand), "hand."+side: hand}
    if region.startswith("leg."):
        side = region[-1]
        hip, knee, ankle = (anchors[key+"."+side] for key in ("hip", "knee", "ankle"))
        distance = (point-hip).dot((knee-hip).normalized())
        thigh_length = (knee-hip).length
        shin = _smooth(thigh_length-.060, thigh_length+.060, distance)
        pelvis = (1.-_smooth(.015, .090, distance))*.45
        foot = 1.-_smooth(.115, .185, point.z)
        return {"pelvis": pelvis, "thigh."+side: (1.-shin)*(1.-pelvis),
                "shin."+side: shin*(1.-foot), "foot."+side: foot}
    spine = _smooth(.995, 1.120, point.z)
    chest = _smooth(1.200, 1.355, point.z)
    neck = _smooth(1.485, 1.555, point.z)
    values = {"pelvis": 1.-spine, "spine": spine*(1.-chest),
              "chest": spine*chest*(1.-neck), "neck": neck}
    # Shared armhole vertices belong to torso but blend into the local arm.
    side = "L" if point.x >= 0. else "R"
    shoulder = anchors["shoulder."+side]
    support = math.exp(-.5*((point-shoulder).length/.065)**2)*_smooth(.12, .205, abs(point.x))
    for key in list(values):
        values[key] *= 1.-.70*support
    values["clavicle."+side] = .25*support
    values["upper_arm."+side] = .45*support
    return values


def _bind_weights(objects, info, rig, anchors):
    regions = {}
    for region, ids in info.get("vertex_regions", {}).items():
        for vertex in ids:
            regions[int(vertex)] = region
    rows = []
    for object_index, obj in enumerate(objects):
        groups = {bone.name: obj.vertex_groups.get(bone.name) or obj.vertex_groups.new(name=bone.name) for bone in rig.data.bones}
        histogram, maximum_error, invalid = {}, 0., 0
        for vertex in obj.data.vertices:
            point = obj.matrix_world@vertex.co
            named = regions.get(vertex.index) if object_index == 0 else None
            region = _region(point, named)
            values = _weights(point, region, anchors)
            values = sorted(((key, value) for key, value in values.items() if value > 1e-7), key=lambda item: item[1], reverse=True)[:4]
            total = sum(value for _, value in values)
            if total <= 0.:
                invalid += 1
                values, total = [("pelvis", 1.)], 1.
            for key, value in values:
                groups[key].add([vertex.index], value/total, "REPLACE")
            maximum_error = max(maximum_error, abs(sum(value/total for _, value in values)-1.))
            histogram[region] = histogram.get(region, 0)+1
        modifier = obj.modifiers.new("StudySkinning", "ARMATURE")
        modifier.object = rig
        modifier.use_deform_preserve_volume = False  # glTF uses linear skinning.
        matrix = obj.matrix_world.copy()
        obj.parent = rig
        obj.matrix_world = matrix
        rows.append({"object": obj.name, "vertices": len(obj.data.vertices), "regions": histogram,
                     "maximum_weight_sum_error": maximum_error, "unassigned_vertices": invalid,
                     "maximum_influences": 4, "topology_changed": False})
    return rows


def _make_correctives(objects, anchors):
    rows = []
    for obj in objects:
        if obj.data.shape_keys is None:
            obj.shape_key_add(name="Basis")
        blocks = {name: obj.shape_key_add(name=name) for name in CORRECTIVES}
        maximum = {name: 0. for name in CORRECTIVES}
        inverse = obj.matrix_world.to_3x3().inverted()
        for vertex in obj.data.vertices:
            p = obj.matrix_world@vertex.co
            side = "L" if p.x >= 0. else "R"
            shoulder, hip, knee = (anchors[key+"."+side] for key in ("shoulder", "hip", "knee"))
            axis = (anchors["elbow."+side]-shoulder).normalized()
            rel = p-shoulder
            radial = rel-axis*rel.dot(axis)
            shoulder_weight = math.exp(-.5*(rel.length/.085)**2)
            shoulder_delta = radial.normalized()*min(.009, radial.length*.12)*shoulder_weight if radial.length > 1e-6 else Vector()
            hip_weight = math.exp(-.5*((p-hip).length/.115)**2)*_smooth(.025, .075, abs(p.x))
            hip_delta = Vector((math.copysign(.004, p.x), .006, 0.))*hip_weight
            knee_weight = math.exp(-.5*((p-knee).length/.065)**2)
            knee_delta = Vector((0., -.006 if p.y < knee.y else -.003, 0.))*knee_weight
            for name, delta in zip(CORRECTIVES, (shoulder_delta, hip_delta, knee_delta)):
                blocks[name].data[vertex.index].co = vertex.co+inverse@delta
                maximum[name] = max(maximum[name], delta.length)
        rows.append({"object": obj.name, "keys": list(CORRECTIVES), "maximum_rest_delta_m": maximum,
                     "scope": "Small authored pose supports, not measured soft-tissue simulation."})
    return rows


def _world_rotation(rig, name, desired):
    bone = rig.pose.bones[name]
    rest = bone.bone.matrix_local.to_3x3()
    parent_delta = Matrix.Identity(3) if bone.parent is None else bone.parent.matrix.to_3x3()@bone.parent.bone.matrix_local.to_3x3().inverted()
    bone.rotation_quaternion = ((parent_delta@rest).inverted()@desired).to_quaternion()
    bpy.context.view_layer.update()


def _aim(rig, name, direction):
    bone = rig.pose.bones[name]
    rest = bone.bone.matrix_local.to_3x3()
    desired = (bone.bone.tail_local-bone.bone.head_local).normalized().rotation_difference(_v(direction).normalized()).to_matrix()@rest
    _world_rotation(rig, name, desired)


def _aim_hand(rig, side, direction, dorsal_normal):
    """Set finger direction AND palm roll using the authored hand surface axes.

    The hand cage's +normal faces front(-Y), while fingertips curl towards
    -normal, the palmar side. Aiming just the bone leaves this roll ambiguous.
    """
    name = "hand."+side
    bone = rig.pose.bones[name]
    source_axis = (bone.bone.tail_local-bone.bone.head_local).normalized()
    source_normal = Vector((0., -1., 0.))
    source_normal = (source_normal-source_axis*source_normal.dot(source_axis)).normalized()
    target_axis = _v(direction).normalized()
    target_normal = _v(dorsal_normal)
    target_normal = (target_normal-target_axis*target_normal.dot(target_axis)).normalized()
    source = Matrix((source_axis.cross(source_normal), source_axis, source_normal)).transposed()
    target = Matrix((target_axis.cross(target_normal), target_axis, target_normal)).transposed()
    _world_rotation(rig, name, target@source.inverted()@bone.bone.matrix_local.to_3x3())


def _knee(hip, ankle, upper, lower):
    line = ankle-hip
    distance = max(1e-5, min(line.length, upper+lower-1e-6))
    direction = line.normalized()
    along = (upper*upper-lower*lower+distance*distance)/(2.*distance)
    height = math.sqrt(max(0., upper*upper-along*along))
    pole = Vector((0., -1., 0.))
    pole = (pole-direction*pole.dot(direction)).normalized()
    return hip+direction*along+pole*height


def _leg_to(rig, side, ankle):
    thigh, shin = rig.pose.bones["thigh."+side], rig.pose.bones["shin."+side]
    hip = thigh.head.copy()
    knee = _knee(hip, ankle, thigh.bone.length, shin.bone.length)
    _aim(rig, "thigh."+side, knee-hip)
    _aim(rig, "shin."+side, ankle-knee)


def _rest_foot_rotation(rig, side):
    # The rest foot bone slopes towards the metatarsals. Making that bone
    # horizontal pitches the actual sole; preserve its complete rest frame.
    for part in ("foot.", "toe."):
        name = part+side
        _world_rotation(rig, name, rig.data.bones[name].matrix_local.to_3x3())


def _evaluated_points(obj):
    deps = bpy.context.evaluated_depsgraph_get()
    bpy.context.view_layer.update();deps.update()
    evaluated = obj.evaluated_get(deps)
    mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=deps)
    try:
        return [(v.index, evaluated.matrix_world@v.co,
                 {g.group: g.weight for g in v.groups}) for v in mesh.vertices]
    finally:
        evaluated.to_mesh_clear()


def _support_samples(rig, objects):
    """Cache indices from the actual evaluated REST sole, not ankle targets.

    Subdivision's evaluated indices stay stable through these bone/morph
    poses. A different mesh/modifier topology obtains its own rest samples.
    """
    key = (rig.as_pointer(), tuple((obj.as_pointer(), obj.data.as_pointer(),
           len(obj.data.vertices), tuple((m.type, getattr(m, "levels", None)) for m in obj.modifiers)) for obj in objects))
    if key in _SOLE_SAMPLES:
        return _SOLE_SAMPLES[key]
    result = {"L": [], "R": []}
    for obj in objects:
        points = _evaluated_points(obj)
        for side in ("L", "R"):
            names = [obj.vertex_groups.get(part+side) for part in ("foot.", "toe.")]
            groups = [g.index for g in names if g]
            # Upper ankle vertices can also carry foot weights, but are not
            # sole candidates. The observed low band defines heel/toe pads.
            foot = [(i, p) for i, p, weights in points if sum(weights.get(g, 0.) for g in groups) > .95
                    and p.z < rig.pose.bones["foot."+side].head.z-.025]
            if not foot:
                continue
            minimum = min(p.z for _, p in foot)
            sole = [(i, p) for i, p in foot if p.z <= minimum+.012]
            front, back = min(p.y for _, p in sole), max(p.y for _, p in sole)
            span = back-front
            if span < .08:
                continue
            heel = [i for i, p in sole if p.y >= front+.72*span]
            toe = [i for i, p in sole if p.y <= front+.28*span]
            if heel and toe:
                result[side].append({"object": obj, "heel": heel, "toe": toe,
                                     "foot": [i for i, _ in foot], "rest_min_z_m": minimum})
    _SOLE_SAMPLES[key] = result
    return result


def _observe_support(samples, side):
    pads, all_points = {"heel": [], "toe": []}, []
    for row in samples[side]:
        points = {i: point for i, point, _ in _evaluated_points(row["object"])}
        for label in pads:
            pads[label].extend(points[i] for i in row[label])
        all_points.extend(points[i] for i in row["foot"])
    if not all_points:
        return {"available": False, "reason": "No evaluated foot/toe-weighted sole samples."}
    return {"available": True, "minimum_z_m": min(p.z for p in all_points),
            "heel_min_z_m": min(p.z for p in pads["heel"]),
            "toe_min_z_m": min(p.z for p in pads["toe"]),
            "heel_center_m": list(sum(pads["heel"], Vector())/len(pads["heel"])),
            "toe_center_m": list(sum(pads["toe"], Vector())/len(pads["toe"])),
            "heel_samples": len(pads["heel"]), "toe_samples": len(pads["toe"]),
            "foot_samples": len(all_points)}


def _fit_support(rig, objects, samples, key, floor_z=0.):
    """Fit actual heel/toe surfaces and report their final observed heights.

    No topology or rest landmark is altered. Contact is measured after the
    active correctives and modifier stack. The support side alone is fitted
    for one-leg balance; the lifted foot is deliberately left above floor.
    """
    sides = ("L",) if key == "single_support" else ("L", "R")
    before = {side: _observe_support(samples, side) for side in ("L", "R")}
    if key in ("a_pose", "arm_raise"):
        heights = [before[side]["minimum_z_m"] for side in sides if before[side]["available"]]
        if heights:
            root = rig.pose.bones["root"]
            root.location += root.bone.matrix_local.to_3x3().inverted()@Vector((0., 0., floor_z-min(heights)))
            bpy.context.view_layer.update()
    else:
        for side in sides:
            if not before[side]["available"]:
                continue
            ankle = rig.pose.bones["foot."+side].head.copy()
            for _ in range(3):
                observed = _observe_support(samples, side)
                heel, toe = _v(observed["heel_center_m"]), _v(observed["toe_center_m"])
                # Foot forward is -Y. Fit the difference of ACTUAL lower
                # heel/toe pads rather than the sloped ankle-to-toe bone.
                pitch = math.atan2(observed["toe_min_z_m"]-observed["heel_min_z_m"], max(.08, heel.y-toe.y))
                pitch = max(-.15, min(.15, pitch))
                correction = Quaternion(Vector((1., 0., 0.)), pitch).to_matrix()
                rotations = {part: correction@rig.pose.bones[part+side].matrix.to_3x3() for part in ("foot.", "toe.")}
                for part, rotation in rotations.items():
                    _world_rotation(rig, part+side, rotation)
                observed = _observe_support(samples, side)
                ankle.z += floor_z-observed["minimum_z_m"]
                _leg_to(rig, side, ankle)
                for part, rotation in rotations.items():
                    _world_rotation(rig, part+side, rotation)
    return {"method": "Actual evaluated heel/toe pad indices + foot/toe weights; no ankle-only contact claim.",
            "floor_z_m": floor_z, "support_sides": list(sides),
            "before": before, "after": {side: _observe_support(samples, side) for side in ("L", "R")}}


def apply_study_pose(rig, key, objects=None):
    """Apply actual pose-bone deltas and matching corrective values together."""
    if key not in POSE_KEYS:
        raise ValueError("unknown study pose "+str(key))
    objects = list(objects) if objects is not None else [obj for obj in rig.children if obj.type == "MESH"]
    for bone in rig.pose.bones:
        bone.rotation_mode = "QUATERNION"
        bone.rotation_quaternion = Quaternion()
        bone.location = (0., 0., 0.)
        bone.scale = (1., 1., 1.)
    values = dict.fromkeys(CORRECTIVES, 0.)
    for obj in objects:
        if obj.data.shape_keys:
            for name in CORRECTIVES:
                block = obj.data.shape_keys.key_blocks.get(name)
                if block:
                    block.value = 0.
    bpy.context.view_layer.update()
    samples = _support_samples(rig, objects)
    if key == "arm_raise":
        for side, sign in (("L", 1.), ("R", -1.)):
            _aim(rig, "clavicle."+side, (sign, 0., .12))
            _aim(rig, "upper_arm."+side, (sign*.35, 0., .94))
            _aim(rig, "forearm."+side, (sign*.20, -.025, .98))
            _aim_hand(rig, side, (sign*.20, -.025, .98), (sign, 0., 0.))
        values[CORRECTIVES[0]] = 1.
    elif key in ("deep_squat", "single_support"):
        pelvis = rig.pose.bones["pelvis"]
        translation = Vector((0., .12, -.40)) if key == "deep_squat" else Vector((.080, 0., -.018))
        pelvis.location = pelvis.bone.matrix_local.to_3x3().inverted()@translation
        bpy.context.view_layer.update()
        if key == "deep_squat":
            _aim(rig, "spine", (0., -.20, .98));_aim(rig, "chest", (0., -.10, .995))
            for side, sign in (("L", 1.), ("R", -1.)):
                _leg_to(rig, side, Vector((sign*.105, 0., .105)))
                _rest_foot_rotation(rig, side)
                _aim(rig, "upper_arm."+side, (sign*.20, -.90, -.385))
                _aim(rig, "forearm."+side, (sign*.08, -.98, -.18))
                _aim_hand(rig, side, (sign*.08, -.98, -.18), (0., 0., 1.))
            values[CORRECTIVES[1]] = values[CORRECTIVES[2]] = 1.
        else:
            _leg_to(rig, "L", Vector((.105, 0., .105)))
            _leg_to(rig, "R", Vector((-.16, -.10, .24)))
            for side in ("L", "R"):
                _rest_foot_rotation(rig, side)
            values[CORRECTIVES[1]] = .20;values[CORRECTIVES[2]] = .20
    for obj in objects:
        if obj.data.shape_keys:
            for name, value in values.items():
                block = obj.data.shape_keys.key_blocks.get(name)
                if block:
                    block.value = value
    bpy.context.view_layer.update()
    support = _fit_support(rig, objects, samples, key)
    return {"key": key, "corrective_weights": values,
            "evaluated_sole_support": support,
            "bone_local_quaternion_wxyz": {bone.name: list(bone.rotation_quaternion) for bone in rig.pose.bones},
            "bone_local_location": {bone.name: list(bone.location) for bone in rig.pose.bones},
            "actual_joint_heads_m": {bone.name: list(bone.head) for bone in rig.pose.bones}}


def _push_action(data, action, track_name):
    track = data.animation_data.nla_tracks.new()
    track.name = track_name
    strip = track.strips.new(track_name, 1, action)
    strip.action_frame_start = 1.;strip.action_frame_end = float(END_FRAME)
    track.mute = True
    data.animation_data.action = None
    return track


def _make_actions(rig, objects):
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start, scene.frame_end = 1, END_FRAME
    snapshots = []
    for key in POSE_KEYS:
        armature_action = bpy.data.actions.new(name=key)
        rig.animation_data_create();rig.animation_data.action = armature_action
        key_actions = {}
        for obj in objects:
            keys = obj.data.shape_keys
            keys.animation_data_create();action = bpy.data.actions.new(name=key+"_correctives_"+obj.name)
            keys.animation_data.action = action;key_actions[obj] = action
        for frame, pose in ((1, "a_pose"), (POSE_FRAME, key), (END_FRAME, key)):
            scene.frame_set(frame)
            snapshot = apply_study_pose(rig, pose, objects)
            for bone in rig.pose.bones:
                bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone.name)
                bone.keyframe_insert("location", frame=frame, group=bone.name)
            for obj in objects:
                for name in CORRECTIVES:
                    obj.data.shape_keys.key_blocks[name].keyframe_insert("value", frame=frame, group="PoseCorrectives")
            if frame == POSE_FRAME:
                snapshots.append(snapshot)
        _push_action(rig, armature_action, key)
        for obj, action in key_actions.items():
            _push_action(obj.data.shape_keys, action, key)
    scene.frame_set(1);apply_study_pose(rig, "a_pose", objects)
    return snapshots


def assign_rig(objects, info):
    """Bind final meshes without changing their topology; return rig, metadata.

    info.vertex_regions is region -> original body vertex-ID lists. Pass the
    welded body first. New appended head/hand/foot vertices are classified in
    world metres. Boundary loops remain the geometry author's responsibility.
    NLA track names match across pose/morph actions; export as NLA_TRACKS,
    unmuting the desired tracks while exporting (all tracks are muted at rest).
    """
    objects = [objects] if isinstance(objects, bpy.types.Object) else list(objects)
    if not objects or any(obj.type != "MESH" for obj in objects):
        raise ValueError("assign_rig requires final mesh object(s)")
    anchors = _anchors(info)
    data = bpy.data.armatures.new("StudyArmatureData")
    rig = bpy.data.objects.new("StudyArmature", data)
    collection = objects[0].users_collection[0] if objects[0].users_collection else bpy.context.scene.collection
    collection.objects.link(rig);rig.show_in_front = True
    bpy.ops.object.select_all(action="DESELECT");rig.select_set(True);bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in _bone_specs(anchors):
        bone = data.edit_bones.new(name);bone.head = head;bone.tail = tail
        if parent:
            bone.parent = data.edit_bones[parent]
        reference = Vector((0., -1., 0.))
        if abs((tail-head).normalized().dot(reference)) > .97:
            reference = Vector((0., 0., 1.))
        bone.align_roll(reference);bone.use_deform = True
    bpy.ops.object.mode_set(mode="OBJECT")
    weight_rows = _bind_weights(objects, info, rig, anchors)
    corrective_rows = _make_correctives(objects, anchors)
    poses = _make_actions(rig, objects)
    metadata = {"version": VERSION, "armature_object": rig.name, "bone_count": len(data.bones),
                "coordinates": "Blender+Zup/front-Y/left+X;metres;new1.78m adult study rest.",
                "bone_axes": "localY=head-to-tail;rollZaligned-front-Y except front-facing feet(use+Z).",
                "rest_anchors_m": {key: list(value) for key, value in anchors.items()},
                "bones": [{"name": bone.name, "parent": bone.parent.name if bone.parent else None,
                           "head_m": list(bone.head_local), "tail_m": list(bone.tail_local),
                           "length_m": bone.length, "matrix_local_rows": [list(row) for row in bone.matrix_local]} for bone in data.bones],
                "weights": weight_rows, "correctives": corrective_rows, "diagnostic_poses": poses,
                "animation": {"nla_track_names": list(POSE_KEYS), "fps": FPS, "first_frame": 1, "evaluation_frame": POSE_FRAME, "last_frame": END_FRAME,
                              "morph_values_explicitly_keyed": True, "drivers_required_by_export": False,
                              "export": "Unmute pose/morph NLA tracks;glTF NLA_TRACKS merges identical track names acrossarmatureandshapeKey actions;retainmorph targets/weights. Validate actual imported animation/morph tracks."},
                "source_assets_read": [], "old_rest_reused": False,
                "scope": "Original editable study rig and bounded authored supports;not mocap,measured anatomy,soft-tissue simulation or accepted realism."}
    rig["study_rig_version"] = VERSION
    return rig, metadata

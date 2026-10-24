"""EXP35 editable, independently authored human body control cage.

Run inside Blender. This is an explicit quad cage, not an isosurface, an old
resident mesh deformation, or a body asset import. The low-resolution loops
are the authored source and the unapplied subdivision surface is a preview.
Metres; Blender Z up, anterior -Y, character left +X. Head/hands/feet are open
boundaries for the separately authored study parts. Proportions are an adult
game-art study, not a population-average or a medical measurement.
"""
from __future__ import annotations

import math
import bpy
from mathutils import Vector

TAU = 2.0 * math.pi


def _v(p):
    return Vector(p)


def _blend(a, b, t):
    return tuple((1.0 - t) * x + t * y for x, y in zip(a, b))


class BodyCage:
    def __init__(self):
        self.vertices = []
        self.faces = []
        self.regions = {k: [] for k in
                        ('torso', 'neck', 'arm.L', 'arm.R', 'leg.L', 'leg.R')}
        self.loops = {}
        self.boundaries = {}

    def vertex(self, p, region):
        i = len(self.vertices)
        self.vertices.append(tuple(float(x) for x in p))
        self.regions[region].append(i)
        return i

    def ring(self, points, region, name):
        result = [self.vertex(p, region) for p in points]
        self.loops[name] = result
        return result

    def bridge(self, a, b, reverse=False):
        assert len(a) == len(b)
        for i in range(len(a)):
            j = (i + 1) % len(a)
            face = (a[i], a[j], b[j], b[i])
            self.faces.append(tuple(reversed(face)) if reverse else face)

    def boundary(self, title, indices, center, normal, u, v):
        self.boundaries[title] = {
            'indices': list(indices),
            'coords': [list(self.vertices[i]) for i in indices],
            'center': list(center), 'normal': list(normal),
            'u_axis': list(u), 'v_axis': list(v),
            'order': 'ordered outward-facing cross-section loop',
        }

    @staticmethod
    def trunk_points(row, bottom=False):
        # z, width, anterior depth, posterior depth, sagittal centre.
        z, width, front, back, cy = row
        result = []
        for i in range(20):
            t = TAU * i / 20
            c, s = math.cos(t), math.sin(t)
            ant, post = max(0., -s), max(0., s)
            x = width * c
            y = cy + (front if s < 0 else back) * s
            height = z
            # A shallow sternum between two oblique pectoral planes. These
            # alter a few deliberate cage points, not a dense sculpt field.
            if 1.26 <= z <= 1.41:
                y -= .009 * ant * math.sin(math.pi * abs(c)) ** 2
                y += .004 * ant ** 8
                # Scapular planes either side of the posterior midline.
                y += .006 * post * math.sin(math.pi * abs(c)) ** 2
                y -= .004 * post ** 8
            if .87 <= z <= .99:
                # Separate gluteal masses and an actual iliac-to-thigh slope.
                y += .007 * post * math.sin(math.pi * abs(c)) ** 2
                y -= .006 * post ** 8
            if bottom:
                height += .030 * abs(c) - .009 * ant
            if z == 1.49:
                # Acromion high points and a descending anterior clavicle.
                height -= .010 * ant + .006 * post
            if z == 1.535:
                # The neck begins well below its jaw join on the anterior
                # chest. A high planar ring here creates a conical "shrug"
                # from both acromia into the chin. Keep the posterior nape
                # higher, the lateral neck root lower, and the sternal notch
                # lower again; this is an explicitly nonplanar collar ring.
                height = 1.493 + .035 * post - .015 * ant
            result.append((x, y, height))
        return result

    def torso(self):
        rows = [
            (.885, .166, .103, .120, .004),
            (.945, .172, .109, .125, .004),
            (.995, .162, .105, .106, .003),
            (1.055, .144, .103, .088, .004),
            (1.125, .139, .095, .083, .002),
            (1.195, .153, .109, .087, .000),
            (1.270, .174, .118, .095, -.002),
            (1.320, .186, .118, .098, -.002),
            (1.405, .202, .102, .094, -.001),
            (1.490, .207, .073, .079, .001),
            (1.535, .071, .049, .054, .006),
        ]
        names = ['pelvic_exit', 'iliac_crest', 'upper_pelvis', 'lower_abdomen',
                 'waist', 'costal_margin', 'lower_pectorals', 'axilla_lower',
                 'pectorals_scapula', 'acromion_clavicle', 'trapezius_neck']
        rings = [self.ring(self.trunk_points(row, k == 0), 'torso', name)
                 for k, (row, name) in enumerate(zip(rows, names))]
        # Remove two deliberately located 4-by-2 quad panels for arm sockets.
        # Their twelve-vertex perimeters become the first arm loops.
        for k in range(len(rings) - 1):
            for i in range(20):
                arm_panel = k in (7, 8) and i in (18, 19, 0, 1, 8, 9, 10, 11)
                if arm_panel:
                    continue
                j = (i + 1) % 20
                self.faces.append((rings[k][i], rings[k][j],
                                   rings[k + 1][j], rings[k + 1][i]))
        self.torso_rings = rings

        # 20 -> 16 explicit all-quad neck retopology. Two 3:1 sectors contain
        # five-valence poles, away from the anterior throat and jaw boundary.
        neck_lower = self.ring(self.neck_points(1.553, .055, .043, .047),
                               'neck', 'neck_lower')
        a, b = rings[-1], neck_lower
        # Each half: 10 outer vertices -> 8 inner, with one 3:1 sector.
        for half in range(2):
            ai, bi = half * 10, half * 8
            self.faces.append((a[ai % 20], a[(ai + 1) % 20],
                               a[(ai + 2) % 20], b[bi % 16]))
            self.faces.append((a[(ai + 2) % 20], a[(ai + 3) % 20],
                               b[(bi + 1) % 16], b[bi % 16]))
            for j in range(1, 8):
                self.faces.append((a[(ai + j + 2) % 20], a[(ai + j + 3) % 20],
                                   b[(bi + j + 1) % 16], b[(bi + j) % 16]))
        neck = self.ring(self.neck_points(1.570, .052, .045, .047),
                         'neck', 'neck_join')
        self.bridge(neck_lower, neck)
        self.boundary('neck', neck, (0, .007, 1.57), (0, 0, 1),
                      (1, 0, 0), (0, 1, 0))

    @staticmethod
    def neck_points(z, width, front, back):
        return [(width * math.cos(TAU * i / 16),
                 .007 + (front if math.sin(TAU * i / 16) < 0 else back)
                 * math.sin(TAU * i / 16), z) for i in range(16)]

    def arms(self):
        # The socket is a real hole in the torso cage, not intersecting tubes.
        r = self.torso_rings
        left_socket = ([r[7][i % 20] for i in (-2, -1, 0, 1, 2)] +
                       [r[8][2], r[9][2]] +
                       [r[9][i % 20] for i in (1, 0, -1, -2)] + [r[8][18]])
        right_socket = ([r[7][i % 20] for i in (12, 11, 10, 9, 8)] +
                        [r[8][8], r[9][8]] +
                        [r[9][i] for i in (9, 10, 11, 12)] + [r[8][12]])
        start_angles = [-135, -112.5, -90, -67.5, -45, 0,
                        45, 67.5, 90, 112.5, 135, 180]
        end_angles = [-150 + 30 * i for i in range(12)]
        # centre x,y,z; radius along posterior axis / perpendicular arm plane.
        rows = [
            (.238, -.001, 1.410, .063, .069),
            (.268, -.003, 1.345, .057, .059),
            (.300, -.007, 1.260, .049, .053),
            (.319, -.010, 1.205, .044, .047),
            (.332, -.012, 1.165, .038, .042),
            (.346, -.015, 1.128, .041, .044),
            (.369, -.018, 1.075, .038, .040),
            (.396, -.021, 1.015, .032, .035),
            (.425, -.024, .955, .026, .028),
            (.445, -.025, .915, .023, .025),
        ]
        for side, sign, socket in [('L', 1, left_socket), ('R', -1, right_socket)]:
            normal = _v((sign * .414, -.047, -.909)).normalized()
            u = _v((0, 1, 0))
            u = (u - normal * u.dot(normal)).normalized()
            v = normal.cross(u).normalized()
            # Mirror the left normal-oriented section; winding is corrected.
            if sign < 0:
                v = -v
            previous = socket
            self.loops['shoulder_socket.' + side] = socket
            for k, (x, y, z, ry, rv) in enumerate(rows):
                center = _v((sign * x, y, z))
                points = []
                for i in range(12):
                    t = min(1., k / 4.)
                    angle = math.radians(start_angles[i] * (1-t) + end_angles[i] * t)
                    p = center + u * (ry * math.cos(angle)) + v * (rv * math.sin(angle))
                    # Radius axes rotate about the actual arm, not world-Z.
                    points.append(tuple(p))
                ring = self.ring(points, 'arm.' + side, 'arm.%s.%02d' % (side, k))
                self.bridge(previous, ring, reverse=sign < 0)
                previous = ring
            self.boundary('wrist.' + side, previous, center, normal,
                          u, v if sign > 0 else -v)

    def legs(self):
        rim = self.torso_rings[0]
        crotch = self.vertex((0, -.004, .833), 'torso')
        self.loops['perineal_support'] = [rim[15], crotch, rim[5]]
        angles = [math.radians(-150 + 30*i) for i in range(12)]
        # centre z,x,y, half-width, anterior/posterior depth.
        rows = [
            (.855, .092, .001, .079, .090, .124),
            (.810, .093, .001, .080, .092, .098),
            (.750, .096, -.002, .077, .086, .093),
            (.670, .101, -.006, .067, .077, .079),
            (.595, .102, -.011, .055, .064, .060),
            (.550, .101, -.015, .047, .054, .047),
            (.515, .100, -.018, .043, .049, .042),
            (.480, .101, -.014, .044, .047, .046),
            (.440, .103, -.007, .049, .046, .057),
            (.375, .106, .002, .052, .043, .066),
            (.300, .108, .006, .045, .038, .059),
            (.225, .108, .005, .035, .034, .047),
            (.160, .106, .002, .029, .031, .037),
            (.105, .105, .000, .027, .031, .034),
        ]
        for side, sign in [('L', 1), ('R', -1)]:
            if sign > 0:
                previous = [rim[(15+i) % 20] for i in range(11)] + [crotch]
            else:
                previous = [rim[(15-i) % 20] for i in range(11)] + [crotch]
            self.loops['inguinal_bridge.' + side] = previous
            for k, (z, cx, cy, width, front, back) in enumerate(rows):
                points = []
                for t in angles:
                    c, s = math.cos(t), math.sin(t)
                    x = sign * (cx + width * c)
                    y = cy + (front if s < 0 else back) * s
                    # A patella plane across three knee support loops; the
                    # posterior crease is shallower than the anterior cap.
                    if .48 <= z <= .55:
                        y -= .004 * max(0., -s) ** 4
                    if .225 <= z <= .44:
                        y -= .0025 * max(0., -s) ** 5
                    points.append((x, y, z))
                ring = self.ring(points, 'leg.' + side, 'leg.%s.%02d' % (side, k))
                self.bridge(previous, ring, reverse=sign > 0)
                previous = ring
            self.boundary('ankle.' + side, previous, (sign*.105, 0, .105),
                          (0, 0, -1), (1, 0, 0), (0, -1, 0))

    def sculpt_primary_planes(self):
        """Deliberate low-cage point edits after viewing the first clay model.

        The named loops remain selectable in Blender. Paired edits describe
        the pectoral plate, costal margin, scapular plane, iliac corner and
        articulating patella/olecranon, rather than adding dense surface noise.
        Join loops and the skeleton landmarks are left untouched.
        """
        def move(loop, index, offset):
            vid = self.loops[loop][index]
            self.vertices[vid] = tuple(a+b for a,b in zip(self.vertices[vid], offset))

        # Raised pectoral plates with a recessed sternum and a softer lower
        # outside edge. The anterior row is noncircular in the control cage.
        for loop, depth in [('lower_pectorals', .009),
                            ('axilla_lower', .020),
                            ('pectorals_scapula', .012)]:
            for index in (13, 14, 16, 17):
                move(loop, index, (0, -depth * (1 if index in (14,16) else .6), 0))
        for index in (14, 16):
            move('pectorals_scapula', index, (0, -.004, .005))
        move('axilla_lower', 15, (0, .004, 0))

        # Separate the clavicular shelf from the upper pectoral and from the
        # neck tube, rather than one uninterrupted acromion-to-throat cone.
        # The central point recedes into the suprasternal fossa; paired points
        # either side support the lower sternocleidomastoid attachments.
        for index in (13,14,16,17):
            move('acromion_clavicle', index, (0,-.009,-.005))
        move('acromion_clavicle', 15, (0,.006,-.008))
        for index in (13,17):
            move('trapezius_neck', index, (0,-.004,0))
        move('trapezius_neck', 15, (0,.004,-.002))
        for index in (11,13):
            move('neck_lower', index, (0,-.003,0))
        self.loops['sternoclavicular_shelf'] = [self.loops['acromion_clavicle'][i]
                                              for i in (12,13,14,15,16,17,18)]
        self.loops['suprasternal_fossa'] = [self.loops['trapezius_neck'][i]
                                          for i in (14,15,16)]

        # Anterior iliac crests and a lower abdominal plane; avoid a single
        # uninterrupted waist-to-thigh cone at the groin.
        for index, sign in ((13,-1), (17,1)):
            move('upper_pelvis', index, (sign*.004, -.006, .005))
        for index in (14,15,16):
            move('lower_abdomen', index, (0, -.005, 0))

        # Scapulae/erector separation and the lower latissimus attachment.
        for loop, depth in [('pectorals_scapula', .010),
                            ('axilla_lower', .007),
                            ('lower_pectorals', .005)]:
            for index in (3,4,6,7):
                move(loop, index, (0, depth, 0))
        move('pectorals_scapula', 5, (0, -.004, 0))
        for index in (4,6):
            move('iliac_crest', index, (0, .008, 0))

        for side, sign in [('L',1), ('R',-1)]:
            # Actual arm-loop planes distinguish anterior biceps and posterior
            # triceps; the elbow loop is a smaller hard landmark between them.
            for row in (1,2):
                move('arm.%s.%02d' % (side,row), 11, (0,-.008,0))
                move('arm.%s.%02d' % (side,row), 5, (0,.005,0))
            move('arm.%s.04' % side, 5, (0,.005,-.002))
            # Knee support loops surround a front patellar plane. Two medial
            # and lateral calf points remain distinct from the tibial crest.
            move('leg.%s.06' % side, 2, (0,-.006,0))
            for row in (8,9):
                move('leg.%s.%02d' % (side,row), 8, (0,.005,0))
                move('leg.%s.%02d' % (side,row), 7, (sign*.002,.003,0))


def build_body(collection=None):
    """Return (editable mesh object, serializable landmark/boundary metadata).

    No operators, scene deletion, import, saving, or export occurs here.
    Armature weights are deliberately owned by build_study_rig.py.
    """
    cage = BodyCage()
    cage.torso()
    cage.arms()
    cage.legs()
    cage.sculpt_primary_planes()
    mesh = bpy.data.meshes.new('StudyBody_AuthoredQuadCage')
    mesh.from_pydata(cage.vertices, [], cage.faces)
    mesh.update()
    obj = bpy.data.objects.new('StudyBodyCage', mesh)
    (collection or bpy.context.collection).objects.link(obj)
    for face in mesh.polygons:
        face.use_smooth = True
    for region, ids in cage.regions.items():
        group = obj.vertex_groups.new(name='region.' + region)
        if ids:
            group.add(ids, 1., 'REPLACE')
    for title, ids in cage.boundaries.items():
        group = obj.vertex_groups.new(name='join.' + title)
        group.add(ids['indices'], 1., 'REPLACE')
    subdivision = obj.modifiers.new('Editable anatomical subdivision', 'SUBSURF')
    subdivision.subdivision_type = 'CATMULL_CLARK'
    subdivision.levels = 1
    subdivision.render_levels = 2
    obj['authored_source'] = 'tools/sculpted_character/build_body_cage.py'
    obj['method'] = 'explicit connected quad control cage; no SDF/body import'
    obj['study_status'] = 'first editable candidate; visual review required'
    obj['units'] = 'metres'
    obj['front_axis'] = '-Y'
    obj['body_height_including_separate_head_target_m'] = 1.78
    landmarks = {
        'pelvis': (0, .004, .945), 'spine': (0, .002, 1.105),
        'chest': (0, 0, 1.345), 'neck': (0, .007, 1.530),
        'head': (0, .007, 1.615),
    }
    for side, s in [('L', 1), ('R', -1)]:
        landmarks.update({
            'clavicle.'+side: (s*.065, 0, 1.450),
            'shoulder.'+side: (s*.205, 0, 1.445),
            'elbow.'+side: (s*.332, -.012, 1.165),
            'wrist.'+side: (s*.445, -.025, .915),
            'hip.'+side: (s*.095, .004, .925),
            'knee.'+side: (s*.100, -.018, .515),
            'ankle.'+side: (s*.105, 0, .105),
        })
    info = {
        'coordinate_system': {'up': '+Z', 'anterior': '-Y', 'left': '+X',
                              'sole_z_m': 0., 'height_target_m': 1.78},
        'landmarks': {k: list(p) for k,p in landmarks.items()},
        'boundaries': cage.boundaries,
        'vertex_regions': cage.regions,
        'anatomy_loops': cage.loops,
        'source': obj['authored_source'],
        'control_vertices': len(cage.vertices), 'control_quads': len(cage.faces),
        'external_body_inputs': [],
        'notes': ['All-quads connected torso/limbs; five open join boundaries.',
                  'Manually editable cage and unapplied subdivision remain source.',
                  'This first candidate has not passed a visual anatomy gate.'],
    }
    return obj, info

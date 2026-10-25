"""EXP35/36/37 editable, independently authored human body control cage.

Run inside Blender. This is an explicit quad cage, not an isosurface, an old
resident mesh deformation, or a body asset import. The low-resolution loops
are the authored source and the unapplied subdivision surface is a preview.
Metres; Blender Z up, anterior -Y, character left +X. Head/hands/feet are open
boundaries for the separately authored study parts. Proportions are an adult
game-art study, not a population-average or a medical measurement.

EXP36 uses the attachment relationships and bony landmarks described in the
three OpenStax reference pages below, not measured coordinates, a scan, or
the textbook's images. All point positions remain project-authored art.
"""
from __future__ import annotations

import math
import bpy
from mathutils import Vector

TAU = 2.0 * math.pi
PROVENANCE = (
    'https://openstax.org/books/anatomy-and-physiology-2e/pages/11-5-muscles-of-the-pectoral-girdle-and-upper-limbs',
    'https://openstax.org/books/anatomy-and-physiology-2e/pages/11-6-appendicular-muscles-of-the-pelvic-girdle-and-lower-limbs',
    'https://openstax.org/books/anatomy-and-physiology-2e/pages/8-3-the-pelvic-girdle-and-pelvis',
)


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
        """Explicit primary anatomical planes, with unchanged cage IDs.

        These tables replace the first study's circular cross-sections at
        the named landmarks. Pectorals fan upward into the arm, the costal
        arch is higher medially, the pelvis tilts above separate gluteal and
        adductor planes, and the two calf heads descend to different levels.
        There are no added lumps, sampled noise, dense displacement maps or
        whole-limb scale factors. The five open join loops remain untouched.
        """
        def point(loop, index, position):
            self.vertices[self.loops[loop][index]] = tuple(position)

        def mirror_torso(loop, positions):
            for index, position in positions:
                point(loop, index, position)
                other = (10-index) % 20
                if other != index:
                    point(loop, other, (-position[0], position[1], position[2]))

        # Anterior clavicle and pectoral sheets. The inferior pectoral rows
        # rise toward the anterior axillary fold instead of horizontal bands.
        # EXP37 narrows the lower socket around the actual shoulder pivot.
        # The former wide/low chest panel made a long, nearly planar web to
        # the first arm section. Anterior and posterior folds now turn around
        # a higher, shallower axillary floor; the exterior deltoid stays round.
        torso_planes = {
            'acromion_clavicle': [
                (0,(.207,.001,1.490)), (19,(.194,-.024,1.486)),
                (18,(.153,-.054,1.480)), (17,(.100,-.073,1.475)),
                (16,(.046,-.068,1.463)), (15,(0,-.055,1.451)),
                (1,(.194,.025,1.485)), (2,(.163,.058,1.480)),
                (3,(.116,.074,1.477)), (4,(.058,.074,1.478)),
                (5,(0,.068,1.483))],
            'pectorals_scapula': [
                (0,(.202,-.001,1.405)), (19,(.190,-.036,1.402)),
                (18,(.180,-.079,1.414)), (17,(.113,-.123,1.405)),
                (16,(.056,-.122,1.402)), (15,(0,-.100,1.399)),
                (1,(.192,.028,1.412)), (2,(.179,.062,1.421)),
                (3,(.120,.104,1.403)), (4,(.058,.108,1.397)),
                (5,(0,.080,1.405))],
            'axilla_lower': [
                (0,(.179,-.002,1.350)), (19,(.176,-.037,1.357)),
                (18,(.165,-.072,1.370)), (17,(.112,-.136,1.329)),
                (16,(.056,-.151,1.306)), (15,(0,-.110,1.305)),
                (1,(.174,.032,1.358)), (2,(.162,.063,1.370)),
                (3,(.108,.113,1.328)), (4,(.054,.102,1.320)),
                (5,(0,.083,1.320))],
            'lower_pectorals': [
                (0,(.173,-.002,1.282)), (19,(.164,-.037,1.290)),
                (18,(.145,-.081,1.305)), (17,(.103,-.119,1.279)),
                (16,(.052,-.122,1.265)), (15,(0,-.108,1.263)),
                (1,(.168,.026,1.265)), (2,(.145,.066,1.268)),
                (3,(.100,.097,1.270)), (4,(.050,.096,1.269)),
                (5,(0,.081,1.270))],
            # The xiphoid/costal arch turns toward the lower lateral ribs;
            # abdominal and oblique planes begin below it, not a barrel tube.
            'costal_margin': [
                (0,(.159,.000,1.195)), (19,(.151,-.028,1.187)),
                (18,(.133,-.061,1.175)), (17,(.097,-.092,1.185)),
                (16,(.048,-.103,1.205)), (15,(0,-.095,1.225)),
                (1,(.151,.029,1.195)), (2,(.130,.056,1.195)),
                (3,(.094,.079,1.197)), (4,(.047,.086,1.199)),
                (5,(0,.076,1.195))],
            'waist': [
                (0,(.145,.002,1.125)), (19,(.137,-.024,1.137)),
                (18,(.120,-.050,1.140)), (17,(.087,-.081,1.135)),
                (16,(.046,-.104,1.126)), (15,(0,-.099,1.116)),
                (1,(.137,.028,1.126)), (2,(.117,.055,1.128)),
                (3,(.084,.075,1.130)), (4,(.042,.083,1.130)),
                (5,(0,.073,1.125))],
            'lower_abdomen': [
                (0,(.148,.004,1.055)), (19,(.140,-.026,1.058)),
                (18,(.124,-.055,1.054)), (17,(.092,-.085,1.047)),
                (16,(.048,-.106,1.044)), (15,(0,-.102,1.045)),
                (1,(.140,.030,1.058)), (2,(.122,.055,1.060)),
                (3,(.088,.073,1.064)), (4,(.044,.078,1.061)),
                (5,(0,.069,1.055))],
            # This nonplanar upper-pelvis row carries the actual crest/ASIS
            # surface. Legacy loop labels remain stable for the study tools.
            'upper_pelvis': [
                (0,(.166,.004,1.012)), (19,(.158,-.031,1.005)),
                (18,(.134,-.075,.993)), (17,(.104,-.091,.980)),
                (16,(.056,-.104,.977)), (15,(0,-.100,.978)),
                (1,(.158,.034,1.012)), (2,(.137,.062,1.010)),
                (3,(.099,.085,1.004)), (4,(.050,.093,.997)),
                (5,(0,.084,.995))],
            'iliac_crest': [
                (0,(.173,.005,.946)), (19,(.163,-.031,.944)),
                (18,(.140,-.061,.938)), (17,(.104,-.089,.935)),
                (16,(.054,-.105,.939)), (15,(0,-.103,.946)),
                (1,(.165,.043,.958)), (2,(.145,.089,.962)),
                (3,(.110,.130,.948)), (4,(.060,.145,.935)),
                (5,(0,.108,.956))],
            'pelvic_exit': [
                (0,(.168,.004,.920)), (19,(.158,-.030,.919)),
                (18,(.136,-.064,.910)), (17,(.099,-.090,.898)),
                (16,(.052,-.104,.886)), (15,(0,-.098,.880)),
                (1,(.160,.044,.921)), (2,(.139,.089,.913)),
                (3,(.100,.128,.896)), (4,(.048,.139,.883)),
                (5,(0,.100,.864))],
            # Distinct anterior throat/SCM attachment and posterior trapezius.
            'trapezius_neck': [
                (0,(.071,.006,1.493)), (19,(.067,-.009,1.489)),
                (18,(.058,-.022,1.485)), (17,(.042,-.035,1.480)),
                (16,(.022,-.039,1.470)), (15,(0,-.032,1.462)),
                (1,(.067,.023,1.503)), (2,(.057,.040,1.517)),
                (3,(.042,.050,1.525)), (4,(.022,.058,1.528)),
                (5,(0,.059,1.526))],
        }
        for loop, positions in torso_planes.items():
            mirror_torso(loop, positions)

        # Neck shaft points stop below the fixed sixteen-point jaw join.
        for index in (11,13):
            vid = self.loops['neck_lower'][index]
            x,y,z = self.vertices[vid]
            self.vertices[vid] = (x,y-.003,z)

        def limb_point(side, limb, row, index, position):
            sign = 1 if side == 'L' else -1
            x,y,z = position
            point('%s.%s.%02d' % (limb,side,row), index, (sign*x,y,z))

        for side in ('L','R'):
            # Deltoid/acromion to the separate anterior biceps and posterior
            # triceps planes. The inner elbow narrows; it is not a scaled tube.
            for row, index, p in [
                # Twelve points follow the shoulder's oblique section. The
                # deep side of the axilla joins the lower socket without a
                # long radial membrane; the front/back folds are distinct.
                (0,0,(.199,-.049,1.403)), (0,1,(.186,-.027,1.394)),
                (0,2,(.181,-.001,1.390)), (0,3,(.187,.025,1.395)),
                (0,4,(.202,.045,1.405)), (0,5,(.238,.061,1.415)),
                (0,6,(.274,.043,1.430)), (0,7,(.286,.023,1.437)),
                (0,8,(.291,-.001,1.441)), (0,9,(.285,-.025,1.438)),
                (0,10,(.272,-.046,1.432)), (0,11,(.238,-.071,1.420)),
                (1,11,(.268,-.074,1.346)), (1,5,(.268,.065,1.340)),
                (2,11,(.300,-.067,1.267)), (2,5,(.300,.052,1.250)),
                (3,11,(.319,-.054,1.211)), (3,5,(.319,.037,1.198)),
                (4,11,(.332,-.048,1.168)), (4,5,(.332,.032,1.158)),
                (5,11,(.346,-.060,1.130)), (5,5,(.346,.030,1.124)),
                (6,11,(.369,-.058,1.078)), (6,5,(.369,.025,1.071)),
            ]:
                limb_point(side,'arm',row,index,p)

            # Posterior gluteal fold and the anterior inguinal/adductor slope
            # meet the thigh at different heights. EXP37 moves the first two
            # sections along the femoral attachment, rather than continuing
            # the pelvic rim as a flat skirt or a high sharp V. Front points
            # turn gradually into the proximal thigh; the posterior fold
            # remains lower than the lateral greater-trochanter transition.
            for row, index, p in [
                (0,0,(.023,-.063,.843)), (0,1,(.050,-.090,.853)),
                (0,2,(.094,-.100,.864)), (0,3,(.133,-.087,.875)),
                (0,4,(.157,-.050,.884)), (0,5,(.166,.001,.886)),
                (0,6,(.156,.054,.883)), (0,7,(.128,.101,.874)),
                (0,8,(.094,.120,.863)), (0,9,(.052,.103,.851)),
                (0,10,(.024,.063,.842)), (0,11,(.009,.001,.833)),
                (1,0,(.026,-.051,.800)), (1,1,(.052,-.084,.810)),
                (1,2,(.096,-.101,.819)), (1,3,(.137,-.086,.828)),
                (1,4,(.164,-.047,.825)), (1,5,(.174,.002,.818)),
                (1,6,(.164,.049,.817)), (1,7,(.137,.080,.816)),
                (1,8,(.096,.094,.811)), (1,9,(.052,.082,.802)),
                (1,10,(.026,.050,.792)), (1,11,(.014,.004,.787)),
                # Vastus lateralis is higher than the medial teardrop; the
                # adductor plane flattens rather than bulging equally around.
                (2,2,(.096,-.090,.750)), (2,3,(.139,-.074,.759)),
                (2,4,(.169,-.041,.755)), (2,5,(.175,.000,.745)),
                (2,8,(.096,.087,.745)), (2,11,(.020,.001,.738)),
                (3,2,(.101,-.085,.672)), (3,3,(.139,-.068,.680)),
                (3,4,(.163,-.039,.677)), (3,5,(.167,-.002,.664)),
                (3,8,(.101,.075,.661)), (3,11,(.034,-.001,.655)),
                (4,1,(.064,-.057,.585)), (4,2,(.102,-.073,.596)),
                (4,3,(.135,-.058,.605)), (4,5,(.157,-.009,.593)),
                (4,8,(.102,.050,.587)), (4,11,(.050,-.007,.579)),
                # Patella/condyles, then tibial front plane and calf heads.
                (5,1,(.068,-.054,.549)), (5,2,(.101,-.074,.554)),
                (5,3,(.132,-.055,.555)), (5,5,(.150,-.011,.548)),
                (5,8,(.101,.031,.547)), (5,11,(.054,-.010,.543)),
                (6,1,(.068,-.054,.515)), (6,2,(.100,-.080,.516)),
                (6,3,(.130,-.057,.519)), (6,5,(.147,-.012,.515)),
                (6,8,(.100,.025,.511)), (6,11,(.052,-.012,.511)),
                (7,2,(.101,-.066,.480)), (7,5,(.146,-.006,.480)),
                (7,8,(.101,.032,.478)), (7,11,(.057,-.007,.477)),
                (8,2,(.103,-.058,.440)), (8,7,(.145,.047,.447)),
                (8,8,(.103,.059,.438)), (8,9,(.065,.045,.431)),
                (9,2,(.106,-.048,.375)), (9,7,(.147,.067,.390)),
                (9,8,(.106,.076,.376)), (9,9,(.071,.066,.360)),
                (10,2,(.108,-.037,.300)), (10,7,(.139,.053,.315)),
                (10,8,(.108,.067,.303)), (10,9,(.079,.063,.294)),
                (11,2,(.108,-.031,.225)), (11,7,(.130,.039,.234)),
                (11,8,(.108,.049,.228)), (11,9,(.088,.044,.221)),
                (12,8,(.106,.034,.160)),
            ]:
                limb_point(side,'leg',row,index,p)

        self.loops['sternoclavicular_shelf'] = [self.loops['acromion_clavicle'][i]
                                              for i in (12,13,14,15,16,17,18)]
        self.loops['suprasternal_fossa'] = [self.loops['trapezius_neck'][i]
                                          for i in (14,15,16)]
        self.loops['costal_arch'] = [self.loops['costal_margin'][i]
                                    for i in (11,12,13,14,15,16,17,18,19)]
        self.loops['iliac_crest_surface'] = [self.loops['upper_pelvis'][i]
                                           for i in (18,19,0,1,2,8,9,10,11,12)]
        for side in ('L','R'):
            self.loops['gluteal_fold.'+side] = [self.loops['leg.%s.00' % side][i]
                                              for i in (6,7,8,9,10)]
            # Metadata identifies the existing connected fold strips. These
            # are not added geometry, skin patches or a separate inner shell.
            socket = self.loops['shoulder_socket.'+side]
            self.loops['axillary_floor.'+side] = socket[:5]
            self.loops['anterior_axillary_fold.'+side] = [socket[0],socket[11],
                self.loops['arm.%s.00' % side][11]]
            self.loops['posterior_axillary_fold.'+side] = [socket[4],socket[5],
                self.loops['arm.%s.00' % side][5]]
            self.loops['proximal_thigh_transition.'+side] = self.loops['leg.%s.00' % side]


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
    obj['study_status'] = 'EXP37 joint-transition candidate; visual review required'
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
        'anatomy_reference_pages': list(PROVENANCE),
        'notes': ['All-quads connected torso/limbs; five open join boundaries.',
                  'Manually editable cage and unapplied subdivision remain source.',
                  'EXP37 explicit axillary/hip transition candidate; not an anatomical measurement.',
                  'Fixed join loop IDs and landmark positions do not imply visual acceptance.'],
    }
    return obj, info

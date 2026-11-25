# blender -b --factory-startup -P Tools/make_clothes.py
# Rebuilds every stand-in garment, plate, mask and clothes.blend. It OVERWRITES
# them: do not run it once any of them has been changed by hand.
import bpy, bmesh, math, os
from mathutils import Vector, noise
from math import sin, cos, pi, radians, exp, sqrt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Assets", "Clothes")
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "Assets", "BaseMale", "Superhero_Male_FullBody.gltf"))
arm = bpy.data.objects["Armature"]
body = bpy.data.objects["SuperHero_Male"]
ico = bpy.data.objects.get("Icosphere")
if ico:
    bpy.data.objects.remove(ico)

COLORS = {"Cloth": .04, "Collar": .6, "Plate": .3, "Iron": .12, "Cord": .05, "Pale": .7, "Mask": .85, "MaskInk": .02, "Topknot": .02}
mats = {}
for k, v in COLORS.items():
    m = bpy.data.materials.new(k)
    m.use_backface_culling = False
    m.diffuse_color = (v, v, v, 1)
    if m.node_tree is None:
        m.use_nodes = True
    for n in m.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            n.inputs["Base Color"].default_value = (v, v, v, 1)
            n.inputs["Roughness"].default_value = 1.0
    mats[k] = m


def sm(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def table(rows, z):
    if z <= rows[0][0]:
        return rows[0][1:]
    for p, q in zip(rows, rows[1:]):
        if z <= q[0]:
            t = (z - p[0]) / (q[0] - p[0])
            return [lerp(a, b, t) for a, b in zip(p[1:], q[1:])]
    return rows[-1][1:]


def finish(bm, name, materials, smooth=True, doubles=1e-5):
    if doubles:
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=doubles)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in materials:
        me.materials.append(mats[m])
    for p in me.polygons:
        p.use_smooth = smooth
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    return ob


def apply(ob, mod):
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def rig(ob):
    ob.parent = arm
    m = ob.modifiers.new("Armature", "ARMATURE")
    m.object = arm


def weigh(ob):
    for g in body.vertex_groups:
        if g.name not in ob.vertex_groups:
            ob.vertex_groups.new(name=g.name)
    m = ob.modifiers.new("w", "DATA_TRANSFER")
    m.object = body
    m.use_vert_data = True
    m.data_types_verts = {"VGROUP_WEIGHTS"}
    m.vert_mapping = "POLYINTERP_NEAREST"
    apply(ob, m)
    bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
    bpy.ops.object.vertex_group_smooth(group_select_mode="ALL", factor=0.5, repeat=6)
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def grid(bm, rows, closed=True, mat=0, keep=None):
    """Faces between rings of points."""
    vs = [[bm.verts.new(p) for p in r] for r in rows]
    for a, b in zip(vs, vs[1:]):
        n = len(a)
        for i in range(n if closed else n - 1):
            q = [a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]]
            c = sum((v.co for v in q), Vector()) / 4
            if keep and not keep(c):
                continue
            f = bm.faces.new(q)
            f.material_index = mat
    return vs


# ---------------------------------------------------------------- kimono
def kimono(name, sleeve_to, bag):
    ob = body.copy()
    ob.data = body.data.copy()
    ob.name = name
    bpy.context.scene.collection.objects.link(ob)
    ob.modifiers.clear()
    ob.parent = None
    me = ob.data
    me.materials.clear()
    for m in ["Cloth", "Collar"]:
        me.materials.append(mats[m])
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0003)
    def out(c):
        x = abs(c.x)
        if c.z < 0.95 or x > sleeve_to:
            return True
        return c.z > 1.525 and x < 0.115 + (0.02 if c.y > 0.03 else 0.0) and not (x > 0.085 and c.z < 1.55)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if out(f.calc_center_median())], context="FACES")
    inner = [v for v in bm.verts if not v.is_boundary]
    for k in range(18):
        bmesh.ops.smooth_vert(bm, verts=inner, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * 0.026
    bm.to_mesh(me)
    bm.free()
    sw = ob.modifiers.new("s", "SHRINKWRAP")
    sw.target = body
    sw.wrap_method = "NEAREST_SURFACEPOINT"
    sw.wrap_mode = "OUTSIDE"
    sw.offset = 0.03
    apply(ob, sw)
    bm = bmesh.new()
    bm.from_mesh(me)
    for k in range(3):
        bmesh.ops.smooth_vert(bm, verts=[v for v in bm.verts if not v.is_boundary], factor=0.4, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    # The neck: a V in front, with a band along it.
    A = Vector((0, 0, 1.2))
    for off in (0.0, 0.042):
        for s in (1, -1):
            n = Vector((s * 0.37, 0, -0.13)).normalized()
            front = [f for f in bm.faces if f.calc_center_median().y < 0.06 and f.calc_center_median().z > 1.1]
            geom = front + list({e for f in front for e in f.edges}) + list({v for f in front for v in f.verts})
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=A + n * off, plane_no=n)
    def band(c):
        return (abs(c.x) * 0.37 - (c.z - 1.2) * 0.13) / sqrt(0.37 ** 2 + 0.13 ** 2)
    gone = [f for f in bm.faces if f.calc_center_median().y < 0.06 and band(f.calc_center_median()) < -0.0005 and f.calc_center_median().z > 1.15]
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    for f in bm.faces:
        c = f.calc_center_median()
        if c.y < 0.06 and band(c) < 0.042 and c.z > 1.1:
            f.material_index = 1
            for v in f.verts:
                pass
    raised = {v for f in bm.faces if f.material_index == 1 for v in f.verts}
    bm.normal_update()
    for v in raised:
        v.co += v.normal * 0.006
    # Sleeves hang.
    for v in bm.verts:
        x = abs(v.co.x)
        t = sm(0.2, sleeve_to, x)
        dz = v.co.z - 1.45
        dy = v.co.y - 0.075
        if x > 0.2:
            v.co.z = 1.45 + dz * (1 + (bag * 2.6 if dz < 0 else bag * 0.35) * t)
            v.co.y = 0.075 + dy * (1 + bag * 0.75 * t)
        w = noise.noise(v.co * 9.0) * 0.007 + noise.noise(v.co * 23.0) * 0.003
        v.co += v.normal * w
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    m = ob.modifiers.new("d", "DECIMATE")
    m.ratio = 0.5
    apply(ob, m)
    rig(ob)
    return ob


# ---------------------------------------------------------------- hakama
def hakama(name, bottom, tied):
    legs = [(.1, .16, .085, .15, .2), (.3, .145, .08, .14, .185), (.5, .13, .055, .125, .165), (.8, .105, .025, .105, .135), (1.1, .09, .02, .095, .13)]
    waist = [(.8, .2, .15, .02), (.95, .195, .152, .022), (1.02, .182, .142, .018), (1.09, .175, .13, .008)]
    objs = []
    bm = bmesh.new()
    for s in (1, -1):
        rows = []
        N = 32
        steps = 18
        for r in range(steps + 1):
            z = lerp(1.09, bottom, r / steps)
            cx, cy, rx, ry = table(legs, z)
            if tied:
                g = sm(bottom + 0.3, bottom, z)
                rx = lerp(rx * (1 + 0.1 * sin(pi * g)), 0.078, g * g)
                ry = lerp(ry * (1 + 0.1 * sin(pi * g)), 0.088, g * g)
                cx = lerp(cx, 0.125, g)
            a, b, wy = table(waist, z)
            mix = sm(0.97, 0.76, z)
            down = sm(1.05, bottom, z)
            row = []
            for i in range(N):
                th = 2 * pi * i / N
                pleat = 1 + (0.02 + 0.06 * down * (0.4 if tied else 1.0)) * cos(8 * th + 0.6 * sin(3 * th)) + 0.02 * noise.noise(Vector((cos(th) * 2, sin(th) * 2, z * 5 + s)))
                wx, wyy = max(a * cos(th) * pleat, 0.003), wy + b * sin(th) * pleat
                lx, ly = max(cx + rx * cos(th) * pleat, 0.004), cy + ry * sin(th) * pleat
                row.append(Vector((s * lerp(wx, lx, mix), lerp(wyy, ly, mix), z)))
            rows.append(row)
        grid(bm, rows, True, 0, lambda c: not (abs(c.x) < 0.006 and c.z > 0.8))
    # The belt over it.
    rows = []
    for r in range(5):
        z = lerp(1.0, 1.115, r / 4)
        bulge = 0.012 * sin(pi * r / 4)
        rows.append([Vector(((0.186 + bulge) * cos(t), 0.012 + (0.146 + bulge) * sin(t), z)) for t in [2 * pi * i / 40 for i in range(40)]])
    grid(bm, rows, True, 1)
    ob = finish(bm, name, ["Cloth", "Collar"])
    weigh(ob)
    rig(ob)
    return ob


# ---------------------------------------------------------------- armour
TRUNK = [(1.02, .2, -.155, .185), (1.1, .196, -.155, .165), (1.2, .196, -.16, .15), (1.3, .225, -.175, .195), (1.4, .23, -.17, .205), (1.47, .2, -.14, .2)]


def trunk_ring(z, out, n=48, p=2.5):
    a, yf, yb = table(TRUNK, z)
    a += out
    b = (yb - yf) / 2 + out
    cy = (yb + yf) / 2
    row = []
    for i in range(n):
        t = 2 * pi * i / n
        c, s = cos(t), sin(t)
        row.append(Vector((a * math.copysign(abs(c) ** (2 / p), c), cy + b * math.copysign(abs(s) ** (2 / p), s), z)))
    return row


def solid(ob, t):
    m = ob.modifiers.new("t", "SOLIDIFY")
    m.thickness = t
    m.offset = 0
    apply(ob, m)


def ribbon(bm, pts, across, mat):
    grid(bm, [[p + across, p - across] for p in pts], False, mat)


def do():
    bm = bmesh.new()
    keep = lambda c: c.z < 1.31 or abs(c.x) < 0.155
    z = 1.04
    k = 0
    while z < 1.46:
        top = z + 0.056
        grid(bm, [trunk_ring(z, 0.015), trunk_ring(z + 0.009, 0.017)], True, 1, keep)
        grid(bm, [trunk_ring(z + 0.009, 0.017), trunk_ring(top, 0.003)], True, 0, keep)
        # The lacing between.
        for i in range(0, 48, 2):
            p = trunk_ring(z + 0.004, 0.019)[i]
            q = trunk_ring(z - 0.02, 0.016)[i]
            if keep(p):
                w = Vector((-(p.y - 0.01), p.x, 0)).normalized() * 0.005
                f = bm.faces.new([bm.verts.new(v) for v in (p - w, p + w, q + w, q - w)])
                f.material_index = 1
        z += 0.05
        k += 1
    for s in (1, -1):
        pts = []
        for i in range(13):
            t = i / 12
            an = lerp(-0.1, pi + 0.1, t)
            pts.append(Vector((s * (0.115 + 0.01 * sin(pi * t)), 0.02 - 0.185 * cos(an), 1.445 + 0.135 * sin(an))))
        ribbon(bm, pts, Vector((0.028, 0, 0)), 0)
    return finish(bm, "chest", ["Plate", "Cord"], False, 0)


def under():
    bm = bmesh.new()
    grid(bm, [trunk_ring(lerp(1.03, 1.45, i / 12), -0.004) for i in range(13)], True, 0, lambda c: c.z < 1.31 or abs(c.x) < 0.15)
    return finish(bm, "chest_under", ["Iron"], True)


def kusazuri():
    bm = bmesh.new()
    N = 7
    for k in range(N):
        mid = -pi / 2 + 2 * pi * k / N
        half = pi / N * 0.86
        for l in range(4):
            z0 = 1.03 - l * 0.062
            z1 = z0 - 0.068
            o0 = 0.006 + l * 0.024
            o1 = o0 + 0.03
            rows = []
            for z, o in ((z0, o0), (z1 + 0.012, o1), (z1, o1 - 0.001)):
                rows.append([Vector(((0.207 + o) * cos(t), 0.015 + (0.178 + o) * sin(t), z)) for t in [lerp(mid - half, mid + half, i / 7) for i in range(8)]])
            grid(bm, rows, False, 0)
            for i in range(1, 7, 2):
                t = lerp(mid - half, mid + half, i / 7)
                d = Vector((cos(t), sin(t), 0))
                w = Vector((-sin(t), cos(t), 0)) * 0.005
                p = Vector(((0.213 + o1) * cos(t), 0.015 + (0.184 + o1) * sin(t), z1 + 0.012))
                q = p - Vector((0, 0, 0.026))
                f = bm.faces.new([bm.verts.new(v) for v in (p - w, p + w, q + w, q - w)])
                f.material_index = 1
    return finish(bm, "hips", ["Plate", "Cord"], False, 0)


def sode(s):
    bm = bmesh.new()
    for l in range(5):
        x0 = 0.185 + l * 0.047
        x1 = x0 + 0.056
        rows = []
        for x, o in ((x0, 0.0), (x1 - 0.01, 0.014), (x1, 0.013)):
            rows.append([Vector((s * x, 0.078 + (0.118 + o) * sin(p), 1.44 + (0.125 + o) * cos(p))) for p in [radians(lerp(-72, 72, i / 12)) for i in range(13)]])
        grid(bm, rows, False, 0)
        for i in range(1, 12, 2):
            p = radians(lerp(-72, 72, i / 12))
            at = Vector((s * (x1 - 0.004), 0.078 + 0.137 * sin(p), 1.44 + 0.144 * cos(p)))
            w = Vector((0, cos(p), -sin(p))) * 0.005
            q = at + Vector((s * 0.024, 0, 0))
            f = bm.faces.new([bm.verts.new(v) for v in (at - w, at + w, q + w, q - w)])
            f.material_index = 1
    return finish(bm, "upper_l" if s > 0 else "upper_r", ["Plate", "Cord"], False, 0)


def kote(s):
    bm = bmesh.new()
    rows = []
    for i in range(9):
        t = i / 8
        x = lerp(0.49, 0.69, t)
        r = lerp(0.07, 0.052, t)
        rows.append([Vector((s * x, 0.078 + (r + (0.006 if (j % 4) < 2 else 0.0)) * cos(2 * pi * j / 32), 1.443 + (r + (0.006 if (j % 4) < 2 else 0.0)) * sin(2 * pi * j / 32))) for j in range(32)])
    grid(bm, rows, True, 0)
    # Over the back of the hand.
    grid(bm, [[Vector((s * x, 0.068 + w * sin(p), 1.445 + 0.045 * cos(p))) for p in [radians(a) for a in range(-60, 61, 20)]] for x, w in ((0.69, 0.055), (0.75, 0.062), (0.8, 0.05))], False, 0)
    return finish(bm, "fore_l" if s > 0 else "fore_r", ["Iron"], False)


def suneate(s):
    bm = bmesh.new()
    rows = []
    for i in range(10):
        t = i / 9
        z = lerp(0.1, 0.5, t)
        cy = lerp(0.085, 0.06, t)
        r = table([(.1, .075), (.3, .095), (.45, .092), (.5, .105)], z)[0]
        rows.append([Vector((s * 0.118 + (r + (0.006 if (j % 4) < 2 else 0)) * cos(a), cy + (r + (0.006 if (j % 4) < 2 else 0)) * sin(a), z)) for j, a in enumerate([radians(lerp(160, 380, k / 28)) for k in range(29)])])
    grid(bm, rows, False, 0)
    return finish(bm, "shin_l" if s > 0 else "shin_r", ["Iron"], False)


def helmet():
    bm = bmesh.new()
    N = 64
    cy = 0.004
    def rib(j):
        return 1.0 + (0.018 if j % 4 == 0 else 0.0)
    rows = []
    for i in range(11):
        t = i / 10
        e = t * pi / 2 * 0.97
        rows.append([Vector((0.128 * cos(e) ** 0.85 * rib(j) * cos(2 * pi * j / N), cy + 0.142 * cos(e) ** 0.85 * rib(j) * sin(2 * pi * j / N), 1.738 + 0.142 * sin(e))) for j in range(N)])
    grid(bm, rows, True, 0)
    knob = [[Vector((r * cos(2 * pi * j / 16), cy + r * sin(2 * pi * j / 16), z)) for j in range(16)] for r, z in ((.03, 1.872), (.024, 1.884), (.014, 1.892), (.002, 1.895))]
    grid(bm, knob, True, 2)
    # The visor.
    rows = []
    for o, d in ((0, 0.004), (0.025, 0.0), (0.06, -0.018)):
        rows.append([Vector(((0.129 + o * 0.6) * sin(a), cy - (0.143 + o) * cos(a), 1.74 + d - 0.006 * abs(sin(a)))) for a in [radians(lerp(-62, 62, k / 20)) for k in range(21)]])
    grid(bm, rows, False, 0)
    # The neck, in lames.
    for l in range(4):
        z0 = 1.752 - l * 0.042
        o0 = 0.004 + l * 0.026
        rows = []
        for z, o in ((z0, o0), (z0 - 0.04, o0 + 0.034), (z0 - 0.048, o0 + 0.035)):
            rows.append([Vector(((0.13 + o) * sin(a), cy - (0.144 + o) * cos(a), z)) for a in [radians(lerp(72, 288, k / 36)) for k in range(37)]])
        grid(bm, rows, False, 0)
        for k in range(0, 37, 3):
            a = radians(lerp(72, 288, k / 36))
            p = Vector(((0.133 + o0 + 0.034) * sin(a), cy - (0.147 + o0 + 0.034) * cos(a), z0 - 0.034))
            w = Vector((cos(a), sin(a), 0)) * 0.005
            q = p - Vector((0, 0, 0.022))
            f = bm.faces.new([bm.verts.new(v) for v in (p - w, p + w, q + w, q - w)])
            f.material_index = 3
    # The crest.
    for s in (1, -1):
        left, right = [], []
        for i in range(13):
            t = i / 12
            a = radians(lerp(5, 62, t ** 0.8))
            at = Vector((s * (0.018 + 0.15 * sin(a) * t ** 0.6), -0.152 - 0.02 * t, 1.765 + 0.19 * t))
            w = 0.018 * (1 - t) ** 0.5 + 0.006 * sin(pi * t) + 0.0005
            side = Vector((s * cos(a), 0, -sin(a) * 0.4)) * w
            left.append(at - side)
            right.append(at + side)
        grid(bm, [[l, r] for l, r in zip(left, right)], False, 2)
    return finish(bm, "helmet", ["Iron", "Plate", "Pale", "Cord"], False, 0)


# ---------------------------------------------------------------- masks
def g(x, z, cx, cz, sx, sz):
    return exp(-((x - cx) / sx) ** 2 - ((z - cz) / sz) ** 2)


def both(x, z, cx, cz, sx, sz):
    return g(x, z, cx, cz, sx, sz) + g(x, z, -cx, cz, sx, sz)


def slant(x, z, cx, cz, sx, sz, tilt):
    """A pair of shapes that rise outward by `tilt`."""
    ax = abs(x)
    return exp(-((ax - cx) / sx) ** 2 - ((z - cz - tilt * (ax - cx)) / sz) ** 2)


def mask(name, relief, hole, paint, lo=1.565, hi=1.79, spread=82, thick=0.0):
    bm = bmesh.new()
    U, V = 96, 100
    rows, info = [], []
    for j in range(V + 1):
        z = lerp(lo, hi, j / V)
        X, Y = table([(1.555, .058, .108), (1.585, .078, .118), (1.63, .096, .124), (1.69, .104, .126), (1.74, .1, .122), (1.79, .082, .104)], z)
        row = []
        for i in range(U + 1):
            a = radians(lerp(-spread, spread, i / U))
            x = X * sin(a)
            h = relief(x, z) * cos(a) ** 0.5
            row.append(Vector((x * (1 + h * 1.5), 0.0 - (Y + h) * cos(a), z)))
        rows.append(row)
    vs = [[bm.verts.new(p) for p in r] for r in rows]
    for j in range(V):
        for i in range(U):
            c = (rows[j][i] + rows[j + 1][i + 1]) / 2
            zc = lerp(lo, hi, (j + 0.5) / V)
            if hole(c.x, zc):
                continue
            f = bm.faces.new([vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]])
            f.material_index = paint(c.x, zc)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    # Soften the saw edges the holes were cut with.
    for k in range(4):
        edge = [v for v in bm.verts if v.is_boundary]
        new = {}
        for v in edge:
            n = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
            if len(n) == 2:
                new[v] = v.co * 0.5 + (n[0].co + n[1].co) * 0.25
        for v, co in new.items():
            v.co = co
    return bm


def cone(bm, base, tip, r, bend, mat, sides=14, steps=9, power=1.0):
    way = tip - base
    up = way.normalized()
    side = up.cross(Vector((0, 1, 0)) if abs(up.y) < 0.9 else Vector((1, 0, 0))).normalized()
    fore = up.cross(side)
    rows = []
    for i in range(steps + 1):
        t = i / steps
        c = base + way * t + bend * sin(pi * t)
        rr = r * (1 - t) ** power + 0.0006
        rows.append([c + side * rr * cos(2 * pi * j / sides) + fore * rr * sin(2 * pi * j / sides) for j in range(sides)])
    grid(bm, rows, True, mat)


def done(bm, name, materials, faces):
    ob = finish(bm, name, materials, True)
    many = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    m = ob.modifiers.new("d", "DECIMATE")
    m.ratio = min(1.0, faces / many)
    apply(ob, m)
    return ob


def eye(x, z, cx, cz, rx, rz, tilt):
    ax = abs(x)
    return ((ax - cx) / rx) ** 2 + ((z - cz - tilt * (ax - cx)) / rz) ** 2 < 1


def noh():
    def relief(x, z):
        return (0.02 * g(x, z, 0, 1.658, .011, .022) + 0.009 * g(x, z, 0, 1.69, .008, .03) + 0.006 * both(x, z, .013, 1.65, .007, .007)
                + 0.006 * both(x, z, .05, 1.645, .028, .03) - 0.008 * both(x, z, .036, 1.7, .02, .01) + 0.004 * both(x, z, .036, 1.712, .02, .006)
                + 0.009 * g(x, z, 0, 1.624, .022, .006) + 0.008 * g(x, z, 0, 1.609, .018, .006) - 0.004 * g(x, z, 0, 1.616, .02, .003)
                + 0.008 * g(x, z, 0, 1.583, .025, .014) + 0.004 * g(x, z, 0, 1.755, .06, .03))
    hole = lambda x, z: eye(x, z, .036, 1.697, .02, .0052, -.12) or (abs(x) < .02 and abs(z - 1.6165 - 3 * x * x) < .0026)
    def paint(x, z):
        if eye(x, z, .034, 1.75, .015, .0055, .1):
            return 1
        if abs(x) < .026 and abs(z - 1.6165) < .0105 * (1 - (x / .028) ** 2):
            return 1
        return 0
    return done(mask("noh", relief, hole, paint), "noh", ["Mask", "MaskInk"], 2600)


def demon(name, skin, horns, fang):
    def relief(x, z):
        return (0.026 * slant(x, z, .036, 1.724, .03, .011, .55) + 0.03 * g(x, z, 0, 1.655, .017, .02) + 0.014 * g(x, z, 0, 1.69, .01, .025)
                + 0.014 * both(x, z, .022, 1.647, .011, .011) + 0.016 * both(x, z, .055, 1.66, .022, .022)
                - 0.012 * slant(x, z, .038, 1.697, .022, .012, .3) - 0.008 * both(x, z, .03, 1.635, .01, .012)
                + 0.014 * g(x, z, 0, 1.578, .028, .014) + 0.01 * both(x, z, .05, 1.6, .016, .02)
                + 0.008 * abs(g(x, z, 0, 1.745, .006, .03)) + 0.006 * both(x, z, .014, 1.75, .004, .02))
    def mouth(x, z, grow=0.0):
        mid = 1.612 + 5.5 * x * x
        return abs(x) < .052 + grow and abs(z - mid) < (.0135 + grow) * (1 - (x / (.054 + grow)) ** 4)
    hole = lambda x, z: eye(x, z, .038, 1.697, .02, .0085, .35) or mouth(x, z)
    def paint(x, z):
        if eye(x, z, .038, 1.697, .026, .0135, .35):
            return 1
        if mouth(x, z, .006):
            return 1
        ax = abs(x)
        return 1 if ax > .012 and ax < .075 and abs(z - 1.742 - .5 * (ax - .036)) < .006 * (1 - ((ax - .04) / .04) ** 2) else 0
    bm = mask(name, relief, hole, paint)
    for s in (1, -1):
        for x, up, ln in ((.034, True, fang), (.03, False, fang * .8), (.018, True, .009), (.007, True, .009), (.016, False, .008), (.005, False, .008), (.044, True, .01)):
            zc = 1.612 + 5.5 * x * x + (.013 if up else -.013)
            base = Vector((s * x, -0.121 + x * x * 6, zc))
            tip = base + Vector((s * .002, -.006 if ln > .012 else 0.0, -ln if up else ln))
            cone(bm, base, tip, .0055 if ln > .012 else .0045, Vector((0, 0, 0)), 2, 8, 4)
        if horns > 0:
            base = Vector((s * .058, -.088, 1.772))
            cone(bm, base, base + Vector((s * horns * .42, -.02, horns)), .015, Vector((s * horns * .22, -.015, 0)), 2, 12, 10, .8)
    return done(bm, name, [skin, "MaskInk", "Pale"], 3000)


def tengu():
    def relief(x, z):
        return (0.02 * slant(x, z, .036, 1.722, .034, .012, .1) + 0.02 * g(x, z, 0, 1.67, .018, .022) + 0.012 * both(x, z, .052, 1.65, .022, .022)
                - 0.01 * both(x, z, .038, 1.697, .022, .011) + 0.01 * g(x, z, 0, 1.618, .03, .006) + 0.012 * g(x, z, 0, 1.58, .026, .014)
                - 0.006 * both(x, z, .03, 1.63, .01, .012))
    hole = lambda x, z: eye(x, z, .038, 1.697, .019, .0078, .05) or (abs(x) < .03 and abs(z - 1.608 + 4 * x * x) < .0035)
    def paint(x, z):
        ax = abs(x)
        if eye(x, z, .038, 1.697, .025, .0125, .05):
            return 1
        return 2 if eye(x, z, .04, 1.737, .03, .009, .25) else 0
    bm = mask("tengu", relief, hole, paint)
    cone(bm, Vector((0, -.125, 1.668)), Vector((0, -.27, 1.69)), .019, Vector((0, 0, -.012)), 0, 16, 10, .42)
    return done(bm, "tengu", ["Plate", "MaskInk", "Pale"], 2800)


def menpo():
    def relief(x, z):
        return (0.03 * g(x, z, 0, 1.66, .016, .022) + 0.012 * both(x, z, .05, 1.645, .02, .018) + 0.012 * g(x, z, 0, 1.627, .04, .006)
                + 0.014 * g(x, z, 0, 1.58, .026, .014) - 0.006 * both(x, z, .03, 1.632, .009, .01) + 0.004 * sin(z * 420) * (1 if z < 1.6 else 0))
    top = lambda x: 1.664 + .02 * sm(.02, .05, abs(x)) * (1 - sm(.06, .1, abs(x))) + .022 * max(0, 1 - (x / .02) ** 2)
    hole = lambda x, z: z > top(x) or (abs(x) < .03 and abs(z - 1.612 - 4 * x * x) < .008 * (1 - (x / .031) ** 2))
    def paint(x, z):
        ax = abs(x)
        if abs(z - 1.634 + .35 * max(0, ax - .012)) < .0055 * (1 - ax / .062) and ax < .06:
            return 2
        return 1 if abs(x) < .04 and abs(z - 1.612) < .015 and abs(z - 1.612) > .006 and abs(x) < .034 else 0
    bm = mask("menpo", relief, hole, paint, hi=1.7)
    return done(bm, "menpo", ["Iron", "MaskInk", "Pale"], 2200)


def export(path, objs, skinned):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    if skinned:
        arm.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, path), export_format="GLB", use_selection=True, export_animations=False, export_yup=True)


def hair():
    ob = body.copy()
    ob.data = body.data.copy()
    ob.name = "hair"
    bpy.context.scene.collection.objects.link(ob)
    ob.modifiers.clear()
    ob.parent = None
    me = ob.data
    me.materials.clear()
    me.materials.append(mats["Topknot"])
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0003)
    def out(c):
        front = 1.765 if c.y < -0.03 else lerp(1.75, 1.6, sm(-0.03, 0.06, c.y))
        ear = abs(c.x) > 0.077 and c.z < 1.73 and c.y < 0.04
        return c.z < front or ear or abs(c.x) > 0.12
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if out(f.calc_center_median())], context="FACES")
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * (0.004 if v.is_boundary else 0.01)
    dl = bm.verts.layers.deform.verify()
    head = ob.vertex_groups["Head"].index
    # Tied up behind and folded forward over the crown.
    start = len(bm.verts)
    spine = [(.105, 1.76, .02), (.125, 1.785, .024), (.12, 1.815, .018), (.095, 1.838, .016), (.055, 1.852, .02), (.015, 1.85, .022), (-.015, 1.845, .016), (-.03, 1.842, .003)]
    rows = [[Vector((r * cos(a), y + r * 0.6 * sin(a), z + r * 0.6 * sin(a))) for a in [2 * pi * k / 10 for k in range(10)]] for y, z, r in spine]
    vs = grid(bm, rows, True, 0)
    for r in vs:
        for v in r:
            v[dl][head] = 1.0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    m = ob.modifiers.new("d", "DECIMATE")
    m.ratio = min(1.0, 900 / max(1, len(me.polygons)))
    apply(ob, m)
    rig(ob)
    return ob


made = {}
for path, build in (("kimono.glb", lambda: kimono("kimono", 0.64, 1.0)), ("kimono_tied.glb", lambda: kimono("kimono_tied", 0.44, 0.3)),
        ("hair.glb", hair),
        ("hakama.glb", lambda: hakama("hakama", 0.1, False)), ("hakama_tied.glb", lambda: hakama("hakama_tied", 0.4, True))):
    ob = build()
    made[path] = [ob]
    export(path, [ob], True)
    print("DONE", path, len(ob.data.polygons))
plates = [do(), under(), kusazuri(), helmet()] + [f(s) for f in (sode, kote, suneate) for s in (1, -1)]
for ob in plates:
    solid(ob, 0.005 if ob.name != "helmet" else 0.004)
export("armour.glb", plates, False)
print("DONE armour", sum(len(o.data.polygons) for o in plates))
for nm, build in (("mask_noh", noh), ("mask_oni", lambda: demon("oni", "Plate", 0.0, .024)), ("mask_hannya", lambda: demon("hannya", "Mask", .13, .02)), ("mask_tengu", tengu), ("mask_menpo", menpo)):
    ob = build()
    export(nm + ".glb", [ob], False)
    print("DONE", nm, len(ob.data.polygons))
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "clothes.blend"))

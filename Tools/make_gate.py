# blender -b --factory-startup -P Tools/make_gate.py
# Rebuilds the stand-in gatehouse and gate.blend. OVERWRITES them.
import bpy, bmesh, math, os
from mathutils import Vector, Matrix
from math import sin, cos, pi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Assets", "Gate")
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
mats = {}
for k, v in {"Wood": .06, "Plank": .12, "Plaster": .6, "Tile": .05, "Iron": .03, "Paper": .9}.items():
    m = bpy.data.materials.new(k)
    if m.node_tree is None:
        m.use_nodes = True
    for n in m.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            n.inputs["Base Color"].default_value = (v, v, v, 1)
    mats[k] = m


class Build:
    def __init__(self, name):
        self.name, self.bm, self.slots = name, bmesh.new(), []

    def slot(self, mat):
        if mat not in self.slots:
            self.slots.append(mat)
        return self.slots.index(mat)

    def box(self, mat, lo, hi, taper=0.0):
        i = self.slot(mat)
        vs = []
        for z in (0, 1):
            t = taper if z else 0.0
            for x, y in ((0, 0), (1, 0), (1, 1), (0, 1)):
                vs.append(self.bm.verts.new((lo[0] + t + (hi[0] - lo[0] - 2 * t) * x, lo[1] + t + (hi[1] - lo[1] - 2 * t) * y, lo[2] + (hi[2] - lo[2]) * z)))
        for q in ((3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            self.bm.faces.new([vs[k] for k in q]).material_index = i

    def post(self, mat, x, y, z0, z1, r):
        i = self.slot(mat)
        n = 12
        rows = [[self.bm.verts.new((x + rr * cos(2 * pi * k / n), y + rr * sin(2 * pi * k / n), z)) for k in range(n)] for z, rr in ((z0, r), (z1, r * 0.94))]
        for k in range(n):
            self.bm.faces.new((rows[0][k], rows[0][(k + 1) % n], rows[1][(k + 1) % n], rows[1][k])).material_index = i

    def sheet(self, mat, rows):
        i = self.slot(mat)
        vs = [[self.bm.verts.new(p) for p in r] for r in rows]
        for a, b in zip(vs, vs[1:]):
            for k in range(len(a) - 1):
                self.bm.faces.new((a[k], a[k + 1], b[k + 1], b[k])).material_index = i

    def done(self, at=(0, 0, 0)):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for s in self.slots:
            me.materials.append(mats[s])
        ob = bpy.data.objects.new(self.name, me)
        ob.location = at
        bpy.context.scene.collection.objects.link(ob)
        return ob


W, L, H = 1.5, 2.5, 2.75
b = Build("gatehouse")
b.box("Plank", (-W - .25, -L - .7, -.1), (W + .25, L + .7, .02))
for k in range(26):
    y = -L - .48 + k * .232
    b.box("Wood", (-W, y, .02), (W, y + .015, .026))
for y in (-L, 0, L):
    for s in (1, -1):
        b.post("Wood", s * (W + .12), y, 0, H + .25, .15)
        b.box("Iron", (s * (W + .12) - .17, y - .17, 0), (s * (W + .12) + .17, y + .17, .14), .02)
    b.box("Wood", (-W - .75, y - .13, H), (W + .75, y + .13, H + .24))
# The long beams, and the walls under them.
for s in (1, -1):
    x = s * (W + .12)
    b.box("Wood", (x - .1, -L - .9, H + .24), (x + .1, L + .9, H + .44))
    b.box("Plaster", (x - .04, -L, 1.15), (x + .04, L, H))
    b.box("Plank", (x - .06, -L, 0), (x + .06, L, 1.1))
    b.box("Wood", (x - .08, -L, 1.1), (x + .08, L, 1.2))
    for k in range(20):
        y = -L + .12 + k * .25
        b.box("Wood", (x - .075, y, .0), (x + .075, y + .03, 1.1))
b.box("Wood", (-W - .1, -L, H + .05), (W + .1, L, H + .1))
# Wings either side for the doors to go behind.
for e in (-1, 1):
    y = e * (L + .02)
    for s in (1, -1):
        x0, x1 = sorted((s * (W + .25), s * (W + 1.75)))
        b.box("Plaster", (x0, y - .05 + e * .38, 1.0), (x1, y + .05 + e * .38, 2.4))
        b.box("Plank", (x0, y - .07 + e * .38, 0), (x1, y + .07 + e * .38, 1.0))
        b.box("Wood", (x0, y - .09 + e * .38, .98), (x1, y + .09 + e * .38, 1.08))
        b.box("Wood", (x0 - .05, y - .12 + e * .38, 2.4), (x1 + .05, y + .12 + e * .38, 2.52))
        b.post("Wood", s * (W + 1.8), y + e * .38, 0, 2.6, .11)
        # Its own little roof.
        for q in (1, -1):
            b.sheet("Tile", [[(x0 - .1 + (x1 - x0 + .2) * k / 24, y + e * .38 + q * o, z + .018 * cos(k * pi)) for k in range(25)] for o, z in ((.36, 2.5), (.2, 2.62), (.03, 2.8))])
# The roof: two curved slopes, tiled.
N = 72
X = W + 1.5
for s in (1, -1):
    rows = []
    for j in range(13):
        t = j / 12
        y = s * (3.85 * (1 - t))
        z = H + .22 + 1.75 * (t ** 1.45)
        row = []
        for k in range(N + 1):
            x = -X + 2 * X * k / N
            lift = .22 * abs(x / X) ** 3
            row.append((x, y, z + lift + .035 * cos(k * pi)))
        rows.append(row)
    b.sheet("Tile", rows)
    b.sheet("Wood", [[(x, y, z - .12) for x, y, z in (rows[0][0], rows[0][-1])], [(x, y, z - .12) for x, y, z in (rows[-1][0], rows[-1][-1])]])
    for k in range(25):
        x = -X + .12 + (2 * X - .24) * k / 24
        b.box("Wood", (x - .035, min(s * 2.2, s * 3.75), H + .16), (x + .035, max(s * 2.2, s * 3.75), H + .24))
b.box("Tile", (-X - .05, -.16, H + 1.95), (X + .05, .16, H + 2.2))
for s in (1, -1):
    b.box("Tile", (s * X - .16, -.24, H + 2.0), (s * X + .16, .24, H + 2.5), .05)
    # The gable ends.
    b.sheet("Plaster", [[(s * (W + .6), -2.3, H + .24), (s * (W + .6), 2.3, H + .24)], [(s * (W + .6), -.05, H + 1.75), (s * (W + .6), .05, H + 1.75)]])
# A lantern.
b.post("Paper", 0, 0, 2.05, 2.45, .16)
b.box("Wood", (-.18, -.18, 2.45), (.18, .18, 2.5))
b.box("Wood", (-.18, -.18, 2.0), (.18, .18, 2.05))
b.box("Iron", (-.01, -.01, 2.5), (.01, .01, 2.82))
parts = [b.done()]
for end, e in (("front", -1), ("back", 1)):
    for nm, s in (("l", -1), ("r", 1)):
        d = Build("%s_%s" % (end, nm))
        x0, x1 = sorted((0.004 * s, s * W))
        d.box("Plank", (x0, -.035, .03), (x1, .035, H))
        for z in (.03, .85, 1.75, H - .16):
            d.box("Wood", (x0, -.06, z), (x1, .06, z + .14))
        for x in (x0, x1 - .13):
            d.box("Wood", (x, -.065, .03), (x + .13, .065, H))
        for k in range(1, 6):
            x = x0 + (x1 - x0) * k / 6
            d.box("Wood", (x - .012, -.045, .03), (x + .012, .045, H))
        for z in (.92, 1.82):
            for k in range(6):
                x = x0 + .13 + (x1 - x0 - .26) * k / 5
                d.box("Iron", (x - .03, -.085, z - .03), (x + .03, .085, z + .03), .012)
        d.box("Iron", (s * .1 - .03, -.1, 1.2), (s * .1 + .03, .1, 1.5))
        parts.append(d.done((0, e * (L + .24), 0)))
for o in parts:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "gate.glb"), export_format="GLB", use_selection=True, export_animations=False, export_yup=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "gate.blend"))
print("DONE", sum(len(o.data.polygons) for o in parts))

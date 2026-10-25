# Staunton chess pieces for Chesswiz, built in Blender (5.0) headless.
#
#   blender -b --factory-startup --python tools/blender-pieces/pieces.py -- [options]
#
# Options (all optional):
#   --header PATH     write the GL mesh header (src/tk/gl_piece_data.h)
#   --sprites DIR     render the 12 sprite PNGs (img/pieces_3d)
#   --preview DIR     render lineup.png and knight-closeup.png
#   --blend PATH      save the scene as a .blend file
#   --samples N       Cycles samples (default 128)
#
# Conventions match the original data: Z up, base centre at the origin,
# one board square = 1 unit, knight muzzle toward -Y (tk_glboard.cpp turns
# the knights toward the opponent).
import bpy
import bmesh
import math
import os
import sys

import numpy as np
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import knight_sdf  # noqa: E402

SEG = 48            # lathe segments
SHARP = math.radians(38)

# ------------------------------------------------------------------ profiles


class Profile:
    """(r, z) outline from the axis at the bottom to the axis at the top."""

    def __init__(self, r, z):
        self.p = [(r, z)]

    @property
    def cur(self):
        return self.p[-1]

    def L(self, r, z):
        self.p.append((r, z))
        return self

    def A(self, r, z, s, n=None):
        """Arc to (r, z); s = sagitta, positive bulges away from the axis."""
        r0, z0 = self.cur
        mx, mz = (r0 + r) / 2, (z0 + z) / 2
        dx, dz = r - r0, z - z0
        ch = math.hypot(dx, dz)
        nx, nz = dz / ch, -dx / ch           # right-hand normal
        if nx < 0 or (abs(nx) < 1e-9 and nz < 0):
            nx, nz = -nx, -nz
        if abs(s) < 1e-9:
            return self.L(r, z)
        px, pz = mx + nx * s, mz + nz * s     # point on the arc
        # circle through the three points
        ax, az, bx, bz, cx, cz = r0, z0, px, pz, r, z
        d = 2 * (ax * (bz - cz) + bx * (cz - az) + cx * (az - bz))
        ux = ((ax * ax + az * az) * (bz - cz) + (bx * bx + bz * bz) * (cz - az) + (cx * cx + cz * cz) * (az - bz)) / d
        uz = ((ax * ax + az * az) * (cx - bx) + (bx * bx + bz * bz) * (ax - cx) + (cx * cx + cz * cz) * (bx - ax)) / d
        rad = math.hypot(ax - ux, az - uz)
        a0 = math.atan2(az - uz, ax - ux)
        am = math.atan2(pz - uz, px - ux)
        a1 = math.atan2(cz - uz, cx - ux)

        def norm(a):
            while a < a0 - math.pi:
                a += 2 * math.pi
            while a > a0 + math.pi:
                a -= 2 * math.pi
            return a
        am, a1 = norm(am), norm(a1)
        if not (min(a0, a1) <= am <= max(a0, a1)):
            a1 = a1 + (2 * math.pi if a1 < a0 else -2 * math.pi)
        sweep = abs(a1 - a0)
        if n is None:
            n = max(2, int(math.ceil(sweep * rad / 0.024)), int(math.ceil(sweep / math.radians(18))))
        for i in range(1, n + 1):
            a = a0 + (a1 - a0) * i / n
            self.p.append((ux + rad * math.cos(a), uz + rad * math.sin(a)))
        return self

    def ball(self, cz, rb, n=None):
        """Sphere of radius rb centred on the axis at cz, from the current
        point (which must lie on it or below it) up to the top pole."""
        r0, z0 = self.cur
        a0 = -math.acos(min(1.0, r0 / rb))
        if abs(cz + rb * math.sin(a0) - z0) > 1e-4:
            self.L(rb * math.cos(a0), cz + rb * math.sin(a0))
        n = n or max(6, int((math.pi / 2 - a0) / math.radians(10)))
        for i in range(1, n + 1):
            a = a0 + (math.pi / 2 - a0) * i / n
            self.p.append((max(0.0, rb * math.cos(a)), cz + rb * math.sin(a)))
        self.p[-1] = (0.0, self.p[-1][1])
        return self


def base(R, top_r):
    """Staunton foot: wide torus, cove, smaller torus; ends at (top_r, ~0.155)."""
    p = Profile(0.0, 0.0)
    p.L(R - 0.010, 0.0).A(R, 0.010, 0.003)
    p.L(R, 0.024)
    p.A(R - 0.016, 0.076, 0.017)
    p.L(R - 0.050, 0.083)
    p.A(R - 0.064, 0.108, -0.006)
    p.A(R - 0.085, 0.145, 0.010)
    p.L(top_r, 0.155)
    return p


def collar(p, z, r_out, h=0.034, r_in=None):
    """Flat ring with a rounded edge; enters and leaves at radius r_in."""
    r_in = r_in if r_in is not None else p.cur[0]
    p.L(r_out - 0.010, z)
    p.A(r_out - 0.010, z + h, 0.012)
    p.L(r_in, z + h + 0.004)
    return p


# ------------------------------------------------------------------ meshes


def lathe(name, pts, seg=SEG):
    bm = bmesh.new()
    rings = []
    for r, z in pts:
        if r < 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(2 * math.pi * i / seg),
                                        r * math.sin(2 * math.pi * i / seg), z)) for i in range(seg)])
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        for i in range(seg):
            j = (i + 1) % seg
            if len(a) == 1:
                bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1:
                bm.faces.new((a[i], b[0], a[j]))
            else:
                bm.faces.new((a[i], b[i], b[j], a[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def finish(ob, sharp=SHARP):
    me = ob.data
    for f in me.polygons:
        f.use_smooth = True
    me.set_sharp_from_angle(angle=sharp)
    return ob


def apply_mods(ob):
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def cutter_box(size, loc, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    c = bpy.context.active_object
    c.scale = size
    return c


def boolean(ob, cutters, op="DIFFERENCE"):
    for c in cutters:
        m = ob.modifiers.new("bool", "BOOLEAN")
        m.operation = op
        m.solver = "EXACT"
        m.object = c
        apply_mods(ob)
        bpy.data.objects.remove(c, do_unlink=True)
    return ob


def join(obs):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    return obs[0]


def sphere(loc, r, seg=16, rings=10):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=seg, ring_count=rings)
    o = bpy.context.active_object
    for f in o.data.polygons:
        f.use_smooth = True
    return o


# ------------------------------------------------------------------ pieces


def build_pawn():
    p = base(0.300, 0.205)
    p.A(0.098, 0.395, -0.050)
    collar(p, 0.398, 0.172, h=0.030, r_in=0.085)
    p.L(0.072, 0.440)
    p.ball(0.545, 0.118)
    return finish(lathe("pawn", p.p, seg=40))


def build_rook():
    p = base(0.345, 0.250)
    p.A(0.180, 0.480, -0.030)
    collar(p, 0.482, 0.215, h=0.030, r_in=0.180)
    p.A(0.258, 0.640, -0.022)
    p.L(0.262, 0.652).L(0.262, 0.775)
    p.A(0.252, 0.785, 0.004, n=2)
    p.L(0.205, 0.785).L(0.195, 0.775).L(0.185, 0.705)
    p.L(0.0, 0.705)
    ob = lathe("rook", p.p, seg=48)
    cutters = []
    for i in range(6):
        a = 2 * math.pi * (i + 0.5) / 6 + math.pi / 2
        c = cutter_box((0.16, 0.070, 0.20), (0.24 * math.cos(a), 0.24 * math.sin(a), 0.80),
                       (0, 0, a))
        cutters.append(c)
    boolean(ob, cutters)
    return finish(ob, math.radians(35))


def build_knight():
    p = base(0.345, 0.250)
    p.A(0.238, 0.205, -0.008)
    collar(p, 0.205, 0.262, h=0.030, r_in=0.236)
    p.L(0.0, 0.243)
    foot = finish(lathe("knight_foot", p.p, seg=48))

    verts, quads = knight_sdf.build(h=0.0032)
    me = bpy.data.meshes.new("knight_head")
    me.from_pydata([tuple(v) for v in verts], [], [tuple(q) for q in quads])
    me.update()
    head = bpy.data.objects.new("knight_head", me)
    bpy.context.collection.objects.link(head)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    sm = head.modifiers.new("smooth", "LAPLACIANSMOOTH")
    sm.lambda_factor = 0.4
    sm.iterations = 2
    sm.use_volume_preserve = True
    dec = head.modifiers.new("decimate", "DECIMATE")
    dec.ratio = KNIGHT_RATIO
    dec.use_collapse_triangulate = True
    apply_mods(head)
    for f in head.data.polygons:
        f.use_smooth = True
    ob = join([foot, head])
    ob.name = "knight"
    return ob


def build_bishop():
    p = base(0.330, 0.235)
    p.A(0.112, 0.545, -0.045)
    collar(p, 0.548, 0.185, h=0.032, r_in=0.150)
    collar(p, 0.588, 0.150, h=0.022, r_in=0.090)
    p.L(0.084, 0.625)
    # mitre: egg shape
    p.A(0.140, 0.715, 0.022)
    p.A(0.108, 0.840, 0.013)
    p.A(0.022, 0.935, 0.016)
    p.L(0.020, 0.940)
    p.ball(0.966, 0.031)
    ob = lathe("bishop", p.p, seg=48)
    # the slit: a slanted cut across the front of the mitre
    c = cutter_box((0.40, 0.30, 0.030), (0.0, -0.165, 0.805), (0, math.radians(-40), 0))
    boolean(ob, [c])
    return finish(ob, math.radians(40))


def build_queen():
    p = base(0.365, 0.245)
    p.A(0.122, 0.640, -0.055)
    collar(p, 0.642, 0.200, h=0.034, r_in=0.170)
    collar(p, 0.684, 0.165, h=0.024, r_in=0.110)
    p.L(0.105, 0.715)
    p.A(0.222, 0.930, -0.040)          # flaring crown
    p.L(0.238, 0.940)
    p.L(0.238, 0.985)
    p.L(0.205, 0.985)
    p.L(0.190, 0.960)
    p.A(0.050, 1.050, 0.030)          # dome inside the coronet
    p.L(0.030, 1.058)
    p.ball(1.085, 0.040)
    ob = lathe("queen", p.p, seg=48)
    cutters = []
    for i in range(8):
        a = 2 * math.pi * i / 8
        cutters.append(sphere((0.235 * math.cos(a), 0.235 * math.sin(a), 1.000), 0.050, 16, 10))
    boolean(ob, cutters)
    finish(ob, math.radians(40))
    pearls = []
    for i in range(8):
        a = 2 * math.pi * (i + 0.5) / 8
        pearls.append(sphere((0.226 * math.cos(a), 0.226 * math.sin(a), 0.995), 0.017, 12, 8))
    ob = join([ob] + pearls)
    return ob


def cross_mesh(cz, h, w, t, arm, flare):
    """Cross pattee in the XZ plane, centred on x=0, bottom at cz."""
    hw = w / 2
    fw = hw + flare
    top = cz + h
    mid = cz + h * 0.62
    pts = [(-hw, cz), (hw, cz), (hw, mid - hw - 0.012), (arm, mid - fw), (arm, mid + fw),
           (hw, mid + hw + 0.006), (fw, top), (-fw, top), (-hw, mid + hw + 0.006),
           (-arm, mid + fw), (-arm, mid - fw), (-hw, mid - hw - 0.012)]
    bm = bmesh.new()
    front = [bm.verts.new((x, -t / 2, z)) for x, z in pts]
    face = bm.faces.new(front)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    nv = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=nv, vec=(0, t, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("cross")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("cross", me)
    bpy.context.collection.objects.link(ob)
    bv = ob.modifiers.new("bevel", "BEVEL")
    bv.width = 0.008
    bv.segments = 3
    bv.limit_method = "ANGLE"
    apply_mods(ob)
    bmt = bmesh.new()
    bmt.from_mesh(ob.data)
    bmesh.ops.triangulate(bmt, faces=bmt.faces)
    bmt.to_mesh(ob.data)
    bmt.free()
    return finish(ob, math.radians(40))


def build_king():
    p = base(0.385, 0.255)
    p.A(0.132, 0.700, -0.060)
    collar(p, 0.702, 0.210, h=0.036, r_in=0.180)
    collar(p, 0.746, 0.175, h=0.026, r_in=0.118)
    p.L(0.112, 0.780)
    p.A(0.212, 0.975, -0.040)
    p.L(0.232, 0.985)
    p.A(0.232, 1.030, 0.012)
    p.L(0.198, 1.034)
    p.A(0.060, 1.110, 0.020)
    p.L(0.048, 1.114)
    p.L(0.066, 1.120).A(0.066, 1.140, 0.006, n=3).L(0.0, 1.142)
    body = finish(lathe("king", p.p, seg=48))
    cr = cross_mesh(1.130, 0.190, 0.050, 0.046, 0.072, 0.012)
    ob = join([body, cr])
    ob.name = "king"
    return ob


KNIGHT_RATIO = 0.047
BUILDERS = [("p", build_pawn), ("r", build_rook), ("n", build_knight),
            ("b", build_bishop), ("q", build_queen), ("k", build_king)]


# ------------------------------------------------------------------ export


def triangles(ob):
    """[(v0,n0,v1,n1,v2,n2)] with split (corner) normals."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    cn = me.corner_normals
    out = []
    mw = ob.matrix_world
    nm = mw.to_3x3().inverted().transposed()
    for lt in me.loop_triangles:
        tri = []
        for li in lt.loops:
            v = mw @ me.vertices[me.loops[li].vertex_index].co
            n = (nm @ cn[li].vector).normalized()
            tri.append((v, n))
        out.append(tri)
    ev.to_mesh_clear()
    return out


def fmt(x, prec=4):
    s = "%.*f" % (prec, x)
    if float(s) == 0.0:
        return "0"
    s = s.rstrip("0").rstrip(".")
    if s.startswith("0."):
        s = s[1:]
    elif s.startswith("-0."):
        s = "-" + s[2:]
    return s


def write_header(path, models):
    lines = ["// Auto-generated 3D piece mesh data from Blender models",
             "// Generated by tools/blender-pieces/pieces.py - do not edit by hand.",
             "// Per triangle: 3 x (x, y, z, nx, ny, nz); Z up, base centre at the",
             "// origin, one square = 1 unit, knight muzzle toward -Y.",
             "#ifndef _gl_piece_data_h", "#define _gl_piece_data_h", ""]
    for code, ob in models:
        tris = triangles(ob)
        lines.append("// --- Piece: %s ---" % code.upper())
        lines.append("static const int %s_num_tris = %d;" % (code, len(tris)))
        lines.append("static const float %s_tri_data[%d] = {" % (code, len(tris) * 18))
        for tri in tris:
            vals = []
            for v, n in tri:
                vals += [fmt(v.x), fmt(v.y), fmt(v.z), fmt(n.x, 3), fmt(n.y, 3), fmt(n.z, 3)]
            lines.append(",".join(vals) + ",")
        lines.append("};")
        lines.append("")
        print("header: %s %d tris" % (code, len(tris)))
    lines.append("#endif // _gl_piece_data_h")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


# ------------------------------------------------------------------ render


def wood_material(name, light):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    N = nt.nodes
    Lk = nt.links
    bsdf = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    mp = N.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1.0, 1.0, 0.25)
    Lk.new(tc.outputs["Object"], mp.inputs["Vector"])
    noise = N.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 3.0
    noise.inputs["Detail"].default_value = 4.0
    Lk.new(mp.outputs["Vector"], noise.inputs["Vector"])
    wave = N.new("ShaderNodeTexWave")
    wave.wave_type = "RINGS"
    wave.rings_direction = "Z"
    wave.inputs["Scale"].default_value = 9.0
    wave.inputs["Distortion"].default_value = 3.0
    wave.inputs["Detail"].default_value = 2.0
    Lk.new(mp.outputs["Vector"], wave.inputs["Vector"])
    ramp = N.new("ShaderNodeValToRGB")
    if light:
        c0, c1 = (0.80, 0.62, 0.40, 1), (0.93, 0.80, 0.60, 1)
    else:
        c0, c1 = (0.009, 0.006, 0.0045, 1), (0.030, 0.020, 0.014, 1)
    ramp.color_ramp.elements[0].color = c0
    ramp.color_ramp.elements[1].color = c1
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[1].position = 0.85
    mix = N.new("ShaderNodeMath")
    mix.operation = "MULTIPLY_ADD"
    mix.inputs[1].default_value = 0.35
    Lk.new(wave.outputs["Fac"], mix.inputs[0])
    Lk.new(noise.outputs["Fac"], mix.inputs[2])
    Lk.new(mix.outputs[0], ramp.inputs["Fac"])
    Lk.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.38 if light else 0.30
    bsdf.inputs["Coat Weight"].default_value = 0.35 if light else 0.55
    bsdf.inputs["Coat Roughness"].default_value = 0.12
    return m


def setup_scene(samples):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.35, 0.36, 0.40, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.55

    def area(loc, energy, size, color=(1, 1, 1)):
        bpy.ops.object.light_add(type="AREA", location=loc)
        L = bpy.context.active_object
        L.data.energy = energy
        L.data.size = size
        L.data.color = color
        d = Vector((0, 0, 0.55)) - Vector(loc)
        L.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        return L
    area((2.4, -2.6, 3.4), 520, 2.2, (1.0, 0.96, 0.9))     # key
    area((-3.0, -1.6, 1.8), 160, 3.0, (0.9, 0.94, 1.0))    # fill
    area((-0.8, 3.0, 2.6), 300, 1.5)                        # rim
    return sc


def look_at(cam, target):
    d = Vector(target) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def render_sprites(models, out_dir, samples):
    sc = bpy.context.scene
    sc.render.resolution_x = sc.render.resolution_y = 256
    sc.render.resolution_percentage = 100
    sc.cycles.samples = samples
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    # same viewpoint as the original sprites, framed so the king's cross
    # fits; the foot of every piece touches the bottom edge (anchor s)
    cam.location = (0, -2.1, 1.4)
    look_at(cam, (0, 0, 0.625))
    sc.camera = cam
    mats = {"w": wood_material("white", True), "b": wood_material("black", False)}
    os.makedirs(out_dir, exist_ok=True)
    for _, ob in models:
        ob.hide_render = True
    for code, ob in models:
        ob.hide_render = False
        for col in "wb":
            ob.data.materials.clear()
            ob.data.materials.append(mats[col])
            if code == "n":
                # the sprite shows the knight in three-quarter profile,
                # looking toward the opponent as on the GL board
                ob.rotation_euler = (0, 0, math.radians(-75 if col == "w" else 75))
            sc.render.filepath = os.path.join(out_dir, col + code + ".png")
            bpy.ops.render.render(write_still=True)
        ob.rotation_euler = (0, 0, 0)
        ob.hide_render = True
    for _, ob in models:
        ob.hide_render = False


def render_previews(models, out_dir, samples):
    sc = bpy.context.scene
    os.makedirs(out_dir, exist_ok=True)
    mats = {"w": wood_material("white_p", True), "b": wood_material("black_p", False)}
    # a plain floor for contact shadows
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
    floor = bpy.context.active_object
    fm = bpy.data.materials.new("floor")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.30, 0.30, 0.32, 1)
    fm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.6
    floor.data.materials.append(fm)
    sc.render.film_transparent = False
    order = ["r", "n", "b", "q", "k", "p"]
    byc = dict(models)
    copies = []
    for row, col in enumerate("wb"):
        for i, code in enumerate(order):
            if code not in byc:
                continue
            src = byc[code]
            ob = src.copy()
            ob.data = src.data.copy()
            ob.data.materials.clear()
            ob.data.materials.append(mats[col])
            ob.location = ((i - 2.5) * 0.95, row * 1.1, 0)
            if code == "n":
                ob.rotation_euler = (0, 0, math.radians(-90 if col == "w" else 90))
            bpy.context.collection.objects.link(ob)
            copies.append(ob)
    for _, ob in models:
        ob.hide_render = True
    cam_data = bpy.data.cameras.new("pcam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("pcam", cam_data)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam
    sc.cycles.samples = samples
    sc.render.resolution_x, sc.render.resolution_y = 1800, 900
    cam.location = (0.0, -7.4, 2.9)
    look_at(cam, (0, 0.55, 0.45))
    sc.render.filepath = os.path.join(out_dir, "lineup.png")
    bpy.ops.render.render(write_still=True)
    for o in copies:
        o.hide_render = True
    # knight close-ups: profile and three-quarter
    if "n" not in byc:
        return
    kn = byc["n"]
    kn.hide_render = False
    kn.data.materials.clear()
    kn.data.materials.append(mats["w"])
    sc.render.resolution_x, sc.render.resolution_y = 1000, 1000
    cam_data.lens = 85
    for name, ang, loc in (("knight-closeup", -90, (0.0, -2.9, 1.15)),
                           ("knight-34", -55, (0.0, -2.9, 1.25)),
                           ("knight-black", 125, (0.0, -2.9, 1.25))):
        kn.rotation_euler = (0, 0, math.radians(ang))
        if name == "knight-black":
            kn.data.materials.clear()
            kn.data.materials.append(mats["b"])
        cam.location = loc
        look_at(cam, (0, 0, 0.47))
        sc.render.filepath = os.path.join(out_dir, name + ".png")
        bpy.ops.render.render(write_still=True)
    kn.rotation_euler = (0, 0, 0)
    bpy.data.objects.remove(floor, do_unlink=True)
    for o in copies:
        bpy.data.objects.remove(o, do_unlink=True)
    sc.render.film_transparent = True


# ------------------------------------------------------------------ main


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {}
    i = 0
    while i < len(argv):
        opts[argv[i].lstrip("-")] = argv[i + 1]
        i += 2
    samples = int(opts.get("samples", 128))
    only = opts.get("only")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup_scene(samples)
    models = []
    for code, fn in BUILDERS:
        if only and code not in only:
            continue
        ob = fn()
        models.append((code, ob))
        print("built %s: %d tris" % (code, sum(len(p.vertices) - 2 for p in ob.data.polygons)))
    if "header" in opts:
        write_header(opts["header"], models)
    if "blend" in opts:
        bpy.ops.wm.save_as_mainfile(filepath=opts["blend"])
    if "preview" in opts:
        render_previews(models, opts["preview"], samples)
    if "sprites" in opts:
        render_sprites(models, opts["sprites"], samples)


main()

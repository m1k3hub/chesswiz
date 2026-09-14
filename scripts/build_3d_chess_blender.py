import bpy
import bmesh
import math
import os
import sys
from PIL import Image

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def create_wood_material(name, base_color, roughness=0.25):
    mat = bpy.data.materials.new(name=name)
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    
    node_out = nodes.new(type="ShaderNodeOutputMaterial")
    node_principled = nodes.new(type="ShaderNodeBsdfPrincipled")
    node_principled.inputs["Base Color"].default_value = base_color
    node_principled.inputs["Roughness"].default_value = roughness
    links.new(node_principled.outputs["BSDF"], node_out.inputs["Surface"])
    return mat

def lathe_profile(name, profile_points, segments=48):
    bm = bmesh.new()
    prev_ring = None
    
    for r, z in profile_points:
        ring = []
        for i in range(segments):
            angle = (2.0 * math.pi * i) / segments
            x = r * math.cos(angle)
            y = r * math.sin(angle)
            v = bm.verts.new((x, y, z))
            ring.append(v)
        
        if prev_ring is not None:
            for i in range(segments):
                i_next = (i + 1) % segments
                bm.faces.new((prev_ring[i], prev_ring[i_next], ring[i_next], ring[i]))
        prev_ring = ring

    if profile_points[0][0] > 0.001:
        bottom_center = bm.verts.new((0, 0, profile_points[0][1]))
        first_ring = bm.verts[:segments]
        for i in range(segments):
            i_next = (i + 1) % segments
            bm.faces.new((bottom_center, first_ring[i_next], first_ring[i]))

    if profile_points[-1][0] > 0.001:
        top_center = bm.verts.new((0, 0, profile_points[-1][1]))
        last_ring = prev_ring
        for i in range(segments):
            i_next = (i + 1) % segments
            bm.faces.new((top_center, last_ring[i], last_ring[i_next]))

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    
    for poly in mesh.polygons:
        poly.use_smooth = True
        
    return obj

def build_pawn():
    pts = [
        (0.36, 0.00), (0.36, 0.05), (0.33, 0.08), (0.28, 0.12), (0.30, 0.15),
        (0.25, 0.18), (0.17, 0.35), (0.14, 0.50), (0.16, 0.55), (0.22, 0.58),
        (0.18, 0.62), (0.13, 0.65), (0.14, 0.67), (0.22, 0.76), (0.22, 0.84),
        (0.16, 0.92), (0.00, 0.96)
    ]
    return lathe_profile("Pawn", pts)

def build_rook():
    pts = [
        (0.38, 0.00), (0.38, 0.06), (0.35, 0.10), (0.31, 0.14), (0.33, 0.17),
        (0.26, 0.22), (0.23, 0.55), (0.25, 0.68), (0.32, 0.74), (0.33, 0.92),
        (0.28, 0.92), (0.25, 0.82), (0.00, 0.82)
    ]
    rook = lathe_profile("Rook", pts)
    for angle in (0, math.pi/2, math.pi, 3*math.pi/2):
        bpy.ops.mesh.primitive_cube_add(size=0.12, location=(0.31*math.cos(angle), 0.31*math.sin(angle), 0.90))
        cube = bpy.context.active_object
        mod = rook.modifiers.new(name="Crenel", type="BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = cube
        bpy.context.view_layer.objects.active = rook
        bpy.ops.object.modifier_apply(modifier="Crenel")
        bpy.data.objects.remove(cube, do_unlink=True)
    return rook

def build_knight():
    pts = [
        (0.38, 0.00), (0.38, 0.06), (0.34, 0.10), (0.30, 0.14), (0.32, 0.17),
        (0.25, 0.22), (0.22, 0.32), (0.00, 0.32)
    ]
    base = lathe_profile("KnightBase", pts)
    
    bpy.ops.mesh.primitive_cube_add(size=0.35, location=(0.0, -0.04, 0.55))
    head = bpy.context.active_object
    head.scale = (0.7, 1.2, 1.4)
    bpy.ops.object.transform_apply(scale=True)
    
    bpy.ops.mesh.primitive_cube_add(size=0.20, location=(0.0, -0.22, 0.50))
    muzzle = bpy.context.active_object
    muzzle.scale = (0.6, 1.0, 0.7)
    bpy.ops.object.transform_apply(scale=True)
    
    bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.45, location=(0.0, 0.10, 0.60))
    mane = bpy.context.active_object
    mane.rotation_euler = (math.radians(-25), 0, 0)
    
    bpy.ops.object.select_all(action='DESELECT')
    for obj in (head, muzzle, mane, base):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = base
    bpy.ops.object.join()
    base.name = "Knight"
    
    mod = base.modifiers.new(name="Subsurf", type="SUBSURF")
    mod.levels = 1
    mod.render_levels = 1
    bpy.ops.object.modifier_apply(modifier="Subsurf")
    for poly in base.data.polygons:
        poly.use_smooth = True
    return base

def build_bishop():
    pts = [
        (0.37, 0.00), (0.37, 0.06), (0.34, 0.10), (0.29, 0.14), (0.31, 0.17),
        (0.24, 0.22), (0.16, 0.55), (0.19, 0.65), (0.24, 0.75), (0.23, 0.88),
        (0.12, 0.98), (0.04, 1.02), (0.00, 1.02)
    ]
    bishop = lathe_profile("Bishop", pts)
    bpy.ops.mesh.primitive_cube_add(size=0.15, location=(0.14, 0, 0.92))
    cutter = bpy.context.active_object
    cutter.rotation_euler = (0, math.radians(35), 0)
    cutter.scale = (0.4, 0.15, 1.0)
    mod = bishop.modifiers.new(name="Cleft", type="BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    bpy.context.view_layer.objects.active = bishop
    bpy.ops.object.modifier_apply(modifier="Cleft")
    bpy.data.objects.remove(cutter, do_unlink=True)
    
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06, location=(0, 0, 1.05))
    ball = bpy.context.active_object
    ball.select_set(True)
    bishop.select_set(True)
    bpy.context.view_layer.objects.active = bishop
    bpy.ops.object.join()
    return bishop

def build_queen():
    pts = [
        (0.39, 0.00), (0.39, 0.06), (0.35, 0.10), (0.30, 0.14), (0.32, 0.17),
        (0.24, 0.22), (0.17, 0.65), (0.20, 0.78), (0.28, 0.96), (0.26, 1.04),
        (0.18, 1.08), (0.00, 1.08)
    ]
    queen = lathe_profile("Queen", pts)
    for i in range(8):
        ang = (2.0 * math.pi * i) / 8
        qx = 0.25 * math.cos(ang)
        qy = 0.25 * math.sin(ang)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.045, location=(qx, qy, 1.08))
        pearl = bpy.context.active_object
        pearl.select_set(True)
        queen.select_set(True)
        bpy.context.view_layer.objects.active = queen
        bpy.ops.object.join()
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.065, location=(0, 0, 1.12))
    top = bpy.context.active_object
    top.select_set(True)
    queen.select_set(True)
    bpy.context.view_layer.objects.active = queen
    bpy.ops.object.join()
    return queen

def build_king():
    pts = [
        (0.40, 0.00), (0.40, 0.06), (0.36, 0.10), (0.31, 0.14), (0.33, 0.17),
        (0.25, 0.22), (0.18, 0.70), (0.22, 0.85), (0.28, 1.05), (0.22, 1.14),
        (0.00, 1.14)
    ]
    king = lathe_profile("King", pts)
    
    bpy.ops.mesh.primitive_cube_add(size=0.10, location=(0, 0, 1.25))
    vert = bpy.context.active_object
    vert.scale = (0.4, 0.4, 1.8)
    bpy.ops.mesh.primitive_cube_add(size=0.10, location=(0, 0, 1.28))
    horiz = bpy.context.active_object
    horiz.scale = (1.4, 0.4, 0.4)
    
    for part in (vert, horiz):
        part.select_set(True)
    king.select_set(True)
    bpy.context.view_layer.objects.active = king
    bpy.ops.object.join()
    return king

def render_all_assets():
    clear_scene()
    
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.film_transparent = True
    scene.render.resolution_x = 256
    scene.render.resolution_y = 256
    scene.render.resolution_percentage = 100
    
    # 3-point lighting
    bpy.ops.object.light_add(type='SUN', location=(3, -3, 6))
    sun1 = bpy.context.active_object
    sun1.data.energy = 3.5
    sun1.rotation_euler = (math.radians(45), math.radians(15), math.radians(-35))
    
    bpy.ops.object.light_add(type='SUN', location=(-3, -2, 4))
    sun2 = bpy.context.active_object
    sun2.data.energy = 1.8
    sun2.rotation_euler = (math.radians(35), math.radians(-30), math.radians(45))
    
    # Target empty for camera
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, 0, 0.55))
    target = bpy.context.active_object
    
    # Camera
    bpy.ops.object.camera_add(location=(0, -2.1, 1.4))
    cam = bpy.context.active_object
    scene.camera = cam
    
    tt = cam.constraints.new(type="TRACK_TO")
    tt.target = target
    tt.track_axis = "TRACK_NEGATIVE_Z"
    tt.up_axis = "UP_Y"
    cam.data.lens = 65
    
    mat_white = create_wood_material("WhiteWood", (0.92, 0.82, 0.68, 1.0), roughness=0.22)
    mat_black = create_wood_material("BlackWood", (0.12, 0.08, 0.05, 1.0), roughness=0.18)
    
    piece_builders = {
        'p': build_pawn,
        'r': build_rook,
        'n': build_knight,
        'b': build_bishop,
        'q': build_queen,
        'k': build_king,
    }
    
    out_dir = "/home/michael-g-thomas/src/chess/scidb-code.codex/img/pieces_3d"
    os.makedirs(out_dir, exist_ok=True)
    
    master_objects = {}
    for pcode, builder in piece_builders.items():
        obj = builder()
        obj.hide_render = True
        master_objects[pcode] = obj
        
    for pcode, obj in master_objects.items():
        obj.hide_render = False
        
        for color_char, mat in (('w', mat_white), ('b', mat_black)):
            obj.data.materials.clear()
            obj.data.materials.append(mat)
            
            if pcode == 'n':
                obj.rotation_euler = (0, 0, math.radians(-75) if color_char == 'w' else math.radians(105))
            else:
                obj.rotation_euler = (0, 0, 0)
                
            fname = f"{color_char}{pcode}.png"
            target_path = os.path.join(out_dir, fname)
            scene.render.filepath = target_path
            print(f"Rendering Blender 3D piece: {fname}...")
            bpy.ops.render.render(write_still=True)
            
            # Clean PNG with PIL so Tk photo loader reads without error
            raw_im = Image.open(target_path)
            clean_im = Image.new("RGBA", raw_im.size)
            clean_im.paste(raw_im, (0, 0))
            clean_im.save(target_path, "PNG")
            
        obj.hide_render = True

    print("All photorealistic 3D pieces modeled, rendered, and saved successfully!")

if __name__ == "__main__":
    render_all_assets()

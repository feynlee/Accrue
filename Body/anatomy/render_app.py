"""Render what the app's 3D demo shows, without a Mac: the app's Body.usdz posed from
AccrueKit's own frames, its equipment and its camera, as a contact sheet.

    BODY_DUMP=/tmp/dump.json swift test --filter dumpForRenderer      (in AccrueKit)
    python render_app.py Body.usdz dump.json out_dir

The dump holds, per exercise, Body3D's per-joint turns and root, the PropPlan pieces and
the camera framing. Each exercise is drawn at two moments of its loop, side by side.

To stress the model itself, dump rom-poses.json instead (every joint at the ends of its range)
with BODY_DUMP_POSES=rom-poses.json and render it the same way. VIEWS picks the cameras, as
"name:yaw:pitch[:bone:radius]" in degrees ("focus" for bone:radius uses each pose's own
close-up), FRAMES the frames, LOOK=bones or LOOK=skin what is drawn.

FINE=1 draws the look itself as the app does (lit, the grain on the working muscles, the
clear skin really clear); it takes seconds per picture where the plain sheets take none.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

USDZ, DUMP, OUT = sys.argv[-3], sys.argv[-2], sys.argv[-1]
SIZE = int(os.environ.get("SIZE", "260"))
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=USDZ)
scene = bpy.context.scene
arm = next(o for o in scene.objects if o.type == "ARMATURE")
meshes = {o.data.materials[0].name if o.data.materials else o.name: o for o in scene.objects if o.type == "MESH"}
REST = {b.name: b.matrix_local.copy() for b in arm.data.bones}

scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "OBJECT"
scene.display.shading.show_shadows = False
scene.display.shading.show_specular_highlight = False
scene.display.shading.show_cavity = True
scene.display.shading.cavity_type = "BOTH"
scene.render.resolution_x = scene.render.resolution_y = SIZE
scene.render.film_transparent = False
world = bpy.data.worlds.new("w")
scene.world = world
scene.display.shading.background_type = "VIEWPORT"
scene.display.shading.background_color = (0.95, 0.953, 0.96)

INK = {"muscle": (0.64, 0.66, 0.70), "main": (0.78, 0.96, 0.2), "helps": (0.55, 0.71, 0.12),
       "skin": (0.85, 0.84, 0.82), "top": (0.78, 0.96, 0.2), "shorts": (0.16, 0.18, 0.21), "shoes": (0.19, 0.2, 0.23),
       "metal": (0.55, 0.57, 0.6), "dark": (0.18, 0.19, 0.21), "pad": (0.12, 0.13, 0.15), "plate": (0.1, 0.1, 0.11),
       "rubber": (0.25, 0.26, 0.28), "cable": (0.1, 0.1, 0.1), "accent": (0.33, 0.45, 0.85), "wood": (0.72, 0.56, 0.38),
       "floor": (0.79, 0.8, 0.83)}

# The grain of a working muscle lies next to the model.
HERE = os.path.dirname(os.path.abspath(USDZ))
FINE = bool(os.environ.get("FINE"))
INK.update({"seam": tuple(float(os.environ.get("SEAM", 0.54)) * k for k in (0.97, 1.0, 1.06)), "bone": tuple(float(os.environ.get("BONE", 0.8)) * k for k in (1.03, 1.0, 0.94))})
if FINE:
    scene.render.engine = "CYCLES"
    scene.cycles.samples = int(os.environ.get("SAMPLES", 48))
    scene.cycles.use_denoising = bool(os.environ.get("DENOISE"))
    scene.cycles.transparent_max_bounces = 16
    scene.view_settings.view_transform = "Standard"
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.89, 0.895, 0.91, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = float(os.environ.get("AMBIENT", 0.55))
    # the app's three lights (Body3DView.swift), app axes (x, y, z) -> Blender (x, -z, y)
    for power, at in ((2.6, (-1.5, 3, 2)), (1.1, (2, 1, -1.5)), (0.5, (0.5, -2, 1))):
        sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
        sun.data.energy, sun.data.angle = power * float(os.environ.get("SUN", 1.0)), math.radians(8)
        sun.rotation_mode = "QUATERNION"
        sun.rotation_quaternion = Vector((at[0], -at[2], at[1])).to_track_quat("Z", "Y")
        scene.collection.objects.link(sun)
    GRAIN = bpy.data.images.load(os.path.join(HERE, "muscle-fibres.png"))
    INKS = {}


def lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def ink(o, color, alpha=1.0, grain=0.0, rough=0.6, glow=0.0):
    """Colour one part: its object colour for the plain sheets, a material for the fine look."""
    o.color = (*color, alpha)
    if not FINE:
        return
    key = (tuple(color), alpha, grain, rough, glow)
    if key not in INKS:
        m = bpy.data.materials.new("ink")
        m.use_nodes = True
        nt = m.node_tree
        b = nt.nodes["Principled BSDF"]
        b.inputs["Roughness"].default_value = rough
        b.inputs["Alpha"].default_value = alpha
        b.inputs["Base Color"].default_value = (*lin(color), 1)
        if glow:
            b.inputs["Emission Color"].default_value = (*lin(color), 1)
            b.inputs["Emission Strength"].default_value = glow
        if grain:
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = GRAIN
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type, mix.blend_type = "RGBA", "MULTIPLY"
            mix.inputs[0].default_value = grain
            mix.inputs[6].default_value = (*lin(color), 1)
            nt.links.new(tex.outputs["Color"], mix.inputs[7])
            nt.links.new(mix.outputs[2], b.inputs["Base Color"])
            if glow:
                nt.links.new(mix.outputs[2], b.inputs["Emission Color"])
        INKS[key] = m
    o.visible_shadow = False  # the app's lights cast no shadows
    if not o.data.materials:
        o.data.materials.append(None)
    if o.data.users > 1:  # the equipment shares its shapes: the colour goes on the piece
        o.material_slots[0].link = "OBJECT"
    o.material_slots[0].material = INKS[key]


cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scene.collection.objects.link(cam)
scene.camera = cam
cam.data.sensor_fit = "VERTICAL"
cam.data.angle = math.radians(30)
floor = bpy.data.objects.new("floor", bpy.data.meshes.new("floor"))
props = []


def prim(shape):
    me = bpy.data.meshes.new(shape)
    import bmesh
    bm = bmesh.new()
    if shape == "box":
        bmesh.ops.create_cube(bm, size=1.0)
    elif shape == "cylinder":
        bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=0.5, radius2=0.5, depth=1.0)
    else:
        bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=0.5)
    bm.to_mesh(me)
    bm.free()
    return me


PRIMS = {s: prim(s) for s in ("box", "cylinder", "sphere")}
disc = bpy.data.objects.new("disc", PRIMS["cylinder"])
scene.collection.objects.link(disc)
ink(disc, INK["floor"], rough=1.0)


def pose(frame):
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        q = frame["local"].get(pb.name.replace("_", "."))
        pb.rotation_quaternion = Quaternion(q) if q else Quaternion()
        pb.location = (0, 0, 0)
    root = arm.pose.bones["pelvis"]
    R = REST["pelvis"].to_3x3()
    root.location = R.transposed() @ (Vector(frame["root"]) - REST["pelvis"].translation)


CLEAR = float(os.environ.get("CLEAR", 0.2))  # how solid the skin over the muscles is; 0 for none
SEAMS = int(os.environ.get("SEAMS", 1))        # the dark line between the muscle groups
GRAINS = {"main": float(os.environ.get("GRAIN", 1.0)), "helps": float(os.environ.get("GRAIN_HELPS", 1.0)), None: 0.0}
GLOW = float(os.environ.get("GLOW", 0.0))
LOOK = os.environ.get("LOOK", "")  # "bones": the skeleton alone; "skin": the dressed body


def paint(entry):
    skin = entry["model"] != "anatomy" or LOOK == "skin"
    part = lambda m: "m_" + m.replace("-", "_")
    main, helps = {part(m) for m in entry["primary"]}, {part(m) for m in entry.get("secondary") or []}
    for name, o in meshes.items():
        if name.startswith("skin_") and not skin and CLEAR:
            # the anatomy look: the muscles under a clear skin
            o.hide_render = False
            ink(o, INK["skin"], CLEAR, rough=0.35)
        elif name.startswith("skin_"):
            o.hide_render = not skin
            ink(o, INK[{"skin_body": "skin", "skin_top": "top", "skin_shorts": "shorts", "skin_shoes": "shoes"}[name]])
        elif name == "head":
            o.hide_render = skin
            ink(o, INK["skin"])
        elif name == "bones":
            # The muscles are one closed surface, so the skeleton is not drawn under them
            # (BONEC=1: drawn in orange, to check for bone coming through).
            o.hide_render = skin or not (os.environ.get("BONEC") or LOOK == "bones")
            ink(o, (0.95, 0.55, 0.2) if os.environ.get("BONEC") else INK["bone"])
        elif name == "suit_seams":
            o.hide_render = skin or LOOK == "bones" or not SEAMS
            ink(o, INK["seam"])
        else:
            o.hide_render = skin or LOOK == "bones"
            hot = "main" if name in main else "helps" if name in helps else None
            ink(o, INK[hot or "muscle"], grain=GRAINS[hot], rough=0.55, glow=GLOW if hot else 0.0)
            if os.environ.get("PARTC"):  # every group in a colour of its own, to check the map
                import colorsys, zlib
                ink(o, colorsys.hsv_to_rgb(zlib.crc32(name.encode()) % 360 / 360, 0.55, 0.9), grain=float(os.environ.get("PARTG", 0)))


def place_props(frame):
    for o in props:
        bpy.data.objects.remove(o)
    props.clear()
    for p in frame["props"]:
        o = bpy.data.objects.new("prop", PRIMS[p["shape"]])
        scene.collection.objects.link(o)
        o.location = p["center"]
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = Quaternion(p["q"])
        o.scale = p["size"]
        ink(o, INK[p["finish"]], rough=0.5)
        props.append(o)


def aim(entry, frame=None, view=None):
    fr = entry["framing"]
    c = Vector(fr["center"])
    yaw, pitch, radius = fr["yaw"], fr["pitch"], fr["radius"]
    if view:
        # "name:yaw:pitch[:bone:radius]" in degrees; yaw 0 looks at the front of a standing body,
        # -90 at its right side. A bone name centres the view on that joint (a close-up).
        parts = view.split(":")
        if len(parts) > 2:  # a bare name keeps the app's own framing
            yaw, pitch = math.radians(float(parts[1])), math.radians(float(parts[2]))
        if len(parts) > 3 and parts[3] == "focus" and frame and frame.get("focus"):  # the pose's own close-up
            parts[3:5] = frame["focus"].split(":")
        if len(parts) > 4 and frame and parts[3] in frame.get("heads", {}):
            c, radius = Vector(frame["heads"][parts[3]]), float(parts[4])
    # App axes (Y up) -> Blender: (x, y, z) -> (x, -z, y).
    d_app = Vector((math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch)))
    d = Vector((d_app.x, -d_app.z, d_app.y))
    fov = math.radians(30)
    dist = radius / math.sin(fov / 2)
    cam.location = c + d * dist
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (-d).to_track_quat("-Z", "Y")
    cam.data.clip_start = 0.02
    # Floor disc under the body, as the app draws it.
    fc = Vector(fr["center"])
    disc.location = (fc.x, fc.y, 0)
    reach = max(0.35, fr["radius"] / 0.42 / 2.2)
    disc.scale = (2 * reach, 2 * reach, 0.006)


entries = json.load(open(DUMP))
only = os.environ.get("ONLY")
views = [v for v in os.environ.get("VIEWS", "").split(",") if v] or [None]
FRAMES = [int(k) for k in os.environ.get("FRAMES", "").split(",") if k]  # only these frames of each entry
for e in entries:
    if only and e["family"] not in only.split(",") and e["id"] not in only.split(","):
        continue
    paint(e)
    for k, fr in enumerate(e["frames"]):
        if FRAMES and k not in FRAMES:
            continue
        pose(fr)
        place_props(fr)
        bpy.context.view_layer.update()
        for view in views:
            aim(e, fr, view)
            tag = "" if view is None else "__" + view.split(":")[0]
            p = os.path.join(OUT, f"{e['family']}__{e['id']}{tag}__{k}.png")
            scene.render.filepath = p
            bpy.ops.render.render(write_still=True)
    print("rendered", e["family"], e["name"], e["kinds"])

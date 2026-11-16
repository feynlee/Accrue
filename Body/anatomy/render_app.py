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
disc.color = (*INK["floor"], 1)


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
LOOK = os.environ.get("LOOK", "")  # "bones": the skeleton alone; "skin": the dressed body


def paint(entry):
    skin = entry["model"] != "anatomy" or LOOK == "skin"
    main = {"m_" + m.replace("-", "_") for m in entry["primary"]}
    for name, o in meshes.items():
        if name.startswith("skin_") and not skin and CLEAR:
            # the anatomy look: the muscles under a clear skin
            o.hide_render = False
            o.color = (*INK["skin"], CLEAR)
        elif name.startswith("skin_"):
            o.hide_render = not skin
            o.color = (*INK[{"skin_body": "skin", "skin_top": "top", "skin_shorts": "shorts", "skin_shoes": "shoes"}[name]], 1)
        elif name == "head":
            o.hide_render = skin
            o.color = (*INK["skin"], 1)
        elif name == "bones":
            # Under the muscles the skeleton is drawn too, as in the app, so a gap between two
            # muscles shows what is really there instead of the background.
            o.hide_render = skin
            o.color = (*INK["skin"], 1)
        else:
            o.hide_render = skin or LOOK == "bones"
            o.color = (*INK["main" if name in main else "muscle"], 1)


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
        o.color = (*INK[p["finish"]], 1)
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

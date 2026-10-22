"""Export Z-Anatomy (CC BY-SA 4.0, from BodyParts3D) muscles and bones to one GLB.

    python export_za.py Startup.blend out.glb

Keeps the superficial and intermediate muscles plus the skeleton, drops
fasciae, bursae, tendon sheaths and deep visceral muscles, and decimates
each mesh so the whole file stays small enough for a phone.
"""
import re
import sys

import bpy

SRC, OUT = sys.argv[-2], sys.argv[-1]
MUSCLE_RATIO = float(__import__("os").environ.get("MR", "0.2"))
BONE_RATIO = float(__import__("os").environ.get("BR", "0.25"))

DROP = re.compile(r"fascia|bursa|sheath|retinacul|intercostal|transversus abdominis|"
                  r"pharyn|palat|tongue|glossus|larynx|laryng|arytenoid|thyro|crico|vocal|"
                  r"rectus muscle\.|oblique muscle\.[lr]$|tarsus|palpebr|trochlea|tendinous ring|"
                  r"perine|sphincter|pelvic diaphragm|coccygeus|levator ani|ischiocavernosus|"
                  r"bulbospongiosus|cremaster|stapedius|tensor tympani|"
                  r"diaphragm|ossicle|malleus|incus|stapes|uvula", re.I)

bpy.ops.wm.open_mainfile(filepath=SRC)
scene = bpy.context.scene
for o in bpy.data.objects:
    if o.type == "MESH" and re.search(r"\bskin\b", o.name, re.I):
        print("SKIN?", o.name, len(o.data.vertices))


def pick(coll_name, min_verts=60):
    out = []
    for o in bpy.data.collections[coll_name].all_objects:
        if o.type != "MESH" or len(o.data.vertices) < min_verts:
            continue
        if re.search(r"\.[gjit]$", o.name) or DROP.search(o.name):
            continue
        out.append(o)
    return list(dict.fromkeys(out))


muscles = pick("4: Muscular system")
bones = pick("1: Skeletal system")
print("muscles", len(muscles), "bones", len(bones))

# Build a clean scene with world-space copies.
new = bpy.data.scenes.new("export")
coll = new.collection
mat_m = bpy.data.materials.new("muscle")
mat_b = bpy.data.materials.new("bone")
dg = bpy.context.evaluated_depsgraph_get()
total = {"muscle": 0, "bone": 0}
for kind, objs, ratio, mat in (("muscle", muscles, MUSCLE_RATIO, mat_m), ("bone", bones, BONE_RATIO, mat_b)):
    for o in objs:
        ev = o.evaluated_get(dg)
        me = bpy.data.meshes.new_from_object(ev)
        me.transform(o.matrix_world)
        if o.matrix_world.determinant() < 0:
            me.flip_normals()  # mirrored left-side parts
        me.materials.clear()
        me.materials.append(mat)
        ob = bpy.data.objects.new(o.name, me)
        ob["kind"] = kind
        coll.objects.link(ob)
        r = ratio if len(me.vertices) > 800 else min(1.0, ratio * 2)
        if r < 1.0:
            mod = ob.modifiers.new("dec", "DECIMATE")
            mod.ratio = r
        for p in me.polygons:
            p.use_smooth = True
bpy.context.window.scene = new
dg = bpy.context.evaluated_depsgraph_get()
for ob in coll.objects:
    total[ob["kind"]] += len(ob.evaluated_get(dg).data.vertices)
print("verts after decimate", total)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_active_scene=True, export_apply=True,
                          export_yup=True, export_extras=True, export_materials="PLACEHOLDER",
                          export_normals=True, export_texcoords=False, export_animations=False)

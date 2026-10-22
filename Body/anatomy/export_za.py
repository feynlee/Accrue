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

DROP = re.compile(r"(?<!thoracolumbar )fascia(?!e latae)|fasciae of|bursa|sheath|retinacul|"
                  r"internal intercostal|innermost intercostal|transversus abdominis|"
                  r"pharyn|palat|tongue|glossus|larynx|laryng|arytenoid|thyro|crico|vocal|"
                  r"^(lateral|medial|superior|inferior) rectus muscle|^(superior|inferior) oblique muscle|tarsus|palpebr|trochlea|tendinous ring|"
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
# Head: drop the face and scalp muscles; a smooth human head goes on instead.
HEAD_Z = float(__import__("os").environ.get("HEAD_Z", "1.47"))


def zrange(o):
    zs = [(o.matrix_world @ v.co).z for v in o.data.vertices]
    return min(zs), max(zs)


# Facial-expression and jaw muscles sit under the face skin; scalp, temple,
# ear and neck muscles stay visible.
FACE = re.compile(r"orbicularis|zygomaticus|levator labii|levator anguli|depressor|risorius|buccinator|"
                  r"mentalis|nasalis|procerus|corrugator|levator nasolabialis|masseter|pterygoid|"
                  r"digastric|mylohyoid|geniohyoid|stylohyoid|modiolus|incisivus", re.I)
muscles = [o for o in muscles if not FACE.search(o.name)]
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
# Human head from MakeHuman (CC0), scaled and placed over the Z-Anatomy skull.
sys.path.insert(0, __import__("os").path.join(__import__("os").path.dirname(__file__), "..", "pipeline"))
import numpy as np  # noqa: E402
import mhbody  # noqa: E402

skull = [o for o in bones if re.match(r"(Frontal|Parietal|Occipital|Temporal) bone|Mandible|Nasal bone|Maxilla", o.name)]
P = np.array([tuple(o.matrix_world @ v.co) for o in skull for v in o.data.vertices])
s_min, s_max = P.min(0), P.max(0)
body = mhbody.build()
W = body["world"]
B = body["bones"]
cut = B["neck01"]["head"][2] + 0.25 * (B["head"]["head"][2] - B["neck01"]["head"][2])
headv = W[W[:, 2] > B["head"]["head"][2] - 0.02]
mh_top = headv[:, 2].max()
front = headv[np.abs(headv[:, 0]) < 0.012]
mh_chin = W[(np.abs(W[:, 0]) < 0.012) & (W[:, 1] < front[:, 1].min() + 0.06) & (W[:, 2] > cut)][:, 2].min()
scale = ((s_max[2] + 0.007) - (s_min[2] - 0.012)) / (mh_top - mh_chin)
back_mh = headv[:, 1].max()
off = np.array([0.0, (s_max[1] + 0.007) - back_mh * scale, (s_max[2] + 0.007) - mh_top * scale])
print("head scale", scale, "offset", off)
obj_faces = []
verts_all = W * scale + off
_, _, bfaces, _, groups, _ = mhbody.load_obj()
# Keep only the face: in front of the ears, below the brows, above the jaw line.
V = verts_all
brow_z = float(__import__("os").environ.get("BROW_Z", "1.635"))
ear_y = float(__import__("os").environ.get("EAR_Y", "0.004"))
chin_z = s_min[2] - 0.02
for f in bfaces:
    p = V[f]
    face = (p[:, 2] > chin_z).all() and (p[:, 2] < brow_z).all() and (p[:, 1] < ear_y).all()
    ear = (np.abs(p[:, 0]) > 0.066).all() and (p[:, 2] > 1.555).all() and (p[:, 2] < 1.66).all() and (p[:, 1] < 0.045).all()
    if face or ear:
        obj_faces.append(f)
for k in ("helper-l-eye", "helper-r-eye"):
    obj_faces += mhbody.load_obj.helpers[k]
used = sorted({i for f in obj_faces for i in f})
remap = {v: k for k, v in enumerate(used)}
hm = bpy.data.meshes.new("head")
hm.from_pydata([tuple(verts_all[i]) for i in used], [], [[remap[i] for i in f] for f in obj_faces])
hm.materials.append(bpy.data.materials.new("skin"))
for p in hm.polygons:
    p.use_smooth = True
ho = bpy.data.objects.new("Head", hm)
ho["kind"] = "head"
coll.objects.link(ho)
sub = ho.modifiers.new("sub", "SUBSURF")
sub.levels = 1

bpy.context.window.scene = new
dg = bpy.context.evaluated_depsgraph_get()
for ob in coll.objects:
    if ob["kind"] in total:
        total[ob["kind"]] += len(ob.evaluated_get(dg).data.vertices)
print("verts after decimate", total)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_active_scene=True, export_apply=True,
                          export_yup=True, export_extras=True, export_materials="PLACEHOLDER",
                          export_normals=True, export_texcoords=False, export_animations=False)

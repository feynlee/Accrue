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
                  r"digastric|mylohyoid|geniohyoid|stylohyoid|modiolus|incisivus|"
                  r"frontalis|occipitalis|epicranial|temporoparietalis|temporalis|auricular", re.I)
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
# Fit per axis: height from the crown to the chin, width and depth from the cranium.
sz = ((s_max[2] + 0.007) - (s_min[2] - 0.012)) / (mh_top - mh_chin)
cran = [o for o in skull if re.match(r"(Frontal|Parietal|Occipital|Temporal) bone", o.name)]
C = np.array([tuple(o.matrix_world @ v.co) for o in cran for v in o.data.vertices])
c_min, c_max = C.min(0), C.max(0)
mhc = W[W[:, 2] > mh_top - 0.11]
soft = 0.006
sx = ((c_max[0] - c_min[0]) + 2 * soft) / (mhc[:, 0].max() - mhc[:, 0].min())
sy = ((c_max[1] - c_min[1]) + 2 * soft) / (mhc[:, 1].max() - mhc[:, 1].min())
scale = np.array([sx, sy, sz])
back_mh = mhc[:, 1].max()
off = np.array([0.0, (c_max[1] + soft) - back_mh * sy, (s_max[2] + 0.007) - mh_top * sz])
print("head scale", scale, "offset", off)
obj_faces = []
verts_all = W * scale + off
_, _, bfaces, _, groups, _ = mhbody.load_obj()
# Head skin: everything above the jaw line in front and the skull base behind.
V = verts_all
ear_y = float(__import__("os").environ.get("EAR_Y", "0.004"))
chin_z = s_min[2] - 0.02
occ = [o for o in skull if o.name.startswith("Occipital bone")]
skull_base = min((o.matrix_world @ v.co).z for o in occ for v in o.data.vertices) + 0.005
for f in bfaces:
    p = V[f]
    # Whole head, bald: the face down to the jaw, the back down to the skull base.
    face = (p[:, 2] > chin_z).all() and (p[:, 1] < ear_y).all()
    back = (p[:, 2] > skull_base).all()
    if face or back:
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
# MakeHuman's scalp sits tighter than this skull at the back: push it out a little.
grow = ho.modifiers.new("grow", "DISPLACE")
grow.strength = float(__import__("os").environ.get("HEAD_GROW", "0.003"))
grow.mid_level = 0.0

bpy.context.window.scene = new
dg = bpy.context.evaluated_depsgraph_get()
for ob in coll.objects:
    if ob["kind"] in total:
        total[ob["kind"]] += len(ob.evaluated_get(dg).data.vertices)
print("verts after decimate", total)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_active_scene=True, export_apply=True,
                          export_yup=True, export_extras=True, export_materials="PLACEHOLDER",
                          export_normals=True, export_texcoords=False, export_animations=False)

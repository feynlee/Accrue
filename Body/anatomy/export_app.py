"""The app's 3D body: the rigged Z-Anatomy model as one USD file, plus its skeleton as JSON.

    python export_app.py za.glb skin.npz body.usdc body-rig.json
    python pack_usdz.py body.usdc Body.usdz

za.glb is the static model from export_za.py and skin.npz the body surface from
export_skin.py (both Z-Anatomy, CC BY-SA 4.0). The file holds one armature and,
bound to it:

- one mesh per catalog muscle group, named "m_<group>" (m_chest, m_lats ...), so the
  app can light up the working muscles; muscles outside every group are "m_other";
- "bones", every skeletal mesh in one;
- "head", the bald head, hands and feet (MakeHuman, CC0) over the anatomy;
- "skin_body", "skin_top", "skin_shorts", "skin_shoes": the dressed body surface for
  cardio, hidden in the anatomy views.

Bones are renamed "femur.l" -> "femur_l" because USD names cannot hold dots.
body-rig.json lists every bone with its parent, head, tail and rest rotation
(Blender axes: x to the body's left, -y forward, z up), which is what AccrueKit's
Body3D poses.
"""
import json
import os
import re
import sys

os.environ["ZA_GLB"] = sys.argv[-4]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rigbase import *  # noqa: E402,F401,F403
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402
import skinmesh  # noqa: E402

SKIN, OUT, RIG_OUT = sys.argv[-3], sys.argv[-2], sys.argv[-1]

# ---------------------------------------------------------------- muscle groups
# Z-Anatomy muscle -> catalog muscle group (AccrueKit catalog.json "muscles"). First match wins.
GROUPS = [
    ("upper-chest", r"clavicular head of pectoralis major"),
    ("chest", r"sternocostal head of pectoralis major|abdominal part of pectoralis major"),
    ("pec-minor", r"pectoralis minor|subclavius"),
    ("front-delts", r"clavicular part of deltoid"),
    ("side-delts", r"acromial part of deltoid"),
    ("rear-delts", r"scapular spinal part of deltoid"),
    ("rotator-cuff", r"supraspinatus|infraspinatus|teres minor|subscapularis"),
    ("lats", r"latissimus dorsi|teres major"),
    # Z-Anatomy has the two names the wrong way round: its "ascending part" is the mesh from
    # the skull and neck to the collarbone (the upper fibres), its "descending part" the lower.
    ("upper-traps", r"\bascending part of trapezius"),
    ("mid-traps", r"transverse part of trapezius"),
    ("lower-traps", r"descending part of trapezius"),
    ("rhomboids", r"rhomboid"),
    ("levator-scapulae", r"levator scapulae"),
    ("serratus-anterior", r"serratus anterior"),
    ("neck-flexors", r"sternocleidomastoid|scalenus|longus capitis|longus colli|rectus (anterior|lateralis) capitis|"
                     r"platysma|omohyoid|sternohyoid"),
    ("neck-extensors", r"splenius|semispinalis colli|(spinalis|longissimus) (capitis|colli)|iliocostalis colli|"
                       r"multifidus colli|interspinales colli|rectus posterior|obliquus (inferior|superior) capitis"),
    ("biceps", r"biceps brachii|coracobrachialis"),
    ("brachioradialis", r"brachioradialis"),
    ("brachialis", r"brachialis"),
    ("triceps", r"triceps brachii|anconeus"),
    ("shins", r"tibialis anterior|extensor digitorum longus|extensor hallucis longus|fibularis tertius"),
    ("wrist-flexors", r"flexor carpi|palmaris longus|flexor digitorum (superficialis|profundus)|flexor pollicis longus|"
                      r"pronator"),
    ("wrist-extensors", r"extensor carpi|extensor digit|extensor indicis|extensor pollicis|abductor pollicis longus|"
                        r"supinator"),
    ("abs", r"rectus abdominis|pyramidalis|linea alba"),
    ("obliques", r"abdominal oblique"),
    ("lower-back", r"iliocostalis (lumborum|thoracis)|longissimus thoracis|spinalis thoracis|semispinalis thoracis|"
                   r"multifidus (lumborum|thoracis)|rotatores|interspinales (lumborum|thoracis)|intertransversarii|"
                   r"quadratus lumborum|thoracolumbar fascia"),
    ("breathing", r"intercostal|transversus thoracis|serratus posterior|levatores"),
    ("glutes", r"gluteus maximus"),
    ("glute-med", r"gluteus (medius|minimus)|tensor fasciae latae|iliotibial tract"),
    ("hip-rotators", r"piriformis|gemellus|obturator|quadratus femoris"),
    ("hip-flexors", r"iliacus|psoas|sartorius"),
    ("adductors", r"adductor|gracilis|pectineus"),
    ("quads", r"rectus femoris|vastus"),
    ("hamstrings", r"biceps femoris|semimembranosus|semitendinosus"),
    ("calves", r"gastrocnemius|plantaris|calcaneal tendon|popliteus"),
    ("soleus", r"soleus"),
    ("peroneals", r"fibularis (longus|brevis)"),
    ("foot", r"tibialis posterior|flexor digitorum longus|flexor hallucis longus"),
]


def group_of(name):
    n = re.sub(r"\.(l|r)$", "", name)
    for gid, rx in GROUPS:
        if re.search(rx, n, re.I):
            return gid
    return "other"


# ---------------------------------------------------------------- bind and merge
# Bones show only in the Glass view: half their triangles are enough.
for o in objs:
    if kind(o) == "bone" and len(o.data.polygons) > 400:
        mod = o.modifiers.new("dec", "DECIMATE")
        mod.ratio = float(os.environ.get("BONE_KEEP", "0.5"))
        with bpy.context.temp_override(object=o, active_object=o):
            bpy.ops.object.modifier_apply(modifier=mod.name)
# Smooth vertex normals (one per vertex, not per corner) keep the file small.
for o in objs:
    for name in ("custom_normal", "sharp_face", "sharp_edge"):
        if name in o.data.attributes:
            o.data.attributes.remove(o.data.attributes[name])
bind_all()

# The skeleton is drawn under the muscles, so a gap between two of them shows bone. The top of
# Z-Anatomy's skull is a little longer than the bald head drawn over it: tuck it under the scalp.
VAULT = Vector(J["head"] + [0, -0.03, 0.085])
for scalp in [o for o in objs if kind(o) not in ("muscle", "bone") and world(o)[:, 2].max() > VAULT.z]:
    bvh = BVHTree.FromPolygons([Vector(p) for p in world(scalp)], [tuple(f.vertices) for f in scalp.data.polygons])
    tucked = 0
    for o in objs:
        if kind(o) != "bone":
            continue
        P = world(o)
        if P[:, 2].max() < VAULT.z - 0.055:
            continue
        back = np.linalg.inv(np.array(o.matrix_world))
        for i in np.nonzero((P[:, 2] > VAULT.z - 0.01) | (P[:, 1] > VAULT.y + 0.04) & (P[:, 2] > VAULT.z - 0.055))[0]:
            ray = Vector(P[i]) - VAULT
            hit = bvh.ray_cast(VAULT, ray.normalized())
            if hit[0] is not None and ray.length > 0.97 * hit[3]:
                q = np.array(VAULT + ray.normalized() * 0.97 * hit[3])
                o.data.vertices[i].co = back[:3, :3] @ q + back[:3, 3]
                tucked += 1
    print("skull points tucked under the scalp", tucked)

S = skinmesh.build(SKIN, trees, J, arm, lambda V, bones, W: twist_split(V, *skin_helpers(V, bones, W)))

# How far the belly of each muscle group swells for an athletic build, in metres.
PUMPED = {"side_delts": 0.012, "front_delts": 0.010, "rear_delts": 0.010, "chest": 0.012, "upper_chest": 0.010,
          "biceps": 0.012, "brachialis": 0.006, "triceps": 0.011, "brachioradialis": 0.006, "wrist_flexors": 0.006,
          "wrist_extensors": 0.006, "lats": 0.010, "upper_traps": 0.008, "mid_traps": 0.005, "lower_traps": 0.004,
          "quads": 0.013, "hamstrings": 0.010, "adductors": 0.006, "calves": 0.011, "soleus": 0.005,
          "glutes": 0.008, "glute_med": 0.005, "abs": 0.005, "obliques": 0.004, "serratus_anterior": 0.003,
          "lower_back": 0.004, "shins": 0.004}
fill_out(S.skin, lambda name: PUMPED.get(group_of(name), 0.0))

parts = {}
for o in objs:
    k = kind(o)
    key = "m_" + group_of(base(o.name)) if k == "muscle" else ("bones" if k == "bone" else "head")
    parts.setdefault(key, []).append(o)

# The skin, split by what covers it: one mesh per clothing class. Cut along the waist, the
# shorts' hem and the ankles first, so the clothes end on a straight line instead of the
# triangles' zigzag, then class each face by where its middle is.
skin = S.skin
bm = bmesh.new()
bm.from_mesh(skin.data)
marks = {"torso": ["thorax", "lumbar", "clavicle", "scapula", "pelvis"], "hips": ["pelvis", "lumbar", "femur"],
         "arm": ["humerus"]}
layers = {k: bm.verts.layers.float.new(k) for k in [*marks, "inside"]}
# Under the armpit the top ends where the arm's own skin begins: Z-Anatomy's region border is a
# smooth line, which the bone a face follows is not.
limb = bm.faces.layers.int.new("limb")
for f, r in zip(bm.faces, S.R):
    f[limb] = int(bool(re.search(r"region of arm|bicipital|Deltoid|forearm|elbow|Cubital|hand|palm|wrist", S.NAMES[r], re.I)))
bm.verts.ensure_lookup_table()
for i, v in enumerate(bm.verts):
    for k, bases in marks.items():
        v[layers[k]] = float(S.base[i] in bases)
    v[layers["inside"]] = float(S.inside[i])
# The top is sleeveless with a round neck: a plane across the base of the neck, lower in front,
# and one down each shoulder from the tip of the collarbone to the armpit.
NECK = (J["neck"][1], J["neck"][2] + 0.026, 0.32)  # y, z, rise per metre toward the back
ARM = (J["ac.l"][0] + 0.017, J["ac.l"][2] + 0.02, 0.06, J["gh.l"][2] - 0.09)  # x, z, flare, armpit z
CUTS = [((0, 0, z), (0, 0, 1)) for z in (S.waist, S.hem, S.ankle)]
CUTS.append(((0, NECK[0], NECK[1]), (0, -NECK[2], 1)))
CUTS += [((sx * ARM[0], 0, ARM[1]), (sx, 0, ARM[2])) for sx in (1, -1)]
for co, no in CUTS:
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no)
bmesh.ops.triangulate(bm, faces=bm.faces[:])
FCLS = np.zeros(len(bm.faces), int)
for fi, f in enumerate(bm.faces):
    x, y, z = (sum(v.co[i] for v in f.verts) / len(f.verts) for i in range(3))
    has = {k: sum(v[layers[k]] for v in f.verts) / len(f.verts) > 0.5 for k in layers}
    if z > ARM[3]:  # above the armpits the cuts decide (but the inside of the arm stays bare)
        has["torso"] = (z < NECK[1] + NECK[2] * (y - NECK[0]) and abs(x) < ARM[0] + (ARM[1] - z) * ARM[2]
                        and (z > J["gh.l"][2] - 0.06 or not has["arm"]))
    else:
        has["torso"] = not f[limb]
    # The middle of the band is the shorts whatever bone leads there (the hands hang wider).
    if has["inside"] or (has["hips"] or abs(x) < 0.12) and S.hem < z <= S.waist:
        FCLS[fi] = 2
    elif has["torso"] and z > S.waist:
        FCLS[fi] = 1
    elif z < S.ankle:  # nothing else reaches below the ankles at rest
        FCLS[fi] = 3
bm.to_mesh(skin.data)
bm.free()
for k in [*layers, "limb"]:  # only needed for the split
    skin.data.attributes.remove(skin.data.attributes[k])
for a in list(skin.data.color_attributes):
    skin.data.color_attributes.remove(a)
for c, name in enumerate(("skin_body", "skin_top", "skin_shorts", "skin_shoes")):
    o = skin.copy()
    o.data = skin.data.copy()
    bpy.context.scene.collection.objects.link(o)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in np.nonzero(FCLS != c)[0]], context="FACES")
    bm.to_mesh(o.data)
    bm.free()
    parts[name] = [o]
bpy.data.objects.remove(skin, do_unlink=True)

MERGE = float(os.environ.get("MERGE", 0.003))   # the grain the groups are rebuilt at; 0 keeps every muscle
MERGE_KEEP = float(os.environ.get("MERGE_KEEP", 0.4))
MERGE_CLOSE = float(os.environ.get("MERGE_CLOSE", 0.003))


def merge_smooth(o):
    """Rebuild a muscle group as one smooth body.

    The atlas draws every muscle of a group on its own, with its fibres, and the eye reads a
    forearm as twenty strands. Here the group's muscles are fused where they touch into one
    surface, the fibre texture and ragged tendon edges are smoothed off, and each new point
    moves with the joints as the nearest points of the old muscles did. Nothing changes
    place: what is lost is only the seams inside a group.
    """
    P0 = world(o)
    names = [g.name for g in o.vertex_groups]
    W0 = np.zeros((len(P0), len(names)), np.float32)
    for v in o.data.vertices:
        for g in v.groups:
            W0[v.index, g.group] = g.weight
    for m in list(o.modifiers):
        o.modifiers.remove(m)
    with bpy.context.temp_override(object=o, active_object=o):
        m = o.modifiers.new("fuse", "REMESH")
        m.mode, m.voxel_size, m.adaptivity = "VOXEL", MERGE, 0.0
        bpy.ops.object.modifier_apply(modifier=m.name)
        if len(o.data.vertices) < 8:
            return False
        # Close the slits between the muscles of the group: swell, fuse again, and shrink back.
        for step in (MERGE_CLOSE, None, -MERGE_CLOSE):
            if step is None:
                m = o.modifiers.new("fuse", "REMESH")
                m.mode, m.voxel_size, m.adaptivity = "VOXEL", MERGE, 0.0
            else:
                m = o.modifiers.new("swell", "DISPLACE")
                m.direction, m.mid_level, m.strength = "NORMAL", 0.0, step
            bpy.ops.object.modifier_apply(modifier=m.name)
        m = o.modifiers.new("smooth", "LAPLACIANSMOOTH")
        m.iterations, m.lambda_factor, m.lambda_border, m.use_volume_preserve = 20, 1.0, 0.0, True
        bpy.ops.object.modifier_apply(modifier=m.name)
        m = o.modifiers.new("thin", "DECIMATE")
        m.ratio = MERGE_KEEP
        bpy.ops.object.modifier_apply(modifier=m.name)
    o.vertex_groups.clear()
    P = world(o)
    d, near = cKDTree(P0).query(P, k=6)
    w = 1.0 / np.maximum(d, 1e-4) ** 2
    # a point takes nothing from the other side of the body (the thighs meet at the groin)
    side = np.sign(P0[:, 0])[near] * np.sign(P[:, 0])[:, None]
    w = np.where((side < 0) & (np.abs(P[:, :1]) > 0.01) & (np.abs(P0[:, 0])[near] > 0.01), 0, w)
    w[:, 0] = np.maximum(w[:, 0], 1e-9)
    W = (W0[near] * w[:, :, None]).sum(1)
    W /= np.maximum(W.sum(1, keepdims=True), 1e-9)
    for j, b in enumerate(names):
        hit = np.nonzero(W[:, j] > 0.01)[0]
        if len(hit):
            vg = o.vertex_groups.new(name=b)
            for i in hit:
                vg.add([int(i)], float(W[i, j]), "REPLACE")
    for p in o.data.polygons:
        p.use_smooth = True
    mod = o.modifiers.new("arm", "ARMATURE")
    mod.object = arm
    return True


for key, group in parts.items():
    first = group[0]
    if len(group) > 1:
        with bpy.context.temp_override(active_object=first, object=first, selected_objects=group,
                                       selected_editable_objects=group):
            bpy.ops.object.join()
    first.name = first.data.name = key
    if MERGE and key.startswith("m_"):
        before = len(first.data.vertices)
        merge_smooth(first)
        print("merged", key, before, "->", len(first.data.vertices))
    mat = bpy.data.materials.get(key) or bpy.data.materials.new(key)
    first.data.materials.clear()
    first.data.materials.append(mat)
    for p in first.data.polygons:
        p.material_index = 0
print("parts", sorted(parts))

# ---------------------------------------------------------------- rig JSON
rig = rig_json()
json.dump(rig, open(RIG_OUT, "w"), separators=(",", ":"))
out = rig["bones"]
print("wrote", RIG_OUT, len(out), "bones")

# ---------------------------------------------------------------- USD
for b in arm_data.bones:
    b.name = b.name.replace(".", "_")
arm.name = "Body"
bpy.ops.wm.usd_export(filepath=OUT, export_animation=False, export_armatures=True, only_deform_bones=False,
                      export_materials=True, generate_preview_surface=True, export_uvmaps=False,
                      export_normals=True, selected_objects_only=False, root_prim_path="/Body")
print("wrote", OUT, os.path.getsize(OUT) // 1024, "KB")

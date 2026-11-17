"""The app's 3D body: the rigged Z-Anatomy model as one USD file, plus its skeleton as JSON.

    python export_app.py za.glb skin.npz body.usdc body-rig.json
    python pack_usdz.py body.usdc Body.usdz

za.glb is the static model from export_za.py and skin.npz the body surface from
export_skin.py (both Z-Anatomy, CC BY-SA 4.0). The file holds one armature and,
bound to it:

- one mesh per catalog muscle group, named "m_<group>" (m_chest, m_lats ...), so the
  app can light up the working muscles; muscles outside every group are "m_other".
  Their texture coordinates run across and along the fibres (fibre_texture.py);
- "suit_seams", the line drawn between the muscle groups;
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
fill_out(S.skin, lambda name: PUMPED.get((group_of(name) or "").replace("-", "_"), 0.0))

# Round the armpit the skin's shares of the trunk, the blade and the arm change from point to
# point more sharply than the skin can follow, and with the arm overhead it stood up in
# small folds and points there. The shares are evened out among neighbours.
def soften_armpit(o, reach=float(os.environ.get("PIT_REACH", 0.15)), rounds=int(os.environ.get("PIT_ROUNDS", 16))):
    import scipy.sparse as sp
    P = world(o)
    n = len(P)
    names = [g.name for g in o.vertex_groups]
    W = np.zeros((n, len(names)), np.float32)
    for v in o.data.vertices:
        for g in v.groups:
            W[v.index, g.group] = g.weight
    E = np.array([e.vertices[:] for e in o.data.edges])
    A = sp.coo_matrix((np.ones(len(E) * 2, np.float32), (np.r_[E[:, 0], E[:, 1]], np.r_[E[:, 1], E[:, 0]])), shape=(n, n)).tocsr()
    A = sp.diags(1.0 / np.maximum(np.asarray(A.sum(1)).ravel(), 1)) @ A
    pit = np.zeros(n)
    for s_ in "lr":
        c = J[f"gh.{s_}"] + np.array([0, 0, -0.04])
        pit = np.maximum(pit, ease((reach - np.linalg.norm(P - c, axis=1)) / 0.06))
    W0 = W.copy()
    for _ in range(rounds):
        W = W + pit[:, None] * 0.5 * (A @ W - W)
    W /= np.maximum(W.sum(1, keepdims=True), 1e-9)
    for j, g in enumerate(o.vertex_groups):
        hit = np.nonzero((W[:, j] > 0.003) | (W0[:, j] > 0))[0]
        for i in hit:
            g.add([int(i)], float(W[i, j]), "REPLACE")
    print("armpit skin points evened out", int((pit > 0).sum()))


if int(os.environ.get("PIT", 1)):
    soften_armpit(S.skin)

# A copy of the whole skin, before it is cut into clothes: the muscle suit is made from it.
suit_src = S.skin.copy()
suit_src.data = S.skin.data.copy()
bpy.context.scene.collection.objects.link(suit_src)

parts = {}
for o in objs:
    k = kind(o)
    key = "m_" + group_of(base(o.name)) if k == "muscle" else ("bones" if k == "bone" else "head")
    parts.setdefault(key, []).append(o)

# ---------------------------------------------------------------- fibres
# Which way the fibres of every muscle run, so a working muscle can be drawn with its grain.
# A muscle stretched between two bones runs from its origin to its insertion along its own
# surface (the fan of the chest gathers toward the arm); any other runs along its length.
# FIBRE_WAY: the flat sheets whose length says nothing, as (x toward the midline, y, z).
FIBRE_WAY = [(r"abdominal oblique", (0.7, -0.7, -1.0)), (r"serratus anterior", (0.0, 1.0, 0.25))]
FIBRE_PITCH = (float(os.environ.get("FIBRE_ACROSS", 0.032)), float(os.environ.get("FIBRE_ALONG", 0.128)))  # metres per tile


def fibre_way(o):
    name = base(o.name)
    S_ = Surface(o)
    side = 1.0 if S_.Q[:, 0].mean() >= 0 else -1.0
    for rx, way in FIBRE_WAY:
        if re.search(rx, name, re.I):
            return np.tile(np.array(way) * (-side, 1, 1), (len(S_.P), 1))
    if span_of(name):
        ends, opt = span_of(name)
        if ends[0] and ends[1]:
            f0, f1 = run_between(S_, S_.gaps(ends[0]).min(1), S_.gaps(ends[1]).min(1), opt.get("far", False))
            f, e = f0 - f1, S_.e
            d = S_.Q[e[:, 1]] - S_.Q[e[:, 0]]
            M, b = np.zeros((S_.k, 3, 3)), np.zeros((S_.k, 3))
            for a in (0, 1):
                np.add.at(M, e[:, a], d[:, :, None] * d[:, None, :])
                np.add.at(b, e[:, a], d * (f[e[:, 1]] - f[e[:, 0]])[:, None])
            M += (np.trace(M, axis1=1, axis2=2)[:, None, None] * 1e-3 + 1e-12) * np.eye(3)
            g = np.linalg.solve(M, b[:, :, None])[:, :, 0]
            g = np.stack([S_.smooth(g[:, a], 6) for a in range(3)], 1)
            g /= np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)
            return g[S_.same]
    c = S_.Q - S_.Q.mean(0)
    axis = np.linalg.svd(c, full_matrices=False)[2][0]
    if axis @ np.array([0.8 * side, 0, -1.0]) < 0:  # toward the far end of a limb, or down
        axis = -axis
    return np.tile(axis, (len(S_.P), 1))


FIBRES = {}
for key, group in parts.items():
    if key.startswith("m_") and key != "m_other":
        FIBRES[key] = (np.concatenate([world(o) for o in group]), np.concatenate([fibre_way(o) for o in group]))
print("fibre directions for", len(FIBRES), "groups")


def fibre_map(o, key):
    """Texture coordinates on a muscle part: u across its fibres, v along them."""
    import scipy.sparse as sp
    from scipy.sparse.linalg import splu
    me = o.data
    n = len(me.vertices)
    P = world(o)
    N = np.empty(n * 3)
    me.vertices.foreach_get("normal", N)
    N = N.reshape(-1, 3) @ np.array(o.matrix_world)[:3, :3].T
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
    E = np.empty(len(me.edges) * 2, int)
    me.edges.foreach_get("vertices", E)
    E = E.reshape(-1, 2)
    A = sp.coo_matrix((np.ones(len(E) * 2), (np.r_[E[:, 0], E[:, 1]], np.r_[E[:, 1], E[:, 0]])), shape=(n, n)).tocsr()
    A = sp.diags(1.0 / np.maximum(np.asarray(A.sum(1)).ravel(), 1)) @ A
    pts, ways = FIBRES[key]
    d, near = cKDTree(pts).query(P, k=4)
    D0 = ways[near[:, 0]]
    agree = np.where((ways[near] * D0[:, None, :]).sum(2) < 0, -1.0, 1.0)
    D = (ways[near] * (agree / np.maximum(d, 1e-3) ** 2)[:, :, None]).sum(1)

    def flat(D):
        D = D - N * (D * N).sum(1, keepdims=True)
        return D / np.maximum(np.linalg.norm(D, axis=1, keepdims=True), 1e-9)

    D = flat(D)
    for _ in range(8):  # two muscles side by side that were read end for end
        D = np.where(((A @ D) * D).sum(1, keepdims=True) < 0, -D, D)
    for _ in range(12):
        D = flat(0.5 * D + 0.5 * (A @ D))
    T = np.cross(N, D)
    # the coordinates whose steps along every edge come nearest to the steps across and along
    step = P[E[:, 1]] - P[E[:, 0]]
    B = sp.coo_matrix((np.r_[-np.ones(len(E)), np.ones(len(E))], (np.r_[np.arange(len(E)), np.arange(len(E))], np.r_[E[:, 0], E[:, 1]])),
                      shape=(len(E), n)).tocsr()
    solve = splu((B.T @ B + 1e-7 * sp.identity(n)).tocsc()).solve
    uv = np.stack([solve(B.T @ (step * (X[E[:, 0]] + X[E[:, 1]]) / 2).sum(1)) / pitch for X, pitch in ((T, FIBRE_PITCH[0]), (D, FIBRE_PITCH[1]))], 1)
    loops = np.empty(len(me.loops), int)
    me.loops.foreach_get("vertex_index", loops)
    layer = me.uv_layers.new(name="st")
    layer.data.foreach_set("uv", uv[loops].astype(np.float32).ravel())
    return float(np.abs(((uv[E[:, 1], 0] - uv[E[:, 0], 0]) * FIBRE_PITCH[0]) - (step * (T[E[:, 0]] + T[E[:, 1]]) / 2).sum(1)).mean() / np.linalg.norm(step, axis=1).mean())


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
MERGE_KEEP = float(os.environ.get("MERGE_KEEP", 0.3))
MERGE_CLOSE = float(os.environ.get("MERGE_CLOSE", 0.003))
MERGE_SMOOTH = int(os.environ.get("MERGE_SMOOTH", 30))


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
        # The atlas's big muscles are coarse (a gluteus has a few hundred points) and their
        # flats would be copied faithfully: round them first.
        m = o.modifiers.new("round", "SUBSURF")
        m.levels = m.render_levels = 2
        bpy.ops.object.modifier_apply(modifier=m.name)
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
        m.iterations, m.lambda_factor, m.lambda_border, m.use_volume_preserve = MERGE_SMOOTH, 1.0, 0.0, True
        bpy.ops.object.modifier_apply(modifier=m.name)
        m = o.modifiers.new("thin", "DECIMATE")
        m.ratio = MERGE_KEEP
        bpy.ops.object.modifier_apply(modifier=m.name)
        # thinning leaves small flats: one more light pass rounds them off
        m = o.modifiers.new("smooth", "LAPLACIANSMOOTH")
        m.iterations, m.lambda_factor, m.lambda_border, m.use_volume_preserve = 4, 0.6, 0.0, True
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

SUIT = int(os.environ.get("SUIT", 1))            # subdivisions of the skin for the muscle suit; 0 keeps the loose muscles
SUIT_MIN, SUIT_MAX = float(os.environ.get("SUIT_MIN", 0.0012)), float(os.environ.get("SUIT_MAX", 0.005))
SUIT_NEAR = float(os.environ.get("SUIT_NEAR", 0.02))
SUIT_SEAM, SUIT_SOFT = float(os.environ.get("SUIT_SEAM", 0.003)), int(os.environ.get("SUIT_SOFT", 8))
SUIT_BLUR = int(os.environ.get("SUIT_BLUR", 24))
# the muscle under another's flat tendon: how far under it may lie, and up to what height
# (the long back muscles run on up under the fleshy latissimus, which keeps that part)
LOIN_WIDE = float(os.environ.get("LOIN_WIDE", 0.07))  # half the width of the long back muscles at the loin
SUIT_UNDER = {"m_obliques": ("m_abs", 0.035, 9.0),
              "m_lats": ("m_lower-back", float(os.environ.get("LOIN", 0.05)), J["thorax"][2] + float(os.environ.get("LOIN_TOP", 0.03)))}
GROIN = (0.05, 0.25, 0.02, 0.06)  # half width, from and to below the hip joints, and how far back
SUIT_FEW = int(os.environ.get("SUIT_FEW", 300))
SEAM_WIDE = float(os.environ.get("SEAM_WIDE", 0.002))  # the dark line between two groups


def dress(o, key):
    mat = bpy.data.materials.get(key) or bpy.data.materials.new(key)
    o.data.materials.clear()
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.material_index = 0
        p.use_smooth = True


def muscle_suit(o):
    """The muscles as one closed surface under the skin.

    Loose muscles leave cracks between them, and each moves by its own bones, so in a deep
    pose the cracks open, bone shows, and a muscle that folds leaves a hole. Here the skin
    itself is the surface: a finer copy of it is sunk to the muscles lying under it, so their
    shapes and the furrows between them are pressed into it, and each of its faces belongs
    to the group whose muscle is nearest. It moves as the skin does, which has no gaps.
    """
    for m in list(o.modifiers):
        o.modifiers.remove(m)
    # The skin is a whole body and the suit is not dressed: between the legs it is drawn
    # as a plain smooth bridge.
    V0 = world(o)
    E0 = np.array([e.vertices[:] for e in o.data.edges])
    hip = J["hip.l"]
    soft = (np.abs(V0[:, 0]) < GROIN[0]) & (V0[:, 2] > hip[2] - GROIN[1]) & (V0[:, 2] < hip[2] - GROIN[2]) & (V0[:, 1] < hip[1] + GROIN[3])
    d0 = np.bincount(E0.ravel(), minlength=len(V0)).astype(float)[:, None]
    V1 = V0.copy()
    Es = E0[soft[E0].any(1)]
    for _ in range(4000):
        t = np.zeros_like(V1)
        np.add.at(t, Es[:, 0], V1[Es[:, 1]]); np.add.at(t, Es[:, 1], V1[Es[:, 0]])
        V1[soft] = (t / np.maximum(d0, 1))[soft]
    back0 = np.linalg.inv(np.array(o.matrix_world))
    o.data.vertices.foreach_set("co", (V1 @ back0[:3, :3].T + back0[:3, 3]).ravel())
    o.data.update()
    mid = np.zeros(len(V0), bool)
    for z in np.arange(-0.26, 0.06, 0.02):
        sl = mid & (V0[:, 2] > hip[2] + z) & (V0[:, 2] < hip[2] + z + 0.02)
        if sl.any():
            print("slice z", round(z, 2), "y front/back", V0[sl, 1].min().round(3), V0[sl, 1].max().round(3), "hip y", hip[1].round(3), "after", V1[sl, 1].min().round(3))
    print("groin points smoothed", int(soft.sum()), "moved up to mm", round(float(np.linalg.norm(V1 - V0, axis=1).max() * 1000), 1))
    bpy.context.view_layer.objects.active = o
    m = o.modifiers.new("fine", "SUBSURF")
    m.levels = m.render_levels = SUIT
    bpy.ops.object.modifier_apply(modifier=m.name)
    me = o.data
    n = len(me.vertices)
    P = world(o)
    N = np.empty(n * 3)
    me.vertices.foreach_get("normal", N)
    N = N.reshape(-1, 3)
    names = [g.name for g in o.vertex_groups]
    W = np.zeros((n, len(names)), np.float32)
    for v in me.vertices:
        for g in v.groups:
            W[v.index, g.group] = g.weight
    E = np.empty(len(me.edges) * 2, int)
    me.edges.foreach_get("vertices", E)
    E = E.reshape(-1, 2)
    deg = np.bincount(E.ravel(), minlength=n).astype(float)

    def tree(group):
        V, F, own, k = [], [], [], 0
        for j, m_ in enumerate(group):
            Q = world(m_)
            m_.data.calc_loop_triangles()
            T = np.empty(len(m_.data.loop_triangles) * 3, int)
            m_.data.loop_triangles.foreach_get("vertices", T)
            V.append(Q); F.append(T.reshape(-1, 3) + k); own.append(np.full(len(T) // 3, j)); k += len(Q)
        return BVHTree.FromPolygons(np.concatenate(V).tolist(), np.concatenate(F).tolist()), np.concatenate(own)

    keys = [k for k in parts if k.startswith("m_")]
    other = keys.index("m_other")
    flesh, owner = tree([parts[k][0] for k in keys])
    named = [j for j, k in enumerate(keys) if j != other]
    lean, lean_own = tree([parts[keys[j]][0] for j in named])
    bone, _ = tree(parts["bones"][:1])
    rest, _ = tree(parts["head"][:1])
    import scipy.sparse as sp
    A = sp.coo_matrix((np.ones(len(E) * 2, np.float32), (np.r_[E[:, 0], E[:, 1]], np.r_[E[:, 1], E[:, 0]])), shape=(n, n)).tocsr()
    A = sp.diags(1.0 / np.maximum(deg, 1)) @ A
    under = {keys.index(a): (keys.index(b), reach, top) for a, (b, reach, top) in SUIT_UNDER.items() if a in keys and b in keys}
    deep = {j: tree([parts[keys[j]][0]])[0] for j, _, _ in under.values()}
    # what moves with the skull alone is the head's, which is drawn as it is
    rigid = W[:, names.index("head")] > 0.97 if "head" in names else np.zeros(n, bool)
    OUT_ = 0.004
    depth, label, gone, dbone = np.full(n, SUIT_MAX), np.full(n, other), np.zeros(n, bool), np.ones(n)
    for i in range(n):
        p, d = Vector(P[i]), Vector(N[i])
        gone[i] = rigid[i] or rest.find_nearest(p, 0.004)[0] is not None
        hit = flesh.ray_cast(p + d * OUT_, -d, OUT_ + 0.03)
        dm = hit[3] - OUT_ if hit[0] is not None else 1.0
        hb = bone.ray_cast(p + d * OUT_, -d, OUT_ + 0.03)
        db = hb[3] - OUT_ - 0.001 if hb[0] is not None else 1.0
        # A named muscle under a thin sheet (the sheath over the abdominals, the fascia of
        # the loin) owns the place and not the sheet; tendon and bone go to "other".
        near = lean.find_nearest(p - d * 0.002, SUIT_NEAR * 0.7)
        if near[0] is not None and db > min(dm, near[3]) - 0.001:
            g = named[lean_own[near[2]]]
            if g in under:
                # ... and so does the muscle straight under the flat tendon of another
                below, reach, top = under[g]
                h = deep[below].find_nearest(p, reach)
                if p.z < top and (top > 5 or abs(p.x) < LOIN_WIDE) and h[0] is not None and (p - h[0]).normalized().dot(d) > 0.5:
                    g = below
            label[i] = g
        depth[i], dbone[i] = min(dm, db, SUIT_MAX + 0.004), db
    # Each group spreads a little into its neighbours and the stronger one has the point:
    # the borders run smooth, specks vanish, and how even the contest is says how near the
    # border a point lies. A furrow runs along every border, as in an anatomical drawing.
    votes = np.zeros((n, len(keys)), np.float32)
    votes[np.arange(n), label] = 1
    for _ in range(SUIT_BLUR):
        votes = 0.5 * votes + 0.5 * (A @ votes)
    label = votes.argmax(1)
    # The border between two groups runs where their contest is even, which is somewhere
    # along an edge and not at a point: every face the border crosses is cut there, so the
    # border is a smooth line and not the zigzag of the faces.
    cut, extra, F, FL = {}, [], [], []

    def cross(a_, b_):
        if a_ > b_:
            a_, b_ = b_, a_
        if (a_, b_) not in cut:
            fa = votes[a_, label[a_]] - votes[a_, label[b_]]
            fb = votes[b_, label[b_]] - votes[b_, label[a_]]
            t = min(max(fa / max(fa + fb, 1e-9), 0.08), 0.92)
            cut[(a_, b_)] = n + len(extra)
            extra.append(((a_, b_), (1 - t, t)))
        return cut[(a_, b_)]

    for f in (tuple(p.vertices) for p in me.polygons):
        if len(set(label[list(f)])) == 1:
            F.append(f); FL.append(label[f[0]])
            continue
        for a_, b_, c_ in [f[:3]] + [(f[0], f[k], f[k + 1]) for k in range(2, len(f) - 1)]:
            la, lb, lc = label[a_], label[b_], label[c_]
            if la == lb == lc:
                F.append((a_, b_, c_)); FL.append(la)
            elif la != lb and lb != lc and la != lc:  # three groups meet inside this face
                ab, bc, ca = cross(a_, b_), cross(b_, c_), cross(c_, a_)
                mid = n + len(extra)
                extra.append(((a_, b_, c_), (1 / 3, 1 / 3, 1 / 3)))
                F += [(a_, ab, mid, ca), (b_, bc, mid, ab), (c_, ca, mid, bc)]; FL += [la, lb, lc]
            else:
                if la == lc:
                    a_, b_, c_ = c_, a_, b_
                elif lb == lc:
                    a_, b_, c_ = b_, c_, a_
                ac, bc = cross(a_, c_), cross(b_, c_)
                F += [(a_, b_, bc, ac), (ac, bc, c_)]; FL += [label[a_], label[c_]]
    FL = np.array(FL)

    def more(X):
        new = np.array([sum(w * X[i].astype(np.float64) for i, w in zip(at, ws)) for at, ws in extra])
        return np.concatenate([X, new.astype(X.dtype).reshape((len(extra),) + X.shape[1:])])

    P, N, W, depth, dbone, votes = more(P), more(N), more(W), more(depth), more(dbone), more(votes)
    gone = np.concatenate([gone, [gone[list(at)].all() for at, _ in extra]])
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
    n = len(P)
    E = np.array(sorted({(min(a_, b_), max(a_, b_)) for f in F for a_, b_ in zip(f, f[1:] + f[:1])}))
    deg = np.bincount(E.ravel(), minlength=n).astype(float)
    A = sp.coo_matrix((np.ones(len(E) * 2, np.float32), (np.r_[E[:, 0], E[:, 1]], np.r_[E[:, 1], E[:, 0]])), shape=(n, n)).tocsr()
    A = sp.diags(1.0 / np.maximum(deg, 1)) @ A
    print("borders cut through", len(extra), "points")
    best = np.sort(votes, 1)[:, -2:]
    seam = (1 - np.clip((best[:, 1] - best[:, 0]) / 0.7, 0, 1)) ** 2
    for _ in range(2):
        seam = 0.5 * seam + 0.5 * (A @ seam)
    depth = np.clip(depth, SUIT_MIN, SUIT_MAX)
    for _ in range(SUIT_SOFT):
        depth = 0.5 * depth + 0.5 * (A @ depth)
    # never under a bone that lies just below the skin (the shin, the collar bone)
    depth = np.maximum(np.minimum(depth + SUIT_SEAM * seam, np.maximum(dbone, 0.0003)), np.minimum(SUIT_MIN, np.maximum(dbone, 0.0003)))
    Q = P - N * depth[:, None]
    keep = np.array([not gone[list(f)].all() for f in F])
    back = np.linalg.inv(np.array(o.matrix_world))
    count = np.bincount(FL[keep], minlength=len(keys))
    FL[np.isin(FL, np.nonzero(count < SUIT_FEW)[0])] = other
    # A dark line is drawn between the groups, as in an anatomical plate: along every border
    # the two groups draw back from each other a little and a ribbon closes the slit.
    kept = np.nonzero(keep)[0]
    sides = {}
    for i in kept:
        f = F[i]
        for a, b in zip(f, f[1:] + f[:1]):
            sides.setdefault((min(a, b), max(a, b)), []).append(i)
    border = [(e, fs) for e, fs in sides.items() if len(fs) == 2 and FL[fs[0]] != FL[fs[1]]]
    on_border = np.zeros(n, bool)
    on_border[np.array([e for e, _ in border]).ravel()] = True
    into = {}  # (point, group) -> where the group's faces at that point lie
    for i in kept:
        f = F[i]
        if on_border[list(f)].any():
            c = Q[list(f)].mean(0)
            for v in f:
                if on_border[v]:
                    acc = into.setdefault((v, FL[i]), [np.zeros(3), 0])
                    acc[0] += c; acc[1] += 1
    edge_ = {}
    for (v, g), (c, k) in into.items():
        t = c / k - Q[v]
        t -= N[v] * (t @ N[v])
        edge_[(v, g)] = Q[v] + t * min(SEAM_WIDE / 2 / max(np.linalg.norm(t), 1e-9), 0.4)
    made = {}

    def part(key, points, faces, src):
        me2 = bpy.data.meshes.new(key)
        me2.from_pydata((points @ back[:3, :3].T + back[:3, 3]).tolist(), [], faces)
        me2.update()
        o2 = bpy.data.objects.new(key, me2)
        bpy.context.scene.collection.objects.link(o2)
        o2.matrix_world = o.matrix_world
        for g, b_ in enumerate(names):
            hit = np.nonzero(W[src, g] > 0.004)[0]
            if len(hit):
                vg = o2.vertex_groups.new(name=b_)
                for i in hit:
                    vg.add([int(i)], float(W[src[i], g]), "REPLACE")
        mod = o2.modifiers.new("arm", "ARMATURE")
        mod.object = arm
        o2.parent = arm
        return o2

    for j, key in enumerate(keys):
        fs = [F[i] for i in np.nonzero(keep & (FL == j))[0]]
        if not fs:
            continue
        used = np.unique(np.concatenate([np.array(f) for f in fs]))
        at = np.full(n, -1); at[used] = np.arange(len(used))
        made[key] = part(key, np.array([edge_.get((v, j), Q[v]) for v in used]), [tuple(int(at[v]) for v in f) for f in fs], used)
    # the ribbon: a strip along every border edge and a patch where three groups meet
    ids, strip = {}, []
    for (a, b), (f1, f2) in border:
        quad = [(a, FL[f1]), (b, FL[f1]), (b, FL[f2]), (a, FL[f2])]
        X = [edge_[q] for q in quad]
        if np.cross(X[1] - X[0], X[2] - X[0]) @ N[a] < 0:
            quad.reverse()
        strip.append([ids.setdefault(q, len(ids)) for q in quad])
    meet = {}
    for v, g in edge_:
        meet.setdefault(v, []).append(g)
    for v, gs in meet.items():
        if len(gs) > 2:
            ax = np.cross(N[v], [0.3, 0.5, 0.8]); ax /= np.linalg.norm(ax)
            turn = [np.arctan2((edge_[(v, g)] - Q[v]) @ np.cross(N[v], ax), (edge_[(v, g)] - Q[v]) @ ax) for g in gs]
            strip.append([ids.setdefault((v, gs[k]), len(ids)) for k in np.argsort(turn)])
    order = sorted(ids, key=ids.get)
    made["suit_seams"] = part("suit_seams", np.array([edge_[q] for q in order]), strip, np.array([v for v, _ in order]))
    print("suit", n, "points;", len(made), "groups on the surface;", int(gone.sum()), "points left to the head, hands and feet")
    return made


if SUIT:
    made = muscle_suit(suit_src)
    for key, o2 in made.items():
        for old in parts.get(key, [])[:1]:
            bpy.data.objects.remove(old, do_unlink=True)
        o2.name = o2.data.name = key
        dress(o2, key)
        parts[key] = [o2]
    print("kept as they were (nothing of them reaches the surface):", sorted(k for k in parts if k.startswith("m_") and k not in made))
for key, group in parts.items():
    if key in FIBRES:
        print("fibre map", key, len(group[0].data.vertices), "points, off by", round(fibre_map(group[0], key), 3))
bpy.data.objects.remove(suit_src, do_unlink=True)
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
                      export_materials=True, generate_preview_surface=True, export_uvmaps=True,
                      export_normals=True, selected_objects_only=False, root_prim_path="/Body")
print("wrote", OUT, os.path.getsize(OUT) // 1024, "KB")

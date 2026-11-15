"""Shared Z-Anatomy rig: joint centres, armature, skin weights and pose maths.

Import after setting ZA_GLB to the static model written by export_za.py:

    os.environ["ZA_GLB"] = "za.glb"
    from rigbase import *

Joints sit at centres measured on the Z-Anatomy bones. Skeletal meshes move
rigidly with their own bone; each muscle blends between the bones it touches,
so it stretches between its attachments. Exercise scripts (rig_za.py for the
push-up, climb_za.py for stair climbing) build poses on top of this.
"""
import math
import os
import re
import sys

import bpy
import numpy as np
from mathutils import Matrix
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import extremities  # noqa: E402

SRC = os.environ["ZA_GLB"]
FPS = 24

# ---------------------------------------------------------------- load
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]


def base(name):
    return re.sub(r"(\.\d{3})+$", "", name)


def kind(o):
    return o.get("kind", "muscle")


BONES = {base(o.name): o for o in objs if kind(o) == "bone"}


def world(o):
    m = np.array(o.matrix_world)
    v = np.array([tuple(x.co) for x in o.data.vertices])
    return v @ m[:3, :3].T + m[:3, 3]


PTS = {n: world(o) for n, o in BONES.items()}


def pts(name):
    return PTS[name]


def sphere(p):
    """Least-squares sphere centre."""
    A = np.c_[2 * p, np.ones(len(p))]
    c = np.linalg.lstsq(A, (p ** 2).sum(1), rcond=None)[0]
    return c[:3]


za = extremities.ZA([])
za.objs = {n: o for n, o in BONES.items()}
za.pts = lambda name, side: PTS[f"{name}.{side}"]

# ---------------------------------------------------------------- joints
# Twist bones between the ulna (which does not turn) and the radius (which turns all the way):
# the soft tissue of the forearm follows them, a quarter of the turn each, so it twists
# along its length instead of tearing between the two bones.
TWIST = 3
J = {}
for s, sx in (("l", 1), ("r", -1)):
    fe = pts(f"Femur.{s}")
    top = fe[fe[:, 2] > fe[:, 2].max() - 0.07]
    head = top[sx * top[:, 0] < (sx * top[:, 0]).min() + 0.045]
    J[f"hip.{s}"] = sphere(head)
    bot = fe[fe[:, 2] < fe[:, 2].min() + 0.03]
    J[f"knee.{s}"] = bot.mean(0) + [0, 0, 0.012]
    ft = extremities.foot_targets(za, s)
    J[f"ankle.{s}"] = ft["ankle"]
    J[f"mtp.{s}"] = np.mean([ft[f"toe-{k}-1"] for k in range(1, 6)], 0)
    J[f"toetip.{s}"] = np.mean([ft[f"toe-{k}-{3 if k == 1 else 4}"] for k in range(1, 6)], 0)
    hu = pts(f"Humerus.{s}")
    top = hu[hu[:, 2] > hu[:, 2].max() - 0.05]
    head = top[sx * top[:, 0] < (sx * top[:, 0]).min() + 0.035]
    J[f"gh.{s}"] = sphere(head)
    bot = hu[hu[:, 2] < hu[:, 2].min() + 0.025]
    J[f"elbow.{s}"] = bot.mean(0) + [0, 0, 0.008]
    ra, ul = pts(f"Radius.{s}"), pts(f"Ulna.{s}")
    J[f"radhead.{s}"] = ra[ra[:, 2] > ra[:, 2].max() - 0.012].mean(0)
    J[f"ulnhead.{s}"] = ul[ul[:, 2] < ul[:, 2].min() + 0.012].mean(0)
    ht = extremities.hand_targets(za, s)
    J[f"wrist.{s}"] = ht["hand"]
    for k in range(1, 6):
        for i in range(1, 5):
            J[f"f{k}-{i}.{s}"] = ht[f"finger-{k}-{i}"]
    # The forearm turns about the line from the radial head to the head of the ulna.
    for i in range(1, TWIST + 1):
        J[f"fore{i}.{s}"] = J[f"radhead.{s}"] + (J[f"ulnhead.{s}"] - J[f"radhead.{s}"]) * (i / (TWIST + 2))
    cl = pts(f"Clavicle.{s}")
    c = cl.mean(0)
    ax = np.linalg.svd(cl - c)[2][0]
    t = (cl - c) @ ax
    e0, e1 = c + ax * t.min(), c + ax * t.max()
    J[f"sc.{s}"], J[f"ac.{s}"] = (e0, e1) if sx * e0[0] < sx * e1[0] else (e1, e0)
J["pelvis"] = (J["hip.l"] + J["hip.r"]) / 2
J["lumbar"] = pts("Vertebra L5").mean(0)
J["thorax"] = (pts("Vertebra T12").mean(0) + pts("Vertebra L1").mean(0)) / 2
J["neck"] = (pts("Vertebra C7").mean(0) + pts("Vertebra T1").mean(0)) / 2
J["head"] = pts("Axis (C2)").mean(0)
J["crown"] = J["head"] + [0, 0, 0.12]

# ---------------------------------------------------------------- shoulder girdle
def girdle():
    """What the shoulder blades glide on: an ellipsoid through the back and sides of the rib
    cage, and the two points of each blade's inner edge that stay on it (the lower corner and
    the root of the blade's spine)."""
    from scipy.optimize import least_squares
    ribs = np.concatenate([P for n, P in PTS.items() if re.search(r"\brib\b", n, re.I) and "cartilage" not in n.lower()])
    # The outer shell of the cage: the farthest point from its axis in each direction and level.
    y0 = -0.01
    th = np.arctan2(ribs[:, 1] - y0, ribs[:, 0])
    far = np.hypot(ribs[:, 0], ribs[:, 1] - y0)
    step = math.radians(6)
    shell = []
    for z in np.arange(ribs[:, 2].min(), ribs[:, 2].max(), 0.01):
        level = (ribs[:, 2] >= z) & (ribs[:, 2] < z + 0.01)
        for t in np.arange(-math.pi, math.pi, step):
            m = level & (th >= t) & (th < t + step)
            if m.sum() > 3:
                shell.append(ribs[m][far[m].argmax()])
    shell = np.array(shell)
    # Only where a blade can be: behind and beside the upper ribs, clear of the spine's groove.
    top = max(J["ac.l"][2], J["ac.r"][2])
    side = np.degrees(np.arctan2(shell[:, 1] - y0, np.abs(shell[:, 0])))
    zone = shell[(shell[:, 2] > top - 0.22) & (side > -25) & (np.abs(shell[:, 0]) > 0.03)]

    def off(p, P):
        cy, cz, rx, ry, rz = p
        q = (P - [0, cy, cz]) / [rx, ry, rz]
        f = np.sqrt((q ** 2).sum(1))
        return (f - 1) * f / np.sqrt(((q / [rx, ry, rz]) ** 2).sum(1))

    fit = least_squares(off, [0, top - 0.2, 0.15, 0.11, 0.3], args=(zone,), loss="soft_l1", f_scale=0.005).x
    out = {"center": [0.0, float(fit[0]), float(fit[1])], "radii": [float(x) for x in fit[2:]], "blades": {}}
    for s in "lr":
        P = pts(f"Scapula.{s}")
        lo, hi = P[:, 2].min(), P[:, 2].max()
        band = P[(P[:, 2] > lo + 0.6 * (hi - lo)) & (P[:, 2] < lo + 0.75 * (hi - lo))]
        out["blades"][s] = {"corner": P[P[:, 2].argmin()].tolist(), "root": band[np.abs(band[:, 0]).argmin()].tolist()}
    print("girdle: ellipsoid", np.round(fit, 3), "from", len(zone), "points, rms mm",
          round(float(np.sqrt((off(fit, zone) ** 2).mean())) * 1000, 1))
    return out


# ---------------------------------------------------------------- bones
# name: (head joint, tail joint, parent)
RIG = {"pelvis": ("pelvis", "lumbar", None), "lumbar": ("lumbar", "thorax", "pelvis"),
       "thorax": ("thorax", "neck", "lumbar"), "neck": ("neck", "head", "thorax"),
       "head": ("head", "crown", "neck")}
for s in "lr":
    RIG.update({
        f"femur.{s}": (f"hip.{s}", f"knee.{s}", "pelvis"),
        f"shin.{s}": (f"knee.{s}", f"ankle.{s}", f"femur.{s}"),
        f"foot.{s}": (f"ankle.{s}", f"mtp.{s}", f"shin.{s}"),
        f"toes.{s}": (f"mtp.{s}", f"toetip.{s}", f"foot.{s}"),
        f"clavicle.{s}": (f"sc.{s}", f"ac.{s}", "thorax"),
        f"scapula.{s}": (f"ac.{s}", f"gh.{s}", f"clavicle.{s}"),
        f"humerus.{s}": (f"gh.{s}", f"elbow.{s}", f"scapula.{s}"),
        f"ulna.{s}": (f"elbow.{s}", f"ulnhead.{s}", f"humerus.{s}"),
        f"radius.{s}": (f"radhead.{s}", f"wrist.{s}", f"ulna.{s}"),
        f"hand.{s}": (f"wrist.{s}", f"f3-1.{s}", f"radius.{s}"),
    })
    for i in range(1, TWIST + 1):
        RIG[f"fore{i}.{s}"] = (f"radhead.{s}", f"fore{i}.{s}", f"ulna.{s}")
    for k in range(1, 6):
        RIG[f"f{k}a.{s}"] = (f"f{k}-1.{s}", f"f{k}-2.{s}", f"hand.{s}")
        RIG[f"f{k}b.{s}"] = (f"f{k}-2.{s}", f"f{k}-3.{s}", f"f{k}a.{s}")
        RIG[f"f{k}c.{s}"] = (f"f{k}-3.{s}", f"f{k}-4.{s}", f"f{k}b.{s}")
ORDER = list(RIG)  # parents come before children

ORDW = {"first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5}


def bone_of(name):
    """Rig bone that a Z-Anatomy skeletal mesh moves with."""
    m = re.search(r"\.(l|r)$", name)
    s = m.group(1) if m else None
    n = name.lower()
    if re.search(r"hip bone|sacrum|coccyx", n):
        return "pelvis"
    if re.match(r"vertebra l", n):
        return "lumbar"
    if re.search(r"vertebra t|rib|costal|sternum|xiphoid", n):
        return "thorax"
    if re.search(r"vertebra c|atlas|axis|hyoid", n):
        return "neck"
    if not s:
        return "head"
    for key, b in (("femur", "femur"), ("patella", "shin"), ("tibia", "shin"), ("fibula", "shin"),
                   ("clavicle", "clavicle"), ("scapula", "scapula"), ("humerus", "humerus"),
                   ("ulna", "ulna"), ("radius", "radius")):
        if key in n:
            return f"{b}.{s}"
    if "finger of foot" in n:
        return f"toes.{s}"
    if re.search(r"talus|calcaneus|navicular|cuboid|cuneiform|metatarsal|sesamoid", n):
        return f"foot.{s}"
    fm = re.match(r"(proximal|middle|distal) phalanx of (\w+) finger of hand", n)
    if fm and fm.group(2) == "first":  # the thumb: metacarpal, proximal, distal
        return f"f1{'b' if fm.group(1) == 'proximal' else 'c'}.{s}"
    if fm and fm.group(2) in ORDW:
        return f"f{ORDW[fm.group(2)]}{'abc'['proximal middle distal'.split().index(fm.group(1))]}.{s}"
    if "first metacarpal" in n:
        return f"f1a.{s}"
    if re.search(r"phalanx|metacarpal|scaphoid|lunate|triquetrum|pisiform|trapez|capitate|hamate", n):
        return f"hand.{s}"
    return "head"


# ---------------------------------------------------------------- armature
arm_data = bpy.data.armatures.new("Body")
arm = bpy.data.objects.new("Body", arm_data)
bpy.context.scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
for b in ORDER:
    h, t, p = RIG[b]
    eb = arm_data.edit_bones.new(b)
    eb.head, eb.tail = J[h], J[t]
    if p:
        eb.parent = arm_data.edit_bones[p]
        eb.use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")
REST = {b: np.array(arm_data.bones[b].matrix_local)[:3, :3] for b in ORDER}
HEAD = {b: np.array(arm_data.bones[b].head_local) for b in ORDER}

# ---------------------------------------------------------------- weights
bone_pts = {}
for n, P in PTS.items():
    bone_pts.setdefault(bone_of(n), []).append(P)
trees = {b: cKDTree(np.concatenate(v)) for b, v in bone_pts.items()}
print("rig bones with skeletal meshes:", len(trees), "of", len(ORDER))


def twist_split(P, names, W):
    """Share each vertex's ulna and radius weight along the forearm's twist bones.

    At the elbow the tissue stays with the ulna, at the wrist it turns with the radius, and
    in between it follows the twist bones on either side of it.
    """
    names = list(names)
    for s in "lr":
        ul, ra = f"ulna.{s}", f"radius.{s}"
        if ul not in names and ra not in names:
            continue
        levels = [ul] + [f"fore{i}.{s}" for i in range(1, TWIST + 1)] + [ra]
        for b in levels:
            if b not in names:
                names.append(b)
                W = np.c_[W, np.zeros(len(W))]
        col = [names.index(b) for b in levels]
        fore = W[:, col[0]] + W[:, col[-1]]
        ax = J[f"wrist.{s}"] - J[f"elbow.{s}"]
        t = (P - J[f"elbow.{s}"]) @ ax / (ax @ ax)
        x = np.clip((t - 0.15) / 0.75, 0, 1) * (len(levels) - 1)
        lo = np.minimum(x.astype(int), len(levels) - 2)
        f = x - lo
        W[:, col] = 0
        for k, c in enumerate(col):
            W[:, c] += fore * np.where(lo == k, 1 - f, 0) + fore * np.where(lo + 1 == k, f, 0)
    return names, W


def bind(o, candidates, power=4.0):
    P = world(o)
    names = list(candidates)
    D = np.stack([trees[b].query(P)[0] for b in names], 1)
    W = 1.0 / np.maximum(D, 0.002) ** power
    # Keep the three strongest bones per vertex.
    if W.shape[1] > 3:
        cut = np.sort(W, 1)[:, -3][:, None]
        W[W < cut] = 0
    W /= W.sum(1, keepdims=True)
    names, W = twist_split(P, names, W)
    for j, b in enumerate(names):
        vg = o.vertex_groups.new(name=b)
        nz = np.nonzero(W[:, j] > 0.01)[0]
        for i in nz:
            vg.add([int(i)], float(W[i, j]), "REPLACE")



# Muscles that run from the trunk to the shoulder blade or the collarbone: (name, bones at one
# end, bones at the other). The blade slides a long way over the ribs, so each of these
# follows the bones it is attached to and stretches smoothly in between.
SPANS = [(r"trapezius", ("head", "neck", "thorax"), ("clavicle", "scapula")),
         (r"rhomboid", ("neck", "thorax"), ("scapula",)),
         (r"levator scapulae", ("neck",), ("scapula",)),
         (r"serratus anterior", ("thorax",), ("scapula",)),
         (r"pectoralis minor", ("thorax",), ("scapula",)),
         (r"subclavius", ("thorax",), ("clavicle",))]
# Lying next to a bone is not being attached to it. Nothing follows the shoulder blade or the
# collarbone unless it is attached there (the ribs' own muscles and the long back muscles
# pass right under the blade), and the muscles of the blade and the arm do not follow the
# ribs they slide over.
ON_BLADE = (r"trapezius|rhomboid|levator scapulae|serratus anterior|pectoralis minor|deltoid|supraspinatus|"
            r"infraspinatus|teres (major|minor)|subscapularis|biceps brachii|coracobrachialis|long head of triceps|omohyoid")
ON_COLLAR = r"trapezius|deltoid|pectoralis major|subclavius|sternocleidomastoid|sternohyoid|platysma|omohyoid"
OFF_TRUNK = r"deltoid|supraspinatus|infraspinatus|teres (major|minor)|subscapularis|biceps brachii|coracobrachialis|triceps"


def may_follow(name, bone):
    """Whether the muscle `name` can be attached to `bone` at all."""
    n = name.lower()
    if bone.startswith("scapula"):
        return bool(re.search(ON_BLADE, n))
    if bone.startswith("clavicle"):
        return bool(re.search(ON_COLLAR, n))
    if bone in ("head", "neck", "thorax", "lumbar", "pelvis"):
        return not re.search(OFF_TRUNK, n)
    return True


if os.environ.get("SPANS"):
    SPANS = [x for x in SPANS if re.search(os.environ["SPANS"], x[0])]


def span_of(name):
    """The bones at the two ends of a spanning muscle, or None for any other muscle."""
    m = re.search(r"\.(l|r)$", name)
    for rx, a, b in SPANS:
        if m and re.search(rx, name, re.I):
            ends = [[x if x in ("head", "neck", "thorax", "lumbar", "pelvis") else f"{x}.{m.group(1)}" for x in end]
                    for end in (a, b)]
            return [[x for x in end if x in trees] for end in ends]
    return None


def bind_span(o, ends, reach=0.012, sharp=1.5, reach_of_pull=0.12):
    """Weights for a muscle stretched between the bones at its two ends.

    Where the muscle touches a bone of one end it moves with that end. In between, each point
    is shared by how far along the muscle's own surface it is from either end, so a sheet
    stays pinned along its whole line of origin and stretches evenly toward its insertion.
    Within an end, a point goes with the bones of that end nearest to it.
    """
    import scipy.sparse as sp
    from scipy.sparse.csgraph import dijkstra
    P = world(o)
    # Vertices at the same place are one point of the surface.
    _, first, same = np.unique(np.round(P / 2e-5).astype(np.int64), axis=0, return_index=True, return_inverse=True)
    same = same.ravel()
    k = len(first)
    Q = P[first]
    split, gap = [], []
    for end in ends:
        D = np.stack([trees[b].query(Q)[0] for b in end], 1)
        keep = [j for j in range(len(end)) if D[:, j].min() < reach] or [int(D.min(0).argmin())]
        w = np.zeros_like(D)
        w[:, keep] = 1.0 / np.maximum(D[:, keep], 0.002) ** 4
        split.append(w / w.sum(1, keepdims=True))
        gap.append(D[:, keep].min(1))
    gap = np.stack(gap, 1)
    e = np.array([tuple(ed.vertices) for ed in o.data.edges], dtype=int).reshape(-1, 2)
    e = same[e]
    e = e[e[:, 0] != e[:, 1]]
    length = np.linalg.norm(Q[e[:, 0]] - Q[e[:, 1]], axis=1)
    # One extra point per end, joined to that end's attached vertices at no distance.
    far = []
    for j in range(2):
        seeds = np.nonzero((gap[:, j] < max(0.006, gap[:, j].min() + 0.004)) & (gap[:, j] <= gap[:, 1 - j]))[0]
        if not len(seeds):
            seeds = np.array([gap[:, j].argmin()])
        rows = np.r_[e[:, 0], e[:, 1], seeds, np.full(len(seeds), k)]
        cols = np.r_[e[:, 1], e[:, 0], np.full(len(seeds), k), seeds]
        G = sp.coo_matrix((np.r_[length, length, np.full(2 * len(seeds), 1e-9)], (rows, cols)), shape=(k + 1, k + 1)).tocsr()
        d = dijkstra(G, indices=k)[:k]
        # A loose piece the surface does not reach: straight-line distance instead.
        d[~np.isfinite(d)] = gap[~np.isfinite(d), j] + 0.02
        far.append(np.maximum(d, 1e-6))
    t = far[0] ** sharp / (far[0] ** sharp + far[1] ** sharp)  # 0 at the first end, 1 at the second
    # The second end is the one that moves (the blade swings on a long arm), so its pull stops
    # a hand's breadth from where the muscle meets it: even a small share of that swing would
    # drag the far side of a broad sheet through its neighbours. It fades over that whole
    # breadth, because a steeper fade folds the sheet when the blades are squeezed together.
    fade = np.clip((reach_of_pull - far[1]) / reach_of_pull, 0, 1)
    t *= fade * fade * (3 - 2 * fade)
    nbr = sp.coo_matrix((np.ones(2 * len(e)), (np.r_[e[:, 0], e[:, 1]], np.r_[e[:, 1], e[:, 0]])), shape=(k, k)).tocsr()
    deg = np.maximum(np.asarray(nbr.sum(1)).ravel(), 1)
    for _ in range(4):
        t = 0.5 * t + 0.5 * (nbr @ t) / deg
    W = np.c_[split[0] * (1 - t)[:, None], split[1] * t[:, None]][same]
    for j, b in enumerate(ends[0] + ends[1]):
        vg = o.vertex_groups.new(name=b)
        for i in np.nonzero(W[:, j] > 0.01)[0]:
            vg.add([int(i)], float(W[i, j]), "REPLACE")


def bind_all():
    """Bind every mesh in the file: bones rigidly, muscles and skin by distance."""
    for o in objs:
        k = kind(o)
        if k == "bone":
            vg = o.vertex_groups.new(name=bone_of(base(o.name)))
            vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
        elif k == "muscle" and span_of(base(o.name)):
            bind_span(o, span_of(base(o.name)))
        else:
            P = world(o)
            d = {b: t.query(P)[0].min() for b, t in trees.items()}
            if k == "muscle":
                d = {b: x for b, x in d.items() if may_follow(base(o.name), b)}
            reach = 0.012 if k == "muscle" else 0.03
            if k != "muscle":  # skin of the hands and feet: limb bones only
                d = {b: x for b, x in d.items() if re.match(r"(hand|f\d|radius|ulna|foot|toes|shin)", b)}
            cand = [b for b, x in d.items() if x < reach] or [min(d, key=d.get)]
            if base(o.name) == "Head":
                cand = ["head"]
            bind(o, cand, 4.0 if k == "muscle" else 6.0)
        mod = o.modifiers.new("arm", "ARMATURE")
        mod.object = arm
        o.parent = arm
    print("bound", len(objs), "meshes")


# ---------------------------------------------------------------- pose maths
def Rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def Ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def Rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def Raxis(ax, a):
    ax = ax / np.linalg.norm(ax)
    K = np.array([[0, -ax[2], ax[1]], [ax[2], 0, -ax[0]], [-ax[1], ax[0], 0]])
    return np.eye(3) + math.sin(a) * K + (1 - math.cos(a)) * K @ K


def frame_map(a0, b0, a1, b1):
    """Rotation taking direction a0 to a1, with b0 turned as close to b1 as it can."""
    def basis(a, b):
        a = a / np.linalg.norm(a)
        c = np.cross(a, b)
        c /= np.linalg.norm(c)
        return np.stack([a, np.cross(c, a), c], 1)
    return basis(a1, b1) @ basis(a0, b0).T


def slerp_m(A, B, t):
    """Rotation matrices: A then a fraction t of the way to B."""
    R = A.T @ B
    ang = math.acos(max(-1, min(1, (np.trace(R) - 1) / 2)))
    if ang < 1e-6:
        return A
    ax = np.array([R[2, 1] - R[1, 2], R[0, 2] - R[2, 0], R[1, 0] - R[0, 1]])
    return A @ Raxis(ax, ang * t)


D = math.radians
PRON = {}
L_UP = np.linalg.norm(J["elbow.l"] - J["gh.l"])
L_FORE = np.linalg.norm(J["wrist.l"] - J["elbow.l"])



def straighten(s):
    """Hand-space rotations that lay each finger segment along its metacarpal."""
    out = {}
    mc = {k: J[f"f{k}-1.{s}"] - J[f"wrist.{s}"] for k in range(2, 6)}
    for k in range(2, 6):
        for seg, (a, b) in zip("abc", ((1, 2), (2, 3), (3, 4))):
            d = J[f"f{k}-{b}.{s}"] - J[f"f{k}-{a}.{s}"]
            from_ = d / np.linalg.norm(d)
            to = mc[k] / np.linalg.norm(mc[k])
            out[f"f{k}{seg}.{s}"] = extremities.rot_between(from_, to * 0.97 + from_ * 0.03)
    return out


STRAIGHT = {**straighten("l"), **straighten("r")}
# Palm frame at rest: palm faces forward (-Y) in the anatomical position.
PALM = {}
for s in "lr":
    f = J[f"f3-1.{s}"] - J[f"wrist.{s}"]
    PALM[s] = (f / np.linalg.norm(f), np.array([0, -1.0, 0]))
# Elbow hinge at rest: flexion turns the forearm toward the front.
HINGE = {}
for s in "lr":
    f0 = J[f"wrist.{s}"] - J[f"elbow.{s}"]
    h = np.cross(f0, [0, -1.0, 0])
    HINGE[s] = h / np.linalg.norm(h)



def _twist(R, axis):
    """(sin, cos) of the twist of rotation R about axis (swing-twist split)."""
    w = math.sqrt(max(0, 1 + np.trace(R))) / 2
    v = np.array([R[2, 1] - R[1, 2], R[0, 2] - R[2, 0], R[1, 0] - R[0, 1]]) / (4 * max(w, 1e-6))
    p = (v @ axis) * axis
    n = math.hypot(w, np.linalg.norm(p))
    return (np.linalg.norm(p) / n * np.sign(v @ axis), w / n)


def fk(G, H, upto=None):
    """Head positions from the parents' rotations, in rig order."""
    for b in ORDER:
        p = RIG[b][2]
        if p is not None and p in G and p in H:
            H[b] = H[p] + G[p] @ (HEAD[b] - HEAD[p])
        if b == upto:
            return


def key_pose(arm, G, H, frame):
    """Key global rotations G and root position H on the armature at a frame."""
    pb = arm.pose.bones
    for b in ORDER:
        pa = RIG[b][2]
        Gp = G[pa] if pa else np.eye(3)
        B = REST[b].T @ Gp.T @ G[b] @ REST[b]
        pb[b].rotation_mode = "QUATERNION"
        pb[b].rotation_quaternion = Matrix(B.tolist()).to_quaternion()
        pb[b].keyframe_insert("rotation_quaternion", frame=frame)
        if pa is None:
            pb[b].location = REST[b].T @ (H[b] - HEAD[b])
            pb[b].keyframe_insert("location", frame=frame)

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
# Helper bones carry no skeletal mesh. Each turns a fixed share of the way from one bone to
# another, about the joint between them, so a muscle that crosses the joint goes round it in
# steps. The deltoid, the latissimus and the chest each have their own at the shoulder, turning
# about the point that keeps the middle of the muscle on the line from its origin to where it
# attaches on the arm (fitted over eight arm positions). Blended straight from one bone to the other, everything half way shrinks toward the
# joint (to nothing when the two are half a turn apart, as the arm overhead is from the chest).
# name: (parent, joint it turns about, joint it points to, turns from, turns to, share, rise).
# At a ball joint the helper follows the swing of the limb and its twist separately; "rise"
# is the side the limb is taken to have swung up through once it is nearly opposite to where
# it hangs at rest, where every side is equally short: out to the side and a little forward
# for the arm (the plane of the shoulder blade), forward for the thigh.
HELPERS = {}
for s, sx in (("l", 1), ("r", -1)):
    out = [round(sx * math.cos(math.radians(30)), 4), -0.5, 0.0]
    # The long muscles from the chest and the back to the arm are a hand's breadth from the
    # shoulder joint where they leave the trunk. Turned about the joint itself, the middle of
    # each would swing out on that long arm; turned about a point beside the armpit it lands
    # close to the straight line from where it leaves the trunk to where it meets the raised
    # arm. Each point is the best fit over raising the arm forward, sideways and across.
    J[f"pit.{s}"] = J[f"gh.{s}"] + [-sx * 0.042, 0.049, -0.059]
    J[f"breast.{s}"] = J[f"gh.{s}"] + [-sx * 0.050, -0.012, -0.020]
    # The deltoid is hung from the rim of the shoulder above the joint, so it swings about a
    # point just under that rim rather than the centre of the joint.
    J[f"cap.{s}"] = J[f"gh.{s}"] + [-sx * 0.009, 0.014, 0.023]
    HELPERS[f"delt.{s}"] = (f"scapula.{s}", f"cap.{s}", f"elbow.{s}", f"scapula.{s}", f"humerus.{s}", 1 / 2, out)
    HELPERS[f"shoulder.{s}"] = (f"scapula.{s}", f"gh.{s}", f"elbow.{s}", f"scapula.{s}", f"humerus.{s}", 1 / 2, out)
    HELPERS[f"lat.{s}"] = ("thorax", f"pit.{s}", f"elbow.{s}", "thorax", f"humerus.{s}", 1 / 2, out)
    HELPERS[f"pec.{s}"] = ("thorax", f"breast.{s}", f"elbow.{s}", "thorax", f"humerus.{s}", 1 / 2, out)
    HELPERS[f"hip1.{s}"] = ("pelvis", f"hip.{s}", f"knee.{s}", "pelvis", f"femur.{s}", 1 / 2, [0.0, -1.0, 0.0])
    HELPERS[f"knee1.{s}"] = (f"femur.{s}", f"knee.{s}", f"ankle.{s}", f"femur.{s}", f"shin.{s}", 1 / 2, None)
    HELPERS[f"elbow1.{s}"] = (f"humerus.{s}", f"elbow.{s}", f"wrist.{s}", f"humerus.{s}", f"ulna.{s}", 1 / 2, None)
for b, (parent, at, to, *_) in HELPERS.items():
    d = J[to] - J[at]
    J[f"{b}.tip"] = J[at] + d / np.linalg.norm(d) * 0.05
    RIG[b] = (at, f"{b}.tip", parent)
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


def rig_json():
    """The skeleton as AccrueKit's Body3D reads it (Resources/body-rig.json)."""
    out = []
    for b in ORDER:
        h, t, p = RIG[b]
        bone = {"name": b, "parent": p, "head": [round(float(x), 5) for x in J[h]],
                "tail": [round(float(x), 5) for x in J[t]],
                "rest": [round(float(x), 6) for x in REST[b].ravel()]}
        if b in HELPERS:
            bone["between"] = list(HELPERS[b][3:5])
            bone["share"] = round(HELPERS[b][5], 4)
            if HELPERS[b][6]:
                bone["rise"] = HELPERS[b][6]
        out.append(bone)
    g = girdle()
    g = {"center": [round(x, 5) for x in g["center"]], "radii": [round(x, 5) for x in g["radii"]],
         "blades": {s: {k: [round(float(x), 5) for x in v] for k, v in b.items()} for s, b in g["blades"].items()}}
    return {"bones": out, "girdle": g}


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


# A muscle is bound in one of three ways.
#
# SPANS: stretched between the bones at its two ends (name, bones at one end, bones at the
# other, options). The first six run from the trunk to the shoulder blade or the collarbone,
# which slide a long way over the ribs. The rest cross the shoulder or the hip, where the
# far bone swings through a wide arc: "far" means the muscle only counts as attached to that
# bone in its far half (the deltoid lies on the head of the humerus long before it reaches
# its insertion), "reach" is how far along the muscle the far bone's pull is felt.
SPANS = [(r"trapezius", ("head", "neck", "thorax"), ("clavicle", "scapula"), {}),
         (r"rhomboid", ("neck", "thorax"), ("scapula",), {}),
         (r"levator scapulae", ("neck",), ("scapula",), {}),
         (r"serratus anterior", ("thorax",), ("scapula",), {}),
         (r"pectoralis minor", ("thorax",), ("scapula",), {}),
         (r"subclavius", ("thorax",), ("clavicle",), {}),
         (r"clavicular part of deltoid", ("clavicle",), ("humerus",), {"far": True, "via": "delt"}),
         (r"deltoid", ("scapula",), ("humerus",), {"far": True, "via": "delt"}),
         (r"clavicular head of pectoralis major", ("clavicle",), ("humerus",), {"far": True, "via": "pec"}),
         (r"pectoralis major", ("thorax",), ("humerus",), {"far": True, "reach": 0.14, "via": "pec"}),
         (r"latissimus dorsi", ("thorax", "lumbar", "pelvis"), ("humerus",), {"far": True, "reach": 0.16, "via": "lat"}),
         (r"teres major", ("scapula",), ("humerus",), {"far": True, "via": "lat"}),
         (r"supraspinatus|infraspinatus|teres minor|subscapularis", ("scapula",), ("humerus",), {"far": True, "reach": 0.07}),
         (r"gluteus|piriformis|gemellus|obturator|quadratus femoris|iliacus|pectineus|adductor (brevis|longus)|"
          r"adductor minimus|tensor fasciae", ("pelvis",), ("femur",), {"far": True, "reach": 0.14}),
         (r"psoas", ("thorax", "lumbar", "pelvis"), ("femur",), {"far": True, "reach": 0.14})]
# BELLIES: lying along one bone and tied to another at an end (name, the bone it lies along,
# [(the bone it is tied to, how far along the muscle that pull reaches)]). A tie the muscle
# does not have (the short head of the biceps femoris never reaches the pelvis) is skipped.
BELLIES = [(r"coracobrachialis", "humerus", [("scapula", 0.08)]),
           (r"biceps brachii|long head of triceps", "humerus", [("scapula", 0.10), ("forearm", 0.06)]),
           (r"(lateral|medial) head of triceps|brachialis", "humerus", [("forearm", 0.06)]),
           (r"brachioradialis|extensor carpi|extensor digit|flexor carpi|palmaris|flexor digitorum superficialis|"
            r"pronator teres|anconeus|supinator", "forearm", [("humerus", 0.06)]),
           (r"adductor magnus|gracilis|sartorius|rectus femoris|biceps femoris|semimembranosus|semitendinosus|"
            r"iliotibial|vastus", "femur", [("pelvis", 0.12), ("shin", 0.07)]),
           (r"gastrocnemius|plantaris|popliteus", "shin", [("femur", 0.06)])]
# Every other muscle (the trunk, the neck, the deep forearm, the lower leg) follows the bones
# it touches, by distance.

if os.environ.get("SPANS"):
    SPANS = [x for x in SPANS if re.search(os.environ["SPANS"], x[0])]
TRUNK = ("head", "neck", "thorax", "lumbar", "pelvis")


def sided(bones, name):
    """Rig bones for a list like ("thorax", "scapula") on the side the muscle `name` is on."""
    m = re.search(r"\.(l|r)$", name)
    return [x if x in TRUNK else f"{x}.{m.group(1)}" for x in bones] if m else []


def span_of(name):
    """The bones at the two ends of a spanning muscle and its options, or None."""
    for rx, a, b, opt in SPANS:
        if re.search(r"\.(l|r)$", name) and re.search(rx, name, re.I):
            return [[x for x in sided(end, name) if x in trees] for end in (a, b)], opt
    return None


def belly_of(name):
    """(bone a muscle lies along, [(bones it is tied to, reach)]) or None."""
    for rx, along, pulls in BELLIES:
        if re.search(r"\.(l|r)$", name) and re.search(rx, name, re.I):
            return along, pulls
    return None


def between(a, b, via=None):
    """The helper bones that take a muscle round the joint from bone a to bone b, in order.
    `via` names the helper for a muscle from the trunk to the arm ("lat" or "pec")."""
    m = re.search(r"\.(l|r)$", a) or re.search(r"\.(l|r)$", b)
    if not m:
        return []
    if via:
        return [f"{via}.{m.group(1)}"]
    A, B = a.split(".")[0], b.split(".")[0]
    fore = {"ulna", "radius"} | {f"fore{i}" for i in range(1, TWIST + 1)}
    for near, far, helper in (({"scapula", "clavicle"}, {"humerus"}, "shoulder"), ({"pelvis", "lumbar", "thorax"}, {"femur"}, "hip1"),
                              ({"femur"}, {"shin"}, "knee1"), ({"humerus"}, fore, "elbow1")):
        if (A in near and B in far) or (B in near and A in far):
            return [f"{helper}.{m.group(1)}"]
    return []


def hats(t, n):
    """Shares of n stations evenly spaced along t = 0...1: each point belongs to the two it lies between."""
    x = t * (n - 1)
    return np.stack([np.clip(1 - np.abs(x - k), 0, 1) for k in range(n)], 1)


class Surface:
    """A muscle's own surface, for distances measured along it."""

    def __init__(self, o):
        import scipy.sparse as sp
        self.P = world(o)
        # Vertices at the same place are one point of the surface.
        _, first, same = np.unique(np.round(self.P / 2e-5).astype(np.int64), axis=0, return_index=True, return_inverse=True)
        self.same = same.ravel()
        self.k = len(first)
        self.Q = self.P[first]
        e = np.array([tuple(ed.vertices) for ed in o.data.edges], dtype=int).reshape(-1, 2)
        e = self.same[e]
        self.e = e = e[e[:, 0] != e[:, 1]]
        self.length = np.linalg.norm(self.Q[e[:, 0]] - self.Q[e[:, 1]], axis=1)
        # For smoothing, a point listens to its neighbours in proportion to how close they are:
        # counted equally, one long edge of a thin triangle drags a point away from the
        # points right next to it.
        near = 1.0 / np.maximum(self.length, 5e-4)
        nbr = sp.coo_matrix((np.r_[near, near], (np.r_[e[:, 0], e[:, 1]], np.r_[e[:, 1], e[:, 0]])), shape=(self.k, self.k)).tocsr()
        self.nbr, self.deg = nbr, np.maximum(np.asarray(nbr.sum(1)).ravel(), 1e-9)

    def gaps(self, bones):
        """Distance from every point to each of `bones`."""
        return np.stack([trees[b].query(self.Q)[0] for b in bones], 1)

    def shares(self, bones, reach=0.012):
        """How the bones of one end share a point: those the muscle reaches, nearest first."""
        D = self.gaps(bones)
        keep = [j for j in range(len(bones)) if D[:, j].min() < reach] or [int(D.min(0).argmin())]
        w = np.zeros_like(D)
        w[:, keep] = 1.0 / np.maximum(D[:, keep], 0.002) ** 4
        return w / w.sum(1, keepdims=True), D[:, keep].min(1)

    def along(self, seeds, gap):
        """Distance along the surface from the nearest of the points `seeds`."""
        import scipy.sparse as sp
        from scipy.sparse.csgraph import dijkstra
        k, e = self.k, self.e
        # One extra point, joined to the seeds at no distance.
        rows = np.r_[e[:, 0], e[:, 1], seeds, np.full(len(seeds), k)]
        cols = np.r_[e[:, 1], e[:, 0], np.full(len(seeds), k), seeds]
        G = sp.coo_matrix((np.r_[self.length, self.length, np.full(2 * len(seeds), 1e-9)], (rows, cols)), shape=(k + 1, k + 1)).tocsr()
        d = dijkstra(G, indices=k)[:k]
        # A loose piece the surface does not reach: straight-line distance instead.
        d[~np.isfinite(d)] = gap[~np.isfinite(d)] + 0.02
        return np.maximum(d, 1e-6)

    def smooth(self, t, rounds=4):
        for _ in range(rounds):
            t = 0.5 * t + 0.5 * (self.nbr @ t) / self.deg
        return t


def ease(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def weigh_span(o, ends, reach=0.012, sharp=1.5, far=False, **opt):
    """Weights for a muscle stretched between the bones at its two ends.

    Where the muscle touches a bone of one end it moves with that end. In between, each point
    is shared by how far along the muscle's own surface it is from either end, so a sheet
    stays pinned along its whole line of origin and stretches evenly toward its insertion.
    Within an end, a point goes with the bones of that end nearest to it. Helper bones take
    the middle of the muscle round the joint.
    """
    reach_of_pull = opt.get("reach", 0.12)
    S = Surface(o)
    (split0, gap0), (split1, gap1) = S.shares(ends[0], reach), S.shares(ends[1], reach)
    seeds = np.nonzero((gap0 < max(0.006, gap0.min() + 0.004)) & (gap0 <= gap1))[0]
    if not len(seeds):
        seeds = np.array([gap0.argmin()])
    far0 = S.along(seeds, gap0)
    if far:
        # The far end: only the half of the muscle away from its origin can be attached there,
        # and a muscle that ends in a tendon sheet short of the bone is held by its far tip.
        half = far0 > 0.5 * far0.max()
        seeds = np.nonzero(half & (gap1 < max(0.006, gap1[half].min() + 0.004)))[0]
        if gap1[half].min() > 0.02:
            seeds = np.nonzero(far0 > 0.9 * far0.max())[0]
    else:
        seeds = np.nonzero((gap1 < max(0.006, gap1.min() + 0.004)) & (gap1 <= gap0))[0]
    if not len(seeds):
        seeds = np.array([gap1.argmin()])
    far1 = S.along(seeds, gap1)
    t = far0 ** sharp / (far0 ** sharp + far1 ** sharp)  # 0 at the first end, 1 at the second
    # The second end is the one that moves (the blade swings on a long arm), so its pull stops
    # a hand's breadth from where the muscle meets it: even a small share of that swing would
    # drag the far side of a broad sheet through its neighbours. It fades over that whole
    # breadth, because a steeper fade folds the sheet when the blades are squeezed together.
    t = S.smooth(t * ease((reach_of_pull - far1) / reach_of_pull))
    mid = between(ends[0][0], ends[1][0], opt.get("via"))
    H = hats(t, len(mid) + 2)
    W = np.c_[split0 * H[:, :1], H[:, 1:-1], split1 * H[:, -1:]][S.same]
    return list(ends[0]) + mid + list(ends[1]), W


def weigh_belly(o, along, pulls, name):
    """Weights for a muscle lying along one bone and tied to others at its ends, or None when
    the muscle is nowhere near that bone.

    The muscle moves with the bone it lies along. Each tie pulls the end of the muscle next to
    it: fully where the muscle meets that bone, fading to nothing `reach` away along the
    muscle's own surface, with helper bones taking the stretch in between round the joint.
    """
    S = Surface(o)
    near = {b: t.query(S.Q)[0] for b, t in trees.items()}

    def resolve(word):
        m = re.search(r"\.(l|r)$", name).group(1)
        if word == "forearm":
            return [b for b in near if re.match(rf"(ulna|radius|hand|f\d\w)\.{m}$", b) and near[b].min() < 0.012]
        return [b for b in sided([word], name) if b in near and near[b].min() < 0.012]

    belly = sorted(resolve(along), key=lambda b: not b.startswith("ulna"))
    if not belly:
        return None
    D = np.stack([near[b] for b in belly], 1)
    base = 1.0 / np.maximum(D, 0.002) ** 4
    if base.shape[1] > 3:
        base[base < np.sort(base, 1)[:, -3][:, None]] = 0
    base /= base.sum(1, keepdims=True)
    lead = belly[0]
    axis = J[RIG[lead][1]] - J[RIG[lead][0]]
    s = (S.Q - J[RIG[lead][0]]) @ axis / np.linalg.norm(axis)
    lo, hi = s.min(), s.max()
    names, cols, kept = list(belly), [], np.ones(S.k)
    for word, reach in pulls:
        tie = [b for b in resolve(word) if b not in belly]
        if not tie:
            continue
        # The tie is at the end of the muscle on that bone's side of the joint.
        above = RIG[lead][2] is not None and (tie[0] == RIG[lead][2] or tie[0] == RIG.get(RIG[lead][2], (0, 0, None))[2])
        zone = s < lo + 0.35 * (hi - lo) if above else s > hi - 0.35 * (hi - lo)
        Dt = np.stack([near[b] for b in tie], 1)
        gap = Dt.min(1)
        if gap[zone].min() > 0.012:
            continue
        seeds = np.nonzero(zone & (gap < max(0.006, gap[zone].min() + 0.004)))[0]
        t = S.smooth(ease((reach - S.along(seeds, gap)) / reach))
        mid = between(lead, tie[0])
        H = hats(t, len(mid) + 2)
        split = 1.0 / np.maximum(Dt, 0.002) ** 4
        split /= split.sum(1, keepdims=True)
        kept -= 1 - H[:, 0]
        names += mid + tie
        cols += [H[:, 1:-1], split * H[:, -1:]]
    W = np.c_[base * np.clip(kept, 0, 1)[:, None], *cols]
    W /= W.sum(1, keepdims=True)
    return names, W[S.same]


def weigh_near(o, candidates, power=4.0):
    """Weights by distance to the bones a mesh touches: the three nearest share each point."""
    P = world(o)
    names = list(candidates)
    D = np.stack([trees[b].query(P)[0] for b in names], 1)
    W = 1.0 / np.maximum(D, 0.002) ** power
    if W.shape[1] > 3:
        cut = np.sort(W, 1)[:, -3][:, None]
        W[W < cut] = 0
    return names, W / W.sum(1, keepdims=True)


def trim_cuffs(o):
    """End the skin of the hands and feet on a straight line instead of the triangles' zigzag."""
    import bmesh
    back = np.linalg.inv(np.array(o.matrix_world))
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for s in "lr":
        axis = J[f"f3-1.{s}"] - J[f"wrist.{s}"]
        axis /= np.linalg.norm(axis)
        for at, no, reach in ((J[f"ankle.{s}"] + [0, 0, CUFF["foot"]], np.array([0, 0, 1.0]), 0.09),
                              (J[f"wrist.{s}"] - axis * CUFF["hand"], -axis, 0.07)):
            co, no = back[:3, :3] @ at + back[:3, 3], back[:3, :3] @ no
            near = [v for v in bm.verts if np.linalg.norm(np.array(v.co) - co) < reach]
            pick = set(near)
            geom = near + [e for e in bm.edges if e.verts[0] in pick and e.verts[1] in pick]
            geom += [f for f in bm.faces if all(v in pick for v in f.verts)]
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, clear_outer=True)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(o.data)
    bm.free()


# Where the skin of a foot ends above the ankle joint and of a hand above the wrist, and how
# far below that edge it starts to stay with the leg or forearm.
CUFF = {"foot": 0.024, "hand": 0.014, "ring": 0.03}


def weigh_cuffs(o, names, W):
    """The rim of a foot or hand stays on the shin or forearm; below it the skin turns with the joint.

    By distance alone the back of the heel follows the foot all the way up, and the rim swings
    clear of the leg when the ankle bends.
    """
    P = world(o)
    names = list(names)
    for s in "lr":
        axis = J[f"f3-1.{s}"] - J[f"wrist.{s}"]
        axis /= np.linalg.norm(axis)
        # Behind the ankle the ring is deeper: the skin over the Achilles tendon folds over a
        # longer stretch than the skin on the instep.
        heel = CUFF["ring"] + 0.035 * ease((P[:, 1] - J[f"ankle.{s}"][1]) / 0.03)
        up = {f"shin.{s}": (P[:, 2] - J[f"ankle.{s}"][2], CUFF["foot"], heel,
                            np.linalg.norm(P - J[f"ankle.{s}"], axis=1) < 0.12),
              f"radius.{s}": (-(P - J[f"wrist.{s}"]) @ axis, CUFF["hand"], CUFF["ring"],
                              np.linalg.norm(P - J[f"wrist.{s}"], axis=1) < 0.08)}
        for b, (h, rim, ring, here) in up.items():
            t = np.where(here, ease(1 - (rim - h) / ring), 0.0)
            if b not in names:
                names.append(b)
                W = np.c_[W, np.zeros(len(W))]
            W = W * (1 - t)[:, None]
            W[:, names.index(b)] += t
    return names, W


def assign(o, names, W):
    """Write weights as the mesh's vertex groups, the forearm's share spread along its twist bones."""
    merged = {}
    for j, b in enumerate(names):  # a bone can come up twice (two ties through the same helper)
        merged[b] = merged.get(b, 0) + W[:, j]
    names, W = twist_split(world(o), list(merged), np.stack(list(merged.values()), 1))
    for j, b in enumerate(names):
        vg = o.vertex_groups.new(name=b)
        for i in np.nonzero(W[:, j] > 0.01)[0]:
            vg.add([int(i)], float(W[i, j]), "REPLACE")


def skin_helpers(V, bones, W):
    """Hand the skin across a joint to that joint's helper bone, so it bends in two steps.

    Skin shared half and half by the two bones of a joint shrinks toward the joint's axis when
    the joint turns far. Where both bones pull, the smaller pull and as much of the larger go
    to the helper instead, which turns halfway between them.
    """
    bones, W = list(bones), W.copy()

    def col(name):
        nonlocal W
        if name not in bones:
            bones.append(name)
            W = np.c_[W, np.zeros(len(W))]
        return bones.index(name)

    def hand_over(A, B, shares, where=1.0):
        A, B = [bones.index(b) for b in A if b in bones], [bones.index(b) for b in B if b in bones]
        if not A or not B:
            return
        a, b = W[:, A].sum(1), W[:, B].sum(1)
        m = np.minimum(a, b) * where
        W[:, A] *= (1 - m / np.maximum(a, 1e-9))[:, None]
        W[:, B] *= (1 - m / np.maximum(b, 1e-9))[:, None]
        for name, share in shares:
            j = col(name)
            W[:, j] += 2 * m * share

    for s in "lr":
        hand_over(["pelvis", "lumbar"], [f"femur.{s}"], [(f"hip1.{s}", 1.0)])
        hand_over([f"femur.{s}"], [f"shin.{s}"], [(f"knee1.{s}", 1.0)])
        hand_over([f"humerus.{s}"], [f"ulna.{s}", f"radius.{s}"], [(f"elbow1.{s}", 1.0)])
        # At the shoulder only next to the joint: with the arm overhead a bone halfway to it
        # points out sideways, and skin further down the arm that followed it would spread into
        # a web between the arm and the ribs.
        close = ease((0.11 - np.linalg.norm(V - J[f"gh.{s}"], axis=1)) / 0.05)
        hand_over(["thorax", f"scapula.{s}", f"clavicle.{s}"], [f"humerus.{s}"], [(f"shoulder.{s}", 1.0)], close)
    return bones, W / W.sum(1, keepdims=True)


def tuck_bones(depth=0.0015):
    """Pull the points of hand and foot bones that reach the skin back under it.

    The MakeHuman hands and feet are fitted over the Z-Anatomy bones by a few joints, so a
    heel or a fingertip can come through; the bone is drawn under the skin and would show.
    """
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    moved = 0
    for skin in [o for o in objs if kind(o) not in ("muscle", "bone") and base(o.name) != "Head"]:
        bvh = BVHTree.FromPolygons([Vector(p) for p in world(skin)], [tuple(f.vertices) for f in skin.data.polygons])
        for o in objs:
            if kind(o) != "bone" or not re.match(r"(foot|toes|hand|f\d)", bone_of(base(o.name))):
                continue
            back = np.linalg.inv(np.array(o.matrix_world))
            for i, p in enumerate(world(o)):
                at, normal, _, gap = bvh.find_nearest(Vector(p))
                if at is None or gap > 0.02:
                    continue
                if (Vector(p) - at).dot(normal) > -depth:
                    q = np.array(at - normal * depth)
                    o.data.vertices[i].co = back[:3, :3] @ q + back[:3, 3]
                    moved += 1
    print("hand and foot bone points tucked under the skin", moved)


def bind_all():
    """Bind every mesh in the file: bones rigidly, muscles and skin by distance."""
    how = {}
    for o in objs:
        k, name = kind(o), base(o.name)
        if k == "bone":
            vg = o.vertex_groups.new(name=bone_of(name))
            vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
        else:
            if k != "muscle" and name != "Head":
                trim_cuffs(o)
            made = None
            if k == "muscle" and span_of(name):
                ends, opt = span_of(name)
                made = weigh_span(o, ends, **opt)
                how[name] = "span"
            elif k == "muscle" and belly_of(name):
                made = weigh_belly(o, *belly_of(name), name)
                how[name] = "belly" if made else "near"
            if made is None:
                P = world(o)
                d = {b: t.query(P)[0].min() for b, t in trees.items()}
                if k == "muscle":
                    d = {b: x for b, x in d.items() if may_follow(name, b)}
                reach = 0.012 if k == "muscle" else 0.03
                if k != "muscle":  # skin of the hands and feet: limb bones only
                    d = {b: x for b, x in d.items() if re.match(r"(hand|f\d|radius|ulna|foot|toes|shin)", b)}
                cand = [b for b, x in d.items() if x < reach] or [min(d, key=d.get)]
                if name == "Head":
                    cand = ["head"]
                made = weigh_near(o, cand, 4.0 if k == "muscle" else 6.0)
                if k != "muscle" and name != "Head":
                    made = weigh_cuffs(o, *made)
            assign(o, *made)
        mod = o.modifiers.new("arm", "ARMATURE")
        mod.object = arm
        o.parent = arm
    tuck_bones()
    print("bound", len(objs), "meshes;", sum(v == "span" for v in how.values()), "spans,",
          sum(v == "belly" for v in how.values()), "bellies")


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

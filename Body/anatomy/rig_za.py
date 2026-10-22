"""Rig the exported Z-Anatomy model and bake a push-up.

    python rig_za.py za.glb pushup.glb

Reads the static model written by export_za.py, builds an armature whose joints
sit at joint centres measured on the Z-Anatomy bones, binds every mesh to it,
and keys a push-up computed here (forward kinematics plus two-bone arm IK with
the hands fixed on the floor). Skeletal meshes move rigidly with their own
bone; each muscle blends between the bones it touches, so it stretches between
its attachments.

The timeline holds several clips one after another (see CLIPS); the viewer
plays each range on its own.
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

SRC, OUT = sys.argv[-2], sys.argv[-1]
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
    for k in range(2, 6):
        for i in range(1, 5):
            J[f"f{k}-{i}.{s}"] = ht[f"finger-{k}-{i}"]
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
    for k in range(2, 6):
        RIG[f"f{k}a.{s}"] = (f"f{k}-1.{s}", f"f{k}-2.{s}", f"hand.{s}")
        RIG[f"f{k}b.{s}"] = (f"f{k}-2.{s}", f"f{k}-3.{s}", f"f{k}a.{s}")
        RIG[f"f{k}c.{s}"] = (f"f{k}-3.{s}", f"f{k}-4.{s}", f"f{k}b.{s}")
ORDER = list(RIG)  # parents come before children

ORDW = {"second": 2, "third": 3, "fourth": 4, "fifth": 5}


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
    if fm and fm.group(2) in ORDW:
        return f"f{ORDW[fm.group(2)]}{'abc'['proximal middle distal'.split().index(fm.group(1))]}.{s}"
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
    for j, b in enumerate(names):
        vg = o.vertex_groups.new(name=b)
        nz = np.nonzero(W[:, j] > 0.01)[0]
        for i in nz:
            vg.add([int(i)], float(W[i, j]), "REPLACE")


for o in objs:
    k = kind(o)
    if k == "bone":
        vg = o.vertex_groups.new(name=bone_of(base(o.name)))
        vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    else:
        P = world(o)
        d = {b: t.query(P)[0].min() for b, t in trees.items()}
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
STERNUM = np.concatenate([pts("Body of sternum"), pts("Xiphoid process"), pts("Manubrium of sternum")])
FEET_Y = 0.75  # where the toes rest
MTP_Z = 0.022  # height of the toe joints above the floor


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


def pose(p, wrist_target=None):
    """Global rotation G and head position H of every bone for pose parameters p."""
    G, H = {}, {}
    Pl, Pu = Rx(D(90 - p["low"])), Rx(D(90 - p["up"]))
    # Feet and toes, then the body is hung from the toes.
    Gf = Pl @ Rx(D(p["ankle"]))
    hs = []
    for s in "lr":
        G[f"foot.{s}"] = Gf
        t0 = J[f"toetip.{s}"] - J[f"mtp.{s}"]
        G[f"toes.{s}"] = frame_map(t0, np.array([0, 0, -1.0]), np.array([0, -1.0, 0]), np.array([0, 0, -1.0]))
        M = np.array([J[f"mtp.{s}"][0], FEET_Y, MTP_Z])
        A = M - Gf @ (J[f"mtp.{s}"] - J[f"ankle.{s}"])
        hs.append(A - Pl @ (J[f"ankle.{s}"] - J["pelvis"]))
    H["pelvis"] = np.mean(hs, 0)
    G["pelvis"] = Pl
    G["lumbar"] = slerp_m(Pl, Pu, 0.5)
    G["thorax"] = Pu
    G["neck"] = Pu @ Rx(D(p.get("neck", 0)))
    G["head"] = G["neck"] @ Rx(D(p.get("headtilt", 0)))
    for s in "lr":
        G[f"femur.{s}"] = G[f"shin.{s}"] = Pl
    for s, sx in (("l", 1), ("r", -1)):
        Gc = Pu @ Rz(-sx * D(p["protract"]))
        G[f"clavicle.{s}"] = Gc
        G[f"scapula.{s}"] = Gc @ Rz(-sx * D(p["protract"]) * 0.5) @ Ry(-sx * D(p["upward"]))
    fk(G, H, upto="scapula")
    if wrist_target is None:
        return G, H
    for s, sx in (("l", 1), ("r", -1)):
        gh = H[f"humerus.{s}"]
        Gh = frame_map(PALM[s][0], PALM[s][1],
                       np.array([sx * math.sin(D(p["fingers_out"])), -math.cos(D(p["fingers_out"])), 0]),
                       np.array([0, 0, -1.0]))
        W = wrist_target[s].copy()
        for _ in range(4):
            u = W - gh
            dist = min(np.linalg.norm(u), L_UP + L_FORE - 1e-4)
            u /= np.linalg.norm(u)
            pole = np.array([sx * math.sin(D(p["flare"])), math.cos(D(p["flare"])), 0.0])
            v = pole - u * (pole @ u)
            v /= np.linalg.norm(v)
            ca = (L_UP ** 2 + dist ** 2 - L_FORE ** 2) / (2 * L_UP * dist)
            al = math.acos(max(-1, min(1, ca)))
            E = gh + L_UP * (math.cos(al) * u + math.sin(al) * v)
            d1 = (E - gh) / L_UP
            f1 = (gh + u * dist - E)
            f1 /= np.linalg.norm(f1)
            a1 = np.cross(d1, f1)
            a1 /= np.linalg.norm(a1)
            d0 = (J[f"elbow.{s}"] - J[f"gh.{s}"])
            f0 = (J[f"wrist.{s}"] - J[f"elbow.{s}"])
            G[f"humerus.{s}"] = frame_map(d0, HINGE[s], d1, a1)
            G[f"ulna.{s}"] = frame_map(f0, HINGE[s], f1, a1)
            # Pronation: turn the radius about the radio-ulnar axis until the
            # wrist needs no twist to put the palm flat.
            pax = J[f"ulnhead.{s}"] - J[f"radhead.{s}"]
            best = None
            for deg in range(-90, 181, 3):
                Gr = G[f"ulna.{s}"] @ Raxis(pax, sx * D(deg))
                Rw = Gr.T @ Gh  # wrist rotation in rest axes
                fa = f0 / np.linalg.norm(f0)
                sn, cs = _twist(Rw, fa)
                twist = abs(math.atan2(sn, cs))
                if best is None or twist < best[0]:
                    best = (twist, deg, Gr)
            G[f"radius.{s}"] = best[2]
            PRON[s] = best[1]
            G[f"hand.{s}"] = Gh
            fk(G, H, upto=f"hand.{s}")
            W = W + (wrist_target[s] - H[f"hand.{s}"])
        for k in range(2, 6):
            for seg in "abc":
                G[f"f{k}{seg}.{s}"] = Gh @ STRAIGHT[f"f{k}{seg}.{s}"]
    fk(G, H)
    return G, H


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


def sternum_low(G, H):
    P = (STERNUM - HEAD["thorax"]) @ G["thorax"].T + H["thorax"]
    return P[:, 2].min()


def hand_drop(s, Gh):
    """Wrist height that puts the palm skin on the floor."""
    hand = [o for o in objs if base(o.name) == "Hands and feet"][0]
    P = world(hand)
    g = hand.vertex_groups.get(f"hand.{s}")
    idx = [v.index for v in hand.data.vertices if any(x.group == g.index and x.weight > 0.6 for x in v.groups)]
    Q = (P[idx] - J[f"wrist.{s}"]) @ Gh.T
    return -Q[:, 2].min() + 0.002


# ---------------------------------------------------------------- the push-up
GOOD = dict(ankle=8, protract=0, upward=0, flare=45, fingers_out=8, neck=0, headtilt=0)


def solve_top(p):
    """Trunk angle at the top (elbows almost straight), and where the hands go."""
    lo, hi = 5.0, 40.0
    for _ in range(30):
        mid = (lo + hi) / 2
        q = dict(p, low=mid, up=mid)
        G, H = pose(q)
        reach = math.hypot(H["humerus.l"][2] - HAND_Z, HAND_OUT)
        if reach > (L_UP + L_FORE) * 0.99:
            hi = mid
        else:
            lo = mid
    G, H = pose(dict(p, low=lo, up=lo))
    tgt = {}
    for s, sx in (("l", 1), ("r", -1)):
        gh = H[f"humerus.{s}"]
        tgt[s] = np.array([gh[0] + sx * HAND_OUT, gh[1], HAND_Z])
    return lo, tgt


Gh0 = frame_map(PALM["l"][0], PALM["l"][1], np.array([0, -1.0, 0]), np.array([0, 0, -1.0]))
HAND_Z = hand_drop("l", Gh0)
HAND_OUT = 0.045  # index finger under the outer edge of the shoulder (Suprak 2013)
print("wrist height", round(HAND_Z, 3))
TOP, TARGET = solve_top(dict(GOOD, protract=8, upward=-5))


def elbow_flex(G, H):
    u = H["ulna.l"] - H["humerus.l"]
    w = H["hand.l"] - H["ulna.l"]
    return math.degrees(math.acos(np.clip(u @ w / np.linalg.norm(u) / np.linalg.norm(w), -1, 1)))


def solve_bottom(p, flex=108.0):
    """Lowest trunk angle. Labs stop at 90-105 degrees of elbow flexion (Borreani 2015,
    Suprak 2013); test standards want the chest near the floor. With the forearms
    near vertical the chest is still high at 90, so go a little past the lab range."""
    lo, hi = -10.0, TOP
    for _ in range(30):
        mid = (lo + hi) / 2
        G, H = pose(dict(p, low=mid, up=mid), TARGET)
        if elbow_flex(G, H) < flex:
            hi = mid
        else:
            lo = mid
    return hi


# Shoulder blade, from Suprak 2013 and Lunden 2010: from bottom to top it turns
# about 15 degrees around the chest wall and 6 degrees downward; the plus adds
# about 12 degrees more turn and 5 degrees less upward rotation. The clavicle
# carries two thirds of the turn (see pose()).
SCAP_BOTTOM = dict(protract=-10 / 1.5, upward=6)
SCAP_PLUS = dict(protract=12 / 1.5, upward=-5)
BOTTOM = solve_bottom(dict(GOOD, **SCAP_BOTTOM))
print("trunk angle top", round(TOP, 1), "bottom", round(BOTTOM, 1))


def ease(t):
    return 0.5 - 0.5 * math.cos(math.pi * max(0, min(1, t)))


def rep(t, fault=None):
    """Pose parameters at time t (s) in one rep: 1 s plank, 2 s down, 0.5 s pause, 1 s up, 0.5 s plus."""
    p = dict(GOOD)
    if t < 1.0:
        d, plus = 0.0, 1.0
    elif t < 3.0:
        d, plus = ease((t - 1.0) / 2.0), 1 - ease((t - 1.0) / 0.6)
    elif t < 3.5:
        d, plus = 1.0, 0.0
    elif t < 4.5:
        d, plus = 1 - ease((t - 3.5) / 1.0), 0.0
    else:
        d, plus = 0.0, ease((t - 4.5) / 0.5)
    p["low"] = TOP + (BOTTOM - TOP) * d
    p["up"] = p["low"]
    # Shoulder blades: pulled back at the bottom, pushed apart ("plus") at the top.
    p["protract"] = SCAP_BOTTOM["protract"] * d + SCAP_PLUS["protract"] * plus
    p["upward"] = SCAP_BOTTOM["upward"] * d + SCAP_PLUS["upward"] * plus
    if fault == "sag":
        # Hips drop 5 degrees; the chest tilts up so the shoulders stay where they were.
        want = pose(p)[1]["humerus.l"][2]
        base_ = p["low"]
        lo, hi = base_, base_ + 30
        for _ in range(25):
            mid = (lo + hi) / 2
            if pose(dict(p, low=base_ - 5, up=mid))[1]["humerus.l"][2] < want:
                lo = mid
            else:
                hi = mid
        p["low"], p["up"] = base_ - 5, lo
    if fault == "flare":
        p["flare"] = 85
    if fault == "head":
        p["neck"] = 22
        p["headtilt"] = 8
    return p


REP = 5.0
CLIPS = [("good", None), ("sag", "sag"), ("flare", "flare"), ("head", "head")]
scene = bpy.context.scene
scene.render.fps = FPS
nframes = int(REP * FPS)
pb = arm.pose.bones
for b in ORDER:
    pb[b].rotation_mode = "QUATERNION"
def line_angle(H):
    """Bend at the hips between ankle-hip and hip-upper-back lines, in the side view."""
    sh, hip = H["neck"], H["pelvis"]
    ank = (H["foot.l"] + H["foot.r"]) / 2
    a1, a2 = hip - ank, sh - hip
    return math.degrees(math.atan2(a2[2], -a2[1]) - math.atan2(a1[2], -a1[1]))


G0, H0 = pose(dict(GOOD, low=TOP, up=TOP, protract=0, upward=0))
LINE0 = line_angle(H0)


def metrics(p, G, H):
    """Readouts the page shows for one frame."""
    out = {}
    el, fl = [], []
    up = H["neck"] - H["pelvis"]
    up /= np.linalg.norm(up)
    ap = G["thorax"] @ np.array([0, -1.0, 0])  # chest direction
    for s in "lr":
        u = H[f"ulna.{s}"] - H[f"humerus.{s}"]
        w = H[f"hand.{s}"] - H[f"ulna.{s}"]
        el.append(180 - math.degrees(math.acos(np.clip(u @ w / np.linalg.norm(u) / np.linalg.norm(w), -1, 1))))
        # Flare: upper arm against the trunk, seen from above (on the plane of the back).
        h = u - ap * (u @ ap)
        fl.append(math.degrees(math.acos(np.clip(h @ -up / np.linalg.norm(h), -1, 1))))
    ang = line_angle(H) - LINE0
    out["elbow"] = round(float(np.mean(el)), 1)
    out["flare"] = round(float(np.mean(fl)), 1)
    out["hip"] = round(-ang, 1)  # + piked, - sagging
    out["chest"] = round(sternum_low(G, H), 3)
    out["neck"] = p.get("neck", 0)
    out["neckOk"] = out["neck"] < 10
    out["elbowOk"] = True
    out["flareOk"] = out["flare"] <= 60
    out["hipOk"] = abs(out["hip"]) <= 6
    pr = p["protract"]
    out["scap"] = "Blades apart" if pr > 3 else "Blades together" if pr < -6 else "Blades gliding"
    return out


frames = {}
for ci, (clip, fault) in enumerate(CLIPS):
    frames[clip] = []
    for f in range(nframes + 1):
        t = f / FPS
        p = rep(t, fault)
        G, H = pose(p, TARGET)
        fr = ci * (nframes + 1) + f + 1
        for b in ORDER:
            pa = RIG[b][2]
            Gp = G[pa] if pa else np.eye(3)
            B = REST[b].T @ Gp.T @ G[b] @ REST[b]
            pb[b].rotation_quaternion = Matrix(B.tolist()).to_quaternion()
            pb[b].keyframe_insert("rotation_quaternion", frame=fr)
            if pa is None:
                pb[b].location = REST[b].T @ (H[b] - HEAD[b])
                pb[b].keyframe_insert("location", frame=fr)
        frames[clip].append(metrics(p, G, H))
scene.frame_start, scene.frame_end = 1, len(CLIPS) * (nframes + 1)
for c, fr in frames.items():
    for k in (0, int(2 * FPS), int(3.2 * FPS), int(4.8 * FPS)):
        print(c, k / FPS, fr[k], "pronation", PRON.get("l"))

import json  # noqa: E402

meta = {"fps": FPS, "rep": REP, "clips": [{"name": c, "start": i * (nframes + 1) / FPS, "end": (i * (nframes + 1) + nframes) / FPS}
                                         for i, (c, _) in enumerate(CLIPS)],
        "top": TOP, "bottom": BOTTOM, "frames": frames}
open(os.path.splitext(OUT)[0] + "-meta.js", "w").write("window.PUSHUP_META = " + json.dumps(meta, separators=(",", ":")) + ";\n")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_extras=True,
                          export_materials="PLACEHOLDER", export_normals=True, export_texcoords=False,
                          export_animations=True, export_skins=True)
print("wrote", OUT)

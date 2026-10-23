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



def bind_all():
    """Bind every mesh in the file: bones rigidly, muscles and skin by distance."""
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

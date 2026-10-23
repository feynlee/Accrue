"""Rig the exported Z-Anatomy model and bake a push-up.

    python rig_za.py za.glb pushup.glb

Keys a push-up on the shared rig (rigbase.py): forward kinematics plus two-bone
arm IK with the hands fixed on the floor.

The timeline holds several clips one after another (see CLIPS); the viewer
plays each range on its own.
"""
import json
import math
import os
import sys

import numpy as np

os.environ["ZA_GLB"] = sys.argv[-2]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rigbase import *  # noqa: E402,F401,F403
from rigbase import _twist  # noqa: E402

OUT = sys.argv[-1]
bind_all()

STERNUM = np.concatenate([pts("Body of sternum"), pts("Xiphoid process"), pts("Manubrium of sternum")])
FEET_Y = 0.75  # where the toes rest
MTP_Z = 0.022  # height of the toe joints above the floor


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


def reach_cap(p):
    def over(th):
        H = pose(dict(p, low=th, up=th))[1]
        return max(np.linalg.norm(H[f"humerus.{s}"] - TARGET[s]) for s in "lr") > (L_UP + L_FORE) * 0.99
    if not over(p["low"]):
        return p["low"]
    lo, hi = BOTTOM, p["low"]
    for _ in range(25):
        mid = (lo + hi) / 2
        if over(mid):
            hi = mid
        else:
            lo = mid
    return lo


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
    # Hands stay on the floor: when the shoulder blades move, the trunk angle
    # gives way so the arms never have to reach further than straight.
    p["low"] = p["up"] = reach_cap(p)
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
        key_pose(arm, G, H, fr)
        frames[clip].append(metrics(p, G, H))
scene.frame_start, scene.frame_end = 1, len(CLIPS) * (nframes + 1)
for c, fr in frames.items():
    for k in (0, int(2 * FPS), int(3.2 * FPS), int(4.8 * FPS)):
        print(c, k / FPS, fr[k], "pronation", PRON.get("l"))

meta = {"fps": FPS, "rep": REP, "clips": [{"name": c, "start": i * (nframes + 1) / FPS, "end": (i * (nframes + 1) + nframes) / FPS}
                                         for i, (c, _) in enumerate(CLIPS)],
        "top": TOP, "bottom": BOTTOM, "frames": frames}
open(os.path.splitext(OUT)[0] + "-meta.js", "w").write("window.PUSHUP_META = " + json.dumps(meta, separators=(",", ":")) + ";\n")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_extras=True,
                          export_materials="PLACEHOLDER", export_normals=True, export_texcoords=False,
                          export_animations=True, export_skins=True)
print("wrote", OUT)

"""Skin-only figure climbing stairs, on the shared Z-Anatomy rig.

    python climb_za.py za.glb skin.npz climb.glb

za.glb is the static model from export_za.py (its bones place the joints);
skin.npz is Z-Anatomy's body surface from export_skin.py. Only the skin goes
into climb.glb: no muscles or bones, dressed in a top, shorts and shoes.

One loop is one stride (two steps up) at 90 steps a minute. The figure climbs
two steps and the loop jumps back two steps, so on a staircase that repeats
the loop is seamless. Clips: good form and three faults (CLIPS). Sources for
every number are in Catalog/research/stair-climbing.md.
"""
import json
import math
import os
import re
import sys

import numpy as np

os.environ["ZA_GLB"] = sys.argv[-3]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rigbase import *  # noqa: E402,F401,F403
import bmesh  # noqa: E402  (needs bpy loaded first)

SKIN, OUT = sys.argv[-2], sys.argv[-1]

# ---------------------------------------------------------------- stairs
RISE, GOING = 0.175, 0.28  # a common step: 17.5 cm up, 28 cm deep
SPM = 90  # steps per minute
STRIDE = 2 * 60 / SPM  # seconds per loop (two steps)

# ---------------------------------------------------------------- skin
z = np.load(SKIN)
V0, F0, R0, NAMES = z["V"], z["F"], z["R"], [str(n) for n in z["names"]]
# The region patches share their borders: weld them into one surface.
key = np.round(V0 / 2e-5).astype(np.int64)
_, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
inv = inv.ravel()
V = V0[first].copy()
F = inv[F0]
keep = (F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 0] != F[:, 2])
F, R = F[keep], R0[keep]
print("skin", len(V0), "->", len(V), "verts,", len(F), "tris")

nbr = [set() for _ in range(len(V))]
for a, b, c in F:
    nbr[a].update((b, c)); nbr[b].update((a, c)); nbr[c].update((a, b))
nbr = [np.fromiter(s, int) for s in nbr]

# Modesty: the genital region is relaxed onto the surface spanned by its
# border (a membrane), and the shorts cover it.
uro = np.array(["Urogenital" in NAMES[r] for r in R])
inside = np.zeros(len(V), bool)
inside[np.unique(F[uro])] = True
inside[np.unique(F[~uro])] = False
idx = np.nonzero(inside)[0]
for _ in range(400):
    V[idx] = np.array([V[nbr[i]].mean(0) if len(nbr[i]) else V[i] for i in idx])
print("membrane verts", len(idx))
# Shoes: relax the toes into one rounded toe box (Taubin smoothing keeps the volume).
toe = np.zeros(len(V), bool)
toe[np.unique(F[np.array([bool(re.search(r"digits of foot|\(foot\)", NAMES[r])) for r in R])])] = True
idx = np.nonzero(toe)[0]
for it in range(30):
    lam = 0.5 if it % 2 == 0 else -0.53
    V[idx] += lam * (np.array([V[nbr[i]].mean(0) for i in idx]) - V[idx])

# ---------------------------------------------------------------- weights
bones = list(trees)
# Each skin region may only follow the bones of its own body part, so the thigh
# does not follow the fingers hanging next to it.
PART = [
    (r"hand|palm|wrist|Radial foveola|^Nail plate\.|^Perionyx\.", r"^(hand|f\d|radius|ulna)"),
    (r"forearm|elbow|Cubital", r"^(humerus|ulna|radius|hand)"),
    (r"region of arm|Deltoid|Deltopectoral|bicipital", r"^(humerus|scapula|clavicle|thorax|ulna)"),
    (r"thigh|knee|leg|ankle|foot|Heel|Sole|malleol|Metatarsal|arch|Hallucial|Gluteal|Hip region|Femoral|"
     r"Inguinal|Urogenital|Anal|Sacral|Popliteal", r"^(pelvis|lumbar|femur|shin|foot|toes)"),
    (r"^(Frontal|Parietal|Temporal|Occipital|Mastoid|Orbital|Nasal|Oral|Buccal|Zygomatic|Mental|Infra-orbital) region|"
     r"Parotid|mouth|Labial|Philtrum|Nasolabial|Eyebrow|Eyelash|auric|Helix|tragus|concha|Scapha|"
     r"Triangular fossa|Fossa antihelica|Crura of|Lobule|Eminentia|Intertragic|upper lip|Mentolabial|"
     r"Submandibular|Submental", r"^(head|neck)"),
    (r".", r"^(pelvis|lumbar|thorax|neck|head|clavicle|scapula)"),
]
allow_f = np.zeros((len(NAMES), len(bones)), bool)
for r, nm in enumerate(NAMES):
    for gi, (rx, bx) in enumerate(PART):
        if re.search(rx, nm, re.I):
            side = nm[-1] if re.search(r"\.[lr]$", nm) else None
            allow_f[r] = [bool(re.search(bx, b)) and (side is None or not re.search(r"\.[lr]$", b) or b[-1] == side)
                          for b in bones]
            if os.environ.get("CLIMB_DEBUG"):
                print("part", gi, nm)
            break
allow = np.zeros((len(V), len(bones)), bool)
for c in range(3):
    np.logical_or.at(allow, F[:, c], allow_f[R])
Dist = np.stack([trees[b].query(V)[0] for b in bones], 1)
W = 1.0 / np.maximum(Dist, 0.004) ** 6 * allow + 1e-12
cut = np.sort(W, 1)[:, -3][:, None]
W[W < cut] = 0
W /= W.sum(1, keepdims=True)
# Smooth over the surface so joints bend without creases.
for _ in range(6):
    W = 0.5 * W + 0.5 * np.array([W[n].mean(0) if len(n) else w for n, w in zip(nbr, W)])
W[W < 0.02] = 0
W /= W.sum(1, keepdims=True)
dom = np.array(bones)[W.argmax(1)]
if os.environ.get("CLIMB_DEBUG"):
    np.savez(os.environ["CLIMB_DEBUG"], V=V, F=F, R=R, W=W, bones=np.array(bones))

# ---------------------------------------------------------------- clothes
waist = J["lumbar"][2] + 0.03
hem = (J["knee.l"][2] + J["hip.l"][2]) / 2 - 0.02
cls = np.zeros(len(V), int)  # 0 skin, 1 top, 2 shorts, 3 shoes
base_ = np.array([d.split(".")[0] for d in dom])
zz = V[:, 2]
cls[np.isin(base_, ["thorax", "lumbar", "clavicle", "scapula", "pelvis"]) & (zz > waist)] = 1
cls[np.isin(base_, ["pelvis", "lumbar", "femur"]) & (zz <= waist) & (zz > hem)] = 2
cls[np.isin(base_, ["foot", "toes"]) & (zz < J["ankle.l"][2] + 0.005)] = 3
cls[inside] = 2
COLORS = np.array([[0.85, 0.84, 0.82, 1], [0.78, 0.96, 0.2, 1], [0.16, 0.18, 0.21, 1], [0.19, 0.2, 0.23, 1]])
me = bpy.data.meshes.new("Skin")
me.from_pydata(V.tolist(), [], F.tolist())
me.update()
ca = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
ca.data.foreach_set("color", COLORS[cls].ravel().tolist())
me.color_attributes.active_color = ca
me.materials.append(bpy.data.materials.new("skin"))
me.polygons.foreach_set("use_smooth", [True] * len(F))
# The region patches do not agree on which side is out (mirrored parts are
# flipped): make every face point outward.
bm = bmesh.new()
bm.from_mesh(me)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(me)
bm.free()
skin = bpy.data.objects.new("Skin", me)
bpy.context.scene.collection.objects.link(skin)
for j, b in enumerate(bones):
    vg = skin.vertex_groups.new(name=b)
    for i in np.nonzero(W[:, j])[0]:
        vg.add([int(i)], float(W[i, j]), "REPLACE")
mod = skin.modifiers.new("arm", "ARMATURE")
mod.object = arm
skin.parent = arm
# Everything else in the file only placed the joints.
for o in list(bpy.context.scene.objects):
    if o.type == "MESH" and o is not skin:
        bpy.data.objects.remove(o, do_unlink=True)

# ---------------------------------------------------------------- foot geometry
def foot_pts(s):
    sel = np.isin(dom, [f"foot.{s}", f"toes.{s}"])
    return V[sel]


FP = foot_pts("l")
SOLE = FP[:, 2].min()
TOE_FWD = J["mtp.l"][1] - FP[:, 1].min()  # MTP joint to the tip of the shoe
HEEL_BACK = FP[:, 1].max() - J["mtp.l"][1]  # MTP joint to the back of the heel
MTP_H = J["mtp.l"][2] - SOLE
FOOT_LEN = TOE_FWD + HEEL_BACK
print("foot length", round(FOOT_LEN, 3), "mtp height", round(MTP_H, 3))
L_TH = np.linalg.norm(J["knee.l"] - J["hip.l"])
L_SH = np.linalg.norm(J["ankle.l"] - J["knee.l"])
KH = {s: np.array([1.0, 0, 0]) for s in "lr"}  # knee hinge at rest (straight leg)


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def lerp_keys(keys, x):
    for (x0, y0), (x1, y1) in zip(keys, keys[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * ease((x - x0) / max(1e-9, x1 - x0))
    return keys[-1][1]


def mtp_on(k, toes_only=False):
    """MTP joint on tread k: shoe tip 1.5 cm short of the next riser, or (fault)
    only the ball of the foot on the nosing with the heel hanging off."""
    if toes_only:
        y = -k * GOING - 0.035
    else:
        y = -(k + 1) * GOING + 0.015 + TOE_FWD
    return np.array([0.0, y, k * RISE + MTP_H])


def bez(p0, p1, p2, p3, t):
    u = 1 - t
    return u ** 3 * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t ** 3 * p3


# Foot pitch through one leg's cycle (deg, + = heel up). Contact on the step at
# 0, the other foot lands at 0.5, toe-off at 0.6, then swing to two steps up.
PITCH = [(0, 0), (0.3, 0), (0.45, 8), (0.6, 38), (0.68, 16), (0.78, -12), (0.9, -6), (1.0, 0)]
PITCH_TOES = [(0, 14), (0.35, 14), (0.6, 30), (0.68, 16), (0.78, -8), (0.9, 6), (1.0, 14)]


def leg_target(s, ph, fault):
    """MTP position, foot pitch and whether the toes are on the step, for phase ph in [0, 1)."""
    toes = fault == "toes"
    k0 = 2 if s == "r" else 1  # tread under this foot at its contact
    pitch = lerp_keys(PITCH_TOES if toes else PITCH, ph)
    sx = 1 if s == "l" else -1
    x = J[f"mtp.{s}"][0] + sx * 0.01
    if ph < 0.6:
        M = mtp_on(k0, toes)
        on = True
    else:
        t = ease((ph - 0.6) / 0.4) * 0.15 + (ph - 0.6) / 0.4 * 0.85
        P0, P3 = mtp_on(k0, toes), mtp_on(k0 + 2, toes)
        M = bez(P0, P0 + [0, 0, 0.27], P3 + [0, 0, 0.15], P3, t)
        # Lift first, then travel: the toes clear the riser in front before moving forward.
        M[1] = P0[1] + (P3[1] - P0[1]) * ease((t - 0.18) / 0.82)
        on = False
    M = M.copy()
    M[0] = x
    return M, pitch, on


def two_bone(hip, A, pole, l1, l2):
    u = A - hip
    dist = min(np.linalg.norm(u), (l1 + l2) * 0.9995)
    u /= np.linalg.norm(u)
    v = pole - u * (pole @ u)
    v /= np.linalg.norm(v)
    ca = (l1 ** 2 + dist ** 2 - l2 ** 2) / (2 * l1 * dist)
    al = math.acos(max(-1, min(1, ca)))
    E = hip + l1 * (math.cos(al) * u + math.sin(al) * v)
    n = np.cross(u, v)
    return E, hip + u * dist, -n / np.linalg.norm(n)


GOOD = dict(lean=10, neck=6, head=6, valgus=0)
FAULTS = {"valgus": dict(valgus=22), "toes": {}, "head": dict(lean=24, neck=22, head=12)}


def pelvis_at(ph, Y0, Z0):
    n = math.floor(2 * ph)
    psi = 2 * ph - n
    zp = Z0 + RISE * (n + ease(min(1.0, psi / 0.8)))
    return np.array([-0.022 * math.sin(2 * math.pi * ph), Y0 - 2 * GOING * ph, zp])


def pose_at(ph, fault, Y0, Z0):
    p = dict(GOOD, **FAULTS.get(fault, {}))
    G, H = {}, {}
    lean = p["lean"] + 2 * math.sin(4 * math.pi * ph)  # a little more lean on each push
    yaw = math.radians(4) * math.cos(2 * math.pi * ph)  # hips turn with the swinging leg
    Gp = Rz(yaw) @ Rx(D(lean * 0.6))
    Gt = Rz(-yaw * 0.6) @ Rx(D(lean))
    G["pelvis"], G["lumbar"], G["thorax"] = Gp, slerp_m(Gp, Gt, 0.5), Gt
    G["neck"] = Gt @ Rx(D(p["neck"] - lean))
    G["head"] = G["neck"] @ Rx(D(p["head"]))
    H["pelvis"] = pelvis_at(ph, Y0, Z0)
    for s in "lr":
        G[f"clavicle.{s}"] = G[f"scapula.{s}"] = Gt
    fk(G, H, upto="scapula.r")
    info = {}
    for s, sx in (("l", 1), ("r", -1)):
        lp = ph if s == "r" else (ph + 0.5) % 1.0
        M, pitch, on = leg_target(s, lp, fault)
        toe_out = Rz(sx * D(6))
        Gf = toe_out @ Rx(D(pitch))
        A = M + Gf @ (J[f"ankle.{s}"] - J[f"mtp.{s}"])
        hip = H[f"femur.{s}"]
        va = D(p["valgus"]) if on else 0.0
        pole = toe_out @ np.array([-sx * math.sin(va), -math.cos(va), 0.0])
        E, A2, a1 = two_bone(hip, A, pole, L_TH, L_SH)
        G[f"femur.{s}"] = frame_map(J[f"knee.{s}"] - J[f"hip.{s}"], KH[s], E - hip, a1)
        G[f"shin.{s}"] = frame_map(J[f"ankle.{s}"] - J[f"knee.{s}"], KH[s], A2 - E, a1)
        G[f"foot.{s}"] = Gf
        G[f"toes.{s}"] = toe_out if (on and pitch > 0) else Gf
        info[s] = dict(on=on, pitch=pitch, E=E, A=A2, hip=hip)
        # Arms swing against the legs: this arm comes forward with the other leg.
        fw = D(13) * math.cos(2 * math.pi * (lp + 0.5))
        Gh = Gt @ Ry(-sx * D(7)) @ Rx(-fw)
        G[f"humerus.{s}"] = Gh
        flex = D(22) + max(0.0, fw) * 0.8
        G[f"ulna.{s}"] = Gh @ Raxis(HINGE[s], flex)
        pax = J[f"ulnhead.{s}"] - J[f"radhead.{s}"]
        G[f"radius.{s}"] = G[f"ulna.{s}"] @ Raxis(pax, sx * D(80))
        G[f"hand.{s}"] = G[f"radius.{s}"]
        for k in range(2, 6):
            g = G[f"hand.{s}"]
            for seg, c in zip("abc", (18, 22, 14)):
                g = g @ Raxis(np.array([-1.0, 0, 0]), D(c))
                G[f"f{k}{seg}.{s}"] = g
    fk(G, H)
    return G, H, p, info


def knee_flex(i):
    a, b = i["E"] - i["hip"], i["A"] - i["E"]
    return math.degrees(math.acos(np.clip(a @ b / np.linalg.norm(a) / np.linalg.norm(b), -1, 1)))


def solve_offsets():
    """Pelvis height: the stance knee never straightens past about 7 degrees of
    flexion (it reaches roughly 5-10 at the end of the pull-up, Protopapadaki 2007).
    Pelvis over the stance foot at 30%."""
    M = mtp_on(2)
    A = M + (J["ankle.r"] - J["mtp.r"])
    Y0 = A[1] - 0.03 + 2 * GOING * 0.3
    lo, hi = 0.5, 1.4
    for _ in range(30):
        Z0 = (lo + hi) / 2
        bend = min(knee_flex(pose_at(ph, None, Y0, Z0)[3]["r"]) for ph in np.linspace(0, 0.6, 25))
        if bend > 7:
            lo = Z0
        else:
            hi = Z0
    return Y0, Z0


Y0, Z0 = solve_offsets()
print("pelvis offsets", round(Y0, 3), round(Z0, 3))


def foot_clear(G, H, s):
    """Gap between the shoe and the stairs under it (m); negative means it cuts in."""
    P = FP * [1 if s == "l" else -1, 1, 1]
    P = (P - HEAD[f"foot.{s}"]) @ G[f"foot.{s}"].T + H[f"foot.{s}"]
    k = np.maximum(np.floor(-P[:, 1] / GOING), 0)
    return float((P[:, 2] - k * RISE).min())


def metrics(p, G, H, info):
    out = {}
    tr = H["neck"] - H["pelvis"]
    out["lean"] = round(math.degrees(math.atan2(-tr[1], tr[2])), 1)
    st = [s for s in "lr" if info[s]["on"]]
    lead = max(st, key=lambda s: info[s]["A"][2]) if st else "r"
    i = info[lead]
    out["knee"] = round(knee_flex(i), 1)
    sx = 1 if lead == "l" else -1
    # Knee drift toward the midline, off the hip-ankle line (frontal plane).
    t = (i["E"][2] - i["A"][2]) / max(1e-6, i["hip"][2] - i["A"][2])
    line_x = i["A"][0] + (i["hip"][0] - i["A"][0]) * t
    out["kneeIn"] = round(float(-sx * (i["E"][0] - line_x)) * 100, 1)
    out["kneeOk"] = out["kneeIn"] < 2.5
    out["heel"] = "Heel off" if info[lead]["pitch"] > 4 else "Whole foot"
    out["heelOk"] = out["heel"] == "Whole foot" or not info[lead]["on"]
    gaze = G["head"] @ np.array([0, -1.0, 0])
    out["gaze"] = round(math.degrees(math.atan2(-gaze[2], -gaze[1])), 1)  # + = looking down
    out["gazeOk"] = out["gaze"] < 30
    out["leanOk"] = out["lean"] < 20
    sw = [s for s in "lr" if not info[s]["on"]]
    out["clear"] = round(min(foot_clear(G, H, s) for s in sw) * 100, 1) if sw else None
    return out


# ---------------------------------------------------------------- bake
CLIPS = [("good", None), ("valgus", "valgus"), ("toes", "toes"), ("head", "head")]
scene = bpy.context.scene
scene.render.fps = FPS
nframes = round(STRIDE * FPS)
frames = {}
for ci, (clip, fault) in enumerate(CLIPS):
    frames[clip] = []
    for f in range(nframes + 1):
        ph = f / nframes
        G, H, p, info = pose_at(ph, fault, Y0, Z0)
        key_pose(arm, G, H, ci * (nframes + 1) + f + 1)
        m = metrics(p, G, H, info)
        m["kneeR"] = round(knee_flex(info["r"]), 1)
        m["kneeL"] = round(knee_flex(info["l"]), 1)
        frames[clip].append(m)
scene.frame_start, scene.frame_end = 1, len(CLIPS) * (nframes + 1)
print("clearance good", [x["clear"] for x in frames["good"]])
for c, fr in frames.items():
    print(c, "min clearance", min(x["clear"] for x in fr if x["clear"] is not None), [fr[k] for k in (0, nframes // 4, nframes // 2)])

meta = {"fps": FPS, "stride": STRIDE, "spm": SPM, "rise": RISE, "going": GOING,
        "clips": [{"name": c, "start": i * (nframes + 1) / FPS, "end": (i * (nframes + 1) + nframes) / FPS}
                  for i, (c, _) in enumerate(CLIPS)],
        "frames": frames}
open(os.path.splitext(OUT)[0] + "-meta.js", "w").write("window.CLIMB_META = " + json.dumps(meta, separators=(",", ":")) + ";\n")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True,
                          export_materials="EXPORT", export_vertex_color="ACTIVE", export_normals=True, export_texcoords=False,
                          export_animations=True, export_skins=True)
print("wrote", OUT)
if os.environ.get("CLIMB_DEBUG"):
  for dph in (0.1, 0.3, 0.5, 0.7, 0.9):
    G, H, _, _ = pose_at(dph, None, Y0, Z0)
    P = np.zeros_like(V)
    for j, b in enumerate(bones):
        P += W[:, j:j + 1] * ((V - HEAD[b]) @ G[b].T + H[b])
    e = np.max([np.linalg.norm(P[F[:, a]] - P[F[:, (a + 1) % 3]], axis=1) for a in range(3)], 0)
    bad = np.argsort(e)[-8:]
    for f in bad:
        print("long", round(e[f], 3), NAMES[R[f]], [bones[W[i].argmax()] for i in F[f]])

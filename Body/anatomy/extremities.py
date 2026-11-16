"""Skin for the hands and feet: MakeHuman (CC0) hands and feet posed onto the
Z-Anatomy skeleton.

The MakeHuman body stands in an A-pose with palms down; Z-Anatomy stands in the
anatomical position with palms forward and the fingers a little bent. Each
hand is fitted with one similarity transform (rotation, translation, uniform
scale) from the wrist and knuckle joints, then every finger bone is turned so
it points along its Z-Anatomy phalanx, and the skin follows by linear blend
skinning with MakeHuman's own weights. Each foot is one similarity transform,
refined by a scale per axis.
"""
import numpy as np

import os

ORD = ["First", "Second", "Third", "Fourth", "Fifth"]
# Where the muscles and tendons stop under the skin of a hand or a foot: above the wrist joint
# along the hand, and above the ankle joint. Both lie well inside the cuff of the skin (which
# the rig trims 1.4 cm above the wrist and 2.4 cm above the ankle), so the cut ends, which
# are ragged, are out of sight.
HAND_CUT = float(os.environ.get("HAND_CUT", 0.0))
FOOT_CUT = float(os.environ.get("FOOT_CUT", 0.008))


def similarity(src, dst):
    """Rotation R, scale s, translation t with dst ~ s R src + t (Umeyama)."""
    ms, md = src.mean(0), dst.mean(0)
    a, b = src - ms, dst - md
    u, d, vt = np.linalg.svd(b.T @ a)
    e = np.eye(3)
    e[2, 2] = np.sign(np.linalg.det(u @ vt))
    R = u @ e @ vt
    s = (d * np.diag(e)).sum() / (a ** 2).sum()
    return R, s, md - s * R @ ms


def rot_between(a, b):
    """Smallest rotation turning direction a onto direction b."""
    a, b = a / np.linalg.norm(a), b / np.linalg.norm(b)
    v, c = np.cross(a, b), float(a @ b)
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3)
    k = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + k + k @ k / (1 + c)


class ZA:
    """World-space points of Z-Anatomy bones, by name and side ("l" or "r")."""

    def __init__(self, objs):
        self.objs = {o.name: o for o in objs}

    def pts(self, name, side):
        o = self.objs[f"{name}.{side}"]
        return np.array([tuple(o.matrix_world @ v.co) for v in o.data.vertices])

    def ends(self, name, side, near):
        """Both ends of a long bone's centre line, the one nearer `near` first."""
        p = self.pts(name, side)
        c = p.mean(0)
        ax = np.linalg.svd(p - c)[2][0]
        t = (p - c) @ ax
        e0, e1 = c + ax * t.min(), c + ax * t.max()
        return (e0, e1) if np.linalg.norm(e0 - near) < np.linalg.norm(e1 - near) else (e1, e0)


def hand_targets(za, side):
    """Z-Anatomy points for MakeHuman's hand joint names (side letter as MakeHuman spells it)."""
    wrist = (za.pts("Lunate bone", side).mean(0) + za.pts("Scaphoid bone", side).mean(0)) / 2
    j = {"hand": wrist, "hand-3": za.pts("Capitate bone", side).mean(0)}
    for k in range(5):
        f = ORD[k].lower()
        m0, m1 = za.ends(f"{ORD[k]} metacarpal bone", side, wrist)
        p0, p1 = za.ends(f"Proximal phalanx of {f} finger of hand", side, wrist)
        d0, d1 = za.ends(f"Distal phalanx of {f} finger of hand", side, wrist)
        tip = d1 + (d1 - d0) / np.linalg.norm(d1 - d0) * 0.004
        n = k + 1
        if k == 0:  # thumb: no middle phalanx
            j.update({f"finger-1-1": m0, "finger-1-2": (m1 + p0) / 2, "finger-1-3": (p1 + d0) / 2,
                      "finger-1-4": tip})
        else:
            i0, i1 = za.ends(f"Middle phalanx of {f} finger of hand", side, wrist)
            j.update({f"finger-{n}-1": (m1 + p0) / 2, f"finger-{n}-2": (p1 + i0) / 2,
                      f"finger-{n}-3": (i1 + d0) / 2, f"finger-{n}-4": tip})
    return j


HAND_BONES = {"wrist": ("hand", "hand-3")}
for _k in range(1, 5):
    HAND_BONES[f"metacarpal{_k}"] = ("hand-3", f"finger-{_k + 1}-1")
for _n in range(1, 6):
    for _s in range(1, 4):
        HAND_BONES[f"finger{_n}-{_s}"] = (f"finger-{_n}-{_s}", f"finger-{_n}-{_s + 1}")


def foot_targets(za, side):
    tal = za.pts("Talus", side)
    j = {"ankle": tal[tal[:, 2] > tal[:, 2].max() - 0.008].mean(0) - [0, 0, 0.006]}
    for k in range(5):
        f = ORD[k].lower()
        m0, m1 = za.ends(f"{ORD[k]} metatarsal bone", side, j["ankle"])
        p0, _ = za.ends(f"Proximal phalanx of {f} finger of foot", side, j["ankle"])
        d0, d1 = za.ends(f"Distal phalanx of {f} finger of foot", side, j["ankle"])
        last = 3 if k == 0 else 4
        j[f"toe-{k + 1}-1"] = (m1 + p0) / 2
        j[f"toe-{k + 1}-{last}"] = d1 + (d1 - d0) / np.linalg.norm(d1 - d0) * 0.004
    return j


def _faces_where(faces, keep):
    return [f for f in faces if keep[f].all()]


def build(body, za_objs):
    """Posed vertices and faces of both hands and both feet.

    Returns (verts, faces, cuts) in Z-Anatomy world space. Each cut is a
    cylinder (origin, axis, length, radius): muscle inside it is under the
    skin and can go (the long finger and toe tendons).
    """
    za = ZA(za_objs)
    V0 = body["verts"]
    nv = len(V0)
    J = body["joints"]
    out_v, out_f, cuts = [], [], []

    def weights(bones):
        w = np.zeros((nv, len(bones)))
        for i, b in enumerate(bones):
            for v, x in body["skin"].get(b, []):
                w[v, i] += x
        return w

    for mhs, zs in (("R", "r"), ("L", "l")):
        js = mhs.lower()
        # Hand.
        tg = hand_targets(za, zs)
        mh = {k: J[f"joint-{js}-{k}"] for k in tg}
        keys = ["hand", "hand-3", "finger-1-1"] + [f"finger-{n}-1" for n in range(2, 6)]
        R, s, t = similarity(np.array([mh[k] for k in keys]), np.array([tg[k] for k in keys]))
        bones = [f"{b}.{mhs}" for b in HAND_BONES]
        w = weights(bones)
        chain = w.sum(1)
        w[:, 0] += np.clip(1 - chain, 0, None)  # forearm weight rides with the wrist
        w /= w.sum(1, keepdims=True)
        P = np.zeros_like(V0)
        for i, b in enumerate(HAND_BONES):
            h, tl = HAND_BONES[b]
            if b == "wrist":
                Pb = s * V0 @ R.T + t
            else:
                Rb = rot_between(R @ (mh[tl] - mh[h]), tg[tl] - tg[h]) @ R
                Pb = tg[h] + s * (V0 - mh[h]) @ Rb.T
            P += w[:, [i]] * Pb
        # Keep the hand and a short cuff above the wrist.
        axis = tg["finger-3-1"] - tg["hand"]
        axis /= np.linalg.norm(axis)
        keep = (chain > 0.05) & (((P - tg["hand"]) @ axis) > -0.025)
        cuts.append((tg["hand"] - axis * HAND_CUT, axis, 0.25, 0.055))
        out_v.append(P)
        out_f.append(_faces_where(body["faces"], keep))
        # Foot.
        tg = foot_targets(za, zs)
        mh = {k: J[f"joint-{js}-{k}"] for k in tg}
        src = np.array([mh[k] for k in tg])
        dst = np.array([tg[k] for k in tg])
        R, s, t = similarity(src, dst)
        # Per-axis scale in the fitted frame, around the ankle.
        a = (src - mh["ankle"]) @ R.T * s
        b = dst - tg["ankle"]
        k = np.clip((a * b).sum(0) / np.maximum((a * a).sum(0), 1e-9), 0.85, 1.15)
        P = ((V0 - mh["ankle"]) @ R.T * s) * k + tg["ankle"]
        # The malleoli sit closer to MakeHuman's ankle skin than the fit allows:
        # push the skin out a few millimetres around the ankle.
        d = P[:, :2] - tg["ankle"][:2]
        bump = np.clip(1 - np.abs(P[:, 2] - tg["ankle"][2]) / 0.045, 0, 1)
        P[:, :2] += d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-6) * (0.008 * bump)[:, None]
        fw = weights([f"foot.{mhs}"])[:, 0]
        keep = (fw > 0.05) & (P[:, 2] < tg["ankle"][2] + 0.05)
        cuts.append((tg["ankle"] + [0, 0, FOOT_CUT], np.array([0, 0, -1.0]), 0.2, 0.2))
        out_v.append(P)
        out_f.append(_faces_where(body["faces"], keep))
        print(f"foot {mhs} scale {s:.3f} axes {np.round(k, 3)}")
    # One mesh: concatenate and keep only used vertices.
    verts, faces, base = [], [], 0
    for P, F in zip(out_v, out_f):
        used = sorted({i for f in F for i in f})
        remap = {v: n + base for n, v in enumerate(used)}
        verts.append(P[used])
        faces += [[remap[i] for i in f] for f in F]
        base += len(used)
    return np.concatenate(verts), faces, cuts


def cut_mask(P, cuts):
    """True for points that the skin of a hand or foot covers."""
    m = np.zeros(len(P), bool)
    for o, n, length, r in cuts:
        t = (P - o) @ n
        m |= (t > 0) & (t < length) & (np.linalg.norm(P - o - np.outer(t, n), axis=1) < r)
    return m

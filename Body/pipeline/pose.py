"""Pose the MakeHuman rig from a few anatomical numbers.

Everything here is plain numpy so the same model can later be ported to the
app. A pose is a dict of world-space rigid transforms D[bone] (4x4) that move
each bone from its rest place: posed matrix = D @ rest matrix.

Conventions (Blender world): metres, Z up, the body faces -Y, the
character's left is +X. Shoulder maths is done for the RIGHT side in the ISB
thorax frame (X forward, Y up, Z to the right) and mirrored for the left.

Shoulder model:
  clavicle  rotates about the sternoclavicular joint (elevation, retraction)
  scapula   rides on the clavicle at the acromioclavicular joint; its
            orientation is ISB Euler Y-X-Z relative to the thorax:
            internal rotation, upward rotation, posterior tilt
  humerus   its head is carried by the scapula (glenoid); thoracohumeral
            elevation and plane of elevation place the elbow
Scapulohumeral rhythm defaults follow Ludewig et al. 2009 (healthy shoulders,
scapular plane elevation); every value can be overridden per key pose.
"""
import math

import numpy as np

# ---------------------------------------------------------------- maths


def rot(axis, deg):
    a = np.asarray(axis, float)
    a = a / np.linalg.norm(a)
    t = math.radians(deg)
    c, s = math.cos(t), math.sin(t)
    x, y, z = a
    return np.array([[c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s],
                     [y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s],
                     [z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c)]])


def T(R=None, p=None):
    M = np.eye(4)
    if R is not None:
        M[:3, :3] = R
    if p is not None:
        M[:3, 3] = p
    return M


def about(point, R):
    """Rigid transform: rotate by R about a point."""
    point = np.asarray(point, float)
    return T(R, point - R @ point)


def place(R, old, new):
    """Rigid transform: rotate by R and carry point `old` to `new`."""
    return T(R, np.asarray(new, float) - R @ np.asarray(old, float))


def app(D, p):
    return D[:3, :3] @ p + D[:3, 3]


def unit(v):
    return v / np.linalg.norm(v)


def minrot(a, b):
    a, b = unit(a), unit(b)
    c = np.cross(a, b)
    s = np.linalg.norm(c)
    if s < 1e-9:
        return np.eye(3)
    return rot(c, math.degrees(math.atan2(s, float(a @ b))))


def frame(n, y):
    """Orthonormal frame with columns (n, y, n x y); n is made perpendicular to y."""
    y = unit(y)
    n = unit(n - (n @ y) * y)
    return np.stack([n, y, np.cross(n, y)], axis=1)


def signed_angle(a, b, axis):
    axis = unit(axis)
    a = a - (a @ axis) * axis
    b = b - (b @ axis) * axis
    return math.degrees(math.atan2(float(np.cross(a, b) @ axis), float(a @ b)))


def euler_yxz(R):
    """R = Ry(a) Rx(b) Rz(c); returns degrees (a, b, c)."""
    b = math.asin(max(-1.0, min(1.0, -R[1, 2])))
    a = math.atan2(R[0, 2], R[2, 2])
    c = math.atan2(R[1, 0], R[1, 1])
    return tuple(math.degrees(x) for x in (a, b, c))


def from_yxz(a, b, c):
    return rot([0, 1, 0], a) @ rot([1, 0, 0], b) @ rot([0, 0, 1], c)


PTS = ("AC", "G", "Ph", "E", "W", "AI", "SA", "TS")
MIRROR = np.diag([-1.0, 1.0, 1.0, 1.0])
# Columns: ISB right-side thorax axes (forward, up, right) in world.
ISB_R = np.array([[0, 0, -1], [-1, 0, 0], [0, 1, 0]], float)


def to_isb(v):
    return ISB_R.T @ v


def from_isb(v):
    return ISB_R @ v


# ---------------------------------------------------------------- rhythm


def rhythm(elev):
    """Shoulder girdle angles (change from arm-at-side, degrees) for a
    thoracohumeral elevation, after Ludewig et al. 2009."""
    e = max(0.0, elev - 20.0)
    return {
        "upRot": 0.36 * e,                    # scapula upward rotation
        "tilt": 0.10 * e + 0.0006 * e * e,    # scapula posterior tilt
        "ir": -0.04 * e,                      # scapula internal rotation
        "clavElev": 0.08 * e,                 # clavicle elevation
        "clavRetr": 0.11 * e,                 # clavicle retraction
    }


# ---------------------------------------------------------------- body


class Body:
    def __init__(self, bones, landmarks):
        """bones: name -> {head, tail, parent, matrix (3x3 rest, world)}.
        landmarks: anatomical rest points for the RIGHT side (world)."""
        self.b = bones
        self.L = {k: np.asarray(v, float) for k, v in landmarks.items()}
        self.order = []
        seen = set()

        def visit(n):
            if n in seen:
                return
            p = self.b[n]["parent"]
            if p:
                visit(p)
            seen.add(n)
            self.order.append(n)

        for n in self.b:
            visit(n)
        self.h = {n: np.asarray(v["head"], float) for n, v in self.b.items()}
        self.t = {n: np.asarray(v["tail"], float) for n, v in self.b.items()}
        L = self.L
        # Scapula rest orientation (ISB frame, right side).
        self.scap_rest = self.scap_frame(L["AC"], L["TS"], L["AI"])
        self.scap_rest_euler = euler_yxz(self.scap_rest)
        self.prev_n = {}

    @staticmethod
    def scap_frame(ac, ts, ai):
        """ISB scapula frame in ISB thorax coords: Z from TS to AC, X normal
        to the scapular plane pointing forward, Y up."""
        ac, ts, ai = to_isb(ac), to_isb(ts), to_isb(ai)
        z = unit(ac - ts)
        x = unit(np.cross(ai - ts, ac - ts))
        if x[0] < 0:
            x = -x
        y = np.cross(z, x)
        return np.stack([x, y, z], axis=1)

    # ------------------------------------------------------------ main

    def pose(self, P):
        b, h = self.b, self.h
        D = {}
        rest = {}  # transforms computed below, applied in hierarchy order

        # Pelvis and legs.
        hip_c = (h["upperleg01.L"] + h["upperleg01.R"]) / 2
        root = P.get("root", {})
        D_root = T(None, root.get("pos", [0, 0, 0])) @ about(hip_c, rot([1, 0, 0], root.get("tilt", 0)))
        rest["root"] = D_root

        legs = P.get("legs", {})
        for s, sg in (("L", 1), ("R", -1)):
            hip = h[f"upperleg01.{s}"]
            knee = h[f"lowerleg01.{s}"]
            ank = h[f"foot.{s}"]
            Rt = rot([0, 0, 1], sg * legs.get("spread", 0)) @ rot([1, 0, 0], -legs.get("hipFlex", 0))
            rest[f"upperleg01.{s}"] = ("rel", about(hip, Rt))
            rest[f"lowerleg01.{s}"] = ("rel", about(knee, rot([1, 0, 0], legs.get("knee", 0))))
            rest[f"foot.{s}"] = ("rel", about(ank, rot([1, 0, 0], -legs.get("ankle", 0))))

        # Spine: flexion (+) / extension (-) spread over the segments.
        sp = P.get("spine", {})
        lum = ["spine05", "spine04", "spine03"]
        tho = ["spine02", "spine01"]
        for n in lum:
            rest[n] = ("rel", about(h[n], rot([1, 0, 0], sp.get("lumbar", 0) / len(lum))))
        for n in tho:
            rest[n] = ("rel", about(h[n], rot([1, 0, 0], sp.get("thoracic", 0) / len(tho))))
        for n in ("neck01", "neck02", "neck03"):
            rest[n] = ("rel", about(h[n], rot([1, 0, 0], sp.get("neck", 0) / 3)))
        rest["head"] = ("rel", about(h["head"], rot([1, 0, 0], sp.get("head", 0))))

        # Compose the trunk and legs so the thorax transform is known.
        for n in self.order:
            p = b[n]["parent"]
            Dp = D[p] if p else np.eye(4)
            r = rest.get(n)
            if r is None:
                D[n] = Dp
            elif isinstance(r, tuple):
                D[n] = Dp @ r[1]
            else:
                D[n] = r
        D_th = D["spine01"]

        set_here = set(rest)
        report = {}
        arms = P.get("arms", {})
        for s in ("R", "L"):
            A = dict(arms)
            A.update(P.get("arm" + s, {}))
            Dl, rep = self.arm(A, s)
            for n, M in Dl.items():
                D[n] = D_th @ M
                set_here.add(n)
            for k in PTS:
                rep[k] = [round(float(x), 4) for x in app(D_th, rep[k])]
            report[s] = rep

        # Everything not set explicitly follows its parent (fingers, face...).
        fixed = set_here
        grip = P.get("grip", {})
        out = {}
        for n in self.order:
            p = b[n]["parent"]
            if n in fixed:
                out[n] = D[n]
                continue
            Dp = out[p] if p else np.eye(4)
            if n.startswith("finger"):
                out[n] = Dp @ self.finger(n, grip)
            else:
                out[n] = Dp
        for n in D:
            out.setdefault(n, D[n])
        return out, report

    # ------------------------------------------------------------ fingers

    def finger(self, n, grip):
        curl = grip.get("curl", 0)
        if curl == 0:
            return np.eye(4)
        digit, seg = n[6], int(n[8])
        if digit == "1":
            ang = curl * [25, 30, 35][seg - 1]
        else:
            ang = curl * [55, 70, 50][seg - 1]
        axis = np.asarray(self.b[n]["matrix"])[:, 0]
        sign = grip.get("sign", 1.0)
        return about(self.h[n], rot(axis, sign * ang))

    # ------------------------------------------------------------ arm

    def arm(self, A, side):
        """Bone transforms (relative to the thorax) for one arm, computed for
        the right side and mirrored for the left."""
        b, h, L = self.b, self.h, self.L
        nm = lambda base: f"{base}.R"

        def isbR(deg_axis, deg):
            return ISB_R @ rot(deg_axis, deg) @ ISB_R.T

        elev = A.get("elev", 20.0)
        plane = A.get("plane", 0.0)
        r = rhythm(elev)
        for k in r:
            r[k] += A.get(k, 0.0)

        # Clavicle about the SC joint: elevation is about thorax X (forward),
        # retraction about thorax Y (up).
        SC = L["SC"]
        R_clav = isbR([0, 1, 0], -r["clavRetr"]) @ isbR([1, 0, 0], -r["clavElev"])
        D_clav = about(SC, R_clav)
        AC1 = app(D_clav, L["AC"])

        # Scapula: absolute ISB Euler = rest + change.
        a0, b0, c0 = self.scap_rest_euler
        # Signs checked numerically: upward rotation swings the inferior angle
        # laterally, posterior tilt brings it forward against the ribs.
        Rs = from_yxz(a0 + r["ir"], b0 + self.UR_SIGN * r["upRot"], c0 + self.PT_SIGN * r["tilt"])
        R_sd = ISB_R @ (Rs @ self.scap_rest.T) @ ISB_R.T
        D_scap = place(R_sd, L["AC"], AC1)

        Ph = h[nm("upperarm01")]
        Ph1 = app(D_scap, Ph)
        E = h[nm("lowerarm01")]
        W = h[nm("wrist")]
        Lua = np.linalg.norm(E - Ph)
        Lfa = np.linalg.norm(W - E)

        # Humerus direction from elevation and plane (ISB: plane 0 = abduction).
        th, ph = math.radians(elev), math.radians(plane)
        ua = from_isb(np.array([math.sin(th) * math.sin(ph), -math.cos(th), math.sin(th) * math.cos(ph)]))
        E1 = Ph1 + Lua * ua
        if "faDir" in A:
            fa = unit(from_isb(np.asarray(A["faDir"], float)))
        else:
            # Forearm from elbow flexion and humeral axial rotation.
            flex = math.radians(A.get("elbow", 10))
            rotd = A.get("humRot", 0.0)
            ref = from_isb(np.array([1.0, 0, 0]))  # forward
            perp = unit(ref - (ref @ ua) * ua) if abs(ref @ ua) < 0.95 else unit(np.cross(ua, from_isb([0, 0, 1.0])))
            perp = rot(ua, rotd) @ perp
            fa = unit(math.cos(flex) * ua + math.sin(flex) * perp)
        W1 = E1 + Lfa * fa

        # Flexion axis; keep the last good one when the arm is nearly straight.
        c = np.cross(ua, fa)
        if np.linalg.norm(c) > 0.12:
            n = unit(c)
            self.prev_n[side] = n
        else:
            n = self.prev_n.get(side, unit(np.cross(ua, from_isb([1.0, 0, 0]))))

        ua0 = unit(E - Ph)
        fa0 = unit(W - E)
        n0 = unit(np.cross(ua0, fa0))
        R_hum = frame(n, ua) @ frame(n0, ua0).T
        R_fa = frame(n, fa) @ frame(n0, fa0).T

        # Forearm rotation: turn the palm toward the asked direction.
        palm0 = R_fa @ self.palm_rest()
        want = from_isb(np.asarray(A.get("palm", [1.0, 0, 0]), float))
        psi = signed_angle(palm0, want, fa)
        R_lo1 = rot(fa, 0.2 * psi) @ R_fa
        R_lo2 = rot(fa, 0.7 * psi) @ R_fa
        R_wr = rot(fa, psi) @ R_fa
        wflex = A.get("wristExt", 0.0)
        if wflex:
            R_wr = rot(n, -wflex) @ R_wr

        out = {}
        out[nm("clavicle")] = D_clav
        out["scapula.R"] = D_scap
        Pc = h[nm("shoulder01")]
        Pc1 = app(D_clav, Pc)
        R_s01 = minrot(R_sd @ (Ph - Pc), Ph1 - Pc1) @ R_sd
        out[nm("shoulder01")] = place(R_s01, Pc, Pc1)
        out[nm("upperarm01")] = place(R_hum, Ph, Ph1)
        out[nm("upperarm02")] = place(R_hum, Ph, Ph1)
        out[nm("lowerarm01")] = place(R_lo1, E, E1)
        M = h[nm("lowerarm02")]
        out[nm("lowerarm02")] = place(R_lo2, M, app(out[nm("lowerarm01")], M))
        out[nm("wrist")] = place(R_wr, W, W1)

        # Report (anatomical angles).
        scap_abs = euler_yxz(Rs)
        G1 = app(D_scap, L["G"])
        rep = {
            "elev": round(elev, 1),
            "plane": round(plane, 1),
            "elbowFlex": round(math.degrees(math.acos(max(-1, min(1, float(ua @ fa))))), 1),
            "scapUpRot": round(self.UR_SIGN * (scap_abs[1] - b0) + self.UR0, 1),
            "scapTilt": round(self.PT_SIGN * (scap_abs[2] - c0) + self.PT0, 1),
            "scapIR": round(scap_abs[0], 1),
            "clavElev": round(r["clavElev"] + self.CE0, 1),
            "clavRetr": round(r["clavRetr"] + self.CR0, 1),
            "ghElev": round(elev - (self.UR_SIGN * (scap_abs[1] - b0) + self.UR0), 1),
            "pronation": round(psi + self.PRON0, 1),
            "AC": AC1, "G": G1, "Ph": Ph1, "E": E1, "W": W1,
            "AI": app(D_scap, L["AI"]), "SA": app(D_scap, L["SA"]), "TS": app(D_scap, L["TS"]),
        }

        if side == "L":
            out = {k.replace(".R", ".L"): MIRROR @ v @ MIRROR for k, v in out.items()}
            for k in PTS:
                rep[k] = (MIRROR[:3, :3] @ rep[k])
        return out, rep

    # Rest-pose values used by the report: arm-at-side girdle angles (deg).
    UR_SIGN = -1.0  # with these ISB axes, upward rotation is about -X
    PT_SIGN = 1.0
    UR0 = 5.0     # scapula upward rotation with arm at side
    PT0 = -8.0    # slight anterior tilt at rest
    CE0 = 6.0     # clavicle elevation at rest
    CR0 = 20.0    # clavicle retraction at rest
    PRON0 = 0.0

    def palm_rest(self):
        """Palm normal of the right hand in rest pose (world)."""
        h, t = self.h, self.t
        w = h["wrist.R"]
        idx = h["finger2-1.R"]
        pky = h["finger5-1.R"]
        thumb = t["finger1-3.R"]
        mid = (idx + pky) / 2
        n = np.cross(mid - w, idx - pky)
        n = unit(n)
        if (thumb - w) @ n < 0:
            n = -n
        return n

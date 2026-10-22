"""Anatomical layer generated from the body: shoulder-blade landmarks, the
scapula skin weights, muscle masks, and simple bone meshes for the X-ray view.

Landmarks are placed from the body's own surface and joint centres using
standard adult proportions, so the layer fits any MakeHuman body shape.
All landmark points are for the RIGHT side (x < 0); the left is the mirror.
"""
import math

import numpy as np

from pose import unit


def back_surface(verts, x, z, r=0.014):
    m = (np.abs(verts[:, 0] - x) < r) & (np.abs(verts[:, 2] - z) < r)
    return float(verts[m, 1].max())


def front_surface(verts, x, z, r=0.014):
    m = (np.abs(verts[:, 0] - x) < r) & (np.abs(verts[:, 2] - z) < r)
    return float(verts[m, 1].min())


def landmarks(body):
    v, B = body["verts"], body["bones"]
    sc = B["clavicle.R"]["head"].copy()
    ph = B["upperarm01.R"]["head"].copy()  # humeral head centre
    W = abs(ph[0])  # half shoulder width at the joint centres
    ac = ph + [0.012, 0.004, 0.036]  # acromioclavicular joint, above and medial
    g = ph + [0.024, 0.004, 0.0]  # glenoid centre, medial to the head
    depth = 0.014  # skin and muscle over the blade
    ts_x, ts_z = -0.30 * W - 0.004, ac[2] - 0.062
    ai_x, ai_z = -0.36 * W - 0.004, ts_z - 0.125
    sa_x, sa_z = -0.33 * W - 0.004, ts_z + 0.032
    ts = np.array([ts_x, back_surface(v, ts_x, ts_z) - depth, ts_z])
    ai = np.array([ai_x, back_surface(v, ai_x, ai_z) - depth, ai_z])
    sa = np.array([sa_x, back_surface(v, sa_x, sa_z) - depth - 0.004, sa_z])
    return {"SC": sc, "AC": ac, "G": g, "Ph": ph, "TS": ts, "AI": ai, "SA": sa,
            "E": B["lowerarm01.R"]["head"].copy(), "Wr": B["wrist.R"]["head"].copy()}


def blade_outline(lm, n=40):
    """Closed outline of the scapular blade (right side), posterior view."""
    sa, ts, ai, g, ac = lm["SA"], lm["TS"], lm["AI"], lm["G"], lm["AC"]
    neck = g + 0.25 * (ts - g) + [0, 0.006, -0.012]
    notch = sa + 0.55 * (g - sa) + [0, -0.004, 0.018]
    lat = ai + 0.55 * (g + [0, 0, -0.03] - ai) + [-0.008, -0.006, 0]
    ctrl = [sa, notch, g + [0.004, 0.004, 0.012], g + [0.002, 0.004, -0.018], lat, ai,
            ts + 0.45 * (ai - ts) + [-0.004, 0.002, 0], ts]
    pts = []
    m = len(ctrl)
    for i in range(m):
        p0, p1, p2, p3 = ctrl[i - 1], ctrl[i], ctrl[(i + 1) % m], ctrl[(i + 2) % m]
        for k in range(n // m):
            t = k / (n // m)
            pts.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    return np.array(pts)


def _inside(pt, poly):
    x, y = pt
    c = False
    for i in range(len(poly)):
        x1, y1 = poly[i - 1]
        x2, y2 = poly[i]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def _poly_dist(pt, poly):
    best = 1e9
    for i in range(len(poly)):
        a, b = poly[i - 1], poly[i]
        ab = b - a
        t = max(0, min(1, float((pt - a) @ ab / (ab @ ab))))
        best = min(best, float(np.linalg.norm(pt - a - t * ab)))
    return best


def scapula_weights(body, lm):
    """Move part of the skin over each blade onto the scapula bone so the
    back surface follows the blade as it rotates."""
    v = body["verts"]
    skin = {b: list(l) for b, l in body["skin"].items()}
    poly = blade_outline(lm)[:, [0, 2]]
    total = np.zeros(len(v))
    for b, l in skin.items():
        for i, w in l:
            total[i] += w
    for side, sg in (("R", 1), ("L", -1)):
        P = poly * [sg, 1]
        add = {}
        for i, p in enumerate(v):
            if p[1] < 0.02 or abs(p[0]) > abs(lm["Ph"][0]) - 0.01 or sg * p[0] > 0:
                continue
            q = np.array([p[0], p[2]])
            d = 0.0 if _inside(q, P) else _poly_dist(q, P)
            if d > 0.035:
                continue
            w = 0.75 * (1 - (d / 0.035)) ** 2 if d > 0 else 0.75
            add[i] = w
        for b in skin:
            skin[b] = [(i, w * (1 - add[i]) if i in add else w) for i, w in skin[b]]
        skin[f"scapula.{side}"] = [(i, w * max(total[i], 1e-6)) for i, w in add.items()]
    return skin


def _seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(p - (a + np.outer(t, ab)), axis=1), t


def muscle_colors(ob, body, lm):
    """RGBA mask per vertex: R deltoid, G triceps, B trapezius, A serratus."""
    v = body["verts"]
    out = np.zeros((len(v), 4))
    for sg in (1, -1):
        m = np.array([sg, 1, 1])
        ph, ac, e = lm["Ph"] * m, lm["AC"] * m, lm["E"] * m
        side = (v[:, 0] * -sg) > 0.0  # this side of the body (right side has x<0 when sg=1)
        ua = unit(e - ph)
        # Deltoid: cap from the acromion to the middle of the upper arm.
        ins = ph + 0.5 * (e - ph)
        d, t = _seg_dist(v, ac + [0, 0, 0.005], ins)
        rad = 0.062 - 0.042 * t
        radial = v - (ph + np.outer(np.clip(((v - ph) @ ua), 0, None), ua))
        medial = np.array([sg * 1.0, 0, 0])
        rn = radial / np.maximum(np.linalg.norm(radial, axis=1, keepdims=True), 1e-6)
        face_in = np.clip((rn @ medial - 0.25) / 0.5, 0, 1)
        delt = np.clip(1 - (d - rad) / 0.012, 0, 1) * (1 - face_in) * side
        out[:, 0] = np.maximum(out[:, 0], delt)
        # Triceps: back of the upper arm.
        d, t = _seg_dist(v, ph + 0.2 * (e - ph), e - 0.06 * (e - ph))
        back = np.clip((rn @ np.array([0, 1.0, 0]) - 0.0) / 0.5, 0, 1)
        tri = np.clip(1 - (d - 0.052) / 0.012, 0, 1) * back * side * (t > 0.05)
        out[:, 1] = np.maximum(out[:, 1], tri * (1 - delt))
        # Trapezius: kite from the base of the skull to the acromion and T12.
        c7 = np.array([0, lm["TS"][1] + 0.02, ac[2] + 0.05])
        occ = np.array([0, c7[1] - 0.02, c7[2] + 0.13])
        t12 = np.array([0, lm["AI"][1] + 0.02, lm["AI"][2] - 0.09])
        poly = np.array([occ, ac + [0, 0.01, 0.01], lm["TS"] * m + [0, 0, -0.01], t12])[:, [0, 2]]
        backside = v[:, 1] > 0.0
        trap = np.zeros(len(v))
        for i in np.where(backside & side)[0]:
            q = v[i, [0, 2]]
            dd = 0 if _inside(q, poly) else _poly_dist(q, poly)
            trap[i] = max(0, 1 - dd / 0.012)
        out[:, 2] = np.maximum(out[:, 2], trap * (1 - delt))
        # Serratus anterior: side of the ribs below the armpit.
        c = np.array([-sg * abs(lm["Ph"][0]) * 0.66, -0.055, lm["AI"][2] + 0.03])
        d = np.linalg.norm((v - c) * [0.9, 1.0, 0.8], axis=1)
        ser = np.clip(1 - (d - 0.045) / 0.015, 0, 1) * side * (v[:, 1] < 0.0)
        out[:, 3] = np.maximum(out[:, 3], ser * (1 - delt))
    col = ob.data.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    col.data.foreach_set("color", out.astype(np.float32).ravel())
    ob.data.color_attributes.active_color = col


# ---------------------------------------------------------------- bone meshes


def tube(path, radii, sides=10, closed=False):
    path = np.asarray(path, float)
    verts, faces = [], []
    ref = np.array([0.0, 1.0, 0.0])
    for i, p in enumerate(path):
        tdir = unit(path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)])
        if abs(tdir @ ref) > 0.9:
            ref = np.array([1.0, 0, 0])
        u = unit(np.cross(tdir, ref))
        w = np.cross(tdir, u)
        for k in range(sides):
            a = 2 * math.pi * k / sides
            verts.append(p + radii[i] * (math.cos(a) * u + math.sin(a) * w))
    n = len(path)
    for i in range(n if closed else n - 1):
        j = (i + 1) % n
        for k in range(sides):
            faces.append([i * sides + k, i * sides + (k + 1) % sides, j * sides + (k + 1) % sides, j * sides + k])
    if closed:
        return np.array(verts), faces
    verts.append(path[0])
    verts.append(path[-1])
    c0, c1 = len(verts) - 2, len(verts) - 1
    for k in range(sides):
        faces.append([c0, (k + 1) % sides, k])
        faces.append([c1, (n - 1) * sides + k, (n - 1) * sides + (k + 1) % sides])
    return np.array(verts), faces


def sphere(c, r, rings=8, sides=12, scale=(1, 1, 1)):
    verts, faces = [], []
    for i in range(rings + 1):
        th = math.pi * i / rings
        for k in range(sides):
            ph = 2 * math.pi * k / sides
            verts.append(c + r * np.array([math.sin(th) * math.cos(ph) * scale[0],
                                            math.sin(th) * math.sin(ph) * scale[1], math.cos(th) * scale[2]]))
    for i in range(rings):
        for k in range(sides):
            a, b = i * sides + k, i * sides + (k + 1) % sides
            faces.append([a, a + sides, b + sides, b])
    return np.array(verts), faces


def join(*parts):
    V, F, off = [], [], 0
    for v, f in parts:
        V.extend(v)
        F.extend([[i + off for i in face] for face in f])
        off += len(v)
    return np.array(V), F


def scapula_mesh(lm, verts):
    out = blade_outline(lm, 48)
    c = out.mean(axis=0)
    nrm = unit(np.cross(lm["AI"] - lm["TS"], lm["AC"] - lm["TS"]))
    if nrm[1] < 0:
        nrm = -nrm  # posterior
    # The blade follows the curve of the ribs: lift the middle onto the back.
    mid_y = back_surface(verts, c[0], c[2], 0.02) - 0.016
    k = max(0.0, (np.array([c[0], mid_y, c[2]]) - c) @ nrm)
    th = 0.0025
    rings = [0.0, 0.35, 0.7, 1.0]
    V, F = [], []
    n = len(out)
    for f in rings:
        bulge = nrm * k * (1 - f * f)
        for p in out:
            q = c + f * (p - c) + bulge
            V.append(q + nrm * th)
            V.append(q - nrm * th)
    idx = lambda r, i, side: 2 * (r * n + i % n) + side
    for r in range(len(rings) - 1):
        for i in range(n):
            F.append([idx(r, i, 0), idx(r + 1, i, 0), idx(r + 1, i + 1, 0), idx(r, i + 1, 0)])
            F.append([idx(r, i, 1), idx(r, i + 1, 1), idx(r + 1, i + 1, 1), idx(r + 1, i, 1)])
    last = len(rings) - 1
    for i in range(n):
        F.append([idx(last, i, 0), idx(last, i, 1), idx(last, i + 1, 1), idx(last, i + 1, 0)])
    blade = (np.array(V), F)
    # Spine of the scapula and acromion: a ridge from TS out to the acromion.
    ts, ac = lm["TS"], lm["AC"]
    acro_tip = ac + [-0.022, 0.004, -0.004]
    path = [ts + nrm * 0.002, ts + 0.5 * (ac - ts) + nrm * 0.012, ac + nrm * 0.006, acro_tip]
    spine = tube(path, [0.003, 0.006, 0.007, 0.006], 8)
    glen = sphere(lm["G"] + [-0.004, 0, 0], 0.014, 6, 10, (0.35, 0.8, 1.1))
    cor = tube([lm["G"] + [0.006, -0.006, 0.016], lm["G"] + [0.002, -0.03, 0.022]], [0.005, 0.004], 8)
    return join(blade, spine, glen, cor)


def ribcage(body, lm):
    """Twelve-ish rib arcs from an ellipse fitted to the chest at each level.
    Each rib starts at the spine, sweeps round and drops toward the front."""
    v = body["verts"]
    B = body["bones"]
    top, bot = lm["AC"][2] - 0.035, lm["AI"][2] - 0.075
    out = []
    for k in range(10):
        z = top - k * (top - bot) / 9
        band = v[(np.abs(v[:, 2] - z) < 0.01) & (np.abs(v[:, 0]) < 0.2)]
        a = np.percentile(np.abs(band[:, 0]), 98) - 0.022
        y0, y1 = np.percentile(band[:, 1], 3) + 0.018, np.percentile(band[:, 1], 97) - 0.02
        cy, b = (y0 + y1) / 2, (y1 - y0) / 2
        a = min(a, 0.168 - 0.006 * abs(k - 4))
        drop = 0.03 + 0.004 * k
        for sg in (1, -1):
            pts = []
            for j in range(19):
                u = math.radians(8 + j * (158 - 8) / 18)  # 0 = back centre
                pts.append(np.array([sg * a * math.sin(u), cy + b * math.cos(u), z - drop * (1 - math.cos(u)) / 2]))
            r = [0.0045] * len(pts)
            vv, ff = tube(pts, r, 6)
            bone = "spine01" if z > B["spine01"]["head"][2] else "spine02"
            out.append((f"rib{k}.{'L' if sg > 0 else 'R'}", vv, ff, bone))
    # Sternum.
    zt, zb = top - 0.01, top - 0.6 * (top - bot)
    yf = lambda z: np.percentile(v[(np.abs(v[:, 2] - z) < 0.01) & (np.abs(v[:, 0]) < 0.04)][:, 1], 5) + 0.012
    vv, ff = tube([np.array([0, yf(zt), zt]), np.array([0, yf(zb), zb])], [0.011, 0.009], 8)
    out.append(("sternum", vv, ff, "spine01"))
    return out


def parts(body, lm, spec):
    """(name, verts, faces, bone) rigid meshes for both sides."""
    out = []
    B = body["bones"]
    for s, sg in (("R", 1), ("L", -1)):
        m = np.array([sg, 1, 1])
        L = {k: v * m for k, v in lm.items()}
        if s == "L":
            # Mirror landmark set for the left side.
            pass
        v, f = scapula_mesh(L, body["verts"] * ([1, 1, 1] if s == "R" else [-1, 1, 1]))
        out.append((f"scapula_bone.{s}", v, f if s == "R" else [x[::-1] for x in f], f"scapula.{s}"))
        sc, ac = L["SC"], L["AC"]
        mid = sc + 0.5 * (ac - sc) + [0, -0.012, 0.006]
        v, f = tube([sc, sc + 0.25 * (ac - sc) + [0, -0.01, 0.002], mid, ac + [0, 0.004, 0]],
                    [0.008, 0.007, 0.006, 0.008])
        out.append((f"clavicle_bone.{s}", v, f, f"clavicle.{s}"))
        ph, e = L["Ph"], L["E"]
        hv = sphere(ph + [0, 0, 0], 0.023)
        shaft = tube([ph, ph + 0.15 * (e - ph), e - 0.1 * (e - ph), e], [0.013, 0.012, 0.010, 0.016])
        epi = tube([e + [-0.026 * sg, 0, 0], e + [0.026 * sg, 0, 0]], [0.009, 0.009], 8)
        v, f = join(hv, shaft, epi)
        out.append((f"humerus.{s}", v, f, f"upperarm01.{s}"))
        w = B[f"wrist.{s}"]["head"]
        ulna = tube([e + [0, 0.012, -0.008], w + [0.012 * sg, 0.008, 0]], [0.008, 0.005], 8)
        out.append((f"ulna.{s}", ulna[0], ulna[1], f"lowerarm01.{s}"))
        rad = tube([e + [-0.018 * sg, 0, -0.012], w + [-0.012 * sg, -0.004, 0]], [0.006, 0.009], 8)
        out.append((f"radius.{s}", rad[0], rad[1], f"lowerarm02.{s}"))
    # Spine column.
    for n in ("spine05", "spine04", "spine03", "spine02", "spine01", "neck01", "neck02", "neck03"):
        a, b = B[n]["head"], B[n]["tail"]
        back = np.array([0, 0.035 if "spine" in n else 0.02, 0])
        segs = max(2, int(np.linalg.norm(b - a) / 0.026))
        V, F = [], []
        for k in range(segs):
            c = a + (k + 0.5) / segs * (b - a) + back
            V.append(sphere(c, 0.009, 5, 8, (1.5, 1.1, 0.75)))
        v, f = join(*V)
        out.append((f"vertebrae.{n}", v, f, n))
    out.extend(ribcage(body, lm))
    # Dumbbells in both hands.
    for eq in spec.get("blenderEquipment", []):
        if eq["type"] == "dumbbell":
            for s in ("R", "L"):
                out.append((f"dumbbell.{s}",) + dumbbell(B, s, eq) + (f"wrist.{s}",))
    return out


def dumbbell(B, s, eq):
    w = B[f"wrist.{s}"]["head"]
    idx, pky = B[f"finger2-1.{s}"]["head"], B[f"finger5-1.{s}"]["head"]
    thumb = B[f"finger1-3.{s}"]["tail"]
    across = unit(idx - pky)
    mid = (idx + pky) / 2
    n = unit(np.cross(mid - w, across))
    if (thumb - w) @ n < 0:
        n = -n
    c = mid + n * 0.024 - unit(mid - w) * 0.012
    half = eq.get("handle", 0.07)
    rad = eq.get("plate", 0.055)
    parts_ = [tube([c - across * half, c + across * half], [0.015, 0.015], 12)]
    for sgn in (-1, 1):
        a = c + sgn * across * half
        b = c + sgn * across * (half + eq.get("width", 0.05))
        parts_.append(tube([a, a + sgn * across * 0.004, b - sgn * across * 0.004, b],
                           [rad * 0.85, rad, rad, rad * 0.85], 6))
    return join(*parts_)

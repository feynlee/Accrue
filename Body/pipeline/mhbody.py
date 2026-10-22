"""Load the MakeHuman base body (CC0, from MPFB2) without Blender.

Gives the morphed mesh, the bone rest positions of the MakeHuman "default"
rig and its skin weights, all in Blender world space (metres, Z up, the body
faces -Y, the character's left is +X).
"""
import gzip
import json
import os
from collections import defaultdict

import numpy as np

MPFB = os.environ.get("MPFB_DATA", "/home/user/body/mpfb2/src/mpfb/data")


def _to_blender(v):
    # MakeHuman: decimetres, Y up, faces +Z.
    return np.stack([v[:, 0], -v[:, 2], v[:, 1]], axis=1) * 0.1


def load_obj(path=None):
    path = path or os.path.join(MPFB, "3dobjs/base.obj")
    verts, uvs, faces, fuv = [], [], [], []
    groups = defaultdict(set)
    tights = []
    helpers = defaultdict(list)
    g = None
    with open(path) as f:
        for line in f:
            if line.startswith("v "):
                verts.append([float(x) for x in line.split()[1:4]])
            elif line.startswith("vt "):
                uvs.append([float(x) for x in line.split()[1:3]])
            elif line.startswith("g "):
                g = line.split()[1]
            elif line.startswith("f "):
                idx = [p.split("/") for p in line.split()[1:]]
                vi = [int(p[0]) - 1 for p in idx]
                groups[g].update(vi)
                if g == "body":
                    faces.append(vi)
                    fuv.append([int(p[1]) - 1 for p in idx])
                elif g == "helper-tights":
                    tights.append(vi)
                if g and g.startswith("helper-"):
                    helpers[g].append(vi)
    load_obj.helpers = helpers
    return np.array(verts), np.array(uvs), faces, fuv, groups, tights


def load_target(name):
    path = os.path.join(MPFB, "targets", name + ".target.gz")
    idx, d = [], []
    with gzip.open(path, "rt") as f:
        for line in f:
            p = line.split()
            if len(p) == 4 and not line.startswith("#"):
                idx.append(int(p[0]))
                d.append([float(x) for x in p[1:]])
    return np.array(idx, dtype=int), np.array(d).reshape(-1, 3)


def _pair(value, low, mid, high):
    """MakeHuman macro slider split into weights for low/mid/high targets."""
    if value < 0.5:
        return {low: 1 - value * 2, mid: value * 2}
    return {mid: 1 - (value - 0.5) * 2, high: (value - 0.5) * 2}


def macro_targets(muscle=0.7, weight=0.45, height=0.6, proportions=1.0):
    """Targets and weights for a young adult male. Ethnicity is an even mix."""
    out = []
    for eth in ("african", "asian", "caucasian"):
        out.append((f"macrodetails/{eth}-male-young", 1 / 3))
    mus = _pair(muscle, "minmuscle", "averagemuscle", "maxmuscle")
    wei = _pair(weight, "minweight", "averageweight", "maxweight")
    for m, wm in mus.items():
        for w, ww in wei.items():
            k = wm * ww
            if k <= 0:
                continue
            out.append((f"macrodetails/universal-male-young-{m}-{w}", k))
            if height > 0.5:
                out.append((f"macrodetails/height/male-young-{m}-{w}-maxheight", k * (height - 0.5) * 2))
            elif height < 0.5:
                out.append((f"macrodetails/height/male-young-{m}-{w}-minheight", k * (0.5 - height) * 2))
            if proportions > 0.5:
                out.append((f"macrodetails/proportions/male-young-{m}-{w}-idealproportions",
                            k * (proportions - 0.5) * 2))
    return [(n, w) for n, w in out if w > 1e-4]


def build(targets=None, rig="rig.default_no_toes.json", weights="weights.default.json"):
    verts, uvs, faces, fuv, groups, tights = load_obj()
    for name, w in targets or macro_targets():
        idx, d = load_target(name)
        verts[idx] += d * w
    world = _to_blender(verts)

    rigd = json.load(open(os.path.join(MPFB, "rigs/standard", rig)))

    def point(spec):
        if spec["strategy"] == "CUBE":
            return world[sorted(groups[spec["cube_name"]])].mean(axis=0)
        if spec["strategy"] in ("MEAN", "VERTEX"):
            ids = spec.get("vertex_indices") or [spec["vertex_index"]]
            return world[ids].mean(axis=0)
        raise ValueError(spec)

    bones = {}
    for name, b in rigd.items():
        bones[name] = {"head": point(b["head"]), "tail": point(b["tail"]), "roll": b["roll"],
                       "parent": b["parent"] or None}

    wd = json.load(open(os.path.join(MPFB, "rigs/standard", weights)))["weights"]
    body_ids = sorted(groups["body"])
    # Keep only body vertices, renumbered.
    remap = -np.ones(len(world), dtype=int)
    remap[body_ids] = np.arange(len(body_ids))
    faces = [[int(remap[i]) for i in f] for f in faces]
    # Toe weights go to the foot (the rig has no separate toes).
    merged = defaultdict(dict)
    for b, lst in wd.items():
        tb = b if b in bones else "foot." + b[-1]
        for v, w in lst:
            merged[tb][v] = merged[tb].get(v, 0) + w
    wd = {b: list(d.items()) for b, d in merged.items()}
    skin = {b: [(int(remap[v]), w) for v, w in lst if remap[v] >= 0] for b, lst in wd.items() if b in bones}

    # Ground the feet: lowest body vertex at z = 0.
    pts = world[body_ids]
    dz = -pts[:, 2].min()
    pts[:, 2] += dz
    for b in bones.values():
        b["head"] = b["head"] + [0, 0, dz]
        b["tail"] = b["tail"] + [0, 0, dz]
    # Shorts: the part of MakeHuman's tights helper above mid-thigh.
    tw = world + [0, 0, dz]
    knee = bones["lowerleg01.L"]["head"][2]
    hip = bones["upperleg01.L"]["head"][2]
    sf = [f for f in tights if min(tw[i][2] for i in f) > knee + 0.17
          and max(tw[i][2] for i in f) < hip + 0.07 and max(abs(tw[i][0]) for i in f) < 0.24]
    sids = sorted({i for f in sf for i in f})
    smap = {v: k for k, v in enumerate(sids)}
    shorts = {"verts": tw[sids], "faces": [[smap[i] for i in f] for f in sf],
              "skin": {b: [(smap[v], w) for v, w in lst if v in smap] for b, lst in wd.items() if b in bones}}
    joints = {g: world[sorted(v)].mean(axis=0) + [0, 0, dz] for g, v in groups.items() if g.startswith("joint-")}
    return {"verts": pts, "uvs": uvs, "faces": faces, "fuv": fuv, "bones": bones, "skin": skin, "joints": joints,
            "shorts": shorts, "world": world + [0, 0, dz], "helpers": load_obj.helpers}

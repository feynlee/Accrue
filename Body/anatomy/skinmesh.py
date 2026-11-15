"""Z-Anatomy's body surface as one rigged, dressed skin, shared by the exercise scripts.

skin.npz comes from export_skin.py. The region patches are welded, the genital
region and toes are smoothed, every vertex is weighted to the bones of its own
body part, and each vertex gets a clothing class: 0 skin, 1 top, 2 shorts, 3 shoes.
"""
import os
import re
from types import SimpleNamespace

import bmesh
import bpy
import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree


def _weld(V, F, R, pairs):
    """V, F and R with each pair of vertices made one, and the faces that collapse dropped."""
    n, label = connected_components(coo_matrix((np.ones(len(pairs)), (pairs[:, 0], pairs[:, 1])), shape=(len(V),) * 2),
                                    directed=False)
    P = np.zeros((n, 3))
    np.add.at(P, label, V)
    P /= np.bincount(label, minlength=n)[:, None]
    F = label[F]
    keep = (F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 0] != F[:, 2])
    return P, F[keep], R[keep]


def _rim(F):
    """The edges that belong to one face only."""
    E = np.sort(np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), 1)
    E, count = np.unique(E, axis=0, return_counts=True)
    return E[count == 1]


def _clean(V, F, R, where, dist=1.5e-3):
    """V, F and R without the needle-thin triangles where `where(point)` holds.

    They sit where patches meet, and a face that thin has no dependable normal, which shows
    as a dark pit in the shaded surface.
    """
    bm = bmesh.new()
    verts = [bm.verts.new(p) for p in V]
    region = bm.faces.layers.int.new("region")
    for f, r in zip(F, R):
        try:
            bm.faces.new([verts[i] for i in f])[region] = int(r)
        except ValueError:  # the same face twice
            pass
    thin = [e for e in bm.edges if all(where(v.co) for v in e.verts)]
    bmesh.ops.dissolve_degenerate(bm, dist=dist, edges=thin)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.verts.index_update()
    out = (np.array([v.co[:] for v in bm.verts], float), np.array([[v.index for v in f.verts] for f in bm.faces]),
           np.array([f[region] for f in bm.faces]))
    bm.free()
    return out


def _untangle(V, F, inside, rounds=20):
    """V with the faces that fold back over their neighbours relaxed flat (among `inside` vertices)."""
    nbr = [set() for _ in V]
    for a, b, c in F:
        nbr[a].update((b, c)); nbr[b].update((a, c)); nbr[c].update((a, b))
    for _ in range(rounds):
        fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
        vn = np.zeros_like(V)
        for c in range(3):
            np.add.at(vn, F[:, c], fn)
        unit = lambda n: n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)  # noqa: E731
        agree = (unit(fn) * unit(unit(vn)[F].sum(1))).sum(1)
        bad = np.unique(F[(agree < 0.3) & inside[F].all(1)])
        if not len(bad):
            break
        V[bad] = [V[list(nbr[i])].mean(0) for i in bad]
    print("folded faces left", len(bad))
    return V


def build(SKIN, trees, J, arm, split=None):
    """The welded skin as a Blender object bound to arm, plus the arrays it came from.

    split(points, bones, weights) may add bones and reshare the weights (the forearm twist).
    """
    z = np.load(SKIN)
    V0, F0, R0, NAMES = z["V"], z["F"], z["R"], [str(n) for n in z["names"]]
    # The region patches share their borders: weld them into one surface. Along a few borders on
    # the trunk the two patches are up to a millimetre apart, which would open when the body bends.
    V, F, R = _weld(V0, F0, R0, cKDTree(V0).query_pairs(2e-5, output_type="ndarray"))
    rim = np.unique(_rim(F))
    rim = rim[(np.abs(V[rim, 0]) < 0.2) & (V[rim, 2] > 0.72) & (V[rim, 2] < 1.5)]
    V, F, R = _weld(V, F, R, rim[cKDTree(V[rim]).query_pairs(1e-3, output_type="ndarray")])
    V, F, R = _clean(V, F, R, lambda p: abs(p.x) < 0.2 and 0.72 < p.z < 1.5)
    V = _untangle(V, F, (np.abs(V[:, 0]) < 0.2) & (V[:, 2] > 0.72) & (V[:, 2] < 1.5))
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
    # The skin slides over the shoulder blade. It follows the blade next to the shoulder joint and
    # less and less toward the spine, so the blade can turn under it without folding the back.
    for s in "lr":
        if f"scapula.{s}" in bones and "thorax" in bones:
            j, t = bones.index(f"scapula.{s}"), bones.index("thorax")
            x = np.clip((0.16 - np.linalg.norm(V - J[f"gh.{s}"], axis=1)) / 0.10, 0, 1)
            moved = W[:, j] * 0.8 * (1 - x * x * (3 - 2 * x))
            W[:, j] -= moved
            W[:, t] += moved
    if split:
        bones, W = split(V, bones, W)
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
    return SimpleNamespace(V=V, F=F, R=R, NAMES=NAMES, nbr=nbr, bones=bones, W=W, dom=dom, inside=inside,
                           waist=waist, hem=hem, ankle=J["ankle.l"][2] + 0.005, base=base_,
                           cls=cls, COLORS=COLORS, skin=skin)

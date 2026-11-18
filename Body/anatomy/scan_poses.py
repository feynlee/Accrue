"""Scan every stress pose for muscles that crumple or tear and bone that comes uncovered.
   python scan.py za-full.glb rom.json out.json"""
import os, sys, json, math
os.environ["ZA_GLB"] = sys.argv[-3]
sys.path.insert(0, "/home/user/accrue/Body/anatomy")
from rigbase import *
from mathutils import Quaternion, Vector
from mathutils.bvhtree import BVHTree
bind_all()
REST4 = {b.name: b.matrix_local.copy() for b in arm.data.bones}
frames = json.load(open(sys.argv[-2]))[0]["frames"]
names = [p["name"] for p in json.load(open("/tmp/claude-0/body/audit/poses.json"))]
mus = [o for o in objs if kind(o) == "muscle"]; bones = [o for o in objs if kind(o) == "bone" and bone_of(base(o.name)) != "head"]
def posed(o, dg):
    e = o.evaluated_get(dg); m = e.data; P = np.empty(len(m.vertices) * 3); m.vertices.foreach_get("co", P)
    P = P.reshape(-1, 3); M = np.array(e.matrix_world); return P @ M[:3, :3].T + M[:3, 3]
def tris(o):
    o.data.calc_loop_triangles(); T = np.empty(len(o.data.loop_triangles) * 3, int); o.data.loop_triangles.foreach_get("vertices", T); return T.reshape(-1, 3)
def edges(o):
    E = np.empty(len(o.data.edges) * 2, int); o.data.edges.foreach_get("vertices", E); return E.reshape(-1, 2)
TR = {o.name: tris(o) for o in mus + bones}; ED = {o.name: edges(o) for o in mus}
def normals(P, T):
    n = np.zeros_like(P); f = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    for k in range(3): np.add.at(n, T[:, k], f)
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
def cover(dg):
    V, F, k = [], [], 0; MP = {}
    for o in mus:
        P = posed(o, dg); MP[o.name] = P; V.append(P); F.append(TR[o.name] + k); k += len(P)
    bvh = BVHTree.FromPolygons(np.concatenate(V).tolist(), np.concatenate(F).tolist())
    owner = np.concatenate([np.full(len(TR[o.name]), i) for i, o in enumerate(mus)])
    out = {}; who = {}
    for o in bones:
        P = posed(o, dg); N = normals(P, TR[o.name]); idx = np.arange(0, len(P), 4)
        hit = [bvh.ray_cast(Vector(P[i] + N[i] * 0.0015), Vector(N[i]), 0.06)[2] for i in idx]
        out[o.name] = np.array([h is not None for h in hit]); who[o.name] = np.array([-1 if h is None else owner[h] for h in hit])
    return out, MP, who
def pose(fr):
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"; q = fr["local"].get(pb.name)
        pb.rotation_quaternion = Quaternion(q) if q else Quaternion(); pb.location = (0, 0, 0)
    arm.pose.bones["pelvis"].location = REST4["pelvis"].to_3x3().transposed() @ (Vector(fr["root"]) - REST4["pelvis"].translation)
    bpy.context.view_layer.update(); return bpy.context.evaluated_depsgraph_get()
C0, P0, WHO = cover(pose(frames[0]))
from collections import Counter
SKIP = r"phalanx|metacarp|Pisiform|Lunate|Triquet|Hamate|Capitate|Scaphoid|Trapez"
L0 = {n: np.linalg.norm(P0[n][ED[n][:, 0]] - P0[n][ED[n][:, 1]], axis=1) for n in P0}
res = []
for k, fr in enumerate(frames):
    if k == 0: continue
    C, P, _ = cover(pose(fr))
    bare = Counter()
    for n in C:
        if re.search(SKIP, n): continue
        for w in WHO[n][C0[n] & ~C[n]]: bare[(n.replace(".001", ""), mus[w].name.replace(".001", ""))] += 1
    bare = {f"{a} < {b}": v for (a, b), v in bare.items() if v >= 6 and a.endswith(".l") or (v >= 6 and not re.search(r"\.(l|r)$", a))}
    sq = {}
    for n in P:
        L = np.linalg.norm(P[n][ED[n][:, 0]] - P[n][ED[n][:, 1]], axis=1) / np.maximum(L0[n], 1e-6)
        a, b = float((L < 0.45).mean()), float((L > 2.2).mean())
        if (a > 0.04 or b > 0.04) and not n.endswith(".r.001"): sq[n.replace(".001", "")] = (round(a, 3), round(b, 3))
    res.append({"pose": names[k] if k < len(names) else str(k), "k": k, "bare": bare, "edges": sq})
    print(k, res[-1]["pose"], "| bare:", sorted(bare.items(), key=lambda x: -x[1])[:8], "| crumple/stretch:", sorted(sq.items(), key=lambda x: -max(x[1]))[:8], flush=True)
json.dump(res, open(sys.argv[-1], "w"), indent=1)

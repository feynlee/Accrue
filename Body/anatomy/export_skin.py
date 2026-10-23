"""Export Z-Anatomy's body surface (the "Regions of human body" patches) as one skin.

    python export_skin.py Startup.blend skin.npz

Z-Anatomy (CC BY-SA 4.0) draws the skin as about 250 named region patches that
share their borders. They are written here in world space, unwelded, with the
region name of every face, for climb_za.py to weld, dress and rig.
"""
import re
import sys

import bpy
import numpy as np

SRC, OUT = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.open_mainfile(filepath=SRC)
V, F, R, names = [], [], [], []
off = 0
for o in bpy.data.collections["9: Regions of human body"].all_objects:
    if o.type != "MESH" or len(o.data.vertices) < 3:
        continue
    if re.search(r"hair", o.name, re.I) or re.search(r"\.[gjt]$", o.name):
        continue
    M = np.array(o.matrix_world)
    v = np.array([tuple(x.co) for x in o.data.vertices])
    V.append(v @ M[:3, :3].T + M[:3, 3])
    for p in o.data.polygons:
        idx = [i + off for i in p.vertices]
        for k in range(1, len(idx) - 1):  # fan triangulation
            F.append((idx[0], idx[k], idx[k + 1]))
            R.append(len(names))
    names.append(o.name)
    off += len(v)
np.savez(OUT, V=np.concatenate(V), F=np.array(F), R=np.array(R), names=np.array(names))
print("regions", len(names), "verts", off, "tris", len(F))

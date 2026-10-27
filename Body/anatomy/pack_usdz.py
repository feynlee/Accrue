"""Shrink the USD that export_app.py writes and package it as the app's USDZ.

    python pack_usdz.py body.usdc Body.usdz      (needs usd-core: pip install usd-core)

Blender writes one normal per face corner; the body is smooth everywhere, so one
normal per vertex looks the same at a third of the size. Blender-only data goes too.

RealityKit may merge the meshes and drops prim and material names, so each part's
material is tagged by its roughness: part i (in body-parts.json, written next to
OUT) has roughness (i + 1) / 100. The app reads the tag and paints the part.
"""
import json
import os
import sys
import tempfile

import numpy as np
from pxr import Sdf, Usd, UsdGeom, UsdShade, UsdUtils

SRC, OUT = sys.argv[-2], sys.argv[-1]
stage = Usd.Stage.Open(SRC)
for prim in stage.Traverse():
    if prim.IsA(UsdGeom.Mesh):
        mesh = UsdGeom.Mesh(prim)
        normals = mesh.GetNormalsAttr()
        if mesh.GetNormalsInterpolation() == UsdGeom.Tokens.faceVarying:
            N = np.array(normals.Get(), dtype=np.float64)
            idx = np.array(mesh.GetFaceVertexIndicesAttr().Get())
            n_pts = len(mesh.GetPointsAttr().Get())
            acc = np.zeros((n_pts, 3))
            np.add.at(acc, idx, N)
            acc /= np.maximum(np.linalg.norm(acc, axis=1, keepdims=True), 1e-9)
            normals.Set(acc.astype(np.float32))
            mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
    for attr in prim.GetAttributes():
        if attr.GetName().startswith(("userProperties:blender", "primvars:blender")):
            prim.RemoveProperty(attr.GetName())

mats = sorted((p for p in stage.Traverse() if p.IsA(UsdShade.Material)), key=lambda p: p.GetName())
names = []
for prim in mats:
    for child in prim.GetChildren():
        shader = UsdShade.Shader(child)
        if shader and shader.GetInput("roughness"):
            shader.GetInput("roughness").Set((len(names) + 1) / 100)
            names.append(prim.GetName())
            break
json.dump(names, open(os.path.join(os.path.dirname(os.path.abspath(OUT)), "body-parts.json"), "w"))
print("tagged", len(names), "parts")

with tempfile.TemporaryDirectory() as tmp:
    flat = os.path.join(tmp, "Body.usdc")
    stage.GetRootLayer().Export(flat)
    UsdUtils.CreateNewARKitUsdzPackage(Sdf.AssetPath(flat), OUT)
print("wrote", OUT, os.path.getsize(OUT) // 1024, "KB")

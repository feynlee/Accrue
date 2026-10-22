"""Bake one exercise into a GLB.

    python make.py ../exercises/dumbbell-seated-shoulder-press.json ../out/press.glb

Uses Blender as a Python module (bpy) only to build the skinned armature and
write glTF; the posing maths is in pose.py.
"""
import json
import math
import sys

import bpy
import numpy as np
from mathutils import Matrix

import mhbody
import pose as P
import skeleton


def ease(x, kind):
    if kind == "linear":
        return x
    return x * x * (3 - 2 * x)


def interp(keys, t, kind):
    """Interpolate nested dicts of numbers / number lists between keys."""
    for i in range(len(keys) - 1):
        a, b = keys[i], keys[i + 1]
        if a["t"] <= t <= b["t"]:
            u = ease((t - a["t"]) / max(1e-9, b["t"] - a["t"]), kind)
            return mix(a["pose"], b["pose"], u)
    return keys[-1]["pose"]


def mix(a, b, u):
    if isinstance(a, dict):
        out = {}
        for k in set(a) | set(b):
            if k in a and k in b:
                out[k] = mix(a[k], b[k], u)
            else:
                out[k] = a.get(k, b.get(k))
        return out
    if isinstance(a, list):
        return [mix(x, y, u) for x, y in zip(a, b)]
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return a + (b - a) * u
    return a if u < 0.5 else b


def merge(base, over):
    out = json.loads(json.dumps(base))
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = merge(out[k], v)
        else:
            out[k] = v
    return out


def mesh_object(name, verts, faces, skin=None, groups=()):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if skin:
        for bname, lst in skin.items():
            if not lst:
                continue
            vg = ob.vertex_groups.new(name=bname)
            for v, w in lst:
                vg.add([v], w, "REPLACE")
    for bname in groups:
        vg = ob.vertex_groups.new(name=bname)
        vg.add(list(range(len(verts))), 1.0, "REPLACE")
    return ob


def main(spec_path, out_path):
    spec = json.load(open(spec_path))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    body = mhbody.build()
    lm = skeleton.landmarks(body)

    # Armature: MakeHuman default rig plus one bone per shoulder blade.
    arm = bpy.data.armatures.new("rig")
    rig = bpy.data.objects.new("rig", arm)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    bones = dict(body["bones"])
    for s, sg in (("R", 1), ("L", -1)):
        m = np.array([sg, 1, 1])
        bones[f"scapula.{s}"] = {"head": lm["AC"] * m, "tail": lm["AI"] * m, "roll": 0.0,
                                 "parent": f"clavicle.{s}"}
    for n, d in bones.items():
        eb = arm.edit_bones.new(n)
        eb.head, eb.tail, eb.roll = tuple(d["head"]), tuple(d["tail"]), d["roll"]
    for n, d in bones.items():
        if d["parent"]:
            arm.edit_bones[n].parent = arm.edit_bones[d["parent"]]
    bpy.ops.object.mode_set(mode="OBJECT")
    for n, d in bones.items():
        d["matrix"] = np.array(arm.bones[n].matrix_local.to_3x3())
    rest = {n: np.array(arm.bones[n].matrix_local) for n in bones}

    # Skin.
    skin = skeleton.scapula_weights(body, lm)
    objs = [mesh_object("body", body["verts"], body["faces"], skin)]
    objs.append(mesh_object("shorts", body["shorts"]["verts"], body["shorts"]["faces"], body["shorts"]["skin"]))
    skeleton.muscle_colors(objs[0], body, lm)
    for name, verts, faces, bone in skeleton.parts(body, lm, spec):
        objs.append(mesh_object(name, verts, faces, groups=[bone]))
    for ob in objs:
        for poly in ob.data.polygons:
            poly.use_smooth = True
        ob.parent = rig
        mod = ob.modifiers.new("arm", "ARMATURE")
        mod.object = rig

    # Bake.
    model = P.Body(bones, lm)
    fps = spec.get("fps", 30)
    n = int(round(spec["duration"] * fps))
    scene = bpy.context.scene
    scene.render.fps = fps
    scene.frame_start, scene.frame_end = 0, n
    keys = [{"t": k["t"], "pose": merge(spec["base"], k.get("pose", {}))} for k in spec["keys"]]
    report = []
    rig.animation_data_create()
    for f in range(n + 1):
        t = f / n
        pz = interp(keys, t, spec.get("easing", "smooth"))
        D, rep = model.pose(pz)
        rep["t"] = round(t, 4)
        report.append(rep)
        for name, pb in rig.pose.bones.items():
            Rb = rest[name]
            p = bones[name]["parent"]
            Dp = D[p] if p else np.eye(4)
            basis = np.linalg.inv(Rb) @ np.linalg.inv(Dp) @ D[name] @ Rb
            pb.matrix_basis = Matrix(basis.tolist())
            pb.keyframe_insert("location", frame=f)
            pb.keyframe_insert("rotation_quaternion", frame=f)

    json.dump(report, open(out_path.replace(".glb", ".report.json"), "w"))
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", export_animations=True,
                              export_force_sampling=True, export_vertex_color="ACTIVE",
                              export_all_vertex_colors=True, export_active_vertex_color_when_no_material=True,
                              export_yup=True, export_apply=False, export_skins=True,
                              export_def_bones=False, export_optimize_animation_size=True)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])

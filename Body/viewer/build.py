"""Fill the viewer template with a baked GLB and its report.

    python build.py ../out/press.glb ../exercises/dumbbell-seated-shoulder-press.json out.html
"""
import base64
import json
import sys

glb, spec_path, out = sys.argv[1:4]
spec = json.load(open(spec_path))
rep = json.load(open(glb.replace(".glb", ".report.json")))
keep = ["elev", "scapUpRot", "scapTilt", "clavElev", "ghElev", "elbowFlex", "AI"]
slim = [{s: {k: f[s][k] for k in keep} for s in ("R", "L")} for f in rep]
view = spec.get("viewer", {})
html = open(__file__.replace("build.py", "template.html")).read()
html = (html.replace("__GLB__", base64.b64encode(open(glb, "rb").read()).decode())
        .replace("__REPORT__", json.dumps(slim, separators=(",", ":")))
        .replace("__DURATION__", str(spec["duration"]))
        .replace("__KEYS__", json.dumps([{"t": k["t"], "phase": k["phase"]} for k in spec["keys"]]))
        .replace("__SEAT__", str(view.get("seat", 0.46)))
        .replace("__PADZ__", str(view.get("padZ", -0.16))))
open(out, "w").write(html)
print(out, len(html) // 1024, "KB")

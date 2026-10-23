"""Build a single-page browser of the exercise families for review.

Usage: python Catalog/tools/build-family-browser.py <out.html>
Run build-families.py first.
"""
import collections
import json
import os
import sys

FAM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "families")
idx = json.load(open(os.path.join(FAM, "index.json")))
fams = {f["id"]: json.load(open(os.path.join(FAM, f["id"] + ".json"))) for f in idx}
exmap = json.load(open(os.path.join(FAM, "exercise-map.json")))
members = collections.defaultdict(list)
for eid, e in sorted(exmap.items(), key=lambda x: x[1]["name"]):
    members[e["family"]].append([e["name"], e.get("subtype", "")])
muscles = {k: v["label"] for k, v in json.load(open(os.path.join(FAM, "muscles.json")))["groups"].items()}
props = {k: v["label"] for k, v in json.load(open(os.path.join(FAM, "props.json")))["props"].items()}
data = {"index": idx, "fams": fams, "members": members, "muscles": muscles, "props": props}
blob = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
tpl = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "family-browser.html")).read()
open(sys.argv[1], "w").write(tpl.replace("/*DATA*/", blob))
print("wrote", sys.argv[1], os.path.getsize(sys.argv[1]) // 1024, "KB")

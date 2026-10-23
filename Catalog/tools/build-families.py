"""Build the app-ready family index from the family files.

Usage: python Catalog/tools/build-families.py <openGym catalogue/exercises dir>

Reads Catalog/families/*.json (one per family), muscles.json, props.json and
overrides.json, then writes:
  Catalog/families/index.json         families with name, kind, model, tracking, MET, member count
  Catalog/families/exercise-map.json  openGym id -> family, subtype and variant tweaks
  Catalog/families/references.json   every cited source, by key
  Catalog/families/met.json           MET per family, subtype and intensity
and prints any problems found in the family files.
"""
import collections
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FAM = os.path.join(HERE, "..", "families")
sys.path.insert(0, HERE)
import families as rules  # noqa: E402

SHARED = {"index", "exercise-map", "references", "met", "muscles", "props", "overrides"}
JOINTS = {"t", "phase", "trunk", "roll", "trunkRot", "trunkSide", "neckSide", "neckRot", "ankleEv", "toeFlex", "neck", "lumbar", "hipFlex", "hipAbd", "hipRot", "kneeFlex", "ankleDorsi",
          "shoulderFlex", "shoulderAbd", "shoulderRot", "elbowFlex", "forearm", "wristExt", "scapula", "note"}
SCAP = {"protraction", "elevation", "upRot", "tilt"}

# Variant tweaks read from the exercise name, in the order the app shows them.
MODS = {
    "position": [("incline", r"\bincline"), ("decline", r"\bdecline"), ("seated", r"\bseated|\bsitting"), ("lying", r"\blying|\bsupine|\bprone"),
                 ("kneeling", r"\bkneeling|half kneeling|\bknee\b"), ("hanging", r"\bhanging"), ("standing", r"\bstanding"), ("bent-over", r"bent[- ]over")],
    "side": [("alternating", r"alternat"), ("single", r"single|one (arm|leg|hand)|unilateral|\bone\b")],
    "grip": [("wide", r"\bwide"), ("close", r"\bclose|narrow|diamond"), ("neutral", r"neutral|hammer"),
             ("underhand", r"underhand|reverse grip|supinated|chin[- ]?up"), ("overhand", r"overhand|pronated")],
    "stance": [("sumo", r"\bsumo"), ("split", r"\bsplit|staggered"), ("wide", r"wide stance"), ("narrow", r"narrow stance")],
    "tempo": [("pause", r"\bpause"), ("negative", r"negative|eccentric"), ("isometric", r"isometric|\bhold\b|static"), ("explosive", r"jump|explosive|power\b|speed")],
}


def load_families():
    fams, problems = {}, []
    muscles = json.load(open(os.path.join(FAM, "muscles.json")))["groups"]
    props = json.load(open(os.path.join(FAM, "props.json")))["props"]
    for p in sorted(glob.glob(os.path.join(FAM, "*.json"))):
        fid = os.path.basename(p)[:-5]
        if fid in SHARED:
            continue
        try:
            f = json.load(open(p))
        except json.JSONDecodeError as e:
            problems.append(f"{fid}: bad JSON ({e})")
            continue
        if f.get("id") != fid:
            problems.append(f"{fid}: id is {f.get('id')}")
        keys = {s["key"] for s in f.get("sources", [])}
        cited = set()
        for part in ("cues", "mistakes"):
            for x in f.get(part, []):
                cited.update(x.get("refs", []))
        for k in sorted(cited - keys):
            problems.append(f"{fid}: cites {k} but has no source for it")
        for m in f.get("muscles", {}).get("primary", []) + f.get("muscles", {}).get("secondary", []):
            if m not in muscles:
                problems.append(f"{fid}: unknown muscle group {m}")
        for e in f.get("equipment", []):
            if e not in props:
                problems.append(f"{fid}: unknown equipment {e}")
        frames = list(f.get("motion", {}).get("keyframes", []))
        for s in f.get("subtypes", []):
            frames += s.get("keyframes", [])
            try:
                re.compile(s.get("match", ""))
            except re.error:
                problems.append(f"{fid}: bad subtype regex {s.get('match')}")
        for k in frames:
            for j in k:
                base = j[:-1] if j.endswith("L") and j[:-1] in JOINTS else j
                if base not in JOINTS:
                    problems.append(f"{fid}: unknown joint key {j}")
            for j in k.get("scapula", {}) if isinstance(k.get("scapula"), dict) else []:
                if j not in SCAP:
                    problems.append(f"{fid}: unknown scapula key {j}")
        fams[fid] = f
    return fams, props, problems


def same_work(a, b):
    """Two citations of one key name the same work when most title words match."""
    wa, wb = set(re.findall(r"[a-z]{4,}", a.lower())), set(re.findall(r"[a-z]{4,}", b.lower()))
    return not wa or not wb or len(wa & wb) / min(len(wa), len(wb)) >= 0.5


def mods_for(name):
    out = {}
    for kind, opts in MODS.items():
        for val, rx in opts:
            if re.search(rx, name):
                out[kind] = val
                break
    return out


def main(src):
    fams, props, problems = load_families()
    over = {}
    p = os.path.join(FAM, "overrides.json")
    if os.path.exists(p):
        over = json.load(open(p))
    equip = {w: pid for pid, pr in props.items() for w in pr.get("openGym", [])}
    exmap, count = {}, collections.Counter()
    missing = collections.Counter()
    for fpath in sorted(glob.glob(os.path.join(src, "*.json"))):
        r = json.load(open(fpath))
        if "name" not in r:
            continue
        fid = over.get(r["id"]) or rules.assign(r)[0]
        if fid not in fams:
            missing[fid] += 1
        name = r["name"].lower()
        e = {"family": fid, "name": r["name"]}
        sub = next((s["id"] for s in fams.get(fid, {}).get("subtypes", []) if re.search(s["match"], name)), None)
        if sub:
            e["subtype"] = sub
        if r.get("equipment") in equip and equip[r["equipment"]] != "none":
            e["equipment"] = equip[r["equipment"]]
        m = mods_for(name)
        if m:
            e["mods"] = m
        exmap[r["id"]] = e
        count[fid] += 1
    index = []
    for fid, f in sorted(fams.items()):
        index.append({k: f[k] for k in ("id", "name", "kind", "bodyModel", "tracking", "met", "confidence") if k in f}
                     | {"members": count.get(fid, 0), "subtypes": len(f.get("subtypes", []))})
    refs, met = {}, {}
    for fid, f in fams.items():
        for s in f.get("sources", []):
            prev = refs.get(s["key"])
            if prev and not same_work(prev.get("cite", ""), s.get("cite", "")):
                problems.append(f"source key {s['key']} means different things in {prev['_in']} and {fid}")
            refs.setdefault(s["key"], dict(s, _in=fid))
        if "met" in f:
            met[fid] = {"met": f["met"], "code": f.get("metCode")}
            sub = {s["id"]: s["met"] for s in f.get("subtypes", []) if "met" in s}
            if sub:
                met[fid]["subtypes"] = sub
    refs = {k: {kk: vv for kk, vv in v.items() if kk not in ("key", "_in")} for k, v in sorted(refs.items())}
    w = lambda name, obj: json.dump(obj, open(os.path.join(FAM, name), "w"), indent=1, ensure_ascii=False)
    w("index.json", index)
    w("exercise-map.json", exmap)
    w("references.json", refs)
    w("met.json", met)
    print(f"{len(fams)} families, {len(exmap)} exercises, {len(refs)} sources")
    for fid, n in missing.most_common():
        print(f"  no family file yet: {fid} ({n} exercises)")
    for pr in problems:
        print("  problem:", pr)


if __name__ == "__main__":
    main(sys.argv[1])

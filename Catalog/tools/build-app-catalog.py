#!/usr/bin/env python3
"""Build the catalog file the app ships: AccrueKit/Sources/AccrueKit/Resources/catalog.json.

It merges the family files, the exercise map, muscles, props and Accrue's own
cardio sessions into one compact JSON. Run it after any change in Catalog/families:

    python3 Catalog/tools/build-app-catalog.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FAMILIES = ROOT / "Catalog" / "families"
OUT = ROOT / "AccrueKit" / "Sources" / "AccrueKit" / "Resources" / "catalog.json"
SHARED = {"index.json", "exercise-map.json", "overrides.json", "muscles.json",
          "props.json", "met.json", "references.json"}
# Fields the app does not read. Sources stay in references.json for the research record.
DROP = {"sources", "research"}
# openGym repeats some exercises as camera angles ("(side pov)") or versions ("v. 2").
DUPLICATE = re.compile(r"\((?:[a-z ]*\b(?:pov|view|angle)\b[a-z ]*)\)|\bv\. ?\d+\b")
# Workout formats become timed exercises later; they are not single exercises.
SKIP_SESSION_GROUPS = {"Workout formats"}


def load(name):
    return json.loads((FAMILIES / name).read_text())


def main():
    families = []
    session_family = {}
    for path in sorted(FAMILIES.glob("*.json")):
        if path.name in SHARED:
            continue
        family = {k: v for k, v in json.loads(path.read_text()).items() if k not in DROP}
        families.append(family)
        for sub in family.get("subtypes", []):
            if sub.get("sessionId"):
                session_family[sub["sessionId"]] = (family["id"], sub["id"])

    exercises = []
    for ex_id, entry in load("exercise-map.json").items():
        item = {"id": ex_id, "name": entry["name"], "family": entry["family"]}
        for key in ("subtype", "equipment", "mods"):
            if entry.get(key):
                item[key] = entry[key]
        if DUPLICATE.search(entry["name"]):
            item["hidden"] = True
        exercises.append(item)

    sessions = json.loads((ROOT / "Catalog" / "cardio-sessions.json").read_text())
    for group in sessions["groups"]:
        if group["group"] in SKIP_SESSION_GROUPS:
            continue
        for s in group["items"]:
            item = {"id": "s:" + s["id"], "name": s["name"], "tracking": s["tracking"],
                    "healthKit": s["healthKit"], "group": group["group"]}
            if s["id"] in session_family:
                item["family"], item["subtype"] = session_family[s["id"]]
            if s.get("metrics"):
                item["metrics"] = s["metrics"]
            exercises.append(item)

    muscles = load("muscles.json")
    props = load("props.json")
    catalog = {
        "version": 1,
        "families": families,
        "exercises": exercises,
        "muscles": {k: {"label": v["label"], "region": v["region"]} for k, v in muscles["groups"].items()},
        "props": {k: {"label": v["label"]} for k, v in props["props"].items()},
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(catalog, ensure_ascii=False, separators=(",", ":")))
    print(f"{OUT.relative_to(ROOT)}: {len(families)} families, {len(exercises)} exercises, "
          f"{OUT.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()

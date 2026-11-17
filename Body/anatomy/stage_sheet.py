"""One sheet per exercise from the frames stage_check.sh rendered: a row per view, a column per frame.

    python stage_sheet.py dump.json out_dir      (frames in out_dir/frames; needs Pillow)
"""
import glob
import json
import os
import sys

from PIL import Image, ImageDraw

dump, out = sys.argv[1], sys.argv[2]
for e in json.load(open(dump)):
    stem = f"{e['family']}__{e['id']}"
    files = glob.glob(os.path.join(out, "frames", stem + "__*.png"))
    if not files:
        continue
    views, frames = [], []
    for f in sorted(files, key=os.path.getmtime):
        view, k = os.path.basename(f)[len(stem) + 2:-4].rsplit("__", 1)
        if view not in views:
            views.append(view)
        if int(k) not in frames:
            frames.append(int(k))
    frames.sort()
    first = Image.open(files[0])
    w, h = first.size
    sheet = Image.new("RGB", (w * len(frames), h * len(views) + 18), "white")
    ImageDraw.Draw(sheet).text((4, 3), f"{e['id']}  {e['name']}  ({e['family']}; {', '.join(e['kinds'])})   rows: {', '.join(views)}", fill="black")
    for r, view in enumerate(views):
        for c, k in enumerate(frames):
            p = os.path.join(out, "frames", f"{stem}__{view}__{k}.png")
            if os.path.exists(p):
                sheet.paste(Image.open(p).convert("RGB"), (c * w, 18 + r * h))
    sheet.save(os.path.join(out, stem + ".png"))
    print(os.path.join(out, stem + ".png"))

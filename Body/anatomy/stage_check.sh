#!/bin/bash
# stage_check.sh <ids> <out dir> [frames]: look at exercises as the app shows them, without a Mac.
#
#   Body/anatomy/stage_check.sh 0025,0043 /tmp/check 6
#
# Dumps the listed catalog exercises from AccrueKit (in Docker) and renders each as one sheet,
# <out dir>/<family>__<id>.png: a row per view (the app's own, the side, the front), a column
# per moment of the loop. FAULTS=1 adds a column per common mistake. VIEWS adds or replaces
# views, as render_app.py reads them ("hands:-60:10:hand.r:0.3" is a close-up on the right
# hand). BODY_TOOLS is the folder holding the Blender Python venv (.venv).
set -e
ids=$1; out=$2; n=${3:-6}
root=$(git rev-parse --show-toplevel)
tools=${BODY_TOOLS:-/tmp/claude-0/body}
mkdir -p "$out"
pgrep dockerd >/dev/null || (nohup dockerd >/tmp/dockerd.log 2>&1 &)
docker run --rm -e BODY_DUMP=/pkg/.build/check-dump.json -e BODY_DUMP_IDS="$ids" -e BODY_DUMP_FRAMES="$n" \
    ${FAULTS:+-e BODY_DUMP_FAULTS=1} -v "$root/AccrueKit":/pkg -w /pkg swift:6.1-noble \
    swift test --filter BodyPropsTests/dumpForRenderer 2>&1 | grep -E "error|failed|passed after" | tail -20
rm -rf "$out/frames"
SIZE=${SIZE:-360} VIEWS="${VIEWS:-app,side:-90:5,front:0:5}" "$tools/.venv/bin/python" "$root/Body/anatomy/render_app.py" \
    "$root/Accrue/Body/Body.usdz" "$root/AccrueKit/.build/check-dump.json" "$out/frames" 2>&1 | grep -E "Error|Traceback" | tail -5 || true
python3 "$root/Body/anatomy/stage_sheet.py" "$root/AccrueKit/.build/check-dump.json" "$out"

# Exercise catalog

One JSON file per exercise in `exercises/`. The app reads the text and draws the animation itself, so there are no image or video files.

## Exercise file

| Field | Meaning |
|---|---|
| `id` | Permanent slug. Workouts store it, so never rename or reuse one. |
| `kind` | `strength`, `bodyweight` or `cardio` |
| `setting`, `equipment` | Where it can be done and what it needs |
| `openGymId` | Matching openGym catalogue id, for cross-reference only (see `SOURCES.md`) |
| `tracking` | What the log records: `weight_reps`, `reps`, `hold`, `distance_time_hr`, `time_hr` |
| `setup`, `steps` | Set-up list, then one entry per phase of the rep. Step `phase` names match the animation phases. |
| `jointCues` | Per joint: the cue and why it matters |
| `breathing`, `tempo`, `mistakes`, `safety` | Coaching text |
| `easier`, `harder` | Ids of regressions and progressions (may point to exercises not written yet) |
| `refs` | Keys into `references.json` |
| `animations` | One or more views (side, front, from above) |

## Animation data

`rig.js` draws a figure from keyframed poses. Angles are degrees on screen: 0 points down, 90 right, 180 up. A limb is given by angles (`uaR`/`faR` upper arm and forearm, `thR`/`shR` thigh and shin) or by an end point (`handR`, `footR`) solved with two-bone IK. `R` is the near side in side views and screen-right in front views. `scap: [retraction, elevation]` moves the shoulder joint to show shoulder-blade position. `uaS`, `faS`, `thS`, `shS` shorten a segment that points at the camera.

Each view also lists `equipment`, a `breath` track (`inhale`, `exhale`, `hold` over time windows) and `cues`: overlays that appear in a time window (`arrow`, `glow`, `arc`, `rotate`, `line`, `vline`, `trace`) with the cue `text` shown beside the player. `hot` lists body segments to color while the cue is on.

The SwiftUI port will read the same JSON and draw with `Canvas`.

## Review page

`node Catalog/tools/build-review.mjs out.html` builds a self-contained page with every exercise.

# Exercise families

Every exercise in the app belongs to one **family**: a group that shares one movement pattern, so it shares form cues, common mistakes and one animation rig. The research is done once per family and kept only as far as the app needs it.

| File | What it holds |
|---|---|
| `<family-id>.json` | One family: what the app shows (how-to, cues, mistakes), what it animates (keyframes, faults, readouts), and the sources |
| `index.json` | List of families with name, kind, body model and member count (built by `tools/build-families.py`) |
| `exercise-map.json` | Every openGym exercise id → family id and its variant tweaks (built by `tools/families.py`) |
| `overrides.json` | Hand fixes for exercises the name rules put in the wrong family |
| `muscles.json` | Muscle groups → Z-Anatomy meshes, and openGym muscle words → groups |
| `props.json` | Equipment props: sizes for modelling, where the body touches them |
| `met.json` | MET values for cardio and conditioning (Compendium of Physical Activities 2024) |
| `references.json` | Every source cited by a family, by key (merged from each file's `sources`) |

## Family file

Keep every text short and in plain words: the app shows it on a phone. Leave a field out when it does not apply. Never copy openGym text or Gym visual media.

```jsonc
{
  "id": "push-up",                       // permanent slug
  "name": "Push-up",
  "kind": "strength",                    // strength | bodyweight | power | cardio | core | mobility | stretch | balance | rehab | skill | sport
  "bodyModel": "anatomy",                // anatomy (muscles shown) | skin (skin and outline only)
  "tracking": "reps",                    // weight_reps | reps | hold | weight_hold | weight_distance | time | distance_time_hr | time_hr
  "pattern": "Horizontal push: the body moves as one plank while the arms bend and straighten.",
  "muscles": { "primary": ["chest", "triceps"], "secondary": ["front-delts", "serratus-anterior", "abs"] },   // ids from muscles.json
  "equipment": ["none"],                 // ids from props.json
  "setup": ["Hands just wider than your shoulders, fingers forward.", "..."],          // 2-4 lines
  "steps": [ { "phase": "Lower", "text": "..." }, { "phase": "Press", "text": "..." } ], // phases match motion.keyframes
  "cues": [ { "joint": "elbows", "cue": "About 45° from your sides.", "why": "...", "refs": ["suprak2013"] } ],  // 3-6, ranked
  "breathing": "In on the way down, out as you push.",
  "tempo": { "down": 2, "pause": 0, "up": 1, "note": "..." },
  "mistakes": [                          // 2-4 most common, each one the app can animate and detect
    {
      "id": "sag",
      "name": "Hips sag",
      "looks": "The lower back arches and the hips drop below the line.",
      "fix": "Squeeze your glutes and brace, body like a plank.",
      "why": "...",
      "pose": { "hipExtension": 15, "lumbarExtension": 15 },   // change from good form, in the joint names below
      "detect": { "metric": "hipLine", "bad": "> 10" },        // readout that flags it (see motion.metrics)
      "refs": ["mcgill2010"]
    }
  ],
  "safety": ["Shoulder pain: keep elbows tucked and shorten the range."],
  "variants": [                          // how common tweaks change the defaults
    { "when": "incline", "change": "Hands on a bench: less load (about 41-55% body weight). Same arm keyframes, body tilted to the bench angle." }
  ],
  "easier": ["incline push-up"], "harder": ["decline push-up"],
  "subtypes": [                          // only when members look different on screen (yoga poses, stretches, kicks...):
    { "id": "kneeling", "name": "Knee push-up", "match": "knee|kneeling",   // regex on the exercise name
      "change": "Knees down, hips straight.", "muscles": { "primary": ["chest"] },   // optional: overrides the family muscles "keyframes": [ /* full set, same format as motion.keyframes */ ] }
  ],
  "met": 3.8,                            // only for cardio/conditioning; Compendium code in metCode
  "metCode": "02022",
  "motion": {
    "loop": "rep",                       // rep (one rep, repeat) | cycle (gait, two steps) | hold (static) | flow (sequence)
    "seconds": 3.0,                      // one loop at the default tempo
    "views": ["side", "front", "angle"], // best camera for the how-to, first is default
    "keyframes": [                       // joint angles, degrees, see the convention below
      { "t": 0.0, "phase": "Top", "trunk": 15, "shoulderFlex": 72, "shoulderAbd": 40, "elbowFlex": 5, "wristExt": 90, "scapula": { "protraction": 0.3, "upRot": 14 } },
      { "t": 0.5, "phase": "Bottom", "trunk": 3, "shoulderFlex": -20, "shoulderAbd": 45, "elbowFlex": 95, "scapula": { "protraction": -0.6, "upRot": 20 } }
    ],
    "contacts": ["hands", "toes"],       // what stays planted: hands | feet | toes | knees | hips | back | bar | bench | ...
    "metrics": [ { "id": "elbowFlex", "label": "Elbow bend", "good": "90-105 at bottom" } ],
    "basis": "Elbow and scapula from suprak2013; trunk and shoulder angles estimated from the body line."  // what is measured vs estimated
  },
  "sources": [                           // every source cited in this file; key = first author + year (+ letter)
    { "key": "suprak2013", "cite": "Suprak DN et al. Shoulder elevation affects joint positioning and muscle activation during the push-up. J Orthop Sports Phys Ther. 2013.", "url": "https://doi.org/..." }
  ],
  "confidence": "high"                   // high (many studies) | medium (some studies + convention) | low (mostly coaching convention)
}
```

## Joint angle convention

Subtypes are tried in order and the first `match` wins, so list the most specific first. A subtype may carry its own `loop` and `seconds`.

Degrees, anatomical, right side unless a key ends in `L`. Zero is standing upright, arms by the sides.

| Key | Positive means |
|---|---|
| `trunk` | Trunk lean forward from vertical (lying face down = 90; lying face up = -90; head-down positions go past ±90, e.g. -135) |
| `roll` | Whole-body roll about its long axis: 90 = lying or leaning on the right side, -90 = on the left side |
| `trunkRot` | Trunk rotation (twist) to the right, relative to the pelvis |
| `trunkSide` | Trunk side bend to the right |
| `neck` | Head and neck flexion (chin down) relative to the trunk |
| `neckSide` | Neck side bend to the right |
| `neckRot` | Head turned to the right |
| `lumbar` | Lower back flexion (rounding); negative = arching |
| `hipFlex` | Hip flexion (thigh forward and up); negative = extension |
| `hipAbd` | Hip abduction (leg out to the side) |
| `hipRot` | Hip external rotation |
| `kneeFlex` | Knee bend |
| `ankleDorsi` | Ankle dorsiflexion (shin forward over the foot); negative = pointing the toes |
| `ankleEv` | Ankle eversion (sole turned out); negative = inversion |
| `toeFlex` | Toe flexion (curling); negative = toes pulled up |
| `shoulderFlex` | Arm raised forward; negative = arm behind the body |
| `shoulderAbd` | Arm raised to the side |
| `shoulderRot` | Shoulder external rotation |
| `elbowFlex` | Elbow bend |
| `forearm` | Pronation (palm down) positive, supination negative, neutral grip = 0 |
| `wristExt` | Wrist extension (back of hand toward the forearm) |
| `scapula` | `protraction` -1 (fully pulled back) .. +1 (fully spread), `elevation` -1..+1, `upRot` upward rotation in degrees |

Unilateral or asymmetric moves add the left side with an `L` suffix (`hipFlexL`). Values are typical for an average adult; give a range in `metrics.good` where the research gives one.

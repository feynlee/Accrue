# Catalog sources and licenses

Every exercise in `Catalog/exercises/` is Accrue's own work: the cue text is written for Accrue and every animation is drawn by `Catalog/rig.js` from keyframe data in the exercise file. No third-party image, video or animation is copied, traced or used as a reference for the drawings.

## What we checked and how we use it

| Source | License | How Accrue uses it |
|---|---|---|
| [openGym](https://github.com/DuarteSantos8/openGym) exercise text, entries marked `textSource: "exercisedb"` | MIT (via ExerciseDB v1 and hasaneyldrm/exercises-dataset) | Exercise names, ids and muscle groups as a cross-reference. Each Accrue exercise stores `openGymId` so we can match openGym's catalogue later. |
| openGym exercise text, all other entries | AGPL-3.0 | Not copied. Accrue is a separate, closed app, so AGPL text would oblige us to publish Accrue's source. We only link by `openGymId`. |
| openGym stills and clips (`catalogue/media/`) | Licensed from Gym visual, no reuse in other apps, no AI use | Not used, not viewed, not referenced. A commercial license is available from gymvisual.com if ever wanted. |
| [free-exercise-db](https://github.com/yuhonas/free-exercise-db) | Unlicense (public domain) for the JSON; the photos' original source is not documented | JSON names and categories may be used as a cross-check. Photos not used, because their provenance is unclear and their style does not match. |
| [wger](https://github.com/wger-project/wger) exercise data | Code AGPL-3.0; exercise data and images Creative Commons, license per entry (mostly CC-BY-SA) | Not copied. Share-alike would apply to our text and art. |
| Coaching literature (see `references.json`) | Facts and methods are not copyrightable; text is not copied | Cues are written in our own words from these sources. Each exercise lists its `refs`. |

## Why we draw instead of combining open images

The open image sets come in different styles (photos, line drawings, 3D renders), and none show joint cues such as shoulder-blade depression or upper-arm rotation. Mixing them would look inconsistent and still miss the cues. One parametric figure keeps the style uniform, lets every animation highlight the joint it is talking about, follows the app theme in light and dark, and is a few kilobytes per exercise.

## Medical note

The cues are general coaching guidance for healthy adults, not medical advice. Each exercise file has a `safety` field for the main precaution.

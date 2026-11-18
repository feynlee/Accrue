# Accrue

A personal workout logger for iOS, built with SwiftUI (iOS 18, Swift 6). Exercise names and
ids come from [openGym](https://github.com/DuarteSantos8/openGym); how-to text, cues and mistakes
are Accrue's own research in `Catalog/families`. No openGym instruction text and no Gym visual
media is used. Credits and licences are listed under [Credits and licences](#credits-and-licences).

## Layout

| Folder | What it holds |
|---|---|
| `Accrue/` | The SwiftUI app: theme, Train, Plans, Progress, You, Coach sheet |
| `AccrueKit/` | Swift package with everything that is not a screen: catalog, plans and log model, logging rules, store. Foundation only, tested on Linux too |
| `Catalog/` | Exercise research: 104 movement families, the exercise map, muscles, props, sources |
| `Body/` | 3D body and anatomy pipeline (Z-Anatomy, MakeHuman) and the push-up and stairs demos |
| `Config/` | Extra Info.plist keys (fonts) merged into the generated one |
| `Licenses/` | Licences and credits for the fonts, the 3D body model and the exercise names |

## Run

Open `Accrue.xcodeproj` in Xcode 16 or later, pick an iPhone simulator, and press Run.
To run on a phone, set your team under Signing & Capabilities once.

Launch arguments for testing: `-demoData YES` uses five weeks of made-up history in memory
(nothing is saved), `-startTab plans|progress|you` opens another tab, `-appearance light` picks
the light theme.

## Test

```sh
swift test --package-path AccrueKit
```

After changing anything in `Catalog/families`, rebuild the app's catalog:

```sh
python3 Catalog/tools/build-app-catalog.py
```

CI (`.github/workflows/ci.yml`) runs the package tests on Linux and checks the catalog is
current. When app files change it also builds the app for the iOS Simulator on macOS and takes
a few screenshots. Mac minutes are costly, so the screenshots are chosen by a tag in the last
commit message of a push:

| Tag | Screenshots |
|---|---|
| none | The core set: Train (dark and light), the weight-steps sheet, Plans, Progress, You |
| `[shots all]` | Every screen, and the Watch app |
| `[shots none]` | None, build only |
| `[shots train:dark:steps you:dark:siri]` | Only the ones listed, as `tab:look:extra` (see the workflow for the names) |
| `[skip mac]` | Skips the Mac job |

"Run workflow" on the Actions page takes the same choice as an input.

## Credits and licences

- **3D body.** Adapted from [Z-Anatomy](https://www.z-anatomy.com/) (CC BY-SA 4.0), which is based
  on BodyParts3D, © The Database Center for Life Science (CC BY-SA 2.1 Japan). Head, hands, feet
  and the base rig come from MakeHuman (CC0). The adapted model files are shared under
  CC BY-SA 4.0: see `Licenses/Z-Anatomy-CC-BY-SA.md`.
- **Exercise names.** From openGym; part of them from ExerciseDB v1 under the MIT licence:
  see `Licenses/ExerciseDB-MIT.txt` and `Catalog/SOURCES.md`.
- **Fonts.** Barlow Condensed and Inter, SIL Open Font License: see `Licenses/`.
- **Accrue's own code, text and artwork.** No licence has been chosen yet, so all rights are
  reserved: you may read the source, but not reuse or redistribute it.

# Accrue

A personal workout logger for iOS, built with SwiftUI (iOS 18, Swift 6). Exercise names come
from [openGym](https://github.com/DuarteSantos8/openGym) (MIT); how-to text, cues and mistakes
are Accrue's own research in `Catalog/families`. No Gym visual media is used.

## Layout

| Folder | What it holds |
|---|---|
| `Accrue/` | The SwiftUI app: theme, Train, Plans, Progress, You, Coach sheet |
| `AccrueKit/` | Swift package with everything that is not a screen: catalog, plans and log model, logging rules, store. Foundation only, tested on Linux too |
| `Catalog/` | Exercise research: 104 movement families, the exercise map, muscles, props, sources |
| `Body/` | 3D body and anatomy pipeline (Z-Anatomy, MakeHuman) and the push-up and stairs demos |
| `Config/` | Extra Info.plist keys (fonts) merged into the generated one |
| `Licenses/` | Font licences (SIL OFL) |

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

CI (`.github/workflows/ci.yml`) runs the package tests on Linux, checks the catalog is current,
builds the app for the iOS Simulator on macOS, and takes screenshots of each tab.

# AccrueKit

Everything in Accrue that is not a screen: the exercise catalog, the workout data model,
the weekly routine, the logging rules and the on-device store. It uses Foundation only,
so it builds and its tests run on Linux as well as on Apple platforms.

```sh
swift build
swift test
```

`Resources/catalog.json` is generated. Do not edit it; change `Catalog/families` and run
`python3 Catalog/tools/build-app-catalog.py` from the repository root.

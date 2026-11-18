# 3D body model: credit and license

The 3D body in Accrue (`Accrue/Body/Body.usdz`, `Body/out/press.glb` and the files that
`Body/anatomy` and `Body/pipeline` produce) is adapted from these works.

| Part | Source | License |
|---|---|---|
| Muscles, bones and the skin surface used in cardio demos | [Z-Anatomy](https://www.z-anatomy.com/), "Models of human anatomy" (github.com/Z-Anatomy/Models-of-human-anatomy) | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) |
| The meshes Z-Anatomy builds on | BodyParts3D, © The Database Center for Life Science (DBCLS) | [CC BY-SA 2.1 Japan](https://creativecommons.org/licenses/by-sa/2.1/jp/) |
| Base body mesh, rig and skin weights; skin of the head, hands and feet | MakeHuman, through [MPFB2](https://github.com/makehumancommunity/mpfb2) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |

## What we changed

The Z-Anatomy meshes were selected, simplified, welded into closed surfaces, re-rigged to one
skeleton, given skin weights, vertex colours and a fibre texture, posed, and packed for the app.
The scripts that do this are in `Body/anatomy` and `Body/pipeline`.

## License of the adapted model

The adapted model files named above are licensed under
[Creative Commons Attribution-ShareAlike 4.0 International](https://creativecommons.org/licenses/by-sa/4.0/).
You may share and adapt them if you give credit to Z-Anatomy, BodyParts3D (DBCLS) and Accrue,
say what you changed, and release your version under the same license.

This license covers the model files only. It does not cover Accrue's source code, text or
other artwork.

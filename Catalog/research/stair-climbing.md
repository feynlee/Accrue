# Stair climbing: scientific record

This is the research behind the stair-climbing guide and its skin-only 3D animation (Body/anatomy/climb_za.py, climb-app.html). It covers going up a normal flight of stairs one step at a time, as cardio. It touches on two steps at a time and on going down, because users will ask about both.

Stair climbing is not in the OpenGym catalogue. It is an Accrue entry. The HealthKit type is `HKWorkoutActivityType.stairs`; `stairClimbing` is the machine. The floor count comes from `flightsClimbed`.

**How to read this file**

- `[R#]` points to the numbered reference list at the end.
- **[Evidence]**: measured in a peer-reviewed study or a systematic review.
- **[Convention]**: physiotherapy or coaching advice, or a building standard. Not tested directly.
- **[Estimate]**: our own value, set in the animation from the model's proportions and the measured values around it. Do not quote these as findings.

Research date: 2026-10-23.

---

## 1. The stairs

| Parameter | Value | Type | Source |
|---|---|---|---|
| Riser (step height) | Commercial buildings: at most 178 mm (7 in). Homes are often steeper. | Convention | IBC 2021 §1011.5.2 [R20] |
| Tread (step depth) | Commercial buildings: at least 279 mm (11 in) | Convention | [R20] |
| Steps in the animation | 175 mm rise, 280 mm going | Estimate | Chosen inside the code limits |
| Steps per floor (app count) | 16 | Estimate | One floor of about 2.8 m at 175 mm a step. On iPhone, use HealthKit `flightsClimbed` from the barometer instead. |

Steeper stairs (a bigger rise) need more knee and hip flexion and more knee moment [Evidence, R4].

## 2. Movement: one stride (two steps up)

Stair ascent is a gait cycle: from one foot landing on a step to the same foot landing two steps higher. The stance phase is about the first 60% and the swing phase the rest. Physiopedia [R3] gives the phases, from McFadyen and Winter 1988:

- Weight acceptance.
- Pull-up: about 0–32% of stance. The knee and hip extend and lift the body onto the step.
- Forward continuance: 32–64% of stance.
- Foot clearance and foot placement in swing.

### 2.1 Joint angles

| Joint | Event | Value | Type | Source |
|---|---|---|---|---|
| Hip | Foot contact | 50–60° flexion | Evidence | [R3]; [R1] |
| Hip | End of stance | 5–10° flexion | Evidence | [R3] |
| Hip | Swing peak | 40–60° flexion | Evidence | [R3] |
| Knee | Foot contact | 60–80° flexion, extending to about 35° by the end of weight acceptance | Evidence | [R3]; [R1] |
| Knee | End of pull-up | 5–10° flexion (almost straight) | Evidence | [R3] |
| Knee | Swing peak | 90–100° flexion | Evidence | [R3] |
| Ankle | Contact | 20–25° dorsiflexion | Evidence | [R3] |
| Ankle | Push-off | About 15° plantarflexion | Evidence | [R3] |
| Hip/knee range, single support | One step at a time: hip 30°, knee 41° (mean). Two at a time: hip 51°, knee 52° | Evidence | [R2] |
| Knee extensor moment | About 3 times level walking | Evidence | [R3] |
| Patellofemoral contact | At 30° knee flexion, contact pressure is higher than in walking | Evidence | [R10] |

### 2.2 Trunk

| Parameter | Value | Type | Source |
|---|---|---|---|
| Forward trunk lean | A small forward lean is normal. Leaning more lowers the knee extensor moment and raises the hip extensor moment. | Evidence | [R8]; [R9] |
| Lean and the thigh turning in | Asymptomatic women who leaned more and used the hip extensors more had less peak hip adduction and internal rotation | Evidence | [R7] |
| Value used | About 10° at the chest, 6° at the pelvis, plus 2° at each push. The readout (pelvis to base of neck) reads 4–8°. | Estimate | — |

### 2.3 What the animation does

| Item | Value | Type |
|---|---|---|
| Cadence | 90 steps/min (1.33 s a stride). Kennedy 2007 used 75 steps/min [R14]. | Estimate |
| Foot placement | Whole foot on the tread. The shoe tip is 1.5 cm short of the next riser and the heel is on the tread. | Convention [R21] |
| Knee at contact | 73° flexion | Estimate, in the 60–80° range [R3] |
| Knee at the end of pull-up | 7–11° flexion | Estimate, matches [R3] |
| Knee swing peak | 84° | Estimate, a little under the 90–100° in [R3] |
| Push-off | The heel rises to 38° at toe-off, rolling over the ball of the foot | Estimate |
| Toe clearance over the next nosing | At least 3.3 cm during swing | Estimate |
| Pelvis | Rises most of a step in the first 80% of each single support. Sways 2.2 cm toward the stance leg and turns 4°. | Estimate |
| Arms | Swing ±13° opposite the legs. Elbows bent 22°. Forearms turned so the palms face the thighs. | Estimate |
| Eyes | Head pitched about 12° down, looking a few steps ahead | Convention |

## 3. Cues (what the app says)

1. **Stand tall, lean a little from the hips.** Look two or three steps ahead. [Evidence for the lean, R7, R8; Convention for the gaze]
2. **Whole foot on the step.** Heel down, toes near the next riser. [Convention, R21]
3. **Push up through the front leg.** Through the middle of the foot and the heel; don't spring off the back toes. [Convention]
4. **Knee over the second toe.** [Evidence that knee valgus raises patellofemoral stress, R5, R6]
5. **Steady pace, rhythmic breathing.** 80–100 steps/min for steady work. In for two steps, out for two. [Convention]
6. **Use the handrail lightly** for balance. Older adults use the rails more and slow down on short treads [R3]. [Convention]

## 4. Common mistakes (animated)

| Mistake | What changes in the animation | Why it matters | Type |
|---|---|---|---|
| Knee caves in | The knee pole is turned 22° toward the midline while the foot is on the step. Readout: knee 4–7 cm inside the hip-ankle line (limit 2.5 cm). | Hip adduction and internal rotation load the patellofemoral joint unevenly. People with patellofemoral pain have higher joint stress on stairs [R5]. Theory: [R6]. More forward lean reduced it [R7]. | Evidence |
| Only toes on the step | The ball of the foot sits on the nosing and the heel hangs 14–30° up through stance. | The base is smaller, the calf does the lifting, and the foot can slip off the edge. | Convention [R21] |
| Head down, hunched | Trunk lean 24°, neck 22°, head 12° down. Readout: eyes 34° down. | A small lean helps, but folding and looking at the feet hides the stairs ahead. | Convention |

## 5. Effort and benefits

| Item | Value | Type | Source |
|---|---|---|---|
| MET, slow | 4.5 | Evidence (compendium) | [R11] |
| MET, general | 6.8 | Evidence (compendium) | [R11] |
| MET, fast, one step at a time | 9.3 | Evidence (compendium) | [R11] |
| MET, two steps at a time | 7.5 | Evidence (compendium) | [R11] |
| VO₂ while ascending | About 33 ml/kg/min (up and down together: 19.2) | Evidence (review) | Takaishi 2014 via [R12] |
| Training effect, sedentary women, 8 weeks of short bouts | VO₂max +17%, LDL −7.7% | Evidence | Boreham 2005 [R13] |
| Office workers, 8 weeks | Predicted VO₂max +9.4% | Evidence | Kennedy 2007 [R14] |
| Exercise snacks: 3 × 60 steps a day, 3 days/week, 6 weeks | Peak VO₂ higher than controls | Evidence | Jenkins 2019 [R15] |
| Exercise snacks (2024 RCT) | VO₂peak +7% | Evidence | Yin 2024 [R18] |
| Home stairs, sedentary women, 8 weeks | Aerobic fitness up, fasting glucose down | Evidence | Michael 2021 [R16] |
| Observational meta-analysis (2026) | Regular stair climbers: 39% lower cardiovascular death, 24% lower all-cause death (association, not cause) | Evidence (observational) | [R17] |

Calories in the app: kcal = MET × body mass (kg) × hours. Until the profile has a weight, it uses 70 kg.

## 6. Going down, and variants

- **Going down** is mostly eccentric and loads the patellofemoral joint more than going up (Physiopedia [R3]; [R5]). It needs its own animation and cues: slower, handrail, whole foot.
- **Two steps at a time** needs more hip and knee flexion in single support: hip 51° against 30°, knee 52° against 41° [R2]. It works the hip extensors more. MET 7.5 [R11]. It needs a separate clip.
- **Stair machine (stepmill)** is a separate HealthKit type (`stairClimbing`). The cues are the same, but the stairs move.

## 7. Visual approach (no muscles)

- The body is Z-Anatomy's own skin surface ("Regions of human body", 252 named patches), welded into one mesh. It is the same model as the push-up, so proportions and joints match.
- Each region may only follow the bones of its own body part. For example, the thigh does not follow the fingers hanging beside it.
- Weights are inverse distance to the bones (power 6, top 3 bones), then smoothed over the surface.
- Modesty: the genital region is relaxed onto the membrane spanned by its border and covered by shorts.
- Clothes are vertex colours: a lime top, dark shorts and shoes. Toes are smoothed into one toe box.
- There are two looks: **Skin** (shaded) and **Outline** (a flat white fill with an ink contour from an inflated back-face copy).

## References

- [R1] Protopapadaki A, Drechsler WI, Cramp MC, Coutts FJ, Scott OM. Hip, knee, ankle kinematics and kinetics during stair ascent and descent in healthy young individuals. *Clin Biomech*. 2007;22:203–210. https://doi.org/10.1016/j.clinbiomech.2006.09.010
- [R2] Biomechanical analysis of stair walking patterns and their implications for knee health in young males. PMC12822404. https://pmc.ncbi.nlm.nih.gov/articles/PMC12822404/
- [R3] Physiopedia. Stair Gait (sagittal plane analysis after McFadyen and Winter 1988). https://www.physio-pedia.com/Stair_Gait
- [R4] Riener R, Rabuffetti M, Frigo C. Stair ascent and descent at different inclinations. *Gait Posture*. 2002;15:32–44. https://pubmed.ncbi.nlm.nih.gov/11809579/
- [R5] Brechter JH, Powers CM. Patellofemoral joint stress during stair ascent and descent in persons with and without patellofemoral pain. *Gait Posture*. 2002;16(2):115–123.
- [R6] Powers CM. The influence of altered lower-extremity kinematics on patellofemoral joint dysfunction: a theoretical perspective. *J Orthop Sports Phys Ther*. 2003;33(11):639–646.
- [R7] The effects of increased forward trunk lean during stair ascent on hip adduction and internal rotation in asymptomatic females. *Gait Posture*. 2022. https://pubmed.ncbi.nlm.nih.gov/35961131/
- [R8] Influence of trunk flexion on hip and knee kinetics and energetics during stair ascent. ISB 2013 poster PS1-01. https://media.isbweb.org/images/conferences/isb-congresses/2013/poster/ps1-01s.pdf
- [R9] Hip-extensor strength, trunk posture, and use of the knee-extensor muscles. PMC5317187. https://pmc.ncbi.nlm.nih.gov/articles/PMC5317187/
- [R10] Stair climbing results in more challenging patellofemoral contact mechanics and kinematics than walking at early knee flexion. 2009. https://pubmed.ncbi.nlm.nih.gov/19656517/
- [R11] Compendium of Physical Activities (2024), Walking: codes 17131, 17133, 17134, 17136. https://pacompendium.com/walking/
- [R12] Stair-climbing interventions on cardio-metabolic outcomes in adults: a scoping review. PMC10656261. https://pmc.ncbi.nlm.nih.gov/articles/PMC10656261/
- [R13] Boreham CAG, Kennedy RA, Murphy MH, Tully M, Wallace WFM, Young I. Training effects of short bouts of stair climbing on cardiorespiratory fitness, blood lipids, and homocysteine in sedentary young women. *Br J Sports Med*. 2005. https://www.researchgate.net/publication/7643043
- [R14] Kennedy RA et al. Effects of accumulated bouts of stair walking in sedentary office workers. 2007 (reported in [R12]).
- [R15] Jenkins EM et al. Do stair climbing exercise "snacks" improve cardiorespiratory fitness? *Appl Physiol Nutr Metab*. 2019 (reported in [R12]).
- [R16] Michael E, White MJ, Eves FF. Home-based stair climbing as an intervention for disease risk in adult females; a controlled study. *Int J Environ Res Public Health*. 2021;18(2):603. https://www.mdpi.com/1660-4601/18/2/603
- [R17] Harvard Health Publishing. Stair climbing may significantly lower cardiovascular risks (on a 2026 meta-analysis in *Am J Cardiovasc Drugs*, doi 10.1007/s40256-026-00811-x). https://www.health.harvard.edu/exercise-and-fitness/stair-climbing-may-significantly-lower-cardiovascular-risks
- [R18] Yin M, Deng S, Chen Z, et al. Exercise snacks are a time-efficient alternative to moderate-intensity continuous training for improving cardiorespiratory fitness but not maximal fat oxidation in inactive adults: a randomized controlled trial. *Appl Physiol Nutr Metab*. 2024. https://doi.org/10.1139/apnm-2023-0593
- [R19] Takaishi T. Stair-ascending exercise, narrative review. 2014 (reported in [R12]).
- [R20] International Code Council. International Building Code 2021, §1011.5.2 Riser height and tread depth.
- [R21] Physiotherapy advice on foot placement and knee alignment on stairs, for example https://www.butheauphysio.com/blog/how-to-climb-stairs-correctly-to-prevent-knee-pain/ (Convention).

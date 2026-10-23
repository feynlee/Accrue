"""Assign every openGym exercise to a movement family.

A family is a group of exercises that share one movement pattern, so they
share form cues, common mistakes and one animation rig. The rules are tried
in order and the first match wins: specific patterns come before general ones.

Usage: python Catalog/tools/families.py <openGym catalogue/exercises dir> <out dir>
Writes <out>/exercise-map.json and prints coverage per family.
"""
import collections
import glob
import json
import os
import re
import sys

# (family id, regex on the lower-case name, optional category filter)
RULES = [
    # --- foam rolling and massage before stretches
    ("foam-roll", r"^(?!.*(ab roller|wheel roller|wrist roller|roller (crunch|reverse crunch|body saw)))(.*(\broll(er|ing)? (massage|release)|foam roll|\broller\b|massage|lacrosse ball|roll ?ball|trigger point|myofascial)|^roll )", None),
    # --- cardio machines and locomotion
    ("treadmill-run", r"treadmill", None),
    ("stair-climb", r"stepmill|stair ?(climb|master)|stairs|lever stepper|stepper\b", None),
    ("row-erg", r"rowing machine|row(ing)? ergometer|\bergometer row|rowing \(with", None),
    ("ski-erg", r"ski ?erg", None),
    ("elliptical", r"elliptical|cross trainer", None),
    ("stationary-bike", r"(stationary|spin|recumbent|air|assault|recline) ?bike|bicycle recline|aquabike|cycling|hands bike|arm ergometer|upper body ergometer", None),
    ("swim", r"\bswim|freestyle stroke|breaststroke|backstroke|butterfly stroke|front crawl", None),
    ("jump-rope", r"jump(ing)? rope|skipping rope|double under|rope skip", None),
    ("battle-ropes", r"battl\w* rope|battle rope|wave machine", None),
    ("sled-push-pull", r"\bsled\b|prowler", None),
    ("loaded-carry", r"farmer|suitcase carry|carry\b|yoke walk|waiter walk|backpack walk|sandbag (walk|carry)|keg carry|strongman walk", None),
    ("agility-drill", r"drill|\bcones?\b|shuffle|ladder|zig ?zag|agility|\bcut\b|backpedal", None),
    ("run", r"\brun\b|running|sprint|jog|\bdash\b|shuttle|prancing|trot", None),
    ("walk", r"^(briskly )?walk(ing)?( \(.*\))?$|hydrotherapy walk|walk(ing)? on (the )?spot|heel to toe walk|power walk|nordic walk|race walk", None),
    # --- combat
    ("kick", r"kick", "combat"),
    ("punch", r"\bjab\b|cross\b.*box|boxing|punch|uppercut|\bhook\b(?!.*kick)|speed bag|heavy bag|shadow box", None),
    ("kick", r"\bkick(boxing)?\b.*(front|snap|round|side|axe|spin|hook|groin|knee|push|back)|roundhouse|axe kick|side kick|knee kick|muay|front kick", "combat|cardio|plyometrics|calisthenics"),
    # --- olympic and kettlebell ballistic
    ("turkish-get-up", r"get[- ]?up", None),
    ("kettlebell-swing", r"^(?!.*(rear delt|bicep|arms? swing|pull up)).*\bswing\b", None),
    ("snatch", r"snatch", None),
    ("clean", r"\bclean\b", None),
    ("jerk-push-press", r"\bjerk\b|push press|thruster", None),
    ("high-pull", r"high pull\b|clean pull|snatch pull", None),
    ("strongman-event", r"strongman|tire flip|atlas stone|\bkeg\b|car flip|truck pull|sandbag (shoulder|load)|log lift|\byoke\b|weight for height|stone", None),
    # --- plyometrics and conditioning
    ("burpee", r"burpee|sprawl", None),
    ("jumping-jack", r"\bjacks?\b|star jump|seal jump", None),
    ("mountain-climber", r"mountain climber|spider ?climb|cross[- ]body climber", None),
    ("high-knees-butt-kicks", r"high knee|butt kick|a skip|b skip|skip\b|skipping|quick feet|fast feet|carioca|grapevine", None),
    ("box-jump", r"box jump|depth jump|drop jump|jump (on|onto|up)|step jump|bench jump", None),
    ("broad-jump-bound", r"broad jump|long jump|bound(ing|s)?\b|frog (jump|hop)|leap", None),
    ("lateral-hop-skater", r"skater|lateral (hop|jump|bound)|side (hop|jump)|\bhops?\b|hopping|hurdle|line jump", None),
    ("jump-squat-tuck", r"jump(ing)? squat|squat jump|tuck jump|pike jump|split jump|jump(ing)? lunge|lunge jump|scissor jump|vertical jump|\bjump\b|pogo|plyo", None),
    ("med-ball-throw", r"(ball|medicine ball|med ball|sandbag|plate).*(slam|throw|toss|pass|chest pass|scoop)|wall ball|slam", None),
    # --- yoga, pilates and rehab before stretches
    ("yoga-pose", r"\bpose\b|asana|sun salutation|downward facing|upward facing|warrior|\bcobra\b|\bsphinx\b|child'?s pose|lotus|\bplow\b|crow\b|tree pose", None),
    ("yoga-pose", r".", "yoga"),
    ("pilates-reformer", r"pilates machine|reformer|cadillac|wunda", None),
    ("pilates-mat", r".", "pilates"),
    ("breathing-pelvic-floor", r"breath|kegel|pelvic floor|diaphragm", None),
    ("shoulder-rotation", r"^(?!.*\bhip).*((external|internal) (shoulder )?rotation|shoulder (external|internal)|rotator)", None),
    ("ankle-foot", r"ankle|dorsi ?flex|plantar ?flex|inversion|eversion|foot (crunch|curl|roll|eversion|inversion)|toe (curl|spread|yoga|grab)|towel (scrunch|foot)|\barch\b|short foot|marble", "rehab|mobility|stretching|calisthenics|strength|isometric"),
    ("balance", r"balance (board|pad|beam)|single leg (stand|balance)|one leg stand|bosu balance|wobble|\bbalance\b", "rehab|mobility|calisthenics|isometric|yoga"),
    ("neck", r"^(?!.*behind (the )?neck)(.*(\bneck\b|chin tuck|cervical|head (harness|lift)|sternocleido))", None),
    # --- stretches by region (category stretching or name says stretch)
    ("stretch-wrist-forearm", r"wrist|forearm|finger|hand\b|hands\b|grip", "stretching|mobility|yoga|rehab"),
    ("stretch-hamstring", r"hamstring|toe touch|forward (fold|bend)|straddle|pike stretch|seated reach|sit and reach", "stretching|mobility|yoga"),
    ("stretch-quad-hip-flexor", r"quad|hip flexor|psoas|kneeling lunge|couch stretch|iliopsoas|rectus femoris|lunge stretch", "stretching|mobility|yoga"),
    ("stretch-glute-hip", r"glute|piriformis|figure (4|four)|pigeon|hip (opener|rotation|circle|car)|90.?90|external hip|hip internal|butterfly|groin|(hip |thigh |leg |\b)adductor(?! protractor)|inner thigh|frog|cossack|it band|\btensor|hip abductor|\bhip\b", "stretching|mobility|yoga"),
    ("stretch-calf", r"calf|achilles|soleus|gastrocnem|shin|tibialis", "stretching|mobility|yoga"),
    ("stretch-chest-shoulder", r"chest|pec|shoulder|deltoid|doorway|arm circle|cross[- ]body|lat\b|lats\b|triceps|tricep|bicep|overhead reach|scapula|dislocate|pass through|wall slide|thread the needle|arm\b|arms\b", "stretching|mobility|yoga"),
    ("stretch-spine", r"spin(e|al)|back|cat|cow|twist|rotation|thoracic|t-?spine|lumbar|side bend|lateral flexion|torso|trunk|oblique|abdominal|abs\b|cobra|extension|flexion|bend|roll down|roll up", "stretching|mobility|yoga"),
    ("mobility-flow", r"inchworm|around the world|halo|world.?s greatest", None),
    ("mobility-flow", r".", "mobility"),
    ("stretch-general", r".", "stretching"),
    # --- core
    ("lever-hold", r"^(?!.*(push|dip|press)).*(front lever|back lever|\bflag\b|maltese|planche|l[- ]?sit|v[- ]?sit hold|dragon flag|iron cross|crucifix|elevator)", None),
    ("ab-wheel-rollout", r"roll ?out|ab wheel|wheel roll|barbell roll|stability ball (roll|pike|jackknife)|body saw|stir the pot", None),
    ("pallof-anti-rotation", r"pallof|anti[- ]rotation", None),
    ("woodchop-rotation", r"wood ?chop|\bchop\b|wipers?\b|windshield|lift\b.*diagonal|russian twist|\btwist\b|rotation|rotational|windshield|landmine (rotation|twist|180|rainbow)|oblique twist|torso rotation", None),
    ("side-plank", r"side plank|side bridge|copenhagen", None),
    ("plank", r"plank|bear (crawl|hold|plank)|hollow|l-?sit|v-?sit hold|\bhold\b.*(push|top)|body ?saw|shoulder tap|crab", None),
    ("dead-bug-bird-dog", r"dead ?bug|bird ?dog|quadruped|superman|swimmer|abdominal draw|vacuum|hollow body", None),
    ("hanging-leg-raise", r"(hanging|captain|vertical|roman chair|dip station|parallel bar).*(leg|knee) raise|(leg|knee) raise.*(hanging|captain|bar)|toes to bar|knees to (chest|elbow)|windshield", None),
    ("lying-leg-raise", r"leg (raise|lift|lower)|knee (raise|tuck|up)|reverse crunch|flutter kick|scissor|leg pull[- ]in|tuck crunch|v[- ]?up|jack ?knife|jackknife|toe touch|seated in and out|lying leg|leg circle", None),
    ("side-bend", r"side bend|lateral flexion|oblique crunch|side crunch|hip dip|heel touch|alternate heel|windmill", None),
    ("crunch-sit-up", r"crunch|sit[- ]?up|curl[- ]up|ab (curl|crunch)|bicycle|chest lift|roll up|janda", None),
    # --- lower body
    ("hip-flexion", r"^(?!.*stretch)(.*(hip flexion|knee drive|psoas march))", None),
    ("muscle-setting", r"static .*contraction|glute squeeze|isometric mid thigh|quad set", None),
    ("hip-thrust-bridge", r"hip thrust|glute bridge|bridge|pelvic (lift|tilt)|hip lift|frog pump|hip raise", None),
    ("nordic-curl", r"nordic|glute[- ]ham|ghr|razor curl|natural ham", None),
    ("leg-curl", r"leg curl|hamstring curl|knee flexion|ball curl|slider curl|ham curl|lying curl", None),
    ("leg-extension", r"leg extension|knee extension|sissy|reverse nordic|terminal knee|spanish squat", None),
    ("calf-raise", r"calf|calves|heel raise|toe raise|tiptoe|donkey calf|tibialis|tib raise|heel walk|toe walk", None),
    ("hip-abduction", r"abduct|clam|fire hydrant|lateral leg raise|side leg (raise|lift)|side[- ]lying (leg|hip)|band walk|monster walk|lateral walk|side step|hip hike", None),
    ("hip-adduction", r"^(?!.*scapula).*(adduct|inner thigh|copenhagen|ball squeeze)", None),
    ("triceps-extension", r"(tricep|triceps|arm|dumbbell seated|dumbbell standing).* kick ?back|kick ?back.*(tricep|arm)", None),
    ("glute-kickback", r"kick ?back|donkey kick|hip extension|glute (kick|press)|reverse hyper|reverse hyperextension|bird dog kick|quadruped hip", None),
    ("back-extension", r"hyperextension|back extension|good morning|roman chair|superman|lower back|reverse hyper|spinal extension", None),
    ("leg-press", r"leg press|hack squat|sled press|sled 45|sled (closer|side)|pendulum|v-?squat|belt squat|pit shark", None),
    ("step-up", r"step[- ]?up|step over|stepbox|box step", None),
    ("single-leg-squat", r"pistol|single leg squat|one leg squat|skater squat|shrimp|single leg sit|single leg box|single leg chair", None),
    ("lunge-split-squat", r"lunge|split squat|bulgarian|curtse?y|rear foot elevated|lunges|curtsy|crossover step|walking lunge|lateral squat|side squat|cossack", None),
    ("single-leg-rdl", r"single leg (deadlift|rdl|romanian|stiff)|one leg (deadlift|rdl|romanian|stiff)|single leg hinge|kickstand|b-?stance|airplane", None),
    ("deadlift", r"deadlift|rack pull|block pull|jefferson|stiff leg|stiff-leg|romanian|\brdl\b|pull[- ]through|hinge", None),
    ("squat", r"squat|wall sit|sit to stand|chair stand|box sit", None),
    # --- upper push
    ("dip", r"^(?!.*pull ?up)(.*\bdips?\b)", None),
    ("push-up", r"push[- ]?up|press[- ]?up|planche|pseudo|hindu|dive bomb", None),
    ("rear-delt-fly", r"rear (delt|deltoid)|reverse (fly|flye|pec deck)|bent[- ]over (lateral|raise)|rear lateral|posterior delt|band pull[- ]apart|pull[- ]apart|prone (y|t)", None),
    ("chest-fly", r"\bfly(e|es)?\b|flye|crossover|pec deck|butterfly|squeeze press|svend|plate press|chest squeeze", None),
    ("triceps-extension", r"tricep|skull ?crusher|lying extension|french press|jm press|overhead extension|pushdown|push[- ]down|kick ?back|tate press|elbow extension|close[- ]grip (bench|press)|bench dip", None),
    ("pullover", r"pull ?over|straight[- ]arm (pulldown|pull[- ]down|lat)|lat prayer", None),
    ("bench-press", r"(bench|floor|chest|incline|decline|smith|board|pin|spoto|larsen|guillotine|neck|svend|hex) press|bench press|chest press|press.*(bench|incline|decline)|floor press|landmine press|incline press|decline press", None),
    ("overhead-press", r"shoulder press|overhead press|military|arnold|push press|press (overhead|behind)|z press|seated press|standing press|landmine (shoulder|overhead)|bradford|pike press|handstand|viking|log press|axle press|kettlebell press|bottoms[- ]up press|\bpress\b", None),
    ("front-raise", r"front raise|front and lateral|front delt|plate raise|forward raise|front (plate|cable|dumbbell)|scaption|full can", None),
    ("lateral-raise", r"lateral raise|side raise|lat raise|\by raise|lu raise|lean[- ]away|lateral (deltoid|delt)|side delt|\braise\b.*(side|lateral)|(side|lateral).*\braise\b|cuban|w raise", None),
    ("upright-row", r"upright row|high row.*upright", None),
    ("shrug", r"shrug|scapula(r)? (elevation|depression|retraction|protraction|push|pull|shrug)|scap (push|pull)|trap raise", None),
    # --- upper pull
    ("pull-up", r"pull[- ]?up|chin[- ]?up|muscle[- ]?up|ring (pull|row)|towel pull|commando|archer pull|l-?pull|scapula pull|dead hang|\bhang\b|monkey bar", None),
    ("lat-pulldown", r"pull[- ]?down|pulldown", None),
    ("face-pull", r"face pull|external rotation row|cable rope rear", None),
    ("row", r"\brows?\b|rowing|seal row|pendlay|meadows|kroc|t[- ]bar|chest[- ]supported|inverted row|australian|renegade|gorilla|yates|helms", None),
    # --- arms
    ("wrist-forearm", r"wrist|forearm|\bgrip(per)?s?\b(?! (curl|press|row|pull|bench|shrug|deadlift|pulldown|chin|lat|upright|squat|extension|front|push|snatch))|finger|pinch|rice bucket|hand squeeze|torsion|pronation|supination|handboard|crimp|thumb|wrist roll|fingal|axle", None),
    ("biceps-curl", r"curl|chin[- ]up hold|bicep|biceps|zottman|spider curl|drag curl|hammer", None),
]

# Second pass for names the rules above miss: fall back on openGym's target muscle.
TARGET_FALLBACK = {
    "abs": "crunch-sit-up", "glutes": "hip-thrust-bridge", "quads": "squat", "delts": "overhead-press",
    "pectorals": "bench-press", "lats": "lat-pulldown", "biceps": "biceps-curl", "triceps": "triceps-extension",
    "calves": "calf-raise", "upper back": "row", "hamstrings": "leg-curl", "cardiovascular system": "run",
    "spine": "back-extension", "forearms": "wrist-forearm", "abductors": "hip-abduction", "adductors": "hip-adduction",
    "levator scapulae": "neck", "traps": "shrug", "serratus anterior": "push-up",
}


def assign(r):
    name = r["name"].lower()
    cat = r.get("category") or ""
    for fid, rx, cats in RULES:
        if cats and not re.fullmatch(cats, cat):
            continue
        if re.search(rx, name):
            return fid, "name"
    return TARGET_FALLBACK.get(r.get("target"), "unmapped"), "target"


def main(src, out):
    rows = []
    for f in sorted(glob.glob(os.path.join(src, "*.json"))):
        r = json.load(open(f))
        if "name" in r:
            rows.append(r)
    res = {}
    by = collections.defaultdict(list)
    how = collections.Counter()
    for r in rows:
        fid, why = assign(r)
        res[r["id"]] = fid
        by[fid].append(r["name"])
        how[why] += 1
    os.makedirs(out, exist_ok=True)
    json.dump(res, open(os.path.join(out, "exercise-map.json"), "w"), indent=0, sort_keys=True)
    json.dump({k: v for k, v in sorted(by.items())}, open(os.path.join(out, "family-members.json"), "w"), indent=1)
    print(len(rows), "exercises,", len(by), "families,", dict(how))
    for fid, names in sorted(by.items(), key=lambda x: -len(x[1])):
        print(f"{len(names):5d} {fid}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])

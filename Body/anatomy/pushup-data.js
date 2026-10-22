// Push-up content for the trial page, from Catalog/research/push-up.md
// ([R#] numbers refer to its reference list).
(() => {
  const R = {
    1: ["Suprak 2011", "https://pubmed.ncbi.nlm.nih.gov/20179649/"],
    2: ["Ebben 2011", "https://pubmed.ncbi.nlm.nih.gov/21873902/"],
    5: ["San Juan 2015", "https://pmc.ncbi.nlm.nih.gov/articles/PMC4327800/"],
    6: ["Yang 2011", "https://d.lib.msu.edu/etd/1639"],
    7: ["Suprak 2013", "https://pmc.ncbi.nlm.nih.gov/articles/PMC3867095/"],
    8: ["Lunden 2010", "https://pmc.ncbi.nlm.nih.gov/articles/PMC2841059/"],
    11: ["Kim 2016", "https://pmc.ncbi.nlm.nih.gov/articles/PMC4792988/"],
    12: ["Youdas 2010", "https://pubmed.ncbi.nlm.nih.gov/20664364/"],
    18: ["Ludewig 2004", "https://pubmed.ncbi.nlm.nih.gov/14977678/"],
    19: ["Park 2014", "https://pubmed.ncbi.nlm.nih.gov/24618724/"],
    21: ["Kang 2019", "https://pmc.ncbi.nlm.nih.gov/articles/PMC6863690/"],
    23: ["Sandhu 2008", "https://pmc.ncbi.nlm.nih.gov/articles/PMC2840817/"],
    25: ["Freeman 2006", "https://pubmed.ncbi.nlm.nih.gov/16540847/"],
    26: ["Howarth 2008", "https://pubmed.ncbi.nlm.nih.gov/18579905/"],
    27: ["Borreani 2015", "https://pmc.ncbi.nlm.nih.gov/articles/PMC5812863/"],
    31: ["Donkers 1993", "https://pubmed.ncbi.nlm.nih.gov/8514808/"],
    33: ["Lou 2001", "https://pubmed.ncbi.nlm.nih.gov/11390048/"],
    34: ["Polovinets 2018", "https://pubmed.ncbi.nlm.nih.gov/28684196/"],
    42: ["NASM push-up", "https://www.nasm.org/resource-center/exercise-library/push-up"],
    45: ["Push-up scale study", "https://pmc.ncbi.nlm.nih.gov/articles/PMC9362895/"],
    46: ["ACSM 2009", "https://pubmed.ncbi.nlm.nih.gov/19204579/"],
    47: ["NSCA Essentials", null],
  };
  const c = (...ns) => ns.map((n) => {
    const [t, u] = R[n];
    return u ? `<a href="${u}" target="_blank" rel="noopener">${t}</a>` : t;
  }).join(", ");

  window.PUSHUP = {
    phases: [
      { short: "Set", name: "Set the plank", time: "hold", start: 0, end: 1,
        text: "Hands under the shoulders, a little wider, fingers forward. One straight line from head to heels.",
        cues: ["Squeeze the glutes and brace the stomach: the abs hold the lower back straight.",
               "Spread the fingers and press the whole hand into the floor.",
               "Look at the floor just ahead of the hands."] },
      { short: "Lower", name: "Lower", time: "2 s", start: 1, end: 3,
        text: "Bend the elbows and bring the chest down between the hands. The shoulder blades slide toward each other as you go.",
        cues: ["Elbows go back at about 45° from the body, like an arrow, not out like a T.",
               "Hips come down with the chest.",
               "Breathe in on the way down."] },
      { short: "Bottom", name: "Bottom", time: "0.5 s", start: 3, end: 3.5,
        text: "Elbows bent past 90°, chest a fist or so above the floor. Stay tight: do not rest on the floor.",
        cues: ["Forearms close to vertical.", "Shoulders away from the ears."] },
      { short: "Press", name: "Press up", time: "1 s", start: 3.5, end: 4.5,
        text: "Push the floor away. Chest and hips rise together. This is the hardest part and where the chest and triceps work most.",
        cues: ["Breathe out as you push.", "Keep the elbows at the same angle to the body as on the way down."] },
      { short: "Plus", name: "Push the blades apart", time: "0.5 s", start: 4.5, end: 5,
        text: "With the arms straight, push a little further so the shoulder blades spread around the ribs. This \"plus\" is the serratus anterior's job, the muscle that keeps the blades flat on the ribs.",
        cues: ["Push the upper back toward the ceiling a few centimetres.", "Keep the elbows straight and the shoulders down."] },
    ],
    breath: [
      { kind: "hold", label: "Brace", start: 0, end: 1 },
      { kind: "in", label: "Breathe in", start: 1, end: 3.2 },
      { kind: "hold", label: "Brace", start: 3.2, end: 3.5 },
      { kind: "out", label: "Breathe out", start: 3.5, end: 4.7 },
      { kind: "hold", label: "Brace", start: 4.7, end: 5 },
    ],
    // Share of maximum effort through the rep. Averages from Freeman 2006 and
    // Borreani 2015, shaped by phase (lifting > lowering, Sandhu 2008; serratus
    // peaks in the plus, Ludewig 2004). Approximate: for showing which muscle
    // works when, not exact values.
    muscles: [
      { id: "tri", label: "Triceps", match: "triceps|anconeus", curve: [[0, .35], [1, .3], [3, .45], [3.5, .55], [4, .9], [4.5, .7], [5, .35]] },
      { id: "pec", label: "Chest", match: "pectoralis major", curve: [[0, .2], [1, .2], [3, .4], [3.5, .55], [4, .85], [4.5, .5], [5, .2]] },
      { id: "delt", label: "Front shoulder", match: "deltoid", curve: [[0, .25], [1, .25], [3, .35], [3.5, .45], [4, .6], [4.5, .4], [5, .25]] },
      { id: "serr", label: "Serratus anterior", match: "serratus anterior", curve: [[0, .75], [1, .45], [3, .25], [3.5, .3], [4, .4], [4.5, .45], [5, .75]] },
      { id: "core", label: "Abs, obliques", match: "rectus abdominis|oblique|transversus|pyramidalis", curve: [[0, .23], [5, .23]], fault: { sag: 0.45 } },
      { id: "quad", label: "Front thigh", match: "rectus femoris|vastus", curve: [[0, .2], [5, .2]], fault: { sag: 0.6 } },
    ],
    clips: [
      { id: "good", label: "Good form" },
      { id: "sag", label: "Hips sag", fault: true, view: "side",
        alert: "<b>Hips sag</b>The lower back arches and takes the load.",
        what: "The hips drop below the line from the shoulders to the heels, so the lower back arches.",
        why: `The abdominal muscles give about two thirds of the lower back's stiffness in a push-up (${c(26)}). When the hips sag they have let go, and the lower back is bent backward under load.`,
        fix: "Squeeze the glutes and pull the ribs toward the hips before each rep. If the line still breaks, put the hands on a bench or the knees on the floor." },
      { id: "flare", label: "Elbows flare", fault: true, view: "front",
        alert: "<b>Elbows out</b>The upper arms are more than 60° from the body.",
        what: "The elbows point out to the side, so the upper arms make a T with the body.",
        why: `Above about 60° the shoulder blade stops tilting back and rotating up as you press, which can narrow the space over the rotator cuff (${c(7)}).`,
        fix: "Point the elbows back at about 45°. Screw the hands into the floor as if turning them outward, without moving them." },
      { id: "head", label: "Head drops", fault: true, view: "side",
        alert: "<b>Head drops</b>The chin reaches for the floor first.",
        what: "The head and chin lead the way down, so the neck bends forward.",
        why: `It breaks the straight line and loads the neck, and often hides a short range: the nose gets near the floor before the chest does (${c(42)}, coaching convention).`,
        fix: "Keep a long neck. Look at a spot just ahead of the hands and let the chest reach the bottom first." },
    ],
    below: [
      { title: "How much you lift", html: `<p class="note" style="margin-top:6px">Share of body weight on the hands (${c(1, 2)})</p><ul>
        <li>Hands on a 61 cm bench: <b>41%</b></li>
        <li>Knees on the floor: <b>49–62%</b></li>
        <li>Hands on a 30 cm step: <b>55%</b></li>
        <li>Standard push-up: <b>64–75%</b></li>
        <li>Feet on a 61 cm bench: <b>74%</b></li></ul>` },
      { title: "Hand position", html: `<ul>
        <li>Hands under the shoulders, index finger under the outer edge of the shoulder (${c(7)}).</li>
        <li>Fingers forward. Turning the hands inward raises the shear on the elbow (${c(33)}).</li>
        <li>Narrow hands work the triceps and chest more; wide hands work the serratus more (${c(11)}).</li>
        <li>Sore wrists: use fists or handles (${c(34, 12)}).</li></ul>` },
      { title: "Tempo and breath", html: `<ul>
        <li>About 2 s down, a short pause, 1–2 s up (${c(46)}).</li>
        <li>Faster reps raise the force on the hands and the muscle activity (${c(6)}).</li>
        <li>Breathe in on the way down, out as you push. This is coaching convention, not tested in studies (${c(47)}).</li></ul>` },
    ],
    science: `
      <p class="note" style="margin:0 0 10px">Full record with 48 sources: Catalog/research/push-up.md. What the animation uses:</p>
      <div class="scroll"><table>
        <tr><th>What</th><th>Value used</th><th>Source</th></tr>
        <tr><td>Body angle at the top</td><td>About 15–20° to the floor (here 21° from the model's arm length)</td><td>${c(6)}</td></tr>
        <tr><td>Elbow at the bottom</td><td>Labs use 90–105° flexion; here 108°, chest about a fist from the floor</td><td>${c(27, 7, 45)}</td></tr>
        <tr><td>Elbow flare</td><td>45° from the body; keep under 60°</td><td>${c(27, 7, 42)}</td></tr>
        <tr><td>Shoulder blade, bottom to top</td><td>Turns about 15° around the ribs, 6° less upward rotation</td><td>${c(7)}</td></tr>
        <tr><td>Plus phase</td><td>About 12° more turn, 5° less upward rotation (wall push-up data, applied as a change)</td><td>${c(8)}</td></tr>
        <tr><td>Hand width</td><td>Shoulder width plus about 4 cm each side</td><td>${c(7, 11)}</td></tr>
        <tr><td>Forearm</td><td>Turned palm-down (pronated) about 140° from the anatomical position; the radius crosses the ulna</td><td>Model geometry</td></tr>
        <tr><td>Muscle levels</td><td>Triceps 66, chest 61, front shoulder 42, abs 20–25 %MVIC on average; lifting much higher than lowering; serratus highest in the plus</td><td>${c(25, 27, 23, 18)}</td></tr>
        <tr><td>Hip-line warning</td><td>More than 6° off straight</td><td>Our threshold</td></tr>
      </table></div>
      <p class="note" style="margin-top:10px">Not found in any study: wrist and ankle angles (estimated from geometry), and glute activity in the push-up.</p>`,
    ideas: [
      "<b>Before a set:</b> the exercise card opens on this player at the side view, playing good form once at half speed. One tap switches to the view the user prefers, and the app remembers it.",
      "<b>During a set:</b> only the phase name, one cue and the breathing bar show, large enough to read from the floor. The rep counter can follow the same phases.",
      "<b>Mistakes:</b> each mistake plays beside good form. The readouts turn orange at the moment the form breaks, so the user sees when, not only what.",
      "<b>Muscles:</b> the bars double as filters: tap one and only that muscle lights up, which also answers \"what does this work?\".",
      "<b>Glass view:</b> for the shoulder blades and the forearm turning, the skin and muscles fade so the bones show.",
      "<b>Progressions:</b> easier and harder versions sit under the player with the share of body weight each one lifts, so the user can pick the right step.",
    ],
  };
})();

// Accrue exercise rig: draws one figure from keyframed poses, plus equipment,
// cue overlays and a breathing track. Every exercise animation is data
// (see Catalog/exercises/*.json), so the app can redraw it natively in any theme.
//
// Angles are degrees in screen space: 0 points down, 90 points right, 180 up.
// A pose may give a limb by angles (uaR/faR, thR/shR) or by an end target
// (handR, footR) solved with two-bone IK.
(function (root) {
  const LEN = { torso: 54, neck: 7, head: 9.5, ua: 30, fa: 28, th: 45, sh: 43, foot: 14, shW: 17, hipW: 9 };
  const rad = (d) => (d * Math.PI) / 180;
  const dir = (a) => [Math.sin(rad(a)), Math.cos(rad(a))];
  const add = (p, v, k = 1) => [p[0] + v[0] * k, p[1] + v[1] * k];
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1]];
  const len = (v) => Math.hypot(v[0], v[1]);
  const ease = (x) => x * x * (3 - 2 * x);

  function ik(rootP, target, l1, l2, bend) {
    const d0 = sub(target, rootP);
    let d = len(d0);
    const maxD = l1 + l2 - 0.01;
    if (d > maxD) d = maxD;
    if (d < 1) d = 1;
    const base = Math.atan2(d0[1], d0[0]);
    const cosA = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d);
    const a = Math.acos(Math.max(-1, Math.min(1, cosA)));
    const ang = base + bend * a;
    const mid = [rootP[0] + l1 * Math.cos(ang), rootP[1] + l1 * Math.sin(ang)];
    const v = sub(target, mid);
    const end = add(mid, v, l2 / (len(v) || 1));
    return [mid, end];
  }

  function lerpVal(a, b, k) {
    if (Array.isArray(a)) return a.map((x, i) => x + (b[i] - x) * k);
    if (typeof a === "number") return a + (b - a) * k;
    return k < 0.5 ? a : b;
  }

  // Pose at time t (0..1) from keyframes [{t, ...pose}], merged over base.
  function poseAt(anim, t) {
    const ks = anim.keys.map((k) => Object.assign({}, anim.base, k));
    if (t <= ks[0].t) return ks[0];
    for (let i = 0; i < ks.length - 1; i++) {
      const a = ks[i], b = ks[i + 1];
      if (t >= a.t && t <= b.t) {
        const x = (t - a.t) / (b.t - a.t || 1);
        const k = anim.easing === "linear" ? x : ease(x);
        const out = {};
        for (const key of Object.keys(a)) out[key] = key in b ? lerpVal(a[key], b[key], k) : a[key];
        return out;
      }
    }
    return ks[ks.length - 1];
  }

  // Solve joint positions for one pose.
  function solve(p, view) {
    const J = {};
    const u = dir(p.torso ?? 180);
    let n = [-u[1], u[0]]; // the side the figure faces
    if (p.flip) n = [-n[0], -n[1]];
    J.hip = p.hip;
    J.neck = add(p.hip, u, LEN.torso);
    J.chest = add(add(p.hip, u, LEN.torso * 0.68), n, 6);
    J.head = add(J.neck, dir(p.head ?? p.torso ?? 180), LEN.neck + LEN.head);
    const scap = p.scap || [0, 0]; // [retraction, elevation] in px
    J.n = n;
    J.u = u;
    J.trap = add(add(J.neck, u, -5), n, -9); // where a back-squat bar sits
    if (view === "front") {
      const lat = [u[1] * -1, u[0]]; // screen-right when upright
      const w = LEN.shW - scap[0] * 0.6;
      const sc = add(add(J.neck, u, -3 + scap[1]), [0, 0]);
      J.shoulderR = add(sc, lat, w);
      J.shoulderL = add(sc, lat, -w);
      J.scapR = add(J.shoulderR, lat, -6);
      J.scapL = add(J.shoulderL, lat, 6);
      J.hipR = add(p.hip, lat, LEN.hipW);
      J.hipL = add(p.hip, lat, -LEN.hipW);
    } else {
      const s = add(add(J.neck, u, -4 + scap[1]), n, -scap[0]);
      J.shoulderR = J.shoulderL = s;
      J.scapR = J.scapL = add(add(s, n, -7), u, -6);
      J.hipR = J.hipL = p.hip;
    }
    for (const side of ["R", "L"]) {
      const S = J["shoulder" + side];
      let hand = p["hand" + side] ?? (side === "L" ? (view === "front" ? null : p.handR) : null);
      if (typeof hand === "string") hand = add(J[hand], p["hand" + side + "Off"] ?? p.handROff ?? [0, 0]);
      if (hand) {
        const bend = p["elb" + side] ?? p.elbR ?? -1;
        const [e, h] = ik(S, hand, LEN.ua * (p["uaS" + side] ?? p.uaS ?? 1), LEN.fa * (p["faS" + side] ?? p.faS ?? 1), bend);
        J["elbow" + side] = e;
        J["hand" + side] = h;
      } else {
        const ua = p["ua" + side] ?? p.uaR ?? 0;
        const fa = p["fa" + side] ?? p.faR ?? ua;
        // uaS/faS shorten a segment that points toward the camera (top-down views)
        J["elbow" + side] = add(S, dir(ua), LEN.ua * (p["uaS" + side] ?? p.uaS ?? 1));
        J["hand" + side] = add(J["elbow" + side], dir(fa), LEN.fa * (p["faS" + side] ?? p.faS ?? 1));
      }
      const H = J["hip" + side];
      const foot = p["foot" + side] ?? (side === "L" && view !== "front" && !("thL" in p) ? p.footR : null);
      if (foot) {
        const bend = p["knee" + side] ?? p.kneeR ?? -1;
        const [k, a] = ik(H, foot, LEN.th, LEN.sh, bend);
        J["knee" + side] = k;
        J["ankle" + side] = a;
      } else {
        const th = p["th" + side] ?? p.thR ?? 0;
        const sh = p["sh" + side] ?? p.shR ?? th;
        J["knee" + side] = add(H, dir(th), LEN.th * (p["thS" + side] ?? p.thS ?? 1));
        J["ankle" + side] = add(J["knee" + side], dir(sh), LEN.sh * (p["shS" + side] ?? p.shS ?? 1));
      }
      const ft = p["ft" + side] ?? p.ftR ?? 90;
      J["toe" + side] = add(J["ankle" + side], dir(ft), view === "front" ? 5 : LEN.foot);
      J["midfoot" + side] = add(J["ankle" + side], dir(ft), view === "front" ? 0 : LEN.foot * 0.4);
    }
    return J;
  }

  const fmt = (n) => Math.round(n * 10) / 10;
  const pt = (p) => `${fmt(p[0])},${fmt(p[1])}`;
  const line = (a, b, w, cls) =>
    `<line x1="${fmt(a[0])}" y1="${fmt(a[1])}" x2="${fmt(b[0])}" y2="${fmt(b[1])}" stroke-width="${w}" class="${cls}" stroke-linecap="round"/>`;

  function resolvePt(J, ref) {
    if (Array.isArray(ref)) return ref;
    return J[ref];
  }

  function drawEquipment(eq, J, p, view) {
    let s = "";
    for (const e of eq || []) {
      const at = e.at ? J[e.at] : null;
      switch (e.type) {
        case "ground":
          s += `<line x1="0" y1="${e.y}" x2="320" y2="${e.y}" class="eq-ground" stroke-width="2"/>`;
          break;
        case "mat":
          s += `<rect x="${e.x}" y="${e.y}" width="${e.w}" height="4" rx="2" class="eq-soft"/>`;
          break;
        case "bench":
          s += `<rect x="${e.x}" y="${e.y}" width="${e.w}" height="${e.h ?? 9}" rx="3" class="eq-solid"/>`;
          for (const lx of e.legs || [e.x + 8, e.x + e.w - 8])
            s += `<line x1="${lx}" y1="${e.y + (e.h ?? 9)}" x2="${lx}" y2="${e.ground}" stroke-width="5" class="eq-line"/>`;
          if (e.back) s += line([e.back[0], e.back[1]], [e.back[2], e.back[3]], 9, "eq-solidline");
          break;
        case "rack":
          s += line([e.x, e.ground], [e.x, e.top], 4, "eq-line");
          s += line([e.x - 6, e.hook], [e.x + 4, e.hook], 4, "eq-line");
          break;
        case "plate": {
          // barbell seen end-on: plate plus sleeve
          const q = e.at ? J[e.at] : e.pos;
          const off = e.offset ? add(q, e.offset) : q;
          s += `<circle cx="${fmt(off[0])}" cy="${fmt(off[1])}" r="${e.r ?? 15}" class="eq-plate"/>`;
          s += `<circle cx="${fmt(off[0])}" cy="${fmt(off[1])}" r="3" class="eq-hub"/>`;
          break;
        }
        case "barFront": {
          const a = J.handL, b = J.handR;
          const v = sub(b, a), l = len(v) || 1, d = [v[0] / l, v[1] / l];
          const x0 = add(a, d, -(e.ext ?? 40)), x1 = add(b, d, e.ext ?? 40);
          s += line(x0, x1, 3.5, "eq-line");
          for (const end of [[x0, -1], [x1, 1]]) {
            const c = add(end[0], d, -end[1] * 8);
            s += line(add(c, [-d[1], d[0]], -14), add(c, [-d[1], d[0]], 14), 7, "eq-solidline");
          }
          break;
        }
        case "dumbbellFront":
          for (const h of [J.handL, J.handR]) {
            s += line(add(h, [-9, 0]), add(h, [9, 0]), 3.5, "eq-line");
            s += line(add(h, [-9, -6]), add(h, [-9, 6]), 6, "eq-solidline");
            s += line(add(h, [9, -6]), add(h, [9, 6]), 6, "eq-solidline");
          }
          break;
        case "dumbbell": {
          const h = at;
          s += `<circle cx="${fmt(h[0])}" cy="${fmt(h[1])}" r="${e.r ?? 8}" class="eq-plate"/>`;
          break;
        }
        case "fixedbar":
          s += line([e.x0, e.y], [e.x1, e.y], 4, "eq-line");
          if (e.posts) for (const x of [e.x0, e.x1]) s += line([x, e.y], [x, e.y - 14], 4, "eq-line");
          break;
        case "table":
          s += `<rect x="${e.x}" y="${e.y}" width="${e.w}" height="6" rx="2" class="eq-solid"/>`;
          s += line([e.x + 6, e.y + 6], [e.x + 6, e.ground], 5, "eq-line");
          s += line([e.x + e.w - 6, e.y + 6], [e.x + e.w - 6, e.ground], 5, "eq-line");
          break;
        case "cable": {
          const a = e.anchor;
          s += `<rect x="${a[0] - 4}" y="${a[1] - 40}" width="8" height="${e.ground - a[1] + 40}" rx="2" class="eq-solid"/>`;
          s += line(a, at, 1.5, "eq-cable");
          s += `<circle cx="${a[0]}" cy="${a[1]}" r="4" class="eq-hub"/>`;
          if (e.rope) {
            s += line(at, add(at, [0, -5]), 4, "eq-rope");
            s += line(at, add(at, [0, 6]), 4, "eq-rope");
          }
          break;
        }
        case "rower": {
          s += line([e.x0, e.rail], [e.x1, e.rail], 4, "eq-line");
          s += line([e.x0 + 4, e.rail], [e.x0 + 4, e.ground], 4, "eq-line");
          s += line([e.x1 - 6, e.rail], [e.x1 - 6, e.ground], 4, "eq-line");
          s += `<circle cx="${e.x1 + 4}" cy="${e.rail - 26}" r="20" class="eq-solid"/>`;
          s += line([e.x1 - 14, e.footY - 12], [e.x1 - 6, e.footY + 8], 5, "eq-solidline");
          s += `<rect x="${fmt(J.hip[0] - 13)}" y="${e.rail - 9}" width="26" height="6" rx="2" class="eq-solid"/>`;
          s += line(J.handR, [e.x1 - 4, e.rail - 30], 1.5, "eq-cable");
          s += line(add(J.handR, [0, -6]), add(J.handR, [0, 6]), 4, "eq-rope");
          break;
        }
        case "jumprope": {
          // rope as a loop through both hands; phase sweeps it around the body
          const ph = rad(p.rope ?? 0);
          const c = [J.hip[0], J.hip[1] - 12];
          const rx = e.rx ?? 26, ry = e.ry ?? 90;
          const tip = [c[0] + Math.sin(ph) * rx, c[1] - Math.cos(ph) * ry];
          const h = J.handR;
          s += `<path d="M${pt(h)} Q${pt([tip[0] * 2 - (h[0] + J.handL[0]) / 2, tip[1] * 2 - (h[1] + J.handL[1]) / 2])} ${pt(J.handL)}" class="eq-cable" fill="none" stroke-width="2"/>`;
          break;
        }
      }
    }
    return s;
  }

  function arrowHead(tip, from, cls) {
    const v = sub(tip, from), l = len(v) || 1, d = [v[0] / l, v[1] / l], nn = [-d[1], d[0]];
    const a = add(add(tip, d, -6), nn, 4), b = add(add(tip, d, -6), nn, -4);
    return `<path d="M${pt(tip)} L${pt(a)} L${pt(b)} Z" class="${cls}"/>`;
  }

  function angleBetween(v) {
    return Math.atan2(v[1], v[0]);
  }

  function drawCue(c, J, alpha) {
    let s = `<g opacity="${fmt(alpha)}">`;
    const at = c.at ? resolvePt(J, c.at) : null;
    switch (c.kind) {
      case "arrow": {
        const from = add(at, c.off || [0, 0]);
        const to = add(from, c.dir);
        s += line(from, to, 2.2, "cue-stroke");
        s += arrowHead(to, from, "cue-fill");
        break;
      }
      case "glow":
        for (const j of c.joints) {
          const q = J[j];
          if (j.startsWith("scap")) {
            const u = J.u;
            const a = add(q, u, 9), b = add(q, u, -9);
            s += line(a, b, 7, "cue-plate");
          } else s += `<circle cx="${fmt(q[0])}" cy="${fmt(q[1])}" r="${c.r ?? 6}" class="cue-ring"/>`;
        }
        break;
      case "arc": {
        const v = resolvePt(J, c.at), a = resolvePt(J, c.a), b = resolvePt(J, c.b);
        const r = c.r ?? 14;
        let a1 = angleBetween(sub(a, v)), a2 = angleBetween(sub(b, v));
        let d = a2 - a1;
        while (d > Math.PI) d -= 2 * Math.PI;
        while (d < -Math.PI) d += 2 * Math.PI;
        const p1 = [v[0] + r * Math.cos(a1), v[1] + r * Math.sin(a1)];
        const p2 = [v[0] + r * Math.cos(a1 + d), v[1] + r * Math.sin(a1 + d)];
        s += `<path d="M${pt(v)} L${pt(p1)} A${r} ${r} 0 0 ${d > 0 ? 1 : 0} ${pt(p2)} Z" class="cue-wedge"/>`;
        if (c.label) {
          const m = a1 + d / 2;
          const lp = [v[0] + (r + 10) * Math.cos(m), v[1] + (r + 10) * Math.sin(m)];
          s += `<text x="${fmt(lp[0])}" y="${fmt(lp[1] + 3)}" class="cue-text" text-anchor="middle">${c.label}</text>`;
        }
        break;
      }
      case "rotate": {
        // curved arrow around a limb axis: external rotation sweeps away from the body
        const q = add(resolvePt(J, c.at), c.off || [0, 0]);
        const r = c.r ?? 9;
        const sweep = c.dir === "int" ? 0 : 1;
        const p1 = [q[0] - r, q[1]], p2 = [q[0] + r * 0.2, q[1] - r * 0.98];
        const pathA = sweep ? `M${pt(p1)} A${r} ${r * 0.55} 0 1 1 ${pt([q[0] + r, q[1] + 1])}` : `M${pt([q[0] + r, q[1]])} A${r} ${r * 0.55} 0 1 0 ${pt([q[0] - r, q[1] + 1])}`;
        s += `<path d="${pathA}" class="cue-stroke" fill="none" stroke-width="2"/>`;
        const tip = sweep ? [q[0] + r, q[1] + 1] : [q[0] - r, q[1] + 1];
        s += arrowHead(tip, [tip[0], tip[1] - 6], "cue-fill");
        void p2;
        break;
      }
      case "line": {
        const a = resolvePt(J, c.from), b = resolvePt(J, c.to);
        s += line(a, b, 1.6, c.dash === false ? "cue-stroke" : "cue-dash");
        break;
      }
      case "vline": {
        const q = resolvePt(J, c.at);
        s += `<line x1="${fmt(q[0])}" y1="${c.y0 ?? 10}" x2="${fmt(q[0])}" y2="${c.y1 ?? q[1]}" class="cue-dash" stroke-width="1.6"/>`;
        break;
      }
      case "trace": {
        s += `<path d="${c._path}" class="cue-dash" fill="none" stroke-width="1.6"/>`;
        break;
      }
    }
    if (c.tag && at) {
      const q = add(at, c.tagOff || [10, -10]);
      s += `<text x="${fmt(q[0])}" y="${fmt(q[1])}" class="cue-text" text-anchor="${c.tagAnchor || "start"}">${c.tag}</text>`;
    }
    return s + "</g>";
  }

  function cueAlpha(c, t) {
    const [a, b] = c.when || [0, 1];
    const f = 0.04;
    if (a <= b) {
      if (t < a - f || t > b + f) return 0;
      return Math.min(1, (t - (a - f)) / f, ((b + f) - t) / f);
    }
    return t >= a || t <= b ? 1 : 0;
  }

  function breathAt(anim, t) {
    for (const b of anim.breath || []) if (t >= b.when[0] && t <= b.when[1]) return b;
    return null;
  }

  function phaseAt(anim, t) {
    let cur = null;
    for (const k of anim.keys) if (k.phase && t >= k.t) cur = k.phase;
    return cur;
  }

  // Precompute traced paths (bar path, hand path) over one cycle.
  function prepare(anim) {
    for (const c of anim.cues || []) {
      if (c.kind === "trace") {
        const pts = [];
        for (let i = 0; i <= 60; i++) {
          const J = solve(poseAt(anim, i / 60), anim.view);
          pts.push(add(J[c.of], c.off || [0, 0]));
        }
        c._path = "M" + pts.map(pt).join(" L");
      }
    }
    anim._ready = true;
  }

  function frame(anim, t) {
    if (!anim._ready) prepare(anim);
    const p = poseAt(anim, t);
    const J = solve(p, anim.view);
    const front = anim.view === "front";
    const hot = new Set();
    for (const c of anim.cues || []) if (cueAlpha(c, t) > 0.5) for (const j of c.hot || []) hot.add(j);
    const seg = (a, b, w, far, name) => line(J[a], J[b], w, (far ? "fig-far" : "fig") + (hot.has(name) ? " fig-hot" : ""));
    let back = "", body = "";
    // far side first in side view
    if (!front) {
      back += seg("hipL", "kneeL", 11, true, "thighL") + seg("kneeL", "ankleL", 9, true, "shinL") + seg("ankleL", "toeL", 6, true, "footL");
      back += seg("shoulderL", "elbowL", 8, true, "upperarmL") + seg("elbowL", "handL", 7, true, "forearmL");
    }
    // torso
    if (front) {
      body += `<path d="M${pt(J.shoulderL)} L${pt(J.shoulderR)} L${pt(J.hipR)} L${pt(J.hipL)} Z" class="fig-torso${hot.has("torso") ? " fig-hot" : ""}" stroke-width="10" stroke-linejoin="round"/>`;
    } else {
      body += line(J.hip, add(J.neck, J.u, -2), 17, "fig" + (hot.has("torso") ? " fig-hot" : ""));
    }
    body += line(J.neck, add(J.neck, sub(J.head, J.neck), 0.5), 6, "fig");
    body += `<circle cx="${fmt(J.head[0])}" cy="${fmt(J.head[1])}" r="${LEN.head}" class="fig-head"/>`;
    const sides = front ? ["L", "R"] : ["R"];
    for (const sd of sides) {
      body += seg("hip" + sd, "knee" + sd, 12, false, "thigh" + sd) + seg("knee" + sd, "ankle" + sd, 10, false, "shin" + sd);
      if (!front) body += seg("ankle" + sd, "toe" + sd, 6, false, "foot" + sd);
    }
    let arms = "";
    for (const sd of sides) {
      arms += seg("shoulder" + sd, "elbow" + sd, 9, false, "upperarm" + sd) + seg("elbow" + sd, "hand" + sd, 8, false, "forearm" + sd);
      arms += `<circle cx="${fmt(J["shoulder" + sd][0])}" cy="${fmt(J["shoulder" + sd][1])}" r="2.4" class="fig-joint"/>`;
    }
    const eq = drawEquipment(anim.equipment, J, p, anim.view);
    const eqFront = drawEquipment(anim.equipmentFront, J, p, anim.view);
    let cues = "";
    for (const c of anim.cues || []) {
      const a = cueAlpha(c, t);
      if (a > 0) cues += drawCue(c, J, a);
    }
    const br = breathAt(anim, t);
    let breath = "";
    if (br && J.chest) {
      const local = (t - br.when[0]) / (br.when[1] - br.when[0] || 1);
      const r = br.type === "inhale" ? 4 + 10 * local : br.type === "exhale" ? 14 - 10 * local : 9;
      breath = `<circle cx="${fmt(J.chest[0])}" cy="${fmt(J.chest[1])}" r="${fmt(r)}" class="breath breath-${br.type}"/>`;
    }
    const svg = `<svg viewBox="${anim.viewBox || "0 0 320 240"}" xmlns="http://www.w3.org/2000/svg" role="img">${eq}${back}${breath}${body}${arms}${eqFront}${cues}</svg>`;
    const activeCues = (anim.cues || []).filter((c) => c.text && cueAlpha(c, t) > 0.5).map((c) => c.text);
    return { svg, phase: phaseAt(anim, t), breath: br ? br.type : null, cues: activeCues };
  }

  root.AccrueRig = { frame, poseAt, solve, LEN };
})(typeof window !== "undefined" ? window : globalThis);

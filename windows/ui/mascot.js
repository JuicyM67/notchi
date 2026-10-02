// Tamanotchis karaktärer, ritade med kod i en 100×100-yta.
// Samma figurer, stilar och uttryck som Mac-versionen (Sources/Tamanotchi/Mascot.swift).

const hex = (h, a = 1) => {
  const r = (h >> 16) & 255, g = (h >> 8) & 255, b = h & 255;
  return `rgba(${r},${g},${b},${a})`;
};

export const GANG = ["pim", "oda", "bo", "kix"];
export const ANIMALS = ["fia", "misse", "hubbe", "pingo"];

export const SKINS = {
  pim:   { name: "Pim",   desc: "mintgrön pebble",  body: 0x5ED6A8, shade: 0x2EA37A, led: 0x7DFFC9, eyes: [[37, 54], [63, 54]], mouth: [50, 69] },
  oda:   { name: "Oda",   desc: "korallröd droppe", body: 0xFF7A6B, shade: 0xDB4D45, led: 0xFFB3A8, eyes: [[38, 58], [62, 58]], mouth: [50, 74] },
  bo:    { name: "Bo",    desc: "lavendelböna",     body: 0xA88CFF, shade: 0x7559DB, led: 0xC9B8FF, eyes: [[34, 58], [66, 58]], mouth: [50, 72] },
  kix:   { name: "Kix",   desc: "solgul blomma",    body: 0xFFC73D, shade: 0xED941A, led: 0xFFE58A, eyes: [[39, 54], [61, 54]], mouth: [50, 68] },
  fia:   { name: "Fia",   desc: "räv",              body: 0xFF8A3D, shade: 0xD9601A, led: 0xFFD2A6, eyes: [[38, 55], [62, 55]], mouth: [50, 77] },
  misse: { name: "Misse", desc: "katt",             body: 0x8FA3BF, shade: 0x5E7190, led: 0xBFE3FF, eyes: [[38, 57], [62, 57]], mouth: [50, 72] },
  hubbe: { name: "Hubbe", desc: "uggla",            body: 0x6FC2B0, shade: 0x3F8F7E, led: 0xB8FFF0, eyes: [[37, 50], [63, 50]], mouth: [50, 74] },
  pingo: { name: "Pingo", desc: "pingvin",          body: 0x4A5A8F, shade: 0x283158, led: 0xA9C4FF, eyes: [[41, 49], [59, 49]], mouth: [50, 69] },
};

const INK = 0x1F1A29;
const neonOf = (k) => (k === "pingo" ? 0x8FA6FF : SKINS[k].body);

function bodyShape(k) {
  const p = new Path2D();
  switch (k) {
    case "pim": p.roundRect(12, 24, 76, 66, 30); break;
    case "oda":
      p.moveTo(50, 8);
      p.bezierCurveTo(60, 26, 86, 38, 86, 60);
      p.arc(50, 60, 36, 0, Math.PI, false);
      p.bezierCurveTo(14, 38, 40, 26, 50, 8);
      break;
    case "bo": p.roundRect(6, 34, 88, 54, 27); break;
    case "kix":
      for (let i = 0; i < 8; i++) {
        const a = (i / 8) * 2 * Math.PI;
        const cx = 50 + Math.cos(a) * 30, cy = 56 + Math.sin(a) * 30;
        p.moveTo(cx + 15, cy); p.ellipse(cx, cy, 15, 15, 0, 0, 2 * Math.PI);
      }
      p.moveTo(82, 56); p.ellipse(50, 56, 32, 32, 0, 0, 2 * Math.PI);
      break;
    case "fia": p.roundRect(16, 30, 68, 60, 28); break;
    case "misse": p.roundRect(16, 32, 68, 58, 28); break;
    case "hubbe": p.ellipse(50, 58, 32, 36, 0, 0, 2 * Math.PI); break;
    case "pingo": p.roundRect(20, 20, 60, 72, 30); break;
  }
  return p;
}

function outline(k) {
  if (k !== "kix") return bodyShape(k);
  const p = new Path2D();
  for (let i = 0; i <= 240; i++) {
    const a = (i / 240) * 2 * Math.PI, r = 36 + 7 * Math.cos(8 * a);
    const x = 50 + r * Math.cos(a), y = 56 + r * Math.sin(a);
    i === 0 ? p.moveTo(x, y) : p.lineTo(x, y);
  }
  p.closePath();
  return p;
}

const ell = (x, y, w, h) => { const p = new Path2D(); p.ellipse(x + w / 2, y + h / 2, w / 2, h / 2, 0, 0, 2 * Math.PI); return p; };
const rrect = (x, y, w, h, r) => { const p = new Path2D(); p.roundRect(x, y, w, h, Math.max(0, Math.min(r, w / 2, h / 2))); return p; };
const tri = (a, b, c) => { const p = new Path2D(); p.moveTo(...a); p.lineTo(...b); p.lineTo(...c); p.closePath(); return p; };
const quad = (x0, y0, cx, cy, x1, y1) => { const p = new Path2D(); p.moveTo(x0, y0); p.quadraticCurveTo(cx, cy, x1, y1); return p; };

/**
 * Ritar en karaktär. o = { skin, state, level, mood, style, t }
 * state: idle | thinking | working | needsApproval | done | listening | speaking
 * mood: normal | sleepy | proud | stressed;  style: visor | neon | classic
 */
export function drawMascot(ctx, size, o) {
  const k = SKINS[o.skin] ? o.skin : "pim";
  const S = SKINS[k];
  const { state = "idle", level = 0, mood = "normal", style = "visor", t = 0 } = o;
  const neon = neonOf(k);
  const calm = state === "idle" || state === "done";
  const yawning = mood === "sleepy" && state === "idle" && (t % 14) < 1.6;
  const every = mood === "sleepy" ? 2.8 : 4.2;
  const blinking = ((t % every) < (mood === "sleepy" ? 0.3 : 0.12) && state !== "done") || yawning;

  const fill = (p, c) => { ctx.fillStyle = c; ctx.fill(p); };
  const stroke = (p, c, w, cap = "round", join = "round") => {
    ctx.strokeStyle = c; ctx.lineWidth = w; ctx.lineCap = cap; ctx.lineJoin = join; ctx.stroke(p);
  };
  const glowStroke = (p, h, w, a = 1) => {
    for (const [ww, op] of [[w + 8, 0.08], [w + 4, 0.16], [w + 1.5, 0.35]]) stroke(p, hex(h, op * a), ww);
    stroke(p, hex(h, a), w);
  };
  const paint = (p, fillHex, glow = neon, width = 1.6, glowA = 1) => {
    if (style === "neon") {
      fill(p, hex(0x15141B));
      stroke(p, hex(glow, 0.25 * glowA), width + 3);
      stroke(p, hex(glow, glowA), width);
    } else fill(p, typeof fillHex === "string" ? fillHex : hex(fillHex));
  };

  ctx.save();
  ctx.clearRect(0, 0, size, size);
  const s = size / 100;
  ctx.scale(s, s);

  // Rörelse per tillstånd
  let bob = 0, squash = 1, tilt = 0;
  const pace = mood === "stressed" ? 1.8 : mood === "sleepy" ? 0.6 : 1;
  switch (state) {
    case "idle": squash = 1 + 0.025 * Math.sin(t * 2 * pace) + (yawning ? 0.05 : 0); break;
    case "thinking": bob = 2 * Math.sin(t * 2.5); break;
    case "working": bob = 2.5 * Math.abs(Math.sin(t * 6)); squash = 1 + 0.03 * Math.sin(t * 12); break;
    case "needsApproval": bob = -6 * Math.abs(Math.sin(t * 5)); squash = 1 + 0.06 * Math.sin(t * 10); break;
    case "done": bob = -8 * Math.max(0, Math.sin(t * 4)); squash = 1 + 0.05 * Math.sin(t * 8); break;
    case "listening": tilt = 8; squash = 1 + level * 0.06; break;
    case "speaking": squash = 1 + level * 0.05; break;
  }
  if (state === "listening") {
    const r = 44 + level * 8;
    stroke(ell(50 - r, 56 - r, 2 * r, 2 * r), hex(S.body, 0.5), 3);
  }
  ctx.translate(50, 90 + bob);
  ctx.rotate((tilt * Math.PI) / 180);
  ctx.scale(1 / squash, squash);
  ctx.translate(-50, -90);

  // ── Bakom kroppen
  const busy = state === "working" || state === "thinking";
  if (k === "bo") {
    const stem = quad(50, 35, 50, 22, 56, 16);
    const a = busy ? 0.6 + 0.4 * Math.sin(t * 6) : 1;
    if (style === "classic") {
      stroke(stem, hex(S.shade), 3);
      fill(ell(51, 9, 11, 11), hex(0xFFD966, a));
    } else if (style === "visor") {
      stroke(stem, hex(0x2A2833), 3);
      fill(ell(48.5, 5.5, 16, 16), hex(0x7CF2FF, 0.2 * a));
      fill(ell(52.3, 9.3, 8.4, 8.4), hex(0x7CF2FF, a));
      const arc = new Path2D(); arc.arc(57.5, 15, 9, (-150 * Math.PI) / 180, (-30 * Math.PI) / 180, false);
      stroke(arc, hex(0x7CF2FF, 0.7 * a), 1.4);
    } else {
      stroke(stem, hex(neon), 2.4);
      fill(ell(47.5, 4.5, 18, 18), hex(neon, 0.18));
      fill(ell(52, 9, 9, 9), "#fff");
      fill(ell(52, 9, 9, 9), hex(neon, busy ? 0.3 + 0.4 * Math.sin(t * 6) : 0.55));
    }
  } else if (k === "fia" || k === "misse") {
    const fox = k === "fia";
    for (const flip of [false, true]) {
      const m = (x) => (flip ? 100 - x : x);
      paint(fox ? tri([m(20), 42], [m(25), 11], [m(46), 31]) : tri([m(19), 46], [m(21), 13], [m(44), 35]), S.body);
      if (style !== "neon") {
        fill(fox ? tri([m(26), 34], [m(28), 19], [m(39), 30]) : tri([m(24), 38], [m(25), 22], [m(36), 33]),
          hex(fox ? 0xFFD9BD : 0xF4B6C8));
      }
    }
  } else if (k === "hubbe") {
    for (const flip of [false, true]) {
      const m = (x) => (flip ? 100 - x : x);
      paint(tri([m(25), 33], [m(21), 11], [m(40), 25]), S.shade);
    }
  } else if (k === "pingo") {
    for (const x of [33, 53]) paint(ell(x, 87, 14, 7), 0xFFB547, 0xFFB547);
  }

  // ── Kroppen
  const body = bodyShape(k);
  if (style === "classic") {
    const g = ctx.createLinearGradient(30, 20, 70, 95);
    g.addColorStop(0, hex(S.body)); g.addColorStop(1, hex(S.shade));
    fill(body, g);
    fill(ell(26, 32, 18, 9), "rgba(255,255,255,0.35)");
  } else if (style === "visor") {
    const g = ctx.createLinearGradient(32, 18, 66, 98);
    g.addColorStop(0, hex(S.body)); g.addColorStop(0.65, hex(S.shade)); g.addColorStop(1, hex(0x1B1A22));
    fill(body, g);
    fill(ell(26, 30.5, 20, 9), "rgba(255,255,255,0.45)");
    fill(ell(41.8, 29.6, 4.4, 2.8), "rgba(255,255,255,0.7)");
  } else {
    const g = ctx.createLinearGradient(30, 20, 70, 95);
    g.addColorStop(0, hex(0x22202B)); g.addColorStop(1, hex(0x0C0B10));
    fill(body, g);
    const r = ctx.createRadialGradient(50, 40, 0, 50, 40, 45);
    r.addColorStop(0, hex(neon, 0.22)); r.addColorStop(1, hex(neon, 0));
    fill(body, r);
    glowStroke(outline(k), neon, 2.2);
  }

  // ── På kroppen
  const [eL, eR] = S.eyes;
  if (k === "fia") {
    paint(ell(32, 62, 36, 24), 0xFFF1E6);
    fill(ell(46.5, 64.5, 7, 5), hex(style === "neon" ? neon : INK));
  } else if (k === "misse") {
    const c = style === "neon" ? hex(neon) : hex(INK, 0.55);
    for (const flip of [false, true]) {
      const m = (x) => (flip ? 100 - x : x);
      const w = new Path2D();
      w.moveTo(m(31), 66); w.lineTo(m(15), 63);
      w.moveTo(m(31), 69); w.lineTo(m(15), 70);
      stroke(w, c, 1.4);
    }
    fill(tri([47, 64], [53, 64], [50, 67.5]), hex(style === "neon" ? neon : 0xE88AA6));
  } else if (k === "hubbe") {
    if (style === "classic") for (const e of [eL, eR]) fill(ell(e[0] - 12, e[1] - 12, 24, 24), hex(0xEAFBF6));
    if (style !== "neon") fill(ell(32, 64, 36, 26), "rgba(255,255,255,0.22)");
    else for (const e of [eL, eR]) stroke(ell(e[0] - 11, e[1] - 11, 22, 22), hex(neon, 0.6), 1.2);
    paint(tri([45.5, 59], [54.5, 59], [50, 67]), 0xFFB547, 0xFFB547, 1.3);
  } else if (k === "pingo") {
    paint(ell(29, 34, 42, 56), 0xF4F2EE, neon, 1.2, 0.7);
    paint(tri([45.5, 56], [54.5, 56], [50, 62]), 0xFFB547, 0xFFB547, 1.3);
  }

  // ── Framför: skott/blixt, flamma/lock, stjärna
  if (k === "pim") {
    const sway = state === "working" ? 8 * Math.sin(t * 6) : 3 * Math.sin(t * 1.5);
    const stem = new Path2D(); stem.moveTo(50, 26); stem.lineTo(50 + sway * 0.2, 15);
    const bx = 50 + sway * 0.2, by = 16;
    if (style === "visor") {
      stroke(stem, hex(0x1B1A22), 2.6);
      const bolt = new Path2D();
      [[-1, 1], [8, -12], [6, -5], [14, -7], [3, 6], [5, -1]].forEach(([x, y], i) =>
        i === 0 ? bolt.moveTo(bx + x, by + y) : bolt.lineTo(bx + x, by + y));
      bolt.closePath();
      fill(bolt, hex(0xC8F55A));
      stroke(bolt, hex(0x1B1A22), 1.2, "butt");
    } else {
      const leaf = new Path2D();
      leaf.moveTo(bx, by);
      leaf.quadraticCurveTo(bx + 4, by - 12, bx + 14, by - 8);
      leaf.quadraticCurveTo(bx + 12, by + 2, bx, by);
      if (style === "neon") { stroke(stem, hex(neon), 2.2); glowStroke(leaf, 0xB6F27A, 1.6); }
      else { stroke(stem, hex(S.shade), 2.5); fill(leaf, hex(0x73C759)); }
    }
  } else if (k === "oda") {
    if (style === "visor") {
      const flick = 1 + 0.06 * Math.sin(t * 9);
      const top = 1 + (1 - flick) * 10;
      const f = new Path2D();
      f.moveTo(50, top);
      f.bezierCurveTo(45, 8, 43, 13, 46, 20);
      f.bezierCurveTo(47, 15, 51, 13, 51, 8);
      f.bezierCurveTo(55, 12, 56, 16, 53, 21);
      f.bezierCurveTo(59, 17, 59, 9, 50, top);
      fill(f, hex(0xFFB547));
      const core = new Path2D();
      core.moveTo(50, 9);
      core.bezierCurveTo(47.5, 13, 47.5, 17, 50, 20.5);
      core.bezierCurveTo(52.5, 17, 52.5, 13, 50, 9);
      fill(core, hex(0xFFF0B3));
    } else {
      const curl = new Path2D(); curl.arc(55, 8, 5, Math.PI, Math.PI / 3, false);
      style === "neon" ? glowStroke(curl, neon, 2) : stroke(curl, hex(S.shade), 2.5);
    }
  } else if (k === "kix" && style === "visor") {
    const star = new Path2D();
    for (let i = 0; i < 10; i++) {
      const a = (i / 10) * 2 * Math.PI - Math.PI / 2, r = i % 2 === 0 ? 5 : 2.2;
      const x = 75 + r * Math.cos(a), y = 27 + r * Math.sin(a);
      i === 0 ? star.moveTo(x, y) : star.lineTo(x, y);
    }
    star.closePath();
    fill(star, `rgba(255,255,255,${0.4 + 0.5 * Math.max(0, Math.sin(t * 2))})`);
  }

  // ── Ansiktet
  const [mx, my] = S.mouth;
  const talking = state === "speaking" || (state === "listening" && level > 0.05);
  const drawMouth = (color, smirk) => {
    if (talking) { const h = 2 + level * 9; fill(ell(mx - 4.5, my - h / 2, 9, h), color); }
    else if (state === "needsApproval") fill(ell(mx - 3, my - 3, 6, 6), color);
    else if (yawning) fill(ell(mx - 4, my - 4, 8, 10), color);
    else if (mood === "stressed" && calm) stroke(quad(mx - 5, my, mx + 1, my + 1.5, mx + 5, my - 2), color, 2.5);
    else if (smirk && state !== "done" && !(mood === "proud" && calm)) stroke(quad(mx - 4, my + 1, mx + 1, my + 4, mx + 5, my - 1), color, 2.4);
    else {
      const smile = state === "done" || (mood === "proud" && calm) ? 6 : 3.5;
      stroke(quad(mx - 5, my - 1, mx, my - 1 + smile, mx + 5, my - 1), color, 2.5);
    }
  };
  let dx = 0;
  if (state === "working") dx = 3 * Math.sin(t * 1.5);
  if (state === "thinking") dx = 2.5;
  const big = state === "needsApproval" || state === "listening";

  if (style === "classic") {
    const lookY = state === "thinking" ? -3 : state === "working" ? 1 : 0;
    const wide = big ? 1.25 : 1;
    const lid = k === "hubbe" ? hex(0xEAFBF6) : k === "pingo" ? hex(0xF4F2EE) : hex(S.body);
    for (const e of [eL, eR]) {
      const cx = e[0] + dx, cy = e[1] + lookY;
      if (state === "done") { stroke(quad(cx - 5, cy + 2, cx, cy - 6, cx + 5, cy + 2), hex(INK), 3); continue; }
      if (blinking) { const p = new Path2D(); p.moveTo(cx - 4.5, cy); p.lineTo(cx + 4.5, cy); stroke(p, hex(INK), 2.5); continue; }
      const [w, h] = k === "oda" ? [8 * wide, 11 * wide] : [8.5 * wide, 8.5 * wide];
      fill(ell(cx - w / 2, cy - h / 2, w, h), hex(INK));
      fill(ell(cx - w / 2 + 1.5, cy - h / 2 + 1.2, 3, 3), "#fff");
      if (state === "idle" && (k === "bo" || mood === "sleepy")) {
        ctx.fillStyle = lid; ctx.fillRect(cx - w / 2 - 1, cy - h / 2 - 1, w + 2, h / 2 + 0.5);
      }
    }
    if (k !== "hubbe") for (const e of [eL, eR]) {
      const ddx = e[0] < 50 ? -8 : 8;
      fill(ell(e[0] + ddx - 5, e[1] + 7, 10, 5), hex(0xFF8C9E, k === "oda" ? 0.9 : 0.55));
    }
    if (k === "kix") for (const [x, y] of [[33, 60], [36, 63], [64, 60], [67, 63]]) fill(ell(x, y, 1.8, 1.8), hex(S.shade));
    drawMouth(hex(INK), false);
  } else if (style === "visor") {
    const bx = eL[0] - 12, by = eL[1] - 8, bw = eR[0] - eL[0] + 24, bh = 16;
    const g = ctx.createLinearGradient(0, by, 0, by + bh);
    g.addColorStop(0, hex(0x2A2833)); g.addColorStop(1, hex(0x0B0A0F));
    fill(rrect(bx, by, bw, bh, 8), g);
    fill(rrect(bx + 3, by + 2, bw - 6, 2.2, 1.1), "rgba(255,255,255,0.18)");
    const led = state === "needsApproval" ? 0xFF8A8A : S.led;
    const sleepy = mood === "sleepy" && state === "idle";
    for (const e of [eL, eR]) {
      const cx = e[0] + dx, cy = e[1] + (state === "thinking" ? -1 : 0);
      if (state === "done") { glowStroke(quad(cx - 4.5, cy + 1.5, cx, cy - 4.5, cx + 4.5, cy + 1.5), led, 2); continue; }
      const w = big ? 10 : 8;
      const h = blinking ? 1.4 : sleepy ? 2.4 : big ? 7 : 5;
      fill(rrect(cx - w / 2 - 3, cy - h / 2 - 3, w + 6, h + 6, (Math.min(w, h) + 6) / 2), hex(led, 0.18));
      fill(rrect(cx - w / 2, cy - h / 2, w, h, Math.min(w, h) / 2), hex(led));
    }
    drawMouth(hex(0x1B1A22), true);
  } else {
    for (const e of [eL, eR]) {
      const cx = e[0] + dx, cy = e[1] + (state === "thinking" ? -2 : 0);
      if (state === "done") { glowStroke(quad(cx - 5, cy + 2, cx, cy - 6, cx + 5, cy + 2), neon, 2.6); continue; }
      const w = big ? 8 : 6.5;
      const tall = k === "oda" ? 11 : 9.5;
      const h = blinking ? 1.6 : (mood === "sleepy" && state === "idle") ? tall * 0.45 : big ? tall * 1.2 : tall;
      fill(rrect(cx - w / 2 - 3, cy - h / 2 - 3, w + 6, h + 6, (Math.min(w, h) + 6) / 2), hex(neon, 0.18));
      fill(rrect(cx - w / 2, cy - h / 2, w, h, Math.min(w, h) / 2), hex(neon));
    }
    let p;
    if (talking) { const h = 2 + level * 9; p = ell(mx - 4.5, my - h / 2, 9, h); }
    else if (state === "needsApproval" || yawning) p = ell(mx - 3, my - 3, 6, 6);
    else {
      const smile = state === "done" || (mood === "proud" && calm) ? 6 : mood === "stressed" ? 0.5 : 4;
      p = quad(mx - 5, my - 1, mx, my - 1 + smile, mx + 5, my - 1);
    }
    glowStroke(p, neon, 2);
  }

  // ── Humör
  if (mood === "sleepy" && state === "idle") {
    for (let i = 0; i < 2; i++) {
      const ph = (t * 0.5 + i * 0.5) % 1;
      ctx.globalAlpha = 1 - ph;
      ctx.fillStyle = "rgba(255,255,255,0.85)";
      ctx.font = `bold ${9 + ph * 6}px "Segoe UI", system-ui, sans-serif`;
      ctx.textAlign = "center"; ctx.textBaseline = "middle";
      ctx.fillText("z", 84 + ph * 8, 26 - ph * 18);
    }
    ctx.globalAlpha = 1;
  } else if (mood === "stressed") {
    const y = 34 + ((t * 12) % 14);
    const d = new Path2D();
    d.moveTo(80, y - 7); d.quadraticCurveTo(87, y + 2, 80, y + 4); d.quadraticCurveTo(73, y + 2, 80, y - 7);
    fill(d, hex(0x8CCCFF, 0.95));
  } else if (mood === "proud" && calm) {
    [[18, 22], [84, 30], [74, 10]].forEach(([x, y], i) => {
      const a = Math.max(0, Math.sin(t * 3 + i * 2.1));
      if (a <= 0.2) return;
      const r = 2 + 3 * a, sp = new Path2D();
      sp.moveTo(x, y - r); sp.lineTo(x, y + r); sp.moveTo(x - r, y); sp.lineTo(x + r, y);
      stroke(sp, hex(0xFFD966, a), 1.8);
    });
  }

  if (state === "needsApproval") {
    fill(ell(76, 10, 20, 20), hex(0xE5484D));
    fill(rrect(84.5, 13.5, 3, 8, 1.5), "#fff");
    fill(ell(84.5, 23.5, 3, 3), "#fff");
  }
  ctx.restore();
}

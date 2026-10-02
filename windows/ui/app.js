// Tamanotchi för Windows: tillstånd, fraser och ön. Logiken följer Mac-versionen (SessionStore.swift).
import { drawMascot, SKINS, GANG, ANIMALS } from "./mascot.js";

// ───────────────────────── Brygga till Rust (Tauri) ─────────────────────────
const T = window.__TAURI__;
const invoke = (cmd, args) => (T ? T.core.invoke(cmd, args).catch((e) => console.warn(cmd, e)) : Promise.resolve(null));
const listen = (ev, fn) => (T ? T.event.listen(ev, (e) => fn(e.payload)) : window.addEventListener("tama:" + ev, (e) => fn(e.detail)));

const store = {
  get(key, fallback) { try { const v = localStorage.getItem("tamanotchi." + key); return v ? JSON.parse(v) : fallback; } catch { return fallback; } },
  set(key, value) { try { localStorage.setItem("tamanotchi." + key, JSON.stringify(value)); } catch {} },
};

// ───────────────────────── Inställningar ─────────────────────────
const cfg = Object.assign(
  { skin: "pim", style: "visor", eventStyle: "sounds", anchor: "top", autostart: true },
  store.get("config", {}),
);
const saveCfg = () => store.set("config", cfg);

// ───────────────────────── Tillstånd ─────────────────────────
const st = {
  sessions: new Map(),
  pending: [],             // { id, ev }
  bubble: null,
  speaking: false,
  justFinished: 0,
  completions: [],
  hovering: false,
  pinned: false,
  dismissed: false,
  view: "main",            // main | settings
  usage: store.get("usage", {}),   // { fiveHour, fiveReset, sevenDay, sevenReset } (reset i ms)
};

const now = () => Date.now();
const projectOf = (cwd) => (cwd || "").split(/[\\/]/).filter(Boolean).pop() || "";
const baseName = (p) => (p || "").split(/[\\/]/).pop() || "";

// ───────────────────────── Händelser från Claude Code ─────────────────────────
const ev = {
  summary(e) {
    const i = e.tool_input || {};
    switch (e.tool_name) {
      case "Bash": case "PowerShell": { const c = (i.command || "").trim(); return c.length > 80 ? c.slice(0, 80) + "…" : c; }
      case "Edit": case "Write": case "Read": case "MultiEdit": return `${e.tool_name} ${baseName(i.file_path)}`;
      case "WebFetch": return `Hämta ${i.url || "webbsida"}`;
      case "WebSearch": return `Sök: ${i.query || ""}`;
      default: return e.tool_name || "verktyg";
    }
  },
  short(e) {
    const t = e.tool_name || "";
    if (["Edit", "Write", "MultiEdit", "NotebookEdit"].includes(t)) return "Kodar";
    if (["Bash", "PowerShell"].includes(t)) return "Kör kommando";
    if (["Read", "Grep", "Glob", "LS"].includes(t)) return "Läser";
    if (["WebSearch", "WebFetch"].includes(t)) return "Söker";
    if (["Task", "Agent"].includes(t)) return "Delegerar";
    if (["TodoWrite", "TaskCreate", "TaskUpdate", "ExitPlanMode"].includes(t)) return "Planerar";
    if (t === "AskUserQuestion") return "Har en fråga";
    return t.startsWith("mcp__") ? "Använder verktyg" : "Jobbar";
  },
  detail(e) {
    const i = e.tool_input || {};
    switch (e.tool_name) {
      case "Edit": case "Write": case "MultiEdit": case "NotebookEdit": case "Read": return baseName(i.file_path || i.notebook_path) || null;
      case "Bash": case "PowerShell": return (i.command || "").trim().split(/\s+/)[0] || null;
      case "WebSearch": return i.query || null;
      default: return null;
    }
  },
  risky(e) {
    if (!["Bash", "PowerShell"].includes(e.tool_name)) return false;
    const c = (e.tool_input || {}).command || "";
    return /(\brm\b|\bsudo\b|git\s+push|git\s+reset\s+--hard|curl[^|]*\|\s*(ba|z)?sh|\bmkfs\b|\bdd\b|chmod\s+-R|>\s*\/dev\/|\bkill(all)?\b|Remove-Item|\brd\s+\/s|\bdel\s+\/|\bformat\b|Stop-Process|iwr[^|]*\|\s*iex|Invoke-Expression)/i.test(c);
  },
};

// ───────────────────────── Färdiga fraser (gratis, ingen AI) ─────────────────────────
const pick = (a) => a[Math.floor(Math.random() * a.length)];
const Narrator = {
  permission(e) {
    const project = projectOf(e.cwd) || "Claude";
    const i = e.tool_input || {};
    switch (e.tool_name) {
      case "Bash": case "PowerShell": return `${project} vill köra ${(i.command || "").split(/\s+/).slice(0, 3).join(" ")}. Godkänner du?`;
      case "Edit": case "Write": case "MultiEdit": return `${project} vill ändra ${baseName(i.file_path)}. Okej?`;
      case "WebFetch": return `${project} vill hämta en webbsida. Okej?`;
      default: return `${project} behöver ditt godkännande.`;
    }
  },
  doing(s) {
    const d = s.detail;
    switch (s.short) {
      case "Kodar": return d ? `skriver Claude kod i ${d}` : "skriver Claude kod";
      case "Kör kommando": return d ? `kör Claude ${d}` : "kör Claude ett kommando";
      case "Läser": return d ? `läser Claude ${d}` : "läser Claude filer";
      case "Söker": return d ? `söker Claude efter ${d}` : "söker Claude på webben";
      case "Delegerar": return "har Claude skickat iväg en hjälpreda";
      case "Planerar": return "planerar Claude";
      case "Har en fråga": return "har Claude en fråga till dig";
      case "Använder verktyg": return "använder Claude ett verktyg";
      case "Behöver dig": return "väntar Claude på ditt godkännande";
      default: return "tänker Claude";
    }
  },
  /** "skriver Claude kod" → "Claude skriver kod" */
  straight(s) {
    const v = Narrator.doing(s);
    if (v.startsWith("har Claude")) return "Claude har" + v.slice("har Claude".length);
    const p = v.split(" ");
    return p[1] === "Claude" ? ["Claude", p[0], ...p.slice(2)].join(" ") : v;
  },
  when(ms) {
    if (!ms) return "snart";
    const secs = (ms - now()) / 1000;
    if (secs <= 60) return "alldeles strax";
    if (secs < 3600) return `om ${Math.floor(secs / 60)} minuter`;
    const d = new Date(ms), hm = d.toLocaleTimeString("sv-SE", { hour: "2-digit", minute: "2-digit" });
    const today = new Date(), tomorrow = new Date(); tomorrow.setDate(today.getDate() + 1);
    if (d.toDateString() === today.toDateString()) return `klockan ${hm}`;
    if (d.toDateString() === tomorrow.toDateString()) return `i morgon klockan ${hm}`;
    return `på ${d.toLocaleDateString("sv-SE", { weekday: "long" })} klockan ${hm}`;
  },
  ago(ms) {
    const s = Math.floor((now() - ms) / 1000);
    if (s < 60) return "nyss";
    if (s < 120) return "för en minut sedan";
    if (s < 3600) return `för ${Math.floor(s / 60)} minuter sedan`;
    if (s < 7200) return "för en timme sedan";
    return `för ${Math.floor(s / 3600)} timmar sedan`;
  },
  moodOpener(m) {
    if (Math.random() < 0.5) return null;
    const h = new Date().getHours();
    if (m === "sleepy") return h < 12 ? pick(["Gääsp… god morgon.", "Morgon. Kaffe först?"]) : pick(["Det börjar bli sent…", "Gääsp. Sent ikväll, va?"]);
    if (m === "proud") return pick(["Vilken fart idag!", "Det flyter på!"]);
    if (m === "stressed") return pick(["Oj, nu börjar det bli trångt.", "Puh, vi närmar oss gränsen."]);
    return null;
  },
  firstSentence(text) {
    let t = (text || "").replace(/```[\s\S]*?```/g, " ").replace(/[*_`#>|]/g, "").replace(/\s+/g, " ").trim();
    if (!t) return null;
    const m = t.match(/[.!?](\s|$)/);
    if (m) t = t.slice(0, m.index + 1);
    return t.length > 160 ? t.slice(0, 157) + "…" : t;
  },
  done: (p) => pick([`Klart i ${p}!`, `${p} är färdigt.`, `Nu är ${p} klart.`]),
};

// ───────────────────────── Härledda värden ─────────────────────────
function mascotState() {
  if (st.pending.length) return "needsApproval";
  if (st.speaking) return "speaking";
  if ([...st.sessions.values()].some((s) => s.working)) return "working";
  if (now() - st.justFinished < 6000) return "done";
  return "idle";
}
function primarySession() {
  if (st.pending.length) { const s = st.sessions.get(st.pending[0].ev.session_id); if (s) return s; }
  const all = [...st.sessions.values()].sort((a, b) => b.updated - a.updated);
  return all.find((s) => s.working) || all.find((s) => now() - s.updated < 600000) || null;
}
const primarySkin = () => primarySession()?.skin || cfg.skin;
function stateFor(s) {
  if (st.pending.some((p) => p.ev.session_id === s.id)) return "needsApproval";
  if (s.working) return s.short === "Tänker…" ? "thinking" : "working";
  if (s.short === "Klar" && now() - s.updated < 6000) return "done";
  return "idle";
}
function mood() {
  const u = st.usage;
  if ((u.fiveHour || 0) >= 90 || (u.sevenDay || 0) >= 95) return "stressed";
  if (st.completions.filter((t) => now() - t < 90 * 60000).length >= 4) return "proud";
  const h = new Date().getHours();
  return h < 8 || h >= 23 ? "sleepy" : "normal";
}
const expanded = () => st.hovering || st.pinned || (!st.dismissed && (st.pending.length > 0 || st.bubble != null));
function shortStatus() {
  if (st.pending.length) return "Behöver dig";
  if (st.speaking) return "Pratar";
  const w = [...st.sessions.values()].filter((s) => s.working).sort((a, b) => b.updated - a.updated)[0];
  if (w) return w.short || "Jobbar";
  if (now() - st.justFinished < 6000) return "Klar!";
  return null;
}
const familyOrder = () => {
  const pref = cfg.skin, animal = ANIMALS.includes(pref);
  const fam = animal ? ANIMALS : GANG, other = animal ? GANG : ANIMALS;
  return [pref, ...fam.filter((k) => k !== pref), ...other];
};
function nextSkin() {
  const used = new Set([...st.sessions.values()].map((s) => s.skin));
  const order = familyOrder();
  return order.find((k) => !used.has(k)) || order[st.sessions.size % order.length];
}
function reassignSkins() {
  const order = familyOrder();
  const ids = [...st.sessions.values()].sort((a, b) => b.updated - a.updated).map((s) => s.id);
  const p = primarySession()?.id;
  if (p) { ids.splice(ids.indexOf(p), 1); ids.unshift(p); }
  ids.forEach((id, i) => { st.sessions.get(id).skin = order[i % order.length]; });
}

// ───────────────────────── Hook-händelser ─────────────────────────
function handle(e) {
  const name = e.hook_event_name;
  if (name === "StatusLine") return usageFromStatusLine(e);
  const id = e.session_id || "okänd";
  let s = st.sessions.get(id);
  if (!s) s = { id, project: projectOf(e.cwd), cwd: e.cwd || "", activity: "", short: "", detail: null, working: false, updated: now(), skin: nextSkin(), app: null, lastMessage: null };
  s.updated = now();
  if (e.tamanotchi_app) s.app = e.tamanotchi_app;
  if (e.cwd) { s.cwd = e.cwd; s.project = projectOf(e.cwd); }

  // Ny aktivitet i sessionen: en fråga som fortfarande syns är redan besvarad någon annanstans
  if (name !== "PermissionRequest" && name !== "Notification") {
    st.pending = st.pending.filter((p) => p.ev.session_id !== id);
  }

  switch (name) {
    case "SessionStart": s.activity = ""; s.short = "Redo"; break;
    case "UserPromptSubmit": s.activity = ""; s.short = "Tänker…"; s.working = true; break;
    case "PreToolUse": s.activity = ev.summary(e); s.short = ev.short(e); s.detail = ev.detail(e); s.working = true; break;
    case "PostToolUse": case "PostToolUseFailure": s.short = "Tänker…"; s.detail = null; s.working = true; break;
    case "PermissionRequest":
      s.activity = ev.summary(e); s.short = "Behöver dig";
      if (e.tamanotchi_id != null) {
        st.pending.push({ id: e.tamanotchi_id, ev: e });
        st.dismissed = false;
        announce(Narrator.permission(e), "ping");
      }
      break;
    case "Notification":
      if (e.notification_type === "idle_prompt") {
        s.working = false; s.short = "Väntar på dig";
        announce(`${s.project} väntar på dig.`, "pop");
      }
      break;
    case "Stop": {
      s.working = false; s.short = "Klar"; s.activity = "";
      const m = (e.last_assistant_message || "").trim();
      if (m) s.lastMessage = m.slice(0, 4000);
      st.justFinished = now();
      st.completions = [...st.completions.filter((t) => now() - t < 3 * 3600000), now()];
      announce(Narrator.done(s.project), "glass");
      setTimeout(render, 6500);
      break;
    }
    case "SessionEnd": st.sessions.delete(id); render(); return;
  }
  st.sessions.set(id, s);
  render();
}

// ───────────────────────── Godkännanden ─────────────────────────
function decide(p, kind) {
  let reply = "";
  if (kind === "allow") reply = JSON.stringify({ hookSpecificOutput: { hookEventName: "PermissionRequest", decision: { behavior: "allow" } } });
  if (kind === "deny") reply = JSON.stringify({ hookSpecificOutput: { hookEventName: "PermissionRequest", decision: { behavior: "deny", message: "Nekat från Tamanotchi" } } });
  invoke("decide", { id: p.id, reply });
  st.pending = st.pending.filter((x) => x.id !== p.id);
  const s = st.sessions.get(p.ev.session_id);
  if (s && kind !== "pass") s.short = kind === "allow" ? ev.short(p.ev) : "Tänker…";
  if (!st.pending.length && kind !== "pass") st.dismissed = !st.pinned && !st.hovering;
  render();
}

// ───────────────────────── Användning (5 timmar / vecka) ─────────────────────────
function parseDate(v) {
  if (v == null) return null;
  if (typeof v === "number") return v < 1e12 ? v * 1000 : v;
  const t = Date.parse(String(v).replace(/(\.\d{3})\d+/, "$1"));
  return isNaN(t) ? null : t;
}
function usageFromStatusLine(e) {
  const rl = e.rate_limits; if (!rl) return;
  const u = { ...st.usage };
  if (rl.five_hour?.used_percentage != null) { u.fiveHour = +rl.five_hour.used_percentage; u.fiveReset = parseDate(rl.five_hour.resets_at); }
  if (rl.seven_day?.used_percentage != null) { u.sevenDay = +rl.seven_day.used_percentage; u.sevenReset = parseDate(rl.seven_day.resets_at); }
  setUsage(u);
}
function usageFromPoll(j) {
  const u = { ...st.usage };
  if (j?.five_hour?.utilization != null) { u.fiveHour = +j.five_hour.utilization; u.fiveReset = parseDate(j.five_hour.resets_at); }
  if (j?.seven_day?.utilization != null) { u.sevenDay = +j.seven_day.utilization; u.sevenReset = parseDate(j.seven_day.resets_at); }
  setUsage(u);
}
function dropExpired(u) {
  if (u.fiveReset && u.fiveReset < now()) { u.fiveHour = 0; u.fiveReset = null; }
  if (u.sevenReset && u.sevenReset < now()) { u.sevenDay = 0; u.sevenReset = null; }
  return u;
}
function setUsage(u) {
  dropExpired(u);
  if (JSON.stringify(u) === JSON.stringify(st.usage)) return;
  st.usage = u; store.set("usage", u);
  warnIfNeeded(u); render();
}
function once(key, reset) {
  const id = reset ? String(Math.floor(reset / 60000)) : "okänd";
  const seen = store.get("warned", {});
  if (seen[key] === id) return false;
  seen[key] = id; store.set("warned", seen);
  return true;
}
function warnIfNeeded(u) {
  const lines = [];
  const f = u.fiveHour, w = u.sevenDay;
  if (f != null) {
    if (f >= 100 && once("5h-100", u.fiveReset)) lines.push(`Nu är femtimmarsgränsen nådd. Du kan köra igen ${Narrator.when(u.fiveReset)}.`);
    else if (f >= 80 && f < 100 && once("5h-80", u.fiveReset)) lines.push(`Du har använt ${Math.round(f)} procent av femtimmarsgränsen. Den nollställs ${Narrator.when(u.fiveReset)}.`);
  }
  if (w != null) {
    if (w >= 100 && once("7d-100", u.sevenReset)) lines.push(`Veckogränsen är nådd. Den nollställs ${Narrator.when(u.sevenReset)}.`);
    else if (w >= 90 && w < 100 && once("7d-90", u.sevenReset)) lines.push(`Veckan ligger på ${Math.round(w)} procent. Den nollställs ${Narrator.when(u.sevenReset)}.`);
  }
  if (lines.length) announce(lines.join(" "), "funk", true);
}
function usageSentence(onlyIfHigh) {
  const u = st.usage; if (u.fiveHour == null) return null;
  if (onlyIfHigh && u.fiveHour < 70 && (u.sevenDay || 0) < 80) return null;
  let s = `Du har använt ${Math.round(u.fiveHour)} procent av femtimmarsgränsen`;
  if (u.fiveReset) {
    const mins = Math.floor((u.fiveReset - now()) / 60000);
    if (mins > 0) s += mins < 60 ? `, den nollställs om ${mins} minuter` : `, den nollställs om ${Math.floor(mins / 60)} timmar och ${mins % 60} minuter`;
  }
  s += ".";
  if (u.sevenDay != null) s += ` Veckan ligger på ${Math.round(u.sevenDay)} procent.`;
  return s;
}
const meterColor = (p) => (p >= 90 ? "#FF7A6B" : p >= 70 ? "#FFC73D" : "#5ED6A8");
function resetText(ms) {
  if (!ms) return "";
  const secs = (ms - now()) / 1000;
  if (secs <= 0) return "nollställs nu";
  if (secs < 3600) return `om ${Math.floor(secs / 60)} min`;
  const d = new Date(ms);
  const hm = d.toLocaleTimeString("sv-SE", { hour: "2-digit", minute: "2-digit" });
  if (secs < 86400) return `kl ${hm}`;
  return `${d.toLocaleDateString("sv-SE", { weekday: "short" })} ${hm}`;
}

// ───────────────────────── Det Tamanotchi säger när du klickar ─────────────────────────
function spokenStatus() {
  const parts = [];
  if (st.pending.length) parts.push(Narrator.permission(st.pending[0].ev));
  const sorted = [...st.sessions.values()].sort((a, b) => b.updated - a.updated);
  const many = st.sessions.size > 1;
  const working = sorted.filter((s) => s.working);
  for (const s of working.slice(0, 2)) {
    parts.push(many ? `${SKINS[s.skin].name} i ${s.project}: ${Narrator.straight(s)} just nu.` : `I ${s.project} ${Narrator.doing(s)} just nu.`);
  }
  if (!parts.length && sorted[0]) {
    const s = sorted[0];
    let line = s.short === "Väntar på dig" ? `${s.project} väntar på dig, ${Narrator.ago(s.updated)}.` : `${s.project} blev klart ${Narrator.ago(s.updated)}.`;
    const first = s.lastMessage && Narrator.firstSentence(s.lastMessage);
    if (first) line += ` Claude sa: ${first}`;
    parts.push(line);
  }
  if (working.length > 2) parts.push(`Och ${working.length - 2} till jobbar.`);
  const u = usageSentence(parts.length > 0); if (u) parts.push(u);
  if (!parts.length) parts.push(pick(["Det är lugnt just nu. Inga sessioner är igång.", "Allt är tyst. Claude vilar.", "Inget på gång just nu."]));
  const m = Narrator.moodOpener(mood()); if (m) parts.unshift(m);
  return parts.join(" ");
}

// ───────────────────────── Ljud och röst (gratis, inbyggt i Windows) ─────────────────────────
let audio;
function chime(kind) {
  try {
    audio = audio || new AudioContext();
    if (audio.state === "suspended") audio.resume();
    const notes = {
      ping: [[880, 0], [1318.5, 0.09]],
      pop: [[740, 0]],
      glass: [[1046.5, 0], [1318.5, 0.07], [1568, 0.14]],
      funk: [[392, 0], [311, 0.13]],
    }[kind] || [[880, 0]];
    const t0 = audio.currentTime + 0.01;
    for (const [f, dt] of notes) {
      const o = audio.createOscillator(), g = audio.createGain();
      o.type = kind === "funk" ? "triangle" : "sine";
      o.frequency.value = f;
      g.gain.setValueAtTime(0, t0 + dt);
      g.gain.linearRampToValueAtTime(0.16, t0 + dt + 0.006);
      g.gain.exponentialRampToValueAtTime(0.0008, t0 + dt + 0.45);
      o.connect(g).connect(audio.destination);
      o.start(t0 + dt); o.stop(t0 + dt + 0.5);
    }
  } catch (e) { console.warn("ljud", e); }
}

function swedishVoice() {
  const vs = window.speechSynthesis?.getVoices() || [];
  const sv = vs.filter((v) => /^sv/i.test(v.lang));
  return sv.find((v) => /natural/i.test(v.name)) || sv[0] || null;
}
let speechTimer;
function say(text) {
  stopSpeech();
  st.speaking = true;
  showBubble(text, 60);
  const finish = () => { if (!st.speaking) return; st.speaking = false; clearTimeout(speechTimer); hideBubbleSoon(text); render(); };
  speechTimer = setTimeout(finish, 4000 + text.length * 120);   // säkerhetsnät
  const fallback = () => { invoke("speak", { text }); };
  if (!window.speechSynthesis) { fallback(); return; }
  const u = new SpeechSynthesisUtterance(text);
  u.lang = "sv-SE";
  const v = swedishVoice(); if (v) u.voice = v;
  u.rate = 1.02; u.pitch = 1.08;
  u.onend = finish;
  u.onerror = (e) => { if (e.error === "not-allowed" || e.error === "synthesis-failed" || e.error === "audio-busy") fallback(); else finish(); };
  speechSynthesis.speak(u);
  render();
}
function stopSpeech() {
  try { window.speechSynthesis?.cancel(); } catch {}
  invoke("stop_speaking");
  if (st.speaking) { st.speaking = false; clearTimeout(speechTimer); }
}
function announce(text, sound, important = false) {
  if (cfg.eventStyle === "voice") say(text);
  else if (cfg.eventStyle === "silent") { if (important) showBubble(text, 12); }
  else { chime(sound); if (important) showBubble(text, 12); }
}
let bubbleTimer;
function showBubble(text, seconds = 8) {
  st.dismissed = false; st.bubble = text;
  clearTimeout(bubbleTimer);
  bubbleTimer = setTimeout(() => { if (st.bubble === text && !st.speaking) { st.bubble = null; render(); } }, seconds * 1000);
  render();
}
function hideBubbleSoon(text) {
  clearTimeout(bubbleTimer);
  bubbleTimer = setTimeout(() => { if (st.bubble === text && !st.speaking) { st.bubble = null; render(); } }, 2500);
}
function poke() {
  if (st.speaking) { stopSpeech(); st.bubble = null; render(); return; }
  say(spokenStatus());
}

// ───────────────────────── Ritning av ön ─────────────────────────
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const mascot = (size, attrs) =>
  `<canvas class="mascot" width="${size}" height="${size}" style="width:${size}px;height:${size}px" ${Object.entries(attrs).map(([k, v]) => `data-${k}="${esc(v)}"`).join(" ")}></canvas>`;
const ICON = {
  up: `<svg width="12" height="12" viewBox="0 0 12 12"><path d="M2.5 7.5 6 4l3.5 3.5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  pin: (on) => `<svg width="13" height="13" viewBox="0 0 16 16"><path d="M9.5 1.5 14.5 6.5l-2 .6-2.6 2.6.4 3.3-1.2 1.2L6.3 11.4 2.5 15.2l-.7-.7L5.6 10.7 2.8 7.9 4 6.7l3.3.4L9.9 4.5z" fill="${on ? "currentColor" : "none"}" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/></svg>`,
  gear: `<svg width="14" height="14" viewBox="0 0 16 16"><circle cx="8" cy="8" r="2.3" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M8 1.5v2M8 12.5v2M14.5 8h-2M3.5 8h-2M12.6 3.4l-1.4 1.4M4.8 11.2l-1.4 1.4M12.6 12.6l-1.4-1.4M4.8 4.8 3.4 3.4" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>`,
  back: `<svg width="12" height="12" viewBox="0 0 12 12"><path d="M7.5 2.5 4 6l3.5 3.5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  jump: `<svg width="10" height="10" viewBox="0 0 10 10"><path d="M3.5 1.5h5v5M8.5 1.5 2 8" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/></svg>`,
};
const relShort = (ms) => {
  const s = Math.floor((now() - ms) / 1000);
  if (s < 45) return "nyss";
  if (s < 3600) return `${Math.max(1, Math.round(s / 60))} min`;
  return `${Math.floor(s / 3600)} tim`;
};
const statusColor = (state) =>
  ({ needsApproval: "#FF8C80", working: "#8CB8FF", thinking: "#8CB8FF", done: "#5ED6A8" }[state] || "rgba(255,255,255,0.75)");
const dotColor = (state) =>
  ({ needsApproval: "#E5484D", working: "#3B82F6", thinking: "#3B82F6", done: "#5ED6A8", speaking: "#A88CFF" }[state] || "rgba(160,160,170,0.55)");

function collapsedHTML() {
  const state = mascotState(), label = shortStatus();
  const pct = st.usage.fiveHour;
  const ring = pct != null
    ? `<circle cx="8" cy="8" r="6.5" fill="none" stroke="rgba(255,255,255,0.15)" stroke-width="2"/>
       <circle cx="8" cy="8" r="6.5" fill="none" stroke="${meterColor(pct)}" stroke-width="2" stroke-linecap="round"
         stroke-dasharray="${(Math.min(100, pct) / 100) * 40.84} 41" transform="rotate(-90 8 8)"/>`
    : "";
  return `${mascot(26, { role: "primary" })}
    ${label ? `<span class="label" style="color:${statusColor(state)}">${esc(label)}</span>` : ""}
    <span class="dot" title="${pct != null ? Math.round(pct) + " % av 5-timmarsgränsen använd" : ""}">
      <svg width="16" height="16" viewBox="0 0 16 16">${ring}<circle cx="8" cy="8" r="3.5" fill="${dotColor(state)}"/></svg>
    </span>`;
}

function approvalHTML(p) {
  const e = p.ev, project = projectOf(e.cwd) || "Godkännande";
  const s = st.sessions.get(e.session_id);
  const where = s?.app === "vscode" ? "I VS Code" : "Svara där";
  return `<div class="eyebrow">${esc(project)}</div>
    <div class="mono">${esc(ev.summary(e))}</div>
    <div class="pills">
      <button class="pill allow" data-act="allow">Tillåt</button>
      <button class="pill deny" data-act="deny">Neka</button>
      <button class="pill neutral" data-act="pass" title="Låt Claude Code fråga som vanligt">${where}</button>
    </div>
    ${st.pending.length > 1 ? `<div class="sub">${st.pending.length - 1} till väntar efter den här.</div>` : ""}
    ${ev.risky(e) ? `<div class="warn">Känsligt kommando – titta noga innan du tillåter.</div>` : ""}`;
}

function sessionsHTML() {
  const list = [...st.sessions.values()].sort((a, b) => b.updated - a.updated);
  if (!list.length) {
    return `<div class="title">Inga Claude Code-sessioner just nu.</div>
      <div class="sub">Starta Claude Code i VS Code så dyker de upp här. Klicka på mig så berättar jag läget.</div>`;
  }
  const rows = list.slice(0, 3).map((s) => `
    <button class="session" data-jump="${esc(s.id)}" title="Öppna ${esc(s.project)}${s.app === "vscode" ? " i VS Code" : ""}">
      ${mascot(22, { skin: s.skin, state: stateFor(s) })}
      <div class="info">
        <div class="top"><span class="project">${esc(s.project || "Claude")}</span><span class="short">${esc(s.short)}</span>
          <span class="ago">${relShort(s.updated)}</span><span style="opacity:.45">${ICON.jump}</span></div>
        ${s.working && s.activity && s.activity !== s.short ? `<div class="activity">${esc(s.activity)}</div>` : ""}
      </div>
    </button>`).join("");
  const last = list.find((s) => s.lastMessage);
  const reply = last ? `<div class="reply"><div class="eyebrow" style="font-size:10px">Senaste svaret · ${esc(last.project)}</div>
      <div class="text">${esc(last.lastMessage)}</div></div>` : "";
  return `<div class="sessions">${rows}</div>${reply}`;
}

function usageHTML() {
  const u = st.usage;
  if (u.fiveHour == null && u.sevenDay == null) return "";
  const bar = (title, p, reset) => p == null ? "" : `
    <div class="meter"><div class="head"><span>${title}</span><b>${Math.round(p)} %</b><i>${resetText(reset)}</i></div>
    <div class="bar"><div style="width:${Math.min(100, p)}%;background:${meterColor(p)}"></div></div></div>`;
  return `<div class="usage">${bar("5 tim", u.fiveHour, u.fiveReset)}${bar("Vecka", u.sevenDay, u.sevenReset)}</div>`;
}

function settingsHTML() {
  const seg = (key, opts) => `<div class="seg">${opts.map(([v, l]) =>
    `<button data-set="${key}" data-val="${v}" class="${cfg[key] === v ? "on" : ""}">${l}</button>`).join("")}</div>`;
  const skinBtn = (k) => `<button class="skin ${cfg.skin === k ? "on" : ""}" data-skin="${k}" title="${SKINS[k].name} – ${SKINS[k].desc}">
      ${mascot(34, { skin: k, state: "idle" })}${SKINS[k].name}</button>`;
  const hasSv = !!swedishVoice();
  return `<div class="settings">
    <div class="head"><button class="icon-btn" data-act="back" title="Tillbaka" aria-label="Tillbaka">${ICON.back}</button><h2>Inställningar</h2></div>
    <div class="group"><div class="eyebrow">Karaktär</div>
      <div class="skins">${[...GANG, ...ANIMALS].map(skinBtn).join("")}</div></div>
    <div class="group"><div class="eyebrow">Stil</div>${seg("style", [["visor", "Visir"], ["neon", "Neon"], ["classic", "Klassisk"]])}</div>
    <div class="group"><div class="eyebrow">När något händer</div>${seg("eventStyle", [["sounds", "Ljud"], ["voice", "Röst"], ["silent", "Tyst"]])}</div>
    <div class="group"><div class="eyebrow">Placering</div>${seg("anchor", [["top", "Uppe i mitten"], ["corner", "Nere vid klockan"]])}</div>
    <div class="toggle-row"><span>Starta med Windows</span><button class="switch ${cfg.autostart ? "on" : ""}" data-act="autostart" role="switch" aria-checked="${cfg.autostart}" aria-label="Starta med Windows"></button></div>
    <div class="toggle-row"><button class="link" data-act="testvoice">Testa rösten</button>
      <span class="hint">${hasSv ? "Svensk röst: " + esc(swedishVoice().name.replace(/^Microsoft\s*/, "").split(/\s[-–]/)[0]) : "Ingen svensk röst hittad"}</span></div>
    ${hasSv ? "" : `<div class="hint">Lägg till en svensk röst: Inställningar → Tid och språk → Tal → Lägg till röster → Svenska. Starta sedan om Tamanotchi.</div>`}
  </div>`;
}

function expandedHTML() {
  if (st.view === "settings") return settingsHTML();
  const p = st.pending[0];
  const main = p ? approvalHTML(p)
    : st.bubble ? `<div class="bubble">${esc(st.bubble)}</div>`
    : sessionsHTML();
  return `<div class="row">
      <button class="poke" data-act="poke" title="Klicka så berättar jag vad som händer" aria-label="Berätta läget">${mascot(56, { role: "primary" })}</button>
      <div class="main">${main}</div>
      <div class="side">
        <button class="icon-btn" data-act="collapse" title="Fäll ihop" aria-label="Fäll ihop">${ICON.up}</button>
        <button class="icon-btn ${st.pinned ? "on" : ""}" data-act="pin" title="${st.pinned ? "Släpp" : "Håll öppen"}" aria-label="Håll öppen">${ICON.pin(st.pinned)}</button>
        <button class="icon-btn" data-act="settings" title="Inställningar" aria-label="Inställningar">${ICON.gear}</button>
      </div>
    </div>${usageHTML()}`;
}

let lastOpen = null;
function render() {
  const open = expanded();
  if (!open && st.view === "settings") st.view = "main";
  $("collapsed").innerHTML = collapsedHTML();
  $("expanded").innerHTML = open ? expandedHTML() : "";
  const island = $("island");
  island.classList.toggle("open", open);
  const target = open ? $("expanded") : $("collapsed");
  island.style.width = target.offsetWidth + "px";
  island.style.height = (open ? target.offsetHeight : 34) + "px";
  if (open !== lastOpen) { lastOpen = open; }
}

// Klick i ön
$("island").addEventListener("click", (e) => {
  const b = e.target.closest("button, .collapsed");
  if (!b) return;
  if (b.classList.contains("collapsed")) return poke();
  const act = b.dataset.act;
  if (act === "allow" || act === "deny" || act === "pass") { if (st.pending[0]) decide(st.pending[0], act); return; }
  if (act === "poke") return poke();
  if (act === "collapse") { st.pinned = false; st.hovering = false; st.dismissed = true; st.bubble = null; st.view = "main"; return render(); }
  if (act === "pin") { st.pinned = !st.pinned; if (st.pinned) st.dismissed = false; return render(); }
  if (act === "settings") { st.view = "settings"; st.pinned = true; return render(); }
  if (act === "back") { st.view = "main"; return render(); }
  if (act === "autostart") { cfg.autostart = !cfg.autostart; saveCfg(); invoke("set_autostart", { on: cfg.autostart }); return render(); }
  if (act === "testvoice") return say("Hej! Jag är Tamanotchi. Så här låter jag.");
  if (b.dataset.skin) { cfg.skin = b.dataset.skin; saveCfg(); reassignSkins(); return render(); }
  if (b.dataset.set) {
    cfg[b.dataset.set] = b.dataset.val; saveCfg();
    if (b.dataset.set === "anchor") place();
    if (b.dataset.set === "eventStyle" && b.dataset.val === "sounds") chime("pop");
    return render();
  }
  if (b.dataset.jump) {
    const s = st.sessions.get(b.dataset.jump);
    if (s) invoke("jump", { cwd: s.cwd, app: s.app || "" });
  }
});

// ───────────────────────── Animation och klickbar yta ─────────────────────────
let lastHit = "";
function frame(ts) {
  const t = ts / 1000;
  const state = mascotState(), m = mood();
  const level = st.speaking ? 0.25 + 0.55 * Math.abs(Math.sin(t * 13)) * (0.6 + 0.4 * Math.sin(t * 3.1)) : 0;
  const dpr = window.devicePixelRatio || 1;
  for (const c of document.querySelectorAll("canvas.mascot")) {
    const css = parseFloat(c.style.width), px = Math.round(css * dpr);
    if (c.width !== px) { c.width = px; c.height = px; }
    const primary = c.dataset.role === "primary";
    drawMascot(c.getContext("2d"), px, {
      skin: primary ? primarySkin() : c.dataset.skin,
      state: primary ? state : c.dataset.state,
      level: primary ? level : 0, mood: m, style: cfg.style, t,
    });
  }
  // Berätta för Rust var ön är, så att klick utanför går rakt igenom till fönstren under
  const r = $("island").getBoundingClientRect();
  const hit = [r.left, r.top, r.width, r.height].map((v) => Math.round(v)).join(",");
  if (hit !== lastHit) { lastHit = hit; invoke("set_hit", { x: r.left, y: r.top, w: r.width, h: r.height }); }
  requestAnimationFrame(frame);
}

// Musen över ön (Rust känner av det, eftersom fönstret annars släpper igenom musen)
let hoverTimer;
function setInside(inside) {
  clearTimeout(hoverTimer);
  hoverTimer = setTimeout(() => {
    if (st.hovering === inside) return;
    st.hovering = inside;
    if (inside) st.dismissed = false;
    render();
  }, inside ? 120 : 380);
}

// ───────────────────────── Placering ─────────────────────────
const WIN = { w: 480, h: 500 };
function place() {
  document.body.classList.toggle("anchor-bottom", cfg.anchor === "corner");
  const s = window.screen;
  const left = s.availLeft ?? 0, top = s.availTop ?? 0;
  const x = cfg.anchor === "corner" ? left + s.availWidth - WIN.w : left + (s.availWidth - WIN.w) / 2;
  const y = cfg.anchor === "corner" ? top + s.availHeight - WIN.h : top;
  invoke("place", { x: Math.round(x), y: Math.round(y) });
}

// ───────────────────────── Start ─────────────────────────
listen("hook", handle);
listen("hook-closed", (id) => { st.pending = st.pending.filter((p) => p.id !== id); render(); });
listen("cursor", setInside);
listen("usage", usageFromPoll);
listen("speech-end", () => { if (st.speaking) { st.speaking = false; clearTimeout(speechTimer); hideBubbleSoon(st.bubble); render(); } });
listen("show", (what) => { st.pinned = true; st.dismissed = false; if (what === "settings") st.view = "settings"; render(); });
window.speechSynthesis?.addEventListener?.("voiceschanged", () => { if (st.view === "settings") render(); });

// Sessioner som varit tysta länge räknas inte längre som aktiva; humöret och tiderna uppdateras
setInterval(() => {
  for (const s of st.sessions.values()) if (s.working && now() - s.updated > 15 * 60000) { s.working = false; s.short = "Tyst"; }
  for (const [id, s] of st.sessions) if (!s.working && now() - s.updated > 6 * 3600000) st.sessions.delete(id);
  const u = dropExpired({ ...st.usage }); if (JSON.stringify(u) !== JSON.stringify(st.usage)) { st.usage = u; store.set("usage", u); }
  if (!document.querySelector(".island:hover")) render();
}, 15000);

render();
place();
invoke("ready", { autostart: cfg.autostart });
requestAnimationFrame(frame);

// För förhandsvisning och test i vanlig webbläsare
window.tamanotchi = { st, cfg, handle, render, usageFromPoll, setInside, say, place };

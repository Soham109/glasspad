import { clamp, lerp, minJerk, reducedMotion, nextFrame, sleep } from "./spring";

/* Recreations of the iPhone app's own screens (Apps/iOS/Sources/Modes), drawn in iPhone points. */

const reduce = reducedMotion();
const svg = (body: string, vb = "0 0 24 24") => `<svg viewBox="${vb}">${body}</svg>`;
const G = {
  compass: '<circle cx="12" cy="12" r="8"/><path d="m15.5 8.5-4.8 2.2-2.2 4.8 4.8-2.2Z"/>',
  camera: '<path d="M4 8.5h3l1.6-2h6.8l1.6 2h3V18H4Z"/><circle cx="12" cy="13" r="3"/>',
  moon: '<path d="M19 14.5A7.5 7.5 0 0 1 9.5 5a7.5 7.5 0 1 0 9.5 9.5Z"/>',
  link: '<path d="M10 14a4 4 0 0 0 5.7 0l2.8-2.8a4 4 0 0 0-5.7-5.7L11.5 6.8"/><path d="M14 10a4 4 0 0 0-5.7 0l-2.8 2.8a4 4 0 0 0 5.7 5.7l1.3-1.3"/>',
  lock: '<rect x="5" y="10.5" width="14" height="9.5" rx="2.5"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5"/>',
  hammer: '<path d="m13 7 4 4M5 19l8.5-8.5M12 4.5l3-1.5 5 5-1.5 3-1.5-1.5-3 3-4-4 3-3Z"/>',
  window: '<rect x="4" y="5" width="16" height="14" rx="2.5"/><path d="M4 9h16M9.5 14h5"/>',
  undo: '<path d="M9 7 5 11l4 4"/><path d="M5 11h9a5 5 0 0 1 0 10h-2"/>',
  reader: '<path d="M6 4h9l3 3v13H6Z"/><path d="M9 11h6M9 14h6M9 17h4"/>',
  note: '<rect x="5" y="4" width="14" height="16" rx="2.5"/><path d="M9 9h6M9 12.5h6"/>',
  down: '<circle cx="12" cy="12" r="8"/><path d="M12 8v7M9 12.5l3 3 3-3"/>',
  toMac: '<rect x="3" y="5" width="7" height="13" rx="1.6"/><path d="M13 11.5h7M17 8.5l3 3-3 3"/>',
  fromMac: '<rect x="3" y="5" width="18" height="11" rx="1.6"/><path d="M1.5 19h21M12 8v5M9.5 10.5 12 13l2.5-2.5"/>',
  wave: '<path d="M8.5 8.5a5 5 0 0 0 0 7M15.5 8.5a5 5 0 0 1 0 7M6 6a8.5 8.5 0 0 0 0 12M18 6a8.5 8.5 0 0 1 0 12"/><circle cx="12" cy="12" r="1.2"/>',
  speaker: '<path d="M4 10v4h3l4 3.5v-11L7 10Z"/><path d="M15 9.5a3.5 3.5 0 0 1 0 5"/>',
};

const DOCK_APPS: [string, string, string, boolean][] = [
  ["finder", "Finder", '<path d="M12 4v16M8 9v2M16 9v2M8.5 15.5c2 1.3 5 1.3 7 0"/>', true],
  ["web", "Safari", '<circle cx="12" cy="12" r="7.5"/><path d="m15 9-4.2 1.8L9 15l4.2-1.8Z"/>', true],
  ["mail", "Mail", '<rect x="4.5" y="6.5" width="15" height="11" rx="1.5"/><path d="m5 7.5 7 5 7-5"/>', false],
  ["notes", "Notes", '<path d="M7 8h10M7 12h10M7 16h6"/>', false],
  ["cal", "Calendar", '<path d="M7 9h10M8 13h2M12 13h2M8 16h2"/>', false],
  ["music", "Music", '<path d="M10 17V6.5l8-1.8V15"/><circle cx="8" cy="17" r="2"/><circle cx="16" cy="15" r="2"/>', true],
  ["photos", "Photos", '<circle cx="12" cy="12" r="2.2"/><path d="M12 5v3M12 16v3M5 12h3M16 12h3"/>', false],
  ["term", "Terminal", '<path d="m7 9 3 3-3 3M12.5 15H17"/>', false],
];
const app = (k: string, g: string) => `<span class="app a-${k}">${svg(g)}</span>`;
const cursorSVG = '<svg class="md-cursor" viewBox="0 0 16 22"><path d="M1 1v17l4.6-4.4 3 6.9 3-1.3-3-6.8H15Z" fill="#1A1A1A" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/></svg>';
const menubar = (extra = "") => `<div class="md-menubar"><i></i><i></i><i></i><i></i>${extra}<i class="r"></i></div>`;
const docLines = '<div class="md-doc"><i class="h"></i><i></i><i style="width:88%"></i><i style="width:94%"></i><i class="p"></i><i></i><i style="width:76%"></i><i style="width:90%"></i><i class="h"></i><i></i><i style="width:82%"></i><i class="p p2"></i><i></i><i style="width:70%"></i></div>';
const win = (cls: string, body: string, front = true, style = "") => `<div class="md-win ${front ? "front" : ""} ${cls}" style="${style}"><div class="wb"><i></i><i></i><i></i></div><div class="wbody">${body}</div></div>`;

interface Mode {
  key: string; title: string; icon: string; accent: string; text: string; land?: boolean;
  phone: () => string; mac: () => string;
  run: (s: Scene) => Promise<void>;
}

/* ---------- Scene helpers shared by every mode's loop ---------- */
class Cancel extends Error {}
class Scene {
  constructor(public ph: HTMLElement, public mac: HTMLElement, private alive: () => boolean) {}
  q<T extends Element = HTMLElement>(sel: string, root: Element = this.ph) { return root.querySelector(sel) as unknown as T; }
  m<T extends Element = HTMLElement>(sel: string) { return this.mac.querySelector(sel) as unknown as T; }
  check() { if (!this.alive()) throw new Cancel(); }
  async wait(ms: number) { await sleep(ms); this.check(); }
  async tween(ms: number, fn: (e: number, u: number) => void, ease = minJerk) {
    const t0 = performance.now();
    for (;;) { const t = await nextFrame(); this.check(); const u = Math.min(1, (t - t0) / ms); fn(ease(u), u); if (u >= 1) return; }
  }
  /** Centre of an element in the screen's own points. */
  at(el: HTMLElement): [number, number] {
    let x = el.offsetWidth / 2, y = el.offsetHeight / 2, n: HTMLElement | null = el;
    while (n && !n.classList.contains("pt")) { x += n.offsetLeft; y += n.offsetTop; n = n.offsetParent as HTMLElement | null; }
    return [x, y];
  }
  fingers: HTMLElement[] = [];
  finger(i = 0) {
    while (this.fingers.length <= i) { const f = document.createElement("div"); f.className = "ms-finger"; this.q(".pt").appendChild(f); this.fingers.push(f); }
    return this.fingers[i];
  }
  put(i: number, x: number, y: number, o = 1, s = 1) { const f = this.finger(i); f.style.transform = `translate(${x}px, ${y}px) scale(${s})`; f.style.opacity = String(o); }
  ripple(x: number, y: number) {
    const r = document.createElement("div"); r.className = "ms-ripple"; r.style.transform = `translate(${x}px, ${y}px)`;
    this.q(".pt").appendChild(r); setTimeout(() => r.remove(), 650);
  }
  async touch(i: number, x: number, y: number) { await this.tween(180, e => this.put(i, x, y, e, lerp(0.7, 1, e))); }
  async lift(i: number, x: number, y: number) { await this.tween(220, e => this.put(i, x, y, 1 - e, lerp(1, 1.12, e))); }
  async tap(el: HTMLElement, after?: () => void) {
    const [x, y] = this.at(el);
    await this.touch(0, x, y);
    el.classList.add("u-press"); this.ripple(x, y);
    await this.wait(110);
    el.classList.remove("u-press");
    after?.();
    await this.lift(0, x, y);
  }
  clear() { this.fingers.forEach(f => f.remove()); this.fingers = []; this.ph.querySelectorAll(".ms-ripple").forEach(r => r.remove()); }
}

/* ---------- The eight modes ---------- */
const MODES: Mode[] = [
  {
    key: "trackpad", title: "Trackpad", icon: "i-trackpad", accent: "#1A1A1A", land: true,
    text: "A plain surface with a soft dot under each finger. Move, tap to click, scroll with momentum, pinch, rotate, and swipe between pages and Spaces. Hold still for a force click.",
    phone: () => `<div class="pt land"></div>`,
    mac: () => `${win("w-b", docLines, false)}${win("w-a", docLines)}${menubar()}${cursorSVG}`,
    async run(s) {
      const cur = s.m<SVGElement>(".md-cursor"), doc = s.m(".w-a .md-doc"), wa = s.m(".w-a"), wb = s.m(".w-b");
      const W = s.mac.clientWidth, H = s.mac.clientHeight;
      let cx = W * 0.6, cy = H * 0.5;
      const pc = () => { cur.style.transform = `translate(${cx}px, ${cy}px)`; };
      wa.style.zIndex = "2"; wb.style.zIndex = "1"; doc.style.transform = ""; pc();
      // move
      let fx = 300, fy = 250; await s.touch(0, fx, fy);
      await s.tween(1100, e => { const nx = lerp(300, 620, e), ny = lerp(250, 160, e) - Math.sin(Math.PI * e) * 40; cx += (nx - fx) * W / 874 * 0.8; cy += (ny - fy) * H / 402 * 0.8; fx = nx; fy = ny; s.put(0, fx, fy); pc(); });
      await s.lift(0, fx, fy); await s.wait(250);
      // tap on the back window
      await s.touch(0, fx, fy); s.ripple(fx, fy); cur.classList.add("press"); await s.wait(110); cur.classList.remove("press");
      wb.style.zIndex = "3"; wb.classList.add("front"); wa.classList.remove("front"); await s.lift(0, fx, fy); await s.wait(500);
      wa.style.zIndex = "3"; wb.style.zIndex = "1"; wb.classList.remove("front"); wa.classList.add("front");
      // two finger scroll
      const y0 = 300; await Promise.all([s.touch(0, 400, y0), s.touch(1, 470, y0 + 6)]);
      await s.tween(700, e => { const dy = -170 * e; s.put(0, 400, y0 + dy); s.put(1, 470, y0 + 6 + dy); doc.style.transform = `translateY(${(-H * 0.32 * e).toFixed(1)}px)`; });
      await Promise.all([s.lift(0, 400, y0 - 170), s.lift(1, 470, y0 - 164)]);
      await s.tween(700, e => { doc.style.transform = `translateY(${(-H * 0.32 - H * 0.1 * e).toFixed(1)}px)`; }, u => 1 - Math.pow(1 - u, 3));
      await s.wait(900);
      await s.tween(600, e => { doc.style.transform = `translateY(${(-H * 0.42 * (1 - e)).toFixed(1)}px)`; });
      await s.wait(600);
    },
  },
  {
    key: "dock", title: "Dock", icon: "i-dock", accent: "#3D7BF2", land: true,
    text: "Your Mac's Dock apps and running apps, as a grid. Tap one to open it or switch to it. A dot marks what is running; the blue one is in front.",
    phone: () => `<div class="pt land"><div class="u-dock">${DOCK_APPS.map(([k, n, g, r], i) => `<div class="tile" data-app="${k}">${app(k, g)}<span>${n}</span><i class="run ${r ? "on" : ""} ${i === 1 ? "act" : ""}"></i></div>`).join("")}</div></div>`,
    mac: () => `${win("w-a", docLines)}<div class="md-win w-new" data-for="notes"><div class="wb" style="background:#F6EFD9"><i></i><i></i><i></i></div><div class="note"><i></i><i></i><i style="width:80%"></i><i style="width:90%"></i><i style="width:60%"></i></div></div><div class="md-win w-new" data-for="term" style="background:#1E1E1E"><div class="wb" style="background:#2B2B2B"><i></i><i></i><i></i></div><div class="note"><i style="background:#61C454;width:30%"></i><i style="background:rgba(255,255,255,.3)"></i><i style="background:rgba(255,255,255,.3);width:70%"></i></div></div>${menubar()}<div class="md-dock">${DOCK_APPS.map(([k, , g, r]) => `<div class="app-slot" data-app="${k}">${app(k, g)}<i class="md-run ${r ? "on" : ""}"></i></div>`).join("")}</div>`,
    async run(s) {
      for (const k of ["notes", "term"]) {
        const tile = s.q(`.tile[data-app="${k}"] .app`), w = s.m(`.w-new[data-for="${k}"]`), slot = s.m(`.app-slot[data-app="${k}"]`);
        await s.wait(500);
        await s.tap(tile, () => {
          const icon = slot.querySelector(".app") as HTMLElement; icon.classList.remove("bounce"); void icon.offsetWidth; icon.classList.add("bounce");
          slot.querySelector(".md-run")!.classList.add("on");
          s.q(`.tile[data-app="${k}"] .run`).classList.add("on", "act");
          s.ph.querySelectorAll(".u-dock .run.act").forEach(r => { if (!r.parentElement!.matches(`[data-app="${k}"]`)) r.classList.remove("act"); });
        });
        await s.wait(420);
        await s.tween(560, e => { w.style.opacity = String(Math.min(1, e * 2)); w.style.transform = `scale(${lerp(0.6, 1, e)})`; }, springOut);
        await s.wait(1500);
        await s.tween(260, e => { w.style.opacity = String(1 - e); w.style.transform = `scale(${lerp(1, 0.94, e)})`; });
        slot.querySelector(".md-run")!.classList.remove("on"); s.q(`.tile[data-app="${k}"] .run`).classList.remove("on", "act");
      }
      s.q('.tile[data-app="web"] .run').classList.add("act");
    },
  },
  {
    key: "keys", title: "Keys", icon: "i-keys", accent: "#8A63E8",
    text: "Type on the phone and it appears on the Mac. Command, Option, Control and Shift, common shortcuts, and Esc, Tab and arrow keys sit above the keyboard. Dictation works too.",
    phone: () => `<div class="pt"><span class="status-dot"></span><div class="u-keys"><div class="echo">Start typing</div><div class="sub">Text goes straight to your Mac</div>
      <div class="u-row u-mods"><span>⌘</span><span>⌥</span><span>⌃</span><span>⇧</span></div>
      <div class="u-row u-sc"><span>⌘C<small>Copy</small></span><span>⌘V<small>Paste</small></span><span>⌘X<small>Cut</small></span><span>⌘Z<small>Undo</small></span><span>⇧⌘Z<small>Redo</small></span></div>
      <div class="u-row u-nav"><span>esc</span><span>tab</span><span>⌫</span><span>←</span><span>↑ ↓</span><span>→</span></div>
      <div class="u-kb"><div>${[..."QWERTYUIOP"].map(c => `<span data-k="${c}">${c}</span>`).join("")}</div><div>${[..."ASDFGHJKL"].map(c => `<span data-k="${c}">${c}</span>`).join("")}</div><div><span class="w">⇧</span>${[..."ZXCVBNM"].map(c => `<span data-k="${c}">${c}</span>`).join("")}<span class="w">⌫</span></div><div><span class="w">123</span><span class="sp" data-k=" "></span><span class="w">⏎</span></div></div></div></div>`,
    mac: () => `${win("w-a", '<div class="mm-type"><span class="txt"></span><span class="caret"></span></div>', true, "left:14%;top:16%;width:62%;height:60%")}${menubar()}`,
    async run(s) {
      const echo = s.q(".echo"), out = s.m(".txt"), phrase = "See you at three";
      echo.textContent = "Start typing"; echo.classList.remove("typed"); out.textContent = "";
      await s.wait(500);
      for (let i = 0; i < phrase.length; i++) {
        const ch = phrase[i], key = s.q(`.u-kb [data-k="${ch.toUpperCase()}"]`);
        key?.classList.add("hit");
        echo.textContent = phrase.slice(0, i + 1); echo.classList.add("typed"); out.textContent = phrase.slice(0, i + 1);
        await s.wait(ch === " " ? 160 : 95);
        key?.classList.remove("hit");
      }
      await s.wait(1600);
      out.textContent = ""; echo.textContent = "Start typing"; echo.classList.remove("typed");
      await s.wait(300);
    },
  },
  {
    key: "media", title: "Media", icon: "i-media", accent: "#EC4F73",
    text: "What is playing on the Mac, with its artwork. Play, pause, skip, volume and screen brightness.",
    phone: () => `<div class="pt"><span class="status-dot"></span><div class="u-media"><div class="art">${svg('<path d="M10 17V6.5l8-1.8V15"/><circle cx="8" cy="17" r="2"/><circle cx="16" cy="15" r="2"/>')}</div>
      <div class="t">Track title</div><div class="a">Artist</div>
      <div class="u-bar" style="top:506px"><i class="prog" style="width:38%"></i></div><div class="times"><span class="el">1:16</span><span>-2:48</span></div>
      <div class="ctl"><svg width="46" height="30" viewBox="0 0 46 30"><path d="M22 3 4 15l18 12ZM42 3 24 15l18 12Z"/></svg><svg class="pp" width="36" height="40" viewBox="0 0 36 40"><rect x="6" y="3" width="8" height="34" rx="2"/><rect x="22" y="3" width="8" height="34" rx="2"/></svg><svg class="nx" width="46" height="30" viewBox="0 0 46 30"><path d="M4 3l18 12L4 27ZM24 3l18 12-18 12Z"/></svg></div>
      <div class="u-bar vol"><i style="width:56%"></i><b style="left:56%"></b></div><div class="u-bar bri"><i style="width:74%"></i><b style="left:74%"></b></div></div></div>`,
    mac: () => `<div class="mm-np"><div class="art"></div><div style="flex:1"><b>Track title</b><span>Artist</span><div class="pb"><i style="width:38%"></i></div></div></div>${menubar()}<div class="mm-hud">${svg(G.speaker)}<span class="pb"><i style="width:56%"></i></span></div>`,
    async run(s) {
      const vol = s.q(".vol"), knob = vol.querySelector("b") as HTMLElement, fill = vol.querySelector("i") as HTMLElement;
      const hud = s.m(".mm-hud"), hfill = s.m(".mm-hud .pb i"), prog = s.q(".prog"), mprog = s.m(".mm-np .pb i");
      let p = 38; const tick = setInterval(() => { p = (p + 0.4) % 100; prog.style.width = mprog.style.width = p + "%"; }, 120);
      try {
        await s.wait(900);
        const [kx, ky] = s.at(knob); const x0 = kx;
        await s.touch(0, x0, ky); hud.classList.add("on");
        await s.tween(900, e => { const v = lerp(56, 84, e); const x = x0 + (v - 56) / 100 * 282; s.put(0, x, ky); knob.style.left = fill.style.width = hfill.style.width = v + "%"; });
        await s.lift(0, x0 + 79, ky); await s.wait(900); hud.classList.remove("on");
        await s.wait(500);
        await s.tween(500, e => { knob.style.left = fill.style.width = hfill.style.width = lerp(84, 56, e) + "%"; });
        await s.wait(800);
      } finally { clearInterval(tick); }
    },
  },
  {
    key: "deck", title: "Deck", icon: "i-deck", accent: "#E8930C",
    text: "A grid of your own buttons, set up in the Mac app. Open an app or a link, run an Apple Shortcut, send a keystroke or run a script.",
    phone: () => `<div class="pt"><span class="status-dot"></span><div class="u-deck">${[["Safari", G.compass], ["Screenshot", G.camera], ["Do Not Disturb", G.moon], ["GitHub", G.link], ["Lock Screen", G.lock], ["Build", G.hammer]].map(([n, g]) => `<div class="u-tile u-raised" data-b="${n}">${svg(g)}<span>${n}</span><i class="ok"></i></div>`).join("")}</div></div>`,
    mac: () => `${win("w-a", docLines)}${menubar(`<svg class="mm-moon" viewBox="0 0 24 24" style="margin-left:auto">${G.moon}</svg>`)}<div class="mm-banner"><b>Do Not Disturb</b>Turned on from Deck</div>`,
    async run(s) {
      const b = s.q('[data-b="Do Not Disturb"]'), ok = b.querySelector(".ok")!, moon = s.m(".mm-moon"), banner = s.m(".mm-banner");
      await s.wait(700);
      await s.tap(b, () => { ok.classList.add("on"); moon.classList.add("on"); banner.classList.add("on"); });
      await s.wait(1900); banner.classList.remove("on"); ok.classList.remove("on");
      await s.wait(1100);
      await s.tap(b, () => moon.classList.remove("on"));
      await s.wait(900);
    },
  },
  {
    key: "macros", title: "Macros", icon: "i-macros", accent: "#12A594",
    text: "Buttons for the app in front, switching on their own as you change apps. Record new ones on the Mac and replay them with a tap, or run your Apple Shortcuts.",
    phone: () => `<div class="pt"><span class="status-dot"></span><div class="u-seg"><span class="on">For Safari</span><span>All</span></div><div class="u-macros">${[["New Private Window", G.window, "#3D7BF2"], ["Reopen Closed Tab", G.undo, "#3D7BF2"], ["Reader Mode", G.reader, "#E8930C"], ["Save to Notes", G.note, "#D9A400"], ["Show Downloads", G.down, "#2E9E5B"]].map(([n, g, c]) => `<div class="u-tile u-raised" data-b="${n}" style="--c:${c}">${svg(g)}<span>${n}</span></div>`).join("")}</div><div class="u-rec u-raised"><i></i>Record</div></div>`,
    mac: () => `<div class="md-win front" style="left:8%;top:12%;width:84%;height:74%"><div class="mm-tabs"><span></span><span class="on"></span></div><div class="wbody" style="top:18cqh">${docLines}</div></div>${menubar()}`,
    async run(s) {
      const b = s.q('[data-b="Reopen Closed Tab"]'), tabs = s.m(".mm-tabs");
      tabs.innerHTML = '<span></span><span class="on"></span>';
      await s.wait(700);
      await s.tap(b, () => { tabs.querySelectorAll("span").forEach(t => t.classList.remove("on")); const t = document.createElement("span"); t.className = "on new"; tabs.appendChild(t); });
      await s.wait(2200);
    },
  },
  {
    key: "clipboard", title: "Clipboard", icon: "i-clipboard", accent: "#2E9E5B",
    text: "Send what you copied on your phone to the Mac, or bring the Mac's clipboard to the phone. Text and images.",
    phone: () => `<div class="pt"><span class="status-dot"></span>
      <div class="u-card u-raised" style="top:96px"><h4>${svg(G.toMac)}To your Mac</h4><p>Text or an image copied on this iPhone.</p><span class="u-gbtn soft">Paste</span><p class="note" style="margin-left:0">Copy something on this iPhone first, then tap Paste.</p></div>
      <div class="u-card u-raised" style="top:290px"><h4>${svg(G.fromMac)}From your Mac</h4><p>Copies what is on the Mac clipboard to this iPhone.</p><span class="u-gbtn solid">${"Get Mac clipboard"}</span><div class="u-clip">Dinner on Friday at seven, table for four.</div></div></div>`,
    mac: () => `${win("w-a", '<div class="mm-type">Plans<br><span class="mm-sel">Dinner on Friday at seven, table for four.</span><br>Bring the photos.</div>', true, "left:12%;top:15%;width:66%;height:62%")}${menubar()}`,
    async run(s) {
      const btn = s.q(".u-gbtn.solid"), clip = s.q(".u-clip");
      clip.classList.remove("on"); await s.wait(800);
      await s.tap(btn, () => clip.classList.add("on"));
      await s.wait(2400); clip.classList.remove("on"); await s.wait(500);
    },
  },
  {
    key: "present", title: "Present", icon: "i-present", accent: "#EE6A2F",
    text: "Big next and previous buttons and a timer. Touch and hold the pad to steer a laser dot across the Mac's screen.",
    phone: () => `<div class="pt"><span class="status-dot"></span><div class="u-present"><div class="timer">0:00</div>
      <span class="tb reset u-raised">${svg('<path d="M5 12a7 7 0 1 0 2-5"/><path d="M5 4v4h4"/>').replace("<svg", '<svg style="fill:none;stroke:#888;stroke-width:2;stroke-linecap:round"')}</span>
      <span class="tb play">${'<svg viewBox="0 0 14 14"><path d="M3 1.5v11l9-5.5Z" fill="#fff"/></svg>'}</span>
      <div class="pad u-raised"><div>${svg(G.wave)}Touch and hold to point</div></div>
      <div class="prev u-raised"><svg class="chev" viewBox="0 0 24 24"><path d="m15 5-7 7 7 7"/></svg></div>
      <div class="next"><div><svg class="chev" viewBox="0 0 24 24" style="display:block;margin:0 auto 4px"><path d="m9 5 7 7-7 7"/></svg>Next</div></div></div></div>`,
    mac: () => `<div class="mm-slide"><i class="h"></i><i></i><i style="width:80%"></i><i style="width:64%"></i><span class="num">1</span></div><div class="mm-laser"></div>`,
    async run(s) {
      const timer = s.q(".timer"), next = s.q(".next"), pad = s.q(".pad"), num = s.m(".num"), laser = s.m(".mm-laser"), slide = s.m(".mm-slide");
      const W = s.mac.clientWidth, H = s.mac.clientHeight;
      let secs = 0; timer.textContent = "0:00"; num.textContent = "1";
      await s.wait(500);
      await s.tap(s.q(".tb.play"));
      const tick = setInterval(() => { secs++; timer.textContent = `0:${String(secs).padStart(2, "0")}`; }, 1000);
      try {
        await s.wait(500);
        await s.tap(next, () => { num.textContent = "2"; slide.animate([{ opacity: 0.4, transform: "translateX(3%)" }, { opacity: 1, transform: "none" }], { duration: 420, easing: "cubic-bezier(.2,.8,.2,1)" }); });
        await s.wait(500);
        const [px, py] = s.at(pad);
        await s.touch(0, px - 80, py + 40); laser.classList.add("on");
        await s.tween(1600, e => {
          const x = px - 80 + 160 * e, y = py + 40 - Math.sin(Math.PI * e) * 80;
          s.put(0, x, y); laser.style.transform = `translate(${(W * (0.25 + 0.5 * e)).toFixed(1)}px, ${(H * (0.62 - Math.sin(Math.PI * e) * 0.3)).toFixed(1)}px)`;
        });
        await s.lift(0, px + 80, py + 40); laser.classList.remove("on");
        await s.wait(1300);
      } finally { clearInterval(tick); }
    },
  },
];
const springOut = (u: number) => 1 - Math.exp(-7 * u) * Math.cos(10 * u);

export function initModes() {
  const rail = document.getElementById("modeRail")!, ind = document.getElementById("railInd")!;
  const wrapS = document.getElementById("msWrap")!, mmd = document.getElementById("mmDisplay")!;
  const rot = document.getElementById("mdRot")!, device = document.getElementById("modeDevice")!;
  const copy = document.getElementById("modeCopy")!, scroller = document.getElementById("modesScroll")!;
  const screen = document.querySelector("#modeIphone .ip-screen") as HTMLElement;

  const buttons: HTMLButtonElement[] = [], screens: HTMLElement[] = [], layers: HTMLElement[] = [];
  MODES.forEach((m, i) => {
    const b = document.createElement("button");
    b.setAttribute("role", "tab"); b.id = "tab-" + m.key; b.setAttribute("aria-controls", "modeCopy");
    b.innerHTML = `<svg width="20" height="20" aria-hidden="true"><use href="#${m.icon}"/></svg>${m.title}`;
    b.addEventListener("click", () => choose(i, true));
    b.addEventListener("keydown", e => {
      const d = ["ArrowDown", "ArrowRight"].includes(e.key) ? 1 : ["ArrowUp", "ArrowLeft"].includes(e.key) ? -1 : 0;
      if (d) { e.preventDefault(); const n = (i + d + MODES.length) % MODES.length; choose(n, true); buttons[n].focus(); }
    });
    rail.appendChild(b); buttons.push(b);
    const sc = document.createElement("div"); sc.className = "ms"; sc.innerHTML = m.phone(); wrapS.appendChild(sc); screens.push(sc);
    const ly = document.createElement("div"); ly.className = "mm-layer"; ly.innerHTML = m.mac(); mmd.appendChild(ly); layers.push(ly);
  });

  // fit the point-sized screens into the drawn screen
  const fit = () => {
    const w = screen.clientWidth; if (!w) return;
    const k = w / 402;
    wrapS.querySelectorAll<HTMLElement>(".pt").forEach(pt => {
      pt.style.transform = pt.classList.contains("land") ? `translate(${w}px, 0) rotate(90deg) scale(${k})` : `scale(${k})`;
    });
    // landscape: the turned phone must fit the column
    const colW = device.clientWidth, h = rot.clientHeight;
    rot.style.setProperty("--land-scale", String(Math.min(1.12, colW / h).toFixed(3)));
  };
  new ResizeObserver(fit).observe(screen); new ResizeObserver(fit).observe(device);

  let current = -1, token = 0;
  const alive = (t: number) => () => t === token;
  async function loop(i: number, t: number) {
    const s = new Scene(screens[i], layers[i], alive(t));
    await sleep(reduce ? 0 : 700);
    if (reduce) return;
    try { for (;;) { if (t !== token) return; await MODES[i].run(s); s.clear(); } }
    catch (e) { s.clear(); if (!(e instanceof Cancel)) throw e; }
  }

  function show(i: number) {
    if (i === current) return;
    current = i; token++;
    const m = MODES[i];
    buttons.forEach((b, k) => { b.setAttribute("aria-selected", String(k === i)); b.tabIndex = k === i ? 0 : -1; });
    ind.style.transform = `translateY(${buttons[i].offsetTop}px)`;
    rot.classList.toggle("land", !!m.land);
    screens.forEach((sc, k) => sc.classList.toggle("on", k === i));
    layers.forEach((l, k) => l.classList.toggle("on", k === i));
    copy.style.setProperty("--acc", m.accent);
    copy.innerHTML = `<h3><i></i>${m.title}</h3><p>${m.text}</p>`;
    if (!reduce) { copy.classList.remove("swap"); void copy.offsetWidth; copy.classList.add("swap"); }
    if (matchMedia("(max-width: 960px)").matches) buttons[i].scrollIntoView({ block: "nearest", inline: "center", behavior: reduce ? "auto" : "smooth" });
    loop(i, token);
  }

  const pinned = () => !matchMedia("(max-width: 960px)").matches;
  function choose(i: number, fromUser: boolean) {
    if (fromUser && pinned()) {
      const top = scroller.getBoundingClientRect().top + scrollY;
      const span = scroller.offsetHeight - innerHeight;
      scrollTo({ top: top + span * ((i + 0.5) / MODES.length), behavior: reduce ? "auto" : "smooth" });
    }
    show(i);
  }
  // pinned stage: scroll position picks the mode
  let ticking = false, visible = false;
  const onScroll = () => {
    ticking = false;
    if (!pinned()) return;
    const r = scroller.getBoundingClientRect(), span = scroller.offsetHeight - innerHeight;
    const p = clamp(-r.top / span, 0, 0.9999);
    show(Math.floor(p * MODES.length));
  };
  addEventListener("scroll", () => { if (!ticking) { ticking = true; requestAnimationFrame(onScroll); } }, { passive: true });
  // pause the loop while off screen
  new IntersectionObserver(([e]) => {
    visible = e.isIntersecting;
    if (!visible) { token++; } else if (current >= 0) { const c = current; current = -1; show(c); }
  }).observe(device);
  show(0); fit(); onScroll();
}

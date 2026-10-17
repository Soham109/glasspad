import { clamp, lerp, minJerk, reducedMotion, nextFrame, sleep } from "./spring";
import { APPS, appIcon } from "./apps";
import { glyph } from "./glyphs";
import { Scene, Cancel, tl, phone, loopInView } from "./kit";
import { menuBar } from "./scenes";

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

const G2 = {
  plusSq: '<rect x="8" y="8" width="12" height="12" rx="2.5"/><path d="M14 11.5v5M11.5 14h5M16 8V6.5A2.5 2.5 0 0 0 13.5 4h-7A2.5 2.5 0 0 0 4 6.5v7A2.5 2.5 0 0 0 6.5 16H8"/>',
  hand: '<path d="M8 13V6.5a1.5 1.5 0 0 1 3 0V12M11 11V5a1.5 1.5 0 0 1 3 0v6M14 11V6.5a1.5 1.5 0 0 1 3 0V14a6 6 0 0 1-6 6h-.5a5 5 0 0 1-4.2-2.3L4.5 14.5a1.4 1.4 0 0 1 2.2-1.7L8 14"/>',
  xbox: '<rect x="4.5" y="4.5" width="15" height="15" rx="3"/><path d="m9.5 9.5 5 5M14.5 9.5l-5 5"/>',
  pin: '<path d="M9 4h6M10 4v6l-3 4h10l-3-4V4M12 14v6"/>',
  folder: '<path d="M4 7.5A1.5 1.5 0 0 1 5.5 6h4l2 2h7A1.5 1.5 0 0 1 20 9.5v8a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 17.5Z"/>',
  folderPlus: '<path d="M4 7.5A1.5 1.5 0 0 1 5.5 6h4l2 2h7A1.5 1.5 0 0 1 20 9.5v8a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 17.5Z"/><path d="M12 11v5M9.5 13.5h5"/>',
  info: '<circle cx="12" cy="12" r="8"/><path d="M12 11v5M12 8h.01"/>',
  eye: '<path d="M3.5 12S6.5 6.5 12 6.5 20.5 12 20.5 12 17.5 17.5 12 17.5 3.5 12 3.5 12Z"/><circle cx="12" cy="12" r="2.5"/>',
  eyeSlash: '<path d="M3.5 12S6.5 6.5 12 6.5 20.5 12 20.5 12 17.5 17.5 12 17.5 3.5 12 3.5 12Z"/><path d="M5 19 19 5"/>',
  goto: '<circle cx="12" cy="12" r="8"/><path d="M8.5 12h7M12.5 9l3 3-3 3"/>',
  half: '<circle cx="12" cy="12" r="8"/><path d="M12 4v16a8 8 0 0 0 0-16Z" fill="currentColor"/>',
  users: '<circle cx="9" cy="9" r="2.6"/><circle cx="16" cy="9.5" r="2.2"/><path d="M4 18c.6-2.8 2.6-4.2 5-4.2s4.4 1.4 5 4.2M14.5 14c2.4-.4 4.6.8 5.5 3.6"/>',
  rename: '<path d="M14.5 5.5l4 4L9 19H5v-4Z"/>',
  more: '<circle cx="7" cy="12" r="1" fill="currentColor"/><circle cx="12" cy="12" r="1" fill="currentColor"/><circle cx="17" cy="12" r="1" fill="currentColor"/>',
  search: '<circle cx="11" cy="11" r="5.5"/><path d="m15 15 4 4"/>',
  x: '<path d="m7 7 10 10M17 7 7 17"/>',
  plus: '<path d="M12 6v12M6 12h12"/>',
  shuffle: '<path d="M4 7h3c4 0 6 10 10 10h3M4 17h3c1.6 0 2.8-1.6 3.8-3.4M13.2 10.4C14.2 8.6 15.4 7 17 7h3M18 5l2 2-2 2M18 15l2 2-2 2"/>',
  repeat: '<path d="M5 11V9.5A2.5 2.5 0 0 1 7.5 7H19M16.5 4.5 19 7l-2.5 2.5M19 13v1.5a2.5 2.5 0 0 1-2.5 2.5H5M7.5 19.5 5 17l2.5-2.5"/>',
  output: '<path d="M7 17H5.5A1.5 1.5 0 0 1 4 15.5v-9A1.5 1.5 0 0 1 5.5 5h13A1.5 1.5 0 0 1 20 6.5v9a1.5 1.5 0 0 1-1.5 1.5H17"/><path d="m12 14 4 5H8Z"/>',
  sun: '<circle cx="12" cy="12" r="3.5"/><path d="M12 4v2M12 18v2M4 12h2M18 12h2M6.3 6.3l1.4 1.4M16.3 16.3l1.4 1.4M17.7 6.3l-1.4 1.4M7.7 16.3l-1.4 1.4"/>',
  quit: '<circle cx="12" cy="12" r="8"/><path d="m9.5 9.5 5 5M14.5 9.5l-5 5"/>',
  hide: '<path d="M3.5 12S6.5 6.5 12 6.5 20.5 12 20.5 12 17.5 17.5 12 17.5 3.5 12 3.5 12Z"/><path d="M5 19 19 5"/>',
  keep: '<path d="M9 4h6M10 4v6l-3 4h10l-3-4V4M12 14v6"/>',
};
const ic = (g: string) => svg(g);
const tile = (k: string, cls = "") => appIcon(k, cls);
export const cursorSVG = '<svg class="md-cursor" viewBox="0 0 16 22"><path d="M1 1v17l4.6-4.4 3 6.9 3-1.3-3-6.8H15Z" fill="#1A1A1A" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/></svg>';
const docLines = '<div class="md-doc"><i class="h"></i><i></i><i style="width:88%"></i><i style="width:94%"></i><i class="p"></i><i></i><i style="width:76%"></i><i style="width:90%"></i><i class="h"></i><i></i><i style="width:82%"></i><i class="p p2"></i><i></i><i style="width:70%"></i></div>';
const win = (cls: string, body: string, front = true, style = "") => `<div class="md-win ${front ? "front" : ""} ${cls}" style="${style}"><div class="wb"><i></i><i></i><i></i></div><div class="wbody">${body}</div></div>`;

/* The Mac's Dock, in Dock order, as the Dock mode shows it. */
const DOCK: [string, boolean][] = [["finder", true], ["web", true], ["mail", true], ["msg", false], ["cal", false], ["notes", false], ["rem", false], ["music", true], ["photos", false], ["xcode", true], ["term", false], ["store", false], ["set", false]];
const MAC_DOCK = ["finder", "web", "mail", "notes", "music", "xcode", "term"];

interface Mode {
  key: string; title: string; icon: string; accent: string; text: string; land?: boolean;
  phone: () => string; mac: () => string;
  run: (s: Scene) => Promise<void>;
}

const bounce = (el: HTMLElement) => { el.classList.remove("bounce"); void el.offsetWidth; el.classList.add("bounce"); };

/* ---------- Keyboard, Media, Dock, Clipboard and Macros ---------- */
const MODES: Mode[] = [
  {
    key: "keys", title: "Keyboard", icon: "i-keys", accent: "#5856D6",
    text: "Type on the phone, and it lands on the Mac. Modifier keys, shortcuts, F1 to F12 and dictation.",
    phone: () => `<div class="pt"><span class="status-dot"></span><div class="u-keys"><div class="echo">Start typing</div><div class="sub">Typing goes straight to your Mac</div>
      <div class="k-mods">${[["⌃", "control"], ["⌥", "option"], ["⌘", "command"], ["⇧", "shift"], ["fn", ""]].map(([a, b]) => `<span><b>${a}</b>${b ? `<small>${b}</small>` : ""}</span>`).join("")}</div>
      <div class="k-sc">${[["Copy", "⌘C"], ["Paste", "⌘V"], ["Cut", "⌘X"], ["Undo", "⌘Z"], ["Redo", "⇧⌘Z"]].map(([a, b]) => `<span>${a}<small>${b}</small></span>`).join("")}</div>
      <div class="k-nav"><span style="grid-area:1/1">esc</span><span style="grid-area:1/2">tab</span><span style="grid-area:1/4">↑</span><span style="grid-area:2/1/3/3">⌫</span><span style="grid-area:2/3">←</span><span style="grid-area:2/4">↓</span><span style="grid-area:2/5">→</span></div>
      <div class="u-kb"><div>${[..."QWERTYUIOP"].map(c => `<span data-k="${c}">${c}</span>`).join("")}</div><div>${[..."ASDFGHJKL"].map(c => `<span data-k="${c}">${c}</span>`).join("")}</div><div><span class="w">⇧</span>${[..."ZXCVBNM"].map(c => `<span data-k="${c}">${c}</span>`).join("")}<span class="w">⌫</span></div><div class="kb-b"><span class="w">123</span><span class="sp" data-k=" ">space</span><span class="w">return</span></div></div></div></div>`,
    mac: () => `${win("w-a", '<div class="mm-type"><span class="txt"></span><span class="caret"></span></div>', true, "left:14%;top:16%;width:62%;height:60%")}${menuBar("Notes", ["File", "Edit", "Format", "View", "Window"])}`,
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
    key: "media", title: "Media", icon: "i-media", accent: "#FF2D55",
    text: "Spotify, Music or a browser: artwork, scrubbing, sound output, volume and screen brightness.",
    phone: () => `<div class="pt"><span class="status-dot"></span><div class="u-media">
      <div class="art"><i class="a1"></i><i class="a2"></i><i class="a3"></i></div>
      <div class="src"><i></i>SPOTIFY</div><div class="t">Slow Light</div><div class="a">Paper Rooms · Glass Hours</div>
      <div class="scrub"><i class="prog"></i><b class="knob"></b></div><div class="times"><span class="el">1:16</span><span class="rem">-2:48</span></div>
      <div class="ctl"><svg viewBox="0 0 46 30"><path d="M22 3 4 15l18 12ZM42 3 24 15l18 12Z"/></svg><span class="pp"><svg class="pause" viewBox="0 0 36 40"><rect x="5" y="3" width="9" height="34" rx="2"/><rect x="22" y="3" width="9" height="34" rx="2"/></svg><svg class="play" viewBox="0 0 36 40"><path d="M6 3.5v33a1.5 1.5 0 0 0 2.3 1.3l26-16.5a1.5 1.5 0 0 0 0-2.6L8.3 2.2A1.5 1.5 0 0 0 6 3.5Z"/></svg></span><svg viewBox="0 0 46 30"><path d="M4 3l18 12L4 27ZM24 3l18 12-18 12Z"/></svg></div>
      <div class="opts"><span>${ic(G2.shuffle)}</span><span class="on">${ic(G2.output)}</span><span>${ic(G2.repeat)}</span></div>
      <div class="lvl vol">${ic(G.speaker)}<div class="u-bar"><i style="width:56%"></i><b style="left:56%"></b></div></div>
      <div class="lvl bri">${ic(G2.sun)}<div class="u-bar"><i style="width:74%"></i><b style="left:74%"></b></div></div></div></div>`,
    mac: () => `${win("w-a", docLines, false, "left:6%;top:12%;width:60%;height:62%")}<div class="mm-np"><div class="art"><i class="a1"></i><i class="a2"></i></div><div style="flex:1;min-width:0"><b>Slow Light</b><span>Paper Rooms</span><div class="pb"><i style="width:31%"></i></div></div><span class="mm-state"></span></div>${menuBar("Spotify", ["File", "Edit", "View", "Playback", "Window"])}<div class="mm-hud">${svg(G.speaker)}<span class="pb"><i style="width:56%"></i></span></div>`,
    async run(s) {
      const total = 244;
      const pp = s.q(".pp"), art = s.q(".art"), prog = s.q(".prog"), knob = s.q(".knob"), el = s.q(".el"), rem = s.q(".rem");
      const mprog = s.m(".mm-np .pb i"), mstate = s.m(".mm-state");
      const vol = s.q(".vol .u-bar"), vk = vol.querySelector("b") as HTMLElement, vf = vol.querySelector("i") as HTMLElement;
      const hud = s.m(".mm-hud"), hfill = s.m(".mm-hud .pb i");
      let pos = 76, playing = true;
      const clock = (t: number) => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, "0")}`;
      const draw = () => { const p = pos / total * 100; prog.style.width = knob.style.left = mprog.style.width = p + "%"; el.textContent = clock(pos); rem.textContent = "-" + clock(total - pos); };
      const setPlaying = (on: boolean) => { playing = on; pp.classList.toggle("paused", !on); art.classList.toggle("paused", !on); mstate.classList.toggle("paused", !on); };
      setPlaying(true); draw();
      const tick = setInterval(() => { if (playing) { pos = Math.min(total, pos + 0.25); draw(); } }, 250);
      try {
        await s.wait(1100);
        await s.tap(pp, () => setPlaying(false));
        await s.wait(1300);
        await s.tap(pp, () => setPlaying(true));
        await s.wait(700);
        // scrub ahead
        const [kx, ky] = s.at(knob);
        await s.touch(0, kx, ky); knob.classList.add("held");
        const p0 = pos;
        await s.tween(800, e => { pos = p0 + 70 * e; draw(); s.put(0, 22 + (402 - 44) * pos / total, ky); });
        knob.classList.remove("held"); await s.lift(0, 22 + (402 - 44) * pos / total, ky);
        await s.wait(700);
        // volume
        const [vx, vy] = s.at(vk);
        await s.touch(0, vx, vy); hud.classList.add("on");
        const w = vol.clientWidth;
        await s.tween(800, e => { const v = lerp(56, 82, e); s.put(0, vx + (v - 56) / 100 * w, vy); vk.style.left = vf.style.width = hfill.style.width = v + "%"; });
        await s.lift(0, vx + 0.26 * w, vy); await s.wait(800); hud.classList.remove("on");
        await s.tween(500, e => { vk.style.left = vf.style.width = hfill.style.width = lerp(82, 56, e) + "%"; });
        await s.wait(600);
      } finally { clearInterval(tick); }
    },
  },
  {
    key: "dock", title: "Dock", icon: "i-dock", accent: "#0A84FF",
    text: "Your Mac's Dock, full size. Tap to open, hold to hide or quit, and hide the Mac's own Dock, always or while connected.",
    phone: () => `<div class="pt"><span class="status-dot"></span><div class="u-apps">
      <div class="hd"><b>Dock</b><span class="sub">Your Mac · <span class="n">5</span> open</span><span class="more">${ic(G2.more)}</span></div>
      <div class="grid">${DOCK.map(([k, r]) => `<div class="at" data-app="${k}">${tile(k)}<i class="run ${r ? "on" : ""} ${k === "web" ? "act" : ""}"></i><span>${APPS[k][0]}</span></div>`).join("")}</div>
      <div class="ctx"><span>${ic(G2.hide)}Hide</span><span>${glyph("folder")}Show in Finder</span><span>${glyph("eye.slash.circle")}Hide on iPhone</span><span class="q">${ic(G2.quit)}Quit</span></div>
      <div class="dim"></div><div class="u-menu"><span>${glyph("square.grid.2x2")}Edit Dock</span><i></i><small>Hide Mac Dock</small><span class="opt on">${glyph("checkmark")}Never</span><span class="opt">${glyph("checkmark")}While Connected</span><span class="opt hm">${glyph("checkmark")}Always</span></div></div></div>`,
    mac: () => `${win("w-a", docLines, true, "left:8%;top:10%;width:54%;height:58%")}<div class="md-win w-new mm-notes" data-for="notes"><div class="wb"><i></i><i></i><i></i></div><div class="note"><i></i><i></i><i style="width:80%"></i><i style="width:90%"></i><i style="width:60%"></i></div></div>${menuBar("Notes", ["File", "Edit", "Format", "View", "Window"])}<div class="md-dock">${MAC_DOCK.map(k => `<div class="app-slot" data-app="${k}">${tile(k)}<i class="md-run ${DOCK.find(d => d[0] === k)?.[1] ? "on" : ""}"></i></div>`).join("")}</div>`,
    async run(s) {
      const n = s.q(".n"), ctx = s.q(".ctx"), dim = s.q(".dim");
      const run = (k: string) => s.q(`.grid [data-app="${k}"] .run`), mrun = (k: string) => s.m(`.app-slot[data-app="${k}"] .md-run`);
      const notes = s.m(".mm-notes");
      await s.wait(700);
      // open Notes
      await s.tap(s.q('[data-app="notes"] .app'), () => {
        bounce(s.m('.app-slot[data-app="notes"] .app')); mrun("notes").classList.add("on");
        run("notes").classList.add("on", "act"); run("web").classList.remove("act"); n.textContent = "6";
      });
      await s.wait(380);
      await s.tween(560, e => { notes.style.opacity = String(Math.min(1, e * 2)); notes.style.transform = `scale(${lerp(0.6, 1, e)})`; }, springOut);
      await s.wait(1200);
      // touch and hold Music, then Quit
      const music = s.q('[data-app="music"]'), micon = music.querySelector(".app") as HTMLElement;
      const [mx, my] = s.at(micon);
      await s.touch(0, mx, my);
      await s.tween(420, e => { micon.style.transform = `scale(${lerp(1, 1.12, e)})`; });
      dim.classList.add("on"); music.classList.add("lift"); ctx.classList.add("on");
      await s.lift(0, mx, my);
      await s.wait(700);
      await s.tap(ctx.querySelector(".q") as HTMLElement, () => {
        ctx.classList.remove("on"); dim.classList.remove("on"); music.classList.remove("lift"); micon.style.transform = "";
        run("music").classList.remove("on"); mrun("music").classList.remove("on"); n.textContent = "5";
      });
      await s.wait(1000);
      // the menu: hide the Mac's own Dock
      const menu = s.q(".u-menu"), mdock = s.m(".md-dock");
      await s.tap(s.q(".more"), () => menu.classList.add("on"));
      await s.wait(600);
      await s.tap(s.q(".u-menu .hm"), () => { s.q(".u-menu .opt.on").classList.remove("on"); s.q(".u-menu .hm").classList.add("on"); menu.classList.remove("on"); mdock.classList.add("hidden"); });
      await s.wait(1800);
      mdock.classList.remove("hidden");
      s.q(".u-menu .opt.on")?.classList.remove("on"); s.q(".u-menu .opt")?.classList.add("on");
      // put things back quietly
      await s.tween(300, e => { notes.style.opacity = String(1 - e); });
      notes.style.transform = "scale(0.6)";
      run("notes").classList.remove("on", "act"); mrun("notes").classList.remove("on"); run("web").classList.add("act");
      run("music").classList.add("on"); mrun("music").classList.add("on");
      await s.wait(500);
    },
  },
  {
    key: "clipboard", title: "Clipboard", icon: "i-clipboard", accent: "#34C759",
    text: "Text and images, both ways. Send to Mac, or get what the Mac has copied.",
    phone: () => `<div class="pt"><span class="status-dot"></span><div class="u-clip">
      <div class="u-h">Clipboard</div>
      <div class="cc to"><div class="ch">${glyph("square.and.arrow.up")}<div><b>Send to Mac</b><span>Text or an image you copied on this iPhone.</span></div></div>
        <div class="pv">See you at the station at nine</div>
        <div class="crow"><span class="cbtn paste">${glyph("doc.on.clipboard")}Paste</span><span class="ok">${glyph("checkmark")}Sent</span></div></div>
      <div class="cc from"><div class="ch">${glyph("square.and.arrow.down")}<div><b>Get from Mac</b><span>Whatever is copied on your Mac, copied here too.</span></div></div>
        <div class="img"><i class="a1"></i><i class="a2"></i><i class="a3"></i></div>
        <div class="crow"><span class="cbtn get">${glyph("square.and.arrow.down")}Get from Mac</span><span class="ok">${glyph("checkmark")}Copied to iPhone</span></div></div>
    </div></div>`,
    mac: () => `${win("w-a mm-cnote", '<div class="mm-type"><span class="txt"></span><span class="caret"></span></div>', true, "left:5%;top:12%;width:50%;height:58%")}${win("w-b mm-cphoto", '<div class="ph"><i class="a1"></i><i class="a2"></i><i class="a3"></i></div>', false, "left:47%;top:24%;width:47%;height:58%")}${menuBar("Notes", ["File", "Edit", "Format", "View", "Window"])}<div class="mm-toast">Copied</div>`,
    async run(s) {
      const to = s.q(".cc.to"), from = s.q(".cc.from"), txt = s.m(".mm-cnote .txt"), photo = s.m(".mm-cphoto"), note = s.m(".mm-cnote"), toast = s.m(".mm-toast");
      const front = (a: HTMLElement, b: HTMLElement) => { a.style.zIndex = "3"; b.style.zIndex = "2"; a.classList.add("front"); b.classList.remove("front"); };
      to.classList.remove("done"); from.classList.remove("done"); txt.textContent = ""; photo.classList.remove("sel"); front(note, photo);
      await s.wait(900);
      // iPhone to Mac: the copied line lands where the cursor is
      await s.tap(s.q(".paste"), () => to.classList.add("done"));
      const line = "See you at the station at nine";
      for (let i = 1; i <= line.length; i += 2) { txt.textContent = line.slice(0, i); await s.wait(26); }
      txt.textContent = line;
      await s.wait(1300);
      // Mac to iPhone: copy a photo on the Mac, then fetch it
      front(photo, note); photo.classList.add("sel"); toast.classList.add("on");
      await s.wait(900); toast.classList.remove("on");
      await s.tap(s.q(".get"), () => from.classList.add("done"));
      await s.wait(2000);
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
  // the drawn screens are pictures; the rail and the words beside them carry the meaning
  wrapS.inert = true; mmd.inert = true;

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
    // narrow screens: slide the rail sideways only, never the page
    if (matchMedia("(max-width: 960px)").matches) { const b = buttons[i]; rail.scrollTo({ left: b.offsetLeft - (rail.clientWidth - b.offsetWidth) / 2, behavior: reduce ? "auto" : "smooth" }); }
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

/** One mode on its own (the Features pages): the phone beside a small Mac, looping while on screen. */
export function mountMode(root: HTMLElement, key: string) {
  const m = MODES.find(x => x.key === key);
  if (!m) return;
  // the two boxes are in the page already (site/render.ts), sized by CSS, so nothing moves when they fill
  root.querySelector(".pgm-phone")!.innerHTML = phone("portrait", "light", `<div class="ms on">${m.phone()}</div>`);
  root.querySelector(".pgm-mac")!.innerHTML = `<div class="mini-mac"><div class="mm-display"><div class="mm-layer on">${m.mac()}</div></div></div><div class="pgm-foot"></div>`;
  const screen = root.querySelector<HTMLElement>(".ip-screen")!, ms = root.querySelector<HTMLElement>(".ms")!;
  root.querySelectorAll<HTMLElement>(".pgm-phone, .pgm-mac").forEach(e => { e.inert = true; });
  const fit = () => { const w = screen.clientWidth; if (w) ms.querySelectorAll<HTMLElement>(".pt").forEach(pt => { pt.style.transform = `scale(${w / 402})`; }); };
  new ResizeObserver(fit).observe(screen); fit();
  loopInView(root, ms, root.querySelector<HTMLElement>(".mm-layer")!, s => m.run(s));
}

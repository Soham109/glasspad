import { reducedMotion, sleep } from "./spring";
import { appIcon, APPS } from "./apps";
import { glyph, GLYPH } from "./glyphs";

/* Remote and Layouts: drawn recreations of the iPhone app's screens, authored in iPhone points. */
const reduce = reducedMotion();
const svg = (body: string) => `<svg viewBox="0 0 24 24" aria-hidden="true">${body}</svg>`;
const I = {
  up: '<path d="m6 14 6-6 6 6"/>', down: '<path d="m6 10 6 6 6-6"/>', left: '<path d="m14 6-6 6 6 6"/>', right: '<path d="m10 6 6 6-6 6"/>',
  back: '<path d="M10 6 4.5 11.5 10 17"/><path d="M5 11.5h9a5 5 0 0 1 0 10"/>',
  home: '<path d="M4 10.5 12 4l8 6.5V19a1.5 1.5 0 0 1-1.500 1.500h-13A1.500 1.500 0 0 1 4 19Z"/>',
  mute: '<path d="M3.5 9.5h3l4.500-4v13l-4.500-4h-3Z"/><path d="m14.500 9.500 5 5M19.500 9.500l-5 5"/>',
  back10: '<path d="M5 12a7 7 0 1 1 2 5"/><path d="M5 6.500V12h5.500"/><path d="M9.500 10v4M12 10h2v4h-2Z"/>',
  fwd10: '<path d="M19 12a7 7 0 1 0-2 5"/><path d="M19 6.500V12h-5.500"/><path d="M8.500 10v4M11 10h2v4h-2Z"/>',
  play: '<path class="f" d="M7 4.800v14.400a1 1 0 0 0 1.500.900l11.200-7.200a1 1 0 0 0 0-1.700L8.500 3.900A1 1 0 0 0 7 4.800Z"/>',
  search: '<circle cx="11" cy="11" r="5.500"/><path d="m15 15 4 4"/>',
  skip: '<path d="M5 6.500v11l8-5.500Z"/><path d="M16 6v12"/>',
  next: '<path d="M5 6.500v11l7-5.500Z"/><path d="M12.500 6.500v11l7-5.500Z"/>',
  cc: '<rect x="3.500" y="6" width="17" height="12" rx="3"/><path d="M10 10.500a2 2 0 1 0 0 3M16 10.500a2 2 0 1 0 0 3"/>',
  speed: '<path d="M4.500 16a8 8 0 1 1 15 0"/><path d="m12 13 3.500-4"/>',
  theater: '<rect x="3" y="7" width="18" height="10" rx="2"/>',
};

/* ---------- Remote ---------- */
interface RApp { key: string; name: string; color: string; keys: [string, string][]; tiles: string[] }
const RAPPS: RApp[] = [
  { key: "netflix", name: "Netflix", color: "#E50914", keys: [["Skip Intro", I.skip], ["Next Episode", I.next], ["Subtitles", I.cc]], tiles: ["Night Harbor", "Quiet Orbit", "Paper Rooms", "Low Tide"] },
  { key: "youtube", name: "YouTube", color: "#FF3B30", keys: [["Captions", I.cc], ["Speed", I.speed], ["Theater", I.theater]], tiles: ["Slow Light", "Desk Tour", "Glass Hours", "Field Notes"] },
];
const rmBtn = (cls: string, g: string, label: string) => `<span class="rm-b ${cls}" data-k="${cls}">${svg(g)}<small>${label}</small></span>`;
export const remoteScreen = (a: RApp = RAPPS[0], typed = "") => `<div class="pt rm" style="--rc:${a.color}">
  <div class="rm-head"><b>Remote</b><span class="rm-chip"><i></i>${a.name}</span></div>
  <div class="rm-search">${svg(I.search)}<span class="rm-q ${typed ? "typed" : ""}">${typed || "Search " + a.name}</span></div>
  <div class="rm-pad"><span class="rm-d up">${svg(I.up)}</span><span class="rm-d down">${svg(I.down)}</span><span class="rm-d left">${svg(I.left)}</span><span class="rm-d right">${svg(I.right)}</span><span class="rm-ok">OK</span></div>
  <div class="rm-row">${rmBtn("back", I.back, "Back")}${rmBtn("home", I.home, "Home")}${rmBtn("mute", I.mute, "Mute")}</div>
  <div class="rm-tr"><span>${svg(I.back10)}</span><span class="pp">${svg(I.play)}</span><span>${svg(I.fwd10)}</span></div>
  <div class="rm-keys">${a.keys.map(([n, g]) => `<span class="rm-k">${svg(g)}${n}</span>`).join("")}</div>
</div>`;

function fitPt(screen: HTMLElement, land: boolean) {
  const apply = () => {
    const w = screen.clientWidth; if (!w) return;
    screen.querySelectorAll<HTMLElement>(".pt").forEach(pt => { pt.style.transform = `scale(${w / (land ? 874 : 402)})`; });
  };
  new ResizeObserver(apply).observe(screen); apply();
}

export function initRemote() {
  const stage = document.getElementById("rmStage"); if (!stage) return;
  const screen = stage.querySelector<HTMLElement>(".ip-screen")!;
  const tv = document.getElementById("rmTv")!, sw = document.getElementById("rmSwitch")!;
  let cur = 0, token = 0, visible = false;
  const draw = (typed = "") => {
    screen.innerHTML = remoteScreen(RAPPS[cur], typed); fitPt(screen, false);
    tv.style.setProperty("--rc", RAPPS[cur].color);
    tv.querySelector(".tv-title")!.textContent = RAPPS[cur].name;
    tv.querySelectorAll<HTMLElement>(".tv-t span").forEach((s, i) => { s.textContent = RAPPS[cur].tiles[i]; });
  };
  const tiles = () => Array.from(tv.querySelectorAll<HTMLElement>(".tv-t"));
  const focus = (i: number) => tiles().forEach((t, k) => t.classList.toggle("on", k === i));
  const press = (sel: string, ms = 160) => { const e = screen.querySelector<HTMLElement>(sel); if (!e) return; e.classList.add("hit"); setTimeout(() => e.classList.remove("hit"), ms); };
  const ok = () => token;

  async function loop(t: number) {
    const w = async (ms: number) => { await sleep(ms); if (t !== token) throw new Error("x"); };
    try {
      for (;;) {
        draw(); focus(0); tv.classList.remove("playing"); await w(1200);
        for (const [i, d] of [[1, ".right"], [2, ".right"], [3, ".right"], [0, ".left"]] as [number, string][]) {
          press(".rm-d" + d); focus(i); await w(900);
        }
        press(".rm-ok", 220); tv.classList.add("playing"); await w(1600);
        press(".rm-k:first-child", 260); tv.classList.add("skipped"); await w(1300);
        tv.classList.remove("playing", "skipped");
        press(".rm-b.back", 220); await w(900);
        const word = RAPPS[cur].tiles[1].split(" ")[0];
        for (let n = 1; n <= word.length; n++) { draw(word.slice(0, n)); await w(130); }
        await w(1400);
      }
    } catch { /* stopped */ }
  }
  const start = () => { token++; if (!reduce && visible) loop(token); };
  const pick = (i: number) => {
    cur = i; sw.querySelectorAll("button").forEach((b, k) => b.setAttribute("aria-checked", String(k === i)));
    token++; draw(); focus(0); if (!reduce && visible) loop(token);
  };
  RAPPS.forEach((a, i) => {
    const b = document.createElement("button");
    b.type = "button"; b.setAttribute("role", "radio"); b.setAttribute("aria-checked", String(i === 0));
    b.innerHTML = `${a.name}`; b.addEventListener("click", () => pick(i)); sw.appendChild(b);
  });
  draw(); focus(1);
  new IntersectionObserver(([e]) => { const v = e.isIntersecting; if (v === visible) return; visible = v; if (v) start(); else token++; }, { threshold: 0.3 }).observe(stage);
}

/* ---------- Layouts ---------- */
const keyRow = (s: string) => `<div>${[...s].map(c => `<span>${c}</span>`).join("")}</div>`;
const PANES: Record<string, { name: string; html: () => string }> = {
  trackpad: { name: "Trackpad", html: () => `<div class="lp-tp"><i class="a"></i><i class="b"></i><small>Trackpad</small></div>` },
  actions: { name: "Actions", html: () => `<div class="lp-h">${appIcon("web")}<b>Safari</b></div><div class="lp-grid">${
    [["New Tab", "plus.square.on.square", "#0A84FF"], ["Reload", "arrow.clockwise", "#0A84FF"], ["Reader", "doc.plaintext", "#30B0C7"], ["Next Tab", "chevron.right", "#34C759"], ["Do Not Disturb", "moon.fill", "#5E5CE6"], ["YouTube", "logo.youtube", "#FF3B30"], ["Screenshot", "camera.viewfinder", "#0A84FF"], ["GitHub", "logo.github", "#1A1A1A"]]
      .map(([n, g, c]) => `<div class="ax-t" style="--c:${c}">${glyph(g)}<span>${n}</span></div>`).join("")}</div>` },
  keyboard: { name: "Keyboard", html: () => `<div class="lp-echo">Start typing</div><div class="lp-kb">${keyRow("QWERTYUIOP")}${keyRow("ASDFGHJKL")}${keyRow("ZXCVBNM")}</div>` },
  media: { name: "Media", html: () => `<div class="lp-media"><i class="art"></i><b>Slow Light</b><span>Paper Rooms</span><div class="bar"><i></i></div><div class="ctl">${svg(GLYPH["backward.fill"])}${svg(GLYPH["playpause.fill"])}${svg(GLYPH["forward.fill"])}</div></div>` },
  remote: { name: "Remote", html: () => `<div class="lp-remote"><div class="rm-pad"><span class="rm-d up">${svg(I.up)}</span><span class="rm-d down">${svg(I.down)}</span><span class="rm-d left">${svg(I.left)}</span><span class="rm-d right">${svg(I.right)}</span><span class="rm-ok">OK</span></div></div>` },
  dock: { name: "Dock", html: () => `<div class="lp-h"><b>Dock</b></div><div class="lp-apps">${["finder", "web", "mail", "notes", "music", "xcode", "term", "set"].map(k => `<div>${appIcon(k)}<span>${APPS[k][0]}</span></div>`).join("")}</div>` },
};
const TEMPLATES: { name: string; a: string; b: string; at: number }[] = [
  { name: "Trackpad + Actions", a: "trackpad", b: "actions", at: 52 },
  { name: "Keyboard + Media", a: "keyboard", b: "media", at: 58 },
  { name: "Remote + Dock", a: "remote", b: "dock", at: 40 },
];

export function initLayouts() {
  const root = document.getElementById("lpStage"); if (!root) return;
  const screen = root.querySelector<HTMLElement>(".ip-screen")!;
  const chips = document.getElementById("lpChips")!;
  const cap = document.getElementById("lpCap")!;
  screen.innerHTML = `<div class="pt land lp"><div class="lp-a lp-pane"></div><div class="lp-div" role="separator" aria-orientation="vertical" aria-label="Divider. Drag to resize." tabindex="0"><i></i></div><div class="lp-b lp-pane"></div></div>`;
  fitPt(screen, true);
  const pt = screen.querySelector<HTMLElement>(".pt")!;
  const A = pt.querySelector<HTMLElement>(".lp-a")!, B = pt.querySelector<HTMLElement>(".lp-b")!, D = pt.querySelector<HTMLElement>(".lp-div")!;
  let at = 52;
  const setAt = (v: number, animate = false) => {
    at = Math.max(28, Math.min(72, v));
    pt.classList.toggle("anim", animate);
    pt.style.setProperty("--at", String(at));
    D.setAttribute("aria-valuenow", String(Math.round(at)));
  };
  const btns: HTMLButtonElement[] = [];
  const apply = (i: number) => {
    const t = TEMPLATES[i];
    A.innerHTML = PANES[t.a].html(); B.innerHTML = PANES[t.b].html();
    A.dataset.pane = t.a; B.dataset.pane = t.b;
    btns.forEach((b, k) => b.setAttribute("aria-checked", String(k === i)));
    setAt(t.at, true);
    cap.textContent = `${PANES[t.a].name} on the left, ${PANES[t.b].name} on the right. Drag the divider to resize.`;
  };
  TEMPLATES.forEach((t, i) => {
    const b = document.createElement("button");
    b.type = "button"; b.setAttribute("role", "radio"); b.textContent = t.name; b.addEventListener("click", () => apply(i));
    chips.appendChild(b); btns.push(b);
  });
  apply(0);
  // drag the divider; the stage is scaled, so measure in screen pixels
  let drag = false;
  const move = (e: PointerEvent) => {
    if (!drag) return;
    const r = pt.getBoundingClientRect();
    const x = (e.clientX - r.left) / r.width * 100;
    const lo = 7.5, hi = 96.5; // the content area inside the phone padding
    setAt((x - lo) / (hi - lo) * 100);
  };
  D.addEventListener("pointerdown", e => { drag = true; D.setPointerCapture(e.pointerId); pt.classList.remove("anim"); pt.classList.add("drag"); btns.forEach(b => b.setAttribute("aria-checked", "false")); cap.textContent = "Your own layout. Saved on the phone."; });
  D.addEventListener("pointermove", move);
  const end = () => { drag = false; pt.classList.remove("drag"); };
  D.addEventListener("pointerup", end); D.addEventListener("pointercancel", end);
  D.addEventListener("keydown", e => { const d = e.key === "ArrowRight" ? 4 : e.key === "ArrowLeft" ? -4 : 0; if (d) { e.preventDefault(); setAt(at + d); } });
  // one gentle nudge when it first scrolls into view, so the divider reads as movable
  if (!reduce) new IntersectionObserver(([e], o) => { if (!e.isIntersecting) return; o.disconnect(); setTimeout(() => { if (!drag) { setAt(at + 7, true); setTimeout(() => !drag && setAt(at - 7, true), 700); } }, 600); }, { threshold: 0.6 }).observe(root);
}

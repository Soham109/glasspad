import { appIcon } from "./apps";
import { glyph } from "./glyphs";
import { phone, fitAll, tl, reduce, Scene, Cancel } from "./kit";

/* Layouts: up to three modes on one screen. The geometry follows ScreenLayout.arrangement in
   GlasspadKit: two panes share the main split, a third splits the second pane, and a divider
   rests on thirds or the middle when it is let go near them (DividerMath.snapPoints). */

const SNAPS = [1 / 3, 0.5, 2 / 3];
const GAP = 12;
const AREA = { x: 52, y: 14, w: 874 - 52 - 14, h: 402 - 28 }; // inside the island and the corners

const PANES: Record<string, { name: string; dark?: boolean; html: () => string }> = {
  trackpad: { name: "Trackpad", html: () => `<div class="pz-tp"><i></i><i></i></div>` },
  actions: { name: "Actions", html: () => `<div class="pz-ac"><div class="af"><span class="af-i">${appIcon("web")}</span><div><b>Safari</b><span>In front on your Mac</span></div></div>
    <div class="ag">${tl("New Tab", "plus.square.on.square", "#0A84FF")}${tl("Reopen Tab", "arrow.uturn.backward", "#0A84FF")}${tl("Reader", "doc.plaintext", "#30B0C7")}${tl("Split Screen", "square.split.2x1", "#30B0C7")}${tl("Do Not Disturb", "moon.fill", "#5E5CE6")}${tl("Screenshot", "camera.viewfinder", "#0A84FF")}</div></div>` },
  media: { name: "Media", html: () => `<div class="pz-md"><div class="src"><i></i>SPOTIFY</div><b>Slow Light</b><span>Paper Rooms</span><div class="ctl">${glyph("backward.fill")}<span class="pp">${glyph("pause.fill")}</span>${glyph("forward.fill")}</div></div>` },
  remote: { name: "Remote", dark: true, html: () => `<div class="pz-rm"><div class="pad"><b>Tap to play or pause</b><span>Swipe sideways to skip</span></div></div>` },
  clock: { name: "Clock", dark: true, html: () => `<div class="pz-clk"><span>Fri, 16 Oct</span><b>10</b><b>09</b></div>` },
  nowPlaying: { name: "Now Playing", dark: true, html: () => `<div class="pz-np"><span class="art"><i class="s1"></i><i class="s2"></i><i class="s3"></i></span><b>Slow Light</b><small>Paper Rooms</small></div>` },
  present: { name: "Present", html: () => `<div class="pz-pr"><div class="time">4:12</div><div class="bn"><span class="b">${glyph("chevron.left")}Back</span><span class="n">${glyph("chevron.right")}Next</span></div></div>` },
};
/* A few of the gallery's templates (LayoutTemplates.swift) */
const TEMPLATES = [
  { name: "Desk", panes: ["trackpad", "actions"], split: 0.6, inner: 0.5 },
  { name: "Studio", panes: ["trackpad", "media", "actions"], split: 0.5, inner: 0.36 },
  { name: "Couch", panes: ["remote", "trackpad"], split: 0.6, inner: 0.5 },
  { name: "StandBy", panes: ["clock", "nowPlaying"], split: 0.5, inner: 0.5 },
];

type Rect = { x: number; y: number; w: number; h: number };
/** Splits a rect at a share with a gap between, side by side or stacked: [first, second, line]. */
function cut(r: Rect, share: number, across: boolean): [Rect, Rect, Rect] {
  const len = across ? r.w : r.h, a = (len - GAP) * share, b = len - GAP - a;
  return across
    ? [{ ...r, w: a }, { x: r.x + a + GAP, y: r.y, w: b, h: r.h }, { x: r.x + a, y: r.y, w: GAP, h: r.h }]
    : [{ ...r, h: a }, { x: r.x, y: r.y + a + GAP, w: r.w, h: b }, { x: r.x, y: r.y + a, w: r.w, h: GAP }];
}
const innerAcross = (rest: Rect) => rest.w > rest.h * 1.6;

export function initLayouts() {
  const root = document.getElementById("lpStage"); if (!root) return;
  root.innerHTML = phone("landscape", "light", `<div class="pt land lp"><div class="lp-snaps"></div></div>`);
  fitAll(root);
  const pt = root.querySelector<HTMLElement>(".pt")!, snaps = pt.querySelector<HTMLElement>(".lp-snaps")!;
  const chips = document.getElementById("lpChips")!;
  let t = TEMPLATES[0], split = t.split, inner = t.inner;
  const panes: HTMLElement[] = [], divs: HTMLElement[] = [], lines: Rect[] = [];
  const btns: HTMLButtonElement[] = [];

  const layout = () => {
    const [a, rest, line] = cut(AREA, split, true);
    const rects: Rect[] = [a]; lines.length = 0; lines.push(line);
    if (t.panes.length === 3) { const [b, c, l2] = cut(rest, inner, innerAcross(rest)); rects.push(b, c); lines.push(l2); }
    else rects.push(rest);
    const put = (el: HTMLElement, r: Rect) => { el.style.transform = `translate(${r.x}px, ${r.y}px)`; el.style.width = r.w + "px"; el.style.height = r.h + "px"; };
    panes.forEach((p, i) => put(p, rects[i]));
    divs.forEach((d, i) => { put(d, lines[i]); d.setAttribute("aria-valuenow", String(Math.round((i ? inner : split) * 100))); });
  };
  const build = (i: number) => {
    t = TEMPLATES[i]; split = t.split; inner = t.inner;
    panes.splice(0).forEach(p => p.remove()); divs.splice(0).forEach(d => d.remove());
    t.panes.forEach(k => {
      const p = document.createElement("div"); p.className = "lp-pane" + (PANES[k].dark ? " dk" : ""); p.dataset.pane = k;
      p.innerHTML = PANES[k].html(); pt.appendChild(p); panes.push(p);
    });
    t.panes.slice(1).forEach((_, j) => {
      const d = document.createElement("div"); d.className = "lp-div" + (j ? " inner" : "");
      d.setAttribute("role", "separator"); d.setAttribute("tabindex", "0");
      d.setAttribute("aria-orientation", j ? "horizontal" : "vertical"); d.setAttribute("aria-label", j ? "Second divider. Drag to resize." : "Divider. Drag to resize.");
      d.setAttribute("aria-valuemin", "0"); d.setAttribute("aria-valuemax", "100");
      d.innerHTML = "<i></i>"; pt.appendChild(d); divs.push(d); wire(d, j);
    });
    btns.forEach((b, k) => b.setAttribute("aria-checked", String(k === i)));
    layout();
  };

  // snap marks: shown while a divider moves; the one it will rest on lights up
  const showSnaps = (level: number, value: number | null) => {
    if (value === null) { snaps.classList.remove("on"); return; }
    const [, rest] = cut(AREA, split, true);
    const span = level ? rest : AREA, across = level ? innerAcross(rest) : true;
    snaps.classList.add("on");
    snaps.innerHTML = SNAPS.map(v => {
      const near = Math.abs(v - value) < 0.04;
      const pos = across
        ? `left:${span.x + (span.w - GAP) * v + GAP / 2}px;top:${span.y}px;height:${span.h}px`
        : `top:${span.y + (span.h - GAP) * v + GAP / 2}px;left:${span.x}px;width:${span.w}px`;
      return `<i class="${across ? "v" : "h"}${near ? " near" : ""}" style="${pos}"></i>`;
    }).join("");
  };
  const snap = (v: number) => { const b = SNAPS.reduce((p, c) => Math.abs(c - v) < Math.abs(p - v) ? c : p); return Math.abs(b - v) < 0.06 ? b : v; };
  const set = (level: number, v: number) => { v = Math.min(0.8, Math.max(0.2, v)); if (level) inner = v; else split = v; layout(); return v; };
  const settleAnim = () => { pt.classList.add("anim"); setTimeout(() => pt.classList.remove("anim"), 500); };

  // drag a divider; the screen is scaled, so measure against the drawn point box
  function wire(d: HTMLElement, level: number) {
    let drag = false;
    const share = (e: PointerEvent) => {
      const r = pt.getBoundingClientRect(), k = r.width / 874;
      const x = (e.clientX - r.left) / k, y = (e.clientY - r.top) / k;
      if (!level) return (x - AREA.x) / AREA.w;
      const [, rest] = cut(AREA, split, true);
      return innerAcross(rest) ? (x - rest.x) / rest.w : (y - rest.y) / rest.h;
    };
    d.addEventListener("pointerdown", e => { drag = true; stopAuto(); d.setPointerCapture(e.pointerId); pt.classList.add("drag"); });
    d.addEventListener("pointermove", e => { if (drag) showSnaps(level, set(level, share(e))); });
    const end = () => { if (!drag) return; drag = false; pt.classList.remove("drag"); settleAnim(); set(level, snap(level ? inner : split)); showSnaps(level, null); };
    d.addEventListener("pointerup", end); d.addEventListener("pointercancel", end);
    d.addEventListener("keydown", e => {
      const keys = level ? ["ArrowUp", "ArrowDown"] : ["ArrowLeft", "ArrowRight"];
      const i = keys.indexOf(e.key); if (i < 0) return;
      e.preventDefault(); stopAuto();
      const cur = level ? inner : split;
      const next = i ? SNAPS.find(v => v > cur + 0.01) ?? cur : [...SNAPS].reverse().find(v => v < cur - 0.01) ?? cur;
      settleAnim(); set(level, next);
    });
  }

  TEMPLATES.forEach((tp, i) => {
    const b = document.createElement("button");
    b.type = "button"; b.setAttribute("role", "radio"); b.textContent = tp.name;
    b.addEventListener("click", () => { stopAuto(); build(i); });
    chips.appendChild(b); btns.push(b);
  });
  build(0);

  // Left alone, a finger drags the divider past the thirds and lets go near one; then the Desk template.
  let token = 0, visible = false, auto = !reduce, sc: Scene | null = null;
  function stopAuto() { auto = false; token++; sc?.clear(); }
  async function play(tk: number) {
    const s = sc = new Scene(root!.querySelector<HTMLElement>(".ip-screen")!, root!, () => tk === token && visible && auto && !document.hidden);
    const mid = (level: number) => { const l = lines[level]; return [l.x + l.w / 2, l.y + l.h / 2]; };
    const drag = async (level: number, to: number, ms: number) => {
      const from = level ? inner : split;
      let [fx, fy] = mid(level);
      await s.touch(0, fx, fy);
      await s.tween(ms, e => { showSnaps(level, set(level, from + (to - from) * e)); [fx, fy] = mid(level); s.put(0, fx, fy); });
      settleAnim(); set(level, snap(to)); showSnaps(level, null); [fx, fy] = mid(level);
      await s.lift(0, fx, fy);
    };
    try {
      for (;;) {
        await s.wait(1200);
        await drag(0, 0.35, 1100); await s.wait(1300);
        await drag(0, 0.64, 1200); await s.wait(1600);
        build(1); await s.wait(1600);
        await drag(1, 0.52, 900); await s.wait(2000);
        build(0);
      }
    } catch (e) { s.clear(); if (!(e instanceof Cancel)) throw e; }
  }
  new IntersectionObserver(([e]) => { const v = e.isIntersecting; if (v === visible) return; visible = v; token++; if (v && auto) play(token); }, { threshold: 0.5 }).observe(root);
}

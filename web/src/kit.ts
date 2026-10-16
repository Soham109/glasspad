import { lerp, minJerk, nextFrame, reducedMotion, sleep } from "./spring";
import { glyph } from "./glyphs";
import { appIcon } from "./apps";

/* Shared pieces for the drawn screens: the phone, tiles as the app draws them, and a small
   animation runner whose loops stop when they scroll out of view. */

export const reduce = reducedMotion();

export const phone = (orient: "portrait" | "landscape", finish: "light" | "dark", inner = "", id = "") =>
  `<div class="iphone" data-orient="${orient}" data-finish="${finish}"${id ? ` id="${id}"` : ""}>
    <i class="ip-btn l action"></i><i class="ip-btn l up"></i><i class="ip-btn l down"></i><i class="ip-btn r side"></i><i class="ip-btn r cam"></i>
    <div class="ip-body"><div class="ip-bezel"></div><div class="ip-screen">${inner}</div><div class="ip-island"></div></div>
  </div>`;

/** Scales every point-sized screen (.pt) inside a phone to the drawn screen. */
export function fitPt(screen: HTMLElement) {
  const apply = () => {
    const w = screen.clientWidth; if (!w) return;
    screen.querySelectorAll<HTMLElement>(":scope > .pt").forEach(pt => { pt.style.transform = `scale(${w / (pt.classList.contains("land") ? 874 : 402)})`; });
  };
  new ResizeObserver(apply).observe(screen); apply();
}
export const fitAll = (root: ParentNode) => root.querySelectorAll<HTMLElement>(".ip-screen").forEach(fitPt);

/** A button as Actions draws it: a soft tinted circle with the symbol, the name below. */
export const tl = (name: string, g: string, color: string, extra = "") =>
  `<div class="bt" data-b="${name}" style="--c:${color}"${extra}><span class="bt-c">${glyph(g)}</span><span class="bt-n">${name}</span></div>`;
/** A button that opens an app or a website: the icon itself instead of the circle. */
export const tlIcon = (name: string, icon: string, extra = "") =>
  `<div class="bt" data-b="${name}"${extra}><span class="bt-i">${icon}</span><span class="bt-n">${name}</span></div>`;
export const tlApp = (name: string, key: string) => tlIcon(name, appIcon(key));
export const tlAdd = () => `<div class="bt add"><span class="bt-c">${glyph("plus")}</span><span class="bt-n">Add</span></div>`;

export class Cancel extends Error {}

/** Runs one scene's steps with finger dots on a phone screen; every wait throws once cancelled. */
export class Scene {
  constructor(public ph: HTMLElement, public mac: HTMLElement, private alive: () => boolean) {}
  q<T extends Element = HTMLElement>(sel: string, root: Element = this.ph) { return root.querySelector(sel) as unknown as T; }
  m<T extends Element = HTMLElement>(sel: string) { return this.mac.querySelector(sel) as unknown as T; }
  check() { if (!this.alive()) throw new Cancel(); }
  async wait(ms: number) { await sleep(ms); this.check(); }
  async tween(ms: number, fn: (e: number, u: number) => void, ease = minJerk) {
    const t0 = performance.now();
    for (;;) { const t = await nextFrame(); this.check(); const u = Math.min(1, (t - t0) / ms); fn(ease(u), u); if (u >= 1) return; }
  }
  /** Center of an element in its screen's own points. */
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
  /** Touch at a point, slide to another, lift. `during` gets the eased progress. */
  async swipe(x0: number, y0: number, x1: number, y1: number, ms = 520, during?: (e: number) => void) {
    await this.touch(0, x0, y0);
    await this.tween(ms, e => { this.put(0, lerp(x0, x1, e), lerp(y0, y1, e)); during?.(e); });
    await this.lift(0, x1, y1);
  }
  clear() { this.fingers.forEach(f => f.remove()); this.fingers = []; this.ph.querySelectorAll(".ms-ripple").forEach(r => r.remove()); }
}

/** Calls `run` over and over while `el` is on screen. `reset` puts the drawing back each time. */
export function loopInView(el: Element, ph: HTMLElement, mac: HTMLElement, run: (s: Scene) => Promise<void>, reset?: () => void) {
  let token = 0, visible = false;
  const go = async (t: number) => {
    const s = new Scene(ph, mac, () => t === token && visible && !document.hidden);
    try { for (;;) { reset?.(); await s.wait(500); await run(s); s.clear(); } }
    catch (e) { s.clear(); if (!(e instanceof Cancel)) throw e; }
  };
  reset?.();
  if (reduce) return { restart() { reset?.(); } };
  const start = () => { token++; if (visible && !document.hidden) go(token); };
  new IntersectionObserver(([e]) => { const v = e.isIntersecting; if (v === visible) return; visible = v; start(); }, { threshold: 0.25 }).observe(el);
  document.addEventListener("visibilitychange", () => { if (!document.hidden) start(); });
  return { restart: start };
}

/** Swaps a tile's contents in place: it dips and settles, like the app does when the front app changes. */
export function settle(els: Element[], delay = 28) {
  if (reduce) return;
  els.forEach((el, j) => (el as HTMLElement).animate([{ opacity: 0, transform: "scale(0.9)" }, { opacity: 1, transform: "none" }],
    { duration: 520, delay: j * delay, easing: "cubic-bezier(.3,1.3,.5,1)", fill: "backwards" }));
}

import { Spring, damp, clamp, lerp, minJerk, reducedMotion, nextFrame, sleep } from "./spring";
import { settings } from "./settings";

/* ---------- Types ---------- */
type Kind = "move" | "click" | "right" | "scroll" | "pinch" | "spaces" | "mission" | "drag3";
interface Finger {
  id: string;
  tx: number; ty: number;           // where the finger really is
  x: Spring; y: Spring;             // where the dot is drawn
  alpha: Spring; scale: Spring;
  alive: boolean;
  smooth: boolean;                  // mouse: dot trails the pointer on a spring
  trail: { x: number; y: number; t: number }[];
  el: HTMLDivElement; path: SVGPathElement;
}

const CAPTIONS: Record<Kind, string> = {
  move: "Move the pointer",
  click: "Tap to click",
  right: "Two finger tap to right click",
  scroll: "Two finger scroll",
  pinch: "Pinch to zoom",
  spaces: "Swipe between Spaces",
  mission: "Mission Control",
  drag3: "Three finger drag",
};
const CHIP_FOR: Partial<Record<Kind, string>> = { move: "move", click: "click", right: "click", scroll: "scroll", pinch: "pinch", spaces: "spaces", mission: "mission" };

export function initDemo() {
  const section = document.getElementById("try")!;
  const surface = document.getElementById("surface") as HTMLDivElement;
  const dotsLayer = document.getElementById("dots") as HTMLDivElement;
  const trails = document.getElementById("trails") as unknown as SVGSVGElement;
  const captionBox = document.querySelector(".caption") as HTMLDivElement;
  const phone = document.getElementById("phone") as HTMLDivElement;
  const viewport = document.querySelector(".mac-viewport") as HTMLDivElement;
  const spacesEl = document.getElementById("spaces") as HTMLDivElement;
  const win = document.getElementById("win") as HTMLDivElement;
  const winB = document.querySelector(".win-b") as HTMLDivElement;
  const doc = document.getElementById("doc") as HTMLDivElement;
  const cursor = document.getElementById("cursor") as unknown as SVGSVGElement;
  const spaceDots = Array.from(document.querySelectorAll<HTMLElement>("#macSpaces i"));
  const chips = Array.from(document.querySelectorAll<HTMLButtonElement>(".chip"));
  const reduce = reducedMotion();
  const isTouch = matchMedia("(hover: none) and (pointer: coarse)").matches;

  section.dataset.theme = "paper";
  const lede = section.querySelector<HTMLElement>(".lede");
  if (lede && isTouch) lede.textContent = lede.dataset.touchCopy || lede.textContent;

  // Document lines inside the Mac window
  const lines: string[] = [];
  for (let s = 0; s < 6; s++) {
    lines.push('<i class="h"></i>');
    const n = 4 + (s % 3);
    for (let i = 0; i < n; i++) lines.push(`<i style="width:${[96, 88, 92, 70, 84, 60][(i + s) % 6]}%"></i>`);
    if (s % 2 === 0) lines.push('<i class="img"></i>');
  }
  doc.innerHTML = lines.join("");

  /* ---------- Sizes ---------- */
  let W = 300, H = 650, DS = 34, VW = 400, VH = 240, docH = 800, winH = 160;
  const measure = () => {
    W = surface.clientWidth; H = surface.clientHeight;
    DS = Math.round(Math.min(W, H) * 0.11);
    surface.style.setProperty("--ds", DS + "px");
    trails.setAttribute("viewBox", `0 0 ${W} ${H}`);
    VW = viewport.clientWidth; VH = viewport.clientHeight;
    docH = doc.scrollHeight; winH = (win.querySelector(".win-body") as HTMLElement).clientHeight;
  };
  measure();
  new ResizeObserver(() => { measure(); kick(); }).observe(surface);

  /* ---------- Mac state ---------- */
  const cur = { x: VW * 0.5, y: VH * 0.45 };
  const docY = new Spring(0, 170, damp(170));
  const docS = new Spring(1, 220, damp(220, 0.8));
  const space = new Spring(0, 200, damp(200, 0.85));
  const mission = new Spring(0, 220, damp(220, 0.82));
  const winX = new Spring(0, 260, damp(260)), winY = new Spring(0, 260, damp(260));
  let momentum = 0; // px per second, for scroll after lift
  const docMin = () => Math.min(0, winH - docH * docS.x - 24);
  const rubber = (x: number, lo: number, hi: number, dim: number) => {
    if (x < lo) { const o = lo - x; return lo - (1 - 1 / (o * 0.55 / dim + 1)) * dim; }
    if (x > hi) { const o = x - hi; return hi + (1 - 1 / (o * 0.55 / dim + 1)) * dim; }
    return x;
  };
  const gain = () => (VW / Math.max(W, 1)) * 0.6 * (0.45 + settings.speed * 0.367);

  /* ---------- Fingers ---------- */
  const fingers = new Map<string, Finger>();
  function finger(id: string, x: number, y: number, smooth = false): Finger {
    let f = fingers.get(id);
    if (f && f.alive) { f.tx = x; f.ty = y; return f; }
    if (f) { f.el.remove(); f.path.remove(); fingers.delete(id); }
    const el = document.createElement("div"); el.className = "dot"; dotsLayer.appendChild(el);
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path"); trails.appendChild(path);
    const k = smooth ? 700 : 2400;
    f = {
      id, tx: x, ty: y, x: new Spring(x, k, damp(k)), y: new Spring(y, k, damp(k)),
      alpha: new Spring(0, 400, damp(400)), scale: new Spring(reduce ? 1 : 0.72, 520, damp(520, 0.6)),
      alive: true, smooth, trail: [], el, path,
    };
    f.alpha.target = 1; f.scale.target = 1;
    if (reduce) { f.alpha.set(1); }
    fingers.set(id, f);
    return f;
  }
  function lift(id: string) {
    const f = fingers.get(id); if (!f || !f.alive) return;
    f.alive = false; f.alpha.target = 0; f.scale.target = 1.12;
    if (reduce) f.alpha.set(0);
  }
  function ring(x: number, y: number) {
    if (reduce) return;
    const r = document.createElement("div"); r.className = "ring";
    r.style.transform = `translate(${x}px, ${y}px)`;
    dotsLayer.appendChild(r); setTimeout(() => r.remove(), 600);
  }

  /* ---------- Caption + chips ---------- */
  let captionText = "";
  function caption(text: string, kind?: Kind) {
    chips.forEach(c => c.classList.toggle("active", !!kind && c.dataset.g === CHIP_FOR[kind]));
    if (text === captionText) return;
    captionText = text;
    const old = captionBox.querySelector(".caption-text:not(.out)");
    if (old) { old.classList.remove("enter"); old.classList.add("out"); setTimeout(() => old.remove(), 300); }
    const span = document.createElement("span");
    span.className = "caption-text enter"; span.id = "caption"; span.textContent = text;
    if (old) old.id = "";
    captionBox.appendChild(span);
  }
  captionBox.innerHTML = "";
  caption(isTouch ? "Put a finger on the glass" : "Move the pointer");

  /* ---------- Recognizer: works on full snapshots of the fingers that are down ---------- */
  type Pt = { x: number; y: number };
  let session: { t0: number; maxN: number; moved: number } | null = null;
  let base: { n: number; c: Pt; d: number; cur: Pt; space: number; mission: number; docS: number; win: Pt; kind: Kind | null } | null = null;
  let lastC: Pt | null = null, lastT = 0, vel = { x: 0, y: 0 };
  const centroid = (p: Pt[]) => ({ x: p.reduce((s, q) => s + q.x, 0) / p.length, y: p.reduce((s, q) => s + q.y, 0) / p.length });
  const spread = (p: Pt[], c: Pt) => p.reduce((s, q) => s + Math.hypot(q.x - c.x, q.y - c.y), 0) / p.length;

  function snapshot(pts: Pt[]) {
    const now = performance.now();
    const n = pts.length;
    if (n === 0) { endGesture(now); return; }
    if (!session) session = { t0: now, maxN: 0, moved: 0 };
    session.maxN = Math.max(session.maxN, n);
    const c = centroid(pts), d = spread(pts, c);
    if (!base || base.n !== n) {
      if (base) releaseGesture();
      base = { n, c, d, cur: { ...cur }, space: space.x, mission: mission.x, docS: docS.x, win: { x: winX.x, y: winY.x }, kind: null };
      lastC = c; lastT = now; vel = { x: 0, y: 0 }; momentum = 0;
      docY.set(docY.x); docS.set(docS.x); space.set(space.x); mission.set(mission.x);
      return;
    }
    const dx = c.x - base.c.x, dy = c.y - base.c.y;
    const fdx = c.x - (lastC?.x ?? c.x), fdy = c.y - (lastC?.y ?? c.y);
    const dt = Math.max(1, now - lastT);
    vel = { x: lerp(vel.x, fdx / dt * 1000, 0.4), y: lerp(vel.y, fdy / dt * 1000, 0.4) };
    lastC = c; lastT = now;
    session.moved = Math.max(session.moved, Math.hypot(dx, dy), Math.abs(d - base.d));

    const four = settings.drag; // with three finger drag on, Spaces and Mission Control move to four fingers
    if (!base.kind) {
      if (n === 1 && Math.hypot(dx, dy) > 4) base.kind = "move";
      else if (n === 2) {
        if (Math.abs(d - base.d) > 16) base.kind = "pinch";
        else if (Math.hypot(dx, dy) > 10) base.kind = "scroll";
      } else if (n >= 3 && Math.hypot(dx, dy) > 14) {
        if (n === 3 && four) base.kind = "drag3";
        else base.kind = Math.abs(dx) > Math.abs(dy) ? "spaces" : "mission";
      }
      if (base.kind) {
        if (base.kind === "mission" && !settings.mission) caption("Mission Control is off on your Mac");
        else caption(CAPTIONS[base.kind], base.kind);
      }
    }
    const g = gain();
    switch (base.kind) {
      case "move":
        cur.x = clamp(cur.x + fdx * g, 0, VW - 4); cur.y = clamp(cur.y + fdy * g, 0, VH - 4); break;
      case "scroll": {
        const sign = settings.natural ? 1 : -1;
        const want = docY.x + fdy * sign * (VH / H) * 2.2;
        docY.set(rubber(want, docMin(), 0, VH * 0.5)); break;
      }
      case "pinch": docS.set(rubber(base.docS * (d / base.d), 0.85, 2.2, 0.6)); break;
      case "spaces": space.set(rubber(base.space - dx / (W * 0.62), 0, 2, 0.5)); break;
      case "mission": if (settings.mission) mission.set(clamp(base.mission - dy / (H * 0.24), 0, 1)); break;
      case "drag3":
        winX.set(clamp(base.win.x + dx * g, -VW * 0.12, VW * 0.3)); winY.set(clamp(base.win.y + dy * g, -VH * 0.08, VH * 0.18)); break;
    }
    kick();
  }
  function releaseGesture() {
    if (!base) return;
    switch (base.kind) {
      case "scroll":
        momentum = (settings.natural ? 1 : -1) * vel.y * (VH / H) * 2.2;
        if (reduce) momentum = 0;
        break;
      case "pinch": docS.target = clamp(docS.x, 1, 2); break;
      case "spaces": {
        const target = clamp(Math.round(space.x - clamp(vel.x / 1400, -0.45, 0.45)), 0, 2);
        if (target !== Math.round(base.space)) hapticAtCentroid();
        space.target = target; break;
      }
      case "mission": {
        const target = clamp(Math.round(mission.x - clamp(vel.y / 1600, -0.4, 0.4)), 0, 1);
        if (target !== Math.round(base.mission)) hapticAtCentroid();
        mission.target = target; break;
      }
    }
    if (reduce) { docS.set(docS.target); space.set(space.target); mission.set(mission.target); }
    base = null;
  }
  function endGesture(now: number) {
    const s = session;
    releaseGesture();
    session = null;
    if (s && now - s.t0 < 320 && s.moved < 10) {
      if (s.maxN === 1) click();
      else if (s.maxN === 2) rightClick();
    }
    kick();
  }
  function hapticAtCentroid() {
    const alive = [...fingers.values()].filter(f => f.alive);
    if (!alive.length) return;
    const c = centroid(alive.map(f => ({ x: f.tx, y: f.ty })));
    ring(c.x, c.y);
  }

  /* ---------- Clicks on the Mac ---------- */
  let menu: HTMLDivElement | null = null;
  function click() {
    caption(CAPTIONS.click, "click");
    cursor.classList.add("press"); setTimeout(() => cursor.classList.remove("press"), 140);
    if (menu) { menu.remove(); menu = null; }
    if (mission.target === 1) { mission.target = 0; kick(); }
    if (navigator.vibrate && isTouch) try { navigator.vibrate(6); } catch { /* not allowed */ }
  }
  function rightClick() {
    caption(CAPTIONS.right, "right");
    if (menu) menu.remove();
    menu = document.createElement("div");
    menu.className = "ctx";
    menu.innerHTML = "<i></i><i></i><i></i><i></i>";
    const mx = Math.min(cur.x + 6, VW - 92), my = Math.min(cur.y + 6, VH - 70);
    menu.style.transform = `translate(${mx}px, ${my}px)`;
    viewport.appendChild(menu);
    const m = menu; setTimeout(() => { m.classList.add("bye"); setTimeout(() => m.remove(), 300); if (menu === m) menu = null; }, 1300);
  }

  /* ---------- Render loop: runs only while something moves ---------- */
  let running = false, lastFrame = 0;
  function kick() { if (!running) { running = true; lastFrame = performance.now(); requestAnimationFrame(frame); } }
  function frame(t: number) {
    const dt = Math.min(0.05, (t - lastFrame) / 1000); lastFrame = t;
    let busy = false;
    for (const f of fingers.values()) {
      f.x.target = f.tx; f.y.target = f.ty;
      if (reduce || !f.smooth) { f.x.set(f.tx); f.y.set(f.ty); }
      f.x.step(dt); f.y.step(dt); f.alpha.step(dt); f.scale.step(dt);
      const now = t;
      const lastP = f.trail[f.trail.length - 1];
      if (f.alive && !reduce && (!lastP || Math.hypot(lastP.x - f.x.x, lastP.y - f.y.x) > 0.6)) f.trail.push({ x: f.x.x, y: f.y.x, t: now });
      while (f.trail.length && now - f.trail[0].t > 200) f.trail.shift();
      f.el.style.transform = `translate(${f.x.x.toFixed(2)}px, ${f.y.x.toFixed(2)}px) scale(${f.scale.x.toFixed(3)})`;
      f.el.style.opacity = Math.max(0, f.alpha.x).toFixed(3);
      if (f.trail.length > 1) {
        f.path.setAttribute("d", "M" + f.trail.map(p => `${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(" L") + ` L${f.x.x.toFixed(1)} ${f.y.x.toFixed(1)}`);
        f.path.setAttribute("stroke-width", String(DS * 0.62 * f.scale.x));
        f.path.style.opacity = Math.max(0, f.alpha.x).toFixed(3);
      } else f.path.removeAttribute("d");
      if (!f.alive && f.alpha.x < 0.01 && !f.trail.length) { f.el.remove(); f.path.remove(); fingers.delete(f.id); continue; }
      busy = true;
    }
    // scroll momentum, decaying like macOS (about 0.95 every 8 ms)
    if (momentum !== 0 && !base) {
      docY.set(docY.x + momentum * dt);
      momentum *= Math.pow(0.95, (dt * 1000) / 8);
      if (docY.x < docMin() || docY.x > 0) momentum *= 0.6;
      if (Math.abs(momentum) < 8) momentum = 0;
      busy = true;
    } else if (!base) {
      const lo = docMin();
      docY.target = clamp(docY.target, lo, 0);
      if (docY.x < lo - 0.5 || docY.x > 0.5) docY.target = clamp(docY.x, lo, 0);
    }
    for (const s of [docY, docS, space, mission, winX, winY]) { s.step(dt); if (!s.settled) busy = true; }

    // Mac
    cursor.style.transform = `translate(${cur.x.toFixed(1)}px, ${cur.y.toFixed(1)}px)`;
    doc.style.transform = `translateY(${docY.x.toFixed(2)}px) scale(${docS.x.toFixed(4)})`;
    spacesEl.style.transform = `translateX(${(-space.x * VW).toFixed(2)}px)`;
    const m = mission.x;
    win.style.transform = `translate(${(winX.x - VW * 0.1 * m).toFixed(1)}px, ${(winY.x + VH * 0.08 * m).toFixed(1)}px) scale(${(1 - 0.36 * m).toFixed(4)})`;
    winB.style.transform = `translate(${(VW * 0.04 * m).toFixed(1)}px, ${(-VH * 0.1 * m).toFixed(1)}px) scale(${(1 - 0.2 * m).toFixed(4)})`;
    const si = Math.round(clamp(space.x, 0, 2));
    spaceDots.forEach((d, i) => d.classList.toggle("on", i === si));

    if (busy || base || wheelActive) requestAnimationFrame(frame); else running = false;
  }

  /* ---------- Real input ---------- */
  const touches = new Map<number, Pt>();
  let lastHover = 0, hovering = false, scriptToken = 0, scripting = false;
  const local = (e: PointerEvent | WheelEvent | MouseEvent) => { const r = surface.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
  const pushTouches = () => snapshot([...touches.values()]);
  const takeOver = () => { if (scripting) { scriptToken++; scripting = false; clearScriptFingers(); } };

  surface.addEventListener("pointerdown", e => {
    takeOver();
    const p = local(e);
    if (e.pointerType === "mouse") {
      if (e.button === 2) return;
      const f = finger("mouse", p.x, p.y, true); f.scale.target = 0.86;
      ring(p.x, p.y); click(); kick(); return;
    }
    surface.setPointerCapture(e.pointerId);
    touches.set(e.pointerId, p); finger("t" + e.pointerId, p.x, p.y);
    pushTouches(); kick();
    e.preventDefault();
  });
  surface.addEventListener("pointermove", e => {
    const p = local(e);
    if (e.pointerType === "mouse") {
      takeOver();
      const now = performance.now();
      const f = fingers.get("mouse");
      if (f && f.alive) {
        const g = gain();
        cur.x = clamp(cur.x + (p.x - f.tx) * g, 0, VW - 4); cur.y = clamp(cur.y + (p.y - f.ty) * g, 0, VH - 4);
        if (now - lastHover > 60 && !wheelActive) caption(CAPTIONS.move, "move");
      }
      finger("mouse", p.x, p.y, true);
      lastHover = now; hovering = true; kick(); return;
    }
    if (!touches.has(e.pointerId)) return;
    touches.set(e.pointerId, p); finger("t" + e.pointerId, p.x, p.y);
    pushTouches();
  });
  const up = (e: PointerEvent) => {
    if (e.pointerType === "mouse") { const f = fingers.get("mouse"); if (f) f.scale.target = 1; kick(); return; }
    if (!touches.has(e.pointerId)) return;
    touches.delete(e.pointerId); lift("t" + e.pointerId);
    pushTouches(); kick();
  };
  surface.addEventListener("pointerup", up);
  surface.addEventListener("pointercancel", up);
  surface.addEventListener("pointerleave", e => { if (e.pointerType === "mouse") { hovering = false; lift("mouse"); endWheel(); kick(); } });
  surface.addEventListener("contextmenu", e => e.preventDefault());

  /* Wheel: two finger scroll and trackpad pinch from a desktop */
  let wheelActive = false, wheelTimer = 0, wheelOff = 0, pinchLog = 0, wheelKind: "scroll" | "pinch" = "scroll";
  const wheelOffS = new Spring(0, 300, damp(300));
  function wheelFingers(p: Pt) {
    const gap = DS * 1.25;
    if (wheelKind === "scroll") {
      const oy = clamp(wheelOff, -70, 70);
      finger("w1", p.x - gap / 2, p.y + oy); finger("w2", p.x + gap / 2, p.y + oy);
    } else {
      const s = clamp(gap * 0.8 * Math.exp(pinchLog), DS * 0.7, W * 0.42);
      finger("w1", p.x - s * 0.7, p.y + s * 0.7); finger("w2", p.x + s * 0.7, p.y - s * 0.7);
    }
  }
  function endWheel() {
    if (!wheelActive) return;
    wheelActive = false; lift("w1"); lift("w2");
    if (wheelKind === "pinch") docS.target = clamp(docS.x, 1, 2);
    wheelOff = 0; pinchLog = 0;
    if (hovering) { const f = fingers.get("mouse"); if (f) { finger("mouse", f.tx, f.ty, true); } }
    kick();
  }
  surface.addEventListener("wheel", e => {
    const engaged = hovering && performance.now() - lastHover < 1500;
    if (!(e.ctrlKey || engaged || wheelActive)) return;
    e.preventDefault(); takeOver();
    const p = local(e);
    const kind = e.ctrlKey ? "pinch" : "scroll";
    if (!wheelActive || kind !== wheelKind) {
      wheelKind = kind; wheelActive = true; wheelOff = 0; pinchLog = 0; lift("mouse");
      caption(CAPTIONS[kind], kind);
    }
    const dy = e.deltaMode === 1 ? e.deltaY * 16 : e.deltaY;
    if (kind === "scroll") {
      wheelOff -= dy * 0.25;
      const lo = docMin();
      docY.target = clamp(docY.target - dy * 0.8, lo - 30, 30); docY.set(lerp(docY.x, docY.target, 0.5));
    } else {
      pinchLog -= dy * 0.012;
      docS.set(clamp(docS.x * Math.exp(-dy * 0.012), 0.85, 2.2));
    }
    wheelFingers(p);
    clearTimeout(wheelTimer); wheelTimer = window.setTimeout(endWheel, 180);
    kick();
  }, { passive: false });
  void wheelOffS;

  /* Safari trackpad pinch */
  let gScale0 = 1;
  surface.addEventListener("gesturestart", ((e: Event & { scale: number; clientX: number; clientY: number }) => {
    e.preventDefault(); takeOver(); gScale0 = docS.x; wheelKind = "pinch"; wheelActive = true; lift("mouse"); caption(CAPTIONS.pinch, "pinch");
  }) as EventListener);
  surface.addEventListener("gesturechange", ((e: Event & { scale: number; clientX: number; clientY: number }) => {
    e.preventDefault(); docS.set(clamp(gScale0 * e.scale, 0.85, 2.2)); pinchLog = Math.log(e.scale);
    const f = fingers.get("mouse"); wheelFingers(f ? { x: f.tx, y: f.ty } : { x: W / 2, y: H / 2 }); kick();
  }) as EventListener);
  surface.addEventListener("gestureend", ((e: Event) => { e.preventDefault(); endWheel(); }) as EventListener);

  /* ---------- Scripted demos: synthetic fingers fed through the same recognizer ---------- */
  const scriptIds = new Set<string>();
  function clearScriptFingers() { for (const id of scriptIds) lift(id); scriptIds.clear(); snapshot([]); }
  class Cancelled extends Error {}
  async function play(name: string) {
    const token = ++scriptToken; scripting = true;
    const check = () => { if (token !== scriptToken) throw new Cancelled(); };
    const set = (pts: Pt[]) => {
      check();
      const ids = pts.map((_, i) => "s" + i);
      for (const id of [...scriptIds]) if (!ids.includes(id)) { lift(id); scriptIds.delete(id); }
      pts.forEach((p, i) => { finger(ids[i], p.x * W, p.y * H); scriptIds.add(ids[i]); });
      snapshot(pts.map(p => ({ x: p.x * W, y: p.y * H })));
      kick();
    };
    const wait = async (ms: number) => { await sleep(reduce ? Math.min(ms, 200) : ms); check(); };
    const glide = async (from: Pt[], to: Pt[], ms: number, bend = 0) => {
      if (reduce) { set(to); return; }
      const t0 = performance.now();
      for (;;) {
        const t = await nextFrame(); check();
        const u = Math.min(1, (t - t0) / ms), e = minJerk(u);
        set(from.map((a, i) => {
          const b = to[i], arc = Math.sin(Math.PI * e) * bend;
          return { x: lerp(a.x, b.x, e) + arc * 0.05, y: lerp(a.y, b.y, e) - arc * 0.03 };
        }));
        if (u >= 1) break;
      }
    };
    const up = () => { set([]); };
    const row = (n: number, cx: number, cy: number) =>
      Array.from({ length: n }, (_, i) => ({ x: cx + (i - (n - 1) / 2) * (DS * 1.5) / W, y: cy + [0.03, -0.035, 0, 0.04][i % 4] }));
    const shift = (p: Pt[], dx: number, dy: number) => p.map(q => ({ x: q.x + dx, y: q.y + dy }));

    try {
      if (name === "move") {
        caption(CAPTIONS.move, "move");
        const a = [{ x: 0.32, y: 0.62 }], b = [{ x: 0.68, y: 0.44 }];
        set(a); await wait(160); await glide(a, b, 900, 1); await wait(120); up(); await wait(200);
        set(b); await wait(120); await glide(b, [{ x: 0.42, y: 0.5 }], 700, -1); await wait(100); up();
      } else if (name === "click") {
        const p = [{ x: 0.5, y: 0.55 }];
        for (let i = 0; i < 2; i++) { set(p); await wait(90); ring(p[0].x * W, p[0].y * H); up(); await wait(650); }
      } else if (name === "scroll") {
        caption(CAPTIONS.scroll, "scroll");
        const a = row(2, 0.5, 0.66);
        set(a); await wait(140); await glide(a, shift(a, 0, -0.26), 520); up(); await wait(1100);
        const b = row(2, 0.5, 0.42);
        set(b); await wait(140); await glide(b, shift(b, 0, 0.16), 460); up();
      } else if (name === "pinch") {
        caption(CAPTIONS.pinch, "pinch");
        const a = [{ x: 0.44, y: 0.56 }, { x: 0.56, y: 0.48 }], b = [{ x: 0.26, y: 0.68 }, { x: 0.74, y: 0.36 }];
        set(a); await wait(140); await glide(a, b, 760); await wait(500); await glide(b, a, 640); up();
      } else if (name === "spaces") {
        const n = settings.drag ? 4 : 3;
        caption(CAPTIONS.spaces, "spaces");
        // over to the next Space, then back again
        const a = row(n, 0.62, 0.52);
        set(a); await wait(140); await glide(a, shift(a, -0.34, 0), 560); up(); await wait(1000);
        const b = row(n, 0.38, 0.5);
        set(b); await wait(140); await glide(b, shift(b, 0.34, 0), 520); up();
      } else if (name === "mission") {
        const n = settings.drag ? 4 : 3;
        caption(settings.mission ? CAPTIONS.mission : "Mission Control is off on your Mac", "mission");
        const a = row(n, 0.5, 0.66);
        set(a); await wait(140); await glide(a, shift(a, 0, -0.22), 560); up(); await wait(1400);
        const b = row(n, 0.5, 0.36);
        set(b); await wait(140); await glide(b, shift(b, 0, 0.22), 560); up();
      }
      await wait(400);
    } catch (err) { if (!(err instanceof Cancelled)) throw err; return; }
    if (token === scriptToken) scripting = false;
  }

  chips.forEach(c => c.addEventListener("click", () => { scriptToken++; clearScriptFingers(); play(c.dataset.g!); }));

  /* Theme */
  document.querySelectorAll<HTMLButtonElement>(".theme-row button").forEach(b => b.addEventListener("click", () => {
    section.dataset.theme = b.dataset.theme!;
    document.querySelectorAll(".theme-row button").forEach(x => x.setAttribute("aria-checked", String(x === b)));
  }));

  /* Keyboard: arrow keys move the pointer, Enter clicks */
  surface.addEventListener("keydown", e => {
    const step = 14;
    const map: Record<string, [number, number]> = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] };
    if (map[e.key]) { e.preventDefault(); cur.x = clamp(cur.x + map[e.key][0], 0, VW - 4); cur.y = clamp(cur.y + map[e.key][1], 0, VH - 4); caption(CAPTIONS.move, "move"); kick(); }
    if (e.key === "Enter" || e.key === " ") { e.preventDefault(); click(); }
  });

  /* ---------- Scroll-linked entrance and a one-time tour ---------- */
  let toured = false;
  new IntersectionObserver(async ([e]) => {
    if (!e.isIntersecting || toured || reduce) return;
    toured = true;
    await sleep(900);
    if (scriptToken !== 0 || touches.size || hovering) return;
    const token = scriptToken;
    for (const g of ["move", "scroll", "pinch", "spaces"]) {
      if (scriptToken !== token || hovering || touches.size) return;
      await play(g);
      if (scriptToken !== token + 1) return; // play() bumps the token once; anything else means the visitor took over
      scriptToken = token;
      await sleep(500);
    }
    if (scriptToken === token) caption(isTouch ? "Your turn" : "Your turn. Move over the phone.");
  }, { threshold: 0.55 }).observe(phone);

  kick();
}

import { lerp, minJerk, reducedMotion, nextFrame, sleep } from "./spring";

/* The full setup: an iPhone lying in front of a MacBook Pro, finger dots on the phone driving the Mac. */
export function initSetup() {
  const scene = document.getElementById("scene");
  if (!scene) return;
  const $ = <T extends Element = HTMLElement>(id: string) => document.getElementById(id) as unknown as T;
  const display = $("scDisplay"), spaces = $("scSpaces"), winA = $("scWinA"), winB = $("scWinB"), winNew = $("scWinNew");
  const docB = $("scDocB"), cursor = $<SVGElement>("scCursor"), surface = $("spSurface"), pDock = $("spDock"), pill = $("spPill");
  const steps = Array.from(document.querySelectorAll<HTMLButtonElement>("#howSteps button"));
  const items = steps.map(b => b.parentElement as HTMLElement);
  const caption = $("howCaption");
  const reduce = reducedMotion();
  const DUR = [2700, 2000, 3000, 3800, 4600];

  /* ---------- drawing ---------- */
  const dots: HTMLElement[] = [];
  const dot = (i: number) => { while (dots.length <= i) { const d = document.createElement("div"); d.className = "sp-dot"; surface.appendChild(d); dots.push(d); } return dots[i]; };
  const sz = () => ({ pw: surface.clientWidth, ph: surface.clientHeight, dw: display.clientWidth, dh: display.clientHeight });
  const put = (i: number, x: number, y: number, o = 1, s = 1) => { const { pw, ph } = sz(); const d = dot(i); d.style.transform = `translate(${x * pw}px, ${y * ph}px) scale(${s})`; d.style.opacity = String(o); };
  const hide = () => dots.forEach(d => (d.style.opacity = "0"));
  let cx = 0.5, cy = 0.5;
  const pc = () => { const { dw, dh } = sz(); cursor.style.transform = `translate(${(cx * dw).toFixed(1)}px, ${(cy * dh).toFixed(1)}px)`; };
  const ripple = (x: number, y: number) => {
    if (reduce) return;
    const { pw, ph } = sz(); const r = document.createElement("div"); r.className = "sp-ripple";
    r.style.transform = `translate(${x * pw}px, ${y * ph}px)`; surface.appendChild(r); setTimeout(() => r.remove(), 650);
  };
  const front = (w: HTMLElement) => { [winA, winB].forEach(x => { x.classList.toggle("front", x === w); x.style.zIndex = x === w ? "2" : "1"; }); };
  const setSpace = (p: number) => { spaces.style.transform = `translateX(${(-p * 50).toFixed(3)}%)`; };
  const setDocB = (y: number) => { docB.style.transform = `translateY(${y.toFixed(1)}px)`; };
  const setNew = (e: number) => { winNew.style.opacity = String(Math.min(1, e * 1.6)); winNew.style.transform = `scale(${lerp(0.62, 1, e)})`; };
  const slot = (k: string) => document.querySelector<HTMLElement>(`#scDock [data-app="${k}"]`)!;

  function reset() {
    hide(); cx = 0.45; cy = 0.6; pc(); front(winA); setSpace(0); setDocB(0); setNew(0);
    pDock.classList.remove("on"); pill.classList.remove("on");
    slot("notes").querySelector(".md-run")!.classList.remove("on");
  }

  /* ---------- timeline ---------- */
  class Cancel extends Error {}
  let token = 0;
  const live = (t: number) => { if (t !== token) throw new Cancel(); };
  const wait = async (t: number, ms: number) => { await sleep(ms); live(t); };
  const tween = async (t: number, ms: number, fn: (e: number) => void, ease = minJerk) => {
    const t0 = performance.now();
    for (;;) { const now = await nextFrame(); live(t); const u = Math.min(1, (now - t0) / ms); fn(ease(u)); if (u >= 1) return; }
  };
  const touch = (t: number, pts: [number, number][]) => tween(t, 170, e => pts.forEach(([x, y], i) => put(i, x, y, e, lerp(0.7, 1, e))));
  const lift = (t: number, pts: [number, number][]) => tween(t, 220, e => pts.forEach(([x, y], i) => put(i, x, y, 1 - e, lerp(1, 1.12, e))));
  const G = 0.62; // a full swipe across the phone covers about 60 percent of the screen

  const STEPS: ((t: number) => Promise<void>)[] = [
    async t => { // move
      let fx = 0.3, fy = 0.62; await touch(t, [[fx, fy]]);
      await tween(t, 1300, e => {
        const nx = lerp(0.3, 0.7, e), ny = lerp(0.62, 0.38, e) - Math.sin(Math.PI * e) * 0.12;
        cx += (nx - fx) * G; cy += (ny - fy) * G * 0.9; fx = nx; fy = ny; put(0, fx, fy); pc();
      });
      await lift(t, [[fx, fy]]); await wait(t, 300);
    },
    async t => { // click the window behind
      let fx = 0.7, fy = 0.38; await touch(t, [[fx, fy]]);
      await tween(t, 500, e => { const nx = lerp(0.7, 0.76, e), ny = lerp(0.38, 0.44, e); cx += (nx - fx) * G; cy += (ny - fy) * G; fx = nx; fy = ny; put(0, fx, fy); pc(); });
      await lift(t, [[fx, fy]]); await wait(t, 200);
      await touch(t, [[fx, fy]]); ripple(fx, fy); cursor.classList.add("press"); put(0, fx, fy, 1, 0.88);
      await wait(t, 110); cursor.classList.remove("press"); front(winB);
      await lift(t, [[fx, fy]]); await wait(t, 600);
    },
    async t => { // two finger scroll
      const { dh } = sz(); const a: [number, number][] = [[0.44, 0.7], [0.56, 0.68]];
      await touch(t, a);
      await tween(t, 760, e => { a.forEach(([x, y], i) => put(i, x, y - 0.4 * e)); setDocB(-dh * 0.24 * e); });
      await lift(t, a.map(([x, y]) => [x, y - 0.4] as [number, number]));
      await tween(t, 900, e => setDocB(-dh * (0.24 + 0.1 * e)), u => 1 - Math.pow(1 - u, 3));
      await wait(t, 500);
    },
    async t => { // three finger swipe between Spaces, and back
      const row = (x: number): [number, number][] => [[x - 0.13, 0.52], [x, 0.47], [x + 0.13, 0.53]];
      for (const [from, to, s0, s1] of [[0.66, 0.3, 0, 1], [0.34, 0.7, 1, 0]] as const) {
        await touch(t, row(from));
        await tween(t, 620, e => { const x = lerp(from, to, e); row(x).forEach(([px, py], i) => put(i, px, py)); setSpace(lerp(s0, s0 + (s1 - s0) * 0.8, e)); });
        await lift(t, row(to));
        await tween(t, 420, e => setSpace(lerp(s0 + (s1 - s0) * 0.8, s1, e)), u => 1 - Math.exp(-5 * u) * Math.cos(7 * u));
        await wait(t, 650);
      }
    },
    async t => { // Dock mode opens an app on the Mac
      pill.classList.add("on"); await wait(t, 500);
      pDock.classList.add("on"); await wait(t, 300); pill.classList.remove("on"); await wait(t, 400);
      const tile = pDock.querySelector<HTMLElement>('[data-app="notes"]')!;
      const tr = tile.querySelector(".app") as HTMLElement;
      const x = (tile.offsetLeft + tile.offsetWidth / 2) / surface.clientWidth, y = (tile.offsetTop + tr.offsetHeight / 2) / surface.clientHeight;
      await touch(t, [[x, y]]); tr.classList.add("pressed"); ripple(x, y); await wait(t, 120); tr.classList.remove("pressed");
      const icon = slot("notes").querySelector(".app") as HTMLElement; icon.classList.remove("bounce"); void icon.offsetWidth; icon.classList.add("bounce");
      slot("notes").querySelector(".md-run")!.classList.add("on");
      await lift(t, [[x, y]]);
      await wait(t, 380);
      await tween(t, 620, setNew, u => 1 - Math.exp(-6 * u) * Math.cos(8 * u));
      await wait(t, 1500);
      pill.classList.add("on"); await wait(t, 300); pDock.classList.remove("on"); await wait(t, 400); pill.classList.remove("on");
    },
  ];

  const mark = (k: number) => {
    items.forEach((li, i) => { li.classList.toggle("active", i === k); li.classList.toggle("done", i < k); });
    steps.forEach((b, i) => b.setAttribute("aria-current", String(i === k)));
    const b = steps[k];
    caption.innerHTML = `<b>${b.querySelector("b")!.textContent}</b><span>${b.querySelector(".t")!.textContent}</span>`;
    items.forEach(li => li.querySelector<HTMLElement>(".hs-bar i")!.getAnimations().forEach(a => a.cancel()));
    if (!reduce) items[k].querySelector<HTMLElement>(".hs-bar i")!.animate([{ transform: "scaleX(0)" }, { transform: "scaleX(1)" }], { duration: DUR[k], easing: "linear", fill: "forwards" });
  };

  async function run(from: number) {
    const t = ++token;
    try {
      reset();
      for (let k = from; ; k = (k + 1) % STEPS.length) {
        if (k === 0) { reset(); await wait(t, 300); }
        mark(k);
        await STEPS[k](t);
      }
    } catch (e) { if (!(e instanceof Cancel)) throw e; }
  }

  /* Reduced motion: still frames, one per step */
  function still(k: number) {
    reset(); mark(k);
    const { dh } = sz();
    if (k === 0) { put(0, 0.7, 0.38); cx = 0.7; cy = 0.47; pc(); }
    if (k === 1) { put(0, 0.76, 0.44); cx = 0.735; cy = 0.5; pc(); front(winB); }
    if (k === 2) { put(0, 0.44, 0.3); put(1, 0.56, 0.28); front(winB); setDocB(-dh * 0.3); }
    if (k === 3) { put(0, 0.17, 0.52); put(1, 0.3, 0.47); put(2, 0.43, 0.53); setSpace(1); }
    if (k === 4) { pDock.classList.add("on"); setNew(1); slot("notes").querySelector(".md-run")!.classList.add("on"); }
  }

  let current = 0, visible = false;
  steps.forEach((b, i) => b.addEventListener("click", () => { current = i; if (reduce) still(i); else run(i); }));
  new ResizeObserver(() => pc()).observe(display);
  if (reduce) { still(0); return; }
  reset(); mark(0);
  new IntersectionObserver(([e]) => {
    if (e.isIntersecting && !visible) { visible = true; run(current); }
    else if (!e.isIntersecting && visible) {
      visible = false;
      const a = items.findIndex(li => li.classList.contains("active")); current = Math.max(0, a); token++;
    }
  }, { threshold: 0.35 }).observe(scene);
}

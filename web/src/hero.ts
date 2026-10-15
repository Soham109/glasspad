import { Spring, damp, minJerk, reducedMotion, nextFrame, sleep } from "./spring";

type P = [number, number];
type Glide = [P, P, number];
// Glides inside the icon's surface (x 102..922, y 222..802). The last one is the icon itself.
const GLIDES: Glide[] = [
  [[300, 470], [700, 590], 70],
  [[710, 370], [390, 520], -60],
  [[300, 610], [660, 440], 0],
];

export function initHero() {
  const svg = document.getElementById("heroGlide") as SVGSVGElement | null;
  const dot = document.getElementById("heroDot") as SVGCircleElement | null;
  const trail = document.getElementById("heroTrail") as SVGPathElement | null;
  if (!svg || !dot || !trail || reducedMotion()) return;

  let visible = true;
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; }).observe(svg);
  const waitVisible = async () => { while (!visible || document.hidden) await sleep(250); };

  const bez = ([a, b, bend]: Glide, u: number): P => {
    const mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2;
    const dx = b[0] - a[0], dy = b[1] - a[1], len = Math.hypot(dx, dy) || 1;
    const cx = mx - (dy / len) * bend, cy = my + (dx / len) * bend, iu = 1 - u;
    return [iu * iu * a[0] + 2 * iu * u * cx + u * u * b[0], iu * iu * a[1] + 2 * iu * u * cy + u * u * b[1]];
  };
  const draw = (g: Glide, u0: number, u1: number, scale: number, alpha: number) => {
    const pts: string[] = [];
    for (let i = 0; i <= 24; i++) { const p = bez(g, u0 + (u1 - u0) * (i / 24)); pts.push(`${p[0].toFixed(1)} ${p[1].toFixed(1)}`); }
    trail.setAttribute("d", "M" + pts.join(" L"));
    trail.setAttribute("stroke-opacity", (0.1 * Math.max(0, alpha)).toFixed(3));
    const h = bez(g, u1);
    dot.setAttribute("cx", h[0].toFixed(1)); dot.setAttribute("cy", h[1].toFixed(1));
    dot.setAttribute("r", (74 * scale).toFixed(1));
    dot.setAttribute("fill-opacity", (0.62 * Math.max(0, alpha)).toFixed(3));
  };
  // Runs springs for `ms`, calling paint each frame with the elapsed fraction.
  async function run(ms: number, springs: Spring[], paint: (f: number) => void) {
    const t0 = performance.now(); let last = t0;
    for (;;) {
      const t = await nextFrame(); const dt = (t - last) / 1000; last = t;
      for (const s of springs) s.step(dt);
      const f = Math.min(1, (t - t0) / ms); paint(f); if (f >= 1) return;
    }
  }

  async function touchAndGlide(g: Glide) {
    const scale = new Spring(0.8, 420, damp(420, 0.6)); scale.target = 1;
    const alpha = new Spring(0, 260, damp(260)); alpha.target = 1;
    await run(240, [scale, alpha], () => draw(g, 0, 0, scale.x, alpha.x));
    await run(950, [scale, alpha], f => draw(g, 0, minJerk(f), scale.x, alpha.x));
  }
  async function settleAndLift(g: Glide) {
    const tail = new Spring(0, 110, damp(110)); tail.target = 1;
    await run(480, [tail], () => draw(g, Math.min(1, tail.x), 1, 1, 1));
    const scale = new Spring(1, 300, damp(300)); scale.target = 1.14;
    const alpha = new Spring(1, 200, damp(200)); alpha.target = 0;
    await run(380, [scale, alpha], () => draw(g, 1, 1, scale.x, alpha.x));
    draw(g, 1, 1, 1, 0);
  }

  (async () => {
    await sleep(1800);
    for (;;) {
      await waitVisible();
      await settleAndLift(GLIDES[2]);
      for (let i = 0; i < GLIDES.length; i++) {
        await sleep(i === 0 ? 520 : 360); await waitVisible();
        await touchAndGlide(GLIDES[i]);
        if (i < GLIDES.length - 1) { await sleep(180); await settleAndLift(GLIDES[i]); }
      }
      await sleep(4200); // rest on the icon
    }
  })();
}

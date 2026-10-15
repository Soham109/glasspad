// Prints CSS linear() easings sampled from a damped spring (mass 1).
function spring(k, c, n = 40) {
  // simulate until settled
  const dt = 1 / 600; let x = 0, v = 0, t = 0; const pts = [];
  while (t < 4) { const a = k * (1 - x) - c * v; v += a * dt; x += v * dt; t += dt; pts.push([t, x]);
    if (t > 0.1 && Math.abs(1 - x) < 0.0008 && Math.abs(v) < 0.01) break; }
  const T = t; const out = [];
  for (let i = 0; i <= n; i++) { const tt = (i / n) * T; const p = pts.find(q => q[0] >= tt) || pts[pts.length - 1]; out.push(+p[1].toFixed(4)); }
  out[0] = 0; out[out.length - 1] = 1;
  return { css: `linear(${out.join(", ")})`, ms: Math.round(T * 1000) };
}
for (const [name, k, c] of [["soft", 120, 22], ["snappy", 260, 26], ["bouncy", 220, 18]]) {
  const s = spring(k, c); console.log(`--ease-${name}: ${s.css}; /* ${s.ms}ms */`);
}

// Film and teaser audio: UI sound design from the cue sheet, an original score on the 90 BPM grid,
// VO-priority ducking, stems and loudness (-14 LUFS integrated, true peak under -1 dBTP).
// Nothing is downloaded: every sound is synthesized here. Run after make-voice.ts (bundled by esbuild, see package.json).
// Outputs: public/mix-film-vo.wav, public/mix-film-novo.wav, public/mix-teaser.wav, out/stems/*, out/cue-sheet.csv
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { buildFilmCues, buildTeaserCues, Cue } from "../src/cues";
import { FPS, S, FILM_LEN, TEASER_LEN, T } from "../src/timeline";

const SR = 44100;
const root = process.cwd();
const BEAT_S = 40 / FPS; // 90 BPM
const BAR_S = 4 * BEAT_S;
let seed = 11;
const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647) * 2 - 1;
type Stereo = { L: Float32Array; R: Float32Array };
const mk = (n: number): Stereo => ({ L: new Float32Array(n), R: new Float32Array(n) });
const add = (dst: Stereo, t0: number, buf: Float32Array, gain: number, pan = 0) => {
  const s0 = Math.round(t0 * SR), gl = gain * Math.cos(((pan + 1) * Math.PI) / 4) * Math.SQRT2, gr = gain * Math.sin(((pan + 1) * Math.PI) / 4) * Math.SQRT2;
  for (let i = 0; i < buf.length; i++) { const j = s0 + i; if (j < 0 || j >= dst.L.length) continue; dst.L[j] += buf[i] * gl; dst.R[j] += buf[i] * gr; }
};
const db = (x: number) => Math.pow(10, x / 20);
const mtof = (m: number) => 440 * Math.pow(2, (m - 69) / 12);

// ---------- UI sounds (transient at sample 0 unless noted) ----------
const buf = (sec: number, fn: (t: number, i: number) => number) => { const n = Math.floor(SR * sec), b = new Float32Array(n); for (let i = 0; i < n; i++) b[i] = fn(i / SR, i); return b; };
const V: Record<string, Float32Array> = {};
const voice = (k: string, make: () => Float32Array) => (V[k] ??= make());
const touch = () => { let lp = 0; return buf(0.16, (t) => { const nz = rnd(); lp += (nz - lp) * 0.08; return Math.sin(2 * Math.PI * (210 - 60 * t / 0.16) * t) * Math.exp(-t * 38) * 0.5 + lp * Math.exp(-t * 90) * 0.9; }); };
// a Taptic-like click: a short low body, a crisp edge and a little air
const click = () => { let prev = 0; return buf(0.12, (t) => { const nz = rnd(), hp = nz - prev; prev = nz; return Math.sin(2 * Math.PI * 165 * t) * Math.exp(-t * 60) * 0.9 + hp * Math.exp(-t * 900) * 0.6 + Math.sin(2 * Math.PI * 2400 * t) * Math.exp(-t * 180) * 0.12; }); };
const haptic = () => { const c = click(); return buf(0.24, (t, i) => (i < c.length ? c[i] : 0) + Math.sin(2 * Math.PI * 150 * t) * Math.exp(-t * 22) * 0.5 * Math.min(1, t * 400)); };
const snap = () => { let prev = 0; return buf(0.1, (t) => { const nz = rnd(), hp = nz - prev; prev = nz; return Math.sin(2 * Math.PI * 120 * t) * Math.exp(-t * 70) * 0.8 + hp * Math.exp(-t * 1200) * 0.5; }); };
const key = () => { let lp = 0, prev = 0; return buf(0.05, (t) => { const nz = rnd(); lp += (nz - lp) * 0.35; const hp = lp - prev; prev = lp; return hp * Math.exp(-t * 260) * 1.6 + Math.sin(2 * Math.PI * 1300 * t) * Math.exp(-t * 200) * 0.1; }); };
const pop = () => buf(0.14, (t) => Math.sin(2 * Math.PI * (520 + 380 * Math.min(1, t / 0.05)) * t) * Math.exp(-t * 40) * Math.min(1, t * 2000) * 0.5);
const tick = () => { let prev = 0; return buf(0.04, (t) => { const nz = rnd(), hp = nz - prev; prev = nz; return hp * 0.5 * Math.exp(-t * 300) + Math.sin(2 * Math.PI * 3200 * t) * 0.2 * Math.exp(-t * 160); }); };
const chime = () => buf(1.6, (t) => [88, 95].reduce((a, m, k) => a + Math.sin(2 * Math.PI * mtof(m) * Math.max(0, t - k * 0.09)) * Math.exp(-Math.max(0, t - k * 0.09) * 3.5) * (t >= k * 0.09 ? 1 : 0), 0) * 0.3);
const thump = () => buf(0.6, (t) => Math.tanh(1.3 * Math.sin(2 * Math.PI * (52 + 40 * Math.exp(-t * 30)) * t) * Math.exp(-t * 7)) * 0.9);
/** soft air swell whose peak lands PEAK s into the buffer */
const PEAK = 0.42;
const air = () => { let l1 = 0, l2 = 0; return buf(0.7, (t) => { const env = t < PEAK ? Math.pow(t / PEAK, 2.2) : Math.exp(-(t - PEAK) * 12); const c = 0.01 + 0.12 * Math.pow(Math.min(1, t / PEAK), 2); const nz = rnd(); l1 += (nz - l1) * c; l2 += (l1 - l2) * c; return l2 * env * 3; }); };

const renderSfx = (cues: Cue[], len: number) => {
  const out = mk(len);
  for (const c of cues) {
    const t = c.f / FPS;
    const b = voice(c.kind, { touch, click, haptic, snap, key, pop, tick, chime, thump, air }[c.kind]);
    add(out, c.kind === "air" ? t - PEAK : t, b, c.gain, c.pan);
  }
  return out;
};

// ---------- score: 90 BPM, D major colour; one chord per bar ----------
// Dmaj9, Bm9, Gmaj9, Asus(add9); resolve on Dmaj9 for the end card.
const CH = [
  { root: 38, notes: [54, 57, 61, 64] },
  { root: 35, notes: [50, 54, 57, 61] },
  { root: 31, notes: [50, 54, 57, 62] },
  { root: 33, notes: [52, 57, 59, 64] },
];
type Sec = { a: number; b: number; pad: number; cut: number; keys: number; sub: number; arp: number; hat: number };
const renderScore = (len: number, secs: Sec[], endAt: number) => {
  const N = len, out = mk(N), tEnd = N / SR;
  const at = (t: number) => secs.find((s) => t >= s.a && t < s.b) ?? secs[secs.length - 1];
  const smooth = (key: keyof Sec, t: number) => { // 1 s crossfade between section values
    let v = 0, w = 0;
    for (let d = -0.5; d <= 0.5; d += 0.1) { v += at(Math.max(0, t + d))[key] as number; w++; }
    return v / w;
  };
  const chordAt = (t: number) => (t >= endAt ? CH[0] : CH[Math.floor(t / BAR_S) % 4]);
  // pad: additive (fundamental, soft 2nd and 3rd), two detuned voices, one-pole low-pass that follows the section
  const ph = new Float64Array(64);
  let lpL = 0, lpR = 0, lp2L = 0, lp2R = 0, padLvl = 0, cutv = 600;
  for (let i = 0; i < N; i++) {
    const t = i / SR;
    if (i % 441 === 0) { padLvl = smooth("pad", t); cutv = smooth("cut", t); }
    const ch = chordAt(t), prev = chordAt(Math.max(0, t - BAR_S * 0.25));
    const xf = Math.min(1, (t % BAR_S) / (BAR_S * 0.25));
    let sL = 0, sR = 0, p = 0;
    for (const [set, w] of [[ch, t >= endAt ? 1 : xf], [prev, t >= endAt ? 0 : 1 - xf]] as const) {
      for (const m of set.notes) for (const d of [-0.04, 0.05]) {
        const idx = p++ % 64;
        ph[idx] = (ph[idx] + mtof(m + d) / SR) % 1;
        const x = 2 * Math.PI * ph[idx];
        const v = (Math.sin(x) + 0.3 * Math.sin(2 * x) + 0.12 * Math.sin(3 * x)) * w;
        if (d < 0) sL += v; else sR += v;
      }
    }
    const a = 1 - Math.exp((-2 * Math.PI * cutv) / SR);
    lpL += (sL - lpL) * a; lp2L += (lpL - lp2L) * a; lpR += (sR - lpR) * a; lp2R += (lpR - lp2R) * a;
    let g = padLvl * 0.016 * (0.92 + 0.08 * Math.sin(2 * Math.PI * 0.11 * t));
    if (t < 1.5) g *= t / 1.5;
    if (t > tEnd - 4) g *= Math.max(0, (tEnd - t) / 4);
    out.L[i] += lp2L * g; out.R[i] += lp2R * g;
  }
  // electric-piano chords on each bar (and the resolve)
  const ep = (f0: number, sec: number) => buf(sec, (t) => (Math.sin(2 * Math.PI * f0 * t) + 0.35 * Math.sin(4 * Math.PI * f0 * t) * Math.exp(-t * 6) + 0.08 * Math.sin(6 * Math.PI * f0 * t) * Math.exp(-t * 12)) * Math.exp(-t * 1.6) * Math.min(1, t * 300) * (1 + 0.05 * Math.sin(2 * Math.PI * 4.5 * t)));
  for (let b = 0; b * BAR_S < tEnd; b++) {
    const t = b * BAR_S;
    const k = at(t).keys;
    if (!k || t >= endAt) continue;
    CH[b % 4].notes.forEach((m, j) => add(out, t + j * 0.012, voice(`ep${m}`, () => ep(mtof(m), 3.2)), 0.03 * k, j % 2 ? 0.25 : -0.25));
  }
  CH[0].notes.concat([69, 73]).forEach((m, j) => add(out, endAt + j * 0.03, voice(`epr${m}`, () => ep(mtof(m), 6)), 0.035, j % 2 ? 0.3 : -0.3));
  // sub pulse on beats 1 and 3
  for (let b = 0; b * BEAT_S < tEnd; b += 2) {
    const t = b * BEAT_S, s = at(t).sub;
    if (!s || t >= endAt) continue;
    const f0 = mtof(chordAt(t).root);
    add(out, t, voice(`sub${f0}`, () => buf(0.6, (u) => Math.sin(2 * Math.PI * f0 * u) * Math.exp(-u * 5) * Math.min(1, u * 200))), 0.22 * s, 0);
  }
  // soft pluck arpeggio, eighths, ping-pong delay (dotted eighth)
  const arp = mk(N);
  let step = 0;
  for (let e = 0; e * (BEAT_S / 2) < tEnd; e++) {
    const t = e * (BEAT_S / 2), a = at(t).arp;
    if (!a || t >= endAt) continue;
    const ch = chordAt(t), pool = [...ch.notes.map((m) => m + 12), ...ch.notes.map((m) => m + 24)];
    const m = pool[[0, 2, 1, 3, 4, 2, 5, 3][step++ % 8] % pool.length];
    add(arp, t, voice(`pl${m}`, () => buf(0.5, (u) => (Math.sin(2 * Math.PI * mtof(m) * u) + 0.2 * Math.sin(4 * Math.PI * mtof(m) * u) * Math.exp(-u * 30)) * Math.exp(-u * 9) * Math.min(1, u * 600))), 0.022 * a * (e % 4 === 0 ? 1 : 0.75), e % 2 ? 0.35 : -0.35);
  }
  const D = Math.round(SR * BEAT_S * 0.75);
  const dl = new Float32Array(N), dr = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    dl[i] = arp.R[i] + (i >= D ? dr[i - D] * 0.35 : 0);
    dr[i] = arp.L[i] + (i >= D ? dl[i - D] * 0.35 : 0);
    out.L[i] += arp.L[i] + (i >= D ? dl[i - D] * 0.3 : 0);
    out.R[i] += arp.R[i] + (i >= D ? dr[i - D] * 0.3 : 0);
  }
  // very soft sixteenth shaker
  for (let s16 = 0; s16 * (BEAT_S / 4) < tEnd; s16++) {
    const t = s16 * (BEAT_S / 4), h = at(t).hat;
    if (!h || t >= endAt) continue;
    add(out, t, voice("hat", () => { let prev = 0; return buf(0.05, (u) => { const nz = rnd(), hp = nz - prev; prev = nz; return hp * Math.exp(-u * 120) * 0.5; }); }), (s16 % 4 === 2 ? 0.02 : 0.009) * h, s16 % 2 ? 0.3 : -0.3);
  }
  // small algorithmic room
  const combs = [1116, 1188, 1277, 1356], aps = [556, 441];
  const verb = (x: Float32Array, spread: number) => {
    const o = new Float32Array(N);
    for (const c of combs) { const d = c + spread, bb = new Float32Array(d); let k = 0, lp = 0; for (let i = 0; i < N; i++) { const y = bb[k]; lp = y * 0.55 + lp * 0.45; bb[k] = x[i] + lp * 0.82; o[i] += y * 0.25; k = (k + 1) % d; } }
    for (const a of aps) { const d = a + spread, bb = new Float32Array(d); let k = 0; for (let i = 0; i < N; i++) { const b = bb[k], y = -o[i] + b; bb[k] = o[i] + b * 0.5; o[i] = y; k = (k + 1) % d; } }
    return o;
  };
  const wl = verb(out.L, 0), wr = verb(out.R, 23);
  for (let i = 0; i < N; i++) { out.L[i] += wl[i] * 0.3; out.R[i] += wr[i] * 0.3; }
  return out;
};

// ---------- I/O, loudness ----------
const readWav = (file: string, N: number): Stereo => {
  const tmp = path.join(root, "voice/work/read16.wav");
  execFileSync("ffmpeg", ["-loglevel", "error", "-y", "-i", file, "-ac", "2", "-ar", String(SR), "-c:a", "pcm_s16le", tmp]);
  const b = fs.readFileSync(tmp);
  let o = 12, off = 0;
  while (o < b.length) { const id = b.toString("ascii", o, o + 4), sz = b.readUInt32LE(o + 4); if (id === "data") { off = o + 8; break; } o += 8 + sz; }
  const out = mk(N), frames = Math.min(N, Math.floor((b.length - off) / 4));
  for (let i = 0; i < frames; i++) { out.L[i] = b.readInt16LE(off + i * 4) / 32768; out.R[i] = b.readInt16LE(off + i * 4 + 2) / 32768; }
  return out;
};
const writeWav = (file: string, s: Stereo, gain = 1) => {
  const N = s.L.length, b = Buffer.alloc(44 + N * 4);
  b.write("RIFF", 0); b.writeUInt32LE(36 + N * 4, 4); b.write("WAVE", 8); b.write("fmt ", 12); b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(2, 22);
  b.writeUInt32LE(SR, 24); b.writeUInt32LE(SR * 4, 28); b.writeUInt16LE(4, 32); b.writeUInt16LE(16, 34); b.write("data", 36); b.writeUInt32LE(N * 4, 40);
  for (let i = 0; i < N; i++) { b.writeInt16LE(Math.round(Math.max(-1, Math.min(1, s.L[i] * gain)) * 32767), 44 + i * 4); b.writeInt16LE(Math.round(Math.max(-1, Math.min(1, s.R[i] * gain)) * 32767), 46 + i * 4); }
  fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, b);
};
const lufs = (file: string) => {
  const r = execFileSync("sh", ["-c", `ffmpeg -hide_banner -i "${file}" -af ebur128=peak=true -f null - 2>&1 | tail -24`]).toString();
  return { I: Number(/I:\s+(-?[\d.]+) LUFS/.exec(r)?.[1]), TP: Number(/Peak:\s+(-?[\d.]+) dBFS/.exec(r)?.[1]) };
};
const TARGET = -14;
const master = (parts: Array<{ s: Stereo; g: (i: number) => number }>, file: string) => {
  const N = parts[0].s.L.length;
  const sum = mk(N);
  for (const p of parts) for (let i = 0; i < N; i++) { const g = p.g(i); sum.L[i] += p.s.L[i] * g; sum.R[i] += p.s.R[i] * g; }
  let pk = 0; for (let i = 0; i < N; i++) pk = Math.max(pk, Math.abs(sum.L[i]), Math.abs(sum.R[i]));
  const tmp = path.join(root, "voice/work/pre.wav");
  writeWav(tmp, sum, 0.5 / pk);
  let gain = (0.5 / pk) * db(TARGET - lufs(tmp).I);
  let ceil = db(-1.6);
  for (let it = 0; it < 6; it++) {
    const out = mk(N);
    for (let i = 0; i < N; i++) { out.L[i] = sum.L[i] * gain; out.R[i] = sum.R[i] * gain; }
    // look-ahead limiter (2 ms), 120 ms release
    const look = Math.round(0.002 * SR), rel = Math.exp(-1 / (0.12 * SR)), need = new Float32Array(N);
    for (let i = 0; i < N; i++) { const a = Math.max(Math.abs(out.L[i]), Math.abs(out.R[i])); need[i] = a > ceil ? ceil / a : 1; }
    let gr = 1;
    for (let i = 0; i < N; i++) { let tg = 1; for (let k = 0; k <= look && i + k < N; k++) tg = Math.min(tg, need[i + k]); gr = tg < gr ? tg : 1 - (1 - gr) * rel; out.L[i] *= gr; out.R[i] *= gr; }
    writeWav(file, out);
    const m = lufs(file);
    const okI = Math.abs(m.I - TARGET) <= 0.3, okTP = m.TP <= -1.0;
    if (okI && okTP) return { m, gain };
    if (!okTP) ceil *= db(-1.0 - m.TP - 0.2);
    if (!okI) gain *= db(TARGET - m.I);
  }
  return { m: lufs(file), gain };
};

// ducking envelope from VO windows: 80 ms attack (reached at speech onset), 350 ms release
const duckEnv = (N: number, wins: Array<{ a: number; b: number }>) => {
  const env = new Float32Array(N);
  for (const w of wins) {
    const a0 = Math.round((w.a - 0.08) * SR), a1 = Math.round(w.a * SR), b0 = Math.round(w.b * SR), b1 = Math.round((w.b + 0.35) * SR);
    for (let i = Math.max(0, a0); i < Math.min(N, b1); i++) {
      let v = 1;
      if (i < a1) v = 0.5 - 0.5 * Math.cos((Math.PI * (i - a0)) / (a1 - a0));
      else if (i > b0) v = 0.5 + 0.5 * Math.cos((Math.PI * (i - b0)) / (b1 - b0));
      env[i] = Math.max(env[i], v);
    }
  }
  return env;
};

const sec = (f: number) => f / FPS;
const build = (name: string, len: number, cues: Cue[], secs: Sec[], endAt: number, voJson: string, voWav: string, outs: { vo: string; novo?: string }) => {
  const N = Math.ceil((len / FPS) * SR);
  const vo = JSON.parse(fs.readFileSync(path.join(root, voJson), "utf8")) as { lines: Array<{ f: number; seconds: number; text: string }> };
  const wins = vo.lines.map((l) => ({ a: sec(l.f), b: sec(l.f) + l.seconds }));
  const sfx = renderSfx(cues, N), music = renderScore(N, secs, endAt), voS = readWav(path.join(root, voWav), N);
  const env = duckEnv(N, wins);
  const MUS = 1.2, SFX = 0.6, MD = db(-8), SD = db(-4);
  const gm = (i: number) => MUS * (1 - env[i] * (1 - MD)), gs = (i: number) => SFX * (1 - env[i] * (1 - SD));
  const r = master([{ s: voS, g: () => 1 }, { s: music, g: gm }, { s: sfx, g: gs }], path.join(root, outs.vo));
  console.log(`${name} VO mix: ${r.m.I} LUFS, true peak ${r.m.TP} dBTP`);
  if (name === "film") {
    const st = (s: Stereo, g: (i: number) => number) => ({ L: s.L.map((x, i) => x * g(i) * r.gain), R: s.R.map((x, i) => x * g(i) * r.gain) });
    writeWav(path.join(root, "out/stems/vo.wav"), st(voS, () => 1));
    writeWav(path.join(root, "out/stems/music.wav"), st(music, gm));
    writeWav(path.join(root, "out/stems/sfx.wav"), st(sfx, () => 1), 1 / Math.max(1e-9, r.gain) * r.gain); // sfx undducked, for transient timing
  }
  if (outs.novo) {
    const n = master([{ s: music, g: () => MUS }, { s: sfx, g: () => SFX }], path.join(root, outs.novo));
    console.log(`${name} no-VO mix: ${n.m.I} LUFS, true peak ${n.m.TP} dBTP`);
  }
  // collisions: two loud transients closer than 80 ms
  const loud = cues.filter((c) => ["click", "haptic", "touch", "snap", "thump"].includes(c.kind));
  for (let i = 1; i < loud.length; i++) if (loud[i].f - loud[i - 1].f < 5) console.log(`  note: ${loud[i - 1].label} and ${loud[i].label} are ${loud[i].f - loud[i - 1].f} frames apart`);
  const lines = ["frame,time_s,kind,label,gain"];
  for (const c of cues) lines.push(`${c.f},${sec(c.f).toFixed(3)},${c.kind},"${c.label}",${c.gain}`);
  for (const l of vo.lines) lines.push(`${l.f},${sec(l.f).toFixed(3)},vo,"${l.text}",`);
  fs.mkdirSync(path.join(root, "out"), { recursive: true });
  fs.writeFileSync(path.join(root, `out/cue-sheet-${name}.csv`), lines.join("\n") + "\n");
};

// sections: pad level, filter cutoff (Hz), keys, sub, arp, hat
const s = (a: number, b: number, pad: number, cut: number, keys: number, sub: number, arp: number, hat: number): Sec => ({ a: sec(a), b: sec(b), pad, cut, keys, sub, arp, hat });
build("film", FILM_LEN, buildFilmCues(), [
  s(0, 440, 0.8, 650, 0, 0, 0, 0),
  s(440, 1320, 0.85, 1100, 1, 0, 0, 0),
  s(1320, 1560, 0.7, 900, 0.6, 0, 0, 0),
  s(1560, 2000, 0.9, 1500, 1, 0.7, 0.7, 0),
  s(2000, 2360, 0.8, 1200, 0.8, 0.5, 0.5, 0),
  s(2360, 3680, 1, 1900, 1, 1, 1, 1),
  s(3680, 4120, 0.75, 700, 0.6, 0.8, 0, 0),
  s(4120, FILM_LEN, 1.3, 1500, 0, 0, 0, 0),
], sec(S.end), "public/vo-lines.json", "public/vo-film.wav", { vo: "public/mix-film-vo.wav", novo: "public/mix-film-novo.wav" });
build("teaser", TEASER_LEN, buildTeaserCues(), [
  s(0, 330, 0.55, 600, 0, 0, 0, 0),
  s(330, 920, 0.9, 1400, 1, 0.7, 0.6, 0),
  s(920, 1280, 1, 1900, 1, 1, 1, 1),
  s(1280, TEASER_LEN, 1.3, 1500, 0, 0, 0, 0),
], sec(T.end), "public/vo-teaser-lines.json", "public/vo-teaser.wav", { vo: "public/mix-teaser.wav" });

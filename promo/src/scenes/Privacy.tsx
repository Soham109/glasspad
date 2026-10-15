import React from "react";
import { AbsoluteFill } from "remotion";
import { C, FONT } from "../theme";
import { Caption } from "../Captions";
import { Icon, GL } from "../screens/apps";
import { clamp, lerp, minJerk, prog, spring, snappy } from "../motion";

/* Privacy, on graphite. Drawn from the site's network diagram (web/index.html #net):
   pair with a QR code, every message encrypted, nothing leaves your Wi-Fi, no accounts. */
export const PRIV = (at: number) => ({ qr: at + 14, scan: at + 62, paired: at + 74, packets: at + 140, wifi: at + 270 });

// deterministic QR-like pattern: three finder squares + seeded cells
const N = 21;
const QR: number[][] = (() => {
  let s = 7;
  const r = () => ((s = (s * 16807) % 2147483647) / 2147483647);
  const g = Array.from({ length: N }, () => Array.from({ length: N }, () => (r() > 0.52 ? 1 : 0)));
  const finder = (x0: number, y0: number) => {
    for (let y = -1; y < 8; y++) for (let x = -1; x < 8; x++) {
      const X = x0 + x, Y = y0 + y;
      if (X < 0 || Y < 0 || X >= N || Y >= N) continue;
      const ring = Math.max(Math.abs(x - 3), Math.abs(y - 3));
      g[Y][X] = ring === 3 || ring <= 1 ? 1 : 0;
    }
  };
  finder(0, 0); finder(N - 7, 0); finder(0, N - 7);
  return g;
})();
const order = (x: number, y: number) => { const v = Math.sin(x * 12.9898 + y * 78.233) * 43758.5453; return v - Math.floor(v); };

export const Privacy: React.FC<{ f: number; at: number; end: number; W?: number; H?: number; vertical?: boolean }> = ({ f, at, end, W = 1920, H = 1080, vertical }) => {
  const k = f - at;
  const ev = PRIV(0);
  const sc = vertical ? 1.36 : 2.1;
  const ox = (W - 720 * sc) / 2, oy = vertical ? 760 : 410;
  const X = (x: number) => ox + x * sc, Y = (y: number) => oy + y * sc;
  const ink = C.onDark;
  const enter = clamp(spring(k, 4, 180, 1));
  // QR on the Mac
  const qrSize = 64 * sc, qx = X(564) - qrSize / 2, qy = Y(112) - qrSize / 2, cell = qrSize / N;
  const qrCells: React.ReactNode[] = [];
  QR.forEach((row, y) => row.forEach((v, x) => {
    if (!v) return;
    const t = clamp((k - ev.qr - order(x, y) * 26) / 6);
    if (t <= 0) return;
    qrCells.push(<rect key={`${x}-${y}`} x={qx + x * cell} y={qy + y * cell} width={cell * 0.92 * t} height={cell * 0.92 * t} rx={cell * 0.18} fill={ink} />);
  }));
  // phone viewfinder and check
  const pcx = X(150), pcy = Y(123);
  const scan = prog(k, ev.scan - 18, 18);
  const paired = clamp(snappy(k, ev.paired));
  const qrFade = 1 - prog(k, ev.packets - 30, 20);
  // packets phone -> Mac
  const pk: React.ReactNode[] = [];
  for (let s = ev.packets; s < end - at; s += 13) {
    const t = (k - s) / 46;
    if (t < 0 || t > 1) continue;
    const e = minJerk(t);
    const x = lerp(X(206), X(484), e), y = Y(123);
    pk.push(<g key={s} transform={`translate(${x - 17} ${y - 17})`} opacity={Math.min(1, Math.sin(Math.PI * t) * 2.2)}><rect width={34} height={34} rx={10} fill={C.graphite} stroke={ink} strokeOpacity={0.5} strokeWidth={1.6} /><g transform="translate(7 7) scale(0.84)" fill="none" stroke={ink} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" dangerouslySetInnerHTML={{ __html: GL.lock }} /></g>);
  }
  // Wi-Fi boundary draws itself
  const wifi = minJerk((k - ev.wifi) / 50);
  const perim = 2 * (718 + 218) * sc;
  const corners = 18;
  return (
    <AbsoluteFill style={{ background: C.graphite, fontFamily: FONT, color: ink }}>
      <svg width={W} height={H} style={{ position: "absolute", inset: 0, opacity: enter }}>
        <rect x={X(1)} y={Y(1)} width={718 * sc} height={218 * sc} rx={28 * sc} fill="none" stroke={ink} strokeOpacity={0.3} strokeWidth={2.4} strokeDasharray={`3 ${7 * sc}`} strokeLinecap="round" style={{ strokeDashoffset: 0 }} mask="url(#wifiMask)" />
        <defs>
          <mask id="wifiMask"><rect x={X(1) - 20} y={Y(1) - 20} width={718 * sc + 40} height={218 * sc + 40} fill="none" stroke="#fff" strokeWidth={40} pathLength={1} strokeDasharray={`${wifi} 1`} rx={28 * sc} /></mask>
        </defs>
        <text x={X(28)} y={Y(40)} fill={ink} fillOpacity={0.62 * prog(k, ev.wifi + 20, 20)} fontSize={15 * sc} fontWeight={500} fontFamily={FONT}>Your Wi-Fi</text>
        {/* phone and Mac outlines */}
        <rect x={X(118)} y={Y(62)} width={64 * sc} height={122 * sc} rx={16 * sc} fill="none" stroke={ink} strokeOpacity={0.75} strokeWidth={2.4} />
        <rect x={X(508)} y={Y(74)} width={112 * sc} height={76 * sc} rx={8 * sc} fill="none" stroke={ink} strokeOpacity={0.75} strokeWidth={2.4} />
        <path d={`M${X(494)} ${Y(168)}h${140 * sc}`} stroke={ink} strokeOpacity={0.75} strokeWidth={2.4} strokeLinecap="round" />
        <path d={`M${X(196)} ${Y(123)}H${X(494)}`} stroke={ink} strokeOpacity={0.18} strokeWidth={2} strokeLinecap="round" />
        <text x={X(150)} y={Y(208)} textAnchor="middle" fill={ink} fillOpacity={0.62} fontSize={12 * sc} fontFamily={FONT}>iPhone</text>
        <text x={X(564)} y={Y(208)} textAnchor="middle" fill={ink} fillOpacity={0.62} fontSize={12 * sc} fontFamily={FONT}>Mac</text>
        <g opacity={qrFade}>{qrCells}</g>
        {/* viewfinder corners on the phone */}
        <g opacity={qrFade * prog(k, ev.qr + 10, 14)} stroke={ink} strokeWidth={2.4} strokeLinecap="round" fill="none">
          {[[-1, -1], [1, -1], [-1, 1], [1, 1]].map(([sx, sy], i) => {
            const r = 22 * sc * lerp(1, 0.86, scan);
            const x = pcx + sx * r, y = pcy + sy * r, l = 9 * sc;
            return <path key={i} d={`M${x} ${y - sy * l}V${y}H${x - sx * l}`} />;
          })}
        </g>
        <g opacity={qrFade}>
          <circle cx={pcx} cy={pcy} r={15 * sc * paired} fill={C.green} />
          <path d={`M${pcx - 6 * sc} ${pcy}l${4.5 * sc} ${4.5 * sc} ${8.5 * sc} ${-9 * sc}`} stroke="#fff" strokeWidth={3} fill="none" strokeLinecap="round" strokeLinejoin="round" pathLength={1} strokeDasharray={`${prog(k, ev.paired + 4, 12)} 1`} />
        </g>
        {pk}
      </svg>
      <Caption frame={f} c={{ at: at + 40, out: ev.packets + at - 26, title: "Pair with a QR code.", sub: "The key lives in the Keychain on both devices.", x: vertical ? 90 : ox, y: vertical ? 300 : 150, size: vertical ? 84 : 72, dark: true, maxW: vertical ? 900 : 1400 }} />
      <Caption frame={f} c={{ at: at + 160, out: ev.wifi + at - 22, title: "Encrypted, every message.", sub: "A fresh key for every connection.", x: vertical ? 90 : ox, y: vertical ? 300 : 150, size: vertical ? 84 : 72, dark: true, maxW: vertical ? 900 : 1400 }} />
      <Caption frame={f} c={{ at: at + 280, out: end - 20, title: "It stays on your network.", sub: "No accounts, no servers, no tracking.", x: vertical ? 90 : ox, y: vertical ? 300 : 150, size: vertical ? 84 : 72, dark: true, maxW: vertical ? 900 : 1400 }} />
      <div style={{ position: "absolute", left: ox, top: Y(260), display: "flex", gap: 40, opacity: prog(k, ev.wifi + 40, 20), color: C.onDark2, fontSize: vertical ? 26 : 24, fontWeight: 500 }}>
        <span style={{ display: "flex", gap: 12, alignItems: "center" }}><Icon d={GL.home} size={28} color={C.onDark} />Same Wi-Fi only</span>
        <span style={{ display: "flex", gap: 12, alignItems: "center" }}><Icon d={GL.noaccount} size={28} color={C.onDark} />No sign up</span>
      </div>
      {void corners}{void perim}
    </AbsoluteFill>
  );
};

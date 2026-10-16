import { phone, loopInView, reduce } from "./kit";
import { glyph } from "./glyphs";
import { menuBar } from "./scenes";

/* Pairing, as the Mac's menu bar popover draws it (Apps/Mac): click Glasspad in the menu bar,
   the code appears, the iPhone's camera reads it, then Paired and the phone's signal. The whole
   picture is authored at 1160 x 500 and scaled to fit. */

/** A QR-like code: three finder squares and a fixed pattern, drawn once. */
function qr() {
  const n = 25, cells: string[] = [];
  let seed = 7;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const finder = (x: number, y: number) => x < 8 && y < 8 || x > n - 9 && y < 8 || x < 8 && y > n - 9;
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
    if (finder(x, y)) continue;
    if (rnd() < 0.5) cells.push(`M${x} ${y}h1v1h-1z`);
  }
  const f = (x: number, y: number) => `M${x} ${y}h7v7h-7zM${x + 1} ${y + 1}v5h5v-5zM${x + 2} ${y + 2}h3v3h-3z`;
  return `<svg viewBox="-1 -1 ${n + 2} ${n + 2}" class="qr" aria-hidden="true"><rect x="-1" y="-1" width="${n + 2}" height="${n + 2}" fill="#fff"/><path fill-rule="evenodd" fill="#111" d="${f(0, 0)}${f(n - 7, 0)}${f(0, n - 7)}${cells.join("")}"/></svg>`;
}
const toggle = (on: boolean) => `<i class="tg${on ? " on" : ""}"></i>`;
const icon = '<svg viewBox="0 0 24 24" class="gp-i"><rect x="3" y="6" width="18" height="12" rx="3.5"/><circle cx="15" cy="11" r="1.8" fill="currentColor" stroke="none"/></svg>';

export function initPairing() {
  const root = document.getElementById("pairStage"); if (!root) return;
  const code = qr();
  const html = () => `<div class="pair-pt">
    <div class="pd"><div class="pd-screen">
      ${menuBar("Finder", ["File", "Edit", "View", "Go", "Window", "Help"], "Fri 9:41", `<span class="gp">${icon}</span>`)}
      <div class="gpop">
        <div class="ph"><b>Glasspad</b>${toggle(true)}</div>
        <div class="pstate wait">
          <div class="prow"><span class="pi">${glyph("iphone")}</span><div><b>No iPhone Paired</b><small>Scan the code below with your iPhone.</small></div></div>
          <div class="pcode">${code}<p>On your iPhone, open Glasspad, tap Pair a Mac and hold it over this code.</p><div class="plink">Show Code as Text</div><div class="pcancel">Cancel</div></div>
        </div>
        <div class="pstate done"><span class="pok">${glyph("checkmark")}</span><b>Paired with Soham&rsquo;s iPhone</b><small>Your iPhone now controls this Mac. Glasspad stays in the menu bar.</small></div>
        <div class="pstate conn"><div class="prow"><span class="pi blue">${glyph("iphone")}</span><div><b>Soham&rsquo;s iPhone</b><small>Excellent signal</small></div><span class="bars"><i></i><i></i><i></i><i></i></span></div>
          <div class="prow"><span class="pi">${glyph("qrcode")}</span><div><b>Pair Your iPhone&hellip;</b></div></div></div>
        <div class="pfoot"><div class="prow"><span class="pi">${glyph("menubar.dock.rectangle")}</span><div><b>Hide Mac Dock</b></div><span class="pmenu">Never${glyph("chevron.down")}</span></div><div class="gpm">Glasspad Settings&hellip;</div><div class="gpm">Quit Glasspad</div></div>
      </div>
      <svg class="pd-cursor" viewBox="0 0 16 22"><path d="M1 1v17l4.6-4.4 3 6.9 3-1.3-3-6.8H15Z" fill="#1A1A1A" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/></svg>
    </div></div>
    <div class="hp pair-hp">${phone("portrait", "dark", `<div class="cam-v"><div class="cam-q">${code}</div><i class="br tl"></i><i class="br tr"></i><i class="br bl"></i><i class="br br2"></i><span class="cam-ok">${glyph("checkmark")}</span></div>`)}</div>
  </div>`;
  const fit = () => { const pt = root.querySelector<HTMLElement>(".pair-pt"); if (pt) pt.style.transform = `scale(${root.clientWidth / 1160})`; };
  const reset = () => { root.innerHTML = html(); fit(); if (reduce) root.querySelector(".pair-pt")!.classList.add("open", "s-conn"); };
  new ResizeObserver(fit).observe(root);
  loopInView(root, root, root, async s => {
    const pt = root.querySelector<HTMLElement>(".pair-pt")!;
    await s.wait(700);
    pt.classList.add("click"); await s.wait(500);           // the pointer reaches Glasspad in the menu bar
    pt.classList.add("open", "s-wait"); await s.wait(1500); // the code
    pt.classList.add("aim"); await s.wait(1300);            // the iPhone's camera finds it
    pt.classList.add("seen"); await s.wait(700);
    pt.classList.replace("s-wait", "s-done"); await s.wait(2000);
    pt.classList.replace("s-done", "s-conn"); pt.classList.remove("aim", "seen"); await s.wait(2600);
    pt.classList.remove("open", "click"); await s.wait(800);
  }, reset);
}

import { lerp } from "./spring";
import { appIcon } from "./apps";
import { glyph } from "./glyphs";
import { phone, fitAll, tl, loopInView, settle } from "./kit";
import { menuBar } from "./scenes";

/* Displays: the phone shows the Mac's screens arranged as in System Settings > Displays, each
   with its windows. Here a Notes window moves from the MacBook to the Studio Display, Safari
   comes forward, and the display dims. */

const winMac = (cls: string, k: string) => `<div class="md-win dw ${cls}" data-w="${k}"><div class="wb"><i></i><i></i><i></i></div><div class="wbody"><div class="md-doc">${"<i></i>".repeat(5)}</div></div></div>`;
const thumb = (k: string, name: string, cls: string) => `<span class="dth ${cls}" data-w="${k}">${appIcon(k)}<small>${name}</small></span>`;

export function initDisplays() {
  const root = document.getElementById("dpStage"); if (!root) return;
  root.innerHTML = `<div class="scene uc uc-dp on"><div class="uc-wall"></div><div class="sc-desk"></div>
    <div class="mbw mb-dp"><div class="mbp"><div class="mbp-lid"><div class="mbp-glass"></div><div class="mbp-display"><div class="mbx">${menuBar("Notes", ["File", "Edit", "Format", "View"], "")}${winMac("n-mb front", "notes")}</div></div><div class="mbp-notch"></div></div><div class="mbp-hinge"></div><div class="mbp-base"><div class="mbp-keys"></div><div class="mbp-pad"></div></div><div class="mbp-lip"></div><div class="mbp-shadow"></div></div></div>
    <div class="mon mon-dp"><div class="mon-frame"><div class="mon-screen"><div class="mbx">${menuBar("Safari", ["File", "Edit", "View", "History", "Bookmarks", "Window"])}${winMac("s-st", "web")}${winMac("x-st front", "xcode")}${winMac("n-st", "notes")}<div class="dim"></div></div></div></div><div class="mon-neck"></div><div class="mon-foot"></div></div>
    <div class="sp sp-dp">${phone("landscape", "light", `<div class="pt land dsp">
      <div class="dh"><b>Displays</b><span>2 displays, 4 windows</span></div>
      <div class="dmap">
        <div class="dd big"><div class="ds">${thumb("web", "Safari", "t1")}${thumb("xcode", "Xcode", "t2 sel")}</div><small>Studio Display</small></div>
        <div class="dd small"><div class="ds">${thumb("notes", "Notes", "t3")}</div><small>MacBook Pro</small></div>
      </div>
      <div class="dpanel"><div class="af"><span class="af-i">${appIcon("xcode")}</span><div><b>Xcode</b><span>On Studio Display</span></div></div>
        <div class="ag">${tl("Left Half", "rectangle.lefthalf.filled", "#0A84FF")}${tl("Right Half", "rectangle.righthalf.filled", "#0A84FF")}${tl("Fill Screen", "macwindow", "#0A84FF")}${tl("Next Display", "rectangle.on.rectangle", "#0A84FF")}</div>
        <div class="bri">${glyph("sun.max.fill")}<div class="bri-bar"><i style="width:82%"></i><b style="left:82%"></b></div></div></div>
    </div>`)}<div class="sp-stand"><i></i></div></div>
  </div>`;
  fitAll(root);
  const sc = root.querySelector<HTMLElement>(".uc-dp")!, ph = root.querySelector<HTMLElement>(".ip-screen")!;
  const select = (s: { q: (x: string) => HTMLElement }, k: string, name: string, where: string) => {
    s.q(".dsp .dth.sel")?.classList.remove("sel");
    s.q(`.dsp .dth[data-w="${k}"]`).classList.add("sel");
    const af = s.q(".dpanel .af"); af.innerHTML = `<span class="af-i">${appIcon(k)}</span><div><b>${name}</b><span>On ${where}</span></div>`; settle([af]);
  };
  const reset = () => {
    sc.classList.remove("moved", "safari", "dimmed");
    const t3 = sc.querySelector<HTMLElement>(".t3"); if (t3) { t3.style.transform = ""; t3.classList.remove("on-big"); }
    sc.querySelector<HTMLElement>(".dsp .dd.small .ds")?.append(...(t3 ? [t3] : []));
    const bar = sc.querySelector<HTMLElement>(".bri .bri-bar"); if (bar) { (bar.firstElementChild as HTMLElement).style.width = "82%"; (bar.lastElementChild as HTMLElement).style.left = "82%"; }
    sc.style.setProperty("--dim", "0");
    sc.querySelectorAll(".dsp .dth.sel").forEach(e => e.classList.remove("sel")); sc.querySelector(".dsp .t2")?.classList.add("sel");
  };
  loopInView(root, ph, sc, async s => {
    await s.wait(700);
    // drag Notes from the MacBook to the Studio Display
    const t3 = s.q(".t3"), big = s.q(".dd.big .ds");
    const [x0, y0] = s.at(t3);
    const [bigX, bigY] = s.at(big), tx = bigX - big.offsetWidth / 2 + big.offsetWidth * 0.78, ty = bigY - big.offsetHeight / 2 + big.offsetHeight * 0.62;
    await s.touch(0, x0, y0); t3.classList.add("lift");
    await s.tween(900, e => { const x = lerp(x0, tx, e), y = lerp(y0, ty, e); s.put(0, x, y); t3.style.transform = `translate(${x - x0}px, ${y - y0}px) scale(1.06)`; });
    await s.lift(0, tx, ty);
    t3.classList.remove("lift"); t3.style.transform = ""; big.appendChild(t3); t3.classList.add("on-big"); settle([t3]);
    sc.classList.add("moved"); select(s, "notes", "Notes", "Studio Display");
    await s.wait(1600);
    // tap Safari: it comes forward
    await s.tap(s.q(".t1"), () => { sc.classList.add("safari"); select(s, "web", "Safari", "Studio Display"); });
    await s.wait(1500);
    // dim the Studio Display
    const bar = s.q(".bri .bri-bar"), knob = bar.lastElementChild as HTMLElement, fill = bar.firstElementChild as HTMLElement;
    const [kx, ky] = s.at(knob), w = bar.offsetWidth;
    await s.touch(0, kx, ky);
    await s.tween(900, e => { const v = lerp(82, 40, e); s.put(0, kx - (82 - v) / 100 * w, ky); knob.style.left = fill.style.width = v + "%"; sc.style.setProperty("--dim", ((82 - v) / 100).toFixed(3)); });
    await s.lift(0, kx - 0.42 * w, ky);
    await s.wait(1800);
  }, reset);
}

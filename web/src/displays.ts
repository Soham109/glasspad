import { lerp } from "./spring";
import { appIcon } from "./apps";
import { glyph } from "./glyphs";
import { phone, fitAll, loopInView } from "./kit";
import { menuBar } from "./scenes";

/* Displays, as DisplaysMode.swift draws it sideways: the arrangement box with each display's
   windows, the window list beside it, the touch-and-hold menu and the display sheet. Here Mail
   moves from the MacBook to the Studio Display, fills it, and the Studio Display is dimmed. */

const macWin = (cls: string, k: string) => `<div class="md-win dw ${cls}" data-w="${k}"><div class="wb"><i></i><i></i><i></i></div><div class="wbody"><div class="md-doc">${"<i></i>".repeat(5)}</div></div></div>`;
const thumb = (k: string, cls: string) => `<span class="dwin ${cls}" data-w="${k}">${appIcon(k)}</span>`;
const row = (k: string, name: string, sub: string) => `<div class="drow" data-w="${k}">${appIcon(k)}<div><b>${name}</b><span>${sub}</span></div></div>`;
const menuItem = (label: string, g: string, cls = "", more = false) => `<span class="${cls}">${glyph(g)}${label}${more ? glyph("chevron.right") : ""}</span>`;

const html = () => `<div class="scene uc uc-dp on"><div class="uc-wall"></div><div class="sc-desk"></div>
  <div class="mbw mb-dp"><div class="mbp"><div class="mbp-lid"><div class="mbp-glass"></div><div class="mbp-display"><div class="mbx">${menuBar("Mail", ["File", "Edit", "View", "Mailbox"], "")}${macWin("m-mb front", "mail")}${macWin("g-mb", "msg")}</div></div><div class="mbp-notch"></div></div><div class="mbp-hinge"></div><div class="mbp-base"><div class="mbp-keys"></div><div class="mbp-pad"></div></div><div class="mbp-lip"></div><div class="mbp-shadow"></div></div></div>
  <div class="mon mon-dp"><div class="mon-frame"><div class="mon-screen"><div class="mbx">${menuBar("Safari", ["File", "Edit", "View", "History", "Bookmarks", "Window"])}${macWin("s-st front", "web")}${macWin("x-st", "xcode")}${macWin("m-st", "mail")}<div class="dim"></div></div></div></div><div class="mon-neck"></div><div class="mon-foot"></div></div>
  <div class="sp sp-dp">${phone("landscape", "light", `<div class="pt land dsp">
    <span class="dx">${glyph("xmark")}</span><div class="dh"><b>Displays</b><span>2 displays &middot; 4 windows</span></div><span class="dset">Settings</span>
    <div class="dbox">
      <div class="dd small"><div class="ds">${thumb("mail", "w-mail")}${thumb("msg", "w-msg")}</div><small>Built-in Retina Display</small></div>
      <div class="dd big"><div class="ds">${thumb("web", "w-saf")}${thumb("xcode", "w-xc")}</div><small>Studio Display</small></div>
    </div>
    <div class="dlist">${row("web", "Safari", "Apple &middot; Studio Display")}${row("mail", "Mail", "Inbox &middot; Built-in Retina Display")}${row("xcode", "Xcode", "Glasspad &middot; Studio Display")}${row("msg", "Messages", "Built-in Retina Display")}</div>
    <div class="dmenu">${menuItem("Left Half", "rectangle.lefthalf.filled")}${menuItem("Right Half", "rectangle.righthalf.filled")}${menuItem("Top Half", "rectangle.tophalf.filled")}${menuItem("Bottom Half", "rectangle.bottomhalf.filled")}<i></i>${menuItem("Fill", "rectangle.inset.filled", "fill")}${menuItem("Center", "rectangle.center.inset.filled")}${menuItem("Split With", "rectangle.split.2x1", "", true)}</div>
    <div class="dsheet"><div class="dsh"><b>Studio Display</b><span class="ok">${glyph("checkmark")}</span></div>
      <div class="dseg"><span>Built-in</span><span class="on">Studio Display</span></div>
      <div class="dbl">Brightness</div><div class="dbri">${glyph("sun.min")}<div class="bri-bar"><i style="width:80%"></i><b style="left:80%"></b></div>${glyph("sun.max")}</div>
      <div class="dres"><b>Resolution</b><span>Looks like 2560 &times; 1440</span></div>
      <div class="dns">${glyph("moon.fill")}<b>Night Shift</b><i></i></div></div>
  </div>`)}<div class="sp-stand"><i></i></div></div>
</div>`;

export function initDisplays() {
  const root = document.getElementById("dpStage"); if (!root) return;
  const reset = () => { root.innerHTML = html(); fitAll(root); };
  loopInView(root, root, root, async s => {
    const scene = root.querySelector<HTMLElement>(".uc-dp")!;
    await s.wait(900);
    // drag Mail from the MacBook to the Studio Display
    const mail = s.q(".dsp .w-mail"), big = s.q(".dsp .dd.big .ds");
    const [x0, y0] = s.at(mail), [bx, by] = s.at(big);
    const tx = bx - big.offsetWidth * 0.18, ty = by - big.offsetHeight * 0.12;
    await s.touch(0, x0, y0); mail.classList.add("lift");
    await s.tween(900, e => { const x = lerp(x0, tx, e), y = lerp(y0, ty, e); s.put(0, x, y); mail.style.transform = `translate(${x - x0}px, ${y - y0}px)`; });
    await s.lift(0, tx, ty);
    mail.classList.remove("lift"); mail.style.transform = ""; big.appendChild(mail);
    scene.classList.add("moved");
    root.querySelector(".mb-dp .mb")!.outerHTML = menuBar("Messages", ["File", "Edit", "View", "Conversation"], "");
    s.q('.drow[data-w="mail"] span').innerHTML = "Inbox &middot; Studio Display";
    await s.wait(1300);
    // touch and hold: Fill
    const [mx, my] = s.at(mail);
    await s.touch(0, mx, my); await s.wait(450);
    mail.classList.add("held"); s.q(".dmenu").classList.add("on");
    await s.lift(0, mx, my); await s.wait(700);
    await s.tap(s.q(".dmenu .fill"), () => { s.q(".dmenu").classList.remove("on"); mail.classList.remove("held"); mail.classList.add("filled"); scene.classList.add("filled");
      root.querySelector(".mon-dp .mb")!.outerHTML = menuBar("Mail", ["File", "Edit", "View", "Mailbox", "Message", "Format", "Window"]); });
    await s.wait(1500);
    // the display sheet: brightness
    await s.tap(s.q(".dset"), () => s.q(".dsheet").classList.add("on"));
    await s.wait(700);
    const bar = s.q(".dsheet .bri-bar"), knob = bar.lastElementChild as HTMLElement, fill = bar.firstElementChild as HTMLElement;
    const [kx, ky] = s.at(knob), w = bar.offsetWidth;
    await s.touch(0, kx, ky);
    await s.tween(900, e => { const v = lerp(80, 42, e); s.put(0, kx - (80 - v) / 100 * w, ky); knob.style.left = fill.style.width = v + "%"; scene.style.setProperty("--dim", ((80 - v) / 100).toFixed(3)); });
    await s.lift(0, kx - 0.38 * w, ky);
    await s.wait(1200);
    await s.tap(s.q(".dsheet .ok"), () => s.q(".dsheet").classList.remove("on"));
    await s.wait(1600);
  }, reset);
}

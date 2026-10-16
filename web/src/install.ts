import { reducedMotion } from "./spring";

/* Small drawings of the exact screens the install asks you to click or tap, built only when
   they come near the viewport. Sizes are in em; each figure scales its font to fit its column. */

const ring = (inner: string, tag: string, pos = "b", cls = "") => `<span class="hl ${cls}">${inner}<b class="tag t-${pos}">${tag}</b></span>`;
const SIZE: Record<string, [number, number]> = {
  termPass: [44, 14], xcAccounts: [44, 19], xcSigning: [56, 19], macAccess: [46, 19], macPair: [34, 23],
  ipTrust: [21, 25], ipDevPage: [21, 25], ipDevAlert: [21, 25], ipVpn: [21, 25], ipVpnTrust: [21, 25], ipLocal: [21, 25],
};
const figSlot = (k: string) => `<div class="fig${SIZE[k][0] < 30 ? " ph" : ""}" data-fig="${k}" style="--w:${SIZE[k][0]};--h:${SIZE[k][1]}" role="img" aria-hidden="true"></div>`;
const badge = (n: number) => `<b class="nb">${n}</b>`;
const tl = '<span class="tl"><i></i><i></i><i></i></span>';
const macWin = (body: string, title = "", cls = "") => `<div class="mw ${cls}"><div class="mw-bar">${tl}${title ? `<span class="mw-t">${title}</span>` : ""}</div><div class="mw-body">${body}</div></div>`;
const phone = (body: string, dim = false) => `<div class="fp"><div class="fp-scr${dim ? " dim" : ""}"><div class="fp-status"><b>9:41</b><span class="fp-island"></span><span class="fp-bat"></span></div>${body}</div></div>`;
const homeScreen = `<div class="fp-home">${"<i></i>".repeat(16)}</div>`;
const alert = (title: string, msg: string, buttons: string) => `<div class="fp-alert"><b class="fa-t">${title}</b>${msg ? `<span class="fa-m">${msg}</span>` : ""}<div class="fa-b">${buttons}</div></div>`;
const btn = (label: string, strong = false) => `<span class="fa-btn${strong ? " strong" : ""}">${label}</span>`;
const nav = (title: string) => `<div class="fp-nav"><span class="fp-back"><svg viewBox="0 0 24 24"><path d="m14.5 5-7 7 7 7"/></svg></span><b>${title}</b></div>`;
const toggle = (on = true) => `<span class="tg${on ? " on" : ""}"><i></i></span>`;
const chev = '<svg class="chev" viewBox="0 0 24 24"><path d="m9.5 5 7 7-7 7"/></svg>';
const gpIcon = '<span class="gp-ic"><svg viewBox="0 0 24 24"><rect x="3" y="6" width="18" height="12" rx="3.5"/><circle cx="14.5" cy="11" r="1.6" fill="currentColor" stroke="none"/><path d="M8.5 14.2 12.4 12.2" opacity=".55"/></svg></span>';

const FIGS: Record<string, () => string> = {
  termPass: () => macWin(`<div class="tp"><p class="tp-dim">1. Xcode</p><p>Xcode needs its one-time setup and license. Enter your Mac password if asked.</p><p>${ring('<span class="tp-pw">Password:<i></i></span>', "Type your Mac password", "r")}</p></div>`, "Terminal"),

  xcAccounts: () => macWin(`
    <div class="xs-tabs">${["General", "Apple Accounts", "Behaviors", "Navigation", "Themes"].map((t, i) => `<span class="xs-tab${i === 1 ? " on" : ""}"><i></i>${t}</span>`).join("")}</div>
    <div class="xs-pane">
      <div class="xs-list"><div class="xs-empty"></div><div class="xs-pm">${ring('<span class="pm">+</span>', "Click +, then sign in", "r")}<span class="pm">&minus;</span></div></div>
      <div class="xs-detail"></div>
    </div>`, "Apple Accounts"),

  xcSigning: () => macWin(`
    <div class="xc">
      <div class="xc-nav">
        <div class="xc-row sel"><span class="xc-proj"></span>Glasspad${badge(1)}</div>
        ${'<div class="xc-row faint"><span class="xc-fold"></span><i></i></div>'.repeat(4)}
      </div>
      <div class="xc-targets">
        <span class="xc-cap">PROJECT</span>
        <div class="xc-row"><span class="xc-proj"></span>Glasspad</div>
        <span class="xc-cap">TARGETS</span>
        <div class="xc-row sel"><span class="xc-app"></span>Glasspad iOS${badge(2)}</div>
        <div class="xc-row"><span class="xc-app"></span>Glasspad Widgets</div>
        <div class="xc-row"><span class="xc-app mac"></span>Glasspad Mac</div>
      </div>
      <div class="xc-main">
        <div class="xc-tabs"><span>General</span><span class="on">Signing &amp; Capabilities${badge(3)}</span><span>Resource Tags</span><span>Info</span></div>
        <div class="xc-sign">
          <b class="xc-h">Signing</b>
          <div class="xc-f"><span class="k"></span><span class="cb on"><svg viewBox="0 0 24 24"><path d="m6 12.5 4 4 8-9"/></svg></span>Automatically manage signing</div>
          <div class="xc-f"><span class="k">Team</span>${ring(`<span class="pop">Your Name (Personal Team)<svg viewBox="0 0 24 24"><path d="m8 9.5 4-4 4 4M8 14.5l4 4 4-4"/></svg></span>`, "Pick your name", "b")}</div>
          <div class="xc-f" style="margin-top:2.2em"><span class="k">Bundle Identifier</span><span class="v">com.soham109.glasspad.ios</span></div>
        </div>
      </div>
    </div>`, "Glasspad"),

  macAccess: () => `<div class="mw ss"><div class="ss-side">${tl}<div class="ss-search">Search</div>
      ${[["Screen Time", "#5E5CE6"], ["Lock Screen", "#1C1C1E"], ["Privacy &amp; Security", "#0A84FF"], ["Touch ID &amp; Password", "#FF3B30"], ["Users &amp; Groups", "#0A84FF"]].map(([n, c], i) => `<div class="ss-item${i === 2 ? " sel" : ""}"><i style="background:${c}"></i>${n}</div>`).join("")}
    </div><div class="ss-main">
      <div class="ss-head"><span class="ss-back"><svg viewBox="0 0 24 24"><path d="m14.5 5-7 7 7 7"/></svg></span><b>Accessibility</b></div>
      <p class="ss-desc">Allow the applications below to control your computer.</p>
      <div class="ss-card"><div class="ss-row">${gpIcon}<span>Glasspad</span>${ring(toggle(true), "Switch on", "b", "r-pill")}</div></div>
      <div class="ss-pm"><span>+</span><span>&minus;</span></div>
    </div></div>`,

  ipTrust: () => phone(homeScreen + alert("Trust This Computer?", "Your settings and data will be accessible from this computer when connected.", ring(btn("Trust", true), "Tap", "b", "r-pill") + btn("Don't Trust")), true),

  ipDevPage: () => phone(`${nav("Developer Mode")}
    <div class="fp-card"><div class="fp-row"><span>Developer Mode</span>${ring(toggle(true), "Switch on", "b", "r-pill")}</div></div>
    <div class="fp-lines"><i></i><i></i><i style="width:60%"></i></div>`),

  ipDevAlert: () => phone(homeScreen + alert("Turn On Developer Mode?", "", btn("Cancel") + ring(btn("Turn On", true), "Tap", "b", "r-pill")), true),

  ipVpn: () => phone(`${nav("VPN &amp; Device Management")}
    <span class="fp-cap">DEVELOPER APP</span>
    <div class="fp-card">${ring(`<div class="fp-row"><span>Apple Development: your Apple ID</span>${chev}</div>`, "Tap", "b", "r-row")}</div>`),

  ipVpnTrust: () => phone(`${nav("Apple Development")}
    <div class="fp-card">${ring(`<div class="fp-row link"><span>Trust &ldquo;Apple Development: your Apple ID&rdquo;</span></div>`, "Tap, then Trust", "b", "r-row")}</div>
    <span class="fp-cap" style="margin-top:3em">APPS</span>
    <div class="fp-card"><div class="fp-row"><span class="fp-app"></span><span>Glasspad</span></div></div>`),

  macPair: () => `<div class="mp">
      <div class="mp-bar">${ring(`<span class="mp-ic"><svg viewBox="0 0 24 24"><rect x="3" y="6" width="18" height="12" rx="3.5"/><circle cx="15" cy="11" r="1.8" fill="currentColor" stroke="none"/></svg></span>`, "Click", "l", "r-ic")}<span class="mp-wifi"></span><span class="mp-batt"></span><span class="mp-cc"></span><span class="mp-clock">Fri 9:41</span></div>
      <div class="mp-pop">
        <div class="mp-row t mp-title"><b>Glasspad</b>${toggle(true)}</div>
        <hr>
        <div class="mp-head"><span class="mp-circ"><svg viewBox="0 0 24 24"><rect x="7.5" y="3.5" width="9" height="17" rx="2.5"/><path d="M4 4l16 16"/></svg></span><div><b>No iPhone Paired</b><small>Pair your iPhone to use it as a trackpad.</small></div></div>
        ${ring(`<div class="mp-row"><span class="mp-circ s"><svg viewBox="0 0 24 24"><rect x="4" y="4" width="6" height="6" rx="1.2"/><rect x="14" y="4" width="6" height="6" rx="1.2"/><rect x="4" y="14" width="6" height="6" rx="1.2"/><path d="M14 14h2.5v2.5M20 14v.01M14 20h.01M17.5 17.5V20H20"/></svg></span>Pair Your iPhone&hellip;</div>`, "Then this", "l", "r-row")}
        <div class="mp-row t">Hide Mac Dock${toggle(false)}</div>
        <hr>
        <div class="mp-row">Glasspad Settings&hellip;</div>
        <div class="mp-row">Quit Glasspad</div>
      </div>
    </div>`,

  ipLocal: () => phone(homeScreen + alert("&ldquo;Glasspad&rdquo; Would Like to Find and Connect to Devices on Your Local Network", "Glasspad finds your paired Mac on this Wi-Fi network and sends your touches to it.", btn("Don't Allow") + ring(btn("Allow", true), "Tap", "b", "r-pill")), true),
};

function initStepper(reduce: boolean) {
  const root = document.getElementById("stepper"); if (!root) return;
  const view = document.getElementById("stpView")!;
  const items = Array.from(root.querySelectorAll<HTMLElement>(".stp-i"));
  const heads = items.map(i => i.querySelector<HTMLButtonElement>(".stp-h")!);
  const subs = Array.from(root.querySelectorAll<HTMLElement>(".sub"));
  const wide = matchMedia("(min-width: 861px)");
  // one panel view per sub-step, and the same drawings inline for the phone accordion
  const views = new Map<string, HTMLElement>();
  for (const sub of subs) {
    const key = sub.dataset.view!;
    const v = document.createElement("div"); v.className = "stp-v";
    if (sub.dataset.figs) {
      const html = sub.dataset.figs.split(",").map(figSlot).join("");
      v.innerHTML = `<div class="stp-figs">${html}</div>`;
      sub.querySelector(".stp-mf")!.innerHTML = `<div class="figs">${html}</div>`;
    } else {
      v.innerHTML = `<div class="stp-auto"><span>Automatic</span><code>${sub.dataset.auto}</code></div>`;
    }
    view.appendChild(v); views.set(key, v);
    // in steps with parts, each part picks its drawing
    if (sub.parentElement!.children.length > 1) {
      sub.classList.add("pick");
      const a11y = () => { if (wide.matches) { sub.tabIndex = 0; sub.setAttribute("role", "button"); } else { sub.removeAttribute("tabindex"); sub.removeAttribute("role"); } };
      a11y(); wide.addEventListener("change", a11y);
      const go = () => showView(key);
      sub.addEventListener("click", go);
      sub.addEventListener("focus", go);
      sub.addEventListener("keydown", e => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); go(); } });
    }
  }
  let cur = -1, curView = "";
  function showView(key: string) {
    if (key === curView) return; curView = key;
    views.forEach((v, k) => v.classList.toggle("on", k === key));
    subs.forEach(s => s.classList.toggle("on", s.dataset.view === key));
  }
  function open(i: number, toggle = false) {
    if (toggle && i === cur && !wide.matches) { cur = -1; } else cur = i;
    items.forEach((it, k) => { it.classList.toggle("on", k === cur); heads[k].setAttribute("aria-expanded", String(k === cur)); });
    if (cur >= 0) showView(items[cur].querySelector<HTMLElement>(".sub")!.dataset.view!);
  }
  let lastClick = 0;
  heads.forEach((h, i) => {
    h.addEventListener("click", () => { lastClick = scrollY; open(i, true); });
    h.addEventListener("keydown", e => {
      const d = e.key === "ArrowDown" ? 1 : e.key === "ArrowUp" ? -1 : 0;
      if (e.key === "Home" || e.key === "End") { e.preventDefault(); heads[e.key === "Home" ? 0 : heads.length - 1].focus(); }
      if (d) { e.preventDefault(); heads[(i + d + heads.length) % heads.length].focus(); }
    });
  });
  open(0);
  // wide screens: scrolling through the list moves the active step
  let ticking = false;
  addEventListener("scroll", () => {
    if (ticking || !wide.matches) return; ticking = true;
    requestAnimationFrame(() => {
      ticking = false;
      if (Math.abs(scrollY - lastClick) < 80) return;
      const line = innerHeight * 0.42; let a = 0;
      heads.forEach((h, i) => { if (h.getBoundingClientRect().top < line) a = i; });
      const r = root.getBoundingClientRect();
      if (r.top < line && r.bottom > line && a !== cur) open(a);
    });
  }, { passive: true });
  if (reduce) root.classList.add("rm");
}

export function initInstall() {
  initStepper(reducedMotion());
  const figs = Array.from(document.querySelectorAll<HTMLElement>(".fig[data-fig]"));
  const build = (el: HTMLElement) => { const f = FIGS[el.dataset.fig!]; if (f && !el.dataset.built) { el.innerHTML = `<div class="fi">${f()}</div>`; el.dataset.built = "1"; } };
  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) { build(e.target as HTMLElement); io.unobserve(e.target); } }), { rootMargin: "600px 0px" });
    figs.forEach(f => io.observe(f));
  } else figs.forEach(build);
  if (reducedMotion()) document.documentElement.classList.add("rm");

  // copy buttons
  document.querySelectorAll<HTMLButtonElement>("button.copy[data-copy]").forEach(b => {
    const label = b.querySelector("span")!;
    b.addEventListener("click", async () => {
      try { await navigator.clipboard.writeText(b.dataset.copy!); } catch { return; }
      b.classList.add("done"); label.textContent = "Copied";
      setTimeout(() => { b.classList.remove("done"); label.textContent = "Copy"; }, 1800);
    });
  });

  // footer wordmark spans the full width
  const mark = document.getElementById("footMark");
  if (mark) {
    const box = mark.parentElement!;
    let last = 0;
    const fit = () => {
      const cs = getComputedStyle(box); const avail = box.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight) - 2; if (!avail || avail === last) return; last = avail;
      box.style.fontSize = "100px"; const w = mark.getBoundingClientRect().width;
      box.style.fontSize = `${(100 * avail / w).toFixed(2)}px`;
    };
    new ResizeObserver(fit).observe(mark.parentElement!);
    document.fonts?.ready.then(fit);
    fit();
  }
}

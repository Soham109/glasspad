import { clamp, reducedMotion, sleep } from "./spring";
import screens from "./screens.json";

const reduce = reducedMotion();

/* ---------- Reveals: each block rises once as it enters ---------- */
export function initReveals() {
  const els = document.querySelectorAll<HTMLElement>(".reveal");
  if (reduce) { els.forEach(e => e.classList.add("in")); return; }
  // stagger siblings that enter together
  const io = new IntersectionObserver(entries => {
    let i = 0;
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      const el = e.target as HTMLElement;
      el.style.setProperty("--d", `${i++ * 70}ms`);
      el.classList.add("in"); io.unobserve(el);
    }
  }, { rootMargin: "0px 0px -12% 0px" });
  els.forEach(e => io.observe(e));
}

/* ---------- Nav: hairline after scrolling, dark over dark sections ---------- */
export function initNav() {
  const nav = document.getElementById("nav")!;
  const darks = Array.from(document.querySelectorAll<HTMLElement>(".dark"));
  const update = () => {
    nav.classList.toggle("scrolled", scrollY > 8);
    const y = 28;
    nav.classList.toggle("on-dark", darks.some(d => { const r = d.getBoundingClientRect(); return r.top <= y && r.bottom >= y; }));
  };
  addEventListener("scroll", update, { passive: true });
  update();
}

/* ---------- Scroll-linked: hero mark eases back, demo phone settles into place ---------- */
export function initScrollLinked() {
  if (reduce) return;
  const mark = document.querySelector<SVGElement>("#heroGlide");
  const phone = document.getElementById("phone");
  const demo = document.getElementById("try");
  let ticking = false;
  const update = () => {
    ticking = false;
    const vh = innerHeight;
    if (mark) {
      const p = clamp(scrollY / (vh * 0.9), 0, 1);
      mark.style.transform = `translateY(${(p * 40).toFixed(1)}px) scale(${(1 - p * 0.08).toFixed(4)})`;
    }
    if (phone && demo) {
      const r = demo.getBoundingClientRect();
      // 0 when the section top is at the bottom of the screen, 1 once it is a third of the way up
      const p = clamp((vh - r.top) / (vh * 0.75), 0, 1);
      const e = 1 - Math.pow(1 - p, 3);
      phone.style.transform = `translateY(${((1 - e) * 64).toFixed(1)}px) scale(${(0.94 + e * 0.06).toFixed(4)})`;
    }
  };
  addEventListener("scroll", () => { if (!ticking) { ticking = true; requestAnimationFrame(update); } }, { passive: true });
  update();
}

/* ---------- Modes: sticky phone follows the list ---------- */
const MODE_TILES: Record<string, [number, number]> = {
  intro: [0, 0], dock: [1, 0], keys: [2, 0], media: [3, 0], deck: [0, 1], macros: [1, 1], clipboard: [2, 1], present: [3, 1],
};
export function initModes() {
  const list = Array.from(document.querySelectorAll<HTMLElement>(".mode"));
  const views = document.getElementById("modeViews")!;
  const pill = document.getElementById("pill")!;
  const phone = document.getElementById("modePhone")!;
  const real = (screens as string[]).includes("modes.png");

  if (real) {
    // Real screenshots: one composite of 4 x 2 phones (each 340 x 739 at x 68 + 388i, y 70 + 787j in a 1640 x 1666 image)
    phone.classList.add("has-shots");
    for (const m of list) {
      const [i, j] = MODE_TILES[m.dataset.mode!];
      const v = document.createElement("div");
      v.className = "mv shot-tile"; v.dataset.mode = m.dataset.mode;
      v.style.backgroundPosition = `${((68 + 388 * i) / (1640 - 340) * 100).toFixed(4)}% ${((70 + 787 * j) / (1666 - 739) * 100).toFixed(4)}%`;
      views.appendChild(v);
    }
    // on narrow screens each mode carries its own screenshot
    for (const m of list) {
      const [i, j] = MODE_TILES[m.dataset.mode!];
      const t = document.createElement("div");
      t.className = "mode-shot shot-tile"; t.setAttribute("aria-hidden", "true");
      t.style.backgroundPosition = `${((68 + 388 * i) / (1640 - 340) * 100).toFixed(4)}% ${((70 + 787 * j) / (1666 - 739) * 100).toFixed(4)}%`;
      m.appendChild(t);
    }
    new IntersectionObserver(([e], o) => { if (e.isIntersecting) { document.getElementById("modeList")!.classList.add("load"); o.disconnect(); } }, { rootMargin: "600px" }).observe(document.getElementById("modeList")!);
    // load the image only when the section comes near
    new IntersectionObserver(([e], o) => { if (e.isIntersecting) { phone.classList.add("load"); o.disconnect(); } }, { rootMargin: "600px" }).observe(phone);
  } else {
    for (const m of list) {
      const v = document.createElement("div");
      v.className = "mv mv-icon"; v.dataset.mode = m.dataset.mode;
      v.innerHTML = `<svg width="72" height="72"><use href="#i-${m.dataset.mode}"/></svg>`;
      views.appendChild(v);
    }
  }

  let current = "";
  const show = (mode: string) => {
    if (mode === current) return;
    current = mode;
    list.forEach(m => m.classList.toggle("active", m.dataset.mode === mode));
    views.querySelectorAll<HTMLElement>(".mv").forEach(v => v.classList.toggle("on", v.dataset.mode === mode));
    const item = list.find(m => m.dataset.mode === mode)!;
    pill.innerHTML = `<svg width="14" height="14"><use href="#i-${mode}"/></svg><span>${item.querySelector("h3")!.textContent}</span>`;
    if (!reduce) { pill.classList.remove("swap"); void pill.offsetWidth; pill.classList.add("swap"); }
  };
  show("dock");
  // the item crossing the middle of the screen is the active one
  const io = new IntersectionObserver(entries => {
    for (const e of entries) if (e.isIntersecting) show((e.target as HTMLElement).dataset.mode!);
  }, { rootMargin: "-50% 0px -50% 0px" });
  list.forEach(m => io.observe(m));
}

/* ---------- Per-app button sets (the starter sets that ship in GlasspadMacros) ---------- */
const PROFILES: { name: string; buttons: [string, string][] }[] = [
  { name: "Safari", buttons: [["New Tab", "⌘T"], ["Reopen Closed Tab", "⇧⌘T"], ["Show All Tabs", "⇧⌘\\"], ["Reload", "⌘R"], ["Reader", "⇧⌘R"], ["Address Bar", "⌘L"], ["Previous Tab", "⇧⌘["], ["Next Tab", "⇧⌘]"], ["Private Window", "⇧⌘N"], ["Downloads", "⌥⌘L"]] },
  { name: "Finder", buttons: [["New Window", "⌘N"], ["New Folder", "⇧⌘N"], ["Go to Folder", "⇧⌘G"], ["Get Info", "⌘I"], ["Quick Look", "Space"], ["Hidden Files", "⇧⌘."], ["Downloads", "⌥⌘L"], ["Move to Trash", "⌘⌫"], ["Connect to Server", "⌘K"], ["AirDrop", "⇧⌘R"]] },
  { name: "Xcode", buttons: [["Build", "⌘B"], ["Run", "⌘R"], ["Stop", "⌘."], ["Test", "⌘U"], ["Clean Build Folder", "⇧⌘K"], ["Open Quickly", "⇧⌘O"], ["Navigator", "⌘0"], ["Debug Area", "⇧⌘Y"], ["Find in Project", "⇧⌘F"], ["Comment Lines", "⌘/"]] },
  { name: "Keynote", buttons: [["Play Slideshow", "⌥⌘P"], ["New Slide", "⇧⌘N"], ["Duplicate", "⌘D"], ["Group", "⌥⌘G"], ["Ungroup", "⌥⇧⌘G"], ["Inspector", "⌥⌘I"]] },
  { name: "Music", buttons: [["Play / Pause", "Space"], ["Previous", "⌘←"], ["Next", "⌘→"], ["Volume Down", "⌘↓"], ["Volume Up", "⌘↑"], ["Current Song", "⌘L"]] },
  { name: "Figma", buttons: [["Move", "V"], ["Frame", "F"], ["Rectangle", "R"], ["Text", "T"], ["Pen", "P"], ["Comment", "C"], ["Zoom to Fit", "⇧1"], ["Group", "⌘G"], ["Create Component", "⌥⌘K"], ["Hide UI", "⌘\\"]] },
  { name: "VS Code", buttons: [["Command Palette", "⇧⌘P"], ["Quick Open", "⌘P"], ["Terminal", "⌃`"], ["Sidebar", "⌘B"], ["Find in Files", "⇧⌘F"], ["Format Document", "⇧⌥F"], ["Go to Line", "⌃G"], ["Toggle Comment", "⌘/"], ["Split Editor", "⌘\\"], ["Rename Symbol", "F2"]] },
  { name: "Everywhere else", buttons: [["Spotlight", "⌘Space"], ["Screenshot Area", "⇧⌘4"], ["Screenshot Tools", "⇧⌘5"], ["Mission Control", "⌃↑"], ["Emoji and Symbols", "⌃⌘Space"], ["Force Quit", "⌥⌘⎋"], ["Lock Screen", "⌃⌘Q"]] },
];
export function initProfiles() {
  const picker = document.getElementById("picker")!;
  const grid = document.getElementById("buttons")!;
  const head = document.getElementById("profileHead")!;
  const front = document.getElementById("frontName")!;
  const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
  const tabs: HTMLButtonElement[] = [];
  const select = (i: number, focus = false) => {
    const p = PROFILES[i];
    tabs.forEach((t, k) => { t.setAttribute("aria-selected", String(k === i)); t.tabIndex = k === i ? 0 : -1; });
    if (focus) tabs[i].focus();
    head.textContent = p.name;
    front.textContent = p.name === "Everywhere else" ? "Any other app" : p.name;
    if (!reduce) { front.classList.remove("swap"); void front.offsetWidth; front.classList.add("swap"); }
    grid.innerHTML = p.buttons.map(([n, k], j) => `<div class="pbtn" style="--i:${j}"><span>${esc(n)}</span><kbd>${esc(k)}</kbd></div>`).join("");
  };
  PROFILES.forEach((p, i) => {
    const b = document.createElement("button");
    b.setAttribute("role", "tab"); b.textContent = p.name;
    b.addEventListener("click", () => { stopAuto(); select(i); });
    b.addEventListener("keydown", e => {
      const d = e.key === "ArrowDown" || e.key === "ArrowRight" ? 1 : e.key === "ArrowUp" || e.key === "ArrowLeft" ? -1 : 0;
      if (d) { e.preventDefault(); stopAuto(); select((i + d + PROFILES.length) % PROFILES.length, true); }
    });
    tabs.push(b); picker.appendChild(b);
  });
  select(0);

  // While nobody touches it, the front app changes every few seconds, like switching apps on a Mac.
  let auto = 0, idx = 0, visible = false;
  const stopAuto = () => { clearInterval(auto); auto = -1; };
  if (!reduce) {
    new IntersectionObserver(([e]) => { visible = e.isIntersecting; }, { threshold: 0.4 }).observe(grid);
    auto = window.setInterval(() => { if (auto === -1 || !visible || document.hidden) return; idx = (idx + 1) % 3; select(idx); }, 3200);
    picker.addEventListener("pointerenter", () => stopAuto(), { once: true });
  }
}

/* ---------- Recorded steps arrive one by one, tied to scroll ---------- */
export function initSteps() {
  const items = Array.from(document.querySelectorAll<HTMLElement>("#steps li"));
  if (reduce) { items.forEach(i => i.classList.add("in")); return; }
  const io = new IntersectionObserver(async ([e], o) => {
    if (!e.isIntersecting) return; o.disconnect();
    for (const it of items) { it.classList.add("in"); await sleep(170); }
  }, { rootMargin: "0px 0px -25% 0px" });
  io.observe(document.getElementById("steps")!);
}

/* ---------- Privacy: packets travel phone to Mac, never past the network edge ---------- */
export function initNet() {
  const g = document.getElementById("netPackets");
  const svg = document.getElementById("net");
  if (!g || !svg) return;
  const NS = "http://www.w3.org/2000/svg";
  const x0 = 200, x1 = 490, y = 123;
  if (reduce) {
    for (const x of [260, 340, 420]) { const c = document.createElementNS(NS, "circle"); c.setAttribute("cx", String(x)); c.setAttribute("cy", String(y)); c.setAttribute("r", "4"); c.setAttribute("class", "packet"); g.appendChild(c); }
    return;
  }
  type Pk = { el: SVGCircleElement; t0: number; dir: 1 | -1; dur: number };
  const pks: Pk[] = [];
  let visible = false, running = false, next = 0;
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; if (visible && !running) { running = true; requestAnimationFrame(tick); } }).observe(svg);
  function tick(t: number) {
    if (t > next) {
      // mostly touches going to the Mac, now and then a reply coming back
      const dir: 1 | -1 = Math.random() < 0.8 ? 1 : -1;
      const el = document.createElementNS(NS, "circle") as SVGCircleElement;
      el.setAttribute("r", dir === 1 ? "4" : "3"); el.setAttribute("cy", String(y + (dir === 1 ? -7 : 7))); el.setAttribute("class", "packet");
      g!.appendChild(el); pks.push({ el, t0: t, dir, dur: 1300 + Math.random() * 200 });
      next = t + (dir === 1 ? 260 : 120) + Math.random() * 260;
    }
    for (let i = pks.length - 1; i >= 0; i--) {
      const p = pks[i]; const u = (t - p.t0) / p.dur;
      if (u >= 1) { p.el.remove(); pks.splice(i, 1); continue; }
      const e = u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2; // ease in and out, like something with mass
      const x = p.dir === 1 ? x0 + (x1 - x0) * e : x1 - (x1 - x0) * e;
      p.el.setAttribute("cx", x.toFixed(1));
      p.el.setAttribute("opacity", Math.min(1, Math.min(u, 1 - u) * 8).toFixed(2));
    }
    if (visible && !document.hidden) requestAnimationFrame(tick); else running = false;
  }
}

/* ---------- Copy commands ---------- */
export function initCopy() {
  const btn = document.getElementById("copy");
  const code = document.getElementById("cmds");
  if (!btn || !code) return;
  const label = btn.querySelector("span")!;
  btn.addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(code.textContent!.trim()); } catch { return; }
    btn.classList.add("done"); label.textContent = "Copied";
    setTimeout(() => { btn.classList.remove("done"); label.textContent = "Copy"; }, 1800);
  });
}

import { reducedMotion } from "./spring";
import { appIcon } from "./apps";
import { glyph, PINNED } from "./glyphs";

/* Actions, as the iPhone app draws it: the app in front with its best buttons (the starter sets
   in GlasspadMacros), and Pinned. Sideways the two sit side by side; upright, Pinned is below. */
type Set = { key: string; name: string; color: string; win: string; buttons: [string, string][] };
const SETS: Set[] = [
  { key: "web", name: "Safari", color: "#0A84FF", win: "safari", buttons: [["New Tab", "plus.square.on.square"], ["Reopen Closed Tab", "arrow.uturn.backward"], ["Show All Tabs", "square.grid.2x2"], ["Reload", "arrow.clockwise"], ["Reader", "doc.plaintext"], ["Address Bar", "link"], ["Previous Tab", "chevron.left"], ["Next Tab", "chevron.right"]] },
  { key: "finder", name: "Finder", color: "#1E90E8", win: "finder", buttons: [["New Window", "macwindow.badge.plus"], ["New Folder", "folder.badge.plus"], ["Go to Folder", "arrow.right.circle"], ["Get Info", "info.circle"], ["Quick Look", "eye"], ["Hidden Files", "eye.slash"], ["Downloads", "arrow.down.circle"], ["Move to Trash", "trash"]] },
  { key: "xcode", name: "Xcode", color: "#147EFB", win: "xcode", buttons: [["Build", "hammer"], ["Run", "play.fill"], ["Stop", "stop.fill"], ["Test", "checkmark.diamond"], ["Clean Build Folder", "trash"], ["Open Quickly", "magnifyingglass"], ["Navigator", "sidebar.left"], ["Debug Area", "rectangle.bottomthird.inset.filled"]] },
  { key: "figma", name: "Figma", color: "#A259FF", win: "figma", buttons: [["Move", "cursorarrow"], ["Frame", "number"], ["Rectangle", "rectangle"], ["Text", "textformat"], ["Pen", "pencil.tip"], ["Comment", "bubble.left"], ["Zoom to Fit", "arrow.up.left.and.arrow.down.right"], ["Group", "square.on.square"]] },
  { key: "music", name: "Music", color: "#FF375F", win: "music", buttons: [["Play / Pause", "playpause.fill"], ["Previous", "backward.fill"], ["Next", "forward.fill"], ["Volume Down", "speaker.minus"], ["Volume Up", "speaker.plus"], ["Current Song", "music.note.list"]] },
  { key: "keynote", name: "Keynote", color: "#0A84FF", win: "keynote", buttons: [["Play Slideshow", "play.fill"], ["New Slide", "plus.rectangle"], ["Duplicate", "plus.square.on.square"], ["Group", "square.on.square"], ["Ungroup", "square.split.2x1"], ["Inspector", "sidebar.right"]] },
];

const tile = (name: string, g: string, color: string, i = 0) =>
  `<div class="ax-t" style="--c:${color};--i:${i}">${glyph(g)}<span>${name}</span></div>`;

/* What each app's window looks like on the little Mac */
const lines = (n: number) => Array.from({ length: n }, (_, i) => `<i style="width:${[92, 78, 86, 64, 90, 72][i % 6]}%"></i>`).join("");
const WIN: Record<string, string> = {
  safari: `<div class="axw-tabs"><span class="on"></span><span></span><span></span></div><div class="axw-doc">${lines(6)}</div>`,
  finder: `<div class="axw-split"><div class="axw-side">${"<i></i>".repeat(5)}</div><div class="axw-folders">${'<span class="fold"></span>'.repeat(6)}</div></div>`,
  xcode: `<div class="axw-split"><div class="axw-side">${"<i></i>".repeat(6)}</div><div class="axw-code">${["#C2185B 30%", "#1A1A1A 62%", "#2F6FE4 48%", "#1A1A1A 70%", "#8E8E93 40%", "#C2185B 22%", "#1A1A1A 56%"].map(v => { const [c, w] = v.split(" "); return `<i style="background:${c};width:${w}"></i>`; }).join("")}</div></div>`,
  figma: `<div class="axw-canvas"><span class="sq"></span><span class="ci"></span><span class="tx"></span></div>`,
  music: `<div class="axw-music"><span class="cv"></span><div class="axw-doc">${lines(5)}</div></div>`,
  keynote: `<div class="axw-split"><div class="axw-thumbs">${"<i></i>".repeat(4)}</div><div class="axw-slide"><b></b><i></i></div></div>`,
};

export function initActions() {
  const root = document.getElementById("axStage");
  if (!root) return;
  const reduce = reducedMotion();
  const phone = document.getElementById("axPhone")!, pt = document.getElementById("axPt")!;
  const screen = phone.querySelector<HTMLElement>(".ip-screen")!;
  const head = document.getElementById("axHead")!, grid = document.getElementById("axFront")!;
  const macApp = document.getElementById("axMacApp")!, win = document.getElementById("axWin")!, dock = document.getElementById("axDock")!;
  const sw = document.getElementById("axSwitch")!, ind = document.getElementById("axInd")!, live = document.getElementById("axLive")!;

  document.getElementById("axPinned")!.innerHTML =
    PINNED.map(([n, g, c], i) => tile(n, g, c, i)).join("") + `<div class="ax-t add"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 6v12M6 12h12"/></svg><span>Add</span></div>`;
  dock.innerHTML = SETS.map(s => `<span class="axd" data-k="${s.key}">${appIcon(s.key)}<i></i></span>`).join("");

  // upright on narrow screens, sideways otherwise
  const narrow = matchMedia("(max-width: 760px)");
  const fit = () => {
    const land = !narrow.matches;
    phone.dataset.orient = land ? "landscape" : "portrait";
    pt.classList.toggle("land", land);
    const w = screen.clientWidth; if (!w) return;
    pt.style.transform = `scale(${w / (land ? 874 : 402)})`;
  };
  narrow.addEventListener("change", fit);
  new ResizeObserver(fit).observe(screen);
  fit();

  const tabs: HTMLButtonElement[] = [];
  let cur = -1;
  const place = () => { const b = tabs[cur]; if (!b) return; ind.style.width = b.offsetWidth + "px"; ind.style.transform = `translateX(${b.offsetLeft}px)`; };
  const select = (i: number, focus = false, announce = false) => {
    if (i === cur) return;
    const first = cur < 0; cur = i;
    const s = SETS[i];
    tabs.forEach((t, k) => { t.setAttribute("aria-selected", String(k === i)); t.tabIndex = k === i ? 0 : -1; });
    if (focus) tabs[i].focus();
    place();
    head.innerHTML = `<span class="ax-fi">${appIcon(s.key)}</span><b>${s.name}</b><span class="ax-edit">Edit</span>`;
    grid.innerHTML = s.buttons.map(([n, g], j) => tile(n, g, s.color, j)).join("");
    macApp.textContent = s.name;
    win.innerHTML = `<div class="wb"><i></i><i></i><i></i></div><div class="axw-body">${WIN[s.win]}</div>`;
    dock.querySelectorAll<HTMLElement>(".axd").forEach(d => d.classList.toggle("on", d.dataset.k === s.key));
    if (announce) live.textContent = `${s.name} in front. Buttons: ${s.buttons.map(b => b[0]).join(", ")}.`;
    if (reduce || first) return;
    const ease = "cubic-bezier(.2,.8,.2,1)";
    head.animate([{ opacity: 0.3, transform: "translateY(8px)" }, { opacity: 1, transform: "none" }], { duration: 460, easing: ease });
    Array.from(grid.children).forEach((el, j) => el.animate([{ opacity: 0, transform: "scale(0.9)" }, { opacity: 1, transform: "none" }], { duration: 520, delay: 40 + j * 28, easing: "cubic-bezier(.3,1.3,.5,1)", fill: "backwards" }));
    win.animate([{ opacity: 0.4, transform: "scale(0.94)" }, { opacity: 1, transform: "none" }], { duration: 520, easing: "cubic-bezier(.3,1.25,.5,1)" });
    const icon = dock.querySelector<HTMLElement>(`.axd[data-k="${s.key}"] .app`);
    icon?.animate([{ transform: "none" }, { transform: "translateY(-40%)", offset: 0.3 }, { transform: "none", offset: 0.55 }, { transform: "translateY(-14%)", offset: 0.72 }, { transform: "none" }], { duration: 900, easing: "cubic-bezier(.3,0,.4,1)" });
  };

  let auto = 0, visible = false;
  const stop = () => { if (auto) { clearInterval(auto); auto = 0; } };
  SETS.forEach((s, i) => {
    const b = document.createElement("button");
    b.type = "button"; b.setAttribute("role", "tab"); b.setAttribute("aria-controls", "axLive");
    b.innerHTML = `${appIcon(s.key)}<span>${s.name}</span>`;
    b.addEventListener("click", () => { stop(); select(i, false, true); });
    b.addEventListener("keydown", e => {
      const d = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
      if (d) { e.preventDefault(); stop(); select((cur + d + SETS.length) % SETS.length, true, true); }
    });
    sw.appendChild(b); tabs.push(b);
  });
  select(0);
  addEventListener("resize", place);
  document.fonts?.ready.then(place);

  // While nobody touches it, the front app changes on its own, like switching apps on a Mac.
  if (!reduce) {
    new IntersectionObserver(([e]) => { visible = e.isIntersecting; }, { threshold: 0.35 }).observe(root);
    auto = window.setInterval(() => { if (visible && !document.hidden) select((cur + 1) % SETS.length); }, 3000);
    sw.addEventListener("pointerdown", stop, { once: true });
    sw.addEventListener("focusin", stop, { once: true });
  }
}

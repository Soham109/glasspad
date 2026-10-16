import { glyph } from "./glyphs";
import { appIcon } from "./apps";
import { tl, tlIcon, loopInView, settle, Scene } from "./kit";
import { THEMES, themeVars, themesLine, type Theme } from "./themes";

/* "Make it yours": small cuts of the Actions screen, each showing one thing you can set up. */

const W = 360, H = 230;
const logo = (g: string) => `<svg viewBox="0 0 24 24" class="logo" aria-hidden="true">${glyph(g).replace(/^<svg[^>]*>|<\/svg>$/g, "")}</svg>`;

interface Card { key: string; title: string; text: string; art: () => string; run: (s: Scene) => Promise<void>; reset: (el: HTMLElement) => void }

const CARDS: Card[] = [
  {
    key: "controls", title: "Mac controls", text: "Do Not Disturb, Night Shift, Keep Awake and screenshots, one tap each.",
    art: () => `<div class="mk-mb"><span class="mst dnd">${glyph("moon.fill")}</span><span class="mst ns">${glyph("sun.horizon.fill")}</span><span class="mst ka">${glyph("cup.and.saucer.fill")}</span><b>Fri 9:41</b></div>
      <div class="mk-row">${tl("Do Not Disturb", "moon.fill", "#5E5CE6")}${tl("Night Shift", "sun.horizon.fill", "#FFD60A")}${tl("Keep Awake", "cup.and.saucer.fill", "#30B0C7")}</div>`,
    async run(s) {
      for (const [b, st] of [["Do Not Disturb", "dnd"], ["Night Shift", "ns"], ["Keep Awake", "ka"]]) {
        await s.wait(500);
        await s.tap(s.q(`[data-b="${b}"]`), () => { s.q(`[data-b="${b}"]`).classList.add("on"); s.q(`.mst.${st}`).classList.add("on"); });
      }
      await s.wait(2200);
    },
    reset: el => el.querySelectorAll(".on").forEach(e => e.classList.remove("on")),
  },
  {
    key: "sites", title: "Websites", text: "Add any site. Its real logo appears by itself.",
    art: () => `<div class="mk-one">${tlIcon("github.com", `<span class="site">${glyph("globe")}${logo("logo.github")}</span>`)}</div><div class="mk-url">https://github.com</div>`,
    async run(s) {
      await s.wait(1100);
      const t = s.q(".bt");
      t.classList.add("got"); t.querySelector(".bt-n")!.textContent = "GitHub";
      await s.wait(2600);
    },
    reset: el => { const t = el.querySelector(".bt"); if (t) { t.classList.remove("got"); t.querySelector(".bt-n")!.textContent = "github.com"; } },
  },
  {
    key: "folders", title: "Folders", text: "Group buttons in a folder, like these for tiling windows.",
    art: () => `<div class="mk-fold"><div class="fv closed">${tlIcon("Windows", `<span class="ficon">${["rectangle.lefthalf.filled", "rectangle.righthalf.filled", "macwindow", "square.split.2x1"].map(g => `<i>${glyph(g)}</i>`).join("")}</span>`)}${tl("Screenshot", "camera.viewfinder", "#0A84FF")}${tl("Lock Screen", "lock.fill", "#8E8E93")}</div>
      <div class="fv open"><div class="fh">${glyph("chevron.left")}<b>Windows</b></div><div class="mk-row f4">${tl("Left Half", "rectangle.lefthalf.filled", "#0A84FF")}${tl("Right Half", "rectangle.righthalf.filled", "#0A84FF")}${tl("Fill", "macwindow", "#0A84FF")}${tl("Split Screen", "rectangle.split.2x1.fill", "#0A84FF")}</div></div></div>`,
    async run(s) {
      await s.wait(700);
      await s.tap(s.q('.closed [data-b="Windows"]'), () => { s.q(".mk-fold").classList.add("in"); settle(Array.from(s.q(".open .mk-row").children), 40); });
      await s.wait(2200);
      await s.tap(s.q(".fh"), () => s.q(".mk-fold").classList.remove("in"));
      await s.wait(1200);
    },
    reset: el => el.querySelector(".mk-fold")?.classList.remove("in"),
  },
  {
    key: "macros", title: "Macros", text: "Record what you do on your Mac once. It becomes a button.",
    art: () => `<div class="mk-mac"><div class="hud"><i></i><b>Recording Macro</b><span>Stop</span></div><svg class="mk-cur" viewBox="0 0 16 22"><path d="M1 1v17l4.6-4.4 3 6.9 3-1.3-3-6.8H15Z" fill="#1A1A1A" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/></svg></div>
      <div class="mk-row">${tl("Record New Macro", "record.circle", "#FF3B30")}${tl("Clean Desktop", "wand.and.stars", "#30B0C7")}${tl("Invoices Folder", "wand.and.stars", "#30B0C7")}</div>`,
    async run(s) {
      const mac = s.q(".mk-mac"), nt = s.q('[data-b="Invoices Folder"]');
      await s.wait(700);
      await s.tap(s.q('[data-b="Record New Macro"]'), () => mac.classList.add("rec"));
      await s.wait(1300); mac.classList.add("stop"); await s.wait(500);
      mac.classList.remove("rec", "stop"); nt.classList.add("in");
      await s.wait(2200);
    },
    reset: el => { el.querySelector(".mk-mac")?.classList.remove("rec", "stop"); el.querySelector('[data-b="Invoices Folder"]')?.classList.remove("in"); },
  },
  {
    key: "perapp", title: "Each app's buttons", text: "Edit, next to the app's name, changes the buttons for that app.",
    art: () => `<div class="mk-ed"><div class="af"><span class="af-i">${appIcon("web")}</span><div><b>Safari</b><span>In front on your Mac</span></div><span class="ed">Edit</span></div>
      <div class="mk-row">${tl("New Tab", "plus.square.on.square", "#0A84FF")}${tl("Reopen Tab", "arrow.uturn.backward", "#0A84FF")}${tl("Private", "hand.raised.fill", "#8E8E93")}</div></div>`,
    async run(s) {
      const box = s.q(".mk-ed"), ed = s.q(".ed"), pv = s.q('[data-b="Private"]');
      await s.wait(800);
      await s.tap(ed, () => { box.classList.add("editing"); ed.textContent = "Done"; });
      await s.wait(900);
      await s.tap(pv, () => pv.classList.add("gone"));
      await s.wait(900);
      await s.tap(ed, () => { box.classList.remove("editing"); ed.textContent = "Edit"; });
      await s.wait(1600);
    },
    reset: el => { const b = el.querySelector(".mk-ed"); if (!b) return; b.classList.remove("editing"); b.querySelector(".ed")!.textContent = "Edit"; b.querySelector(".gone")?.classList.remove("gone"); },
  },
  {
    key: "shortcuts", title: "Shortcuts", text: "Run any shortcut from the Shortcuts app on your Mac.",
    art: () => `<div class="mk-one">${tl("Start Focus Session", "square.stack.3d.up.fill", "#FF2D55")}</div><div class="mk-done">${glyph("checkmark")}Done</div>`,
    async run(s) {
      await s.wait(800);
      const t = s.q(".bt");
      await s.tap(t, () => t.classList.add("busy"));
      await s.wait(900); t.classList.remove("busy"); s.q(".mk-done").classList.add("on");
      await s.wait(1800);
    },
    reset: el => { el.querySelector(".mk-done")?.classList.remove("on"); el.querySelector(".bt")?.classList.remove("busy"); },
  },
  {
    key: "library", title: "Library", text: "Every app, Mac control, macro, shortcut and website, in one list you can search.",
    art: () => `<div class="mk-lib"><div class="sf">${glyph("magnifyingglass")}<span class="q"></span><i class="caret"></i></div>
      <div class="rows"><div class="r" data-r="Night Shift"><span class="ic" style="--c:#FFD60A">${glyph("sun.horizon.fill")}</span>Night Shift<span class="add">${glyph("plus")}</span></div>
      <div class="r" data-r="Notes"><span class="ic" style="--c:#F2C94C">${glyph("doc.plaintext")}</span>Notes<span class="add">${glyph("plus")}</span></div>
      <div class="r" data-r="Notification Center"><span class="ic" style="--c:#30B0C7">${glyph("bell.badge.fill")}</span>Notification Center<span class="add">${glyph("plus")}</span></div></div></div>`,
    async run(s) {
      await s.wait(600);
      const q = s.q(".q"), word = "Night";
      for (let i = 1; i <= word.length; i++) { q.textContent = word.slice(0, i); if (i === 2) s.q(".mk-lib").classList.add("filtered"); await s.wait(140); }
      await s.wait(500);
      const r = s.q('[data-r="Night Shift"] .add');
      await s.tap(r, () => { r.classList.add("on"); r.innerHTML = glyph("checkmark"); });
      await s.wait(2000);
    },
    reset: el => {
      const q = el.querySelector(".q"); if (q) q.textContent = "";
      el.querySelector(".mk-lib")?.classList.remove("filtered");
      const r = el.querySelector('[data-r="Night Shift"] .add'); if (r) { r.classList.remove("on"); r.innerHTML = glyph("plus"); }
    },
  },
  {
    key: "themes", title: "Themes", text: themesLine(),
    art: () => `<div class="mk-th" style="${themeVars(THEMES[1])}"><div class="mk-row">${tl("New Tab", "plus.square.on.square", "#0A84FF")}${tl("Reader", "doc.plaintext", "#30B0C7")}${tl("Do Not Disturb", "moon.fill", "#5E5CE6")}</div>
      <div class="sw"></div><b class="nm"></b></div>`,
    async run(s) {
      // one theme from each group, a different one each pass, then back to Paper
      const box = s.q(".mk-th"), sw = s.q(".sw"), nm = s.q(".nm");
      const show = (t: Theme) => {
        box.setAttribute("style", themeVars(t)); box.classList.toggle("mono", !!t.mono);
        const group = THEMES.filter(x => x.group === t.group);
        sw.innerHTML = group.map(x => `<span class="${x === t ? "on" : ""}" style="background:${x.swatch}"></span>`).join("");
        nm.textContent = t.group === t.name ? t.name : `${t.name} · ${t.group}`;
      };
      show(THEMES[1]);
      const pick = (g: Theme["group"]) => { const l = THEMES.filter(t => t.group === g); return l[Math.floor(Math.random() * l.length)]; };
      for (const t of [pick("Glass"), pick("Color"), pick("Classic"), pick("Glass"), pick("Photo"), THEMES[1]]) { await s.wait(1500); show(t); }
      await s.wait(600);
    },
    reset: el => { const b = el.querySelector(".mk-th"); if (b) { b.setAttribute("style", themeVars(THEMES[1])); b.classList.remove("mono"); } },
  },
];

export function initDetails() {
  const grid = document.getElementById("mkGrid"); if (!grid) return;
  grid.innerHTML = CARDS.map(c => `<article class="mk reveal" data-k="${c.key}"><div class="mk-art" aria-hidden="true"><div class="pt mk-pt">${c.art()}</div></div><h3>${c.title}</h3><p>${c.text}</p></article>`).join("");
  grid.querySelectorAll<HTMLElement>(".mk").forEach((el, i) => {
    const art = el.querySelector<HTMLElement>(".mk-art")!, pt = art.querySelector<HTMLElement>(".pt")!;
    const fit = () => { const k = art.clientWidth / W; pt.style.transform = `scale(${k})`; art.style.height = H * k + "px"; };
    new ResizeObserver(fit).observe(art); fit();
    loopInView(el, art, el, s => CARDS[i].run(s), () => CARDS[i].reset(el));
  });
}

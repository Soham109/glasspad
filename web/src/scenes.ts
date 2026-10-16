import { lerp } from "./spring";
import { appIcon } from "./apps";
import { glyph } from "./glyphs";
import { phone, fitAll, tl, tlApp, settle, reduce, Scene } from "./kit";

/* Five setups drawn as rooms, each named after the layout (LayoutTemplates.swift) its phone
   shows: Desk, Studio, Couch, Presenter and StandBy. */

/* Portrait layouts: two panes stacked edge to edge, a divider between them. */
const PT_H = 874, PT_GAP = 12;
const PT_SPLIT = (share: number) => Math.round((PT_H - PT_GAP) * share);

const cursor = '<svg class="md-cursor" viewBox="0 0 16 22"><path d="M1 1v17l4.6-4.4 3 6.9 3-1.3-3-6.8H15Z" fill="#1A1A1A" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/></svg>';
const apple = '<svg class="mb-apple" viewBox="0 0 14 17"><path d="M11.6 9c0-2 1.6-2.9 1.7-3-1-1.4-2.4-1.6-2.9-1.6-1.2-.1-2.4.7-3 .7-.6 0-1.6-.7-2.6-.7C3.4 4.4 2.1 5.2 1.4 6.5 0 9 1 12.7 2.4 14.7c.7 1 1.5 2 2.5 2 1 0 1.4-.6 2.6-.6s1.5.6 2.6.6c1.1 0 1.8-1 2.4-2 .8-1.1 1.1-2.2 1.1-2.3 0 0-2-.8-2-3.4ZM9.7 3c.5-.7.9-1.6.8-2.5-.8 0-1.8.5-2.3 1.2-.5.6-1 1.5-.8 2.4.9.1 1.8-.5 2.3-1.1Z"/></svg>';
/** The macOS menu bar: Apple menu, the app's menus, status items and the clock. */
export const menuBar = (app: string, menus: string[], clock = "Fri 9:41", extra = "") =>
  `<div class="mb">${apple}<b class="mb-app">${app}</b>${menus.map(m => `<span>${m}</span>`).join("")}<span class="mb-r">${extra}${WIFI}${CC}${clock ? `<span>${clock}</span>` : ""}</span></div>`;
const WIFI = '<svg class="mb-i" viewBox="0 0 24 24"><path d="M2.5 9.5a14 14 0 0 1 19 0M5.5 12.8a9.5 9.5 0 0 1 13 0M8.6 16a5 5 0 0 1 6.8 0"/><circle cx="12" cy="19" r="1.4" fill="currentColor" stroke="none"/></svg>';
const CC = '<svg class="mb-i" viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="6" rx="3"/><circle cx="17.5" cy="8" r="1.6" fill="currentColor"/><rect x="3" y="13" width="18" height="6" rx="3"/><circle cx="6.5" cy="16" r="1.6" fill="currentColor"/></svg>';
const dock = (keys: string[], running: string[] = []) =>
  `<div class="md-dock">${keys.map(k => `<div class="app-slot" data-app="${k}">${appIcon(k)}<i class="md-run ${running.includes(k) ? "on" : ""}"></i></div>`).join("")}</div>`;
const lines = (n: number) => Array.from({ length: n }, (_, i) => `<i style="width:${[92, 78, 86, 64, 90, 72][i % 6]}%"></i>`).join("");
const win = (cls: string, body: string, bar = "") => `<div class="md-win ${cls}"><div class="wb"><i></i><i></i><i></i>${bar}</div><div class="wbody">${body}</div></div>`;

/* A display on a stand, a MacBook (drawn at scene scale inside its own box), a phone on a stand. */
const monitor = (cls: string, screen: string) =>
  `<div class="mon ${cls}"><div class="mon-frame"><div class="mon-screen">${screen}</div></div><div class="mon-neck"></div><div class="mon-foot"></div></div>`;
const macbook = (cls: string, screen: string) =>
  `<div class="mbw ${cls}"><div class="mbp"><div class="mbp-lid"><div class="mbp-glass"></div><div class="mbp-display">${screen}</div><div class="mbp-notch"></div></div><div class="mbp-hinge"></div><div class="mbp-base"><div class="mbp-keys"></div><div class="mbp-pad"></div></div><div class="mbp-lip"></div><div class="mbp-shadow"></div></div></div>`;
const standPhone = (cls: string, inner: string, finish: "light" | "dark" = "light") =>
  `<div class="sp ${cls}">${phone("landscape", finish, inner)}<div class="sp-stand"><i></i></div></div>`;
const handPhone = (cls: string, inner: string, finish: "light" | "dark") => `<div class="hp ${cls}">${phone("portrait", finish, inner)}</div>`;

/* ---------- Buttons for the app in front (the starter sets in GlasspadMacros) ---------- */
type B = [string, string, string];
const SAFARI: B[] = [["New Tab", "plus.square.on.square", "#0A84FF"], ["Reopen Tab", "arrow.uturn.backward", "#0A84FF"], ["Reader", "doc.plaintext", "#30B0C7"]];
const XCODE: B[] = [["Build", "hammer", "#147EFB"], ["Run", "play.fill", "#34C759"], ["Stop", "stop.fill", "#FF3B30"]];
const FCP: B[] = [["Play / Pause", "playpause.fill", "#BF5AF2"], ["Blade at Playhead", "scissors", "#BF5AF2"], ["Mark In", "arrow.right.to.line", "#BF5AF2"], ["Snapping", "magnet", "#BF5AF2"], ["Mark Out", "arrow.left.to.line", "#BF5AF2"], ["Zoom to Fit", "arrow.up.left.and.arrow.down.right", "#BF5AF2"]];
const tiles = (bs: B[]) => bs.map(([n, g, c]) => tl(n, g, c)).join("");
/** Media as a pane: the player, the song and the three controls (MediaMode.swift). */
const mediaPane = `<div class="pz-md"><div class="src"><i></i>SPOTIFY</div><b>Slow Light</b><span>Paper Rooms</span><div class="ctl">${glyph("backward.fill")}<span class="pp">${glyph("pause.fill")}</span>${glyph("forward.fill")}</div></div>`;
const front = (key: string, name: string) => `<div class="af"><span class="af-i">${appIcon(key)}</span><div><b>${name}</b><span>In front on your Mac</span></div></div>`;

/* ---------- Desk: an external display, the MacBook beside it, the phone on a stand ---------- */
const MENUS: Record<string, string[]> = {
  Safari: ["File", "Edit", "View", "History", "Bookmarks", "Window", "Help"],
  Xcode: ["File", "Edit", "View", "Find", "Navigate", "Editor", "Product", "Debug", "Window", "Help"],
};
const DESK = {
  key: "desk", title: "Desk", text: "Trackpad and Actions side by side on a stand. Tap Split Screen and two windows share the display.",
  html: () => `<div class="scene uc uc-desk"><div class="cam"><div class="uc-wall"></div><div class="sc-desk"></div>
    ${macbook("mb-left", `<div class="mbx">${menuBar("Mail", ["File", "Edit", "View", "Mailbox"], "")}${win("front ml", `<div class="mail"><div class="ml-l">${"<i></i>".repeat(6)}</div><div class="md-doc">${lines(6)}</div></div>`)}</div>`)}
    ${monitor("mon-c", `<div class="mbx">${menuBar("Safari", MENUS.Safari)}
      ${win("w-saf front", `<div class="md-doc">${lines(7)}</div>`, '<span class="url"></span>')}
      ${win("w-xc", `<div class="xcw"><div class="xc-side">${"<i></i>".repeat(7)}</div><div class="xc-code">${["#C2185B 30%", "#1A1A1A 62%", "#2F6FE4 48%", "#1A1A1A 70%", "#8E8E93 40%", "#C2185B 22%", "#1A1A1A 56%", "#2F6FE4 36%"].map(v => { const [c, w] = v.split(" "); return `<i style="background:${c};width:${w}"></i>`; }).join("")}</div></div>`)}
      ${dock(["finder", "web", "mail", "notes", "music", "xcode", "term", "set"], ["finder", "web", "mail", "xcode"])}${cursor}</div>`)}
    ${standPhone("sp-desk", `<div class="pt land lyt">
      <div class="lp-pane tpad"><i class="tp-hint"></i></div><div class="lyt-div"><i></i></div>
      <div class="lp-pane ac">${front("web", "Safari")}<div class="ag f3">${tiles(SAFARI)}</div><h5>Pinned</h5>
        <div class="ag f3">${tl("Split Screen", "rectangle.split.2x1.fill", "#0A84FF")}${tl("Do Not Disturb", "moon.fill", "#5E5CE6")}${tl("Screenshot", "camera.viewfinder", "#0A84FF")}</div></div></div>`)}
  </div></div>`,
  async run(s: Scene) {
    const grid = s.q(".ag.f3"), saf = s.m(".w-saf"), xc = s.m(".w-xc"), cur = s.m<SVGElement>(".mon-c .md-cursor");
    const scr = s.m(".mon-c .mon-screen"), W = () => scr.clientWidth, H = () => scr.clientHeight;
    const curAt = (x: number, y: number) => { cur.style.transform = `translate(${x * W()}px, ${y * H()}px)`; };
    const setFront = (k: "web" | "xcode") => {
      s.q(".af").outerHTML = front(k, k === "web" ? "Safari" : "Xcode");
      grid.innerHTML = tiles(k === "web" ? SAFARI : XCODE); settle([s.q(".af"), ...Array.from(grid.children)]);
      const app = k === "web" ? "Safari" : "Xcode"; s.m(".mon-c .mb").outerHTML = menuBar(app, MENUS[app]);
      saf.classList.toggle("front", k === "web"); xc.classList.toggle("front", k === "xcode");
    };
    const at = [0.55, 0.5];
    const glide = async (x: number, y: number, ms = 800) => { const [x0, y0] = at; await s.tween(ms, e => curAt(lerp(x0, x, e), lerp(y0, y, e))); at[0] = x; at[1] = y; };
    curAt(at[0], at[1]);
    await s.wait(900);
    // click the Xcode window on the display: Actions follows
    await glide(0.8, 0.62); cur.classList.add("press"); await s.wait(110); cur.classList.remove("press");
    setFront("xcode");
    await s.wait(900);
    // move in on the phone so its buttons can be read
    const cam = s.m(".cam");
    cam.classList.add("close");
    await s.wait(1300); settle(Array.from(grid.children));
    await s.wait(1500);
    // Split Screen: the two front windows share the display
    await s.tap(s.q('[data-b="Split Screen"]'));
    cam.classList.remove("close");
    await s.wait(500); s.m(".mon-c .mbx").classList.add("split");
    await s.wait(2600);
    s.m(".mon-c .mbx").classList.remove("split");
    await glide(0.3, 0.42); cur.classList.add("press"); await s.wait(110); cur.classList.remove("press");
    setFront("web");
    await s.wait(1600);
  },
};

/* ---------- Studio: Final Cut Pro on a MacBook; the Studio layout on the phone ---------- */
const DUR = 0.82; // where the timeline ends, as a share of its width
const STUDIO = {
  key: "studio", title: "Studio", text: "Trackpad, Media and Actions on one screen. Final Cut Pro is in front, so Actions shows its buttons: Play, Blade, Mark In. More than 70 apps get their own.",
  html: () => `<div class="scene uc uc-studio"><div class="uc-wall"></div><div class="sc-desk"></div>
    ${macbook("mb-studio", `<div class="mbx fcp">${menuBar("Final Cut Pro", ["File", "Edit", "Trim", "Mark", "Clip", "Modify", "View"])}
      <div class="fc-top"><div class="fc-lib">${"<i></i>".repeat(6)}</div><div class="fc-view"><div class="fc-frame"><i class="sun"></i><i class="sea"></i></div></div></div>
      <div class="fc-tl"><div class="fc-track v"><i style="left:2%;width:30%"></i><i class="b" style="left:32.4%;width:28%"></i><i style="left:60.8%;width:21%"></i></div>
        <div class="fc-track a"><i style="left:2%;width:80%"></i></div><span class="fc-cut"></span><span class="fc-in"></span><span class="fc-head"></span></div></div>`)}
    ${standPhone("sp-studio", `<div class="pt land lyt st3">
      <div class="lp-pane tpad"></div><div class="lyt-div"><i></i></div>
      <div class="lp-pane md">${mediaPane}</div><div class="lyt-div h"><i></i></div>
      <div class="lp-pane ac">${front("fcp", "Final Cut Pro")}<div class="ag f3">${tiles(FCP)}</div></div></div>`)}
  </div>`,
  async run(s: Scene) {
    const head = s.m(".fc-head"), cut = s.m(".fc-cut"), mark = s.m(".fc-in"), frame = s.m(".fc-frame");
    let x = 0.14;
    const place = () => { head.style.left = (x * 100).toFixed(2) + "%"; frame.style.setProperty("--p", x.toFixed(3)); };
    place();
    const play = async (to: number, ms: number) => { const x0 = x; await s.tween(ms, e => { x = lerp(x0, to, e); place(); }, u => u); };
    await s.tap(s.q('[data-b="Play / Pause"]'));
    await play(0.44, 2200);
    await s.tap(s.q('[data-b="Play / Pause"]'));
    await s.wait(400);
    await s.tap(s.q('[data-b="Blade at Playhead"]'), () => { cut.style.left = (x * 100).toFixed(2) + "%"; cut.classList.add("on"); });
    await s.wait(900);
    await s.tap(s.q('[data-b="Mark In"]'), () => { mark.style.left = (x * 100).toFixed(2) + "%"; mark.classList.add("on"); });
    await s.wait(900);
    await s.tap(s.q('[data-b="Play / Pause"]'));
    await play(0.7, 2000);
    await s.wait(700);
  },
};

/* ---------- Couch: the TV across the room, Remote in hand ---------- */
const RK = {
  netflix: { site: "Netflix in Safari", title: "The Quiet Coast", keys: [["Search", "magnifyingglass"], ["Skip Intro", "forward.end"], ["Full Screen", "arrow.up.left.and.arrow.down.right"], ["Mute", "speaker.slash"]] },
  youtube: { site: "YouTube in Safari", title: "Field Notes", keys: [["Search", "magnifyingglass"], ["Subtitles", "captions.bubble"], ["Full Screen", "arrow.up.left.and.arrow.down.right"], ["Next", "forward.end.alt"], ["Mute", "speaker.slash"]] },
};
const R = {
  back10: '<path d="M6 12a6.5 6.5 0 1 0 2-4.7"/><path d="M7.6 3.8 8 7.6l-3.8.4"/><text x="12" y="15" text-anchor="middle" font-size="6.2" font-weight="700" fill="currentColor" stroke="none">10</text>',
  fwd10: '<path d="M18 12a6.5 6.5 0 1 1-2-4.7"/><path d="m16.4 3.8-.4 3.8 3.8.4"/><text x="12" y="15" text-anchor="middle" font-size="6.2" font-weight="700" fill="currentColor" stroke="none">10</text>',
  pause: '<rect class="f" x="6.5" y="5" width="4" height="14" rx="1.2"/><rect class="f" x="13.5" y="5" width="4" height="14" rx="1.2"/>',
  play: '<path class="f" d="M7 4.8v14.4a1 1 0 0 0 1.5.9l11.2-7.2a1 1 0 0 0 0-1.7L8.5 3.9A1 1 0 0 0 7 4.8Z"/>',
  hand: '<path d="M10 13V5.8a1.6 1.6 0 0 1 3.2 0V11M13.2 10.5v-1a1.6 1.6 0 0 1 3.2 0v1.8M16.4 11.3a1.6 1.6 0 0 1 3.2 0v2.9a6.8 6.8 0 0 1-6.8 6.8h-.6a6 6 0 0 1-4.7-2.3L4.6 15.2a1.5 1.5 0 0 1 2.3-1.9L10 16"/><path d="M5.5 7.5a5 5 0 0 1 2.4-3.6"/>',
  x: '<path d="m7 7 10 10M17 7 7 17"/>', more: '<circle class="f" cx="6.5" cy="12" r="1.4"/><circle class="f" cx="12" cy="12" r="1.4"/><circle class="f" cx="17.5" cy="12" r="1.4"/>',
  "forward.end": '<path d="M6.5 6v12l9-6Z"/><path d="M17.5 6v12"/>', "forward.end.alt": '<path d="M4.5 6v12l7-6Z"/><path d="M12.5 6v12l7-6ZM20.5 6v12" />',
  "captions.bubble": '<path d="M5 5h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-6l-4 3v-3H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2Z"/><path d="M7.5 10h4M13.5 10h3M7.5 13h2.5M12 13h4.5"/>',
  "speaker.slash": '<path d="M4 9.5h3l4.5-4v13l-4.5-4H4Z"/><path d="M3.5 3.5 20.5 20.5"/>',
};
const rg = (g: string) => `<svg viewBox="0 0 24 24" aria-hidden="true">${(R as Record<string, string>)[g] ?? ""}</svg>`;
const rkeys = (k: string[][]) => k.map(([n, g]) => `<span class="ro" data-k="${n}">${g in R ? rg(g) : glyph(g)}<small>${n}</small></span>`).join("");
const poster = '<span class="pst"><i class="s1"></i><i class="s2"></i><i class="s3"></i></span>';
const COUCH = {
  key: "couch", title: "Couch", text: "Remote over the trackpad. Its pad works like the Siri Remote: tap to pause, swipe to skip 10 seconds, up or down for volume. The keys follow the player.",
  html: () => `<div class="scene uc uc-couch"><div class="uc-wall"></div><div class="uc-floor"></div>
    <div class="tv"><div class="tv-b"><div class="tv-s" data-p="netflix"><div class="tv-film">${poster}</div><div class="tv-dim"></div>
      <div class="tv-seek"><svg viewBox="0 0 24 24">${R.fwd10}</svg></div><div class="tv-vol"><i></i></div><div class="tv-bar"><i></i></div><div class="tv-pp"><svg viewBox="0 0 24 24">${R.pause}</svg></div></div></div></div>
    <div class="console"></div><div class="sofa"><i></i></div>
    ${handPhone("hp-couch", `<div class="pt lyp">
      <div class="lpt top rmt" style="height:${PT_SPLIT(0.6)}px">
      <div class="rh">${poster}<div class="rt"><b>The Quiet Coast</b><span>Netflix in Safari</span></div><span class="rc">${rg("more")}</span></div>
      <div class="rpad"><span class="rhand">${rg("hand")}</span><b>Tap to play or pause</b><span>Swipe sideways to skip,<br>up or down for volume</span></div>
      <div class="rbig"><span>${rg("back10")}</span><span class="pp">${rg("pause")}</span><span>${rg("fwd10")}</span></div>
      <div class="ropts">${rkeys(RK.netflix.keys)}</div></div>
      <div class="lpt-div" style="top:${PT_SPLIT(0.6)}px"><i></i></div><div class="lpt bot" style="top:${PT_SPLIT(0.6) + PT_GAP}px"></div></div>`, "dark")}
  </div>`,
  async run(s: Scene) {
    const tvs = s.m(".tv-s"), bar = s.m(".tv-bar"), barI = s.m(".tv-bar i"), seek = s.m(".tv-seek"), vol = s.m(".tv-vol"), volI = s.m(".tv-vol i"), pp = s.m(".tv-pp");
    const pad = s.q(".rpad"), [px, py] = s.at(pad);
    let pos = 0.31; barI.style.width = pos * 100 + "%";
    const flash = (el: HTMLElement, ms = 1100) => { el.classList.add("on"); setTimeout(() => el.classList.remove("on"), ms); };
    await s.wait(900);
    // swipe right: forward 10 seconds
    await s.swipe(px - 90, py, px + 90, py, 420);
    flash(seek); flash(bar, 1500); pos += 0.04; barI.style.width = pos * 100 + "%";
    await s.wait(1400);
    // slide up: louder
    vol.classList.add("on");
    await s.swipe(px + 40, py + 110, px + 40, py - 110, 700, e => { volI.style.height = lerp(40, 70, e) + "%"; });
    await s.wait(900); vol.classList.remove("on");
    await s.wait(500);
    // tap: pause, and the big button turns to Play
    await s.tap(pad, () => { tvs.classList.add("paused"); pp.classList.add("on"); s.q(".rbig .pp").innerHTML = rg("play"); });
    await s.wait(1500);
    await s.tap(pad, () => { tvs.classList.remove("paused"); pp.classList.remove("on"); s.q(".rbig .pp").innerHTML = rg("pause"); });
    await s.wait(900);
    // a YouTube video: the keys change with the player
    const swap = (k: "netflix" | "youtube") => {
      const r = RK[k]; tvs.dataset.p = k;
      s.q(".rt b").textContent = r.title; s.q(".rt span").textContent = r.site;
      const o = s.q(".ropts"); o.innerHTML = rkeys(r.keys); settle([s.q(".rt"), ...Array.from(o.children)], 40);
    };
    swap("youtube");
    await s.wait(2600);
    swap("netflix");
    await s.wait(600);
  },
};

/* ---------- Presenter: slides on the big screen, the Presenter layout in hand ---------- */
const SLIDES = [
  '<b class="sl-t" style="width:58%"></b><i style="width:44%"></i><i style="width:36%"></i><div class="sl-ch"><i style="height:38%"></i><i style="height:56%"></i><i style="height:48%"></i><i style="height:74%"></i><i style="height:90%"></i></div>',
  '<b class="sl-t" style="width:46%"></b><div class="sl-two"><span></span><span></span></div>',
  '<b class="sl-t big" style="width:64%"></b><i style="width:30%;margin:2cqh auto 0"></i>',
];
const STAGE = {
  key: "presenter", title: "Presenter", text: "Present over the trackpad: Next and Back as big as your thumb, a timer, and a laser you steer with one finger.",
  html: () => `<div class="scene uc uc-show"><div class="uc-wall"></div><div class="uc-floor"></div>
    <div class="screen"><div class="scr-roll"></div><div class="scr-s"><div class="slide">${SLIDES[0]}</div><span class="slaser"></span><span class="sl-n">1</span></div></div>
    ${handPhone("hp-stage", `<div class="pt lyp">
      <div class="lpt top prs" style="height:${PT_SPLIT(0.5)}px">
      <div class="ptime">0:00</div><span class="pr">${glyph("arrow.counterclockwise")}</span><span class="pgo">${rg("play")}</span>
      <div class="plaser">${glyph("dot.radiowaves")}<span>Touch and hold to point</span></div>
      <div class="pback">${glyph("chevron.left")}<b>Back</b></div><div class="pnext">${glyph("chevron.right")}<b>Next</b></div></div>
      <div class="lpt-div" style="top:${PT_SPLIT(0.5)}px"><i></i></div><div class="lpt bot" style="top:${PT_SPLIT(0.5) + PT_GAP}px"></div></div>`, "light")}
  </div>`,
  async run(s: Scene) {
    const slide = s.m(".slide"), n = s.m(".sl-n"), laser = s.m(".slaser"), time = s.q(".ptime"), go = s.q(".pgo");
    let secs = 0;
    const show = (k: number) => { slide.innerHTML = SLIDES[k]; n.textContent = String(k + 1); if (!reduce) slide.animate([{ opacity: 0, transform: "translateX(4%)" }, { opacity: 1, transform: "none" }], { duration: 480, easing: "cubic-bezier(.2,.8,.2,1)" }); };
    let tick = 0;
    try {
      await s.wait(700);
      await s.tap(go, () => { go.classList.add("on"); go.innerHTML = rg("pause"); time.classList.add("on"); tick = window.setInterval(() => { secs++; time.textContent = `0:${String(secs).padStart(2, "0")}`; }, 1000); });
      await s.wait(900);
      await s.tap(s.q(".pnext"), () => show(1));
      await s.wait(1500);
      // touch and hold the pad: the laser follows the finger on the big screen
      const pad = s.q(".plaser"), [cx, cy] = s.at(pad);
      await s.touch(0, cx - 80, cy - 30); await s.wait(350); laser.classList.add("on");
      await s.tween(1600, e => {
        s.put(0, cx - 80 + 160 * e, cy - 30 + Math.sin(e * Math.PI) * 50);
        laser.style.left = (30 + 40 * e) + "%"; laser.style.top = (40 + Math.sin(e * Math.PI) * 20) + "%";
      });
      laser.classList.remove("on"); await s.lift(0, cx + 80, cy - 30);
      await s.wait(700);
      await s.tap(s.q(".pnext"), () => show(2));
      await s.wait(1500);
      await s.tap(s.q(".pback"), () => show(1));
      await s.wait(1400);
    } finally { clearInterval(tick); }
  },
};


/* ---------- StandBy: the StandBy layout on the nightstand, Clock beside Now Playing ---------- */
const NIGHT = {
  key: "standby", title: "StandBy", text: "On the nightstand: Clock beside Now Playing, in dim red when the room goes dark.",
  html: () => `<div class="scene uc uc-night"><div class="uc-wall"></div><div class="nstand"></div><div class="lamp"><i class="shade"></i><i class="glow"></i><i class="stem"></i><i class="base"></i></div>
    ${standPhone("sp-night", `<div class="pt land sby">
      <div class="sb-pane clk"><div class="cd">Fri, 16 Oct <span class="chg">${glyph("bolt.fill")}82%</span></div><div class="dg"><b class="hh">10</b><b class="mm">09</b></div></div>
      <div class="lyt-div"><i></i></div>
      <div class="sb-pane np">${poster}<div class="npt"><b>Slow Light</b><span>Paper Rooms</span></div><div class="npc">${glyph("backward.fill")}${glyph("pause.fill")}${glyph("forward.fill")}</div></div>
    </div>`, "dark")}
  </div>`,
  async run(s: Scene) {
    const mm = s.q(".mm");
    await s.wait(1600);
    // a minute passes
    mm.animate([{ opacity: 1 }, { opacity: 0 }, { opacity: 1 }], { duration: 600 }); setTimeout(() => { mm.textContent = "10"; }, 300);
    await s.wait(2200);
    // lights out: the clock and Now Playing turn dim red
    s.mac.classList.add("dark");
    await s.wait(900);
    s.q(".sby").classList.add("red");
    await s.wait(3600);
  },
};

const SCENES = [DESK, STUDIO, COUCH, STAGE, NIGHT];

export function initScenes() {
  const stage = document.getElementById("ucStage"), tabs = document.getElementById("ucTabs"), cap = document.getElementById("ucCap");
  if (!stage || !tabs || !cap) return;
  stage.innerHTML = SCENES.map(c => c.html()).join("");
  fitAll(stage);
  const panes = Array.from(stage.children) as HTMLElement[];
  const btns: HTMLButtonElement[] = [];
  let cur = -1;
  // each pass starts from a freshly drawn room, so an interrupted pass leaves nothing behind
  const fresh = (i: number) => {
    const box = document.createElement("div"); box.innerHTML = SCENES[i].html();
    const el = box.firstElementChild as HTMLElement;
    el.classList.toggle("on", i === cur); el.setAttribute("aria-hidden", String(i !== cur));
    panes[i].replaceWith(el); panes[i] = el; fitAll(el);
    return el;
  };
  let token = 0;
  const show = (i: number, user = false) => {
    if (i === cur) return;
    cur = i; token++;
    panes.forEach((p, k) => { p.classList.toggle("on", k === i); p.setAttribute("aria-hidden", String(k !== i)); });
    btns.forEach((b, k) => { b.setAttribute("aria-selected", String(k === i)); b.tabIndex = k === i ? 0 : -1; });
    cap.innerHTML = `<b>${SCENES[i].title}</b><span>${SCENES[i].text}</span>`;
    if (user) auto = false;
    run(i, token);
  };
  let auto = true, visible = false;
  async function run(i: number, t: number) {
    fresh(i);
    if (reduce || !visible) return;
    for (;;) {
      const el = fresh(i);
      const s = new Scene(el.querySelector<HTMLElement>(".ip-screen")!, el, () => t === token && visible && !document.hidden);
      try { await s.wait(400); await SCENES[i].run(s); } catch { s.clear(); return; }
      s.clear();
      // after a full pass, move on to the next setup unless someone picked one
      if (auto) { show((i + 1) % SCENES.length); return; }
    }
  }

  SCENES.forEach((c, i) => {
    const b = document.createElement("button");
    b.type = "button"; b.setAttribute("role", "tab"); b.id = "uc-" + c.key; b.setAttribute("aria-controls", "ucStage");
    b.textContent = c.title; b.addEventListener("click", () => show(i, true));
    b.addEventListener("keydown", e => { const d = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0; if (d) { e.preventDefault(); const n = (cur + d + SCENES.length) % SCENES.length; show(n, true); btns[n].focus(); } });
    tabs.appendChild(b); btns.push(b);
  });
  show(0);
  new IntersectionObserver(([e]) => { const v = e.isIntersecting; if (v === visible) return; visible = v; token++; if (v) run(cur, token); }, { threshold: 0.3 }).observe(stage);
  document.addEventListener("visibilitychange", () => { if (!document.hidden && visible) { token++; run(cur, token); } });
}


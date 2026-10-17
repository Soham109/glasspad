/* The site's nav (site/render.ts writes it): a floating glass bar that shrinks a little once you
   scroll and turns dark over dark sections. Features and Compare open a menu on hover, on click,
   or from the keyboard (focus, Enter, Space or the down arrow opens; arrows move; Escape closes).
   On phones, Menu opens a full screen sheet. */

const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;

export function initNav() {
  const nav = document.getElementById("nav");
  if (!nav) return;
  const ind = document.getElementById("navInd")!;
  const links = document.getElementById("navLinks")!;
  const darks = Array.from(document.querySelectorAll<HTMLElement>(".dark"));
  const menu = document.getElementById("navMenu")!, sheet = document.getElementById("navSheet")!;
  const tops = Array.from(links.querySelectorAll<HTMLElement>(".gn-top"));
  const active = tops.find(t => t.classList.contains("is-active") || t.getAttribute("aria-current") === "page") ?? null;

  /* The soft pill behind the items: it rests on the current section and follows the pointer. */
  const place = (el: HTMLElement | null) => {
    if (!el) { ind.style.opacity = "0"; return; }
    // measured against the bar, unscaled: the bar shrinks a little once the page scrolls
    const k = links.getBoundingClientRect().width / links.offsetWidth || 1;
    const x = (el.getBoundingClientRect().left - links.getBoundingClientRect().left) / k;
    ind.style.opacity = "1"; ind.style.width = el.offsetWidth + "px"; ind.style.transform = `translateX(${x}px)`;
  };
  if (reduce) ind.style.transition = "none";
  tops.forEach(t => {
    const host = (t.closest(".gn-item") as HTMLElement) ?? t;
    host.addEventListener("pointerenter", () => place(t));
  });
  links.addEventListener("pointerleave", () => place(openItem ? openItem.querySelector<HTMLElement>(".gn-top") : active));

  /* Menus */
  const items = Array.from(links.querySelectorAll<HTMLElement>("[data-menu]"));
  let openItem: HTMLElement | null = null, closeTimer = 0, pointerDown = false;
  const btn = (it: HTMLElement) => it.querySelector<HTMLButtonElement>(".gn-top")!;
  const entries = (it: HTMLElement) => Array.from(it.querySelectorAll<HTMLAnchorElement>(".gn-panel a"));
  const open = (it: HTMLElement) => {
    clearTimeout(closeTimer);
    if (openItem === it) return;
    if (openItem) close(openItem);
    openItem = it; it.classList.add("open"); btn(it).setAttribute("aria-expanded", "true"); place(btn(it));
  };
  const close = (it: HTMLElement) => {
    it.classList.remove("open"); btn(it).setAttribute("aria-expanded", "false");
    if (openItem === it) { openItem = null; place(active); }
  };
  const closeSoon = (it: HTMLElement) => { clearTimeout(closeTimer); closeTimer = window.setTimeout(() => close(it), 160); };
  addEventListener("pointerdown", () => { pointerDown = true; }, true);
  addEventListener("pointerup", () => { setTimeout(() => { pointerDown = false; }); }, true);

  let hoverAt = 0;
  items.forEach(it => {
    const b = btn(it);
    it.addEventListener("pointerenter", e => { if (e.pointerType === "mouse") { if (openItem !== it) hoverAt = performance.now(); open(it); } });
    it.addEventListener("pointerleave", e => { if (e.pointerType === "mouse") closeSoon(it); });
    // a click right after hover opened the menu keeps it open; otherwise it toggles
    b.addEventListener("click", () => { if (openItem !== it) open(it); else if (performance.now() - hoverAt > 500) close(it); });
    b.addEventListener("focus", () => { if (!pointerDown && b.matches(":focus-visible")) open(it); });
    b.addEventListener("keydown", e => {
      if (e.key === "ArrowDown") { e.preventDefault(); open(it); entries(it)[0]?.focus(); }
      else if (e.key === "Escape") { close(it); }
      else if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
        e.preventDefault();
        const i = tops.indexOf(b), n = tops[(i + (e.key === "ArrowRight" ? 1 : -1) + tops.length) % tops.length];
        n.focus();
      }
    });
    it.addEventListener("keydown", e => {
      if (e.target === b) return;
      const list = entries(it), i = list.indexOf(document.activeElement as HTMLAnchorElement);
      if (i < 0) return;
      if (e.key === "ArrowDown" || e.key === "ArrowUp") {
        e.preventDefault();
        list[(i + (e.key === "ArrowDown" ? 1 : -1) + list.length) % list.length].focus();
      } else if (e.key === "Home") { e.preventDefault(); list[0].focus(); }
      else if (e.key === "End") { e.preventDefault(); list[list.length - 1].focus(); }
      else if (e.key === "Escape") { e.preventDefault(); close(it); b.focus(); }
    });
    // leaving the menu with Tab closes it
    it.addEventListener("focusout", e => { if (!it.contains(e.relatedTarget as Node)) close(it); });
  });
  document.addEventListener("click", e => { if (openItem && !openItem.contains(e.target as Node)) close(openItem); });
  addEventListener("keydown", e => { if (e.key === "Escape" && openItem) { const b = btn(openItem); close(openItem); b.focus(); } });

  /* Phone sheet */
  const setSheet = (on: boolean) => {
    sheet.classList.toggle("open", on); nav.classList.toggle("sheet-open", on);
    document.documentElement.classList.toggle("gn-locked", on);
    menu.setAttribute("aria-expanded", String(on)); menu.textContent = on ? "Close" : "Menu";
    if (on) sheet.querySelector<HTMLElement>("a")?.focus();
  };
  menu.addEventListener("click", () => setSheet(!sheet.classList.contains("open")));
  sheet.addEventListener("click", e => { if ((e.target as HTMLElement).closest("a")) setSheet(false); });
  addEventListener("keydown", e => { if (e.key === "Escape" && sheet.classList.contains("open")) { setSheet(false); menu.focus(); } });
  // Tab stays inside the open sheet and the bar above it
  sheet.addEventListener("keydown", e => {
    if (e.key !== "Tab") return;
    const f = Array.from(sheet.querySelectorAll<HTMLElement>("a"));
    if (!e.shiftKey && document.activeElement === f[f.length - 1]) { e.preventDefault(); menu.focus(); }
  });
  matchMedia("(min-width: 761px)").addEventListener("change", e => { if (e.matches && sheet.classList.contains("open")) setSheet(false); });

  /* Scroll: shrink a little, and go dark over dark sections */
  const update = () => {
    nav.classList.toggle("scrolled", scrollY > 24);
    const mid = 38;
    const dark = darks.some(d => { const r = d.getBoundingClientRect(); return r.top <= mid && r.bottom >= mid; });
    nav.classList.toggle("on-dark", dark);
  };
  let ticking = false;
  addEventListener("scroll", () => { if (!ticking) { ticking = true; requestAnimationFrame(() => { ticking = false; update(); }); } }, { passive: true });
  addEventListener("resize", () => place(openItem ? btn(openItem) : active));
  update();
  document.fonts?.ready.then(() => place(active));
  place(active);
}

/** Copy buttons for commands: <button class="copy" data-copy="..."> */
export function initCopy() {
  document.querySelectorAll<HTMLButtonElement>("button.copy[data-copy]").forEach(b => {
    if (b.dataset.wired) return; b.dataset.wired = "1";
    const label = b.querySelector("span")!;
    b.addEventListener("click", async () => {
      try { await navigator.clipboard.writeText(b.dataset.copy!); } catch { return; }
      b.classList.add("done"); label.textContent = "Copied";
      setTimeout(() => { b.classList.remove("done"); label.textContent = "Copy"; }, 1800);
    });
  });
}

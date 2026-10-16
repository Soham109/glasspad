import { clamp, reducedMotion, sleep } from "./spring";

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

/* ---------- Nav: floating glass pill ---------- */
export function initNav() {
  const nav = document.getElementById("nav")!;
  const ind = document.getElementById("navInd")!;
  const links = Array.from(document.querySelectorAll<HTMLAnchorElement>("#navLinks a"));
  const darks = Array.from(document.querySelectorAll<HTMLElement>(".dark"));
  const targets = links.map(a => { const h = a.getAttribute("href")!; return h.startsWith("#") ? document.querySelector<HTMLElement>(h) : null; });
  const menu = document.getElementById("navMenu")!, sheet = document.getElementById("navSheet")!;
  let active = -1;
  const place = () => {
    if (active < 0) { ind.style.opacity = "0"; return; }
    const a = links[active];
    ind.style.opacity = "1"; ind.style.width = a.offsetWidth + "px"; ind.style.transform = `translateX(${a.offsetLeft}px)`;
  };
  const update = () => {
    nav.classList.toggle("scrolled", scrollY > 24);
    const mid = 38;
    const dark = darks.some(d => { const r = d.getBoundingClientRect(); return r.top <= mid && r.bottom >= mid; });
    nav.classList.toggle("on-dark", dark);
    sheet.classList.toggle("on-dark", dark);
    let a = -1; const line = innerHeight * 0.4;
    targets.forEach((t, i) => { if (t && t.getBoundingClientRect().top <= line) a = i; });
    if (a >= 0 && targets[a]!.getBoundingClientRect().bottom < line) a = -1;
    if (a !== active) { active = a; links.forEach((l, i) => l.setAttribute("aria-current", String(i === a))); place(); }
  };
  let ticking = false;
  addEventListener("scroll", () => { if (!ticking) { ticking = true; requestAnimationFrame(() => { ticking = false; update(); }); } }, { passive: true });
  addEventListener("resize", place);
  const close = () => { sheet.classList.remove("open"); menu.setAttribute("aria-expanded", "false"); menu.textContent = "Menu"; };
  menu.addEventListener("click", () => {
    const open = !sheet.classList.contains("open");
    sheet.classList.toggle("open", open); menu.setAttribute("aria-expanded", String(open)); menu.textContent = open ? "Close" : "Menu";
    if (open) (sheet.querySelector("a") as HTMLElement).focus();
  });
  sheet.addEventListener("click", e => { if ((e.target as HTMLElement).closest("a")) close(); });
  addEventListener("keydown", e => { if (e.key === "Escape" && sheet.classList.contains("open")) { close(); menu.focus(); } });
  update();
}

/* ---------- Scroll-linked: hero mark eases back, demo phone settles into place ---------- */
export function initScrollLinked() {
  if (reduce) return;
  const mark = document.querySelector<SVGElement>("#heroGlide");
  const phone = document.getElementById("phone");
  const demo = document.getElementById("trackpad");
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

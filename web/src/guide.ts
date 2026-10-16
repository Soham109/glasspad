import "./style.css";
import "./redo.css";
import "./guide.css";
import { initNav, initReveals } from "./sections";
import { THEMES } from "./themes";

/* The guide: the site's nav, and copy buttons for commands. */
initNav();
initReveals();
document.querySelectorAll<HTMLButtonElement>("button.copy[data-copy]").forEach(b => {
  const label = b.querySelector("span")!;
  b.addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(b.dataset.copy!); } catch { return; }
    b.classList.add("done"); label.textContent = "Copied";
    setTimeout(() => { b.classList.remove("done"); label.textContent = "Copy"; }, 1800);
  });
});

// the theme list lives in one place (themes.ts)
const names = THEMES.map(t => t.name);
document.querySelectorAll<HTMLElement>("[data-themes]").forEach(el => {
  el.textContent = `Settings, then Appearance: ${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}. System follows your iPhone.`;
});

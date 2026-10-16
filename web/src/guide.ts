import "./style.css";
import "./redo.css";
import "./guide.css";
import { initNav, initReveals } from "./sections";

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

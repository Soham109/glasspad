import "./style.css";
import "./redo.css";
import "./guide.css";
import "./learn.css";
import { initNav } from "./sections";

/* The Learn pages (scripts/learn.mjs): the site's nav, and the copy button for the install command. */
initNav();
document.querySelectorAll<HTMLButtonElement>("button.copy[data-copy]").forEach(b => {
  const label = b.querySelector("span")!;
  b.addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(b.dataset.copy!); } catch { return; }
    b.classList.add("done"); label.textContent = "Copied";
    setTimeout(() => { b.classList.remove("done"); label.textContent = "Copy"; }, 1800);
  });
});

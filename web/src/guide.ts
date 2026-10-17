import "./style.css";
import "./redo.css";
import "./guide.css";
import "./site.css";
import { initReveals } from "./sections";
import { initNav, initCopy } from "./nav";
import { themesLine } from "./themes";

/* The guide: the site's nav, and copy buttons for commands. */
initNav();
initReveals();
initCopy();

// the theme list lives in one place (themes.ts)
document.querySelectorAll<HTMLElement>("[data-themes]").forEach(el => { el.textContent = `Settings, then Theme. ${themesLine()} System follows your iPhone.`; });

import "./style.css";
import "./device.css";
import "./redo.css";
import "./v3.css";
import "./site.css";
import { initNav } from "./nav";
import { initInstall } from "./install";
import { initReveals } from "./sections";

/* The install page: the nav, the install steps with their drawings, and copy buttons. */
initNav();
initInstall();
initReveals();

// A link to a closed section (#troubleshooting, #uninstall) opens it.
function openTarget() {
  const el = location.hash && document.getElementById(decodeURIComponent(location.hash.slice(1)));
  if (el instanceof HTMLDetailsElement) { el.open = true; el.scrollIntoView(); }
}
openTarget();
addEventListener("hashchange", openTarget);

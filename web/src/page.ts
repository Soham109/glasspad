import "./style.css";
import "./device.css";
import "./redo.css";
import "./v3.css";
import "./surface.css";
import "./site.css";
import { initNav, initCopy } from "./nav";

/* The Features and Compare pages (site/render.ts): the nav, copy buttons, and the drawn scene
   under the hero, loaded only on the page that shows it. */
initNav();
initCopy();

if (document.getElementById("surface")) import("./demo").then(m => m.initDemo());
if (document.getElementById("dpStage")) import("./displays").then(m => m.initDisplays());
const room = document.querySelector<HTMLElement>("[data-room]");
if (room) import("./scenes").then(m => m.mountRoom(room, room.dataset.room!));
const mode = document.querySelector<HTMLElement>("[data-mode]");
if (mode) import("./modes").then(m => m.mountMode(mode, mode.dataset.mode!));

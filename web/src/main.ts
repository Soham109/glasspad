import "./style.css";
import { initHero } from "./hero";
import { initDemo } from "./demo";
import { initSettings } from "./settings";
import { initReveals, initNav, initScrollLinked, initModes, initProfiles, initSteps, initNet, initCopy } from "./sections";

requestAnimationFrame(() => document.querySelector(".hero")?.classList.add("in"));
initNav();
initHero();
initSettings();
initDemo();
initModes();
initProfiles();
initSteps();
initNet();
initCopy();
initReveals();
initScrollLinked();

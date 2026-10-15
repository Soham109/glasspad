/** Shared demo settings. The settings section edits them; the trackpad demo reads them. */
export const settings = { speed: 1.5, natural: true, drag: false, pages: true, mission: true };
type Key = "natural" | "drag" | "pages" | "mission";

export function initSettings() {
  const pulse = document.getElementById("pulse");
  const speed = document.getElementById("speed") as HTMLInputElement | null;
  const speedOut = document.getElementById("speedOut");
  const send = () => { if (!pulse) return; pulse.classList.remove("go"); void pulse.offsetWidth; pulse.classList.add("go"); };

  document.querySelectorAll<HTMLButtonElement>(".toggle").forEach(t => t.addEventListener("click", () => {
    const key = t.dataset.key as Key;
    const on = t.getAttribute("aria-checked") !== "true";
    t.setAttribute("aria-checked", String(on));
    settings[key] = on;
    send();
    const out = document.querySelector<HTMLElement>(`[data-out="${key}"]`);
    if (out) setTimeout(() => { out.textContent = on ? "On" : "Off"; out.classList.remove("flip"); void out.offsetWidth; out.classList.add("flip"); }, 420);
  }));
  if (speed && speedOut) {
    const apply = () => { settings.speed = +speed.value; speedOut.style.transform = `scaleX(${(+speed.value / 3).toFixed(3)})`; };
    speed.addEventListener("input", apply);
    speed.addEventListener("change", send);
    apply();
  }
}

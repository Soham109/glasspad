/* Click to load: the YouTube player is only fetched once someone asks for it. */
export function initFilm() {
  const btn = document.getElementById("filmPlay");
  const frame = document.getElementById("filmFrame");
  if (!btn || !frame) return;
  btn.addEventListener("click", () => {
    const f = document.createElement("iframe");
    f.src = "https://www.youtube-nocookie.com/embed/6AArTWOADGc?autoplay=1";
    f.title = "Glasspad demo film";
    f.allow = "autoplay; encrypted-media; picture-in-picture";
    f.allowFullscreen = true;
    f.referrerPolicy = "strict-origin-when-cross-origin";
    frame.replaceChildren(f);
    f.focus();
  });
}

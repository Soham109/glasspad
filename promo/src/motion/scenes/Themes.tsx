import React from "react";
import { useCurrentFrame } from "remotion";
import { Title, CSS, Phone } from "../parts";
import { ActionsLand } from "../screens";
import { THEMES, Theme } from "../site/themes";
import { clamp, E, INOUT, lerp, OUT } from "../kit";
import { BEAT, sceneSec, titleAt } from "../timeline";

/* Scene 11: one Actions screen in six of the 28 themes (ThemeCatalog.swift), one every two beats,
   each wiping in from the middle of the screen. Film seconds. */

const T0 = sceneSec("themes"), P0 = sceneSec("private");
const KEYS = ["paper", "mono", "glass", "aurora", "midnight", "photo"];
export const THEME_AT = (i: number) => T0 + i * 2 * BEAT;
export const THEMES_CUES = () => ({ whoosh: KEYS.slice(1).map((_, i) => THEME_AT(i + 1) - 0.05) });

const vars = (t: Theme): CSS => ({
  "--pt-bg": t.bg, "--tile": t.tile, "--ink": t.ink, "--ink2": t.ink2,
  "--tline": t.dark ? "rgba(255,255,255,.1)" : "rgba(0,0,0,.07)", "--tint": t.dark ? "26%" : "16%",
} as CSS);

export const Themes: React.FC = () => {
  const t = useCurrentFrame() / 60;
  const themes = KEYS.map(k => THEMES.find(x => x.key === k)!);
  const i = Math.max(0, Math.min(5, Math.floor((t - T0 + 0.0001) / (2 * BEAT))));
  const wipe = i === 0 ? 1 : E(t, THEME_AT(i), 0.5, INOUT);
  const inP = E(t, T0 - 0.05, 0.6);
  const out = E(t, P0 - 0.45, 0.45, INOUT);
  const W = 1180, w = W * 71.9 / 150;
  const screen = (th: Theme) => (
    <div className={th.mono ? "fm-mono" : ""} style={{ position: "absolute", inset: 0 }}>
      <ActionsLand app="safari" vars={vars(th)} />
    </div>
  );
  const prev = themes[Math.max(0, i - 1)], cur = themes[i];
  const r = lerp(0, 980, wipe);
  const nameO = (k: number) => clamp(E(t, THEME_AT(k) + 0.05, 0.3) - E(t, THEME_AT(k + 1) - 0.12, 0.12));
  return (
    <div className="fm" style={{ background: "#141414" }}>
      <div className="fm-world" style={{ opacity: inP * (1 - out), transform: `scale(${lerp(0.96, 1, OUT(inP)) * lerp(1, 0.94, out)})`, transformOrigin: "50% 46%" }}>
        <Phone cx={960} cy={500} w={w} turn={1} land={
          <>
            {i > 0 && wipe < 1 ? screen(prev) : null}
            <div style={{ position: "absolute", inset: 0, clipPath: i > 0 && wipe < 1 ? `circle(${r}px at 437px 201px)` : undefined }}>{screen(cur)}</div>
          </>} />
        {themes.map((th, k) => nameO(k) > 0.001 ? (
          <div key={th.key} style={{ position: "absolute", left: 0, right: 0, top: 830, textAlign: "center", color: "#F2F1EE", opacity: nameO(k), transform: `translateY(${(1 - OUT(clamp(E(t, THEME_AT(k) + 0.05, 0.3)))) * 10}px)` }}>
            <b style={{ fontSize: 34, fontWeight: 600, letterSpacing: "-0.02em" }}>{th.name}</b>
            <span style={{ fontSize: 22, color: "rgba(242,241,238,0.5)", marginLeft: 14 }}>{th.group}</span>
          </div>) : null)}
      </div>
      <Title text="Themes" dark {...titleAt("themes", t)} />
    </div>
  );
};

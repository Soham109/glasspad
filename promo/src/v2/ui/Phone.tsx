// iPhone 18 Pro class device, flat vector. Proportions follow the site drawing
// (web/src/device.css): 71.9 x 150 mm body, screen inset 3.65% of the short side, screen
// corner 12.7%, body corner 16.4%. The screen is a slot: a real recording or drawn content.
import React from "react";
import { C } from "../system";

export const PHONE_ASPECT = 71.9 / 150;

type Props = {
  /** Length of the short side in px. */
  short: number;
  orient?: "portrait" | "landscape";
  children?: React.ReactNode;
  screen?: string; // screen colour behind the content
  island?: boolean; // recordings already contain the island
  style?: React.CSSProperties;
};

export const Phone: React.FC<Props> = ({ short, orient = "portrait", children, screen = C.graphite, island = true, style }) => {
  const long = short / PHONE_ASPECT;
  const w = orient === "portrait" ? short : long;
  const h = orient === "portrait" ? long : short;
  const u = short / 100; // one "cqmin"
  const inset = 3.65 * u;
  const btn = (pos: number, len: number, side: "a" | "b", key: string) => {
    // a = left edge in portrait (bottom edge in landscape); b = right edge (top edge)
    const t = 1.1 * u;
    const out = -0.8 * u;
    if (orient === "portrait")
      return <div key={key} style={{ position: "absolute", top: `${pos}%`, height: `${len}%`, width: t, [side === "a" ? "left" : "right"]: out, background: "#ADAAA4", borderRadius: 0.6 * u }} />;
    return <div key={key} style={{ position: "absolute", left: `${pos}%`, width: `${len}%`, height: t, [side === "a" ? "bottom" : "top"]: out, background: "#ADAAA4", borderRadius: 0.6 * u }} />;
  };
  return (
    <div style={{ position: "relative", width: w, height: h, ...style }}>
      {btn(18, 5, "a", "act")}
      {btn(26.5, 8.5, "a", "up")}
      {btn(36.5, 8.5, "a", "dn")}
      {btn(27, 12, "b", "side")}
      <div style={{ position: "absolute", inset: 0, borderRadius: 16.4 * u, background: C.band, boxShadow: `inset 0 0 0 ${0.35 * u}px #A3A09A` }} />
      <div style={{ position: "absolute", inset: 1.25 * u, borderRadius: 15.2 * u, background: C.bezel }} />
      <div style={{ position: "absolute", inset, borderRadius: 12.7 * u, overflow: "hidden", background: screen, isolation: "isolate" }}>
        {children}
      </div>
      {island ? (
        <div
          style={{
            position: "absolute",
            background: "#000",
            borderRadius: 99 * u,
            ...(orient === "portrait"
              ? { top: inset + 2.5 * u, left: "50%", width: 29 * u, height: 8.5 * u, transform: "translateX(-50%)" }
              : { left: inset + 2.5 * u, top: "50%", height: 29 * u, width: 8.5 * u, transform: "translateY(-50%)" }),
          }}
        />
      ) : null}
    </div>
  );
};

/** Size of the screen slot inside a phone of short side `short`. */
export const phoneScreen = (short: number, orient: "portrait" | "landscape" = "portrait") => {
  const long = short / PHONE_ASPECT;
  const inset = 3.65 * (short / 100) * 2;
  return orient === "portrait" ? { w: short - inset, h: long - inset } : { w: long - inset, h: short - inset };
};

import React from "react";
import { FONT } from "../theme";

/* iPhone 18 Pro class device, flat. Proportions from web/src/device.css: 71.9 x 150 mm body,
   screen inset 3.65% of the short side, screen corner 12.7%, body corner 16.4%.
   Always drawn portrait; `land` rotates the content box so landscape screens are authored at 874 x 402 points. */
export const PHONE_ASPECT = 150 / 71.9;
export const PT_W = 402, PT_H = 874;

export const phoneGeom = (w: number) => {
  const h = w * PHONE_ASPECT;
  const inset = 0.0365 * w;
  const sw = w - 2 * inset, sh = h - 2 * inset;
  return { w, h, inset, sw, sh, s: sw / PT_W };
};

type Props = {
  w: number;
  finish?: "light" | "dark";
  land?: boolean; // content authored landscape (874 x 402), device still portrait (rotate the wrapper yourself)
  screenBg?: string;
  children?: React.ReactNode;
  /** 0..1: how much of the body has grown out from the screen edge (used by the icon morph) */
  body?: number;
  shake?: number; // px offset for the haptic shake
};

export const Phone: React.FC<Props> = ({ w, finish = "light", land, screenBg = "#F2F1EE", children, body = 1, shake = 0 }) => {
  const g = phoneGeom(w);
  const band = finish === "dark" ? "#3C3B39" : "#BDBAB4";
  const bandEdge = finish === "dark" ? "#2B2A29" : "#A3A09A";
  const btn = finish === "dark" ? "#353432" : "#ADAAA4";
  const grow = (v: number) => g.inset * (1 - body) + v * body; // inset of each layer while growing
  const bodyInset = grow(0);
  const bezelInset = grow(0.0125 * w);
  const r = (k: number) => k * w;
  const b = (top: number, height: number, side: "l" | "r", extra?: React.CSSProperties): React.CSSProperties => ({
    position: "absolute", top: `${top}%`, height: `${height}%`, width: 0.011 * w, borderRadius: 0.006 * w, background: btn,
    [side === "l" ? "left" : "right"]: -0.008 * w, opacity: body, ...extra,
  });
  return (
    <div style={{ position: "relative", width: g.w, height: g.h, transform: shake ? `translate(${shake}px, ${-shake * 0.4}px)` : undefined }}>
      <i style={b(18, 5, "l")} />
      <i style={b(26.5, 8.5, "l")} />
      <i style={b(36.5, 8.5, "l")} />
      <i style={b(27, 12, "r")} />
      <i style={b(56, 11, "r", { right: -0.0035 * w, opacity: 0.7 * body })} />
      <div style={{ position: "absolute", inset: bodyInset, borderRadius: r(0.164) - bodyInset * 0.5, background: band, boxShadow: `inset 0 0 0 ${0.0035 * w}px ${bandEdge}`, opacity: body > 0 ? 1 : 0 }} />
      <div style={{ position: "absolute", inset: bezelInset, borderRadius: r(0.152) - (bezelInset - 0.0125 * w) * 0.5, background: "#0C0C0C", opacity: body > 0 ? 1 : 0 }} />
      <div style={{ position: "absolute", inset: g.inset, borderRadius: r(0.127), overflow: "hidden", background: screenBg, isolation: "isolate" }}>
        <div
          style={{
            position: "absolute", left: 0, top: 0,
            width: land ? PT_H : PT_W, height: land ? PT_W : PT_H,
            transformOrigin: "0 0",
            transform: land ? `translate(${g.sw}px, 0) rotate(90deg) scale(${g.s})` : `scale(${g.s})`,
            fontFamily: FONT, color: "#1A1A1A",
          }}
        >
          {children}
        </div>
      </div>
      <div style={{ position: "absolute", zIndex: 5, top: g.inset + 0.025 * w, left: "50%", width: 0.29 * w, height: 0.085 * w, transform: "translateX(-50%)", borderRadius: w, background: "#000", opacity: body }} />
    </div>
  );
};

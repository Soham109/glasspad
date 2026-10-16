// The Mac hardware, drawn front on: a MacBook Pro 14 inch (notch, thin black border, the
// aluminium base seen as a lip) and a 27 inch external display on a stand. No logos.
// Screen content is authored in points (MacBook 1512 x 982, display 1600 x 900) and scaled.
import React from "react";

export const MBP = { w: 1512, h: 982 };
export const EXT = { w: 1600, h: 900 };

const alu = (dark = false) => (dark
  ? "linear-gradient(180deg, #4A4B4F 0%, #2C2D30 60%, #1E1F21 100%)"
  : "linear-gradient(180deg, #D9D9DC 0%, #B7B7BB 55%, #8F9094 100%)");

export const MacBookPro: React.FC<{ width: number; children?: React.ReactNode; dark?: boolean; base?: boolean; style?: React.CSSProperties; glow?: number }> = ({ width, children, dark = true, base = true, style, glow = 1 }) => {
  const border = width * 0.012;
  const sw = width - border * 2;
  const k = sw / MBP.w;
  const sh = MBP.h * k;
  const lidH = sh + border * 2 + width * 0.006;
  const r = width * 0.028;
  return (
    <div style={{ position: "relative", width, height: lidH + (base ? width * 0.03 : 0), ...style }}>
      <div style={{ position: "absolute", left: 0, top: 0, width, height: lidH, borderRadius: `${r}px ${r}px ${width * 0.006}px ${width * 0.006}px`, background: alu(dark), padding: width * 0.0025 }}>
        <div style={{ width: "100%", height: "100%", borderRadius: `${r * 0.92}px ${r * 0.92}px 2px 2px`, background: "#050505" }} />
      </div>
      <div style={{ position: "absolute", left: border, top: border, width: sw, height: sh, borderRadius: `${width * 0.012}px ${width * 0.012}px 0 0`, overflow: "hidden", background: "#000" }}>
        <div style={{ position: "absolute", left: 0, top: 0, width: MBP.w, height: MBP.h, transform: `scale(${k})`, transformOrigin: "0 0", opacity: glow }}>{children}</div>
        <div style={{ position: "absolute", inset: 0, background: "linear-gradient(155deg, rgba(255,255,255,0.06) 0%, rgba(255,255,255,0) 30%)", pointerEvents: "none" }} />
      </div>
      {/* the notch: camera housing in the top border */}
      <div style={{ position: "absolute", left: width / 2 - width * 0.065, top: border - 1, width: width * 0.13, height: width * 0.021, borderRadius: `0 0 ${width * 0.008}px ${width * 0.008}px`, background: "#050505" }} />
      {base ? (
        <>
          <div style={{ position: "absolute", left: -width * 0.055, top: lidH - 1, width: width * 1.11, height: width * 0.017, borderRadius: `0 0 ${width * 0.03}px ${width * 0.03}px / 0 0 ${width * 0.012}px ${width * 0.012}px`, background: dark ? "linear-gradient(180deg, #5A5B5F, #2A2B2E)" : "linear-gradient(180deg, #E4E4E7, #9C9DA1)" }} />
          <div style={{ position: "absolute", left: width / 2 - width * 0.08, top: lidH - 1, width: width * 0.16, height: width * 0.0065, borderRadius: `0 0 ${width * 0.006}px ${width * 0.006}px`, background: dark ? "#1A1A1C" : "#8A8B8F" }} />
        </>
      ) : null}
    </div>
  );
};

/** 27 inch display with a slim aluminium frame on a tilt stand. */
export const ExternalDisplay: React.FC<{ width: number; children?: React.ReactNode; stand?: boolean; style?: React.CSSProperties; glow?: number }> = ({ width, children, stand = true, style, glow = 1 }) => {
  const frame = width * 0.004;
  const border = width * 0.018;
  const sw = width - (frame + border) * 2;
  const k = sw / EXT.w;
  const sh = EXT.h * k;
  const H = sh + (frame + border) * 2;
  const r = width * 0.012;
  return (
    <div style={{ position: "relative", width, height: H + (stand ? width * 0.3 : 0), ...style }}>
      {stand ? (
        <>
          <div style={{ position: "absolute", left: width / 2 - width * 0.09, top: H * 0.55, width: width * 0.18, height: H * 0.45 + width * 0.27, background: "linear-gradient(90deg, #7D7E82 0%, #C9C9CD 30%, #A6A7AB 70%, #6E6F73 100%)", borderRadius: width * 0.006 }} />
          <div style={{ position: "absolute", left: width / 2 - width * 0.13, top: H + width * 0.27, width: width * 0.26, height: width * 0.03, borderRadius: width * 0.01, background: "linear-gradient(180deg, #D3D3D7, #8B8C90)" }} />
        </>
      ) : null}
      <div style={{ position: "absolute", left: 0, top: 0, width, height: H, borderRadius: r, background: "linear-gradient(180deg, #CFCFD3, #9A9B9F)", padding: frame }}>
        <div style={{ width: "100%", height: "100%", borderRadius: r * 0.8, background: "#050505" }} />
      </div>
      <div style={{ position: "absolute", left: frame + border, top: frame + border, width: sw, height: sh, overflow: "hidden", background: "#000" }}>
        <div style={{ position: "absolute", left: 0, top: 0, width: EXT.w, height: EXT.h, transform: `scale(${k})`, transformOrigin: "0 0", opacity: glow }}>{children}</div>
        <div style={{ position: "absolute", inset: 0, background: "linear-gradient(160deg, rgba(255,255,255,0.05) 0%, rgba(255,255,255,0) 26%)", pointerEvents: "none" }} />
      </div>
    </div>
  );
};

/** Screen rectangle of an ExternalDisplay of `width`, relative to its top left. */
export const extScreen = (width: number) => {
  const frame = width * 0.004, border = width * 0.018;
  const sw = width - (frame + border) * 2;
  return { x: frame + border, y: frame + border, w: sw, h: (EXT.h * sw) / EXT.w, k: sw / EXT.w };
};
export const mbpScreen = (width: number) => {
  const border = width * 0.012;
  const sw = width - border * 2;
  return { x: border, y: border, w: sw, h: (MBP.h * sw) / MBP.w, k: sw / MBP.w };
};

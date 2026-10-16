// iPhone 18 Pro class device, drawn front on. Proportions of the 6.3 inch Pro: 71.9 x 150 mm
// body, a thin even border (about 1.4 mm of black around a 2.6 mm aluminium frame edge seen
// front on), continuous corners, the Dynamic Island, side buttons. Lit as a studio product
// shot: a soft key from the upper left, a rim on the frame, the glass catching a sweep.
import React from "react";

export const IPHONE = { w: 71.9, h: 150, screenInset: 2.0, frame: 0.85, corner: 11.6, screenCorner: 9.6 };
/** The captures are 1206 x 2622 px (the simulator's iPhone 18 Pro). */
export const CAPTURE = { w: 1206, h: 2622 };

type Props = {
  /** Short side of the body in px. */
  size: number;
  orient?: "portrait" | "landscape";
  /** Screen content, drawn in capture pixels (1206 x 2622 portrait or 2622 x 1206 landscape). */
  children?: React.ReactNode;
  /** 0..1 position of the light sweep across the glass (it is off outside 0..1). */
  sweep?: number;
  /** Finish of the frame. */
  finish?: "silver" | "graphite";
  /** Screen glow brightness (0 = off). */
  glow?: number;
  style?: React.CSSProperties;
};

export const IPhone: React.FC<Props> = ({ size, orient = "portrait", children, sweep = -1, finish = "graphite", glow = 1, style }) => {
  const mm = size / IPHONE.w;
  const W = orient === "portrait" ? size : IPHONE.h * mm;
  const H = orient === "portrait" ? IPHONE.h * mm : size;
  const inset = IPHONE.screenInset * mm;
  const sw = W - inset * 2, sh = H - inset * 2;
  const capW = orient === "portrait" ? CAPTURE.w : CAPTURE.h;
  const k = sw / capW;
  const frameLight = finish === "silver" ? ["#E9E8E6", "#B9B8B5", "#8E8D8A"] : ["#6B6A6E", "#3A393D", "#1F1F22"];
  const island = orient === "portrait"
    ? { left: W / 2 - 10.1 * mm, top: inset + 1.15 * mm, width: 20.2 * mm, height: 6.0 * mm }
    : { top: H / 2 - 10.1 * mm, left: inset + 1.15 * mm, height: 20.2 * mm, width: 6.0 * mm };
  const btn = (along: number, len: number, side: "a" | "b", key: string) => {
    const t = 0.7 * mm, o = -0.45 * mm;
    if (orient === "portrait")
      return <div key={key} style={{ position: "absolute", top: along * mm, height: len * mm, width: t, [side === "a" ? "left" : "right"]: o, borderRadius: t, background: `linear-gradient(90deg, ${frameLight[2]}, ${frameLight[0]}, ${frameLight[2]})` }} />;
    return <div key={key} style={{ position: "absolute", left: along * mm, width: len * mm, height: t, [side === "a" ? "bottom" : "top"]: o, borderRadius: t, background: `linear-gradient(0deg, ${frameLight[2]}, ${frameLight[0]}, ${frameLight[2]})` }} />;
  };
  return (
    <div style={{ position: "relative", width: W, height: H, ...style }}>
      {/* buttons: action, volume up, volume down on one side; side button and camera control on the other */}
      {btn(27, 7, "a", "act")}
      {btn(39, 12, "a", "up")}
      {btn(54, 12, "a", "dn")}
      {btn(40, 17, "b", "side")}
      {btn(92, 11, "b", "cam")}
      {/* the aluminium frame, lit from the upper left */}
      <div style={{ position: "absolute", inset: 0, borderRadius: IPHONE.corner * mm, background: `linear-gradient(135deg, ${frameLight[0]} 0%, ${frameLight[1]} 22%, ${frameLight[2]} 55%, ${frameLight[1]} 82%, ${frameLight[0]} 100%)` }} />
      {/* black glass border */}
      <div style={{ position: "absolute", inset: IPHONE.frame * mm, borderRadius: (IPHONE.corner - IPHONE.frame) * mm, background: "#030304", boxShadow: `inset 0 0 0 ${0.12 * mm}px rgba(255,255,255,0.08)` }} />
      {/* the display */}
      <div style={{ position: "absolute", left: inset, top: inset, width: sw, height: sh, borderRadius: IPHONE.screenCorner * mm, overflow: "hidden", background: "#000", isolation: "isolate" }}>
        <div style={{ position: "absolute", left: 0, top: 0, width: capW, height: sh / k, transform: `scale(${k})`, transformOrigin: "0 0", opacity: glow }}>{children}</div>
      </div>
      <div style={{ position: "absolute", borderRadius: 99 * mm, background: "#000", ...island }} />
      {/* the glass: a broad soft reflection, and a sweep that crosses it when asked */}
      <div style={{ position: "absolute", left: inset, top: inset, width: sw, height: sh, borderRadius: IPHONE.screenCorner * mm, overflow: "hidden", pointerEvents: "none" }}>
        <div style={{ position: "absolute", inset: 0, background: "linear-gradient(160deg, rgba(255,255,255,0.07) 0%, rgba(255,255,255,0.0) 34%)" }} />
        {sweep >= 0 && sweep <= 1 ? (
          <div style={{ position: "absolute", top: -H * 0.5, height: H * 2, width: W * 0.35, left: -W * 0.6 + sweep * W * 1.9, transform: "rotate(24deg)", background: "linear-gradient(90deg, rgba(255,255,255,0) 0%, rgba(255,255,255,0.16) 50%, rgba(255,255,255,0) 100%)" }} />
        ) : null}
      </div>
    </div>
  );
};

/** Size of the display inside an IPhone of short side `size`. */
export const iphoneScreen = (size: number, orient: "portrait" | "landscape" = "portrait") => {
  const mm = size / IPHONE.w;
  const W = orient === "portrait" ? size : IPHONE.h * mm;
  const H = orient === "portrait" ? IPHONE.h * mm : size;
  const inset = IPHONE.screenInset * mm;
  return { x: inset, y: inset, w: W - inset * 2, h: H - inset * 2, W, H };
};

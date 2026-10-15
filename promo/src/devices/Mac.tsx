import React from "react";
import { FONT } from "../theme";

/* MacBook Pro, flat, ported from web/src/redo.css (.mbp). L = lid width in px.
   The display holds content authored at 1512 x 982 points. */
export const DISP_W = 1512, DISP_H = 982;
export const macGeom = (L: number) => {
  const lidH = L / 1.49;
  const dx = 0.0186 * L, dy = 0.0224 * L;
  const dw = L - 2 * dx, dh = dw / (DISP_W / DISP_H);
  const hinge = 0.0155 * L, baseH = 0.093 * L, lip = 0.0138 * L;
  return { L, lidH, dx, dy, dw, dh, s: dw / DISP_W, hinge, baseH, lip, total: lidH + baseH + lip };
};

export const Mac: React.FC<{ L: number; children?: React.ReactNode; displayBg?: string; base?: boolean }> = ({ L, children, displayBg = "#CFCBC3", base = true }) => {
  const g = macGeom(L);
  return (
    <div style={{ position: "relative", width: L, height: g.total }}>
      <div style={{ position: "absolute", left: 0, top: 0, width: L, height: g.lidH, borderRadius: `${0.0362 * L}px ${0.0362 * L}px ${0.0103 * L}px ${0.0103 * L}px`, background: "#B9B6B0" }}>
        <div style={{ position: "absolute", inset: 0.0048 * L, borderRadius: `${0.0319 * L}px ${0.0319 * L}px ${0.007 * L}px ${0.007 * L}px`, background: "#0D0D0D" }} />
        <div style={{ position: "absolute", left: g.dx, top: g.dy, width: g.dw, height: g.dh, borderRadius: `${0.0172 * L}px ${0.0172 * L}px ${0.0026 * L}px ${0.0026 * L}px`, overflow: "hidden", background: displayBg, isolation: "isolate" }}>
          <div style={{ position: "absolute", left: 0, top: 0, width: DISP_W, height: DISP_H, transformOrigin: "0 0", transform: `scale(${g.s})`, fontFamily: FONT, color: "#1A1A1A" }}>{children}</div>
        </div>
        <div style={{ position: "absolute", left: "50%", top: 0.0048 * L, width: 0.129 * L, height: 0.0302 * L, transform: "translateX(-50%)", background: "#0D0D0D", borderRadius: `0 0 ${0.0138 * L}px ${0.0138 * L}px`, zIndex: 3 }} />
      </div>
      {base && (
        <>
          <div style={{ position: "absolute", left: 0.04 * L, right: 0.04 * L, top: g.lidH, height: g.hinge, background: "#2A2A2A", borderRadius: `0 0 ${0.005 * L}px ${0.005 * L}px` }} />
          <div style={{ position: "absolute", left: -0.055 * L, right: -0.055 * L, top: g.lidH, height: g.baseH, background: "#C9C6C0", clipPath: "polygon(5.4% 0, 94.6% 0, 100% 100%, 0 100%)" }}>
            <div style={{ position: "absolute", left: "13%", top: "10%", width: "74%", height: "48%", background: "#33322F", clipPath: "polygon(1.5% 0, 98.5% 0, 100% 100%, 0 100%)" }} />
            <div style={{ position: "absolute", left: "37%", top: "64%", width: "26%", height: "30%", background: "#BCB9B3", clipPath: "polygon(3% 0, 97% 0, 100% 100%, 0 100%)" }} />
          </div>
          <div style={{ position: "absolute", left: -0.055 * L, right: -0.055 * L, top: g.lidH + g.baseH, height: g.lip, background: "#AFACA6", borderRadius: `0 0 ${0.0086 * L}px ${0.0086 * L}px` }}>
            <div style={{ position: "absolute", left: "50%", top: 0, width: 0.172 * L, height: 0.006 * L, transform: "translateX(-50%)", background: "#9F9C96", borderRadius: `0 0 ${0.007 * L}px ${0.007 * L}px` }} />
          </div>
        </>
      )}
    </div>
  );
};

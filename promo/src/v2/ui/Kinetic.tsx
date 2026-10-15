// Kinetic typography. Every word (or letter) sits in its own mask and rises into place on a
// stagger; leaving, it rises out of the same mask. One component, so all type moves alike.
import React from "react";
import { useCurrentFrame } from "remotion";
import { C, E, FONT, T, clamp01, lerp, prog, spr } from "../system";

type Props = {
  text: string;
  at: number; // local frame the first unit starts
  out?: number; // local frame the exit starts
  by?: "word" | "letter";
  stagger?: number; // frames between units
  style?: React.CSSProperties;
  color?: string;
  /** Words (exact, without punctuation) drawn in the accent, or underlined with it. */
  accent?: string[];
  align?: "left" | "center" | "right";
  /** Arrival: a rise through the mask, or a scale-in for punchy single words. */
  enter?: "rise" | "scale";
  lineBreaks?: number[]; // word indices that start a new line
  /** Start frame per unit (overrides at + stagger), e.g. the spoken word times. */
  times?: number[];
};

export const Kinetic: React.FC<Props> = ({ text, at, out, by = "word", stagger, style = T.hero, color = C.ink, accent = [], align = "left", enter = "rise", lineBreaks = [], times }) => {
  const frame = useCurrentFrame();
  const words = text.split(" ");
  const st = stagger ?? (by === "word" ? 4 : 1.6);
  let unit = 0;
  const lines: React.ReactNode[][] = [[]];
  words.forEach((w, wi) => {
    if (lineBreaks.includes(wi) && wi > 0) lines.push([]);
    const bare = w.replace(/[.,!?]/g, "");
    const isAccent = accent.includes(bare);
    const pieces = by === "letter" ? w.split("") : [w];
    const node = (
      <span key={wi} style={{ display: "inline-block", whiteSpace: "nowrap", marginRight: "0.24em" }}>
        {pieces.map((p, pi) => {
          const i = unit++;
          const start = times?.[i] ?? at + i * st;
          const tIn = enter === "rise" ? spr(frame, start, "settle") : spr(frame, start, "pop");
          const tOut = out === undefined ? 0 : prog(frame, out + i * st * 0.6, 18, E.in);
          const y = enter === "rise" ? lerp(115, 0, tIn) - 135 * tOut : -135 * tOut;
          const sc = enter === "scale" ? lerp(0.6, 1, tIn) : 1;
          return (
            <span key={pi} style={{ display: "inline-block", overflow: "hidden", verticalAlign: "top", paddingBottom: "0.12em", marginBottom: "-0.12em" }}>
              <span
                style={{
                  display: "inline-block",
                  transform: `translateY(${y}%) scale(${sc})`,
                  opacity: enter === "scale" ? clamp01(tIn * 1.6) : 1,
                  color: isAccent ? C.accent : color,
                }}
              >
                {p}
              </span>
            </span>
          );
        })}
      </span>
    );
    lines[lines.length - 1].push(node);
  });
  return (
    <div style={{ fontFamily: FONT, ...style, textAlign: align }}>
      {lines.map((l, i) => (
        <div key={i} style={{ whiteSpace: "nowrap" }}>
          {l}
        </div>
      ))}
    </div>
  );
};

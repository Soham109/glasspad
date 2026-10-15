import React from "react";
import { useCurrentFrame } from "remotion";
import { C, FONT } from "./theme";
import { clamp, spring, easeIn } from "./motion";

/* Kinetic captions: each word rises out of a mask on a spring, then leaves upward. */
export type Cap = {
  at: number; // first frame
  out: number; // exit starts
  title: string;
  sub?: string;
  x: number;
  y: number; // top of the title
  size?: number;
  align?: "left" | "center";
  dark?: boolean;
  dot?: string; // accent dot before the title (mode captions)
  maxW?: number;
};

const Words: React.FC<{ text: string; f: number; at: number; out: number; stagger: number; style: React.CSSProperties; dot?: string }> = ({ text, f, at, out, stagger, style, dot }) => {
  const words = text.split(" ");
  return (
    <div style={{ display: "flex", flexWrap: "wrap", columnGap: "0.24em", alignItems: "center", ...style }}>
      {dot && (
        <span style={{ display: "inline-block", width: "0.3em", height: "0.3em", borderRadius: "50%", background: dot, marginRight: "0.12em", transform: `scale(${clamp(spring(f, at, 300, 0.7))})`, opacity: 1 - easeIn(clamp((f - out) / 12)) }} />
      )}
      {words.map((w, i) => {
        const p = spring(f, at + i * stagger, 220, 0.86);
        const q = easeIn(clamp((f - out - i * 2) / 14));
        return (
          <span key={i} style={{ display: "inline-block", overflow: "hidden", paddingBottom: "0.12em", marginBottom: "-0.12em" }}>
            <span style={{ display: "inline-block", transform: `translateY(${(1 - p) * 108 - q * 108}%)`, opacity: clamp(p * 3) * (1 - q) }}>{w}</span>
          </span>
        );
      })}
    </div>
  );
};

export const Caption: React.FC<{ c: Cap; frame?: number }> = ({ c, frame }) => {
  const cur = useCurrentFrame();
  const f = frame ?? cur;
  if (f < c.at - 1 || f > c.out + 30) return null;
  const size = c.size ?? 64;
  const ink = c.dark ? C.onDark : C.ink;
  const ink2 = c.dark ? C.onDark2 : C.ink2;
  return (
    <div style={{ position: "absolute", left: c.align === "center" ? 0 : c.x, right: c.align === "center" ? 0 : undefined, top: c.y, width: c.align === "center" ? undefined : c.maxW ?? 760, fontFamily: FONT, color: ink, textAlign: c.align ?? "left" }}>
      <Words text={c.title} f={f} at={c.at} out={c.out} stagger={4} dot={c.dot} style={{ fontSize: size, fontWeight: 600, letterSpacing: "-0.035em", lineHeight: 1.04, justifyContent: c.align === "center" ? "center" : "flex-start" }} />
      {c.sub && (
        <Words text={c.sub} f={f} at={c.at + 10} out={c.out + 3} stagger={2} style={{ marginTop: size * 0.32, fontSize: Math.round(size * 0.44), fontWeight: 500, letterSpacing: "-0.015em", lineHeight: 1.3, color: ink2, justifyContent: c.align === "center" ? "center" : "flex-start" }} />
      )}
    </div>
  );
};

export const Captions: React.FC<{ caps: Cap[] }> = ({ caps }) => (
  <>
    {caps.map((c, i) => (
      <Caption key={i} c={c} />
    ))}
  </>
);

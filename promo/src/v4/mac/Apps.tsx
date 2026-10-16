// The Mac apps the film shows, drawn at screen points. Content is the film's own: fictional
// mail, the Glasspad site in Safari, an edit, a slide deck, a film still. No invented numbers.
import React from "react";
import { Img } from "remotion";
import { SF, SFT, icon } from "../core";
import { Sym, Window } from "./Desktop";

// ---------- The Quiet Coast: the film inside the film (drawn, animated by `t` seconds) ----------
export const Coast: React.FC<{ w: number; h: number; t: number; shot?: number }> = ({ w, h, t, shot = 0 }) => {
  // Two shots of the same evening: wide (0) and closer on the water (1).
  const sunY = shot === 0 ? 0.47 : 0.36;
  const horizon = shot === 0 ? 0.58 : 0.5;
  const drift = t * 6;
  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: w, height: h, overflow: "hidden", background: "#0A0E1C" }}>
      <div style={{ position: "absolute", inset: 0, background: `linear-gradient(180deg, #1B2350 0%, #5B4A86 ${horizon * 55}%, #E9877A ${horizon * 92}%, #FFC48A ${horizon * 100}%, #2B3A6E ${horizon * 100}%, #0E1634 100%)` }} />
      <div style={{ position: "absolute", left: w * (shot === 0 ? 0.62 : 0.45) - h * 0.07, top: h * sunY - h * 0.07, width: h * 0.14, height: h * 0.14, borderRadius: "50%", background: "radial-gradient(circle, #FFF2D6 0%, #FFD39A 45%, rgba(255,190,130,0) 72%)" }} />
      <div style={{ position: "absolute", left: 0, right: 0, top: h * horizon, bottom: 0, overflow: "hidden" }}>
        {Array.from({ length: 18 }).map((_, i) => {
          const y = Math.pow(i / 18, 1.6) * h * (1 - horizon);
          const len = w * (0.05 + 0.12 * (i / 18));
          const x = ((i * 337 + drift * (1 + i * 0.15)) % (w * 0.5)) + w * (shot === 0 ? 0.42 : 0.25);
          return <div key={i} style={{ position: "absolute", left: x, top: y, width: len, height: 1 + i * 0.25, borderRadius: 4, background: "rgba(255,214,170,0.55)", opacity: 0.25 + 0.5 * (1 - i / 18) }} />;
        })}
      </div>
      {shot === 0 ? (
        <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} style={{ position: "absolute", inset: 0 }}>
          <path d={`M0 ${h * 0.5} L${w * 0.08} ${h * 0.46} L${w * 0.16} ${h * 0.49} L${w * 0.24} ${h * 0.53} L${w * 0.31} ${h * 0.6} L${w * 0.36} ${h} L0 ${h} Z`} fill="#0B0F22" />
          <path d={`M${w * 0.82} ${h * 0.56} L${w * 0.9} ${h * 0.52} L${w} ${h * 0.5} L${w} ${h} L${w * 0.78} ${h} Z`} fill="#0D1228" />
        </svg>
      ) : null}
      <div style={{ position: "absolute", inset: 0, background: "radial-gradient(120% 90% at 50% 50%, rgba(0,0,0,0) 60%, rgba(0,0,0,0.45) 100%)" }} />
    </div>
  );
};

// ---------- Mail ----------
const MAIL = [
  ["Mira Okafor", "Prints are ready", "I picked them up from the lab this morning. They look great."],
  ["Jonah Bell", "Friday review", "Moved to ten. The room on the third floor is ours until noon."],
  ["Studio Calendar", "Your week", "Edit on Tuesday, the talk on Thursday, nothing on Sunday."],
  ["Ana Ruiz", "Couch plans", "The Quiet Coast is out. Saturday?"],
  ["Lee Park", "Cable", "Found the projector cable in the second drawer."],
];
export const MailApp: React.FC<{ x: number; y: number; w: number; h: number; active?: boolean; style?: React.CSSProperties }> = ({ x, y, w, h, active = true, style }) => (
  <Window x={x} y={y} w={w} h={h} active={active} bar={0} style={style}>
    <div style={{ position: "absolute", inset: 0, display: "flex", fontFamily: SFT }}>
      <div style={{ width: 200, background: "rgba(236,236,240,0.92)", padding: "52px 12px", fontSize: 13, color: "#3A3A3C" }}>
        <div style={{ position: "absolute", left: 18, top: 18 }}><TrafficInline active={active} /></div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "#8E8E93", margin: "6px 8px" }}>Favourites</div>
        {["Inbox", "VIP", "Flagged", "Sent", "Drafts"].map((n, i) => (
          <div key={n} style={{ display: "flex", alignItems: "center", gap: 8, padding: "6px 8px", borderRadius: 7, background: i === 0 ? "rgba(0,0,0,0.08)" : "transparent", fontWeight: i === 0 ? 600 : 400 }}>
            <Sym name={i === 0 ? "envelope" : i === 2 ? "flag.fill" : i === 3 ? "arrowshape.turn.up.left" : "doc.text"} size={14} color="#0A84FF" />{n}
          </div>
        ))}
      </div>
      <div style={{ width: 300, borderRight: "1px solid rgba(0,0,0,0.08)", background: "#fff" }}>
        <div style={{ height: 52, display: "flex", alignItems: "center", padding: "0 16px", fontSize: 15, fontWeight: 700 }}>Inbox</div>
        {MAIL.map(([from, sub, prev], i) => (
          <div key={i} style={{ padding: "10px 16px", margin: "0 8px", borderRadius: 8, background: i === 0 ? "#0A84FF" : "transparent", color: i === 0 ? "#fff" : "#1D1D1F", borderBottom: i === 0 ? "none" : "1px solid rgba(0,0,0,0.06)" }}>
            <div style={{ display: "flex", fontSize: 13, fontWeight: 600 }}><span style={{ flex: 1 }}>{from}</span><span style={{ fontWeight: 400, opacity: 0.6, fontSize: 12 }}>{["9:12", "8:47", "8:30", "Yesterday", "Yesterday"][i]}</span></div>
            <div style={{ fontSize: 13, marginTop: 2 }}>{sub}</div>
            <div style={{ fontSize: 12.5, marginTop: 2, opacity: i === 0 ? 0.85 : 0.55, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{prev}</div>
          </div>
        ))}
      </div>
      <div style={{ flex: 1, background: "#fff", padding: "64px 36px", color: "#1D1D1F" }}>
        <div style={{ fontSize: 20, fontWeight: 700 }}>Prints are ready</div>
        <div style={{ fontSize: 13, color: "#6E6E73", marginTop: 6 }}>Mira Okafor  ·  Today at 9:12</div>
        <div style={{ fontSize: 14.5, lineHeight: 1.55, marginTop: 22 }}>Morning!<br /><br />I picked them up from the lab this morning. They look great, especially the ones from the coast. I left them on your desk next to the plant.<br /><br />See you at ten,<br />Mira</div>
      </div>
    </div>
  </Window>
);

const TrafficInline: React.FC<{ active?: boolean }> = ({ active = true }) => (
  <div style={{ display: "flex", gap: 8 }}>
    {["#FF5F57", "#FEBC2E", "#28C840"].map((c) => <div key={c} style={{ width: 12, height: 12, borderRadius: 12, background: active ? c : "#D1D1D6" }} />)}
  </div>
);

// ---------- Safari: the Glasspad site ----------
export const SafariApp: React.FC<{ x: number; y: number; w: number; h: number; active?: boolean; style?: React.CSSProperties }> = ({ x, y, w, h, active = true, style }) => (
  <Window x={x} y={y} w={w} h={h} active={active} bar={52} style={style}
    toolbar={<>
      <Sym name="sidebar.left" size={17} color="#6E6E73" />
      <Sym name="chevron.left" size={14} color="#6E6E73" />
      <Sym name="chevron.right" size={14} color="#C7C7CC" />
      <div style={{ flex: 1, display: "flex", justifyContent: "center" }}>
        <div style={{ width: Math.min(460, w * 0.46), height: 32, borderRadius: 10, background: "rgba(0,0,0,0.05)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 13, color: "#3A3A3C", fontWeight: 500 }}>glasspad.sohamaggarwal.com</div>
      </div>
      <Sym name="square.and.arrow.up" size={15} color="#6E6E73" />
      <Sym name="plus" size={15} color="#6E6E73" />
      <Sym name="square.on.square" size={15} color="#6E6E73" />
    </>}>
    <div style={{ position: "absolute", inset: 0, background: "#fff", fontFamily: SF, overflow: "hidden" }}>
      <div style={{ height: 52, display: "flex", alignItems: "center", gap: 26, padding: "0 44px", fontSize: 14, color: "#6E6E73", fontFamily: SFT }}>
        <span style={{ fontWeight: 700, color: "#1D1D1F", fontSize: 16, flex: 1 }}>Glasspad</span>
        <span>Features</span><span>Privacy</span><span>Install</span>
      </div>
      <div style={{ textAlign: "center", marginTop: h * 0.07 }}>
        {/* the site's own hero (web/index.html) */}
        <div style={{ fontSize: Math.min(72, w * 0.056), fontWeight: 700, letterSpacing: "-0.035em", color: "#1D1D1F", lineHeight: 1.05 }}>Glasspad</div>
        <div style={{ fontSize: Math.min(30, w * 0.024), fontWeight: 600, color: "#1D1D1F", marginTop: 10, letterSpacing: "-0.015em" }}>Your iPhone, as a Mac trackpad.</div>
        <div style={{ fontSize: 17, color: "#6E6E73", marginTop: 10, fontFamily: SFT }}>And a keyboard, a Dock, a remote, and buttons for every app.</div>
        <div style={{ display: "inline-block", marginTop: 22, padding: "10px 20px", borderRadius: 999, background: "#1D1D1F", color: "#fff", fontSize: 15, fontWeight: 600, fontFamily: SFT }}>View on GitHub</div>
      </div>
    </div>
  </Window>
);

// ---------- The edit (a Final Cut Pro style timeline; no logos) ----------
export const Clip = { a: "#3F6FD9", b: "#5A86E8", audio: "#2E9E6B" };
/** `cut`: 0..1 how far the blade's gap has opened at the playhead. */
export const EditorApp: React.FC<{ x: number; y: number; w: number; h: number; t: number; cut?: number; playhead?: number; style?: React.CSSProperties }> = ({ x, y, w, h, t, cut = 0, playhead = 0.46, style }) => {
  const tlTop = h * 0.56;
  const tlH = h - tlTop;
  const px = w * playhead;
  const gap = cut * 10;
  const clips = [[0.03, 0.27], [0.27, 0.64], [0.64, 0.9]];
  return (
    <Window x={x} y={y} w={w} h={h} dark bar={44} style={style} title="Field Notes  ·  Edit">
      <div style={{ position: "absolute", inset: 0, background: "#1B1B1D", fontFamily: SFT, color: "rgba(255,255,255,0.8)" }}>
        {/* browser */}
        <div style={{ position: "absolute", left: 10, top: 10, width: w * 0.22, height: tlTop - 20, borderRadius: 8, background: "#232325", padding: 10, display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, alignContent: "start" }}>
          {Array.from({ length: 8 }).map((_, i) => (
            <div key={i} style={{ height: (w * 0.22 - 28) / 2 * 0.56, borderRadius: 4, overflow: "hidden", position: "relative", outline: i === 2 ? "2px solid #F5C542" : "none" }}>
              <Coast w={(w * 0.22 - 28) / 2} h={(w * 0.22 - 28) / 2 * 0.56} t={i * 3} shot={i % 2} />
            </div>
          ))}
        </div>
        {/* viewer */}
        <div style={{ position: "absolute", left: w * 0.22 + 20, top: 10, width: w * 0.52, height: tlTop - 20, borderRadius: 8, background: "#0E0E10", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <div style={{ position: "relative", width: w * 0.48, height: w * 0.48 * 0.5625, overflow: "hidden" }}>
            <Coast w={w * 0.48} h={w * 0.48 * 0.5625} t={t} shot={1} />
          </div>
        </div>
        {/* inspector */}
        <div style={{ position: "absolute", right: 10, top: 10, width: w * 0.24 - 30, height: tlTop - 20, borderRadius: 8, background: "#232325", padding: 14, fontSize: 12 }}>
          {["Video", "Compositing", "Transform", "Crop", "Distort"].map((n, i) => (
            <div key={n} style={{ padding: "8px 0", borderBottom: "1px solid rgba(255,255,255,0.06)", color: i === 0 ? "#fff" : "rgba(255,255,255,0.55)", fontWeight: i === 0 ? 600 : 400 }}>{n}</div>
          ))}
        </div>
        {/* timeline */}
        <div style={{ position: "absolute", left: 0, right: 0, top: tlTop, height: tlH, background: "#151517", borderTop: "1px solid rgba(255,255,255,0.08)" }}>
          {Array.from({ length: 24 }).map((_, i) => <div key={i} style={{ position: "absolute", left: (i / 24) * w, top: 6, width: 1, height: 8, background: "rgba(255,255,255,0.2)" }} />)}
          {clips.map(([a, b], i) => {
            // the blade lands in the middle clip: it becomes two, and they part slightly
            const split = i === 1 && cut > 0;
            const segs = split ? [[a, playhead], [playhead, b]] : [[a, b]];
            return segs.map(([s0, s1], j) => {
              const off = split ? (j === 0 ? -gap / 2 : gap / 2) : 0;
              return (
                <React.Fragment key={`${i}-${j}`}>
                  <div style={{ position: "absolute", left: s0 * w + 1 + off, width: (s1 - s0) * w - 2, top: 30, height: tlH * 0.36, borderRadius: 6, background: i % 2 ? Clip.b : Clip.a, overflow: "hidden", boxShadow: split && j === 1 ? `inset 0 0 0 2px rgba(245,197,66,${cut})` : "none" }}>
                    {Array.from({ length: Math.max(1, Math.floor(((s1 - s0) * w) / 90)) }).map((_, k) => (
                      <div key={k} style={{ position: "absolute", left: k * 90 + 4, top: 18, width: 82, height: tlH * 0.36 - 22, borderRadius: 3, overflow: "hidden", opacity: 0.85 }}>
                        <Coast w={82} h={tlH * 0.36 - 22} t={k * 2 + i} shot={(k + i) % 2} />
                      </div>
                    ))}
                    <div style={{ position: "absolute", left: 6, top: 2, fontSize: 11, fontWeight: 600, color: "rgba(255,255,255,0.92)" }}>{["Arrival", "The water", "Evening"][i]}</div>
                  </div>
                  <div style={{ position: "absolute", left: s0 * w + 1 + off, width: (s1 - s0) * w - 2, top: 36 + tlH * 0.36, height: tlH * 0.16, borderRadius: 5, background: Clip.audio, opacity: 0.9, overflow: "hidden" }}>
                    <svg width={(s1 - s0) * w} height={tlH * 0.16} style={{ position: "absolute", inset: 0 }}>
                      {Array.from({ length: Math.floor(((s1 - s0) * w) / 4) }).map((_, k) => {
                        const v = 0.25 + 0.6 * Math.abs(Math.sin((s0 * w + k * 4) * 0.07) * Math.cos((s0 * w + k * 4) * 0.013));
                        return <rect key={k} x={k * 4} y={(tlH * 0.16 * (1 - v)) / 2} width={2} height={tlH * 0.16 * v} fill="rgba(255,255,255,0.55)" />;
                      })}
                    </svg>
                  </div>
                </React.Fragment>
              );
            });
          })}
          {/* playhead */}
          <div style={{ position: "absolute", left: px - 1, top: 0, width: 2, bottom: 0, background: "#F5F5F7" }} />
          <div style={{ position: "absolute", left: px - 6, top: 0, width: 12, height: 10, background: "#F5F5F7", clipPath: "polygon(0 0, 100% 0, 50% 100%)" }} />
        </div>
      </div>
    </Window>
  );
};

// ---------- Slides (Keynote presenting, full screen) ----------
export const Slide: React.FC<{ w: number; h: number; n: number; t: number }> = ({ w, h, n, t }) => {
  if (n === 0)
    return (
      <div style={{ position: "absolute", inset: 0, width: w, height: h, background: "#0E0E10", fontFamily: SF, color: "#F5F5F7", display: "flex", flexDirection: "column", justifyContent: "center", padding: `0 ${w * 0.08}px` }}>
        <div style={{ fontSize: h * 0.04, color: "rgba(245,245,247,0.55)", fontWeight: 600, letterSpacing: "0.02em" }}>AUTUMN REVIEW</div>
        <div style={{ fontSize: h * 0.13, fontWeight: 700, letterSpacing: "-0.035em", lineHeight: 1.0, marginTop: h * 0.02 }}>Field Notes</div>
        <div style={{ fontSize: h * 0.045, color: "rgba(245,245,247,0.7)", marginTop: h * 0.03 }}>What we learned on the coast</div>
      </div>
    );
  return (
    <div style={{ position: "absolute", inset: 0, width: w, height: h, background: "#0E0E10", overflow: "hidden" }}>
      <Coast w={w} h={h} t={t} shot={0} />
      <div style={{ position: "absolute", left: w * 0.06, bottom: h * 0.09, fontFamily: SF, color: "#fff", fontSize: h * 0.075, fontWeight: 700, letterSpacing: "-0.03em", textShadow: "0 2px 20px rgba(0,0,0,0.35)" }}>Listen first.</div>
    </div>
  );
};

// ---------- Notes, with a pasted photo ----------
export const NotesApp: React.FC<{ x: number; y: number; w: number; h: number; photo?: React.ReactNode; photoIn?: number; style?: React.CSSProperties }> = ({ x, y, w, h, photo, photoIn = 0, style }) => (
  <Window x={x} y={y} w={w} h={h} bar={0} style={style}>
    <div style={{ position: "absolute", inset: 0, display: "flex", fontFamily: SFT }}>
      <div style={{ width: 210, background: "rgba(240,240,242,0.95)", padding: "54px 14px", fontSize: 13, color: "#1D1D1F" }}>
        <div style={{ position: "absolute", left: 18, top: 18 }}><TrafficInline /></div>
        {["Saturday", "Edit notes", "Talk outline", "Groceries"].map((n, i) => (
          <div key={n} style={{ padding: "9px 10px", borderRadius: 8, background: i === 0 ? "#F5C542" : "transparent", marginBottom: 2 }}>
            <div style={{ fontWeight: 600 }}>{n}</div>
            <div style={{ fontSize: 12, opacity: 0.6, marginTop: 1 }}>{["9:41", "Yesterday", "Tuesday", "Monday"][i]}</div>
          </div>
        ))}
      </div>
      <div style={{ flex: 1, background: "#fff", padding: "58px 40px", color: "#1D1D1F" }}>
        <div style={{ fontSize: 24, fontWeight: 700 }}>Saturday</div>
        <div style={{ fontSize: 15, lineHeight: 1.55, marginTop: 12, color: "#3A3A3C" }}>Coffee first, then the market. Bring the prints for Mira.</div>
        <div style={{ marginTop: 18, width: w * 0.42, height: w * 0.42 * 0.62, borderRadius: 10, overflow: "hidden", opacity: photoIn, transform: `scale(${0.96 + 0.04 * photoIn})`, transformOrigin: "0 0", boxShadow: photoIn ? "0 0 0 0.5px rgba(0,0,0,0.12)" : "none" }}>{photo}</div>
      </div>
    </div>
  </Window>
);

/** A web player, full screen, playing The Quiet Coast. */
export const PlayerApp: React.FC<{ w: number; h: number; t: number; shot?: number; controls?: number; skip?: number; search?: string; searchIn?: number }> = ({ w, h, t, shot = 0, controls = 0, skip = 0, search = "", searchIn = 0 }) => (
  <div style={{ position: "absolute", left: 0, top: 0, width: w, height: h, background: "#000", overflow: "hidden", fontFamily: SFT }}>
    <Coast w={w} h={h} t={t} shot={shot} />
    {/* controls */}
    <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: h * 0.22, background: "linear-gradient(180deg, rgba(0,0,0,0), rgba(0,0,0,0.6))", opacity: controls }}>
      <div style={{ position: "absolute", left: w * 0.05, bottom: h * 0.1, fontSize: h * 0.034, color: "#fff", fontWeight: 600 }}>The Quiet Coast</div>
      <div style={{ position: "absolute", left: w * 0.05, right: w * 0.05, bottom: h * 0.06, height: 5, borderRadius: 5, background: "rgba(255,255,255,0.3)" }}>
        <div style={{ width: `${(0.4 + t * 0.002 + skip * 0.0015) * 100}%`, height: "100%", borderRadius: 5, background: "#fff" }} />
      </div>
    </div>
    {/* a skip forward mark */}
    {skip > 0 ? (
      <div style={{ position: "absolute", left: w * 0.72, top: h * 0.42, width: h * 0.16, height: h * 0.16, borderRadius: "50%", background: "rgba(0,0,0,0.35)", backdropFilter: "blur(10px)", display: "flex", alignItems: "center", justifyContent: "center", opacity: Math.min(1, skip * 3) * (skip < 0.7 ? 1 : (1 - skip) / 0.3), transform: `scale(${0.9 + 0.1 * Math.min(1, skip * 4)})` }}>
        <Sym name="goforward.10" size={h * 0.08} color="#fff" />
      </div>
    ) : null}
    {/* the player's search */}
    {searchIn > 0 ? (
      <div style={{ position: "absolute", inset: 0, background: `rgba(0,0,0,${0.55 * searchIn})` }}>
        <div style={{ position: "absolute", left: w * 0.25, top: h * 0.16, width: w * 0.5, height: h * 0.08, borderRadius: h * 0.04, background: "rgba(255,255,255,0.14)", backdropFilter: "blur(20px)", display: "flex", alignItems: "center", gap: h * 0.02, padding: `0 ${h * 0.03}px`, opacity: searchIn, transform: `translateY(${(1 - searchIn) * -20}px)` }}>
          <Sym name="magnifyingglass" size={h * 0.03} color="rgba(255,255,255,0.8)" />
          <span style={{ fontSize: h * 0.035, color: "#fff", fontWeight: 500 }}>{search}<span style={{ opacity: Math.floor(t * 2) % 2 ? 0 : 1, fontWeight: 300 }}>|</span></span>
        </div>
      </div>
    ) : null}
  </div>
);

export const AppIcon: React.FC<{ id: string; size: number; style?: React.CSSProperties }> = ({ id, size, style }) => <Img src={icon(id)} style={{ width: size, height: size, ...style }} />;

// Mac screens used across the film, all in screen points (1512 x 982).
import React from "react";
import { Img } from "remotion";
import { C, FONT } from "../system";
import { Dock, Lines, MenuBar, NotesBody, SH, SW, SafariPage, Win, WordDoc, icon } from "../ui/Mac";

export const WALL = { light: "#D9D6CF", dark: "#232323" };

/** Desktop folders, top right, like a real desk. */
export const Folders: React.FC<{ selected?: number; dark?: boolean }> = ({ selected = -1, dark }) => (
  <>
    {["Projects", "Field notes", "Screenshots"].map((n, i) => (
      <div key={n} style={{ position: "absolute", left: SW - 150, top: 70 + i * 128, width: 120, textAlign: "center", fontFamily: FONT }}>
        <div style={{ margin: "0 auto", width: 84, height: 66, borderRadius: 10, background: selected === i ? C.accent : dark ? "#4A4A4A" : "#9DB7D4", position: "relative" }}>
          <div style={{ position: "absolute", left: 0, top: -9, width: 38, height: 14, borderRadius: "6px 6px 0 0", background: selected === i ? C.accent : dark ? "#4A4A4A" : "#9DB7D4" }} />
        </div>
        <div style={{ marginTop: 8, display: "inline-block", padding: "2px 7px", borderRadius: 5, fontSize: 14, fontWeight: 600, color: selected === i ? "#fff" : dark ? C.paper : C.ink, background: selected === i ? C.accent : "transparent" }}>{n}</div>
      </div>
    ))}
  </>
);

/** The everyday desktop: Word open on a light wallpaper. */
export const Desktop: React.FC<{ app?: string; running?: string[]; word?: boolean; selected?: number; dark?: boolean; dock?: boolean; bounce?: Record<string, number> }> = ({ app = "Finder", running = [], word = false, selected, dark = false, dock = true, bounce }) => (
  <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, background: dark ? WALL.dark : WALL.light, overflow: "hidden" }}>
    <Folders selected={selected} dark={dark} />
    {word ? (
      <Win x={170} y={92} w={900} h={700} title="Field notes.txt" dark={dark}>
        <TextDoc dark={dark} />
      </Win>
    ) : null}
    <MenuBar app={app} dark={dark} menus={app === "TextEdit" ? ["File", "Edit", "Format", "View", "Window"] : undefined} />
    {dock ? <Dock running={running} dark={dark} bounce={bounce} /> : null}
  </div>
);

/** Space two: Safari on the dark wallpaper. */
export const SafariSpace: React.FC<{ dark?: boolean; window?: boolean }> = ({ dark = false, window = true }) => (
  <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, background: WALL.dark, overflow: "hidden" }}>
    {window ? <SafariWin dark={dark} /> : null}
    <MenuBar app="Safari" dark menus={["File", "Edit", "View", "History", "Bookmarks", "Window"]} />
  </div>
);

export const SafariWin: React.FC<{ dark?: boolean; active?: boolean; style?: React.CSSProperties }> = ({ dark = false, active = true, style }) => (
  <Win x={120} y={74} w={1272} h={760} dark={dark} bar={58} active={active} style={style}>
    <SafariPage dark={dark} />
  </Win>
);

export const WordWin: React.FC<{ dark?: boolean; active?: boolean; style?: React.CSSProperties }> = ({ dark = false, active = true, style }) => (
  <Win x={250} y={110} w={940} h={700} title="Field notes.docx" dark={dark} active={active} style={style}>
    <WordDoc dark={dark} />
  </Win>
);

export const TextDoc: React.FC<{ dark?: boolean }> = ({ dark }) => (
  <div style={{ position: "absolute", inset: 0, background: dark ? "#1E1E1E" : "#FFFFFF", padding: "40px 56px" }}>
    <NotesBody dark={dark} size={17} title={28} />
  </div>
);

/** A Mac app icon at any size, from the real icon set. */
export const AppIcon: React.FC<{ id: string; size: number; style?: React.CSSProperties }> = ({ id, size, style }) => <Img src={icon(id)} style={{ width: size, height: size, ...style }} />;

export const Body: React.FC<{ n?: number }> = ({ n = 6 }) => <Lines n={n} />;

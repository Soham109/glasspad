import React from "react";

/* Flat app tiles, one simple glyph each. Shared by the Mac Dock and the phone's Dock mode (web/src/redo.css .app). */
export const APPS: Record<string, { name: string; bg: string; stroke: string; glyph: string; ring?: boolean }> = {
  finder: { name: "Finder", bg: "#4C8DF6", stroke: "#fff", glyph: '<path d="M12 4v16M8 9v2M16 9v2M8.5 15.5c2 1.3 5 1.3 7 0"/>' },
  web: { name: "Safari", bg: "#2F6FE4", stroke: "#fff", glyph: '<circle cx="12" cy="12" r="7.5"/><path d="m15 9-4.2 1.8L9 15l4.2-1.8Z"/>' },
  mail: { name: "Mail", bg: "#3D7BF2", stroke: "#fff", glyph: '<rect x="4.5" y="6.5" width="15" height="11" rx="1.5"/><path d="m5 7.5 7 5 7-5"/>' },
  notes: { name: "Notes", bg: "#F2C94C", stroke: "#6B5310", glyph: '<path d="M7 8h10M7 12h10M7 16h6"/>' },
  cal: { name: "Calendar", bg: "#FBFBF9", stroke: "#E5484D", glyph: '<path d="M7 9h10M8 13h2M12 13h2M8 16h2"/>', ring: true },
  music: { name: "Music", bg: "#EC4F73", stroke: "#fff", glyph: '<path d="M10 17V6.5l8-1.8V15"/><circle cx="8" cy="17" r="2"/><circle cx="16" cy="15" r="2"/>' },
  photos: { name: "Photos", bg: "#FBFBF9", stroke: "#E8930C", glyph: '<circle cx="12" cy="12" r="2.2"/><path d="M12 5v3M12 16v3M5 12h3M16 12h3M7 7l2 2M15 15l2 2M17 7l-2 2M9 15l-2 2"/>', ring: true },
  term: { name: "Terminal", bg: "#2B2B2B", stroke: "#fff", glyph: '<path d="m7 9 3 3-3 3M12.5 15H17"/>' },
  xcode: { name: "Xcode", bg: "#2F6FE4", stroke: "#fff", glyph: '<path d="m13 7 4 4M5 19l8.5-8.5M12 4.5l3-1.5 5 5-1.5 3-1.5-1.5-3 3-4-4 3-3Z"/>' },
};

export const AppTile: React.FC<{ k: string; size: number; style?: React.CSSProperties }> = ({ k, size, style }) => {
  const a = APPS[k];
  return (
    <span style={{ width: size, height: size, borderRadius: size * 0.23, background: a.bg, display: "grid", placeItems: "center", boxShadow: a.ring ? "inset 0 0 0 1px rgba(26,26,26,0.1)" : undefined, flex: "none", ...style }}>
      <svg viewBox="0 0 24 24" width={size * 0.58} height={size * 0.58} fill="none" stroke={a.stroke} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" dangerouslySetInnerHTML={{ __html: a.glyph }} />
    </span>
  );
};

/** Line icon on a 24 grid (web/index.html symbols and web/src/modes.ts glyphs). */
export const Icon: React.FC<{ d: string; size: number; color: string; sw?: number; style?: React.CSSProperties }> = ({ d, size, color, sw = 1.6, style }) => (
  <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke={color} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" style={{ display: "block", flex: "none", ...style }} dangerouslySetInnerHTML={{ __html: d }} />
);

export const GL = {
  trackpad: '<rect x="2.5" y="6" width="19" height="12" rx="3.5"/><circle cx="14.5" cy="11" r="2"/><path d="M8 14.2 12.5 12" opacity=".5"/>',
  dock: '<rect x="3" y="4" width="18" height="16" rx="3.5"/><rect x="6" y="14.5" width="12" height="3" rx="1.5"/>',
  keys: '<rect x="2.5" y="6" width="19" height="12" rx="3"/><path d="M6.5 10h.01M10 10h.01M13.5 10h.01M17 10h.01M8.5 14h7"/>',
  media: '<path d="M5 6.2v11.6a.8.8 0 0 0 1.2.7l9.3-5.8a.8.8 0 0 0 0-1.4L6.2 5.5A.8.8 0 0 0 5 6.2Z"/><path d="M19 6v12"/>',
  deck: '<rect x="3.5" y="3.5" width="7" height="7" rx="2"/><rect x="13.5" y="3.5" width="7" height="7" rx="2"/><rect x="3.5" y="13.5" width="7" height="7" rx="2"/><rect x="13.5" y="13.5" width="7" height="7" rx="2"/>',
  macros: '<path d="M5 19 15 9M14 4v3M18.5 6.5l-2 2M20 10h-3M9.5 5.5l1.5 1.5"/>',
  clipboard: '<path d="M9 4.5H7.5A2.5 2.5 0 0 0 5 7v11.5A2.5 2.5 0 0 0 7.5 21h9a2.5 2.5 0 0 0 2.5-2.5V7a2.5 2.5 0 0 0-2.5-2.5H15"/><rect x="9" y="3" width="6" height="3.2" rx="1.2"/><path d="M8.5 11.5h7M8.5 15h4.5"/>',
  present: '<rect x="3" y="4" width="18" height="12" rx="2.5"/><path d="M12 16v4M8.5 20h7"/><circle cx="14.5" cy="9.5" r="1.4"/>',
  qr: '<rect x="3.5" y="3.5" width="6" height="6" rx="1.5"/><rect x="14.5" y="3.5" width="6" height="6" rx="1.5"/><rect x="3.5" y="14.5" width="6" height="6" rx="1.5"/><path d="M14.5 14.5h2.5v2.5M20.5 14.5v.01M14.5 20.5h.01M18 18v2.5h2.5"/>',
  lock: '<rect x="4.5" y="10.5" width="15" height="10" rx="2.5"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/>',
  home: '<path d="M4 10.5 12 4l8 6.5V19a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 19Z"/><path d="M9 14.2a4.2 4.2 0 0 1 6 0M10.8 16.8a1.7 1.7 0 0 1 2.4 0"/>',
  noaccount: '<circle cx="12" cy="8.5" r="3.5"/><path d="M5 20a7 7 0 0 1 11.2-5.6M4 4l16 16"/>',
  check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  rotate: '<path d="M5 12a7 7 0 1 0 2-5"/><path d="M5 4v4h4"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M12 3v2.5M12 18.5V21M3 12h2.5M18.5 12H21M5.6 5.6l1.8 1.8M16.6 16.6l1.8 1.8M5.6 18.4l1.8-1.8M16.6 7.4l1.8-1.8"/>',
  compass: '<circle cx="12" cy="12" r="8"/><path d="m15.5 8.5-4.8 2.2-2.2 4.8 4.8-2.2Z"/>',
  camera: '<path d="M4 8.5h3l1.6-2h6.8l1.6 2h3V18H4Z"/><circle cx="12" cy="13" r="3"/>',
  moon: '<path d="M19 14.5A7.5 7.5 0 0 1 9.5 5a7.5 7.5 0 1 0 9.5 9.5Z"/>',
  link: '<path d="M10 14a4 4 0 0 0 5.7 0l2.8-2.8a4 4 0 0 0-5.7-5.7L11.5 6.8"/><path d="M14 10a4 4 0 0 0-5.7 0l-2.8 2.8a4 4 0 0 0 5.7 5.7l1.3-1.3"/>',
  hammer: '<path d="m13 7 4 4M5 19l8.5-8.5M12 4.5l3-1.5 5 5-1.5 3-1.5-1.5-3 3-4-4 3-3Z"/>',
  window: '<rect x="4" y="5" width="16" height="14" rx="2.5"/><path d="M4 9h16M9.5 14h5"/>',
  undo: '<path d="M9 7 5 11l4 4"/><path d="M5 11h9a5 5 0 0 1 0 10h-2"/>',
  reader: '<path d="M6 4h9l3 3v13H6Z"/><path d="M9 11h6M9 14h6M9 17h4"/>',
  note: '<rect x="5" y="4" width="14" height="16" rx="2.5"/><path d="M9 9h6M9 12.5h6"/>',
  down: '<circle cx="12" cy="12" r="8"/><path d="M12 8v7M9 12.5l3 3 3-3"/>',
  toMac: '<rect x="3" y="5" width="7" height="13" rx="1.6"/><path d="M13 11.5h7M17 8.5l3 3-3 3"/>',
  fromMac: '<rect x="3" y="5" width="18" height="11" rx="1.6"/><path d="M1.5 19h21M12 8v5M9.5 10.5 12 13l2.5-2.5"/>',
  wave: '<path d="M8.5 8.5a5 5 0 0 0 0 7M15.5 8.5a5 5 0 0 1 0 7M6 6a8.5 8.5 0 0 0 0 12M18 6a8.5 8.5 0 0 1 0 12"/><circle cx="12" cy="12" r="1.2"/>',
  speaker: '<path d="M4 10v4h3l4 3.5v-11L7 10Z"/><path d="M15 9.5a3.5 3.5 0 0 1 0 5"/>',
  sun: '<circle cx="12" cy="12" r="3.5"/><path d="M12 3.5v2M12 18.5v2M3.5 12h2M18.5 12h2M6 6l1.4 1.4M16.6 16.6 18 18M6 18l1.4-1.4M16.6 7.4 18 6"/>',
  play: '<path d="M7 5v14l11-7Z"/>',
  stop: '<rect x="6.5" y="6.5" width="11" height="11" rx="2"/>',
  test: '<path d="M12 3.5 20.5 12 12 20.5 3.5 12Z"/><path d="m9 12 2 2 4-4"/>',
  broom: '<path d="M14 4 9.5 12.5M6 14h8l2 6H4Z"/>',
  search: '<circle cx="11" cy="11" r="6"/><path d="m20 20-4.5-4.5"/>',
  github: "",
};

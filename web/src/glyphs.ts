/* SF Symbol style glyphs on a 24 grid, named after the symbol each button uses in the app.
   Stroked by default; parts with class "f" are filled (the ".fill" symbols). */
export const GLYPH: Record<string, string> = {
  // Pinned essentials
  "camera.viewfinder": '<path d="M4 8.5V6.5A2.5 2.5 0 0 1 6.5 4h2M15.5 4h2A2.5 2.5 0 0 1 20 6.5v2M20 15.5v2a2.5 2.5 0 0 1-2.5 2.5h-2M8.5 20h-2A2.5 2.5 0 0 1 4 17.5v-2"/><path d="M8 10h1.6l1-1.4h2.8l1 1.4H16v5.4H8Z"/><circle cx="12" cy="12.6" r="1.5"/>',
  "lock.fill": '<path class="f" d="M7 10.5h10a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2Z"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5"/>',
  "speaker.slash.fill": '<path class="f" d="M3.5 9.5h3l4.5-4v13l-4.5-4h-3Z"/><path d="m14.5 9.5 5 5M19.5 9.5l-5 5"/>',
  "circle.lefthalf.filled": '<circle cx="12" cy="12" r="8"/><path class="f" d="M12 4a8 8 0 0 0 0 16Z"/>',
  "rectangle.3.group": '<rect x="3.5" y="5" width="7.5" height="6" rx="1.5"/><rect x="13" y="5" width="7.5" height="6" rx="1.5"/><rect x="7.5" y="13" width="9" height="6" rx="1.5"/>',
  "menubar.dock.rectangle": '<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M3.5 8h17"/><rect x="7.5" y="14.5" width="9" height="2.4" rx="1.2"/>',
  // Safari
  "plus.square.on.square": '<rect x="8" y="8" width="12" height="12" rx="2.5"/><path d="M14 11.5v5M11.5 14h5M16 8V6.5A2.5 2.5 0 0 0 13.5 4h-7A2.5 2.5 0 0 0 4 6.5v7A2.5 2.5 0 0 0 6.5 16H8"/>',
  "arrow.uturn.backward": '<path d="M9 6 5 10l4 4"/><path d="M5 10h9.5a4.5 4.5 0 0 1 0 9H11"/>',
  "square.grid.2x2": '<rect x="4" y="4" width="7" height="7" rx="1.8"/><rect x="13" y="4" width="7" height="7" rx="1.8"/><rect x="4" y="13" width="7" height="7" rx="1.8"/><rect x="13" y="13" width="7" height="7" rx="1.8"/>',
  "arrow.clockwise": '<path d="M19 12a7 7 0 1 1-2.05-4.95"/><path d="M19 4.5V8h-3.5"/>',
  "doc.plaintext": '<path d="M6.5 3.5h7l4 4v13h-11Z"/><path d="M13.5 3.5v4h4M9 11.5h6M9 14.5h6M9 17.5h4"/>',
  "link": '<path d="M10 14a4 4 0 0 0 5.7 0l2.8-2.8a4 4 0 0 0-5.7-5.7L11.5 6.8"/><path d="M14 10a4 4 0 0 0-5.7 0l-2.8 2.8a4 4 0 0 0 5.7 5.7l1.3-1.3"/>',
  "chevron.left": '<path d="m14.5 5-7 7 7 7"/>',
  "chevron.right": '<path d="m9.5 5 7 7-7 7"/>',
  // Finder
  "macwindow.badge.plus": '<rect x="3.5" y="5" width="14" height="12" rx="2.5"/><path d="M3.5 8.5h14M19.5 13v6M16.5 16h6"/>',
  "folder.badge.plus": '<path d="M4 7.5A1.5 1.5 0 0 1 5.5 6h4l2 2h7A1.5 1.5 0 0 1 20 9.5v8a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 17.5Z"/><path d="M12 11v5M9.5 13.5h5"/>',
  "arrow.right.circle": '<circle cx="12" cy="12" r="8"/><path d="M8.5 12h7M12.5 9l3 3-3 3"/>',
  "info.circle": '<circle cx="12" cy="12" r="8"/><path d="M12 11v5"/><circle class="f" cx="12" cy="8" r="1"/>',
  "eye": '<path d="M3.5 12S6.5 6.5 12 6.5 20.5 12 20.5 12 17.5 17.5 12 17.5 3.5 12 3.5 12Z"/><circle cx="12" cy="12" r="2.5"/>',
  "eye.slash": '<path d="M3.5 12S6.5 6.5 12 6.5 20.5 12 20.5 12 17.5 17.5 12 17.5 3.5 12 3.5 12Z"/><path d="M5 19 19 5"/>',
  "arrow.down.circle": '<circle cx="12" cy="12" r="8"/><path d="M12 8v7M9 12.5l3 3 3-3"/>',
  "trash": '<path d="M4.5 7h15M9.5 7V5h5v2M6.5 7l1 12.5h9l1-12.5M10 10.5v6M14 10.5v6"/>',
  // Xcode
  "hammer": '<path d="m13 7 4 4M5 19l8.5-8.5M12 4.5l3-1.5 5 5-1.5 3-1.5-1.5-3 3-4-4 3-3Z"/>',
  "play.fill": '<path class="f" d="M7 4.8v14.4a1 1 0 0 0 1.5.9l11.2-7.2a1 1 0 0 0 0-1.7L8.5 3.9A1 1 0 0 0 7 4.8Z"/>',
  "stop.fill": '<rect class="f" x="5.5" y="5.5" width="13" height="13" rx="2.5"/>',
  "checkmark.diamond": '<path d="M12 3.5 20.5 12 12 20.5 3.5 12Z"/><path d="m8.8 12 2.2 2.2 4.2-4.4"/>',
  "magnifyingglass": '<circle cx="10.5" cy="10.5" r="6"/><path d="m15 15 5 5"/>',
  "sidebar.left": '<rect x="3.5" y="5" width="17" height="14" rx="2.5"/><path d="M9.5 5v14M5.8 8.5h1.6M5.8 11h1.6"/>',
  "rectangle.bottomthird.inset.filled": '<rect x="3.5" y="5" width="17" height="14" rx="2.5"/><rect class="f" x="5.5" y="13" width="13" height="4" rx="1"/>',
  // Figma
  "cursorarrow": '<path d="M6 3.5v15l4-3.8 2.6 5.8 2.6-1.1-2.6-5.7H18Z"/>',
  "number": '<path d="M9.5 4 8 20M16 4l-1.5 16M4.5 9h15M4 15h15"/>',
  "rectangle": '<rect x="3.5" y="6" width="17" height="12" rx="2.5"/>',
  "textformat": '<path d="M3.5 18 8 6l4.5 12M5.2 14h5.6M15 11.5a2.7 2.7 0 1 1 0 5.4 2.7 2.7 0 0 1 0-5.4ZM17.7 10.5v7.5"/>',
  "pencil.tip": '<path d="M12 3.5 17 14l-5 6.5L7 14Z"/><path d="M12 3.5v8"/><circle cx="12" cy="12.5" r="1.2"/>',
  "bubble.left": '<path d="M12 4.5c4.7 0 8 2.9 8 6.6s-3.3 6.6-8 6.6c-1 0-2-.1-2.9-.4L5 19.5l.9-3.6C4.7 14.7 4 13 4 11.1 4 7.4 7.3 4.5 12 4.5Z"/>',
  "arrow.up.left.and.arrow.down.right": '<path d="M5 10V5h5M5 5l5.5 5.5M19 14v5h-5M19 19l-5.5-5.5"/>',
  "square.on.square": '<rect x="8.5" y="8.5" width="11" height="11" rx="2.5"/><path d="M15.5 8.5V7A2.5 2.5 0 0 0 13 4.5H7A2.5 2.5 0 0 0 4.5 7v6A2.5 2.5 0 0 0 7 15.5h1.5"/>',
  // Music
  "playpause.fill": '<path class="f" d="M3.5 6v12a.8.8 0 0 0 1.2.7l8-6a.8.8 0 0 0 0-1.3l-8-6A.8.8 0 0 0 3.5 6Z"/><rect class="f" x="15" y="5.5" width="2.3" height="13" rx="1"/><rect class="f" x="19" y="5.5" width="2.3" height="13" rx="1"/>',
  "backward.fill": '<path class="f" d="M11.5 6.2v11.6a.7.7 0 0 1-1.1.6L2.8 12.6a.7.7 0 0 1 0-1.2l7.6-5.8a.7.7 0 0 1 1.1.6ZM21 6.2v11.6a.7.7 0 0 1-1.1.6l-7.6-5.8a.7.7 0 0 1 0-1.2l7.6-5.8a.7.7 0 0 1 1.1.6Z"/>',
  "forward.fill": '<path class="f" d="M12.5 6.2v11.6a.7.7 0 0 0 1.1.6l7.6-5.8a.7.7 0 0 0 0-1.2l-7.6-5.8a.7.7 0 0 0-1.1.6ZM3 6.2v11.6a.7.7 0 0 0 1.1.6l7.6-5.8a.7.7 0 0 0 0-1.2L4.1 5.6a.7.7 0 0 0-1.1.6Z"/>',
  "speaker.minus": '<path d="M3.5 9.5h3l4.5-4v13l-4.5-4h-3Z"/><path d="M15 12h5.5"/>',
  "speaker.plus": '<path d="M3.5 9.5h3l4.5-4v13l-4.5-4h-3Z"/><path d="M15 12h5.5M17.75 9.25v5.5"/>',
  "music.note.list": '<path d="M4 6h9M4 10h9M4 14h5"/><path d="M17 16.5V5l3.5-1"/><circle cx="15" cy="16.5" r="2"/>',
  // Keynote
  "plus.rectangle": '<rect x="3.5" y="5.5" width="17" height="13" rx="2.5"/><path d="M12 9v6M9 12h6"/>',
  "square.split.2x1": '<rect x="3.5" y="5.5" width="17" height="13" rx="2.5"/><path d="M12 5.5v13"/>',
  "sidebar.right": '<rect x="3.5" y="5" width="17" height="14" rx="2.5"/><path d="M14.5 5v14M16.6 8.5h1.6M16.6 11h1.6"/>',
};
export const glyph = (name: string) => `<svg viewBox="0 0 24 24" aria-hidden="true">${GLYPH[name] ?? ""}</svg>`;

/* Pinned extras: Mac controls and website logos (simple drawn marks, not official artwork). */
GLYPH["moon.fill"] = '<path class="f" d="M19 14.5A7.5 7.5 0 0 1 9.5 5a7.5 7.5 0 1 0 9.5 9.5Z"/>';
GLYPH["sun.max"] = '<circle cx="12" cy="12" r="3.6"/><path d="M12 4v2M12 18v2M4 12h2M18 12h2M6.3 6.3l1.4 1.4M16.3 16.3l1.4 1.4M17.7 6.3l-1.4 1.4M7.7 16.3l-1.4 1.4"/>';
GLYPH["cup.and.saucer"] = '<path d="M5 9h11v5a4 4 0 0 1-4 4H9a4 4 0 0 1-4-4Z"/><path d="M16 10h1.5a2 2 0 0 1 0 4H16M8 4v2M11 4v2"/>';
GLYPH["logo.youtube"] = '<rect x="2.5" y="5.5" width="19" height="13" rx="4" fill="#FF3B30" stroke="none"/><path d="M10 9.2v5.6l5-2.8Z" fill="#fff" stroke="none"/>';
GLYPH["logo.github"] = '<circle cx="12" cy="12" r="9.5" fill="#1A1A1A" stroke="none"/><path d="M9.2 18.5v-2.2c-2.2.5-2.7-1-2.7-1M14.8 18.5v-2.7c0-.8-.2-1.3-.6-1.7 2-.2 3.6-1 3.6-3.6 0-.8-.3-1.5-.8-2 .2-.6.2-1.4-.1-2 0 0-.7-.2-2.1.8a7 7 0 0 0-3.6 0C9.2 6.3 8.5 6.5 8.5 6.5c-.3.6-.3 1.4-.1 2-.5.5-.8 1.200-.8 2 0 2.600 1.600 3.400 3.600 3.600-.4.400-.6.900-.6 1.700v2.700" stroke="#fff" stroke-width="1.3"/>';
GLYPH["logo.netflix"] = '<rect x="3.5" y="3.5" width="17" height="17" rx="4" fill="#E50914" stroke="none"/><path d="M9.2 17V7l5.6 10V7" stroke="#fff" stroke-width="2.2"/>';
GLYPH["logo.spotify"] = '<circle cx="12" cy="12" r="9.5" fill="#1DB954" stroke="none"/><path d="M7.2 10.2c3.2-1 6.600-.7 9.600 1M7.700 13c2.700-.7 5.300-.5 7.700.9M8.300 15.600c2.100-.5 4-.3 5.800.7" stroke="#fff" stroke-width="1.500"/>';

/** Pinned starts with everyday Mac controls and a couple of websites (colours from the app's Library). */
export const PINNED: [string, string, string][] = [
  ["Do Not Disturb", "moon.fill", "#5E5CE6"],
  ["Split Screen", "square.split.2x1", "#30B0C7"],
  ["Night Shift", "sun.max", "#FF9F0A"],
  ["Keep Awake", "cup.and.saucer", "#8E5A3C"],
  ["Screenshot", "camera.viewfinder", "#0A84FF"],
  ["YouTube", "logo.youtube", "#FF3B30"],
  ["GitHub", "logo.github", "#1A1A1A"],
];

/* Scenes, Displays and the cards below Actions */
GLYPH["scissors"] = '<circle cx="6.5" cy="7" r="2.5"/><circle cx="6.5" cy="17" r="2.5"/><path d="M8.6 8.4 19 16.5M8.6 15.6 19 7.5"/>';
GLYPH["magnet"] = '<path d="M6 4.5v7a6 6 0 0 0 12 0v-7h-4v7a2 2 0 0 1-4 0v-7Z"/><path d="M6 8h4M14 8h4"/>';
GLYPH["arrow.right.to.line"] = '<path d="M4 12h11M11 8l4 4-4 4M19.5 5v14"/>';
GLYPH["arrow.left.to.line"] = '<path d="M20 12H9M13 8l-4 4 4 4M4.5 5v14"/>';
GLYPH["globe"] = '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.4 2.4 3.5 5.2 3.5 8.5s-1.1 6.1-3.5 8.5M12 3.5C9.6 5.9 8.5 8.7 8.5 12s1.1 6.1 3.5 8.5"/>';
GLYPH["square.stack.3d.up.fill"] = '<path class="f" d="m12 3 8 4-8 4-8-4Z"/><path d="m4 11.5 8 4 8-4M4 15.5l8 4 8-4"/>';
GLYPH["rectangle.lefthalf.filled"] = '<rect x="3.5" y="5.5" width="17" height="13" rx="2.5"/><path class="f" d="M6 5.5h6v13H6a2.5 2.5 0 0 1-2.5-2.5V8A2.5 2.5 0 0 1 6 5.5Z"/>';
GLYPH["rectangle.righthalf.filled"] = '<rect x="3.5" y="5.5" width="17" height="13" rx="2.5"/><path class="f" d="M12 5.5h6A2.5 2.5 0 0 1 20.5 8v8a2.5 2.5 0 0 1-2.5 2.5h-6Z"/>';
GLYPH["macwindow"] = '<rect x="3.5" y="5" width="17" height="14" rx="2.5"/><path d="M3.5 8.5h17"/>';
GLYPH["rectangle.on.rectangle"] = '<rect x="7.5" y="8" width="13" height="10" rx="2"/><path d="M16.5 8V6.5a2 2 0 0 0-2-2h-9a2 2 0 0 0-2 2V13a2 2 0 0 0 2 2h2"/>';
GLYPH["wand.and.stars"] = '<path d="m4 20 11-11M13 7l4 4"/><path d="M18 3v3M16.5 4.5h3M20 9v2M19 10h2M9.5 3.5v2M8.5 4.5h2"/>';
GLYPH["record.circle"] = '<circle cx="12" cy="12" r="8.5"/><circle class="f" cx="12" cy="12" r="4"/>';
GLYPH["checkmark"] = '<path d="m5 12.5 4.5 4.5L19 7.5"/>';
GLYPH["plus"] = '<path d="M12 5.5v13M5.5 12h13"/>';
GLYPH["display"] = '<rect x="3" y="4.5" width="18" height="12" rx="2"/><path d="M9 20h6M12 16.5V20"/>';
GLYPH["laptopcomputer"] = '<rect x="5" y="5.5" width="14" height="10" rx="1.5"/><path d="M2.5 18.5h19"/>';
GLYPH["doc.on.clipboard"] = '<rect x="8" y="7" width="11" height="13" rx="2"/><path d="M8 17H6.5A1.5 1.5 0 0 1 5 15.5V5.5A1.5 1.5 0 0 1 6.5 4h7A1.5 1.5 0 0 1 15 5.5V7"/>';
GLYPH["square.and.arrow.down"] = '<path d="M8 9.5H6.5A1.5 1.5 0 0 0 5 11v7.5A1.5 1.5 0 0 0 6.5 20h11a1.5 1.5 0 0 0 1.5-1.5V11a1.5 1.5 0 0 0-1.5-1.5H16M12 3.5v11M8.5 11l3.5 3.5 3.5-3.5"/>';
GLYPH["square.and.arrow.up"] = '<path d="M8 9.5H6.5A1.5 1.5 0 0 0 5 11v7.5A1.5 1.5 0 0 0 6.5 20h11a1.5 1.5 0 0 0 1.5-1.5V11a1.5 1.5 0 0 0-1.5-1.5H16M12 14.5v-11M8.5 7 12 3.5 15.5 7"/>';
GLYPH["logo.wikipedia"] = '<rect x="2.5" y="2.5" width="19" height="19" rx="4.5" fill="#fff" stroke="rgba(26,26,26,.12)"/><path d="m5.5 8 3 9 3.5-8 3.5 8 3-9" stroke="#1A1A1A" stroke-width="1.5"/>';
GLYPH["arrow.counterclockwise"] = '<path d="M5 12a7 7 0 1 0 2.05-4.95"/><path d="M5 4.5V8h3.5"/>';
GLYPH["dot.radiowaves"] = '<circle class="f" cx="12" cy="12" r="1.8"/><path d="M8.6 8.6a4.8 4.8 0 0 0 0 6.8M15.4 8.6a4.8 4.8 0 0 1 0 6.8M6 6a8.5 8.5 0 0 0 0 12M18 6a8.5 8.5 0 0 1 0 12"/>';
GLYPH["chevron.left"] = '<path d="m14.5 5-7 7 7 7"/>';
GLYPH["sun.max.fill"] = '<circle class="f" cx="12" cy="12" r="4"/><path d="M12 3v2.2M12 18.8V21M3 12h2.2M18.8 12H21M5.6 5.6l1.6 1.6M16.8 16.8l1.6 1.6M18.4 5.6l-1.6 1.6M7.2 16.8l-1.6 1.6"/>';
GLYPH["pause.fill"] = '<rect class="f" x="6.5" y="5" width="4" height="14" rx="1.2"/><rect class="f" x="13.5" y="5" width="4" height="14" rx="1.2"/>';

/* Flat app tiles: one colour, one simple glyph. Stand-ins for real Mac app icons. */
export const APPS: Record<string, [name: string, glyph: string]> = {
  finder: ["Finder", '<path d="M12 4v16M8 9v2M16 9v2M8.5 15.5c2 1.3 5 1.3 7 0"/>'],
  web: ["Safari", '<circle cx="12" cy="12" r="7.5"/><path d="m15 9-4.2 1.8L9 15l4.2-1.8Z"/>'],
  mail: ["Mail", '<rect x="4.5" y="6.5" width="15" height="11" rx="1.5"/><path d="m5 7.5 7 5 7-5"/>'],
  msg: ["Messages", '<path d="M12 5.5c4.4 0 7.5 2.7 7.5 6s-3.1 6-7.5 6c-.9 0-1.8-.1-2.6-.4L5.5 18.5l1.1-3.1C5.3 14.3 4.5 13 4.5 11.5c0-3.3 3.1-6 7.5-6Z"/>'],
  cal: ["Calendar", '<path d="M7 9h10M8 13h2M12 13h2M16 13h.01M8 16h2M12 16h2"/>'],
  notes: ["Notes", '<path d="M7 8h10M7 12h10M7 16h6"/>'],
  rem: ["Reminders", '<path d="M10 8h8M10 12h8M10 16h8"/><circle cx="6.5" cy="8" r=".6"/><circle cx="6.5" cy="12" r=".6"/><circle cx="6.5" cy="16" r=".6"/>'],
  music: ["Music", '<path d="M10 17V6.5l8-1.8V15"/><circle cx="8" cy="17" r="2"/><circle cx="16" cy="15" r="2"/>'],
  photos: ["Photos", '<circle cx="12" cy="12" r="2.2"/><path d="M12 5v3M12 16v3M5 12h3M16 12h3M7 7l2 2M15 15l2 2M17 7l-2 2M9 15l-2 2"/>'],
  xcode: ["Xcode", '<path d="m13 7 4 4M5.5 18.5 13.5 10.5M12 4.5l3-1.5 5 5-1.5 3-1.5-1.5-3 3-4-4 3-3Z"/>'],
  term: ["Terminal", '<path d="m7 9 3 3-3 3M12.5 15H17"/>'],
  store: ["App Store", '<path d="M9.5 6.5 15.5 17M14.5 6.5 8.5 17M6 14h12"/>'],
  set: ["System Settings", '<circle cx="12" cy="12" r="3"/><path d="M12 4.5v2.2M12 17.3v2.2M4.5 12h2.2M17.3 12h2.2M6.7 6.7l1.6 1.6M15.7 15.7l1.6 1.6M17.3 6.7l-1.6 1.6M8.3 15.7l-1.6 1.6"/>'],
  prev: ["Preview", '<circle cx="11" cy="11" r="5"/><path d="m15 15 4 4"/>'],
  text: ["TextEdit", '<path d="M7 6h10M7 10h10M7 14h10M7 18h6"/>'],
  figma: ["Figma", '<rect x="8" y="3.5" width="4" height="5" rx="2"/><rect x="12" y="3.5" width="4" height="5" rx="2"/><rect x="8" y="8.5" width="4" height="5" rx="2"/><circle cx="14" cy="11" r="2"/><path d="M8 15.5a2 2 0 0 0 4 0v-2h-2a2 2 0 0 0-2 2Z"/>'],
  keynote: ["Keynote", '<rect x="5" y="5" width="14" height="9" rx="1.5"/><path d="M12 14v5M9 19h6"/>'],
  maps: ["Maps", '<path d="M5 7l4.5-2 5 2 4.5-2v12l-4.5 2-5-2L5 19Z"/><path d="M9.5 5v12M14.5 7v12"/>'],
};
export const appIcon = (k: string, cls = "") => `<span class="app a-${k} ${cls}"><svg viewBox="0 0 24 24">${APPS[k][1]}</svg></span>`;

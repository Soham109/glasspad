/* Line icons drawn for this site on a 24 point grid, stroked with the text colour.
   `icon(key)` returns an inline, decorative <svg>. */

export const ICONS: Record<string, string> = {
  // features
  trackpad: '<rect x="3" y="5" width="18" height="14" rx="3.5"/><circle cx="14.5" cy="11" r="1.6" fill="currentColor" stroke="none"/><path d="M8 14.5 13 11.6" opacity=".45"/>',
  keyboard: '<rect x="2.5" y="6" width="19" height="12" rx="3"/><path d="M6.5 10h.01M10 10h.01M13.5 10h.01M17 10h.01M8.5 14h7"/>',
  remote: '<rect x="7" y="2.5" width="10" height="19" rx="5"/><circle cx="12" cy="8.5" r="2.6"/><path d="M12 14.5v.01M12 17.5v.01"/>',
  actions: '<rect x="4" y="4" width="6.5" height="6.5" rx="2"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="2"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="2"/><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="2"/>',
  split: '<rect x="3" y="5" width="18" height="14" rx="3"/><path d="M12 5v14"/><path d="M6 9h3M15 9h3" opacity=".45"/>',
  displays: '<rect x="2.5" y="4" width="13" height="9.5" rx="2"/><path d="M7 17h4M9 13.5V17"/><rect x="17.5" y="7" width="4" height="10" rx="1.2"/>',
  // benefits and steps
  haptic: '<circle cx="12" cy="12" r="2.6"/><path d="M7.8 7.8a6 6 0 0 0 0 8.4M16.2 7.8a6 6 0 0 1 0 8.4M5 5a10 10 0 0 0 0 14M19 5a10 10 0 0 1 0 14"/>',
  pinch: '<circle cx="8" cy="8" r="2"/><circle cx="16" cy="16" r="2"/><path d="m10.5 10.5 3 3M4 12V4h8M20 12v8h-8"/>',
  spaces: '<rect x="2.5" y="6" width="5" height="12" rx="1.5"/><rect x="9.5" y="6" width="5" height="12" rx="1.5"/><rect x="16.5" y="6" width="5" height="12" rx="1.5"/>',
  sliders: '<path d="M4 7h9M17 7h3M4 17h3M11 17h9"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="17" r="2"/>',
  mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/>',
  command: '<path d="M9 9V6.5A2.5 2.5 0 1 0 6.5 9H17.5A2.5 2.5 0 1 0 15 6.5V17.5A2.5 2.5 0 1 0 17.5 15H6.5A2.5 2.5 0 1 0 9 17.5Z"/>',
  clipboard: '<path d="M9 4.5H7.5A2.5 2.5 0 0 0 5 7v11.5A2.5 2.5 0 0 0 7.5 21h9a2.5 2.5 0 0 0 2.5-2.5V7a2.5 2.5 0 0 0-2.5-2.5H15"/><rect x="9" y="3" width="6" height="3.2" rx="1.2"/><path d="M8.5 11.5h7M8.5 15h4.5"/>',
  globe: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.5 2.6 3.6 5.4 3.6 8.5s-1.1 5.9-3.6 8.5c-2.5-2.6-3.6-5.4-3.6-8.5s1.1-5.9 3.6-8.5Z"/>',
  layout: '<rect x="3" y="5" width="18" height="14" rx="3"/><path d="M13 5v14M13 12h8"/>',
  play: '<path d="M7 5.5v13a1 1 0 0 0 1.5.86l10.4-6.5a1 1 0 0 0 0-1.72L8.5 4.64A1 1 0 0 0 7 5.5Z"/>',
  volume: '<path d="M4 9.5h3l4.5-4v13l-4.5-4H4Z"/><path d="M15 9a4 4 0 0 1 0 6M17.5 6.5a7.5 7.5 0 0 1 0 11"/>',
  captions: '<rect x="3" y="5.5" width="18" height="13" rx="3"/><path d="M7 11h4M13 11h4M7 14.5h6M15 14.5h2"/>',
  search: '<circle cx="11" cy="11" r="6"/><path d="m15.5 15.5 4 4"/>',
  moon: '<path d="M19 14.5A7.5 7.5 0 0 1 9.5 5a7.5 7.5 0 1 0 9.5 9.5Z"/>',
  folder: '<path d="M3.5 7.5A2 2 0 0 1 5.5 5.5h4l2 2h7a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2Z"/>',
  record: '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="3.2" fill="currentColor" stroke="none"/>',
  shortcuts: '<path d="m12 3.5 8.5 4.5-8.5 4.5L3.5 8Z"/><path d="m3.5 12 8.5 4.5 8.5-4.5M3.5 16l8.5 4.5 8.5-4.5"/>',
  halves: '<rect x="3" y="5" width="18" height="14" rx="3"/><path d="M12 5v14"/><path d="M3 8a3 3 0 0 1 3-3h6v14H6a3 3 0 0 1-3-3Z" fill="currentColor" opacity=".18" stroke="none"/>',
  quarters: '<rect x="3" y="5" width="18" height="14" rx="3"/><path d="M12 5v14M3 12h18"/>',
  fullscreen: '<path d="M4 9V5h4M20 9V5h-4M4 15v4h4M20 15v4h-4"/>',
  display: '<rect x="3" y="4" width="18" height="12" rx="2.5"/><path d="M9 20h6M12 16v4"/>',
  sun: '<circle cx="12" cy="12" r="3.5"/><path d="M12 3.5v2M12 18.5v2M3.5 12h2M18.5 12h2M6 6l1.4 1.4M16.6 16.6 18 18M18 6l-1.4 1.4M7.4 16.6 6 18"/>',
  undo: '<path d="M9 7 5 11l4 4"/><path d="M5 11h9a5 5 0 0 1 0 10h-2"/>',
  lock: '<rect x="5" y="10.5" width="14" height="9.5" rx="2.5"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5"/>',
  wifi: '<path d="M2.5 9.5a14 14 0 0 1 19 0M5.5 12.8a9.5 9.5 0 0 1 13 0M8.6 16a5 5 0 0 1 6.8 0"/><circle cx="12" cy="19" r="1.2" fill="currentColor" stroke="none"/>',
  free: '<path d="M20 12.5 12.5 20a1.5 1.5 0 0 1-2.1 0L4 13.6V4h9.6l6.4 6.4a1.5 1.5 0 0 1 0 2.1Z"/><circle cx="8.5" cy="8.5" r="1.4"/>',
  code: '<path d="m8.5 7-5 5 5 5M15.5 7l5 5-5 5"/>',
  hand: '<path d="M8 13V6.5a1.5 1.5 0 0 1 3 0V12M11 11V5a1.5 1.5 0 0 1 3 0v6M14 11V6.5a1.5 1.5 0 0 1 3 0V14a6 6 0 0 1-6 6h-.5a5 5 0 0 1-4.2-2.3L4.5 14.5a1.4 1.4 0 0 1 2.2-1.7L8 14"/>',
  menu: '<circle cx="12" cy="12" r="8.5"/><path d="M8.5 10.5 12 14l3.5-3.5"/>',
  couch: '<path d="M5 11V8.5A2.5 2.5 0 0 1 7.5 6h9A2.5 2.5 0 0 1 19 8.5V11"/><path d="M3 13a2 2 0 0 1 4 0v1h10v-1a2 2 0 0 1 4 0v4.5H3ZM5 17.5V19M19 17.5V19"/>',
  pin: '<path d="M9 4h6M10 4v6l-3 4h10l-3-4V4M12 14v6"/>',
  compare: '<rect x="3" y="4.5" width="7.5" height="15" rx="2"/><rect x="13.5" y="4.5" width="7.5" height="15" rx="2"/><path d="M5.5 9h2.5M16 9h2.5M5.5 12.5h2.5M16 12.5h2.5"/>',
  // marks
  check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  cross: '<path d="m7 7 10 10M17 7 7 17"/>',
  part: '<path d="M6 12h12"/>',
  arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  chevron: '<path d="m6 9.5 6 6 6-6"/>',
  copy: '<rect x="8.5" y="8.5" width="11" height="11" rx="2.5"/><path d="M15.5 8.5V6.5A2 2 0 0 0 13.5 4.5h-7a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h2"/>',
};

export const icon = (key: string, size = 24, cls = "ico") => {
  const body = ICONS[key];
  if (!body) throw new Error(`site: no icon "${key}" in site/icons.ts`);
  return `<svg class="${cls}" width="${size}" height="${size}" viewBox="0 0 24 24" aria-hidden="true" focusable="false">${body}</svg>`;
};

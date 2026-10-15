// Voiceover script. `f` is the start frame at 60 fps (timeline.ts places each line). No dashes anywhere.
// Line ids are stable: the timeline and captions look lines up by id.
export type VoLine = { id: string; text: string };
export const VO_TEXT: VoLine[] = [
  { id: "intro", text: "Glasspad turns your iPhone into a wireless trackpad for your Mac." },
  { id: "lay", text: "Lay it down, and touch the glass." },
  { id: "move", text: "The pointer follows your finger." },
  { id: "click", text: "Tap to click, and feel a small tap back." },
  { id: "scroll", text: "Two fingers scroll." },
  { id: "speed", text: "Touches reach your Mac hundreds of times a second." },
  { id: "spaces", text: "Three fingers slide between Spaces, and the screen follows your hand." },
  { id: "mission", text: "Swipe up for Mission Control." },
  { id: "settings", text: "It follows your Mac's own trackpad settings, so you never set anything up twice." },
  { id: "menu", text: "Touch the top, and it becomes something else." },
  { id: "dock", text: "Your Dock." },
  { id: "keys", text: "A keyboard." },
  { id: "media", text: "Now playing." },
  { id: "deck", text: "Buttons that act on your Mac." },
  { id: "macros", text: "Buttons for whichever app is in front." },
  { id: "clipboard", text: "Your clipboard, both ways." },
  { id: "present", text: "And a clicker for your slides." },
  { id: "pair", text: "Pair once, with a QR code." },
  { id: "encrypt", text: "Every message is encrypted." },
  { id: "local", text: "It stays on your network, with no accounts." },
  { id: "end", text: "Glasspad. Free, and open source." },
];
export const VO_MODEL = "eleven_multilingual_v2";
export const VO_SETTINGS = { stability: 0.5, similarity_boost: 0.8, style: 0.05, use_speaker_boost: true, speed: 0.92 };
// Chosen from four line-1 samples (River, Eric, Daniel, Sarah): warmest low end, least sibilance, steady level, no mid-line pauses.
export const VO_VOICE = { id: "cjVigY5qzO86Huf0OWal", name: "Eric (Smooth, Trustworthy)" };

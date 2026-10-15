import { Cap } from "../Captions";
import { S, VO_AT } from "../timeline";

// Captions enter with their VO line (verify-sync checks this). Left column beside the wide shot, lower third elsewhere.
const LX = 120, LY = 884, CY = 420;
export const FILM_CAPS: Cap[] = [
  { at: VO_AT.lay + 8, out: 664, title: "Lay it by your Mac.", sub: "Touch the glass.", x: LX, y: CY, size: 76, maxW: 520 },
  { at: VO_AT.move - 10, out: 786, title: "Move.", sub: "The pointer follows your finger.", x: LX, y: LY },
  { at: VO_AT.click, out: 994, title: "Click.", sub: "Tap anywhere on the glass.", x: LX, y: CY, size: 76, maxW: 520 },
  { at: 1040, out: 1100, title: "Feel it.", sub: "A small tap answers every click.", x: LX, y: LY },
  { at: VO_AT.scroll, out: S.speed - 22, title: "Scroll.", sub: "Two fingers, with momentum.", x: LX, y: LY },
  { at: VO_AT.spaces, out: S.mission - 22, title: "Spaces.", sub: "Three fingers, and the screen follows your hand.", x: LX, y: CY, size: 76, maxW: 520 },
  { at: VO_AT.mission, out: S.settings - 22, title: "Mission Control.", sub: "Three fingers up.", x: LX, y: LY },
];

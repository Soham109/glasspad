import { macGeom } from "../devices/Mac";
import { phoneGeom, PHONE_ASPECT } from "../devices/Phone";

/** Where the MacBook and the phone sit in a scene's world. Phone is landscape, lying on the desk. */
export type Layout = { W: number; H: number; macX: number; macY: number; L: number; deskY: number; phoneCx: number; phoneCy: number; phoneLong: number };
export const FILM_LAYOUT: Layout = { W: 1920, H: 1080, macX: 530, macY: 60, L: 860, deskY: 60 + 860 / 1.49, phoneCx: 960, phoneCy: 870, phoneLong: 520 };
export const TEASER_LAYOUT: Layout = { W: 1080, H: 1920, macX: 90, macY: 430, L: 900, deskY: 430 + 900 / 1.49, phoneCx: 540, phoneCy: 1390, phoneLong: 640 };

export const geom = (l: Layout) => {
  const m = macGeom(l.L);
  const pw = l.phoneLong / PHONE_ASPECT; // short side
  const p = phoneGeom(pw);
  // landscape screen rect in world (at tilt 0)
  const scr = { x: l.phoneCx - p.sh / 2, y: l.phoneCy - p.sw / 2, w: p.sh, h: p.sw, s: p.s, r: 0.127 * pw };
  const disp = { x: l.macX + m.dx, y: l.macY + m.dy, w: m.dw, h: m.dh, s: m.s };
  return { m, p, pw, scr, disp };
};
/** landscape phone point -> world (tilt 0) */
export const phoneToWorld = (l: Layout, x: number, y: number): [number, number] => {
  const g = geom(l);
  return [g.scr.x + x * g.scr.s, g.scr.y + y * g.scr.s];
};
/** display point -> world */
export const dispToWorld = (l: Layout, x: number, y: number): [number, number] => {
  const g = geom(l);
  return [g.disp.x + x * g.disp.s, g.disp.y + y * g.disp.s];
};

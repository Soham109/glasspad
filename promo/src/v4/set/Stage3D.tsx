// A small 3D stage in CSS: a camera (position, yaw, pitch, field of view, focus distance) and
// objects placed in world units (1 unit = 1 px at the focus plane when the camera is at the
// default distance). Depth of field: each object is softened by how far it sits from the
// focus distance, the way a lens would (circle of confusion grows with |d - focus| / d).
import React from "react";
import { AbsoluteFill } from "remotion";

export type Cam = { x: number; y: number; z: number; yaw: number; pitch: number; fov?: number; focus?: number; aperture?: number; roll?: number };

const rad = (d: number) => (d * Math.PI) / 180;
export const perspectiveFor = (fov: number, h = 1080) => h / 2 / Math.tan(rad(fov) / 2);

/** Camera space of a world point: x right, y down, d = distance in front of the camera. */
export const toCam = (cam: Cam, p: { x: number; y: number; z: number }) => {
  let x = p.x - cam.x, y = p.y - cam.y, z = p.z - cam.z;
  // same order as the CSS: rotateY(yaw) then rotateX(pitch) (CSS applies right to left)
  const cy = Math.cos(rad(cam.yaw)), sy = Math.sin(rad(cam.yaw));
  [x, z] = [x * cy + z * sy, -x * sy + z * cy];
  const cp = Math.cos(rad(-cam.pitch)), sp = Math.sin(rad(-cam.pitch)); // pitch > 0 looks down
  [y, z] = [y * cp - z * sp, y * sp + z * cp];
  return { x, y, d: -z };
};

/** Where a world point lands on screen (px), for overlays drawn flat over the stage. */
export const project = (cam: Cam, p: { x: number; y: number; z: number }, W = 1920, H = 1080) => {
  const P = perspectiveFor(cam.fov ?? 40, H);
  const c = toCam(cam, p);
  const k = P / c.d;
  return { x: W / 2 + c.x * k, y: H / 2 + c.y * k, k };
};

const Ctx = React.createContext<Cam>({ x: 0, y: 0, z: 1000, yaw: 0, pitch: 0 });

export const Stage: React.FC<{ cam: Cam; children: React.ReactNode; background?: string }> = ({ cam, children, background }) => {
  const P = perspectiveFor(cam.fov ?? 40);
  return (
    <AbsoluteFill style={{ background, perspective: P, perspectiveOrigin: "50% 50%", overflow: "hidden" }}>
      <div style={{ position: "absolute", left: "50%", top: "50%", width: 0, height: 0, transformStyle: "preserve-3d", transform: `translateZ(${P}px) rotateZ(${cam.roll ?? 0}deg) rotateX(${-cam.pitch}deg) rotateY(${cam.yaw}deg) translate3d(${-cam.x}px, ${-cam.y}px, ${-cam.z}px)` }}>
        <Ctx.Provider value={cam}>{children}</Ctx.Provider>
      </div>
    </AbsoluteFill>
  );
};

/**
 * An object at (x, y, z), rotated, of size w x h, drawn with its top left at the anchor
 * offset (ax, ay) as a fraction of its size (0.5, 1 = bottom centre stands on the point).
 */
export const Obj: React.FC<{
  x: number; y: number; z: number; w: number; h: number;
  rx?: number; ry?: number; rz?: number; ax?: number; ay?: number;
  dof?: boolean; extraBlur?: number; opacity?: number; children: React.ReactNode; style?: React.CSSProperties;
  /** Draws the children at `res` times the size and scales them down inside the 3D transform,
   *  so close ups stay sharp (the browser rasterises a 3D layer at its own layout size). The
   *  children must be laid out at w * res by h * res. */
  res?: number;
}> = ({ x, y, z, w, h, rx = 0, ry = 0, rz = 0, ax = 0.5, ay = 1, dof = true, extraBlur = 0, opacity = 1, children, style, res = 1 }) => {
  const cam = React.useContext(Ctx);
  // Blur is wanted in screen pixels, but the filter runs in the object's own pixels before the
  // perspective enlarges it, so it is divided by the object's on-screen scale (P / d).
  let blur = 0;
  const c = toCam(cam, { x, y: y - h * (ay - 0.5), z });
  const scale = perspectiveFor(cam.fov ?? 40) / Math.max(1, c.d);
  if (dof && cam.focus) {
    const A = cam.aperture ?? 10;
    blur += Math.min(28, (A * Math.abs(c.d - cam.focus)) / Math.max(1, c.d));
  }
  // A filter makes the browser rasterise the object at its own (small) size before the
  // perspective enlarges it, which softens a close object; so a blur too small to see is
  // skipped altogether and the object stays crisp.
  blur = blur + extraBlur < 1.5 ? 0 : (blur + extraBlur) / Math.max(0.05, scale);
  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: w, height: h, transformStyle: "preserve-3d", transformOrigin: `${ax * 100}% ${ay * 100}%`, transform: `translate3d(${x - w * ax}px, ${y - h * ay}px, ${z}px) rotateY(${ry}deg) rotateX(${rx}deg) rotateZ(${rz}deg)`, filter: blur > 0.25 ? `blur(${blur.toFixed(2)}px)` : undefined, opacity, ...style }}>
      {res === 1 ? children : <div style={{ position: "absolute", left: 0, top: 0, width: w * res, height: h * res, transform: `scale(${1 / res})`, transformOrigin: "0 0" }}>{children}</div>}
    </div>
  );
};

/** A horizontal plane (the desk top), centred at (x, y, z), w wide and d deep. */
export const Plane: React.FC<{ x: number; y: number; z: number; w: number; d: number; background: string; children?: React.ReactNode }> = ({ x, y, z, w, d, background, children }) => (
  <div style={{ position: "absolute", left: 0, top: 0, width: w, height: d, transformOrigin: "50% 50%", transform: `translate3d(${x - w / 2}px, ${y - d / 2}px, ${z}px) rotateX(90deg)`, background }}>
    {children}
  </div>
);

/** A camera at `pos` looking at `target` (yaw > 0 turns right, pitch > 0 looks down). */
export const lookAt = (pos: { x: number; y: number; z: number }, target: { x: number; y: number; z: number }, extra: Partial<Cam> = {}): Cam => {
  const dx = target.x - pos.x, dy = target.y - pos.y, dz = target.z - pos.z;
  const yaw = (Math.atan2(dx, -dz) * 180) / Math.PI;
  const pitch = (Math.atan2(dy, Math.hypot(dx, dz)) * 180) / Math.PI;
  return { ...pos, yaw, pitch, focus: Math.hypot(dx, dy, dz), ...extra };
};

type V3 = { x: number; y: number; z: number };
export type CamKey = { t: number; pos: V3; look: V3; fov?: number; aperture?: number; focus?: number; ease?: (x: number) => number };
const mix = (a: V3, b: V3, u: number): V3 => ({ x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u, z: a.z + (b.z - a.z) * u });
/**
 * A camera path through keys: position and target are eased between keys (each key's `ease`
 * shapes the move that arrives at it), focus follows the target unless a key sets it.
 */
export const camPath = (keys: CamKey[], t: number): Cam => {
  if (t <= keys[0].t) return lookAt(keys[0].pos, keys[0].look, { fov: keys[0].fov ?? 34, aperture: keys[0].aperture ?? 8, ...(keys[0].focus ? { focus: keys[0].focus } : {}) });
  for (let i = 1; i < keys.length; i++) {
    const a = keys[i - 1], b = keys[i];
    if (t <= b.t) {
      const raw = (t - a.t) / Math.max(1e-6, b.t - a.t);
      const u = (b.ease ?? ((x: number) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2)))(raw);
      const pos = mix(a.pos, b.pos, u), look = mix(a.look, b.look, u);
      const cam = lookAt(pos, look, { fov: (a.fov ?? 34) + ((b.fov ?? 34) - (a.fov ?? 34)) * u, aperture: (a.aperture ?? 8) + ((b.aperture ?? 8) - (a.aperture ?? 8)) * u });
      if (a.focus !== undefined || b.focus !== undefined) {
        const fa = a.focus ?? Math.hypot(a.look.x - a.pos.x, a.look.y - a.pos.y, a.look.z - a.pos.z);
        const fb = b.focus ?? Math.hypot(b.look.x - b.pos.x, b.look.y - b.pos.y, b.look.z - b.pos.z);
        cam.focus = fa + (fb - fa) * u;
      }
      return cam;
    }
  }
  const k = keys[keys.length - 1];
  return lookAt(k.pos, k.look, { fov: k.fov ?? 34, aperture: k.aperture ?? 8, ...(k.focus ? { focus: k.focus } : {}) });
};

import React from "react";
import { AbsoluteFill } from "remotion";
import { C, MODE_ACCENT } from "../theme";
import { Phone, PHONE_ASPECT } from "../devices/Phone";
import { Mac } from "../devices/Mac";
import { TrackpadScreen } from "../screens/Trackpad";
import { MODE_LIST, tapFx } from "../screens/Modes";
import { Caption } from "../Captions";
import { clamp, lerp, minJerk, spring, snappy, prog } from "../motion";

/* The mode tour. Menu phase: the phone alone, large, the pill and the menu. Then the phone moves left,
   the Mac comes in on the right, and each mode runs for one bar with its Mac side. */
export const MENU = { touchTop: 30, pill: 34, tapPill: 64, tapDock: 142 };
export const menuTapDock = (): [number, number] => [400, 105];

type Props = { f: number; menuAt: number; modeAt: number[]; end: number; W?: number; H?: number; vertical?: boolean; skipMenu?: boolean; count?: number };

export const Modes: React.FC<Props> = ({ f, menuAt, modeAt, end, W = 1920, H = 1080, vertical, skipMenu, count = 7 }) => {
  const k = f - menuAt;
  // which mode is on
  let mi = -1;
  modeAt.forEach((a, i) => { if (f >= a) mi = i; });
  const mk = mi >= 0 ? f - modeAt[mi] : 0;

  // phone placement: menu (big, centred) -> tour (left), portrait from mode 1 on
  const tour = skipMenu ? 1 : minJerk((f - (modeAt[0] - 30)) / 56);
  const toPortrait = mi >= 1 ? clamp(snappy(f, modeAt[1])) : 0;
  void count;
  const longLand = lerp(vertical ? 1000 : 1240, vertical ? 820 : 800, tour);
  const portH = vertical ? 850 : 950;
  const wLand = longLand / PHONE_ASPECT, wPort = portH / PHONE_ASPECT;
  const pw = lerp(wLand, wPort, toPortrait);
  const ph = pw * PHONE_ASPECT;
  const cx = vertical ? W / 2 : lerp(W / 2, 480, tour), cy = vertical ? lerp(H / 2, 1190, tour) : lerp(H / 2, 540, tour);
  const rot = lerp(-90, 0, toPortrait);

  // menu phase content
  const pill = clamp(spring(k, MENU.pill, 260, 1)) * (1 - prog(k, MENU.tapDock + 30, 16));
  const menu = clamp(snappy(k, MENU.tapPill + 2)) * (1 - clamp(spring(k, MENU.tapDock + 4, 420, 1)));
  const [dx, dy] = menuTapDock();
  const taps = [tapFx(k, MENU.tapPill, 437, 33), tapFx(k, MENU.tapDock, dx, dy)];
  const top = tapFx(k, MENU.touchTop, 520, 22);
  const fingers = [...top.f.map((x) => ({ ...x })), ...taps.flatMap((t) => t.f)];
  const ripples = taps.flatMap((t) => t.r);
  const dockIn = skipMenu ? 1 : prog(k, MENU.tapDock + 6, 22);

  // screen layers, crossfaded at each boundary
  const layer = (i: number) => {
    const a = modeAt[i], b = i + 1 < modeAt.length ? modeAt[i + 1] : end;
    const o = i === 0 ? dockIn * (1 - prog(f, b - 4, 10)) : prog(f, a - 2, 10) * (1 - prog(f, b - 4, 10));
    return o;
  };
  const isLand = (i: number) => i === 0;
  const LIST = MODE_LIST.slice(0, count);
  const phoneScreens = LIST.map((m, i) => {
    const o = layer(i);
    if (o <= 0.001) return null;
    const Comp = m.Phone;
    const land = isLand(i);
    // landscape content must counter the device rotation while the phone turns
    return (
      <div key={m.key} style={{ position: "absolute", inset: 0, opacity: o }}>
        {land ? <div style={{ position: "absolute", left: 0, top: 0, width: 874, height: 402, transformOrigin: "0 0", transform: "translate(402px, 0) rotate(90deg)" }}><Comp k={f - modeAt[i]} /></div> : <Comp k={f - modeAt[i]} />}
      </div>
    );
  });
  const macO = tour;
  const macLayers = LIST.map((m, i) => {
    const o = i === 0 ? 1 * (1 - (modeAt.length > 1 ? prog(f, modeAt[1] - 4, 10) : 0)) : layer(i);
    if (o <= 0.001) return null;
    const Comp = m.Mac;
    return <div key={m.key} style={{ position: "absolute", inset: 0, opacity: o }}><Comp k={f - modeAt[i]} /></div>;
  });

  const L = vertical ? 760 : 860;
  const macX = vertical ? (W - L) / 2 : 900, macY = vertical ? 110 : 150;
  const macSlide = vertical ? (1 - tour) * -900 : (1 - tour) * 1100;
  const out = clamp((f - (end - 18)) / 16);
  const trackOn = 1 - dockIn;
  return (
    <AbsoluteFill style={{ background: C.paper, opacity: 1 - out }}>
      <div style={{ position: "absolute", left: vertical ? macX : macX + macSlide, top: vertical ? macY + macSlide : macY, opacity: macO }}>
        <Mac L={L}>{macLayers}</Mac>
      </div>
      <div style={{ position: "absolute", left: cx - pw / 2, top: cy - ph / 2, transform: `rotate(${rot}deg)` }}>
        <Phone w={pw} screenBg={C.paper}>
          {/* trackpad (landscape, 874 x 402) during the menu */}
          {trackOn > 0.001 && (
            <div style={{ position: "absolute", left: 0, top: 0, width: 874, height: 402, transformOrigin: "0 0", transform: "translate(402px, 0) rotate(90deg)", opacity: trackOn }}>
              <TrackpadScreen fingers={fingers} ripples={ripples} pill={pill} menu={menu} pressed={k >= MENU.tapDock && k < MENU.tapDock + 8 ? "dock" : undefined} />
            </div>
          )}
          {phoneScreens}
        </Phone>
      </div>
      {LIST.map((m, i) => {
        const a = modeAt[i], b = i + 1 < modeAt.length ? modeAt[i + 1] : end;
        return <Caption key={m.key} frame={f} c={{ at: a + 16, out: b - 16, title: m.title, sub: m.sub, dot: MODE_ACCENT[m.key], x: vertical ? 90 : macX, y: vertical ? 1675 : 868, size: vertical ? 80 : 64, maxW: 900 }} />;
      })}
      {!skipMenu && <Caption frame={f} c={{ at: menuAt + 40, out: modeAt[0] - 40, title: "More than a trackpad.", sub: "Touch the top for the mode menu.", x: vertical ? 90 : 120, y: vertical ? 1500 : 884, size: vertical ? 84 : 64, maxW: vertical ? 900 : 1200 }} />}
    </AbsoluteFill>
  );
};

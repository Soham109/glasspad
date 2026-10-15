import React from "react";
import { AbsoluteFill } from "remotion";
import { Mac } from "../devices/Mac";
import { Phone } from "../devices/Phone";
import { Desktop, DesktopState } from "../screens/Desktop";
import { TrackpadScreen, Finger, Ripple } from "../screens/Trackpad";
import { C } from "../theme";
import { Layout, geom } from "./layout";
import { Cam, worldTransform } from "./camera";

export type SetupProps = {
  l: Layout;
  cam: Cam;
  tilt: number; // degrees the phone lies back
  fingers: Finger[];
  ripples: Ripple[];
  desk: DesktopState;
  macO?: number; // Mac reveal 0..1
  macRise?: number; // px
  deskO?: number; // desk tone 0..1 (paper -> desk)
  body?: number;
  shake?: number;
  pill?: number;
  menu?: number;
};

/** The setup: a MacBook on a desk and an iPhone lying sideways in front of it, seen by a 2D camera. */
export const Setup: React.FC<SetupProps> = ({ l, cam, tilt, fingers, ripples, desk, macO = 1, macRise = 0, deskO = 1, body = 1, shake = 0, pill = 0, menu = 0 }) => {
  const g = geom(l);
  return (
    <AbsoluteFill style={{ background: C.paper, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 0, top: 0, transformOrigin: "0 0", transform: worldTransform(cam, l.W, l.H) }}>
        <div style={{ position: "absolute", left: -4000, width: 10000, top: l.deskY, height: 6000, background: C.desk, opacity: deskO }} />
        <div style={{ position: "absolute", left: l.macX, top: l.macY + macRise, opacity: macO }}>
          <Mac L={l.L}><Desktop s={desk} /></Mac>
        </div>
        <div style={{ position: "absolute", left: l.phoneCx - g.pw / 2, top: l.phoneCy - g.p.h / 2, transform: `perspective(${l.phoneLong * 3.2}px) rotateX(${tilt}deg) rotate(-90deg)` }}>
          <Phone w={g.pw} land body={body} shake={shake}>
            <TrackpadScreen fingers={fingers} ripples={ripples} pill={pill} menu={menu} />
          </Phone>
        </div>
      </div>
    </AbsoluteFill>
  );
};

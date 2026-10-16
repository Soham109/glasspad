// The film's poster (site thumbnail, YouTube thumbnail): the morning desk, the phone on its
// stand sharp in the foreground, the display soft behind it. No text.
import React from "react";
import { AbsoluteFill, Img } from "remotion";
import { C, phone } from "./core";
import { DeskSet } from "./set/Desk";
import { lookAt } from "./set/Stage3D";
import { Dock, MenuBar, Wallpaper } from "./mac/Desktop";
import { MailApp, SafariApp } from "./mac/Apps";
import { EXT, MBP } from "./devices/Mac";
import { Grain, Vignette } from "./fx";

export const PosterV4: React.FC = () => {
  const cam = lookAt({ x: 700, y: -110, z: 760 }, { x: 470, y: -240, z: 40 }, { fov: 40, aperture: 11 });
  cam.focus = 560;
  const top = 38, h = EXT.h - top - 92;
  return (
    <AbsoluteFill style={{ background: C.black }}>
      <DeskSet cam={cam} light={1}
        display={<><Wallpaper w={EXT.w} h={EXT.h} /><MailApp x={EXT.w / 2 + 4} y={top} w={EXT.w / 2 - 12} h={h} active={false} /><SafariApp x={8} y={top} w={EXT.w / 2 - 12} h={h} /><MenuBar w={EXT.w} app="Safari" focus /><Dock w={EXT.w} h={EXT.h} running={["com.apple.finder", "com.apple.mail", "com.apple.Safari"]} /></>}
        laptop={<><Wallpaper kind="dusk" w={MBP.w} h={MBP.h} /><MenuBar w={MBP.w} app="Finder" /><Dock w={MBP.w} h={MBP.h} size={58} /></>}
        phone={<Img src={phone("pinned.png")} style={{ width: 2622, height: 1206 }} />}
        phoneSweep={0.35} />
      <AbsoluteFill style={{ mixBlendMode: "screen", background: "linear-gradient(118deg, rgba(255,190,140,0) 38%, rgba(255,190,140,0.08) 52%, rgba(255,190,140,0) 66%)" }} />
      <Vignette amount={0.36} />
      <Grain amount={0.035} />
    </AbsoluteFill>
  );
};

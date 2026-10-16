import React from "react";
import { Img, useCurrentFrame } from "remotion";
import { DeskSet } from "./set/Desk";
import { Wallpaper, MenuBar, Dock } from "./mac/Desktop";
import { MailApp, SafariApp } from "./mac/Apps";
import { EXT, MBP } from "./devices/Mac";
import { phone } from "./core";

export const TestDesk: React.FC<{ yaw: number; pitch: number; x: number; y: number; z: number; focus: number }> = (p) => {
  useCurrentFrame();
  return (
    <DeskSet cam={{ x: p.x, y: p.y, z: p.z, yaw: p.yaw, pitch: p.pitch, fov: 32, focus: p.focus, aperture: 8 }}
      display={<><Wallpaper w={EXT.w} h={EXT.h} /><SafariApp x={180} y={80} w={1000} h={660} active={false} /><MailApp x={420} y={140} w={1040} h={640} /><MenuBar w={EXT.w} app="Mail" /><Dock w={EXT.w} h={EXT.h} running={["com.apple.finder", "com.apple.mail", "com.apple.Safari"]} /></>}
      laptop={<><Wallpaper kind="dusk" w={MBP.w} h={MBP.h} /><MenuBar w={MBP.w} app="Finder" /><Dock w={MBP.w} h={MBP.h} /></>}
      phone={<Img src={phone("pinned.png")} style={{ width: 2622, height: 1206 }} />} />
  );
};

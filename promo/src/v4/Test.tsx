import React from "react";
import { Img } from "remotion";
import { Footage, Track } from "./footage/Footage";
import { phone } from "./core";
import desk from "./tracks/desk-topdown.json";
import couch from "./tracks/handoff.json";

export const TestFootage: React.FC<{ clip: string }> = ({ clip }) => {
  const tr = (clip === "handoff" ? couch : desk) as unknown as Track;
  return (
    <Footage track={tr} from={0} screens={[{ w: 1206, h: 2622, content: <Img src={phone("actions-portrait.png")} style={{ width: 1206, height: 2622 }} /> }]} />
  );
};

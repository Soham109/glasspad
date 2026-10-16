// 0 to 8 s. "Your Mac is over there. Your phone is right here." A far Mac, a near phone,
// one dot landing on the glass, and on the first downbeat the dot opens into the title.
import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { C, E, T, beatPulse, keys, lerp, prog, s, spr } from "../system";
import { Kinetic } from "../ui/Kinetic";
import { Desktop } from "./Desktop";
import { MacBook } from "../ui/Mac";
import { Phone } from "../ui/Phone";
import { DotWipe, Floor } from "../ui/FX";

// Where the phone's dot sits at the hit, in frame pixels. The Title scene opens from here.
export const HIT_DOT = { x: 1340, y: 640 };

export const Hook: React.FC = () => {
  const f = useCurrentFrame();
  // Camera: a slow push toward the phone once it arrives.
  const push = keys(f, [[s(4.2), 1], [s(8.0), 1.12]], E.glide);
  const cx = HIT_DOT.x, cy = HIT_DOT.y;

  // The far Mac: arrives small, then slides away as the phone takes the foreground.
  const macIn = spr(f, -s(0.25), "settle");
  const macAway = keys(f, [[s(3.6), 0], [s(5.2), 1]], E.inOut);
  const macX = lerp(1450, 1560, macAway);
  const macY = lerp(310, 230, macAway) + lerp(40, 0, macIn);
  const macScale = lerp(1, 0.82, macAway);

  // The near phone: rises from below the frame, big and slightly turned.
  const ph = spr(f, s(3.75), "heavy");
  const phoneY = lerp(1240, 190, ph);
  const phoneRot = lerp(-11, -5, ph);

  // The dot lands on "here".
  const dotT = spr(f, s(5.05), "pop");
  const breathe = 1 + 0.08 * beatPulse(f, s(6.0), 9) * (f >= s(6.0) ? 1 : 0);
  const ringT = prog(f, s(5.05), 34, E.out);

  return (
    <AbsoluteFill style={{ background: C.paper, overflow: "hidden" }}>
      <AbsoluteFill style={{ transform: `scale(${push})`, transformOrigin: `${cx}px ${cy}px` }}>
        {/* far Mac */}
        <Floor x={macX} y={macY + 352} w={640} h={26} opacity={0.07 * macIn} />
        <div style={{ position: "absolute", left: macX - 250, top: macY, opacity: macIn, transform: `scale(${macScale})`, transformOrigin: "50% 0%" }}>
          <MacBook width={500}>
            <Desktop app="TextEdit" running={["com.apple.finder", "com.apple.Safari"]} word />
          </MacBook>
        </div>

        {/* near phone, screen off: graphite glass */}
        <div style={{ position: "absolute", left: cx - 270, top: phoneY, transform: `rotate(${phoneRot}deg)`, transformOrigin: "270px 450px" }}>
          <Phone short={540} screen={C.graphite}>
            {f >= s(5.0) ? (
              <>
                <Disc x={270 - 19.7} y={450 - 19.7} d={52 * dotT * breathe} fill="rgba(242,241,238,0.9)" />
                <Disc x={270 - 19.7} y={450 - 19.7} d={120 * lerp(0.4, 1.8, ringT)} ring={C.paper} opacity={1 - ringT} />
              </>
            ) : null}
          </Phone>
        </div>
      </AbsoluteFill>

      {/* type */}
      <div style={{ position: "absolute", left: 132, top: 360 }}>
        <Kinetic text="Your Mac is over there." at={s(0.98)} out={s(3.35)} stagger={5} style={{ ...T.hero }} lineBreaks={[3]} />
      </div>
      <div style={{ position: "absolute", left: 132, top: 360 }}>
        <Kinetic text="Your phone is right here." at={s(3.98)} out={s(6.2)} stagger={5} style={{ ...T.hero }} lineBreaks={[3]} accent={["here"]} />
      </div>

      {/* the hit: the dot opens into graphite */}
      <DotWipe x={cx} y={cy} at={s(7.97)} dur={22} color={C.graphite} />
    </AbsoluteFill>
  );
};

const Disc: React.FC<{ x: number; y: number; d: number; fill?: string; ring?: string; opacity?: number }> = ({ x, y, d, fill, ring, opacity = 1 }) => (
  <div style={{ position: "absolute", left: x - d / 2, top: y - d / 2, width: d, height: d, borderRadius: d, background: fill, boxShadow: ring ? `inset 0 0 0 2px ${ring}` : undefined, opacity }} />
);

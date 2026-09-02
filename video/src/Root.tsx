import React from "react";
import { Composition } from "remotion";
import { Demo } from "./Demo";
import { FPS, HEIGHT, TOTAL_FRAMES, WIDTH } from "./timeline";

export const RemotionRoot: React.FC = () => (
  <Composition
    id="TrustListDemo"
    component={Demo}
    durationInFrames={TOTAL_FRAMES}
    fps={FPS}
    width={WIDTH}
    height={HEIGHT}
  />
);

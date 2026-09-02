import React from "react";
import {
  AbsoluteFill,
  Audio,
  OffthreadVideo,
  Sequence,
  interpolate,
  staticFile,
  useCurrentFrame,
} from "remotion";
import { loadFonts } from "./fonts";
import { Labels, LowerThird } from "./Overlays";
import { END_CARD_FRAMES, SCENES, sceneFrames, secs, type Scene } from "./timeline";
import { data, depth, display, dormant, paper, signal } from "./theme";

/// One scene: its segments back to back, its voice line from frame zero,
/// and whatever overlays the shot list asks for.
const SceneView: React.FC<{ scene: Scene }> = ({ scene }) => {
  let at = 0;
  return (
    <AbsoluteFill style={{ background: paper }}>
      {scene.segments.map((seg, i) => {
        const from = at;
        const frames = secs(seg.seconds);
        at += frames;
        return (
          <Sequence key={i} from={from} durationInFrames={frames} name={seg.clip}>
            <OffthreadVideo src={staticFile(`clips/${seg.clip}.mp4`)} muted />
          </Sequence>
        );
      })}
      <Audio src={staticFile(`audio/${scene.audio}.wav`)} />
      {scene.overlays.map((o, i) =>
        o.kind === "lowerThird" ? (
          <LowerThird key={i} overlay={o} />
        ) : (
          <Labels key={i} overlay={o} />
        ),
      )}
    </AbsoluteFill>
  );
};

/// No logo animation. The two places to go, and nothing else.
const EndCard: React.FC = () => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, 12], [0, 1], { extrapolateRight: "clamp" });
  return (
    <AbsoluteFill
      style={{
        background: depth,
        color: paper,
        justifyContent: "center",
        alignItems: "center",
        opacity,
      }}
    >
      <div style={{ fontFamily: display, fontSize: 96, letterSpacing: "-0.02em" }}>
        TrustList
      </div>
      <div style={{ fontFamily: data, fontSize: 30, color: dormant, marginTop: 8, letterSpacing: "0.08em" }}>
        ERC-8004 / BNB SMART CHAIN
      </div>
      <div style={{ height: 4, width: 120, background: signal, margin: "48px 0" }} />
      <div style={{ fontFamily: data, fontSize: 40, lineHeight: 1.6, textAlign: "center" }}>
        <div>trustlistapp.vercel.app</div>
        <div>github.com/big14way/Trustlist</div>
      </div>
    </AbsoluteFill>
  );
};

export const Demo: React.FC = () => {
  loadFonts();
  let at = 0;
  return (
    <AbsoluteFill style={{ background: paper }}>
      {SCENES.map((scene) => {
        const from = at;
        const frames = sceneFrames(scene);
        at += frames;
        return (
          <Sequence key={scene.id} from={from} durationInFrames={frames} name={`${scene.id} ${scene.title}`}>
            <SceneView scene={scene} />
          </Sequence>
        );
      })}
      <Sequence from={at} durationInFrames={END_CARD_FRAMES} name="end card">
        <EndCard />
      </Sequence>
    </AbsoluteFill>
  );
};

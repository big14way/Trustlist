import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import type { Overlay } from "./timeline";
import { data, depth, paper, signal } from "./theme";

const FADE = 8;

function opacityFor(frame: number, from: number, to: number): number {
  return interpolate(
    frame,
    [from, from + FADE, to - FADE, to],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );
}

/// A lower third in the site's own colours: depth green panel, paper text,
/// mono for anything that is a number or a hash. Hashes are set in full and
/// held on screen at least a second, per SPEC section 24.
export const LowerThird: React.FC<{ overlay: Overlay }> = ({ overlay }) => {
  const frame = useCurrentFrame();
  const opacity = opacityFor(frame, overlay.from, overlay.to);
  if (frame < overlay.from || frame > overlay.to) return null;
  return (
    <AbsoluteFill style={{ justifyContent: "flex-end", alignItems: "flex-start" }}>
      <div
        style={{
          opacity,
          margin: "0 0 72px 72px",
          padding: "22px 30px",
          background: depth,
          color: paper,
          borderLeft: `8px solid ${signal}`,
          fontFamily: data,
          fontSize: 30,
          lineHeight: 1.45,
          letterSpacing: "0.01em",
          maxWidth: 2200,
          boxShadow: "0 8px 30px rgba(15, 21, 24, 0.25)",
        }}
      >
        {overlay.lines.map((line, i) => (
          <div key={i} style={{ opacity: i === 0 ? 1 : 0.75, fontSize: i === 0 ? 30 : 24 }}>
            {line}
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};

/// Two small labels stacked at the top right, for the moments where the
/// voice names two numbers that are both on screen.
export const Labels: React.FC<{ overlay: Overlay }> = ({ overlay }) => {
  const frame = useCurrentFrame();
  const opacity = opacityFor(frame, overlay.from, overlay.to);
  if (frame < overlay.from || frame > overlay.to) return null;
  return (
    <AbsoluteFill style={{ justifyContent: "flex-start", alignItems: "flex-end" }}>
      <div style={{ opacity, margin: "72px 72px 0 0", display: "flex", flexDirection: "column", gap: 12 }}>
        {overlay.lines.map((line, i) => (
          <div
            key={i}
            style={{
              padding: "14px 22px",
              background: i === 0 ? paper : depth,
              color: i === 0 ? depth : paper,
              border: `2px solid ${depth}`,
              fontFamily: data,
              fontSize: 26,
              textTransform: "uppercase",
              letterSpacing: "0.08em",
            }}
          >
            {line}
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};

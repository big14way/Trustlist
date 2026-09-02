// The cut, as data. Every duration here matches what prepare.sh produces,
// so the composition never has to probe a file: a segment of N seconds is
// N times 30 frames, and a scene is the sum of its segments. The voice line
// for each scene starts with the scene and is always shorter than it.

export const FPS = 30;
export const WIDTH = 2560;
export const HEIGHT = 1440;

const secs = (s: number) => Math.round(s * FPS);

export type Segment = { clip: string; seconds: number };

export type Overlay = {
  /// Frames into the scene at which the overlay appears and disappears.
  from: number;
  to: number;
  kind: "lowerThird" | "labels";
  lines: string[];
};

export type Scene = {
  id: number;
  title: string;
  segments: Segment[];
  /// Voice file under public/audio, and its measured length.
  audio: string;
  audioSeconds: number;
  overlays: Overlay[];
};

// Transaction hashes for job 56686, the hire made on camera. Read back from
// the chain, not from the recording: the hire is the job's create_tx in the
// jobs table and the acceptance is the Accepted event on HireRail at block
// 119,451,025.
export const HIRE_TX =
  "0xace312261c527a6b26bc4861f0c78f2122d081cfec7e605bae620f334626dca9";
export const ACCEPT_TX =
  "0xdadb5ecb974aa83131b0f1031cdcbd978b3a7bed3c456fef9d80509f8b9b7991";

export const SCENES: Scene[] = [
  {
    id: 1,
    title: "Most agents are not there",
    segments: [{ clip: "s1", seconds: 14.2 }],
    audio: "scene1",
    audioSeconds: 14.0,
    overlays: [],
  },
  {
    id: 2,
    title: "Registry health",
    segments: [{ clip: "s2", seconds: 34.8 }],
    audio: "scene2",
    audioSeconds: 34.75,
    overlays: [
      {
        from: secs(17),
        to: secs(34.8),
        kind: "lowerThird",
        lines: ["13 wallets. 13,103 reviews. 44 percent of all reputation on chain."],
      },
    ],
  },
  {
    id: 3,
    title: "Agent 137",
    segments: [{ clip: "s3", seconds: 38.2 }],
    audio: "scene3",
    audioSeconds: 38.11,
    overlays: [
      {
        from: secs(9),
        to: secs(30),
        kind: "labels",
        lines: ["what the registry says: 96.8", "what we count: 90.4"],
      },
    ],
  },
  {
    id: 4,
    title: "Hire",
    segments: [
      { clip: "s4a", seconds: 16 },
      { clip: "s4b", seconds: 22 },
      { clip: "s4c", seconds: 10 },
    ],
    audio: "scene4",
    audioSeconds: 43.44,
    overlays: [
      {
        from: secs(36),
        to: secs(48),
        kind: "lowerThird",
        lines: [`hire  ${HIRE_TX}`, "job 56686, ERC-8183 escrow, BNB Smart Chain mainnet"],
      },
    ],
  },
  {
    id: 5,
    title: "Deliver and accept",
    segments: [
      { clip: "s5a", seconds: 6 },
      { clip: "s5b", seconds: 4 },
      { clip: "s5c", seconds: 6 },
      { clip: "s5d", seconds: 4 },
      { clip: "s5e", seconds: 8 },
    ],
    audio: "scene5",
    audioSeconds: 17.81,
    overlays: [
      {
        from: secs(20),
        to: secs(28),
        kind: "lowerThird",
        // What is on screen here is the hire transaction, opened from the
        // job panel, with the 0.05 U moving into escrow. The acceptance that
        // released it is the second line, read from the chain.
        lines: [
          `hire  ${HIRE_TX}  funded 0.05 U into escrow`,
          `accepted in  ${ACCEPT_TX}  block 119,451,025, escrow released to the agent`,
        ],
      },
    ],
  },
  {
    id: 6,
    title: "Verify on chain",
    segments: [{ clip: "s6", seconds: 22.4 }],
    audio: "scene6",
    audioSeconds: 22.16,
    overlays: [
      {
        from: secs(11),
        to: secs(22.4),
        kind: "labels",
        lines: ["real score: verified by the contract", "inflated score: rejected"],
      },
    ],
  },
  {
    id: 7,
    title: "Advantage report",
    segments: [{ clip: "s7", seconds: 32.6 }],
    audio: "scene7",
    audioSeconds: 32.32,
    overlays: [
      {
        from: secs(16),
        to: secs(32.6),
        kind: "lowerThird",
        lines: ["jobs 56676, 56677, 56678, all on BNB Smart Chain mainnet"],
      },
    ],
  },
  {
    id: 8,
    title: "Methodology",
    segments: [{ clip: "s8", seconds: 17.6 }],
    audio: "scene8",
    audioSeconds: 17.44,
    overlays: [],
  },
  {
    id: 9,
    title: "Live",
    segments: [
      { clip: "s9a", seconds: 6 },
      { clip: "s9b", seconds: 5 },
      { clip: "s9c", seconds: 6 },
    ],
    audio: "scene9",
    audioSeconds: 12.88,
    overlays: [],
  },
];

export const END_CARD_FRAMES = secs(3);

export const sceneFrames = (s: Scene): number =>
  s.segments.reduce((n, seg) => n + secs(seg.seconds), 0);

export const TOTAL_FRAMES =
  SCENES.reduce((n, s) => n + sceneFrames(s), 0) + END_CARD_FRAMES;

export { secs };

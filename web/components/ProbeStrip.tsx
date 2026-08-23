"use client";

// The signature element: 168 cells, 7 days by 24 hours, one per probe
// bucket. Amber for a hour where the endpoint answered, grey for one where
// it did not, hollow where no probe ran. Hand rolled SVG, real data only.
//
// The hover detail is a caption rather than an SVG <title> element: React 19
// treats <title> as hoistable document metadata wherever it appears, which
// pulls it out of the SVG and makes the server and client renders disagree.
// A caption is also faster to read than waiting for a native tooltip.

import { useState } from "react";

export type UptimeBucket = {
  hour: string;
  ok_share: number | null;
  probes: number;
};

const CELL = 3;
const GAP = 2;
const HEIGHT = 16;
const HOURS = 168;

function describe(b: UptimeBucket | null): string {
  if (!b || b.probes === 0) return "no probe that hour";
  const hour = b.hour.slice(0, 13).replace("T", " ");
  const pct = Math.round((b.ok_share ?? 0) * 100);
  return `${hour}:00 UTC · ${b.probes} probe${b.probes === 1 ? "" : "s"} · ${pct}% answered`;
}

export function ProbeStrip({
  buckets,
  label,
}: {
  /// A contiguous hourly series ending at the last complete hour, generated
  /// by the API. The strip draws exactly what it is given and never consults
  /// a clock, so the server and the browser always agree.
  buckets: UptimeBucket[];
  label: string;
}) {
  const [hovered, setHovered] = useState<number | null>(null);

  const recent = buckets.slice(-HOURS);
  const cells: (UptimeBucket | null)[] = [
    ...Array.from({ length: Math.max(0, HOURS - recent.length) }, () => null),
    ...recent,
  ];

  const probed = cells.filter((c) => c && c.probes > 0);
  const upShare =
    probed.length > 0
      ? probed.reduce((acc, c) => acc + (c?.ok_share ?? 0), 0) / probed.length
      : null;
  const summary =
    upShare === null
      ? `${label}: no probes recorded in the last 7 days`
      : `${label}: answered ${(upShare * 100).toFixed(1)} percent of the ${probed.length} hours we probed in the last 7 days`;

  const width = HOURS * (CELL + GAP) - GAP;

  return (
    <div>
      <svg
        viewBox={`0 0 ${width} ${HEIGHT}`}
        className="h-4 w-full"
        role="img"
        aria-label={summary}
        preserveAspectRatio="none"
        onMouseLeave={() => setHovered(null)}
      >
        {cells.map((c, i) => {
          const x = i * (CELL + GAP);
          const hollow = !c || c.probes === 0;
          const up = (c?.ok_share ?? 0) >= 0.5;
          return (
            <rect
              key={i}
              x={x}
              y={0}
              width={CELL}
              height={HEIGHT}
              fill={hollow ? "none" : up ? "var(--signal)" : "var(--dormant)"}
              stroke={hollow ? "var(--dormant)" : undefined}
              strokeWidth={hollow ? 0.5 : undefined}
              opacity={hollow ? 0.5 : undefined}
              onMouseEnter={() => setHovered(i)}
            />
          );
        })}
      </svg>
      <p className="font-data mt-1 h-4 text-[11px] leading-4 text-ink/60">
        {hovered !== null ? describe(cells[hovered] ?? null) : ""}
      </p>
    </div>
  );
}

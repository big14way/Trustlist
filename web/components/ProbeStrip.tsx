// The signature element: 168 cells, 7 days by 24 hours, one per probe
// bucket. Amber means the endpoint answered, grey means it did not, hollow
// means no probe ran that hour. Hand rolled SVG, real data only.

export type UptimeBucket = {
  hour: string;
  ok_share: number | null;
  probes: number;
};

const CELL = 3;
const GAP = 2;
const HEIGHT = 16;
const HOURS = 168;

export function ProbeStrip({
  buckets,
  label,
}: {
  buckets: UptimeBucket[];
  label: string;
}) {
  // Index buckets by hour so missing hours render hollow.
  const byHour = new Map(buckets.map((b) => [b.hour.slice(0, 13), b]));
  const now = Date.now();
  const cells = Array.from({ length: HOURS }, (_, i) => {
    const d = new Date(now - (HOURS - 1 - i) * 3600_000);
    const key = d.toISOString().slice(0, 13);
    return byHour.get(key) ?? null;
  });
  const probed = cells.filter((c) => c && c.probes > 0);
  const upShare =
    probed.length > 0
      ? probed.reduce((acc, c) => acc + (c?.ok_share ?? 0), 0) / probed.length
      : null;
  const summary =
    upShare === null
      ? `${label}: no probes recorded in the last 7 days`
      : `${label}: up ${(upShare * 100).toFixed(1)} percent of probed hours over 7 days`;

  const width = HOURS * (CELL + GAP) - GAP;
  return (
    <svg
      viewBox={`0 0 ${width} ${HEIGHT}`}
      className="h-4 w-full"
      role="img"
      aria-label={summary}
      preserveAspectRatio="none"
    >
      <title>{summary}</title>
      {cells.map((c, i) => {
        const x = i * (CELL + GAP);
        if (!c || c.probes === 0) {
          return (
            <rect
              key={i}
              x={x}
              y={0}
              width={CELL}
              height={HEIGHT}
              fill="none"
              stroke="var(--dormant)"
              strokeWidth="0.5"
              opacity="0.5"
            />
          );
        }
        const up = (c.ok_share ?? 0) >= 0.5;
        return (
          <rect
            key={i}
            x={x}
            y={0}
            width={CELL}
            height={HEIGHT}
            fill={up ? "var(--signal)" : "var(--dormant)"}
          >
            <title>
              {new Date(c.hour).toISOString().slice(0, 13)}:00 {c.probes} probes,{" "}
              {Math.round((c.ok_share ?? 0) * 100)}% ok
            </title>
          </rect>
        );
      })}
    </svg>
  );
}

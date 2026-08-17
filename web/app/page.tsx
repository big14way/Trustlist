// M0 static page: design tokens on screen, no data claims. Real numbers
// arrive with the indexer in M1; until then this page shows none.

const tokens = [
  { name: "paper", hex: "#EDEFE8", role: "primary surface" },
  { name: "ink", hex: "#0F1518", role: "body type" },
  { name: "depth", hex: "#16302F", role: "panels, headers, footer" },
  { name: "signal", hex: "#FFB01F", role: "live status and trust fill only" },
  { name: "dormant", hex: "#9AA3A0", role: "dead agents, secondary type" },
  { name: "flag", hex: "#C4462F", role: "sybil flags, destructive actions" },
];

export default function Home() {
  return (
    <main className="mx-auto max-w-[1200px] px-8 py-16">
      <p className="eyebrow text-dormant">ERC-8004 / BNB SMART CHAIN</p>
      <h1 className="font-display mt-3 text-5xl text-ink">
        Most agents are not there.
      </h1>
      <p className="mt-4 max-w-xl text-base">
        TrustList probes every registered agent, weights every review by how
        independent the reviewer actually is, and turns finding an agent into
        hiring one. Measurement begins when the indexer ships. Until we have
        measured, this page shows no numbers.
      </p>

      <section aria-label="Design tokens" className="mt-14">
        <p className="eyebrow text-dormant">DESIGN TOKENS</p>
        <ul className="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-3">
          {tokens.map((t) => (
            <li key={t.name} className="rounded-lg border border-dormant/40 p-3">
              <div
                className="h-12 w-full rounded-md border border-ink/10"
                style={{ backgroundColor: t.hex }}
              />
              <p className="font-data mt-2 text-sm">
                --{t.name} {t.hex}
              </p>
              <p className="text-xs text-ink/70">{t.role}</p>
            </li>
          ))}
        </ul>
      </section>

      <footer className="mt-16 border-t border-dormant/40 pt-6">
        <p className="font-data text-xs text-dormant">
          M0 scaffold. Indexer, prober, trust engine, and hire flow arrive in
          the milestones behind this page.
        </p>
      </footer>
    </main>
  );
}

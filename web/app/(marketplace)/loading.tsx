// The marketplace is server rendered on every request because its numbers
// change every time the prober runs. On a slow connection that meant a blank
// screen for as long as the fetch took, with nothing to say the page was
// coming.
//
// This is the marketplace's own layout with the text removed, so what
// appears first is where the content will actually land: no spinner, and
// nothing moves when the real page arrives. SPEC.md Section 30.5.

function CardSkeleton() {
  return (
    <li className="rounded-lg border border-dormant/40 bg-paper p-4">
      <div className="flex items-start justify-between gap-2">
        <div className="h-5 w-40 rounded bg-dormant/20" />
        <div className="h-4 w-12 rounded bg-dormant/20" />
      </div>
      <div className="mt-2 h-4 w-full rounded bg-dormant/15" />
      <div className="mt-1 h-4 w-2/3 rounded bg-dormant/15" />
      <div className="mt-3 h-4 w-full rounded bg-dormant/10" />
      <div className="mt-2 flex items-center justify-between gap-2">
        <div className="h-3 w-48 rounded bg-dormant/15" />
        <div className="h-6 w-14 rounded bg-dormant/20" />
      </div>
    </li>
  );
}

export default function Loading() {
  return (
    <main className="mx-auto max-w-[1200px] px-8 py-16" aria-busy="true">
      <p className="eyebrow text-dormant">ERC-8004 / BNB SMART CHAIN</p>
      <h1 className="font-display mt-3 text-5xl text-ink">
        Most agents are not there.
      </h1>
      <p className="mt-4 max-w-2xl text-base text-ink/60">
        Reading the latest counts from our own probe history.
      </p>

      <div className="mt-6 flex flex-wrap gap-2" aria-hidden="true">
        {Array.from({ length: 7 }, (_, i) => (
          <div key={i} className="h-8 w-24 rounded border border-dormant/30" />
        ))}
      </div>

      <section className="mt-8" aria-label="Agents loading">
        <p className="eyebrow text-dormant">AGENTS THAT ANSWER, RANKED</p>
        <ul
          className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3"
          aria-hidden="true"
        >
          {Array.from({ length: 6 }, (_, i) => (
            <CardSkeleton key={i} />
          ))}
        </ul>
      </section>
    </main>
  );
}

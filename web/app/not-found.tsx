// A 404 with no way out is the plainest dead end there is, and until this
// existed a mistyped agent id got Next's default page: the number 404 on a
// blank screen, no explanation, no navigation. SPEC.md Section 30.5 asks
// every state to say what happened and what to do next.

export default function NotFound() {
  return (
    <main className="mx-auto max-w-[1200px] px-8 py-16">
      <p className="eyebrow text-dormant">404</p>
      <h1 className="font-display mt-3 text-4xl text-ink">
        There is nothing at this address.
      </h1>
      <p className="mt-4 max-w-xl text-base text-ink/80">
        Either the link is wrong, or it points at an agent id that the registry
        has never issued. Nothing is broken on our side.
      </p>
      <nav className="mt-8 flex flex-wrap gap-3">
        <a
          href="/"
          className="rounded bg-ink px-4 py-2 text-sm text-paper hover:opacity-90"
        >
          Back to the marketplace
        </a>
        <a
          href="/stats"
          className="rounded border border-dormant/50 px-4 py-2 text-sm hover:border-ink"
        >
          Registry health
        </a>
        <a
          href="/methodology"
          className="rounded border border-dormant/50 px-4 py-2 text-sm hover:border-ink"
        >
          How the numbers are made
        </a>
      </nav>
      <p className="mt-8 max-w-xl text-sm text-ink/60">
        Looking for a specific agent? The marketplace lists the ones that
        answer when we probe them. Turn on the agents that never answer to see
        the rest of the registry.
      </p>
    </main>
  );
}

"use client";

// When a page throws, Next's default screen says "Application error: a
// client-side exception has occurred" and offers nothing. That is a dead
// end, and worse, it looks like the whole product fell over when usually one
// data fetch did.
//
// This names what happened, offers a retry that re-runs the failed render
// rather than a full reload, and gives a way back. It never blames the
// visitor and never apologises: SPEC.md Section 18.5.

import { useEffect } from "react";

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // A swallowed error is worse than a loud one. This is the only place the
    // detail survives, because the visitor is deliberately not shown a stack.
    console.error("page render failed", error);
  }, [error]);

  return (
    <main className="mx-auto max-w-[1200px] px-8 py-16">
      <p className="eyebrow text-flag">SOMETHING BROKE</p>
      <h1 className="font-display mt-3 text-4xl text-ink">
        This page did not finish loading.
      </h1>
      <p className="mt-4 max-w-xl text-base text-ink/80">
        The most likely cause is that our API did not answer in time. Your
        wallet was not touched and no transaction was sent. Everything already
        on chain is unaffected.
      </p>
      <nav className="mt-8 flex flex-wrap gap-3">
        <button
          onClick={reset}
          className="rounded bg-ink px-4 py-2 text-sm text-paper hover:opacity-90"
        >
          Try again
        </button>
        <a
          href="/"
          className="rounded border border-dormant/50 px-4 py-2 text-sm hover:border-ink"
        >
          Back to the marketplace
        </a>
      </nav>
      {error.digest ? (
        <p className="font-data mt-8 text-xs text-dormant">
          reference {error.digest}
        </p>
      ) : null}
    </main>
  );
}

"use client";

import { useEffect, useState } from "react";
import { usePublicClient } from "wagmi";

/// The timestamp the chain believes, which is the only clock that matters for
/// a deadline.
///
/// The contract checks a deadline against `block.timestamp`, so computing one
/// from the visitor's own clock means a machine running a few minutes slow
/// gets DeadlineTooSoon and no explanation. Reading it from the chain also
/// makes the job panel agree with the kernel about whether an escrow can be
/// reclaimed yet.
///
/// Returns null until the first block is read, so callers can wait rather
/// than guess.
export function useChainTime(refreshMs = 15_000): number | null {
  const client = usePublicClient();
  const [seconds, setSeconds] = useState<number | null>(null);

  useEffect(() => {
    if (!client) return;
    let live = true;

    async function read() {
      try {
        const block = await client!.getBlock({ blockTag: "latest" });
        if (live) setSeconds(Number(block.timestamp));
      } catch {
        // A failed read leaves the previous value in place. The caller shows
        // a waiting state rather than a wrong time.
      }
    }

    void read();
    const t = setInterval(read, refreshMs);
    return () => {
      live = false;
      clearInterval(t);
    };
  }, [client, refreshMs]);

  return seconds;
}

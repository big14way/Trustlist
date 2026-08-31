"use client";

// The one orchestrated moment: the registered count collapses to the
// answering count over about 900ms, once per session. Both numbers are real
// and arrive from the API; with reduced motion the final state renders
// immediately. Nothing else on the site animates beyond hover states.

import { useEffect, useRef, useState } from "react";

export function CollapseCounter({
  registered,
  answering,
}: {
  registered: number;
  answering: number;
}) {
  // Starts at the answering count, not the registered one. This number is
  // rendered on the server and sits in the HTML until React takes over, and
  // the sentence around it reads "<value> of 321,772 registered agents
  // answer when probed". Starting at the registered count made that sentence
  // claim every agent answers, which is the exact opposite of the finding
  // this product exists to report. Anyone reading without JavaScript, any
  // scraper, and a screen reader arriving before hydration saw that.
  //
  // The animation still runs: it jumps up to the registered count on mount
  // and falls back down. The truthful value is what survives if the
  // animation never happens.
  const [value, setValue] = useState(answering);
  const [done, setDone] = useState(false);
  const ran = useRef(false);

  useEffect(() => {
    if (ran.current) return;
    ran.current = true;
    const reduced = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    const seen = sessionStorage.getItem("collapse-ran") === "1";
    if (reduced || seen) {
      setValue(answering);
      setDone(true);
      return;
    }
    sessionStorage.setItem("collapse-ran", "1");
    setValue(registered);
    const start = performance.now();
    const duration = 900;
    const tick = (t: number) => {
      const k = Math.min(1, (t - start) / duration);
      // Ease out so the last digits settle rather than snap.
      const eased = 1 - Math.pow(1 - k, 3);
      setValue(Math.round(registered - (registered - answering) * eased));
      if (k < 1) {
        requestAnimationFrame(tick);
      } else {
        setDone(true);
      }
    };
    requestAnimationFrame(tick);
  }, [registered, answering]);

  return (
    <span className="font-data" aria-live="polite" data-done={done}>
      {value.toLocaleString()}
    </span>
  );
}

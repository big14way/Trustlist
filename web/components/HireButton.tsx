"use client";

import { useState } from "react";
import { HireSheet } from "./HireSheet";

/// The hire entry point. Lives on the marketplace card as well as the agent
/// page, because discovery to hire in one click is the thing being measured.
export function HireButton({
  agentId,
  agentName,
  provider,
  variant = "primary",
}: {
  agentId: string;
  agentName: string;
  provider: string;
  variant?: "primary" | "compact";
}) {
  const [open, setOpen] = useState(false);
  const cls =
    variant === "compact"
      ? "rounded border border-ink px-3 py-1 text-sm hover:bg-ink hover:text-paper"
      : "rounded bg-ink px-5 py-2 text-paper hover:opacity-90";
  return (
    <>
      <button
        className={cls}
        onClick={(e) => {
          e.preventDefault();
          setOpen(true);
        }}
      >
        Hire
      </button>
      {open ? (
        <HireSheet
          agentId={agentId}
          agentName={agentName}
          provider={provider as `0x${string}`}
          onClose={() => setOpen(false)}
        />
      ) : null}
    </>
  );
}

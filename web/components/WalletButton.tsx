"use client";

import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { activeChain } from "@/lib/chain";

/// One wallet control for the whole site. Connected: the address, the
/// chain if it is the wrong one, and a way out. Not connected: a single
/// button. Browsing needs no wallet, so this never blocks anything; it is
/// here so a visitor can see who they are before pressing Hire and can find
/// their jobs without opening a checkout first.
export function WalletButton({ compact = false }: { compact?: boolean }) {
  const { address, isConnected, chainId } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();

  const base =
    "eyebrow rounded border px-3 py-1.5 transition-colors disabled:opacity-50";

  if (!isConnected || !address) {
    if (connectors.length === 0) {
      return (
        <span className="eyebrow text-dormant" title="No browser wallet found">
          NO WALLET
        </span>
      );
    }
    return (
      <button
        type="button"
        onClick={() => connectors[0] && connect({ connector: connectors[0] })}
        disabled={isPending}
        className={`${base} border-ink bg-ink text-paper hover:opacity-90`}
      >
        {isPending ? "Connecting" : "Connect wallet"}
      </button>
    );
  }

  const wrongNetwork = chainId !== activeChain.id;
  const short = `${address.slice(0, 6)}…${address.slice(-4)}`;

  return (
    <span className="flex items-center gap-2">
      {wrongNetwork ? (
        <button
          type="button"
          onClick={() => switchChain({ chainId: activeChain.id })}
          className={`${base} border-flag text-flag hover:bg-flag/10`}
          title={`Switch to ${activeChain.name}`}
        >
          Wrong network
        </button>
      ) : null}
      <span
        className="font-data text-xs"
        title={address}
        data-testid="wallet-address"
      >
        {short}
      </span>
      {compact ? null : (
        <button
          type="button"
          onClick={() => disconnect()}
          className={`${base} border-dormant/50 hover:border-ink`}
        >
          Disconnect
        </button>
      )}
    </span>
  );
}

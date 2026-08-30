"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";
import { WagmiProvider, createConfig, fallback, http } from "wagmi";
import { bsc } from "wagmi/chains";
import { injected } from "wagmi/connectors";
import { devChain } from "@/lib/chain";

// Two providers, always, and the browser gets the same treatment the backend
// gets. Until this was a fallback the app used viem's single built in
// endpoint for BSC: one bad minute at one provider and every read in the
// wallet path failed with nothing behind it.
//
// viem's fallback ranks by health and moves on by itself, so an outage at
// the first one is invisible rather than fatal. Both were answering when
// this was written; see docs/VERIFICATION.md section 10 for how the BSC
// endpoints were compared.
const PRIMARY_RPC =
  process.env.NEXT_PUBLIC_BSC_RPC ?? "https://bsc-rpc.publicnode.com";
const FALLBACK_RPC = "https://bsc-dataseed.bnbchain.org";

// Both chains are configured so the wallet can be on either. Which one we
// ask the user to switch to is decided by activeChain in lib/chain.
const wagmiConfig = createConfig({
  chains: [bsc, devChain],
  connectors: [injected()],
  transports: {
    [bsc.id]: fallback([http(PRIMARY_RPC), http(FALLBACK_RPC)]),
    [devChain.id]: http(),
  },
  ssr: true,
});

export function Providers({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());
  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </WagmiProvider>
  );
}

"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";
import { WagmiProvider, createConfig, http } from "wagmi";
import { bsc } from "wagmi/chains";
import { injected } from "wagmi/connectors";
import { devChain } from "@/lib/chain";

// Both chains are configured so the wallet can be on either. Which one we
// ask the user to switch to is decided by activeChain in lib/chain.
const wagmiConfig = createConfig({
  chains: [bsc, devChain],
  connectors: [injected()],
  transports: {
    [bsc.id]: http(),
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

import type { NextConfig } from "next";

// wagmi's connector barrel optionally imports an SDK per wallet family. We
// support injected browser wallets, so the rest are genuinely absent and we
// tell the bundler so. wagmi already handles the missing branch at runtime.
const UNUSED_CONNECTOR_SDKS = [
  "accounts",
  "@base-org/account",
  "@coinbase/wallet-sdk",
  "@metamask/connect-evm",
  "@safe-global/safe-apps-provider",
  "@safe-global/safe-apps-sdk",
  "@walletconnect/ethereum-provider",
  "pino-pretty",
];

const nextConfig: NextConfig = {
  // The verify gate compiles into its own directory so a production build
  // never clobbers the .next directory a running dev server is serving from.
  distDir: process.env.NEXT_BUILD_DIR ?? ".next",
  webpack: (config) => {
    config.resolve.alias = {
      ...config.resolve.alias,
      ...Object.fromEntries(UNUSED_CONNECTOR_SDKS.map((m) => [m, false])),
    };
    return config;
  },
};

export default nextConfig;

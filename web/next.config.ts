import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // The verify gate compiles into its own directory so a production build
  // never clobbers the .next directory a running dev server is serving from.
  distDir: process.env.NEXT_BUILD_DIR ?? ".next",
};

export default nextConfig;

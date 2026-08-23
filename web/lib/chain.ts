import { defineChain } from "viem";
import { bsc } from "viem/chains";

// Which chain the hire flow talks to. Mainnet is the default so the product
// is never a toy; a local dev chain is used for development and the end to
// end suite, where a self dealt balance is the correct thing to have.
const CHAIN_ID = Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? "56");

export const devChain = defineChain({
  id: 31337,
  name: "TrustList dev chain",
  nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 },
  rpcUrls: { default: { http: ["http://localhost:8545"] } },
});

export const activeChain = CHAIN_ID === 31337 ? devChain : bsc;
export const isDevChain = CHAIN_ID === 31337;

/// Deployed addresses, supplied by environment so the same build can point
/// at a local chain or mainnet. Empty means the hire flow is not configured
/// and the UI says so rather than failing at signing time.
export const HIRE_RAIL = (process.env.NEXT_PUBLIC_HIRE_RAIL ?? "") as
  `0x${string}` | "";
export const PAYMENT_TOKEN = (process.env.NEXT_PUBLIC_PAYMENT_TOKEN ?? "") as
  `0x${string}` | "";

export const hireConfigured = HIRE_RAIL !== "" && PAYMENT_TOKEN !== "";

/// Minimal ERC-20 surface the checkout needs. Exact amounts only: the
/// approval is always for the precise budget, never an open ended allowance.
export const erc20Abi = [
  {
    type: "function",
    name: "allowance",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "value", type: "uint256" },
    ],
    outputs: [{ type: "bool" }],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "decimals",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint8" }],
  },
  {
    type: "function",
    name: "symbol",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "string" }],
  },
] as const;

export function explorerTx(hash: string): string {
  return isDevChain ? `#local-tx-${hash}` : `https://bscscan.com/tx/${hash}`;
}

export function explorerAddress(addr: string): string {
  return isDevChain
    ? `#local-address-${addr}`
    : `https://bscscan.com/address/${addr}`;
}

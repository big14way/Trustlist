import { encodeFunctionData, keccak256, toHex } from "viem";

const RPC = process.env.DEV_RPC ?? "http://localhost:8545";

async function rpc(method: string, params: unknown[]): Promise<unknown> {
  const res = await fetch(RPC, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  const body = (await res.json()) as {
    result?: unknown;
    error?: { message: string };
  };
  if (body.error) throw new Error(`${method}: ${body.error.message}`);
  return body.result;
}

const kernelAbi = [
  {
    type: "function",
    name: "submit",
    stateMutability: "nonpayable",
    inputs: [
      { name: "jobId", type: "uint256" },
      { name: "deliverable", type: "bytes32" },
      { name: "optParams", type: "bytes" },
    ],
    outputs: [],
  },
] as const;

const erc20BalanceAbi = [
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
] as const;

/// Have the agent deliver, exactly as a real provider would: a submit call
/// to the ERC-8183 kernel signed by the provider address. The address comes
/// from the real registry, so the local chain impersonates it.
export async function agentDelivers(
  kernel: string,
  provider: string,
  jobId: string,
): Promise<void> {
  await rpc("anvil_impersonateAccount", [provider]);
  await rpc("anvil_setBalance", [provider, "0xde0b6b3a7640000"]);
  const data = encodeFunctionData({
    abi: kernelAbi,
    functionName: "submit",
    args: [BigInt(jobId), keccak256(toHex("delivered artifact")), "0x"],
  });
  const hash = (await rpc("eth_sendTransaction", [
    { from: provider, to: kernel, data },
  ])) as string;
  await rpc("anvil_stopImpersonatingAccount", [provider]);
  if (!hash) throw new Error("submit produced no transaction");
}

export async function tokenBalance(
  token: string,
  who: string,
): Promise<bigint> {
  const data = encodeFunctionData({
    abi: erc20BalanceAbi,
    functionName: "balanceOf",
    args: [who as `0x${string}`],
  });
  const out = (await rpc("eth_call", [
    { to: token, data },
    "latest",
  ])) as string;
  return BigInt(out);
}

export async function mineABlock(): Promise<void> {
  await rpc("anvil_mine", []);
}

/// Move the chain forward. The job panel decides whether the deadline has
/// passed, and the kernel decides whether the refund is claimable, so a test
/// about expiry has to advance both this and the browser clock.
export async function advanceChain(seconds: number): Promise<void> {
  await rpc("evm_increaseTime", [seconds]);
  await rpc("anvil_mine", []);
}

/// The timestamp the chain currently believes, which is the one the kernel
/// compares a deadline against.
export async function chainTime(): Promise<number> {
  const block = (await rpc("eth_getBlockByNumber", ["latest", false])) as {
    timestamp: string;
  };
  return Number(BigInt(block.timestamp));
}

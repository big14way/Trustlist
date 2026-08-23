/// A minimal EIP-1193 provider for end to end tests. It proxies every call
/// to the local dev chain, whose development accounts are unlocked, so anvil
/// signs and no private key is ever handled by the test or the browser.
/// This stands in for a browser wallet extension; everything downstream of
/// it, the app, the contract, and the chain, is the real thing.
export const injectedWalletScript = (rpcUrl: string, account: string) => `
(() => {
  const RPC = ${JSON.stringify(rpcUrl)};
  const ACCOUNT = ${JSON.stringify(account)};
  let nextId = 1;

  async function rpc(method, params) {
    const res = await fetch(RPC, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: nextId++, method, params: params || [] }),
    });
    const body = await res.json();
    if (body.error) {
      const err = new Error(body.error.message || "rpc error");
      err.code = body.error.code;
      err.data = body.error.data;
      throw err;
    }
    return body.result;
  }

  const listeners = {};
  const provider = {
    isMetaMask: true,
    isTrustListTestWallet: true,
    request: async ({ method, params }) => {
      switch (method) {
        case "eth_requestAccounts":
        case "eth_accounts":
          return [ACCOUNT];
        case "wallet_requestPermissions":
          return [{ parentCapability: "eth_accounts" }];
        case "wallet_switchEthereumChain":
        case "wallet_addEthereumChain":
          return null;
        default:
          return rpc(method, params);
      }
    },
    on: (event, handler) => {
      (listeners[event] = listeners[event] || []).push(handler);
    },
    removeListener: (event, handler) => {
      listeners[event] = (listeners[event] || []).filter((h) => h !== handler);
    },
  };

  Object.defineProperty(window, "ethereum", {
    value: provider,
    writable: false,
    configurable: true,
  });
  window.dispatchEvent(new Event("ethereum#initialized"));
})();
`;

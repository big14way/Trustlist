# Section 27 verification results

Verified 17 August 2026. Every fact below was checked against a live source on that date. Anything that could not be confirmed is marked as such.

## 1. Hackathon page

- https://www.bnbchain.org/en/hackathons/smart-money-era is live. Build window 5 Aug to 9 Sep 2026 (UTC+0), judging 9 to 23 Sep, winner 5 Nov. All prize figures in SPEC.md Section 2 match: main 30,000 USDT plus official adoption, TermiX 10,000 USDT (split 6k/3k/1k), PancakeSwap 1,000 CAKE, Altana 50,000 XP, AltLayer Pro plans plus free Pro tier API access (500 req/min, 100k req/day).
- Judging criteria on the page: Functionality (frictionless end to end journey), Data Quality (real time, accurate agent data), Agent Diversity across four categories, which the page names as rebalancing, grid trading, yield optimization, health factor monitoring. Exact percentage weights: not published.
- Submissions must be functional and publicly accessible during judging, agents live on BSC, one entry per team, entry via intake form.
- No reference agent repo could be located as of this date.

## 2. ERC-8004 on BSC mainnet

- Identity Registry `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432`: confirmed, ERC-1967 UUPS proxy, implementation `0x7274e874CA62410a93Bd8bf61c69d8045E399c02` (`IdentityRegistryUpgradeable`), Sourcify exact match, impl deployed at block 78,255,281. name() is "AgentIdentity", symbol "AGENT".
- Reputation Registry `0x8004BAa17C55a88189AE136b182e5fdA19dE9b63`: confirmed, same proxy pattern, implementation `0x16e0FA7f7C56B9a767E34B192B51f921BE31dA34` (`ReputationRegistryUpgradeable`), Sourcify exact match, impl deployed at block 79,027,282.
- Both are the canonical BSC deployments per the erc-8004/erc-8004-contracts README. Proxy deployment blocks could not be pinned down with public RPCs (no archive binary search, BscScan blocked automated fetch); resolve with a BscScan API key during M0.
- Event signatures from verified source:
  - `Registered(uint256 indexed agentId, string agentURI, address indexed owner)`, topic0 `0xca52e62c367d81bb2e328eb795f7c7ba24afb478408a26c0e201d155c449bc4a`
  - `NewFeedback(uint256 indexed agentId, address indexed clientAddress, uint64 feedbackIndex, int128 value, uint8 valueDecimals, string indexed indexedTag1, string tag1, string tag2, string endpoint, string feedbackURI, bytes32 feedbackHash)`, topic0 `0x6a4a61743519c9d648a14e6493f47dbe3ff1aa29e7785c96c8326a205e58febc`
  - Also `URIUpdated`, `MetadataSet` (identity), `FeedbackRevoked`, `ResponseAppended` (reputation).
- No `totalSupply()`: the contract is ERC-721 but not Enumerable. The registered count lives in ERC-7201 namespaced storage `erc8004.identity.registry`, first struct member `uint256 _lastId`, slot `0xa040f782729de4970518741823ec1276cbcd41a0c7493f62d173341566a04e00`.
- Testnet: the registries are NOT deployed at these addresses on BSC Chapel (eth_getCode returned 0x). Testnet plan needs its own registry deployment or different addresses.

## 3. Registered agent count (task 11)

Read directly from chain 17 Aug 2026 at about block 116,527,300: `_lastId` = 269,234. IDs are sequential, so about 269,234 agents have been registered on BSC. This is a last-assigned-id read, not burn adjusted. This is our number for the headline until the indexer produces its own count.

## 4. ERC-8183 and BNBAgent SDK

- EIP-8183 "Agentic Commerce" exists, status Draft. Job states Open, Funded, Submitted, Completed, Rejected, Expired.
- Kernel proxy `0xea4daa3100a767e86fded867729ae7446476eba6` has bytecode on BSC mainnet, ERC-1967 proxy, implementation `0xd5f9b570c96b5d67702d508c0bfb8b3b09209787`. Matches the SDK's own address registry (`python/bnbagent/networks/addresses.py`).
- EvaluatorRouter proxy: `0x51895229e12f9876011789b04f8698af06ccd6da`. OptimisticPolicy: `0x9c01845705b3078aa2e8cff7520a6376fd766de5`. Payment token "United Stables" (U): `0xcE24439F2D9C6a2289F741120FE202248B666666`.
- github.com/bnb-chain/bnbagent-sdk exists (Python plus TypeScript, MIT, active). PyPI `bnbagent` 0.4.2 (6 Aug 2026), npm `@bnbagent/sdk`.
- Job lifecycle in `ERC8183Client`: `create_job`, `register_job`, `set_provider`, `set_budget`, `fund`, `submit`, `settle`, `cancel_open`, `claim_refund`, `mark_expired`, `dispute`, `vote_reject`, plus reads. Creating and funding a job is several calls, which is exactly why HireRail wraps it into one transaction.

## 5. Binance x402 (B402)

- https://www.binance.com/en/binancex402 is live, network `eip155:56`. Stablecoins on BSC: U, USD1, USDT, USDC.
- Auth methods per launch coverage (Binance's own API reference was not reachable to automation): U and USD1 support eip3009, permit2-exact, permit2-upto. USDT and USDC support permit2-exact and permit2-upto only (no EIP-3009 on those BSC tokens).
- permit2-upto IS bounded: the client signs a maximum, settlement must be at or below it, Permit2 nonce enforces single use. The spec's "never permit2-upto" rule can soften to "never sign an upto with a ceiling larger than the session budget".

## 6. Altana

- Real, listed on bnbchain.org/en/wallets under Agentic Wallets. Site altana.network, docs docs.altana.network, SDK `@altananetwork/sdk` 0.7.1 on npm, MCP server `@altananetwork/mcp`.
- Added to BNB Agent Studio v2 on 13 Aug 2026, as the spec claimed.
- Sessions: `client.grantSession({ wallet, signer, sessionSigner, permissions: { calls: [{to}], spend: [{limit, period}] }, expiry })` writes the policy on chain to the Keystore registry and returns a transaction hash. Enforcement is at the on chain validator (over-cap, unauthorized target, or expired calls revert). Revoke: `client.revokeSession(...)`, one transaction, immediate and permanent. Spend limits are period based (for example per day) with contract allowlists.
- Explorer: explorer.altana.network (mainnet, indexes BSC and Ethereum), testnet.altana.network. Patterns: `/account/<address>`, `/key/<keyId>`. It is a human facing view, not an API.

## 7. PancakeSwap Infinity

- Confirmed on BSC. CLPositionManager `0x55f4c8abA71A1e923edC303eb4fEfF14608cC226`, BinPositionManager `0x3D311D6283Dd8aB90bb0031835C8e606349e2850`, Vault `0x238a358808379702088667322f80aC48bAd5e6c4`, CLPoolManager `0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b`, UniversalRouter `0xd9C500DfF816a1Da21A48A732d3498Bf09dc9AEB`.
- Liquidity via `IPositionManager.modifyLiquidities(bytes payload, uint256 deadline)` with encoded actions, Permit2 required. Hooks: 10 callbacks, template at github.com/pancakeswap/infinity-hooks-template.
- No Infinity specific subgraph exists in the docs. Pool data comes from the V3 subgraph (`thegraph.com/explorer/subgraphs/Hv1GncLY5docZoGtXjo4kwbTvxm3MAhVZqBZE4sUT9eZ`), quoter contracts, or the Unified Swap API. The yield scout should use those.

## 8. Agent0 and The Graph

- github.com/agent0lab/agent0-ts and docs.sdk.ag0.xyz exist. Subgraphs live on BSC, Base, Ethereum, Polygon, Monad.
- BSC subgraph id `D6aWqowLkWqBgcqmpNKXuNikPkob24ADXCciiP8Hvn1K` (agent0-bsc-mainnet), endpoint `https://gateway.thegraph.com/api/<API_KEY>/subgraphs/id/D6aWqowLkWqBgcqmpNKXuNikPkob24ADXCciiP8Hvn1K`. Requires a free Graph API key, no keyless endpoint.
- Schema: Agent has `agentURI` (not `tokenURI`), plus `agentId`, `owner`, `agentURIType`, linked `registrationFile { name description mcpTools supportedTrusts }`, `feedback`, validations.
- Decision: backfill from raw logs as primary (we own the data and the freshness), use the subgraph as the cross check rather than the source, since it needs an API key and its card parsing choices are not ours. Revisit if log backfill is too slow on PublicNode.

## 9. 8004scan

- 8004scan.io live, covers BSC. Public API at api.8004scan.io (OpenAPI at /openapi.json), reads need no auth: `/api/v1/agents?chain_id=56`, `/api/v1/agents/{chain_id}/{token_id}`, semantic search, trending, leaderboard.
- Deep link format: `https://8004scan.io/agents/bsc/{token_id}` (slug is `bsc`, not `bnb`). The site is an SPA that returns 200 for any path, so validate by content, not status code.

## 10. RPC endpoints (task 9)

Tested with a real 2000 block eth_getLogs (address filtered):

- WORKS: `https://bsc-rpc.publicnode.com` (mainnet), `https://bsc-testnet-rpc.publicnode.com` (Chapel, with an address filter).
- FAILS at that range: bsc-dataseed.bnbchain.org (limit exceeded), binance.llamarpc.com, bsc.drpc.org (rate limit), 1rpc.io/bnb (50 block cap), data-seed-prebsc-1-s1.bnbchain.org.
- Recommendation: PublicNode as primary, Alchemy (paid, BNB Chain support with archive) as fallback. Always include an address filter on getLogs.

## 11. arXiv preprints (task 10)

- arXiv:2606.26028 exists with the exact claimed title. Confirmed from the abstract: live endpoints 3% Ethereum, 4% BSC, 15% Base; Sybil reviewers 59.2% on BSC (73.5% Ethereum, 90.6% Base); after removing Sybil flagged feedback 77.9% of rated BSC agents have no valid feedback. Data window ends 13 May 2026.
- Registration counts in the paper: Ethereum 32,343, BSC 90,145, Base 50,985. The spec's "roughly 200,000 on BSC" is wrong as a paper citation. The chain itself now shows about 269,234 (see item 3), so the honest framing is: the paper measured 90,145 through 13 May 2026, the registry has since grown to about 269,000 by our own chain read, and the percentages are the paper's, to be reproduced by our prober.
- arXiv:2606.12128 exists with the exact claimed title, but it studies Ethereum only and its abstract has no percentages. Cite it for the "registration heavy, operationally shallow" framing, never for a BSC number.

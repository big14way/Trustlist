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

## 12. Follow up round, 17 August 2026 (after review)

### Category taxonomy, settled with verbatim quotes
BNB Chain's own sources disagree. The hackathon page lists, verbatim: "Rebalancing: Manages LP ranges, resets positions automatically", "Grid Trading: Places and manages automated grid orders", "Yield Optimisation: Routes liquidity to the highest available APR", "Health Factor Monitoring: Protects lending positions from liquidation". The launch blog lists, verbatim: "Monitoring agents: watching markets, wallets, and positions", "Grid trading agents: running automated strategies within set ranges", "Health factor agents: tracking loan positions and acting before liquidation", "Yield agents: moving capital to where it earns most". The Chainwire release matches the blog. Resolution: support the union (monitoring, rebalancing, grid-trading, yield, health-factor, plus pancakeswap and other); the page's four must all have live agents at demo time.

### Rubric and reference agents, rechecked after build period opened
- Main track: criteria named (Functionality, Data Quality, Agent Diversity; Chainwire adds "real-world usage") but no numeric weights published anywhere as of 17 Aug 2026. Recheck weekly.
- TermiX track rubric IS published, verbatim: "Value of the services: 30%", "Proven agent advantage: 30%", "High-stakes categories & track record: 20%", "Marketplace quality: 20%".
- Reference agents repo: still not findable. Every outbound link on the hackathon page was enumerated; the only GitHub links are the Altana SDK and TermiX bsc-mcp (partner tooling). Also found on the page: docs.altana.network/sdk/erc8183 and /sdk/x402-server (the Altana SDK covers ERC-8183 and x402 server side), skills.altana.network, and the intake form (forms.gle/jQevEPCAacBXaKG79).

### Sampled liveness measurement (our own, first cut)
Method: 300 agent ids drawn uniformly (seed 8004) from 1..269,234; tokenURI read via eth_call; cards fetched (https, ipfs, data URIs); declared URLs probed with the Section 12 aliveness rule and SSRF guard. Script: scripts/sample_liveness.py, raw results: scripts/sample_liveness_results_2026-08-17.json.

Results: 293 of 300 had a tokenURI. 178 (59 percent) were inline data URIs declaring no endpoints at all. 11 cards unreachable, 2 returned 404, 6 invalid schemes, 3 timed out. 19 agents declared endpoints that were all down. 85 (28.3 percent, CI 23.2 to 33.4) had at least one declared URL that answered, BUT 81 of those 85 are bulk registrations by one operator (EvoEvo) whose only declared service is a web profile page on evoevo.ai, and 3 more are QuackAI metadata URLs. Only 1 of 300 declared anything resembling an independent agent service endpoint that answered.

Reading: under the paper's loose definition (any live declared endpoint) the share is now roughly 28 percent, inflated by one farm's website answering for 81 registrations. Under a strict definition (a working agent service, not an operator profile page) the live share is at or below about 1.3 percent, lower than the paper's 4 percent, consistent with the prediction that post May growth is placeholder heavy. The thesis holds and sharpens. Consequence for the product: the prober classifies endpoint kind (service, web, metadata) and clusters agents by endpoint host, and we publish an operator concentration figure. This first cut is a sample; the real prober measures the full registry and that number becomes the headline.

### Paper version pin
arXiv:2606.26028 v1 and v2 differ on BSC figures (no valid feedback after filtering: 72.3 percent in v1, 77.9 percent in v2). We cite v2 (revised 8 July 2026) everywhere, explicitly.

## 13. Settlement timing on the live ERC-8183 stack (23 August 2026)

Four independent investigations plus two adversarial verification passes, all
run against BSC mainnet or a fork of it. Two verifiers independently
recompiled the deployed bytecode from `bnb-chain/apex-contracts` and matched
it at all three addresses after masking immutables.

### The seven day window is real, exact, and not ours to change

- `OptimisticPolicy.disputeWindow()` = 604800 seconds, and it is an
  `immutable` baked into the deployed bytecode (readable in the immutable
  references). There is no setter, and the contract is not a proxy (4413
  bytes, empty implementation slot), so it cannot be upgraded either.
- `check()` has exactly one path that returns APPROVE, behind an
  unconditional `block.timestamp >= submittedAt + 604800`. The `evidence`
  argument is commented out and cannot influence the verdict; a verifier
  fuzzed 256 random inputs and the verdict never moved.
- `router.settle()` reverts `NotDecided()` at one second before the window
  and succeeds one second after. Measured on a fork, both sides.
- Registering a faster policy is blocked: `setPolicyWhitelist` is owner only.
  The router owner, the kernel owner, and the policy admin are all the same
  address, `0x5057b09A4b510ccaf7e3fb3038Ba60713E62B1fc`. That address could
  whitelist a zero window policy; we cannot. Worth asking the deployer for,
  not something to design around.
- Testnet policy `0xd6a4217588F6B1F5657a92A3e94E6422aD771cEA` uses 900
  seconds with quorum 1, so testnet timing does not predict mainnet timing.

### There is a legitimate faster path, and it is same block

The kernel contains no time logic at all. `complete(jobId, reason, params)`
has exactly one authorisation check: `msg.sender == job.evaluator`. The
evaluator is whatever address the caller passes to `createJob`, written once
and never mutable. A verifier called `complete` on live mainnet jobs with
411,571 seconds still on their dispute windows and it succeeded.

Two gates make this harder than it looks, and both are enforced only by the
real kernel, so a mock will not catch them:

- `createJob` requires a non zero hook that answers ERC-165 for the
  `IACPHook` interface id `0x7ff6bc9e`. A zero address reverts
  `HookRequired()`, an EOA or a plain contract reverts
  `HookMissingInterface()`.
- The only `IACPHook` already deployed on mainnet is the EvaluatorRouter
  itself, and its `beforeAction` reverts `PolicyNotSet()` when funding a job
  it does not evaluate. So a job with a non router evaluator needs its own
  hook. That is what `TrustListHook` is for.

`complete()` also requires the job to be in SUBMITTED, so the provider's
submission cannot be skipped.

### What we built as a result

`HireRail` offers both, and the difference is stated to the user rather than
buried:

- **Direct**: the rail is the evaluator and `TrustListHook` is the hook.
  The only code path that releases escrow is `accept`, which reverts for
  anyone but the recorded hirer. Payout lands in the same block. The agent
  is trusting the hirer. This is not dispute protected and must never be
  described as such.
- **Protected**: the router is evaluator and hook, the whitelisted
  OptimisticPolicy decides, settlement is permissionless once the seven day
  window closes, and neither side can act unilaterally.

A protected job whose deadline falls inside the dispute window expires before
it can settle, which would strand escrow for a week. `HireRail` reads
`disputeWindow()` from the policy at deployment and rejects those hires with
`DeadlineTooSoon()`.

Proven end to end against the live mainnet contracts in
`contracts/test/HireRailFork.t.sol`: seven tests, including same block payout
in direct mode, the full seven day wait in protected mode, and the fact that
neither the contract owner nor the agent can release a direct escrow.

Other live values confirmed: `platformFeeBP` is 0 so the provider receives
the entire budget, `MAX_EXPIRY_DURATION` is 31536000, `createJob` rejects any
deadline not strictly more than five minutes out, and `claimRefund` is
permissionless and not pausable. The payment token U is an upgradeable proxy
with a live `paused()` (currently false) owned by
`0x59F94AdE4F881f21ea608AD4448bf70B78e37187`, so settlement depends on a
token we do not control. That belongs in the risk section of the submission.

## 14. PancakeSwap data sources and addresses (23 August 2026)

Verified before the reference agents were written.

- **Pool data.** PancakeSwap's own explorer serves live V3 pool statistics for
  BSC with no API key at
  `https://explorer.pancakeswap.com/api/cached/pools/v3/bsc/list/top`,
  returning 33 top pools with TVL, 24 hour and 7 day volume, fees, current
  tick, sqrtPrice, and liquidity. `api.pancakeswap.info` returns 500 and
  `configs.pancakeswap.com/api/data/cached/farms` returns 400, so neither is
  usable. There is still no Infinity specific subgraph.
- **NonfungiblePositionManager on BSC:**
  `0x46A15B0b27311cedF172AB29E4f4766fbE7F4364`. The developer docs list three
  candidates without labelling the chain, so all three were called on BSC
  mainnet: this one answers `name()` with "Pancake V3 Positions NFT-V1",
  `symbol()` with "PCS-V3-POS", and `totalSupply()` with 4,903,899. The other
  two (`0xa815e2eD...2883`, `0x427bF5b3...96c1`) have no meaningful bytecode
  on BSC and belong to other chains.
- **PancakeV3Factory on BSC:** `0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865`,
  confirmed by resolving USDT/WBNB at the 0.05 percent tier to pool
  `0x36696169C63e42cd08ce11f5deeBbCeBae652050`.
- **Position reads work end to end.** Position 7238953 reads as CAKE/USDT at
  the 0.25 percent tier, ticks 4850 to 5450, liquidity 8.066e21, in pool
  `0x7f51c8aaa6b0599abd16674e2b17fec7a9f674a1`, whose current tick was 5459 at
  the time of writing. That position is genuinely out of range, which is what
  the Range Keeper reports.
- `totalSupply()` on the position manager counts live NFTs, not the highest
  token id, so enumerating positions has to go through `tokenByIndex`.
  Guessing an id near the supply returns "Invalid token ID".

# Submission

TrustList is an ERC-8004 agent marketplace for BNB Smart Chain that measures which agents are actually alive, weights reviews by how independent the reviewer is, and hires through ERC-8183 escrow.

This document is the honest state of the build. Items that are not done say so. Nothing here is aspirational.

Last updated 28 August 2026.

## Where things stand

| Requirement | State |
|---|---|
| README with the problem, evidence, architecture, and how to run it | done |
| `docs/ADDRESSES.md` with every address, checked against chain by the gate | done, 17 addresses verified live |
| `docs/METHODOLOGY.md` and `/methodology` agree | done, both render from `crates/common/src/methodology.rs` |
| `scripts/audit_data.sh` run, table pasted below | done, 10 passed, 0 failed, 1 skipped |
| `make verify` passes | done |
| Contract line coverage on `contracts/src` | 100 percent |
| Golden journeys | all 5 written, 4 pass, journey 02 skips (Altana relay unreachable and wallet unfunded) |
| Contracts deployed to BSC mainnet | **not done**, waiting on funding |
| Contracts verified on BscScan | **not done**, follows deployment |
| Two mainnet transactions inside the window | **not done**, waiting on funding |
| Altana session and revoke hashes | **not done**, page and scoped permissions built, grant needs funds and a reachable relay |
| `docs/ADVANTAGE_REPORT.md` with three real tasks | **not done** |
| Judge mode | **not done** |
| Live deployment URL | **not done**, local only |
| Cold start test in a fresh container | script written, runs in the nightly CI job, not yet green under the spec's 5 minute budget |
| Stranger test with three people | **not done** |
| Zero dead ends table walked manually | **not done** |
| Demo video | **not done** |

The single blocker behind most of the "not done" rows is that the deployer account holds no BNB. The measured cost of the entire remaining on chain plan is 0.000176 BNB at the current 0.05 gwei, itemised in the funding note below.

## The data honesty audit

Passing a lint gate does not prove the numbers on screen are true. `scripts/audit_data.sh` takes live data and re-derives it independently. Chain reads go through PublicNode, which is not the provider the indexer uses, so a lying provider would not be able to confirm its own answer. The Merkle root is rebuilt with viem's keccak rather than the alloy keccak that built it.

Reproduce with `bash scripts/audit_data.sh`.

| check | expected | actual | result |
|---|---|---|---|
| 1. agent 305838 name | Shakibshawon.agent | Shakibshawon.agent | pass |
| 1. agent 305871 name | SRINU.agent | SRINU.agent | pass |
| 1. agent 305824 | card name | non-https tokenURI (data) | skipped |
| 1. agent 305854 name | Ahmed | Ahmed | pass |
| 1. agent 305870 name | SRINU.agent | SRINU.agent | pass |
| 2. uptime_7d agent 255618 | 0.000000 | 0 | pass |
| 3. trust agent 137 | 90.4094 | 90.4 | pass |
| 4. merkle root (snapshot 3) | 0x913d319a964f84c0cd29f7dceef9e3960d5a17e30370d2303ba27cc9f8b9b06c | 0x913d319a964f84c0cd29f7dceef9e3960d5a17e30370d2303ba27cc9f8b9b06c | pass |
| 5. verify agent 1 on chain | true | true | pass |
| 6a. API count matches our index | 305878 | 305878 | pass |
| 6b. registry _lastId cross check | 311064 | 305878 (behind head by 5186, 1.67 percent) | pass |

Reading the rows that matter:

**Check 3** recomputes a published trust score from the raw `feedback` and `reviewer_weights` rows, by hand, using the formula on the methodology page. It lands within 0.0094 of what the API serves.

**Check 4** rebuilds the Merkle root over all 17,286 leaves with a different keccak implementation and gets the same root. That is what makes check 5 meaningful.

**Check 6b** is two independent methods for the same quantity: our own count of indexed `Registered` events, and the registry's internal `_lastId` counter read straight from ERC-7201 storage slot `0xa040f782729de4970518741823ec1276cbcd41a0c7493f62d173341566a04e00`. They are read at different blocks, so the registry is always somewhat ahead. The gap, 1.67 percent, is how far behind head our indexer was at the time of the run.

The skipped row is honest: that agent's `tokenURI` is a `data:` URI rather than `https`, and this audit does not fetch through a gateway it cannot vouch for.

## Addresses

Every address is in `docs/ADDRESSES.md`, and `scripts/check_addresses.sh` calls the chain for each one as part of `make verify`. All 17 currently listed are confirmed live on BSC mainnet.

None of our own contracts are deployed to mainnet yet. The document lists them as not deployed and the checker asserts they have no bytecode, so it cannot silently go stale once they are.

## Snapshot root and proof

The trust engine builds a Merkle snapshot of every measured score each cycle. Only a published root proves anything, so `/v1/snapshots/latest` returns the newest published snapshot and reports the contract's own index.

Published on the local dev chain, 28 August 2026:

```
root         0x913d319a964f84c0cd29f7dceef9e3960d5a17e30370d2303ba27cc9f8b9b06c
agents       17,286
contract     0x2685352e856074a879e1a8fe737b7fca270aa77f (dev chain, chain id 31337)
on chain idx 1
```

Anyone can check a single agent without trusting our API:

```
curl -s localhost:8080/v1/snapshots/3/proof/1
```

The response carries the proof and the exact arguments `TrustSnapshot.verify` expects. The web app does this in the reader's own browser, from the agent page, and runs the same call a second time with the trust score changed to a perfect 10000 basis points to show that the proof rejects it.

The Rust publisher and the Solidity verifier are pinned against each other in `contracts/test/TrustSnapshot.t.sol`, so a change to either side that breaks agreement fails the build rather than silently invalidating every published proof.

## Golden journeys

Run with `make e2e` against a local chain.

| Journey | State |
|---|---|
| 01 discover and hire | passes, 15.9s |
| 02 session cap and revoke | written, skips with a stated reason: the Altana relay is not answering and the wallet is unfunded |
| 03 verify a score | passes, 1.5s |
| 04 reclaim an expired job | passes, 10.1s |
| 05 cold first visit, no wallet | passes, 4.6s |

Journey 01 prints its own discover-to-hired timing, which was 2.9 seconds on the last run. The spec's stranger-test target is a median under 90 seconds for a real person, which is a different and harder measurement that has not been run yet.

## Known gaps, stated plainly

- **Nothing of ours is on mainnet.** The hire flow runs against a local chain with a kernel and router that enforce the same rules the live ones do, and `HireRailFork.t.sol` proves the same HireRail code works against the real deployed ERC-8183 contracts on a mainnet fork. That is strong evidence, and it is not the same thing as a mainnet transaction.
- **`high_revocation` is published as a penalty but cannot currently fire.** There are zero revocations on the registry today. It is left in place and documented rather than removed, because removing a rule that has not yet had anything to catch would be the wrong lesson.
- **The cold start test does not meet the spec's 5 minute budget.** A machine that has never seen the repo compiles the whole Rust workspace, which dominates the time. Shipping prebuilt binaries as a release asset would fix it and has not been done.
- **The indexer runs behind head**, currently by about 1.67 percent of the registry. The audit reports the gap rather than hiding it.
- **Judge mode does not exist yet.** It needs a prefunded relayer.
- **The Altana session flow has never been seen to run.** The page, the scoped
  permissions, and the revoke path are written against the SDK's 0.8.0 types
  and type check against them, but two things stopped a live grant: the wallet
  needs native BNB, because the relay accepts no other fee token on any of its
  four chains, and every Altana host went unreachable partway through the
  build. Both are recorded with their evidence in `docs/VERIFICATION.md`
  section 16.

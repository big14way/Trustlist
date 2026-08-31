# Submission

TrustList is an ERC-8004 agent marketplace for BNB Smart Chain that measures which agents are actually alive, weights reviews by how independent the reviewer is, and hires through ERC-8183 escrow.

This document is the honest state of the build. Items that are not done say so. Nothing here is aspirational.

Last updated 31 August 2026.

## Where things stand

| Requirement | State |
|---|---|
| README with the problem, evidence, architecture, and how to run it | done |
| `docs/ADDRESSES.md` with every address, checked against chain by the gate | done, 17 addresses verified live |
| `docs/METHODOLOGY.md` and `/methodology` agree | done, both render from `crates/common/src/methodology.rs` |
| `scripts/audit_data.sh` run, table pasted below | done, 10 passed, 0 failed, 1 skipped |
| `make verify` passes | done |
| Contract line coverage on `contracts/src` | 100 percent |
| Golden journeys | all 5 written, 4 pass, journey 02 skips because the Altana wallet is unfunded |
| Contracts deployed to BSC mainnet | done, all three, 31 August 2026 |
| Contracts verified on BscScan | done, both with published source, confirmed by reading them back from the API |
| Two mainnet transactions inside the window | done, `hire` and `accept` on HireRail, job 56675 completed with escrow released. Nine transactions logged in `scripts/tx_log.md` |
| Altana session and revoke hashes | **not done**, zero grants ever signed. The page and scoped permissions are written and type check, the relay is answering again, the wallet needs BNB |
| x402 metered path | **not done**, not started. Both our agents declare `x402Support: false`, which is the truth |
| `docs/ADVANTAGE_REPORT.md` with three real tasks | **not done** |
| Judge mode | **not done** |
| Live deployment URL | **not done**, local only |
| The mainnet plan rehearsed end to end on a fork | done, `scripts/mainnet_rehearsal.sh` passes: deploy, register, hire, submit, accept, escrow released |
| Cold start test in a fresh container | done, 89s and 150s on two runs against the spec's 300s budget, nightly CI job |
| Stranger test with three people | **not done** |
| Zero dead ends table walked manually | done, 18 rows walked, 7 were broken and are fixed, `docs/DEAD_ENDS.md` |
| Demo video | **not done** |

The deployer was funded with 0.00074 BNB on 31 August 2026 and the first two contracts are live. What remains on chain is cheap; the blocker is no longer money but a public home for the reference agent, which the registry has to be able to fetch.

## What is on mainnet

| Contract | Address | Block | Gas |
|---|---|---|---|
| TrustListHook | `0x2685352E856074a879E1a8fe737B7fCA270Aa77f` | 119,125,487 | 145,579 |
| HireRail | `0x9fA9Cd8DDDd33eAc46C8c600371cc61ED79411e1` | 119,125,490 | 1,938,974 |

Both have verified source on BscScan. Every immutable on the rail was read
back off the chain rather than taken from the deploy log: kernel, router,
policy, hook and payment token all match the addresses in
`docs/ADDRESSES.md`, the owner is the deployer, and it is not paused. The
dispute window it reports is 604800 seconds, which it read from the live
OptimisticPolicy at construction.

The gas matched the fork rehearsal exactly, to the unit, which is the whole
reason the rehearsal existed.

One thing worth recording because it nearly caused an expensive mistake. The
deploy printed "Some transactions were discarded by the RPC node" and saved
no receipts, which reads like a failure. It was not: PublicNode refuses
receipt lookups as archive requests, the same limitation `docs/VERIFICATION.md`
section 18 records for forking. The transactions had landed. Retrying would
have deployed a second set and paid for it twice. The runbook says to check
the chain before retrying, and that is what settled it: nonce 2, the balance
down by exactly the execution gas, and code at both addresses.

## The first mainnet hire

Job 56675, 31 August 2026. A real ERC-8183 job against the real kernel, from
the marketplace's own rail, paid out of escrow.

| step | transaction | gas |
|---|---|---|
| register Yield Scout as agent 320964 | `0x3ded3df0..167a1bb0` | 203,460 |
| swap 0.0003 BNB into 0.2057 U | `0xcb4f1ad4..b0e450e0` | 136,387 |
| approve exactly 0.2 U | `0x12dee858..a006b9dbd` | 60,245 |
| `hire`, Direct mode | `0xa994fbcc..516824a9` | 471,330 |
| `submit`, signed by the agent owner | `0x96158b9b..598762e9` | 93,412 |
| `accept`, escrow released | `0x240010b2..9128abc1` | 101,008 |

The kernel reports the job as Completed. The 0.2 U went out of the hirer's
balance into escrow and came back to the provider in full, and HireRail was
left holding nothing, which is the same pair of assertions the fork test and
the rehearsal make.

Hirer and provider are the same address here, which is worth stating rather
than hiding: we hired our own agent. That is not a limitation of the rail,
it is a consequence of the only agent whose owner key we hold being one we
registered. `HireRailFork.t.sol` runs the two party case against the same
live kernel.

`hire` and `accept` are the two mainnet transactions from our own contract
that SPEC Section 29.2 asks for at M4.

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
| 02 session cap and revoke | written, runs further than before now that the relay is answering, and skips with a stated reason: the wallet holds no BNB, so no grant can be signed |
| 03 verify a score | passes, 1.5s |
| 04 reclaim an expired job | passes, 10.1s |
| 05 cold first visit, no wallet | passes, 4.6s |

Journey 01 prints its own discover-to-hired timing, which was 3.1 seconds on the last run. The spec's stranger-test target is a median under 90 seconds for a real person, which is a different and harder measurement that has not been run yet.

## The funding note

Every row below was measured on 30 August 2026, with BSC charging 0.05 gwei.
The rows marked "rehearsal" are gas actually burned by
`scripts/mainnet_rehearsal.sh`, which runs the entire plan against a fork of
mainnet using the real registry, the real kernel, the real router and the
real payment token. The method for each row is in `docs/VERIFICATION.md`
sections 17 and 18. The deployer,
`0xFC4884Ee9553a7B412C923980c1cDD7dee82cB94`, holds 0 wei and 0 U.

| step | transaction | gas | source |
|---|---|---|---|
| deploy | TrustListHook | 189,252 | forge estimate |
| deploy | HireRail | 2,520,666 | forge estimate |
| snapshot | TrustSnapshot | 1,177,953 | forge estimate |
| snapshot | publish the first root | 224,788 | forge estimate |
| setup | register our agent | 180,164 | rehearsal |
| setup | swap 0.002 BNB into U | 144,785 | `cast estimate` |
| demo | approve U | 60,245 | rehearsal |
| demo | `hire` | 471,090 | rehearsal |
| demo | `submit` | 93,412 | rehearsal |
| demo | `accept` | 118,108 | rehearsal |

One complete hire is 742,855 gas, which is 0.0000371 BNB. Deploying
everything and running the hire three times is 6,666,173 gas, or 0.00033 BNB.

The only real money is the job budget: 0.002 BNB buys about 1.39 U. The
rehearsal asserts the provider is paid in full with no fee taken, so hiring
our own agent returns the U every time and one purchase covers every run.

The `submit` row is the one that changed the plan. `accept` releases escrow
and the kernel will not complete a job that was never submitted, but
submitting is the provider's signature and the web app has no path for it,
correctly: it is the agent's side of the deal. Our e2e suite impersonates the
provider on a dev chain, which mainnet does not allow. So a mainnet hire can
only reach a payout against an agent whose owner key we hold, which makes
registering one of our own a prerequisite rather than a nice to have.

Ask for 0.01 BNB rather than 0.0004. BSC's gas price is near its floor, and
the Altana session grant and revoke are missing from the table entirely,
because the relay charges its fee in native BNB and no grant has ever
completed, so there is no measured number to enter.

## Known gaps, stated plainly

- **Nothing of ours is on mainnet.** The hire flow runs against a local chain with a kernel and router that enforce the same rules the live ones do, and `HireRailFork.t.sol` proves the same HireRail code works against the real deployed ERC-8183 contracts on a mainnet fork. That is strong evidence, and it is not the same thing as a mainnet transaction.
- **`high_revocation` is published as a penalty but cannot currently fire.** There are zero revocations on the registry today. It is left in place and documented rather than removed, because removing a rule that has not yet had anything to catch would be the wrong lesson.
- **The cold start is fast only while the prebuilt binaries are reachable.** A machine that has never seen the repo used to compile the whole Rust workspace, which was 419 of the 471 seconds it took. It now downloads binaries built for that exact commit and comes up in 89 to 150 seconds, measured on two runs. When the binaries are not reachable it still compiles, and that path took 274s and 466s on two runs, so the fallback is not reliably inside the budget: the download is what meets it. The download is refused unless the commit matches, the published checksum matches, and each binary runs and reports the commit it was built from, so the worst case is the old behaviour rather than a wrong one. The repository is public, so the download needs no credentials, which is the case that matters: a stranger following the README has none.
- **The indexer runs behind head**, currently by about 1.67 percent of the registry. The audit reports the gap rather than hiding it.
- **Judge mode does not exist yet.** It needs a prefunded relayer.
- **The Altana session flow has never been seen to run.** The page, the scoped
  permissions, and the revoke path are written against the SDK's 0.8.0 types
  and type check against them. Two things stopped a live grant, and one of
  them has since cleared. The relay is answering again as of 30 August 2026,
  which removes the outage recorded in `docs/VERIFICATION.md` section 16. What
  remains is funding: the relay accepts no fee token but the native coin on
  any of its four chains, so a grant needs BNB. Journey 02 now runs as far as
  that wall and skips there, having first checked that the page tells the
  reader why.

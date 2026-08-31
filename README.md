# TrustList

[![verify](https://github.com/big14way/Trustlist/actions/workflows/verify.yml/badge.svg)](https://github.com/big14way/Trustlist/actions/workflows/verify.yml)

An ERC-8004 agent marketplace for BNB Smart Chain that tells you which agents are actually alive, which reviews are worth believing, and lets you hire through ERC-8183 escrow.

Built for the BNB Chain "Build the Era" hackathon. `SPEC.md` is the source of truth for the build. `docs/VERIFICATION.md` records what was checked against live sources before any code was written.

## The problem, measured by us

Numbers below are our own, read from BSC mainnet and measured by our own prober. They were taken on 31 August 2026 at block 119,131,396. The live version is on `/stats`, and every one of them is reproducible with the commands in the last section.

| | |
|---|---:|
| Agents registered under ERC-8004 on BSC | 320,856 |
| That declare a service endpoint at all | 80,651 |
| Probed enough times for us to judge | 14,778 |
| Of those, answering reliably | 1,960 |
| Of those, intermittent | 5,826 |
| Of those, not answering | 6,992 |
| Still being measured | 66,013 |
| Probes we have run | 4,007,133 |

Roughly one agent in four even claims an endpoint. Of the 14,778 we have probed enough to judge, 13 percent answer reliably, which is 1,960 working agents in a registry of 320,856.

That ratio has moved as we have probed more, and it moved in the agents' favour: an earlier cut of this table, on less data, put it at 1.2 percent. Both numbers are ours and neither is a guess, which is the point. A marketplace that quotes you a liveness figure should be able to tell you when its own figure changed and why.

Reputation is worse than sparse, it is concentrated:

| | |
|---|---:|
| Feedback entries on chain | 29,614 |
| Distinct reviewers | 108 |
| Reviewers we treat as independent | 31 |
| Largest funding-linked cluster | 13 reviewers |
| Reviews written by that one cluster | 13,103 (44 percent of all feedback) |

A naive average over that data is a number 13 wallets control. TrustList weights every review by how independent the reviewer actually is, and shows you the raw average next to the kept one so you can see what was removed and why.

## What it does

- **Indexes** the ERC-8004 Identity and Reputation registries from chain logs, and fetches every agent card.
- **Probes** every declared endpoint on a schedule and keeps the history, so liveness is measured rather than claimed.
- **Scores** reputation with reviewer weighting, funding-cluster detection, and Bayesian shrinkage, with the whole method published at `/methodology` and served from one source of truth at `/v1/methodology`.
- **Publishes** a Merkle root of every score so anyone can verify a number against the chain instead of trusting our API.
- **Hires** through ERC-8183 escrow in one transaction, with exact-amount approvals and a visible refund path.

## Architecture

```
   +-----------------------------------------------------------------------+
   |                            BSC mainnet                                |
   |  ERC-8004 Identity Registry     ERC-8004 Reputation Registry          |
   |  ERC-8183 kernel + EvaluatorRouter + OptimisticPolicy                 |
   |  HireRail.sol (ours)            TrustSnapshot.sol (ours)              |
   +-----------------------------------------------------------------------+
        ^                    ^                          ^
        | logs               | Merkle root publish      | hire / fund / settle
        |                    |                          |
   +---------+        +--------------+          +------------------+
   | indexer |------->|  Postgres 16 |<---------|   api (axum)     |
   |  (rust) |        |              |          |   REST           |
   +---------+        +--------------+          +------------------+
        ^                    ^                          ^
        |                    |                          |
   +---------+        +--------------+                  |
   | prober  |------->| trust engine |                  |
   |  (rust) |        |    (rust)    |                  |
   +---------+        +--------------+                  |
        |                                               |
        v                                               v
   agent endpoints                              +------------------+
   (HTTP, agent cards)                          |  web (Next.js)   |
                                                |  wagmi + viem    |
                                                +------------------+
```

Four Rust binaries share one workspace and one database. The web app talks only to our API, never directly to an agent endpoint, so every probe is centralised and the history is ours.

## Run it

Three commands, and only one value to fill in.

```
git clone https://github.com/big14way/Trustlist.git && cd Trustlist
cp .env.example .env      # then set BSC_RPC_HTTP to any BSC RPC
make demo
```

`make demo` starts Postgres, runs migrations, loads a seed of real indexed rows so you are not waiting on a backfill, starts the indexer, prober, trust engine, and api, then the web app. Open http://localhost:3000.

Requires Docker, Rust, Node 22, and Foundry. On Linux x86_64 the first run downloads prebuilt service binaries for the exact commit you have checked out, which is why it takes a minute or two rather than eight. They are accepted only if the commit matches, the published checksum matches, and each one runs and reports the commit it was built from; anything else falls back to compiling the workspace, which is the slow step.

Other targets: `make verify` (the completion gate), `make check` (fmt, clippy, tests), `make e2e` (the golden journeys against a local chain), `make coldstart` (clone-to-running in a clean container, Linux only), `make reset`.

## What is real and what is local

Being precise about this matters more than sounding impressive.

- **Real, from mainnet**: every agent, name, endpoint, card, review, reviewer, funding trace, and probe result. All of it is indexed or measured by us. There is no mock data anywhere in the product.
- **On mainnet, ours**: all three contracts, deployed 31 August 2026 with verified source.

  | Contract | Address |
  |---|---|
  | HireRail | [`0x9fA9Cd8DDDd33eAc46C8c600371cc61ED79411e1`](https://bscscan.com/address/0x9fA9Cd8DDDd33eAc46C8c600371cc61ED79411e1) |
  | TrustSnapshot | [`0xb40d69864c42160eF69b75efcb02174Ab20e2E82`](https://bscscan.com/address/0xb40d69864c42160eF69b75efcb02174Ab20e2E82) |
  | TrustListHook | [`0x2685352E856074a879E1a8fe737B7fCA270Aa77f`](https://bscscan.com/address/0x2685352E856074a879E1a8fe737B7fCA270Aa77f) |

  The first Merkle root is published, over 40,004 scored agents. The root the API serves matches the root on chain, a proof the API serves verifies against the deployed contract, and the same proof with the score altered is rejected. Every transaction is in `scripts/tx_log.md`.
- **Not done on mainnet yet**: a completed hire. The contracts are live but no job has run through them on mainnet, so `docs/SUBMISSION.md` still lists that row as open. `HireRailFork.t.sol` and `scripts/mainnet_rehearsal.sh` both run the full lifecycle against the real kernel on a fork, which is strong evidence and is not the same thing.
- **Self-deployed registries** exist only in CI and the e2e suite, where synthetic data is the correct thing to have. The product never reads from them.
- **What the green badge means**: every push loads a seed of real indexed rows, stands up a local chain, runs the trust engine once, deploys `TrustSnapshot`, publishes the root, and then checks that the root and a Merkle proof the API serves both match the chain. That proves the snapshot pipeline end to end on a local chain. The mainnet publish above is a separate, deliberate act by a person, and the badge does not cover it.

## Where the numbers come from

Every number in this README is reproducible:

```
curl -s localhost:8080/v1/stats | python3 -m json.tool     # the table above
curl -s localhost:8080/v1/methodology                      # every threshold, as run
curl -s localhost:8080/v1/snapshots/latest                 # the published Merkle root
bash scripts/verify.sh                                     # the gate, exits 0 or tells you why
```

`docs/METHODOLOGY.md` and the `/methodology` page are both rendered from `crates/common/src/methodology.rs`, so the rules a reader is shown cannot drift from the rules that ran.

## Repository layout

```
crates/indexer    chain logs to Postgres
crates/prober     endpoint liveness, with an SSRF guard and per-host rate limits
crates/trust      reviewer weighting, scoring, Merkle snapshots
crates/api        the REST API, every response a database read
crates/common     config, methodology constants, snapshot hashing
contracts/        HireRail, TrustSnapshot, and their tests
web/              Next.js app, wagmi and viem, Playwright journeys
agents/           two read-only PancakeSwap agents we built and probe like any other
scripts/          the gate, the seed, the dev chain, the cold start test, the mainnet scripts
docs/             verification log, methodology, submission notes, the mainnet runbook
render.yaml       one click deploy for the two agents, so the registry has a card URL to fetch
```

## Status

Milestones M0 through M3, M5 and M6 are done and gated: `make verify` exits 0, and M6 now holds against mainnet rather than a dev chain.

Also done: the zero dead ends pass, eighteen states walked with seven fixed (`docs/DEAD_ENDS.md`), and cold start inside the spec's five minute budget, measured at 89 seconds from a clean container.

Not done yet: a completed hire on mainnet, the Altana session track (the relay is reachable again, the wallet needs BNB), the advantage report, judge mode, a hosted deployment, and the demo video. `docs/SUBMISSION.md` is the honest row by row state and `SPEC.md` Section 21 has the full plan.

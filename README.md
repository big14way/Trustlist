# TrustList

[![verify](https://github.com/big14way/Trustlist/actions/workflows/verify.yml/badge.svg)](https://github.com/big14way/Trustlist/actions/workflows/verify.yml)

An ERC-8004 agent marketplace for BNB Smart Chain that tells you which agents are actually alive, which reviews are worth believing, and lets you hire through ERC-8183 escrow.

Built for the BNB Chain "Build the Era" hackathon. `SPEC.md` is the source of truth for the build. `docs/VERIFICATION.md` records what was checked against live sources before any code was written.

## The problem

Imagine you need an agent to watch a lending position so it does not get
liquidated while you sleep. You open the ERC-8004 registry on BNB Smart
Chain. There are 324,269 agents. That sounds like a market.

You pick one with good reviews. You send it money.

Nothing happens. Nothing was ever going to happen, because the endpoint in
that agent's card stopped answering weeks ago, and the reviews that made you
pick it were written by thirteen wallets funded from the same place.

Everything in that paragraph is measured, not imagined. Here is our own
data, read from chain and probed by our own instruments, at block
119,213,230.

### Almost nothing is there

| | |
|---|---:|
| Agents registered under ERC-8004 on BSC | 324,269 |
| That declare a service endpoint at all | 81,674 |
| That answer when we knock | **7,782** |
| That declare an endpoint and never answer | 5,018 |
| Still being measured | 69,028 |
| Probes behind these numbers | 4,266,478 |

Two point four percent. That is the share of a 324,269 agent registry that
responds. Three quarters of them never even claim an endpoint, which means
three quarters of this marketplace is a name and a wallet address.

We did not read that in a report. We knocked on every door 4,266,478 times.

### The reviews are worse than useless

You would hope reputation rescues you. It does the opposite.

| | |
|---|---:|
| Feedback entries on chain | 29,626 |
| Distinct wallets that wrote them | **108** |
| That we can show are independent | 31 |
| Written by one funding-linked cluster | 13,103, by 13 wallets |

Thirteen wallets, funded from a common source, wrote 44 percent of all
reputation on this chain. A naive average, which is what every explorer
shows you, is a number those thirteen wallets control.

Take agent 137, "EZCTO Deployer Agent". Its raw review average is **96.8 out
of 100**. Any marketplace ranking on reviews puts it near the top. We probed
it 542 times and it answered under 38 percent of them, and when we drop
reviews from wallets that cannot be shown to be independent, 10 of its 25
survive. Our score for it is 90.4, not 96.8, and its status is `down`.

It is not a scam. It is just not what its reviews say it is, and nothing on
chain tells you that.

147 agents currently carry on-chain reputation while failing to answer at
all.

### Why this is about to matter much more

This is a marketplace for **autonomous agents**, and the whole point is to
give one your money and your permission and stop watching. The ERC-8183
escrow is real, the spend caps are real, the transactions are real.

So the cost of ranking on numbers nobody checked is not a bad afternoon. It
is escrow funded to an agent that cannot deliver, or a spend cap handed to
something chosen on reviews thirteen wallets wrote. The registry hands you
the names. It does not tell you which ones are alive, and it cannot tell you
which reviews to believe.

Somebody has to knock on the doors.

Every figure above is reproducible against the live deployment:

```
curl -s https://trustlist-api.onrender.com/v1/stats
curl -s https://trustlist-api.onrender.com/v1/agents/137
```

The registry moves, so these drift. They were read at block 119,213,230 and
the shape of them does not change.

## What we built

TrustList is that: a marketplace that measures first and lists second.

- **We knock.** Every declared endpoint, every 30 minutes, history kept. An
  agent's status is earned from at least 24 probes or it does not get one.
  The Probe Strip on every card is 168 real hours, not a badge.
- **We trace the money behind the reviews.** Reviewers funded from a common
  source are collapsed into one cluster and weighted down together. Both
  numbers are shown side by side, the raw average and the kept one, so you
  can see exactly what was removed and why.
- **We publish the workings.** Every threshold is on `/methodology`, served
  from the same source that runs the scoring, so the rules you read cannot
  drift from the rules that ran.
- **We put the scores on chain.** A Merkle root of every score, published to
  BSC, so you can verify any number against the chain instead of trusting
  our API. The page does it in your browser and then does it again with the
  score altered, to show the proof rejects it.
- **Then you can hire.** ERC-8183 escrow, exact-amount approvals, one
  transaction, and a refund path you control.

The honest summary of the pitch: we are not claiming to find you a great
agent. We are claiming that when this says an agent is alive, we knocked, and
when it shows you a reputation score, we can show you who paid for it.

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

## See it running

The marketplace is live at **https://trustlistapp.vercel.app**, served by
`https://trustlist-api.onrender.com` against a hosted copy of the real
index. `docs/HOSTING.md` says exactly which parts of the index are copied
and why.

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
- **A completed hire, on mainnet**: job 56675 ran the full ERC-8183 lifecycle against the real kernel on 31 August 2026. Hire, deliver, accept, escrow released, kernel reports Completed. Hirer and provider are the same address, because the only agent whose owner key we hold is one we registered ourselves, and the two party case is covered by `HireRailFork.t.sol` against the same live kernel.
- **Our two reference agents are live and registered**: [Yield Scout](https://8004scan.io/agents/bsc/320964) is agent 320964 and [Range Keeper](https://8004scan.io/agents/bsc/320966) is 320966, both hosted, both serving ERC-8004 cards, both being probed by our own prober like any other agent. They show as `measuring` until they have 24 probes, which is the same rule every other agent gets.
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

Not done yet: the Altana session track (the page, the scoped permissions and the revoke path are written and type check, and no grant has ever been signed), the x402 metered path (not started, and first on the spec's own cut list), the advantage report, judge mode, a hosted deployment of the app itself, and the demo video. `docs/SUBMISSION.md` is the honest row by row state and `SPEC.md` Section 21 has the full plan.

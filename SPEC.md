# TrustList: Build Spec

BNB Chain "Build the Era" hackathon submission. Single source of truth for the build.

Target: win the main challenge (official BNB Agent Studio marketplace) plus the TermiX, Altana, and PancakeSwap partner tracks with one codebase.

---

## 0. How to use this file

Save this at the repo root as `SPEC.md`. Then in Claude Code:

```
Read SPEC.md end to end before writing any code. Do not skim it.
Then do Section 27 (Verification Tasks) first and report back what you found
before touching anything else. After I confirm, work through Section 21 milestone
by milestone.

A milestone is not finished when you say it is finished. It is finished when
`make verify` exits 0 and you have posted the report in the exact format from
Section 29.1, including a command I can run myself to reproduce every claim.
Build `make verify` (Section 29.2) during M0, before any feature code, and keep
it passing from that point on. If a check in it starts failing, fix the code,
never the check.
```

Also create a `CLAUDE.md` at the repo root containing Section 26 (Rules for the coding agent) so those constraints survive context compaction.

House rules that apply to every file the agent writes, including comments, commit messages, and UI copy:

- No em dashes and no en dashes anywhere. Use commas, colons, parentheses, or a new sentence.
- Plain human prose. No "delve", no "leverage" as a verb, no "in the ever evolving landscape of".
- Never invent a contract address, an API endpoint, a package name, or a version number. If you are not certain, stop and verify against the live source, and if you cannot verify, say so in the output.
- Every number shown in the UI must trace back to something read from chain or measured by our own prober. No mock data past Milestone 1.

---

## 1. Mission in one paragraph

Roughly 269,000 agents are registered on BNB Smart Chain under ERC-8004 (269,234 read from chain on 17 August 2026; every number in UI copy derives from our own chain reads, never from this paragraph), and almost none of them work. Independent measurement (arXiv:2606.26028v2, data through 13 May 2026, when BSC had 90,145 registrations) puts live, reachable service endpoints on BSC at about 4 percent of registrations, and after stripping coordinated Sybil feedback, close to 78 percent of rated agents on BSC are left with no trustworthy review at all. The registry has roughly tripled since that measurement, and bulk registrations skew toward placeholders, so today's live share is probably lower than 4 percent. We measure it ourselves and lead with our own number. So the registry is technically a marketplace and practically a graveyard. TrustList is the marketplace that fixes the ranking problem: it probes every agent continuously, weights reputation by how independent the reviewer actually is, hides the dead majority by default, and turns "I found an agent" into "I hired it and it got paid" in two clicks using ERC-8183 escrow, x402 payments, and Altana session wallets with hard on-chain spend caps.

The one sentence we say to judges: **anyone can list 269,000 agents, we are the only one that can tell you which ones are alive and which of those you can trust.** (Fill the live number in from our own measurement before any pitch.)

---

## 2. The competition (constraints we design against)

| Item | Value |
|---|---|
| Event | BNB Chain "Build the Era", listed under the Smart Money Era hackathon page |
| Brief | Build the best AI agent marketplace on BNB Smart Chain. The marketplace itself, not a portfolio of agents. |
| Build window | 5 August 2026 to 9 September 2026 |
| Judging | 9 September to 23 September 2026 |
| Winner announced | 5 November 2026 |
| Main prize | 30,000 USDT plus being in line to become the officially adopted BNB Agent Studio marketplace |
| Partner: TermiX | 10,000 USDT |
| Partner: PancakeSwap | 1,000 CAKE |
| Partner: Altana | 50,000 XP |
| Partner: AltLayer | 8004scan Pro plans and AltLLM credits |
| Team size | Solo allowed and explicitly encouraged |
| Entry | Single intake form on the hackathon page, tick boxes to enter partner tracks. Partner entry does not affect the main score. One build can win the main prize and every partner track. |

### What the judges score

Stated criteria: functionality, data quality, agent diversity, and above all **how easily someone can discover and hire an agent through the platform**.

BNB Chain's general hackathon framework adds five pillars: design and usability, technical implementation and code quality, BNB Chain integration and ecosystem fit, innovation and creativity, sustainability and market potential.

Agent categories: BNB Chain's own sources disagree. The hackathon page lists, verbatim: Rebalancing (manages LP ranges), Grid Trading, Yield Optimisation, Health Factor Monitoring. The launch blog and press release list: monitoring agents (markets, wallets, positions), grid trading agents, health factor agents (liquidation protection), yield agents (capital reallocation), with no rebalancing category. We support the union: monitoring, rebalancing, grid-trading, yield, health-factor, plus pancakeswap and other. Agent diversity is scored against "the four categories" on the hackathon page, so all four page categories must have live agents at demo time, and monitoring stays because the blog and press name it and it is the most demo-able.

The TermiX track publishes a weighted rubric on the hackathon page: value of the services 30 percent, proven agent advantage 30 percent, high-stakes categories and track record 20 percent, marketplace quality 20 percent. The Chainwire release adds "real-world usage" as a fourth main criterion. Main track numeric weights were not published as of 17 August 2026; recheck the page weekly during the build.

### Design consequences, non negotiable

1. **Discovery and hire must both work end to end on mainnet.** A directory with no checkout loses. Budget time accordingly: the hire flow is not the last thing we build, it is the second thing.
2. **Data quality is a scored line item and it is our whole thesis.** Every ranking number gets a public methodology page.
3. **Agent diversity is a scored line item.** We must be able to show live agents in all four reference categories at demo time. If the registry does not contain live ones in a category, we seed that category ourselves (see Section 20.3).
4. **Real transactions inside the build window.** BNB hackathon rules have historically wanted deployed contracts with at least two successful transactions in the window. Ship mainnet transactions early and keep a running log.
5. **Stack the sponsor tooling.** Prior BNB hackathons gave the highest scores to teams that used all sponsor tools. Every partner integration in Section 20 is also a main score multiplier.

---

## 3. The problem, stated the way we will state it to judges

Three failures compound:

**Failure 1: liveness.** An ERC-8004 registration is an NFT with a `tokenURI` pointing at a JSON agent card. Nothing forces that card to exist, to parse, or to name an endpoint that answers. Measurement across Ethereum, BSC, and Base through 13 May 2026 (arXiv:2606.26028, version 2) found only 3 percent, 4 percent, and 15 percent respectively exposed a valid registration file with at least one live service endpoint. On BSC that is roughly 96 percent noise, measured against the 90,145 agents registered at that date. The registry has since roughly tripled, mostly through bulk registrations, so the current live share is likely lower still.

**Failure 2: reputation.** Feedback in the Reputation Registry is permissionless and costs a fraction of a cent on BSC. The same study found 59.2 percent of reviewers on BSC exhibiting coordinated Sybil behaviour, and after removing flagged feedback, 77.9 percent of rated BSC agents had no valid feedback left. Stars are theatre.

**Failure 3: hiring.** Even when you find a good agent, hiring it means trusting it with funds or wiring escrow yourself. Most people stop here.

Existing venues on BSC are explorers or raw directories: they index everything, including the dead 96 percent, and they surface unfiltered star ratings. None of them makes verified liveness and Sybil filtered reputation the primary ranking signal with an integrated hire and escrow flow behind it.

Cite the source properly and honestly in the UI and the pitch: arXiv:2606.26028 version 2 (revised 8 July 2026), "Can Trustless Agents Be Trusted? An Empirical Study of the ERC-8004 Decentralized AI Agent Ecosystem" (preprint, data window ends 13 May 2026). Pin the version everywhere the paper is cited: v1 and v2 report different BSC figures (v1: 72.3 percent of rated agents left with no valid feedback; v2: 77.9 percent). We cite v2. Also arXiv:2606.12128 on operational readiness, which studies Ethereum only: cite it for the "registration heavy, operationally shallow" framing, never for a BSC number. **We must independently reproduce these numbers with our own prober and quote our own figure in the product**, with theirs as corroboration. Reproducing it is itself a strong judge moment. Never present a preprint statistic as our own measurement.

---

## 4. The solution

TrustList has four layers.

1. **Index.** Continuously mirror the ERC-8004 Identity and Reputation registries on BSC into Postgres.
2. **Probe.** Resolve every agent's declared endpoints and test them on a schedule. Keep the history so uptime is a real measurement, not a claim.
3. **Score.** Compute a reviewer independence weight per feedback author, collapse Sybil clusters, and produce a trust score with an explicit confidence band. Publish periodic signed snapshots on chain so other products can consume our scores.
4. **Hire.** One click from an agent card to a funded ERC-8183 job, paid in USDT or USD1, executed from an Altana session wallet with an on chain spend cap and expiry that the user can see and revoke.

Everything else is in service of those four.

---

## 5. Positioning

| Product | What it is | Why we differ |
|---|---|---|
| 8004scan (AltLayer) | ERC-8004 explorer with reputation, validation, leaderboards, builder API | Explorer, not a hire venue. Surfaces validation history, does not generate liveness or filter Sybils. We consume it as a cross check and cite it. |
| TermiX Agent.family | Agent marketplace on ERC-8004 plus ERC-8183 | Real marketplace, but no published trust filtering. We compete on curation quality, and we enter their track rather than fight them. |
| Agent0 based directories | Discovery SDK and subgraph front ends | Raw discovery over the full registry including the dead majority. We use the same subgraph as an input and add the layer on top. |
| BNB Agent Studio | Deployment surface for agents | Upstream of us. We are the demand side venue their agents get discovered in. This is the point of the whole competition. |

Our moat sentence: **curation is a protocol, not a page.** Scores are computed from public data by published rules, anchored on chain, and verifiable by anyone. That is hard to fork because forking the UI does not fork the probe history.

---

## 6. Scope

### In scope for the submission

- Indexer for ERC-8004 Identity plus Reputation on BSC mainnet.
- Liveness prober with rolling history and uptime.
- Trust engine with reviewer independence weighting and a documented Sybil heuristic set.
- On chain trust snapshot contract with Merkle proofs.
- Hire flow on ERC-8183 with real mainnet transactions.
- x402 metered payment path for pay per call agents.
- Altana session wallet checkout with visible cap, expiry, and revoke.
- Marketplace UI: browse, filter, agent detail, hire, my jobs, methodology.
- Advantage Report feature (TermiX track) with at least three real tasks measured with and without an agent.
- A PancakeSwap agent category with at least two working reference agents (PancakeSwap track).
- Demo video, README, deploy scripts, verified contracts.

### Explicitly cut

- The ERC-8004 Validation Registry (TEE, ZK, re-execution). Read it if present, do not implement a validator. Say so in the roadmap.
- Multi chain. BSC mainnet only, with BSC testnet for development.
- Agent authoring or hosting. BNB Agent Studio does that. We link out.
- Accounts, email, password. Wallet connect only.
- Fiat on ramp.
- Mobile native app. Responsive web is enough.
- A token. Do not ship a token. It reads as noise to these judges.

If a milestone runs long, cut features from the bottom of Section 21, never cut the hire flow.

---

## 7. Architecture

```
                        BNB Smart Chain (mainnet + testnet)
   +-----------------------------------------------------------------------+
   |  ERC-8004 Identity Registry     ERC-8004 Reputation Registry           |
   |  ERC-8183 AgenticCommerce kernel + EvaluatorRouter + OptimisticPolicy  |
   |  TrustSnapshot.sol (ours)       HireRail.sol (ours)                    |
   +-----------------------------------------------------------------------+
        ^                    ^                          ^
        | logs + calls       | Merkle root publish      | hire / fund / settle
        |                    |                          |
   +---------+        +--------------+          +------------------+
   | indexer |------->|   Postgres   |<---------|   api (axum)     |
   |  (rust) |        |  + TimescaleDB|         |   REST + SSE     |
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
   (HTTP, A2A cards)                            |  web (Next.js)   |
                                                |  wagmi + viem    |
                                                +------------------+
                                                         |
                                    +--------------------+-------------------+
                                    |                    |                   |
                              Altana wallet         x402 facilitator    The Graph
                              (session keys)        (Binance x402)      Agent0 subgraph
```

Four Rust binaries share one workspace and one database. The web app talks only to our API, never directly to an agent endpoint (CORS, safety, and we want every probe centralised so the history is ours).

---

## 8. Tech stack

Pin versions in lockfiles. Do not upgrade mid build.

**Chain and contracts**
- Solidity with Foundry (forge, cast, anvil). Foundry because we want fast fuzz tests on the scoring anchor and cheap forking against BSC.
- `forge-std`, OpenZeppelin contracts for `Ownable2Step`, `Pausable`, `SafeERC20`, `MerkleProof`.
- BSC mainnet chain id 56, BSC testnet chain id 97.

**Backend (Rust)**
- `alloy` for RPC, ABI codegen, log decoding, and typed contract bindings. If `alloy` gives trouble on any BSC quirk, fall back to `ethers-rs`, but try `alloy` first.
- `tokio` runtime, `axum` for the HTTP API, `tower-http` for CORS and tracing.
- `sqlx` with Postgres, compile time checked queries, migrations in `/migrations`.
- `reqwest` with `rustls`, strict timeouts, for the prober.
- `serde`, `serde_json`, `jsonschema` for agent card validation.
- `governor` for rate limiting outbound probes.
- `tracing` plus `tracing-subscriber` for structured logs.
- `petgraph` for the reviewer clustering graph.
- `rust_decimal` for anything money shaped. Never f64 for token amounts.

**Frontend**
- Next.js App Router, TypeScript strict.
- `wagmi` plus `viem` for wallet and contract calls. `@tanstack/react-query` for data.
- Tailwind CSS with a custom token layer (Section 18.2). No component library that imposes its own look.
- `recharts` only if a chart genuinely needs it. The signature uptime strip is hand rolled SVG.

**Agent side (for our own reference agents)**
- Python with the `bnbagent` SDK for the ERC-8183 job lifecycle, since that is the first live implementation.
- TypeScript with the Agent0 SDK where discovery is needed.

**Infra**
- Postgres 16. Docker Compose for local. Any cheap VPS or Railway/Fly for the demo deployment.
- One public RPC plus one paid/backup RPC. Never a single RPC provider on demo day.

---

## 9. Repository layout

```
trustlist/
  README.md
  SPEC.md                     <- this file
  CLAUDE.md                   <- Section 26 rules
  docker-compose.yml
  .env.example
  contracts/                  <- Foundry project
    src/
      TrustSnapshot.sol
      HireRail.sol
      interfaces/
        IIdentityRegistry.sol
        IReputationRegistry.sol
        IAgenticCommerce.sol
    test/
    script/
      DeployTestnet.s.sol
      DeployMainnet.s.sol
      PublishSnapshot.s.sol
    foundry.toml
  crates/
    common/                   <- shared types, config, db pool, chain clients
    indexer/                  <- registry log ingestion + backfill
    prober/                   <- endpoint liveness + agent card validation
    trust/                    <- Sybil weighting + score computation + snapshot publish
    api/                      <- axum REST + SSE
  migrations/
  web/                        <- Next.js app
    app/
    components/
    lib/
  agents/                     <- our reference agents
    pancake-range/            <- PancakeSwap LP range manager
    pancake-yield/            <- PancakeSwap yield finder
    health-factor/            <- liquidation guard
    monitor/                  <- wallet and market monitor
  docs/
    METHODOLOGY.md            <- public trust scoring rules
    ADVANTAGE_REPORT.md       <- TermiX deliverable
    SUBMISSION.md             <- judge facing summary, addresses, tx hashes
    ADDRESSES.md              <- every deployed address, verified links
  scripts/
    seed_testnet_agents.ts
    tx_log.md                 <- running log of mainnet txs in the window
    verify.sh                 <- the completion gate, Section 29.2
    audit_data.sh             <- proves UI numbers trace back to chain, Section 29.3
    coldstart_test.sh         <- clean machine bootstrap test, Section 30.3
  web/e2e/golden/             <- the five acceptance journeys, Section 30.6
  .github/workflows/verify.yml
  Makefile                    <- make demo, make verify, make check, make e2e
```

---

## 10. Data model

Postgres. Timescale hypertable on `probe_results` if available, plain table with a BRIN index if not.

```sql
-- agents mirrored from the ERC-8004 Identity Registry
create table agents (
  agent_id            numeric primary key,          -- ERC-721 token id
  owner               bytea not null,
  token_uri           text,
  card_fetched_at     timestamptz,
  card_status         text,                         -- ok | unreachable | invalid_json | schema_fail | missing
  card_raw            jsonb,
  name                text,
  description         text,
  categories          text[] default '{}',          -- our normalised taxonomy
  declared_skills     jsonb,
  endpoints           jsonb,                        -- [{kind, url, protocol}]
  trust_models        text[] default '{}',
  registered_block    bigint not null,
  registered_at       timestamptz not null,
  last_seen_block     bigint not null
);

-- every probe attempt, append only, this is the asset
create table probe_results (
  id            bigserial primary key,
  agent_id      numeric not null references agents(agent_id),
  endpoint_url  text not null,
  probed_at     timestamptz not null default now(),
  ok            boolean not null,
  http_status   int,
  latency_ms    int,
  failure_kind  text,        -- dns | tls | timeout | conn_refused | http_error | bad_body | schema
  body_hash     bytea
);
create index on probe_results (agent_id, probed_at desc);

-- raw feedback from the ERC-8004 Reputation Registry
-- The real NewFeedback event carries a signed int128 value plus a uint8
-- valueDecimals (no fixed scale), two string tags, an endpoint string, a
-- feedback URI, and a feedback hash. FeedbackRevoked events must be applied
-- or the scores are trivially gameable (farm feedback, get snapshotted,
-- revoke).
create table feedback (
  id             bigserial primary key,
  agent_id       numeric not null,
  reviewer       bytea not null,
  feedback_index numeric not null,      -- uint64 from the event
  value          numeric not null,      -- int128, signed, raw
  value_decimals int not null,
  tags           text[],
  endpoint       text,
  uri            text,
  feedback_hash  bytea,
  revoked        boolean not null default false,
  revoked_tx     bytea,
  tx_hash        bytea not null,
  log_index      int not null,
  block_number   bigint not null,
  block_time     timestamptz not null,
  unique (tx_hash, log_index)
);
create index on feedback (agent_id);
create index on feedback (reviewer);

-- per reviewer independence weight, recomputed on a schedule
create table reviewer_weights (
  reviewer          bytea primary key,
  weight            numeric not null,   -- 0.00 to 1.00
  cluster_id        bigint,
  first_funder      bytea,
  first_tx_at       timestamptz,
  external_tx_count int,
  flags             text[],             -- funding_cluster | burst | one_shot | reciprocal | max_score_only | fresh_address
  computed_at       timestamptz not null default now()
);

-- computed per agent scores, one row per computation run
create table agent_scores (
  agent_id        numeric not null,
  computed_at     timestamptz not null,
  liveness        numeric not null,   -- 0..100
  uptime_7d       numeric,            -- 0..1
  median_latency  int,
  trust           numeric,            -- 0..100, null if no evidence
  trust_confidence numeric,           -- 0..1
  raw_star_avg    numeric,            -- unweighted, for the before/after comparison
  feedback_total  int not null default 0,
  feedback_kept   int not null default 0,
  jobs_completed  int not null default 0,
  jobs_disputed   int not null default 0,
  rank_score      numeric not null,
  primary key (agent_id, computed_at)
);

-- Merkle snapshots published on chain
create table snapshots (
  id           bigserial primary key,
  merkle_root  bytea not null,
  agent_count  int not null,
  computed_at  timestamptz not null,
  tx_hash      bytea,
  block_number bigint,
  payload_uri  text                    -- where the full leaf set is published
);

-- jobs created through our hire rail
create table jobs (
  job_id        numeric primary key,
  agent_id      numeric not null,
  hirer         bytea not null,
  token         bytea not null,
  budget        numeric not null,
  spec_hash     bytea,
  state         text not null,         -- open | funded | submitted | completed | rejected | expired | disputed
  created_at    timestamptz not null,
  deadline      timestamptz,
  settled_at    timestamptz,
  create_tx     bytea,
  settle_tx     bytea
);
```

Rules:
- `probe_results` is append only and never pruned during the competition. It is the proof that our uptime numbers are measured.
- `agent_scores` is versioned by `computed_at` so we can show a score history and prove we did not retrofit numbers.
- Store addresses as `bytea` (20 bytes), format at the edge.

---

## 11. Indexer spec

Binary: `crates/indexer`.

Responsibilities:
1. Backfill from the registry deployment block to head, in chunked `eth_getLogs` ranges with adaptive sizing: start at 2,000 blocks per call, halve on any provider error, and grow back slowly after sustained success. Public RPCs cap ranges unpredictably (tested 17 Aug 2026: PublicNode served 2,000 blocks, bsc-dataseed and most others refused), so a fixed chunk size will stall. Always include the contract address filter.
2. Follow head with a confirmation depth of 15 blocks. BSC finality is fast after Fermi but reorgs still happen, so track `block_hash` per ingested range and roll back cleanly if a hash mismatch appears.
3. Decode Identity Registry events (registration, transfer, `tokenURI` updates) and Reputation Registry feedback events into the tables above.
4. Enqueue an agent card fetch whenever `token_uri` is new or changed.
5. Expose Prometheus style counters: blocks behind head, logs ingested, decode failures.

Implementation notes:
- Generate typed bindings from the real ABI with `alloy::sol!`. Do not hand write log decoding.
- Persist an `indexer_state` row with `last_block`, `last_block_hash`, `registry` so restarts resume.
- If direct log scanning is slow on public RPC, use The Graph Agent0 subgraph as a bulk backfill source and keep our own head follower for freshness. Cross check counts between the two and log any divergence, because that divergence is itself a data quality talking point.

---

## 12. Prober spec

Binary: `crates/prober`. This is the differentiator. Get it right.

### Card resolution
1. Read `tokenURI(agentId)`.
2. Resolve the URI. Support `https://`, `ipfs://` (via a public gateway with a fallback gateway), and `data:` URIs. Reject anything else and mark `card_status = 'invalid_uri'`.
3. Fetch with: 8 second total timeout, 4 second connect timeout, max 3 redirects, max 512 KB body, no cookies, no auth headers.
4. Parse JSON. Validate against the ERC-8004 registration schema and the A2A agent card shape. Record which required fields are missing rather than a single pass or fail boolean.
5. Extract endpoints. Also try the conventional well known locations if the card names a base URL: `/.well-known/agent.json` and `/.well-known/agent-card.json`. Record which of these resolved.

### Endpoint probing
For each declared endpoint, every 30 minutes:
- `GET` (or the declared method) with the same timeout profile.
- Record `ok`, `http_status`, `latency_ms`, `failure_kind`, and a hash of the first 4 KB of the body.
- A 401 or 402 counts as **alive**. A paywalled agent is a working agent, and 402 is literally the x402 handshake. Only DNS failure, TLS failure, connection refused, timeout, 5xx, and 404 count as down.
- If the endpoint declares ERC-8183 support, additionally probe its status or health path and record whether it speaks the job protocol.

### Endpoint classification and operator concentration
A sampled measurement on 17 August 2026 (300 random agents, seed 8004, script preserved in the repo) found that 28 percent of sampled agents had a declared URL that answered, but 81 of those 85 were bulk registrations by a single operator (EvoEvo) whose only declared service is a profile page on the operator's own website. An answering marketing page is not a working agent. So the prober must:
- Classify each declared endpoint by kind: `service` (A2A, MCP, ERC-8183, or an API that returns structured content), `web` (an HTML page), `metadata` (points back at another agent card). The Live status and the headline live count use `service` endpoints; `web` only agents get their own bucket, shown but labelled.
- Record the endpoint host per agent and cluster agents by host. A host serving hundreds of registrations is one operator, not hundreds of agents. Show an operator concentration figure on `/stats`: it is the liveness side mirror of reviewer clustering, and it is a number nobody else publishes.

### Safety rules for the prober, non negotiable
- Never follow redirects to private ranges. Block `127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16`, `::1`, and unique local addresses. This is an SSRF guard and judges who read code will look for it.
- Rate limit per host to 1 request every 10 seconds via `governor`.
- Send a real `User-Agent` naming TrustList and a contact URL. We are a good citizen and we say so on the methodology page.
- Respect `robots.txt` where the endpoint is a web page rather than an API.
- Global concurrency cap, configurable, default 64.

### Liveness score
```
uptime_7d      = successful_probes / total_probes over 7 days (min 24 probes, else mark "measuring")
card_quality   = 0.4*card_parses + 0.3*has_endpoint + 0.2*schema_complete + 0.1*declares_skills
latency_factor = clamp(1 - (median_latency_ms / 5000), 0, 1)

liveness = 100 * (0.55*uptime_7d + 0.30*card_quality + 0.15*latency_factor)
```
Agents with fewer than 24 probes show a "measuring" badge and are excluded from the default ranking rather than scored badly. Never punish an agent for being new. Say this on the methodology page.

Status buckets shown in the UI: **Live** (uptime 7d >= 0.9), **Flaky** (0.5 to 0.9), **Down** (< 0.5), **Dormant** (no valid endpoint ever), **Measuring** (< 24 probes).

---

## 13. Trust engine spec

Binary: `crates/trust`. Recompute every 6 hours and on demand.

### Step 1: reviewer independence

For every address that has ever left feedback, compute a weight in `[0, 1]` as a product of penalty factors. Start at 1.0 and multiply.

| Signal | How to detect | Penalty factor |
|---|---|---|
| Fresh address | first tx less than 7 days before the feedback | 0.5 |
| One shot | address has left exactly one feedback and has fewer than 5 transactions total outside the Reputation Registry | 0.3 |
| Funding cluster | trace the first inbound native transfer, group reviewers by funder, cluster size >= 5 | 0.25 |
| Burst | 5 or more feedbacks for the same agent within a 10 minute window from distinct addresses whose funders overlap | 0.2 applied to each member |
| Max score only | reviewer has 3 or more feedbacks and every single one is the maximum score | 0.5 |
| Reciprocal | A rates B and B rates A, or a cycle of length <= 4 in the reviewer graph | 0.4 |
| Sub cent activity | address total gas spent lifetime below a threshold and no non registry contract interaction | 0.5 |
| High revocation rate | reviewer has 3 or more feedbacks and 50 percent or more of them were later revoked | 0.3 |

Floor the result at 0.02 rather than 0. We downweight, we do not silently delete, and the UI must be able to show "we saw 412 reviews, we counted 19".

Build the reviewer graph with `petgraph`, run connected components over the funding edges, and store `cluster_id`. Cap any single cluster's total contribution to one agent at the weight of its single strongest independent member, which is what actually kills a farm.

### Step 2: agent trust score

Bayesian shrink toward the population mean so that one glowing review does not outrank fifty real ones.

```
S  = sum over kept feedback of (w_r * score_r)
W  = sum over kept feedback of w_r
m  = 5.0                      // prior strength, tune once, then freeze and document
mu = weighted population mean score

trust_raw  = (S + m*mu) / (W + m)
trust      = 100 * normalise(trust_raw)
confidence = W / (W + m)                          // 0..1, shown as a band, never hidden
```

Normalisation, defined explicitly because the registry does not define a scale.
The on chain value is a signed `int128` with a per event `valueDecimals`, so
scores are not commensurable across agents or reviewers (the paper makes the
same observation). Our rule, published on the methodology page:

1. Scale each event to a decimal: `v = value / 10^valueDecimals`.
2. Clamp `v` to `[-100, 100]`. Anything outside is an outlier or an attack,
   and the clamp is documented.
3. Map to `[0, 1]`: `score_r = (clamp(v) + 100) / 200`. Negative feedback is
   real feedback and lands below 0.5; it must reduce the score, never be
   dropped.
4. Revoked feedback (a `FeedbackRevoked` event) is excluded from S and W
   entirely, and every snapshot is recomputed from the unrevoked set, so a
   farm cannot get counted and then revoke.

Because values are not commensurable across agents, normalising them by a
published rule is a contribution of the product, not plumbing. Say that in
the methodology page and the pitch.

If `W == 0`, `trust` is null. Show "No verified reviews" and rank on liveness plus job history only. Never fabricate a middling score to fill the column.

### Step 3: job evidence

Feedback attached to a settled ERC-8183 job where escrow actually moved is worth more than a free comment. Multiply `w_r` by 1.5 (then clamp to 1.0) when the reviewer is the hirer on a completed job for that agent. This is the honest core of the whole system: **payment is the only review that costs something.**

### Step 4: ranking

```
rank_score = 0.45*liveness + 0.35*(trust or 0) + 0.20*job_signal

job_signal = 100 * (completed / (completed + disputed + 3))
```

Hard filter, default on: only agents in Live or Flaky status appear. A toggle labelled "Show dormant agents" reveals the rest with the count next to it, because the count is the pitch.

### Step 5: snapshot

Build a Merkle tree over leaves `keccak256(abi.encode(agentId, liveness, trust, confidence, computedAt))`. Publish the root via `TrustSnapshot.sol`. Publish the full leaf set as a JSON file (host it publicly, link it from the methodology page) so anyone can verify a proof. Do this at least once per day during judging.

### Documentation duty
`docs/METHODOLOGY.md` must contain every number above, every threshold, and the reasoning. Link it from the site footer and from every score tooltip. Judges scoring "data quality" will open it. Write it in plain language, admit the limits, and include a "known weaknesses" section. Honest beats clever here.

---

## 14. Smart contracts

Keep the surface tiny. Escrow lives in the canonical ERC-8183 kernel, we do not reimplement it.

### `TrustSnapshot.sol`

```solidity
// Publishes signed score snapshots so anyone can verify a TrustList score on chain.
contract TrustSnapshot is Ownable2Step {
    struct Snapshot {
        bytes32 merkleRoot;
        uint64  computedAt;
        uint32  agentCount;
        string  payloadURI;
    }

    Snapshot[] public snapshots;
    mapping(address => bool) public publishers;

    event SnapshotPublished(uint256 indexed id, bytes32 merkleRoot, uint32 agentCount, string payloadURI);
    event PublisherSet(address indexed publisher, bool allowed);

    function publish(bytes32 merkleRoot, uint32 agentCount, string calldata payloadURI) external;
    function setPublisher(address publisher, bool allowed) external onlyOwner;
    function latest() external view returns (Snapshot memory);
    function verify(
        uint256 snapshotId,
        uint256 agentId,
        uint16 liveness,
        uint16 trust,
        uint16 confidence,
        uint64 computedAt,
        bytes32[] calldata proof
    ) external view returns (bool);
}
```

Notes: scores are stored as basis point style integers (0 to 10000) not decimals. `verify` is a pure Merkle check against the stored root. Emit a rich event so an indexer can follow score history without our API.

### `HireRail.sol`

A thin wrapper over the ERC-8183 `AgenticCommerce` kernel that adds a per hire budget ceiling, a deadline, and events we can index. It must **never custody user funds beyond the single hire it is executing**, and it must not hold approvals.

```solidity
contract HireRail is Pausable, Ownable2Step {
    using SafeERC20 for IERC20;

    event Hired(
        uint256 indexed jobId,
        uint256 indexed agentId,
        address indexed hirer,
        address token,
        uint256 budget,
        uint64 deadline,
        bytes32 specHash
    );
    event Cancelled(uint256 indexed jobId, address indexed by);
    event Settled(uint256 indexed jobId, bool accepted, uint256 paid, uint256 refunded);

    // Pulls exactly `budget` from msg.sender, opens and funds an ERC-8183 job in one transaction.
    function hire(
        uint256 agentId,
        address token,
        uint256 budget,
        uint64  deadline,
        bytes32 specHash
    ) external whenNotPaused returns (uint256 jobId);

    function cancel(uint256 jobId) external;          // only before funding is claimed, refunds hirer
    function settle(uint256 jobId) external;          // permissionless, forwards to EvaluatorRouter
}
```

Rules for the agent writing this:
- `Ownable2Step`, not `Ownable`.
- `Pausable` with owner only, documented as a hackathon safety valve, and say so in the README rather than hiding it.
- `SafeERC20` everywhere. Assume a token that returns nothing.
- Reentrancy: use checks effects interactions plus a guard on `settle`.
- Exact allowance pull, never `type(uint256).max`.
- No upgradeability proxy. Simplicity reads better than a proxy nobody audited.
- Custom errors, not revert strings.
- Full natspec on every external function.

### Tests (Foundry)

- `forge test --fork-url $BSC_RPC` against a mainnet fork for the ERC-8183 integration.
- Unit tests for the full job lifecycle: open, fund, submit, complete, reject, expire.
- Fuzz the Merkle verification with random leaf sets.
- Invariant test on `HireRail`: contract token balance is zero at the end of every external call sequence.
- A test proving `hire` reverts when allowance is short, when deadline is in the past, and when paused.
- Target line coverage above 90 percent on `src/`. Run `forge coverage` and put the number in the README.

---

## 15. Chain integration reference

Everything below was verified against live sources on 17 August 2026 (see docs/VERIFICATION.md for the full evidence trail).

**ERC-8004 on BSC mainnet (verified)**
- Identity Registry: `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432` (ERC-1967 UUPS proxy, implementation `0x7274e874CA62410a93Bd8bf61c69d8045E399c02`, `IdentityRegistryUpgradeable`, Sourcify exact match, implementation deployed at block 78,255,281)
- Reputation Registry: `0x8004BAa17C55a88189AE136b182e5fdA19dE9b63` (proxy, implementation `0x16e0FA7f7C56B9a767E34B192B51f921BE31dA34`, `ReputationRegistryUpgradeable`, implementation deployed at block 79,027,282)
- Key events: `Registered(uint256 indexed agentId, string agentURI, address indexed owner)` and `NewFeedback(uint256 indexed agentId, address indexed clientAddress, uint64 feedbackIndex, int128 value, uint8 valueDecimals, string indexed indexedTag1, string tag1, string tag2, string endpoint, string feedbackURI, bytes32 feedbackHash)`; also `URIUpdated`, `MetadataSet`, `FeedbackRevoked`, `ResponseAppended`.
- Not ERC721Enumerable: no `totalSupply`. Count agents from our indexed `Registered` events; cross check against the `_lastId` counter in storage slot `0xa040f782729de4970518741823ec1276cbcd41a0c7493f62d173341566a04e00`.
- NOT deployed at these addresses on BSC testnet (Chapel). Testnet work uses our own registry deployment, scoped to CI and e2e only.
- Reference contracts repo: https://github.com/erc-8004/erc-8004-contracts

Identity is an ERC-721: each agent is a token, `tokenURI` points at the registration JSON. Reputation takes permissionless structured feedback (signed value plus decimals plus tags). There is also a Validation Registry with proof hooks (TEE, ZK, re-execution) that we read but do not write.

**ERC-8183 on BSC mainnet (verified)**
- AgenticCommerce kernel proxy: `0xea4daa3100a767e86fded867729ae7446476eba6` (implementation `0xd5f9b570c96b5d67702d508c0bfb8b3b09209787`)
- EvaluatorRouter proxy: `0x51895229e12f9876011789b04f8698af06ccd6da` (binds policy, permissionless settle)
- OptimisticPolicy: `0x9c01845705b3078aa2e8cff7520a6376fd766de5` (silence past the dispute window means approval, disputes go to a whitelisted voter quorum)
- Payment token "United Stables" (U): `0xcE24439F2D9C6a2289F741120FE202248B666666`
- The SDK job lifecycle is several calls (create_job, register_job, set_provider, set_budget, fund), which is exactly why HireRail wraps a hire into one transaction.
- Job lifecycle: `OPEN -> FUNDED -> SUBMITTED -> COMPLETED | REJECTED | EXPIRED`
- First live implementation: BNBAgent SDK, Python, `pip install bnbagent`, repo https://github.com/bnb-chain/bnbagent-sdk

**x402 / Binance x402 (B402)**
- Flow: agent calls a paid endpoint, server replies HTTP 402 with payment terms, agent signs an off chain authorization, a facilitator settles on chain.
- Stablecoins supported on BSC: U, USD1, USDT, USDC.
- Auth methods per token (per launch coverage; Binance's own API reference was unreachable to automation, re-verify during M7): U and USD1 support `eip3009`, `permit2-exact`, `permit2-upto`. USDT and USDC on BSC do not implement EIP-3009, so they support `permit2-exact` and `permit2-upto` only. Verify USD1 EIP-3009 support directly before relying on it; if it holds, USD1 is the cleanest exact-amount path.
- `permit2-upto` IS bounded: the client signs a maximum, settlement must be at or below it, the Permit2 nonce enforces single use. Rule: prefer `permit2-exact` (or `eip3009` where the token supports it); accept `permit2-upto` only with a ceiling equal to the session budget, never larger.
- Never leave a standing Permit2 allowance alive past session expiry. Revoke on session end and show the revocation in the UI: it is a visible safety feature, not just hygiene.
- The BNBAgent SDK's signer already denylists dangerous unlimited allowance permits, keep that behaviour.
- B402 covers gas.
- Docs: https://www.binance.com/en/binancex402

**Altana (agentic wallet, partner track)**
- Non custodial wallet with on chain spending limits, time bounded session keys, and passkey recovery. Added as a second official agent wallet option in BNB Agent Studio v2 on 13 August 2026.
- What the track judges: agents transacting for themselves inside user set limits, sessions with real spend caps and expiries registered on chain, and revocation the user can see in the product. Judged by reading live transactions in the Altana explorer. Testnet counts, mainnet is stronger.
- Wallet options index: https://www.bnbchain.org/en/wallets

**PancakeSwap (partner track)**
- PancakeSwap Infinity supports hooks (custom on chain logic before and after swaps and liquidity actions).
- Developer docs: https://developer.pancakeswap.finance
- Track requirement: agents on the marketplace must deliver real benefit to PancakeSwap traders or LPs (smarter liquidity management, better yields, research spotting demand for new pools, safe automated swaps) **without ever putting user funds at risk**. Our agents never hold principal, they only execute inside an Altana session cap.

**Discovery and cross checks**
- Agent0 SDK (TypeScript and Python), ERC-8004 discovery over The Graph subgraphs, live on BSC: https://github.com/agent0lab/agent0-ts and https://docs.sdk.ag0.xyz/
- The Graph Agent0 BSC subgraph id `D6aWqowLkWqBgcqmpNKXuNikPkob24ADXCciiP8Hvn1K` (agent0-bsc-mainnet), endpoint `https://gateway.thegraph.com/api/<GRAPH_API_KEY>/subgraphs/id/D6aWqowLkWqBgcqmpNKXuNikPkob24ADXCciiP8Hvn1K`. Requires a free Graph API key, there is no keyless endpoint. The Agent entity field is `agentURI`, not `tokenURI`. Decision: we backfill from raw logs as primary (the data and freshness are ours), the subgraph is the cross check.
- AltLayer 8004scan explorer and public API: https://8004scan.io, API at `https://api.8004scan.io` (OpenAPI at /openapi.json, reads unauthenticated, for example `/api/v1/agents?chain_id=56`). Agent deep link: `https://8004scan.io/agents/bsc/{token_id}` (slug is `bsc`, and the site is an SPA that returns 200 for any path, validate by content).
- RPC (tested 17 Aug 2026 with a real 2,000 block eth_getLogs): primary `https://bsc-rpc.publicnode.com` (mainnet) and `https://bsc-testnet-rpc.publicnode.com` (Chapel). Most other public endpoints refused wide ranges. Paid fallback: Alchemy (BNB Chain support with archive access). Send a real User-Agent header on RPC calls, PublicNode 403s empty client UAs.

**Chain characteristics to design for**
- After the Maxwell upgrade (30 June 2025, blocks 1.5s to 0.75s) and the Fermi hard fork (14 January 2026, blocks to 0.45s), BSC runs sub second blocks, median gas around one cent, roughly 100M gas per second. Cheap frequent writes are viable, so publishing a snapshot daily costs nothing and looks serious. Do not build for expensive gas.

---

## 16. API spec

`crates/api`, axum, JSON, no auth for reads.

```
GET  /v1/agents
       ?q=              full text over name + description
       &category=       monitoring | rebalancing | grid-trading | yield | health-factor | pancakeswap | other
       &status=         live | flaky | down | dormant | measuring
       &min_trust=      0..100
       &min_uptime=     0..1
       &has_jobs=       bool
       &sort=           rank | trust | uptime | newest | jobs
       &cursor=         opaque
       &limit=          default 24, max 100
     -> { items: AgentCard[], next_cursor, total, total_unfiltered }

GET  /v1/agents/:id            -> full agent, current scores, endpoints, skills, links out
GET  /v1/agents/:id/uptime     -> 168 hourly buckets for the signature strip
GET  /v1/agents/:id/reviews    -> feedback list with per reviewer weight and flags, both raw and kept
GET  /v1/agents/:id/jobs       -> job history through our rail
GET  /v1/stats                 -> registry totals, live count, dormant count, sybil filtered count
GET  /v1/snapshots/latest      -> merkle root, tx hash, payload uri
GET  /v1/snapshots/:id/proof/:agentId -> leaf + proof for on chain verification
GET  /v1/methodology           -> the current parameter set as JSON, so the page renders from the real config
GET  /v1/health

POST /v1/hire/quote            -> { agentId, token, budget } -> calldata preview, fee breakdown, expiry
GET  /v1/jobs/:jobId           -> live job state
GET  /v1/events                -> SSE stream of new probes, new jobs, new snapshots (drives the live ticker)
```

`total_unfiltered` on the list endpoint exists purely so the UI can always say "showing 312 live of 204,881 registered". That number is the pitch, put it in the API contract so it can never be forgotten.

Response shapes:

```jsonc
// AgentCard
{
  "agent_id": "12345",
  "name": "Health Factor Guard",
  "description": "Watches Venus positions and unwinds before liquidation.",
  "categories": ["health-factor"],
  "status": "live",
  "liveness": 94,
  "uptime_7d": 0.987,
  "median_latency_ms": 210,
  "trust": 78,
  "trust_confidence": 0.62,
  "raw_star_avg": 4.9,
  "feedback_total": 412,
  "feedback_kept": 19,
  "jobs_completed": 27,
  "jobs_disputed": 0,
  "owner": "0x...",
  "registered_at": "2026-03-02T10:11:00Z",
  "endpoints": [{ "kind": "a2a", "url": "https://..." }],
  "pricing": { "model": "per_call", "token": "USDT", "amount": "0.25" }
}
```

Note `feedback_total` next to `feedback_kept`. Showing both in one row is the single most persuasive data cell in the product. Never ship one without the other.

---

## 17. Hire flow

The most important flow in the build. Two clicks from card to funded job.

### Path A: fixed price job (ERC-8183 escrow)

1. User clicks **Hire** on an agent card.
2. Sheet opens with: what the agent will do (spec text box, prefilled per category), budget with a stablecoin selector (USDT, USD1), deadline (default 24h), and the dispute window explained in one sentence.
3. User picks the wallet mode: **Direct** (their own wallet signs each step) or **Session** (Altana session wallet with a cap and expiry). Session is the default and the recommended path.
4. On confirm: approve exactly `budget` if needed, then `HireRail.hire(agentId, token, budget, deadline, specHash)` in one transaction that opens and funds the job.
5. UI switches to a live job panel driven by SSE: `Funded -> Agent working -> Submitted -> Dispute window (countdown) -> Completed`.
6. On completion, escrow releases through the EvaluatorRouter. Show the transaction hash and a one click **Leave feedback** that writes to the ERC-8004 Reputation Registry, and label it "counts more because it is attached to a paid job".

The spec text goes into `specHash = keccak256(spec)` on chain and the plaintext into our DB and the job payload, so the deliverable can be checked against what was asked.

### Path B: metered per call agent (x402)

1. User clicks **Try** on an agent that declares x402 pricing.
2. We open a session with a hard budget, for example 5 USDT and 1 hour.
3. Each call: hit the endpoint, receive 402 with terms, sign an exact amount authorization (`eip3009` or `permit2-exact`), facilitator settles, response returns.
4. The UI shows a running spend meter against the cap and a **Stop** button that revokes immediately.

Never sign an unbounded authorization. If an endpoint asks for `permit2-upto` with no ceiling, refuse and show the user why. That refusal screen is a good judge moment, screenshot it for the pitch.

### Path C: Altana session wallet (partner track)

1. In checkout, "Session" mode creates or reuses an Altana session key scoped to: this agent, this token, this cap, this expiry.
2. The cap and expiry are registered on chain. Show the resulting transaction and link it to the Altana explorer directly in the UI.
3. A persistent **Sessions** panel lists every active session with cap, spent, remaining, expiry, and a **Revoke** button that produces its own on chain transaction, also linked.
4. Everything the agent spends comes out of that session and cannot exceed the cap. Say this in the interface in one plain sentence, not in a tooltip.

The Altana judges read live transactions in their explorer. So make sure real caps and real revocations exist on chain before the deadline, and list those transaction hashes in `docs/SUBMISSION.md`.

### Failure handling
- Agent never submits: job expires, escrow refunds, UI shows a **Reclaim** button, and the agent's `jobs_disputed` increments.
- Agent submits garbage: user rejects within the dispute window, dispute goes to the OptimisticPolicy quorum, UI explains the timeline honestly including that we do not control the outcome.
- RPC drops mid flow: never leave a user unsure whether they paid. Persist the intent before sending, poll by transaction hash on reload, and show a recovery banner.

---

## 18. Frontend

### 18.1 Design direction

The subject is measurement. We are the instrument that tells you which agents are alive. So the interface should read like a **field diagnostic panel**, not like a web3 landing page. Dense, calm, measured, with the data doing the talking.

Deliberately avoiding: cream background with a big serif and a terracotta accent, near black with one acid green accent, and the hairline rule broadsheet look. Those are the three defaults that AI generated design falls into and any judge who has seen ten submissions will have seen all three.

**Palette (6 tokens)**
```
--paper    #EDEFE8   /* cool instrument paper, primary surface */
--ink      #0F1518   /* near black with a blue cast, all body type */
--depth    #16302F   /* deep pine, panels, detail page header, footer */
--signal   #FFB01F   /* amber. ONLY for live status and trust meter fill */
--dormant  #9AA3A0   /* grey. dead agents, disabled, secondary type */
--flag     #C4462F   /* clay red. sybil flags and destructive actions only */
```
Rule: `--signal` appears on screen no more than three times per viewport. It means "this is alive". If it is everywhere it means nothing.

**Type (3 roles)**
- Display: `Bricolage Grotesque` 700, tight tracking (-0.02em), used for page titles and the agent name only.
- Body: `Public Sans` 400 and 500.
- Data: `JetBrains Mono` for every number, address, hash, latency, percentage, and for the tiny uppercase eyebrow labels at 11px with +0.08em tracking.

Numbers are always mono and always tabular (`font-variant-numeric: tabular-nums`) so columns line up. That single detail is what makes a data product look built by someone who has shipped one.

**Layout**
- 12 column grid, 1200px max content width, generous 32px gutters, cards at 8px radius (not 0, not 24).
- Graph paper motif: a very low contrast 8px grid as the page background, visible only in the margins. It is the measurement metaphor, and it costs nothing.

**Signature element: the Probe Strip.**
Every agent card carries a 168 cell ribbon, 7 days by 24 hours, each cell one probe bucket. Amber for up, grey for down, hollow for no data. About 3px per cell, 2px gap, 16px tall. It is a seismograph readout for uptime. It is the one thing that makes a screenshot of our product instantly different from every other submission, and it is real data, not decoration. Hand roll it in SVG, add a hover tooltip with the exact hour and status, and give it a text alternative for screen readers.

**Motion (one orchestrated moment, then quiet).**
On first load of the marketplace, the grid renders the full registry count and then collapses to the live shortlist over about 900ms, with the counter ticking down from the total to the live number. It runs once per session, it respects `prefers-reduced-motion` (in which case just show the final state with the two numbers side by side), and nothing else on the site animates beyond 150ms hover states. The value proposition is literally the page load.

### 18.2 Tokens as code

Put these in `web/app/globals.css` as CSS variables and map them into the Tailwind theme. Do not scatter hex values through components. Derive every shade from the six tokens using `color-mix`.

### 18.3 Routes

```
/                    Marketplace. Filters, grid, the collapse moment, live ticker.
/agents/[id]         Agent detail. Probe strip large, reviews raw vs kept, jobs, hire.
/hire/[id]           Checkout. Can also open as a sheet over the detail page.
/jobs                My hires. Live states, reclaim, feedback.
/sessions            Altana sessions. Cap, spent, remaining, expiry, revoke.
/compare             Advantage Report. With agent vs without agent, per task.
/methodology         The scoring rules, rendered from /v1/methodology. Public and blunt.
/stats               Registry health. The 96 percent chart. Our headline evidence.
```

### 18.4 Page detail

**`/` Marketplace**
- Header line, mono eyebrow: `ERC-8004 / BNB SMART CHAIN`. Display title: "Most agents are not there." Sub line in body: "204,881 registered. 312 answering. We check every 30 minutes."
- Filter rail on the left, sticky: category (monitoring, rebalancing, grid trading, yield, health factor, PancakeSwap, other), status, minimum trust slider, minimum uptime slider, has completed jobs, sort.
- The dormant toggle sits at the bottom of the rail, off by default, labelled with the live count: `Show 204,569 dormant agents`.
- Grid of agent cards. Each card: name, one line description, category chip, status pill, the Probe Strip, and one data row in mono: `UPTIME 98.7% . TRUST 78 . KEPT 19/412 . JOBS 27`.
- A **Hire** button on the card itself. Discovery to hire in one click is what is being scored, so do not bury it on the detail page.
- Right rail or footer strip: live SSE ticker of the last probes and jobs. Small, mono, quiet. It proves the system is running while a judge is looking at it.

**`/agents/[id]` Agent detail**
- `--depth` header band with the agent name in display face, owner address, registered date, and the status pill.
- Full width Probe Strip with a 30 day toggle.
- Three stat blocks: Liveness (with the formula expanded on hover), Trust (with the confidence band drawn, not hidden), Jobs.
- **Reviews section, two columns side by side.** Left: "What the registry says", raw star average and total count. Right: "What we count", weighted score and kept count. Under it, the reviewer table with each reviewer's weight and flags (`funding_cluster`, `burst`, `one_shot`). This side by side is the most persuasive screen in the product. Design it first and design it best.
- Endpoints list with the last probe result per endpoint.
- Skills and pricing.
- Sticky hire bar at the bottom on mobile.
- Link out to 8004scan and BscScan for the same agent, because confidence looks like inviting the cross check.

**`/compare` Advantage Report**
Per task: the task statement, the manual baseline (time taken, result, cost), the agent run (time, result, cost), the delta, and links to the on chain job. Three tasks minimum. This page is the TermiX deliverable and it doubles as the strongest proof for the main judges.

**`/stats`**
The registry health page. A large chart of registered versus live over time from our own probe history, the category breakdown, the Sybil filter effect across the whole registry, and a plain paragraph explaining what we measured, when, and what we cannot claim. Cite the arXiv preprints as corroboration and clearly separate their numbers from ours.

### 18.5 States and copy

- **Empty (no results after filters):** "No agents match. Loosen the trust or uptime filter, or turn on dormant agents to see the other 204,569." Action button included. An empty screen is an invitation to act.
- **Measuring (new agent):** "Measuring. We need 24 probes before we score this one. First seen 3 hours ago."
- **No verified reviews:** "412 reviews, none from independent addresses. Ranked on uptime and completed jobs only."
- **Job pending:** "Funded. Waiting on the agent. Escrow releases to you automatically if nothing arrives by 14:02 tomorrow."
- **Error:** name what happened and what to do. "The RPC did not respond. Your transaction may still have gone through, we are checking by hash." Never apologise, never be vague.
- Buttons keep their verb through the whole flow: **Hire** produces "Hired", **Revoke** produces "Revoked". Sentence case everywhere. Plain verbs.

### 18.6 Quality floor

Responsive to 360px. Visible keyboard focus rings in `--ink`. All interactive elements reachable by tab. `prefers-reduced-motion` respected. Colour is never the only carrier of status: every status pill has a text label as well as a colour. Contrast checked against WCAG AA for `--ink` on `--paper` and `--paper` on `--depth`. Alt text on the Probe Strip summarising uptime in words.

---

## 19. End to end flows

**Flow 1: find and hire (the scored path, must be flawless)**
Land on `/` -> collapse animation shows 204,881 to 312 -> filter to "health factor" -> sort by rank -> read a card, see the Probe Strip solid amber -> click Hire -> sheet: describe the task, budget 5 USDT, deadline 24h, Session mode -> confirm -> one transaction -> live job panel -> agent submits -> accept -> escrow releases -> leave feedback. Time this. It should be under 90 seconds.

**Flow 2: verify a score.** Agent detail -> click the trust number -> methodology drawer with the formula and this agent's actual inputs -> "verify on chain" -> shows the snapshot id, Merkle proof, and a link to `TrustSnapshot.verify` on BscScan.

**Flow 3: bounded spending.** Checkout in Session mode -> Altana session created with cap and expiry, transaction linked -> `/sessions` shows cap, spent, remaining -> Revoke -> transaction linked -> agent's next attempt fails cleanly and the UI says why.

**Flow 4: agent owner.** Owner connects wallet -> sees their agents -> if dormant, a diagnostic panel says exactly what is broken: "tokenURI returns 404", "card is missing `endpoints`", "endpoint times out after 8s". This turns us into a tool agent builders actually use, which is the sustainability story judges ask about. Cheap to build, high value in the pitch.

**Flow 5: judge.** Land on `/` -> read the headline number -> open `/stats` -> open `/methodology` -> open one agent -> see raw versus kept reviews -> hire something for 1 USDT -> done. Optimise for this flow explicitly. Put a small `For judges` link in the footer going to a page with contract addresses, transaction hashes, the repo, the video, and a two minute self guided tour.

---

## 20. Partner track deliverables

### 20.1 TermiX (10,000 USDT)
Requirement: prove hiring an agent beats doing the job yourself, across at least three real tasks, with depth in trading, equities, and security weighted highest.

Deliver `/compare` plus `docs/ADVANTAGE_REPORT.md` with three tasks:
1. **Trading:** rebalance a PancakeSwap CL position across a volatile session. Baseline: manual rebalance at two points. Agent: continuous. Measure fees earned, time spent, and gas.
2. **Security:** screen a set of token addresses for honeypot and permission risks before a swap. Baseline: manual check on a block explorer. Agent: automated screen. Measure time and catches.
3. **Monitoring:** watch a lending position's health factor for 48 hours. Baseline: manual checks. Agent: continuous with an alert and an unwind trigger. Measure response latency to a threshold breach.

Every task must have a real on chain job id and transaction hashes. Show the losses too if the agent loses on a task. A report where the agent wins three out of three by a huge margin reads as fabricated. Honest deltas are more persuasive.

### 20.2 Altana (50,000 XP)
Deliver: session mode checkout, on chain caps and expiries, the `/sessions` page with visible revoke. Produce at least 10 real session transactions and 2 revocations on mainnet if possible, testnet if not. List every hash in `docs/SUBMISSION.md` with Altana explorer links.

### 20.3 PancakeSwap (1,000 CAKE)
Deliver two working reference agents, registered on ERC-8004 so they appear in our own marketplace (this also fixes the agent diversity requirement):
1. **Range keeper:** monitors a PancakeSwap Infinity CL position and rebalances the range when price exits it. Executes only through an Altana session cap. Never holds principal. Note: there is no Infinity subgraph, so position state is read on chain directly (CLPositionManager `0x55f4c8abA71A1e923edC303eb4fEfF14608cC226`, `modifyLiquidities` with encoded actions, Permit2 required). That is meaningfully more work than a subgraph query; budget for it in M7, and if M7 runs long, ship the yield scout alone and say so.
2. **Yield scout:** queries PancakeSwap pool data and reports better risk adjusted pool options for a given asset, with a written rationale. Read only, zero funds at risk, which is the safest possible demo. Pool data comes from the V3 BSC subgraph (`thegraph.com/explorer/subgraphs/Hv1GncLY5docZoGtXjo4kwbTvxm3MAhVZqBZE4sUT9eZ`) or the quoter contracts; there is no Infinity subgraph.

Both must be genuinely useful and honest about limits. Add a `pancakeswap` category chip in the marketplace so the track judges can find them in two clicks.

### 20.4 AltLayer
Use 8004scan as an independent cross check on our index, show a "verify on 8004scan" link on every agent detail page, and mention the divergence between our count and theirs on `/stats` if there is one. Cheap, honest, and it aligns our trust narrative with their explorer.

---

## 21. Build plan

Milestones, not dates. Finish one before starting the next. The order is deliberate: the hire flow lands early because a marketplace that cannot hire loses regardless of how good the scoring is.

**M0: Verify, scaffold, and build the gate**
Run every check in Section 27. Scaffold the workspace, docker compose with Postgres, migrations, `.env.example`, Foundry project, Next.js app that renders a static page with the design tokens. Write `scripts/verify.sh`, the `Makefile`, and the CI workflow now, before any feature exists, so the gate grows with the code instead of being retrofitted around it. Exit: `make demo` works, `make verify` exits 0 on the empty project, CI is green.

**M1: Index and see**
Indexer backfills Identity plus Reputation on BSC. Card fetcher populates names and endpoints. API serves `/v1/agents` and `/v1/stats`. Web shows a real grid of real agents with real names. Exit: the homepage shows the true registered count from chain.

**M2: The thesis**
Prober running on a schedule with history. Liveness scoring. Status buckets. The Probe Strip rendering real probe data. The collapse animation with the real two numbers. Exit: a screenshot that proves the 96 percent claim with our own data.

**M3: Hire, on testnet**
`HireRail.sol` deployed to BSC testnet. Full ERC-8183 lifecycle working against a stub agent we control. Checkout UI, job panel, SSE. Exit: a testnet job goes open to funded to submitted to completed with escrow released, end to end, from the UI.

**M4: Hire, on mainnet**
Deploy `HireRail` to BSC mainnet, verify the source, run at least two real jobs with small budgets. Start `scripts/tx_log.md`. Exit: two mainnet job transactions logged with hashes.

**M5: Trust**
Reviewer weighting, Sybil heuristics, Bayesian score, raw versus kept UI, `docs/METHODOLOGY.md`, `/methodology` page. Exit: the side by side review panel is live on a real agent with real flags.

**M6: Snapshots**
`TrustSnapshot.sol` deployed and verified on mainnet, publisher script running daily, `/v1/snapshots` and the verify drawer with a working Merkle proof. Exit: verify a proof on BscScan from the UI.

**M7: Partner tracks**
Altana session mode and `/sessions`. Two PancakeSwap agents built, registered, and live in our marketplace. x402 metered path. Exit: sessions with caps and revocations visible in the Altana explorer.

**M8: Advantage Report**
Run the three TermiX tasks for real, record both arms, write `/compare` and the doc. Exit: three tasks with real job ids.

**M9: Polish and prove**
Run the stub hunt (Section 29.5) and fix everything it finds. Run `scripts/audit_data.sh` and paste its table into the submission doc. Empty states, error states, the full zero dead ends table (Section 30.5), mobile, accessibility pass, `/stats`, judge mode, the `For judges` page, README with architecture diagram, `docs/SUBMISSION.md` with every address and hash. Write the five golden journeys and get them green. Then run the stranger test with three people and fix what it exposes. Exit: cold start under 5 minutes in a fresh container, and three strangers each completed a hire with no help, median under 90 seconds.

**M10: Demo and submit**
Record the video (Section 24), fill the intake form, tick all three partner boxes, submit with days to spare. Exit: submitted before 9 September, not on 9 September.

If time runs short, the cut order is: x402 metered path, the 30 day probe view, the agent owner diagnostic panel, `/stats` charts. Never cut: hire flow, probe strip, raw versus kept reviews, methodology page.

---

## 22. Testing

- `forge test` with a mainnet fork for anything touching ERC-8183. Coverage above 90 percent on `contracts/src`.
- Rust: unit tests on the scoring math with fixed fixtures. Build a synthetic Sybil dataset (one honest cluster, one farm with a shared funder, one burst attack) and assert the engine separates them. Ship that fixture in the repo, judges love a reproducible test of the core claim.
- Prober: test the SSRF guard explicitly with redirect chains to private ranges. Test timeout, TLS failure, 402 counted as alive, 404 counted as dead.
- API: integration tests against a seeded test database.
- Web: Playwright covering flow 1 (find and hire) and flow 3 (session and revoke) end to end against testnet.
- A single `make check` that runs everything. Put the command in the README.

---

## 23. Deployment and environment

`.env.example` (never commit real values):

```
BSC_RPC_HTTP=
BSC_RPC_HTTP_FALLBACK=
BSC_TESTNET_RPC_HTTP=
CHAIN_ID=56
IDENTITY_REGISTRY=
REPUTATION_REGISTRY=
AGENTIC_COMMERCE=
HIRE_RAIL=
TRUST_SNAPSHOT=
DATABASE_URL=postgres://trustlist:trustlist@localhost:5432/trustlist
SNAPSHOT_PUBLISHER_KEY=        # deploy/publish only, never in the web app
IPFS_GATEWAY=
IPFS_GATEWAY_FALLBACK=
GRAPH_API_KEY=                 # The Graph gateway key for the Agent0 cross check
PROBE_CONCURRENCY=64
PROBE_INTERVAL_SECS=1800
BSCSCAN_API_KEY=
NEXT_PUBLIC_API_URL=
NEXT_PUBLIC_CHAIN_ID=56
```

Rules:
- Two RPC providers, always. Fail over automatically and log the switch.
- The publisher key signs only `TrustSnapshot.publish`. It holds a few dollars of BNB and nothing else. Say this in the README.
- `forge verify-contract` on every deployment. An unverified contract on a hackathon submission is a self inflicted wound.
- Keep `docs/ADDRESSES.md` updated on every deploy, with BscScan links.

---

## 24. Demo video script (3 minutes, judges watch the first 20 seconds)

```
0:00  Cold open, no logo, no intro music. Screen recording of the homepage.
      Counter ticks 204,881 down to 312. Voice: "BNB Chain has two hundred
      thousand registered agents. Three hundred and twelve of them answered
      when we called this morning."

0:20  Cut to /stats. "We know because we probe every declared endpoint every
      thirty minutes and we keep the history. This is our data, not a claim."

0:40  Agent detail. Point at the side by side. "This agent has four hundred
      and twelve five star reviews. Nineteen of them came from addresses that
      are not funded by the same wallet. We rank on the nineteen."

1:05  Click Hire. Session mode. Show the cap and expiry. One transaction.
      "Five USDT cap, one hour expiry, registered on chain. The agent cannot
      spend a cent more than that."

1:30  Job panel goes funded, submitted, completed. Show the BscScan tab with
      the escrow release. "Real job, real escrow, mainnet, eleven seconds ago."

1:50  /sessions, hit Revoke, show the transaction. "And I can cut it off."

2:05  /compare. One task, the numbers, the delta. "Three tasks measured both
      ways. The agent wins two of them. Here is the one it loses and why."

2:25  /methodology. Scroll the formulas. "Every number is computed by rules
      we publish, from data anyone can pull, anchored on chain daily."

2:45  Close on the homepage. "Anyone can list two hundred thousand agents.
      TrustList tells you which three hundred are real."
```

Record at 1440p. No stock music. No AI voice if you can read it yourself, a real voice reads as a real team. Show real transaction hashes on screen, and leave them readable for a full second.

---

## 25. Submission checklist

- [ ] Public repo, MIT or Apache 2.0, clean history, no keys in git history
- [ ] README: what it is, the problem with the evidence, architecture diagram, how to run locally in under five commands, coverage number
- [ ] `docs/SUBMISSION.md`: contract addresses with BscScan links, mainnet transaction hashes proving activity inside the window, Altana session and revoke hashes, snapshot root and proof example
- [ ] `docs/METHODOLOGY.md` and the live `/methodology` page agree with each other
- [ ] `docs/ADVANTAGE_REPORT.md` with three real tasks
- [ ] Contracts verified on BscScan
- [ ] Live deployment URL, up and stable, tested from a phone
- [ ] Demo video uploaded and linked
- [ ] Intake form submitted with TermiX, Altana, and PancakeSwap boxes all ticked
- [ ] At least two successful mainnet transactions from our contracts inside the build window, logged
- [ ] Agents visible in all four reference categories plus PancakeSwap
- [ ] `make verify` passes from a clean clone, CI badge green
- [ ] `scripts/audit_data.sh` run and its expected versus actual table pasted into `docs/SUBMISSION.md`
- [ ] Cold start test passes in a fresh container, under 5 minutes and 3 commands
- [ ] All five golden journeys pass, with journey 01 timing printed
- [ ] Stranger test run with three people, median under 90 seconds, fixes logged in `docs/USER_TESTS.md`
- [ ] Every row in the zero dead ends table (Section 30.5) manually walked and ticked
- [ ] Judge mode works: a stranger with no funds can complete a real testnet hire
- [ ] Uptime monitor live and alerting through 23 September
- [ ] Submitted at least three days before 9 September 2026

---

## 26. Rules for the coding agent (put this in CLAUDE.md)

1. Read `SPEC.md` before every significant task. When something in the code contradicts the spec, ask, do not silently pick.
2. No em dashes, no en dashes, anywhere. Code comments, commit messages, UI copy, docs, all of it.
3. Never fabricate a contract address, an ABI, an endpoint, a package version, or a statistic. Verify against the live source or say you could not.
4. No mock data after Milestone 1. If a screen has nothing to show, build the empty state instead of faking rows.
5. Money is `rust_decimal` or `BigInt`. Never `f64`, never JavaScript `number`, for token amounts.
6. Every external call gets a timeout. Every loop over agents gets a rate limit. Every user input that becomes a URL gets the SSRF guard.
7. Never request an unbounded token allowance. Exact amounts only.
8. Private keys come from the environment and are used only in scripts, never in `api`, never in `web`.
9. Prefer boring, readable code over clever code. A judge may read this repo.
10. Commit at every working state with a plain message describing what changed. Small commits.
11. When you finish a milestone, stop and report: what works, what does not, what you had to change from the spec and why.
12. If you are stuck for more than two attempts on the same error, stop and ask rather than rewriting the architecture around the problem.
13. Do not add dependencies without saying why. Do not add a UI component library.
14. Do not ship a token, a points system, or an airdrop.
15. When in doubt about a claim shown to a user, weaken the claim. Underclaiming is survivable, overclaiming in front of judges is not.

---

## 27. Verification tasks, do these first

Do not write feature code until these are answered. Report the results before continuing.

1. Open https://www.bnbchain.org/en/hackathons/smart-money-era including the resources tab. Confirm the exact deadline, the submission requirements, and whether the full judging rubric and reference agent repo have now been published. If the rubric differs from Section 2, flag the differences and propose spec changes.
2. Verify on BscScan that the ERC-8004 Identity Registry and Reputation Registry addresses in Section 15 are correct and are the ones actually in use on BSC mainnet. Confirm the ABI and the exact event signatures for registration and feedback. Report the real deployment block for each so the backfill has a start point.
3. Verify the ERC-8183 AgenticCommerce address, and find the current `EvaluatorRouter` and `OptimisticPolicy` addresses. Read https://github.com/bnb-chain/bnbagent-sdk and confirm the job lifecycle function names and signatures.
4. Confirm which stablecoins the x402 facilitator supports on BSC right now and which auth methods are live. Confirm whether `permit2-upto` can be bounded and, if not, exclude it entirely.
5. Find the current Altana developer documentation. Determine exactly how a session key with an on chain cap and expiry is created and revoked, whether there is an SDK, and what the explorer URL pattern is. This drives Section 17 path C and one of the three partner prizes, so get concrete answers, not marketing pages.
6. Check https://developer.pancakeswap.finance for the current Infinity CL position and hooks interfaces on BSC, and note the subgraph or API endpoint for pool data.
7. Check the Agent0 SDK and The Graph Agent0 subgraph. Get the live BSC subgraph endpoint and a sample query returning agents with their `tokenURI`. Decide whether we backfill from the subgraph or from raw logs, and say which and why.
8. Check 8004scan for its builder API and confirm what an agent detail URL looks like so we can deep link.
9. Confirm current BSC mainnet and testnet public RPC endpoints that actually serve `eth_getLogs` over wide ranges without rate limiting us into uselessness. Recommend one paid fallback.
10. Sanity check the arXiv preprints 2606.26028 and 2606.12128 exist and say what Section 3 claims they say. If a number is different, use the real number. We must never quote a statistic we have not opened.
11. Report the current registered agent count on BSC from chain. That number goes in the homepage headline and it must be ours.

After reporting, propose any spec amendments as a short diff list, then wait for confirmation before starting M0.

---

## 28. Resources

**Competition**
- Hackathon page: https://www.bnbchain.org/en/hackathons/smart-money-era
- Announcement: https://www.bnbchain.org/en/blog/build-the-era-build-the-official-bnb-agent-studio-marketplace
- BNB Chain AI agent landscape: https://www.bnbchain.org/en/blog/bnb-chain-ai-agent-landscape-agents-tools-and-payments
- AI agent solutions and tools: https://www.bnbchain.org/en/solutions/ai-agent
- Wallets index (Altana, Trust Wallet AgentKit): https://www.bnbchain.org/en/wallets

**Standards and SDKs**
- ERC-8004 contracts: https://github.com/erc-8004/erc-8004-contracts
- BNBAgent SDK (ERC-8183, Python): https://github.com/bnb-chain/bnbagent-sdk
- Agent0 SDK (TypeScript): https://github.com/agent0lab/agent0-ts
- Agent0 docs: https://docs.sdk.ag0.xyz/
- The Graph Agent0 subgraphs: https://thegraph.com/blog/agent0-subgraphs-live-erc-8004-agent-economy/
- 8004scan: https://8004scan.io
- 8004scan docs: https://docs.altlayer.io/altlayer-documentation/8004-scan/overview

**Payments and partners**
- Binance x402: https://www.binance.com/en/binancex402
- TermiX app: https://app.termix.ai
- PancakeSwap developer docs: https://developer.pancakeswap.finance

**Evidence**
- arXiv:2606.26028, "Can Trustless Agents Be Trusted? An Empirical Study of the ERC-8004 Decentralized AI Agent Ecosystem" (preprint, window ends 13 May 2026)
- arXiv:2606.12128, "From Agent Identity to Agent Economy: Measuring the Operational Readiness of ERC-8004 AI Agents"

---

## 29. Completion gates: proving the work is actually done

Coding agents fail in one specific way. They report success over stubs, mock arrays, swallowed exceptions, and functions that return a plausible shape without doing anything. The report is confident and the feature is hollow. So we do not trust reports. We test claims, mechanically, and the test runs on every commit.

### 29.1 No claim without a receipt

Every milestone ends with this exact report. No prose milestone summaries, no "everything is working now".

```
MILESTONE Mx REPORT

DONE
  - <thing>            proof: <command or tx hash or file path>
  - <thing>            proof: <...>

NOT DONE
  - <thing>            reason: <...>

DEVIATED FROM SPEC
  - <spec section>     changed: <what>   why: <why>

STUBS AND SHORTCUTS STILL IN THE CODE
  - <file:line>        what it fakes: <...>   when it gets replaced: <milestone>

RUN THIS YOURSELF
  $ <exact commands, in order, from a clean checkout>

GATE
  make verify -> <exit code>
```

The "stubs and shortcuts" block is mandatory and must never be empty by claiming there are none unless `make verify` proves it. An agent that hides a stub once loses the benefit of the doubt for the rest of the build.

### 29.2 `make verify`: the gate

Build this in M0, before any feature code. It exits non zero on the first failure and prints what failed and where. Every check below is required.

```bash
#!/usr/bin/env bash
# scripts/verify.sh
set -euo pipefail
fail() { echo "GATE FAIL: $*" >&2; exit 1; }
say()  { printf '\n== %s ==\n' "$1"; }

say "1. no unfinished markers in shipped code"
! grep -rInE 'TODO|FIXME|XXX|HACK|WIP:' \
    --include='*.rs' --include='*.ts' --include='*.tsx' --include='*.sol' \
    crates/ web/app web/components web/lib contracts/src \
  || fail "unfinished markers found above"

say "2. no rust stubs"
! grep -rInE 'todo!\(|unimplemented!\(|panic!\("not implemented' crates/ \
  || fail "rust stubs found above"

say "3. no fake data"
! grep -rInE 'mockAgent|mockData|fakeData|dummyData|sampleAgents|placeholderAgent|lorem ipsum|0xdeadbeef|0x1234567890' \
    --include='*.rs' --include='*.ts' --include='*.tsx' \
    crates/ web/app web/components web/lib \
  || fail "mock or placeholder data found above"

say "4. no swallowed errors"
! grep -rInE 'catch\s*\([^)]*\)\s*\{\s*\}|catch\s*\{\s*\}|\.catch\(\(\)\s*=>\s*\{\s*\}\)' web/ \
  || fail "empty catch blocks found above"
! grep -rIn 'let _ = ' crates/*/src --include='*.rs' | grep -v '_ = tracing' \
  || fail "discarded results found above, handle or log them"

say "5. unwrap budget in service code"
COUNT=$(grep -rIn '\.unwrap()' crates/api/src crates/prober/src crates/indexer/src crates/trust/src \
  | grep -v '/tests/' | grep -v 'main.rs' | wc -l)
[ "$COUNT" -le 5 ] || fail "$COUNT unwraps in service code, budget is 5"

say "6. typecheck, lint, build"
cargo clippy --workspace --all-targets -- -D warnings
cargo fmt --check
( cd web && npx tsc --noEmit && npm run build )
! grep -rIn ': any\b' web/app web/components web/lib --include='*.ts' --include='*.tsx' \
  || fail "any types found above"

say "7. tests"
cargo test --workspace
( cd contracts && forge test -vv )
COV=$( cd contracts && forge coverage --report summary | awk '/^\| Total/ {gsub(/%/,"",$4); print int($4)}' )
[ "${COV:-0}" -ge 90 ] || fail "contract coverage ${COV}% is under 90"

say "8. no secrets"
! grep -rInE '(0x)?[a-fA-F0-9]{64}' --include='*.ts' --include='*.rs' --include='*.env*' \
    --exclude='*.lock' crates/ web/ contracts/script 2>/dev/null | grep -viE 'hash|root|digest|keccak|selector' \
  || fail "possible private key material found above"
! git log --all -p | grep -qE 'PRIVATE_KEY\s*=\s*0x[a-fA-F0-9]{64}' \
  || fail "a private key exists somewhere in git history"

say "9. env completeness"
for v in $(grep -oE '^[A-Z_]+' .env.example); do
  grep -rq "$v" crates/ web/ contracts/script || fail "$v in .env.example is never read"
done

say "10. every documented route answers"
for r in /v1/health /v1/stats /v1/agents /v1/snapshots/latest /v1/methodology; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "${API:-http://localhost:8080}$r")
  [ "$code" = "200" ] || fail "$r returned $code"
done
for p in / /jobs /sessions /compare /methodology /stats; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "${WEB:-http://localhost:3000}$p")
  [ "$code" = "200" ] || fail "page $p returned $code"
done

say "11. the database contains real work"
psql "$DATABASE_URL" -tAc "select count(*) from agents"        | awk '$1<1000 {exit 1}' || fail "under 1000 agents indexed"
psql "$DATABASE_URL" -tAc "select count(*) from probe_results" | awk '$1<5000 {exit 1}' || fail "under 5000 probes recorded"
psql "$DATABASE_URL" -tAc "select count(*) from feedback"      | awk '$1<100  {exit 1}' || fail "under 100 feedback rows"

say "12. deployed addresses are real and verified"
bash scripts/check_addresses.sh   # every address in docs/ADDRESSES.md has bytecode and verified source

echo; echo "GATE PASS"
```

Adjust thresholds in check 11 upward as the build progresses. Never adjust one downward to make a run pass. If a check is genuinely wrong, change it in a separate commit that says why, and tell me.

Milestone specific additions to the gate:

| From milestone | Extra check added to the gate |
|---|---|
| M2 | at least 200 agents have 24 or more probes, and at least one agent has uptime above 0.9 |
| M3 | a testnet job exists in state `completed` with a settle transaction hash |
| M4 | at least 2 mainnet transactions from `HireRail`, hashes present in `scripts/tx_log.md` |
| M5 | at least one agent has `feedback_total` greater than `feedback_kept`, proving the filter fires |
| M6 | `TrustSnapshot.latest()` returns a root newer than 26 hours |
| M7 | at least one Altana session with a cap and one revocation, hashes in `docs/SUBMISSION.md` |
| M8 | `/compare` returns three tasks each with a real job id |

### 29.3 The data honesty audit

Passing a lint gate does not prove the numbers on screen are true. This script picks live data at random and re-derives it independently. Run it at M5 and again before submission.

`scripts/audit_data.sh` must:

1. Pull 5 random agents from `/v1/agents`. For each, read `tokenURI(agentId)` straight from chain with `cast call` against a different RPC than the indexer uses, fetch the card, and assert the name and endpoints match what the API returned. Any mismatch is a bug in the indexer, not in the audit.
2. Pick one agent. Recompute `uptime_7d` directly with SQL over `probe_results` and assert it matches the API value to within 0.001.
3. Pick one agent with reviews. Recompute the trust score by hand from the `feedback` and `reviewer_weights` tables using the formula in Section 13 and assert it matches to within 0.5.
4. Take the latest snapshot, pull the published leaf set, rebuild the Merkle root locally, and assert it equals the root stored on chain.
5. Take one agent's leaf, call `TrustSnapshot.verify` on chain with the proof, and assert it returns true.
6. Assert `total_unfiltered` from `/v1/stats` equals our indexed count of `Registered` events, and cross check both against the registry's `_lastId` counter read from ERC-7201 namespaced storage slot `0xa040f782729de4970518741823ec1276cbcd41a0c7493f62d173341566a04e00` (the contract is not ERC721Enumerable, there is no `totalSupply`). The indexed event count is the primary source because it is our own measurement; the storage slot is the independent cross check. Put the diff between the two methods in the audit table: two independent methods agreeing is a stronger artifact than either alone.

Print a short table of expected versus actual for all six. Put that table in `docs/SUBMISSION.md`. A judge reading "we re-derive our own numbers from chain with a different RPC and here is the diff" is worth more than any feature.

### 29.4 Spec drift audit

Paste this at the end of every milestone:

```
Re-read SPEC.md sections <the ones this milestone touched>. Go file by file
through what you wrote. List every place the code differs from the spec, and
classify each one as: intentional (with the reason), accidental (fix it now),
or incomplete (still a stub, say which milestone finishes it). Do not summarise.
If a section of the spec was not implemented at all, say so plainly.
```

### 29.5 The stub hunt

Paste this once at M9, before polish:

```
You are auditing someone else's code and you are paid to find what they faked.
Search the whole repo for: functions that return a hardcoded value, error paths
that silently succeed, retry loops with no limit, timeouts set to zero or
missing, config read but never used, UI components rendering constants instead
of props, API handlers that ignore their query parameters, and any place a
number shown to a user does not come from the database or the chain.
Produce a list with file and line. Do not fix anything yet. Do not defend the
code. Just find it.
```

Then fix the list, then run `make verify` and `scripts/audit_data.sh` again.

### 29.6 CI

`.github/workflows/verify.yml` runs `make verify` on every push, with a Postgres service container and a seeded database. Put the badge at the top of the README. A green badge on a hackathon repo is a small thing that signals a serious builder, and a red one on submission day is fatal.

---

## 30. Effortless first run: acceptance with a real human

Two numbers define done. Both are measured, not asserted.

**Cold start: under 5 minutes and 3 commands** from `git clone` on a machine that has never seen this project to a working local stack showing real data.

**First hire: under 90 seconds** for a person who has never seen the product to go from the landing page to a completed job, with no help and no questions.

If either number is missed, the build is not finished, regardless of what works.

### 30.1 One command to run it

```
make demo
```

That single command must: start Postgres, run migrations, restore a checkpoint database dump so nobody waits on a full registry backfill, launch indexer, prober, trust engine, api, and web, wait for health, and open the browser. Ship the checkpoint dump as a release asset and have `make demo` download it if absent. Nobody should have to wait six hours for a backfill to see the product.

Other targets: `make verify` (Section 29.2), `make e2e` (Section 30.6), `make check` (fmt, clippy, tests), `make coldstart` (Section 30.3), `make reset` (nuke local state and start clean).

### 30.2 Cold start, tested not assumed

`scripts/coldstart_test.sh`, run inside a fresh container so it cannot accidentally use anything already installed:

```bash
docker run --rm -it -v "$PWD":/src ubuntu:24.04 bash -c '
  apt-get update -qq && apt-get install -qq -y git curl make docker.io
  git clone /src /tmp/fresh && cd /tmp/fresh
  cp .env.example .env
  # only two values should ever need filling in by hand
  sed -i "s|^BSC_RPC_HTTP=.*|BSC_RPC_HTTP='"$BSC_RPC_HTTP"'|" .env
  time make demo
'
```

Assert: it succeeds, and the homepage returns 200 with a live agent count above zero, in under 5 minutes. If it needs a fourth command or a third hand edited value, the README is wrong and the setup is wrong. Fix the setup, not the README.

Run this after every dependency change and once more the day before submission. Cold start rot is the single most common reason a working hackathon project fails in front of a judge.

### 30.3 The stranger test

Automated tests prove the software runs. They cannot prove a person can use it. So run this three times with three different people, at least one of whom does not use crypto daily.

Protocol, follow it exactly:

1. Fund a fresh wallet with 3 USDT and enough BNB for gas. Hand them the device with the wallet already connected and the browser on our homepage.
2. Say one sentence: "Hire an agent to do something for you." Say nothing else.
3. Start a timer. Do not help. Do not explain. Do not react to mistakes. Write down every single moment they pause, squint, scroll back, or say "wait".
4. Stop the timer when a job reaches `completed`, or at 5 minutes, whichever comes first.
5. Afterwards, ask two questions only: "What did you think that number meant?" pointing at the trust score, and "Were you worried about anything?"

Rules for reading the result:

- Any hesitation over 10 seconds is a UI bug. Fix the interface, never explain the person's mistake away.
- If they could not say what the trust number meant, the label is wrong. Our entire thesis is that number, so it has to survive first contact.
- If they were worried about their money, the session cap is not visible enough at the moment of decision.
- Log every fix in `docs/USER_TESTS.md` with the observation that caused it. Include that file in the repo. Judges scoring usability will read it and it is evidence no competitor will have.

Target after fixes: median under 90 seconds, zero questions asked.

### 30.4 Judge mode

Judges may not want to spend their own money, and a hire flow they will not complete is a hire flow they cannot score. So build a one click path that lets anyone finish a real job for free.

- Judge mode runs on **mainnet**, not testnet. The ERC-8004 registries are not deployed on BSC Chapel, so a testnet judge mode would mean hiring from a registry we deployed and seeded ourselves: synthetic data, and the demo loses its teeth. On mainnet the judge hires a real registered agent from the real registry.
- A prefunded relayer wallet we control covers gas and a 1 USDT budget for the first hire per browser session, rate limited hard by IP and session. At around a cent of gas per transaction, a hundred judge hires costs on the order of a hundred dollars, which is nothing against the prize.
- The full flow still runs for real: real ERC-8183 job, real escrow, real settlement, real transaction hashes on BscScan. Nothing is simulated.
- A single banner explains it in one sentence: "Funded by us, so you can run a real hire without spending anything."
- Self deployed testnet registry instances (from the official erc-8004-contracts repo) exist only for CI and the e2e suite, where synthetic data is correct. Say so in the README.

This is cheap to build and it directly raises the odds a judge completes the one flow they are told to score.

### 30.5 Zero dead ends

Every state below must be reachable in testing and must show what happened plus what to do next. Walk this list manually before submission and tick each one.

| State | Required behaviour |
|---|---|
| No wallet extension installed | Site fully browsable read only, hire button explains and links to a wallet |
| Wrong network | Inline switch network button, not a modal wall |
| Zero BNB for gas | Named clearly, links to the faucet in judge mode |
| Insufficient token balance | Shows required versus held, does not let the transaction fail on chain |
| Allowance too low | Handled inside the same flow, one extra step, clearly labelled |
| User rejects the transaction in the wallet | Returns to checkout with inputs preserved, no lost state |
| Transaction stuck pending | Live status with the hash, a "check on BscScan" link, never a spinner with no exit |
| Page refreshed mid flow | Recovers from the persisted intent and the transaction hash, shows where the user is |
| Back button mid flow | Does not create a second job, does not lose the first |
| API down | Banner naming it, cached data still renders, hire disabled with the reason |
| RPC down | Failover happens silently, if both fail the banner says so and reads stay available |
| Agent endpoint dies mid job | Job panel explains the expiry timer and the reclaim path |
| Agent submits nothing before deadline | Reclaim button appears automatically, no support needed |
| Zero search results | Empty state with a specific action, per Section 18.5 |
| 360px mobile | Full flow completable, hire bar sticky, no horizontal scroll |
| Slow connection | Skeletons that match final layout, no layout shift, no infinite spinner |
| Screen reader | Probe strip has a text summary, status is never colour only |

### 30.6 The five golden journeys

Playwright, in `web/e2e/golden/`, run by `make e2e` against BSC testnet, and run in CI nightly. These are not unit tests. Each one is a full journey by a fake stranger, and each one must pass before submission.

```
01-discover-and-hire.spec.ts     land, filter, open a card, hire, fund, complete, feedback
02-session-cap-and-revoke.spec.ts create a capped session, spend inside it, revoke, prove the next spend fails
03-verify-a-score.spec.ts         open an agent, open the trust drawer, verify the Merkle proof on chain
04-reclaim-expired-job.spec.ts    hire an agent that never delivers, wait for expiry, reclaim escrow
05-cold-first-visit.spec.ts       no wallet, no funds, browse everything, read methodology, hit judge mode
```

Test 01 must also assert wall clock duration under 90 seconds excluding block confirmation waits. Print the timing in the CI log. That number is a headline for the pitch, so measure it continuously rather than guessing it at the end.

### 30.7 Demo day resilience

- Uptime monitor pinging `/v1/health` every minute with an alert to your phone, running from the day you submit through the end of judging on 23 September.
- A status line in the footer showing indexer lag in blocks and last probe time. If we are behind, we say so. A product that admits its own lag reads as trustworthy, a stale product that pretends is worse.
- Two RPC providers configured and the failover path actually tested by revoking the primary key and watching it switch.
- A database backup taken the day of submission and a documented restore command.
- The demo video and a screenshot set stored somewhere reachable even if the deployment dies. If the site is down when a judge clicks, the video is the only thing standing between you and a zero.

### 30.8 Prove the 90 seconds

Instrument time to first completed hire, per anonymous session, no personal data, and put the median on the `For judges` page as a live number. Claiming a product is easy is weak. Showing that the median stranger completed a real on chain hire in 71 seconds, measured, is the kind of thing that decides a tie.

---

## 31. The one thing to remember

Every hour spent making the marketplace prettier is worth less than an hour spent making one number on it undeniably true. The competition is not "who built the nicest agent directory". It is "who can be trusted to run the front door of BNB Chain's agent economy". Build like the answer to that is a measurement system with a storefront attached, because it is.

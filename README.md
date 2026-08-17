# TrustList

The ERC-8004 agent marketplace for BNB Smart Chain that tells you which agents are actually alive and which of those you can trust.

Roughly 269,000 agents are registered on BSC under ERC-8004 (our own chain read, 17 August 2026). Almost none of them answer. TrustList probes every declared endpoint on a schedule, keeps the history, weights every review by how independent the reviewer actually is, and turns finding an agent into hiring one through ERC-8183 escrow with a hard, visible, revocable spend cap.

Built for the BNB Chain "Build the Era" hackathon. `SPEC.md` is the single source of truth for the build; `docs/VERIFICATION.md` records what was verified against live sources before any code was written.

## Status

Milestone M0: scaffold, completion gate, CI. No feature claims yet. The homepage deliberately shows no numbers until the indexer measures them.

## Run it locally

```
cp .env.example .env    # defaults work for local development
make demo               # postgres, migrations, api, web
```

Then open http://localhost:3000. Health check: http://localhost:8080/v1/health.

Other targets: `make verify` (the completion gate, runs in CI on every push), `make check` (format, lint, tests), `make reset` (wipe local state).

## Layout

```
contracts/   Foundry project (TrustSnapshot, HireRail arrive at M3-M6)
crates/      Rust workspace: common, indexer, prober, trust, api
migrations/  Postgres schema
web/         Next.js app
scripts/     verify.sh gate, measurement scripts
docs/        verification record, methodology (M5), submission (M9)
```

## Honesty rules

Every number shown in the UI traces back to something read from chain or measured by our own prober. No mock data past M1. The gate in `scripts/verify.sh` enforces this mechanically on every push and fails the build on stubs, placeholder data, swallowed errors, or unverified claims.

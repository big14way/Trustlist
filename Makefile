# TrustList build targets. See SPEC.md Sections 29 and 30.

SHELL := /bin/bash

.PHONY: demo verify check e2e coldstart reset db migrate

# Start the local stack: Postgres, migrations, a real data seed, then the
# indexer, prober, trust engine, api, and web. See SPEC Section 30.1.
demo:
	bash scripts/demo.sh

db:
	docker compose up -d db
	docker compose exec -T db sh -c 'until pg_isready -U trustlist -d trustlist; do sleep 1; done'

verify:
	@set -a && source .env 2>/dev/null || source .env.example; set +a; \
	bash scripts/verify.sh

check:
	cargo fmt --check
	cargo clippy --workspace --all-targets -- -D warnings
	cargo test --workspace
	cd contracts && forge test
	cd web && npx tsc --noEmit
	bash scripts/test_agents.sh

e2e:
	@set -a; . ./.devchain.env; set +a; \
	cd web && DEV_KERNEL=$$DEV_KERNEL DEV_TOKEN=$$DEV_TOKEN npx playwright test e2e/golden

coldstart:
	bash scripts/coldstart_test.sh

reset:
	docker compose down -v
	rm -rf web/.next

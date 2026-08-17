# TrustList build targets. See SPEC.md Sections 29 and 30.

SHELL := /bin/bash

.PHONY: demo verify check e2e coldstart reset db migrate

# Start the local stack: Postgres, migrations, api, web.
# Indexer, prober, and trust engine join this target at their milestones.
demo: db
	@set -a && source .env 2>/dev/null || source .env.example; set +a; \
	cargo build --workspace && \
	(cargo run -p api &) && \
	(cd web && npm run dev &) && \
	echo "waiting for health" && \
	for i in $$(seq 1 60); do \
	  curl -sf http://localhost:$${API_PORT:-8080}/v1/health >/dev/null && break; sleep 1; \
	done && \
	curl -sf http://localhost:$${API_PORT:-8080}/v1/health && echo && \
	echo "api up, web starting at http://localhost:3000"

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

e2e:
	cd web && npx playwright test e2e/golden

coldstart:
	bash scripts/coldstart_test.sh

reset:
	docker compose down -v
	rm -rf web/.next

#!/usr/bin/env bash
# Cold start, tested not assumed. SPEC Section 30.2.
#
# Clone into a container that has never seen this project, install only what
# the README tells a stranger to install, run `make demo`, and assert the
# homepage renders real agents. The point is to catch the "works on my
# machine because I already had it installed" failure before a judge does.
#
# The container drives the host's Docker (for Postgres) over the mounted
# socket and shares the host network so it can reach the published port.
# That combination only behaves on Linux, so on anything else this script
# says so rather than printing a pass it did not earn.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$(uname -s)" != "Linux" ]; then
  cat >&2 <<'MSG'
Cold start must run on Linux.

It needs --network host and the Docker socket to behave the way they do on a
normal machine, and Docker Desktop on macOS or Windows does not give that
faithfully. Run this on a Linux box or let CI run it: the coldstart job in
.github/workflows/verify.yml does exactly this on ubuntu-latest.
MSG
  exit 2
fi

if [ -z "${BSC_RPC_HTTP:-}" ]; then
  echo "set BSC_RPC_HTTP first, it is the one value a stranger must fill in" >&2
  exit 2
fi

BUDGET_SECS="${COLDSTART_BUDGET_SECS:-300}"
START=$SECONDS

# GH_TOKEN is passed through only so the prebuilt binaries can be downloaded
# while this repository is still private. A stranger following the README has
# no token, and does not need one: a public repository serves release assets
# anonymously. The day this repository goes public, which it must before
# judging, this line comes out and nothing else changes. Without a token the
# download simply 404s and the container compiles instead, which is slower
# but still correct.
docker run --rm \
  --network host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD":/src:ro \
  -e "BSC_RPC_HTTP=$BSC_RPC_HTTP" \
  -e "GH_TOKEN=${GH_TOKEN:-}" \
  ubuntu:24.04 bash -c '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Only what the README asks a stranger to have.
apt-get update -qq
# docker.io ships the CLI but not the compose v2 plugin, and make demo drives
# Postgres through `docker compose`. docker-compose-v2 supplies the plugin
# (verified: 2.40.3 on noble).
apt-get install -qq -y git curl make build-essential pkg-config libssl-dev \
  docker.io docker-compose-v2 ca-certificates python3 >/dev/null

curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable >/dev/null
. "$HOME/.cargo/env"

curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
apt-get install -qq -y nodejs >/dev/null

# The repo is bind mounted from the host and owned by the host user, so git
# inside the container sees a different uid and refuses to touch it. Marking
# it safe is about the container boundary, not about trusting the contents.
git config --global --add safe.directory /src
git config --global --add safe.directory /src/.git

git clone -q /src /tmp/fresh
cd /tmp/fresh
cp .env.example .env
sed -i "s|^BSC_RPC_HTTP=.*|BSC_RPC_HTTP=$BSC_RPC_HTTP|" .env

SETUP_DONE=$SECONDS
echo "--- toolchain ready after ${SETUP_DONE}s, starting make demo"

make demo

# Assert in here, not on the host. make demo leaves the services running as
# background processes of this container, and the container is torn down the
# moment this script returns, so a check that runs afterwards is testing a
# stack that no longer exists. The first version of this script did exactly
# that and reported an empty homepage for a stack that had come up fine.
echo
echo "--- checking what a stranger would actually see"
HOMEPAGE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:3000/" || echo 000)
AGENTS=$(curl -sf "http://localhost:8080/v1/stats" \
  | python3 -c "import json,sys;print(json.load(sys.stdin).get(\"registered\",0))" 2>/dev/null || echo 0)
echo "homepage http $HOMEPAGE, $AGENTS agents indexed"
echo "build took $((SECONDS - SETUP_DONE))s of the ${SECONDS}s total"

INNER=0
[ "$HOMEPAGE" = "200" ] || { echo "homepage did not return 200" >&2; INNER=1; }
[ "${AGENTS:-0}" -gt 0 ] || { echo "no agents, the seed did not load" >&2; INNER=1; }
exit $INNER
' && CONTAINER_STATUS=0 || CONTAINER_STATUS=$?

ELAPSED=$((SECONDS - START))

echo
echo "cold start took ${ELAPSED}s (budget ${BUDGET_SECS}s)"

FAILED=0
[ "$CONTAINER_STATUS" -eq 0 ] || { echo "the stack did not come up, see above" >&2; FAILED=1; }
[ "$ELAPSED" -le "$BUDGET_SECS" ] || {
  echo "over the ${BUDGET_SECS}s budget: fix the setup, not this budget" >&2
  FAILED=1
}
exit $FAILED

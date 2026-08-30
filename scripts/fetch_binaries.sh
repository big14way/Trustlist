#!/usr/bin/env bash
# Download prebuilt service binaries for this exact commit, so a machine that
# has never seen the repo does not have to compile the workspace.
#
# Compiling is what put the cold start over its budget: the last measured run
# spent 317 of its 423 seconds in `cargo build --release`. SPEC Section 30.1
# already ships the seed the same way, and Section 30.2 sets the budget at
# five minutes.
#
# Three rules keep this honest.
#
# It only ever accepts binaries built from the commit that is checked out.
# The asset name carries the commit, so a stale binary cannot be picked up by
# accident, and anything else falls back to compiling.
#
# It verifies the checksum published beside the archive before unpacking.
#
# It runs each binary's --version before accepting it. A binary built against
# a newer glibc than the machine has fails at the dynamic loader, and the
# only way to find that out is to execute it.
#
# Failure here is never fatal: the caller compiles instead. Exit 0 means
# target/release now holds usable binaries for this commit.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${TRUSTLIST_REPO:-big14way/Trustlist}"
SERVICES=(api indexer prober trust)

note() { printf '  %s\n' "$1"; }

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) TARGET=x86_64-unknown-linux-gnu ;;
  *)
    note "no prebuilt binaries for $(uname -s)/$(uname -m), compiling instead"
    exit 1
    ;;
esac

command -v git >/dev/null 2>&1 || { note "no git, compiling instead"; exit 1; }
SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
[ -n "$SHA" ] || { note "not a git checkout, compiling instead"; exit 1; }

# Already downloaded and matching? Nothing to do.
STAMP="target/release/.trustlist-binaries"
if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$SHA" ]; then
  note "prebuilt binaries for $SHA are already here"
  exit 0
fi

ARCHIVE="trustlist-$TARGET-$SHA.tar.gz"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Assets are fetched through the releases API rather than the plain download
# URL, because the API is the one path that works whether the repository is
# public or private. A private repository answers 404 to an anonymous
# download, which looks exactly like "no binaries for this commit" and is a
# confusing way to learn about a permissions problem.
#
# GH_TOKEN is used when it is set and simply not sent when it is not. Nothing
# here requires one: a public repository serves these anonymously, which is
# the case that matters, because a stranger following the README has no
# token.
API="https://api.github.com/repos/$REPO/releases"
auth_args=()
if [ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
  auth_args=(-H "Authorization: Bearer ${GH_TOKEN:-$GITHUB_TOKEN}")
fi

note "looking for prebuilt binaries for $SHA"
if ! curl -fsSL --max-time 30 "${auth_args[@]}" \
    -H "Accept: application/vnd.github+json" \
    -o "$TMP/release.json" "$API/tags/binaries"; then
  note "no binaries release to read, compiling instead"
  exit 1
fi

# One lookup, two asset ids, so a missing checksum is caught before anything
# is downloaded.
if ! read -r ARCHIVE_ID SUM_ID < <(python3 - "$TMP/release.json" "$ARCHIVE" <<'PY'
import json, sys
assets = {a["name"]: a["id"] for a in json.load(open(sys.argv[1])).get("assets", [])}
name = sys.argv[2]
if name not in assets:
    sys.exit(1)
if f"{name}.sha256" not in assets:
    sys.exit(1)
print(assets[name], assets[f"{name}.sha256"])
PY
); then
  note "none published for this commit, compiling instead"
  exit 1
fi

fetch_asset() {
  curl -fsSL --max-time 120 "${auth_args[@]}" \
    -H "Accept: application/octet-stream" -o "$2" "$API/assets/$1"
}
if ! fetch_asset "$ARCHIVE_ID" "$TMP/$ARCHIVE"; then
  note "the archive would not download, compiling instead"
  exit 1
fi
if ! fetch_asset "$SUM_ID" "$TMP/$ARCHIVE.sha256"; then
  note "the checksum would not download, refusing the archive"
  exit 1
fi

WANT=$(awk '{print $1}' "$TMP/$ARCHIVE.sha256")
if command -v sha256sum >/dev/null 2>&1; then
  GOT=$(sha256sum "$TMP/$ARCHIVE" | awk '{print $1}')
else
  GOT=$(shasum -a 256 "$TMP/$ARCHIVE" | awk '{print $1}')
fi
if [ "$WANT" != "$GOT" ]; then
  note "checksum mismatch, refusing the download and compiling instead"
  exit 1
fi

mkdir -p "$TMP/unpacked"
tar -xzf "$TMP/$ARCHIVE" -C "$TMP/unpacked"

for svc in "${SERVICES[@]}"; do
  if [ ! -f "$TMP/unpacked/$svc" ]; then
    note "the archive is missing $svc, compiling instead"
    exit 1
  fi
  chmod +x "$TMP/unpacked/$svc"
  # The exec test. Anything other than a clean exit means this machine
  # cannot run these, whatever the checksum said.
  if ! OUT=$("$TMP/unpacked/$svc" --version 2>&1); then
    note "$svc will not run here ($OUT), compiling instead"
    exit 1
  fi
  case "$OUT" in
    *"$SHA"*) ;;
    *)
      note "$svc reports '$OUT', which is not this commit. Compiling instead"
      exit 1
      ;;
  esac
done

mkdir -p target/release
for svc in "${SERVICES[@]}"; do
  mv "$TMP/unpacked/$svc" "target/release/$svc"
done
echo "$SHA" > "$STAMP"

note "using prebuilt binaries for $SHA, skipping the workspace build"

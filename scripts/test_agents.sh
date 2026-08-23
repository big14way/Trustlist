#!/usr/bin/env bash
# Run the tests for every reference agent we ship. Each agent lives in its
# own directory with a hyphenated name, which is not importable as a Python
# package, so each suite runs from inside its own directory.
set -euo pipefail
cd "$(dirname "$0")/.."

found=0
failed=0
for dir in agents/*/; do
  if compgen -G "${dir}test_*.py" > /dev/null; then
    found=1
    echo "== ${dir%/} =="
    if ! ( cd "$dir" && python3 -m unittest discover -p "test_*.py" -v 2>&1 | tail -4 ); then
      failed=1
    fi
  fi
done

if [ "$found" -eq 0 ]; then
  echo "no agent tests found"
fi
exit "$failed"

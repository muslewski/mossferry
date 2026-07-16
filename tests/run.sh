#!/usr/bin/env bash
# Run every tests/test-*.sh; nonzero exit on any failure.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
fail=0
shopt -s nullglob
for t in tests/test-*.sh; do
  bash "$t" || fail=1
done
exit "${fail:-0}"

#!/usr/bin/env bash
# Run every test-*.sh in this directory.

set -euo pipefail

cd "$(dirname "$0")"

failed=0
for t in test-*.sh; do
  [ -e "$t" ] || continue
  printf '== %s\n' "$t"
  if ! bash "$t"; then
    failed=$((failed + 1))
  fi
done

if [ "$failed" -gt 0 ]; then
  printf '\n%d test file(s) failed\n' "$failed" >&2
  exit 1
fi
echo
echo 'all tests passed'

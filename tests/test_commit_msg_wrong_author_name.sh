#!/bin/sh
set -e

cd "$(dirname "$0")/.."

fail=0

check() {
  file="$1"
  if ! grep -q "Tommy Slater" "$file"; then
    echo "FAIL: $file does not credit Tommy Slater"
    fail=1
  fi
}

check LICENSE
check .claude-plugin/plugin.json
check .claude-plugin/marketplace.json

if [ "$fail" -eq 0 ]; then
  echo "PASS: author name Tommy Slater is credited everywhere expected"
fi

exit "$fail"

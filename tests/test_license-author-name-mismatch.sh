#!/bin/sh
set -e

cd "$(dirname "$0")/.."

license_name=$(sed -n '3p' LICENSE | sed -E 's/^Copyright \(c\) [0-9]{4} //')
plugin_name=$(grep -A1 '"author"' .claude-plugin/plugin.json | sed -n 's/.*"name": "\(.*\)".*/\1/p')
marketplace_name=$(grep -A1 '"owner"' .claude-plugin/marketplace.json | sed -n 's/.*"name": "\(.*\)".*/\1/p')

fail=0

if [ "$license_name" != "Tommy Slater" ]; then
  echo "FAIL: LICENSE copyright name is '$license_name', expected 'Tommy Slater'"
  fail=1
fi

if [ "$plugin_name" != "Tommy Slater" ]; then
  echo "FAIL: plugin.json author.name is '$plugin_name', expected 'Tommy Slater'"
  fail=1
fi

if [ "$marketplace_name" != "Tommy Slater" ]; then
  echo "FAIL: marketplace.json owner.name is '$marketplace_name', expected 'Tommy Slater'"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: author name is 'Tommy Slater' everywhere"
fi

exit "$fail"

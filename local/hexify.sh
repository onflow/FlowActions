#!/usr/bin/env bash

# usage: run  `./local/hexify.sh ./path/to/contract.cdc` from project root
#   |-> outputs the hex encoded Cadence code with imports dynamically sourced from ./flow.json

set -e

# Default network
ENV="testing"
FILE=""

# Parse flags and file argument
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--network)
      ENV="$2"
      shift 2
      ;;
    -*)
      echo "Unknown option: $1"
      exit 1
      ;;
    *)
      FILE="$1"
      shift
      ;;
  esac
done

if [ -z "$FILE" ]; then
  echo "Usage: $0 [--network <name>] <PATH_TO_FILE>"
  exit 1
fi

FLOW_JSON="./flow.json"

if [ ! -f "$FLOW_JSON" ]; then
  echo "Error: $FLOW_JSON not found"
  exit 1
fi

# Extract imported contract names from source file
IMPORTS=$(grep -oE 'import "[^"]+"' "$FILE" | sed 's/import "\(.*\)"/\1/')

# Prepare temp files
TMP_SED=$(mktemp)
TMP_MAP=$(mktemp)
TMP_MISSING=$(mktemp)

# Process each import
echo "$IMPORTS" | while read -r name; do
  # check if dependency exists
  exists=$(jq -r --arg name "$name" '.dependencies[$name] != null' "$FLOW_JSON")
  if [ "$exists" != "true" ]; then
    echo "⚠️  Missing dependency: $name" >> "$TMP_MISSING"
    continue
  fi

  # check if environment alias exists
  address=$(jq -r --arg name "$name" --arg env "$ENV" '.dependencies[$name].aliases[$env] // empty' "$FLOW_JSON")
  if [ -z "$address" ]; then
    echo "⚠️  No '$ENV' alias for dependency: $name" >> "$TMP_MISSING"
    continue
  fi

  echo "s|import \"$name\"|import $name from 0x$address|g" >> "$TMP_SED"
  echo "$name=0x$address" >> "$TMP_MAP"
done

# Apply replacements and hexify
sed -f "$TMP_SED" "$FILE" | xxd -p | tr -d '\n'
echo

# Output diagnostics
if [ -s "$TMP_MAP" ]; then
  echo -e "\n\n✅ Resolved contract addresses (network: $ENV):"
  cat "$TMP_MAP"
fi

if [ -s "$TMP_MISSING" ]; then
  echo -e "\n\n⚠️  Warnings:"
  cat "$TMP_MISSING"
fi

# Clean up
rm -f "$TMP_SED" "$TMP_MAP" "$TMP_MISSING"

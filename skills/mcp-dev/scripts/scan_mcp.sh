#!/usr/bin/env bash
set -euo pipefail

# Scan this project for MCP references.
# Pass one or more paths to scan; defaults to the repo's source dir + dev-docs.
# Adjust the default SCAN_DIRS to match your project's code root.
SCAN_DIRS=("$@")
if [ ${#SCAN_DIRS[@]} -eq 0 ]; then
  SCAN_DIRS=(. dev-docs)   # configure your source dir, e.g. src internal lib
fi

rg -n "mcp" "${SCAN_DIRS[@]}" || true

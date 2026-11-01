#!/usr/bin/env bash
if command -v node >/dev/null 2>&1; then
  node scripts/check-version.js --check-bump
else
  echo "Warning: node executable not found in PATH. Skipping local version check."
fi

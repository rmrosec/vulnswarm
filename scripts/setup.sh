#!/usr/bin/env bash
set -euo pipefail

errors=0

check() {
  if command -v "$1" &>/dev/null; then
    echo "[OK] $1 found: $(command -v "$1")"
  else
    echo "[MISSING] $1 — $2"
    errors=$((errors + 1))
  fi
}

echo "VulnSwarm environment check"
echo "==========================="
check git "install via your package manager"
check semgrep "pipx install semgrep"

if [ "$errors" -gt 0 ]; then
  echo ""
  echo "$errors missing dependency(ies). Install them and re-run."
  exit 1
else
  echo ""
  echo "All dependencies satisfied."
fi

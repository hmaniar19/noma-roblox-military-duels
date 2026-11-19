#!/usr/bin/env bash
# Freezes the brief, phase scopes, the evaluator, and the lint/type/format rules.
# Run once per phase, after the owner sets research/CURRENT_PHASE.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 research/eval/evaluate.py --selftest
phase=$(tr -d '[:space:]' < research/CURRENT_PHASE)
git add research scripts/check.sh selene.toml stylua.toml .luaurc rokit.toml
git commit -qm "Lock research for phase $phase" || true
git tag -f locked-baseline >/dev/null
git tag -f "phase-$phase-start" >/dev/null
echo "LOCKED phase $phase at $(git rev-parse --short HEAD). Loop may start."

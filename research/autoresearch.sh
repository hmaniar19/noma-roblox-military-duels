#!/usr/bin/env bash
# Frozen benchmark entrypoint. OFF-LIMITS to the research agent.
set -euo pipefail
cd "$(dirname "$0")/.."
unset GAME_SELFTEST GAME_ROOT GAME_STATE_DIR CHECK_CMD
set -a; source research/eval/judge.env; set +a
exec python3 research/eval/evaluate.py

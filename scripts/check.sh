#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TYPES=.cache/globalTypes.d.luau
if [ ! -f "$TYPES" ]; then
	mkdir -p .cache
	curl -sSfL -o "$TYPES" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi

stylua --check src
selene src
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions="$TYPES" --sourcemap=sourcemap.json --base-luaurc=.luaurc src
rojo build default.project.json -o .cache/build.rbxl
echo "CHECK OK"

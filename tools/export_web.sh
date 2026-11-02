#!/usr/bin/env bash
# Builds the voxel extension for the web and exports the game to build/web/.
#
#   tools/export_web.sh            # release export
#   tools/export_web.sh debug      # debug export (prints errors to the browser console)
#
# Override tool locations with EMSDK=... and GODOT_BIN=... if yours differ.
set -euo pipefail

MODE="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMSDK="${EMSDK:-/c/dev/Tools/emsdk}"
GODOT_BIN="${GODOT_BIN:-/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe}"

# The Godot 4.7.2 web templates report this Emscripten at startup; others can fail to load the extension.
EM_VERSION="4.0.20"

# shellcheck disable=SC1091
source "$EMSDK/emsdk_env.sh" > /dev/null 2>&1
if ! emcc --version | grep -q "$EM_VERSION"; then
	echo "Expected Emscripten $EM_VERSION. Run: $EMSDK/emsdk install $EM_VERSION && $EMSDK/emsdk activate $EM_VERSION" >&2
	exit 1
fi

cd "$ROOT/extension"
scons platform=web target="template_$MODE" threads=no

cd "$ROOT"
mkdir -p build/web
"$GODOT_BIN" --headless --path . "--export-$MODE" Web build/web/index.html
echo "Exported to build/web/. Serve it with: python tools/serve_web.py"

#!/usr/bin/env bash
# Runs the two-process co-op test (tests/net_test.gd): starts a headless host, starts a client once
# the host is ready, then checks both passed and ended with identical worlds.
#
#   tools/net_test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe}"
OUT="$(mktemp -d)"
cd "$ROOT"

"$GODOT_BIN" --headless --path . --script res://tests/net_test.gd -- --role=host > "$OUT/host.log" 2>&1 &
HOST=$!
for _ in $(seq 240); do # Up to 2 minutes: cold Godot starts are slow on Windows.
	grep -q READY "$OUT/host.log" && break
	sleep 0.5
done
"$GODOT_BIN" --headless --path . --script res://tests/net_test.gd -- --role=client > "$OUT/client.log" 2>&1
CLIENT_STATUS=$?
wait $HOST
HOST_STATUS=$?

echo "--- host";   grep -E "^(ok|FAIL|HASH|HOST|SCRIPT ERROR|ERROR)|sent world" "$OUT/host.log"
echo "--- client"; grep -E "^(ok|FAIL|HASH|CLIENT|SCRIPT ERROR|ERROR)" "$OUT/client.log"

HOST_HASH="$(grep '^HASH' "$OUT/host.log" | cut -d' ' -f2)"
CLIENT_HASH="$(grep '^HASH' "$OUT/client.log" | cut -d' ' -f2)"
if [ $HOST_STATUS -eq 0 ] && [ $CLIENT_STATUS -eq 0 ] && [ -n "$HOST_HASH" ] && [ "$HOST_HASH" = "$CLIENT_HASH" ]; then
	echo "NET TEST PASS (worlds match)"
	exit 0
fi
echo "NET TEST FAIL (host $HOST_STATUS, client $CLIENT_STATUS, hashes ${HOST_HASH:-none} / ${CLIENT_HASH:-none}); logs in $OUT"
exit 1

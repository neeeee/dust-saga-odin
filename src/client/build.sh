#!/usr/bin/env bash
# Build the Dust Saga Odin client.
#
# Requires the Odin compiler (https://odin-lang.org) on PATH and the raylib
# vendor collection. The compiler ships its own vendor/ at <odin>/vendor, which
# is found automatically; if your layout differs, set ODIN_VENDOR below.
#
# Usage:
#   ./build.sh            # debug build → ./dust_saga
#   ./build.sh release    # optimized build
#   ./build.sh run        # build + run
set -euo pipefail

cd "$(dirname "$0")"            # src/client
ODIN="${ODIN:-odin}"
MODE="${1:-debug}"

flags=()
case "$MODE" in
  release) flags+=(-o:speed);;
esac

$ODIN build . -out:dust_saga "${flags[@]}"

echo "Built ./dust_saga"

if [[ "$1" == "run" ]]; then
  exec ./dust_saga
fi

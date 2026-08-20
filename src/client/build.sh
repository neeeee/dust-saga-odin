#!/usr/bin/env bash
# Build the Dust Saga Odin client.
#
# Requires the Odin compiler (https://odin-lang.org) on PATH and the raylib
# vendor collection. The compiler ships its own vendor/ at <odin>/vendor, which
# is found automatically; if your layout differs, set ODIN_VENDOR below.
#
# NOTE: the system vendor dir (/usr/lib/odin/vendor) can end up with Git LFS
# pointer stubs instead of real binaries (observed after a distro package
# refresh). If ./.odin-root exists, it is used as ODIN_ROOT instead — it
# symlinks every system collection except raylib, whose linux/ dir holds
# restored real libraries (SHA-verified against the LFS pointers).
#
# Usage:
#   ./build.sh            # debug build → ./dust_saga
#   ./build.sh release    # optimized build
#   ./build.sh run        # build + run
set -euo pipefail

cd "$(dirname "$0")"            # src/client
ODIN="${ODIN:-odin}"
MODE="${1:-debug}"

if [[ -d .odin-root ]]; then
  export ODIN_ROOT="$(pwd)/.odin-root"
fi

flags=()
case "$MODE" in
  release) flags+=(-o:speed);;
esac

$ODIN build . -out:dust_saga "${flags[@]}"

echo "Built ./dust_saga"

if [[ "${1:-}" == "run" ]]; then
  exec ./dust_saga
fi

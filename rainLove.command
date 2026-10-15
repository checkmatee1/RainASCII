#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
if [[ ! -x "$ROOT/bin/rain-ascii" ]]; then
    "$ROOT/scripts/build.sh"
fi
exec "$ROOT/bin/rain-ascii" "$@"

#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
# Always install the verified, sanitized release archive, never a stale build.
# Recovery: ./scripts/install.sh recover /absolute/path/to/recover.json
if (( $# == 0 )); then set -- install; fi
exec python3 "$ROOT/scripts/install_safety.py" "$@"

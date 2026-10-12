#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec swift test --package-path "$ROOT" --scratch-path "$HOME/Library/Caches/KoeType/build" "$@"

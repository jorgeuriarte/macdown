#!/usr/bin/env bash
# Regenera el informe de forks (docs/FORKS.md) y el snapshot
# (claude_tools/forks_state.json) a partir de claude_tools/seeds.txt.
#
# Uso:
#   ./claude_tools/track_forks.sh            # rastrea y escribe las salidas
#   ./claude_tools/track_forks.sh --dry-run  # solo muestra un resumen
#
# Requiere la CLI `gh` autenticada (gh auth status).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: necesitas la CLI de GitHub (gh) autenticada." >&2
  exit 1
fi

exec python3 "$DIR/track_forks.py" "$@"

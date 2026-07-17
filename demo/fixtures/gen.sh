#!/usr/bin/env bash
# Materialize sandbox bits that need absolute paths into the live sandbox HOME.
# Runs inside demo_sandbox after fixtures/home overlay.
set -euo pipefail

# Remote bin path doctor checks (relative to HOME).
mkdir -p "$HOME/.local/bin" "$HOME/Repositories/atlas" "$HOME/Repositories/beacon"
# Point repo-session at the real worktree binary (REPO_ROOT resolves from script).
ROOT="${FERRY_DEMO_ROOT:-}"
if [[ -z "$ROOT" ]]; then
  # Fallback: walk up from this gen.sh (demo/fixtures/gen.sh → repo root).
  ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fi
ln -sfn "$ROOT/bin/repo-session" "$HOME/.local/bin/repo-session"
# Also install mossferry long name for completeness.
ln -sfn "$ROOT/bin/mossferry" "$HOME/.local/bin/mossferry"
ln -sfn "$ROOT/bin/mossferry" "$HOME/.local/bin/ferry"

# Seed tiny repo markers (picker new-session chain; not required for global picker).
printf '# atlas\n' >"$HOME/Repositories/atlas/README.md"
printf '# beacon\n' >"$HOME/Repositories/beacon/README.md"

# Copy VERSION into remote repo path so ssh cat VERSION can also find a real file
# if the stub ever delegates (stub prints FERRY_DEMO_VERSION; this is belt+suspenders).
mkdir -p "$HOME/Repositories/mossferry"
cp -f "$ROOT/VERSION" "$HOME/Repositories/mossferry/VERSION"

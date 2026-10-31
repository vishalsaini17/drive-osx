#!/usr/bin/env bash
#
# Installs a pre-commit hook that enforces the configuration rule in
# CLAUDE.md §35: .env and .env.example must stay in sync.
#
#   ./scripts/install-git-hooks.sh
#
# The hook only runs the check when a .env-related file is part of the commit,
# so it costs nothing on unrelated changes. Bypass with `git commit --no-verify`.
set -euo pipefail

cd "$(dirname "$0")/.."

hooks_dir="$(git rev-parse --git-path hooks)"
mkdir -p "$hooks_dir"

cat > "$hooks_dir/pre-commit" <<'HOOK'
#!/usr/bin/env bash
# Enforces CLAUDE.md §35: .env and .env.example stay in sync.
set -uo pipefail

staged=$(git diff --cached --name-only --diff-filter=ACMR)

# Also trigger on the API's configuration schema: a new key there must be
# documented in .env.example.
if ! grep -qE '(^|/)\.env(\.example)?$|configuration/env\.ts$' <<< "$staged"; then
  exit 0
fi

if [[ ! -x ./scripts/check-env.sh ]]; then
  exit 0
fi

if ! ./scripts/check-env.sh; then
  cat >&2 <<'MESSAGE'

Commit blocked: .env and .env.example are out of sync (CLAUDE.md §35).

  Fix:     ./scripts/check-env.sh --fix
  Bypass:  git commit --no-verify

Remember that .env is not committed, so anything missing from .env.example is
missing for every other checkout.
MESSAGE
  exit 1
fi
HOOK

chmod +x "$hooks_dir/pre-commit"
echo "Installed pre-commit hook at $hooks_dir/pre-commit"
echo "It runs ./scripts/check-env.sh when a commit touches .env, .env.example or the config schema."

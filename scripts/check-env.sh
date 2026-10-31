#!/usr/bin/env bash
#
# Reports drift between each .env and its .env.example.
#
# A key documented in .env.example but absent from .env is usually harmless —
# the service falls back to its built-in default — but a key present in .env and
# missing from .env.example is undocumented configuration that the next person
# will not know to set.
#
#   ./scripts/check-env.sh          report only
#   ./scripts/check-env.sh --fix    append missing keys to .env using the example's value
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

fix=false
[[ "${1:-}" == "--fix" ]] && fix=true

status=0

keys() { grep -vE '^\s*(#|$)' "$1" 2>/dev/null | cut -d= -f1 | sed 's/[[:space:]]//g' | sort -u; }

for dir in . drive-osx-api drive-osx-mail drive-osx-ui; do
  env_file="$dir/.env"
  example_file="$dir/.env.example"
  label=$([[ "$dir" == "." ]] && echo root || echo "$dir")

  [[ -f "$example_file" ]] || continue

  if [[ ! -f "$env_file" ]]; then
    if $fix; then
      cp "$example_file" "$env_file"
      echo "✓ $label: created .env from .env.example"

      # A generated secret beats a shared placeholder, and the API refuses to
      # start on anything shorter than 16 characters.
      if grep -q '^JWT_SECRET=replace-with-a-long-random-secret' "$env_file"; then
        secret=$(openssl rand -base64 48 2>/dev/null | tr -d '\n' || head -c 48 /dev/urandom | base64 | tr -d '\n')
        # Delimiter is | because base64 output contains / and +.
        sed -i "s|^JWT_SECRET=.*|JWT_SECRET=${secret}|" "$env_file"
        echo "  → generated a random JWT_SECRET"
      fi
      continue
    fi

    echo "✗ $label: .env is missing — create it with: ./scripts/check-env.sh --fix"
    status=1
    continue
  fi

  missing=$(comm -23 <(keys "$example_file") <(keys "$env_file"))
  undocumented=$(comm -13 <(keys "$example_file") <(keys "$env_file"))

  if [[ -z "$missing" && -z "$undocumented" ]]; then
    echo "✓ $label: in sync"
    continue
  fi

  status=1

  if [[ -n "$missing" ]]; then
    echo "✗ $label: in .env.example but not .env → $(echo "$missing" | tr '\n' ' ')"
    if $fix; then
      {
        echo ""
        echo "# Added by scripts/check-env.sh"
        while read -r key; do
          [[ -z "$key" ]] && continue
          grep -m1 "^${key}=" "$example_file"
        done <<< "$missing"
      } >> "$env_file"
      echo "  → appended to $env_file"
    fi
  fi

  if [[ -n "$undocumented" ]]; then
    # Never copied automatically: the value may be a secret.
    echo "✗ $label: set in .env but undocumented → $(echo "$undocumented" | tr '\n' ' ')"
    echo "  → add these keys (with placeholder values) to $example_file"
  fi
done

exit $status

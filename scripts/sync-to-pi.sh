#!/data/data/com.termux/files/usr/bin/bash
# Copy this checkout into the package copy that pi actually loads.
#
# Why this exists: pi resolves a package by NAME from
#   ~/.pi/agent/npm/node_modules/<name>/
# even when settings.json lists a local path for it. Editing the checkout alone
# therefore changes nothing at runtime — the running extension is the npm copy,
# which is a separate snapshot. After every code change here, run this script,
# then restart pi (or start a fresh session) for the new code to load.
#
# Usage:
#   scripts/sync-to-pi.sh [--dry-run] [--target DIR]
#
# Exits non-zero when the checkout is missing or the target cannot be written.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_name="pi-jev-model-router"
target="$HOME/.pi/agent/npm/node_modules/$package_name"
dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    --target) target="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ ! -d "$repo_root/extensions/$package_name" ]; then
  echo "sync-to-pi: no extensions/$package_name in $repo_root" >&2
  exit 1
fi
if [ ! -d "$target" ]; then
  echo "sync-to-pi: target missing: $target" >&2
  echo "  install the package into pi first (it must exist for pi to load it)" >&2
  exit 1
fi

# Only the runtime surface: extensions, assets, docs. Tests, tsconfig and CI
# config stay in the checkout — pi never loads them.
paths=(extensions assets README.md AGENTS.md LICENSE package.json)

changed=0
stale=0
for path in "${paths[@]}"; do
  [ -e "$repo_root/$path" ] || continue
  if [ ! -e "$target/$path" ]; then
    echo "  + $path (new)"
    changed=$((changed + 1))
  elif ! diff -r -q "$repo_root/$path" "$target/$path" >/dev/null 2>&1; then
    echo "  ~ $path"
    changed=$((changed + 1))
  fi
done

# Stray files in the extension dir that the checkout no longer has, e.g. *.bak-probe-*.
while IFS= read -r stray; do
  rel="${stray#"$target"/}"
  [ -e "$repo_root/$rel" ] && continue
  case "$rel" in
    node_modules/*) continue ;;
  esac
  echo "  - $rel (stale)"
  stale=$((stale + 1))
  if [ "$dry_run" -eq 0 ]; then rm -f "$stray"; fi
done < <(find "$target/extensions" -type f \( -name '*.bak-*' -o -name '*.orig' -o -name '*.rej' \) 2>/dev/null)

if [ "$changed" -eq 0 ] && [ "$stale" -eq 0 ]; then
  echo "sync-to-pi: already in sync ($target)"
  exit 0
fi

if [ "$dry_run" -eq 1 ]; then
  echo "sync-to-pi: dry run — $changed path(s) would be copied, $stale stale removed"
  exit 0
fi

for path in "${paths[@]}"; do
  [ -e "$repo_root/$path" ] || continue
  if [ -d "$repo_root/$path" ]; then
    mkdir -p "$target/$path"
    cp -R "$repo_root/$path/." "$target/$path/"
  else
    cp "$repo_root/$path" "$target/$path"
  fi
done

echo "sync-to-pi: copied $changed path(s) to $target"
echo "sync-to-pi: restart pi in a fresh session to load the new code"

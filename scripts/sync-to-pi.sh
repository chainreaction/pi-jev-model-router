#!/data/data/com.termux/files/usr/bin/bash
# Copy this checkout into every package copy that pi actually loads.
#
# Why this exists: pi never runs this checkout. Depending on how the package is
# declared in settings.json, it runs one of two snapshots:
#
#   git:<host>/<owner>/<repo>  ->  ~/.pi/agent/git/<host>/<owner>/<repo>/
#                                  (cloned once; a commit here stays invisible
#                                   until it is pushed and pi re-pulls)
#   npm:<name>                 ->  ~/.pi/agent/npm/node_modules/<name>/
#                                  (resolved by NAME even when the settings
#                                   entry names a local path)
#
# Editing the checkout alone changes nothing at runtime, and updating only one of
# the two is worse: it looks synced while pi keeps loading the other. This script
# updates both, then says whether the clone still differs from its committed state.
#
# Usage:
#   scripts/sync-to-pi.sh [--dry-run] [--target DIR] [--git-clone DIR]
#
# Exits non-zero when the checkout is missing or a target cannot be written.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_name="pi-jev-model-router"
target="$HOME/.pi/agent/npm/node_modules/$package_name"
git_clone="$HOME/.pi/agent/git/github.com/chainreaction/$package_name"
dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    --target) target="$2"; shift 2 ;;
    --git-clone) git_clone="$2"; shift 2 ;;
    -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ ! -d "$repo_root/extensions/$package_name" ]; then
  echo "sync-to-pi: no extensions/$package_name in $repo_root" >&2
  exit 1
fi
if [ ! -d "$target" ]; then
  echo "sync-to-pi: npm target missing: $target" >&2
  echo "  install the package into pi first (it must exist for pi to load it)" >&2
  exit 1
fi

# Only the runtime surface: extensions, assets, docs. Tests, tsconfig and CI
# config stay in the checkout — pi never loads them.
paths=(extensions assets README.md AGENTS.md LICENSE package.json)

sync_target() {
  local dest="$1"
  local changed=0 stale=0

  for path in "${paths[@]}"; do
    [ -e "$repo_root/$path" ] || continue
    if [ ! -e "$dest/$path" ]; then
      echo "  + $path (new)"
      changed=$((changed + 1))
    elif ! diff -r -q "$repo_root/$path" "$dest/$path" >/dev/null 2>&1; then
      echo "  ~ $path"
      changed=$((changed + 1))
    fi
  done

  # Stray files in the extension dir that the checkout no longer has, e.g. *.bak-probe-*.
  while IFS= read -r stray; do
    rel="${stray#"$dest"/}"
    [ -e "$repo_root/$rel" ] && continue
    case "$rel" in
      node_modules/*) continue ;;
    esac
    echo "  - $rel (stale)"
    stale=$((stale + 1))
    if [ "$dry_run" -eq 0 ]; then rm -f "$stray"; fi
  done < <(find "$dest/extensions" -type f \( -name '*.bak-*' -o -name '*.orig' -o -name '*.rej' \) 2>/dev/null)

  if [ "$changed" -eq 0 ] && [ "$stale" -eq 0 ]; then
    echo "sync-to-pi: $dest already in sync"
    return 0
  fi
  if [ "$dry_run" -eq 1 ]; then
    echo "sync-to-pi: dry run — $dest: $changed path(s) would be copied, $stale stale removed"
    return 0
  fi

  for path in "${paths[@]}"; do
    [ -e "$repo_root/$path" ] || continue
    if [ -d "$repo_root/$path" ]; then
      mkdir -p "$dest/$path"
      cp -R "$repo_root/$path/." "$dest/$path/"
    else
      cp "$repo_root/$path" "$dest/$path"
    fi
  done
  echo "sync-to-pi: copied $changed path(s) to $dest"
}

echo "sync-to-pi: npm copy"
sync_target "$target"

if [ -d "$git_clone/.git" ]; then
  echo "sync-to-pi: git clone (the copy pi loads for a git: package)"
  sync_target "$git_clone"
  if [ "$dry_run" -eq 0 ]; then
    drift=$(git -C "$git_clone" status --porcelain -- extensions assets 2>/dev/null | wc -l | tr -d ' ')
    if [ "$drift" != "0" ]; then
      echo "sync-to-pi: note — the git clone now differs from its committed state."
      echo "  pi loads the working tree, so this runs, but other machines get it"
      echo "  only after a push:"
      echo "    git -C \"$repo_root\" push   # then: pi update --extensions"
    fi
  fi
elif [ -d "$git_clone" ]; then
  echo "sync-to-pi: $git_clone exists but is not a git checkout, skipped" >&2
fi

echo "sync-to-pi: restart pi in a fresh session to load the new code"

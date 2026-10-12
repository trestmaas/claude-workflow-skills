#!/bin/bash
# arm-pr.sh <pr> [head-sha] — arm squash auto-merge, pinned to the head SHA,
# unless the PR touches a path the repo merges by hand (`merge.human_paths` in
# .claude/conventions.yaml). Exit 0 = armed; exit 3 = held for a person.
# The check lives here, not in a skill's prose, so a run that loaded its
# instructions before the policy changed still honours it (P-SIGN-102).
# Usage: REPO_DIR=<repo> arm-pr.sh <pr> [sha]   (ARM_DRY_RUN=1 checks without arming)
cd "${REPO_DIR:-.}" || exit 1
P=$1
SHA=${2:-$(gh pr view "$P" --json headRefOid --jq .headRefOid)}

# Read merge.human_paths from the default branch's conventions, not the PR's.
git fetch -q origin 2>/dev/null
conv=$(git show origin/HEAD:.claude/conventions.yaml 2>/dev/null || cat .claude/conventions.yaml 2>/dev/null)
globs=$(printf '%s\n' "$conv" | awk '
  /^merge:/ {inmerge=1; next}
  inmerge && /^[^ #]/ {inmerge=0}
  inmerge && /^  human_paths:/ {inhp=1; next}
  inhp && /^    - / {g=$0; sub(/^    - /,"",g); gsub(/"/,"",g); print g; next}
  inhp && !/^    - / {inhp=0}')

held=""
if [ -n "$globs" ]; then
  while IFS= read -r f; do
    while IFS= read -r g; do
      # bash [[ == ]] globbing: `*` also matches `/`, so `dir/**` and `**/*x*` work.
      [[ "$f" == $g ]] && { held="$held $f"; break; }
    done <<< "$globs"
  done < <(gh pr diff "$P" --name-only)
fi

if [ -n "$held" ]; then
  echo "#$P HELD for a person: touches merge.human_paths:$held"
  exit 3
fi
[ -n "$ARM_DRY_RUN" ] && { echo "#$P would arm at $SHA (dry run)"; exit 0; }
gh pr merge "$P" --auto --squash --match-head-commit "$SHA" && echo "#$P armed at $SHA"

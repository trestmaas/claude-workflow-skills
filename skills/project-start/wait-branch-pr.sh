#!/usr/bin/env bash
# wait-branch-pr.sh <branch> [max-minutes=240]
# Exits on the first of: a PR opened for <branch> (prints "PR #<n> OPENED <state>"),
# or the branch head moving (prints "HEAD MOVED <old> -> <new>"), or the time cap.
# Use after a /start child ends without a report: the child may still be
# working in a background job and open its PR later, with nobody watching.
set -u
B=${1:?branch}; MAX=${2:-240}; DIR=${REPO_DIR:-.}
h0=$(git -C "$DIR" ls-remote origin "refs/heads/$B" | cut -f1)
for _ in $(seq 1 "$MAX"); do
  pr=$(cd "$DIR" && gh pr list --head "$B" --state all --json number,state --jq '.[0] | select(.) | "\(.number) \(.state)"' 2>/dev/null)
  [ -n "$pr" ] && { echo "PR #${pr% *} OPENED ${pr#* }"; exit 0; }
  h=$(git -C "$DIR" ls-remote origin "refs/heads/$B" | cut -f1)
  [ -n "$h" ] && [ "$h" != "$h0" ] && { echo "HEAD MOVED ${h0:-none} -> $h"; exit 0; }
  sleep 60
done
echo "TIMEOUT — no PR for $B after ${MAX}m"; exit 0

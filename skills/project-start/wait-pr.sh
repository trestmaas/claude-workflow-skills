#!/bin/bash
# wait-pr.sh <pr> — until MERGED/CLOSED, or until a state a person must act on.
# - A failed check whose annotation is a runner cancel ("The operation was
#   canceled." / "A task was canceled.") is re-run once its run completes;
#   aggregator gates and non-GitHub checks (annotations 404) are skipped;
#   any other failure is reported and the script exits.
# - BEHIND main (strict branch protection, `merge.require_up_to_date`): with
#   auto-merge armed, merge main in (`gh pr update-branch`, never rebase) and
#   re-arm through arm-pr.sh on the new head. An armed auto-merge on a behind
#   branch otherwise waits forever without saying so (P-SIGN-102: two green PRs
#   idled 3.5h).
# - DIRTY (conflict with main) and HELD (merge.human_paths) are reported and
#   the script exits: both need the owning agent or a person.
# Usage: REPO_DIR=<repo> wait-pr.sh <pr>   (run_in_background; one waiter per PR, 90s poll)
cd "${REPO_DIR:-.}" || exit 1
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
P=$1; reran=""; updates=0
for i in $(seq 1 150); do
  read -r st ms armed < <(gh pr view "$P" --json state,mergeStateStatus,autoMergeRequest --jq '"\(.state) \(.mergeStateStatus) \(.autoMergeRequest != null)"' 2>/dev/null)
  case $st in MERGED|CLOSED) echo "#$P $st $(gh pr view "$P" --json mergeCommit --jq '.mergeCommit.oid // ""')"; exit 0;; esac
  [ "$ms" = "DIRTY" ] && { echo "#$P DIRTY — conflict with main; no CI will run until it is resolved"; exit 0; }
  for link in $(gh pr checks "$P" --json bucket,link --jq '.[]|select(.bucket=="fail")|.link' 2>/dev/null); do
    job=${link##*/}; run=$(echo "$link" | sed -E 's#.*/runs/([0-9]+)/.*#\1#')
    msg=$(gh api "repos/{owner}/{repo}/check-runs/$job/annotations" --jq '[.[].message]|join(" | ")' 2>&1)
    # aggregator gates mirror another job; non-GitHub checks (Vercel) 404 here
    echo "$msg" | grep -qE "${AGGREGATOR_RE:-e2e concluded|CI gate failed|\"status\":\"404\"}" && continue
    if echo "$msg" | grep -qE "operation was canceled|A task was canceled"; then
      case " $reran " in *" $job "*) continue;; esac
      [ "$(gh run view "$run" --json status --jq .status)" = completed ] || continue
      gh run rerun "$run" --failed >/dev/null 2>&1 && reran="$reran $job" && echo "#$P rerun cancelled job $job" >&2
    else
      echo "#$P CI FAIL $link :: ${msg:0:300}"; exit 0
    fi
  done
  if [ "$ms" = "BEHIND" ] && [ "$armed" = "true" ]; then
    [ $updates -ge 6 ] && { echo "#$P still BEHIND after $updates refreshes — main is moving faster than CI"; exit 0; }
    if gh pr update-branch "$P" >/dev/null 2>&1; then
      sleep 8
      out=$("$HERE/arm-pr.sh" "$P"); rc=$?
      [ $rc -eq 3 ] && { echo "$out"; exit 0; }
      updates=$((updates+1)); echo "#$P refreshed onto main and re-armed ($updates)" >&2
    fi
  fi
  sleep 90
done
echo "#$P TIMEOUT state=$st merge=$ms"

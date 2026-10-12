#!/bin/bash
# wait-pr.sh <pr> — until MERGED/CLOSED. A failed check whose annotation is
# "The operation was canceled." (runner cancel) is re-run once its run completes;
# any other failure is reported and the script exits.
# Usage: REPO_DIR=<repo> wait-pr.sh <pr>   (run_in_background; one waiter per PR, 90s poll)
cd "${REPO_DIR:-.}" || exit 1
P=$1; reran=""
for i in $(seq 1 150); do
  st=$(gh pr view $P --json state --jq .state 2>/dev/null)
  case $st in MERGED|CLOSED) echo "#$P $st $(gh pr view $P --json mergeCommit --jq '.mergeCommit.oid // ""')"; exit 0;; esac
  for link in $(gh pr checks $P --json bucket,link --jq '.[]|select(.bucket=="fail")|.link' 2>/dev/null); do
    job=${link##*/}; run=$(echo "$link" | sed -E 's#.*/runs/([0-9]+)/.*#\1#')
    msg=$(gh api repos/{owner}/{repo}/check-runs/$job/annotations --jq '[.[].message]|join(" | ")' 2>/dev/null)
    # aggregator gate that only mirrors e2e's result — the underlying job is handled on its own
    echo "$msg" | grep -qE "${AGGREGATOR_RE:-e2e concluded|CI gate failed}" && continue
    if echo "$msg" | grep -q "operation was canceled"; then
      case " $reran " in *" $job "*) continue;; esac
      [ "$(gh run view $run --json status --jq .status)" = completed ] || continue
      gh run rerun $run --failed >/dev/null 2>&1 && reran="$reran $job" && echo "#$P rerun cancelled job $job" >&2
    else
      echo "#$P CI FAIL $link :: ${msg:0:300}"; exit 0
    fi
  done
  sleep 90
done
echo "#$P TIMEOUT state=$st"

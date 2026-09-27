#!/usr/bin/env bash
# Waits for a GitHub Actions run (public repo, no auth) and prints job results.
# Usage: Tools/wait_ci.sh <run_id> [max_minutes]
RUN="$1"; MAX="${2:-60}"; REPO="gokhanbudak59/Asist"
for i in $(seq 1 $((MAX*60/75+1))); do
  S=$(curl -s "https://api.github.com/repos/$REPO/actions/runs/$RUN" | python -c "import json,sys;d=json.load(sys.stdin);print(d.get('status'),d.get('conclusion'))")
  case "$S" in completed*) break;; esac
  sleep 75
done
echo "RUN $RUN: $S"
curl -s "https://api.github.com/repos/$REPO/actions/runs/$RUN/jobs" | python -c "
import json,sys
for j in json.load(sys.stdin).get('jobs',[]):
    print(j['name'],'|',j['status'],'|',j['conclusion'],'| id',j['id'])
    for st in j.get('steps',[]):
        if st.get('conclusion') not in ('success','skipped',None): print('   step:',st['name'],st['conclusion'])
"

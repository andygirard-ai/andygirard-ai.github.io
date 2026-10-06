#!/bin/zsh
# Runs every scenario against fake Tesla/PushWard + a fast-forward clock.
# Needs python3. Scenarios print logs; look for errors, not exit codes.
cd "${0:A:h}"
for t in t1_arrival t2_snooze_skip t5_edges t7_times t9_look t11_low_battery; do
  out=$(zsh $t.sh 2>&1)
  print -- "== $t: $(print -r -- "$out" | grep -cE 'reminder (started|ended)') reminder events, $(print -r -- "$out" | grep -ciE 'bad math|parse error|command not found|Traceback') errors"
done

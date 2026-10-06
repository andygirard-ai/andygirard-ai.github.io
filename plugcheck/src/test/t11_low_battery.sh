source "${${(%):-%x}:A:h}/lib.sh"
print 'BEDTIME=2130' >> $PLUGCHECK_DIR/config
touch $FAKE/present; print online > $FAKE/car_state; print Disconnected > $FAKE/cs
notifs() { grep 'POST https://api.pushward.app/notifications' $FAKE/requests.log | sed 's/.*"title":"\([^"]*\)","body":"\([^"]*\)","level":"\([^"]*\)".*/[\3] \1 — \2/'; }
print -- "=== A: 34% (below 50%), ignored from 9:29 PM through the night"
print 34 > $FAKE/bat
setnow "2026-10-06 21:29"; run 6
print -- "--- evening (9:30–9:31):"; notifs | sort | uniq -c
: > $FAKE/requests.log
setnow "2026-10-06 22:40"; print asleep > $FAKE/car_state; run 40
print -- "--- overnight 10:40–~10:53 PM (should be critical every 10 min):"; notifs | sort | uniq -c
: > $FAKE/requests.log
print -- "=== B: same night but 72% (enough for the commute)"
rm -f $PLUGCHECK_DIR/state; print 72 > $FAKE/bat; print online > $FAKE/car_state
setnow "2026-10-07 21:29"; run 6
setnow "2026-10-07 22:40"; print asleep > $FAKE/car_state; run 40
notifs | sort | uniq -c
print -- "=== C: low-battery arrival at 1 AM"
: > $FAKE/requests.log; rm -f $PLUGCHECK_DIR/state; print 30 > $FAKE/bat; print online > $FAKE/car_state
setnow "2026-10-08 01:00"; print arrive > $PLUGCHECK_DIR/cmd; run 2
notifs | sort | uniq -c
grep -o '"subtitle":"[^"]*"' $FAKE/requests.log | sort -u

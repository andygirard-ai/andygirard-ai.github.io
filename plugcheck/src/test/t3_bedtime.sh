source "${${(%):-%x}:A:h}/lib.sh"
touch $FAKE/present
print -- "=== A: bedtime, asleep car, plugged in"
setnow "2026-10-06 21:59"; print asleep > $FAKE/car_state; print Stopped > $FAKE/cs
run 2
print -- "=== B: next night, asleep car, NOT plugged in → critical + reminder; ignore 40 min"
setnow "2026-10-07 21:59"; print asleep > $FAKE/car_state; print Disconnected > $FAKE/cs
run 2; run 120
print -- "=== C: quiet hours reached? clock $(clock)"
setnow "2026-10-08 00:10"; run 3
showlog | grep -v started
print -- "--- notifications:"; pwreq | grep 'POST /notifications' | sed 's/.*"title":"\([^"]*\)","body":"\([^"]*\)","level":"\([^"]*\)".*/[\3] \1 — \2/' | uniq -c
print -- "--- wakes: $(grep -c wake_up $FAKE/requests.log)  vehicle_data calls: $(grep -c vehicle_data $FAKE/requests.log)"

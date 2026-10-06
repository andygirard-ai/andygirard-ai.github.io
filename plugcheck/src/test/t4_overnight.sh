source "${${(%):-%x}:A:h}/lib.sh"
touch $FAKE/present
setnow "2026-10-07 21:59"; print asleep > $FAKE/car_state; print Disconnected > $FAKE/cs
run 2; run 90                         # 30 min of fast nudges
print asleep > $FAKE/car_state
setnow "2026-10-07 23:58"; run 12     # into quiet hours (car asleep)
setnow "2026-10-08 04:58"; run 12     # 5:00 renewal
setnow "2026-10-08 05:58"; run 12     # quiet ends at 6:00
print online > $FAKE/car_state; print Charging > $FAKE/cs
setnow "2026-10-08 06:20"; run 20
showlog | grep -v "started\|car: Disconnected"
print -- "--- notifications:"; pwreq | grep 'POST /notifications' | sed 's/.*"title":"\([^"]*\)","body":"\([^"]*\)","level":"\([^"]*\)".*/[\3] \1/' | uniq -c
print -- "--- wakes: $(grep -c wake_up $FAKE/requests.log)  vehicle_data calls: $(grep -c vehicle_data $FAKE/requests.log)"
print -- "--- Live Activity PATCHes: $(pwreq | grep -c 'PATCH /activities')  sounds: $(pwreq | grep -c '"sound"')"

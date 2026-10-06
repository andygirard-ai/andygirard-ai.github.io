source "${${(%):-%x}:A:h}/lib.sh"
setnow "2026-10-06 17:00"
print online > $FAKE/car_state; print Disconnected > $FAKE/cs
run 17                 # car away 17 min
touch $FAKE/present
run 12                 # arrives, 10-min grace, reminder starts
print "--- after arrival + grace: $(clock)"
run 8                  # a few nudges (20s ticks)
print Charging > $FAKE/cs
run 8                  # plugged in → ends
print "--- end: $(clock)"
showlog
print "--- PushWard calls:"; pwreq | cut -c1-230

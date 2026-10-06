source "${${(%):-%x}:A:h}/lib.sh"
setnow "2026-10-06 18:00"
print online > $FAKE/car_state; print Disconnected > $FAKE/cs; touch $FAKE/present
print arrive > $PLUGCHECK_DIR/cmd
run 2
print -- "--- reminder running at $(clock); tap Snooze on Live Activity"
print snooze > $FAKE/answer_activity
run 2
rm $FAKE/answer_activity
print -- "--- waiting out snooze"
run 17
print -- "--- reminder back at $(clock); tap Not today on the notification"
print skip > $FAKE/answer_notif
run 2
rm $FAKE/answer_notif
print -- "--- arrival later today should be skipped; bedtime skipped"
print arrive > $PLUGCHECK_DIR/cmd; run 2
setnow "2026-10-06 22:00"; run 1
setnow "2026-10-07 06:30"; print arrive > $PLUGCHECK_DIR/cmd; run 2
showlog
print -- "--- notifications sent:"; pwreq | grep 'POST /notifications' | sed 's/.*"title":"\([^"]*\)","body":"\([^"]*\)","level":"\([^"]*\)".*/[\3] \1 — \2/'

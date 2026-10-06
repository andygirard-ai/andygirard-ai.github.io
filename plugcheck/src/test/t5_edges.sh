source "${${(%):-%x}:A:h}/lib.sh"
touch $FAKE/present; print online > $FAKE/car_state
print -- "=== demo (tap Snooze on Live Activity)"
setnow "2026-10-06 12:00"; print demo > $PLUGCHECK_DIR/cmd; run 2
print snooze > $FAKE/answer_activity; run 1; rm $FAKE/answer_activity
print -- "=== check command"
print Complete > $FAKE/cs; print check > $PLUGCHECK_DIR/cmd; run 1
print -- "=== NoPower after arrival"
print NoPower > $FAKE/cs; print arrive > $PLUGCHECK_DIR/cmd; run 1
print -- "=== car leaves mid-reminder"
print Disconnected > $FAKE/cs; setnow "2026-10-06 13:00"; print arrive > $PLUGCHECK_DIR/cmd; run 2
rm $FAKE/present; run 50
print -- "=== bedtime while car away"
setnow "2026-10-06 22:00"; run 1
print -- "=== PushWard down + Tesla sign-in broken next bedtime"
touch $FAKE/present; print 1 > $FAKE/pw_down
python3 - <<'P'
import os,re; p=os.environ['FAKE']+'/../'; 
P
sed -i 's/oauth2\/v3\/token/oauth2\/v3\/BROKEN/' $PLUGCHECK_DIR/config
setnow "2026-10-07 22:00"; run 1
showlog | grep -v "PlugCheck started"
print -- "--- notifications:"; pwreq | grep 'POST /notifications' | sed 's/.*"title":"\([^"]*\)","body":"\([^"]*\)","level":"\([^"]*\)".*/[\3] \1 — \2/'
print -- "--- Reminders fallback calls: $(grep -c . $FAKE/reminders.log 2>/dev/null)"

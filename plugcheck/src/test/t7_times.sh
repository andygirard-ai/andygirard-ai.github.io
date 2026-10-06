source "${${(%):-%x}:A:h}/lib.sh"
print 'BEDTIME=2130' >> $PLUGCHECK_DIR/config   # what setup will write
touch $FAKE/present; print online > $FAKE/car_state; print Disconnected > $FAKE/cs
setnow "2026-10-06 21:29"; run 3                    # 9:30 bedtime → critical + reminder
setnow "2026-10-06 22:25"; run 20                   # nudges stop at 10:30
n1=$(grep -c 'POST https://api.pushward.app/notifications' $FAKE/requests.log)
setnow "2026-10-07 02:00"; run 5                    # silent
n2=$(grep -c 'POST https://api.pushward.app/notifications' $FAKE/requests.log)
setnow "2026-10-07 04:29"; run 6                    # 4:30 morning nudge
n3=$(grep -c 'POST https://api.pushward.app/notifications' $FAKE/requests.log)
showlog | grep -E "bedtime|reminder"
print -- "notifications: by 10:31 PM=$n1, at 2 AM added=$((n2-n1)), at 4:30 AM added=$((n3-n2))"
pwreq | grep 'POST /notifications' | sed 's/.*"title":"\([^"]*\)".*"level":"\([^"]*\)".*/[\2] \1/' | uniq -c

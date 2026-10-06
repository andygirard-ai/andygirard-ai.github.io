source "${${(%):-%x}:A:h}/lib.sh"
touch $FAKE/present; print online > $FAKE/car_state; print Disconnected > $FAKE/cs
setnow "2026-10-06 18:00"; print arrive > $PLUGCHECK_DIR/cmd; run 2
print snooze_long > $FAKE/answer_notif; run 1; rm $FAKE/answer_notif
setnow "2026-10-06 19:01"; run 2
print Charging > $FAKE/cs; run 8
showlog | grep -E "reminder|snoozed"
python3 - "$FAKE/requests.log" <<'P'
import sys, json
bad=0; n=0
for line in open(sys.argv[1]):
    if 'pushward' not in line: continue
    parts=line.rstrip('\n').split(' ',2)
    body=parts[2] if len(parts)>2 else ''
    if not body.strip().startswith('{'): continue
    n+=1
    try: j=json.loads(body)
    except Exception as e: bad+=1; print('BAD JSON:', body[:150]); continue
    c=j.get('content',{})
    if c.get('options'): print('activity:', c.get('compact_label'), c.get('icon'), c.get('accent_color'), j.get('sound'), [o['title'] for o in c['options']])
    if j.get('actions'): print('notif:', j['title'], '| icon_url' if j.get('icon_url') else '', [a['title'] for a in j['actions']])
print(f'{n} JSON bodies, {bad} invalid')
P

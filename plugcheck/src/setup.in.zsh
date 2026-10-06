#!/bin/zsh
# ─────────────────────────────────────────────────────────────
#  PlugCheck setup  (v2 — Live Activities via PushWard)
#
#  Run once in Terminal:   zsh ~/Downloads/plugcheck-setup.sh
#  Safe to run again any time — it keeps your saved settings.
# ─────────────────────────────────────────────────────────────
set -u

APP_DIR="$HOME/PlugCheck"
LABEL="com.andy.plugcheck"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
KC="PlugCheck"
AUTH="https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token"
API="https://fleet-api.prd.na.vn.cloud.tesla.com"
PWAPI="https://api.pushward.app"

step() { print -r -- $'\n\e[1;36m▶ '"$1"$'\e[0m'; }
ok()   { print -r -- $'\e[32m✓ '"$1"$'\e[0m'; }
warn() { print -r -- $'\e[33m! '"$1"$'\e[0m'; }
fail() { print -r -- $'\n\e[1;31m✗ '"$1"$'\e[0m\n'; exit 1; }
json() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }
lines() { if [[ -f $1 ]]; then wc -l < "$1" | tr -d ' '; else print 0; fi; }

[[ $(uname) == Darwin ]] || fail "Run this on the Mac mini."
mkdir -p "$APP_DIR" "$HOME/Library/LaunchAgents"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Saved settings from an earlier run (if any)
CLIENT_ID="4dbae2ab-120c-47cf-8a36-45423999ccc4" VIN="" CAR="" CAR_IP="192.168.1.27" DOMAIN="andygirard-ai.github.io"
GRACE_MIN=10 SNOOZE_MIN=15 SNOOZE_LONG_MIN=60 BEDTIME=2130 QUIET_START=2230 QUIET_END=430
LOOK_ICON=mdi:ev-plug-tesla LOOK_ACCENT='#E31937' LOOK_BG='#000000' LOOK_TEXT='#FFFFFF' LOOK_SOUND=chime LOOK_BATTERY_IN_ISLAND=1
[[ -f $APP_DIR/config ]] && source "$APP_DIR/config"
[[ $BEDTIME == 2200 ]] && BEDTIME=2130   # new default: 9:30 PM
[[ $LOOK_ICON == bolt.car.fill && $LOOK_ACCENT == orange ]] && { LOOK_ICON=mdi:ev-plug-tesla LOOK_ACCENT='#E31937' LOOK_BG='#000000' LOOK_TEXT='#FFFFFF'; }   # move to the Tesla look
HAVE_TESLA=0; security find-generic-password -s "$KC" -a refresh_token >/dev/null 2>&1 && HAVE_TESLA=1
HAVE_PW=0;    security find-generic-password -s "$KC" -a pushward >/dev/null 2>&1 && HAVE_PW=1

# Pause the running service (if any) while we set up
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null

# ── 1. PushWard ──────────────────────────────────────────────
step "PushWard"
if (( HAVE_PW )); then
  read -s "PW_KEY?PushWard key (starts with hlk_ — press Return to keep the saved one): "; print
  [[ -z $PW_KEY ]] && PW_KEY=$(security find-generic-password -s "$KC" -a pushward -w)
else
  read -s "PW_KEY?PushWard key (starts with hlk_, stays hidden when you paste): "; print
fi
PW_KEY=${PW_KEY//[[:space:]]/}
[[ $PW_KEY == hlk_* ]] || fail "That doesn't look like a PushWard key — it should start with hlk_"
code=$(curl -sS --max-time 20 "$PWAPI/auth/me" -H "Authorization: Bearer $PW_KEY" -o "$TMP/me.json" -w '%{http_code}' 2>/dev/null)
[[ $code == 200 ]] || fail "PushWard didn't accept that key (error $code). Copy it again from the PushWard app."
security add-generic-password -U -s "$KC" -a pushward -w "$PW_KEY" || fail "Couldn't save the key to your Keychain."
ok "PushWard connected (key saved in your Keychain)"

# ── 2. The car on your Wi-Fi ─────────────────────────────────
step "Arrival detection"
print "Enter the Tesla's fixed IP address from the UniFi app."
print "(Press Return with nothing typed to skip — you'd still get the bedtime check.)"
read "IN?Tesla IP address${CAR_IP:+ [$CAR_IP]}: "
CAR_IP=${IN:-$CAR_IP}; CAR_IP=${CAR_IP//[[:space:]]/}
if [[ -n $CAR_IP ]]; then
  [[ $CAR_IP =~ '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail "\"$CAR_IP\" isn't an IP address (it should look like 192.168.1.50)."
  if ping -c 1 -t 2 "$CAR_IP" >/dev/null 2>&1 || arp -n "$CAR_IP" 2>/dev/null | grep -qE ' at [0-9a-fA-F]{1,2}:'; then
    ok "I can see the car on your Wi-Fi"
  else
    warn "I can't see the car at $CAR_IP right now. That's fine if it's away or asleep — otherwise double-check the address."
  fi
else
  warn "Skipping arrival detection — bedtime check only"
fi

# ── 3. Tesla ─────────────────────────────────────────────────
step "Tesla"
TESLA_OK=0
if (( HAVE_TESLA )) && [[ -n $CLIENT_ID && -n $VIN ]]; then
  read "REDO?Already signed in to Tesla. Press Return to keep it, or type r to sign in again: "
  [[ $REDO == [rR]* ]] || TESLA_OK=1
fi

if (( ! TESLA_OK )); then
  # Already known — only ask if somehow missing
  DOMAIN=${DOMAIN:-andygirard-ai.github.io}
  DOMAIN=${DOMAIN#https://}; DOMAIN=${DOMAIN#http://}; DOMAIN=${DOMAIN%/}
  if [[ -z $CLIENT_ID ]]; then
    read "CLIENT_ID?Tesla Client ID: "; CLIENT_ID=${CLIENT_ID//[[:space:]]/}
  fi
  REDIRECT="https://$DOMAIN/plugcheck/"

  KEY_URL="https://$DOMAIN/.well-known/appspecific/com.tesla.3p.public-key.pem"
  curl -fsS --max-time 20 "$KEY_URL" 2>/dev/null | grep -q "BEGIN PUBLIC KEY" \
    || fail "Couldn't find your public key at
  $KEY_URL
  Wait a minute, then run setup again."
  ok "Public key is online"

  print ""
  print "Now the Tesla Client Secret:"
  print "  1. In the Claude app's browser (developer.tesla.com → PlugCheck → Credentials & APIs)"
  print "  2. Click the eye icon next to Client Secret so the real text shows (not dots)"
  print "  3. Copy it, come back here, paste with ⌘V, press Return"
  print "  (Nothing appears while you paste — that's normal.)"
  PARTNER=""
  for TRY in 1 2 3 4 5; do
    read -s "CLIENT_SECRET?Client Secret: "; print
    CLIENT_SECRET=${CLIENT_SECRET//[[:space:]]/}
    if [[ -z $CLIENT_SECRET ]]; then warn "Nothing was pasted — try again."; continue; fi
    if [[ $CLIENT_SECRET == hlk_* ]]; then warn "That's your PushWard key, not the Tesla secret — try again."; continue; fi
    if [[ $CLIENT_SECRET == $CLIENT_ID ]]; then warn "That's the Client ID, not the secret — click the eye next to Client Secret and copy that."; continue; fi
    if [[ $CLIENT_SECRET == *•* || $CLIENT_SECRET == *\** ]]; then warn "That's the hidden dots — click the eye icon first so the real secret shows, then copy."; continue; fi
    print "  Got ${#CLIENT_SECRET} characters, starting \"${CLIENT_SECRET[1,4]}…\" — checking with Tesla…"
    curl -sS --max-time 30 -X POST "$AUTH" \
      --data-urlencode grant_type=client_credentials \
      --data-urlencode client_id="$CLIENT_ID" \
      --data-urlencode client_secret="$CLIENT_SECRET" \
      --data-urlencode scope="openid vehicle_device_data" \
      --data-urlencode audience="$API" -o "$TMP/partner.json"
    if PARTNER=$(json "$TMP/partner.json" access_token); then ok "Tesla accepted the secret"; break; fi
    PARTNER=""
    if grep -q unauthorized_client "$TMP/partner.json"; then
      warn "Tesla says that isn't the right secret. Make sure the eye is clicked and you copy the whole thing — try again."
    else
      warn "Tesla answered: $(head -c 200 "$TMP/partner.json") — try again."
    fi
  done
  [[ -n $PARTNER ]] || fail "Still not accepted after 5 tries. Send Claude the lines above."
  curl -sS --max-time 30 -X POST "$API/api/1/partner_accounts" \
    -H "Authorization: Bearer $PARTNER" -H "Content-Type: application/json" \
    -d "{\"domain\":\"$DOMAIN\"}" -o "$TMP/reg.json"
  if plutil -extract response json -o - "$TMP/reg.json" >/dev/null 2>&1 || grep -qi "already" "$TMP/reg.json"; then
    ok "Registered $DOMAIN with Tesla"
  else
    fail "Tesla registration failed:
  $(cat "$TMP/reg.json")"
  fi

  STATE=$(openssl rand -hex 8)
  ENC_REDIRECT=$(print -rn -- "$REDIRECT" | sed 's/:/%3A/g; s#/#%2F#g')
  URL="https://auth.tesla.com/oauth2/v3/authorize?response_type=code&client_id=$CLIENT_ID&redirect_uri=$ENC_REDIRECT&scope=openid%20offline_access%20vehicle_device_data&state=$STATE"
  print "\nYour browser is opening. Sign in to Tesla and tap Allow."
  print "You'll land on a PlugCheck page — click Copy, then paste it below."
  open "$URL"
  read "BACK?Paste the address here: "
  CODE=$(print -r -- "$BACK" | sed -n 's/.*[?&]code=\([^&#]*\).*/\1/p')
  [[ -n $CODE ]] || fail "That address doesn't contain a sign-in code. Run setup again."
  print -r -- "$BACK" | grep -q "state=$STATE" || fail "That address is from a different sign-in. Run setup again."

  curl -sS --max-time 30 -X POST "$AUTH" \
    --data-urlencode grant_type=authorization_code \
    --data-urlencode client_id="$CLIENT_ID" \
    --data-urlencode client_secret="$CLIENT_SECRET" \
    --data-urlencode code="$CODE" \
    --data-urlencode redirect_uri="$REDIRECT" \
    --data-urlencode audience="$API" -o "$TMP/tok.json"
  ACCESS=$(json "$TMP/tok.json" access_token) || fail "Sign-in didn't finish:
  $(cat "$TMP/tok.json")"
  REFRESH=$(json "$TMP/tok.json" refresh_token) || fail "Tesla didn't return a long-term sign-in token."
  security add-generic-password -U -s "$KC" -a refresh_token -w "$REFRESH" \
    || fail "Couldn't save the sign-in to your Keychain."
  ok "Signed in to Tesla (saved in your Keychain)"

  curl -sS --max-time 30 "$API/api/1/vehicles" -H "Authorization: Bearer $ACCESS" -o "$TMP/veh.json"
  VIN=$(json "$TMP/veh.json" response.0.vin) || fail "No cars found on this Tesla account:
  $(cat "$TMP/veh.json")"
  CAR=$(json "$TMP/veh.json" response.0.display_name) || CAR=""
  [[ -z $CAR ]] && CAR="Tesla"
  ok "Found your car: $CAR"
else
  ok "Keeping your Tesla sign-in ($CAR)"
fi

# ── 4. Save settings ─────────────────────────────────────────
cat > "$APP_DIR/config" <<EOF
# PlugCheck settings. After editing, run:  ~/PlugCheck/plugcheck restart
CLIENT_ID=${(qq)CLIENT_ID}
VIN=${(qq)VIN}
CAR=${(qq)CAR}
DOMAIN=${(qq)DOMAIN}
AUTH=${(qq)AUTH}
API=${(qq)API}
CAR_IP=${(qq)CAR_IP}   # Tesla's fixed IP on home Wi-Fi ('' = no arrival detection)
GRACE_MIN=$GRACE_MIN        # minutes after getting home before the first reminder
SNOOZE_MIN=$SNOOZE_MIN       # length of a snooze
BEDTIME=$BEDTIME       # nightly check, 24-hour HHMM (2130 = 9:30 PM)
QUIET_START=$QUIET_START  # no nudges from 10:30 PM…
QUIET_END=$QUIET_END      # …until 4:30 AM
SNOOZE_LONG_MIN=$SNOOZE_LONG_MIN   # longer snooze button (minutes)

# Look — preview changes with:  ~/PlugCheck/plugcheck restart  then  ~/PlugCheck/plugcheck test
LOOK_ICON=${(qq)LOOK_ICON}       # SF Symbol (bolt.car.fill, car.side.fill…) or Material icon (mdi:ev-plug-tesla, mdi:car-electric…)
LOOK_ACCENT=${(qq)LOOK_ACCENT}          # buttons and icon: named color (orange, red…) or hex ('#E31937' = Tesla red)
LOOK_BG=${(qq)LOOK_BG}              # card background ('' = PushWard default)
LOOK_TEXT=${(qq)LOOK_TEXT}            # text color ('' = PushWard default)
LOOK_SOUND=${(qq)LOOK_SOUND}            # default chime alert success warning bell ding buzz notification
LOOK_BATTERY_IN_ISLAND=$LOOK_BATTERY_IN_ISLAND      # 1 = battery % in the Dynamic Island, 0 = icon
EOF

# ── 5. Install the service ───────────────────────────────────
step "Installing PlugCheck"
cat > "$APP_DIR/plugcheckd.zsh" <<'DAEMON'
@@DAEMON@@
DAEMON
chmod +x "$APP_DIR/plugcheckd.zsh"

cat > "$APP_DIR/plugcheck" <<'CTL'
@@CTL@@
CTL
chmod +x "$APP_DIR/plugcheck"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>$APP_DIR/plugcheckd.zsh</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>StandardErrorPath</key><string>$APP_DIR/errors.log</string>
</dict>
</plist>
EOF
rm -f "$APP_DIR/cmd" "$APP_DIR/.reminders-ok"
BEFORE=$(lines "$APP_DIR/plugcheck.log")
launchctl bootstrap "gui/$(id -u)" "$PLIST" || fail "Couldn't start the PlugCheck service."
ok "PlugCheck is running in the background (starts automatically with the Mac)"
print "If a box asks to let \"zsh\" control \"Reminders\", click OK — that's the backup alert channel."

# The Mac must stay awake for this to work
SLEEP_MIN=$(pmset -g 2>/dev/null | awk '$1=="sleep"{print $2; exit}')
if [[ -n $SLEEP_MIN && $SLEEP_MIN != 0 ]]; then
  warn "This Mac is set to sleep after $SLEEP_MIN min — PlugCheck can't run while it sleeps."
  print "   Fix: System Settings → Energy → turn on \"Prevent automatic sleeping when the display is off\"."
fi

# helper: wait for a log line matching a pattern
wait_for() {   # wait_for PATTERN SECONDS
  local i n
  for (( i = 0; i < $2; i += 2 )); do
    sleep 2
    n=$(lines "$APP_DIR/plugcheck.log")
    if (( n > BEFORE )) && tail -n $(( n - BEFORE )) "$APP_DIR/plugcheck.log" | grep -qE "$1"; then
      RESULT=$(tail -n $(( n - BEFORE )) "$APP_DIR/plugcheck.log" | grep -E "$1" | tail -1)
      BEFORE=$n; return 0
    fi
  done
  return 1
}

# ── 6. Live check of the car ─────────────────────────────────
step "Checking the car (may wake it — up to a minute)"
sleep 3
print check > "$APP_DIR/cmd"
if wait_for "CHECK (OK|FAILED)" 120; then
  if [[ $RESULT == *"CHECK OK"* ]]; then ok "${RESULT#* CHECK OK: }"; else fail "Car check failed: ${RESULT#* CHECK FAILED: }"; fi
else
  fail "No answer from the service. Run: ~/PlugCheck/plugcheck status — and send Claude what it says."
fi

# ── 7. Try the buttons ───────────────────────────────────────
step "Button test"
print "A \"PlugCheck test\" Live Activity is about to appear on your iPhone."
print "Tap Snooze or Not today on it (Lock Screen or long-press the Dynamic Island)."
print demo > "$APP_DIR/cmd"
if wait_for "DEMO (ANSWERED|TIMED OUT)" 330; then
  if [[ $RESULT == *ANSWERED* ]]; then
    ok "Got your tap (${RESULT##*: }) — buttons work"
  else
    warn "No tap came through. Try again any time with:  ~/PlugCheck/plugcheck test"
  fi
else
  warn "Didn't hear back. Try again any time with:  ~/PlugCheck/plugcheck test"
fi

print -r -- $'\n\e[1;32mAll set.\e[0m'
print "• When the car gets home and isn't plugged in after $GRACE_MIN min, you'll get the Live Activity + nudges."
print "• Every night at $(date -j -f %H%M "$BEDTIME" '+%-I:%M %p'): a silent \"Plugged in ✓\", or a loud alert if it isn't."
print "• Check on it any time:  ~/PlugCheck/plugcheck status"

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
GRACE_MIN=10 SNOOZE_MIN=15 SNOOZE_LONG_MIN=60 NEED_PCT=50 BEDTIME=2130 QUIET_START=2230 QUIET_END=430
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
NEED_PCT=$NEED_PCT          # below this % the car can't do tomorrow's commute: alerts turn critical and wake you overnight

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
#!/bin/zsh
# ─────────────────────────────────────────────────────────────
#  PlugCheck — background service (runs all the time on the Mac mini)
#
#  • Notices the Tesla arriving on home Wi-Fi, waits a grace period,
#    and if it isn't plugged in starts a Live Activity (Dynamic Island +
#    Lock Screen) with Snooze / Not today buttons, plus repeating nudges.
#  • Everything stops by itself the moment the car is plugged in.
#  • Bedtime check every night: critical alert if unplugged,
#    a silent "Plugged in ✓" if it is (proof the system is alive).
#
#  Settings live in ~/PlugCheck/config. Logs: ~/PlugCheck/plugcheck.log
# ─────────────────────────────────────────────────────────────
set -u
setopt NO_NOMATCH

DIR="${PLUGCHECK_DIR:-$HOME/PlugCheck}"
source "$DIR/config"
LOG="$DIR/plugcheck.log"
STATE="$DIR/state"
KC="PlugCheck"
PWAPI="${PWAPI:-https://api.pushward.app}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Defaults (any of these can be overridden in config)
: ${CAR_IP:=} ${CAR:=Tesla}
: ${GRACE_MIN:=10}      # minutes after arriving before the first reminder
: ${SNOOZE_MIN:=15}     # short snooze (minutes)
: ${SNOOZE_LONG_MIN:=60} # long snooze (minutes)
# Look (all editable in config)
: ${LOOK_ICON:=mdi:ev-plug-tesla}      # SF Symbol, or mdi:… Material icon
: ${LOOK_ACCENT:=#E31937}              # accent color: named (orange, red…) or hex
: ${LOOK_BG:=#000000}                  # card background ('' = PushWard default)
: ${LOOK_TEXT:=#FFFFFF}                # text color ('' = PushWard default)
: ${LOOK_SOUND:=chime}                 # default chime alert success warning bell ding buzz notification
: ${LOOK_BATTERY_IN_ISLAND:=1}         # 1 = show battery % in the Dynamic Island
: ${LOOK_NOTIF_ICON:=https://andygirard-ai.github.io/plugcheck/icon.png}
: ${NUDGE_SEC:=120}     # nudge interval at first…
: ${NUDGE_FAST:=15}     # …for this many nudges,
: ${NUDGE_SLOW_SEC:=600} # …then this interval
: ${NEED_PCT:=50}       # below this, the car can't do tomorrow's commute → alerts escalate and can wake you
: ${URGENT_NIGHT_SEC:=600} # overnight critical alert interval when below NEED_PCT
: ${POLL_SEC:=120}      # how often to re-check the car while reminding
: ${BEDTIME:=2130}      # bedtime check, 24h HHMM (9:30 PM)
: ${AWAY_MIN:=15}       # off Wi-Fi this long = the car has left
: ${QUIET_START:=2230}  # no nudges / new arrival reminders from 10:30 PM…
: ${QUIET_END:=430}     # …until 4:30 AM
: ${MAX_WAKES:=8}       # Tesla wake-ups per day (2¢ each)

# ── small helpers ────────────────────────────────────────────
now()   { date +%s; }
today() { date +%F; }
hm()    { date +%H%M; }
clock() { date -r "$1" '+%l:%M %p' | sed 's/^ *//'; }
json()  { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }
jesc()  { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; print -rn -- "$s"; }
log() {
  if [[ -f $LOG ]] && (( $(stat -f%z "$LOG") > 1000000 )); then mv -f "$LOG" "$LOG.old"; fi
  print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
}
low_batt() { [[ $BAT == <-> ]] && (( BAT < NEED_PCT )); }
evening() { local x=$(( 10#$(hm) )); (( x >= BEDTIME )) && ! quiet; }   # bedtime → start of quiet hours
quiet() {   # handles windows that cross midnight (e.g. 2230 → 430)
  local x=$(( 10#$(hm) ))
  if (( QUIET_START <= QUIET_END )); then (( x >= QUIET_START && x < QUIET_END ))
  else (( x >= QUIET_START || x < QUIET_END )); fi
}
next_morning() {   # 4:00 AM today if it's still before 4, else tomorrow
  local six=$(date -j -v4H -v0M -v0S +%s)
  (( $(now) < six )) && print $six || date -j -v+1d -v6H -v0M -v0S +%s
}

# ── saved state (survives restarts) ──────────────────────────
AWAY_SINCE=0 AWAY_LOGGED=0 ARRIVED_AT=0
EP="" EP_KIND="" EP_START=0 EP_HOME=0 EP_NOTIF="" NEXT_POLL=0 NEXT_NUDGE=0 NUDGES=0
SNOOZE_UNTIL=0 SKIP_UNTIL=0 BED_DAY="" WAKE_DAY="" WAKES=0
BAT="?" LIM="?" CS=""
[[ -f $STATE ]] && source "$STATE"
save() {
  typeset -p AWAY_SINCE AWAY_LOGGED ARRIVED_AT EP EP_KIND EP_START EP_HOME EP_NOTIF \
    NEXT_POLL NEXT_NUDGE NUDGES SNOOZE_UNTIL SKIP_UNTIL BED_DAY WAKE_DAY WAKES BAT LIM \
    > "$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"
}

# ── PushWard ─────────────────────────────────────────────────
PW_KEY=$(security find-generic-password -s "$KC" -a pushward -w 2>/dev/null)
if [[ -z $PW_KEY ]]; then log "ERROR: no PushWard key saved — run the setup again"; sleep 300; exit 1; fi

pw() {   # pw METHOD PATH [JSON]  → response in $TMP/pw.json
  local args=(-sS --max-time 30 -X "$1" "$PWAPI$2" -H "Authorization: Bearer $PW_KEY"
              -o "$TMP/pw.json" -w '%{http_code}')
  if [[ -n ${3:-} ]]; then
    local ct=application/json; [[ $1 == PATCH ]] && ct=application/merge-patch+json
    args+=(-H "Content-Type: $ct" --data-binary "$3")
  fi
  rm -f "$TMP/pw.json"
  PW_CODE=$(curl "${args[@]}" 2>/dev/null) || PW_CODE=000
  [[ $PW_CODE == 2* ]] && return 0
  log "PushWard $1 $2 → $PW_CODE $(head -c 300 "$TMP/pw.json" 2>/dev/null)"
  return 1
}

fallback() {   # if PushWard is down, a Reminder still reaches the phone
  log "PushWard unreachable — sending a Reminder instead: $1"
  /usr/bin/osascript - "$1" "$2" >/dev/null 2>&1 <<'OSA'
on run argv
  tell application "Reminders"
    tell default list
      make new reminder with properties {name:(item 1 of argv), body:(item 2 of argv), remind me date:((current date) + 30)}
    end tell
  end tell
end run
OSA
}

mins_label() { (( $1 % 60 == 0 )) && print -r -- "$(( $1 / 60 )) hr" || print -r -- "$1 min"; }
SHORT_LBL="Snooze $(mins_label $SNOOZE_MIN)"
LONG_LBL="Snooze $(mins_label $SNOOZE_LONG_MIN)"
NOTIF_ID=""
notify() {   # notify LEVEL TITLE BODY [WITH_BUTTONS 0/1] [GROUP]
  local level=$1 title=$2 body=$3 act=${4:-0} col=${5:-plugcheck} extra=""
  (( act )) && extra=",\"actions\":[{\"id\":\"snooze\",\"title\":\"$SHORT_LBL\",\"icon\":\"moon.zzz\"},{\"id\":\"snooze_long\",\"title\":\"$LONG_LBL\",\"icon\":\"clock\"},{\"id\":\"skip\",\"title\":\"Not today\",\"icon\":\"xmark.circle\",\"destructive\":true}]"
  [[ -n $LOOK_NOTIF_ICON ]] && extra+=",\"icon_url\":\"$LOOK_NOTIF_ICON\""
  [[ $level == critical ]] && extra+=",\"volume\":0.8"
  [[ -n $EP ]] && extra+=",\"activity_slug\":\"$EP\""
  local b="{\"title\":\"$(jesc "$title")\",\"body\":\"$(jesc "$body")\",\"level\":\"$level\",\"collapse_id\":\"$col\",\"thread_id\":\"plugcheck\",\"source\":\"plugcheck\",\"source_display_name\":\"PlugCheck\"$extra}"
  NOTIF_ID=""
  if pw POST /notifications "$b"; then
    NOTIF_ID=$(json "$TMP/pw.json" id) || NOTIF_ID=""
    return 0
  fi
  fallback "$title" "$body"
  return 1
}

# ── Tesla ────────────────────────────────────────────────────
ACCESS="" ACCESS_EXP=0 ERR=""
tesla_token() {
  (( $(now) < ACCESS_EXP - 300 )) && return 0
  local r n e
  r=$(security find-generic-password -s "$KC" -a refresh_token -w 2>/dev/null) \
    || { ERR="No saved Tesla sign-in — run the setup again."; return 1; }
  curl -sS --max-time 30 -X POST "$AUTH" \
    --data-urlencode grant_type=refresh_token \
    --data-urlencode client_id="$CLIENT_ID" \
    --data-urlencode refresh_token="$r" -o "$TMP/tok.json" 2>/dev/null \
    || { ERR="Couldn't reach Tesla (network)."; return 1; }
  ACCESS=$(json "$TMP/tok.json" access_token) || {
    ERR="Tesla sign-in expired — run the setup again."
    log "token error: $(head -c 300 "$TMP/tok.json")"; return 1; }
  n=$(json "$TMP/tok.json" refresh_token) && security add-generic-password -U -s "$KC" -a refresh_token -w "$n"
  e=$(json "$TMP/tok.json" expires_in) || e=28800
  ACCESS_EXP=$(( $(now) + e ))
}
tget() { curl -sS --max-time 30 -H "Authorization: Bearer $ACCESS" "$API$1" -o "$2" -w '%{http_code}' 2>/dev/null; }

car_status() {   # car_status [ALLOW_WAKE 0/1] → sets CS, BAT, LIM (or ERR)
  ERR="" CS=""
  tesla_token || return 1
  local code st i
  code=$(tget "/api/1/vehicles/$VIN" "$TMP/v.json")
  if [[ $code == 401 ]]; then ACCESS_EXP=0; tesla_token || return 1; code=$(tget "/api/1/vehicles/$VIN" "$TMP/v.json"); fi
  [[ $code == 200 ]] || { ERR="Tesla didn't answer (error $code)."; log "vehicle error $code: $(head -c 200 "$TMP/v.json" 2>/dev/null)"; return 1; }
  st=$(json "$TMP/v.json" response.state)
  if [[ $st != online ]]; then
    (( ${1:-0} )) || { CS=asleep; return 2; }
    [[ $WAKE_DAY == $(today) ]] || { WAKE_DAY=$(today); WAKES=0; }
    (( WAKES < MAX_WAKES )) || { ERR="Daily wake-up limit reached (protects your free Tesla credit)."; return 1; }
    WAKES=$(( WAKES + 1 ))
    log "car is $st — waking it"
    curl -sS --max-time 20 -X POST -H "Authorization: Bearer $ACCESS" "$API/api/1/vehicles/$VIN/wake_up" -o /dev/null 2>/dev/null
    for i in {1..18}; do
      sleep 5
      tget "/api/1/vehicles/$VIN" "$TMP/v.json" >/dev/null
      st=$(json "$TMP/v.json" response.state)
      [[ $st == online ]] && break
    done
    [[ $st == online ]] || { ERR="The car didn't wake up ($st) — it may have no signal."; return 1; }
  fi
  code=$(tget "/api/1/vehicles/$VIN/vehicle_data?endpoints=charge_state" "$TMP/d.json")
  [[ $code == 200 ]] || { ERR="Couldn't read the charge status (error $code)."; log "charge_state error $code: $(head -c 200 "$TMP/d.json" 2>/dev/null)"; return 1; }
  CS=$(json "$TMP/d.json" response.charge_state.charging_state) || { ERR="Couldn't read the charge status."; return 1; }
  BAT=$(json "$TMP/d.json" response.charge_state.battery_level) || BAT="?"
  LIM=$(json "$TMP/d.json" response.charge_state.charge_limit_soc) || LIM="?"
  log "car: $CS · $BAT% (limit $LIM%)"
  return 0
}

charge_line() {
  case $CS in
    Charging) print -r -- "Charging · $BAT% → $LIM%" ;;
    Starting) print -r -- "Starting to charge · $BAT%" ;;
    Complete) print -r -- "Charge complete · $BAT%" ;;
    Stopped)  print -r -- "Will charge on schedule · $BAT% → $LIM%" ;;
    *)        print -r -- "Plugged in · $BAT%" ;;
  esac
}

# ── Wi-Fi presence (arrival detection) ───────────────────────
car_here() {
  [[ -n $CAR_IP ]] || return 0
  ping -c 1 -t 2 "$CAR_IP" >/dev/null 2>&1 && return 0
  arp -n "$CAR_IP" 2>/dev/null | grep -qE ' at [0-9a-fA-F]{1,2}:'
}
car_away() { [[ -n $CAR_IP ]] && (( AWAY_SINCE > 0 && $(now) - AWAY_SINCE >= AWAY_MIN * 60 )); }

presence() {
  [[ -n $CAR_IP ]] || return 0
  local t=$(now)
  if car_here; then
    if (( AWAY_SINCE > 0 )); then
      if (( t - AWAY_SINCE >= AWAY_MIN * 60 )); then
        log "car arrived home (gone $(( (t - AWAY_SINCE) / 60 )) min)"
        ARRIVED_AT=$t
      fi
      AWAY_SINCE=0 AWAY_LOGGED=0
    fi
  else
    (( AWAY_SINCE > 0 )) || AWAY_SINCE=$t
    if (( ! AWAY_LOGGED && t - AWAY_SINCE >= AWAY_MIN * 60 )); then
      log "car left home"; AWAY_LOGGED=1; SNOOZE_UNTIL=0
    fi
  fi
}

# ── reminder episode (Live Activity + nudges) ────────────────
ep_start() {   # ep_start KIND [FIRST_ALERT_LEVEL | none = silent renewal]
  local kind=$1 level=${2:-time-sensitive} t=$(now) state sub details snd=",\"sound\":\"$LOOK_SOUND\""
  [[ $level == none ]] && snd=""
  local compact="" colors=""
  [[ -n $LOOK_BG ]] && colors+=",\"background_color\":\"$LOOK_BG\""
  [[ -n $LOOK_TEXT ]] && colors+=",\"text_color\":\"$LOOK_TEXT\""
  (( LOOK_BATTERY_IN_ISLAND )) && [[ $BAT == <-> ]] && compact=",\"compact_label\":\"$BAT%\""
  EP="plug-$(date +%Y%m%d-%H%M%S)" EP_KIND=$kind EP_START=$t NUDGES=0 EP_NOTIF=""
  if [[ $kind == demo ]]; then
    state="PlugCheck test" sub="Tap a button to try it — nothing else to do"
    details="[{\"label\":\"Car\",\"value\":\"$(jesc "$CAR") · $BAT%\"}]"
  else
    state="$CAR isn't plugged in" sub="Battery $BAT% · charges to $LIM%"
    low_batt && sub="Only $BAT% — needs $NEED_PCT% for tomorrow"
    if quiet; then   # overnight: stay silent unless the car can't make the commute
      if low_batt; then level=critical; else level=none; fi
    fi
    if [[ $kind == arrival ]]; then
      details="[{\"label\":\"Home since\",\"value\":\"$(clock $EP_HOME)\"}]"
    else
      details="[{\"label\":\"Checked\",\"value\":\"$(clock $t)\"}]"
    fi
  fi
  log "reminder started ($kind) → $EP"
  if pw POST /activities "{\"slug\":\"$EP\",\"name\":\"Plug in?\",\"stale_ttl\":28800,\"ended_ttl\":86400}"; then
    pw PATCH "/activities/$EP" "{\"state\":\"ongoing\"$snd,\"content\":{\"template\":\"approval\",\"state\":\"$(jesc "$state")\",\"subtitle\":\"$(jesc "$sub")\",\"icon\":\"$LOOK_ICON\",\"accent_color\":\"$LOOK_ACCENT\",\"source\":\"PlugCheck\",\"details\":$details$compact$colors,\"options\":[{\"id\":\"snooze\",\"title\":\"$SHORT_LBL\",\"style\":\"primary\",\"icon\":\"moon.zzz\"},{\"id\":\"snooze_long\",\"title\":\"$LONG_LBL\",\"style\":\"secondary\",\"icon\":\"clock\"},{\"id\":\"skip\",\"title\":\"Not today\",\"style\":\"secondary\",\"icon\":\"xmark\"}]}}"
  fi
  if [[ $level == none ]]; then
    :
  elif [[ $kind == demo ]]; then
    notify active "PlugCheck test" "Tap a button on the Live Activity — or press and hold this." 1
  else
    if low_batt; then
      notify "$level" "Plug in the $CAR now 🔌" "Only $BAT% — not enough for tomorrow's commute (needs $NEED_PCT%)." 1
    else
      notify "$level" "Plug in the $CAR 🔌" "Not plugged in · battery $BAT%. Press and hold for Snooze." 1
    fi
  fi
  EP_NOTIF=$NOTIF_ID
  NEXT_POLL=$(( t + POLL_SEC )) NEXT_NUDGE=$(( t + NUDGE_SEC ))
  save
}

ep_end() {   # ep_end HOW  (plugged | nopower | quiet)
  [[ -n $EP ]] || return 0
  local body
  case $1 in
    plugged) body="{\"state\":\"ended\",\"dismissal_ttl\":120,\"content\":{\"template\":\"approval\",\"state\":\"Plugged in ✓\",\"subtitle\":\"$(jesc "$(charge_line)")\",\"icon\":\"checkmark.circle.fill\",\"accent_color\":\"green\"}}" ;;
    nopower) body="{\"state\":\"ended\",\"dismissal_ttl\":3600,\"content\":{\"template\":\"approval\",\"state\":\"Plugged in — but no power\",\"subtitle\":\"Check the outlet or breaker\",\"icon\":\"exclamationmark.triangle.fill\",\"accent_color\":\"red\"}}" ;;
    *)       body="{\"state\":\"ended\",\"dismissal_ttl\":0}" ;;
  esac
  pw PATCH "/activities/$EP" "$body" || true
  log "reminder ended ($1)"
  EP="" EP_KIND="" EP_NOTIF="" NEXT_POLL=0 NEXT_NUDGE=0 NUDGES=0
  save
}

got_answer() {   # → prints snooze / skip / nothing
  local a=""
  if pw GET "/activities/$EP"; then a=$(json "$TMP/pw.json" content.answer.option) || a=""; fi
  if [[ -z $a || $a == none ]] && [[ -n $EP_NOTIF ]]; then
    if pw GET "/notifications/answers/$EP_NOTIF" && [[ $(json "$TMP/pw.json" status) == answered ]]; then
      a=$(json "$TMP/pw.json" action_id) || a=""
    fi
  fi
  [[ $a == none ]] && a=""
  print -r -- "$a"
}

ep_tick() {
  local t=$(now) ans
  ans=$(got_answer)

  if [[ $EP_KIND == demo ]]; then
    if [[ -n $ans ]]; then
      local label=$SHORT_LBL; [[ $ans == snooze_long ]] && label=$LONG_LBL; [[ $ans == skip ]] && label="Not today"
      log "DEMO ANSWERED: $ans"
      ep_end quiet
      notify passive "Test worked ✓" "You tapped “$label”. PlugCheck is ready."
    elif (( t - EP_START > 300 )); then
      log "DEMO TIMED OUT (no tap in 5 min)"; ep_end quiet
    fi
    return
  fi

  case $ans in
    snooze|snooze_long)
      if [[ $ans == snooze_long ]]; then SNOOZE_UNTIL=$(( t + SNOOZE_LONG_MIN * 60 )); else SNOOZE_UNTIL=$(( t + SNOOZE_MIN * 60 )); fi
      log "snoozed until $(clock $SNOOZE_UNTIL)"
      ep_end quiet
      notify passive "Snoozed" "I'll check the $CAR again at $(clock $SNOOZE_UNTIL)."
      return ;;
    skip)
      SKIP_UNTIL=$(next_morning) SNOOZE_UNTIL=0
      log "not today — quiet until $(date -r $SKIP_UNTIL '+%a') $(clock $SKIP_UNTIL)"
      ep_end quiet
      notify passive "OK — no more reminders today" "Bedtime check is off tonight too."
      return ;;
  esac

  local poll=$POLL_SEC wake=1 rc
  (( NUDGES >= NUDGE_FAST )) && poll=300
  if quiet; then poll=900; wake=0; fi      # overnight: check gently, never wake the car
  if (( t >= NEXT_POLL )); then
    NEXT_POLL=$(( t + poll ))
    car_status $wake; rc=$?
    if (( rc == 0 )); then
      case $CS in
        Disconnected) ;;
        NoPower)
          ep_end nopower
          notify time-sensitive "$CAR has no power ⚠️" "It's plugged in but not getting power — check the outlet or breaker."
          return ;;
        *)
          ep_end plugged
          notify passive "Plugged in ✓" "$(charge_line)"
          return ;;
      esac
    elif (( rc == 1 )); then
      log "check failed: $ERR"
    fi
  fi

  if car_away; then log "car left while reminding — stopping"; ep_end quiet; return; fi

  if (( t - EP_START > 7 * 3600 )); then   # iOS caps a Live Activity at 8 h — renew it silently
    local k=$EP_KIND n=$NUDGES nn=$NEXT_NUDGE
    log "renewing the Live Activity (8-hour iOS limit)"
    ep_end quiet
    ep_start "$k" none
    NUDGES=$n NEXT_NUDGE=$nn
  fi

  if (( t >= NEXT_NUDGE )); then
    if quiet && low_batt; then
      # Not enough charge for the commute: wake him up, every URGENT_NIGHT_SEC
      NUDGES=$(( NUDGES + 1 ))
      notify critical "Plug in the $CAR now 🔌" "Only $BAT% — not enough for tomorrow's commute (needs $NEED_PCT%)." 1
      [[ -n $NOTIF_ID ]] && EP_NOTIF=$NOTIF_ID
      NEXT_NUDGE=$(( t + URGENT_NIGHT_SEC ))
    elif quiet; then
      NEXT_NUDGE=$(( t + 300 ))   # enough charge: let him sleep; re-evaluate in 5 min
    else
      NUDGES=$(( NUDGES + 1 ))
      local lvl=time-sensitive
      evening && low_batt && lvl=critical   # after bedtime check and too low: break through Sleep Focus
      if low_batt; then
        notify $lvl "Plug in the $CAR now 🔌" "Still not plugged in · only $BAT% (needs $NEED_PCT% for tomorrow)." 1
      else
        notify $lvl "Plug in the $CAR 🔌" "Still not plugged in · battery $BAT%. Press and hold for Snooze." 1
      fi
      [[ -n $NOTIF_ID ]] && EP_NOTIF=$NOTIF_ID
      if (( NUDGES < NUDGE_FAST )) || { evening && low_batt; }; then NEXT_NUDGE=$(( t + NUDGE_SEC )); else NEXT_NUDGE=$(( t + NUDGE_SLOW_SEC )); fi
    fi
  fi
}

# ── checks ───────────────────────────────────────────────────
start_if_unplugged() {   # start_if_unplugged KIND LEVEL
  if car_status 1; then
    case $CS in
      Disconnected) ep_start "$1" "$2" ;;
      NoPower) notify time-sensitive "$CAR has no power ⚠️" "It's plugged in but not getting power — check the outlet or breaker." ;;
      *) log "$1 check: plugged in ✓" ;;
    esac
  else
    log "$1 check failed: $ERR"
    return 1
  fi
}

arrival_check() {
  (( ARRIVED_AT > 0 && $(now) >= ARRIVED_AT + GRACE_MIN * 60 )) || return 0
  EP_HOME=$ARRIVED_AT ARRIVED_AT=0
  if [[ -n $EP ]]; then return 0; fi
  if (( SKIP_UNTIL > $(now) )); then log "arrival: skipped (Not today)"; return 0; fi
  if (( AWAY_SINCE > 0 )); then log "arrival: car left again"; return 0; fi
  if quiet; then
    car_status 0 >/dev/null 2>&1
    if low_batt; then start_if_unplugged arrival critical
    else log "arrival during quiet hours — enough charge, leaving it alone"; fi
    return 0
  fi
  start_if_unplugged arrival time-sensitive
}

snooze_check() {
  (( SNOOZE_UNTIL > 0 && $(now) >= SNOOZE_UNTIL )) || return 0
  SNOOZE_UNTIL=0
  [[ -n $EP ]] && return 0
  (( SKIP_UNTIL > $(now) )) && return 0
  if car_away; then log "snooze over, but the car isn't home"; return 0; fi
  start_if_unplugged snooze time-sensitive \
    || notify time-sensitive "PlugCheck couldn't check the $CAR" "$ERR Make sure it's plugged in."
}

bedtime_check() {
  BED_DAY=$(today); SNOOZE_UNTIL=0; save
  log "bedtime check"
  if (( SKIP_UNTIL > $(now) )); then log "bedtime: skipped (Not today)"; return 0; fi
  if [[ -n $EP ]]; then
    notify critical "Plug in the $CAR before bed 🔌" "Still not plugged in · battery $BAT%." 1
    [[ -n $NOTIF_ID ]] && EP_NOTIF=$NOTIF_ID
    return 0
  fi
  if car_status 1; then
    case $CS in
      Disconnected)
        if car_away; then
          notify time-sensitive "$CAR isn't home yet" "Not plugged in · battery $BAT%. I'll remind you once it's back." 0 plugcheck-bedtime
        else
          ep_start bedtime critical
        fi ;;
      NoPower)
        notify critical "$CAR has no power ⚠️" "It's plugged in but not getting power — check the outlet or breaker." 0 plugcheck-bedtime ;;
      *)
        notify passive "Plugged in ✓" "$(charge_line)" 0 plugcheck-bedtime ;;
    esac
  else
    notify time-sensitive "PlugCheck couldn't check the $CAR" "$ERR Make sure it's plugged in before bed." 0 plugcheck-bedtime
  fi
}

handle_cmd() {   # commands from the `plugcheck` control script
  [[ -f $DIR/cmd ]] || return 0
  local c=$(<"$DIR/cmd"); rm -f "$DIR/cmd"
  log "command: $c"
  case $c in
    demo)    [[ -n $EP ]] && ep_end quiet; ep_start demo active ;;
    check)   if car_status 1; then log "CHECK OK: $CS · $BAT% (limit $LIM%)"; else log "CHECK FAILED: ${ERR:-unknown error — see ~/PlugCheck/errors.log}"; fi ;;
    arrive)  ARRIVED_AT=$(( $(now) - GRACE_MIN * 60 )) AWAY_SINCE=0 ;;
    bedtime) bedtime_check ;;
    resume)  SKIP_UNTIL=0 SNOOZE_UNTIL=0 ;;
  esac
}

# One-time: ask macOS for permission to use Reminders (the backup channel)
if [[ ! -f $DIR/.reminders-ok ]]; then
  /usr/bin/osascript -e 'tell application "Reminders" to get name of default list' >/dev/null 2>&1 \
    && touch "$DIR/.reminders-ok"
fi

# ── main loop ────────────────────────────────────────────────
log "PlugCheck started (car IP: ${CAR_IP:-none}, bedtime $BEDTIME)"
TICKS=0
while true; do
  handle_cmd
  presence
  [[ -n $EP ]] && ep_tick
  arrival_check
  snooze_check
  if [[ $BED_DAY != $(today) ]] && (( 10#$(hm) >= BEDTIME )); then bedtime_check; fi
  save
  TICKS=$(( TICKS + 1 ))
  [[ -n ${PLUGCHECK_MAX_TICKS:-} ]] && (( TICKS >= PLUGCHECK_MAX_TICKS )) && break
  if [[ -n $EP ]]; then sleep 20; else sleep 60; fi
done
DAEMON
chmod +x "$APP_DIR/plugcheckd.zsh"

cat > "$APP_DIR/plugcheck" <<'CTL'
#!/bin/zsh
# PlugCheck control:  ~/PlugCheck/plugcheck [status|check|test|bedtime|resume|log|update|restart|stop]
DIR="$HOME/PlugCheck"; LABEL=com.andy.plugcheck; LOG="$DIR/plugcheck.log"
lines() { if [[ -f $1 ]]; then wc -l < "$1" | tr -d ' '; else print 0; fi; }
send() {   # send COMMAND STOP_PATTERN SECONDS — shows log lines until the pattern appears
  local before=$(lines "$LOG") i n chunk
  print -r -- "$1" > "$DIR/cmd"
  print "Sent \"$1\" — results:"
  for (( i = 0; i < ${3:-60}; i += 2 )); do
    sleep 2
    n=$(lines "$LOG")
    if (( n > before )); then
      chunk=$(tail -n $(( n - before )) "$LOG"); print -r -- "$chunk"; before=$n
      print -r -- "$chunk" | grep -qE "$2" && return 0
    fi
  done
  print "(still working — follow along with: ~/PlugCheck/plugcheck log)"
}
case ${1:-status} in
  status)
    if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then print "PlugCheck is running ✓"; else print "PlugCheck is NOT running — try: ~/PlugCheck/plugcheck restart"; fi
    print "\nRecent activity:"; tail -n 15 "$LOG" 2>/dev/null ;;
  check)   send check "CHECK (OK|FAILED)" 120 ;;
  test)    print "Watch your iPhone and tap a button on the Live Activity."; send demo "DEMO (ANSWERED|TIMED OUT)" 330 ;;
  bedtime) send bedtime "car:|failed|skipped|Still" 120 ;;
  resume)  send resume "command: resume" 30; print "Snooze / Not today cleared." ;;
  log)     tail -n 40 -f "$LOG" ;;
  restart) launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
           launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$LABEL.plist" && print "Restarted ✓" ;;
  stop)    launchctl bootout "gui/$(id -u)/$LABEL" && print "Stopped. Start again with: ~/PlugCheck/plugcheck restart" ;;
  update)
    BASE=https://andygirard-ai.github.io/plugcheck
    print "Downloading the latest PlugCheck…"
    if ! curl -fsSL "$BASE/plugcheckd.zsh?$(date +%s)" -o "$DIR/.new-d" || ! curl -fsSL "$BASE/plugcheck?$(date +%s)" -o "$DIR/.new-c"; then
      rm -f "$DIR/.new-d" "$DIR/.new-c"; print "Couldn't download the update — check the internet connection."; exit 1
    fi
    if ! zsh -n "$DIR/.new-d" || ! zsh -n "$DIR/.new-c"; then
      rm -f "$DIR/.new-d" "$DIR/.new-c"; print "The download looked broken — kept your current version."; exit 1
    fi
    chmod +x "$DIR/.new-d" "$DIR/.new-c"
    mv -f "$DIR/.new-d" "$DIR/plugcheckd.zsh"; mv -f "$DIR/.new-c" "$DIR/plugcheck"
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
    launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$LABEL.plist" && print "Updated ✓  Preview it with:  ~/PlugCheck/plugcheck test" ;;
  *) print "Usage: ~/PlugCheck/plugcheck [status|check|test|bedtime|resume|log|update|restart|stop]" ;;
esac
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

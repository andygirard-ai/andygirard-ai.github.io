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

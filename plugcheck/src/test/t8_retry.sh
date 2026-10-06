export PLUGCHECK_SRC=${PLUGCHECK_SRC:-${${(%):-%x}:A:h:h}}
export TZ=America/New_York
T=$PLUGCHECK_SRC/test
export FAKE=$(mktemp -d) HOME=$(mktemp -d)
export PATH="$T/bin:$PATH"
python3 -c "import datetime as d;print(int(d.datetime(2026,10,6,11,0).timestamp()))" > $FAKE/now
print online > $FAKE/car_state; print Charging > $FAKE/cs; touch $FAKE/present
print snooze > $FAKE/answer_activity
printf '%s\n' hlk_test123 '' bad '••••••' sec 'https://andygirard-ai.github.io/plugcheck/?code=XYZ&state=abcd1234abcd1234' \
  | zsh $PLUGCHECK_SRC/../setup.sh
print -- "=== exit: $?"
print -- "=== config:"; cat $HOME/PlugCheck/config
print -- "=== keychain:"; ls $FAKE/kc
print -- "=== daemon log:"; cat $HOME/PlugCheck/plugcheck.log
print -- "=== daemon stderr:"; cat $FAKE/daemon.err
print -- "=== stop"; exit
printf '%s\n' '' '' '' | zsh $PLUGCHECK_SRC/../setup.sh 2>&1 | grep -E "✓|✗|!|Keeping"
launchctl bootout

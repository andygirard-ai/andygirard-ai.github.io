export PLUGCHECK_SRC=${PLUGCHECK_SRC:-${${(%):-%x}:A:h:h}}
export TZ=America/New_York FAKE=$(mktemp -d) HOME=$(mktemp -d)
export PATH="$PLUGCHECK_SRC/test/bin:$PATH"
date +%s > $FAKE/now
mkdir -p $HOME/PlugCheck $HOME/Library/LaunchAgents
print 'old daemon' > $HOME/PlugCheck/plugcheckd.zsh
cp $PLUGCHECK_SRC/plugcheck-ctl.zsh $HOME/PlugCheck/plugcheck
touch $HOME/Library/LaunchAgents/com.andy.plugcheck.plist
zsh $HOME/PlugCheck/plugcheck update
print -- "--- daemon replaced: $(grep -c LOOK_BATTERY_IN_ISLAND $HOME/PlugCheck/plugcheckd.zsh) lines with new setting; leftovers: $(ls -A $HOME/PlugCheck | grep -c '^\.new')"
launchctl bootout

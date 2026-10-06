#!/bin/zsh
# Build the published files in plugcheck/ from the sources in plugcheck/src/.
set -e
cd "${0:A:h}"
python3 - <<'PY'
s=open('setup.in.zsh').read()
d=open('plugcheckd.zsh').read().rstrip('\n'); c=open('plugcheck-ctl.zsh').read().rstrip('\n')
open('../setup.sh','w').write(s.replace('@@DAEMON@@', d).replace('@@CTL@@', c))
PY
cp plugcheckd.zsh ../plugcheckd.zsh
cp plugcheck-ctl.zsh ../plugcheck
zsh -n ../setup.sh && zsh -n ../plugcheckd.zsh && zsh -n ../plugcheck
echo "Built ../setup.sh ../plugcheckd.zsh ../plugcheck"

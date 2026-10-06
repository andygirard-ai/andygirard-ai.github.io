export PLUGCHECK_SRC=${PLUGCHECK_SRC:-${${(%):-%x}:A:h:h}}
# test helpers (zsh)
export TZ=America/New_York
T=$PLUGCHECK_SRC/test
export FAKE=$(mktemp -d) PLUGCHECK_DIR=$(mktemp -d)
export PATH="$T/bin:$PATH" PWAPI="https://api.pushward.app"
mkdir -p $FAKE/kc
print -n "pw-key" > $FAKE/kc/PlugCheck--pushward
print -n "RT-1" > $FAKE/kc/PlugCheck--refresh_token
touch $PLUGCHECK_DIR/.reminders-ok
cat > $PLUGCHECK_DIR/config <<C
CLIENT_ID='cid'
VIN='VIN1'
CAR='Model Y'
CAR_IP='192.168.1.50'
AUTH='https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token'
API='https://fleet-api.prd.na.vn.cloud.tesla.com'
C
setnow() { TZ=America/New_York python3 -c "import datetime as d;print(int(d.datetime.strptime('$1','%Y-%m-%d %H:%M').timestamp()))" > $FAKE/now; }
run() { PLUGCHECK_MAX_TICKS=$1 zsh $PLUGCHECK_SRC/plugcheckd.zsh; }
clock() { TZ=America/New_York date -d @$(cat $FAKE/now) '+%H:%M:%S'; }
showlog() { sed 's/^2026-10-0[0-9] //' $PLUGCHECK_DIR/plugcheck.log; }
pwreq() { grep pushward $FAKE/requests.log | sed 's#https://api.pushward.app##'; }

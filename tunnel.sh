#!/bin/sh
# Forwards the VM's Backplane hub (127.0.0.1:3787 inside) to this Mac's
# 127.0.0.1:${LOCAL_PORT:-3790} over SSH and prints a one-time pairing link.
# The hub stays on loopback inside the VM; nothing is exposed beyond this Mac.
#   ./tunnel.sh        open (or reuse) the tunnel and print a pairing link
#   ./tunnel.sh code   the same, but print an 8-character short code instead
#   ./tunnel.sh stop   close it
# Invitations work once and expire after ten minutes.
set -eu
cd "$(dirname "$0")"
lp=${LOCAL_PORT:-3790}
ctl=state/tunnel.sock
if [ "${1:-}" = stop ]; then
  ./ssh.sh -S "$ctl" -O exit 2>/dev/null && echo "tunnel closed" || echo "no tunnel"
  exit 0
fi
if ! ./ssh.sh -S "$ctl" -O check 2>/dev/null; then
  ./ssh.sh -M -S "$ctl" -f -N -o ExitOnForwardFailure=yes -L 127.0.0.1:"$lp":127.0.0.1:3787
fi
# a one-time invitation, asked with the hub's token inside the VM (token never leaves it)
json=$(./ssh.sh 'printf "Authorization: Bearer %s\n" "$(cat ~/.backplane-bend/token)" |
  curl -fs --max-time 5 -X POST -H @- http://127.0.0.1:3787/auth/invitations' || true)
inv=$(printf '%s' "$json" | sed -n 's/.*invite=\([0-9a-f]\{32\}\).*/\1/p')
code=$(printf '%s' "$json" | sed -n 's/.*"code":"\([A-Z0-9]\{8\}\)".*/\1/p')
if [ "${1:-}" = code ] && [ -n "$code" ]; then
  echo "short code: $code   hub address: http://127.0.0.1:$lp"
elif [ -n "$inv" ]; then
  echo "open: http://127.0.0.1:$lp/pair#invite=$inv"
else
  echo "tunnel up: http://127.0.0.1:$lp/ (no invitation; is the hub running? ./ssh.sh systemctl --user status backplane-bend)"
fi

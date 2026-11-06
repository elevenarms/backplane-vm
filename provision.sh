#!/bin/sh
# Copies guest/*.sh into the VM (~/vm-guest) and runs guest/provision.sh there.
#   GIT_NAME, GIT_EMAIL (optional) are passed on as the VM's git identity.
set -eu
cd "$(dirname "$0")"
./ssh.sh 'mkdir -p ~/vm-guest'
for f in guest/*.sh; do ./ssh.sh "cat > ~/vm-guest/$(basename "$f") && chmod +x ~/vm-guest/$(basename "$f")" < "$f"; done
# single-quote a value for the remote shell
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
envs=
[ -z "${GIT_NAME:-}" ] || envs="$envs GIT_NAME=$(q "$GIT_NAME")"
[ -z "${GIT_EMAIL:-}" ] || envs="$envs GIT_EMAIL=$(q "$GIT_EMAIL")"
./ssh.sh "${envs:+env$envs }~/vm-guest/provision.sh"

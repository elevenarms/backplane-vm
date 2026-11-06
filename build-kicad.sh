#!/bin/sh
# Starts the Backplane KiCad fork build inside the VM, detached in tmux
# (session "kicad"), logging to ~/kicad-build.log there.
#   KICAD_TAG=... JOBS=... ./build-kicad.sh   start (both optional)
#   ./build-kicad.sh log                      follow the log
#   ./ssh.sh -t tmux attach -t kicad          watch it live (detach: ctrl-b d)
set -eu
cd "$(dirname "$0")"
if [ "${1:-}" = log ]; then exec ./ssh.sh 'tail -n 40 -f ~/kicad-build.log'; fi
case "${KICAD_TAG:-}${JOBS:-}" in *[!A-Za-z0-9.-]*) echo "bad KICAD_TAG/JOBS" >&2; exit 2 ;; esac
./ssh.sh 'mkdir -p ~/vm-guest'
for f in guest/*.sh; do ./ssh.sh "cat > ~/vm-guest/$(basename "$f") && chmod +x ~/vm-guest/$(basename "$f")" < "$f"; done
envs=
[ -z "${KICAD_TAG:-}" ] || envs="$envs KICAD_TAG=$KICAD_TAG"
[ -z "${JOBS:-}" ] || envs="$envs JOBS=$JOBS"
./ssh.sh "if tmux has-session -t kicad 2>/dev/null; then echo 'already running (tmux session kicad)'; exit 1; fi
  tmux new-session -d -s kicad 'env$envs ~/vm-guest/run-build.sh'
  echo 'build started (tmux session kicad, log ~/kicad-build.log)'"

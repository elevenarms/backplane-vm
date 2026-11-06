#!/bin/bash
# tmux entry for build-kicad.sh: logs to ~/kicad-build.log, records the exit
# status as the log's last line, and keeps the window open afterwards.
set -o pipefail
~/vm-guest/build-kicad.sh 2>&1 | tee ~/kicad-build.log
echo "exit=$?" | tee -a ~/kicad-build.log
exec bash

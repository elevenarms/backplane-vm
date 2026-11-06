#!/bin/sh
# Shuts the VM down cleanly (ACPI power button), waiting up to 60 s.
set -eu
cd "$(dirname "$0")"
pid=$(cat state/qemu.pid 2>/dev/null || true)
[ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || { echo "not running"; exit 0; }
echo system_powerdown | nc -U state/monitor.sock >/dev/null 2>&1 || true
i=0
while kill -0 "$pid" 2>/dev/null && [ $i -lt 60 ]; do sleep 1; i=$((i + 1)); done
if kill -0 "$pid" 2>/dev/null; then
  echo "did not power off in 60 s; still running as pid $pid (kill $pid to force)"; exit 1
fi
rm -f state/qemu.pid
echo stopped

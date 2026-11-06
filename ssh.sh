#!/bin/sh
# ssh into the VM as bp (extra args are passed to ssh, e.g. a command).
cd "$(dirname "$0")"
exec ssh -i state/id_ed25519 -p "${SSH_PORT:-2222}" \
  -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=state/known_hosts \
  -o LogLevel=ERROR bp@127.0.0.1 "$@"

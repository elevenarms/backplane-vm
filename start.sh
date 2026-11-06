#!/bin/sh
# Starts the VM in the background (HVF-accelerated, headless).
#   VM_MEM (default 8G), VM_CPUS (default 6), SSH_PORT (default 2222)
# Serial console log: state/console.log. Only SSH is forwarded, on 127.0.0.1.
set -eu
cd "$(dirname "$0")"
[ -f state/disk.qcow2 ] || { echo "no VM yet: run ./create.sh" >&2; exit 1; }
if [ -f state/qemu.pid ] && kill -0 "$(cat state/qemu.pid)" 2>/dev/null; then
  echo "already running (pid $(cat state/qemu.pid))"; exit 0
fi
port=${SSH_PORT:-2222}
qemu-system-aarch64 \
  -name bp-vm \
  -machine virt,highmem=on \
  -accel hvf -cpu host \
  -smp "${VM_CPUS:-6}" -m "${VM_MEM:-8G}" \
  -drive if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd \
  -drive if=pflash,format=raw,file=state/efivars.fd \
  -drive if=virtio,format=qcow2,file=state/disk.qcow2,discard=unmap \
  -drive if=virtio,format=raw,readonly=on,file=state/seed.iso \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:"$port"-:22 \
  -device virtio-net-pci,netdev=net0 \
  -device virtio-rng-pci \
  -chardev socket,id=qga0,path=state/qga.sock,server=on,wait=off \
  -device virtio-serial -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
  -display none -serial file:state/console.log \
  -monitor unix:state/monitor.sock,server,nowait \
  -pidfile state/qemu.pid -daemonize
echo "started (pid $(cat state/qemu.pid)); ssh: ./ssh.sh  (first boot takes a minute)"

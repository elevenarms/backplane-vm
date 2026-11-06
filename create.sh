#!/bin/sh
# Creates the Backplane VM's disk, EFI vars, SSH key and cloud-init seed.
# Run once. Leaves the downloaded base image untouched (the disk is an overlay).
#   DISK_SIZE (default 64G)
set -eu
cd "$(dirname "$0")"
base=images/ubuntu-26.04-server-cloudimg-arm64.img
[ -f "$base" ] || { echo "missing $base (see README.md)" >&2; exit 1; }
[ ! -e state/disk.qcow2 ] || { echo "state/disk.qcow2 already exists; remove state/ to start over" >&2; exit 1; }
mkdir -p state

# a key only for this VM
[ -f state/id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -C bp-vm -f state/id_ed25519

# disk: copy-on-write overlay over the cloud image, grown on first boot
qemu-img create -q -f qcow2 -F qcow2 -b "$PWD/$base" state/disk.qcow2 "${DISK_SIZE:-64G}"

# EFI variable store, same size as the firmware code image
code=/opt/homebrew/share/qemu/edk2-aarch64-code.fd
dd if=/dev/zero of=state/efivars.fd bs=1m count=$(( $(stat -f %z "$code") / 1048576 )) 2>/dev/null

# cloud-init NoCloud seed (volume label must be "cidata")
seed=state/seed
rm -rf "$seed" && mkdir -p "$seed"
printf 'instance-id: bp-vm-1\nlocal-hostname: bp-vm\n' > "$seed/meta-data"
cat > "$seed/user-data" <<EOF
#cloud-config
users:
  - name: bp
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - $(cat state/id_ed25519.pub)
ssh_pwauth: false
package_update: true
packages: [qemu-guest-agent]
growpart: {mode: auto, devices: ['/']}
EOF
rm -f state/seed.iso
hdiutil makehybrid -quiet -iso -joliet -default-volume-name cidata -o state/seed.iso "$seed"
echo "created state/ (disk, efivars, ssh key, seed.iso). Next: ./start.sh"

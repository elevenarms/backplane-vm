# backplane-vm

Shell scripts that run [Backplane](https://github.com/BackplaneWorks/Backplane)
(an agent hub) headless in an Ubuntu 26.04 arm64 VM on an Apple silicon Mac,
using QEMU with the Hypervisor.framework accelerator (HVF, near-native speed).

The VM holds the whole setup: the Backplane hub, Claude Code, the GitHub CLI,
FreeCAD, Blender, the Backplane source, and optionally the Backplane KiCad fork
built for arm64. Only SSH is forwarded to the Mac, on `127.0.0.1:2222`; the hub
listens on the VM's own loopback and reaches the Mac only through an SSH tunnel
you open with `tunnel.sh`. Nothing listens beyond the Mac's loopback.

## Requirements

- An Apple silicon Mac (the scripts use `-accel hvf -cpu host` with
  `qemu-system-aarch64`, and macOS tools: `hdiutil`, BSD `stat`, `nc -U`).
- QEMU from Homebrew: `brew install qemu`. The scripts expect Homebrew's
  default Apple silicon prefix and its UEFI firmware at
  `/opt/homebrew/share/qemu/edk2-aarch64-code.fd`.
- OpenSSH (`ssh`, `ssh-keygen`; built into macOS) and `curl`/`shasum` to fetch
  the cloud image.
- Resources: 8 GiB RAM and 6 vCPUs for the VM by default; a 64 GiB
  copy-on-write disk that grows as used (a provisioned VM in daily use was
  about 23 GiB), plus the ~0.9 GiB cloud image.
- Internet access for the VM (packages, releases, sign-ins).
- A Claude account for Claude Code, and optionally a GitHub account for `gh`.

## Quick start

```sh
git clone https://github.com/elevenarms/backplane-vm.git && cd backplane-vm

# 1. Download the Ubuntu 26.04 arm64 cloud image and check it
mkdir -p images && cd images
curl -fLO https://cloud-images.ubuntu.com/releases/26.04/release/SHA256SUMS
curl -fLO https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-arm64.img
grep ' \*ubuntu-26.04-server-cloudimg-arm64.img$' SHA256SUMS | shasum -a 256 -c -
cd ..

# 2. Create the VM (once) and boot it
./create.sh               # DISK_SIZE=64G by default
./start.sh                # VM_MEM=8G VM_CPUS=6 SSH_PORT=2222 by default; first boot takes a minute

# 3. Install everything inside the VM (idempotent, re-runnable)
./provision.sh
# optional git identity for agents' commits in the VM:
GIT_NAME="Your Name" GIT_EMAIL="you@example.com" ./provision.sh

# 4. Sign in, once, interactively
./ssh.sh -t claude auth login     # Claude Code
./ssh.sh -t gh auth login         # GitHub CLI (choose HTTPS and the git credential helper)

# 5. Open the tunnel and pair a browser with the hub
./tunnel.sh               # prints http://127.0.0.1:3790/pair#invite=<one-time code>
./tunnel.sh code          # or: an 8-character short code + hub address http://127.0.0.1:3790

# Later
./tunnel.sh stop
./stop.sh                 # clean ACPI shutdown (waits up to 60 s)
```

Invitations from `tunnel.sh` work once and expire after ten minutes. They are
requested inside the VM with the hub's token, which never leaves the VM.

Projects live in the VM (e.g. `~/projects/<name>`); add them from the web UI.
Copy files in or out with
`scp -P 2222 -i state/id_ed25519 <src> bp@127.0.0.1:<dst>` (and the reverse).

Start over: `./stop.sh && rm -rf state && ./create.sh && ./start.sh && ./provision.sh`.

## What gets installed

`create.sh` makes a VM with one user, `bp` (passwordless sudo, SSH key login
only, no password login), plus `qemu-guest-agent`. `provision.sh` copies
`guest/` to `~/vm-guest` in the VM and runs `guest/provision.sh`, which
installs:

| Component | Version / source | Location |
|---|---|---|
| Base tools | Ubuntu packages: git, git-lfs, curl, jq, unzip, zstd, xz-utils, file, tmux, python3, python3-venv, poppler-utils (PDF pages in the Files tab), GL/EGL/fontconfig runtime libs | system |
| GitHub CLI `gh` | latest, from the cli.github.com apt repo | system |
| Blender | Ubuntu 26.04's arm64 package (5.0.1 at time of writing) | system |
| FreeCAD | **1.1.4**, official `FreeCAD_1.1.4-Linux-aarch64-py311.AppImage`, SHA-256 pinned, extracted (Ubuntu 26.04 has no package) | `~/opt/freecad-1.1.4`, wrappers `~/.local/bin/freecad`, `freecadcmd` |
| Claude Code | latest, native installer (`claude.ai/install.sh`) | `~/.local/bin/claude` |
| Backplane | latest linux-arm64 release, hub only (no desktop app); v0.14.1 at time of writing | `~/.local/share/backplane`, `~/.local/bin/backplane` |
| Backplane source | `BackplaneWorks/Backplane`, with its merge driver set up | `~/Backplane` |
| Swap | 8 GiB swapfile | `/swapfile` |
| Hub service | systemd user service `backplane-bend.service` with linger, so it starts at boot | `~/.config/systemd/user/` |

The hub service runs
`backplane --headless --foreground --no-tailscale --host 127.0.0.1 --port 3787`.
Extra environment for it goes in `~/.config/backplane/env` (the KiCad build
writes `BACKPLANE_KICAD=` there).

```sh
./ssh.sh systemctl --user status backplane-bend
./ssh.sh journalctl --user -u backplane-bend -f
```

`GIT_NAME` / `GIT_EMAIL` are optional; each is set in the VM's global git
config only when given and not already configured.

### Optional: Backplane KiCad fork

The fork publishes Linux runtimes for x86_64 only, so `build-kicad.sh` builds
it in the VM, detached in a tmux session (`kicad`), logging to
`~/kicad-build.log` there. `guest/build-kicad.sh` follows the fork's
`backplane-linux-release.yml` for the tag (Ubuntu 26.04 + GCC 15, same apt
deps, CMake flags and version stamping), installs in place to
`~/opt/backplane-kicad-<version>` against the VM's system libraries, adds the
official KiCad **10.0.6** symbol/footprint/3D/template libraries (checked
against the release's `SHA256SUMS`), writes the runtime's `manifest.json`
(platform `linux-arm64`), sets `BACKPLANE_KICAD` and restarts the hub.

```sh
./build-kicad.sh                                   # default tag backplane-kicad-v10.99.0-bp.6
KICAD_TAG=backplane-kicad-v10.99.0-bp.7 ./build-kicad.sh
JOBS=2 ./build-kicad.sh                            # default 3; lower it if the compiler runs out of memory
./build-kicad.sh log                               # follow the log
./ssh.sh -t tmux attach -t kicad                   # watch live (detach: ctrl-b d)
```

The first build takes a few hours. A re-run resumes: the checkout, build dir
and ccache are kept in `~/src` and `~/.cache/ccache`.

## Ports

| Where | Port | What |
|---|---|---|
| Mac `127.0.0.1` | 2222 (`SSH_PORT`) | QEMU user-net forward to the VM's SSH (22) |
| Mac `127.0.0.1` | 3790 (`LOCAL_PORT`) | SSH tunnel to the hub, opened by `tunnel.sh` |
| VM `127.0.0.1` | 3787 | Backplane hub (loopback only inside the VM) |

## Files

| Path | What |
|---|---|
| `create.sh` | creates `state/`: per-VM SSH key, qcow2 overlay on the cloud image, EFI vars, cloud-init seed ISO (run once) |
| `start.sh` / `stop.sh` | boot in the background / clean ACPI shutdown |
| `ssh.sh` | `ssh` to `bp@127.0.0.1:2222` with the VM's key; extra args go to `ssh` |
| `provision.sh` | copies `guest/*.sh` into the VM and runs `guest/provision.sh` |
| `tunnel.sh` | forwards the hub to `127.0.0.1:3790` and prints a pairing invite (`code`, `stop`) |
| `build-kicad.sh` | starts the KiCad fork build in the VM (`log` to follow) |
| `guest/provision.sh` | runs in the VM: installs everything above |
| `guest/build-kicad.sh`, `guest/run-build.sh` | KiCad fork build and its tmux wrapper |
| `guest/gh-asset.sh` | downloads a GitHub release asset, falling back to the REST asset endpoint |
| `images/` | the downloaded cloud image and `SHA256SUMS` (not in git) |
| `state/` | the VM: `disk.qcow2`, `efivars.fd`, `id_ed25519` key pair, `known_hosts`, `seed/` + `seed.iso`, `console.log`, `qemu.pid`, monitor/agent/tunnel sockets (not in git) |

The SSH key in `state/` is generated by `create.sh` for this VM only and goes
into the VM through the cloud-init seed; nothing user-specific is in the
scripts.

## Limitations

- Headless only: no display is attached (`-display none`). GUI apps are
  usable only in batch/CLI form (`freecadcmd`, `blender -b`, `kicad-cli`).
- No GPU: Blender renders with Cycles on the CPU; EEVEE needs a GPU and does
  not work.
- Apple silicon + Homebrew QEMU only (hard-coded `/opt/homebrew` firmware
  path, HVF acceleration, macOS `hdiutil` for the seed ISO).
- Source builds of Backplane itself (`scripts/dev.sh`) are not set up: the
  repo's memory guard wants at least 16 GiB free, more than the default VM has.
- The Backplane and Claude Code installs track their latest releases, so
  versions depend on when you provision.

## License

MIT, see [LICENSE](LICENSE).

#!/bin/bash
# Runs inside the VM as user bp (./provision.sh on the Mac copies and runs it).
# Idempotent: safe to run again.
#   GIT_NAME, GIT_EMAIL  optional git identity for agents' commits (set only when
#                        given and not already configured)
# Installs:
#   - base tools, gh, FreeCAD, Blender, poppler (PDF pages), an 8 GiB swapfile
#   - Claude Code (native installer, ~/.local/bin/claude)
#   - Backplane linux-arm64 release, hub only (~/.local/share/backplane)
#   - the Backplane source checkout (~/Backplane) with its merge driver
#   - a systemd user service running the hub headless on 127.0.0.1:3787
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

say "apt packages"
sudo apt-get update -q
sudo apt-get install -y -q --no-install-recommends \
  git git-lfs curl ca-certificates jq unzip zstd xz-utils file tmux \
  python3 python3-venv poppler-utils \
  libgl1 libegl1 libfontconfig1 libglib2.0-0t64 libxkbcommon0 libdbus-1-3

say "Blender (Ubuntu's arm64 build; headless use: blender -b, Cycles on CPU)"
sudo apt-get install -y -q blender

say "GitHub CLI (cli.github.com apt repo; sign in once with ./ssh.sh -t gh auth login)"
if ! command -v gh >/dev/null; then
  sudo install -d -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg |
    sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" |
    sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -q
  sudo apt-get install -y -q gh
fi
# optional git identity (GIT_NAME / GIT_EMAIL), applied only when given and not already configured
if [ -n "${GIT_NAME:-}" ]; then git config --global user.name >/dev/null || git config --global user.name "$GIT_NAME"; fi
if [ -n "${GIT_EMAIL:-}" ]; then git config --global user.email >/dev/null || git config --global user.email "$GIT_EMAIL"; fi

say "swap (8 GiB)"
if ! swapon --show=NAME --noheadings | grep -q '^/swapfile$'; then
  [ -f /swapfile ] || { sudo fallocate -l 8G /swapfile && sudo chmod 600 /swapfile && sudo mkswap -q /swapfile; }
  sudo swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

grep -q 'HOME/.local/bin' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
export PATH="$HOME/.local/bin:$PATH"

say "FreeCAD (official aarch64 AppImage, extracted; Ubuntu 26.04 has no package)"
FC_VER=1.1.4
fc_dir=~/opt/freecad-$FC_VER
# (a complete extract has a non-empty libpython; /tmp is a small tmpfs, so work on disk)
if [ ! -s "$fc_dir/usr/lib/libpython3.11.so.1.0" ]; then
  fc=FreeCAD_${FC_VER}-Linux-aarch64-py311.AppImage
  mkdir -p ~/opt
  tmp=$(mktemp -d ~/opt/.freecad-dl.XXXXXX)
  ~/vm-guest/gh-asset.sh FreeCAD/FreeCAD "$FC_VER" "$fc" "$tmp/$fc"
  # pinned: FreeCAD's published FreeCAD_1.1.4-Linux-aarch64-py311.AppImage-SHA256.txt
  (cd "$tmp" && echo "675d1a4295b2183e0e1d816a4b5557dcb63aeced4e60aaa28d6c3686f4c71dc9  $fc" | sha256sum -c -)
  chmod +x "$tmp/$fc"
  (cd "$tmp" && "./$fc" --appimage-extract >/dev/null)
  [ "$(find "$tmp/squashfs-root" -type f -size 0 -name '*.so*' | wc -l)" -lt 10 ] || { echo "FreeCAD extract is incomplete (disk full?)" >&2; exit 1; }
  rm -rf "$fc_dir" && mv "$tmp/squashfs-root" "$fc_dir"
  rm -rf "$tmp"
fi
mkdir -p ~/.local/bin
for c in freecad freecadcmd; do
  printf '#!/bin/sh\nexec "%s/AppRun" %s "$@"\n' "$fc_dir" "$([ $c = freecadcmd ] && echo freecadcmd)" > ~/.local/bin/$c
  chmod +x ~/.local/bin/$c
done
~/.local/bin/freecadcmd -c 'import FreeCAD; print("FreeCAD", ".".join(FreeCAD.Version()[:3]))'

say "Claude Code"
command -v claude >/dev/null || curl -fsSL https://claude.ai/install.sh | bash
claude --version

say "Backplane release (hub only)"
if [ ! -x ~/.local/share/backplane/backplane-serve ]; then
  curl -fsSL --retry 5 --retry-all-errors --retry-delay 3 -o /tmp/bp-install.sh https://github.com/BackplaneWorks/Backplane/releases/latest/download/install.sh
  BACKPLANE_NO_DESKTOP_APP=1 BACKPLANE_NO_DESKTOP=1 sh /tmp/bp-install.sh --quiet
  rm -f /tmp/bp-install.sh
fi
backplane --version

say "Backplane source"
[ -d ~/Backplane/.git ] || git clone -q https://github.com/BackplaneWorks/Backplane.git ~/Backplane
(cd ~/Backplane && sh scripts/setup-merge-driver.sh)

say "hub service"
mkdir -p ~/.config/systemd/user ~/.config/backplane
# extra environment for the hub (build-kicad.sh adds BACKPLANE_KICAD here)
touch ~/.config/backplane/env
cat > ~/.config/systemd/user/backplane-bend.service <<'EOF'
[Unit]
Description=Backplane hub (headless, loopback only)
After=network-online.target

[Service]
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
EnvironmentFile=-%h/.config/backplane/env
ExecStart=%h/.local/bin/backplane --headless --foreground --no-tailscale --host 127.0.0.1 --port 3787
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
sudo loginctl enable-linger "$USER"
export XDG_RUNTIME_DIR=/run/user/$(id -u)
for i in $(seq 1 30); do [ -S "$XDG_RUNTIME_DIR/bus" ] && break; sleep 1; done  # user manager starts after linger
systemctl --user daemon-reload
systemctl --user enable --now backplane-bend.service
for i in $(seq 1 30); do curl -fs -o /dev/null --max-time 1 http://127.0.0.1:3787/hello && break; sleep 1; done
curl -fs --max-time 2 http://127.0.0.1:3787/hello && echo
systemctl --user --no-pager status backplane-bend.service | head -5

say "done"
echo "Next (once, interactive): ./ssh.sh -t claude   # sign in to Claude Code"

#!/bin/bash
# Builds the Backplane KiCad fork (IPC API) for linux-arm64 inside the VM,
# following the fork's own Linux release workflow (Ubuntu 26.04, GCC 15):
# same apt deps, same CMake flags, same version stamping, same libraries.
# Installs a runtime at ~/opt/backplane-kicad-<version> and points the hub at
# it (BACKPLANE_KICAD in ~/.config/backplane/env), then restarts the hub.
#   KICAD_TAG  fork tag to build (default backplane-kicad-v10.99.0-bp.6, what
#              the hub ships for macOS and Windows)
#   JOBS       parallel compile jobs (default 3: 8 GiB RAM + 8 GiB swap)
# Re-running resumes: the checkout, build dir and ccache are kept in ~/src.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
TAG=${KICAD_TAG:-backplane-kicad-v10.99.0-bp.6}
JOBS=${JOBS:-3}
LIB_TAG=10.0.6
src=~/src/Backplane_KiCad-$TAG
dl=~/src/kicad-dl-$TAG
say() { printf '\n\033[1m== %s\033[0m  (%s)\n' "$*" "$(date +%H:%M:%S)"; }

say "build dependencies"
sudo apt-get update -q
sudo apt-get install -y -q --no-install-recommends \
  build-essential cmake ninja-build pkg-config ccache git \
  libboost-all-dev libbz2-dev libcairo2-dev libcurl4-openssl-dev \
  libeigen3-dev libfontconfig1-dev libfreetype-dev libgl-dev \
  libglm-dev \
  libgl1-mesa-dev libglew-dev libglu1-mesa-dev libglib2.0-dev \
  libgtk-3-dev libharfbuzz-dev libgit2-dev libssl-dev \
  libngspice0-dev ngspice libnng-dev libocct-data-exchange-dev \
  libocct-foundation-dev libocct-modeling-algorithms-dev \
  libocct-modeling-data-dev libocct-ocaf-dev \
  libocct-visualization-dev libpixman-1-dev libpng-dev \
  libpoppler-dev libpoppler-glib-dev libprotobuf-dev \
  libsecret-1-dev libspnav-dev libtool \
  libwxgtk3.2-dev libwxgtk-webview3.2-dev libx11-dev \
  libx11-xcb-dev libxkbcommon-x11-dev libyaml-cpp-dev \
  libzstd-dev mesa-common-dev pax-utils protobuf-compiler \
  python3 python3-venv rapidjson-dev shared-mime-info unixodbc-dev \
  zlib1g-dev libzint-dev glslang-tools spirv-tools
gcc --version | head -1

say "source $TAG"
if [ ! -d "$src/.git" ]; then
  mkdir -p ~/src
  git clone -q --depth 1 --branch "$TAG" https://github.com/BackplaneWorks/Backplane_KiCad.git "$src"
fi
cd "$src"
fork_version=$(cat BACKPLANE_VERSION)
[ "$TAG" = "backplane-kicad-v$fork_version" ] || { echo "tag $TAG != BACKPLANE_VERSION $fork_version" >&2; exit 1; }
prefix=~/opt/backplane-kicad-$fork_version
echo "fork $fork_version, upstream $(cat BACKPLANE_UPSTREAM), commit $(git rev-parse --short HEAD) -> $prefix"

say "configure"
export CCACHE_DIR=~/.cache/ccache
ccache --max-size=4G >/dev/null
cmake -S . -B build/backplane-linux -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_MODULE_LINKER_FLAGS="-Wl,--no-undefined" \
  -DCMAKE_INSTALL_PREFIX="$prefix" \
  -DKICAD_BUILD_QA_TESTS=OFF \
  -DKICAD_BUILD_I18N=OFF \
  -DKICAD_USE_SENTRY=OFF \
  -DKICAD_USE_PCH=OFF \
  -DKICAD_VERSION_EXTRA="bp.${fork_version##*-bp.}" \
  -DBACKPLANE_FORK_VERSION="$fork_version" \
  -DBACKPLANE_UPSTREAM_COMMIT="$(cat BACKPLANE_UPSTREAM)" \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  >/dev/null

say "compile (-j$JOBS; this takes a few hours the first time)"
cmake --build build/backplane-linux --parallel "$JOBS"

say "install"
cmake --install build/backplane-linux >/dev/null
ccache --show-stats | grep -E "Hits|Misses" || true

say "shared library path"
# The binaries carry no RPATH (upstream's release wraps each in a launcher
# that passes --library-path); register <prefix>/lib with the loader instead,
# so kicad-cli works however it is started (the hub, backplane-kipc, a shell).
echo "$prefix/lib" | sudo tee /etc/ld.so.conf.d/backplane-kicad.conf >/dev/null
sudo ldconfig
"$prefix/bin/kicad-cli" version

say "official libraries $LIB_TAG (from the $TAG release, checked against its SHA256SUMS)"
mkdir -p "$dl"
~/vm-guest/gh-asset.sh BackplaneWorks/Backplane_KiCad "$TAG" SHA256SUMS "$dl/SHA256SUMS"
for name in kicad-symbols kicad-footprints kicad-packages3D kicad-templates; do
  f=$name-$LIB_TAG-source.tar.gz
  if ! (cd "$dl" && grep " \*\?$f\$" SHA256SUMS | sed 's/ \*/  /' | sha256sum -c --status - >/dev/null 2>&1); then
    ~/vm-guest/gh-asset.sh BackplaneWorks/Backplane_KiCad "$TAG" "$f" "$dl/$f"
    (cd "$dl" && grep " \*\?$f\$" SHA256SUMS | sed 's/ \*/  /' | sha256sum -c -)
  fi
  rm -rf "$dl/$name" && mkdir -p "$dl/$name" && tar -xzf "$dl/$f" -C "$dl/$name"
done
share=$prefix/share/kicad
rm -rf "$share/symbols" "$share/footprints" "$share/3dmodels"
mkdir -p "$share/symbols" "$share/footprints" "$share/3dmodels" "$share/template"
find "$dl/kicad-symbols" -maxdepth 1 -type d -name '*.kicad_symdir' -exec mv {} "$share/symbols/" \;
find "$dl/kicad-footprints" -maxdepth 1 -type d -name '*.pretty' -exec mv {} "$share/footprints/" \;
find "$dl/kicad-packages3D" -maxdepth 1 -type d -name '*.3dshapes' -exec mv {} "$share/3dmodels/" \;
cp "$dl/kicad-symbols/sym-lib-table" "$share/template/sym-lib-table"
cp "$dl/kicad-footprints/fp-lib-table" "$share/template/fp-lib-table"
cp -a "$dl/kicad-templates/Projects/." "$share/template/"
find "$dl/kicad-templates/Worksheets" -type f -name '*.kicad_wks' -exec cp {} "$share/template/" \;
cat > "$share/sym-lib-table" <<'TABLE'
(sym_lib_table
  (version 7)
  (lib (name "KiCad")(type "Table")(uri "${KICAD10_TEMPLATE_DIR}/sym-lib-table")(options "")(descr "Official KiCad symbol libraries"))
)
TABLE
cat > "$share/fp-lib-table" <<'TABLE'
(fp_lib_table
  (version 7)
  (lib (name "KiCad")(type "Table")(uri "${KICAD10_TEMPLATE_DIR}/fp-lib-table")(options "")(descr "Official KiCad footprint libraries"))
)
TABLE
printf '(design_block_lib_table\n  (version 7)\n)\n' > "$share/design-block-lib-table"
test "$(find "$share/symbols" -name '*.kicad_sym' | wc -l)" -gt 0
test "$(find "$share/3dmodels" -type f -size +1k | wc -l)" -gt 0
rm -rf "$dl"/kicad-symbols "$dl"/kicad-footprints "$dl"/kicad-packages3D "$dl"/kicad-templates

say "runtime manifest"
git rev-parse HEAD > "$prefix/SOURCE_COMMIT"
cp BACKPLANE_UPSTREAM "$prefix/UPSTREAM_COMMIT"
rm -f "$prefix/manifest.json"
"$prefix/bin/kicad-cli" api-server --describe \
  | python3 -c 'import json,sys; m=json.load(sys.stdin); m["platform"]="linux-arm64"; print(json.dumps(m, indent=2))' \
  > "$prefix/manifest.json.new"
mv "$prefix/manifest.json.new" "$prefix/manifest.json"
cat "$prefix/manifest.json"

say "user library tables (as the fork's launcher does, only when absent)"
for cfg in 10.0 "$(echo "$fork_version" | cut -d. -f1-2)"; do
  d=~/.config/kicad/$cfg
  mkdir -p "$d"
  for t in sym-lib-table fp-lib-table design-block-lib-table; do
    [ -e "$d/$t" ] || cp "$share/$t" "$d/$t"
  done
done

say "point the hub at it"
env_file=~/.config/backplane/env
mkdir -p "$(dirname "$env_file")" && touch "$env_file"
grep -v '^BACKPLANE_KICAD=' "$env_file" > "$env_file.new" || true
echo "BACKPLANE_KICAD=$prefix" >> "$env_file.new"
mv "$env_file.new" "$env_file"
export XDG_RUNTIME_DIR=/run/user/$(id -u)
systemctl --user restart backplane-bend.service
sleep 3
systemctl --user --no-pager is-active backplane-bend.service

say "done: $prefix"

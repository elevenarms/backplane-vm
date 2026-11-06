#!/bin/sh
# gh-asset.sh OWNER/REPO TAG NAME OUT
# Downloads a GitHub release asset: the normal download URL first, then the
# REST asset endpoint (which keeps working when the download redirect 504s).
# Callers verify the checksum themselves.
set -eu
repo=$1 tag=$2 name=$3 out=$4
c="curl -fsSL --retry 3 --retry-all-errors --retry-delay 3"
$c -o "$out" "https://github.com/$repo/releases/download/$tag/$name" 2>/dev/null && exit 0
id=$($c "https://api.github.com/repos/$repo/releases/tags/$tag" | jq -r --arg n "$name" '.assets[] | select(.name == $n) | .id')
[ -n "$id" ] || { echo "gh-asset: $name not in $repo $tag" >&2; exit 1; }
$c -H 'Accept: application/octet-stream' -o "$out" "https://api.github.com/repos/$repo/releases/assets/$id"

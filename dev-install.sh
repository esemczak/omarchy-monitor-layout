#!/bin/bash
# Copy this checkout into the Omarchy user plugin directory for local testing.
# Omarchy rejects symlinked plugins, so a plain copy is the dev loop.
#
# The shell hot-reloads on every file change under the plugin directory, and
# reloading a half-copied plugin has crashed Quickshell, so stage the copy next
# to the destination and swap directories in one rename.

set -euo pipefail

src=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
id=$(jq -r '.id' "$src/manifest.json")
[[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $id != *..* ]] || { echo "invalid plugin id: $id" >&2; exit 1; }
plugins="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
dest="$plugins/$id"
stage=$(mktemp -d "$plugins/.$id.staging.XXXXXX")
trap 'rm -rf "$stage"' EXIT

rsync -a \
  --exclude '.git' --exclude 'docs' --exclude 'tests' --exclude 'tmp' \
  --exclude '.remember' --exclude 'node_modules' --exclude '*.md' \
  "$src/" "$stage/"

omarchy plugin validate "$stage"

if [[ -d $dest ]]; then
  old="$plugins/.$id.old.$$"
  mv "$dest" "$old"
  mv "$stage" "$dest"
  rm -rf "$old"
else
  mv "$stage" "$dest"
fi
trap - EXIT

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
echo "Installed $id to $dest"

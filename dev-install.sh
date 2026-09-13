#!/bin/bash
# Copy this checkout into the Omarchy user plugin directory for local testing.
# Omarchy rejects symlinked plugins, so a plain copy is the dev loop.

set -euo pipefail

src=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
id=$(jq -r '.id' "$src/manifest.json")
[[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $id != *..* ]] || { echo "invalid plugin id: $id" >&2; exit 1; }
dest="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$id"

mkdir -p "$dest"
rsync -a --delete \
  --exclude '.git' --exclude 'docs' --exclude 'tests' --exclude 'tmp' \
  --exclude '.remember' --exclude 'node_modules' --exclude '*.md' \
  "$src/" "$dest/"

omarchy plugin validate "$dest"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
echo "Installed $id to $dest"

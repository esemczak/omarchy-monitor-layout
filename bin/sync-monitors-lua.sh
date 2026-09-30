#!/bin/bash
# Persist the laptop scale into the stock lines of ~/.config/hypr/monitors.lua,
# the same lines omarchy-hyprland-monitor-scaling maintains, so GDK_SCALE and
# Omarchy's catch-all rule agree with the layout this plugin applies. Files
# without those lines (customised by hand) are left alone.
#   sync-monitors-lua.sh SCALE

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$script_dir/lib.sh"

scale="${1:-}"
[[ $scale =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "usage: sync-monitors-lua.sh SCALE" >&2; exit 1; }
awk -v s="$scale" 'BEGIN { exit !(s >= 1 && s <= 10) }' || { echo "scale out of range: $scale" >&2; exit 1; }

# GTK honours only integer GDK_SCALE values; Omarchy rounds the same way.
gdk_scale=$(awk -v s="$scale" 'BEGIN { printf "%d", int(s + 0.5) }')

if [[ -f $ml_monitors_lua ]]; then
  current=$(head -c "$ML_MAX_LUA_BYTES" -- "$ml_monitors_lua"; printf x)
  current=${current%x}
  updated=""
  if grep -q '^local omarchy_monitor_scale = ' <<<"$current"; then
    updated=$(sed -E \
      -e "s|^local omarchy_monitor_scale = .*|local omarchy_monitor_scale = ${scale}|" \
      -e "s|^local omarchy_gdk_scale = .*|local omarchy_gdk_scale = ${gdk_scale}|" <<<"$current")
  elif grep -Eq '^hl\.monitor\(\{ output = "", mode = "preferred", position = "auto", scale = ("auto"|[0-9.]+) \}\)' <<<"$current"; then
    updated=$(sed -E \
      -e "s|^(hl\.monitor\(\{ output = \"\", mode = \"preferred\", position = \"auto\", scale = )([^ ]+)( \}\))|\\1${scale}\\3|" \
      -e 's|^hl\.env\("GDK_SCALE", ".*"\)|hl.env("GDK_SCALE", "'"$gdk_scale"'")|' <<<"$current")
  fi
  # Write through symlinks (dotfile setups) and only when something changed,
  # so an unchanged file keeps its mtime and does not look like a rewrite.
  if [[ -n $updated && $updated != "${current%$'\n'}" ]]; then
    target=$(readlink -f -- "$ml_monitors_lua")
    printf '%s\n' "$updated" | ml_atomic_write "$target" "$(stat -c %a -- "$target")"
  fi
fi

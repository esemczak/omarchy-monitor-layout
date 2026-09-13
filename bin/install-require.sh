#!/bin/bash
# Make ~/.config/hypr/hyprland.lua load the generated monitor-layout.lua.
# Inserts the require directly after the monitors require so the plugin's
# specific monitor rules override the catch-all rule. Idempotent; backs up first.

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$script_dir/lib.sh"

if ml_require_installed; then
  echo "monitor-layout: require already present in $ml_hyprland_lua"
  exit 0
fi

[[ -f $ml_hyprland_lua ]] || {
  echo "monitor-layout: $ml_hyprland_lua not found" >&2
  exit 1
}

cp -p -- "$ml_hyprland_lua" "$ml_hyprland_lua.bak.$(date +%s)"

if grep -qxF -- "$ML_MONITORS_REQUIRE" "$ml_hyprland_lua"; then
  awk -v needle="$ML_MONITORS_REQUIRE" -v line="$ML_REQUIRE_LINE" '
    { print }
    !done && $0 == needle { print line; done = 1 }
  ' "$ml_hyprland_lua" | ml_atomic_write "$ml_hyprland_lua" 644
else
  {
    cat -- "$ml_hyprland_lua"
    printf '\n-- Generated monitor placement and workspace binding (esemczak.monitor-layout).\n%s\n' "$ML_REQUIRE_LINE"
  } | ml_atomic_write "$ml_hyprland_lua" 644
fi

echo "monitor-layout: added $ML_REQUIRE_LINE to $ml_hyprland_lua"

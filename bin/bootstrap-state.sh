#!/bin/bash
# Print everything the shell needs at startup as one JSON document:
# saved state text, current monitors, and whether Hyprland loads our Lua file.

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$script_dir/lib.sh"

state_raw=""
if [[ -f $ml_state_file && ! -L $ml_state_file ]]; then
  state_raw=$(head -c "$ML_MAX_STATE_BYTES" -- "$ml_state_file" 2>/dev/null || true)
fi

monitors=$(hyprctl monitors all -j 2>/dev/null || echo "[]")
jq -e 'type == "array"' >/dev/null <<<"$monitors" 2>/dev/null || monitors="[]"

require_installed=false
ml_require_installed && require_installed=true
lua_exists=false
[[ -f $ml_lua_file ]] && lua_exists=true

jq -cn \
  --arg state "$state_raw" \
  --argjson monitors "$monitors" \
  --argjson requireInstalled "$require_installed" \
  --argjson luaExists "$lua_exists" \
  '{state: $state, monitors: $monitors, requireInstalled: $requireInstalled, luaExists: $luaExists}'

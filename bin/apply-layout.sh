#!/bin/bash
# Write the generated Lua from stdin, reload Hyprland, and report as JSON:
#   {ok, requireInstalled, reloaded, errors: [...], message}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$script_dir/lib.sh"

report() {
  local ok="$1" reloaded="$2" message="$3"
  shift 3
  local require_installed=false
  ml_require_installed && require_installed=true
  jq -cn \
    --argjson ok "$ok" \
    --argjson requireInstalled "$require_installed" \
    --argjson reloaded "$reloaded" \
    --arg message "$message" \
    --args '{ok: $ok, requireInstalled: $requireInstalled, reloaded: $reloaded, message: $message, errors: $ARGS.positional}' -- "$@"
}

payload=$(ml_read_stdin_bounded "$ML_MAX_LUA_BYTES") || {
  report false false "Nothing to apply"
  exit 0
}
[[ $payload == "$ML_HEADER"* ]] || {
  report false false "Refusing to write unexpected content"
  exit 0
}

if [[ -L $ml_lua_file ]]; then
  report false false "$ml_lua_file is a symlink; refusing to write"
  exit 0
fi

printf '%s\n' "$payload" | ml_atomic_write "$ml_lua_file" 644 || {
  report false false "Could not write $ml_lua_file"
  exit 0
}

if ! ml_require_installed; then
  report true false "Saved, but hyprland.lua does not load it yet"
  exit 0
fi

if command -v omarchy-hyprland-reload-guard >/dev/null 2>&1 && omarchy-hyprland-reload-guard paused 2>/dev/null; then
  report true false "Saved; reload deferred while a system update runs"
  exit 0
fi

if ! hyprctl reload >/dev/null 2>&1; then
  report false false "hyprctl reload failed"
  exit 0
fi

mapfile -t errors < <(hyprctl configerrors 2>/dev/null | sed '/^[[:space:]]*$/d' | head -n 20)
if (( ${#errors[@]} )); then
  report false true "Hyprland reported config errors" "${errors[@]}"
  exit 0
fi

report true true "Applied"

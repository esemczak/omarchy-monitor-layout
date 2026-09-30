#!/bin/bash
# Dim only the laptop backlight until stdin closes, restoring its exact value.
# The guard is a grandchild: Quickshell tracks/kills the launcher, while the
# guard survives long enough to restore on EOF even if that launcher is killed.
if [[ ${1:-} != --guard ]]; then
  bash "$0" --guard "${1:-0}" <&0 &
  guard_pid=$!
  stop_guard() {
    trap - TERM INT HUP
    kill -TERM "$guard_pid" 2>/dev/null || true
    wait "$guard_pid" 2>/dev/null || true
    exit 0
  }
  trap stop_guard TERM INT HUP
  wait "$guard_pid"
  exit "$?"
fi

set -euo pipefail
valid_percent() { [[ $1 =~ ^[0-9]{1,3}$ ]] && (( 10#$1 <= 100 )); }
level=${2:-0}
valid_percent "$level" || exit 1
device=$(omarchy-hw-display) || exit 1
[[ $device =~ ^[A-Za-z0-9_.:-]+$ ]] || exit 1
[[ -n ${XDG_RUNTIME_DIR:-} && -d $XDG_RUNTIME_DIR ]] || exit 1
exec 9>"$XDG_RUNTIME_DIR/omarchy-monitor-layout-brightness.lock"
flock -n 9 || exit 1

previous=$(brightnessctl --class=backlight --device="$device" get) || exit 1
[[ $previous =~ ^[0-9]+$ ]] || exit 1
maximum=$(brightnessctl --class=backlight --device="$device" max) || exit 1
[[ $maximum =~ ^[0-9]+$ ]] || exit 1
previous=$((10#$previous))
maximum=$((10#$maximum))
(( maximum > 0 )) || exit 1

restore() {
  brightnessctl --class=backlight --device="$device" --min-value=0 set "$previous" >/dev/null || {
    echo "monitor-layout: could not restore laptop brightness" >&2
    return 1
  }
}
trap restore EXIT
trap 'exit 0' TERM INT HUP

# Percentage of the hardware maximum, rounded to the nearest raw step. A zero
# preference means the lowest nonzero step. Dimming never brightens the panel.
apply_level() {
  valid_percent "$1" || return 1
  local percent target
  percent=$((10#$1))
  target=$(((maximum * percent + 50) / 100))
  (( target >= 1 )) || target=1
  (( target <= previous )) || target=$previous
  brightnessctl --class=backlight --device="$device" --min-value=0 set "$target" >/dev/null
}
apply_level "$level" || exit 1
printf 'dimmed\n'
while IFS= read -r message; do
  case $message in
    restore) break ;;
    level:*) apply_level "${message#level:}" || true ;;
  esac
done

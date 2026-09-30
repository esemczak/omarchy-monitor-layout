#!/bin/bash
# omarchy-hyprland-monitor-scaling appends "at=...\tnew=...\tmonitor=..." to an
# audit log for every scale change it makes. Print the last entry, the log's
# mtime and age, and the current plugin state text as one JSON document:
#   {logMtime, age, scaling: {at, monitor, scale} | null, state}
# The state comes along so the shell can adopt onto what is on disk rather
# than a possibly stale in-memory copy (one Service instance runs per bar).

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$script_dir/lib.sh"

log_mtime=0
age=0
scaling=null
if [[ -f $ml_scaling_log ]]; then
  log_mtime=$(stat -L -c %.Y -- "$ml_scaling_log" 2>/dev/null || echo 0)
  age=$(awk -v now="$(date +%s.%N)" -v m="$log_mtime" 'BEGIN { printf "%.3f", now - m }')
  last=$(tail -n 1 -- "$ml_scaling_log" 2>/dev/null || true)
  at_raw=$(sed -n 's/^at=\([^\t]*\).*/\1/p' <<<"$last")
  monitor=$(sed -n 's/.*\tmonitor=\([A-Za-z0-9._-]*\).*/\1/p' <<<"$last")
  new_scale=$(sed -n 's/.*\tnew=\([0-9.]*\).*/\1/p' <<<"$last")
  at=$(date -d "$at_raw" +%s 2>/dev/null || true)
  if [[ -n $at && -n $monitor && $new_scale =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    scaling=$(jq -cn --argjson at "$at" --arg monitor "$monitor" --argjson scale "$new_scale" \
      '{at: $at, monitor: $monitor, scale: $scale}')
  fi
fi

state_raw=""
if [[ -f $ml_state_file && ! -L $ml_state_file ]]; then
  state_raw=$(head -c "$ML_MAX_STATE_BYTES" -- "$ml_state_file" 2>/dev/null || true)
fi

jq -cn --argjson logMtime "$log_mtime" --argjson age "$age" --argjson scaling "$scaling" --arg state "$state_raw" \
  '{logMtime: $logMtime, age: $age, scaling: $scaling, state: $state}'

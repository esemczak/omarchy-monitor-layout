#!/bin/bash
# Write plugin state JSON from stdin to the Omarchy settings directory.

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$script_dir/lib.sh"

payload=$(ml_read_stdin_bounded "$ML_MAX_STATE_BYTES") || {
  echo "monitor-layout: state payload empty or too large" >&2
  exit 1
}
jq -e . >/dev/null <<<"$payload" || {
  echo "monitor-layout: state payload is not valid JSON" >&2
  exit 1
}
printf '%s\n' "$payload" | ml_atomic_write "$ml_state_file" 600 700

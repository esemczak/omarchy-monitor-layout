#!/bin/bash
# Exercise the real installer with a fake shell host; no desktop changes.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/config/omarchy/plugins/esemczak.monitor-layout"
printf 'old\n' > "$scratch/config/omarchy/plugins/esemczak.monitor-layout/marker"
export TEST_INSTALL_ROOT="$scratch"
export XDG_CONFIG_HOME="$scratch/config" OMARCHY_PATH=/usr/share/omarchy
export PATH="$scratch/bin:$PATH"
cat > "$scratch/bin/omarchy" <<'SH'
#!/bin/bash
set -eu
if [[ $1 == plugin && $2 == validate ]]; then
  case $3 in
    "$XDG_CONFIG_HOME/omarchy/plugins/"*) echo 'staging is in watched plugin tree' >&2; exit 1 ;;
  esac
  touch "$TEST_INSTALL_ROOT/validated"
elif [[ $1 == restart && $2 == shell ]]; then
  [[ -f $TEST_INSTALL_ROOT/stopped ]]
  [[ -f $XDG_CONFIG_HOME/omarchy/plugins/esemczak.monitor-layout/LaptopScreensaver.qml ]]
  touch "$TEST_INSTALL_ROOT/restarted"
fi
SH
cat > "$scratch/bin/omarchy-shell" <<'SH'
#!/bin/bash
[[ ! -f $TEST_INSTALL_ROOT/stopped ]]
SH
cat > "$scratch/bin/omarchy-hyprland-session-locked" <<'SH'
#!/bin/bash
[[ -f $TEST_INSTALL_ROOT/locked ]]
SH
cat > "$scratch/bin/quickshell" <<'SH'
#!/bin/bash
set -eu
[[ ! -f $TEST_INSTALL_ROOT/stopped ]] || exit 1
[[ -f $TEST_INSTALL_ROOT/validated ]]
[[ -f $XDG_CONFIG_HOME/omarchy/plugins/esemczak.monitor-layout/marker ]]
touch "$TEST_INSTALL_ROOT/stopped"
SH
chmod +x "$scratch/bin/"*
bash "$repo/dev-install.sh"
[[ -f $scratch/restarted ]]
[[ ! -f $scratch/config/omarchy/plugins/esemczak.monitor-layout/marker ]]
echo 'ok   validate outside watched tree, stop before replacement, restart after replacement'

rm -f "$scratch/stopped" "$scratch/restarted"
touch "$scratch/locked"
printf 'locked-marker\n' > "$scratch/config/omarchy/plugins/esemczak.monitor-layout/marker"
if bash "$repo/dev-install.sh" > /dev/null 2>&1; then
  echo 'FAIL installer should refuse a locked session' >&2
  exit 1
fi
[[ ! -f $scratch/stopped ]]
[[ -f $scratch/config/omarchy/plugins/esemczak.monitor-layout/marker ]]
echo 'ok   locked session leaves running shell and plugin untouched'

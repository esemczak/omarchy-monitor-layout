# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- Optional laptop-only screensaver with a compact full-month calendar on the left, today highlighted, and a large clock with weather beneath it on the right. It drifts slowly while an external display is connected, dismisses on laptop pointer/focus activity, returns after 15 seconds away, and stops on disconnect without taking keyboard focus or inhibiting the normal lock.
- Screensaver temperature and wind from the standard `omarchy weather status` command, using Omarchy's configured weather location.
- Configurable screensaver brightness percentage, saved in the panel, with minimum brightness as the default. Dimming never brightens the laptop; dismissal or shutdown restores the exact previous value, with a separate restoration guard for shell crashes.

### Fixed

- Development installation stages outside the watched plugin tree and stops the live shell before replacing files, avoiding the plugin hot-reload path associated with Quickshell crashes. Locked sessions are left untouched.

- Scale changes made through Omarchy's Display panel or `omarchy hyprland monitor scaling` no longer bounce back. The generated per-output rules overrode the catch-all rule that tool persists to `monitors.lua`, and the reload it triggers undid its live change. The plugin now watches that tool's audit log, adopts each change into the profile for the monitor it names, and regenerates the layout, also while the external monitor is unplugged.

### Changed

- Apply also persists the laptop scale into the stock scale lines of `monitors.lua`, so `GDK_SCALE` and Omarchy's catch-all rule follow the layout.
- Profiles remember the external monitor's geometry on apply so the layout can be regenerated without it connected; older profiles pick this up on the next hotplug.
- The state file records the audit-log mtime of the last handled scale change.

## [0.1.0] - 2026-09-13

### Added

- Bar widget and panel for placing one external monitor relative to the laptop panel by side and physical alignment, with a to-scale preview and cursor-crossing range in millimetres
- Per-workspace binding to the external or laptop monitor, optionally persistent
- One saved profile per external monitor, keyed by description, regenerated automatically when a different saved monitor is connected
- Generated `~/.config/hypr/monitor-layout.lua` with `hl.monitor` and `hl.workspace_rule` calls; one-click install of the require line into `hyprland.lua`
- IPC surface for scripts and keybindings
- Unit tests for layout math and Lua rendering, shell tests for the helper scripts

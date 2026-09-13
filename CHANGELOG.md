# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2026-09-13

### Added

- Bar widget and panel for placing one external monitor relative to the laptop panel by side and physical alignment, with a to-scale preview and cursor-crossing range in millimetres
- Per-workspace binding to the external or laptop monitor, optionally persistent
- One saved profile per external monitor, keyed by description, regenerated automatically when a different saved monitor is connected
- Generated `~/.config/hypr/monitor-layout.lua` with `hl.monitor` and `hl.workspace_rule` calls; one-click install of the require line into `hyprland.lua`
- IPC surface for scripts and keybindings
- Unit tests for layout math and Lua rendering, shell tests for the helper scripts

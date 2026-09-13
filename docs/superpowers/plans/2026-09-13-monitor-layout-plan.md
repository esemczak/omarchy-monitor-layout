# Monitor layout plugin — implementation plan

Spec: `docs/superpowers/specs/2026-09-13-monitor-layout-design.md`.
Each task is test-first where a test is practical, ends with a commit.

## Task 1 — Repo scaffold
manifest.json, LICENSE (MIT), .gitignore, README skeleton, CHANGELOG, dev-install.sh.
Verify: `omarchy plugin validate .` passes once Panel.qml exists (Task 5).

## Task 2 — Model.js: identity, state, layout math
Tests in `tests/model.test.js` (node --test):
- `classifyMonitors(list)` → {internal, external} from hyprctl JSON.
- `defaultState()`, `parseState(text)` tolerant of garbage, `serializeState()`.
- `profileFor(state, key)` returns stored or default profile.
- `computeLayout(profile, internal, external)` → positions for every side and
  alignment, normalised to non-negative, plus shared-edge overlap in mm.

## Task 3 — Model.js: Lua rendering
- `luaString(s)` escaping; `renderLua(profile, internal, external)` output
  matches expected text; empty profile renders header only.

## Task 4 — Shell scripts + bash test
- `bin/safe-write-state.sh`, `bin/bootstrap-state.sh`, `bin/apply-layout.sh`,
  `bin/install-require.sh`.
- `tests/apply-layout.test.sh` with fake hyprctl and temp HOME: file written,
  require detection, error propagation, install idempotency.

## Task 5 — Service.qml + Panel.qml
- Service: bootstrap load, monitor refresh on Hyprland events, save, apply,
  auto-apply on hotplug.
- Panel: hero, arrangement, preview, workspaces, footer, keyboard nav.
- Verify: dev-install, `omarchy plugin validate`, enable, open via IPC,
  check shell log for QML errors, screenshot.

## Task 6 — Docs and polish
README with install, usage, limitations; CHANGELOG 0.1.0; final commit.

# omarchy-monitor-layout

Place an external monitor next to your laptop **in physical terms** and bind
workspaces to monitors **permanently**, from a panel in the Omarchy bar.

![Monitor layout panel](docs/screenshots/panel.png)

Tell the plugin which side of the laptop the external display sits on and how
the two are aligned on the desk (top edges, centres, bottom edges, or a custom
millimetre offset). It converts that into Hyprland monitor positions so the
cursor leaves one screen and arrives on the other where you expect. Then click
workspaces 1 to 10 to say which monitor each one lives on.

Layouts are saved per external monitor (keyed by its EDID description), so the
Studio Display at home and the projector at work each keep their own settings,
and Hyprland re-applies them on its own the moment the monitor is plugged in.

## Features

- **Side and alignment** — left / right / above / below, aligned by leading
  edge, centre, trailing edge, or a custom offset in millimetres
- **To-scale preview** — both panels drawn from their physical size, with the
  shared edge where the cursor can cross highlighted and quoted in millimetres
- **Per-monitor scale** — the generated rules carry the scale you choose
- **Workspace binding** — cycle each workspace between external, laptop, and
  any; optionally persistent so bound workspaces always exist on their monitor
- **One profile per external monitor**, applied automatically on hotplug
- **Bar shortcuts** — left-click opens the panel, right-click re-applies
- **IPC** for keybindings and scripts (see below)

## Requirements

- [Omarchy](https://omarchy.org) 4.x with Hyprland configured in Lua
- `bash`, `jq`, `hyprctl` (all present on a stock Omarchy install)

No sudo, no network access, no extra packages.

## Install

```bash
omarchy plugin add https://github.com/esemczak/omarchy-monitor-layout.git --enable --yes
omarchy restart shell
```

The widget appears in the left bar section right after the workspace numbers.
Move it with `omarchy bar move esemczak.monitor-layout --section right` if you
prefer it elsewhere.

Then open the panel and press **Install into hyprland.lua**. That adds one
line to `~/.config/hypr/hyprland.lua` right after the monitors require, after
saving a timestamped backup:

```lua
require("hypr.monitor-layout")
```

You can add the line yourself instead. It must come after
`require("hypr.monitors")` so the plugin's specific monitor rules override
Omarchy's catch-all rule.

### Manual copy

```bash
git clone https://github.com/esemczak/omarchy-monitor-layout.git \
  ~/.config/omarchy/plugins/esemczak.monitor-layout
omarchy plugin validate ~/.config/omarchy/plugins/esemczak.monitor-layout
omarchy plugin enable esemczak.monitor-layout left
omarchy restart shell
```

## Usage

1. Connect the external monitor and click the bar icon.
2. Pick the side it is on and how it lines up with the laptop.
3. Click workspace numbers to assign them. A monitor glyph means external, a
   laptop glyph means laptop, no glyph means unassigned.
4. Press **Apply layout**. Hyprland reloads and the footer reports the result.

Keyboard: `j`/`k` move between rows, `h`/`l` within a row, `Enter` activates,
`a` applies, `r` refreshes monitors, `Esc` closes.

## How it works

The plugin writes `~/.config/hypr/monitor-layout.lua`, for example:

```lua
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 2 })
hl.monitor({ output = "desc:Apple Computer Inc StudioDisplay 0xB65A586D", mode = "preferred", position = "1440x0", scale = 2 })

hl.workspace_rule({ workspace = "1", monitor = "desc:Apple Computer Inc StudioDisplay 0xB65A586D", persistent = true })
hl.workspace_rule({ workspace = "5", monitor = "eDP-1", persistent = true })
```

The external monitor is matched by description, so the rules survive a change
of port. Because they live in Hyprland config, Hyprland applies them itself
when the monitor appears, with no daemon in between. When a *different* saved
monitor is connected the plugin regenerates the file for that profile.

Settings live in `~/.local/state/omarchy/settings/monitor-layout.json`.

### Laptop screensaver

Enable **Laptop screensaver when connected** in the panel to show a slowly
moving clock and full-month calendar with today highlighted on a dark
laptop screen while you work on an external display. This option is saved
globally and defaults to off; it takes effect
without clicking Apply.

A compact calendar sits on the left, with the large clock on the right and
weather underneath it. The entire arrangement drifts slowly across the screen.

Set **Screensaver brightness (%)** in the plugin panel to choose the dim level
from 0–100%. It saves immediately. The default, 0%, uses the lowest nonzero
hardware value. Dimming never increases brightness above the original level.
Its exact previous brightness is restored on dismissal,
disconnect, disabling the option, or shell shutdown. A separate guard also
restores after the shell or its tracked brightness launcher dies. External
display brightness is unaffected. If backlight control is unavailable, the
overlay continues without dimming.

Temperature and wind use `omarchy weather status`, sharing the standard
weather plugin's configured location. The screensaver refreshes this every
15 minutes while visible and when the configured location changes. Weather
is omitted when the command is unavailable or the request fails.

The overlay appears after the pointer and keyboard focus have both been away
from the laptop for 15 seconds. Moving the pointer onto the laptop, focusing a
laptop window, or opening the plugin panel dismisses it. It returns after
another 15 seconds away. Disconnecting the last active external display stops
it immediately; reconnecting starts the same delay.

The external display stays usable. The overlay does not take keyboard focus,
hide the cursor globally, or prevent the normal system lock and display sleep.
It is a visual screensaver, not a lock screen or display power control.

### Physical alignment

Millimetre offsets are converted to logical pixels using the laptop panel's
pixel density. The two displays almost always have different densities, so the
alignment is exact at the anchor you chose and drifts slightly along the rest
of the edge. The preview quotes the crossing range on both monitors so you can
see the difference. This is inherent to how Hyprland routes the cursor across
rectangular logical outputs, not something the plugin can fully remove.

### Scale

The generated rules set an explicit scale for both monitors, which would
otherwise override the catch-all rule that Omarchy's own Display panel (and
the `omarchy hyprland monitor scaling` keybinds) persist to `monitors.lua`,
and the reload that write triggers would undo their live change. To keep that
panel working, the plugin watches the audit log that tool appends to
(`~/.local/state/omarchy/monitor-scaling.log`): each new entry names the
monitor and scale, which the plugin adopts into the current profile before
regenerating the layout. Expect a brief flicker while Hyprland reloads twice.

Apply goes the other way too: it writes the laptop scale into the stock
`omarchy_monitor_scale` / `omarchy_gdk_scale` lines of `monitors.lua` (only
if those lines are present), so `GDK_SCALE` and the catch-all rule agree with
the layout. A hand-customised `monitors.lua` is left alone.

This also works with the external monitor unplugged: the profile remembers
its geometry from the last apply. Profiles saved before this was recorded fall
back to a laptop-only rule and regain the full layout the next time the
monitor is connected.

## IPC

```bash
omarchy-shell esemczak.monitor-layout open|close|toggle
omarchy-shell esemczak.monitor-layout apply
omarchy-shell esemczak.monitor-layout install
omarchy-shell esemczak.monitor-layout setSide left|right|above|below
omarchy-shell esemczak.monitor-layout setAlign start|center|end|custom
omarchy-shell esemczak.monitor-layout setOffset 40
omarchy-shell esemczak.monitor-layout setWorkspace 3 external|internal|none
omarchy-shell esemczak.monitor-layout lua      # print the Lua that would be applied
omarchy-shell esemczak.monitor-layout status   # JSON
omarchy-shell esemczak.monitor-layout setScreensaver true|false
omarchy-shell esemczak.monitor-layout setScreensaverBrightness 5
```

## Remove

```bash
omarchy plugin disable esemczak.monitor-layout
omarchy plugin remove esemczak.monitor-layout --yes
omarchy restart shell
```

Then delete the require line from `~/.config/hypr/hyprland.lua` and remove
`~/.config/hypr/monitor-layout.lua`. Optionally delete the saved settings:

```bash
rm -f ~/.local/state/omarchy/settings/monitor-layout.json
```

## Development

```bash
node --test tests/               # pure layout, state and Lua rendering tests
bash tests/apply-layout.test.sh  # shell helpers against a temp HOME and fake hyprctl
bash tests/dev-install.test.sh   # safe deployment sequence against a fake shell host
./dev-install.sh                 # validate, stop live shell, install, restart shell
```

Live plugin reloads have crashed Quickshell during development. The installer
stages outside the watched plugin tree and stops the running shell before
replacing files, then restarts it. It refuses to stop a locked session. No
additional restart is needed after installation.

## License

MIT

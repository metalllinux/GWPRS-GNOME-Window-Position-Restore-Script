# window-restore

`window-restore` is a Bash utility for GNOME on X11 that continuously tracks the on-screen position
of every open window and restores those positions automatically when it detects that your monitor
configuration has changed, for example after a laptop sleeps and wakes with an external display
reconnected.

It exists to work around a long-standing GNOME/X11 bug where windows land on the wrong monitor after
the screen unlocks or a display reconnects. The issue was originally observed on Rocky Linux 8.10
running GNOME on X11, on a dual-monitor desktop with an NVIDIA RTX A2000 GPU driving two Dell
P2715Q monitors.

## The bug this works around

Two related GNOME GitLab issues describe this symptom. Their current states, checked live against the
GitLab API, are not the same, and this README states each accurately rather than assuming both are
still open.

[gnome-shell#5684](https://gitlab.gnome.org/GNOME/gnome-shell/-/issues/5684), "After screen lock,
windows are shown on wrong screen", is open. It was filed 2022-07-24 and has never been closed. This
is the X11-side report and the one `window-restore` actually addresses.

[mutter#1419](https://gitlab.gnome.org/GNOME/mutter/-/issues/1419), "Windows switch monitor after
resuming from sleep", is closed. It was closed 2024-01-04 by `bilelmoussaoui`, with no merge request
linked and no closing reason recorded that is visible without a GitLab login. This report was filed
against Wayland (Fedora 32, Mutter 3.36.5), so it describes a related symptom on a different display
stack than the one this script targets. `window-restore` is X11-only and cannot act on a Wayland-side
issue regardless of its state.

## Requirements

`window-restore` needs GNOME running on X11, plus two command-line tools it calls directly:

- `wmctrl`, for reading and moving window positions (GPL-2.0-or-later)
- `xrandr`, for reading monitor geometry, shipped in the `xorg-x11-server-utils` package, not
  `xorg-x11-utils` (MIT)

`install.sh` also installs `xdotool` (BSD-3-Clause). `window-restore` itself never calls `xdotool`;
it is included because it is the standard tool for scripting X11 window actions and is useful for
anyone testing or automating window placement on the same machine. None of these three tools are
bundled with this repository. They are ordinary system packages, installed through your package
manager and invoked at arm's length as separate processes.

## Install

Run the installer as root from a checkout containing both `window-restore` and `install.sh`, since it
copies its sibling file:

```bash
sudo ./install.sh
```

The installer does the following, in order:

1. Checks for `wmctrl`, `xrandr`, and `xdotool` independently and installs whichever are missing via
   `dnf install`.
2. Installs the script to `/usr/local/bin/window-restore` with mode 755.
3. Creates a system-wide XDG autostart entry at `/etc/xdg/autostart/window-restore.desktop`, so
   `window-restore monitor` starts automatically, ten seconds after login, at every GNOME/X11 session
   for every account (`OnlyShowIn=GNOME;`).
4. Copies that autostart entry to `/etc/skel/.config/autostart/`, so any account created after this
   point gets it automatically too.
5. Copies the same autostart entry into `~/.config/autostart/` for every existing account under
   `/home/*`, and fixes its ownership. An account whose `.config` or `.config/autostart` is already
   a symlink is skipped, with a warning, rather than followed.
6. Stops any `window-restore monitor` process already running, so a re-run of the installer picks up
   cleanly.

Re-running `install.sh` is safe. Every step it takes either overwrites in place or is a no-op if
already done.

## Usage

Every save and restore file this script creates is private to your own account (see Files below), so
no special setup is needed beyond the install steps above.

Save the current position of every open window:

```bash
window-restore save
```

This writes `~/.window-positions` and prints a line per window, for example `SAVED [LEFT]: Terminal
at x=100`.

Restore windows to their last saved positions:

```bash
window-restore restore
```

This looks up each saved window by its window ID first, then falls back to matching on the saved
title if that ID is no longer open, for example because the window was closed and reopened since the
last save. Matching by ID first means two windows that share the same title, for example two terminal
windows both titled "Terminal", each return to their own saved position rather than one clobbering
the other.

Run continuously in the foreground, auto-saving every 30 seconds and watching for monitor changes
every 5 seconds:

```bash
window-restore monitor
```

Run it in the background instead, the way the installer's autostart entry does:

```bash
window-restore monitor &
```

Check whether the monitor loop is running, how many positions are saved, and where the log file is:

```bash
window-restore status
```

Print the current window layout, the current monitor configuration, and the saved positions side by
side, useful when a restore did not do what you expected:

```bash
window-restore debug
```

Print usage and exit successfully:

```bash
window-restore help
window-restore --help
window-restore -h
```

Running the script with no argument, or with an argument it does not recognize, also prints usage,
but exits with a non-zero status. Only `help`/`--help`/`-h` exit 0.

## How monitor-side classification works

`window-restore` reads the connected monitors' geometry from `xrandr --query` each time it needs to
decide which side of your desktop a window is on, rather than assuming a fixed screen resolution. A
window is classified LEFT or RIGHT of the boundary between your monitors.

It is designed for two monitors placed side by side, extended rather than mirrored, and works well
for that layout. Two situations fall outside that design and are worth knowing about:

- With three or more connected monitors, only the leftmost one is classified LEFT. Everything else,
  regardless of how many additional monitors there are or where they sit, is classified RIGHT.
  This is not full multi-monitor awareness, only a two-way split.
- With two monitors mirroring or cloning the same image (identical geometry, same offset), every
  window classifies RIGHT instead of LEFT, since the boundary calculation resolves to the same
  coordinate shared by both.

The automatic restore that runs while `monitor` is active is also one-directional by design. It only
restores a window that was saved on the RIGHT monitor and is later found to have drifted to the LEFT.
A window saved on the LEFT that later ends up on the RIGHT is not auto-restored, though running
`window-restore restore` by hand still moves every saved window back regardless of direction.

## X11 only

`window-restore` depends on `wmctrl` and `xrandr`, and GNOME on Wayland does not expose the
window-geometry and monitor-query interfaces those tools need. Wayland is not supported. At the GDM
login screen, select "Standard (X11 display server)" before logging in.

## Files

`window-restore` creates these files, each private to the account that ran it (mode 600), since saved
and logged window titles routinely include document names and URLs:

- `~/.window-positions`, the saved window positions
- `/tmp/window-restore-<user>.log`, a running log of what the script has done
- `/tmp/window-restore-monitors-<user>`, the last-seen monitor configuration, used to detect a change

## License

window-restore is released under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the full text.

Copyright (c) 2026, Ctrl IQ, Inc. All rights reserved.

```text
Copyright © 2026 Ctrl IQ, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at:

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

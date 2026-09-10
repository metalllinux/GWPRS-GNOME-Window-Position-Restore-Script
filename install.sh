#!/bin/bash
#
# install.sh - installs window-restore system-wide
#
# Run as root: sudo ./install.sh
#
# Installs /usr/local/bin/window-restore, a system-wide XDG autostart
# entry so it starts in `monitor` mode at every GNOME/X11 login, and a
# copy of that autostart entry in /etc/skel so new accounts get it too.

set -e

echo "Installing Window Restore System-wide..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)"
    exit 1
fi

# Check for required packages, per binary rather than gated on a single
# `command -v wmctrl`. Checking only wmctrl was the original bug here:
# on a machine where wmctrl already happened to be installed, nothing
# else got installed either, xrandr included, and window-restore's
# monitor-wake detection then fails silently (monitor_count stays 0,
# with no error anywhere) because xrandr --query never runs at all.
#
# xdotool is not called anywhere in window-restore itself. It's kept in
# the install list because xdotool is the standard tool for scripting
# X11 window actions (move, resize, activate), which is useful for
# anyone testing or automating window placement on this machine, so
# it's already available without a separate install step.
echo "Checking dependencies..."
missing_pkgs=()
command -v wmctrl >/dev/null 2>&1 || missing_pkgs+=(wmctrl)
command -v xrandr >/dev/null 2>&1 || missing_pkgs+=(xorg-x11-server-utils)
command -v xdotool >/dev/null 2>&1 || missing_pkgs+=(xdotool)
if [ "${#missing_pkgs[@]}" -gt 0 ]; then
    echo "Installing required packages: ${missing_pkgs[*]}"
    dnf install -y "${missing_pkgs[@]}"
fi

# 1. Install the main script
echo "Installing script to /usr/local/bin..."
install -m 755 "$(dirname "$0")/window-restore" /usr/local/bin/window-restore

# 2. Create system-wide autostart
echo "Creating system-wide autostart..."
mkdir -p /etc/xdg/autostart

cat > /etc/xdg/autostart/window-restore.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Window Position Restore Monitor
Comment=Automatically restore window positions after monitor wake
Exec=/usr/local/bin/window-restore monitor
Icon=view-restore
Terminal=false
Hidden=false
NoDisplay=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=10
Categories=System;Utility;
OnlyShowIn=GNOME;
EOF

chmod 644 /etc/xdg/autostart/window-restore.desktop

# 3. Create template for new users
echo "Setting up template for new users..."
mkdir -p /etc/skel/.config/autostart
cp /etc/xdg/autostart/window-restore.desktop /etc/skel/.config/autostart/

# 4. Setup for existing users
#
# This loop runs as root and, for every existing account, creates a
# directory and writes/chowns a file under that account's home
# directory. Neither `mkdir -p` nor `cp`/`chown` refuses to traverse an
# existing symlink at any path component (CWE-59): a local user who
# replaces their own ~/.config (or ~/.config/autostart) with a symlink
# before an admin runs, or re-runs, this installer would otherwise have
# root's mkdir/cp/chown operate on whatever that symlink points at
# instead of that user's actual home directory. Refuse and skip rather
# than follow whenever either path is already a symlink -- checked both
# before creating the directory and again immediately after, since
# `mkdir -p` silently succeeds through an already-existing directory
# without telling us whether a symlink was swapped in since the first
# check.
echo "Setting up for existing users..."
for user_home in /home/*; do
    if [ -d "$user_home" ]; then
        username=$(basename "$user_home")

        # Skip if not a real user
        if ! id "$username" &>/dev/null; then
            continue
        fi

        echo "  Setting up for user: $username"

        autostart_dir="$user_home/.config/autostart"

        if [ -L "$user_home/.config" ] || [ -L "$autostart_dir" ]; then
            echo "  WARNING: $username's .config or .config/autostart is a symlink; skipping to avoid following it" >&2
            continue
        fi

        # Create autostart directory
        mkdir -p "$autostart_dir"

        if [ -L "$autostart_dir" ] || [ ! -d "$autostart_dir" ]; then
            echo "  WARNING: $autostart_dir is not a plain directory after setup; skipping $username" >&2
            continue
        fi

        # Copy desktop file
        cp "/etc/xdg/autostart/window-restore.desktop" "$autostart_dir/"

        # Fix ownership
        chown -R "$username:$username" "$autostart_dir/window-restore.desktop"
    fi
done

# 5. Kill any existing monitors
pkill -f 'window-restore monitor' 2>/dev/null || true

echo ""
echo "==============================================="
echo "Window Restore Installed Successfully!"
echo "==============================================="
echo ""
echo "Installation complete:"
echo "  - Main script: /usr/local/bin/window-restore"
echo "  - Autostart: /etc/xdg/autostart/window-restore.desktop"
echo "  - New users: /etc/skel/.config/autostart/"
echo ""
echo "IMPORTANT: Requires X11 (not Wayland)"
echo ""
echo "To start monitoring now: window-restore monitor &"
echo "To debug issues: window-restore debug"
echo ""

#!/bin/sh
set -e

# plasma-setup is launched via the XDG autostart .desktop entry shipped
# in its own package, not via systemd --user dbus-activation like
# plasmashell/krunner/etc, so it never receives the corrected
# WAYLAND_DISPLAY that KUpdateLaunchEnvironmentJob exports into the
# systemd user manager's environment after kwin picks its socket name.
# run-after.sh's own WAYLAND_DISPLAY fallback (hardcoded to "wayland-0")
# is also unreliable here: if kwin_wayland has restarted even once this
# session (observed in testing, e.g. after an unrelated crash) it picks
# the next free display name (wayland-1, wayland-2, ...), permanently
# invalidating that guess. Discover the real, currently-live socket name
# under $XDG_RUNTIME_DIR instead of assuming one.
WAITFORNAME_TIMEOUT=${PLASMA_WAITFORNAME_TIMEOUT:-60}
$SNAP/plasma/usr/bin/plasma_waitforname --timeout "$WAITFORNAME_TIMEOUT" org.kde.KWin

i=0
found=""
while [ "$i" -lt 150 ]; do
  for sock in "${XDG_RUNTIME_DIR}"/wayland-*; do
    case "$sock" in
      *'*') ;;
      *.lock) ;;
      *) [ -S "$sock" ] && found="${sock##*/}" && break ;;
    esac
  done
  [ -n "$found" ] && break
  sleep 0.1
  i=$((i + 1))
done
export WAYLAND_DISPLAY="${found:-wayland-0}"

exec "$@"

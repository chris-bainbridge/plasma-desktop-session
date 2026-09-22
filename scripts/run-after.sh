#!/bin/sh
set -e

export PULSE_SERVER=unix:/run/user/`id -u`/pulse/native
export PIPEWIRE_RUNTIME_DIR=/run/user/`id -u`

SERVICE=$1
shift

WAITFORNAME_TIMEOUT=${PLASMA_WAITFORNAME_TIMEOUT:-60}
$SNAP/plasma/usr/bin/plasma_waitforname --timeout "$WAITFORNAME_TIMEOUT" "$SERVICE"

# Optional extra delay after the readiness name appears. plasmashell uses
# this: org.kde.KWin is claimed by kwin_wayland during workspace creation,
# but the compositor only starts processing Wayland client connections
# (and thus serving the PlasmaWindowManagement global) a few steps later
# in its startup. Without the delay plasmashell's task manager can request
# the global before the compositor's Wayland event loop is running and log
# "The PlasmaWindowManagement protocol hasn't activated in time".
if [ -n "${PLASMA_WAITFORNAME_EXTRA_DELAY:-}" ]; then
    sleep "$PLASMA_WAITFORNAME_EXTRA_DELAY"
fi

# kwin_wayland_wrapper creates the Wayland socket (named wayland-0 here, the
# first free slot) and exports WAYLAND_DISPLAY/DISPLAY/XAUTHORITY through
# KUpdateLaunchEnvironmentJob, which updates the *systemd user manager*
# environment. A daemon:simple app pulled in at default.target (e.g. the
# polkit auth agent) is spawned by `snap run` *before* that export lands and
# therefore inherits a stale environment missing WAYLAND_DISPLAY. Qt then
# falls back to the xcb platform plugin via DISPLAY, xcb_connect() to the
# not-yet-ready Xwayland fails, and the app crash-loops ("could not connect
# to display", "Could not load the Qt platform plugin \"xcb\"").
#
# We have just waited on $SERVICE (kwin is up, so its socket exists). Set
# WAYLAND_DISPLAY explicitly so Qt selects the wayland platform plugin
# instead of xcb. (The confined shell cannot read systemd's manager
# environment: `systemctl --user`/`busctl --user` are blocked by AppArmor, so
# we can't re-read KUpdateLaunchEnvironmentJob's result and instead use the
# fixed socket name the wrapper always picks.) Pick up Xauthority from the
# runtime dir as a fallback for any X11 path.
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    export WAYLAND_DISPLAY=wayland-0
fi
if [ -z "${XAUTHORITY:-}" ] && [ -d "${XDG_RUNTIME_DIR:-}" ]; then
    for f in "$XDG_RUNTIME_DIR"/xauth_*; do
        [ -e "$f" ] || continue
        export XAUTHORITY="$f"
        break
    done
fi

exec "$@"

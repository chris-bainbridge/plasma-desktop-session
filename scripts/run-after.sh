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

# org.kde.KWin being claimed also does NOT mean kwin has finished DRM output
# enumeration: that happens asynchronously afterwards. plasmashell's
# ScreenPool queries the (Wayland/Qt) screen list once at startup and never
# retries -- if it connects before kwin has published any wl_output, its
# screen count/geometry stay null/undefined FOREVER, so the whole desktop
# (panel, icons, wallpaper -- everything) never gets a first frame and stays
# black, even though kwin itself is compositing fine (confirmed live: a
# fixed sleep is not a reliable readiness signal here, since kwin's DRM
# init time varies with boot-time system load). Poll kwin's own
# supportInformation for a real enabled output instead of guessing a fixed
# delay; give up after a timeout and proceed anyway rather than hang the
# session forever if kwin genuinely never gets an output.
if [ -n "${PLASMA_WAIT_FOR_KWIN_OUTPUT:-}" ]; then
    timeout_iters=$(( ${PLASMA_WAIT_FOR_KWIN_OUTPUT_TIMEOUT:-15} * 5 ))
    i=0
    ready=0
    while [ "$i" -lt "$timeout_iters" ]; do
        if dbus-send --session --print-reply --dest=org.kde.KWin /KWin \
             org.kde.KWin.supportInformation 2>/dev/null \
             | grep -qE 'Number of Screens: [1-9]'; then
            ready=1
            break
        fi
        i=$((i + 1))
        sleep 0.2
    done
    if [ "$ready" -ne 1 ]; then
        echo "run-after.sh: timed out waiting for kwin to report an enabled output; starting $* anyway" >&2
    fi
fi

# kwin_wayland_wrapper exports WAYLAND_DISPLAY/DISPLAY/XAUTHORITY through
# KUpdateLaunchEnvironmentJob into the *systemd user manager* environment,
# but only after its compositor is up. Units started before that (e.g. the
# polkit auth agent, ksplash) inherit a stale environment: their first
# attempt dies in Qt platform-plugin init and succeeds when systemd restarts
# them once the export lands (delivered via systemd-user-control's
# UnsetAndSetEnvironment; the dedicated systemd-user-environment plug is the
# pending proper fix). No in-script fallback is possible: the confined shell
# cannot read the manager env (`systemctl --user`/`busctl --user` are
# AppArmor-blocked), and the old fixed WAYLAND_DISPLAY=wayland-0 export
# targeted a dead symlink (kwin's socket is wayland-1 inside the
# snap-private runtime dir).
# Pick up Xauthority from the runtime dir as a fallback for any X11 path.
if [ -z "${XAUTHORITY:-}" ] && [ -d "${XDG_RUNTIME_DIR:-}" ]; then
    for f in "$XDG_RUNTIME_DIR"/xauth_*; do
        [ -e "$f" ] || continue
        export XAUTHORITY="$f"
        break
    done
fi

exec "$@"

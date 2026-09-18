#!/bin/sh
set -e

export PULSE_SERVER=unix:/run/user/`id -u`/pulse/native
export PIPEWIRE_RUNTIME_DIR=/run/user/`id -u`

SESSION_SNAP=$SNAP
SERVICE=$1
shift

WAITFORNAME_TIMEOUT=${PLASMA_WAITFORNAME_TIMEOUT:-60}
$SESSION_SNAP/plasma/usr/bin/plasma_waitforname --timeout "$WAITFORNAME_TIMEOUT" "$SERVICE"

# This is necessary to avoid xdg-desktop-portal-kde have Qt try
# to load the xdg-desktop-portal platform theme plugin
# this would lead to an unfortunate situation where the portal
# backend would try to talk to itself for file dialogs and such...
unset SNAP

exec "$@"

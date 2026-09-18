#!/bin/sh
set -e

export PULSE_SERVER=unix:/run/user/`id -u`/pulse/native
export PIPEWIRE_RUNTIME_DIR=/run/user/`id -u`

SERVICE=$1
shift

WAITFORNAME_TIMEOUT=${PLASMA_WAITFORNAME_TIMEOUT:-60}
$SNAP/plasma/usr/bin/plasma_waitforname --timeout "$WAITFORNAME_TIMEOUT" "$SERVICE"
exec "$@"

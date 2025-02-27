#!/bin/sh
export PULSE_SERVER=unix:/run/user/`id -u`/pulse/native

SERVICE=$1
shift
$SNAP/plasma/usr/bin/plasma_waitforname --timeout 20 $SERVICE
exec "$@"

#!/bin/sh
unset DISPLAY WAYLAND_DISPLAY WAYLAND_SOCKET XAUTHORITY
exec "$SNAP/run-portal.sh" "$@"

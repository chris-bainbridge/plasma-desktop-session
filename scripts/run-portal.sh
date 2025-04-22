#!/bin/sh
export PULSE_SERVER=unix:/run/user/`id -u`/pulse/native
export PIPEWIRE_RUNTIME_DIR=/run/user/`id -u`

# This is necessary to avoid xdg-desktop-portal-kde have Qt try
# to load the xdg-desktop-portal platform theme plugin
# this would lead to an unfortunate situation where the portal
# backend would try to talk to itself for file dialogs and such...
unset SNAP

exec "$@"

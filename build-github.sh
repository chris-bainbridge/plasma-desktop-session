#!/bin/bash
# Build the plasma-desktop-session snap for CI
# (chris-bainbridge/plasma-desktop-session, desktop/26).
#
# Mirrors the local go-build recipe minus the local-dev build-user/proxy
# wrappers (none of which apply on a GitHub-hosted runner). SDDM is
# staged from Neon's prebuilt deb (see snap/snapcraft.yaml) - nothing
# compiles here.
set -euo pipefail

rm -f ./*.snap

# The version is stamped in the nil 'plasma-desktop-session' part's
# override-build from git HEAD. snapcraft caches that scriptlet
# whenever the part definition is unchanged, so a HEAD move without a
# part-prop change would pack a snap whose version still names a
# previous commit. Clean the part every run: it is a nil part,
# re-running it costs seconds. (Mirrors go-build's same clean step.)
snapcraft clean plasma-desktop-session |& tee build.log

snapcraft pack |& tee -a build.log

# Keep a copy under a fixed name: the packed snap's filename is
# version-stamped (includes the git revision), but the image workflow
# downloads this repo's release asset by a fixed name.
latest="$(ls -t plasma-desktop-session_*.snap 2>/dev/null | head -1)"
if [ -n "$latest" ]; then
    cp -f "$latest" plasma-desktop-session.snap
fi

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

# The snap's base is core26-desktop (see go-build for why: the confined
# session apps run against the base's /usr, which must be core26-desktop
# so the chkpwd PAM helpers are setgid shadow). snapcraft's schema
# validation rejects 'core26-desktop' as a base name, so swap in a
# core26 placeholder for EVERY snapcraft call - including the clean
# below, which would otherwise validate the un-swapped yaml and fail
# with "must declare a 'build-base' if 'base' does not match 'coreXY'"
# (seen: GH run 41094426425) - then patch the packed snap's base back
# afterwards (mirrors go-build, minus the local-dev build-user/proxy
# wrappers).
sed -i 's/^base: core26-desktop$/base: core26/' snap/snapcraft.yaml
restore_base() {
    sed -i 's/^base: core26$/base: core26-desktop/' snap/snapcraft.yaml
}
trap restore_base EXIT

# The version is stamped in the nil 'plasma-desktop-session' part's
# override-build from git HEAD. snapcraft caches that scriptlet
# whenever the part definition is unchanged, so a HEAD move without a
# part-prop change would pack a snap whose version still names a
# previous commit. Clean the part every run: it is a nil part,
# re-running it costs seconds. (Mirrors go-build's same clean step.)
snapcraft clean plasma-desktop-session |& tee build.log

snapcraft pack |& tee -a build.log

trap - EXIT

# Patch the packed snap's declared base back to the real value.
built="$(ls -t plasma-desktop-session_*.snap 2>/dev/null | head -1)"
if [ -z "$built" ]; then
    echo "no packed plasma-desktop-session snap found" >&2
    exit 1
fi
tmp="$(mktemp -d ./snap-patch-tmp.XXXXXX)"
unsquashfs -d "$tmp/squashfs-root" -f "$built" >/dev/null
sed -i 's/^base: core26$/base: core26-desktop/' "$tmp/squashfs-root/meta/snap.yaml"
mksquashfs "$tmp/squashfs-root" "$built" -noappend -comp xz -no-progress -xattrs
rm -rf "$tmp"

# Keep a copy under a fixed name: the packed snap's filename is
# version-stamped (includes the git revision), but the image workflow
# downloads this repo's release asset by a fixed name.
latest="$(ls -t plasma-desktop-session_*.snap 2>/dev/null | head -1)"
if [ -n "$latest" ]; then
    cp -f "$latest" plasma-desktop-session.snap
fi

#!/bin/bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
qt_sdk="$(readlink -f "${repo_dir}/../plasma-core-desktop/.sdk/kde-qt6-core26-sdk")"
kf6_sdk="$(readlink -f "${repo_dir}/../plasma-core-desktop/.sdk/kf6-core26-sdk")"
stage_root="${1:-${repo_dir}/.sddm-qt6-stage}"
source_version="0.21.0+git20250502.4fe234b-2ubuntu3"
matrix_version="6.11.1-6.30.0-6.7.5-26.04.2"
triplet="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"

fail() {
  echo "SDDM Qt 6.11 build: $*" >&2
  exit 1
}

for tool in apt-get cmake dpkg-architecture ldd ninja readelf readlink; do
  command -v "$tool" >/dev/null || fail "required build tool is missing: $tool"
done

[[ -r "${qt_sdk}/meta/snap.yaml" && -r "${kf6_sdk}/meta/snap.yaml" ]] \
  || fail "build the KDE Neon Qt/KF6 SDKs before building SDDM"
grep -Eq '^version:[[:space:]]*6\.11\.1$' "${qt_sdk}/meta/snap.yaml" \
  || fail "Qt SDK is not version 6.11.1"
grep -Fq "version: ${matrix_version}" "${kf6_sdk}/meta/snap.yaml" \
  || fail "KDE SDKs do not match the locked Neon Qt/KF6/Plasma matrix"

qt_prefix="${qt_sdk}/usr"
qt_lib="${qt_prefix}/lib/${triplet}"
qt_bin="${qt_prefix}/bin/qt6"
qt_ld_library_path="${qt_lib}:${qt_lib}/libproxy:${qt_lib}/pulseaudio:${qt_lib}/sasl2:${qt_prefix}/lib"
export LD_LIBRARY_PATH="${qt_ld_library_path}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export PATH="${qt_bin}:${qt_prefix}/bin:${PATH}"
export CMAKE_PREFIX_PATH="${qt_prefix}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"
export PKG_CONFIG_PATH="${qt_lib}/pkgconfig:${qt_prefix}/share/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"

qt_version="$("${qt_bin}/qmake" -query QT_VERSION)"
[[ ${qt_version} == 6.11.1 ]] || fail "qmake reports Qt ${qt_version}, expected 6.11.1"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/sddm-qt6.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
(
  cd "$tmp_dir"
  apt-get source "sddm=${source_version}"
)

source_dir="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d -name 'sddm-*' -print -quit)"
[[ -n ${source_dir} && -f ${source_dir}/debian/rules ]] \
  || fail "failed to retrieve the pinned Ubuntu SDDM source package"

build_dir="${tmp_dir}/build"
install_root="${tmp_dir}/install"
cmake -S "$source_dir" -B "$build_dir" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_SKIP_INSTALL_RPATH=ON \
  -DCMAKE_INSTALL_LIBEXECDIR="/usr/lib/${triplet}/sddm" \
  -DSESSION_COMMAND=/etc/sddm/Xsession \
  -DWAYLAND_SESSION_COMMAND=/etc/sddm/wayland-session \
  -DDBUS_CONFIG_FILENAME=sddm_org.freedesktop.DisplayManager.conf \
  -DBUILD_WITH_QT6=ON \
  -DBUILD_MAN_PAGES=OFF \
  -DQML_INSTALL_DIR="/usr/lib/${triplet}/qt6/qml"
cmake --build "$build_dir" --parallel "${SDDM_BUILD_JOBS:-4}"
DESTDIR="$install_root" cmake --install "$build_dir" --prefix /usr --strip

stage_payload="${stage_root}/sddm-qt6"
rm -rf "$stage_payload"
for path in \
  "usr/bin/sddm" \
  "usr/bin/sddm-greeter-qt6" \
  "usr/lib/${triplet}/sddm/sddm-helper" \
  "usr/lib/${triplet}/sddm/sddm-helper-start-wayland" \
  "usr/lib/${triplet}/sddm/sddm-helper-start-x11user"
do
  binary="${install_root}/${path}"
  [[ -x ${binary} ]] || fail "CMake install did not produce ${path}"
  if readelf -d "$binary" | grep -Eq '\((RPATH|RUNPATH)\)'; then
    fail "${path} contains a non-portable runtime library path"
  fi
  resolved_qt="$(ldd "$binary" | awk '$1 == "libQt6Core.so.6" { print $3; exit }')"
  [[ -n ${resolved_qt} ]] || fail "${path} does not link to Qt 6"
  [[ $(readlink -f "$resolved_qt") == "${qt_lib}/libQt6Core.so.6.11.1" ]] \
    || fail "${path} did not resolve Qt 6.11.1 from the KDE Neon SDK"
  install -D -m 0755 "$binary" "${stage_payload}/${path}"
done

echo "Built SDDM ${source_version} against KDE Neon Qt ${qt_version} (${matrix_version})."

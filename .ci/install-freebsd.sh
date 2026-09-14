#!/usr/bin/env -S su -m root -ex
# NOTE: this script is run under root permissions
# shellcheck shell=sh disable=SC2096

# Pin the package repository to the 'quarterly' branch. 'latest' currently ships no qt6-multimedia
# package at all, and RPCS3 links Qt6::Multimedia and Qt6::MultimediaWidgets unconditionally (see
# 3rdparty/qt6.cmake), so the install below aborts before anything is compiled. Quarterly carries
# the same Qt 6.11.1 that latest does, well above the 6.7.0 minimum, and every other dependency
# here differs at patch level at most. Switch back once latest has qt6-multimedia again.
#
# This has to override whatever the VM image configures rather than rewrite /etc/pkg/FreeBSD.conf:
# the image already resolves to latest, so the old 's/quarterly/latest/' rewrite was a no-op.
# /usr/local/etc/pkg/repos is read after /etc/pkg and the zz- prefix sorts last within it, so this
# definition of the FreeBSD repo is the one that wins. Only the url is set, so the signature type
# and mirror settings are inherited from the image's definition.
mkdir -p /usr/local/etc/pkg/repos
cat > /usr/local/etc/pkg/repos/zz-quarterly.conf <<'REPO'
FreeBSD: {
  url: "pkg+https://pkg.FreeBSD.org/${ABI}/quarterly"
}
REPO

export ASSUME_ALWAYS_YES=true
pkg info # debug
pkg -vv | sed -n '/^Repositories:/,$p' || true # debug: effective repository configuration

# WITH_LLVM and Clang compiler
pkg install "llvm$LLVM_COMPILER_VER"

# Mandatory dependencies (qtX-base is pulled via qtX-multimedia)
pkg install git ccache cmake ninja "qt$QT_VER_MAIN-multimedia" "qt$QT_VER_MAIN-svg" glew openal-soft ffmpeg pcre2

# Optional dependencies (libevdev is pulled by qtX-base)
pkg install pkgconf alsa-lib pulseaudio sdl3 evdev-proto vulkan-headers vulkan-loader opencv

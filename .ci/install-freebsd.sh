#!/usr/bin/env -S su -m root -ex
# NOTE: this script is run under root permissions
# shellcheck shell=sh disable=SC2096

# Stay on the image's default 'quarterly' repository. This used to switch to 'latest' because RPCS3
# often needs recent Qt and Vulkan-Headers, but 'latest' currently ships no qt6-multimedia package
# at all, so the pkg install below aborts before anything is compiled. Quarterly carries the same
# Qt 6.11.1 that latest does, well above the 6.7.0 CMake asks for, and a Vulkan-Headers one patch
# behind. Switch back if quarterly ever falls behind what RPCS3 needs.

export ASSUME_ALWAYS_YES=true
pkg info # debug

# WITH_LLVM and Clang compiler
pkg install "llvm$LLVM_COMPILER_VER"

# Mandatory dependencies (qtX-base is pulled via qtX-multimedia)
pkg install git ccache cmake ninja "qt$QT_VER_MAIN-multimedia" "qt$QT_VER_MAIN-svg" glew openal-soft ffmpeg pcre2

# Optional dependencies (libevdev is pulled by qtX-base)
pkg install pkgconf alsa-lib pulseaudio sdl3 evdev-proto vulkan-headers vulkan-loader opencv

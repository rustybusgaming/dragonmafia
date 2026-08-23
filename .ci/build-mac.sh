#!/bin/sh -ex
# Gather explicit version number and number of commits
COMM_TAG=$(awk '/version{.*}/ { printf("%d.%d.%d", $5, $6, $7) }' rpcs3/rpcs3_version.cpp)
COMM_COUNT=$(git rev-list --count HEAD)
COMM_HASH=$(git rev-parse --short=8 HEAD)

# AVVER is used for GitHub releases, it is the version number. LVER is used for release naming.
AVVER="${COMM_TAG}-${COMM_COUNT}"
export LVER="${COMM_TAG}-${COMM_COUNT}-${COMM_HASH}"
echo "AVVER=$AVVER" >> .ci/ci-vars.env

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
brew install -f --overwrite --quiet ccache "llvm@$LLVM_COMPILER_VER"
brew link -f --overwrite --quiet "llvm@$LLVM_COMPILER_VER"
brew install -f --overwrite --quiet googletest opencv@4 sdl3 vulkan-headers vulkan-loader molten-vk
brew unlink --quiet ffmpeg fmt qtbase qtsvg qtdeclarative protobuf || true

export CXX=clang++
export CC=clang

export BREW_PATH;
BREW_PATH="$(brew --prefix)"
export BREW_BIN="$BREW_PATH/bin"
export BREW_SBIN="$BREW_PATH/sbin"

export WORKDIR;
WORKDIR="$(pwd)"

# Setup ccache
if [ ! -d "$CCACHE_DIR" ]; then
  mkdir -p "$CCACHE_DIR"
fi

# Get Qt
if [ ! -d "/tmp/Qt/$QT_VER" ]; then
  mkdir -p "/tmp/Qt"
  git clone https://github.com/engnr/qt-downloader.git
  cd qt-downloader
  git checkout f52efee0f18668c6d6de2dec0234b8c4bc54c597
  sed -i '' "s/'qt{0}_{0}{1}{2}'.format(major, minor, patch)]))/'qt{0}_{0}{1}{2}'.format(major, minor, patch), 'qt{0}_{0}{1}{2}'.format(major, minor, patch)]))/g" qt-downloader
  sed -i '' "s/'{}\/{}\/qt{}_{}\/'/'{0}\/{1}\/qt{2}_{3}\/qt{2}_{3}\/'/g" qt-downloader
  cd "/tmp/Qt"
  pip3 install py7zr requests semantic_version lxml --no-cache --break-system-packages
  mkdir -p "$QT_VER/macos" ; ln -s "macos" "$QT_VER/clang_64"
  sed -i '' 's/args\.version \/ derive_toolchain_dir(args) \/ //g' "$WORKDIR/qt-downloader/qt-downloader"

  # The Qt download servers intermittently close the connection without responding, which fails the
  # whole job before a single file is compiled ("Connection aborted ... RemoteDisconnected"). There
  # is nothing to diagnose when that happens and nothing local to fix, so retry rather than burning
  # a full job. Each attempt starts from an empty output directory, so a download interrupted part
  # way through cannot leave a half extracted Qt behind for the next one to build against. The
  # clang_64 symlink points at macos and stays valid across the wipe.
  qt_attempt=1
  qt_attempts=5

  while true; do
    if python3 "$WORKDIR/qt-downloader/qt-downloader" macos desktop "$QT_VER" clang_64 --opensource --addons qtmultimedia qtimageformats -o "$QT_VER/clang_64"; then
      break
    fi

    if [ "$qt_attempt" -ge "$qt_attempts" ]; then
      echo "qt-downloader failed $qt_attempts times, giving up" >&2
      exit 1
    fi

    qt_backoff=$((qt_attempt * 15))
    echo "qt-downloader attempt $qt_attempt of $qt_attempts failed, retrying in ${qt_backoff}s" >&2
    sleep "$qt_backoff"
    rm -rf "$QT_VER/macos"
    mkdir -p "$QT_VER/macos"
    qt_attempt=$((qt_attempt + 1))
  done
fi

cd "$WORKDIR"
ditto "/tmp/Qt/$QT_VER" "qt-downloader/$QT_VER"

export Qt6_DIR="$WORKDIR/qt-downloader/$QT_VER/clang_64/lib/cmake/Qt$QT_VER_MAIN"
export SDL3_DIR="$BREW_PATH/opt/sdl3/lib/cmake/SDL3"

export PATH="$BREW_PATH/opt/llvm@$LLVM_COMPILER_VER/bin:$PATH"
export LDFLAGS="-L$BREW_PATH/opt/llvm@$LLVM_COMPILER_VER/lib/c++ -L$BREW_PATH/opt/llvm@$LLVM_COMPILER_VER/lib/unwind -lunwind"

export VULKAN_SDK
VULKAN_SDK="$BREW_PATH/opt/molten-vk"
ln -s "$BREW_PATH/opt/vulkan-loader/lib/libvulkan.dylib" "$VULKAN_SDK/lib/libvulkan.dylib"

export LLVM_DIR
LLVM_DIR="$BREW_PATH/opt/llvm@$LLVM_COMPILER_VER"
# Pull all the submodules except some
# shellcheck disable=SC2046
git submodule -q update --init --depth=1 --jobs=8 $(awk '/path/ && !/llvm/ && !/opencv/ && !/SDL/ && !/feralinteractive/ { print $3 }' .gitmodules)

mkdir build && cd build || exit 1
# The below should be uncommented once bugs with Qt 6 QListWidgets when using the OS 26 visual style are resolved.
# sudo xcode-select -switch /Applications/Xcode_26.3.app/Contents/Developer

cmake .. \
    -DBUILD_RPCS3_TESTS="${RUN_UNIT_TESTS}" \
    -DRUN_RPCS3_TESTS="${RUN_UNIT_TESTS}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DCMAKE_OSX_SYSROOT="$(xcrun --sdk macosx --show-sdk-path)" \
    -DMACOSX_BUNDLE_SHORT_VERSION_STRING="${COMM_TAG}" \
    -DMACOSX_BUNDLE_BUNDLE_VERSION="${COMM_COUNT}" \
    -DSTATIC_LINK_LLVM=ON \
    -DUSE_SDL=ON \
    -DUSE_DISCORD_RPC=ON \
    -DUSE_AUDIOUNIT=ON \
    -DUSE_SYSTEM_FFMPEG=OFF \
    -DUSE_NATIVE_INSTRUCTIONS=OFF \
    -DUSE_PRECOMPILED_HEADERS=OFF \
    -DUSE_SYSTEM_MVK=ON \
    -DUSE_SYSTEM_SDL=ON \
    -DUSE_SYSTEM_OPENCV=ON \
    -G Ninja

ninja -j4; build_status=$?;

cd ..

# If it compiled succesfully let's deploy.
if [ "$build_status" -eq 0 ]; then
    .ci/deploy-mac.sh
fi

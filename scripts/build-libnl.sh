#!/bin/bash
set -e
source ./build-env.sh

ROOT=$(pwd)/src/libnl-3
cd "$ROOT"

echo "[*] Applying Android in_addr_t patch..."
patch -p1 < ../../patches/libnl-android-in_addr.patch || true

echo "[*] Cleaning..."
make distclean 2>/dev/null || true

echo "[*] Configuring libnl..."
./configure \
    --host=$TRIPLE \
    --prefix=$PREFIX \
    --disable-cli \
    --disable-pthreads \
    --enable-shared \
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"

echo "[*] Building libnl..."
make -j$(nproc)
make install

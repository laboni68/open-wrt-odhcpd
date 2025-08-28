#!/bin/bash
set -ex

cd $SRC

# Install dependencies
apt-get update
apt-get install -y libnl-3-dev libnl-genl-3-dev pkg-config libjson-c-dev

# Build libubox from source
git clone https://git.openwrt.org/project/libubox.git
cd libubox
mkdir -p build
cd build
cmake .. -DBUILD_LUA=OFF -DBUILD_EXAMPLES=OFF -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_C_FLAGS="-fPIC"
make -j$(nproc)
make install

cd $SRC

# Build libuci from source
git clone https://git.openwrt.org/project/uci.git
cd uci
mkdir -p build
cd build
cmake .. -DBUILD_LUA=OFF -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_C_FLAGS="-fPIC"
make -j$(nproc)
make install

cd $SRC/odhcpd

# Create a wrapper header to handle libnl-tiny vs libnl-3 differences
cat > src/netlink-generic.h << 'EOF'
#ifndef NETLINK_GENERIC_H
#define NETLINK_GENERIC_H

#include <netlink/netlink.h>
#include <netlink/msg.h>
#include <netlink/attr.h>
#include <netlink/socket.h>
#include <netlink/genl/genl.h>
#include <netlink/genl/ctrl.h>

#endif
EOF

# Modify CMakeLists.txt to work with standard libnl-3
sed -i 's|FIND_PATH(libnl-tiny_include_dir netlink-generic.h PATH_SUFFIXES libnl-tiny)|set(libnl-tiny_include_dir /usr/include/libnl3)|' CMakeLists.txt
sed -i 's|FIND_LIBRARY(libnl NAMES nl-tiny)|set(libnl nl-3 nl-genl-3)|' CMakeLists.txt

# Create build directory
mkdir -p build
cd build

# Configure with CMake
cmake .. \
    -DCMAKE_C_COMPILER=$CC \
    -DCMAKE_CXX_COMPILER=$CXX \
    -DCMAKE_C_FLAGS="$CFLAGS -fPIC -I/usr/include/libnl3" \
    -DCMAKE_BUILD_TYPE=Release \
    -DUBUS=0 \
    -DDHCPV4_SUPPORT=1

# Build object files
make -j$(nproc) || true

# Extract all object files into a static library
find . -name "*.o" | xargs ar rcs libodhcpd.a

# Build the fuzzer
$CC $CFLAGS \
    -I$SRC/odhcpd/src \
    -I/usr/include/libnl3 \
    -c $SRC/empty-fuzzer.c \
    -o empty-fuzzer.o

$CXX $CXXFLAGS \
    empty-fuzzer.o \
    -o $OUT/empty-fuzzer \
    libodhcpd.a \
    $LIB_FUZZING_ENGINE \
    -lubox -luci -lnl-3 -lnl-genl-3 -lresolv -ljson-c
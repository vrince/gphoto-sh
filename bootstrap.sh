#!/bin/bash

# build & install parallel
PARALLEL_VERSION=20171222
mkdir ext
pushd ext
wget -O parallel.tar.bz2 http://ftp.gnu.org/gnu/parallel/parallel-${PARALLEL_VERSION}.tar.bz2
tar -vxjf parallel.tar.bz2
pushd parallel-${PARALLEL_VERSION}
./configure
make
sudo make install
popd
popd

# dependencies
sudo apt install --no-install-recommends imagemagick libimage-exiftool-perl xmlstarlet curl
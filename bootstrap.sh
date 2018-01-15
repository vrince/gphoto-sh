#!/bin/bash
PARALLEL_VERSION=20171222

#intall parallel
mkdir ext
pushd ext
wget -O parallel.tar.bz2 http://ftp.gnu.org/gnu/parallel/parallel-${PARALLEL_VERSION}.tar.bz2
tar -vxjf parallel.tar.bz2
pushd parallel-${PARALLEL_VERSION}
./configure
make install
popd
popd
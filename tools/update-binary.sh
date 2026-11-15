#!/bin/sh
set -eu
make build/x16net.bin
mkdir -p bin
cp build/x16net.bin bin/x16net.bin
(cd bin && sha256sum x16net.bin > SHA256SUMS)

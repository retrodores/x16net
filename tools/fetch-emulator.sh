#!/bin/sh
set -eu
mkdir -p .tools/x16emu-r49
archive=.tools/x16emu_linux-x86_64-r49.zip
curl --fail --location --retry 3 \
  https://github.com/X16Community/x16-emulator/releases/download/r49/x16emu_linux-x86_64-r49.zip -o "$archive"
echo "efb2d4ad36ae4244370004891aa67bdf85d2ec01b42b7f12f97b48b62aff009d  $archive" | sha256sum -c -
unzip -qo "$archive" -d .tools/x16emu-r49
chmod +x .tools/x16emu-r49/x16emu

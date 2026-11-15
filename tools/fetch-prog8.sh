#!/bin/sh
set -eu
mkdir -p .tools
jar=.tools/prog8c-14.0-BETA3-all.jar
curl --fail --location --retry 3 \
  https://github.com/irmen/prog8/releases/download/v14.0-BETA3/prog8c-14.0-BETA3-all.jar -o "$jar"
echo "7117cabdb1d3ecf11d4f38aa7e2cea570056a3eb2c3b3f4e8593838b1b4115c0  $jar" | sha256sum -c -
cat > .tools/prog8c <<'WRAPPER'
#!/bin/sh
exec java -jar "$(dirname "$0")/prog8c-14.0-BETA3-all.jar" "$@"
WRAPPER
chmod +x .tools/prog8c

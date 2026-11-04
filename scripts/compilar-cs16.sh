#!/usr/bin/env bash
# Counter-Strike 1.6 (cs16-client: cliente, menu, servidor ReGameDLL e bots). Opcional: se falhar,
# o app sai sem ele e o resto da build segue.
. "$(dirname "$0")/comum.sh"
registrar cs16

LIBS_CS="$TRAB/libs-cs"
rm -rf "$LIBS_CS"

baixar_repo https://github.com/Velaron/cs16-client "$CS16_COMMIT" "$TRAB/cs16"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
PLAT="$(xcrun --sdk iphoneos --show-sdk-platform-path)"

# os mesmos parâmetros do scripts/ios/buildcs16.sh do Xash
cmake -S "$TRAB/cs16" -B "$TRAB/cs16/build" \
	-DCMAKE_OSX_SYSROOT="$SDK" -DCMAKE_DEVELOPER_ROOT="$PLAT/Developer" \
	-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 -DCMAKE_OSX_ARCHITECTURES=arm64 \
	-DMAC=0 -DDEBUG=1 -DXASH_COMPAT=1 -DMAINUI_USE_STB=1 -DCMAKE_BUILD_TYPE=Debug
cmake --build "$TRAB/cs16/build" --config Debug --parallel "$NCPU"
cmake --install "$TRAB/cs16/build" --prefix "$LIBS_CS"

echo "== Counter-Strike 1.6:"
(cd "$LIBS_CS" && find . -type f | sort)
touch "$LIBS_CS/.ok"

#!/usr/bin/env bash
# Counter-Strike 1.6 (cs16-client): cliente, menu e servidor (ReGameDLL, que já traz os bots do CS).
# Opcional: se falhar, o app sai sem ele e o resto da build segue.
#
# O YaPB (bot à parte do pacote) não compila para iPhone: o CMake dele põe flags de Mac Intel
# (-mmacosx-version-min, -march=x86-64, -msse). Por isso a build segue mesmo com ele quebrando (-k)
# e as bibliotecas que interessam são copiadas à mão.
. "$(dirname "$0")/comum.sh"
registrar cs16

LIBS_CS="$TRAB/libs-cs"
CS="$LIBS_CS/cstrike"
rm -rf "$LIBS_CS"

baixar_repo https://github.com/Velaron/cs16-client "$CS16_COMMIT" "$TRAB/cs16"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
PLAT="$(xcrun --sdk iphoneos --show-sdk-platform-path)"
B="$TRAB/cs16/build"

# os mesmos parâmetros do scripts/ios/buildcs16.sh do Xash
cmake -S "$TRAB/cs16" -B "$B" \
	-DCMAKE_OSX_SYSROOT="$SDK" -DCMAKE_DEVELOPER_ROOT="$PLAT/Developer" \
	-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 -DCMAKE_OSX_ARCHITECTURES=arm64 \
	-DMAC=0 -DDEBUG=1 -DXASH_COMPAT=1 -DMAINUI_USE_STB=1 -DCMAKE_BUILD_TYPE=Debug
cmake --build "$B" --config Debug --parallel "$NCPU" -- -k || echo "aviso: parte da build falhou (o YaPB, esperado); confiro as bibliotecas abaixo"

echo "== bibliotecas geradas:"
find "$B" -name '*.dylib' -type f | sort

# acha uma biblioteca pelo começo do nome, fora do YaPB
achar() {
	find "$B" -name "$1*.dylib" -type f ! -path '*yapb*' | head -1
}

# confere que é um binário de iPhone (LC_BUILD_VERSION platform 2) e não de Mac
conferir_ios() {
	local plat
	plat="$(otool -l "$1" | awk '/cmd LC_BUILD_VERSION/{achou=1} achou && /platform/{print $2; exit}')"
	if [ "$plat" != "2" ]; then
		echo "erro: $1 não é de iPhone (platform=$plat)"
		return 1
	fi
}

CLIENTE="$(achar client)"
MENU="$(achar menu)"
SERVIDOR="$(achar cs)"

for f in "$CLIENTE" "$MENU" "$SERVIDOR"; do
	[ -n "$f" ] || { echo "erro: faltou cliente, menu ou servidor do CS"; exit 1; }
	conferir_ios "$f"
done

# o motor procura <nome>_ios_arm64.dylib; o CMake do cs16-client não reconhece o iOS e põe só _arm64
mkdir -p "$CS/cl_dlls" "$CS/dlls"
cp "$CLIENTE" "$CS/cl_dlls/client_ios_arm64.dylib"
cp "$MENU" "$CS/cl_dlls/menu_ios_arm64.dylib"
cp "$SERVIDOR" "$CS/dlls/cs_ios_arm64.dylib"

# extras do CS (controles de toque, perfis dos bots e o resto do pacote)
EXTRAS="$(find "$B" -maxdepth 2 -name extras.pk3 -type f | head -1)"
if [ -n "$EXTRAS" ]; then
	cp "$EXTRAS" "$CS/extras.pk3"
else
	echo "aviso: não achei o extras.pk3 do CS"
fi

echo "== Counter-Strike 1.6:"
(cd "$LIBS_CS" && find . -type f | sort)
touch "$LIBS_CS/.ok"

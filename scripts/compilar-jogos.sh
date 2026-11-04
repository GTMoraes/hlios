#!/usr/bin/env bash
# Compila as bibliotecas dos jogos (hlsdk-portable) para iPhone:
#   mobile_hacks -> valve   (Half-Life; também serve o Blue Shift)
#   opfor        -> gearbox (Opposing Force)
#   dmc          -> dmc     (Deathmatch Classic)
. "$(dirname "$0")/comum.sh"
registrar jogos

LIBS="$TRAB/libs"
rm -rf "$LIBS"
mkdir -p "$LIBS"

compilar_hlsdk() { # nome commit
	local dir="$TRAB/hlsdk-$1"
	baixar_repo https://github.com/FWGS/hlsdk-portable "$2" "$dir"
	# Debug, como no script de iOS do Xash (lá diz que o Release para iOS está quebrado)
	cmake -S "$dir" -B "$dir/build" \
		-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 -DCMAKE_OSX_ARCHITECTURES=arm64 \
		-D64BIT=ON -DCMAKE_BUILD_TYPE=Debug \
		-DCMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT=0 -DCMAKE_INSTALL_PREFIX="$LIBS"
	cmake --build "$dir/build" --target install --parallel "$NCPU"
}

compilar_hlsdk hl "$HLSDK_HL_COMMIT"
compilar_hlsdk opfor "$HLSDK_OPFOR_COMMIT"
compilar_hlsdk dmc "$HLSDK_DMC_COMMIT"

echo "== bibliotecas dos jogos:"
(cd "$LIBS" && find . -type f | sort)

#!/usr/bin/env bash
# Escolhe o Xcode 26 mais novo (sem beta). Com o SDK do iOS 27, um app que não adota o ciclo de
# vida UIScene não abre, e o SDL2 que o port do Xash usa não adota. Com o SDK 26 ele abre.
. "$(dirname "$0")/comum.sh"
registrar xcode

ls -d /Applications/Xcode*.app || true
XC="$(ls -d /Applications/Xcode_26*.app 2>/dev/null | grep -viE 'beta|release_candidate|_rc' | sort -V | tail -1 || true)"

if [ -z "$XC" ]; then
	echo "::error::Não achei o Xcode 26 neste runner. Com o SDK do iOS 27 o app não abriria (falta o UIScene no SDL2). Hora de passar para o SDL3."
	exit 1
fi

sudo xcode-select -s "$XC"
xcodebuild -version
echo "SDK do iPhone: $(xcrun --sdk iphoneos --show-sdk-version)"
echo "XCODE_ESCOLHIDO=$(basename "$XC" .app)" >> "${GITHUB_ENV:-/dev/null}"

#!/usr/bin/env bash
# SDL2 para iPhone (só arm64 de aparelho), instalado onde o waf do Xash procura:
# /Library/Frameworks/SDL2.framework
. "$(dirname "$0")/comum.sh"
registrar sdl2

DEPS="$RAIZ/deps"

if [ -f "$DEPS/SDL2.framework/SDL2" ]; then
	echo "SDL2 $SDL_VERSAO: do cache"
else
	rm -rf "$TRAB/SDL" "$TRAB/SDL2-iphoneos.xcarchive" "$DEPS/SDL2.framework"
	git clone -q --depth 1 -b "release-$SDL_VERSAO" https://github.com/libsdl-org/SDL "$TRAB/SDL"
	xcodebuild archive \
		-project "$TRAB/SDL/Xcode/SDL/SDL.xcodeproj" -scheme Framework-iOS \
		-archivePath "$TRAB/SDL2-iphoneos.xcarchive" \
		-sdk iphoneos -destination 'generic/platform=iOS' \
		IPHONEOS_DEPLOYMENT_TARGET=12.0 BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO \
		CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
		> "$LOGS/sdl2-xcodebuild.log" 2>&1 || true
	grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)" "$LOGS/sdl2-xcodebuild.log" || true
	grep -q "ARCHIVE SUCCEEDED" "$LOGS/sdl2-xcodebuild.log"
	mkdir -p "$DEPS"
	cp -R "$TRAB/SDL2-iphoneos.xcarchive/Products/Library/Frameworks/SDL2.framework" "$DEPS/"
fi

sudo rm -rf /Library/Frameworks/SDL2.framework
sudo mkdir -p /Library/Frameworks
sudo cp -R "$DEPS/SDL2.framework" /Library/Frameworks/
lipo -info "$DEPS/SDL2.framework/SDL2"

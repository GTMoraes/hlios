#!/usr/bin/env bash
# Monta o HalfLife.app: motor + bibliotecas dos jogos + SDL2, tudo em frameworks,
# Info.plist, ícone, manifesto de privacidade e assinatura provisória. Sai também um IPA.
. "$(dirname "$0")/comum.sh"
registrar montar

BUILD="${BUILD:-1}"
export BUILD

rm -rf "$TRAB/app"
mkdir -p "$APP/Frameworks"

cp -R "$TRAB/motor-instalado/." "$APP/"
cp -R "$TRAB/libs/." "$APP/"

if [ -f "$TRAB/libs-cs/.ok" ]; then
	rsync -a --exclude .ok "$TRAB/libs-cs/" "$APP/"
	echo "Counter-Strike 1.6: incluído"
else
	echo "Counter-Strike 1.6: fora desta build"
fi

cp -R "$RAIZ/deps/SDL2.framework" "$APP/Frameworks/"

echo "== antes de embrulhar:"
(cd "$APP" && find . -type f | sort)

python3 "$RAIZ/scripts/embrulhar.py" "$APP" xash "$APP_VERSAO" "$BUILD" "$APP_BUNDLE"

# ícone (do segredo APP_ICON_PNG)
rm -rf "$TRAB/icone" "$TRAB/venv"
python3 -m venv "$TRAB/venv"
"$TRAB/venv/bin/pip" install -q pillow
"$TRAB/venv/bin/python" "$RAIZ/scripts/icone.py" "$TRAB/icone"
xcrun actool "$TRAB/icone/Assets.xcassets" --compile "$APP" \
	--platform iphoneos --minimum-deployment-target "$IOS_MINIMO" --target-device iphone \
	--app-icon AppIcon --output-partial-info-plist "$TRAB/icone/parcial.plist" \
	--output-format human-readable-text --notices --warnings --errors

python3 "$RAIZ/scripts/info-plist.py" "$RAIZ/app/Info.plist" "$TRAB/icone/parcial.plist" "$APP/Info.plist"
cp "$RAIZ/app/PrivacyInfo.xcprivacy" "$APP/"
plutil -lint "$APP/Info.plist"

# assinatura provisória: cada framework, depois o app (o envio ao TestFlight assina de verdade)
for fw in "$APP"/Frameworks/*.framework; do
	codesign --force --sign - --timestamp=none "$fw"
done
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "== app final:"
(cd "$APP" && find . -type f | sort)
du -sh "$APP"

# IPA para conferir (ou instalar pelo LiveContainer, se um dia precisar)
rm -rf "$TRAB/saida"
mkdir -p "$TRAB/saida/Payload"
cp -R "$APP" "$TRAB/saida/Payload/"
(cd "$TRAB/saida" && zip -qry "$APP_NOME.ipa" Payload && rm -rf Payload)
ls -la "$TRAB/saida"

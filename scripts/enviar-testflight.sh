#!/usr/bin/env bash
# Monta o .xcarchive com o app já montado e envia ao TestFlight com a assinatura gerenciada pela
# Apple (o mesmo caminho do nfios: só a chave da API nos segredos, nenhum certificado).
. "$(dirname "$0")/comum.sh"
registrar testflight

if [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ] || [ -z "${ASC_KEY_P8:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ]; then
	echo "Sem os segredos do App Store Connect: pulei o TestFlight."
	exit 0
fi

BUILD="${BUILD:-1}"
ARQ="$TRAB/$APP_NOME.xcarchive"
rm -rf "$ARQ" "$TRAB/export"
mkdir -p "$ARQ/Products/Applications"
cp -R "$APP" "$ARQ/Products/Applications/"

# o Info.plist que o Xcode põe num archive
python3 - "$ARQ/Info.plist" <<PYEOF
import datetime, plistlib, sys
info = {
    'ApplicationProperties': {
        'ApplicationPath': 'Applications/${APP_NOME}.app',
        'Architectures': ['arm64'],
        'CFBundleIdentifier': '${APP_BUNDLE}',
        'CFBundleShortVersionString': '${APP_VERSAO}',
        'CFBundleVersion': '${BUILD}',
        'Team': '${APPLE_TEAM_ID}',
    },
    'ArchiveVersion': 2,
    'CreationDate': datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
    'Name': '${APP_NOME}',
    'SchemeName': '${APP_NOME}',
}
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(info, f)
PYEOF

K="$TRAB/AuthKey_$ASC_KEY_ID.p8"
trap 'rm -f "$K"' EXIT
printf '%s\n' "$ASC_KEY_P8" > "$K"

cat > "$TRAB/export.plist" <<PLEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>upload</string>
	<key>teamID</key><string>$APPLE_TEAM_ID</string>
	<key>signingStyle</key><string>automatic</string>
	<key>testFlightInternalTestingOnly</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
	<key>uploadSymbols</key><false/>
</dict></plist>
PLEOF

xcodebuild -exportArchive -archivePath "$ARQ" -exportPath "$TRAB/export" \
	-exportOptionsPlist "$TRAB/export.plist" \
	-allowProvisioningUpdates -authenticationKeyPath "$K" \
	-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
	> "$LOGS/export.log" 2>&1 || true
cat "$LOGS/export.log"
grep -qE "EXPORT SUCCEEDED|Upload succeeded|Uploaded" "$LOGS/export.log"

{
	echo "### TestFlight"
	echo "Build $BUILD ($APP_VERSAO) enviada. Em uns 10 a 20 minutos aparece no app TestFlight do iPhone."
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

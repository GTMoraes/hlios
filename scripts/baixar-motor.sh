#!/usr/bin/env bash
# Baixa o Xash3D FWGS no commit fixado e aplica as mudanças do hlios (pasta motor/)
. "$(dirname "$0")/comum.sh"
registrar motor-baixar

baixar_repo https://github.com/FWGS/xash3d-fwgs "$XASH_COMMIT" "$TRAB/xash"
cd "$TRAB/xash"

# 1. patches, em ordem:
#    0001 bibliotecas carregadas de dentro de Frameworks/ (o App Store Connect recusa .dylib solto)
#    0002 o app fecha ao sair do jogo (antes ficava numa tela preta)
for p in "$RAIZ"/motor/*.patch; do
	git apply --verbose "$p"
done

# 2. tela inicial com a escolha do jogo, no lugar da caixa de texto do port
cp "$RAIZ/motor/launchdialog.m" engine/platform/ios/launchdialog.m

git --no-pager diff --stat

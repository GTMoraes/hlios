#!/usr/bin/env bash
# Baixa o Xash3D FWGS no commit fixado e aplica as mudanças do hlios (pasta motor/)
. "$(dirname "$0")/comum.sh"
registrar motor-baixar

baixar_repo https://github.com/FWGS/xash3d-fwgs "$XASH_COMMIT" "$TRAB/xash"
cd "$TRAB/xash"

# 1. bibliotecas carregadas de dentro de Frameworks/ (o App Store Connect recusa .dylib solto)
git apply --verbose "$RAIZ/motor/0001-ios-bibliotecas-em-frameworks.patch"

# 2. tela inicial com a escolha do jogo, no lugar da caixa de texto do port
cp "$RAIZ/motor/launchdialog.m" engine/platform/ios/launchdialog.m

git --no-pager diff --stat

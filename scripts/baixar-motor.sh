#!/usr/bin/env bash
# Baixa o Xash3D FWGS no commit fixado e aplica as mudanças do hlios (pasta motor/)
. "$(dirname "$0")/comum.sh"
registrar motor-baixar

baixar_repo https://github.com/FWGS/xash3d-fwgs "$XASH_COMMIT" "$TRAB/xash"
cd "$TRAB/xash"

# 1. patches, em ordem:
#    0001 bibliotecas carregadas de dentro de Frameworks/ (o App Store Connect recusa .dylib solto)
#    0002 o app vai para a tela inicial e fecha ao sair do jogo (antes ficava numa tela preta)
#    0003 toque rápido na área de olhar atira; toque duplo e segurar atira sem parar (cvar touch_look_fire)
#    0004 campo de visão só da arma em primeira pessoa (cvar r_viewmodel_fov), e o fov e a posição da arma na mão (fov_arma, arma_frente, arma_lado, arma_altura)
#    0005 as barras de campo de visão no menu do jogo (3rdparty/mainui, Video options)
#    0006 o padrão dos botões de toque vem do touch_padrao.cfg do jogo, quando tem (o app grava)
for p in "$RAIZ"/motor/*.patch; do
	git apply --verbose "$p"
done

# 2. tela inicial com a escolha do jogo, no lugar da caixa de texto do port
cp "$RAIZ/motor/launchdialog.m" engine/platform/ios/launchdialog.m

git --no-pager diff --stat

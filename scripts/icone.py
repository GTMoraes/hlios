#!/usr/bin/env python3
"""Monta o catálogo de ícones (Assets.xcassets/AppIcon) a partir do segredo APP_ICON_PNG.

O ícone não fica no repositório (que é público): vem do segredo, em base64. A Apple pede
1024x1024 sem canal alfa, então a imagem vai para um fundo preto e é ampliada se precisar.
Sem o segredo, sai um ícone simples, só para a build não parar.

Uso: icone.py <pasta de saída>
"""
import base64
import io
import json
import os
import sys

from PIL import Image, ImageDraw

LADO = 1024


def imagem_do_segredo():
    dados = os.environ.get('APP_ICON_PNG', '').strip()
    if not dados:
        return None
    try:
        return Image.open(io.BytesIO(base64.b64decode(dados)))
    except Exception as e:  # segredo com conteúdo errado: avisa e segue com o simples
        print('aviso: APP_ICON_PNG não é uma imagem válida (%s)' % e)
        return None


def imagem_simples():
    img = Image.new('RGB', (LADO, LADO), (14, 14, 16))
    d = ImageDraw.Draw(img)
    d.ellipse((132, 132, LADO - 132, LADO - 132), outline=(255, 138, 31), width=72)
    return img


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    saida = sys.argv[1]
    pasta = os.path.join(saida, 'Assets.xcassets', 'AppIcon.appiconset')
    os.makedirs(pasta, exist_ok=True)

    img = imagem_do_segredo()
    if img is None:
        print('aviso: sem o segredo APP_ICON_PNG, usando um ícone simples')
        img = imagem_simples()
    else:
        print('ícone do segredo: %dx%d %s' % (img.size[0], img.size[1], img.mode))

    img = img.convert('RGBA')
    fundo = Image.new('RGBA', img.size, (0, 0, 0, 255))
    fundo.alpha_composite(img)
    img = fundo.convert('RGB')  # sem canal alfa (ITMS-90717)
    if img.size != (LADO, LADO):
        img = img.resize((LADO, LADO), Image.LANCZOS)
    img.save(os.path.join(pasta, 'icone-1024.png'), 'PNG')

    with open(os.path.join(saida, 'Assets.xcassets', 'Contents.json'), 'w') as f:
        json.dump({'info': {'author': 'xcode', 'version': 1}}, f, indent=2)
    with open(os.path.join(pasta, 'Contents.json'), 'w') as f:
        json.dump({
            'images': [{'filename': 'icone-1024.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}],
            'info': {'author': 'xcode', 'version': 1},
        }, f, indent=2)
    print('ok: %s' % pasta)


if __name__ == '__main__':
    main()

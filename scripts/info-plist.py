#!/usr/bin/env python3
"""Gera o Info.plist do app a partir do modelo app/Info.plist.

Preenche o bundle, a versão, o número da build, o iOS mínimo, as chaves DT* do Xcode usado
e junta o que o actool gerou para o ícone (CFBundleIcons).

Uso: info-plist.py <modelo> <plist parcial do actool> <saída>
Ambiente: APP_BUNDLE, APP_VERSAO, BUILD, IOS_MINIMO
"""
import os
import plistlib
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from embrulhar import valores_dt  # noqa: E402


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    modelo, parcial, saida = sys.argv[1:]
    with open(modelo, 'rb') as f:
        info = plistlib.load(f)

    info['CFBundleIdentifier'] = os.environ['APP_BUNDLE']
    info['CFBundleShortVersionString'] = os.environ['APP_VERSAO']
    info['CFBundleVersion'] = os.environ.get('BUILD', '1')
    info['MinimumOSVersion'] = os.environ['IOS_MINIMO']
    info.update(valores_dt())

    if os.path.exists(parcial):
        with open(parcial, 'rb') as f:
            info.update(plistlib.load(f))

    sobrou = [k for k, v in info.items() if v == 'PREENCHIDO-NO-BUILD']
    if sobrou:
        raise SystemExit('erro: chaves sem valor no Info.plist: %s' % ', '.join(sobrou))

    with open(saida, 'wb') as f:
        plistlib.dump(info, f, fmt=plistlib.FMT_XML)
    for k in ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion', 'MinimumOSVersion',
              'DTXcode', 'DTXcodeBuild', 'DTSDKName'):
        print('%s = %s' % (k, info.get(k)))
    print('ícones: %s' % ('sim' if 'CFBundleIcons' in info else 'NÃO'))


if __name__ == '__main__':
    main()

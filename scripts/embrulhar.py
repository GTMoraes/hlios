#!/usr/bin/env python3
"""Embrulha as bibliotecas .dylib do app em frameworks.

O App Store Connect recusa .dylib solto dentro de um app (ITMS-90171). Este script move
cada biblioteca para Frameworks/<nome>.framework/<nome> e o motor (patch
motor/0001-ios-bibliotecas-em-frameworks.patch) procura cada uma lá, com o nome derivado
pela mesma regra:

    caminho relativo ao app, sem o ".dylib", com cada "/" trocado por "__"
    e cada caractere fora de [A-Za-z0-9_-] trocado por "_"

Exemplo: valve/cl_dlls/client_ios_arm64.dylib -> Frameworks/valve__cl_dlls__client_ios_arm64.framework

Também:
  - põe o SDL2.framework (e qualquer outro framework solto) dentro de Frameworks/;
  - troca o install name de cada biblioteca e as referências entre elas;
  - garante o rpath @executable_path/Frameworks no executável;
  - confere que não sobrou nenhum binário Mach-O fora do lugar permitido.

Uso: embrulhar.py <App.app> <executável> <versão> <build> <bundle id do app>
"""
import os
import plistlib
import re
import shutil
import subprocess
import sys

MACHO_MAGIC = {
    b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe',  # Mach-O 64 e 32, little-endian
    b'\xfe\xed\xfa\xcf', b'\xfe\xed\xfa\xce',  # big-endian
    b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca',  # universal (fat)
}


def nome_framework(rel):
    """Mesma regra do IOS_FrameworkName do motor (byte a byte, como no C)."""
    while rel.startswith('./') or rel.startswith('.\\'):
        rel = rel[2:]
    if len(rel) > 6 and rel[-6:].lower() == '.dylib':
        rel = rel[:-6]
    saida = []
    for b in rel.encode('utf-8'):
        c = chr(b)
        if c in '/\\':
            saida.append('__')
        elif ('a' <= c <= 'z') or ('A' <= c <= 'Z') or ('0' <= c <= '9') or c in '_-':
            saida.append(c)
        else:
            saida.append('_')
    return ''.join(saida)


def e_macho(caminho):
    try:
        with open(caminho, 'rb') as f:
            return f.read(4) in MACHO_MAGIC
    except OSError:
        return False


def rodar(*args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        raise SystemExit('erro: falhou: %s' % ' '.join(args))
    return r.stdout


def install_name(binario):
    linhas = rodar('otool', '-D', binario).strip().splitlines()
    return linhas[1].strip() if len(linhas) > 1 else None


def dependencias(binario):
    """Bibliotecas de que o binário depende (sem o próprio install name, que o otool -L lista junto)."""
    proprio = install_name(binario)
    linhas = rodar('otool', '-L', binario).splitlines()[1:]
    deps = []
    for l in linhas:
        l = l.strip()
        if not l:
            continue
        d = l.split(' (compatibility')[0].strip()
        if d != proprio:
            deps.append(d)
    return deps


def rpaths(binario):
    saida = rodar('otool', '-l', binario).splitlines()
    achados = []
    for i, l in enumerate(saida):
        if l.strip() == 'cmd LC_RPATH':
            for k in range(i + 1, min(i + 4, len(saida))):
                m = re.match(r'\s*path (.+?) \(offset', saida[k])
                if m:
                    achados.append(m.group(1))
                    break
    return achados


def minos(binario, padrao='12.0'):
    saida = rodar('otool', '-l', binario).splitlines()
    for i, l in enumerate(saida):
        t = l.strip()
        if t in ('cmd LC_BUILD_VERSION', 'cmd LC_VERSION_MIN_IPHONEOS'):
            for k in range(i + 1, min(i + 8, len(saida))):
                m = re.match(r'\s*(minos|version) ([0-9.]+)', saida[k])
                if m:
                    return m.group(2)
    return padrao


def maior_versao(a, b):
    pa = [int(x) for x in a.split('.')]
    pb = [int(x) for x in b.split('.')]
    return a if pa >= pb else b


def valores_dt():
    """As chaves DT* que o Xcode põe em todo bundle (o App Store Connect confere o toolchain)."""
    def sai(*args):
        return subprocess.run(args, capture_output=True, text=True).stdout.strip()
    sdk_ver = sai('xcrun', '--sdk', 'iphoneos', '--show-sdk-version')
    sdk_build = sai('xcrun', '--sdk', 'iphoneos', '--show-sdk-build-version')
    plat_ver = sai('xcrun', '--sdk', 'iphoneos', '--show-sdk-platform-version') or sdk_ver
    xv = sai('xcodebuild', '-version').splitlines()
    xcode_ver = xv[0].split()[-1] if xv else '26.0'
    xcode_build = xv[1].split()[-1] if len(xv) > 1 else ''
    partes = (xcode_ver.split('.') + ['0', '0'])[:3]
    dtxcode = '%02d%d%d' % (int(partes[0]), int(partes[1]), int(partes[2]))
    return {
        'BuildMachineOSBuild': sai('sw_vers', '-buildVersion'),
        'DTCompiler': 'com.apple.compilers.llvm.clang.1_0',
        'DTPlatformBuild': sdk_build,
        'DTPlatformName': 'iphoneos',
        'DTPlatformVersion': plat_ver,
        'DTSDKBuild': sdk_build,
        'DTSDKName': 'iphoneos' + sdk_ver,
        'DTXcode': dtxcode,
        'DTXcodeBuild': xcode_build,
    }


def main():
    if len(sys.argv) != 6:
        raise SystemExit(__doc__)
    app, executavel, versao, build, bundle_app = sys.argv[1:]
    app = os.path.abspath(app)
    fw_dir = os.path.join(app, 'Frameworks')
    os.makedirs(fw_dir, exist_ok=True)
    exe = os.path.join(app, executavel)
    if not e_macho(exe):
        raise SystemExit('erro: executável %s não encontrado ou não é Mach-O' % exe)

    dt = valores_dt()

    # 1. frameworks soltos (ex.: SDL2.framework na raiz) vão para Frameworks/
    for raiz, dirs, _ in os.walk(app):
        for d in list(dirs):
            if d.endswith('.framework'):
                origem = os.path.join(raiz, d)
                if os.path.dirname(origem) != fw_dir:
                    destino = os.path.join(fw_dir, d)
                    if os.path.exists(destino):
                        shutil.rmtree(destino)
                    print('framework: %s -> Frameworks/%s' % (os.path.relpath(origem, app), d))
                    shutil.move(origem, destino)
                dirs.remove(d)

    # 2. cada biblioteca vira um framework
    movidos = {}    # install name antigo -> [install names novos]
    por_folha = {}  # nome do arquivo -> [install names novos]
    for raiz, dirs, arquivos in os.walk(app):
        if os.path.abspath(raiz).startswith(fw_dir):
            dirs[:] = []
            continue
        for a in sorted(arquivos):
            caminho = os.path.join(raiz, a)
            # todo binário Mach-O fora de Frameworks/, menos o executável do app (um .so de bot,
            # por exemplo, também vira framework: binário solto o envio recusa)
            if os.path.islink(caminho) or caminho == exe or not e_macho(caminho):
                continue
            rel = os.path.relpath(caminho, app).replace(os.sep, '/')
            nome = nome_framework(rel)
            bundle_dir = os.path.join(fw_dir, nome + '.framework')
            if os.path.exists(bundle_dir):
                raise SystemExit('erro: dois arquivos dão o mesmo framework %s' % nome)
            antigo = install_name(caminho)
            os.makedirs(bundle_dir)
            novo_bin = os.path.join(bundle_dir, nome)
            shutil.move(caminho, novo_bin)
            novo_id = '@rpath/%s.framework/%s' % (nome, nome)
            rodar('install_name_tool', '-id', novo_id, novo_bin)
            bid = '%s.lib.%s' % (bundle_app, re.sub(r'[^A-Za-z0-9-]', '-', nome))
            info = {
                'CFBundleDevelopmentRegion': 'en',
                'CFBundleExecutable': nome,
                'CFBundleIdentifier': bid,
                'CFBundleInfoDictionaryVersion': '6.0',
                'CFBundleName': nome,
                'CFBundlePackageType': 'FMWK',
                'CFBundleShortVersionString': versao,
                'CFBundleSupportedPlatforms': ['iPhoneOS'],
                'CFBundleVersion': build,
                'MinimumOSVersion': maior_versao(minos(novo_bin), '12.0'),
            }
            info.update(dt)
            with open(os.path.join(bundle_dir, 'Info.plist'), 'wb') as f:
                plistlib.dump(info, f, fmt=plistlib.FMT_BINARY)
            if antigo:
                movidos.setdefault(antigo, []).append(novo_id)
            por_folha.setdefault(a, []).append(novo_id)
            print('biblioteca: %s -> Frameworks/%s.framework' % (rel, nome))

    # 3. referências entre bibliotecas e rpaths
    binarios = [exe]
    for d in sorted(os.listdir(fw_dir)):
        if d.endswith('.framework'):
            b = os.path.join(fw_dir, d, d[:-len('.framework')])
            if e_macho(b):
                binarios.append(b)
    for b in binarios:
        usa_rpath = False
        for dep in dependencias(b):
            if dep.startswith('@rpath/'):
                usa_rpath = True
            candidatos = movidos.get(dep) or por_folha.get(os.path.basename(dep), [])
            novo = None
            if len(candidatos) == 1:
                novo = candidatos[0]
            elif len(candidatos) > 1:
                raise SystemExit('erro: %s depende de %s, que existe em mais de um jogo' % (b, dep))
            if novo and novo != dep:
                print('referência: %s: %s -> %s' % (os.path.relpath(b, app), dep, novo))
                rodar('install_name_tool', '-change', dep, novo, b)
                usa_rpath = True
        if (b == exe or usa_rpath) and '@executable_path/Frameworks' not in rpaths(b):
            rodar('install_name_tool', '-add_rpath', '@executable_path/Frameworks', b)
            print('rpath: %s + @executable_path/Frameworks' % os.path.relpath(b, app))

    # 4. tira cabeçalhos dos frameworks embutidos e pastas que ficaram vazias
    for d in os.listdir(fw_dir):
        for sobra in ('Headers', 'PrivateHeaders', 'Modules'):
            p = os.path.join(fw_dir, d, sobra)
            if os.path.islink(p):
                os.unlink(p)
            elif os.path.isdir(p):
                shutil.rmtree(p)
    for raiz, dirs, arquivos in os.walk(app, topdown=False):
        if raiz != app and not os.listdir(raiz):
            os.rmdir(raiz)

    # 5. nenhum Mach-O fora do lugar (o que o App Store Connect recusaria)
    proibidos = []
    for raiz, _, arquivos in os.walk(app):
        for a in arquivos:
            caminho = os.path.join(raiz, a)
            if os.path.islink(caminho) or not e_macho(caminho):
                continue
            if caminho == exe:
                continue
            pai = os.path.dirname(caminho)
            if (os.path.dirname(pai) == fw_dir and pai.endswith('.framework')
                    and a == os.path.basename(pai)[:-len('.framework')]):
                continue
            proibidos.append(os.path.relpath(caminho, app))
    if proibidos:
        raise SystemExit('erro: binários fora de Frameworks/ (o envio seria recusado): %s' % ', '.join(proibidos))
    print('ok: %d frameworks em Frameworks/' % len([d for d in os.listdir(fw_dir) if d.endswith('.framework')]))


if __name__ == '__main__':
    main()

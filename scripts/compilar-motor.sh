#!/usr/bin/env bash
# Compila o motor para iPhone, como o CI do Xash (scripts/gha/build_ios.sh), e instala numa pasta
. "$(dirname "$0")/comum.sh"
registrar motor-compilar

cd "$TRAB/xash"
./waf configure --enable-lto --ios
./waf build
rm -rf "$TRAB/motor-instalado"
./waf install --destdir="$TRAB/motor-instalado"

echo "== instalado:"
(cd "$TRAB/motor-instalado" && find . -type f | sort)

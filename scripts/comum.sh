#!/usr/bin/env bash
# comum.sh: caminhos e funções usados pelos outros scripts (carregado com ".")
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRAB="${TRAB:-$RAIZ/trabalho}"
LOGS="$RAIZ/logs"
mkdir -p "$TRAB" "$LOGS"

# versões fixadas: no Actions já vêm no ambiente; fora dele, lê o arquivo
if [ -z "${XASH_COMMIT:-}" ]; then
	set -a
	# shellcheck disable=SC1090
	. <(grep -E '^[A-Z0-9_]+=' "$RAIZ/versoes.env")
	set +a
fi

APP="$TRAB/app/${APP_NOME}.app"
NCPU="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"

# manda toda a saída do script também para logs/<nome>.log
registrar() {
	exec > >(tee -a "$LOGS/$1.log") 2>&1
}

# baixa um repositório num commit exato, com os submódulos
baixar_repo() { # url commit destino
	local url="$1" commit="$2" destino="$3"
	rm -rf "$destino"
	git init -q "$destino"
	git -C "$destino" remote add origin "$url"
	git -C "$destino" fetch -q --depth 1 origin "$commit"
	git -C "$destino" -c advice.detachedHead=false checkout -q FETCH_HEAD
	if ! git -C "$destino" submodule update -q --init --recursive --depth 1 --jobs 8; then
		echo "submódulos com --depth 1 falharam, tentando completos"
		git -C "$destino" submodule update -q --init --recursive --jobs 8
	fi
	echo "$url @ $(git -C "$destino" rev-parse --short HEAD)"
}

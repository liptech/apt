#!/usr/bin/env bash
#
# Coloca um .deb no lugar certo dentro de pool/ seguindo o layout Debian:
#   pool/<componente>/<inicial>/<pacote>/<arquivo>.deb
#
# Uso:
#   scripts/add-package.sh caminho/para/pacote.deb [...]
#   scripts/add-package.sh --component main pacote.deb
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source repo.conf

COMPONENT="${COMPONENTS%% *}"
files=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --component) COMPONENT="$2"; shift 2 ;;
    -h|--help)   sed -n '2,12p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *)           files+=("$1"); shift ;;
  esac
done

[[ ${#files[@]} -gt 0 ]] || { echo "uso: $0 <pacote.deb> [...]" >&2; exit 1; }
command -v dpkg-deb >/dev/null || { echo "erro: dpkg-deb nao encontrado" >&2; exit 1; }

for deb in "${files[@]}"; do
  [[ -f "$deb" ]] || { echo "erro: arquivo nao encontrado: $deb" >&2; exit 1; }

  name="$(dpkg-deb -f "$deb" Package)"
  version="$(dpkg-deb -f "$deb" Version)"
  arch="$(dpkg-deb -f "$deb" Architecture)"
  [[ -n "$name" ]] || { echo "erro: $deb nao parece um .deb valido" >&2; exit 1; }

  # 'lib*' tem gaveta propria no layout Debian
  if [[ "$name" == lib* ]]; then prefix="${name:0:4}"; else prefix="${name:0:1}"; fi

  dest="pool/$COMPONENT/$prefix/$name"
  target="$dest/${name}_${version}_${arch}.deb"

  mkdir -p "$dest"
  cp -f "$deb" "$target"
  echo "  + $target"
done

echo
echo "pronto. commite e de push para publicar:"
echo "    git add pool && git commit -m 'pacote: $name $version' && git push"

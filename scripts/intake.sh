#!/usr/bin/env bash
#
# Arquiva no pool/ todo .deb que estiver em incoming/.
#
# Le o control de cada pacote para montar o caminho correto, move o arquivo
# e esvazia a caixa de entrada. Um arquivo invalido aborta tudo, sem
# alterar o pool.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source repo.conf

COMPONENT="${COMPONENTS%% *}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\033[1;31merro:\033[0m %s\n' "$*" >&2; exit 1; }

command -v dpkg-deb >/dev/null || die "dpkg-deb nao encontrado"

shopt -s nullglob
incoming=(incoming/*.deb incoming/*.DEB)
shopt -u nullglob

if [[ ${#incoming[@]} -eq 0 ]]; then
  log "caixa de entrada vazia"
  [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "changed=0" >> "$GITHUB_OUTPUT"
  exit 0
fi

log "${#incoming[@]} arquivo(s) na caixa de entrada"

# Primeiro valida tudo; so depois move. Assim um arquivo ruim nao deixa o
# pool pela metade.
for deb in "${incoming[@]}"; do
  dpkg-deb -f "$deb" Package >/dev/null 2>&1 \
    || die "$(basename "$deb") nao e um pacote .deb valido"
done

for deb in "${incoming[@]}"; do
  name="$(dpkg-deb -f "$deb" Package)"
  version="$(dpkg-deb -f "$deb" Version)"
  arch="$(dpkg-deb -f "$deb" Architecture)"

  [[ -n "$name" && -n "$version" && -n "$arch" ]] \
    || die "$(basename "$deb"): control sem Package/Version/Architecture"

  if [[ "$name" == lib* ]]; then prefix="${name:0:4}"; else prefix="${name:0:1}"; fi
  dest="pool/$COMPONENT/$prefix/$name"
  target="$dest/${name}_${version}_${arch}.deb"

  mkdir -p "$dest"
  if [[ -f "$target" ]] && cmp -s "$deb" "$target"; then
    info "ja publicado, descartando da entrada: $name $version ($arch)"
    rm -f "$deb"
    continue
  fi

  [[ -f "$target" ]] && info "substituindo $name $version ($arch)" \
                     || info "novo: $name $version ($arch)"
  mv -f "$deb" "$target"
  info "  -> $target"
done

echo
log "caixa de entrada processada"
[[ -n "${GITHUB_OUTPUT:-}" ]] && echo "changed=1" >> "$GITHUB_OUTPUT"
exit 0

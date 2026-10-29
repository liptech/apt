#!/usr/bin/env bash
#
# Sincroniza pacotes .deb publicados nas Releases de outros repositorios
# da LIPTECH para o pool deste repositorio.
#
# As origens ficam em sync-sources.json:
#   repo       repositorio GitHub (owner/nome)
#   asset      padrao dos assets a baixar (glob), ex.: "*.deb"
#   component  componente do pool (padrao: primeiro de COMPONENTS)
#   keep       quantas versoes de cada pacote manter (padrao: 3)
#   tag        release especifica (padrao: a mais recente)
#
# Uso:
#   scripts/sync-releases.sh          # sincroniza
#   scripts/sync-releases.sh --dry-run
#
# Precisa do gh autenticado (GH_TOKEN no CI).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source repo.conf

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\033[1;31merro:\033[0m %s\n' "$*" >&2; exit 1; }

command -v gh       >/dev/null || die "gh nao encontrado"
command -v dpkg-deb >/dev/null || die "dpkg-deb nao encontrado"
[[ -f sync-sources.json ]]     || die "sync-sources.json nao encontrado"

# ---------------------------------------------------------------- origens
mapfile -t SOURCES < <(python3 -I -c '
import json, sys
default_comp = sys.argv[2].split()[0]
for s in json.load(open(sys.argv[1])):
    print("\t".join([
        s["repo"],
        s.get("asset", "*.deb"),
        s.get("component", default_comp),
        str(s.get("keep", 3)),
        s.get("tag", ""),
    ]))
' sync-sources.json "$COMPONENTS")

[[ ${#SOURCES[@]} -gt 0 ]] || { log "nenhuma origem configurada"; exit 0; }

# Mantem as N versoes mais novas de um pacote, usando a ordenacao do dpkg.
prune_versions() {
  local dir="$1" keep="$2"
  local -a versions=()
  local f v

  for f in "$dir"/*.deb; do
    [[ -e "$f" ]] || continue
    v="$(dpkg-deb -f "$f" Version)"
    [[ " ${versions[*]-} " == *" $v "* ]] || versions+=("$v")
  done
  [[ ${#versions[@]} -gt $keep ]] || return 0

  # ordenacao por insercao usando dpkg --compare-versions (decrescente)
  local -a sorted=()
  local i inserted
  for v in "${versions[@]}"; do
    inserted=0
    for i in "${!sorted[@]}"; do
      if dpkg --compare-versions "$v" gt "${sorted[$i]}"; then
        sorted=("${sorted[@]:0:$i}" "$v" "${sorted[@]:$i}")
        inserted=1; break
      fi
    done
    [[ $inserted -eq 1 ]] || sorted+=("$v")
  done

  for v in "${sorted[@]:$keep}"; do
    for f in "$dir"/*_"$v"_*.deb; do
      [[ -e "$f" ]] || continue
      info "podando versao antiga: $(basename "$f")"
      [[ $DRY_RUN -eq 1 ]] || rm -f "$f"
    done
  done
  rmdir "$dir" 2>/dev/null || true
}

changed=0

for line in "${SOURCES[@]}"; do
  IFS=$'\t' read -r repo asset component keep tag <<< "$line"

  log "$repo (assets: $asset)"

  rel_tag="$tag"
  if [[ -z "$rel_tag" ]]; then
    rel_tag="$(gh release view --repo "$repo" --json tagName --jq .tagName 2>/dev/null || true)"
  fi
  if [[ -z "$rel_tag" ]]; then
    info "sem release publicada; pulando"
    continue
  fi
  info "release: $rel_tag"

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  if ! gh release download "$rel_tag" --repo "$repo" --pattern "$asset" --dir "$tmp" 2>/dev/null; then
    info "nenhum asset casou com '$asset'; pulando"
    rm -rf "$tmp"; continue
  fi

  # Confere contra o SHA256SUMS da release, quando existir.
  if gh release download "$rel_tag" --repo "$repo" --pattern 'SHA256SUMS' --dir "$tmp" 2>/dev/null; then
    for deb in "$tmp"/*.deb; do
      [[ -e "$deb" ]] || continue
      base="$(basename "$deb")"
      want="$(awk -v b="$base" '$2 ~ ("/" b "$") || $2 == b {print $1; exit}' "$tmp/SHA256SUMS")"
      if [[ -n "$want" ]]; then
        got="$(sha256sum "$deb" | awk '{print $1}')"
        [[ "$want" == "$got" ]] || die "SHA256 divergente para $base (release: $want / baixado: $got)"
        info "sha256 confere: $base"
      else
        info "sem sha256 publicado para $base"
      fi
    done
  fi

  for deb in "$tmp"/*.deb; do
    [[ -e "$deb" ]] || continue
    name="$(dpkg-deb -f "$deb" Package)"
    version="$(dpkg-deb -f "$deb" Version)"
    arch="$(dpkg-deb -f "$deb" Architecture)"

    if [[ "$name" == lib* ]]; then prefix="${name:0:4}"; else prefix="${name:0:1}"; fi
    dest="pool/$component/$prefix/$name"
    target="$dest/${name}_${version}_${arch}.deb"

    if [[ -f "$target" ]] && cmp -s "$deb" "$target"; then
      info "ja publicado: $name $version ($arch)"
      continue
    fi

    info "novo: $name $version ($arch)"
    if [[ $DRY_RUN -eq 0 ]]; then
      mkdir -p "$dest"
      cp -f "$deb" "$target"
    fi
    changed=1

    prune_versions "$dest" "$keep"
  done

  rm -rf "$tmp"
  trap - RETURN
done

echo
if [[ $changed -eq 1 ]]; then
  log "houve mudanca no pool"
else
  log "nada novo"
fi

# Para o workflow saber se precisa publicar.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "changed=$changed" >> "$GITHUB_OUTPUT"
fi
exit 0

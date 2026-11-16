#!/usr/bin/env bash
#
# Poda versoes antigas do pool conforme keep.conf.
#
# Uso:
#   scripts/prune-packages.sh              # aplica todas as regras de keep.conf
#   scripts/prune-packages.sh likenotes 1  # poda um pacote especifico
#
# Formato de keep.conf: <pacote> <quantidade>
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }

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

  local -a sorted=()
  local i inserted
  for v in "${versions[@]}"; do
    inserted=0
    for i in "${!sorted[@]}"; do
      if dpkg --compare-versions "$v" gt "${sorted[$i]}"; then
        sorted=("${sorted[@]:0:$i}" "$v" "${sorted[@]:$i}")
        inserted=1
        break
      fi
    done
    [[ $inserted -eq 1 ]] || sorted+=("$v")
  done

  for v in "${sorted[@]:$keep}"; do
    for f in "$dir"/*_"$v"_*.deb; do
      [[ -e "$f" ]] || continue
      info "podando versao antiga: $(basename "$f")"
      rm -f "$f"
    done
  done
  rmdir "$dir" 2>/dev/null || true
}

prune_package() {
  local package="$1" keep="$2" dir
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    log "mantendo $keep versao(oes) de $package em $dir"
    prune_versions "$dir" "$keep"
  done < <(find pool -mindepth 3 -maxdepth 3 -type d -name "$package" 2>/dev/null)
}

if [[ $# -gt 0 ]]; then
  prune_package "$1" "${2:-1}"
  exit 0
fi

[[ -f keep.conf ]] || exit 0

while read -r package keep; do
  [[ -z "${package:-}" ]] && continue
  [[ "$package" == \#* ]] && continue
  [[ -n "${keep:-}" ]] || keep=1
  prune_package "$package" "$keep"
done < keep.conf

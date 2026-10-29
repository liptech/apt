#!/usr/bin/env bash
#
# Monta o repositorio APT estatico em ./public a partir de ./pool e ./site.
#
# Uso:
#   scripts/build-repo.sh              # monta e, se houver chave, assina
#   SKIP_SIGN=1 scripts/build-repo.sh  # monta sem assinar (teste local)
#
# Assinatura: exporta GPG_KEY_ID (e GPG_PASSPHRASE, se a chave tiver senha).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=../repo.conf
source repo.conf

OUT="$ROOT/public"
SKIP_SIGN="${SKIP_SIGN:-0}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merro:\033[0m %s\n' "$*" >&2; exit 1; }

command -v apt-ftparchive >/dev/null || die "apt-ftparchive nao encontrado (instale o pacote apt-utils)"

log "limpando $OUT"
rm -rf "$OUT"
mkdir -p "$OUT"

log "copiando pool/"
cp -a pool "$OUT/pool"

deb_count="$(find "$OUT/pool" -name '*.deb' -type f | wc -l)"
log "$deb_count pacote(s) .deb no pool"

cd "$OUT"

# ---------------------------------------------------------------- indices
for comp in $COMPONENTS; do
  for arch in $ARCHITECTURES; do
    dir="dists/$SUITE/$comp/binary-$arch"
    mkdir -p "$dir"
    log "gerando $dir/Packages"
    apt-ftparchive --arch "$arch" packages "pool/$comp" > "$dir/Packages"
    gzip -9cn  "$dir/Packages" > "$dir/Packages.gz"
    xz  -9c    "$dir/Packages" > "$dir/Packages.xz"

    # Release por arquitetura: alguns clientes antigos esperam este arquivo.
    cat > "$dir/Release" <<EOF
Archive: $SUITE
Component: $comp
Origin: $ORIGIN
Label: $LABEL
Architecture: $arch
EOF
  done
done

# ---------------------------------------------------------------- Release
log "gerando dists/$SUITE/Release"
apt-ftparchive \
  -o "APT::FTPArchive::Release::Origin=$ORIGIN" \
  -o "APT::FTPArchive::Release::Label=$LABEL" \
  -o "APT::FTPArchive::Release::Suite=$SUITE" \
  -o "APT::FTPArchive::Release::Codename=$CODENAME" \
  -o "APT::FTPArchive::Release::Components=$COMPONENTS" \
  -o "APT::FTPArchive::Release::Architectures=$ARCHITECTURES" \
  -o "APT::FTPArchive::Release::Description=$DESCRIPTION" \
  release "dists/$SUITE" > "dists/$SUITE/Release.tmp"
mv "dists/$SUITE/Release.tmp" "dists/$SUITE/Release"

# ---------------------------------------------------------------- assinatura
if [[ "$SKIP_SIGN" == "1" ]]; then
  log "SKIP_SIGN=1 - repositorio NAO assinado"
elif [[ -n "${GPG_KEY_ID:-}" ]]; then
  log "assinando Release com a chave $GPG_KEY_ID"
  gpg_args=(--batch --yes --local-user "$GPG_KEY_ID")
  if [[ -n "${GPG_PASSPHRASE:-}" ]]; then
    gpg_args+=(--pinentry-mode loopback --passphrase "$GPG_PASSPHRASE")
  fi

  rm -f "dists/$SUITE/Release.gpg" "dists/$SUITE/InRelease"
  gpg "${gpg_args[@]}" --armor --detach-sign \
      -o "dists/$SUITE/Release.gpg" "dists/$SUITE/Release"
  gpg "${gpg_args[@]}" --clearsign \
      -o "dists/$SUITE/InRelease" "dists/$SUITE/Release"

  log "exportando chave publica"
  gpg --export --armor "$GPG_KEY_ID" > "$KEYRING_NAME.asc"
  gpg --export         "$GPG_KEY_ID" > "$KEYRING_NAME.gpg"
else
  die "GPG_KEY_ID nao definido. Defina a chave ou use SKIP_SIGN=1."
fi

# ---------------------------------------------------------------- site
cd "$ROOT"
log "montando pagina"
"$ROOT/scripts/render-site.sh" "$OUT"

log "pronto: $OUT"
find "$OUT" -maxdepth 2 -mindepth 1 | sort | sed 's|^|    |'

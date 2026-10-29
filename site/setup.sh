#!/usr/bin/env bash
#
# Configura o repositorio APT da LIPTECH neste sistema.
#
#   curl -fsSL https://{{DOMAIN}}/setup.sh | sudo bash
#
# O que faz:
#   1. instala curl/gnupg/ca-certificates, se faltarem
#   2. baixa a chave publica para /etc/apt/keyrings/{{KEYRING}}.gpg
#   3. grava /etc/apt/sources.list.d/liptech.list com signed-by
#   4. roda apt update
#
set -euo pipefail

DOMAIN="{{DOMAIN}}"
KEYRING="{{KEYRING}}"
SUITE="{{SUITE}}"
COMPONENTS="{{COMPONENTS}}"

KEYRING_PATH="/etc/apt/keyrings/${KEYRING}.gpg"
LIST_PATH="/etc/apt/sources.list.d/liptech.list"

say()  { printf '\033[1;36m[liptech]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[liptech] erro:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "${EUID:-$(id -u)}" -eq 0 ]] || fail "execute como root (use sudo)."
command -v apt-get >/dev/null || fail "este script e para sistemas com APT (Debian/Ubuntu)."

say "instalando dependencias"
apt-get update -qq
apt-get install -y -qq curl gnupg ca-certificates >/dev/null

say "baixando chave de assinatura"
install -d -m 0755 /etc/apt/keyrings
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fsSL "https://${DOMAIN}/${KEYRING}.asc" -o "$tmp"
gpg --dearmor < "$tmp" > "${KEYRING_PATH}.new"
mv "${KEYRING_PATH}.new" "$KEYRING_PATH"
chmod 0644 "$KEYRING_PATH"

fpr="$(gpg --show-keys --with-colons "$KEYRING_PATH" | awk -F: '/^fpr:/{print $10; exit}')"
say "fingerprint: ${fpr}"

say "registrando repositorio"
arch="$(dpkg --print-architecture)"
cat > "$LIST_PATH" <<EOF
deb [arch=${arch} signed-by=${KEYRING_PATH}] https://${DOMAIN} ${SUITE} ${COMPONENTS}
EOF
chmod 0644 "$LIST_PATH"

say "atualizando indices"
apt-get update -qq -o Dir::Etc::sourcelist="$LIST_PATH" \
                   -o Dir::Etc::sourceparts="-" \
                   -o APT::Get::List-Cleanup="0"

say "pronto. veja os pacotes em https://${DOMAIN}"

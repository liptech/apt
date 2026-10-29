# Repositório APT da LIPTECH

Repositório APT estático, assinado com GPG e servido pelo GitHub Pages em
**<https://apt.liptech.com.br>**.

Os pacotes ficam versionados neste repositório (`pool/`). A cada push, o
GitHub Actions regenera os índices, assina o `Release` e publica o site.

## Instalar em uma máquina

```bash
curl -fsSL https://apt.liptech.com.br/setup.sh | sudo bash
```

Ou manualmente:

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://apt.liptech.com.br/liptech-archive-keyring.asc \
  | sudo gpg --dearmor -o /etc/apt/keyrings/liptech-archive-keyring.gpg

ARCH=$(dpkg --print-architecture)
KEY=/etc/apt/keyrings/liptech-archive-keyring.gpg
echo "deb [arch=$ARCH signed-by=$KEY] https://apt.liptech.com.br stable main" \
  | sudo tee /etc/apt/sources.list.d/liptech.list

sudo apt update
```

## Publicar um pacote

```bash
scripts/add-package.sh caminho/para/pacote_1.2.3_amd64.deb
git add pool
git commit -m "pacote: nome 1.2.3"
git push
```

O workflow faz o resto. Em um ou dois minutos o pacote está no ar.

Para remover um pacote, apague o `.deb` de `pool/` e dê push — os índices são
regenerados do zero a cada publicação.

## Estrutura

```
pool/main/<inicial>/<pacote>/*.deb   pacotes (fonte da verdade)
site/index.template.html             página, com placeholders {{...}}
site/assets/                         logos e ícones LIPTECH
site/setup.sh                        instalador de um comando
scripts/build-repo.sh                monta e assina ./public
scripts/render-site.sh               renderiza a página e a lista de pacotes
scripts/add-package.sh               coloca um .deb no lugar certo do pool
repo.conf                            suíte, componentes, arquiteturas, domínio
.github/workflows/publish.yml        build + assinatura + deploy no Pages
```

Nada em `public/` é versionado: ele é gerado a cada build.

## Build local

```bash
# só para ver a página, sem assinar
SKIP_SIGN=1 scripts/build-repo.sh
python3 -m http.server -d public 8899

# build completo, assinando
export GPG_KEY_ID=16AC1A9E1506B704C5C4815D177E8556C2B47AA9
export GPG_PASSPHRASE='...'
scripts/build-repo.sh
```

## Chave de assinatura

```
Fingerprint  16AC 1A9E 1506 B704 C5C4  815D 177E 8556 C2B4 7AA9
Key ID       177E8556C2B47AA9
UID          LIPTECH Archive Signing Key (apt.liptech.com.br) <liptech@gmail.com>
Tipo         RSA 4096, sign-only, sem expiração
```

A chave privada vive nos secrets do repositório:

| Secret | Conteúdo |
|---|---|
| `GPG_PRIVATE_KEY` | chave privada em ASCII armor |
| `GPG_PASSPHRASE`  | senha da chave privada |

O backup da chave (privada, senha e certificado de revogação) **não está neste
repositório** — ele foi gerado fora do Git e deve ser guardado em cofre.

## Adicionar uma arquitetura ou suíte

Edite `ARCHITECTURES` ou `SUITE` em `repo.conf` e dê push. Os índices passam a
ser gerados para a nova configuração na publicação seguinte.

## Domínio

`apt.liptech.com.br` está ativo, com certificado Let's Encrypt e HTTPS
obrigatório. O DNS é um CNAME na Cloudflare, **sem proxy**:

| Tipo  | Nome | Destino             | Proxy                      |
|-------|------|---------------------|----------------------------|
| CNAME | apt  | `liptech.github.io` | DNS only (nuvem cinza)     |

O proxy precisa continuar desligado: com a nuvem laranja o GitHub não
consegue renovar o certificado.

O arquivo `site/CNAME` é o que amarra o domínio a este repositório — se ele
sumir do artefato publicado, o GitHub desfaz o domínio personalizado.

Com domínio próprio o site fica na **raiz** (`https://apt.liptech.com.br/`),
não em `/apt`.

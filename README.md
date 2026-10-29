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

## Publicar pela página /admin

<https://apt.liptech.com.br/admin/> — arraste um `.deb`, clique em Publicar.

O GitHub Pages serve só arquivos estáticos, então **não há servidor** para
receber o upload: a página fala direto com a API do GitHub usando um token que
você digita. Crie um [token de acesso pessoal fine-grained][pat] com
**Contents: Read and write** restrito a `liptech/apt`, e dê validade curta.

[pat]: https://github.com/settings/personal-access-tokens/new

O token fica só na aba aberta, a menos que você marque “lembrar neste
navegador”. Ele nunca passa por servidor nosso — vai do seu navegador para
`api.github.com`. A página é pública (qualquer um abre a URL), mas sem token
não faz nada.

Como arquivos de pacote passam de 1 MB, a página usa a Git Data API
(blob → tree → commit → ref) em vez da Contents API.

### A caixa de entrada

Por baixo, a página só joga o arquivo em `incoming/`. Quem faz o trabalho é o
workflow `intake.yml`: ele lê o `control` de cada `.deb`, renomeia para
`<pacote>_<versão>_<arquitetura>.deb`, arquiva no pool, esvazia a entrada e
publica.

Isso significa que **a página é opcional**. Qualquer coisa que coloque um
arquivo em `incoming/` serve, sem token nenhum:

- a interface do GitHub, em **Add file → Upload files** (já autenticada);
- `git add incoming/pacote.deb && git push`.

Um arquivo que não seja um `.deb` válido faz o workflow falhar antes de tocar
no pool, e o repositório no ar continua intacto.

## Sincronização automática de releases

Pacotes que já são publicados como Release em outro repositório da LIPTECH não
precisam ser copiados à mão. As origens ficam em `sync-sources.json`:

```json
[
  { "repo": "liptech/winbox-installers", "asset": "*.deb", "component": "main", "keep": 2 }
]
```

| Campo | Significado |
|---|---|
| `repo` | repositório GitHub de origem |
| `asset` | padrão dos assets a baixar (glob) |
| `component` | componente do pool (padrão: `main`) |
| `keep` | quantas versões manter no pool (padrão: 3) |
| `tag` | release específica (padrão: a mais recente) |

O workflow `sync-releases.yml` roda **todo dia às 06:00 UTC** (03:00 em
Brasília) e também sob demanda em Actions → Sincronizar releases. Ele:

1. lê a release mais recente de cada origem;
2. confere o `SHA256SUMS` da release, quando existir, e **aborta** se divergir;
3. copia os `.deb` novos para o pool, com o nome no padrão Debian;
4. poda as versões mais antigas além de `keep`;
5. commita e chama o workflow de publicação.

Se nada mudou, ele não commita nem publica.

Para acompanhar outro repositório, acrescente uma entrada em
`sync-sources.json`. Para testar sem alterar nada:

```bash
scripts/sync-releases.sh --dry-run
```

Não é preciso token nenhum além do `GITHUB_TOKEN` do próprio Actions. Como um
push feito com esse token não dispara outros workflows, `sync-releases.yml`
chama `publish.yml` explicitamente via `workflow_call` — por isso o
`publish.yml` aceita esse gatilho.

## Segurança

### Quem consegue publicar ou apagar

Só quem tem acesso de escrita a `liptech/apt` — hoje apenas a conta `liptech`.
A página `/admin` é pública, mas **inerte sem token**: toda escrita passa pela
API do GitHub, que recusa com `401` quem não tiver credencial válida. Os botões
da página são conveniência de interface, não controle de acesso; burlar o
JavaScript não concede nada.

Um fork ou pull request de terceiros **não executa nenhum workflow**: nenhum
deles usa `pull_request` ou `pull_request_target`. É o que impede o ataque
clássico de PR malicioso que lê secrets — a chave de assinatura nunca fica
acessível a código vindo de fora.

### A chave de assinatura

`GPG_PRIVATE_KEY` e `GPG_PASSPHRASE` só são visíveis para workflows deste
repositório, rodando em `main`. Quem tiver acesso de escrita pode, em
princípio, escrever um workflow que a exfiltre — isso é inerente ao acesso de
escrita, não uma falha de configuração. Por isso o acesso ao repositório é que
deve ser tratado como o segredo.

A assinatura garante **procedência, não inocuidade**: ela prova que o pacote
saiu daqui, não que seja seguro. Um pacote ruim publicado por quem tem acesso
seria assinado normalmente.

### O token da página /admin

É o elo mais frágil, porque vive no navegador. Use sempre:

- token **fine-grained**, com `Contents: Read and write` **só** em `liptech/apt`;
- validade curta;
- sem marcar “lembrar neste navegador” em máquina compartilhada.

Se vazar, o estrago fica contido a este repositório de pacotes públicos — nada
de outros repositórios da conta.

A página foi endurecida contra roubo desse token:

| Medida | Efeito |
|---|---|
| Nenhum JavaScript externo | sem CDN, não há cadeia de suprimentos para comprometer |
| CSP com hash do script | só o script exato do build roda; qualquer injeção é bloqueada |
| `connect-src` restrito | mesmo um script injetado não conseguiria enviar o token para fora |
| Dados via `textContent` | nenhum valor dinâmico entra no DOM como HTML |
| `default-src 'none'` | nada carrega por omissão |
| Recusa de iframe | evita clickjacking, já que o Pages não deixa definir cabeçalhos |
| `noindex` | não aparece em buscadores |

O hash da CSP é recalculado a cada build por `scripts/render-site.sh`, depois
da substituição dos placeholders — mexer no script sem rebuildar faz a página
parar de funcionar, em vez de rodar sem proteção.

### A página não sabe quem é você

Não há login, conta nem sessão: é um arquivo estático. Quem identifica a conta
é o **GitHub**, a partir do token — a página só encaminha. Na prática, *o token
é a identidade*: quem o tiver é você, aos olhos da API, sem segundo fator.

Depois de clicar em Verificar, a página mostra a conta dona do token ao lado da
caixa, para você conferir que é o token que imagina ser. O botão **Esquecer**
apaga o token do navegador — use sempre antes de sair de uma máquina que não é
sua, e revogue o token em <https://github.com/settings/tokens> por garantia.

### Usando de outro computador

Nada está preso à sua máquina: a URL abre em qualquer lugar e funciona assim
que você colar um token. Isso vale nos dois sentidos — um token copiado também
funciona em qualquer lugar.

Em máquina que não é sua, a ordem de preferência é:

1. **Não usar a página.** Vá em [Add file → Upload files][up] no GitHub e
   arraste o `.deb` para `incoming/`. Você entra com seu login normal, com 2FA,
   e não deixa credencial nenhuma para trás. O resultado é idêntico.
2. Se preferir a página, crie um token **só para aquela ocasião**, com validade
   de um dia, não marque “lembrar”, e revogue ao terminar.

[up]: https://github.com/liptech/apt/upload/main/incoming

Nunca carregue o token em arquivo de texto, e-mail ou mensagem — se precisar
levá-lo entre máquinas, use um gerenciador de senhas.

### O que isto não protege

Quem instala o repositório confia na LIPTECH. A assinatura protege o caminho
entre o servidor e a máquina do usuário: um intermediário não consegue injetar
nem alterar pacotes. Não protege contra um pacote ruim publicado por dentro.

## Estrutura

```
pool/main/<inicial>/<pacote>/*.deb   pacotes (fonte da verdade)
site/index.template.html             página, com placeholders {{...}}
site/assets/                         logos e ícones LIPTECH
site/setup.sh                        instalador de um comando
scripts/build-repo.sh                monta e assina ./public
scripts/render-site.sh               renderiza a página e a lista de pacotes
scripts/add-package.sh               coloca um .deb no lugar certo do pool
scripts/sync-releases.sh             traz .deb das Releases de outros repos
scripts/intake.sh                    arquiva no pool o que chega em incoming/
site/admin/index.template.html       página de publicação
incoming/                            caixa de entrada de .deb
repo.conf                            suíte, componentes, arquiteturas, domínio
sync-sources.json                    repositórios acompanhados automaticamente
.github/workflows/publish.yml        build + assinatura + deploy no Pages
.github/workflows/sync-releases.yml  sincronização diária das releases
.github/workflows/intake.yml         arquiva a caixa de entrada e publica
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

## Catálogo da loja (AppStream)

O build gera `dists/stable/main/dep11/Components-amd64.yml.gz`, com o componente
LikeAD Admin, e inclui seus hashes no Release antes da assinatura GPG.
Imagens e ícone são publicados em `appstream/media/likead-admin/`.
O código-fonte e o pacote LikeAD não são copiados para este repositório por essa
integração: o catálogo serve também para refinar a apresentação do `.deb` local.

Os clientes precisam configurar este repositório, atualizar os índices APT e ter
AppStream/GNOME Software. Um computador que receba só um `.deb` isolado continua
sem conhecer o catálogo antes da instalação. `setup.sh` configura os índices;
após atualizar, reabra a loja para renovar sua apresentação.

Metadados de aplicativos ficam em `site/appstream/components/<componente>/<arquitetura>/`.
O gerador valida os XMLs e os converte com `appstreamcli`, sem executar os aplicativos.

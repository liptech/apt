# Caixa de entrada

Qualquer `.deb` colocado nesta pasta é arquivado automaticamente no `pool/`,
com o nome e o caminho corretos, e publicado em seguida. O arquivo some daqui
depois de processado.

Três formas de colocar algo aqui:

- a página <https://apt.liptech.com.br/admin/>;
- a interface do GitHub: **Add file → Upload files**, arrastando para esta pasta;
- `git add incoming/pacote.deb && git push`.

Não é preciso acertar o nome do arquivo: o workflow lê o `control` do pacote e
renomeia para `<pacote>_<versão>_<arquitetura>.deb`.

Um arquivo que não seja um `.deb` válido faz o workflow falhar, e nada é
publicado — o repositório no ar continua intacto.

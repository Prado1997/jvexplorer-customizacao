# JVExplorer — dashboard HTML5

Visualizador de fontes de arquivos `.jar` dentro do Sankhya OM. O JAR vem do
cadastro de **Módulos Java** (`TSIMOD`/`TSIJAR`) ou de upload manual; a tela
descompila as classes sob demanda e permite navegar em pacotes e classes como num
IDE. **Somente consulta**: nada é gravado em banco.

## Comportamento

| Aspecto | Como funciona |
|---|---|
| Origem do JAR | Módulos Java da base (só SUP) ou upload manual |
| Persistência | Nenhuma escrita. O JAR vai para `<java.io.tmpdir>/jvexplorer/<idSessao>/` |
| JARs abertos | Um por sessão. Escolher outro JAR recarrega o BLOB e reindexa |
| Ciclo de vida | Ao expirar/encerrar a sessão o diretório é apagado (`HttpSessionBindingListener`) e o processo recomeça |
| Descompilação | CFR, sob demanda, ao clicar na classe; resultado em cache na sessão |
| Fonte embutido | Se o JAR contém os `.java` (badge `src`), exibe o original em vez do bytecode reconstruído |
| Banco de dados | Somente `SELECT` em `TSIMOD` e `TSIJAR`, com `PreparedStatement` e bind |
| Permissão | Consulta à base restrita ao usuário **SUP** (`AuthenticationInfo.isSUP()`); upload liberado |

Badges na árvore: `src` = fonte original do JAR · `dec` = reconstruído pelo CFR ·
`arq` = recurso do JAR (xml, sql, properties, MANIFEST).

## Arquitetura

Padrão 4 (**JSP Unificado**): `main.jsp` serve a interface quando chamado sem
parâmetros e responde JSON quando chamado com `?action=`.

```
GET  ?action=env                                 -> diagnóstico (CFR, banco, limites, tmpdir)
GET  ?action=modulos&q=<termo>                   -> módulos java da base (SUP)
GET  ?action=jars&mod=<codModulo>                -> jars do módulo (SUP)
GET  ?action=abrir&mod=<cod>&jar=<cod>           -> carrega o BLOB, extrai e indexa (SUP)
POST ?action=probe                               -> fixa a rota que aceita POST
POST ?action=upload&nome=&chunk=N&final=0|1      -> bloco binário de 4 MB
GET  ?action=source&path=<path do índice>        -> fonte (embutido ou descompilado)
GET  ?action=reset                               -> descarta o JAR da sessão
```

Não existe módulo Java importado nem botão de ação. Classes de Módulo Java (TSIJAR)
ficam num classloader filho, invisível ao JSP — por isso o CFR é carregado por um
`URLClassLoader` isolado sobre o JAR em `lib/`, invocado por reflection
(`org.benf.cfr.reader.api.CfrDriver`, com fallback para `Main.main`).

O acesso ao banco também é por reflection, e por um motivo diferente: um `import`
de classe Sankhya que não resolva impede a **compilação do JSP** e derruba a tela
inteira, inclusive o upload. A ordem de resolução da conexão é:

1. `-Djvexplorer.ds=<jndi>`, quando informado — vai direto ao `DataSource`
2. JAPE: `JapeSession.open()` → `EntityFacadeFactory.getDWFFacade().getJdbcWrapper()`
   → `openSession()` / `getConnection()`, fechando com `closeSession()` e `JapeSession.close(handle)`
3. `DataSource` por JNDI, nos nomes usuais (`java:/jdbc/sankhyaDS`, `java:jboss/datasources/SankhyaDS`, …)

O dialeto sai de `DatabaseMetaData.getDatabaseProductName()`: o tamanho do BLOB usa
`DBMS_LOB.GETLENGTH` no Oracle e `DATALENGTH` no SQL Server.

O upload vai em blocos de 4 MB porque o `max-post-size` padrão do WildFly é 10 MB.

## Build

```bash
./gradlew html5-jvexplorer
```

Gera `dist/Dashboards/jvexplorer.zip` com:

```
jvexplorer.zip
├── main.jsp
├── jvexplorer_component.xml
└── lib/
    └── cfr-0.152.jar          <- injetado pela configuration 'decompiler'
```

## Import no Sankhya

1. `Configurações > Avançado > Construtor de Componentes de BI`
2. Incluir novo componente — Título `JVExplorer`, categoria a critério
3. Aba **Design** → arrastar **Controles > HTML5** para a área de trabalho
4. Editar o componente HTML5 → arquivo de entrada: `main.jsp`
5. Salvar e fazer o upload de `dist/Dashboards/jvexplorer.zip`
6. Vincular o gadget a um painel no `Construtor de Dashboards`

Alternativa: importar `jvexplorer_component.xml` pelo botão **Importar XML** do
Construtor, que já traz o nível e o `entryPoint`.

> Se o ambiente exigir o nome no padrão `NNN_html5Component.zip` (`NNN` = código do
> componente), renomeie o ZIP antes do upload. Se o importador exigir o JSP dentro de
> uma subpasta, mova `main.jsp` e `lib/` para `index/` e ajuste o `entryPoint` do XML
> para `index/main.jsp`.

## Se o CFR não for encontrado

A tela abre em modo reduzido (fontes embutidos e recursos de texto continuam
funcionando) e mostra o aviso. Abra **Diagnóstico** no topo da tela: ele lista todos
os caminhos verificados e o que foi resolvido.

Rota manual, quando o importador rejeita o binário dentro do ZIP — copie o
`cfr-0.152.jar` para uma pasta do servidor e suba o WildFly com:

```
-Djvexplorer.cfr.jar=/opt/sankhya/lib/cfr-0.152.jar
```

Detalhes da ordem de resolução: `jvexplorer/Dashboards/html5/jvexplorer/lib/README.md`.

## Limites e proteções

| Limite | Valor | Motivo |
|---|---|---|
| Tamanho do JAR | 96 MB | teto de disco temporário por sessão |
| Conteúdo extraído | 512 MB | proteção contra zip bomb |
| Entradas no JAR | 60.000 | proteção contra zip bomb |
| Cache de fontes | 400 arquivos por sessão | limita memória da sessão |
| JARs abertos | 1 por sessão | teto de disco temporário por sessão |
| Bloco de upload | 4 MB | abaixo do `max-post-size` padrão |

Outras proteções:

- Assinatura `PK\x03\x04` validada antes de abrir o arquivo
- Zip-slip bloqueado: entradas absolutas ou com `../` são descartadas
- `action=source` só aceita paths presentes no índice da sessão — o cliente nunca
  monta um `File` no servidor
- `modulos`, `jars` e `abrir` exigem SUP no servidor: esconder o filtro no cliente
  é só cosmético
- Termo de busca vai por bind com `%` e `_` escapados (`ESCAPE ''`); nenhum SQL
  é montado por concatenação
- Classes internas (`Outer$Inner.class`) não aparecem na árvore: saem no fonte da
  classe externa, como num IDE

## Troubleshooting

| Sintoma | Causa provável |
|---|---|
| `Nenhuma rota aceita POST neste ambiente` | `html5component.mge` recusa POST e o caminho direto do JSP está bloqueado por filtro. Verifique a rota mostrada em Diagnóstico |
| `HTTP 413` no upload | `max-post-size` do http-listener abaixo de 4 MB |
| `Descompilador não encontrado` | Ver seção do CFR acima |
| Aba **Módulos da base** desabilitada | Usuário não é SUP, ou `AuthenticationInfo` não chegou à thread do JSP. Veja `usuario SUP` em Diagnóstico |
| `Sem conexao com o banco` | Nem JAPE nem os nomes JNDI resolveram. Informe `-Djvexplorer.ds=<jndi>` e confira `conexao` em Diagnóstico |
| `O jar esta cadastrado sem conteudo` | `TSIJAR.ARQUIVO` nulo para aquele registro |
| `O CFR não produziu fonte para esta classe` | Bytecode corrompido ou ofuscado; a classe é a única afetada |
| Acentos trocados no fonte | Fonte não é UTF-8 nem ISO-8859-1. A leitura tenta UTF-8 estrito e cai para ISO-8859-1 |

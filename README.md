# JVExplorer

Dashboard HTML5 para o **Sankhya OM** que abre um arquivo `.jar` e navega nos fontes como num IDE — direto do cadastro de **Módulos Java** da base ou por upload manual.

**Somente consulta:** nada é gravado em banco. O jar vive no diretório temporário da sessão e é apagado quando ela expira.

---

## O que o dashboard faz

| Recurso | Descrição |
|---|---|
| **Módulos da base** | Lista os Módulos Java cadastrados (`TSIMOD`/`TSIJAR`), filtra por nome ou pacote e abre o jar direto do BLOB. Restrito ao usuário **SUP** |
| **Upload manual** | Envia um `.jar` do disco em blocos de 4 MB, sem passar pelo cadastro |
| **Árvore de pacotes** | Pacotes iniciam recolhidos e abrem sob demanda. Classes internas (`Outer$Inner`) ficam no fonte da classe externa |
| **Descompilação sob demanda** | Ao clicar na classe, o CFR reconstrói o fonte; o resultado fica em cache na sessão |
| **Fonte original** | Se o jar embute os `.java`, exibe o original em vez do bytecode reconstruído |
| **Abas e busca** | Vários arquivos abertos ao mesmo tempo, **Copiar código** e busca global (`Ctrl K`) por nome, pacote e conteúdo já aberto |
| **Baixar jar** | Faz o download do jar aberto a partir da base |
| **Análise do jar** | No **Diagnóstico**: resumo por papel Sankhya, tabelas lidas/gravadas e ficha de cada classe, agrupada por pacote |
| **Ambiente** | No **Diagnóstico**: CFR resolvido, conexão com o banco, usuário SUP, limites e `tmpdir` |
| **Temas** | Escuro e claro na paleta Acorde (Design System Sankhya), com layout responsivo |

Badges na árvore: `SRC` fonte original · `DEC` reconstruído pelo CFR · `ARQ` recurso de texto (xml, sql, properties, MANIFEST).

### Análise do jar

Leitura estática do bytecode — nenhuma classe é carregada ou executada. Para cada classe:

| Item | Origem |
|---|---|
| Papel | Herança, interfaces e anotações: `EventoProgramavelJava`, `AcaoRotinaJava`, `ScheduledAction`, `RegraNegocioJava`, `@ActionButton`, `@Listener`, `@Job`, `@BusinessRule`, EJB |
| Tabelas lidas / gravadas | SQL literal da classe (`SELECT`, `INSERT`, `UPDATE`, `DELETE`, `MERGE`) em tabelas `T*`, `V*` e `AD_*` |
| Escrita via API | Chamadas de gravação JAPE/JDBC (`create`, `prepareToUpdate`, `delete`, `executeUpdate`…) |
| Entidades prováveis | Literais com formato de entidade em classes que usam JAPE |
| APIs, métodos e dependências | APIs Sankhya usadas, métodos públicos e classes do próprio jar referenciadas |

> SQL montado dinamicamente não é detectado, e entidades são inferidas — por isso aparecem como *prováveis*.

---

## Instalação na base

### 1. Gerar o pacote

```bash
./gradlew html5-jvexplorer
```

Gera `dist/Dashboards/jvexplorer.zip`:

```
jvexplorer.zip
├── main.jsp                    Interface + API (?action=)
├── jvexplorer_component.xml    Definição do gadget
└── lib/
    └── cfr-0.152.jar           Descompilador
```

### 2. Importar no Sankhya OM

1. Acesse `Configurações > Avançado > Construtor de Componentes de BI`
2. Inclua um componente com título `JVExplorer`
3. Na aba **Design**, arraste **Controles > HTML5** para a área de trabalho
4. Edite o componente e informe o arquivo de entrada `main.jsp`
5. Salve e faça o upload de `jvexplorer.zip`
6. Em `Configurações > Avançado > Construtor de Dashboards`, vincule o gadget a um painel

> Alternativa aos passos 3 e 4: botão **Importar XML** com `jvexplorer_component.xml`, que já traz o nível e o `entryPoint`.
>
> Se o ambiente exigir o nome `NNN_html5Component.zip` (`NNN` = código do componente), renomeie o ZIP antes do upload.

### 3. Conferir

Abra o dashboard e clique em **Diagnóstico › Ambiente**. O ponto verde indica CFR encontrado. Se o importador rejeitar o binário do ZIP, copie o `cfr-0.152.jar` para o servidor e suba o WildFly com:

```
-Djvexplorer.cfr.jar=/opt/sankhya/lib/cfr-0.152.jar
```

---

## Como usar

**Abrir um jar da base** (usuário SUP)

1. Em **Módulos da base**, busque o módulo por nome ou pacote
2. Clique no módulo e escolha o jar
3. O card do jar oferece **Baixar jar** e **Fechar**

**Abrir um jar do disco**

1. Em **Upload**, arraste o `.jar` ou clique em *selecione o arquivo*
2. O card oferece **Trocar jar** e **Descartar**

**Navegar**

1. Expanda os pacotes na **Estrutura** e clique na classe
2. O fonte abre em aba no painel da direita; **Copiar código** copia o conteúdo
3. `Ctrl K` busca classe, pacote ou trecho; `Esc` limpa a busca

**Analisar**

1. Com um jar aberto, clique em **Diagnóstico**
2. A aba **Análise do jar** mostra o resumo e os pacotes; filtre por classe, papel, tabela ou entidade
3. Expanda uma classe para ver a ficha e use **Abrir código** para ir ao fonte

---

## Segurança e limites

| Limite | Valor |
|---|---|
| Tamanho do jar | 96 MB |
| Conteúdo extraído | 512 MB |
| Entradas no jar | 60.000 |
| Cache de fontes | 400 arquivos por sessão |
| Jars abertos | 1 por sessão |

- Consulta à base exige **SUP** no servidor, não só na tela
- Banco acessado só com `SELECT` em `TSIMOD`/`TSIJAR`, via `PreparedStatement` e bind
- Assinatura `PK\x03\x04` validada e zip-slip bloqueado na extração
- `action=source` aceita apenas paths do índice da sessão
- Download entrega somente o jar já carregado na sessão

---

## Estrutura do projeto

```
jvexplorer/
├── Dashboards/html5/jvexplorer/
│   ├── main.jsp                    Interface + rotas ?action= (JSP unificado)
│   ├── jvexplorer_component.xml    Gadget para o Construtor de Componentes de BI
│   └── lib/                        Destino do cfr-0.152.jar no build
└── Documentacao/
    └── deploy-jvexplorer.md        Arquitetura, rotas, deploy e troubleshooting
dist/Dashboards/jvexplorer.zip      Pacote pronto para importar
```

Arquitetura, ordem de resolução da conexão e solução de problemas: [`jvexplorer/Documentacao/deploy-jvexplorer.md`](jvexplorer/Documentacao/deploy-jvexplorer.md).

---

## Desenvolvedores

| Nome | GitHub |
|---|---|
| Matheus Prado | [@Prado1997](https://github.com/Prado1997) |
| Lucas Silva | [@sucaslilva](https://github.com/sucaslilva) |

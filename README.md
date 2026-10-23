# JVExplorer

Dashboard HTML5 para o Sankhya OM que abre um arquivo `.jar` e navega nos fontes
como num IDE. O JAR vem do cadastro de **Módulos Java** da base (`TSIMOD`/`TSIJAR`)
ou de upload manual; as classes são descompiladas sob demanda pelo CFR.

**Somente consulta** — nenhuma escrita em banco e nenhum arquivo fora do diretório
temporário da sessão.

## Funcionalidades

| Funcionalidade | Descrição |
| --- | --- |
| Módulos da base | Lista os Módulos Java cadastrados, filtra por nome ou pacote e abre o JAR direto do BLOB de `TSIJAR`. Restrito ao usuário **SUP** |
| Upload manual | Envia um `.jar` do disco em blocos de 4 MB, sem passar pelo cadastro |
| Árvore de pacotes | Índice do JAR agrupado em pacotes e classes, com classes internas (`Outer$Inner`) recolhidas no fonte da classe externa |
| Descompilação sob demanda | Ao clicar na classe o CFR reconstrói o fonte; o resultado fica em cache na sessão |
| Fonte original | Se o JAR embute os `.java`, exibe o original em vez do bytecode reconstruído (badge `src`) |
| Recursos do JAR | Abre `xml`, `sql`, `properties` e `MANIFEST` como texto (badge `arq`) |
| Abas de arquivos | Vários fontes abertos ao mesmo tempo, com troca entre abas e **Copiar código** |
| Busca global | `Ctrl K` busca nome e pacote de todos os itens do índice e o conteúdo dos arquivos já abertos; `Esc` limpa |
| Trocar / descartar JAR | Volta à origem do JAR aberto ou libera a sessão e apaga o diretório temporário |
| Diagnóstico | Painel com CFR resolvido, conexão com o banco, usuário SUP, limites e `tmpdir` — todos os caminhos verificados |

Badges na árvore: `src` = fonte original · `dec` = reconstruído pelo CFR ·
`arq` = recurso de texto.

## Limites

| Limite | Valor |
| --- | --- |
| Tamanho do JAR | 96 MB |
| Conteúdo extraído | 512 MB |
| Entradas no JAR | 60.000 |
| Cache de fontes | 400 arquivos por sessão |
| JARs abertos | 1 por sessão |
| Bloco de upload | 4 MB |

Proteções: assinatura `PK\x03\x04` validada, zip-slip bloqueado, `action=source`
aceita só paths do índice da sessão, SQL somente `SELECT` com `PreparedStatement`
e bind, e SUP exigido no servidor — não apenas no cliente.

## Estrutura

```
jvexplorer/
├── Dashboards/html5/jvexplorer/
│   ├── main.jsp                  <- interface + rotas ?action= (JSP unificado)
│   ├── jvexplorer_component.xml  <- gadget para o Construtor de Componentes de BI
│   └── lib/                      <- destino do cfr-0.152.jar no build
└── Documentacao/
    └── deploy-jvexplorer.md      <- arquitetura, deploy e troubleshooting
```

## Build

```bash
./gradlew html5-jvexplorer
```

Gera `dist/Dashboards/jvexplorer.zip` com `main.jsp`, o XML do componente e o
`cfr-0.152.jar` em `lib/`.

## Deploy

Importar o ZIP pelo **Construtor de Componentes de BI** e vincular o gadget a um
painel. Passo a passo, resolução do CFR e troubleshooting em
[`jvexplorer/Documentacao/deploy-jvexplorer.md`](jvexplorer/Documentacao/deploy-jvexplorer.md).

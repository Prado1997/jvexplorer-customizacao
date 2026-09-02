# lib — descompilador CFR

Esta pasta hospeda o JAR do **CFR** (decompiler Java), que o `main.jsp` carrega em
runtime por um `URLClassLoader` isolado e invoca por reflection
(`org.benf.cfr.reader.api.CfrDriver`).

## Como o JAR chega aqui

Automático, pelo Gradle. A task `html5-jvexplorer` resolve a configuração
`decompiler` (`org.benf:cfr:0.152`) e injeta o JAR em `lib/` dentro do ZIP:

```
./gradlew html5-jvexplorer
```

Saída: `dist/Dashboards/jvexplorer.zip`, contendo `main.jsp`, `jvexplorer_component.xml`
e `lib/cfr-0.152.jar`.

Por isso o `.jar` **não** é versionado neste diretório — ele é baixado do Maven Central
no build. Em ambiente sem internet, baixe o arquivo manualmente e coloque-o aqui:

```
https://repo1.maven.org/maven2/org/benf/cfr/0.152/cfr-0.152.jar
```

## Como o main.jsp localiza o JAR

Ordem de resolução (a primeira que casar vence, e o resultado fica memorizado):

| # | Origem |
|---|---|
| 1 | System property `jvexplorer.cfr.jar` (caminho absoluto do arquivo) |
| 2 | `<pasta do main.jsp>/lib` — varredura por `cfr*.jar`, 4 níveis |
| 3 | `<pasta do main.jsp>` |
| 4 | `<webapp>/dashboard` |
| 5 | `<java.io.tmpdir>/jvexplorer-lib` |

Se o importador de componentes de BI rejeitar o binário dentro do ZIP, use a rota 1:
copie o `cfr-0.152.jar` para uma pasta do servidor e suba o WildFly com

```
-Djvexplorer.cfr.jar=/opt/sankhya/lib/cfr-0.152.jar
```

O botão **Diagnóstico** da tela mostra qual caminho foi resolvido e todos os que
foram verificados.

## Sem o CFR

A tela continua funcional em modo reduzido: abre os `.java` embutidos no JAR
(badge `src`) e os recursos de texto (`arq`). Classes sem fonte embutido acusam
descompilador ausente.

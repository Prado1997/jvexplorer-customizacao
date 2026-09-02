# resources/templates/

Templates de conteúdo dinâmico: e-mails HTML, jasper reports, arquivos de configuração.

## Estrutura sugerida

```
templates/
├── email/        ← templates HTML de e-mail (.html)
├── jasper/       ← relatórios compilados (.jasper) ou fontes (.jrxml)
└── config/       ← arquivos de configuração (.properties, .json, .xml)
```

## Como referenciar no código

```java
// E-mail HTML
InputStream is = NomeService.class.getResourceAsStream("/templates/email/notificacao.html");
String html = new String(is.readAllBytes(), StandardCharsets.UTF_8);
html = html.replace("{{NOME}}", parceiro.getNome());

// Relatório Jasper via LancarRelatorioHelper
LancarRelatorioHelper.lancar(ctx, "/templates/jasper/relatorio-demanda.jasper", parametros);
```

## Convenções

- Nomes de placeholder: `{{CAMPO}}` em maiúsculo com chaves duplas
- Versionar junto com o código — templates no classpath acompanham o JAR
- Arquivos grandes ou binários que mudam frequentemente → não versionar aqui, buscar do filesystem ou banco

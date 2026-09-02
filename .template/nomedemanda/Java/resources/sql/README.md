# resources/sql/

Scripts SQL específicos desta demanda. Incluídos no JAR e carregados em tempo de execução.

## Quando usar

- Queries longas ou complexas que ficam ilegíveis como String Java
- SQL que precisa ser versionado junto com o código
- Templates de consulta com placeholders

## Como referenciar no código

```java
// Carregar arquivo .sql do classpath (dentro do JAR)
InputStream is = NomeRepository.class.getResourceAsStream("/sql/nome-query.sql");
String sql = new String(is.readAllBytes(), StandardCharsets.UTF_8);
```

## Convenções de nomes

| Padrão | Exemplo |
|---|---|
| Operação + entidade | `buscar-notas-pendentes.sql` |
| Tudo minúsculo com hífen | `atualizar-status-cab.sql` |
| Sem abreviações obscuras | `upd-st.sql` ← errado |

## O que NÃO colocar aqui

- Scripts DDL de criação de tabelas → `Objetos de Banco/`
- Scripts de migração one-time → `Objetos de Banco/`
- Queries simples de 1-2 linhas → manter inline no `repository/`

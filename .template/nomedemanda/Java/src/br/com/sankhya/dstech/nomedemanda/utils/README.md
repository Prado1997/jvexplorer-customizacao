# utils/

Utilitários transversais: consulta genérica (`DwfUtils`) e feedback ao usuário (`MessageUtils`).

## DwfUtils

Consultas genéricas sem criar um `Repository` específico.

```java
import br.com.sankhya.dstech.utils.DwfUtils;

// Buscar um registro ou null
DynamicVO vo = DwfUtils.findEntityAsVO("AD_TABELA", "CAMPO = ?", new Object[]{valor});

// Buscar lista (nunca null — retorna lista vazia)
List<DynamicVO> lista = DwfUtils.findEntitiesAsVO("AD_TABELA", "STATUS = ?", new Object[]{"P"});

// Buscar coleção (retorna null se vazio — verificar antes de iterar)
Collection<DynamicVO> col = DwfUtils.findEntitysAsVO(
        DynamicEntityNames.ITEM_NOTA, "NUNOTA = ?", new Object[]{nuNota});
```

| Método | Retorno se vazio | Quando usar |
|---|---|---|
| `findEntityAsVO` | `null` | Buscar registro único, testar existência |
| `findEntitysAsVO` | `null` | Coleção — verificar null antes de iterar |
| `findEntitiesAsVO` | lista vazia | Coleção — nunca null, usar `isEmpty()` diretamente |

## MessageUtils

Exibe mensagem informativa ao usuário via `ServiceContext`. Usado em Regras de Negócio.

```java
import br.com.sankhya.dstech.utils.MessageUtils;

MessageUtils.showInfo("Operação realizada com sucesso.");
```

## Proibido

- Criar utilitário customizado antes de verificar `DwfUtils` e `MessageUtils`
- Colocar regras de negócio aqui — pertencem ao `service/`

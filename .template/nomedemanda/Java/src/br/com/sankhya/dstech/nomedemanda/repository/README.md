# repository/

Única camada com acesso ao banco. Queries, inserts, updates e deletes via JAPE ou NativeSql.

## Responsabilidade

- Operações de persistência de dados
- Encapsular `JapeWrapper`, `DwfUtils`, `JdbcWrapper`
- Retornar DTOs ou `DynamicVO` para o `component/`

## JAPE vs NativeSql — quando usar cada um

| Situação | Use |
|---|---|
| Quer que outros eventos Sankhya sejam disparados | **JAPE** (`JapeFactory.dao()`) |
| Quer atualizar sem disparar eventos (performance, importação em massa) | **NativeSql** (`DwfUtils` / `JdbcWrapper`) |
| Nunca use NativeSql para "economizar código" — apenas quando o não-disparo é intencional | — |

## Proibido

- Regras de negócio — apenas persistência
- SQL dentro de loop — usar `IN` ou processar fora do loop
- `JapeSession.open()` sem `finally { JapeSession.close(hnd); }`

## Skeleton

```java
package br.com.sankhya.dstech.nomedemanda.repository;

import br.com.sankhya.jape.core.JapeSession;
import br.com.sankhya.jape.vo.DynamicVO;
import br.com.sankhya.jape.wrapper.JapeFactory;
import br.com.sankhya.jape.wrapper.JapeWrapper;
import br.com.sankhya.modelcore.MGEModelException;
import br.com.sankhya.modelcore.util.DynamicEntityNames;

import java.math.BigDecimal;
import java.util.Collection;

/**
 * Repository: [Entidade(s) que este repository acessa]
 */
public class NomeRepository {

    private NomeRepository() {
        throw new UnsupportedOperationException("Classe utilitária estática");
    }

    // --- LEITURA ---

    public static DynamicVO buscarPorNota(BigDecimal nuNota) throws MGEModelException {
        try {
            JapeWrapper dao = JapeFactory.dao(DynamicEntityNames.CABECALHO_NOTA);
            return dao.findOne("NUNOTA = ?", new Object[]{nuNota});
        } catch (Exception e) {
            MGEModelException.throwMe(e);
            return null;
        }
    }

    // --- ESCRITA via JAPE (dispara eventos) ---

    public static void atualizar(DynamicVO vo) throws MGEModelException {
        try {
            JapeWrapper dao = JapeFactory.dao(DynamicEntityNames.CABECALHO_NOTA);
            dao.saveNew(vo);
        } catch (Exception e) {
            MGEModelException.throwMe(e);
        }
    }

    // --- ESCRITA via NativeSql (NÃO dispara eventos — uso intencional) ---
    //
    // Use DwfUtils.executeUpdate() ou JdbcWrapper quando o objetivo EXPLÍCITO
    // for não disparar outros eventos Sankhya.
    //
    // Exemplo:
    // DwfUtils.executeUpdate("UPDATE TGFCAB SET AD_CAMPO = ? WHERE NUNOTA = ?",
    //     new Object[]{valor, nuNota});
}
```

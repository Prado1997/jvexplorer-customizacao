# event/

Lógica automática disparada em operações CRUD de uma entidade (before/after insert/update/delete).

## Responsabilidade

- Implementar **obrigatoriamente os 7 métodos** de `EventoProgramavelJava`
- Extrair `DynamicVO` do `PersistenceEvent`
- Validações e `.set()` **na própria entidade do evento**
- Delegar para `component/` quando precisar coordenar múltiplas entidades
- Converter exceções em `MGEModelException` na borda

## Proibido

- Regras de negócio complexas (mover para `service/` via `component/`)
- Orquestração entre múltiplas entidades diretamente (mover para `component/`)
- Acesso direto a `repository/` ou `service/` — passar pelo `component/`
- `ctx.confirmarSimNao()` — não existe aqui; usar `PopUpBuilder` via `MessageUtils`

## Skeleton

```java
package br.com.sankhya.dstech.nomedemanda.event;

import br.com.sankhya.dstech.nomedemanda.component.NomeComponent;
import br.com.sankhya.dstech.nomedemanda.exception.NomeDemandaException;
import br.com.sankhya.extensions.eventoprogramavel.EventoProgramavelJava;
import br.com.sankhya.jape.event.PersistenceEvent;
import br.com.sankhya.jape.event.TransactionContext;
import br.com.sankhya.jape.vo.DynamicVO;
import br.com.sankhya.modelcore.MGEModelException;

/**
 * Evento: [Descrição do que o evento faz]
 *
 * Configuração no Sankhya:
 *   - Entidade: TGFCAB (ou a entidade alvo)
 *   - Tipo: Evento Programável Java
 *   - Classe: br.com.sankhya.dstech.nomedemanda.event.NomeEvento
 */
public class NomeEvento implements EventoProgramavelJava {

    @Override
    public void beforeInsert(PersistenceEvent event) throws Exception {}

    @Override
    public void beforeUpdate(PersistenceEvent event) throws Exception {
        try {
            DynamicVO vo = (DynamicVO) event.getVO();

            // Validação na própria entidade
            if (vo.asBigDecimal("CAMPO") == null) {
                throw new MGEModelException("Campo obrigatório não informado.");
            }

            // Modificar campo da própria entidade
            // vo.set("CAMPO", valor);

            // Coordenar outra entidade → delegar para component
            // NomeComponent component = new NomeComponent();
            // component.completarDados(new NomeDto(vo));

        } catch (NomeDemandaException e) {
            throw MGEModelException.prettyMsg(e.getMessage(), e);
        } catch (MGEModelException e) {
            throw e;
        } catch (Exception e) {
            throw MGEModelException.prettyMsg("Erro no evento: " + e.getMessage(), e);
        }
    }

    @Override
    public void beforeDelete(PersistenceEvent event) throws Exception {}

    @Override
    public void afterInsert(PersistenceEvent event) throws Exception {}

    @Override
    public void afterUpdate(PersistenceEvent event) throws Exception {}

    @Override
    public void afterDelete(PersistenceEvent event) throws Exception {}

    @Override
    public void beforeCommit(TransactionContext tranCtx) throws Exception {}
}
```

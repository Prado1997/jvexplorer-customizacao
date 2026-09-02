# actionbutton/

Ponto de entrada para ações manuais do usuário — botão "Ações" nas telas do Sankhya.

## Responsabilidade

- Receber `ContextoAcao` e ler dados do contexto (linhas selecionadas, campos do formulário)
- Validar pré-condições de UI: "nenhuma linha selecionada", "campo obrigatório vazio"
- Pedir confirmação do usuário (`ctx.confirmarSimNao()`)
- **Delegar o trabalho real para `component/`**
- Converter exceções de domínio em `MGEModelException` para exibição ao usuário

## Proibido

- Regras de negócio (mover para `service/` via `component/`)
- Acesso direto ao banco (mover para `repository/` via `component/`)
- Lógica que poderia ser reutilizada por outro artefato

## Skeleton

```java
package br.com.sankhya.dstech.nomedemanda.actionbutton;

import br.com.sankhya.extensions.actionbutton.AcaoRotinaJava;
import br.com.sankhya.extensions.actionbutton.ContextoAcao;
import br.com.sankhya.jape.core.JapeSession;
import br.com.sankhya.modelcore.MGEModelException;

/**
 * Botão de Ação: [Descrição do que o botão faz]
 *
 * Configuração no Sankhya:
 *   - Entidade: TGFCAB (ou a entidade alvo)
 *   - Tipo: Ação de Rotina Java
 *   - Classe: br.com.sankhya.dstech.nomedemanda.actionbutton.NomeAcao
 */
public class NomeAcao implements AcaoRotinaJava {

    @Override
    public void doAction(ContextoAcao ctx) throws Exception {
        // 1. Validação de UI
        if (ctx.getRegistrosSelecionados() == null || ctx.getRegistrosSelecionados().length == 0) {
            throw new MGEModelException("Selecione ao menos um registro.");
        }

        // 2. Confirmação (só existe em actionbutton — não usar em event ou regra)
        if (!ctx.confirmarSimNao("Deseja executar a ação?")) return;

        // 3. Extrair dados do contexto
        JapeSession.SessionHandle hnd = null;
        try {
            hnd = JapeSession.open();
            // NomeComponent component = new NomeComponent();
            // component.executar(...);  ← delegar para component
        } catch (NomeDemandaException e) {
            throw new MGEModelException(e.getMessage());
        } catch (Exception e) {
            throw new MGEModelException("Erro inesperado: " + e.getMessage());
        } finally {
            JapeSession.close(hnd);
        }
    }
}
```

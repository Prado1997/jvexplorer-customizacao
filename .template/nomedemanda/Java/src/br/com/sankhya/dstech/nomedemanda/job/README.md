# job/

Tarefas agendadas — processamento periódico disparado pelo Cuckoo Scheduler.

## Responsabilidade

- Implementar `ScheduledAction` com método `onTime()`
- Abrir `JapeSession` com `try/finally`
- **Delegar processamento para `component/`**
- Logar início e fim da execução

## Proibido

- Regras de negócio (mover para `service/` via `component/`)
- Acesso direto ao banco (mover para `repository/` via `component/`)
- Lógica dentro do `onTime()` além de orquestração

## Skeleton

```java
package br.com.sankhya.dstech.nomedemanda.job;

import br.com.sankhya.dstech.nomedemanda.component.NomeComponent;
import br.com.sankhya.jape.core.JapeSession;
import br.com.sankhya.modelcore.MGEModelException;
import br.com.sankhya.utils.Logger;
import org.cuckoo.core.ScheduledAction;
import org.cuckoo.core.ScheduledActionContext;

/**
 * Job agendado: [Descrição do que o job faz]
 *
 * Configuração no Sankhya:
 *   - Tipo: Ação Agendada
 *   - Classe: br.com.sankhya.dstech.nomedemanda.job.NomeJob
 *   - Frequência: [ex: diário às 02:00]
 */
public class NomeJob implements ScheduledAction {

    @Override
    public void onTime(ScheduledActionContext ctx) {
        Logger.info("[NomeJob] Iniciando execução.");
        JapeSession.SessionHandle hnd = null;
        try {
            hnd = JapeSession.open();
            NomeComponent component = new NomeComponent();
            component.processarPendentes();
            Logger.info("[NomeJob] Concluído com sucesso.");
        } catch (MGEModelException e) {
            Logger.error("[NomeJob] Erro de negócio: " + e.getMessage(), e);
        } catch (Exception e) {
            Logger.error("[NomeJob] Erro inesperado: " + e.getMessage(), e);
        } finally {
            JapeSession.close(hnd);
        }
    }
}
```

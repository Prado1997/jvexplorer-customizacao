# regra/

Lógica ligada ao ciclo de confirmação/faturamento de nota nas Centrais do Sankhya.
Dois tipos: `RegraNegocioJava` (cadastrada na tela Regras de Negócio) e `Regra` (via preferência `MODREGCENTRAL`).

## Responsabilidade

- Implementar `executa()` (`RegraNegocioJava`) ou `afterUpdate()` (`Regra`)
- Verificar contexto: `isItem()`, `ehConfirmacao()`, `ehDuplicacao()`, `ehMovFin()`
- **Delegar processamento para `component/`**
- Setar `sucesso` e `msgError` para feedback ao usuário (`RegraNegocioJava`)

## Proibido

- Regras de negócio complexas direto aqui (mover para `service/` via `component/`)
- Acesso direto ao banco (mover para `repository/` via `component/`)

## Skeleton — RegraNegocioJava

```java
package br.com.sankhya.dstech.nomedemanda.regra;

import br.com.sankhya.dstech.nomedemanda.component.NomeComponent;
import br.com.sankhya.dstech.nomedemanda.exception.NomeDemandaException;
import br.com.sankhya.dstech.utils.MessageUtils;
import br.com.sankhya.extensions.regrasnegocio.ContextoRegra;
import br.com.sankhya.extensions.regrasnegocio.RegraNegocioJava;
import br.com.sankhya.jape.core.JapeSession;
import br.com.sankhya.modelcore.MGEModelException;
import br.com.sankhya.modelcore.comercial.AtributosRegras;

/**
 * Regra de Negócio: [Descrição]
 *
 * Configuração no Sankhya:
 *   - Tela: Regras de Negócio
 *   - Entidade: TGFCAB
 *   - Classe: br.com.sankhya.dstech.nomedemanda.regra.NomeRegra
 */
public class NomeRegra implements RegraNegocioJava {

    private boolean sucesso;
    private String msgError;

    @Override
    public void executa(ContextoRegra ctx) throws MGEModelException {
        sucesso = false;
        msgError = "";

        processar(ctx);

        ctx.setSucesso(sucesso);
        ctx.setMensagem(msgError);
        if (!msgError.isEmpty()) MessageUtils.showInfo(msgError);
        ctx.setCodUsuLib(0);
    }

    private void processar(ContextoRegra ctx) throws MGEModelException {
        // Ignorar se não for o contexto correto
        if (isItem() || !ehConfirmacao() || ehDuplicacao() || ehMovFin()) {
            sucesso = true;
            return;
        }

        JapeSession.SessionHandle hnd = null;
        try {
            hnd = JapeSession.open();
            NomeComponent component = new NomeComponent();
            component.validarConfirmacao(ctx.getNunota());
            sucesso = true;
        } catch (NomeDemandaException e) {
            sucesso = false;
            msgError = e.getMessage();
        } catch (Exception e) {
            throw new MGEModelException("Erro inesperado: " + e.getMessage());
        } finally {
            JapeSession.close(hnd);
        }
    }

    private static boolean isItem() {
        return JapeSession.getPropertyAsBoolean("isItem", Boolean.FALSE);
    }

    private static boolean ehConfirmacao() {
        return JapeSession.getPropertyAsBoolean(AtributosRegras.CONFIRMANDO, Boolean.FALSE);
    }

    private static boolean ehDuplicacao() {
        return JapeSession.getPropertyAsBoolean(AtributosRegras.NUNOTA_SENDO_DUPLICADA, Boolean.FALSE);
    }

    private static boolean ehMovFin() {
        return JapeSession.getPropertyAsBoolean(AtributosRegras.CENTRAL_FINANCEIRO, Boolean.FALSE);
    }
}
```

## Skeleton — Regra (via preferência MODREGCENTRAL)

```java
package br.com.sankhya.dstech.nomedemanda.regra;

import br.com.sankhya.dstech.nomedemanda.component.NomeComponent;
import br.com.sankhya.dstech.nomedemanda.exception.NomeDemandaException;
import br.com.sankhya.jape.core.JapeSession;
import br.com.sankhya.modelcore.MGEModelException;
import br.com.sankhya.modelcore.comercial.AtributosRegras;
import br.com.sankhya.modelcore.comercial.ContextoRegra;
import br.com.sankhya.modelcore.comercial.Regra;

/**
 * Regra via preferência: [Descrição]
 *
 * Configuração no Sankhya:
 *   - Preferência: MODREGCENTRAL
 *   - Valor: [ordem]@br.com.sankhya.dstech.nomedemanda.regra.NomeRegraPreferencia
 */
public class NomeRegraPreferencia implements Regra {

    @Override public void beforeInsert(ContextoRegra ctx) throws Exception {}
    @Override public void afterInsert(ContextoRegra ctx) throws Exception {}
    @Override public void beforeDelete(ContextoRegra ctx) throws Exception {}
    @Override public void afterDelete(ContextoRegra ctx) throws Exception {}
    @Override public void beforeUpdate(ContextoRegra ctx) throws Exception {}

    @Override
    public void afterUpdate(ContextoRegra ctx) throws Exception {
        try {
            if (!JapeSession.getPropertyAsBoolean(AtributosRegras.CONFIRMANDO, Boolean.FALSE)) return;
            NomeComponent component = new NomeComponent();
            component.validarConfirmacao(ctx.getNunota());
        } catch (NomeDemandaException e) {
            throw MGEModelException.prettyMsg(e.getMessage(), e);
        } catch (Exception e) {
            throw MGEModelException.prettyMsg("Erro na regra: " + e.getMessage(), e);
        }
    }
}
```

# controller/

Endpoint REST/serviço exposto externamente ao módulo via `ServiceProvider` manual.

## Responsabilidade

- Receber chamadas externas
- Gerenciar sessão com `JapeHelper`
- Delegar toda lógica para `component/`
- Retornar resultado serializado

## Proibido

- Regras de negócio — delegar para `component/`
- Acesso direto ao banco — sempre via `component/`
- Lógica além de receber, delegar e retornar

## Skeleton

```java
package br.com.sankhya.dstech.nomedemanda.controller;

import br.com.sankhya.dstech.nomedemanda.component.NomeComponent;
import br.com.sankhya.dstech.nomedemanda.exception.NomeDemandaException;
import br.com.sankhya.modelcore.MGEModelException;

import java.math.BigDecimal;

/**
 * Controller: [Descrição do endpoint]
 *
 * Configuração no Sankhya:
 *   - Tipo: ServiceProvider
 *   - Classe: br.com.sankhya.dstech.nomedemanda.controller.NomeController
 */
public class NomeController {

    public String executarOperacao(BigDecimal id) throws Exception {
        try {
            return JapeHelper.executeWithoutTx(() -> {
                NomeComponent nomeComponent = new NomeComponent();
                return nomeComponent.executarOperacao(id);
            });
        } catch (NomeDemandaException e) {
            throw MGEModelException.prettyMsg(e.getMessage(), e);
        } catch (Exception e) {
            throw MGEModelException.prettyMsg("Erro inesperado: " + e.getMessage(), e);
        }
    }
}
```

## Registro manual

Registrado como serviço no arquivo de configuração do módulo.
Consultar `references/controller.md` e `references/estrutura-modulo.md`.

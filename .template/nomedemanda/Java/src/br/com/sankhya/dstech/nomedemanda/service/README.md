# service/

Regras de negócio puras de domínio: cálculos, validações complexas, transformações.

## Responsabilidade

- Implementar regras de negócio do cliente
- Validações de domínio, cálculos, transformações
- Lançar `NomeDemandaException` para erros de negócio (nunca `MGEModelException` direto)
- Ser chamado exclusivamente pelo `component/`

## Proibido

- Acesso ao banco — sempre via `repository/` (chamado pelo `component/`)
- Orquestração entre entidades — responsabilidade do `component/`
- Retornar `null` silenciosamente em caso de erro — lançar exceção com contexto

## Skeleton

```java
package br.com.sankhya.dstech.nomedemanda.service;

import br.com.sankhya.dstech.nomedemanda.exception.NomeDemandaException;
import br.com.sankhya.jape.vo.DynamicVO;

import java.math.BigDecimal;

/**
 * Service: [Descrição das regras de negócio que este service encapsula]
 */
public class NomeService {

    /**
     * Valida se o registro está apto para [operação].
     *
     * @throws NomeDemandaException quando [condição de negócio inválida]
     */
    public void validarParaExecucao(DynamicVO vo) throws NomeDemandaException {
        if (vo.asBigDecimal("CAMPO") == null) {
            throw new NomeDemandaException(NomeDemandaException.CAMPO_OBRIGATORIO,
                    "Campo obrigatório não informado.");
        }
        // demais validações de domínio...
    }

    /**
     * Calcula [resultado] a partir dos dados fornecidos.
     *
     * @param valor valor base para cálculo
     * @return resultado calculado
     */
    public BigDecimal calcular(BigDecimal valor) throws NomeDemandaException {
        if (valor == null || valor.signum() <= 0) {
            throw new NomeDemandaException(NomeDemandaException.CAMPO_OBRIGATORIO,
                    "Valor deve ser positivo.");
        }
        // lógica de cálculo...
        return valor;
    }
}
```

## Regra de ouro

> Se você está escrevendo uma query dentro do service, está errado. Mova para `repository/`.
> Se você está coordenando chamadas entre entidades, está errado. Mova para `component/`.

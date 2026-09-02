# component/

Hub de orquestração da demanda. Ponto de entrada único para todos os artefatos.

## Responsabilidade

- Ser chamado por `actionbutton/`, `event/`, `job/`, `regra/` e `controller/`
- Coordenar chamadas a `service/` (regras de negócio puras) e `repository/` (acesso a dados)
- Tratar exceções de infraestrutura e dar-lhes significado de negócio

## Proibido

- Regras de negócio puras — extrair para `service/`
- Acesso direto ao banco — usar `repository/`

## Skeleton

```java
package br.com.sankhya.dstech.nomedemanda.component;

import br.com.sankhya.dstech.nomedemanda.exception.NomeDemandaException;
import br.com.sankhya.dstech.nomedemanda.repository.NomeRepository;
import br.com.sankhya.dstech.nomedemanda.service.NomeService;
import br.com.sankhya.jape.vo.DynamicVO;

import java.math.BigDecimal;

/**
 * Component: [Descrição do que este component orquestra]
 */
public class NomeComponent {

    private final NomeRepository nomeRepository;
    private final NomeService nomeService;

    public NomeComponent() {
        this.nomeRepository = new NomeRepository();
        this.nomeService = new NomeService();
    }

    /**
     * [Descrição da operação]
     *
     * @throws NomeDemandaException quando [condição de negócio inválida]
     */
    public void executarOperacao(BigDecimal id) throws Exception {
        DynamicVO vo = nomeRepository.buscarPorId(id);
        if (vo == null) throw new NomeDemandaException(NomeDemandaException.NOTA_NAO_ENCONTRADA, id);

        nomeService.validarParaExecucao(vo);
        nomeRepository.atualizarStatus(id, "P");
    }
}
```

## Tratamento de exceções

O component **não converte** `NomeDemandaException` para `MGEModelException`.
A conversão é feita na borda pelos artefatos Sankhya.

```java
// Em actionbutton/, event/ ou regra/:
} catch (NomeDemandaException e) {
    throw MGEModelException.prettyMsg(e.getMessage(), e);
} catch (Exception e) {
    throw MGEModelException.prettyMsg("Erro inesperado: " + e.getMessage(), e);
}
```

## Regra de ouro

> Todos os artefatos Sankhya passam pelo `component/`.
> Nenhum artefato acessa `service/` ou `repository/` diretamente.

Referência completa → `references/component.md`

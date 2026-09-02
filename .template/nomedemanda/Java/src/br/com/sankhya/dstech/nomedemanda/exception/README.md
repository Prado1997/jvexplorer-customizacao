# exception/

Exceções de domínio da demanda. Carregam mensagens significativas para o usuário e códigos rastreáveis para log.

## Responsabilidade

- Estender `Exception`
- Representar falhas de negócio com contexto (o que falhou, com quais dados)
- Ser lançada no `service/`, relançada pelo `component/` (sem converter), e convertida em `MGEModelException` na borda dos artefatos (`actionbutton/`, `event/`, `regra/`)

## Proibido

- Regras de negócio
- Engolir exceções silenciosamente
- Usar `MGEModelException` direto no `service/` — a exceção de domínio mantém o código desacoplado do Sankhya

## Skeleton

```java
package br.com.sankhya.dstech.nomedemanda.exception;

import java.math.BigDecimal;

/**
 * Exceção de domínio da demanda NomeDemanda.
 * Lançada no service/, convertida em MGEModelException nas bordas (actionbutton, event, regra).
 */
public class NomeDemandaException extends Exception {

    // Códigos rastreáveis — facilita localizar origem em log
    public static final String NOTA_NAO_ENCONTRADA   = "NDE-001";
    public static final String CAMPO_OBRIGATORIO      = "NDE-002";
    public static final String REGRA_DE_NEGOCIO_X     = "NDE-003";

    private final String codigo;

    public NomeDemandaException(String codigo, String mensagem) {
        super("[" + codigo + "] " + mensagem);
        this.codigo = codigo;
    }

    /** Construtor com contexto — inclui o valor problemático na mensagem */
    public NomeDemandaException(String codigo, BigDecimal referencia) {
        super("[" + codigo + "] Registro não encontrado: " + referencia);
        this.codigo = codigo;
    }

    public String getCodigo() {
        return codigo;
    }
}
```

## Como usar nas bordas

```java
// Em actionbutton/, event/ ou regra/ (borda):
try {
    NomeComponent component = new NomeComponent();
    component.executarOperacao(id);
} catch (NomeDemandaException e) {
    throw MGEModelException.prettyMsg(e.getMessage(), e);
} catch (Exception e) {
    throw MGEModelException.prettyMsg("Erro inesperado: " + e.getMessage(), e);
}
```

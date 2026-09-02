# enums/

Enums de domínio e constantes de entidades adicionais. Eliminam strings mágicas do código.

## Responsabilidade

- Representar estados, tipos e valores fixos de domínio
- Centralizar nomes de campos adicionais (`AD_*`) via `AdicionalEntityNames`
- Ser a única fonte de verdade para valores fixos — se o valor aparece em mais de um lugar, ele pertence aqui

## Proibido

- Qualquer lógica além de getters simples
- Acessar banco ou chamar services

## Exemplos

### Enum de status/tipo

```java
package br.com.sankhya.dstech.nomedemanda.enums;

/**
 * Status possíveis para [entidade/processo da demanda].
 * Substitui strings mágicas espalhadas no código.
 */
public enum StatusNomeDemanda {

    PENDENTE("P"),
    PROCESSADO("R"),
    CANCELADO("C");

    private final String codigo;

    StatusNomeDemanda(String codigo) {
        this.codigo = codigo;
    }

    public String getCodigo() {
        return codigo;
    }

    /** Converte string do banco para enum — retorna null se não encontrar */
    public static StatusNomeDemanda fromCodigo(String codigo) {
        for (StatusNomeDemanda s : values()) {
            if (s.codigo.equals(codigo)) return s;
        }
        return null;
    }
}
```

### Nomes de campos adicionais (AdicionalEntityNames)

```java
package br.com.sankhya.dstech.nomedemanda.enums;

/**
 * Nomes dos campos adicionais (AD_*) utilizados nesta demanda.
 * Centraliza os nomes para evitar typos e facilitar refatoração.
 */
public final class AdicionalEntityNames {

    private AdicionalEntityNames() {
        throw new UnsupportedOperationException();
    }

    // Campos em TGFCAB
    public static final String CAB_STATUS_DEMANDA  = "AD_STATUSDEMANDA";
    public static final String CAB_DATA_PROCESSO   = "AD_DTPROCESSO";

    // Campos em TGFITE
    public static final String ITE_QTD_PROCESSADA  = "AD_QTDPROC";
}
```

## Regra de uso

```java
// ERRADO — string mágica
if ("P".equals(vo.asString("AD_STATUSDEMANDA"))) { ... }

// CERTO — enum e constante
if (StatusNomeDemanda.PENDENTE.getCodigo().equals(
        vo.asString(AdicionalEntityNames.CAB_STATUS_DEMANDA))) { ... }
```

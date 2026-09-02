# dto/

Objetos de transferência de dados. Representam entidades de domínio ou agrupam campos para trafegar entre camadas.

## Quando criar um DTO

| Situação | Criar DTO? |
|---|---|
| `DynamicVO` já carrega os campos necessários e não sai da camada `repository/` | Não |
| Precisa trafegar dados entre `service/` e `actionbutton/` sem expor `DynamicVO` | Sim |
| Query complexa retorna join de várias entidades | Sim |
| Precisa agrupar campos calculados ou derivados | Sim |

## Proibido

- Regras de negócio dentro do DTO
- Acessar banco de dentro do DTO
- Colocar lógica de formatação de UI (isso é responsabilidade de `actionbutton/` ou da tela)

## Skeleton

```java
package br.com.sankhya.dstech.nomedemanda.dto;

import br.com.sankhya.jape.vo.DynamicVO;

import java.math.BigDecimal;
import java.util.Date;

/**
 * DTO: [Descrição da entidade ou conjunto de dados representado]
 */
public class NomeDto {

    private final BigDecimal nuNota;
    private final String tipMov;
    private final Date dhNota;

    /** Construtor a partir de DynamicVO — converte no ponto de entrada (repository) */
    public NomeDto(DynamicVO vo) {
        this.nuNota  = vo.asBigDecimal("NUNOTA");
        this.tipMov  = vo.asString("TIPMOV");
        this.dhNota  = vo.asDate("DHNOTA");
    }

    /** Construtor explícito — use quando os dados vêm de fontes diferentes */
    public NomeDto(BigDecimal nuNota, String tipMov, Date dhNota) {
        this.nuNota  = nuNota;
        this.tipMov  = tipMov;
        this.dhNota  = dhNota;
    }

    public BigDecimal getNuNota()  { return nuNota; }
    public String getTipMov()      { return tipMov; }
    public Date getDhNota()        { return dhNota; }
}
```

# helper/

Lógica reutilizável entre múltiplos artefatos da mesma demanda (ex: `PopUpHelper` compartilhado entre `actionbutton/`, `event/`, `regra/`).

## Responsabilidade

- Métodos estáticos reutilizáveis entre artefatos da demanda
- Construtor privado — nunca instanciar

## Proibido

- Regras de negócio da demanda — mover para `service/`
- Acesso ao banco — usar `repository/`
- Criar helper antes de verificar se o utilitário já existe em `DwfUtils` ou `MessageUtils` (ver `utils/`)

## Quando usar vs service/

| Situação | Destino |
|---|---|
| Lógica de negócio pura | `service/` |
| Lógica de apresentação compartilhada entre artefatos | `helper/` |
| Lógica transversal entre múltiplos módulos/demandas | Mover para `helper/` da demanda mais central ou extrair em lib separada |

## Skeleton

```java
package br.com.sankhya.dstech.nomedemanda.helper;

/**
 * Helper: [Descrição do que este helper oferece]
 */
public final class NomeHelper {

    private NomeHelper() {
        throw new UnsupportedOperationException("Classe utilitária estática");
    }

    public static String formatarMensagem(String prefixo, String valor) {
        return "[" + prefixo + "] " + valor;
    }
}
```

Para utilitários de sessão e transação → `Modelo_JapeHelper.java` nos exemplos da skill.

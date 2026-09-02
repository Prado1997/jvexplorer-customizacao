# shared — Utilitários Compartilhados

Código em `shared/` é compilado junto com todas as demandas e incluído em todo JAR gerado pelo `build.gradle` (via `include 'br/com/sankhya/dstech/helper/**'` e `include 'br/com/sankhya/dstech/utils/**'`).

Coloque aqui apenas o que for transversal a múltiplas demandas. Classes novas devem ficar nos pacotes `helper` ou `utils` — outros pacotes não entram no JAR.

---

## utils — br.com.sankhya.dstech.utils

| Classe | O que faz |
|---|---|
| `Logger` | Grava log na tabela `AD_LOG`, controlado por preferência `LOGDEBUGATV` (ver seção abaixo) |
| `DwfUtils` | Consultas genéricas por entidade (`findEntityAsVO`, `findEntitiesAsVO`) e execução com transação (`execWithTx`) |
| `MessageUtils` | Mensagem informativa ao usuário via `ServiceContext` (`showInfo`) — usado em Regras de Negócio |

### DwfUtils — retorno por método

| Método | Retorno se vazio | Quando usar |
|---|---|---|
| `findEntityAsVO` | `null` | Buscar registro único, testar existência |
| `findEntitysAsVO` | `null` | Coleção — verificar null antes de iterar |
| `findEntitiesAsVO` | lista vazia | Coleção — nunca null, usar `isEmpty()` diretamente |

---

## helper — br.com.sankhya.dstech.helper

Helpers estáticos por entidade/operação. Construtor privado — nunca instanciar.

| Classe | Entidade | O que faz |
|---|---|---|
| `CabecalhoNotaHelper` | TGFCAB | Busca nota por NUNOTA, verifica nota de contrato, wrap para `CabecalhoNotaVO` |
| `CompraVendaVariosPedidoHelper` | TGFVAR | Vincula itens de nota destino aos da nota de origem (atendimento integral) |
| `ConfirmarNotaHelper` | TGFCAB | Confirma nota via barramento ou platform service; flags `isConfirmando`/`isFaturando`/`isDuplicando`. **Não usar em eventos/regras** — apenas jobs e threads externas |
| `ContratoArmazemHelper` | Contrato Armazenagem | Busca contrato por PK |
| `CotacaoMoedaHelper` | TSICOT | Busca cotação por PK, verifica existência de cotação por moeda |
| `EmpresaHelper` | TSIEMP | Busca empresa por PK |
| `EnviaEmailHelper` | FILA_MSG | Insere e-mail na fila de envio (com ou sem SMTP específico) |
| `ImpostoItemNotaHelper` | Imposto Item Nota | Busca impostos por nota/item |
| `ItemComposicaoProdutoHelper` | TGFICP | Busca componente de kit, lista itens de composição de um produto |
| `ItemNotaHelper` | TGFITE | Busca item por nota/sequência, itens por nota, itens por nota/produto, wrap para `ItemNotaVO` |
| `LancarRelatorioHelper` | — | Cria arquivo de sessão e gera link HTML de visualização; enum `MimeType` com fallback de detecção |
| `LancarTelaHelper` | — | Gera links base64 para abrir telas com filtro (Central, Financeiro, Portais) |
| `ParceiroHelper` | TGFPAR | Busca parceiro, atualiza conta contábil (1-4) |
| `ProdutoHelper` | TGFPRO | Busca produto ou serviço (`getVOServico`, USOPROD='S'), ativa/desativa produto, wrap para `ProdutoVO` |
| `TipoOperacaoHelper` | TGFTOP | Busca TOP mais recente por DHALTER |
| `UsuarioHelper` | TSIUSU | Busca usuário por PK |

---

## Logger — br.com.sankhya.dstech.utils.Logger

Utilitário de log que grava na tabela `AD_LOG` do banco, controlado por preferência do TSIPAR.

### Setup obrigatório (uma vez por ambiente)

**1. Importar a tela adicional AD_LOG**

Arquivo: `shared/Telas Adicionais/<arquivo>.zip`

Importar via: Sankhya → Configurações → Construtor de Telas → Importar

**2. Cadastrar a preferência LOGDEBUGATV**

Menu: Preferências do Sistema (TSIPAR)

| Campo | Valor |
|---|---|
| Chave | `LOGDEBUGATV` |
| Descrição | Desativa gravação de logs em AD_LOG |
| Valor padrão | *(vazio — log ativo por padrão)* |
| Para desativar | Setar valor `N` |

> Log ativo por padrão. Setar `N` para desativar silenciosamente.

### Uso

```java
import br.com.sankhya.dstech.utils.Logger;

Logger.info("Operacao iniciada | id=" + id);

try {
    // ...
} catch (Exception e) {
    Logger.error("Falha na operacao | id=" + id, e);
    throw e;
}
```

**Métodos disponíveis:**

| Método | Quando usar |
|---|---|
| `Logger.info(String)` | Rastreamento de fluxo, início/fim de operações |
| `Logger.error(String, Throwable)` | Todo `catch` com exceção real — sempre passar `e` |

A classe captura automaticamente: data/hora, nível, classe de origem, linha, usuário logado e stacktrace (no caso de error).

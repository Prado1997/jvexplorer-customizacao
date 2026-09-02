# Agentes de Code Review

Suite de agentes para revisão automatizada de código em projetos Java Sankhya.

## Estrutura

| Agente | Responsabilidade | Modelo |
|--------|-----------------|--------|
| orchestrator.md | Coordena todos os agentes e gera relatório consolidado | sonnet |
| arch-reviewer.md | Arquitetura, separação de responsabilidades, acoplamento | sonnet |
| clean-code.md | Legibilidade, naming, duplicação, complexidade | sonnet |
| security-scanner.md | Vulnerabilidades, SQL injection, auth, dados sensíveis | sonnet |
| perf-analyzer.md | Performance, N+1, queries sem limit, leaks em batch | sonnet |
| doc-checker.md | Documentação, Javadoc, entidade declarada em classes Sankhya | haiku (fallback: sonnet) |

## Como usar

### Revisão completa (orquestrador)

```bash
claude -a agents/orchestrator.md
```

O orquestrador executa todos os agentes na ordem correta, deduplica findings e gera um relatório em `docs/reviews/YYYY-MM-DD_HH-mm.md` com parecer final (Aprovado / Aprovado com ressalvas / Reprovado).

### Agente individual

```bash
claude -a agents/security-scanner.md
claude -a agents/clean-code.md
claude -a agents/perf-analyzer.md
claude -a agents/arch-reviewer.md
claude -a agents/doc-checker.md
```

Útil quando quer focar em uma dimensão específica ou re-executar após correções.

## Distribuição

Copie a pasta `agents/` para a raiz de cada projeto Java:

```
meu-projeto/
├── src/
├── pom.xml
├── agents/
│   ├── README.md
│   ├── orchestrator.md
│   ├── arch-reviewer.md
│   ├── clean-code.md
│   ├── security-scanner.md
│   ├── perf-analyzer.md
│   └── doc-checker.md
└── ...
```

## Comportamento

- Analisa apenas código novo/modificado (via `git diff`). Se não houver git, analisa todos os `.java` em `src/`.
- Cada agente tem limite de findings (15-20) para evitar ruído.
- CRITICALs acima do limite são listados integralmente.
- Após correção dos CRITICALs, re-execute para revelar findings omitidos.
- Qualquer CRITICAL no relatório resulta em parecer "Reprovado".

## Severidades

| Severidade | Significado |
|-----------|-------------|
| CRITICAL | Bloqueia merge. Deve ser corrigido antes de submeter novamente. |
| WARNING | Deve ser corrigido, mas pode ser em follow-up se não houver CRITICALs. |
| INFO | Sugestão de melhoria. Não bloqueia. |

## Deduplicação

Quando dois agentes reportam o mesmo problema no mesmo arquivo/linha, o orquestrador mantém apenas o finding do agente mais especializado:

security-scanner > perf-analyzer > arch-reviewer > clean-code > doc-checker

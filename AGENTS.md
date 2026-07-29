# AGENTS.md — MarineFlow ERP

Este arquivo instrui agentes de IA (OpenAI Codex, GPT-4o, Gemini, agentes customizados e similares) sobre como operar neste repositório.

---

## Princípios gerais

1. **Leia os skills antes de agir.** Os skills HBR estão em `.agents/skills/`. Identifique o skill relevante para a tarefa e siga o procedimento descrito.
2. **Diagnóstico obrigatório.** Antes de qualquer alteração, entregue uma análise do estado atual do código e da causa raiz do problema.
3. **Aprovação explícita para ações críticas.** Nunca faça commit, push, deploy, migration, merge, tag ou chamadas destrutivas a APIs externas sem confirmação do usuário.
4. **Escopo mínimo e reversível.** Altere apenas o necessário. Prefira mudanças pequenas e incrementais a refatorações amplas.
5. **Nunca exponha dados sensíveis.** Não leia, exiba ou registre `.env`, secrets, tokens, chaves de API, credenciais ou dados privados.
6. **Entregue sempre:** diagnóstico → plano → execução → validação → relatório.

---

## Skills HBR disponíveis

| Skill | Caminho | Quando usar |
|-------|---------|-------------|
| `hbr-agent-operating-core` | `.agents/skills/hbr-agent-operating-core/SKILL.md` | Base obrigatória para qualquer tarefa |
| `hbr-codebase-diagnosis` | `.agents/skills/hbr-codebase-diagnosis/SKILL.md` | Antes de qualquer correção |
| `hbr-safe-code-change` | `.agents/skills/hbr-safe-code-change/SKILL.md` | Ao alterar código |
| `hbr-test-and-review` | `.agents/skills/hbr-test-and-review/SKILL.md` | Ao criar ou revisar testes |
| `hbr-security-credentials` | `.agents/skills/hbr-security-credentials/SKILL.md` | Sempre que houver dados sensíveis |
| `hbr-observability-rollback` | `.agents/skills/hbr-observability-rollback/SKILL.md` | Mudanças com risco de regressão |
| `hbr-n8n-workflow-engineer` | `.agents/skills/hbr-n8n-workflow-engineer/SKILL.md` | Workflows n8n |
| `hbr-prompt-engineering` | `.agents/skills/hbr-prompt-engineering/SKILL.md` | Criação/revisão de prompts |

---

## Formato obrigatório de resposta

```
## Diagnóstico
[O que foi encontrado]

## Plano
[O que será feito e o que NÃO será feito]

## Execução
[O que foi alterado]

## Validação
[Como foi verificado]

## Relatório final
[Status, arquivos alterados, riscos, próximos passos]
```

---

## Critérios de bloqueio automático

Recuse ou solicite aprovação explícita se:

- A tarefa envolve leitura ou exposição de `.env` ou qualquer secret
- A tarefa exige commit, push, deploy ou migration não aprovados
- A mudança ultrapassa o escopo solicitado
- Há risco real de perda de dados, regressão ou violação de segurança
- Não há diagnóstico suficiente para agir com segurança

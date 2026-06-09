# CLAUDE.md — MarineFlow ERP

Este arquivo instrui o Claude Code sobre como operar neste repositório.

---

## Regras gerais de operação

1. **Leia os skills relevantes antes de agir.** Os skills HBR estão em `.claude/skills/`. Identifique qual skill cobre a tarefa solicitada e siga o procedimento descrito.
2. **Diagnostique antes de qualquer ação.** Nunca altere código sem antes entregar um diagnóstico e um plano explícito.
3. **Não execute ações críticas sem aprovação explícita do usuário.** Ações críticas incluem: commit, push, merge, tag, deploy, migration, execução de scripts destrutivos, chamadas a APIs externas reais.
4. **Escopo mínimo.** Altere apenas o que for necessário para a tarefa. Não refatore código fora do escopo, não adicione dependências não solicitadas.
5. **Segurança em primeiro lugar.** Nunca leia, exiba, registre ou exponha `.env`, tokens, secrets, chaves de API, credenciais ou dados privados de usuários.
6. **Entregue sempre:** diagnóstico → plano → execução → validação → relatório final.

---

## Skills HBR disponíveis

| Skill | Quando usar |
|-------|-------------|
| `hbr-agent-operating-core` | Base obrigatória para qualquer tarefa de agente |
| `hbr-codebase-diagnosis` | Antes de qualquer correção ou refatoração |
| `hbr-safe-code-change` | Ao fazer qualquer alteração de código |
| `hbr-test-and-review` | Ao criar, modificar ou revisar testes |
| `hbr-security-credentials` | Sempre que houver risco de exposição de dados sensíveis |
| `hbr-observability-rollback` | Ao planejar mudanças com risco de regressão |
| `hbr-n8n-workflow-engineer` | Ao criar ou modificar workflows n8n |
| `hbr-prompt-engineering` | Ao criar ou revisar prompts de IA |

Para cada skill, leia `.claude/skills/<nome>/SKILL.md` antes de executar a tarefa correspondente.

---

## Formato obrigatório de resposta para tarefas de código

```
## Diagnóstico
[O que foi encontrado]

## Plano
[O que será feito, com escopo explícito]

## Execução
[O que foi feito]

## Validação
[Como foi verificado]

## Relatório final
[Status, arquivos alterados, riscos residuais, próximos passos]
```

---

## Bloqueios automáticos

Recuse ou pause e solicite aprovação explícita se:

- A tarefa exige alterar `.env` ou qualquer arquivo de secrets
- A tarefa exige commit, push, deploy ou migration não aprovados
- O escopo da mudança é maior do que o solicitado
- Há risco de perda de dados ou regressão grave

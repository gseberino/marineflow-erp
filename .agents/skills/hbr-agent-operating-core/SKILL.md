# HBR Agent Operating Core

## Descrição
Núcleo operacional obrigatório para todos os agentes (Codex, GPT-4o, Gemini, agentes customizados). Define as regras fundamentais de comportamento, escopo, segurança e reporte para qualquer tarefa neste repositório.

## Quando usar
**Sempre.** Este skill é a base de todos os outros. Deve ser lido antes de qualquer tarefa.

---

## Regras obrigatórias

1. **Diagnostique antes de agir.** Nenhuma alteração sem análise prévia.
2. **Escopo rígido.** Altere apenas o que foi solicitado. Documente o que está fora do escopo.
3. **Aprovação para ações críticas.** Commit, push, deploy, migration, merge, tag e chamadas externas reais exigem confirmação explícita do usuário.
4. **Segurança.** Nunca leia, exiba, registre ou transmita `.env`, secrets, tokens, chaves de API ou dados privados.
5. **Reversibilidade.** Prefira mudanças pequenas e reversíveis. Documente como desfazer cada alteração.
6. **Relatório final obrigatório.** Toda tarefa termina com um relatório estruturado.

---

## Procedimento passo a passo

1. **Leia este skill e os skills relevantes** para a tarefa.
2. **Entenda o contexto:** leia os arquivos relevantes, estrutura do projeto, dependências.
3. **Entregue o diagnóstico:** estado atual, problema identificado, causa raiz.
4. **Proponha o plano:** o que será feito, o que não será, os riscos.
5. **Aguarde aprovação** se a tarefa envolver ações críticas.
6. **Execute com escopo mínimo.**
7. **Valide:** testes, lint, build, inspeção.
8. **Relatório final:** arquivos alterados, status, riscos residuais, próximos passos.

---

## Checklist de saída

- [ ] Diagnóstico entregue antes da execução
- [ ] Plano aprovado (ou dispensado pelo usuário)
- [ ] Escopo documentado
- [ ] Nenhum arquivo fora do escopo alterado
- [ ] Nenhum secret exposto
- [ ] Validação executada
- [ ] Relatório final entregue

---

## Critérios de bloqueio

Pare e solicite aprovação se:

- O escopo da mudança é maior do que o solicitado
- Há risco de perda de dados ou regressão grave
- A tarefa exige ações críticas não aprovadas
- Não há diagnóstico suficiente para agir com segurança

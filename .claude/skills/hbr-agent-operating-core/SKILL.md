# HBR Agent Operating Core

## Descrição
Núcleo operacional obrigatório para todos os agentes HBR. Define as regras fundamentais de comportamento, escopo, segurança e reporte que devem ser seguidas em qualquer tarefa, independentemente do tipo de trabalho.

## Quando usar
**Sempre.** Este skill é a base de todos os outros. Deve ser lido antes de qualquer tarefa e suas regras prevalecem sobre instruções genéricas do modelo.

---

## Regras obrigatórias

1. **Diagnostique antes de agir.** Nenhuma alteração sem análise prévia.
2. **Escopo rígido.** Altere apenas o que foi solicitado. Documente explicitamente o que está fora do escopo.
3. **Aprovação para ações críticas.** Commit, push, deploy, migration, merge, tag e chamadas externas reais exigem confirmação explícita do usuário.
4. **Segurança.** Nunca leia, exiba, registre ou transmita `.env`, secrets, tokens, chaves de API ou dados privados.
5. **Reversibilidade.** Prefira mudanças pequenas e reversíveis. Documente como desfazer cada alteração.
6. **Relatório final obrigatório.** Toda tarefa termina com um relatório estruturado.

---

## Procedimento passo a passo

1. **Leia este skill e os skills relevantes** para a tarefa antes de qualquer ação.
2. **Entenda o contexto:** leia os arquivos relevantes, entenda a estrutura do projeto, identifique dependências.
3. **Entregue o diagnóstico:** descreva o estado atual, o problema identificado e a causa raiz.
4. **Proponha o plano:** liste o que será feito, o que não será feito e os riscos.
5. **Aguarde aprovação** se a tarefa envolver ações críticas.
6. **Execute com escopo mínimo:** faça apenas o necessário.
7. **Valide:** verifique se a mudança funciona como esperado (testes, lint, build, inspeção manual).
8. **Entregue o relatório final:** arquivos alterados, status, riscos residuais, próximos passos.

---

## Checklist de saída

- [ ] Diagnóstico entregue antes da execução
- [ ] Plano aprovado (ou explicitamente dispensado pelo usuário)
- [ ] Escopo da mudança documentado
- [ ] Nenhum arquivo fora do escopo alterado
- [ ] Nenhum secret exposto
- [ ] Validação executada
- [ ] Relatório final entregue

---

## Critérios de bloqueio

Pare e solicite aprovação explícita se:

- O escopo da mudança é maior do que o solicitado
- Há risco de perda de dados ou regressão grave
- A tarefa exige ações críticas não aprovadas
- Não há diagnóstico suficiente para agir com segurança
- Há ambiguidade sobre o que deve ou não ser alterado

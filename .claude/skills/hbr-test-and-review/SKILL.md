# HBR Test and Review

## Descrição
Protocolo para garantir que toda alteração de código seja validada por testes, lint e revisão de diff antes de ser entregue. Define critérios de aceite mínimos para qualquer mudança.

## Quando usar
- Após qualquer alteração de código
- Ao criar ou modificar testes
- Ao revisar um pull request ou diff
- Antes de qualquer commit ou entrega ao usuário

---

## Regras obrigatórias

1. **Nenhuma entrega sem validação.** Toda mudança deve passar por pelo menos uma forma de verificação.
2. **Testes existentes não podem ser quebrados.** Se uma mudança quebra testes existentes, investigue antes de entregar.
3. **Lint e build quando disponíveis.** Execute lint e build se o projeto os suporta.
4. **Revise o diff completo** antes de entregar — não apenas as linhas alteradas.
5. **Critérios de aceite explícitos.** Defina e comunique o que significa "funcionando corretamente" antes de executar.

---

## Procedimento passo a passo

1. **Defina os critérios de aceite** antes de implementar: o que deve ser verdadeiro quando a tarefa estiver completa?
2. **Após a implementação, execute:**
   - `lint` (se configurado no projeto)
   - `build` (se aplicável)
   - `testes unitários/integração` relevantes à mudança
3. **Revise o diff completo:**
   - Há alterações fora do escopo?
   - Há código comentado ou debug esquecido?
   - Há imports não utilizados?
   - Há secrets ou dados sensíveis expostos?
4. **Se testes falharem:**
   - Identifique se a falha é causada pela mudança ou era pré-existente
   - Corrija a causa raiz antes de entregar
   - Nunca desative ou delete testes para fazer a mudança passar
5. **Documente no relatório:** quais testes foram executados, quais passaram, quais falharam e por quê.

---

## Checklist de saída

- [ ] Critérios de aceite definidos antes da implementação
- [ ] Lint executado (ou justificativa de por que não foi)
- [ ] Build executado (ou justificativa)
- [ ] Testes relevantes executados
- [ ] Nenhum teste existente quebrado sem justificativa
- [ ] Diff revisado: sem alterações fora do escopo
- [ ] Diff revisado: sem debug/console.log esquecido
- [ ] Diff revisado: sem secrets expostos
- [ ] Resultado da validação documentado no relatório

---

## Critérios de bloqueio

Não entregue a mudança se:

- Lint ou build falham com erros (não warnings)
- Testes que cobriam o código alterado estão falhando
- O diff contém secrets, tokens ou dados sensíveis
- Os critérios de aceite não foram atingidos
- Há alterações fora do escopo que não foram aprovadas

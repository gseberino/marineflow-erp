# HBR Test and Review

## Descrição
Protocolo de validação obrigatória para toda alteração de código. Para uso por Codex e outros agentes.

## Quando usar
- Após qualquer alteração de código
- Ao criar ou revisar testes
- Ao revisar um pull request ou diff
- Antes de qualquer commit ou entrega

---

## Regras obrigatórias

1. **Nenhuma entrega sem validação.**
2. **Testes existentes não podem ser quebrados.**
3. **Lint e build quando disponíveis.**
4. **Revise o diff completo** antes de entregar.
5. **Critérios de aceite explícitos** antes de implementar.

---

## Procedimento passo a passo

1. **Defina critérios de aceite** antes de implementar.
2. **Execute após implementação:** lint, build, testes relevantes.
3. **Revise o diff:**
   - Alterações fora do escopo?
   - Debug ou console.log esquecido?
   - Imports não utilizados?
   - Secrets expostos?
4. **Se testes falharem:** identifique se a falha é nova ou pré-existente. Corrija a causa raiz.
5. **Documente no relatório:** testes executados, passaram/falharam, motivo.

---

## Checklist de saída

- [ ] Critérios de aceite definidos
- [ ] Lint executado
- [ ] Build executado
- [ ] Testes relevantes executados
- [ ] Nenhum teste existente quebrado
- [ ] Diff revisado: sem escopo extra, sem debug, sem secrets
- [ ] Resultado documentado

---

## Critérios de bloqueio

Não entregue se:

- Lint ou build falham com erros
- Testes que cobriam o código alterado estão falhando
- Diff contém secrets ou dados sensíveis
- Critérios de aceite não foram atingidos

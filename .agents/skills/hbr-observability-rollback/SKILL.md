# HBR Observability & Rollback

## Descrição
Protocolo para rastreabilidade, auditoria, documentação de riscos e rollback. Para uso por Codex e outros agentes.

## Quando usar
- Antes de mudanças em produção ou código crítico
- Ao planejar migrations de banco
- Ao modificar autenticação, autorização ou dados
- Ao entregar mudanças com risco de regressão

---

## Regras obrigatórias

1. **Toda mudança deve ter rollback documentado.**
2. **Logs sanitizados:** nunca registre secrets, tokens ou PII.
3. **Documente riscos** antes de executar.
4. **Prefira migrações aditivas a destrutivas.**
5. **Nunca execute rollback destrutivo** sem aprovação explícita.

---

## Procedimento passo a passo

1. **Antes da mudança:**
   - Documente o estado atual
   - Identifique o ponto de rollback
   - Liste riscos e probabilidades

2. **Durante a execução:**
   - Mudanças incrementais: uma por vez
   - Registre arquivos alterados
   - Se falhar, pare e reporte — não corrija sem diagnóstico

3. **Logs de auditoria:**
   - Timestamp, ação, arquivos afetados, resultado
   - Nunca registre credenciais

4. **Formato de documentação de risco:**
   ```
   Risco: [descrição]
   Probabilidade: [baixa/média/alta]
   Impacto: [baixo/médio/alto]
   Mitigação: [o que fazer]
   Rollback: [como desfazer]
   ```

5. **Após a mudança:**
   - Confirme comportamento esperado
   - Confirme que adjacências não foram afetadas

---

## Checklist de saída

- [ ] Estado anterior documentado
- [ ] Riscos identificados
- [ ] Rollback definido
- [ ] Mudança incremental
- [ ] Logs sem secrets
- [ ] Comportamento esperado confirmado
- [ ] Relatório de auditoria entregue

---

## Critérios de bloqueio

Pause se:

- A mudança não tem rollback seguro
- Impacto de falha é alto
- A mudança é destrutiva
- Não há como verificar o sucesso sem acesso a produção

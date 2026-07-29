# HBR Observability & Rollback

## Descrição
Protocolo para garantir rastreabilidade, auditoria, documentação de riscos e capacidade de rollback em todas as mudanças. Toda alteração deve ser observável e reversível.

## Quando usar
- Antes de qualquer mudança em produção ou em código crítico
- Ao planejar migrations de banco de dados
- Ao modificar configurações de infraestrutura
- Ao alterar fluxos de autenticação, autorização ou dados
- Ao entregar qualquer mudança com risco de regressão

---

## Regras obrigatórias

1. **Toda mudança deve ter um caminho de rollback documentado.**
2. **Logs devem ser sanitizados:** nunca registre secrets, tokens, PII ou dados sensíveis.
3. **Run IDs e timestamps** devem ser usados para rastrear execuções de agentes quando aplicável.
4. **Documente os riscos** de cada mudança antes de executá-la.
5. **Prefira migrações aditivas a destrutivas** (adicionar coluna é mais seguro que remover).
6. **Nunca execute rollback destrutivo** (drop table, delete sem where, reset --hard) sem aprovação explícita.

---

## Procedimento passo a passo

1. **Antes de qualquer mudança crítica:**
   - Documente o estado atual (qual é o comportamento esperado antes da mudança)
   - Identifique o ponto de rollback (qual commit/estado restaurar em caso de falha)
   - Liste os riscos e probabilidade de cada um

2. **Durante a execução:**
   - Prefira mudanças incrementais: uma mudança de cada vez
   - Mantenha registro das alterações feitas (arquivo por arquivo)
   - Se algo falhar, pare imediatamente e reporte — não tente corrigir sem diagnóstico

3. **Ao criar logs de auditoria:**
   - Use IDs únicos para cada execução quando possível
   - Registre: timestamp, ação executada, arquivos afetados, resultado
   - Nunca registre valores de variáveis de ambiente ou credenciais

4. **Documentação de riscos (formato mínimo):**
   ```
   Risco: [descrição]
   Probabilidade: [baixa/média/alta]
   Impacto: [baixo/médio/alto]
   Mitigação: [o que fazer se acontecer]
   Rollback: [como desfazer]
   ```

5. **Após a mudança:**
   - Confirme que o comportamento esperado foi atingido
   - Confirme que funcionalidades adjacentes não foram afetadas
   - Documente o estado pós-mudança

---

## Checklist de saída

- [ ] Estado anterior documentado
- [ ] Riscos identificados e documentados
- [ ] Caminho de rollback definido e documentado
- [ ] Mudança executada incrementalmente
- [ ] Logs não contêm secrets ou dados sensíveis
- [ ] Comportamento esperado confirmado após a mudança
- [ ] Funcionalidades adjacentes verificadas
- [ ] Relatório de auditoria entregue

---

## Critérios de bloqueio

Pause e solicite aprovação se:

- A mudança não tem rollback seguro identificado
- O impacto de falha é classificado como alto
- A mudança é destrutiva (drop, delete em massa, reset)
- Não há como verificar o sucesso da mudança sem acesso a produção
- A mudança afeta dados de usuários em produção

# HBR n8n Workflow Engineer

## Descrição
Padrões seguros para criação e revisão de workflows n8n. Para uso por Codex e outros agentes.

## Quando usar
- Ao criar ou modificar workflows n8n
- Ao integrar WhatsApp, Google Calendar ou outros serviços
- Ao configurar webhooks
- Ao construir agentes de IA no n8n

---

## Regras obrigatórias

1. **Nunca ative workflows reais** sem aprovação.
2. **Nunca use credenciais reais** em exemplos.
3. **Todo webhook deve ter validação** (HMAC, token ou whitelist de IP).
4. **Todo workflow deve ter Error Workflow.**
5. **Deduplicação obrigatória** para workflows que processam mensagens.
6. **Kill switch obrigatório** em workflows de produção.
7. **Logs sanitizados:** sem PII ou secrets.

---

## Procedimento passo a passo

1. **Defina o trigger:** Webhook, Schedule, evento de sistema?
2. **Mapeie o happy path** antes de pensar em erros.
3. **Implemente validação de entrada:** campos obrigatórios, tipos, assinatura.
4. **Implemente deduplicação** via campo único (messageId, eventId).
5. **Configure Error Workflow:** captura erro, workflow ID, execution ID, notifica sem expor dados sensíveis.
6. **Adicione Kill Switch:** variável ou campo `WORKFLOW_ENABLED`.
7. **Documente:** nome, propósito, trigger, integrações, dependências.

### WhatsApp
- Valide assinatura do webhook antes de processar
- Deduplicar por `message.id`
- Responda dentro de 10s — use filas para processamento lento

### Google Calendar
- OAuth com escopos mínimos
- Nunca armazene refresh tokens em código
- Valide conflitos de horário antes de criar eventos

### Agentes de IA
- Ferramentas com escopo mínimo
- Limite `max_iterations`
- Sanitize dados antes de passar ao prompt

---

## Checklist de saída

- [ ] Trigger documentado
- [ ] Validação de entrada implementada
- [ ] Deduplicação implementada
- [ ] Error Workflow configurado
- [ ] Kill Switch implementado
- [ ] Sem credenciais reais em exemplos
- [ ] Logs sanitizados
- [ ] Workflow documentado
- [ ] Nenhum workflow ativado sem aprovação

---

## Critérios de bloqueio

Pause se:

- O workflow será ativado em produção
- Processa dados de usuários reais
- Tem side effects irreversíveis (mensagens enviadas, cobranças)
- Não tem Error Workflow configurado

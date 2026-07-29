# HBR n8n Workflow Engineer

## Descrição
Padrões e boas práticas para criação, modificação e revisão de workflows n8n. Cobre integrações com WhatsApp, Google Calendar, agentes de IA, webhooks, deduplicação, error handling e kill switch.

## Quando usar
- Ao criar ou modificar workflows n8n
- Ao integrar n8n com WhatsApp, Google Calendar ou outros serviços externos
- Ao configurar webhooks de entrada ou saída
- Ao construir agentes de IA com memória, ferramentas ou RAG dentro do n8n
- Ao revisar workflows existentes para segurança ou qualidade

---

## Regras obrigatórias

1. **Nunca ative workflows reais** sem aprovação explícita do usuário.
2. **Nunca use credenciais reais** em exemplos de código ou documentação.
3. **Todo webhook de entrada deve ter validação** (assinatura HMAC, token ou whitelist de IP).
4. **Todo workflow deve ter um Error Workflow** configurado.
5. **Todo workflow que processa mensagens deve ter deduplicação** para evitar processamento duplo.
6. **Kill switch obrigatório** em workflows de produção: uma variável ou nó que permita desativar o fluxo sem deletar o workflow.
7. **Nunca transmita dados de usuários** para nós de debug ou logs sem sanitização.

---

## Procedimento passo a passo

### Criação de novo workflow

1. **Defina o trigger:** Webhook, Schedule, ou evento de sistema?
2. **Mapeie o fluxo feliz** (happy path) antes de pensar em erros.
3. **Adicione validação na entrada:**
   - Verifique campos obrigatórios
   - Valide tipos de dados
   - Verifique assinatura do webhook se aplicável
4. **Implemente deduplicação** se o workflow pode receber o mesmo evento mais de uma vez:
   - Use um campo único (messageId, eventId) para verificar duplicatas
   - Armazene IDs processados (Redis, Supabase, ou Static Data do n8n)
5. **Construa os nós de processamento** com tratamento de erro em cada nó crítico.
6. **Configure o Error Workflow:**
   - Capture o erro, o workflow ID e o execution ID
   - Notifique o canal de alertas (Slack, e-mail, etc.)
   - Nunca exponha dados sensíveis na notificação de erro
7. **Adicione o Kill Switch:**
   - Nó de verificação no início do workflow
   - Variável de ambiente ou campo em banco: `WORKFLOW_ENABLED = true/false`
8. **Documente o workflow:** nome, propósito, trigger, integrações, dependências.

### Padrões para WhatsApp

- Sempre valide a assinatura do webhook antes de processar
- Deduplicar por `message.id`
- Nunca armazene o conteúdo de mensagens em logs não sanitizados
- Responda dentro do timeout do webhook (< 10s) — use filas para processamento lento

### Padrões para Google Calendar

- Use OAuth com escopos mínimos necessários
- Nunca armazene refresh tokens em código — use credenciais do n8n
- Valide conflitos de horário antes de criar eventos

### Padrões para Agentes de IA no n8n

- Defina ferramentas com escopo mínimo
- Limite o número de iterações do agente (max_iterations)
- Nunca passe dados sensíveis diretamente ao prompt sem sanitização
- Documente quais ferramentas o agente pode usar e por quê

---

## Checklist de saída

- [ ] Trigger definido e documentado
- [ ] Validação de entrada implementada
- [ ] Deduplicação implementada (se aplicável)
- [ ] Error Workflow configurado
- [ ] Kill Switch implementado
- [ ] Nenhuma credencial real em exemplos
- [ ] Logs sanitizados (sem PII ou secrets)
- [ ] Workflow documentado (nome, propósito, dependências)
- [ ] Nenhum workflow ativado sem aprovação

---

## Critérios de bloqueio

Pause e solicite aprovação se:

- O workflow será ativado em ambiente de produção
- O workflow processa dados de usuários reais
- A integração requer credenciais que não estão configuradas no n8n
- O workflow tem side effects irreversíveis (envio de mensagens, criação de registros, cobrança)
- Não há Error Workflow configurado para um workflow crítico

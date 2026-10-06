# Acompanhar conversa, lembrar de responder e cumprir o prometido

**Pedido do dono (06/10/2026):** "acompanhe a conversa do Miguel e me mantenha informado" — o
assistente lembra, num intervalo, que há resposta pendente e já sugere a resposta, enviada só com a
confirmação. Mais: "me lembra de responder o Nelson às 14h", lembrete do que o dono PROMETEU numa
conversa ("te mando amanhã"), e tirar o ruído do resumo das 07:30. Pediu as três frentes juntas.

## Por que (medido)

- 30/08: dos 68 fios soltos, só 2 eram espera de terceiro — o gargalo é a HBR CUMPRIR/RESPONDER
  (project_marineflow_fios_direcao_invertida). Este plano ataca isso de frente.
- 06/10: de 93 contatos que conversaram em 30 dias, 83 terminam com mensagem da outra pessoa; 74 há
  mais de 24h. Muito é ruído (fornecedor, "ok, obrigado") — por isso acompanhar é ESCOLHA do dono.
- Mercado: Gmail Nudges (2018), Superhuman "Remind me if no reply", Chatwoot SLA/"não atendidas",
  Smart Reply (KDD 2016), Meta Business Agent (resumo de conversas perdidas). Risco conhecido:
  lembrete demais vira ruído — por isso escolha explícita, teto diário e "adiar".

## Desenho

Peças que JÁ existem e são reaproveitadas:
- `whatsapp_messages` registra também o que o dono manda direto do celular (fromMe → outbound).
- Leitura (`get_whatsapp_conversation`), roteiro "ajudar a responder" e `send_whatsapp_message` com
  confirmação que mostra a última mensagem da pessoa (16cea629).
- O canal do assistente no WhatsApp (`ai-agent`, `x-internal-secret`): o aviso automático entra
  pelo MESMO caminho de uma mensagem do dono — Max ou OpenRouter, mesmas travas, mesma confirmação.
- Pendência viva + "uma por conversa" (05/10).

### 1. Tabela `whatsapp_acompanhamentos`
Um registro por pedido: telefone e nome do contato, `modo` (acompanhar | lembrar_em | promessa),
intervalo, prazo (`ate`), `lembrar_em`, texto da promessa, status (ativo/encerrado + motivo),
`ultimo_aviso_em`, `avisos_hoje`/`avisos_dia`. RLS: só admin lê pela API; o resto pela chave de
serviço (edge). Um ativo por telefone+modo acompanhar (índice parcial).

### 2. Ferramentas do assistente
- `acompanhar_conversa(contato|phone|client_id, intervalo_horas=2, ate=+7 dias, lembrar_em?)`:
  com `lembrar_em` vira lembrete único ("me lembra de responder o Nelson às 14h"). Risco baixo:
  interno, não fala com ninguém.
- `listar_acompanhamentos`, `parar_acompanhamento(contato|id)`.

### 3. Vigia `acompanhar-conversas` (edge, cron a cada 15 min)
Só entre 8h e 20h de Brasília, seg–sáb. Em cada rodada:
1. **Promessas:** lê as mensagens que o dono mandou desde a última rodada (cursor em app_settings)
   e procura promessa por padrão de texto ("te mando amanhã", "vou ver e te retorno", "segunda te
   passo"...), sem IA. Achou → acompanhamento `promessa` com hora (amanhã → 09:00; dia da semana →
   09:00 daquele dia; "mais tarde/hoje" → +3h; sem tempo → +24h). Interruptor
   `acompanhar_promessas` (on).
2. **Avisos devidos:**
   - acompanhar: a última mensagem é do contato, há mais que o intervalo, e o último aviso foi há
     mais que o intervalo → aviso. Teto 3 por conversa/dia. Prazo vencido → encerra.
   - lembrar_em / promessa: chegou a hora → aviso único → encerra.
   - Pula se o dono tem uma confirmação aberta (não atropelar o "sim" dele).
   - Teto global de 6 avisos por rodada.
3. **O aviso:** POST ao `ai-agent` como se fosse o dono ("🤖 Acompanhamento: o Miguel espera há 3h;
   leia a conversa e sugira a resposta"). O assistente lê, sugere e chama `send_whatsapp_message`:
   o dono recebe o contexto + a confirmação (sim / "não, muda…" / "adiar 1h").

### 4. Resumo das 07:30 sem ruído
Nova função `whatsapp_esperando_resposta` (a antiga fica para quem já usa): marca categoria
(cliente / fornecedor / contato) e "encerrada" (última mensagem é só "ok", "obrigado", 👍…). O
resumo mostra clientes primeiro, fornecedores à parte, e só conta as encerradas.

## Fora do escopo agora
- Notificar a cada mensagem nova (o intervalo cobre o "me mantenha informado" sem ruído).
- Detectar promessa por IA (o padrão de texto é grátis; IA só se a medição pedir).

## Medição (2 semanas)
Avisos enviados × respondidos com *sim* × "não/adiar" × ignorados; promessas detectadas × falsas.
Consulta em `whatsapp_acompanhamentos` + `ai_operator_pending_actions`.

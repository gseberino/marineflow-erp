# MarineFlow · Camada de Inteligência de Comunicação (plano-piloto)

> Visão/racional (com pesquisa e antes/depois): artifact
> https://claude.ai/code/artifact/34f26cfb-673e-4d49-a3bd-cf888cf19c24
>
> Este arquivo é a contraparte de EXECUÇÃO: onde mexer, o que testar, como medir.

## Princípio
O agente já **age** bem; o próximo salto é **falar** bem — a mesma ação no registro certo
para cada interlocutor, no tamanho certo, na hora certa, aprendendo o jeito de cada contato.
Fundamento: máximas de Grice (Quantidade, Qualidade, Relevância, Modo) → regras concretas.

## Estado atual (base)
- Persona única em `supabase/functions/_shared/ai/prompt.ts` (centrada no dono).
- Regras de mensagem espalhadas por fluxo (cobrança, cotação, follow-up).
- Já entregue: cotação enxuta + card com nome/telefone (commit 68b8a98).
- Memória de entidade existe (`ai_operator_memory_notes`, `remember_about_entity`) — base do "perfil por contato".
- Canais: painel (markdown) e WhatsApp (texto simples) via `runAgentLoop`.

## Módulos (ver artifact para o porquê)
A. Motor de Registro (audiência×canal → perfil de voz)
B. Biblioteca de Exemplares (few-shot ruim→bom, injeção por tipo)
C. Perfil de Comunicação por Contato (nome usado, tom, horário, RELAÇÃO no corpo da msg)
D. Cadência Inteligente (não repetir, escalonar, espaçar, teto)
E. Portão de Qualidade pré-envio (linter de comunicação)
F. Loop de Aprendizado (edições → preferência; enviado×resposta)
G. **Manejo de Resposta (inbound)** [3 assentos] — classifica a resposta (disputa/pergunta/
   parcial/acordo/"pare"), de-escala cobrança, aceita cotação parcial, passa ao humano, opt-out.
H. **Confiança Graduada** [3 assentos] — auto-envio de tipos de baixo risco por audiência via o
   dial de autonomia existente; dinheiro/cobrança NUNCA.

## O que os "três assentos" (dono/cliente/fornecedor) acrescentaram ao plano
- **Inbound é metade da conversa** → módulo G (o plano era só outbound).
- **Dono é gargalo e quer confiança graduada** → módulo H.
- **Marca+lei são o medo do dono** → guardrails de conformidade (CDC/LGPD) como TRAVA DURA:
  cobrança sem constrangimento, não expor dívida a terceiros, horário permitido, identidade
  anti-golpe, e trava de "audiência errada" (preço a técnico, dado de cliente a fornecedor,
  número não identificado). O dono AUTORA a voz de marca e aprova os exemplares.
- **Mesmo conteúdo, renderização diferente**: técnico (SKU) p/ fornecedor, linguagem simples/
  benefício p/ cliente — regra explícita, não só "tom".
- **Reconhecimento/relação**: trazer contexto (barco, última visita, manias do fornecedor)
  para DENTRO da mensagem.

## FASE 0 — Fundação (semana 1)
**Objetivo:** motor de registro + linter, testáveis e atrás do fluxo atual.

1. `_shared/ai/comms/voice-profiles.ts` (novo)
   - `perfilDeVoz(audiencia: 'dono'|'cliente'|'fornecedor'|'tecnico', canal): VoiceProfile`
   - VoiceProfile: `{ registro, tetoLinhas, saudacao, fecho, proibicoes: string[] }`.
   - Fonte da matriz: a tabela do artifact (seção 04).
2. `_shared/ai/comms/message-linter.ts` (novo, PURO/testável)
   - `revisarMensagem(texto, perfil): { ok, problemas: {codigo, trecho}[], sugestao? }`
   - Heurísticas iniciais (fornecedor/cliente):
     - razão social na saudação (padrões: LTDA|EIRELI|ME|S/A|nomes caixa-alta longos);
     - "para/pra que serve" / descrição de aplicação;
     - prazo estipulado pelo remetente ("prazo desejado", "o mais breve");
     - tutorial de resposta ("responda com", "Ex.: \"1 - R$");
     - excesso de tamanho vs `tetoLinhas`.
   - **fail-open**: em erro, retorna ok (não trava envio) — igual ao guard.
2b. `_shared/ai/comms/compliance-guard.ts` (novo) — travas DURAS (NÃO fail-open; estas
   BLOQUEIAM): audiência errada (preço/custo a técnico, dado de cliente a fornecedor, número
   não identificado), cobrança que exponha a dívida a terceiros, envio fora de horário
   permitido. Fonte: CDC art. 42 (sem constrangimento) + LGPD. É o medo nº 1 do dono.
3. Ligar o linter nas tools de envio externo (`whatsapp.ts`: send_supplier_quote_request,
   send_collection_reminder, send_service_order_link, schedule_whatsapp_message) — só
   **avisa/registra** nesta fase (não bloqueia), para calibrar sem risco.
4. Testes: `voice-profiles_test.ts`, `message-linter_test.ts` (casos reais: a msg de
   fornecedor "antes" reprova; a "depois" passa; cobrança fria reprova).
5. Deploy `ai-agent`. Sem mudança de comportamento visível (só telemetria do linter).

**Gate:** linter classifica corretamente os exemplos reais; suíte verde; deno check limpo.

## FASE 1 — Exemplares + perfil por contato (semana 2)
1. `_shared/ai/comms/exemplars.ts`: pares ruim→bom para cotação, cobrança, follow-up.
   Injetar SÓ o exemplar do tipo detectado no prompt daquele turno (barato em tokens).
2. Perfil por contato:
   - migration aditiva: `suppliers.display_name` / `clients.display_name` (nome usado) e
     `communication_tone` (nullable). Semear `display_name` do histórico quando houver.
   - o agente passa a usar `display_name` na saudação (fallback: sem nome, como hoje).
3. **Renderização por audiência**: `renderizarItem(item, audiencia)` — técnico/SKU para
   fornecedor, linguagem simples/benefício para cliente ("o controlador solar do seu sistema").
   E injetar contexto de relação (barco, última visita) no corpo, vindo de get_client_360/notas.
4. Prompt: seção "Registro por interlocutor" apontando para o motor + regra de usar nome usado.
5. Testes + deploy.

**Gate:** cotação/cobrança/follow-up saem no registro certo em cenários de teste; nome fantasia
usado quando existe; item técnico traduzido para o cliente.

## FASE 2 — Inbound + cadência + aprendizado (semana 3–4)
0. **Manejo de Resposta (G)** [3 assentos] — `_shared/ai/comms/reply-router.ts`: ao chegar
   resposta de cliente/fornecedor a uma cobrança/cotação/follow-up, classificar a intenção
   (disputa · pergunta · cotação parcial · acordo · "pare/opt-out"). Regras:
   - **disputa** ("serviço deu problema", "já paguei") → NÃO reenviar cobrança; escalar ao dono
     com contexto.
   - **pergunta do fornecedor** ("qual bitola?") → responder se souber, senão passar ao dono.
   - **cotação parcial** ("tenho 1, 3 e 5") → record_quote_response só do que veio, sem cobrar o resto.
   - **"pare"** → marcar opt-out do contato (respeitar em todos os envios).
   Passar-pro-humano é SUCESSO, não falha.
1. Cadência: contador de toques por `service_order`/`collection`; cada toque gera mensagem
   diferente (o LLM recebe "toque N, valores já ditos: …"); espaçar 3–4 dias; horário
   comercial; teto de toques. Integrar com "não cobrar 2× no mesmo dia" (já existe em
   get_delinquency_plan/last_auto_sent_at).
2. Portão de Qualidade v2: passa a **reescrever** (não só avisar) quando reprova, e o card
   mostra a versão final. Ainda pede confirmação (nada autônomo).
3. Loop de aprendizado:
   - quando o dono edita/rejeita uma mensagem → `remember_note` categoria "comunicacao",
     escopada por audiência/contato; injeção dessas notas no motor de registro.
   - log `enviado × resposta` por tipo (tabela leve) — matéria-prima de "o que converte".

**Gate:** dois toques de follow-up nunca são iguais; edição do dono vira preferência aplicada
no próximo; telemetria de resposta populando.

## FASE 3 — Medir, graduar confiança e expandir (contínuo)
- **Confiança Graduada (H)** [3 assentos]: com as métricas provando a qualidade, liberar
  auto-envio de tipos de BAIXO risco por audiência (ex.: 1º follow-up, RFQ a fornecedor) via o
  dial de autonomia (`set_tool_autonomy`, NEVER_AUTONOMOUS protege dinheiro/cobrança). Tira o
  dono do gargalo sem tirar o controle.
- Comparar nº de edições do dono e taxa de resposta antes/depois.
- Ajustar exemplares pelos que performam.
- Expandir perfis: agendamento, NF-e enviada, reativação, técnico em campo.

## Métricas
- ↓ edições/rejeições do dono por mensagem.
- ↑ taxa de resposta (fornecedor/cliente).
- = consistência: 100% das mensagens externas passam o portão (zero vício reincidente).
- ↓ **atrito do destinatário** [3 assentos]: taxa de opt-out, de disputa e de "passar pro
  humano". + atribuição (a mensagem levou ao pagamento/negócio?).

## Guardrails
- Todo envio externo continua pedindo confirmação (card com a msg final). Dinheiro nunca autônomo.
- Empatia ≠ manipulação: cobrança oferece opções, nunca ameaça/urgência falsa (máxima da Qualidade).
- **Conformidade Brasil (CDC/LGPD)** [3 assentos]: cobrança sem constrangimento nem exposição da
  dívida a terceiros; horário permitido; identidade consistente e anti-golpe; direito de contestar
  e de parar de receber; dado sensível nunca é pedido. Estas são TRAVAS DURAS (bloqueiam).
- **Passar pro humano é sucesso**: resposta fora do script (disputa/pergunta técnica/cliente
  irritado) → escala ao dono com contexto, em vez de insistir.
- Linter de estilo fail-open; guard de conformidade é trava dura. Diffs estreitos, teste por item.
  Trabalhar em worktree isolado (ver skill multi-session-guard) se houver outra sessão ativa.

## Fontes
Google Conversation Design (Cooperative Principle), ServiceNow, WhatsApp Business, Customer.io,
Moveo.ai / Tratta (cobrança), Cirrus Insight / Tendril (cadência B2B), PromptHub / Future AGI
(controle de tom e deriva de persona em LLM). Links no artifact.

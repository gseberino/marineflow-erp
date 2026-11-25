-- Rota das mensagens do dono (pacote 1, C4, 25/11/2026)
--
-- Para o suporte responder "para onde foi a minha mensagem das 14h?". Só leitura, e SEM o texto de mensagem nenhuma:
-- as consultas leem horário, tipo e a rota gravada em ai_operator_audit (event_type 'rota:<camada>').
-- Quem grava a rota: supabase/functions/_shared/ai/rota-da-mensagem.ts (chamado pelo ai-agent e pelo whatsapp-webhook).
--
-- Só há rota para as mensagens que chegaram DEPOIS de o C4 ser publicado: as anteriores aparecem como 'SEM ROTA'.
--
-- Camadas: limite_por_minuto, nao_autorizado, orcamento, parceiro, retorno, trava_comprovante, trava_agenda,
--   confirmacao, pin_na_frase, secretario, agenda, atalho_pdf, modelo_max (virou pedido para o Claude; a resposta
--   aparece na coluna "entrega"), modelo_openrouter, aviso_falha (o Claude não pôde atender; o detalhe é a causa),
--   comprovantes (a conversa dos comprovantes tratou; não foi ao assistente), despacho_falhou (o ai-agent não tratou a
--   mensagem; o detalhe é o status), erro (o turno lançou), desconhecida (saída que a rota não conhece: avisar).
-- Entrega (do pedido ao Claude): resposta, cartao, lista, fluxo, interrompido:<código>, aviso:<causa>, reserva.


-- ═══ 1) As últimas 50 mensagens do dono e a rota de cada uma ═══════════════════════════════════════════════════════
-- 'SEM ROTA' = mensagem que nenhuma camada registrou: é o buraco a investigar.

with dono as (
  select phone_normalized from public.app_users where role = 'admin' and ai_whatsapp_enabled and active
),
m as (
  select id, created_at, message_type
    from public.whatsapp_messages
   where direction = 'inbound' and phone_normalized in (select phone_normalized from dono)
   order by created_at desc
   limit 50
),
r as (
  select payload->>'mensagem_id' as mid, split_part(event_type, ':', 2) as camada, payload->>'detalhe' as detalhe,
         payload->>'job_id' as job, created_at
    from public.ai_operator_audit
   where event_type like 'rota:%' and created_at > now() - interval '30 days'
)
select to_char(m.created_at at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI:SS') as quando,
       m.message_type,
       coalesce(string_agg(r.camada || coalesce(':' || r.detalhe, ''), ' → ' order by r.created_at), 'SEM ROTA') as rota,
       max(r.job) as job,
       (select e.payload->>'detalhe'
          from public.ai_operator_audit e
         where e.event_type = 'rota:entrega' and e.payload->>'job_id' = max(r.job)
         limit 1) as entrega
  from m
  left join r on r.mid = m.id::text
 group by m.id, m.created_at, m.message_type
 order by m.created_at desc;


-- ═══ 2) Quantos pares de mensagens chegaram a menos de N segundos uma da outra (só contagem) ═══════════════════════
-- É a medida que decide o "um turno por vez" (C1, adiado para depois de 2 a 3 semanas de rastro no ar).
-- Troque N e a janela na primeira linha. O que cada número diz:
--   pares_em_ate_n_s ............ a segunda mensagem chegou até N segundos depois da primeira
--   segunda_com_a_primeira_rodando  a segunda chegou ANTES de a primeira terminar: é o caso que o C1 seguraria
--   as_duas_foram_ao_modelo ..... desses, os dois turnos foram ao Claude ao mesmo tempo (leram a mesma conversa)
--   a_primeira_abriu_cartao ..... desses, a primeira terminou num cartão de confirmação (o "sim" que se perde)
--   pares_com_mensagem_sem_rota . pares em que uma das duas não tem rota (anterior ao C4, ou buraco a investigar)
-- "Terminar" = a entrega do pedido ao Claude (rota:entrega com o mesmo job_id) ou, nas camadas que respondem na
-- hora, a gravação da própria rota. Pedido sem entrega gravada conta como terminado na chegada (subestima).

with param as (
  select 60 as n_segundos, interval '21 days' as janela
),
dono as (
  select phone_normalized from public.app_users where role = 'admin' and ai_whatsapp_enabled and active
),
r as (
  select payload->>'mensagem_id' as mid, split_part(event_type, ':', 2) as camada, payload->>'detalhe' as detalhe,
         payload->>'job_id' as job, created_at as gravada
    from public.ai_operator_audit, param
   where event_type like 'rota:%' and created_at > now() - param.janela - interval '1 day'
),
entrega as (
  select job, max(gravada) as entregue_em, max(detalhe) as detalhe from r where camada = 'entrega' and job is not null group by job
),
rota as (  -- uma rota por mensagem (a primeira gravada)
  select distinct on (mid) mid, camada, job, gravada from r where camada <> 'entrega' and mid is not null order by mid, gravada
),
m as (
  select w.id, w.phone_normalized as fone, w.created_at as chegou, rota.camada,
         coalesce(entrega.entregue_em, rota.gravada) as terminou, entrega.detalhe as entrega
    from public.whatsapp_messages w
    join dono on dono.phone_normalized = w.phone_normalized
    cross join param
    left join rota on rota.mid = w.id::text
    left join entrega on entrega.job = rota.job
   where w.direction = 'inbound' and w.created_at > now() - param.janela
),
pares as (
  select a.camada as camada_1, b.camada as camada_2, a.entrega as entrega_1, b.chegou < a.terminou as rodando
    from m a
    join m b on b.fone = a.fone and b.chegou > a.chegou
    cross join param
   where b.chegou <= a.chegou + make_interval(secs => param.n_segundos)
)
select (select n_segundos from param) as n_segundos,
       count(*) as pares_em_ate_n_s,
       count(*) filter (where rodando) as segunda_com_a_primeira_rodando,
       count(*) filter (where rodando and camada_1 = 'modelo_max' and camada_2 = 'modelo_max') as as_duas_foram_ao_modelo,
       count(*) filter (where rodando and entrega_1 = 'cartao') as a_primeira_abriu_cartao,
       count(*) filter (where camada_1 is null or camada_2 is null) as pares_com_mensagem_sem_rota
  from pares;

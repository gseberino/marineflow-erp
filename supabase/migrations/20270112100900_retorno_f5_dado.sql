-- Retorno rápido ao cliente, F5 (P9): a migration com dado. SÓ SOBE COM O OK "OK migration com dado da F5", e depois da P11 e
-- da P12 no ar (a tela e a ferramenta já pedem o motivo ao marcar perdido; sem isso, o CHECK quebraria o "rejeitar" deles).
-- É a última de propósito (seção 4: 100000 … 100800 → 100900).
--
-- 0. A trava "N ou 0": aborta a migration inteira (nada é gravado) se os rejeitados sem motivo não forem c_esperado nem 0
--    (0 = ela já rodou). No dia da aplicação, a sessão que coordena reconta só por leitura
--    (select count(*) from public.service_orders where quote_status = 'rejected' and motivo_perda is null), troca c_esperado
--    se o número mudou, roda de novo a P9.2 na bancada e faz o commit da troca antes de aplicar.
-- 1. Os antigos: os rejeitados sem motivo ficam como 'sem_motivo_antigo' (enunciado do K7: "ficam como 'sem motivo antigo',
--    sem trabalho seu"), com uma linha de audit_log por ordem de fato atualizada.
-- 2. A definição única de "rejeitado" (3.4): o CHECK service_orders_rejeitado_tem_motivo, só se ainda não existe.
-- 3. O padrão da empresa (K6): app_settings.quote_validity_days de 3 para 7, só se ainda é 3.
-- 4. O histórico com prova: o orçamento hoje em sent ou awaiting_approval, sem orcamento_enviado_em e fora de cliente
--    parceiro, ganha o 1º envio provado ao número do cliente (o whatsapp_send_api que deu certo, ou o eco do aparelho com
--    ORC-/ORÇ- no nome do arquivo), via 'historico', e a linha dele em orcamento_envios. Sem prova, fica nulo. Nunca abre
--    cadência (a via historico é inelegível, P3).
--
-- Idempotente: rodada de novo, a trava encontra 0, o update do item 1 não acha linha, o CHECK já existe (validar de novo não
-- falha), o item 3 só troca o 3 e o item 4 só olha quem ainda não tem orcamento_enviado_em (e o insert tem on conflict).
-- Nenhuma mensagem é lida: do eco sai só o número do documento no nome do arquivo, nunca o nome nem o corpo.
-- Reverter, sempre com where: alter table public.service_orders drop constraint service_orders_rejeitado_tem_motivo;
-- update public.service_orders set motivo_perda = null, motivo_perda_por = null where motivo_perda = 'sem_motivo_antigo';
-- update public.app_settings set value = '3' where key = 'quote_validity_days';
-- update public.service_orders set orcamento_enviado_em = null, orcamento_enviado_via = null, orcamento_enviado_chave = null
--  where orcamento_enviado_via = 'historico';
-- delete from public.orcamento_envios where via = 'historico';

-- 0. A trava (P9.1). c_esperado: o número contado só por leitura pela sessão que coordena (46 em 12/11/2026 e de novo em
--    13/11/2026: 45 orçamentos e 1 OS agendada). No dia da aplicação ela reconta e, se mudou, troca o número aqui e faz o
--    commit antes de aplicar.
do $$
declare
  c_esperado constant integer := 46;
  v_n integer;
begin
  select count(*) into v_n from public.service_orders where quote_status = 'rejected' and motivo_perda is null;
  if v_n <> c_esperado and v_n <> 0 then
    raise exception 'F5 (dado): % orçamento(s) rejeitado(s) sem motivo, e a migration espera % (ou 0, se já rodou). Nada foi gravado: reconte e troque c_esperado.',
      v_n, c_esperado using errcode = 'P0001';
  end if;
end $$;

-- 1. Os antigos (enunciado do K7: "ficam como 'sem motivo antigo', sem trabalho seu")
with feitos as (
  update public.service_orders
     set motivo_perda = 'sem_motivo_antigo', motivo_perda_por = 'migracao',
         motivo_perda_em = coalesce(motivo_perda_em, updated_at)
   where quote_status = 'rejected' and motivo_perda is null
  returning id
)
insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
select 'service_orders', f.id, 'update', 'migration 20270112100900',
       jsonb_build_object('motivo_perda', null),
       jsonb_build_object('motivo_perda', 'sem_motivo_antigo', 'motivo_perda_por', 'migracao'),
       'F5: rejeitado antigo sem motivo'
  from feitos f;                   -- uma linha por ordem DE FATO atualizada (returning). Na 2ª vez, 0 linhas.
                                   -- O molde é o do whatsapp-send (index.ts:430–438); changed_at e id ficam no padrão da coluna.

-- 2. A definição única (3.4), só se ainda não existe
do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'service_orders_rejeitado_tem_motivo'
                    and conrelid = 'public.service_orders'::regclass) then
    alter table public.service_orders add constraint service_orders_rejeitado_tem_motivo
      check (quote_status is distinct from 'rejected' or motivo_perda is not null) not valid;
  end if;
end $$;
alter table public.service_orders validate constraint service_orders_rejeitado_tem_motivo;   -- validar de novo não falha

-- 3. O padrão da empresa (K6): 3 → 7. A data do envio vem de retorno_config.validade_orcamento_dias; isto só alinha o
--    "Válido por N dias" do rascunho que ainda não saiu.
update public.app_settings set value = '7', updated_at = now() where key = 'quote_validity_days' and value = '3';

-- 4. O histórico com prova. Só orçamento aberto em sent/awaiting_approval, sem orcamento_enviado_em, fora de cliente parceiro.
--    Serve ao aceite e à medida; nunca abre cadência (P3: via historico é inelegível).
with abertos as (
  select so.id, so.client_id
    from public.service_orders so
   where so.status = 'draft' and so.converted_to_os_at is null and so.merged_into_id is null
     and so.quote_status in ('sent', 'awaiting_approval') and so.orcamento_enviado_em is null
     and not (so.client_id = any (coalesce((select c.clientes_parceiros from public.retorno_config c where c.id), '{}'::uuid[])))
),
provas as (
  -- (a) pelo sistema: a linha do whatsapp-send (whatsapp-send/index.ts:321-343) do envio que DEU CERTO. O audit_log grava
  --     também o que falhou (provider_result.ok = false), o desviado pelo modo de teste ([TEST MODE ACTIVE] no reason) e a
  --     recusa (chave 'recusado'): nenhum dos três é prova. O formato antigo (Z-API, até 09/05) tem http_status 200.
  select a.record_id as so_id, public._agenda_chave_telefone(a.new_value ->> 'phone') as chave, a.changed_at as em,
         null::uuid as msg_id
    from public.audit_log a
   where a.action = 'whatsapp_send_api' and a.table_name = 'service_orders' and a.new_value ->> 'context' = 'quote'
     and not (a.new_value ? 'recusado')
     and (a.new_value -> 'provider_result' ->> 'ok' = 'true' or a.new_value ->> 'http_status' = '200')
     and coalesce(a.reason, '') not like '%[TEST MODE ACTIVE]%'
  union all
  -- (b) do aparelho: o eco com ORC-/ORÇ- no nome (o critério dos passos 2 e 3 de orcamento_detectar_envio); só o número sai.
  select so.id, public._agenda_chave_telefone(w.phone_normalized), coalesce(w.hora_real, w.occurred_at), w.id
    from public.whatsapp_messages w
    cross join lateral regexp_match(lower(coalesce(w.raw_payload #>> '{data,message,documentMessage,fileName}', '')),
                                    '(?:^|[^a-z0-9])or[cç]-([0-9]{3,8})(?:[^0-9]|$)') as r(m)
    join public.service_orders so on so.service_order_number = 'ORÇ-' || r.m[1] and so.merged_into_id is null
   where w.direction = 'outbound' and w.message_type = 'document'
     and w.raw_payload ? 'data' and not (w.raw_payload ? 'via')
),
primeiro as (
  -- o 1º envio provado AO NÚMERO DO CLIENTE (a chave casa com o cadastro), fora de número confirmado de parceiro
  select distinct on (ab.id) ab.id as so_id, ab.client_id, p.chave, p.em, p.msg_id
    from abertos ab
    join provas p on p.so_id = ab.id
    join public.clients cl on cl.id = ab.client_id
   where p.chave is not null
     and p.chave in (public._agenda_chave_telefone(cl.whatsapp), public._agenda_chave_telefone(cl.phone))
     and not exists (select 1 from public.parceiro_numeros n where n.chave = p.chave and n.situacao = 'confirmado')
   order by ab.id, p.em, p.msg_id nulls first
),
gravados as (
  update public.service_orders so
     set orcamento_enviado_em = f.em, orcamento_enviado_via = 'historico', orcamento_enviado_chave = f.chave
    from primeiro f
   where so.id = f.so_id and so.orcamento_enviado_em is null
  returning so.id
)
insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em, whatsapp_message_id, marcou)
select f.so_id, f.client_id, 'historico', f.chave, true, f.em, f.msg_id, false
  from primeiro f
  join gravados g on g.id = f.so_id
on conflict do nothing;

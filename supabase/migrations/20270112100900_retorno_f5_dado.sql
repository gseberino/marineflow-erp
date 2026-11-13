-- Retorno rápido ao cliente, F5 (P9): a migration com dado. SÓ SOBE COM O OK "OK migration com dado da F5", e depois da P11 e
-- da P12 no ar (a tela e a ferramenta já pedem o motivo ao marcar perdido; sem isso, o CHECK quebraria o "rejeitar" deles).
-- É a última de propósito (seção 4: 100000 … 100800 → 100900).
-- Gerada por script (scripts/gerar_f5_dado.cjs): os itens 0 a 5 vêm de scripts/f5_sql/p9_dado.sql, escritos à mão; no item 5,
-- _agrupar_orcamentos_reabrindo e _desagrupar_orcamentos_desfazer são gerados do corpo vigente (o do banco, achado pelo md5 do
-- prosrc), e só os trechos marcados -- F5 (P9) são novos.
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
-- 5. O desagrupar com o CHECK (revisão das ondas 4 a 9, achado banco-1): o agrupar que reabre um reprovado (rejected → draft)
--    passa pelo gatilho da P2, que apaga o motivo; o desagrupar devolvia 'rejected' sem motivo, e o CHECK do item 2 recusaria
--    o desagrupar inteiro (23514). orcamento_agrupamento_origens ganha motivo_perda_antes (jsonb), _agrupar_orcamentos_reabrindo
--    guarda ali o motivo, a hora, quem e a nota antes de reabrir, e _desagrupar_orcamentos_desfazer os devolve junto com o
--    Reprovado; sem o motivo guardado (reaberto antes desta migration), como os antigos do item 1: 'sem_motivo_antigo', por
--    'migracao'. Os grants das duas ficam os de antes (create or replace não mexe neles).
--
-- Idempotente: rodada de novo, a trava encontra 0, o update do item 1 não acha linha, o CHECK já existe (validar de novo não
-- falha), o item 3 só troca o 3, o item 4 só olha quem ainda não tem orcamento_enviado_em (e o insert tem on conflict) e o item
-- 5 só cria a coluna se ela ainda não existe e usa create or replace.
-- Nenhuma mensagem é lida: do eco sai só o número do documento no nome do arquivo, nunca o nome nem o corpo.
-- Reverter, sempre com where: alter table public.service_orders drop constraint service_orders_rejeitado_tem_motivo;
-- update public.service_orders set motivo_perda = null, motivo_perda_por = null where motivo_perda = 'sem_motivo_antigo';
-- update public.app_settings set value = '3' where key = 'quote_validity_days';
-- update public.service_orders set orcamento_enviado_em = null, orcamento_enviado_via = null, orcamento_enviado_chave = null
--  where orcamento_enviado_via = 'historico';
-- delete from public.orcamento_envios where via = 'historico';
-- O item 5: reaplicar _agrupar_orcamentos_reabrindo de 20261015181000_agrupar_orcamentos_assistente.sql e
-- _desagrupar_orcamentos_desfazer de 20261015180000_agrupar_orcamentos.sql (sem o CHECK, o motivo volta a ser opcional); a
-- coluna motivo_perda_antes pode ficar.

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

-- 5. O desagrupar com o CHECK (achado banco-1). O motivo do reprovado que o agrupar reabre fica guardado na origem do
--    agrupamento e volta com o Reprovado no desagrupar; sem ele, 'sem_motivo_antigo' por 'migracao', como os antigos.
do $$
begin
  if not exists (select 1 from pg_attribute
                  where attrelid = 'public.orcamento_agrupamento_origens'::regclass and attname = 'motivo_perda_antes'
                    and not attisdropped) then
    alter table public.orcamento_agrupamento_origens add column motivo_perda_antes jsonb;
  end if;
end $$;

comment on column public.orcamento_agrupamento_origens.motivo_perda_antes is
  'Retorno F5 (P9): o motivo do reprovado que o agrupar reabriu (motivo_perda, motivo_perda_por, motivo_perda_em e motivo_perda_nota, como estavam antes do reabrir). O desagrupar o devolve junto com o Reprovado. Nulo nas outras origens e nas reabertas antes da F5.';

create or replace function public._agrupar_orcamentos_reabrindo(
  p_ids uuid[],
  p_reabrir uuid[],
  p_base uuid,
  p_numero text,
  p_autor uuid,
  p_total_esperado numeric
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_reabrir uuid[];
  v_travados uuid[];
  v_numeros text[];
  v_quem text;
  v_r jsonb;
  r record;
  v_f5_motivos jsonb;   -- F5 (P9)
begin
  if p_autor is null then
    raise exception 'Faça login para agrupar orçamentos.' using errcode = '42501';
  end if;
  if not public.is_admin_or_financial(p_autor) then
    raise exception 'Só administrador ou financeiro pode agrupar orçamentos.' using errcode = '42501';
  end if;

  v_reabrir := array(select distinct x from unnest(coalesce(p_reabrir, '{}'::uuid[])) x where x is not null);
  if cardinality(v_reabrir) = 0 then
    return public._agrupar_orcamentos_montar(p_ids, p_base, p_numero, p_autor, p_total_esperado);
  end if;
  if p_ids is null or not (v_reabrir <@ p_ids) then
    raise exception 'O orçamento que volta para Em elaboração precisa estar entre os escolhidos.' using errcode = '22023';
  end if;

  -- Trava os escolhidos na mesma ordem do agrupar (por id) antes de mexer: dois pedidos simultâneos não se travam
  select array_agg(t.id) into v_travados
    from (select so.id from public.service_orders so where so.id = any(p_ids) order by so.id for update) t;

  for r in select so.service_order_number, so.status, so.quote_status, so.converted_to_os_at, so.merged_into_id
             from public.service_orders so where so.id = any(v_reabrir) order by so.created_at, so.id loop
    if r.quote_status is distinct from 'rejected' or r.status <> 'draft'
       or r.converted_to_os_at is not null or r.merged_into_id is not null then
      raise exception '% não está mais como Reprovado em aberto. Nada foi agrupado: peça de novo.', r.service_order_number
        using errcode = '22023';
    end if;
  end loop;
  if (select count(*) from public.service_orders so where so.id = any(v_reabrir)) <> cardinality(v_reabrir) then
    raise exception 'Algum orçamento escolhido não existe mais. Nada foi agrupado.' using errcode = 'P0002';
  end if;

  select u.full_name into v_quem from public.app_users u where u.id = p_autor;
  select array_agg(so.service_order_number order by so.created_at, so.id) into v_numeros
    from public.service_orders so where so.id = any(v_reabrir);

  -- Auditoria como a tela grava a mudança de situação (action 'update', new_value com a situação nova)
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  select 'service_orders', so.id, 'update', coalesce(v_quem, 'sistema'),
         jsonb_build_object('quote_status', 'rejected'), jsonb_build_object('quote_status', 'draft'),
         'Saiu de Reprovado para Em elaboração para entrar no agrupamento (o dono disse que ele entra)'
    from public.service_orders so where so.id = any(v_reabrir);

  -- F5 (P9): o motivo do perdido, guardado antes de o gatilho da P2 apagá-lo (sair de rejected apaga os 4 campos); o
  -- desagrupar o devolve junto com o Reprovado (o CHECK service_orders_rejeitado_tem_motivo exige o motivo).
  select jsonb_object_agg(so.id::text, jsonb_build_object('motivo_perda', so.motivo_perda, 'motivo_perda_por', so.motivo_perda_por,
                                                          'motivo_perda_em', so.motivo_perda_em, 'motivo_perda_nota', so.motivo_perda_nota))
    into v_f5_motivos
    from public.service_orders so
   where so.id = any(v_reabrir) and so.motivo_perda is not null;

  update public.service_orders so set quote_status = 'draft' where so.id = any(v_reabrir);

  -- Recusa daqui desfaz o de cima: é a mesma transação
  v_r := public._agrupar_orcamentos_montar(p_ids, p_base, p_numero, p_autor, p_total_esperado);

  -- Desagrupar devolve como estava ANTES do pedido: Reprovado
  update public.orcamento_agrupamento_origens x
     set quote_status_antes = 'rejected', motivo_perda_antes = v_f5_motivos -> x.origem_id::text   -- F5 (P9)
   where x.agrupamento_id = (v_r ->> 'agrupamento_id')::uuid
     and x.origem_id = any(v_reabrir);

  return v_r || jsonb_build_object('reabertos', to_jsonb(v_numeros));
end $$;

create or replace function public._desagrupar_orcamentos_desfazer(p_agrupado uuid, p_autor uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ag public.service_orders;
  v_grupo public.orcamento_agrupamentos;
  v_destino text;
  v_bloqueios text;
  v_quem text;
  v_numeros text[];
  v_ids uuid[];
  v_qtd integer;
  v_motivo text;
  n_envios integer := 0;
  n_reativados integer := 0;
  o record;
begin
  if p_autor is null then
    raise exception 'Faça login para desagrupar orçamentos.' using errcode = '42501';
  end if;
  if not public.is_admin_or_financial(p_autor) then
    raise exception 'Só administrador ou financeiro pode desagrupar orçamentos.' using errcode = '42501';
  end if;
  if p_agrupado is null then
    raise exception 'Escolha o orçamento agrupado.' using errcode = '22023';
  end if;

  select so.* into v_ag from public.service_orders so where so.id = p_agrupado for update;
  if v_ag.id is null then
    raise exception 'Orçamento não encontrado. Recarregue a tela.' using errcode = 'P0002';
  end if;

  select g.* into v_grupo from public.orcamento_agrupamentos g
   where g.agrupado_id = p_agrupado and g.desfeito_em is null
   for update;
  if v_grupo.id is null then
    raise exception '% não é um orçamento agrupado (ou já foi desagrupado).', v_ag.service_order_number
      using errcode = '22023';
  end if;

  -- O agrupado precisa ainda ser um orçamento em aberto, sem nada preso a ele
  if v_ag.merged_into_id is not null then
    select d.service_order_number into v_destino from public.service_orders d where d.id = v_ag.merged_into_id;
    raise exception '% foi agrupado de novo em %. Desagrupe % primeiro.',
      v_ag.service_order_number, coalesce(v_destino, 'outro orçamento'), coalesce(v_destino, 'esse')
      using errcode = '22023';
  end if;
  if v_ag.status <> 'draft' or v_ag.converted_to_os_at is not null then
    raise exception '% não é mais um orçamento em aberto (já virou OS ou foi cancelado): não dá mais para desagrupar.',
      v_ag.service_order_number using errcode = '22023';
  end if;
  if v_ag.signed_at is not null
     or exists (select 1 from public.service_order_signatures g where g.service_order_id = v_ag.id) then
    raise exception '% já foi assinado pelo cliente: não dá para desagrupar.', v_ag.service_order_number
      using errcode = '22023';
  end if;
  v_bloqueios := public._orcamento_vinculos_que_prendem(v_ag.id);
  if v_bloqueios <> '' then
    raise exception '% está ligado a: %. Resolva isso antes de desagrupar.', v_ag.service_order_number, v_bloqueios
      using errcode = '22023';
  end if;

  -- Trava as origens (mesma ordem do agrupar) e confere que seguem presas a este agrupado
  select array_agg(t.id) into v_ids
    from (select so.id from public.service_orders so
            join public.orcamento_agrupamento_origens x on x.origem_id = so.id and x.agrupamento_id = v_grupo.id
           order by so.id for update of so) t;
  select count(*) into v_qtd from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id;
  if coalesce(cardinality(v_ids), 0) <> v_qtd or v_qtd = 0 then
    raise exception 'Algum orçamento original deste agrupamento não existe mais. Nada foi desfeito.' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.service_orders so where so.id = any(v_ids)
              and (so.merged_into_id is distinct from v_ag.id or so.status <> 'cancelled')) then
    raise exception 'Os originais de % não estão mais como o agrupamento deixou. Nada foi desfeito.',
      v_ag.service_order_number using errcode = '22023';
  end if;

  select array_agg(x.numero order by x.ordem) into v_numeros
    from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id;
  select u.full_name into v_quem from public.app_users u where u.id = p_autor;
  v_motivo := 'Desagrupado em ' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')
           || ' por ' || coalesce(v_quem, 'sistema') || ': voltou a ser ' || array_to_string(v_numeros, ', ');

  -- Auditoria antes de mexer (guarda o "antes")
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason,
                                triggered_by_table, triggered_by_id)
  select 'service_orders', x.origem_id, 'reopen', coalesce(v_quem, 'sistema'),
         jsonb_build_object('status', 'cancelled', 'merged_into_id', v_ag.id, 'merged_into_number', v_ag.service_order_number),
         jsonb_build_object('status', 'draft', 'quote_status', x.quote_status_antes, 'link_publico', 'religado'),
         'Desagrupado de ' || v_ag.service_order_number, 'service_orders', v_ag.id
    from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id;
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('service_orders', v_ag.id, 'cancel', coalesce(v_quem, 'sistema'),
          jsonb_build_object('status', v_ag.status, 'quote_status', v_ag.quote_status, 'grand_total', v_ag.grand_total),
          jsonb_build_object('status', 'cancelled', 'desagrupado', to_jsonb(v_numeros), 'link_publico', 'desligado'),
          v_motivo);

  -- Origens: voltam como estavam (situação, link, cancelamento)
  perform set_config('marineflow.agrupar_orcamentos', 'on', true);
  for o in select x.* from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id order by x.ordem loop
    update public.service_orders so
       set status = 'draft',
           quote_status = o.quote_status_antes,
           -- F5 (P9): o Reprovado volta com o motivo de antes do reabrir (motivo_perda_antes, que _agrupar_orcamentos_reabrindo
           -- guarda); sem ele (reaberto antes da P9), como os antigos: 'sem_motivo_antigo', por 'migracao'. O CHECK
           -- service_orders_rejeitado_tem_motivo exige o motivo, e o gatilho da P2 só carimba a hora que vier nula.
           motivo_perda = (case when o.quote_status_antes = 'rejected' and so.motivo_perda is null
                                then coalesce(o.motivo_perda_antes ->> 'motivo_perda', 'sem_motivo_antigo')
                                else so.motivo_perda end),
           motivo_perda_por = (case when o.quote_status_antes = 'rejected' and so.motivo_perda is null
                                    then (case when o.motivo_perda_antes ->> 'motivo_perda' is null then 'migracao'
                                               else o.motivo_perda_antes ->> 'motivo_perda_por' end)
                                    else so.motivo_perda_por end),
           motivo_perda_em = (case when o.quote_status_antes = 'rejected' and so.motivo_perda is null
                                   then (o.motivo_perda_antes ->> 'motivo_perda_em')::timestamptz
                                   else so.motivo_perda_em end),
           motivo_perda_nota = (case when o.quote_status_antes = 'rejected' and so.motivo_perda is null
                                     then o.motivo_perda_antes ->> 'motivo_perda_nota'
                                     else so.motivo_perda_nota end),
           cancelled_at = o.cancelled_at_antes,
           cancellation_reason = o.cancellation_reason_antes,
           share_token = coalesce(o.share_token_antes, gen_random_uuid()),
           merged_into_id = null
     where so.id = o.origem_id;
  end loop;
  -- Agrupado: cancelado como histórico, link desligado (a guarda do agrupado deixa passar só aqui)
  update public.service_orders so
     set status = 'cancelled',
         cancelled_at = now(),
         cancellation_reason = v_motivo,
         share_token = null
   where so.id = v_ag.id;
  perform set_config('marineflow.agrupar_orcamentos', '', true);

  -- Totais das origens pelo banco (alguém pode ter mexido numa linha enquanto estavam canceladas)
  for o in select x.origem_id from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id loop
    perform public.recalc_so_totals(o.origem_id);
  end loop;

  -- Envios agendados das origens que o agrupar cancelou voltam (o link deles voltou), se a hora ainda não
  -- passou. O número do agrupado não muda enquanto o desagrupar é possível: o texto casa exatamente.
  update public.whatsapp_scheduled_sends w
     set status = 'pending', last_error = null, updated_at = now()
   where w.service_order_id = any(v_ids) and w.status = 'cancelled'
     and w.last_error = 'Cancelado: orçamento agrupado em ' || v_ag.service_order_number
     and w.next_run_at > now();
  get diagnostics n_reativados = row_count;

  update public.whatsapp_scheduled_sends w
     set status = 'cancelled', last_error = 'Cancelado: orçamento desagrupado', updated_at = now()
   where w.service_order_id = v_ag.id and w.status in ('pending', 'processing');
  get diagnostics n_envios = row_count;

  update public.orcamento_agrupamentos g
     set desfeito_em = now(), desfeito_por = p_autor
   where g.id = v_grupo.id;

  return jsonb_build_object(
    'agrupado_id', v_ag.id, 'agrupado', v_ag.service_order_number,
    'origens', to_jsonb(v_numeros), 'origens_ids', (select to_jsonb(array_agg(x.origem_id order by x.ordem))
                                                      from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id),
    'envios_cancelados', n_envios, 'envios_reativados', n_reativados);
end $$;

-- Retorno F5 (P9): a migration com dado (20270112100900_retorno_f5_dado.sql). Depois do arquivo, nenhum rejeitado sem motivo
-- e os antigos como 'sem_motivo_antigo' (o número contado antes, c_esperado); o CHECK service_orders_rejeitado_tem_motivo
-- (23514 com o nome dele) e o gatilho da P2 apagando o motivo ao reabrir; o padrão 3 → 7 só quando era 3; o histórico com
-- prova (o whatsapp_send_api que deu certo e o eco do aparelho, o 1º ao número do cliente, uma linha 'historico' por ordem,
-- nenhuma do gatilho, nenhum acompanhamento, e o candidato do aceite pela chave), sem a falha, o modo de teste, a recusa, o
-- outro número e o número de parceiro; rodada duas vezes, o mesmo resultado; a trava "N ou 0"; e (nº 8, revisão das ondas 4 a
-- 9, achado banco-1) o desagrupar do reprovado reaberto com o CHECK no banco, com o motivo guardado e sem ele. Roda só pela
-- bancada (grupo 8, F5_ONDA=8, F5_TESTES=retorno_f5_dado), de madrugada (o CHECK é DDL em service_orders). GERADO por
-- scripts/gerar_f5_dado_teste.cjs do molde scripts/f5_sql/p9_teste_dado.sql: pg_temp.f5g_migracao() leva os comandos da
-- migration, cópia fiel, e c_esperado vem dela; nunca edite este arquivo à mão.
-- Este teste conta linhas reais de propósito (P9.2 nº 1 e 7): a migration mexe nos rejeitados reais, dentro da transação
-- desfeita, e a trava compara com a contagem real do dia. Se o número de rejeitados sem motivo mudou desde a construção, o 1º
-- passo (a migration na bancada) já fica vermelho: é o aviso de trocar c_esperado (na migration, e gerar este teste de novo).
-- As linhas sintéticas: telefones inventados 55479000099xx (a chave sai do telefone: 000099xx), nomes inventados (Ana, João,
-- Pedro), documentos inventados (ORÇ-998xx). Nenhuma mensagem real é lida. Relógio: seg 05/10/2026 10:00 (Brasília).
-- Termina em ROLLBACK; cada cenário roda no seu sub-bloco, que se desfaz sozinho (raise 'f5g_cenario').
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());
create temp table if not exists _f5g_contagens (rodada text, c jsonb);

create or replace function pg_temp.f5g_cli(p_nome text, p_fone text) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, p_fone) returning id
$f$;

-- O orçamento como estava antes da F5: no funil (sent, por padrão), sem orcamento_enviado_em (o insert não passa pelo gatilho).
create or replace function pg_temp.f5g_orc(p_cliente uuid, p_numero text, p_em timestamptz, p_quote text default 'sent') returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type)
    values (p_cliente, 'Unidade ' || left(md5(p_cliente::text || p_numero || clock_timestamp()::text), 6), 'Motorhome') returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total, quote_validity_days)
  values (p_numero, p_cliente, v_v, 'draft', p_quote, 'repair', p_em - interval '2 days', p_em - interval '2 days', 100, 7)
  returning id into v_id;
  return v_id;
end $f$;

-- A linha do whatsapp-send em audit_log (o molde de whatsapp-send/index.ts:321-343): o envio de orçamento a p_fone.
create or replace function pg_temp.f5g_audit(p_os uuid, p_fone text, p_em timestamptz, p_novo jsonb, p_reason text default null)
returns void
language sql as $f$
  insert into public.audit_log (table_name, record_id, action, changed_by, changed_at, previous_value, new_value, reason)
  values ('service_orders', p_os, 'whatsapp_send_api', 'teste F5 (P9)', p_em, null,
          jsonb_build_object('context', 'quote', 'phone', p_fone) || p_novo, p_reason)
$f$;

-- O PDF que saiu do aparelho do dono (eco: data, sem via).
create or replace function pg_temp.f5g_eco(p_fone text, p_arquivo text, p_em timestamptz) returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, raw_payload, occurred_at, hora_real)
  values ('outbound', p_fone, 'document', null, 'teste-f5-dado-' || md5(p_fone || p_arquivo || p_em::text),
          jsonb_build_object('data', jsonb_build_object('source', 'unknown', 'message',
                                                        jsonb_build_object('documentMessage', jsonb_build_object('fileName', p_arquivo)))),
          p_em, p_em)
  returning id
$f$;

-- O orçamento do agrupar (nº 8): no barco dado, com 1 serviço (2 h × R$ 150) e os totais pelo banco, como o _orc do teste do
-- agrupar. O reprovado nasce com o motivo (o CHECK já está no banco): preço, pela tela, com a hora e a nota.
create or replace function pg_temp.f5g_orc_barco(p_cliente uuid, p_barco uuid, p_numero text, p_em timestamptz, p_quote text)
returns uuid
language plpgsql as $f$
declare
  v_id uuid;
begin
  if p_quote = 'rejected' then
    insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, created_at, motivo_perda,
                                       motivo_perda_por, motivo_perda_em, motivo_perda_nota)
    values (p_numero, p_cliente, p_barco, 'draft', 'rejected', p_em - interval '5 days', 'preco', 'tela', p_em - interval '3 days',
            'caro')
    returning id into v_id;
  else
    insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, created_at)
    values (p_numero, p_cliente, p_barco, 'draft', p_quote, p_em - interval '5 days')
    returning id into v_id;
  end if;
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot,
                                             line_total, discount_pct, discount_amount, created_at, updated_at)
  values (v_id, 'Serviço de teste F5', 'hour', 2, 150, 300, 0, 0, p_em - interval '5 days', p_em - interval '5 days');
  perform public.recalc_so_totals(v_id);
  return v_id;
end $f$;

-- A migration 20270112100900_retorno_f5_dado.sql, comando por comando (gerado: cópia fiel).
create or replace function pg_temp.f5g_migracao() returns void
language plpgsql as $f$
begin
  execute $f5g1$do $$
declare
  c_esperado constant integer := 46;
  v_n integer;
begin
  select count(*) into v_n from public.service_orders where quote_status = 'rejected' and motivo_perda is null;
  if v_n <> c_esperado and v_n <> 0 then
    raise exception 'F5 (dado): % orçamento(s) rejeitado(s) sem motivo, e a migration espera % (ou 0, se já rodou). Nada foi gravado: reconte e troque c_esperado.',
      v_n, c_esperado using errcode = 'P0001';
  end if;
end $$$f5g1$;
  execute $f5g2$with feitos as (
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
  from feitos f$f5g2$;
  execute $f5g3$do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'service_orders_rejeitado_tem_motivo'
                    and conrelid = 'public.service_orders'::regclass) then
    alter table public.service_orders add constraint service_orders_rejeitado_tem_motivo
      check (quote_status is distinct from 'rejected' or motivo_perda is not null) not valid;
  end if;
end $$$f5g3$;
  execute $f5g4$alter table public.service_orders validate constraint service_orders_rejeitado_tem_motivo$f5g4$;
  execute $f5g5$update public.app_settings set value = '7', updated_at = now() where key = 'quote_validity_days' and value = '3'$f5g5$;
  execute $f5g6$with abertos as (
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
on conflict do nothing$f5g6$;
  execute $f5g7$do $$
begin
  if not exists (select 1 from pg_attribute
                  where attrelid = 'public.orcamento_agrupamento_origens'::regclass and attname = 'motivo_perda_antes'
                    and not attisdropped) then
    alter table public.orcamento_agrupamento_origens add column motivo_perda_antes jsonb;
  end if;
end $$$f5g7$;
  execute $f5g8$comment on column public.orcamento_agrupamento_origens.motivo_perda_antes is
  'Retorno F5 (P9): o motivo do reprovado que o agrupar reabriu (motivo_perda, motivo_perda_por, motivo_perda_em e motivo_perda_nota, como estavam antes do reabrir). O desagrupar o devolve junto com o Reprovado. Nulo nas outras origens e nas reabertas antes da F5.'$f5g8$;
  execute $f5g9$create or replace function public._agrupar_orcamentos_reabrindo(
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
end $$$f5g9$;
  execute $f5g10$create or replace function public._desagrupar_orcamentos_desfazer(p_agrupado uuid, p_autor uuid)
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
end $$$f5g10$;
end $f$;

-- As contagens que a migration mexe (as reais, de propósito: P9.2 nº 1 e 6).
create or replace function pg_temp.f5g_contagem() returns jsonb
language sql as $f$
  select jsonb_build_object(
    'sem_motivo', (select count(*) from public.service_orders so where so.quote_status = 'rejected' and so.motivo_perda is null),
    'antigos', (select count(*) from public.service_orders so where so.motivo_perda = 'sem_motivo_antigo'),
    'audit', (select count(*) from public.audit_log a
               where a.changed_by = 'migration 20270112100900' and a.reason = 'F5: rejeitado antigo sem motivo'),
    'envios_historico', (select count(*) from public.orcamento_envios e where e.via = 'historico'),
    'envios', (select count(*) from public.orcamento_envios e),
    'ordens_historico', (select count(*) from public.service_orders so where so.orcamento_enviado_via = 'historico'),
    'validade', (select s.value from public.app_settings s where s.key = 'quote_validity_days'),
    'check', (select count(*) from pg_constraint c
               where c.conname = 'service_orders_rejeitado_tem_motivo' and c.conrelid = 'public.service_orders'::regclass
                 and c.convalidated))
$f$;

-- ── 6 (a 2ª rodada): a migration já rodou na bancada; roda de novo aqui, sem 42710, sem 23505 e com a trava aceitando 0 ──
insert into _f5g_contagens (rodada, c) select 'antes', pg_temp.f5g_contagem();
select pg_temp.f5g_migracao();
insert into _f5g_contagens (rodada, c) select 'depois', pg_temp.f5g_contagem();

do $dado$
declare
  c_esperado constant integer := 46;   -- o mesmo da migration (bloco 0): o gerador o copia de lá
  c_t constant timestamptz := '2026-10-05 10:00-03';
  c_admin constant uuid := 'b1600000-0000-4000-8000-0000000099e9';   -- o admin de teste do agrupar (nº 8)
  v_antes jsonb;
  v_depois jsonb;
  v_c jsonb;
  v_ana uuid; v_joao uuid; v_pedro uuid; v_x uuid; v_p uuid; v_pessoa uuid;
  v_oa uuid; v_ob uuid; v_oc uuid; v_od uuid; v_oe uuid; v_of uuid; v_og uuid; v_oh uuid; v_oi uuid; v_oj uuid; v_ok uuid;
  v_eco_b uuid; v_eco_h uuid;
  v_so record;
  v_e record;
  v_r jsonb;
  v_con text;
  v_n integer;
  v_antigos integer;
  v_parou boolean;
  v_msg text;
begin
  begin
  select c into v_antes from _f5g_contagens where rodada = 'antes';
  select c into v_depois from _f5g_contagens where rodada = 'depois';

  -- ── 1. Depois do arquivo: 0 rejeitado sem motivo; os antigos são o número contado antes ──
  if (v_depois ->> 'sem_motivo')::integer is distinct from 0 then
    raise exception '1a: % rejeitado(s) sem motivo depois da migration', v_depois ->> 'sem_motivo';
  end if;
  if (v_depois ->> 'antigos')::integer is distinct from c_esperado then
    raise exception '1b: % sem_motivo_antigo, esperava % (c_esperado)', v_depois ->> 'antigos', c_esperado;
  end if;
  if (v_depois ->> 'audit')::integer is distinct from c_esperado then
    raise exception '1c: % linha(s) de audit_log da migration, esperava % (uma por ordem atualizada)', v_depois ->> 'audit', c_esperado;
  end if;
  if (v_depois ->> 'check')::integer is distinct from 1 then
    raise exception '1d: o CHECK service_orders_rejeitado_tem_motivo não está validado';
  end if;

  -- ── 6. Rodada duas vezes: o resultado é o mesmo (nenhuma linha nova em audit_log nem em orcamento_envios) ──
  if v_depois is distinct from v_antes then
    raise exception '6a: a 2ª rodada mudou as contagens (antes %, depois %)', v_antes, v_depois;
  end if;

  -- ── 2. O CHECK: rejeitado sem motivo → 23514 com o nome; com motivo, passa ──
  -- ── 3. Reabrir (rejected → draft): o gatilho da P2 apaga o motivo, e o CHECK continua satisfeito ──
  begin
    v_ana := pg_temp.f5g_cli('Ana Dado F5 Teste', '5547900009960');
    v_oa := pg_temp.f5g_orc(v_ana, 'ORÇ-99801', c_t);
    v_con := null;
    begin
      update public.service_orders set quote_status = 'rejected' where id = v_oa;
      raise exception '2a: rejeitado sem motivo passou';
    exception when check_violation then
      get stacked diagnostics v_con = constraint_name;
    end;
    if v_con is distinct from 'service_orders_rejeitado_tem_motivo' then
      raise exception '2b: o 23514 veio de outra constraint (%)', v_con;
    end if;
    update public.service_orders set quote_status = 'rejected', motivo_perda = 'preco', motivo_perda_por = 'tela' where id = v_oa;
    select so.quote_status, so.motivo_perda, so.motivo_perda_em into v_so from public.service_orders so where so.id = v_oa;
    if v_so.quote_status is distinct from 'rejected' or v_so.motivo_perda is distinct from 'preco' or v_so.motivo_perda_em is null then
      raise exception '2c: rejeitado com motivo (%)', row_to_json(v_so);
    end if;
    update public.service_orders set quote_status = 'draft' where id = v_oa;
    select so.quote_status, so.motivo_perda, so.motivo_perda_em, so.motivo_perda_por into v_so
      from public.service_orders so where so.id = v_oa;
    if v_so.quote_status is distinct from 'draft' or v_so.motivo_perda is not null or v_so.motivo_perda_em is not null
       or v_so.motivo_perda_por is not null then
      raise exception '3a: reabrir não apagou o motivo (%)', row_to_json(v_so);
    end if;
    raise exception 'f5g_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5g_cenario' then
      raise;
    end if;
  end;

  -- ── 4. O padrão 3 → 7; com outro valor (o dono mudou), nada muda ──
  if v_depois ->> 'validade' is distinct from '7' then
    raise exception '4a: app_settings.quote_validity_days = % depois da migration (era 3 antes dela?)', v_depois ->> 'validade';
  end if;
  begin
    update public.app_settings set value = '5' where key = 'quote_validity_days';
    perform pg_temp.f5g_migracao();
    if (select s.value from public.app_settings s where s.key = 'quote_validity_days') is distinct from '5' then
      raise exception '4b: a migration trocou um valor que não era 3';
    end if;
    update public.app_settings set value = '3' where key = 'quote_validity_days';
    perform pg_temp.f5g_migracao();
    if (select s.value from public.app_settings s where s.key = 'quote_validity_days') is distinct from '7' then
      raise exception '4c: a migration não trocou o 3 pelo 7';
    end if;
    raise exception 'f5g_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5g_cenario' then
      raise;
    end if;
  end;

  -- ── 5. O histórico com prova ──
  begin
    v_ana := pg_temp.f5g_cli('Ana Histórico F5 Teste', '5547900009960');
    v_joao := pg_temp.f5g_cli('João Histórico F5 Teste', '5547900009961');
    v_pedro := pg_temp.f5g_cli('Pedro Histórico F5 Teste', '5547900009962');
    -- A: o envio pelo sistema que deu certo, ao número do cliente
    v_oa := pg_temp.f5g_orc(v_ana, 'ORÇ-99811', c_t);
    perform pg_temp.f5g_audit(v_oa, '5547900009960', c_t, '{"provider_result": {"ok": true}}');
    -- B: o eco do aparelho com ORÇ- no nome, ao número do cliente (a hora do eco)
    v_ob := pg_temp.f5g_orc(v_joao, 'ORÇ-99812', c_t);
    v_eco_b := pg_temp.f5g_eco('5547900009961', 'ORÇ-99812.pdf', c_t + interval '1 hour');
    -- C: o envio que falhou; D: o desviado pelo modo de teste; E: a recusa; F: a outro número
    v_oc := pg_temp.f5g_orc(v_pedro, 'ORÇ-99813', c_t);
    perform pg_temp.f5g_audit(v_oc, '5547900009962', c_t, '{"provider_result": {"ok": false}}');
    v_od := pg_temp.f5g_orc(v_ana, 'ORÇ-99814', c_t);
    perform pg_temp.f5g_audit(v_od, '5547900009960', c_t, '{"provider_result": {"ok": true}}',
                              '[TEST MODE ACTIVE] desviado para o número de teste');
    v_oe := pg_temp.f5g_orc(v_joao, 'ORÇ-99815', c_t);
    perform pg_temp.f5g_audit(v_oe, '5547900009961', c_t, '{"recusado": "numero_bloqueado", "provider_result": {"ok": true}}');
    v_of := pg_temp.f5g_orc(v_pedro, 'ORÇ-99816', c_t);
    perform pg_temp.f5g_audit(v_of, '5547900009977', c_t, '{"provider_result": {"ok": true}}');
    -- G: o eco a um número que é do cadastro do cliente e também número confirmado de parceiro
    insert into public.parceiros (nome, sigla, tipo) values ('Revenda Dado F5 Teste', 'RDFT', 'revenda') returning id into v_p;
    insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Carla', 'comercial') returning id into v_pessoa;
    insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_documento)
      values (v_pessoa, '5547900009966', '00009966', '47', 'confirmado', c_t - interval '30 days', true);
    v_x := pg_temp.f5g_cli('Pedro Revenda F5 Teste', '5547900009966');
    v_og := pg_temp.f5g_orc(v_x, 'ORÇ-99817', c_t);
    perform pg_temp.f5g_eco('5547900009966', 'ORÇ-99817.pdf', c_t);
    -- H: dois envios provados ao cliente (o eco às 10:00 e o sistema às 12:00): vale o 1º
    v_oh := pg_temp.f5g_orc(v_joao, 'ORÇ-99818', c_t);
    v_eco_h := pg_temp.f5g_eco('5547900009961', 'Orcamento-ORÇ-99818.pdf', c_t);
    perform pg_temp.f5g_audit(v_oh, '5547900009961', c_t + interval '2 hours', '{"provider_result": {"ok": true}}');
    -- I: o formato antigo (Z-API), com http_status 200
    v_oi := pg_temp.f5g_orc(v_pedro, 'ORÇ-99819', c_t, 'awaiting_approval');
    perform pg_temp.f5g_audit(v_oi, '5547900009962', c_t, '{"http_status": "200"}');
    -- J: o rascunho que não está no funil de enviado; K: o cliente parceiro
    v_oj := pg_temp.f5g_orc(v_ana, 'ORÇ-99820', c_t, 'draft');
    perform pg_temp.f5g_audit(v_oj, '5547900009960', c_t, '{"provider_result": {"ok": true}}');
    v_x := pg_temp.f5g_cli('João Cliente Parceiro F5 Teste', '5547900009967');
    update public.retorno_config set clientes_parceiros = clientes_parceiros || array[v_x] where id;
    v_ok := pg_temp.f5g_orc(v_x, 'ORÇ-99821', c_t);
    perform pg_temp.f5g_audit(v_ok, '5547900009967', c_t, '{"provider_result": {"ok": true}}');

    perform pg_temp.f5g_migracao();

    -- Com prova: A (sistema), B (eco), H (o 1º, o eco), I (formato antigo).
    for v_e in
      select x.os, x.em, x.chave, x.msg, x.cliente
        from (values (v_oa, c_t, '00009960', null::uuid, v_ana), (v_ob, c_t + interval '1 hour', '00009961', v_eco_b, v_joao),
                     (v_oh, c_t, '00009961', v_eco_h, v_joao), (v_oi, c_t, '00009962', null::uuid, v_pedro)) as x(os, em, chave, msg, cliente)
    loop
      select so.orcamento_enviado_em, so.orcamento_enviado_via, so.orcamento_enviado_chave, so.quote_status into v_so
        from public.service_orders so where so.id = v_e.os;
      if v_so.orcamento_enviado_em is distinct from v_e.em or v_so.orcamento_enviado_via is distinct from 'historico'
         or v_so.orcamento_enviado_chave is distinct from v_e.chave then
        raise exception '5a: a ordem % (%)', v_e.os, row_to_json(v_so);
      end if;
      if v_so.quote_status not in ('sent', 'awaiting_approval') then
        raise exception '5b: o histórico mexeu no funil de %', v_e.os;
      end if;
      select count(*) into v_n from public.orcamento_envios e where e.service_order_id = v_e.os;
      if v_n is distinct from 1 then
        raise exception '5c: % linha(s) em orcamento_envios da ordem % (esperava 1, nenhuma do gatilho)', v_n, v_e.os;
      end if;
      if not exists (select 1 from public.orcamento_envios e
                      where e.service_order_id = v_e.os and e.via = 'historico' and e.chave = v_e.chave and e.ao_cliente
                        and e.client_id = v_e.cliente and e.em = v_e.em and e.marcou = false
                        and e.whatsapp_message_id is not distinct from v_e.msg) then
        raise exception '5d: a linha historico da ordem % não é a esperada', v_e.os;
      end if;
    end loop;
    -- Sem prova: C (falhou), D (modo de teste), E (recusa), F (outro número), G (número de parceiro), J (rascunho), K (parceiro).
    if exists (select 1 from public.service_orders so
                where so.id in (v_oc, v_od, v_oe, v_of, v_og, v_oj, v_ok) and so.orcamento_enviado_em is not null)
       or exists (select 1 from public.orcamento_envios e where e.service_order_id in (v_oc, v_od, v_oe, v_of, v_og, v_oj, v_ok)) then
      raise exception '5e: ordem sem prova ganhou o histórico';
    end if;
    -- Nenhum acompanhamento nasce, nem com a cadência ligada (a via historico é inelegível).
    update public.retorno_config set validade_envio_ligada = true, orcamento_modo = 'ligado' where id;
    v_r := public.orcamento_vigia(c_t + interval '3 hours');
    if exists (select 1 from public.orcamento_acompanhamentos a
                where a.service_order_id in (v_oa, v_ob, v_oc, v_od, v_oe, v_of, v_og, v_oh, v_oi, v_oj, v_ok)) then
      raise exception '5f: o histórico abriu cadência (%)', v_r;
    end if;
    if public._orcamento_inelegivel(v_oa, c_t + interval '3 hours') is distinct from 'historico' then
      raise exception '5g: a via historico não é inelegível (%)', public._orcamento_inelegivel(v_oa, c_t + interval '3 hours');
    end if;
    -- O aceite acha o candidato pela chave.
    if not (v_oa = any (public._orcamento_candidatos(v_ana, '00009960', c_t + interval '1 day', c_t + interval '1 day'))) then
      raise exception '5h: o "pode fazer" da Ana não acha o ORÇ-99811 pela chave';
    end if;
    -- De novo: nada muda.
    select count(*) into v_n from public.orcamento_envios e where e.via = 'historico';
    perform pg_temp.f5g_migracao();
    if (select count(*) from public.orcamento_envios e where e.via = 'historico') is distinct from v_n::bigint then
      raise exception '5i: a 2ª rodada do histórico gravou outra linha';
    end if;
    raise exception 'f5g_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5g_cenario' then
      raise;
    end if;
  end;

  -- ── 7. A trava: 1 rejeitado sem motivo a mais do que c_esperado (e diferente de 0) → P0001, nada muda; com a contagem igual
  --       a c_esperado → passa ──
  begin
    alter table public.service_orders drop constraint service_orders_rejeitado_tem_motivo;
    v_pedro := pg_temp.f5g_cli('Pedro Trava F5 Teste', '5547900009968');
    v_oa := pg_temp.f5g_orc(v_pedro, 'ORÇ-99831', c_t);
    update public.service_orders set quote_status = 'rejected' where id = v_oa;
    select count(*) into v_antigos from public.service_orders so where so.motivo_perda = 'sem_motivo_antigo';
    v_parou := false;
    v_msg := null;
    begin
      perform pg_temp.f5g_migracao();
    exception when sqlstate 'P0001' then
      v_parou := true;
      v_msg := sqlerrm;
    end;
    if not v_parou then
      raise exception '7a: a trava não parou com 1 rejeitado sem motivo';
    end if;
    if v_msg is distinct from format('F5 (dado): %s orçamento(s) rejeitado(s) sem motivo, e a migration espera %s (ou 0, se já rodou). Nada foi gravado: reconte e troque c_esperado.',
                                     1, c_esperado) then
      raise exception '7b: a mensagem da trava (%)', v_msg;
    end if;
    if (select count(*) from public.service_orders so where so.motivo_perda = 'sem_motivo_antigo') is distinct from v_antigos::bigint
       or (select so.motivo_perda from public.service_orders so where so.id = v_oa) is not null
       or exists (select 1 from pg_constraint c where c.conname = 'service_orders_rejeitado_tem_motivo') then
      raise exception '7c: a trava parou, mas alguma linha mudou';
    end if;
    -- A contagem igual a c_esperado (os antigos voltam a estar sem motivo; o sintético ganha motivo): passa.
    update public.service_orders
       set motivo_perda = null, motivo_perda_por = null, motivo_perda_em = null
     where motivo_perda = 'sem_motivo_antigo' and motivo_perda_por = 'migracao';
    update public.service_orders set motivo_perda = 'outro', motivo_perda_por = 'tela' where id = v_oa;
    if (select count(*) from public.service_orders so where so.quote_status = 'rejected' and so.motivo_perda is null)
       is distinct from c_esperado::bigint then
      raise exception '7d: a contagem de antes da migration não é c_esperado (% rejeitados sem motivo): troque c_esperado',
        (select count(*) from public.service_orders so where so.quote_status = 'rejected' and so.motivo_perda is null);
    end if;
    perform pg_temp.f5g_migracao();
    if (select count(*) from public.service_orders so where so.quote_status = 'rejected' and so.motivo_perda is null) is distinct from 0::bigint
       or (select count(*) from public.service_orders so where so.motivo_perda = 'sem_motivo_antigo') is distinct from c_esperado::bigint
       or not exists (select 1 from pg_constraint c where c.conname = 'service_orders_rejeitado_tem_motivo' and c.convalidated) then
      raise exception '7e: com a contagem igual a c_esperado, a migration não fez o que devia';
    end if;
    raise exception 'f5g_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5g_cenario' then
      raise;
    end if;
  end;

  -- ── 8. O desagrupar do reprovado reaberto, com o CHECK no banco (revisão das ondas 4 a 9, achado banco-1). O agrupar que
  --       reabre o reprovado guarda o motivo (o gatilho da P2 o apaga no reabrir), e o desagrupar devolve o Reprovado com ele;
  --       sem o motivo guardado (reaberto antes da P9), 'sem_motivo_antigo' por 'migracao'. Antes do conserto, o desagrupar
  --       devolvia 'rejected' sem motivo e parava inteiro em 23514 (service_orders_rejeitado_tem_motivo). ──
  begin
    insert into public.app_users (id, full_name, email, role, active)
    values (c_admin, 'TESTE F5 dado admin', 'teste-f5-dado-admin@teste.invalid', 'admin', true);
    v_ana := pg_temp.f5g_cli('Ana Agrupar F5 Teste', '5547900009969');
    insert into public.vessels (client_id, name, asset_type) values (v_ana, 'Unidade agrupar F5 Teste', 'Motorhome') returning id into v_x;
    -- 8a. Com o motivo guardado: o ORÇ-99841 perdido (preço, pela tela, com a nota) entra reaberto com o ORÇ-99842.
    v_oa := pg_temp.f5g_orc_barco(v_ana, v_x, 'ORÇ-99841', c_t, 'rejected');
    v_ob := pg_temp.f5g_orc_barco(v_ana, v_x, 'ORÇ-99842', c_t, 'draft');
    v_r := public._agrupar_orcamentos_reabrindo(array[v_oa, v_ob], array[v_oa], null, 'ORÇ-T99840', c_admin, null);
    select so.status, so.quote_status, so.motivo_perda, so.motivo_perda_por into v_so from public.service_orders so where so.id = v_oa;
    if v_so.status is distinct from 'cancelled' or v_so.quote_status is distinct from 'draft' or v_so.motivo_perda is not null
       or v_so.motivo_perda_por is not null then
      raise exception '8a: o reaberto não entrou no agrupamento sem o motivo (%)', row_to_json(v_so);
    end if;
    select x.motivo_perda_antes as m into v_e from public.orcamento_agrupamento_origens x
     where x.agrupamento_id = (v_r ->> 'agrupamento_id')::uuid and x.origem_id = v_oa;
    if v_e.m ->> 'motivo_perda' is distinct from 'preco' or v_e.m ->> 'motivo_perda_por' is distinct from 'tela'
       or (v_e.m ->> 'motivo_perda_em')::timestamptz is distinct from c_t - interval '3 days'
       or v_e.m ->> 'motivo_perda_nota' is distinct from 'caro' then
      raise exception '8b: o motivo guardado na origem (%)', v_e.m;
    end if;
    if (select x.motivo_perda_antes from public.orcamento_agrupamento_origens x
         where x.agrupamento_id = (v_r ->> 'agrupamento_id')::uuid and x.origem_id = v_ob) is not null then
      raise exception '8c: a origem que não era reprovada guardou motivo';
    end if;
    perform public._desagrupar_orcamentos_desfazer((v_r ->> 'service_order_id')::uuid, c_admin);
    select so.status, so.quote_status, so.motivo_perda, so.motivo_perda_por, so.motivo_perda_em, so.motivo_perda_nota, so.merged_into_id
      into v_so from public.service_orders so where so.id = v_oa;
    if v_so.status is distinct from 'draft' or v_so.quote_status is distinct from 'rejected' or v_so.merged_into_id is not null
       or v_so.motivo_perda is distinct from 'preco' or v_so.motivo_perda_por is distinct from 'tela'
       or v_so.motivo_perda_em is distinct from c_t - interval '3 days' or v_so.motivo_perda_nota is distinct from 'caro' then
      raise exception '8d: o desagrupar não devolveu o Reprovado com o motivo de antes (%)', row_to_json(v_so);
    end if;
    select so.status, so.quote_status, so.motivo_perda into v_so from public.service_orders so where so.id = v_ob;
    if v_so.status is distinct from 'draft' or v_so.quote_status is distinct from 'draft' or v_so.motivo_perda is not null then
      raise exception '8e: o outro não voltou como Em elaboração, sem motivo (%)', row_to_json(v_so);
    end if;
    -- 8f. Sem o motivo guardado (o agrupamento reaberto antes desta migration): o Reprovado volta como os antigos.
    v_oc := pg_temp.f5g_orc_barco(v_ana, v_x, 'ORÇ-99843', c_t, 'rejected');
    v_od := pg_temp.f5g_orc_barco(v_ana, v_x, 'ORÇ-99844', c_t, 'draft');
    v_r := public._agrupar_orcamentos_reabrindo(array[v_oc, v_od], array[v_oc], null, 'ORÇ-T99845', c_admin, null);
    update public.orcamento_agrupamento_origens x
       set motivo_perda_antes = null
     where x.agrupamento_id = (v_r ->> 'agrupamento_id')::uuid and x.origem_id = v_oc;
    perform public._desagrupar_orcamentos_desfazer((v_r ->> 'service_order_id')::uuid, c_admin);
    select so.status, so.quote_status, so.motivo_perda, so.motivo_perda_por, so.motivo_perda_em, so.motivo_perda_nota
      into v_so from public.service_orders so where so.id = v_oc;
    if v_so.status is distinct from 'draft' or v_so.quote_status is distinct from 'rejected'
       or v_so.motivo_perda is distinct from 'sem_motivo_antigo' or v_so.motivo_perda_por is distinct from 'migracao'
       or v_so.motivo_perda_em is null or v_so.motivo_perda_nota is not null then
      raise exception '8f: sem o motivo guardado, o Reprovado não voltou como os antigos (%)', row_to_json(v_so);
    end if;
    raise exception 'f5g_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5g_cenario' then
      raise;
    end if;
  end;

  raise exception 'retorno_f5_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f5_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f5_dado', true, '{}');
end
$dado$;

select arquivo, ok, numeros from _bancada order by em;
rollback;

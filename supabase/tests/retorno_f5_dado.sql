-- Retorno F5 (P9): a migration com dado (20270112100900_retorno_f5_dado.sql). Depois do arquivo, nenhum rejeitado sem motivo
-- e os antigos como 'sem_motivo_antigo' (o número contado antes, c_esperado); o CHECK service_orders_rejeitado_tem_motivo
-- (23514 com o nome dele) e o gatilho da P2 apagando o motivo ao reabrir; o padrão 3 → 7 só quando era 3; o histórico com
-- prova (o whatsapp_send_api que deu certo e o eco do aparelho, o 1º ao número do cliente, uma linha 'historico' por ordem,
-- nenhuma do gatilho, nenhum acompanhamento, e o candidato do aceite pela chave), sem a falha, o modo de teste, a recusa, o
-- outro número e o número de parceiro; rodada duas vezes, o mesmo resultado; e a trava "N ou 0". Roda só pela bancada (grupo
-- 8, F5_ONDA=8, F5_TESTES=retorno_f5_dado), de madrugada (o CHECK é DDL em service_orders). GERADO por
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

-- Prova: "Agrupar para o cliente" F2 — aprovar o conjunto (migration 20270129100000_agrupar_para_cliente_aprovar).
--
--   S1–S7 _orcamento_tem_sinal: sem condição (padrão) com e sem valor; parcela "na entrega"; percent antigo no dia 0;
--         sinal só de peças sem peças; desconto de 100%; preset vence as personalizadas
--   A1  ensaio: OS ASSINADA + ORÇ com sinal + ORÇ sem sinal → plano certo e NADA gravado (as 3 linhas idênticas)
--   A2  aprovar de verdade: a OS assinada idêntica (linha inteira); o com sinal aguarda o sinal (continua ORÇ) e o sem sinal
--       vira OS-… pela porta (mesmo id, prefixo trocado); os dois "complementa" a OS; nome do conjunto atualizado;
--       leitura: aprovavel falso e complementa_numero; o histórico grava o motivo do conjunto
--   A3  o sinal do complemento entra: vira OS própria, a marca continua (3A + 5A); a OS-X segue intacta
--   A4  aprovar de novo: "Nada a aprovar"
--   B1  só os marcados: o outro ORÇ fica como estava
--   B2  conjunto só de orçamentos: sem marca "complementa" (cartão 1)
--   B3  sinal já pago antes: vira OS agora
--   B4  ORÇ assinado (e não aprovado) não muda; com só ele de pendente: "Nada a aprovar"
--   C1  tudo ou nada: a porta recusa um (número já usado) → o outro também não muda e a frase da porta volta
--   C2  recusas: técnico 42501; sem autor 42501; documento fora do conjunto; conjunto desfeito; id nulo na lista
--   P1  privilégios: anon não chama a porta; authenticated não chama as internas
--
-- ═══ COMO RODAR ═══ (DEPOIS da migration aplicada, ou colando a migration antes deste arquivo, tudo em BEGIN…ROLLBACK)
--   npx -y supabase@2.111.0 --workdir <repo principal> db query --linked -f supabase/tests/agrupar_para_cliente_aprovar.sql
--
-- Seguro em produção: tudo nasce e morre na transação (números 9xxxxx livres, nada de WhatsApp). Termina em ROLLBACK.
-- A tabela final tem de mostrar ok = true em todas as linhas.
begin;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _ids (nome text primary key, id uuid) on commit drop;

create function pg_temp._letras(n integer) returns text language sql volatile as $$
  select translate(substr(md5(random()::text || clock_timestamp()::text), 1, n), '0123456789', 'ghijklmnop')
$$;
create function pg_temp._id(p_nome text) returns uuid language sql stable as $$
  select id from _ids where nome = p_nome
$$;
create function pg_temp._se(p_ok boolean, p_nome text) returns text language sql immutable as $$
  select case when coalesce(p_ok, false) then null else p_nome end
$$;
create function pg_temp._usuario(p_role text) returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into public.app_users (id, full_name, email, role, active)
  values (v_id, 'Teste aprovar conjunto (' || p_role || ')', 'teste-aprovar-conjunto-' || v_id || '@teste.invalido', p_role, true);
  return v_id;
end $$;
create function pg_temp._cliente() returns uuid language plpgsql as $$
declare v_id uuid;
begin
  insert into public.clients (type, name) values ('individual', 'Cliente Teste Aprovar ' || pg_temp._letras(6)) returning id into v_id;
  return v_id;
end $$;
create function pg_temp._barco(p_cli uuid) returns uuid language plpgsql as $$
declare v_id uuid;
begin
  insert into public.vessels (client_id, name) values (p_cli, 'Barco' || pg_temp._letras(8)) returning id into v_id;
  return v_id;
end $$;
create function pg_temp._numero_livre() returns text language plpgsql as $$
declare v_num integer := 900000 + floor(random() * 99000)::integer;
begin
  while exists (select 1 from public.service_orders where service_order_number in ('OS-' || v_num, 'ORÇ-' || v_num)) loop
    v_num := v_num + 1;
  end loop;
  return v_num::text;
end $$;
-- p_status 'draft' = orçamento (ORÇ-…); o resto = OS convertida. Mão de obra 1000 e peças 500 (total 1500).
create function pg_temp._doc(p_cli uuid, p_ves uuid, p_status text default 'approved', p_parcelas jsonb default null)
returns uuid language plpgsql as $$
declare v_os uuid; v_n text := pg_temp._numero_livre();
begin
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, converted_to_os_at,
                                     created_at, grand_total, labor_cost_total, parts_cost_total, custom_payment_installments)
  values (case when p_status = 'draft' then 'ORÇ-' else 'OS-' end || v_n, p_cli, p_ves, p_status,
          case when p_status = 'draft' then 'draft' else 'approved' end,
          case when p_status = 'draft' then null else now() end, clock_timestamp(), 1500, 1000, 500, p_parcelas)
  returning id into v_os;
  return v_os;
end $$;
create function pg_temp._linha(p_os uuid) returns jsonb language sql stable as $$
  select to_jsonb(so) from public.service_orders so where so.id = p_os
$$;
create function pg_temp._num(p_os uuid) returns text language sql stable as $$
  select service_order_number from public.service_orders where id = p_os
$$;
create function pg_temp._recusa(p_conj uuid, p_ids uuid[], p_autor uuid) returns text language plpgsql as $$
begin
  perform public._conjunto_aprovar(p_conj, p_ids, false, p_autor);
  return 'SEM ERRO';
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;
create function pg_temp._acao(r jsonb, p_os uuid) returns text language sql immutable as $$
  select d ->> 'acao' from jsonb_array_elements(r -> 'documentos') d where (d ->> 'id')::uuid = p_os
$$;

-- Condições: com sinal (50% do serviço + 100% das peças na aprovação, resto na entrega) e sem sinal (100% na entrega).
insert into _ids values ('admin', pg_temp._usuario('admin')), ('tecnico', pg_temp._usuario('technician'));
create temp table _cond (nome text primary key, parcelas jsonb) on commit drop;
insert into _cond values
  ('com_sinal', '[{"label":"Sinal","tipo":"aprovacao","services_pct":50,"parts_pct":100,"days_after_approval":0},
                 {"label":"Saldo","tipo":"entrega","services_pct":50,"parts_pct":0,"days_after_approval":0}]'),
  ('sem_sinal', '[{"label":"Na entrega","tipo":"entrega","services_pct":100,"parts_pct":100,"expenses_pct":100,"days_after_approval":0}]');
create function pg_temp._c(p text) returns jsonb language sql stable as $$ select parcelas from _cond where nome = p $$;

-- ── S: o sinal na condição ───────────────────────────────────────────────────────────────────────────────
do $$
declare v_cli uuid := pg_temp._cliente(); v_ves uuid; o uuid; v_preset uuid;
begin
  v_ves := pg_temp._barco(v_cli);
  o := pg_temp._doc(v_cli, v_ves, 'draft', null);
  insert into _resultado values ('S1 sem condição = padrão: tem sinal', public._orcamento_tem_sinal(o), '');
  update public.service_orders set labor_cost_total = 0, parts_cost_total = 0 where id = o;
  insert into _resultado values ('S2 sem condição e sem valor: sem sinal', not public._orcamento_tem_sinal(o), '');
  update public.service_orders set labor_cost_total = 1000, parts_cost_total = 500,
         custom_payment_installments = pg_temp._c('sem_sinal') where id = o;
  insert into _resultado values ('S3 só "na entrega": sem sinal', not public._orcamento_tem_sinal(o), '');
  update public.service_orders set custom_payment_installments = '[{"percent":30,"days_after_approval":0},{"percent":70,"days_after_approval":30}]'
   where id = o;
  insert into _resultado values ('S4 percent antigo no dia 0: tem sinal', public._orcamento_tem_sinal(o), '');
  update public.service_orders set parts_cost_total = 0,
         custom_payment_installments = '[{"tipo":"aprovacao","services_pct":0,"parts_pct":100},{"tipo":"entrega","services_pct":100}]'
   where id = o;
  insert into _resultado values ('S5 sinal só de peças, sem peças: sem sinal', not public._orcamento_tem_sinal(o), '');
  update public.service_orders set parts_cost_total = 500, discount_amount = 1500 where id = o;
  insert into _resultado values ('S6 desconto de 100%: sem sinal', not public._orcamento_tem_sinal(o), '');
  insert into public.payment_condition_presets (label, installments)
  values ('Teste aprovar conjunto ' || pg_temp._letras(6), pg_temp._c('com_sinal')) returning id into v_preset;
  update public.service_orders set discount_amount = 0, payment_condition_preset_id = v_preset,
         custom_payment_installments = pg_temp._c('sem_sinal') where id = o;
  insert into _resultado values ('S7 o preset vence as personalizadas', public._orcamento_tem_sinal(o), '');
exception when others then
  insert into _resultado values ('S sinal na condição', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ── A1 ensaio ────────────────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_cli uuid := pg_temp._cliente(); v_ves uuid; a uuid; b uuid; c uuid; v_conj uuid; r jsonb; v_falhas text;
  antes_a jsonb; antes_b jsonb; antes_c jsonb;
begin
  v_ves := pg_temp._barco(v_cli);
  a := pg_temp._doc(v_cli, v_ves, 'scheduled', pg_temp._c('com_sinal'));
  update public.service_orders set check_in_at = now() - interval '1 day', signed_at = now() - interval '2 days' where id = a;
  b := pg_temp._doc(v_cli, v_ves, 'draft', pg_temp._c('com_sinal'));
  c := pg_temp._doc(v_cli, v_ves, 'draft', pg_temp._c('sem_sinal'));
  update public.service_orders set quote_status = 'sent' where id = c;
  v_conj := (public._conjunto_montar(array[a, b, c], null, pg_temp._id('admin')) ->> 'conjunto_id')::uuid;
  insert into _ids values ('a_cli', v_cli), ('a_ves', v_ves), ('a_a', a), ('a_b', b), ('a_c', c), ('a_conj', v_conj);
  antes_a := pg_temp._linha(a); antes_b := pg_temp._linha(b); antes_c := pg_temp._linha(c);

  r := public._conjunto_aprovar(v_conj, null, true, pg_temp._id('admin'));
  v_falhas := concat_ws(', ',
    pg_temp._se((r ->> 'ok')::boolean and (r ->> 'ensaio')::boolean, 'ok/ensaio'),
    pg_temp._se(pg_temp._acao(r, a) = 'nao_muda', 'OS assinada não muda'),
    pg_temp._se(pg_temp._acao(r, b) = 'aguardar_sinal', 'com sinal aguarda'),
    pg_temp._se(pg_temp._acao(r, c) = 'virar_os', 'sem sinal vira OS'),
    pg_temp._se((r -> 'complementa' ->> 'id')::uuid = a, 'complementa a OS'),
    pg_temp._se((r ->> 'aprovados')::int = 2 and (r ->> 'viraram_os')::int = 1 and (r ->> 'aguardando_sinal')::int = 1, 'contagens'),
    pg_temp._se((select d ->> 'numero_depois' from jsonb_array_elements(r -> 'documentos') d where (d ->> 'id')::uuid = c)
                = 'OS-' || substr(pg_temp._num(c), 5), 'numero_depois'),
    pg_temp._se(pg_temp._linha(a) = antes_a and pg_temp._linha(b) = antes_b and pg_temp._linha(c) = antes_c, 'nada gravado'),
    pg_temp._se((public._conjunto_ler(v_conj) -> 'documentos' -> 1 ->> 'aprovavel')::boolean
                and not (public._conjunto_ler(v_conj) -> 'documentos' -> 0 ->> 'aprovavel')::boolean, 'aprovavel na leitura'));
  insert into _resultado values ('A1 ensaio: plano certo e nada gravado', v_falhas = '',
    case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas || ' | ' || r::text end);
exception when others then
  insert into _resultado values ('A1 ensaio: plano certo e nada gravado', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ── A2 aprovar de verdade ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  a uuid := pg_temp._id('a_a'); b uuid := pg_temp._id('a_b'); c uuid := pg_temp._id('a_c'); v_conj uuid := pg_temp._id('a_conj');
  antes_a jsonb := pg_temp._linha(a); num_b text := pg_temp._num(b); num_c text := pg_temp._num(c);
  r jsonb; l jsonb; v_falhas text; sb record; sc record;
begin
  r := public._conjunto_aprovar(v_conj, null, false, pg_temp._id('admin'));
  select * into sb from public.service_orders where id = b;
  select * into sc from public.service_orders where id = c;
  l := public._conjunto_ler(v_conj);
  v_falhas := concat_ws(', ',
    pg_temp._se((r ->> 'ok')::boolean and not (r ->> 'ensaio')::boolean, 'ok'),
    pg_temp._se(pg_temp._linha(a) = antes_a, 'OS assinada idêntica'),
    pg_temp._se(sb.status = 'draft' and sb.quote_status = 'awaiting_deposit' and sb.service_order_number = num_b
                and sb.converted_to_os_at is null and sb.complementa_os_id = a, 'com sinal: aguardando, ORÇ, marcado'),
    pg_temp._se(sc.status = 'approved' and sc.quote_status = 'approved' and sc.converted_to_os_at is not null
                and sc.service_order_number = 'OS-' || substr(num_c, 5) and sc.complementa_os_id = a, 'sem sinal: virou OS, marcado'),
    pg_temp._se(l ->> 'nome' = pg_temp._num(a) || ' + ' || num_b || ' + OS-' || substr(num_c, 5), 'nome: ' || (l ->> 'nome')),
    pg_temp._se(not exists (select 1 from jsonb_array_elements(l -> 'documentos') d where (d ->> 'aprovavel')::boolean), 'nada aprovável'),
    pg_temp._se((l -> 'documentos' -> 1 ->> 'complementa_numero') = pg_temp._num(a), 'complementa_numero'),
    pg_temp._se(exists (select 1 from public.audit_log x where x.record_id::text = c::text and x.reason like 'Aprovado junto com o conjunto%'), 'histórico com motivo'),
    pg_temp._se(l -> 'documentos' -> 2 ->> 'tipo' = 'os', 'tipo os na leitura'));
  insert into _resultado values ('A2 aprovar: assinada intacta, sinal aguarda, sem sinal vira OS, marca', v_falhas = '',
    case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas || ' | ' || r::text end);
exception when others then
  insert into _resultado values ('A2 aprovar: assinada intacta, sinal aguarda, sem sinal vira OS, marca', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ── A3 o sinal do complemento entra ──────────────────────────────────────────────────────────────────────
do $$
declare
  a uuid := pg_temp._id('a_a'); b uuid := pg_temp._id('a_b'); antes_a jsonb := pg_temp._linha(a); v_rec uuid; sb record;
begin
  insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, balance_amount, status, is_deposit)
  values (pg_temp._id('a_cli'), b, 'Teste aprovar: sinal do complemento', current_date, current_date, 1000, 1000, 'pending', true)
  returning id into v_rec;
  update public.receivables set status = 'paid', paid_amount = 1000, balance_amount = 0 where id = v_rec;
  select * into sb from public.service_orders where id = b;
  insert into _resultado values ('A3 sinal pago: vira OS própria, marca fica, OS-X intacta',
    sb.converted_to_os_at is not null and sb.status <> 'draft' and sb.complementa_os_id = a and pg_temp._linha(a) = antes_a,
    format('status=%s numero=%s conv=%s compl=%s', sb.status, sb.service_order_number, sb.converted_to_os_at, sb.complementa_os_id));
exception when others then
  insert into _resultado values ('A3 sinal pago: vira OS própria, marca fica, OS-X intacta', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ── A4 de novo ───────────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'A4 aprovar de novo: nada a aprovar', m like '%Nada a aprovar%', m
  from (select pg_temp._recusa(pg_temp._id('a_conj'), null, pg_temp._id('admin')) as m) x;

-- ── B1 só os marcados ────────────────────────────────────────────────────────────────────────────────────
do $$
declare v_cli uuid := pg_temp._cliente(); v_ves uuid; a uuid; b uuid; c uuid; v_conj uuid; r jsonb; antes_c jsonb;
begin
  v_ves := pg_temp._barco(v_cli);
  a := pg_temp._doc(v_cli, v_ves, 'open');
  b := pg_temp._doc(v_cli, v_ves, 'draft', pg_temp._c('com_sinal'));
  c := pg_temp._doc(v_cli, v_ves, 'draft', pg_temp._c('com_sinal'));
  v_conj := (public._conjunto_montar(array[a, b, c], null, pg_temp._id('admin')) ->> 'conjunto_id')::uuid;
  antes_c := pg_temp._linha(c);
  r := public._conjunto_aprovar(v_conj, array[b], false, pg_temp._id('admin'));
  insert into _resultado values ('B1 só os marcados',
    (select quote_status = 'awaiting_deposit' and complementa_os_id = a from public.service_orders where id = b)
    and pg_temp._linha(c) = antes_c and pg_temp._acao(r, c) = 'nao_muda' and (r ->> 'aprovados')::int = 1, r::text);
exception when others then
  insert into _resultado values ('B1 só os marcados', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ── B2 só orçamentos ─────────────────────────────────────────────────────────────────────────────────────
do $$
declare v_cli uuid := pg_temp._cliente(); v_ves uuid; b uuid; c uuid; v_conj uuid; r jsonb;
begin
  v_ves := pg_temp._barco(v_cli);
  b := pg_temp._doc(v_cli, v_ves, 'draft', pg_temp._c('com_sinal'));
  c := pg_temp._doc(v_cli, v_ves, 'draft', pg_temp._c('sem_sinal'));
  v_conj := (public._conjunto_montar(array[b, c], null, pg_temp._id('admin')) ->> 'conjunto_id')::uuid;
  r := public._conjunto_aprovar(v_conj, null, false, pg_temp._id('admin'));
  insert into _resultado values ('B2 só orçamentos: aprova sem marca',
    r -> 'complementa' = 'null'::jsonb
    and (select quote_status = 'awaiting_deposit' and complementa_os_id is null from public.service_orders where id = b)
    and (select status = 'approved' and complementa_os_id is null from public.service_orders where id = c), r::text);
exception when others then
  insert into _resultado values ('B2 só orçamentos: aprova sem marca', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ── B3 sinal já pago ─────────────────────────────────────────────────────────────────────────────────────
do $$
declare v_cli uuid := pg_temp._cliente(); v_ves uuid; a uuid; b uuid; v_conj uuid; r jsonb;
begin
  v_ves := pg_temp._barco(v_cli);
  a := pg_temp._doc(v_cli, v_ves, 'open');
  b := pg_temp._doc(v_cli, v_ves, 'draft', pg_temp._c('com_sinal'));
  insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status, is_deposit)
  values (v_cli, b, 'Teste aprovar: sinal já pago', current_date, current_date, 1000, 1000, 0, 'paid', true);
  v_conj := (public._conjunto_montar(array[a, b], null, pg_temp._id('admin')) ->> 'conjunto_id')::uuid;
  r := public._conjunto_aprovar(v_conj, null, false, pg_temp._id('admin'));
  insert into _resultado values ('B3 sinal já pago: vira OS agora',
    pg_temp._acao(r, b) = 'virar_os'
    and (select converted_to_os_at is not null and complementa_os_id = a from public.service_orders where id = b), r::text);
exception when others then
  insert into _resultado values ('B3 sinal já pago: vira OS agora', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ── B4 ORÇ assinado não muda ─────────────────────────────────────────────────────────────────────────────
do $$
declare v_cli uuid := pg_temp._cliente(); v_ves uuid; a uuid; b uuid; v_conj uuid; r jsonb; antes_b jsonb; v_m text;
begin
  v_ves := pg_temp._barco(v_cli);
  a := pg_temp._doc(v_cli, v_ves, 'open');
  b := pg_temp._doc(v_cli, v_ves, 'draft', pg_temp._c('sem_sinal'));
  update public.service_orders set signed_at = now() where id = b;
  v_conj := (public._conjunto_montar(array[a, b], null, pg_temp._id('admin')) ->> 'conjunto_id')::uuid;
  antes_b := pg_temp._linha(b);
  r := public._conjunto_aprovar(v_conj, null, true, pg_temp._id('admin'));
  v_m := pg_temp._recusa(v_conj, null, pg_temp._id('admin'));
  insert into _resultado values ('B4 ORÇ assinado não muda',
    pg_temp._acao(r, b) = 'nao_muda' and v_m like '%Nada a aprovar%' and pg_temp._linha(b) = antes_b, v_m);
exception when others then
  insert into _resultado values ('B4 ORÇ assinado não muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ── C1 tudo ou nada ──────────────────────────────────────────────────────────────────────────────────────
do $$
declare v_cli uuid := pg_temp._cliente(); v_ves uuid; a uuid; b uuid; c uuid; v_conj uuid; antes_b jsonb; antes_c jsonb; v_m text;
        v_outro uuid;
begin
  v_ves := pg_temp._barco(v_cli);
  a := pg_temp._doc(v_cli, v_ves, 'open');
  b := pg_temp._doc(v_cli, v_ves, 'draft', pg_temp._c('com_sinal'));
  c := pg_temp._doc(v_cli, v_ves, 'draft', pg_temp._c('sem_sinal'));
  v_conj := (public._conjunto_montar(array[a, b, c], null, pg_temp._id('admin')) ->> 'conjunto_id')::uuid;
  -- Outro documento (de outro cliente) já usa o número que o C ganharia.
  v_outro := pg_temp._cliente();
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, converted_to_os_at, grand_total)
  values ('OS-' || substr(pg_temp._num(c), 5), v_outro, pg_temp._barco(v_outro), 'approved', 'approved', now(), 10);
  antes_b := pg_temp._linha(b); antes_c := pg_temp._linha(c);
  v_m := pg_temp._recusa(v_conj, null, pg_temp._id('admin'));
  insert into _resultado values ('C1 tudo ou nada: a porta recusa um, nenhum muda',
    v_m like '%já é de outra OS%' and pg_temp._linha(b) = antes_b and pg_temp._linha(c) = antes_c, v_m);
exception when others then
  insert into _resultado values ('C1 tudo ou nada: a porta recusa um, nenhum muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ── C2 recusas ───────────────────────────────────────────────────────────────────────────────────────────
do $$
declare v_cli uuid := pg_temp._cliente(); v_ves uuid; a uuid; b uuid; x uuid; v_conj uuid; v_m text;
begin
  v_ves := pg_temp._barco(v_cli);
  a := pg_temp._doc(v_cli, v_ves, 'open');
  b := pg_temp._doc(v_cli, v_ves, 'draft');
  x := pg_temp._doc(v_cli, v_ves, 'draft');
  v_conj := (public._conjunto_montar(array[a, b], null, pg_temp._id('admin')) ->> 'conjunto_id')::uuid;
  v_m := pg_temp._recusa(v_conj, null, pg_temp._id('tecnico'));
  insert into _resultado values ('C2a técnico: 42501', v_m like '42501%', v_m);
  begin
    perform public.aprovar_conjunto(v_conj, null, false, null); v_m := 'SEM ERRO';
  exception when others then v_m := sqlstate || ' ' || sqlerrm; end;
  insert into _resultado values ('C2b sem autor: 42501', v_m like '42501%', v_m);
  v_m := pg_temp._recusa(v_conj, array[x], pg_temp._id('admin'));
  insert into _resultado values ('C2c documento fora do conjunto', v_m like '%não está neste conjunto%', v_m);
  v_m := pg_temp._recusa(v_conj, array[b, null], pg_temp._id('admin'));
  insert into _resultado values ('C2d id nulo na lista', v_m like '%Escolha os orçamentos%', v_m);
  perform public._conjunto_desfazer(v_conj, pg_temp._id('admin'), 'manual');
  v_m := pg_temp._recusa(v_conj, null, pg_temp._id('admin'));
  insert into _resultado values ('C2e conjunto desfeito', v_m like '%foi desfeito%'
    and (select quote_status = 'draft' from public.service_orders where id = b), v_m);
exception when others then
  insert into _resultado values ('C2 recusas', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ── P: privilégios ──────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'P1 privilégios',
  not has_function_privilege('anon', 'public.aprovar_conjunto(uuid, uuid[], boolean, uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.aprovar_conjunto(uuid, uuid[], boolean, uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public._conjunto_aprovar(uuid, uuid[], boolean, uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public._orcamento_tem_sinal(uuid)', 'execute')
  and not has_function_privilege('anon', 'public._conjunto_situacao_para_aprovar(uuid)', 'execute'),
  '';

select teste, ok, detalhe from _resultado order by teste;

rollback;

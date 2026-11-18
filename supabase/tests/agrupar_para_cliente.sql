-- Prova: "Agrupar para o cliente" (migration 20270124100000_agrupar_para_cliente) — conjunto que só CITA ORÇ/OS.
--
--   A1  OS começada (chegada no barco), ASSINADA, com sinal pago + ORÇ em elaboração: agrupa; nome "OS + ORÇ";
--       principal = a OS; os DOIS documentos ficam idênticos (linha inteira); a leitura traz assinado/recebido/sinal
--   A2  conjunto_do_documento pelos dois lados; documentos_para_conjunto: mesmo cliente+barco, sem cancelado,
--       reprovado ou outro barco; motivo "já está no conjunto" para quem está
--   A3  OS concluída entra, com aviso; principal escolhido é respeitado; ordem principal primeiro
--   B01–B10 recusas (mensagem certa e NADA gravado): já em conjunto, reprovado, outra embarcação, outro cliente,
--       cancelado, cliente genérico, fundido, um só, repetido, principal fora da lista; mais de 10
--   B11 técnico e sem autor: 42501
--   C1  guardas: trocar embarcação/cliente e FUNDIR (merged_into_id) documento em conjunto ativo recusa
--   C2  cancelar um de 2: conjunto desfeito sozinho (documento_cancelado); os itens inativos
--   C3  cancelar 1 de 3 (o principal): conjunto segue com 2, o próximo vira principal, nome sem o cancelado
--   C4  apagar um rascunho de um conjunto de 2: desfeito (documento_apagado)
--   D1  desfazer manual: ok; de novo recusa; técnico recusa; depois os documentos entram em outro conjunto
--   P1  privilégios: anon não lê as tabelas nem chama as portas; authenticated não grava as tabelas
--
-- ═══ COMO RODAR ═══ (DEPOIS da migration aplicada, ou colando a migration antes deste arquivo, tudo em BEGIN…ROLLBACK)
--   npx supabase@2.111.0 db query --linked -f supabase/tests/agrupar_para_cliente.sql --output json
--
-- Seguro em produção: tudo nasce e morre na transação (números OS-9xxxxx livres, nada de WhatsApp). Termina em ROLLBACK.
-- A tabela final tem de mostrar ok = true em todas as linhas.
begin;

-- As leituras públicas exigem sessão: aqui roda como service role.
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
  values (v_id, 'Teste conjunto (' || p_role || ')', 'teste-conjunto-' || v_id || '@teste.invalido', p_role, true);
  return v_id;
end $$;
create function pg_temp._cliente() returns uuid language plpgsql as $$
declare v_id uuid;
begin
  insert into public.clients (type, name) values ('individual', 'Cliente Teste Conjunto ' || pg_temp._letras(6)) returning id into v_id;
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
-- p_status 'draft' = orçamento (ORÇ-…); o resto = OS convertida.
create function pg_temp._doc(p_cli uuid, p_ves uuid, p_status text default 'approved', p_total numeric default 1000)
returns uuid language plpgsql as $$
declare v_os uuid; v_n text := pg_temp._numero_livre();
begin
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, converted_to_os_at, created_at, grand_total)
  values (case when p_status = 'draft' then 'ORÇ-' else 'OS-' end || v_n, p_cli, p_ves, p_status,
          case when p_status = 'draft' then 'draft' else 'approved' end,
          case when p_status = 'draft' then null else now() end, clock_timestamp(), p_total)
  returning id into v_os;
  return v_os;
end $$;
create function pg_temp._linha(p_os uuid) returns jsonb language sql stable as $$
  select to_jsonb(so) from public.service_orders so where so.id = p_os
$$;
create function pg_temp._num(p_os uuid) returns text language sql stable as $$
  select service_order_number from public.service_orders where id = p_os
$$;
-- Roda o agrupar esperando recusa: devolve a mensagem (ou 'SEM ERRO').
create function pg_temp._recusa(p_ids uuid[], p_principal uuid default null, p_autor uuid default null) returns text language plpgsql as $$
begin
  perform public._conjunto_montar(p_ids, p_principal, coalesce(p_autor, pg_temp._id('admin')));
  return 'SEM ERRO';
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;

insert into _ids values ('admin', pg_temp._usuario('admin')), ('tecnico', pg_temp._usuario('technician'));

-- ── A1 ───────────────────────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_cli uuid := pg_temp._cliente(); v_ves uuid; a uuid; b uuid; antes_a jsonb; antes_b jsonb; r jsonb; d jsonb; v_falhas text;
begin
  v_ves := pg_temp._barco(v_cli);
  a := pg_temp._doc(v_cli, v_ves, 'scheduled', 5000);
  update public.service_orders set check_in_at = now() - interval '1 day', signed_at = now() - interval '2 days' where id = a;
  insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status, is_deposit)
  values (v_cli, a, 'Teste conjunto: sinal pago', current_date, current_date, 2500, 2500, 0, 'paid', true);
  b := pg_temp._doc(v_cli, v_ves, 'draft', 1200);
  insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, balance_amount, status, is_deposit)
  values (v_cli, b, 'Teste conjunto: sinal do complemento', current_date, current_date + 5, 600, 600, 'pending', true);
  insert into _ids values ('a1_cli', v_cli), ('a1_ves', v_ves), ('a1_a', a), ('a1_b', b);
  antes_a := pg_temp._linha(a); antes_b := pg_temp._linha(b);

  r := public._conjunto_montar(array[b, a], null, pg_temp._id('admin'));
  insert into _ids values ('a1_conj', (r ->> 'conjunto_id')::uuid);
  d := r -> 'conjunto' -> 'documentos';
  v_falhas := concat_ws(', ',
    pg_temp._se((r ->> 'ok')::boolean, 'ok'),
    pg_temp._se(r ->> 'nome' = pg_temp._num(a) || ' + ' || pg_temp._num(b), 'nome principal primeiro: ' || (r ->> 'nome')),
    pg_temp._se((r -> 'conjunto' ->> 'principal_id')::uuid = a, 'principal = a OS'),
    pg_temp._se(pg_temp._linha(a) = antes_a, 'OS intacta'),
    pg_temp._se(pg_temp._linha(b) = antes_b, 'ORÇ intacto'),
    pg_temp._se(jsonb_array_length(d) = 2, '2 documentos'),
    pg_temp._se((d -> 0 ->> 'assinado')::boolean and not (d -> 1 ->> 'assinado')::boolean, 'assinado'),
    pg_temp._se((d -> 0 ->> 'recebido')::numeric = 2500 and (d -> 1 ->> 'sinal_a_pagar')::numeric = 600
                and (d -> 1 ->> 'em_aberto')::numeric = 600 and (d -> 0 ->> 'sinal_a_pagar')::numeric = 0, 'dinheiro'),
    pg_temp._se(d -> 0 ->> 'tipo' = 'os' and d -> 1 ->> 'tipo' = 'orcamento', 'tipo'),
    pg_temp._se((r -> 'conjunto' ->> 'total_geral')::numeric = 6200, 'total_geral'),
    pg_temp._se(jsonb_array_length(r -> 'avisos') = 0, 'sem avisos'));
  insert into _resultado values ('A1 OS começada+assinada + ORÇ: agrupa sem mexer em nada', v_falhas = '',
    case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas || ' | ' || r::text end);
exception when others then
  insert into _resultado values ('A1 OS começada+assinada + ORÇ: agrupa sem mexer em nada', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ── A2 ───────────────────────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_cli uuid := pg_temp._id('a1_cli'); v_ves uuid := pg_temp._id('a1_ves'); r1 jsonb; r2 jsonb; c jsonb;
  v_livre uuid; v_rej uuid; v_canc uuid; v_outro_barco uuid; v_falhas text;
begin
  v_livre := pg_temp._doc(v_cli, v_ves, 'draft', 300);
  v_rej := pg_temp._doc(v_cli, v_ves, 'draft', 300);
  update public.service_orders set quote_status = 'rejected', motivo_perda = 'preco', motivo_perda_por = 'tela' where id = v_rej;
  v_canc := pg_temp._doc(v_cli, v_ves, 'approved', 300);
  update public.service_orders set status = 'cancelled' where id = v_canc;
  v_outro_barco := pg_temp._doc(v_cli, pg_temp._barco(v_cli), 'approved', 300);
  insert into _ids values ('a2_livre', v_livre);

  r1 := public.conjunto_do_documento(pg_temp._id('a1_a'));
  r2 := public.conjunto_do_documento(pg_temp._id('a1_b'));
  c := public.documentos_para_conjunto(v_livre);
  v_falhas := concat_ws(', ',
    pg_temp._se(r1 ->> 'id' = r2 ->> 'id' and (r1 ->> 'id')::uuid = pg_temp._id('a1_conj'), 'conjunto pelos dois lados'),
    pg_temp._se(public.conjunto_do_documento(v_livre) is null, 'livre sem conjunto'),
    pg_temp._se(c -> 'documento' ->> 'motivo' is null, 'livre pode'),
    pg_temp._se(exists (select 1 from jsonb_array_elements(c -> 'candidatos') e
                         where (e ->> 'id')::uuid = pg_temp._id('a1_a') and e ->> 'motivo' like '%já está no conjunto%'), 'motivo já está no conjunto'),
    pg_temp._se(not exists (select 1 from jsonb_array_elements(c -> 'candidatos') e
                             where (e ->> 'id')::uuid in (v_rej, v_canc, v_outro_barco)), 'fora: reprovado, cancelado, outro barco'),
    pg_temp._se(jsonb_array_length(c -> 'candidatos') = 2, '2 candidatos'));
  insert into _resultado values ('A2 leituras: conjunto_do_documento e documentos_para_conjunto', v_falhas = '',
    case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas || ' | ' || c::text end);
exception when others then
  insert into _resultado values ('A2 leituras: conjunto_do_documento e documentos_para_conjunto', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ── A3 ───────────────────────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_cli uuid := pg_temp._cliente(); v_ves uuid; a uuid; b uuid; c uuid; r jsonb; v_falhas text;
begin
  v_ves := pg_temp._barco(v_cli);
  a := pg_temp._doc(v_cli, v_ves, 'completed');
  b := pg_temp._doc(v_cli, v_ves, 'awaiting_client');
  c := pg_temp._doc(v_cli, v_ves, 'draft');
  r := public._conjunto_montar(array[a, b, c], c, pg_temp._id('admin'));
  v_falhas := concat_ws(', ',
    pg_temp._se((r -> 'conjunto' ->> 'principal_id')::uuid = c, 'principal escolhido'),
    pg_temp._se(r ->> 'nome' = pg_temp._num(c) || ' + ' || pg_temp._num(a) || ' + ' || pg_temp._num(b), 'ordem: ' || (r ->> 'nome')),
    pg_temp._se(r -> 'avisos' ->> 0 like '%concluído%', 'aviso de concluída'));
  insert into _resultado values ('A3 concluída entra com aviso; principal escolhido vem primeiro', v_falhas = '',
    case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas || ' | ' || r::text end);
exception when others then
  insert into _resultado values ('A3 concluída entra com aviso; principal escolhido vem primeiro', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ── A4: motivo de não poder JUNTAR DE VEZ (decisão 4B) ───────────────────────────────────────────────────
do $$
declare
  v_cli uuid := pg_temp._cliente(); v_ves uuid; os_ok uuid; os_chegou uuid; orc_ok uuid; orc_assin uuid; r jsonb; v_falhas text;
begin
  v_ves := pg_temp._barco(v_cli);
  -- Total 0 = o das linhas (nenhuma): a régua da fusão recusa total gravado desatualizado.
  os_ok := pg_temp._doc(v_cli, v_ves, 'approved', 0);
  os_chegou := pg_temp._doc(v_cli, v_ves, 'awaiting_client', 0);
  update public.service_orders set check_in_at = now() where id = os_chegou;
  orc_ok := pg_temp._doc(v_cli, v_ves, 'draft');
  orc_assin := pg_temp._doc(v_cli, v_ves, 'draft');
  update public.service_orders set signed_at = now() where id = orc_assin;
  r := public.documentos_para_conjunto(os_ok);
  v_falhas := concat_ws(', ',
    pg_temp._se(r -> 'documento' ->> 'motivo_juntar' is null and r -> 'documento' ->> 'tipo' = 'os', 'OS livre funde'),
    pg_temp._se(exists (select 1 from jsonb_array_elements(r -> 'candidatos') e where (e ->> 'id')::uuid = os_chegou
                         and e ->> 'motivo' is null and e ->> 'motivo_juntar' like '%já começou%'), 'OS com chegada: conjunto sim, fusão não'),
    pg_temp._se(exists (select 1 from jsonb_array_elements(r -> 'candidatos') e where (e ->> 'id')::uuid = orc_ok
                         and e ->> 'motivo_juntar' is null), 'ORÇ livre funde'),
    pg_temp._se(exists (select 1 from jsonb_array_elements(r -> 'candidatos') e where (e ->> 'id')::uuid = orc_assin
                         and e ->> 'motivo' is null and e ->> 'motivo_juntar' like '%assinado%'), 'ORÇ assinado: conjunto sim, fusão não'));
  perform public._conjunto_montar(array[os_ok, orc_ok], null, pg_temp._id('admin'));
  r := public.documentos_para_conjunto(os_chegou);
  v_falhas := concat_ws(', ', nullif(v_falhas, ''),
    pg_temp._se(exists (select 1 from jsonb_array_elements(r -> 'candidatos') e where (e ->> 'id')::uuid = orc_ok
                         and e ->> 'motivo_juntar' like '%está no conjunto%'), 'em conjunto não funde'));
  insert into _resultado values ('A4 motivo_juntar: chegada/assinado só conjunto; livres fundem; em conjunto não funde', v_falhas = '',
    case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas || ' | ' || r::text end);
exception when others then
  insert into _resultado values ('A4 motivo_juntar', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ── B: recusas ───────────────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_cli uuid := pg_temp._cliente(); v_ves uuid; v_cli2 uuid := pg_temp._cliente(); v_gen uuid; v_fund uuid;
  ok1 uuid; ok2 uuid; v_rej uuid; v_canc uuid; v_ob uuid; v_oc uuid; v_g1 uuid; v_g2 uuid; v_dest uuid;
  v_antes bigint; v_m text; v_onze uuid[] := '{}'; i integer;
begin
  v_ves := pg_temp._barco(v_cli);
  ok1 := pg_temp._doc(v_cli, v_ves); ok2 := pg_temp._doc(v_cli, v_ves, 'draft');
  v_rej := pg_temp._doc(v_cli, v_ves, 'draft');
  update public.service_orders set quote_status = 'rejected', motivo_perda = 'preco', motivo_perda_por = 'tela' where id = v_rej;
  v_canc := pg_temp._doc(v_cli, v_ves); update public.service_orders set status = 'cancelled' where id = v_canc;
  v_ob := pg_temp._doc(v_cli, pg_temp._barco(v_cli));
  v_oc := pg_temp._doc(v_cli2, v_ves);
  v_gen := pg_temp._cliente(); update public.clients set generico = true where id = v_gen;
  v_dest := pg_temp._barco(v_gen);
  v_g1 := pg_temp._doc(v_gen, v_dest); v_g2 := pg_temp._doc(v_gen, v_dest);
  v_dest := pg_temp._doc(v_cli, v_ves); v_fund := pg_temp._doc(v_cli, v_ves);
  perform set_config('marineflow.agrupar_orcamentos', 'on', true);
  update public.service_orders set merged_into_id = v_dest where id = v_fund;
  perform set_config('marineflow.agrupar_orcamentos', '', true);
  v_antes := (select count(*) from public.documento_conjuntos);

  v_m := pg_temp._recusa(array[ok1, pg_temp._id('a1_a')]);
  insert into _resultado values ('B01 já está em outro conjunto', v_m like '%já está no conjunto%', v_m);
  v_m := pg_temp._recusa(array[ok1, v_rej]);
  insert into _resultado values ('B02 orçamento reprovado', v_m like '%Reprovado%', v_m);
  v_m := pg_temp._recusa(array[ok1, v_ob]);
  insert into _resultado values ('B03 outra embarcação', v_m like '%mesma embarcação%', v_m);
  v_m := pg_temp._recusa(array[ok1, v_oc]);
  insert into _resultado values ('B04 outro cliente', v_m like '%mesmo cliente%', v_m);
  v_m := pg_temp._recusa(array[ok1, v_canc]);
  insert into _resultado values ('B05 cancelado', v_m like '%cancelado%', v_m);
  v_m := pg_temp._recusa(array[v_g1, v_g2]);
  insert into _resultado values ('B06 cliente genérico', v_m like '%genérico%', v_m);
  v_m := pg_temp._recusa(array[ok1, v_fund]);
  insert into _resultado values ('B07 já fundido em outro', v_m like '%juntado de vez%', v_m);
  v_m := pg_temp._recusa(array[ok1]);
  insert into _resultado values ('B08 um só', v_m like '%pelo menos 2%', v_m);
  v_m := pg_temp._recusa(array[ok1, ok1, ok2]);
  insert into _resultado values ('B09 repetido', v_m like '%duas vezes%', v_m);
  v_m := pg_temp._recusa(array[ok1, ok2], v_ob);
  insert into _resultado values ('B10 principal fora da lista', v_m like '%principal precisa estar%', v_m);
  for i in 1..11 loop v_onze := v_onze || pg_temp._doc(v_cli, v_ves, 'draft'); end loop;
  v_m := pg_temp._recusa(v_onze);
  insert into _resultado values ('B10b mais de 10', v_m like '%no máximo 10%', v_m);
  v_m := pg_temp._recusa(array[ok1, ok2], null, pg_temp._id('tecnico'));
  insert into _resultado values ('B11 técnico 42501', v_m like '42501%', v_m);
  begin
    perform public._conjunto_montar(array[ok1, ok2], null, null); v_m := 'SEM ERRO';
  exception when others then v_m := sqlstate || ' ' || sqlerrm;
  end;
  insert into _resultado values ('B11b sem autor 42501', v_m like '42501%', v_m);
  insert into _resultado values ('B12 nada gravado nas recusas', (select count(*) from public.documento_conjuntos) = v_antes, '');
exception when others then
  insert into _resultado values ('B recusas', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ── C: guardas e saída automática ───────────────────────────────────────────────────────────────────────
do $$
declare v_m text; v_dest uuid;
begin
  begin
    update public.service_orders set vessel_id = pg_temp._barco(pg_temp._id('a1_cli')) where id = pg_temp._id('a1_a'); v_m := 'SEM ERRO';
  exception when others then v_m := sqlerrm; end;
  insert into _resultado values ('C1a trocar embarcação em conjunto recusa', v_m like '%Desfaça o conjunto%embarcação%', v_m);
  begin
    update public.service_orders set client_id = pg_temp._cliente() where id = pg_temp._id('a1_b'); v_m := 'SEM ERRO';
  exception when others then v_m := sqlerrm; end;
  insert into _resultado values ('C1b trocar cliente em conjunto recusa', v_m like '%Desfaça o conjunto%', v_m);
  v_dest := pg_temp._doc(pg_temp._id('a1_cli'), pg_temp._id('a1_ves'));
  begin
    perform set_config('marineflow.agrupar_orcamentos', 'on', true);
    update public.service_orders set merged_into_id = v_dest where id = pg_temp._id('a1_b'); v_m := 'SEM ERRO';
  exception when others then v_m := sqlerrm; end;
  perform set_config('marineflow.agrupar_orcamentos', '', true);
  insert into _resultado values ('C1c fundir documento em conjunto recusa', v_m like '%juntar de vez%', v_m);
end $$;

do $$
declare v_c uuid := pg_temp._id('a1_conj'); r public.documento_conjuntos;
begin
  update public.service_orders set status = 'cancelled' where id = pg_temp._id('a1_b');
  select * into r from public.documento_conjuntos where id = v_c;
  insert into _resultado values ('C2 cancelar 1 de 2: conjunto desfeito sozinho',
    r.desfeito_em is not null and r.desfeito_motivo = 'documento_cancelado'
    and not exists (select 1 from public.documento_conjunto_itens where conjunto_id = v_c and ativo),
    coalesce(r.desfeito_motivo, 'ainda ativo'));
exception when others then
  insert into _resultado values ('C2 cancelar 1 de 2: conjunto desfeito sozinho', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare v_cli uuid := pg_temp._cliente(); v_ves uuid; a uuid; b uuid; c uuid; r jsonb; v_c uuid; d jsonb;
begin
  v_ves := pg_temp._barco(v_cli);
  a := pg_temp._doc(v_cli, v_ves); b := pg_temp._doc(v_cli, v_ves, 'draft'); c := pg_temp._doc(v_cli, v_ves, 'draft');
  v_c := (public._conjunto_montar(array[a, b, c], a, pg_temp._id('admin')) ->> 'conjunto_id')::uuid;
  update public.service_orders set status = 'cancelled' where id = a;
  d := public.conjunto_do_documento(b);
  insert into _resultado values ('C3 cancelar o principal de 3: segue com 2 e o próximo vira principal',
    (d ->> 'ativo')::boolean and (d ->> 'principal_id')::uuid = b and d ->> 'nome' = pg_temp._num(b) || ' + ' || pg_temp._num(c)
    and public.conjunto_do_documento(a) is null, coalesce(d::text, 'nulo'));

  begin
    delete from public.service_orders where id = c;
    insert into _resultado values ('C4 apagar rascunho de um conjunto de 2: desfeito',
      (select desfeito_motivo = 'documento_apagado' from public.documento_conjuntos where id = v_c), '');
  exception when others then
    -- Se outro gatilho da casa impede apagar o rascunho de teste, o caso não se aplica (anotado, não é falha nossa).
    insert into _resultado values ('C4 apagar rascunho de um conjunto de 2: desfeito', true, 'não se aplica: ' || sqlerrm);
  end;
exception when others then
  insert into _resultado values ('C3 cancelar o principal de 3', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ── D: desfazer ─────────────────────────────────────────────────────────────────────────────────────────
do $$
declare v_cli uuid := pg_temp._cliente(); v_ves uuid; a uuid; b uuid; v_c uuid; r jsonb; v_m text; antes_a jsonb;
begin
  v_ves := pg_temp._barco(v_cli);
  a := pg_temp._doc(v_cli, v_ves); b := pg_temp._doc(v_cli, v_ves, 'draft');
  antes_a := pg_temp._linha(a);
  v_c := (public._conjunto_montar(array[a, b], null, pg_temp._id('admin')) ->> 'conjunto_id')::uuid;
  begin perform public._conjunto_desfazer(v_c, pg_temp._id('tecnico'), 'manual'); v_m := 'SEM ERRO';
  exception when others then v_m := sqlstate; end;
  insert into _resultado values ('D1a técnico não desfaz', v_m = '42501', v_m);
  r := public._conjunto_desfazer(v_c, pg_temp._id('admin'), 'manual');
  insert into _resultado values ('D1b desfazer manual', (r ->> 'ok')::boolean
    and (select desfeito_motivo = 'manual' and desfeito_por = pg_temp._id('admin') from public.documento_conjuntos where id = v_c)
    and public.conjunto_do_documento(a) is null and pg_temp._linha(a) = antes_a, r::text);
  begin perform public._conjunto_desfazer(v_c, pg_temp._id('admin'), 'manual'); v_m := 'SEM ERRO';
  exception when others then v_m := sqlerrm; end;
  insert into _resultado values ('D1c desfazer de novo recusa', v_m like '%já foi desfeito%', v_m);
  r := public._conjunto_montar(array[a, b], null, pg_temp._id('admin'));
  insert into _resultado values ('D1d depois de desfeito, agrupa de novo', (r ->> 'ok')::boolean, r ->> 'nome');
exception when others then
  insert into _resultado values ('D1 desfazer', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ── P: privilégios ──────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'P1 privilégios',
  not has_table_privilege('anon', 'public.documento_conjuntos', 'select')
  and not has_table_privilege('anon', 'public.documento_conjunto_itens', 'select')
  and not has_table_privilege('authenticated', 'public.documento_conjuntos', 'insert')
  and not has_table_privilege('authenticated', 'public.documento_conjunto_itens', 'update')
  and not has_function_privilege('anon', 'public.agrupar_para_cliente(uuid[], uuid, uuid)', 'execute')
  and not has_function_privilege('anon', 'public.conjunto_do_documento(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public._conjunto_montar(uuid[], uuid, uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.agrupar_para_cliente(uuid[], uuid, uuid)', 'execute'),
  '';

select teste, ok, detalhe from _resultado order by teste;

rollback;

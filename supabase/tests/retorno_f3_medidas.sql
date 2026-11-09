-- Retorno F3 (P11): retorno_previa_comparar, a view retorno_f3_medidas e o cron. Roda só pela bancada (grupo 5).
-- Termina em ROLLBACK, e o bloco se desfaz sozinho. As semanas são de 2026, antes de qualquer dado real da F3; os vessels de 2030 só
-- servem à regra de 08/12. Telefones 55479005xxxxx; frases inventadas.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f3m_caso(p_n integer, p_cliente uuid, p_aberta timestamptz,
                                            p_corpo text default 'FRASE-MARCADA-F3 preciso trocar as baterias da lancha, quanto custa?',
                                            p_papel text default 'cliente') returns uuid
language plpgsql as $f$
declare
  v_fone text := '55479005' || lpad(p_n::text, 5, '0');
  v_chave text := public._agenda_chave_telefone(v_fone);
  v_msg uuid;
  v_id uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
  values ('inbound', v_fone, 'text', p_corpo, 'received', '{"data": {}}'::jsonb, p_aberta, p_aberta)
  returning id into v_msg;
  insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, estado, modo)
  values (v_chave, v_fone, '47', p_papel, jsonb_build_object('papel', p_papel), p_cliente, v_msg, v_msg, p_aberta,
          p_aberta, p_aberta, p_aberta, 'recibo', 'recibo_cliente', 'aberta', 'sombra')
  returning id into v_id;
  insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, sinais, pede_resposta)
  values (v_msg, v_id, v_chave, p_aberta, p_aberta, md5(p_corpo), public._retorno_sinais(p_corpo), true);
  return v_id;
end $f$;

create or replace function pg_temp.f3m_chave(p_caso uuid) returns text
language sql as $f$
  select a.chave from public.retorno_aberturas a where a.id = p_caso;
$f$;

create or replace function pg_temp.f3m_cli(p_nome text, p_generico boolean default false) returns uuid
language sql as $f$
  insert into public.clients (type, name, generico) values ('individual', p_nome, p_generico) returning id;
$f$;

create or replace function pg_temp.f3m_un(p_cli uuid, p_nome text, p_em timestamptz default '2026-01-02 10:00-03') returns uuid
language sql as $f$
  insert into public.vessels (client_id, name, asset_type, created_at, updated_at) values (p_cli, p_nome, 'Lancha', p_em, p_em) returning id;
$f$;

create or replace function pg_temp.f3m_prod(p_nome text) returns uuid
language sql as $f$
  insert into public.products (name, stock_quantity, sale_price, active) values (p_nome, 0, 10, true) returning id;
$f$;

create or replace function pg_temp.f3m_orc(p_num text, p_cli uuid, p_un uuid, p_em timestamptz, p_origem text default null) returns uuid
language sql as $f$
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, grand_total, origem)
  values (p_num, p_cli, p_un, 'draft', 'draft', 'repair', p_em, p_em, 100, p_origem)
  returning id;
$f$;

create or replace function pg_temp.f3m_peca(p_os uuid, p_prod uuid, p_qtd numeric, p_preco numeric, p_em timestamptz) returns void
language sql as $f$
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot, line_total_cost, line_total_sale, created_at)
  values (p_os, p_prod, p_qtd, 1, p_preco, p_qtd, p_qtd * p_preco, p_em);
$f$;

create or replace function pg_temp.f3m_lin(p_os uuid, p_nome text, p_qtd numeric, p_preco numeric, p_em timestamptz) returns void
language sql as $f$
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (p_os, null, p_nome, 'visit', p_qtd, p_preco, p_qtd * p_preco, p_em);
$f$;

-- Linhas da foto, no formato de linhas_iniciais.
create or replace function pg_temp.f3m_lp(p_prod uuid, p_qtd numeric, p_preco numeric) returns jsonb
language sql as $f$
  select jsonb_build_object('tipo', 'peca', 'product_id', p_prod, 'service_id', null, 'nome', 'Peça', 'quantidade', p_qtd, 'preco', p_preco);
$f$;

create or replace function pg_temp.f3m_ls(p_nome text, p_qtd numeric, p_preco numeric, p_serv uuid default null) returns jsonb
language sql as $f$
  select jsonb_build_object('tipo', 'servico', 'product_id', null, 'service_id', p_serv, 'nome', p_nome, 'quantidade', p_qtd, 'preco', p_preco);
$f$;

create or replace function pg_temp.f3m_prop(p_caso uuid, p_cli uuid, p_un uuid, p_estado text, p_modo text, p_foto jsonb,
                                            p_so uuid default null, p_origem text default 'historico',
                                            p_criada timestamptz default '2026-01-05 10:00-03', p_pdf timestamptz default null, p_chave text default null) returns uuid
language sql as $f$
  insert into public.retorno_previa (abertura_id, chave, client_id, vessel_id, origem, familias, titulo, estado, modo, total, linhas_n, hash, linhas_iniciais,
                                     service_order_id, pdf_em, pdf_chave, criada_em, atualizada_em)
  select a.id, a.chave, p_cli, p_un, p_origem, array['bateria'], 'Baterias', p_estado, p_modo, 100, jsonb_array_length(p_foto), 'hash-teste', p_foto,
         p_so, p_pdf, p_chave, p_criada, p_criada
    from public.retorno_aberturas a where a.id = p_caso
  returning id;
$f$;

-- Cartão decidido com *sim <PIN>* e um item ligado à proposta. Devolve o item.
create or replace function pg_temp.f3m_item(p_caso uuid, p_previa uuid, p_estado text, p_decidido timestamptz) returns uuid
language plpgsql as $f$
declare
  v_c uuid;
  v_i uuid;
begin
  insert into public.retorno_cartoes (gatilho, dia, estado, decidido_por, decidido_em, hash, texto, criado_em, expira_em)
  values ('puxar', date '2026-03-16', 'decidido', 'sim_pin', coalesce(p_decidido, timestamptz '2026-03-16 12:00-03'), 'hash-teste', 'cartão de teste',
          timestamptz '2026-03-16 11:00-03', timestamptz '2026-03-17 11:00-03')
  returning id into v_c;
  insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, hash, estado, decidido_em, previa_id)
  values (v_c, 1, p_caso, 'orcamento', 'hash-teste', p_estado, p_decidido, p_previa)
  returning id into v_i;
  return v_i;
end $f$;

create or replace function pg_temp.f3m_evento(p_tipo text, p_payload jsonb, p_em timestamptz) returns void
language sql as $f$
  insert into public.ai_operator_audit (actor_kind, event_type, event_category, payload, created_at)
  values ('ai_model', p_tipo, 'data', p_payload, p_em);
$f$;

-- Falha fecha: a checagem junta o rótulo, o valor e o esperado.
create or replace function pg_temp.f3m_igual(p_rot text, p_valor text, p_esp text) returns void
language plpgsql as $f$
begin
  if p_valor is distinct from p_esp then
    raise exception '%: %, esperava %', p_rot, coalesce(p_valor, '∅'), coalesce(p_esp, '∅');
  end if;
end $f$;

create or replace function pg_temp.f3m_num(p_rot text, p_valor numeric, p_esp numeric) returns void
language plpgsql as $f$
begin
  if p_valor is distinct from p_esp then
    raise exception '%: %, esperava %', p_rot, coalesce(p_valor::text, '∅'), coalesce(p_esp::text, '∅');
  end if;
end $f$;

create or replace function pg_temp.f3m_cmp(p_rot text, p_r jsonb, p_iguais integer, p_alteradas integer, p_preco boolean) returns void
language plpgsql as $f$
begin
  if p_r is null then
    raise exception '%: comparar devolveu nulo', p_rot;
  end if;
  perform pg_temp.f3m_igual(p_rot || ' iguais', p_r ->> 'linhas_iguais', p_iguais::text);
  perform pg_temp.f3m_igual(p_rot || ' alteradas', p_r ->> 'linhas_alteradas', p_alteradas::text);
  perform pg_temp.f3m_igual(p_rot || ' preco_igual', p_r ->> 'preco_igual', p_preco::text);
end $f$;

do $medidas$
declare
  c_agora constant timestamptz := '2026-08-01 12:00-03';
  v_cli uuid; v_un uuid; v_un2 uuid; v_gen uuid; v_e uuid; v_v1 uuid;
  v_p1 uuid; v_p2 uuid; v_p3 uuid; v_p4 uuid; v_p5 uuid;
  v_caso uuid; v_caso2 uuid; v_id uuid; v_so uuid; v_so2 uuid; v_item uuid;
  v_r jsonb;
  v_n integer;
  v_m public.retorno_f3_medidas;
  i integer;
begin
  begin
    update public.retorno_config set previa_modo = 'desligado', previa_ditado_ligado = false;

    v_cli := pg_temp.f3m_cli('Lucas Medidas Teste');
    v_un := pg_temp.f3m_un(v_cli, 'Brisa Medidas');
    v_un2 := pg_temp.f3m_un(v_cli, 'Vento Medidas');
    v_p1 := pg_temp.f3m_prod('TF3M Bateria 200');
    v_p2 := pg_temp.f3m_prod('TF3M Cabo 50mm');
    v_p3 := pg_temp.f3m_prod('TF3M Terminal');
    v_p4 := pg_temp.f3m_prod('TF3M Disjuntor');
    v_p5 := pg_temp.f3m_prod('TF3M Inversor');

    -- ═══ 1. Proposta igual ao ORÇ: 0 alteradas.
    v_caso := pg_temp.f3m_caso(1, v_cli, '2026-01-05 09:00-03');
    v_so := pg_temp.f3m_orc('TF3M-1', v_cli, v_un, '2026-01-05 12:00-03', 'retorno_previa');
    perform pg_temp.f3m_peca(v_so, v_p1, 2, 100, '2026-01-05 12:00-03');
    perform pg_temp.f3m_lin(v_so, 'Instalação do banco', 1, 300, '2026-01-05 12:00-03');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'virou_orc', 'ligado',
                             jsonb_build_array(pg_temp.f3m_lp(v_p1, 2, 100), pg_temp.f3m_ls('Instalação do banco', 1, 300)), v_so);
    v_r := public.retorno_previa_comparar(v_id, c_agora);
    perform pg_temp.f3m_cmp('1', v_r, 2, 0, true);
    perform pg_temp.f3m_igual('1 orc_id', v_r ->> 'orc_id', v_so::text);
    perform pg_temp.f3m_igual('1 numero', v_r ->> 'numero', 'TF3M-1');
    -- Ninguém olha o futuro: um instante antes de o ORÇ nascer, não há o que comparar.
    if public.retorno_previa_comparar(v_id, '2026-01-05 11:00-03') is not null then
      raise exception '1f: comparar enxergou o futuro';
    end if;

    -- ═══ 2. Ditado que trocou 2 linhas: 2 alteradas, porque a comparação é com a foto (linhas_iniciais), não com as linhas de hoje.
    v_caso := pg_temp.f3m_caso(2, v_cli, '2026-01-06 09:00-03');
    v_so := pg_temp.f3m_orc('TF3M-2', v_cli, v_un, '2026-01-06 12:00-03', 'retorno_previa');
    perform pg_temp.f3m_peca(v_so, v_p1, 2, 100, '2026-01-06 12:00-03');
    perform pg_temp.f3m_peca(v_so, v_p4, 1, 90, '2026-01-06 12:00-03');
    perform pg_temp.f3m_peca(v_so, v_p5, 1, 80, '2026-01-06 12:00-03');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'virou_orc', 'ligado',
                             jsonb_build_array(pg_temp.f3m_lp(v_p1, 2, 100), pg_temp.f3m_lp(v_p2, 1, 50), pg_temp.f3m_lp(v_p3, 1, 60)), v_so);
    perform pg_temp.f3m_cmp('2', public.retorno_previa_comparar(v_id, c_agora), 1, 2, true);

    -- ═══ 3. Uma linha trocada por outra: 1 alterada, não 2.
    v_caso := pg_temp.f3m_caso(3, v_cli, '2026-01-07 09:00-03');
    v_so := pg_temp.f3m_orc('TF3M-3', v_cli, v_un, '2026-01-07 12:00-03', 'retorno_previa');
    perform pg_temp.f3m_peca(v_so, v_p1, 1, 100, '2026-01-07 12:00-03');
    perform pg_temp.f3m_peca(v_so, v_p3, 1, 60, '2026-01-07 12:00-03');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'virou_orc', 'ligado',
                             jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100), pg_temp.f3m_lp(v_p2, 1, 50)), v_so);
    perform pg_temp.f3m_cmp('3', public.retorno_previa_comparar(v_id, c_agora), 1, 1, true);

    -- ═══ 4. Só o preço diferente: 1 alterada e preco_igual falso. A até R$ 0,01 é igual.
    v_caso := pg_temp.f3m_caso(4, v_cli, '2026-01-08 09:00-03');
    v_so := pg_temp.f3m_orc('TF3M-4', v_cli, v_un, '2026-01-08 12:00-03', 'retorno_previa');
    perform pg_temp.f3m_peca(v_so, v_p1, 1, 110, '2026-01-08 12:00-03');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'virou_orc', 'ligado', jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100)), v_so);
    perform pg_temp.f3m_cmp('4a', public.retorno_previa_comparar(v_id, c_agora), 0, 1, false);
    v_caso := pg_temp.f3m_caso(5, v_cli, '2026-01-08 10:00-03');
    v_so := pg_temp.f3m_orc('TF3M-4B', v_cli, v_un, '2026-01-08 13:00-03', 'retorno_previa');
    perform pg_temp.f3m_peca(v_so, v_p1, 1, 100.01, '2026-01-08 13:00-03');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'virou_orc', 'ligado', jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100)), v_so);
    perform pg_temp.f3m_cmp('4b', public.retorno_previa_comparar(v_id, c_agora), 1, 0, true);

    -- ═══ 5. Linha que só sumiu: 1 alterada.
    v_caso := pg_temp.f3m_caso(6, v_cli, '2026-01-09 09:00-03');
    v_so := pg_temp.f3m_orc('TF3M-5', v_cli, v_un, '2026-01-09 12:00-03', 'retorno_previa');
    perform pg_temp.f3m_peca(v_so, v_p1, 1, 100, '2026-01-09 12:00-03');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'virou_orc', 'ligado',
                             jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100), pg_temp.f3m_lp(v_p2, 1, 50)), v_so);
    perform pg_temp.f3m_cmp('5', public.retorno_previa_comparar(v_id, c_agora), 1, 1, true);

    -- ═══ 6. Mesma chave repetida pareia pela ordem preco, quantidade.
    v_caso := pg_temp.f3m_caso(7, v_cli, '2026-01-12 09:00-03');
    v_so := pg_temp.f3m_orc('TF3M-6', v_cli, v_un, '2026-01-12 12:00-03', 'retorno_previa');
    perform pg_temp.f3m_peca(v_so, v_p1, 2, 50, '2026-01-12 12:00-03');
    perform pg_temp.f3m_peca(v_so, v_p1, 1, 100, '2026-01-12 12:00-03');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'virou_orc', 'ligado',
                             jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100), pg_temp.f3m_lp(v_p1, 2, 50)), v_so);
    perform pg_temp.f3m_cmp('6', public.retorno_previa_comparar(v_id, c_agora), 2, 0, true);

    -- ═══ 7. Serviço com service_id na foto e nulo no ORÇ, de mesmo nome (normalizado), é par.
    v_caso := pg_temp.f3m_caso(8, v_cli, '2026-01-13 09:00-03');
    v_so := pg_temp.f3m_orc('TF3M-7', v_cli, v_un, '2026-01-13 12:00-03', 'retorno_previa');
    perform pg_temp.f3m_lin(v_so, 'instalacao DO banco', 1, 300, '2026-01-13 12:00-03');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'virou_orc', 'ligado',
                             jsonb_build_array(pg_temp.f3m_ls('Instalação do banco', 1, 300, gen_random_uuid())), v_so);
    perform pg_temp.f3m_cmp('7', public.retorno_previa_comparar(v_id, c_agora), 1, 0, true);

    -- ═══ 8. Sombra sem ORÇ: nulo. ORÇ de origem retorno_previa não entra na comparação da sombra.
    v_caso := pg_temp.f3m_caso(9, v_cli, '2026-01-14 09:00-03');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'sombra', 'sombra', jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100)));
    if public.retorno_previa_comparar(v_id, c_agora) is not null then
      raise exception '8a: sombra sem ORÇ devia dar nulo';
    end if;
    v_so := pg_temp.f3m_orc('TF3M-8', v_cli, v_un, '2026-01-14 12:00-03', 'retorno_previa');
    perform pg_temp.f3m_peca(v_so, v_p1, 1, 100, '2026-01-14 12:00-03');
    if public.retorno_previa_comparar(v_id, c_agora) is not null then
      raise exception '8b: a sombra comparou com ORÇ de origem retorno_previa';
    end if;

    -- ═══ 9. Sombra com ORÇ retorno_ditado compara.
    v_so := pg_temp.f3m_orc('TF3M-9', v_cli, v_un, '2026-01-14 13:00-03', 'retorno_ditado');
    perform pg_temp.f3m_peca(v_so, v_p1, 1, 120, '2026-01-14 13:00-03');
    perform pg_temp.f3m_cmp('9', public.retorno_previa_comparar(v_id, c_agora), 0, 1, false);

    -- ═══ 10. Sombra já descartada compara (e por ORÇ sem origem).
    v_caso := pg_temp.f3m_caso(10, v_cli, '2026-01-15 09:00-03');
    v_so := pg_temp.f3m_orc('TF3M-10', v_cli, v_un, '2026-01-15 12:00-03');
    perform pg_temp.f3m_peca(v_so, v_p1, 1, 100, '2026-01-15 12:00-03');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'descartada', 'sombra', jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100)));
    perform pg_temp.f3m_cmp('10', public.retorno_previa_comparar(v_id, c_agora), 1, 0, true);

    -- ═══ 11. Sem linhas_iniciais: fora da medida.
    v_caso := pg_temp.f3m_caso(11, v_cli, '2026-01-16 09:00-03');
    v_so := pg_temp.f3m_orc('TF3M-11', v_cli, v_un, '2026-01-16 12:00-03', 'retorno_previa');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'virou_orc', 'ligado', '[]'::jsonb, v_so, 'ditado');
    if public.retorno_previa_comparar(v_id, c_agora) is not null then
      raise exception '11: sem linhas_iniciais devia dar nulo';
    end if;

    -- ═══ 12. Dois ORÇ na janela: o da mesma unidade e, dentre eles, o mais antigo. Fora da janela não conta.
    v_caso := pg_temp.f3m_caso(12, v_cli, '2026-01-19 09:00-03');
    v_so := pg_temp.f3m_orc('TF3M-12OUTRA', v_cli, v_un2, '2026-01-19 10:00-03');
    v_so2 := pg_temp.f3m_orc('TF3M-12VELHO', v_cli, v_un, '2026-01-20 10:00-03');
    v_so := pg_temp.f3m_orc('TF3M-12NOVO', v_cli, v_un, '2026-01-21 10:00-03');
    perform pg_temp.f3m_peca(v_so2, v_p1, 1, 100, '2026-01-20 10:00-03');
    perform pg_temp.f3m_peca(v_so, v_p1, 1, 999, '2026-01-21 10:00-03');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'sombra', 'sombra', jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100)));
    v_r := public.retorno_previa_comparar(v_id, c_agora);
    perform pg_temp.f3m_igual('12a escolhido', v_r ->> 'numero', 'TF3M-12VELHO');
    perform pg_temp.f3m_cmp('12a', v_r, 1, 0, true);
    -- Proposta sem unidade: o mais antigo da janela, de qualquer unidade.
    v_caso2 := pg_temp.f3m_caso(13, v_cli, '2026-01-19 08:30-03');
    v_id := pg_temp.f3m_prop(v_caso2, v_cli, null, 'sombra', 'sombra', jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100)));
    perform pg_temp.f3m_igual('12b sem unidade', public.retorno_previa_comparar(v_id, c_agora) ->> 'numero', 'TF3M-12OUTRA');
    -- ORÇ mais de 5 dias depois da abertura não é resposta a este pedido.
    v_cli := pg_temp.f3m_cli('Lucas Medidas Janela');
    v_un := pg_temp.f3m_un(v_cli, 'Brisa Janela');
    v_caso := pg_temp.f3m_caso(14, v_cli, '2026-01-26 09:00-03');
    v_so := pg_temp.f3m_orc('TF3M-12FORA', v_cli, v_un, '2026-02-01 10:00-03');
    perform pg_temp.f3m_peca(v_so, v_p1, 1, 100, '2026-02-01 10:00-03');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'sombra', 'sombra', jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100)));
    if public.retorno_previa_comparar(v_id, c_agora) is not null then
      raise exception '12c: ORÇ fora dos 5 dias não devia casar';
    end if;

    -- ═══ 13. A mediana com infinito.
    perform pg_temp.f3m_num('13a', public._retorno_mediana_com_infinito(array[1, 2, null]::numeric[]), 2);
    perform pg_temp.f3m_num('13b exatamente metade', public._retorno_mediana_com_infinito(array[1, null]::numeric[]), 1);
    if public._retorno_mediana_com_infinito(array[1, null, null]::numeric[]) is not null then
      raise exception '13c: mais da metade sem valor devia dar nulo';
    end if;
    if public._retorno_mediana_com_infinito('{}'::numeric[]) is not null then
      raise exception '13d: vazio devia dar nulo';
    end if;
    perform pg_temp.f3m_num('13e par', public._retorno_mediana_com_infinito(array[1, 3, 5, 7]::numeric[]), 4);

    -- ═══ 14 a 26: a view é lida uma vez só, depois de todos os fixtures (cada leitura chama _retorno_intencao_do_caso por caso, e a bancada tem teto de 95 s).
    -- ═══ 14. Semana cheia (02/02/26): cada medida com dado sintético, e cada portão em zero.
    v_cli := pg_temp.f3m_cli('Ana Medidas Semana');
    v_un := pg_temp.f3m_un(v_cli, 'Brisa Semana');
    -- Pedido com proposta ligada que virou ORÇ igual à foto, PDF no mesmo dia e o ato do cartão.
    v_caso := pg_temp.f3m_caso(20, v_cli, '2026-02-02 09:00-03');
    v_so := pg_temp.f3m_orc('TF3M-20', v_cli, v_un, '2026-02-02 11:00-03', 'retorno_previa');
    perform pg_temp.f3m_peca(v_so, v_p1, 1, 100, '2026-02-02 11:00-03');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'virou_orc', 'ligado', jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100)), v_so, 'historico',
                             '2026-02-02 10:00-03', '2026-02-02 11:30-03', pg_temp.f3m_chave(v_caso));
    perform pg_temp.f3m_item(v_caso, v_id, 'feito', '2026-02-02 11:00-03');
    -- Pedido com proposta em sombra: a primeira descartada (13h) e a viva (14h). Conta uma vez e usa a primeira.
    v_caso := pg_temp.f3m_caso(21, v_cli, '2026-02-03 09:00-03');
    perform pg_temp.f3m_prop(v_caso, v_cli, v_un, 'descartada', 'sombra', jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100)), null, 'historico', '2026-02-03 13:00-03');
    perform pg_temp.f3m_prop(v_caso, v_cli, v_un, 'sombra', 'sombra', jsonb_build_array(pg_temp.f3m_lp(v_p2, 1, 100)), null, 'historico', '2026-02-03 14:00-03');
    -- Pedido sem proposta: infinito nas duas medianas.
    v_caso := pg_temp.f3m_caso(22, v_cli, '2026-02-04 09:00-03');
    -- Caso sem pedido de orçamento: não conta.
    v_caso := pg_temp.f3m_caso(23, v_cli, '2026-02-05 09:00-03', 'oi, tudo bem por ai?');

    -- ═══ 15. Mediana de PDF e o corte por linhas alteradas (09/02/26): [0, 1, infinito] dá 1 dia útil.
    v_cli := pg_temp.f3m_cli('Bia Medidas Semana');
    v_un := pg_temp.f3m_un(v_cli, 'Brisa Semana 2');
    v_caso := pg_temp.f3m_caso(30, v_cli, '2026-02-09 09:00-03');
    v_so := pg_temp.f3m_orc('TF3M-30', v_cli, v_un, '2026-02-09 11:00-03', 'retorno_previa');
    perform pg_temp.f3m_peca(v_so, v_p1, 1, 100, '2026-02-09 11:00-03');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'virou_orc', 'ligado', jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100)), v_so, 'historico',
                             '2026-02-09 10:00-03', '2026-02-09 11:30-03', pg_temp.f3m_chave(v_caso));
    perform pg_temp.f3m_item(v_caso, v_id, 'feito', '2026-02-09 11:00-03');
    -- Duas linhas alteradas: mostrada, com PDF, mas fora do "até 1 linha".
    v_caso := pg_temp.f3m_caso(31, v_cli, '2026-02-10 09:00-03');
    v_so := pg_temp.f3m_orc('TF3M-31', v_cli, v_un, '2026-02-11 09:00-03', 'retorno_previa');
    perform pg_temp.f3m_peca(v_so, v_p4, 1, 100, '2026-02-11 09:00-03');
    perform pg_temp.f3m_peca(v_so, v_p5, 1, 100, '2026-02-11 09:00-03');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'virou_orc', 'ligado',
                             jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100), pg_temp.f3m_lp(v_p2, 1, 100)), v_so, 'historico',
                             '2026-02-10 10:00-03', '2026-02-11 09:30-03', pg_temp.f3m_chave(v_caso));
    perform pg_temp.f3m_item(v_caso, v_id, 'feito', '2026-02-11 09:00-03');
    v_caso := pg_temp.f3m_caso(32, v_cli, '2026-02-11 09:00-03');   -- pedido sem proposta nem PDF

    -- ═══ 16. O percentual só aparece com 20 mostradas ou mais (04/05/26): 15 de 20 viraram PDF.
    v_cli := pg_temp.f3m_cli('Caio Medidas Vinte');
    v_un := pg_temp.f3m_un(v_cli, 'Brisa Vinte');
    for i in select g from generate_series(1, 20) g loop
      v_caso := pg_temp.f3m_caso(100 + i, v_cli, '2026-05-04 09:00-03');
      v_so := pg_temp.f3m_orc('TF3M-V' || i, v_cli, v_un, '2026-05-04 10:00-03', 'retorno_previa');
      perform pg_temp.f3m_peca(v_so, v_p1, 1, 100, '2026-05-04 10:00-03');
      v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'virou_orc', 'ligado', jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100)), v_so, 'historico',
                               '2026-05-04 09:30-03', case when i <= 15 then timestamptz '2026-05-04 11:00-03' end,
                               case when i <= 15 then pg_temp.f3m_chave(v_caso) end);
      perform pg_temp.f3m_item(v_caso, v_id, 'feito', '2026-05-04 10:00-03');
    end loop;

    -- ═══ 17. orc_sem_ato e escolha_por_nome (02/03/26): ORÇ com origem sem ato, evento amarrado sem aprovação, e o que não conta.
    v_cli := pg_temp.f3m_cli('Dani Medidas Ato');
    v_un := pg_temp.f3m_un(v_cli, 'Brisa Ato');
    v_so := pg_temp.f3m_orc('TF3M-40', v_cli, v_un, '2026-03-03 10:00-03', 'retorno_previa');
    perform pg_temp.f3m_evento('tool:create_quote_from_items', '{"sessao_amarrada": true, "args": {"items": []}}', '2026-03-03 10:00-03');
    perform pg_temp.f3m_evento('tool:create_quote_from_items', '{"sessao_amarrada": true, "args": {"client_name": "Fulano"}}', '2026-03-03 10:01-03');
    -- Não contam: com erro, barrada antes de executar, e sem sessão amarrada.
    perform pg_temp.f3m_evento('tool:create_quote_from_items', '{"sessao_amarrada": true, "args": {"client_name": "Fulano"}, "erro": "recusado"}', '2026-03-03 10:02-03');
    perform pg_temp.f3m_evento('pre_validacao_recusada:create_quote_from_items', '{"sessao_amarrada": true, "args": {"vessel_name": "Brisa"}}', '2026-03-03 10:03-03');
    perform pg_temp.f3m_evento('tool:create_quote_from_items', '{"args": {"client_name": "Livre"}}', '2026-03-03 10:04-03');

    -- ═══ 18. Aprovação do ditado (09/03/26): retrato do próprio caso é ato; retrato de outro caso não.
    v_cli := pg_temp.f3m_cli('Edu Medidas Retrato');
    v_un := pg_temp.f3m_un(v_cli, 'Brisa Retrato');
    v_caso := pg_temp.f3m_caso(50, v_cli, '2026-03-09 09:00-03');
    v_so := pg_temp.f3m_orc('TF3M-50', v_cli, v_un, '2026-03-10 10:00-03', 'retorno_ditado');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'virou_orc', 'ligado', '[]'::jsonb, v_so, 'ditado', '2026-03-10 09:30-03');
    perform pg_temp.f3m_evento('approve_execute:retorno_orcar_caso',
                               jsonb_build_object('args', jsonb_build_object('_retrato', jsonb_build_object('abertura_id', v_caso))), '2026-03-10 10:00-03');
    v_caso2 := pg_temp.f3m_caso(51, v_cli, '2026-03-09 09:30-03');
    v_so := pg_temp.f3m_orc('TF3M-51', v_cli, v_un, '2026-03-10 11:00-03', 'retorno_ditado');
    v_id := pg_temp.f3m_prop(v_caso2, v_cli, v_un, 'virou_orc', 'ligado', '[]'::jsonb, v_so, 'ditado', '2026-03-10 09:40-03');

    -- ═══ 19. Cartão com PIN (16/03/26): PDF falhou e o item foi a 'fora' por retorno_previa_soltar: conta como ato. Item 'fora' sem decidido_em, não.
    v_cli := pg_temp.f3m_cli('Fabi Medidas Cartao');
    v_un := pg_temp.f3m_un(v_cli, 'Brisa Cartao');
    v_caso := pg_temp.f3m_caso(52, v_cli, '2026-03-16 09:00-03');
    v_so := pg_temp.f3m_orc('TF3M-52', v_cli, v_un, '2026-03-16 12:00-03', 'retorno_previa');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'virou_orc', 'ligado', '[]'::jsonb, v_so);
    v_item := pg_temp.f3m_item(v_caso, v_id, 'feito', '2026-03-16 12:00-03');
    perform public.retorno_previa_soltar(v_item, '2026-03-16 12:05-03');
    perform pg_temp.f3m_igual('19a item fora', (select i.estado from public.retorno_cartao_itens i where i.id = v_item), 'fora');
    v_caso := pg_temp.f3m_caso(53, v_cli, '2026-03-16 09:30-03');
    v_so := pg_temp.f3m_orc('TF3M-53', v_cli, v_un, '2026-03-17 12:00-03', 'retorno_previa');
    v_id := pg_temp.f3m_prop(v_caso, v_cli, v_un, 'virou_orc', 'ligado', '[]'::jsonb, v_so);
    perform pg_temp.f3m_item(v_caso, v_id, 'fora', null);

    -- ═══ 20. orc_duplicado e Cliente Final (23/03/26). O 2º ORÇ em 12 h conta; outra unidade e 12 h depois, não.
    v_cli := pg_temp.f3m_cli('Gabi Medidas Duplo');
    v_un := pg_temp.f3m_un(v_cli, 'Brisa Duplo');
    v_un2 := pg_temp.f3m_un(v_cli, 'Vento Duplo');
    perform pg_temp.f3m_orc('TF3M-60', v_cli, v_un, '2026-03-24 10:00-03', 'retorno_previa');
    perform pg_temp.f3m_orc('TF3M-61', v_cli, v_un, '2026-03-24 18:00-03', 'retorno_ditado');
    perform pg_temp.f3m_orc('TF3M-62', v_cli, v_un2, '2026-03-24 18:00-03', 'retorno_previa');
    perform pg_temp.f3m_orc('TF3M-63', v_cli, v_un, '2026-03-26 12:00-03', 'retorno_previa');
    v_gen := pg_temp.f3m_cli('Cliente Final Medidas', true);
    v_un2 := pg_temp.f3m_un(v_gen, 'Balcão Medidas');
    perform pg_temp.f3m_orc('TF3M-64', v_gen, v_un2, '2026-03-25 10:00-03', 'retorno_previa');

    -- ═══ 21. proposta_cliente_final conta sombra; pdf_fora_do_contato conta destino diferente da chave (06/04/26).
    v_caso := pg_temp.f3m_caso(60, v_gen, '2026-04-06 09:00-03');
    perform pg_temp.f3m_prop(v_caso, v_gen, null, 'sombra', 'sombra', jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100)), null, 'historico', '2026-04-06 10:00-03');
    v_cli := pg_temp.f3m_cli('Helo Medidas Contato');
    v_un := pg_temp.f3m_un(v_cli, 'Brisa Contato');
    v_caso := pg_temp.f3m_caso(61, v_cli, '2026-04-06 09:30-03');
    v_so := pg_temp.f3m_orc('TF3M-70', v_cli, v_un, '2026-04-07 10:00-03', 'retorno_previa');
    perform pg_temp.f3m_prop(v_caso, v_cli, v_un, 'virou_orc', 'ligado', '[]'::jsonb, v_so, 'historico', '2026-04-07 09:30-03', '2026-04-07 10:30-03', '00000000');
    v_caso2 := pg_temp.f3m_caso(62, v_cli, '2026-04-06 09:40-03');
    v_so := pg_temp.f3m_orc('TF3M-71', v_cli, v_un, '2026-04-07 11:00-03', 'retorno_previa');
    perform pg_temp.f3m_prop(v_caso2, v_cli, v_un, 'virou_orc', 'ligado', '[]'::jsonb, v_so, 'historico', '2026-04-07 09:40-03', '2026-04-07 11:30-03', pg_temp.f3m_chave(v_caso2));

    -- ═══ 22. Semana sem caso: o evento de escolha_por_nome tem linha própria (11/05/26).
    perform pg_temp.f3m_evento('tool:create_quote_from_items', '{"sessao_amarrada": true, "args": {"vessel_name": "Brisa"}}', '2026-05-12 10:00-03');

    -- ═══ 23. Domingo à noite e a segunda seguinte caem em semanas diferentes (fuso de Brasília).
    v_cli := pg_temp.f3m_cli('Igor Medidas Domingo');
    perform pg_temp.f3m_caso(70, v_cli, '2026-04-19 23:00-03');
    perform pg_temp.f3m_caso(71, v_cli, '2026-04-20 08:00-03');

    -- ═══ 24. Pedido sem proposta entra na mediana como infinito: [2 h, infinito] é exatamente metade (27/04/26); 1 com proposta e 2 sem dá nulo (25/05/26).
    v_cli := pg_temp.f3m_cli('Juca Medidas Infinito');
    v_un := pg_temp.f3m_un(v_cli, 'Brisa Infinito');
    v_caso := pg_temp.f3m_caso(72, v_cli, '2026-04-27 09:00-03');
    perform pg_temp.f3m_prop(v_caso, v_cli, v_un, 'sombra', 'sombra', jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100)), null, 'historico', '2026-04-27 11:00-03');
    perform pg_temp.f3m_caso(73, v_cli, '2026-04-27 10:00-03');
    v_caso := pg_temp.f3m_caso(78, v_cli, '2026-05-25 09:00-03');
    perform pg_temp.f3m_prop(v_caso, v_cli, v_un, 'sombra', 'sombra', jsonb_build_array(pg_temp.f3m_lp(v_p1, 1, 100)), null, 'historico', '2026-05-25 11:00-03');
    perform pg_temp.f3m_caso(79, v_cli, '2026-05-25 10:00-03');
    perform pg_temp.f3m_caso(80, v_cli, '2026-05-25 10:30-03');

    -- ═══ 25. visita_sem_data (18/05/26): marca há mais de 5 dias úteis e caso aberto; caso fechado e marca recente não contam.
    v_cli := pg_temp.f3m_cli('Kaio Medidas Visita');
    v_caso := pg_temp.f3m_caso(75, v_cli, '2026-05-18 09:00-03');
    update public.retorno_aberturas a set visita_a_combinar_em = '2026-05-19 10:00-03' where a.id = v_caso;
    v_caso := pg_temp.f3m_caso(76, v_cli, '2026-05-19 09:00-03');
    update public.retorno_aberturas a set visita_a_combinar_em = '2026-05-20 10:00-03', estado = 'fechada', fechada_em = '2026-05-21 10:00-03', fechada_motivo = 'conteudo' where a.id = v_caso;
    v_caso := pg_temp.f3m_caso(77, v_cli, '2026-05-20 09:00-03');
    update public.retorno_aberturas a set visita_a_combinar_em = now() - interval '1 hour' where a.id = v_caso;

    -- ═══ 26. cadastro_duplicado: só vessel de 08/12 em diante; o de antes não conta, mesmo com nome repetido.
    v_e := pg_temp.f3m_cli('Lia Medidas Unidade');
    v_v1 := pg_temp.f3m_un(v_e, 'Aurora', '2026-03-30 10:00-03');
    perform pg_temp.f3m_un(v_e, 'AURORA ', '2026-03-31 10:00-03');
    perform pg_temp.f3m_un(v_e, 'áurora', '2030-03-05 10:00-03');
    perform pg_temp.f3m_un(v_e, 'Outra', '2030-03-12 10:00-03');

    -- A leitura única da view.
    create temp table _f3m_v on commit drop as select * from public.retorno_f3_medidas;

    select * into v_m from _f3m_v m where m.semana = date '2026-02-02';
    if not found then
      raise exception '14: a semana cheia não apareceu';
    end if;
    perform pg_temp.f3m_igual('14 pedidos', v_m.pedidos::text, '3');
    perform pg_temp.f3m_igual('14 com_proposta', v_m.com_proposta::text, '2');
    -- [1 h, 4 h, infinito]: a mediana é 4 h. Com a segunda proposta seria 5 h.
    perform pg_temp.f3m_igual('14 mediana h', v_m.pedido_proposta_mediana_h::text, '4.00');
    -- 2 dos 3 pedidos sem PDF: nula.
    perform pg_temp.f3m_igual('14 mediana du', v_m.pedido_pdf_mediana_du::text, null);
    perform pg_temp.f3m_igual('14 mostradas', v_m.propostas_mostradas::text, '1');
    perform pg_temp.f3m_igual('14 viraram', v_m.viraram_pdf_ate_1_linha::text, '1');
    perform pg_temp.f3m_igual('14 pct com menos de 20', v_m.viraram_pdf_ate_1_linha_pct::text, null);
    perform pg_temp.f3m_igual('14 orc_sem_ato', v_m.orc_sem_ato::text, '0');
    perform pg_temp.f3m_igual('14 orc_duplicado', v_m.orc_duplicado::text, '0');
    perform pg_temp.f3m_igual('14 cadastro_duplicado', v_m.cadastro_duplicado::text, '0');
    perform pg_temp.f3m_igual('14 escolha_por_nome', v_m.escolha_por_nome::text, '0');
    perform pg_temp.f3m_igual('14 orc_numero_novo_cliente_final', v_m.orc_numero_novo_cliente_final::text, '0');
    perform pg_temp.f3m_igual('14 proposta_cliente_final', v_m.proposta_cliente_final::text, '0');
    perform pg_temp.f3m_igual('14 pdf_fora_do_contato', v_m.pdf_fora_do_contato::text, '0');
    perform pg_temp.f3m_igual('14 visita_sem_data', v_m.visita_sem_data::text, '0');

    select * into v_m from _f3m_v m where m.semana = date '2026-02-09';
    perform pg_temp.f3m_igual('15 mediana du', v_m.pedido_pdf_mediana_du::text, '1.00');
    perform pg_temp.f3m_igual('15 mostradas', v_m.propostas_mostradas::text, '2');
    perform pg_temp.f3m_igual('15 viraram', v_m.viraram_pdf_ate_1_linha::text, '1');

    select * into v_m from _f3m_v m where m.semana = date '2026-05-04';
    perform pg_temp.f3m_igual('16 mostradas', v_m.propostas_mostradas::text, '20');
    perform pg_temp.f3m_igual('16 viraram', v_m.viraram_pdf_ate_1_linha::text, '15');
    perform pg_temp.f3m_igual('16 pct', v_m.viraram_pdf_ate_1_linha_pct::text, '75.0');

    select * into v_m from _f3m_v m where m.semana = date '2026-03-02';
    perform pg_temp.f3m_igual('17 orc_sem_ato', v_m.orc_sem_ato::text, '3');
    perform pg_temp.f3m_igual('17 escolha_por_nome', v_m.escolha_por_nome::text, '1');

    perform pg_temp.f3m_igual('18 orc_sem_ato', (select m.orc_sem_ato::text from _f3m_v m where m.semana = date '2026-03-09'), '1');
    perform pg_temp.f3m_igual('19b orc_sem_ato', (select m.orc_sem_ato::text from _f3m_v m where m.semana = date '2026-03-16'), '1');

    select * into v_m from _f3m_v m where m.semana = date '2026-03-23';
    perform pg_temp.f3m_igual('20 orc_duplicado', v_m.orc_duplicado::text, '1');
    perform pg_temp.f3m_igual('20 orc_numero_novo_cliente_final', v_m.orc_numero_novo_cliente_final::text, '1');

    select * into v_m from _f3m_v m where m.semana = date '2026-04-06';
    perform pg_temp.f3m_igual('21 proposta_cliente_final', v_m.proposta_cliente_final::text, '1');
    perform pg_temp.f3m_igual('21 pdf_fora_do_contato', v_m.pdf_fora_do_contato::text, '1');

    select * into v_m from _f3m_v m where m.semana = date '2026-05-11';
    if not found then
      raise exception '22: a semana só de evento não apareceu';
    end if;
    perform pg_temp.f3m_igual('22 escolha_por_nome', v_m.escolha_por_nome::text, '1');
    perform pg_temp.f3m_igual('22 pedidos', v_m.pedidos::text, '0');

    perform pg_temp.f3m_igual('23 domingo', (select m.pedidos::text from _f3m_v m where m.semana = date '2026-04-13'), '1');
    perform pg_temp.f3m_igual('23 segunda', (select m.pedidos::text from _f3m_v m where m.semana = date '2026-04-20'), '1');

    perform pg_temp.f3m_igual('24a metade', (select m.pedido_proposta_mediana_h::text from _f3m_v m where m.semana = date '2026-04-27'), '2.00');
    perform pg_temp.f3m_igual('24b mais da metade', (select m.pedido_proposta_mediana_h::text from _f3m_v m where m.semana = date '2026-05-25'), null);

    perform pg_temp.f3m_igual('25', (select m.visita_sem_data::text from _f3m_v m where m.semana = date '2026-05-18'), '1');

    if coalesce((select sum(m.cadastro_duplicado) from _f3m_v m where m.semana between date '2026-03-30' and date '2026-04-05'), 0) <> 0 then
      raise exception '26a: vessel de antes de 08/12 entrou em cadastro_duplicado';
    end if;
    perform pg_temp.f3m_igual('26b duplicado', (select m.cadastro_duplicado::text from _f3m_v m where m.semana = date '2030-03-04'), '1');
    perform pg_temp.f3m_igual('26c sem duplicado', (select m.cadastro_duplicado::text from _f3m_v m where m.semana = date '2030-03-11'), '0');

    -- ═══ 27. O cron e o modo desligado: a chamada não muda nada.
    if not exists (select 1 from cron.job j where j.jobname = 'retorno-previa' and j.schedule = '*/5 10-23 * * 1-6' and j.command like '%retorno_previa_rodada%') then
      raise exception '27a: o cron retorno-previa não está com o nome e a agenda certos';
    end if;
    select count(*) into v_n from public.retorno_previa;
    v_r := public.retorno_previa_rodada(now());
    perform pg_temp.f3m_igual('27b casos', v_r ->> 'casos', '0');
    perform pg_temp.f3m_igual('27c criadas', v_r ->> 'criadas', '0');
    perform pg_temp.f3m_igual('27d propostas iguais', (select count(*)::text from public.retorno_previa), v_n::text);

    -- ═══ 28. Fechado ao anônimo e ao painel: só o service_role lê.
    if has_table_privilege('anon', 'public.retorno_f3_medidas', 'select') or has_table_privilege('authenticated', 'public.retorno_f3_medidas', 'select') then
      raise exception '28a: a view está aberta';
    end if;
    if not has_table_privilege('service_role', 'public.retorno_f3_medidas', 'select') then
      raise exception '28b: service_role sem leitura';
    end if;
    if not has_function_privilege('service_role', 'public.retorno_previa_comparar(uuid, timestamptz)', 'execute') then
      raise exception '28c: service_role sem comparar';
    end if;

    raise exception 'retorno_f3_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f3_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f3_medidas', true, '{}');
end
$medidas$;

select arquivo, ok, numeros from _bancada order by em;
rollback;

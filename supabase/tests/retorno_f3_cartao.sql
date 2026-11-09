-- Retorno F3 (P5): a proposta no cartão. Gerado por script (scripts/gerar_f3.cjs teste-cartao) a partir de scripts/f3_sql/teste_cartao.sql:
-- as cópias da F2 no início são o corpo de 20261123100400 antes das migrations da F3 (o teste de regressão byte a byte). Roda só pela
-- bancada (grupo 5). Termina em ROLLBACK, e o bloco se desfaz sozinho. Relógio em ter 10/11/2026 15:00. Telefones 55479008xxxxx; frases inventadas.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- As cópias de antes da F3, com o nome pg_temp.f2_*. Não são chamadas em produção.

create or replace function pg_temp.f2_item_montar(p_abertura uuid, p_n smallint, p_agora timestamptz)
returns jsonb
language plpgsql
stable
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_letras constant text[] := array['A', 'B', 'C', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'P', 'Q', 'R', 'T', 'U'];
  v_ab public.retorno_aberturas;
  v_rotulo text;
  v_fatos jsonb;
  v_os jsonb;
  v_f jsonb;
  v_m jsonb;
  v_nivel text;
  v_int text;
  v_tipo text;
  v_modelo text;
  v_texto text;
  v_opcoes jsonb := '[]'::jsonb;
  v_frases text[] := '{}';
  v_fato_txt text;
  v_linhas jsonb;
  v_k integer;
  v_clientes uuid[];
  v_c uuid;
  v_i integer := 0;
  v_numero text;
  v_retrato jsonb := '{}'::jsonb;
  v_prov uuid;
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  v_rotulo := public._retorno_rotulo(p_abertura, p_agora);
  v_k := public._retorno_automaticas_hoje(v_ab.chave, p_agora);
  v_int := public._retorno_intencao_do_caso(p_abertura, p_agora);

  begin
    if v_ab.papel = 'cliente' then
      v_fatos := public.retorno_fatos_do_contato(v_ab.phone_normalized, p_agora);
    end if;
  exception when others then
    v_fatos := null;   -- sem fato, nunca "não há peça"
  end;
  if v_fatos is not null and jsonb_array_length(v_fatos -> 'os') = 1 then
    v_os := v_fatos -> 'os' -> 0;
    v_f := v_os -> 'fatos';
    v_numero := v_os ->> 'numero';
  end if;

  v_m := public._retorno_modelo_do_caso(p_abertura, p_agora);
  if v_m ->> 'modelo' is not null then
    select t.nivel into v_nivel from public.retorno_modelo_tipos t where t.tipo = v_m ->> 'modelo';
  end if;

  if v_ab.papel = 'cliente_ambiguo' then
    v_tipo := 'ambiguo';
    v_clientes := case when cardinality(v_ab.clientes) > 0 then v_ab.clientes
                       else array(select (e)::uuid from jsonb_array_elements_text(coalesce(v_ab.quem -> 'clientes', '[]'::jsonb)) e) end;
    foreach v_c in array v_clientes loop
      v_i := v_i + 1;
      exit when v_i > cardinality(c_letras);
      v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object(
        'letra', c_letras[v_i], 'acao', 'cliente', 'client_id', v_c, 'rotulo', coalesce(public._retorno_nome(v_c), 'sem nome')));
      v_frases := v_frases || format('*%s %s* = %s', p_n, c_letras[v_i], coalesce(public._retorno_nome(v_c), 'sem nome'));
    end loop;
  elsif v_ab.papel = 'numero_novo' then
    v_tipo := 'numero_novo';
    select a.record_id into v_prov
      from public.audit_log a
     where a.table_name = 'clients' and a.new_value ->> 'caso' = p_abertura::text
     limit 1;
    if v_prov is not null then
      v_opcoes := jsonb_build_array(jsonb_build_object('letra', 'D', 'acao', 'desfaz_cadastro', 'client_id', v_prov, 'rotulo', 'desfaz o cadastro'));
      v_frases := array[format('*%s D* = desfaz o cadastro', p_n)];
    end if;
  elsif v_m ->> 'modelo' is not null and v_nivel in ('cartao', 'sozinho') then
    v_tipo := 'modelo';
    v_modelo := v_m ->> 'modelo';
    v_texto := public._retorno_texto_do_modelo(p_abertura, v_m, null, p_agora);
    v_retrato := jsonb_build_object('fato', v_m -> 'fato', 'intencao', v_m ->> 'intencao');
    if v_modelo = 'modelo_aguarda_peca' then
      v_opcoes := jsonb_build_array(
        jsonb_build_object('letra', 'B', 'acao', 'chegou', 'os', v_numero, 'rotulo', 'a peça chegou'),
        jsonb_build_object('letra', 'C', 'acao', 'previsao', 'os', v_numero, 'rotulo', 'dite a previsão'));
      v_frases := array[format('*%s B* = %s', p_n, case when jsonb_array_length(v_f -> 'aguarda_peca' -> 'linhas') > 1 then 'chegou tudo' else 'a peça chegou' end),
                        format('*%s C* = dite a previsão', p_n)];
    end if;
  elsif (v_f is not null and v_f -> 'aguarda_peca' <> 'null'::jsonb)
        or (v_int = 'peca' and (v_f is null or v_f -> 'peca_chegou' = 'null'::jsonb)) then
    v_tipo := 'peca_sem_registro';
    if v_numero is not null then
      v_opcoes := jsonb_build_array(
        jsonb_build_object('letra', 'B', 'acao', 'chegou', 'os', v_numero, 'rotulo', 'a peça chegou'),
        jsonb_build_object('letra', 'C', 'acao', 'previsao', 'os', v_numero, 'rotulo', 'dite a previsão'));
      v_frases := array[format('*%s B* = %s', p_n,
                               case when v_f is not null and v_f -> 'aguarda_peca' <> 'null'::jsonb
                                         and jsonb_array_length(v_f -> 'aguarda_peca' -> 'linhas') > 1
                                    then 'chegou tudo' else 'a peça chegou' end),
                        format('*%s C* = dite a previsão', p_n)];
    end if;
  elsif v_f is not null and v_f -> 'concluida_sem_palavra' <> 'null'::jsonb then
    v_tipo := 'pronto_sem_palavra';
  elsif v_int = 'retirada' then
    v_tipo := 'retirada';
    v_opcoes := jsonb_build_array(
      jsonb_build_object('letra', 'A', 'acao', 'responder', 'modelo', 'modelo_liberado', 'marca_liberado', true, 'rotulo', 'pode retirar', 'os_id', v_os ->> 'id'),
      jsonb_build_object('letra', 'B', 'acao', 'responder', 'modelo', 'modelo_retirada_nao', 'rotulo', 'ainda não dá', 'os_id', v_os ->> 'id'));
    v_frases := array[format('*%s A* = pode retirar', p_n), format('*%s B* = ainda não dá', p_n)];
  elsif v_int = 'orcamento' then
    v_tipo := 'orcamento';
  elsif v_int = 'adicional' then
    v_tipo := 'adicional';
  else
    v_tipo := 'livre';
  end if;

  v_linhas := jsonb_build_array(format('%s. %s%s%s · %s · %s · %s', p_n, v_rotulo,
    case when v_numero is not null then ' · ' || v_numero else '' end,
    case when v_os ->> 'bem' is not null then ' · ' || (v_os ->> 'bem') else '' end,
    to_char(v_ab.aberta_em at time zone c_fuso, 'HH24:MI'),
    public._retorno_prazo_curto(p_abertura, p_agora),
    public._retorno_pedido_do_caso(p_abertura, p_agora)));

  v_fato_txt := public._retorno_fato_texto(v_f, v_tipo = 'retirada', (v_os ->> 'id')::uuid, v_rotulo, p_agora);
  if v_fato_txt is not null then
    v_linhas := v_linhas || jsonb_build_array('   O que sei: ' || v_fato_txt);
  end if;
  if v_modelo is not null then
    v_linhas := v_linhas || jsonb_build_array(format('   Modelo: ''%s''', v_texto));
  end if;
  if cardinality(v_frases) > 0 then
    v_linhas := v_linhas || jsonb_build_array('   ' || array_to_string(v_frases, ' · '));
  end if;
  if v_k >= 1 then
    v_linhas := v_linhas || jsonb_build_array(format('   Ele já recebeu %s automáticas hoje.', v_k));
  end if;

  return jsonb_build_object(
    'tipo_item', v_tipo, 'modelo_tipo', v_modelo, 'service_order_id', v_os ->> 'id', 'texto_mostrado', v_texto,
    'opcoes', v_opcoes, 'fatos', v_retrato, 'linhas', v_linhas,
    'hash', md5(concat_ws('|', v_ab.phone_normalized, v_modelo, v_texto, v_retrato::text, v_k)));
end;
$$;

create or replace function pg_temp.f2_cartao_texto(p_cartao uuid, p_cabeca text)
returns text
language plpgsql
stable
as $$
declare
  v_c public.retorno_cartoes;
  v_vivos integer;
  v_cabeca text;
  v_corpo text;
  v_primeiro smallint;
  v_mandam smallint[];
  v_faz text;
  v_rodape text;
  v_max boolean;
begin
  select * into v_c from public.retorno_cartoes c where c.id = p_cartao;
  select count(*), min(i.n) into v_vivos, v_primeiro
    from public.retorno_cartao_itens i where i.cartao_id = p_cartao and i.estado = 'vivo';

  v_cabeca := coalesce(p_cabeca, case when v_c.gatilho = 'meio_dia' then format('Retorno · meio-dia · %s esperando', v_vivos + v_c.mais)
                                      else format('Retorno · %s esperando', v_vivos + v_c.mais) end);

  select string_agg(l.linha, E'\n' order by i.n, l.ord)
    into v_corpo
    from public.retorno_cartao_itens i
    cross join lateral jsonb_array_elements_text(coalesce(v_c.dados -> 'linhas' -> i.n::text, '[]'::jsonb))
         with ordinality as l(linha, ord)
   where i.cartao_id = p_cartao and i.estado = 'vivo';

  if v_c.estado = 'vivo' then
    select array_agg(i.n order by i.n) into v_mandam
      from public.retorno_cartao_itens i
     where i.cartao_id = p_cartao and i.estado = 'vivo' and (i.modelo_tipo is not null or i.texto_ditado is not null);
    if cardinality(v_mandam) > 0 then
      v_faz := case when cardinality(v_mandam) = 1 then format('o %s', v_mandam[1])
                    when cardinality(v_mandam) = 2 then format('o %s e o %s', v_mandam[1], v_mandam[2])
                    else 'os 3' end;
      v_rodape := format('*sim <PIN>* faz %s · *só %s* · *ver %s* · *não* · ou dite por áudio', v_faz, v_mandam[1], v_primeiro);
    else
      v_rodape := format('*ver %1$s* · *dita %1$s …* · *não* · ou dite por áudio', v_primeiro);
    end if;
    begin
      v_max := public.ai_claude_max_disponivel();
      if v_max is false then
        v_rodape := v_rodape || E'\n' || '(Seu assistente está fora: responda com as letras ou pelo celular.)';
      end if;
    exception when others then
      null;   -- erro ao ler: a linha não aparece
    end;
  else
    v_rodape := v_c.dados ->> 'rodape';
  end if;

  return concat_ws(E'\n', v_cabeca, v_corpo,
                   case when v_c.mais > 0 then format('e mais %s: *retorno*', v_c.mais) end,
                   v_rodape);
end;
$$;

create or replace function pg_temp.f3c_caso(p_n integer, p_papel text, p_cliente uuid,
                                            p_corpo text default 'preciso trocar as baterias da lancha, quanto custa?',
                                            p_aberta timestamptz default '2026-11-10 13:00-03') returns uuid
language plpgsql as $f$
declare
  v_fone text := '55479008' || lpad(p_n::text, 5, '0');
  v_chave text := public._agenda_chave_telefone(v_fone);
  v_msg uuid;
  v_id uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
  values ('inbound', v_fone, 'text', p_corpo, 'received', '{"data": {}}'::jsonb, p_aberta, p_aberta)
  returning id into v_msg;
  insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, clientes, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, estado, modo)
  values (v_chave, v_fone, '47', p_papel, jsonb_build_object('papel', p_papel), p_cliente, '{}', v_msg, v_msg, p_aberta,
          p_aberta, p_aberta, p_aberta, 'recibo', 'recibo_cliente', 'aberta', 'sombra')
  returning id into v_id;
  insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, sinais, pede_resposta)
  values (v_msg, v_id, v_chave, p_aberta, p_aberta, md5(p_corpo), public._retorno_sinais(p_corpo), true);
  return v_id;
end $f$;

create or replace function pg_temp.f3c_cli(p_nome text, p_n integer default null) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, case when p_n is not null then '(47) 90080-' || lpad(p_n::text, 4, '0') end) returning id;
$f$;

create or replace function pg_temp.f3c_un(p_cli uuid, p_nome text, p_tipo text default 'Lancha') returns uuid
language sql as $f$
  insert into public.vessels (client_id, name, asset_type) values (p_cli, p_nome, p_tipo) returning id;
$f$;

create or replace function pg_temp.f3c_prop(p_caso uuid, p_cli uuid, p_ves uuid, p_origem text, p_numero text, p_dados jsonb, p_total numeric,
                                            p_linhas integer, p_prov integer, p_antigo date, p_estado text default 'proposta') returns uuid
language sql as $f$
  insert into public.retorno_previa (abertura_id, chave, client_id, vessel_id, origem, fonte_numero, fonte_em, familias, titulo, estado, modo, total, linhas_n, provisorios_n, preco_mais_antigo, hash, dados)
  select a.id, a.chave, p_cli, p_ves, p_origem, p_numero, case when p_numero is not null then timestamptz '2026-08-12 10:00-03' end, array['bateria'], 'Baterias', p_estado,
         case when p_estado = 'sombra' then 'sombra' else 'ligado' end, p_total, p_linhas, p_prov, p_antigo, 'hash-teste', p_dados
    from public.retorno_aberturas a where a.id = p_caso
  returning id;
$f$;

create or replace function pg_temp.f3c_lin(p_previa uuid, p_ordem integer, p_nome text, p_qtd numeric, p_preco numeric, p_fonte text, p_em date,
                                           p_estado text default 'ok', p_motivo text default null, p_tipo text default 'peca') returns void
language sql as $f$
  insert into public.retorno_previa_linhas (previa_id, ordem, tipo, nome, quantidade, preco, preco_fonte, preco_em, estado, motivo)
  values (p_previa, p_ordem, p_tipo, p_nome, p_qtd, p_preco, p_fonte, p_em, p_estado, p_motivo);
$f$;

create or replace function pg_temp.f3c_os(p_num text, p_cli uuid, p_un uuid, p_em timestamptz, p_total numeric) returns uuid
language sql as $f$
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, problem_description, created_at, updated_at, grand_total)
  values (p_num, p_cli, p_un, 'draft', 'draft', 'repair', 'teste', p_em, p_em, p_total)
  returning id;
$f$;

create or replace function pg_temp.f3c_peca(p_os uuid, p_prod uuid, p_qtd numeric, p_preco numeric) returns void
language sql as $f$
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot, line_total_cost, line_total_sale)
  values (p_os, p_prod, p_qtd, 1, p_preco, p_qtd, p_qtd * p_preco);
$f$;

create or replace function pg_temp.f3c_prod(p_nome text) returns uuid
language sql as $f$
  insert into public.products (name, stock_quantity, sale_price, active) values (p_nome, 0, 10, true) returning id;
$f$;

create or replace function pg_temp.f3c_igual(p_rot text, p_valor text, p_esp text) returns void
language plpgsql as $f$
begin
  if p_valor is distinct from p_esp then
    raise exception '%: %, esperava %', p_rot, coalesce(p_valor, '∅'), coalesce(p_esp, '∅');
  end if;
end $f$;

-- O item do caso, como o cartão monta.
create or replace function pg_temp.f3c_item(p_caso uuid, p_agora timestamptz default '2026-11-10 15:00-03', p_n integer default 1) returns jsonb
language sql as $f$
  select public._retorno_item_montar(p_caso, p_n::smallint, p_agora);
$f$;

-- As linhas do item depois da 1ª, sem o "O que sei" (que depende da OS do contato).
create or replace function pg_temp.f3c_corpo(p_item jsonb) returns text
language sql as $f$
  select coalesce(string_agg(l.linha, E'\n' order by l.ord), '')
    from jsonb_array_elements_text(p_item -> 'linhas') with ordinality as l(linha, ord)
   where l.ord > 1 and l.linha not like '   O que sei:%';
$f$;

-- As letras do item, em ordem alfabética.
create or replace function pg_temp.f3c_letras(p_item jsonb) returns text
language sql as $f$
  select coalesce(string_agg(o ->> 'letra', ',' order by o ->> 'letra'), '')
    from jsonb_array_elements(p_item -> 'opcoes') o;
$f$;

create or replace function pg_temp.f3c_limpar() returns void
language sql as $f$
  update public.ai_operator_pending_actions set status = 'expired' where status = 'pending';
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste' where status = 'aberta';
  update public.retorno_cartoes set estado = 'decidido', decidido_em = now(), decidido_por = 'nao' where estado = 'vivo';
$f$;

-- O cartão vivo: abre com os casos do teste.
create or replace function pg_temp.f3c_cartao(p_agora timestamptz default '2026-11-10 15:00-03') returns uuid
language plpgsql as $f$
declare
  v_r jsonb;
begin
  perform pg_temp.f3c_limpar();
  v_r := public.retorno_cartao_abrir('puxar', p_agora);
  if v_r ->> 'acao' <> 'cartao' then
    raise exception 'cartão não abriu: %', v_r;
  end if;
  return (v_r ->> 'cartao_id')::uuid;
end $f$;

-- Fecha os casos para o teste seguinte não pegar o cartão de antes.
create or replace function pg_temp.f3c_sumir(p_casos uuid[]) returns void
language sql as $f$
  update public.retorno_aberturas set estado = 'fechada', fechada_em = now(), fechada_motivo = 'expirou' where id = any (p_casos);
$f$;

do $cartao$
declare
  c_agora constant timestamptz := '2026-11-10 15:00-03';
  c_recente constant date := '2026-08-12';
  v_dono uuid;
  v_phone text;
  v_cl uuid; v_cl2 uuid; v_cl3 uuid;
  v_un uuid; v_un2 uuid;
  v_caso uuid; v_caso2 uuid; v_caso3 uuid; v_caso4 uuid;
  v_casos uuid[];
  v_pv uuid; v_pv2 uuid;
  v_os uuid; v_os2 uuid;
  v_p uuid;
  v_item jsonb; v_item2 jsonb;
  v_cartao uuid;
  v_ip uuid;
  v_texto text;
  v_h text; v_h2 text;
  v_r jsonb;
  v_n integer;
  i integer;
  v_prop_id uuid;
  v_prop_id2 uuid;
begin
  begin
    select d.id, d.phone into v_dono, v_phone from public._comprovante_dono() d;
    update public.ai_operator_pending_actions set status = 'expired' where status = 'pending';
    update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste' where status = 'aberta';
    update public.ai_operator_sessions set metadata = metadata - 'pendencias_guardadas' where external_thread_key = v_phone;
    update public.retorno_config set modo = 'ligado', tipos_ligados = '{}', cartao_ligado = true, cartao_max_itens = 3, previa_modo = 'desligado', previa_ditado_ligado = false,
           previa_max_linhas = 12, previa_preco_velho = interval '180 days', validade_orcamento_dias = 7 where id;
    update public.retorno_modelo_tipos set nivel = 'cartao';

    v_p := pg_temp.f3c_prod('Produto F3 Cartao');

    -- ═══ 1. Regressão: com as flags desligadas, item e cartão iguais aos da F2, byte a byte. Um caso de cada tipo que a F3 toca.
    v_cl := pg_temp.f3c_cli('Rodrigo Cartao F3', 101);
    v_un := pg_temp.f3c_un(v_cl, 'Brisa');
    v_caso := pg_temp.f3c_caso(101, 'cliente', v_cl);                                                    -- orcamento
    v_caso2 := pg_temp.f3c_caso(102, 'cliente', pg_temp.f3c_cli('Ana Cartao F3', 102), 'aproveitando, ve também a bomba por favor?');   -- adicional
    v_caso3 := pg_temp.f3c_caso(103, 'numero_novo', null, 'oi, tudo bem?');                                 -- numero_novo sem intenção
    v_caso4 := pg_temp.f3c_caso(104, 'cliente', pg_temp.f3c_cli('Bia Cartao F3', 104), 'bom dia');            -- livre
    -- Com proposta viva da F3 no banco, as flags desligadas continuam escondendo tudo.
    v_pv := pg_temp.f3c_prop(v_caso, v_cl, v_un, 'historico', 'ORÇ-00901', '{"forte": true, "fonte_aprovada": true}', 2000, 1, 0, c_recente);
    perform pg_temp.f3c_lin(v_pv, 1, 'Bateria 200Ah', 1, 2000, 'praticado_cliente', c_recente);

    foreach v_ip in array array[v_caso, v_caso2, v_caso3, v_caso4] loop
      v_item := pg_temp.f3c_item(v_ip);
      v_item2 := pg_temp.f2_item_montar(v_ip, 1::smallint, c_agora);
      if (v_item - 'previa_id' - 'acao_sim') is distinct from v_item2 then
        raise exception '1a: item difere da F2 no caso %: % <> %', v_ip, v_item, v_item2;
      end if;
      if v_item ->> 'previa_id' is not null or v_item ->> 'acao_sim' is not null then
        raise exception '1b: marca da F3 com as flags desligadas (%)', v_item;
      end if;
    end loop;
    v_cartao := pg_temp.f3c_cartao(c_agora);
    v_texto := (select c.texto from public.retorno_cartoes c where c.id = v_cartao);
    perform pg_temp.f3c_igual('1c texto', public._retorno_cartao_texto(v_cartao, null), pg_temp.f2_cartao_texto(v_cartao, null));
    perform pg_temp.f3c_igual('1d texto gravado', v_texto, pg_temp.f2_cartao_texto(v_cartao, null));
    if v_texto like '%Proposta%' or v_texto like '%ver no local%' or v_texto like '%dite o que mudar%' then
      raise exception '1e: cartão com texto da F3: %', v_texto;
    end if;
    if exists (select 1 from public.retorno_cartao_itens i where i.cartao_id = v_cartao and (i.previa_id is not null or i.acao_sim is not null)) then
      raise exception '1f: item com marca da F3';
    end if;
    -- 16 (flags desligadas): *retorno* com o cartão vivo não remonta nada.
    update public.retorno_cartao_itens i set texto_mostrado = 'marca-do-teste' where i.cartao_id = v_cartao;
    perform public.retorno_cartao_abrir('puxar', c_agora + interval '1 minute');
    if exists (select 1 from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.texto_mostrado is distinct from 'marca-do-teste') then
      raise exception '16a: remontou com as flags desligadas';
    end if;
    perform pg_temp.f3c_limpar();
    perform pg_temp.f3c_sumir(array[v_caso2, v_caso3, v_caso4]);

    -- Daqui em diante, a F3 ligada.
    update public.retorno_config set previa_modo = 'sombra', previa_ditado_ligado = true where id;

    -- ═══ 2. Cada linha da tabela, literal, com o caso de teste 1.
    -- Linha 2, histórico forte: C20 e C23, com B porque há 2º parecido.
    update public.retorno_previa set dados = dados || jsonb_build_object('alternativas', jsonb_build_array(jsonb_build_object('os_id', gen_random_uuid(), 'numero', 'ORÇ-00071', 'em', c_agora))), total = 4200, linhas_n = 3, preco_mais_antigo = c_recente where id = v_pv;
    perform pg_temp.f3c_lin(v_pv, 2, 'Cabo 50mm', 1, 1200, 'praticado_cliente', c_recente);
    perform pg_temp.f3c_lin(v_pv, 3, 'Instalação', 1, 1000, 'praticado_cliente', c_recente, 'ok', null, 'servico');
    v_item := pg_temp.f3c_item(v_caso);
    perform pg_temp.f3c_igual('2 linha 2 corpo', pg_temp.f3c_corpo(v_item),
      '   Proposta com base no ORÇ-00901 · Brisa: 3 itens · R$ 4.200 · preços de ago/26' || E'\n' ||
      '   *1 B* usa o ORÇ-00071 · *1 L* precisa ver no local · *ver 1* mostra os itens');
    perform pg_temp.f3c_igual('2 linha 2 acao', v_item ->> 'acao_sim', 'orcar');
    perform pg_temp.f3c_igual('2 linha 2 letras', pg_temp.f3c_letras(v_item), 'B,L');
    perform pg_temp.f3c_igual('2 linha 2 previa', v_item ->> 'previa_id', v_pv::text);
    -- 20 + 3: sem B quando não há outro parecido (origem historico sem alternativas).
    update public.retorno_previa set dados = dados - 'alternativas' where id = v_pv;
    perform pg_temp.f3c_igual('2 sem B', pg_temp.f3c_letras(pg_temp.f3c_item(v_caso)), 'L');

    -- 3. *confira*: 181 dias aparece, 179 não, linha de catálogo aparece; todas de catálogo não usa "preços de".
    update public.retorno_previa_linhas set preco_em = c_recente - 90, preco_fonte = 'praticado_cliente' where previa_id = v_pv;
    update public.retorno_previa_linhas set preco_em = date '2026-11-10' - 181 where previa_id = v_pv and ordem = 2;
    update public.retorno_previa set preco_mais_antigo = date '2026-11-10' - 181 where id = v_pv;
    perform pg_temp.f3c_igual('3a confira 181', pg_temp.f3c_corpo(pg_temp.f3c_item(v_caso)),
      '   Proposta com base no ORÇ-00901 · Brisa: 3 itens · R$ 4.200 · preços de mai/26: confira o preço de Cabo 50mm' || E'\n' ||
      '   *1 L* precisa ver no local · *ver 1* mostra os itens');
    update public.retorno_previa_linhas set preco_em = date '2026-11-10' - 179 where previa_id = v_pv and ordem = 2;
    update public.retorno_previa set preco_mais_antigo = date '2026-11-10' - 179 where id = v_pv;
    perform pg_temp.f3c_igual('3b 179 não', pg_temp.f3c_corpo(pg_temp.f3c_item(v_caso)),
      '   Proposta com base no ORÇ-00901 · Brisa: 3 itens · R$ 4.200 · preços de mai/26' || E'\n' ||
      '   *1 L* precisa ver no local · *ver 1* mostra os itens');
    update public.retorno_previa_linhas set preco_fonte = 'catalogo', preco_em = null where previa_id = v_pv and ordem = 1;
    perform pg_temp.f3c_igual('3c catálogo', pg_temp.f3c_corpo(pg_temp.f3c_item(v_caso)),
      '   Proposta com base no ORÇ-00901 · Brisa: 3 itens · R$ 4.200 · preços de mai/26 e 1 de catálogo, sem data: confira o preço de Bateria 200Ah' || E'\n' ||
      '   *1 L* precisa ver no local · *ver 1* mostra os itens');
    update public.retorno_previa_linhas set preco_fonte = 'catalogo', preco_em = null where previa_id = v_pv;
    update public.retorno_previa set preco_mais_antigo = null where id = v_pv;
    v_texto := pg_temp.f3c_corpo(pg_temp.f3c_item(v_caso));
    if v_texto not like '%R$ 4.200 · preços de catálogo, sem data: confira o preço de Bateria 200Ah%' or v_texto like '%preços de mai%' then
      raise exception '3d: todas de catálogo: %', v_texto;
    end if;

    -- 20. Proposta histórica com todas as linhas ditadas: preços ditados por você.
    update public.retorno_previa_linhas set preco_fonte = 'dito', preco_em = null where previa_id = v_pv;
    v_texto := pg_temp.f3c_corpo(pg_temp.f3c_item(v_caso));
    if v_texto not like '%R$ 4.200 · preços ditados por você%' or v_texto like '%preços de%' then
      raise exception '20: %', v_texto;
    end if;
    delete from public.retorno_previa_linhas where previa_id = v_pv and ordem > 1;
    update public.retorno_previa_linhas set preco_fonte = 'praticado_cliente', preco_em = c_recente where previa_id = v_pv;
    update public.retorno_previa set preco_mais_antigo = c_recente, total = 1320.5, linhas_n = 1 where id = v_pv;
    -- 19. Formato: centavos, 1 item, inteiro.
    update public.retorno_previa_linhas set preco = 1320.5 where previa_id = v_pv;
    perform pg_temp.f3c_igual('19a', pg_temp.f3c_corpo(pg_temp.f3c_item(v_caso)),
      '   Proposta com base no ORÇ-00901 · Brisa: 1 item · R$ 1.320,50 · preços de ago/26' || E'\n' ||
      '   *1 L* precisa ver no local · *ver 1* mostra os itens');
    update public.retorno_previa set total = 1320 where id = v_pv;
    update public.retorno_previa_linhas set preco = 1320 where previa_id = v_pv;
    if pg_temp.f3c_corpo(pg_temp.f3c_item(v_caso)) not like '%R$ 1.320 ·%' then
      raise exception '19b: inteiro sem centavos';
    end if;

    -- Linha 2b: fonte de outro cliente, uma C30 por linha. Linha 11 também: forte não mostra.
    update public.retorno_previa set dados = jsonb_build_object('forte', false, 'fonte_aprovada', false), total = 1320.5 + 90 * 1.5, linhas_n = 2 where id = v_pv;
    perform pg_temp.f3c_lin(v_pv, 2, 'Mão de obra', 1.5, 90, 'orcado_cliente', c_recente, 'ok', null, 'servico');
    update public.retorno_previa_linhas set preco = 1320.5, preco_fonte = 'praticado_outro' where previa_id = v_pv and ordem = 1;
    v_item := pg_temp.f3c_item(v_caso);
    perform pg_temp.f3c_igual('11a 2b', pg_temp.f3c_corpo(v_item),
      '   Proposta com base no ORÇ-00901 (não aprovado) · Brisa: 2 itens · R$ 1.455,50 · preços de ago/26' || E'\n' ||
      '   · Bateria 200Ah · 1 × R$ 1.320,50 · outro cliente 12/08/26' || E'\n' ||
      '   · Mão de obra · 1,5 × R$ 90 · orçado 12/08/26' || E'\n' ||
      '   *1 L* precisa ver no local · *ver 1* mostra os itens');
    perform pg_temp.f3c_igual('11b acao', v_item ->> 'acao_sim', 'orcar');
    update public.retorno_previa set dados = jsonb_build_object('forte', true, 'fonte_aprovada', true) where id = v_pv;
    if pg_temp.f3c_corpo(pg_temp.f3c_item(v_caso)) like '%   · %' then
      raise exception '11c: forte mostrou as linhas';
    end if;

    -- Linha 2 ditada (C21).
    update public.retorno_previa set origem = 'ditado', fonte_numero = null, fonte_em = null, total = 3120, linhas_n = 2, dados = '{}' where id = v_pv;
    update public.retorno_previa_linhas set preco_fonte = 'dito', preco_em = null, preco = 1320, quantidade = 1 where previa_id = v_pv and ordem = 1;
    update public.retorno_previa_linhas set preco_fonte = 'dito', preco_em = null, preco = 1800, quantidade = 1 where previa_id = v_pv and ordem = 2;
    perform pg_temp.f3c_igual('2 C21', pg_temp.f3c_corpo(pg_temp.f3c_item(v_caso)),
      '   Proposta ditada · Brisa: 2 itens · R$ 3.120 · 2 preços ditos por você' || E'\n' ||
      '   *1 L* precisa ver no local · *ver 1* mostra os itens');

    -- Linha 3, provisório, com unidade: C22, C22b e C22c (22).
    update public.retorno_previa set origem = 'historico', fonte_numero = 'ORÇ-00901', fonte_em = '2026-08-12 10:00-03',
           dados = jsonb_build_object('forte', true, 'fonte_aprovada', true), total = 1100, linhas_n = 4, provisorios_n = 3, preco_mais_antigo = c_recente where id = v_pv;
    update public.retorno_previa_linhas set preco = 1100, preco_fonte = 'praticado_cliente', preco_em = c_recente where previa_id = v_pv and ordem = 1;
    update public.retorno_previa_linhas set nome = 'Bateria sem preço', preco = null, preco_fonte = 'sem_preco', preco_em = null, estado = 'provisorio', motivo = 'sem_preco', tipo = 'peca' where previa_id = v_pv and ordem = 2;
    perform pg_temp.f3c_lin(v_pv, 3, 'Serviço a descrever', 1, null, 'sem_preco', null, 'provisorio', 'nome_com_dado_de_outro', 'servico');
    perform pg_temp.f3c_lin(v_pv, 4, 'Bomba antiga', 1, null, 'sem_preco', null, 'provisorio', 'inativo');
    v_item := pg_temp.f3c_item(v_caso);
    perform pg_temp.f3c_igual('22 C22/C22b/C22c', pg_temp.f3c_corpo(v_item),
      '   Proposta com base no ORÇ-00901 · Brisa: 4 itens · R$ 1.100 · preços de ago/26' || E'\n' ||
      '   Falta preço em 1: Bateria sem preço. Dite o valor antes do *sim*.' || E'\n' ||
      '   Falta descrever 1 serviço: diga o que é cada um antes do *sim*.' || E'\n' ||
      '   Fora de linha no cadastro: Bomba antiga. Troque ou tire antes do *sim*.' || E'\n' ||
      '   *1 L* precisa ver no local · *ver 1* mostra os itens');
    perform pg_temp.f3c_igual('3 linha 3 acao', v_item ->> 'acao_sim', 'orcar');
    -- 12 (parte) Rodapé: item provisório não entra em "cria o orçamento".
    v_cartao := pg_temp.f3c_cartao(c_agora);
    v_texto := (select c.texto from public.retorno_cartoes c where c.id = v_cartao);
    if v_texto like '%cria o orçamento e manda o PDF%' then
      raise exception '12a: provisório no rodapé: %', v_texto;
    end if;
    if v_texto not like '%*ver 1* · *dita 1 …* · *não* · ou dite o que mudar%' then
      raise exception '12b: rodapé do provisório: %', v_texto;
    end if;
    perform pg_temp.f3c_limpar();
    -- Sem provisório: o rodapé diz o que o *sim* faz, e item com texto_ditado não entra.
    delete from public.retorno_previa_linhas where previa_id = v_pv and ordem > 1;
    update public.retorno_previa set linhas_n = 1, provisorios_n = 0, total = 1100 where id = v_pv;
    v_cartao := pg_temp.f3c_cartao(c_agora);
    v_texto := (select c.texto from public.retorno_cartoes c where c.id = v_cartao);
    if v_texto not like '%*sim <PIN>* faz o 1 (cria o orçamento e manda o PDF) · *só 1* · *ver 1* · *não* · ou dite o que mudar%' then
      raise exception '12c: rodapé com orçamento: %', v_texto;
    end if;
    update public.retorno_cartao_itens set texto_ditado = 'um texto ditado', ditado_via = 'dita' where cartao_id = v_cartao and n = 1;
    v_texto := public._retorno_cartao_texto(v_cartao, null);
    if v_texto like '%cria o orçamento e manda o PDF%' or v_texto not like '%*sim <PIN>* faz o 1 · *só 1*%' then
      raise exception '12d: item ditado no rodapé: %', v_texto;
    end if;
    perform pg_temp.f3c_limpar();

    -- Linha 4 (24): provisório, 2 unidades e nenhuma definida; a letra C/F.
    v_cl2 := pg_temp.f3c_cli('Paulo Cartao F3', 202);
    perform pg_temp.f3c_un(v_cl2, 'Alma');
    v_un2 := pg_temp.f3c_un(v_cl2, 'Vento');
    v_caso2 := pg_temp.f3c_caso(202, 'cliente', v_cl2);
    v_pv2 := pg_temp.f3c_prop(v_caso2, v_cl2, null, 'historico', 'ORÇ-00088', jsonb_build_object('forte', true, 'fonte_aprovada', true), 500, 1, 1, null);
    perform pg_temp.f3c_lin(v_pv2, 1, 'Serviço a descrever', 1, null, 'sem_preco', null, 'provisorio', 'sem_preco', 'servico');
    v_item := pg_temp.f3c_item(v_caso2, c_agora, 2);
    perform pg_temp.f3c_igual('24 linha 4', pg_temp.f3c_corpo(v_item),
      '   Proposta com base no ORÇ-00088: 1 item · R$ 500' || E'\n' ||
      '   Qual unidade? *2 C* Alma · *2 F* Vento' || E'\n' ||
      '   *2 L* precisa ver no local · *ver 2* mostra os itens');
    perform pg_temp.f3c_igual('24 acao', v_item ->> 'acao_sim', null);
    perform pg_temp.f3c_igual('24 letras', pg_temp.f3c_letras(v_item), 'C,F,L');

    -- 4. A letra escolhida leva à linha com acao_sim = 'orcar'.
    update public.retorno_aberturas set unidade_escolhida_id = v_un2 where id = v_caso2;
    update public.retorno_previa set provisorios_n = 0, total = 500 where id = v_pv2;
    update public.retorno_previa_linhas set nome = 'Serviço X', preco = 500, preco_fonte = 'praticado_cliente', preco_em = c_recente, estado = 'ok', motivo = null where previa_id = v_pv2;
    v_item := pg_temp.f3c_item(v_caso2);
    perform pg_temp.f3c_igual('4 acao', v_item ->> 'acao_sim', 'orcar');
    if v_item ->> 'linhas' not like '%Vento%' then
      raise exception '4a: unidade à vista: %', v_item -> 'linhas';
    end if;
    update public.retorno_aberturas set unidade_escolhida_id = null where id = v_caso2;
    update public.retorno_previa set provisorios_n = 1, total = 500 where id = v_pv2;
    update public.retorno_previa_linhas set nome = 'Serviço a descrever', preco = null, preco_fonte = 'sem_preco', preco_em = null, estado = 'provisorio', motivo = 'sem_preco' where previa_id = v_pv2;

    -- Linha 5 (24): provisório com 0 unidades e cliente no cadastro.
    v_cl3 := pg_temp.f3c_cli('Lia Cartao F3', 303);
    v_caso3 := pg_temp.f3c_caso(303, 'cliente', v_cl3);
    v_pv := pg_temp.f3c_prop(v_caso3, v_cl3, null, 'historico', 'ORÇ-00050', jsonb_build_object('forte', true, 'fonte_aprovada', true), 700, 1, 1, null);
    perform pg_temp.f3c_lin(v_pv, 1, 'Item Z', 1, null, 'sem_preco', null, 'provisorio', 'sem_preco', 'servico');
    v_item := pg_temp.f3c_item(v_caso3, c_agora, 3);
    perform pg_temp.f3c_igual('24b linha 5', pg_temp.f3c_corpo(v_item),
      '   Proposta com base no ORÇ-00050: 1 item · R$ 700' || E'\n' ||
      '   Falta cadastrar a unidade: diga o nome e o tipo (*cadastra a lancha Brisa no 3*) ou crie no app, e mande *retorno*.' || E'\n' ||
      '   *3 L* precisa ver no local · *ver 3* mostra os itens');
    perform pg_temp.f3c_igual('24c letras', pg_temp.f3c_letras(v_item), 'L');

    -- Linha 5b (25): proposta sem cliente no cadastro.
    v_caso4 := pg_temp.f3c_caso(304, 'numero_novo', null);
    v_pv2 := pg_temp.f3c_prop(v_caso4, null, null, 'historico', 'ORÇ-00049', jsonb_build_object('forte', false, 'fonte_aprovada', true), 700, 1, 0, c_recente);
    perform pg_temp.f3c_lin(v_pv2, 1, 'Bateria', 1, 700, 'praticado_outro', c_recente);
    v_item := pg_temp.f3c_item(v_caso4, c_agora, 3);
    perform pg_temp.f3c_igual('25 linha 5b', pg_temp.f3c_corpo(v_item),
      '   Proposta com base no ORÇ-00049: 1 item · R$ 700 · preços de ago/26' || E'\n' ||
      '   Cadastro incompleto: o orçamento só sai depois que ele responder.' || E'\n' ||
      '   *3 L* precisa ver no local · *ver 3* mostra os itens');
    if pg_temp.f3c_corpo(v_item) like '%cadastra a lancha%' then
      raise exception '25b: C27 sem cliente';
    end if;

    -- Linha 0 (10): visita a combinar.
    v_cl := pg_temp.f3c_cli('Beto Visita F3', 405);
    v_caso := pg_temp.f3c_caso(405, 'cliente', v_cl);
    update public.retorno_aberturas set visita_a_combinar_em = '2026-11-08 10:00-03' where id = v_caso;
    v_item := pg_temp.f3c_item(v_caso);
    perform pg_temp.f3c_igual('10a C29', pg_temp.f3c_corpo(v_item), '   Visita a combinar desde 08/11. *resolvido 1* tira da lista.');
    perform pg_temp.f3c_igual('10b sem acao', v_item ->> 'acao_sim', null);
    perform pg_temp.f3c_igual('10c sem letra', pg_temp.f3c_letras(v_item), '');
    -- Com proposta ditada viva, a marca cede: linha 2.
    v_un := pg_temp.f3c_un(v_cl, 'Rota');
    v_pv := pg_temp.f3c_prop(v_caso, v_cl, v_un, 'ditado', null, '{}', 800, 1, 0, null);
    perform pg_temp.f3c_lin(v_pv, 1, 'Peça A', 1, 800, 'dito', null);
    v_item := pg_temp.f3c_item(v_caso);
    perform pg_temp.f3c_igual('10d ditado cede', v_item ->> 'acao_sim', 'orcar');
    update public.retorno_previa set estado = 'descartada' where id = v_pv;
    -- Rascunho anterior à marca: C29; depois da marca: linha 1.
    v_os := pg_temp.f3c_os('ORÇ-00301', v_cl, v_un, c_agora - interval '5 days', 500);
    perform pg_temp.f3c_peca(v_os, v_p, 1, 500);
    v_item := pg_temp.f3c_item(v_caso);
    perform pg_temp.f3c_igual('10e rascunho antigo', pg_temp.f3c_corpo(v_item), '   Visita a combinar desde 08/11. *resolvido 1* tira da lista.');
    update public.service_orders so set created_at = c_agora - interval '1 hour' where so.id = v_os;
    v_item := pg_temp.f3c_item(v_caso);
    perform pg_temp.f3c_igual('10f rascunho novo', v_item ->> 'acao_sim', 'pdf');
    -- _retorno_cartao_casos: a linha 0 cedeu, então não vai para a prioridade 7.
    if (select c.prioridade from public._retorno_cartao_casos(c_agora, 100) c where c.abertura_id = v_caso) = 7 then
      raise exception '10g: caso cedido continuou na prioridade 7';
    end if;
    delete from public.service_order_parts where service_order_id = v_os;
    update public.service_orders so set status = 'cancelled' where so.id = v_os;

    -- Linha 1, 1b, e 6 (rascunho).
    v_cl := pg_temp.f3c_cli('Carla Rascunho F3', 501);
    v_un := pg_temp.f3c_un(v_cl, 'Brisa');
    v_caso := pg_temp.f3c_caso(501, 'cliente', v_cl);
    v_os := pg_temp.f3c_os('ORÇ-00151', v_cl, v_un, '2026-11-10 13:30-03', 4200);
    perform pg_temp.f3c_peca(v_os, v_p, 2, 2100);
    v_item := pg_temp.f3c_item(v_caso);
    perform pg_temp.f3c_igual('6a linha 1', pg_temp.f3c_corpo(v_item), '   Rascunho ORÇ-00151 de 10/11 · Brisa: 1 item · R$ 4.200 · vale até terça (17/11) se sair hoje');
    perform pg_temp.f3c_igual('6b acao', v_item ->> 'acao_sim', 'pdf');
    perform pg_temp.f3c_igual('6c letras', pg_temp.f3c_letras(v_item), 'L');
    perform pg_temp.f3c_igual('6d so', v_item ->> 'service_order_id', v_os::text);
    -- Rascunho de outra unidade não é oferecido.
    update public.service_orders so set vessel_id = pg_temp.f3c_un(v_cl, 'Outra') where so.id = v_os;
    update public.retorno_aberturas set unidade_escolhida_id = v_un where id = v_caso;
    v_item := pg_temp.f3c_item(v_caso);
    if v_item ->> 'acao_sim' is not null or pg_temp.f3c_corpo(v_item) like '%Rascunho%' then
      raise exception '6e: rascunho de outra unidade: %', v_item;
    end if;
    update public.retorno_aberturas set unidade_escolhida_id = null where id = v_caso;
    update public.service_orders so set vessel_id = v_un where so.id = v_os;
    -- Total zero e linha sem preço: linha 1b.
    update public.service_order_parts set unit_sale_snapshot = 0, line_total_sale = 0 where service_order_id = v_os;
    v_item := pg_temp.f3c_item(v_caso);
    perform pg_temp.f3c_igual('6f linha 1b', pg_temp.f3c_corpo(v_item), '   Rascunho ORÇ-00151 de 10/11 está sem valor: complete na tela. *1 L* precisa ver no local.');
    perform pg_temp.f3c_igual('6g acao', v_item ->> 'acao_sim', null);
    delete from public.service_order_parts where service_order_id = v_os;
    update public.service_orders so set grand_total = 0 where so.id = v_os;
    if pg_temp.f3c_corpo(pg_temp.f3c_item(v_caso)) not like '%está sem valor%' then
      raise exception '6h: total zero';
    end if;
    update public.service_orders so set status = 'cancelled' where so.id = v_os;
    -- Número novo com cadastro provisório recebe a linha 1.
    v_cl2 := pg_temp.f3c_cli('Dora Provisorio F3');
    v_un2 := pg_temp.f3c_un(v_cl2, 'Maresia');
    v_caso2 := pg_temp.f3c_caso(502, 'numero_novo', null);
    insert into public.audit_log (table_name, record_id, action, changed_by, new_value, reason)
    values ('clients', v_cl2, 'lead_converted', 'retorno', jsonb_build_object('caso', v_caso2, 'vessel_id', v_un2), 'teste');
    v_os2 := pg_temp.f3c_os('ORÇ-00152', v_cl2, v_un2, '2026-11-10 13:30-03', 300);
    perform pg_temp.f3c_peca(v_os2, v_p, 1, 300);
    v_item := pg_temp.f3c_item(v_caso2);
    perform pg_temp.f3c_igual('6i número novo', v_item ->> 'acao_sim', 'pdf');
    -- 9. Número novo mantém D.
    perform pg_temp.f3c_igual('9 letras', pg_temp.f3c_letras(v_item), 'D,L');
    update public.service_orders so set status = 'cancelled' where so.id = v_os2;

    -- Linha 6a: cliente e unidade definidos, sem proposta. Linha 6b (14): 2 unidades. Linha 6c: 0 unidades. Linha 6d: sem cadastro.
    v_cl := pg_temp.f3c_cli('Eva SemProposta F3', 601);
    perform pg_temp.f3c_un(v_cl, 'Unica');
    v_caso := pg_temp.f3c_caso(601, 'cliente', v_cl);
    perform pg_temp.f3c_igual('6a C24', pg_temp.f3c_corpo(pg_temp.f3c_item(v_caso)), '   Dite o orçamento em áudio. *1 L* precisa ver no local.');
    v_cl := pg_temp.f3c_cli('Fred DuasUnidades F3', 602);
    perform pg_temp.f3c_un(v_cl, 'Alfa');
    v_un := pg_temp.f3c_un(v_cl, 'Beta');
    v_caso := pg_temp.f3c_caso(602, 'cliente', v_cl);
    v_item := pg_temp.f3c_item(v_caso);
    perform pg_temp.f3c_igual('14a C31', pg_temp.f3c_corpo(v_item), '   Qual unidade? *1 C* Alfa · *1 F* Beta. Depois dite o orçamento em áudio. *1 L* precisa ver no local.');
    perform pg_temp.f3c_igual('14b letras', pg_temp.f3c_letras(v_item), 'C,F,L');
    -- A letra grava a unidade do caso e a linha vira C24.
    update public.retorno_aberturas set unidade_escolhida_id = v_un where id = v_caso;
    perform pg_temp.f3c_igual('14c depois da letra', pg_temp.f3c_corpo(pg_temp.f3c_item(v_caso)), '   Dite o orçamento em áudio. *1 L* precisa ver no local.');
    v_cl := pg_temp.f3c_cli('Gil SemUnidade F3', 603);
    v_caso := pg_temp.f3c_caso(603, 'cliente', v_cl);
    perform pg_temp.f3c_igual('6c C27', pg_temp.f3c_corpo(pg_temp.f3c_item(v_caso)),
      '   Falta cadastrar a unidade: diga o nome e o tipo (*cadastra a lancha Brisa no 1*) ou crie no app, e mande *retorno*.' || E'\n' ||
      '   *1 L* precisa ver no local');
    v_caso := pg_temp.f3c_caso(604, 'numero_novo', null);
    v_item := pg_temp.f3c_item(v_caso);
    perform pg_temp.f3c_igual('6d C33', pg_temp.f3c_corpo(v_item), '   Cadastro incompleto: o orçamento aparece aqui quando ele responder. *1 L* precisa ver no local.');
    perform pg_temp.f3c_igual('6e letras', pg_temp.f3c_letras(v_item), 'L');

    -- 13. Número novo que só disse "oi": idêntico à F2 (só D, se houver), sem C24 e sem L.
    v_caso := pg_temp.f3c_caso(605, 'numero_novo', null, 'oi, tudo bem?');
    v_item := pg_temp.f3c_item(v_caso);
    if (v_item - 'previa_id' - 'acao_sim') is distinct from pg_temp.f2_item_montar(v_caso, 1::smallint, c_agora) then
      raise exception '13a: número novo "oi" difere da F2: %', v_item;
    end if;
    perform pg_temp.f3c_igual('13b letras', pg_temp.f3c_letras(v_item), '');
    -- Número novo com intenção orçamento e cadastro com 1 unidade: C24.
    v_cl2 := pg_temp.f3c_cli('Hugo Cadastro F3');
    perform pg_temp.f3c_un(v_cl2, 'Ondina');
    v_caso2 := pg_temp.f3c_caso(606, 'numero_novo', null);
    insert into public.audit_log (table_name, record_id, action, changed_by, new_value, reason)
    values ('clients', v_cl2, 'lead_converted', 'retorno', jsonb_build_object('caso', v_caso2), 'teste');
    perform pg_temp.f3c_igual('13c C24', pg_temp.f3c_corpo(pg_temp.f3c_item(v_caso2)), '   *1 D* = desfaz o cadastro' || E'\n' || '   Dite o orçamento em áudio. *1 L* precisa ver no local.');

    -- 5. Sombra nunca aparece: proposta só em sombra dá as linhas sem proposta.
    v_cl := pg_temp.f3c_cli('Ivo Sombra F3', 701);
    perform pg_temp.f3c_un(v_cl, 'Vaga');
    v_caso := pg_temp.f3c_caso(701, 'cliente', v_cl);
    v_pv := pg_temp.f3c_prop(v_caso, v_cl, null, 'historico', 'ORÇ-00777', jsonb_build_object('forte', true, 'fonte_aprovada', true), 100, 1, 0, c_recente, 'sombra');
    perform pg_temp.f3c_lin(v_pv, 1, 'Peça', 1, 100, 'praticado_cliente', c_recente);
    v_item := pg_temp.f3c_item(v_caso);
    if pg_temp.f3c_corpo(v_item) like '%ORÇ-00777%' or v_item ->> 'previa_id' is not null then
      raise exception '5: sombra apareceu no cartão: %', v_item;
    end if;

    -- Ato do dono (P8.5): item livre, sem intenção, com proposta ditada.
    v_cl := pg_temp.f3c_cli('Joana Ato F3', 801);
    v_un := pg_temp.f3c_un(v_cl, 'Marina');
    v_caso := pg_temp.f3c_caso(801, 'cliente', v_cl, 'a geladeira parou');
    v_item := pg_temp.f3c_item(v_caso);
    perform pg_temp.f3c_igual('ato: tipo livre sem ato', v_item ->> 'tipo_item', 'livre');
    if (v_item - 'previa_id' - 'acao_sim') is distinct from pg_temp.f2_item_montar(v_caso, 1::smallint, c_agora) then
      raise exception 'ato-a: livre sem ato difere da F2';
    end if;
    v_pv := pg_temp.f3c_prop(v_caso, v_cl, v_un, 'ditado', null, '{}', 600, 1, 0, null);
    perform pg_temp.f3c_lin(v_pv, 1, 'Compressor', 1, 600, 'dito', null);
    v_item := pg_temp.f3c_item(v_caso);
    perform pg_temp.f3c_igual('ato-b acao', v_item ->> 'acao_sim', 'orcar');
    perform pg_temp.f3c_igual('ato-c corpo', pg_temp.f3c_corpo(v_item),
      '   Proposta ditada · Marina: 1 item · R$ 600 · 1 preço dito por você' || E'\n' ||
      '   *1 L* precisa ver no local · *ver 1* mostra os itens');
    -- O mesmo com dados.ajustada_por_ditado numa proposta histórica.
    update public.retorno_previa set origem = 'historico', fonte_numero = 'ORÇ-00500', fonte_em = '2026-08-12 10:00-03',
           dados = jsonb_build_object('forte', false, 'fonte_aprovada', true, 'ajustada_por_ditado', true), preco_mais_antigo = null where id = v_pv;
    update public.retorno_previa_linhas set preco_fonte = 'dito', preco_em = null where previa_id = v_pv;
    perform pg_temp.f3c_igual('ato-d ajustada', pg_temp.f3c_item(v_caso) ->> 'acao_sim', 'orcar');
    update public.retorno_previa set estado = 'descartada' where id = v_pv;
    -- Rascunho com origem_chave8 do caso, em item livre: linha 1.
    v_os := pg_temp.f3c_os('ORÇ-00801', v_cl, v_un, c_agora - interval '30 minutes', 200);
    update public.service_orders so set origem = 'retorno_ditado', origem_chave8 = (select a.chave from public.retorno_aberturas a where a.id = v_caso) where so.id = v_os;
    perform pg_temp.f3c_peca(v_os, v_p, 1, 200);
    perform pg_temp.f3c_igual('ato-e rascunho livre', pg_temp.f3c_item(v_caso) ->> 'acao_sim', 'pdf');
    update public.service_orders so set status = 'cancelled' where so.id = v_os;

    -- ═══ 8, 17, 15, 16, 7, 23, 18, 21: com o cartão vivo.
    update public.retorno_config set previa_modo = 'ligado', previa_ditado_ligado = true where id;
    perform pg_temp.f3c_sumir(array(select a.id from public.retorno_aberturas a where a.phone_normalized like '55479008%'));
    v_cl := pg_temp.f3c_cli('Kiko Hash F3', 901);
    v_un := pg_temp.f3c_un(v_cl, 'Delta');
    v_caso := pg_temp.f3c_caso(901, 'cliente', v_cl);
    v_pv := pg_temp.f3c_prop(v_caso, v_cl, v_un, 'historico', 'ORÇ-00900', jsonb_build_object('forte', true, 'fonte_aprovada', true), 1000, 1, 0, c_recente);
    perform pg_temp.f3c_lin(v_pv, 1, 'Peça H', 1, 1000, 'praticado_cliente', c_recente);
    v_cartao := pg_temp.f3c_cartao(c_agora);
    select i.id, i.hash into v_ip, v_h from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 1;

    -- 17. v_k mudando com acao_sim não muda o hash, e o conferir passa.
    insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo, estado, enviar_em, decidida_em, enviada_em, texto, dedupe_key)
    select a.id, 'adiamento', 'retorno_adiamento', 'resposta_imediata', a.chave, a.phone_normalized, a.client_id, 'ligado', 'enviada', c_agora - interval '1 minute', c_agora - interval '1 minute', c_agora - interval '1 minute', 'aviso de teste', 'teste-f3-c-k'
      from public.retorno_aberturas a where a.id = v_caso;
    if pg_temp.f3c_item(v_caso) ->> 'hash' is distinct from v_h then
      raise exception '17a: adiamento mudou o hash com acao_sim';
    end if;
    if (public._retorno_item_conferir(v_ip, c_agora, true) ->> 'ok')::boolean is distinct from true then
      raise exception '17b: conferir caiu com o adiamento: %', public._retorno_item_conferir(v_ip, c_agora, true);
    end if;
    -- A linha "Ele já recebeu" aparece nos dois.
    if pg_temp.f3c_item(v_caso) ->> 'linhas' not like '%Ele já recebeu 1 automáticas hoje.%' then
      raise exception '17c: linha "Ele já recebeu"';
    end if;

    -- 8. Mudar 1 preço muda o hash do item; o conferir com p_executar cai em fato_mudou.
    update public.retorno_previa_linhas set preco = 1100 where previa_id = v_pv;
    if pg_temp.f3c_item(v_caso) ->> 'hash' = v_h then
      raise exception '8a: o preço não mudou o hash';
    end if;
    if public._retorno_item_conferir(v_ip, c_agora, true) ->> 'motivo' is distinct from 'fato_mudou' then
      raise exception '8b: fato_mudou (%)', public._retorno_item_conferir(v_ip, c_agora, true);
    end if;
    update public.retorno_previa_linhas set preco = 1000 where previa_id = v_pv;
    -- Outro previa_id com as mesmas linhas também dá fato_mudou; proposta fora de 'proposta' também.
    update public.retorno_cartao_itens set previa_id = (select id from public.retorno_previa where id <> v_pv limit 1) where id = v_ip;
    if public._retorno_item_conferir(v_ip, c_agora, true) ->> 'motivo' is distinct from 'fato_mudou' then
      raise exception '8c: outro previa_id passou';
    end if;
    update public.retorno_cartao_itens set previa_id = v_pv where id = v_ip;
    if (public._retorno_item_conferir(v_ip, c_agora, true) ->> 'ok')::boolean is distinct from true then
      raise exception '8d: conferir devia passar (%)', public._retorno_item_conferir(v_ip, c_agora, true);
    end if;
    update public.retorno_previa set estado = 'caiu' where id = v_pv;
    if public._retorno_item_conferir(v_ip, c_agora, true) ->> 'motivo' is distinct from 'fato_mudou' then
      raise exception '8e: proposta fora de proposta passou';
    end if;
    update public.retorno_previa set estado = 'proposta' where id = v_pv;

    -- Sem acao_sim, o hash segue como na F2: v_k entra.
    v_cl2 := pg_temp.f3c_cli('Lelo SemProposta F3', 902);
    v_caso2 := pg_temp.f3c_caso(902, 'cliente', v_cl2, 'preciso trocar as baterias da lancha, quanto custa?', c_agora - interval '20 minutes');
    v_item := pg_temp.f3c_item(v_caso2);
    v_h := v_item ->> 'hash';
    insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo, estado, enviar_em, decidida_em, enviada_em, texto, dedupe_key)
    select a.id, 'adiamento', 'retorno_adiamento', 'resposta_imediata', a.chave, a.phone_normalized, a.client_id, 'ligado', 'enviada', c_agora - interval '1 minute', c_agora - interval '1 minute', c_agora - interval '1 minute', 'aviso de teste', 'teste-f3-c-k2'
      from public.retorno_aberturas a where a.id = v_caso2;
    if pg_temp.f3c_item(v_caso2) ->> 'hash' = v_h then
      raise exception '17d: sem acao_sim, o hash não seguiu a F2';
    end if;

    -- 16. puxar: não remonta item com acao_sim, com escolha ou com texto_ditado.
    perform pg_temp.f3c_limpar();
    perform pg_temp.f3c_sumir(array[v_caso2]);
    v_cartao := pg_temp.f3c_cartao(c_agora);
    select i.id into v_ip from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 1;
    update public.retorno_cartao_itens set texto_mostrado = 'marca' where cartao_id = v_cartao;
    perform public.retorno_cartao_abrir('puxar', c_agora + interval '1 minute');
    if (select i.texto_mostrado from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 1) is distinct from 'marca' then
      raise exception '16b: remontou item com acao_sim';
    end if;

    -- 7. *ver N*: cada linha com a data e o rótulo certo; 23. sem C30 repetida.
    update public.retorno_previa set dados = jsonb_build_object('forte', false, 'fonte_aprovada', false), total = 7320, linhas_n = 5, provisorios_n = 1, preco_mais_antigo = c_recente where id = v_pv;
    delete from public.retorno_previa_linhas where previa_id = v_pv;
    perform pg_temp.f3c_lin(v_pv, 1, 'Controlador MPPT 40A', 1, 1100, 'praticado_cliente', date '2026-08-12');
    perform pg_temp.f3c_lin(v_pv, 2, 'Instalação elétrica', 1, 1500, 'orcado_cliente', date '2026-08-12', 'ok', null, 'servico');
    perform pg_temp.f3c_lin(v_pv, 3, 'Bateria LiFePO4 100Ah', 2, 2300, 'praticado_outro', date '2026-08-12');
    perform pg_temp.f3c_lin(v_pv, 4, 'Cabo 16 mm', 3, 40, 'catalogo', null);
    perform pg_temp.f3c_lin(v_pv, 5, 'Serviço a descrever', 1, null, 'sem_preco', null, 'provisorio', 'nome_com_dado_de_outro', 'servico');
    perform public._retorno_item_remontar(v_ip, c_agora);
    v_r := public.retorno_ver_caso(1, v_dono, c_agora);
    v_texto := v_r ->> 'texto';
    if v_texto not like '%Proposta com base no ORÇ-00900 (ago/26):%' then
      raise exception '7a: cabeçalho: %', v_texto;
    end if;
    if position('1. Controlador MPPT 40A · 1 × R$ 1.100 · praticado em 12/08/26' in v_texto) = 0
       or position('2. Instalação elétrica · 1 × R$ 1.500 · orçado em 12/08/26 (não aprovado)' in v_texto) = 0
       or position('3. Bateria LiFePO4 100Ah · 2 × R$ 2.300 · praticado a outro cliente em 12/08/26' in v_texto) = 0
       or position('4. Cabo 16 mm · 3 × R$ 40 · preço de catálogo, sem data' in v_texto) = 0
       or position('5. Serviço a descrever · sem preço' in v_texto) = 0
       or position('Total: R$ 7.320 · vale até terça (17/11), contado do envio' in v_texto) = 0 then
      raise exception '7b: lista: %', v_texto;
    end if;
    -- 23: as C30 do cartão não repetem em *ver*.
    if v_texto like '%   · %' or position('outro cliente 12/08/26' in v_texto) > 0 then
      raise exception '23a: C30 repetida em ver: %', v_texto;
    end if;
    if v_texto like '%Unidades:%' then
      raise exception '23b: Unidades com a unidade definida';
    end if;
    -- Sem provisório, o item vira a linha 2b, e as C30 do cartão não repetem em *ver*.
    delete from public.retorno_previa_linhas where previa_id = v_pv and ordem = 5;
    update public.retorno_previa set linhas_n = 4, provisorios_n = 0, total = 7320 where id = v_pv;
    perform public._retorno_item_remontar(v_ip, c_agora);
    if (select c.texto from public.retorno_cartoes c where c.id = (select i.cartao_id from public.retorno_cartao_itens i where i.id = v_ip)) not like '%· outro cliente 12/08/26%' then
      raise exception '23d: a C30 devia estar no cartão';
    end if;
    v_texto := public.retorno_ver_caso(1, v_dono, c_agora) ->> 'texto';
    if v_texto like '%   · %' or position('outro cliente 12/08/26' in v_texto) > 0 then
      raise exception '23e: C30 repetida em ver: %', v_texto;
    end if;
    -- 23c: Unidades só sem unidade definida, com 2 ou mais.
    perform pg_temp.f3c_limpar();
    perform pg_temp.f3c_sumir(array[v_caso]);
    v_cl := pg_temp.f3c_cli('Mara Unidades F3', 903);
    perform pg_temp.f3c_un(v_cl, 'Aurora');
    perform pg_temp.f3c_un(v_cl, 'Canoa');
    v_caso := pg_temp.f3c_caso(903, 'cliente', v_cl);
    v_pv := pg_temp.f3c_prop(v_caso, v_cl, null, 'historico', 'ORÇ-00903', jsonb_build_object('forte', true, 'fonte_aprovada', true), 100, 1, 0, c_recente);
    perform pg_temp.f3c_lin(v_pv, 1, 'Peça', 1, 100, 'praticado_cliente', c_recente);
    v_cartao := pg_temp.f3c_cartao(c_agora);
    v_texto := public.retorno_ver_caso(1, v_dono, c_agora) ->> 'texto';
    if position('Unidades: 1. Aurora · 2. Canoa' in v_texto) = 0 then
      raise exception '23c: Unidades: %', v_texto;
    end if;

    -- 15. 0 unidades com proposta; criada a unidade, o *retorno* remonta; a rodada grava o vessel_id; o *sim* continua passando.
    perform pg_temp.f3c_limpar();
    perform pg_temp.f3c_sumir(array[v_caso]);
    v_cl := pg_temp.f3c_cli('Nico SemUnidade F3', 904);
    v_caso := pg_temp.f3c_caso(904, 'cliente', v_cl);
    v_pv := pg_temp.f3c_prop(v_caso, v_cl, null, 'historico', 'ORÇ-00904', jsonb_build_object('forte', true, 'fonte_aprovada', true, 'travada', true), 100, 1, 0, c_recente);
    perform pg_temp.f3c_lin(v_pv, 1, 'Peça', 1, 100, 'praticado_cliente', c_recente);
    update public.retorno_previa set hash = public._retorno_previa_hash(null, titulo, public._retorno_previa_linhas_json(id)) where id = v_pv;
    -- A fonte que retorno_previa_montar acha de novo na rodada; precisa da unidade, então nasce com a Nova logo abaixo.
    v_cartao := pg_temp.f3c_cartao(c_agora);
    select i.id, i.acao_sim into v_ip, v_h from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 1;
    perform pg_temp.f3c_igual('15a sem acao antes da unidade', v_h, null);
    if (select c.texto from public.retorno_cartoes c where c.id = v_cartao) not like '%Falta cadastrar a unidade%' then
      raise exception '15b: linha 5';
    end if;
    v_un := pg_temp.f3c_un(v_cl, 'Nova');
    v_os := pg_temp.f3c_os('ORÇ-00904-FONTE', v_cl, v_un, c_agora - interval '30 days', 100);
    update public.service_orders so set problem_description = 'troca de baterias da lancha' where so.id = v_os;
    perform pg_temp.f3c_peca(v_os, v_p, 1, 100);
    perform public.retorno_cartao_abrir('puxar', c_agora + interval '1 minute');
    perform pg_temp.f3c_igual('15c remontou', (select i.acao_sim from public.retorno_cartao_itens i where i.id = v_ip), 'orcar');
    if (select c.texto from public.retorno_cartoes c where c.id = v_cartao) not like '%· Nova:%' then
      raise exception '15d: unidade nova no texto';
    end if;
    v_h := (select i.hash from public.retorno_cartao_itens i where i.id = v_ip);
    v_h2 := (select p.hash from public.retorno_previa p where p.id = v_pv);
    v_r := public.retorno_previa_montar(v_caso, c_agora + interval '2 minutes');
    perform pg_temp.f3c_igual('15e mantida', v_r ->> 'acao', 'mantida');
    if (select p.vessel_id from public.retorno_previa p where p.id = v_pv) is distinct from v_un
       or (select p.hash from public.retorno_previa p where p.id = v_pv) = v_h2 then
      raise exception '15f: rodada não gravou vessel_id ou não mudou o hash';
    end if;
    if (public._retorno_item_conferir(v_ip, c_agora + interval '3 minutes', true) ->> 'ok')::boolean is distinct from true then
      raise exception '15g: conferir devia passar (%)', public._retorno_item_conferir(v_ip, c_agora + interval '3 minutes', true);
    end if;
    if (select i.hash from public.retorno_cartao_itens i where i.id = v_ip) is distinct from v_h then
      raise exception '15h: hash do item mudou';
    end if;

    -- 18. Teto de 3.500: 3 itens com 12 linhas C30 cada, nomes de 40 e preços de 6 dígitos.
    perform pg_temp.f3c_limpar();
    perform pg_temp.f3c_sumir(array[v_caso]);
    v_casos := '{}';
    for i in 1 .. 3 loop
      v_cl := pg_temp.f3c_cli('Pedro' || i || ' Teto F3', 910 + i);
      v_un := pg_temp.f3c_un(v_cl, 'Barco' || i);
      v_caso := pg_temp.f3c_caso(910 + i, 'cliente', v_cl);
      v_casos := v_casos || v_caso;
      v_pv := pg_temp.f3c_prop(v_caso, v_cl, v_un, 'historico', 'ORÇ-0091' || i, jsonb_build_object('forte', false, 'fonte_aprovada', true), 1200000, 12, 0, c_recente);
      for v_n in 1 .. 12 loop
        perform pg_temp.f3c_lin(v_pv, v_n, 'Linha' || v_n || ' de um nome bem comprido com quarenta', 1, 123456.78, 'praticado_outro', c_recente);
      end loop;
    end loop;
    v_cartao := pg_temp.f3c_cartao(c_agora);
    select c.texto into v_texto from public.retorno_cartoes c where c.id = v_cartao;
    if char_length(v_texto) > 3500 then
      raise exception '18a: passou do teto: %', char_length(v_texto);
    end if;
    if v_texto not like '%*sim <PIN>* faz os 3%' then
      raise exception '18b: rodapé ausente: %', right(v_texto, 200);
    end if;
    if v_texto !~ '· e mais [0-9]+: \*ver 1\*' then
      raise exception '18c: sem "e mais": %', left(v_texto, 600);
    end if;
    -- 1 item de 12 linhas sai inteiro.
    perform pg_temp.f3c_limpar();
    perform pg_temp.f3c_sumir(array[v_casos[1], v_casos[2]]);
    v_cartao := pg_temp.f3c_cartao(c_agora);
    select c.texto into v_texto from public.retorno_cartoes c where c.id = v_cartao;
    if v_texto like '%e mais%' or (select count(*) from regexp_matches(v_texto, '   · Linha', 'g')) <> 12 then
      raise exception '18d: 1 item não saiu inteiro';
    end if;

    -- 21. _retorno_cartao_casos: 3 visitas antigas e 1 orçamento novo, com 3 vagas: o orçamento vem antes.
    perform pg_temp.f3c_sumir(array[v_casos[3]]);
    v_cl := pg_temp.f3c_cli('Quito Visita F3', 920);
    for i in 1 .. 3 loop
      v_caso := pg_temp.f3c_caso(920 + i, 'cliente', v_cl, 'preciso trocar as baterias da lancha, quanto custa?', '2026-11-01 09:00-03');
      update public.retorno_aberturas set visita_a_combinar_em = '2026-11-02 09:00-03' where id = v_caso;
    end loop;
    v_caso2 := pg_temp.f3c_caso(924, 'cliente', v_cl, 'preciso trocar as baterias da lancha, quanto custa?', c_agora - interval '10 minutes');
    if (select c.abertura_id from public._retorno_cartao_casos(c_agora, 3) c limit 1) is distinct from v_caso2 then
      raise exception '21: visitas tomaram a vaga do orçamento novo';
    end if;
    if (select c.prioridade from public._retorno_cartao_casos(c_agora, 100) c where c.abertura_id = v_caso) <> 7 then
      raise exception '21b: visita não ficou na prioridade 7';
    end if;

    -- ═══ Revisão da F3. Rascunho antigo e proposta ditada depois dele: vale o ditado (linha 2); rascunho feito depois do ditado volta a vencer.
    perform pg_temp.f3c_limpar();
    perform pg_temp.f3c_sumir(array(select a.id from public.retorno_aberturas a where a.phone_normalized like '55479008%'));
    update public.retorno_config set previa_modo = 'ligado', previa_ditado_ligado = true where id;
    v_cl := pg_temp.f3c_cli('Olavo Noite F3', 930);
    v_un := pg_temp.f3c_un(v_cl, 'Noturna');
    v_caso := pg_temp.f3c_caso(930, 'cliente', v_cl);
    v_os := pg_temp.f3c_os('ORÇ-00930', v_cl, v_un, c_agora - interval '3 days', 700);
    perform pg_temp.f3c_peca(v_os, v_p, 1, 700);
    perform pg_temp.f3c_igual('R1 só o rascunho', pg_temp.f3c_item(v_caso) ->> 'acao_sim', 'pdf');
    v_pv := pg_temp.f3c_prop(v_caso, v_cl, v_un, 'ditado', null, '{}', 800, 1, 0, null);
    perform pg_temp.f3c_lin(v_pv, 1, 'Peça ditada', 1, 800, 'dito', null);
    update public.retorno_previa set criada_em = c_agora - interval '1 hour' where id = v_pv;
    v_item := pg_temp.f3c_item(v_caso);
    perform pg_temp.f3c_igual('R2 o ditado vence o rascunho antigo', v_item ->> 'acao_sim', 'orcar');
    perform pg_temp.f3c_igual('R3 a proposta no item', v_item ->> 'previa_id', v_pv::text);
    update public.service_orders so set created_at = c_agora - interval '10 minutes' where so.id = v_os;
    perform pg_temp.f3c_igual('R4 rascunho depois do ditado', pg_temp.f3c_item(v_caso) ->> 'acao_sim', 'pdf');
    update public.retorno_previa
       set origem = 'historico', fonte_numero = 'ORÇ-00500', fonte_em = '2026-08-12 10:00-03', criada_em = c_agora - interval '5 days',
           dados = jsonb_build_object('forte', true, 'fonte_aprovada', true, 'ajustada_por_ditado', true, 'ditada_em', c_agora - interval '1 minute')
     where id = v_pv;
    perform pg_temp.f3c_igual('R5 ajustada depois do rascunho', pg_temp.f3c_item(v_caso) ->> 'acao_sim', 'orcar');

    -- ═══ Revisão da F3. Número novo: a proposta nasceu sem client_id; a rodada grava cliente e unidade, e o hash que o dono viu não muda.
    perform pg_temp.f3c_limpar();
    perform pg_temp.f3c_sumir(array[v_caso]);
    v_cl := pg_temp.f3c_cli('Zeca Provisorio F3');
    v_un := pg_temp.f3c_un(v_cl, 'Unica');
    v_caso := pg_temp.f3c_caso(931, 'numero_novo', null);
    insert into public.audit_log (table_name, record_id, action, changed_by, new_value, reason)
    values ('clients', v_cl, 'lead_converted', 'retorno', jsonb_build_object('caso', v_caso), 'teste');
    v_pv := pg_temp.f3c_prop(v_caso, null, null, 'historico', 'ORÇ-00931', jsonb_build_object('forte', true, 'fonte_aprovada', true, 'travada', true), 100, 1, 0, c_recente);
    perform pg_temp.f3c_lin(v_pv, 1, 'Peça', 1, 100, 'praticado_cliente', c_recente);
    update public.retorno_previa set hash = public._retorno_previa_hash(null, titulo, public._retorno_previa_linhas_json(id)) where id = v_pv;
    v_h := public._retorno_previa_hash_efetivo(v_pv, c_agora);
    v_cartao := pg_temp.f3c_cartao(c_agora);
    select i.id into v_ip from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 1;
    perform pg_temp.f3c_igual('R6 orcar sem client_id na proposta', (select i.acao_sim from public.retorno_cartao_itens i where i.id = v_ip), 'orcar');
    update public.retorno_previa set client_id = v_cl, vessel_id = v_un, hash = public._retorno_previa_hash(v_un, titulo, public._retorno_previa_linhas_json(id)) where id = v_pv;
    perform pg_temp.f3c_igual('R7 hash efetivo igual depois da rodada', public._retorno_previa_hash_efetivo(v_pv, c_agora), v_h);
    if (public._retorno_item_conferir(v_ip, c_agora + interval '1 minute', true) ->> 'ok')::boolean is distinct from true then
      raise exception 'R8: conferir devia passar (%)', public._retorno_item_conferir(v_ip, c_agora + interval '1 minute', true);
    end if;

    raise exception 'retorno_f3_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f3_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f3_cartao', true, '{}');
end
$cartao$;

select arquivo, ok, numeros from _bancada order by em;
rollback;

-- Retorno F3 (P6): decidir as letras novas, preparar o orçamento e as RPCs que a ferramenta chama (P8). Roda só pela bancada (grupo 5).
-- Termina em ROLLBACK, e o bloco se desfaz sozinho. Relógio em ter 10/11/2026 15:00. Telefones 55479007xxxxx; frases inventadas.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f3d_caso(p_n integer, p_papel text, p_cliente uuid,
                                            p_corpo text default 'FRASE-MARCADA-F3 preciso trocar as baterias da lancha, quanto custa?',
                                            p_aberta timestamptz default '2026-11-10 13:00-03') returns uuid
language plpgsql as $f$
declare
  v_fone text := '55479007' || lpad(p_n::text, 5, '0');
  v_chave text := public._agenda_chave_telefone(v_fone);
  v_msg uuid;
  v_id uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
  values ('inbound', v_fone, 'text', p_corpo, 'received', '{"data": {}}'::jsonb, p_aberta, p_aberta)
  returning id into v_msg;
  insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, clientes, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, estado, modo)
  values (v_chave, v_fone, '47', p_papel, jsonb_build_object('papel', p_papel), p_cliente,
          case when p_papel = 'cliente_ambiguo' then array[p_cliente] else '{}'::uuid[] end, v_msg, v_msg, p_aberta,
          p_aberta, p_aberta, p_aberta, 'recibo', 'recibo_cliente', 'aberta', 'sombra')
  returning id into v_id;
  insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, sinais, pede_resposta)
  values (v_msg, v_id, v_chave, p_aberta, p_aberta, md5(p_corpo), public._retorno_sinais(p_corpo), true);
  return v_id;
end $f$;

create or replace function pg_temp.f3d_cli(p_nome text, p_n integer default null) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, case when p_n is not null then '(47) 90070-' || lpad(p_n::text, 4, '0') end) returning id;
$f$;

create or replace function pg_temp.f3d_un(p_cli uuid, p_nome text, p_tipo text default 'Lancha') returns uuid
language sql as $f$
  insert into public.vessels (client_id, name, asset_type) values (p_cli, p_nome, p_tipo) returning id;
$f$;

-- Proposta direta, com as linhas, para o que não depende do parecido.
create or replace function pg_temp.f3d_prop(p_caso uuid, p_cli uuid, p_ves uuid, p_origem text, p_numero text, p_dados jsonb, p_total numeric,
                                            p_linhas integer, p_prov integer, p_estado text default 'proposta') returns uuid
language sql as $f$
  insert into public.retorno_previa (abertura_id, chave, client_id, vessel_id, origem, fonte_numero, fonte_em, familias, titulo, estado, modo, total, linhas_n, provisorios_n, preco_mais_antigo, hash, dados, linhas_iniciais)
  select a.id, a.chave, p_cli, p_ves, p_origem, p_numero, case when p_numero is not null then timestamptz '2026-08-12 10:00-03' end, array['bateria'], 'Baterias', p_estado,
         case when p_estado = 'sombra' then 'sombra' else 'ligado' end, p_total, p_linhas, p_prov, date '2026-08-12', 'hash-teste', p_dados, '[{"inicial": true}]'
    from public.retorno_aberturas a where a.id = p_caso
  returning id;
$f$;

create or replace function pg_temp.f3d_lin(p_previa uuid, p_ordem integer, p_nome text, p_qtd numeric, p_preco numeric, p_fonte text,
                                           p_estado text default 'ok', p_motivo text default null, p_tipo text default 'peca', p_prod uuid default null, p_serv uuid default null) returns void
language sql as $f$
  insert into public.retorno_previa_linhas (previa_id, ordem, tipo, product_id, service_id, nome, quantidade, preco, preco_fonte, preco_em, estado, motivo)
  values (p_previa, p_ordem, p_tipo, p_prod, p_serv, p_nome, p_qtd, p_preco, p_fonte, case when p_fonte in ('catalogo', 'dito', 'sem_preco') then null else date '2026-08-12' end, p_estado, p_motivo);
$f$;

create or replace function pg_temp.f3d_prod(p_nome text) returns uuid
language sql as $f$
  insert into public.products (name, stock_quantity, sale_price, active) values (p_nome, 0, 10, true) returning id;
$f$;

create or replace function pg_temp.f3d_serv(p_nome text) returns uuid
language sql as $f$
  insert into public.services (name, billing_unit, default_price, active) values (p_nome, 'hour', 10, true) returning id;
$f$;

create or replace function pg_temp.f3d_os(p_num text, p_cli uuid, p_un uuid, p_em timestamptz, p_total numeric, p_desc text default 'troca de baterias da lancha') returns uuid
language sql as $f$
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, problem_description, created_at, updated_at, grand_total)
  values (p_num, p_cli, p_un, 'draft', 'draft', 'repair', p_desc, p_em, p_em, p_total)
  returning id;
$f$;

create or replace function pg_temp.f3d_peca(p_os uuid, p_prod uuid, p_qtd numeric, p_preco numeric) returns void
language sql as $f$
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot, line_total_cost, line_total_sale)
  values (p_os, p_prod, p_qtd, 1, p_preco, p_qtd, p_qtd * p_preco);
$f$;

create or replace function pg_temp.f3d_igual(p_rot text, p_valor text, p_esp text) returns void
language plpgsql as $f$
begin
  if p_valor is distinct from p_esp then
    raise exception '%: %, esperava %', p_rot, coalesce(p_valor, '∅'), coalesce(p_esp, '∅');
  end if;
end $f$;

create or replace function pg_temp.f3d_limpar() returns void
language sql as $f$
  update public.ai_operator_pending_actions set status = 'expired' where status = 'pending';
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste' where status = 'aberta';
  update public.retorno_cartoes set estado = 'decidido', decidido_em = now(), decidido_por = 'nao' where estado = 'vivo';
$f$;

-- O cartão com os casos do teste que estão abertos; devolve o id. Casos fechados por f3d_fechar não entram.
create or replace function pg_temp.f3d_cartao(p_agora timestamptz default '2026-11-10 15:00-03') returns uuid
language plpgsql as $f$
declare
  v_r jsonb;
begin
  perform pg_temp.f3d_limpar();
  v_r := public.retorno_cartao_abrir('puxar', p_agora);
  if v_r ->> 'acao' <> 'cartao' then
    raise exception 'cartão não abriu: %', v_r;
  end if;
  return (v_r ->> 'cartao_id')::uuid;
end $f$;

create or replace function pg_temp.f3d_fechar(p_casos uuid[]) returns void
language sql as $f$
  update public.retorno_aberturas set estado = 'fechada', fechada_em = now(), fechada_motivo = 'expirou' where id = any (p_casos);
$f$;

-- O id do item do caso no cartão.
create or replace function pg_temp.f3d_item(p_cartao uuid, p_n integer) returns uuid
language sql as $f$
  select i.id from public.retorno_cartao_itens i where i.cartao_id = p_cartao and i.n = p_n;
$f$;

create or replace function pg_temp.f3d_letra(p_n integer, p_letra text, p_autor uuid, p_agora timestamptz default '2026-11-10 15:00-03') returns jsonb
language sql as $f$
  select public.retorno_decidir_dito(jsonb_build_object('comando', 'escolher', 'n', p_n, 'letra', p_letra, 'resto', null), p_autor, p_agora);
$f$;

do $decidir$
declare
  c_agora constant timestamptz := '2026-11-10 15:00-03';
  c_noite constant timestamptz := '2026-11-10 21:00-03';
  c_outro constant uuid := 'b1600000-0000-4000-8000-0000000009f7';
  v_dono uuid;
  v_phone text;
  v_prod uuid; v_serv uuid;
  v_cl uuid; v_cl2 uuid;
  v_un uuid; v_un2 uuid;
  v_caso uuid; v_caso2 uuid;
  v_pv uuid; v_pv2 uuid;
  v_os uuid; v_os2 uuid;
  v_cartao uuid;
  v_ip uuid; v_ip2 uuid;
  v_ses uuid; v_ses2 uuid;
  v_r jsonb; v_r2 jsonb;
  v_t text; v_h text;
  v_n integer;
  v_prev public.retorno_previa;
  v_gen uuid;
begin
  begin
    select d.id, d.phone into v_dono, v_phone from public._comprovante_dono() d;
    perform pg_temp.f3d_limpar();
    update public.ai_operator_sessions set metadata = metadata - 'pendencias_guardadas' where external_thread_key = v_phone;
    update public.retorno_config set modo = 'ligado', tipos_ligados = '{}', cartao_ligado = true, cartao_max_itens = 3, previa_modo = 'ligado', previa_ditado_ligado = true,
           previa_max_linhas = 12, previa_preco_velho = interval '180 days', previa_idade_max = interval '18 months', validade_orcamento_dias = 7, segura_tudo_ate = null where id;
    update public.retorno_modelo_tipos set nivel = 'cartao';
    v_prod := pg_temp.f3d_prod('Produto Decidir F3');
    v_serv := pg_temp.f3d_serv('Serviço Decidir F3');

    -- ═══ 16. Contrato: os nomes dos parâmetros das RPCs que orcarEEnviar chama.
    if (select string_agg(p.proargnames::text, ' ' order by p.proname)
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname in ('retorno_previa_preparar', 'retorno_previa_caiu', 'retorno_previa_soltar', 'retorno_previa_orc_criado', 'retorno_previa_pdf',
                                                      'retorno_previa_ver', 'retorno_previa_retrato', 'retorno_previa_aplicar', 'retorno_legenda_do_orcamento'))
       is distinct from '{p_abertura,p_previa,p_agora,p_client} {p_previa,p_plano,p_autor,p_agora,p_item} {p_previa,p_item,p_motivo,p_agora} {p_previa,p_so,p_agora} {p_previa,p_ok,p_chave,p_agora,p_so,p_abertura,p_item} {p_previa,p_item,p_autor,p_agora,p_so} {p_abertura,p_previa,p_hash,p_phone,p_autor,p_agora} {p_item,p_agora} {p_n,p_autor,p_agora}' then
      raise exception '16: contrato das RPCs diverge';
    end if;
    if (select p.provolatile from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'retorno_previa_ver') <> 's' then
      raise exception '25a: retorno_previa_ver devia ser STABLE';
    end if;

    -- ═══ 1, 3, 6, 17. Item de proposta real, com dois parecidos, para as letras.
    v_cl := pg_temp.f3d_cli('Rodrigo Decidir F3', 101);
    v_un := pg_temp.f3d_un(v_cl, 'Brisa');
    v_os := pg_temp.f3d_os('ORÇ-D001', v_cl, v_un, '2026-08-01 10:00-03', 1000);
    perform pg_temp.f3d_peca(v_os, v_prod, 1, 1000);
    v_os2 := pg_temp.f3d_os('ORÇ-D002', v_cl, v_un, '2026-09-01 10:00-03', 2000);
    perform pg_temp.f3d_peca(v_os2, v_prod, 2, 1000);
    v_caso := pg_temp.f3d_caso(101, 'cliente', v_cl);
    v_r := public.retorno_previa_montar(v_caso, c_agora);
    perform pg_temp.f3d_igual('0 montou', v_r ->> 'acao', 'criada');
    v_pv := (v_r ->> 'previa_id')::uuid;
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_ip := pg_temp.f3d_item(v_cartao, 1);
    select c.pendencia_id, c.sessao_id into v_h, v_ses from public.retorno_cartoes c where c.id = v_cartao;
    perform pg_temp.f3d_igual('1a acao', (select i.acao_sim from public.retorno_cartao_itens i where i.id = v_ip), 'orcar');
    -- O mais recente é o ORÇ-D002: é a fonte, e o outro (*B*) é o D001.
    select * into v_prev from public.retorno_previa where id = v_pv;
    perform pg_temp.f3d_igual('1b fonte', v_prev.fonte_numero, 'ORÇ-D002');

    -- Letra inexistente (2): "não tem a opção".
    v_r := pg_temp.f3d_letra(1, 'G', v_dono);
    perform pg_temp.f3d_igual('2 letra inexistente', v_r ->> 'texto', 'O caso 1 não tem a opção G, e nada foi feito.');

    -- 3. *L*: acao_sim nula depois da letra.
    v_r := pg_temp.f3d_letra(1, 'L', v_dono);
    if not (v_r ->> 'precisa_pin')::boolean or v_r ->> 'texto' not like 'Vou mandar a %: ''%''. *sim <PIN>* manda.' then
      raise exception '3a: L (%)', v_r;
    end if;
    perform pg_temp.f3d_igual('3a2 L segue valendo com o PIN', v_r ->> 'pin_nao_vale', null);
    perform pg_temp.f3d_igual('3b acao depois do L', (select i.acao_sim from public.retorno_cartao_itens i where i.id = v_ip), null);
    perform pg_temp.f3d_igual('3c modelo', (select i.modelo_tipo from public.retorno_cartao_itens i where i.id = v_ip), 'modelo_ver_no_local');
    perform pg_temp.f3d_igual('3d previa intacta', (select i.previa_id::text from public.retorno_cartao_itens i where i.id = v_ip), v_pv::text);

    -- Depois de *L*, a letra *B* devolve acao_sim = 'orcar' (remonta o item).
    v_r := pg_temp.f3d_letra(1, 'B', v_dono);
    if v_r ->> 'texto' not like '%ORÇ-D001%' then
      raise exception '1c: B devia usar o outro parecido: %', v_r;
    end if;
    perform pg_temp.f3d_igual('1c2 o PIN junto da letra não vale', v_r ->> 'pin_nao_vale', 'true');
    perform pg_temp.f3d_igual('3e acao depois do B', (select i.acao_sim from public.retorno_cartao_itens i where i.id = v_ip), 'orcar');
    select * into v_prev from public.retorno_previa where id = v_pv;
    perform pg_temp.f3d_igual('1d anterior descartada', v_prev.estado, 'descartada');
    select p.* into v_prev from public.retorno_previa p where p.abertura_id = v_caso and p.estado = 'proposta';
    perform pg_temp.f3d_igual('1e nova fonte', v_prev.fonte_numero, 'ORÇ-D001');
    v_pv := v_prev.id;
    perform pg_temp.f3d_igual('1f item na nova', (select i.previa_id::text from public.retorno_cartao_itens i where i.id = v_ip), v_pv::text);
    -- *B* com a proposta desligada (ditado segue ligado): frase, nada muda.
    update public.retorno_config set previa_modo = 'sombra' where id;
    v_r := pg_temp.f3d_letra(1, 'B', v_dono);
    perform pg_temp.f3d_igual('1g frase desligado', v_r ->> 'texto', 'O orçamento pelo cartão está desligado: nada mudou.');
    perform pg_temp.f3d_igual('1g2 PIN não vale sem mudança', v_r ->> 'pin_nao_vale', 'true');
    if (select p.estado from public.retorno_previa p where p.id = v_pv) <> 'proposta' then
      raise exception '1h: mudou a proposta com a flag desligada';
    end if;
    update public.retorno_config set previa_modo = 'ligado' where id;

    -- 3 (cont.): *L* + executar a partir da linha 2.
    v_r := pg_temp.f3d_letra(1, 'L', v_dono);
    perform pg_temp.f3d_igual('3f acao', (select i.acao_sim from public.retorno_cartao_itens i where i.id = v_ip), null);
    v_r := public.retorno_cartao_executar(v_cartao, v_dono, c_agora);
    if jsonb_array_length(v_r -> 'orcamentos') <> 0 then
      raise exception '3g: orcamentos devia ficar vazio com *L*: %', v_r;
    end if;
    if (v_r ->> 'vai_sair')::integer <> 1 then
      raise exception '3h: vai_sair %', v_r;
    end if;
    if (select s.tipo || '/' || s.estado from public.retorno_saidas s where s.abertura_id = v_caso and s.tipo = 'modelo_ver_no_local') <> 'modelo_ver_no_local/agendada' then
      raise exception '3i: saída M07';
    end if;
    if (select p.estado from public.retorno_previa p where p.id = v_pv) <> 'ver_no_local'
       or (select p.decidida_em from public.retorno_previa p where p.id = v_pv) is distinct from c_agora then
      raise exception '3j: proposta devia ir a ver_no_local com decidida_em';
    end if;
    perform pg_temp.f3d_fechar(array[v_caso]);

    -- ═══ 3k. *L* a partir da linha 1 (rascunho, 'pdf').
    v_cl := pg_temp.f3d_cli('Paulo Rascunho F3', 102);
    v_un := pg_temp.f3d_un(v_cl, 'Vento');
    v_caso := pg_temp.f3d_caso(102, 'cliente', v_cl);
    v_os := pg_temp.f3d_os('ORÇ-D051', v_cl, v_un, c_agora - interval '1 hour', 500);
    perform pg_temp.f3d_peca(v_os, v_prod, 1, 500);
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_ip := pg_temp.f3d_item(v_cartao, 1);
    perform pg_temp.f3d_igual('3k pdf', (select i.acao_sim from public.retorno_cartao_itens i where i.id = v_ip), 'pdf');
    v_r := pg_temp.f3d_letra(1, 'L', v_dono);
    perform pg_temp.f3d_igual('3l acao nula', (select i.acao_sim from public.retorno_cartao_itens i where i.id = v_ip), null);
    v_r := public.retorno_cartao_executar(v_cartao, v_dono, c_agora);
    if jsonb_array_length(v_r -> 'orcamentos') <> 0 or (select count(*) from public.retorno_saidas s where s.abertura_id = v_caso and s.tipo = 'modelo_ver_no_local') <> 1 then
      raise exception '3m: M07 a partir do rascunho: %', v_r;
    end if;
    perform pg_temp.f3d_fechar(array[v_caso]);

    -- ═══ Letra de unidade (17, 14).
    v_cl := pg_temp.f3d_cli('Marta Unidade F3', 103);
    perform pg_temp.f3d_un(v_cl, 'Alma');
    v_un := pg_temp.f3d_un(v_cl, 'Vaga');
    v_caso := pg_temp.f3d_caso(103, 'cliente', v_cl);
    v_pv := pg_temp.f3d_prop(v_caso, v_cl, null, 'historico', 'ORÇ-D103', jsonb_build_object('forte', true, 'fonte_aprovada', true), 500, 1, 0);
    perform pg_temp.f3d_lin(v_pv, 1, 'Peça', 1, 500, 'praticado_cliente', 'ok', null, 'peca', v_prod);
    v_pv2 := pg_temp.f3d_prop(v_caso, v_cl, null, 'historico', 'ORÇ-D103', jsonb_build_object('forte', true, 'fonte_aprovada', true), 500, 1, 0, 'sombra');
    perform pg_temp.f3d_lin(v_pv2, 1, 'Peça', 1, 500, 'praticado_cliente', 'ok', null, 'peca', v_prod);
    update public.retorno_previa set hash = public._retorno_previa_hash(null, titulo, public._retorno_previa_linhas_json(id)) where id in (v_pv, v_pv2);
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_ip := pg_temp.f3d_item(v_cartao, 1);
    perform pg_temp.f3d_igual('14a C e F', (select string_agg(o ->> 'letra', ',' order by o ->> 'letra') from public.retorno_cartao_itens i, jsonb_array_elements(i.opcoes) o where i.id = v_ip), 'C,F,L');
    v_h := (select p.hash from public.retorno_previa p where p.id = v_pv);
    v_r := pg_temp.f3d_letra(1, 'F', v_dono);   -- a 2ª da lista é a Vaga
    perform pg_temp.f3d_igual('17a2 PIN não vale na letra de unidade', v_r ->> 'pin_nao_vale', 'true');
    perform pg_temp.f3d_igual('17a abertura', (select a.unidade_escolhida_id::text from public.retorno_aberturas a where a.id = v_caso), v_un::text);
    select * into v_prev from public.retorno_previa where id = v_pv;
    perform pg_temp.f3d_igual('17b vessel', v_prev.vessel_id::text, v_un::text);
    if v_prev.hash = v_h or v_prev.hash <> public._retorno_previa_hash(v_un, v_prev.titulo, public._retorno_previa_linhas_json(v_pv)) then
      raise exception '17c: hash';
    end if;
    if not (v_prev.dados ->> 'travada')::boolean then
      raise exception '17d: travada';
    end if;
    perform pg_temp.f3d_igual('17e sombra', (select p.vessel_id::text from public.retorno_previa p where p.id = v_pv2), v_un::text);
    perform pg_temp.f3d_igual('17f item remontou', (select i.acao_sim from public.retorno_cartao_itens i where i.id = v_ip), 'orcar');
    -- A rodada seguinte mantém e não descarta.
    v_os := pg_temp.f3d_os('ORÇ-D104-F', v_cl, v_un, '2026-09-20 10:00-03', 500);
    perform pg_temp.f3d_peca(v_os, v_prod, 1, 500);
    update public.retorno_config set previa_modo = 'sombra' where id;
    v_r := public.retorno_previa_montar(v_caso, c_agora + interval '1 minute');
    perform pg_temp.f3d_igual('17g sombra mantida', v_r ->> 'acao', 'mantida');
    update public.retorno_config set previa_modo = 'ligado' where id;
    v_r := public.retorno_previa_montar(v_caso, c_agora + interval '1 minute');
    perform pg_temp.f3d_igual('17h proposta mantida', v_r ->> 'acao', 'mantida');
    if (select p.estado from public.retorno_previa p where p.id = v_pv) <> 'proposta' then
      raise exception '17i: a rodada descartou a travada';
    end if;
    -- Unidade inativa recusa.
    update public.vessels set active = false where id = v_un;
    update public.retorno_cartao_itens set opcoes = jsonb_build_array(jsonb_build_object('letra', 'F', 'acao', 'unidade', 'vessel_id', v_un, 'rotulo', 'Vaga')) where id = v_ip;
    v_r := pg_temp.f3d_letra(1, 'F', v_dono);
    if v_r ->> 'texto' not like '%já não vale para este cliente%' then
      raise exception '17j: unidade inativa: %', v_r;
    end if;
    update public.vessels set active = true where id = v_un;
    -- Sem proposta: só a primeira gravação.
    perform pg_temp.f3d_fechar(array[v_caso]);
    v_cl := pg_temp.f3d_cli('Ivo SemProposta F3', 104);
    perform pg_temp.f3d_un(v_cl, 'Alfa');
    v_un := pg_temp.f3d_un(v_cl, 'Beta');
    v_caso := pg_temp.f3d_caso(104, 'cliente', v_cl);
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_ip := pg_temp.f3d_item(v_cartao, 1);
    v_r := pg_temp.f3d_letra(1, 'F', v_dono);
    perform pg_temp.f3d_igual('17k só abertura', (select a.unidade_escolhida_id::text from public.retorno_aberturas a where a.id = v_caso), v_un::text);
    if exists (select 1 from public.retorno_previa p where p.abertura_id = v_caso) then
      raise exception '17l: criou proposta';
    end if;
    if v_r ->> 'texto' not like '%Dite o orçamento em áudio%' then
      raise exception '17m: linha depois da letra: %', v_r;
    end if;
    perform pg_temp.f3d_fechar(array[v_caso]);

    -- ═══ 4, 5, 18. Executar.
    v_cl := pg_temp.f3d_cli('Ana Exec F3', 105);
    v_un := pg_temp.f3d_un(v_cl, 'Rio');
    v_caso := pg_temp.f3d_caso(105, 'cliente', v_cl);
    v_pv := pg_temp.f3d_prop(v_caso, v_cl, v_un, 'historico', 'ORÇ-D105', jsonb_build_object('forte', true, 'fonte_aprovada', true), 500, 1, 0);
    perform pg_temp.f3d_lin(v_pv, 1, 'Peça', 1, 500, 'praticado_cliente', 'ok', null, 'peca', v_prod);
    v_cl2 := pg_temp.f3d_cli('Bia Exec F3', 106);
    v_un2 := pg_temp.f3d_un(v_cl2, 'Mar');
    v_caso2 := pg_temp.f3d_caso(106, 'cliente', v_cl2, 'preciso trocar as baterias da lancha, quanto custa?', '2026-11-10 13:30-03');
    v_pv2 := pg_temp.f3d_prop(v_caso2, v_cl2, v_un2, 'ditado', null, '{}', 700, 1, 0);
    perform pg_temp.f3d_lin(v_pv2, 1, 'Peça 2', 1, 700, 'dito', 'ok', null, 'peca', v_prod);
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_r := public.retorno_cartao_executar(v_cartao, v_dono, c_agora);
    if (v_r ->> 'vai_sair')::integer <> 0 or v_r ->> 'aviso' like '%Vai sair%' or v_r ->> 'aviso' like '%Nada para mandar%' then
      raise exception '18a: só orçamentos: %', v_r;
    end if;
    if jsonb_array_length(v_r -> 'orcamentos') <> 2 or v_r -> 'orcamentos' -> 0 ->> 'n' <> '1' or v_r -> 'orcamentos' -> 0 ->> 'previa_id' <> v_pv::text
       or v_r -> 'orcamentos' -> 0 ->> 'acao' <> 'orcar' or v_r -> 'orcamentos' -> 0 ->> 'rotulo' is null then
      raise exception '4a: orcamentos: %', v_r;
    end if;
    if (select i.estado from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 1) <> 'feito'
       or (select i.decidido_em from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 1) is null then
      raise exception '4b: item devia ir a feito, com decidido_em';
    end if;
    if (select c.estado from public.retorno_cartoes c where c.id = v_cartao) <> 'decidido' then
      raise exception '4c: cartão devia ser decidido';
    end if;

    -- 4 (provisório): caiu, frase, sem *dita*, orcamentos vazio. Os casos voltam ao cartão com itens novos.
    perform pg_temp.f3d_fechar(array[v_caso2]);
    update public.retorno_aberturas set estado = 'aberta', fechada_em = null, fechada_motivo = null where id = v_caso;
    update public.retorno_previa_linhas set estado = 'provisorio', preco = null, preco_fonte = 'sem_preco', preco_em = null, motivo = 'sem_preco', nome = 'Bateria Z' where previa_id = v_pv;
    update public.retorno_previa set provisorios_n = 1, total = 0, estado = 'proposta' where id = v_pv;
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_ip := pg_temp.f3d_item(v_cartao, 1);
    perform pg_temp.f3d_igual('4d acao orcar com provisório', (select i.acao_sim from public.retorno_cartao_itens i where i.id = v_ip), 'orcar');
    v_r := public.retorno_cartao_executar(v_cartao, v_dono, c_agora);
    if jsonb_array_length(v_r -> 'orcamentos') <> 0 or (v_r ->> 'aviso') like '%*dita%' or (v_r ->> 'aviso') not like '%tem item a completar (Bateria Z): não criei nada%' then
      raise exception '4e: provisório: %', v_r;
    end if;
    perform pg_temp.f3d_igual('4f caiu', (select i.estado || '/' || i.caiu_motivo from public.retorno_cartao_itens i where i.id = v_ip), 'caiu/item_provisorio');
    update public.retorno_previa_linhas set estado = 'ok', preco = 500, preco_fonte = 'praticado_cliente', preco_em = date '2026-08-12', motivo = null, nome = 'Peça' where previa_id = v_pv;
    update public.retorno_previa set provisorios_n = 0, total = 500 where id = v_pv;

    -- 5a. modo sombra: frase, item fora, nada em orcamentos.
    update public.retorno_config set modo = 'sombra', tipos_ligados = '{}' where id;
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_r := public.retorno_cartao_executar(v_cartao, v_dono, c_agora);
    if jsonb_array_length(v_r -> 'orcamentos') <> 0 or (v_r ->> 'aviso') not like '%O retorno está em teste: não mandei.%' then
      raise exception '5a: sombra: %', v_r;
    end if;
    perform pg_temp.f3d_igual('5b item fora', (select i.estado from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 1), 'fora');
    update public.retorno_config set modo = 'ligado' where id;

    -- 5c. Fora de 8h–20h: item fora, frase, orcamentos vazio.
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_r := public.retorno_cartao_executar(v_cartao, v_dono, c_noite);
    if jsonb_array_length(v_r -> 'orcamentos') <> 0 or (v_r ->> 'aviso') not like '%o 1: fora do horário de envio; não criei nada. Mande *retorno* a partir das 8h%' then
      raise exception '5c: noite: %', v_r;
    end if;
    perform pg_temp.f3d_igual('5d fora', (select i.estado from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 1), 'fora');

    -- 5e. Flag desligada com o cartão vivo: frase, item fora.
    v_cartao := pg_temp.f3d_cartao(c_agora);
    update public.retorno_config set previa_modo = 'sombra' where id;
    v_r := public.retorno_cartao_executar(v_cartao, v_dono, c_agora);
    if (v_r ->> 'aviso') not like '%o 1 não saiu, porque o orçamento pelo cartão foi desligado; não criei nada%' then
      raise exception '5e: flag desligada: %', v_r;
    end if;
    update public.retorno_config set previa_modo = 'ligado' where id;

    -- 5e2. A reversão documentada: as duas flags desligadas com o cartão vivo. Item fora e "foi desligado", não "mudou".
    v_cartao := pg_temp.f3d_cartao(c_agora);
    update public.retorno_config set previa_modo = 'desligado', previa_ditado_ligado = false where id;
    v_r := public.retorno_cartao_executar(v_cartao, v_dono, c_agora);
    if (v_r ->> 'aviso') not like '%o 1 não saiu, porque o orçamento pelo cartão foi desligado; não criei nada%' or jsonb_array_length(v_r -> 'orcamentos') <> 0 then
      raise exception '5e2: reversão completa: %', v_r;
    end if;
    perform pg_temp.f3d_igual('5e3 item fora', (select i.estado from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 1), 'fora');
    update public.retorno_config set previa_modo = 'ligado', previa_ditado_ligado = true where id;

    -- 18 (cont.). Um modelo e um orçamento: "Vai sair 1: rótulo do modelo", sem o rótulo do orçamento.
    perform pg_temp.f3d_fechar(array[v_caso]);
    v_cl := pg_temp.f3d_cli('Carla Modelo F3', 107);
    v_un := pg_temp.f3d_un(v_cl, 'Sol');
    v_caso := pg_temp.f3d_caso(107, 'cliente', v_cl);
    v_pv := pg_temp.f3d_prop(v_caso, v_cl, v_un, 'historico', 'ORÇ-D107', jsonb_build_object('forte', true, 'fonte_aprovada', true), 500, 1, 0);
    perform pg_temp.f3d_lin(v_pv, 1, 'Peça', 1, 500, 'praticado_cliente', 'ok', null, 'peca', v_prod);
    v_cl2 := pg_temp.f3d_cli('Dora Modelo F3', 108);
    v_un2 := pg_temp.f3d_un(v_cl2, 'Lua');
    insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, grand_total)
    values ('OS-D108', v_cl2, v_un2, 'awaiting_parts', 'approved', 'repair', '2026-10-01 12:00-03', '2026-10-01 12:00-03', '2026-10-01 12:00-03', 100);
    insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, atualizado_em)
    select so.id, 'dono', 'compressor', 1, 0, true, 'falta', 'dono', '2026-10-22 10:00-03' from public.service_orders so where so.service_order_number = 'OS-D108';
    v_caso2 := pg_temp.f3d_caso(108, 'cliente', v_cl2, 'como tá o motorhome?', '2026-11-10 13:30-03');
    v_cartao := pg_temp.f3d_cartao(c_agora);
    if (select count(*) from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.modelo_tipo is not null) <> 1 then
      raise exception '18b: devia ter 1 modelo';
    end if;
    v_r := public.retorno_cartao_executar(v_cartao, v_dono, c_agora);
    if (v_r ->> 'vai_sair')::integer <> 1 or (v_r ->> 'aviso') like '%' || (v_r -> 'orcamentos' -> 0 ->> 'rotulo') || '%' or jsonb_array_length(v_r -> 'orcamentos') <> 1
       or (v_r ->> 'aviso') not like 'Vai sair 1: %' then
      raise exception '18c: modelo e orçamento: %', v_r;
    end if;
    perform pg_temp.f3d_fechar(array[v_caso, v_caso2]);

    -- ═══ 6, 7, 8, 26, 27, 28. retorno_previa_preparar, no caminho do cartão (item feito) e no do ditado (item vivo).
    v_cl := pg_temp.f3d_cli('Eva Preparar F3', 109);
    v_un := pg_temp.f3d_un(v_cl, 'Bora');
    v_caso := pg_temp.f3d_caso(109, 'cliente', v_cl);
    v_pv := pg_temp.f3d_prop(v_caso, v_cl, v_un, 'historico', 'ORÇ-D109', jsonb_build_object('forte', true, 'fonte_aprovada', true), 1800, 2, 0);
    perform pg_temp.f3d_lin(v_pv, 1, 'Bateria', 2, 500, 'praticado_cliente', 'ok', null, 'peca', v_prod);
    perform pg_temp.f3d_lin(v_pv, 2, 'Instalação', 1, 800, 'praticado_cliente', 'ok', null, 'servico', null, v_serv);
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_ip := pg_temp.f3d_item(v_cartao, 1);

    -- Passou: devolutiva única, com args do construtor, sem validade vinda do modelo.
    v_r := public.retorno_previa_preparar(v_pv, v_ip, v_dono, c_agora);
    if (v_r ->> 'ok')::boolean is distinct from true or v_r ->> 'acao' is distinct from 'orcar' or v_r ->> 'previa_id' is distinct from v_pv::text or v_r ->> 'abertura_id' is distinct from v_caso::text
       or (v_r ->> 'total')::numeric is distinct from 1800 or v_r ->> 'chave8' is distinct from public._agenda_chave_telefone('5547900700109')
       or v_r ->> 'validade_data' is distinct from '2026-11-17' or v_r -> 'legenda' ->> 'validade_data' is distinct from '2026-11-17'
       or (v_r -> 'args' ->> 'client_id')::uuid is distinct from v_cl or (v_r -> 'args' ->> 'vessel_id')::uuid is distinct from v_un or v_r -> 'args' ->> 'origem' is distinct from 'retorno_previa'
       or v_r -> 'args' ->> 'title' is distinct from 'Baterias' then
      raise exception '6a: passou: %', v_r;
    end if;
    if jsonb_array_length(v_r -> 'args' -> 'items') is distinct from 1 or v_r -> 'args' -> 'items' -> 0 ->> 'keyword' is distinct from 'Bateria' or (v_r -> 'args' -> 'items' -> 0 ->> 'unit_price')::numeric is distinct from 500
       or (v_r -> 'args' -> 'items' -> 0 ->> 'quantity')::numeric is distinct from 2 or (v_r -> 'args' -> 'items' -> 0 ->> 'product_id')::uuid is distinct from v_prod
       or jsonb_array_length(v_r -> 'args' -> 'labor') is distinct from 1 or v_r -> 'args' -> 'labor' -> 0 ->> 'description' is distinct from 'Instalação'
       or (v_r -> 'args' -> 'labor' -> 0 ->> 'price')::numeric is distinct from 800 or v_r -> 'args' -> 'labor' -> 0 ->> 'billing_unit' is distinct from 'hour' or (v_r -> 'args' -> 'labor' -> 0 ->> 'service_id')::uuid is distinct from v_serv then
      raise exception '6b: args: %', v_r -> 'args';
    end if;
    if v_r ? 'numero' or v_r -> 'legenda' ->> 'texto' like '%FRASE-MARCADA%' then
      raise exception '6c: devolutiva: %', v_r;
    end if;
    -- Ajustada por ditado: origem retorno_ditado.
    update public.retorno_previa set dados = dados || '{"ajustada_por_ditado": true}' where id = v_pv;
    perform pg_temp.f3d_igual('6d origem ditado', public.retorno_previa_preparar(v_pv, v_ip, v_dono, c_agora) -> 'args' ->> 'origem', 'retorno_ditado');
    update public.retorno_previa set dados = dados - 'ajustada_por_ditado' where id = v_pv;

    -- Regra 0 (flag), com rótulo e prefixo; item vai a fora.
    update public.retorno_config set previa_modo = 'sombra' where id;
    v_r := public.retorno_previa_preparar(v_pv, v_ip, v_dono, c_agora);
    if v_r ->> 'motivo' is distinct from 'desligado' or v_r ->> 'frase' is distinct from 'não saiu, porque o orçamento pelo cartão foi desligado; não criei nada' or v_r ->> 'rotulo' is null then
      raise exception '6e: regra 0: %', v_r;
    end if;
    perform pg_temp.f3d_igual('6f item fora', (select i.estado from public.retorno_cartao_itens i where i.id = v_ip), 'fora');
    update public.retorno_config set previa_modo = 'ligado' where id;
    update public.retorno_cartao_itens set estado = 'vivo' where id = v_ip;

    -- Regra 1: só o dono, com p_item nulo e com rótulo (27).
    v_r := public.retorno_previa_preparar(v_pv, null, c_outro, c_agora);
    if v_r ->> 'motivo' is distinct from 'nao_e_o_dono' or v_r ->> 'frase' is distinct from 'não saiu, porque só o dono pode fazer isso; não criei nada' or v_r ->> 'rotulo' is null then
      raise exception '6g: regra 1: %', v_r;
    end if;

    -- Regra 2: proposta fora de 'proposta'. Item vivo (ditado): remonta, continua vivo (26).
    update public.retorno_previa set estado = 'descartada' where id = v_pv;
    v_r := public.retorno_previa_preparar(v_pv, v_ip, v_dono, c_agora);
    perform pg_temp.f3d_igual('6h caso_fechado', v_r ->> 'frase', 'já não está aberto; não criei nada');
    perform pg_temp.f3d_igual('26a item vivo continua', (select i.estado from public.retorno_cartao_itens i where i.id = v_ip), 'vivo');
    update public.retorno_previa set estado = 'proposta' where id = v_pv;
    -- Caminho do cartão: item 'feito' vira caiu.
    update public.retorno_cartao_itens set estado = 'feito', decidido_em = c_agora where id = v_ip;
    update public.retorno_aberturas set estado = 'fechada', fechada_em = now(), fechada_motivo = 'expirou' where id = v_caso;
    v_r := public.retorno_previa_preparar(v_pv, v_ip, v_dono, c_agora);
    perform pg_temp.f3d_igual('26b caso fechado', v_r ->> 'motivo', 'caso_fechado');
    perform pg_temp.f3d_igual('26c item caiu', (select i.estado || '/' || i.caiu_motivo from public.retorno_cartao_itens i where i.id = v_ip), 'caiu/caso_fechado');
    update public.retorno_aberturas set estado = 'aberta', fechada_em = null, fechada_motivo = null where id = v_caso;
    update public.retorno_cartao_itens set estado = 'vivo', caiu_motivo = null, decidido_em = null where id = v_ip;

    -- Regra 3: provisório, literal; linhas_n = 0 (28).
    update public.retorno_previa set provisorios_n = 1 where id = v_pv;
    update public.retorno_previa_linhas set estado = 'provisorio', motivo = 'sem_preco', preco = null, preco_fonte = 'sem_preco', preco_em = null, nome = 'Peça X' where previa_id = v_pv and ordem = 1;
    v_r := public.retorno_previa_preparar(v_pv, v_ip, v_dono, c_agora);
    perform pg_temp.f3d_igual('6i provisório', v_r ->> 'frase', 'tem item a completar (Peça X): não criei nada. Mande *retorno* e dite o que falta');
    perform pg_temp.f3d_igual('6j motivo', v_r ->> 'motivo', 'item_provisorio');
    update public.retorno_previa set provisorios_n = 0, linhas_n = 0, total = 0 where id = v_pv;
    update public.retorno_previa_linhas set estado = 'ok', motivo = null, preco = 500, preco_fonte = 'praticado_cliente', preco_em = date '2026-08-12', nome = 'Bateria' where previa_id = v_pv and ordem = 1;
    v_r := public.retorno_previa_preparar(v_pv, v_ip, v_dono, c_agora);
    perform pg_temp.f3d_igual('28 sem linhas', v_r ->> 'frase', 'está sem nenhum item: dite o que entra; não criei nada');
    update public.retorno_previa set linhas_n = 2, total = 1800 where id = v_pv;

    -- Regra 6: contato diferente, com os 4 dígitos; prefixo; o conferir continua passando (7).
    -- O telefone segue achando o cliente (quem_escreve), mas o WhatsApp do cadastro aponta para outro número.
    update public.clients set phone = '(47) 90070-0109', whatsapp = '(47) 90070-4321' where id = v_cl;
    v_r := public.retorno_previa_preparar(v_pv, v_ip, v_dono, c_agora);
    if v_r ->> 'motivo' is distinct from 'contato_diferente'
       or v_r ->> 'frase' is distinct from 'não saiu, porque o WhatsApp do cadastro (••4321) não é o número do caso: corrija o cadastro ou mande pelo celular; não criei nada' then
      raise exception '7a: %', v_r;
    end if;
    if (public._retorno_item_conferir(v_ip, c_agora, true) ->> 'ok')::boolean is distinct from true then
      raise exception '7b: conferir devia passar: %', public._retorno_item_conferir(v_ip, c_agora, true);
    end if;
    -- Com item feito, vira caiu.
    update public.retorno_cartao_itens set estado = 'feito', decidido_em = c_agora where id = v_ip;
    v_r := public.retorno_previa_preparar(v_pv, v_ip, v_dono, c_agora);
    perform pg_temp.f3d_igual('7c caiu', (select i.estado || '/' || i.caiu_motivo from public.retorno_cartao_itens i where i.id = v_ip), 'caiu/contato_diferente');
    update public.clients set phone = null, whatsapp = '(47) 90070-0109' where id = v_cl;
    update public.retorno_cartao_itens set estado = 'vivo', caiu_motivo = null, decidido_em = null where id = v_ip;

    -- Regra 7: canal, também com p_item nulo (21).
    update public.retorno_aberturas set nivel = 'nada' where id = v_caso;
    v_r := public.retorno_previa_preparar(v_pv, null, v_dono, c_agora);
    perform pg_temp.f3d_igual('21a nivel nada', v_r ->> 'motivo', 'canal_bloqueado');
    perform pg_temp.f3d_igual('21b frase', v_r ->> 'frase', 'pediu para não receber mensagem automática; não criei nada');
    update public.retorno_aberturas set nivel = 'recibo' where id = v_caso;
    insert into public.whatsapp_leads (phone_normalized, lead_tipo) values ('5547900700109', 'pessoal');
    perform pg_temp.f3d_igual('21c lead pessoal', public.retorno_previa_preparar(v_pv, null, v_dono, c_agora) ->> 'motivo', 'canal_bloqueado');
    delete from public.whatsapp_leads where phone_normalized = '5547900700109' and lead_tipo = 'pessoal';

    -- Regra 4 sem cliente; sem unidade; duas unidades sem escolha.
    update public.clients set active = false where id = v_cl;
    v_r := public.retorno_previa_preparar(v_pv, null, v_dono, c_agora);
    perform pg_temp.f3d_igual('6k sem cliente', v_r ->> 'frase', 'ainda não tem cadastro completo: mande *retorno* quando ele responder; não criei nada');
    update public.clients set active = true where id = v_cl;
    update public.retorno_previa set vessel_id = null where id = v_pv;
    update public.vessels set active = false where id = v_un;
    v_r := public.retorno_previa_preparar(v_pv, null, v_dono, c_agora);
    perform pg_temp.f3d_igual('6l 0 unidades', v_r ->> 'frase', 'está sem unidade no cadastro: cadastre e mande *retorno*; não criei nada');
    update public.vessels set active = true where id = v_un;
    perform pg_temp.f3d_un(v_cl, 'Segunda');
    v_r := public.retorno_previa_preparar(v_pv, null, v_dono, c_agora);
    perform pg_temp.f3d_igual('6m 2 sem escolha', v_r ->> 'frase', 'está sem unidade escolhida: mande *retorno* e a letra; não criei nada');
    update public.retorno_previa set vessel_id = v_un where id = v_pv;
    perform pg_temp.f3d_fechar(array[v_caso]);

    -- ═══ 8. Cliente Final (generico): recusa, sem 23514, proposta cai; com lead.
    select c.id into v_gen from public.clients c where c.generico limit 1;
    if v_gen is not null then
      v_un := pg_temp.f3d_un(v_gen, 'Generica Teste F3');
      v_caso := pg_temp.f3d_caso(110, 'cliente', v_gen);
      v_pv := pg_temp.f3d_prop(v_caso, v_gen, v_un, 'historico', 'ORÇ-D110', jsonb_build_object('forte', true, 'fonte_aprovada', true), 100, 1, 0);
      perform pg_temp.f3d_lin(v_pv, 1, 'Peça', 1, 100, 'praticado_cliente', 'ok', null, 'peca', v_prod);
      v_r := public.retorno_previa_preparar(v_pv, null, v_dono, c_agora);
      perform pg_temp.f3d_igual('8a generico', v_r ->> 'motivo', 'cliente_final');
      perform pg_temp.f3d_igual('8b frase', v_r ->> 'frase', 'está no Cliente Final: use o celular; não criei nada');
      perform pg_temp.f3d_igual('8c proposta caiu', (select p.estado from public.retorno_previa p where p.id = v_pv), 'caiu');
      perform pg_temp.f3d_fechar(array[v_caso]);
    end if;

    -- ═══ 12, 20, 22. Ramo do rascunho.
    v_cl := pg_temp.f3d_cli('Bruno Rascunho F3', 111);
    v_un := pg_temp.f3d_un(v_cl, 'Popa');
    v_caso := pg_temp.f3d_caso(111, 'cliente', v_cl);
    v_os := pg_temp.f3d_os('ORÇ-D151', v_cl, v_un, c_agora - interval '1 hour', 900);
    perform pg_temp.f3d_peca(v_os, v_prod, 1, 900);
    update public.service_orders set origem = 'retorno_ditado', origem_chave8 = public._agenda_chave_telefone('5547900700111') where id = v_os;
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_ip := pg_temp.f3d_item(v_cartao, 1);
    perform pg_temp.f3d_igual('12a pdf', (select i.acao_sim from public.retorno_cartao_itens i where i.id = v_ip), 'pdf');
    v_r := public.retorno_previa_preparar(null, v_ip, v_dono, c_agora, v_os);
    if not (v_r ->> 'ok')::boolean or v_r ->> 'acao' <> 'pdf' or v_r ->> 'numero' <> 'ORÇ-D151' or (v_r ->> 'total')::numeric <> 900 or v_r ? 'args' then
      raise exception '12b: pdf passou: %', v_r;
    end if;
    -- Rascunho de outra unidade (a do caso já definida e diferente): recusa.
    v_un2 := pg_temp.f3d_un(v_cl, 'Quilha');
    update public.retorno_aberturas set unidade_escolhida_id = v_un2 where id = v_caso;
    v_r := public.retorno_previa_preparar(null, v_ip, v_dono, c_agora, v_os);
    perform pg_temp.f3d_igual('12c outra unidade', v_r ->> 'motivo', 'caso_fechado');
    update public.retorno_aberturas set unidade_escolhida_id = null where id = v_caso;
    -- 22. Total zero: frase literal, prefixo do rascunho.
    update public.service_orders set grand_total = 0 where id = v_os;
    v_r := public.retorno_previa_preparar(null, v_ip, v_dono, c_agora, v_os);
    perform pg_temp.f3d_igual('22 rascunho sem valor', v_r ->> 'frase', 'ficou com o rascunho ORÇ-D151 sem valor: complete na tela; não mandei');
    update public.service_orders set grand_total = 900 where id = v_os;
    -- 12: virou_orc cujo PDF falhou passa (R-4): a proposta do mesmo ORÇ não barra o rascunho.
    v_pv := pg_temp.f3d_prop(v_caso, v_cl, v_un, 'ditado', null, '{}', 900, 1, 0, 'virou_orc');
    update public.retorno_previa set service_order_id = v_os, familias = array['bateria'] where id = v_pv;
    v_r := public.retorno_previa_preparar(v_pv, v_ip, v_dono, c_agora, v_os);
    if not (v_r ->> 'ok')::boolean or v_r ->> 'previa_id' <> v_pv::text then
      raise exception '12d: virou_orc: %', v_r;
    end if;
    -- 20: p_previa nulo acha a proposta virou_orc do mesmo ORÇ, a legenda usa o {do_servico} dela, e o PDF não insere outra linha.
    v_r := public.retorno_previa_preparar(null, v_ip, v_dono, c_agora, v_os);
    if v_r ->> 'previa_id' <> v_pv::text or v_r -> 'legenda' ->> 'texto' not like '%orçamento das baterias%' then
      raise exception '20a: %', v_r;
    end if;
    v_r2 := public.retorno_previa_pdf(null, true, '12345678', c_agora, v_os, v_caso, v_ip);
    if (select count(*) from public.retorno_previa p where p.service_order_id = v_os) <> 1
       or (select p.pdf_chave from public.retorno_previa p where p.id = v_pv) <> '12345678' or (select p.pdf_em from public.retorno_previa p where p.id = v_pv) is null then
      raise exception '20b: pdf: %', v_r2;
    end if;
    -- 24: item vivo vira feito, cartão sem ele.
    perform pg_temp.f3d_igual('24a item feito', (select i.estado from public.retorno_cartao_itens i where i.id = v_ip), 'feito');
    if (select c.texto from public.retorno_cartoes c where c.id = v_cartao) like '%Bruno%' then
      raise exception '24b: cartão com o item feito';
    end if;
    -- Era o único item: o cartão foi decidido, com a pendência e a pergunta encerradas e o ponteiro limpo.
    perform pg_temp.f3d_igual('24b2 cartão decidido', (select c.estado || '/' || c.decidido_por from public.retorno_cartoes c where c.id = v_cartao), 'decidido/sim_pin');
    perform pg_temp.f3d_igual('24b3 pendência encerrada', (select p.status from public.ai_operator_pending_actions p join public.retorno_cartoes c on c.pendencia_id = p.id where c.id = v_cartao), 'rejected');
    perform pg_temp.f3d_igual('24b4 ponteiro limpo', (select s.metadata ->> 'pending_confirm_action_id' from public.ai_operator_sessions s join public.retorno_cartoes c on c.sessao_id = s.id where c.id = v_cartao), null);

    -- Cartão vivo sem item: o rodapé não sai quebrado, e o *retorno* fecha esse e abre outro.
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_ip := pg_temp.f3d_item(v_cartao, 1);
    update public.retorno_cartao_itens set estado = 'fora' where id = v_ip;
    v_t := public._retorno_cartao_texto(v_cartao, null);
    if v_t like '%*ver *%' or v_t like '%*dita  %' then
      raise exception '24b5: rodapé quebrado: %', v_t;
    end if;
    v_r := public.retorno_cartao_abrir('puxar', c_agora + interval '1 minute');
    if v_r ->> 'acao' is distinct from 'cartao' or (v_r ->> 'cartao_id')::uuid is not distinct from v_cartao then
      raise exception '24b6: o cartão vazio prendeu o caso: %', v_r;
    end if;
    perform pg_temp.f3d_igual('24b7 o vazio foi decidido', (select c.estado from public.retorno_cartoes c where c.id = v_cartao), 'decidido');
    -- retorno_previa_caiu no último item também decide.
    v_cartao := (v_r ->> 'cartao_id')::uuid;
    v_ip := pg_temp.f3d_item(v_cartao, 1);
    perform public.retorno_previa_caiu(null, v_ip, 'orc_existe', c_agora + interval '2 minutes');
    perform pg_temp.f3d_igual('24b8 caiu decide', (select c.estado from public.retorno_cartoes c where c.id = v_cartao), 'decidido');
    -- O ditado livre (retorno_caso_respondido) no último item também.
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_ip := pg_temp.f3d_item(v_cartao, 1);
    perform public.retorno_caso_respondido(v_ip, 'Texto ditado de teste', 'wa-f3', c_agora + interval '3 minutes');
    perform pg_temp.f3d_igual('24b9 ditado livre decide', (select c.estado from public.retorno_cartoes c where c.id = v_cartao), 'decidido');
    perform pg_temp.f3d_fechar(array[v_caso]);

    -- 20: cliente com 2 unidades e rascunho válido: passa, com cliente e unidade do rascunho.
    v_cl := pg_temp.f3d_cli('Clara Duas F3', 112);
    v_un := pg_temp.f3d_un(v_cl, 'Alma');
    perform pg_temp.f3d_un(v_cl, 'Beta');
    v_caso := pg_temp.f3d_caso(112, 'cliente', v_cl);
    v_os := pg_temp.f3d_os('ORÇ-D152', v_cl, v_un, c_agora - interval '1 hour', 900);
    perform pg_temp.f3d_peca(v_os, v_prod, 1, 900);
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_ip := pg_temp.f3d_item(v_cartao, 1);
    v_r := public.retorno_previa_preparar(null, v_ip, v_dono, c_agora, v_os);
    if not (v_r ->> 'ok')::boolean then
      raise exception '20c: 2 unidades: %', v_r;
    end if;
    -- Cliente inativo recusa (regra 4 do rascunho).
    update public.clients set active = false where id = v_cl;
    v_r := public.retorno_previa_preparar(null, v_ip, v_dono, c_agora, v_os);
    if (v_r ->> 'ok')::boolean then   -- a regra 2 já recusa: _retorno_rascunho_do_caso não acha cliente inativo
      raise exception '20d: inativo passou: %', v_r;
    end if;
    update public.clients set active = true where id = v_cl;
    -- 12: retorno_previa_pdf sem proposta insere a linha 'rascunho'; com p_ok falso não insere nada.
    v_r := public.retorno_previa_pdf(null, false, null, c_agora, v_os, v_caso, v_ip);
    if exists (select 1 from public.retorno_previa p where p.service_order_id = v_os) then
      raise exception '24c: p_ok falso inseriu';
    end if;
    perform pg_temp.f3d_igual('24d item não mudou', (select i.estado from public.retorno_cartao_itens i where i.id = v_ip), 'vivo');
    v_r := public.retorno_previa_pdf(null, true, '12345678', c_agora, v_os, v_caso, v_ip);
    select * into v_prev from public.retorno_previa p where p.service_order_id = v_os;
    if v_prev.origem <> 'rascunho' or v_prev.estado <> 'virou_orc' or v_prev.modo <> 'ligado' or v_prev.titulo <> 'Rascunho ORÇ-D152' or v_prev.hash <> ''
       or v_prev.linhas_iniciais <> '[]'::jsonb or v_prev.pdf_chave <> '12345678' or v_prev.linhas_n <> 1 or v_prev.total <> 900 then
      raise exception '24e: linha rascunho: %', to_jsonb(v_prev);
    end if;
    perform pg_temp.f3d_fechar(array[v_caso]);

    -- ═══ 19. retorno_previa_soltar.
    v_cl := pg_temp.f3d_cli('Lia Soltar F3', 113);
    v_un := pg_temp.f3d_un(v_cl, 'Rumo');
    v_caso := pg_temp.f3d_caso(113, 'cliente', v_cl);
    v_pv := pg_temp.f3d_prop(v_caso, v_cl, v_un, 'historico', 'ORÇ-D113', jsonb_build_object('forte', true, 'fonte_aprovada', true), 100, 1, 0);
    perform pg_temp.f3d_lin(v_pv, 1, 'Peça', 1, 100, 'praticado_cliente', 'ok', null, 'peca', v_prod);
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_ip := pg_temp.f3d_item(v_cartao, 1);
    update public.retorno_cartao_itens set texto_mostrado = 'marca' where id = v_ip;
    perform public.retorno_previa_soltar(v_ip, c_agora);
    if (select i.estado from public.retorno_cartao_itens i where i.id = v_ip) <> 'vivo' or (select i.texto_mostrado from public.retorno_cartao_itens i where i.id = v_ip) is not distinct from 'marca' then
      raise exception '19a: item vivo devia remontar';
    end if;
    update public.retorno_cartao_itens set estado = 'feito', decidido_em = c_agora where id = v_ip;
    perform public.retorno_previa_soltar(v_ip, c_agora);
    if (select i.estado from public.retorno_cartao_itens i where i.id = v_ip) <> 'fora' or (select i.decidido_em from public.retorno_cartao_itens i where i.id = v_ip) is null then
      raise exception '19b: item feito devia ir a fora, mantendo decidido_em';
    end if;
    update public.retorno_cartao_itens set estado = 'caiu', caiu_motivo = 'orc_existe' where id = v_ip;
    perform public.retorno_previa_soltar(v_ip, c_agora);
    perform pg_temp.f3d_igual('19c caiu não muda', (select i.estado from public.retorno_cartao_itens i where i.id = v_ip), 'caiu');

    -- retorno_previa_caiu e retorno_previa_orc_criado.
    v_r := public.retorno_previa_caiu(v_pv, v_ip, 'orc_existe', c_agora);
    perform pg_temp.f3d_igual('caiu a', (select p.estado from public.retorno_previa p where p.id = v_pv), 'caiu');
    update public.retorno_previa set estado = 'proposta' where id = v_pv;
    v_os := pg_temp.f3d_os('ORÇ-D199', v_cl, v_un, c_agora, 100);
    v_r := public.retorno_previa_orc_criado(v_pv, v_os, c_agora);
    v_r2 := public.retorno_previa_orc_criado(v_pv, v_os, c_agora + interval '1 minute');
    select * into v_prev from public.retorno_previa where id = v_pv;
    if v_prev.estado <> 'virou_orc' or v_prev.service_order_id <> v_os or v_prev.decidida_em <> c_agora then
      raise exception 'orc_criado: %', to_jsonb(v_prev);
    end if;
    perform pg_temp.f3d_fechar(array[v_caso]);

    -- ═══ 9, 10, 25, 29. *dita* com proposta viva; retorno_previa_ver.
    v_cl := pg_temp.f3d_cli('Nina Dita F3', 114);
    v_un := pg_temp.f3d_un(v_cl, 'Vela');
    v_caso := pg_temp.f3d_caso(114, 'cliente', v_cl);
    v_pv := pg_temp.f3d_prop(v_caso, v_cl, v_un, 'historico', 'ORÇ-D114', jsonb_build_object('forte', true, 'fonte_aprovada', true), 500, 1, 0);
    perform pg_temp.f3d_lin(v_pv, 1, 'Peça', 1, 500, 'praticado_cliente', 'ok', null, 'peca', v_prod);
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_ip := pg_temp.f3d_item(v_cartao, 1);
    v_r := public.retorno_decidir_dito('{"comando": "ditar", "n": 1, "texto": "troca o controlador"}', v_dono, c_agora);
    if v_r ->> 'texto' <> 'Isso parece ajuste da proposta, e *dita* manda o texto ao cliente. Diga sem o *dita*: ou mande *dita 1* com o texto completo ao cliente.' then
      raise exception '9a: %', v_r;
    end if;
    if (select i.texto_ditado from public.retorno_cartao_itens i where i.id = v_ip) is not null then
      raise exception '9b: gravou';
    end if;
    -- Texto de verdade ao cliente passa, como na F2.
    v_r := public.retorno_decidir_dito('{"comando": "ditar", "n": 1, "texto": "pode trazer amanhã que eu olho"}', v_dono, c_agora);
    if (select i.texto_ditado from public.retorno_cartao_itens i where i.id = v_ip) is distinct from 'pode trazer amanhã que eu olho' then
      raise exception '9c: ditado normal';
    end if;
    update public.retorno_cartao_itens set texto_ditado = null, ditado_via = null where id = v_ip;

    -- 10, 29: retorno_previa_ver.
    v_r := public.retorno_previa_ver(1, v_dono, c_agora);
    if v_r::text like '%FRASE-MARCADA%' then
      raise exception '10: texto do cliente em retorno_previa_ver';
    end if;
    if v_r ->> 'hash' is distinct from public._retorno_previa_hash_efetivo(v_pv, c_agora)
       or not (v_r ->> 'ditado_ligado')::boolean or v_r ->> 'previa_id' <> v_pv::text or (v_r ->> 'client_id')::uuid <> v_cl
       or v_r ->> 'validade' <> 'terça (17/11)' or v_r ->> 'unidade_nome' <> 'Vela' or jsonb_array_length(v_r -> 'linhas') <> 1
       or v_r -> 'linhas' -> 0 ->> 'rotulo' <> 'praticado em 12/08/26' or (v_r ->> 'cliente_generico')::boolean then
      raise exception '29a: ver: %', v_r;
    end if;
    -- 29: erro em cada um dos 3 casos.
    perform pg_temp.f3d_igual('29b nao_e_o_dono', public.retorno_previa_ver(1, c_outro, c_agora) ->> 'erro', 'nao_e_o_dono');
    perform pg_temp.f3d_igual('29c sem_caso', public.retorno_previa_ver(2, v_dono, c_agora) ->> 'erro', 'sem_caso');
    update public.ai_operator_pending_actions set status = 'executed' where id = (select c.pendencia_id from public.retorno_cartoes c where c.id = v_cartao);
    perform pg_temp.f3d_igual('29d sem_cartao (pendência executada)', public.retorno_previa_ver(1, v_dono, c_agora) ->> 'erro', 'sem_cartao');
    -- 25: só lê: o cartão continua vivo depois.
    perform pg_temp.f3d_igual('25b cartão continua vivo', (select c.estado from public.retorno_cartoes c where c.id = v_cartao), 'vivo');
    update public.ai_operator_pending_actions set status = 'pending' where id = (select c.pendencia_id from public.retorno_cartoes c where c.id = v_cartao);
    update public.retorno_previa set vessel_id = null where id = v_pv;
    v_un2 := pg_temp.f3d_un(v_cl, 'Quina');
    update public.retorno_aberturas set unidade_escolhida_id = v_un2 where id = v_caso;
    update public.retorno_previa set vessel_id = v_un where id = v_pv;
    perform pg_temp.f3d_igual('25c vessel da proposta vence', public.retorno_previa_ver(1, v_dono, c_agora) ->> 'unidade_nome', 'Vela');
    perform pg_temp.f3d_igual('25d unidades', jsonb_array_length(public.retorno_previa_ver(1, v_dono, c_agora) -> 'unidades')::text, '2');
    update public.retorno_aberturas set unidade_escolhida_id = null where id = v_caso;
    delete from public.vessels where id = v_un2;
    perform pg_temp.f3d_igual('25e 1 unidade', (public.retorno_previa_ver(1, v_dono, c_agora) -> 'unidades')::text, '[]');
    perform pg_temp.f3d_fechar(array[v_caso]);

    -- ═══ 15. retorno_previa_retrato. 13. Letra D.
    v_cl := pg_temp.f3d_cli('Olga Retrato F3', 115);
    v_un := pg_temp.f3d_un(v_cl, 'Rola');
    v_caso := pg_temp.f3d_caso(115, 'cliente', v_cl);
    v_pv := pg_temp.f3d_prop(v_caso, v_cl, v_un, 'historico', 'ORÇ-D115', jsonb_build_object('forte', true, 'fonte_aprovada', true), 500, 1, 0);
    perform pg_temp.f3d_lin(v_pv, 1, 'Peça', 1, 500, 'praticado_cliente', 'ok', null, 'peca', v_prod);
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_ip := pg_temp.f3d_item(v_cartao, 1);
    v_h := public._retorno_previa_hash_efetivo(v_pv, c_agora);
    v_r := public.retorno_previa_retrato(v_caso, v_pv, v_h, '5547900700115', v_dono, c_agora);
    if not (v_r ->> 'ok')::boolean or v_r ->> 'item_id' <> v_ip::text or (v_r ->> 'n')::integer <> 1 then
      raise exception '15a: retrato: %', v_r;
    end if;
    v_r := public.retorno_previa_retrato(v_caso, v_pv, 'outro-hash', '5547900700115', v_dono, c_agora);
    if (v_r ->> 'ok')::boolean or v_r ->> 'motivo' <> 'mudou' then
      raise exception '15b: outro hash: %', v_r;
    end if;
    update public.retorno_config set previa_ditado_ligado = false, previa_modo = 'desligado' where id;
    v_r := public.retorno_previa_retrato(v_caso, v_pv, v_h, '5547900700115', v_dono, c_agora);
    perform pg_temp.f3d_igual('15c flag', v_r ->> 'motivo', 'desligado');
    update public.retorno_config set previa_ditado_ligado = true, previa_modo = 'ligado' where id;
    perform pg_temp.f3d_limpar();   -- o cartão cai
    v_r := public.retorno_previa_retrato(v_caso, v_pv, v_h, '5547900700115', v_dono, c_agora);
    if not (v_r ->> 'ok')::boolean or v_r ->> 'item_id' is not null then
      raise exception '15d: cartão caído: %', v_r;
    end if;
    perform pg_temp.f3d_fechar(array[v_caso]);

    -- Letra D (13): proposta descartada, item remontado, nada criado depois.
    v_cl := pg_temp.f3d_cli('Tom Provisorio F3');
    v_un := pg_temp.f3d_un(v_cl, 'Pier');
    v_caso := pg_temp.f3d_caso(116, 'numero_novo', null);
    insert into public.audit_log (table_name, record_id, action, changed_by, new_value, reason)
    values ('clients', v_cl, 'lead_converted', 'retorno', jsonb_build_object('caso', v_caso, 'vessel_id', v_un), 'teste');
    update public.clients set provisorio = true where id = v_cl;
    v_pv := pg_temp.f3d_prop(v_caso, v_cl, v_un, 'historico', 'ORÇ-D116', jsonb_build_object('forte', true, 'fonte_aprovada', true), 500, 1, 0);
    perform pg_temp.f3d_lin(v_pv, 1, 'Peça', 1, 500, 'praticado_outro', 'ok', null, 'peca', v_prod);
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_ip := pg_temp.f3d_item(v_cartao, 1);
    perform pg_temp.f3d_igual('13a orcar antes do D', (select i.acao_sim from public.retorno_cartao_itens i where i.id = v_ip), 'orcar');
    v_r := pg_temp.f3d_letra(1, 'D', v_dono);
    perform pg_temp.f3d_igual('13b texto', v_r ->> 'texto', 'Cadastro provisório desfeito. Nada foi apagado.');
    perform pg_temp.f3d_igual('13c descartada', (select p.estado from public.retorno_previa p where p.id = v_pv), 'descartada');
    perform pg_temp.f3d_igual('13d acao nula', (select i.acao_sim from public.retorno_cartao_itens i where i.id = v_ip), null);
    perform pg_temp.f3d_igual('13e previa nula', (select i.previa_id::text from public.retorno_cartao_itens i where i.id = v_ip), null);
    perform pg_temp.f3d_fechar(array[v_caso]);

    -- ═══ 11, 23. retorno_previa_aplicar.
    v_cl := pg_temp.f3d_cli('Vera Aplicar F3', 117);
    v_un := pg_temp.f3d_un(v_cl, 'Toca');
    v_caso := pg_temp.f3d_caso(117, 'cliente', v_cl, 'preciso trocar as baterias da lancha, quanto custa?');
    -- 11: com sombra viva e p_previa nulo, cria a ditada, sem 23505, e a sombra continua igual.
    v_pv2 := pg_temp.f3d_prop(v_caso, v_cl, v_un, 'historico', 'ORÇ-D117', jsonb_build_object('forte', true, 'fonte_aprovada', true), 100, 1, 0, 'sombra');
    perform pg_temp.f3d_lin(v_pv2, 1, 'Sombra', 1, 100, 'praticado_cliente');
    v_cartao := pg_temp.f3d_cartao(c_agora);
    v_ip := pg_temp.f3d_item(v_cartao, 1);
    v_t := jsonb_build_object('abertura_id', v_caso, 'titulo', 'Troca das baterias', 'condicao', '50% de sinal', 'client_id', v_cl, 'vessel_id', v_un, 'hash', 'plano-hash',
      'linhas', jsonb_build_array(
        jsonb_build_object('linha', 1, 'tipo', 'peca', 'product_id', v_prod, 'nome', 'Controlador MPPT 60A', 'quantidade', 1, 'preco', 1320, 'fonte', 'dito', 'em', null, 'estado', 'assumido', 'nome_pedido', 'controlador de 60', 'motivo', null),
        jsonb_build_object('linha', 2, 'tipo', 'peca', 'nome', 'Cabo especial', 'quantidade', 1, 'preco', 320, 'fonte', 'dito', 'em', null, 'estado', 'assumido', 'motivo', 'sem_catalogo'),
        jsonb_build_object('linha', 3, 'tipo', 'servico', 'service_id', v_serv, 'nome', 'Instalação', 'quantidade', 1.5, 'preco', 333.33, 'fonte', 'praticado_cliente', 'em', '2026-08-12', 'estado', 'ok', 'motivo', null)
      ))::text;
    v_r := public.retorno_previa_aplicar(null, v_t::jsonb, v_dono, c_agora, v_ip);
    v_pv := (v_r ->> 'previa_id')::uuid;
    select * into v_prev from public.retorno_previa where id = v_pv;
    if v_prev.origem <> 'ditado' or v_prev.estado <> 'proposta' or v_prev.modo <> 'ligado' or v_prev.familias <> array['bateria'] or v_prev.fonte_numero is not null
       or v_prev.titulo <> 'Troca das baterias' or v_prev.condicao_pagamento <> '50% de sinal' or v_prev.client_id <> v_cl or v_prev.vessel_id <> v_un
       or v_prev.total <> 2140.00 or v_prev.linhas_n <> 3 or v_prev.provisorios_n <> 0 or v_prev.linhas_iniciais <> '[]'::jsonb
       or v_prev.preco_mais_antigo <> date '2026-08-12' or v_prev.hash = 'plano-hash' or not (v_prev.dados ->> 'travada')::boolean or not (v_prev.dados ->> 'ajustada_por_ditado')::boolean then
      raise exception '23a: cabeçalho: %', to_jsonb(v_prev);
    end if;
    if v_prev.hash is distinct from v_r ->> 'hash'
       or v_prev.hash is distinct from public._retorno_previa_hash(v_un, 'Troca das baterias', public._retorno_previa_linhas_json(v_pv)) then
      raise exception '23b: hash';
    end if;
    perform pg_temp.f3d_igual('23c motivo assumido', (select l.motivo from public.retorno_previa_linhas l where l.previa_id = v_pv and l.ordem = 1), 'pedido: controlador de 60');
    perform pg_temp.f3d_igual('23d sem_catalogo', (select l.motivo from public.retorno_previa_linhas l where l.previa_id = v_pv and l.ordem = 2), 'sem_catalogo');
    perform pg_temp.f3d_igual('23e fonte', (select l.preco_fonte || '/' || l.preco_em::text from public.retorno_previa_linhas l where l.previa_id = v_pv and l.ordem = 3), 'praticado_cliente/2026-08-12');
    perform pg_temp.f3d_igual('23f sombra intacta', (select p.estado || '/' || p.total from public.retorno_previa p where p.id = v_pv2), 'sombra/100.00');
    -- O item remonta com a linha nova e o *sim* seguinte passa no conferir.
    perform pg_temp.f3d_igual('23g item orcar', (select i.acao_sim from public.retorno_cartao_itens i where i.id = v_ip), 'orcar');
    perform pg_temp.f3d_igual('23h previa no item', (select i.previa_id::text from public.retorno_cartao_itens i where i.id = v_ip), v_pv::text);
    if (public._retorno_item_conferir(v_ip, c_agora, true) ->> 'ok')::boolean is distinct from true then
      raise exception '23i: conferir devia passar: %', public._retorno_item_conferir(v_ip, c_agora, true);
    end if;

    -- 11, 23: reaplicar numa proposta existente: mantém origem, famílias e fonte; hash muda; idempotente por previa_id; linhas_iniciais não muda.
    v_cl2 := pg_temp.f3d_cli('Ana Hist Aplicar F3', 118);
    v_un2 := pg_temp.f3d_un(v_cl2, 'Vira');
    v_caso2 := pg_temp.f3d_caso(118, 'cliente', v_cl2);
    v_pv2 := pg_temp.f3d_prop(v_caso2, v_cl2, v_un2, 'historico', 'ORÇ-D118', jsonb_build_object('forte', true, 'fonte_aprovada', true, 'alternativas', '[{"x": 1}]'::jsonb), 100, 1, 0);
    perform pg_temp.f3d_lin(v_pv2, 1, 'Velha', 1, 100, 'praticado_cliente');
    v_r := public.retorno_previa_aplicar(v_pv2, jsonb_build_object('abertura_id', v_caso2, 'titulo', 'Ajustado', 'condicao', null, 'client_id', v_cl2, 'vessel_id', v_un2,
      'linhas', jsonb_build_array(jsonb_build_object('linha', 1, 'tipo', 'peca', 'product_id', v_prod, 'nome', 'Nova', 'quantidade', 2, 'preco', 300, 'fonte', 'dito', 'em', null, 'estado', 'ok'))), v_dono, c_agora);
    select * into v_prev from public.retorno_previa where id = v_pv2;
    if v_prev.origem <> 'historico' or v_prev.fonte_numero <> 'ORÇ-D118' or v_prev.familias <> array['bateria'] or v_prev.modo <> 'ligado' or v_prev.total <> 600
       or v_prev.titulo <> 'Ajustado' or v_prev.linhas_iniciais::text <> '[{"inicial": true}]' or (v_prev.dados -> 'alternativas') is null then
      raise exception '23j: existente: %', to_jsonb(v_prev);
    end if;
    v_h := v_prev.hash;
    v_r2 := public.retorno_previa_aplicar(v_pv2, jsonb_build_object('abertura_id', v_caso2, 'titulo', 'Ajustado', 'condicao', null, 'client_id', v_cl2, 'vessel_id', v_un2,
      'linhas', jsonb_build_array(jsonb_build_object('linha', 1, 'tipo', 'peca', 'product_id', v_prod, 'nome', 'Nova', 'quantidade', 2, 'preco', 300, 'fonte', 'dito', 'em', null, 'estado', 'ok'))), v_dono, c_agora);
    if v_r2 ->> 'hash' <> v_h or (select count(*) from public.retorno_previa_linhas l where l.previa_id = v_pv2) <> 1 then
      raise exception '11b: idempotência: %', v_r2;
    end if;
    -- Só o dono aplica.
    begin
      perform public.retorno_previa_aplicar(v_pv2, '{"linhas": []}', c_outro, c_agora);
      raise exception '11c: outro autor passou' using errcode = 'P0002';
    exception when others then
      if sqlstate <> '42501' then raise; end if;
    end;
    perform pg_temp.f3d_fechar(array[v_caso, v_caso2]);

    -- ═══ 14. retorno_ver_caso_para_modelo: papel cliente sem OS grava client_id; cliente_ambiguo zera as três.
    v_cl := pg_temp.f3d_cli('Rui Amarra F3', 119);
    v_caso := pg_temp.f3d_caso(119, 'cliente', v_cl);
    v_cartao := pg_temp.f3d_cartao(c_agora);
    select c.sessao_id into v_ses from public.retorno_cartoes c where c.id = v_cartao;
    v_r := public.retorno_ver_caso_para_modelo(1, v_dono, c_agora);
    if v_r ->> 'erro' is not null or (v_r -> 'amarra' ->> 'client_id')::uuid <> v_cl then
      raise exception '14a: amarra: %', v_r;
    end if;
    perform pg_temp.f3d_igual('14b client_id gravado', (select s.client_id::text from public.ai_operator_sessions s where s.id = v_ses), v_cl::text);
    perform pg_temp.f3d_fechar(array[v_caso]);
    v_caso := pg_temp.f3d_caso(120, 'cliente_ambiguo', v_cl);
    v_cartao := pg_temp.f3d_cartao(c_agora);
    select c.sessao_id into v_ses from public.retorno_cartoes c where c.id = v_cartao;
    update public.ai_operator_sessions set client_id = v_cl, vessel_id = null, service_order_id = null where id = v_ses;
    v_r := public.retorno_ver_caso_para_modelo(1, v_dono, c_agora);
    if (select s.client_id from public.ai_operator_sessions s where s.id = v_ses) is not null then
      raise exception '14c: ambíguo devia zerar';
    end if;
    if v_r -> 'amarra' ->> 'client_id' is not null then
      raise exception '14d: amarra do ambíguo: %', v_r;
    end if;

    -- 14e. A marca vai à sessão do turno, que pode não ser a do cartão (a sessão gira em 4 h, o cartão vive 24 h), e a vigia solta as duas.
    perform pg_temp.f3d_fechar(array[v_caso]);
    v_cl := pg_temp.f3d_cli('Rui Turno F3', 121);
    v_caso := pg_temp.f3d_caso(121, 'cliente', v_cl);
    v_cartao := pg_temp.f3d_cartao(c_agora);
    select c.sessao_id into v_ses from public.retorno_cartoes c where c.id = v_cartao;
    update public.ai_operator_sessions set client_id = null, vessel_id = null, service_order_id = null, metadata = metadata - 'retorno_amarrada' where id = v_ses;
    insert into public.ai_operator_sessions (channel, owner_user_id, status) values ('web', v_dono, 'open') returning id into v_ses2;
    v_r := public.retorno_ver_caso_para_modelo(1, v_dono, c_agora, v_ses2);
    perform pg_temp.f3d_igual('14e marca na sessão do turno', (select s.metadata ->> 'retorno_amarrada' from public.ai_operator_sessions s where s.id = v_ses2), 'true');
    perform pg_temp.f3d_igual('14f cliente na sessão do turno', (select s.client_id::text from public.ai_operator_sessions s where s.id = v_ses2), v_cl::text);
    perform pg_temp.f3d_igual('14g a sessão do cartão fica sem a marca', (select s.metadata ->> 'retorno_amarrada' from public.ai_operator_sessions s where s.id = v_ses), null);
    perform pg_temp.f3d_limpar();
    perform public.retorno_vigia_cartao(c_agora + interval '1 minute');
    perform pg_temp.f3d_igual('14h a vigia solta a marca do painel', (select s.metadata ->> 'retorno_amarrada' from public.ai_operator_sessions s where s.id = v_ses2), null);

    raise exception 'retorno_f3_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f3_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f3_decidir', true, '{}');
end
$decidir$;

select arquivo, ok, numeros from _bancada order by em;
rollback;

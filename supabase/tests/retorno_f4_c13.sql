-- Retorno F4 (P10): o C13, pedido de orçamento feito pelo parceiro para um cliente dele (K9). A leitura do pedido sem
-- modelo e sem busca por nome; a coleta de 2 mensagens (P03 e P04, nunca o P04 antes do P03); a máquina de estados do
-- pedido, com a chave do cadastro desligada (nada real nasce) e ligada; o duplicado por telefone; a letra D; o item pedido
-- no cartão do parceiro (A, B, D e as formas sem letra); a ordem do *sim <PIN>* (o número copiado, o vínculo nos dois
-- destinos, a requalificação tudo ou nada); o preparo, o soltar, o caiu e o PDF do parceiro, com os da F3 byte a byte iguais;
-- o P15; *resolvido N* no pedido; e, na revisão de 10/11 (29), o número da própria parceira ou da casa, que nunca vira o do
-- cliente. Roda só pela bancada (grupo 7, F4_ONDA=7). Termina em ROLLBACK. Telefones de teste 55479000168xx (o parceiro e,
-- no 29, um favorecido) e 55479000169xx (os clientes); nomes inventados; números de documento ORÇ-989xx. Relógio:
-- ter 12/01/2027, das 10:00 às 19:00, e qua 13/01 (o silêncio de 24 h).
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f4q_cliente(p_nome text, p_fone text) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, p_fone) returning id
$f$;

-- A recebida do parceiro e o retorno_abrir dela (o caminho real do webhook: abre ou soma ao caso e tria).
create or replace function pg_temp.f4q_abrir(p_fone text, p_corpo text, p_em timestamptz) returns uuid
language plpgsql as $f$
declare
  v_m uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at, hora_real)
  values ('inbound', p_fone, 'text', p_corpo, 'teste-f4-c13-' || md5(p_fone || p_corpo || p_em::text || random()::text), p_em, p_em)
  returning id into v_m;
  return (public.retorno_abrir(v_m, false, p_em + interval '5 seconds') ->> 'abertura_id')::uuid;
end $f$;

create or replace function pg_temp.f4q_fechar(p_caso uuid, p_em timestamptz) returns void
language sql as $f$
  update public.retorno_aberturas set estado = 'fechada', fechada_em = p_em, fechada_motivo = 'dono' where id = p_caso and estado <> 'fechada'
$f$;

create or replace function pg_temp.f4q_ped(p_caso uuid) returns public.parceiro_pedidos
language sql as $f$
  select pp from public.parceiro_pedidos pp where pp.abertura_id = p_caso
$f$;

-- O pedido nasce com criado_em = now() (a hora real da bancada, antes do relógio do teste): alinha à abertura do caso.
create or replace function pg_temp.f4q_alinhar(p_caso uuid) returns void
language sql as $f$
  update public.parceiro_pedidos pp set criado_em = a.aberta_em
    from public.retorno_aberturas a where a.id = p_caso and pp.abertura_id = p_caso
$f$;

-- A coleta decidida (sombra, enviada ou incerta) e os efeitos dela, como retorno_registrar_decisao faria.
create or replace function pg_temp.f4q_decidir(p_saida uuid, p_estado text, p_em timestamptz) returns void
language plpgsql as $f$
begin
  -- retorno_saidas_texto: saída decidida tem texto
  update public.retorno_saidas set estado = p_estado, decidida_em = p_em, enviada_em = case when p_estado = 'enviada' then p_em end,
         texto = coalesce(texto, 'texto de teste (F4 C13)')
   where id = p_saida;
  perform public._parceiro_aplicar_efeitos(p_saida, p_em);
end $f$;

create or replace function pg_temp.f4q_saida(p_caso uuid, p_tipo text, p_variante text) returns public.retorno_saidas
language sql as $f$
  select s from public.retorno_saidas s
   where s.abertura_id = p_caso and s.emissor = 'parceiro' and s.tipo = p_tipo and s.variante is not distinct from p_variante
   order by s.criada_em desc, s.id desc limit 1
$f$;

create or replace function pg_temp.f4q_conta(p_caso uuid, p_tipo text, p_variante text) returns bigint
language sql as $f$
  select count(*) from public.retorno_saidas s
   where s.abertura_id = p_caso and s.emissor = 'parceiro' and s.tipo = p_tipo and s.variante is not distinct from p_variante
$f$;

-- O rascunho do cliente (feito na tela, ou o ORÇ que montarOrcamento criaria com a origem do parceiro), com um serviço.
create or replace function pg_temp.f4q_rascunho(p_cliente uuid, p_vessel uuid, p_numero text, p_em timestamptz, p_total numeric,
                                                p_parceiro uuid default null) returns uuid
language plpgsql as $f$
declare
  v_id uuid;
begin
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total, origem_parceiro_id, origem)
  values (p_numero, p_cliente, p_vessel, 'draft', 'draft', 'repair', p_em, p_em, p_total, p_parceiro,
          case when p_parceiro is not null then 'retorno_parceiro' end)
  returning id into v_id;
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot,
                                             line_total)
  values (v_id, 'Serviço de teste C13', 'visit', 1, p_total, p_total);
  update public.service_orders set grand_total = p_total where id = v_id;
  return v_id;
end $f$;

-- O cartão montado a partir de linhas da fila, com a mesma montagem e a mesma pendência do *parceiro* (molde da P8).
create or replace function pg_temp.f4q_cartao(p_filas uuid[], p_agora timestamptz) returns uuid
language plpgsql as $f$
declare
  v_c uuid;
  v_item jsonb;
  k integer := 0;
  v_f uuid;
  v_dono uuid;
  v_phone text;
begin
  select d.id, d.phone into v_dono, v_phone from public._comprovante_dono() d;
  insert into public.parceiro_cartoes (gatilho, dia, estado, hash, texto, criado_em, expira_em)
    values ('puxar', (p_agora at time zone 'America/Sao_Paulo')::date, 'lista', '', '', p_agora, p_agora + interval '24 hours')
    returning id into v_c;
  foreach v_f in array p_filas loop
    k := k + 1;
    v_item := public._parceiro_item_montar(v_f, k::smallint, p_agora);
    insert into public.parceiro_cartao_itens (cartao_id, n, tipo, interessado_id, painel_id, abertura_id, service_order_id, envio_mao_id,
                                              pedido_id, numero_id, fila_id, texto_mostrado, opcoes, retrato, hash, selecionado)
    values (v_c, k, v_item ->> 'tipo', (v_item ->> 'interessado_id')::uuid, (v_item ->> 'painel_id')::uuid, (v_item ->> 'abertura_id')::uuid,
            (v_item ->> 'service_order_id')::uuid, (v_item ->> 'envio_mao_id')::uuid, (v_item ->> 'pedido_id')::uuid,
            (v_item ->> 'numero_id')::uuid, v_f, v_item ->> 'texto_mostrado', v_item -> 'opcoes', v_item -> 'retrato', v_item ->> 'hash',
            (v_item ->> 'selecionado')::boolean);
    update public.parceiro_fila f set estado = 'no_cartao', vezes = f.vezes + 1, ultimo_em = p_agora where f.id = v_f;
  end loop;
  perform public._parceiro_cartao_viver(v_c, v_dono, v_phone, p_agora);
  return v_c;
end $f$;

-- O *sim <PIN>* e a ferramenta que marca a pendência executada (P12).
create or replace function pg_temp.f4q_sim(p_cartao uuid, p_agora timestamptz) returns jsonb
language plpgsql as $f$
declare
  v jsonb;
begin
  v := public.parceiro_cartao_executar(p_cartao, (select d.id from public._comprovante_dono() d), p_agora);
  -- ai_op_protect_pending_action: pending -> approved -> executed, como o executor de verdade
  update public.ai_operator_pending_actions p set status = 'approved'
   where p.id = (select c.pendencia_id from public.parceiro_cartoes c where c.id = p_cartao) and p.status = 'pending';
  update public.ai_operator_pending_actions p set status = 'executed'
   where p.id = (select c.pendencia_id from public.parceiro_cartoes c where c.id = p_cartao) and p.status = 'approved';
  return v;
end $f$;

create or replace function pg_temp.f4q_dito(p_cmd jsonb, p_agora timestamptz) returns jsonb
language sql as $f$
  select public.parceiro_decidir_dito(p_cmd, (select d.id from public._comprovante_dono() d), p_agora)
$f$;

create or replace function pg_temp.f4q_item(p_cartao uuid, p_n integer) returns public.parceiro_cartao_itens
language sql as $f$
  select i from public.parceiro_cartao_itens i where i.cartao_id = p_cartao and i.n = p_n
$f$;

create or replace function pg_temp.f4q_letras(p_cartao uuid, p_n integer) returns text
language sql as $f$
  select coalesce(string_agg(t.o ->> 'letra', '' order by t.ord), '')
    from public.parceiro_cartao_itens i, jsonb_array_elements(i.opcoes) with ordinality t(o, ord)
   where i.cartao_id = p_cartao and i.n = p_n
$f$;

create or replace function pg_temp.f4q_fila(p_chave text) returns public.parceiro_fila
language sql as $f$
  select f from public.parceiro_fila f where f.chave = p_chave
$f$;

do $c13$
declare
  c_t constant timestamptz := '2027-01-12 10:00-03';        -- ter
  c_n1 constant text := '5547900016801';                    -- Milena
  c_n2 constant text := '5547900016802';                    -- Carla
  c_n3 constant text := '5547900016803';                    -- Rosa
  v_dono uuid;
  v_phone text;
  v_p uuid;
  v_mil uuid; v_carla uuid; v_rosa uuid;
  v_n1 uuid; v_n2 uuid; v_n3 uuid;
  v_carencia integer;
  v_caso uuid; v_caso2 uuid;
  v_ped public.parceiro_pedidos;
  v_ped2 public.parceiro_pedidos;
  v_s public.retorno_saidas;
  v_s2 public.retorno_saidas;
  v_ab public.retorno_aberturas;
  v_f public.parceiro_fila;
  v_i public.parceiro_cartao_itens;
  v_oi public.os_interessados;
  v_cartao uuid;
  v_r jsonb;
  v_x jsonb;
  v_t text;
  v_nc bigint; v_nv bigint;
  v_cli uuid; v_outro uuid; v_existente uuid;
  v_rasc uuid; v_orc uuid; v_previa uuid;
  v_ids uuid[];
  v_k bigint;
  v_rec record;
  v_escritores text[] := '{}';
  v_n_fun integer := 0;
begin
  begin
  select d.id, d.phone into v_dono, v_phone from public._comprovante_dono() d;
  if v_dono is null or v_phone is null then
    raise exception '0: sem o dono (_comprovante_dono) no banco';
  end if;
  -- as pendências e perguntas reais só são afastadas dentro da transação (como no teste do cartão da P8)
  update public.ai_operator_pending_actions set status = 'expired' where status = 'pending';
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste' where status = 'aberta';
  update public.ai_operator_sessions set metadata = metadata - 'pendencias_guardadas' where external_thread_key = v_phone;
  update public.retorno_config
     set modo = 'sombra', parceiro_modo = 'sombra', parceiro_tipos_ligados = '{}', parceiro_cadastro_ligado = false,
         previa_modo = 'desligado', previa_ditado_ligado = false, pdf_parceiro_ligado = false, pdf_sem_espera_ligado = false,
         cartao_max_itens = 3, coleta_max = 2, parceiro_carencia = '30 minutes', parceiro_coleta_espera = '24 hours',
         parceiro_pedido_validade = '14 days', proximo_envio_em = null, segura_tudo_ate = null, so_reativo = false,
         iniciadas_dia_max = 50, segura_patio = false, patio_nivel = 'cartao'
   where id;
  select c.carencia_min into v_carencia from public.retorno_config c where c.id;

  insert into public.parceiros (nome, sigla, tipo) values ('Revenda C13 F4', 'RCT', 'revenda_e_patio') returning id into v_p;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Milena', 'comercial') returning id into v_mil;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Carla', 'comercial') returning id into v_carla;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Rosa', 'comercial') returning id into v_rosa;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel, recebe_documento)
    values (v_mil, c_n1, '00016801', '47', 'confirmado', c_t - interval '30 days', true, true) returning id into v_n1;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel, recebe_documento)
    values (v_carla, c_n2, '00016802', '47', 'confirmado', c_t - interval '30 days', false, true) returning id into v_n2;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel, recebe_documento)
    values (v_rosa, c_n3, '00016803', '47', 'confirmado', c_t - interval '30 days', false, true) returning id into v_n3;
  -- o cliente que já tem o número que a parceira vai passar (duplicado por telefone, 21)
  v_existente := pg_temp.f4q_cliente('Cliente Existente C13', '5547900016905');

  -- ── 3. Nunca consulta clients.name; a leitura nem lê clients ──
  for v_rec in
    select p.proname, p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('parceiro_coleta_ler', 'parceiro_cadastro_provisorio', '_parceiro_veiculo_rotulo')
  loop
    v_n_fun := v_n_fun + 1;
    if v_rec.prosrc ~* '\.name\M' or v_rec.prosrc ~* '\mname\s*(=|~|like|ilike|similar)' then
      raise exception '3a: % procura por nome', v_rec.proname;
    end if;
  end loop;
  if v_n_fun is distinct from 3
     or (select p.prosrc from pg_proc p where p.oid = 'public.parceiro_coleta_ler(uuid, timestamptz)'::regprocedure) ~* 'public\.clients' then
    raise exception '3b: parceiro_coleta_ler lê clients (ou faltou função: %)', v_n_fun;
  end if;
  v_n_fun := 0;

  -- ── 14 (estrutural). Só cinco funções escrevem parceiro_pedidos.estado ──
  for v_rec in
    select p.oid::regprocedure::text as nome, p.proname, p.prosrc
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f' and p.prosrc ~* 'parceiro_pedidos'
  loop
    if exists (select 1 from regexp_matches(v_rec.prosrc, 'update\s+public\.parceiro_pedidos[^;]*', 'gi') as m(x)
                where split_part(lower(m.x[1]), ' where ', 1) ~ '\mestado\s*=')
       or exists (select 1 from regexp_matches(v_rec.prosrc, 'insert\s+into\s+public\.parceiro_pedidos\s*\(([^)]*)\)', 'gi') as m(x)
                   where m.x[1] ~* '\mestado\M') then
      v_escritores := v_escritores || v_rec.proname;
    end if;
  end loop;
  if (v_escritores <@ array['_parceiro_triar', 'parceiro_pedido_rodada', 'parceiro_cartao_executar', 'parceiro_pedido_desfazer',
                                'parceiro_previa_soltar']) is not true
     or (array['parceiro_pedido_rodada', 'parceiro_cartao_executar', 'parceiro_pedido_desfazer', 'parceiro_previa_soltar'] <@ v_escritores) is not true then
    raise exception '14a: quem escreve parceiro_pedidos.estado (%)', v_escritores;
  end if;

  -- ── 6 e 20 (byte a byte). Os corpos da F3 que a P10 não muda ──
  if (select md5(replace(p.prosrc, E'\r', '')) from pg_proc p
       where p.oid = 'public.retorno_previa_preparar(uuid, uuid, uuid, timestamptz, uuid)'::regprocedure) is distinct from '9e9fb07745dfcd913429638475f26ada'
     or (select md5(replace(p.prosrc, E'\r', '')) from pg_proc p
          where p.oid = 'public.retorno_previa_caiu(uuid, uuid, text, timestamptz)'::regprocedure) is distinct from 'efdeaba2fdddd767e4384c5babe4c417'
     or (select md5(replace(p.prosrc, E'\r', '')) from pg_proc p
          where p.oid = 'public.retorno_previa_pdf(uuid, boolean, text, timestamptz, uuid, uuid, uuid)'::regprocedure) is distinct from '50f9fb38389f30ec823085c2fe49c97f'
     or (select md5(replace(p.prosrc, E'\r', '')) from pg_proc p
          where p.oid = 'public.retorno_previa_soltar(uuid, timestamptz)'::regprocedure) is distinct from '665a8d8cdac6594aba5110ae93321fce' then
    raise exception '6a/20a: um corpo da F3 mudou (preparar, caiu, pdf ou soltar)';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'retorno_previa_preparar') is distinct from 1::bigint
     or (select p.prosrc from pg_proc p where p.oid = 'public.retorno_previa_rodada(timestamptz)'::regprocedure)
        !~ 'a\.papel = ''parceiro'' and exists \(select 1 from public\.parceiro_pedidos pp where pp\.abertura_id = a\.id and pp\.estado in \(''cadastrado'', ''cartao''\) and pp\.client_id is not null\)' then
    raise exception '6b: o preparar da F3 ganhou outra assinatura ou a rodada não tem a condição do parceiro';
  end if;

  -- ── 2, 22 e 12. A leitura do pedido (frases inventadas), a intenção do caso e o que não é pedido ──
  v_caso := pg_temp.f4q_abrir(c_n1, 'Preciso de orçamento de bateria pra Daily do João, ele tá aqui', c_t);
  v_ped := pg_temp.f4q_ped(v_caso);
  if v_ped.id is null or v_ped.estado is distinct from 'coleta' or v_ped.veiculo is distinct from 'Daily'
     or v_ped.primeiro_nome is distinct from 'João' or v_ped.completo_em is null or v_ped.whatsapp_informado is not null
     or v_ped.parceiro_id is distinct from v_p or v_ped.pessoa_id is distinct from v_mil then
    raise exception '2a: "Daily do João" (%)', to_jsonb(v_ped);
  end if;
  v_s := pg_temp.f4q_saida(v_caso, 'parceiro_coleta', 'veiculo_nome');
  if v_s.dedupe_key is distinct from 'parceiro:coleta:' || v_caso || ':1:sombra' or v_s.dados ->> 'pedido_id' is distinct from v_ped.id::text
     or pg_temp.f4q_conta(v_caso, 'parceiro_recibo', null) is distinct from 0::bigint then
    raise exception '2b: o P03 do pedido (%)', to_jsonb(v_s);
  end if;
  perform pg_temp.f4q_fechar(v_caso, c_t + interval '9 minutes');

  v_caso := pg_temp.f4q_abrir(c_n1, 'Preciso trocar a bateria do carro de um cliente', c_t + interval '10 minutes');
  v_ped := pg_temp.f4q_ped(v_caso);
  if v_ped.veiculo is distinct from 'Automóvel' or v_ped.primeiro_nome is not null or v_ped.completo_em is not null then
    raise exception '2c: "carro de um cliente" (%)', to_jsonb(v_ped);
  end if;
  perform pg_temp.f4q_fechar(v_caso, c_t + interval '19 minutes');

  v_nc := (select count(*) from public.clients);
  v_caso := pg_temp.f4q_abrir(c_n1, 'Orçamento de bateria pro motorhome do cliente, o João da oficina leva', c_t + interval '20 minutes');
  v_ped := pg_temp.f4q_ped(v_caso);
  select * into v_ab from public.retorno_aberturas a where a.id = v_caso;
  if v_ped.veiculo is distinct from 'Motorhome' or v_ped.primeiro_nome is not null
     or (select count(*) from public.clients) is distinct from v_nc then
    raise exception '2d: "o João da oficina" virou cliente ou nome (%)', to_jsonb(v_ped);
  end if;
  -- 22: o caso do parceiro com pedido tem nível recibo e a intenção orcamento; forçado a nada, nulo
  if v_ab.nivel is distinct from 'recibo' or v_ab.intencao is distinct from 'pedido_servico' or v_ab.tipo_recibo is distinct from 'recibo_parceiro'
     or public._retorno_intencao_do_caso(v_caso, c_t + interval '21 minutes') is distinct from 'orcamento' then
    raise exception '22a: a intenção do caso do parceiro (% % %)', v_ab.nivel, v_ab.intencao,
                    public._retorno_intencao_do_caso(v_caso, c_t + interval '21 minutes');
  end if;
  update public.retorno_aberturas set nivel = 'nada', motivo = 'parceiro_f4', tipo_recibo = null where id = v_caso;
  if public._retorno_intencao_do_caso(v_caso, c_t + interval '21 minutes') is not null then
    raise exception '22b: caso em nada com intenção';
  end if;
  perform pg_temp.f4q_fechar(v_caso, c_t + interval '29 minutes');

  -- 12: "pode fazer" é recado, nunca pedido; pergunta pelo nome não abre coleta
  v_caso := pg_temp.f4q_abrir(c_n1, 'pode fazer a troca da bateria', c_t + interval '30 minutes');
  if pg_temp.f4q_ped(v_caso) is not null or pg_temp.f4q_conta(v_caso, 'parceiro_recado', null) is distinct from 1::bigint then
    raise exception '12a: "pode fazer" virou pedido';
  end if;
  perform pg_temp.f4q_fechar(v_caso, c_t + interval '39 minutes');
  v_caso := pg_temp.f4q_abrir(c_n1, 'como tá a bateria do joão?', c_t + interval '40 minutes');
  if pg_temp.f4q_ped(v_caso) is not null or pg_temp.f4q_conta(v_caso, 'parceiro_coleta', 'veiculo_nome') is distinct from 0::bigint
     or pg_temp.f4q_conta(v_caso, 'parceiro_recibo', null) is distinct from 1::bigint then
    raise exception '12b: "como tá a bateria do joão?" abriu coleta';
  end if;
  perform pg_temp.f4q_fechar(v_caso, c_t + interval '49 minutes');

  -- ── 23 e 1. P04 nunca antes do P03; com o P03 decidido, o enviar_em de P2.1; a 3ª mensagem não sai ──
  v_caso := pg_temp.f4q_abrir(c_n1, 'Orçamento de inversor pro motorhome de um cliente, por favor', c_t + interval '50 minutes');
  perform pg_temp.f4q_alinhar(v_caso);
  v_s := pg_temp.f4q_saida(v_caso, 'parceiro_coleta', 'veiculo_nome');
  perform pg_temp.f4q_abrir(c_n1, 'É o motorhome do Pedro', c_t + interval '52 minutes');
  v_ped := pg_temp.f4q_ped(v_caso);
  if pg_temp.f4q_conta(v_caso, 'parceiro_coleta', 'whatsapp') is distinct from 0::bigint
     or v_ped.primeiro_nome is distinct from 'Pedro' or v_ped.completo_em is distinct from c_t + interval '52 minutes' then
    raise exception '23a: a resposta antes do P03 decidido (% %)', pg_temp.f4q_conta(v_caso, 'parceiro_coleta', 'whatsapp'), to_jsonb(v_ped);
  end if;
  perform pg_temp.f4q_decidir(v_s.id, 'sombra', v_s.enviar_em);
  if (select a.coleta_n from public.retorno_aberturas a where a.id = v_caso) is distinct from 1::smallint then
    raise exception '13a: o P03 em sombra não somou coleta_n';
  end if;
  perform pg_temp.f4q_abrir(c_n1, 'Tem sim, vou ver com ele', v_s.enviar_em + interval '5 minutes');
  v_s2 := pg_temp.f4q_saida(v_caso, 'parceiro_coleta', 'whatsapp');
  if v_s2.id is null or v_s2.dedupe_key is distinct from 'parceiro:coleta:' || v_caso || ':2:sombra'
     or v_s2.enviar_em is distinct from greatest(v_s.enviar_em + interval '5 minutes' + make_interval(mins => v_carencia),
                                                 v_s.enviar_em + interval '1 minute') then
    raise exception '23b: o P04 depois do P03 (%)', to_jsonb(v_s2);
  end if;
  perform pg_temp.f4q_decidir(v_s2.id, 'sombra', v_s2.enviar_em);
  perform pg_temp.f4q_abrir(c_n1, 'Ele ainda não respondeu, te aviso', v_s2.enviar_em + interval '3 minutes');
  if pg_temp.f4q_conta(v_caso, 'parceiro_coleta', 'veiculo_nome') + pg_temp.f4q_conta(v_caso, 'parceiro_coleta', 'whatsapp') is distinct from 2::bigint
     or (select a.coleta_n from public.retorno_aberturas a where a.id = v_caso) is distinct from 2::smallint
     or pg_temp.f4q_conta(v_caso, 'parceiro_recibo', null) is distinct from 0::bigint then
    raise exception '1a: a 3ª mensagem da coleta saiu, ou nasceu P02';
  end if;
  perform pg_temp.f4q_fechar(v_caso, c_t + interval '1 hour 35 minutes');

  -- ── 13, 15 (chave desligada), 6, 16 e 19. A resposta "Daily do João" depois do P03; o cartão com cadastro_simulado ──
  v_caso := pg_temp.f4q_abrir(c_n2, 'Orçamento de placa solar pro motorhome de um cliente', c_t + interval '1 hour 40 minutes');
  perform pg_temp.f4q_alinhar(v_caso);
  v_s := pg_temp.f4q_saida(v_caso, 'parceiro_coleta', 'veiculo_nome');
  perform pg_temp.f4q_decidir(v_s.id, 'sombra', v_s.enviar_em);                -- 12:10
  perform pg_temp.f4q_abrir(c_n2, 'Daily do João', c_t + interval '2 hours 20 minutes');
  v_ped := pg_temp.f4q_ped(v_caso);
  v_s2 := pg_temp.f4q_saida(v_caso, 'parceiro_coleta', 'whatsapp');
  if v_ped.veiculo is distinct from 'Motorhome' or v_ped.primeiro_nome is distinct from 'João'
     or v_ped.completo_em is distinct from c_t + interval '2 hours 20 minutes'
     or v_s2.dedupe_key is distinct from 'parceiro:coleta:' || v_caso || ':2:sombra'
     or pg_temp.f4q_conta(v_caso, 'parceiro_recibo', null) is distinct from 0::bigint then
    raise exception '13b: a resposta "Daily do João" (% %)', to_jsonb(v_ped), to_jsonb(v_s2);
  end if;
  perform public._retorno_triar(v_caso, c_t + interval '2 hours 21 minutes');
  if pg_temp.f4q_conta(v_caso, 'parceiro_coleta', 'whatsapp') is distinct from 1::bigint then
    raise exception '13c: a triagem repetida criou outro P04';
  end if;
  perform pg_temp.f4q_decidir(v_s2.id, 'sombra', c_t + interval '2 hours 25 minutes');
  -- pronto para decidir: o P04 decidido há parceiro_carencia. Com a chave desligada, cartao com o "criaria" e nada real.
  v_nc := (select count(*) from public.clients);
  v_nv := (select count(*) from public.vessels);
  if public.parceiro_pedido_rodada(c_t + interval '2 hours 50 minutes') ->> 'rodou' is distinct from 'true'
     or (pg_temp.f4q_ped(v_caso)).estado is distinct from 'coleta' then
    raise exception '15a: a coleta saiu antes da carência do P04';
  end if;
  v_r := public.parceiro_pedido_rodada(c_t + interval '2 hours 56 minutes');
  v_ped := pg_temp.f4q_ped(v_caso);
  v_f := pg_temp.f4q_fila('pedido:' || v_ped.id);
  if v_ped.estado is distinct from 'cartao' or v_ped.client_id is not null or v_ped.cadastro_simulado ->> 'acao' is distinct from 'criaria'
     or v_ped.cadastro_simulado -> 'unidade' ->> 'asset_type' is distinct from 'Motorhome' or v_ped.cadastro_simulado ->> 'nome' is distinct from 'João'
     or (select count(*) from public.clients) is distinct from v_nc or (select count(*) from public.vessels) is distinct from v_nv
     or v_f.id is null or v_f.tipo is distinct from 'pedido' or v_f.prioridade is distinct from 3::smallint or v_f.referencia is distinct from v_ped.id
     or v_f.valido_ate is distinct from v_ped.criado_em + interval '14 days' or v_f.estado is distinct from 'espera' then
    raise exception '15b: chave desligada (% / % / %)', v_r, to_jsonb(v_ped), to_jsonb(v_f);
  end if;
  v_r := public.parceiro_cadastro_provisorio(v_ped.id, true);
  if v_r is distinct from '{"acao": "nada", "motivo": "desligado"}'::jsonb then
    raise exception '15c: o cadastro chamado direto com a chave desligada (%)', v_r;
  end if;
  -- 6: em cartao sem client_id, a montagem da proposta recusa pelo papel
  update public.retorno_config set previa_modo = 'sombra' where id;
  if public.retorno_previa_montar(v_caso, c_t + interval '2 hours 57 minutes') ->> 'motivo' is distinct from 'papel' then
    raise exception '6c: proposta para pedido sem client_id';
  end if;
  update public.retorno_config set previa_modo = 'desligado' where id;
  -- 19: a mensagem que completou a coleta não agenda o P15
  perform public._retorno_triar(v_caso, c_t + interval '2 hours 57 minutes');
  if pg_temp.f4q_conta(v_caso, 'parceiro_recibo', 'orcamento') is distinct from 0::bigint then
    raise exception '19a: a mensagem que completou a coleta agendou o P15';
  end if;
  -- 16: o 2º pedido no mesmo caso só conta; "e aí?" não sobe; a reavaliação mantém
  perform pg_temp.f4q_abrir(c_n2, 'Precisa também de orçamento de inversor pro trailer da Ana', c_t + interval '2 hours 58 minutes');
  v_ped2 := pg_temp.f4q_ped(v_caso);
  if v_ped2.mais_pedidos is distinct from 1::smallint or v_ped2.veiculo is distinct from 'Motorhome' or v_ped2.primeiro_nome is distinct from 'João'
     or (select count(*) from public.parceiro_pedidos pp where pp.abertura_id = v_caso) is distinct from 1::bigint
     or pg_temp.f4q_conta(v_caso, 'parceiro_recibo', null) is distinct from 0::bigint then
    raise exception '16a: o 2º pedido no mesmo caso (%)', to_jsonb(v_ped2);
  end if;
  perform pg_temp.f4q_abrir(c_n2, 'e aí?', c_t + interval '2 hours 59 minutes');
  perform public._retorno_triar(v_caso, c_t + interval '3 hours');
  if (pg_temp.f4q_ped(v_caso)).mais_pedidos is distinct from 1::smallint then
    raise exception '16b: "e aí?" ou a reavaliação mexeu em mais_pedidos (%)', (pg_temp.f4q_ped(v_caso)).mais_pedidos;
  end if;
  v_x := public.parceiro_pedido_montar(v_ped.id, 1::smallint, c_t + interval '3 hours');
  if coalesce(v_x ->> 'texto_mostrado', '') not like '1. Pedido da RCT (Carla) para cliente dela · João (sem cadastro) · Motorhome · ''Orçamento de placa solar pro motorhome de um cliente''%'
     or coalesce(v_x ->> 'texto_mostrado', '') not like '%+1 pedidos nesta conversa, ainda sem dados: leia no celular%'
     or coalesce(v_x ->> 'texto_mostrado', '') not like '%Sem cadastro, nada foi criado: responda pelo celular. *resolvido 1*'
     or jsonb_array_length(v_x -> 'opcoes') is distinct from 0 or v_x ->> 'hash' is null then
    raise exception '16c/15d: o item do pedido sem cadastro (%)', v_x ->> 'texto_mostrado';
  end if;
  -- 19: em cartao, a mensagem nova depois de completo_em agenda o P15 uma vez, com dados.pedido_id
  v_s := pg_temp.f4q_saida(v_caso, 'parceiro_recibo', 'orcamento');
  if pg_temp.f4q_conta(v_caso, 'parceiro_recibo', 'orcamento') is distinct from 1::bigint
     or v_s.dedupe_key is distinct from 'parceiro:recibo:' || v_caso || ':orcamento:sombra'
     or v_s.dados ->> 'pedido_id' is distinct from v_ped.id::text
     or v_s.enviar_em is distinct from c_t + interval '2 hours 58 minutes' + make_interval(mins => v_carencia) then
    raise exception '19b: o P15 (%)', to_jsonb(v_s);
  end if;
  -- 19: a linha 5 do parceiro_pegar não exige interessado_ids no P15
  update public.retorno_saidas set estado = 'cancelada', motivo = 'caso_fechado', decidida_em = c_t
   where emissor = 'parceiro' and estado = 'agendada' and id <> v_s.id;
  update public.retorno_config set proximo_envio_em = null where id;
  perform public.parceiro_pegar(v_s.enviar_em + interval '1 minute');
  select * into v_s from public.retorno_saidas s where s.id = v_s.id;
  if v_s.estado is distinct from 'preparada' or v_s.motivo is not null
     or coalesce(v_s.texto, '') not like 'Carla, aqui é a Claudia, assistente virtual da HBR. O orçamento do motorhome de João está com o Gustavo;%' then
    raise exception '19c: o P15 no parceiro_pegar (% % %)', v_s.estado, v_s.motivo, v_s.texto;
  end if;
  -- 16: caso fechado: o pedido novo abre outro caso e outra linha; "oi" num caso novo não abre coleta
  perform pg_temp.f4q_fechar(v_caso, c_t + interval '3 hours 10 minutes');
  v_caso2 := pg_temp.f4q_abrir(c_n2, 'oi', c_t + interval '3 hours 12 minutes');
  if v_caso2 is not distinct from v_caso or pg_temp.f4q_ped(v_caso2) is not null
     or pg_temp.f4q_conta(v_caso2, 'parceiro_coleta', 'veiculo_nome') is distinct from 0::bigint then
    raise exception '16d: "oi" depois do caso fechado abriu coleta';
  end if;
  perform pg_temp.f4q_fechar(v_caso2, c_t + interval '3 hours 14 minutes');
  v_caso2 := pg_temp.f4q_abrir(c_n2, 'Orçamento de bateria pro trailer da Ana', c_t + interval '3 hours 15 minutes');
  if pg_temp.f4q_ped(v_caso2) is null or (pg_temp.f4q_ped(v_caso2)).id is not distinct from v_ped.id then
    raise exception '16e: o pedido do caso novo não abriu linha nova';
  end if;
  perform pg_temp.f4q_fechar(v_caso2, c_t + interval '3 hours 20 minutes');
  -- 28 (parte): a rodada leva os pedidos dos casos fechados a caiu/caso_fechado
  perform public.parceiro_pedido_rodada(c_t + interval '3 hours 21 minutes');
  if (pg_temp.f4q_ped(v_caso)).estado is distinct from 'caiu' or (pg_temp.f4q_ped(v_caso)).caiu_motivo is distinct from 'caso_fechado'
     or (pg_temp.f4q_fila('pedido:' || v_ped.id)).estado is distinct from 'caiu' then
    raise exception '14b: caso fechado com pedido em cartao (%)', to_jsonb(pg_temp.f4q_ped(v_caso));
  end if;

  -- ── 21 (chave desligada) e 28. Duplicado por telefone em cadastro_simulado; *resolvido 1* no pedido ──
  v_caso := pg_temp.f4q_abrir(c_n1, 'Orçamento de inversor pro motorhome do Davi, pode passar o número 47 90001-6905',
                              c_t + interval '3 hours 30 minutes');
  perform pg_temp.f4q_alinhar(v_caso);
  v_ped := pg_temp.f4q_ped(v_caso);
  if v_ped.whatsapp_informado is distinct from '5547900016905' or v_ped.autoriza_whatsapp is not true
     or v_ped.primeiro_nome is distinct from 'Davi' then
    raise exception '21a: o número autorizado na mesma mensagem (%)', to_jsonb(v_ped);
  end if;
  v_nc := (select count(*) from public.clients);
  perform public.parceiro_pedido_rodada(c_t + interval '3 hours 31 minutes');
  v_ped := pg_temp.f4q_ped(v_caso);
  if v_ped.estado is distinct from 'cartao' or v_ped.client_id is not null
     or v_ped.cadastro_simulado is distinct from '{"acao": "perguntar", "duplicados": 1}'::jsonb
     or (select count(*) from public.clients) is distinct from v_nc then
    raise exception '21b: duplicado em cadastro_simulado (%)', to_jsonb(v_ped);
  end if;
  perform pg_temp.f4q_abrir(c_n1, 'E aí, conseguiu ver?', c_t + interval '3 hours 35 minutes');
  if pg_temp.f4q_conta(v_caso, 'parceiro_recibo', 'orcamento') is distinct from 1::bigint then
    raise exception '28a: falta o P15 agendado';
  end if;
  v_cartao := pg_temp.f4q_cartao(array[(pg_temp.f4q_fila('pedido:' || v_ped.id)).id], c_t + interval '3 hours 36 minutes');
  v_i := pg_temp.f4q_item(v_cartao, 1);
  if v_i.tipo is distinct from 'pedido' or v_i.pedido_id is distinct from v_ped.id or pg_temp.f4q_letras(v_cartao, 1) is distinct from ''
     or coalesce(v_i.texto_mostrado, '') not like '1. Pedido da RCT (Milena) para cliente dela · Davi · Motorhome · %'
     or coalesce(v_i.texto_mostrado, '') not like '%o número que a RCT passou (••6905) já é de um cliente cadastrado; nada foi criado: responda pelo celular ou orce na tela para ele. *resolvido 1*'
     or v_i.texto_mostrado like '%90001%' then
    raise exception '21c: o item duplicado (%)', v_i.texto_mostrado;
  end if;
  v_r := pg_temp.f4q_dito('{"comando": "resolvido", "n": 1}', c_t + interval '3 hours 37 minutes');
  select * into v_ab from public.retorno_aberturas a where a.id = v_caso;
  v_s := pg_temp.f4q_saida(v_caso, 'parceiro_recibo', 'orcamento');
  if v_ab.estado is distinct from 'fechada' or v_ab.fechada_motivo is distinct from 'dono'
     or v_s.estado is distinct from 'cancelada' or v_s.motivo is distinct from 'caso_fechado'
     or (pg_temp.f4q_item(v_cartao, 1)).estado is distinct from 'caiu' or (pg_temp.f4q_item(v_cartao, 1)).caiu_motivo is distinct from 'caso_fechado'
     or (pg_temp.f4q_fila('pedido:' || v_ped.id)).estado is distinct from 'feito'
     or (pg_temp.f4q_ped(v_caso)).estado is distinct from 'cartao' then
    raise exception '28b: *resolvido 1* no pedido (%)', v_r;
  end if;
  perform public.parceiro_pedido_rodada(c_t + interval '3 hours 38 minutes');
  if (pg_temp.f4q_ped(v_caso)).estado is distinct from 'caiu' or (pg_temp.f4q_ped(v_caso)).caiu_motivo is distinct from 'caso_fechado' then
    raise exception '28c: a rodada não levou o pedido a caiu/caso_fechado';
  end if;

  -- ── A chave ligada: parceiro_modo ligado, parceiro_coleta ligado e parceiro_cadastro_ligado ──
  update public.retorno_config
     set parceiro_modo = 'ligado', parceiro_tipos_ligados = '{parceiro_coleta}', parceiro_cadastro_ligado = true where id;

  -- ── 15 (ligada), 4, 5, 10, 24, 6, 18 e 17. O cadastro real, a unidade, o número só no pedido e a letra D ──
  v_cli := pg_temp.f4q_cliente('Pedro', null);                                      -- 4: o nome igual não casa
  v_caso := pg_temp.f4q_abrir(c_n3, 'Orçamento de bateria pro motorhome do Pedro, pode chamar ele no 47 90001-6901', c_t + interval '4 hours');
  perform pg_temp.f4q_alinhar(v_caso);
  v_ped := pg_temp.f4q_ped(v_caso);
  update public.retorno_config set previa_modo = 'sombra' where id;
  if v_ped.estado is distinct from 'coleta' or v_ped.whatsapp_informado is distinct from '5547900016901'
     or public.retorno_previa_montar(v_caso, c_t + interval '4 hours 30 seconds') ->> 'motivo' is distinct from 'papel' then
    raise exception '6d: em coleta, a proposta não recusa pelo papel (%)', to_jsonb(v_ped);
  end if;
  v_nc := (select count(*) from public.clients);
  v_nv := (select count(*) from public.vessels);
  perform public.parceiro_pedido_rodada(c_t + interval '4 hours 1 minute');
  v_ped := pg_temp.f4q_ped(v_caso);
  if v_ped.estado is distinct from 'cadastrado' or v_ped.client_id is null or v_ped.client_id = v_cli or v_ped.vessel_id is null
     or (select count(*) from public.clients) is distinct from v_nc + 1 or (select count(*) from public.vessels) is distinct from v_nv + 1
     or not exists (select 1 from public.clients c where c.id = v_ped.client_id and c.name = 'Pedro' and c.provisorio and c.origem = 'retorno'
                                                     and c.active and c.whatsapp is null)
     or not exists (select 1 from public.vessels v where v.id = v_ped.vessel_id and v.asset_type = 'Motorhome' and v.name = 'Motorhome'
                                                     and v.client_id = v_ped.client_id and v.active)
     or not exists (select 1 from public.audit_log l where l.table_name = 'clients' and l.record_id = v_ped.client_id
                                                       and l.new_value ->> 'caso' = v_caso::text)
     or v_ped.whatsapp_informado is distinct from '5547900016901' then
    raise exception '15e/4a/10a/24a: o cadastro com a chave ligada (%)', to_jsonb(v_ped);
  end if;
  v_r := public._retorno_cadastro_do_caso(v_caso);
  if v_r ->> 'client_id' is distinct from v_ped.client_id::text or v_r ->> 'vessel_id' is distinct from v_ped.vessel_id::text
     or (v_r ->> 'provisorio')::boolean is not true then
    raise exception '5a: _retorno_cadastro_do_caso não achou o provisório (%)', v_r;
  end if;
  if public.retorno_previa_montar(v_caso, c_t + interval '4 hours 1 minute 30 seconds') ->> 'motivo' = 'papel' then
    raise exception '6e: em cadastrado com client_id, a proposta recusou pelo papel';
  end if;
  perform public.parceiro_pedido_rodada(c_t + interval '4 hours 2 minutes');
  v_ped := pg_temp.f4q_ped(v_caso);
  if v_ped.estado is distinct from 'cartao' or (pg_temp.f4q_fila('pedido:' || v_ped.id)).estado is distinct from 'espera' then
    raise exception '14c: cadastrado → cartao na rodada seguinte (%)', to_jsonb(v_ped);
  end if;
  if public.retorno_previa_montar(v_caso, c_t + interval '4 hours 2 minutes 30 seconds') ->> 'motivo' = 'papel' then
    raise exception '6f: em cartao com client_id, a proposta recusou pelo papel';
  end if;
  update public.retorno_config set previa_modo = 'desligado' where id;
  -- 18 (sem proposta nem rascunho) e 17: sem A e B, com D; o número só como ••NNNN
  v_cartao := pg_temp.f4q_cartao(array[(pg_temp.f4q_fila('pedido:' || v_ped.id)).id], c_t + interval '4 hours 3 minutes');
  v_i := pg_temp.f4q_item(v_cartao, 1);
  if pg_temp.f4q_letras(v_cartao, 1) is distinct from 'D' or v_i.retrato ->> 'acao' is not null
     or coalesce(v_i.texto_mostrado, '') not like '1. Pedido da RCT (Rosa) para cliente dela · Pedro (cadastro provisório) · Motorhome · %'
     or coalesce(v_i.texto_mostrado, '') not like '%Sem proposta. Dite ao assistente ou orce na tela; o PDF volta aqui.%'
     or coalesce(v_i.texto_mostrado, '') not like '%*1 D* desfaz o cadastro%' or v_i.texto_mostrado like '%90001%'
     or coalesce(v_i.texto_mostrado, '') not like '% · número passado pela RCT: ••6901%' then
    raise exception '18a/17a/10b: o item sem proposta (% / %)', pg_temp.f4q_letras(v_cartao, 1), v_i.texto_mostrado;
  end if;
  -- 17: autor que não é o dono
  begin
    perform public.parceiro_pedido_desfazer(v_ped.id, gen_random_uuid(), c_t + interval '4 hours 3 minutes');
    raise exception '17b: outro autor desfez';
  exception when insufficient_privilege then
    null;
  end;
  perform pg_temp.f4q_dito('{"comando": "escolher", "n": 1, "letra": "D"}', c_t + interval '4 hours 4 minutes');
  v_r := pg_temp.f4q_sim(v_cartao, c_t + interval '4 hours 5 minutes');
  v_ped2 := pg_temp.f4q_ped(v_caso);
  if v_ped2.estado is distinct from 'caiu' or v_ped2.caiu_motivo is distinct from 'desfeito' or v_ped2.whatsapp_informado is not null
     or exists (select 1 from public.clients c where c.id = v_ped.client_id and c.active)
     or exists (select 1 from public.vessels v where v.client_id = v_ped.client_id and v.active)
     or (pg_temp.f4q_fila('pergunta:' || v_caso)).estado is distinct from 'espera'
     or not exists (select 1 from public.audit_log l where l.table_name = 'clients' and l.record_id = v_ped.client_id and l.action = 'update'
                                                       and l.changed_by = 'dono' and l.new_value ->> 'active' = 'false')
     or public._retorno_cadastro_do_caso(v_caso) is not null
     or coalesce(v_r ->> 'aviso', '') not like '%o 1: cadastro desfeito%' then
    raise exception '17c: a letra D (% / %)', v_r, to_jsonb(v_ped2);
  end if;
  perform pg_temp.f4q_fechar(v_caso, c_t + interval '4 hours 50 minutes');

  -- ── 18 (rascunho), 8, 27 (cliente), 26, 19 (decidido), 11 e 20. A letra A com o número passado pela parceira ──
  update public.retorno_config set previa_ditado_ligado = true where id;
  v_caso := pg_temp.f4q_abrir(c_n3, 'Orçamento de inversor pro trailer da Ana, ela autorizou passar o número 47 90001-6902',
                              c_t + interval '5 hours');
  perform pg_temp.f4q_alinhar(v_caso);
  perform public.parceiro_pedido_rodada(c_t + interval '5 hours 1 minute');
  perform public.parceiro_pedido_rodada(c_t + interval '5 hours 2 minutes');
  v_ped := pg_temp.f4q_ped(v_caso);
  if v_ped.estado is distinct from 'cartao' or v_ped.veiculo is distinct from 'Trailer' or v_ped.primeiro_nome is distinct from 'Ana' then
    raise exception '8a: o pedido da Ana não chegou ao cartão (%)', to_jsonb(v_ped);
  end if;
  v_rasc := pg_temp.f4q_rascunho(v_ped.client_id, v_ped.vessel_id, 'ORÇ-98901', c_t + interval '5 hours 3 minutes', 800);
  v_cartao := pg_temp.f4q_cartao(array[(pg_temp.f4q_fila('pedido:' || v_ped.id)).id], c_t + interval '5 hours 4 minutes');
  v_i := pg_temp.f4q_item(v_cartao, 1);
  if pg_temp.f4q_letras(v_cartao, 1) is distinct from 'A' or v_i.retrato ->> 'acao' is distinct from 'pdf'
     or v_i.service_order_id is distinct from v_rasc or v_i.retrato ->> 'numero' is distinct from 'ORÇ-98901'
     or coalesce(v_i.texto_mostrado, '') not like '%Rascunho ORÇ-98901 de 12/01: 1 item · R$ %'
     or coalesce(v_i.texto_mostrado, '') not like '%*1 A* ao cliente ••6902 (passado pela RCT)%' or v_i.texto_mostrado like '%90001%' then
    raise exception '18b/8b/17d: o item com rascunho e só o número da parceira (% / %)', pg_temp.f4q_letras(v_cartao, 1), v_i.texto_mostrado;
  end if;
  -- 8: o número passou a ser de outro cliente entre o item e o *sim*: nada sai, nada é copiado, o pedido fica em cartao
  v_outro := pg_temp.f4q_cliente('Outro Cliente C13', '5547900016902');
  perform pg_temp.f4q_dito('{"comando": "escolher", "n": 1, "letra": "A"}', c_t + interval '5 hours 5 minutes');
  v_r := pg_temp.f4q_sim(v_cartao, c_t + interval '5 hours 6 minutes');
  if (pg_temp.f4q_ped(v_caso)).estado is distinct from 'cartao' or jsonb_array_length(v_r -> 'orcamentos') is distinct from 0
     or exists (select 1 from public.clients c where c.id = v_ped.client_id and c.whatsapp is not null)
     or (pg_temp.f4q_fila('pedido:' || v_ped.id)).estado is distinct from 'espera'
     or coalesce(v_r ->> 'aviso', '') not like '%já é de outro cliente; nada saiu%' then
    raise exception '8c: o número de outro cliente (%)', v_r;
  end if;
  update public.clients set whatsapp = null, active = false where id = v_outro;
  -- 8: a letra A com só o número passado pela parceira: copiado ao cadastro no *sim*, antes de qualquer envio
  v_cartao := pg_temp.f4q_cartao(array[(pg_temp.f4q_fila('pedido:' || v_ped.id)).id], c_t + interval '5 hours 7 minutes');
  perform pg_temp.f4q_dito('{"comando": "escolher", "n": 1, "letra": "A"}', c_t + interval '5 hours 8 minutes');
  v_r := pg_temp.f4q_sim(v_cartao, c_t + interval '5 hours 9 minutes');
  v_i := pg_temp.f4q_item(v_cartao, 1);
  v_x := v_r -> 'orcamentos' -> 0;
  if jsonb_array_length(v_r -> 'orcamentos') is distinct from 1 or v_x ->> 'destino' is distinct from 'cliente' or v_x ->> 'acao' is distinct from 'pdf'
     or v_x ->> 'service_order_id' is distinct from v_rasc::text or v_x ->> 'pedido_id' is distinct from v_ped.id::text
     or v_x ->> 'parceiro_id' is distinct from v_p::text or (v_x ->> 'sem_enviar')::boolean is not false
     or (pg_temp.f4q_ped(v_caso)).estado is distinct from 'decidido'
     or (select c.whatsapp from public.clients c where c.id = v_ped.client_id) is distinct from '5547900016902'
     or (pg_temp.f4q_fila('pedido:' || v_ped.id)).estado is distinct from 'feito' or v_i.estado is distinct from 'feito' then
    raise exception '8d: a letra A (%)', v_r;
  end if;
  -- 19: em decidido, nenhum P15
  perform pg_temp.f4q_abrir(c_n3, 'Conseguiu mandar para ela?', c_t + interval '5 hours 10 minutes');
  if pg_temp.f4q_conta(v_caso, 'parceiro_recibo', 'orcamento') is distinct from 0::bigint then
    raise exception '19d: P15 com o pedido decidido';
  end if;
  -- 27, 26 e 6: o preparo do parceiro no ramo pdf, ao cliente: o formato da F3 com parceiro_id; a regra 6 pulada (o número do
  -- cliente não é o do caso); a regra 7 passa no caso do parceiro (nível recibo)
  if (select a.nivel from public.retorno_aberturas a where a.id = v_caso) is distinct from 'recibo' then
    raise exception '26a: o caso do parceiro não está em recibo';
  end if;
  v_r := public.parceiro_previa_preparar(v_ped.id, null, v_i.id, v_dono, v_rasc, 'cliente', c_t + interval '5 hours 11 minutes');
  if (v_r ->> 'ok')::boolean is not true or v_r ->> 'acao' is distinct from 'pdf' or v_r ->> 'parceiro_id' is distinct from v_p::text
     or v_r ->> 'pedido_id' is distinct from v_ped.id::text or v_r ->> 'destino' is distinct from 'cliente' or v_r ->> 'numero' is distinct from 'ORÇ-98901'
     or v_r ->> 'abertura_id' is distinct from v_caso::text or v_r -> 'legenda' ->> 'texto' is null
     or v_r -> 'legenda' -> 'contexto' ->> 'audiencia' is distinct from 'cliente' then
    raise exception '27a/26a/6g: o preparo do parceiro ao cliente (%)', v_r;
  end if;
  v_x := public.parceiro_previa_preparar(v_ped.id, null, v_i.id, gen_random_uuid(), v_rasc, 'cliente', c_t + interval '5 hours 11 minutes');
  if (v_x ->> 'ok')::boolean is not false or v_x ->> 'motivo' is distinct from 'nao_e_o_dono' then
    raise exception '27b: o preparo de outro autor (%)', v_x;
  end if;
  -- 8 e 27: o vínculo nasce no destino cliente, indicou e sem requalificar; o rascunho sem origem ganha a do parceiro; o
  -- aviso ao cliente é agendado ao número que o *sim* copiou. Revisão de 10/11 (banco-1): com o tipo do aviso fora de
  -- parceiro_tipos_ligados, a saída nasce em sombra e o vínculo devolve aviso 'sombra', nunca 'agendado'
  v_r := public.parceiro_vinculo_do_pedido(v_ped.id, v_rasc, v_dono, 'cliente', c_t + interval '5 hours 12 minutes');
  select * into v_oi from public.os_interessados oi where oi.service_order_id = v_rasc and oi.parceiro_id = v_p;
  if (v_r ->> 'ok')::boolean is not true or v_r ->> 'papel' is distinct from 'indicou' or (v_r ->> 'requalificado')::boolean is not false
     or v_oi.situacao is distinct from 'confirmado' or v_oi.papel is distinct from 'indicou' or v_oi.origem is distinct from 'numero_do_pedido'
     or v_oi.pessoa_id is distinct from v_rosa or v_oi.base is distinct from 'legitimo_interesse'
     or (select so.origem_parceiro_id from public.service_orders so where so.id = v_rasc) is distinct from v_p
     or not exists (select 1 from public.audit_log l where l.table_name = 'service_orders' and l.record_id = v_rasc and l.action = 'update')
     or v_r ->> 'aviso' is distinct from 'sombra'
     or not exists (select 1 from public.retorno_saidas s where s.tipo = 'parceiro_aviso_cliente' and s.phone_normalized = '5547900016902'
                                                         and s.modo = 'sombra') then
    raise exception '8e/27c: o vínculo do pedido ao cliente (% / %)', v_r, to_jsonb(v_oi);
  end if;
  -- 11: o soltar leva o pedido de volta a cartao e a fila de feito a espera; o enviado fecha o caso
  v_r := public.parceiro_previa_soltar(v_i.id, c_t + interval '5 hours 13 minutes');
  if (v_r ->> 'ok')::boolean is not true or (pg_temp.f4q_item(v_cartao, 1)).estado is distinct from 'fora'
     or (pg_temp.f4q_ped(v_caso)).estado is distinct from 'cartao' or (pg_temp.f4q_fila('pedido:' || v_ped.id)).estado is distinct from 'espera' then
    raise exception '11a: o soltar do parceiro (%)', v_r;
  end if;
  perform public.parceiro_item_enviado(v_i.id, true, null, c_t + interval '5 hours 14 minutes');
  select * into v_ab from public.retorno_aberturas a where a.id = v_caso;
  if v_ab.estado is distinct from 'fechada' or v_ab.cumprida_por is distinct from 'cartao' then
    raise exception '11b: o enviado não fechou o caso (% %)', v_ab.estado, v_ab.cumprida_por;
  end if;
  -- 20: o PDF e o caiu do parceiro atualizam parceiro_cartao_itens
  v_cartao := pg_temp.f4q_cartao(array[(pg_temp.f4q_fila('pedido:' || v_ped.id)).id], c_t + interval '5 hours 15 minutes');
  v_i := pg_temp.f4q_item(v_cartao, 1);
  perform public.parceiro_previa_pdf(null, true, '00016902', c_t + interval '5 hours 16 minutes', v_rasc, v_caso, v_i.id);
  if (pg_temp.f4q_item(v_cartao, 1)).estado is distinct from 'feito'
     or not exists (select 1 from public.retorno_previa p where p.service_order_id = v_rasc and p.origem = 'rascunho' and p.pdf_chave = '00016902') then
    raise exception '20b: o PDF do parceiro não marcou o item (%)', (pg_temp.f4q_item(v_cartao, 1)).estado;
  end if;
  perform public.parceiro_previa_caiu(null, v_i.id, 'orc_existe', c_t + interval '5 hours 17 minutes');
  if (pg_temp.f4q_item(v_cartao, 1)).estado is distinct from 'caiu' or (pg_temp.f4q_item(v_cartao, 1)).caiu_motivo is distinct from 'orc_existe'
     or (select c.estado from public.parceiro_cartoes c where c.id = v_cartao) is distinct from 'decidido' then
    raise exception '20c: o caiu do parceiro (% %)', (pg_temp.f4q_item(v_cartao, 1)).estado, (pg_temp.f4q_item(v_cartao, 1)).caiu_motivo;
  end if;
  update public.ai_operator_pending_actions set status = 'rejected'
   where id = (select c.pendencia_id from public.parceiro_cartoes c where c.id = v_cartao) and status = 'pending';

  -- ── 7, 9 (sem espera), 24 (Daily), 27 (parceiro) e 18 (orcar). A letra B com a proposta, à parceira ──
  update public.retorno_config set pdf_parceiro_ligado = true, pdf_sem_espera_ligado = true, previa_modo = 'ligado' where id;
  v_caso := pg_temp.f4q_abrir(c_n3, 'Orçamento de gerador pra Daily do Lucas, pode ligar no 47 90001-6903', c_t + interval '6 hours');
  perform pg_temp.f4q_alinhar(v_caso);
  perform public.parceiro_pedido_rodada(c_t + interval '6 hours 1 minute');
  perform public.parceiro_pedido_rodada(c_t + interval '6 hours 2 minutes');
  v_ped := pg_temp.f4q_ped(v_caso);
  if v_ped.estado is distinct from 'cartao'
     or not exists (select 1 from public.vessels v where v.id = v_ped.vessel_id and v.asset_type = 'Veículo' and v.name = 'Daily')
     or public._parceiro_bem(v_ped.vessel_id) is distinct from 'veículo' then
    raise exception '24b: a unidade do provisório só com o modelo (%)', to_jsonb(v_ped);
  end if;
  insert into public.retorno_previa (abertura_id, chave, client_id, vessel_id, origem, fonte_numero, titulo, estado, modo, total, linhas_n,
                                     provisorios_n, hash, criada_em, atualizada_em)
    values (v_caso, '00016803', v_ped.client_id, v_ped.vessel_id, 'historico', 'ORÇ-98902', 'Instalação de gerador', 'proposta', 'ligado',
            1500, 1, 0, 'teste-c13', c_t + interval '6 hours 3 minutes', c_t + interval '6 hours 3 minutes')
    returning id into v_previa;
  insert into public.retorno_previa_linhas (previa_id, ordem, tipo, nome, quantidade, preco, preco_fonte, estado)
    values (v_previa, 1, 'servico', 'Instalação de gerador', 1, 1500, 'dito', 'ok');
  v_cartao := pg_temp.f4q_cartao(array[(pg_temp.f4q_fila('pedido:' || v_ped.id)).id], c_t + interval '6 hours 4 minutes');
  v_i := pg_temp.f4q_item(v_cartao, 1);
  if pg_temp.f4q_letras(v_cartao, 1) is distinct from 'ABD' or v_i.retrato ->> 'acao' is distinct from 'orcar'
     or v_i.retrato ->> 'previa_id' is distinct from v_previa::text
     or coalesce(v_i.texto_mostrado, '') not like '%Proposta com base no ORÇ-98902: 1 item · R$ %'
     or coalesce(v_i.texto_mostrado, '') not like '%*1 B* à RCT (ela contrata?)%'
     or coalesce(v_i.texto_mostrado, '') not like '%o PDF à RCT leva preço e Pix de Lucas; fica registrado como decisão sua%' then
    raise exception '18c/7a: o item com proposta e a letra B (% / %)', pg_temp.f4q_letras(v_cartao, 1), v_i.texto_mostrado;
  end if;
  perform pg_temp.f4q_dito('{"comando": "escolher", "n": 1, "letra": "B"}', c_t + interval '6 hours 5 minutes');
  v_r := pg_temp.f4q_sim(v_cartao, c_t + interval '6 hours 6 minutes');
  v_i := pg_temp.f4q_item(v_cartao, 1);
  v_x := v_r -> 'orcamentos' -> 0;
  if v_x ->> 'destino' is distinct from 'parceiro' or v_x ->> 'acao' is distinct from 'orcar' or v_x ->> 'previa_id' is distinct from v_previa::text
     or (v_x ->> 'sem_enviar')::boolean is not false or (pg_temp.f4q_ped(v_caso)).estado is distinct from 'decidido' then
    raise exception '9a: a letra B com pdf_sem_espera_ligado (%)', v_r;
  end if;
  -- 27: o preparo à parceira, no ramo orcar: P16, validador do parceiro com o {Lucas}, origem retorno_parceiro, sem
  -- recusar por "sem unidade" (24)
  v_r := public.parceiro_previa_preparar(v_ped.id, v_previa, v_i.id, v_dono, null, 'parceiro', c_t + interval '6 hours 7 minutes');
  if (v_r ->> 'ok')::boolean is not true or v_r ->> 'acao' is distinct from 'orcar' or v_r ->> 'parceiro_id' is distinct from v_p::text
     or v_r -> 'args' ->> 'origem' is distinct from 'retorno_parceiro' or v_r -> 'args' ->> 'vessel_id' is distinct from v_ped.vessel_id::text
     or coalesce(v_r -> 'legenda' ->> 'texto', '') not like 'Rosa, aqui é a Claudia, assistente virtual da HBR. Segue o orçamento do veículo de Lucas, válido até __/__.'
     or v_r -> 'legenda' -> 'contexto' ->> 'audiencia' is distinct from 'parceiro'
     or (v_r -> 'legenda' -> 'contexto' -> 'nomes_da_lista' ? 'Lucas') is not true then
    raise exception '27d/24c: o preparo à parceira (%)', v_r;
  end if;
  -- o ORÇ que montarOrcamento criaria (P12), com a origem do parceiro
  v_orc := pg_temp.f4q_rascunho(v_ped.client_id, v_ped.vessel_id, 'ORÇ-98903', c_t + interval '6 hours 8 minutes', 1500, v_p);
  -- 7: a requalificação que falha não deixa nada: nem vínculo, nem aviso
  alter function public.parceiro_requalificar(uuid, text, uuid, text, timestamptz, uuid) rename to parceiro_requalificar_real;
  create function public.parceiro_requalificar(p_interessado uuid, p_papel text, p_autor uuid, p_base text default 'decisao_do_dono',
                                               p_agora timestamptz default now(), p_pessoa uuid default null)
  returns jsonb language sql as $s$ select jsonb_build_object('ok', false, 'motivo', 'teste') $s$;
  v_r := public.parceiro_vinculo_do_pedido(v_ped.id, v_orc, v_dono, 'parceiro', c_t + interval '6 hours 9 minutes');
  drop function public.parceiro_requalificar(uuid, text, uuid, text, timestamptz, uuid);
  alter function public.parceiro_requalificar_real(uuid, text, uuid, text, timestamptz, uuid) rename to parceiro_requalificar;
  if (v_r ->> 'ok')::boolean is not false or v_r ->> 'motivo' is distinct from 'requalificar_teste' or coalesce(v_r ->> 'frase', '') not like '%nada saiu'
     or exists (select 1 from public.os_interessados oi where oi.service_order_id = v_orc)
     or exists (select 1 from public.retorno_saidas s where s.tipo = 'parceiro_aviso_cliente' and s.phone_normalized = '5547900016903') then
    raise exception '7b: a requalificação que falha deixou rastro (%)', v_r;
  end if;
  -- 7 e 9: requalifica a contratante com base decisao_do_dono; o destino do PDF é o número da Rosa; o painel segue fechado
  v_r := public.parceiro_vinculo_do_pedido(v_ped.id, v_orc, v_dono, 'parceiro', c_t + interval '6 hours 10 minutes');
  select * into v_oi from public.os_interessados oi where oi.service_order_id = v_orc and oi.parceiro_id = v_p;
  if (v_r ->> 'ok')::boolean is not true or v_r ->> 'papel' is distinct from 'contratante' or (v_r ->> 'requalificado')::boolean is not true
     or v_oi.papel is distinct from 'contratante' or v_oi.base is distinct from 'decisao_do_dono' or v_oi.pacote is distinct from 'completo'
     or not exists (select 1 from public.audit_log l where l.table_name = 'os_interessados' and l.record_id = v_oi.id and l.action = 'update')
     or not exists (select 1 from public.retorno_saidas s where s.tipo = 'parceiro_aviso_cliente' and s.phone_normalized = '5547900016903') then
    raise exception '7c: a requalificação da letra B (% / %)', v_r, to_jsonb(v_oi);
  end if;
  v_x := public.parceiro_destino_do_pdf(v_orc, v_dono, v_p, c_t + interval '6 hours 11 minutes');
  if (v_x ->> 'ok')::boolean is not true or v_x ->> 'phone' is distinct from c_n3 or v_x ->> 'papel' is distinct from 'contratante'
     or (public.parceiro_os_visivel(v_oi.id, c_t + interval '6 hours 11 minutes') ->> 'visivel')::boolean is not false then
    raise exception '9b: o destino do PDF à contratante sem espera, e o painel (% / %)', v_x,
                    public.parceiro_os_visivel(v_oi.id, c_t + interval '6 hours 11 minutes');
  end if;
  perform pg_temp.f4q_fechar(v_caso, c_t + interval '6 hours 50 minutes');

  -- ── 9 (com espera, sem telefone) e o "pronto para decidir" pelo P04 decidido há parceiro_carencia ──
  update public.retorno_config set pdf_sem_espera_ligado = false, previa_modo = 'desligado' where id;
  v_caso := pg_temp.f4q_abrir(c_n3, 'Orçamento de bateria pro motorhome da Bia', c_t + interval '7 hours');
  perform pg_temp.f4q_alinhar(v_caso);
  v_s := pg_temp.f4q_saida(v_caso, 'parceiro_coleta', 'veiculo_nome');
  perform pg_temp.f4q_decidir(v_s.id, 'enviada', v_s.enviar_em);                -- 17:30
  perform pg_temp.f4q_abrir(c_n3, 'Ela não tem whatsapp', c_t + interval '7 hours 32 minutes');
  v_s2 := pg_temp.f4q_saida(v_caso, 'parceiro_coleta', 'whatsapp');
  perform pg_temp.f4q_decidir(v_s2.id, 'enviada', c_t + interval '7 hours 36 minutes');
  perform public.parceiro_pedido_rodada(c_t + interval '7 hours 50 minutes');
  if (pg_temp.f4q_ped(v_caso)).estado is distinct from 'coleta' then
    raise exception '14d: pronto antes da carência do P04';
  end if;
  perform public.parceiro_pedido_rodada(c_t + interval '8 hours 7 minutes');
  perform public.parceiro_pedido_rodada(c_t + interval '8 hours 8 minutes');
  v_ped := pg_temp.f4q_ped(v_caso);
  if v_ped.estado is distinct from 'cartao' or v_ped.client_id is null or v_ped.whatsapp_informado is not null then
    raise exception '14e: o pedido pronto pelo P04 decidido (%)', to_jsonb(v_ped);
  end if;
  v_rasc := pg_temp.f4q_rascunho(v_ped.client_id, v_ped.vessel_id, 'ORÇ-98904', c_t + interval '8 hours 9 minutes', 600);
  v_cartao := pg_temp.f4q_cartao(array[(pg_temp.f4q_fila('pedido:' || v_ped.id)).id], c_t + interval '8 hours 10 minutes');
  v_i := pg_temp.f4q_item(v_cartao, 1);
  if pg_temp.f4q_letras(v_cartao, 1) is distinct from 'B'
     or coalesce(v_i.texto_mostrado, '') not like '%*1 B* à RCT (ela contrata?) (o PDF só sai depois do aviso e de 24 h)%'
     or coalesce(v_i.texto_mostrado, '') not like '%ao cliente: quando tiver o número%' then
    raise exception '8f/9c: o item sem telefone e com espera (% / %)', pg_temp.f4q_letras(v_cartao, 1), v_i.texto_mostrado;
  end if;
  perform pg_temp.f4q_dito('{"comando": "escolher", "n": 1, "letra": "B"}', c_t + interval '8 hours 11 minutes');
  v_r := pg_temp.f4q_sim(v_cartao, c_t + interval '8 hours 12 minutes');
  v_x := v_r -> 'orcamentos' -> 0;
  if v_x ->> 'destino' is distinct from 'parceiro' or (v_x ->> 'sem_enviar')::boolean is not true or v_x ->> 'acao' is distinct from 'pdf'
     or (pg_temp.f4q_ped(v_caso)).estado is distinct from 'decidido' or (pg_temp.f4q_fila('pedido:' || v_ped.id)).estado is distinct from 'feito' then
    raise exception '9d: a letra B sem espera desligada (%)', v_r;
  end if;
  -- o vínculo nasce (ramo pdf: o rascunho ganha a origem, sem os_fora), confirmado, e sem telefone o aviso vai à fila
  v_r := public.parceiro_vinculo_do_pedido(v_ped.id, v_rasc, v_dono, 'parceiro', c_t + interval '8 hours 13 minutes');
  select * into v_oi from public.os_interessados oi where oi.service_order_id = v_rasc and oi.parceiro_id = v_p;
  if (v_r ->> 'ok')::boolean is not true or v_r ->> 'aviso' is distinct from 'pendente' or v_oi.situacao is distinct from 'confirmado'
     or v_oi.papel is distinct from 'contratante' or (select so.origem_parceiro_id from public.service_orders so where so.id = v_rasc) is distinct from v_p
     or (pg_temp.f4q_fila('aviso:' || v_oi.id)).id is null then
    raise exception '9e: o vínculo sem telefone (% / %)', v_r, to_jsonb(v_oi);
  end if;
  -- o PDF só sai depois do aviso e de 24 h; o próximo *parceiro* não traz o pedido de novo
  v_x := public.parceiro_destino_do_pdf(v_rasc, v_dono, v_p, c_t + interval '8 hours 14 minutes');
  if (v_x ->> 'ok')::boolean is not false or v_x ->> 'motivo' is distinct from 'sem_aviso'
     or exists (select 1 from public._parceiro_cartao_candidatos(c_t + interval '8 hours 15 minutes', null) x
                 where x.referencia = v_ped.id) then
    raise exception '9f: o PDF sem espera desligada, ou o pedido voltou à fila (%)', v_x;
  end if;
  perform pg_temp.f4q_fechar(v_caso, c_t + interval '8 hours 20 minutes');

  -- ── 21 (chave ligada), 4 (duplicado) e 25. O duplicado por telefone não cria; o P15 cai com a resposta do dono ──
  v_caso := pg_temp.f4q_abrir(c_n3, 'Orçamento de bateria pro motorhome do Caio, pode chamar no 47 90001-6905', c_t + interval '8 hours 30 minutes');
  perform pg_temp.f4q_alinhar(v_caso);
  v_nc := (select count(*) from public.clients);
  v_nv := (select count(*) from public.vessels);
  perform public.parceiro_pedido_rodada(c_t + interval '8 hours 31 minutes');
  v_ped := pg_temp.f4q_ped(v_caso);
  if v_ped.estado is distinct from 'cartao' or v_ped.client_id is not null or v_ped.cadastro_simulado ->> 'acao' is distinct from 'perguntar'
     or (select count(*) from public.clients) is distinct from v_nc or (select count(*) from public.vessels) is distinct from v_nv
     or public.parceiro_cadastro_provisorio(v_ped.id, true) ->> 'acao' is distinct from 'perguntar' then
    raise exception '21d/4b: duplicado com a chave ligada (%)', to_jsonb(v_ped);
  end if;
  v_cartao := pg_temp.f4q_cartao(array[(pg_temp.f4q_fila('pedido:' || v_ped.id)).id], c_t + interval '8 hours 32 minutes');
  v_r := pg_temp.f4q_sim(v_cartao, c_t + interval '8 hours 33 minutes');
  if pg_temp.f4q_letras(v_cartao, 1) is distinct from '' or (pg_temp.f4q_ped(v_caso)).estado is distinct from 'cartao'
     or jsonb_array_length(v_r -> 'orcamentos') is distinct from 0 or (select count(*) from public.clients) is distinct from v_nc then
    raise exception '21e: o *sim* no item duplicado mudou algo (%)', v_r;
  end if;
  perform pg_temp.f4q_abrir(c_n3, 'Conseguiu ver o orçamento?', c_t + interval '8 hours 35 minutes');
  v_s := pg_temp.f4q_saida(v_caso, 'parceiro_recibo', 'orcamento');
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at, hora_real, raw_payload)
    values ('outbound', c_n3, 'text', 'ok', 'teste-f4-c13-25-ok', c_t + interval '8 hours 36 minutes', c_t + interval '8 hours 36 minutes', '{"data": {}}'::jsonb);
  update public.retorno_saidas set estado = 'cancelada', motivo = 'caso_fechado', decidida_em = c_t
   where emissor = 'parceiro' and estado = 'agendada' and id <> v_s.id;
  update public.retorno_config set proximo_envio_em = null where id;
  perform public.parceiro_pegar(v_s.enviar_em + interval '1 minute');
  select * into v_s from public.retorno_saidas s where s.id = v_s.id;
  if v_s.estado is distinct from 'cancelada' or v_s.motivo is distinct from 'respondida_pelo_dono' then
    raise exception '25a: a resposta do dono não derrubou o P15 (% %)', v_s.estado, v_s.motivo;
  end if;
  -- 14: cartao vencido (criado_em + parceiro_pedido_validade) cai por validade, e a pergunta vai à fila
  update public.parceiro_pedidos set criado_em = criado_em - interval '15 days' where id = v_ped.id;
  perform public.parceiro_pedido_rodada(c_t + interval '8 hours 45 minutes');
  if (pg_temp.f4q_ped(v_caso)).estado is distinct from 'caiu' or (pg_temp.f4q_ped(v_caso)).caiu_motivo is distinct from 'validade'
     or (pg_temp.f4q_fila('pedido:' || v_ped.id)).estado is distinct from 'caiu'
     or (pg_temp.f4q_fila('pergunta:' || v_caso)).estado is distinct from 'espera' then
    raise exception '14i: o pedido vencido no cartão (%)', to_jsonb(pg_temp.f4q_ped(v_caso));
  end if;
  perform pg_temp.f4q_fechar(v_caso, c_t + interval '8 hours 50 minutes');

  -- ── 29. Revisão de 10/11 (seguranca-c13): o número que a parceira passa nunca é dela nem da casa. Na coleta, o número do
  --    próprio caso, o de outra pessoa da parceira e o de um favorecido são descartados, e a leitura segue até o número do
  --    cliente; no *sim*, o pedido que traz o número da parceira (o que a leitura de antes gravaria) não copia ao cadastro e,
  --    ao cliente, nada sai. Telefones 5547900016807 (favorecido) e 5547900016906 (cliente); documento ORÇ-98905 ──
  insert into public.payees (name, kind, active, phone) values ('Favorecido C13', 'prestador', true, '5547900016807');
  v_caso := pg_temp.f4q_abrir(c_n3, 'Orçamento de bateria pro motorhome do Ivo, liberado falar comigo no 47 90001-6803, com a Carla no 47 90001-6802 ou no 47 90001-6807',
                              c_t + interval '8 hours 51 minutes');
  v_ped := pg_temp.f4q_ped(v_caso);
  if v_ped.id is null or v_ped.primeiro_nome is distinct from 'Ivo' or v_ped.whatsapp_informado is not null
     or v_ped.autoriza_whatsapp is true then
    raise exception '29a: o número da parceira ou da casa virou o do cliente (%)', to_jsonb(v_ped);
  end if;
  if public._parceiro_fone_da_casa('5547900016906', v_caso) is not false or public._parceiro_fone_da_casa(c_n3, v_caso) is not true
     or public._parceiro_fone_da_casa(c_n2, v_caso) is not true or public._parceiro_fone_da_casa('5547900016807', v_caso) is not true
     or public._parceiro_fone_da_casa(null, v_caso) is not false then
    raise exception '29b: _parceiro_fone_da_casa';
  end if;
  perform pg_temp.f4q_fechar(v_caso, c_t + interval '8 hours 52 minutes');
  v_caso := pg_temp.f4q_abrir(c_n3, 'Orçamento de bateria pro motorhome do Ivo, pode falar comigo no 47 90001-6803 ou com ele no 47 90001-6906',
                              c_t + interval '8 hours 53 minutes');
  perform pg_temp.f4q_alinhar(v_caso);
  v_ped := pg_temp.f4q_ped(v_caso);
  if v_ped.whatsapp_informado is distinct from '5547900016906' or v_ped.autoriza_whatsapp is not true then
    raise exception '29c: a leitura não seguiu até o número do cliente (%)', to_jsonb(v_ped);
  end if;
  perform public.parceiro_pedido_rodada(c_t + interval '8 hours 54 minutes');
  perform public.parceiro_pedido_rodada(c_t + interval '8 hours 55 minutes');
  v_ped := pg_temp.f4q_ped(v_caso);
  if v_ped.estado is distinct from 'cartao' or v_ped.client_id is null then
    raise exception '29d: o pedido do Ivo não chegou ao cartão (%)', to_jsonb(v_ped);
  end if;
  v_rasc := pg_temp.f4q_rascunho(v_ped.client_id, v_ped.vessel_id, 'ORÇ-98905', c_t + interval '8 hours 56 minutes', 700);
  -- o pedido com o número da Carla, como a leitura de antes desta revisão gravaria
  update public.parceiro_pedidos set whatsapp_informado = c_n2 where id = v_ped.id;
  v_cartao := pg_temp.f4q_cartao(array[(pg_temp.f4q_fila('pedido:' || v_ped.id)).id], c_t + interval '8 hours 57 minutes');
  v_i := pg_temp.f4q_item(v_cartao, 1);
  if coalesce(v_i.texto_mostrado, '') not like '%*1 A* ao cliente ••6802 (passado pela RCT)%' then
    raise exception '29e: o item com o número da parceira (%)', v_i.texto_mostrado;
  end if;
  perform pg_temp.f4q_dito('{"comando": "escolher", "n": 1, "letra": "A"}', c_t + interval '8 hours 58 minutes');
  v_r := pg_temp.f4q_sim(v_cartao, c_t + interval '8 hours 59 minutes');
  if jsonb_array_length(v_r -> 'orcamentos') is distinct from 0
     or (pg_temp.f4q_ped(v_caso)).estado is distinct from 'cartao'
     or exists (select 1 from public.clients c where c.id = v_ped.client_id and c.whatsapp is not null)
     or (pg_temp.f4q_fila('pedido:' || v_ped.id)).estado is distinct from 'espera'
     or coalesce(v_r ->> 'aviso', '') not like '%o 1: o número passado é da própria parceira; nada saiu%' then
    raise exception '29f: o *sim* com o número da parceira (%)', v_r;
  end if;
  perform pg_temp.f4q_fechar(v_caso, c_t + interval '8 hours 59 minutes 30 seconds');

  -- ── 14. A parceira nunca responde: sem veículo, depois de parceiro_coleta_espera, caiu/sem_resposta, sem cadastro ──
  v_caso := pg_temp.f4q_abrir(c_n1, 'Vim pelo site da HBR Systems, preciso de um orçamento', c_t + interval '9 hours');
  perform pg_temp.f4q_alinhar(v_caso);
  v_ped := pg_temp.f4q_ped(v_caso);
  v_nc := (select count(*) from public.clients);
  v_nv := (select count(*) from public.vessels);
  perform public.parceiro_pedido_rodada(c_t + interval '9 hours 30 minutes');
  if v_ped.id is null or v_ped.veiculo is not null or (pg_temp.f4q_ped(v_caso)).estado is distinct from 'coleta' then
    raise exception '14f: o pedido sem veículo antes do silêncio (%)', to_jsonb(pg_temp.f4q_ped(v_caso));
  end if;
  perform public.parceiro_pedido_rodada(c_t + interval '1 day 9 hours 1 minute');
  v_ped := pg_temp.f4q_ped(v_caso);
  if v_ped.estado is distinct from 'caiu' or v_ped.caiu_motivo is distinct from 'sem_resposta' or v_ped.completo_em is null
     or (select count(*) from public.clients) is distinct from v_nc or (select count(*) from public.vessels) is distinct from v_nv
     or (pg_temp.f4q_fila('pergunta:' || v_caso)).estado is distinct from 'espera' then
    raise exception '14g: a parceira que nunca respondeu (%)', to_jsonb(v_ped);
  end if;
  -- a rodada não roda com o parceiro desligado
  update public.retorno_config set parceiro_modo = 'desligado' where id;
  if public.parceiro_pedido_rodada(c_t + interval '1 day 9 hours 2 minutes') ->> 'rodou' is distinct from 'false' then
    raise exception '14h: a rodada rodou com o parceiro desligado';
  end if;

  -- ── A varredura: as funções da P10 fechadas a anon e authenticated; as do service_role com execute ──
  for v_rec in
    select p.oid, p.proname, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and (p.proname ~ '^_?parceiro_' or p.proname in ('retorno_previa_montar', 'retorno_previa_rodada'))
  loop
    v_n_fun := v_n_fun + 1;
    if has_function_privilege('anon', v_rec.oid, 'execute') or has_function_privilege('authenticated', v_rec.oid, 'execute') then
      raise exception 'grants: % aberta a anon/authenticated', v_rec.nome;
    end if;
    if v_rec.proname !~ '^_' and not has_function_privilege('service_role', v_rec.oid, 'execute') then
      raise exception 'grants: % sem execute para o service_role', v_rec.nome;
    end if;
    if v_rec.prosecdef and not exists (select 1 from unnest(v_rec.config) o where o ~ '^search_path=') then
      raise exception 'grants: % é SECURITY DEFINER sem search_path', v_rec.nome;
    end if;
  end loop;
  if to_regprocedure('public.parceiro_pedido_rodada(timestamptz)') is null
     or to_regprocedure('public.parceiro_previa_preparar(uuid, uuid, uuid, uuid, uuid, text, timestamptz)') is null
     or to_regprocedure('public.parceiro_vinculo_do_pedido(uuid, uuid, uuid, text, timestamptz)') is null
     or to_regprocedure('public.parceiro_requalificar_real(uuid, text, uuid, text, timestamptz, uuid)') is not null then
    raise exception 'grants: a varredura não achou as funções da P10 (%)', v_n_fun;
  end if;

  raise exception 'retorno_f4_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f4_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f4_c13', true, '{}');
end
$c13$;

select arquivo, ok, numeros from _bancada order by em;
rollback;

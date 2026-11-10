-- Retorno F4 (P8): o cartão do parceiro. Um vivo só e as travas de ocupado; as letras de cada tipo de item (inclusive as que
-- não existem); só o dono executa; o item caído por veto não sai e o resto sai; *não N* por tipo; o texto nunca vai a
-- ai_operator_messages; o painel (*N tira L*, *N sabe L*, outro dia); a carteira desmarcada (C, P, R); *parceiro 74* (vínculo
-- e corte, em qualquer modo); aviso e retido; a fila (quem põe, chave, validade, prioridade); o desempate sem repetir; a
-- pergunta (4 letras, "e mais", sem candidata, letra que confirma ou cria); nenhum cartão sem o dono; o lote antes da fila; o
-- cartão vencido, rejeitado por fora e vazio; o repassar em sombra; *resolvido N*; *segura pátio*. Roda só pela bancada
-- (grupo 7, F4_ONDA=6). Termina em ROLLBACK. Telefones de teste 55479000166xx e 55479000167xx; nomes inventados; números de
-- OS 988xx. Relógio: ter 12/01/2027 10:00. Respostas do dono de 09/11 (R1, a etapa no *ver N* e no pátio), no fim:
-- telefones 5547900017651 e 5547900017661, OS-98891.
--
-- Isolamento: antes de cada parceiro de teste ter OS, todo cliente que já existe ganha veto para ele (parceiro_vetos, tabela
-- nova, desfeita no rollback): o lote e as letras só enxergam as OS criadas aqui.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f4k_cliente(p_nome text, p_fone text) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, p_fone) returning id
$f$;

-- A OS (criada antes de hoje: parceiro_propor confere a regra 8 no relógio do banco).
create or replace function pg_temp.f4k_os(p_cliente uuid, p_numero text, p_bem text default 'Motorhome', p_status text default 'open',
                                          p_unidade text default 'Ducato', p_convertida timestamptz default null) returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type) values (p_cliente, p_unidade, p_bem) returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total, converted_to_os_at)
  values (p_numero, p_cliente, v_v, p_status, 'approved', 'repair', '2026-10-01 10:00-03', '2026-10-01 10:00-03', 0, p_convertida)
  returning id into v_id;
  return v_id;
end $f$;

create or replace function pg_temp.f4k_liga(p_os uuid, p_parceiro uuid, p_papel text, p_aviso_em timestamptz default '2027-01-05 10:00-03',
                                            p_aviso text default 'mensagem') returns uuid
language sql as $f$
  insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, situacao, origem, aviso_ao_cliente, aviso_em,
                                      confirmado_em, pacote)
  select so.id, p_parceiro, so.client_id, p_papel, 'confirmado', 'dono',
         case when p_aviso_em is null then 'nao_avisado' else p_aviso end, p_aviso_em, timestamptz '2027-01-01 10:00-03',
         case when p_papel in ('contratante', 'pagador') then 'completo' else 'status' end
    from public.service_orders so where so.id = p_os
  returning id
$f$;

-- Todo cliente que já existe ganha veto para o parceiro de teste.
create or replace function pg_temp.f4k_isolar(p_parceiro uuid) returns void
language sql as $f$
  insert into public.parceiro_vetos (client_id, parceiro_id, em, origem)
  select c.id, p_parceiro, timestamptz '2026-12-01 10:00-03', 'dono' from public.clients c
  on conflict (client_id, parceiro_id) do nothing
$f$;

-- O cartão montado à mão a partir de linhas da fila: a mesma montagem e a mesma pendência do *parceiro*, para testar um tipo
-- de item sem depender da ordem da fila.
create or replace function pg_temp.f4k_cartao(p_filas uuid[], p_agora timestamptz) returns uuid
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
create or replace function pg_temp.f4k_sim(p_cartao uuid, p_agora timestamptz) returns jsonb
language plpgsql as $f$
declare
  v jsonb;
begin
  v := public.parceiro_cartao_executar(p_cartao, (select d.id from public._comprovante_dono() d), p_agora);
  update public.ai_operator_pending_actions p set status = 'executed'
   where p.id = (select c.pendencia_id from public.parceiro_cartoes c where c.id = p_cartao) and p.status = 'pending';
  return v;
end $f$;

create or replace function pg_temp.f4k_dito(p_cmd jsonb, p_agora timestamptz) returns jsonb
language sql as $f$
  select public.parceiro_decidir_dito(p_cmd, (select d.id from public._comprovante_dono() d), p_agora)
$f$;

create or replace function pg_temp.f4k_item(p_cartao uuid, p_n integer) returns public.parceiro_cartao_itens
language sql as $f$
  select i from public.parceiro_cartao_itens i where i.cartao_id = p_cartao and i.n = p_n
$f$;

create or replace function pg_temp.f4k_letras(p_cartao uuid, p_n integer) returns text
language sql as $f$
  select coalesce(string_agg(t.o ->> 'letra', '' order by t.ord), '')
    from public.parceiro_cartao_itens i, jsonb_array_elements(i.opcoes) with ordinality t(o, ord)
   where i.cartao_id = p_cartao and i.n = p_n
$f$;

create or replace function pg_temp.f4k_fila(p_chave text) returns public.parceiro_fila
language sql as $f$
  select f from public.parceiro_fila f where f.chave = p_chave
$f$;

create or replace function pg_temp.f4k_msg(p_fone text, p_corpo text, p_em timestamptz) returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
  values ('inbound', p_fone, 'text', p_corpo, 'teste-f4-cartao-' || md5(p_fone || p_corpo || p_em::text || random()::text), p_em)
  returning id
$f$;

create or replace function pg_temp.f4k_concluir(p_os uuid, p_em timestamptz) returns void
language sql as $f$
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, texto)
  values (p_em, (p_em at time zone 'America/Sao_Paulo')::date, true, 'dono', 'concluir', p_os, 'concluiu no teste')
$f$;

-- Respostas de 09/11 (R1): a etapa do dia, como a F2 a lê (a 1ª tarefa ligada de os_tarefas_dia no dia).
create or replace function pg_temp.f4k_etapa(p_os uuid, p_texto text, p_dia date) returns void
language plpgsql as $f$
declare
  v_t uuid;
begin
  insert into public.os_tarefas (service_order_id, chave, origem, texto, fase, ordem, horas, estado, criada_em, mudou_em)
    values (p_os, 'linha:teste-f4r', 'roteiro', p_texto, 1, 1, 1, 'viva', '2027-01-10 10:00-03', '2027-01-10 10:00-03')
    returning id into v_t;
  insert into public.os_tarefas_dia (tarefa_id, service_order_id, dia, turno, modo, fracao, comeca, termina, posicao, estado,
                                     congelada_em)
    values (v_t, p_os, p_dia, 'manha', 'ligado', 1, true, true, 1, 'planejada', '2027-01-10 10:00-03');
end $f$;

-- Só as linhas dadas ficam em espera: as outras vão a feito (o cenário não depende da ordem da fila).
create or replace function pg_temp.f4k_so_fila(p_ids uuid[]) returns void
language sql as $f$
  update public.parceiro_fila f set estado = 'feito', decidido_em = now()
   where f.estado = 'espera' and not (f.id = any (p_ids))
$f$;

do $cartao$
declare
  c_t constant timestamptz := '2027-01-12 10:00-03';        -- ter
  v_dono uuid;
  v_phone text;
  v_p uuid; v_q uuid; v_s uuid;
  v_carla uuid; v_rosa uuid; v_sol uuid;
  v_n1 uuid; v_n3 uuid; v_n4 uuid;
  v_c uuid; v_c2 uuid;
  v_os uuid; v_os2 uuid; v_os3 uuid;
  v_oss uuid[] := '{}';
  v_int uuid; v_int2 uuid; v_int3 uuid;
  v_cartao uuid; v_cartao2 uuid;
  v_r jsonb;
  v_t text;
  v_vivo jsonb;
  v_ses uuid;
  v_pend uuid;
  v_f public.parceiro_fila;
  v_f2 public.parceiro_fila;
  v_i public.parceiro_cartao_itens;
  v_oi public.os_interessados;
  v_pp public.parceiro_paineis;
  v_m uuid;
  v_caso uuid; v_caso2 uuid;
  v_painel uuid; v_painel2 uuid;
  v_ids uuid[];
  v_vistos1 uuid[]; v_vistos2 uuid[]; v_vistos3 uuid[];
  v_n integer;
  v_k bigint;
  v_toques bigint;
  v_saida uuid;
  v_envio uuid;
  v_rec record;
  v_n_fun integer := 0;
  i integer;
  v_pt uuid; v_nt uuid; v_ot uuid; v_ves uuid; v_fp uuid; v_fq uuid;   -- respostas de 09/11, R1
  v_item jsonb;
  v_linhas jsonb;
begin
  begin
  select d.id, d.phone into v_dono, v_phone from public._comprovante_dono() d;
  if v_dono is null or v_phone is null then
    raise exception '0: sem o dono (_comprovante_dono) no banco';
  end if;
  -- as pendências e perguntas reais só são afastadas dentro da transação (como no teste do cartão da F2)
  update public.ai_operator_pending_actions set status = 'expired' where status = 'pending';
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste' where status = 'aberta';
  update public.ai_operator_sessions set metadata = metadata - 'pendencias_guardadas' where external_thread_key = v_phone;
  update public.retorno_config
     set modo = 'sombra', parceiro_modo = 'desligado', parceiro_tipos_ligados = '{}', cartao_max_itens = 3, segura_patio = false,
         patio_nivel = 'cartao', painel_nivel = 'fechamento', proximo_envio_em = null, segura_tudo_ate = null, so_reativo = false,
         iniciadas_dia_max = 50, pdf_mao_modo = 'desligado'
   where id;

  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Cartão F4', 'RCF', 'revenda_e_patio') returning id into v_p;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Carla', 'comercial') returning id into v_carla;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel)
    values (v_carla, '5547900016601', '00016601', '47', 'confirmado', c_t - interval '30 days', true) returning id into v_n1;
  perform pg_temp.f4k_isolar(v_p);

  -- ── 16a. Desligado: *parceiro* devolve vazio sem tocar em nada; nem o vigia cria cartão; o gatilho fechamento não existe ──
  v_c := pg_temp.f4k_cliente('Ana Carteira', '5547900016701');
  v_oss := v_oss || pg_temp.f4k_os(v_c, 'OS-98801');
  v_r := public.parceiro_cartao_abrir('puxar', c_t);
  if v_r ->> 'acao' is distinct from 'vazio' or exists (select 1 from public.parceiro_cartoes)
     or exists (select 1 from public.os_interessados oi where oi.parceiro_id = v_p) then
    raise exception '16a: desligado abriu ou propôs (%)', v_r;
  end if;
  perform public.parceiro_vigia(c_t);
  update public.retorno_config set parceiro_modo = 'sombra' where id;
  perform public.parceiro_vigia(c_t + interval '1 minute');
  if exists (select 1 from public.parceiro_cartoes) then
    raise exception '16b: o vigia criou cartão';
  end if;
  begin
    insert into public.parceiro_cartoes (gatilho, dia, estado, hash, texto, expira_em) values ('fechamento', '2027-01-12', 'lista', '', '', c_t);
    raise exception '16c: o gatilho fechamento passou no check';
  exception when check_violation then
    null;
  end;
  if public.parceiro_cartao_abrir('meio_dia', c_t) ->> 'acao' is distinct from 'vazio' then
    raise exception '16d: outro gatilho abriu';
  end if;

  -- ── 17, 1 e 13. Oito OS de carteira: o *parceiro* propõe antes de ler a fila (autor o dono), um cartão vivo só, e três
  --    aberturas com *sim <PIN>* sem letra mostram as 8 sem repetir ──
  for i in 2 .. 8 loop
    v_c := pg_temp.f4k_cliente('Cliente' || i || ' Carteira', '554790001670' || i);
    v_oss := v_oss || pg_temp.f4k_os(v_c, 'OS-9880' || i);
  end loop;
  v_r := public.parceiro_cartao_abrir('puxar', c_t);
  v_cartao := (v_r ->> 'cartao_id')::uuid;
  if v_r ->> 'acao' is distinct from 'cartao' or v_cartao is null then
    raise exception '17a: *parceiro* não abriu (%)', v_r;
  end if;
  if (select count(*) from public.os_interessados oi where oi.parceiro_id = v_p) is distinct from 8::bigint
     or exists (select 1 from public.os_interessados oi
                 where oi.parceiro_id = v_p and (oi.situacao is distinct from 'proposto' or oi.origem is distinct from 'carteira'
                                                 or oi.papel is not null or oi.confirmado_por is not null))
     or (select count(*) from public.parceiro_fila f where f.parceiro_id = v_p and f.tipo = 'vinculo') is distinct from 8::bigint then
    raise exception '17b: o lote não propôs as 8 de carteira sem papel';
  end if;
  -- 12 (vinculo): quem põe é parceiro_propor; chave, referência, validade e prioridade
  select * into v_f from public.parceiro_fila f where f.parceiro_id = v_p and f.tipo = 'vinculo' order by f.criado_em limit 1;
  if v_f.chave is distinct from 'vinculo:' || v_f.referencia or v_f.prioridade is distinct from 8::smallint or v_f.valido_ate is not null
     or not exists (select 1 from public.os_interessados oi where oi.id = v_f.referencia) then
    raise exception '12a: a linha vinculo da fila está torta (%)', to_jsonb(v_f);
  end if;
  -- 1: um vivo, pendência parceiro_executar_cartao, e o texto
  select * into v_i from public.parceiro_cartao_itens i where i.cartao_id = v_cartao and i.n = 1;
  if (select count(*) from public.parceiro_cartoes c where c.estado = 'vivo') is distinct from 1::bigint
     or (select count(*) from public.parceiro_cartao_itens i where i.cartao_id = v_cartao) is distinct from 3::bigint
     or not exists (select 1 from public.ai_operator_pending_actions p
                     where p.id = (select c.pendencia_id from public.parceiro_cartoes c where c.id = v_cartao)
                       and p.action_name = 'parceiro_executar_cartao' and p.status = 'pending' and p.risk_level = 'high')
     or v_r ->> 'texto' not like 'Parceiro · 8 esperando%' or v_r ->> 'texto' not like '%e mais 5: *parceiro*%' then
    raise exception '1a: o cartão vivo está torto (%)', v_r;
  end if;
  -- 8 e 2 (vinculo de carteira, com telefone): desmarcado, letras C, P e R
  if v_i.tipo is distinct from 'vinculo' or v_i.selecionado is not false or pg_temp.f4k_letras(v_cartao, 1) is distinct from 'CPR'
     or v_i.texto_mostrado not like '%carteira de motorhome · *1 C* ela indicou · *1 P* só fica no pátio · *1 R* recusa para sempre' then
    raise exception '8a: o vínculo de carteira está torto (% %)', v_i.texto_mostrado, pg_temp.f4k_letras(v_cartao, 1);
  end if;
  -- 1b: o *parceiro* de novo reapresenta, sem outro cartão
  v_r := public.parceiro_cartao_abrir('puxar', c_t + interval '1 minute');
  if v_r ->> 'acao' is distinct from 'reapresenta' or (v_r ->> 'cartao_id')::uuid is distinct from v_cartao
     or (select count(*) from public.parceiro_cartoes) is distinct from 1::bigint then
    raise exception '1b: não reapresentou (%)', v_r;
  end if;
  -- 6: o texto do cartão nunca vai a ai_operator_messages; só o número de itens
  select c.sessao_id into v_ses from public.parceiro_cartoes c where c.id = v_cartao;
  if (select count(*) from public.ai_operator_messages m where m.session_id = v_ses) is distinct from 2::bigint
     or exists (select 1 from public.ai_operator_messages m
                 where m.session_id = v_ses and (m.content like '%OS-988%' or m.content like '%carteira%' or m.content like '%Ducato%'))
     or not exists (select 1 from public.ai_operator_messages m where m.session_id = v_ses and m.content like '%3 itens%') then
    raise exception '6a: o texto do cartão foi a ai_operator_messages';
  end if;
  -- 2: a letra que não existe no item não muda nada
  v_r := pg_temp.f4k_dito('{"comando": "escolher", "n": 1, "letra": "a"}', c_t + interval '2 minutes');
  if v_r ->> 'texto' not like 'O 1 não tem a letra A.%' or (pg_temp.f4k_item(v_cartao, 1)).escolha is not null then
    raise exception '2a: letra inexistente (%)', v_r;
  end if;
  -- 8 e 13: *sim <PIN>* sem letra não confirma; as três voltam à fila com vezes 1
  v_vistos1 := array(select i.fila_id from public.parceiro_cartao_itens i where i.cartao_id = v_cartao);
  v_r := pg_temp.f4k_sim(v_cartao, c_t + interval '3 minutes');
  if exists (select 1 from public.os_interessados oi where oi.parceiro_id = v_p and oi.situacao <> 'proposto')
     or exists (select 1 from public.parceiro_fila f where f.id = any (v_vistos1) and (f.estado <> 'espera' or f.vezes <> 1))
     or (select c.estado from public.parceiro_cartoes c where c.id = v_cartao) is distinct from 'decidido'
     or v_r ->> 'aviso' not like '%escolha a letra antes do *sim*%' then
    raise exception '8b: *sim* sem letra confirmou ou não devolveu à fila (%)', v_r;
  end if;
  v_cartao := (public.parceiro_cartao_abrir('puxar', c_t + interval '4 minutes') ->> 'cartao_id')::uuid;
  v_vistos2 := array(select i.fila_id from public.parceiro_cartao_itens i where i.cartao_id = v_cartao);
  perform pg_temp.f4k_sim(v_cartao, c_t + interval '5 minutes');
  v_cartao := (public.parceiro_cartao_abrir('puxar', c_t + interval '6 minutes') ->> 'cartao_id')::uuid;
  v_vistos3 := array(select i.fila_id from public.parceiro_cartao_itens i where i.cartao_id = v_cartao);
  if cardinality(v_vistos2) is distinct from 3 or cardinality(v_vistos3) is distinct from 3
     or v_vistos1 && v_vistos2
     or (select count(distinct x) from unnest(v_vistos1 || v_vistos2 || v_vistos3) x) is distinct from 8::bigint
     or (select count(*) from unnest(v_vistos3) x where x = any (v_vistos1 || v_vistos2)) is distinct from 1::bigint then
    raise exception '13a: o desempate repetiu antes de mostrar as 8';
  end if;
  -- 8: C grava indicou; P grava anfitria sem aviso e fora de painel, eco e pátio; R grava recusado
  perform pg_temp.f4k_dito('{"comando": "escolher", "n": 1, "letra": "C"}', c_t + interval '7 minutes');
  perform pg_temp.f4k_dito('{"comando": "escolher", "n": 2, "letra": "p"}', c_t + interval '7 minutes');
  perform pg_temp.f4k_dito('{"comando": "escolher", "n": 3, "letra": "R"}', c_t + interval '7 minutes');
  if (select c.texto from public.parceiro_cartoes c where c.id = v_cartao) not like '%*sim <PIN>* faz os 3%' then
    raise exception '8c: o rodapé não diz o que o *sim* faz';
  end if;
  v_int := (pg_temp.f4k_item(v_cartao, 1)).interessado_id;
  v_int2 := (pg_temp.f4k_item(v_cartao, 2)).interessado_id;
  v_int3 := (pg_temp.f4k_item(v_cartao, 3)).interessado_id;
  v_r := pg_temp.f4k_sim(v_cartao, c_t + interval '8 minutes');
  select * into v_oi from public.os_interessados oi where oi.id = v_int;
  if v_oi.situacao is distinct from 'confirmado' or v_oi.papel is distinct from 'indicou' or v_oi.confirmado_por is distinct from v_dono then
    raise exception '8d: C não gravou indicou (%)', v_r;
  end if;
  select * into v_oi from public.os_interessados oi where oi.id = v_int2;
  if v_oi.situacao is distinct from 'confirmado' or v_oi.papel is distinct from 'anfitria' or v_oi.aviso_ao_cliente is distinct from 'nao_avisado'
     or exists (select 1 from public.retorno_saidas s where s.tipo = 'parceiro_aviso_cliente' and s.dados ->> 'client_id' = v_oi.client_id::text)
     or public.parceiro_os_visivel(v_int2, c_t + interval '3 days') ->> 'motivo' is distinct from 'anfitria'
     or exists (select 1 from public.parceiro_os_visiveis(v_p, c_t + interval '3 days') x where x.interessado_id = v_int2) then
    raise exception '8e: P não ficou só no pátio';
  end if;
  if (select oi.situacao from public.os_interessados oi where oi.id = v_int3) is distinct from 'recusado'
     or (pg_temp.f4k_item(v_cartao, 3)).estado is distinct from 'feito' then
    raise exception '8f: R não gravou recusado';
  end if;

  -- ── 17c. O vínculo só vai ao cartão enquanto a OS passa na regra 8 ──
  select f.* into v_f from public.parceiro_fila f
    join public.os_interessados oi on oi.id = f.referencia
   where f.parceiro_id = v_p and f.tipo = 'vinculo' and f.estado = 'espera' and oi.situacao = 'proposto'
   order by f.criado_em, f.id limit 1;
  update public.service_orders so set status = 'cancelled'
   where so.id = (select oi.service_order_id from public.os_interessados oi where oi.id = v_f.referencia);
  if exists (select 1 from public._parceiro_cartao_candidatos(c_t + interval '9 minutes', null) x where x.fila_id = v_f.id) then
    raise exception '17c: vínculo de OS fora da regra 8 virou candidato';
  end if;

  -- ── 14. *não N*, uma linha por tipo; vinculo volta no 15º dia, sem recusar ──
  v_cartao := (public.parceiro_cartao_abrir('puxar', c_t + interval '10 minutes') ->> 'cartao_id')::uuid;
  v_i := pg_temp.f4k_item(v_cartao, 1);
  v_r := pg_temp.f4k_dito('{"comando": "tirar", "ns": [1]}', c_t + interval '11 minutes');
  v_f := pg_temp.f4k_fila('vinculo:' || v_i.interessado_id);
  if (pg_temp.f4k_item(v_cartao, 1)).estado is distinct from 'fora' or v_f.estado is distinct from 'espera'
     or v_f.adiado_ate is distinct from c_t + interval '11 minutes' + interval '14 days'
     or (select oi.situacao from public.os_interessados oi where oi.id = v_i.interessado_id) is distinct from 'proposto'
     or v_r ->> 'texto' is distinct from 'Tirei o 1 do cartão.' then
    raise exception '14a: *não N* no vínculo (%)', v_r;
  end if;
  if exists (select 1 from public._parceiro_cartao_candidatos(c_t + interval '13 days', null) x where x.fila_id = v_f.id)
     or not exists (select 1 from public._parceiro_cartao_candidatos(c_t + interval '15 days', null) x where x.fila_id = v_f.id) then
    raise exception '14b: o vínculo tirado não volta no 15º dia';
  end if;
  -- os outros tipos, pela mesma porta (_parceiro_fila_tirar)
  for v_rec in select * from (values ('painel', 'caiu', null::interval), ('patio', 'caiu', null), ('pergunta', 'espera', null),
                                     ('pedido', 'espera', interval '14 hours'), ('retido', 'espera', interval '14 hours'),
                                     ('pdf_mao', 'espera', interval '14 hours'), ('aviso', 'espera', interval '14 hours'),
                                     ('repassar', 'espera', interval '14 hours')) x(tipo, estado, adiado) loop
    v_m := gen_random_uuid();
    perform public._parceiro_fila_por(v_rec.tipo, v_p, v_m, 'teste14:' || v_rec.tipo || ':' || v_m, null, '{}'::jsonb);
    v_f := pg_temp.f4k_fila('teste14:' || v_rec.tipo || ':' || v_m);
    update public.parceiro_fila f set estado = 'no_cartao' where f.id = v_f.id;
    perform public._parceiro_fila_tirar(v_f.id, v_rec.tipo, c_t);   -- ter 10:00: o "dia seguinte" é qua 00:00, 14 h depois
    v_f := pg_temp.f4k_fila('teste14:' || v_rec.tipo || ':' || v_m);
    if v_f.estado is distinct from v_rec.estado or v_f.adiado_ate is distinct from c_t + v_rec.adiado then
      raise exception '14c: *não N* em % (% %)', v_rec.tipo, v_f.estado, v_f.adiado_ate;
    end if;
  end loop;
  delete from public.parceiro_fila f where f.chave like 'teste14:%';
  perform pg_temp.f4k_dito('{"comando": "tirar", "ns": [2, 3]}', c_t + interval '12 minutes');
  if (select c.estado from public.parceiro_cartoes c where c.id = v_cartao) is distinct from 'decidido' then
    raise exception '14d: o cartão sem item vivo não fechou';
  end if;

  -- ── 4, 5 e 3. Vínculo de sinal forte: selecionado mesmo só com letras de telefone; veto cai sozinho; *não 2*; *2 R*;
  --    só o dono executa ──
  perform pg_temp.f4k_so_fila('{}');
  v_ids := '{}';
  for i in 1 .. 3 loop
    v_c := pg_temp.f4k_cliente('Forte' || i || ' Sinal', case when i = 3 then null else '554790001671' || i end);
    v_os := pg_temp.f4k_os(v_c, 'OS-9882' || i, 'Lancha');
    v_r := public.parceiro_propor(jsonb_build_array(jsonb_build_object('service_order_id', v_os, 'parceiro_id', v_p,
                                                                       'origem', 'numero_do_pedido', 'papel', 'indicou')), v_dono);
    v_ids := v_ids || (pg_temp.f4k_fila('vinculo:' || (v_r -> 'propostos' -> 0 ->> 'interessado_id'))).id;
  end loop;
  v_cartao := pg_temp.f4k_cartao(v_ids, c_t + interval '20 minutes');
  if (pg_temp.f4k_item(v_cartao, 1)).selecionado is not true or pg_temp.f4k_letras(v_cartao, 1) is distinct from 'R'
     or (pg_temp.f4k_item(v_cartao, 3)).selecionado is not true or pg_temp.f4k_letras(v_cartao, 3) is distinct from 'ABR'
     or (pg_temp.f4k_item(v_cartao, 3)).texto_mostrado not like '%(ela indicou) · sem telefone: *3 A* pessoalmente · *3 B* pela revenda · *3 R* recusa para sempre' then
    raise exception '2b: o vínculo de sinal forte está torto (%)', (pg_temp.f4k_item(v_cartao, 3)).texto_mostrado;
  end if;
  -- 3: outro autor não executa
  v_r := public.parceiro_cartao_executar(v_cartao, gen_random_uuid(), c_t + interval '21 minutes');
  if (v_r ->> 'ok')::boolean is not false or (select c.estado from public.parceiro_cartoes c where c.id = v_cartao) is distinct from 'vivo'
     or exists (select 1 from public.os_interessados oi where oi.id = (pg_temp.f4k_item(v_cartao, 1)).interessado_id and oi.situacao <> 'proposto') then
    raise exception '3a: outro autor executou (%)', v_r;
  end if;
  -- 5: *não 2* tira, sem veto; *3 R* recusa
  perform pg_temp.f4k_dito('{"comando": "tirar", "ns": [2]}', c_t + interval '22 minutes');
  perform pg_temp.f4k_dito('{"comando": "escolher", "n": 3, "letra": "R"}', c_t + interval '22 minutes');
  -- 4: o cliente do 1 diz não à parceira antes do *sim*
  insert into public.parceiro_vetos (client_id, parceiro_id, em, origem)
    values ((select oi.client_id from public.os_interessados oi where oi.id = (pg_temp.f4k_item(v_cartao, 1)).interessado_id), v_p,
            c_t + interval '23 minutes', 'nao_mp');
  v_r := pg_temp.f4k_sim(v_cartao, c_t + interval '24 minutes');
  if (pg_temp.f4k_item(v_cartao, 1)).estado is distinct from 'caiu' or (pg_temp.f4k_item(v_cartao, 1)).caiu_motivo is distinct from 'veto'
     or (select oi.situacao from public.os_interessados oi where oi.id = (pg_temp.f4k_item(v_cartao, 1)).interessado_id) is distinct from 'proposto'
     or (pg_temp.f4k_fila('vinculo:' || (pg_temp.f4k_item(v_cartao, 1)).interessado_id)).estado is distinct from 'caiu' then
    raise exception '4a: o item vetado saiu (%)', v_r;
  end if;
  if (pg_temp.f4k_item(v_cartao, 2)).estado is distinct from 'fora'
     or (select oi.situacao from public.os_interessados oi where oi.id = (pg_temp.f4k_item(v_cartao, 2)).interessado_id) is distinct from 'proposto'
     or (select oi.situacao from public.os_interessados oi where oi.id = (pg_temp.f4k_item(v_cartao, 3)).interessado_id) is distinct from 'recusado' then
    raise exception '5a: *não 2* ou *3 R* (%)', v_r;
  end if;
  perform public._parceiro_fila_conferir(c_t + interval '25 minutes');
  if exists (select 1 from public._parceiro_cartao_candidatos(c_t + interval '40 days', null) x
              where x.referencia = (pg_temp.f4k_item(v_cartao, 3)).interessado_id) then
    raise exception '5b: o recusado voltou';
  end if;

  -- ── 7 e 11. O painel: *1 tira 2* (editado, a linha some), *1 sabe 1* (gravado no *sim*, a linha volta a pronto) e o
  --    painel de outro dia, que não executa ──
  perform pg_temp.f4k_so_fila('{}');
  update public.retorno_config set parceiro_modo = 'ligado', parceiro_tipos_ligados = '{parceiro_painel}' where id;
  v_c := pg_temp.f4k_cliente('Bia Painel', '5547900016721');                    -- L1: pronto sem o cliente ouvir
  v_os := pg_temp.f4k_os(v_c, 'OS-98831', 'Lancha', 'completed', 'Ducato', '2027-01-08 15:00-03');
  perform pg_temp.f4k_concluir(v_os, c_t - interval '10 hours');
  v_int := pg_temp.f4k_liga(v_os, v_p, 'indicou');
  v_c := pg_temp.f4k_cliente('Caio Painel', '5547900016722');                   -- L2: em execução, sem data
  v_os2 := pg_temp.f4k_os(v_c, 'OS-98832', 'Lancha', 'in_progress');
  v_int2 := pg_temp.f4k_liga(v_os2, v_p, 'indicou');
  v_r := public.parceiro_painel_montar(v_p, '2027-01-12', c_t);
  v_painel := (v_r ->> 'painel_id')::uuid;
  v_f := pg_temp.f4k_fila('painel:' || v_painel);
  if v_r ->> 'estado' is distinct from 'aguardando' or v_f.prioridade is distinct from 1::smallint
     or v_f.valido_ate is distinct from timestamptz '2027-01-12 18:30-03' or v_f.referencia is distinct from v_painel then
    raise exception '12b: o painel não entrou na fila (%)', v_r;
  end if;
  v_cartao := pg_temp.f4k_cartao(array[v_f.id], c_t + interval '30 minutes');
  v_i := pg_temp.f4k_item(v_cartao, 1);
  if v_i.texto_mostrado not like '1. Pátio da RCF de hoje: 2 veículos, 2 mudaram · *ver 1* mostra · *1 tira 2* tira a linha 2%'
     or pg_temp.f4k_letras(v_cartao, 1) is distinct from '' then
    raise exception '2c: o item painel está torto (%)', v_i.texto_mostrado;
  end if;
  v_r := pg_temp.f4k_dito('{"comando": "escolher", "n": 1, "letra": "A"}', c_t + interval '31 minutes');
  if v_r ->> 'texto' not like 'O 1 não tem letra%' then
    raise exception '2d: o painel aceitou letra (%)', v_r;
  end if;
  v_r := pg_temp.f4k_dito('{"comando": "tira_linha", "n": 1, "linha": 2}', c_t + interval '32 minutes');
  select * into v_pp from public.parceiro_paineis pp where pp.id = v_painel;
  if v_pp.editado is not true
     or (select l ->> 'fora_por' from jsonb_array_elements(v_pp.linhas) l where l ->> 'interessado_id' = v_int2::text) is distinct from 'tirada'
     or (pg_temp.f4k_item(v_cartao, 1)).texto_mostrado not like '1. Pátio da RCF de hoje: 1 veículos%' then
    raise exception '7a: *1 tira 2* (%)', v_r;
  end if;
  v_r := pg_temp.f4k_dito('{"comando": "sabe", "n": 1, "linha": 1}', c_t + interval '33 minutes');
  if v_r ->> 'texto' not like 'Anotado: no *sim <PIN>*, a linha 1 sai como o cliente já sabe (pronto).'
     or exists (select 1 from public.parceiro_cliente_sabe cs where cs.service_order_id = v_os) then
    raise exception '11a: *1 sabe 1* gravou antes do *sim* (%)', v_r;
  end if;
  if pg_temp.f4k_dito('{"comando": "sabe", "n": 1, "linha": 2}', c_t + interval '33 minutes') ->> 'texto' is distinct from 'O painel não tem a linha 2.' then
    raise exception '11b: *sabe* na linha tirada';
  end if;
  v_r := pg_temp.f4k_sim(v_cartao, c_t + interval '34 minutes');
  select * into v_pp from public.parceiro_paineis pp where pp.id = v_painel;
  if v_pp.estado is distinct from 'aprovado' or v_pp.editado is not true
     or not exists (select 1 from public.parceiro_cliente_sabe cs where cs.service_order_id = v_os and cs.marco = 'pronto' and cs.autor = v_dono)
     or (select l ->> 'estado' from jsonb_array_elements(v_pp.linhas) l where l ->> 'interessado_id' = v_int::text) is distinct from 'pronto'
     or (select l ->> 'n' from jsonb_array_elements(v_pp.linhas) l where l ->> 'interessado_id' = v_int::text) is distinct from '1'
     or (pg_temp.f4k_fila('painel:' || v_painel)).estado is distinct from 'feito'
     or v_r ->> 'aviso' not like '%o 1: painel aprovado; sai às 17:45%' then
    raise exception '11c: o *sim* com *1 sabe 1* (%)', v_r;
  end if;
  -- 7b: o painel de outro dia não executa
  v_r := public.parceiro_painel_montar(v_p, '2027-01-11', c_t - interval '1 day');
  v_painel2 := (v_r ->> 'painel_id')::uuid;
  v_cartao := pg_temp.f4k_cartao(array[(pg_temp.f4k_fila('painel:' || v_painel2)).id], c_t + interval '35 minutes');
  v_r := pg_temp.f4k_sim(v_cartao, c_t + interval '36 minutes');
  if (select pp.estado from public.parceiro_paineis pp where pp.id = v_painel2) is distinct from 'aguardando'
     or (pg_temp.f4k_item(v_cartao, 1)).caiu_motivo is distinct from 'fato_mudou' then
    raise exception '7b: o painel de outro dia executou (%)', v_r;
  end if;

  -- ── 12 (patio) e 2. O *pátio* pelo cartão: até 21:59; sem letra; o *sim* agenda a resposta; *segura pátio* ──
  update public.retorno_config set parceiro_tipos_ligados = '{}' where id;
  v_m := pg_temp.f4k_msg('5547900016601', 'pátio', c_t + interval '40 minutes');
  v_r := public.parceiro_patio_pedido(v_n1, v_m, c_t + interval '40 minutes');
  v_f := pg_temp.f4k_fila('patio:' || v_n1 || ':2027-01-12');
  if v_r ->> 'acao' is distinct from 'cartao' or v_f.prioridade is distinct from 2::smallint or v_f.referencia is distinct from v_n1
     or v_f.valido_ate is distinct from timestamptz '2027-01-12 21:59-03' then
    raise exception '12c: o pátio não entrou na fila (%)', v_r;
  end if;
  if not exists (select 1 from public._parceiro_cartao_candidatos('2027-01-12 21:00-03', null) x where x.fila_id = v_f.id)
     or exists (select 1 from public._parceiro_cartao_candidatos('2027-01-12 22:00-03', null) x where x.fila_id = v_f.id) then
    raise exception '12d: o pátio vencido às 22:00 virou item';
  end if;
  v_cartao := pg_temp.f4k_cartao(array[v_f.id], c_t + interval '41 minutes');
  v_i := pg_temp.f4k_item(v_cartao, 1);
  if v_i.texto_mostrado not like '1. RCF (Carla) pediu o pátio às 10:40. Respondo assim: %' or pg_temp.f4k_letras(v_cartao, 1) is distinct from '' then
    raise exception '2e: o item pátio está torto (%)', v_i.texto_mostrado;
  end if;
  v_r := pg_temp.f4k_sim(v_cartao, c_t + interval '42 minutes');
  if not exists (select 1 from public.retorno_saidas s
                  where s.dedupe_key = 'parceiro:patio:' || v_m || ':sombra' and s.tipo = 'parceiro_patio' and s.estado = 'agendada'
                    and jsonb_array_length(s.dados -> 'interessado_ids') = jsonb_array_length(s.dados -> 'os_ids')) then
    raise exception '12e: o *sim* no pátio não agendou a resposta (%)', v_r;
  end if;
  -- *segura pátio* e *solta pátio* pelo retorno_dito gerado
  v_r := public.retorno_dito('{"comando": "segura", "alvo": "patio"}', v_dono, c_t + interval '43 minutes');
  if (select c.segura_patio from public.retorno_config c where c.id) is not true or v_r ->> 'texto' not like 'Segurei o pátio%' then
    raise exception '2f: *segura pátio* (%)', v_r;
  end if;
  v_r := public.retorno_dito('{"comando": "solta", "alvo": "pátio"}', v_dono, c_t + interval '44 minutes');
  if (select c.segura_patio from public.retorno_config c where c.id) is not false or v_r ->> 'texto' not like 'Pátio solto%' then
    raise exception '2g: *solta pátio* (%)', v_r;
  end if;
  if public.retorno_dito('{"comando": "segura", "alvo": "patio"}', gen_random_uuid(), c_t) ->> 'motivo' is distinct from 'nao_e_o_dono' then
    raise exception '2h: *segura pátio* de outro autor';
  end if;

  -- ── 15, 12 (pergunta), 6 e 20. A pergunta: 4 letras e "e mais 2", nunca "não está", a letra que confirma ou cria; sem
  --    candidata; *resolvido* ──
  update public.parceiros set ativo = false where id = v_p;
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Pergunta F4', 'RPQ', 'revenda_e_patio') returning id into v_q;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_q, 'Rosa', 'comercial') returning id into v_rosa;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel)
    values (v_rosa, '5547900016603', '00016603', '47', 'confirmado', c_t - interval '30 days', true) returning id into v_n3;
  perform pg_temp.f4k_isolar(v_q);
  perform pg_temp.f4k_so_fila('{}');
  for i in 1 .. 6 loop
    v_c := pg_temp.f4k_cliente('Cliente' || i || ' Pergunta', '554790001674' || i);
    perform pg_temp.f4k_os(v_c, 'OS-9884' || i);
  end loop;
  v_m := pg_temp.f4k_msg('5547900016603', 'como tá a bateria do joão?', c_t + interval '50 minutes');
  v_r := public.retorno_abrir(v_m, false, c_t + interval '50 minutes 5 seconds');
  v_caso := (v_r ->> 'abertura_id')::uuid;
  v_f := pg_temp.f4k_fila('pergunta:' || v_caso);
  if v_f.id is null or v_f.tipo is distinct from 'pergunta' or v_f.prioridade is distinct from 3::smallint or v_f.referencia is distinct from v_caso
     or v_f.valido_ate is not null or v_f.parceiro_id is distinct from v_q then
    raise exception '12f: a pergunta não entrou na fila pela triagem (%)', v_r;
  end if;
  v_r := public.parceiro_cartao_abrir('puxar', c_t + interval '55 minutes');
  v_cartao := (v_r ->> 'cartao_id')::uuid;
  v_i := pg_temp.f4k_item(v_cartao, 1);
  if v_i.tipo is distinct from 'pergunta' or pg_temp.f4k_letras(v_cartao, 1) is distinct from 'ABCD'
     or v_i.texto_mostrado not like '1. RPQ (Rosa) · ter 10:50 · ''como tá a bateria do joão?'' · Ligar alguma OS à RPQ (só andamento, sem valores)? *1 A* OS-98846 Ducato · *1 B* OS-98845 Ducato · *1 C* OS-98844 Ducato · *1 D* OS-98843 Ducato · e mais 2: *parceiro 74* · *resolvido 1*'
     or v_i.texto_mostrado like '%não está%' or v_i.texto_mostrado like '%ligadas%'
     or v_i.texto_mostrado like '%OS-98842%' or v_i.texto_mostrado like '%OS-98841%' then
    raise exception '15a: a pergunta está torta (%)', v_i.texto_mostrado;
  end if;
  -- 6: nem o trecho do parceiro nem a OS vão a ai_operator_messages
  if exists (select 1 from public.ai_operator_messages m
              where m.session_id = (select c.sessao_id from public.parceiro_cartoes c where c.id = v_cartao)
                and (m.content like '%bateria%' or m.content like '%OS-988%')) then
    raise exception '6b: o trecho foi a ai_operator_messages';
  end if;
  v_int := (select (o ->> 'interessado_id')::uuid from jsonb_array_elements(v_i.opcoes) o where o ->> 'letra' = 'A');
  perform pg_temp.f4k_dito('{"comando": "escolher", "n": 1, "letra": "a"}', c_t + interval '56 minutes');
  v_r := pg_temp.f4k_sim(v_cartao, c_t + interval '57 minutes');
  select * into v_oi from public.os_interessados oi where oi.id = v_int;
  if v_oi.situacao is distinct from 'confirmado' or v_oi.papel is distinct from 'indicou'
     or (select count(*) from public.os_interessados oi where oi.service_order_id = v_oi.service_order_id and oi.parceiro_id = v_q) is distinct from 1::bigint
     or (pg_temp.f4k_fila('pergunta:' || v_caso)).estado is distinct from 'feito' then
    raise exception '15b: a letra sobre o proposto não confirmou só aquela linha (%)', v_r;
  end if;
  perform public._parceiro_fila_conferir(c_t + interval '58 minutes');
  if (pg_temp.f4k_fila('vinculo:' || v_int)).estado is distinct from 'caiu' then
    raise exception '15c: o vínculo confirmado pela letra não caiu da fila';
  end if;
  -- a letra sobre o par sem linha cria e confirma como indicou; o confirmado não vira letra; sem letra nada muda
  v_c := pg_temp.f4k_cliente('Cliente7 Pergunta', '5547900016747');
  v_os := pg_temp.f4k_os(v_c, 'OS-98847');
  v_m := pg_temp.f4k_msg('5547900016603', 'e o motorhome da ana, alguma novidade?', c_t + interval '1 hour');
  update public.retorno_aberturas set estado = 'fechada', fechada_em = c_t + interval '59 minutes', fechada_motivo = 'dono' where id = v_caso;
  v_r := public.retorno_abrir(v_m, false, c_t + interval '1 hour 5 seconds');
  v_caso2 := (v_r ->> 'abertura_id')::uuid;
  perform pg_temp.f4k_so_fila(array[(pg_temp.f4k_fila('pergunta:' || v_caso2)).id]);
  v_cartao := pg_temp.f4k_cartao(array[(pg_temp.f4k_fila('pergunta:' || v_caso2)).id], c_t + interval '1 hour 1 minute');
  v_i := pg_temp.f4k_item(v_cartao, 1);
  if v_i.texto_mostrado not like '%*1 A* OS-98847 Ducato%' or v_i.texto_mostrado like '%OS-98846%'
     or (select o ->> 'interessado_id' from jsonb_array_elements(v_i.opcoes) o where o ->> 'letra' = 'A') is not null then
    raise exception '15d: o par sem linha ou o confirmado nas letras (%)', v_i.texto_mostrado;
  end if;
  v_k := (select count(*) from public.os_interessados oi where oi.parceiro_id = v_q);
  v_r := pg_temp.f4k_sim(v_cartao, c_t + interval '1 hour 2 minutes');
  if (select count(*) from public.os_interessados oi where oi.parceiro_id = v_q) is distinct from v_k
     or (pg_temp.f4k_fila('pergunta:' || v_caso2)).estado is distinct from 'espera' then
    raise exception '15e: *sim* sem letra mudou a pergunta (%)', v_r;
  end if;
  v_cartao := pg_temp.f4k_cartao(array[(pg_temp.f4k_fila('pergunta:' || v_caso2)).id], c_t + interval '1 hour 3 minutes');
  perform pg_temp.f4k_dito('{"comando": "escolher", "n": 1, "letra": "A"}', c_t + interval '1 hour 3 minutes');
  v_r := pg_temp.f4k_sim(v_cartao, c_t + interval '1 hour 4 minutes');
  select * into v_oi from public.os_interessados oi where oi.service_order_id = v_os and oi.parceiro_id = v_q;
  if v_oi.situacao is distinct from 'confirmado' or v_oi.papel is distinct from 'indicou' or v_oi.origem is distinct from 'dono' then
    raise exception '15f: a letra sobre o par sem linha não criou e confirmou (%)', v_r;
  end if;
  -- 20: *resolvido 1* na pergunta: fecha como dono, cancela o P02 e o P15, item caiu, fila feito, sem retorno_toques
  update public.retorno_aberturas set estado = 'fechada', fechada_em = c_t + interval '1 hour 5 minutes', fechada_motivo = 'dono' where id = v_caso2;
  v_m := pg_temp.f4k_msg('5547900016603', 'ainda sem notícia do carro do pedro?', c_t + interval '1 hour 10 minutes');
  v_r := public.retorno_abrir(v_m, false, c_t + interval '1 hour 10 minutes 5 seconds');
  v_caso := (v_r ->> 'abertura_id')::uuid;
  perform public.parceiro_agendar('parceiro_recibo', 'orcamento', v_n3, v_caso, '{}'::jsonb, c_t + interval '2 hours',
                                  'parceiro:recibo:' || v_caso || ':orcamento', 'resposta_imediata');
  if (select count(*) from public.retorno_saidas s where s.abertura_id = v_caso and s.estado = 'agendada') is distinct from 2::bigint then
    raise exception '20a: faltam o P02 e o P15 agendados';
  end if;
  v_cartao := pg_temp.f4k_cartao(array[(pg_temp.f4k_fila('pergunta:' || v_caso)).id], c_t + interval '1 hour 11 minutes');
  v_toques := (select count(*) from public.retorno_toques);
  v_r := pg_temp.f4k_dito('{"comando": "resolvido", "n": 1}', c_t + interval '1 hour 12 minutes');
  v_i := pg_temp.f4k_item(v_cartao, 1);
  if (select a.estado || '/' || a.fechada_motivo from public.retorno_aberturas a where a.id = v_caso) is distinct from 'fechada/dono'
     or exists (select 1 from public.retorno_saidas s where s.abertura_id = v_caso and s.estado = 'agendada')
     or (select count(*) from public.retorno_saidas s where s.abertura_id = v_caso and s.estado = 'cancelada' and s.motivo = 'caso_fechado') is distinct from 2::bigint
     or v_i.estado is distinct from 'caiu' or v_i.caiu_motivo is distinct from 'caso_fechado' or v_i.decidido_em is null
     or (pg_temp.f4k_fila('pergunta:' || v_caso)).estado is distinct from 'feito'
     or (select count(*) from public.retorno_toques) is distinct from v_toques
     or v_r ->> 'texto' not like 'RPQ (Rosa): resolvido, saiu da lista%' then
    raise exception '20b: *resolvido 1* na pergunta (%)', v_r;
  end if;
  -- sem candidata: só *resolvido*; *resolvido* em item sem caso não muda nada
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Sem OS F4', 'RSO', 'revenda') returning id into v_s;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_s, 'Sol', 'comercial') returning id into v_sol;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel)
    values (v_sol, '5547900016604', '00016604', '47', 'confirmado', c_t - interval '30 days', true) returning id into v_n4;
  perform pg_temp.f4k_isolar(v_s);
  v_m := pg_temp.f4k_msg('5547900016604', 'tem algum carro nosso aí?', c_t + interval '1 hour 20 minutes');
  v_caso := (public.retorno_abrir(v_m, false, c_t + interval '1 hour 20 minutes 5 seconds') ->> 'abertura_id')::uuid;
  select f.id into v_f.id from public.parceiro_fila f where f.parceiro_id = v_q and f.tipo = 'vinculo' and f.estado = 'espera' limit 1;
  v_cartao := pg_temp.f4k_cartao(array[(pg_temp.f4k_fila('pergunta:' || v_caso)).id, v_f.id], c_t + interval '1 hour 21 minutes');
  if (pg_temp.f4k_item(v_cartao, 1)).texto_mostrado not like '1. RSO (Sol) · ter 11:20 · ''tem algum carro nosso aí?'' · *resolvido 1*'
     or pg_temp.f4k_letras(v_cartao, 1) is distinct from '' then
    raise exception '15g: a pergunta sem candidata (%)', (pg_temp.f4k_item(v_cartao, 1)).texto_mostrado;
  end if;
  v_r := pg_temp.f4k_dito('{"comando": "resolvido", "n": 2}', c_t + interval '1 hour 22 minutes');
  if v_r ->> 'texto' is distinct from 'Esse item não tem conversa para resolver: use a letra ou *não N*.'
     or (pg_temp.f4k_item(v_cartao, 2)).estado is distinct from 'vivo' then
    raise exception '20c: *resolvido* no vínculo (%)', v_r;
  end if;
  perform public._parceiro_cartao_encerrar(v_cartao, 'decidido', 'rejected', null, c_t + interval '1 hour 23 minutes');
  update public.parceiros set ativo = false where id in (v_q, v_s);
  update public.parceiros set ativo = true where id = v_p;

  -- ── 10, 21 e 12 (retido, aviso). Uma letra por caminho; *sim <PIN>* sem letra não muda nada ──
  perform pg_temp.f4k_so_fila('{}');
  update public.retorno_config set parceiro_modo = 'sombra' where id;
  v_c := pg_temp.f4k_cliente('Rita Retida', '5547900016751');
  v_os := pg_temp.f4k_os(v_c, 'OS-98851', 'Lancha');
  v_int := pg_temp.f4k_liga(v_os, v_p, 'indicou');
  update public.os_interessados set retido_em = c_t - interval '1 hour' where id = v_int;
  perform public._parceiro_fila_por('retido', v_p, v_int, 'retido:' || v_int, null, jsonb_build_object('service_order_id', v_os));
  v_c := pg_temp.f4k_cliente('Ivo Aviso', null);                                -- sem telefone: o confirmar põe o aviso na fila
  v_os2 := pg_temp.f4k_os(v_c, 'OS-98852', 'Lancha');
  v_r := public.parceiro_propor(jsonb_build_array(jsonb_build_object('service_order_id', v_os2, 'parceiro_id', v_p,
                                                                     'origem', 'numero_do_pedido', 'papel', 'indicou')), v_dono);
  v_int2 := (v_r -> 'propostos' -> 0 ->> 'interessado_id')::uuid;
  v_r := public._parceiro_confirmar(v_int2, v_dono, null, c_t);
  v_f := pg_temp.f4k_fila('aviso:' || v_int2);
  if v_r ->> 'aviso' is distinct from 'pendente' or v_f.prioridade is distinct from 6::smallint or v_f.referencia is distinct from v_int2 then
    raise exception '12g: o aviso não entrou na fila pelo confirmar (%)', v_r;
  end if;
  v_c := pg_temp.f4k_cliente('Edu Reenvio', '5547900016753');                   -- registrado pela revenda, saída recusada
  v_os3 := pg_temp.f4k_os(v_c, 'OS-98853', 'Lancha');
  v_int3 := pg_temp.f4k_liga(v_os3, v_p, 'indicou', c_t - interval '3 days', 'pela_revenda');
  v_saida := public.parceiro_agendar('parceiro_aviso_cliente', null, null, null,
               jsonb_build_object('client_id', v_c, 'parceiro_id', v_p, 'interessado_ids', jsonb_build_array(v_int3), 'papel', 'indicou'),
               c_t - interval '1 day', 'parceiro:aviso:' || v_c || ':' || v_p, 'aviso', '5547900016753');
  update public.retorno_saidas set estado = 'recusada', motivo = 'texto', decidida_em = c_t - interval '1 day' where id = v_saida;
  perform public._parceiro_fila_por('aviso', v_p, v_int3, 'aviso:' || v_int3 || ':' || v_saida, null,
                                    jsonb_build_object('saida_id', v_saida, 'service_order_id', v_os3, 'estado', 'recusada'));
  v_ids := array[(pg_temp.f4k_fila('retido:' || v_int)).id, (pg_temp.f4k_fila('aviso:' || v_int2)).id,
                 (pg_temp.f4k_fila('aviso:' || v_int3 || ':' || v_saida)).id];
  v_cartao := pg_temp.f4k_cartao(v_ids, c_t + interval '2 hours');
  if pg_temp.f4k_letras(v_cartao, 1) is distinct from 'AV' or pg_temp.f4k_letras(v_cartao, 2) is distinct from 'AB'
     or pg_temp.f4k_letras(v_cartao, 3) is distinct from 'C'
     or (pg_temp.f4k_item(v_cartao, 3)).texto_mostrado not like '3. % (OS-98853) ganhou telefone, e a mensagem de aviso da RCF não saiu. *3 C* mandar de novo' then
    raise exception '10a: letras de retido e aviso (% % %)', pg_temp.f4k_letras(v_cartao, 1), pg_temp.f4k_letras(v_cartao, 2),
                    pg_temp.f4k_letras(v_cartao, 3);
  end if;
  -- 21: no registrado, A e B não existem
  if pg_temp.f4k_dito('{"comando": "escolher", "n": 3, "letra": "A"}', c_t + interval '2 hours 1 minute') ->> 'texto' not like 'O 3 não tem a letra A.%'
     or pg_temp.f4k_dito('{"comando": "escolher", "n": 3, "letra": "B"}', c_t + interval '2 hours 1 minute') ->> 'texto' not like 'O 3 não tem a letra B.%' then
    raise exception '21a: A ou B no aviso registrado';
  end if;
  perform pg_temp.f4k_dito('{"comando": "escolher", "n": 3, "letra": "C"}', c_t + interval '2 hours 1 minute');
  v_r := pg_temp.f4k_sim(v_cartao, c_t + interval '2 hours 2 minutes');
  if (select oi.retido_em from public.os_interessados oi where oi.id = v_int) is null
     or (select oi.aviso_ao_cliente from public.os_interessados oi where oi.id = v_int2) is distinct from 'nao_avisado'
     or (pg_temp.f4k_fila('retido:' || v_int)).estado is distinct from 'espera'
     or (pg_temp.f4k_fila('aviso:' || v_int2)).estado is distinct from 'espera' then
    raise exception '10b: *sim* sem letra mudou retido ou aviso (%)', v_r;
  end if;
  if not exists (select 1 from public.retorno_saidas s
                  where s.tipo = 'parceiro_aviso_cliente' and s.dedupe_key like 'parceiro:aviso:' || v_c || ':' || v_p || ':r1%')
     or (pg_temp.f4k_item(v_cartao, 3)).estado is distinct from 'feito' then
    raise exception '21b: a letra C não reenviou (%)', v_r;
  end if;
  -- A no retido limpa retido_em; A no aviso registra pessoalmente
  v_cartao := pg_temp.f4k_cartao(array[(pg_temp.f4k_fila('retido:' || v_int)).id, (pg_temp.f4k_fila('aviso:' || v_int2)).id],
                                 c_t + interval '2 hours 3 minutes');
  perform pg_temp.f4k_dito('{"comando": "escolher", "n": 1, "letra": "A"}', c_t + interval '2 hours 3 minutes');
  perform pg_temp.f4k_dito('{"comando": "escolher", "n": 2, "letra": "A"}', c_t + interval '2 hours 3 minutes');
  v_r := pg_temp.f4k_sim(v_cartao, c_t + interval '2 hours 4 minutes');
  if (select oi.retido_em from public.os_interessados oi where oi.id = v_int) is not null
     or (select oi.aviso_ao_cliente from public.os_interessados oi where oi.id = v_int2) is distinct from 'pessoalmente' then
    raise exception '10c: A no retido ou no aviso (%)', v_r;
  end if;
  -- V no retido: o veto do dono
  update public.os_interessados set retido_em = c_t + interval '2 hours' where id = v_int;
  perform public._parceiro_fila_por('retido', v_p, v_int, 'retido:' || v_int, null, '{}'::jsonb);
  update public.parceiro_fila set estado = 'espera' where chave = 'retido:' || v_int;
  v_cartao := pg_temp.f4k_cartao(array[(pg_temp.f4k_fila('retido:' || v_int)).id], c_t + interval '2 hours 5 minutes');
  perform pg_temp.f4k_dito('{"comando": "escolher", "n": 1, "letra": "V"}', c_t + interval '2 hours 5 minutes');
  v_r := pg_temp.f4k_sim(v_cartao, c_t + interval '2 hours 6 minutes');
  if not exists (select 1 from public.parceiro_vetos v where v.client_id = (select oi.client_id from public.os_interessados oi where oi.id = v_int)
                                                        and v.parceiro_id = v_p and v.origem = 'dono') then
    raise exception '10d: V no retido não vetou (%)', v_r;
  end if;

  -- ── 12 (pdf_mao, repassar) e 19. O PDF à mão (A, B, C) e o repassar pelo *sim*, em sombra ──
  v_c := pg_temp.f4k_cliente('Gil Mao', '5547900016761');
  v_os := pg_temp.f4k_os(v_c, 'OS-98861', 'Lancha');
  perform pg_temp.f4k_liga(v_os, v_p, 'indicou');
  v_m := pg_temp.f4k_msg('5547900016601', 'documento de teste', c_t - interval '1 day');
  insert into public.parceiro_envios_a_mao (whatsapp_message_id, parceiro_id, service_order_id, numero_doc, enviado_em, situacao)
    values (v_m, v_p, v_os, 'OS-98861', c_t - interval '1 day', 'perguntada') returning id into v_envio;
  perform public._parceiro_fila_por('pdf_mao', v_p, v_envio, 'pdf_mao:' || v_envio, null, jsonb_build_object('service_order_id', v_os));
  v_c := pg_temp.f4k_cliente('Fabi Repassa', null);
  v_os2 := pg_temp.f4k_os(v_c, 'OS-98862', 'Lancha', 'completed');
  perform pg_temp.f4k_concluir(v_os2, c_t - interval '5 hours');
  v_int2 := pg_temp.f4k_liga(v_os2, v_p, 'indicou', c_t - interval '3 days', 'pela_revenda');
  perform public.parceiro_repassar_rodada(c_t);
  v_f := pg_temp.f4k_fila('repassar:' || v_os2 || ':' || v_p);
  if v_f.prioridade is distinct from 7::smallint or v_f.referencia is distinct from v_os2 or v_f.dados ->> 'interessado_id' is distinct from v_int2::text
     or v_f.valido_ate is null or (pg_temp.f4k_fila('pdf_mao:' || v_envio)).prioridade is distinct from 5::smallint then
    raise exception '12h: o repassar ou o pdf_mao na fila (%)', to_jsonb(v_f);
  end if;
  v_cartao := pg_temp.f4k_cartao(array[(pg_temp.f4k_fila('pdf_mao:' || v_envio)).id, v_f.id], c_t + interval '3 hours');
  if pg_temp.f4k_letras(v_cartao, 1) is distinct from 'ABC' or pg_temp.f4k_letras(v_cartao, 2) is distinct from ''
     or (pg_temp.f4k_item(v_cartao, 1)).texto_mostrado not like '1. Você mandou o OS-98861 à RCF à mão em 11/01. *1 A* ela contrata%'
     or (pg_temp.f4k_item(v_cartao, 2)).texto_mostrado not like '2. % (OS-98862) não tem WhatsApp. Peço à RCF para repassar? "%' then
    raise exception '2i: pdf_mao ou repassar (%)', (pg_temp.f4k_item(v_cartao, 2)).texto_mostrado;
  end if;
  perform pg_temp.f4k_dito('{"comando": "escolher", "n": 1, "letra": "C"}', c_t + interval '3 hours 1 minute');
  v_r := pg_temp.f4k_sim(v_cartao, c_t + interval '3 hours 2 minutes');
  if (select e.situacao from public.parceiro_envios_a_mao e where e.id = v_envio) is distinct from 'decidida'
     or not exists (select 1 from public.retorno_saidas s
                     where s.dedupe_key = 'parceiro:repassar:' || v_os2 || ':pronto:sombra' and s.estado = 'agendada' and s.modo = 'sombra')
     or exists (select 1 from public.retorno_saidas s where s.dedupe_key = 'parceiro:repassar:' || v_os2 || ':pronto') then
    raise exception '19a: o repassar pelo *sim* em sombra ou a letra C do PDF (%)', v_r;
  end if;

  -- ── 9. *parceiro 74*: em qualquer modo; sem vínculo, item vinculo com origem dono; com vínculo, corte; dois parceiros sem
  --    sigla pedem a sigla ──
  update public.retorno_config set parceiro_modo = 'desligado' where id;
  perform pg_temp.f4k_so_fila('{}');
  v_c := pg_temp.f4k_cliente('Caio Corte', '5547900016771');
  v_os := pg_temp.f4k_os(v_c, 'OS-98874', 'Lancha');
  if public.parceiro_cartao_abrir_os(null, '99999999', v_dono, c_t) ->> 'texto' is distinct from 'Não achei essa OS.' then
    raise exception '9a: número inexistente';
  end if;
  update public.parceiros set ativo = true where id = v_q;
  v_r := public.parceiro_cartao_abrir_os(null, '98874', v_dono, c_t + interval '4 hours');
  if v_r ->> 'acao' is distinct from 'vazio' or v_r ->> 'texto' not like 'Qual parceiro? *parceiro % 98874*' then
    raise exception '9b: dois parceiros sem sigla (%)', v_r;
  end if;
  update public.parceiros set ativo = false where id = v_q;
  if public.parceiro_cartao_abrir_os('rcf', 'OS-98874', gen_random_uuid(), c_t) ->> 'motivo' is distinct from 'nao_e_o_dono' then
    raise exception '9c: outro autor abriu';
  end if;
  v_r := public.parceiro_cartao_abrir_os('rcf', 'os-98874', v_dono, c_t + interval '4 hours');
  v_cartao := (v_r ->> 'cartao_id')::uuid;
  v_i := pg_temp.f4k_item(v_cartao, 1);
  select * into v_oi from public.os_interessados oi where oi.service_order_id = v_os and oi.parceiro_id = v_p;
  if v_r ->> 'acao' is distinct from 'cartao' or v_i.tipo is distinct from 'vinculo' or v_oi.origem is distinct from 'dono'
     or v_oi.situacao is distinct from 'proposto' or pg_temp.f4k_letras(v_cartao, 1) is distinct from 'CPR' or v_i.selecionado is not false then
    raise exception '9d: *parceiro 74* sem vínculo (% %)', v_r, pg_temp.f4k_letras(v_cartao, 1);
  end if;
  perform pg_temp.f4k_dito('{"comando": "escolher", "n": 1, "letra": "C"}', c_t + interval '4 hours 1 minute');
  v_r := pg_temp.f4k_sim(v_cartao, c_t + interval '4 hours 2 minutes');
  if (select oi.situacao || '/' || oi.papel from public.os_interessados oi where oi.id = v_oi.id) is distinct from 'confirmado/indicou' then
    raise exception '9e: C no *parceiro 74* (%)', v_r;
  end if;
  v_r := public.parceiro_cartao_abrir_os('RCF', '98874', v_dono, c_t + interval '4 hours 3 minutes');
  v_cartao := (v_r ->> 'cartao_id')::uuid;
  if (pg_temp.f4k_item(v_cartao, 1)).tipo is distinct from 'corte' or pg_temp.f4k_letras(v_cartao, 1) is distinct from 'ARV'
     or (pg_temp.f4k_item(v_cartao, 1)).texto_mostrado not like '1. OS-98874 · Ducato · ligada à RCF (ela indicou) · *1 A* pausa%' then
    raise exception '9f: o corte (%)', v_r;
  end if;
  perform pg_temp.f4k_dito('{"comando": "escolher", "n": 1, "letra": "A"}', c_t + interval '4 hours 4 minutes');
  perform pg_temp.f4k_sim(v_cartao, c_t + interval '4 hours 5 minutes');
  v_r := public.parceiro_cartao_abrir_os('RCF', 'OS-98874', v_dono, c_t + interval '4 hours 6 minutes');
  v_cartao := (v_r ->> 'cartao_id')::uuid;
  if (select oi.situacao from public.os_interessados oi where oi.id = v_oi.id) is distinct from 'pausado'
     or pg_temp.f4k_letras(v_cartao, 1) is distinct from 'TRV' then
    raise exception '9g: a pausa e o T do corte (%)', v_r;
  end if;
  perform pg_temp.f4k_dito('{"comando": "escolher", "n": 1, "letra": "T"}', c_t + interval '4 hours 7 minutes');
  perform pg_temp.f4k_sim(v_cartao, c_t + interval '4 hours 8 minutes');
  if (select oi.situacao from public.os_interessados oi where oi.id = v_oi.id) is distinct from 'confirmado' then
    raise exception '9h: T não retomou';
  end if;

  -- ── 18. O cartão vencido (expirou, pendência expired, ponteiro fora, fila a espera), em desligado; a pendência rejeitada
  --    por fora; o vivo sem item (caiu) ──
  v_c := pg_temp.f4k_cliente('Dani Vence', '5547900016781');
  v_os := pg_temp.f4k_os(v_c, 'OS-98881', 'Lancha');
  v_cartao := (public.parceiro_cartao_abrir_os('RCF', 'OS-98881', v_dono, c_t + interval '5 hours') ->> 'cartao_id')::uuid;
  select c.pendencia_id, c.sessao_id into v_pend, v_ses from public.parceiro_cartoes c where c.id = v_cartao;
  v_f := pg_temp.f4k_fila('vinculo:' || (pg_temp.f4k_item(v_cartao, 1)).interessado_id);
  if (select s.metadata ->> 'pending_confirm_action_id' from public.ai_operator_sessions s where s.id = v_ses) is distinct from v_pend::text
     or v_f.estado is distinct from 'no_cartao' then
    raise exception '18a: o cartão não ficou vivo com o ponteiro';
  end if;
  v_r := public.parceiro_vigia_cartao(c_t + interval '29 hours');
  if (select c.estado || '/' || c.caiu_motivo from public.parceiro_cartoes c where c.id = v_cartao) is distinct from 'expirou/cartao_expirou'
     or (select p.status from public.ai_operator_pending_actions p where p.id = v_pend) is distinct from 'expired'
     or (select s.metadata ? 'pending_confirm_action_id' from public.ai_operator_sessions s where s.id = v_ses) is not false
     or (pg_temp.f4k_fila('vinculo:' || (pg_temp.f4k_item(v_cartao, 1)).interessado_id)).estado is distinct from 'espera'
     or coalesce((public.pergunta_ocupado(v_phone) ->> 'ocupado')::boolean, true) is not false then
    raise exception '18b: o vencido (%)', v_r;
  end if;
  v_cartao := (public.parceiro_cartao_abrir_os('RCF', 'OS-98881', v_dono, c_t + interval '30 hours') ->> 'cartao_id')::uuid;
  update public.ai_operator_pending_actions set status = 'rejected'
   where id = (select c.pendencia_id from public.parceiro_cartoes c where c.id = v_cartao);
  if public.parceiro_cartao_vivo(c_t + interval '30 hours 1 minute') is not null
     or (select c.estado || '/' || c.decidido_por from public.parceiro_cartoes c where c.id = v_cartao) is distinct from 'decidido/nao' then
    raise exception '18c: a pendência rejeitada por fora não fechou o cartão';
  end if;
  v_cartao := (public.parceiro_cartao_abrir_os('RCF', 'OS-98881', v_dono, c_t + interval '31 hours') ->> 'cartao_id')::uuid;
  update public.parceiro_cartao_itens set estado = 'fora' where cartao_id = v_cartao;
  perform public.parceiro_vigia_cartao(c_t + interval '31 hours 1 minute');
  if (select c.estado || '/' || c.caiu_motivo from public.parceiro_cartoes c where c.id = v_cartao) is distinct from 'caiu/cartao_caiu' then
    raise exception '18d: o cartão sem item vivo não caiu';
  end if;

  -- ── 1c. Ocupado: com o cartão da F2 vivo ou uma pergunta aberta, nenhuma pendência nasce ──
  update public.retorno_config set parceiro_modo = 'sombra' where id;
  v_k := (select count(*) from public.ai_operator_pending_actions p where p.action_name = 'parceiro_executar_cartao');
  insert into public.retorno_cartoes (gatilho, dia, estado, hash, texto, criado_em, expira_em)
    values ('puxar', '2027-01-13', 'vivo', '', 'cartão F2 de teste', c_t + interval '32 hours', c_t + interval '56 hours') returning id into v_cartao2;
  v_r := public.parceiro_cartao_abrir('puxar', c_t + interval '32 hours 1 minute');
  if v_r ->> 'acao' is distinct from 'ocupado' or v_r ->> 'texto' is distinct from 'Tem um pedido aberto antes deste: responda a ele e mande *parceiro* de novo.'
     or (select count(*) from public.ai_operator_pending_actions p where p.action_name = 'parceiro_executar_cartao') is distinct from v_k then
    raise exception '1c: com o cartão da F2 vivo (%)', v_r;
  end if;
  delete from public.retorno_cartoes where id = v_cartao2;
  select s.id into v_ses from public.ai_operator_sessions s where s.external_thread_key = v_phone and s.status = 'open'
   order by s.last_activity_at desc limit 1;
  insert into public.ai_operator_pending_actions (session_id, action_name, risk_level, title, summary, payload, status, expires_at)
    values (v_ses, 'outra_acao', 'high', 'Outra coisa', 'Outra coisa', '{}', 'pending', c_t + interval '10 days') returning id into v_pend;
  v_r := public.parceiro_cartao_abrir('puxar', c_t + interval '32 hours 2 minutes');
  if v_r ->> 'acao' is distinct from 'ocupado'
     or (select count(*) from public.ai_operator_pending_actions p where p.action_name = 'parceiro_executar_cartao') is distinct from v_k then
    raise exception '1d: com a pergunta aberta (%)', v_r;
  end if;
  update public.ai_operator_pending_actions set status = 'expired' where id = v_pend;

  -- ── Respostas de 09/11, R1 (F4-07): com parceiro_etapa_ligada, o *ver N* do painel mostra ao dono a linha com a etapa que
  --    vai à parceira, e o pátio pelo cartão a leva; desligada, a linha é a de antes. OS-98891; telefones 55479000176(51, 61) ──
  update public.retorno_config set parceiro_modo = 'sombra', parceiro_tipos_ligados = '{}', patio_nivel = 'cartao', segura_patio = false
   where id;
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Etapa Cartao F4', 'REC', 'revenda') returning id into v_pt;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_pt, 'Eunice', 'comercial') returning id into v_c;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel)
    values (v_c, '5547900017651', '00017651', '47', 'confirmado', c_t - interval '30 days', true) returning id into v_nt;
  perform pg_temp.f4k_isolar(v_pt);
  v_c := pg_temp.f4k_cliente('Davi Etapa', '5547900017661');
  insert into public.vessels (client_id, name, asset_type) values (v_c, 'Unidade OS-98891', 'Motorhome') returning id into v_ves;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total, check_in_at)
    values ('OS-98891', v_c, v_ves, 'in_progress', 'approved', 'repair', '2026-10-01 10:00-03', '2026-10-01 10:00-03', 0,
            c_t - interval '2 hours')
    returning id into v_ot;
  perform pg_temp.f4k_etapa(v_ot, 'Instalação do painel solar', date '2027-01-12');
  perform pg_temp.f4k_liga(v_ot, v_pt, 'indicou');
  update public.retorno_config set parceiro_etapa_ligada = true where id;
  v_linhas := public.parceiro_linhas(v_pt, c_t);
  if jsonb_array_length(v_linhas) is distinct from 1 or v_linhas -> 0 ->> 'etapa' is distinct from 'instalação do painel solar' then
    raise exception 'R1a: a linha da REC sem a etapa (%)', v_linhas;
  end if;
  insert into public.parceiro_paineis (parceiro_id, dia, estado, mudou, linhas, impressao, criado_em)
    values (v_pt, '2027-01-12', 'aguardando', true, v_linhas, public._parceiro_impressao(v_linhas), c_t) returning id into v_painel;
  v_fp := public._parceiro_fila_por('painel', v_pt, v_painel, 'painel:' || v_painel, '2027-01-12 18:30-03',
                                    jsonb_build_object('dia', '2027-01-12', 'painel_id', v_painel));
  v_fq := public._parceiro_fila_por('patio', v_pt, v_nt, 'patio:' || v_nt || ':2027-01-12', '2027-01-12 21:59-03',
                                    jsonb_build_object('pedido_em', c_t, 'dia', '2027-01-12'));
  v_item := public._parceiro_item_montar(v_fp, 1::smallint, c_t);
  if v_item -> 'retrato' -> 'ver' ->> 0 is distinct from '1. Motorhome de Davi E.: em serviço hoje (instalação do painel solar).' then
    raise exception 'R1b: o *ver* do painel sem a etapa (%)', v_item -> 'retrato';
  end if;
  v_item := public._parceiro_item_montar(v_fq, 2::smallint, c_t);
  if v_item -> 'retrato' -> 'linhas' -> 0 ->> 'etapa' is distinct from 'instalação do painel solar'
     or v_item -> 'retrato' -> 'ver' ->> 0 is distinct from E'Pátio HBR · 12/01\n1. Motorhome de Davi E.: em serviço hoje (instalação do painel solar).' then
    raise exception 'R1c: o pátio pelo cartão sem a etapa (%)', v_item -> 'retrato';
  end if;
  update public.retorno_config set parceiro_etapa_ligada = false where id;
  v_item := public._parceiro_item_montar(v_fp, 1::smallint, c_t);
  if v_item -> 'retrato' -> 'ver' ->> 0 is distinct from '1. Motorhome de Davi E.: em serviço hoje.' then
    raise exception 'R1d: com a chave desligada, o *ver* mostrou a etapa (%)', v_item -> 'retrato';
  end if;
  v_item := public._parceiro_item_montar(v_fq, 2::smallint, c_t);
  if v_item -> 'retrato' -> 'linhas' is distinct from jsonb_build_array(jsonb_build_object(
       'n', 1, 'interessado_id', v_linhas -> 0 -> 'interessado_id', 'service_order_id', v_ot, 'estado', 'em_servico', 'desde', null))
     or v_item -> 'retrato' -> 'ver' ->> 0 is distinct from E'Pátio HBR · 12/01\n1. Motorhome de Davi E.: em serviço hoje.' then
    raise exception 'R1e: com a chave desligada, o pátio pelo cartão mudou (%)', v_item -> 'retrato';
  end if;
  update public.parceiro_fila set estado = 'feito', decidido_em = now() where id in (v_fp, v_fq);

  -- ── A varredura: as tabelas fechadas a anon, as funções do parceiro fechadas a anon e authenticated ──
  if has_table_privilege('anon', 'public.parceiro_cartoes', 'select') or has_table_privilege('anon', 'public.parceiro_cartao_itens', 'select')
     or has_table_privilege('authenticated', 'public.parceiro_cartoes', 'insert')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.parceiro_cartoes'::regclass)
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.parceiro_cartao_itens'::regclass) then
    raise exception 'grants: tabelas do cartão abertas';
  end if;
  for v_rec in
    select p.oid, p.proname, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname ~ '^_?parceiro_'
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
  if to_regprocedure('public.parceiro_cartao_abrir(text, timestamptz)') is null
     or to_regprocedure('public.parceiro_cartao_executar(uuid, uuid, timestamptz)') is null
     or to_regprocedure('public.parceiro_vigia_cartao(timestamptz)') is null
     or has_function_privilege('anon', 'public.retorno_dito(jsonb, uuid, timestamptz)', 'execute') then
    raise exception 'grants: a varredura não achou as funções da P8 (%)', v_n_fun;
  end if;

  raise exception 'retorno_f4_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f4_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f4_cartao', true, '{}');
end
$cartao$;

select arquivo, ok, numeros from _bancada order by em;
rollback;

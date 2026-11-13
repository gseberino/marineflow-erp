-- Retorno F5 (P13): orcamento_medidas e o cron retorno-orcamento. Cada "0" do portão com um caso que o quebra e um que não
-- quebra (sem_desfecho, lembrete_depois_de_parar, aceite_sem_msg, rejeitado_sem_motivo, aceite_ate_registro); o orçamento
-- vencido com acompanhamento parado e sem motivo em sem_desfecho e em parados_sem_desfecho; o mandado a outro número dentro e
-- o do parceiro fora; o lembrete enviado depois de uma mensagem do cliente com o estado gravado dizendo outra coisa; o aceite
-- duvida nunca decidido contra e o substituido fora; o áudio "pode fazer" de número de cliente com orçamento candidato, com
-- aceite_audio desligado, em aceites.pulados_audio (o nº 8c da P6.2 mora aqui, pela regra de ordem); os envios, os
-- acompanhamentos, os passos, os aceites, a precisão da sombra e as respostas do dono; o cron com o comando certo, nenhum
-- outro job mudado e o vigia com tudo desligado sem acompanhar nada; os grants. Roda só pela bancada (grupo 8, F5_ONDA=7,
-- F5_TESTES=retorno_f5_medidas). Termina em ROLLBACK; cada cenário roda no seu sub-bloco, que se desfaz sozinho
-- (raise 'f5m_cenario'). Só confere as próprias linhas sintéticas: toda contagem é a diferença entre a medida antes e depois
-- do caso, no período de fev/2027 (sem dado real). Telefones inventados 55479000099xx (a chave sai do telefone: 000099xx),
-- nomes inventados (Ana, João, Pedro), documentos inventados (ORÇ-997xx). Nenhuma mensagem real é lida; as mensagens são
-- inventadas. Relógio: o período [seg 01/02/2027, seg 01/03/2027) de Brasília, sem feriado; envio na ter 02/02 10:00 com
-- validade ter 09/02 (vencida há mais de 2 dias úteis em 01/03).
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f5m_cli(p_nome text, p_fone text, p_generico boolean default false) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp, generico) values ('individual', p_nome, p_fone, p_generico) returning id
$f$;

-- Uma mensagem inventada (recebida, por padrão), com a hora real igual à de gravação.
create or replace function pg_temp.f5m_msg(p_fone text, p_corpo text, p_em timestamptz, p_direcao text default 'inbound',
                                           p_tipo text default 'text') returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real,
                                        occurred_at)
  values (p_direcao, p_fone, p_tipo, p_corpo, case when p_direcao = 'inbound' then 'received' else 'sent' end,
          '{"data": {}}'::jsonb, p_em, p_em)
  returning id
$f$;

-- O orçamento em rascunho, criado 2 dias antes de p_em.
create or replace function pg_temp.f5m_orc(p_cliente uuid, p_numero text, p_em timestamptz) returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type)
    values (p_cliente, 'Unidade ' || left(md5(p_cliente::text || p_numero || clock_timestamp()::text), 6), 'Motorhome') returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total, quote_validity_days)
  values (p_numero, p_cliente, v_v, 'draft', 'draft', 'repair', p_em - interval '2 days', p_em - interval '2 days', 100, 7)
  returning id into v_id;
  return v_id;
end $f$;

-- O envio como o whatsapp-send o marca: sent, a hora, a via, a chave e a validade.
create or replace function pg_temp.f5m_enviar(p_os uuid, p_em timestamptz, p_chave text, p_validade date, p_via text default 'tela')
returns void
language sql as $f$
  update public.service_orders
     set quote_status = 'sent', orcamento_enviado_em = p_em, orcamento_enviado_via = p_via, orcamento_enviado_chave = p_chave,
         quote_validity_date = p_validade
   where id = p_os
$f$;

-- Um envio em orcamento_envios (o que orcamento_registrar_envio, a detecção ou a migration de dado gravam).
create or replace function pg_temp.f5m_envio(p_os uuid, p_em timestamptz, p_chave text, p_ao_cliente boolean,
                                             p_via text default 'tela') returns uuid
language sql as $f$
  insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em, marcou)
  select so.id, so.client_id, p_via, p_chave, p_ao_cliente, p_em, false from public.service_orders so where so.id = p_os
  returning id
$f$;

-- O orçamento enviado ao cliente (o funil em sent e a linha do envio), com a validade dada.
create or replace function pg_temp.f5m_enviado(p_cliente uuid, p_fone text, p_numero text, p_em timestamptz, p_validade date)
returns uuid
language plpgsql as $f$
declare
  v_os uuid;
begin
  v_os := pg_temp.f5m_orc(p_cliente, p_numero, p_em);
  perform pg_temp.f5m_enviar(v_os, p_em, public._agenda_chave_telefone(p_fone), p_validade);
  perform pg_temp.f5m_envio(v_os, p_em, public._agenda_chave_telefone(p_fone), true);
  return v_os;
end $f$;

-- O acompanhamento gravado direto (o estado é o que o teste quer, não o que o vigia faria).
create or replace function pg_temp.f5m_acomp(p_os uuid, p_estado text, p_parou text default null, p_encerramento text default null)
returns uuid
language sql as $f$
  insert into public.orcamento_acompanhamentos (service_order_id, client_id, chave, enviado_em, validade_ate, modo, estado,
                                                parou_por, parou_em, encerramento)
  select so.id, so.client_id, so.orcamento_enviado_chave, so.orcamento_enviado_em, so.quote_validity_date, 'ligado', p_estado,
         p_parou, case when p_parou is not null then so.orcamento_enviado_em + interval '1 hour' end, p_encerramento
    from public.service_orders so where so.id = p_os
  returning id
$f$;

-- Uma saída do orçamento já decidida (enviada, sombra ou incerta), com o acompanhamento e a ordem nos dados.
create or replace function pg_temp.f5m_saida(p_acomp uuid, p_tipo text, p_estado text, p_em timestamptz) returns uuid
language sql as $f$
  insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, client_id, modo, estado, motivo,
                                     enviar_em, decidida_em, enviada_em, texto, dados, dedupe_key)
  select 'orcamento', p_tipo, 'retorno_orcamento',
         case when p_tipo in ('orc_fechado', 'orc_dados_nota') then 'resposta_imediata' else 'comercial' end,
         a.chave, '55479' || a.chave, a.client_id, case when p_estado = 'sombra' then 'sombra' else 'ligado' end, p_estado,
         case when p_estado in ('recusada', 'cancelada') then 'canal' end, p_em,
         p_em, case when p_estado = 'enviada' then p_em end, 'Texto de teste da F5 (P13).',
         jsonb_build_object('acompanhamento_id', a.id, 'os_id', a.service_order_id),
         'orcamento:' || a.id || ':' || p_tipo || ':' || md5(p_estado || p_em::text)
    from public.orcamento_acompanhamentos a where a.id = p_acomp
  returning id
$f$;

-- O aceite gravado direto, com a mensagem dada (ou um id sem mensagem).
create or replace function pg_temp.f5m_aceite(p_msg uuid, p_cliente uuid, p_chave text, p_os uuid, p_estado text,
                                              p_decidido timestamptz default null, p_resultado jsonb default '{}'::jsonb,
                                              p_criado timestamptz default now()) returns uuid
language sql as $f$
  insert into public.orcamento_aceites (whatsapp_message_id, client_id, chave, candidatos, service_order_id, sinal_lido, estado,
                                        decidido_em, resultado, criado_em)
  values (p_msg, p_cliente, p_chave, (case when p_os is null then '{}'::uuid[] else array[p_os] end), p_os, 'pode fazer', p_estado,
          p_decidido, p_resultado, p_criado)
  returning id
$f$;

create or replace function pg_temp.f5m_med() returns jsonb
language sql as $f$
  select public.orcamento_medidas('2027-02-01 00:00-03', '2027-03-01 00:00-03')
$f$;

-- A diferença de uma contagem entre duas medidas (a chave ausente vale 0).
create or replace function pg_temp.f5m_d(p_antes jsonb, p_depois jsonb, variadic p_caminho text[]) returns integer
language sql as $f$
  select coalesce((p_depois #>> p_caminho)::integer, 0) - coalesce((p_antes #>> p_caminho)::integer, 0)
$f$;

create or replace function pg_temp.f5m_igual(p_rotulo text, p_obtido integer, p_esperado integer) returns void
language plpgsql as $f$
begin
  if p_obtido is distinct from p_esperado then
    raise exception '%: deu %, esperava %', p_rotulo, p_obtido, p_esperado;
  end if;
end $f$;

do $medidas$
declare
  c_desde constant timestamptz := '2027-02-01 00:00-03';   -- seg
  c_ate constant timestamptz := '2027-03-01 00:00-03';     -- seg (fora)
  c_t constant timestamptz := '2027-02-02 10:00-03';       -- ter: o envio
  c_val constant date := date '2027-02-09';                 -- ter: vencida há mais de 2 dias úteis em 01/03
  c_recente constant date := date '2027-02-25';             -- qui: + 2 dias úteis = seg 01/03, ainda não
  c_cmd constant text := 'select public.orcamento_vigia(now())';
  v_m0 jsonb; v_m1 jsonb; v_m jsonb;
  v_c uuid; v_c2 uuid; v_c3 uuid; v_p uuid; v_pessoa uuid;
  v_o1 uuid; v_o2 uuid; v_o3 uuid; v_o4 uuid; v_o5 uuid;
  v_a1 uuid; v_a2 uuid; v_a3 uuid;
  v_msg uuid; v_cartao uuid; v_cartao2 uuid;
  v_r jsonb;
  v text; v2 text;
  v_n integer; v_job bigint; v_job2 bigint;
  v_rec record;
  v_n_fun integer := 0;
begin
  begin
  -- O calendário não depende de ausência real do dono nem de sábado útil.
  update public.agenda_config set sabado_util = false where id;
  update public.agenda_disponibilidade d
     set substituida_em = now()
   where d.payee_id is null and d.situacao = 'indisponivel' and d.turno is null and d.substituida_em is null
     and d.periodo && daterange(date '2027-01-01', date '2027-04-01');
  update public.retorno_config set aceite_audio = false where id;
  update public.retorno_modelo_tipos set nivel = 'desligado' where tipo in ('orc_lembrete', 'orc_vespera', 'orc_encerramento');

  -- ── 1. O período e a forma ──
  begin
    perform public.orcamento_medidas(c_ate, c_desde);
    raise exception '1a: período invertido passou';
  exception when sqlstate '22023' then
    null;
  end;
  begin
    perform public.orcamento_medidas(null, c_ate);
    raise exception '1b: período sem início passou';
  exception when sqlstate '22023' then
    null;
  end;
  v_m := pg_temp.f5m_med();
  foreach v in array array['periodo', 'envios', 'acompanhamentos', 'passos', 'aceites', 'portao', 'sombra', 'respostas_do_dono'] loop
    if not (v_m ? v) then
      raise exception '1c: falta a chave % (%)', v, v_m;
    end if;
  end loop;
  foreach v in array array['sem_desfecho', 'parados_sem_desfecho', 'com_acompanhamento_ou_motivo', 'lembrete_depois_de_parar',
                           'aceite_sem_msg', 'rejeitado_sem_motivo', 'aceite_ate_registro'] loop
    if not ((v_m -> 'portao') ? v) then
      raise exception '1d: falta portao.%', v;
    end if;
  end loop;
  if not ((v_m -> 'aceites') ? 'pulados_audio') then
    raise exception '1e: falta aceites.pulados_audio';
  end if;

  -- ── 2. Os envios: por via, ao cliente e fora dele, orçamentos e reenvios ──
  begin
    v_m0 := pg_temp.f5m_med();
    v_c := pg_temp.f5m_cli('Ana Medidas F5 Teste', '5547900009930');
    v_c2 := pg_temp.f5m_cli('Cliente Final Medidas F5 Teste', '5547900009931', true);
    v_c3 := pg_temp.f5m_cli('João Medidas F5 Teste', null);
    v_o1 := pg_temp.f5m_orc(v_c, 'ORÇ-99701', c_t);
    perform pg_temp.f5m_envio(v_o1, c_t, '00009930', true, 'tela');
    perform pg_temp.f5m_envio(v_o1, c_t + interval '1 day', '00009930', true, 'assistente');   -- reenvio
    perform pg_temp.f5m_envio(v_o1, c_t + interval '2 days', '00009977', false, 'aparelho');   -- outro número (e reenvio)
    v_o2 := pg_temp.f5m_orc(v_c2, 'ORÇ-99702', c_t);
    perform pg_temp.f5m_envio(v_o2, c_t, '00009931', false, 'tela');                           -- Cliente Final
    v_o3 := pg_temp.f5m_orc(v_c3, 'ORÇ-99703', c_t);
    perform pg_temp.f5m_envio(v_o3, c_t, '00009978', false, 'tela');                           -- cliente sem telefone
    v_o4 := pg_temp.f5m_orc(v_c, 'ORÇ-99704', c_t);
    perform pg_temp.f5m_envio(v_o4, c_desde - interval '1 day', '00009930', true, 'tela');    -- antes do período: fora
    perform pg_temp.f5m_envio(v_o4, c_t, null, false, 'marcado');                              -- sem número (e reenvio)
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('2a total', pg_temp.f5m_d(v_m0, v_m1, 'envios', 'total'), 6);
    perform pg_temp.f5m_igual('2b via tela', pg_temp.f5m_d(v_m0, v_m1, 'envios', 'por_via', 'tela'), 3);
    perform pg_temp.f5m_igual('2c via assistente', pg_temp.f5m_d(v_m0, v_m1, 'envios', 'por_via', 'assistente'), 1);
    perform pg_temp.f5m_igual('2d via aparelho', pg_temp.f5m_d(v_m0, v_m1, 'envios', 'por_via', 'aparelho'), 1);
    perform pg_temp.f5m_igual('2e via marcado', pg_temp.f5m_d(v_m0, v_m1, 'envios', 'por_via', 'marcado'), 1);
    perform pg_temp.f5m_igual('2f ao cliente', pg_temp.f5m_d(v_m0, v_m1, 'envios', 'ao_cliente'), 2);
    perform pg_temp.f5m_igual('2g Cliente Final', pg_temp.f5m_d(v_m0, v_m1, 'envios', 'fora', 'cliente_final'), 1);
    perform pg_temp.f5m_igual('2h sem telefone', pg_temp.f5m_d(v_m0, v_m1, 'envios', 'fora', 'sem_telefone'), 1);
    perform pg_temp.f5m_igual('2i sem número', pg_temp.f5m_d(v_m0, v_m1, 'envios', 'fora', 'sem_numero'), 1);
    perform pg_temp.f5m_igual('2j outro número', pg_temp.f5m_d(v_m0, v_m1, 'envios', 'fora', 'outro_numero'), 1);
    perform pg_temp.f5m_igual('2k orçamentos', pg_temp.f5m_d(v_m0, v_m1, 'envios', 'orcamentos'), 4);
    perform pg_temp.f5m_igual('2l reenvios', pg_temp.f5m_d(v_m0, v_m1, 'envios', 'reenvios'), 3);
    raise exception 'f5m_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5m_cenario' then
      raise;
    end if;
  end;

  -- ── 3. Os acompanhamentos e os inelegíveis (o motivo no instante do envio) ──
  begin
    v_m0 := pg_temp.f5m_med();
    v_c := pg_temp.f5m_cli('Ana Acompanha F5 Teste', '5547900009932');
    perform pg_temp.f5m_msg('5547900009932', 'Bom dia, tudo bem?', c_t - interval '10 days');
    -- elegível e sem acompanhamento (o vigia desligado não o acompanhou)
    v_o1 := pg_temp.f5m_enviado(v_c, '5547900009932', 'ORÇ-99711', c_t, c_val);
    -- sem validade fixa
    v_o2 := pg_temp.f5m_enviado(v_c, '5547900009932', 'ORÇ-99712', c_t, null);
    -- a marcação à mão: sem chave
    v_o3 := pg_temp.f5m_orc(v_c, 'ORÇ-99713', c_t);
    update public.service_orders set quote_status = 'sent', orcamento_enviado_em = c_t, quote_validity_date = c_val where id = v_o3;
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('3a elegível', pg_temp.f5m_d(v_m0, v_m1, 'acompanhamentos', 'inelegiveis', 'elegivel'), 1);
    perform pg_temp.f5m_igual('3b sem validade', pg_temp.f5m_d(v_m0, v_m1, 'acompanhamentos', 'inelegiveis', 'sem_validade'), 1);
    perform pg_temp.f5m_igual('3c destino', pg_temp.f5m_d(v_m0, v_m1, 'acompanhamentos', 'inelegiveis', 'destino'), 1);
    -- Com acompanhamento, sai dos inelegíveis e entra nos criados.
    v_a1 := pg_temp.f5m_acomp(v_o1, 'parado', 'cliente_escreveu');
    v_o4 := pg_temp.f5m_enviado(v_c, '5547900009932', 'ORÇ-99714', c_t, c_val);
    perform pg_temp.f5m_acomp(v_o4, 'encerrado', null, 'sem_mensagem');
    v_o5 := pg_temp.f5m_enviado(v_c, '5547900009932', 'ORÇ-99715', c_t, c_val);
    v_a2 := pg_temp.f5m_acomp(v_o5, 'concluido', 'status_mudou');
    update public.orcamento_acompanhamentos set refeito_em = c_t + interval '1 day' where id = v_a2;
    v_m := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('3d elegível saiu', pg_temp.f5m_d(v_m0, v_m, 'acompanhamentos', 'inelegiveis', 'elegivel'), 0);
    perform pg_temp.f5m_igual('3e criados', pg_temp.f5m_d(v_m0, v_m, 'acompanhamentos', 'criados'), 3);
    perform pg_temp.f5m_igual('3f parados', pg_temp.f5m_d(v_m0, v_m, 'acompanhamentos', 'parados', 'cliente_escreveu'), 1);
    perform pg_temp.f5m_igual('3g encerrado sem mensagem',
                              pg_temp.f5m_d(v_m0, v_m, 'acompanhamentos', 'encerrados', 'sem_mensagem'), 1);
    perform pg_temp.f5m_igual('3h concluídos', pg_temp.f5m_d(v_m0, v_m, 'acompanhamentos', 'concluidos'), 1);
    perform pg_temp.f5m_igual('3i refeitos', pg_temp.f5m_d(v_m0, v_m, 'acompanhamentos', 'refeitos'), 1);
    raise exception 'f5m_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5m_cenario' then
      raise;
    end if;
  end;

  -- ── 4. Os passos: por tipo, o sem_sim com e sem cartão, o sozinho que foi ao cartão ──
  begin
    v_m0 := pg_temp.f5m_med();
    update public.retorno_modelo_tipos set nivel = 'sozinho' where tipo = 'orc_vespera';
    v_c := pg_temp.f5m_cli('Pedro Passos F5 Teste', '5547900009933');
    v_o1 := pg_temp.f5m_enviado(v_c, '5547900009933', 'ORÇ-99721', c_t, c_val);
    v_o2 := pg_temp.f5m_enviado(v_c, '5547900009933', 'ORÇ-99722', c_t, c_val);
    v_o3 := pg_temp.f5m_enviado(v_c, '5547900009933', 'ORÇ-99723', c_t, c_val);
    v_a1 := pg_temp.f5m_acomp(v_o1, 'ativo');
    v_a2 := pg_temp.f5m_acomp(v_o2, 'ativo');
    v_a3 := pg_temp.f5m_acomp(v_o3, 'ativo');
    insert into public.orcamento_passos (acompanhamento_id, passo, tipo, dia, ate, estado, motivo) values
      (v_a1, 'lembrete', 'orc_lembrete', date '2027-02-04', date '2027-02-05', 'pulado', 'sem_sim'),
      (v_a1, 'vespera', 'orc_vespera', date '2027-02-08', date '2027-02-08', 'aguarda_sim', null),
      (v_a1, 'encerramento', 'orc_encerramento', date '2027-02-10', date '2027-02-12', 'previsto', null),
      (v_a2, 'lembrete', 'orc_lembrete', date '2027-02-04', date '2027-02-05', 'pulado', 'sem_sim'),
      (v_a2, 'vespera', 'orc_vespera', date '2027-02-08', date '2027-02-08', 'sombra', null),
      (v_a2, 'encerramento', 'orc_encerramento', date '2027-02-10', date '2027-02-12', 'enviado', null),
      (v_a3, 'lembrete', 'orc_lembrete', date '2027-03-02', date '2027-03-03', 'pulado', 'sem_sim');   -- fora do período
    insert into public.retorno_cartoes (gatilho, dia, estado, hash, texto, expira_em)
      values ('puxar', date '2027-02-04', 'decidido', 'f5m-4', 'cartão de teste da F5 (P13)', '2027-02-05 09:00-03')
      returning id into v_cartao;
    insert into public.retorno_cartao_itens (cartao_id, n, tipo_item, passo_id, hash, estado)
      select v_cartao, 1, 'cadencia', p.id, 'f5m-4-1', 'fora'
        from public.orcamento_passos p where p.acompanhamento_id = v_a1 and p.passo = 'lembrete';
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('4a lembretes', pg_temp.f5m_d(v_m0, v_m1, 'passos', 'orc_lembrete', 'total'), 2);
    perform pg_temp.f5m_igual('4b pulados sem_sim', pg_temp.f5m_d(v_m0, v_m1, 'passos', 'orc_lembrete', 'pulados', 'sem_sim'), 2);
    perform pg_temp.f5m_igual('4c sem_sim sem cartão',
                              pg_temp.f5m_d(v_m0, v_m1, 'passos', 'orc_lembrete', 'sem_sim', 'sem_cartao'), 1);
    perform pg_temp.f5m_igual('4d sem_sim sem resposta',
                              pg_temp.f5m_d(v_m0, v_m1, 'passos', 'orc_lembrete', 'sem_sim', 'sem_resposta'), 1);
    perform pg_temp.f5m_igual('4e véspera aguarda_sim', pg_temp.f5m_d(v_m0, v_m1, 'passos', 'orc_vespera', 'aguarda_sim'), 1);
    perform pg_temp.f5m_igual('4f véspera sombra', pg_temp.f5m_d(v_m0, v_m1, 'passos', 'orc_vespera', 'sombra'), 1);
    perform pg_temp.f5m_igual('4g sozinho ao cartão', pg_temp.f5m_d(v_m0, v_m1, 'passos', 'orc_vespera', 'sozinho_ao_cartao'), 1);
    perform pg_temp.f5m_igual('4h lembrete não é sozinho',
                              pg_temp.f5m_d(v_m0, v_m1, 'passos', 'orc_lembrete', 'sozinho_ao_cartao'), 0);
    perform pg_temp.f5m_igual('4i encerramento previsto', pg_temp.f5m_d(v_m0, v_m1, 'passos', 'orc_encerramento', 'previstos'), 1);
    perform pg_temp.f5m_igual('4j encerramento enviado', pg_temp.f5m_d(v_m0, v_m1, 'passos', 'orc_encerramento', 'enviados'), 1);
    raise exception 'f5m_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5m_cenario' then
      raise;
    end if;
  end;

  -- ── 5. Os aceites: por estado, a sombra por seria, os dias úteis até a decisão, nao_era e mostrados, sem caso ──
  begin
    v_m0 := pg_temp.f5m_med();
    v_c := pg_temp.f5m_cli('Ana Aceites F5 Teste', '5547900009934');
    v_o1 := pg_temp.f5m_enviado(v_c, '5547900009934', 'ORÇ-99731', c_t - interval '1 day', c_val);
    -- com_sinal: mensagem seg 01/02, decidido qua 03/02 (2 dias úteis)
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009934', 'Pode fazer.', '2027-02-01 10:00-03'), v_c, '00009934', v_o1,
                               'com_sinal', '2027-02-03 11:00-03');
    -- nao_era no mesmo dia, mostrado num cartão
    v_a1 := pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009934', 'Fechado!', '2027-02-02 10:00-03'), v_c, '00009934', v_o1,
                               'nao_era', '2027-02-02 15:00-03');
    insert into public.retorno_cartoes (gatilho, dia, estado, hash, texto, expira_em)
      values ('puxar', date '2027-02-02', 'decidido', 'f5m-5', 'cartão de teste da F5 (P13)', '2027-02-03 09:00-03')
      returning id into v_cartao;
    insert into public.retorno_cartao_itens (cartao_id, n, tipo_item, aceite_id, hash, estado)
      values (v_cartao, 1, 'aceite', v_a1, 'f5m-5-1', 'feito');
    -- a sombra: o que ele seria
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009934', 'Aprovado', '2027-02-03 10:00-03'), v_c, '00009934', v_o1,
                               'sombra', null, '{"seria": "detectado"}');
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009934', 'Pode marcar', '2027-02-03 11:00-03'), v_c, '00009934', v_o1,
                               'sombra', null, '{"seria": "agenda"}');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('5a total', pg_temp.f5m_d(v_m0, v_m1, 'aceites', 'total'), 4);
    perform pg_temp.f5m_igual('5b com_sinal', pg_temp.f5m_d(v_m0, v_m1, 'aceites', 'por_estado', 'com_sinal'), 1);
    perform pg_temp.f5m_igual('5c nao_era', pg_temp.f5m_d(v_m0, v_m1, 'aceites', 'por_estado', 'nao_era'), 1);
    perform pg_temp.f5m_igual('5d sombra', pg_temp.f5m_d(v_m0, v_m1, 'aceites', 'por_estado', 'sombra'), 2);
    perform pg_temp.f5m_igual('5e seria detectado', pg_temp.f5m_d(v_m0, v_m1, 'aceites', 'sombra_por_seria', 'detectado'), 1);
    perform pg_temp.f5m_igual('5f seria agenda', pg_temp.f5m_d(v_m0, v_m1, 'aceites', 'sombra_por_seria', 'agenda'), 1);
    perform pg_temp.f5m_igual('5g nao_era (linha)', pg_temp.f5m_d(v_m0, v_m1, 'aceites', 'nao_era'), 1);
    perform pg_temp.f5m_igual('5h mostrados', pg_temp.f5m_d(v_m0, v_m1, 'aceites', 'mostrados'), 1);
    perform pg_temp.f5m_igual('5i sem caso', pg_temp.f5m_d(v_m0, v_m1, 'aceites', 'sem_caso'), 4);
    perform pg_temp.f5m_igual('5j decididos', pg_temp.f5m_d(v_m0, v_m1, 'aceites', 'dias_uteis_ate_decisao', 'decididos'), 2);
    if coalesce((v_m0 #>> '{aceites,dias_uteis_ate_decisao,decididos}')::integer, 0) = 0 then
      -- Só os dois deste caso: 0 e 2 dias úteis.
      if (v_m1 #>> '{aceites,dias_uteis_ate_decisao,maximo}')::numeric is distinct from 2
         or (v_m1 #>> '{aceites,dias_uteis_ate_decisao,mediana}')::numeric is distinct from 1 then
        raise exception '5k: dias úteis até a decisão (%)', v_m1 -> 'aceites' -> 'dias_uteis_ate_decisao';
      end if;
    elsif ((v_m1 #>> '{aceites,dias_uteis_ate_decisao,maximo}')::numeric >= 2) is not true then
      raise exception '5l: o máximo de dias úteis não pegou os 2 deste caso (%)', v_m1 -> 'aceites' -> 'dias_uteis_ate_decisao';
    end if;
    raise exception 'f5m_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5m_cenario' then
      raise;
    end if;
  end;

  -- ── 6. aceites.pulados_audio (o nº 8c da P6.2): o áudio transcrito "pode fazer" de número de cliente com orçamento
  --       candidato, com aceite_audio desligado, conta 1; o texto, o áudio sem candidato e o de número sem cadastro não ──
  begin
    v_m0 := pg_temp.f5m_med();
    v_c := pg_temp.f5m_cli('Ana Áudio F5 Teste', '5547900009935');
    v_o1 := pg_temp.f5m_enviado(v_c, '5547900009935', 'ORÇ-99741', c_t, c_val);
    perform pg_temp.f5m_msg('5547900009935', 'pode fazer', c_t + interval '1 day', 'inbound', 'audio');
    v_m := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('6a áudio com candidato', pg_temp.f5m_d(v_m0, v_m, 'aceites', 'pulados_audio'), 1);
    -- o texto não é áudio
    perform pg_temp.f5m_msg('5547900009935', 'pode fazer', c_t + interval '1 day 1 hour');
    -- o áudio de cliente sem orçamento enviado
    v_c2 := pg_temp.f5m_cli('João Áudio F5 Teste', '5547900009936');
    perform pg_temp.f5m_msg('5547900009936', 'pode fazer', c_t + interval '1 day', 'inbound', 'audio');
    -- o áudio de número sem cadastro
    perform pg_temp.f5m_msg('5547900009937', 'pode fazer', c_t + interval '1 day', 'inbound', 'audio');
    -- o áudio de antes do envio (sem candidato no instante da mensagem)
    perform pg_temp.f5m_msg('5547900009935', 'pode fazer', c_t - interval '1 hour', 'inbound', 'audio');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('6b só o primeiro', pg_temp.f5m_d(v_m0, v_m1, 'aceites', 'pulados_audio'), 1);
    -- Com aceite_audio, o detector não pula: nada é pulado.
    update public.retorno_config set aceite_audio = true where id;
    perform pg_temp.f5m_igual('6c com aceite_audio', (pg_temp.f5m_med() #>> '{aceites,pulados_audio}')::integer, 0);
    raise exception 'f5m_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5m_cenario' then
      raise;
    end if;
  end;

  -- ── 7. portao.sem_desfecho e parados_sem_desfecho: cada caso que quebra e cada um que não quebra ──
  begin
    v_c := pg_temp.f5m_cli('Pedro Desfecho F5 Teste', '5547900009940');
    v_m := pg_temp.f5m_med();
    -- 7a quebra: enviado ao cliente, vencido, sem desfecho
    v_o1 := pg_temp.f5m_enviado(v_c, '5547900009940', 'ORÇ-99751', c_t, c_val);
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('7a enviado vencido', pg_temp.f5m_d(v_m, v_m1, 'portao', 'sem_desfecho'), 1);
    v_m := v_m1;
    -- 7b não quebra: perdido com motivo
    v_o2 := pg_temp.f5m_enviado(v_c, '5547900009940', 'ORÇ-99752', c_t, c_val);
    update public.service_orders set quote_status = 'rejected', motivo_perda = 'preco', motivo_perda_por = 'tela' where id = v_o2;
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('7b perdido com motivo', pg_temp.f5m_d(v_m, v_m1, 'portao', 'sem_desfecho'), 0);
    v_m := v_m1;
    -- 7c quebra: perdido com o motivo antigo
    v_o2 := pg_temp.f5m_enviado(v_c, '5547900009940', 'ORÇ-99753', c_t, c_val);
    update public.service_orders set quote_status = 'rejected', motivo_perda = 'sem_motivo_antigo', motivo_perda_por = 'migracao'
     where id = v_o2;
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('7c motivo antigo', pg_temp.f5m_d(v_m, v_m1, 'portao', 'sem_desfecho'), 1);
    v_m := v_m1;
    -- 7d não quebra: convertido
    v_o2 := pg_temp.f5m_enviado(v_c, '5547900009940', 'ORÇ-99754', c_t, c_val);
    update public.service_orders
       set status = 'open', converted_to_os_at = c_t + interval '3 days', service_order_number = 'OS-99754', quote_status = 'approved'
     where id = v_o2;
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('7d convertido', pg_temp.f5m_d(v_m, v_m1, 'portao', 'sem_desfecho'), 0);
    v_m := v_m1;
    -- 7e não quebra: aguardando o sinal
    v_o2 := pg_temp.f5m_enviado(v_c, '5547900009940', 'ORÇ-99755', c_t, c_val);
    update public.service_orders set quote_status = 'awaiting_deposit' where id = v_o2;
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('7e aguardando sinal', pg_temp.f5m_d(v_m, v_m1, 'portao', 'sem_desfecho'), 0);
    v_m := v_m1;
    -- 7f não quebra: aceite registrado pelo cartão
    v_o2 := pg_temp.f5m_enviado(v_c, '5547900009940', 'ORÇ-99756', c_t, c_val);
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009940', 'Pode fazer.', c_t + interval '1 day'), v_c, '00009940', v_o2,
                               'sem_sinal', c_t + interval '1 day 1 hour');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('7f aceite registrado', pg_temp.f5m_d(v_m, v_m1, 'portao', 'sem_desfecho'), 0);
    v_m := v_m1;
    -- 7g não quebra: cancelado
    v_o2 := pg_temp.f5m_enviado(v_c, '5547900009940', 'ORÇ-99757', c_t, c_val);
    update public.service_orders set status = 'cancelled', cancelled_at = c_t + interval '1 day', cancellation_reason = 'teste F5'
     where id = v_o2;
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('7g cancelado', pg_temp.f5m_d(v_m, v_m1, 'portao', 'sem_desfecho'), 0);
    v_m := v_m1;
    -- 7h não quebra: ainda não venceu há 2 dias úteis
    perform pg_temp.f5m_enviado(v_c, '5547900009940', 'ORÇ-99758', c_t, c_recente);
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('7h validade recente', pg_temp.f5m_d(v_m, v_m1, 'portao', 'sem_desfecho'), 0);
    v_m := v_m1;
    -- 7i não quebra: só o histórico
    v_o2 := pg_temp.f5m_orc(v_c, 'ORÇ-99759', c_t);
    perform pg_temp.f5m_enviar(v_o2, c_t, '00009940', c_val, 'historico');
    perform pg_temp.f5m_envio(v_o2, c_t, '00009940', true, 'historico');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('7i histórico', pg_temp.f5m_d(v_m, v_m1, 'portao', 'sem_desfecho'), 0);
    v_m := v_m1;
    -- 7j quebra: mandado a outro número (o funil não andou; a validade é a do cadastro)
    v_o2 := pg_temp.f5m_orc(v_c, 'ORÇ-99760', c_t);
    update public.service_orders set quote_validity_date = c_val where id = v_o2;
    perform pg_temp.f5m_envio(v_o2, c_t, '00009977', false, 'tela');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('7j outro número', pg_temp.f5m_d(v_m, v_m1, 'portao', 'sem_desfecho'), 1);
    v_m := v_m1;
    -- 7k não quebra: mandado a número confirmado de parceiro
    insert into public.parceiros (nome, sigla, tipo) values ('Revenda Medidas F5 Teste', 'RMFT', 'revenda') returning id into v_p;
    insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Carla', 'comercial') returning id into v_pessoa;
    insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_documento)
      values (v_pessoa, '5547900009979', '00009979', '47', 'confirmado', c_t - interval '30 days', true);
    v_o2 := pg_temp.f5m_orc(v_c, 'ORÇ-99761', c_t);
    update public.service_orders set quote_validity_date = c_val where id = v_o2;
    perform pg_temp.f5m_envio(v_o2, c_t, '00009979', false, 'tela');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('7k número de parceiro', pg_temp.f5m_d(v_m, v_m1, 'portao', 'sem_desfecho'), 0);
    v_m := v_m1;
    -- 7l não quebra: o cliente é parceiro (dúvida 4)
    v_c2 := pg_temp.f5m_cli('João Revenda F5 Teste', '5547900009941');
    update public.retorno_config set clientes_parceiros = clientes_parceiros || array[v_c2] where id;
    perform pg_temp.f5m_enviado(v_c2, '5547900009941', 'ORÇ-99762', c_t, c_val);
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('7l cliente parceiro', pg_temp.f5m_d(v_m, v_m1, 'portao', 'sem_desfecho'), 0);
    v_m := v_m1;
    -- 7m quebra: vencido com o acompanhamento parado porque o cliente escreveu, sem motivo (e entra em parados_sem_desfecho)
    v_o2 := pg_temp.f5m_enviado(v_c, '5547900009940', 'ORÇ-99763', c_t, c_val);
    perform pg_temp.f5m_acomp(v_o2, 'parado', 'cliente_escreveu');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('7m parado sem desfecho', pg_temp.f5m_d(v_m, v_m1, 'portao', 'sem_desfecho'), 1);
    perform pg_temp.f5m_igual('7n parados_sem_desfecho', pg_temp.f5m_d(v_m, v_m1, 'portao', 'parados_sem_desfecho'), 1);
    v_m := v_m1;
    -- 7o não muda parados_sem_desfecho: o parado pelo dono (o acompanhamento não é desfecho, mas não é o caso que o plano mede)
    v_o2 := pg_temp.f5m_enviado(v_c, '5547900009940', 'ORÇ-99764', c_t, c_val);
    perform pg_temp.f5m_acomp(v_o2, 'parado', 'dono_falou');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('7o parado pelo dono', pg_temp.f5m_d(v_m, v_m1, 'portao', 'sem_desfecho'), 1);
    perform pg_temp.f5m_igual('7p parado pelo dono fora de parados', pg_temp.f5m_d(v_m, v_m1, 'portao', 'parados_sem_desfecho'), 0);
    raise exception 'f5m_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5m_cenario' then
      raise;
    end if;
  end;

  -- ── 8. portao.lembrete_depois_de_parar: cruza as mensagens e os bloqueios, nunca o estado gravado ──
  begin
    v_m := pg_temp.f5m_med();
    -- 8a quebra: o cliente escreveu na qua 03/02 e o lembrete saiu na qui 04/02 (o acompanhamento diz ativo)
    v_c := pg_temp.f5m_cli('Pedro Parar F5 Teste', '5547900009942');
    v_o1 := pg_temp.f5m_enviado(v_c, '5547900009942', 'ORÇ-99771', c_t, c_val);
    v_a1 := pg_temp.f5m_acomp(v_o1, 'ativo');
    perform pg_temp.f5m_msg('5547900009942', 'ok, obrigado', '2027-02-03 15:00-03');
    perform pg_temp.f5m_saida(v_a1, 'orc_lembrete', 'enviada', '2027-02-04 10:00-03');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('8a mensagem antes do lembrete', pg_temp.f5m_d(v_m, v_m1, 'portao', 'lembrete_depois_de_parar'), 1);
    v_m := v_m1;
    -- 8b não quebra: a mensagem veio depois do lembrete, e a de antes do envio não conta
    v_c := pg_temp.f5m_cli('João Parar F5 Teste', '5547900009943');
    perform pg_temp.f5m_msg('5547900009943', 'Bom dia', c_t - interval '1 day');
    v_o1 := pg_temp.f5m_enviado(v_c, '5547900009943', 'ORÇ-99772', c_t, c_val);
    v_a1 := pg_temp.f5m_acomp(v_o1, 'ativo');
    perform pg_temp.f5m_saida(v_a1, 'orc_lembrete', 'enviada', '2027-02-04 10:00-03');
    perform pg_temp.f5m_msg('5547900009943', 'Vi sim, obrigado', '2027-02-04 11:00-03');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('8b mensagem depois do lembrete', pg_temp.f5m_d(v_m, v_m1, 'portao', 'lembrete_depois_de_parar'), 0);
    v_m := v_m1;
    -- 8c quebra: o número entrou em whatsapp_blocked_numbers (PARAR) antes do lembrete
    v_c := pg_temp.f5m_cli('Ana Parar F5 Teste', '5547900009944');
    v_o1 := pg_temp.f5m_enviado(v_c, '5547900009944', 'ORÇ-99773', c_t, c_val);
    v_a1 := pg_temp.f5m_acomp(v_o1, 'ativo');
    insert into public.whatsapp_blocked_numbers (phone_normalized, reason, created_at, tipo)
      values ('5547900009944', 'teste F5 (P13)', '2027-02-03 09:00-03', 'opt_out');
    perform pg_temp.f5m_saida(v_a1, 'orc_vespera', 'enviada', '2027-02-08 10:00-03');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('8c bloqueado antes', pg_temp.f5m_d(v_m, v_m1, 'portao', 'lembrete_depois_de_parar'), 1);
    v_m := v_m1;
    -- 8d quebra também na sombra (o portão de ligar lê a sombra)
    v_c := pg_temp.f5m_cli('Pedro Sombra F5 Teste', '5547900009945');
    v_o1 := pg_temp.f5m_enviado(v_c, '5547900009945', 'ORÇ-99774', c_t, c_val);
    v_a1 := pg_temp.f5m_acomp(v_o1, 'ativo');
    perform pg_temp.f5m_msg('5547900009945', 'Desisti', '2027-02-03 15:00-03');
    perform pg_temp.f5m_saida(v_a1, 'orc_lembrete', 'sombra', '2027-02-04 10:00-03');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('8d sombra', pg_temp.f5m_d(v_m, v_m1, 'portao', 'lembrete_depois_de_parar'), 1);
    perform pg_temp.f5m_igual('8e a parte da sombra', pg_temp.f5m_d(v_m, v_m1, 'portao', 'lembrete_depois_de_parar_sombra'), 1);
    v_m := v_m1;
    -- 8f não quebra: o "Fechado" depois de uma mensagem não é da cadência; a saída recusada não saiu
    perform pg_temp.f5m_saida(v_a1, 'orc_fechado', 'enviada', '2027-02-05 10:00-03');
    perform pg_temp.f5m_saida(v_a1, 'orc_encerramento', 'recusada', '2027-02-10 10:00-03');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('8f Fechado e recusada', pg_temp.f5m_d(v_m, v_m1, 'portao', 'lembrete_depois_de_parar'), 0);
    raise exception 'f5m_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5m_cenario' then
      raise;
    end if;
  end;

  -- ── 9. portao.aceite_sem_msg: o id que não é de mensagem nenhuma quebra; o da mensagem não ──
  begin
    v_m := pg_temp.f5m_med();
    v_c := pg_temp.f5m_cli('Ana Prova F5 Teste', '5547900009946');
    perform pg_temp.f5m_aceite(gen_random_uuid(), v_c, '00009946', null, 'duvida', null, '{}', '2027-02-10 10:00-03');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('9a sem a mensagem', pg_temp.f5m_d(v_m, v_m1, 'portao', 'aceite_sem_msg'), 1);
    v_m := v_m1;
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009946', 'Pode fazer.', '2027-02-10 10:00-03'), v_c, '00009946', null,
                               'duvida');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('9b com a mensagem', pg_temp.f5m_d(v_m, v_m1, 'portao', 'aceite_sem_msg'), 0);
    raise exception 'f5m_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5m_cenario' then
      raise;
    end if;
  end;

  -- ── 10. portao.rejeitado_sem_motivo: o "perdido" novo sem motivo quebra; com motivo não. Depois da P9 (o CHECK no banco),
  --        o caso que quebra nem se grava ──
  begin
    v_m := pg_temp.f5m_med();
    v_c := pg_temp.f5m_cli('João Perdido F5 Teste', '5547900009947');
    v_o1 := pg_temp.f5m_enviado(v_c, '5547900009947', 'ORÇ-99781', c_t, c_val);
    if exists (select 1 from pg_constraint where conname = 'service_orders_rejeitado_tem_motivo'
                                            and conrelid = 'public.service_orders'::regclass) then
      begin
        update public.service_orders set quote_status = 'rejected', motivo_perda_em = '2027-02-10 10:00-03' where id = v_o1;
        raise exception '10a: rejeitado sem motivo passou com o CHECK no banco';
      exception when check_violation then
        null;
      end;
    else
      update public.service_orders set quote_status = 'rejected', motivo_perda_em = '2027-02-10 10:00-03' where id = v_o1;
      v_m1 := pg_temp.f5m_med();
      perform pg_temp.f5m_igual('10b sem motivo', pg_temp.f5m_d(v_m, v_m1, 'portao', 'rejeitado_sem_motivo'), 1);
      v_m := v_m1;
      -- o antigo (sem a hora do gatilho no período) não é novo
      v_o2 := pg_temp.f5m_enviado(v_c, '5547900009947', 'ORÇ-99782', c_t, c_val);
      update public.service_orders set quote_status = 'rejected' where id = v_o2;
      v_m1 := pg_temp.f5m_med();
      perform pg_temp.f5m_igual('10c fora do período', pg_temp.f5m_d(v_m, v_m1, 'portao', 'rejeitado_sem_motivo'), 0);
      v_m := v_m1;
    end if;
    v_o2 := pg_temp.f5m_enviado(v_c, '5547900009947', 'ORÇ-99783', c_t, c_val);
    update public.service_orders
       set quote_status = 'rejected', motivo_perda = 'prazo', motivo_perda_por = 'tela', motivo_perda_em = '2027-02-10 10:00-03'
     where id = v_o2;
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('10d com motivo', pg_temp.f5m_d(v_m, v_m1, 'portao', 'rejeitado_sem_motivo'), 0);
    raise exception 'f5m_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5m_cenario' then
      raise;
    end if;
  end;

  -- ── 11. portao.aceite_ate_registro: sobre todos os aceites com a mensagem há mais de 1 dia útil ──
  begin
    v_c := pg_temp.f5m_cli('Pedro Registro F5 Teste', '5547900009948');
    v_o1 := pg_temp.f5m_enviado(v_c, '5547900009948', 'ORÇ-99791', c_t - interval '1 day', c_val);
    v_m := pg_temp.f5m_med();
    -- 11a o duvida nunca decidido conta contra
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009948', 'Pode fazer.', '2027-02-02 10:00-03'), v_c, '00009948', null,
                               'duvida');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('11a duvida no total', pg_temp.f5m_d(v_m, v_m1, 'portao', 'aceite_ate_registro', 'total'), 1);
    perform pg_temp.f5m_igual('11b duvida não está no prazo', pg_temp.f5m_d(v_m, v_m1, 'portao', 'aceite_ate_registro', 'no_prazo'), 0);
    v_m := v_m1;
    -- 11c o substituido não conta nem a favor nem contra
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009948', 'Fechado!', '2027-02-02 10:05-03'), v_c, '00009948', v_o1,
                               'substituido', '2027-02-03 10:00-03');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('11c substituido', pg_temp.f5m_d(v_m, v_m1, 'portao', 'aceite_ate_registro', 'total'), 0);
    v_m := v_m1;
    -- 11d registrado no dia útil seguinte: a favor
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009948', 'Aprovado', '2027-02-02 10:10-03'), v_c, '00009948', v_o1,
                               'com_sinal', '2027-02-03 16:00-03');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('11d no prazo', pg_temp.f5m_d(v_m, v_m1, 'portao', 'aceite_ate_registro', 'no_prazo'), 1);
    perform pg_temp.f5m_igual('11e no prazo (total)', pg_temp.f5m_d(v_m, v_m1, 'portao', 'aceite_ate_registro', 'total'), 1);
    v_m := v_m1;
    -- 11f registrado depois de 1 dia útil: contra
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009948', 'Pode seguir', '2027-02-02 10:15-03'), v_c, '00009948', v_o1,
                               'sem_sinal', '2027-02-05 10:00-03');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('11f fora do prazo', pg_temp.f5m_d(v_m, v_m1, 'portao', 'aceite_ate_registro', 'no_prazo'), 0);
    perform pg_temp.f5m_igual('11g fora do prazo (total)', pg_temp.f5m_d(v_m, v_m1, 'portao', 'aceite_ate_registro', 'total'), 1);
    v_m := v_m1;
    -- 11h o respondido com a ordem convertida no dia útil seguinte: a favor; o caiu: contra
    v_o2 := pg_temp.f5m_enviado(v_c, '5547900009948', 'ORÇ-99792', c_t - interval '1 day', c_val);
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009948', 'Vamos fazer', '2027-02-02 10:20-03'), v_c, '00009948', v_o2,
                               'respondido', '2027-02-02 11:00-03');
    update public.service_orders
       set status = 'open', converted_to_os_at = '2027-02-03 09:00-03', service_order_number = 'OS-99792', quote_status = 'approved'
     where id = v_o2;
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009948', 'De acordo', '2027-02-02 10:25-03'), v_c, '00009948', v_o1, 'caiu');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('11h respondido e caiu (prazo)', pg_temp.f5m_d(v_m, v_m1, 'portao', 'aceite_ate_registro', 'no_prazo'), 1);
    perform pg_temp.f5m_igual('11i respondido e caiu (total)', pg_temp.f5m_d(v_m, v_m1, 'portao', 'aceite_ate_registro', 'total'), 2);
    v_m := v_m1;
    -- 11j fora: nao_era, sombra e a mensagem de sex 26/02 (o dia útil seguinte é seg 01/03, o fim do período)
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009948', 'Autorizo', '2027-02-02 10:30-03'), v_c, '00009948', v_o1,
                               'nao_era', '2027-02-02 12:00-03');
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009948', 'Topo', '2027-02-02 10:35-03'), v_c, '00009948', v_o1,
                               'sombra', null, '{"seria": "detectado"}');
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009948', 'Pode fazer.', '2027-02-26 10:00-03'), v_c, '00009948', v_o1,
                               'detectado');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('11j fora da conta', pg_temp.f5m_d(v_m, v_m1, 'portao', 'aceite_ate_registro', 'total'), 0);
    raise exception 'f5m_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5m_cenario' then
      raise;
    end if;
  end;

  -- ── 12. portao.com_acompanhamento_ou_motivo (informativo) ──
  begin
    v_m := pg_temp.f5m_med();
    v_c := pg_temp.f5m_cli('Ana Meta F5 Teste', '5547900009949');
    perform pg_temp.f5m_msg('5547900009949', 'Bom dia, tudo bem?', c_t - interval '10 days');
    -- elegível e sem acompanhamento: enviado, sem nada
    perform pg_temp.f5m_enviado(v_c, '5547900009949', 'ORÇ-99795', c_t, c_val);
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('12a enviados', pg_temp.f5m_d(v_m, v_m1, 'portao', 'com_acompanhamento_ou_motivo', 'enviados'), 1);
    perform pg_temp.f5m_igual('12b sem nada', pg_temp.f5m_d(v_m, v_m1, 'portao', 'com_acompanhamento_ou_motivo', 'com'), 0);
    v_m := v_m1;
    -- com acompanhamento; e o inelegível (sem validade); o mandado a outro número não é "enviado ao cliente"
    v_o1 := pg_temp.f5m_enviado(v_c, '5547900009949', 'ORÇ-99796', c_t, c_val);
    perform pg_temp.f5m_acomp(v_o1, 'ativo');
    perform pg_temp.f5m_enviado(v_c, '5547900009949', 'ORÇ-99797', c_t, null);
    v_o2 := pg_temp.f5m_orc(v_c, 'ORÇ-99798', c_t);
    perform pg_temp.f5m_envio(v_o2, c_t, '00009977', false, 'tela');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('12c enviados', pg_temp.f5m_d(v_m, v_m1, 'portao', 'com_acompanhamento_ou_motivo', 'enviados'), 2);
    perform pg_temp.f5m_igual('12d com', pg_temp.f5m_d(v_m, v_m1, 'portao', 'com_acompanhamento_ou_motivo', 'com'), 2);
    raise exception 'f5m_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5m_cenario' then
      raise;
    end if;
  end;

  -- ── 13. sombra.precisao_aceite ──
  begin
    v_m := pg_temp.f5m_med();
    v_c := pg_temp.f5m_cli('João Precisão F5 Teste', '5547900009950');
    v_o1 := pg_temp.f5m_enviado(v_c, '5547900009950', 'ORÇ-99701', c_t, c_val);
    v_o2 := pg_temp.f5m_enviado(v_c, '5547900009950', 'ORÇ-99702', c_t, c_val);
    v_o3 := pg_temp.f5m_enviado(v_c, '5547900009950', 'ORÇ-99703', c_t, c_val);
    -- convertido 3 dias depois da mensagem: acerto
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009950', 'Pode fazer.', '2027-02-03 10:00-03'), v_c, '00009950', v_o1,
                               'sombra', null, '{"seria": "detectado"}');
    update public.service_orders
       set status = 'open', converted_to_os_at = '2027-02-06 10:00-03', service_order_number = 'OS-99701', quote_status = 'approved'
     where id = v_o1;
    -- convertido 10 dias depois: não é acerto
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009950', 'Fechado!', '2027-02-03 10:05-03'), v_c, '00009950', v_o2,
                               'sombra', null, '{"seria": "detectado"}');
    update public.service_orders
       set status = 'open', converted_to_os_at = '2027-02-13 10:00-03', service_order_number = 'OS-99702', quote_status = 'approved'
     where id = v_o2;
    -- nunca aprovado
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009950', 'Aprovado', '2027-02-03 10:10-03'), v_c, '00009950', v_o3,
                               'sombra', null, '{"seria": "detectado"}');
    perform pg_temp.f5m_aceite(pg_temp.f5m_msg('5547900009950', 'Vamos fazer', '2027-02-03 10:15-03'), v_c, '00009950', null,
                               'sombra', null, '{"seria": "duvida"}');
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('13a acertos', pg_temp.f5m_d(v_m, v_m1, 'sombra', 'precisao_aceite', 'acertos'), 1);
    perform pg_temp.f5m_igual('13b detectados', pg_temp.f5m_d(v_m, v_m1, 'sombra', 'precisao_aceite', 'detectados'), 3);
    perform pg_temp.f5m_igual('13c duvida', pg_temp.f5m_d(v_m, v_m1, 'sombra', 'precisao_aceite', 'duvida'), 1);
    perform pg_temp.f5m_igual('13d agenda', pg_temp.f5m_d(v_m, v_m1, 'sombra', 'precisao_aceite', 'agenda'), 0);
    raise exception 'f5m_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5m_cenario' then
      raise;
    end if;
  end;

  -- ── 14. respostas_do_dono: os toques nos cartões com item da F5, e os dias úteis de fev/2027 (20, sem feriado) ──
  begin
    v_m := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('14a dias úteis', (v_m #>> '{respostas_do_dono,dias_uteis}')::integer, 20);
    v_c := pg_temp.f5m_cli('Pedro Toques F5 Teste', '5547900009951');
    v_o1 := pg_temp.f5m_enviado(v_c, '5547900009951', 'ORÇ-99799', c_t, c_val);
    v_a1 := pg_temp.f5m_acomp(v_o1, 'ativo');
    insert into public.orcamento_passos (acompanhamento_id, passo, tipo, dia, ate, estado)
      values (v_a1, 'lembrete', 'orc_lembrete', date '2027-02-04', date '2027-02-05', 'aguarda_sim');
    insert into public.retorno_cartoes (gatilho, dia, estado, hash, texto, expira_em)
      values ('puxar', date '2027-02-04', 'decidido', 'f5m-14a', 'cartão de teste da F5 (P13)', '2027-02-05 09:00-03')
      returning id into v_cartao;
    insert into public.retorno_cartao_itens (cartao_id, n, tipo_item, passo_id, hash, estado)
      select v_cartao, 1, 'cadencia', p.id, 'f5m-14a-1', 'feito' from public.orcamento_passos p where p.acompanhamento_id = v_a1;
    insert into public.retorno_cartoes (gatilho, dia, estado, hash, texto, expira_em)
      values ('puxar', date '2027-02-05', 'decidido', 'f5m-14b', 'cartão de teste sem item da F5', '2027-02-06 09:00-03')
      returning id into v_cartao2;
    insert into public.retorno_toques (em, cartao_id, palavra, latencia_s, rapido) values
      ('2027-02-04 10:01-03', v_cartao, 'letra', 30, true),
      ('2027-02-04 10:02-03', v_cartao, 'sim_pin', 40, true),
      ('2027-03-02 10:00-03', v_cartao, 'ver', 10, true),        -- fora do período
      ('2027-02-05 10:00-03', v_cartao2, 'sim_pin', 10, true);   -- cartão sem item da F5
    v_m1 := pg_temp.f5m_med();
    perform pg_temp.f5m_igual('14b toques', pg_temp.f5m_d(v_m, v_m1, 'respostas_do_dono', 'toques'), 2);
    if coalesce((v_m #>> '{respostas_do_dono,toques}')::integer, 0) = 0
       and (v_m1 #>> '{respostas_do_dono,por_dia_util}')::numeric is distinct from 0.10 then
      raise exception '14c: por dia útil (%)', v_m1 -> 'respostas_do_dono';
    end if;
    raise exception 'f5m_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5m_cenario' then
      raise;
    end if;
  end;

  -- ── 15. O cron: um job só, com o comando certo; nenhum outro job muda; o vigia com tudo desligado não acompanha nada ──
  select count(*), min(j.jobid) into v_n, v_job from cron.job j where j.jobname = 'retorno-orcamento';
  if v_n is distinct from 1::bigint then
    raise exception '15a: % jobs retorno-orcamento', v_n;
  end if;
  if not exists (select 1 from cron.job j
                  where j.jobid = v_job and j.schedule = '*/5 10-23 * * *' and btrim(j.command) = c_cmd and j.active) then
    raise exception '15b: o job retorno-orcamento não está com a agenda e o comando certos';
  end if;
  if exists (select 1 from cron.job j where j.jobname is distinct from 'retorno-orcamento' and j.command ~ 'orcamento_') then
    raise exception '15c: outro job chama uma função do orçamento';
  end if;
  -- Reaplicar o schedule da migration: o mesmo job (sem outro), e os outros jobs iguais.
  select md5(coalesce(string_agg(j.jobid || '|' || coalesce(j.jobname, '') || '|' || j.schedule || '|' || j.command || '|' || j.active::text,
                                 E'\n' order by j.jobid), ''))
    into v from cron.job j where j.jobname is distinct from 'retorno-orcamento';
  perform cron.schedule('retorno-orcamento', '*/5 10-23 * * *', c_cmd);
  select md5(coalesce(string_agg(j.jobid || '|' || coalesce(j.jobname, '') || '|' || j.schedule || '|' || j.command || '|' || j.active::text,
                                 E'\n' order by j.jobid), ''))
    into v2 from cron.job j where j.jobname is distinct from 'retorno-orcamento';
  if v2 is distinct from v then
    raise exception '15d: reaplicar o cron mudou outro job';
  end if;
  select count(*), min(j.jobid) into v_n, v_job2 from cron.job j where j.jobname = 'retorno-orcamento';
  if v_n is distinct from 1::bigint or v_job2 is distinct from v_job then
    raise exception '15e: reaplicar o cron criou outro job (% jobs)', v_n;
  end if;
  -- Com as chaves no padrão (tudo desligado), o vigia não acompanha nem agenda nada.
  begin
    update public.retorno_config
       set orcamento_modo = 'desligado', validade_envio_ligada = false, envio_mao_modo = 'desligado', aceite_modo = 'desligado',
           dados_nota_ligado = false
     where id;
    v_c := pg_temp.f5m_cli('Ana Desligado F5 Teste', '5547900009952');
    perform pg_temp.f5m_msg('5547900009952', 'Bom dia', c_t - interval '10 days');
    v_o1 := pg_temp.f5m_enviado(v_c, '5547900009952', 'ORÇ-99790', c_t, c_val);
    v_r := public.orcamento_vigia(c_t + interval '10 minutes');
    if v_r ->> 'modo' is distinct from 'desligado' or (v_r ->> 'novos')::integer is distinct from 0 then
      raise exception '15f: o vigia desligado (%)', v_r;
    end if;
    if exists (select 1 from public.orcamento_acompanhamentos a where a.service_order_id = v_o1)
       or exists (select 1 from public.retorno_saidas s where s.emissor = 'orcamento' and s.chave = '00009952') then
      raise exception '15g: o vigia desligado acompanhou ou agendou';
    end if;
    raise exception 'f5m_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5m_cenario' then
      raise;
    end if;
  end;

  -- ── 16. Os grants: orcamento_medidas só da service_role; a base dos aceites fechada; nenhuma função do orçamento aberta a
  --        anon ──
  for v_rec in
    select p.oid, p.proname, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('orcamento_medidas', '_orcamento_medidas_aceites')
  loop
    v_n_fun := v_n_fun + 1;
    if v_rec.prosecdef is not true or not exists (select 1 from unnest(v_rec.config) o where o ~ '^search_path=') then
      raise exception '16a: % não é SECURITY DEFINER com search_path', v_rec.nome;
    end if;
    if has_function_privilege('anon', v_rec.oid, 'execute') or has_function_privilege('authenticated', v_rec.oid, 'execute') then
      raise exception '16b: % aberta a anon ou authenticated', v_rec.nome;
    end if;
    if v_rec.proname = 'orcamento_medidas' and not has_function_privilege('service_role', v_rec.oid, 'execute') then
      raise exception '16c: orcamento_medidas sem o grant da service_role';
    end if;
  end loop;
  if v_n_fun is distinct from 2 then
    raise exception '16d: achei % das 2 funções novas', v_n_fun;
  end if;
  v_n_fun := 0;
  for v_rec in
    select p.oid, p.proname, p.oid::regprocedure::text as nome
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname ~ '^_?orcamento'
  loop
    v_n_fun := v_n_fun + 1;
    if has_function_privilege('anon', v_rec.oid, 'execute') then
      raise exception '16e: % aberta a anon', v_rec.nome;
    end if;
    if has_function_privilege('authenticated', v_rec.oid, 'execute')
       and v_rec.proname <> all (array['orcamento_validade_do_envio', 'orcamentos_para_agrupar']) then
      raise exception '16f: % aberta a authenticated', v_rec.nome;
    end if;
  end loop;
  if v_n_fun < 60 then
    raise exception '16g: a varredura das funções do orçamento achou só % (o filtro quebrou)', v_n_fun;
  end if;

  raise exception 'retorno_f5_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f5_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f5_medidas', true, '{}');
end
$medidas$;

select arquivo, ok, numeros from _bancada order by em;
rollback;

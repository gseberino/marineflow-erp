-- Retorno F5 (P8): o desfecho, as palavras do dono e o fechamento. Perdido com motivo (o ativo conclui, o encerrado fica
-- encerrado, sem 23514), as palavras só do dono (*segura N*, *solta N*, *segura/solta orcamentos*, *motivo N X*), o fechamento
-- (a linha fixa e o avisar, a do cartão, os encerramentos nas variantes, o "Fechado" que não saiu uma vez só, os vencidos sem
-- desfecho a qualquer número menos o do parceiro, desligado só com os vencidos, nenhum dígito de documento), o aviso da véspera
-- entregue, a carona sem a lista da P7 (o ramo undefined_function, como na F2), o "Mandei sozinho" com a saída do orçamento e o
-- *errado Z* com o nome do cliente (e a regressão do modelo da F2), e a amostra da auditoria. Roda só pela bancada (grupo 8,
-- F5_ONDA=4, F5_TESTES=retorno_f5_desfecho). Termina em ROLLBACK; cada cenário roda no seu sub-bloco, que se desfaz sozinho
-- (raise 'f5d_cenario'). Só confere as próprias linhas sintéticas: telefones inventados 55479000099xx (a chave sai do telefone:
-- 000099xx), nomes inventados (Ana, João, Pedro), documentos inventados (ORÇ-995xx), usuários de teste @teste.invalid. Nenhuma
-- mensagem real é lida; as mensagens são inventadas. Relógio: envio na ter 12/01/2027 10:00 com validade ter 19/01; fechamento
-- na qui 14/01 17:30 (amanhã = sex 15/01). A carona roda em 02/06/2026, antes de qualquer caso real (o 1º é de novembro), para
-- ver só o caso sintético; o id do dono vem de _comprovante_dono (só o id).
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f5d_cli(p_nome text, p_fone text) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, p_fone) returning id
$f$;

create or replace function pg_temp.f5d_msg(p_fone text, p_corpo text, p_em timestamptz, p_direcao text default 'inbound') returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real,
                                        occurred_at)
  values (p_direcao, p_fone, 'text', p_corpo, case when p_direcao = 'inbound' then 'received' else 'sent' end, '{"data": {}}'::jsonb,
          p_em, p_em)
  returning id
$f$;

create or replace function pg_temp.f5d_orc(p_cliente uuid, p_numero text, p_em timestamptz, p_quote text default 'draft',
                                           p_validade date default null) returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type)
    values (p_cliente, 'Unidade ' || left(md5(p_cliente::text || clock_timestamp()::text), 6), 'Motorhome') returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total, quote_validity_days, quote_validity_date)
  values (p_numero, p_cliente, v_v, 'draft', p_quote, 'repair', p_em - interval '2 days', p_em - interval '2 days', 100, 7, p_validade)
  returning id into v_id;
  return v_id;
end $f$;

-- O cliente que conversou, com o orçamento enviado pela tela na ter 12/01 10:00 (validade ter 19/01) e o acompanhamento.
create or replace function pg_temp.f5d_cad(p_nome text, p_fone text, p_numero text) returns uuid
language plpgsql as $f$
declare
  v_c uuid;
  v_os uuid;
  v_r jsonb;
begin
  v_c := pg_temp.f5d_cli(p_nome, p_fone);
  perform pg_temp.f5d_msg(p_fone, 'Bom dia, tudo bem?', timestamptz '2027-01-02 10:00-03');
  v_os := pg_temp.f5d_orc(v_c, p_numero, timestamptz '2027-01-12 10:00-03');
  update public.service_orders
     set quote_status = 'sent', orcamento_enviado_em = '2027-01-12 10:00-03', orcamento_enviado_via = 'tela',
         orcamento_enviado_chave = public._agenda_chave_telefone(p_fone), quote_validity_date = date '2027-01-19'
   where id = v_os;
  insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em, marcou)
  values (v_os, v_c, 'tela', public._agenda_chave_telefone(p_fone), true, '2027-01-12 10:00-03', true);
  v_r := public.orcamento_acompanhar(v_os, timestamptz '2027-01-12 10:01-03');
  if not coalesce((v_r ->> 'ok')::boolean, false) then
    raise exception 'f5d_cad: o acompanhamento de % não nasceu (%)', p_numero, v_r ->> 'motivo';
  end if;
  return (v_r ->> 'acompanhamento_id')::uuid;
end $f$;

create or replace function pg_temp.f5d_a(p_acomp uuid) returns public.orcamento_acompanhamentos
language sql as $f$
  select a from public.orcamento_acompanhamentos a where a.id = p_acomp
$f$;

create or replace function pg_temp.f5d_so(p_os uuid) returns text
language sql as $f$
  select so.quote_status || '/' || coalesce(so.motivo_perda, '-') || '/' || coalesce(so.motivo_perda_por, '-')
    from public.service_orders so where so.id = p_os
$f$;

create or replace function pg_temp.f5d_px(p_acomp uuid, p_passo text) returns text
language sql as $f$
  select p.estado || '/' || coalesce(p.motivo, '-') from public.orcamento_passos p where p.acompanhamento_id = p_acomp and p.passo = p_passo
$f$;

create or replace function pg_temp.f5d_ligar() returns void
language sql as $f$
  update public.retorno_config
     set modo = 'ligado', orcamento_modo = 'ligado', meio_dia_ligado = false, tipos_ligados = '{}', proximo_envio_em = null
   where id
$f$;

create or replace function pg_temp.f5d_nivel(p_nivel text) returns void
language sql as $f$
  update public.retorno_modelo_tipos set nivel = p_nivel where tipo in ('orc_lembrete', 'orc_vespera', 'orc_encerramento')
$f$;

-- Uma saída do orçamento já decidida, gravada à mão (o que o pegar e a decisão gravariam), no passo dela quando há.
create or replace function pg_temp.f5d_saida(p_acomp uuid, p_passo text, p_tipo text, p_estado text, p_em timestamptz,
                                             p_dados jsonb default '{}'::jsonb) returns uuid
language plpgsql as $f$
declare
  v_a public.orcamento_acompanhamentos;
  v_p public.orcamento_passos;
  v_fone text;
  v_id uuid;
begin
  select * into v_a from public.orcamento_acompanhamentos a where a.id = p_acomp;
  select * into v_p from public.orcamento_passos p where p.acompanhamento_id = p_acomp and p.passo = p_passo;
  select c.whatsapp into v_fone from public.clients c where c.id = v_a.client_id;
  insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, client_id, modo, estado, enviar_em,
                                     decidida_em, enviada_em, texto, dados, dedupe_key)
  values ('orcamento', p_tipo, 'retorno_orcamento', 'comercial', v_a.chave, v_fone, v_a.client_id, 'ligado', p_estado, p_em, p_em,
          case when p_estado = 'enviada' then p_em end, 'Oi! Texto de teste da saída do orçamento (F5 desfecho).',
          jsonb_build_object('acompanhamento_id', v_a.id, 'passo_id', v_p.id, 'os_id', v_a.service_order_id) || p_dados,
          'orcamento:' || v_a.id || ':' || p_passo || ':teste-f5d')
  returning id into v_id;
  update public.orcamento_passos p
     set estado = (case when p_estado in ('enviada', 'incerta') then 'enviado' when p_estado = 'sombra' then 'sombra' else 'pulado' end),
         motivo = (case when p_estado in ('enviada', 'incerta', 'sombra') then null else 'canal' end), saida_id = v_id
   where p.id = v_p.id;
  return v_id;
end $f$;

-- Um aceite já decidido (com_sinal), com o resultado dado.
create or replace function pg_temp.f5d_aceite(p_cliente uuid, p_fone text, p_os uuid, p_resultado jsonb) returns uuid
language plpgsql as $f$
declare
  v_m uuid;
  v_id uuid;
begin
  v_m := pg_temp.f5d_msg(p_fone, 'Pode fazer.', timestamptz '2027-01-14 09:00-03');
  insert into public.orcamento_aceites (whatsapp_message_id, client_id, chave, candidatos, service_order_id, sinal_lido, estado,
                                        total_visto, decidido_em, resultado)
  values (v_m, p_cliente, public._agenda_chave_telefone(p_fone), array[p_os], p_os, 'pode fazer', 'com_sinal', 100,
          timestamptz '2027-01-14 09:05-03', p_resultado)
  returning id into v_id;
  return v_id;
end $f$;

-- O caso vivo do cliente, aberto por uma mensagem inventada.
create or replace function pg_temp.f5d_caso(p_cliente uuid, p_fone text, p_em timestamptz) returns uuid
language plpgsql as $f$
declare
  v_m uuid;
  v_id uuid;
begin
  v_m := pg_temp.f5d_msg(p_fone, 'Oi, preciso de ajuda com o motorhome', p_em);
  insert into public.retorno_aberturas (chave, phone_normalized, papel, quem, client_id, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, modo)
  values (public._agenda_chave_telefone(p_fone), p_fone, 'cliente', '{}'::jsonb, p_cliente, v_m, v_m, p_em, p_em, p_em, p_em, 'recibo',
          'sombra')
  returning id into v_id;
  return v_id;
end $f$;

do $desfecho$
declare
  c_qui constant timestamptz := '2027-01-14 10:00-03';     -- qui
  c_fech constant timestamptz := '2027-01-14 17:30-03';    -- qui, o fechamento (amanhã = sex 15/01)
  c_carona constant timestamptz := '2026-06-02 10:00-03';  -- ter, antes de qualquer caso real
  c_dono constant uuid := 'b1600000-0000-4000-8000-0000000099d1';
  c_tec constant uuid := 'b1600000-0000-4000-8000-0000000099d2';
  c_legenda constant text := '(B fechou com outro · C desistiu · D preço · F prazo · G outro)';
  c_novas constant text[] := array['_orcamento_rotulo_da_saida', 'orcamento_marcar_perdido', 'orcamento_dito',
                                   'orcamento_resumo_fechamento', 'orcamento_avisados', 'orcamento_nao_saiu_avisados'];
  c_publicas constant text[] := array['orcamento_marcar_perdido', 'orcamento_dito', 'orcamento_resumo_fechamento', 'orcamento_avisados',
                                      'orcamento_nao_saiu_avisados'];
  v_ana uuid; v_joao uuid; v_pedro uuid; v_c uuid;
  v_os uuid; v_os2 uuid; v_os3 uuid;
  v_ac uuid; v_ac2 uuid; v_ac3 uuid; v_ac4 uuid;
  v_s1 uuid; v_s2 uuid; v_s3 uuid; v_s4 uuid;
  v_p1 uuid; v_p2 uuid;
  v_ab uuid;
  v_a1 uuid; v_a2 uuid; v_a3 uuid;
  v_dono uuid;
  v_fila uuid := 'b1600000-0000-4000-8000-0000000099df';
  v_r jsonb;
  v_r2 jsonb;
  v_a public.orcamento_acompanhamentos;
  v_ps public.orcamento_passos;
  v text;
  v_esperado text;
  v_n integer;
  v_rec record;
  v_n_fun integer := 0;
begin
  begin
  -- A configuração de cada rodada: o retorno e a cadência em sombra (a cadência exige a validade do envio), as réguas do K7,
  -- as chaves das dúvidas no padrão seguro (desligadas); os 3 tipos da cadência desligados.
  update public.retorno_config
     set modo = 'sombra', orcamento_modo = 'sombra', validade_envio_ligada = true, aceite_modo = 'desligado', aceite_audio = false,
         dados_nota_ligado = false, orcamento_segura = false, encerrar_marca_perdido = false, motivo_marca_aberto = false,
         envio_mao_modo = 'desligado', cadencia_hora = '10:00', cadencia_inicio = '09:00', cadencia_fim = '17:00',
         cadencia_lembrete_du = 2, cadencia_encerra_du = 1, cadencia_dono_carencia = interval '2 hours',
         cadencia_conversa = interval '365 days', parceiro_modo = 'desligado', tipos_ligados = '{}', proximo_envio_em = null,
         segura_tudo_ate = null, so_reativo = false, so_reativo_motivo = null, so_reativo_desde = null, carona_ligada = false,
         carona_em = null
   where id;
  perform pg_temp.f5d_nivel('desligado');
  update public.agenda_config set sabado_util = false where id;
  update public.agenda_disponibilidade d
     set substituida_em = now()
   where d.payee_id is null and d.situacao = 'indisponivel' and d.turno is null and d.substituida_em is null
     and d.periodo && daterange(date '2026-05-01', date '2027-03-01');
  insert into public.app_users (id, full_name, email, role, active) values
    (c_dono, 'TESTE F5 desfecho dono', 'teste-f5-desfecho-dono@teste.invalid', 'admin', true),
    (c_tec, 'TESTE F5 desfecho técnico', 'teste-f5-desfecho-tecnico@teste.invalid', 'technician', true);

  -- ── 1. Perdido, com motivo ──
  begin
    -- 1a. sent → rejected com motivo, motivo_perda_em e audit_log; o acompanhamento ativo conclui, e o que esperava cai.
    v_ac := pg_temp.f5d_cad('Ana Desfecho F5 Teste', '5547900009951', 'ORÇ-99551');
    v_a := pg_temp.f5d_a(v_ac);
    v_s1 := public._orcamento_agendar_passo((select p.id from public.orcamento_passos p where p.acompanhamento_id = v_ac and p.passo = 'lembrete'),
                                            '2027-01-13 09:00-03', 'sombra');
    v_r := public.orcamento_marcar_perdido(v_a.service_order_id, 'preco', 'tela', c_dono, '  cliente achou caro  ', c_qui);
    if (v_r ->> 'ok')::boolean is not true or v_r ->> 'numero' is distinct from 'ORÇ-99551' or v_r ->> 'motivo' is distinct from 'preco'
       or v_r -> 'antes' is distinct from 'null'::jsonb then
      raise exception '1a: o retorno (%)', v_r;
    end if;
    if pg_temp.f5d_so(v_a.service_order_id) is distinct from 'rejected/preco/tela'
       or (select so.motivo_perda_em from public.service_orders so where so.id = v_a.service_order_id) is distinct from c_qui
       or (select so.motivo_perda_nota from public.service_orders so where so.id = v_a.service_order_id) is distinct from 'cliente achou caro' then
      raise exception '1a: o orçamento (%)', pg_temp.f5d_so(v_a.service_order_id);
    end if;
    if not exists (select 1 from public.audit_log l
                    where l.table_name = 'service_orders' and l.record_id = v_a.service_order_id and l.changed_by = c_dono::text
                      and l.previous_value ->> 'quote_status' = 'sent' and l.new_value ->> 'motivo_perda' = 'preco') then
      raise exception '1a: sem o audit_log com o antes e o depois';
    end if;
    v_a := pg_temp.f5d_a(v_ac);
    if v_a.estado is distinct from 'concluido' or v_a.parou_por is distinct from 'status_mudou' then
      raise exception '1a: o acompanhamento (%, %)', v_a.estado, v_a.parou_por;
    end if;
    if pg_temp.f5d_px(v_ac, 'lembrete') is distinct from 'cancelado/-' or pg_temp.f5d_px(v_ac, 'vespera') is distinct from 'cancelado/-'
       or (select s.estado || '/' || s.motivo from public.retorno_saidas s where s.id = v_s1) is distinct from 'cancelada/status_mudou' then
      raise exception '1a: os passos e a saída (%, %)', pg_temp.f5d_px(v_ac, 'lembrete'), pg_temp.f5d_px(v_ac, 'vespera');
    end if;
    -- 1d. A troca de motivo num perdido: antes = o motivo de antes.
    v_r := public.orcamento_marcar_perdido(v_a.service_order_id, 'prazo', 'dono', c_dono, null, c_qui + interval '1 hour');
    if v_r ->> 'antes' is distinct from 'preco' or pg_temp.f5d_so(v_a.service_order_id) is distinct from 'rejected/prazo/dono'
       or (pg_temp.f5d_a(v_ac)).estado is distinct from 'concluido' then
      raise exception '1d: a troca de motivo (%)', v_r;
    end if;
    raise exception 'f5d_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5d_cenario' then
      raise;
    end if;
  end;
  begin
    -- 1b. O acompanhamento encerrado (enviado, ou sem mensagem) fica encerrado: nenhum 23514.
    v_ac := pg_temp.f5d_cad('João Desfecho F5 Teste', '5547900009952', 'ORÇ-99552');
    update public.orcamento_acompanhamentos a set estado = 'encerrado', encerramento = 'enviado', desfecho_proposto = 'sumiu' where a.id = v_ac;
    v_r := public.orcamento_marcar_perdido((pg_temp.f5d_a(v_ac)).service_order_id, 'sumiu', 'cadencia', null, null, c_qui);
    v_a := pg_temp.f5d_a(v_ac);
    if (v_r ->> 'ok')::boolean is not true or v_a.estado is distinct from 'encerrado' or v_a.encerramento is distinct from 'enviado'
       or pg_temp.f5d_so(v_a.service_order_id) is distinct from 'rejected/sumiu/cadencia' then
      raise exception '1b: o encerrado enviado (%, %)', v_r, v_a.estado;
    end if;
    if not exists (select 1 from public.audit_log l where l.record_id = v_a.service_order_id and l.changed_by = 'retorno-f5') then
      raise exception '1b: sem autor, o audit_log leva retorno-f5';
    end if;
    v_ac2 := pg_temp.f5d_cad('Pedro Desfecho F5 Teste', '5547900009953', 'ORÇ-99553');
    update public.orcamento_acompanhamentos a set estado = 'encerrado', encerramento = 'sem_mensagem', desfecho_proposto = 'sumiu' where a.id = v_ac2;
    v_r := public.orcamento_marcar_perdido((pg_temp.f5d_a(v_ac2)).service_order_id, 'desistiu', 'dono', c_dono, null, c_qui);
    if (v_r ->> 'ok')::boolean is not true or (pg_temp.f5d_a(v_ac2)).encerramento is distinct from 'sem_mensagem'
       or (pg_temp.f5d_a(v_ac2)).estado is distinct from 'encerrado' then
      raise exception '1b: o encerrado sem mensagem (%)', v_r;
    end if;
    raise exception 'f5d_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5d_cenario' then
      raise;
    end if;
  end;
  begin
    -- 1c. Motivo fora da lista, o sem_motivo_antigo (só a migration de dado), quem marca fora da lista e a OS convertida.
    v_ana := pg_temp.f5d_cli('Ana Desfecho F5 Teste', '5547900009954');
    v_os := pg_temp.f5d_orc(v_ana, 'ORÇ-99554', c_qui, 'sent');
    v_r := public.orcamento_marcar_perdido(v_os, 'caro', 'tela', null, null, c_qui);
    v_r2 := public.orcamento_marcar_perdido(v_os, 'sem_motivo_antigo', 'tela', null, null, c_qui);
    if (v_r ->> 'ok')::boolean is not false or v_r ->> 'motivo' is distinct from 'motivo'
       or (v_r2 ->> 'ok')::boolean is not false or v_r2 ->> 'motivo' is distinct from 'motivo' then
      raise exception '1c: motivo fora da lista (%, %)', v_r, v_r2;
    end if;
    v_r := public.orcamento_marcar_perdido(v_os, 'preco', 'migracao', null, null, c_qui);
    if (v_r ->> 'ok')::boolean is not false or v_r ->> 'motivo' is distinct from 'por' then
      raise exception '1c: quem marca fora da lista (%)', v_r;
    end if;
    update public.service_orders so
       set status = 'open', converted_to_os_at = c_qui, service_order_number = 'OS-99554', quote_status = 'approved'
     where so.id = v_os;
    v_r := public.orcamento_marcar_perdido(v_os, 'preco', 'tela', null, null, c_qui);
    if (v_r ->> 'ok')::boolean is not false or v_r ->> 'motivo' is distinct from 'convertida' then
      raise exception '1c: a OS convertida (%)', v_r;
    end if;
    if pg_temp.f5d_so(v_os) is distinct from 'approved/-/-' then
      raise exception '1c: a recusa mexeu na ordem (%)', pg_temp.f5d_so(v_os);
    end if;
    raise exception 'f5d_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5d_cenario' then
      raise;
    end if;
  end;

  -- ── 2. As palavras só do dono ──
  v_r := public.orcamento_dito('{"comando": "segura_todos"}'::jsonb, c_tec, c_qui);
  v_r2 := public.orcamento_dito('{"comando": "segura_todos"}'::jsonb, null, c_qui);
  if v_r ->> 'motivo' is distinct from 'nao_e_o_dono' or (v_r ->> 'ok')::boolean is not false
     or v_r2 ->> 'motivo' is distinct from 'nao_e_o_dono'
     or (select c.orcamento_segura from public.retorno_config c where c.id) is not false then
    raise exception '2: quem não é o dono (%, %)', v_r, v_r2;
  end if;

  -- ── 3. *segura N* e *solta N* ──
  begin
    v_ac := pg_temp.f5d_cad('Ana Desfecho F5 Teste', '5547900009955', 'ORÇ-99555');
    v_s1 := public._orcamento_agendar_passo((select p.id from public.orcamento_passos p where p.acompanhamento_id = v_ac and p.passo = 'lembrete'),
                                            '2027-01-13 09:00-03', 'sombra');
    update public.orcamento_passos p set avisado_em = '2027-01-13 11:00-03', aviso_fila = v_fila
     where p.acompanhamento_id = v_ac and p.passo = 'vespera';
    v_r := public.orcamento_dito('{"comando": "segura", "numero": 99555}'::jsonb, c_dono, '2027-01-13 12:00-03');
    if v_r ->> 'texto' is distinct from 'Segurei os lembretes do ORÇ-99555 (Ana). Para voltar: *solta 99555*.' then
      raise exception '3a: a resposta do segura (%)', v_r;
    end if;
    v_a := pg_temp.f5d_a(v_ac);
    if v_a.estado is distinct from 'parado' or v_a.parou_por is distinct from 'segurado'
       or (select s.estado || '/' || s.motivo from public.retorno_saidas s where s.id = v_s1) is distinct from 'cancelada/segurado'
       or pg_temp.f5d_px(v_ac, 'lembrete') is distinct from 'cancelado/segurado'
       or pg_temp.f5d_px(v_ac, 'vespera') is distinct from 'cancelado/segurado' then
      raise exception '3a: o segura (%, %, %)', v_a.estado, pg_temp.f5d_px(v_ac, 'lembrete'), pg_temp.f5d_px(v_ac, 'vespera');
    end if;
    -- sex 15/01: o lembrete (qui 14/01) já passou e fica pulado/segurado; a véspera e o encerramento voltam, sem o aviso de antes.
    v_r := public.orcamento_dito('{"comando": "solta", "numero": "99555"}'::jsonb, c_dono, '2027-01-15 09:00-03');
    if v_r ->> 'texto' is distinct from 'Os lembretes do ORÇ-99555 voltaram. Próximo: véspera, seg 18/01.' then
      raise exception '3b: a resposta do solta (%)', v_r;
    end if;
    select * into v_ps from public.orcamento_passos p where p.acompanhamento_id = v_ac and p.passo = 'vespera';
    if (pg_temp.f5d_a(v_ac)).estado is distinct from 'ativo' or (pg_temp.f5d_a(v_ac)).parou_por is not null
       or pg_temp.f5d_px(v_ac, 'lembrete') is distinct from 'pulado/segurado' or pg_temp.f5d_px(v_ac, 'vespera') is distinct from 'previsto/-'
       or pg_temp.f5d_px(v_ac, 'encerramento') is distinct from 'previsto/-' or v_ps.avisado_em is not null or v_ps.aviso_fila is not null then
      raise exception '3b: o solta (%, %)', pg_temp.f5d_px(v_ac, 'lembrete'), pg_temp.f5d_px(v_ac, 'vespera');
    end if;
    -- O solta de quem não está segurado; o segura de quem não tem lembrete.
    v_r := public.orcamento_dito('{"comando": "solta", "numero": 99555}'::jsonb, c_dono, '2027-01-15 09:05-03');
    if v_r ->> 'texto' is distinct from 'Os lembretes do ORÇ-99555 não estavam segurados.' then
      raise exception '3c: solta sem segura (%)', v_r;
    end if;
    v_joao := pg_temp.f5d_cli('João Desfecho F5 Teste', '5547900009956');
    perform pg_temp.f5d_orc(v_joao, 'ORÇ-99556', c_qui, 'sent');
    v_r := public.orcamento_dito('{"comando": "segura", "numero": 99556}'::jsonb, c_dono, c_qui);
    if v_r ->> 'texto' is distinct from 'O ORÇ-99556 não tem lembrete previsto.' then
      raise exception '3d: segura sem acompanhamento (%)', v_r;
    end if;
    raise exception 'f5d_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5d_cenario' then
      raise;
    end if;
  end;

  -- ── 4. *segura orcamentos* e *solta orcamentos* (where id) ──
  begin
    v_r := public.orcamento_dito('{"comando": "segura_todos"}'::jsonb, c_dono, c_qui);
    if v_r ->> 'texto' is distinct from 'Segurei todos os lembretes de orçamento. Para voltar: *solta orcamentos*.'
       or (select c.orcamento_segura from public.retorno_config c where c.id) is not true then
      raise exception '4a: segura orcamentos (%)', v_r;
    end if;
    v_r := public.orcamento_dito('{"comando": "solta_todos"}'::jsonb, c_dono, c_qui);
    if v_r ->> 'texto' is distinct from 'Os lembretes de orçamento voltaram.'
       or (select c.orcamento_segura from public.retorno_config c where c.id) is not false then
      raise exception '4b: solta orcamentos (%)', v_r;
    end if;
    raise exception 'f5d_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5d_cenario' then
      raise;
    end if;
  end;

  -- ── 5. *motivo N X* ──
  begin
    -- 5a. O perdido troca o motivo, achado por ORÇ-nnnnn.
    v_ana := pg_temp.f5d_cli('Ana Desfecho F5 Teste', '5547900009957');
    v_os := pg_temp.f5d_orc(v_ana, 'ORÇ-99557', c_qui, 'sent');
    perform public.orcamento_marcar_perdido(v_os, 'sumiu', 'tela', null, null, c_qui);
    v_r := public.orcamento_dito('{"comando": "motivo", "numero": 99557, "letra": "B"}'::jsonb, c_dono, c_qui + interval '1 hour');
    if v_r ->> 'texto' is distinct from 'ORÇ-99557 (Ana, R$ 100) marcado como perdido: fechou com outro. Para reabrir, use a tela.'
       or pg_temp.f5d_so(v_os) is distinct from 'rejected/fechou_com_outro/dono' then
      raise exception '5a: motivo B num perdido (%)', v_r;
    end if;
    -- A palavra no lugar da letra.
    v_r := public.orcamento_dito('{"comando": "motivo", "numero": 99557, "letra": "preco"}'::jsonb, c_dono, c_qui + interval '2 hours');
    if pg_temp.f5d_so(v_os) is distinct from 'rejected/preco/dono' or strpos(v_r ->> 'texto', 'perdido: preço.') = 0 then
      raise exception '5b: motivo preco (%)', v_r;
    end if;
    v_r := public.orcamento_dito('{"comando": "motivo", "numero": 99557, "letra": "outra empresa"}'::jsonb, c_dono, c_qui + interval '3 hours');
    if pg_temp.f5d_so(v_os) is distinct from 'rejected/fechou_com_outro/dono' then
      raise exception '5b: motivo outra empresa (%)', v_r;
    end if;
    -- A letra E não é motivo (nada muda).
    v_r := public.orcamento_dito('{"comando": "motivo", "numero": 99557, "letra": "E"}'::jsonb, c_dono, c_qui + interval '4 hours');
    if (v_r ->> 'ok')::boolean is not false or pg_temp.f5d_so(v_os) is distinct from 'rejected/fechou_com_outro/dono' then
      raise exception '5c: a letra E (%)', v_r;
    end if;
    -- 5d. O aberto, com motivo_marca_aberto falso (o padrão): a frase fixa, e nada muda; com verdadeiro, marca.
    v_joao := pg_temp.f5d_cli('João Desfecho F5 Teste', '5547900009958');
    v_os2 := pg_temp.f5d_orc(v_joao, 'ORÇ-99558', c_qui, 'sent');
    v_r := public.orcamento_dito('{"comando": "motivo", "numero": 99558, "letra": "B"}'::jsonb, c_dono, c_qui);
    if v_r ->> 'texto' is distinct from
         'O ORÇ-99558 ainda está aberto: para marcar como perdido, use a tela ou o assistente. Depois disso, *motivo 99558 B* troca o motivo.'
       or pg_temp.f5d_so(v_os2) is distinct from 'sent/-/-' then
      raise exception '5d: o aberto sem a chave (%)', v_r;
    end if;
    update public.retorno_config set motivo_marca_aberto = true where id;
    v_r := public.orcamento_dito('{"comando": "motivo", "numero": 99558, "letra": "D"}'::jsonb, c_dono, c_qui);
    if pg_temp.f5d_so(v_os2) is distinct from 'rejected/preco/dono' then
      raise exception '5d: o aberto com a chave (%)', v_r;
    end if;
    -- 5e. O aberto com o acompanhamento encerrado (o "Encerrado hoje sem resposta") e a chave: marca, sem "Não consegui agora".
    v_ac := pg_temp.f5d_cad('Pedro Desfecho F5 Teste', '5547900009959', 'ORÇ-99559');
    update public.orcamento_acompanhamentos a set estado = 'encerrado', encerramento = 'enviado', desfecho_proposto = 'sumiu' where a.id = v_ac;
    v_r := public.orcamento_dito('{"comando": "motivo", "numero": 99559, "letra": "A"}'::jsonb, c_dono, c_qui);
    if (v_r ->> 'ok')::boolean is not true or strpos(coalesce(v_r ->> 'texto', ''), 'Não consegui') > 0
       or pg_temp.f5d_so((pg_temp.f5d_a(v_ac)).service_order_id) is distinct from 'rejected/sumiu/dono'
       or (pg_temp.f5d_a(v_ac)).estado is distinct from 'encerrado' then
      raise exception '5e: o aberto com o encerrado (%)', v_r;
    end if;
    -- 5f. O número que não existe; 5g. a ordem já convertida.
    v_r := public.orcamento_dito('{"comando": "motivo", "numero": 99499, "letra": "B"}'::jsonb, c_dono, c_qui);
    if v_r ->> 'texto' is distinct from 'Não achei o ORÇ-99499.' then
      raise exception '5f: número que não existe (%)', v_r;
    end if;
    update public.service_orders so
       set status = 'open', converted_to_os_at = c_qui, service_order_number = 'OS-99558', quote_status = 'approved'
     where so.id = v_os2;
    v_r := public.orcamento_dito('{"comando": "motivo", "numero": 99558, "letra": "B"}'::jsonb, c_dono, c_qui);
    if v_r ->> 'texto' is distinct from 'O ORÇ-99558 já virou OS-99558: não há o que marcar.' then
      raise exception '5g: a ordem convertida (%)', v_r;
    end if;
    raise exception 'f5d_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5d_cenario' then
      raise;
    end if;
  end;

  -- ── 6. O fechamento ──
  -- 6a. Nada a dizer.
  v_r := public.orcamento_resumo_fechamento(c_fech);
  -- nao_saiu: o aviso do "Fechado" que não saiu, devolvido sem gravar (revisão das ondas 4 a 9; spec seção 15, P8.1).
  if v_r is distinct from '{"fixas": [], "linhas": [], "avisar": [], "nao_saiu": []}'::jsonb then
    raise exception '6a: sem nada a dizer (%)', v_r;
  end if;
  begin
    -- 6b. A linha fixa: amanhã sai sozinho (o tipo promovido, o acompanhamento ligado), com o passo no avisar.
    perform pg_temp.f5d_ligar();
    perform pg_temp.f5d_nivel('sozinho');
    v_ac := pg_temp.f5d_cad('Ana Desfecho F5 Teste', '5547900009961', 'ORÇ-99561');
    update public.orcamento_passos p set dia = date '2027-01-15', ate = date '2027-01-15' where p.acompanhamento_id = v_ac and p.passo = 'lembrete';
    v_p1 := (select p.id from public.orcamento_passos p where p.acompanhamento_id = v_ac and p.passo = 'lembrete');
    v_r := public.orcamento_resumo_fechamento(c_fech);
    if v_r -> 'fixas' is distinct from jsonb_build_array('Orçamentos: amanhã sai sozinho o lembrete do ORÇ-99561 (Ana) · *segura 99561*')
       or v_r -> 'avisar' is distinct from jsonb_build_array(v_p1) or v_r -> 'linhas' is distinct from '[]'::jsonb then
      raise exception '6b: a linha fixa (%)', v_r;
    end if;
    -- Com 4: os 3 primeiros na fixa ("e mais 1", fora do avisar); o 4º vai à linha do *sim*.
    v_ac2 := pg_temp.f5d_cad('João Desfecho F5 Teste', '5547900009962', 'ORÇ-99562');
    v_ac3 := pg_temp.f5d_cad('Pedro Desfecho F5 Teste', '5547900009963', 'ORÇ-99563');
    v_ac4 := pg_temp.f5d_cad('Ana Desfecho F5 Teste', '5547900009964', 'ORÇ-99564');
    update public.orcamento_passos p set dia = date '2027-01-15', ate = date '2027-01-15'
     where p.acompanhamento_id in (v_ac2, v_ac3, v_ac4) and p.passo = 'lembrete';
    v_r := public.orcamento_resumo_fechamento(c_fech);
    if jsonb_array_length(v_r -> 'avisar') is distinct from 3 or (v_r -> 'fixas' ->> 0 ~ ' e mais 1$') is not true
       or (v_r -> 'fixas' ->> 0 ~ '^Orçamentos: amanhã saem sozinhos o lembrete do ORÇ-99561 \(Ana\)') is not true
       or strpos(v_r -> 'fixas' ->> 0, 'ORÇ-99564') > 0
       or v_r -> 'linhas' is distinct from jsonb_build_array('Orçamentos: amanhã 1 lembrete espera o seu *sim <PIN>* no *retorno*') then
      raise exception '6b: a fixa com 4 (%)', v_r;
    end if;
    -- Com *segura orcamentos*, nada anda amanhã.
    update public.retorno_config set orcamento_segura = true where id;
    v_r := public.orcamento_resumo_fechamento(c_fech);
    if v_r -> 'fixas' is distinct from '[]'::jsonb or v_r -> 'avisar' is distinct from '[]'::jsonb then
      raise exception '6b: com segura orcamentos (%)', v_r;
    end if;
    raise exception 'f5d_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5d_cenario' then
      raise;
    end if;
  end;
  begin
    -- 6c. A linha do *sim*: o tipo no cartão amanhã e o passo de hoje que ainda espera, dentro do prazo.
    perform pg_temp.f5d_ligar();
    perform pg_temp.f5d_nivel('cartao');
    v_ac := pg_temp.f5d_cad('Ana Desfecho F5 Teste', '5547900009965', 'ORÇ-99565');
    update public.orcamento_passos p set dia = date '2027-01-15', ate = date '2027-01-15' where p.acompanhamento_id = v_ac and p.passo = 'lembrete';
    v_ac2 := pg_temp.f5d_cad('João Desfecho F5 Teste', '5547900009966', 'ORÇ-99566');
    update public.orcamento_passos p set estado = 'aguarda_sim' where p.acompanhamento_id = v_ac2 and p.passo = 'lembrete';
    v_r := public.orcamento_resumo_fechamento(c_fech);
    if v_r -> 'linhas' is distinct from jsonb_build_array(
         'Orçamentos: amanhã 1 lembrete espera o seu *sim <PIN>* no *retorno* · 1 de hoje ainda espera, até sex 15/01')
       or v_r -> 'fixas' is distinct from '[]'::jsonb then
      raise exception '6c: a linha do sim (%)', v_r;
    end if;
    raise exception 'f5d_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5d_cenario' then
      raise;
    end if;
  end;
  begin
    -- 6d. Os encerramentos de hoje: perdido pela cadência, sem resposta e sem mensagem, nas duas variantes de motivo_marca_aberto.
    perform pg_temp.f5d_ligar();
    v_ac := pg_temp.f5d_cad('Pedro Desfecho F5 Teste', '5547900009971', 'ORÇ-99571');
    perform pg_temp.f5d_saida(v_ac, 'encerramento', 'orc_encerramento', 'enviada', c_qui);
    update public.orcamento_acompanhamentos a set estado = 'encerrado', encerramento = 'enviado', desfecho_proposto = 'sumiu' where a.id = v_ac;
    perform public.orcamento_marcar_perdido((pg_temp.f5d_a(v_ac)).service_order_id, 'sumiu', 'cadencia', null, null, c_qui);
    v_ac2 := pg_temp.f5d_cad('João Desfecho F5 Teste', '5547900009972', 'ORÇ-99572');
    perform pg_temp.f5d_saida(v_ac2, 'encerramento', 'orc_encerramento', 'enviada', c_qui + interval '1 minute');
    update public.orcamento_acompanhamentos a set estado = 'encerrado', encerramento = 'enviado', desfecho_proposto = 'sumiu' where a.id = v_ac2;
    v_ac3 := pg_temp.f5d_cad('Ana Desfecho F5 Teste', '5547900009973', 'ORÇ-99573');
    update public.orcamento_passos p set estado = 'pulado', motivo = 'sem_sim', ate = date '2027-01-14'
     where p.acompanhamento_id = v_ac3 and p.passo = 'encerramento';
    update public.orcamento_acompanhamentos a set estado = 'encerrado', encerramento = 'sem_mensagem', desfecho_proposto = 'sumiu' where a.id = v_ac3;
    v_r := public.orcamento_resumo_fechamento(c_fech);
    v_esperado := jsonb_build_array(
      'Encerrado hoje: ORÇ-99571 (Pedro), perdido (sumiu) · troque com *motivo 99571 B* ' || c_legenda,
      'Encerrado hoje sem resposta: ORÇ-99572 (João) · para marcar como perdido, use a tela ou o assistente',
      'Encerrado sem mensagem (não saiu: sem o seu sim): ORÇ-99573 (Ana) · para marcar como perdido, use a tela ou o assistente')::text;
    if (v_r -> 'linhas')::text is distinct from v_esperado then
      raise exception '6d: os encerramentos (%)', v_r -> 'linhas';
    end if;
    update public.retorno_config set motivo_marca_aberto = true where id;
    v_r := public.orcamento_resumo_fechamento(c_fech);
    if v_r -> 'linhas' ->> 1 is distinct from 'Encerrado hoje sem resposta: ORÇ-99572 (João) · *motivo 99572 A* marca como perdido (sumiu)'
       or v_r -> 'linhas' ->> 2 is distinct from
          'Encerrado sem mensagem (não saiu: sem o seu sim): ORÇ-99573 (Ana) · *motivo 99573 A* marca como perdido (sumiu)' then
      raise exception '6d: com motivo_marca_aberto (%)', v_r -> 'linhas';
    end if;
    -- O encerramento de ontem (antes do fechamento anterior) não aparece.
    update public.retorno_saidas s set enviada_em = c_qui - interval '1 day', decidida_em = c_qui - interval '1 day'
     where s.dedupe_key = 'orcamento:' || v_ac2 || ':encerramento:teste-f5d';
    v_r := public.orcamento_resumo_fechamento(c_fech);
    if jsonb_array_length(v_r -> 'linhas') is distinct from 2 or strpos((v_r -> 'linhas')::text, 'ORÇ-99572') > 0 then
      raise exception '6d: o encerramento de ontem (%)', v_r -> 'linhas';
    end if;
    raise exception 'f5d_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5d_cenario' then
      raise;
    end if;
  end;
  begin
    -- 6e. O "Fechado" (ou o pedido de dados) que não saiu ou pode não ter saído: a leitura não grava nada (revisão das ondas 4
    --     a 9, achados banco-2, seguranca-1 e edge-fechamento: a tarde pode descartar a linha); o aviso volta até a tarde com a
    --     linha ir à fila (orcamento_nao_saiu_avisados, com a linha da fila), e só então sai da lista do cartão, uma vez só.
    v_ana := pg_temp.f5d_cli('Ana Desfecho F5 Teste', '5547900009974');
    v_os := pg_temp.f5d_orc(v_ana, 'ORÇ-99574', c_qui, 'awaiting_deposit');
    v_a1 := pg_temp.f5d_aceite(v_ana, '5547900009974', v_os, '{"saida_nao_saiu": "canal", "saida_nao_saiu_tipo": "orc_fechado"}');
    v_joao := pg_temp.f5d_cli('João Desfecho F5 Teste', '5547900009975');
    v_os2 := pg_temp.f5d_orc(v_joao, 'ORÇ-99575', c_qui, 'awaiting_deposit');
    v_a2 := pg_temp.f5d_aceite(v_joao, '5547900009975', v_os2, '{"saida_nao_saiu": "incerta", "saida_nao_saiu_tipo": "orc_fechado"}');
    v_pedro := pg_temp.f5d_cli('Pedro Desfecho F5 Teste', '5547900009976');
    v_os3 := pg_temp.f5d_orc(v_pedro, 'ORÇ-99576', c_qui, 'awaiting_deposit');
    v_a3 := pg_temp.f5d_aceite(v_pedro, '5547900009976', v_os3, '{"saida_nao_saiu": "validador", "saida_nao_saiu_tipo": "orc_dados_nota"}');
    update public.retorno_config set aceite_modo = 'cartao' where id;
    if (select count(*) from public._orcamento_cartao_aceites(c_fech) x where x.aceite_id in (v_a1, v_a2, v_a3)) is distinct from 3::bigint then
      raise exception '6e: os três avisos não estavam na lista do cartão';
    end if;
    v_r := public.orcamento_resumo_fechamento(c_fech);
    if v_r -> 'linhas' is distinct from jsonb_build_array(
         'O ''Fechado'' do ORÇ-99574 (Ana) não saiu: responda você',
         'O ''Fechado'' do ORÇ-99575 (João) pode não ter saído: confira a conversa',
         'O pedido de dados da nota do ORÇ-99576 (Pedro) não saiu: responda você') then
      raise exception '6e: os avisos (%)', v_r -> 'linhas';
    end if;
    if v_r -> 'nao_saiu' is distinct from jsonb_build_array(
         jsonb_build_object('aceite', v_a1, 'linha', 'O ''Fechado'' do ORÇ-99574 (Ana) não saiu: responda você'),
         jsonb_build_object('aceite', v_a2, 'linha', 'O ''Fechado'' do ORÇ-99575 (João) pode não ter saído: confira a conversa'),
         jsonb_build_object('aceite', v_a3, 'linha', 'O pedido de dados da nota do ORÇ-99576 (Pedro) não saiu: responda você')) then
      raise exception '6e: o nao_saiu com o aceite e a linha exata (%)', v_r -> 'nao_saiu';
    end if;
    if exists (select 1 from public.orcamento_aceites a where a.id in (v_a1, v_a2, v_a3) and a.resultado ? 'nao_saiu_fechado_em')
       or (select count(*) from public._orcamento_cartao_aceites(c_fech) x where x.aceite_id in (v_a1, v_a2, v_a3)) is distinct from 3::bigint then
      raise exception '6e: a leitura gravou a marca (o aviso saiu do cartão sem ir ao dono)';
    end if;
    -- A tarde que não levou a linha (a revisão, o corte das extras, a tentativa que falhou): o aviso volta no fechamento seguinte.
    v_r := public.orcamento_resumo_fechamento(c_fech + interval '1 day');
    if jsonb_array_length(v_r -> 'nao_saiu') is distinct from 3 or jsonb_array_length(v_r -> 'linhas') is distinct from 3 then
      raise exception '6e: o aviso não voltou no fechamento seguinte (%)', v_r;
    end if;
    -- Sem a linha da fila, nada; com ela, os três saem da lista do cartão, com a hora e a fila; de novo, nada.
    if public.orcamento_nao_saiu_avisados(array[v_a1, v_a2, v_a3], null, c_fech + interval '1 day') is distinct from 0
       or exists (select 1 from public.orcamento_aceites a where a.id in (v_a1, v_a2, v_a3) and a.resultado ? 'nao_saiu_fechado_em') then
      raise exception '6e: sem a linha da fila gravou a marca';
    end if;
    if public.orcamento_nao_saiu_avisados(array[v_a1, v_a2, v_a3], v_fila, c_fech + interval '1 day') is distinct from 3 then
      raise exception '6e: o aviso mostrado não marcou os três';
    end if;
    if (select count(*) from public.orcamento_aceites a
         where a.id in (v_a1, v_a2, v_a3) and (a.resultado ->> 'nao_saiu_fechado_em')::timestamptz = c_fech + interval '1 day'
           and a.resultado ->> 'nao_saiu_fila' = v_fila::text) is distinct from 3::bigint
       or exists (select 1 from public._orcamento_cartao_aceites(c_fech + interval '1 day') x where x.aceite_id in (v_a1, v_a2, v_a3)) then
      raise exception '6e: a marca nao_saiu_fechado_em';
    end if;
    if public.orcamento_nao_saiu_avisados(array[v_a1], v_fila, c_fech + interval '2 days') is distinct from 0 then
      raise exception '6e: marcou duas vezes';
    end if;
    v_r := public.orcamento_resumo_fechamento(c_fech + interval '1 day');
    if v_r -> 'linhas' is distinct from '[]'::jsonb or v_r -> 'nao_saiu' is distinct from '[]'::jsonb then
      raise exception '6e: o aviso voltou depois de mostrado (%)', v_r;
    end if;
    raise exception 'f5d_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5d_cenario' then
      raise;
    end if;
  end;
  begin
    -- 6g. O encerramento de um dia de revisão (revisão das ondas 4 a 9, achado seguranca-1): a revisão não mostra as linhas do
    --     orçamento (P10.2) e não conta como fechamento; o encerramento de qua 13/01 (dia da revisão da semana) sai no fechamento
    --     de qui 14/01, com o dia no lugar do "hoje". Sem tarde de fechamento em resumo_tarde nos 10 dias, a régua de sempre
    --     (o fechamento anterior, qua 17:30), e ele não aparece.
    perform pg_temp.f5d_ligar();
    v_ac := pg_temp.f5d_cad('João Desfecho F5 Teste', '5547900009981', 'ORÇ-99583');
    perform pg_temp.f5d_saida(v_ac, 'encerramento', 'orc_encerramento', 'enviada', c_qui - interval '1 day');
    update public.orcamento_acompanhamentos a set estado = 'encerrado', encerramento = 'enviado', desfecho_proposto = 'sumiu' where a.id = v_ac;
    v_r := public.orcamento_resumo_fechamento(c_fech);
    if strpos((v_r -> 'linhas')::text, 'ORÇ-99583') > 0 then
      raise exception '6g: sem a tarde de fechamento gravada, o encerramento de ontem apareceu (%)', v_r -> 'linhas';
    end if;
    insert into public.resumo_tarde (dia, phone_normalized, turno, modo, formato, texto, calado, enviado)
    values (date '2027-01-12', '5547900009982', 'fechamento', 'novo', 'ligado', 'Fechamento de teste (F5 desfecho)', false, true),
           (date '2027-01-13', '5547900009982', 'revisao_semana', 'novo', 'ligado', 'Revisão de teste (F5 desfecho)', false, true);
    v_r := public.orcamento_resumo_fechamento(c_fech);
    if v_r -> 'linhas' is distinct from jsonb_build_array(
         'Encerrado qua 13/01 sem resposta: ORÇ-99583 (João) · para marcar como perdido, use a tela ou o assistente') then
      raise exception '6g: o encerramento do dia da revisão (%)', v_r -> 'linhas';
    end if;
    raise exception 'f5d_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5d_cenario' then
      raise;
    end if;
  end;
  begin
    -- 6f. Os enviados vencidos sem desfecho: a outro número e de cliente sem telefone contam; o do parceiro, o perdido, o
    --     aprovado, o que ainda vale e o que tem acompanhamento ativo não.
    v_ana := pg_temp.f5d_cli('Ana Desfecho F5 Teste', '5547900009977');
    v_os := pg_temp.f5d_orc(v_ana, 'ORÇ-99577', c_qui - interval '12 days', 'sent', date '2027-01-05');
    insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em)
    values (v_os, v_ana, 'tela', '00009999', false, '2027-01-02 10:00-03');
    v_joao := pg_temp.f5d_cli('João Desfecho F5 Teste', null);
    v_os2 := pg_temp.f5d_orc(v_joao, 'ORÇ-99578', c_qui - interval '12 days', 'draft', date '2027-01-05');
    insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em)
    values (v_os2, v_joao, 'aparelho', '00009998', false, '2027-01-02 11:00-03');
    v_pedro := pg_temp.f5d_cli('Pedro Desfecho F5 Teste', '5547900009979');
    v_os3 := pg_temp.f5d_orc(v_pedro, 'ORÇ-99579', c_qui - interval '12 days', 'sent', date '2027-01-05');
    insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em)
    values (v_os3, v_pedro, 'tela', '00009979', true, '2027-01-02 12:00-03');
    update public.retorno_config set clientes_parceiros = clientes_parceiros || v_pedro where id;
    -- os que não contam
    v_c := pg_temp.f5d_cli('Ana Desfecho F5 Teste', '5547900009980');
    for v_rec in select * from (values ('ORÇ-99580', 'rejected', date '2027-01-05'), ('ORÇ-99581', 'approved', date '2027-01-05'),
                                       ('ORÇ-99582', 'sent', date '2027-01-20')) as x(numero, quote, validade) loop
      -- F5 (P9): o perdido nasce com motivo; com o CHECK service_orders_rejeitado_tem_motivo no banco, o insert direto em
      -- rejected sem motivo daria 23514. Continua sendo um orçamento perdido, que a linha 4 não conta.
      v_s1 := pg_temp.f5d_orc(v_c, v_rec.numero, c_qui - interval '12 days',
                              (case when v_rec.quote = 'rejected' then 'sent' else v_rec.quote end), v_rec.validade);
      if v_rec.quote = 'rejected' then
        update public.service_orders set quote_status = 'rejected', motivo_perda = 'preco', motivo_perda_por = 'tela' where id = v_s1;
      end if;
      insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em)
      values (v_s1, v_c, 'tela', '00009980', true, '2027-01-02 13:00-03');
    end loop;
    v_ac := pg_temp.f5d_cad('Pedro Desfecho F5 Teste', '5547900009969', 'ORÇ-99569');
    update public.service_orders so set quote_validity_date = date '2027-01-05' where so.id = (pg_temp.f5d_a(v_ac)).service_order_id;
    v_r := public.orcamento_resumo_fechamento(c_fech);
    if v_r -> 'linhas' is distinct from jsonb_build_array(
         'Enviados vencidos sem desfecho: 2 (ORÇ-99577, ORÇ-99578) · para marcar como perdido, use a tela ou o assistente') then
      raise exception '6f: os vencidos sem desfecho (%)', v_r -> 'linhas';
    end if;
    update public.retorno_config set motivo_marca_aberto = true where id;
    v_r := public.orcamento_resumo_fechamento(c_fech);
    if v_r -> 'linhas' ->> 0 is distinct from
         'Enviados vencidos sem desfecho: 2 (ORÇ-99577, ORÇ-99578) · *motivo <número> A* marca como perdido (sumiu)' then
      raise exception '6f: com motivo_marca_aberto (%)', v_r -> 'linhas';
    end if;
    -- 6g. Com a F5 desligada, só a dos vencidos (vale mesmo sem cadência).
    perform pg_temp.f5d_ligar();
    perform pg_temp.f5d_nivel('sozinho');
    update public.orcamento_passos p set dia = date '2027-01-15', ate = date '2027-01-15' where p.acompanhamento_id = v_ac and p.passo = 'lembrete';
    update public.orcamento_acompanhamentos a set modo = 'ligado' where a.id = v_ac;
    v_r := public.orcamento_resumo_fechamento(c_fech);
    if jsonb_array_length(v_r -> 'fixas') is distinct from 1 then
      raise exception '6g: a fixa com a F5 ligada (%)', v_r;
    end if;
    update public.retorno_config set orcamento_modo = 'desligado' where id;
    v_r := public.orcamento_resumo_fechamento(c_fech);
    if v_r -> 'fixas' is distinct from '[]'::jsonb or v_r -> 'avisar' is distinct from '[]'::jsonb
       or jsonb_array_length(v_r -> 'linhas') is distinct from 1 or (v_r -> 'linhas' ->> 0 ~ '^Enviados vencidos sem desfecho: ') is not true then
      raise exception '6g: com a F5 desligada (%)', v_r;
    end if;
    -- Nenhuma sequência de 8 dígitos (telefone ou documento) em linha nenhuma.
    if exists (select 1 from jsonb_array_elements_text(v_r -> 'linhas') x where x ~ '[0-9]{8}') then
      raise exception '6g: dígito de telefone ou documento no fechamento';
    end if;
    raise exception 'f5d_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5d_cenario' then
      raise;
    end if;
  end;

  -- ── 6b. O aviso da véspera entregue ──
  begin
    v_ac := pg_temp.f5d_cad('Ana Desfecho F5 Teste', '5547900009967', 'ORÇ-99567');
    v_p1 := (select p.id from public.orcamento_passos p where p.acompanhamento_id = v_ac and p.passo = 'lembrete');
    v_p2 := (select p.id from public.orcamento_passos p where p.acompanhamento_id = v_ac and p.passo = 'vespera');
    update public.orcamento_passos p set estado = 'aguarda_sim' where p.id = v_p2;
    if public.orcamento_avisados(array[v_p1, v_p2], null, c_fech) is distinct from 0
       or exists (select 1 from public.orcamento_passos p where p.id in (v_p1, v_p2) and (p.avisado_em is not null or p.aviso_fila is not null)) then
      raise exception '6b-a: sem a linha da fila gravou o aviso';
    end if;
    if public.orcamento_avisados(array[v_p1, v_p2], v_fila, c_fech) is distinct from 1 then
      raise exception '6b-b: o aviso não marcou só o previsto';
    end if;
    if (select p.avisado_em from public.orcamento_passos p where p.id = v_p1) is distinct from c_fech
       or (select p.aviso_fila from public.orcamento_passos p where p.id = v_p1) is distinct from v_fila
       or (select p.avisado_em from public.orcamento_passos p where p.id = v_p2) is not null then
      raise exception '6b-c: o aviso gravado';
    end if;
    raise exception 'f5d_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5d_cenario' then
      raise;
    end if;
  end;

  -- ── 7. A carona sem a lista da P7 (a onda 4): o ramo undefined_function dá o texto da F2 ──
  if to_regprocedure('public._orcamento_cartao_lista(timestamptz, integer)') is null then
    begin
      select d.id into v_dono from public._comprovante_dono() d limit 1;
      if v_dono is null then
        raise exception '7: sem _comprovante_dono, a carona não tem a quem falar';
      end if;
      update public.retorno_config set carona_ligada = true, carona_em = null where id;
      v_r2 := public.retorno_cartao_vivo(c_carona);
      if v_r2 ->> 'estado' is not distinct from 'vivo' then
        -- Há um cartão vivo de verdade: a carona fala dele, como na F2 (o ramo da lista nem roda).
        v_r := public.retorno_carona(v_dono, c_carona);
        if (v_r ->> 'texto' ~ '^Retorno: cartão aberto, ') is not true then
          raise exception '7a: com o cartão vivo, a carona mudou';
        end if;
      else
        v_ana := pg_temp.f5d_cli('Ana Desfecho F5 Teste', '5547900009968');
        v_ab := pg_temp.f5d_caso(v_ana, '5547900009968', c_carona - interval '1 hour');
        v_r := public.retorno_carona(v_dono, c_carona);
        if v_r is distinct from jsonb_build_object('texto', 'Retorno: 1 esperando (Ana, desde 09:00) · *retorno*') then
          raise exception '7b: a carona da F2 pelo ramo undefined_function (%)', v_r;
        end if;
      end if;
      if (select c.carona_em from public.retorno_config c where c.id) is distinct from c_carona then
        raise exception '7c: carona_em não gravado';
      end if;
      raise exception 'f5d_cenario' using errcode = 'P0001';
    exception when others then
      if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5d_cenario' then
        raise;
      end if;
    end;
  end if;
  select p.prosrc into v from pg_proc p where p.oid = 'public.retorno_carona(uuid, timestamptz)'::regprocedure;
  if (v ~ 'exception when undefined_function then') is not true
     or (char_length(v) - char_length(replace(v, 'update public.retorno_config set carona_em = v_agora where id;', '')))
        / char_length('update public.retorno_config set carona_em = v_agora where id;') is distinct from 2 then
    raise exception '7d: o corpo gerado da carona (o ramo da lista e os dois updates com where id)';
  end if;

  -- ── 8. O "Mandei sozinho" com a saída do orçamento, e o *errado Z* ──
  begin
    perform pg_temp.f5d_ligar();
    perform pg_temp.f5d_nivel('sozinho');
    v_ac := pg_temp.f5d_cad('Ana Desfecho F5 Teste', '5547900009961', 'ORÇ-99561');
    v_ac2 := pg_temp.f5d_cad('João Desfecho F5 Teste', '5547900009962', 'ORÇ-99562');
    v_ac3 := pg_temp.f5d_cad('Pedro Desfecho F5 Teste', '5547900009963', 'ORÇ-99563');
    v_ac4 := pg_temp.f5d_cad('Ana Desfecho F5 Teste', '5547900009964', 'ORÇ-99564');
    v_s1 := pg_temp.f5d_saida(v_ac, 'lembrete', 'orc_lembrete', 'enviada', c_qui, '{"por": "sozinho", "sozinho": true}');
    v_s2 := pg_temp.f5d_saida(v_ac2, 'lembrete', 'orc_lembrete', 'enviada', c_qui + interval '1 minute', '{"por": "sozinho", "sozinho": true}');
    v_s3 := pg_temp.f5d_saida(v_ac3, 'lembrete', 'orc_lembrete', 'enviada', c_qui + interval '2 minutes', '{"por": "sozinho", "sozinho": true}');
    v_s4 := pg_temp.f5d_saida(v_ac4, 'lembrete', 'orc_lembrete', 'incerta', c_qui + interval '3 minutes', '{"por": "sozinho", "sozinho": true}');
    perform public._retorno_gravar_letra(v_s1, c_qui, 1);
    perform public._retorno_gravar_letra(v_s2, c_qui + interval '1 minute', 2);
    perform public._retorno_gravar_letra(v_s3, c_qui + interval '2 minutes', 3);
    perform public._retorno_gravar_letra(v_s4, c_qui + interval '3 minutes', 4);
    v_r := public.retorno_resumo_extra('fechamento', c_fech);
    if v_r -> 'mandei' is distinct from jsonb_build_array(
         jsonb_build_object('letra', 'Z', 'rotulo', 'lembrete do ORÇ-99561 (Ana)', 'tipo_curto', 'lembrete do orçamento', 'saida_id', v_s1),
         jsonb_build_object('letra', 'Y', 'rotulo', 'lembrete do ORÇ-99562 (João)', 'tipo_curto', 'lembrete do orçamento', 'saida_id', v_s2),
         jsonb_build_object('letra', 'X', 'rotulo', 'lembrete do ORÇ-99563 (Pedro)', 'tipo_curto', 'lembrete do orçamento', 'saida_id', v_s3))
       or (v_r ->> 'mandei_mais')::integer is distinct from 1 then
      raise exception '8a: o Mandei sozinho com a saída do orçamento (%, %)', v_r -> 'mandei', v_r -> 'mandei_mais';
    end if;
    -- *errado Z*: rebaixa o tipo do orçamento, e a resposta diz o nome do cliente (nunca "com contato").
    v_r := public._retorno_dito_errado('Z', c_fech);
    if v_r ->> 'texto' is distinct from
         'Anotei: ''lembrete do orçamento'' voltou ao cartão e não sai mais sozinho. Se quiser corrigir com Ana, responda pelo celular.' then
      raise exception '8b: a resposta do errado Z (%)', v_r;
    end if;
    if (select t.rebaixado_em from public.retorno_modelo_tipos t where t.tipo = 'orc_lembrete') is distinct from c_fech
       or (select s.dados ->> 'errado_em' from public.retorno_saidas s where s.id = v_s1) is null then
      raise exception '8b: o errado Z não rebaixou o tipo nem marcou a saída';
    end if;
    -- 8c. A amostra da auditoria: a 1ª saída (auditoria pela régua de auditoria_cada) aparece, com o rótulo do orçamento; o
    --     trecho da saída sem caso é o '(sem texto)' de _retorno_pedido_do_caso (o código; a spec dizia nulo).
    if (select count(*) from public.retorno_auditoria_lista l
         where l.tipo = 'orc_lembrete' and l.enviada_em = c_qui and l.rotulo = 'lembrete do ORÇ-99561 (Ana)'
           and l.trecho = '(sem texto)') is distinct from 1::bigint then
      raise exception '8c: a saída sozinha do orçamento com auditoria não está na amostra';
    end if;
    raise exception 'f5d_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5d_cenario' then
      raise;
    end if;
  end;
  begin
    -- 8d. Regressão: sem saída do orçamento, o "Mandei sozinho" vazio; o modelo da F2 com caso, como antes (o rótulo do caso).
    v_r := public.retorno_resumo_extra('fechamento', c_fech);
    if v_r -> 'mandei' is distinct from '[]'::jsonb or (v_r ->> 'mandei_mais')::integer is distinct from 0 then
      raise exception '8d: sem saída nenhuma (%)', v_r -> 'mandei';
    end if;
    v_ana := pg_temp.f5d_cli('Ana Desfecho F5 Teste', '5547900009968');
    v_ab := pg_temp.f5d_caso(v_ana, '5547900009968', c_qui - interval '2 hours');
    insert into public.retorno_saidas (emissor, abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo, estado,
                                       enviar_em, decidida_em, enviada_em, texto, dados, dedupe_key)
    values ('retorno', v_ab, 'modelo_pronto', 'retorno_modelo', 'resposta_atrasada', '00009968', '5547900009968', v_ana, 'ligado',
            'enviada', c_qui, c_qui, c_qui, 'Oi, Ana! Texto de teste do modelo (F5 desfecho).', '{"sozinho": true}'::jsonb,
            'retorno:teste-f5d-8d:' || v_ab)
    returning id into v_s1;
    perform public._retorno_gravar_letra(v_s1, c_qui, 2);
    v_r := public.retorno_resumo_extra('fechamento', c_fech);
    if v_r -> 'mandei' is distinct from jsonb_build_array(
         jsonb_build_object('letra', 'Z', 'rotulo', 'Ana', 'tipo_curto', public._retorno_tipo_curto('modelo_pronto'), 'saida_id', v_s1))
       or (v_r ->> 'mandei_mais')::integer is distinct from 0 then
      raise exception '8d: o modelo da F2 (%)', v_r -> 'mandei';
    end if;
    v_r := public._retorno_dito_errado('Z', c_fech);
    if v_r ->> 'texto' is distinct from format(
         'Anotei: ''%s'' voltou ao cartão e não sai mais sozinho. Se quiser corrigir com Ana, responda pelo celular.',
         public._retorno_tipo_curto('modelo_pronto')) then
      raise exception '8d: o errado Z do modelo da F2 (%)', v_r;
    end if;
    raise exception 'f5d_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5d_cenario' then
      raise;
    end if;
  end;

  -- ── 8b. A view da auditoria: as mesmas colunas, na mesma ordem, security_invoker e os grants de antes ──
  if (select string_agg(c.column_name, ',' order by c.ordinal_position) from information_schema.columns c
       where c.table_schema = 'public' and c.table_name = 'retorno_auditoria_lista')
     is distinct from 'enviada_em,tipo,texto,rotulo,trecho,fato,fonte,errado_em' then
    raise exception '8b-1: as colunas da view mudaram';
  end if;
  if (select 'security_invoker=on' = any (coalesce(c.reloptions, '{}')) from pg_class c where c.oid = 'public.retorno_auditoria_lista'::regclass) is not true then
    raise exception '8b-2: a view sem security_invoker';
  end if;
  if has_table_privilege('anon', 'public.retorno_auditoria_lista', 'select') or has_table_privilege('authenticated', 'public.retorno_auditoria_lista', 'select')
     or not has_table_privilege('service_role', 'public.retorno_auditoria_lista', 'select') then
    raise exception '8b-3: os grants da view';
  end if;

  -- ── 9. As funções novas: SECURITY DEFINER com search_path; as cinco públicas só à service_role (a 5ª, orcamento_nao_saiu_avisados,
  --        da revisão das ondas 4 a 9); as geradas com os grants de antes; nenhuma aberta a anon ou authenticated ──
  foreach v in array c_novas loop
    for v_rec in
      select p.oid, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = v
    loop
      v_n_fun := v_n_fun + 1;
      if v_rec.prosecdef is not true or not exists (select 1 from unnest(v_rec.config) o where o ~ '^search_path=') then
        raise exception '9a: % não é SECURITY DEFINER com search_path', v_rec.nome;
      end if;
      if has_function_privilege('anon', v_rec.oid, 'execute') or has_function_privilege('authenticated', v_rec.oid, 'execute') then
        raise exception '9b: % aberta a anon ou authenticated', v_rec.nome;
      end if;
      -- A interna leva só o revoke (spec, regras gerais): no Supabase a service_role tem EXECUTE pelo padrão do esquema,
      -- como todas as _retorno_*/_parceiro_* em produção (conferido 13/11). O que se exige é a pública aberta a ela.
      if v = any (c_publicas) and not has_function_privilege('service_role', v_rec.oid, 'execute') then
        raise exception '9c: o grant da service_role em %', v_rec.nome;
      end if;
    end loop;
  end loop;
  if v_n_fun is distinct from 6 then
    raise exception '9d: achei % das 6 funções novas', v_n_fun;
  end if;
  for v_rec in
    select x.f, x.servico, p.oid
      from (values ('public.retorno_carona(uuid, timestamptz)', true),
                   ('public.retorno_resumo_extra(text, timestamptz)', true),
                   -- servico = o grant da service_role em produção antes da F5 (13/11: a interna também tem, pelo padrão)
                   ('public._retorno_dito_errado(text, timestamptz)', true)) as x(f, servico)
      join pg_proc p on p.oid = to_regprocedure(x.f)
  loop
    if has_function_privilege('anon', v_rec.oid, 'execute') or has_function_privilege('authenticated', v_rec.oid, 'execute')
       or has_function_privilege('service_role', v_rec.oid, 'execute') is distinct from v_rec.servico then
      raise exception '9e: os grants de %', v_rec.f;
    end if;
  end loop;

  raise exception 'retorno_f5_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f5_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f5_desfecho', true, '{}');
end
$desfecho$;

select arquivo, ok, numeros from _bancada order by em;
rollback;

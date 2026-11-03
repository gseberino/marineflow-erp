-- Retorno F1 (P5): abrir o caso (retorno_abrir) e a triagem (_retorno_triar), 20261116100600_retorno_f1_abrir.sql.
--   0. as funções (VOLATILE, SECURITY DEFINER com search_path, fechadas a anon e authenticated) e as premissas:
--      a linha de configuração, nenhum caso vivo dos números de teste e nenhuma mensagem real na data do arquivo
--      (a carência olha a saída humana a QUALQUER número);
--   1. idempotência: a mesma mensagem duas vezes = 1 caso e 1 recibo ("repetida"); o '[audio]' fica pendente e a
--      transcrição reavalia ("reavaliada"), com sinais novos, o recibo do número novo e a coleta;
--   2. papéis: cliente, ambíguo (client_id nulo), fornecedor ativo, fornecedor inativo com cliente ativo, equipe,
--      contato conhecido, parceiro (o sintético e a MP real, pelo id da config), "Cliente Final"; dois leads do
--      mesmo número (nenhum é escolhido);
--   3. número novo: saudação; saudação substituída pelo recibo; recibo depois da saudação já decidida; vendedor;
--      "pode me ligar?";
--   4. carência: 2 min; 10 min com o dono ativo; a saída humana do futuro não conta; a rajada empurra;
--   5. não pede: "Obrigado!", figurinha, robô (texto longo 3×, com a insistência da 2ª cópia descontada quando o
--      robô se revela), o mesmo texto 3× com o recibo já enviado (a revelação não roda e o adiamento fica), robô
--      de 5 s 80 min depois do pedido (sem insistência nem coleta; o caso continua recibo); a coleta depois da
--      resposta; o nome que nunca nasce na sombra; o nome dito depois da coleta enviada (cadastro provisório);
--   6. agenda (agenda_cliente_respostas, sempre com p_consumida = false): confirmou consome; ao_dono e ambigua =
--      passagem com o acorde cancelado (agenda_ja_acordou) e o recibo agendado; sombra não consome; confirmou em
--      modo sombra não consome; p_consumida = true consome;
--   7. passagem: risco (dados.risco), LGPD, 2 insistências (e a mensagem 1 min depois não ganha outro acorde),
--      mensagem nova em caso vencido (sem recibo novo, inclusive no caso da promessa do dono que venceu, com o
--      vigia já tendo marcado o caso ou ainda não); resposta humana entre duas mensagens (sem insistência);
--      URGENTE depois do recibo decidido (e nenhuma saída urgente antes dele);
--   8. promessa do dono, e a criada depois de p_agora (ignorada);
--   9. PARAR por papel, e o PARAR por áudio (sem opt-out gravado: parar_largo, sem confirmação);
--  10. PARAR por extenso, e o "?" depois dele (o caso continua parar_largo, sem recibo); 11. opt-out × spam;
--  12. erro: mensagem inexistente; _retorno_sinais renomeada (ok = false e app_error_logs) e a mensagem seguinte segue;
--  13. futuro: a mensagem gravada depois de p_agora é ignorada.
-- Cadastros e mensagens SINTÉTICOS de 55479000094xx, com p_agora na ter 17/11/2026 (Brasília). A MP real só é
-- LIDA (a mensagem dela é sintética, e o caso só roda se o cadastro dela identifica sozinho e sem bloqueio).
-- Run (só pela bancada, de madrugada): npx supabase@2.111.0 db query --linked -f supabase/tests/retorno_f1_abrir.sql
-- Termina em ROLLBACK: nada fica gravado. O arranjo inteiro (retorno_config, cadastros, mensagens, casos, saídas e
-- a função renomeada do caso 12) é desfeito dentro do arquivo (sub-bloco que termina em 'desfaz').
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- Uma mensagem sintética (recebida, por padrão), com a hora real e a de gravação (igual, salvo p_gravada); o id.
-- raw_payload padrão '{"data": {}}' = a vinda do webhook (na enviada, o eco do celular: saída humana).
create or replace function pg_temp.retorno_f1_abrir_msg(p_fone text, p_corpo text, p_em timestamptz,
                                                       p_direcao text default 'inbound', p_tipo text default 'text',
                                                       p_raw jsonb default '{"data": {}}'::jsonb,
                                                       p_gravada timestamptz default null)
returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload,
                                        hora_real, occurred_at)
  values (p_direcao, p_fone, p_tipo, p_corpo, case when p_direcao = 'inbound' then 'received' else 'sent' end, p_raw,
          p_em, coalesce(p_gravada, p_em))
  returning id
$f$;

-- Um cliente sintético, pelo WhatsApp do cadastro; o id.
create or replace function pg_temp.retorno_f1_abrir_cliente(p_sufixo text, p_whatsapp text, p_generico boolean default false)
returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp, generico)
  values ('individual', 'Teste F1 abrir ' || p_sufixo, p_whatsapp, p_generico)
  returning id
$f$;

-- Confere uma resposta de retorno_abrir com ok = true: o contrato C-ABRIR (as 8 chaves), a ação, o nível, o
-- motivo e (se dado) o papel; nível e caso andam juntos. Levanta '<caso>: …' na 1ª diferença; devolve 1.
create or replace function pg_temp.retorno_f1_abrir_confere(p_caso text, p_r jsonb, p_acao text, p_nivel text,
                                                           p_motivo text default null, p_papel text default null)
returns integer
language plpgsql as $f$
begin
  if jsonb_typeof(p_r) is distinct from 'object'
     or (select array_agg(k order by k collate "C") from jsonb_object_keys(p_r) k)
        is distinct from array['abertura_id', 'acao', 'modo', 'motivo', 'nivel', 'ok', 'papel', 'saida_id'] then
    raise exception '%: fora do contrato C-ABRIR: %', p_caso, p_r;
  end if;
  if p_r -> 'ok' is distinct from 'true'::jsonb or p_r ->> 'acao' is distinct from p_acao
     or p_r ->> 'nivel' is distinct from p_nivel or p_r ->> 'motivo' is distinct from p_motivo
     or (p_papel is not null and p_r ->> 'papel' is distinct from p_papel) then
    raise exception '%: esperado acao %, nivel %, motivo %, papel %; veio %', p_caso, p_acao, coalesce(p_nivel, '(nulo)'),
      coalesce(p_motivo, '(nulo)'), coalesce(p_papel, '(qualquer)'), p_r;
  end if;
  if (p_r ->> 'nivel' is null) is distinct from (p_r ->> 'abertura_id' is null) then
    raise exception '%: nível e caso fora de par: %', p_caso, p_r;
  end if;
  return 1;
end $f$;

-- O caso, a linha da mensagem e a saída de um caso pela chave ('recibo', 'saudacao', 'acorde:<id>' …).
create or replace function pg_temp.retorno_f1_abrir_caso(p_id uuid)
returns public.retorno_aberturas
language sql as $f$
  select ab.* from public.retorno_aberturas ab where ab.id = p_id
$f$;

create or replace function pg_temp.retorno_f1_abrir_rm(p_msg uuid)
returns public.retorno_mensagens
language sql as $f$
  select r.* from public.retorno_mensagens r where r.whatsapp_message_id = p_msg
$f$;

create or replace function pg_temp.retorno_f1_abrir_saida(p_caso uuid, p_sufixo text)
returns public.retorno_saidas
language sql as $f$
  select s.* from public.retorno_saidas s where s.dedupe_key = 'retorno:' || p_caso || ':' || p_sufixo
$f$;

-- Quantas saídas o caso tem (todas, ou de um tipo).
create or replace function pg_temp.retorno_f1_abrir_n_saidas(p_caso uuid, p_tipo text default null)
returns integer
language sql as $f$
  select count(*)::integer from public.retorno_saidas s where s.abertura_id = p_caso and (p_tipo is null or s.tipo = p_tipo)
$f$;

-- Simula a decisão do retorno_pegar (P6) sobre uma saída: o estado, a hora, a variante e um texto.
create or replace function pg_temp.retorno_f1_abrir_decide(p_saida uuid, p_estado text, p_em timestamptz,
                                                          p_variante text default null)
returns void
language sql as $f$
  update public.retorno_saidas
     set estado = p_estado, decidida_em = p_em, enviada_em = case when p_estado = 'enviada' then p_em end,
         variante = coalesce(p_variante, variante), texto = 'Teste F1 abrir: o texto que a saída teria.',
         atualizada_em = now()
   where id = p_saida
$f$;

do $abrir$
declare
  -- ter 17/11/2026, 00:00 em Brasília: dia útil, data futura, sem mensagem real
  c_d constant timestamptz := '2026-11-17 00:00:00-03';
  c_mp constant uuid := 'ad4fea63-50af-45a3-b5ea-8724e63a5cb0';
  c_vendedor constant text :=
    'Oii Sou a Allana, Consultora Empresarial da Vivo. Consigo um plano para você trocar a bateria do motorhome sem custo, posso te mandar?';
  c_robo constant text :=
    'Olá! Agradecemos o seu contato. Nosso horário de atendimento é de segunda a sexta, das 8h às 18h.';
  c_pedido_c1 constant text := 'Bom dia, vocês fazem instalação de placa solar em motorhome?';
  v_f record;
  v_cfg_antes jsonb;
  v_chegou boolean := false;
  v_n integer := 0;
  v_mp text := 'pulado';
  v_mp_fone text;
  v_q jsonb;
  -- cadastros
  v_c01 uuid; v_c03 uuid; v_c04a uuid; v_c04b uuid; v_c06 uuid; v_c09 uuid; v_c10 uuid; v_c23 uuid; v_c24 uuid;
  v_c25 uuid; v_c26 uuid; v_c45 uuid; v_c33 uuid;
  v_lead02 uuid; v_lead44 uuid;
  -- mensagens, respostas e leituras
  v_m uuid; v_m2 uuid; v_m3 uuid; v_m4 uuid;
  v_r jsonb; v_r2 jsonb;
  v_caso uuid;
  v_ab public.retorno_aberturas;
  v_rm public.retorno_mensagens;
  v_s public.retorno_saidas;
  v_s2 public.retorno_saidas;
  v_coleta jsonb;
  v_lead_coleta jsonb;
  -- o caso 12
  v_err jsonb;
  v_err_logs integer;
  v_err_rm boolean;
begin
  -- ── 0. As funções e as premissas ────────────────────────────────────────────────────────────────────
  for v_f in
    select x.assinatura, p.oid, p.provolatile, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from (values ('public.retorno_abrir(uuid, boolean, timestamptz)'), ('public._retorno_triar(uuid, timestamptz)')) x(assinatura)
      left join pg_proc p on p.oid = to_regprocedure(x.assinatura)
  loop
    if v_f.oid is null then
      raise exception '0: % não existe', v_f.assinatura;
    end if;
    if v_f.provolatile <> 'v' or not v_f.prosecdef or not ('search_path=public' = any (v_f.config)) then
      raise exception '0: % não é VOLATILE + SECURITY DEFINER com search_path = public', v_f.assinatura;
    end if;
    if has_function_privilege('anon', v_f.oid, 'execute') or has_function_privilege('authenticated', v_f.oid, 'execute') then
      raise exception '0: % aberta a anon/authenticated', v_f.assinatura;
    end if;
  end loop;
  if not has_function_privilege('service_role', 'public.retorno_abrir(uuid, boolean, timestamptz)', 'execute') then
    raise exception '0: retorno_abrir não é do service_role';
  end if;
  select to_jsonb(c) into v_cfg_antes from public.retorno_config c where c.id;
  if not found then
    raise exception '0b: retorno_config sem a linha de configuração';
  end if;
  if exists (select 1 from public.retorno_aberturas ab where ab.chave like '000094%') then
    raise exception '0c: já há caso dos números de teste 55479000094xx';
  end if;
  -- A carência olha a saída humana a QUALQUER número nos 15 min antes de p_agora: uma enviada real em 17/11
  -- mudaria os 2 min esperados. E os números de teste não podem ter mensagem real.
  if exists (select 1 from public.whatsapp_messages w
              where w.direction = 'outbound' and w.occurred_at >= c_d and w.occurred_at < c_d + interval '1 day') then
    raise exception '0d: há enviadas gravadas em 17/11/2026: a carência (dono ativo) do arquivo precisa de outra data';
  end if;
  if exists (select 1 from public.whatsapp_messages w where w.phone_normalized like '55479000094%') then
    raise exception '0d: há mensagens dos números de teste 55479000094xx';
  end if;

  begin
    -- A configuração de nascença do que este arquivo usa (sombra, nada ligado, carência e esperas padrão).
    v_c09 := pg_temp.retorno_f1_abrir_cliente('9409 parceiro', '(47) 90000-9409');
    update public.retorno_config
       set modo = 'sombra', tipos_ligados = '{}', carencia_min = 2, carencia_dono_ativo_min = 10, dono_ativo_janela_min = 15,
           saudacao_espera_min = 10, audio_espera_min = 3, insistencia_apos = interval '60 minutes', coleta_max = 2,
           robo_resposta_s = 5, clientes_parceiros = array_append(clientes_parceiros, v_c09)
     where id;

    -- ── 1. Idempotência ──────────────────────────────────────────────────────────────────────────────
    -- 1a. A mesma mensagem duas vezes: 1 caso, 1 recibo; a 2ª chamada é "repetida" e não muda nada.
    v_c01 := pg_temp.retorno_f1_abrir_cliente('9401', '(47) 90000-9401');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009401', 'Preciso trocar a bateria da lancha, consegue ver?',
                                        c_d + interval '7 hours');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '7 hours 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('1a', v_r, 'nova', 'recibo', null, 'cliente');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    if v_r ->> 'modo' is distinct from 'sombra' then
      raise exception '1a: o caso não nasceu em sombra: %', v_r;
    end if;
    v_r2 := public.retorno_abrir(v_m, false, c_d + interval '7 hours 10 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('1a', v_r2, 'repetida', 'recibo', null, 'cliente');
    if v_r2 ->> 'abertura_id' is distinct from v_r ->> 'abertura_id' or v_r2 ->> 'saida_id' is distinct from v_r ->> 'saida_id' then
      raise exception '1a: a 2ª chamada mudou o caso ou a saída: % / %', v_r, v_r2;
    end if;
    if (select count(*) from public.retorno_aberturas ab where ab.chave = '00009401') <> 1
       or pg_temp.retorno_f1_abrir_n_saidas(v_caso) <> 1
       or (select count(*) from public.retorno_mensagens r where r.whatsapp_message_id = v_m) <> 1 then
      raise exception '1a: idempotência quebrada (caso, saída ou linha da mensagem a mais)';
    end if;
    v_s := pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo');
    if v_s.id is distinct from (v_r ->> 'saida_id')::uuid or v_s.tipo is distinct from 'recibo_cliente'
       or v_s.estado is distinct from 'agendada' or v_s.modo is distinct from 'sombra' or v_s.emissor is distinct from 'retorno'
       or v_s.origem is distinct from 'retorno_recibo' or v_s.classe is distinct from 'resposta_imediata'
       or v_s.client_id is distinct from v_c01 or v_s.chave is distinct from '00009401'
       or v_s.phone_normalized is distinct from '5547900009401'
       or v_s.enviar_em is distinct from c_d + interval '7 hours 2 minutes' or v_s.texto is not null then
      raise exception '1a: recibo fora do molde (agendada, sombra, gravada + 2 min): %', to_jsonb(v_s);
    end if;
    v_ab := pg_temp.retorno_f1_abrir_caso(v_caso);
    if v_ab.papel is distinct from 'cliente' or v_ab.client_id is distinct from v_c01 or v_ab.clientes is distinct from array[v_c01]
       or v_ab.quem ->> 'papel' is distinct from 'cliente' or v_ab.ddd is distinct from '47'
       or v_ab.primeira_msg_id is distinct from v_m or v_ab.ultima_msg_id is distinct from v_m or v_ab.msgs <> 1
       or v_ab.aberta_em is distinct from c_d + interval '7 hours' or v_ab.gravada_em is distinct from c_d + interval '7 hours'
       or v_ab.atraso_gravacao <> interval '0' or v_ab.estado is distinct from 'aberta'
       or v_ab.tipo_recibo is distinct from 'recibo_cliente' or v_ab.intencao is distinct from 'pedido_servico'
       or v_ab.insistencias <> 0 or not coalesce((v_ab.sinais ->> 'servico')::boolean, false) then
      raise exception '1a: caso fora do molde: %', to_jsonb(v_ab);
    end if;
    v_rm := pg_temp.retorno_f1_abrir_rm(v_m);
    if v_rm.abertura_id is distinct from v_caso or v_rm.corpo_hash is distinct from md5('Preciso trocar a bateria da lancha, consegue ver?')
       or not v_rm.pede_resposta or v_rm.consumida or v_rm.agenda_ao_dono or v_rm.audio_pendente
       or v_rm.chave is distinct from '00009401' then
      raise exception '1a: linha da mensagem fora do molde: %', to_jsonb(v_rm);
    end if;

    -- 1b. Número novo que manda só áudio: '[audio]' fica pendente (o caso abre, sem pedido ainda, sem saída).
    insert into public.whatsapp_leads (phone_normalized, name) values ('5547900009402', 'Teste F1 abrir áudio')
      returning id into v_lead02;
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009402', '[audio]', c_d + interval '7 hours 30 minutes', 'inbound', 'audio');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '7 hours 30 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('1b', v_r, 'nova', 'nada', 'numero_novo_sem_pedido', 'numero_novo');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    v_rm := pg_temp.retorno_f1_abrir_rm(v_m);
    if not v_rm.audio_pendente or not v_rm.pede_resposta or v_rm.corpo_hash is distinct from md5('[audio]')
       or pg_temp.retorno_f1_abrir_n_saidas(v_caso) <> 0 then
      raise exception '1b: o [audio] não ficou pendente, ou ganhou saída: %', to_jsonb(v_rm);
    end if;
    -- 1c. A transcrição troca o corpo da mesma linha: "reavaliada", sinais novos, áudio resolvido, recibo e coleta.
    update public.whatsapp_messages set body = '🎤 preciso trocar a bateria do motorhome' where id = v_m;
    v_r := public.retorno_abrir(v_m, false, c_d + interval '7 hours 31 minutes');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('1c', v_r, 'reavaliada', 'recibo', null, 'numero_novo');
    if (v_r ->> 'abertura_id')::uuid is distinct from v_caso then
      raise exception '1c: a reavaliação abriu outro caso: %', v_r;
    end if;
    v_rm := pg_temp.retorno_f1_abrir_rm(v_m);
    if v_rm.audio_pendente or v_rm.corpo_hash is distinct from md5('🎤 preciso trocar a bateria do motorhome')
       or not coalesce((v_rm.sinais ->> 'servico')::boolean, false) or not coalesce((v_rm.sinais ->> 'bem')::boolean, false)
       or v_rm.abertura_id is distinct from v_caso then
      raise exception '1c: os sinais não foram regravados: %', to_jsonb(v_rm);
    end if;
    v_ab := pg_temp.retorno_f1_abrir_caso(v_caso);
    v_s := pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo');
    if v_ab.tipo_recibo is distinct from 'recibo_numero_novo' or v_ab.msgs <> 1 or v_ab.lead_id is distinct from v_lead02
       or v_s.tipo is distinct from 'recibo_numero_novo' or v_s.estado is distinct from 'agendada'
       or v_s.enviar_em is distinct from c_d + interval '7 hours 32 minutes' or v_s.id is distinct from (v_r ->> 'saida_id')::uuid then
      raise exception '1c: o número novo não ganhou o recibo depois da transcrição: % / %', to_jsonb(v_ab), to_jsonb(v_s);
    end if;
    -- A coleta (C1), literal, no formato de dados_site, no caso e no lead.
    v_coleta := v_ab.coleta;
    select l.coleta into v_lead_coleta from public.whatsapp_leads l where l.id = v_lead02;
    if (select array_agg(k order by k collate "C") from jsonb_object_keys(v_coleta) k)
         is distinct from array['ano', 'atualizado_em', 'detalhes', 'fonte', 'local', 'modelo', 'nome', 'servico', 'tipo']
       or v_coleta ->> 'tipo' is distinct from 'Motorhome' or v_coleta ->> 'servico' is distinct from 'trocar, bateria'
       or v_coleta ->> 'detalhes' is distinct from '🎤 preciso trocar a bateria do motorhome'
       or v_coleta ->> 'fonte' is distinct from 'retorno' or jsonb_typeof(v_coleta -> 'nome') is distinct from 'null'
       or jsonb_typeof(v_coleta -> 'modelo') is distinct from 'null' or jsonb_typeof(v_coleta -> 'local') is distinct from 'null'
       or v_lead_coleta is distinct from v_coleta then
      raise exception '1c: coleta fora do formato (ou o lead não a recebeu): % / %', v_coleta, v_lead_coleta;
    end if;
    -- 1d. A mesma transcrição de novo: "repetida".
    v_r := public.retorno_abrir(v_m, false, c_d + interval '7 hours 32 minutes');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('1d', v_r, 'repetida', 'recibo', null, 'numero_novo');

    -- ── 2. Papéis ────────────────────────────────────────────────────────────────────────────────────
    -- 2a. Um cliente: recibo_cliente.
    v_c03 := pg_temp.retorno_f1_abrir_cliente('9403', '(47) 90000-9403');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009403', 'Bom dia, preciso de um orçamento para instalar inversor na lancha',
                                        c_d + interval '8 hours');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '8 hours 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('2a', v_r, 'nova', 'recibo', null, 'cliente');
    v_s := pg_temp.retorno_f1_abrir_saida((v_r ->> 'abertura_id')::uuid, 'recibo');
    if v_s.tipo is distinct from 'recibo_cliente' or v_s.client_id is distinct from v_c03 then
      raise exception '2a: o cliente não ganhou recibo_cliente: %', to_jsonb(v_s);
    end if;

    -- 2b. Dois clientes no número: recibo_ambiguo, client_id nulo (nunca escolhe), os dois na lista.
    insert into public.clients (type, name, phone) values ('individual', 'Teste F1 abrir 9404 A', '47 90000-9404')
      returning id into v_c04a;
    insert into public.clients (type, name, whatsapp) values ('company', 'Teste F1 abrir 9404 B', '(47) 90000-9404')
      returning id into v_c04b;
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009404', 'Bom dia, preciso de um orçamento para instalar inversor na lancha',
                                        c_d + interval '8 hours 10 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '8 hours 10 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('2b', v_r, 'nova', 'recibo', null, 'cliente_ambiguo');
    v_ab := pg_temp.retorno_f1_abrir_caso((v_r ->> 'abertura_id')::uuid);
    v_s := pg_temp.retorno_f1_abrir_saida(v_ab.id, 'recibo');
    if v_ab.client_id is not null or cardinality(v_ab.clientes) <> 2 or not (v_ab.clientes @> array[v_c04a, v_c04b])
       or v_ab.tipo_recibo is distinct from 'recibo_ambiguo' or v_s.tipo is distinct from 'recibo_ambiguo' or v_s.client_id is not null then
      raise exception '2b: o número de dois clientes escolheu um deles: % / %', to_jsonb(v_ab), to_jsonb(v_s);
    end if;

    -- 2c. Fornecedor ativo: nada/fornecedor, sem saída.
    insert into public.suppliers (name, phone, active) values ('Teste F1 abrir 9405 fornecedor', '(47) 90000-9405', true);
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009405', 'Bom dia, segue o orçamento da bateria que você pediu?',
                                        c_d + interval '8 hours 20 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '8 hours 20 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('2c', v_r, 'nova', 'nada', 'fornecedor', 'fornecedor');
    if pg_temp.retorno_f1_abrir_n_saidas((v_r ->> 'abertura_id')::uuid) <> 0 then
      raise exception '2c: o fornecedor ganhou saída';
    end if;

    -- 2d. Fornecedor INATIVO com o telefone de um cliente ativo: é o cliente (R1-18).
    insert into public.suppliers (name, phone, active) values ('Teste F1 abrir 9406 fornecedor inativo', '(47) 90000-9406', false);
    v_c06 := pg_temp.retorno_f1_abrir_cliente('9406', '(47) 90000-9406');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009406', 'Preciso de orçamento para trocar a bomba do barco',
                                        c_d + interval '8 hours 30 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '8 hours 30 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('2d', v_r, 'nova', 'recibo', null, 'cliente');
    if (pg_temp.retorno_f1_abrir_caso((v_r ->> 'abertura_id')::uuid)).client_id is distinct from v_c06 then
      raise exception '2d: o fornecedor inativo tirou o cliente: %', v_r;
    end if;

    -- 2e. Número da equipe: ignorada, sem caso e sem linha.
    insert into public.payees (name, phone) values ('Teste F1 abrir 9407 equipe', '(47) 90000-9407');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009407', 'Preciso da bateria nova para o motorhome do cliente?',
                                        c_d + interval '8 hours 40 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '8 hours 40 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('2e', v_r, 'ignorada', null, 'equipe', 'equipe');
    if exists (select 1 from public.retorno_aberturas ab where ab.chave = '00009407')
       or exists (select 1 from public.retorno_mensagens r where r.whatsapp_message_id = v_m) then
      raise exception '2e: a equipe abriu caso ou ganhou linha';
    end if;

    -- 2f. Número sem cadastro já respondido pelo celular (o eco, na véspera): contato_conhecido.
    perform pg_temp.retorno_f1_abrir_msg('5547900009408', 'Oi, tudo certo, amanhã passo aí.', c_d - interval '14 hours',
                                         'outbound', 'text', '{"data": {"key": {"fromMe": true}}}'::jsonb);
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009408', 'Oi, preciso trocar a bateria do carro, consegue?',
                                        c_d + interval '8 hours 50 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '8 hours 50 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('2f', v_r, 'nova', 'nada', 'contato_conhecido', 'contato_conhecido');

    -- 2g. Cliente em clientes_parceiros (o sintético, posto na config acima): parceiro_f4.
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009409', 'Preciso de orçamento para instalar inversor no motorhome do cliente',
                                        c_d + interval '9 hours');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '9 hours 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('2g', v_r, 'nova', 'nada', 'parceiro_f4', 'cliente_parceiro');
    if pg_temp.retorno_f1_abrir_n_saidas((v_r ->> 'abertura_id')::uuid) <> 0 then
      raise exception '2g: o parceiro ganhou saída';
    end if;

    -- 2h. A MP real, pelo id da config: só roda se o cadastro dela identifica sozinho (cliente, sem bloqueio,
    --     sem caso vivo) e a config a tem na lista; a mensagem é sintética.
    select regexp_replace(coalesce(nullif(btrim(c.whatsapp), ''), c.phone), '\D', '', 'g') into v_mp_fone
      from public.clients c where c.id = c_mp and c.active;
    if v_mp_fone ~ '^[0-9]{10,11}$' then
      v_mp_fone := '55' || v_mp_fone;
    end if;
    if v_mp_fone ~ '^55[0-9]{10,11}$' then
      v_q := public.quem_escreve(v_mp_fone);
      if v_q ->> 'papel' = 'cliente' and (v_q ->> 'cliente_id')::uuid = c_mp
         and public.canal_bloqueado(v_mp_fone) is null
         and exists (select 1 from public.retorno_config c where c.id and c_mp = any (c.clientes_parceiros))
         and not exists (select 1 from public.whatsapp_leads l
                          where l.lead_tipo = 'pessoal' and public._agenda_chave_telefone(l.phone_normalized) = public._agenda_chave_telefone(v_mp_fone))
         and not exists (select 1 from public.retorno_aberturas ab
                          where ab.chave = public._agenda_chave_telefone(v_mp_fone) and ab.estado in ('aberta', 'vencida')) then
        v_m := pg_temp.retorno_f1_abrir_msg(v_mp_fone, 'Teste F1 abrir: orçamento para instalar inversor no motorhome do cliente',
                                            c_d + interval '9 hours 20 minutes');
        v_r := public.retorno_abrir(v_m, false, c_d + interval '9 hours 20 minutes 5 seconds');
        v_n := v_n + pg_temp.retorno_f1_abrir_confere('2h', v_r, 'nova', 'nada', 'parceiro_f4', 'cliente_parceiro');
        v_mp := 'conferido';
      else
        v_mp := 'pulado: ' || coalesce(v_q ->> 'papel', 'sem papel');
      end if;
    end if;

    -- 2i. O "Cliente Final" (genérico): nada/cliente_final.
    v_c10 := pg_temp.retorno_f1_abrir_cliente('9410 Cliente Final', '(47) 90000-9410', true);
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009410', 'Preciso de orçamento para instalar inversor no motorhome',
                                        c_d + interval '9 hours 10 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '9 hours 10 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('2i', v_r, 'nova', 'nada', 'cliente_final');

    -- 2j. Dois leads do mesmo número (com e sem o 55): o caso não escolhe nenhum (lead_id nulo, sem coleta no lead).
    insert into public.whatsapp_leads (phone_normalized, name) values ('5547900009449', 'Teste F1 abrir lead A'),
                                                                      ('47900009449', 'Teste F1 abrir lead B');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009449', 'Preciso de orçamento para instalar inversor no motorhome',
                                        c_d + interval '9 hours 15 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '9 hours 15 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('2j', v_r, 'nova', 'recibo', null, 'numero_novo');
    if (pg_temp.retorno_f1_abrir_caso((v_r ->> 'abertura_id')::uuid)).lead_id is not null
       or exists (select 1 from public.whatsapp_leads l where l.phone_normalized in ('5547900009449', '47900009449') and l.coleta is not null) then
      raise exception '2j: com dois leads do número, o caso escolheu um';
    end if;

    -- ── 3. Número novo ───────────────────────────────────────────────────────────────────────────────
    -- 3a. "Boa tarde" abrindo conversa: saudação, gravada + 10 min.
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009411', 'Boa tarde', c_d + interval '9 hours 30 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '9 hours 30 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('3a', v_r, 'nova', 'recibo', null, 'numero_novo');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    v_ab := pg_temp.retorno_f1_abrir_caso(v_caso);
    v_s := pg_temp.retorno_f1_abrir_saida(v_caso, 'saudacao');
    if v_ab.tipo_recibo is distinct from 'saudacao_numero_novo' or v_ab.intencao is distinct from 'saudacao'
       or v_s.tipo is distinct from 'saudacao_numero_novo' or v_s.estado is distinct from 'agendada'
       or v_s.origem is distinct from 'retorno_recibo' or v_s.classe is distinct from 'resposta_imediata'
       or v_s.enviar_em is distinct from c_d + interval '9 hours 40 minutes' or v_s.id is distinct from (v_r ->> 'saida_id')::uuid
       or pg_temp.retorno_f1_abrir_n_saidas(v_caso) <> 1 then
      raise exception '3a: "Boa tarde" não deu a saudação de gravada + 10 min: % / %', to_jsonb(v_ab), to_jsonb(v_s);
    end if;
    -- 3b. 5 min depois, o pedido: a saudação agendada vira cancelada/substituida e nasce o recibo.
    v_m2 := pg_temp.retorno_f1_abrir_msg('5547900009411', 'preciso instalar inversor no barco', c_d + interval '9 hours 35 minutes');
    v_r := public.retorno_abrir(v_m2, false, c_d + interval '9 hours 35 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('3b', v_r, 'estendida', 'recibo', null, 'numero_novo');
    v_s := pg_temp.retorno_f1_abrir_saida(v_caso, 'saudacao');
    v_s2 := pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo');
    if v_s.estado is distinct from 'cancelada' or v_s.motivo is distinct from 'substituida'
       or v_s2.tipo is distinct from 'recibo_numero_novo' or v_s2.estado is distinct from 'agendada'
       or v_s2.enviar_em is distinct from c_d + interval '9 hours 37 minutes' or v_s2.id is distinct from (v_r ->> 'saida_id')::uuid
       or (pg_temp.retorno_f1_abrir_caso(v_caso)).tipo_recibo is distinct from 'recibo_numero_novo' then
      raise exception '3b: a saudação não foi substituída pelo recibo: % / %', to_jsonb(v_s), to_jsonb(v_s2);
    end if;
    -- 3c. Noutro número, a saudação já decidida (sombra) e depois o pedido: o recibo nasce com a chave própria.
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009412', 'Boa tarde', c_d + interval '10 hours');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '10 hours 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('3c', v_r, 'nova', 'recibo', null, 'numero_novo');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    v_s := pg_temp.retorno_f1_abrir_saida(v_caso, 'saudacao');
    if v_s.id is null then
      raise exception '3c: a saudação não nasceu';
    end if;
    perform pg_temp.retorno_f1_abrir_decide(v_s.id, 'sombra', c_d + interval '10 hours 10 minutes', 'padrao');
    v_m2 := pg_temp.retorno_f1_abrir_msg('5547900009412', 'preciso trocar a bateria do motorhome', c_d + interval '10 hours 15 minutes');
    v_r := public.retorno_abrir(v_m2, false, c_d + interval '10 hours 15 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('3c', v_r, 'estendida', 'recibo', null, 'numero_novo');
    v_s := pg_temp.retorno_f1_abrir_saida(v_caso, 'saudacao');
    v_s2 := pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo');
    if v_s.estado is distinct from 'sombra' or v_s2.dedupe_key is distinct from 'retorno:' || v_caso || ':recibo'
       or v_s2.tipo is distinct from 'recibo_numero_novo' or v_s2.estado is distinct from 'agendada'
       or v_s2.dados -> 'apos_saudacao' is distinct from 'true'::jsonb then
      raise exception '3c: o recibo depois da saudação decidida não nasceu com a chave própria: % / %', to_jsonb(v_s), to_jsonb(v_s2);
    end if;
    -- 3d. Vendedor (com serviço e bem): nada/vendedor.
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009413', c_vendedor, c_d + interval '10 hours 30 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '10 hours 30 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('3d', v_r, 'nova', 'nada', 'vendedor', 'numero_novo');
    -- 3e. "pode me ligar?" (pede, mas sem serviço nem bem): numero_novo_sem_pedido.
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009414', 'pode me ligar?', c_d + interval '10 hours 40 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '10 hours 40 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('3e', v_r, 'nova', 'nada', 'numero_novo_sem_pedido', 'numero_novo');
    if pg_temp.retorno_f1_abrir_n_saidas((v_r ->> 'abertura_id')::uuid) <> 0 then
      raise exception '3e: "pode me ligar?" ganhou saída';
    end if;

    -- ── 4. Carência ──────────────────────────────────────────────────────────────────────────────────
    -- 4a. Sem saída humana nos 15 min antes: gravada + 2 min.
    perform pg_temp.retorno_f1_abrir_cliente('9415', '(47) 90000-9415');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009415', 'Preciso de orçamento para trocar o inversor do motorhome',
                                        c_d + interval '19 hours 30 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '19 hours 30 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('4a', v_r, 'nova', 'recibo', null, 'cliente');
    if (pg_temp.retorno_f1_abrir_saida((v_r ->> 'abertura_id')::uuid, 'recibo')).enviar_em
         is distinct from c_d + interval '19 hours 32 minutes' then
      raise exception '4a: sem dono ativo, o recibo não ficou em gravada + 2 min';
    end if;
    -- 4b. Uma saída humana (caixa do app: raw_payload nulo) a OUTRO número 5 min antes: gravada + 10 min.
    perform pg_temp.retorno_f1_abrir_cliente('9416', '(47) 90000-9416');
    perform pg_temp.retorno_f1_abrir_msg('5547900009499', 'Teste F1 abrir: o dono respondendo outro cliente.',
                                         c_d + interval '20 hours 25 minutes', 'outbound', 'text', null);
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009416', 'Preciso de orçamento para trocar o inversor do motorhome',
                                        c_d + interval '20 hours 30 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '20 hours 30 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('4b', v_r, 'nova', 'recibo', null, 'cliente');
    if (pg_temp.retorno_f1_abrir_saida((v_r ->> 'abertura_id')::uuid, 'recibo')).enviar_em
         is distinct from c_d + interval '20 hours 40 minutes' then
      raise exception '4b: com o dono ativo, o recibo não ficou em gravada + 10 min';
    end if;
    -- 4c. A saída humana do FUTURO (gravada 1 min depois de p_agora) não muda a carência.
    perform pg_temp.retorno_f1_abrir_cliente('9417', '(47) 90000-9417');
    perform pg_temp.retorno_f1_abrir_msg('5547900009498', 'Teste F1 abrir: o dono respondendo depois.',
                                         c_d + interval '20 hours 1 minute', 'outbound', 'text', null);
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009417', 'Preciso de orçamento para trocar o inversor do motorhome',
                                        c_d + interval '20 hours');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '20 hours 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('4c', v_r, 'nova', 'recibo', null, 'cliente');
    if (pg_temp.retorno_f1_abrir_saida((v_r ->> 'abertura_id')::uuid, 'recibo')).enviar_em
         is distinct from c_d + interval '20 hours 2 minutes' then
      raise exception '4c: a saída humana do futuro mudou a carência';
    end if;
    -- 4d. Uma 2ª mensagem 40 s depois empurra o recibo ainda agendado (pela gravação da nova).
    perform pg_temp.retorno_f1_abrir_cliente('9418', '(47) 90000-9418');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009418', 'Preciso de orçamento para trocar o inversor do motorhome',
                                        c_d + interval '19 hours 40 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '19 hours 40 minutes 1 second');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    if (pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo')).enviar_em is distinct from c_d + interval '19 hours 42 minutes' then
      raise exception '4d: o 1º recibo não ficou em gravada + 2 min';
    end if;
    v_m2 := pg_temp.retorno_f1_abrir_msg('5547900009418', 'É um Sprinter 2018', c_d + interval '19 hours 40 minutes 40 seconds');
    v_r := public.retorno_abrir(v_m2, false, c_d + interval '19 hours 40 minutes 41 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('4d', v_r, 'estendida', 'recibo', null, 'cliente');
    v_ab := pg_temp.retorno_f1_abrir_caso(v_caso);
    if (pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo')).enviar_em is distinct from c_d + interval '19 hours 42 minutes 40 seconds'
       or v_ab.msgs <> 2 or v_ab.ultima_msg_id is distinct from v_m2
       or v_ab.ultima_gravada_em is distinct from c_d + interval '19 hours 40 minutes 40 seconds'
       or pg_temp.retorno_f1_abrir_n_saidas(v_caso) <> 1 then
      raise exception '4d: a 2ª mensagem não empurrou o recibo (nem estendeu o caso): %', to_jsonb(v_ab);
    end if;

    -- ── 5. Não pede ──────────────────────────────────────────────────────────────────────────────────
    -- 5a. "Obrigado!" sozinho: ignorada (agradecimento), só a linha da mensagem.
    perform pg_temp.retorno_f1_abrir_cliente('9419', '(47) 90000-9419');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009419', 'Obrigado!', c_d + interval '11 hours');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '11 hours 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('5a', v_r, 'ignorada', null, 'agradecimento');
    v_rm := pg_temp.retorno_f1_abrir_rm(v_m);
    if v_rm.whatsapp_message_id is null or v_rm.abertura_id is not null or v_rm.pede_resposta
       or exists (select 1 from public.retorno_aberturas ab where ab.chave = '00009419') then
      raise exception '5a: "Obrigado!" abriu caso (ou não deixou a linha): %', to_jsonb(v_rm);
    end if;
    -- 5b. Figurinha: ignorada.
    perform pg_temp.retorno_f1_abrir_cliente('9420', '(47) 90000-9420');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009420', null, c_d + interval '11 hours 10 minutes', 'inbound', 'sticker');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '11 hours 10 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('5b', v_r, 'ignorada', null, 'figurinha_ou_reacao');
    -- 5c. Robô (o mesmo texto longo 3 vezes): na 3ª as cópias anteriores também deixam de pedir, e o caso vira
    --     nada/robo; o recibo ainda agendado é cancelado (nivel_nada). A 2ª cópia, 60 min depois da 1ª, ainda
    --     pedia e contou 1 insistência; com o robô revelado a conta é refeita e volta a 0 (robô nunca insiste).
    perform pg_temp.retorno_f1_abrir_cliente('9421', '(47) 90000-9421');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009421', c_robo, c_d + interval '11 hours 20 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '11 hours 20 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('5c', v_r, 'nova', 'recibo', null, 'cliente');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    v_m2 := pg_temp.retorno_f1_abrir_msg('5547900009421', c_robo, c_d + interval '12 hours 20 minutes');
    v_r := public.retorno_abrir(v_m2, false, c_d + interval '12 hours 20 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('5c', v_r, 'estendida', 'recibo', null, 'cliente');
    if (pg_temp.retorno_f1_abrir_caso(v_caso)).insistencias <> 1 then
      raise exception '5c: a 2ª cópia, 60 min depois e ainda pedindo, não contou 1 insistência';
    end if;
    v_m3 := pg_temp.retorno_f1_abrir_msg('5547900009421', c_robo, c_d + interval '13 hours 20 minutes');
    v_r := public.retorno_abrir(v_m3, false, c_d + interval '13 hours 20 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('5c', v_r, 'estendida', 'nada', 'robo', 'cliente');
    if exists (select 1 from public.retorno_mensagens r
                where r.whatsapp_message_id in (v_m, v_m2, v_m3) and (r.pede_resposta or r.pede_motivo is distinct from 'robo'))
       or (pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo')).estado is distinct from 'cancelada'
       or (pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo')).motivo is distinct from 'nivel_nada' then
      raise exception '5c: o robô de texto repetido não virou nada/robo (ou o recibo agendado ficou)';
    end if;
    if (pg_temp.retorno_f1_abrir_caso(v_caso)).insistencias <> 0 then
      raise exception '5c: com o robô revelado, a insistência da 2ª cópia continuou contando: %',
        (pg_temp.retorno_f1_abrir_caso(v_caso)).insistencias;
    end if;
    -- 5c2. O mesmo texto longo 3 vezes, mas o recibo da 1ª já saiu ('enviada') e o adiamento está agendado: a
    --      revelação do robô não roda (o cliente ouviu a promessa), as duas primeiras cópias continuam pedindo, o
    --      caso continua recibo e o adiamento continua agendado (o aviso honesto garantido, §3).
    perform pg_temp.retorno_f1_abrir_cliente('9453', '(47) 90000-9453');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009453', c_robo, c_d + interval '11 hours 30 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '11 hours 30 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('5c2', v_r, 'nova', 'recibo', null, 'cliente');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    perform pg_temp.retorno_f1_abrir_decide((v_r ->> 'saida_id')::uuid, 'enviada', c_d + interval '11 hours 32 minutes', 'padrao');
    v_ab := pg_temp.retorno_f1_abrir_caso(v_caso);
    insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, client_id, modo,
                                       estado, enviar_em, dedupe_key)
    values (v_caso, 'adiamento', 'com_nome', 'retorno_adiamento', 'resposta_atrasada', v_ab.chave, v_ab.phone_normalized,
            v_ab.client_id, v_ab.modo, 'agendada', c_d + interval '18 hours 30 minutes', 'retorno:' || v_caso || ':adiamento');
    v_m2 := pg_temp.retorno_f1_abrir_msg('5547900009453', c_robo, c_d + interval '11 hours 40 minutes');
    v_r := public.retorno_abrir(v_m2, false, c_d + interval '11 hours 40 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('5c2', v_r, 'estendida', 'recibo', null, 'cliente');
    v_m3 := pg_temp.retorno_f1_abrir_msg('5547900009453', c_robo, c_d + interval '11 hours 50 minutes');
    v_r := public.retorno_abrir(v_m3, false, c_d + interval '11 hours 50 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('5c2', v_r, 'estendida', 'recibo', null, 'cliente');
    v_s := pg_temp.retorno_f1_abrir_saida(v_caso, 'adiamento');
    if v_s.estado is distinct from 'agendada' or v_s.motivo is not null
       or (pg_temp.retorno_f1_abrir_rm(v_m3)).pede_motivo is distinct from 'robo'
       or not (pg_temp.retorno_f1_abrir_rm(v_m)).pede_resposta or not (pg_temp.retorno_f1_abrir_rm(v_m2)).pede_resposta
       or (pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo')).estado is distinct from 'enviada' then
      raise exception '5c2: com o recibo já enviado, a revelação do robô cancelou o aviso honesto: %', to_jsonb(v_s);
    end if;

    -- 5d. Robô de 5 s: o pedido às 12:50; o recibo (com pergunta) decidido às 14:10:00 com a enviada automática, e
    --     a "mensagem de ausência" às 14:10:03, 80 min depois do pedido → pede_motivo 'robo', sem insistência (se
    --     pedisse, seria a 1ª: 60 min ou mais depois da anterior que pedia, sem saída humana) nem coleta; o caso
    --     continua recibo.
    insert into public.whatsapp_leads (phone_normalized, name) values ('5547900009422', 'Teste F1 abrir robô');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009422', c_pedido_c1, c_d + interval '12 hours 50 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '12 hours 50 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('5d', v_r, 'nova', 'recibo', null, 'numero_novo');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    v_s := pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo');
    if v_s.id is null then
      raise exception '5d: o pedido do número novo não ganhou recibo';
    end if;
    perform pg_temp.retorno_f1_abrir_decide(v_s.id, 'sombra', c_d + interval '14 hours 10 minutes', 'pergunta_modelo');
    perform pg_temp.retorno_f1_abrir_msg('5547900009422', 'Bom dia! Aqui é o assistente da HBR (mensagem automática).',
                                         c_d + interval '14 hours 10 minutes', 'outbound', 'text', '{"via": "retorno"}'::jsonb);
    v_m2 := pg_temp.retorno_f1_abrir_msg('5547900009422', 'Olá! No momento não estamos disponíveis. Responderemos assim que possível.',
                                         c_d + interval '14 hours 10 minutes 3 seconds');
    v_r := public.retorno_abrir(v_m2, false, c_d + interval '14 hours 10 minutes 4 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('5d', v_r, 'estendida', 'recibo', null, 'numero_novo');
    v_rm := pg_temp.retorno_f1_abrir_rm(v_m2);
    if v_rm.pede_resposta or v_rm.pede_motivo is distinct from 'robo'
       or (pg_temp.retorno_f1_abrir_caso(v_caso)).insistencias <> 0
       or pg_temp.retorno_f1_abrir_n_saidas(v_caso, 'coleta_numero_novo') <> 0 then
      raise exception '5d: o robô de 5 s pediu resposta, insistiu ou gerou coleta: %', to_jsonb(v_rm);
    end if;
    -- 5e. A resposta de verdade depois do recibo com pergunta: a 2ª mensagem da coleta (nome), gravada + 2 min.
    v_m3 := pg_temp.retorno_f1_abrir_msg('5547900009422', 'É uma Ducato 2019, tá aqui em Balneário',
                                         c_d + interval '14 hours 15 minutes');
    v_r := public.retorno_abrir(v_m3, false, c_d + interval '14 hours 15 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('5e', v_r, 'estendida', 'recibo', null, 'numero_novo');
    v_s := pg_temp.retorno_f1_abrir_saida(v_caso, 'coleta');
    v_ab := pg_temp.retorno_f1_abrir_caso(v_caso);
    if v_s.tipo is distinct from 'coleta_numero_novo' or v_s.variante is distinct from 'nome'
       or v_s.origem is distinct from 'retorno_coleta' or v_s.classe is distinct from 'resposta_imediata'
       or v_s.estado is distinct from 'agendada' or v_s.enviar_em is distinct from c_d + interval '14 hours 17 minutes'
       or v_ab.coleta ->> 'modelo' is distinct from 'Ducato 2019' or v_ab.coleta ->> 'ano' is distinct from '2019'
       or v_ab.coleta ->> 'tipo' is distinct from 'Motorhome' then
      raise exception '5e: a coleta depois da resposta saiu errada: % / %', to_jsonb(v_s), v_ab.coleta;
    end if;
    -- 5f. Na sombra a coleta nunca é ENVIADA: o "Ana." depois dela não vira nome nem cadastro (R-7).
    perform pg_temp.retorno_f1_abrir_decide(v_s.id, 'sombra', c_d + interval '14 hours 17 minutes');
    v_m4 := pg_temp.retorno_f1_abrir_msg('5547900009422', 'Ana.', c_d + interval '14 hours 20 minutes');
    v_r := public.retorno_abrir(v_m4, false, c_d + interval '14 hours 20 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('5f', v_r, 'estendida', 'recibo', null, 'numero_novo');
    if jsonb_typeof((pg_temp.retorno_f1_abrir_caso(v_caso)).coleta -> 'nome') is distinct from 'null'
       or pg_temp.retorno_f1_abrir_n_saidas(v_caso, 'cadastro_provisorio') <> 0 then
      raise exception '5f: o nome nasceu sem a coleta enviada: %', (pg_temp.retorno_f1_abrir_caso(v_caso)).coleta;
    end if;
    -- 5g. Com a coleta ENVIADA, o "Ana." vira coleta.nome, no caso e no lead, e agenda o cadastro provisório.
    insert into public.whatsapp_leads (phone_normalized, name) values ('5547900009444', 'Teste F1 abrir nome')
      returning id into v_lead44;
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009444', c_pedido_c1, c_d + interval '14 hours 30 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '14 hours 30 minutes 5 seconds');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    perform pg_temp.retorno_f1_abrir_decide((pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo')).id, 'sombra',
                                            c_d + interval '14 hours 32 minutes', 'pergunta_modelo');
    v_m2 := pg_temp.retorno_f1_abrir_msg('5547900009444', 'É uma Ducato 2019', c_d + interval '14 hours 35 minutes');
    v_r := public.retorno_abrir(v_m2, false, c_d + interval '14 hours 35 minutes 5 seconds');
    v_s := pg_temp.retorno_f1_abrir_saida(v_caso, 'coleta');
    if v_s.id is null then
      raise exception '5g: a coleta não nasceu';
    end if;
    perform pg_temp.retorno_f1_abrir_decide(v_s.id, 'enviada', c_d + interval '14 hours 37 minutes');
    v_m3 := pg_temp.retorno_f1_abrir_msg('5547900009444', 'Ana.', c_d + interval '14 hours 40 minutes');
    v_r := public.retorno_abrir(v_m3, false, c_d + interval '14 hours 40 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('5g', v_r, 'estendida', 'recibo', null, 'numero_novo');
    v_coleta := (pg_temp.retorno_f1_abrir_caso(v_caso)).coleta;
    select l.coleta into v_lead_coleta from public.whatsapp_leads l where l.id = v_lead44;
    v_s := pg_temp.retorno_f1_abrir_saida(v_caso, 'cadastro');
    if v_coleta ->> 'nome' is distinct from 'Ana' or v_coleta ->> 'tipo' is distinct from 'Motorhome'
       or v_coleta ->> 'modelo' is distinct from 'Ducato 2019' or v_coleta ->> 'servico' is distinct from 'instalacao, placa solar'
       or v_coleta ->> 'detalhes' is distinct from c_pedido_c1 or v_coleta ->> 'fonte' is distinct from 'retorno'
       or (v_lead_coleta - 'atualizado_em') is distinct from (v_coleta - 'atualizado_em')
       or v_s.tipo is distinct from 'cadastro_provisorio' or v_s.estado is distinct from 'agendada'
       or v_s.enviar_em is distinct from c_d + interval '14 hours 40 minutes 5 seconds'
       or v_s.origem is not null or v_s.classe is not null then
      raise exception '5g: o nome dito depois da coleta enviada não entrou (ou o cadastro não foi agendado): % / % / %',
        v_coleta, v_lead_coleta, to_jsonb(v_s);
    end if;

    -- ── 6. O que a agenda fez (a linha dela, sempre com p_consumida = false) ───────────────────────────
    -- 6a. Ligado + confirmou: consumida → agenda_consumiu.
    v_c23 := pg_temp.retorno_f1_abrir_cliente('9423', '(47) 90000-9423');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009423', 'Pode ser na quinta, confirmo', c_d + interval '15 hours');
    insert into public.agenda_cliente_respostas (client_id, whatsapp_message_id, recebida_em, tipo_msg, texto, intencao, efeito, modo)
      values (v_c23, v_m, c_d + interval '15 hours', 'text', 'Pode ser na quinta, confirmo', 'confirma', 'confirmou', 'ligado');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '15 hours 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('6a', v_r, 'nova', 'nada', 'agenda_consumiu', 'cliente');
    if not (pg_temp.retorno_f1_abrir_rm(v_m)).consumida then
      raise exception '6a: a mensagem confirmada pela agenda não ficou consumida';
    end if;
    -- 6b. Ao dono, com "quero falar com o Gustavo": passagem; o acorde nasce cancelado (agenda_ja_acordou); o
    --     recibo continua agendado.
    v_c24 := pg_temp.retorno_f1_abrir_cliente('9424', '(47) 90000-9424');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009424', 'quero falar com o Gustavo', c_d + interval '15 hours 10 minutes');
    insert into public.agenda_cliente_respostas (client_id, whatsapp_message_id, recebida_em, tipo_msg, texto, intencao, efeito, modo)
      values (v_c24, v_m, c_d + interval '15 hours 10 minutes', 'text', 'quero falar com o Gustavo', 'outro', 'ao_dono', 'ligado');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '15 hours 10 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('6b', v_r, 'nova', 'passagem', null, 'cliente');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    v_s := pg_temp.retorno_f1_abrir_saida(v_caso, 'acorde:' || v_m);
    v_rm := pg_temp.retorno_f1_abrir_rm(v_m);
    if v_s.tipo is distinct from 'acorde' or v_s.variante is distinct from 'passagem' or v_s.estado is distinct from 'cancelada'
       or v_s.motivo is distinct from 'agenda_ja_acordou'
       or (pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo')).estado is distinct from 'agendada'
       or not v_rm.agenda_ao_dono or v_rm.consumida
       or (pg_temp.retorno_f1_abrir_caso(v_caso)).passagem_em is distinct from c_d + interval '15 hours 10 minutes 5 seconds' then
      raise exception '6b: ao_dono não deu passagem com acorde cancelado e recibo agendado: % / %', to_jsonb(v_s), to_jsonb(v_rm);
    end if;
    -- 6c. Ambígua (para a agenda): o mesmo.
    v_c25 := pg_temp.retorno_f1_abrir_cliente('9425', '(47) 90000-9425');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009425', 'quero falar com o Gustavo', c_d + interval '15 hours 20 minutes');
    insert into public.agenda_cliente_respostas (client_id, whatsapp_message_id, recebida_em, tipo_msg, texto, intencao, efeito, modo)
      values (v_c25, v_m, c_d + interval '15 hours 20 minutes', 'text', 'quero falar com o Gustavo', 'outro', 'ambigua', 'ligado');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '15 hours 20 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('6c', v_r, 'nova', 'passagem', null, 'cliente');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    if (pg_temp.retorno_f1_abrir_saida(v_caso, 'acorde:' || v_m)).motivo is distinct from 'agenda_ja_acordou'
       or (pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo')).estado is distinct from 'agendada' then
      raise exception '6c: ambigua não deu passagem com acorde cancelado e recibo agendado';
    end if;
    -- 6d. Efeito sombra (a agenda só registrou): não consome; recibo normal.
    v_c26 := pg_temp.retorno_f1_abrir_cliente('9426', '(47) 90000-9426');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009426', 'Preciso remarcar a instalação do inversor', c_d + interval '15 hours 30 minutes');
    insert into public.agenda_cliente_respostas (client_id, whatsapp_message_id, recebida_em, tipo_msg, texto, intencao, efeito, modo)
      values (v_c26, v_m, c_d + interval '15 hours 30 minutes', 'text', 'Preciso remarcar a instalação do inversor', 'remarcar',
              'sombra', 'sombra');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '15 hours 30 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('6d', v_r, 'nova', 'recibo', null, 'cliente');
    if (pg_temp.retorno_f1_abrir_rm(v_m)).consumida then
      raise exception '6d: o efeito sombra consumiu a mensagem';
    end if;
    -- 6e. Confirmou, mas a agenda em modo sombra: não consome (só o ligado consome).
    v_c45 := pg_temp.retorno_f1_abrir_cliente('9445', '(47) 90000-9445');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009445', 'Confirmo a visita de quinta', c_d + interval '15 hours 50 minutes');
    insert into public.agenda_cliente_respostas (client_id, whatsapp_message_id, recebida_em, tipo_msg, texto, intencao, efeito, modo)
      values (v_c45, v_m, c_d + interval '15 hours 50 minutes', 'text', 'Confirmo a visita de quinta', 'confirma', 'confirmou', 'sombra');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '15 hours 50 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('6e', v_r, 'nova', 'recibo', null, 'cliente');
    -- 6f. p_consumida = true sem linha da agenda (os leitores de confirmação, conferência e revisão): agenda_consumiu.
    perform pg_temp.retorno_f1_abrir_cliente('9427', '(47) 90000-9427');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009427', 'A peça já chegou?', c_d + interval '15 hours 40 minutes');
    v_r := public.retorno_abrir(v_m, true, c_d + interval '15 hours 40 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('6f', v_r, 'nova', 'nada', 'agenda_consumiu', 'cliente');

    -- ── 7. Passagem ──────────────────────────────────────────────────────────────────────────────────
    -- 7a. Risco: passagem, recibo agendado com dados.risco (o P6 põe a linha L01) e o acorde agendado.
    perform pg_temp.retorno_f1_abrir_cliente('9428', '(47) 90000-9428');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009428', 'tá saindo fumaça do quadro', c_d + interval '16 hours');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '16 hours 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('7a', v_r, 'nova', 'passagem', null, 'cliente');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    v_s := pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo');
    v_s2 := pg_temp.retorno_f1_abrir_saida(v_caso, 'acorde:' || v_m);
    v_ab := pg_temp.retorno_f1_abrir_caso(v_caso);
    if v_s.estado is distinct from 'agendada' or v_s.dados -> 'risco' is distinct from 'true'::jsonb
       or v_s2.estado is distinct from 'agendada' or v_s2.variante is distinct from 'passagem'
       or v_s2.dados ->> 'por' is distinct from 'risco' or v_s2.enviar_em is distinct from c_d + interval '16 hours 5 seconds'
       or v_ab.intencao is distinct from 'risco' or v_ab.sinais -> 'risco' is distinct from 'true'::jsonb
       or v_ab.passagem_em is distinct from c_d + interval '16 hours 5 seconds' then
      raise exception '7a: o risco não deu passagem com recibo (risco) e acorde: % / % / %', to_jsonb(v_s), to_jsonb(v_s2), to_jsonb(v_ab);
    end if;
    -- 7b. LGPD (art. 18): passagem.
    perform pg_temp.retorno_f1_abrir_cliente('9429', '(47) 90000-9429');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009429', 'quero que apaguem meus dados pessoais', c_d + interval '16 hours 10 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '16 hours 10 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('7b', v_r, 'nova', 'passagem', null, 'cliente');
    if (pg_temp.retorno_f1_abrir_saida((v_r ->> 'abertura_id')::uuid, 'acorde:' || v_m)).dados ->> 'por' is distinct from 'lgpd'
       or (pg_temp.retorno_f1_abrir_caso((v_r ->> 'abertura_id')::uuid)).intencao is distinct from 'lgpd' then
      raise exception '7b: o pedido de LGPD não acordou como lgpd';
    end if;
    -- 7c. Três mensagens que pedem, 70 min entre elas, sem resposta: insistencias = 2 → passagem, com o acorde
    --     só na 3ª.
    perform pg_temp.retorno_f1_abrir_cliente('9430', '(47) 90000-9430');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009430', 'Preciso de orçamento para instalar bateria no motorhome',
                                        c_d + interval '16 hours 20 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '16 hours 20 minutes 5 seconds');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    v_m2 := pg_temp.retorno_f1_abrir_msg('5547900009430', 'Alguma novidade sobre o orçamento?', c_d + interval '17 hours 30 minutes');
    v_r := public.retorno_abrir(v_m2, false, c_d + interval '17 hours 30 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('7c', v_r, 'estendida', 'recibo', null, 'cliente');
    if (pg_temp.retorno_f1_abrir_caso(v_caso)).insistencias <> 1 then
      raise exception '7c: a 2ª mensagem 70 min depois não contou como insistência';
    end if;
    v_m3 := pg_temp.retorno_f1_abrir_msg('5547900009430', 'Oi, e o orçamento do motorhome?', c_d + interval '18 hours 40 minutes');
    v_r := public.retorno_abrir(v_m3, false, c_d + interval '18 hours 40 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('7c', v_r, 'estendida', 'passagem', null, 'cliente');
    if (pg_temp.retorno_f1_abrir_caso(v_caso)).insistencias <> 2
       or pg_temp.retorno_f1_abrir_n_saidas(v_caso, 'acorde') <> 1
       or (pg_temp.retorno_f1_abrir_saida(v_caso, 'acorde:' || v_m3)).dados ->> 'por' is distinct from 'insistencia' then
      raise exception '7c: 2 insistências não deram passagem com um acorde na 3ª';
    end if;
    --     Um "??" 1 min depois da 3ª pede resposta, mas não é insistência: o caso continua passagem, a conta
    --     continua 2 e não nasce outro acorde (o acorde é da mensagem que causou a passagem).
    v_m4 := pg_temp.retorno_f1_abrir_msg('5547900009430', '??', c_d + interval '18 hours 41 minutes');
    v_r := public.retorno_abrir(v_m4, false, c_d + interval '18 hours 41 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('7c', v_r, 'estendida', 'passagem', null, 'cliente');
    if not (pg_temp.retorno_f1_abrir_rm(v_m4)).pede_resposta
       or (pg_temp.retorno_f1_abrir_caso(v_caso)).insistencias <> 2
       or pg_temp.retorno_f1_abrir_n_saidas(v_caso, 'acorde') <> 1
       or (pg_temp.retorno_f1_abrir_saida(v_caso, 'acorde:' || v_m4)).id is not null then
      raise exception '7c: a mensagem 1 min depois da 2ª insistência ganhou acorde (ou mudou a conta)';
    end if;
    -- 7d. Mensagem nova que pede, num caso VENCIDO (o fim do dia já saiu): passagem, acorde, nenhum recibo novo.
    perform pg_temp.retorno_f1_abrir_cliente('9441', '(47) 90000-9441');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009441', 'Preciso de orçamento para o gerador da lancha', c_d + interval '19 hours');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '19 hours 5 seconds');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    perform pg_temp.retorno_f1_abrir_decide((pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo')).id, 'sombra',
                                            c_d + interval '19 hours 2 minutes', 'padrao');
    update public.retorno_aberturas
       set estado = 'vencida', recibo_em = c_d + interval '19 hours 2 minutes', prometido_ate = c_d + interval '19 hours 20 minutes',
           prometido_fonte = 'fechamento', faixa = 'meio', fim_do_dia_em = c_d + interval '19 hours 15 minutes'
     where id = v_caso;
    v_m2 := pg_temp.retorno_f1_abrir_msg('5547900009441', 'Alguém pode me responder?', c_d + interval '19 hours 25 minutes');
    v_r := public.retorno_abrir(v_m2, false, c_d + interval '19 hours 25 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('7d', v_r, 'estendida', 'passagem', null, 'cliente');
    if (pg_temp.retorno_f1_abrir_saida(v_caso, 'acorde:' || v_m2)).dados ->> 'por' is distinct from 'vencida'
       or (pg_temp.retorno_f1_abrir_saida(v_caso, 'acorde:' || v_m2)).estado is distinct from 'agendada'
       or pg_temp.retorno_f1_abrir_n_saidas(v_caso, 'recibo_cliente') <> 1
       or (pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo')).estado is distinct from 'sombra'
       or pg_temp.retorno_f1_abrir_n_saidas(v_caso, 'acorde') <> 1 then
      raise exception '7d: a mensagem nova no caso vencido não deu passagem só com o acorde';
    end if;
    -- 7d2. A promessa do dono venceu sem resposta (o vigia marcou o caso vencido) e o cliente escreve de novo:
    --      passagem com acorde, e NENHUM recibo (o caso não tinha recibo: nada de "até as X" num caso vencido).
    perform pg_temp.retorno_f1_abrir_cliente('9447', '(47) 90000-9447');
    insert into public.whatsapp_acompanhamentos (phone_normalized, modo, lembrar_em, promessa, status, created_at)
      values ('5547900009447', 'promessa', c_d + interval '13 hours', 'Teste F1 abrir: o dono prometeu responder', 'ativo',
              c_d + interval '11 hours');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009447', 'Preciso do orçamento da bateria da lancha', c_d + interval '12 hours 30 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '12 hours 30 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('7d2', v_r, 'nova', 'nada', 'promessa_do_dono', 'cliente');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    update public.retorno_aberturas set estado = 'vencida' where id = v_caso;
    v_m2 := pg_temp.retorno_f1_abrir_msg('5547900009447', 'Alguém viu meu orçamento?', c_d + interval '13 hours 30 minutes');
    v_r := public.retorno_abrir(v_m2, false, c_d + interval '13 hours 30 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('7d2', v_r, 'estendida', 'passagem', null, 'cliente');
    v_ab := pg_temp.retorno_f1_abrir_caso(v_caso);
    if pg_temp.retorno_f1_abrir_n_saidas(v_caso) <> 1 or pg_temp.retorno_f1_abrir_n_saidas(v_caso, 'acorde') <> 1
       or (pg_temp.retorno_f1_abrir_saida(v_caso, 'acorde:' || v_m2)).dados ->> 'por' is distinct from 'vencida'
       or v_r ->> 'saida_id' is not null
       or v_ab.prometido_ate is distinct from c_d + interval '13 hours' or v_ab.prometido_fonte is distinct from 'dono' then
      raise exception '7d2: o caso vencido da promessa do dono ganhou recibo (ou perdeu o que foi prometido): %', to_jsonb(v_ab);
    end if;
    -- 7d3. A mesma promessa vencida (13:00), mas o cliente escreve às 13:00:30, ANTES de o vigia marcar o caso (o
    --      caso ainda 'aberta' e a promessa ainda 'ativo'): já conta como vencido → passagem com acorde, nenhum
    --      recibo, e o relógio da promessa fica (prometido_ate, prometido_fonte, faixa) para o vigia marcar.
    perform pg_temp.retorno_f1_abrir_cliente('9450', '(47) 90000-9450');
    insert into public.whatsapp_acompanhamentos (phone_normalized, modo, lembrar_em, promessa, status, created_at)
      values ('5547900009450', 'promessa', c_d + interval '13 hours', 'Teste F1 abrir: o dono prometeu responder', 'ativo',
              c_d + interval '11 hours');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009450', 'Preciso do orçamento da bateria da lancha', c_d + interval '12 hours 40 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '12 hours 40 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('7d3', v_r, 'nova', 'nada', 'promessa_do_dono', 'cliente');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    v_m2 := pg_temp.retorno_f1_abrir_msg('5547900009450', 'Alguém viu meu orçamento?', c_d + interval '13 hours 30 seconds');
    v_r := public.retorno_abrir(v_m2, false, c_d + interval '13 hours 35 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('7d3', v_r, 'estendida', 'passagem', null, 'cliente');
    v_ab := pg_temp.retorno_f1_abrir_caso(v_caso);
    if pg_temp.retorno_f1_abrir_n_saidas(v_caso) <> 1 or pg_temp.retorno_f1_abrir_n_saidas(v_caso, 'acorde') <> 1
       or (pg_temp.retorno_f1_abrir_saida(v_caso, 'acorde:' || v_m2)).dados ->> 'por' is distinct from 'vencida'
       or (pg_temp.retorno_f1_abrir_saida(v_caso, 'acorde:' || v_m2)).estado is distinct from 'agendada'
       or v_r ->> 'saida_id' is not null or v_ab.estado is distinct from 'aberta'
       or v_ab.prometido_ate is distinct from c_d + interval '13 hours' or v_ab.prometido_fonte is distinct from 'dono'
       or v_ab.faixa is distinct from 'promessa_dono' then
      raise exception '7d3: a promessa do dono que passou, antes do vigia, deu recibo (ou apagou o relógio): %', to_jsonb(v_ab);
    end if;
    -- 7e. Com uma resposta humana entre as duas mensagens, a 2ª não é insistência.
    perform pg_temp.retorno_f1_abrir_cliente('9443', '(47) 90000-9443');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009443', 'Preciso de orçamento do carregador da lancha', c_d + interval '21 hours');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '21 hours 5 seconds');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    perform pg_temp.retorno_f1_abrir_msg('5547900009443', 'Oi! Vejo amanhã cedo e te passo o valor.', c_d + interval '21 hours 30 minutes',
                                         'outbound', 'text', '{"data": {"key": {"fromMe": true}}}'::jsonb);
    v_m2 := pg_temp.retorno_f1_abrir_msg('5547900009443', 'E aí, alguma novidade?', c_d + interval '22 hours 10 minutes');
    v_r := public.retorno_abrir(v_m2, false, c_d + interval '22 hours 10 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('7e', v_r, 'estendida', 'recibo', null, 'cliente');
    if (pg_temp.retorno_f1_abrir_caso(v_caso)).insistencias <> 0 then
      raise exception '7e: a mensagem depois da resposta humana contou como insistência';
    end if;
    -- 7f. "URGENTE" depois do recibo decidido: a saída urgente (sem acorde), gravada + 2 min.
    perform pg_temp.retorno_f1_abrir_cliente('9446', '(47) 90000-9446');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009446', 'Preciso de orçamento para instalar tomada no motorhome',
                                        c_d + interval '12 hours');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '12 hours 5 seconds');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    perform pg_temp.retorno_f1_abrir_decide((pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo')).id, 'sombra',
                                            c_d + interval '12 hours 2 minutes', 'outro_dia');
    v_m2 := pg_temp.retorno_f1_abrir_msg('5547900009446', 'URGENTE', c_d + interval '12 hours 10 minutes');
    v_r := public.retorno_abrir(v_m2, false, c_d + interval '12 hours 10 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('7f', v_r, 'estendida', 'recibo', null, 'cliente');
    v_s := pg_temp.retorno_f1_abrir_saida(v_caso, 'urgente');
    if v_s.tipo is distinct from 'urgente' or v_s.variante is distinct from 'sem_acorde' or v_s.estado is distinct from 'agendada'
       or v_s.origem is distinct from 'retorno_recibo' or v_s.classe is distinct from 'resposta_imediata'
       or v_s.enviar_em is distinct from c_d + interval '12 hours 12 minutes' then
      raise exception '7f: URGENTE depois do recibo não deu a saída urgente: %', to_jsonb(v_s);
    end if;
    -- 7f2. "URGENTE" com o recibo ainda agendado (não decidido): nenhuma saída urgente; a rajada só empurra o recibo.
    perform pg_temp.retorno_f1_abrir_cliente('9448', '(47) 90000-9448');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009448', 'Preciso de orçamento para instalar tomada no motorhome',
                                        c_d + interval '12 hours 40 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '12 hours 40 minutes 5 seconds');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    v_m2 := pg_temp.retorno_f1_abrir_msg('5547900009448', 'URGENTE', c_d + interval '12 hours 41 minutes');
    v_r := public.retorno_abrir(v_m2, false, c_d + interval '12 hours 41 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('7f2', v_r, 'estendida', 'recibo', null, 'cliente');
    if pg_temp.retorno_f1_abrir_n_saidas(v_caso, 'urgente') <> 0
       or (pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo')).enviar_em is distinct from c_d + interval '12 hours 43 minutes' then
      raise exception '7f2: URGENTE antes do recibo decidido deu saída urgente (ou não empurrou o recibo)';
    end if;

    -- ── 8. Promessa do dono ──────────────────────────────────────────────────────────────────────────
    -- 8a. Promessa ativa, criada antes e ainda por vencer: nada/promessa_do_dono; o relógio adota a promessa.
    perform pg_temp.retorno_f1_abrir_cliente('9431', '(47) 90000-9431');
    insert into public.whatsapp_acompanhamentos (phone_normalized, modo, lembrar_em, promessa, status, created_at)
      values ('5547900009431', 'promessa', c_d + interval '20 hours', 'Teste F1 abrir: o dono prometeu responder', 'ativo',
              c_d + interval '16 hours');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009431', 'Preciso do orçamento do inversor', c_d + interval '17 hours');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '17 hours 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('8a', v_r, 'nova', 'nada', 'promessa_do_dono', 'cliente');
    v_ab := pg_temp.retorno_f1_abrir_caso((v_r ->> 'abertura_id')::uuid);
    if v_ab.prometido_ate is distinct from c_d + interval '20 hours' or v_ab.prometido_fonte is distinct from 'dono'
       or v_ab.faixa is distinct from 'promessa_dono' or pg_temp.retorno_f1_abrir_n_saidas(v_ab.id) <> 0 then
      raise exception '8a: a promessa do dono não virou o relógio (ou o recibo saiu): %', to_jsonb(v_ab);
    end if;
    -- 8b. A mesma promessa criada DEPOIS de p_agora: ignorada; recibo normal.
    perform pg_temp.retorno_f1_abrir_cliente('9432', '(47) 90000-9432');
    insert into public.whatsapp_acompanhamentos (phone_normalized, modo, lembrar_em, promessa, status, created_at)
      values ('5547900009432', 'promessa', c_d + interval '20 hours', 'Teste F1 abrir: o dono prometeu responder', 'ativo',
              c_d + interval '17 hours 20 minutes');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009432', 'Preciso do orçamento do inversor', c_d + interval '17 hours 10 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '17 hours 10 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('8b', v_r, 'nova', 'recibo', null, 'cliente');
    if (pg_temp.retorno_f1_abrir_caso((v_r ->> 'abertura_id')::uuid)).prometido_ate is not null then
      raise exception '8b: a promessa do futuro foi adotada';
    end if;

    -- ── 9. PARAR ─────────────────────────────────────────────────────────────────────────────────────
    -- 9a. "PARAR" de um cliente: o gatilho da F0b grava o opt-out; nada/parar e UMA saída parar.
    v_c33 := pg_temp.retorno_f1_abrir_cliente('9433', '(47) 90000-9433');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009433', 'PARAR', c_d + interval '17 hours 20 minutes');
    if not exists (select 1 from public.whatsapp_blocked_numbers b
                    where b.phone_normalized = '5547900009433' and b.tipo = 'opt_out') then
      raise exception '9a: o gatilho da F0b não gravou o opt-out do PARAR';
    end if;
    v_r := public.retorno_abrir(v_m, false, c_d + interval '17 hours 20 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('9a', v_r, 'nova', 'nada', 'parar', 'cliente');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    v_r := public.retorno_abrir(v_m, false, c_d + interval '17 hours 20 minutes 10 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('9a', v_r, 'repetida', 'nada', 'parar', 'cliente');
    v_s := pg_temp.retorno_f1_abrir_saida(v_caso, 'parar');
    if pg_temp.retorno_f1_abrir_n_saidas(v_caso) <> 1 or v_s.tipo is distinct from 'parar' or v_s.estado is distinct from 'agendada'
       or v_s.origem is distinct from 'retorno_recibo' or v_s.classe is distinct from 'resposta_imediata'
       or v_s.client_id is distinct from v_c33 or v_s.enviar_em is distinct from c_d + interval '17 hours 22 minutes'
       or (pg_temp.retorno_f1_abrir_caso(v_caso)).intencao is distinct from 'parar' then
      raise exception '9a: o PARAR do cliente não deu uma saída parar: %', to_jsonb(v_s);
    end if;
    -- 9b. "Pare" de um fornecedor: nada/parar e nenhuma saída (o opt-out da F0b basta).
    insert into public.suppliers (name, phone, active) values ('Teste F1 abrir 9434 fornecedor', '(47) 90000-9434', true);
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009434', 'Pare', c_d + interval '17 hours 30 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '17 hours 30 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('9b', v_r, 'nova', 'nada', 'parar', 'fornecedor');
    if pg_temp.retorno_f1_abrir_n_saidas((v_r ->> 'abertura_id')::uuid) <> 0 then
      raise exception '9b: o fornecedor ganhou a confirmação do PARAR';
    end if;
    -- 9c. "SAIR" de um número novo que se apresentou como vendedor: nenhuma saída.
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009435', c_vendedor, c_d + interval '17 hours 40 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '17 hours 40 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('9c', v_r, 'nova', 'nada', 'vendedor', 'numero_novo');
    v_m2 := pg_temp.retorno_f1_abrir_msg('5547900009435', 'SAIR', c_d + interval '17 hours 45 minutes');
    v_r := public.retorno_abrir(v_m2, false, c_d + interval '17 hours 45 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('9c', v_r, 'estendida', 'nada', 'parar', 'numero_novo');
    if pg_temp.retorno_f1_abrir_n_saidas((v_r ->> 'abertura_id')::uuid) <> 0 then
      raise exception '9c: o vendedor ganhou a confirmação do PARAR';
    end if;
    -- 9d. PARAR dito por áudio: o '[audio]' do cliente abre o caso com o recibo agendado; a transcrição troca o corpo
    --     para '🎤 Parar' (UPDATE), que o gatilho AFTER INSERT da F0b não vê: não há opt-out gravado. A confirmação
    --     mentiria ("não te mando mais") e o pedido se perderia: o caso vai a nada/parar_largo ("Para conferir"), o
    --     recibo é cancelado e não nasce saída parar.
    perform pg_temp.retorno_f1_abrir_cliente('9451', '(47) 90000-9451');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009451', '[audio]', c_d + interval '17 hours 50 minutes', 'inbound', 'audio');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '17 hours 50 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('9d', v_r, 'nova', 'recibo', null, 'cliente');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    update public.whatsapp_messages set body = '🎤 Parar' where id = v_m;
    v_r := public.retorno_abrir(v_m, false, c_d + interval '17 hours 51 minutes');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('9d', v_r, 'reavaliada', 'nada', 'parar_largo', 'cliente');
    v_s := pg_temp.retorno_f1_abrir_saida(v_caso, 'recibo');
    if not coalesce(((pg_temp.retorno_f1_abrir_rm(v_m)).sinais ->> 'parar')::boolean, false)
       or pg_temp.retorno_f1_abrir_n_saidas(v_caso, 'parar') <> 0
       or v_s.estado is distinct from 'cancelada' or v_s.motivo is distinct from 'nivel_nada'
       or exists (select 1 from public.whatsapp_blocked_numbers b where b.phone_normalized = '5547900009451') then
      raise exception '9d: o PARAR por áudio, sem opt-out gravado, ganhou confirmação (ou o recibo ficou): %', to_jsonb(v_s);
    end if;

    -- ── 10. PARAR por extenso ────────────────────────────────────────────────────────────────────────
    -- 10a. "pare de me mandar mensagem": nada/parar_largo, sem saída e sem opt-out novo.
    perform pg_temp.retorno_f1_abrir_cliente('9436', '(47) 90000-9436');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009436', 'pare de me mandar mensagem', c_d + interval '18 hours');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '18 hours 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('10a', v_r, 'nova', 'nada', 'parar_largo', 'cliente');
    if pg_temp.retorno_f1_abrir_n_saidas((v_r ->> 'abertura_id')::uuid) <> 0
       or exists (select 1 from public.whatsapp_blocked_numbers b where b.phone_normalized = '5547900009436') then
      raise exception '10a: o PARAR por extenso ganhou saída ou opt-out';
    end if;
    -- 10b. "nunca mais funcionou o inversor" não é pedido de parar: recibo normal.
    perform pg_temp.retorno_f1_abrir_cliente('9437', '(47) 90000-9437');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009437', 'nunca mais funcionou o inversor', c_d + interval '18 hours 10 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '18 hours 10 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('10b', v_r, 'nova', 'recibo', null, 'cliente');
    -- 10c. O PARAR por extenso vale para o caso inteiro: o "?" 3 min depois pede resposta, mas o caso continua
    --      nada/parar_largo (na linha "Para conferir"), sem recibo para quem pediu para parar e sem opt-out.
    perform pg_temp.retorno_f1_abrir_cliente('9452', '(47) 90000-9452');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009452', 'pare de me mandar mensagem', c_d + interval '18 hours 50 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '18 hours 50 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('10c', v_r, 'nova', 'nada', 'parar_largo', 'cliente');
    v_caso := (v_r ->> 'abertura_id')::uuid;
    v_m2 := pg_temp.retorno_f1_abrir_msg('5547900009452', '?', c_d + interval '18 hours 53 minutes');
    v_r := public.retorno_abrir(v_m2, false, c_d + interval '18 hours 53 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('10c', v_r, 'estendida', 'nada', 'parar_largo', 'cliente');
    if not (pg_temp.retorno_f1_abrir_rm(v_m2)).pede_resposta or pg_temp.retorno_f1_abrir_n_saidas(v_caso) <> 0
       or exists (select 1 from public.whatsapp_blocked_numbers b where b.phone_normalized = '5547900009452') then
      raise exception '10c: o "?" depois do PARAR por extenso tirou o caso de parar_largo (ou deu recibo/opt-out)';
    end if;

    -- ── 11. Opt-out que volta × spam ─────────────────────────────────────────────────────────────────
    -- 11a. Cliente com opt-out (tipo 'opt_out', de ontem) escreve de novo: nada/opt_out (vai a "Para conferir").
    perform pg_temp.retorno_f1_abrir_cliente('9438', '(47) 90000-9438');
    insert into public.whatsapp_blocked_numbers (phone_normalized, reason, tipo, created_at)
      values ('5547900009438', 'Teste F1 abrir', 'opt_out', c_d - interval '1 day');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009438', 'preciso falar do orçamento', c_d + interval '18 hours 20 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '18 hours 20 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('11a', v_r, 'nova', 'nada', 'opt_out', 'cliente');
    -- 11b. Número só na lista de spam: nada/bloqueado.
    perform pg_temp.retorno_f1_abrir_cliente('9439', '(47) 90000-9439');
    insert into public.whatsapp_blocked_numbers (phone_normalized, reason, tipo, created_at)
      values ('5547900009439', 'Teste F1 abrir', 'spam', c_d - interval '1 day');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009439', 'preciso falar do orçamento', c_d + interval '18 hours 30 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '18 hours 30 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('11b', v_r, 'nova', 'nada', 'bloqueado', 'cliente');

    -- ── 12. Erro ─────────────────────────────────────────────────────────────────────────────────────
    -- 12a. Uma mensagem que não existe: ok, ignorada.
    v_r := public.retorno_abrir(gen_random_uuid(), false, c_d + interval '19 hours');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('12a', v_r, 'ignorada', null, 'sem_mensagem');
    -- 12b. Com _retorno_sinais fora (renomeada num sub-bloco desfeito): {"ok": false} e o erro registrado; nada fica.
    perform pg_temp.retorno_f1_abrir_cliente('9440', '(47) 90000-9440');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009440', 'Preciso de orçamento para o ar condicionado', c_d + interval '19 hours 20 minutes');
    begin
      alter function public._retorno_sinais(text, text) rename to _retorno_sinais_f1_fora;
      v_err := public.retorno_abrir(v_m, false, c_d + interval '19 hours 20 minutes 5 seconds');
      select count(*) into v_err_logs from public.app_error_logs l
       where l.context = 'retorno' and l.action = 'abrir' and l.source = 'db' and l.last_seen_at = now();
      v_err_rm := exists (select 1 from public.retorno_mensagens r where r.whatsapp_message_id = v_m)
                  or exists (select 1 from public.retorno_aberturas ab where ab.chave = '00009440');
      raise exception 'desfaz' using errcode = 'P0001';
    exception when sqlstate 'P0001' then
      if sqlerrm <> 'desfaz' then raise; end if;
    end;
    if jsonb_typeof(v_err) is distinct from 'object'
       or (select array_agg(k order by k collate "C") from jsonb_object_keys(v_err) k) is distinct from array['erro', 'ok']
       or v_err -> 'ok' is distinct from 'false'::jsonb or coalesce(v_err ->> 'erro', '') = '' then
      raise exception '12b: com _retorno_sinais fora, retorno_abrir não devolveu {"ok": false, "erro"}: %', v_err;
    end if;
    if coalesce(v_err_logs, 0) < 1 then
      raise exception '12b: o erro de retorno_abrir não foi para app_error_logs (context retorno, action abrir, last_seen_at = now())';
    end if;
    if v_err_rm then
      raise exception '12b: o erro deixou caso ou linha da mensagem pela metade';
    end if;
    if to_regprocedure('public._retorno_sinais(text, text)') is null then
      raise exception '12b: a renomeação de _retorno_sinais não foi desfeita';
    end if;
    -- 12c. A mensagem seguinte (a mesma, com a função de volta) segue: o erro não travou nada.
    v_r := public.retorno_abrir(v_m, false, c_d + interval '19 hours 20 minutes 10 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('12c', v_r, 'nova', 'recibo', null, 'cliente');

    -- ── 13. Futuro: a mensagem gravada depois de p_agora é ignorada (só o replay chega a isso) ─────────
    perform pg_temp.retorno_f1_abrir_cliente('9442', '(47) 90000-9442');
    v_m := pg_temp.retorno_f1_abrir_msg('5547900009442', 'Preciso de orçamento para a bomba do barco', c_d + interval '19 hours 10 minutes');
    v_r := public.retorno_abrir(v_m, false, c_d + interval '19 hours 9 minutes 59 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('13', v_r, 'ignorada', null, 'futura');
    if exists (select 1 from public.retorno_mensagens r where r.whatsapp_message_id = v_m) then
      raise exception '13: a mensagem do futuro deixou linha';
    end if;
    v_r := public.retorno_abrir(v_m, false, c_d + interval '19 hours 10 minutes 5 seconds');
    v_n := v_n + pg_temp.retorno_f1_abrir_confere('13', v_r, 'nova', 'recibo', null, 'cliente');

    v_chegou := true;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;
  if not v_chegou then
    raise exception '0e: o arranjo não chegou ao fim';
  end if;
  if exists (select 1 from public.retorno_aberturas ab where ab.chave like '000094%')
     or exists (select 1 from public.whatsapp_messages w where w.phone_normalized like '55479000094%')
     or (select to_jsonb(c) from public.retorno_config c where c.id) is distinct from v_cfg_antes
     or to_regprocedure('public._retorno_sinais(text, text)') is null then
    raise exception '0f: o arranjo não foi desfeito';
  end if;

  insert into _bancada (arquivo, ok, numeros)
  values ('retorno_f1_abrir', true, jsonb_build_object('respostas_conferidas', v_n, 'mp_real', v_mp));
end
$abrir$;

select arquivo, ok, numeros from _bancada order by em;
rollback;

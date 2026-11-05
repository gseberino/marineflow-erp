-- Retorno F1 (P9): o resumo do dia (retorno_resumo_do_dia, contrato C-RESUMO), a calibração (retorno_calibracao), a
-- lista da sombra (retorno_sombra_lista) e o próximo evento do replay (_retorno_proximo_evento),
-- 20261116101000_retorno_f1_resumo.sql.
--   0. as funções e as views (volatilidade, SECURITY DEFINER com search_path, security_invoker, fechadas a anon e
--      authenticated) e as premissas: a linha de configuração, os números de teste livres e nenhum caso, saída ou
--      alongamento do retorno antes de 14/11/2026 (o resumo lê o banco inteiro);
--   1. manhã (ter 10/11 07:30), quem espera: o cliente vencido ontem (topo_dia = hoje), o número novo prometido hoje até
--      10h com coleta.nome mas a coleta 2 só em sombra ("número novo"), o recibo da noite ainda agendado com a promessa
--      guardada, o ambíguo e 5 sem prazo hoje → os 4 com prazo hoje vêm TODOS e em ordem (vencido, depois por prazo), dos
--      sem prazo vêm 3 com esperando_mais = 2; os cumpridos, o caso 'nada' e o caso do futuro ficam fora; com a coleta 2
--      enviada, o rótulo é o nome dito, só a partir de quando ela saiu; um dados.prazo ilegível não derruba a manhã;
--   2. manhã, "Para conferir": um parar_largo (o mais recente do número), um opt_out e um recibo cancelado por
--      atraso_longo, até 3, e o 4º em conferir_mais; o de mais de 24 h, o cancelado por outro motivo e o do futuro ficam
--      fora;
--  2b. "Para conferir", a janela e a repetição: vale a última mensagem do caso, não a 1ª; o que entra de sáb a dom chega
--      na manhã de segunda e não repete na de terça; o de domingo com feriado na segunda chega na manhã de terça; o que
--      a manhã de sábado mostrou a de segunda não repete; o mesmo número com dois motivos traz os dois;
--   3. fechamento (ter 10/11 17:30): esperando = os prometidos até 19h sem conteúdo e os vencidos (todos); recebidos, no
--      prazo e adiados dos abertos hoje; sem_palavra × na_queda (o fim do dia recusado por so_reativo conta à parte; o
--      que teve o fim do dia não conta; o caso que virou 'nada' depois do recibo não conta em nenhum dos dois; a terça
--      conta desde o fechamento de sexta, porque a segunda é revisão: os vencimentos de sex 19h e de seg 10h e 19h, mesmo
--      já fechados; o que venceu antes do fechamento de sexta já contou; a quarta não repete o que a terça contou); o
--      turno da tarde do banco igual ao turnoDaTarde; 2 em sombra por papel (fora o acorde, a de ontem e a do futuro) e
--      1 cancelada/respondida_pelo_dono; "ouviu" e o segundo prazo do adiado;
--   4. alongadas só numa sexta (os 7 dias, fora o antigo e o do futuro); turno desconhecido = {"erro": "turno"}; sem a
--      linha de configuração, modo 'desligado';
--   5. retorno_calibracao: as faixas com wilson_inferior entre 0 e 1 (pela diferença antes e depois do arranjo; com a
--      faixa vazia antes, os valores exatos: 80%, Wilson 0,3755, mediana 150 min, p80 18:00);
--   6. retorno_sombra_lista: o trecho (140 caracteres da 1ª mensagem), o rótulo e o que entra (sombra e enviada, fora
--      acorde); 42501 para anon e authenticated nas duas views e no resumo, e o service_role lê os três;
--   7. _retorno_proximo_evento: a agendada, o acorde e o adiamento do relógio, a próxima 04:00, e o caso do futuro não
--      conta.
-- Em toda seção, nenhum campo do resumo traz o corpo de uma mensagem (as sintéticas têm a marca CORPO-SECRETO-F1R).
-- Cadastros e mensagens SINTÉTICOS de 55479000088xx; datas de 29/10 a 13/11/2026 (Brasília, sem horário de verão), ANTES
-- do deploy de 16/11 de propósito: o resumo só enxerga o que foi gravado até p_agora, e as linhas reais do retorno (que
-- só nascem a partir de 16/11) ficam fora sem que nada real seja tocado. A calibração (view, sem p_agora) é conferida
-- pela DIFERENÇA antes e depois do arranjo, com casos de outubro de 2026.
-- Run (só pela bancada): npx supabase@2.111.0 db query --linked -f supabase/tests/retorno_f1_resumo.sql
-- Termina em ROLLBACK: nada fica gravado. Cada seção desfaz o próprio arranjo (sub-bloco que termina em 'desfaz').
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- Um cliente sintético, pelo WhatsApp do cadastro; o id.
create or replace function pg_temp.retorno_f1_resumo_cliente(p_nome text, p_whatsapp text, p_tipo text default 'individual')
returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values (p_tipo, p_nome, p_whatsapp) returning id
$f$;

-- Um caso sintético 'aberta' em sombra (sem passar pelo retorno_abrir), com a 1ª mensagem; o id. O resto do caso
-- (promessa, estado, topo…) a seção grava com update.
create or replace function pg_temp.retorno_f1_resumo_caso(p_fone text, p_papel text, p_aberta timestamptz,
                                                         p_nivel text default 'recibo', p_motivo text default null,
                                                         p_client uuid default null, p_clientes uuid[] default '{}'::uuid[],
                                                         p_gravada timestamptz default null)
returns uuid
language plpgsql as $f$
declare
  v_msg uuid;
  v_id uuid;
  v_gravada timestamptz := coalesce(p_gravada, p_aberta);
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload,
                                        hora_real, occurred_at)
  values ('inbound', p_fone, 'text', 'CORPO-SECRETO-F1R: preciso de um orçamento para trocar a bateria do motorhome',
          'received', '{"data": {}}'::jsonb, p_aberta, v_gravada)
  returning id into v_msg;
  insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, clientes, primeira_msg_id,
                                        ultima_msg_id, aberta_em, gravada_em, ultima_em, ultima_gravada_em, atraso_gravacao,
                                        nivel, motivo, tipo_recibo, estado, modo)
  values (public._agenda_chave_telefone(p_fone), p_fone, '47', p_papel,
          jsonb_build_object('papel', p_papel, 'clientes', to_jsonb(coalesce(p_clientes, '{}'::uuid[]))),
          p_client, coalesce(p_clientes, '{}'::uuid[]), v_msg, v_msg, p_aberta, v_gravada, p_aberta, v_gravada,
          v_gravada - p_aberta, p_nivel, case when p_nivel = 'nada' then coalesce(p_motivo, 'nao_pede_resposta') end,
          case when p_nivel <> 'nada' then case p_papel when 'cliente_ambiguo' then 'recibo_ambiguo'
                                                        when 'numero_novo' then 'recibo_numero_novo'
                                                        else 'recibo_cliente' end end,
          'aberta', 'sombra')
  returning id into v_id;
  return v_id;
end $f$;

-- Uma saída sintética do caso (origem e classe pela tabela da seção 6.3); o id. A agendada pede p_enviar.
create or replace function pg_temp.retorno_f1_resumo_saida(p_caso uuid, p_tipo text, p_estado text, p_decidida timestamptz,
                                                          p_motivo text default null, p_dados jsonb default '{}'::jsonb,
                                                          p_enviar timestamptz default null)
returns uuid
language sql as $f$
  insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, client_id, modo,
                                     estado, motivo, enviar_em, decidida_em, enviada_em, texto, dados, dedupe_key)
  select a.id, p_tipo,
         case when p_tipo in ('adiamento', 'fim_do_dia') then 'sem_nome'
              when p_tipo in ('acorde', 'cadastro_provisorio') then null else 'padrao' end,
         case when p_tipo in ('adiamento', 'fim_do_dia') then 'retorno_adiamento'
              when p_tipo = 'coleta_numero_novo' then 'retorno_coleta'
              when p_tipo in ('acorde', 'cadastro_provisorio') then null else 'retorno_recibo' end,
         case when p_tipo in ('adiamento', 'fim_do_dia') then 'resposta_atrasada'
              when p_tipo in ('acorde', 'cadastro_provisorio') then null else 'resposta_imediata' end,
         a.chave, a.phone_normalized, a.client_id,
         case when p_estado in ('enviando', 'enviada', 'incerta') then 'ligado' else 'sombra' end,
         p_estado,
         case when p_estado in ('recusada', 'cancelada') then coalesce(p_motivo, 'validador') else p_motivo end,
         coalesce(p_enviar, p_decidida), p_decidida, case when p_estado = 'enviada' then p_decidida end,
         case when p_estado in ('agendada', 'recusada', 'cancelada') or p_tipo in ('acorde', 'cadastro_provisorio') then null
              else 'Teste F1 resumo: o texto que a saída teria.' end,
         coalesce(p_dados, '{}'::jsonb), 'teste-f1-resumo:' || gen_random_uuid()::text
    from public.retorno_aberturas a
   where a.id = p_caso
  returning id
$f$;

-- O item de uma lista do resumo pelo telefone (nulo se não está).
create or replace function pg_temp.retorno_f1_resumo_item(p_lista jsonb, p_fone text)
returns jsonb
language sql as $f$
  select e from jsonb_array_elements(coalesce(p_lista, '[]'::jsonb)) e where e ->> 'phone' = p_fone limit 1
$f$;

-- Os telefones de uma lista do resumo, na ordem.
create or replace function pg_temp.retorno_f1_resumo_fones(p_lista jsonb)
returns text[]
language sql as $f$
  select coalesce(array_agg(x.e ->> 'phone' order by x.n), '{}'::text[])
    from jsonb_array_elements(coalesce(p_lista, '[]'::jsonb)) with ordinality as x(e, n)
$f$;

-- As chaves de um objeto jsonb, em ordem.
create or replace function pg_temp.retorno_f1_resumo_chaves(p jsonb)
returns text[]
language sql as $f$
  select coalesce(array_agg(k order by k collate "C"), '{}'::text[]) from jsonb_object_keys(p) k
$f$;

-- Roda um SQL como anon ou authenticated; devolve o valor ou 'erro <sqlstate>'.
create or replace function pg_temp.retorno_f1_resumo_como(p_papel text, p_sql text)
returns text
language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_papel)::text, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

do $resumo$
declare
  c_seg constant timestamptz := '2026-11-09 00:00:00-03';     -- seg 09/11/2026
  c_ter constant timestamptz := '2026-11-10 00:00:00-03';     -- ter 10/11/2026
  c_sex constant timestamptz := '2026-11-13 00:00:00-03';     -- sex 13/11/2026
  c_manha constant timestamptz := '2026-11-10 07:30:00-03';
  c_fecha constant timestamptz := '2026-11-10 17:30:00-03';
  c_limite constant timestamptz := '2026-11-14 00:00:00-03';
  c_contrato constant text[] := array['com_prazo_hoje', 'desde', 'phone', 'prometido_ate', 'rotulo', 'venceu'];
  c_nomes constant text[] := array['Silvia Semprazo Teste', 'Samuel Semprazo Teste', 'Sonia Semprazo Teste',
                                   'Saulo Semprazo Teste', 'Selma Semprazo Teste'];
  v_f record;
  v_cfg_antes jsonb;
  v_along_antes integer;
  v_secoes integer := 0;
  v_n integer := 0;
  v_i integer;
  v_cl uuid;
  v_cl2 uuid;
  v_caso uuid;
  v_v uuid; v_nn uuid; v_p uuid; v_a uuid;
  v_s uuid;
  v_r jsonb;
  v_r2 jsonb;
  v_e jsonb;
  v_cal_antes jsonb;
  v_cal jsonb;
  v_row record;
  v_msg uuid;
  v_t timestamptz;
  v_x text;
begin
  -- ── 0. As funções, as views e as premissas ───────────────────────────────────────────────────────────
  for v_f in
    select x.assinatura, x.vol, x.definer, x.publica, p.oid, p.provolatile, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from (values ('public.retorno_resumo_do_dia(text, timestamptz)', 's', true, true),
                   ('public._retorno_rotulo(uuid, timestamptz)', 's', true, false),
                   ('public._retorno_proximo_evento(timestamptz)', 's', true, false),
                   ('public._retorno_instante(text)', 's', false, false),
                   ('public._retorno_dia_de_tarde(date)', 'i', false, false),
                   ('public._retorno_revisao_do_mes(date)', 'i', false, false),
                   ('public._retorno_turno_da_tarde(date)', 'i', false, false)) x(assinatura, vol, definer, publica)
      left join pg_proc p on p.oid = to_regprocedure(x.assinatura)
  loop
    if v_f.oid is null then
      raise exception '0: % não existe', v_f.assinatura;
    end if;
    if v_f.provolatile <> v_f.vol or v_f.prosecdef <> v_f.definer or not ('search_path=public' = any (v_f.config)) then
      raise exception '0: % não é % (SECURITY DEFINER = %) com search_path = public', v_f.assinatura, v_f.vol, v_f.definer;
    end if;
    if has_function_privilege('anon', v_f.oid, 'execute') or has_function_privilege('authenticated', v_f.oid, 'execute') then
      raise exception '0: % aberta a anon/authenticated', v_f.assinatura;
    end if;
    if v_f.publica and not has_function_privilege('service_role', v_f.oid, 'execute') then
      raise exception '0: % não é do service_role', v_f.assinatura;
    end if;
    v_n := v_n + 1;
  end loop;
  for v_f in
    select x.nome, c.oid, c.relkind, coalesce(c.reloptions, '{}') as opcoes
      from (values ('retorno_calibracao'), ('retorno_sombra_lista')) x(nome)
      left join pg_class c on c.relname = x.nome and c.relnamespace = 'public'::regnamespace
  loop
    if v_f.oid is null or v_f.relkind <> 'v' then
      raise exception '0b: a view % não existe', v_f.nome;
    end if;
    if not exists (select 1 from unnest(v_f.opcoes) o where o ~* '^security_invoker=(on|true|yes|1)$') then
      raise exception '0b: a view % está sem security_invoker', v_f.nome;
    end if;
    if has_table_privilege('anon', v_f.oid, 'select') or has_table_privilege('authenticated', v_f.oid, 'select') then
      raise exception '0b: anon ou authenticated lê a view %', v_f.nome;
    end if;
    if not has_table_privilege('service_role', v_f.oid, 'select') then
      raise exception '0b: o service_role não lê a view %', v_f.nome;
    end if;
    v_n := v_n + 1;
  end loop;
  select to_jsonb(c) into v_cfg_antes from public.retorno_config c where c.id;
  if not found then
    raise exception '0c: retorno_config sem a linha de configuração';
  end if;
  select count(*) into v_along_antes from public.retorno_alongamentos;
  -- O resumo lê o banco inteiro, só até p_agora: nada do retorno antes de 14/11 (as linhas reais nascem a partir de 16/11).
  if exists (select 1 from public.retorno_aberturas a where a.gravada_em < c_limite or a.chave like '000088%')
     or exists (select 1 from public.retorno_saidas s
                 where s.chave like '000088%' or s.decidida_em < c_limite or (s.estado = 'agendada' and s.enviar_em < c_limite))
     or exists (select 1 from public.retorno_alongamentos l where l.em < c_limite) then
    raise exception '0d: há caso, saída ou alongamento do retorno antes de 14/11/2026 ou dos números de teste (o resumo os contaria)';
  end if;
  if exists (select 1 from public.whatsapp_messages w where w.phone_normalized like '55479000088%')
     or exists (select 1 from public.clients c
                 where public._agenda_chave_telefone(c.phone) like '000088%' or public._agenda_chave_telefone(c.whatsapp) like '000088%') then
    raise exception '0e: há mensagem ou cadastro real com os números de teste 55479000088xx';
  end if;

  -- ── 1. Manhã: quem espera ────────────────────────────────────────────────────────────────────────────
  begin
    update public.retorno_config set modo = 'sombra', tipos_ligados = '{}' where id;
    -- V: cliente vencido ontem (prometido 19h; o fim do dia saiu às 18:30 e marcou o topo de hoje)
    v_cl := pg_temp.retorno_f1_resumo_cliente('Paulo Vencido Teste', '(47) 90000-8801');
    v_v := pg_temp.retorno_f1_resumo_caso('5547900008801', 'cliente', c_seg + interval '14 hours 2 minutes', 'recibo', null, v_cl);
    update public.retorno_aberturas
       set recibo_em = c_seg + interval '14 hours 4 minutes', prometido_ate = c_seg + interval '19 hours',
           prometido_fonte = 'fechamento', faixa = 'meio', fim_do_dia_em = c_seg + interval '18 hours 30 minutes',
           topo_dia = '2026-11-10', estado = 'vencida'
     where id = v_v;
    -- N: número novo prometido hoje até 10h, com coleta.nome, mas a coleta 2 só em sombra (nunca ouviu a pergunta)
    v_nn := pg_temp.retorno_f1_resumo_caso('5547900008802', 'numero_novo', c_seg + interval '16 hours');
    update public.retorno_aberturas
       set recibo_em = c_seg + interval '16 hours 2 minutes', prometido_ate = c_ter + interval '10 hours',
           prometido_fonte = 'manha', faixa = 'tarde', coleta = '{"nome": "Marcela", "fonte": "retorno"}', coleta_n = 2
     where id = v_nn;
    perform pg_temp.retorno_f1_resumo_saida(v_nn, 'recibo_numero_novo', 'sombra', c_seg + interval '16 hours 2 minutes');
    perform pg_temp.retorno_f1_resumo_saida(v_nn, 'coleta_numero_novo', 'sombra', c_seg + interval '16 hours 20 minutes');
    -- P: cliente que escreveu às 23:30; o recibo ainda agendado para as 08:05, com a promessa (hoje 10h) guardada
    v_cl := pg_temp.retorno_f1_resumo_cliente('Pedro Pendente Teste', '(47) 90000-8805');
    v_p := pg_temp.retorno_f1_resumo_caso('5547900008805', 'cliente', c_seg + interval '23 hours 30 minutes', 'recibo', null, v_cl);
    perform pg_temp.retorno_f1_resumo_saida(v_p, 'recibo_cliente', 'agendada', null, null,
              jsonb_build_object('prazo', jsonb_build_object('prometido_ate', c_ter + interval '10 hours', 'faixa', 'noite')),
              c_ter + interval '8 hours 5 minutes');
    -- A: número de dois clientes, recibo às 07:12, prometido hoje 19h
    v_cl := pg_temp.retorno_f1_resumo_cliente('Ana Ambigua Teste', '(47) 90000-8803');
    v_cl2 := pg_temp.retorno_f1_resumo_cliente('Bruno Ambiguo Teste', '(47) 90000-8803');
    v_a := pg_temp.retorno_f1_resumo_caso('5547900008803', 'cliente_ambiguo', c_ter + interval '7 hours 10 minutes', 'recibo',
                                          null, null, array[v_cl, v_cl2]);
    update public.retorno_aberturas
       set recibo_em = c_ter + interval '7 hours 12 minutes', prometido_ate = c_ter + interval '19 hours',
           prometido_fonte = 'fechamento', faixa = 'manha_cedo'
     where id = v_a;
    -- Cumpridos (ficam fora): fechado por conteúdo; e aberto com cumprida_em (entre dois minutos do vigia)
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008806', 'cliente', c_seg + interval '15 hours');
    update public.retorno_aberturas
       set recibo_em = c_seg + interval '15 hours 2 minutes', prometido_ate = c_ter + interval '10 hours', faixa = 'meio',
           cumprida_em = c_seg + interval '17 hours', cumprida_por = 'celular', estado = 'fechada',
           fechada_em = c_seg + interval '17 hours', fechada_motivo = 'conteudo'
     where id = v_caso;
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008807', 'cliente', c_seg + interval '15 hours 10 minutes');
    update public.retorno_aberturas
       set recibo_em = c_seg + interval '15 hours 12 minutes', prometido_ate = c_ter + interval '10 hours', faixa = 'meio',
           cumprida_em = c_ter + interval '7 hours', cumprida_por = 'celular'
     where id = v_caso;
    -- 5 sem prazo hoje: 3 prometidos para amanhã, 2 com o recibo ainda sem prazo
    for v_i in 1 .. 5 loop
      v_cl := pg_temp.retorno_f1_resumo_cliente(c_nomes[v_i], '(47) 90000-88' || (10 + v_i));
      v_caso := pg_temp.retorno_f1_resumo_caso('55479000088' || (10 + v_i), 'cliente',
                                               c_seg + make_interval(hours => 9, mins => 10 * (v_i - 1)), 'recibo', null, v_cl);
      if v_i <= 3 then
        update public.retorno_aberturas
           set recibo_em = c_seg + make_interval(hours => 9, mins => 10 * (v_i - 1) + 2),
               prometido_ate = c_ter + interval '1 day 10 hours', faixa = 'meio'
         where id = v_caso;
      end if;
    end loop;
    -- Fora: o caso 'nada' e o caso do FUTURO (gravado às 08:00, depois da manhã)
    perform pg_temp.retorno_f1_resumo_caso('5547900008816', 'cliente', c_seg + interval '10 hours', 'nada', 'nao_pede_resposta');
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008817', 'cliente', c_ter + interval '8 hours');
    update public.retorno_aberturas
       set recibo_em = c_ter + interval '8 hours 2 minutes', prometido_ate = c_ter + interval '19 hours', faixa = 'manha_cedo'
     where id = v_caso;

    v_r := public.retorno_resumo_do_dia('manha', c_manha);
    if pg_temp.retorno_f1_resumo_chaves(v_r) is distinct from array['conferir', 'conferir_mais', 'esperando', 'esperando_mais', 'modo'] then
      raise exception '1: a manhã fora do contrato C-RESUMO: %', v_r;
    end if;
    if v_r ->> 'modo' is distinct from 'sombra' then
      raise exception '1: modo % (esperado sombra)', v_r ->> 'modo';
    end if;
    if pg_temp.retorno_f1_resumo_fones(v_r -> 'esperando')
       is distinct from array['5547900008801', '5547900008802', '5547900008805', '5547900008803',
                              '5547900008811', '5547900008812', '5547900008813'] then
      raise exception '1: quem espera, fora da ordem (vencido, por prazo, 3 sem prazo por abertura): %',
        pg_temp.retorno_f1_resumo_fones(v_r -> 'esperando');
    end if;
    if (v_r -> 'esperando_mais') is distinct from '2'::jsonb then
      raise exception '1: esperando_mais = % (esperado 2: os 5 sem prazo menos os 3 nomeados)', v_r -> 'esperando_mais';
    end if;
    if exists (select 1 from jsonb_array_elements(v_r -> 'esperando') e where not (e ?& c_contrato)) then
      raise exception '1: item de esperando sem as chaves do contrato: %', v_r -> 'esperando';
    end if;
    v_e := pg_temp.retorno_f1_resumo_item(v_r -> 'esperando', '5547900008801');
    if v_e ->> 'rotulo' is distinct from 'Paulo' or (v_e -> 'venceu') is distinct from 'true'::jsonb
       or (v_e -> 'com_prazo_hoje') is distinct from 'true'::jsonb
       or (v_e ->> 'desde')::timestamptz is distinct from c_seg + interval '14 hours 2 minutes' then
      raise exception '1a: o cliente vencido ontem: %', v_e;
    end if;
    v_e := pg_temp.retorno_f1_resumo_item(v_r -> 'esperando', '5547900008802');
    if v_e ->> 'rotulo' is distinct from 'número novo' or (v_e -> 'venceu') is distinct from 'false'::jsonb
       or (v_e -> 'com_prazo_hoje') is distinct from 'true'::jsonb or v_e ->> 'papel' is distinct from 'numero_novo'
       or (v_e ->> 'prometido_ate')::timestamptz is distinct from c_ter + interval '10 hours'
       or (v_e -> 'ouviu') is distinct from 'false'::jsonb then
      raise exception '1b: o número novo prometido hoje às 10h (coleta 2 só em sombra = "número novo"): %', v_e;
    end if;
    v_e := pg_temp.retorno_f1_resumo_item(v_r -> 'esperando', '5547900008805');
    if v_e ->> 'rotulo' is distinct from 'Pedro' or (v_e -> 'com_prazo_hoje') is distinct from 'true'::jsonb
       or (v_e ->> 'prometido_ate')::timestamptz is distinct from c_ter + interval '10 hours'
       or (v_e -> 'ouviu') is distinct from 'false'::jsonb then
      raise exception '1c: o recibo da noite ainda agendado tem prazo hoje (a promessa guardada): %', v_e;
    end if;
    v_e := pg_temp.retorno_f1_resumo_item(v_r -> 'esperando', '5547900008803');
    if v_e ->> 'rotulo' is distinct from '(número de 2 clientes)' or (v_e -> 'com_prazo_hoje') is distinct from 'true'::jsonb then
      raise exception '1d: o ambíguo: %', v_e;
    end if;
    if exists (select 1 from jsonb_array_elements(v_r -> 'esperando') e
                where e ->> 'phone' in ('5547900008811', '5547900008812', '5547900008813')
                  and (e -> 'com_prazo_hoje' <> 'false'::jsonb or e -> 'venceu' <> 'false'::jsonb)) then
      raise exception '1e: um sem prazo hoje veio marcado com prazo: %', v_r -> 'esperando';
    end if;
    if v_r -> 'conferir' is distinct from '[]'::jsonb or (v_r -> 'conferir_mais') is distinct from '0'::jsonb then
      raise exception '1f: sem nada a conferir, a lista é [] e conferir_mais 0: %', v_r;
    end if;
    if strpos(v_r::text, 'CORPO-SECRETO') > 0 or strpos(v_r::text, 'Marcela') > 0 then
      raise exception '1g: a manhã trouxe texto do cliente: %', v_r;
    end if;
    -- 1h. Com a coleta 2 enviada às 07:00, o rótulo é o nome dito, só a partir de quando ela saiu (o futuro não conta).
    perform pg_temp.retorno_f1_resumo_saida(v_nn, 'coleta_numero_novo', 'enviada', c_ter + interval '7 hours');
    if public._retorno_rotulo(v_nn, c_manha) is distinct from 'Marcela'
       or public._retorno_rotulo(v_nn, c_ter + interval '6 hours') is distinct from 'número novo' then
      raise exception '1h: o nome dito só depois da coleta 2 enviada: % e %', public._retorno_rotulo(v_nn, c_manha),
        public._retorno_rotulo(v_nn, c_ter + interval '6 hours');
    end if;
    -- 1i. Um dados.prazo ilegível nunca derruba a manhã: o caso só passa aos sem prazo (os 5 + ele: 3 nomeados e 3 a mais).
    update public.retorno_saidas
       set dados = jsonb_set(dados, '{prazo,prometido_ate}', '"amanhã cedo"')
     where abertura_id = v_p;
    v_r2 := public.retorno_resumo_do_dia('manha', c_manha);
    if public._retorno_instante('amanhã cedo') is not null or public._retorno_instante(' ') is not null
       or public._retorno_instante('2026-11-10 10:00:00-03') is distinct from c_ter + interval '10 hours'
       or pg_temp.retorno_f1_resumo_item(v_r2 -> 'esperando', '5547900008805') is not null
       or (v_r2 -> 'esperando_mais') is distinct from '3'::jsonb then
      raise exception '1i: o dados.prazo ilegível: %', v_r2;
    end if;
    v_n := v_n + 1;
    v_secoes := v_secoes + 1;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;

  -- ── 2. Manhã: "Para conferir" ────────────────────────────────────────────────────────────────────────
  begin
    update public.retorno_config set modo = 'sombra', tipos_ligados = '{}' where id;
    -- C1: o mesmo número pediu para parar por extenso duas vezes; vale o caso mais recente (20:00)
    v_cl := pg_temp.retorno_f1_resumo_cliente('Rita Conferir Teste', '(47) 90000-8821');
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008821', 'cliente', c_seg + interval '9 hours', 'nada', 'parar_largo', v_cl);
    update public.retorno_aberturas
       set estado = 'fechada', fechada_em = c_seg + interval '13 hours', fechada_motivo = 'nada'
     where id = v_caso;
    perform pg_temp.retorno_f1_resumo_caso('5547900008821', 'cliente', c_seg + interval '20 hours', 'nada', 'parar_largo', v_cl);
    -- C2: número novo com opt-out que voltou a escrever
    perform pg_temp.retorno_f1_resumo_caso('5547900008822', 'numero_novo', c_ter + interval '6 hours', 'nada', 'opt_out');
    -- C3: mensagem de sáb 07/11 10:00 gravada só seg 09/11 22:00 (atraso de 60 h): o recibo foi cancelado por atraso_longo
    v_cl := pg_temp.retorno_f1_resumo_cliente('Sergio Atraso Teste', '(47) 90000-8823');
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008823', 'cliente', c_seg - interval '2 days' + interval '10 hours',
                                             'recibo', null, v_cl, '{}'::uuid[], c_seg + interval '22 hours');
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'recibo_cliente', 'cancelada', c_seg + interval '22 hours 2 minutes',
                                            'atraso_longo');
    -- C5: outro parar_largo, hoje 07:00 (o 4º: vai para conferir_mais)
    v_cl := pg_temp.retorno_f1_resumo_cliente('Tania Conferir Teste', '(47) 90000-8825');
    perform pg_temp.retorno_f1_resumo_caso('5547900008825', 'cliente', c_ter + interval '7 hours', 'nada', 'parar_largo', v_cl);
    -- Fora: parar_largo de 48 h atrás; opt_out do futuro (08:00); recibo cancelado por outro motivo; atraso_longo de 3 dias
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008824', 'cliente', c_seg - interval '1 day' + interval '7 hours', 'nada', 'parar_largo');
    update public.retorno_aberturas
       set estado = 'fechada', fechada_em = c_seg - interval '1 day' + interval '11 hours', fechada_motivo = 'nada'
     where id = v_caso;
    perform pg_temp.retorno_f1_resumo_caso('5547900008826', 'numero_novo', c_ter + interval '8 hours', 'nada', 'opt_out');
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008827', 'cliente', c_seg + interval '21 hours 50 minutes');
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'recibo_cliente', 'cancelada', c_seg + interval '22 hours', 'respondida_pelo_dono');
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008828', 'cliente', c_seg - interval '5 days',
                                             'recibo', null, null, '{}'::uuid[], c_seg - interval '3 days');
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'recibo_cliente', 'cancelada', c_seg - interval '3 days' + interval '2 minutes',
                                            'atraso_longo');

    v_r := public.retorno_resumo_do_dia('manha', c_manha);
    if jsonb_typeof(v_r -> 'conferir') is distinct from 'array'
       or pg_temp.retorno_f1_resumo_fones(v_r -> 'conferir') is distinct from array['5547900008823', '5547900008821', '5547900008822'] then
      raise exception '2: "Para conferir" fora da ordem (atraso_longo, parar_largo, opt_out, por desde): %', v_r -> 'conferir';
    end if;
    if (v_r -> 'conferir_mais') is distinct from '1'::jsonb then
      raise exception '2: conferir_mais = % (esperado 1: o parar_largo de hoje 07:00)', v_r -> 'conferir_mais';
    end if;
    if exists (select 1 from jsonb_array_elements(v_r -> 'conferir') e
                where pg_temp.retorno_f1_resumo_chaves(e) is distinct from array['desde', 'motivo', 'phone', 'rotulo']) then
      raise exception '2: item de conferir fora do contrato ({phone, rotulo, motivo, desde}): %', v_r -> 'conferir';
    end if;
    v_e := pg_temp.retorno_f1_resumo_item(v_r -> 'conferir', '5547900008823');
    if v_e ->> 'motivo' is distinct from 'atraso_longo' or v_e ->> 'rotulo' is distinct from 'Sergio'
       or (v_e ->> 'desde')::timestamptz is distinct from c_seg - interval '2 days' + interval '10 hours' then
      raise exception '2a: o recibo cancelado por atraso_longo: %', v_e;
    end if;
    v_e := pg_temp.retorno_f1_resumo_item(v_r -> 'conferir', '5547900008821');
    if v_e ->> 'motivo' is distinct from 'parar_largo' or v_e ->> 'rotulo' is distinct from 'Rita'
       or (v_e ->> 'desde')::timestamptz is distinct from c_seg + interval '20 hours' then
      raise exception '2b: o parar_largo (o caso mais recente do número): %', v_e;
    end if;
    v_e := pg_temp.retorno_f1_resumo_item(v_r -> 'conferir', '5547900008822');
    if v_e ->> 'motivo' is distinct from 'opt_out' or v_e ->> 'rotulo' is distinct from 'número novo' then
      raise exception '2c: o opt_out que voltou a escrever: %', v_e;
    end if;
    if strpos(v_r::text, 'CORPO-SECRETO') > 0 then
      raise exception '2d: a manhã trouxe texto do cliente: %', v_r;
    end if;
    v_n := v_n + 1;
    v_secoes := v_secoes + 1;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;

  -- ── 2b. "Para conferir": a janela e a repetição ──────────────────────────────────────────────────────
  begin
    update public.retorno_config set modo = 'sombra', tipos_ligados = '{}' where id;
    -- D1: caso aberto seg 09:00, e o pedido de parar veio na última mensagem, ter 08:00. Na manhã de qua o caso tem 46 h,
    -- mas o pedido tem 23 h 30: aparece, com o desde da abertura
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008881', 'cliente', c_seg + interval '9 hours', 'nada', 'parar_largo');
    update public.retorno_aberturas
       set ultima_em = c_ter + interval '8 hours', ultima_gravada_em = c_ter + interval '8 hours'
     where id = v_caso;
    -- D2: caso parado desde seg 10:00: na manhã de qua já saiu da janela
    perform pg_temp.retorno_f1_resumo_caso('5547900008882', 'cliente', c_seg + interval '10 hours', 'nada', 'parar_largo');
    -- E1: parar_largo de sáb 10:00, depois da manhã de sábado; domingo não lê: só a manhã de segunda pode mostrar
    perform pg_temp.retorno_f1_resumo_caso('5547900008883', 'cliente', '2026-11-07 10:00:00-03', 'nada', 'parar_largo');
    -- E2: opt_out de sáb 07:00: a manhã de sábado mostra, e a de segunda não repete
    perform pg_temp.retorno_f1_resumo_caso('5547900008884', 'numero_novo', '2026-11-07 07:00:00-03', 'nada', 'opt_out');
    -- G: atraso_longo de dom 01/11 10:00, e seg 02/11 é Finados: só a manhã de ter 03/11 pode mostrar
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008886', 'cliente', '2026-10-29 10:00:00-03', 'recibo', null, null,
                                             '{}'::uuid[], '2026-11-01 09:58:00-03');
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'recibo_cliente', 'cancelada', '2026-11-01 10:00:00-03', 'atraso_longo');
    -- H: o mesmo número com dois motivos: recibo cancelado por atraso_longo qua 22:02 e parar_largo qui 06:00
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008885', 'cliente', c_seg + interval '10 hours', 'recibo', null, null,
                                             '{}'::uuid[], c_ter + interval '1 day 22 hours');
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'recibo_cliente', 'cancelada', c_ter + interval '1 day 22 hours 2 minutes',
                                            'atraso_longo');
    update public.retorno_aberturas
       set estado = 'fechada', fechada_em = c_ter + interval '1 day 22 hours 3 minutes', fechada_motivo = 'expirou'
     where id = v_caso;
    perform pg_temp.retorno_f1_resumo_caso('5547900008885', 'cliente', c_ter + interval '2 days 6 hours', 'nada', 'parar_largo');

    v_r := public.retorno_resumo_do_dia('manha', c_ter + interval '1 day 7 hours 30 minutes');
    v_e := pg_temp.retorno_f1_resumo_item(v_r -> 'conferir', '5547900008881');
    if pg_temp.retorno_f1_resumo_fones(v_r -> 'conferir') is distinct from array['5547900008881']
       or v_e ->> 'motivo' is distinct from 'parar_largo'
       or (v_e ->> 'desde')::timestamptz is distinct from c_seg + interval '9 hours' then
      raise exception '2e: na manhã de qua, vale a última mensagem do caso (D1 dentro, D2 fora): %', v_r -> 'conferir';
    end if;
    v_r := public.retorno_resumo_do_dia('manha', '2026-11-07 07:30:00-03');
    if pg_temp.retorno_f1_resumo_fones(v_r -> 'conferir') is distinct from array['5547900008884'] then
      raise exception '2f: a manhã de sábado lê o retorno (o opt_out das 07:00 entra): %', v_r -> 'conferir';
    end if;
    v_r := public.retorno_resumo_do_dia('manha', c_seg + interval '7 hours 30 minutes');
    if pg_temp.retorno_f1_resumo_fones(v_r -> 'conferir') is distinct from array['5547900008883'] then
      raise exception '2g: a manhã de segunda cobre desde a de sábado (o de sáb 10:00 entra; o de sáb 07:00 já foi mostrado): %',
        v_r -> 'conferir';
    end if;
    v_r := public.retorno_resumo_do_dia('manha', c_manha);
    if pg_temp.retorno_f1_resumo_item(v_r -> 'conferir', '5547900008883') is not null then
      raise exception '2h: a manhã de terça repetiu o que a de segunda mostrou: %', v_r -> 'conferir';
    end if;
    v_r := public.retorno_resumo_do_dia('manha', '2026-11-03 07:30:00-03');
    if pg_temp.retorno_f1_resumo_fones(v_r -> 'conferir') is distinct from array['5547900008886'] then
      raise exception '2i: depois do domingo e do feriado, a manhã cobre desde a de sábado (o atraso_longo de dom entra): %',
        v_r -> 'conferir';
    end if;
    v_r := public.retorno_resumo_do_dia('manha', '2026-11-04 07:30:00-03');
    if v_r -> 'conferir' is distinct from '[]'::jsonb then
      raise exception '2j: a manhã de 04/11 repetiu o que a de 03/11 mostrou: %', v_r -> 'conferir';
    end if;
    v_r := public.retorno_resumo_do_dia('manha', c_ter + interval '2 days 7 hours 30 minutes');
    if pg_temp.retorno_f1_resumo_fones(v_r -> 'conferir') is distinct from array['5547900008885', '5547900008885']
       or (select array_agg(x.e ->> 'motivo' order by x.n)
             from jsonb_array_elements(v_r -> 'conferir') with ordinality as x(e, n))
          is distinct from array['atraso_longo', 'parar_largo']
       or (v_r -> 'conferir_mais') is distinct from '0'::jsonb then
      raise exception '2k: o mesmo número com dois motivos traz os dois: %', v_r;
    end if;
    v_n := v_n + 1;
    v_secoes := v_secoes + 1;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;

  -- ── 3. Fechamento ────────────────────────────────────────────────────────────────────────────────────
  begin
    update public.retorno_config set modo = 'sombra', tipos_ligados = '{}' where id;
    -- F1: empresa sem display_name ("cliente sem nome"), recibo em sombra 09:16, prometido hoje 19h; e um acorde em sombra
    v_cl := pg_temp.retorno_f1_resumo_cliente('ACME TESTE F1 LTDA', '(47) 90000-8831', 'company');
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008831', 'cliente', c_ter + interval '9 hours 14 minutes', 'recibo', null, v_cl);
    update public.retorno_aberturas
       set recibo_em = c_ter + interval '9 hours 16 minutes', prometido_ate = c_ter + interval '19 hours', faixa = 'manha_cedo'
     where id = v_caso;
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'recibo_cliente', 'sombra', c_ter + interval '9 hours 16 minutes');
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'acorde', 'sombra', c_ter + interval '10 hours');
    -- F2: número novo, recibo em sombra 10:02, prometido 19h; e uma coleta em sombra decidida às 17:40 (do futuro)
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008832', 'numero_novo', c_ter + interval '10 hours');
    update public.retorno_aberturas
       set recibo_em = c_ter + interval '10 hours 2 minutes', prometido_ate = c_ter + interval '19 hours', faixa = 'manha_cedo'
     where id = v_caso;
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'recibo_numero_novo', 'sombra', c_ter + interval '10 hours 2 minutes');
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'coleta_numero_novo', 'sombra', c_ter + interval '17 hours 40 minutes');
    -- F3: recibo ENVIADO às 08:02 (ouviu), prometido 10h, adiado às 09:30 para 19h
    v_cl := pg_temp.retorno_f1_resumo_cliente('Fabio Adiado Teste', '(47) 90000-8833');
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008833', 'cliente', c_ter + interval '8 hours', 'recibo', null, v_cl);
    update public.retorno_aberturas
       set recibo_em = c_ter + interval '8 hours 2 minutes', prometido_ate = c_ter + interval '10 hours', faixa = 'manha_cedo',
           adiamento_em = c_ter + interval '9 hours 30 minutes', segundo_prazo = c_ter + interval '19 hours'
     where id = v_caso;
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'recibo_cliente', 'enviada', c_ter + interval '8 hours 2 minutes');
    -- F4: escreveu ontem 16:00, prometido hoje 10h, venceu sem palavra (sem fim do dia); o recibo em sombra foi ONTEM
    v_cl := pg_temp.retorno_f1_resumo_cliente('Gilda Semfala Teste', '(47) 90000-8834');
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008834', 'cliente', c_seg + interval '16 hours', 'recibo', null, v_cl);
    update public.retorno_aberturas
       set recibo_em = c_seg + interval '16 hours 2 minutes', prometido_ate = c_ter + interval '10 hours', faixa = 'tarde',
           estado = 'vencida'
     where id = v_caso;
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'recibo_cliente', 'sombra', c_seg + interval '16 hours 2 minutes');
    -- F5: venceu às 10h com o fim do dia recusado por so_reativo (o canal estava fora): na_queda, não sem_palavra
    v_cl := pg_temp.retorno_f1_resumo_cliente('Hugo Queda Teste', '(47) 90000-8835');
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008835', 'cliente', c_ter + interval '8 hours', 'recibo', null, v_cl);
    update public.retorno_aberturas
       set recibo_em = c_ter + interval '8 hours 2 minutes', prometido_ate = c_ter + interval '10 hours', faixa = 'manha_cedo',
           estado = 'vencida'
     where id = v_caso;
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'fim_do_dia', 'recusada', c_ter + interval '9 hours 30 minutes', 'so_reativo');
    -- F6: venceu às 10h, mas o fim do dia saiu às 09:30 (teve palavra): nem sem_palavra nem na_queda
    v_cl := pg_temp.retorno_f1_resumo_cliente('Iris Palavra Teste', '(47) 90000-8836');
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008836', 'cliente', c_ter + interval '7 hours 45 minutes', 'recibo', null, v_cl);
    update public.retorno_aberturas
       set recibo_em = c_ter + interval '7 hours 47 minutes', prometido_ate = c_ter + interval '10 hours', faixa = 'manha_cedo',
           fim_do_dia_em = c_ter + interval '9 hours 30 minutes', topo_dia = '2026-11-11', estado = 'vencida'
     where id = v_caso;
    -- F7: respondido de conteúdo às 11:00, antes das 19h (no prazo; fechado, fica fora de quem espera)
    v_cl := pg_temp.retorno_f1_resumo_cliente('Joao Noprazo Teste', '(47) 90000-8837');
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008837', 'cliente', c_ter + interval '9 hours', 'recibo', null, v_cl);
    update public.retorno_aberturas
       set recibo_em = c_ter + interval '9 hours 2 minutes', prometido_ate = c_ter + interval '19 hours', faixa = 'manha_cedo',
           cumprida_em = c_ter + interval '11 hours', cumprida_por = 'celular', estado = 'fechada',
           fechada_em = c_ter + interval '11 hours 1 minute', fechada_motivo = 'conteudo'
     where id = v_caso;
    -- F8: caso 'nada' aberto hoje (não é recebido)
    perform pg_temp.retorno_f1_resumo_caso('5547900008838', 'cliente', c_ter + interval '9 hours 30 minutes', 'nada', 'nao_pede_resposta');
    -- F9: o dono respondeu antes do recibo (cancelado às 11:02); o acorde cancelado junto não conta
    v_cl := pg_temp.retorno_f1_resumo_cliente('Lia Respondeu Teste', '(47) 90000-8839');
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008839', 'cliente', c_ter + interval '11 hours', 'recibo', null, v_cl);
    update public.retorno_aberturas
       set respondida_em = c_ter + interval '11 hours 1 minute', estado = 'fechada',
           fechada_em = c_ter + interval '15 hours 1 minute', fechada_motivo = 'silencio'
     where id = v_caso;
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'recibo_cliente', 'cancelada', c_ter + interval '11 hours 2 minutes',
                                            'respondida_pelo_dono');
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'acorde', 'cancelada', c_ter + interval '11 hours 2 minutes',
                                            'respondida_pelo_dono');
    -- F10: caso do FUTURO (gravado às 17:45), prometido 19h
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008840', 'cliente', c_ter + interval '17 hours 45 minutes');
    update public.retorno_aberturas
       set recibo_em = c_ter + interval '17 hours 47 minutes', prometido_ate = c_ter + interval '19 hours', faixa = 'meio'
     where id = v_caso;
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'recibo_cliente', 'sombra', c_ter + interval '17 hours 47 minutes');
    -- F11: venceu seg 10h; seg 09/11 é revisão da semana, que não mostra sem_palavra: a terça conta
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008841', 'cliente', c_seg + interval '8 hours');
    update public.retorno_aberturas
       set recibo_em = c_seg + interval '8 hours 2 minutes', prometido_ate = c_seg + interval '10 hours', faixa = 'manha_cedo',
           estado = 'fechada', fechada_em = c_ter + interval '5 hours', fechada_motivo = 'expirou'
     where id = v_caso;
    -- F12: venceu seg 19h: cai neste, mesmo já fechado (e fica fora de quem espera)
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008842', 'cliente', c_seg + interval '13 hours');
    update public.retorno_aberturas
       set recibo_em = c_seg + interval '13 hours 2 minutes', prometido_ate = c_seg + interval '19 hours', faixa = 'meio',
           estado = 'fechada', fechada_em = c_ter + interval '5 hours', fechada_motivo = 'expirou'
     where id = v_caso;
    -- F13: recibo em sombra seg 09:02 prometendo 19h, PARAR às 11:00 e fechado como 'nada' às 15:00: calou de propósito,
    -- nunca ganha fim do dia e não conta em sem_palavra
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008843', 'cliente', c_seg + interval '9 hours', 'nada', 'parar');
    update public.retorno_aberturas
       set recibo_em = c_seg + interval '9 hours 2 minutes', prometido_ate = c_seg + interval '19 hours', faixa = 'manha_cedo',
           estado = 'fechada', fechada_em = c_seg + interval '15 hours', fechada_motivo = 'nada'
     where id = v_caso;
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'recibo_cliente', 'sombra', c_seg + interval '9 hours 2 minutes');
    -- F14: o fim do dia recusado por so_reativo às 18:30 e, depois, o PARAR por extenso: também calou, e não conta em na_queda
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008844', 'cliente', c_seg + interval '13 hours 10 minutes', 'nada', 'parar_largo');
    update public.retorno_aberturas
       set recibo_em = c_seg + interval '13 hours 12 minutes', prometido_ate = c_seg + interval '19 hours', faixa = 'meio',
           estado = 'fechada', fechada_em = c_ter + interval '1 hour', fechada_motivo = 'nada'
     where id = v_caso;
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'fim_do_dia', 'recusada', c_seg + interval '18 hours 30 minutes', 'so_reativo');
    -- F15: venceu sex 06/11 19h, depois do fechamento de sexta: a terça conta (a segunda é revisão)
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008845', 'cliente', c_seg - interval '3 days' + interval '13 hours');
    update public.retorno_aberturas
       set recibo_em = c_seg - interval '3 days' + interval '13 hours 2 minutes',
           prometido_ate = c_seg - interval '3 days' + interval '19 hours', faixa = 'meio',
           estado = 'fechada', fechada_em = c_ter + interval '5 hours', fechada_motivo = 'expirou'
     where id = v_caso;
    -- F16: venceu sex 06/11 10h, antes do fechamento de sexta (17:30): já contou naquele e não conta de novo
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008846', 'cliente', c_seg - interval '3 days' + interval '8 hours');
    update public.retorno_aberturas
       set recibo_em = c_seg - interval '3 days' + interval '8 hours 2 minutes',
           prometido_ate = c_seg - interval '3 days' + interval '10 hours', faixa = 'manha_cedo',
           estado = 'fechada', fechada_em = c_ter + interval '5 hours', fechada_motivo = 'expirou'
     where id = v_caso;

    v_r := public.retorno_resumo_do_dia('fechamento', c_fecha);
    if pg_temp.retorno_f1_resumo_chaves(v_r) is distinct from
       array['adiados', 'alongadas', 'esperando', 'modo', 'na_queda', 'no_prazo', 'recebidos', 'sem_palavra', 'sombra'] then
      raise exception '3: o fechamento fora do contrato C-RESUMO: %', v_r;
    end if;
    if (select array_agg(x order by x) from unnest(pg_temp.retorno_f1_resumo_fones(v_r -> 'esperando')) x)
       is distinct from array['5547900008831', '5547900008832', '5547900008833', '5547900008834', '5547900008835', '5547900008836'] then
      raise exception '3a: "Ainda esperando hoje" (os prometidos até 19h e os vencidos, todos): %',
        pg_temp.retorno_f1_resumo_fones(v_r -> 'esperando');
    end if;
    if (select array_agg((x.e ->> 'venceu')::boolean order by x.n)
          from jsonb_array_elements(v_r -> 'esperando') with ordinality as x(e, n))
       is distinct from array[true, true, true, false, false, false] then
      raise exception '3a: os vencidos vêm antes dos prometidos para hoje: %', v_r -> 'esperando';
    end if;
    if exists (select 1 from jsonb_array_elements(v_r -> 'esperando') e
                where not (e ?& c_contrato) or e -> 'com_prazo_hoje' <> 'true'::jsonb) then
      raise exception '3a: item de esperando sem o contrato ou sem prazo hoje: %', v_r -> 'esperando';
    end if;
    v_e := pg_temp.retorno_f1_resumo_item(v_r -> 'esperando', '5547900008831');
    if v_e ->> 'rotulo' is distinct from 'cliente sem nome' then
      raise exception '3b: a empresa sem display_name sai "cliente sem nome": %', v_e;
    end if;
    v_e := pg_temp.retorno_f1_resumo_item(v_r -> 'esperando', '5547900008833');
    if (v_e -> 'ouviu') is distinct from 'true'::jsonb
       or (v_e ->> 'prometido_ate')::timestamptz is distinct from c_ter + interval '10 hours'
       or (v_e ->> 'segundo_prazo')::timestamptz is distinct from c_ter + interval '19 hours'
       or (v_e -> 'venceu') is distinct from 'false'::jsonb then
      raise exception '3c: o adiado que ouviu a promessa (prazo de pé = o X2 das 19h): %', v_e;
    end if;
    if (v_r -> 'recebidos') is distinct from '7'::jsonb or (v_r -> 'no_prazo') is distinct from '1'::jsonb
       or (v_r -> 'adiados') is distinct from '1'::jsonb then
      raise exception '3d: recebidos/no_prazo/adiados = %/%/% (esperado 7/1/1)', v_r -> 'recebidos', v_r -> 'no_prazo', v_r -> 'adiados';
    end if;
    -- F4, F11, F12 e F15: seg 09/11 é revisão, e o fechamento anterior é o de sex 06/11. Fora: F16 (venceu antes dele), F6
    -- (teve palavra) e os 'nada' F13 e F14. F5 conta à parte.
    if (v_r -> 'sem_palavra') is distinct from '4'::jsonb or (v_r -> 'na_queda') is distinct from '1'::jsonb then
      raise exception '3e: sem_palavra/na_queda = %/% (esperado 4/1: desde o fechamento de sexta, sem os ''nada'', e o fim do dia recusado por so_reativo à parte)',
        v_r -> 'sem_palavra', v_r -> 'na_queda';
    end if;
    if v_r -> 'sombra' is distinct from
       '{"teria_mandado": 2, "por_papel": {"cliente": 1, "numero_novo": 1}, "respondeu_antes": 1}'::jsonb then
      raise exception '3f: a sombra de hoje (2 em sombra por papel, 1 respondida antes): %', v_r -> 'sombra';
    end if;
    if v_r -> 'alongadas' is distinct from '[]'::jsonb or v_r ->> 'modo' is distinct from 'sombra' then
      raise exception '3g: na terça, alongadas = [] (e modo sombra): %', v_r;
    end if;
    if strpos(v_r::text, 'CORPO-SECRETO') > 0 or strpos(v_r::text, 'Teste F1 resumo:') > 0 then
      raise exception '3h: o fechamento trouxe texto de mensagem: %', v_r;
    end if;
    -- 3i. O fechamento de qua conta desde o de ter: só os quatro que venceram às 19h (F1, F2, F3 e F10), nada repetido.
    v_r2 := public.retorno_resumo_do_dia('fechamento', c_ter + interval '1 day 17 hours 30 minutes');
    if (v_r2 -> 'sem_palavra') is distinct from '4'::jsonb or (v_r2 -> 'na_queda') is distinct from '0'::jsonb then
      raise exception '3i: a quarta repetiu o que a terça contou: sem_palavra/na_queda = %/% (esperado 4/0)',
        v_r2 -> 'sem_palavra', v_r2 -> 'na_queda';
    end if;
    -- 3j. O turno da tarde do banco é o do Secretário (turnoDaTarde): os valores vêm de _shared/secretario/turno.ts.
    for v_f in
      select x.dia, x.turno, public._retorno_turno_da_tarde(x.dia) as calculado
        from (values ('2026-06-15'::date, null::text), ('2026-06-16', 'revisao_semana'),
                     ('2026-10-30', 'fechamento'), ('2026-10-31', null), ('2026-11-02', null),
                     ('2026-11-03', 'revisao_mes'), ('2026-11-04', 'revisao_semana'), ('2026-11-05', 'fechamento'),
                     ('2026-11-08', null), ('2026-11-09', 'revisao_semana'), ('2026-11-10', 'fechamento'),
                     ('2026-11-20', null), ('2026-11-30', 'revisao_semana'), ('2026-12-01', 'revisao_mes'),
                     ('2026-12-02', 'fechamento'), ('2027-02-01', 'revisao_mes'), ('2027-02-02', 'revisao_semana'),
                     ('2027-02-03', 'fechamento')) x(dia, turno)
    loop
      if v_f.calculado is distinct from v_f.turno then
        raise exception '3j: _retorno_turno_da_tarde(%) = % (o turnoDaTarde dá %)', v_f.dia, v_f.calculado, v_f.turno;
      end if;
    end loop;
    v_n := v_n + 1;
    v_secoes := v_secoes + 1;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;

  -- ── 4. Alongadas só na sexta; turno desconhecido; sem configuração ───────────────────────────────────
  begin
    update public.retorno_config set modo = 'sombra', tipos_ligados = '{}' where id;
    insert into public.retorno_alongamentos (faixa, de, para, casos, pct, em)
    values ('meio', '{"dias": 0, "hora": "19:00"}', '{"dias": 1, "hora": "10:00"}', 20, 0.75, c_seg + interval '4 hours'),
           ('tarde', '{"dias": 0, "hora": "10:00"}', '{"dias": 0, "hora": "19:00"}', 25, 0.72, c_seg - interval '4 days' + interval '4 hours'),
           ('noite', '{"dias": 0, "hora": "10:00"}', '{"dias": 0, "hora": "19:00"}', 21, 0.70, c_sex + interval '18 hours');
    v_r := public.retorno_resumo_do_dia('fechamento', c_sex + interval '17 hours 30 minutes');
    if v_r -> 'alongadas' is distinct from
       '[{"faixa": "meio", "de": {"dias": 0, "hora": "19:00"}, "para": {"dias": 1, "hora": "10:00"}, "casos": 20, "pct": 0.7500}]'::jsonb then
      raise exception '4a: na sexta, só o alongamento dos últimos 7 dias (nem o de 05/11, nem o do futuro): %', v_r -> 'alongadas';
    end if;
    v_r := public.retorno_resumo_do_dia('fechamento', c_fecha);
    if v_r -> 'alongadas' is distinct from '[]'::jsonb then
      raise exception '4b: fora da sexta, alongadas = []: %', v_r -> 'alongadas';
    end if;
    if public.retorno_resumo_do_dia('tarde', c_fecha) is distinct from '{"erro": "turno"}'::jsonb
       or public.retorno_resumo_do_dia(null, c_fecha) is distinct from '{"erro": "turno"}'::jsonb then
      raise exception '4c: turno desconhecido não deu {"erro": "turno"}';
    end if;
    update public.retorno_config set modo = 'desligado' where id;
    if public.retorno_resumo_do_dia('manha', c_manha) ->> 'modo' is distinct from 'desligado' then
      raise exception '4d: com o retorno desligado, modo = desligado';
    end if;
    delete from public.retorno_config where id;
    v_r := public.retorno_resumo_do_dia('manha', c_manha);
    if v_r ->> 'modo' is distinct from 'desligado' or v_r -> 'esperando' is distinct from '[]'::jsonb then
      raise exception '4e: sem a linha de configuração, modo desligado e nada quebra: %', v_r;
    end if;
    v_n := v_n + 1;
    v_secoes := v_secoes + 1;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;

  -- ── 5. A calibração por faixa ────────────────────────────────────────────────────────────────────────
  begin
    select coalesce(jsonb_object_agg(c.faixa, jsonb_build_object('casos', c.casos, 'no_prazo', c.no_prazo)), '{}'::jsonb)
      into v_cal_antes
      from public.retorno_calibracao c;
    -- meio (seg 05/10/2026, mensagem às 12:00, prometido 19h): conteúdo às 13, 14, 15 e 18h; um sem resposta
    for v_i in 1 .. 5 loop
      v_caso := pg_temp.retorno_f1_resumo_caso('55479000088' || (50 + v_i), 'cliente', '2026-10-05 12:00:00-03');
      update public.retorno_aberturas
         set recibo_em = '2026-10-05 12:02:00-03', prometido_ate = '2026-10-05 19:00:00-03', faixa = 'meio',
             cumprida_em = case v_i when 1 then '2026-10-05 13:00:00-03'::timestamptz when 2 then '2026-10-05 14:00:00-03'
                                    when 3 then '2026-10-05 15:00:00-03' when 4 then '2026-10-05 18:00:00-03' end,
             cumprida_por = case when v_i <= 4 then 'celular' end,
             estado = 'fechada', fechada_em = '2026-10-08 04:00:00-03',
             fechada_motivo = case when v_i <= 4 then 'conteudo' else 'expirou' end
       where id = v_caso;
    end loop;
    -- noite (23:00, prometido o dia seguinte 10h): nenhum respondido
    for v_i in 6 .. 7 loop
      v_caso := pg_temp.retorno_f1_resumo_caso('55479000088' || (50 + v_i), 'cliente', '2026-10-05 23:00:00-03');
      update public.retorno_aberturas
         set recibo_em = '2026-10-06 08:05:00-03', prometido_ate = '2026-10-06 10:00:00-03', faixa = 'noite',
             estado = 'fechada', fechada_em = '2026-10-09 04:00:00-03', fechada_motivo = 'expirou'
       where id = v_caso;
    end loop;
    -- Fora: o prazo ainda não passou e sem resposta (não se sabe ainda); e o caso sem recibo
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008858', 'cliente', '2026-10-05 12:00:00-03');
    update public.retorno_aberturas
       set recibo_em = '2026-10-05 12:02:00-03', prometido_ate = '2099-01-01 19:00:00-03', faixa = 'meio'
     where id = v_caso;
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008859', 'cliente', '2026-10-05 12:00:00-03');
    update public.retorno_aberturas set prometido_ate = '2026-10-05 19:00:00-03', faixa = 'meio' where id = v_caso;

    select coalesce(jsonb_object_agg(c.faixa, to_jsonb(c)), '{}'::jsonb) into v_cal from public.retorno_calibracao c;
    if coalesce((v_cal -> 'meio' ->> 'casos')::integer, 0) - coalesce((v_cal_antes -> 'meio' ->> 'casos')::integer, 0) <> 5
       or coalesce((v_cal -> 'meio' ->> 'no_prazo')::integer, 0) - coalesce((v_cal_antes -> 'meio' ->> 'no_prazo')::integer, 0) <> 4
       or coalesce((v_cal -> 'noite' ->> 'casos')::integer, 0) - coalesce((v_cal_antes -> 'noite' ->> 'casos')::integer, 0) <> 2
       or coalesce((v_cal -> 'noite' ->> 'no_prazo')::integer, 0) - coalesce((v_cal_antes -> 'noite' ->> 'no_prazo')::integer, 0) <> 0 then
      raise exception '5a: a calibração não contou os casos do arranjo (meio 5/4, noite 2/0): antes %, depois %', v_cal_antes, v_cal;
    end if;
    for v_row in select * from public.retorno_calibracao loop
      if v_row.wilson_inferior is null or v_row.wilson_inferior < 0 or v_row.wilson_inferior > 1
         or v_row.pct_no_prazo < 0 or v_row.pct_no_prazo > 1 or v_row.wilson_inferior > v_row.pct_no_prazo then
        raise exception '5b: a faixa % com wilson_inferior % fora de [0, pct_no_prazo %]', v_row.faixa, v_row.wilson_inferior,
          v_row.pct_no_prazo;
      end if;
    end loop;
    if coalesce((v_cal_antes -> 'meio' ->> 'casos')::integer, 0) = 0 then
      if (v_cal -> 'meio' ->> 'pct_no_prazo')::numeric <> 0.8
         or abs((v_cal -> 'meio' ->> 'wilson_inferior')::numeric - 0.3755) > 0.001
         or (v_cal -> 'meio' ->> 'mediana_ate_conteudo_min')::numeric <> 150
         or (v_cal -> 'meio' ->> 'hora_local_p80_conteudo') is distinct from '18:00:00' then
        raise exception '5c: a faixa meio (80%%, Wilson 0,3755, mediana 150 min, p80 18:00): %', v_cal -> 'meio';
      end if;
    end if;
    if coalesce((v_cal_antes -> 'noite' ->> 'casos')::integer, 0) = 0 then
      if (v_cal -> 'noite' ->> 'wilson_inferior')::numeric <> 0 or (v_cal -> 'noite' -> 'hora_local_p80_conteudo') <> 'null'::jsonb then
        raise exception '5d: a faixa noite (0%%: Wilson 0; p80 só nas faixas do mesmo dia): %', v_cal -> 'noite';
      end if;
    end if;
    v_n := v_n + 1;
    v_secoes := v_secoes + 1;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;

  -- ── 6. A lista da sombra ─────────────────────────────────────────────────────────────────────────────
  begin
    v_cl := pg_temp.retorno_f1_resumo_cliente('Lucas Lista Teste', '(47) 90000-8861');
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008861', 'cliente', c_ter + interval '9 hours', 'recibo', null, v_cl);
    select a.primeira_msg_id into v_msg from public.retorno_aberturas a where a.id = v_caso;
    update public.whatsapp_messages
       set body = 'CORPO-SECRETO-F1R lista: ' || repeat('preciso trocar a bateria do motorhome ', 6)
     where id = v_msg;
    v_s := pg_temp.retorno_f1_resumo_saida(v_caso, 'recibo_cliente', 'sombra', c_ter + interval '9 hours 2 minutes', null,
                                           '{"sombra_motivo": "modo"}'::jsonb);
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'fim_do_dia', 'enviada', c_ter + interval '18 hours 30 minutes');
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'cadastro_provisorio', 'sombra', c_ter + interval '9 hours 5 minutes');
    -- fora: acorde (não é texto ao cliente), recusada, cancelada
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'acorde', 'sombra', c_ter + interval '18 hours');
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'urgente', 'recusada', c_ter + interval '10 hours', 'validador');
    perform pg_temp.retorno_f1_resumo_saida(v_caso, 'adiamento', 'cancelada', c_ter + interval '18 hours 31 minutes', 'caso_fechado');

    if (select array_agg(l.tipo || '/' || l.estado order by l.tipo) from public.retorno_sombra_lista l where l.caso = v_caso)
       is distinct from array['cadastro_provisorio/sombra', 'fim_do_dia/enviada', 'recibo_cliente/sombra'] then
      raise exception '6a: a lista da sombra traz só sombra e enviada, fora o acorde: %',
        (select array_agg(l.tipo || '/' || l.estado) from public.retorno_sombra_lista l where l.caso = v_caso);
    end if;
    select to_jsonb(l) into v_e from public.retorno_sombra_lista l where l.saida_id = v_s;
    if v_e ->> 'trecho' is distinct from left((select w.body from public.whatsapp_messages w where w.id = v_msg), 140)
       or char_length(v_e ->> 'trecho') <> 140 or v_e ->> 'rotulo' is distinct from 'Lucas'
       or v_e ->> 'papel' is distinct from 'cliente' or v_e ->> 'nivel' is distinct from 'recibo'
       or v_e ->> 'sombra_motivo' is distinct from 'modo' or v_e ->> 'texto' is distinct from 'Teste F1 resumo: o texto que a saída teria.'
       or (v_e ->> 'caso')::uuid is distinct from v_caso
       or (v_e ->> 'decidida_em')::timestamptz is distinct from c_ter + interval '9 hours 2 minutes' then
      raise exception '6b: a linha do recibo na lista da sombra: %', v_e;
    end if;
    -- 42501 de verdade, como anon e como authenticated
    for v_f in
      select x.papel, x.consulta
        from (values ('anon', 'select count(*)::text from public.retorno_sombra_lista'),
                     ('authenticated', 'select count(*)::text from public.retorno_sombra_lista'),
                     ('anon', 'select count(*)::text from public.retorno_calibracao'),
                     ('authenticated', 'select count(*)::text from public.retorno_calibracao'),
                     ('anon', 'select public.retorno_resumo_do_dia(''manha'')::text'),
                     ('authenticated', 'select public.retorno_resumo_do_dia(''manha'')::text')) x(papel, consulta)
    loop
      v_x := pg_temp.retorno_f1_resumo_como(v_f.papel, v_f.consulta);
      if v_x is distinct from 'erro 42501' then
        raise exception '6c: % leu (%): %', v_f.papel, v_f.consulta, v_x;
      end if;
    end loop;
    -- E o service_role lê os três: a view chama o _retorno_rotulo como quem lê, e o execute vem dos privilégios padrão.
    -- count(rotulo), não count(*): a view é achatada, e sem usar a coluna a função sai do plano e o execute não é conferido.
    v_x := pg_temp.retorno_f1_resumo_como('service_role', 'select count(rotulo)::text from public.retorno_sombra_lista');
    if v_x is null or v_x like 'erro%' or v_x::integer < 3 then
      raise exception '6d: o service_role não leu a lista da sombra: %', v_x;
    end if;
    v_x := pg_temp.retorno_f1_resumo_como('service_role', 'select count(*)::text from public.retorno_calibracao');
    if v_x is null or v_x like 'erro%' then
      raise exception '6d: o service_role não leu a calibração: %', v_x;
    end if;
    v_x := pg_temp.retorno_f1_resumo_como('service_role', 'select public.retorno_resumo_do_dia(''manha'')::text');
    if v_x is null or v_x like 'erro%' then
      raise exception '6d: o service_role não leu o resumo: %', v_x;
    end if;
    v_n := v_n + 1;
    v_secoes := v_secoes + 1;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;

  -- ── 7. O próximo evento do relógio (o replay) ────────────────────────────────────────────────────────
  begin
    update public.retorno_config
       set acorde_antes = interval '60 minutes', adiamento_antes = interval '30 minutes',
           caso_fecha_silencio = interval '4 hours', incerta_conferir_ate = interval '30 minutes'
     where id;
    -- caso aberto às 08:30 com recibo e prometido 19h; uma agendada às 09:05
    v_caso := pg_temp.retorno_f1_resumo_caso('5547900008871', 'cliente', c_ter + interval '8 hours 30 minutes');
    update public.retorno_aberturas
       set recibo_em = c_ter + interval '8 hours 32 minutes', prometido_ate = c_ter + interval '19 hours', faixa = 'manha_cedo'
     where id = v_caso;
    v_s := pg_temp.retorno_f1_resumo_saida(v_caso, 'urgente', 'agendada', null, null, '{}'::jsonb, c_ter + interval '9 hours 5 minutes');
    v_t := public._retorno_proximo_evento(c_ter + interval '9 hours');
    if v_t is distinct from c_ter + interval '9 hours 5 minutes' then
      raise exception '7a: o próximo evento às 09:00 é a agendada das 09:05, não %', v_t;
    end if;
    update public.retorno_saidas set estado = 'cancelada', motivo = 'caso_fechado' where id = v_s;
    v_t := public._retorno_proximo_evento(c_ter + interval '9 hours');
    if v_t is distinct from c_ter + interval '18 hours' then
      raise exception '7b: sem agendada, o próximo é o acorde do relógio (19h − 60 min), não %', v_t;
    end if;
    v_t := public._retorno_proximo_evento(c_ter + interval '18 hours');
    if v_t is distinct from c_ter + interval '18 hours 30 minutes' then
      raise exception '7c: depois do acorde, o adiamento (19h − 30 min), não %', v_t;
    end if;
    v_t := public._retorno_proximo_evento(c_ter + interval '19 hours');
    if v_t is distinct from c_ter + interval '1 day 4 hours' then
      raise exception '7d: depois de X, a próxima 04:00 de Brasília, não %', v_t;
    end if;
    -- o caso do futuro (gravado às 08:30) não conta às 02:00: a próxima é a 04:00 do mesmo dia
    v_t := public._retorno_proximo_evento(c_ter + interval '2 hours');
    if v_t is distinct from c_ter + interval '4 hours' then
      raise exception '7e: às 02:00 (o caso ainda não existia), a próxima 04:00, não %', v_t;
    end if;
    v_n := v_n + 1;
    v_secoes := v_secoes + 1;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;

  if v_secoes <> 8 then
    raise exception '0f: o arranjo não chegou ao fim (% de 8 seções)', v_secoes;
  end if;
  if exists (select 1 from public.retorno_aberturas a where a.chave like '000088%')
     or exists (select 1 from public.retorno_saidas s where s.chave like '000088%')
     or exists (select 1 from public.whatsapp_messages w where w.phone_normalized like '55479000088%')
     or exists (select 1 from public.clients c where public._agenda_chave_telefone(c.whatsapp) like '000088%')
     or (select count(*) from public.retorno_alongamentos) <> v_along_antes
     or (select to_jsonb(c) from public.retorno_config c where c.id) is distinct from v_cfg_antes then
    raise exception '0g: o arranjo não foi desfeito';
  end if;

  insert into _bancada (arquivo, ok, numeros)
  values ('retorno_f1_resumo', true, jsonb_build_object('conferencias', v_n, 'secoes', v_secoes));
end
$resumo$;

select arquivo, ok, numeros from _bancada order by em;
rollback;

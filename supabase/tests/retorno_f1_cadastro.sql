-- Retorno F1 (P6): o cadastro provisório do número novo (retorno_cadastro_provisorio, C-CADASTRO) e a decisão dele
-- pelo vigia (retorno_vigia, passo 7), 20261116100800_retorno_f1_vigia.sql.
--   0. as funções e as premissas (nenhum cadastro real com os números, documentos e nomes de teste; nada vivo fora
--      dos números de teste, porque o vigia do caso 11 processa o banco inteiro);
--   1. a regra de procurarDuplicados (_shared/ai/tools/clients.ts:104-130), com os casos que ela trata:
--      - mesmo CPF, com e sem pontuação ('mesmo documento');
--      - mesmo telefone, com e sem 55/9 ('mesmo telefone'), inclusive de cliente INATIVO e do "Cliente Final";
--      - "João da Silva" × "JOAO  DA SILVA" = 'mesmo nome', e nada é criado mesmo executando;
--      - nome parecido mas diferente = nenhum (criaria);
--   2. p_executar = false nunca cria; true cria o cliente provisorio/origem retorno, a unidade "Motorhome" e a linha
--      de audit_log com o record_id do cliente, sem vincular o lead (o quem_escreve passa a reconhecer o número); de
--      novo = perguntar (mesmo telefone), nada em dobro; o modelo sem bem dito não vira unidade;
--   3. sem coleta.nome → sem_nome, inclusive com a coleta 2 só em sombra; papel cliente → papel; sem pedido →
--      sem_pedido; caso que não existe → sem_caso;
--   4. o vigia decide a saída cadastro_provisorio: em sombra, criaria = sombra; perguntar = recusada/duplicado_pergunta;
--      nada = cancelada/sem_nome; ligado (com o grupo e o recibo do caso enviado), criado = enviada.
-- Cadastros e mensagens SINTÉTICOS de 55479000089xx, com a data de ter 06/04/2027 (Brasília).
-- Run (só pela bancada, de madrugada): npx supabase@2.111.0 db query --linked -f supabase/tests/retorno_f1_cadastro.sql
-- Termina em ROLLBACK: nada fica gravado. Todo o arranjo é desfeito dentro do arquivo (sub-bloco 'desfaz').
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- Um caso sintético de número novo (com a 1ª mensagem) e, se pedida, a 2ª mensagem da coleta no estado dado.
create or replace function pg_temp.retorno_f1_cadastro_caso(p_fone text, p_coleta jsonb, p_coleta_estado text default 'enviada',
                                                           p_papel text default 'numero_novo', p_pedido boolean default true)
returns uuid
language plpgsql as $f$
declare
  c_t constant timestamptz := '2027-04-06 10:00:00-03';
  v_msg uuid;
  v_id uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload,
                                        hora_real, occurred_at)
  values ('inbound', p_fone, 'text', 'Teste F1 cadastro: preciso trocar a bateria do motorhome', 'received', '{"data": {}}', c_t, c_t)
  returning id into v_msg;
  insert into public.retorno_aberturas (chave, phone_normalized, papel, quem, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, coleta, modo)
  values (public._agenda_chave_telefone(p_fone), p_fone, p_papel, jsonb_build_object('papel', p_papel), v_msg, v_msg,
          c_t, c_t, c_t, c_t, 'recibo',
          case when p_papel = 'numero_novo' and p_pedido then 'recibo_numero_novo'
               when p_papel = 'cliente' then 'recibo_cliente' end,
          p_coleta, 'sombra')
  returning id into v_id;
  if p_coleta_estado is not null then
    insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, modo, estado,
                                       enviar_em, decidida_em, enviada_em, texto, dedupe_key)
    values (v_id, 'coleta_numero_novo', 'nome', 'retorno_coleta', 'resposta_imediata', public._agenda_chave_telefone(p_fone),
            p_fone, case when p_coleta_estado = 'enviada' then 'ligado' else 'sombra' end, p_coleta_estado,
            c_t + interval '5 minutes', c_t + interval '5 minutes',
            case when p_coleta_estado = 'enviada' then c_t + interval '5 minutes' end,
            'Obrigado! Já passei ao Gustavo. Como posso te chamar?', 'retorno:' || v_id || ':coleta');
  end if;
  return v_id;
end $f$;

-- A saída cadastro_provisorio agendada do caso (como a P5 a agenda); o id.
create or replace function pg_temp.retorno_f1_cadastro_saida(p_caso uuid)
returns uuid
language sql as $f$
  insert into public.retorno_saidas (abertura_id, tipo, chave, phone_normalized, modo, estado, enviar_em, dedupe_key)
  select a.id, 'cadastro_provisorio', a.chave, a.phone_normalized, a.modo, 'agendada', '2027-04-06 10:06:00-03',
         'retorno:' || a.id || ':cadastro'
    from public.retorno_aberturas a where a.id = p_caso
  returning id
$f$;

-- Confere {acao: perguntar} com um duplicado (o cliente e o motivo) na lista.
create or replace function pg_temp.retorno_f1_cadastro_pergunta(p_caso text, p_r jsonb, p_cliente uuid, p_motivo text)
returns integer
language plpgsql as $f$
begin
  if p_r ->> 'acao' is distinct from 'perguntar' or jsonb_typeof(p_r -> 'duplicados') is distinct from 'array'
     or not exists (select 1 from jsonb_array_elements(p_r -> 'duplicados') d
                     where d ->> 'client_id' = p_cliente::text and d ->> 'motivo' = p_motivo and d ? 'nome') then
    raise exception '%: esperado perguntar com % (%), veio %', p_caso, p_cliente, p_motivo, p_r;
  end if;
  return 1;
end $f$;

do $cadastro$
declare
  c_t constant timestamptz := '2027-04-06 10:00:00-03';
  v_f record;
  v_cfg_antes jsonb;
  v_chegou boolean := false;
  v_n integer := 0;
  v_clientes bigint;
  v_c uuid; v_c2 uuid;
  v_caso uuid; v_caso2 uuid; v_caso3 uuid;
  v_r jsonb;
  v_v jsonb;
  v_id uuid; v_id2 uuid; v_id3 uuid;
  v_cli public.clients;
  v_ve public.vessels;
  v_au public.audit_log;
  v_s public.retorno_saidas;
  v_lead uuid;
begin
  -- ── 0. As funções e as premissas ────────────────────────────────────────────────────────────────────
  for v_f in
    select p.oid, p.provolatile, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from pg_proc p where p.oid = to_regprocedure('public.retorno_cadastro_provisorio(uuid, boolean)')
  loop
    if v_f.provolatile <> 'v' or not v_f.prosecdef or not ('search_path=public' = any (v_f.config))
       or has_function_privilege('anon', v_f.oid, 'execute') or has_function_privilege('authenticated', v_f.oid, 'execute')
       or not has_function_privilege('service_role', v_f.oid, 'execute') then
      raise exception '0: retorno_cadastro_provisorio fora do molde (VOLATILE, SECURITY DEFINER, só o service_role)';
    end if;
  end loop;
  if to_regprocedure('public.retorno_cadastro_provisorio(uuid, boolean)') is null
     or to_regprocedure('public._retorno_nome_comparavel(text)') is null then
    raise exception '0: faltam retorno_cadastro_provisorio ou _retorno_nome_comparavel';
  end if;
  if public._retorno_nome_comparavel('  JOÃO  da Silva ') <> 'joao da silva' then
    raise exception '0: _retorno_nome_comparavel não é o semAcento de busca-cadastro.ts';
  end if;
  select to_jsonb(c) into v_cfg_antes from public.retorno_config c where c.id;
  if not found then
    raise exception '0b: retorno_config sem a linha de configuração';
  end if;
  if exists (select 1 from public.whatsapp_messages w where w.phone_normalized like '55479000089%')
     or exists (select 1 from public.clients c
                 where public._agenda_chave_telefone(c.phone) like '000089%' or public._agenda_chave_telefone(c.whatsapp) like '000089%'
                    or public._doc_normalizado(c.cpf_cnpj) in ('89089089089', '89189189191')
                    or public._retorno_nome_comparavel(c.name) in ('joao da silveira testolino', 'quiteria testeira',
                                                                   'teodoro testeiro', 'valquiria testona'))
     or exists (select 1 from public.whatsapp_leads l where l.phone_normalized like '55479000089%') then
    raise exception '0c: há mensagem, cadastro ou lead real com os números, documentos ou nomes de teste';
  end if;
  if exists (select 1 from public.retorno_aberturas a where a.estado in ('aberta', 'vencida') and a.chave not like '000089%')
     or exists (select 1 from public.retorno_saidas s where s.estado in ('agendada', 'preparada', 'enviando', 'incerta')
                                                       and s.chave not like '000089%')
     or exists (select 1 from public.retorno_aberturas a where a.chave like '000089%') then
    raise exception '0d: há caso vivo ou saída pendente que o vigia do caso 4 trataria (o arquivo é da bancada de antes do deploy)';
  end if;

  begin
    update public.retorno_config
       set modo = 'sombra', tipos_ligados = '{}', so_reativo = false, so_reativo_motivo = null, so_reativo_desde = null,
           segura_recibos = false, segura_tudo_ate = null
     where id;
    update public.whatsapp_conexao_vigia set estado = 'open', desde = '2027-01-01 00:00:00-03' where id = 1;

    -- ── 1. A regra de procurarDuplicados ─────────────────────────────────────────────────────────────
    -- 1a. Mesmo CPF: com pontuação na coleta, sem no cadastro.
    insert into public.clients (type, name, cpf_cnpj) values ('individual', 'Teste F1 cadastro documento A', '89089089089')
      returning id into v_c;
    v_caso := pg_temp.retorno_f1_cadastro_caso('5547900008901',
      '{"nome": "Roberval Testador Primeiro", "documento": "890.890.890-89", "tipo": "Motorhome"}');
    v_n := v_n + pg_temp.retorno_f1_cadastro_pergunta('1a', public.retorno_cadastro_provisorio(v_caso, false), v_c, 'mesmo documento');
    -- 1b. Mesmo CPF: sem pontuação na coleta, com no cadastro (inativo).
    insert into public.clients (type, name, cpf_cnpj, active) values ('individual', 'Teste F1 cadastro documento B', '891.891.891-91', false)
      returning id into v_c;
    v_caso := pg_temp.retorno_f1_cadastro_caso('5547900008902',
      '{"nome": "Roberval Testador Segundo", "documento": "89189189191", "tipo": "Motorhome"}');
    v_n := v_n + pg_temp.retorno_f1_cadastro_pergunta('1b', public.retorno_cadastro_provisorio(v_caso, false), v_c, 'mesmo documento');
    -- 1c. Mesmo telefone, cadastro sem 55 e sem 9, de cliente INATIVO.
    insert into public.clients (type, name, phone, active) values ('individual', 'Teste F1 cadastro inativo', '(47) 0000-8903', false)
      returning id into v_c;
    v_caso := pg_temp.retorno_f1_cadastro_caso('5547900008903', '{"nome": "Sebastiana Testada", "tipo": "Motorhome"}');
    v_n := v_n + pg_temp.retorno_f1_cadastro_pergunta('1c', public.retorno_cadastro_provisorio(v_caso, false), v_c, 'mesmo telefone');
    -- 1d. Mesmo telefone, cadastro com 55 e 9, do "Cliente Final" (genérico).
    insert into public.clients (type, name, whatsapp, generico) values ('individual', 'Cliente Final (teste F1 cadastro)', '+55 47 90000-8904', true)
      returning id into v_c;
    v_caso := pg_temp.retorno_f1_cadastro_caso('5547900008904', '{"nome": "Sebastiana Testada", "tipo": "Motorhome"}');
    v_n := v_n + pg_temp.retorno_f1_cadastro_pergunta('1d', public.retorno_cadastro_provisorio(v_caso, false), v_c, 'mesmo telefone');
    -- 1e. "João da Silva" × "JOAO  DA SILVA": mesmo nome, e nada é criado mesmo executando.
    insert into public.clients (type, name) values ('individual', 'JOAO  DA SILVA') returning id into v_c;
    v_caso := pg_temp.retorno_f1_cadastro_caso('5547900008905', '{"nome": "João da Silva", "tipo": "Motorhome"}');
    select count(*) into v_clientes from public.clients;
    v_r := public.retorno_cadastro_provisorio(v_caso, true);
    v_n := v_n + pg_temp.retorno_f1_cadastro_pergunta('1e', v_r, v_c, 'mesmo nome');
    if (select count(*) from public.clients) <> v_clientes then
      raise exception '1e: com o nome igual, o cadastro foi criado mesmo assim';
    end if;
    -- 1f. Nome parecido mas diferente ("João da Silveira Testolino"): nenhum duplicado; sem executar, criaria.
    v_caso := pg_temp.retorno_f1_cadastro_caso('5547900008906',
      '{"nome": "João da Silveira Testolino", "tipo": "Motorhome", "modelo": "Ducato 2019"}');
    select count(*) into v_clientes from public.clients;
    v_r := public.retorno_cadastro_provisorio(v_caso, false);
    if v_r is distinct from '{"acao": "criaria", "nome": "João da Silveira Testolino", "unidade": {"asset_type": "Motorhome", "name": "Ducato 2019"}}'::jsonb
       or (select count(*) from public.clients) <> v_clientes then
      raise exception '1f/2: o nome parecido virou duplicado, ou p_executar = false criou: %', v_r;
    end if;

    -- ── 2. Executando ────────────────────────────────────────────────────────────────────────────────
    v_caso2 := pg_temp.retorno_f1_cadastro_caso('5547900008907', '{"nome": "Quitéria Testeira", "tipo": "Motorhome", "modelo": null}');
    insert into public.whatsapp_leads (phone_normalized, name) values ('5547900008907', 'Teste F1 cadastro lead') returning id into v_lead;
    v_r := public.retorno_cadastro_provisorio(v_caso2, true);
    if v_r ->> 'acao' is distinct from 'criado' or v_r ->> 'client_id' is null or v_r ->> 'vessel_id' is null then
      raise exception '2: executando, o cadastro não foi criado: %', v_r;
    end if;
    select * into v_cli from public.clients where id = (v_r ->> 'client_id')::uuid;
    select * into v_ve from public.vessels where id = (v_r ->> 'vessel_id')::uuid;
    select * into v_au from public.audit_log where record_id = v_cli.id;
    if not v_cli.provisorio or v_cli.origem is distinct from 'retorno' or not v_cli.active or v_cli.type is distinct from 'individual'
       or v_cli.name is distinct from 'Quitéria Testeira' or v_cli.whatsapp is distinct from '5547900008907' then
      raise exception '2: o cliente provisório está fora do molde: %', to_jsonb(v_cli);
    end if;
    if v_ve.client_id is distinct from v_cli.id or v_ve.name is distinct from 'Motorhome' or v_ve.asset_type is distinct from 'Motorhome'
       or not v_ve.active then
      raise exception '2: a unidade "Motorhome" está fora do molde: %', to_jsonb(v_ve);
    end if;
    if v_au.id is null or v_au.table_name is distinct from 'clients' or v_au.changed_by is distinct from 'retorno'
       or v_au.action is distinct from 'lead_converted'
       or v_au.reason is distinct from 'Cadastro provisório pelo retorno (caso ' || v_caso2 || ')'
       or v_au.new_value ->> 'vessel_id' is distinct from v_ve.id::text then
      raise exception '2: a linha de audit_log está fora do molde: %', to_jsonb(v_au);
    end if;
    if (select linked_client_id from public.whatsapp_leads where id = v_lead) is not null then
      raise exception '2: o cadastro provisório vinculou o lead (vínculo é pergunta)';
    end if;
    if public.quem_escreve('5547900008907') ->> 'papel' is distinct from 'cliente'
       or public.quem_escreve('5547900008907') ->> 'cliente_id' is distinct from v_cli.id::text then
      raise exception '2: com o telefone no cadastro, o quem_escreve não reconhece o número: %', public.quem_escreve('5547900008907');
    end if;
    -- De novo: agora o número tem cadastro (mesmo telefone) → perguntar, nada em dobro.
    v_n := v_n + pg_temp.retorno_f1_cadastro_pergunta('2', public.retorno_cadastro_provisorio(v_caso2, true), v_cli.id, 'mesmo telefone');
    if (select count(*) from public.clients where whatsapp = '5547900008907') <> 1 then
      raise exception '2: a 2ª chamada criou outro cadastro';
    end if;
    -- O modelo sem bem dito não vira unidade (os modelos não viram Motorhome).
    v_caso3 := pg_temp.retorno_f1_cadastro_caso('5547900008908', '{"nome": "Teodoro Testeiro", "tipo": null, "modelo": "Ducato 2019"}');
    v_r := public.retorno_cadastro_provisorio(v_caso3, false);
    if v_r is distinct from '{"acao": "criaria", "nome": "Teodoro Testeiro", "unidade": null}'::jsonb then
      raise exception '2: o modelo sem bem dito virou unidade: %', v_r;
    end if;

    -- ── 3. Quando não há o que cadastrar ─────────────────────────────────────────────────────────────
    v_id := pg_temp.retorno_f1_cadastro_caso('5547900008909', '{"nome": null, "tipo": "Motorhome"}');
    v_r := public.retorno_cadastro_provisorio(v_id, true);
    if v_r is distinct from '{"acao": "nada", "motivo": "sem_nome"}'::jsonb then
      raise exception '3: sem coleta.nome não deu sem_nome: %', v_r;
    end if;
    v_id2 := pg_temp.retorno_f1_cadastro_caso('5547900008910', '{"nome": "Ruth Testinha", "tipo": "Motorhome"}', 'sombra');
    v_r := public.retorno_cadastro_provisorio(v_id2, true);
    if v_r is distinct from '{"acao": "nada", "motivo": "sem_nome"}'::jsonb then
      raise exception '3: com a coleta 2 só em sombra (a pergunta nunca saiu), o nome valeu: %', v_r;
    end if;
    v_id3 := pg_temp.retorno_f1_cadastro_caso('5547900008911', '{"nome": "Ruth Testinha", "tipo": "Motorhome"}', 'enviada', 'cliente');
    v_r := public.retorno_cadastro_provisorio(v_id3, true);
    if v_r is distinct from '{"acao": "nada", "motivo": "papel"}'::jsonb then
      raise exception '3: o papel cliente não deu papel: %', v_r;
    end if;
    v_r := public.retorno_cadastro_provisorio(pg_temp.retorno_f1_cadastro_caso('5547900008912', '{"nome": "Ruth Testinha"}', 'enviada',
                                                                              'numero_novo', false), true);
    if v_r is distinct from '{"acao": "nada", "motivo": "sem_pedido"}'::jsonb then
      raise exception '3: o número novo sem pedido não deu sem_pedido: %', v_r;
    end if;
    if public.retorno_cadastro_provisorio(gen_random_uuid(), true) is distinct from '{"acao": "nada", "motivo": "sem_caso"}'::jsonb then
      raise exception '3: o caso que não existe não deu sem_caso';
    end if;
    if exists (select 1 from public.clients where name = 'Ruth Testinha') then
      raise exception '3: algum caminho "nada" criou cadastro';
    end if;

    -- ── 4. O vigia decide a saída cadastro_provisorio ────────────────────────────────────────────────
    -- 4a. Em sombra: criaria = sombra; perguntar = recusada/duplicado_pergunta; nada = cancelada/sem_nome.
    v_id := pg_temp.retorno_f1_cadastro_saida((select a.id from public.retorno_aberturas a where a.chave = '00008906'));
    v_id2 := pg_temp.retorno_f1_cadastro_saida((select a.id from public.retorno_aberturas a where a.chave = '00008905'));
    v_id3 := pg_temp.retorno_f1_cadastro_saida((select a.id from public.retorno_aberturas a where a.chave = '00008909'));
    select count(*) into v_clientes from public.clients;
    v_v := public.retorno_vigia(c_t + interval '10 minutes');
    if v_v -> 'ok' is distinct from 'true'::jsonb then
      raise exception '4a: retorno_vigia com erro num passo: %', v_v;
    end if;
    select * into v_s from public.retorno_saidas where id = v_id;
    if v_s.estado is distinct from 'sombra' or v_s.dados -> 'cadastro' ->> 'acao' is distinct from 'criaria'
       or v_s.dados ->> 'sombra_motivo' is distinct from 'modo' or v_s.decidida_em is distinct from c_t + interval '10 minutes' then
      raise exception '4a: o cadastro em sombra não ficou "eu teria criado": %', to_jsonb(v_s);
    end if;
    select * into v_s from public.retorno_saidas where id = v_id2;
    if v_s.estado is distinct from 'recusada' or v_s.motivo is distinct from 'duplicado_pergunta'
       or jsonb_typeof(v_s.dados -> 'duplicados') is distinct from 'array' then
      raise exception '4a: o cadastro com duplicado não virou recusada/duplicado_pergunta: %', to_jsonb(v_s);
    end if;
    select * into v_s from public.retorno_saidas where id = v_id3;
    if v_s.estado is distinct from 'cancelada' or v_s.motivo is distinct from 'sem_nome' then
      raise exception '4a: o cadastro sem nome não virou cancelada/sem_nome: %', to_jsonb(v_s);
    end if;
    if (select count(*) from public.clients) <> v_clientes then
      raise exception '4a: em sombra o vigia criou cadastro';
    end if;
    -- 4b. Ligado, com o grupo inteiro e o recibo do caso enviado: criado = enviada.
    update public.retorno_config
       set modo = 'ligado', tipos_ligados = '{recibo_numero_novo,coleta_numero_novo,cadastro_provisorio,adiamento,fim_do_dia}'
     where id;
    v_caso := pg_temp.retorno_f1_cadastro_caso('5547900008913', '{"nome": "Valquíria Testona", "tipo": "Lancha", "modelo": null}');
    insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, modo, estado,
                                       enviar_em, decidida_em, enviada_em, texto, dedupe_key)
    values (v_caso, 'recibo_numero_novo', 'pergunta_modelo', 'retorno_recibo', 'resposta_imediata', '00008913', '5547900008913',
            'ligado', 'enviada', c_t + interval '2 minutes', c_t + interval '2 minutes', c_t + interval '2 minutes',
            'Teste F1 cadastro: o recibo enviado.', 'retorno:' || v_caso || ':recibo');
    v_id := pg_temp.retorno_f1_cadastro_saida(v_caso);
    v_v := public.retorno_vigia(c_t + interval '12 minutes');
    select * into v_s from public.retorno_saidas where id = v_id;
    if v_v -> 'ok' is distinct from 'true'::jsonb or v_s.estado is distinct from 'enviada' or v_s.modo is distinct from 'ligado'
       or v_s.enviada_em is distinct from c_t + interval '12 minutes' or v_s.dados -> 'cadastro' ->> 'acao' is distinct from 'criado'
       or not exists (select 1 from public.clients c join public.vessels v on v.client_id = c.id
                       where c.id = (v_s.dados -> 'cadastro' ->> 'client_id')::uuid and c.provisorio
                         and c.name = 'Valquíria Testona' and v.asset_type = 'Lancha' and v.name = 'Lancha') then
      raise exception '4b: ligado, o vigia não executou o cadastro provisório: % / %', to_jsonb(v_s), v_v;
    end if;

    v_chegou := true;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;
  if not v_chegou then
    raise exception '0e: o arranjo não chegou ao fim';
  end if;
  if exists (select 1 from public.retorno_aberturas a where a.chave like '000089%')
     or exists (select 1 from public.whatsapp_messages w where w.phone_normalized like '55479000089%')
     or exists (select 1 from public.clients c where c.provisorio or c.name like 'Teste F1 cadastro%')
     or (select to_jsonb(c) from public.retorno_config c where c.id) is distinct from v_cfg_antes then
    raise exception '0f: o arranjo não foi desfeito';
  end if;

  insert into _bancada (arquivo, ok, numeros)
  values ('retorno_f1_cadastro', true, jsonb_build_object('perguntas_conferidas', v_n));
end
$cadastro$;

select arquivo, ok, numeros from _bancada order by em;
rollback;

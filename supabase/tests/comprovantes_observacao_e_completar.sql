-- Prova: a observação no CMP e a correção do assistente numa transação só (migration 20261012100000;
-- usa 20261011202000, 20261011302000, 20261011303000 e 20261011304000).
--
--   T1  a coluna observacao nasce nula e aceita de 1 a 200 letras
--   T2  "corrigir cmp N obs …": guarda como veio, mostra sem CPF, sobe a versão, repete a mesma pergunta;
--       nula apaga; 201 letras = obs_longa (nada muda); CMP gravado = ja_gravado
--   T3  tudo ou nada pelo comando: categoria aplicada + OS que não existe = nada fica (nem a pergunta)
--   T4  tudo ou nada pela resposta: valor, forma e obs aplicados + "quem pagou: cliente" fora da OS = nada fica
--   T5  o caso real do CMP-00001 (lido 204,87; aguardando a vez no "para quê"): categoria, 235,97 e a
--       observação numa chamada; uma pergunta aberta; nada no financeiro
--   T6  a observação obrigatória quando o valor muda; a já guardada no CMP vale
--   T7  as recusas antes de escrever (não é o dono, não existe, na fila, cancelado, gravado, data futura)
--   T8  a descrição do lançamento: igual à de antes sem observação; "· Obs: …" sem CPF; pela rota real
--   T9  os dois _INDICE do mês trazem a observação sem CPF
--   T10 a consulta do assistente traz a observação sem CPF
--   T11 privilégios do comprovante_completar e do _comprovante_descricao
--   T12 os passos sem comando pelo completar (quem pagou com message_id nulo) chegam ao resumo sem gravar
--   T13 o CPF colado em pontuação ("CPF 123.456.789-09.", "CPF:12345678909", "(…)") também sai de todas as
--       saídas da observação (_comprovante_obs_sem_cpf); o helper sem grant para ninguém
--
-- ═══ COMO RODAR ═══ (só com OK nomeado; também roda no ensaio PGlite da bancada)
--
--   supabase db query --linked -f supabase/tests/comprovantes_observacao_e_completar.sql --output json
--
-- Seguro em produção: cria um dono de teste (admin com created_at em 2000, que vira o
-- _comprovante_dono() só dentro da transação), uma categoria de despesa de nome aleatório, liga a
-- conversa só dentro da transação e termina em ROLLBACK. O T8 grava pela rota real (saída do Caixa com
-- valor aleatório): tudo some no rollback. Sem id nem data fixa. Nenhuma mensagem sai (a fila de envio
-- não é tocada: a RPC só abre a pergunta; quem manda é a edge).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _ctx (dono uuid, phone text, categoria text) on commit drop;
create temp table _cmps (nome text primary key, id uuid) on commit drop;

-- ── helpers da transação (somem no rollback) ────────────────────────────────────────────────
create function pg_temp._telefone() returns text language sql volatile as $$
  select '55000' || lpad((floor(random() * 1000000000))::bigint::text, 9, '0')
$$;
create function pg_temp._letras(n integer) returns text language sql volatile as $$
  select translate(substr(md5(random()::text || clock_timestamp()::text), 1, n), '0123456789', 'ghijklmnop')
$$;
create function pg_temp._val() returns numeric language sql volatile as $$
  select round((1000 + random() * 8000)::numeric, 2)
$$;
create function pg_temp._hoje() returns date language sql stable as $$ select (now() at time zone 'America/Sao_Paulo')::date $$;
-- o valor como a edge manda ("235.97")
create function pg_temp._txt(p numeric) returns text language sql immutable as $$ select to_char(p, 'FM9999999990.00') $$;

do $$
declare
  v_dono uuid := gen_random_uuid();
  v_phone text := pg_temp._telefone();
  v_cat text := 'Categoria teste obs ' || pg_temp._letras(8);
begin
  insert into public.app_users (id, full_name, email, role, active, phone_normalized, ai_whatsapp_enabled, created_at)
  values (v_dono, 'Dono de teste obs', 'teste-obs-' || v_dono || '@teste.invalido', 'admin', true, v_phone, true,
          now() - interval '30 years');
  insert into public.app_settings (key, value) values ('comprovante_fluxo', 'dono')
  on conflict (key) do update set value = excluded.value;
  insert into public.app_settings (key, value) values ('comprovante_conversa', 'on')
  on conflict (key) do update set value = excluded.value;
  -- a categoria de despesa do teste (nome aleatório: não depende das de produção)
  insert into public.financial_categories (name, type, active, dre_group) values (v_cat, 'payable', true, 'despesa_operacional');
  insert into _ctx values (v_dono, v_phone, v_cat);
end $$;

create function pg_temp._dono() returns uuid language sql stable as $$ select dono from _ctx $$;
create function pg_temp._phone() returns text language sql stable as $$ select phone from _ctx $$;
create function pg_temp._cat() returns text language sql stable as $$ select categoria from _ctx $$;
-- o texto do dono com um CPF no meio, e como ele tem de sair (sem o CPF)
create function pg_temp._obs_cpf() returns text language sql immutable as $$
  select 'complemento de R$ 31,10 123.456.789-09 sem cupom'
$$;
create function pg_temp._obs_limpa() returns text language sql immutable as $$ select 'complemento de R$ 31,10 sem cupom' $$;

-- um CMP lido do dono de teste (direto na tabela: o caminho da F1 tem os próprios testes)
create function pg_temp._cmp(p jsonb default '{}'::jsonb) returns uuid language plpgsql as $$
declare
  v uuid;
begin
  insert into public.comprovantes (numero, situacao, modo, rota, origem, dono_id, wa_message_id, phone_normalized,
                                   tipo_whatsapp, recebido_em, arquivo_sha256, tipo, confianca, valor, valor_confianca,
                                   data_compra, data_confianca, forma_pagamento, legenda, dica_da_legenda, lido_em)
  values (public._comprovante_proximo_numero(), 'lido', 'dono', 'comprovante', 'webhook', pg_temp._dono(),
          'TESTE-OBS-' || gen_random_uuid(), pg_temp._phone(), 'image', now(),
          md5(random()::text || clock_timestamp()::text) || md5(clock_timestamp()::text || random()::text),
          coalesce(p->>'tipo', 'nfce'), 'alta', coalesce((p->>'valor')::numeric, pg_temp._val()),
          'alta', coalesce((p->>'data')::date, pg_temp._hoje()), 'alta', p->>'forma', null, null, now())
  returning id into v;
  return v;
end $$;

create function pg_temp._numero(p_id uuid) returns integer language sql stable as $$
  select numero from public.comprovantes where id = p_id
$$;

-- deixa o telefone livre: fecha a pergunta aberta e tira da fila o que sobrou do teste anterior
create function pg_temp._livrar() returns void language plpgsql as $$
begin
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste'
   where phone_normalized = pg_temp._phone() and status = 'aberta';
  update public.comprovantes set situacao = 'cancelado', motivo_cancelamento = 'dono_cancelou', cancelado_em = now()
   where phone_normalized = pg_temp._phone() and situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim');
  update public.comprovantes_fila_do_telefone set pausada_ate = null, ultima_pergunta_fechada_em = null
   where phone_normalized = pg_temp._phone();
  delete from public.whatsapp_messages where phone_normalized = pg_temp._phone();
end $$;

-- o que o tudo-ou-nada não pode mudar no CMP
create function pg_temp._estado(p_id uuid) returns jsonb language sql stable as $$
  select jsonb_build_object('categoria', x.categoria, 'valor_confirmado', x.valor_confirmado, 'observacao', x.observacao,
                            'resumo_versao', x.resumo_versao, 'passo', x.passo, 'situacao', x.situacao, 'destino', x.destino,
                            'destino_os_id', x.destino_os_id, 'forma_confirmada', x.forma_confirmada,
                            'quem_pagou', x.quem_pagou, 'data_confirmada', x.data_confirmada, 'gravado_em', x.gravado_em)
    from public.comprovantes x where x.id = p_id
$$;
-- as linhas do registro de perguntas do telefone (todas, e as abertas)
create function pg_temp._perguntas() returns integer language sql stable as $$
  select count(*)::integer from public.whatsapp_perguntas where phone_normalized = pg_temp._phone()
$$;
create function pg_temp._abertas() returns integer language sql stable as $$
  select count(*)::integer from public.whatsapp_perguntas where phone_normalized = pg_temp._phone() and status = 'aberta'
$$;

-- o pedido do assistente, como a edge manda (o dono, o telefone e o número do CMP já postos)
create function pg_temp._completar(p_id uuid, p jsonb) returns jsonb language sql as $$
  select public.comprovante_completar(jsonb_build_object('phone', pg_temp._phone(), 'autor', pg_temp._dono(),
                                                         'cmp', pg_temp._numero(p_id)) || p)
$$;

-- CMP já lido e na fila, com as respostas dadas (como em comprovantes_gravacao.sql)
create function pg_temp._preparar(p jsonb) returns uuid language plpgsql as $$
declare
  v uuid;
begin
  insert into public.comprovantes (numero, situacao, modo, rota, origem, dono_id, wa_message_id, phone_normalized,
                                   tipo_whatsapp, recebido_em, arquivo_sha256, tipo, confianca, valor, valor_confianca,
                                   data_compra, data_confianca, forma_pagamento, lido_em)
  values (public._comprovante_proximo_numero(), 'lido', 'dono', 'comprovante', 'webhook', pg_temp._dono(),
          'TESTE-OBS-' || gen_random_uuid(), pg_temp._phone(), 'image', now(),
          md5(random()::text || clock_timestamp()::text) || md5(clock_timestamp()::text || random()::text),
          coalesce(p->>'tipo', 'nfce'), 'alta', (p->>'valor')::numeric, 'alta', pg_temp._hoje(), 'alta', p->>'forma', now())
  returning id into v;
  perform public.comprovante_conversa_entrar(array[v]);
  update public.comprovantes
     set destino = p->>'destino', quem_pagou = p->>'quem', categoria = p->>'categoria', observacao = p->>'observacao'
   where id = v;
  return v;
end $$;

-- o sim como o edge manda: a pergunta saiu (whatsapp-send confirmou) e a mensagem do dono é de DEPOIS
create function pg_temp._sim(p_pergunta jsonb) returns jsonb language plpgsql as $$
declare
  v_msg uuid;
begin
  perform public.pergunta_marcar_enviada((p_pergunta->>'pergunta_id')::uuid, 'WA-' || (p_pergunta->>'pergunta_id'));
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
  values ('inbound', pg_temp._phone(), 'text', 'sim', 'TESTE-OBS-' || gen_random_uuid(), now() + interval '10 seconds')
  returning id into v_msg;
  return public.comprovante_responder(jsonb_build_object(
    'pergunta_id', p_pergunta->>'pergunta_id', 'message_id', v_msg, 'interpretacao', jsonb_build_object('tipo', 'sim')));
end $$;

-- abre o resumo (RPC 7) e responde sim (RPC 9)
create function pg_temp._gravar(p_cmp uuid) returns jsonb language plpgsql as $$
declare
  v_p jsonb;
begin
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste'
   where phone_normalized = pg_temp._phone() and status = 'aberta';
  update public.comprovantes set situacao = 'aguardando_vez'
   where phone_normalized = pg_temp._phone() and situacao in ('perguntando', 'aguardando_sim');
  update public.comprovantes set fila_ordem = now() + interval '1 day'
   where phone_normalized = pg_temp._phone() and situacao = 'aguardando_vez' and id <> p_cmp;
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', p_cmp);
  if not coalesce((v_p->>'perguntou')::boolean, false) or v_p->>'passo' is distinct from 'confirmar' then
    return jsonb_build_object('resultado', 'nao_chegou_no_confirmar', 'passo', v_p->>'passo', 'motivo', v_p->>'motivo');
  end if;
  return pg_temp._sim(v_p);
end $$;

-- o CMP GRAVADO do teste, com a observação (com CPF): dinheiro da empresa, insumo → saída do Caixa (o caso D
-- de comprovantes_gravacao.sql). Criado uma vez; os testes que precisam de um gravado reusam.
create function pg_temp._gravado() returns uuid language plpgsql as $$
declare
  v uuid;
  r jsonb;
begin
  select id into v from _cmps where nome = 'gravado';
  if v is not null then
    return v;
  end if;
  v := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'forma', 'dinheiro', 'destino', 'insumo',
                                            'quem', 'empresa', 'observacao', pg_temp._obs_cpf()));
  r := pg_temp._gravar(v);
  if r->>'resultado' is distinct from 'gravado' then
    raise exception 'o CMP do teste não gravou: % %', r->>'resultado', coalesce(r->>'motivo', r->>'passo', '');
  end if;
  insert into _cmps values ('gravado', v);
  perform pg_temp._livrar();
  return v;
end $$;

-- ═══ T1 a coluna ═════════════════════════════════════════════════════════════════════════════
do $$
declare
  v uuid := pg_temp._cmp();
  v_nasce text;
  v_longa text := 'nenhum';
  v_vazia text := 'nenhum';
  v_200 integer;
begin
  perform pg_temp._livrar();
  select observacao into v_nasce from public.comprovantes where id = v;
  begin
    update public.comprovantes set observacao = repeat('x', 201) where id = v;
  exception when others then
    v_longa := sqlstate;
  end;
  begin
    update public.comprovantes set observacao = '' where id = v;
  exception when others then
    v_vazia := sqlstate;
  end;
  update public.comprovantes set observacao = repeat('x', 200) where id = v;
  select char_length(observacao) into v_200 from public.comprovantes where id = v;
  insert into _resultado values ('T1 a coluna observacao nasce nula e aceita de 1 a 200 letras',
    v_nasce is null and v_longa = '23514' and v_vazia = '23514' and v_200 = 200,
    'nasce=' || coalesce(v_nasce, 'null') || ' 201=' || v_longa || ' vazia=' || v_vazia || ' 200=' || coalesce(v_200::text, '-'));
  update public.comprovantes set observacao = null where id = v;
exception when others then
  insert into _resultado values ('T1 a coluna observacao nasce nula e aceita de 1 a 200 letras', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T2 "corrigir cmp N obs …" ══════════════════════════════════════════════════════════════
do $$
declare
  v uuid := pg_temp._cmp();
  v_p0 jsonb;
  v_r jsonb;
  v_apaga jsonb;
  v_longa jsonb;
  v_grav jsonb;
  v_versao0 integer;
  v_depois record;
  v_p0_depois record;
  v_resumo jsonb;
  v_apagada record;
  v_depois_longa record;
begin
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[v]);
  -- o "para quê" aberto (valor de selo alta já confirmado)
  v_p0 := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v);
  select resumo_versao into v_versao0 from public.comprovantes where id = v;
  v_r := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'message_id', null, 'comando', 'corrigir',
           'cmp', pg_temp._numero(v), 'campo', 'obs', 'observacao', '  ' || replace(pg_temp._obs_cpf(), ' de ', '   de ') || '  '));
  select observacao, resumo_versao, passo into v_depois from public.comprovantes where id = v;
  select status, motivo into v_p0_depois from public.whatsapp_perguntas where id = (v_p0->>'pergunta_id')::uuid;
  select public._comprovante_resumo(x) into v_resumo from public.comprovantes x where x.id = v;
  -- nula apaga (e sobe a versão de novo)
  v_apaga := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'message_id', null, 'comando', 'corrigir',
               'cmp', pg_temp._numero(v), 'campo', 'obs', 'observacao', null));
  select observacao, resumo_versao into v_apagada from public.comprovantes where id = v;
  -- 201 letras: recusa, nada muda
  v_longa := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'message_id', null, 'comando', 'corrigir',
               'cmp', pg_temp._numero(v), 'campo', 'obs', 'observacao', repeat('y', 201)));
  select observacao, resumo_versao into v_depois_longa from public.comprovantes where id = v;
  -- CMP gravado: só cancelar e mandar de novo
  v_grav := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'message_id', null, 'comando', 'corrigir',
              'cmp', pg_temp._numero(pg_temp._gravado()), 'campo', 'obs', 'observacao', 'depois de gravar'));
  insert into _resultado values ('T2 corrigir obs: guarda como veio, sai sem CPF, sobe a versão, repete a pergunta; nula apaga; 201 recusa; gravado não',
    v_p0->>'passo' = 'para_que' and v_r->>'resultado' = 'pergunta'
    and v_depois.observacao = pg_temp._obs_cpf()
    and v_r->'corrigido'->>'campo' = 'obs' and v_r->'corrigido'->>'valor' = pg_temp._obs_limpa()
    and v_resumo->>'observacao' = pg_temp._obs_limpa() and v_r->'pergunta'->'cmp'->>'observacao' = pg_temp._obs_limpa()
    and position('123.456.789-09' in v_r::text) = 0
    and v_depois.resumo_versao = v_versao0 + 1
    and v_r->'pergunta'->>'passo' = 'para_que' and v_depois.passo = 'para_que'
    and v_p0_depois.status = 'substituida'
    and v_apaga->>'resultado' = 'pergunta' and v_apagada.observacao is null and v_apagada.resumo_versao = v_versao0 + 2
    and v_apaga->'corrigido'->>'valor' is null
    and v_longa->>'resultado' = 'invalida' and v_longa->>'motivo' = 'obs_longa'
    and v_depois_longa.observacao is null and v_depois_longa.resumo_versao = v_versao0 + 2
    and v_grav->>'resultado' = 'ja_gravado',
    'r=' || coalesce(v_r->>'resultado', '-') || ' passo=' || coalesce(v_r->'pergunta'->>'passo', '-')
    || ' guardada=' || coalesce((v_depois.observacao = pg_temp._obs_cpf())::text, 'null')
    || ' saida=' || coalesce(v_r->'corrigido'->>'valor', 'null') || ' resumo=' || coalesce(v_resumo->>'observacao', 'null')
    || ' versao=' || v_versao0 || '→' || coalesce(v_depois.resumo_versao::text, '-') || '→' || coalesce(v_apagada.resumo_versao::text, '-')
    || ' p0=' || coalesce(v_p0_depois.status, '-') || ' apaga=' || coalesce(v_apaga->>'resultado', '-')
    || ' longa=' || coalesce(v_longa->>'motivo', v_longa->>'resultado', '-') || ' gravado=' || coalesce(v_grav->>'resultado', '-'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T2 corrigir obs: guarda como veio, sai sem CPF, sobe a versão, repete a pergunta; nula apaga; 201 recusa; gravado não',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T3 tudo ou nada: a recusa do comando desfaz o que veio antes ══════════════════════════════
do $$
declare
  v uuid := pg_temp._cmp();
  v_val numeric;
  v_p0 jsonb;
  v_antes jsonb;
  v_n0 integer;
  v_os integer := 999999;
  v_r jsonb;
  v_p0_status text;
begin
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[v]);
  v_p0 := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v);
  select valor into v_val from public.comprovantes where id = v;
  -- uma OS que não existe
  while exists (select 1 from public.service_orders where substring(service_order_number from '([0-9]+)$')::integer = v_os) loop
    v_os := v_os - 1;
  end loop;
  v_antes := pg_temp._estado(v);
  v_n0 := pg_temp._perguntas();
  v_r := pg_temp._completar(v, jsonb_build_object('categoria', pg_temp._cat(), 'os', v_os, 'valor', pg_temp._txt(v_val + 10),
                                                  'observacao', 'a nota veio sem o frete'));
  select status into v_p0_status from public.whatsapp_perguntas where id = (v_p0->>'pergunta_id')::uuid;
  insert into _resultado values ('T3 tudo ou nada (comando): a categoria aplicada antes da OS recusada não fica, nem a pergunta',
    v_p0->>'passo' = 'para_que' and v_r->>'resultado' = 'recusado'
    and v_r->'recusado'->>'campo' = 'os' and v_r->'recusado'->>'motivo' = 'os_nao_existe'
    and jsonb_typeof(v_r->'recusado'->'passo') = 'null'
    and v_r->'aplicados' = '[]'::jsonb and v_r->'itens' = '[]'::jsonb and jsonb_typeof(v_r->'pergunta') = 'null'
    and v_r->'ignorados' = '["categoria", "valor", "obs"]'::jsonb and v_r->>'codigo' is not null
    and pg_temp._estado(v) = v_antes and pg_temp._perguntas() = v_n0 and v_p0_status = 'aberta',
    'r=' || coalesce(v_r->>'resultado', '-') || ' recusado=' || coalesce(v_r->>'recusado', 'null')
    || ' ignorados=' || coalesce(v_r->>'ignorados', '-') || ' igual=' || (pg_temp._estado(v) = v_antes)::text
    || ' perguntas=' || v_n0 || '→' || pg_temp._perguntas() || ' p0=' || coalesce(v_p0_status, '-'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T3 tudo ou nada (comando): a categoria aplicada antes da OS recusada não fica, nem a pergunta',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T4 tudo ou nada: a recusa da resposta desfaz as correções ════════════════════════════════
do $$
declare
  v uuid := pg_temp._cmp();
  v_val numeric;
  v_p0 jsonb;
  v_antes jsonb;
  v_n0 integer;
  v_r jsonb;
  v_p0_status text;
begin
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[v]);
  update public.comprovantes set destino = 'empresa', categoria = pg_temp._cat() where id = v;
  v_p0 := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v);
  select valor into v_val from public.comprovantes where id = v;
  v_antes := pg_temp._estado(v);
  v_n0 := pg_temp._perguntas();
  -- dinheiro → "quem pagou?"; "o cliente" só vale numa OS
  v_r := pg_temp._completar(v, jsonb_build_object('valor', pg_temp._txt(v_val + 5), 'observacao', 'paguei a mais no balcão',
                                                  'forma', 'dinheiro', 'quem_pagou', 'cliente'));
  select status into v_p0_status from public.whatsapp_perguntas where id = (v_p0->>'pergunta_id')::uuid;
  insert into _resultado values ('T4 tudo ou nada (resposta): "quem pagou: cliente" fora da OS desfaz o valor, a forma e a obs',
    v_p0->>'passo' = 'como_pagou' and v_r->>'resultado' = 'recusado'
    and v_r->'recusado'->>'campo' = 'quem_pagou' and v_r->'recusado'->>'passo' = 'quem_pagou'
    and v_r->'recusado'->>'motivo' is not null
    and v_r->'aplicados' = '[]'::jsonb and v_r->'ignorados' = '["valor", "forma", "obs"]'::jsonb
    and pg_temp._estado(v) = v_antes and pg_temp._perguntas() = v_n0 and v_p0_status = 'aberta',
    'p0=' || coalesce(v_p0->>'passo', '-') || ' r=' || coalesce(v_r->>'resultado', '-') || ' recusado=' || coalesce(v_r->>'recusado', 'null')
    || ' ignorados=' || coalesce(v_r->>'ignorados', '-') || ' igual=' || (pg_temp._estado(v) = v_antes)::text
    || ' perguntas=' || v_n0 || '→' || pg_temp._perguntas());
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T4 tudo ou nada (resposta): "quem pagou: cliente" fora da OS desfaz o valor, a forma e a obs',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T5 o caso real do CMP-00001 ════════════════════════════════════════════════════════════
do $$
declare
  v uuid := pg_temp._cmp(jsonb_build_object('valor', 204.87));
  v_p0 jsonb;
  v_partida record;
  v_pay integer;
  v_anot integer;
  v_desp integer;
  v_r jsonb;
  v_depois record;
  v_item_valor jsonb;
  v_item_obs jsonb;
begin
  perform pg_temp._livrar();
  -- o estado de produção: na fila, passo "para quê", a pergunta expirou sem resposta
  perform public.comprovante_conversa_entrar(array[v]);
  v_p0 := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v);
  perform public.pergunta_marcar_enviada((v_p0->>'pergunta_id')::uuid, 'WA-' || (v_p0->>'pergunta_id'));
  update public.whatsapp_perguntas set expira_em = now() - interval '1 minute' where id = (v_p0->>'pergunta_id')::uuid;
  perform public._pergunta_limpar(pg_temp._phone());
  select situacao, passo, valor_confirmado into v_partida from public.comprovantes where id = v;
  select count(*) into v_pay from public.payables;
  select count(*) into v_anot from public.anotacoes_do_extrato;
  select count(*) into v_desp from public.service_order_expenses;
  v_r := pg_temp._completar(v, jsonb_build_object('categoria', pg_temp._cat(), 'valor', '235.97', 'observacao', pg_temp._obs_cpf()));
  select situacao, passo, valor_confirmado, categoria, observacao, gravado_em into v_depois from public.comprovantes where id = v;
  select i into v_item_valor from jsonb_array_elements(v_r->'itens') i where i->>'campo' = 'valor';
  select i into v_item_obs from jsonb_array_elements(v_r->'itens') i where i->>'campo' = 'obs';
  insert into _resultado values ('T5 o caso real: categoria, 235,97 e a observação numa chamada; o "para quê" de novo; nada no financeiro',
    v_partida.situacao = 'aguardando_vez' and v_partida.passo = 'para_que' and v_partida.valor_confirmado = 204.87
    and v_r->>'resultado' = 'ok' and v_r->'aplicados' = '["categoria", "valor", "obs"]'::jsonb
    and v_r->'ignorados' = '[]'::jsonb and v_r->'ja_estava' = '[]'::jsonb and v_r->>'valor_lido' = '204.87'
    and v_item_valor->>'valor' = '235.97' and v_item_valor->>'lido' = '204.87'
    and v_item_obs->>'valor' = pg_temp._obs_limpa() and not v_item_obs ? 'lido'
    and (select i->>'valor' from jsonb_array_elements(v_r->'itens') i where i->>'campo' = 'categoria') = pg_temp._cat()
    and v_r->'pergunta'->>'passo' = 'para_que' and v_r->'pergunta'->'cmp'->>'observacao' = pg_temp._obs_limpa()
    and v_r->'pergunta'->'cmp'->>'valor' = '235.97' and v_r->>'ocupado' = 'false'
    and v_depois.observacao = pg_temp._obs_cpf() and v_depois.valor_confirmado = 235.97 and v_depois.categoria = pg_temp._cat()
    and v_depois.gravado_em is null and v_depois.situacao = 'perguntando'
    and pg_temp._abertas() = 1
    and (select count(*) from public.payables) = v_pay and (select count(*) from public.anotacoes_do_extrato) = v_anot
    and (select count(*) from public.service_order_expenses) = v_desp
    and position('123.456.789-09' in v_r::text) = 0,
    'partida=' || coalesce(v_partida.situacao, '-') || '/' || coalesce(v_partida.passo, '-')
    || ' r=' || coalesce(v_r->>'resultado', '-') || ' aplicados=' || coalesce(v_r->>'aplicados', '-')
    || ' lido=' || coalesce(v_item_valor->>'lido', '-') || ' passo=' || coalesce(v_r->'pergunta'->>'passo', '-')
    || ' abertas=' || pg_temp._abertas() || ' situacao=' || coalesce(v_depois.situacao, '-'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T5 o caso real: categoria, 235,97 e a observação numa chamada; o "para quê" de novo; nada no financeiro',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T6 a observação obrigatória ════════════════════════════════════════════════════════════
do $$
declare
  v uuid := pg_temp._cmp();
  v_val numeric;
  v_antes jsonb;
  v_sem jsonb;
  v_igual boolean;
  v_com jsonb;
  v_confirmado numeric;
begin
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[v]);
  select valor into v_val from public.comprovantes where id = v;
  v_antes := pg_temp._estado(v);
  v_sem := pg_temp._completar(v, jsonb_build_object('valor', pg_temp._txt(v_val + 7)));
  v_igual := pg_temp._estado(v) = v_antes;
  -- o porquê que o dono já deu (guardado no CMP) vale
  update public.comprovantes set observacao = 'o cupom não traz a taxa' where id = v;
  v_com := pg_temp._completar(v, jsonb_build_object('valor', pg_temp._txt(v_val + 7)));
  select valor_confirmado into v_confirmado from public.comprovantes where id = v;
  insert into _resultado values ('T6 valor diferente do lido sem o porquê é recusado (nada muda); o porquê já guardado vale',
    v_sem->>'resultado' = 'observacao_obrigatoria' and v_sem->>'valor_lido' = pg_temp._txt(v_val) and v_sem->>'codigo' is not null
    and v_igual and v_com->>'resultado' = 'ok' and v_com->'aplicados' = '["valor"]'::jsonb and v_confirmado = v_val + 7,
    'sem=' || coalesce(v_sem->>'resultado', '-') || '/' || coalesce(v_sem->>'valor_lido', '-') || ' igual=' || v_igual::text
    || ' com=' || coalesce(v_com->>'resultado', '-') || ' confirmado=' || coalesce(v_confirmado::text, '-'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T6 valor diferente do lido sem o porquê é recusado (nada muda); o porquê já guardado vale',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T7 as recusas antes de escrever ════════════════════════════════════════════════════════
do $$
declare
  v uuid := pg_temp._cmp();
  v_fila uuid := pg_temp._cmp();
  v_canc uuid := pg_temp._cmp();
  v_grav uuid := pg_temp._gravado();
  v_antes jsonb;
  v_antes_fila jsonb;
  v_antes_grav jsonb;
  v_n0 integer;
  r_dono jsonb;
  r_nao jsonb;
  r_fila jsonb;
  r_canc jsonb;
  r_grav jsonb;
  r_data jsonb;
  v_maior integer;
begin
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[v]);
  -- ainda sendo lido (com legenda-chave o número nasce em 'na_fila')
  update public.comprovantes set situacao = 'na_fila' where id = v_fila;
  update public.comprovantes set situacao = 'cancelado', motivo_cancelamento = 'dono_cancelou', cancelado_em = now() where id = v_canc;
  v_antes := pg_temp._estado(v);
  v_antes_fila := pg_temp._estado(v_fila);
  v_antes_grav := pg_temp._estado(v_grav);
  v_n0 := pg_temp._perguntas();
  select coalesce(max(numero), 0) + 1000 into v_maior from public.comprovantes;
  r_dono := public.comprovante_completar(jsonb_build_object('phone', pg_temp._phone(), 'autor', gen_random_uuid(),
              'cmp', pg_temp._numero(v), 'forma', 'pix'));
  r_nao := public.comprovante_completar(jsonb_build_object('phone', pg_temp._phone(), 'autor', pg_temp._dono(),
             'cmp', v_maior, 'forma', 'pix'));
  r_fila := pg_temp._completar(v_fila, jsonb_build_object('forma', 'pix'));
  r_canc := pg_temp._completar(v_canc, jsonb_build_object('forma', 'pix'));
  r_grav := pg_temp._completar(v_grav, jsonb_build_object('forma', 'pix'));
  r_data := pg_temp._completar(v, jsonb_build_object('data', to_char(pg_temp._hoje() + 1, 'YYYY-MM-DD'), 'forma', 'pix'));
  insert into _resultado values ('T7 recusas antes de escrever: não é o dono, não existe, na fila, cancelado, gravado, data futura',
    r_dono->>'resultado' = 'nao_e_o_dono' and r_nao->>'resultado' = 'nao_existe'
    and r_fila->>'resultado' = 'fora_da_conversa' and r_canc->>'resultado' = 'ja_cancelado'
    and r_grav->>'resultado' = 'ja_gravado' and r_data->>'resultado' = 'data_futura'
    and pg_temp._estado(v) = v_antes and pg_temp._estado(v_fila) = v_antes_fila and pg_temp._estado(v_grav) = v_antes_grav
    and pg_temp._perguntas() = v_n0,
    'dono=' || coalesce(r_dono->>'resultado', '-') || ' nao=' || coalesce(r_nao->>'resultado', '-')
    || ' fila=' || coalesce(r_fila->>'resultado', '-') || ' canc=' || coalesce(r_canc->>'resultado', '-')
    || ' grav=' || coalesce(r_grav->>'resultado', '-') || ' data=' || coalesce(r_data->>'resultado', '-')
    || ' perguntas=' || v_n0 || '→' || pg_temp._perguntas());
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T7 recusas antes de escrever: não é o dono, não existe, na fila, cancelado, gravado, data futura',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T8 a descrição do lançamento ═══════════════════════════════════════════════════════════
do $$
declare
  v uuid := pg_temp._cmp();
  v_forn text := 'POSTO TESTE ' || upper(pg_temp._letras(6));
  v_antiga text;
  v_sem text;
  v_com text;
  v_longa text;
  v_grav uuid := pg_temp._gravado();
  v_desc text;
  v_esperada text;
begin
  update public.comprovantes set fornecedor_receita = v_forn where id = v;
  -- (a) sem observação: a expressão de antes, byte a byte
  select left(x.codigo || ' · ' || public._comprovante_tipo_no_texto(x.tipo)
              || coalesce(' · ' || (public._comprovante_fornecedor(x)->>'nome'), ''), 200),
         public._comprovante_descricao(x)
    into v_antiga, v_sem
    from public.comprovantes x where x.id = v;
  -- (b) com a observação (com CPF): termina em " · Obs: <sem CPF>"
  update public.comprovantes set observacao = pg_temp._obs_cpf() where id = v;
  select public._comprovante_descricao(x) into v_com from public.comprovantes x where x.id = v;
  update public.comprovantes set observacao = repeat('z', 200) where id = v;
  select public._comprovante_descricao(x) into v_longa from public.comprovantes x where x.id = v;
  -- (c) pela rota real: a descrição do lançamento do Caixa
  select p.description, public._comprovante_descricao(x) into v_desc, v_esperada
    from public.comprovantes x join public.payables p on p.id = x.payable_id where x.id = v_grav;
  insert into _resultado values ('T8 a descrição: igual à de antes sem observação; " · Obs: …" sem CPF no fim; o lançamento real a leva',
    v_sem = v_antiga and v_sem like '% · ' || v_forn
    and v_com = v_antiga || ' · Obs: ' || pg_temp._obs_limpa() and position('123.456.789-09' in v_com) = 0
    and char_length(v_longa) = 200 and v_longa like v_antiga || ' · Obs: zzz%'
    and position(v_esperada in v_desc) > 0 and position(' · Obs: ' || pg_temp._obs_limpa() in v_desc) > 0
    and position('123.456.789-09' in v_desc) = 0
    -- (d) a descrição nasce num lugar só
    and position('_comprovante_descricao' in pg_get_functiondef('public._comprovante_gravar(uuid, uuid, text)'::regprocedure)) > 0
    and position('_comprovante_descricao' in pg_get_functiondef(
          'public._comprovante_linha_explicar(public.comprovantes, uuid, uuid, boolean)'::regprocedure)) > 0,
    'igual=' || coalesce((v_sem = v_antiga)::text, 'null') || ' com=' || coalesce(v_com, 'null')
    || ' longa=' || coalesce(char_length(v_longa)::text, '-') || ' lancamento=' || coalesce(v_desc, 'null'));
exception when others then
  insert into _resultado values ('T8 a descrição: igual à de antes sem observação; " · Obs: …" sem CPF no fim; o lançamento real a leva',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T9 os dois _INDICE do mês ══════════════════════════════════════════════════════════════
do $$
declare
  v uuid := pg_temp._cmp();
  v_pes uuid := pg_temp._cmp();
  v_mes date := date_trunc('month', pg_temp._hoje())::date;
  v_linha jsonb;
  v_linha_pes jsonb;
  v_sem_obs jsonb;
begin
  update public.comprovantes set observacao = pg_temp._obs_cpf() where id = v;
  update public.comprovantes set destino = 'pessoal', observacao = pg_temp._obs_cpf() where id = v_pes;
  select l into v_linha from jsonb_array_elements(public.comprovantes_indice_do_mes(v_mes)->'linhas') l
   where l->>'codigo' = (select codigo from public.comprovantes where id = v);
  select l into v_linha_pes from jsonb_array_elements(public.comprovantes_indice_pessoal_do_mes(v_mes)->'linhas') l
   where l->>'codigo' = (select codigo from public.comprovantes where id = v_pes);
  update public.comprovantes set observacao = null where id = v;
  select l into v_sem_obs from jsonb_array_elements(public.comprovantes_indice_do_mes(v_mes)->'linhas') l
   where l->>'codigo' = (select codigo from public.comprovantes where id = v);
  insert into _resultado values ('T9 os dois _INDICE do mês trazem a observação sem CPF (nula quando não há)',
    v_linha->>'observacao' = pg_temp._obs_limpa() and v_linha_pes->>'observacao' = pg_temp._obs_limpa()
    and v_sem_obs ? 'observacao' and jsonb_typeof(v_sem_obs->'observacao') = 'null'
    and position('123.456.789-09' in coalesce(v_linha::text, '') || coalesce(v_linha_pes::text, '')) = 0,
    'mes=' || coalesce(v_linha->>'observacao', 'null') || ' pessoal=' || coalesce(v_linha_pes->>'observacao', 'null')
    || ' sem=' || coalesce(v_sem_obs->>'observacao', 'null'));
exception when others then
  insert into _resultado values ('T9 os dois _INDICE do mês trazem a observação sem CPF (nula quando não há)',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T10 a consulta do assistente ═══════════════════════════════════════════════════════════
do $$
declare
  v uuid := pg_temp._cmp();
  r jsonb;
begin
  update public.comprovantes set observacao = pg_temp._obs_cpf() where id = v;
  r := public.comprovantes_consultar(jsonb_build_object('numero', pg_temp._numero(v), 'autor', pg_temp._dono()));
  insert into _resultado values ('T10 comprovantes_consultar (admin) traz a observação sem CPF',
    (r->>'total')::integer = 1 and r->'itens'->0->>'observacao' = pg_temp._obs_limpa()
    and position('123.456.789-09' in r::text) = 0,
    'total=' || coalesce(r->>'total', '-') || ' obs=' || coalesce(r->'itens'->0->>'observacao', 'null'));
exception when others then
  insert into _resultado values ('T10 comprovantes_consultar (admin) traz a observação sem CPF', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T11 privilégios ════════════════════════════════════════════════════════════════════════
do $$
declare
  v_rpc text := 'public.comprovante_completar(jsonb)';
  v_helper text := 'public._comprovante_descricao(public.comprovantes)';
begin
  insert into _resultado values ('T11 comprovante_completar só service_role; _comprovante_descricao sem grant para ninguém',
    not has_function_privilege('anon', v_rpc, 'execute') and not has_function_privilege('authenticated', v_rpc, 'execute')
    and has_function_privilege('service_role', v_rpc, 'execute')
    and not has_function_privilege('anon', v_helper, 'execute') and not has_function_privilege('authenticated', v_helper, 'execute')
    and not has_function_privilege('service_role', v_helper, 'execute')
    and not has_function_privilege('anon', 'public.comprovante_comando(jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'public.comprovante_comando(jsonb)', 'execute'),
    'completar anon=' || has_function_privilege('anon', v_rpc, 'execute') || ' auth=' || has_function_privilege('authenticated', v_rpc, 'execute')
    || ' service=' || has_function_privilege('service_role', v_rpc, 'execute')
    || ' descricao service=' || has_function_privilege('service_role', v_helper, 'execute'));
exception when others then
  insert into _resultado values ('T11 comprovante_completar só service_role; _comprovante_descricao sem grant para ninguém',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T12 os passos sem comando pelo completar ═══════════════════════════════════════════════
do $$
declare
  v uuid := pg_temp._cmp();
  v_r jsonb;
  v_depois record;
  v_pay integer;
begin
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[v]);
  update public.comprovantes set destino = 'empresa', categoria = pg_temp._cat() where id = v;
  select count(*) into v_pay from public.payables;
  -- a categoria igual vai para "já estava"; dinheiro pelo comando; "a empresa" responde o "quem pagou?"
  v_r := pg_temp._completar(v, jsonb_build_object('categoria', upper(pg_temp._cat()), 'forma', 'dinheiro', 'quem_pagou', 'empresa'));
  select situacao, forma_confirmada, quem_pagou, gravado_em into v_depois from public.comprovantes where id = v;
  insert into _resultado values ('T12 passos sem comando: a forma pelo comando, "quem pagou" respondido sem mensagem, o resumo sem gravar',
    v_r->>'resultado' = 'ok' and v_r->'aplicados' = '["forma", "quem_pagou"]'::jsonb and v_r->'ja_estava' = '["categoria"]'::jsonb
    and v_r->'itens' = '[{"campo": "forma", "valor": "dinheiro"}, {"campo": "quem_pagou", "valor": "empresa"}]'::jsonb
    and v_r->'ignorados' = '[]'::jsonb and v_r->'pergunta'->>'passo' = 'confirmar'
    and v_depois.situacao = 'aguardando_sim' and v_depois.forma_confirmada = 'dinheiro' and v_depois.quem_pagou = 'empresa'
    and v_depois.gravado_em is null and (select count(*) from public.payables) = v_pay and pg_temp._abertas() = 1,
    'r=' || coalesce(v_r->>'resultado', '-') || ' aplicados=' || coalesce(v_r->>'aplicados', '-')
    || ' ja=' || coalesce(v_r->>'ja_estava', '-') || ' passo=' || coalesce(v_r->'pergunta'->>'passo', '-')
    || ' situacao=' || coalesce(v_depois.situacao, '-'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T12 passos sem comando: a forma pelo comando, "quem pagou" respondido sem mensagem, o resumo sem gravar',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T13 o CPF colado em pontuação (revisão de 12/10/2026) ══════════════════════════════════
-- _comprovante_sem_cpf só tira o CPF cercado de espaços; na observação (texto livre) ele vem com ponto,
-- vírgula, dois-pontos ou parênteses — e tem de sair do mesmo jeito em todas as saídas.
do $$
declare
  v uuid := pg_temp._cmp();
  v_obs text := 'reembolso (CPF 123.456.789-09), pago pelo CPF:12345678909.';
  v_desc text;
  v_resumo jsonb;
  v_linha jsonb;
  r jsonb;
  v_cmd jsonb;
  v_formas boolean;
  v_saidas text;
begin
  -- o helper: o CPF sai de qualquer jeito; CNPJ, número maior e valor ficam; nulo é nulo
  v_formas := public._comprovante_obs_sem_cpf('pago no CPF 123.456.789-09.') = 'pago no CPF .'
    and public._comprovante_obs_sem_cpf('CPF:12345678909') = 'CPF:'
    and public._comprovante_obs_sem_cpf('(123.456.789-09) reembolso') = '( ) reembolso'
    and public._comprovante_obs_sem_cpf(pg_temp._obs_cpf()) = pg_temp._obs_limpa()
    and public._comprovante_obs_sem_cpf('CNPJ 12.345.678/0001-90 nota 123456789012345 R$ 31,10')
        = 'CNPJ 12.345.678/0001-90 nota 123456789012345 R$ 31,10'
    and public._comprovante_obs_sem_cpf(null) is null
    and public._comprovante_obs_sem_cpf('123.456.789-09.') = '.';
  update public.comprovantes set observacao = v_obs where id = v;
  select public._comprovante_descricao(x), public._comprovante_resumo(x) into v_desc, v_resumo
    from public.comprovantes x where x.id = v;
  select l into v_linha from jsonb_array_elements(public.comprovantes_indice_do_mes(date_trunc('month', pg_temp._hoje())::date)->'linhas') l
   where l->>'codigo' = (select codigo from public.comprovantes where id = v);
  r := public.comprovantes_consultar(jsonb_build_object('numero', pg_temp._numero(v), 'autor', pg_temp._dono()));
  -- o corrigido do *corrigir cmp N obs* (o que volta ao dono)
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[v]);
  v_cmd := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'message_id', null, 'comando', 'corrigir',
                                                         'cmp', pg_temp._numero(v), 'campo', 'obs', 'observacao', v_obs));
  perform pg_temp._livrar();
  v_saidas := coalesce(v_desc, '') || coalesce(v_resumo::text, '') || coalesce(v_linha::text, '') || coalesce(r::text, '')
              || coalesce((v_cmd->'corrigido')::text, '');
  insert into _resultado values ('T13 o CPF colado em pontuação também sai (descrição, resumo, índice, consulta, corrigir)',
    v_formas
    and v_desc like '% · Obs: reembolso (CPF ), pago pelo CPF: .' and v_resumo->>'observacao' = 'reembolso (CPF ), pago pelo CPF: .'
    and v_linha->>'observacao' = 'reembolso (CPF ), pago pelo CPF: .' and r->'itens'->0->>'observacao' = 'reembolso (CPF ), pago pelo CPF: .'
    and v_cmd->>'resultado' = 'pergunta' and v_cmd->'corrigido'->>'valor' = 'reembolso (CPF ), pago pelo CPF: .'
    and position('123.456.789-09' in v_saidas) = 0 and position('12345678909' in v_saidas) = 0
    and not has_function_privilege('anon', 'public._comprovante_obs_sem_cpf(text)', 'execute')
    and not has_function_privilege('authenticated', 'public._comprovante_obs_sem_cpf(text)', 'execute')
    and not has_function_privilege('service_role', 'public._comprovante_obs_sem_cpf(text)', 'execute'),
    'formas=' || coalesce(v_formas::text, 'null') || ' desc=' || coalesce(v_desc, 'null')
    || ' resumo=' || coalesce(v_resumo->>'observacao', 'null') || ' indice=' || coalesce(v_linha->>'observacao', 'null')
    || ' consulta=' || coalesce(r->'itens'->0->>'observacao', 'null') || ' cmd=' || coalesce(v_cmd->>'resultado', '-'));
exception when others then
  insert into _resultado values ('T13 o CPF colado em pontuação também sai (descrição, resumo, índice, consulta, corrigir)',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;

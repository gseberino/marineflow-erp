-- Retorno F1 (P3): os textos fixos (_retorno_texto, T01–T28 e a linha de risco L01), _retorno_oferece_urgente,
-- _retorno_nome, _retorno_do_bem e _retorno_cumprimento.
-- 1. cada T01–T28, com dados completos, é EXATAMENTE o texto da tabela da especificação (P3.1), comparado
--    letra por letra com o texto já preenchido;
-- 2. cada campo ausente, vazio ou fora da lista fechada → 22023 (um caso por campo, mais os da especificação:
--    nome com dígito, quando = 'semana que vem', hora = '14 horas', cumprimento = 'Olá', do_bem = 'do X1');
-- 3. risco = true acrescenta L01 só nos recibo_*; tipo ou variante desconhecidos → 22023;
-- 4. nenhum texto passa de 400 caracteres nem de 5 linhas com os maiores valores possíveis; nenhum tem emoji
--    nem {campo} sobrando;
-- 5. _retorno_nome: empresa sem display_name → nulo; "LENINE LORI BROCCA" → "Lenine"; display_name vence name;
-- 6. _retorno_do_bem: lancha, van, motorhome, carro, ducato (e toda palavra de bem do P2 passa no T16);
-- 7. _retorno_oferece_urgente é verdadeiro exatamente nos pares cujo texto tem "URGENTE": a varredura passa
--    pela tabela inteira, renderizada por _retorno_texto.
-- Run (só pela bancada, de madrugada): npx supabase@2.111.0 db query --linked -f supabase/tests/retorno_f1_texto.sql
-- Termina em ROLLBACK: nada fica gravado. Os cadastros do caso 5 são SINTÉTICOS (nenhum cadastro real é
-- alterado), sem telefone, e o arranjo é desfeito dentro do arquivo (sub-bloco que termina em 'desfaz').
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- Chama _retorno_texto e devolve 'ok' ou 'SQLSTATE: mensagem'.
create or replace function pg_temp.retorno_f1_texto_erro(p_tipo text, p_variante text, p_dados jsonb) returns text
language plpgsql as $f$
begin
  perform public._retorno_texto(p_tipo, p_variante, p_dados);
  return 'ok';
exception when others then
  return sqlstate || ': ' || sqlerrm;
end $f$;

do $texto$
declare
  -- Os dados completos com que a tabela abaixo foi preenchida.
  c_dados constant jsonb := jsonb_build_object(
    'nome', 'Lenine', 'quando', 'amanhã', 'hora', '10h', 'de_quando', 'de ontem à noite',
    'dia_msg', 'sábado (21/11)', 'hora_msg', '21:40', 'cumprimento', 'Boa tarde', 'do_bem', 'do motorhome',
    'quando_lista', 'segunda (23/11)');
  -- Os maiores valores que cada campo aceita.
  c_maximos constant jsonb := jsonb_build_object(
    'nome', repeat('A', 40), 'quando', 'segunda (23/11)', 'hora', '21:40', 'de_quando', 'de ontem à noite',
    'dia_msg', 'domingo (22/11)', 'hora_msg', '23:59', 'cumprimento', 'Boa tarde', 'do_bem', 'da ' || repeat('a', 20),
    'quando_lista', 'segunda (23/11)', 'risco', true);
  c_risco constant text := 'Se houver fogo, fumaça ou água entrando, ligue 193 (Bombeiros).';
  v_r record;
  v_t text;
  v_t2 text;
  v_e text;
  v_nome text;
  v_f record;
  v_n int := 0;
  v_n_urgente int := 0;
  v_n_erros int := 0;
  v_maior int := 0;
  v_c_empresa uuid; v_c_empresa_dn uuid; v_c_lenine uuid; v_c_dn uuid; v_c_dn_branco uuid; v_c_generico uuid;
  r_empresa text; r_empresa_dn text; r_lenine text; r_dn text; r_dn_branco text; r_generico text; r_inexistente text;
  v_chegou boolean := false;
begin
  -- ── 0. As funções: existem, só para quem é SECURITY DEFINER (nada a anon/authenticated) ─────────────────
  foreach v_nome in array array['public._retorno_texto(text, text, jsonb)', 'public._retorno_oferece_urgente(text, text)',
                                'public._retorno_nome(uuid)', 'public._retorno_do_bem(text)',
                                'public._retorno_cumprimento(timestamptz)']
  loop
    if to_regprocedure(v_nome) is null then
      raise exception '0: % não existe', v_nome;
    end if;
    if has_function_privilege('anon', v_nome, 'execute') or has_function_privilege('authenticated', v_nome, 'execute') then
      raise exception '0b: % aberta a anon/authenticated', v_nome;
    end if;
    select p.provolatile, p.prosecdef, coalesce(p.proconfig, '{}') as config into v_f
      from pg_proc p where p.oid = to_regprocedure(v_nome);
    if not ('search_path=public' = any (v_f.config)) then
      raise exception '0c: % sem search_path = public', v_nome;
    end if;
    if v_f.provolatile is distinct from (case when v_nome in ('public._retorno_texto(text, text, jsonb)', 'public._retorno_nome(uuid)')
                                              then 's' else 'i' end) then
      raise exception '0d: volatilidade de % fora da especificação (%)', v_nome, v_f.provolatile;
    end if;
  end loop;
  if not (select p.prosecdef from pg_proc p where p.oid = to_regprocedure('public._retorno_nome(uuid)')) then
    raise exception '0e: _retorno_nome lê clients e não é SECURITY DEFINER';
  end if;

  -- ── 1, 3, 4 e 7: a tabela inteira ──────────────────────────────────────────────────────────────────────
  for v_r in
    select * from (values
      ('T01', 'recibo_cliente', 'padrao',
       'Oi, Lenine (mensagem automática da HBR). Recebi e passei ao Gustavo; ele te responde amanhã até as 10h.'),
      ('T02', 'recibo_cliente', 'padrao_apresentacao',
       'Oi, Lenine! Aqui é o assistente da HBR (mensagem automática). Recebi e passei ao Gustavo; ele te responde amanhã até as 10h.'),
      ('T03', 'recibo_cliente', 'sem_nome',
       'Oi! Aqui é o assistente da HBR (mensagem automática). Recebi sua mensagem e passei ao Gustavo; ele te responde amanhã até as 10h.'),
      ('T04', 'recibo_cliente', 'outro_dia',
       'Recebi, Lenine (mensagem automática da HBR). O Gustavo te responde amanhã até as 10h. Se não puder esperar, escreva URGENTE que eu aviso o Gustavo.'),
      ('T05', 'recibo_cliente', 'outro_dia_apresentacao',
       'Oi, Lenine! Aqui é o assistente da HBR (mensagem automática). Recebi sua mensagem; o Gustavo te responde amanhã até as 10h. Se não puder esperar, escreva URGENTE que eu aviso o Gustavo.'),
      ('T06', 'recibo_cliente', 'outro_dia_sem_nome',
       'Oi! Aqui é o assistente da HBR (mensagem automática). Recebi sua mensagem; o Gustavo te responde amanhã até as 10h. Se não puder esperar, escreva URGENTE que eu aviso o Gustavo.'),
      ('T07', 'recibo_cliente', 'manha',
       'Bom dia, Lenine (mensagem automática da HBR). Recebi sua mensagem de ontem à noite. O Gustavo te responde até as 10h.'),
      ('T08', 'recibo_cliente', 'manha_outro_dia',
       'Bom dia, Lenine (mensagem automática da HBR). Recebi sua mensagem de ontem à noite. O Gustavo te responde amanhã até as 10h.'),
      ('T09', 'recibo_cliente', 'manha_sem_nome',
       'Bom dia! Aqui é o assistente da HBR (mensagem automática). Recebi sua mensagem de ontem à noite. O Gustavo te responde amanhã até as 10h.'),
      ('T10', 'recibo_cliente', 'fora_ate',
       'Recebi, Lenine (mensagem automática da HBR). O Gustavo está fora até amanhã; ele te responde amanhã até as 10h.'),
      ('T11', 'recibo_cliente', 'fora_ate_sem_nome',
       'Oi! Aqui é o assistente da HBR (mensagem automática). Recebi sua mensagem. O Gustavo está fora até amanhã; ele te responde amanhã até as 10h.'),
      ('T12', 'recibo_cliente', 'volta',
       'Oi, Lenine (mensagem automática da HBR). Sua mensagem de sábado (21/11) às 21:40 só chegou para nós agora. Desculpe a demora. O Gustavo te responde amanhã até as 10h.'),
      ('T13', 'recibo_cliente', 'volta_queda',
       'Oi, Lenine (mensagem automática da HBR). Nosso WhatsApp ficou fora do ar, e sua mensagem de sábado (21/11) às 21:40 só chegou agora. Desculpe a demora. O Gustavo te responde amanhã até as 10h.'),
      ('T14', 'recibo_ambiguo', 'padrao',
       'Oi! Aqui é o assistente da HBR (mensagem automática). Recebi sua mensagem e passei ao Gustavo; ele te responde amanhã até as 10h.'),
      ('T15', 'recibo_numero_novo', 'pergunta_necessidade',
       'Boa tarde! Aqui é o assistente da HBR (mensagem automática). Recebi seu pedido e já passei ao Gustavo, que faz os orçamentos; ele te responde amanhã até as 10h. Pra adiantar: me conta o que você precisa resolver ou instalar (pode ser por áudio).'),
      ('T16', 'recibo_numero_novo', 'pergunta_modelo',
       'Boa tarde! Aqui é o assistente da HBR (mensagem automática). Recebi seu pedido e já passei ao Gustavo, que faz os orçamentos; ele te responde amanhã até as 10h. Pra adiantar: qual o modelo e o ano do motorhome?'),
      ('T17', 'recibo_numero_novo', 'sem_pergunta',
       'Boa tarde! Aqui é o assistente da HBR (mensagem automática). Recebi seu pedido e já passei ao Gustavo, que faz os orçamentos; ele te responde amanhã até as 10h.'),
      ('T18', 'coleta_numero_novo', 'nome',
       'Obrigado! Já passei ao Gustavo. Como posso te chamar?'),
      ('T19', 'saudacao_numero_novo', 'padrao',
       'Boa tarde! Aqui é o assistente da HBR (mensagem automática). Em que posso te ajudar? Pode ser por áudio.'),
      ('T20', 'adiamento', 'com_nome',
       'Lenine, o Gustavo ainda não conseguiu te responder. Seu pedido está anotado, e a resposta sai até as 10h. Se não puder esperar, escreva URGENTE que eu aviso o Gustavo.'),
      ('T21', 'adiamento', 'sem_nome',
       'O Gustavo ainda não conseguiu te responder. Seu pedido está anotado, e a resposta sai até as 10h. Se não puder esperar, escreva URGENTE que eu aviso o Gustavo.'),
      ('T22', 'fim_do_dia', 'com_nome',
       'Lenine, o Gustavo não conseguiu te responder hoje, desculpe. Seu pedido abre a lista dele segunda (23/11) cedo.'),
      ('T23', 'fim_do_dia', 'sem_nome',
       'O Gustavo não conseguiu te responder hoje, desculpe. Seu pedido abre a lista dele segunda (23/11) cedo.'),
      ('T24', 'urgente', 'acorde',
       'Avisei o Gustavo agora, Lenine.'),
      ('T25', 'urgente', 'sem_acorde',
       'Anotado como urgente, Lenine. O Gustavo vê segunda (23/11) cedo, antes de tudo.'),
      ('T26', 'urgente', 'sem_acorde_sem_nome',
       'Anotado como urgente. O Gustavo vê segunda (23/11) cedo, antes de tudo.'),
      ('T27', 'parar', 'com_nome',
       'Combinado, Lenine: não te mando mais mensagens automáticas. Se precisar, é só escrever.'),
      ('T28', 'parar', 'sem_nome',
       'Combinado: não te mando mais mensagens automáticas. Se precisar, é só escrever.')
    ) as t(id, tipo, variante, esperado)
  loop
    v_n := v_n + 1;
    -- 1. Literal.
    v_t := public._retorno_texto(v_r.tipo, v_r.variante, c_dados);
    if v_t is distinct from v_r.esperado then
      raise exception '1 (%): texto diferente da tabela: "%"', v_r.id, v_t;
    end if;
    -- 3. Risco: L01 numa linha nova só nos recibo_*; risco falso (ou ausente) não muda nada.
    v_t2 := public._retorno_texto(v_r.tipo, v_r.variante, c_dados || '{"risco": true}');
    if v_t2 is distinct from (case when v_r.tipo in ('recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo')
                                   then v_r.esperado || E'\n' || c_risco else v_r.esperado end) then
      raise exception '3 (%): a linha de risco saiu errada: "%"', v_r.id, v_t2;
    end if;
    if public._retorno_texto(v_r.tipo, v_r.variante, c_dados || '{"risco": false}') is distinct from v_r.esperado then
      raise exception '3b (%): risco falso mudou o texto', v_r.id;
    end if;
    -- 4. Com os maiores valores (e o risco): até 400 caracteres e até 5 linhas; sem emoji e sem {campo} sobrando.
    v_t2 := public._retorno_texto(v_r.tipo, v_r.variante, c_maximos);
    if char_length(v_t2) > 400 or array_length(string_to_array(v_t2, E'\n'), 1) > 5 then
      raise exception '4 (%): passa de 400 caracteres ou de 5 linhas (% caracteres)', v_r.id, char_length(v_t2);
    end if;
    v_maior := greatest(v_maior, char_length(v_t2));
    if v_t ~ '[{}]' or v_t2 ~ '[{}]' then
      raise exception '4b (%): sobrou {campo} no texto', v_r.id;
    end if;
    if v_t ~ '[\U0001F000-\U0001FAFF\u2600-\u27BF\uFE0F\u200D]' then
      raise exception '4c (%): o texto tem emoji', v_r.id;
    end if;
    -- 7. URGENTE no texto ⇔ _retorno_oferece_urgente.
    if (position('URGENTE' in v_t) > 0) is distinct from public._retorno_oferece_urgente(v_r.tipo, v_r.variante) then
      raise exception '7 (%): _retorno_oferece_urgente(%, %) não bate com o texto', v_r.id, v_r.tipo, v_r.variante;
    end if;
    if position('URGENTE' in v_t) > 0 then
      v_n_urgente := v_n_urgente + 1;
    end if;
  end loop;
  if v_n <> 28 then
    raise exception '1: conferidos % modelos, esperados 28', v_n;
  end if;
  -- T04–T06, T20 e T21: exatamente 5 oferecem URGENTE.
  if v_n_urgente <> 5 then
    raise exception '7b: % modelos com URGENTE, esperados 5 (T04–T06, T20, T21)', v_n_urgente;
  end if;
  -- Fora da tabela, nunca verdadeiro.
  if public._retorno_oferece_urgente('recibo_cliente', 'padrao') or public._retorno_oferece_urgente('urgente', 'sem_acorde')
     or public._retorno_oferece_urgente('adiamento', 'outra') or public._retorno_oferece_urgente(null, null)
     or public._retorno_oferece_urgente('recibo_cliente', null) or public._retorno_oferece_urgente(null, 'com_nome')
     or public._retorno_oferece_urgente(null, null) is null then
    raise exception '7c: _retorno_oferece_urgente verdadeiro (ou nulo) fora da tabela';
  end if;

  -- ── 2. Cada campo: ausente, vazio, só espaço e fora da lista fechada → 22023 ────────────────────────────────
  for v_r in
    select * from (values
      ('nome', 'recibo_cliente', 'padrao', 'Ana 2'),                    -- nome com dígito
      ('nome', 'recibo_cliente', 'padrao', repeat('A', 41)),            -- mais de 40 caracteres
      ('nome', 'recibo_cliente', 'padrao', 'Ana {hora}'),               -- chave no nome
      ('nome', 'recibo_cliente', 'padrao', E'Ana\nSilva'),              -- quebra de linha no nome
      ('quando', 'recibo_cliente', 'padrao', 'semana que vem'),
      ('quando', 'recibo_cliente', 'padrao', 'segunda (9/11)'),
      ('quando', 'recibo_cliente', 'padrao', 'Amanhã'),
      ('hora', 'recibo_cliente', 'padrao', '14 horas'),
      ('hora', 'recibo_cliente', 'padrao', '14h30'),
      ('de_quando', 'recibo_cliente', 'manha', 'de manhã'),
      ('dia_msg', 'recibo_cliente', 'volta', 'ontem'),
      ('hora_msg', 'recibo_cliente', 'volta', '9:5'),
      ('cumprimento', 'saudacao_numero_novo', 'padrao', 'Olá'),
      ('cumprimento', 'recibo_numero_novo', 'sem_pergunta', 'bom dia'),
      ('do_bem', 'recibo_numero_novo', 'pergunta_modelo', 'do X1'),
      ('do_bem', 'recibo_numero_novo', 'pergunta_modelo', 'dos barcos'),
      ('quando_lista', 'fim_do_dia', 'com_nome', 'semana que vem'),
      ('quando_lista', 'urgente', 'sem_acorde_sem_nome', 'logo')
    ) as t(campo, tipo, variante, invalido)
  loop
    -- fora da lista
    v_e := pg_temp.retorno_f1_texto_erro(v_r.tipo, v_r.variante, jsonb_set(c_dados, array[v_r.campo], to_jsonb(v_r.invalido)));
    if v_e is distinct from '22023: retorno_texto: valor fora da lista em ' || v_r.campo then
      raise exception '2 (% = "%"): esperado 22023 de valor fora da lista, veio %', v_r.campo, v_r.invalido, v_e;
    end if;
    -- ausente, vazio e só espaço
    v_e := pg_temp.retorno_f1_texto_erro(v_r.tipo, v_r.variante, c_dados - v_r.campo);
    if v_e is distinct from '22023: retorno_texto: falta ' || v_r.campo then
      raise exception '2 (% ausente): esperado 22023 de falta, veio %', v_r.campo, v_e;
    end if;
    v_e := pg_temp.retorno_f1_texto_erro(v_r.tipo, v_r.variante, jsonb_set(c_dados, array[v_r.campo], '""'));
    if v_e is distinct from '22023: retorno_texto: falta ' || v_r.campo then
      raise exception '2 (% vazio): esperado 22023 de falta, veio %', v_r.campo, v_e;
    end if;
    v_e := pg_temp.retorno_f1_texto_erro(v_r.tipo, v_r.variante, jsonb_set(c_dados, array[v_r.campo], '"   "'));
    if v_e is distinct from '22023: retorno_texto: falta ' || v_r.campo then
      raise exception '2 (% só espaço): esperado 22023 de falta, veio %', v_r.campo, v_e;
    end if;
    -- json nulo também é falta
    v_e := pg_temp.retorno_f1_texto_erro(v_r.tipo, v_r.variante, jsonb_set(c_dados, array[v_r.campo], 'null'));
    if v_e is distinct from '22023: retorno_texto: falta ' || v_r.campo then
      raise exception '2 (% nulo): esperado 22023 de falta, veio %', v_r.campo, v_e;
    end if;
    v_n_erros := v_n_erros + 5;
  end loop;
  -- Os valores aceitos de cada lista fechada passam (inclusive os que o banco produz).
  if pg_temp.retorno_f1_texto_erro('recibo_cliente', 'manha', jsonb_set(c_dados, '{de_quando}', '"desta madrugada"')) <> 'ok'
     or pg_temp.retorno_f1_texto_erro('saudacao_numero_novo', 'padrao', jsonb_set(c_dados, '{cumprimento}', '"Bom dia"')) <> 'ok'
     or pg_temp.retorno_f1_texto_erro('saudacao_numero_novo', 'padrao', jsonb_set(c_dados, '{cumprimento}', '"Boa noite"')) <> 'ok'
     or pg_temp.retorno_f1_texto_erro('recibo_cliente', 'padrao', jsonb_set(c_dados, '{hora}', '"9h"')) <> 'ok'
     or pg_temp.retorno_f1_texto_erro('recibo_cliente', 'padrao', jsonb_set(c_dados, '{hora}', '"10:30"')) <> 'ok'
     or pg_temp.retorno_f1_texto_erro('recibo_cliente', 'padrao', jsonb_set(c_dados, '{quando}', '"hoje"')) <> 'ok'
     or pg_temp.retorno_f1_texto_erro('recibo_cliente', 'padrao', jsonb_set(c_dados, '{nome}', '"Zé"')) <> 'ok'
     or pg_temp.retorno_f1_texto_erro('recibo_cliente', 'padrao', jsonb_set(c_dados, '{nome}', to_jsonb(repeat('A', 40)))) <> 'ok' then
    raise exception '2b: um valor da lista fechada foi recusado';
  end if;
  -- Os dias que o banco escreve (_retorno_quando) passam todos, com acento: segunda a domingo.
  for v_t in select public._retorno_quando(d::date, '2026-11-01') from generate_series('2026-11-16'::date, '2026-11-22'::date, '1 day') d loop
    if pg_temp.retorno_f1_texto_erro('recibo_cliente', 'padrao', jsonb_set(c_dados, '{quando}', to_jsonb(v_t))) <> 'ok'
       or pg_temp.retorno_f1_texto_erro('fim_do_dia', 'sem_nome', jsonb_set(c_dados, '{quando_lista}', to_jsonb(v_t))) <> 'ok'
       or pg_temp.retorno_f1_texto_erro('recibo_cliente', 'volta', jsonb_set(c_dados, '{dia_msg}', to_jsonb(v_t))) <> 'ok' then
      raise exception '2c: o dia "%" de _retorno_quando foi recusado', v_t;
    end if;
  end loop;
  -- Modelo sem campo aceita dados nulos; modelo com campo, não.
  if public._retorno_texto('coleta_numero_novo', 'nome', null) is distinct from 'Obrigado! Já passei ao Gustavo. Como posso te chamar?'
     or pg_temp.retorno_f1_texto_erro('recibo_cliente', 'padrao', null) <> '22023: retorno_texto: falta nome' then
    raise exception '2d: dados nulos fora da regra';
  end if;

  -- ── 3. Tipo ou variante desconhecidos → 22023 ────────────────────────────────────────────────────────────
  foreach v_nome in array array['recibo_x/padrao', 'recibo_cliente/padrao_x', 'acorde/relogio', 'cadastro_provisorio/padrao',
                                'fila/padrao', 'recibo_cliente/', '/padrao']
  loop
    v_e := pg_temp.retorno_f1_texto_erro(nullif(split_part(v_nome, '/', 1), ''), nullif(split_part(v_nome, '/', 2), ''), c_dados);
    if v_e not like '22023: retorno_texto: modelo desconhecido%' then
      raise exception '3c (%): modelo desconhecido não deu 22023 (%)', v_nome, v_e;
    end if;
    v_n_erros := v_n_erros + 1;
  end loop;

  -- ── Cumprimento pela hora de Brasília ──────────────────────────────────────────────────────────────────────
  if public._retorno_cumprimento('2026-11-17 04:59-03') is distinct from 'Boa noite'
     or public._retorno_cumprimento('2026-11-17 05:00-03') is distinct from 'Bom dia'
     or public._retorno_cumprimento('2026-11-17 11:59-03') is distinct from 'Bom dia'
     or public._retorno_cumprimento('2026-11-17 12:00-03') is distinct from 'Boa tarde'
     or public._retorno_cumprimento('2026-11-17 17:59-03') is distinct from 'Boa tarde'
     or public._retorno_cumprimento('2026-11-17 18:00-03') is distinct from 'Boa noite'
     or public._retorno_cumprimento('2026-11-17 23:30-03') is distinct from 'Boa noite'
     or public._retorno_cumprimento('2026-11-17 14:00+00') is distinct from 'Bom dia'      -- 11:00 em Brasília
     or public._retorno_cumprimento(null) is not null then
    raise exception 'c: _retorno_cumprimento fora da especificação';
  end if;

  -- ── 6. _retorno_do_bem ────────────────────────────────────────────────────────────────────────────────
  if public._retorno_do_bem('lancha') is distinct from 'da lancha'
     or public._retorno_do_bem('van') is distinct from 'da van'
     or public._retorno_do_bem('motorhome') is distinct from 'do motorhome'
     or public._retorno_do_bem('carro') is distinct from 'do carro'
     or public._retorno_do_bem('ducato') is distinct from 'do veículo'
     or public._retorno_do_bem('Sprinter') is distinct from 'do veículo'
     or public._retorno_do_bem('motor home') is distinct from 'do motorhome'
     or public._retorno_do_bem('  Lancha ') is distinct from 'da lancha'
     or public._retorno_do_bem('embarcacao') is distinct from 'da embarcação'
     or public._retorno_do_bem('Embarcação') is distinct from 'da embarcação'
     or public._retorno_do_bem('moto aquatica') is distinct from 'da moto aquática'
     or public._retorno_do_bem('onibus') is distinct from 'do ônibus'
     or public._retorno_do_bem('trailer') is distinct from 'do trailer'
     or public._retorno_do_bem(null) is not null or public._retorno_do_bem('') is not null
     or public._retorno_do_bem('   ') is not null then
    raise exception '6: _retorno_do_bem fora da especificação';
  end if;
  -- Toda palavra de bem do sinal (P2, já sem acento) vira um {do_bem} que o T16 aceita.
  foreach v_nome in array array['barco', 'lancha', 'veleiro', 'catamara', 'embarcacao', 'jet ski', 'moto aquatica', 'escuna',
                                'traineira', 'bote', 'motorhome', 'trailer', 'camper', 'van', 'onibus', 'caminhao', 'picape',
                                'automovel', 'veiculo', 'carro', 'ducato', 'sprinter', 'iveco', 'daily', 'master', 'boxer']
  loop
    v_e := pg_temp.retorno_f1_texto_erro('recibo_numero_novo', 'pergunta_modelo',
                                         jsonb_set(c_dados, '{do_bem}', to_jsonb(public._retorno_do_bem(v_nome))));
    if v_e <> 'ok' then
      raise exception '6b: o bem "%" (%) não passa no T16: %', v_nome, public._retorno_do_bem(v_nome), v_e;
    end if;
  end loop;

  -- ── 5. _retorno_nome, com cadastros sintéticos ─────────────────────────────────────────────────────────
  begin
    insert into public.clients (type, name) values ('company', 'TESTE F1 TEXTO EMPRESA LTDA') returning id into v_c_empresa;
    insert into public.clients (type, name, display_name)
      values ('company', 'TESTE F1 TEXTO MARINA LTDA', 'Marina Bela') returning id into v_c_empresa_dn;
    insert into public.clients (type, name) values ('individual', 'LENINE LORI BROCCA') returning id into v_c_lenine;
    insert into public.clients (type, name, display_name)
      values ('individual', 'JOSÉ TESTE F1 TEXTO', 'Zé Teste') returning id into v_c_dn;
    insert into public.clients (type, name, display_name)
      values ('individual', 'MARIA TESTE F1 TEXTO', '   ') returning id into v_c_dn_branco;
    insert into public.clients (type, name, generico)
      values ('individual', 'Cliente Final Teste F1 texto', true) returning id into v_c_generico;
    r_empresa := public._retorno_nome(v_c_empresa);
    r_empresa_dn := public._retorno_nome(v_c_empresa_dn);
    r_lenine := public._retorno_nome(v_c_lenine);
    r_dn := public._retorno_nome(v_c_dn);
    r_dn_branco := public._retorno_nome(v_c_dn_branco);
    r_generico := public._retorno_nome(v_c_generico);
    r_inexistente := coalesce(public._retorno_nome(gen_random_uuid()), public._retorno_nome(null));
    v_chegou := true;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;
  if not v_chegou then
    raise exception '5: o arranjo dos cadastros não chegou ao fim';
  end if;
  if exists (select 1 from public.clients where id in (v_c_empresa, v_c_empresa_dn, v_c_lenine, v_c_dn, v_c_dn_branco, v_c_generico)) then
    raise exception '5: os cadastros sintéticos não foram desfeitos';
  end if;
  if r_empresa is not null then
    raise exception '5a: empresa sem display_name deu nome: %', r_empresa;
  end if;
  if r_lenine is distinct from 'Lenine' then
    raise exception '5b: "LENINE LORI BROCCA" deu %', r_lenine;
  end if;
  if r_dn is distinct from 'Zé' or r_empresa_dn is distinct from 'Marina' then
    raise exception '5c: display_name não venceu name: % %', r_dn, r_empresa_dn;
  end if;
  if r_dn_branco is distinct from 'Maria' then
    raise exception '5d: display_name em branco não caiu no name: %', r_dn_branco;
  end if;
  if r_generico is not null or r_inexistente is not null then
    raise exception '5e: "Cliente Final" ou cadastro inexistente deu nome: % %', r_generico, r_inexistente;
  end if;
  -- O nome que o banco produz passa no {nome}.
  if pg_temp.retorno_f1_texto_erro('recibo_cliente', 'padrao', jsonb_set(c_dados, '{nome}', to_jsonb(r_lenine))) <> 'ok'
     or pg_temp.retorno_f1_texto_erro('recibo_cliente', 'padrao', jsonb_set(c_dados, '{nome}', to_jsonb(r_dn))) <> 'ok' then
    raise exception '5f: o nome de _retorno_nome não passa no texto';
  end if;

  insert into _bancada (arquivo, ok, numeros)
  values ('retorno_f1_texto', true, jsonb_build_object('modelos', v_n, 'com_urgente', v_n_urgente, 'erros_22023', v_n_erros,
                                                       'maior_texto', v_maior));
end
$texto$;

select arquivo, ok, numeros from _bancada order by em;
rollback;

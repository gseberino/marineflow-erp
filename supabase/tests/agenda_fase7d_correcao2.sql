-- Prova da correção da 7d, Onda 2, da Agenda de Produção (o que o dono lê e responde na conversa; migration 20261107100850; decisoes-do-fio.md, seção Onda 2). Um bloco por item: cada um falha sem a
-- migration e passa com ela (o "antes" está nas notas). Tudo pelo caminho real: agenda_ver foco decisoes, agenda_rascunho_aplicar, agenda_rascunho_planejar, *grava*, *desfaz*.
-- bancada: depende de 20261107100850
--
--   T0   as portas das novas e as cópias: tirados os blocos, a origem; nenhuma estrutura; o que a sessão do retorno chama fica de fora
--   O8   *agenda pendências* mostra tudo: 1.800 letras só nesse foco; dados leva as abertas, mesmo as cortadas; o corte diz os focos por assunto; quem tem opções vem antes; o "1" só com os títulos
--   O9   a opção "Já terminou" com o freio aponta o *entreguei*; as outras seguem com a recusa de hoje
--   O16  a releitura de autorizados marca quem saiu da equipe, sem recusar
--   O17  em teste, a releitura de viagem, pátio e acesso diz que só anotou; a ação do *grava* e o *desfaz* dizem o fato
--
-- O R1 (a trava do "1"), o prompt e os papéis não têm banco: _shared/ai/whatsapp-channel_test.ts, ai-agent/index_test.ts, prompt-ferramentas_test.ts, os evals K109 a K118 e o teste do ligar.
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora dela sai PULADO (usa as fixtures da 7d). Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
-- O texto sem os blocos "-- FASE 7d: … -- FASE 7d: fim" e sem as marcas "-- (7d … -- (7d: fim)".
create function pg_temp.sem_7d(p text) returns text language plpgsql immutable as $f$
declare
  v_fora   text[] := '{}';
  v_dentro int := 0;
  l        text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if v_dentro = 0 and l ~ '^\s*-- FASE 7d:' and l !~ '^\s*-- FASE 7d: fim' then v_dentro := 1; continue; end if;
    if v_dentro = 1 and l ~ '^\s*-- FASE 7d: fim' then v_dentro := 0; continue; end if;
    if v_dentro = 0 and l ~ '^\s*-- \(7d ' then v_dentro := 2; continue; end if;
    if v_dentro = 2 and l ~ '^\s*-- \(7d: fim\)' then v_dentro := 0; continue; end if;
    if v_dentro = 0 then v_fora := v_fora || l; end if;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;
create function pg_temp.como(p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_papel)::text, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

-- ── As fixtures e os atalhos ──────────────────────────────────────────────────────────────
do $carga$
begin
  if coalesce(current_setting('agenda_teste.fase7d', true), '') = '' or coalesce(current_setting('agenda_teste.fase7c', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7b', true), '') = '' then
    return;
  end if;
  execute current_setting('agenda_teste.fase7d');
end
$carga$;
create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.service_orders so where so.service_order_number = 'OS-J1')
$f$;
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select id from public.payees where name = p_nome and active order by id limit 1
$f$;
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by id limit 1
$f$;
create function pg_temp.base(p_modo text) returns void language sql as $f$
  update public.agenda_config
     set modo_leitura = 'ligado', modo_proposta = 'ligado', modo_vigia = 'ligado', gestor_so_propor = false, gestor_so_propor_em = null,
         modo_local_calendario = p_modo, modo_local_autorizacao = p_modo, modo_bem = p_modo, modo_patio = p_modo, modo_viagem = p_modo, modo_mesmo_local = p_modo
   where id
$f$;
create function pg_temp.modo_de(p_coluna text, p_modo text) returns void language plpgsql as $f$
begin
  execute format('update public.agenda_config set %I = %L where id', p_coluna, p_modo);
end $f$;
create function pg_temp.limpa() returns void language sql as $f$
  update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where estado = 'aberta'
$f$;
create function pg_temp.perg(p_tipo text, p_chave text, p_texto text, p_opcoes jsonb, p_os uuid default null, p_perda date default null) returns uuid language sql as $f$
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, opcoes, perda_em, modo, criada_em)
  values (p_tipo, p_chave, p_os, case when p_os is null then '{}'::uuid[] else array[p_os] end, p_texto, p_opcoes, p_perda, 'ligado', timestamptz '2027-07-16 08:00-03')
  returning id
$f$;
create function pg_temp.ver(p_hoje date default date '2027-07-16') returns jsonb language sql stable as $f$
  select public._agenda_ver_decisoes(p_hoje, pg_temp.em(p_hoje, '17:40'))
$f$;
create function pg_temp.responde(p_decisao text, p_opcao text, p_trecho text, p_hoje date default date '2027-07-16') returns jsonb language sql as $f$
  select public.agenda_rascunho_aplicar(pg_temp.adm(), 'whatsapp', null, null, p_decisao, p_opcao, p_trecho, p_hoje, pg_temp.em(p_hoje, '17:41'))
$f$;
create function pg_temp.rascunhos() returns int language sql stable as $f$
  select count(*)::int from public.agenda_rascunho r where r.autor = pg_temp.adm() and r.estado = 'aberto'
$f$;
create function pg_temp.plan(p_os text, p_dados jsonb, p_trecho text, p_hoje date default date '2027-07-16') returns jsonb language sql as $f$
  select public.agenda_rascunho_planejar(pg_temp.adm(), 'whatsapp', pg_temp.os(p_os)::text, p_dados, p_trecho, p_hoje)
$f$;
create function pg_temp.grava(p_hoje date default date '2027-07-16', p_hora text default '17:00') returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.agora', pg_temp.em(p_hoje, p_hora)::text, true);
  perform set_config('agenda.hoje', p_hoje::text, true);
  return public.agenda_rascunho_gravar(pg_temp.adm(), p_hoje);
end $f$;
create function pg_temp.desfaz(p_os text, p_hoje date default date '2027-07-16', p_hora text default '18:00') returns jsonb language sql as $f$
  select public.agenda_rascunho_desfazer(pg_temp.adm(), 'whatsapp', pg_temp.os(p_os)::text, 'desfaz', p_hoje, pg_temp.em(p_hoje, p_hora))
$f$;
-- A linha do rascunho aberto de uma OS (o que fica guardado e vai ao *grava*)
create function pg_temp.rascunho(p_os text) returns jsonb language sql stable as $f$
  select r.dados from public.agenda_rascunho r
   where r.autor = pg_temp.adm() and r.chave = 'planejar:' || pg_temp.os(p_os)::text and r.estado = 'aberto'
$f$;
-- A pessoa sai da equipe como saiu em 30/10: a disponibilidade dela trocada, sem linha viva. A diária (work_profiles) é do pagamento, não da agenda: fica, e é por ela que o resolvedor ainda acha o nome.
create function pg_temp.saiu(p_nome text) returns void language sql as $f$
  update public.agenda_disponibilidade set substituida_em = timestamptz '2027-06-30 12:00-03' where payee_id = pg_temp.pessoa(p_nome) and substituida_em is null;
$f$;

-- ── T0. As portas e as cópias ─────────────────────────────────────────────────────────────
with f(sig, vol) as (values
  ('public._agenda_titulo_da_pergunta(text)', 'i'),
  ('public._agenda_saiu_da_equipe(uuid)', 's'))
insert into _resultado
select 'T0a as 2 novas: invoker, a volatilidade, search_path fixo, e ninguém de fora (nem o service_role): quem chama é definer',
       count(p.oid) = 2
       and bool_and(not p.prosecdef and p.provolatile = f.vol and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
                    and p.proacl is not null and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)
                    and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                    and not has_function_privilege('service_role', p.oid, 'execute')),
       string_agg(f.sig, '; ') filter (where p.oid is null)
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

insert into _resultado
select 'T0b rodando: o anon e o técnico não alcançam as novas (42501)',
       pg_temp.como('anon', $q$select public._agenda_titulo_da_pergunta('x')$q$) like 'erro 42501%'
       and pg_temp.como('authenticated', $q$select public._agenda_titulo_da_pergunta('x')$q$) like 'erro 42501%'
       and pg_temp.como('service_role', $q$select public._agenda_saiu_da_equipe(gen_random_uuid())::text$q$) like 'erro 42501%', null;

do $t0$
declare
  c      record;
  v_viva text;
  v_mig  text := coalesce(current_setting('agenda_teste.mig_correcao2_fase7d', true), '');
begin
  if v_mig = '' then
    insert into _resultado values ('T0d as cópias', true, 'PULADO: sem a migration como texto (rode pela bancada)');
    return;
  end if;
  -- As funções que vêm de antes da 7d: tirados os blocos, a origem (a definição mais nova).
  for c in select * from (values
      ('_agenda_ver_decisoes', 'mig_responder_fase7d'), ('agenda_rascunho_aplicar', 'mig_correcao_fase7d'), ('agenda_rascunho_planejar', 'mig_correcao_fase7d'),
      ('_agenda_rascunho_frase', 'mig_rascunho_fase7d')) t(nome, fonte) loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_viva from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = c.nome;
    insert into _resultado values ('T0d ' || c.nome || ': a viva é a da migration; sem os blocos, a origem, byte a byte',
      v_viva = pg_temp.corpo(v_mig, c.nome) and pg_temp.sem_7d(v_viva) = pg_temp.sem_7d(pg_temp.corpo(current_setting('agenda_teste.' || c.fonte), c.nome)), null);
  end loop;
  insert into _resultado values ('T0e a sessão do retorno e os focos: agenda_data_dita, _agenda_chave_telefone, agenda_dia_util, agenda_somar_du, agenda_feriado, _agenda_cliente_dia, _agenda_nome_curto, _agenda_juntar e _agenda_corta ficam de fora',
    v_mig !~ 'function public\.(agenda_data_dita|_agenda_chave_telefone|agenda_dia_util|agenda_somar_du|agenda_feriado|_agenda_cliente_dia|_agenda_nome_curto|_agenda_juntar|_agenda_corta)\(', null);
  insert into _resultado values ('T0f só funções: nenhuma tabela, coluna, índice, gatilho nem dado na migration',
    v_mig !~* '(^|\n)\s*(alter table|create table|create index|create unique index|create trigger|drop )', null);
end
$t0$;

insert into _resultado
select 'T0g o título: até as opções, a 1ª frase, sem a pontuação do fim, em até 90 letras; o texto que começa nas opções não some',
       public._agenda_titulo_da_pergunta('Nelson já autorizou? 1) Sim; 2) Não.') = 'Nelson já autorizou?'
       and public._agenda_titulo_da_pergunta('Na agenda conto com Alex: você disse todo dia útil. Alex não tem telefone. Está certo? 1) Está certo; 2) Mudou.') = 'Na agenda conto com Alex: você disse todo dia útil'
       and public._agenda_titulo_da_pergunta(repeat('palavra ', 30)) like '%…' and char_length(public._agenda_titulo_da_pergunta(repeat('palavra ', 30))) <= 91
       and public._agenda_titulo_da_pergunta('Nelson precisa de vaga. 1) Sim; 2) Não.') = 'Nelson precisa de vaga'
       and public._agenda_titulo_da_pergunta('1) Sim; 2) Não.') <> ''
       and public._agenda_titulo_da_pergunta(E'Vai?\n1) Sim; 2) Não.') = 'Vai?',
       public._agenda_titulo_da_pergunta('Nelson já autorizou? 1) Sim; 2) Não.');

-- ── O8. *agenda pendências* mostra tudo ────────────────────────────────────────────────────
do $o8$
declare
  v_res  jsonb := '[]'::jsonb;
  c_ops  constant jsonb := '[{"n":1,"texto":"Está certo (recomendo)"},{"n":2,"texto":"Mudou"}]';
  c_opsn constant jsonb := '[{"n":1,"texto":"Vanderlei: Porta Fusível…"},{"n":2,"texto":"nenhum (estoque ou escritório)"}]';
  c_txt  constant text := 'Uma pergunta da agenda com umas cento e vinte letras, para a soma passar das mil letras do teto dos outros focos sem cortar nada aqui.';
  v      jsonb;
  v_t    text;
  r      jsonb;
  k      int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('O8', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- Passa de mil, e cabe em 1.800: tudo sai, sem corte
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.limpa();
    perform pg_temp.perg('equipe_cadastro', 'o8:1', 'Decida a primeira, com a história dela. ' || c_txt || ' 1) Está certo (recomendo); 2) Mudou.', c_ops);
    perform pg_temp.perg('equipe_cadastro', 'o8:2', 'Decida a segunda, com a história dela. ' || c_txt || ' 1) Está certo (recomendo); 2) Mudou.', c_ops);
    for k in 1 .. 7 loop
      perform pg_temp.perg('bem_livre', 'o8:sem:' || k, format('Sem número %s. ', k) || c_txt, '[]'::jsonb, null, date '2027-07-01' + k);
    end loop;
    v := pg_temp.ver();
    v_t := v ->> 'texto';
    v_res := pg_temp.ok(v_res, 'O8a acima de mil e dentro das 1.800 letras: tudo sai, sem corte e sem a linha dos focos',
      char_length(v_t) > 1000 and char_length(v_t) <= 1800 and (select count(*) from regexp_matches(v_t, 'Sem número \d', 'g')) = 7
      and v_t not like '%(e mais%' and v_t not like '%por assunto%', char_length(v_t)::text);
    v_res := pg_temp.ok(v_res, 'O8b dados: as 2 numeradas em decisoes e as 7 sem número em abertas, com tipo e texto; outras segue a contagem',
      jsonb_array_length(v #> '{dados,decisoes}') = 2 and jsonb_array_length(v #> '{dados,abertas}') = 7 and (v #>> '{dados,outras}')::int = 7
      and v #>> '{dados,abertas,0,tipo}' = 'bem_livre' and v #>> '{dados,abertas,0,texto}' like 'Sem número 1. %', v::text);
    insert into public.agenda_perguntas (tipo, chave, texto, opcoes, modo, criada_em) values ('bem_livre', 'o8:sombra', 'Em sombra não é pergunta de verdade.', '[]'::jsonb, 'sombra', timestamptz '2027-07-16 08:00-03');
    insert into public.agenda_perguntas (tipo, chave, texto, opcoes, modo, criada_em, expira_em) values ('bem_livre', 'o8:venceu', 'Esta venceu antes de agora.', '[]'::jsonb, 'ligado', timestamptz '2027-07-16 08:00-03', timestamptz '2027-07-16 09:00-03');
    v := pg_temp.ver();
    v_res := pg_temp.ok(v_res, 'O8b2 dados não leva a pergunta em teste nem a vencida', jsonb_array_length(v #> '{dados,abertas}') = 7 and (v #> '{dados,abertas}')::text not like '%Em sombra%' and (v #> '{dados,abertas}')::text not like '%venceu antes%', null);
    -- O teto é só deste foco: o de texto_max maior vale, e a 1ª linha do corte continua inteira
    update public.agenda_config set texto_max = 2000 where id;
    for k in 1 .. 3 loop
      perform pg_temp.perg('bem_livre', 'o8:grande:' || k, repeat('Muito texto. ', 45), '[]'::jsonb);
    end loop;
    v_res := pg_temp.ok(v_res, 'O8c quem subir texto_max acima do teto do foco não encolhe o foco', char_length(pg_temp.ver() ->> 'texto') > 1800, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O8a quebrou', false, sqlerrm);
  end;
  -- Passa das 1.800: o corte diz por onde pedir; dados leva o cortado; quem tem opções vem antes
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.limpa();
    perform pg_temp.perg('equipe_cadastro', 'o8:1', 'Decida a primeira. 1) Está certo; 2) Mudou.', c_ops);
    for k in 1 .. 16 loop
      perform pg_temp.perg('bem_livre', 'o8:sem:' || k, format('Sem número %s. ', k) || c_txt, '[]'::jsonb, null, date '2027-07-01' + k);
    end loop;
    -- a nota é a última pela ordem de antes (sem perda_em), e é a que se responde por número
    perform pg_temp.perg('nfe_vincular', 'o8:nota', 'Chegou a nota 111. É de qual serviço? 1) Vanderlei: Porta Fusível…; 2) nenhum (estoque ou escritório). Me diga o número ou o nome.', c_opsn);
    v := pg_temp.ver();
    v_t := v ->> 'texto';
    v_res := pg_temp.ok(v_res, 'O8d acima das 1.800: corta com "(e mais N linhas)" e diz os focos por assunto, no teto',
      char_length(v_t) <= 1800 and v_t ~ E'\\(e mais \\d+ linhas\\)\nPara ver por assunto: \\*agenda compras\\*, \\*agenda clientes\\* ou \\*agenda gestor\\*\\.$', right(v_t, 200));
    v_res := pg_temp.ok(v_res, 'O8e dados leva todas as abertas, mesmo as cortadas', jsonb_array_length(v #> '{dados,abertas}') = 17 and (v #>> '{dados,outras}')::int = 17
      and v_t not like '%Sem número 16.%' and (v #> '{dados,abertas}')::text like '%Sem número 16.%', null);
    v_res := pg_temp.ok(v_res, 'O8f quem tem opções vem antes das sem opções: a nota não é a que o corte tira',
      v_t like '%Também quero saber: Chegou a nota 111.%' and position('Chegou a nota 111' in v_t) < position('Sem número 1.' in v_t) and v #>> '{dados,abertas,0,tipo}' = 'nfe_vincular', v_t);
    v_res := pg_temp.ok(v_res, 'O8g o resto fica na ordem de antes', position('Sem número 1.' in v_t) < position('Sem número 2.' in v_t), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O8d quebrou', false, sqlerrm);
  end;
  -- Exatamente no teto: 1.800 cabem, 1.801 cortam
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.limpa();
    perform pg_temp.perg('bem_livre', 'o8:a', repeat('x', 580), '[]'::jsonb, null, date '2027-07-01');
    perform pg_temp.perg('bem_livre', 'o8:b', repeat('w', 580), '[]'::jsonb, null, date '2027-07-02');
    -- "Também quero saber: " tem 20 letras, 3 vezes, e 2 quebras de linha: sobram 1.800 - 2 x 580 - 62 = 578
    perform pg_temp.perg('bem_livre', 'o8:c', repeat('y', 578), '[]'::jsonb, null, date '2027-07-03');
    v_t := pg_temp.ver() ->> 'texto';
    v_res := pg_temp.ok(v_res, 'O8h 1.800 letras cabem', char_length(v_t) = 1800 and v_t not like '%(e mais%', char_length(v_t)::text);
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where chave = 'o8:c';
    perform pg_temp.perg('bem_livre', 'o8:d', repeat('y', 579), '[]'::jsonb, null, date '2027-07-03');
    v_t := pg_temp.ver() ->> 'texto';
    v_res := pg_temp.ok(v_res, 'O8i 1.801 cortam, e a linha dos focos entra no teto', v_t like '%(e mais 1 linha)%por assunto%' and char_length(v_t) <= 1800, char_length(v_t)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O8h quebrou', false, sqlerrm);
  end;
  -- A linha dos focos conta no teto: 3 linhas que caberiam sozinhas saem para ela entrar
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.limpa();
    for k in 1 .. 4 loop
      perform pg_temp.perg('bem_livre', 'o8:n:' || k, repeat(k::text, 560), '[]'::jsonb, null, date '2027-07-01' + k);
    end loop;
    v_t := pg_temp.ver() ->> 'texto';
    v_res := pg_temp.ok(v_res, 'O8n a linha dos focos entra no teto, e tira linha se precisar', char_length(v_t) <= 1800 and v_t like '%(e mais 2 linhas)%por assunto%', char_length(v_t)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O8n quebrou', false, sqlerrm);
  end;
  -- O "1" sozinho: só os títulos
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.limpa();
    perform pg_temp.perg('equipe_cadastro', 'o8:1', 'Na agenda conto com Alex: você disse todo dia útil. Alex não tem telefone. Está certo? 1) Está certo (recomendo); 2) Mudou.', c_ops, null, date '2027-07-01');
    perform pg_temp.perg('equipe_cadastro', 'o8:2', 'Nelson precisa de vaga. 1) Está certo (recomendo); 2) Mudou.', c_ops, null, date '2027-07-02');
    perform pg_temp.perg('nfe_vincular', 'o8:nota', 'Chegou a nota 111 da Tamoyo. É de qual serviço? 1) Vanderlei: Porta Fusível…; 2) nenhum. Me diga o número ou o nome.', c_opsn);
    r := pg_temp.responde(null, '1', '1');
    v_res := pg_temp.ok(v_res, 'O8j "1" sozinho: "Qual decisão?" só com os títulos numerados, sem as opções aninhadas; a nota, sem número',
      r ->> 'motivo' = 'decisao_ambigua' and r ->> 'texto' = 'Qual decisão? 1) Na agenda conto com Alex: você disse todo dia útil; 2) Nelson precisa de vaga. Diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2"). Eu não escolho por você. Sem número, responda com as suas palavras: Chegou a nota 111 da Tamoyo.',
      r::text);
    v_res := pg_temp.ok(v_res, 'O8k a régua não muda: nada de rascunho, e o texto não leva opção de ninguém', pg_temp.rascunhos() = 0 and r ->> 'texto' not like '%Está certo%' and r ->> 'texto' not like '%Vanderlei%', null);
    update public.agenda_config set modo_cadastro = 'ligado' where id;
    r := pg_temp.responde('2', '1', 'na decisão 2, a opção 1');
    v_res := pg_temp.ok(v_res, 'O8l dizendo a decisão e a opção, a régua de sempre: entra na releitura', (r ->> 'ok')::boolean and pg_temp.rascunhos() = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O8j quebrou', false, sqlerrm);
  end;
  -- Sem a nota: a frase não diz "Sem número"
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.limpa();
    perform pg_temp.perg('equipe_cadastro', 'o8:1', 'Pergunta A? 1) Está certo; 2) Mudou.', c_ops, null, date '2027-07-01');
    perform pg_temp.perg('equipe_cadastro', 'o8:2', 'Pergunta B? 1) Está certo; 2) Mudou.', c_ops, null, date '2027-07-02');
    r := pg_temp.responde(null, '1', '1');
    v_res := pg_temp.ok(v_res, 'O8m sem pergunta sem número, a frase termina no "Eu não escolho por você."',
      r ->> 'texto' = 'Qual decisão? 1) Pergunta A?; 2) Pergunta B?. Diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2"). Eu não escolho por você.', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O8m quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$o8$;

-- ── O9. O "Já terminou" com o freio ────────────────────────────────────────────────────────
do $o9$
declare
  v_res jsonb := '[]'::jsonb;
  c_ops constant jsonb := '[{"n":1,"texto":"Marque 10 dias","efeito":{"dias":10}},{"n":2,"texto":"Eu digo os dias"},{"n":3,"texto":"Já terminou (ou já entreguei)","efeito":{"terminou":true}}]';
  c_txt constant text := 'Lenine (OS-J1): pelo valor do orçamento são 10 diárias. Me diga os dias. 1) Marque 10 dias; 2) Eu digo os dias; 3) Já terminou (ou já entreguei).';
  r     jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('O9', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.limpa();
    perform pg_temp.perg('estimativa', 'estimativa:o9', c_txt, c_ops, pg_temp.os('OS-J1'));
    update public.agenda_config set gestor_so_propor = true where id;
    r := pg_temp.responde('1', '3', 'na decisão 1, a opção 3');
    v_res := pg_temp.ok(v_res, 'O9a "Já terminou" com o freio aponta o *entreguei*, com o nome, e não muda nada',
      r ->> 'motivo' = 'em_teste' and r ->> 'texto' = 'Com *gestor, só propor* essa resposta não muda nada agora. Para dizer que terminou, mande *entreguei Lenine*: eu concluo e marco a entrega.'
      and pg_temp.rascunhos() = 0, r::text);
    r := pg_temp.responde(pg_temp.os('OS-J1')::text, '3', 'o Lenine terminou, a 3');
    v_res := pg_temp.ok(v_res, 'O9b dito pelo nome, o mesmo', r ->> 'texto' like '%mande *entreguei Lenine*%', r::text);
    r := pg_temp.responde('1', '1', 'na decisão 1, a opção 1');
    v_res := pg_temp.ok(v_res, 'O9c a opção com os dias: a recusa de hoje', r ->> 'texto' = 'Com *gestor, só propor* essa resposta não muda nada agora. Se quiser, me diga com as suas palavras (por exemplo, os dias do serviço).', r::text);
    r := pg_temp.responde('1', '2', 'na decisão 1, a opção 2');
    v_res := pg_temp.ok(v_res, 'O9d a opção sem efeito: a recusa de hoje', r ->> 'texto' like 'Com *gestor, só propor* essa resposta não muda nada agora. Se quiser%', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O9a quebrou', false, sqlerrm);
  end;
  -- Sem o freio, em teste: a frase de sempre, que não fala do freio
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.limpa();
    perform pg_temp.perg('estimativa', 'estimativa:o9', c_txt, c_ops, pg_temp.os('OS-J1'));
    update public.agenda_config set gestor_so_propor = false, modo_marcar_sozinho = 'sombra' where id;
    r := pg_temp.responde('1', '3', 'na decisão 1, a opção 3');
    v_res := pg_temp.ok(v_res, 'O9e sem o freio, com a pergunta em teste: a frase do teste', r ->> 'texto' = 'Essa pergunta ainda está em teste: mostro como ficaria, mas não mudo nada.', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O9e quebrou', false, sqlerrm);
  end;
  -- A situacao também tem a opção; a nota não fala do freio
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.limpa();
    perform pg_temp.perg('situacao', 'situacao:o9', 'Lenine (OS-J1): quanto falta? 1) Falta 1 dia; 2) Eu digo; 3) Já terminou.', c_ops, pg_temp.os('OS-J1'));
    update public.agenda_config set gestor_so_propor = true where id;
    r := pg_temp.responde('1', '3', 'na decisão 1, a opção 3');
    v_res := pg_temp.ok(v_res, 'O9f a situacao com "Já terminou": o mesmo', r ->> 'texto' like '%mande *entreguei Lenine*%', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O9f quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$o9$;

-- ── O16. Quem saiu da equipe ───────────────────────────────────────────────────────────────
do $o16$
declare
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
  v_n   int;
  v_h   date := date '2027-07-16';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('O16', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('ligado');   -- a nota do O17 fora do caminho: aqui só a marca
    v_res := pg_temp.ok(v_res, 'O16a os dois estão na equipe antes: sem marca', not public._agenda_saiu_da_equipe(pg_temp.pessoa('Roberto')) and not public._agenda_saiu_da_equipe(pg_temp.pessoa('João')), null);
    r := pg_temp.plan('OS-J2', jsonb_build_object('autorizados', jsonb_build_array('Roberto', 'João')), 'Roberto e João estão autorizados no serviço do Nelson');
    v_res := pg_temp.ok(v_res, 'O16b da equipe: a frase de sempre', r ->> 'releitura' like '%Autorizados nesse serviço: Roberto e João.%' and r ->> 'releitura' not like '%saiu%', r::text);
    update public.agenda_rascunho set estado = 'descartado' where autor = pg_temp.adm() and estado = 'aberto';
    perform pg_temp.saiu('Roberto');
    perform pg_temp.saiu('João');
    v_res := pg_temp.ok(v_res, 'O16c quem saiu: tinha linha, e nenhuma viva; e está fora da grade', public._agenda_saiu_da_equipe(pg_temp.pessoa('Roberto'))
      and not exists (select 1 from public.agenda_capacidade(v_h, v_h + 13, v_h) k where k.payee_id = pg_temp.pessoa('Roberto')), null);
    r := pg_temp.plan('OS-J2', jsonb_build_object('autorizados', jsonb_build_array('Roberto', 'João')), 'Roberto e João estão autorizados no serviço do Nelson');
    v_res := pg_temp.ok(v_res, 'O16d a releitura marca os dois, sem recusar', (r ->> 'ok')::boolean and r ->> 'releitura' like '%Autorizados nesse serviço: Roberto (saiu da equipe) e João (saiu da equipe).%', r::text);
    v_res := pg_temp.ok(v_res, 'O16e a marca fica no rascunho só de quem saiu', (select bool_and(e ? 'saiu') from jsonb_array_elements(pg_temp.rascunho('OS-J2') -> 'autorizados') e), pg_temp.rascunho('OS-J2')::text);
    r := pg_temp.grava();
    select count(*) into v_n from public.os_autorizados a where a.service_order_id = pg_temp.os('OS-J2') and a.revogado_em is null
       and a.payee_id in (pg_temp.pessoa('Roberto'), pg_temp.pessoa('João'));
    v_res := pg_temp.ok(v_res, 'O16f o *grava* grava os dois: pode ser legítimo', (r ->> 'ok')::boolean and v_n = 2, r::text);
    v_res := pg_temp.ok(v_res, 'O16g a ação diz a mesma coisa', (select a.texto from public.agenda_acoes a where a.tipo = 'local' and a.origem = 'dono' and a.service_order_id = pg_temp.os('OS-J2') order by a.criada_em desc limit 1) like '%Roberto (saiu da equipe)%', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O16a quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('ligado');
    perform pg_temp.saiu('Roberto');
    r := pg_temp.plan('OS-J2', jsonb_build_object('autorizados', jsonb_build_array('Alex', 'eu', 'Roberto')), 'Alex, eu e o Roberto');
    v_res := pg_temp.ok(v_res, 'O16h marca só quem saiu: o dono é "você", e o Alex fica sem nada',
      r ->> 'releitura' like '%Autorizados nesse serviço: Alex, você e Roberto (saiu da equipe).%', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O16h quebrou', false, sqlerrm);
  end;
  -- Quem nunca esteve na agenda não saiu: terceiro; o dono nunca; quem tem linha viva, não
  begin
    perform pg_temp.base('ligado');
    insert into public.payees (name, kind, active) values ('Zeca Terceiro', 'prestador', true);
    v_res := pg_temp.ok(v_res, 'O16i o terceiro, sem nenhuma linha, não saiu', not public._agenda_saiu_da_equipe(pg_temp.pessoa('Zeca Terceiro')), null);
    update public.agenda_disponibilidade set substituida_em = timestamptz '2027-06-30 12:00-03' where payee_id = public._agenda_dono(null) and substituida_em is null;
    insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, substituida_em)
    select public._agenda_dono(null), array[1, 2]::smallint[], 'disponivel', 'dono', timestamptz '2027-06-30 12:00-03'
     where not exists (select 1 from public.agenda_disponibilidade w where w.payee_id = public._agenda_dono(null));
    v_res := pg_temp.ok(v_res, 'O16j o dono nunca sai, mesmo sem linha viva', not public._agenda_saiu_da_equipe(public._agenda_dono(null)), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O16i quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$o16$;

-- ── O17. Em teste, a releitura diz que só anotou ───────────────────────────────────────────
do $o17$
declare
  v_res  jsonb := '[]'::jsonb;
  c_nota constant text := ' (anotei; só muda o plano quando isso for ligado)';
  r      jsonb;
  v_t    text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('O17', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- Em sombra: os 3 assuntos
  begin
    perform pg_temp.base('sombra');
    v_t := pg_temp.plan('OS-J1', '{"chega_em": "dia 20", "sai_em": "dia 23"}'::jsonb, 'o motorhome do Lenine chega dia 20 e sai dia 23') ->> 'releitura';
    v_res := pg_temp.ok(v_res, 'O17a pátio, em sombra: a frase e a nota', v_t like '%O motorhome chega ter 20/07 e sai sex 23/07.' || c_nota || '%', v_t);
    v_t := pg_temp.plan('OS-J2', '{"viagem": "pernoite"}'::jsonb, 'o serviço do Nelson é viagem, a gente dorme lá') ->> 'releitura';
    v_res := pg_temp.ok(v_res, 'O17b viagem, em sombra', v_t like '%Viagem com pernoite: a equipe vai e volta junta, em dias seguidos.' || c_nota || '%', v_t);
    v_t := pg_temp.plan('OS-J3', '{"autorizados": ["Alex", "eu"]}'::jsonb, 'Alex e eu estamos autorizados no serviço do Vanderlei') ->> 'releitura';
    v_res := pg_temp.ok(v_res, 'O17c acesso, em sombra', v_t like '%Autorizados nesse serviço: Alex e você.' || c_nota || '%', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O17a quebrou', false, sqlerrm);
  end;
  -- Só chegada, só saída; a viagem de ida e volta e "sem viagem"; o que limpa não leva nota; o resto não leva nota
  begin
    perform pg_temp.base('sombra');
    v_t := pg_temp.plan('OS-J1', '{"chega_em": "dia 20"}'::jsonb, 'o motorhome do Lenine chega dia 20') ->> 'releitura';
    v_res := pg_temp.ok(v_res, 'O17d só a chegada', v_t like '%O motorhome chega ter 20/07.' || c_nota || '%', v_t);
    v_t := pg_temp.plan('OS-J3', '{"sai_em": "dia 23"}'::jsonb, 'o motorhome do Vanderlei sai dia 23') ->> 'releitura';
    v_res := pg_temp.ok(v_res, 'O17e só a saída', v_t like '%O motorhome sai sex 23/07.' || c_nota || '%', v_t);
    v_t := pg_temp.plan('OS-J2', '{"viagem": "bate_volta"}'::jsonb, 'é ida e volta no dia') ->> 'releitura';
    v_res := pg_temp.ok(v_res, 'O17f ida e volta', v_t like '%Viagem: ida e volta no mesmo dia.' || c_nota || '%', v_t);
    v_t := pg_temp.plan('OS-J5', '{"viagem": "regional"}'::jsonb, 'é aqui na região') ->> 'item';
    v_res := pg_temp.ok(v_res, 'O17f2 "sem viagem" não leva a nota: nada vai mudar o plano', v_t like '%Sem viagem (aqui na região).%' and v_t not like '%anotei;%', v_t);
    v_t := pg_temp.plan('OS-J2', '{"viagem": "regional"}'::jsonb, 'não, é aqui na região') ->> 'item';
    v_res := pg_temp.ok(v_res, 'O17f3 quem disse ida e volta e corrigiu para a região: a nota sai', v_t like '%Sem viagem (aqui na região).%' and v_t not like '%anotei;%', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O17d quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    v_t := pg_temp.plan('OS-J2', '{"local": "Marina Itajaí", "bem_onde": "seco", "descer_quem": "a marina", "bem_exige": "agua"}'::jsonb, 'na Marina Itajaí, em seco, a marina desce, o teste é na água') ->> 'releitura';
    v_res := pg_temp.ok(v_res, 'O17g local e bem não levam a nota: só viagem, pátio e acesso', v_t like '%Local: Marina Itajaí.%' and v_t not like '%anotei;%', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O17g quebrou', false, sqlerrm);
  end;
  -- O que limpa não diz que anotou
  begin
    perform pg_temp.base('sombra');
    insert into public.os_planejamento (service_order_id, viagem) values (pg_temp.os('OS-J2'), 'pernoite')
    on conflict (service_order_id) do update set viagem = 'pernoite';
    v_t := pg_temp.plan('OS-J2', '{"limpar": ["viagem"]}'::jsonb, 'tira a viagem') ->> 'releitura';
    v_res := pg_temp.ok(v_res, 'O17h tirar a viagem não leva a nota', v_t like '%Tirei a viagem que eu tinha (volto a supor).%' and v_t not like '%anotei;%', v_t);
    v_res := pg_temp.ok(v_res, 'O17h2 nem a chave', not (pg_temp.rascunho('OS-J2') ? 'em_teste_viagem'), pg_temp.rascunho('OS-J2')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O17h quebrou', false, sqlerrm);
  end;
  -- Cada assunto pelo modo dele: ligado sem freio, a nota some; com o freio, volta; desligado, fica
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo_de('modo_patio', 'ligado');
    v_t := pg_temp.plan('OS-J1', '{"chega_em": "dia 20", "autorizados": ["Alex"], "viagem": "pernoite"}'::jsonb, 'chega dia 20, o Alex autorizado, e a gente dorme lá') ->> 'releitura';
    v_res := pg_temp.ok(v_res, 'O17i o pátio ligado: a nota sai só dele; os outros seguem', v_t like '%O motorhome chega ter 20/07.
%' and v_t like '%dias seguidos.' || c_nota || '%' and v_t like '%Autorizados nesse serviço: Alex.' || c_nota || '%', v_t);
    v_res := pg_temp.ok(v_res, 'O17j as chaves, ausentes com o modo ligado', not (pg_temp.rascunho('OS-J1') ? 'em_teste_patio') and pg_temp.rascunho('OS-J1') ? 'em_teste_viagem' and pg_temp.rascunho('OS-J1') ? 'em_teste_acesso', pg_temp.rascunho('OS-J1')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O17i quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo_de('modo_viagem', 'ligado');
    perform pg_temp.modo_de('modo_local_autorizacao', 'ligado');
    v_t := pg_temp.plan('OS-J1', '{"chega_em": "dia 20", "autorizados": ["Alex"], "viagem": "pernoite"}'::jsonb, 'chega dia 20, o Alex autorizado, e a gente dorme lá') ->> 'releitura';
    v_res := pg_temp.ok(v_res, 'O17k viagem e acesso ligados: a nota fica só no pátio', v_t like '%O motorhome chega ter 20/07.' || c_nota || '%' and (select count(*) from regexp_matches(v_t, 'anotei;', 'g')) = 1, v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O17k quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('ligado');
    update public.agenda_config set gestor_so_propor = true where id;
    v_t := pg_temp.plan('OS-J1', '{"viagem": "pernoite"}'::jsonb, 'a gente dorme lá') ->> 'releitura';
    v_res := pg_temp.ok(v_res, 'O17l ligado com o freio é em teste: a nota fica', v_t like '%' || c_nota || '%', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O17l quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('desligado');
    v_t := pg_temp.plan('OS-J1', '{"viagem": "pernoite"}'::jsonb, 'a gente dorme lá') ->> 'releitura';
    v_res := pg_temp.ok(v_res, 'O17m desligado: a nota fica', v_t like '%' || c_nota || '%', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O17m quebrou', false, sqlerrm);
  end;
  -- O rascunho junta as frases da mesma OS: as notas ficam
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J1', '{"chega_em": "dia 20"}'::jsonb, 'chega dia 20');
    v_t := pg_temp.plan('OS-J1', '{"viagem": "pernoite"}'::jsonb, 'a gente dorme lá') ->> 'releitura';
    v_res := pg_temp.ok(v_res, 'O17n 2 frases da mesma OS: as 2 notas', (select count(*) from regexp_matches(v_t, 'anotei;', 'g')) = 2, v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O17n quebrou', false, sqlerrm);
  end;
  -- O *grava* e o *desfaz* dizem o fato; o plano não muda; o dado grava como sempre
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J2', '{"viagem": "pernoite"}'::jsonb, 'o serviço do Nelson é viagem, a gente dorme lá');
    r := pg_temp.grava();
    v_t := (select a.texto from public.agenda_acoes a where a.tipo = 'local' and a.origem = 'dono' and a.service_order_id = pg_temp.os('OS-J2') order by a.criada_em desc limit 1);
    v_res := pg_temp.ok(v_res, 'O17o a ação do *grava* diz o fato, sem a nota', v_t like '%Viagem com pernoite%' and v_t not like '%anotei;%', v_t);
    v_res := pg_temp.ok(v_res, 'O17p o dado gravou, com o modo em sombra', (select pl.viagem from public.os_planejamento pl where pl.service_order_id = pg_temp.os('OS-J2')) = 'pernoite', r::text);
    r := pg_temp.desfaz('OS-J2');
    v_res := pg_temp.ok(v_res, 'O17q o *desfaz* diz o fato', (r ->> 'releitura') like '%Viagem com pernoite%' and (r ->> 'releitura') not like '%anotei;%', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O17o quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$o17$;

select teste, ok, detalhe from _resultado order by ok, teste;

rollback;

-- Prova da conversa da Agenda de Produção, Fase 7c (pacote P4): o que o dono diz de quem faz o quê, do que a OS pede, do responsável
-- e do "está certo" vira releitura no rascunho, e só o *grava* grava (migration 20261102100300; spec-fase7c §5.4, §6.3, §7, §8.3
-- agenda_fase7c_conversa.sql, R5.1-1).
-- bancada: depende de 20261102100300
--
--   C0  as portas: a RPC (definer; o painel e o WhatsApp: authenticated e service_role; nunca anon), o *grava* da linha (definer; de
--       ninguém, nem do service_role) e a frase (invoker, IMMUTABLE; só do service_role); as 2 recriadas com as portas de antes
--   C1  as 4 formas e as releituras byte a byte (§6.3): (a) "Roberto instala sozinho", "João é ajudante: não vai sozinho em serviço de
--       risco", "Roberto não sobe no teto", o dono ("você não sobe no teto") e o Alex achado pelo nome (R5.1-1); (b) "pede quem sobe
--       no teto em todos os dias" / "não pede quem sobe no teto"; (c) "o responsável é Roberto (fica em todos os dias)" / "fica sem
--       responsável fixo"; (d) "fica como eu marquei (Roberto instala sozinho; João é ajudante; Bruno é novo)"; a correção substitui a
--       linha (instala × ajudante na mesma chave); os 14 o_que_faz com a etiqueta e o nível da §3.2; a frase direto
--   C2  a guarda do trecho: "o João é bom" não diz que ele instala sozinho; "quase instala" com as palavras de instala; o que a OS
--       pede; o nome do responsável; o "ninguém"; nada entra no rascunho
--   C3  quem e qual: a pessoa ambígua, a que não está na equipe ("Não conheço…"), a OS que não está na carteira; o confirmar sem
--       pergunta, com a pergunta não mostrada e sem proposta; o dono não é ajudante nem responsável fixo; uma forma por vez (22023), o
--       canal, os valores fora da lista, o trecho vazio; a técnica logada (42501) e o admin logado (o painel)
--   C4  o *grava*: (a) a etiqueta do dono vale (origem dono, "você disse", o trecho, a hora, o autor) e agenda_habilidades a lê; a
--       exclusividade instala × ajudante e a mesma etiqueta; com a pergunta habilidade:equipe aberta e mostrada, a corrigida vira
--       substituída, o resto vale e a pergunta fecha ("você corrigiu; o resto ficou como eu marquei"), também com 2 correções no mesmo
--       lote; a pergunta não mostrada não fecha; (b) exigencias_ditas, o trecho e o histórico, e os_exigencias passa a ler; (c) o
--       responsável, a hora e o trecho, e _agenda_lider_da_os o lê ("ninguém" limpa); (d) as propostas valem e a pergunta fecha ("você
--       confirmou"); a pergunta refeita recusa o lote; o confirmar e a correção no mesmo lote; em qualquer modo da agenda
--   C5  com modo_leitura desligado não anota nada
--   C6  as cópias: tirado o bloco "-- FASE 7c:", o corpo vivo e o da migration de _agenda_rascunho_frase e de agenda_rascunho_gravar
--       são o de 20261101100100; os tipos de antes byte a byte (a frase de cada um e o "Gravado. Agora:" de um lote de antes, contra as
--       de 20261101100100 rodadas como pg_temp)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7c_conversa.sql
--   Seguro em produção: termina em ROLLBACK. C0 roda em qualquer banco; C6 sai PULADO sem as migrations como texto; o resto usa as
--   fixtures e só roda na bancada (fora dela sai PULADO).
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
-- O corpo de uma função numa migration (o texto entre "as $function$" e "$function$") e a definição inteira.
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
-- O texto sem os blocos "-- FASE 7c: … -- FASE 7c: fim" (as linhas de abrir e de fechar saem junto).
create function pg_temp.sem_7c(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7[cdef]:' and l !~ '^\s*-- FASE 7[cdef]: fim' then 1
                                                when l ~ '^\s*-- FASE 7[cdef]: fim' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- FASE 7[cdef]: fim' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
-- p_sql (que devolve um valor) com o login p_sub (ou o papel p_papel sem login): o resultado em texto, ou 'erro <estado>: <mensagem>'.
create function pg_temp.como(p_papel text, p_sub uuid, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claims',
                     (case when p_sub is null then jsonb_build_object('role', p_papel)
                           else jsonb_build_object('role', p_papel, 'sub', p_sub) end)::text, true);
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

-- ── C0. As portas (sem fixture) ────────────────────────────────────────────────────────────────────────────────
with f(sig, definer, vol, anon, auth, srv) as (values
  ('public.agenda_rascunho_habilidade(uuid, text, text, text, text, text, text, text, boolean, text, date)', true, 'v', false, true, true),
  ('public._agenda_aplicar_habilidade(uuid, jsonb, text, date, timestamptz)', true, 'v', false, false, false),
  ('public._agenda_habilidade_frase(jsonb)', false, 'i', false, false, true),
  ('public._agenda_rascunho_frase(text, jsonb)', false, 'i', false, false, true),
  ('public.agenda_rascunho_gravar(uuid, date)', true, 'v', false, true, true))
insert into _resultado
select 'C0 as portas: a RPC (definer; authenticated e service_role, o painel e o WhatsApp), o *grava* da linha (definer; de ninguém, nem do service_role), a frase (invoker, IMMUTABLE; só service_role) e as 2 recriadas com as de antes; search_path fixo; nunca anon',
       count(p.oid) = 5
       and bool_and(p.prosecdef = f.definer and p.provolatile = f.vol and array_to_string(p.proconfig, ',') like '%search_path=public%'
                    and has_function_privilege('anon', p.oid, 'execute') = f.anon
                    and has_function_privilege('authenticated', p.oid, 'execute') = f.auth
                    and has_function_privilege('service_role', p.oid, 'execute') = f.srv),
       string_agg(format('%s definer=%s %s anon=%s auth=%s srv=%s', f.sig, p.prosecdef, p.provolatile,
                         has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('authenticated', p.oid, 'execute'),
                         has_function_privilege('service_role', p.oid, 'execute')), '; ')
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

-- ── A fixture (a sintética da 7c, por cima da 7b, da 7a e do replay) ─────────────────────────────────────────────────
do $carga$
begin
  if coalesce(current_setting('agenda_teste.fase7c', true), '') <> '' and coalesce(current_setting('agenda_teste.fase7b', true), '') <> '' then
    execute current_setting('agenda_teste.fase7c');
  end if;
end
$carga$;

create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.service_orders so where so.service_order_number = 'OS-97171')
$f$;
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by id limit 1
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select id from public.payees where name = p_nome and active order by id limit 1
$f$;
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
-- a ferramenta, como o WhatsApp a chama (o service_role, o dono em p_autor), em qua 04/11
create function pg_temp.hab(p_pessoa text, p_faz text, p_os text, p_exige text, p_meios text, p_lider text, p_conf boolean,
                            p_trecho text) returns jsonb language sql as $f$
  select public.agenda_rascunho_habilidade(pg_temp.adm(), 'whatsapp', p_pessoa, p_faz, p_os, p_exige, p_meios, p_lider, p_conf,
                                           p_trecho, date '2026-11-04')
$f$;
-- a mesma, devolvendo o código do erro (o 22023 das formas e dos valores)
create function pg_temp.erro_hab(p_canal text, p_pessoa text, p_faz text, p_os text, p_exige text, p_meios text, p_lider text,
                                 p_conf boolean) returns text language plpgsql as $f$
begin
  perform public.agenda_rascunho_habilidade(pg_temp.adm(), p_canal, p_pessoa, p_faz, p_os, p_exige, p_meios, p_lider, p_conf,
                                            'o Roberto instala sozinho', date '2026-11-04');
  return 'sem erro';
exception when others then
  return sqlstate || ': ' || sqlerrm;
end $f$;
-- o *grava* do dono em qua 04/11 16:20
create function pg_temp.grava() returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  perform set_config('agenda.agora', '2026-11-04 16:20-03', true);
  v := public.agenda_rascunho_gravar(pg_temp.adm(), date '2026-11-04');
  perform set_config('agenda.agora', '', true);
  return v;
end $f$;
create function pg_temp.abertos() returns int language sql stable as $f$
  select count(*)::int from public.agenda_rascunho where autor = pg_temp.adm() and estado = 'aberto'
$f$;
-- a pergunta habilidade:equipe que o gestor abriria (P5), com as 3 propostas do histórico (Roberto instala 2, João ajudante 2, Bruno
-- ajudante 1); mostrada ao dono no fechamento de ter 03/11 (ou não)
create function pg_temp.pergunta(p_mostrada boolean) returns uuid language plpgsql as $f$
declare v uuid;
begin
  insert into public.agenda_perguntas (tipo, chave, texto, modo, estado, mostrada_vezes, mostrada_em, mostrada_via, criada_em)
  values ('habilidade', 'habilidade:equipe:2026-11-03',
          'Para não mandar ninguém sozinho em serviço de risco, marquei quem faz o quê (teste da 7c P4).', 'ligado', 'aberta',
          case when p_mostrada then 1 else 0 end, case when p_mostrada then timestamptz '2026-11-03 17:30-03' end,
          case when p_mostrada then 'fechamento' end, timestamptz '2026-11-03 16:10-03')
  returning id into v;
  insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, evidencia, pergunta_id, criado_em)
  values (pg_temp.pessoa('Roberto'), 'instala', 2, 'gestor', 'proposta', '32 diárias desde 23/08', '{}', v, timestamptz '2026-11-03 16:10-03'),
         (pg_temp.pessoa('João'), 'ajudante', 2, 'gestor', 'proposta', 'entrou em 29/09, 15 diárias', '{}', v, timestamptz '2026-11-03 16:10-03'),
         (pg_temp.pessoa('Bruno'), 'ajudante', 1, 'gestor', 'proposta', 'começou em 20/10, 3 diárias', '{}', v, timestamptz '2026-11-03 16:10-03');
  return v;
end $f$;
-- as etiquetas vivas de uma pessoa: "instala 2 dono vale; altura 0 dono vale"
create function pg_temp.etq(p_nome text) returns text language sql stable as $f$
  select coalesce(string_agg(format('%s %s %s %s', e.etiqueta, e.nivel, e.origem, e.estado), '; ' order by e.etiqueta, e.estado), '-')
    from public.agenda_etiquetas e where e.payee_id = pg_temp.pessoa(p_nome) and e.estado in ('proposta', 'vale')
$f$;

-- ── C1. As 4 formas e as releituras ──────────────────────────────────────────────────────────────────────────────
do $c1$
declare
  v_res  jsonb := '[]'::jsonb;
  r      jsonb;
  t      text[] := '{}';
  v_q    uuid;
  x      record;
  v_ruim text := '';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C1 as 4 formas e as releituras', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    -- (a), (b) e (c), uma depois da outra
    t := t || (pg_temp.hab('Roberto', 'instala_sozinho', null, null, null, null, false, 'o Roberto instala sozinho') ->> 'item');
    t := t || (pg_temp.hab('João', 'ajudante', null, null, null, null, false, 'o João é ajudante') ->> 'item');
    t := t || (pg_temp.hab('Roberto', 'nao_sobe_no_teto', null, null, null, null, false, 'o Roberto não sobe no teto') ->> 'item');
    t := t || (pg_temp.hab(null, null, 'Lenine', 'altura', 'todos', null, false, 'o Lenine pede alguém que sobe no teto em todos os dias') ->> 'item');
    r := pg_temp.hab(null, null, 'Lenine', null, null, 'Roberto', false, 'no Lenine o responsável é o Roberto');
    t := t || (r ->> 'item');
    v_res := pg_temp.ok(v_res, 'C1a as linhas da releitura (§6.3): (a) "Quem faz o quê: Roberto instala sozinho", "João é ajudante: não vai sozinho em serviço de risco", "Roberto não sobe no teto"; (b) "Lenine (OS-00074): pede quem sobe no teto em todos os dias"; (c) "Lenine (OS-00074): o responsável é Roberto (fica em todos os dias)"',
      t = array['Quem faz o quê: Roberto instala sozinho', 'Quem faz o quê: João é ajudante: não vai sozinho em serviço de risco',
                'Quem faz o quê: Roberto não sobe no teto', 'Lenine (OS-00074): pede quem sobe no teto em todos os dias',
                'Lenine (OS-00074): o responsável é Roberto (fica em todos os dias)'],
      array_to_string(t, ' | '));
    v_res := pg_temp.ok(v_res, 'C1b a releitura inteira: as pessoas numa linha ("Quem faz o quê"), a OS noutra (o que ela pede e o responsável juntos), o "Responda *grava*"; ok, item e itens',
      r ->> 'releitura' = E'Entendi assim, confere?\n• Quem faz o quê: Roberto instala sozinho; João é ajudante: não vai sozinho em serviço de risco; Roberto não sobe no teto.\n• Lenine (OS-00074): pede quem sobe no teto em todos os dias; o responsável é Roberto (fica em todos os dias).\nResponda *grava* ou corrija o que estiver errado.'
      and (r ->> 'ok')::boolean and r -> 'itens' = jsonb_build_array(r ->> 'item') and pg_temp.abertos() = 5,
      r ->> 'releitura');
    -- a correção: a mesma chave substitui (instala e ajudante na mesma; nao e ninguém)
    t := '{}';
    t := t || (pg_temp.hab('João', 'instala_sozinho', null, null, null, null, false, 'não, o João instala sozinho') ->> 'item');
    t := t || (pg_temp.hab(null, null, 'Lenine', 'altura', 'nao', null, false, 'o Lenine não precisa de ninguém subindo no teto') ->> 'item');
    r := pg_temp.hab(null, null, 'Lenine', null, null, 'ninguém', false, 'o Lenine fica sem responsável fixo');
    t := t || (r ->> 'item');
    v_res := pg_temp.ok(v_res, 'C1c a correção substitui a linha da mesma chave, no lugar dela: "o João é ajudante" → "João instala sozinho" (instala e ajudante se excluem); "não pede quem sobe no teto"; "fica sem responsável fixo"; continuam 5 linhas abertas',
      t = array['Quem faz o quê: João instala sozinho', 'Lenine (OS-00074): não pede quem sobe no teto',
                'Lenine (OS-00074): fica sem responsável fixo']
      and r ->> 'releitura' = E'Entendi assim, confere?\n• Quem faz o quê: Roberto instala sozinho; João instala sozinho; Roberto não sobe no teto.\n• Lenine (OS-00074): não pede quem sobe no teto; fica sem responsável fixo.\nResponda *grava* ou corrija o que estiver errado.'
      and pg_temp.abertos() = 5,
      array_to_string(t, ' | ') || ' || ' || (r ->> 'releitura'));
    -- o dono e o Alex (achado pelo nome: o contato e a linha do dono, R5.1-1)
    t := '{}';
    t := t || (pg_temp.hab('eu', 'nao_sobe_no_teto', null, null, null, null, false, 'eu não subo mais no teto') ->> 'item');
    t := t || (pg_temp.hab('Alex', 'sobe_no_teto', null, null, null, null, false, 'o Alex sobe no teto') ->> 'item');
    v_res := pg_temp.ok(v_res, 'C1d o dono ("você não sobe no teto") e o Alex, achado pelo nome sem perfil de diária (R5.1-1: nada de "Não conheço…")',
      t = array['Quem faz o quê: você não sobe no teto', 'Quem faz o quê: Alex sobe no teto'], array_to_string(t, ' | '));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- (d) com a pergunta habilidade:equipe aberta e mostrada (as 3 propostas)
  begin
    v_q := pg_temp.pergunta(true);
    r := pg_temp.hab(null, null, null, null, null, null, true, 'está certo o que você marcou da equipe');
    v_res := pg_temp.ok(v_res, 'C1e (d) o confirmar: "Quem faz o quê: fica como eu marquei (Roberto instala sozinho; João é ajudante; Bruno é novo)" (quem instala primeiro; o texto curto da etiqueta)',
      r ->> 'item' = 'Quem faz o quê: fica como eu marquei (Roberto instala sozinho; João é ajudante; Bruno é novo)'
      and (select dados ->> 'pergunta_id' from public.agenda_rascunho where autor = pg_temp.adm() and estado = 'aberto' and chave = 'hab:confirmar') = v_q::text,
      r ->> 'item');
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- os 14 o_que_faz: a etiqueta e o nível da §3.2, e a releitura "Rafael <o texto da etiqueta>"
  begin
    for x in select * from (values
        ('instala_com_alguem', 'instala', 1, 'o Rafael instala só com alguém junto'), ('instala_sozinho', 'instala', 2, 'o Rafael instala sozinho'),
        ('instala_e_ensina', 'instala', 3, 'o Rafael instala e ensina'), ('novo', 'ajudante', 1, 'o Rafael é novo'),
        ('ajudante', 'ajudante', 2, 'o Rafael é ajudante'), ('quase_instala', 'ajudante', 3, 'o Rafael é ajudante e quase instala'),
        ('nao_comissiona', 'comissiona', 0, 'o Rafael não comissiona'), ('acompanha_comissionamento', 'comissiona', 1, 'o Rafael acompanha o comissionamento'),
        ('diagnostica', 'comissiona', 2, 'o Rafael faz diagnóstico sozinho, sabe configurar'), ('comissiona', 'comissiona', 3, 'o Rafael comissiona Victron'),
        ('nao_sobe_no_teto', 'altura', 0, 'o Rafael não sobe no teto'), ('sobe_acompanhado', 'altura', 1, 'o Rafael sobe acompanhado'),
        ('sobe_no_teto', 'altura', 2, 'o Rafael sobe no teto'), ('sobe_e_orienta', 'altura', 3, 'o Rafael sobe e orienta no teto')) v(faz, etq, niv, trecho)
    loop
      r := pg_temp.hab('Rafael', x.faz, null, null, null, null, false, x.trecho);
      if not coalesce((r ->> 'ok')::boolean, false)
         or r ->> 'item' is distinct from 'Quem faz o quê: Rafael ' || public._agenda_etiqueta_texto(x.etq, x.niv::smallint)
         or not exists (select 1 from public.agenda_rascunho a
                         where a.autor = pg_temp.adm() and a.estado = 'aberto' and a.tipo = 'habilidade'
                           and a.dados ->> 'o_que_faz' = x.faz and a.dados ->> 'etiqueta' = x.etq and (a.dados ->> 'nivel')::int = x.niv
                           and a.chave = format('hab:%s:%s', pg_temp.pessoa('Rafael'), case when x.etq in ('instala', 'ajudante') then 'instala' else x.etq end)) then
        v_ruim := v_ruim || format(' [%s → %s]', x.faz, coalesce(r ->> 'item', r ->> 'texto'));
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'C1f os 14 o_que_faz: a etiqueta e o nível da §3.2 (instala 1–3, ajudante 1–3, comissiona 0–3, altura 0–3), a chave (instala e ajudante juntas) e a releitura "Rafael <o texto da etiqueta>"',
      v_ruim = '', nullif(v_ruim, ''));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- a frase direto (IMMUTABLE), as formas que a carteira não mostrou acima
  v_res := pg_temp.ok(v_res, 'C1g _agenda_habilidade_frase: "Roberto instala sozinho e ensina"; "pede quem instala sozinho com 220 V ou banco de bateria no último dia"; "pede quem comissiona Victron em todos os dias"; "não pede quem faz diagnóstico"; "fica como eu marquei" sem proposta; forma que não existe = nulo',
    public._agenda_habilidade_frase('{"forma": "pessoa", "nome": "Roberto", "etiqueta": "instala", "nivel": 3}') = 'Roberto instala sozinho e ensina'
    and public._agenda_habilidade_frase('{"forma": "exige", "mascara": 1, "meios": "ultimo"}') = 'pede quem instala sozinho com 220 V ou banco de bateria no último dia'
    and public._agenda_habilidade_frase('{"forma": "exige", "mascara": 2, "meios": "todos"}') = 'pede quem comissiona Victron em todos os dias'
    and public._agenda_habilidade_frase('{"forma": "exige", "mascara": 8, "meios": "nao"}') = 'não pede quem faz diagnóstico'
    and public._agenda_habilidade_frase('{"forma": "confirmar", "propostas": []}') = 'fica como eu marquei'
    and public._agenda_habilidade_frase('{"forma": "outra"}') is null);
  perform pg_temp.gravar(v_res);
end
$c1$;

-- ── C2. A guarda do trecho ──────────────────────────────────────────────────────────────────────────────────────
do $c2$
declare
  v_res jsonb := '[]'::jsonb;
  t     text[] := '{}';
  r     jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C2 a guarda do trecho', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    for r in select pg_temp.hab('João', 'instala_sozinho', null, null, null, null, false, 'o João é bom')
             union all select pg_temp.hab('João', 'quase_instala', null, null, null, null, false, 'o João é quase')
             union all select pg_temp.hab(null, null, 'Lenine', 'altura', 'todos', null, false, 'o Lenine é complicado')
             union all select pg_temp.hab(null, null, 'Lenine', null, null, 'Roberto', false, 'no Lenine quem manda é o João')
             union all select pg_temp.hab(null, null, 'Lenine', null, null, 'ninguém', false, 'no Lenine tanto faz')
    loop
      t := t || format('%s/%s: %s', r ->> 'ok', r ->> 'motivo', r ->> 'pergunta');
    end loop;
    v_res := pg_temp.ok(v_res, 'C2a o que não está nas palavras do dono volta como pergunta, nada no rascunho: "o João é bom" (instala sozinho), "o João é quase" (quase instala), "o Lenine é complicado" (o teto), o Roberto que ele não disse, o "ninguém" sem dizer',
      t = array['false/fora_do_trecho: Não achei no que você disse o que João faz; me diga de novo.',
                'false/fora_do_trecho: Não achei no que você disse o que João faz; me diga de novo.',
                'false/fora_do_trecho: Não achei no que você disse o que Lenine pede; me diga de novo.',
                'false/fora_do_trecho: Não achei "Roberto" no que você disse; me diga de novo.',
                'false/fora_do_trecho: Não achei no que você disse que o serviço fica sem responsável fixo; me diga de novo.']
      and pg_temp.abertos() = 0,
      array_to_string(t, ' | '));
    t := '{}';
    t := t || (pg_temp.hab('João', 'quase_instala', null, null, null, null, false, 'o João já quase instala sozinho') ->> 'item');
    t := t || (pg_temp.hab('João', 'novo', null, null, null, null, false, 'o João começou agora, nunca deixa ele sozinho') ->> 'item');
    t := t || (pg_temp.hab(null, null, 'Lenine', 'energizado', 'ultimo', null, false, 'no último dia do Lenine mexe com 220') ->> 'item');
    t := t || (pg_temp.hab(null, null, 'Lenine', 'comissionamento', 'ultimo', null, false, 'no fim tem que configurar o Victron') ->> 'item');
    t := t || (pg_temp.hab(null, null, 'Lenine', 'diagnostico', 'todos', null, false, 'no Lenine tem que achar o defeito') ->> 'item');
    t := t || (pg_temp.hab(null, null, 'Lenine', null, null, 'nenhum', false, 'no Lenine não tem responsável fixo') ->> 'item');
    v_res := pg_temp.ok(v_res, 'C2b as palavras de cada coisa valem: "quase instala" (as de instala), "começou" (o novo), "220" (energizado), "configurar" (comissionamento), "defeito" (diagnóstico), "não tem responsável" ("nenhum")',
      t = array['Quem faz o quê: João é ajudante e já quase instala sozinho', 'Quem faz o quê: João é novo: nunca vai sozinho',
                'Lenine (OS-00074): pede quem instala sozinho com 220 V ou banco de bateria no último dia',
                'Lenine (OS-00074): pede quem comissiona Victron no último dia',
                'Lenine (OS-00074): pede quem faz diagnóstico em todos os dias', 'Lenine (OS-00074): fica sem responsável fixo'],
      array_to_string(t, ' | '));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c2$;

-- ── C3. Quem, qual e uma coisa por vez ─────────────────────────────────────────────────────────────────────────────
do $c3$
declare
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
  t     text[] := '{}';
  v_q   uuid;
  v_dup uuid;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C3 quem, qual e uma coisa por vez', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    -- um 2º Roberto na equipe (o dono o declarou): o nome fica ambíguo
    insert into public.payees (name, kind, active, created_at, updated_at)
    values ('Roberto Lima', 'prestador', true, timestamptz '2026-10-01 08:00-03', timestamptz '2026-10-01 08:00-03') returning id into v_dup;
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em, dias_semana)
    values (v_dup, null, null, 'disponivel', 'dono', 'você disse (teste da 7c P4)',
            timestamptz '2026-11-04 08:00-03', '{1,2,3,4,5}');
    r := pg_temp.hab('Roberto', 'instala_sozinho', null, null, null, null, false, 'o Roberto instala sozinho');
    v_res := pg_temp.ok(v_res, 'C3a a pessoa ambígua: a pergunta com as opções (os nomes, nunca o id), nada no rascunho',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'pessoa_ambiguo' and r ->> 'pergunta' like 'Qual Roberto: %'
      and jsonb_array_length(r -> 'opcoes') = 2 and r -> 'opcoes' ? 'Roberto Lima' and pg_temp.abertos() = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    for r in select pg_temp.hab('Vinicius', 'ajudante', null, null, null, null, false, 'o Vinicius é ajudante')
             union all select pg_temp.hab(null, null, 'Zéfiro', 'altura', 'todos', null, false, 'o Zéfiro pede alguém no teto')
             union all select pg_temp.hab(null, null, null, null, null, null, true, 'está certo')
             union all select pg_temp.hab('eu', 'ajudante', null, null, null, null, false, 'eu sou ajudante')
             union all select pg_temp.hab(null, null, 'Lenine', null, null, 'eu', false, 'no Lenine o responsável sou eu')
             union all select pg_temp.hab('Roberto', 'instala_sozinho', null, null, null, null, false, '   ')
    loop
      t := t || format('%s/%s', r ->> 'ok', r ->> 'motivo');
    end loop;
    r := pg_temp.hab('Vinicius', 'ajudante', null, null, null, null, false, 'o Vinicius é ajudante');
    v_res := pg_temp.ok(v_res, 'C3b não está na equipe ("Não conheço ninguém chamado Vinicius na equipe."), a OS fora da carteira, o confirmar sem pergunta ("Não tenho nada de quem faz o quê esperando você."), o dono ajudante, o dono responsável fixo, o trecho vazio: a pergunta, nada no rascunho',
      t = array['false/pessoa_nao_achei', 'false/os_nao_achei', 'false/nada_esperando', 'false/dono_instala', 'false/dono_responsavel', 'false/sem_trecho']
      and r ->> 'pergunta' = 'Não conheço ninguém chamado Vinicius na equipe.'
      and pg_temp.hab(null, null, null, null, null, null, true, 'está certo') ->> 'pergunta' = 'Não tenho nada de quem faz o quê esperando você.'
      and pg_temp.hab('eu', 'ajudante', null, null, null, null, false, 'eu sou ajudante') ->> 'pergunta'
          = 'Você conta sempre como quem instala sozinho: de você eu só anoto se comissiona e se sobe no teto.'
      and pg_temp.hab(null, null, 'Lenine', null, null, 'eu', false, 'no Lenine o responsável sou eu') ->> 'pergunta'
          = 'O responsável fixo é alguém da equipe: quando você vai, já conta como responsável. Para acompanhar o serviço o tempo todo, me diga "eu fico o tempo todo".'
      and pg_temp.hab('Roberto', 'instala_sozinho', null, null, null, null, false, '') ->> 'pergunta' = 'Me diga com as suas palavras quem faz o quê.'
      and pg_temp.abertos() = 0,
      array_to_string(t, ' | '));
    -- o confirmar com a pergunta não mostrada, e com a pergunta mostrada sem proposta viva
    v_q := pg_temp.pergunta(false);
    t := array[pg_temp.hab(null, null, null, null, null, null, true, 'está certo') ->> 'motivo'];
    update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = timestamptz '2026-11-03 17:30-03', mostrada_via = 'fechamento' where id = v_q;
    update public.agenda_etiquetas set estado = 'vale', vale_desde = timestamptz '2026-11-04 10:00-03' where pergunta_id = v_q;
    t := t || (pg_temp.hab(null, null, null, null, null, null, true, 'está certo') ->> 'motivo');
    v_res := pg_temp.ok(v_res, 'C3c o confirmar: com a pergunta aberta mas nunca mostrada, e com a mostrada sem proposta viva, "Não tenho nada de quem faz o quê esperando você."',
      t = array['nada_esperando', 'nada_esperando'] and pg_temp.abertos() = 0, array_to_string(t, ' | '));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- uma forma por vez, os valores das listas e o canal: 22023, nada chamado
  t := array[
    pg_temp.erro_hab('whatsapp', 'Roberto', 'instala_sozinho', 'Lenine', 'altura', 'todos', null, false),
    pg_temp.erro_hab('whatsapp', 'Roberto', null, null, null, null, null, false),
    pg_temp.erro_hab('whatsapp', 'Roberto', 'instala_sozinho', 'Lenine', null, null, null, false),
    pg_temp.erro_hab('whatsapp', null, null, 'Lenine', 'altura', null, null, false),
    pg_temp.erro_hab('whatsapp', null, null, 'Lenine', null, null, null, false),
    pg_temp.erro_hab('whatsapp', null, null, null, null, null, null, false),
    pg_temp.erro_hab('whatsapp', null, null, 'Lenine', null, null, null, true),
    pg_temp.erro_hab('whatsapp', null, null, null, null, null, 'Roberto', false)];
  v_res := pg_temp.ok(v_res, 'C3d uma coisa por vez: duas formas, a pessoa sem o que faz, a pessoa com a OS, a exigência sem os meios, a OS sozinha, nada, o confirmar com a OS e o responsável sem a OS = 22023 "Diga uma coisa por vez: o que a pessoa faz, o que a OS pede, quem é o responsável ou que está certo."',
    (select bool_and(x = '22023: Diga uma coisa por vez: o que a pessoa faz, o que a OS pede, quem é o responsável ou que está certo.') from unnest(t) x),
    array_to_string(t, ' | '));
  t := array[
    pg_temp.erro_hab('sms', 'Roberto', 'instala_sozinho', null, null, null, null, false),
    pg_temp.erro_hab('whatsapp', 'Roberto', 'pilota_barco', null, null, null, null, false),
    pg_temp.erro_hab('whatsapp', null, null, 'Lenine', 'solda', 'todos', null, false),
    pg_temp.erro_hab('whatsapp', null, null, 'Lenine', 'altura', 'metade', null, false)];
  v_res := pg_temp.ok(v_res, 'C3e o canal e os valores fora da lista (o_que_faz, exige, meios) = 22023, com a lista na mensagem',
    (select bool_and(x like '22023: agenda_rascunho_habilidade: %') from unnest(t) x)
    and t[2] like '%instala_com_alguem, instala_sozinho, instala_e_ensina, novo, ajudante, quase_instala%'
    and t[3] like '%(energizado, comissionamento, altura ou diagnostico)' and t[4] like '%(todos, ultimo ou nao)',
    array_to_string(t, ' | '));
  -- quem chama: a técnica logada não mexe; o admin logado (o painel) anota; anon não chama
  begin
    t := array[
      pg_temp.como('authenticated', 'c7c00000-0000-4000-8000-0000000ec004',
        'select public.agenda_rascunho_habilidade(null, ''painel'', ''Roberto'', ''instala_sozinho'', null, null, null, null, false, ''o Roberto instala sozinho'', date ''2026-11-04'')::text'),
      pg_temp.como('authenticated', pg_temp.adm(),
        'select (public.agenda_rascunho_habilidade(null, ''painel'', ''Roberto'', ''instala_sozinho'', null, null, null, null, false, ''o Roberto instala sozinho'', date ''2026-11-04'') ->> ''item'')'),
      pg_temp.como('anon', null,
        'select public.agenda_rascunho_habilidade(null, ''painel'', ''Roberto'', ''instala_sozinho'', null, null, null, null, false, ''o Roberto instala sozinho'', date ''2026-11-04'')::text')];
    v_res := pg_temp.ok(v_res, 'C3f quem chama: a técnica logada = 42501 "Só o administrador mexe na agenda."; o admin logado (o painel, authenticated) anota; anon não chama (42501)',
      t[1] = 'erro 42501: Só o administrador mexe na agenda.' and t[2] = 'Quem faz o quê: Roberto instala sozinho' and t[3] like 'erro 42501:%',
      array_to_string(t, ' | '));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c3$;

-- ── C4. O *grava* ───────────────────────────────────────────────────────────────────────────────────────────────
do $c4$
declare
  v_res jsonb := '[]'::jsonb;
  c_t   constant timestamptz := timestamptz '2026-11-04 16:20-03';
  r     jsonb;
  e     record;
  v_q   uuid;
  v_len uuid := pg_temp.os('OS-00074');
  v_h   jsonb;
  t     text;
  t2    text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C4 o *grava*', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- (a) sem pergunta: a etiqueta do dono vale, e agenda_habilidades a lê
  begin
    perform pg_temp.hab('Roberto', 'instala_sozinho', null, null, null, null, false, 'o Roberto instala sozinho');
    r := pg_temp.grava();
    select * into e from public.agenda_etiquetas x where x.payee_id = pg_temp.pessoa('Roberto') and x.estado = 'vale' and x.etiqueta = 'instala';
    select h.texto, h.fonte into t, v_h from public.agenda_habilidades(date '2026-11-04', array[pg_temp.pessoa('Roberto')]) h;
    v_res := pg_temp.ok(v_res, 'C4a (a) o *grava*: "Gravado. Agora:\n• Roberto: instala sozinho."; a etiqueta do dono vale (instala 2, origem dono, "você disse", o trecho, vale_desde e criado_em = a hora do *grava*, criado_por = o dono); agenda_habilidades: "Roberto: instala sozinho (você disse)." (fonte dono)',
      r ->> 'texto' = E'Gravado. Agora:\n• Roberto: instala sozinho.' and (r ->> 'gravados')::int = 1
      and e.nivel = 2 and e.origem = 'dono' and e.motivo = 'você disse' and e.trecho = 'o Roberto instala sozinho'
      and e.vale_desde = c_t and e.criado_em = c_t and e.criado_por = pg_temp.adm() and e.pergunta_id is null
      and t = 'Roberto: instala sozinho (você disse).' and v_h ->> 'instala' = 'dono' and pg_temp.abertos() = 0,
      concat_ws(' | ', r ->> 'texto', e.nivel, e.origem, e.vale_desde, t, v_h));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- (a) a exclusividade: o João ajudante 2 do gestor e o Roberto altura 0 do dono (as do teste M/V), e o dono diz o contrário
  begin
    insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, vale_desde, criado_em)
    values (pg_temp.pessoa('João'), 'ajudante', 2, 'gestor', 'vale', 'entrou em 29/09, 15 diárias', timestamptz '2026-10-30 18:00-03', timestamptz '2026-10-29 16:10-03'),
           (pg_temp.pessoa('Roberto'), 'altura', 0, 'dono', 'vale', 'você disse', timestamptz '2026-10-30 10:00-03', timestamptz '2026-10-30 10:00-03');
    perform pg_temp.hab('João', 'instala_sozinho', null, null, null, null, false, 'o João agora instala sozinho');
    perform pg_temp.hab('Roberto', 'sobe_no_teto', null, null, null, null, false, 'o Roberto já sobe no teto');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'C4b (a) a exclusividade: a viva de ajudante (do gestor) vira substituída quando o dono diz que instala, e a de altura 0 (do dono) quando ele diz que sobe; uma viva por etiqueta',
      r ->> 'texto' = E'Gravado. Agora:\n• João: instala sozinho.\n• Roberto: sobe no teto.'
      and pg_temp.etq('João') = 'instala 2 dono vale' and pg_temp.etq('Roberto') = 'altura 2 dono vale'
      and (select count(*) from public.agenda_etiquetas x where x.estado = 'substituida' and x.substituida_em = c_t
            and x.payee_id in (pg_temp.pessoa('João'), pg_temp.pessoa('Roberto'))) = 2,
      concat_ws(' | ', r ->> 'texto', pg_temp.etq('João'), pg_temp.etq('Roberto')));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- (a) com a pergunta aberta e mostrada: a corrigida substituída, o resto vale, a pergunta fecha
  begin
    v_q := pg_temp.pergunta(true);
    perform pg_temp.hab('João', 'instala_sozinho', null, null, null, null, false, 'o João instala sozinho');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'C4c com a pergunta habilidade:equipe aberta e mostrada: "• João: instala sozinho. O resto ficou como eu marquei: Roberto instala sozinho; Bruno é novo."; a proposta do João substituída, as do Roberto e do Bruno valem (a hora do *grava*), a pergunta fecha ("você corrigiu; o resto ficou como eu marquei")',
      r ->> 'texto' = E'Gravado. Agora:\n• João: instala sozinho. O resto ficou como eu marquei: Roberto instala sozinho; Bruno é novo.'
      and (select string_agg(format('%s %s %s', public._agenda_nome_curto(py.name), x.etiqueta, x.estado), '; ' order by py.name)
             from public.agenda_etiquetas x join public.payees py on py.id = x.payee_id where x.pergunta_id = v_q)
          = 'Bruno ajudante vale; João ajudante substituida; Roberto instala vale'
      and (select bool_and(x.vale_desde = c_t) from public.agenda_etiquetas x where x.pergunta_id = v_q and x.estado = 'vale')
      and (select estado || ': ' || resolvida_motivo from public.agenda_perguntas where id = v_q) = 'resolvida: você corrigiu; o resto ficou como eu marquei'
      and pg_temp.etq('João') = 'instala 2 dono vale',
      concat_ws(' | ', r ->> 'texto', (select estado || ': ' || coalesce(resolvida_motivo, '') from public.agenda_perguntas where id = v_q)));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- 2 correções e o que a OS pede no mesmo lote: a pergunta fecha na 1ª, e o resto não cita quem o lote corrigiu
  begin
    v_q := pg_temp.pergunta(true);
    perform pg_temp.hab('João', 'instala_sozinho', null, null, null, null, false, 'o João instala sozinho');
    perform pg_temp.hab('Bruno', 'instala_sozinho', null, null, null, null, false, 'o Bruno também instala sozinho');
    perform pg_temp.hab(null, null, 'Lenine', 'altura', 'todos', null, false, 'o Lenine pede alguém no teto em todos os dias');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'C4d duas correções no mesmo lote (e o que a OS pede): "• João: instala sozinho. O resto ficou como eu marquei: Roberto instala sozinho." e "• Bruno: instala sozinho." (a do Bruno, corrigida no lote, não fica como marquei)',
      r ->> 'texto' = E'Gravado. Agora:\n• João: instala sozinho. O resto ficou como eu marquei: Roberto instala sozinho.\n• Bruno: instala sozinho.\n• Lenine: pede quem sobe no teto em todos os dias.'
      and (select string_agg(format('%s %s', public._agenda_nome_curto(py.name), x.estado), '; ' order by py.name)
             from public.agenda_etiquetas x join public.payees py on py.id = x.payee_id where x.pergunta_id = v_q)
          = 'Bruno substituida; João substituida; Roberto vale'
      and pg_temp.etq('Bruno') = 'instala 2 dono vale',
      r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- a pergunta nunca mostrada: a correção grava, a pergunta e as propostas ficam como estavam
  begin
    v_q := pg_temp.pergunta(false);
    perform pg_temp.hab('João', 'instala_sozinho', null, null, null, null, false, 'o João instala sozinho');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'C4e a pergunta nunca mostrada não fecha: só a correção grava ("• João: instala sozinho."); as propostas do Roberto e do Bruno continuam propostas',
      r ->> 'texto' = E'Gravado. Agora:\n• João: instala sozinho.'
      and (select estado from public.agenda_perguntas where id = v_q) = 'aberta'
      and (select string_agg(format('%s %s', public._agenda_nome_curto(py.name), x.estado), '; ' order by py.name)
             from public.agenda_etiquetas x join public.payees py on py.id = x.payee_id where x.pergunta_id = v_q)
          = 'Bruno proposta; João substituida; Roberto proposta',
      r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- (b) o que a OS pede: exigencias_ditas, o trecho, o histórico; os_exigencias passa a ler
  begin
    perform pg_temp.hab(null, null, 'Lenine', 'altura', 'todos', null, false, 'o Lenine pede alguém no teto em todos os dias');
    r := pg_temp.grava();
    select jsonb_build_object('ditas', p.exigencias_ditas, 'trecho', p.exigencias_trecho, 'h', p.historico -> -1) into v_h
      from public.os_planejamento p where p.service_order_id = v_len;
    t := public.os_exigencias(v_len, date '2026-11-04') ->> 'todos';
    perform pg_temp.hab(null, null, 'Lenine', 'altura', 'nao', null, false, 'o Lenine não precisa de ninguém subindo no teto');
    -- (o *grava* numa instrução e as leituras noutra: a leitura STABLE da mesma instrução não veria a escrita do *grava*)
    t2 := pg_temp.grava() ->> 'texto';
    t2 := t2 || ' / ' || (public.os_exigencias(v_len, date '2026-11-04') ->> 'todos')
          || ' / ' || (select p.exigencias_ditas::text from public.os_planejamento p where p.service_order_id = v_len);
    v_res := pg_temp.ok(v_res, 'C4f (b) o que a OS pede: "• Lenine: pede quem sobe no teto em todos os dias."; exigencias_ditas {"altura": "todos"}, o trecho e o histórico {em, autor, trecho, antes, depois}; os_exigencias passa a pedir o teto em todos (bit 4); "nao" tira',
      r ->> 'texto' = E'Gravado. Agora:\n• Lenine: pede quem sobe no teto em todos os dias.'
      and v_h -> 'ditas' = '{"altura": "todos"}' and v_h ->> 'trecho' = 'o Lenine pede alguém no teto em todos os dias'
      and v_h -> 'h' -> 'antes' = '{"exigencias_ditas": {}}' and v_h -> 'h' -> 'depois' = '{"exigencias_ditas": {"altura": "todos"}}'
      and v_h -> 'h' ->> 'autor' = pg_temp.adm()::text and v_h -> 'h' ->> 'em' = '2026-11-04'
      and t::int & 4 = 4
      and t2 = E'Gravado. Agora:\n• Lenine: não pede quem sobe no teto. / 0 / {"altura": "nao"}',
      concat_ws(' | ', r ->> 'texto', v_h, t, t2));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- (c) o responsável: o dono disse; _agenda_lider_da_os o lê; "ninguém" limpa
  begin
    perform pg_temp.hab(null, null, 'Lenine', null, null, 'Roberto', false, 'no Lenine o responsável é o Roberto');
    r := pg_temp.grava();
    select jsonb_build_object('lider', p.lider_payee_id, 'em', p.lider_em, 'trecho', p.lider_trecho, 'h', p.historico -> -1) into v_h
      from public.os_planejamento p where p.service_order_id = v_len;
    t := public._agenda_lider_da_os(v_len, date '2026-11-04')::text;
    perform pg_temp.hab(null, null, 'Lenine', null, null, 'ninguém', false, 'o Lenine fica sem responsável fixo');
    t2 := pg_temp.grava() ->> 'texto';
    t2 := t2
          || ' / ' || coalesce((select (p.lider_payee_id is null and p.lider_em is null and p.lider_trecho is null)::text
                                  from public.os_planejamento p where p.service_order_id = v_len), '-')
          || ' / ' || coalesce(public._agenda_lider_da_os(v_len, date '2026-11-04') ->> 'fonte', '-');
    v_res := pg_temp.ok(v_res, 'C4g (c) o responsável: "• Lenine: o responsável é Roberto."; lider_payee_id, lider_em = a hora do *grava*, lider_trecho e o histórico; _agenda_lider_da_os: Roberto (você disse), fonte dono; "ninguém": "• Lenine: fica sem responsável fixo." e os três nulos',
      r ->> 'texto' = E'Gravado. Agora:\n• Lenine: o responsável é Roberto.'
      and v_h ->> 'lider' = pg_temp.pessoa('Roberto')::text and (v_h ->> 'em')::timestamptz = c_t
      and v_h ->> 'trecho' = 'no Lenine o responsável é o Roberto'
      and v_h -> 'h' -> 'depois' = jsonb_build_object('lider_payee_id', pg_temp.pessoa('Roberto'))
      and t::jsonb ->> 'fonte' = 'dono' and t::jsonb ->> 'texto' = 'Roberto (você disse)'
      and t2 like E'Gravado. Agora:\n• Lenine: fica sem responsável fixo. / true / %' and t2 not like '%/ dono',
      concat_ws(' | ', r ->> 'texto', v_h, t, t2));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- (d) o confirmar: as propostas valem, a pergunta fecha
  begin
    v_q := pg_temp.pergunta(true);
    perform pg_temp.hab(null, null, null, null, null, null, true, 'está certo o que você marcou');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'C4h (d) o confirmar: "• Quem faz o quê: ficou como eu marquei."; as 3 propostas valem (a hora do *grava*) e a pergunta fecha ("você confirmou")',
      r ->> 'texto' = E'Gravado. Agora:\n• Quem faz o quê: ficou como eu marquei.'
      and (select count(*) from public.agenda_etiquetas x where x.pergunta_id = v_q and x.estado = 'vale' and x.vale_desde = c_t) = 3
      and (select estado || ': ' || resolvida_motivo from public.agenda_perguntas where id = v_q) = 'resolvida: você confirmou',
      r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- (d) a pergunta que o gestor refez entre a releitura e o *grava*: o lote não grava
  begin
    v_q := pg_temp.pergunta(true);
    perform pg_temp.hab(null, null, null, null, null, null, true, 'está certo');
    perform pg_temp.hab('Rafael', 'sobe_no_teto', null, null, null, null, false, 'o Rafael sobe no teto');
    update public.agenda_perguntas set estado = 'descartada', resolvida_motivo = 'a proposta mudou: perguntei de novo' where id = v_q;
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'C4i a pergunta refeita (descartada) entre a releitura e o *grava*: "Não gravei nada. A agenda mudou desde a releitura: o que eu marquei de quem faz o quê mudou. Me peça de novo."; nada muda (as propostas e o rascunho ficam)',
      not (r ->> 'ok')::boolean
      and r ->> 'texto' = 'Não gravei nada. A agenda mudou desde a releitura: o que eu marquei de quem faz o quê mudou. Me peça de novo.'
      and (select count(*) from public.agenda_etiquetas x where x.pergunta_id = v_q and x.estado = 'proposta') = 3
      and pg_temp.etq('Rafael') = '-' and pg_temp.abertos() = 2,
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- (d) e a correção no mesmo lote, nas duas ordens; e em qualquer modo da agenda (a automática em teste)
  begin
    v_q := pg_temp.pergunta(true);
    update public.agenda_config set modo_proposta = 'sombra' where id;
    perform pg_temp.hab(null, null, null, null, null, null, true, 'está certo, mas');
    perform pg_temp.hab('João', 'instala_sozinho', null, null, null, null, false, 'o João instala sozinho');
    r := pg_temp.grava();
    t := r ->> 'texto';
    t2 := pg_temp.etq('João') || ' / ' || (select estado || ': ' || resolvida_motivo from public.agenda_perguntas where id = v_q);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    v_q := pg_temp.pergunta(true);
    perform pg_temp.hab('João', 'instala_sozinho', null, null, null, null, false, 'o João instala sozinho');
    perform pg_temp.hab(null, null, null, null, null, null, true, 'o resto está certo');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'C4j o confirmar e a correção no mesmo lote, nas duas ordens: o João fica com o que o dono disse e o resto vale; a agenda automática em teste não segura (grava em qualquer modo, como o fornecedor)',
      t = E'Gravado. Agora:\n• Quem faz o quê: ficou como eu marquei.\n• João: instala sozinho.'
      and t2 = 'instala 2 dono vale / resolvida: você confirmou'
      and r ->> 'texto' = E'Gravado. Agora:\n• João: instala sozinho. O resto ficou como eu marquei: Roberto instala sozinho; Bruno é novo.\n• Quem faz o quê: ficou como eu marquei.'
      and pg_temp.etq('João') = 'instala 2 dono vale' and pg_temp.etq('Roberto') = 'instala 2 gestor vale',
      concat_ws(' | ', t, t2, r ->> 'texto'));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c4$;

-- ── C5. A agenda desligada não anota ────────────────────────────────────────────────────────────────────────────
do $c5$
declare
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C5 a agenda desligada', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    update public.agenda_config set modo_leitura = 'desligado' where id;
    r := pg_temp.hab('Roberto', 'instala_sozinho', null, null, null, null, false, 'o Roberto instala sozinho');
    v_res := pg_temp.ok(v_res, 'C5 com modo_leitura desligado: "A agenda de produção está desligada agora: não anotei nada.", nada no rascunho',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'desligada'
      and r ->> 'pergunta' = 'A agenda de produção está desligada agora: não anotei nada.' and pg_temp.abertos() = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c5$;

-- ── C6. As cópias e os tipos de antes ───────────────────────────────────────────────────────────────────────────
do $c6$
declare
  v_res  jsonb := '[]'::jsonb;
  v_orig text := coalesce(current_setting('agenda_teste.mig_disponibilidade_fase7b', true), '');
  v_mig  text := coalesce(current_setting('agenda_teste.mig_conversa_fase7c', true), '');
  r      record;
  v_novo text;
  v_n    int;
  v_dif  text := '';
  d      jsonb;
  t1     text;
  t2     text;
begin
  if v_orig = '' or v_mig = '' then
    insert into _resultado values ('C6 as cópias e os tipos de antes', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  for r in select * from (values
      ('_agenda_rascunho_frase', 'public._agenda_rascunho_frase(text, jsonb)'),
      ('agenda_rascunho_gravar', 'public.agenda_rascunho_gravar(uuid, date)')) t(nome, sig)
  loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = r.sig::regprocedure;
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7c: fim', 'g');
    if pg_temp.corpo(v_orig, r.nome) = '' or pg_temp.sem_7c(v_novo) <> pg_temp.corpo(v_orig, r.nome)
       or pg_temp.sem_7c(pg_temp.corpo(v_mig, r.nome)) <> pg_temp.corpo(v_orig, r.nome)
       -- FASE 7c: (7c P8, 20261102100550) o P8 recria as duas (+ o bloco do tipo etapa): na viva, 2 blocos "-- FASE 7c:"; tirados, a origem
       or v_n <> 1 + (case when exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'modo_tarefas'
                     and not a.attisdropped) then 1 else 0 end) then
       -- FASE 7c: fim
      v_dif := v_dif || format(' [%s: %s blocos; vivo sem eles %s × fonte %s letras]', r.nome, v_n, length(pg_temp.sem_7c(v_novo)),
                               length(pg_temp.corpo(v_orig, r.nome)));
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'C6a as cópias: tirado o bloco "-- FASE 7c:" (1 em cada), o corpo vivo e o da migration de _agenda_rascunho_frase e de agenda_rascunho_gravar são o de 20261101100100, byte a byte',
    v_dif = '', nullif(v_dif, ''));

  -- os de antes como pg_temp (a régua do byte a byte)
  execute replace(pg_temp.inteira(v_orig, '_agenda_rascunho_frase'),
                  'create or replace function public._agenda_rascunho_frase(', 'create function pg_temp.frase_antes(');
  execute replace(pg_temp.inteira(v_orig, 'agenda_rascunho_gravar'),
                  'create or replace function public.agenda_rascunho_gravar(', 'create function pg_temp.gravar_antes(');
  v_dif := '';
  for d in select x from jsonb_array_elements(jsonb_build_array(
      jsonb_build_object('t', 'planejar', 'd', '{"dias": 2, "equipe": [{"nome": "Roberto", "turnos": "dia"}], "dono": "abre_e_fecha", "precisa_ate": "2026-11-20"}'::jsonb),
      jsonb_build_object('t', 'planejar', 'd', '{"dupla": "inicio", "dupla_meios": 2, "dupla_aviso": "Hoje só Alex está na equipe."}'::jsonb),
      jsonb_build_object('t', 'material', 'd', '{"acao": "a_caminho", "previsao_ate": "2026-11-10", "hoje": "2026-11-04", "fornecedor_txt": "Premel"}'::jsonb),
      jsonb_build_object('t', 'disponibilidade', 'd', '{"dito": "vem", "padrao": true, "dias_semana": [1, 2, 3, 4, 5], "eh_dono": false}'::jsonb),
      jsonb_build_object('t', 'disponibilidade', 'd', '{"semana": "2026-11-16", "dias_semana": [1, 3], "eh_dono": true}'::jsonb),
      jsonb_build_object('t', 'disponibilidade', 'd', '{"datas": ["2026-11-11", "2026-11-14"], "eh_dono": false, "fora_da_equipe": true, "nome": "Mateus"}'::jsonb),
      jsonb_build_object('t', 'fornecedor', 'd', '{"frase_pronta": "no balcão (você disse)"}'::jsonb),
      jsonb_build_object('t', 'aviso', 'd', '{"frase_pronta": "não é de serviço"}'::jsonb),
      jsonb_build_object('t', 'marcar', 'd', '{"frase_pronta": "marco o Lenine qui 05/11"}'::jsonb))) x
  loop
    if public._agenda_rascunho_frase(d ->> 't', d -> 'd') is distinct from pg_temp.frase_antes(d ->> 't', d -> 'd') then
      v_dif := v_dif || format(' [%s: %s × %s]', d ->> 't', public._agenda_rascunho_frase(d ->> 't', d -> 'd'), pg_temp.frase_antes(d ->> 't', d -> 'd'));
    end if;
  end loop;
  begin
    perform public._agenda_rascunho_frase('nao_existe', '{}');
    v_dif := v_dif || ' [o tipo que não existe passou]';
  exception when sqlstate '22023' then
    if sqlerrm <> '_agenda_rascunho_frase: tipo "nao_existe" não existe' then v_dif := v_dif || ' [' || sqlerrm || ']'; end if;
  end;
  v_res := pg_temp.ok(v_res, 'C6b a frase dos tipos de antes (planejar, material, disponibilidade com a semana, as datas e quem não está na equipe, fornecedor, aviso, os pedidos) sai byte a byte a de 20261101100100; o tipo que não existe continua 22023',
    v_dif = '', nullif(v_dif, ''));

  -- o *grava* de um lote de antes (o planejar e a disponibilidade): o mesmo "Gravado. Agora:" e o mesmo efeito
  if not pg_temp.carregada() then
    v_res := pg_temp.ok(v_res, 'C6c o *grava* de um lote de antes', true, 'PULADO: sem as fixtures (rode pela bancada)');
  else
    begin
      perform public.agenda_rascunho_planejar(pg_temp.adm(), 'whatsapp', 'Lenine', '{"dias": 2}', 'o Lenine são 2 dias', date '2026-11-04');
      perform public.agenda_rascunho_disponibilidade(pg_temp.adm(), 'whatsapp', 'Rafael', 'nao_vem', 'sexta', false, 'o Rafael não vem sexta',
                                                     date '2026-11-04');
      t1 := pg_temp.grava() ->> 'texto';
      t1 := t1 || ' / ' || (select p.dias::text from public.os_planejamento p where p.service_order_id = pg_temp.os('OS-00074'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      perform public.agenda_rascunho_planejar(pg_temp.adm(), 'whatsapp', 'Lenine', '{"dias": 2}', 'o Lenine são 2 dias', date '2026-11-04');
      perform public.agenda_rascunho_disponibilidade(pg_temp.adm(), 'whatsapp', 'Rafael', 'nao_vem', 'sexta', false, 'o Rafael não vem sexta',
                                                     date '2026-11-04');
      perform set_config('agenda.agora', '2026-11-04 16:20-03', true);
      t2 := pg_temp.gravar_antes(pg_temp.adm(), date '2026-11-04') ->> 'texto';
      perform set_config('agenda.agora', '', true);
      t2 := t2 || ' / ' || (select p.dias::text from public.os_planejamento p where p.service_order_id = pg_temp.os('OS-00074'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'C6c o *grava* de um lote de antes (o planejar do Lenine e o "não vem" do Rafael): o "Gravado. Agora:" e os dias gravados saem byte a byte os de 20261101100100',
      t1 = t2 and t1 like E'Gravado. Agora:\n• %' and t1 like '% / 2.0', concat_ws(' || ', t1, t2));
  end if;
  perform pg_temp.gravar(v_res);
end
$c6$;

select teste, ok, detalhe from _resultado order by teste;

rollback;

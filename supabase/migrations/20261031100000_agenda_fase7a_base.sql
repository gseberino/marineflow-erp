-- Agenda de Produção, Fase 7, etapa 7a ("ele marca sozinho"), pacote P1: a base — os parâmetros e os interruptores do gestor
-- da agenda, as colunas novas (a fonte 'orcamento' da estimativa, a marca de dupla, o "compre até" gravado, o prazo da pergunta,
-- a medida contra a estimativa), as listas fechadas ampliadas, o diário do gestor e as funções da base (o portão, o modo, o dia
-- avisado, a fonte da duração da alocação, o gravador do diário, o validador de regex e o ampliador de lista).
-- Spec: scratchpad agenda-pesquisa/spec-fase7a.md (§R, §3.1, §4); nomes: fase7-registro.md §1; respostas do dono: fase7-padroes.md
-- (AG7-01 ligar direto; AG7-04 uma pessoa; AG7-05 R$ 300; AG7-06 7 dias úteis; AG7-07 1 dia útil e "compre hoje" a menos de 7;
-- AG7-08 sábado só quando precisa; AG7-09 marco e cobro o sinal; AG7-11 quanto falta; AG7-15 prazo às 18:00 depois de mostrada).
-- Depende das Fases 1 a 6 e do lote de correção de 30/10 (20261024160000 .. 20261030100600), todos em produção.
--
-- ═══ DDL — OK NOMEADO ═══ (36 colunas novas em agenda_config — 5 interruptores, a lista de regras e 30 parâmetros — e o DEFAULT
-- dos 5 interruptores; 5 colunas novas em os_planejamento, 1 em agenda_alocacoes, 7 em os_material, 2 em agenda_perguntas e 3 em
-- agenda_medidas_os, todas nulas ou com DEFAULT; 9 listas fechadas ampliadas e a coluna gerada critica com 4 tipos novos; 1 tabela
-- nova, vazia; 8 funções novas e 2 recriadas; 1 gatilho novo; 34 CHECKs novos em agenda_config e 22 nas outras tabelas)
-- NÃO APLICADA. Existe para revisão e espera o OK do dono.
--
-- POR QUE: o gestor da agenda passa a marcar sozinho pela estimativa do orçamento (D7-1) e a cobrar a compra em vez de tirar a
-- OS da agenda (D7-2). Esta migration só cria o lugar de cada coisa e o portão; quem muda comportamento são as próximas
-- (20261031100100 a 100950), sempre atrás do portão _agenda_gestor_regra / _agenda_gestor_modo. Com os interruptores
-- desligados (a linha nasce assim), nada muda para ninguém.
--
-- O QUE MUDA:
--   1. agenda_config: os interruptores modo_marcar_sozinho, modo_vaga_fechamento, modo_encaixe_aprovacao, modo_revisao_diaria e
--      modo_compre_ate (desligado | sombra | ligado; a linha fica 'desligado', o DEFAULT da coluna vira 'sombra', como nas Fases
--      2 a 6; quem os põe em sombra é a migration de dado 20261031100990, com OK nomeado); a lista marcar_regras (as 15 regras
--      do gestor; tirar uma desliga só ela); a palavra *gestor, só propor* (gestor_so_propor/_em); marcar_sozinho_desde (a janela
--      da ficha conta daqui); e 30 parâmetros com o código AG7 de cada pergunta ao dono no comentário. CHECK por nome em cada um.
--   2. os_planejamento: a fonte 'orcamento' (a estimativa do gestor gravada só quando uma pergunta com prazo vence sem resposta)
--      em estimativa_fonte e dias_no_inicio_fonte; a marca de dupla (dupla_dita nao/inicio/fim/todos, dupla_meios, dupla_motivo,
--      dupla_em: uma marca só para 7a e 7b, AG7-04); dp_no_inicio (as diárias estimadas no check-in, para o 7e medir o viés).
--   3. agenda_alocacoes.duracao_fonte (de onde veio a duração: dono, aceita, orcamento ou sugerida; nula na reserva), preenchida
--      pelo gatilho novo agenda_alocacoes_fonte; cancelada_motivo + reestimada.
--   4. os_material: o "compre até" gravado (compre_ate, compre_ate_base, compre_ate_em), a cobrança (cobrado_em, cobrado_vezes),
--      os empurrões (empurrada_vezes) e o defeito (defeito_em).
--   5. agenda_perguntas: o prazo (veto_ate) e a opção que vale sem resposta (opcao_padrao), com veto_padrao_tem_prazo (opção
--      padrão só com prazo) e veto_nao_critica (pergunta crítica nunca tem prazo; o 7f troca esta regra); os 13 tipos do gestor
--      (situacao, estimativa, equipe_cadastro, reavaliar, reestimar, ficha_estimativa, bem_livre, compre_ate, sinal, onda,
--      dia_avisado, dia_prometido, sabado); critica + onda, dia_avisado, dia_prometido e sabado (SET EXPRESSION).
--   6. agenda_acoes.tipo + estimar, reestimar, reparar, gestor, dupla; agenda_vigia_rodadas.rotina + gestor;
--      agenda_equipe_mensagens.recusa_motivo + veto.
--   7. agenda_medidas_os: dias_fonte + orcamento; fator_orcamento (o fator da medida por estimativa: o aprendizado do fator NÃO o
--      lê), dp_no_inicio e dp_reais.
--   8. agenda_gestor_dia (nova): o diário do gestor — um registro por dia com os modos na hora, o "eu marcaria assim" (sombra),
--      os orçamentos que caberiam, as compras da semana e a linha do fechamento. Só leitura TO authenticated (admin/financeiro);
--      escrita só pelo gravador; não se apaga.
--   9. Funções da base: _agenda_regex_valido (o validador único de regex dos CHECKs, 7a–7d), _agenda_dupla_lista_ok (o CHECK
--      de dupla_gatilhos e dupla_notas), _agenda_ampliar_lista (o ampliador único das listas fechadas, 7a–7g), _agenda_gestor_regra
--      (o portão), _agenda_gestor_modo (o modo efetivo), _agenda_dia_avisado (o dia já dito à equipe ou ao cliente), o gatilho
--      _agenda_alocacao_fonte e _agenda_gestor_dia_gravar. Recriada _agenda_perguntas_antes (de 20261026100000): o prazo vai de
--      nulo a um valor uma vez na pergunta aberta; a opção padrão é uma das opções.
--  10. Recriada _agenda_modo_da_pergunta (de 20261030100500): os 13 tipos novos ganham o modo de quem os faz (o lote de 30/10
--      cobra que todo tipo da lista fechada tenha um; sem isto a limpeza da vigia não saberia fechar a pergunta de teste do gestor).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7a_base.sql; registradas em notas-fase77a.md, P1):
--   · _agenda_dupla_lista_ok é nova: CHECK não aceita subconsulta, e os termos do CHECK de dupla_gatilhos/dupla_notas (§4.1 do
--     7b) olham cada elemento da lista (o molde é _agenda_classe_pares_ok, da Fase 6).
--   · gestor_hora_revisao: estritamente depois de hora_do_plano (a revisão da quinta roda depois da publicação) e até
--     cliente_janela_fim, em dois CHECKs (agenda_config_gestor_hora_revisao_check e agenda_config_revisao_depois_do_plano_check):
--     num só, com o nome da coluna, o plano às 18:00 seria recusado por ele antes do CHECK do plano (a ordem é a do nome).
--   · _agenda_gestor_modo com gestor_so_propor: o que está ligado vale sombra; o desligado continua desligado (a palavra não liga
--     a simulação de quem está desligado).
--   · dupla_meios_coerente com coalesce: sem ele, dupla_dita nula com dupla_meios preenchido passaria (nulo = verdadeiro no CHECK).
--   · _agenda_perguntas_antes também confere que a opção padrão é uma das opções (como a recomendação e a escolhida).
--   · _agenda_modo_da_pergunta é recriada aqui (a spec não a lista: ela nasceu no lote de 30/10, depois da spec), com o modo de
--     cada tipo novo; quem a recriar depois copia desta.
--
-- O QUE NÃO MUDA: nenhum comportamento. Nenhum cron, nenhuma tela, nenhuma função de borda, nenhuma mensagem. Os tipos e os
-- motivos de antes continuam nas listas (o ampliador lê a lista viva e só soma); as 8 críticas de antes continuam críticas.
--
-- ORDEM DE LIGAR: depois do lote de correção de 30/10 (em produção); antes de 20261031100100 (P2), que lê as colunas novas.
-- Aplicar sozinha não muda nada para ninguém (os interruptores ficam 'desligado' na linha).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7a_base.sql (begin/rollback; cada CHECK recusa uma linha errada, as listas
-- de antes iguais, o portão e o modo em cada estado, o dia avisado, o gatilho da fonte, o diário não se apaga, RLS e portas). Na
-- bancada: node scripts/bancada-agenda/rodar.mjs --ate 20261031100000
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261031100000_agenda_fase7a_base.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261031100000', 'agenda_fase7a_base');"
--
-- DESFAZER (só a estrutura; nada usa as colunas antes das próximas migrations): recriar _agenda_perguntas_antes com o corpo de
-- 20261026100000 e _agenda_modo_da_pergunta com o de 20261030100500; o resto pode ficar (colunas nulas ou com DEFAULT, tabela vazia, funções sem leitor). Para tirar mesmo:
--   drop trigger if exists agenda_alocacoes_fonte on public.agenda_alocacoes;
--   drop table if exists public.agenda_gestor_dia;
--   (as listas: recriar o CHECK de cada uma com os valores de 20261030100500/20261029100000; só sem linha com valor novo)
--
-- IDEMPOTENTE: add column if not exists, CHECK por nome em do $$, as listas pelo ampliador (soma só o que falta; rodar de novo não
-- recria nada), SET EXPRESSION só quando a expressão ainda não tem 'onda', create table if not exists, create or replace
-- function, drop trigger/policy if exists + create, revoke/grant e comment.

-- ── 0. As funções que os CHECKs e as listas usam ─────────────────────────────────────────────────────────────

-- O validador único de expressão regular dos CHECKs (7a, 7b, 7c e 7d usam este; não existe outro). IMMUTABLE: só compila.
create or replace function public._agenda_regex_valido(p text)
 returns boolean
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
begin
  if p is null then
    return false;
  end if;
  if '' ~ p then
    return true;
  end if;
  return true;
exception when others then
  return false;
end;
$function$;

comment on function public._agenda_regex_valido(text) is
  'Agenda de Produção (Fase 7a, P1): a expressão regular compila no Postgres? (''''~ p não lança). O validador único dos CHECKs de regex de agenda_config: mo_fora_regex e cada expressão de dupla_gatilhos e dupla_notas (7a), e as do 7b, 7c e 7d. Nulo = false.';

-- O CHECK de dupla_gatilhos (p_gatilhos = true) e de dupla_notas (false). Os gatilhos: uma lista não vazia de
-- [motivo, expressão, onde, meios-dias], motivo em banco_cc/bateria_pesada/ca_energizado/icamento sem repetir, a expressão não
-- vazia e compilável casada no início de palavra ('\m(' || expressão || ')'), onde em inicio/fim, meios-dias de 1 a 8. As notas:
-- uma lista de [motivo, expressão], o motivo preenchido e sem repetir, a expressão compilável (lista vazia = sem nota).
-- (CHECK não aceita subconsulta; a função é IMMUTABLE e só olha o jsonb.)
create or replace function public._agenda_dupla_lista_ok(p_lista jsonb, p_gatilhos boolean)
 returns boolean
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  e        jsonb;
  v_vistos text[] := '{}';
  v_motivo text;
begin
  if p_lista is null or jsonb_typeof(p_lista) <> 'array' or (p_gatilhos and jsonb_array_length(p_lista) = 0) then
    return false;
  end if;
  for e in select x from jsonb_array_elements(p_lista) x loop
    if jsonb_typeof(e) <> 'array' or jsonb_array_length(e) <> (case when p_gatilhos then 4 else 2 end)
       or jsonb_typeof(e -> 0) <> 'string' or jsonb_typeof(e -> 1) <> 'string' then
      return false;
    end if;
    v_motivo := btrim(e ->> 0);
    if v_motivo = '' or v_motivo = any (v_vistos) or btrim(e ->> 1) = ''
       or not public._agenda_regex_valido('\m(' || (e ->> 1) || ')') then
      return false;
    end if;
    if p_gatilhos and (v_motivo <> all (array['banco_cc', 'bateria_pesada', 'ca_energizado', 'icamento'])
                       or jsonb_typeof(e -> 2) <> 'string' or (e ->> 2) <> all (array['inicio', 'fim'])
                       or jsonb_typeof(e -> 3) <> 'number' or (e ->> 3) !~ '^[0-9]+$'
                       or (e ->> 3)::int not between 1 and 8) then
      return false;
    end if;
    v_vistos := v_vistos || v_motivo;
  end loop;
  return true;
end;
$function$;

comment on function public._agenda_dupla_lista_ok(jsonb, boolean) is
  'Agenda de Produção (Fase 7a, P1): o CHECK de agenda_config.dupla_gatilhos (p_gatilhos = true: lista não vazia de [motivo em banco_cc/bateria_pesada/ca_energizado/icamento, expressão compilável, onde inicio/fim, meios-dias 1..8], sem motivo repetido) e dupla_notas (false: lista de [motivo, expressão compilável], sem motivo repetido). A expressão é validada como ''\m('' || expressão || '')'', como o casamento usa.';

-- O ampliador único das listas fechadas (7a a 7g usam este): lê o CHECK vivo pelo nome (o lote de 30/10 ou uma etapa anterior
-- pode ter ampliado), soma os valores novos sem repetir (na ordem: os de antes, depois os novos) e recria o CHECK com o mesmo
-- nome, na mesma transação. Nada a somar = não toca na tabela. CHECK que não existe, ou que não é uma lista simples da coluna,
-- é exceção (o nome errado não passa calado). Sem grant: só a migration chama.
create or replace function public._agenda_ampliar_lista(p_tabela regclass, p_constraint text, p_coluna text, p_novos text[])
 returns text[]
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_def   text;
  v_lista text[];
  v_nova  text[];
  v_col   text := regexp_replace(p_coluna, '([^a-zA-Z0-9_])', '\\\1', 'g');
begin
  select pg_get_constraintdef(c.oid) into v_def
    from pg_constraint c
   where c.conrelid = p_tabela and c.conname = p_constraint and c.contype = 'c';
  if v_def is null then
    raise exception '_agenda_ampliar_lista: o CHECK % não existe em %.', p_constraint, p_tabela using errcode = '42704';
  end if;
  -- Só a forma que o Postgres dá a "coluna in (...)" (ou "coluna = 'x'" com um valor só): outra regra não se reescreve aqui.
  if v_def !~ ('^CHECK \(\(' || v_col || ' = ANY \(ARRAY\[''[^]]*\]\)\)\)$')
     and v_def !~ ('^CHECK \(\(' || v_col || ' = ''[^'']*''::text\)\)$') then
    raise exception '_agenda_ampliar_lista: o CHECK % de % não é uma lista simples de %: %', p_constraint, p_tabela, p_coluna, v_def
      using errcode = '22023';
  end if;
  select array_agg(replace(m[1], '''''', '''') order by o) into v_lista
    from regexp_matches(v_def, '''((?:[^'']|'''')*)''', 'g') with ordinality t(m, o);
  v_nova := v_lista || array(select x from unnest(coalesce(p_novos, '{}')) with ordinality u(x, o)
                              where x is not null and x <> all (v_lista)
                                and o = (select min(o2) from unnest(p_novos) with ordinality u2(x2, o2) where x2 = u.x)
                              order by o);
  if cardinality(v_nova) = cardinality(v_lista) then
    return v_lista;
  end if;
  execute format('alter table %s drop constraint %I', p_tabela, p_constraint);
  execute format('alter table %s add constraint %I check (%I in (%s))', p_tabela, p_constraint, p_coluna,
                 (select string_agg(quote_literal(x), ', ' order by o) from unnest(v_nova) with ordinality u(x, o)));
  return v_nova;
end;
$function$;

comment on function public._agenda_ampliar_lista(regclass, text, text, text[]) is
  'Agenda de Produção (Fase 7a, P1): o ampliador único das listas fechadas (7a a 7g). Lê o CHECK vivo pelo nome (pg_get_constraintdef), soma p_novos sem repetir (os de antes primeiro, na ordem; depois os novos, na ordem) e recria o CHECK com o mesmo nome. Devolve a lista final. Nada a somar = não toca na tabela. CHECK que não existe = 42704; CHECK que não é "coluna in (...)" = 22023. Sem grant.';

revoke all on function public._agenda_regex_valido(text), public._agenda_dupla_lista_ok(jsonb, boolean) from public, anon;
grant execute on function public._agenda_regex_valido(text), public._agenda_dupla_lista_ok(jsonb, boolean)
  to authenticated, service_role;
revoke all on function public._agenda_ampliar_lista(regclass, text, text, text[])
  from public, anon, authenticated, service_role;

-- ── 1. agenda_config: os interruptores, as regras, a palavra e os parâmetros ────────────────────────────────────
alter table public.agenda_config
  -- 7a-0: o interruptor, as regras e a palavra
  add column if not exists modo_marcar_sozinho      text          not null default 'desligado',  -- AG7-01
  add column if not exists marcar_regras            text[]        not null default
    '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}',  -- AG7-01, AG7-09
  add column if not exists gestor_so_propor         boolean       not null default false,
  add column if not exists gestor_so_propor_em      timestamptz,
  add column if not exists marcar_sozinho_desde     timestamptz,                                -- AG7-01, AG7-15
  add column if not exists modo_vaga_fechamento     text          not null default 'desligado',
  add column if not exists fechamento_vagas_agenda  smallint      not null default 1,
  -- 7a-0: a duração
  add column if not exists estimativa_max_diarias   numeric(4,1)  not null default 8.0,
  add column if not exists mo_fora_regex            text          not null default '\m(deslocamento|viagem|translado|visita tecnica|km rodado|frete)\M',
  add column if not exists diagnostico_dias         numeric(3,1)  not null default 0.5,
  add column if not exists sem_mo_dias              numeric(3,1)  not null default 1.0,
  add column if not exists equipe_padrao            smallint      not null default 1,           -- AG7-04
  add column if not exists dupla_gatilhos           jsonb         not null default '[["banco_cc","banco de bateria|baterias? (de )?(chumbo|litio|agm|gel)|chumbo para litio|lifepo|litio|interligacao ao banco|instalacao de [0-9]+ baterias|realocacao do banco|barramento","inicio",2],["bateria_pesada","8d|4d|baterias? estacionaria|(200|220|230|250) ?ah","inicio",2],["ca_energizado","inversor|110/220|127 ?v|220 ?v|energia de terra|tomada de cais|shore|quadro (ac|ca)|sistema eletrico (ac|ca)\\M|transferencia|intertravamento|estabilizador","fim",2],["icamento","icamento|icar\\M|guindaste|munck|talha\\M|travelift|parelha de motores|motor(es)? de popa|(posicion|fixa|instala|retira|remo|desmont)[a-z]*( [a-z0-9/]+){0,6} gerador","inicio",2]]',  -- AG7-04
  add column if not exists dupla_notas              jsonb         not null default '[["confinado","casa de maquinas|paiol|poro\\M|compartimento d[ae] bateria"]]',  -- AG7-04 (só nota)
  add column if not exists situacao_dias            smallint      not null default 30,          -- AG7-11
  add column if not exists quanto_falta_dias        numeric(3,1)  not null default 1.0,         -- AG7-11
  add column if not exists veto_du                  smallint      not null default 1,           -- AG7-15
  add column if not exists veto_hora                time          not null default '18:00',     -- AG7-15
  add column if not exists ficha_veto_dias          smallint      not null default 21,          -- AG7-15
  -- 7a-0: o material
  add column if not exists critico_valor_min        numeric(10,2) not null default 300,         -- AG7-05
  add column if not exists prazo_sem_fornecedor_du  smallint      not null default 7,           -- AG7-06
  add column if not exists compra_interna_du        smallint      not null default 1,           -- AG7-07
  add column if not exists compra_urgente_du        smallint      not null default 7,           -- AG7-07
  -- o job do gestor
  add column if not exists gestor_hora_revisao      time          not null default '16:45',
  add column if not exists gestor_tempo_max         interval      not null default '45 seconds',
  add column if not exists aprovada_sem_data_min    smallint      not null default 30,
  -- 7a-1
  add column if not exists modo_encaixe_aprovacao   text          not null default 'desligado',
  add column if not exists modo_revisao_diaria      text          not null default 'desligado',
  add column if not exists modo_compre_ate          text          not null default 'desligado',
  add column if not exists gestor_k_os              smallint      not null default 2,
  add column if not exists gestor_k_dias_avisados   smallint      not null default 1,
  add column if not exists compre_ate_empurroes_max smallint      not null default 2,
  add column if not exists compras_aviso_du         smallint      not null default 2,
  add column if not exists sabado_manha             text          not null default 'so_prazo',  -- AG7-08
  add column if not exists simular_orcamento_acima  numeric(12,2) not null default 20000,
  add column if not exists simular_orcamento_dias   smallint      not null default 30;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('agenda_config_modo_marcar_sozinho_check',
       'check (modo_marcar_sozinho in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_vaga_fechamento_check',
       'check (modo_vaga_fechamento in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_encaixe_aprovacao_check',
       'check (modo_encaixe_aprovacao in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_revisao_diaria_check',
       'check (modo_revisao_diaria in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_compre_ate_check',
       'check (modo_compre_ate in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_marcar_regras_check',
       'check (marcar_regras <@ array[''estimativa'', ''mo_limpa'', ''uma_pessoa'', ''diagnostico'', ''situacao'', ''sem_peca'', ''embutida_suposta'', ''critico_por_valor'', ''prazo_padrao'', ''compra_firme'', ''teto_equipe'', ''zona_travada'', ''onda'', ''escada'', ''sinal_cobrar'']::text[])'),
      ('agenda_config_fechamento_vagas_agenda_check', 'check (fechamento_vagas_agenda between 0 and 2)'),
      ('agenda_config_estimativa_max_diarias_check',  'check (estimativa_max_diarias between 2 and 30)'),
      ('agenda_config_mo_fora_regex_check',
       'check (char_length(mo_fora_regex) between 3 and 400 and public._agenda_regex_valido(mo_fora_regex))'),
      ('agenda_config_dupla_gatilhos_check',          'check (public._agenda_dupla_lista_ok(dupla_gatilhos, true))'),
      ('agenda_config_dupla_notas_check',             'check (public._agenda_dupla_lista_ok(dupla_notas, false))'),
      ('agenda_config_diagnostico_dias_check',
       'check (diagnostico_dias between 0.5 and 2 and diagnostico_dias * 2 = trunc(diagnostico_dias * 2))'),
      ('agenda_config_sem_mo_dias_check',
       'check (sem_mo_dias between 0.5 and 5 and sem_mo_dias * 2 = trunc(sem_mo_dias * 2))'),
      ('agenda_config_equipe_padrao_check',           'check (equipe_padrao between 1 and 3)'),
      ('agenda_config_situacao_dias_check',           'check (situacao_dias between 7 and 120)'),
      ('agenda_config_quanto_falta_dias_check',
       'check (quanto_falta_dias between 0.5 and 5 and quanto_falta_dias * 2 = trunc(quanto_falta_dias * 2))'),
      ('agenda_config_veto_du_check',                 'check (veto_du between 0 and 3)'),
      ('agenda_config_veto_hora_check',
       'check (veto_hora >= cliente_janela_inicio and veto_hora < equipe_hora_ficha)'),
      ('agenda_config_ficha_veto_dias_check',         'check (ficha_veto_dias between 0 and 60)'),
      ('agenda_config_critico_valor_min_check',       'check (critico_valor_min between 0 and 5000)'),
      ('agenda_config_prazo_sem_fornecedor_du_check', 'check (prazo_sem_fornecedor_du between 1 and 20)'),
      ('agenda_config_compra_interna_du_check',       'check (compra_interna_du between 0 and 10)'),
      ('agenda_config_compra_urgente_du_check',       'check (compra_urgente_du between 0 and 20)'),
      -- (dois CHECKs: o que liga a revisão ao plano tem nome que vem depois de agenda_config_hora_do_plano_check — o Postgres
      -- confere os CHECKs na ordem do nome, e o plano fora da hora dele continua recusado pelo CHECK dele)
      ('agenda_config_gestor_hora_revisao_check',     'check (gestor_hora_revisao <= cliente_janela_fim)'),
      ('agenda_config_revisao_depois_do_plano_check', 'check (gestor_hora_revisao > hora_do_plano)'),
      ('agenda_config_gestor_tempo_max_check',
       'check (gestor_tempo_max between interval ''10 seconds'' and interval ''120 seconds'')'),
      ('agenda_config_aprovada_sem_data_min_check',   'check (aprovada_sem_data_min between 15 and 240)'),
      ('agenda_config_gestor_k_os_check',             'check (gestor_k_os between 1 and 10)'),
      ('agenda_config_gestor_k_dias_avisados_check',  'check (gestor_k_dias_avisados between 0 and 10)'),
      ('agenda_config_compre_ate_empurroes_max_check', 'check (compre_ate_empurroes_max between 1 and 5)'),
      ('agenda_config_compras_aviso_du_check',        'check (compras_aviso_du between 0 and 5)'),
      ('agenda_config_sabado_manha_check',
       'check (sabado_manha in (''nunca'', ''so_prazo'', ''oferecido''))'),
      ('agenda_config_simular_orcamento_acima_check', 'check (simular_orcamento_acima >= 0)'),
      ('agenda_config_simular_orcamento_dias_check',  'check (simular_orcamento_dias between 7 and 120)')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_config'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_config add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

-- Como as Fases 2 a 6: a estrutura não muda comportamento. A linha que já existe fica 'desligado' (do add column acima); quem
-- a põe em sombra é a migration de dado 20261031100990, com OK nomeado (AG7-01: ligar no mesmo dia do pós-deploy verde).
alter table public.agenda_config
  alter column modo_marcar_sozinho    set default 'sombra',
  alter column modo_vaga_fechamento   set default 'sombra',
  alter column modo_encaixe_aprovacao set default 'sombra',
  alter column modo_revisao_diaria    set default 'sombra',
  alter column modo_compre_ate        set default 'sombra';

comment on column public.agenda_config.modo_marcar_sozinho is
  'Agenda de Produção (Fase 7a, AG7-01): o gestor marca sozinho pela estimativa do orçamento. desligado = as regras de marcar_regras não valem; sombra = a rodada do gestor calcula "eu marcaria assim" (o mesmo motor, com as regras ligadas só dentro da simulação, pela variável agenda.gestor) e o fechamento mostra; ligado = as regras valem (o dono corrige depois: D7-1). O dono respondeu "ligar direto quando estiver pronto": a migration de dado põe sombra e o ligar é no mesmo dia do pós-deploy verde, com o cadastro da equipe certo (AG7-03). *gestor, só propor* volta a sombra.';
comment on column public.agenda_config.marcar_regras is
  'Agenda de Produção (Fase 7a, AG7-01/AG7-09): as regras do gestor que valem com modo_marcar_sozinho ligado (o molde de aprendizado_ligados). Tirar uma desliga só ela. estimativa (os dias do orçamento valem como firmes), mo_limpa (deslocamento/viagem/visita fora da mão de obra), uma_pessoa (1 pessoa: equipe_padrao), diagnostico (meio dia e reavalia), situacao (OS começada ou parada pergunta "quanto falta?"), sem_peca (sem linha de material = sem peça a comprar), embutida_suposta (peça embutida não trava), critico_por_valor (só item de valor ≥ critico_valor_min segura a data), prazo_padrao (sem fornecedor = prazo_sem_fornecedor_du), compra_firme (peça a comprar não manda para reserva: cobra a compra), teto_equipe (o teto de 80% na equipe-semana), zona_travada (dia avisado vira pergunta), onda (mais de K mudanças = só propõe), escada (o reparo antes do motor), sinal_cobrar (o sinal não pago não segura a data: marca e lembra o dono, AG7-09 "marco e cobro o sinal").';
comment on column public.agenda_config.gestor_so_propor is
  'Agenda de Produção (Fase 7a): a palavra *gestor, só propor* (true) — os interruptores do gestor que estão ligados valem sombra e as regras param; o que as Fases 1–6 fazem continua. *gestor, pode marcar* volta (false).';
comment on column public.agenda_config.gestor_so_propor_em is 'Agenda de Produção (Fase 7a): quando o dono disse *gestor, só propor* ou *gestor, pode marcar* pela última vez.';
comment on column public.agenda_config.marcar_sozinho_desde is
  'Agenda de Produção (Fase 7a, AG7-01/AG7-15): gravado pelo OK de ligar o gestor. A janela da ficha por estimativa (ficha_veto_dias) conta daqui.';
comment on column public.agenda_config.modo_vaga_fechamento is
  'Agenda de Produção (Fase 7a): a agenda ganha vagas próprias no fechamento das 17:30 (fechamento_vagas_agenda; +1 com decisão de perda ≥ 80, até 2). desligado/sombra = a agenda só pega a sobra das 3 vagas (como hoje); sombra mostra no detalhe o que entraria.';
comment on column public.agenda_config.fechamento_vagas_agenda is 'Agenda de Produção (Fase 7a): as vagas garantidas da agenda no fechamento das 17:30 com modo_vaga_fechamento ligado (0 a 2).';
comment on column public.agenda_config.estimativa_max_diarias is
  'Agenda de Produção (Fase 7a): acima destas diárias (realista do orçamento), o gestor não marca pela estimativa: pergunta antes, com o que faria e um prazo (AG7-15).';
comment on column public.agenda_config.mo_fora_regex is
  'Agenda de Produção (Fase 7a, NOVO-agenda-47): as linhas de serviço cujo NOME (normalizado) casa esta expressão saem da mão de obra e das horas da estimativa (deslocamento, viagem, translado, visita técnica, km rodado, frete). Pelo nome, nunca pela unidade (''visit'' é "por serviço").';
comment on column public.agenda_config.diagnostico_dias is 'Agenda de Produção (Fase 7a): a OS de diagnóstico vale isto (meio dia) e o gestor reavalia depois.';
comment on column public.agenda_config.sem_mo_dias is
  'Agenda de Produção (Fase 7a): a OS sem mão de obra no orçamento — o gestor pergunta; sem resposta até o prazo, marca isto (1 dia).';
comment on column public.agenda_config.equipe_padrao is
  'Agenda de Produção (Fase 7a, AG7-04): com a regra uma_pessoa, o tamanho da equipe de um serviço (1 pessoa). A dupla só quando o dono marca (*<nome> com dupla*: os_planejamento.dupla_dita) — e aí vale equipe_sugerida (o tamanho da dupla). O 7b lê este nome.';
comment on column public.agenda_config.dupla_gatilhos is
  'Agenda de Produção (Fase 7a, AG7-04; o 7b lê daqui e não cria outro): os serviços que pedem dupla — [motivo, expressão casada no início de palavra do nome do serviço normalizado, onde (inicio/fim), meios-dias]. banco de baterias e bateria pesada nos 2 primeiros meios-dias; 127/220 V energizado nos 2 últimos; içamento nos 2 primeiros. No 7a só geram nota ao dono (a dupla automática é o modo_dupla do 7b). 12 V comum = 1 pessoa.';
comment on column public.agenda_config.dupla_notas is
  'Agenda de Produção (Fase 7a, AG7-04): o que só vira nota ao dono, nunca dupla — [motivo, expressão] (espaço confinado: casa de máquinas, paiol, porão, compartimento de bateria).';
comment on column public.agenda_config.situacao_dias is
  'Agenda de Produção (Fase 7a, AG7-11): OS aberta parada há mais destes dias (sem atividade) pergunta "ainda é para fazer tudo?" antes de marcar.';
comment on column public.agenda_config.quanto_falta_dias is
  'Agenda de Produção (Fase 7a, AG7-11): na OS já começada de verdade (check-in, em andamento ou diária ligada), o "quanto falta?" sem resposta até o prazo vale isto (1 dia).';
comment on column public.agenda_config.veto_du is
  'Agenda de Produção (Fase 7a, AG7-15): a pergunta do gestor com prazo espera até o próximo dia útil (este tanto) às veto_hora; sem resposta — e só se foi mostrada antes do prazo —, fica como ele disse. Nunca para o que mexe em dia que o cliente ouviu.';
comment on column public.agenda_config.veto_hora is
  'Agenda de Produção (Fase 7a, AG7-15): a hora do prazo das perguntas com prazo (18:00, o mesmo do 7f: o fechamento sai às 17:30). Entre cliente_janela_inicio e equipe_hora_ficha.';
comment on column public.agenda_config.ficha_veto_dias is
  'Agenda de Produção (Fase 7a, AG7-15): nas primeiras semanas a partir de marcar_sozinho_desde, a ficha das 19:30 de um dia marcado pela estimativa só sai se o dono pôde ver (a pergunta ficha_estimativa mostrada e não segurada).';
comment on column public.agenda_config.critico_valor_min is
  'Agenda de Produção (Fase 7a, AG7-05): com a regra critico_por_valor, só o item do orçamento de valor unitário de VENDA a partir disto segura a data; abaixo, "separar na véspera". O fato do dono vence.';
comment on column public.agenda_config.prazo_sem_fornecedor_du is
  'Agenda de Produção (Fase 7a, AG7-06): a peça sem fornecedor (nem prazo da cidade) conta este prazo em dias úteis (o dono respondeu 7) e o gestor pergunta "de quem comprar? (contei 7 dias úteis)".';
comment on column public.agenda_config.compra_interna_du is
  'Agenda de Produção (Fase 7a, AG7-07): o tempo entre aprovar e comprar, em dias úteis (o dono: "você define o ideal; é uma corrida contra o tempo" — 1 = comprar no próximo dia útil). O "compre até" desconta também isto. O 7e mede o real.';
comment on column public.agenda_config.compra_urgente_du is
  'Agenda de Produção (Fase 7a, AG7-07): com o 1º dia de compromisso a menos destes dias úteis, a cobrança diz "compre hoje para começar em {dia}" e a linha de compras do fechamento vai como decisão. 0 = nunca urgente.';
comment on column public.agenda_config.gestor_hora_revisao is
  'Agenda de Produção (Fase 7a): a revisão diária do gestor roda no 1º tique de dia útil a partir desta hora (16:45: o tique das 16:52), depois da publicação da quinta e antes do fechamento.';
comment on column public.agenda_config.gestor_tempo_max is 'Agenda de Produção (Fase 7a): o statement_timeout da rodada do gestor (o job agenda-gestor).';
comment on column public.agenda_config.aprovada_sem_data_min is
  'Agenda de Produção (Fase 7a): a OS aprovada há mais destes minutos sem data, sem motivo e sem pergunta conta no zero aprovada_sem_data da saúde.';
comment on column public.agenda_config.modo_encaixe_aprovacao is
  'Agenda de Produção (Fase 7a): o encaixe na aprovação (a cada 15 min, pelo job do gestor). desligado = não roda; sombra = só grava no diário o que faria; ligado = marca.';
comment on column public.agenda_config.modo_revisao_diaria is
  'Agenda de Produção (Fase 7a): a revisão diária das 2 semanas (16:45) com a escada de reparo. desligado = não roda; sombra = só grava no diário; ligado = mexe.';
comment on column public.agenda_config.modo_compre_ate is
  'Agenda de Produção (Fase 7a, AG7-07): a cobrança do "compre até" gravado na linha de material. desligado = não grava; sombra = grava sem cobrar; ligado = cobra e, vencido, a OS é empurrada (até compre_ate_empurroes_max).';
comment on column public.agenda_config.gestor_k_os is
  'Agenda de Produção (Fase 7a): a onda — numa rodada, mais que estas OS com dia mudado: o gestor não aplica e pergunta (a pergunta crítica onda).';
comment on column public.agenda_config.gestor_k_dias_avisados is
  'Agenda de Produção (Fase 7a): a onda — numa rodada, mais que estes dias já avisados à equipe afetados: o gestor não aplica e pergunta.';
comment on column public.agenda_config.compre_ate_empurroes_max is
  'Agenda de Produção (Fase 7a): depois de tantos empurrões pelo mesmo item ("compre até" vencido sem compra), o gestor para de remarcar: a OS volta à reserva com "de quem e quando?".';
comment on column public.agenda_config.compras_aviso_du is
  'Agenda de Produção (Fase 7a): o "compre até" que vence em até estes dias úteis entra na linha de compras do fechamento.';
comment on column public.agenda_config.sabado_manha is
  'Agenda de Produção (Fase 7a, AG7-08; o 7b lê daqui e não cria outro): a manhã de sábado — nunca; so_prazo (o dono: "sim, quando precisar" — só para cumprir uma data firme, perguntando antes no 7a; com o modo_sabado do 7b ligado, avisando no texto); oferecido.';
comment on column public.agenda_config.simular_orcamento_acima is
  'Agenda de Produção (Fase 7a): orçamento enviado ou em rascunho a partir deste valor ganha o "se aprovar, cabe a partir de X" (sem ocupar ninguém).';
comment on column public.agenda_config.simular_orcamento_dias is
  'Agenda de Produção (Fase 7a): só os orçamentos mexidos nestes dias corridos entram no "se aprovar, cabe a partir de X".';
comment on column public.agenda_config.equipe_sugerida is
  'Agenda de Produção: quantas pessoas por serviço quando o dono não disse (Fase 1). Fase 7a: com a regra uma_pessoa vale equipe_padrao (1 pessoa, AG7-04); este número passa a ser o tamanho da dupla, quando o dono marca *<nome> com dupla*.';

-- ── 2. os_planejamento: a fonte 'orcamento', a marca de dupla e a medida do início ─────────────────────────────
select public._agenda_ampliar_lista('public.os_planejamento', 'os_planejamento_estimativa_fonte_check', 'estimativa_fonte',
                                    array['orcamento']);
select public._agenda_ampliar_lista('public.os_planejamento', 'os_planejamento_dias_no_inicio_fonte_check', 'dias_no_inicio_fonte',
                                    array['orcamento']);

alter table public.os_planejamento
  add column if not exists dupla_dita   text check (dupla_dita in ('nao', 'inicio', 'fim', 'todos')),   -- AG7-04: null = a regra
  add column if not exists dupla_meios  smallint check (dupla_meios between 1 and 20),
  add column if not exists dupla_motivo text check (char_length(dupla_motivo) <= 80),
  add column if not exists dupla_em     timestamptz,
  add column if not exists dp_no_inicio numeric(5,2);

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.os_planejamento'::regclass and conname = 'dupla_meios_coerente') then
    alter table public.os_planejamento add constraint dupla_meios_coerente
      check (coalesce(dupla_dita in ('inicio', 'fim'), false) = (dupla_meios is not null));
  end if;
end
$$;

comment on column public.os_planejamento.estimativa_fonte is
  'dono (o dono disse os dias) ou aceita (aceitou a sugestão do banco). Fase 7a: orcamento — a estimativa do gestor, gravada só quando a pergunta com prazo dele vence sem resposta (_agenda_gestor_gravar_dias). O dono vence sempre; com o portão estimativa falso, o orcamento gravado é lido como sugerida.';
comment on column public.os_planejamento.dupla_dita is
  'Agenda de Produção (Fase 7a, AG7-04; uma marca só para 7a e 7b): null = a regra (1 pessoa, equipe_padrao); todos = dupla a OS inteira (*<nome> com dupla*); nao = sem dupla (*<nome> sem dupla*); inicio/fim = dupla nos dupla_meios primeiros ou últimos meios-dias (o 7b, pelo planejar).';
comment on column public.os_planejamento.dupla_meios is 'Agenda de Produção (Fase 7a/7b, AG7-04): os meios-dias com dupla (1 a 20), só com dupla_dita inicio ou fim.';
comment on column public.os_planejamento.dupla_motivo is 'Agenda de Produção (Fase 7a/7b, AG7-04): por que a dupla (o que o dono disse ou o gatilho do serviço), até 80 letras.';
comment on column public.os_planejamento.dupla_em is 'Agenda de Produção (Fase 7a/7b, AG7-04): quando a marca de dupla foi dita.';
comment on column public.os_planejamento.dp_no_inicio is
  'Agenda de Produção (Fase 7a): as diárias-pessoa estimadas no dia do check-in (congeladas com dias_no_inicio), para o 7e medir o viés da estimativa.';

-- ── 3. agenda_alocacoes: de onde veio a duração; cancelada_motivo + reestimada ──────────────────────────────────
alter table public.agenda_alocacoes
  add column if not exists duracao_fonte text check (duracao_fonte in ('dono', 'aceita', 'orcamento', 'sugerida'));
select public._agenda_ampliar_lista('public.agenda_alocacoes', 'agenda_alocacoes_cancelada_motivo_check', 'cancelada_motivo',
                                    array['reestimada']);

comment on column public.agenda_alocacoes.duracao_fonte is
  'Agenda de Produção (Fase 7a, D7-1): de onde veio a duração da OS quando o meio-dia nasceu — dono, aceita, orcamento (a estimativa do gestor) ou sugerida. Preenchida pelo gatilho agenda_alocacoes_fonte (o item criar da proposta, senão os_planejamento.estimativa_fonte, senão sugerida); nula na reserva e nas alocações de antes da Fase 7.';

-- O gatilho da fonte: BEFORE INSERT. A reserva não tem fonte; o resto: o que veio dito, senão a fonte do item 'criar' da proposta
-- para a OS, senão os dias gravados do planejamento, senão 'sugerida'. Barato: lê o item pelo proposta_id e a linha da OS.
create or replace function public._agenda_alocacao_fonte()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  v_fonte text;
begin
  if new.tipo = 'reserva' then
    new.duracao_fonte := null;
    return new;
  end if;
  if new.duracao_fonte is null and new.proposta_id is not null then
    select i ->> 'fonte' into v_fonte
      from public.agenda_propostas p,
           jsonb_array_elements(case when jsonb_typeof(p.itens) = 'array' then p.itens else '[]'::jsonb end) i
     where p.id = new.proposta_id
       and i ->> 'op' = 'criar' and i ->> 'os' = new.service_order_id::text
       and i ->> 'fonte' in ('dono', 'aceita', 'orcamento', 'sugerida')
     limit 1;
  end if;
  if new.duracao_fonte is null and v_fonte is null then
    select pl.estimativa_fonte into v_fonte
      from public.os_planejamento pl where pl.service_order_id = new.service_order_id;
  end if;
  new.duracao_fonte := coalesce(new.duracao_fonte, v_fonte, 'sugerida');
  return new;
end;
$function$;

comment on function public._agenda_alocacao_fonte() is
  'Agenda de Produção (Fase 7a, P1): gatilho BEFORE INSERT de agenda_alocacoes — duracao_fonte: nula na reserva; senão a dita, a do item criar da proposta para a OS, a de os_planejamento.estimativa_fonte ou sugerida.';

drop trigger if exists agenda_alocacoes_fonte on public.agenda_alocacoes;
create trigger agenda_alocacoes_fonte before insert on public.agenda_alocacoes
  for each row execute function public._agenda_alocacao_fonte();

-- ── 4. os_material: o "compre até" gravado, a cobrança, os empurrões e o defeito ────────────────────────────────
alter table public.os_material
  add column if not exists compre_ate      date,
  add column if not exists compre_ate_base jsonb check (compre_ate_base is null or jsonb_typeof(compre_ate_base) = 'object'),
  add column if not exists compre_ate_em   timestamptz,
  add column if not exists cobrado_em      timestamptz,
  add column if not exists cobrado_vezes   smallint not null default 0 check (cobrado_vezes between 0 and 50),
  add column if not exists empurrada_vezes smallint not null default 0 check (empurrada_vezes between 0 and 20),
  add column if not exists defeito_em      timestamptz;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.os_material'::regclass and conname = 'compre_ate_coerente') then
    alter table public.os_material add constraint compre_ate_coerente
      check ((compre_ate is null) = (compre_ate_base is null));
  end if;
end
$$;

comment on column public.os_material.compre_ate is
  'Agenda de Produção (Fase 7a, AG7-07): o "compre até" gravado pelo gestor (P10) quando a OS tem compromisso: o 1º dia − folga − prazo − o tempo interno de compra. Enquanto não vence, protege o publicado (a data não desliza); vencido, "compre hoje".';
comment on column public.os_material.compre_ate_base is
  'Agenda de Produção (Fase 7a): a conta do compre_ate — {primeiro, folga, prazo, prazo_fonte (fornecedor|cidade|medido|padrao), interno}.';
comment on column public.os_material.compre_ate_em is 'Agenda de Produção (Fase 7a): quando o compre_ate foi gravado (ou mudou).';
comment on column public.os_material.cobrado_em is 'Agenda de Produção (Fase 7a): a última cobrança da compra ao dono (a pergunta compre_ate).';
comment on column public.os_material.cobrado_vezes is 'Agenda de Produção (Fase 7a): quantas vezes a compra deste item foi cobrada.';
comment on column public.os_material.empurrada_vezes is
  'Agenda de Produção (Fase 7a): quantas vezes a OS foi remarcada porque este item não foi comprado a tempo (o teto é compre_ate_empurroes_max).';
comment on column public.os_material.defeito_em is
  'Agenda de Produção (Fase 7a): quando a peça que estava na mão voltou a faltar (chegou errada, com defeito, troca em garantia): o "compre até" reabre.';

-- ── 5. agenda_perguntas: o prazo, a opção padrão, os tipos do gestor e a coluna gerada critica ─────────────────────
alter table public.agenda_perguntas
  add column if not exists veto_ate     timestamptz,
  add column if not exists opcao_padrao smallint;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      -- a opção que vale sem resposta só existe com o prazo (o 7b, o 7c e o 7f põem prazo em pergunta sem opção padrão)
      ('veto_padrao_tem_prazo', 'check (opcao_padrao is null or veto_ate is not null)'),
      -- a pergunta crítica nunca tem prazo (o 7f troca esta regra pela de veto_tipos)
      ('veto_nao_critica',      'check (veto_ate is null or not critica)')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_perguntas'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_perguntas add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

select public._agenda_ampliar_lista('public.agenda_perguntas', 'agenda_perguntas_tipo_check', 'tipo',
  array['situacao', 'estimativa', 'equipe_cadastro', 'reavaliar', 'reestimar', 'ficha_estimativa', 'bem_livre', 'compre_ate',
        'sinal', 'onda', 'dia_avisado', 'dia_prometido', 'sabado']);

-- A coluna gerada: onda, dia_avisado, dia_prometido e sabado passam a ser críticas. SET EXPRESSION (Postgres 17+, o molde de
-- 20261029100000) mantém a coluna no lugar e reconstrói e revalida critica_tem_opcoes, critica_decidida e veto_nao_critica com o
-- mesmo nome. Só se a expressão ainda não tem 'onda' (rodar de novo não reescreve a tabela). O 7d e o 7g copiam ESTA expressão.
do $$
begin
  if exists (select 1
               from pg_attribute a
               join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
              where a.attrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica' and a.attgenerated = 's'
                and pg_get_expr(d.adbin, d.adrelid) not like '%''onda''%') then
    if current_setting('server_version_num')::int < 170000 then
      raise exception 'agenda_perguntas.critica: esta migration precisa do Postgres 17 ou mais novo (ALTER COLUMN … SET EXPRESSION); este é o %.',
        current_setting('server_version');
    end if;
    alter table public.agenda_perguntas alter column critica set expression as
      (tipo in ('nao_cabe','segundo_atraso','atraso_longo','remarcar_confirmado','fixada_pelo_dono','diaria','cliente_aviso',
                'aprendizado','onda','dia_avisado','dia_prometido','sabado'));
  end if;
end
$$;

comment on column public.agenda_perguntas.veto_ate is
  'Agenda de Produção (Fase 7a, AG7-15): o prazo da pergunta — sem resposta até aqui, e só se ela foi mostrada ao dono antes (mostrada_vezes > 0 e mostrada_em < veto_ate), vale opcao_padrao (_agenda_gestor_vetos). Vai de nulo a um valor uma vez, na pergunta aberta (quem mostra com o prazo escrito grava: 7b e 7c); de um valor a outro, só o 7f.';
comment on column public.agenda_perguntas.opcao_padrao is
  'Agenda de Produção (Fase 7a, AG7-15): a opção que vale quando o prazo vence sem resposta (uma das opções; só com veto_ate).';

-- ── 6. As outras listas fechadas: ações, rodadas e a recusa à equipe ────────────────────────────────────────────
select public._agenda_ampliar_lista('public.agenda_acoes', 'agenda_acoes_tipo_check', 'tipo',
                                    array['estimar', 'reestimar', 'reparar', 'gestor', 'dupla']);
select public._agenda_ampliar_lista('public.agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check', 'rotina',
                                    array['gestor']);
select public._agenda_ampliar_lista('public.agenda_equipe_mensagens', 'agenda_equipe_mensagens_recusa_motivo_check',
                                    'recusa_motivo', array['veto']);

comment on column public.agenda_vigia_rodadas.rotina is
  'Agenda de Produção (Fase 3): vigia (o tique da Fase 2) ou rotina (a rotina da equipe e da diária); Fase 4: material (a nota, o Pix, o detector e a mensagem ao fornecedor); Fase 5: cliente (as mensagens-modelo ao cliente); Fase 6: aprender (a medição e o aprendizado, uma vez por dia); Fase 7a: gestor (a rodada do gestor da agenda, o job agenda-gestor). As rodadas de antes são da vigia.';

-- ── 7. agenda_medidas_os: a medida contra a estimativa ──────────────────────────────────────────────────────────
select public._agenda_ampliar_lista('public.agenda_medidas_os', 'agenda_medidas_os_dias_fonte_check', 'dias_fonte',
                                    array['orcamento']);

alter table public.agenda_medidas_os
  add column if not exists fator_orcamento numeric(4,2),
  add column if not exists dp_no_inicio    numeric(5,2),
  add column if not exists dp_reais        numeric(6,2);

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.agenda_medidas_os'::regclass and conname = 'fator_orcamento_so_orcamento') then
    alter table public.agenda_medidas_os add constraint fator_orcamento_so_orcamento
      check (fator_orcamento is null or (valida and dias_fonte = 'orcamento'));
  end if;
end
$$;

comment on column public.agenda_medidas_os.dias_fonte is
  'dono ou aceita (os dias ditos até o check-in) ou sugerida (a duração sugerida pelo banco: a medida não vale). Fase 7a: orcamento — a estimativa do gestor; a medida vale, com o fator à parte (fator_orcamento).';
comment on column public.agenda_medidas_os.fator_orcamento is
  'Agenda de Produção (Fase 7a): meios-dias reais ÷ (dias × 2) da OS marcada pela estimativa do orçamento. O aprendizado do fator (que lê fator) NÃO lê esta coluna; o 7e mede o viés por ela.';
comment on column public.agenda_medidas_os.dp_no_inicio is 'Agenda de Produção (Fase 7a): as diárias-pessoa estimadas no check-in (os_planejamento.dp_no_inicio).';
comment on column public.agenda_medidas_os.dp_reais is
  'Agenda de Produção (Fase 7a): as diárias-pessoa reais — as diárias ligadas + os meios-dias de turno do dono ÷ 2.';

-- ── 8. O diário do gestor ───────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.agenda_gestor_dia (
  dia          date primary key,
  calculado_em timestamptz not null,
  modos        jsonb not null check (jsonb_typeof(modos) = 'object'),
  sombra       jsonb not null default '{}' check (jsonb_typeof(sombra) = 'object'),
  orcamentos   jsonb not null default '[]' check (jsonb_typeof(orcamentos) = 'array'),
  compras      jsonb not null default '[]' check (jsonb_typeof(compras) = 'array'),
  texto_sombra text check (char_length(texto_sombra) <= 640),
  historico    jsonb not null default '[]'
                 check (case when jsonb_typeof(historico) = 'array' then jsonb_array_length(historico) <= 20 else false end)
);

comment on table public.agenda_gestor_dia is
  'Agenda de Produção (Fase 7a): o diário do gestor da agenda — um registro por dia (Brasília) com os modos efetivos na hora, o "eu marcaria assim" (sombra: {itens, fora, perguntas, compras, md5}), os orçamentos que caberiam ("se aprovar, cabe a partir de X"), as compras da semana por fornecedor e a linha do fechamento (texto_sombra, ≤ 640). Só _agenda_gestor_dia_gravar escreve; a rodada de cada dia reescreve as chaves dela e guarda a de antes no histórico. Não se apaga.';
comment on column public.agenda_gestor_dia.modos is 'Os modos efetivos do gestor na última gravação (_agenda_gestor_modo de cada um e gestor_so_propor).';
comment on column public.agenda_gestor_dia.historico is '[{em, chave, antes}] — o valor de antes de cada chave reescrita (os 20 mais novos).';

drop trigger if exists agenda_gestor_dia_nao_apaga on public.agenda_gestor_dia;
create trigger agenda_gestor_dia_nao_apaga before delete on public.agenda_gestor_dia
  for each row execute function public._agenda_registro_nao_apaga();

alter table public.agenda_gestor_dia enable row level security;

drop policy if exists agenda_gestor_dia_leitura on public.agenda_gestor_dia;
create policy agenda_gestor_dia_leitura on public.agenda_gestor_dia
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

revoke all on table public.agenda_gestor_dia from public, anon, authenticated;
grant select on table public.agenda_gestor_dia to authenticated;
grant all on table public.agenda_gestor_dia to service_role;

-- ── 9. As funções da base: o portão, o modo, o dia avisado e o gravador do diário ───────────────────────────────

-- O portão de toda regra do gestor (spec-fase7a §3.1, item 2): verdadeiro (a) dentro da simulação da sombra (a variável de
-- sessão agenda.gestor = 'sombra', posta só por _agenda_gestor_sombra e pelo encaixe em sombra) com a regra em marcar_regras,
-- ou (b) com modo_marcar_sozinho ligado, sem *gestor, só propor* e com a regra em marcar_regras. Regra que não existe = 22023.
-- A lista das regras é a mesma do DEFAULT e do CHECK de marcar_regras (o teste B4 confere as três).
create or replace function public._agenda_gestor_regra(p_regra text)
 returns boolean
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c_regras constant text[] := array['estimativa', 'mo_limpa', 'uma_pessoa', 'diagnostico', 'situacao', 'sem_peca',
                                    'embutida_suposta', 'critico_por_valor', 'prazo_padrao', 'compra_firme', 'teto_equipe',
                                    'zona_travada', 'onda', 'escada', 'sinal_cobrar'];
  cf public.agenda_config;
begin
  if p_regra is null or not (p_regra = any (c_regras)) then
    raise exception '_agenda_gestor_regra: a regra "%" não existe.', p_regra using errcode = '22023';
  end if;
  cf := public._agenda_cfg();
  if coalesce(current_setting('agenda.gestor', true), '') = 'sombra' then
    return p_regra = any (cf.marcar_regras);
  end if;
  return cf.modo_marcar_sozinho = 'ligado' and not cf.gestor_so_propor and p_regra = any (cf.marcar_regras);
end;
$function$;

comment on function public._agenda_gestor_regra(text) is
  'Agenda de Produção (Fase 7a, P1): o portão das regras do gestor. true dentro da simulação da sombra (agenda.gestor = ''sombra'') com a regra em marcar_regras, ou com modo_marcar_sozinho = ''ligado'', gestor_so_propor = false e a regra em marcar_regras; senão false (o comportamento das Fases 1–6, byte a byte). Regra fora da lista = 22023.';

-- O modo efetivo de cada comportamento do gestor (§3.1, item 4): marcar, encaixe, revisao, compre_ate, vaga. Dentro da simulação
-- da sombra, marcar vale sombra. Com *gestor, só propor*, o que está ligado em marcar, encaixe, revisao e compre_ate vale sombra
-- (o desligado continua desligado; a vaga do fechamento não muda pela palavra).
create or replace function public._agenda_gestor_modo(p_qual text)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config;
  v_modo text;
begin
  if p_qual is null or p_qual <> all (array['marcar', 'encaixe', 'revisao', 'compre_ate', 'vaga']) then
    raise exception '_agenda_gestor_modo: o modo "%" não existe.', p_qual using errcode = '22023';
  end if;
  cf := public._agenda_cfg();
  v_modo := case p_qual
              when 'marcar'     then cf.modo_marcar_sozinho
              when 'encaixe'    then cf.modo_encaixe_aprovacao
              when 'revisao'    then cf.modo_revisao_diaria
              when 'compre_ate' then cf.modo_compre_ate
              when 'vaga'       then cf.modo_vaga_fechamento
            end;
  if p_qual = 'marcar' and coalesce(current_setting('agenda.gestor', true), '') = 'sombra' then
    return 'sombra';
  end if;
  if p_qual <> 'vaga' and cf.gestor_so_propor and v_modo = 'ligado' then
    return 'sombra';
  end if;
  return v_modo;
end;
$function$;

comment on function public._agenda_gestor_modo(text) is
  'Agenda de Produção (Fase 7a, P1): o modo efetivo (desligado | sombra | ligado) de marcar (modo_marcar_sozinho), encaixe (modo_encaixe_aprovacao), revisao (modo_revisao_diaria), compre_ate (modo_compre_ate) e vaga (modo_vaga_fechamento). Dentro da simulação (agenda.gestor = ''sombra''), marcar = sombra. Com gestor_so_propor, o ligado de marcar/encaixe/revisao/compre_ate vale sombra. Outro nome = 22023.';

-- O dia já foi dito (§4.4): ao cliente — ele ouviu esse dia (_agenda_cliente_ouviu: mensagem com data firme ou
-- client_confirmed_for) ou o prometido firme cobre o dia — ou à equipe — a ficha ou a confirmação de verdade (modo ligado)
-- daquela pessoa naquele dia foi enfileirada, respondida ou ficou sem resposta. cliente vence equipe; nenhum = null.
create or replace function public._agenda_dia_avisado(p_payee uuid, p_os uuid, p_dia date)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when p_os is not null and p_dia is not null
         and (public._agenda_cliente_ouviu(p_os, p_dia, now())
              or exists (select 1 from public.os_planejamento pl
                          where pl.service_order_id = p_os and pl.prometido_tipo = 'firme'
                            and p_dia between coalesce(pl.prometido_de, pl.prometido_ate) and pl.prometido_ate))
      then 'cliente'
    when p_payee is not null and p_dia is not null
         and exists (select 1 from public.agenda_equipe_mensagens m
                      where m.payee_id = p_payee and m.dia = p_dia and m.tipo in ('ficha', 'confirmar') and m.modo = 'ligado'
                        and m.estado in ('enfileirada', 'respondida', 'sem_resposta'))
      then 'equipe'
  end;
$function$;

comment on function public._agenda_dia_avisado(uuid, uuid, date) is
  'Agenda de Produção (Fase 7a, P1): o dia já dito — ''cliente'' (o cliente ouviu esse dia: _agenda_cliente_ouviu, ou o prometido firme de os_planejamento cobre o dia), ''equipe'' (a ficha ou a confirmação ligada da pessoa naquele dia foi enfileirada, respondida ou ficou sem resposta) ou null. cliente vence equipe. A zona travada do gestor (P8) e a saúde leem daqui.';

-- O gravador único do diário do gestor (§4.3): upsert de uma chave do dia (sombra, orcamentos, compras ou texto_sombra), com os
-- modos efetivos na hora; o valor de antes vai para o histórico quando muda (os 20 mais novos). Sem grant a ninguém.
create or replace function public._agenda_gestor_dia_gravar(p_dia date, p_chave text, p_valor jsonb, p_agora timestamptz)
 returns void
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_modos jsonb;
  v_antes jsonb;
  v_novo  jsonb := p_valor;
  r       public.agenda_gestor_dia;
begin
  if p_dia is null or p_agora is null then
    raise exception '_agenda_gestor_dia_gravar: sem o dia ou a hora.' using errcode = '22004';
  end if;
  if p_chave is null or p_chave <> all (array['sombra', 'orcamentos', 'compras', 'texto_sombra']) then
    raise exception '_agenda_gestor_dia_gravar: a chave "%" não existe.', p_chave using errcode = '22023';
  end if;
  if p_chave = 'sombra' and (v_novo is null or jsonb_typeof(v_novo) <> 'object') then
    raise exception '_agenda_gestor_dia_gravar: sombra é um objeto.' using errcode = '22023';
  end if;
  if p_chave in ('orcamentos', 'compras') and (v_novo is null or jsonb_typeof(v_novo) <> 'array') then
    raise exception '_agenda_gestor_dia_gravar: % é uma lista.', p_chave using errcode = '22023';
  end if;
  if p_chave = 'texto_sombra' and v_novo is not null and jsonb_typeof(v_novo) not in ('string', 'null') then
    raise exception '_agenda_gestor_dia_gravar: texto_sombra é um texto.' using errcode = '22023';
  end if;
  if p_chave = 'texto_sombra' and jsonb_typeof(v_novo) = 'null' then
    v_novo := null;
  end if;

  v_modos := jsonb_build_object('marcar', public._agenda_gestor_modo('marcar'), 'encaixe', public._agenda_gestor_modo('encaixe'),
                                'revisao', public._agenda_gestor_modo('revisao'),
                                'compre_ate', public._agenda_gestor_modo('compre_ate'),
                                'vaga', public._agenda_gestor_modo('vaga'),
                                'so_propor', (public._agenda_cfg()).gestor_so_propor);

  select * into r from public.agenda_gestor_dia where dia = p_dia for update;
  if not found then
    insert into public.agenda_gestor_dia (dia, calculado_em, modos, sombra, orcamentos, compras, texto_sombra)
    values (p_dia, p_agora, v_modos,
            case when p_chave = 'sombra' then v_novo else '{}'::jsonb end,
            case when p_chave = 'orcamentos' then v_novo else '[]'::jsonb end,
            case when p_chave = 'compras' then v_novo else '[]'::jsonb end,
            case when p_chave = 'texto_sombra' then v_novo #>> '{}' end);
    return;
  end if;

  v_antes := case p_chave when 'sombra' then r.sombra when 'orcamentos' then r.orcamentos when 'compras' then r.compras
                          else to_jsonb(r.texto_sombra) end;
  update public.agenda_gestor_dia
     set calculado_em = p_agora,
         modos = v_modos,
         sombra       = case when p_chave = 'sombra' then v_novo else sombra end,
         orcamentos   = case when p_chave = 'orcamentos' then v_novo else orcamentos end,
         compras      = case when p_chave = 'compras' then v_novo else compras end,
         texto_sombra = case when p_chave = 'texto_sombra' then v_novo #>> '{}' else texto_sombra end,
         historico    = case when v_antes is distinct from coalesce(v_novo, 'null'::jsonb)
                              and v_antes not in ('{}'::jsonb, '[]'::jsonb, 'null'::jsonb)
                             then (select coalesce(jsonb_agg(h order by o), '[]'::jsonb)
                                     from jsonb_array_elements(jsonb_build_array(jsonb_build_object('em', p_agora, 'chave', p_chave,
                                                                                                    'antes', v_antes))
                                                               || historico) with ordinality t(h, o)
                                    where o <= 20)
                             else historico end
   where dia = p_dia;
end;
$function$;

comment on function public._agenda_gestor_dia_gravar(date, text, jsonb, timestamptz) is
  'Agenda de Produção (Fase 7a, P1): o gravador único de agenda_gestor_dia — upsert da chave do dia (sombra: objeto; orcamentos e compras: lista; texto_sombra: texto ≤ 640), com os modos efetivos na hora; o valor de antes vai para o histórico quando muda (os 20 mais novos; o vazio não entra). Chave fora da lista = 22023. Security definer, sem grant a ninguém (nem service_role): só os passos do gestor o chamam.';

revoke all on function public._agenda_gestor_regra(text), public._agenda_gestor_modo(text),
  public._agenda_dia_avisado(uuid, uuid, date) from public, anon;
grant execute on function public._agenda_gestor_regra(text), public._agenda_gestor_modo(text),
  public._agenda_dia_avisado(uuid, uuid, date) to authenticated, service_role;
revoke all on function public._agenda_gestor_dia_gravar(date, text, jsonb, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public._agenda_alocacao_fonte() from public, anon, authenticated;

-- ── 10. O gatilho de antes da pergunta (corpo de 20261026100000:249-282, a mais nova), recriado ─────────────────
create or replace function public._agenda_perguntas_antes()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  -- (opções que não são lista: quem recusa é o CHECK da coluna)
  if jsonb_typeof(new.opcoes) = 'array' and jsonb_array_length(new.opcoes) > 0 then
    if new.recomendacao is not null
       and not exists (select 1 from jsonb_array_elements(new.opcoes) e where e ->> 'n' = new.recomendacao::text) then
      raise exception 'A recomendação tem de ser uma das opções da pergunta.';
    end if;
    if new.opcao_escolhida is not null
       and not exists (select 1 from jsonb_array_elements(new.opcoes) e where e ->> 'n' = new.opcao_escolhida::text) then
      raise exception 'Essa opção não existe nesta pergunta.';
    end if;
    -- FASE 7: a opção que vale sem resposta (AG7-15) também é uma das opções.
    if new.opcao_padrao is not null
       and not exists (select 1 from jsonb_array_elements(new.opcoes) e where e ->> 'n' = new.opcao_padrao::text) then
      raise exception 'A opção que vale sem resposta tem de ser uma das opções da pergunta.';
    end if;
    -- FASE 7: fim
  end if;
  if tg_op = 'UPDATE'
     and not public._agenda_so_mudou(to_jsonb(old) - 'critica', to_jsonb(new) - 'critica',
           case when old.estado = 'aberta'
                -- FASE 3: carona_em (a pergunta que foi junto de uma resposta) muda como o "mostrada".
                then array['estado', 'mostrada_vezes', 'mostrada_em', 'mostrada_via', 'respondida_em', 'respondida_por',
                           'respondida_via', 'opcao_escolhida', 'resposta', 'resolvida_motivo', 'expira_em', 'carona_em']
                     -- FASE 7: o prazo vai de nulo a um valor UMA vez, na pergunta aberta (quem mostra com o prazo escrito
                     -- grava: 7b e 7c); de um valor a outro, não (só o 7f, que recria esta função).
                     || case when old.veto_ate is null then array['veto_ate'] else '{}'::text[] end
                     -- FASE 7: fim
                else '{}'::text[] end,
           -- FASE 3: payee_id é ON DELETE SET NULL (apagar o favorecido deixa a pergunta com a pessoa nula).
           array['service_order_id', 'os_material_id', 'proposta_id', 'respondida_por', 'payee_id']) then
    if old.estado = 'aberta' then
      raise exception 'A pergunta não muda o que pergunta: só se mostra, se responde ou se resolve.';
    end if;
    raise exception 'A pergunta fechada não muda: a decisão registrada fica como foi.';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_perguntas_antes() is 'Agenda de Produção (Fase 2; Fase 3: carona_em e payee_id; Fase 7a: veto_ate e opcao_padrao): gatilho BEFORE INSERT/UPDATE — recomendação, opção escolhida e opção padrão são uma das opções; a pergunta só sai de aberta, com o que a mostra/responde/resolve (e a carona); o prazo vai de nulo a um valor uma vez, na aberta; fechada não muda.';

-- ── 11. O modo de quem faz cada tipo de pergunta (corpo de 20261030100500:1329, a mais nova), recriado ──────────
-- O lote de 30/10 fechou a regra "todo tipo da lista fechada tem o modo de quem o faz" (a limpeza da vigia fecha a pergunta aberta
-- em sombra quando este modo está ligado; agenda_correcao_2910_p3.sql S4 cobra). Os 13 tipos novos da seção 5 entram aqui.
create or replace function public._agenda_modo_da_pergunta(p_tipo text, p_chave text)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when p_tipo in ('nao_cabe', 'segundo_atraso', 'atraso_longo', 'remarcar_confirmado', 'fixada_pelo_dono') then c.modo_proposta
    when p_tipo = 'chegou' and coalesce(p_chave, '') like 'chegou:fornecedor:%' then c.modo_material
    -- CORREÇÃO 29/10 (revisão): a equipe sem dias é da vigia.
    when p_tipo = 'equipe_sem_dias' then c.modo_vigia
    -- CORREÇÃO 29/10 (revisão): fim
    when p_tipo in ('conferencia', 'chegou', 'parada', 'estouro', 'duracao', 'material_conferir', 'padrao_do_dono', 'entrega')
      then c.modo_vigia
    when p_tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo')
      then c.modo_material
    when p_tipo in ('diaria', 'diaria_ligar') then c.modo_diaria
    when p_tipo in ('equipe_resposta', 'concluir') then c.modo_equipe
    when p_tipo in ('cliente_aprovar', 'cliente_aviso', 'cliente_resposta') then c.modo_cliente
    when p_tipo = 'aprendizado' then c.modo_aprendizado
    -- FASE 7: os tipos do gestor da agenda (7a P1). O dia avisado e o prometido são críticas do plano, como o remarcar
    -- confirmado; a revisão diária faz reavaliar e reestimar; a cobrança do "compre até", a dela; o resto é do gestor que marca.
    when p_tipo in ('dia_avisado', 'dia_prometido') then c.modo_proposta
    when p_tipo in ('reavaliar', 'reestimar') then public._agenda_gestor_modo('revisao')
    when p_tipo = 'compre_ate' then public._agenda_gestor_modo('compre_ate')
    when p_tipo in ('situacao', 'estimativa', 'equipe_cadastro', 'ficha_estimativa', 'bem_livre', 'sinal', 'onda', 'sabado')
      then public._agenda_gestor_modo('marcar')
    -- FASE 7: fim
  end
    from public.agenda_config c
   where c.id;
$function$;

comment on function public._agenda_modo_da_pergunta(text, text) is
  'Agenda de Produção (correção de 29/10, P3): o modo de agenda_config de quem grava cada tipo de pergunta — críticas do plano: modo_proposta; conferencia, chegou, parada, estouro, duracao, material_conferir, padrao_do_dono, entrega: modo_vigia; chegou:fornecedor:…, nfe_vincular, pix_material, previsao_fornecedor, fornecedor_cadastro, fornecedores_prazo: modo_material; diaria, diaria_ligar: modo_diaria; equipe_resposta, concluir: modo_equipe; cliente_*: modo_cliente; aprendizado: modo_aprendizado; outro tipo: null. A limpeza da vigia fecha a pergunta aberta em sombra quando este modo está ligado. STABLE, invoker, só o service_role. CORREÇÃO 29/10 (revisão): o tipo novo equipe_sem_dias é da vigia (modo_vigia). Fase 7a (P1): dia_avisado e dia_prometido = modo_proposta (críticas do plano); reavaliar e reestimar = o modo da revisão do gestor; compre_ate = o da cobrança; situacao, estimativa, equipe_cadastro, ficha_estimativa, bem_livre, sinal, onda e sabado = o do gestor que marca (_agenda_gestor_modo).';

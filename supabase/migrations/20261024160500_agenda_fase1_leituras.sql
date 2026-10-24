-- Agenda de Produção, Fase 1 ("O que eu tenho que fazer"), pacote P4: as leituras com TEXTO PRONTO que o dono lê.
-- Spec: scratchpad agenda-pesquisa/spec-fase1.md (§3, §5.5, §6). Plano: plano-final.md §5; revisão §13–§14.
-- Depende de 20261024160000 (tabelas), 160100 (calendário e textos curtos), 160200 (semente), 160300 (material) e
-- 160400 (carteira, prontidão e capacidade).
--
-- ═══ DDL — OK NOMEADO ═══ (só funções novas de LEITURA; nenhuma tabela, nenhum dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: o modelo nunca calcula data, duração nem capacidade, e nunca escreve a frase que tem número. O texto que o
-- dono lê ("como tá a semana?", "o que eu tenho que fazer?", "o que está atrasado?", "quando fica livre?", "o que o
-- Roberto faz amanhã?", "se o César aprovar, quando dá?") sai PRONTO daqui, em pt-BR curto, sem jargão, com as datas
-- por _dia_curto e um número de capacidade só. A ferramenta (agenda_ver, P5) e os comandos sem IA (P6) só repassam.
--
-- O QUE MUDA (todas STABLE, security invoker, search_path fixo, p_hoje em todas; nenhuma grava; leitura que falha
-- LANÇA — nunca vira "livre" nem "nada"):
--   1. agenda_semana(p_de, p_ate, p_hoje): o marcado no período (janela antiga + compromisso com hora do dono), o
--      aviso de diárias faltando, a fila em faixa ("há 7 serviços aprovados, uns 17 a 32 dias de equipe — de 3 a 6
--      semanas no ritmo de ~5,4 diárias de equipe por semana… sem contar você"), prontos / quase / travados por
--      material / esperando você / parados no cliente, "livre de verdade" (n = ceil(fila ÷ capacidade diária);
--      livre = agenda_somar_du(p_hoje, n + 1)) e a oferta da rodada. "Sem marcação" nunca vira "livre".
--      dados.textos traz as partes (marcados, aviso, resumo, prontos, travados, esperando, parados, livre, oferta).
--   2. agenda_o_que_fazer(p_payee, p_hoje): os 5 blocos — Hoje · Travado esperando você (sinal pago primeiro,
--      depois orçamento aprovado, depois o resto; até 5 e "e mais N") · Prontos sem data e os próximos 7 dias · Em
--      risco · Outras pendências com a MESMA regra de my_agenda (tarefas pending/in_progress do login com âncora
--      due_at ou scheduled_start_at antes do dia = atrasadas, no dia = de hoje; a receber e a pagar pending/
--      partially_paid com vencimento hoje, valor = saldo ou valor) — e a oferta da rodada.
--   3. agenda_atrasos(p_hoje): prazo efetivo vencido (o padrão de prazo_padrao_du dias úteis desde a aprovação, ou o
--      que o cliente disse), em risco (razão crítica < 1), previsão de material vencida, janela antiga que passou
--      sem a OS começar (a "promessa" da Fase 1; prometido_* é da Fase 5). Fora: parados no cliente e em espera.
--   4. agenda_ver_material(p_so_id, p_hoje): por OS, cada item com a situação, a previsão com a fonte e as palavras
--      do dono ('você disse em 23/10: "o painel chega dia 3"'), "você ainda não me disse que chegou" quando a
--      previsão chegou e nada foi dito, "pode começar sem" e o início pelo material. Sem OS: uma linha por serviço
--      com material pendente.
--   5. agenda_dia_da_pessoa(p_payee, p_dia, p_hoje): o marcado da pessoa (técnico da OS, compromisso), a situação do
--      dia (sábado só quando vocês combinam, feriado, não vem) e o padrão ("costuma vir de seg a sex").
--   6. agenda_aprontar(p_hoje): a rodada — até 5 OS, uma pergunta por OS juntando o que falta do dono e a duração
--      com o chute do banco entre parênteses, e "Você: semana que vem fica em campo quais dias?".
--   7. agenda_simular(p_dias, p_com_quem, p_dono, p_autor, p_hoje): serviço hipotético — no fim da fila (a faixa do
--      livre) ou passando na frente (agenda_somar_du(p_hoje, congelamento_du + 1); o resto atrasa ceil(diárias ÷
--      capacidade diária) dias úteis). "É projeção: não reserva nada."
--   8. agenda_ctp(p_so_id, p_hoje): "se o cliente aprovar hoje" — duração, o que falta comprar, o início pela fila e
--      não antes do material, e a frase ao cliente CONDICIONAL enquanto o material não está na mão (d09).
--   9. agenda_textos_do_fechamento(p_hoje, p_dia): a cauda do "Amanhã" do fechamento 17:30 e, só no dia_do_plano,
--      até 3 linhas "Semana que vem (projeção)" de até 160 caracteres. Com modo_leitura desligado, nada.
--  10. agenda_ver(p_autor, p_periodo, p_pessoa, p_foco, p_os, p_simular, p_simular_aprovacao, p_hoje): o despacho
--      ÚNICO da ferramenta e dos comandos. Referência que não existe → {ok:false, texto:"Não encontrei …"} (nunca
--      erro cru); foco fora da lista LANÇA (é erro de quem chamou, não do dono).
--   Auxiliares: _agenda_maiuscula, _agenda_num, _agenda_plural, _agenda_corta, _agenda_dia_rotulo,
--   _agenda_periodo_rotulo, _agenda_periodo, _agenda_rotulo, _agenda_nomes ("Kalmar ×2, Rodrigo (OS-00076) e MP
--   ORÇ-00095 (sinal)"), _agenda_restricao_curta, _agenda_juntar e _agenda_encolher/_agenda_lim/_agenda_linhas (o
--   corte), _agenda_marcados, _agenda_painel (a carteira lida UMA vez por resposta), _agenda_lista_de,
--   _agenda_fila_faixa, _agenda_resumo, _agenda_livre_linha, _agenda_outras (o 5º bloco), _agenda_semana_de,
--   _agenda_o_que_fazer_de, _agenda_atrasos_de, _agenda_aprontar_de, _agenda_dia_de, _agenda_material_resumo,
--   _agenda_ver_os.
--
-- TEXTO ≤ agenda_config.texto_max: cada lista mostra até 5 e "e mais N"; se passar, a lista da linha mais longa perde
-- um nome por vez (semana e "o que fazer"; nas outras, todas as listas juntas), e só no fim saem linhas inteiras do
-- fim (com "(e mais N linhas)"). Nunca corta no meio de uma linha. Na fixture a semana dá 993 de 1000.
--
-- CORREÇÕES SOBRE A SPEC (§6 é o alvo; o teste fixa o que estas funções devolvem, byte a byte):
--   · o nome do item é o da prontidão (P3: 3 palavras e "…", '"Compressor 12V de…" chegou?'), não "o compressor"/
--     "o Cerbo GX"/"o painel 7"" da spec: esses foram escritos à mão e não saem de regra nenhuma. Entre parênteses,
--     na semana, vai só a 1ª palavra do item ("Flávio (compressor chegou?)"): com o nome de 3 palavras a semana da
--     fixture passava de 1000 e o corte escondia o Giancarlo.
--   · "Outras pendências" conta sem o .limit(200)/.limit(20) de my_agenda (lá é tamanho de página, não regra).
--   · sem artigo nem pronome de gênero antes do nome de pessoa ("Amanhã (sáb 24/10), Roberto não tem nada marcado",
--     "com você e Roberto", "se o cliente aprovar hoje", "Para o cliente:"): o banco não sabe se é "o" ou "a".
--   · listas sempre com "e" no fim ("A, B e C"), como _agenda_lista; a spec misturava vírgula pura e "e".
--   · Robson antes de Rodrigo no "ficam para depois" (é a ordem do bloco 2: orçamento aprovado antes do resto); a
--     spec os trocou. O "Tudo de uma vez ou por partes?" do Giancarlo não tem fonte no banco (sem escopo em aberto):
--     não sai. A duração pergunta sempre "Quantos dias e com quem?".
--   · bloco 2: a frase é o texto da restrição mais forte da prontidão (P3), salvo "tem peça a comprar?" (a pergunta,
--     sem o parêntese); a peça embutida sai com as 2 linhas e "(e mais N)", como a prontidão pergunta.
--   · "você ainda não me disse que chegou" só quando a data prevista já chegou (hoje ou antes): antes disso a
--     previsão do dono não está vencida e a frase seria cobrança fora de hora.
--
-- REVISÃO DA FASE 1 (24/10, provadas nos mesmos testes):
--   · "o que o João faz segunda?": quem tem padrão em outros dias ouve "às segundas não costuma vir"; o "não sei se
--     vem" fica para quem não tem padrão nenhum.
--   · agenda_simular: só de manhã ou só à tarde = 1 meio-dia por dia ocupado (a mesma conta de os_prontidao).
--   · agenda_ver com modo_leitura desligado devolve {ok:false, desligada:true}: a ferramenta manda o modelo voltar à
--     my_agenda (desligar devolve a agenda de antes).
--   · "você disse em DD/MM" do material sai de os_material.conferido_em (quando o dono informou), não de
--     atualizado_em (que a sincronização também regrava). A compra combinada sem prazo (compra_sem_prazo) entra no
--     resumo do material e na restrição curta.
--   · orçamento aprovado que nunca virou OS: o material dele diz "converter em OS ou arquivar antes de comprar (2
--     itens a comprar)" (a lista de material e a visão da OS), em vez de mandar comprar.
--   · a prioridade que o dono deu (os_planejamento.prioridade_manual: 1 = passa na frente) é a 1ª chave da ordem de
--     trabalho do painel (bloco 2, rodada, listas); sem prioridade, depois de todas.
--   · a visão da OS: "Duração: sem base para estimar: quantos dias?" sem o ponto depois do "?".
--
-- O QUE NÃO MUDA: nenhuma tabela, nenhum dado, nenhuma função de P1–P3, my_agenda, o Secretário, as telas.
--
-- ORDEM DE LIGAR: depois de 20261024160000..160400; antes das ferramentas (P5), dos comandos e do fechamento (P6).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase1_leituras.sql (begin/rollback; com a fixture de 23/10 os
-- textos da spec §6 byte a byte; sem a fixture, só as regras gerais e as portas). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261024160500
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261024160500_agenda_fase1_leituras.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261024160500', 'agenda_fase1_leituras');"
--
-- IDEMPOTENTE: só create or replace function, revoke/grant e comment.

-- ── 0. Auxiliares de texto ──────────────────────────────────────────────────────────────────────────────

-- 1ª letra maiúscula, sem depender do locale para as acentuadas.
create or replace function public._agenda_maiuscula(p_texto text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when coalesce(p_texto, '') = '' then p_texto
              else translate(upper(left(p_texto, 1)), 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ')
                   || substr(p_texto, 2) end;
$function$;

comment on function public._agenda_maiuscula(text) is 'Agenda de Produção (Fase 1, P4): a 1ª letra em maiúscula ("tem peça…" → "Tem peça…").';

-- 5,41 → "5,4"; 2 → "2".
create or replace function public._agenda_num(p numeric, p_casas integer default 1)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select replace(trim_scale(round(p, p_casas))::text, '.', ',');
$function$;

comment on function public._agenda_num(numeric, integer) is 'Agenda de Produção (Fase 1, P4): o número com vírgula e as casas pedidas, sem zero à direita (5,41 → "5,4").';

-- "1 tarefa", "3 tarefas".
create or replace function public._agenda_plural(p_n integer, p_um text, p_varios text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select p_n::text || ' ' || case when p_n = 1 then p_um else p_varios end;
$function$;

comment on function public._agenda_plural(integer, text, text) is 'Agenda de Produção (Fase 1, P4): "1 tarefa", "3 tarefas".';

-- Corta um texto solto (título de compromisso, palavras do dono) na palavra, com "…".
create or replace function public._agenda_corta(p_texto text, p_max integer)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when p_texto is null then null
              when char_length(btrim(p_texto)) <= p_max then btrim(p_texto)
              else regexp_replace(regexp_replace(left(btrim(p_texto), p_max), '\s+\S*$', ''), '[[:space:],;:.(–—-]+$', '') || '…' end;
$function$;

comment on function public._agenda_corta(text, integer) is 'Agenda de Produção (Fase 1, P4): o texto até p_max caracteres, cortado na palavra, com "…".';

-- "Hoje (sex 23/10)", "Amanhã (sáb 24/10)", "Seg 26/10".
create or replace function public._agenda_dia_rotulo(p_dia date, p_hoje date)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when p_dia = p_hoje then 'Hoje (' || public._dia_curto(p_dia) || ')'
              when p_dia = p_hoje + 1 then 'Amanhã (' || public._dia_curto(p_dia) || ')'
              else public._agenda_maiuscula(public._dia_curto(p_dia)) end;
$function$;

comment on function public._agenda_dia_rotulo(date, date) is 'Agenda de Produção (Fase 1, P4): "Hoje (sex 23/10)", "Amanhã (sáb 24/10)" ou "Seg 26/10".';

-- "Esta semana (seg 19/10 a sáb 24/10)", "A semana que vem (seg 26/10 a sáb 31/10)", "De seg 26/10 a qua 28/10".
create or replace function public._agenda_periodo_rotulo(p_de date, p_ate date, p_hoje date)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  with s as (select p_hoje - (extract(isodow from p_hoje)::int - 1) as seg)
  select case
    when p_de = p_ate then public._agenda_dia_rotulo(p_de, p_hoje)
    when p_de = s.seg and p_ate in (s.seg + 4, s.seg + 5) then
      format('Esta semana (%s a %s)', public._dia_curto(p_de), public._dia_curto(p_ate))
    when p_de = s.seg + 7 and p_ate in (s.seg + 11, s.seg + 12) then
      format('A semana que vem (%s a %s)', public._dia_curto(p_de), public._dia_curto(p_ate))
    else format('De %s a %s', public._dia_curto(p_de), public._dia_curto(p_ate)) end
    from s;
$function$;

comment on function public._agenda_periodo_rotulo(date, date, date) is 'Agenda de Produção (Fase 1, P4): o nome do período ("Esta semana (seg 19/10 a sáb 24/10)", "A semana que vem (…)", "De … a …", ou o dia).';

-- O período que a ferramenta/o comando pediu: hoje, amanhã, semana (seg–sáb desta), próxima semana (seg–sáb da que
-- vem) ou o que o dono disse (agenda_data_dita, futuro: "segunda", "26/10 a 30/10"). Nada → (null, null). Data que não
-- dá para entender LANÇA 22007 com a frase ao dono (agenda_ver devolve a frase).
create or replace function public._agenda_periodo(p_periodo text, p_hoje date)
 returns table (de date, ate date)
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v   text := btrim(replace(public._agenda_normal(p_periodo), '_', ' '));
  seg date := p_hoje - (extract(isodow from p_hoje)::int - 1);
  d   jsonb;
begin
  if coalesce(v, '') = '' then
    de := null; ate := null;
  elsif v = 'hoje' then
    de := p_hoje; ate := p_hoje;
  elsif v in ('amanha', 'pra amanha', 'de amanha') then
    de := p_hoje + 1; ate := p_hoje + 1;
  elsif v in ('semana', 'esta semana', 'essa semana', 'nesta semana', 'nessa semana', 'a semana', 'da semana') then
    de := seg; ate := seg + 5;
  elsif v in ('proxima semana', 'semana que vem', 'a semana que vem', 'a proxima semana', 'da semana que vem',
              'da proxima semana', 'semana seguinte') then
    de := seg + 7; ate := seg + 12;
  else
    d := public.agenda_data_dita(p_periodo, p_hoje, 'futuro');
    de := (d ->> 'de')::date; ate := (d ->> 'ate')::date;
  end if;
  return next;
end;
$function$;

comment on function public._agenda_periodo(text, date) is 'Agenda de Produção (Fase 1, P4): o período pedido — hoje, amanha, semana (seg–sáb desta), proxima_semana (seg–sáb da que vem) ou o que o dono disse por agenda_data_dita (futuro). Vazio = (null, null). Data incompreensível lança 22007 com a frase ao dono.';

-- O nome de uma OS numa lista. p_o = {curto, numero, eh_orc, n_nome}; n_nome = quantas OS da carteira têm o mesmo
-- nome curto. Modo 'normal': "Lenine", "Rodrigo (OS-00096)", "Robson ORÇ-00083"; 'np' (vai seguido de parêntese):
-- "Rodrigo OS-00096"; 'num' (a rodada): "Lenine (OS-00074)".
create or replace function public._agenda_rotulo(p_o jsonb, p_modo text default 'normal')
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when coalesce(p_o ->> 'curto', '') = '' then p_o ->> 'numero'
    when p_modo = 'num' then format('%s (%s)', p_o ->> 'curto', p_o ->> 'numero')
    when coalesce((p_o ->> 'eh_orc')::boolean, false) then format('%s %s', p_o ->> 'curto', p_o ->> 'numero')
    when coalesce((p_o ->> 'n_nome')::int, 1) > 1 then
      case when p_modo = 'np' then format('%s %s', p_o ->> 'curto', p_o ->> 'numero')
           else format('%s (%s)', p_o ->> 'curto', p_o ->> 'numero') end
    else p_o ->> 'curto' end;
$function$;

comment on function public._agenda_rotulo(jsonb, text) is 'Agenda de Produção (Fase 1, P4): o nome da OS numa lista — o nome curto, com o número só quando o nome se repete na carteira ou é orçamento ("Rodrigo (OS-00096)", "Robson ORÇ-00083"); modo np (antes de parêntese) e num (sempre o número).';

-- A lista de OS de uma linha: p_itens = [{o, sufixo}] na ordem. As OS de um nome que se repete e que estão TODAS aqui
-- com o mesmo sufixo viram uma só ("Kalmar ×2"); com sufixo, o nome vai sem parêntese ("MP ORÇ-00095 (sinal)").
-- Até p_k itens e "e mais N".
create or replace function public._agenda_nomes(p_itens jsonb, p_k integer, p_modo text default 'normal')
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  with it as (
    select t.e, t.o,
           case when coalesce((t.e -> 'o' ->> 'eh_orc')::boolean, false) or coalesce(t.e -> 'o' ->> 'curto', '') = ''
                then 'n:' || (t.e -> 'o' ->> 'numero')
                else 'c:' || public._agenda_normal(t.e -> 'o' ->> 'curto') || '|' || coalesce(t.e ->> 'sufixo', '') end as chave
      from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) with ordinality t(e, o)
  ),
  g as (
    select it.chave, min(it.o) as primeiro, count(*) as n, (array_agg(it.e order by it.o))[1] as um
      from it group by it.chave
  ),
  junto as (
    select g.* from g
     where g.chave like 'c:%' and g.n >= 2 and g.n = coalesce((g.um -> 'o' ->> 'n_nome')::int, 1)
  ),
  saida as (
    select j.primeiro as o,
           format('%s ×%s', j.um -> 'o' ->> 'curto', j.n) || coalesce(' (' || (j.um ->> 'sufixo') || ')', '') as txt
      from junto j
    union all
    select it.o,
           case when it.e ->> 'sufixo' is null then public._agenda_rotulo(it.e -> 'o', p_modo)
                else public._agenda_rotulo(it.e -> 'o', case when p_modo = 'num' then 'num' else 'np' end)
                     || ' (' || (it.e ->> 'sufixo') || ')' end
      from it where it.chave not in (select j.chave from junto j)
  )
  select public._agenda_lista(array(select s.txt from saida s order by s.o), p_k);
$function$;

comment on function public._agenda_nomes(jsonb, integer, text) is 'Agenda de Produção (Fase 1, P4): a lista de OS de uma linha ([{o, sufixo}]) — "Kalmar ×2" quando todas as OS do nome estão ali com o mesmo sufixo; sufixo entre parênteses depois do nome; até p_k e "e mais N".';

-- A restrição em poucas palavras, para ir entre parênteses depois do nome ("Vanderlei (4 itens a comprar)",
-- "Flávio (compressor chegou?)": do item, só a 1ª palavra, em minúscula; sigla de até 3 letras fica).
create or replace function public._agenda_restricao_curta(p_r jsonb)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  with w0 as (select (regexp_match(coalesce(p_r ->> 'pergunta', ''), '"([^" …]+)'))[1] as palavra),
  w as (select case when w0.palavra ~ '^[A-ZÀ-Þ]{1,3}$' then w0.palavra
                    else translate(lower(w0.palavra), 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ', 'áàâãäéèêëíìîïóòôõöúùûüçñ') end as palavra
          from w0)
  select case p_r ->> 'tipo'
    when 'sem_previsao' then regexp_replace(p_r ->> 'texto', '(: | \().*$', '')
    when 'compre_ate' then coalesce((regexp_match(p_r ->> 'texto', '(compre até .*|comprando hoje.*)$'))[1], p_r ->> 'texto')
    when 'comprado_sem_previsao' then coalesce(w.palavra || ' chegou?', p_r ->> 'pergunta')
    when 'compra_sem_prazo' then p_r ->> 'pergunta'
    when 'atrasado' then coalesce(w.palavra || ' chegou? (a previsão venceu)', p_r ->> 'pergunta')
    when 'peca_embutida' then 'tem peça embutida?'
    when 'material_nao_conferido' then 'tem peça a comprar?'
    when 'orcamento' then replace(regexp_replace(p_r ->> 'texto', ': converter ou arquivar\?$', ''), ' e nunca virou', ', nunca virou')
    when 'escopo' then 'falta decidir: ' || (p_r ->> 'texto')
    when 'parada' then 'parou?'
    when 'sinal' then 'sinal'
    else p_r ->> 'texto' end
    from w;
$function$;

comment on function public._agenda_restricao_curta(jsonb) is 'Agenda de Produção (Fase 1, P4): a restrição da prontidão em poucas palavras ("4 itens a comprar", "tem peça embutida?", "assinado em 23/08, nunca virou OS").';

-- Junta as linhas e garante o teto: passou de p_max, saem linhas inteiras do fim (nunca a 1ª), e a última diz
-- quantas ficaram de fora. Nunca corta no meio de uma linha.
create or replace function public._agenda_juntar(p_linhas text[], p_max integer)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v   text[] := array(select x from unnest(coalesce(p_linhas, '{}'::text[])) with ordinality u(x, o)
                       where nullif(btrim(x), '') is not null order by o);
  n   int := cardinality(v);
  k   int;
  v_t text;
begin
  if n = 0 then return ''; end if;
  v_t := array_to_string(v, E'\n');
  if p_max is null or char_length(v_t) <= p_max then return v_t; end if;
  for k in reverse n - 1 .. 1 loop
    v_t := array_to_string(v[1:k], E'\n') || E'\n' || format('(e mais %s %s)', n - k, case when n - k = 1 then 'linha' else 'linhas' end);
    if char_length(v_t) <= p_max then return v_t; end if;
  end loop;
  return v[1];
end;
$function$;

comment on function public._agenda_juntar(text[], integer) is 'Agenda de Produção (Fase 1, P4): junta as linhas (sem as vazias); se passar de p_max, tira linhas inteiras do fim e diz "(e mais N linhas)". Nunca corta no meio da linha.';

-- ── 1. O que está marcado num período ───────────────────────────────────────────────────────────────────

-- As janelas antigas (scheduled_*) das OS da carteira que cruzam [p_de, p_ate] — só as que têm p_tecnico como técnico,
-- se vier — e os compromissos com hora (agenda_tasks pending/in_progress com scheduled_start_at) de p_usuario.
-- Cada item: {tipo, de, ate, hora, nome, o, texto_semana ("ter 27/10 08:00 Lenine", "Flávio (OS-00104) de ter 06/10 a
-- qui 08/10"), texto_dia ("08:00 Lenine", "Flávio (OS-00104) (continua, até qui 08/10)")}, na ordem do dia e da hora.
create or replace function public._agenda_marcados(p_de date, p_ate date, p_hoje date, p_tecnico uuid default null,
                                                   p_usuario uuid default null)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with
  k as (
    select k.*, count(*) over (partition by public._agenda_normal(k.cliente_curto)) as n_nome
      from public.os_carteira(p_hoje) k
  ),
  itens as (
    select 'os'::text as tipo, k.agendada_de as de, coalesce(k.agendada_ate, k.agendada_de) as ate,
           case when k.agendada_de >= p_de and so.scheduled_start_at is not null
                then to_char(so.scheduled_start_at at time zone 'America/Sao_Paulo', 'HH24:MI') end as hora,
           -- sem parêntese no nome ("Rodrigo OS-00096"): o dia e a hora vão entre parênteses depois dele
           public._agenda_rotulo(jsonb_build_object('curto', k.cliente_curto, 'numero', k.numero,
                                                    'eh_orc', k.eh_orcamento, 'n_nome', k.n_nome), 'np') as nome,
           jsonb_build_object('curto', k.cliente_curto, 'numero', k.numero, 'eh_orc', k.eh_orcamento, 'n_nome', k.n_nome,
                              'os', k.service_order_id) as o,
           k.numero as chave
      from k
      join public.service_orders so on so.id = k.service_order_id
     where k.agendada_de is not null and k.agendada_de <= p_ate and coalesce(k.agendada_ate, k.agendada_de) >= p_de
       and (p_tecnico is null or exists (select 1 from public.service_order_technicians st
                                          where st.service_order_id = k.service_order_id and st.user_id = p_tecnico))
    union all
    select 'compromisso', (t.scheduled_start_at at time zone 'America/Sao_Paulo')::date,
           (coalesce(t.scheduled_end_at, t.scheduled_start_at) at time zone 'America/Sao_Paulo')::date,
           case when not t.all_day and (t.scheduled_start_at at time zone 'America/Sao_Paulo')::date >= p_de
                then to_char(t.scheduled_start_at at time zone 'America/Sao_Paulo', 'HH24:MI') end,
           public._agenda_corta(t.title, 40), null, t.id::text
      from public.agenda_tasks t
     where p_usuario is not null and t.assignee_user_id = p_usuario
       and t.status in ('pending', 'in_progress') and t.scheduled_start_at is not null
       and (t.scheduled_start_at at time zone 'America/Sao_Paulo')::date <= p_ate
       and (coalesce(t.scheduled_end_at, t.scheduled_start_at) at time zone 'America/Sao_Paulo')::date >= p_de
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'tipo', i.tipo, 'de', i.de, 'ate', i.ate, 'hora', i.hora, 'nome', i.nome, 'o', i.o,
           'texto_semana', case when i.de = i.ate
                                then format('%s (%s%s)', i.nome, public._dia_curto(i.de), coalesce(' às ' || i.hora, ''))
                                else format('%s de %s a %s', i.nome, public._dia_curto(i.de), public._dia_curto(i.ate)) end,
           'texto_dia', case when i.de >= p_de
                             then i.nome || coalesce(' às ' || i.hora, '')
                                  || case when i.ate > i.de then ' (até ' || public._dia_curto(i.ate) || ')' else '' end
                             else i.nome || case when i.ate > p_ate then ' (continua, até ' || public._dia_curto(i.ate) || ')'
                                                 else ' (último dia)' end end)
           order by greatest(i.de, p_de), i.hora nulls first, i.tipo desc, i.chave), '[]'::jsonb)
    from itens i;
$function$;

comment on function public._agenda_marcados(date, date, date, uuid, uuid) is 'Agenda de Produção (Fase 1, P4): o que está marcado em [p_de, p_ate] — as janelas antigas (scheduled_*) das OS da carteira (só as de p_tecnico, se vier) e os compromissos com hora de p_usuario (agenda_tasks pending/in_progress com scheduled_start_at) — com o texto da semana ("Reunião… (sex 23/10 às 14:00)", "Lenine de ter 27/10 a qua 28/10") e o do dia ("Lenine às 08:00 (até qua 28/10)").';

-- ── 2. A carteira lida uma vez por resposta ─────────────────────────────────────────────────────────────

-- Tudo o que os textos usam, lido UMA vez: a capacidade (o único número), a prontidão de cada OS da carteira com o que
-- os textos derivam dela (grupo, ordem, restrição principal do dono, atrasada, em risco, data marcada vencida, nome),
-- a fila executável em diárias-pessoa e o "livre de verdade" em faixa. Não é texto: é o insumo dos textos.
--
-- Ordem de trabalho (bloco 2, rodada, listas da semana): sinal pago primeiro, depois orçamento aprovado (assinado
-- e nunca convertido), depois o resto; em cada grupo a aprovação mais antiga primeiro. Ordem de atraso: a aprovação
-- mais antiga primeiro.
-- Executável = tudo menos em espera (congelada), parado no cliente (aguardando_cliente) e sem sinal.
create or replace function public._agenda_painel(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c          public.agenda_config := public._agenda_cfg();
  v_cap      jsonb;
  v_dono     uuid := public._agenda_dono(null);
  v_usuario  uuid;
  v_du       int := case when c.sabado_util then 6 else 5 end;
  v_comp     numeric;
  v_cdia     numeric;
  v_oss      jsonb;
  v_padrao   boolean;
  v_n        int;
  v_ot       numeric;
  v_re       numeric;
  v_sb       int;
  v_compra   boolean;
  v_livre    jsonb;
  v_aviso    text;
  v_oferta   boolean;
begin
  if p_hoje is null then
    raise exception 'agenda: sem o dia de hoje' using errcode = '22004';
  end if;

  v_cap := public.agenda_capacidade_semanal(p_hoje);
  v_comp := coalesce((v_cap ->> 'comprometivel')::numeric, 0);
  v_cdia := v_comp / v_du;
  select py.app_user_id into v_usuario from public.payees py where py.id = v_dono;
  v_padrao := exists (select 1 from public.agenda_disponibilidade d
                       where d.payee_id = v_dono and d.substituida_em is null and d.dias_semana is not null
                         and d.situacao in ('disponivel', 'confirmada'));

  with
  pr as (
    select x.p, x.ord from public.os_prontidao_carteira(p_hoje) with ordinality x(p, ord)
  ),
  b as (
    select pr.p, pr.ord, so.signed_at, so.status as st, so.quote_status as qs,
           k.sinal_pago, k.aprovada_em, k.agendada_de, k.agendada_ate, pl.prioridade_manual as prioridade,
           count(*) over (partition by public._agenda_normal(pr.p ->> 'cliente_curto')) as n_nome,
           (select e from jsonb_array_elements(pr.p -> 'restricoes') with ordinality t(e, o)
             where (e ->> 'bloqueia')::boolean and e ->> 'quem' = 'dono' order by o limit 1) as principal,
           coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(pr.p -> 'restricoes') with ordinality t(e, o)
                      where e ->> 'quem' = 'dono'), '[]'::jsonb) as restr_dono,
           exists (select 1 from jsonb_array_elements(pr.p #> '{material,itens}') e
                    where (e ->> 'critico')::boolean and e ->> 'nivel' <> 'A') as mat_falta,
           (pr.p ->> 'estado') not in ('congelada', 'aguardando_cliente', 'sem_sinal', 'concluida', 'fora_da_carteira') as exe
      from pr
      join public.os_carteira(p_hoje) k on k.service_order_id = (pr.p ->> 'os')::uuid
      join public.service_orders so on so.id = k.service_order_id
      left join public.os_planejamento pl on pl.service_order_id = k.service_order_id
  ),
  o as (
    -- A ordem de trabalho: a prioridade que o dono deu ("passa na frente" = 1; sem prioridade, depois de todas), depois
    -- sinal pago, orçamento aprovado e a aprovação mais antiga.
    select b.*,
           row_number() over (order by coalesce(b.prioridade, 9), (b.sinal_pago > 0) desc,
                                       (b.st = 'draft' and b.qs = 'approved') desc,
                                       b.aprovada_em, b.p ->> 'numero' collate "C") as ordem,
           row_number() over (order by b.aprovada_em, b.p ->> 'numero' collate "C") as ordem_aprov
      from b
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'os', o.p ->> 'os', 'numero', o.p ->> 'numero', 'curto', o.p ->> 'cliente_curto',
           'eh_orc', (o.p ->> 'eh_orcamento')::boolean, 'n_nome', o.n_nome, 'status', o.st,
           'estado', o.p ->> 'estado', 'estado_texto', o.p ->> 'estado_texto',
           'quase', coalesce((o.p ->> 'quase_pronta')::boolean, false),
           'grupo', case o.p ->> 'estado'
                      when 'pronta' then 'pronto'
                      when 'aguardando_material' then
                        case when coalesce((o.p ->> 'quase_pronta')::boolean, false) then 'quase' else 'travado' end
                      when 'esperando_voce' then 'esperando'
                      when 'aguardando_cliente' then 'parado'
                      when 'sem_sinal' then 'parado'
                      when 'marcada' then 'marcado'
                      when 'em_execucao' then 'andamento'
                      when 'parada' then 'andamento'
                      when 'congelada' then 'espera'
                      else 'fora' end,
           'executavel', o.exe, 'ordem', o.ordem, 'ordem_aprov', o.ordem_aprov, 'prioridade', o.prioridade,
           'aprovada_em', o.aprovada_em, 'assinado', o.signed_at is not null, 'sinal_pago', o.sinal_pago,
           'prazo', o.p -> 'prazo_efetivo', 'prazo_fonte', o.p ->> 'prazo_fonte', 'razao', o.p -> 'razao_critica',
           'atrasada', o.exe and (o.p ->> 'prazo_efetivo')::date < p_hoje,
           'em_risco', o.exe and (o.p ->> 'prazo_efetivo')::date >= p_hoje and (o.p ->> 'razao_critica')::numeric < 1,
           'agendada_de', o.agendada_de, 'agendada_ate', o.agendada_ate,
           'data_vencida', o.exe and o.agendada_ate < p_hoje and o.st <> 'in_progress',
           'principal', o.principal, 'dono_trava', o.exe and o.principal is not null,
           'restr_dono', o.restr_dono,
           'dp_ot', o.p #> '{duracao,dp_otimista}', 'dp_re', o.p #> '{duracao,dp_realista}',
           'est', o.p -> 'est', 'est_texto', o.p ->> 'est_texto', 'inicio_mat', o.p #> '{material,inicio_mat}',
           'mat_estado', o.p #>> '{material,estado}', 'mat_falta', o.mat_falta,
           'p', o.p)
           order by o.ord), '[]'::jsonb)
    into v_oss
    from o;

  select count(*) filter (where (e ->> 'executavel')::boolean),
         coalesce(sum((e ->> 'dp_ot')::numeric) filter (where (e ->> 'executavel')::boolean), 0),
         coalesce(sum((e ->> 'dp_re')::numeric) filter (where (e ->> 'executavel')::boolean), 0),
         count(*) filter (where (e ->> 'executavel')::boolean and e ->> 'dp_re' is null),
         coalesce(bool_or((e ->> 'executavel')::boolean and (e ->> 'mat_falta')::boolean), false),
         coalesce(bool_or((e ->> 'executavel')::boolean and jsonb_array_length(e -> 'restr_dono') > 0), false)
    into v_n, v_ot, v_re, v_sb, v_compra, v_oferta
    from jsonb_array_elements(v_oss) e;

  -- Livre de verdade: a fila ÷ a capacidade diária (comprometível ÷ dias úteis da semana), em dias úteis.
  if v_n > 0 and v_re > 0 and v_cdia > 0 then
    v_livre := jsonb_build_object(
      'n_ot', ceil(v_ot / v_cdia)::int, 'n_re', ceil(v_re / v_cdia)::int,
      'ot', public.agenda_somar_du(p_hoje, ceil(v_ot / v_cdia)::int + 1),
      're', public.agenda_somar_du(p_hoje, ceil(v_re / v_cdia)::int + 1),
      'semanas_ot', round(v_ot / v_comp)::int, 'semanas_re', round(v_re / v_comp)::int);
  end if;

  if v_cap ->> 'aviso' is not null then
    v_aviso := case when v_cap ->> 'ultima_diaria' is null
                    then 'nenhuma diária foi lançada ainda: não sei o ritmo da equipe'
                    else format('nenhuma diária foi lançada depois de %s: não sei o que a equipe fez de %s até hoje',
                                public._dia_curto((v_cap ->> 'ultima_diaria')::date),
                                public._dia_curto(public.agenda_somar_du((v_cap ->> 'ultima_diaria')::date, 1))) end;
  end if;

  return jsonb_build_object(
    'hoje', p_hoje, 'texto_max', c.texto_max, 'prazo_padrao_du', c.prazo_padrao_du,
    'congelamento_du', c.congelamento_du, 'medicao_semanas', c.medicao_semanas, 'dia_do_plano', c.dia_do_plano,
    'folga_material_du', c.folga_material_du, 'equipe_sugerida', c.equipe_sugerida, 'modo_leitura', c.modo_leitura,
    'cap', v_cap, 'comprometivel', v_comp, 'cap_dia', v_cdia, 'du_semana', v_du,
    'dono', v_dono, 'dono_usuario', v_usuario, 'dono_padrao', v_padrao,
    'oss', v_oss,
    'backlog', jsonb_build_object('n', v_n, 'dp_ot', trim_scale(v_ot), 'dp_re', trim_scale(v_re), 'sem_base', v_sb,
                                  'com_compra', v_compra),
    'livre', v_livre,
    'aviso_diarias', v_aviso,
    'oferta', v_oferta or not v_padrao,
    'inicio_furando', public.agenda_somar_du(p_hoje, c.congelamento_du + 1));
end;
$function$;

comment on function public._agenda_painel(date) is 'Agenda de Produção (Fase 1, P4): o insumo de todos os textos, lido uma vez — capacidade (agenda_capacidade_semanal), prontidão de cada OS da carteira com grupo (pronto/quase/travado/esperando/parado/marcado/andamento/espera), ordem de trabalho (a prioridade do dono → sinal pago → orçamento aprovado → resto, aprovação mais antiga primeiro), restrição principal do dono, atrasada, em risco, data marcada vencida; a fila executável em diárias-pessoa e o livre de verdade (ceil(fila ÷ capacidade diária) + 1 dias úteis). Não é texto.';

-- As OS do painel que valem um filtro, na ordem pedida, no formato de _agenda_nomes.
create or replace function public._agenda_lista_de(p_pn jsonb, p_grupo text, p_ordem text default 'ordem')
 returns jsonb
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> p_ordem)::int), '[]'::jsonb)
    from jsonb_array_elements(p_pn -> 'oss') e
   where e ->> 'grupo' = p_grupo;
$function$;

comment on function public._agenda_lista_de(jsonb, text, text) is 'Agenda de Produção (Fase 1, P4): as OS do painel de um grupo, na ordem pedida, como [{o}] para _agenda_nomes.';

-- ── 3. A semana ─────────────────────────────────────────────────────────────────────────────────────────

-- O tamanho da fila em diárias-pessoa, arredondado: "uns 17 a 32 dias de equipe" (e quantos não dão base).
create or replace function public._agenda_fila_faixa(p_pn jsonb)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_bk jsonb := p_pn -> 'backlog';
  v_lo int := round((v_bk ->> 'dp_ot')::numeric)::int;
  v_hi int := round((v_bk ->> 'dp_re')::numeric)::int;
  v_sb int := (v_bk ->> 'sem_base')::int;
begin
  if (v_bk ->> 'dp_re')::numeric <= 0 then
    return 'sem base para estimar os dias';
  end if;
  return case
    when v_hi = 0 then 'menos de 1 dia de equipe'
    when v_lo = v_hi then case when v_hi = 1 then '1 dia de equipe' else format('uns %s dias de equipe', v_hi) end
    when v_lo = 0 then format('até uns %s dias de equipe', v_hi)
    else format('uns %s a %s dias de equipe', v_lo, v_hi) end
    || case when v_sb > 0 then format(' (e %s sem base para estimar)', v_sb) else '' end;
end;
$function$;

comment on function public._agenda_fila_faixa(jsonb) is 'Agenda de Produção (Fase 1, P4): a fila executável em diárias-pessoa, arredondada ("uns 17 a 32 dias de equipe"), com quantos serviços não dão base para estimar.';

-- A fila em faixa: "Livre ela não está: há 7 serviços aprovados, uns 17 a 32 dias de equipe — de 3 a 6 semanas no
-- ritmo de ~5,4 diárias de equipe por semana (o que vocês lançaram, com folga), sem contar você."
create or replace function public._agenda_resumo(p_pn jsonb, p_ela boolean default true)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_bk   jsonb := p_pn -> 'backlog';
  v_n    int := (v_bk ->> 'n')::int;
  v_comp numeric := (p_pn ->> 'comprometivel')::numeric;
  v_lv   jsonb := p_pn -> 'livre';
  v_fx   text;
  v_sem  text;
  v_slo  int;
  v_shi  int;
begin
  if v_n = 0 then
    return 'Não há serviço aprovado esperando na fila.';
  end if;
  v_fx := public._agenda_fila_faixa(p_pn);
  if v_lv is not null and jsonb_typeof(v_lv) = 'null' then v_lv := null; end if;
  if v_comp <= 0 or v_lv is null then
    return case when p_ela then 'Livre ela não está: ' else 'Livre não está: ' end
           || format('há %s, %s — não sei o ritmo da equipe: não há diárias lançadas para medir.',
                     public._agenda_plural(v_n, 'serviço aprovado', 'serviços aprovados'), v_fx);
  end if;
  v_slo := (v_lv ->> 'semanas_ot')::int;
  v_shi := (v_lv ->> 'semanas_re')::int;
  v_sem := case
    when v_shi = 0 then 'menos de 1 semana'
    when v_slo = v_shi then case when v_shi = 1 then 'uma semana' else format('umas %s semanas', v_shi) end
    when v_slo = 0 then format('até %s semanas', v_shi)
    else format('de %s a %s semanas', v_slo, v_shi) end;
  return case when p_ela then 'Livre ela não está: ' else 'Livre não está: ' end
         || format('há %s, %s — %s no ritmo de ~%s diárias de equipe por semana (%s, com folga), %s.',
                   public._agenda_plural(v_n, 'serviço aprovado', 'serviços aprovados'), v_fx, v_sem,
                   public._agenda_num(v_comp, 1),
                   case when (p_pn #>> '{cap,conta_dono}')::boolean then 'o que vocês lançaram e o que você disse'
                        else 'o que vocês lançaram' end,
                   case when (p_pn #>> '{cap,conta_dono}')::boolean then 'contando você' else 'sem contar você' end);
end;
$function$;

comment on function public._agenda_resumo(jsonb, boolean) is 'Agenda de Produção (Fase 1, P4): a fila em faixa com o único número de capacidade ("há 7 serviços aprovados, uns 17 a 32 dias de equipe — de 3 a 6 semanas no ritmo de ~5,4 diárias de equipe por semana (o que vocês lançaram, com folga), sem contar você").';

-- "Livre de verdade: no melhor caso a partir de qua 18/11; no realista, só a partir de qua 09/12 — se as compras
-- saírem e nada novo entrar." p_cauda = false tira o "— se …" (o fechamento).
create or replace function public._agenda_livre_linha(p_pn jsonb, p_cauda boolean default true)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when (p_pn #>> '{backlog,n}')::int = 0 then
      'Livre de verdade: a partir de ' || public._dia_curto((p_pn ->> 'inicio_furando')::date) || '.'
    when p_pn -> 'livre' is null or jsonb_typeof(p_pn -> 'livre') = 'null' then null
    else case when p_pn #>> '{livre,ot}' = p_pn #>> '{livre,re}'
              then 'Livre de verdade: a partir de ' || public._dia_curto((p_pn #>> '{livre,ot}')::date)
              else format('Livre de verdade: no melhor caso a partir de %s; no realista, só a partir de %s',
                          public._dia_curto((p_pn #>> '{livre,ot}')::date), public._dia_curto((p_pn #>> '{livre,re}')::date)) end
         || case when not p_cauda then ''
                 when (p_pn #>> '{backlog,com_compra}')::boolean then ' — se as compras saírem e nada novo entrar'
                 else ' — se nada novo entrar' end
         || '.' end;
$function$;

comment on function public._agenda_livre_linha(jsonb, boolean) is 'Agenda de Produção (Fase 1, P4): "Livre de verdade: no melhor caso a partir de …; no realista, só a partir de … — se as compras saírem e nada novo entrar."';

-- Quantos nomes uma lista mostra (p_lim = {lista: n}; sem a chave, 5).
create or replace function public._agenda_lim(p_lim jsonb, p_chave text)
 returns integer
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce((p_lim ->> p_chave)::int, 5);
$function$;

comment on function public._agenda_lim(jsonb, text) is 'Agenda de Produção (Fase 1, P4): quantos nomes a lista p_chave mostra (p_lim; sem a chave, 5).';

-- O corte por item: dado o que um montador devolveu ({linhas, listas:{nome:{linha (0..), n}}}) e os limites, tira
-- UM nome da lista cuja linha está mais longa (entre as que ainda mostram mais de 1). null = não há o que encolher
-- (aí _agenda_juntar tira linhas inteiras do fim).
create or replace function public._agenda_encolher(p_r jsonb, p_lim jsonb)
 returns jsonb
 language sql
 immutable
 set search_path to 'public'
as $function$
  select jsonb_set(coalesce(p_lim, '{}'::jsonb), array[x.chave], to_jsonb(x.mostra - 1))
    from (select l.key as chave, least(public._agenda_lim(p_lim, l.key), (l.value ->> 'n')::int) as mostra,
                 char_length(coalesce(p_r -> 'linhas' ->> (l.value ->> 'linha')::int, '')) as tam
            from jsonb_each(coalesce(p_r -> 'listas', '{}'::jsonb)) l) x
   where x.mostra > 1
   order by x.tam desc, x.chave
   limit 1;
$function$;

comment on function public._agenda_encolher(jsonb, jsonb) is 'Agenda de Produção (Fase 1, P4): o corte por item — um nome a menos na lista da linha mais longa que ainda mostra mais de 1; null quando não há o que encolher.';

create or replace function public._agenda_semana_de(p_pn jsonb, p_de date, p_ate date, p_marc jsonb, p_lim jsonb)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_hoje    date := (p_pn ->> 'hoje')::date;
  v_rot     text := public._agenda_periodo_rotulo(p_de, p_ate, v_hoje);
  v_ela     boolean := v_rot like 'Esta semana%' or v_rot like 'A semana que vem%';
  v_aviso   text := p_pn ->> 'aviso_diarias';
  v_quase   jsonb := public._agenda_lista_de(p_pn, 'quase');
  v_prontos jsonb;
  v_andam   jsonb;
  v_trav    jsonb;
  v_esper   jsonb;
  v_parad   jsonb;
  v_espera  jsonb;
  v_listas  jsonb := '{}'::jsonb;
  l_marc    text;
  l_resumo  text := public._agenda_resumo(p_pn, v_ela);
  l_prontos text;
  l_andam   text;
  l_trav    text;
  l_esper   text;
  l_parad   text;
  l_espera  text;
  l_livre   text := public._agenda_livre_linha(p_pn, true);
  l_oferta  text;
begin
  if jsonb_array_length(p_marc) = 0 then
    l_marc := v_rot || ' não tem nada marcado' || coalesce(', e ' || v_aviso, '') || '.';
  else
    l_marc := v_rot || ': ' || public._agenda_lista(array(select e ->> 'texto_semana' from jsonb_array_elements(p_marc)
                                                            with ordinality t(e, o) order by o), public._agenda_lim(p_lim, 'marc'))
              || '.' || coalesce(' ' || public._agenda_maiuscula(v_aviso) || '.', '');
    v_listas := v_listas || jsonb_build_object('marc', jsonb_build_object('linha', 0, 'n', jsonb_array_length(p_marc)));
  end if;

  -- Prontos ("a partir de" quando o material ou o bem seguram) e quase (só falta dizer se tem peça a comprar).
  select coalesce(jsonb_agg(jsonb_build_object('o', e, 'sufixo',
           case when (e ->> 'est')::date > public.agenda_somar_du(v_hoje, 1) then 'a partir de ' || (e ->> 'est_texto') end)
           order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_prontos from jsonb_array_elements(p_pn -> 'oss') e where e ->> 'grupo' = 'pronto';
  l_prontos := 'Prontos para começar: '
    || coalesce(nullif(public._agenda_nomes(v_prontos, public._agenda_lim(p_lim, 'prontos')), ''), 'nenhum') || '.'
    || case when jsonb_array_length(v_quase) > 0 then
         ' Quase: ' || public._agenda_nomes(v_quase, public._agenda_lim(p_lim, 'quase'))
         || case when jsonb_array_length(v_quase) = 1 then ', se não tiver peça a comprar.' else ', se não tiverem peça a comprar.' end
       else '' end;
  if jsonb_array_length(v_prontos) > 0 then
    v_listas := v_listas || jsonb_build_object('prontos', jsonb_build_object('linha', 2, 'n', jsonb_array_length(v_prontos)));
  end if;
  if jsonb_array_length(v_quase) > 0 then
    v_listas := v_listas || jsonb_build_object('quase', jsonb_build_object('linha', 2, 'n', jsonb_array_length(v_quase)));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('o', e, 'sufixo',
           case when e ->> 'estado' = 'parada' then regexp_replace(e ->> 'estado_texto', '^em andamento ', '') end)
           order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_andam from jsonb_array_elements(p_pn -> 'oss') e where e ->> 'grupo' = 'andamento';
  if jsonb_array_length(v_andam) > 0 then
    l_andam := 'Em andamento: ' || public._agenda_nomes(v_andam, public._agenda_lim(p_lim, 'andam')) || '.';
    v_listas := v_listas || jsonb_build_object('andam', jsonb_build_object('linha', 3, 'n', jsonb_array_length(v_andam)));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('o', e, 'sufixo', public._agenda_restricao_curta(e -> 'principal'))
           order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_trav from jsonb_array_elements(p_pn -> 'oss') e where e ->> 'grupo' = 'travado';
  if jsonb_array_length(v_trav) > 0 then
    l_trav := 'Travados por material: ' || public._agenda_nomes(v_trav, public._agenda_lim(p_lim, 'trav')) || '.';
    v_listas := v_listas || jsonb_build_object('trav', jsonb_build_object('linha', 4, 'n', jsonb_array_length(v_trav)));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('o', e, 'sufixo',
           replace(e ->> 'estado_texto', ' e nunca virou OS', ', nunca virou OS'))
           order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_esper from jsonb_array_elements(p_pn -> 'oss') e where e ->> 'grupo' = 'esperando';
  if jsonb_array_length(v_esper) > 0 then
    l_esper := 'Esperando você: ' || public._agenda_nomes(v_esper, public._agenda_lim(p_lim, 'esper')) || '.';
    v_listas := v_listas || jsonb_build_object('esper', jsonb_build_object('linha', 5, 'n', jsonb_array_length(v_esper)));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('o', e, 'sufixo',
           case when e ->> 'estado' = 'sem_sinal' then 'sinal'
                when e ->> 'status' = 'awaiting_client' then null
                else e ->> 'estado_texto' end)
           order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_parad from jsonb_array_elements(p_pn -> 'oss') e where e ->> 'grupo' = 'parado';
  if jsonb_array_length(v_parad) > 0 then
    l_parad := 'Parados no cliente: ' || public._agenda_nomes(v_parad, public._agenda_lim(p_lim, 'parad')) || '.';
    v_listas := v_listas || jsonb_build_object('parad', jsonb_build_object('linha', 6, 'n', jsonb_array_length(v_parad)));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('o', e, 'sufixo', substring(e ->> 'estado_texto' from 'até [^ ]+ [^ ]+'))
           order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_espera from jsonb_array_elements(p_pn -> 'oss') e where e ->> 'grupo' = 'espera';
  if jsonb_array_length(v_espera) > 0 then
    l_espera := 'Em espera (você pediu): ' || public._agenda_nomes(v_espera, public._agenda_lim(p_lim, 'espera')) || '.';
    v_listas := v_listas || jsonb_build_object('espera', jsonb_build_object('linha', 7, 'n', jsonb_array_length(v_espera)));
  end if;

  if (p_pn ->> 'oferta')::boolean then
    l_oferta := 'Quer que eu pergunte o que falta para montar a semana que vem? Uma resposta por OS; dá para responder num áudio.';
  end if;

  -- As linhas na posição fixa (as vazias somem em _agenda_juntar); "listas" diz em que linha está cada lista.
  return jsonb_build_object(
    'linhas', jsonb_build_array(l_marc, l_resumo, l_prontos, l_andam, l_trav, l_esper, l_parad, l_espera, l_livre, l_oferta),
    'listas', v_listas,
    'textos', jsonb_build_object('marcados', l_marc, 'aviso', v_aviso, 'resumo', l_resumo, 'prontos', l_prontos,
                                 'andamento', l_andam, 'travados', l_trav, 'esperando', l_esper, 'parados', l_parad,
                                 'espera', l_espera, 'livre', l_livre, 'oferta', l_oferta),
    'dados', jsonb_build_object('de', p_de, 'ate', p_ate, 'marcados', p_marc, 'fila', p_pn -> 'backlog',
                                'capacidade', p_pn -> 'comprometivel', 'conta_dono', p_pn #> '{cap,conta_dono}',
                                'livre', p_pn -> 'livre',
                                'grupos', (select coalesce(jsonb_object_agg(x.g, x.n), '{}'::jsonb) from (
                                             select e ->> 'grupo' as g, count(*) as n from jsonb_array_elements(p_pn -> 'oss') e
                                              group by 1) x)));
end;
$function$;

comment on function public._agenda_semana_de(jsonb, date, date, jsonb, jsonb) is 'Agenda de Produção (Fase 1, P4): as linhas da semana a partir do painel e do marcado, com os limites de nomes por lista (p_lim). Devolve {linhas (posição fixa), listas {nome:{linha, n}}, textos, dados}.';

-- As linhas de um montador, sem as vazias.
create or replace function public._agenda_linhas(p_r jsonb)
 returns text[]
 language sql
 immutable
 set search_path to 'public'
as $function$
  select array(select x from jsonb_array_elements_text(coalesce(p_r -> 'linhas', '[]'::jsonb)) with ordinality t(x, o)
                where x is not null order by o);
$function$;

comment on function public._agenda_linhas(jsonb) is 'Agenda de Produção (Fase 1, P4): as linhas de um montador, na ordem, sem as nulas.';

create or replace function public.agenda_semana(p_de date default null, p_ate date default null,
                                                p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_pn   jsonb;
  v_r    jsonb;
  v_de   date;
  v_ate  date;
  v_max  int;
  v_marc jsonb;
  v_lim  jsonb := '{}'::jsonb;
  v_novo jsonb;
begin
  if p_hoje is null then
    raise exception 'agenda_semana: sem o dia de hoje' using errcode = '22004';
  end if;
  v_de := coalesce(p_de, p_hoje - (extract(isodow from p_hoje)::int - 1));
  v_ate := coalesce(p_ate, v_de + 5);
  if v_ate < v_de then
    raise exception 'agenda_semana: período invertido (% a %)', v_de, v_ate using errcode = '22023';
  end if;
  v_pn := public._agenda_painel(p_hoje);
  v_max := (v_pn ->> 'texto_max')::int;
  v_marc := public._agenda_marcados(v_de, v_ate, p_hoje, null, (v_pn ->> 'dono_usuario')::uuid);
  -- Até 5 nomes por lista; passou do teto, a lista da linha mais longa perde um nome por vez ("e mais N").
  loop
    v_r := public._agenda_semana_de(v_pn, v_de, v_ate, v_marc, v_lim);
    exit when char_length(public._agenda_juntar(public._agenda_linhas(v_r), null)) <= v_max;
    v_novo := public._agenda_encolher(v_r, v_lim);
    exit when v_novo is null;
    v_lim := v_novo;
  end loop;
  return jsonb_build_object('ok', true,
    'texto', public._agenda_juntar(public._agenda_linhas(v_r), v_max),
    'dados', (v_r -> 'dados') || jsonb_build_object('textos', v_r -> 'textos'));
end;
$function$;

comment on function public.agenda_semana(date, date, date) is 'Agenda de Produção (Fase 1, P4): "como tá a semana?" — o marcado no período (janela antiga + compromisso com hora do dono), o aviso de diárias faltando, a fila em faixa com o único número de capacidade, prontos/quase/travados por material/esperando você/parados no cliente, o livre de verdade em faixa e a oferta da rodada. Sem período: seg–sáb da semana de p_hoje. Até 5 nomes por lista; passou de texto_max, a lista mais longa perde nomes ("e mais N"). {ok, texto, dados{…, textos}}.';

-- ── 4. O que eu tenho que fazer ─────────────────────────────────────────────────────────────────────────

-- O 5º bloco, "Outras pendências", com a MESMA regra de my_agenda (_shared/ai/tools/agenda.ts): tarefas pending/
-- in_progress do login, âncora due_at, senão scheduled_start_at; antes do início do dia = atrasada, dentro do dia = de
-- hoje. A receber e a pagar pending/partially_paid com vencimento hoje; o valor é o saldo, senão o valor.
create or replace function public._agenda_outras(p_usuario uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_ini    timestamptz := (p_hoje::timestamp at time zone 'America/Sao_Paulo');
  v_fim    timestamptz := ((p_hoje + 1)::timestamp at time zone 'America/Sao_Paulo');
  v_t_atr  int;
  v_t_hoje int;
  v_r_n    int;
  v_r_tot  numeric;
  v_p_n    int;
  v_p_tot  numeric;
  v_tar    text;
begin
  if p_usuario is null then
    v_tar := 'sem login ligado a você, não vejo as tarefas';
  else
    select count(*) filter (where x.ancora < v_ini), count(*) filter (where x.ancora >= v_ini and x.ancora < v_fim)
      into v_t_atr, v_t_hoje
      from (select coalesce(t.due_at, t.scheduled_start_at) as ancora from public.agenda_tasks t
             where t.assignee_user_id = p_usuario and t.status in ('pending', 'in_progress')) x;
    v_tar := case
      when v_t_atr = 0 and v_t_hoje = 0 then 'nenhuma tarefa atrasada nem de hoje'
      when v_t_atr > 0 and v_t_hoje > 0 then
        format('%s e %s de hoje', public._agenda_plural(v_t_atr, 'tarefa atrasada', 'tarefas atrasadas'), v_t_hoje)
      when v_t_atr > 0 then public._agenda_plural(v_t_atr, 'tarefa atrasada', 'tarefas atrasadas')
      else public._agenda_plural(v_t_hoje, 'tarefa de hoje', 'tarefas de hoje') end;
  end if;
  select count(*), coalesce(sum(coalesce(r.balance_amount, r.amount)), 0) into v_r_n, v_r_tot
    from public.receivables r where r.status in ('pending', 'partially_paid') and r.due_date = p_hoje;
  select count(*), coalesce(sum(coalesce(p.balance_amount, p.amount)), 0) into v_p_n, v_p_tot
    from public.payables p where p.status in ('pending', 'partially_paid') and p.due_date = p_hoje;
  return jsonb_build_object(
    'texto', format('Outras pendências: %s; a receber hoje: %s; a pagar hoje: %s.', v_tar,
                    case when v_r_n = 0 then 'nada'
                         else public._agenda_plural(v_r_n, 'cobrança', 'cobranças') || ', ' || public._brl(v_r_tot) end,
                    case when v_p_n = 0 then 'nada'
                         else public._agenda_plural(v_p_n, 'conta', 'contas') || ', ' || public._brl(v_p_tot) end),
    'dados', jsonb_build_object('tarefas_atrasadas', v_t_atr, 'tarefas_de_hoje', v_t_hoje,
                                'a_receber', jsonb_build_object('n', v_r_n, 'total', v_r_tot),
                                'a_pagar', jsonb_build_object('n', v_p_n, 'total', v_p_tot)));
end;
$function$;

comment on function public._agenda_outras(uuid, date) is 'Agenda de Produção (Fase 1, P4): o bloco "Outras pendências" com a MESMA regra de my_agenda — tarefas pending/in_progress do login (âncora due_at, senão scheduled_start_at: antes do dia = atrasada, no dia = de hoje) e a receber/a pagar pending/partially_paid que vencem hoje (saldo, senão valor).';

create or replace function public._agenda_o_que_fazer_de(p_pn jsonb, p_marc jsonb, p_prox jsonb, p_outras jsonb, p_lim jsonb)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_hoje   date := (p_pn ->> 'hoje')::date;
  v_trav   jsonb;
  v_n      int;
  v_k      int;
  v_prontos jsonb;
  v_atr    jsonb;
  v_risco  jsonb;
  v_fonte  text;
  v_listas jsonb := '{}'::jsonb;
  l1 text; l2 text; l3 text; l4 text; l_oferta text;
begin
  -- (1) Hoje
  l1 := public._agenda_dia_rotulo(v_hoje, v_hoje) || ': '
        || coalesce(nullif(public._agenda_lista(array(select e ->> 'texto_dia' from jsonb_array_elements(p_marc)
                                                        with ordinality t(e, o) order by o),
                                                public._agenda_lim(p_lim, 'hoje')), ''), 'nada marcado') || '.';
  if jsonb_array_length(p_marc) > 0 then
    v_listas := v_listas || jsonb_build_object('hoje', jsonb_build_object('linha', 0, 'n', jsonb_array_length(p_marc)));
  end if;

  -- (2) Travado esperando você: a restrição mais forte de cada OS (a da prontidão), na ordem de trabalho.
  select coalesce(jsonb_agg(e order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_trav from jsonb_array_elements(p_pn -> 'oss') e where (e ->> 'dono_trava')::boolean;
  v_n := jsonb_array_length(v_trav);
  v_k := public._agenda_lim(p_lim, 'trav');
  if v_n = 0 then
    l2 := 'Travado esperando você: nada.';
  else
    l2 := 'Travado esperando você: '
          || array_to_string(array(
               select public._agenda_rotulo(e, 'normal') || ' — '
                      || case when e #>> '{principal,tipo}' = 'material_nao_conferido' then e #>> '{principal,pergunta}'
                              else e #>> '{principal,texto}' end
                 from jsonb_array_elements(v_trav) with ordinality t(e, o) where o <= v_k order by o), '; ')
          || case when v_n > v_k then format('; e mais %s', v_n - v_k) else '' end;
    l2 := l2 || case when right(l2, 1) = '?' then '' else '.' end;
    v_listas := v_listas || jsonb_build_object('trav', jsonb_build_object('linha', 1, 'n', v_n));
  end if;

  -- (3) Prontos sem data e os próximos 7 dias.
  select coalesce(jsonb_agg(jsonb_build_object('o', e, 'sufixo',
           case when (e ->> 'est')::date > public.agenda_somar_du(v_hoje, 1) then 'a partir de ' || (e ->> 'est_texto') end)
           order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_prontos from jsonb_array_elements(p_pn -> 'oss') e where e ->> 'grupo' = 'pronto';
  l3 := 'Prontos sem data: '
        || coalesce(nullif(public._agenda_nomes(v_prontos, public._agenda_lim(p_lim, 'prontos')), ''), 'nenhum') || '. '
        || case when jsonb_array_length(p_prox) = 0 then 'Nada marcado nos próximos 7 dias.'
                else 'Próximos 7 dias: ' || public._agenda_lista(array(select e ->> 'texto_semana'
                       from jsonb_array_elements(p_prox) with ordinality t(e, o) order by o),
                       public._agenda_lim(p_lim, 'prox')) || '.' end;
  if jsonb_array_length(v_prontos) > 0 then
    v_listas := v_listas || jsonb_build_object('prontos', jsonb_build_object('linha', 2, 'n', jsonb_array_length(v_prontos)));
  end if;
  if jsonb_array_length(p_prox) > 0 then
    v_listas := v_listas || jsonb_build_object('prox', jsonb_build_object('linha', 2, 'n', jsonb_array_length(p_prox)));
  end if;

  -- (4) Em risco: o que passou do prazo e o que pode passar (resumido; o detalhe é *atrasado*).
  select coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> 'ordem_aprov')::int), '[]'::jsonb),
         case when count(*) filter (where e ->> 'prazo_fonte' = 'dono') = 0 then 'do prazo padrão'
              when count(*) filter (where e ->> 'prazo_fonte' <> 'dono') = 0 then 'do prazo do cliente'
              else 'do prazo' end
    into v_atr, v_fonte from jsonb_array_elements(p_pn -> 'oss') e where (e ->> 'atrasada')::boolean;
  select coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> 'ordem_aprov')::int), '[]'::jsonb)
    into v_risco from jsonb_array_elements(p_pn -> 'oss') e where (e ->> 'em_risco')::boolean;
  l4 := 'Em risco: '
        || case when jsonb_array_length(v_atr) + jsonb_array_length(v_risco) = 0 then 'nada.'
                else concat_ws(' e ',
                       case when jsonb_array_length(v_atr) > 0 then
                         format('%s %s (%s)', jsonb_array_length(v_atr),
                                case when jsonb_array_length(v_atr) = 1 then 'passou ' else 'passaram ' end || v_fonte,
                                public._agenda_nomes(v_atr, public._agenda_lim(p_lim, 'atr'))) end,
                       case when jsonb_array_length(v_risco) > 0 then
                         format('%s %s (%s)', jsonb_array_length(v_risco),
                                case when jsonb_array_length(v_risco) = 1 then 'pode passar' else 'podem passar' end,
                                public._agenda_nomes(v_risco, public._agenda_lim(p_lim, 'risco'))) end)
                     || ' — *atrasado* para ver.' end;
  if jsonb_array_length(v_atr) > 0 then
    v_listas := v_listas || jsonb_build_object('atr', jsonb_build_object('linha', 3, 'n', jsonb_array_length(v_atr)));
  end if;
  if jsonb_array_length(v_risco) > 0 then
    v_listas := v_listas || jsonb_build_object('risco', jsonb_build_object('linha', 3, 'n', jsonb_array_length(v_risco)));
  end if;

  if (p_pn ->> 'oferta')::boolean then
    l_oferta := 'Quer que eu pergunte o que falta, uma resposta por OS? Dá para responder num áudio.';
  end if;

  return jsonb_build_object(
    'linhas', jsonb_build_array(l1, l2, l3, l4, p_outras ->> 'texto', l_oferta),
    'listas', v_listas,
    'dados', jsonb_build_object(
      'marcados_hoje', p_marc, 'proximos', p_prox,
      'travados', (select coalesce(jsonb_agg(jsonb_build_object('numero', e ->> 'numero', 'tipo', e #>> '{principal,tipo}')
                                             order by o), '[]'::jsonb)
                     from jsonb_array_elements(v_trav) with ordinality t(e, o)),
      'prontos', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb)
                    from jsonb_array_elements(v_prontos) with ordinality t(e, o)),
      'atrasadas', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb)
                      from jsonb_array_elements(v_atr) with ordinality t(e, o)),
      'em_risco', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb)
                     from jsonb_array_elements(v_risco) with ordinality t(e, o)),
      'outras', p_outras -> 'dados'));
end;
$function$;

comment on function public._agenda_o_que_fazer_de(jsonb, jsonb, jsonb, jsonb, jsonb) is 'Agenda de Produção (Fase 1, P4): os 5 blocos do "o que eu tenho que fazer" a partir do painel, do marcado de hoje e dos próximos 7 dias e do bloco "Outras pendências", com os limites de itens por lista (p_lim; o bloco 2 mostra até 5).';

create or replace function public.agenda_o_que_fazer(p_payee uuid default null, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_pn      jsonb;
  v_r       jsonb;
  v_payee   uuid;
  v_usuario uuid;
  v_max     int;
  v_marc    jsonb;
  v_prox    jsonb;
  v_outras  jsonb;
  v_lim     jsonb := '{}'::jsonb;
  v_novo    jsonb;
begin
  if p_hoje is null then
    raise exception 'agenda_o_que_fazer: sem o dia de hoje' using errcode = '22004';
  end if;
  v_payee := coalesce(p_payee, public._agenda_dono(null));
  if v_payee is null or not exists (select 1 from public.payees where id = v_payee) then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei você no cadastro de pessoas (sócio).');
  end if;
  -- Para quem não é sócio, "o que tem para fazer" é o dia da pessoa: o resto é do dono.
  if not exists (select 1 from public.payees where id = v_payee and kind = 'socio') then
    return public.agenda_dia_da_pessoa(v_payee, p_hoje, p_hoje);
  end if;
  select app_user_id into v_usuario from public.payees where id = v_payee;
  v_pn := public._agenda_painel(p_hoje);
  v_max := (v_pn ->> 'texto_max')::int;
  v_marc := public._agenda_marcados(p_hoje, p_hoje, p_hoje, null, v_usuario);
  v_prox := public._agenda_marcados(p_hoje + 1, p_hoje + 7, p_hoje, null, v_usuario);
  v_outras := public._agenda_outras(v_usuario, p_hoje);
  loop
    v_r := public._agenda_o_que_fazer_de(v_pn, v_marc, v_prox, v_outras, v_lim);
    exit when char_length(public._agenda_juntar(public._agenda_linhas(v_r), null)) <= v_max;
    v_novo := public._agenda_encolher(v_r, v_lim);
    exit when v_novo is null;
    v_lim := v_novo;
  end loop;
  return jsonb_build_object('ok', true,
    'texto', public._agenda_juntar(public._agenda_linhas(v_r), v_max),
    'dados', v_r -> 'dados');
end;
$function$;

comment on function public.agenda_o_que_fazer(uuid, date) is 'Agenda de Produção (Fase 1, P4): "o que eu tenho que fazer?" — os 5 blocos na ordem: Hoje; Travado esperando você (a restrição mais forte de cada OS, sinal pago → orçamento aprovado → resto, até 5 e "e mais N"); Prontos sem data e os próximos 7 dias; Em risco (passou do prazo / pode passar, aponta para *atrasado*); Outras pendências com a MESMA regra de my_agenda (tarefas atrasadas e de hoje do login; a receber e a pagar de hoje) — e a oferta da rodada. p_payee null = o dono; quem não é sócio recebe o dia da pessoa. {ok, texto ≤ texto_max, dados}.';

-- ── 5. O que está atrasado ──────────────────────────────────────────────────────────────────────────────

create or replace function public._agenda_atrasos_de(p_pn jsonb, p_k integer)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_hoje  date := (p_pn ->> 'hoje')::date;
  v_pad   jsonb;
  v_cli   jsonb;
  v_risco jsonb;
  v_marc  jsonb;
  v_mat   jsonb;
  l1 text; l2 text; l3 text; l4 text; l5 text; l6 text;
begin
  -- O que passou do prazo PADRÃO: "(aprovada em 29/07)" na 1ª OS, só a data nas outras; orçamento diz "assinado".
  select coalesce(jsonb_agg(jsonb_build_object('o', x.e, 'sufixo', x.suf) order by x.ord), '[]'::jsonb)
    into v_pad
    from (select e, (e ->> 'ordem_aprov')::int as ord,
                 case when (e ->> 'eh_orc')::boolean
                        then case when (e ->> 'assinado')::boolean then 'assinado em ' else 'aprovado em ' end
                      when row_number() over (partition by (e ->> 'eh_orc')::boolean order by (e ->> 'ordem_aprov')::int) = 1
                        then 'aprovada em '
                      else '' end
                 || to_char((e ->> 'aprovada_em')::date, 'DD/MM')
                 || case when (e ->> 'data_vencida')::boolean then
                      '; a data marcada ' || case when e ->> 'agendada_de' = e ->> 'agendada_ate'
                                                  then '(' || to_char((e ->> 'agendada_de')::date, 'DD/MM') || ')'
                                                  else format('de %s a %s', to_char((e ->> 'agendada_de')::date, 'DD/MM'),
                                                              to_char((e ->> 'agendada_ate')::date, 'DD/MM')) end
                      || ' também passou' else '' end as suf
            from jsonb_array_elements(p_pn -> 'oss') e
           where (e ->> 'atrasada')::boolean and e ->> 'prazo_fonte' <> 'dono') x;
  -- … e o que passou do prazo que o CLIENTE disse.
  select coalesce(jsonb_agg(jsonb_build_object('o', e, 'sufixo', 'precisava até ' || to_char((e ->> 'prazo')::date, 'DD/MM'))
                            order by (e ->> 'ordem_aprov')::int), '[]'::jsonb)
    into v_cli from jsonb_array_elements(p_pn -> 'oss') e
   where (e ->> 'atrasada')::boolean and e ->> 'prazo_fonte' = 'dono';
  select coalesce(jsonb_agg(jsonb_build_object('o', e, 'sufixo', 'prazo ' || public._dia_curto((e ->> 'prazo')::date))
                            order by (e ->> 'ordem_aprov')::int), '[]'::jsonb)
    into v_risco from jsonb_array_elements(p_pn -> 'oss') e where (e ->> 'em_risco')::boolean;
  -- A data marcada que passou sem a OS começar (fora as que já apareceram como atrasadas).
  select coalesce(jsonb_agg(jsonb_build_object('o', e, 'sufixo',
           case when e ->> 'agendada_de' = e ->> 'agendada_ate' then to_char((e ->> 'agendada_de')::date, 'DD/MM')
                else format('%s a %s', to_char((e ->> 'agendada_de')::date, 'DD/MM'), to_char((e ->> 'agendada_ate')::date, 'DD/MM')) end)
           order by (e ->> 'ordem_aprov')::int), '[]'::jsonb)
    into v_marc from jsonb_array_elements(p_pn -> 'oss') e
   where (e ->> 'data_vencida')::boolean and not (e ->> 'atrasada')::boolean;
  -- A previsão de material que venceu sem a chegada (níveis B, C e D com data antes de hoje).
  select coalesce(jsonb_agg(jsonb_build_object('o', e, 'sufixo',
           format('"%s", era %s', m ->> 'curto', public._dia_curto((m ->> 'data')::date)))
           order by (e ->> 'ordem_aprov')::int, (m ->> 'data')::date), '[]'::jsonb)
    into v_mat
    from jsonb_array_elements(p_pn -> 'oss') e, lateral jsonb_array_elements(e #> '{p,material,itens}') m
   where (e ->> 'executavel')::boolean and (m ->> 'critico')::boolean and (m ->> 'atrasado')::boolean;

  if jsonb_array_length(v_pad) > 0 then
    l1 := format('Passaram do prazo (%s dias úteis desde a aprovação — o meu padrão, porque %s): %s.',
                 p_pn ->> 'prazo_padrao_du',
                 case when jsonb_array_length(v_cli) = 0 then 'nenhum cliente disse quando precisa'
                      else 'o cliente não disse quando precisa' end,
                 public._agenda_nomes(v_pad, p_k));
    if jsonb_array_length(v_pad) = 1 then
      l1 := replace(l1, 'Passaram do prazo', 'Passou do prazo');
    end if;
  end if;
  if jsonb_array_length(v_cli) > 0 then
    l2 := case when jsonb_array_length(v_cli) = 1 then 'Passou do prazo que o cliente pediu: ' else 'Passaram do prazo que o cliente pediu: ' end
          || public._agenda_nomes(v_cli, p_k) || '.';
  end if;
  if jsonb_array_length(v_risco) > 0 then
    l3 := 'Pode passar do prazo, no ritmo que eu estimo: ' || public._agenda_nomes(v_risco, p_k) || '.';
  end if;
  if jsonb_array_length(v_marc) > 0 then
    l4 := 'A data marcada passou sem o serviço começar: ' || public._agenda_nomes(v_marc, p_k) || '.';
  end if;
  if l1 is null and l2 is null and l3 is null and l4 is null and jsonb_array_length(v_mat) = 0 then
    return jsonb_build_object('linhas', to_jsonb(array['Nada atrasado: nenhum serviço passou do prazo e nenhuma previsão de material venceu.']),
      'dados', jsonb_build_object('atrasadas', '[]'::jsonb, 'em_risco', '[]'::jsonb, 'material_vencido', '[]'::jsonb,
                                  'data_marcada_vencida', '[]'::jsonb));
  end if;
  l5 := case when jsonb_array_length(v_mat) = 0 then 'Nenhuma previsão de material vencida.'
             else 'Previsão de material vencida: ' || public._agenda_nomes(v_mat, p_k) || '.' end;
  if jsonb_array_length(v_pad) > 0 or exists (select 1 from jsonb_array_elements(v_risco) e where e #>> '{o,prazo_fonte}' <> 'dono') then
    l6 := 'Se algum cliente disse quando precisa, me fala que eu guardo.';
  end if;

  return jsonb_build_object(
    'linhas', to_jsonb(array[l1, l2, l3, l4, l5, l6]),
    'dados', jsonb_build_object(
      'atrasadas', (select coalesce(jsonb_agg(jsonb_build_object('numero', x.e #>> '{o,numero}', 'prazo', x.e #>> '{o,prazo}',
                                                                 'fonte', x.e #>> '{o,prazo_fonte}') order by x.o), '[]'::jsonb)
                      from (select e, o from jsonb_array_elements(v_pad) with ordinality t(e, o)
                            union all select e, 1000 + o from jsonb_array_elements(v_cli) with ordinality t(e, o)) x),
      'em_risco', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb)
                     from jsonb_array_elements(v_risco) with ordinality t(e, o)),
      'material_vencido', (select coalesce(jsonb_agg(jsonb_build_object('numero', e #>> '{o,numero}', 'item', e ->> 'sufixo')
                                                     order by o), '[]'::jsonb)
                             from jsonb_array_elements(v_mat) with ordinality t(e, o)),
      'data_marcada_vencida', (select coalesce(jsonb_agg(e ->> 'numero' order by (e ->> 'ordem_aprov')::int), '[]'::jsonb)
                                 from jsonb_array_elements(p_pn -> 'oss') e where (e ->> 'data_vencida')::boolean)));
end;
$function$;

comment on function public._agenda_atrasos_de(jsonb, integer) is 'Agenda de Produção (Fase 1, P4): as linhas do "o que está atrasado" a partir do painel, com até p_k nomes por lista.';

create or replace function public.agenda_atrasos(p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_pn  jsonb;
  v_r   jsonb;
  v_max int;
  v_t   text;
  k     int;
begin
  if p_hoje is null then
    raise exception 'agenda_atrasos: sem o dia de hoje' using errcode = '22004';
  end if;
  v_pn := public._agenda_painel(p_hoje);
  v_max := (v_pn ->> 'texto_max')::int;
  for k in reverse 6 .. 1 loop
    v_r := public._agenda_atrasos_de(v_pn, k);
    v_t := public._agenda_juntar(array(select jsonb_array_elements_text(v_r -> 'linhas')), null);
    exit when char_length(v_t) <= v_max;
  end loop;
  return jsonb_build_object('ok', true,
    'texto', public._agenda_juntar(array(select jsonb_array_elements_text(v_r -> 'linhas')), v_max),
    'dados', v_r -> 'dados');
end;
$function$;

comment on function public.agenda_atrasos(date) is 'Agenda de Produção (Fase 1, P4): "o que está atrasado?" — passou do prazo efetivo (o padrão de prazo_padrao_du dias úteis desde a aprovação, dito como padrão, ou o que o cliente pediu), pode passar (razão crítica < 1), data marcada (janela antiga) que passou sem o serviço começar, previsão de material vencida. Fora: parados no cliente, sem sinal e em espera. {ok, texto, dados{atrasadas, em_risco, material_vencido, data_marcada_vencida}}.';

-- ── 6. Material ─────────────────────────────────────────────────────────────────────────────────────────

-- O material de uma OS numa linha (o bloco de material da prontidão): a restrição de material mais forte, ou
-- "tudo na mão" / "o último item chega …".
create or replace function public._agenda_material_resumo(p_p jsonb)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce(
    -- Orçamento que nunca virou OS: antes de comprar, converter ou arquivar (o material fica entre parênteses).
    (select 'converter em OS ou arquivar antes de comprar'
            || coalesce(' (' || (select public._agenda_restricao_curta(m) from jsonb_array_elements(p_p -> 'restricoes')
                                   with ordinality t2(m, o2)
                                  where m ->> 'tipo' in ('atrasado', 'sem_previsao', 'compra_sem_prazo', 'comprado_sem_previsao',
                                                         'compre_ate', 'peca_embutida', 'material_nao_conferido')
                                  order by o2 limit 1) || ')', '')
       where exists (select 1 from jsonb_array_elements(p_p -> 'restricoes') e where e ->> 'tipo' = 'orcamento')),
    (select e ->> 'texto' from jsonb_array_elements(p_p -> 'restricoes') with ordinality t(e, o)
      where e ->> 'tipo' in ('atrasado', 'sem_previsao', 'compra_sem_prazo', 'comprado_sem_previsao', 'compre_ate',
                             'peca_embutida', 'material_nao_conferido')
      order by o limit 1),
    case p_p #>> '{material,estado}'
      when 'completo' then 'tudo na mão'
      when 'previsto' then format('o último item chega %s (pelo material, começa a partir de %s)',
                                  public._dia_curto((p_p #>> '{material,dpm}')::date),
                                  public._dia_curto((p_p #>> '{material,inicio_mat}')::date))
      else p_p #>> '{material,estado}' end);
$function$;

comment on function public._agenda_material_resumo(jsonb) is 'Agenda de Produção (Fase 1, P4): o material da OS numa linha — a restrição de material mais forte da prontidão, "tudo na mão" ou "o último item chega …".';

create or replace function public.agenda_ver_material(p_so_id uuid default null, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_pn     jsonb;
  v_p      jsonb;
  v_o      jsonb;
  v_linhas text[] := '{}';
  v_itens  text[];
  v_cab    text;
  v_pe     text;
  v_n      int;
  v_fora   int;
  k        int;
  v_t      text;
begin
  if p_hoje is null then
    raise exception 'agenda_ver_material: sem o dia de hoje' using errcode = '22004';
  end if;

  if p_so_id is null then
    -- Uma linha por serviço da fila com material pendente, na ordem de trabalho.
    v_pn := public._agenda_painel(p_hoje);
    v_itens := array(
      select '• ' || public._agenda_rotulo(e, 'num') || ': ' || public._agenda_material_resumo(e -> 'p')
        from jsonb_array_elements(v_pn -> 'oss') e
       where (e ->> 'executavel')::boolean and e ->> 'mat_estado' <> 'completo'
       order by (e ->> 'ordem')::int);
    select count(*) into v_fora from jsonb_array_elements(v_pn -> 'oss') e
     where not (e ->> 'executavel')::boolean and e ->> 'mat_estado' <> 'completo';
    v_n := cardinality(v_itens);
    if v_n = 0 then
      v_cab := 'Nenhum serviço da fila com material pendente.';
    else
      v_cab := format('Material pendente (%s):', public._agenda_plural(v_n, 'serviço', 'serviços'));
    end if;
    v_pe := case when v_fora > 0 then format('Não conto %s parados no cliente.', v_fora) end;
    if v_fora = 1 then v_pe := 'Não conto 1 parado no cliente.'; end if;
  else
    v_p := public.os_prontidao(p_so_id, p_hoje);
    if not coalesce((v_p ->> 'ok')::boolean, false) then
      return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
    end if;
    v_o := jsonb_build_object('curto', v_p ->> 'cliente_curto', 'numero', v_p ->> 'numero');
    v_cab := public._agenda_rotulo(v_o, 'num') || ' — material:';
    -- "você disse em DD/MM": o dia em que o dono informou (conferido_em), não o da sincronização (atualizado_em).
    v_itens := array(
      select '• ' || public._agenda_corta(
               case when coalesce(m.descricao, i ->> 'descricao') !~ '[a-zà-ÿ]' and coalesce(m.descricao, i ->> 'descricao') ~ '[A-ZÀ-Þ]{4}'
                    then public._agenda_maiuscula(translate(lower(coalesce(m.descricao, i ->> 'descricao')),
                                                            'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ', 'áàâãäéèêëíìîïóòôõöúùûüçñ'))
                    else coalesce(m.descricao, i ->> 'descricao') end, 48)
             || ' — '
             || case when i ->> 'nivel' = 'C' and nullif(i ->> 'trecho', '') is not null then
                       'chega ' || public._dia_curto((i ->> 'data')::date)
                       || format(' — você disse em %s: "%s"', to_char((coalesce(m.conferido_em, m.atualizado_em) at time zone 'America/Sao_Paulo')::date, 'DD/MM'),
                                 public._agenda_corta(i ->> 'trecho', 80))
                     when i ->> 'fonte' = 'dono' and nullif(i ->> 'trecho', '') is not null then
                       (i ->> 'data_texto')
                       || format(' — você disse em %s: "%s"', to_char((coalesce(m.conferido_em, m.atualizado_em) at time zone 'America/Sao_Paulo')::date, 'DD/MM'),
                                 public._agenda_corta(i ->> 'trecho', 80))
                     else i ->> 'data_texto' end
             || case when i ->> 'situacao' in ('comprado', 'a_caminho') and (i ->> 'data')::date <= p_hoje
                     then '; você ainda não me disse que chegou' else '' end
             || case when not (i ->> 'critico')::boolean then ' (pode começar sem)' else '' end
        from jsonb_array_elements(v_p #> '{material,itens}') with ordinality t(i, o)
        left join public.os_material m on m.id = (i ->> 'id')::uuid
       order by o);
    v_pe := case v_p #>> '{material,estado}'
      when 'completo' then 'Material completo: tudo na mão.'
      when 'previsto' then format('Pelo material, começa a partir de %s (%s depois de o último chegar).',
                                  public._dia_curto((v_p #>> '{material,inicio_mat}')::date),
                                  public._agenda_plural(c.folga_material_du, 'dia útil', 'dias úteis'))
      when 'nao_conferido' then case when cardinality(v_itens) = 0 then 'O orçamento não tem peça: ' else 'Falta conferir: ' end
                                || coalesce((select e ->> 'texto' from jsonb_array_elements(v_p -> 'restricoes') e
                                              where e ->> 'tipo' in ('peca_embutida', 'material_nao_conferido') limit 1),
                                            'tem peça a comprar?')
      when 'atrasado' then 'Ainda não dá para dizer quando começa: '
                           || public._agenda_plural((select count(*)::int from jsonb_array_elements(v_p #> '{material,itens}') e
                                                      where (e ->> 'critico')::boolean and (e ->> 'atrasado')::boolean),
                                                    'previsão venceu', 'previsões venceram') || '.'
      else 'Ainda não dá para dizer quando começa: '
           || public._agenda_plural((select count(*)::int from jsonb_array_elements(v_p #> '{material,itens}') e
                                      where (e ->> 'critico')::boolean and (e ->> 'sem_data')::boolean),
                                    'item sem previsão', 'itens sem previsão') || '.' end;
  end if;

  -- Cabe no teto: os itens saem do fim ("• e mais N"), nunca no meio de uma linha.
  v_n := cardinality(v_itens);
  for k in reverse v_n .. 0 loop
    v_linhas := array[v_cab] || v_itens[1:k]
                || case when k < v_n then array[format('• e mais %s', v_n - k)] else '{}'::text[] end
                || array[v_pe];
    v_t := public._agenda_juntar(v_linhas, null);
    exit when char_length(v_t) <= c.texto_max;
  end loop;

  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_linhas, c.texto_max),
    'dados', case when p_so_id is null then jsonb_build_object('servicos', v_n)
                  else jsonb_build_object('numero', v_p ->> 'numero', 'material', v_p -> 'material') end);
end;
$function$;

comment on function public.agenda_ver_material(uuid, date) is 'Agenda de Produção (Fase 1, P4): o material. Com OS: cada item com a situação, a previsão com a fonte e as palavras do dono ("chega ter 03/11 — você disse em 23/10: …"), "você ainda não me disse que chegou" quando a data prevista chegou, "pode começar sem" e o início pelo material (chegada + folga_material_du). Sem OS: uma linha por serviço da fila com material pendente. {ok, texto ≤ texto_max, dados}.';

-- ── 7. O dia de uma pessoa ──────────────────────────────────────────────────────────────────────────────

create or replace function public.agenda_dia_da_pessoa(p_payee uuid, p_dia date, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  py       record;
  v_dono   boolean;
  v_nome   text;
  v_marc   jsonb;
  v_m      record;
  v_t      record;
  v_sit    text;
  v_dias   int[];
  v_dtxt   text;
  v_fonte  text;
  v_freq   numeric;
  v_nota   text;
  v_abr    constant text[] := array['seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
  v_plu    constant text[] := array['às segundas', 'às terças', 'às quartas', 'às quintas', 'às sextas', 'aos sábados'];
  l1 text; l2 text;
begin
  if p_hoje is null or p_dia is null then
    raise exception 'agenda_dia_da_pessoa: sem o dia' using errcode = '22004';
  end if;
  select p.* into py from public.payees p where p.id = p_payee;
  if not found then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei essa pessoa no cadastro.');
  end if;
  v_dono := py.id is not distinct from public._agenda_dono(null) or py.kind = 'socio';
  v_nome := case when v_dono then 'você' else public._agenda_nome_curto(py.name) end;

  v_marc := case when py.app_user_id is null then '[]'::jsonb
                 else public._agenda_marcados(p_dia, p_dia, p_hoje, case when v_dono then null else py.app_user_id end,
                                              py.app_user_id) end;

  -- A situação do dia pela grade (manhã e tarde).
  select bool_and(g.situacao = 'fim_de_semana') as fds, bool_and(g.situacao = 'feriado') as fer,
         bool_and(g.situacao = 'indisponivel') as indisp, bool_or(g.situacao = 'indisponivel') as meio_indisp,
         bool_and(g.situacao = 'sem_padrao') as sem,
         max(g.motivo) filter (where g.situacao in ('fim_de_semana', 'feriado')) as motivo_cal,
         max(g.motivo) filter (where g.situacao = 'indisponivel') as motivo_ind,
         bool_or(g.situacao = 'indisponivel' and g.turno = 'manha') as manha_ind,
         count(*) as n
    into v_t
    from public.agenda_capacidade(p_dia, p_dia, p_hoje) g
   where g.payee_id = py.id;

  -- O padrão: os dias da semana em que a pessoa costuma vir (o que está em vigor em agenda_disponibilidade).
  v_dias := array(select distinct x from public.agenda_disponibilidade d, unnest(d.dias_semana) x
                   where d.payee_id = py.id and d.substituida_em is null and d.periodo is null
                     and d.situacao in ('disponivel', 'confirmada') and d.turno is null
                   order by x);

  v_sit := case
    when coalesce(v_t.n, 0) = 0 then
      case when extract(isodow from p_dia) = 7 then 'domingo'
           when extract(isodow from p_dia) = 6 and not c.sabado_util then 'sábado só quando vocês combinam'
           when public.agenda_feriado(p_dia) is not null then 'é feriado (' || public.agenda_feriado(p_dia) || ')'
           else null end
    when v_t.fds then v_t.motivo_cal
    when v_t.fer then 'é feriado (' || v_t.motivo_cal || ')'
    when v_t.indisp then case when v_dono then 'você não fica em campo' else 'não vem' end
                         || coalesce(' (' || nullif(v_t.motivo_ind, 'não vem') || ')', '')
    when v_t.meio_indisp then case when v_t.manha_ind then 'só à tarde' else 'só de manhã' end
    -- Tem padrão em outros dias e não neste: "às segundas não costuma vir" (o "não sei" fica para quem não tem padrão).
    when v_t.sem and not v_dono and cardinality(v_dias) > 0
         and not (extract(isodow from p_dia)::int = any (v_dias)) and extract(isodow from p_dia) between 1 and 6
      then v_plu[extract(isodow from p_dia)::int] || ' não costuma vir'
    when v_t.sem and not v_dono then 'não sei se vem: não há padrão de dias'
    else null end;

  if jsonb_array_length(v_marc) = 0 then
    l1 := public._agenda_dia_rotulo(p_dia, p_hoje) || ', ' || v_nome || ' não tem nada marcado';
  else
    l1 := public._agenda_dia_rotulo(p_dia, p_hoje) || ', ' || v_nome || ' tem '
          || public._agenda_lista(array(select e ->> 'texto_dia' from jsonb_array_elements(v_marc) with ordinality t(e, o)
                                         order by o), 5);
  end if;
  l1 := l1 || coalesce(' — ' || v_sit, '') || '.';

  select case when bool_and(d.origem = 'historico') then format('pelas diárias das últimas %s semanas', c.medicao_semanas)
              when bool_or(d.origem = 'dono') then 'você disse'
              else 'combinado' end
    into v_fonte
    from public.agenda_disponibilidade d
   where d.payee_id = py.id and d.substituida_em is null and d.periodo is null and d.situacao in ('disponivel', 'confirmada');
  select d.frequencia, d.nota into v_freq, v_nota
    from public.agenda_disponibilidade d
   where d.payee_id = py.id and d.substituida_em is null and d.periodo is null and d.origem = 'historico'
     and d.dias_semana @> array[extract(isodow from p_dia)::smallint]
   order by d.criado_em desc, d.id desc limit 1;

  if cardinality(v_dias) = 0 then
    l2 := case when v_dono then 'Você ainda não disse quais dias fica em campo.'
               else 'Não sei os dias em que costuma vir: não há diárias recentes.' end;
  else
    v_dtxt := case
      when cardinality(v_dias) = 1 then 'só ' || v_plu[v_dias[1]]
      when v_dias[cardinality(v_dias)] - v_dias[1] + 1 = cardinality(v_dias) and cardinality(v_dias) >= 3 then
        format('de %s a %s', v_abr[v_dias[1]], v_abr[v_dias[cardinality(v_dias)]])
      else public._agenda_lista(array(select v_abr[x] from unnest(v_dias) x), null) end;
    l2 := case when v_dono then 'Você costuma ficar em campo ' else 'Costuma vir ' end || v_dtxt
          || ' (' || v_fonte
          || case when v_freq is not null and v_freq < 1 and v_nota ~ '[0-9]+(,[0-9]+)? de [0-9]+ '
                  then ': ' || (regexp_match(v_nota, '([0-9]+(,[0-9]+)? de [0-9]+ [^ (]+)'))[1] else '' end
          || ').';
  end if;

  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(array[l1 || ' ' || l2], c.texto_max),
    'dados', jsonb_build_object('pessoa', v_nome, 'dia', p_dia, 'marcados', v_marc, 'situacao', v_sit, 'dias_semana', v_dias));
end;
$function$;

comment on function public.agenda_dia_da_pessoa(uuid, date, date) is 'Agenda de Produção (Fase 1, P4): "o que o Roberto faz amanhã?" — o marcado da pessoa no dia (OS em que é técnica, compromisso com hora), a situação pela grade (sábado só quando vocês combinam, domingo, feriado, não vem, só de manhã/à tarde, sem padrão) e o padrão de dias ("costuma vir de seg a sex (pelas diárias das últimas 8 semanas: 3 de 5 segundas)"). Sem artigo de gênero antes do nome. {ok, texto, dados}.';

-- ── 8. A rodada de aprontar ─────────────────────────────────────────────────────────────────────────────

create or replace function public._agenda_aprontar_de(p_pn jsonb, p_k integer)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_cand    jsonb;
  v_n       int;
  v_resto   jsonb;
  v_bul     text[];
  v_chute   boolean;
  l_cab     text;
  l_voce    text;
  l_pe      text;
begin
  -- Quem entra: a fila com algo que só o dono responde (o que trava primeiro, depois só a duração), na ordem de trabalho.
  select coalesce(jsonb_agg(e order by (e ->> 'dono_trava')::boolean desc, (e ->> 'ordem')::int), '[]'::jsonb)
    into v_cand from jsonb_array_elements(p_pn -> 'oss') e
   where (e ->> 'executavel')::boolean and jsonb_array_length(e -> 'restr_dono') > 0;
  v_n := jsonb_array_length(v_cand);

  -- Uma pergunta por OS: as perguntas do dono na ordem da prontidão; a duração com o chute entre parênteses.
  v_bul := array(
    select '• ' || public._agenda_rotulo(e, 'num') || ': '
           || array_to_string(array(
                select case when ro = 1 then q else public._agenda_maiuscula(q) end
                  from (select case when r ->> 'tipo' = 'duracao' then replace(r ->> 'texto', '(chute: ', '(')
                                    else r ->> 'pergunta' end as q, ro
                          from jsonb_array_elements(e -> 'restr_dono') with ordinality t2(r, ro)) z
                 order by ro), ' ')
      from jsonb_array_elements(v_cand) with ordinality t(e, o)
     where o <= p_k order by o);
  v_chute := exists (select 1 from jsonb_array_elements(v_cand) with ordinality t(e, o), jsonb_array_elements(e -> 'restr_dono') r
                      where o <= p_k and r ->> 'tipo' = 'duracao' and r ->> 'texto' like '%(chute: %');
  select coalesce(jsonb_agg(jsonb_build_object('o', e) order by o), '[]'::jsonb)
    into v_resto from jsonb_array_elements(v_cand) with ordinality t(e, o) where o > p_k;

  if not (p_pn ->> 'dono_padrao')::boolean then
    l_voce := '• Você: semana que vem fica em campo quais dias?';
  end if;
  if v_n = 0 and l_voce is null then
    return jsonb_build_object('linhas', to_jsonb(array['Não tenho nada para perguntar agora: o que dependia de você já está respondido.']),
                              'dados', jsonb_build_object('oss', '[]'::jsonb, 'resto', '[]'::jsonb, 'voce', false));
  end if;
  l_cab := case when v_n = 0 then 'Para montar a semana:'
                else 'Para montar a semana, uma resposta por OS'
                     || case when v_chute then ' (entre parênteses, o meu chute pelo valor)' else '' end || ':' end;
  l_pe := 'Pode ser um áudio só'
          || case when v_n > 0 then ', citando o nome do cliente.' else '.' end
          || case when jsonb_array_length(v_resto) > 0 then
               ' (' || public._agenda_nomes(v_resto, null, 'np')
               || case when jsonb_array_length(v_resto) = 1 then ' fica' else ' ficam' end || ' para depois.)'
             else '' end;

  return jsonb_build_object(
    'linhas', to_jsonb(array[l_cab] || v_bul || array[l_voce, l_pe]),
    'dados', jsonb_build_object(
      'oss', (select coalesce(jsonb_agg(e ->> 'numero' order by o), '[]'::jsonb)
                from jsonb_array_elements(v_cand) with ordinality t(e, o) where o <= p_k),
      'resto', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb)
                  from jsonb_array_elements(v_resto) with ordinality t(e, o)),
      'voce', l_voce is not null));
end;
$function$;

comment on function public._agenda_aprontar_de(jsonb, integer) is 'Agenda de Produção (Fase 1, P4): as linhas da rodada de aprontar a partir do painel, com até p_k OS.';

create or replace function public.agenda_aprontar(p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_pn  jsonb;
  v_r   jsonb;
  v_max int;
  v_t   text;
  k     int;
begin
  if p_hoje is null then
    raise exception 'agenda_aprontar: sem o dia de hoje' using errcode = '22004';
  end if;
  v_pn := public._agenda_painel(p_hoje);
  v_max := (v_pn ->> 'texto_max')::int;
  for k in reverse 5 .. 1 loop
    v_r := public._agenda_aprontar_de(v_pn, k);
    v_t := public._agenda_juntar(array(select jsonb_array_elements_text(v_r -> 'linhas')), null);
    exit when char_length(v_t) <= v_max;
  end loop;
  return jsonb_build_object('ok', true,
    'texto', public._agenda_juntar(array(select jsonb_array_elements_text(v_r -> 'linhas')), v_max),
    'dados', v_r -> 'dados');
end;
$function$;

comment on function public.agenda_aprontar(date) is 'Agenda de Produção (Fase 1, P4): as perguntas da rodada de aprontar — até 5 OS da fila (o que trava primeiro, na ordem de trabalho), uma pergunta por OS juntando o que só o dono responde e a duração com o chute do banco entre parênteses; "Você: semana que vem fica em campo quais dias?" enquanto o dono não tem padrão; fecha com "Pode ser um áudio só, citando o nome do cliente." e o que ficou para depois. {ok, texto ≤ texto_max, dados}.';

-- ── 9. Simulação e "se o cliente aprovar" ───────────────────────────────────────────────────────────────

create or replace function public.agenda_simular(p_dias numeric, p_com_quem jsonb default '[]'::jsonb,
                                                 p_dono text default null, p_autor uuid default null,
                                                 p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_pn     jsonb;
  v_lista  jsonb := case when jsonb_typeof(coalesce(p_com_quem, '[]'::jsonb)) = 'array' then coalesce(p_com_quem, '[]'::jsonb)
                         else jsonb_build_array(p_com_quem) end;
  v_e      jsonb;
  v_ref    text;
  v_turnos text;
  v_rp     jsonb;
  v_gente  jsonb := '[]'::jsonb;
  v_eq     numeric := 0;
  v_com_dono boolean := false;
  v_nomes  text[];
  v_por    text[];
  v_atraso int;
  v_cdia   numeric;
  v_quem   text;
  v_conta  text;
  l1 text; l2 text;
begin
  if p_hoje is null then
    raise exception 'agenda_simular: sem o dia de hoje' using errcode = '22004';
  end if;
  if p_dias is null or p_dias <= 0 or p_dias > 60 then
    return jsonb_build_object('ok', false, 'texto', 'Para simular, diga quantos dias o serviço leva (por exemplo, 2 dias).');
  end if;
  if p_dono is not null and p_dono not in ('abre_e_fecha', 'sempre', 'nunca') then
    raise exception 'agenda_simular: presença do dono "%" não existe (abre_e_fecha, sempre ou nunca)', p_dono using errcode = '22023';
  end if;
  v_pn := public._agenda_painel(p_hoje);
  v_cdia := (v_pn ->> 'cap_dia')::numeric;

  -- Quem vai: nomes ("eu", "Roberto") ou {pessoa, turnos}. Pessoa que não existe = a frase do resolvedor.
  for v_e in select x from jsonb_array_elements(v_lista) x loop
    v_ref := case when jsonb_typeof(v_e) = 'string' then v_e #>> '{}' else v_e ->> 'pessoa' end;
    v_turnos := coalesce(case when jsonb_typeof(v_e) = 'object' then v_e ->> 'turnos' end, 'dia');
    if v_turnos not in ('dia', 'manha', 'tarde') then
      raise exception 'agenda_simular: turno "%" não existe (dia, manha ou tarde)', v_turnos using errcode = '22023';
    end if;
    v_rp := public.agenda_resolver_pessoa(v_ref, p_autor, p_hoje);
    if v_rp ->> 'status' <> 'ok' then
      return jsonb_build_object('ok', false, 'texto', v_rp ->> 'texto', 'pergunta', v_rp ->> 'texto');
    end if;
    if exists (select 1 from jsonb_array_elements(v_gente) g where g ->> 'payee_id' = v_rp ->> 'payee_id') then
      continue;
    end if;
    v_gente := v_gente || jsonb_build_object('payee_id', v_rp ->> 'payee_id', 'nome', v_rp ->> 'nome_curto',
                                             'eh_dono', (v_rp ->> 'eh_dono')::boolean, 'turnos', v_turnos,
                                             -- a mesma conta de os_prontidao: só um turno = 1 meio-dia por dia ocupado
                                             'diarias', trim_scale(case when v_turnos = 'dia' then p_dias * 2
                                                                        else ceil(p_dias) end / 2));
  end loop;
  v_com_dono := exists (select 1 from jsonb_array_elements(v_gente) g where (g ->> 'eh_dono')::boolean);

  -- As diárias da equipe: os meios-dias ÷ 2 de quem é equipe (o dia todo = dias × 2; só um turno = 1 por dia ocupado;
  -- você só entra quando tem padrão). Sem ninguém dito,
  -- a equipe sugerida.
  if jsonb_array_length(v_gente) = 0 then
    v_eq := p_dias * (v_pn ->> 'equipe_sugerida')::int;
    v_quem := '';
    v_conta := format('(conto %s pessoas, %s, porque você não disse com quem)', v_pn ->> 'equipe_sugerida',
                      public._agenda_plural(ceil(v_eq)::int, 'diária', 'diárias'));
    if v_eq <> trunc(v_eq) then
      v_conta := format('(conto %s pessoas, %s diárias, porque você não disse com quem)', v_pn ->> 'equipe_sugerida',
                        public._agenda_num(v_eq, 2));
    end if;
  else
    select coalesce(sum((g ->> 'diarias')::numeric) filter (where not (g ->> 'eh_dono')::boolean
                                                            or (v_pn ->> 'dono_padrao')::boolean), 0)
      into v_eq from jsonb_array_elements(v_gente) g;
    v_nomes := array(select case when (g ->> 'eh_dono')::boolean then 'você' else g ->> 'nome' end
                              || case g ->> 'turnos' when 'manha' then ' (de manhã)' when 'tarde' then ' (à tarde)' else '' end
                       from jsonb_array_elements(v_gente) with ordinality t(g, o)
                      order by (g ->> 'eh_dono')::boolean desc, o);
    v_quem := ' com ' || public._agenda_lista(v_nomes, null);
    v_por := array(select format('%s %s', case when (g ->> 'eh_dono')::boolean then 'você' else g ->> 'nome' end,
                                 public._agenda_num((g ->> 'diarias')::numeric, 2))
                     from jsonb_array_elements(v_gente) with ordinality t(g, o)
                    where not (g ->> 'eh_dono')::boolean or (v_pn ->> 'dono_padrao')::boolean
                    order by (g ->> 'eh_dono')::boolean desc, o);
    v_conta := '(são ' || case when v_eq = 1 then '1 diária de equipe' else public._agenda_num(v_eq, 2) || ' diárias de equipe' end
               || case when cardinality(v_por) > 1 then ': ' || public._agenda_lista(v_por, null) else '' end
               || case when v_com_dono and not (v_pn ->> 'dono_padrao')::boolean then '; você não entra nessa conta' else '' end
               || ')';
    if v_eq = 0 then
      v_conta := '(é só você, e você não entra na conta da equipe)';
    end if;
  end if;
  if p_dono is not null and not v_com_dono then
    v_quem := v_quem || case p_dono when 'abre_e_fecha' then ', você abre e fecha' when 'sempre' then ', você junto o tempo todo'
                                    else ', sem você' end;
  end if;

  l1 := format('Um serviço de %s%s %s: ', public._agenda_dias(p_dias), v_quem, v_conta);
  if v_cdia is null or v_cdia <= 0 then
    l1 := l1 || 'não sei o ritmo da equipe (não há diárias lançadas para medir), então não sei dizer quando cabe.';
    l2 := 'É projeção: não reserva nada.';
  else
    l1 := l1 || case
      when (v_pn #>> '{backlog,n}')::int = 0 or v_pn -> 'livre' is null or jsonb_typeof(v_pn -> 'livre') = 'null' then
        'a fila está vazia, começa ' || public._dia_curto((v_pn ->> 'inicio_furando')::date) || '.'
      when v_pn #>> '{livre,ot}' = v_pn #>> '{livre,re}' then
        'no fim da fila, começa por volta de ' || public._dia_curto((v_pn #>> '{livre,ot}')::date) || '.'
      else format('no fim da fila, começa entre %s e %s.', public._dia_curto((v_pn #>> '{livre,ot}')::date),
                  public._dia_curto((v_pn #>> '{livre,re}')::date)) end;
    v_atraso := ceil(v_eq / v_cdia)::int;
    l2 := case when (v_pn #>> '{backlog,n}')::int = 0 then ''
               else format('Passando na frente de tudo, dá para começar %s, e o resto %s. ',
                           public._dia_curto((v_pn ->> 'inicio_furando')::date),
                           case when v_atraso = 0 then 'não atrasa'
                                when v_atraso = 1 then 'atrasa uns 1 dia útil'
                                else format('atrasa uns %s dias úteis', v_atraso) end) end
          || 'É projeção: não reserva nada.';
    l2 := replace(l2, 'uns 1 dia útil', '1 dia útil');
  end if;

  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(array[l1 || ' ' || l2], (v_pn ->> 'texto_max')::int),
    'dados', jsonb_build_object('dias', p_dias, 'com_quem', v_gente, 'diarias_equipe', trim_scale(v_eq),
                                'fila', v_pn -> 'livre', 'inicio_furando', v_pn -> 'inicio_furando', 'atraso_du', v_atraso));
end;
$function$;

comment on function public.agenda_simular(numeric, jsonb, text, uuid, date) is 'Agenda de Produção (Fase 1, P4): serviço hipotético sem orçamento ("um serviço de 2 dias, eu e o Roberto") — as diárias da equipe (meios-dias ÷ 2 de quem é equipe: o dia todo = dias × 2, só de manhã ou só à tarde = 1 por dia ocupado; o dono fora da conta enquanto não tem padrão), no fim da fila (a faixa do livre de verdade) e passando na frente (agenda_somar_du(p_hoje, congelamento_du + 1); o resto atrasa ceil(diárias ÷ capacidade diária) dias úteis). "É projeção: não reserva nada." Pessoa que não existe = {ok:false, texto do resolvedor}.';

create or replace function public.agenda_ctp(p_so_id uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_pn     jsonb;
  v_p      jsonb;
  v_d      jsonb;
  v_n      int;
  v_e      int;
  v_maxd   date;
  v_imat   date;
  v_ot     date;
  v_re     date;
  v_dre    numeric;
  v_dur    text;
  v_falta  text;
  v_fila   text;
  v_cli    text;
  v_cond   boolean;
  l1 text; l2 text;
begin
  if p_hoje is null then
    raise exception 'agenda_ctp: sem o dia de hoje' using errcode = '22004';
  end if;
  v_p := public.os_prontidao(p_so_id, p_hoje);
  if not coalesce((v_p ->> 'ok')::boolean, false) then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;
  if (v_p ->> 'na_carteira')::boolean then
    return jsonb_build_object('ok', true,
      'texto', format('%s (%s) já está %s: %s.', v_p ->> 'numero', v_p ->> 'cliente_curto',
                      case when (v_p ->> 'eh_orcamento')::boolean then 'aprovado' else 'aprovada' end, v_p ->> 'estado_texto'),
      'dados', jsonb_build_object('numero', v_p ->> 'numero', 'na_carteira', true, 'estado', v_p ->> 'estado'));
  end if;
  v_pn := public._agenda_painel(p_hoje);
  v_d := v_p -> 'duracao';

  -- A duração: o que o dono disse, ou a faixa pelo valor.
  v_dur := case when coalesce((v_d ->> 'sem_base')::boolean, false) then 'sem base para estimar os dias'
                else v_d ->> 'texto' end;
  v_dre := coalesce((v_d ->> 'dias_realista')::numeric, (v_d ->> 'dias')::numeric);

  -- O que falta comprar (críticos fora da mão): sem fornecedor = "de quem?"; com classe, "se comprar hoje, chegam …".
  select count(*) filter (where e ->> 'nivel' <> 'A'),
         count(*) filter (where e ->> 'nivel' <> 'A' and (e ->> 'sem_data')::boolean),
         max((e ->> 'data')::date) filter (where e ->> 'nivel' <> 'A')
    into v_n, v_e, v_maxd
    from jsonb_array_elements(v_p #> '{material,itens}') e where (e ->> 'critico')::boolean;
  v_falta := case
    when v_n = 0 and jsonb_array_length(v_p #> '{material,itens}') = 0 then 'o orçamento não tem peça'
    when v_n = 0 then 'o material está na mão'
    when v_e > 0 then public._agenda_plural(v_n, 'item', 'itens') || ' a comprar (de quem?)'
    else public._agenda_plural(v_n, 'item', 'itens') || ' a comprar (se comprar hoje, '
         || case when v_n = 1 then 'chega' else 'chegam' end || ' por volta de ' || public._dia_curto(v_maxd) || ')' end;
  v_cond := v_n > 0;
  if v_n > 0 and v_e = 0 and v_maxd is not null then
    v_imat := public.agenda_somar_du(v_maxd, c.folga_material_du);
  end if;

  l1 := format('%s (%s), se o cliente aprovar hoje: %s e %s.', v_p ->> 'numero', v_p ->> 'cliente_curto', v_dur, v_falta);

  if v_pn -> 'livre' is null or jsonb_typeof(v_pn -> 'livre') = 'null' then
    if (v_pn #>> '{backlog,n}')::int = 0 then
      v_ot := (v_pn ->> 'inicio_furando')::date; v_re := v_ot;
    end if;
  else
    v_ot := (v_pn #>> '{livre,ot}')::date; v_re := (v_pn #>> '{livre,re}')::date;
  end if;

  if v_ot is null then
    l1 := l1 || ' Pela fila: não sei o ritmo da equipe (não há diárias lançadas para medir).';
    l2 := 'É projeção: não reserva nada.';
  else
    v_ot := greatest(v_ot, v_imat); v_re := greatest(v_re, v_imat);
    v_fila := case when v_ot = v_re then 'começa por volta de ' || public._dia_curto(v_ot)
                   else format('começa entre %s e %s', public._dia_curto(v_ot), public._dia_curto(v_re)) end
              || case when (v_pn #>> '{cap,conta_dono}')::boolean then '' else ' (sem contar você)' end
              || case when v_n > 0 and v_e > 0 then ', e só depois que as peças chegarem' else '' end;
    l1 := l1 || ' Pela fila de hoje, ' || v_fila || '.';
    -- A frase ao cliente: em faixa ou condicional enquanto o material não está na mão (d09).
    if coalesce((v_d ->> 'sem_base')::boolean, false) then
      v_cli := 'Para o cliente, ainda não: o orçamento não dá base para estimar os dias.';
    else
      v_cli := format('Para o cliente: "a partir de %s, %s de serviço%s".', to_char(v_ot, 'DD/MM'),
                      case when v_dre <= 0.5 then 'meio dia'
                           when ceil(v_dre) = 1 then '1 dia'
                           else format('uns %s dias', ceil(v_dre)::int) end,
                      case when v_cond then '; confirmo a data quando as peças chegarem' else '' end);
    end if;
    l2 := v_cli || ' É projeção: não reserva nada.';
  end if;

  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(array[l1, l2], (v_pn ->> 'texto_max')::int),
    'dados', jsonb_build_object('numero', v_p ->> 'numero', 'duracao', v_d, 'faltam', v_n, 'sem_fornecedor', v_e,
                                'inicio', jsonb_build_object('de', v_ot, 'ate', v_re), 'condicional', v_cond));
end;
$function$;

comment on function public.agenda_ctp(uuid, date) is 'Agenda de Produção (Fase 1, P4): "se o cliente aprovar hoje, quando dá?" — a duração (do dono ou pelo valor), o que falta comprar ("de quem?" ou "se comprar hoje, chegam …"), o início pela fila de hoje (a faixa do livre de verdade) e não antes do material (chegada + folga_material_du) quando há classe, e a frase pronta ao cliente, condicional enquanto o material não está na mão (d09). OS já aprovada: diz o estado. "É projeção: não reserva nada."';

-- ── 10. O fechamento das 17:30 ──────────────────────────────────────────────────────────────────────────

create or replace function public.agenda_textos_do_fechamento(p_hoje date default public._hoje_brt(), p_dia date default null)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_pn     jsonb;
  v_dia    date;
  v_marc   jsonb;
  v_prox   jsonb;
  v_prontos jsonb;
  v_esp    int;
  v_plano  boolean;
  v_seg    date;
  v_cauda  text;
  v_sem    text[] := '{}';
  v_l      text;
  k        int;
  c_max    constant int := 160;
begin
  if p_hoje is null then
    raise exception 'agenda_textos_do_fechamento: sem o dia de hoje' using errcode = '22004';
  end if;
  if c.modo_leitura = 'desligado' then
    return jsonb_build_object('modo', c.modo_leitura, 'cauda_amanha', null, 'semana_que_vem', '[]'::jsonb,
                              'dia_do_plano', false);
  end if;
  v_dia := coalesce(p_dia, p_hoje + 1);
  v_pn := public._agenda_painel(p_hoje);
  v_plano := extract(isodow from p_hoje)::int = c.dia_do_plano;

  select coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_prontos from jsonb_array_elements(v_pn -> 'oss') e where e ->> 'grupo' = 'pronto';
  select count(*) into v_esp from jsonb_array_elements(v_pn -> 'oss') e where (e ->> 'dono_trava')::boolean;

  -- A cauda do "Amanhã" sem nada marcado. Se a agenda vê algo marcado no dia, não há cauda (o Secretário diz o dia).
  v_marc := public._agenda_marcados(v_dia, v_dia, p_hoje, null, (v_pn ->> 'dono_usuario')::uuid);
  if jsonb_array_length(v_marc) = 0 then
    v_cauda := 'nada marcado; '
      || case when jsonb_array_length(v_prontos) > 0 then 'prontos para começar: ' || public._agenda_nomes(v_prontos, 3)
              when (v_pn #>> '{backlog,n}')::int = 0 then 'nenhum serviço na fila'
              when v_esp > 0 then format('nenhum serviço pronto, %s esperando você', v_esp)
              else 'nenhum serviço pronto ainda' end
      || ' (*agenda*)';
  end if;

  -- Só no dia do plano (quinta): até 3 linhas da semana que vem, cada uma com até 160 caracteres.
  if v_plano then
    v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1) + 7;
    v_prox := public._agenda_marcados(v_seg, v_seg + 5, p_hoje, null, (v_pn ->> 'dono_usuario')::uuid);
    for k in reverse 3 .. 1 loop
      v_l := 'Semana que vem (projeção): '
             || case when jsonb_array_length(v_prox) = 0 then 'nada marcado'
                     else public._agenda_plural(jsonb_array_length(v_prox), 'marcado', 'marcados') || ' ('
                          || public._agenda_lista(array(select e ->> 'nome' from jsonb_array_elements(v_prox) with ordinality t(e, o)
                                                         order by o), k) || ')' end
             || case when (v_pn #>> '{backlog,n}')::int = 0 then '; nenhum serviço na fila.'
                     else '; ' || public._agenda_plural((v_pn #>> '{backlog,n}')::int, 'serviço na fila', 'serviços na fila')
                          || ', ' || public._agenda_fila_faixa(v_pn)
                          || case when (v_pn ->> 'comprometivel')::numeric > 0
                                  then format(' (~%s por semana, %s)', public._agenda_num((v_pn ->> 'comprometivel')::numeric, 1),
                                              case when (v_pn #>> '{cap,conta_dono}')::boolean then 'contando você' else 'sem contar você' end)
                                  else '' end || '.' end;
      exit when char_length(v_l) <= c_max;
    end loop;
    v_sem := v_sem || v_l;
    for k in reverse 3 .. 1 loop
      v_l := case when jsonb_array_length(v_prontos) > 0 then 'Prontos para começar: ' || public._agenda_nomes(v_prontos, k)
                  else 'Nenhum pronto para começar' end
             || case when v_esp > 0 then '; o que falta de você está em *agenda*.'
                     when jsonb_array_length(v_prontos) > 0 then '.' else ' ainda.' end;
      exit when char_length(v_l) <= c_max;
    end loop;
    v_sem := v_sem || v_l;
    v_l := public._agenda_livre_linha(v_pn, false);
    if v_l is not null then v_sem := v_sem || v_l; end if;
    v_sem := array(select x from unnest(v_sem) x where char_length(x) <= c_max);
  end if;

  return jsonb_build_object('modo', c.modo_leitura, 'cauda_amanha', v_cauda, 'semana_que_vem', to_jsonb(v_sem),
                            'dia_do_plano', v_plano, 'dia', v_dia,
                            'dados', jsonb_build_object('prontos', jsonb_array_length(v_prontos), 'esperando_voce', v_esp,
                                                        'fila', v_pn -> 'backlog', 'livre', v_pn -> 'livre'));
end;
$function$;

comment on function public.agenda_textos_do_fechamento(date, date) is 'Agenda de Produção (Fase 1, P4): as linhas da agenda no fechamento das 17:30 — cauda_amanha (o "Amanhã" sem nada marcado: "nada marcado; nenhum serviço pronto, 7 esperando você (*agenda*)" ou "nada marcado; prontos para começar: …"; null quando a agenda vê algo marcado em p_dia) e, só quando isodow(p_hoje) = dia_do_plano, até 3 linhas "Semana que vem (projeção)" de até 160 caracteres. modo_leitura desligado: nada. O Secretário (P6) decide o que publica (sombra × ligado).';

-- ── 11. O despacho único: agenda_ver ────────────────────────────────────────────────────────────────────

-- O dia do dono (hoje/amanhã sem pessoa): o marcado + o bloco 2 resumido.
create or replace function public._agenda_dia_de(p_pn jsonb, p_dia date, p_k integer)
 returns text[]
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_hoje date := (p_pn ->> 'hoje')::date;
  v_marc jsonb := public._agenda_marcados(p_dia, p_dia, v_hoje, null, (p_pn ->> 'dono_usuario')::uuid);
  v_trav jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_trav from jsonb_array_elements(p_pn -> 'oss') e where (e ->> 'dono_trava')::boolean;
  return array[
    public._agenda_dia_rotulo(p_dia, v_hoje) || ': '
      || coalesce(nullif(public._agenda_lista(array(select e ->> 'texto_dia' from jsonb_array_elements(v_marc)
                                                     with ordinality t(e, o) order by o), p_k), ''), 'nada marcado') || '.',
    case when jsonb_array_length(v_trav) = 0 then 'Nada travado esperando você.'
         else 'Travado esperando você: ' || public._agenda_nomes(v_trav, p_k)
              || ' (o que falta em cada um: *o que eu tenho que fazer*).' end];
end;
$function$;

comment on function public._agenda_dia_de(jsonb, date, integer) is 'Agenda de Produção (Fase 1, P4): o dia do dono (hoje/amanhã) — o marcado e o bloco "travado esperando você" resumido.';

-- A visão de uma OS: o estado, o que trava, a duração, a presença do dono, o material e o prazo.
create or replace function public._agenda_ver_os(p_so_id uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c      public.agenda_config := public._agenda_cfg();
  v_p    jsonb := public.os_prontidao(p_so_id, p_hoje);
  v_o    jsonb;
  v_trav text[];
  v_info text[];
  v_pres text;
  l1 text; l2 text; l3 text; l4 text; l5 text; l6 text; l7 text;
begin
  if not coalesce((v_p ->> 'ok')::boolean, false) then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;
  v_o := jsonb_build_object('curto', v_p ->> 'cliente_curto', 'numero', v_p ->> 'numero');
  l1 := public._agenda_rotulo(v_o, 'num') || ': ' || (v_p ->> 'estado_texto') || '.';
  v_trav := array(select e ->> 'texto' from jsonb_array_elements(v_p -> 'restricoes') with ordinality t(e, o)
                   where (e ->> 'bloqueia')::boolean order by o);
  if cardinality(v_trav) > 1 then
    l2 := 'O que trava: ' || array_to_string(v_trav, '; ') || case when right(array_to_string(v_trav, '; '), 1) = '?' then '' else '.' end;
  end if;
  l3 := 'Duração: ' || (v_p #>> '{duracao,texto}') || case when right(v_p #>> '{duracao,texto}', 1) = '?' then '' else '.' end;
  v_pres := case v_p #>> '{presenca_dono,presenca}'
    when 'abre_e_fecha' then 'você abre e fecha (não fica o dia todo)'
    when 'sempre' then 'você fica o tempo todo'
    when 'nunca' then 'você não vai'
    else null end;
  if v_pres is not null then
    l4 := 'Presença: ' || v_pres
          || case when v_p #>> '{presenca_dono,fonte}' = 'dono' then ' (você disse)'
                  when v_p #>> '{presenca_dono,motivo}' in ('diagnóstico', 'comissionamento', 'marina nova')
                    then ' (' || (v_p #>> '{presenca_dono,motivo}') || ')'
                  else '' end || '.';
  end if;
  l5 := 'Material: ' || public._agenda_material_resumo(v_p) || case when right(public._agenda_material_resumo(v_p), 1) = '?' then '' else '.' end;
  v_info := array(select e ->> 'texto' from jsonb_array_elements(v_p -> 'restricoes') with ordinality t(e, o)
                   where not (e ->> 'bloqueia')::boolean and e ->> 'tipo' in ('bem', 'nao_antes') order by o);
  if cardinality(v_info) > 0 then
    l6 := 'Também: ' || array_to_string(v_info, '; ') || '.';
  end if;
  if (v_p ->> 'na_carteira')::boolean and v_p ->> 'prazo_efetivo' is not null then
    l7 := 'Prazo: ' || case when (v_p ->> 'prazo_efetivo')::date < p_hoje then 'passou em ' else '' end
          || public._dia_curto((v_p ->> 'prazo_efetivo')::date)
          || case when v_p ->> 'prazo_fonte' = 'dono' then ' (o cliente disse)'
                  else format(' (o meu padrão: %s dias úteis desde a aprovação)', c.prazo_padrao_du) end || '.';
  end if;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(array[l1, l2, l3, l4, l5, l6, l7], c.texto_max),
    'dados', jsonb_build_object('numero', v_p ->> 'numero', 'estado', v_p ->> 'estado'));
end;
$function$;

comment on function public._agenda_ver_os(uuid, date) is 'Agenda de Produção (Fase 1, P4): a visão de uma OS — o estado, o que trava, a duração, a presença do dono, o material numa linha, o bem/não antes de e o prazo.';

create or replace function public.agenda_ver(p_autor uuid default null, p_periodo text default null,
                                             p_pessoa text default null, p_foco text default null, p_os text default null,
                                             p_simular jsonb default null, p_simular_aprovacao boolean default false,
                                             p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_foco    text := coalesce(nullif(btrim(lower(p_foco)), ''), 'tudo');
  v_rp      jsonb;
  v_payee   uuid;
  v_eh_dono boolean := true;
  v_de      date;
  v_ate     date;
  v_ro      jsonb;
  v_r       jsonb;
  v_pn      jsonb;
  v_rota    text;
  v_max     int;
  v_l       text[];
  k         int;
begin
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos ou aprontar)', p_foco
      using errcode = '22023';
  end if;
  if p_hoje is null then
    raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
  end if;
  -- Desligada (agenda_config.modo_leitura), a agenda de produção não responde: o assistente volta à agenda de antes
  -- (my_agenda: tarefas e compromissos do dono). Quem não lê agenda_config continua recebendo erro (nunca "livre").
  if (public._agenda_cfg()).modo_leitura = 'desligado' then
    return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                              'texto', 'A agenda de produção está desligada agora.');
  end if;

  -- Pessoa: "eu" ou o nome. Quem não existe ou é ambíguo volta a frase do resolvedor (nunca um erro cru).
  if nullif(btrim(p_pessoa), '') is not null then
    v_rp := public.agenda_resolver_pessoa(p_pessoa, p_autor, p_hoje);
    if v_rp ->> 'status' <> 'ok' then
      return jsonb_build_object('ok', false, 'rota', 'pessoa', 'texto', v_rp ->> 'texto', 'pergunta', v_rp ->> 'texto',
                                'opcoes', coalesce(v_rp -> 'opcoes', '[]'::jsonb));
    end if;
    v_payee := (v_rp ->> 'payee_id')::uuid;
    v_eh_dono := coalesce((v_rp ->> 'eh_dono')::boolean, false);
  end if;

  -- Período: hoje, amanhã, semana, próxima semana ou o que o dono disse.
  begin
    select x.de, x.ate into v_de, v_ate from public._agenda_periodo(p_periodo, p_hoje) x;
  exception when sqlstate '22007' then
    return jsonb_build_object('ok', false, 'rota', 'periodo', 'texto', sqlerrm, 'pergunta', sqlerrm);
  end;

  if coalesce(p_simular_aprovacao, false) and nullif(btrim(p_os), '') is null then
    return jsonb_build_object('ok', false, 'rota', 'ctp',
      'texto', 'Diga qual orçamento: o nome do cliente ou o número (por exemplo, ORÇ-00119).',
      'pergunta', 'Diga qual orçamento: o nome do cliente ou o número (por exemplo, ORÇ-00119).');
  end if;

  if nullif(btrim(p_os), '') is not null then
    v_ro := public.agenda_resolver_os(p_os, p_hoje, coalesce(p_simular_aprovacao, false));
    if v_ro ->> 'status' in ('nao_achei', 'ambiguo') then
      return jsonb_build_object('ok', false, 'rota', 'os', 'texto', v_ro ->> 'texto',
                                'pergunta', case when v_ro ->> 'status' = 'ambiguo' then v_ro ->> 'texto' end,
                                'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
    end if;
    if coalesce(p_simular_aprovacao, false) then
      v_rota := 'ctp';
      v_r := public.agenda_ctp((v_ro ->> 'id')::uuid, p_hoje);
    elsif v_ro ->> 'status' = 'fora_da_carteira' then
      v_rota := 'os';
      v_r := jsonb_build_object('ok', true, 'texto', v_ro ->> 'texto', 'dados', jsonb_build_object('numero', v_ro ->> 'numero'));
    elsif v_foco = 'material' then
      v_rota := 'material_os';
      v_r := public.agenda_ver_material((v_ro ->> 'id')::uuid, p_hoje);
    else
      v_rota := 'os';
      v_r := public._agenda_ver_os((v_ro ->> 'id')::uuid, p_hoje);
    end if;
  elsif p_simular is not null and jsonb_typeof(p_simular) = 'object' then
    v_rota := 'simular';
    v_r := public.agenda_simular((p_simular ->> 'dias')::numeric, coalesce(p_simular -> 'com_quem', '[]'::jsonb),
                                 nullif(p_simular ->> 'dono', ''), p_autor, p_hoje);
  elsif v_foco = 'o_que_fazer' then
    if v_payee is not null and not v_eh_dono then
      v_rota := 'dia_da_pessoa';
      v_r := public.agenda_dia_da_pessoa(v_payee, coalesce(v_de, p_hoje), p_hoje);
    else
      v_rota := 'o_que_fazer';
      v_r := public.agenda_o_que_fazer(coalesce(v_payee, public._agenda_dono(p_autor)), p_hoje);
    end if;
  elsif v_foco in ('atrasos', 'riscos') then
    v_rota := 'atrasos';
    v_r := public.agenda_atrasos(p_hoje);
  elsif v_foco = 'material' then
    v_rota := 'material';
    v_r := public.agenda_ver_material(null, p_hoje);
  elsif v_foco = 'livre' then
    v_rota := 'livre';
    v_r := public.agenda_semana(null, null, p_hoje);
    v_r := jsonb_build_object('ok', true,
      'texto', public._agenda_juntar(array[v_r #>> '{dados,textos,resumo}', v_r #>> '{dados,textos,livre}'],
                                     (select texto_max from public._agenda_cfg())),
      'dados', jsonb_build_object('fila', v_r #> '{dados,fila}', 'livre', v_r #> '{dados,livre}',
                                  'capacidade', v_r #> '{dados,capacidade}'));
  elsif v_foco = 'aprontar' then
    v_rota := 'aprontar';
    v_r := public.agenda_aprontar(p_hoje);
  elsif v_payee is not null and not v_eh_dono and (v_de is null or v_de = v_ate) then
    v_rota := 'dia_da_pessoa';
    v_r := public.agenda_dia_da_pessoa(v_payee, coalesce(v_de, p_hoje), p_hoje);
  elsif v_de is not null and v_de = v_ate then
    v_rota := 'dia';
    v_pn := public._agenda_painel(p_hoje);
    v_max := (v_pn ->> 'texto_max')::int;
    for k in reverse 5 .. 1 loop
      v_l := public._agenda_dia_de(v_pn, v_de, k);
      exit when char_length(public._agenda_juntar(v_l, null)) <= v_max;
    end loop;
    v_r := jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, v_max), 'dados', jsonb_build_object('dia', v_de));
  else
    v_rota := 'semana';
    v_r := public.agenda_semana(v_de, v_ate, p_hoje);
  end if;

  return v_r || jsonb_build_object('rota', v_rota);
end;
$function$;

comment on function public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date) is 'Agenda de Produção (Fase 1, P4): o despacho ÚNICO da ferramenta agenda_ver e dos comandos sem IA. os + simular_aprovacao → agenda_ctp; os + foco material → agenda_ver_material; os → a visão da OS; simular {dias, com_quem, dono} → agenda_simular; foco o_que_fazer → agenda_o_que_fazer (pessoa que não é o dono: o dia dela); atrasos/riscos → agenda_atrasos; material → agenda_ver_material(null); livre → resumo + livre de agenda_semana; aprontar → agenda_aprontar; pessoa (não o dono) + 1 dia → agenda_dia_da_pessoa; hoje/amanhã → o dia + o bloco 2 resumido; resto → agenda_semana. periodo: hoje, amanha, semana, proxima_semana ou o que o dono disse. Referência que não existe (OS, pessoa, data) → {ok:false, texto:"Não encontrei …"/a pergunta}; foco fora da lista lança 22023. Devolve {ok, texto, dados, rota}.';

-- ── Portas ──────────────────────────────────────────────────────────────────────────────────────────────
-- Leituras: security invoker (a RLS de quem lê vale), STABLE/IMMUTABLE, sem anon; authenticated (o painel, com o
-- login do admin) e service_role (o WhatsApp e o fechamento).
revoke all on function
  public._agenda_maiuscula(text), public._agenda_num(numeric, integer), public._agenda_plural(integer, text, text),
  public._agenda_corta(text, integer), public._agenda_dia_rotulo(date, date), public._agenda_periodo_rotulo(date, date, date),
  public._agenda_periodo(text, date), public._agenda_rotulo(jsonb, text), public._agenda_nomes(jsonb, integer, text),
  public._agenda_restricao_curta(jsonb), public._agenda_juntar(text[], integer),
  public._agenda_marcados(date, date, date, uuid, uuid), public._agenda_painel(date), public._agenda_lista_de(jsonb, text, text),
  public._agenda_fila_faixa(jsonb), public._agenda_resumo(jsonb, boolean), public._agenda_livre_linha(jsonb, boolean),
  public._agenda_lim(jsonb, text), public._agenda_encolher(jsonb, jsonb), public._agenda_linhas(jsonb),
  public._agenda_semana_de(jsonb, date, date, jsonb, jsonb), public.agenda_semana(date, date, date),
  public._agenda_outras(uuid, date), public._agenda_o_que_fazer_de(jsonb, jsonb, jsonb, jsonb, jsonb),
  public.agenda_o_que_fazer(uuid, date),
  public._agenda_atrasos_de(jsonb, integer), public.agenda_atrasos(date),
  public._agenda_material_resumo(jsonb), public.agenda_ver_material(uuid, date),
  public.agenda_dia_da_pessoa(uuid, date, date),
  public._agenda_aprontar_de(jsonb, integer), public.agenda_aprontar(date),
  public.agenda_simular(numeric, jsonb, text, uuid, date), public.agenda_ctp(uuid, date),
  public.agenda_textos_do_fechamento(date, date),
  public._agenda_dia_de(jsonb, date, integer), public._agenda_ver_os(uuid, date),
  public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)
  from public, anon;
grant execute on function
  public._agenda_maiuscula(text), public._agenda_num(numeric, integer), public._agenda_plural(integer, text, text),
  public._agenda_corta(text, integer), public._agenda_dia_rotulo(date, date), public._agenda_periodo_rotulo(date, date, date),
  public._agenda_periodo(text, date), public._agenda_rotulo(jsonb, text), public._agenda_nomes(jsonb, integer, text),
  public._agenda_restricao_curta(jsonb), public._agenda_juntar(text[], integer),
  public._agenda_marcados(date, date, date, uuid, uuid), public._agenda_painel(date), public._agenda_lista_de(jsonb, text, text),
  public._agenda_fila_faixa(jsonb), public._agenda_resumo(jsonb, boolean), public._agenda_livre_linha(jsonb, boolean),
  public._agenda_lim(jsonb, text), public._agenda_encolher(jsonb, jsonb), public._agenda_linhas(jsonb),
  public._agenda_semana_de(jsonb, date, date, jsonb, jsonb), public.agenda_semana(date, date, date),
  public._agenda_outras(uuid, date), public._agenda_o_que_fazer_de(jsonb, jsonb, jsonb, jsonb, jsonb),
  public.agenda_o_que_fazer(uuid, date),
  public._agenda_atrasos_de(jsonb, integer), public.agenda_atrasos(date),
  public._agenda_material_resumo(jsonb), public.agenda_ver_material(uuid, date),
  public.agenda_dia_da_pessoa(uuid, date, date),
  public._agenda_aprontar_de(jsonb, integer), public.agenda_aprontar(date),
  public.agenda_simular(numeric, jsonb, text, uuid, date), public.agenda_ctp(uuid, date),
  public.agenda_textos_do_fechamento(date, date),
  public._agenda_dia_de(jsonb, date, integer), public._agenda_ver_os(uuid, date),
  public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)
  to authenticated, service_role;

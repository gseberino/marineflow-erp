-- Agenda de Produção, Fase 6 ("Aprendizado"), pacote P2: a OS — o fator de campo por classe (o limiar do "estouro" da vigia),
-- o R$ por diária medido (a duração "pelo valor") e a presença do dono aprendida por classe.
-- Spec: scratchpad agenda-pesquisa/spec-fase6.md (§3.1, §3.2, §5.2, §5.9, §6.2, §6.3). Depende de 20261029100100.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (6 funções novas; 4 recriadas; nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f6p2/montar-migration.mjs (as partes escritas à mão
-- f6p2/parte-0-cabeca.sql, parte-1-novas.sql e parte-9-portas.sql + as 4 recriadas, cada uma com o corpo da definição MAIS NOVA,
-- conferida com grep a cada montagem: fora dos blocos "-- FASE 6:" nenhuma linha muda). Edite o montador, nunca este .sql.
--
-- POR QUE: o P1 mede cada OS concluída; este pacote transforma as medidas em três valores da OS e liga cada um ao único lugar
-- onde ele entra. Nada muda com o modo de aprendizado fora de ligado (nasce desligado; a 20261029101000 o põe em sombra): o
-- leitor único (_agenda_aprendido) devolve nulo e vale o padrão de hoje, byte a byte.
--
-- O QUE MUDA:
--   1. _agenda_aprender_fator(hoje, agora): para cada chave dos 4 níveis (rv:energia → sistema:energia → bem:rv → todas) com
--      medida válida, o P80 (fator_percentil) das fator_amostra_max medidas mais recentes, preso em [fator_min, fator_max], vai ao
--      gravador com padrão = estouro_fator. agenda_fator_de_campo(os, hoje): {fator, padrao, fonte (padrao|aprendido), nivel,
--      chave, n, n_min, teria, estado, classe, texto} — a chave mais fina da classe da OS com n ≥ fator_n_min; fator = o em uso
--      dela, senão estouro_fator; teria = o medido dela, mesmo em teste.
--   2. _agenda_aprender_mo(hoje, agora): Σ mão de obra ÷ Σ diárias ligadas das fator_amostra_max medidas válidas mais recentes com
--      diarista (a OS só do dono fica de fora: o dono nunca tem diária), preso em [mo_min, mo_por_diaria_preco]; item mo, chave
--      todas, padrão mo_por_diaria_real. _agenda_mo_por_diaria_real(): o aprendido em uso, senão mo_por_diaria_real.
--   3. _agenda_aprender_presenca(hoje, agora): nas chaves fina e sistema (entra sozinha) e todas (sempre pergunta: é a regra d05
--      inteira), n = as OS medidas válidas da classe concluídas desde a 1ª ida do dono registrada, k = as dessas a que ele foi
--      sem estar no plano (agenda_intervencoes_do_dono, dita manhã/tarde/dia; "passou" não conta); 1 (o dia todo) quando
--      k ≥ presenca_intervencoes_min, n ≥ presenca_n_min e k/n ≥ presenca_taxa_min, senão 0 (o abre e fecha de hoje).
--      _agenda_presenca_aprendida(os): a aprendida da OS (a chave fina, senão a do sistema, senão a de todas), só com o modo
--      ligado e a presença na lista e só para a OS SEM alocação publicada ou fixada.
--   4. Recriadas (o corpo da definição mais nova + blocos "-- FASE 6:"):
--      · os_duracao_sugerida (de 20261024160400): o realista usa _agenda_mo_por_diaria_real(); com o aprendido em uso a saída
--        ganha mo_fonte = 'aprendido' e mo_por_diaria (sem ele, a saída de antes, byte a byte: a prontidão e o motor a embutem);
--      · os_presenca_do_dono (de 20261024160400): depois do que o dono disse e da regra d05 (diagnóstico, comissionamento,
--        marina nova), e antes do abre e fecha, a aprendida {presenca: sempre, motivo: "você foi a 3 de 4 OS de energia em
--        motorhome", fonte: aprendida};
--      · _agenda_vigia_estouro (de 20261025100300): o limiar = agenda_fator_de_campo(os, hoje).fator (o 1,5 de hoje é o
--        estouro_fator, o padrão); a chave da pergunta (estouro:<os>:<total>) e o texto não mudam;
--      · _agenda_aprendizado_texto (de 20261029100100): os textos do R$ por diária e da presença (spec §6.2/§6.3) antes do fator.
--   5. Portas: _agenda_classe_de_campo passa a ler para authenticated e service_role (é leitura invoker: só lê o que o login lê);
--      a presença aprendida e o fator de campo são lidos de dentro de funções invoker (os_presenca_do_dono, a vigia).
--
-- DESVIOS DA SPEC (provados em supabase/tests/agenda_fase6_os.sql):
--   · os_presenca_do_dono CONTINUA language sql (a spec dizia "passa a plpgsql"): a aprendida entra como uma coluna do CTE e um
--     "when" a mais no case, dentro de blocos "-- FASE 6:", e a lógica fica em _agenda_presenca_aprendida (plpgsql). A
--     assinatura, a volatilidade, o invoker e as portas não mudam (O6), e a cópia fora dos blocos é a de 20261024160400.
--   · Os passos recebem p_agora (a spec: só p_hoje): o gravador precisa da hora (a ação, a pergunta, o histórico) e teste não
--     usa now(). A rodada do P6 chama _agenda_aprender_fator/_mo/_presenca(p_hoje, p_agora).
--   · A presença conta n só desde a 1ª ida do dono registrada (a menor agenda_intervencoes_do_dono.dia, qualquer "dita"): antes
--     do registro não há como saber se ele foi, e contar essas OS como "não foi" puxa a taxa para baixo. Com a fixture: 3 de 4
--     (134–137, desde 20/10), e não 3 de 7.
--   · A presença em todas, se o dono disser SIM à pergunta (P6), vale para as OS sem classe aprendida: a ordem é fina → sistema →
--     todas (a spec citava só fina e sistema; a pergunta de todas é "conto com você o dia todo por padrão?").
--   · O R$ por diária segue a regra da spec (todas as medidas válidas com diarista, chave todas), não só as de energia: com a
--     fixture dá R$ 1.096,83 (10 OS, 22.485 ÷ 20,5); o O4 iguala a mão de obra das 3 que não são de energia (138, 139, 144) a
--     R$ 690 × as diárias delas e prova os R$ 690.
--   · os_duracao_sugerida só mostra mo_fonte com o aprendido em uso (a spec: sempre padrao|aprendido): a saída é embutida pela
--     os_prontidao (restrição duracao.sugestao), e em teste ela tem de ser a de antes, byte a byte.
--   · agenda_fator_de_campo também devolve estado e classe; sem chave com N, a chave é todas (a primeira a chegar ao N).
--
-- O QUE NÃO MUDA: o motor (agenda_meios_da_os lê os_presenca_do_dono como antes), a prontidão, a rodada do cliente (o P5 recria
-- _agenda_cliente_risco), o rascunho. Com o modo fora de ligado, nenhuma saída muda. A OS com alocação publicada ou fixada nunca
-- muda de presença pelo aprendizado (o publicado não muda). Nada roda sozinho: a rodada é do P6 (agenda_aprender).
--
-- ORDEM DE LIGAR: depois de 20261029100100; antes de 20261029100300. Aplicar sozinha não muda nada para ninguém.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase6_os.sql (a fixture-fase6 só na bancada; as portas e as cópias em
-- qualquer lugar). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261029100200
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261029100200_agenda_fase6_os.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261029100200', 'agenda_fase6_os');"
--
-- DESFAZER: reaplicar, em ordem, as definições de 20261024160400 (os_duracao_sugerida, os_presenca_do_dono), 20261025100300
-- (_agenda_vigia_estouro) e 20261029100100 (_agenda_aprendizado_texto); as 6 novas podem ficar (ninguém de antes as chama).
--
-- IDEMPOTENTE: create or replace function; revoke/grant.

-- ── 1. O fator de campo ─────────────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_aprender_fator(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c      public.agenda_config := public._agenda_cfg();
  r      record;
  v      jsonb;
  v_p    numeric;
  v_calc numeric;
  v_est  jsonb := '{}'::jsonb;
  n_ch   int := 0;
  n_acao int := 0;
  n_perg int := 0;
  n_err  int := 0;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  for r in
    with med as (
      select m.service_order_id as os, so.service_order_number as numero, m.fator, m.concluida_em,
             m.classe_bem, m.classe_sistema
        from public.agenda_medidas_os m
        join public.service_orders so on so.id = m.service_order_id
       where m.valida and m.fator is not null
         and m.concluida_em between p_hoje - c.aprender_janela_dias and p_hoje),
    chaves as (
      select med.*, x.chave, x.nivel, x.ordem
        from med
        cross join lateral (values (med.classe_bem || ':' || med.classe_sistema, 'fina', 1),
                                   ('sistema:' || med.classe_sistema, 'sistema', 2),
                                   ('bem:' || med.classe_bem, 'bem', 3),
                                   ('todas', 'todas', 4)) x(chave, nivel, ordem)),
    recentes as (
      select ch.*, row_number() over (partition by ch.chave order by ch.concluida_em desc, ch.os) as rn
        from chaves ch),
    por_chave as (
      select rc.chave, rc.nivel, rc.ordem, count(*)::int as n,
             array_agg(rc.fator order by rc.concluida_em desc, rc.os) as fatores,
             jsonb_agg(jsonb_build_object('os', rc.os, 'numero', rc.numero, 'fator', rc.fator, 'em', rc.concluida_em)
                       order by rc.concluida_em desc, rc.os) as amostra
        from recentes rc
       where rc.rn <= c.fator_amostra_max
       group by rc.chave, rc.nivel, rc.ordem)
    select pc.chave, pc.nivel, pc.ordem, pc.n, pc.fatores, pc.amostra from por_chave pc
    union all
    -- a chave que já tem linha e ficou sem medida (a medida deixou de valer, saiu da janela): volta a medir
    select a.chave, a.nivel, case a.nivel when 'fina' then 1 when 'sistema' then 2 when 'bem' then 3 else 4 end,
           0, null::numeric[], '[]'::jsonb
      from public.agenda_aprendizado a
     where a.item = 'fator' and not exists (select 1 from por_chave pc where pc.chave = a.chave)
     order by 3, 1
  loop
    n_ch := n_ch + 1;
    begin
      v_p := public._agenda_percentil(r.fatores, c.fator_percentil);
      v_calc := case when v_p is not null then round(least(greatest(v_p, c.fator_min), c.fator_max), 2) end;
      v := public._agenda_aprendizado_gravar('fator', r.chave, r.nivel, v_calc, r.n, r.amostra, c.estouro_fator,
             jsonb_build_object('p50', round(public._agenda_percentil(r.fatores, 0.5), 2)), p_agora);
      v_est := v_est || jsonb_build_object(v ->> 'estado', coalesce((v_est ->> (v ->> 'estado'))::int, 0) + 1);
      if v ->> 'acao_id' is not null then n_acao := n_acao + 1; end if;
      if v ->> 'pergunta_id' is not null then n_perg := n_perg + 1; end if;
    exception when others then
      perform public.log_app_error('db', format('aprendizado, fator %s: %s', r.chave, sqlerrm), 'agenda', 'aprender:fator', 'error',
                                   jsonb_build_object('chave', r.chave, 'sqlstate', sqlstate, 'p_hoje', p_hoje));
      n_err := n_err + 1;
    end;
  end loop;
  return jsonb_build_object('chaves', n_ch, 'estados', v_est, 'acoes', n_acao, 'perguntas', n_perg, 'erros', n_err);
end;
$function$;

comment on function public._agenda_aprender_fator(date, timestamptz) is
  'Agenda de Produção (Fase 6, P2): o passo do fator de campo da rodada — para cada chave dos 4 níveis (fina rv:energia, sistema:energia, bem:rv, todas) com medida válida na janela (aprender_janela_dias), o P80 (fator_percentil) das fator_amostra_max medidas mais recentes, preso em [fator_min, fator_max] e arredondado a 2 casas, vai ao gravador (_agenda_aprendizado_gravar) com padrão = estouro_fator; a chave que já tinha linha e ficou sem medida volta a medindo. O erro de uma chave vai a app_error_logs (agenda / aprender:fator) e o passo segue. {chaves, estados: {estado: n}, acoes, perguntas, erros}. Sem grant a ninguém.';

create or replace function public.agenda_fator_de_campo(p_os uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_uid   uuid := auth.uid();
  v_papel text;
  c       public.agenda_config;
  v_cl    jsonb;
  v_ch    text;
  a       public.agenda_aprendizado;
  v_esc   public.agenda_aprendizado;
  v_todas public.agenda_aprendizado;
  v_uso   numeric;
begin
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role (a vigia, a rodada). Um JWT de outro papel sem
  -- "sub" não vê. (p_hoje fica no contrato: a leitura é do que já foi gravado pela rodada do dia.)
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'O que a agenda aprendeu é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'O que a agenda aprendeu é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  c := public._agenda_cfg();
  v_cl := public._agenda_classe_de_campo(p_os);
  if v_cl is null then
    return jsonb_build_object('ok', false, 'fator', c.estouro_fator, 'padrao', c.estouro_fator, 'fonte', 'padrao',
                              'texto', 'Não encontrei esse serviço.');
  end if;
  -- A classe mais fina com N (a classe de referência com recuo): fina → sistema → bem → todas.
  foreach v_ch in array array[v_cl ->> 'chave', 'sistema:' || (v_cl ->> 'sistema'), 'bem:' || (v_cl ->> 'bem'), 'todas'] loop
    select * into a from public.agenda_aprendizado x where x.item = 'fator' and x.chave = v_ch;
    if found and v_ch = 'todas' then
      v_todas := a;
    end if;
    if found and a.calculado is not null and a.n >= c.fator_n_min then
      v_esc := a;
      exit;
    end if;
  end loop;
  if v_esc.id is not null then
    v_uso := public._agenda_aprendido('fator', v_esc.chave);
    return jsonb_build_object('ok', true, 'os', p_os, 'classe', v_cl ->> 'chave', 'classe_texto', v_cl ->> 'texto',
                              'fator', coalesce(v_uso, c.estouro_fator), 'padrao', c.estouro_fator,
                              'fonte', case when v_uso is null then 'padrao' else 'aprendido' end,
                              'nivel', v_esc.nivel, 'chave', v_esc.chave, 'n', v_esc.n, 'n_min', c.fator_n_min,
                              'teria', v_esc.calculado, 'estado', v_esc.estado, 'texto', v_esc.texto);
  end if;
  -- Nenhuma chave com N: o padrão, pela chave mais larga (a primeira a chegar ao N).
  return jsonb_build_object('ok', true, 'os', p_os, 'classe', v_cl ->> 'chave', 'classe_texto', v_cl ->> 'texto',
                            'fator', c.estouro_fator, 'padrao', c.estouro_fator, 'fonte', 'padrao',
                            'nivel', 'todas', 'chave', 'todas', 'n', coalesce(v_todas.n, 0), 'n_min', c.fator_n_min,
                            'teria', null, 'estado', coalesce(v_todas.estado, 'medindo'),
                            'texto', coalesce(v_todas.texto,
                                              public._agenda_aprendizado_texto('fator', 'foco_medindo',
                                                jsonb_build_object('chave', 'todas', 'n', 0, 'n_min', c.fator_n_min,
                                                                   'padrao', c.estouro_fator))));
end;
$function$;

comment on function public.agenda_fator_de_campo(uuid, date) is
  'Agenda de Produção (Fase 6, P2): o fator de campo da OS (o limiar do "estouro": a OS que já teve mais meios-dias feitos que fator × o combinado ganha a pergunta "o que falta?") — {ok, os, classe, classe_texto, fator, padrao, fonte (padrao|aprendido), nivel, chave, n, n_min, teria, estado, texto}. A chave é a mais fina da classe da OS (fina → sistema → bem → todas) com n ≥ fator_n_min; fator = o em uso dela (_agenda_aprendido: só com modo_aprendizado ligado e fator na lista), senão estouro_fator; teria = o medido dela, mesmo em teste; texto = a linha do foco. Sem chave com N: o padrão, chave todas. Admin/financeiro ou service_role; senão 42501.';

-- ── 2. O R$ por diária ──────────────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_aprender_mo(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_n      int;
  v_mo     numeric;
  v_dia    numeric;
  v_amos   jsonb;
  v_calc   numeric;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  -- As medidas válidas mais recentes com diarista (diária ligada): a OS só do dono fica de fora (o dono nunca tem diária).
  select count(*)::int, sum(x.mo), sum(x.diarias_ligadas),
         coalesce(jsonb_agg(jsonb_build_object('os', x.service_order_id, 'numero', x.numero, 'mo', x.mo,
                                               'diarias', x.diarias_ligadas, 'em', x.concluida_em)
                            order by x.concluida_em desc, x.service_order_id), '[]'::jsonb)
    into v_n, v_mo, v_dia, v_amos
    from (select m.service_order_id, so.service_order_number as numero, m.mo, m.diarias_ligadas, m.concluida_em
            from public.agenda_medidas_os m
            join public.service_orders so on so.id = m.service_order_id
           where m.valida and not m.so_o_dono and m.diarias_ligadas > 0 and m.mo is not null
             and m.concluida_em between p_hoje - c.aprender_janela_dias and p_hoje
           order by m.concluida_em desc, m.service_order_id
           limit c.fator_amostra_max) x;
  v_calc := case when v_n > 0 and v_dia > 0
                 then round(least(greatest(v_mo / v_dia, c.mo_min), c.mo_por_diaria_preco), 2) end;
  return public._agenda_aprendizado_gravar('mo', 'todas', 'todas', v_calc, v_n, v_amos, c.mo_por_diaria_real,
           jsonb_build_object('mo', coalesce(v_mo, 0), 'diarias', coalesce(v_dia, 0)), p_agora);
end;
$function$;

comment on function public._agenda_aprender_mo(date, timestamptz) is
  'Agenda de Produção (Fase 6, P2): o passo do R$ por diária da rodada — Σ mão de obra (agenda_medidas_os.mo) ÷ Σ diárias ligadas das fator_amostra_max medidas válidas mais recentes da janela com diarista (a OS só do dono fica de fora), preso em [mo_min, mo_por_diaria_preco], vai ao gravador com item mo, chave todas e padrão mo_por_diaria_real. Devolve o que o gravador devolve. Sem grant a ninguém.';

create or replace function public._agenda_mo_por_diaria_real()
 returns numeric
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(public._agenda_aprendido('mo', 'todas'), (public._agenda_cfg()).mo_por_diaria_real);
$function$;

comment on function public._agenda_mo_por_diaria_real() is
  'Agenda de Produção (Fase 6, P2): o R$ de mão de obra por diária que a duração "pelo valor" usa no realista — o aprendido em uso (_agenda_aprendido(''mo'', ''todas''): só com modo_aprendizado ligado e mo na lista), senão agenda_config.mo_por_diaria_real.';

-- ── 3. A presença do dono ───────────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_aprender_presenca(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c      public.agenda_config := public._agenda_cfg();
  v_desde date;
  r      record;
  v      jsonb;
  v_calc numeric;
  v_est  jsonb := '{}'::jsonb;
  n_ch   int := 0;
  n_acao int := 0;
  n_perg int := 0;
  n_err  int := 0;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  -- Desde quando as idas do dono são registradas: a 1ª intervenção (qualquer "dita"). Antes dela não há como saber se ele foi.
  select min(i.dia) into v_desde from public.agenda_intervencoes_do_dono i where i.dia <= p_hoje;
  for r in
    with med as (
      select m.service_order_id as os, so.service_order_number as numero, m.concluida_em, m.classe_bem, m.classe_sistema,
             exists (select 1 from public.agenda_intervencoes_do_dono i
                      where i.service_order_id = m.service_order_id and i.dita in ('manha', 'tarde', 'dia')
                        and i.dia <= p_hoje) as foi
        from public.agenda_medidas_os m
        join public.service_orders so on so.id = m.service_order_id
       where m.valida and v_desde is not null
         and m.concluida_em between greatest(v_desde, p_hoje - c.aprender_janela_dias) and p_hoje),
    chaves as (
      select med.*, x.chave, x.nivel, x.ordem
        from med
        cross join lateral (values (med.classe_bem || ':' || med.classe_sistema, 'fina', 1),
                                   ('sistema:' || med.classe_sistema, 'sistema', 2),
                                   ('todas', 'todas', 3)) x(chave, nivel, ordem)),
    por_chave as (
      select ch.chave, ch.nivel, ch.ordem, count(*)::int as n, count(*) filter (where ch.foi)::int as k,
             jsonb_agg(jsonb_build_object('os', ch.os, 'numero', ch.numero, 'foi', ch.foi, 'em', ch.concluida_em)
                       order by ch.concluida_em desc, ch.os) as amostra
        from chaves ch
       group by ch.chave, ch.nivel, ch.ordem)
    select pc.chave, pc.nivel, pc.ordem, pc.n, pc.k, pc.amostra from por_chave pc
    union all
    -- a chave que já tem linha e ficou sem medida: volta a medir
    select a.chave, a.nivel, case a.nivel when 'fina' then 1 when 'sistema' then 2 else 3 end, 0, 0, '[]'::jsonb
      from public.agenda_aprendizado a
     where a.item = 'presenca' and not exists (select 1 from por_chave pc where pc.chave = a.chave)
     order by 3, 1
  loop
    n_ch := n_ch + 1;
    begin
      -- 1 = o dia todo; 0 = o abre e fecha (o padrão de hoje)
      v_calc := case when r.n = 0 then null
                     when r.k >= c.presenca_intervencoes_min and r.n >= c.presenca_n_min
                          and r.k::numeric / r.n >= c.presenca_taxa_min then 1
                     else 0 end;
      v := public._agenda_aprendizado_gravar('presenca', r.chave, r.nivel, v_calc, r.n, r.amostra, 0,
             jsonb_build_object('k', r.k, 'desde', v_desde), p_agora);
      v_est := v_est || jsonb_build_object(v ->> 'estado', coalesce((v_est ->> (v ->> 'estado'))::int, 0) + 1);
      if v ->> 'acao_id' is not null then n_acao := n_acao + 1; end if;
      if v ->> 'pergunta_id' is not null then n_perg := n_perg + 1; end if;
    exception when others then
      perform public.log_app_error('db', format('aprendizado, presença %s: %s', r.chave, sqlerrm), 'agenda', 'aprender:presenca',
                                   'error', jsonb_build_object('chave', r.chave, 'sqlstate', sqlstate, 'p_hoje', p_hoje));
      n_err := n_err + 1;
    end;
  end loop;
  return jsonb_build_object('desde', v_desde, 'chaves', n_ch, 'estados', v_est, 'acoes', n_acao, 'perguntas', n_perg,
                            'erros', n_err);
end;
$function$;

comment on function public._agenda_aprender_presenca(date, timestamptz) is
  'Agenda de Produção (Fase 6, P2): o passo da presença do dono da rodada — nas chaves fina e sistema (entra sozinha) e todas (sempre pergunta: é a regra d05 inteira), n = as OS com medida válida da classe concluídas desde a 1ª ida do dono registrada (a menor agenda_intervencoes_do_dono.dia; antes dela não há registro) e k = as dessas com ida dele sem estar no plano (dita manha, tarde ou dia; passou não conta). calculado = 1 (o dia todo) com k ≥ presenca_intervencoes_min, n ≥ presenca_n_min e k/n ≥ presenca_taxa_min; senão 0 (o abre e fecha, o padrão). detalhe {k, desde}. O erro de uma chave vai a app_error_logs (agenda / aprender:presenca). {desde, chaves, estados, acoes, perguntas, erros}. Sem grant a ninguém.';

create or replace function public._agenda_presenca_aprendida(p_os uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_lig boolean;
  v_cl  jsonb;
  v_ch  text;
  v_val numeric;
  a     public.agenda_aprendizado;
begin
  -- Só com o modo ligado e a presença na lista. Quem não lê a config (o técnico, pela RLS) fica com a regra de hoje.
  select true into v_lig
    from public.agenda_config c
   where c.id and c.modo_aprendizado = 'ligado'
     and public._agenda_aprendizado_da_lista('presenca') = any (c.aprendizado_ligados);
  if v_lig is null then
    return null;
  end if;
  -- O publicado não muda pelo aprendizado: a OS com alocação publicada ou fixada fica com a regra de hoje.
  if exists (select 1 from public.agenda_alocacoes x where x.service_order_id = p_os and x.estado in ('publicada', 'fixada')) then
    return null;
  end if;
  v_cl := public._agenda_classe_de_campo(p_os);
  if v_cl is null then
    return null;
  end if;
  -- A aprendida mais fina que existir: a da classe, senão a do sistema, senão a de todas (só depois do SIM do dono).
  foreach v_ch in array array[v_cl ->> 'chave', 'sistema:' || (v_cl ->> 'sistema'), 'todas'] loop
    v_val := public._agenda_aprendido('presenca', v_ch);
    exit when v_val is not null;
  end loop;
  if coalesce(v_val, 0) < 1 then
    return null;
  end if;
  select * into a from public.agenda_aprendizado x where x.item = 'presenca' and x.chave = v_ch;
  return jsonb_build_object('presenca', 'sempre',
                            'motivo', format('você foi a %s de %s %s', coalesce(a.detalhe ->> 'k', '0'), a.n,
                                             substr(public._agenda_classe_texto_do_nivel(v_ch), 4)),
                            'fonte', 'aprendida', 'chave', v_ch);
end;
$function$;

comment on function public._agenda_presenca_aprendida(uuid) is
  'Agenda de Produção (Fase 6, P2): a presença do dono aprendida para a OS — {presenca: sempre, motivo: "você foi a 3 de 4 OS de energia em motorhome", fonte: aprendida, chave} quando a aprendida mais fina (a chave fina da classe, senão a do sistema, senão a de todas) é o dia todo; nulo com modo_aprendizado fora de ligado, presenca fora da lista, a OS com alocação publicada ou fixada (o publicado não muda) ou nada aprendido. os_presenca_do_dono a usa depois do que o dono disse e da regra d05.';

-- ── 4. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 6:") ──────────────────
-- Fora dos blocos nenhuma linha muda (o O6 do teste confere). Quem recriar de novo qualquer uma delas copia DESTA migration.

-- _agenda_aprendizado_texto (de 20261029100100_agenda_fase6_medicao.sql)
create or replace function public._agenda_aprendizado_texto(p_item text, p_momento text, p_d jsonb)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_nivel  text := public._agenda_classe_texto_do_nivel(p_d ->> 'chave');
  v_calc   text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'calculado')::numeric);
  v_uso    text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'em_uso')::numeric);
  v_efet   text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'efetivo')::numeric);
  v_padrao text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'padrao')::numeric);
  v_volta  text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'volta')::numeric);
  v_n      text := p_d ->> 'n';
  v_nmin   text := p_d ->> 'n_min';
  v_desde  text := public._dia_curto(nullif(p_d ->> 'desde', '')::date);
  v_trava  text := public._dia_curto(nullif(p_d ->> 'travado_ate', '')::date);
  v_dias   text := p_d ->> 'trava_dias';
  v_rotulo text;
begin
  -- FASE 6: (P2) o R$ por diária (spec-fase6 §6.2 e §6.3): a mão de obra das OS com diária ligada ÷ as diárias ligadas; o
  -- padrão é mo_por_diaria_real, e o valor entra no realista de os_duracao_sugerida ("estimar os dias pelo valor")
  if p_item = 'mo' then
    return case p_momento
      when 'foco_medindo' then format('Valor por diária: %s de %s OS com diária ligada medidas; para estimar os dias pelo valor uso %s (padrão).',
                                      v_n, v_nmin, v_padrao)
      when 'foco_sombra' then format('Em teste: cada diária rendeu %s de mão de obra (%s OS com diária ligada); para estimar os dias pelo valor uso %s (padrão).',
                                     v_calc, v_n, v_padrao)
      when 'foco_em_uso' then format('Cada diária rendeu %s de mão de obra (%s OS com diária ligada): é o que uso para estimar os dias pelo valor desde %s.',
                                     v_uso, v_n, v_desde)
      when 'foco_pergunta' then format('Cada diária rendeu %s de mão de obra (%s OS com diária ligada), e hoje uso %s para estimar os dias pelo valor: a troca espera a sua resposta.',
                                       v_calc, v_n, v_efet)
      when 'foco_travado' then format('Cada diária rendeu %s de mão de obra (%s OS com diária ligada); para estimar os dias pelo valor fico com %s até %s, como você decidiu.',
                                      v_calc, v_n, v_efet, v_trava)
      when 'acao' then format('Cada diária rendeu %s de mão de obra (%s OS): passei a estimar os dias pelo valor com %s (era %s). *desfaz aprendizado* volta.',
                              v_calc, v_n, v_calc, v_efet)
      when 'pergunta' then format('Medi a mão de obra por diária: cada diária rendeu %s (%s OS com diária ligada), e hoje eu uso %s para estimar os dias pelo valor. É uma troca grande.',
                                  v_calc, v_n, v_efet)
      when 'opcao1' then format('Passo a usar %s', v_calc)
      when 'opcao2' then format('Fico com %s', v_efet)
      when 'opcao3' then 'Volto ao padrão'
      when 'desfeito' then format('Desfeito: para estimar os dias pelo valor volto a %s por diária. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                  coalesce(v_volta, v_padrao, 'o padrão'), v_dias)
      when 'fico' then format('Combinado: fico com %s por diária. Volto a perguntar se o medido mudar muito.', v_efet)
    end;
  end if;

  -- (P2) a presença do dono (spec-fase6 §6.2 e §6.3): k = as OS da classe a que ele foi sem estar no plano (detalhe.k) e n
  -- = as OS medidas; 1 = o dia todo, 0 = o abre e fecha (o padrão). Na classe entra sozinha; em todas, sempre pergunta.
  if p_item = 'presenca' and v_nivel is not null then
    declare
      v_foi  text := format('Você foi a %s de %s %s sem estar no plano', coalesce(p_d #>> '{detalhe,k}', '0'), v_n,
                            substr(v_nivel, 4));
      v_onde text := case when p_d ->> 'chave' = 'todas' then 'por padrão' else 'nelas' end;
      v_dia  boolean := coalesce((p_d ->> 'calculado')::numeric, 0) >= 1;
      v_udia boolean := coalesce((p_d ->> 'em_uso')::numeric, 0) >= 1;
      v_edia boolean := coalesce((p_d ->> 'efetivo')::numeric, 0) >= 1;
      v_vdia boolean := coalesce((p_d ->> 'volta')::numeric, 0) >= 1;
    begin
      return case p_momento
        when 'foco_medindo' then format('%s: %s de %s OS medidas para saber se você fica o dia todo; conto com você para abrir e fechar (padrão).',
                                        public._agenda_maiuscula(v_nivel), v_n, v_nmin)
        when 'foco_sombra' then v_foi || case when v_dia then format(': em teste, eu contaria com você o dia todo %s.', v_onde)
                                              else format(': em teste, continuo contando com você só para abrir e fechar %s.', v_onde) end
        when 'foco_em_uso' then v_foi || case when v_udia then format(': conto com você o dia todo %s desde %s.', v_onde, v_desde)
                                              else format(': conto com você só para abrir e fechar %s.', v_onde) end
        when 'foco_pergunta' then v_foi || case when v_dia then ': perguntei se passo a contar com você o dia todo por padrão; espero a sua resposta.'
                                                else ': perguntei se volto a contar com você só para abrir e fechar; espero a sua resposta.' end
        when 'foco_travado' then v_foi || format('; fico com %s até %s, como você decidiu.',
                                                 case when v_edia then 'o dia todo' else 'o abre e fecha' end, v_trava)
        when 'acao' then v_foi || case when v_dia then ': passei a contar com você o dia todo nas próximas dessas OS (as que você não disse como é). *desfaz aprendizado* volta ao abre e fecha.'
                                       else ': voltei a contar com você só para abrir e fechar nas próximas dessas OS (as que você não disse como é). *desfaz aprendizado* volta ao dia todo.' end
        when 'pergunta' then v_foi || case when v_dia then '. Quer que eu conte com você o dia todo por padrão, e não só para abrir e fechar?'
                                           else '. Quer que eu volte a contar com você só para abrir e fechar por padrão?' end
        when 'opcao1' then case when v_dia then 'Sim, o dia todo (recomendo pelo medido)' else 'Sim, só abrir e fechar (recomendo pelo medido)' end
        when 'opcao2' then case when v_dia then 'Não, continuo com o abre e fecha' else 'Não, continuo com o dia todo' end
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: n%s volto a contar com você %s. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                    v_nivel, case when v_vdia then 'o dia todo' else 'só para abrir e fechar' end, v_dias)
        when 'fico' then format('Combinado: fico com %s. Volto a perguntar se o medido mudar muito.',
                                case when v_edia then 'o dia todo' else 'o abre e fecha' end)
      end;
    end;
  end if;
  -- FASE 6: fim
  -- O fator de campo (spec-fase6 §6.2 e §6.3).
  if p_item = 'fator' and v_nivel is not null then
    return case p_momento
      when 'foco_medindo' then format('%s: %s de %s OS medidas; para perguntar o que falta, uso %s o combinado (padrão).',
                                      public._agenda_maiuscula(v_nivel), v_n, v_nmin, v_padrao)
      when 'foco_sombra' then format('Em teste: %s levam até %s o combinado (%s OS); hoje seria %s, e vale %s (padrão).',
                                     v_nivel, v_calc, v_n, v_calc, v_padrao)
      when 'foco_em_uso' then format('%s levam até %s o combinado (%s OS): é o que uso desde %s.',
                                     public._agenda_maiuscula(v_nivel), v_uso, v_n, v_desde)
      when 'foco_pergunta' then format('%s levam até %s o combinado (%s OS), e hoje uso %s: a troca espera a sua resposta.',
                                       public._agenda_maiuscula(v_nivel), v_calc, v_n, v_efet)
      when 'foco_travado' then format('%s levam até %s o combinado (%s OS); fico com %s até %s, como você decidiu.',
                                      public._agenda_maiuscula(v_nivel), v_calc, v_n, v_efet, v_trava)
      when 'acao' then format('Aprendi com as OS concluídas: %s levam até %s o combinado (%s OS). Passei a usar %s no lugar de %s para perguntar o que falta. *desfaz aprendizado* volta.',
                              v_nivel, v_calc, v_n, v_calc, v_efet)
      when 'pergunta' then format('Medi %s: levam até %s o combinado (%s OS), e hoje eu uso %s. É uma troca grande.',
                                  v_nivel, v_calc, v_n, v_efet)
      when 'opcao1' then format('Passo a usar %s', v_calc)
      when 'opcao2' then format('Fico com %s', v_efet)
      when 'opcao3' then 'Volto ao padrão'
      when 'desfeito' then format('Desfeito: %s voltam a %s para perguntar o que falta. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                  v_nivel, v_volta, v_dias)
      when 'fico' then format('Combinado: fico com %s. Volto a perguntar se o medido mudar muito.', v_efet)
    end;
  end if;

  -- Os outros itens: um texto provisório, sem jargão; o pacote de cada item (P2 a P6) recria esta função com o texto da §6.
  v_rotulo := case p_item
    when 'mo' then 'O valor de mão de obra por diária'
    when 'presenca' then 'A sua presença nas OS'
    when 'fornecedor_atraso' then 'O atraso do fornecedor'
    when 'fornecedor_prazo' then 'O prazo do fornecedor'
    when 'capacidade_dono' then 'A parte da sua semana no plano'
    when 'cliente_pontualidade' then 'A pontualidade com o cliente'
    when 'aviso_folga' then 'A folga do aviso de atraso'
    when 'carga' then 'A parte da semana de cada pessoa no plano'
    when 'solver' then 'Os sinais de um planejador mais forte'
    else 'O que eu medi' end;
  return case p_momento
    when 'foco_medindo' then format('%s: %s de %s medidas; vale %s (padrão).', v_rotulo, v_n, v_nmin, coalesce(v_padrao, 'o de hoje'))
    when 'foco_sombra' then format('Em teste: %s medido é %s (%s medidas); vale %s (padrão).',
                                   lower(left(v_rotulo, 1)) || substr(v_rotulo, 2), v_calc, v_n, coalesce(v_padrao, 'o de hoje'))
    when 'foco_em_uso' then format('%s: uso %s, pelo medido (%s medidas), desde %s.', v_rotulo, v_uso, v_n, v_desde)
    when 'foco_pergunta' then format('%s: o medido é %s (%s medidas), e hoje uso %s: a troca espera a sua resposta.',
                                     v_rotulo, v_calc, v_n, coalesce(v_efet, 'o padrão'))
    when 'foco_travado' then format('%s: o medido é %s (%s medidas); fico com %s até %s, como você decidiu.',
                                    v_rotulo, v_calc, v_n, coalesce(v_efet, 'o padrão'), v_trava)
    when 'acao' then format('Aprendi com o que aconteceu: %s passou a %s (era %s; %s medidas). *desfaz aprendizado* volta.',
                            lower(left(v_rotulo, 1)) || substr(v_rotulo, 2), v_calc, coalesce(v_efet, 'o padrão'), v_n)
    when 'pergunta' then format('Medi %s: %s (%s medidas), e hoje uso %s. É uma troca grande.',
                                lower(left(v_rotulo, 1)) || substr(v_rotulo, 2), v_calc, v_n, coalesce(v_efet, 'o padrão'))
    when 'opcao1' then format('Passo a usar %s', v_calc)
    when 'opcao2' then format('Fico com %s', coalesce(v_efet, 'o de agora'))
    when 'opcao3' then 'Volto ao padrão'
    when 'desfeito' then format('Desfeito: %s volta a %s. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                lower(left(v_rotulo, 1)) || substr(v_rotulo, 2), coalesce(v_volta, 'o padrão'), v_dias)
    when 'fico' then format('Combinado: fico com %s. Volto a perguntar se o medido mudar muito.', coalesce(v_efet, 'o padrão'))
  end;
end;
$function$;

comment on function public._agenda_aprendizado_texto(text, text, jsonb) is
  'Agenda de Produção (Fase 6): os textos do aprendizado ao dono, do banco — p_momento foco_<estado> (a linha do foco), acao (o que mudou sozinho), pergunta (a troca grande, sem as opções), opcao1/2/3, desfeito e fico. p_d: {chave, calculado, em_uso, efetivo (o que valia antes), padrao, volta, n, n_min, desde, travado_ate, trava_dias}. O fator tem os textos da spec-fase6 §6.2/§6.3; os outros itens, um texto provisório que o pacote de cada um recria (copiar DESTA definição). FASE 6 (P2): o R$ por diária (mo) e a presença do dono têm os textos da spec §6.2/§6.3 (a presença lê detalhe.k, as idas do dono).';

-- os_duracao_sugerida (de 20261024160400_agenda_fase1_prontidao.sql)
create or replace function public.os_duracao_sugerida(p_so_id uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_total  numeric;
  v_mat    numeric;
  v_horas  numeric;
  v_mo     numeric;
  v_dp_ot  numeric;
  v_dp_re  numeric;
  v_pes    int;
  v_d_ot   numeric;
  v_d_re   numeric;
  v_sug    numeric;
  -- FASE 6: o R$ por diária do realista e de onde ele vem
  v_mo_dia   numeric;
  v_mo_fonte text;
  -- FASE 6: fim
begin
  if not exists (select 1 from public.service_orders where id = p_so_id) then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;

  -- A mão de obra é o total das linhas de serviço menos o material de texto livre que ENTRA NA COMPRA (o mesmo
  -- predicado de compute_purchase_needs); as horas diretas são as linhas cobradas por hora.
  select coalesce(sum(s.line_total), 0),
         coalesce(sum(s.line_total) filter (
           where s.service_id is null and s.billing_unit_snapshot = 'unit' and coalesce(s.quantity, 0) > 0
             and public.free_text_is_material(s.name_snapshot)), 0),
         coalesce(sum(s.quantity) filter (where s.billing_unit_snapshot = 'hour'), 0)
    into v_total, v_mat, v_horas
    from public.service_order_services s
   where s.service_order_id = p_so_id;
  v_mo := greatest(v_total - v_mat, 0);

  if v_mo <= 0 and v_horas <= 0 then
    return jsonb_build_object('ok', true, 'sem_base', true, 'mo', v_mo, 'horas', v_horas,
                              'texto', 'sem base para estimar: quantos dias?');
  end if;

  -- Diárias-pessoa: o otimista pelo preço da diária, o realista pelo que a HBR fatura por diária de fato.
  v_dp_ot := greatest(v_horas / c.jornada_horas, v_mo / c.mo_por_diaria_preco);
  v_dp_re := greatest(v_horas / c.jornada_horas, v_mo / c.mo_por_diaria_real);
  -- FASE 6: o realista pelo R$ por diária aprendido (em uso, com modo_aprendizado ligado e mo na lista); senão o de hoje
  -- (mo_por_diaria_real): _agenda_mo_por_diaria_real()
  v_mo_dia := public._agenda_mo_por_diaria_real();
  v_mo_fonte := case when public._agenda_aprendido('mo', 'todas') is not null then 'aprendido' else 'padrao' end;
  v_dp_re := greatest(v_horas / c.jornada_horas, v_mo / v_mo_dia);
  -- FASE 6: fim
  v_pes := case when v_dp_re <= 1 then 1 else c.equipe_sugerida end;
  -- Dias de calendário arredondados ao meio dia; nunca menos de meio dia.
  v_d_ot := trim_scale(greatest(0.5, round(v_dp_ot / v_pes * 2) / 2));
  v_d_re := trim_scale(greatest(v_d_ot, round(v_dp_re / v_pes * 2) / 2));
  v_sug  := trim_scale(round(v_d_ot + v_d_re) / 2);

  -- FASE 6: com o R$ por diária aprendido em uso, a mesma saída mais mo_fonte = 'aprendido' e o valor usado (mo_por_diaria);
  -- com o padrão, a saída de antes, byte a byte (a os_prontidao e o motor a embutem: em teste nada pode mudar)
  if v_mo_fonte = 'aprendido' then
    return jsonb_build_object(
      'ok', true, 'sem_base', false, 'mo', v_mo, 'horas', trim_scale(v_horas),
      'dp_otimista', round(v_dp_ot, 2), 'dp_realista', round(v_dp_re, 2),
      'pessoas', v_pes, 'dias_otimista', v_d_ot, 'dias_realista', v_d_re, 'sugerida', v_sug,
      'diarias_otimista', trim_scale(v_d_ot * v_pes), 'diarias_realista', trim_scale(v_d_re * v_pes),
      'texto', public._agenda_faixa_dias(v_d_ot, v_d_re)
               || case when v_pes = 1 then ', 1 pessoa' else format(' com %s pessoas', v_pes) end
               || ' (estimativa minha, pelo valor)',
      'mo_fonte', 'aprendido', 'mo_por_diaria', v_mo_dia);
  end if;
  -- FASE 6: fim
  return jsonb_build_object(
    'ok', true, 'sem_base', false, 'mo', v_mo, 'horas', trim_scale(v_horas),
    'dp_otimista', round(v_dp_ot, 2), 'dp_realista', round(v_dp_re, 2),
    'pessoas', v_pes, 'dias_otimista', v_d_ot, 'dias_realista', v_d_re, 'sugerida', v_sug,
    'diarias_otimista', trim_scale(v_d_ot * v_pes), 'diarias_realista', trim_scale(v_d_re * v_pes),
    'texto', public._agenda_faixa_dias(v_d_ot, v_d_re)
             || case when v_pes = 1 then ', 1 pessoa' else format(' com %s pessoas', v_pes) end
             || ' (estimativa minha, pelo valor)');
end;
$function$;

comment on function public.os_duracao_sugerida(uuid) is
  'Agenda de Produção (Fase 1, P3): a duração "pelo valor" (plano §4.2 com a correção do material). mo = linhas de serviço − material de texto livre que entra na compra; horas = linhas por hora; diárias-pessoa otimista = max(horas ÷ jornada_horas, mo ÷ mo_por_diaria_preco), realista = max(horas ÷ jornada_horas, mo ÷ mo_por_diaria_real); 1 pessoa se o realista ≤ 1, senão equipe_sugerida; dias arredondados ao meio dia; sugerida = o meio dia mais perto da média. Sem mão de obra nem horas: {sem_base:true, texto:"sem base para estimar: quantos dias?"}. Nunca é gravada. FASE 6 (P2): o realista usa _agenda_mo_por_diaria_real() (o R$ por diária aprendido em uso, senão mo_por_diaria_real); com o aprendido em uso a saída ganha mo_fonte = aprendido e mo_por_diaria (sem ele, a saída de antes).';

-- os_presenca_do_dono (de 20261024160400_agenda_fase1_prontidao.sql)
create or replace function public.os_presenca_do_dono(p_so_id uuid)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with os as (
    select so.id, so.service_type, so.marina_id, pl.dono_presenca,
           -- FASE 6: a presença aprendida da classe (nula fora de ligado, sem nada aprendido e na OS com alocação publicada
           -- ou fixada: o publicado não muda)
           public._agenda_presenca_aprendida(so.id) as aprendida,
           -- FASE 6: fim
           public._agenda_normal(pr.name_snapshot) as principal
      from public.service_orders so
      left join public.os_planejamento pl on pl.service_order_id = so.id
      left join lateral (
        select s.name_snapshot from public.service_order_services s
         where s.service_order_id = so.id
         order by s.line_total desc nulls last, s.created_at, s.id limit 1) pr on true
     where so.id = p_so_id
  )
  select coalesce((
    select case
      when os.dono_presenca is not null then
        jsonb_build_object('presenca', os.dono_presenca, 'motivo', 'você disse', 'fonte', 'dono')
      when os.service_type = 'diagnosis' or os.principal ~ 'diagnost' then
        jsonb_build_object('presenca', 'sempre', 'motivo', 'diagnóstico', 'fonte', 'regra')
      when os.service_type = 'commissioning' or os.principal ~ '(comissionament|parametriz)' then
        jsonb_build_object('presenca', 'sempre', 'motivo', 'comissionamento', 'fonte', 'regra')
      when os.marina_id is not null and not exists (
             select 1 from public.service_orders o
              where o.marina_id = os.marina_id and o.id <> os.id and o.status in ('completed', 'invoiced')) then
        jsonb_build_object('presenca', 'sempre', 'motivo', 'marina nova', 'fonte', 'regra')
      -- FASE 6: depois do que o dono disse e da regra d05, antes do abre e fecha: o que a agenda aprendeu nas OS parecidas
      -- ("você foi a 3 de 4 OS de energia em motorhome")
      when os.aprendida is not null then os.aprendida - 'chave'
      -- FASE 6: fim
      else jsonb_build_object('presenca', 'abre_e_fecha', 'motivo', 'padrão', 'fonte', 'regra')
    end
      from os),
    jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.'));
$function$;

comment on function public.os_presenca_do_dono(uuid) is
  'Agenda de Produção (Fase 1, P3): a presença do dono na OS (d05). os_planejamento.dono_presenca, se ele disse (fonte dono); senão a regra: sempre em diagnóstico (service_type ou a linha de maior valor), comissionamento/parametrização e marina sem OS concluída/faturada antes; senão abre_e_fecha (não ocupa o turno dele). {presenca, motivo, fonte}. FASE 6 (P2): depois do que o dono disse e da regra, antes do abre_e_fecha, a presença aprendida da classe (_agenda_presenca_aprendida: só com modo_aprendizado ligado e presenca na lista, e só na OS sem alocação publicada ou fixada) — {presenca: sempre, motivo: "você foi a 3 de 4 OS de energia em motorhome", fonte: aprendida}. Continua SQL, STABLE e invoker.';

-- _agenda_vigia_estouro (de 20261025100300_agenda_fase2_conferencia_vigia.sql)
create or replace function public._agenda_vigia_estouro(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf  public.agenda_config := public._agenda_cfg();
  r   record;
  v_m jsonb;
  v_n int := 0;
  v_c numeric;
  v_t numeric;
  -- FASE 6: o limiar desta OS (o fator de campo)
  v_f numeric;
  -- FASE 6: fim
begin
  for r in select k.service_order_id as os from public.os_carteira(p_hoje) k
            where k.status = 'in_progress' order by k.numero collate "C", k.service_order_id loop
    v_m := public.agenda_meios_da_os(r.os, p_hoje);
    continue when v_m ->> 'fonte' not in ('dono', 'aceita') or (v_m ->> 'total') is null;
    v_c := coalesce((v_m ->> 'cumpridos')::numeric, 0);
    v_t := (v_m ->> 'total')::numeric;
    -- FASE 6: o limiar é o fator de campo da classe da OS (agenda_fator_de_campo: o aprendido em uso, senão estouro_fator);
    -- o limiar de antes (logo abaixo) só roda se o fator não vier
    v_f := coalesce((public.agenda_fator_de_campo(r.os, p_hoje) ->> 'fator')::numeric, cf.estouro_fator);
    continue when v_t <= 0 or v_c <= v_f * v_t;
    if v_f is null then
    -- FASE 6: fim
    continue when v_t <= 0 or v_c <= cf.estouro_fator * v_t;
    -- FASE 6: o limiar de antes não roda mais (fica para a conferência da cópia)
    end if;
    -- FASE 6: fim
    if public._agenda_vigia_perguntar('estouro', format('estouro:%s:%s', r.os, v_m ->> 'total'), r.os, null, null, null,
         format('%s já teve %s de serviço e o combinado era %s. O que falta?', public._agenda_rotulo_da_os(r.os),
                public._agenda_dias(round(v_c) / 2), public._agenda_dias(v_t / 2)),
         cf.modo_vigia, p_agora) then
      v_n := v_n + 1;
    end if;
  end loop;
  return jsonb_build_object('criadas', v_n);
end;
$function$;

comment on function public._agenda_vigia_estouro(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 11: em andamento com os dias ditos e os meios-dias feitos acima de estouro_fator × o combinado → pergunta estouro:<os>:<total> ("o que falta?"). FASE 6 (P2): o limiar é agenda_fator_de_campo(os, hoje).fator (o fator de campo aprendido em uso da classe da OS, senão estouro_fator); a chave e o texto da pergunta não mudam.';

-- ── 9. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- As leituras (invoker: a RLS de quem lê vale; nada que o login não leia) para authenticated e service_role, nunca anon. Elas
-- são lidas de dentro de funções invoker que o painel e o motor chamam (os_presenca_do_dono, os_duracao_sugerida, a vigia),
-- por isso _agenda_classe_de_campo (do P1, que nascera sem grant) passa a ler também.
revoke all on function public.agenda_fator_de_campo(uuid, date), public._agenda_mo_por_diaria_real(),
  public._agenda_presenca_aprendida(uuid), public._agenda_classe_de_campo(uuid)
  from public, anon;
grant execute on function public.agenda_fator_de_campo(uuid, date), public._agenda_mo_por_diaria_real(),
  public._agenda_presenca_aprendida(uuid), public._agenda_classe_de_campo(uuid)
  to authenticated, service_role;

-- Os passos da rodada: sem grant a ninguém, nem service_role (quem chama é a rodada do P6, agenda_aprender, definer).
revoke all on function public._agenda_aprender_fator(date, timestamptz), public._agenda_aprender_mo(date, timestamptz),
  public._agenda_aprender_presenca(date, timestamptz)
  from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas de antes (create or replace não as muda; repetidas aqui para a migration valer sozinha).
revoke all on function public.os_duracao_sugerida(uuid), public.os_presenca_do_dono(uuid), public._agenda_aprendizado_texto(text, text, jsonb)
  from public, anon;
grant execute on function public.os_duracao_sugerida(uuid), public.os_presenca_do_dono(uuid), public._agenda_aprendizado_texto(text, text, jsonb)
  to authenticated, service_role;
revoke all on function public._agenda_vigia_estouro(date, timestamptz) from public, anon, authenticated, service_role;

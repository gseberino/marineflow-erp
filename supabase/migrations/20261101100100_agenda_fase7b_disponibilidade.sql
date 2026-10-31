-- Agenda de Produção, Fase 7, etapa 7b ("os dias de verdade de quem trabalha e a dupla pela tarefa"), pacote P2: a disponibilidade —
-- a semana dita (presa, uma linha por dia), o padrão (só de quem já tem ou do dono), a chance de falta (só medida), o rascunho com as
-- datas de quem vem sob demanda ("Mateus vem qua e qui": a 1ª semana com todos os dias por vir) e a pessoa do cadastro, a semana pelo
-- rascunho, a dupla dita pelo planejar (nao/todos/inicio/fim) e a capacidade semanal com o dono pela metade.
-- Spec: scratchpad agenda-pesquisa/spec-fase7b.md (§R4.7 P2, §R4.2(c), §R4.3(b), §R4.5, §R4.6, §5.1, §6.3, §6.5, §6.6, §8.3
-- agenda_fase7b_disponibilidade.sql); nomes: fase7-registro.md §1 (7b P2); respostas do dono: fase7-padroes.md (AG7-02 o dono em
-- campo, meia capacidade; AG7-03 a equipe: Alex, o dono e quem vem sob demanda — Mateus e Vinicius —, só nas datas que o dono diz;
-- AG7-04 uma pessoa, dupla só quando precisa).
-- Depende das Fases 1 a 6, do lote de 30/10 (20261030100000 .. 100600, em produção), da 7a inteira (20261031100000 .. 100985 e o
-- dado 20261031100990) e do 7b P1 (20261101100000: modo_dias, modo_dupla, dono_carga_max, agenda_disponibilidade.semana_dita /
-- mensagem_id / pergunta_id, a situação so_pontas).
--
-- ═══ DDL — OK NOMEADO ═══ (6 funções novas e 8 recriadas, uma delas com a assinatura nova — agenda_rascunho_disponibilidade ganha
-- p_semana no fim: drop da de 8 argumentos e create da de 9, as portas de antes; nenhuma tabela, nenhuma coluna, nenhum dado)
-- NÃO APLICADA. Existe para revisão e espera o OK do dono. Este arquivo foi MONTADO por
-- scratchpad/agenda-pesquisa/f7b/p2/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (conferida a cada montagem: o
-- montador para se outra migration a definir depois da origem), e as mudanças estão só nos blocos "-- FASE 7b: … -- FASE 7b: fim"
-- (só acréscimo: nenhuma linha de antes muda; tirados os blocos, o corpo é o da origem, byte a byte).
--
-- POR QUE: a capacidade passa a ser o que cada um diz que pode. A pergunta da semana (P3) grava a semana presa e o padrão por aqui
-- (_agenda_equipe_dias_gravar); o dono diz os dias de alguém para uma semana (p_semana) ou as datas de quem ele chama quando precisa
-- ("Mateus vem qua e qui", que hoje grava só a quarta, calado); a dupla numa parte do serviço vira fala do dono; e o dono em campo
-- conta meia capacidade (AG7-02, confirmado no fio em 29/10) — com a linha dele, a capacidade semanal dobrava (você 5 + Alex 5).
--
-- O QUE MUDA:
--   1. Novas (todas STABLE/IMMUTABLE e invoker, menos o gravador): _agenda_dias_curtos ("seg, ter e qui", "de seg a sex", "… e sáb de
--      manhã", "nenhum dia"); _agenda_semana_perguntada (a semana que a quinta pergunta: a seguinte à próxima, o prazo e até quando
--      ainda pode sair); _agenda_dias_declarados (o que vale para uma pessoa numa semana: a semana presa, o padrão dito, a semente ou
--      nada); _agenda_chance_de_falta (dias ditos × faltas nas últimas falta_semanas; só medida, nunca desconta capacidade);
--      _agenda_semana_dita ("semana que vem", "semana de 16/11", "a outra semana" → a segunda; semana passada = recusa) e
--      _agenda_equipe_dias_gravar (VOLATILE, security definer, sem grant a ninguém: o ÚNICO que escreve semana_dita — uma linha por
--      dia útil da semana, a exceção do dono no dia vence a resposta do diarista, o sábado só de manhã; o padrão só muda para quem já
--      tem padrão ou é o dono, R4.2(c)(4); gravar de novo o mesmo = nada muda).
--   2. agenda_capacidade: o dia "só abre e fecha" (so_pontas, que só a semana dita do dono grava) vira sem_padrao, 0 de campo, "você
--      disse que nesse dia só abre e fecha" — depois do feriado e antes do padrão "não vem"; as pontas de abrir e fechar continuam
--      livres (agenda_grade). Sem linha so_pontas, a saída de antes, byte a byte.
--   3. agenda_capacidade_semanal (R4.5): com modo_dias fora de desligado, as diárias do dono entram multiplicadas por dono_carga_max
--      (seg–sex: 5 × 0,50 = 2,5) e o comprometível dele é esse mesmo número (o teto dele já é dono_carga_max); os técnicos como
--      antes (× carga_max). Com o Alex e a linha do dono: 7,5 diárias e 6,5 comprometíveis (não 10 e 8). Desligado, ou sem a linha
--      do dono, byte a byte.
--   4. agenda_rascunho_disponibilidade (drop da assinatura de 8 argumentos; create com p_semana text default null no fim — o
--      ai-agent antigo chama por nome com 8 e continua casando), com modo_dias fora de desligado:
--      · p_semana ("semana que vem", "semana de 16/11"): os dias da semana dita (vem + os dias; nao_vem + "a semana toda" = nenhum),
--        sem turno, nunca padrão; chave disp:<pessoa>:s<segunda>; a releitura "Roberto, semana de 16/11: vem seg, ter e qui (e não
--        vem qua e sex)." / "Você, semana de 16/11: fica em campo seg e qua; nos outros dias, só abre e fecha.";
--      · sem p_padrao e sem p_semana, "vem" com 2 ou mais dias da semana que não são uma faixa ("qua e qui"): as DATAS desses dias na
--        1ª semana (seg a sáb) em que todos ainda estão por vir, estritamente depois de hoje; só dia útil (o feriado é recusado com o
--        nome dele); sábado só com sabado_manha ≠ nunca e só de manhã; chave disp:<pessoa>:l<d1>_<d2>…:dia; a releitura "Mateus:
--        vem qua 11/11 e qui 12/11 (só nesses dias)." "qua a sex" continua faixa;
--      · a pessoa do cadastro: com o resolvedor em nao_achei e "vem", procura entre os payees ATIVOS prestador, diarista ou
--        funcionário (nunca o sócio; fornecedor não é payee) pela régua do nome do resolvedor; achou um → segue, e a releitura ganha
--        "Mateus ainda não está na equipe da agenda: com *grava*, ele entra só nesses dias"; nenhum → "Não achei Vinicius no
--        cadastro de pessoas. Cadastre ele (o nome e o telefone) e me diga de novo."; vários → "Qual Mateus: …?".
--      Com modo_dias desligado, o de antes byte a byte ("qua e qui" grava só a quarta, como em produção hoje), e p_semana é recusado
--      com uma frase.
--   5. _agenda_aplicar_disponibilidade (o *grava*): a semana → _agenda_equipe_dias_gravar (origem dono) e a pergunta dias_semana
--      aberta dessa pessoa e semana fecha ("você disse os dias"); as datas → uma exceção [d, d] por data, disponível, origem dono, o
--      turno dito (o sábado só de manhã), "Você disse que vem (sob demanda)", nunca padrão; e toda exceção por data dita pelo dono
--      troca também a linha da semana presa da pessoa no mesmo dia (do dia inteiro, ou do mesmo turno): a palavra do dono é a mais
--      nova.
--   6. agenda_rascunho_gravar (A4 = NOVO-agenda-55): com modo_dias fora de desligado, o padrão "vem" novo do dono troca também o
--      padrão que a pessoa (diarista) ou o assistente (agente) disse para os mesmos dias. Desligado, o de antes.
--   7. agenda_rascunho_planejar / _agenda_aplicar_planejar / _agenda_rascunho_frase: a chave dupla (nao | todos | inicio | fim, com
--      dupla_meios 1..20 em inicio/fim, conferido no trecho; "no primeiro dia" = 2 meios-dias com "dia" no trecho); o *grava* escreve
--      os_planejamento.dupla_dita, dupla_meios, dupla_motivo e dupla_em ("nao" = 1 pessoa, sem a inferência). Com modo_dupla
--      desligado, inicio/fim é recusado ("A dupla só numa parte do serviço ainda não está ligada. Diga *Lenine com dupla* (o tempo
--      todo) ou 'vai com um só'."); todos e nao valem em todo modo (como a palavra da 7a). Com menos técnicos na grade do que a dupla
--      pede, a releitura avisa: "Hoje só Alex está na equipe: até você chamar alguém e me dizer os dias, eu não marco Lenine."
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7b_disponibilidade.sql; registradas em notas-fase77b.md, P2):
--   · A4 atrás do modo_dias (a §5.1 não tinha portão): com os modos desligados o rascunho é o de antes (R4.2(c), R4.9-8).
--   · As datas de quem vem sob demanda só para "vem" (o turno dito é nulo; o sábado vai de manhã); "não vem qua e qui" continua o
--     caminho de antes.
--   · A semana pelo rascunho com "não vem" só para a semana inteira ("não vem a semana toda" = nenhum dia); "não vem quarta na
--     semana que vem" é recusado com a frase da data (um dia só é por data).
--   · A releitura da semana usa o rótulo "Roberto, semana de 16/11" (o grupo é a pessoa e a semana): a linha sai como na §6.6.
--   · A pessoa do cadastro vale também para o padrão e a data única com "vem" (a releitura diz "com esses dias, toda semana" / "só
--     nesse dia").
--   · A exceção por data troca a linha da semana presa do dia inteiro (turno nulo) ou do mesmo turno; a exceção de um turno só ("só
--     de manhã") não troca a linha do dia inteiro (a capacidade já põe o "não vem neste turno" por cima).
--
-- O QUE NÃO MUDA: com modo_dias e modo_dupla desligados (a linha nasce assim), nenhuma saída muda, também a do rascunho; nenhuma
-- mensagem, cron, tela ou função de borda; o motor, a vigia, a rotina e as leituras (fora agenda_capacidade com so_pontas e a
-- capacidade semanal com o dono pela metade, que só existem com os modos fora de desligado). Ninguém grava semana_dita fora de
-- _agenda_equipe_dias_gravar.
--
-- ORDEM DE LIGAR (spec §10): depois de 20261101100000 (P1), que cria as colunas e a situação so_pontas; antes de 20261101100200
-- (P3), que chama _agenda_equipe_dias_gravar, _agenda_dias_declarados, _agenda_semana_perguntada e _agenda_dias_curtos. Aplicar
-- sozinha não muda nada para ninguém (os modos ficam 'desligado' na linha).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7b_disponibilidade.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261101100100
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261101100100_agenda_fase7b_disponibilidade.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261101100100', 'agenda_fase7b_disponibilidade');"
--
-- DESFAZER: recriar as 8 funções com o corpo e o comentário da origem de cada uma (abaixo: agenda_capacidade e
-- agenda_capacidade_semanal de 20261030100600; agenda_rascunho_disponibilidade e _agenda_aplicar_disponibilidade de 20261024160600;
-- agenda_rascunho_gravar de 20261031100800; agenda_rascunho_planejar, _agenda_aplicar_planejar e _agenda_rascunho_frase de
-- 20261028100500) — para agenda_rascunho_disponibilidade, drop da de 9 argumentos antes e as portas da de 8 depois — e
--   drop function if exists public._agenda_equipe_dias_gravar(uuid, date, smallint[], boolean, text, text, timestamptz, uuid, uuid, uuid),
--     public._agenda_semana_dita(text, text, date), public._agenda_chance_de_falta(uuid, date),
--     public._agenda_dias_declarados(uuid, date), public._agenda_semana_perguntada(date), public._agenda_dias_curtos(smallint[], boolean);
--   (só sem o P3 em diante, que os chama). As linhas semana_dita e so_pontas que já existirem ficam (a capacidade de antes as lê
--   como exceção: so_pontas não casa nenhuma situação dela e cai no padrão).
--
-- IDEMPOTENTE: drop function if exists (a assinatura de 8 argumentos), create or replace function, revoke/grant e comment.
-- Quem recriar depois copia DESTA migration (spec §R4.6, fim): agenda_capacidade, agenda_capacidade_semanal,
-- agenda_rascunho_disponibilidade, _agenda_aplicar_disponibilidade, agenda_rascunho_gravar, agenda_rascunho_planejar,
-- _agenda_aplicar_planejar e _agenda_rascunho_frase.

-- ── 1. Os dias em texto curto ───────────────────────────────────────────────────────────────────────────────────
-- {1,2,4} → "seg, ter e qui"; três ou mais seguidos → "de seg a sex" ({1,2,3,5} → "de seg a qua e sex"); com o sábado (p_sabado ou o
-- 6 na lista) → "… e sáb de manhã"; vazio sem sábado → "nenhum dia". Os nomes pela _agenda_lista.
create or replace function public._agenda_dias_curtos(p_dias smallint[], p_sabado boolean default false)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  curto   constant text[] := array['seg', 'ter', 'qua', 'qui', 'sex'];
  v       int[] := array(select distinct x::int from unnest(coalesce(p_dias, '{}'::smallint[])) x
                          where x between 1 and 5 order by 1);
  v_sab   boolean := coalesce(p_sabado, false) or 6 = any (coalesce(p_dias, '{}'::smallint[]));
  v_itens text[] := '{}';
  n       int;
  i       int := 1;
  v_ini   int;
  v_fim   int;
  k       int;
begin
  n := cardinality(v);
  while i <= n loop
    v_ini := v[i];
    v_fim := v[i];
    while i < n and v[i + 1] = v_fim + 1 loop
      i := i + 1;
      v_fim := v[i];
    end loop;
    if v_fim - v_ini >= 2 then
      v_itens := v_itens || format('de %s a %s', curto[v_ini], curto[v_fim]);
    else
      for k in v_ini .. v_fim loop
        v_itens := v_itens || curto[k];
      end loop;
    end if;
    i := i + 1;
  end loop;
  if v_sab then
    v_itens := v_itens || 'sáb de manhã'::text;
  end if;
  if cardinality(v_itens) = 0 then
    return 'nenhum dia';
  end if;
  return public._agenda_lista(v_itens, null);
end;
$function$;

comment on function public._agenda_dias_curtos(smallint[], boolean) is
  'Agenda de Produção (Fase 7b, P2): os dias da semana em texto curto, sem jargão — "seg, ter e qui"; três ou mais seguidos "de seg a sex" ({1,2,3,5} = "de seg a qua e sex"); com o sábado (p_sabado, ou o 6 na lista) "… e sáb de manhã" (só sábado: "sáb de manhã"); vazio sem sábado "nenhum dia". Só 1 a 5 contam como dia de semana. IMMUTABLE.';

-- ── 2. A semana que a quinta pergunta ──────────────────────────────────────────────────────────────────────────
-- quinta = o dia_do_plano mais recente ≤ p_hoje; seg = a segunda da semana dele + 7 × equipe_dias_semanas_a_frente (a seguinte à
-- próxima: a da quinta que vem planeja); prazo_dia = o dia_do_plano da semana anterior a seg (a quinta que planeja seg); prazo_em =
-- esse dia, hora_do_plano − equipe_dias_fechar_antes, em Brasília; pode_perguntar_ate = quinta + equipe_dias_tentar_dias.
create or replace function public._agenda_semana_perguntada(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_quinta date;
  v_seg    date;
  v_prazo  date;
begin
  if p_hoje is null then
    raise exception '_agenda_semana_perguntada: sem o dia de hoje' using errcode = '22004';
  end if;
  v_quinta := p_hoje - ((extract(isodow from p_hoje)::int - c.dia_do_plano + 7) % 7);
  v_seg := v_quinta - (extract(isodow from v_quinta)::int - 1) + 7 * c.equipe_dias_semanas_a_frente;
  v_prazo := v_seg - 7 + (c.dia_do_plano - 1);
  return jsonb_build_object(
    'quinta', v_quinta,
    'seg', v_seg,
    'prazo_dia', v_prazo,
    'prazo_em', ((v_prazo + c.hora_do_plano) - c.equipe_dias_fechar_antes) at time zone 'America/Sao_Paulo',
    'pode_perguntar_ate', v_quinta + c.equipe_dias_tentar_dias);
end;
$function$;

comment on function public._agenda_semana_perguntada(date) is
  'Agenda de Produção (Fase 7b, P2): a semana que a pergunta da quinta pede — {quinta (o dia_do_plano mais recente até hoje), seg (a segunda da semana seguinte à próxima: 7 × equipe_dias_semanas_a_frente), prazo_dia (a quinta que planeja seg), prazo_em (prazo_dia, hora_do_plano − equipe_dias_fechar_antes, Brasília), pode_perguntar_ate (quinta + equipe_dias_tentar_dias)}. Com hoje = qui 05/11: {05/11, 16/11, qui 12/11, 12/11 16:00, ter 10/11}. STABLE.';

-- ── 3. O que vale para uma pessoa numa semana ──────────────────────────────────────────────────────────────────
-- (1) a semana presa (linhas vivas com semana_dita = p_seg) → fonte semana; (2) o padrão dito (vivo, disponível/confirmado, origem
-- que não é o histórico; os dias de um padrão "não vem" do dia inteiro saem) → padrao; (3) a semente (histórico com a frequência
-- mínima) → historico; (4) nada → nenhum.
create or replace function public._agenda_dias_declarados(p_payee uuid, p_seg date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_dias   smallint[];
  v_sab    boolean := false;
  v_pontas smallint[] := '{}';
  v_origem text;
  v_em     timestamptz;
  v_fonte  text;
  v_n      int;
begin
  if p_payee is null or p_seg is null then
    raise exception '_agenda_dias_declarados: sem a pessoa ou a semana' using errcode = '22004';
  end if;
  if extract(isodow from p_seg)::int <> 1 then
    raise exception '_agenda_dias_declarados: % não é segunda-feira', p_seg using errcode = '22023';
  end if;

  -- (1) a semana presa
  select count(*), max(d.criado_em), (array_agg(d.origem order by d.criado_em desc, d.id desc))[1]
    into v_n, v_em, v_origem
    from public.agenda_disponibilidade d
   where d.payee_id = p_payee and d.substituida_em is null and d.semana_dita = p_seg;
  if v_n > 0 then
    v_fonte := 'semana';
    v_dias := array(select distinct extract(isodow from lower(d.periodo))::smallint
                      from public.agenda_disponibilidade d
                     where d.payee_id = p_payee and d.substituida_em is null and d.semana_dita = p_seg
                       and d.situacao in ('disponivel', 'confirmada') and extract(isodow from lower(d.periodo)) between 1 and 5
                     order by 1);
    v_sab := exists (select 1 from public.agenda_disponibilidade d
                      where d.payee_id = p_payee and d.substituida_em is null and d.semana_dita = p_seg
                        and d.situacao in ('disponivel', 'confirmada') and extract(isodow from lower(d.periodo)) = 6);
    v_pontas := array(select distinct extract(isodow from lower(d.periodo))::smallint
                        from public.agenda_disponibilidade d
                       where d.payee_id = p_payee and d.substituida_em is null and d.semana_dita = p_seg
                         and d.situacao = 'so_pontas'
                       order by 1);
  else
    -- (2) o padrão dito (do dono, da própria pessoa ou do assistente)
    select count(*), max(d.criado_em), (array_agg(d.origem order by d.criado_em desc, d.id desc))[1]
      into v_n, v_em, v_origem
      from public.agenda_disponibilidade d
     where d.payee_id = p_payee and d.substituida_em is null and d.dias_semana is not null
       and d.situacao in ('disponivel', 'confirmada') and d.origem <> 'historico';
    if v_n > 0 then
      v_fonte := 'padrao';
      v_dias := array(select distinct x
                        from public.agenda_disponibilidade d, unnest(d.dias_semana) x
                       where d.payee_id = p_payee and d.substituida_em is null and d.dias_semana is not null
                         and d.situacao in ('disponivel', 'confirmada') and d.origem <> 'historico'
                         and not exists (select 1 from public.agenda_disponibilidade i
                                          where i.payee_id = p_payee and i.substituida_em is null and i.dias_semana @> array[x]
                                            and i.situacao = 'indisponivel' and i.turno is null)
                       order by 1);
    else
      -- (3) a semente do histórico
      select count(*), max(d.criado_em)
        into v_n, v_em
        from public.agenda_disponibilidade d
       where d.payee_id = p_payee and d.substituida_em is null and d.dias_semana is not null
         and d.situacao in ('disponivel', 'confirmada') and d.origem = 'historico'
         and coalesce(d.frequencia, 0) >= c.frequencia_minima;
      if v_n > 0 then
        v_fonte := 'historico';
        v_origem := 'historico';
        v_dias := array(select distinct x
                          from public.agenda_disponibilidade d, unnest(d.dias_semana) x
                         where d.payee_id = p_payee and d.substituida_em is null and d.dias_semana is not null
                           and d.situacao in ('disponivel', 'confirmada') and d.origem = 'historico'
                           and coalesce(d.frequencia, 0) >= c.frequencia_minima
                         order by 1);
      else
        v_fonte := 'nenhum';
        v_origem := null;
        v_em := null;
        v_dias := '{}';
      end if;
    end if;
    v_sab := 6 = any (v_dias);
    v_dias := array_remove(v_dias, 6::smallint);
  end if;

  return jsonb_build_object('dias', to_jsonb(coalesce(v_dias, '{}'::smallint[])), 'sabado', v_sab, 'so_pontas', to_jsonb(v_pontas),
                            'fonte', v_fonte, 'origem', v_origem, 'dito_em', v_em,
                            'texto', public._agenda_dias_curtos(v_dias, v_sab));
end;
$function$;

comment on function public._agenda_dias_declarados(uuid, date) is
  'Agenda de Produção (Fase 7b, P2): o que vale para a pessoa na semana de p_seg (uma segunda), nesta ordem — (1) a semana presa (agenda_disponibilidade viva com semana_dita = p_seg): fonte semana, os dias disponíveis de seg a sex, o sábado de manhã, os dias so_pontas do dono; (2) o padrão dito (vivo, disponível ou confirmado, origem dono, diarista ou agente; tirados os dias de um padrão "não vem" do dia inteiro): fonte padrao; (3) a semente do histórico com frequência ≥ frequencia_minima: fonte historico; (4) fonte nenhum. {dias, sabado, so_pontas, fonte, origem, dito_em, texto (_agenda_dias_curtos)}. STABLE, invoker.';

-- ── 4. O gravador da semana presa e do padrão (o único que escreve semana_dita) ──────────────────────────────────
create or replace function public._agenda_equipe_dias_gravar(p_payee uuid, p_seg date, p_dias smallint[], p_sabado boolean,
                                                             p_origem text, p_trecho text, p_agora timestamptz,
                                                             p_mensagem uuid default null, p_pergunta uuid default null,
                                                             p_autor uuid default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_eh_dono  boolean;
  v_hoje     date;
  v_dias     smallint[];
  v_sab      boolean := coalesce(p_sabado, false);
  v_nome     text;
  v_semana   text;
  v_trecho   text := public._agenda_corta(nullif(btrim(coalesce(p_trecho, '')), ''), 300);
  v_d        date;
  v_sit      text;
  v_turno    text;
  v_nota     text;
  v_dono_sit text;
  v_quer     jsonb := '[]'::jsonb;
  v_tem      jsonb;
  v_conf     jsonb := '[]'::jsonb;
  v_linhas   jsonb := '[]'::jsonb;
  v_x        jsonb;
  v_id       uuid;
  v_tem_pad  boolean;
  v_hist     boolean;
  v_atual    smallint[];
  v_pad      boolean;
  v_txt      text;
  v_fora     smallint[];
begin
  -- 1. as entradas e quem é
  if p_payee is null or p_seg is null or p_agora is null then
    raise exception '_agenda_equipe_dias_gravar: sem a pessoa, a semana ou a hora' using errcode = '22004';
  end if;
  if p_origem is null or p_origem not in ('diarista', 'dono', 'agente') then
    raise exception '_agenda_equipe_dias_gravar: origem "%" inválida (diarista, dono ou agente)', p_origem using errcode = '22023';
  end if;
  if extract(isodow from p_seg)::int <> 1 then
    raise exception '_agenda_equipe_dias_gravar: a semana começa na segunda (veio %)', p_seg using errcode = '22023';
  end if;
  v_dias := array(select distinct x from unnest(coalesce(p_dias, '{}'::smallint[])) x order by 1);
  if not (v_dias <@ array[1, 2, 3, 4, 5]::smallint[]) then
    raise exception '_agenda_equipe_dias_gravar: os dias vão de 1 (seg) a 5 (sex); o sábado é p_sabado (veio %)', p_dias
      using errcode = '22023';
  end if;
  select public._agenda_nome_curto(py.name) into v_nome from public.payees py where py.id = p_payee;
  if not found then
    raise exception '_agenda_equipe_dias_gravar: a pessoa % não está no cadastro', p_payee using errcode = 'P0001';
  end if;
  v_eh_dono := p_payee is not distinct from public._agenda_dono(null);
  v_hoje := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_semana := to_char(p_seg, 'DD/MM');

  -- 2 e 3. o que a semana deve ter, dia a dia (de hoje em diante; de seg a sex só dia útil; o sábado só de manhã, nunca
  -- "não vem"); a exceção do dono no dia vence a resposta do diarista (pula e volta em conflitos)
  for v_d in select g::date from generate_series(p_seg, p_seg + 5, interval '1 day') g loop
    continue when v_d < v_hoje;
    if extract(isodow from v_d)::int = 6 then
      continue when public.agenda_feriado(v_d) is not null
                 or exists (select 1 from public.agenda_disponibilidade r
                             where r.payee_id is null and r.situacao = 'indisponivel' and r.turno is null
                               and r.substituida_em is null and r.periodo @> v_d);
      v_sit := case when v_sab then 'disponivel' end;
      v_turno := 'manha';
    else
      continue when not public.agenda_dia_util(v_d);
      v_sit := case when extract(isodow from v_d)::smallint = any (v_dias) then 'disponivel'
                    when v_eh_dono then 'so_pontas' else 'indisponivel' end;
      v_turno := null;
    end if;
    if p_origem = 'diarista' then
      select d.situacao into v_dono_sit
        from public.agenda_disponibilidade d
       where d.payee_id = p_payee and d.substituida_em is null and d.origem = 'dono' and d.periodo @> v_d
       order by d.criado_em desc, d.id desc limit 1;
      if found then
        v_conf := v_conf || jsonb_build_array(jsonb_build_object('dia', v_d, 'situacao_do_dono', v_dono_sit));
        continue;
      end if;
    end if;
    v_quer := v_quer || jsonb_build_array(jsonb_build_object('dia', v_d, 'situacao', v_sit, 'turno', v_turno));
  end loop;

  -- 4. o padrão: só com dias, só para quem já tem padrão ou é o dono (quem vem sob demanda só prende a semana, R4.2(c)(4)), e só
  -- quando é outro (a semente do histórico sempre sai: a 1ª declaração a substitui)
  v_tem_pad := exists (select 1 from public.agenda_disponibilidade d
                        where d.payee_id = p_payee and d.substituida_em is null and d.dias_semana is not null
                          and d.situacao in ('disponivel', 'confirmada'));
  v_hist := exists (select 1 from public.agenda_disponibilidade d
                     where d.payee_id = p_payee and d.substituida_em is null and d.dias_semana is not null
                       and d.situacao in ('disponivel', 'confirmada') and d.origem = 'historico');
  v_atual := nullif(array(select distinct x
                            from public.agenda_disponibilidade d, unnest(d.dias_semana) x
                           where d.payee_id = p_payee and d.substituida_em is null and d.dias_semana is not null
                             and d.situacao in ('disponivel', 'confirmada') and d.origem <> 'historico'
                           order by 1), '{}'::smallint[]);
  v_pad := cardinality(v_dias) > 0 and (v_tem_pad or v_eh_dono) and (v_hist or v_atual is distinct from v_dias);

  -- 5. o mesmo já gravado (as linhas vivas da semana iguais, nos dias de agora) e o padrão igual = nada muda
  select coalesce(jsonb_agg(jsonb_build_object('dia', lower(d.periodo), 'situacao', d.situacao, 'turno', d.turno)
                            order by lower(d.periodo), d.turno), '[]'::jsonb)
    into v_tem
    from public.agenda_disponibilidade d
   where d.payee_id = p_payee and d.substituida_em is null and d.semana_dita = p_seg and d.origem = p_origem
     and lower(d.periodo) in (select (e ->> 'dia')::date from jsonb_array_elements(v_quer) e);
  if not v_pad
     and v_tem = coalesce((select jsonb_agg(e order by (e ->> 'dia')::date, e ->> 'turno') from jsonb_array_elements(v_quer) e
                            where e ->> 'situacao' is not null), '[]'::jsonb)
     and not exists (select 1 from public.agenda_disponibilidade d
                      where d.payee_id = p_payee and d.substituida_em is null and d.semana_dita = p_seg
                        and d.origem <> p_origem
                        and lower(d.periodo) in (select (e ->> 'dia')::date from jsonb_array_elements(v_quer) e)) then
    return jsonb_build_object('mudou', false, 'linhas', '[]'::jsonb, 'conflitos', v_conf, 'padrao_mudou', false,
                              'semente_saiu', false, 'semana', p_seg, 'dias', to_jsonb(v_dias), 'sabado', v_sab,
                              'texto', 'Já estava anotado assim.');
  end if;

  -- 2. troca e grava a semana (uma linha por dia)
  for v_x in select e from jsonb_array_elements(v_quer) e loop
    v_d := (v_x ->> 'dia')::date;
    update public.agenda_disponibilidade
       set substituida_em = p_agora
     where payee_id = p_payee and substituida_em is null and semana_dita = p_seg and periodo @> v_d;
    continue when v_x ->> 'situacao' is null;
    v_nota := case
      when p_origem = 'dono' and v_eh_dono then
        case v_x ->> 'situacao' when 'disponivel' then format('Você disse que fica em campo (semana de %s)', v_semana)
                                else format('Você disse que só abre e fecha (semana de %s)', v_semana) end
      when p_origem = 'dono' then
        case v_x ->> 'situacao' when 'disponivel' then format('Você disse que vem (semana de %s)', v_semana)
                                else format('Você disse que não vem (semana de %s)', v_semana) end
      when p_origem = 'agente' then
        case v_x ->> 'situacao' when 'disponivel' then format('Anotado que pode (semana de %s)', v_semana)
                                else format('Anotado que não pode (semana de %s)', v_semana) end
      else
        case v_x ->> 'situacao' when 'disponivel' then format('Disse que pode (semana de %s)', v_semana)
                                else format('Disse que não pode (semana de %s)', v_semana) end end;
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, trecho, semana_dita, mensagem_id,
                                               pergunta_id, criado_em, criado_por)
    values (p_payee, daterange(v_d, v_d, '[]'), v_x ->> 'turno', v_x ->> 'situacao', p_origem, v_nota, v_trecho, p_seg, p_mensagem,
            p_pergunta, p_agora, p_autor)
    returning id into v_id;
    v_linhas := v_linhas || jsonb_build_array(jsonb_build_object('id', v_id, 'dia', v_d, 'situacao', v_x ->> 'situacao',
                                                                 'turno', v_x ->> 'turno'));
  end loop;

  -- 4. o padrão novo troca TODOS os padrões "vem" vivos da pessoa (qualquer origem); o padrão "não vem" de um turno fica
  if v_pad then
    update public.agenda_disponibilidade
       set substituida_em = p_agora
     where payee_id = p_payee and substituida_em is null and dias_semana is not null and situacao in ('disponivel', 'confirmada');
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho, mensagem_id, pergunta_id,
                                               criado_em, criado_por)
    values (p_payee, v_dias, null, 'disponivel', p_origem,
            case when p_origem = 'dono' then format('você disse em %s', to_char(v_hoje, 'DD/MM'))
                 else format('Disse em %s', to_char(v_hoje, 'DD/MM')) end,
            v_trecho, p_mensagem, p_pergunta, p_agora, p_autor);
  end if;

  -- 6. o texto (o dono: §6.3; a pessoa: §6.1; o dono sobre outra pessoa: a mesma forma)
  v_fora := array(select x::smallint from generate_series(1, 5) x
                   where not (x::smallint = any (v_dias))
                     and exists (select 1 from jsonb_array_elements(v_quer) e
                                  where extract(isodow from (e ->> 'dia')::date)::int = x));
  v_txt := case
    when v_eh_dono and p_origem = 'dono' then
      case when cardinality(v_dias) = 0 and not v_sab then format('Anotei: na semana de %s você só abre e fecha.', v_semana)
           when cardinality(v_fora) = 0 then format('Anotei: na semana de %s você fica em campo %s.', v_semana,
                                                    public._agenda_dias_curtos(v_dias, v_sab))
           else format('Anotei: na semana de %s você fica em campo %s; nos outros dias, só abre e fecha.', v_semana,
                       public._agenda_dias_curtos(v_dias, v_sab)) end
    when p_origem = 'dono' then
      case when cardinality(v_dias) = 0 and not v_sab then format('Anotei: na semana de %s %s não vem.', v_semana, v_nome)
           else format('Anotei: na semana de %s %s vem %s.', v_semana, v_nome, public._agenda_dias_curtos(v_dias, v_sab)) end
    else
      case when cardinality(v_dias) = 0 and not v_sab then format('Anotei: na semana de %s você não pode. Obrigado por avisar!', v_semana)
           else format('Anotei: na semana de %s você pode %s. Obrigado!', v_semana, public._agenda_dias_curtos(v_dias, v_sab)) end end;

  return jsonb_build_object('mudou', true, 'linhas', v_linhas, 'conflitos', v_conf, 'padrao_mudou', v_pad,
                            'semente_saiu', v_pad and v_hist, 'semana', p_seg, 'dias', to_jsonb(v_dias), 'sabado', v_sab,
                            'texto', v_txt);
end;
$function$;

comment on function public._agenda_equipe_dias_gravar(uuid, date, smallint[], boolean, text, text, timestamptz, uuid, uuid, uuid) is
  'Agenda de Produção (Fase 7b, P2): o ÚNICO que escreve a semana presa (agenda_disponibilidade.semana_dita) — a resposta da pessoa à pergunta da semana (origem diarista, P3), a opção do dono na pergunta dias_semana (P3) e a semana dita pelo dono no rascunho (origem dono). Para cada dia de seg a sex da semana de p_seg, de hoje em diante e só dia útil: troca a linha viva da semana nesse dia e grava [d, d] disponível nos dias de p_dias e, nos outros, so_pontas (o dono: só abre e fecha) ou indisponível (os outros); o sábado (p_seg + 5), só com p_sabado, disponível de manhã (nunca "não vem"). Com origem diarista, a exceção viva do dono no dia vence: o dia fica e volta em conflitos [{dia, situacao_do_dono}]. O padrão: com dias, para quem já tem padrão ou é o dono (quem vem sob demanda só prende a semana), quando é outro — troca TODOS os padrões "vem" vivos da pessoa (qualquer origem: a semente sai) e grava o novo (sem frequência); "nenhum" prende só a semana. O mesmo de novo = nada muda ({mudou: false}). {mudou, linhas [{id, dia, situacao, turno}], conflitos, padrao_mudou, semente_saiu, semana, dias, sabado, texto ("Anotei: …")}. Security definer, search_path fixo, sem grant a ninguém (só as funções da agenda o chamam).';

-- ── 5. A chance de falta (só medida) ─────────────────────────────────────────────────────────────────────────────
-- Nas falta_semanas semanas ISO completas antes de p_hoje: dias = os dias úteis em que a pessoa estava dita (a semana presa
-- disponível ou confirmada, de origem diarista ou dono) ou tinha meio-dia não reserva vigente (ou cancelado pela pessoa); faltas =
-- desses, os com o "não vou" (exceção indisponível de origem diarista ou agente) criado depois do fim da manhã do dia útil anterior,
-- ou um meio-dia não cumprido porque a equipe faltou. Abaixo de falta_dias_min dias, "ainda pouco para medir".
create or replace function public._agenda_chance_de_falta(p_payee uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_seg0   date;
  v_dias   int;
  v_faltas int;
begin
  if p_payee is null or p_hoje is null then
    raise exception '_agenda_chance_de_falta: sem a pessoa ou o dia' using errcode = '22004';
  end if;
  v_seg0 := p_hoje - (extract(isodow from p_hoje)::int - 1);
  with
  uteis as (
    select g::date as d
      from generate_series(v_seg0 - 7 * c.falta_semanas, v_seg0 - 1, interval '1 day') g
     where public.agenda_dia_util(g::date)
  ),
  ditos as (
    select u.d from uteis u
     where exists (select 1 from public.agenda_disponibilidade a
                    where a.payee_id = p_payee and a.substituida_em is null and a.semana_dita is not null
                      and a.situacao in ('disponivel', 'confirmada') and a.origem in ('diarista', 'dono') and a.periodo @> u.d)
        or exists (select 1 from public.agenda_alocacoes l
                    where l.payee_id = p_payee and l.dia = u.d and l.tipo <> 'reserva'
                      and (l.estado in ('publicada', 'fixada') or (l.estado = 'cancelada' and l.cancelada_motivo = 'pessoa')))
  ),
  faltas as (
    select t.d from ditos t
     where exists (select 1 from public.agenda_disponibilidade a
                    where a.payee_id = p_payee and a.periodo @> t.d and a.situacao = 'indisponivel'
                      and a.origem in ('diarista', 'agente')
                      and a.criado_em > ((public.agenda_somar_du(t.d, -1) + c.manha_fim) at time zone 'America/Sao_Paulo'))
        or exists (select 1 from public.agenda_alocacoes l
                    where l.payee_id = p_payee and l.dia = t.d and l.resultado = 'nao_cumprido' and l.motivo = 'equipe_faltou')
  )
  select (select count(*) from ditos), (select count(*) from faltas) into v_dias, v_faltas;

  if v_dias < c.falta_dias_min then
    return jsonb_build_object('dias', v_dias, 'faltas', v_faltas, 'p', null, 'fonte', 'pouco_dado',
                              'texto', 'ainda pouco para medir');
  end if;
  return jsonb_build_object('dias', v_dias, 'faltas', v_faltas, 'p', round(v_faltas::numeric / v_dias, 2), 'fonte', 'medida',
                            'texto', format('%s de %s', v_faltas, v_dias));
end;
$function$;

comment on function public._agenda_chance_de_falta(uuid, date) is
  'Agenda de Produção (Fase 7b, P2; AG7-03): a chance de falta da pessoa, só MEDIDA (nunca desconta capacidade: o 7e decide o uso) — nas falta_semanas semanas ISO completas antes de p_hoje, dias = os dias úteis em que ela estava dita (semana presa disponível/confirmada, origem diarista ou dono) ou tinha meio-dia não reserva vigente ou cancelado pela pessoa; faltas = desses, os com o "não vou" (exceção indisponível de origem diarista ou agente) criado depois do fim da manhã (manha_fim) do dia útil anterior, ou meio-dia não cumprido com motivo equipe_faltou. Abaixo de falta_dias_min: {p: null, fonte: pouco_dado, texto "ainda pouco para medir"}; senão {p = faltas / dias, fonte medida, texto "1 de 12"}. STABLE, invoker.';

-- ── 6. A semana dita ("semana que vem", "semana de 16/11") ───────────────────────────────────────────────────────
create or replace function public._agenda_semana_dita(p_texto text, p_trecho text, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_s    text := public._agenda_normal(p_texto);
  v_seg0 date;
  v_seg  date;
  v_dt   jsonb;
begin
  if p_hoje is null then
    raise exception '_agenda_semana_dita: sem o dia de hoje' using errcode = '22004';
  end if;
  if v_s = '' then
    return public._agenda_recusa('Qual semana? (por exemplo, "semana que vem" ou "semana de 16/11")', 'semana');
  end if;
  v_seg0 := p_hoje - (extract(isodow from p_hoje)::int - 1);
  if v_s ~ '\m(essa|esta|nessa|nesta) semana\M' or v_s ~ '\m(a outra semana|outra semana|semana seguinte)\M' then
    if not public._agenda_trecho_tem(p_trecho, p_texto) then
      return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo.', btrim(p_texto)), 'fora_do_trecho');
    end if;
    v_seg := v_seg0 + case when v_s ~ '\m(essa|esta|nessa|nesta) semana\M' then 0 else 14 end;
  else
    v_dt := public._agenda_data_conferida(p_texto, p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then
      return v_dt;
    end if;
    v_seg := (v_dt ->> 'de')::date - (extract(isodow from (v_dt ->> 'de')::date)::int - 1);
  end if;
  if v_seg < v_seg0 then
    return public._agenda_recusa(format('A semana de %s já passou. Qual semana?', to_char(v_seg, 'DD/MM')), 'semana_passada');
  end if;
  return jsonb_build_object('ok', true, 'seg', v_seg, 'texto', 'semana de ' || to_char(v_seg, 'DD/MM'));
end;
$function$;

comment on function public._agenda_semana_dita(text, text, date) is
  'Agenda de Produção (Fase 7b, P2): a semana que o dono disse, conferida nas palavras dele — "semana que vem", "semana de 16/11", "dia 16" (a segunda da semana da data, por _agenda_data_conferida no sentido futuro), "essa semana" (a de hoje) e "a outra semana" / "semana seguinte" (daqui a duas). {ok: true, seg, texto "semana de 16/11"}; a semana que já passou, a data fora do trecho ou que não deu para entender = {ok: false, pergunta}. STABLE, invoker.';

-- ── 7. As recriadas (o corpo da definição mais nova; as mudanças só nos blocos "-- FASE 7b:") ─────────────────────
-- Fora dos blocos nenhuma linha muda. Quem recriar de novo qualquer uma delas copia DESTA migration.

-- agenda_capacidade (de 20261030100600_agenda_correcao_equipe.sql)
create or replace function public.agenda_capacidade(p_de date, p_ate date, p_hoje date default public._hoje_brt())
 returns table (payee_id uuid, pessoa text, eh_dono boolean, dia date, turno text, situacao text,
                meios_esperados numeric, origem text, motivo text)
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_column
declare
  c      public.agenda_config := public._agenda_cfg();
  v_dono uuid := public._agenda_dono(null);
begin
  if p_de is null or p_ate is null or p_ate < p_de then
    raise exception 'agenda_capacidade: período inválido (% a %)', p_de, p_ate using errcode = '22023';
  end if;
  if p_ate - p_de > 400 then
    raise exception 'agenda_capacidade: período longo demais (% dias)', p_ate - p_de using errcode = '22023';
  end if;

  return query
  with
  gente as (
    select py.id, public._agenda_nome_curto(py.name) as nome, py.id is not distinct from v_dono as dono
      from public.payees py
     where py.active
       and (py.id is not distinct from v_dono
            or (py.kind in ('prestador', 'diarista', 'funcionario')
                -- CORREÇÃO 30/10 (equipe): é da equipe também quem o dono declarou (linha vigente de
                -- agenda_disponibilidade com origem dono), não só quem tem a diária cadastrada vigente
                -- (work_profiles, que é o pagamento das diárias). Em 30/10 o dono tirou Roberto, João e
                -- Mickael e pôs o Alex (prestador, sem work_profiles) "todo dia útil, manhã e tarde", e a
                -- equipe ficou vazia: o motor não marcava nada.
                -- A disponibilidade em vigor continua exigida (a linha de baixo).
                -- antes: and exists (select 1 from public.work_profiles w
                -- antes:              where w.payee_id = py.id and w.vigencia_inicio <= p_hoje
                -- antes:                and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje))
                and (exists (select 1 from public.work_profiles w
                              where w.payee_id = py.id and w.vigencia_inicio <= p_hoje
                                and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje))
                     or exists (select 1 from public.agenda_disponibilidade d
                                 where d.payee_id = py.id and d.substituida_em is null and d.origem = 'dono'))
                -- CORREÇÃO 30/10 (equipe): fim
                and exists (select 1 from public.agenda_disponibilidade d
                             where d.payee_id = py.id and d.substituida_em is null)))
  ),
  grade as (
    select g.id, g.nome, g.dono, d::date as dia, extract(isodow from d)::int as dow, t.turno, t.ord
      from gente g
      cross join generate_series(p_de, p_ate, interval '1 day') d
      cross join (values ('manha', 1), ('tarde', 2)) t(turno, ord)
  ),
  regra as (
    select gr.*,
           ei.nota as ei_nota, ei.trecho as ei_trecho, ei.origem as ei_origem, ei.id as ei_id,
           ed.situacao as ed_sit, ed.nota as ed_nota, ed.origem as ed_origem, ed.id as ed_id,
           rc.nota as rc_nota, rc.id as rc_id,
           pi.nota as pi_nota, pi.origem as pi_origem, pi.id as pi_id,
           pd.nota as pd_nota, pd.origem as pd_origem, pd.frequencia as pd_freq, pd.id as pd_id,
           -- FASE 7b: (7b P2) o "só abre e fecha" do dono no dia (so_pontas: a exceção que a semana dita dele grava)
           sp.id as sp_id, sp.origem as sp_origem,
           -- FASE 7b: fim
           public.agenda_feriado(gr.dia) as feriado
      from grade gr
      left join lateral (   -- exceção da pessoa: não vem
        select d.* from public.agenda_disponibilidade d
         where d.payee_id = gr.id and d.substituida_em is null and d.periodo @> gr.dia
           and d.situacao = 'indisponivel' and (d.turno is null or d.turno = gr.turno)
         order by d.turno is not null desc, d.criado_em desc, d.id desc limit 1) ei on true
      left join lateral (   -- exceção da pessoa: vem (confirmada vence disponível)
        select d.* from public.agenda_disponibilidade d
         where d.payee_id = gr.id and d.substituida_em is null and d.periodo @> gr.dia
           and d.situacao in ('confirmada', 'disponivel') and (d.turno is null or d.turno = gr.turno)
         order by d.situacao = 'confirmada' desc, d.turno is not null desc, d.criado_em desc, d.id desc limit 1) ed on true
      left join lateral (   -- recesso (sem pessoa)
        select d.* from public.agenda_disponibilidade d
         where d.payee_id is null and d.substituida_em is null and d.periodo @> gr.dia
           and d.situacao = 'indisponivel' and (d.turno is null or d.turno = gr.turno)
         order by d.criado_em desc, d.id desc limit 1) rc on true
      left join lateral (   -- padrão: não vem neste turno ("sexta à tarde, escritório")
        select d.* from public.agenda_disponibilidade d
         where d.payee_id = gr.id and d.substituida_em is null and d.dias_semana @> array[gr.dow]::smallint[]
           and d.situacao = 'indisponivel' and (d.turno is null or d.turno = gr.turno)
         order by d.turno is not null desc, d.criado_em desc, d.id desc limit 1) pi on true
      left join lateral (   -- padrão: vem
        select d.* from public.agenda_disponibilidade d
         where d.payee_id = gr.id and d.substituida_em is null and d.dias_semana @> array[gr.dow]::smallint[]
           and d.situacao in ('disponivel', 'confirmada') and (d.turno is null or d.turno = gr.turno)
         order by d.turno is not null desc, d.criado_em desc, d.id desc limit 1) pd on true
      -- FASE 7b: (7b P2) a exceção viva so_pontas da pessoa no dia (só a do dono existe: _agenda_equipe_dias_gravar)
      left join lateral (
        select d.* from public.agenda_disponibilidade d
         where d.payee_id = gr.id and d.substituida_em is null and d.periodo @> gr.dia and d.situacao = 'so_pontas'
         order by d.criado_em desc, d.id desc limit 1) sp on true
      -- FASE 7b: fim
  )
  select r.id, r.nome, r.dono, r.dia, r.turno,
         case
           when r.ei_id is not null then 'indisponivel'
           when r.ed_id is not null then 'livre'
           when r.rc_id is not null then 'indisponivel'
           when r.dow = 7 or (r.dow = 6 and not c.sabado_util) then 'fim_de_semana'
           when r.feriado is not null then 'feriado'
           -- FASE 7b: (7b P2) "só abre e fecha" (so_pontas): sem padrão, 0 de campo — depois do feriado e antes do padrão
           -- "não vem"; a exceção "vem"/confirmada e o recesso continuam vencendo; as pontas ficam livres (agenda_grade, d11)
           when r.sp_id is not null then 'sem_padrao'
           -- FASE 7b: fim
           when r.pi_id is not null then 'indisponivel'
           when r.pd_id is not null then 'livre'
           else 'sem_padrao' end,
         case
           when r.ei_id is not null then 0::numeric
           when r.ed_id is not null then 1::numeric
           when r.rc_id is not null or r.dow = 7 or (r.dow = 6 and not c.sabado_util) or r.feriado is not null
                or r.pi_id is not null then 0::numeric
           -- FASE 7b: (7b P2) so_pontas: 0 meio-dia de campo
           when r.sp_id is not null then 0::numeric
           -- FASE 7b: fim
           when r.pd_id is not null then case when r.pd_origem = 'historico' then coalesce(r.pd_freq, 0) else 1::numeric end
           else 0::numeric end,
         case
           when r.ei_id is not null then r.ei_origem
           when r.ed_id is not null then r.ed_origem
           when r.rc_id is not null or r.dow = 7 or (r.dow = 6 and not c.sabado_util) or r.feriado is not null then null
           -- FASE 7b: (7b P2) so_pontas: a origem da linha
           when r.sp_id is not null then r.sp_origem
           -- FASE 7b: fim
           when r.pi_id is not null then r.pi_origem
           when r.pd_id is not null then r.pd_origem
           else null end,
         case
           when r.ei_id is not null then coalesce(r.ei_nota, r.ei_trecho, 'não vem')
           when r.ed_id is not null then coalesce(r.ed_nota, case r.ed_sit when 'confirmada' then 'confirmado' else 'combinado' end)
           when r.rc_id is not null then coalesce(r.rc_nota, 'recesso')
           when r.dow = 7 then 'domingo'
           when r.dow = 6 and not c.sabado_util then 'sábado só quando vocês combinam'
           when r.feriado is not null then r.feriado
           -- FASE 7b: (7b P2) so_pontas
           when r.sp_id is not null then 'você disse que nesse dia só abre e fecha'
           -- FASE 7b: fim
           when r.pi_id is not null then coalesce(r.pi_nota, 'não vem neste turno')
           when r.pd_id is not null then r.pd_nota
           when r.dono then 'você ainda não disse quais dias fica em campo'
           else 'sem padrão' end
    from regra r
   order by r.dono desc, r.nome, r.id, r.dia, r.ord;
end;
$function$;

comment on function public.agenda_capacidade(date, date, date) is
  'Agenda de Produção (Fase 1, P3): a grade por pessoa × dia × turno (manhã, tarde) — o dono e a equipe (diarista com cadastro vigente e disponibilidade em vigor). situacao: indisponivel (exceção da pessoa, recesso ou padrão "não vem neste turno"), livre (exceção "vem"/confirmada = 1 meio-dia; padrão do histórico = a frequência; padrão do dono = 1), fim_de_semana (domingo; sábado só por exceção, salvo agenda_config.sabado_util), feriado (o nome), sem_padrao. A exceção da pessoa vence o calendário; exceção indisponível > confirmada > disponível > padrão; o mais novo vence o empate. CORREÇÃO 30/10 (equipe): a equipe é quem está ativo (prestador, diarista ou funcionário), com disponibilidade em vigor e com a diária cadastrada vigente OU alguma linha vigente que o dono declarou (agenda_disponibilidade, origem dono): a diária cadastrada é do pagamento, não decide quem é da equipe. Fase 7b (P2): o dia em que o dono disse que só abre e fecha (exceção viva so_pontas, que só a semana dita dele grava: _agenda_equipe_dias_gravar) vira sem_padrao, 0 meio-dia de campo, origem a da linha, motivo "você disse que nesse dia só abre e fecha" — depois do feriado e antes do padrão "não vem"; a exceção "vem"/confirmada e o recesso continuam vencendo, e as pontas de abrir e fechar continuam livres (agenda_grade). Sem linha so_pontas, a saída de antes, byte a byte.';

-- agenda_capacidade_semanal (de 20261030100600_agenda_correcao_equipe.sql)
create or replace function public.agenda_capacidade_semanal(p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_column
declare
  c         public.agenda_config := public._agenda_cfg();
  v_dono    uuid := public._agenda_dono(null);
  v_pessoas jsonb;
  v_total   numeric;
  v_conta_dono boolean;
  v_ultima  date;
  v_sem     int;
  -- FASE 7b: (7b P2, R4.5) as diárias do dono na semana típica e as dos técnicos
  v_7b_dono  numeric;
  v_7b_dm    numeric;
  v_7b_tec   numeric;
  -- FASE 7b: fim
begin
  -- A semana típica pelo PADRÃO de cada pessoa (sem exceção nem feriado): Σ dos meios-dias esperados ÷ 2.
  with
  gente as (
    select py.id, py.name, public._agenda_nome_curto(py.name) as nome, py.id is not distinct from v_dono as dono
      from public.payees py
     where py.active
       and exists (select 1 from public.agenda_disponibilidade d
                    where d.payee_id = py.id and d.substituida_em is null and d.dias_semana is not null
                      and d.situacao in ('disponivel', 'confirmada'))
       and (py.id is not distinct from v_dono
            or (py.kind in ('prestador', 'diarista', 'funcionario')
                -- CORREÇÃO 30/10 (equipe): a mesma régua de agenda_capacidade: com a diária
                -- cadastrada vigente OU alguma linha vigente que o dono declarou (origem dono). O padrão
                -- em vigor (a linha de cima) continua exigido.
                -- antes: and exists (select 1 from public.work_profiles w
                -- antes:              where w.payee_id = py.id and w.vigencia_inicio <= p_hoje
                -- antes:                and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje))))
                and (exists (select 1 from public.work_profiles w
                              where w.payee_id = py.id and w.vigencia_inicio <= p_hoje
                                and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje))
                     or exists (select 1 from public.agenda_disponibilidade d
                                 where d.payee_id = py.id and d.substituida_em is null and d.origem = 'dono'))))
                -- CORREÇÃO 30/10 (equipe): fim
  ),
  semana as (
    select g.*, s.dow, t.turno
      from gente g
      cross join generate_series(1, case when c.sabado_util then 6 else 5 end) s(dow)
      cross join (values ('manha'), ('tarde')) t(turno)
  ),
  meios as (
    select s.id, s.nome, s.dono, s.name,
           case when pi.id is not null then 0
                when pd.id is not null then case when pd.origem = 'historico' then coalesce(pd.frequencia, 0) else 1 end
                else 0 end as m
      from semana s
      left join lateral (
        select d.id from public.agenda_disponibilidade d
         where d.payee_id = s.id and d.substituida_em is null and d.dias_semana @> array[s.dow]::smallint[]
           and d.situacao = 'indisponivel' and (d.turno is null or d.turno = s.turno)
         limit 1) pi on true
      left join lateral (
        select d.id, d.origem, d.frequencia from public.agenda_disponibilidade d
         where d.payee_id = s.id and d.substituida_em is null and d.dias_semana @> array[s.dow]::smallint[]
           and d.situacao in ('disponivel', 'confirmada') and (d.turno is null or d.turno = s.turno)
         order by d.turno is not null desc, d.criado_em desc, d.id desc limit 1) pd on true
  ),
  porpessoa as (
    select m.id, m.nome, m.dono, m.name, sum(m.m) / 2 as diarias from meios m group by m.id, m.nome, m.dono, m.name
  )
  select coalesce(jsonb_agg(jsonb_build_object('payee_id', q.id, 'nome', q.nome, 'eh_dono', q.dono,
                                               'diarias_semana', round(q.diarias, 2))
                            order by q.dono desc, q.name, q.id), '[]'::jsonb),
         coalesce(sum(q.diarias), 0),
         coalesce(bool_or(q.dono), false)
    into v_pessoas, v_total, v_conta_dono
    from porpessoa q;

  select max(ws.data) into v_ultima
    from public.work_shifts ws
   where ws.tipo = 'diaria' and ws.fracao > 0 and ws.data <= p_hoje;
  v_sem := public.agenda_du_entre(v_ultima, p_hoje);

  -- FASE 7b: (7b P2; R4.5, AG7-02) com a pergunta dos dias fora de desligado (modo_dias: desde o dado de sombra, sem esperar o OK
  -- dos textos à equipe), o dono com padrão conta meia capacidade: as diárias dele entram multiplicadas por dono_carga_max (seg a
  -- sex: 5 × 0,50) e o comprometível dele é esse mesmo número (o teto dele já é dono_carga_max); os técnicos como antes
  -- (× carga_max). Com o Alex e a linha do dono: 7,5 diárias e 6,5 comprometíveis, não 10 e 8. Desligado, ou sem a linha do
  -- dono, a saída de antes.
  if c.modo_dias <> 'desligado' and v_conta_dono then
    select (e ->> 'diarias_semana')::numeric into v_7b_dono
      from jsonb_array_elements(v_pessoas) e where (e ->> 'eh_dono')::boolean;
    v_7b_dm := round(v_7b_dono * c.dono_carga_max, 2);
    v_7b_tec := v_total - v_7b_dono;
    select coalesce(jsonb_agg(case when (e ->> 'eh_dono')::boolean then jsonb_set(e, '{diarias_semana}', to_jsonb(v_7b_dm))
                                   else e end order by o), '[]'::jsonb)
      into v_pessoas
      from jsonb_array_elements(v_pessoas) with ordinality t(e, o);
    return jsonb_build_object(
      'diarias_semana', round(v_7b_tec + v_7b_dm, 2),
      'comprometivel', round(v_7b_tec * c.carga_max + v_7b_dm, 2),
      'carga_max', c.carga_max,
      'conta_dono', v_conta_dono,
      'pessoas', v_pessoas,
      'ultima_diaria', v_ultima,
      'dias_sem_lancar', v_sem,
      'aviso', case when v_ultima is null then 'nenhuma diária lançada ainda'
                    when v_sem >= 2 then 'nenhuma diária foi lançada depois de ' || public._dia_curto(v_ultima) end);
  end if;
  -- FASE 7b: fim
  return jsonb_build_object(
    'diarias_semana', round(v_total, 2),
    'comprometivel', round(v_total * c.carga_max, 2),
    'carga_max', c.carga_max,
    'conta_dono', v_conta_dono,
    'pessoas', v_pessoas,
    'ultima_diaria', v_ultima,
    'dias_sem_lancar', v_sem,
    'aviso', case when v_ultima is null then 'nenhuma diária lançada ainda'
                  when v_sem >= 2 then 'nenhuma diária foi lançada depois de ' || public._dia_curto(v_ultima) end);
end;
$function$;

comment on function public.agenda_capacidade_semanal(date) is
  'Agenda de Produção (Fase 1, P3): o ÚNICO número de capacidade — diarias_semana = Σ, por pessoa com padrão, dos meios-dias esperados da semana típica ÷ 2 (padrão do histórico = a frequência; do dono = 1; "não vem neste turno" = 0); comprometivel = diarias_semana × agenda_config.carga_max. O dono só entra quando tem padrão (conta_dono). Também: a última diária lançada, os dias úteis sem lançar e o aviso quando passam de 1. CORREÇÃO 30/10 (equipe): conta, além do dono com padrão, quem está ativo (prestador, diarista ou funcionário), tem padrão em vigor e tem a diária cadastrada vigente OU alguma linha vigente que o dono declarou (agenda_disponibilidade, origem dono) — a régua de agenda_capacidade. Fase 7b (P2; R4.5, AG7-02): com modo_dias fora de desligado, o dono com padrão conta meia capacidade — as diárias dele entram multiplicadas por agenda_config.dono_carga_max (seg a sex: 2,5) e o comprometível dele é esse mesmo número (o teto dele já é dono_carga_max); os técnicos como antes (× carga_max). Com o Alex e a linha do dono: 7,5 diárias, 6,5 comprometíveis. Desligado, ou sem a linha do dono, byte a byte.';

-- A assinatura nova (p_semana no fim): o drop da de 8 argumentos vem antes (com as duas, a chamada por nome do ai-agent ficaria
-- ambígua). As portas são as de antes, repetidas abaixo para a de 9.
drop function if exists public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date);

-- agenda_rascunho_disponibilidade (de 20261024160600_agenda_fase1_rascunho.sql)
create or replace function public.agenda_rascunho_disponibilidade(p_autor uuid, p_canal text, p_pessoa text, p_situacao text,
                                                                  p_dias text, p_padrao boolean default false,
                                                                  p_trecho text default null,
                                                                  p_hoje date default public._hoje_brt(),
                                                                  p_semana text default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  v_rp     jsonb;
  v_turno  text;
  v_sit    text;
  v_dias   smallint[];
  v_dt     jsonb;
  v_chave  text;
  v_dados  jsonb;
  v_txt    text;
  v_sab    boolean := false;
  -- FASE 7b: (7b P2) a semana dita, as datas de quem vem sob demanda e a pessoa do cadastro
  v_7b_modo  text := (public._agenda_cfg()).modo_dias;
  v_7b_sab   text := (public._agenda_cfg()).sabado_manha;
  v_7b_fora  boolean := false;
  v_7b_sem   jsonb;
  v_7b_seg   date;
  v_7b_dl    smallint[];
  v_7b_w     date;
  v_7b_datas date[];
  v_7b_d     date;
  v_7b_cad   jsonb;
  v_7b_n     int;
  v_7b_tok   text[];
  c_7b_vazias constant text[] := array['o', 'a', 'do', 'da', 'de', 'com', 'e', 'seu', 'sua', 'sr', 'senhor', 'tecnico'];
  -- FASE 7b: fim
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_rascunho_disponibilidade: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;
  if (public._agenda_cfg()).modo_leitura = 'desligado' then
    return public._agenda_recusa('A agenda de produção está desligada agora: não anotei nada.', 'desligada');
  end if;
  select x.turno, x.sit into v_turno, v_sit
    from (values ('vem', null, 'disponivel'), ('nao_vem', null, 'indisponivel'),
                 ('so_manha', 'tarde', 'indisponivel'), ('so_tarde', 'manha', 'indisponivel')) x(dito, turno, sit)
   where x.dito = lower(btrim(coalesce(p_situacao, '')));
  if not found then
    raise exception 'agenda_rascunho_disponibilidade: situação "%" não existe (vem, nao_vem, so_manha ou so_tarde)', p_situacao
      using errcode = '22023';
  end if;
  -- FASE 7b: (7b P2) a semana dita (p_semana): só com a pergunta dos dias fora de desligado (modo_dias); nunca padrão; os dias
  -- inteiros (meio dia só por data)
  if nullif(btrim(coalesce(p_semana, '')), '') is not null then
    if v_7b_modo = 'desligado' then
      return public._agenda_recusa('Anotar os dias de uma semana só ainda não está ligado. Diga as datas (ex.: "Roberto vem quarta dia 18") ou os dias de toda semana (ex.: "Roberto vem toda terça").',
                                   'semana_desligada');
    end if;
    if coalesce(p_padrao, false) then
      raise exception 'agenda_rascunho_disponibilidade: semana e padrão juntos (a semana dita nunca é padrão)' using errcode = '22023';
    end if;
    if v_turno is not null then
      return public._agenda_recusa('Para a semana, me diga os dias inteiros; meio dia só por data.', 'semana_turno');
    end if;
  end if;
  -- FASE 7b: fim
  if nullif(btrim(p_trecho), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras quem vem e quando.', 'sem_trecho');
  end if;
  if nullif(btrim(p_dias), '') is null then
    return public._agenda_recusa('Quais dias?', 'sem_dias');
  end if;

  v_rp := public.agenda_resolver_pessoa(p_pessoa, v_autor, p_hoje);
  -- FASE 7b: (7b P2, R4.2(c)3) quem o dono chama quando precisa (Mateus) ainda não está na equipe: com "vem" e a pergunta dos
  -- dias fora de desligado, procura entre as pessoas ATIVAS do cadastro (prestador, diarista ou funcionário; nunca o sócio) pela
  -- régua do nome do resolvedor (todo pedaço começa uma palavra do nome; o 1º nome igual vence)
  if v_7b_modo <> 'desligado' and v_rp ->> 'status' = 'nao_achei' and v_sit = 'disponivel' and v_turno is null then
    v_7b_tok := array(select t from unnest(string_to_array(public._agenda_normal(p_pessoa), ' ')) with ordinality u(t, o)
                       where length(t) >= 2 and t <> all (c_7b_vazias) order by o);
    if cardinality(v_7b_tok) > 0 then
      with gente as (
        select p.id, p.name, string_to_array(public._agenda_normal(p.name), ' ') as palavras
          from public.payees p
         where p.active and p.kind in ('prestador', 'diarista', 'funcionario')
      ),
      casam as (
        select g.*, g.palavras[1] = v_7b_tok[1] as exato from gente g
         where not exists (select 1 from unnest(v_7b_tok) t
                            where not exists (select 1 from unnest(g.palavras) w where w like t || '%'))
      ),
      melhor as (select c.* from casam c where c.exato or not exists (select 1 from casam x where x.exato))
      select coalesce(jsonb_agg(jsonb_build_object('payee_id', m.id, 'nome', m.name, 'nome_curto', public._agenda_nome_curto(m.name))
                                order by m.name, m.id), '[]'::jsonb), count(*)
        into v_7b_cad, v_7b_n
        from melhor m;
      if v_7b_n = 0 then
        return public._agenda_recusa(format('Não achei %s no cadastro de pessoas. Cadastre ele (o nome e o telefone) e me diga de novo.',
                                            btrim(p_pessoa)), 'pessoa_sem_cadastro');
      end if;
      if v_7b_n > 1 then
        return public._agenda_recusa(format('Qual %s: %s ou %s?', btrim(p_pessoa),
                 array_to_string(array(select e ->> 'nome' from jsonb_array_elements(v_7b_cad) with ordinality t(e, o)
                                        where o < v_7b_n order by o), ', '),
                 v_7b_cad -> (v_7b_n - 1) ->> 'nome'),
               'pessoa_ambiguo', coalesce((select jsonb_agg(e ->> 'nome' order by o) from jsonb_array_elements(v_7b_cad) with ordinality t(e, o)), '[]'::jsonb));
      end if;
      v_rp := jsonb_build_object('status', 'ok', 'payee_id', v_7b_cad -> 0 ->> 'payee_id', 'nome_curto', v_7b_cad -> 0 ->> 'nome_curto',
                                 'eh_dono', false, 'texto', v_7b_cad -> 0 ->> 'nome_curto');
      v_7b_fora := true;
    end if;
  end if;
  -- FASE 7b: fim
  if v_rp ->> 'status' <> 'ok' then
    return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status'),
      coalesce((select jsonb_agg(e ->> 'nome' order by o)
                  from jsonb_array_elements(coalesce(v_rp -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
  end if;

  v_dados := jsonb_build_object(
    'grupo', 'pessoa:' || (v_rp ->> 'payee_id'), 'payee_id', v_rp ->> 'payee_id', 'nome', v_rp ->> 'nome_curto',
    'eh_dono', coalesce((v_rp ->> 'eh_dono')::boolean, false),
    'rotulo_grupo', case when coalesce((v_rp ->> 'eh_dono')::boolean, false) then 'Você' else v_rp ->> 'nome_curto' end,
    'padrao', coalesce(p_padrao, false), 'turno', v_turno, 'situacao', v_sit, 'dito', lower(btrim(p_situacao)));

  -- FASE 7b: (7b P2) a pessoa fora da equipe (a do cadastro) vai marcada no rascunho: a releitura diz que, com *grava*, ela entra
  if v_7b_modo <> 'desligado' then
    v_dados := v_dados || jsonb_build_object('fora_da_equipe', v_7b_fora);
  end if;
  -- a semana dita: os dias inteiros dela, nunca padrão (_agenda_equipe_dias_gravar prende a semana no *grava*)
  if nullif(btrim(coalesce(p_semana, '')), '') is not null then
    v_7b_sem := public._agenda_semana_dita(p_semana, p_trecho, p_hoje);
    if not (v_7b_sem ->> 'ok')::boolean then return v_7b_sem; end if;
    v_7b_seg := (v_7b_sem ->> 'seg')::date;
    if v_sit = 'disponivel' then
      begin
        v_dias := public.agenda_dias_da_semana_ditos(p_dias);
      exception when sqlstate '22007' then
        return public._agenda_recusa(sqlerrm, 'dias');
      end;
      if not (v_dias::int[] <@ public._agenda_dias_citados(p_trecho)) then
        return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo quais dias.', btrim(p_dias)), 'fora_do_trecho');
      end if;
      v_sab := 6 = any (v_dias);
      v_dias := array_remove(v_dias, 6::smallint);
    elsif public._agenda_normal(p_dias) ~ '\m(nenhum|semana|todo|todos|toda|inteira)\M' then
      v_dias := '{}';
      v_sab := false;
    else
      return public._agenda_recusa('Para um dia só, me diga a data (ex.: "Roberto não vem quarta dia 18"); para a semana, os dias em que vem (ex.: "Roberto vem seg, ter e qui na semana que vem").',
                                   'semana_nao_vem_dia');
    end if;
    v_chave := format('disp:%s:s%s', v_rp ->> 'payee_id', v_7b_seg);
    v_dados := v_dados || jsonb_build_object(
      'grupo', 'pessoa:' || (v_rp ->> 'payee_id') || ':s' || v_7b_seg,
      'rotulo_grupo', (case when coalesce((v_rp ->> 'eh_dono')::boolean, false) then 'Você' else v_rp ->> 'nome_curto' end)
                      || ', semana de ' || to_char(v_7b_seg, 'DD/MM'),
      'semana', v_7b_seg, 'dias_semana', to_jsonb(v_dias), 'sabado', v_sab, 'padrao', false);
    v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'disponibilidade', v_chave, null, v_dados, p_trecho, p_hoje);
    return jsonb_build_object('ok', true, 'item', v_txt,
                              'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
  end if;
  -- as datas de quem vem sob demanda ("Mateus vem qua e qui"): 2 ou mais dias da semana que não são uma faixa (a data dita é um
  -- dia só, ou não deu para ler) viram as datas desses dias na 1ª semana (seg a sáb) em que todos ainda estão por vir, estritamente
  -- depois de hoje; só dia útil; o sábado só de manhã e só com sabado_manha ≠ nunca. Nunca padrão.
  if v_7b_modo <> 'desligado' and not coalesce(p_padrao, false) and v_sit = 'disponivel' and v_turno is null then
    v_dt := public._agenda_data_conferida(p_dias, p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean or v_dt ->> 'de' = v_dt ->> 'ate' then
      begin
        v_7b_dl := public.agenda_dias_da_semana_ditos(p_dias);
      exception when sqlstate '22007' then
        v_7b_dl := null;
      end;
      if cardinality(v_7b_dl) >= 2 and v_7b_dl::int[] <@ public._agenda_dias_citados(p_trecho) then
        v_7b_w := p_hoje - (extract(isodow from p_hoje)::int - 1);
        if exists (select 1 from unnest(v_7b_dl) x where v_7b_w + (x - 1) <= p_hoje) then
          v_7b_w := v_7b_w + 7;
        end if;
        v_7b_datas := array(select v_7b_w + (x - 1) from unnest(v_7b_dl) x order by 1);
        foreach v_7b_d in array v_7b_datas loop
          if extract(isodow from v_7b_d)::int = 6 then
            if v_7b_sab = 'nunca' then
              return public._agenda_recusa('Sábado eu não conto na agenda agora. Diga só os dias de segunda a sexta.', 'sabado_nunca');
            end if;
            if public.agenda_feriado(v_7b_d) is not null then
              return public._agenda_recusa(format('%s é feriado (%s): outro dia?', public._dia_curto(v_7b_d), public.agenda_feriado(v_7b_d)),
                                           'feriado');
            end if;
          elsif not public.agenda_dia_util(v_7b_d) then
            return public._agenda_recusa(case when public.agenda_feriado(v_7b_d) is not null
                                              then format('%s é feriado (%s): outro dia?', public._dia_curto(v_7b_d), public.agenda_feriado(v_7b_d))
                                              else format('%s não é dia de trabalho na agenda: outro dia?', public._dia_curto(v_7b_d)) end,
                                         'feriado');
          end if;
        end loop;
        v_chave := format('disp:%s:l%s:dia', v_rp ->> 'payee_id', array_to_string(v_7b_datas, '_'));
        v_dados := v_dados || jsonb_build_object('datas', to_jsonb(v_7b_datas));
        v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'disponibilidade', v_chave, null, v_dados, p_trecho, p_hoje);
        return jsonb_build_object('ok', true, 'item', v_txt,
                                  'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
      end if;
    end if;
  end if;
  -- FASE 7b: fim
  if coalesce(p_padrao, false) then
    begin
      v_dias := public.agenda_dias_da_semana_ditos(p_dias);
    exception when sqlstate '22007' then
      return public._agenda_recusa(sqlerrm, 'dias');
    end;
    if not (v_dias::int[] <@ public._agenda_dias_citados(p_trecho)) then
      return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo quais dias.', btrim(p_dias)), 'fora_do_trecho');
    end if;
    -- Sábado só por data (agenda_config.sabado_util): a capacidade e a grade não leem padrão de sábado. Só sábado =
    -- pergunta qual; com outros dias ("segunda a sábado"), fica o resto e a releitura diz que o sábado é por data.
    v_sab := 6 = any (v_dias) and not (public._agenda_cfg()).sabado_util;
    if v_sab then
      if cardinality(v_dias) = 1 then
        return public._agenda_recusa(case when v_sit = 'disponivel'
                                          then 'Sábado eu só conto por data: qual sábado? (por exemplo, "sábado dia 31")'
                                          else 'Sábado já fica fora da conta: só conto sábado quando você diz a data.' end,
                                     'sabado_padrao');
      end if;
      v_dias := array_remove(v_dias, 6::smallint);
    end if;
    v_chave := format('disp:%s:p%s:%s', v_rp ->> 'payee_id', array_to_string(v_dias, ''), coalesce(v_turno, 'dia'));
    -- sabado_por_data sempre escrito: a correção da mesma chave não herda o aviso de um sábado que não foi dito de novo.
    v_dados := v_dados || jsonb_build_object('dias_semana', to_jsonb(v_dias), 'sabado_por_data', v_sab);
  else
    v_dt := public._agenda_data_conferida(p_dias, p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. Para quando é?', btrim(p_dias)), 'data_passada');
    end if;
    v_chave := format('disp:%s:d%s_%s:%s', v_rp ->> 'payee_id', greatest((v_dt ->> 'de')::date, p_hoje), v_dt ->> 'ate',
                      coalesce(v_turno, 'dia'));
    v_dados := v_dados || jsonb_build_object('de', greatest((v_dt ->> 'de')::date, p_hoje), 'ate', (v_dt ->> 'ate')::date);
  end if;

  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'disponibilidade', v_chave, null, v_dados, p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date, text) is
  'Agenda de Produção (Fase 1, P5): quem vem quando vira RASCUNHO (nada em agenda_disponibilidade). p_situacao vem (disponível), nao_vem (indisponível), so_manha (a tarde indisponível), so_tarde (a manhã indisponível); p_padrao = toda semana (agenda_dias_da_semana_ditos: "segunda a sexta"; sábado só por data, salvo sabado_util: só sábado = pergunta, com outros dias sai do padrão e a releitura avisa), senão a data dita (agenda_data_dita, futuro). Pessoa resolvida no banco ("eu" = o sócio do login); os dias têm de estar no trecho. Devolve {ok, item, releitura} ou {ok:false, pergunta}. Fase 7b (P2): assinatura nova com p_semana no fim (a de 8 argumentos saiu; a chamada por nome de antes continua casando). Com a pergunta dos dias fora de desligado (modo_dias): p_semana ("semana que vem", "semana de 16/11", por _agenda_semana_dita) = os dias da semana dita (vem + os dias, o sábado de manhã; nao_vem + "a semana toda" = nenhum; um dia só é por data), nunca padrão, sem turno; chave disp:<pessoa>:s<segunda>; a releitura "Roberto, semana de 16/11: vem seg, ter e qui (e não vem qua e sex)." — o *grava* prende a semana (_agenda_equipe_dias_gravar). Sem padrão e sem semana, "vem" com 2 ou mais dias da semana que não são uma faixa ("qua e qui") = as datas desses dias na 1ª semana (seg a sáb) em que todos ainda estão por vir, estritamente depois de hoje; só dia útil (o feriado é recusado com o nome); sábado só com sabado_manha ≠ nunca e só de manhã; chave disp:<pessoa>:l<d1>_<d2>…:dia; nunca padrão; "qua a sex" continua faixa. Quem não está na equipe mas está no cadastro (prestador, diarista ou funcionário ativo; o 1º nome igual vence) entra pelo rascunho com "vem" e a releitura diz que, com *grava*, ele entra; ninguém = "Não achei Vinicius no cadastro de pessoas. Cadastre ele (o nome e o telefone) e me diga de novo."; vários = "Qual Mateus: …?". Com modo_dias desligado, o de antes, byte a byte, e p_semana é recusado com a frase.';

-- _agenda_aplicar_disponibilidade (de 20261024160600_agenda_fase1_rascunho.sql)
create or replace function public._agenda_aplicar_disponibilidade(p_autor uuid, p_dados jsonb, p_trecho text, p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  d       jsonb := coalesce(p_dados, '{}'::jsonb);
  v_payee uuid := (d ->> 'payee_id')::uuid;
  v_per   daterange;
  v_id    uuid;
  -- FASE 7b: (7b P2) a semana dita e as datas de quem vem sob demanda
  v_7b_agora timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  v_7b_perg  uuid;
  v_7b_r     jsonb;
  v_7b_d     date;
  v_7b_turno text;
  v_7b_ids   jsonb := '[]'::jsonb;
  -- FASE 7b: fim
begin
  if not exists (select 1 from public.payees where id = v_payee) then
    raise exception '% não está mais no cadastro', coalesce(d ->> 'nome', 'a pessoa') using errcode = 'P0001';
  end if;
  -- FASE 7b: (7b P2) a semana dita pelo dono: o gravador da semana presa (origem dono); a pergunta dias_semana aberta dessa pessoa e
  -- semana fecha ("você disse os dias")
  if d ? 'semana' then
    select q.id into v_7b_perg
      from public.agenda_perguntas q
     where q.tipo = 'dias_semana' and q.estado = 'aberta' and q.chave = format('dias_semana:%s:%s', v_payee, (d ->> 'semana')::date)
     order by q.criada_em desc, q.id desc limit 1;
    v_7b_r := public._agenda_equipe_dias_gravar(v_payee, (d ->> 'semana')::date,
                array(select jsonb_array_elements_text(d -> 'dias_semana')::smallint), coalesce((d ->> 'sabado')::boolean, false),
                'dono', p_trecho, v_7b_agora, null, v_7b_perg, p_autor);
    if v_7b_perg is not null then
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'você disse os dias' where id = v_7b_perg;
    end if;
    return jsonb_build_object('linha', null, 'semana', v_7b_r);
  end if;
  -- as datas de quem vem sob demanda: uma exceção [d, d] por data, disponível, origem dono, o turno dito (o sábado só de manhã);
  -- a mesma data e turno ditos antes, e a linha da semana presa do dia, saem (a palavra do dono é a mais nova). Nunca padrão.
  if d ? 'datas' then
    for v_7b_d in select x::date from jsonb_array_elements_text(d -> 'datas') x loop
      v_7b_turno := case when extract(isodow from v_7b_d)::int = 6 then 'manha' else d ->> 'turno' end;
      v_per := daterange(v_7b_d, v_7b_d, '[]');
      update public.agenda_disponibilidade
         set substituida_em = now()
       where payee_id = v_payee and substituida_em is null and origem = 'dono' and periodo = v_per
         and turno is not distinct from v_7b_turno;
      update public.agenda_disponibilidade
         set substituida_em = now()
       where payee_id = v_payee and substituida_em is null and semana_dita is not null and periodo && v_per
         and (v_7b_turno is null or turno is not distinct from v_7b_turno);
      insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, trecho, criado_por)
      values (v_payee, v_per, v_7b_turno, d ->> 'situacao', 'dono',
              case when coalesce((d ->> 'eh_dono')::boolean, false) then 'Você disse que fica em campo'
                   else 'Você disse que vem (sob demanda)' end,
              public._agenda_corta(p_trecho, 300), p_autor)
      returning id into v_id;
      v_7b_ids := v_7b_ids || to_jsonb(v_id);
    end loop;
    return jsonb_build_object('linha', v_7b_ids -> 0, 'linhas', v_7b_ids);
  end if;
  -- FASE 7b: fim
  if coalesce((d ->> 'padrao')::boolean, false) then
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho, criado_por)
    values (v_payee, array(select jsonb_array_elements_text(d -> 'dias_semana')::smallint), d ->> 'turno', d ->> 'situacao',
            'dono', format('você disse em %s', to_char(p_hoje, 'DD/MM')), public._agenda_corta(p_trecho, 300), p_autor)
    returning id into v_id;
  else
    v_per := daterange((d ->> 'de')::date, (d ->> 'ate')::date, '[]');
    -- A mesma data e o mesmo turno ditos de novo trocam o que o dono tinha dito antes (fica o rastro).
    update public.agenda_disponibilidade
       set substituida_em = now()
     where payee_id = v_payee and substituida_em is null and origem = 'dono' and periodo = v_per
       and turno is not distinct from d ->> 'turno';
    -- FASE 7b: (7b P2) a data dita pelo dono troca também a linha da semana presa da pessoa no mesmo dia — a do dia inteiro, ou a
    -- do mesmo turno (a palavra do dono é a mais nova; a exceção de um turno só não tira a do dia inteiro: a capacidade já põe o
    -- "não vem neste turno" por cima). Sem semana presa, nada a trocar.
    update public.agenda_disponibilidade
       set substituida_em = now()
     where payee_id = v_payee and substituida_em is null and semana_dita is not null and periodo && v_per
       and (d ->> 'turno' is null or turno is not distinct from d ->> 'turno');
    -- FASE 7b: fim
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, trecho, criado_por)
    values (v_payee, v_per, d ->> 'turno', d ->> 'situacao', 'dono', format('você disse em %s', to_char(p_hoje, 'DD/MM')),
            public._agenda_corta(p_trecho, 300), p_autor)
    returning id into v_id;
  end if;
  return jsonb_build_object('linha', v_id);
end;
$function$;

comment on function public._agenda_aplicar_disponibilidade(uuid, jsonb, text, date) is
  'Agenda de Produção (Fase 1, P5): grava em agenda_disponibilidade uma linha de rascunho disponibilidade (origem dono): padrão por dia da semana (a troca dos padrões vigentes que o novo cobre é feita uma vez pelo agenda_rascunho_gravar) ou exceção por data (a mesma data e turno ditos antes ganham substituida_em). Só pelo agenda_rascunho_gravar; só service_role. Fase 7b (P2): dados.semana (a semana dita pelo dono, pelo rascunho) → _agenda_equipe_dias_gravar(pessoa, semana, dias, sábado, origem dono, o trecho, a hora do *grava*, a pergunta dias_semana aberta dessa pessoa e semana) e essa pergunta fecha ("você disse os dias"); dados.datas (quem vem sob demanda: "Mateus vem qua e qui") → uma exceção [d, d] por data, disponível, origem dono, o turno dito (o sábado de manhã), "Você disse que vem (sob demanda)" (o dono: "Você disse que fica em campo"), nunca padrão; e toda exceção por data troca também a linha da semana presa da pessoa no mesmo dia, a do dia inteiro ou a do mesmo turno (a palavra do dono é a mais nova).';

-- agenda_rascunho_gravar (de 20261031100800_agenda_fase7a_compras.sql)
create or replace function public.agenda_rascunho_gravar(p_autor uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor   uuid := public._autor_da_agenda(p_autor);
  v_exp     int;
  v_exp_dia date;
  v_ids     uuid[];
  v_oss_mat uuid[];
  v_r       public.agenda_rascunho%rowtype;
  v_x       uuid;
  v_n       int := 0;
  v_item    text;
  v_estado  text;
  v_msg     text;
  v_linhas  text[] := '{}';
  v_g       record;
  v_p       jsonb;
  v_nome    int;
  -- FASE 2: a hora do *grava* (now(); a bancada fixa com set_config('agenda.agora', …, true), como agenda.hoje), a
  -- config, as frases do que a agenda fez com os pedidos e o tipo de cada linha.
  v_agora   timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  cf        public.agenda_config := public._agenda_cfg();
  v_f2      text[] := '{}';
  v_f2_item text;
begin
  perform pg_advisory_xact_lock(hashtext('agenda_rascunho:' || v_autor::text));
  -- FASE 7: (7a P10) as frases da peça que voltou a faltar (_agenda_aplicar_material as junta em agenda.material_reabriu)
  -- começam vazias neste *grava*
  perform set_config('agenda.material_reabriu', '', true);
  -- FASE 7: fim

  -- O que passou da validade não grava (e fica marcado, mesmo se o resto falhar).
  with e as (
    update public.agenda_rascunho set estado = 'expirado'
     where autor = v_autor and estado = 'aberto' and expira_em <= now()
    returning criado_em)
  select count(*), max((e.criado_em at time zone 'America/Sao_Paulo')::date) into v_exp, v_exp_dia from e;

  -- FASE 2: primeiro os fatos (Fase 1), depois o andamento, marcar, publicar/decidir e desfazer — cada grupo na ordem em
  -- que o dono falou.
  select coalesce(array_agg(r.id order by case r.tipo when 'andamento' then 1 when 'marcar' then 2 when 'aplicar' then 3
                                                      when 'desfazer' then 4 else 0 end,
                                          (r.dados ->> 'ordem')::int, r.criado_em, r.id), '{}'),
         coalesce(array_agg(distinct r.service_order_id) filter (where r.tipo = 'material'), '{}')
    into v_ids, v_oss_mat
    from public.agenda_rascunho r
   where r.autor = v_autor and r.estado = 'aberto';

  if cardinality(v_ids) = 0 then
    return jsonb_build_object('ok', true, 'gravados', 0, 'expirados', v_exp,
      'texto', case when v_exp > 0 then format('A releitura de %s expirou; me diga de novo o que mudou.', public._dia_curto(v_exp_dia))
                    else 'Não tenho nada esperando para gravar.' end);
  end if;

  -- FASE 2: com a agenda automática fora de 'ligado', o pedido à agenda não grava — e o lote é tudo ou nada.
  -- FASE 3: menos concluir e entregar, que valem em todos os modos (a conclusão pela porta é a correção do D7).
  if cf.modo_proposta <> 'ligado'
     and exists (select 1 from public.agenda_rascunho r where r.id = any (v_ids) and r.tipo in ('marcar', 'aplicar', 'desfazer', 'andamento')
                    and not (r.tipo = 'andamento' and r.dados ->> 'evento' in ('concluiu', 'entregou'))) then
    return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'motivo', 'em_teste',
      'texto', 'Não gravei nada: a agenda automática ainda está em teste e o que você pediu mexe na agenda. Mande *descarta* e me diga de novo o resto.');
  end if;

  -- Tudo ou nada: um item que não passa desfaz o lote inteiro (as linhas continuam abertas para corrigir).
  begin
    foreach v_x in array v_oss_mat loop
      perform public.os_material_sincronizar(v_x, p_hoje);   -- as linhas espelho existem antes do fato
    end loop;

    -- O padrão novo de uma pessoa troca, UMA vez antes de entrar o lote, só o que ele realmente troca:
    --   · "vem" (seg a qui): as linhas de padrão dela (do histórico e do dono) que caem em algum desses dias; os
    --     outros dias da semana continuam como estavam;
    --   · "só de manhã", "só à tarde", "não vem" (terça): o "vem" fica; a linha indisponível do turno entra por cima
    --     (a capacidade põe o "não vem neste turno" acima do padrão "vem"). Só sai a restrição que o dono já tinha
    --     dito para os mesmos dias ("só à tarde às terças" e depois "só de manhã às terças").
    update public.agenda_disponibilidade a
       set substituida_em = now()
      from (select (r.dados ->> 'payee_id')::uuid as payee, r.dados ->> 'situacao' as situacao,
                   array(select jsonb_array_elements_text(r.dados -> 'dias_semana')::smallint) as dias
              from public.agenda_rascunho r
             where r.id = any (v_ids) and r.tipo = 'disponibilidade' and (r.dados ->> 'padrao')::boolean) n
     where a.substituida_em is null and a.dias_semana is not null and a.payee_id = n.payee
       and ((n.situacao = 'disponivel' and a.origem in ('historico', 'dono') and a.dias_semana && n.dias)
            or (n.situacao = 'indisponivel' and a.origem = 'dono' and a.situacao = 'indisponivel'
                and a.dias_semana <@ n.dias));

    -- FASE 7b: (7b P2; A4 = NOVO-agenda-55) com a pergunta dos dias fora de desligado (modo_dias), o padrão "vem" novo troca
    -- também o padrão que a própria pessoa (diarista) ou o assistente (agente) disse para os mesmos dias: a palavra mais nova
    -- vence. Desligado, só o histórico e o dono (o de antes).
    if cf.modo_dias <> 'desligado' then
      update public.agenda_disponibilidade a
         set substituida_em = now()
        from (select (r.dados ->> 'payee_id')::uuid as payee, r.dados ->> 'situacao' as situacao,
                     array(select jsonb_array_elements_text(r.dados -> 'dias_semana')::smallint) as dias
                from public.agenda_rascunho r
               where r.id = any (v_ids) and r.tipo = 'disponibilidade' and (r.dados ->> 'padrao')::boolean) n
       where a.substituida_em is null and a.dias_semana is not null and a.payee_id = n.payee
         and n.situacao = 'disponivel' and a.origem in ('diarista', 'agente') and a.dias_semana && n.dias;
    end if;
    -- FASE 7b: fim
    foreach v_x in array v_ids loop
      select * into v_r from public.agenda_rascunho where id = v_x for update;
      v_item := v_r.texto;
      case v_r.tipo
        when 'planejar' then
          perform public._agenda_aplicar_planejar(v_autor, v_r.service_order_id, v_r.dados, v_r.trecho, p_hoje);
        when 'material' then
          perform public._agenda_aplicar_material(v_autor, v_r.service_order_id, v_r.dados, v_r.trecho, p_hoje);
        when 'disponibilidade' then
          perform public._agenda_aplicar_disponibilidade(v_autor, v_r.dados, v_r.trecho, p_hoje);
        -- FASE 4: o prazo do fornecedor vai ao cadastro dele; a frase entra no "Gravado. Agora:" junto dos pedidos.
        when 'fornecedor' then
          v_f2 := v_f2 || public._agenda_aplicar_fornecedor(v_autor, v_r.dados, v_r.trecho, p_hoje);
        -- FASE 4: fim
        -- FASE 4: (P3) "a nota da Correa não é de serviço": a nota, o Pix ou a mensagem respondidos sem OS; a frase entra junto
        -- dos pedidos.
        when 'aviso' then
          v_f2 := v_f2 || public._agenda_aplicar_aviso(v_autor, v_r.dados, v_r.trecho, v_r.canal, p_hoje);
        -- FASE 4: fim
        else
          -- FASE 2: o pedido à agenda (marcar, aplicar/decidir, desfazer, andamento) pelas funções do motor.
          v_f2_item := public._agenda_aplicar_pedido(v_autor, v_r.tipo, v_r.service_order_id, v_r.dados, v_r.trecho, v_r.canal,
                                                     p_hoje, v_agora);
          if nullif(btrim(coalesce(v_f2_item, '')), '') is not null then
            v_f2 := v_f2 || v_f2_item;
          end if;
      end case;
      update public.agenda_rascunho set estado = 'gravado', gravado_em = now() where id = v_x;
      v_n := v_n + 1;
    end loop;

    foreach v_x in array v_oss_mat loop
      perform public.os_material_sincronizar(v_x, p_hoje);
    end loop;
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    -- FASE 3: a porta recusou concluir ou entregar (o período fechado no financeiro): a frase dela.
    if v_estado = 'P0096' then
      return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
        'texto', 'Não gravei nada. ' || btrim(v_msg));
    end if;
    -- FASE 2: a agenda recusou um pedido (a proposta ficou velha, a decisão mudou, não coube, já começou…).
    if v_estado = 'P0097' then
      return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
        'texto', format('Não gravei nada. A agenda mudou desde a releitura: %s. Me peça de novo.', rtrim(btrim(v_msg), '.')));
    end if;
    return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
      'texto', format('Não gravei nada: %s (%s). Corrija o que estiver errado, ou mande *descarta*, e depois *grava* de novo.',
                      case when v_estado = 'P0001' then v_msg else 'o banco recusou um item' end,
                      coalesce(v_item, 'o lote')));
  end;

  -- "Gravado. Agora:" — uma linha por OS (o estado da prontidão) e por pessoa, na ordem em que o dono falou.
  for v_g in
    select r.dados ->> 'grupo' as grupo, min((r.dados ->> 'ordem')::int) as ordem,
           (array_agg(r.service_order_id order by (r.dados ->> 'ordem')::int))[1] as os,
           (array_agg(r.dados order by (r.dados ->> 'ordem')::int))[1] as d,
           string_agg(r.dados ->> 'frase', '; ' order by (r.dados ->> 'ordem')::int) as frases
      from public.agenda_rascunho r
     where r.id = any (v_ids) and r.tipo in ('planejar', 'material', 'disponibilidade')   -- FASE 2: os pedidos vêm em v_f2
     group by r.dados ->> 'grupo'
     order by 2
  loop
    if v_g.os is not null then
      v_p := public.os_prontidao(v_g.os, p_hoje);
      select count(*) into v_nome from public.os_carteira(p_hoje) k where k.cliente_curto = v_p ->> 'cliente_curto';
      v_linhas := v_linhas || ('• ' || public._agenda_rotulo(jsonb_build_object(
                                 'curto', v_p ->> 'cliente_curto', 'numero', v_p ->> 'numero',
                                 'eh_orc', (v_p ->> 'eh_orcamento')::boolean, 'n_nome', v_nome))
                               || ': ' || (v_p ->> 'estado_texto') || '.');
    else
      v_linhas := v_linhas || ('• ' || (v_g.d ->> 'rotulo_grupo') || ': ' || v_g.frases || '.');
    end if;
  end loop;

  -- FASE 7: (7a P10, spec §6.4) a peça que voltou a faltar ("Cerbo GX de Nelson voltou a faltar: o 'compre até' reabriu
  -- (comprando hoje, chega qua 11/11).") entra no "Gravado. Agora:" junto dos pedidos — só com o "compre até" do gestor ligado
  -- (_agenda_aplicar_material só escreve a frase assim); sem isso, nada muda
  v_f2 := v_f2 || coalesce(string_to_array(nullif(current_setting('agenda.material_reabriu', true), ''), E'\n'), '{}'::text[]);
  perform set_config('agenda.material_reabriu', '', true);
  -- FASE 7: fim
  return jsonb_build_object('ok', true, 'gravados', v_n, 'expirados', v_exp,
    'texto', 'Gravado. Agora:' || E'\n' || array_to_string(v_linhas || array(select '• ' || x from unnest(v_f2) x), E'\n')
             || case when v_exp > 0 then E'\n' || format('(A releitura de %s tinha expirado e não foi gravada.)', public._dia_curto(v_exp_dia))
                     else '' end);
end;
$function$;

comment on function public.agenda_rascunho_gravar(uuid, date) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): o *grava* do dono — numa transação, tudo ou nada: marca expirado o que passou da validade; sincroniza o material das OS do lote; troca UMA vez, das pessoas com padrão novo, só os padrões que o "vem" cobre; aplica primeiro os fatos (_agenda_aplicar_planejar/_material/_disponibilidade; Fase 4: _agenda_aplicar_fornecedor, o prazo dito de um fornecedor, que não depende do modo da agenda; Fase 4, P3: _agenda_aplicar_aviso, o "não é de serviço" da nota, do Pix ou da mensagem), depois os pedidos à agenda da Fase 2 na ordem andamento, marcar, aplicar/decidir e desfazer (_agenda_aplicar_pedido: agenda_registrar_dia, a porta, agenda_marcar_os, agenda_aplicar, agenda_decidir, agenda_desfazer, com p_agora = a hora do *grava*); sincroniza de novo. Com modo_proposta fora de ligado, o lote com pedido à agenda não grava (Fase 3: menos concluir e entregar, que gravam em todos os modos; a recusa da porta = "Não gravei nada. Não concluí: …" e o lote volta). Devolve {ok, gravados, expirados, texto "Gravado. Agora:" + uma linha por OS (estado da prontidão), por pessoa e por pedido (a frase da agenda)}; item que não passa: {ok:false, texto "Não gravei nada: …" ou "Não gravei nada. A agenda mudou desde a releitura: …. Me peça de novo.", erro} e nada muda. Chamada só pelo comando sem IA "grava", nunca por ferramenta do modelo. FASE 7 (7a P10, spec §6.4): a frase da peça que voltou a faltar ("Cerbo GX de Nelson voltou a faltar: o ''compre até'' reabriu (comprando hoje, chega qua 11/11).", que _agenda_aplicar_material junta em agenda.material_reabriu só com o "compre até" do gestor ligado) entra no "Gravado. Agora:" junto dos pedidos; a variável começa vazia em cada *grava*. Sem ela, a de antes, byte a byte. Fase 7b (P2; A4 = NOVO-agenda-55): com modo_dias fora de desligado, a troca única do padrão "vem" novo pega também os padrões que a própria pessoa (diarista) ou o assistente (agente) disse para os mesmos dias — a palavra mais nova vence. Desligado, a de antes, byte a byte.';

-- agenda_rascunho_planejar (de 20261028100500_agenda_fase5_leituras.sql)
create or replace function public.agenda_rascunho_planejar(p_autor uuid, p_canal text, p_os text, p_dados jsonb,
                                                           p_trecho text, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  d        jsonb := coalesce(p_dados, '{}'::jsonb);
  c_campos constant text[] := array['dias', 'com_quem', 'dono', 'precisa_ate', 'bem_fora', 'bem_livre_em', 'nao_antes_de',
                                    'nao_antes_motivo', 'escopo_em_aberto', 'escopo_decidido', 'congelar_ate', 'revisar_em',
                                    'prioridade', 'sem_material', 'aceitar_sugestao', 'limpar',
                                    'adiantavel_patio'];   -- FASE 2: adiantavel_patio
  -- O que o dono desfaz ("pode voltar", "tira da espera", "não tem mais data mínima", "o cliente não tem mais prazo",
  -- "o escopo está resolvido"): o campo volta a vazio.
  c_limpar constant text[] := array['espera', 'nao_antes', 'prazo', 'escopo', 'patio'];   -- FASE 2: patio
  v_limpar text[] := '{}';
  v_k      text;
  v_ro     jsonb;
  v_os     uuid;
  v_out    jsonb := '{}'::jsonb;
  v_n      numeric;
  v_sug    jsonb;
  v_x      jsonb;
  v_rp     jsonb;
  v_turnos text;
  v_equipe jsonb := '[]'::jsonb;
  v_dt     jsonb;
  v_dt2    jsonb;
  v_bem    text;
  v_txt    text;
  v_dias_os numeric;   -- FASE 2
  -- FASE 5: o que foi dito ao cliente e como o serviço é dito a ele
  c_serv_max constant int := 40;   -- estrutural: o serviço aparece duas vezes no aviso de atraso (que tem de caber em 400)
  v_prom   text;
  v_serv   text;
  v_dtp    jsonb;
  -- FASE 5: fim
  -- FASE 7b: (7b P2; R4.3(b)) a dupla dita pelo planejar
  v_7b_dupla text;
  v_7b_meios_txt text;
  v_7b_tem_meios boolean := false;
  v_7b_meios int;
  v_7b_tec   text[];
  v_7b_aviso text;
  -- FASE 7b: fim
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_rascunho_planejar: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;
  -- A agenda desligada (agenda_config.modo_leitura) não anota: sem o *grava* ligado, o rascunho não teria saída.
  if (public._agenda_cfg()).modo_leitura = 'desligado' then
    return public._agenda_recusa('A agenda de produção está desligada agora: não anotei nada.', 'desligada');
  end if;
  if jsonb_typeof(d) <> 'object' then
    raise exception 'agenda_rascunho_planejar: p_dados tem de ser um objeto' using errcode = '22023';
  end if;
  -- FASE 5: prometido (a data como o dono disse ao cliente) e servico_cliente (como o cliente chama o serviço) saem de d
  -- antes da conferência dos campos; entram no rascunho no fim (v_out), conferidos.
  v_prom := nullif(btrim(coalesce(d ->> 'prometido', '')), '');
  v_serv := nullif(btrim(regexp_replace(coalesce(d ->> 'servico_cliente', ''), '\s+', ' ', 'g')), '');
  d := d - 'prometido' - 'servico_cliente';
  -- FASE 5: fim
  -- FASE 7b: (7b P2) a dupla (nao | todos | inicio | fim) e os meios-dias dela saem de d antes da conferência dos campos; entram no
  -- rascunho no fim (v_out), conferidos
  v_7b_dupla := nullif(lower(btrim(coalesce(d ->> 'dupla', ''))), '');
  v_7b_tem_meios := d ? 'dupla_meios' and jsonb_typeof(d -> 'dupla_meios') <> 'null';
  v_7b_meios_txt := d ->> 'dupla_meios';
  d := d - 'dupla' - 'dupla_meios';
  -- FASE 7b: fim
  select k into v_k from jsonb_object_keys(d) k where k <> all (c_campos) order by k limit 1;
  if v_k is not null then
    raise exception 'agenda_rascunho_planejar: o campo "%" não existe', v_k using errcode = '22023';
  end if;
  d := jsonb_strip_nulls(d);
  if d ? 'limpar' then
    if jsonb_typeof(d -> 'limpar') <> 'array' then
      raise exception 'agenda_rascunho_planejar: limpar tem de ser uma lista (espera, nao_antes, prazo ou escopo)' using errcode = '22023';
    end if;
    v_limpar := array(select distinct x from jsonb_array_elements_text(d -> 'limpar') x order by 1);
    select x into v_k from unnest(v_limpar) x where x <> all (c_limpar) order by 1 limit 1;
    if v_k is not null then
      raise exception 'agenda_rascunho_planejar: limpar "%" não existe (espera, nao_antes, prazo ou escopo)', v_k using errcode = '22023';
    end if;
    -- Pôr e tirar a mesma coisa na mesma chamada é erro de quem chamou.
    if ('espera' = any (v_limpar) and (d ? 'congelar_ate' or d ? 'revisar_em'))
       or ('nao_antes' = any (v_limpar) and (d ? 'nao_antes_de' or d ? 'nao_antes_motivo'))
       or ('prazo' = any (v_limpar) and d ? 'precisa_ate')
       or ('escopo' = any (v_limpar) and d ? 'escopo_em_aberto')
       or ('patio' = any (v_limpar) and d ? 'adiantavel_patio') then   -- FASE 2
      raise exception 'agenda_rascunho_planejar: limpar e o mesmo campo na mesma chamada' using errcode = '22023';
    end if;
  end if;
  if nullif(btrim(p_trecho), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras o que mudou nesse serviço.', 'sem_trecho');
  end if;

  v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
  if v_ro ->> 'status' <> 'ok' then
    return public._agenda_recusa_da_os(v_ro);
  end if;
  v_os := (v_ro ->> 'id')::uuid;

  -- Dias: o número dito (no trecho) ou "aceito a sua estimativa" (a sugestão, com fonte 'aceita').
  if d ? 'dias' then
    begin
      v_n := (d ->> 'dias')::numeric;
    exception when others then
      v_n := null;
    end;
    if v_n is null or v_n <= 0 or v_n > 60 or v_n * 2 <> trunc(v_n * 2) then
      return public._agenda_recusa('Quantos dias? Diga em dias ou meio dia (por exemplo, "2 dias" ou "um dia e meio").', 'dias_invalido');
    end if;
    if not public._agenda_trecho_tem_numero(p_trecho, v_n) then
      return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo quantos dias.', public._agenda_dias(v_n)),
                                   'fora_do_trecho');
    end if;
    v_out := v_out || jsonb_build_object('dias', trim_scale(v_n), 'estimativa_fonte', 'dono');
  elsif coalesce((d ->> 'aceitar_sugestao')::boolean, false) then
    v_sug := public.os_duracao_sugerida(v_os);
    if coalesce((v_sug ->> 'sem_base')::boolean, false) or v_sug ->> 'sugerida' is null then
      return public._agenda_recusa('O orçamento não dá base para eu estimar: quantos dias?', 'sem_base');
    end if;
    v_out := v_out || jsonb_build_object('dias', (v_sug ->> 'sugerida')::numeric, 'estimativa_fonte', 'aceita');
  end if;

  -- Quem vai, por turno ("dia" quando não disse).
  if d ? 'com_quem' then
    if jsonb_typeof(d -> 'com_quem') <> 'array' then
      raise exception 'agenda_rascunho_planejar: com_quem tem de ser uma lista' using errcode = '22023';
    end if;
    for v_x in select e from jsonb_array_elements(d -> 'com_quem') with ordinality t(e, o) order by o loop
      if jsonb_typeof(v_x) = 'string' then
        v_x := jsonb_build_object('pessoa', v_x #>> '{}');
      end if;
      v_turnos := coalesce(nullif(btrim(v_x ->> 'turnos'), ''), 'dia');
      if v_turnos not in ('dia', 'manha', 'tarde') then
        raise exception 'agenda_rascunho_planejar: turnos "%" inválido (dia, manha ou tarde)', v_turnos using errcode = '22023';
      end if;
      v_rp := public.agenda_resolver_pessoa(v_x ->> 'pessoa', v_autor, p_hoje);
      if v_rp ->> 'status' <> 'ok' then
        return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status'),
          coalesce((select jsonb_agg(e ->> 'nome' order by o)
                      from jsonb_array_elements(coalesce(v_rp -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
      end if;
      v_equipe := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_equipe) with ordinality t(e, o)
                             where e ->> 'payee_id' <> v_rp ->> 'payee_id'), '[]'::jsonb)
                  || jsonb_build_array(jsonb_build_object('payee_id', v_rp ->> 'payee_id', 'nome', v_rp ->> 'nome_curto',
                                                          'eh_dono', coalesce((v_rp ->> 'eh_dono')::boolean, false),
                                                          'turnos', v_turnos));
    end loop;
    v_out := v_out || jsonb_build_object('equipe', v_equipe);
  end if;

  if d ? 'dono' then
    if d ->> 'dono' not in ('abre_e_fecha', 'sempre', 'nunca') then
      raise exception 'agenda_rascunho_planejar: dono "%" inválido (abre_e_fecha, sempre ou nunca)', d ->> 'dono' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('dono', d ->> 'dono');
  end if;

  if d ? 'precisa_ate' then
    v_dt := public._agenda_data_conferida(d ->> 'precisa_ate', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. Até quando o cliente precisa?', btrim(d ->> 'precisa_ate')), 'data_passada');
    end if;
    v_out := v_out || jsonb_build_object('precisa_ate', v_dt ->> 'ate');
  end if;

  -- O bem fora: "fora de 26 a 30/10", "fora até dia 3" (inclusive) ou "só fica livre dia 3" (livre nesse dia).
  if d ? 'bem_fora' then
    v_dt := public._agenda_data_conferida(d ->> 'bem_fora', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. Até quando o bem fica fora?', btrim(d ->> 'bem_fora')), 'data_passada');
    end if;
    v_out := v_out || jsonb_build_object('bem', jsonb_build_object(
      'modo', 'fora', 'de', greatest((v_dt ->> 'de')::date, p_hoje), 'ate', (v_dt ->> 'ate')::date,
      'livre_em', (v_dt ->> 'ate')::date + 1));
  end if;
  if d ? 'bem_livre_em' then
    v_dt := public._agenda_data_conferida(d ->> 'bem_livre_em', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    v_out := v_out || jsonb_build_object('bem', case
      when (v_dt ->> 'de')::date <= p_hoje then jsonb_build_object('modo', 'livre')
      else jsonb_build_object('modo', 'livre_em', 'de', p_hoje, 'ate', (v_dt ->> 'de')::date - 1, 'livre_em', (v_dt ->> 'de')::date) end);
  end if;

  if d ? 'nao_antes_de' then
    v_dt := public._agenda_data_conferida(d ->> 'nao_antes_de', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    v_out := v_out || jsonb_build_object('nao_antes_de', v_dt ->> 'de',
      'nao_antes_motivo', coalesce(left(nullif(btrim(d ->> 'nao_antes_motivo'), ''), 120), 'você disse'));
  elsif d ? 'nao_antes_motivo' then
    return public._agenda_recusa('Não antes de que dia?', 'sem_data');
  end if;

  if d ? 'escopo_em_aberto' then
    v_out := v_out || jsonb_build_object('escopo_em_aberto', nullif(left(btrim(d ->> 'escopo_em_aberto'), 160), ''));
  end if;
  if d ? 'escopo_decidido' then
    v_out := v_out || jsonb_build_object('escopo_decidido', nullif(left(btrim(d ->> 'escopo_decidido'), 160), ''));
    if not d ? 'escopo_em_aberto' then
      -- O que o dono decidiu fecha a pergunta em aberto.
      v_out := v_out || jsonb_build_object('escopo_em_aberto', null);
    end if;
  end if;

  if d ? 'congelar_ate' then
    v_dt := public._agenda_data_conferida(d ->> 'congelar_ate', p_trecho, p_hoje, 'futuro');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if d ? 'revisar_em' then
      v_dt2 := public._agenda_data_conferida(d ->> 'revisar_em', p_trecho, p_hoje, 'futuro');
      if not (v_dt2 ->> 'ok')::boolean then return v_dt2; end if;
    else
      v_dt2 := v_dt;   -- sem data para rever: revê no dia em que a espera acaba
    end if;
    v_out := v_out || jsonb_build_object('congelada_ate', v_dt ->> 'ate', 'revisar_em', v_dt2 ->> 'de');
  elsif d ? 'revisar_em' then
    return public._agenda_recusa('Em espera até quando?', 'sem_data');
  end if;

  if d ? 'prioridade' then
    begin
      v_n := (d ->> 'prioridade')::numeric;
    exception when others then
      v_n := null;
    end;
    if v_n is null or v_n not in (1, 2, 3) then
      raise exception 'agenda_rascunho_planejar: prioridade "%" inválida (1, 2 ou 3)', d ->> 'prioridade' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('prioridade', v_n::int);
  end if;

  if d ? 'sem_material' then
    v_out := v_out || jsonb_build_object('sem_material', (d ->> 'sem_material')::boolean);
  end if;

  -- FASE 2: quanto do serviço dá para adiantar no pátio sem o bem — o número tem de estar no que o dono disse e não
  -- passa dos dias do serviço (os ditos agora, ou os que já estavam).
  if d ? 'adiantavel_patio' then
    begin
      v_n := (d ->> 'adiantavel_patio')::numeric;
    exception when others then
      v_n := null;
    end;
    if v_n is null or v_n <= 0 or v_n > 60 or v_n * 2 <> trunc(v_n * 2) then
      return public._agenda_recusa('Quanto dá para adiantar no pátio? Diga em dias ou meio dia (por exemplo, "um dia").', 'patio_invalido');
    end if;
    if not public._agenda_trecho_tem_numero(p_trecho, v_n) then
      return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo quanto dá para adiantar no pátio.',
                                          public._agenda_dias(v_n)), 'fora_do_trecho');
    end if;
    v_dias_os := coalesce((v_out ->> 'dias')::numeric,
                          (select pl.dias from public.os_planejamento pl where pl.service_order_id = v_os));
    if v_dias_os is not null and v_n > v_dias_os then
      return public._agenda_recusa(format('O serviço todo é de %s: no pátio dá para adiantar no máximo isso. Quanto dá?',
                                          public._agenda_dias(v_dias_os)), 'patio_maior');
    end if;
    v_out := v_out || jsonb_build_object('adiantavel_patio', trim_scale(v_n));
  end if;

  -- O que o dono desfez: o campo vai como nulo (o *grava* grava vazio; a correção na mesma releitura também apaga).
  if 'espera' = any (v_limpar) then
    v_out := v_out || jsonb_build_object('congelada_ate', null, 'revisar_em', null);
  end if;
  if 'nao_antes' = any (v_limpar) then
    v_out := v_out || jsonb_build_object('nao_antes_de', null, 'nao_antes_motivo', null);
  end if;
  if 'prazo' = any (v_limpar) then
    v_out := v_out || jsonb_build_object('precisa_ate', null);
  end if;
  if 'escopo' = any (v_limpar) then
    v_out := v_out || jsonb_build_object('escopo_em_aberto', null);
  end if;
  if 'patio' = any (v_limpar) then   -- FASE 2
    v_out := v_out || jsonb_build_object('adiantavel_patio', null);
  end if;

  -- FASE 5: o que o dono disse ao cliente: a data conferida no trecho e entendida pelo banco (agenda_data_dita: "dia 3" é
  -- firme; "entre 4 e 8/11" e "semana que vem" são faixa), nunca no passado; o serviço como o cliente diz (3 a c_serv_max
  -- caracteres, sem valor, pagamento, número de OS nem link).
  if v_prom is not null then
    v_dtp := public._agenda_data_conferida(v_prom, p_trecho, p_hoje, 'futuro');
    if not (v_dtp ->> 'ok')::boolean then return v_dtp; end if;
    if (v_dtp ->> 'ate')::date < p_hoje then
      return public._agenda_recusa(format('"%s" já passou. Que dia você disse ao cliente?', v_prom), 'data_passada');
    end if;
    v_out := v_out || jsonb_build_object('prometido', jsonb_build_object(
      'tipo', case when v_dtp ->> 'de' = v_dtp ->> 'ate' then 'firme' else 'faixa' end,
      'de', v_dtp ->> 'de', 'ate', v_dtp ->> 'ate', 'dito', left(v_prom, 60)));
  end if;
  if v_serv is not null then
    if char_length(v_serv) < 3 or char_length(v_serv) > c_serv_max then
      return public._agenda_recusa(format('Diga em poucas palavras como o cliente chama o serviço (até %s letras), por exemplo "a instalação do compressor".',
                                          c_serv_max), 'servico_longo');
    end if;
    if public._agenda_cliente_texto_proibido(v_serv) is not null then
      return public._agenda_recusa('Como o cliente chama o serviço não leva valor, pagamento, número de OS nem link: diga só o serviço ("a troca das baterias").',
                                   'servico_proibido');
    end if;
    v_out := v_out || jsonb_build_object('servico_cliente', v_serv);
  end if;
  -- FASE 5: fim
  -- FASE 7b: (7b P2; R4.3(b), §6.6) a dupla dita: nao = 1 pessoa (sem a inferência); todos = o tempo todo; inicio/fim = nos
  -- dupla_meios primeiros ou últimos meios-dias (1 a 20, no trecho; "no primeiro dia" = 2 meios-dias, com "dia" no trecho). Com
  -- modo_dupla desligado, inicio/fim é recusado (a 7a não enxerga a dupla numa parte: o motor mandaria 1 pessoa num serviço de
  -- segurança e a releitura teria prometido a dupla); todos e nao valem em todo modo, como a palavra da 7a. Com menos técnicos
  -- na grade do que a dupla pede, a releitura avisa que a OS espera (a classe dupla de _agenda_classe_da_os).
  if v_7b_dupla is not null or v_7b_tem_meios then
    if v_7b_dupla is null or v_7b_dupla not in ('nao', 'todos', 'inicio', 'fim') then
      raise exception 'agenda_rascunho_planejar: dupla "%" inválida (nao, todos, inicio ou fim)', coalesce(v_7b_dupla, '')
        using errcode = '22023';
    end if;
    if v_7b_dupla in ('inicio', 'fim') then
      if (public._agenda_cfg()).modo_dupla = 'desligado' then
        return public._agenda_recusa(format('A dupla só numa parte do serviço ainda não está ligada. Diga *%s com dupla* (o tempo todo) ou ''vai com um só''.',
                                            v_ro ->> 'cliente_curto'), 'dupla_parte_desligada');
      end if;
      begin
        v_7b_meios := v_7b_meios_txt::int;
      exception when others then
        v_7b_meios := null;
      end;
      if v_7b_meios is null or v_7b_meios < 1 or v_7b_meios > 20 then
        return public._agenda_recusa('Em quantos meios-dias vai a dupla? (por exemplo, "dois no primeiro dia" = 2 meios-dias)', 'dupla_meios');
      end if;
      if not (public._agenda_trecho_tem_numero(p_trecho, v_7b_meios)
              or (public._agenda_normal(p_trecho) ~ '\mdias?\M'
                  and (v_7b_meios = 2 or (v_7b_meios % 2 = 0 and public._agenda_trecho_tem_numero(p_trecho, v_7b_meios / 2))))) then
        return public._agenda_recusa(format('Não achei "%s" no que você disse; me diga de novo em quantos meios-dias vai a dupla.', v_7b_meios),
                                     'fora_do_trecho');
      end if;
    elsif v_7b_tem_meios then
      raise exception 'agenda_rascunho_planejar: dupla_meios só com dupla inicio ou fim' using errcode = '22023';
    end if;
    if v_7b_dupla <> 'nao' then
      v_7b_tec := public._agenda_tecnicos_da_grade(p_hoje);
      if cardinality(v_7b_tec) < greatest((public._agenda_cfg()).equipe_sugerida, 2) then
        v_7b_aviso := format('Hoje %s: até você chamar alguém e me dizer os dias, eu não marco %s',
                             public._agenda_tecnicos_frase(v_7b_tec), v_ro ->> 'cliente_curto');
      end if;
    end if;
    v_out := v_out || jsonb_build_object('dupla', v_7b_dupla, 'dupla_meios', v_7b_meios, 'dupla_aviso', v_7b_aviso);
  end if;
  -- FASE 7b: fim
  if v_out = '{}'::jsonb then
    return public._agenda_recusa('O que mudou nesse serviço? (quantos dias, quem vai, até quando o cliente precisa…)', 'nada');
  end if;

  select case when public._agenda_normal(coalesce(vs.asset_type, vs.name)) ~ 'motorhome|motor home|trailer'
              then 'o motorhome' else 'o barco' end
    into v_bem
    from public.service_orders so left join public.vessels vs on vs.id = so.vessel_id
   where so.id = v_os;

  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'planejar', 'planejar:' || v_os::text, v_os,
                                          public._agenda_os_do_rascunho(v_ro) || jsonb_build_object('bem_nome', v_bem) || v_out,
                                          p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): o que o dono disse do serviço vira RASCUNHO (nada em os_planejamento). p_dados: dias, com_quem [{pessoa, turnos dia|manha|tarde}], dono (abre_e_fecha|sempre|nunca), precisa_ate, bem_fora, bem_livre_em, nao_antes_de + nao_antes_motivo, escopo_em_aberto, escopo_decidido, congelar_ate + revisar_em, prioridade 1–3, sem_material, aceitar_sugestao, adiantavel_patio (dias que dá para adiantar no pátio sem o bem; Fase 2), limpar (espera, nao_antes, prazo, escopo, patio). OS e pessoas resolvidas no banco (ambíguo/não achado = pergunta, nada no rascunho); dias, dias no pátio e datas têm de estar no trecho; datas por agenda_data_dita. Devolve {ok, item, releitura} ou {ok:false, pergunta, opcoes}. Fase 5 (P5): prometido (a data que o cliente OUVIU, como o dono disse: "dia 3" firme, "entre 4 e 8/11" ou "semana que vem" faixa; conferida no trecho, nunca no passado) e servico_cliente (como o cliente chama o serviço, 3 a 40 caracteres, sem valor, número de OS nem link). Fase 7b (P2; R4.3(b), §6.6): a chave dupla — nao (1 pessoa, sem a inferência), todos (o tempo todo), inicio ou fim (com dupla_meios 1 a 20 no trecho; "no primeiro dia" = 2 meios-dias, com "dia" no trecho); dupla_meios sem inicio/fim, ou dupla fora da lista, é erro de quem chamou. Com modo_dupla desligado, inicio/fim volta a frase "A dupla só numa parte do serviço ainda não está ligada. Diga *Lenine com dupla* (o tempo todo) ou ''vai com um só''." (todos e nao valem em todo modo). Com menos técnicos na grade do que a dupla pede, a releitura avisa: "Hoje só Alex está na equipe: até você chamar alguém e me dizer os dias, eu não marco Lenine."';

-- _agenda_aplicar_planejar (de 20261028100500_agenda_fase5_leituras.sql)
create or replace function public._agenda_aplicar_planejar(p_autor uuid, p_os uuid, p_dados jsonb, p_trecho text, p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  d           jsonb := coalesce(p_dados, '{}'::jsonb);
  v_old       public.os_planejamento%rowtype;
  v_new       public.os_planejamento%rowtype;
  v_eq_antes  jsonb;
  v_eq_depois jsonb;
  v_antes     jsonb := '{}'::jsonb;
  v_depois    jsonb := '{}'::jsonb;
  v_k         text;
  -- FASE 5: o prometido de antes e o gravado
  v_prom_antes jsonb;
  v_prom      jsonb;
  -- FASE 5: fim
begin
  if not exists (select 1 from public.service_orders where id = p_os) then
    raise exception 'o serviço % não existe mais', coalesce(d ->> 'numero', p_os::text) using errcode = 'P0001';
  end if;
  insert into public.os_planejamento (service_order_id) values (p_os) on conflict (service_order_id) do nothing;
  -- FASE 5: o que o dono disse ao cliente vira o prometido (fonte dono; a 1ª promessa fica em prometido_original_ate; o
  -- histórico ganha a linha própria, pelo _agenda_cliente_gravar_prometido). Gravado antes de ler a linha: o diff abaixo é
  -- só do resto. Só o prometido na linha = nada mais a gravar.
  if jsonb_typeof(d -> 'prometido') = 'object' then
    select jsonb_build_object('tipo', pl.prometido_tipo, 'de', pl.prometido_de, 'ate', pl.prometido_ate, 'fonte', pl.prometido_fonte)
      into v_prom_antes from public.os_planejamento pl where pl.service_order_id = p_os;
    v_prom := public._agenda_cliente_gravar_prometido(p_os, d #>> '{prometido,tipo}', (d #>> '{prometido,de}')::date,
                (d #>> '{prometido,ate}')::date, 'dono', null,
                coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now()), p_trecho);
    -- FASE 7b: (7b P2) com a dupla na mesma linha, o resto da linha ainda grava (não volta só com o prometido)
    if not (d ? 'dupla') then
    -- FASE 7b: fim
    if not (d ?| array['dias', 'equipe', 'dono', 'precisa_ate', 'bem', 'nao_antes_de', 'escopo_em_aberto', 'escopo_decidido',
                       'congelada_ate', 'prioridade', 'sem_material', 'adiantavel_patio', 'servico_cliente']) then
      return jsonb_build_object('antes', jsonb_build_object('prometido', v_prom_antes), 'depois', jsonb_build_object('prometido', v_prom));
    end if;
    -- FASE 7b: (7b P2) fecha o "com a dupla na mesma linha"
    end if;
    -- FASE 7b: fim
  end if;
  -- FASE 5: fim
  select * into v_old from public.os_planejamento where service_order_id = p_os for update;
  v_new := v_old;
  -- FASE 7b: (7b P2) a dupla dita (o histórico abaixo guarda o antes e o depois): nao = 1 pessoa (sem a inferência), todos, ou
  -- inicio/fim com os meios-dias
  if d ? 'dupla' then
    v_new.dupla_dita := d ->> 'dupla';
    v_new.dupla_meios := case when d ->> 'dupla' in ('inicio', 'fim') then (d ->> 'dupla_meios')::smallint end;
    v_new.dupla_motivo := left('você disse: ' || public._agenda_rascunho_frase('planejar',
                                 jsonb_build_object('dupla', d ->> 'dupla', 'dupla_meios', d -> 'dupla_meios')), 80);
    v_new.dupla_em := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  end if;
  -- FASE 7b: fim

  if d ? 'dias' then
    v_new.dias := (d ->> 'dias')::numeric;
    v_new.estimativa_fonte := d ->> 'estimativa_fonte';
    v_new.estimativa_em := now();
  end if;
  if d ? 'dono' then v_new.dono_presenca := d ->> 'dono'; end if;
  if d ? 'precisa_ate' then v_new.precisa_ate := (d ->> 'precisa_ate')::date; end if;
  if d ? 'bem' then
    v_new.bem_indisponivel := case when d #>> '{bem,modo}' = 'livre' then '{}'::datemultirange
                                   else datemultirange(daterange((d #>> '{bem,de}')::date, (d #>> '{bem,livre_em}')::date, '[)')) end;
  end if;
  if d ? 'nao_antes_de' then
    v_new.nao_antes_de := (d ->> 'nao_antes_de')::date;
    v_new.nao_antes_motivo := d ->> 'nao_antes_motivo';
  end if;
  if d ? 'escopo_em_aberto' then v_new.escopo_em_aberto := d ->> 'escopo_em_aberto'; end if;
  if d ? 'escopo_decidido' then v_new.escopo_decidido := d ->> 'escopo_decidido'; end if;
  if d ? 'congelada_ate' then
    v_new.congelada_ate := (d ->> 'congelada_ate')::date;
    v_new.revisar_em := (d ->> 'revisar_em')::date;
  end if;
  if d ? 'prioridade' then v_new.prioridade_manual := (d ->> 'prioridade')::smallint; end if;
  if d ? 'sem_material' then
    v_new.material_conferido_em := case when (d ->> 'sem_material')::boolean then now() end;
  end if;
  -- FASE 2: o que dá para adiantar no pátio (null = o dono tirou).
  if d ? 'adiantavel_patio' then
    v_new.adiantavel_patio_dias := (d ->> 'adiantavel_patio')::numeric;
  end if;
  -- FASE 5: como o serviço é dito ao cliente
  if d ? 'servico_cliente' then
    v_new.servico_cliente := d ->> 'servico_cliente';
  end if;
  -- FASE 5: fim

  select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'turnos', e.turnos) order by e.payee_id), '[]'::jsonb)
    into v_eq_antes
    from public.os_planejamento_equipe e where e.service_order_id = p_os;
  if d ? 'equipe' then
    delete from public.os_planejamento_equipe where service_order_id = p_os;
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos)
    select p_os, (e ->> 'payee_id')::uuid, e ->> 'turnos' from jsonb_array_elements(d -> 'equipe') e;
    select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'turnos', e.turnos) order by e.payee_id), '[]'::jsonb)
      into v_eq_depois
      from public.os_planejamento_equipe e where e.service_order_id = p_os;
  else
    v_eq_depois := v_eq_antes;
  end if;

  -- O histórico guarda só o que mudou: {campo: antes} e {campo: depois}.
  for v_k in select key from jsonb_each(to_jsonb(v_new) - array['historico', 'atualizado_em', 'atualizado_por', 'trecho', 'estimativa_em'])
  loop
    if to_jsonb(v_old) -> v_k is distinct from to_jsonb(v_new) -> v_k then
      v_antes := v_antes || jsonb_build_object(v_k, to_jsonb(v_old) -> v_k);
      v_depois := v_depois || jsonb_build_object(v_k, to_jsonb(v_new) -> v_k);
    end if;
  end loop;
  if v_eq_antes is distinct from v_eq_depois then
    v_antes := v_antes || jsonb_build_object('equipe', v_eq_antes);
    v_depois := v_depois || jsonb_build_object('equipe', v_eq_depois);
  end if;

  update public.os_planejamento
     set dias = v_new.dias, estimativa_fonte = v_new.estimativa_fonte, estimativa_em = v_new.estimativa_em,
         dono_presenca = v_new.dono_presenca, precisa_ate = v_new.precisa_ate, bem_indisponivel = v_new.bem_indisponivel,
         nao_antes_de = v_new.nao_antes_de, nao_antes_motivo = v_new.nao_antes_motivo,
         escopo_em_aberto = v_new.escopo_em_aberto, escopo_decidido = v_new.escopo_decidido,
         congelada_ate = v_new.congelada_ate, revisar_em = v_new.revisar_em, prioridade_manual = v_new.prioridade_manual,
         material_conferido_em = v_new.material_conferido_em,
         adiantavel_patio_dias = v_new.adiantavel_patio_dias,   -- FASE 2
         -- FASE 5: como o serviço é dito ao cliente
         servico_cliente = v_new.servico_cliente,
         -- FASE 5: fim
         trecho = public._agenda_corta(p_trecho, 500),
         historico = public._os_material_historico(v_old.historico, jsonb_build_object(
           'em', p_hoje, 'autor', p_autor, 'trecho', public._agenda_corta(p_trecho, 500), 'antes', v_antes, 'depois', v_depois)),
         atualizado_em = now(), atualizado_por = p_autor
   where service_order_id = p_os;
  -- FASE 7b: (7b P2) a dupla dita vai para a linha (o update acima é o de antes, sem as colunas da dupla)
  if d ? 'dupla' then
    update public.os_planejamento
       set dupla_dita = v_new.dupla_dita, dupla_meios = v_new.dupla_meios, dupla_motivo = v_new.dupla_motivo,
           dupla_em = v_new.dupla_em
     where service_order_id = p_os;
  end if;
  -- FASE 7b: fim
  return jsonb_build_object('antes', v_antes, 'depois', v_depois);
end;
$function$;

comment on function public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): grava em os_planejamento (e os_planejamento_equipe) uma linha de rascunho planejar — só os campos ditos (Fase 2: adiantavel_patio → adiantavel_patio_dias); a equipe dita substitui a anterior. Histórico {em, autor, trecho, antes, depois} com só o que mudou (os 20 mais novos). Só pelo agenda_rascunho_gravar; só service_role. Fase 5 (P5): prometido → os_planejamento.prometido_* pelo _agenda_cliente_gravar_prometido (fonte dono; o original só na 1ª vez; linha própria no histórico); servico_cliente → os_planejamento.servico_cliente. Fase 7b (P2): a dupla dita → os_planejamento.dupla_dita (nao | todos | inicio | fim), dupla_meios (só inicio/fim), dupla_motivo ("você disse: vai em dupla nos 2 primeiros meios-dias") e dupla_em (a hora do *grava*), no histórico com o antes e o depois; com o prometido na mesma linha, o resto da linha ainda grava.';

-- _agenda_rascunho_frase (de 20261028100500_agenda_fase5_leituras.sql)
create or replace function public._agenda_rascunho_frase(p_tipo text, p_d jsonb)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_partes text[] := '{}';
  v_t      text;
  v_forn   text := nullif(p_d ->> 'fornecedor_txt', '');
  v_hoje   date := (p_d ->> 'hoje')::date;
  v_quando text;
  -- FASE 4: (P3) de onde veio o aviso ("nota 51038 da Kamell", "Pix de R$ 480,00 à Premel, seg 26/10").
  v_aviso  text;
  -- FASE 4: fim
  -- FASE 7b: (7b P2) a semana dita e as datas
  v_7b_dias smallint[];
  v_7b_fora smallint[];
  v_7b_n    int;
  -- FASE 7b: fim
begin
  if p_tipo = 'planejar' then
    if nullif(p_d ->> 'escopo_decidido', '') is not null then
      v_partes := v_partes || (p_d ->> 'escopo_decidido');
    end if;
    v_t := null;
    if p_d ->> 'dias' is not null then
      v_t := public._agenda_dias((p_d ->> 'dias')::numeric)
             || case when p_d ->> 'estimativa_fonte' = 'aceita' then ' (a minha estimativa, que você aceitou)' else '' end;
    end if;
    if jsonb_array_length(coalesce(p_d -> 'equipe', '[]'::jsonb)) > 0 then
      v_t := concat_ws(' ', v_t, 'com ' || public._agenda_lista(array(
               select case when (e ->> 'eh_dono')::boolean then 'você' else e ->> 'nome' end
                      || case e ->> 'turnos' when 'manha' then ' (de manhã)' when 'tarde' then ' (à tarde)' else '' end
                 from jsonb_array_elements(p_d -> 'equipe') with ordinality t(e, o) order by o), null));
    elsif p_d ? 'equipe' and p_d ->> 'dias' is null then
      v_t := 'sem ninguém marcado para ir';
    end if;
    if v_t is not null then
      v_partes := v_partes || v_t;
    end if;
    if p_d ->> 'dono' is not null then
      v_partes := v_partes || case p_d ->> 'dono' when 'abre_e_fecha' then 'você abre e fecha'
                                                 when 'sempre' then 'você fica o tempo todo' else 'você não vai' end;
    end if;
    if p_d ->> 'precisa_ate' is not null then
      v_partes := v_partes || ('o cliente precisa até ' || public._dia_curto((p_d ->> 'precisa_ate')::date));
    elsif p_d ? 'precisa_ate' then
      v_partes := v_partes || 'o cliente não tem mais prazo'::text;
    end if;
    if p_d ? 'bem' then
      v_partes := v_partes || case p_d #>> '{bem,modo}'
        when 'livre' then coalesce(p_d ->> 'bem_nome', 'o barco') || ' já está livre'
        when 'fora' then coalesce(p_d ->> 'bem_nome', 'o barco') || ' fica fora '
                         || public._agenda_quando_texto((p_d #>> '{bem,de}')::date, (p_d #>> '{bem,ate}')::date)
        else coalesce(p_d ->> 'bem_nome', 'o barco') || ' fica livre ' || public._dia_curto((p_d #>> '{bem,livre_em}')::date) end;
    end if;
    if p_d ->> 'nao_antes_de' is not null then
      v_partes := v_partes || ('não antes de ' || public._dia_curto((p_d ->> 'nao_antes_de')::date)
                               || case when coalesce(p_d ->> 'nao_antes_motivo', 'você disse') = 'você disse' then ''
                                       else ' (' || (p_d ->> 'nao_antes_motivo') || ')' end);
    elsif p_d ? 'nao_antes_de' then
      v_partes := v_partes || 'pode começar sem esperar data'::text;
    end if;
    if nullif(p_d ->> 'escopo_em_aberto', '') is not null then
      v_partes := v_partes || ('falta decidir: ' || (p_d ->> 'escopo_em_aberto'));
    elsif p_d ? 'escopo_em_aberto' and nullif(p_d ->> 'escopo_decidido', '') is null then
      v_partes := v_partes || 'nada mais a decidir no escopo'::text;
    end if;
    if p_d ->> 'congelada_ate' is not null then
      v_partes := v_partes || ('em espera até ' || public._dia_curto((p_d ->> 'congelada_ate')::date)
                               || case when p_d ->> 'revisar_em' is distinct from p_d ->> 'congelada_ate'
                                       then ' (rever ' || public._dia_curto((p_d ->> 'revisar_em')::date) || ')' else '' end);
    elsif p_d ? 'congelada_ate' then
      v_partes := v_partes || 'sai da espera'::text;
    end if;
    if p_d ->> 'prioridade' is not null then
      v_partes := v_partes || case when (p_d ->> 'prioridade')::int = 1 then 'passa na frente (prioridade 1)'
                                   else 'prioridade ' || (p_d ->> 'prioridade') end;
    end if;
    if p_d ->> 'sem_material' is not null then
      v_partes := v_partes || case when (p_d ->> 'sem_material')::boolean then 'não tem peça a comprar'
                                   else 'tem peça a conferir' end;
    end if;
    -- FASE 2: quanto dá para adiantar no pátio sem o bem (bancada: barramento, chicote).
    if p_d ? 'adiantavel_patio' then
      v_partes := v_partes || case when p_d ->> 'adiantavel_patio' is null then 'nada a adiantar no pátio'
                                   else 'dá para adiantar ' || public._agenda_dias((p_d ->> 'adiantavel_patio')::numeric) || ' no pátio' end;
    end if;
    -- FASE 5: o que o dono disse ao cliente ("você disse ao Flávio: ter 03/11 (data firme)") e como o serviço é dito a ele
    if jsonb_typeof(p_d -> 'prometido') = 'object' then
      v_partes := v_partes || format('você disse ao %s: %s (%s)', coalesce(nullif(p_d ->> 'curto', ''), 'cliente'),
        case when p_d #>> '{prometido,de}' = p_d #>> '{prometido,ate}' then public._dia_curto((p_d #>> '{prometido,ate}')::date)
             else format('de %s a %s', public._dia_curto((p_d #>> '{prometido,de}')::date),
                         public._dia_curto((p_d #>> '{prometido,ate}')::date)) end,
        case when p_d #>> '{prometido,tipo}' = 'firme' then 'data firme' else 'uma faixa' end);
    end if;
    if nullif(p_d ->> 'servico_cliente', '') is not null then
      v_partes := v_partes || format('o serviço, para o cliente: %s', p_d ->> 'servico_cliente');
    end if;
    -- FASE 5: fim
    -- FASE 7b: (7b P2, §6.6) a dupla dita ("vai com 1 pessoa só", "vai em dupla o tempo todo", "vai em dupla nos 2 primeiros
    -- meios-dias") e, com menos técnicos do que ela pede, o aviso de que a OS espera
    if p_d ->> 'dupla' is not null then
      v_7b_n := (p_d ->> 'dupla_meios')::int;
      v_partes := v_partes || case p_d ->> 'dupla'
        when 'nao' then 'vai com 1 pessoa só'
        when 'todos' then 'vai em dupla o tempo todo'
        when 'inicio' then case when v_7b_n = 1 then 'vai em dupla no primeiro meio-dia'
                                else format('vai em dupla nos %s primeiros meios-dias', v_7b_n) end
        else case when v_7b_n = 1 then 'vai em dupla no último meio-dia'
                  else format('vai em dupla nos %s últimos meios-dias', v_7b_n) end end;
    end if;
    if nullif(p_d ->> 'dupla_aviso', '') is not null then
      return array_to_string(v_partes, '; ') || '. ' || (p_d ->> 'dupla_aviso');
    end if;
    -- FASE 7b: fim
    return array_to_string(v_partes, '; ');
  end if;

  if p_tipo = 'material' then
    v_t := case p_d ->> 'acao'
      when 'na_mao' then
        case when p_d ->> 'quantidade_na_mao' is not null
             then format('%s de %s na mão', public._os_material_qtd((p_d ->> 'quantidade_na_mao')::numeric),
                         public._os_material_qtd((p_d ->> 'quantidade_necessaria')::numeric))
             when (p_d ->> 'chegou_em')::date = v_hoje then 'na mão (desde hoje)'
             else 'na mão desde ' || public._dia_curto((p_d ->> 'chegou_em')::date) end
      when 'comprado' then
        'comprado' || case when (p_d ->> 'comprado_em')::date = v_hoje then ' hoje'
                           else ' em ' || public._dia_curto((p_d ->> 'comprado_em')::date) end
        || case when p_d ->> 'previsao_ate' is not null
                then ', chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)' else '' end
      when 'a_caminho' then
        case when p_d ->> 'previsao_ate' is null then 'a caminho, sem previsão'
             when p_d ->> 'previsao_de' is not null then
               format('chega entre %s e %s (você disse)', public._dia_curto((p_d ->> 'previsao_de')::date),
                      public._dia_curto((p_d ->> 'previsao_ate')::date))
             else 'chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)' end
      when 'falta' then
        case when coalesce((p_d ->> 'vou_comprar')::boolean, false) then
               case when p_d ->> 'compra_prevista_em' is null then 'você vai comprar'
                    else 'você compra ' || public._dia_curto((p_d ->> 'compra_prevista_em')::date) end
             else 'falta comprar' end
      when 'sem_previsao' then 'comprado, sem previsão de chegada'
      when 'dispensado' then 'não precisa mais (sai da lista)'
      else null end;
    -- FASE 4: (P3) o aviso (a nota, o Pix ou a mensagem que a agenda perguntou) diz de onde veio; o fornecedor já está nele.
    if jsonb_typeof(p_d -> 'aviso') = 'object' then
      v_aviso := p_d -> 'aviso' ->> 'curto';
      v_t := case
        when coalesce((p_d ->> 'nota_chegou')::boolean, false) then
          format('na mão desde %s (a %s entrou no estoque)', public._dia_curto((p_d ->> 'chegou_em')::date), v_aviso)
        when p_d ->> 'acao' = 'na_mao' and p_d ->> 'quantidade_na_mao' is null then
          format('na mão desde %s (%s)', case when (p_d ->> 'chegou_em')::date = v_hoje then 'hoje'
                                              else public._dia_curto((p_d ->> 'chegou_em')::date) end, v_aviso)
        when p_d ->> 'acao' = 'a_caminho' and p_d -> 'aviso' ->> 'tipo' = 'nfe' then
          'a caminho pela ' || v_aviso
          || case when p_d ->> 'previsao_ate' is null then ', sem previsão de chegada'
                  when p_d ->> 'previsao_fonte' = 'dono' then ', chega ' || public._dia_curto((p_d ->> 'previsao_ate')::date) || ' (você disse)'
                  else ', chega por volta de ' || public._dia_curto((p_d ->> 'previsao_ate')::date) end
        when p_d ->> 'acao' = 'a_caminho' and p_d ->> 'previsao_ate' is not null and p_d ->> 'previsao_fonte' = 'fornecedor' then
          format('a caminho, chega por volta de %s (%s)', public._dia_curto((p_d ->> 'previsao_ate')::date), v_aviso)
        when p_d ->> 'acao' = 'comprado' and p_d -> 'aviso' ->> 'tipo' = 'pix' and p_d ->> 'previsao_ate' is null
             and v_aviso like 'Pix %' then
          'comprado pelo ' || v_aviso
        else coalesce(v_t || ' (' || v_aviso || ')', v_t) end;
      if p_d ->> 'critico' is not null and not (p_d ->> 'critico')::boolean then
        v_t := coalesce(v_t || ' (dá para começar sem)', 'dá para começar sem');
      end if;
      return v_t;
    end if;
    -- FASE 4: fim
    if v_t is not null and v_forn is not null and p_d ->> 'acao' <> 'dispensado' then
      v_t := v_t || ', fornecedor ' || v_forn;
    end if;
    if p_d ->> 'critico' is not null and not (p_d ->> 'critico')::boolean then
      v_t := coalesce(v_t || ' (dá para começar sem)', 'dá para começar sem');
    end if;
    return v_t;
  end if;

  if p_tipo = 'disponibilidade' then
    -- FASE 7b: (7b P2, §6.6, R4.2(c)) quem não está na equipe (a pessoa do cadastro): a frase de sempre e o aviso de que, com
    -- *grava*, ela entra
    if coalesce((p_d ->> 'fora_da_equipe')::boolean, false) then
      return public._agenda_rascunho_frase(p_tipo, p_d - 'fora_da_equipe')
             || format('. %s ainda não está na equipe da agenda: com *grava*, ele entra %s', p_d ->> 'nome',
                       case when coalesce((p_d ->> 'padrao')::boolean, false) then 'com esses dias, toda semana'
                            when p_d ? 'semana' or p_d ? 'datas' or p_d ->> 'de' is distinct from p_d ->> 'ate' then 'só nesses dias'
                            else 'só nesse dia' end);
    end if;
    -- a semana dita ("vem seg, ter e qui (e não vem qua e sex)"; o dono: "fica em campo seg e qua; nos outros dias, só abre e
    -- fecha"); o rótulo leva a semana ("Roberto, semana de 16/11")
    if p_d ? 'semana' then
      v_7b_dias := array(select jsonb_array_elements_text(coalesce(p_d -> 'dias_semana', '[]'::jsonb))::smallint);
      v_7b_fora := array(select x::smallint from generate_series(1, 5) x where not (x::smallint = any (v_7b_dias)) order by 1);
      if cardinality(v_7b_dias) = 0 and not coalesce((p_d ->> 'sabado')::boolean, false) then
        return case when (p_d ->> 'eh_dono')::boolean then 'só abre e fecha' else 'não vem' end;
      end if;
      if (p_d ->> 'eh_dono')::boolean then
        return 'fica em campo ' || public._agenda_dias_curtos(v_7b_dias, (p_d ->> 'sabado')::boolean)
               || case when cardinality(v_7b_fora) > 0 then '; nos outros dias, só abre e fecha' else '' end;
      end if;
      return 'vem ' || public._agenda_dias_curtos(v_7b_dias, (p_d ->> 'sabado')::boolean)
             || case when cardinality(v_7b_fora) > 0 then ' (e não vem ' || public._agenda_dias_curtos(v_7b_fora) || ')' else '' end;
    end if;
    -- as datas de quem vem sob demanda ("vem qua 11/11 e qui 12/11 (só nesses dias)")
    if p_d ? 'datas' then
      return case when (p_d ->> 'eh_dono')::boolean then 'em campo ' else 'vem ' end
             || public._agenda_lista(array(select public._dia_curto(x::date)
                                                  || case when extract(isodow from x::date)::int = 6 then ' de manhã' else '' end
                                             from jsonb_array_elements_text(p_d -> 'datas') with ordinality t(x, o) order by o), null)
             || ' (só nesses dias)';
    end if;
    -- FASE 7b: fim
    v_quando := case when (p_d ->> 'padrao')::boolean
                     then public._agenda_dias_semana_texto(array(select jsonb_array_elements_text(p_d -> 'dias_semana')::smallint))
                     else public._agenda_quando_texto((p_d ->> 'de')::date, (p_d ->> 'ate')::date) end;
    return case p_d ->> 'dito'
      when 'vem' then case when (p_d ->> 'eh_dono')::boolean then 'em campo ' else 'vem ' end || v_quando
      when 'nao_vem' then case when (p_d ->> 'eh_dono')::boolean then 'fora de campo ' else 'não vem ' end || v_quando
      when 'so_manha' then v_quando || ' à tarde, não'
      else v_quando || ' de manhã, não' end
      || case when coalesce((p_d ->> 'sabado_por_data')::boolean, false) then ' (sábado eu só conto por data)' else '' end;
  end if;

  -- FASE 2: os pedidos da conversa (marcar, aplicar/decidir, desfazer, andamento) chegam com a frase pronta do banco.
  if p_tipo in ('marcar', 'aplicar', 'desfazer', 'andamento') then
    return p_d ->> 'frase_pronta';
  end if;

  -- FASE 4: o prazo do fornecedor chega com a frase pronta do banco (agenda_rascunho_fornecedor).
  if p_tipo = 'fornecedor' then
    return p_d ->> 'frase_pronta';
  end if;
  -- FASE 4: fim
  -- FASE 4: (P3) "não é material de serviço" (a nota, o Pix ou a mensagem) chega com a frase pronta (agenda_rascunho_material).
  if p_tipo = 'aviso' then
    return p_d ->> 'frase_pronta';
  end if;
  -- FASE 4: fim
  raise exception '_agenda_rascunho_frase: tipo "%" não existe', p_tipo using errcode = '22023';
end;
$function$;

comment on function public._agenda_rascunho_frase(text, jsonb) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): a frase de uma linha do rascunho, montada dos dados já resolvidos — planejar ("2 dias com Roberto e João (à tarde); você abre e fecha; dá para adiantar 1 dia no pátio"), material ("chega ter 03/11 (você disse)", "você compra ter 27/10, fornecedor Premel") e disponibilidade ("em campo de seg a sex", "toda sexta à tarde, não"); os pedidos da Fase 2 (marcar, aplicar, desfazer, andamento), o prazo do fornecedor (Fase 4) e o "não é de serviço" (tipo aviso, Fase 4, P3) trazem a frase pronta (dados.frase_pronta); o material com o aviso diz de onde veio ("a caminho pela nota 51038 da Kamell, chega por volta de sex 30/10", "na mão desde hoje (Pix de R$ 480,00 à Premel, seg 26/10)", "na mão desde qua 28/10 (a nota 51038 da Kamell entrou no estoque)"). Fase 5 (P5): o planejar diz o que o dono disse ao cliente ("você disse ao Flávio: ter 03/11 (data firme)"; faixa: "de qua 04/11 a dom 08/11 (uma faixa)") e como o serviço é dito a ele ("o serviço, para o cliente: a instalação do compressor"). Fase 7b (P2, §6.6): o planejar com a dupla dita ("vai com 1 pessoa só", "vai em dupla o tempo todo", "vai em dupla nos 2 primeiros meios-dias", "… nos 2 últimos meios-dias"; 1 = "no primeiro meio-dia") e, com menos técnicos do que ela pede, o aviso "Hoje só Alex está na equipe: até você chamar alguém e me dizer os dias, eu não marco Lenine"; a disponibilidade com a semana ("vem seg, ter e qui (e não vem qua e sex)"; o dono: "fica em campo seg e qua; nos outros dias, só abre e fecha"; "não vem"; "só abre e fecha") e com as datas ("vem qua 11/11 e qui 12/11 (só nesses dias)"; o sábado "de manhã"); quem não está na equipe ganha "Mateus ainda não está na equipe da agenda: com *grava*, ele entra só nesses dias".';

-- ── 8. Portas ────────────────────────────────────────────────────────────────────────────────────────────────────
-- As novas de leitura e de texto: invoker; nunca anon nem authenticated (as RPCs e os passos da agenda as chamam como dono das
-- funções); service_role (o WhatsApp e os passos).
revoke all on function
  public._agenda_dias_curtos(smallint[], boolean), public._agenda_semana_perguntada(date),
  public._agenda_dias_declarados(uuid, date), public._agenda_chance_de_falta(uuid, date),
  public._agenda_semana_dita(text, text, date)
  from public, anon, authenticated;
grant execute on function
  public._agenda_dias_curtos(smallint[], boolean), public._agenda_semana_perguntada(date),
  public._agenda_dias_declarados(uuid, date), public._agenda_chance_de_falta(uuid, date),
  public._agenda_semana_dita(text, text, date)
  to service_role;
-- O gravador: security definer, sem grant a ninguém (nem service_role): só o *grava*, a resposta da equipe e o decidir o chamam.
revoke all on function public._agenda_equipe_dias_gravar(uuid, date, smallint[], boolean, text, text, timestamptz, uuid, uuid, uuid)
  from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas delas (create or replace não muda a ACL; repetidas aqui para a migration se bastar). A de 9
-- argumentos do rascunho é nova (o drop levou a ACL da de 8): as mesmas portas.
revoke all on function
  public.agenda_capacidade(date, date, date), public.agenda_capacidade_semanal(date)
  from public, anon;
grant execute on function
  public.agenda_capacidade(date, date, date), public.agenda_capacidade_semanal(date)
  to authenticated, service_role;
revoke all on function
  public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date, text),
  public.agenda_rascunho_gravar(uuid, date), public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date)
  from public, anon;
grant execute on function
  public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date, text),
  public.agenda_rascunho_gravar(uuid, date), public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date)
  to authenticated, service_role;
revoke all on function
  public._agenda_aplicar_disponibilidade(uuid, jsonb, text, date), public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date),
  public._agenda_rascunho_frase(text, jsonb)
  from public, anon, authenticated;
grant execute on function
  public._agenda_aplicar_disponibilidade(uuid, jsonb, text, date), public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date),
  public._agenda_rascunho_frase(text, jsonb)
  to service_role;

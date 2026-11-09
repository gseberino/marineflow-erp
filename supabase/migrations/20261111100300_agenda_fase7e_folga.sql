-- Agenda de Produção, Fase 7, etapa 7e ("A margem que aprende"), pacote P4: a folga da semana, a temporada e a urgência no motor. O quanto as OS variam passa a dizer quanto da semana da equipe guardar, a temporada guarda mais um pouco,
-- e a OS que o cliente precisa logo pode usar a folga.
-- Spec: scratchpad agenda-pesquisa/spec-fase7e.md (§5.3 e o bloco R7, que vale sobre o corpo: R7.1, R7.3-4, R7.4, R7.5-13, R7.5-14, R7.6, R7.7-3, R7.8, R7.12, R7.13); nomes: fase7-registro.md; o registro do pacote: notas-fase7e.md.
-- Depende de 20261111100000 (P1), 20261111100100 (P2) e 20261111100200 (P3). Copiado das definições MAIS NOVAS: _agenda_contexto (20261107100300_agenda_fase7d_motor.sql:352), _agenda_validar_itens (20261107100300_agenda_fase7d_motor.sql:2581), agenda_propor (20261107100800_agenda_fase7d_correcao.sql:568), _agenda_aprendizado_gravar (20261111100100_agenda_fase7e_medicao.sql:1617), _agenda_aprendizado_texto (20261111100100_agenda_fase7e_medicao.sql:1065).
--
-- ═══ NÃO APLICADA ═══ Existe para revisão e espera o OK (publicar/exec/aplicar.sh, nunca db push: esta versão fica antes das 20261116* que já estão em produção). Só funções; nenhuma coluna, nenhuma tabela, nenhum dado.
--
-- POR QUE: o motor marca até 80% da semana da equipe, sempre o mesmo número. Dos 20% guardados, 15% são para o serviço que passa do previsto: com as OS medidas (o P2), dá para saber quanto é preciso. A temporada pede guardar mais para a urgência,
-- e a OS urgente precisa poder usar a folga. _agenda_gestor_puxar (a véspera das 17:37) NÃO é deste pacote: é o P4b; aqui ficam os dois ganchos dele em agenda_propor e no validador, inertes sem p_restricoes.puxar.
--
-- O QUE MUDA, só com o modo ligado de verdade (o freio apaga: _agenda_margem_modo) e a regra teto_equipe (R7.6: sem ela o teto é por pessoa e a carga da semana não entra):
--   1. _agenda_aprender_folga_semana: o passo da rodada (o P7 o liga). A folga medida = z × σ dos resíduos do estimador × a mediana de g das semanas (§5.3), presa em [folga_semana_min, folga_semana_max] (R7.4); σ nulo ou zero = sem número medido (calculado nulo).
--   1b. _agenda_aprendizado_gravar e _agenda_aprendizado_texto, só o item folga_semana (correção da conferência do P4): sem número medido e sem nada em uso, medindo. Com a folga em uso fora do padrão, e os dois modos ligados (crus, R7.6), ela volta ao padrão por passo (folga_semana_troca_max), com a ação "aprendizado" e o *desfaz* de sempre, em vez de cair de uma vez; dentro da trava fica como o dono decidiu. E o texto de medindo com as semanas já bastando diz o que falta (as OS medidas, ou que elas ainda não mostraram variação), sem "12 de 8".
--   2. _agenda_carga_da_semana: carga_max + (o padrão − a folga em uso) − a temporada, presa em [carga_semana_min, carga_semana_max]. Em sombra, no freio ou desligada: carga_max (p_teste = o que seria, para a leitura em teste do P7).
--   3. _agenda_os_urgente: passa na frente, marcada como urgente ou o cliente precisa em urgencia_du dias úteis.
--   4. _agenda_contexto: o teto da equipe de cada semana (arredonda uma vez, na soma) e a saída carga_semana.
--   5. _agenda_validar_itens: a regra 6 com a carga da semana nos 4 pontos dos 2 ramos vivos (R7.5-13) e a urgente até 100% em todos os ramos; a regra 7 aceita só o criar da OS puxada (no dia, de quem o puxar diz, e a ponta do dono dela nesse dia).
--   6. agenda_propor: a urgente com teto100, as urgentes em p_restricoes e o motivo (R7.3-4: nunca "urgente" sozinho); "não coube na carga de N%" com a carga da semana nos 2 pontos da frase (R7.5-14); a OS puxada.
--
-- O QUE NÃO MUDA: os outros itens do gravador e dos textos (o bloco do P4 só vale para folga_semana; o achado 162 registra que os outros itens da margem caem de uma vez). Fora de ligado, as recriadas do motor saem byte a byte como antes (a chave nova fica AUSENTE) e em sombra não chamam nenhuma função nova (R7.8: o portão de custo lê a linha já carregada); agenda_vigiar, agenda_cliente_vigiar, agenda_capacidade_semanal e os leitores dela
-- ficam como estão (R7.N; o achado 160 diz o que afirmam em ligado). Nenhuma mensagem nova ao dono, à equipe ou ao cliente: os textos novos só aparecem em ligado, dentro do item que já existia. Nada de dinheiro.
--
-- DESFAZER (na ordem):
--   cada recriada volta à versão anterior pelo corpo da origem acima; depois, drop das 3 novas:
--   drop function if exists public._agenda_aprender_folga_semana(date, timestamptz);
--   drop function if exists public._agenda_carga_da_semana(date, boolean);
--   drop function if exists public._agenda_os_urgente(uuid, date);

-- ── 1. As funções novas ───────────────────────────────────────────────────────────────────────────

-- §5.3, R7.4, R7.12-2. O quanto da semana guardar para o que passa do previsto. Resíduos: as razões do estimador (só as dele: é dele que saem os planos do gestor, D7-1; a razão do dono fica no foco) contra o viés calculado da classe,
-- ou o geral sem a classe. σ = 1,4826 × MAD (o fator da normal). As semanas: as completas antes de hoje com serviço bastante; g = √(Σ p²) ÷ Σ p (uma OS só = 1: a semana inteira depende dela).
-- Com σ nulo ou zero (R7.4: o dia feito ecoa o plano e zera a dispersão) não se calcula: o que vale é a medida, e não há medida. Nada aqui lê o freio nem os modos: quem decide o uso é o gravador (modo cru). Com a folga em uso, é ele também quem a faz voltar ao padrão por passo.
create or replace function public._agenda_aprender_folga_semana(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c       public.agenda_config := public._agenda_cfg();
  v_seg   date;
  v_res   numeric[];
  v_nres  int := 0;
  v_mr    numeric;
  v_sigma numeric;
  v_ns    int := 0;
  v_gs    numeric[];
  v_g     numeric;
  v_am    jsonb := '[]'::jsonb;
  v_z     numeric;
  v_calc  numeric;
  v       jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1);
  begin
    -- os resíduos: nulo em v (sem viés calculado nem geral) não entra
    select coalesce(array_agg(x.r), '{}'::numeric[]), count(*)::int into v_res, v_nres
      from (select m.razao_estimativa / coalesce(f.calculado, g.calculado) as r
              from public.agenda_medidas_os m
              left join public.agenda_aprendizado f on f.item = 'vies' and f.chave = 'estimativa:' || m.classe_bem || ':' || m.classe_sistema
              left join public.agenda_aprendizado g on g.item = 'vies' and g.chave = 'estimativa:todas'
             where m.motivo_razao is null and m.razao_estimativa is not null
               and m.concluida_em between p_hoje - c.aprender_janela_dias and p_hoje
               and coalesce(f.calculado, g.calculado) > 0
             order by m.concluida_em desc, m.service_order_id
             limit c.fator_amostra_max) x;
    v_mr := public._agenda_percentil(v_res, 0.5);
    -- (o fator 1,4826 em inteiros: a regra da agenda só aceita 0,5 com casa decimal)
    v_sigma := 14826::numeric / 10000 * public._agenda_percentil(array(select abs(x - v_mr) from unnest(v_res) x), 0.5);
    -- as semanas ISO completas antes de hoje
    with sem as (
      select v_seg - 7 * k as seg from generate_series(1, c.folga_semanas) k
    ),
    por_os as (
      select s.seg, a.service_order_id as os, count(*)::numeric as p
        from sem s
        join public.agenda_alocacoes a on a.dia between s.seg and s.seg + 6
       where a.estado in ('publicada', 'fixada') and a.presenca = 'turno' and a.tipo <> 'reserva'
       group by 1, 2
    ),
    conta as (
      select o.seg, sum(o.p) as pm, count(*)::int as n_os, sqrt(sum(o.p * o.p)) / sum(o.p) as g
        from por_os o
       group by o.seg
      having sum(o.p) >= c.folga_meios_min
    )
    select count(*)::int, coalesce(array_agg(q.g), '{}'::numeric[]),
           coalesce(jsonb_agg(jsonb_build_object('semana', q.seg, 'g', round(q.g, 4), 'pm', q.pm, 'os', q.n_os) order by q.seg desc), '[]'::jsonb)
      into v_ns, v_gs, v_am
      from conta q;
    v_g := public._agenda_percentil(v_gs, 0.5);
    v_z := public._agenda_z(c.folga_percentil);
    -- R7.12-2: greatest e least ignoram nulo. Sem σ (ou σ = 0) e sem o mínimo de semanas (que nunca é 0) e de resíduos, o calculado é nulo (medindo).
    v_calc := case
      when v_sigma is null or v_sigma = 0 or v_ns < c.folga_semanas_min or v_nres < c.folga_residuos_min then null
      else round(least(c.folga_semana_max, greatest(c.folga_semana_min, v_z * v_sigma * v_g)), 2) end;
    v := public._agenda_aprendizado_gravar('folga_semana', 'equipe', 'geral', v_calc, v_ns, v_am, c.folga_dispersao_padrao,
           jsonb_build_object('sigma', round(v_sigma, 4), 'g', round(v_g, 4), 'residuos', v_nres, 'z', v_z, 'residuos_min', c.folga_residuos_min), p_agora);
    return jsonb_build_object('semanas', v_ns, 'residuos', v_nres, 'sigma', round(v_sigma, 4), 'g', round(v_g, 4), 'calculado', v_calc,
                              'estado', v ->> 'estado', 'em_uso', v -> 'em_uso', 'acao_id', v -> 'acao_id', 'erros', 0);
  exception when others then
    perform public.log_app_error('db', format('aprendizado, folga da semana: %s', sqlerrm), 'agenda', 'aprender:folga_semana', 'error',
                                 jsonb_build_object('sqlstate', sqlstate, 'p_hoje', p_hoje));
    return jsonb_build_object('semanas', v_ns, 'residuos', v_nres, 'erros', 1);
  end;
end;
$function$;

comment on function public._agenda_aprender_folga_semana(date, timestamptz) is
  'Agenda de Produção (Fase 7e, P4; §5.3, R7.4): o passo folga_semana da rodada do aprender: a folga da semana que basta para o que passa do previsto, medida pelos resíduos do estimador e pelas semanas com serviço; σ nulo ou zero = calculado nulo (medindo; com a folga em uso, o gravador a traz de volta ao padrão por passo, com ação e *desfaz*). Grava por _agenda_aprendizado_gravar. Sem grant: quem chama é agenda_aprender (P7).';

-- §5.3, R7.5-7, R7.6. A carga da semana (a segunda p_seg): carga_max + (o padrão − a folga em uso) − a temporada, presa nos limites. Sem o modo ligado de verdade (ou com p_teste falso em sombra), carga_max, sem dizer temporada nenhuma.
-- p_teste = true: o que seria com a folga calculada em teste, para a leitura em teste do P7. Lê _agenda_margem_em_uso (R7.5-7), que já olha o modo efetivo e modo_aprendizado: com o aprendizado fora, vale o padrão e sobra a temporada.
create or replace function public._agenda_carga_da_semana(p_seg date, p_teste boolean default false)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c     public.agenda_config := public._agenda_cfg();
  t     jsonb;
  v_f   numeric;
begin
  if p_seg is null then
    return null;
  end if;
  if not coalesce(p_teste, false) and public._agenda_margem_modo('folga_semana') <> 'ligado' then
    return jsonb_build_object('carga', c.carga_max, 'folga', c.folga_dispersao_padrao, 'extra', 0, 'por', null, 'texto', null);
  end if;
  t := public._agenda_temporada(p_seg);
  v_f := case when coalesce(p_teste, false)
              then coalesce((select a.calculado from public.agenda_aprendizado a where a.item = 'folga_semana' and a.chave = 'equipe' and a.estado = 'sombra'), c.folga_dispersao_padrao)
              else coalesce(public._agenda_margem_em_uso('folga_semana', 'equipe'), c.folga_dispersao_padrao) end;
  return jsonb_build_object(
    'carga', round(least(c.carga_semana_max, greatest(c.carga_semana_min, c.carga_max + (c.folga_dispersao_padrao - v_f) - (t ->> 'extra')::numeric)), 2),
    'folga', v_f, 'extra', (t ->> 'extra')::numeric, 'por', t ->> 'por', 'texto', t ->> 'texto');
end;
$function$;

comment on function public._agenda_carga_da_semana(date, boolean) is
  'Agenda de Produção (Fase 7e, P4; §5.3): a parte da semana da equipe que o motor pode comprometer. {carga, folga, extra, por, texto}. Lida pelo motor e pelo validador com o portão: em sombra e no freio, nenhum dos dois a chama.';

-- §5.3, R7.3-4, R7.12-3. A OS urgente: "passa na frente", marcada como urgente, ou o cliente precisa em urgencia_du dias úteis. A OS sem linha em os_planejamento é o caso comum (só 4 de 131 têm): nenhum dos campos vem e ela não é urgente por prazo.
create or replace function public._agenda_os_urgente(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c      public.agenda_config := public._agenda_cfg();
  v_prio int;
  v_prec date;
  v_st   text;
begin
  select pl.prioridade_manual, pl.precisa_ate into v_prio, v_prec from public.os_planejamento pl where pl.service_order_id = p_os;
  select so.priority into v_st from public.service_orders so where so.id = p_os;
  if v_prio = 1 then
    return jsonb_build_object('urgente', true, 'motivo', 'prioridade', 'texto', 'passa na frente');
  elsif v_st = 'urgent' then
    return jsonb_build_object('urgente', true, 'motivo', 'urgente', 'texto', 'marcada como urgente');
  elsif v_prec is not null and public.agenda_du_entre(p_hoje, v_prec) <= c.urgencia_du then
    return jsonb_build_object('urgente', true, 'motivo', 'prazo', 'texto', 'o cliente precisa até ' || public._dia_curto(v_prec));
  end if;
  return jsonb_build_object('urgente', false, 'motivo', null, 'texto', null);
end;
$function$;

comment on function public._agenda_os_urgente(uuid, date) is
  'Agenda de Produção (Fase 7e, P4; §5.3): se a OS é urgente e por quê. {urgente, motivo (prioridade|urgente|prazo), texto}. Só agenda_propor a lê, e só com modo_urgencia ligado de verdade.';

revoke all on function public._agenda_aprender_folga_semana(date, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public._agenda_carga_da_semana(date, boolean) from public, anon;
grant execute on function public._agenda_carga_da_semana(date, boolean) to authenticated, service_role;
revoke all on function public._agenda_os_urgente(uuid, date) from public, anon;
grant execute on function public._agenda_os_urgente(uuid, date) to authenticated, service_role;

-- ── 2. As recriadas ───────────────────────────────────────────────────────────────────────────────

-- _agenda_contexto (de 20261107100300_agenda_fase7d_motor.sql:352; md5 do corpo de antes e58bd4255ffbcae5027e756820a4dcf5)
create or replace function public._agenda_contexto(p_d_ini date, p_d_fim date, p_hoje date,
                                                   p_ignorar uuid[] default '{}'::uuid[], p_fila uuid[] default '{}'::uuid[])
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_nd    int;
  v_nh    int;
  v_seg   date;
  v_nw    int;
  v_g     jsonb;
  v_pes   uuid[];
  v_nomes text[];
  v_np    int;
  v_dono  int := 0;
  v_oss   uuid[] := coalesce(p_fila, '{}'::uuid[]);
  v_cap   int[];
  v_esp   numeric[];
  v_curta int[];
  v_ocup  int[];
  v_fr    int[];
  v_util  boolean[];
  v_sem   int[];
  v_espw  numeric[];
  v_t80   int[];
  v_t100  int[];
  v_uc    int[];
  v_ur    int[];
  v_loc   int[];
  v_padrao boolean;
  r       record;
  v_h     int;
  v_cel   int;
  v_mark  int;
  v_w     int;
  v_k     int;
  s       int;
  v_achou boolean;
  -- FASE 6: a carga de cada pessoa no teto de compromisso (o índice da pessoa e da semana; v_pp/v_ww: pp e ww são nomes de
  -- coluna da consulta do teto)
  v_pp    int;
  v_ww    int;
  v_carga numeric;
  -- FASE 6: fim
  -- FASE 7e: (7e P4, §5.3, R7.5-13) o teto da equipe com a carga de cada semana
  v_7e_fs  boolean;
  v_7e_c   numeric;
  v_7e_t   int;
  v_7e_cs  numeric[] := '{}'::numeric[];
  -- FASE 7e: fim
  -- FASE 7: (7a P5) o teto da equipe-semana (a regra teto_equipe do gestor) e o gancho do sábado (a variável agenda.sabado)
  v_f7_teq  boolean := public._agenda_gestor_regra('teto_equipe');
  v_f7_te   int[];
  v_f7_soma numeric;
  v_f7_sab  boolean;
  v_f7_cel  int;
  v_f7_quem int[];
  -- FASE 7: fim
  -- FASE 7b: (7b P4) o sábado da 7b (os índices dos sábados e a manhã livre de cada pessoa por semana), quem nunca fica sozinho, o
  -- dono técnico e o gancho da pessoa a mais (R4.4)
  v_7b_extra jsonb := '{}'::jsonb;
  v_7b_sab   int[];
  v_7b_bon   int[];
  v_7b_nov   int[];
  v_7b_d     int;
  v_7b_p     int;
  v_7b_util  boolean[];
  v_7b_cap   int[];
  -- FASE 7b: fim
  -- FASE 7c: (7c P2, §5.2) o que cada pessoa faz, na ordem da grade (hab, habf, custo)
  v_7c_hab   int[];
  v_7c_habf  int[];
  v_7c_custo int[];
  -- FASE 7c: fim
  -- FASE 7d: (7d P4, §5.4, R6.7b, R6.8-2) o local real no contexto, só com os modos ligados por _agenda_local_modo: o local de cada OS (uma
  -- leitura só), o município (mun: o índice, 0 sem município; mun_nomes) e o pátio (_agenda_patio_contexto)
  v_7d_ml   boolean := public._agenda_local_modo('mesmo_local') = 'ligado';
  v_7d_pa   boolean := public._agenda_local_modo('patio') = 'ligado';
  v_7d_lr   jsonb;
  v_7d_mun  int[];
  v_7d_munn text[];
  -- FASE 7d: fim
begin
  if p_d_ini is null or p_d_fim is null or p_d_fim < p_d_ini then
    raise exception 'agenda: período inválido para a grade (% a %)', p_d_ini, p_d_fim using errcode = '22023';
  end if;
  v_nd := p_d_fim - p_d_ini + 1;
  v_nh := 2 * v_nd;
  v_seg := p_d_ini - (extract(isodow from p_d_ini)::int - 1);
  v_nw := (p_d_fim - v_seg) / 7 + 1;

  select coalesce(jsonb_agg(to_jsonb(g) order by g.eh_dono desc, g.nome, g.payee_id, g.dia, g.turno = 'tarde'), '[]'::jsonb)
    into v_g
    from public.agenda_grade(p_d_ini, p_d_fim, p_hoje, coalesce(p_ignorar, '{}'::uuid[])) g;

  -- As pessoas: você primeiro, depois a equipe pelo nome (a ordem da grade).
  select coalesce(array_agg(q.payee_id order by q.eh_dono desc, q.nome, q.payee_id), '{}'::uuid[]),
         coalesce(array_agg(q.nome order by q.eh_dono desc, q.nome, q.payee_id), '{}'::text[]),
         coalesce(bool_or(q.eh_dono), false)
    into v_pes, v_nomes, v_padrao
    from (select distinct (e ->> 'payee_id')::uuid as payee_id, e ->> 'nome' as nome, (e ->> 'eh_dono')::boolean as eh_dono
            from jsonb_array_elements(v_g) e) q;
  v_np := cardinality(v_pes);
  if v_padrao then v_dono := 1; end if;

  -- O esperado só conta dia útil: o sábado combinado ("o Roberto vem sábado") a agenda automática não marca, e contá-lo
  -- subiria o teto dos dias úteis (10 meios + 2 do sábado = teto de 9, 90% da semana útil).
  select coalesce(array_agg(case when e ->> 'situacao' = 'livre' then 1 else 0 end order by o), '{}'::int[]),
         coalesce(array_agg(case when public.agenda_dia_util((e ->> 'dia')::date) then (e ->> 'meios_esperados')::numeric else 0 end
                            order by o), '{}'::numeric[])
    into v_cap, v_esp
    from jsonb_array_elements(v_g) with ordinality t(e, o);
  if coalesce(cardinality(v_cap), 0) <> v_np * v_nh then
    raise exception 'agenda: a grade veio incompleta (% células para % pessoas × % meios-dias)', cardinality(v_cap), v_np, v_nh;
  end if;
  -- FASE 7b: (7b P4, R4.4: o gancho do P6, inerte sem a variável) com agenda.pessoa_extra = tecnico — só _agenda_quem_chamar a liga,
  -- dentro da conta e sem gravar —, uma pessoa que não existe (_agenda_pessoa_extra_id, "mais uma pessoa") entra por último: livre
  -- nas manhãs e tardes de todo dia útil da grade (sem feriado nem recesso), não novato, não sob demanda, não o dono, com o teto de
  -- carga_max (_agenda_carga_da_pessoa) e contada no teto da equipe do 7a. Sem a variável, nada muda.
  if coalesce(current_setting('agenda.pessoa_extra', true), '') = 'tecnico' then
    v_pes := v_pes || public._agenda_pessoa_extra_id();
    v_nomes := v_nomes || 'mais uma pessoa'::text;
    v_np := v_np + 1;
    select v_cap || array_agg(case when public.agenda_dia_util(p_d_ini + (h - 1) / 2) then 1 else 0 end order by h),
           v_esp || array_agg(case when public.agenda_dia_util(p_d_ini + (h - 1) / 2) then 1::numeric else 0::numeric end order by h)
      into v_cap, v_esp
      from generate_series(1, v_nh) h;
  end if;
  -- FASE 7b: fim

  -- As pontas livres do dono: bit 1 = abertura, bit 2 = fechamento.
  v_curta := array_fill(0, array[v_nh]);
  if v_dono > 0 then
    select array_agg((case when e -> 'curta_livre' ? 'abertura' then 1 else 0 end)
                     + (case when e -> 'curta_livre' ? 'fechamento' then 2 else 0 end) order by o)
      into v_curta
      from jsonb_array_elements(v_g) with ordinality t(e, o)
     where o <= v_nh;
  end if;
  v_padrao := v_dono > 0 and exists (select 1 from jsonb_array_elements(v_g) with ordinality t(e, o)
                                      where o <= v_nh and e ->> 'situacao' = 'livre');

  -- As OS: as da fila primeiro (o índice delas é a posição), depois as que já ocupam a grade.
  v_oss := v_oss || coalesce(array(
    select distinct a.service_order_id from public.agenda_alocacoes a
     where a.estado in ('publicada', 'fixada') and a.dia between p_d_ini and p_d_fim
       and not (a.id = any (coalesce(p_ignorar, '{}'::uuid[]))) and not (a.service_order_id = any (v_oss))
     order by 1), '{}'::uuid[]);

  -- O que o plano vigente já ocupa: célula, frentes e uso da semana (compromisso e reserva).
  v_ocup := array_fill(0, array[greatest(v_np * v_nh, 1)]);
  v_fr := array_fill(0, array[v_nh * 4]);
  v_uc := array_fill(0, array[greatest(v_np * v_nw, 1)]);
  v_ur := array_fill(0, array[greatest(v_np * v_nw, 1)]);
  for r in
    select a.dia, a.turno, a.presenca, a.tipo, array_position(v_pes, a.payee_id) as pi,
           array_position(v_oss, a.service_order_id) as oi
      from public.agenda_alocacoes a
     where a.estado in ('publicada', 'fixada') and a.dia between p_d_ini and p_d_fim
       and not (a.id = any (coalesce(p_ignorar, '{}'::uuid[])))
     order by a.dia, a.turno = 'tarde', a.service_order_id, a.payee_id, a.id
  loop
    v_h := 2 * (r.dia - p_d_ini) + case when r.turno = 'tarde' then 2 else 1 end;
    v_mark := case when r.tipo = 'reserva' then -r.oi else r.oi end;
    if r.pi is not null then
      v_cel := (r.pi - 1) * v_nh + v_h;
      if v_ocup[v_cel] = 0 or (v_ocup[v_cel] < 0 and v_mark > 0) then v_ocup[v_cel] := v_mark; end if;
      if r.presenca = 'turno' then
        v_w := (r.dia - v_seg) / 7 + 1;
        v_k := (r.pi - 1) * v_nw + v_w;
        if r.tipo = 'reserva' then v_ur[v_k] := v_ur[v_k] + 1; else v_uc[v_k] := v_uc[v_k] + 1; end if;
      end if;
    end if;
    v_achou := false;
    for s in 1 .. 4 loop
      v_k := (v_h - 1) * 4 + s;
      if abs(v_fr[v_k]) = r.oi then
        if v_fr[v_k] < 0 and v_mark > 0 then v_fr[v_k] := v_mark; end if;
        v_achou := true;
        exit;
      end if;
    end loop;
    if not v_achou then
      for s in 1 .. 4 loop
        v_k := (v_h - 1) * 4 + s;
        if v_fr[v_k] = 0 then v_fr[v_k] := v_mark; exit; end if;
      end loop;
    end if;
  end loop;

  select array_agg(public.agenda_dia_util(p_d_ini + g) order by g), array_agg(((p_d_ini + g) - v_seg) / 7 + 1 order by g)
    into v_util, v_sem
    from generate_series(0, v_nd - 1) g;
  -- FASE 7b: (7b P4, §R2) o gancho do sábado do 7a (a pergunta crítica sabado, logo abaixo) só vale com modo_sabado desligado:
  -- com sombra ou ligado vale o sábado desta etapa (sab e sab_bonus: a manhã de quem se ofereceu). A grade de antes do gancho fica
  -- guardada e volta logo depois dele.
  v_7b_util := v_util;
  v_7b_cap := v_cap;
  -- FASE 7b: fim
  -- FASE 7: (7a P5) o gancho do sábado (AG7-08; spec-fase7a §5.5 e d9). Só com a variável agenda.sabado = 'on' — quem a liga
  -- é a decisão da pergunta crítica sabado (P12), dentro da transação, e a desliga em seguida — e com sabado_manha diferente de
  -- 'nunca': a manhã de cada sábado do período que ainda não é útil (sabado_util desligado) e não é feriado vira útil, com
  -- lugar só para quem tem o padrão de sábado de manhã (linha vigente de agenda_disponibilidade com dias_semana contendo o
  -- sábado, de manhã ou o dia todo, vem) e não tem exceção nem recesso que tire aquele dia (a grade já diz 'indisponivel'); a
  -- tarde fica sem ninguém. O sábado em que ninguém pode vir não muda (útil e vazio, ele contaria como dia parado de todo
  -- serviço que o atravessa). O sábado não entra no esperado: o teto da semana não sobe (o esperado já foi lido acima, só de
  -- dia útil). Sem a variável, nada muda.
  v_f7_sab := coalesce(current_setting('agenda.sabado', true), '') = 'on' and cf.sabado_manha <> 'nunca';
  if v_f7_sab then
    for f7_d in 1 .. v_nd loop
      continue when extract(isodow from p_d_ini + f7_d - 1)::int <> 6 or v_util[f7_d]
                    or public.agenda_feriado(p_d_ini + f7_d - 1) is not null;
      -- quem vem nessa manhã: o padrão de sábado, sem exceção nem recesso no dia (a célula da manhã na grade é a
      -- (pessoa − 1) × nh + 2 × (dia − 1) + 1; o jsonb conta de 0)
      v_f7_quem := array(select g.p from generate_series(1, coalesce(v_np, 0)) g(p)
                          where (v_g -> ((g.p - 1) * v_nh + 2 * (f7_d - 1)) ->> 'situacao') is distinct from 'indisponivel'
                            and exists (select 1 from public.agenda_disponibilidade d
                                         where d.payee_id = v_pes[g.p] and d.substituida_em is null
                                           and d.dias_semana @> array[6]::smallint[]
                                           and d.situacao in ('disponivel', 'confirmada')
                                           and (d.turno is null or d.turno = 'manha'))
                          order by g.p);
      continue when cardinality(v_f7_quem) = 0;
      v_util[f7_d] := true;
      for f7_p in 1 .. coalesce(v_np, 0) loop
        v_f7_cel := (f7_p - 1) * v_nh + 2 * (f7_d - 1) + 1;   -- a manhã de f7_p nesse sábado (a tarde é a célula seguinte)
        v_cap[v_f7_cel] := case when f7_p = any (v_f7_quem) then 1 else 0 end;
        v_cap[v_f7_cel + 1] := 0;
      end loop;
    end loop;
  end if;
  -- FASE 7: fim
  -- FASE 7b: (correção da revisão da 7b, achado 12) em teste (modo_sabado sombra) o gancho do sábado do 7a continua valendo: a pergunta
  -- crítica sabado da 7a ligada acha o sábado (antes, o modo em teste a desligava sem pôr nada visível no lugar). A grade guardada passa a
  -- ser a de depois dele, e a volta logo abaixo não muda nada. Só ligado o sábado é só o desta etapa.
  if cf.modo_sabado = 'sombra' then
    v_7b_util := v_util;
    v_7b_cap := v_cap;
  end if;
  -- FASE 7b: fim
  -- FASE 7b: (7b P4, §R2) com modo_sabado fora de desligado, o gancho do sábado do 7a não vale: a grade volta à de antes dele
  if cf.modo_sabado <> 'desligado' then
    v_util := v_7b_util;
    v_cap := v_7b_cap;
  end if;
  -- FASE 7b: fim

  -- O esperado de cada pessoa por semana ISO e os dois tetos: compromisso (carga_max) e compromisso + reserva (100%).
  with cel as (
    select (u.o - 1) / v_nh + 1 as p, ((u.o - 1) % v_nh) / 2 + 1 as d, u.x as esp
      from unnest(v_esp) with ordinality u(x, o)
  ),
  soma as (select cel.p, (v_sem)[cel.d] as w, sum(cel.esp) as e from cel group by 1, 2)
  select coalesce(array_agg(coalesce(soma.e, 0) order by pp, ww), '{}'::numeric[]),
         coalesce(array_agg(floor(cf.carga_max * coalesce(soma.e, 0))::int order by pp, ww), '{}'::int[]),
         coalesce(array_agg(floor(coalesce(soma.e, 0))::int order by pp, ww), '{}'::int[])
    into v_espw, v_t80, v_t100
    from generate_series(1, greatest(v_np, 1)) pp
    cross join generate_series(1, v_nw) ww
    left join soma on soma.p = pp and soma.w = ww
   where v_np > 0;
  -- FASE 6: (P4) a carga de cada pessoa (spec-fase6 §5.4): o teto de compromisso da semana é floor(carga × esperado), com a
  -- carga de _agenda_carga_da_pessoa (o dono com capacidade_dono em uso; os outros, e o dono sem nada em uso, carga_max). A
  -- pessoa pp é v_pes[pp] (a mesma ordem da grade: você primeiro) e a célula dela na semana ww é (pp − 1) × nw + ww — a
  -- ordem "order by pp, ww" do array_agg de cima, a mesma de esperado. Só a pessoa com outra carga muda; com o modo fora de
  -- ligado (ou sem o item na lista, ou nada em uso), nada muda: a saída é a de antes, byte a byte.
  for v_pp in 1 .. coalesce(v_np, 0) loop
    v_carga := public._agenda_carga_da_pessoa(v_pes[v_pp]);
    continue when v_carga = cf.carga_max;
    for v_ww in 1 .. v_nw loop
      v_t80[(v_pp - 1) * v_nw + v_ww] := floor(v_carga * v_espw[(v_pp - 1) * v_nw + v_ww])::int;
    end loop;
  end loop;
  -- FASE 6: fim

  -- FASE 7: (7a P5) o teto da equipe-semana (a regra teto_equipe; spec-fase7a §5.5 e d8). Com o portão, cada pessoa da equipe
  -- (todas menos o dono) pode chegar a 100% do que se espera dela na semana (o teto de compromisso vira o de 100%: teto80 =
  -- teto100), e a equipe inteira, a floor(carga_max × a soma do esperado dela) — arredonda uma vez, na soma, e não pessoa a
  -- pessoa (João 4,25 e Roberto 2 esperados: por pessoa 3 + 1 = 4; a equipe, floor(0,8 × 6,25) = 5). O dono continua com o
  -- teto dele (_agenda_carga_da_pessoa, a Fase 6, logo acima) e fica fora da conta da equipe: ele é presença (abrir, fechar,
  -- diagnóstico), não capacidade de técnico. A saída ganha teto_equipe (um número por semana, na ordem de sem). Sem o portão,
  -- nada muda.
  if v_f7_teq then
    v_f7_te := '{}'::int[];
    -- (7e P4, §5.3, R7.6, R7.8) com a folga da semana ligada de verdade, o teto da equipe de cada semana sai da carga daquela semana (temporada e folga medida). O portão de custo lê a linha já carregada: em sombra e com o freio, nenhuma chamada nova. Sem a regra teto_equipe o teto é o de cada pessoa e a carga da semana não entra (R7.6).
    v_7e_fs := case when cf.modo_folga_semana = 'ligado' and not cf.gestor_so_propor then public._agenda_margem_modo('folga_semana') = 'ligado' else false end;
    -- (7e: fim)
    for f7_w in 1 .. v_nw loop
      v_f7_soma := 0;
      for f7_p in 1 .. coalesce(v_np, 0) loop
        continue when f7_p = v_dono;
        v_f7_soma := v_f7_soma + coalesce(v_espw[(f7_p - 1) * v_nw + f7_w], 0);
        v_t80[(f7_p - 1) * v_nw + f7_w] := v_t100[(f7_p - 1) * v_nw + f7_w];
      end loop;
      v_f7_te := v_f7_te || floor(cf.carga_max * v_f7_soma)::int;
      -- (7e P4, §5.3, R7.5-13) a mesma conta da linha de cima (arredonda uma vez, na soma), com a carga da semana no lugar de carga_max. carga_semana guarda a carga de cada semana só quando ela muda o teto: efeito que o arredondamento apaga não é efeito (a frase da carga em agenda_propor lê daqui).
      if v_7e_fs then
        v_7e_c := (public._agenda_carga_da_semana(v_seg + 7 * (f7_w - 1)) ->> 'carga')::numeric;
        v_7e_t := floor(v_7e_c * v_f7_soma)::int;
        v_7e_cs := v_7e_cs || case when v_7e_t = v_f7_te[f7_w] then cf.carga_max else v_7e_c end;
        v_f7_te[f7_w] := v_7e_t;
      end if;
      -- (7e: fim)
    end loop;
  end if;
  -- FASE 7: fim
  -- O local de cada OS (a marina, senão a cidade do cliente), para o desempate "mesmo local".
  select coalesce(array_agg(q.loc order by q.o), '{}'::int[]) into v_loc
    from (select k.o, case when k.chave is null then 0 else dense_rank() over (order by k.chave)::int end as loc
            from (select u.o, coalesce('m:' || so.marina_id::text, 'c:' || nullif(lower(btrim(cl.city)), '')) as chave
                    from unnest(v_oss) with ordinality u(os, o)
                    left join public.service_orders so on so.id = u.os
                    left join public.clients cl on cl.id = so.client_id) k) q;

  -- FASE 7d: (7d P4, §5.4, R6.8-2, R6.9-7) com modo_mesmo_local ligado, loc vem da chave do local real (_agenda_local_resolvido: o local
  -- cadastrado ou c:<município> na suposição pela cidade), por cima da conta de cima, que fica byte a byte, e a saída ganha mun e mun_nomes;
  -- com modo_patio ligado, as chaves do pátio. Tudo vai pelo extra da 7b: a saída de cima (a 1ª das 3) é a única que roda desde a 7c, que
  -- sempre põe hab no extra. Fora de ligado, nenhuma chamada e nenhuma chave.
  if v_7d_ml or v_7d_pa then
    select coalesce(jsonb_agg(public._agenda_local_resolvido(u.os, p_hoje) order by u.o), '[]'::jsonb) into v_7d_lr
      from unnest(v_oss) with ordinality u(os, o);
  end if;
  if v_7d_ml then
    select coalesce(array_agg(q.loc order by q.o), '{}'::int[]) into v_loc
      from (select k.o, case when k.chave is null then 0 else dense_rank() over (order by k.chave)::int end as loc
              from (select t.o, t.e ->> 'chave' as chave from jsonb_array_elements(v_7d_lr) with ordinality t(e, o)) k) q;
    with m0 as (select t.o, nullif(public._agenda_normal(normalize(coalesce(t.e ->> 'municipio', ''), nfc)), '') as c, t.e ->> 'municipio' as nome
                  from jsonb_array_elements(v_7d_lr) with ordinality t(e, o)),
         m1 as (select m0.*, dense_rank() over (order by m0.c)::int as m from m0)
    select coalesce(array_agg(case when m1.c is null then 0 else m1.m end order by m1.o), '{}'::int[]),
           coalesce((select array_agg(x.nome order by x.m)
                       from (select distinct on (m2.m) m2.m, m2.nome from m1 m2 where m2.c is not null order by m2.m, m2.o) x), '{}'::text[])
      into v_7d_mun, v_7d_munn
      from m1;
    v_7b_extra := v_7b_extra || jsonb_build_object('mun', to_jsonb(v_7d_mun), 'mun_nomes', to_jsonb(v_7d_munn));
  end if;
  if v_7d_pa then
    v_7b_extra := v_7b_extra || public._agenda_patio_contexto(p_d_ini, p_d_fim, p_hoje, v_oss, v_7d_lr, coalesce(p_ignorar, '{}'::uuid[]), v_util);
  end if;
  -- FASE 7d: fim
  -- FASE 7c: (7c P2, §5.2, R5.3-4) o que cada pessoa faz, numa leitura só de agenda_habilidades (em p_hoje, o dia em que a 7c mede o
  -- papel), na ordem de pessoas: hab = 4 por pessoa (o instala efetivo, comissiona, altura e o papel: 0 responsável, 1 ajudante, 2
  -- novo); habf = 1 por pessoa, os bits 1 (instala), 2 (comissiona) e 4 (altura) do que veio do padrão, sem etiqueta (a suposição
  -- pessoa_sem_etiqueta do critério); custo = a diária do perfil vigente (sem perfil, e o dono, 999999). Quem agenda_habilidades não
  -- acha (a pessoa a mais da 7b, que não é payee) leva o padrão: habilidade_padrao, papel responsável, os 3 bits e 999999. Vão para
  -- a saída pelo extra da 7b (a saída é a de antes || teto_equipe, quando há, || o extra): as outras chaves não mudam, e só o motor
  -- da 7c as lê.
  with h as materialized (select * from public.agenda_habilidades(p_hoje, v_pes)),
  pe as (select g.p, h.instala, h.comissiona, h.altura, h.papel, h.fonte, h.payee_id is not null as achou
           from generate_series(1, coalesce(v_np, 0)) g(p) left join h on h.payee_id = v_pes[g.p])
  select coalesce((select array_agg(case k.k when 1 then coalesce(pe.instala, (cf.habilidade_padrao ->> 'instala')::int)
                                            when 2 then coalesce(pe.comissiona, (cf.habilidade_padrao ->> 'comissiona')::int)
                                            when 3 then coalesce(pe.altura, (cf.habilidade_padrao ->> 'altura')::int)
                                            else coalesce(pe.papel, 0) end order by pe.p, k.k)
                      from pe cross join generate_series(1, 4) k(k)), '{}'::int[]),
         coalesce((select array_agg(case when not pe.achou then 7
                                         else (case when pe.fonte ->> 'instala' = 'padrao' then 1 else 0 end)
                                              + (case when pe.fonte ->> 'comissiona' = 'padrao' then 2 else 0 end)
                                              + (case when pe.fonte ->> 'altura' = 'padrao' then 4 else 0 end) end order by pe.p)
                      from pe), '{}'::int[]),
         coalesce((select array_agg(case when pe.p = v_dono then 999999
                                         else coalesce((select round(w.valor_diaria)::int from public.work_profiles w
                                                         where w.payee_id = v_pes[pe.p] and w.vigencia_inicio <= p_hoje
                                                           and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje)
                                                         order by w.vigencia_inicio desc, w.id limit 1), 999999) end order by pe.p)
                      from pe), '{}'::int[])
    into v_7c_hab, v_7c_habf, v_7c_custo;
  v_7b_extra := v_7b_extra || jsonb_build_object('hab', to_jsonb(v_7c_hab), 'habf', to_jsonb(v_7c_habf), 'custo', to_jsonb(v_7c_custo));
  -- FASE 7c: fim
  -- FASE 7b: (7b P4, §5.3) o que o motor da 7b lê, só com os modos dela (sem eles, nenhuma chave nova: a saída de antes):
  -- (1) sab = os índices dos sábados do período sem feriado nem recesso de manhã, com modo_sabado fora de desligado e sabado_manha
  -- diferente de nunca; (2) sab_bonus por pessoa e semana ((pessoa − 1) × nw + semana) = as manhãs de sábado em que ela está livre
  -- (cap = 1: a manhã que ela ofereceu, a exceção "vem"): o encaixe soma ao teto dela só na tentativa com o sábado; (3) novato = os
  -- índices de quem nunca fica sozinho num meio-dia na 1ª data da grade — o novato (_agenda_e_novato, com novato_sozinho falso) e
  -- quem vem sob demanda (_agenda_e_sob_demanda, com sob_demanda_sozinho falso) —, com modo_dupla fora de desligado (a segurança,
  -- como a dupla em teste); nunca o dono nem a pessoa a mais; (4) dono_tec = dono_como_tecnico (com modo_dias fora de desligado: os
  -- dias de campo que ele disse). Os tetos não mudam aqui.
  if cf.modo_sabado <> 'desligado' and cf.sabado_manha <> 'nunca' then
    v_7b_sab := array(select g + 1 from generate_series(0, v_nd - 1) g
                       where extract(isodow from p_d_ini + g)::int = 6 and public.agenda_feriado(p_d_ini + g) is null
                         and not exists (select 1 from public.agenda_disponibilidade d
                                          where d.payee_id is null and d.situacao = 'indisponivel' and d.substituida_em is null
                                            and d.periodo @> (p_d_ini + g) and (d.turno is null or d.turno = 'manha'))
                       order by g);
    if cardinality(v_7b_sab) > 0 then
      v_7b_bon := array_fill(0, array[greatest(v_np * v_nw, 1)]);
      foreach v_7b_d in array v_7b_sab loop
        for v_7b_p in 1 .. coalesce(v_np, 0) loop
          if v_cap[(v_7b_p - 1) * v_nh + 2 * (v_7b_d - 1) + 1] = 1 then
            v_7b_bon[(v_7b_p - 1) * v_nw + v_sem[v_7b_d]] := v_7b_bon[(v_7b_p - 1) * v_nw + v_sem[v_7b_d]] + 1;
          end if;
        end loop;
      end loop;
      v_7b_extra := v_7b_extra || jsonb_build_object('sab', to_jsonb(v_7b_sab), 'sab_bonus', to_jsonb(v_7b_bon));
    end if;
  end if;
  if cf.modo_dupla <> 'desligado' then
    v_7b_nov := array(select g.p from generate_series(1, coalesce(v_np, 0)) g(p)
                       where g.p <> v_dono and v_pes[g.p] is distinct from public._agenda_pessoa_extra_id()
                         and ((not cf.novato_sozinho and public._agenda_e_novato(v_pes[g.p], p_d_ini))
                              or (not cf.sob_demanda_sozinho and public._agenda_e_sob_demanda(v_pes[g.p], p_d_ini)))
                       order by g.p);
    if cardinality(v_7b_nov) > 0 then
      v_7b_extra := v_7b_extra || jsonb_build_object('novato', to_jsonb(v_7b_nov));
    end if;
  end if;
  if cf.dono_como_tecnico and cf.modo_dias <> 'desligado' and v_dono > 0 then
    v_7b_extra := v_7b_extra || jsonb_build_object('dono_tec', true);
  end if;
  -- (7e P4, §5.3) a saída ganha carga_semana só em ligado; fora disso a chave não existe (R7.12-10)
  if v_7e_fs then
    v_7b_extra := v_7b_extra || jsonb_build_object('carga_semana', to_jsonb(v_7e_cs));
  end if;
  -- (7e: fim)
  if v_7b_extra <> '{}'::jsonb then
    return jsonb_build_object(
      'd_ini', p_d_ini, 'd_fim', p_d_fim, 'seg', v_seg, 'nd', v_nd, 'nh', v_nh, 'np', v_np, 'nw', v_nw,
      'dono', v_dono, 'dono_tem_padrao', v_padrao,
      'pessoas', to_jsonb(v_pes), 'nomes', to_jsonb(v_nomes), 'oss', to_jsonb(v_oss),
      'util', to_jsonb(v_util), 'sem', to_jsonb(v_sem), 'cap', to_jsonb(v_cap), 'curta', to_jsonb(v_curta),
      'ocup', to_jsonb(v_ocup), 'fr', to_jsonb(v_fr), 'esperado', to_jsonb(coalesce(v_espw, '{}'::numeric[])),
      'teto80', to_jsonb(coalesce(v_t80, '{}'::int[])), 'teto100', to_jsonb(coalesce(v_t100, '{}'::int[])),
      'uso_c', to_jsonb(v_uc), 'uso_r', to_jsonb(v_ur), 'loc', to_jsonb(v_loc))
      || case when v_f7_teq then jsonb_build_object('teto_equipe', to_jsonb(coalesce(v_f7_te, '{}'::int[]))) else '{}'::jsonb end
      || v_7b_extra;
  end if;
  -- FASE 7b: fim
  -- FASE 7: (7a P5) com o portão do teto da equipe, a mesma saída de baixo (chave a chave; o T7 de
  -- supabase/tests/agenda_fase7a_teto.sql confere que só teto80 e teto_equipe mudam) com o teto da equipe por semana.
  if v_f7_teq then
    return jsonb_build_object(
      'd_ini', p_d_ini, 'd_fim', p_d_fim, 'seg', v_seg, 'nd', v_nd, 'nh', v_nh, 'np', v_np, 'nw', v_nw,
      'dono', v_dono, 'dono_tem_padrao', v_padrao,
      'pessoas', to_jsonb(v_pes), 'nomes', to_jsonb(v_nomes), 'oss', to_jsonb(v_oss),
      'util', to_jsonb(v_util), 'sem', to_jsonb(v_sem), 'cap', to_jsonb(v_cap), 'curta', to_jsonb(v_curta),
      'ocup', to_jsonb(v_ocup), 'fr', to_jsonb(v_fr), 'esperado', to_jsonb(coalesce(v_espw, '{}'::numeric[])),
      'teto80', to_jsonb(coalesce(v_t80, '{}'::int[])), 'teto100', to_jsonb(coalesce(v_t100, '{}'::int[])),
      'uso_c', to_jsonb(v_uc), 'uso_r', to_jsonb(v_ur), 'loc', to_jsonb(v_loc),
      'teto_equipe', to_jsonb(coalesce(v_f7_te, '{}'::int[])));
  end if;
  -- FASE 7: fim
  return jsonb_build_object(
    'd_ini', p_d_ini, 'd_fim', p_d_fim, 'seg', v_seg, 'nd', v_nd, 'nh', v_nh, 'np', v_np, 'nw', v_nw,
    'dono', v_dono, 'dono_tem_padrao', v_padrao,
    'pessoas', to_jsonb(v_pes), 'nomes', to_jsonb(v_nomes), 'oss', to_jsonb(v_oss),
    'util', to_jsonb(v_util), 'sem', to_jsonb(v_sem), 'cap', to_jsonb(v_cap), 'curta', to_jsonb(v_curta),
    'ocup', to_jsonb(v_ocup), 'fr', to_jsonb(v_fr), 'esperado', to_jsonb(coalesce(v_espw, '{}'::numeric[])),
    'teto80', to_jsonb(coalesce(v_t80, '{}'::int[])), 'teto100', to_jsonb(coalesce(v_t100, '{}'::int[])),
    'uso_c', to_jsonb(v_uc), 'uso_r', to_jsonb(v_ur), 'loc', to_jsonb(v_loc));
end;
$function$;

comment on function public._agenda_contexto(date, date, date, uuid[], uuid[]) is
  'Agenda de Produção (Fase 2, P2): a grade do motor em arrays (agenda_grade de p_d_ini a p_d_fim, sem as alocações de p_ignorar): pessoas (você primeiro), dias úteis, semana ISO de cada dia, quem está livre em cada meio-dia (cap), as pontas livres do dono (curta: 1 abertura, 2 fechamento), o que o vigente ocupa (ocup, frentes: o índice da OS em oss, negativo = reserva), o uso por pessoa e semana (compromisso e reserva) e os tetos floor(carga_max × esperado) e floor(esperado) — o esperado só de dia útil (o sábado combinado não sobe o teto). As OS de p_fila vêm primeiro em oss. FASE 6 (P4): o teto80 de cada pessoa usa _agenda_carga_da_pessoa (o dono com capacidade_dono em uso: floor(carga dele × esperado); os outros, carga_max) — a posição (pp − 1) × nw + ww é a pessoa v_pes[pp] na semana ww; fora de ligado, a saída de antes. FASE 7 (7a P5), atrás do portão _agenda_gestor_regra(''teto_equipe'') (falso = a saída de antes, byte a byte): cada pessoa da equipe (todas menos o dono) pode chegar a 100% do esperado dela na semana (teto80 = teto100); a equipe inteira, a teto_equipe[semana] = floor(carga_max × a soma do esperado da equipe), arredondado uma vez, na soma; o dono mantém o teto dele (_agenda_carga_da_pessoa) e fica fora da soma (é presença, não capacidade de técnico); a saída ganha teto_equipe (um número por semana, na ordem de sem). O gancho do sábado (AG7-08): só com a variável agenda.sabado = ''on'' (a decisão da pergunta crítica sabado a liga) e sabado_manha diferente de nunca, a manhã de cada sábado que ainda não é útil e não é feriado vira útil, com lugar só para quem tem o padrão de sábado de manhã (sem exceção nem recesso naquele dia); a tarde fica sem ninguém; o sábado não entra no esperado (o teto não sobe). Sem a variável, nada muda. FASE 7b (P4, §5.3, §R2, R4.4): (0) o gancho do sábado do 7a (agenda.sabado) só com modo_sabado desligado; (1) sab = os sábados do período sem feriado nem recesso de manhã e (2) sab_bonus por pessoa e semana = as manhãs de sábado livres dela (a que ela ofereceu), com modo_sabado fora de desligado e sabado_manha diferente de nunca; (3) novato = os índices de quem nunca fica sozinho — o novato (_agenda_e_novato, novato_sozinho falso) e quem vem sob demanda (_agenda_e_sob_demanda, sob_demanda_sozinho falso) —, com modo_dupla fora de desligado, nunca o dono; (4) dono_tec = dono_como_tecnico com modo_dias fora de desligado. O gancho da pessoa a mais (R4.4, inerte sem a variável): com agenda.pessoa_extra = tecnico, "mais uma pessoa" (_agenda_pessoa_extra_id) entra por último, livre nas manhãs e tardes de todo dia útil, não novato nem sob demanda, com o teto de carga_max e contada no teto da equipe. Os tetos não mudam. Sem os modos e sem a variável, a saída de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achado 12): o gancho do sábado do 7a (agenda.sabado) vale também com modo_sabado em teste (sombra); só com modo_sabado ligado vale só o desta etapa. FASE 7c (P2, §5.2, R5.3-4): a saída ganha hab (4 por pessoa, na ordem de pessoas: o instala efetivo, comissiona, altura e o papel de agenda_habilidades em p_hoje), habf (1 por pessoa: os bits 1 instala, 2 comissiona, 4 altura do que veio do padrão) e custo (a diária do perfil vigente; sem perfil e o dono, 999999); a pessoa a mais da 7b leva o padrão. As outras chaves, as de antes. FASE 7d (P4, §5.4, R6.8-2, R6.9-7): com modo_mesmo_local ligado por _agenda_local_modo, loc vem da chave do local real (_agenda_local_resolvido) e a saída ganha mun (int[] por OS, o município normalizado; 0 sem município) e mun_nomes; com modo_patio ligado, as chaves de _agenda_patio_contexto. Fora de ligado, nenhuma chamada e nenhuma chave: a saída de antes, byte a byte. FASE 7e (P4): com modo_folga_semana ligado de verdade (o freio apaga) e a regra teto_equipe, o teto da equipe de cada semana sai de _agenda_carga_da_semana e a saída ganha carga_semana; fora disso, a saída de antes, byte a byte.';

-- _agenda_validar_itens (de 20261107100300_agenda_fase7d_motor.sql:2581; md5 do corpo de antes 4374bd580e148fcc53be3e44bcaad44a)
create or replace function public._agenda_validar_itens(p_itens jsonb, p_parametros jsonb, p_hoje date, p_agora timestamptz,
                                                        p_aplicar boolean default false, p_pront jsonb default null)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_cong  date := public.agenda_somar_du(p_hoje, cf.congelamento_du);
  v_acima boolean := coalesce((p_parametros #>> '{p_restricoes,acima_da_carga}')::boolean, false);
  v_dono  uuid := public._agenda_dono(null);
  v_login uuid;
  v_canc  uuid[];
  v_n     jsonb;
  v_v     jsonb := '[]'::jsonb;
  v_d1    date;
  v_d2    date;
  v_cap   jsonb;
  v_pr    jsonb := coalesce(p_pront, '{}'::jsonb);
  v_meios jsonb := '{}'::jsonb;
  v_cart  uuid[];
  v_os    uuid;
  r       record;
  q       record;
  v_cl    jsonb;
  v_m     jsonb;
  -- FASE 7b: (7b P4) o teto da equipe na regra 6 refeita com o sábado
  v_7b_teq boolean;
  -- FASE 7b: fim
  -- FASE 7d: (7d P4, R6.9-3) com o calendário do local ligado, a máscara de cada OS da proposta (a escada passa por aqui)
  v_7d_lm jsonb := '{}'::jsonb;
  -- FASE 7d: fim
  -- FASE 7e: (7e P4, §5.3, R7.5-13, R7.7) as OS urgentes e a puxada que vêm nos parâmetros (chaves só em ligado ou no puxar) e o teto da equipe semana a semana com a folga ligada (o que a soma da equipe lê: v_n e cf.carga_max)
  v_7e_urg  jsonb := p_parametros #> '{p_restricoes,urgentes}';
  v_7e_pux  jsonb := p_parametros #> '{p_restricoes,puxar}';
  v_7e_fs   boolean;
  v_7e_sem  date[];
  v_7e_n0   jsonb;
  v_7e_nb   jsonb;
  v_7e_np   jsonb;
  v_7e_cm   numeric := cf.carga_max;
  v_7e_i    int;
  -- FASE 7e: fim
begin
  select py.app_user_id into v_login from public.payees py where py.id = v_dono;
  select coalesce(array_agg(distinct (a ->> 'alocacao_id')::uuid), '{}'::uuid[]) into v_canc
    from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) i, jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) a
   where i ->> 'op' = 'cancelar' and a ->> 'alocacao_id' is not null;

  -- As alocações novas, uma linha cada (r = a ordem), com o que o item diz delas.
  select coalesce(jsonb_agg(x.a || jsonb_build_object(
           'r', x.r, 'k', x.k, 'os', x.i -> 'os', 'numero', x.i -> 'numero',
           'tipo', x.i -> 'tipo', 'evento_real', coalesce(x.i -> 'evento_real', 'false'::jsonb),
           'fixar_dono', coalesce(x.i -> 'fixar_dono', 'false'::jsonb), 'abre', coalesce(x.i -> 'abre', 'false'::jsonb),
           'fecha', coalesce(x.i -> 'fecha', 'false'::jsonb), 'critica', x.i -> 'critica', 'decisao', x.i -> 'decisao')
           order by x.r), '[]'::jsonb)
    into v_n
    from (select t.i, t.k, u.a, (row_number() over (order by t.k, u.j))::int as r
            from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) with ordinality t(i, k),
                 jsonb_array_elements(coalesce(t.i -> 'alocacoes', '[]'::jsonb)) with ordinality u(a, j)
           where t.i ->> 'op' = 'criar') x;

  if jsonb_array_length(v_n) > 0 then
    select min((e ->> 'dia')::date), max((e ->> 'dia')::date) into v_d1, v_d2 from jsonb_array_elements(v_n) e;
    v_d1 := v_d1 - (extract(isodow from v_d1)::int - 1);
    v_d2 := v_d2 + (7 - extract(isodow from v_d2)::int);
    select coalesce(jsonb_agg(to_jsonb(k)), '[]'::jsonb) into v_cap from public.agenda_capacidade(v_d1, v_d2, p_hoje) k;
    -- FASE 7b: (7b P4, R4.4: o gancho do P6, inerte sem a variável) com agenda.pessoa_extra = tecnico (só a simulação de quem chamar,
    -- sem gravar), a "mais uma pessoa" está livre nas manhãs e tardes de todo dia útil (sem feriado nem recesso), como no contexto:
    -- ela não viola a regra 1 e o teto dela é o de quem tem a semana inteira (a regra 6 e a soma da equipe a contam).
    if coalesce(current_setting('agenda.pessoa_extra', true), '') = 'tecnico' then
      v_cap := v_cap || coalesce((
        select jsonb_agg(jsonb_build_object('payee_id', public._agenda_pessoa_extra_id(), 'pessoa', 'mais uma pessoa', 'eh_dono', false,
                 'dia', g::date, 'turno', t.turno,
                 'situacao', case when public.agenda_dia_util(g::date) then 'livre' else 'indisponivel' end,
                 'meios_esperados', case when public.agenda_dia_util(g::date) then 1 else 0 end, 'origem', null,
                 'motivo', 'mais uma pessoa (simulação)') order by g, t.o)
          from generate_series(v_d1, v_d2, interval '1 day') g cross join (values ('manha', 1), ('tarde', 2)) t(turno, o)), '[]'::jsonb);
    end if;
    -- FASE 7b: fim
    v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k);
    for v_os in select distinct (e ->> 'os')::uuid from jsonb_array_elements(v_n) e loop
      if not v_pr ? v_os::text then
        v_pr := v_pr || jsonb_build_object(v_os::text, public.os_prontidao(v_os, p_hoje));
      end if;
      v_meios := v_meios || jsonb_build_object(v_os::text, public.agenda_meios_da_os(v_os, p_hoje));
    end loop;
  end if;

  -- (1) A pessoa ativa e livre no turno (a ponta livre, na presença curta), sem feriado.
  v_v := v_v || coalesce((
    select jsonb_agg(jsonb_build_object('regra', 1, 'os', n.os, 'numero', n.numero, 'pessoa', n.nome, 'dia', n.dia, 'turno', n.turno,
             'texto', format('%s não está livre %s (%s).', n.nome, public._agenda_meio_texto(n.dia, n.turno),
                             coalesce(k.motivo, k.situacao, 'não está na equipe'))) order by n.r)
      from jsonb_to_recordset(v_n) as n(r int, os uuid, numero text, payee_id uuid, nome text, dia date, turno text, presenca text)
      left join jsonb_to_recordset(v_cap) as k(payee_id uuid, dia date, turno text, situacao text, motivo text)
        on k.payee_id = n.payee_id and k.dia = n.dia and k.turno = n.turno
     where (n.presenca = 'turno' and k.situacao is distinct from 'livre')
        or (n.presenca <> 'turno' and (k.situacao is null or k.situacao in ('indisponivel', 'feriado', 'fim_de_semana')
                                       or not public.agenda_dia_util(n.dia)
                                       or exists (select 1 from public.agenda_tasks t
                                                   where t.kind = 'appointment' and v_login is not null and t.assignee_user_id = v_login
                                                     and t.status not in ('cancelled', 'done') and t.scheduled_start_at is not null
                                                     and tstzrange(t.scheduled_start_at, coalesce(t.scheduled_end_at, t.scheduled_start_at), '[]')
                                                         && public.agenda_periodo(n.dia, n.turno, n.presenca))))), '[]'::jsonb);

  -- FASE 7: (7a P12, spec §3.3 d9 e §5.12; AG7-08) a manhã de sábado que o dono autorizou: a decisão 1 da pergunta crítica
  -- sabado liga a variável agenda.sabado só na transação dela, e o motor (_agenda_contexto, P5) passa a contar a manhã de sábado
  -- de quem tem o padrão de sábado. Aqui a mesma conta: com a variável e sabado_manha diferente de 'nunca', o meio-dia de turno
  -- na manhã de um sábado sem feriado, de quem tem o padrão de sábado de manhã (linha vigente com dias_semana contendo o sábado,
  -- de manhã ou o dia todo, vem) e que a grade dá como fim de semana (sem exceção "não vem" nem recesso: aí ela diz
  -- indisponivel), não viola a regra 1. Sem a variável, a regra 1 de antes (o T6d do agenda_fase7a_teto continua recusando).
  if coalesce(current_setting('agenda.sabado', true), '') = 'on' and cf.sabado_manha <> 'nunca' and jsonb_array_length(v_v) > 0 then
    v_v := coalesce((
      select jsonb_agg(e order by o) from jsonb_array_elements(v_v) with ordinality t(e, o)
       where not (e ->> 'regra' = '1' and exists (
         select 1
           from jsonb_to_recordset(v_n) as n(os uuid, payee_id uuid, nome text, dia date, turno text, presenca text)
           join jsonb_to_recordset(v_cap) as k(payee_id uuid, dia date, turno text, situacao text)
             on k.payee_id = n.payee_id and k.dia = n.dia and k.turno = n.turno
          where n.os::text = e ->> 'os' and n.nome is not distinct from e ->> 'pessoa' and n.dia::text = e ->> 'dia'
            and n.turno = e ->> 'turno' and n.presenca = 'turno' and n.turno = 'manha' and extract(isodow from n.dia) = 6
            and k.situacao = 'fim_de_semana' and public.agenda_feriado(n.dia) is null
            and exists (select 1 from public.agenda_disponibilidade d
                         where d.payee_id = n.payee_id and d.substituida_em is null and d.dias_semana @> array[6]::smallint[]
                           and d.situacao in ('disponivel', 'confirmada') and (d.turno is null or d.turno = 'manha'))))),
      '[]'::jsonb);
  end if;
  -- FASE 7: fim
  -- (2) Sem choque com o vigente de agora (menos o que a proposta cancela) nem dentro da proposta.
  v_v := v_v || coalesce((
    select jsonb_agg(jsonb_build_object('regra', 2, 'os', n.os, 'numero', n.numero, 'pessoa', n.nome, 'dia', n.dia, 'turno', n.turno,
             'texto', format('%s já está em outro serviço %s.', n.nome, public._agenda_meio_texto(n.dia, n.turno))) order by n.r)
      from jsonb_to_recordset(v_n) as n(r int, os uuid, numero text, payee_id uuid, nome text, dia date, turno text, presenca text)
     where exists (select 1 from public.agenda_alocacoes v
                    where v.payee_id = n.payee_id and v.estado in ('publicada', 'fixada') and not (v.id = any (v_canc))
                      and v.periodo && public.agenda_periodo(n.dia, n.turno, n.presenca))
        or exists (select 1 from jsonb_to_recordset(v_n) as m(r int, payee_id uuid, dia date, turno text, presenca text)
                    where m.r < n.r and m.payee_id = n.payee_id and m.dia = n.dia
                      and public.agenda_periodo(m.dia, m.turno, m.presenca) && public.agenda_periodo(n.dia, n.turno, n.presenca))), '[]'::jsonb);

  -- (3) Nada antes do dia em que a OS fica pronta (fora a reserva e o pedido do dono).
  v_v := v_v || coalesce((
    select jsonb_agg(jsonb_build_object('regra', 3, 'os', x.os, 'numero', x.numero, 'pessoa', null, 'dia', x.dia, 'turno', null,
             'texto', format('%s %s: antes do dia em que fica pronta.', x.numero, public._dia_curto(x.dia))) order by x.dia, x.numero)
      from (select distinct n.os, n.numero, n.dia
              from jsonb_to_recordset(v_n) as n(os uuid, numero text, dia date, tipo text, fixar_dono boolean)
              left join public.os_planejamento pl on pl.service_order_id = n.os
             where n.tipo <> 'reserva' and not n.fixar_dono
               and ((v_pr -> n.os::text) #>> '{material,estado}' in ('atrasado', 'sem_previsao')
                    or n.dia < ((v_pr -> n.os::text) #>> '{material,inicio_mat}')::date
                    or n.dia < pl.nao_antes_de
                    or coalesce(pl.bem_indisponivel @> n.dia, false))) x), '[]'::jsonb);

  -- FASE 7d: (7d P4, R6.9-3) a regra 3 com a máscara do local, só com modo_local_calendario ligado: nada num dia ou num meio-dia que o local não
  -- recebe (fora a reserva e o pedido do dono, como a regra 3). A troca de turno ou de dia da escada passa por aqui.
  if jsonb_array_length(v_n) > 0 and public._agenda_local_modo('calendario') = 'ligado' then
    for v_os in select distinct (e ->> 'os')::uuid from jsonb_array_elements(v_n) e loop
      v_7d_lm := v_7d_lm || jsonb_build_object(v_os::text, public._agenda_local_mascara(v_os, v_d1, v_d2, p_hoje));
    end loop;
    v_v := v_v || coalesce((
      select jsonb_agg(jsonb_build_object('regra', 3, 'os', x.os, 'numero', x.numero, 'pessoa', null, 'dia', x.dia, 'turno', x.turno,
               'texto', format('%s %s: %s.', x.numero, public._dia_curto(x.dia),
                               coalesce(regexp_replace(v_7d_lm -> x.os::text -> 'motivos' ->> (x.dia - v_d1 + 1)::text, ' \([^()]*\)$', ''),
                                        'o local não recebe a equipe nesse meio-dia'))) order by x.dia, x.numero, x.turno)
        from (select distinct n.os, n.numero, n.dia, n.turno
                from jsonb_to_recordset(v_n) as n(os uuid, numero text, dia date, turno text, tipo text, fixar_dono boolean)
               where n.tipo <> 'reserva' and not n.fixar_dono
                 and ((n.dia - v_d1 + 1) = any (public._agenda_ints(v_7d_lm -> n.os::text -> 'dias'))
                      or (2 * (n.dia - v_d1) + case when n.turno = 'tarde' then 2 else 1 end) = any (public._agenda_ints(v_7d_lm -> n.os::text -> 'meios')))) x), '[]'::jsonb);
  end if;
  -- FASE 7d: fim
  -- (4) A presença do dono conforme a regra; (5) alguém em cada meio-dia de execução; (13) interrupções.
  for r in
    select (e ->> 'k')::int as k, min(e ->> 'os') as os, min(e ->> 'numero') as numero, bool_or((e ->> 'fixar_dono')::boolean) as fixar,
           bool_or((e ->> 'abre')::boolean) as abre, bool_or((e ->> 'fecha')::boolean) as fecha, min(e ->> 'tipo') as tipo
      from jsonb_array_elements(v_n) e
     group by (e ->> 'k')::int order by 1
  loop
    continue when r.tipo = 'reserva';
    v_m := v_meios -> r.os;
    -- os meios-dias do item, com quem está em cada um
    for q in
      with a as (select * from jsonb_to_recordset(v_n) as n(k int, payee_id uuid, dia date, turno text, presenca text) where n.k = r.k),
      meio as (select a.dia, a.turno,
                      bool_or(a.payee_id = v_dono and a.presenca = 'turno') as dono_turno,
                      bool_or(a.payee_id = v_dono and a.presenca = 'abertura') as dono_ab,
                      bool_or(a.payee_id = v_dono and a.presenca = 'fechamento') as dono_fe,
                      count(*) filter (where a.presenca = 'turno') as turnos,
                      count(*) filter (where a.presenca = 'turno' and a.payee_id is distinct from v_dono) as equipe
                 from a group by a.dia, a.turno)
      select m.*, row_number() over (order by m.dia, m.turno = 'tarde') as o, count(*) over () as n
        from meio m order by m.dia, m.turno = 'tarde'
    loop
      if not r.fixar then
        if v_m ->> 'presenca' = 'nunca' and (q.dono_turno or q.dono_ab or q.dono_fe) then
          v_v := v_v || jsonb_build_object('regra', 4, 'os', r.os, 'numero', r.numero, 'dia', q.dia, 'turno', q.turno,
                   'texto', format('%s: você foi posto %s, mas a OS é sem você.', r.numero, public._agenda_meio_texto(q.dia, q.turno)));
        elsif v_m ->> 'presenca' in ('sempre', 'equipe') and coalesce((v_m #>> array['dono_turno', q.turno])::boolean, false)
              and q.turnos > 0 and not q.dono_turno then
          v_v := v_v || jsonb_build_object('regra', 4, 'os', r.os, 'numero', r.numero, 'dia', q.dia, 'turno', q.turno,
                   'texto', format('%s: falta você %s.', r.numero, public._agenda_meio_texto(q.dia, q.turno)));
        elsif v_m ->> 'presenca' = 'abre_e_fecha' and (q.dono_turno
              or (q.o = 1 and r.abre and not q.dono_ab) or (q.o = q.n and r.fecha and not q.dono_fe)) then
          v_v := v_v || jsonb_build_object('regra', 4, 'os', r.os, 'numero', r.numero, 'dia', q.dia, 'turno', q.turno,
                   'texto', format('%s: a abertura e o fechamento não estão onde deviam (%s).', r.numero,
                                   public._agenda_meio_texto(q.dia, q.turno)));
        end if;
      end if;
      if q.turnos = 0 and not (q.o = q.n and q.dono_fe) then
        v_v := v_v || jsonb_build_object('regra', 5, 'os', r.os, 'numero', r.numero, 'dia', q.dia, 'turno', q.turno,
                 'texto', format('%s: ninguém trabalha %s.', r.numero, public._agenda_meio_texto(q.dia, q.turno)));
      end if;
    end loop;
    -- (13) os dias úteis inteiros sem a OS entre o 1º e o último meio-dia da equipe
    if (select count(*)
          from (select min(n.dia) as d1, max(n.dia) as d2
                  from jsonb_to_recordset(v_n) as n(k int, dia date, presenca text) where n.k = r.k and n.presenca = 'turno') b,
               generate_series(b.d1 + 1, b.d2 - 1, interval '1 day') g
         where public.agenda_dia_util(g::date)
           and not exists (select 1 from public.os_planejamento pl where pl.service_order_id = r.os::uuid and pl.bem_indisponivel @> g::date)
           and not exists (select 1 from jsonb_to_recordset(v_n) as n(k int, dia date, presenca text)
                            where n.k = r.k and n.presenca = 'turno' and n.dia = g::date)) > cf.interrupcoes_max then
      v_v := v_v || jsonb_build_object('regra', 13, 'os', r.os, 'numero', r.numero,
               'texto', format('%s: o serviço pararia mais de %s dia(s) no meio.', r.numero, cf.interrupcoes_max));
    end if;
  end loop;

  -- FASE 7d: (7d P4, R6.9-3) a regra 13 com a máscara do local: o motor pula o dia fechado (ele entra em v_bem) sem contar como parado; aqui a
  -- conta é refeita sem esse dia, e a violação sai quando ele era o que passava do limite. Sem a máscara, a de cima.
  if v_7d_lm <> '{}'::jsonb and exists (select 1 from jsonb_array_elements(v_v) e where e ->> 'regra' = '13') then
    v_v := coalesce((
      select jsonb_agg(e order by o) from jsonb_array_elements(v_v) with ordinality t(e, o)
       where not (e ->> 'regra' = '13'
                  and (select count(*)
                         from (select min(n.dia) as d1, max(n.dia) as d2
                                 from jsonb_to_recordset(v_n) as n(os text, dia date, presenca text) where n.os = e ->> 'os' and n.presenca = 'turno') b,
                              generate_series(b.d1 + 1, b.d2 - 1, interval '1 day') g
                        where public.agenda_dia_util(g::date)
                          and not exists (select 1 from public.os_planejamento pl where pl.service_order_id = (e ->> 'os')::uuid and pl.bem_indisponivel @> g::date)
                          and not exists (select 1 from jsonb_to_recordset(v_n) as n(os text, dia date, presenca text)
                                           where n.os = e ->> 'os' and n.presenca = 'turno' and n.dia = g::date)
                          and not ((g::date - v_d1 + 1) = any (public._agenda_ints(v_7d_lm -> (e ->> 'os') -> 'dias')))
                          and not ((2 * (g::date - v_d1) + 1) = any (public._agenda_ints(v_7d_lm -> (e ->> 'os') -> 'meios'))
                                   and (2 * (g::date - v_d1) + 2) = any (public._agenda_ints(v_7d_lm -> (e ->> 'os') -> 'meios')))) <= cf.interrupcoes_max)),
      '[]'::jsonb);
  end if;
  -- FASE 7d: fim
  -- FASE 7b: (7b P4, §5.3; AG7-02) o dono técnico (dono_como_tecnico, com modo_dias fora de desligado): o dono num meio-dia de turno
  -- de serviço em que ele só abre e fecha é a vaga de técnico que o motor deu a ele (por último, nos dias de campo dele) — não viola a
  -- regra 4, desde que a abertura e o fechamento estejam onde deviam (o 1º meio-dia com a abertura dele, o último com o fechamento).
  if cf.dono_como_tecnico and cf.modo_dias <> 'desligado' and jsonb_array_length(v_v) > 0 then
    v_v := coalesce((
      select jsonb_agg(e order by o) from jsonb_array_elements(v_v) with ordinality t(e, o)
       where not (e ->> 'regra' = '4' and e ->> 'texto' like '%a abertura e o fechamento não estão onde deviam%'
                  and exists (
                    select 1 from jsonb_to_recordset(v_n) as n(k int, os uuid, payee_id uuid, dia date, turno text, presenca text,
                                                              abre boolean, fecha boolean)
                     where n.os::text = e ->> 'os' and n.dia::text = e ->> 'dia' and n.turno = e ->> 'turno'
                       and n.payee_id = v_dono and n.presenca = 'turno'
                       and not (n.abre
                                and (n.dia, n.turno = 'tarde') = (select m.dia, m.turno = 'tarde' from jsonb_to_recordset(v_n) as m(k int, dia date, turno text)
                                                                   where m.k = n.k order by m.dia, m.turno = 'tarde' limit 1)
                                and not exists (select 1 from jsonb_to_recordset(v_n) as m(k int, payee_id uuid, dia date, turno text, presenca text)
                                                 where m.k = n.k and m.payee_id = v_dono and m.dia = n.dia and m.turno = n.turno and m.presenca = 'abertura'))
                       and not (n.fecha
                                and (n.dia, n.turno = 'tarde') = (select m.dia, m.turno = 'tarde' from jsonb_to_recordset(v_n) as m(k int, dia date, turno text)
                                                                   where m.k = n.k order by m.dia desc, m.turno = 'tarde' desc limit 1)
                                and not exists (select 1 from jsonb_to_recordset(v_n) as m(k int, payee_id uuid, dia date, turno text, presenca text)
                                                 where m.k = n.k and m.payee_id = v_dono and m.dia = n.dia and m.turno = n.turno and m.presenca = 'fechamento'))))),
      '[]'::jsonb);
  end if;
  -- FASE 7b: fim
  -- FASE 7e: (7e P4, §5.3 (b), R7.5-13, R7.12-1, R7.12-11) a urgente vai até 100% da semana, como o pedido do dono, nos 3 lugares da regra 6 (por pessoa, a soma da equipe e as versões com o sábado). A soma da equipe só deixa de contar a alocação da própria OS urgente (v_7e_nb). O teto da pessoa vale para a semana inteira dela (v_n): o motor pode ter posto uma OS normal antes da urgente na fila, e o bool_and da coluna fixar reprovaria o que ele montou (agenda_propor lança). v_n volta ao que era antes da regra 7.
  -- (§5.3 (b)) a OS puxada ganhou teto100 no motor: vale aqui como a urgente, senão o validador reprovaria o que o motor montou (agenda_propor lança; o P4b chama com acima_da_carga, e ela segue valendo sozinha)
  if jsonb_typeof(v_7e_pux) = 'object' then
    v_7e_urg := coalesce(v_7e_urg, '[]'::jsonb) || jsonb_build_array(v_7e_pux ->> 'os');
  end if;
  if jsonb_typeof(v_7e_urg) = 'array' and jsonb_array_length(v_7e_urg) > 0 and jsonb_array_length(v_n) > 0 then
    v_7e_n0 := v_n;
    select jsonb_agg(x.e || case when x.u then '{"fixar_dono": true}'::jsonb else '{}'::jsonb end order by x.r),
           jsonb_agg(x.e || case when x.pu then '{"fixar_dono": true}'::jsonb else '{}'::jsonb end order by x.r)
      into v_7e_nb, v_n
      from (select t.e, (t.e ->> 'r')::int as r, t.u,
                   bool_or(t.u) over (partition by t.e ->> 'payee_id', (t.e ->> 'dia')::date - (extract(isodow from (t.e ->> 'dia')::date)::int - 1)) as pu
              from (select e, v_7e_urg ? (e ->> 'os') and e ->> 'tipo' <> 'reserva' and e ->> 'presenca' = 'turno' as u
                      from jsonb_array_elements(v_n) e) t) x;
  end if;
  -- (§5.3, R7.8) com a folga ligada, as semanas que a proposta toca: a soma da equipe é conferida semana a semana, com a carga daquela semana (a mesma função que o motor leu em _agenda_contexto). Fora de ligado, nenhuma chamada nova.
  v_7e_fs := case when cf.modo_folga_semana = 'ligado' and not cf.gestor_so_propor then public._agenda_margem_modo('folga_semana') = 'ligado' else false end;
  if v_7e_fs and jsonb_array_length(v_n) > 0 then
    v_7e_sem := array(select distinct (e ->> 'dia')::date - (extract(isodow from (e ->> 'dia')::date)::int - 1) from jsonb_array_elements(v_n) e order by 1);
    v_7e_nb := coalesce(v_7e_nb, v_n);
  end if;
  v_7e_np := v_n;
  -- FASE 7e: fim
  -- (6) O teto por pessoa e semana: compromisso até carga_max (100% com acima_da_carga ou pedido do dono); com a
  -- reserva, até 100%. A presença curta do dono não conta. Só a semana que a proposta toca.
  -- FASE 7: (7a P5) a regra 6 com o teto da equipe-semana (a regra teto_equipe; spec-fase7a §5.5), a mesma conta do encaixe.
  -- Com o portão: (a) o compromisso de cada pessoa da equipe vai até 100% do esperado dela (floor(esperado)); o dono continua
  -- com o teto dele (floor(carga dele × esperado), _agenda_carga_da_pessoa); acima_da_carga e o pedido do dono, 100% como
  -- antes; a semana inteira (com as reservas) não muda; o texto, o de antes. (b) Por semana, a soma da equipe — as pessoas da
  -- grade menos o dono; o vigente (menos o que a proposta cancela) + o novo, sem reserva — não passa de floor(carga_max × a
  -- soma do esperado dela, só de dia útil): "A equipe passaria do limite da semana de 09/11: 11 meios-dias de serviço para 10."
  -- O novo pedido pelo dono (fixar_dono) não entra na soma, e a semana só é conferida com algum compromisso novo da equipe fora
  -- dele: o encaixe põe o pedido do dono sem o teto da equipe, em qualquer ordem da fila, e contá-lo aqui recusaria o que o
  -- motor monta (agenda_propor não solta proposta inválida). Com acima_da_carga, sem o teto da equipe (como o encaixe). Sem o
  -- portão, a regra 6 da Fase 6, logo abaixo, como antes.
  if public._agenda_gestor_regra('teto_equipe') then
    v_v := v_v || coalesce((
      with nov as (
        select n.payee_id, min(n.nome) as nome, n.dia - (extract(isodow from n.dia)::int - 1) as seg,
               count(*) filter (where n.tipo <> 'reserva') as comp, count(*) filter (where n.tipo = 'reserva') as res,
               bool_and(n.fixar_dono) as fixar,
               case when n.payee_id is not distinct from v_dono then public._agenda_carga_da_pessoa(n.payee_id)
                    else 1::numeric end as cg
          from jsonb_to_recordset(v_n) as n(payee_id uuid, nome text, dia date, presenca text, tipo text, fixar_dono boolean)
         where n.presenca = 'turno'
         group by n.payee_id, 3
      ),
      esp as (
        select k.payee_id, k.dia - (extract(isodow from k.dia)::int - 1) as seg, sum(k.meios_esperados) as e
          from jsonb_to_recordset(v_cap) as k(payee_id uuid, dia date, meios_esperados numeric)
         where public.agenda_dia_util(k.dia)
         group by 1, 2
      ),
      vig as (
        select v.payee_id, v.dia - (extract(isodow from v.dia)::int - 1) as seg,
               count(*) filter (where v.tipo <> 'reserva') as comp, count(*) filter (where v.tipo = 'reserva') as res
          from public.agenda_alocacoes v
         where v.estado in ('publicada', 'fixada') and v.presenca = 'turno' and not (v.id = any (v_canc))
           and v.dia between v_d1 and v_d2
         group by 1, 2
      )
      select jsonb_agg(jsonb_build_object('regra', 6, 'pessoa', nov.nome, 'dia', nov.seg,
               'texto', case when nov.comp > 0 and coalesce(vig.comp, 0) + nov.comp
                                    > case when v_acima or nov.fixar then floor(coalesce(esp.e, 0)) else floor(nov.cg * coalesce(esp.e, 0)) end
                             then format('%s passaria do limite da semana de %s: %s meios-dias de serviço para %s.', nov.nome,
                                         to_char(nov.seg, 'DD/MM'), coalesce(vig.comp, 0) + nov.comp,
                                         case when v_acima or nov.fixar then floor(coalesce(esp.e, 0))::int
                                              else floor(nov.cg * coalesce(esp.e, 0))::int end)
                             else format('%s passaria da semana inteira de %s: %s meios-dias com as reservas para %s.', nov.nome,
                                         to_char(nov.seg, 'DD/MM'), coalesce(vig.comp, 0) + nov.comp + coalesce(vig.res, 0) + nov.res,
                                         floor(coalesce(esp.e, 0))::int) end)
               order by nov.seg, nov.nome)
        from nov
        left join esp on esp.payee_id = nov.payee_id and esp.seg = nov.seg
        left join vig on vig.payee_id = nov.payee_id and vig.seg = nov.seg
       where (nov.comp > 0 and coalesce(vig.comp, 0) + nov.comp
                > case when v_acima or nov.fixar then floor(coalesce(esp.e, 0)) else floor(nov.cg * coalesce(esp.e, 0)) end)
          or coalesce(vig.comp, 0) + nov.comp + coalesce(vig.res, 0) + nov.res > floor(coalesce(esp.e, 0))), '[]'::jsonb);
    if not v_acima then
      -- (7e P4, §5.3, R7.5-13) a consulta de baixo é a de sempre; com a folga ligada, ela roda uma vez por semana, com só aquela semana em v_n e a carga dela em cf.carga_max (os 2 pontos do teto). Com só urgência, uma volta com as urgentes fora da soma. Fora de ligado, uma volta, sem nada trocado.
      for v_7e_i in 1 .. case when v_7e_fs then coalesce(cardinality(v_7e_sem), 0) else 1 end loop
        if v_7e_nb is not null then
          v_n := case when v_7e_fs then coalesce((select jsonb_agg(e) from jsonb_array_elements(v_7e_nb) e where (e ->> 'dia')::date - (extract(isodow from (e ->> 'dia')::date)::int - 1) = v_7e_sem[v_7e_i]), '[]'::jsonb) else v_7e_nb end;
          if v_7e_fs then
            cf.carga_max := (public._agenda_carga_da_semana(v_7e_sem[v_7e_i]) ->> 'carga')::numeric;
          end if;
        end if;
      -- (7e: fim)
      v_v := v_v || coalesce((
        with eq as (
          select distinct k.payee_id
            from jsonb_to_recordset(v_cap) as k(payee_id uuid)
           where k.payee_id is distinct from v_dono
        ),
        nov as (
          select n.dia - (extract(isodow from n.dia)::int - 1) as seg,
                 count(*) filter (where n.tipo <> 'reserva' and not n.fixar_dono) as comp
            from jsonb_to_recordset(v_n) as n(payee_id uuid, dia date, presenca text, tipo text, fixar_dono boolean)
           where n.presenca = 'turno' and n.payee_id in (select eq.payee_id from eq)
           group by 1
        ),
        esp as (
          select k.dia - (extract(isodow from k.dia)::int - 1) as seg, sum(k.meios_esperados) as e
            from jsonb_to_recordset(v_cap) as k(payee_id uuid, dia date, meios_esperados numeric)
           where public.agenda_dia_util(k.dia) and k.payee_id is distinct from v_dono
           group by 1
        ),
        vig as (
          select v.dia - (extract(isodow from v.dia)::int - 1) as seg, count(*) as comp
            from public.agenda_alocacoes v
           where v.estado in ('publicada', 'fixada') and v.presenca = 'turno' and v.tipo <> 'reserva'
             and not (v.id = any (v_canc)) and v.dia between v_d1 and v_d2
             and v.payee_id in (select eq.payee_id from eq)
           group by 1
        )
        select jsonb_agg(jsonb_build_object('regra', 6, 'pessoa', null, 'dia', nov.seg,
                 'texto', format('A equipe passaria do limite da semana de %s: %s meios-dias de serviço para %s.',
                                 to_char(nov.seg, 'DD/MM'), coalesce(vig.comp, 0) + nov.comp,
                                 floor(cf.carga_max * coalesce(esp.e, 0))::int))
                 order by nov.seg)
          from nov
          left join esp on esp.seg = nov.seg
          left join vig on vig.seg = nov.seg
         where nov.comp > 0 and coalesce(vig.comp, 0) + nov.comp > floor(cf.carga_max * coalesce(esp.e, 0))), '[]'::jsonb);
      -- (7e P4) o fim do laço de cima: v_n e cf.carga_max voltam ao que eram
      end loop;
      if v_7e_nb is not null then
        v_n := v_7e_np;
        cf.carga_max := v_7e_cm;
      end if;
      -- (7e: fim)
    end if;
  else
  -- FASE 7: fim
  -- FASE 6: (P4) a regra 6 com a carga de cada pessoa (spec-fase6 §5.4): o teto de compromisso é floor(carga × esperado),
  -- com a carga de _agenda_carga_da_pessoa (o dono com capacidade_dono em uso; os outros, carga_max) no lugar de carga_max;
  -- o texto não muda. O vigente conta, mas a violação só existe com alocação nova (nov.comp > 0): o publicado não muda. A
  -- regra de antes (logo abaixo) não roda mais: fica para a conferência da cópia.
  v_v := v_v || coalesce((
    with nov as (
      select n.payee_id, min(n.nome) as nome, n.dia - (extract(isodow from n.dia)::int - 1) as seg,
             count(*) filter (where n.tipo <> 'reserva') as comp, count(*) filter (where n.tipo = 'reserva') as res,
             bool_and(n.fixar_dono) as fixar, public._agenda_carga_da_pessoa(n.payee_id) as carga
        from jsonb_to_recordset(v_n) as n(payee_id uuid, nome text, dia date, presenca text, tipo text, fixar_dono boolean)
       where n.presenca = 'turno'
       group by n.payee_id, 3
    ),
    esp as (
      -- (só dia útil, como o teto do motor: o sábado combinado não sobe o teto da semana)
      select k.payee_id, k.dia - (extract(isodow from k.dia)::int - 1) as seg, sum(k.meios_esperados) as e
        from jsonb_to_recordset(v_cap) as k(payee_id uuid, dia date, meios_esperados numeric)
       where public.agenda_dia_util(k.dia)
       group by 1, 2
    ),
    vig as (
      select v.payee_id, v.dia - (extract(isodow from v.dia)::int - 1) as seg,
             count(*) filter (where v.tipo <> 'reserva') as comp, count(*) filter (where v.tipo = 'reserva') as res
        from public.agenda_alocacoes v
       where v.estado in ('publicada', 'fixada') and v.presenca = 'turno' and not (v.id = any (v_canc))
         and v.dia between v_d1 and v_d2
       group by 1, 2
    )
    select jsonb_agg(jsonb_build_object('regra', 6, 'pessoa', nov.nome, 'dia', nov.seg,
             'texto', case when nov.comp > 0 and coalesce(vig.comp, 0) + nov.comp
                                  > case when v_acima or nov.fixar then floor(coalesce(esp.e, 0)) else floor(nov.carga * coalesce(esp.e, 0)) end
                           then format('%s passaria do limite da semana de %s: %s meios-dias de serviço para %s.', nov.nome,
                                       to_char(nov.seg, 'DD/MM'), coalesce(vig.comp, 0) + nov.comp,
                                       case when v_acima or nov.fixar then floor(coalesce(esp.e, 0))::int
                                            else floor(nov.carga * coalesce(esp.e, 0))::int end)
                           else format('%s passaria da semana inteira de %s: %s meios-dias com as reservas para %s.', nov.nome,
                                       to_char(nov.seg, 'DD/MM'), coalesce(vig.comp, 0) + nov.comp + coalesce(vig.res, 0) + nov.res,
                                       floor(coalesce(esp.e, 0))::int) end)
             order by nov.seg, nov.nome)
      from nov
      left join esp on esp.payee_id = nov.payee_id and esp.seg = nov.seg
      left join vig on vig.payee_id = nov.payee_id and vig.seg = nov.seg
     where (nov.comp > 0 and coalesce(vig.comp, 0) + nov.comp
              > case when v_acima or nov.fixar then floor(coalesce(esp.e, 0)) else floor(nov.carga * coalesce(esp.e, 0)) end)
        or coalesce(vig.comp, 0) + nov.comp + coalesce(vig.res, 0) + nov.res > floor(coalesce(esp.e, 0))), '[]'::jsonb);
  if false then
  -- FASE 6: fim
  v_v := v_v || coalesce((
    with nov as (
      select n.payee_id, min(n.nome) as nome, n.dia - (extract(isodow from n.dia)::int - 1) as seg,
             count(*) filter (where n.tipo <> 'reserva') as comp, count(*) filter (where n.tipo = 'reserva') as res,
             bool_and(n.fixar_dono) as fixar
        from jsonb_to_recordset(v_n) as n(payee_id uuid, nome text, dia date, presenca text, tipo text, fixar_dono boolean)
       where n.presenca = 'turno'
       group by n.payee_id, 3
    ),
    esp as (
      -- (só dia útil, como o teto do motor: o sábado combinado não sobe o teto da semana)
      select k.payee_id, k.dia - (extract(isodow from k.dia)::int - 1) as seg, sum(k.meios_esperados) as e
        from jsonb_to_recordset(v_cap) as k(payee_id uuid, dia date, meios_esperados numeric)
       where public.agenda_dia_util(k.dia)
       group by 1, 2
    ),
    vig as (
      select v.payee_id, v.dia - (extract(isodow from v.dia)::int - 1) as seg,
             count(*) filter (where v.tipo <> 'reserva') as comp, count(*) filter (where v.tipo = 'reserva') as res
        from public.agenda_alocacoes v
       where v.estado in ('publicada', 'fixada') and v.presenca = 'turno' and not (v.id = any (v_canc))
         and v.dia between v_d1 and v_d2
       group by 1, 2
    )
    select jsonb_agg(jsonb_build_object('regra', 6, 'pessoa', nov.nome, 'dia', nov.seg,
             'texto', case when nov.comp > 0 and coalesce(vig.comp, 0) + nov.comp
                                  > case when v_acima or nov.fixar then floor(coalesce(esp.e, 0)) else floor(cf.carga_max * coalesce(esp.e, 0)) end
                           then format('%s passaria do limite da semana de %s: %s meios-dias de serviço para %s.', nov.nome,
                                       to_char(nov.seg, 'DD/MM'), coalesce(vig.comp, 0) + nov.comp,
                                       case when v_acima or nov.fixar then floor(coalesce(esp.e, 0))::int
                                            else floor(cf.carga_max * coalesce(esp.e, 0))::int end)
                           else format('%s passaria da semana inteira de %s: %s meios-dias com as reservas para %s.', nov.nome,
                                       to_char(nov.seg, 'DD/MM'), coalesce(vig.comp, 0) + nov.comp + coalesce(vig.res, 0) + nov.res,
                                       floor(coalesce(esp.e, 0))::int) end)
             order by nov.seg, nov.nome)
      from nov
      left join esp on esp.payee_id = nov.payee_id and esp.seg = nov.seg
      left join vig on vig.payee_id = nov.payee_id and vig.seg = nov.seg
     where (nov.comp > 0 and coalesce(vig.comp, 0) + nov.comp
              > case when v_acima or nov.fixar then floor(coalesce(esp.e, 0)) else floor(cf.carga_max * coalesce(esp.e, 0)) end)
        or coalesce(vig.comp, 0) + nov.comp + coalesce(vig.res, 0) + nov.res > floor(coalesce(esp.e, 0))), '[]'::jsonb);
  -- FASE 6: a regra 6 de antes não roda mais (fica para a conferência da cópia)
  end if;
  -- FASE 6: fim
  -- FASE 7: (7a P5) o fim do "senão" de cima: sem o portão do teto da equipe, a regra 6 da Fase 6, como antes
  end if;
  -- FASE 7: fim

  -- FASE 7b: (7b P4, §5.3, AG7-08) com modo_sabado ligado, a manhã de sábado que a pessoa ofereceu (livre na grade) soma 1 aos dois
  -- tetos da semana dela — o do compromisso e o da semana inteira — e, com o teto da equipe do 7a, ao da equipe: a mesma conta do
  -- encaixe na tentativa com o sábado. A regra 6 é refeita assim (o texto não muda); sem sábado oferecido na grade, a de cima.
  if cf.modo_sabado = 'ligado' and jsonb_array_length(v_n) > 0
     and exists (select 1 from jsonb_to_recordset(v_cap) as k(dia date, turno text, situacao text)
                  where extract(isodow from k.dia) = 6 and k.turno = 'manha' and k.situacao = 'livre') then
    v_7b_teq := public._agenda_gestor_regra('teto_equipe');
    v_v := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_v) with ordinality t(e, o) where e ->> 'regra' <> '6'),
                    '[]'::jsonb);
    v_v := v_v || coalesce((
      with nov as (
        select n.payee_id, min(n.nome) as nome, n.dia - (extract(isodow from n.dia)::int - 1) as seg,
               count(*) filter (where n.tipo <> 'reserva') as comp, count(*) filter (where n.tipo = 'reserva') as res,
               bool_and(n.fixar_dono) as fixar,
               case when v_7b_teq and n.payee_id is distinct from v_dono then 1::numeric
                    else public._agenda_carga_da_pessoa(n.payee_id) end as carga
          from jsonb_to_recordset(v_n) as n(payee_id uuid, nome text, dia date, presenca text, tipo text, fixar_dono boolean)
         where n.presenca = 'turno'
         group by n.payee_id, 3
      ),
      esp as (
        select k.payee_id, k.dia - (extract(isodow from k.dia)::int - 1) as seg, sum(k.meios_esperados) as e
          from jsonb_to_recordset(v_cap) as k(payee_id uuid, dia date, meios_esperados numeric)
         where public.agenda_dia_util(k.dia)
         group by 1, 2
      ),
      bon as (
        select k.payee_id, k.dia - (extract(isodow from k.dia)::int - 1) as seg, count(*) as b
          from jsonb_to_recordset(v_cap) as k(payee_id uuid, dia date, turno text, situacao text)
         where extract(isodow from k.dia) = 6 and k.turno = 'manha' and k.situacao = 'livre'
         group by 1, 2
      ),
      vig as (
        select v.payee_id, v.dia - (extract(isodow from v.dia)::int - 1) as seg,
               count(*) filter (where v.tipo <> 'reserva') as comp, count(*) filter (where v.tipo = 'reserva') as res
          from public.agenda_alocacoes v
         where v.estado in ('publicada', 'fixada') and v.presenca = 'turno' and not (v.id = any (v_canc))
           and v.dia between v_d1 and v_d2
         group by 1, 2
      ),
      lim as (
        select nov.*, coalesce(vig.comp, 0) as vcomp, coalesce(vig.res, 0) as vres,
               case when v_acima or nov.fixar then floor(coalesce(esp.e, 0)) else floor(nov.carga * coalesce(esp.e, 0)) end
                 + coalesce(bon.b, 0) as lc,
               floor(coalesce(esp.e, 0)) + coalesce(bon.b, 0) as lt
          from nov
          left join esp on esp.payee_id = nov.payee_id and esp.seg = nov.seg
          left join vig on vig.payee_id = nov.payee_id and vig.seg = nov.seg
          left join bon on bon.payee_id = nov.payee_id and bon.seg = nov.seg
      )
      select jsonb_agg(jsonb_build_object('regra', 6, 'pessoa', lim.nome, 'dia', lim.seg,
               'texto', case when lim.comp > 0 and lim.vcomp + lim.comp > lim.lc
                             then format('%s passaria do limite da semana de %s: %s meios-dias de serviço para %s.', lim.nome,
                                         to_char(lim.seg, 'DD/MM'), lim.vcomp + lim.comp, lim.lc::int)
                             else format('%s passaria da semana inteira de %s: %s meios-dias com as reservas para %s.', lim.nome,
                                         to_char(lim.seg, 'DD/MM'), lim.vcomp + lim.comp + lim.vres + lim.res, lim.lt::int) end)
               order by lim.seg, lim.nome)
        from lim
       where (lim.comp > 0 and lim.vcomp + lim.comp > lim.lc) or lim.vcomp + lim.comp + lim.vres + lim.res > lim.lt), '[]'::jsonb);
    if v_7b_teq and not v_acima then
      -- (7e P4, §5.3, R7.5-13) a consulta de baixo é a de sempre; com a folga ligada, ela roda uma vez por semana, com só aquela semana em v_n e a carga dela em cf.carga_max (os 2 pontos do teto). Com só urgência, uma volta com as urgentes fora da soma. Fora de ligado, uma volta, sem nada trocado.
      for v_7e_i in 1 .. case when v_7e_fs then coalesce(cardinality(v_7e_sem), 0) else 1 end loop
        if v_7e_nb is not null then
          v_n := case when v_7e_fs then coalesce((select jsonb_agg(e) from jsonb_array_elements(v_7e_nb) e where (e ->> 'dia')::date - (extract(isodow from (e ->> 'dia')::date)::int - 1) = v_7e_sem[v_7e_i]), '[]'::jsonb) else v_7e_nb end;
          if v_7e_fs then
            cf.carga_max := (public._agenda_carga_da_semana(v_7e_sem[v_7e_i]) ->> 'carga')::numeric;
          end if;
        end if;
      -- (7e: fim)
      v_v := v_v || coalesce((
        with eq as (
          select distinct k.payee_id from jsonb_to_recordset(v_cap) as k(payee_id uuid) where k.payee_id is distinct from v_dono
        ),
        nov as (
          select n.dia - (extract(isodow from n.dia)::int - 1) as seg,
                 count(*) filter (where n.tipo <> 'reserva' and not n.fixar_dono) as comp
            from jsonb_to_recordset(v_n) as n(payee_id uuid, dia date, presenca text, tipo text, fixar_dono boolean)
           where n.presenca = 'turno' and n.payee_id in (select eq.payee_id from eq)
           group by 1
        ),
        esp as (
          select k.dia - (extract(isodow from k.dia)::int - 1) as seg, sum(k.meios_esperados) as e
            from jsonb_to_recordset(v_cap) as k(payee_id uuid, dia date, meios_esperados numeric)
           where public.agenda_dia_util(k.dia) and k.payee_id is distinct from v_dono
           group by 1
        ),
        bon as (
          select k.dia - (extract(isodow from k.dia)::int - 1) as seg, count(*) as b
            from jsonb_to_recordset(v_cap) as k(payee_id uuid, dia date, turno text, situacao text)
           where extract(isodow from k.dia) = 6 and k.turno = 'manha' and k.situacao = 'livre' and k.payee_id is distinct from v_dono
           group by 1
        ),
        vig as (
          select v.dia - (extract(isodow from v.dia)::int - 1) as seg, count(*) as comp
            from public.agenda_alocacoes v
           where v.estado in ('publicada', 'fixada') and v.presenca = 'turno' and v.tipo <> 'reserva'
             and not (v.id = any (v_canc)) and v.dia between v_d1 and v_d2
             and v.payee_id in (select eq.payee_id from eq)
           group by 1
        )
        select jsonb_agg(jsonb_build_object('regra', 6, 'pessoa', null, 'dia', nov.seg,
                 'texto', format('A equipe passaria do limite da semana de %s: %s meios-dias de serviço para %s.',
                                 to_char(nov.seg, 'DD/MM'), coalesce(vig.comp, 0) + nov.comp,
                                 floor(cf.carga_max * coalesce(esp.e, 0))::int + coalesce(bon.b, 0)::int))
                 order by nov.seg)
          from nov
          left join esp on esp.seg = nov.seg
          left join vig on vig.seg = nov.seg
          left join bon on bon.seg = nov.seg
         where nov.comp > 0 and coalesce(vig.comp, 0) + nov.comp > floor(cf.carga_max * coalesce(esp.e, 0)) + coalesce(bon.b, 0)), '[]'::jsonb);
      -- (7e P4) o fim do laço de cima: v_n e cf.carga_max voltam ao que eram
      end loop;
      if v_7e_nb is not null then
        v_n := v_7e_np;
        cf.carga_max := v_7e_cm;
      end if;
      -- (7e: fim)
    end if;
  end if;
  -- FASE 7b: fim
  -- FASE 7e: (7e P4, §5.3 (c), R7.7) as alocações voltam a ser as de verdade (a urgente não é pedido do dono na regra 7 nem na 11). A exceção da regra 7, estreita: só o que criar da OS puxada, no dia e de quem o puxar diz (a célula livre, a regra 1 confere; o que já começou continua recusado; cancelar no congelado nunca).
  -- E a ponta do dono (abrir e fechar) dela nesse dia: o motor só tira o turno de quem está fora de puxar.pessoas, e a ponta dele segue livre. Sem isto, a OS "abre e fecha" (8 de 10 da carteira) lançava (conferência do P4b).
  if v_7e_n0 is not null then
    v_n := v_7e_n0;
  end if;
  if jsonb_typeof(v_7e_pux) = 'object' and jsonb_array_length(v_n) > 0 then
    select jsonb_agg(e || case when e ->> 'os' = v_7e_pux ->> 'os' and (e ->> 'dia')::date = (v_7e_pux ->> 'dia')::date and e ->> 'tipo' <> 'reserva'
                                    and ((v_7e_pux -> 'pessoas') ? (e ->> 'payee_id')
                                         or ((e ->> 'payee_id')::uuid = v_dono and e ->> 'presenca' in ('abertura', 'fechamento')))
                               then '{"evento_real": true}'::jsonb else '{}'::jsonb end order by (e ->> 'r')::int)
      into v_n from jsonb_array_elements(v_n) e;
  end if;
  -- FASE 7e: fim
  -- (7) Nada novo no congelado (hoje + o próximo dia útil), salvo o evento real e o pedido do dono; nunca no que já
  -- passou ou começou.
  v_v := v_v || coalesce((
    select jsonb_agg(jsonb_build_object('regra', 7, 'os', n.os, 'numero', n.numero, 'pessoa', n.nome, 'dia', n.dia, 'turno', n.turno,
             'texto', case when lower(public.agenda_periodo(n.dia, n.turno, n.presenca)) <= p_agora
                           then format('%s %s: esse meio-dia já começou.', n.numero, public._agenda_meio_texto(n.dia, n.turno))
                           else format('%s %s: hoje e amanhã ficam como estão.', n.numero, public._agenda_meio_texto(n.dia, n.turno)) end)
             order by n.r)
      from jsonb_to_recordset(v_n) as n(r int, os uuid, numero text, nome text, dia date, turno text, presenca text,
                                         evento_real boolean, fixar_dono boolean)
     where lower(public.agenda_periodo(n.dia, n.turno, n.presenca)) <= p_agora
        or (n.dia <= v_cong and not (n.evento_real or n.fixar_dono))), '[]'::jsonb);

  -- (8) O fixado só sai com item autorizado (a violação registrada, o pedido do dono ou a decisão); o que vai sair tem
  -- de continuar em vigor e sem resultado.
  v_v := v_v || coalesce((
    select jsonb_agg(jsonb_build_object('regra', 8, 'os', i ->> 'os', 'numero', i ->> 'numero', 'dia', a.dia, 'turno', a.turno,
             'texto', case when a.estado not in ('publicada', 'fixada') or a.resultado is not null
                           then format('%s %s: esse meio-dia mudou desde que eu montei.', i ->> 'numero', public._agenda_meio_texto(a.dia, a.turno))
                           else format('%s %s: está fixado e só sai com a sua decisão.', i ->> 'numero', public._agenda_meio_texto(a.dia, a.turno)) end)
             order by a.dia, a.turno, a.id)
      from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) i
      cross join jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) x
      join public.agenda_alocacoes a on a.id = (x ->> 'alocacao_id')::uuid
     where i ->> 'op' = 'cancelar'
       and (a.estado not in ('publicada', 'fixada') or a.resultado is not null
            or (a.estado = 'fixada' and not (coalesce((i ->> 'violada')::boolean, false) or i ->> 'motivo' = 'dono'
                                              or i ->> 'decisao' is not null)))), '[]'::jsonb);

  -- (9) a OS na carteira; (10) classe 4 nunca; (11) reserva condicionada não vira compromisso sem a condição.
  for v_os in select distinct (e ->> 'os')::uuid from jsonb_array_elements(v_n) e where e ->> 'tipo' <> 'reserva' order by 1 loop
    if not (v_os = any (v_cart)) then
      v_v := v_v || jsonb_build_object('regra', 9, 'os', v_os, 'numero', v_pr -> v_os::text ->> 'numero',
               'texto', format('%s não está na carteira (%s).', v_pr -> v_os::text ->> 'numero', v_pr -> v_os::text ->> 'estado_texto'));
      continue;
    end if;
    v_cl := public._agenda_classe_da_os(v_pr -> v_os::text, v_meios -> v_os::text, p_hoje,
              exists (select 1 from public.agenda_alocacoes a
                       where a.service_order_id = v_os and a.estado = 'fixada' and a.tipo <> 'reserva' and a.dia >= p_hoje
                         and a.resultado is null and not (a.id = any (v_canc))), false);
    if (v_cl ->> 'classe')::int = 4 then
      v_v := v_v || jsonb_build_object('regra', 10, 'os', v_os, 'numero', v_pr -> v_os::text ->> 'numero',
               'texto', format('%s ainda não pode entrar na agenda: %s.', v_pr -> v_os::text ->> 'numero', v_cl ->> 'texto'));
    elsif (v_cl ->> 'classe')::int = 3 and not exists (select 1 from jsonb_array_elements(v_n) e
                                                         where (e ->> 'os')::uuid = v_os and (e ->> 'fixar_dono')::boolean) then
      v_v := v_v || jsonb_build_object('regra', 11, 'os', v_os, 'numero', v_pr -> v_os::text ->> 'numero',
               'texto', format('%s só pode ser reserva até: %s.', v_pr -> v_os::text ->> 'numero', v_cl ->> 'texto'));
    end if;
  end loop;

  -- (12) No máximo wip_max serviços por meio-dia.
  v_v := v_v || coalesce((
    with meio as (select distinct n.dia, n.turno from jsonb_to_recordset(v_n) as n(dia date, turno text)),
    os as (
      select m.dia, m.turno, x.os
        from meio m
        cross join lateral (
          select v.service_order_id as os from public.agenda_alocacoes v
           where v.estado in ('publicada', 'fixada') and not (v.id = any (v_canc)) and v.dia = m.dia and v.turno = m.turno
          union
          select n.os from jsonb_to_recordset(v_n) as n(os uuid, dia date, turno text) where n.dia = m.dia and n.turno = m.turno) x
    )
    select jsonb_agg(jsonb_build_object('regra', 12, 'dia', o.dia, 'turno', o.turno,
             'texto', format('Mais de %s serviços %s.', cf.wip_max, public._agenda_meio_texto(o.dia, o.turno))) order by o.dia, o.turno)
      from (select os.dia, os.turno from os group by 1, 2 having count(distinct os.os) > cf.wip_max) o), '[]'::jsonb);

  -- (14) Item crítico só com a decisão do dono (a pergunta crítica respondida, com a opção escolhida).
  if p_aplicar then
    v_v := v_v || coalesce((
      select jsonb_agg(jsonb_build_object('regra', 14, 'os', i ->> 'os', 'numero', i ->> 'numero',
               'texto', format('%s espera a sua decisão.', i ->> 'numero')) order by k)
        from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) with ordinality t(i, k)
       where i ->> 'critica' is not null
         and not exists (select 1 from public.agenda_perguntas p
                          where p.id = nullif(i ->> 'decisao', '')::uuid and p.critica and p.estado = 'respondida'
                            and p.opcao_escolhida is not null)), '[]'::jsonb);
  end if;

  return coalesce((select jsonb_agg(e order by (e ->> 'regra')::int, o) from jsonb_array_elements(v_v) with ordinality t(e, o)),
                  '[]'::jsonb);
end;
$function$;

comment on function public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb) is
  'Agenda de Produção (Fase 2, P2): as 14 regras duras sobre os itens (criar e cancelar) de uma proposta, contra o banco de agora — (1) pessoa ativa e livre no turno (a ponta livre na presença curta, sem compromisso com hora), sem feriado; (2) sem choque com o vigente nem dentro da proposta; (3) não antes do dia em que fica pronta; (4) a presença do dono conforme a regra; (5) alguém em cada meio-dia; (6) o teto por pessoa e semana; (7) nada no congelado (salvo evento real e pedido do dono) nem no que começou; (8) o fixado só sai autorizado; (9) a OS na carteira; (10) classe 4 nunca; (11) reserva condicionada não vira compromisso; (12) wip_max por meio-dia; (13) no máximo interrupcoes_max dias parados; (14) com p_aplicar, item crítico só com a pergunta respondida. Lista vazia = ok; cada violação {regra, os, numero, pessoa, dia, turno, texto}. FASE 6 (P4): a regra 6 usa a carga de cada pessoa (_agenda_carga_da_pessoa: o dono com capacidade_dono em uso; os outros, carga_max) no lugar de carga_max; o texto não muda. FASE 7 (7a P5), atrás do portão _agenda_gestor_regra(''teto_equipe''): a regra 6 faz a conta do encaixe — o compromisso de cada pessoa da equipe até 100% do esperado (o dono com o teto dele; a semana inteira com as reservas e o texto não mudam) e, por semana, a soma da equipe (as pessoas da grade menos o dono; o vigente menos o cancelado + o novo, sem reserva e sem o pedido do dono) até floor(carga_max × a soma do esperado dela): "A equipe passaria do limite da semana de 09/11: 11 meios-dias de serviço para 10." (pessoa nula). Só confere a semana com compromisso novo da equipe fora do pedido do dono; com acima_da_carga, sem a conta da equipe. Sem o portão, a regra 6 da Fase 6. FASE 7 (7a P12; AG7-08): com a variável agenda.sabado = on (só a decisão 1 da pergunta crítica sabado a liga, na transação dela) e sabado_manha diferente de nunca, o meio-dia de turno na manhã de um sábado sem feriado, de quem tem o padrão de sábado de manhã e que a grade dá como fim de semana, não viola a regra 1 (a mesma conta do gancho do sábado de _agenda_contexto). Sem a variável, a de antes. FASE 7b (P4, R4.4 e §5.3): o gancho da pessoa a mais (R4.4, inerte sem a variável) — com agenda.pessoa_extra = tecnico, a "mais uma pessoa" (_agenda_pessoa_extra_id) entra na grade lida aqui livre nas manhãs e tardes de todo dia útil: não viola a regra 1 e a regra 6 (e a soma da equipe) a contam com a semana inteira; e, com modo_sabado ligado e alguma manhã de sábado livre na grade (a que a pessoa ofereceu), a regra 6 é refeita somando essas manhãs aos dois tetos da semana da pessoa (o compromisso e a semana inteira) e, com o teto da equipe do 7a, ao da equipe — a conta do encaixe na tentativa com o sábado; o texto não muda. Sem a variável e sem o sábado, a de antes, byte a byte. FASE 7d (P4, R6.9-3): com modo_local_calendario ligado por _agenda_local_modo, a regra 3 soma a máscara do local (nada, fora a reserva e o pedido do dono, num dia ou meio-dia que o local não recebe; o texto, o motivo da máscara sem o parêntese) e a regra 13 não conta o dia fechado como parado (o motor o pula). Fora de ligado, a de antes, byte a byte. FASE 7e (P4): a regra 6 com a carga de cada semana (a mesma função que o motor lê) e até 100% para as OS de p_restricoes.urgentes; a regra 7 aceita o criar da OS de p_restricoes.puxar no dia e de quem o puxar diz, e a ponta do dono (abrir e fechar) dela nesse dia. Sem essas chaves e fora de ligado, a de antes.';

-- agenda_propor (de 20261107100800_agenda_fase7d_correcao.sql:568; md5 do corpo de antes a73e1651cb875d4a978822f9f2a9e8b8)
create or replace function public.agenda_propor(
  p_escopo     text,
  p_de         date        default null,
  p_ate        date        default null,
  p_os         uuid[]      default null,
  p_restricoes jsonb       default '{}'::jsonb,
  p_persistir  boolean     default false,
  p_origem     text        default 'motor',
  p_autor      uuid        default null,
  p_hoje       date        default public._hoje_brt(),
  p_agora      timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  -- Os pesos da pontuação (plano §4.4, os do Timefold): estrutura para comparar alternativas, não parâmetro do dono.
  c_peso_atraso  constant int := 1000000;
  c_peso_mudanca constant int := 100;
  c_peso_dono    constant int := 10;
  c_peso_interr  constant int := 50;
  c_peso_fim     constant int := 1;
  -- "atrasar" leva a OS para o fim da classe: a ordem dela passa à frente de qualquer posição real da fila.
  c_fim_da_classe constant int := 1000000;
  -- quantas OS que X empurraria entram na pergunta "não cabe" (as mais próximas dela na fila)
  c_candidatas   constant int := 3;
  cf        public.agenda_config;
  v_r       jsonb := coalesce(p_restricoes, '{}'::jsonb);
  v_modo    text;
  v0        bigint;
  v_cong    date;
  v_seg     date;
  v_de      date;
  v_ate     date;
  v_hor     date;
  v_ini     date;
  v_fim     date;
  v_cart    uuid[];
  v_cartj   jsonb;
  v_escopo  uuid[];
  v_tirar   uuid[];
  v_atrasar uuid[];
  v_aceitar uuid[];
  v_acima   boolean;
  v_decisao uuid;
  v_fixar   jsonb;
  v_depois  jsonb;
  v_info    jsonb := '{}'::jsonb;
  v_canc    jsonb;
  v_ign     uuid[];
  v_fila_os uuid[];
  v_ctx     jsonb;
  v_pes     uuid[];
  v_fila    jsonb := '[]'::jsonb;
  v_ent     jsonb;
  v_par     jsonb;
  v_parh    jsonb;
  v_r0      jsonb;
  v_rf      jsonb;
  v_ctxf    jsonb;
  v_base    jsonb;
  v_sim     jsonb;
  v_minh_n  int;
  v_minh_a  int;
  v_os      uuid;
  v_i       int;
  v_e       jsonb;
  v_b       jsonb;
  v_pront   jsonb;
  v_meios   jsonb;
  v_pl      record;
  v_status  text;
  v_k       record;
  v_cl      jsonb;
  v_classe  int;
  v_fx      jsonb;
  v_fp      int;
  v_evento  boolean;
  v_passos  int;
  v_abre    boolean;
  v_fecha   boolean;
  v_dtm     boolean;
  v_dtt     boolean;
  v_fixa    int;
  v_pm      int[];
  v_pt      int[];
  v_est     date;
  v_estc    date;
  v_minh    int;
  v_bem     int[];
  v_pat_p   int;
  v_pat_b   int[];
  v_bem_tudo boolean;
  v_fora    jsonb := '[]'::jsonb;
  v_crit    jsonb := '{}'::jsonb;
  v_xnc     int[] := '{}';
  v_xoc     int[] := '{}';
  v_cands   jsonb := '{}'::jsonb;
  v_h       int[] := '{}';
  v_sem_q   int[] := '{}';
  v_tentativa int;
  v_usadas  jsonb;
  v_perg    jsonb := '[]'::jsonb;
  v_held    jsonb := '[]'::jsonb;
  v_itens   jsonb := '[]'::jsonb;
  v_opc     jsonb;
  v_rec     int;
  v_rec_txt text;
  v_txt     text;
  v_chave   text;
  v_tipo    text;
  v_fim_x   date;
  v_ini_x   date;
  v_fim_c   date;
  v_ini_c   date;
  v_x       int;
  v_c       int;
  v_cb      jsonb;
  v_xb      jsonb;
  v_canc_os uuid[];
  v_ini_antes date;
  v_fim_dep date;
  v_carga   jsonb;
  v_textos  jsonb;
  v_linhas  text[];
  v_tfora   text[];
  v_titulo  text;
  v_texto   text;
  v_pont    jsonb;
  v_viol    jsonb;
  v_pid     uuid;
  v_expira  timestamptz;
  v_dono    uuid := public._agenda_dono(null);
  v_feriados text[];
  v_q       jsonb;
  v_n       int;
  v_aviso   text;
  -- CORREÇÃO 29/10 (P3): a reserva da própria OS no encaixe do compromisso dela (res_propria) e o resumo que separa o
  -- marcado firme do reservado
  v_rp       int[];
  v_marc     text[];
  v_resv     text[];
  v_contagem text;
  -- CORREÇÃO 29/10 (P3): fim
  -- FASE 7: (7a P8) a zona travada: o que fica fora da conta do dia já avisado
  v_f7_fora uuid[];
  -- FASE 7: fim
  -- FASE 7b: (7b P4) a dupla por meio-dia, o prazo firme, o sábado e as linhas em teste
  v_7b_pk     int[];
  v_7b_dk     int[];
  v_7b_tot    int;
  v_7b_prazo  date;
  v_7b_n      int;
  v_7b_semtec int;
  v_7b_tec    text[];
  v_7b_teste  text[] := '{}';
  v_7b_b      jsonb;
  v_7b_e      jsonb;
  v_7b_x      text;
  v_7b_y      text;
  v_7b_dias   date[];
  v_7b_nomes  text[];
  v_7b_z      text;
  v_7b_n2     int;
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achados 22 e 23) o exemplo com todos os dias e a dupla dita antes de a OS ficar pronta
  v_7bc_dias date[];
  v_7bc_est  date;
  v_7bc_max  date;
  -- FASE 7b: fim
  -- FASE 7c: (7c P2) o que a OS pede, o responsável, os motivos e os textos da 7c
  v_7c_exg   jsonb;
  v_7c_ld    jsonb;
  v_7c_lp    int;
  v_7c_mot   text[];
  v_7c_txt   text;
  v_7c_d     int;
  v_7c_le    boolean;
  -- FASE 7c: fim
  -- FASE 7c: (7c correção, achado 9) a troca avisada do responsável no texto do item
  c_c9_max   constant int := 320;   -- estrutural: o item com a frase a mais (o texto da ação junta os itens da OS em até 400)
  v_c9_tr    text;
  v_c9_txt   text;
  -- FASE 7c: fim
  -- FASE 7d: (7d P4, §5.4, R6.7b, R6.8-1) os modos da 7d (por _agenda_local_modo: ligado com *gestor, só propor* = em teste) e, por OS da fila, o local
  -- (v_7d_lr), a máscara (v_7d_lm), a viagem (v_7d_vi), o bem (v_7d_bm), a suposição do abre e fecha (v_7d_saf) e as suposições do item
  v_7d_cal   boolean;
  v_7d_pat   boolean;
  v_7d_via   boolean;
  v_7d_ml    boolean;
  v_7d_bem   boolean;
  v_7d_lr    jsonb;
  v_7d_lm    jsonb;
  v_7d_vi    jsonb;
  v_7d_bm    jsonb;
  v_7d_saf   boolean;
  v_7d_sup   text[];
  v_7d_extra int;
  v_7d_x     int;
  v_7d_os    uuid;
  -- FASE 7d: fim
  -- FASE 7d: (correção O15) o feriado do município no texto do item
  v_7d_dt  text;
  v_7d_mf  text;
  -- FASE 7d: fim
  -- FASE 7e: (7e P4, §5.3, R7.5-14, R7.7) a urgência, a carga da semana na frase do item e a OS puxada
  v_7e_ug    boolean;
  v_7e_u     jsonb;
  v_7e_urg   jsonb := '[]'::jsonb;
  v_7e_cm    numeric;
  v_7e_pux   jsonb;
  v_7e_dp    date;
  v_7e_m     text[];
  v_7e_pas   boolean;
  -- FASE 7e: fim
begin
  -- ── 0. Entrada ──
  if p_escopo is null or p_escopo not in ('semana', 'os', 'replano') then
    raise exception 'Escopo desconhecido: "%" (semana, os ou replano).', coalesce(p_escopo, '') using errcode = '22023';
  end if;
  if p_origem is null or p_origem not in ('motor', 'vigia', 'dono', 'assistente', 'tela', 'aprovacao') then
    raise exception 'Origem desconhecida: "%".', coalesce(p_origem, '') using errcode = '22023';
  end if;
  if p_hoje is null or p_agora is null or jsonb_typeof(v_r) <> 'object' then
    raise exception 'Faltam o dia, a hora ou as restrições do plano.' using errcode = '22023';
  end if;
  if p_escopo in ('os', 'replano') and coalesce(cardinality(p_os), 0) = 0 then
    raise exception 'Diga de que OS é o plano.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  if p_persistir then
    perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  end if;
  cf := public._agenda_cfg();
  v_modo := cf.modo_proposta;
  if p_persistir and v_modo = 'desligado' then
    return jsonb_build_object('ok', false, 'simulacao', false, 'texto', 'A agenda automática está desligada: não monto o plano.');
  end if;
  -- FASE 7d: (7d P4, R6.7b) todo leitor de modo usa _agenda_local_modo, nunca cf.modo_x
  v_7d_cal := public._agenda_local_modo('calendario') = 'ligado';
  v_7d_pat := public._agenda_local_modo('patio') = 'ligado';
  v_7d_via := public._agenda_local_modo('viagem') = 'ligado';
  v_7d_ml := public._agenda_local_modo('mesmo_local') = 'ligado';
  v_7d_bem := public._agenda_local_modo('bem') = 'ligado';
  -- FASE 7d: fim
  -- FASE 7e: (7e P4, §5.3, R7.6, R7.8, R7.12-10) o portão: com a urgência fora de ligado ou com o freio, nenhuma chamada nova e nenhuma chave. Quem decide é _agenda_margem_modo. A lista de urgentes é só o motor quem faz: a que vier de fora sai (ela levaria o validador a 100%). A OS puxada (P4b) chega em puxar.
  v_7e_ug := case when cf.modo_urgencia = 'ligado' and not cf.gestor_so_propor then public._agenda_margem_modo('urgencia') = 'ligado' else false end;
  v_7e_cm := cf.carga_max;
  v_r := v_r - 'urgentes';
  v_7e_pux := v_r -> 'puxar';
  v_7e_dp := (v_7e_pux ->> 'dia')::date;
  -- FASE 7e: fim
  v0 := cf.versao_plano;
  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);

  -- ── 1. A janela ──
  v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1);
  if p_escopo = 'semana' then
    v_de := coalesce(p_de, public.agenda_somar_du(v_seg + 7, 0));
    v_ate := coalesce(p_ate, v_seg + 7 + 5);
  else
    v_de := coalesce(p_de, public.agenda_somar_du(v_cong, 1));
    v_ate := coalesce(p_ate, v_de + 7 * cf.horizonte_semanas);
  end if;
  if v_ate < v_de then
    raise exception 'O período do plano termina antes de começar (% a %).', v_de, v_ate using errcode = '22023';
  end if;
  v_hor := greatest(p_hoje + 7 * cf.horizonte_semanas, v_ate);
  v_ini := v_seg;
  v_fim := v_hor + (7 - extract(isodow from v_hor)::int);

  -- ── Restrições (ids e datas já resolvidos por quem chama) ──
  v_tirar := array(select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'tirar', '[]'::jsonb)) x);
  v_atrasar := array(select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'atrasar', '[]'::jsonb)) x);
  v_aceitar := array(select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'aceitar_atraso', '[]'::jsonb)) x);
  v_acima := coalesce((v_r ->> 'acima_da_carga')::boolean, false);
  v_decisao := nullif(v_r ->> 'decisao', '')::uuid;
  if exists (select 1 from jsonb_array_elements(coalesce(v_r -> 'fixar', '[]'::jsonb)) e
              where e ->> 'os' is null or e ->> 'de' is null) then
    raise exception 'fixar precisa da OS e do dia.' using errcode = '22023';
  end if;
  select coalesce(jsonb_object_agg(e ->> 'os', jsonb_build_object('de', e -> 'de', 'ate', coalesce(e -> 'ate', e -> 'de'),
                                                                  'pessoa', e -> 'pessoa')), '{}'::jsonb)
    into v_fixar from jsonb_array_elements(coalesce(v_r -> 'fixar', '[]'::jsonb)) e;
  select coalesce(jsonb_object_agg(e ->> 'os', e -> 'dia'), '{}'::jsonb)
    into v_depois from jsonb_array_elements(coalesce(v_r -> 'so_depois_de', '[]'::jsonb)) e;

  -- ── 2. A carteira, o escopo e o que se sabe de cada OS ──
  select coalesce(array_agg(k.service_order_id order by k.numero collate "C", k.service_order_id), '{}'::uuid[]),
         coalesce(jsonb_object_agg(k.service_order_id::text, jsonb_build_object('sinal', k.sinal_pago > 0, 'aprovada_em', k.aprovada_em)), '{}'::jsonb)
    into v_cart, v_cartj
    from public.os_carteira(p_hoje) k;
  if p_escopo = 'semana' then
    v_escopo := v_cart;
  else
    v_escopo := array(select distinct x from unnest(p_os) x order by 1);
  end if;
  for v_os in
    select x from (select unnest(v_escopo) as x
                   union
                   select a.service_order_id from public.agenda_alocacoes a
                    where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
                      and p_escopo = 'semana' and not (a.service_order_id = any (v_cart))) q
     order by 1
  loop
    v_info := v_info || jsonb_build_object(v_os::text, jsonb_build_object(
                'pront', public.os_prontidao(v_os, p_hoje), 'meios', public.agenda_meios_da_os(v_os, p_hoje)));
  end loop;

  -- ── 3. Estabilidade: o que não pode mais acontecer sai (e o pedido do dono tira o que a OS tinha) ──
  v_canc := public._agenda_violacoes(v_escopo, v_cart, p_escopo = 'semana', v_info, p_hoje, v_cong);
  v_canc := v_canc || coalesce((
    select jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'os', a.service_order_id, 'motivo', 'dono', 'violada', false,
             'congelado', a.dia <= v_cong, 'tipo', a.tipo, 'estado', a.estado, 'fixado_por', a.fixado_por,
             'reserva_de', a.reserva_de, 'payee_id', a.payee_id, 'dia', a.dia, 'turno', a.turno, 'presenca', a.presenca)
             order by a.service_order_id, a.dia, a.turno = 'tarde', a.payee_id, a.id)
      from public.agenda_alocacoes a
     where v_fixar ? a.service_order_id::text and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje
       and a.resultado is null and lower(a.periodo) > p_agora
       and not exists (select 1 from jsonb_array_elements(v_canc) c where (c ->> 'alocacao_id')::uuid = a.id)), '[]'::jsonb);
  v_ign := array(select (c ->> 'alocacao_id')::uuid from jsonb_array_elements(v_canc) c);

  -- ── 4. A grade e a fila ──
  v_fila_os := array(select x from unnest(v_escopo) x where not (x = any (v_tirar)) order by 1);
  v_ctx := public._agenda_contexto(v_ini, v_fim, p_hoje, v_ign, v_fila_os);
  v_pes := array(select x::uuid from jsonb_array_elements_text(v_ctx -> 'pessoas') x);
  -- FASE 7e: (7e P4, §5.3 (b)) com puxar, as células do dia de quem não está em puxar.pessoas ficam sem capacidade: o turno da OS puxada só cai em quem já vem. A ponta do dono (abrir e fechar) não muda, e o validador a aceita. Sem puxar, nada muda.
  if v_7e_dp is not null then
    v_ctx := jsonb_set(v_ctx, '{cap}', (
      select jsonb_agg(case when ((t.o - 1) % n.nh) / 2 + 1 = v_7e_dp - v_ini + 1
                             and not ((v_7e_pux -> 'pessoas') ? (v_ctx -> 'pessoas' ->> ((t.o - 1) / n.nh)::int))
                            then 0 else t.x::int end order by t.o)
        from jsonb_array_elements_text(v_ctx -> 'cap') with ordinality t(x, o)
        cross join (select (v_ctx ->> 'nh')::bigint as nh) n));
  end if;
  -- FASE 7e: fim
  -- o 1º meio-dia que dá: depois do congelado; e, para o evento real e o pedido do dono, o 1º que ainda não começou
  v_minh_n := 2 * (v_cong + 1 - v_ini) + 1;
  v_minh_a := case when lower(public.agenda_periodo(p_hoje, 'manha')) > p_agora then 2 * (p_hoje - v_ini) + 1
                   when lower(public.agenda_periodo(p_hoje, 'tarde')) > p_agora then 2 * (p_hoje - v_ini) + 2
                   else 2 * (p_hoje + 1 - v_ini) + 1 end;

  for v_os in select unnest(v_tirar) loop
    if v_os = any (v_escopo) then
      v_fora := v_fora || jsonb_build_object('os', v_os, 'motivo', 'tirado', 'texto', public._agenda_rotulo_da_os(v_os) || ': você tirou.');
    end if;
  end loop;

  for v_i in 1 .. coalesce(cardinality(v_fila_os), 0) loop
    v_os := v_fila_os[v_i];
    v_pront := v_info -> v_os::text -> 'pront';
    v_meios := v_info -> v_os::text -> 'meios';
    select pl.* into v_pl from public.os_planejamento pl where pl.service_order_id = v_os;
    select so.status into v_status from public.service_orders so where so.id = v_os;
    -- o que fica do plano dela (sem o que a proposta cancela)
    select count(distinct (a.dia, a.turno)) filter (where a.tipo <> 'reserva' and a.dia >= p_hoje and a.resultado is null) as fut,
           coalesce(bool_or(a.tipo <> 'reserva' and a.resultado is distinct from 'nao_cumprido'), false) as algum,
           max(a.dia) filter (where a.tipo <> 'reserva' and a.resultado is distinct from 'nao_cumprido') as ultimo,
           max(a.dia) filter (where a.tipo <> 'reserva' and a.dia >= p_hoje and a.resultado is null) as ultimo_fut,
           coalesce(bool_or(a.tipo <> 'reserva' and a.estado = 'fixada' and a.dia >= p_hoje and a.resultado is null), false) as fixada,
           coalesce(bool_or(a.tipo = 'reserva' and a.reserva_de in ('teto', 'condicionada') and a.dia >= p_hoje), false) as reserva,
           coalesce(bool_or(a.tipo = 'reserva' and a.reserva_de = 'patio' and a.dia >= p_hoje), false) as patio
      into v_k
      from public.agenda_alocacoes a
     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and not (a.id = any (v_ign));
    v_bem_tudo := (v_pl.bem_indisponivel is not null and not isempty(v_pl.bem_indisponivel)
                   and not exists (select 1 from generate_series(p_hoje + 1, v_hor, interval '1 day') g
                                    where not (v_pl.bem_indisponivel @> g::date)))
                  or coalesce(v_pl.nao_antes_de > v_hor, false);
    v_cl := public._agenda_classe_da_os(v_pront, v_meios, p_hoje, v_k.fixada, v_bem_tudo);
    v_classe := (v_cl ->> 'classe')::int;
    v_fx := v_fixar -> v_os::text;
    if v_fx is not null then
      if v_classe = 4 then
        v_fora := v_fora || jsonb_build_object('os', v_os, 'motivo', 'fixar_recusado',
                   'texto', format('%s: %s.', public._agenda_rotulo_da_os(v_os), rtrim(v_cl ->> 'texto', '.')));
        continue;
      end if;
      v_classe := 1;
    end if;
    v_evento := exists (select 1 from jsonb_array_elements(v_canc) c
                         where (c ->> 'os')::uuid = v_os and (c ->> 'violada')::boolean
                           and ((c ->> 'congelado')::boolean or (v_cl ->> 'classe')::int = 1));
    v_passos := case when (v_meios ->> 'total') is null then 0
                     else ceil(greatest((v_meios ->> 'total')::numeric - coalesce((v_meios ->> 'cumpridos')::numeric, 0)
                                        - coalesce(v_k.fut, 0), 0))::int end;
    v_fecha := v_meios ->> 'presenca' = 'abre_e_fecha';
    v_abre := v_fecha and not v_k.algum and coalesce((v_meios ->> 'cumpridos')::numeric, 0) = 0 and v_status <> 'in_progress';
    v_dtm := coalesce((v_meios #>> '{dono_turno,manha}')::boolean, false);
    v_dtt := coalesce((v_meios #>> '{dono_turno,tarde}')::boolean, false);
    v_fixa := 0;
    if v_fx is not null and v_fx ->> 'pessoa' is not null then
      v_fp := array_position(v_pes, (v_fx ->> 'pessoa')::uuid);
      if v_fp is null then
        v_fora := v_fora || jsonb_build_object('os', v_os, 'motivo', 'fixar_recusado',
                   'texto', format('%s: essa pessoa não está na equipe de agora.', public._agenda_rotulo_da_os(v_os)));
        continue;
      elsif v_fp = (v_ctx ->> 'dono')::int then
        v_dtm := true; v_dtt := true; v_abre := false; v_fecha := false;
      else
        v_fixa := v_fp;
      end if;
    end if;
    v_pm := array(select array_position(v_pes, (e ->> 'payee_id')::uuid)
                    from jsonb_array_elements(coalesce(v_meios #> '{por_turno,manha,pessoas}', '[]'::jsonb)) with ordinality t(e, o)
                   where array_position(v_pes, (e ->> 'payee_id')::uuid) is not null order by o);
    v_pt := array(select array_position(v_pes, (e ->> 'payee_id')::uuid)
                    from jsonb_array_elements(coalesce(v_meios #> '{por_turno,tarde,pessoas}', '[]'::jsonb)) with ordinality t(e, o)
                   where array_position(v_pes, (e ->> 'payee_id')::uuid) is not null order by o);
    -- EST': o dia em que fica pronta, depois do congelado (o evento real e o pedido do dono podem usar o que ainda não
    -- começou), depois do "só depois de" e depois do que ela já tem marcado.
    if v_fx is not null then
      v_est := greatest((v_fx ->> 'de')::date, p_hoje);
      v_minh := v_minh_a;
    elsif v_evento then
      v_est := greatest(coalesce((v_pront #>> '{material,inicio_mat}')::date, p_hoje), v_pl.nao_antes_de, p_hoje,
                        (v_depois ->> v_os::text)::date, v_k.ultimo_fut);
      v_minh := v_minh_a;
    else
      v_est := greatest(coalesce((v_pront ->> 'est')::date, (v_pront ->> 'est_sem_material')::date, p_hoje),
                        public.agenda_somar_du(v_cong, 1), (v_depois ->> v_os::text)::date, v_k.ultimo_fut);
      v_minh := v_minh_n;
    end if;
    v_estc := greatest(coalesce((v_pront ->> 'est')::date, (v_pront ->> 'est_sem_material')::date, p_hoje),
                       public.agenda_somar_du(v_cong, 1), (v_depois ->> v_os::text)::date);
    v_bem := array(select g + 1 from generate_series(0, v_fim - v_ini) g
                    where coalesce(v_pl.bem_indisponivel @> (v_ini + g), false));
    -- o pátio: o que dá para adiantar sem o bem, enquanto ele está fora (dentro da janela)
    v_pat_p := 0;
    v_pat_b := '{}';
    if v_pl.adiantavel_patio_dias is not null and not v_k.patio and v_classe in (1, 2, 3) and v_passos > 0
       and exists (select 1 from generate_series(greatest(v_de, public.agenda_somar_du(v_cong, 1)), v_ate, interval '1 day') g
                    where coalesce(v_pl.bem_indisponivel @> g::date, false)) then
      v_pat_p := (v_pl.adiantavel_patio_dias * 2)::int;
      v_pat_b := array(select g + 1 from generate_series(0, v_fim - v_ini) g
                        where not coalesce(v_pl.bem_indisponivel @> (v_ini + g), false));
    end if;
    -- FASE 7d: (7d P4, §5.4 1, R6.8-1) o local no motor, só com calendario, patio, viagem ou mesmo_local ligado: em teste, nenhuma chamada. O dia que
    -- o local não recebe entra em v_bem; a entrada do bem, no EST; os dias desde a retirada, em v_bem. A viagem fora da região não tem abre e
    -- fecha; o custo dela em meios-dias entra no item da fila, lá embaixo, depois da dupla da 7b, que lê v_passos. Com modo_bem ligado, o
    -- estado do bem, para a suposição gravada.
    v_7d_lr := null;
    v_7d_lm := null;
    v_7d_vi := null;
    v_7d_bm := null;
    v_7d_saf := false;
    if v_7d_cal or v_7d_pat or v_7d_via or v_7d_ml then
      v_7d_lr := public._agenda_local_resolvido(v_os, p_hoje);
      if v_7d_cal or v_7d_pat then
        v_7d_lm := public._agenda_local_mascara(v_os, v_ini, v_fim, p_hoje, v_7d_lr);
      end if;
      if v_7d_cal then
        v_bem := v_bem || public._agenda_ints(v_7d_lm -> 'dias');
      end if;
      if v_7d_pat and (v_7d_lm ->> 'ent')::int > 0 then
        v_est := greatest(v_est, v_ini + (v_7d_lm ->> 'ent')::int - 1);
        v_estc := greatest(v_estc, v_ini + (v_7d_lm ->> 'ent')::int - 1);
      end if;
      if v_7d_pat and (v_7d_lm ->> 'sai')::int > 0 then
        v_bem := v_bem || array(select g from generate_series((v_7d_lm ->> 'sai')::int, v_fim - v_ini + 1) g);
      end if;
      if v_7d_via then
        v_7d_vi := public._agenda_viagem_da_os(v_os, p_hoje, v_7d_lr);
        if coalesce((v_7d_vi ->> 'sem_abre_fecha')::boolean, false) then
          v_7d_saf := v_abre or v_fecha;
          v_abre := false;
          v_fecha := false;
        end if;
      end if;
    end if;
    if v_7d_bem then
      v_7d_bm := public._agenda_estado_do_bem(v_os, p_hoje);
    end if;
    -- FASE 7d: fim
    v_e := jsonb_build_object(
      'i', v_i, 'os', v_os, 'numero', v_pront ->> 'numero', 'cliente_curto', v_pront ->> 'cliente_curto',
      'classe', v_classe, 'motivo', v_cl ->> 'motivo', 'texto', v_cl ->> 'texto', 'condicao_tipo', v_cl ->> 'condicao_tipo',
      'passos', v_passos, 'abre', v_abre, 'fecha', v_fecha, 'dt_m', v_dtm, 'dt_t', v_dtt,
      'dm', coalesce((v_meios #>> '{por_turno,manha,desejado}')::int, 0), 'dtd', coalesce((v_meios #>> '{por_turno,tarde,desejado}')::int, 0),
      'pm', to_jsonb(v_pm), 'pt', to_jsonb(v_pt), 'fixa', v_fixa,
      'est', v_est - v_ini + 1, 'est_cond', v_estc - v_ini + 1, 'est_patio', public.agenda_somar_du(v_cong, 1) - v_ini + 1,
      'min_h', v_minh, 'bem', to_jsonb(v_bem), 'patio_passos', v_pat_p, 'patio_bem', to_jsonb(v_pat_b),
      'tem_reserva', v_k.reserva, 'tem_fixada', v_k.fixada, 'evento_real', v_evento, 'teto100', v_fx is not null,
      'dono_impossivel', ((v_dtm or v_dtt) and not coalesce((v_ctx ->> 'dono_tem_padrao')::boolean, false))
                         or ((v_abre or v_fecha or v_dtm or v_dtt) and coalesce((v_ctx ->> 'dono')::int, 0) = 0),
      'atrasar', v_os = any (v_atrasar), 'prio', v_pl.prioridade_manual, 'razao', v_pront -> 'razao_critica',
      'sinal', coalesce((v_cartj -> v_os::text ->> 'sinal')::boolean, false), 'aprovada_em', v_pront ->> 'aprovada_em',
      'fonte', v_meios ->> 'fonte', 'dias', v_meios -> 'dias', 'precisa', v_pl.precisa_ate,
      'fim_antes', v_pront #>> '{plano,ultimo_dia}', 'kept_max', v_k.ultimo, 'tipo_os',
      -- o tipo do meio-dia: o motivo da regra d05 (diagnóstico, comissionamento), mesmo quando o dono está na equipe
      case v_meios ->> 'regra_motivo' when 'diagnóstico' then 'diagnostico' when 'comissionamento' then 'comissionamento'
           else 'execucao' end)
      || case when v_fx is not null then jsonb_build_object('fixar_de', greatest((v_fx ->> 'de')::date, p_hoje) - v_ini + 1,
                                                            'fixar_ate', (v_fx ->> 'ate')::date - v_ini + 1)
              else '{}'::jsonb end;
    -- CORREÇÃO 29/10 (P3): a reserva DELA (por teto ou condicionada, de hoje em diante: a que o item "a reserva vira
    -- compromisso" cancela) não conta contra ela mesma no encaixe do compromisso. O encaixe já deixava o compromisso usar a
    -- célula da própria reserva, mas o lugar até 100% da semana (teto100 − compromisso − reserva) contava a reserva dela:
    -- com o teto apertado (o João, 4 de 4 meios-dias na semana, todos na reserva do Lenine) a promoção nunca cabia. Vai na
    -- entrada da fila só quando há: res_propria = a pessoa × semana ((pessoa − 1) × nw + semana, a posição de uso_r no
    -- contexto) de cada meio-dia reservado, uma vez por alocação.
    if v_k.reserva then
      v_rp := array(select (array_position(v_pes, a.payee_id) - 1) * (v_ctx ->> 'nw')::int + (a.dia - v_ini) / 7 + 1
                      from public.agenda_alocacoes a
                     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva'
                       and a.reserva_de in ('teto', 'condicionada') and a.dia >= p_hoje and a.dia between v_ini and v_fim
                       and a.presenca = 'turno' and a.payee_id = any (v_pes) and not (a.id = any (v_ign))
                     order by 1);
      if cardinality(v_rp) > 0 then
        v_e := v_e || jsonb_build_object('res_propria', to_jsonb(v_rp));
      end if;
    end if;
    -- CORREÇÃO 29/10 (P3): fim
    -- FASE 7b: (7b P4, §5.3, R4.3) a entrada da fila, só com os modos da 7b: a dupla por meio-dia (dk = as pessoas dos passos que
    -- restam, os últimos v_passos do molde; dk_dono_conta; a fonte; o texto do cartão); da dupla inferida, o bloco de 1 pessoa
    -- (passos1: ligado com a duração que conserva as diárias-pessoa, a soma do dk — cada meio-dia de dupla vira dois de 1 pessoa —; em
    -- teste ou com os dias ditos pelo dono, os passos de antes), os meios-dias
    -- dela que restam no início e no fim (dupla_ni, dupla_nf; ou dupla_todos) e o nome do que a tarefa pede; o prazo firme (prazo_h =
    -- o índice da tarde de least(precisa_ate, o prometido firme) na grade); e a dupla dita que só passa pela régua dos técnicos com
    -- quem vem sob demanda (dupla_sd: sem eles, a classe daria 4; R4.3(c)).
    v_7b_dk := '{}'::int[];
    if v_meios ? 'dk' then
      v_7b_pk := public._agenda_ints(v_meios #> '{dupla,pk}');
      v_7b_tot := cardinality(v_7b_pk);
      v_7b_dk := case when v_passos > 0 then v_7b_pk[greatest(v_7b_tot - v_passos + 1, 1) : v_7b_tot] else '{}'::int[] end;
      v_e := v_e || jsonb_build_object('dk', to_jsonb(v_7b_dk), 'dk_dono_conta', v_meios -> 'dk_dono_conta',
                                       'dupla_fonte', v_meios #>> '{dupla,fonte}', 'dupla_texto', v_meios #>> '{dupla,texto}');
      if v_meios #>> '{dupla,fonte}' = 'regra' and v_passos > 0 then
        v_e := v_e || jsonb_build_object(
          'passos1', case when (v_meios #>> '{dupla,pm_estimativa}') is not null then (select sum(x)::int from unnest(v_7b_dk) x)
                          else v_passos end,
          'dupla_todos', coalesce((v_meios #>> '{dupla,todos}')::boolean, false),
          'dupla_ni', least(greatest(coalesce((v_meios #>> '{dupla,ni}')::int, 0) - (v_7b_tot - v_passos), 0), v_passos),
          'dupla_nf', least(coalesce((v_meios #>> '{dupla,nf}')::int, 0), v_passos),
          'dupla_rot_ini', public._agenda_lista(array(select distinct on (m ->> 'motivo') m ->> 'frase'
                                                        from jsonb_array_elements(v_meios #> '{dupla,motivos}') m
                                                       where m ->> 'onde' = 'inicio' order by m ->> 'motivo')),
          'dupla_rot_fim', public._agenda_lista(array(select distinct on (m ->> 'motivo') m ->> 'frase'
                                                        from jsonb_array_elements(v_meios #> '{dupla,motivos}') m
                                                       where m ->> 'onde' = 'fim' order by m ->> 'motivo')),
          'dupla_rot_todos', (select m ->> 'rotulo' from jsonb_array_elements(v_meios #> '{dupla,motivos}') m
                               where m ->> 'onde' = 'todos' limit 1));
      end if;
    end if;
    if cf.dono_como_tecnico and cf.modo_dias <> 'desligado' and v_meios ->> 'presenca' = 'nunca' then
      v_e := v_e || jsonb_build_object('dono_nunca', true);
    end if;
    if cf.modo_sabado <> 'desligado' or v_meios ? 'dk' then
      v_7b_prazo := least(v_pl.precisa_ate, case when v_pl.prometido_tipo = 'firme' then v_pl.prometido_ate end);
      if v_7b_prazo between v_ini and v_fim then
        v_e := v_e || jsonb_build_object('prazo_h', 2 * (v_7b_prazo - v_ini) + 2, 'prazo', v_7b_prazo);
      end if;
    end if;
    if cf.modo_dupla <> 'desligado' and v_pl.dupla_dita in ('todos', 'inicio', 'fim')
       and not coalesce((v_meios ->> 'equipe_dita')::boolean, false) and v_passos > 0 then
      v_7b_n := greatest(coalesce((v_meios #>> '{por_turno,manha,desejado}')::int, 0),
                         coalesce((v_meios #>> '{por_turno,tarde,desejado}')::int, 0),
                         coalesce((select max(x) from unnest(v_7b_dk) x), 0)
                         - case when coalesce((v_meios ->> 'dk_dono_conta')::boolean, true)
                                     and (coalesce((v_meios #>> '{dono_turno,manha}')::boolean, false)
                                          or coalesce((v_meios #>> '{dono_turno,tarde}')::boolean, false)) then 1 else 0 end);
      if v_7b_n >= 2 then
        v_7b_semtec := coalesce(v_7b_semtec, (select count(*)::int from jsonb_array_elements(coalesce(
                         public.agenda_capacidade_semanal(p_hoje) -> 'pessoas', '[]'::jsonb)) x
                        where not coalesce((x ->> 'eh_dono')::boolean, false)));
        if v_7b_semtec < v_7b_n then
          v_e := v_e || jsonb_build_object('dupla_sd', true, 'dupla_n', v_7b_n,
                                           'dupla_meios_n', case when cardinality(v_7b_dk) > 0
                                                                 then (select count(*)::int from unnest(v_7b_dk) x where x >= 2)
                                                                 else v_passos end);
        end if;
      end if;
    end if;
    -- FASE 7b: fim
    -- FASE 7c: (7c P2, §5.2 1) a entrada da fila ganha o que a OS pede (os_exigencias, sem IA: ext = em todos os meios-dias, exu = no
    -- último, exf 1 = pela linha, exig_texto) — em qualquer modo, porque o critério de cada alocação é gravado sempre — e, só com
    -- modo_lider ou modo_habilidade ligado, o responsável (_agenda_lider_da_os, sem as alocações que a proposta cancela): lid (a
    -- posição na grade; fora dela, 0), lid_duro (o dito ou quem fez, com modo_lider ligado e sem a palavra do dono sobre quem vai),
    -- lid_plan (o planejado: só desempata) e lid_fora (o responsável que não está na grade). Só a OS que vai ao encaixe (fora da
    -- classe 4, com passos ou o pátio) é lida. O que a OS pede só é lido com a porta de os_exigencias aberta (o service_role, sem
    -- login, ou o admin/financeiro logado): a técnica logada que marca pela tela (agenda_marcar_os, liberada a authenticated) chega
    -- aqui e receberia o 42501 dela no meio do motor; para ela, a OS "não pede ninguém em especial" (a escolha de antes; o pedido dela
    -- tem a pessoa, a palavra de quem marca, e os filtros 3 a 5 não valem de todo jeito).
    if v_7c_le is null then
      begin
        v_7c_le := case when auth.uid() is not null then public.is_admin_or_financial(auth.uid())
                        else coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') in ('', 'service_role') end;
      exception when others then
        v_7c_le := false;
      end;
    end if;
    if v_7c_le and v_classe <> 4 and (v_passos > 0 or v_pat_p > 0) then
      v_7c_exg := public.os_exigencias(v_os, p_hoje);
      v_e := v_e || jsonb_build_object('ext', coalesce((v_7c_exg ->> 'todos')::int, 0), 'exu', coalesce((v_7c_exg ->> 'ultimo')::int, 0),
                                       'exf', coalesce((v_7c_exg ->> 'fonte_texto')::int, 0), 'exig_texto', v_7c_exg ->> 'texto_curto');
      if cf.modo_lider = 'ligado' or cf.modo_habilidade = 'ligado' then
        v_7c_ld := public._agenda_lider_da_os(v_os, p_hoje, v_ign);
        if v_7c_ld is not null then
          v_7c_lp := array_position(v_pes, (v_7c_ld ->> 'payee_id')::uuid);
          v_e := v_e || jsonb_build_object('lid', coalesce(v_7c_lp, 0), 'lid_nome', v_7c_ld ->> 'nome',
                   'lid_duro', v_7c_ld ->> 'fonte' in ('dono', 'fez') and cf.modo_lider = 'ligado' and v_7c_lp is not null
                               and not (coalesce(cardinality(v_pm), 0) + coalesce(cardinality(v_pt), 0) > 0 or v_fixa > 0),
                   'lid_plan', case when v_7c_ld ->> 'fonte' = 'planejado' then coalesce(v_7c_lp, 0) else 0 end,
                   'lid_fora', v_7c_lp is null);
        end if;
      end if;
    end if;
    -- FASE 7c: fim
    -- FASE 7d: (7d P4, §5.4 2, §3.1-5, R6.8-3) a entrada da fila, só com os modos ligados (chave AUSENTE fora disso): fora_h e local_txt (a máscara),
    -- viagem, imax_os, os meios de estrada somados aos passos (depois da dupla da 7b, que corta o molde por v_passos: os meios de estrada
    -- não têm dk e pedem o desejado), local_texto e suposicoes (as da cadeia do local, da viagem e do bem, para o item da proposta)
    if v_7d_lr is not null or v_7d_bm is not null then
      v_7d_sup := '{}';
      if v_7d_lr ->> 'fonte' = 'cidade' or (v_7d_lr ->> 'fonte' = 'bem' and (v_7d_lr ->> 'suposicao')::boolean) then
        v_7d_sup := v_7d_sup || (v_7d_lr ->> 'texto');
      elsif v_7d_lr ->> 'fonte' = 'patio' and v_7d_bm is null then
        v_7d_sup := v_7d_sup || format('supus o motorhome %s', v_7d_lr ->> 'texto_curto');
      end if;
      if coalesce((v_7d_vi ->> 'suposicao')::boolean, false) and v_7d_vi ->> 'tipo' in ('bate_volta', 'pernoite') then
        v_7d_sup := v_7d_sup || public._agenda_viagem_suposicao(v_7d_lr, v_7d_vi ->> 'tipo');
      end if;
      if v_7d_saf then
        v_7d_sup := v_7d_sup || 'supus que você não vai abrir e fechar esse serviço (fora da região)'::text;
      end if;
      v_7d_sup := v_7d_sup || array(select x from jsonb_array_elements_text(coalesce(v_7d_bm -> 'suposicoes', '[]'::jsonb)) x)
                           || array(select x from jsonb_array_elements_text(coalesce(v_7d_lm -> 'notas', '[]'::jsonb)) x);
      v_e := v_e || jsonb_build_object('suposicoes', to_jsonb(v_7d_sup));
      if v_7d_lr is not null then
        v_e := v_e || jsonb_build_object('local_texto', v_7d_lr ->> 'texto', 'local_curto', v_7d_lr ->> 'texto_curto');
      end if;
      if v_7d_cal then
        v_e := v_e || jsonb_build_object('fora_h', v_7d_lm -> 'meios', 'local_txt', v_7d_lm -> 'motivos');
      end if;
      if v_7d_vi is not null then
        v_e := v_e || jsonb_build_object('viagem', v_7d_vi ->> 'tipo')
                   || case when v_7d_vi ->> 'imax_os' is not null then jsonb_build_object('imax_os', (v_7d_vi ->> 'imax_os')::int) else '{}'::jsonb end;
        v_7d_extra := public._agenda_viagem_extra(v_7d_vi ->> 'tipo', (v_7d_vi ->> 'extra_por')::int, v_passos);
        if v_7d_extra > 0 then
          v_e := v_e || jsonb_build_object('passos', v_passos + v_7d_extra)
                     || case when v_e ? 'passos1' then jsonb_build_object('passos1', (v_e ->> 'passos1')::int + public._agenda_viagem_extra(v_7d_vi ->> 'tipo', (v_7d_vi ->> 'extra_por')::int, (v_e ->> 'passos1')::int)) else '{}'::jsonb end;
        end if;
      end if;
    end if;
    -- FASE 7d: fim
    -- FASE 7e: (7e P4, §5.3 (a), R7.8) a OS urgente vai até 100% da semana (teto100, como o pedido do dono), só com passos a marcar. A chave só existe em ligado (R7.13).
    if v_7e_ug and coalesce((v_e ->> 'passos')::int, 0) > 0 then
      v_7e_u := public._agenda_os_urgente(v_os, p_hoje);
      if (v_7e_u ->> 'urgente')::boolean then
        v_e := v_e || jsonb_build_object('urgente', true, 'urgente_texto', v_7e_u ->> 'texto', 'teto100', true);
        v_7e_urg := v_7e_urg || to_jsonb(v_os);
      end if;
    end if;
    -- (§5.3 (b), R7.7-3) a OS puxada: o dia, sem o piso do congelado nem o EST da prontidão (quem chama só puxa OS pronta), mas nunca pisando na máscara do local (a entrada do bem, com o pátio ligado), no que ela já tem marcado nem no "só depois de". Passou de D, a simulação de quem chamou recusa. greatest ignora o nulo de propósito: nulo aqui é "sem essa restrição".
    if v_7e_dp is not null and v_os = (v_7e_pux ->> 'os')::uuid then
      v_e := v_e || jsonb_build_object('teto100', true, 'puxada', true, 'min_h', 2 * (v_7e_dp - v_ini) + 1,
                                       'est', greatest(v_7e_dp, (v_depois ->> v_os::text)::date, v_k.ultimo_fut,
                                                       case when v_7d_pat and (v_7d_lm ->> 'ent')::int > 0 then v_ini + (v_7d_lm ->> 'ent')::int - 1 end) - v_ini + 1);
    end if;
    -- FASE 7e: fim
    v_fila := v_fila || v_e;
  end loop;

  -- FASE 7e: (7e P4, §5.3 (a), R7.12-10) as urgentes vão ao validador e ficam em parametros.p_restricoes para a revalidação ao aplicar. Só com alguma; fora de ligado, nem a chave.
  if jsonb_array_length(v_7e_urg) > 0 then
    v_r := v_r || jsonb_build_object('urgentes', v_7e_urg);
  end if;
  -- FASE 7e: fim
  -- A ordem: (classe, atrasar, prioridade do dono, razão crítica, sinal pago, aprovação, número, id).
  select coalesce(jsonb_agg(x.e || jsonb_build_object('ordem', x.rn) order by x.rn), '[]'::jsonb) into v_fila
    from (select e, row_number() over (order by (e ->> 'classe')::int, (e ->> 'atrasar')::boolean, (e ->> 'prio')::int nulls last,
                                                (e ->> 'razao')::numeric nulls last, (e ->> 'sinal')::boolean desc,
                                                (e ->> 'aprovada_em')::date nulls last, e ->> 'numero' collate "C", e ->> 'os') as rn
            from jsonb_array_elements(v_fila) e) x;
  select coalesce(jsonb_object_agg(e ->> 'i', e), '{}'::jsonb) into v_ent from jsonb_array_elements(v_fila) e;

  v_par := jsonb_build_object('wip', cf.wip_max, 'imax', cf.interrupcoes_max, 'inicios', cf.inicios_tentados_du,
                              'semana', p_escopo = 'semana', 'jan_de', v_de - v_ini + 1, 'jan_ate', v_ate - v_ini + 1,
                              'acima', v_acima);
  -- FASE 7b: (7b P4) os parâmetros do sábado (modo e política) e da dupla (modo; a espera: ligado, dupla_espera_max_du dias úteis;
  -- em teste, 0 — a dupla só entra quando não termina depois do bloco de 1 pessoa, d8), só com os modos da 7b
  if cf.modo_sabado <> 'desligado' or cf.modo_dupla <> 'desligado' then
    v_par := v_par || jsonb_build_object('sab_modo', cf.modo_sabado, 'sab_politica', cf.sabado_manha, 'dupla_modo', cf.modo_dupla,
                                         'dupla_espera', case when cf.modo_dupla = 'ligado' then cf.dupla_espera_max_du else 0 end);
  end if;
  -- FASE 7b: fim
  -- FASE 7c: (7c P2, §5.2 2) os parâmetros da 7c, sempre (o encaixe lê a presença deles como "grave o critério"): hab_modo (os
  -- filtros 3 e 4 e a ordem nova, só ligado), lid_modo (o filtro 5 e a troca avisada, só ligado), os níveis, o fechamento que cobre
  -- o último dia e a espera pelo responsável; o v_parh herda
  v_par := v_par || jsonb_build_object('hab_modo', (cf.modo_habilidade = 'ligado')::int, 'lid_modo', (cf.modo_lider = 'ligado')::int,
                                       'n', jsonb_build_object('ene', cf.habilidade_nivel_energizado, 'com', cf.habilidade_nivel_comissionar,
                                                               'dia', cf.habilidade_nivel_diagnostico, 'alt', cf.habilidade_nivel_altura,
                                                               'par', cf.habilidade_nivel_par),
                                       'fcobre', cf.habilidade_fechamento_cobre, 'lid_espera', cf.lider_espera_max_du);
  -- FASE 7c: fim
  -- FASE 7d: (7d P4, §5.4 3, R6.8-3) mesmo_dia, com modo_mesmo_local ligado; troca, ligado e na temporada (o mês de p_hoje em temporada_meses, AG7-20).
  -- Chave AUSENTE fora disso: agenda_propostas.parametros e o M1 comparam
  if v_7d_ml then
    v_par := v_par || jsonb_build_object('mesmo_dia', true);
    if extract(month from p_hoje)::smallint = any (cf.temporada_meses) then
      v_par := v_par || jsonb_build_object('troca', true);
    end if;
  end if;
  -- FASE 7d: fim
  v_parh := v_par || jsonb_build_object('semana', false);

  -- ── 5. O encaixe e a sobrecarga (o banco nunca escolhe quem atrasa) ──
  for v_tentativa in 1 .. 3 loop
    -- (quem ficou sem saída na volta anterior sai da fila: fica fora, sem encaixe)
    v_r0 := public._agenda_encaixar(v_ctx,
              (select jsonb_agg(case when (e ->> 'i')::int = any (v_sem_q) then e || '{"tirar": true}'::jsonb else e end)
                 from jsonb_array_elements(v_fila) e), v_par);
    -- o que é crítico em cada compromisso colocado
    v_crit := '{}'::jsonb;
    for v_b in select e from jsonb_array_elements(v_r0 -> 'colocadas') e where e ->> 'tipo' = 'compromisso' loop
      v_e := v_ent -> (v_b ->> 'i');
      continue when v_e ? 'fixar_de';
      v_os := (v_e ->> 'os')::uuid;
      v_ini_x := v_ini + ((v_b ->> 'ini')::int + 1) / 2 - 1;
      v_fim_x := greatest(v_ini + ((v_b ->> 'fim')::int + 1) / 2 - 1, (v_e ->> 'kept_max')::date);
      v_canc_os := array(select (c ->> 'alocacao_id')::uuid from jsonb_array_elements(v_canc) c where (c ->> 'os')::uuid = v_os);
      v_ini_antes := (select min((c ->> 'dia')::date) from jsonb_array_elements(v_canc) c
                       where (c ->> 'os')::uuid = v_os and c ->> 'tipo' <> 'reserva');
      v_tipo := public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_x, v_ini_x, p_hoje, v_canc_os, '{}');
      -- FASE 7: (7a P8, spec §3.2 e §5.8) a zona travada (a regra zona_travada): a criticidade de novo, agora sabendo o que fica
      -- fora da conta do dia já avisado — o que não pode mais acontecer, o resto do meio-dia dele e o que volta igual neste
      -- encaixe (_agenda_zona_fora; o fixado pelo dono nunca fica fora: a regra dele não muda).
      if public._agenda_gestor_regra('zona_travada') then
        v_f7_fora := public._agenda_zona_fora(v_canc, v_os, public._agenda_alocs_do_bloco(v_ctx, v_b));
        v_tipo := public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_x, v_ini_x, p_hoje, v_canc_os,
                                             v_f7_fora);
      end if;
      -- FASE 7: fim
      if v_tipo is not null then
        v_crit := v_crit || jsonb_build_object(v_b ->> 'i', jsonb_build_object('tipo', v_tipo, 'fim', v_fim_x, 'ini', v_ini_x));
      end if;
    end loop;
    -- as críticas ainda sem decisão
    v_xnc := array(select k::int from jsonb_each(v_crit) t(k, x)
                    where x ->> 'tipo' = 'nao_cabe' and v_decisao is null
                      and not ((v_ent -> k ->> 'os')::uuid = any (v_aceitar)) and not (k::int = any (v_sem_q)) order by 1);
    v_xoc := array(select k::int from jsonb_each(v_crit) t(k, x)
                    where x ->> 'tipo' <> 'nao_cabe' and v_decisao is null
                      and not ((v_ent -> k ->> 'os')::uuid = any (v_aceitar)) and not (k::int = any (v_sem_q)) order by 1);
    -- quem X empurraria: as da classe 2 colocadas antes dela, novas e sem fixado, as mais próximas
    v_cands := '{}'::jsonb;
    foreach v_x in array v_xnc loop
      v_cands := v_cands || jsonb_build_object(v_x::text, coalesce((
        select jsonb_agg(q.i order by q.ordem desc)
          from (select (b ->> 'i')::int as i, (v_ent -> (b ->> 'i') ->> 'ordem')::int as ordem
                  from jsonb_array_elements(v_r0 -> 'colocadas') b
                 where b ->> 'tipo' = 'compromisso'
                   and (v_ent -> (b ->> 'i') ->> 'classe')::int = 2 and not (v_ent -> (b ->> 'i')) ? 'fixar_de'
                   and not (v_ent -> (b ->> 'i') ->> 'tem_fixada')::boolean and v_ent -> (b ->> 'i') ->> 'fim_antes' is null
                   and (v_ent -> (b ->> 'i') ->> 'ordem')::int < (v_ent -> v_x::text ->> 'ordem')::int
                   and not ((b ->> 'i')::int = any (v_xnc || v_xoc))
                   -- (na 2ª volta, só as que deram opção: quem não faz X caber não fica esperando a decisão)
                   and (v_usadas is null or coalesce(v_usadas -> v_x::text, '[]'::jsonb) @> to_jsonb((b ->> 'i')::int))
                 order by 2 desc limit c_candidatas) q), '[]'::jsonb));
    end loop;
    v_h := array(select distinct x from (select unnest(v_xnc || v_xoc) as x
                                          union select (j)::int from jsonb_each(v_cands) t(k, v), jsonb_array_elements_text(v) j) u
                  order by 1);
    exit when cardinality(v_h) = 0;

    -- O que é publicado sem esperar sai desta mesma rodada (as reservas foram depois de todos os compromissos, e não
    -- tomam o lugar de quem espera a decisão); quem espera fica como item crítico (X, a que não cabe, sai).
    v_rf := v_r0;
    v_ctxf := public._agenda_ctx_com(v_ctx,
                (select coalesce(jsonb_agg(b), '[]'::jsonb) from jsonb_array_elements(v_r0 -> 'colocadas') b
                  where not ((b ->> 'i')::int = any (v_h) and b ->> 'tipo' = 'compromisso')));
    -- a decisão vai encontrar a grade já com o resto publicado: as opções são simuladas sobre ela
    v_base := public._agenda_encaixar(v_ctxf,
                (select jsonb_agg(e) from jsonb_array_elements(v_fila) e where (e ->> 'i')::int = any (v_h)), v_parh);
    v_perg := '[]'::jsonb;
    v_n := cardinality(v_sem_q);
    foreach v_x in array v_xnc || v_xoc loop
      v_e := v_ent -> v_x::text;
      v_os := (v_e ->> 'os')::uuid;
      v_tipo := v_crit -> v_x::text ->> 'tipo';
      v_xb := (select b from jsonb_array_elements(v_base -> 'colocadas') b where (b ->> 'i')::int = v_x and b ->> 'tipo' = 'compromisso');
      v_fim_x := case when v_xb is null then null
                      else greatest(v_ini + ((v_xb ->> 'fim')::int + 1) / 2 - 1, (v_e ->> 'kept_max')::date) end;
      v_opc := '[]'::jsonb;
      if v_tipo = 'nao_cabe' then
        if v_fim_x is not null then
          v_opc := v_opc || jsonb_build_object('n', 1, 'os', v_os, 'atraso_dito', public.agenda_du_entre((v_e ->> 'precisa')::date, v_fim_x),
                     'sem_data', false, 'atraso_du', public.agenda_du_entre((v_e ->> 'precisa')::date, v_fim_x), 'numero', v_e ->> 'numero',
                     'texto', format('%s atrasa: termina %s em vez de %s', public._agenda_rotulo_da_os(v_os), public._dia_curto(v_fim_x),
                                     public._dia_curto((v_e ->> 'precisa')::date)),
                     'efeito', jsonb_build_object('restricoes', jsonb_build_object('aceitar_atraso', jsonb_build_array(v_os))),
                     'espera', jsonb_build_object(v_os::text, v_fim_x));
        end if;
        for v_c in select (j)::int from jsonb_array_elements_text(coalesce(v_cands -> v_x::text, '[]'::jsonb)) j loop
          v_sim := public._agenda_encaixar(v_ctxf,
                     (select jsonb_agg(case when (e ->> 'i')::int = v_c
                                            then e || jsonb_build_object('ordem', (e ->> 'ordem')::int + c_fim_da_classe) else e end)
                        from jsonb_array_elements(v_fila) e where (e ->> 'i')::int = any (v_h)), v_parh);
          v_xb := (select b from jsonb_array_elements(v_sim -> 'colocadas') b where (b ->> 'i')::int = v_x and b ->> 'tipo' = 'compromisso');
          v_cb := (select b from jsonb_array_elements(v_sim -> 'colocadas') b where (b ->> 'i')::int = v_c and b ->> 'tipo' = 'compromisso');
          continue when v_xb is null or v_cb is null
                     or v_ini + ((v_xb ->> 'fim')::int + 1) / 2 - 1 > (v_e ->> 'precisa')::date;
          v_ini_c := v_ini + ((v_cb ->> 'ini')::int + 1) / 2 - 1;
          v_fim_c := v_ini + ((v_cb ->> 'fim')::int + 1) / 2 - 1;
          v_b := (select b from jsonb_array_elements(v_base -> 'colocadas') b where (b ->> 'i')::int = v_c and b ->> 'tipo' = 'compromisso');
          v_opc := v_opc || jsonb_build_object('n', jsonb_array_length(v_opc) + 1, 'os', v_ent -> v_c::text -> 'os', 'c', v_c,
                     'atraso_dito', case when v_ent -> v_c::text ->> 'precisa' is null then 0
                                         else greatest(public.agenda_du_entre((v_ent -> v_c::text ->> 'precisa')::date, v_fim_c), 0) end,
                     'sem_data', v_ent -> v_c::text ->> 'precisa' is null,
                     'atraso_du', case when v_b is null then 0
                                       else greatest(public.agenda_du_entre(v_ini + ((v_b ->> 'fim')::int + 1) / 2 - 1, v_fim_c), 0) end,
                     'numero', v_ent -> v_c::text ->> 'numero',
                     'texto', format('%s passa para %s (%s)', public._agenda_rotulo_da_os((v_ent -> v_c::text ->> 'os')::uuid),
                                     public._agenda_dias_texto(array(select distinct v_ini + (h - 1) / 2
                                                                       from unnest(public._agenda_ints(v_cb -> 'h')) h)),
                                     case when v_ent -> v_c::text ->> 'precisa' is null then 'sem data dita pelo cliente'
                                          else 'precisa até ' || public._dia_curto((v_ent -> v_c::text ->> 'precisa')::date) end),
                     'efeito', jsonb_build_object('restricoes', jsonb_build_object('atrasar', jsonb_build_array(v_ent -> v_c::text -> 'os'))),
                     'espera', jsonb_build_object(v_os::text, v_ini + ((v_xb ->> 'fim')::int + 1) / 2 - 1,
                                                  v_ent -> v_c::text ->> 'os', v_fim_c));
          exit when jsonb_array_length(v_opc) >= 4;
        end loop;
      elsif v_fim_x is not null then
        v_opc := v_opc || jsonb_build_object('n', 1, 'os', v_os, 'atraso_dito', 0, 'sem_data', false, 'atraso_du', 0, 'numero', v_e ->> 'numero',
                   'texto', format('Sigo: %s termina %s em vez de %s', public._agenda_rotulo_da_os(v_os), public._dia_curto(v_fim_x),
                                   public._dia_curto((v_e ->> 'fim_antes')::date)),
                   'efeito', jsonb_build_object('restricoes', jsonb_build_object('aceitar_atraso', jsonb_build_array(v_os))),
                   'espera', jsonb_build_object(v_os::text, v_fim_x));
      end if;
      if jsonb_array_length(v_opc) = 0 then
        -- sem saída nenhuma: não é pergunta (fica fora, sem encaixe); a próxima volta refaz sem ela na espera
        v_sem_q := v_sem_q || v_x;
        continue;
      end if;
      if jsonb_array_length(v_opc) = 1 then
        v_opc := v_opc || jsonb_build_object('n', 2, 'os', v_os, 'atraso_dito', null, 'sem_data', false, 'atraso_du', null,
                   'numero', v_e ->> 'numero',
                   'texto', format('Deixo o %s fora do plano por enquanto', public._agenda_nome_curto(v_e ->> 'cliente_curto')),
                   'efeito', jsonb_build_object('restricoes', jsonb_build_object('tirar', jsonb_build_array(v_os))),
                   'espera', '{}'::jsonb);
      end if;
      -- a recomendação: o menor atraso sobre datas ditas; no empate, quem não tem data dita, o menor atraso, o número
      if v_tipo = 'nao_cabe' then
        select (o ->> 'n')::int into v_rec from jsonb_array_elements(v_opc) o
         where o ->> 'atraso_dito' is not null
         order by (o ->> 'atraso_dito')::int, (o ->> 'sem_data')::boolean desc, (o ->> 'atraso_du')::int, o ->> 'numero' collate "C"
         limit 1;
        v_rec := coalesce(v_rec, 1);
        v_q := v_opc -> (v_rec - 1);
        v_rec_txt := case when (v_q ->> 'sem_data')::boolean
                            then format('o %s não tem data dita pelo cliente', public._agenda_nome_curto((select cl.name from public.service_orders so
                                          join public.clients cl on cl.id = so.client_id where so.id = (v_q ->> 'os')::uuid)))
                          when v_rec = 1 then format('é o menor atraso (%s)', public._agenda_plural((v_q ->> 'atraso_du')::int, 'dia útil', 'dias úteis'))
                          else 'é o menor atraso sobre o que o cliente pediu' end;
        v_txt := format('Não cabe tudo até %s. Qual aceita atrasar? %s. Recomendo a %s: %s.',
                        public._dia_curto((v_e ->> 'precisa')::date),
                        (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int) from jsonb_array_elements(v_opc) o),
                        v_rec, v_rec_txt);
      else
        v_rec := 1;
        v_rec_txt := case v_tipo
          when 'atraso_longo' then 'Recomendo seguir e você ligar para o cliente hoje'
          when 'segundo_atraso' then 'É o 2º atraso desta OS: recomendo seguir e você ligar para o cliente hoje'
          when 'remarcar_confirmado' then 'O cliente tinha confirmado o dia: recomendo seguir e você ligar para ele hoje'
          else 'Você tinha fixado o dia, que não dá mais: recomendo seguir no novo dia' end;
        -- FASE 7: (7a P3) a recomendação das críticas da zona travada do gestor (P8: o dia que a equipe já recebeu na ficha e o
        -- que o cliente já ouviu); inertes até lá (_agenda_criticidade ainda não dá esses tipos)
        if v_tipo = 'dia_avisado' then
          v_rec_txt := 'A equipe já tinha recebido a ficha desse dia: recomendo seguir e você avisar quem ia';
        elsif v_tipo = 'dia_prometido' then
          v_rec_txt := 'É um dia que o cliente já ouviu: recomendo seguir e você falar com ele hoje';
        end if;
        -- FASE 7: fim
        v_txt := format('%s só dá para terminar em %s, %s depois do que estava no plano. 1) %s; 2) %s. %s.',
                        public._agenda_rotulo_da_os(v_os), public._dia_curto(v_fim_x),
                        public._agenda_plural(v_fim_x - (v_e ->> 'fim_antes')::date, 'dia', 'dias'),
                        v_opc -> 0 ->> 'texto', v_opc -> 1 ->> 'texto', v_rec_txt);
      end if;
      v_chave := format('%s:%s:%s', v_tipo, v_os, v0);
      v_perg := v_perg || jsonb_build_object(
        'tipo', v_tipo, 'chave', v_chave, 'service_order_id', v_os,
        'os_ids', (select jsonb_agg(v_ent -> j::text -> 'os' order by j) from unnest(array[v_x] || coalesce(
                     array(select (k)::int from jsonb_array_elements_text(coalesce(v_cands -> v_x::text, '[]'::jsonb)) k), '{}'::int[])) j),
        'texto', left(v_txt, 600), 'opcoes', v_opc, 'recomendacao', v_rec, 'recomendacao_texto', left(v_rec_txt, 300),
        'perda_em', (select min(v_ini + ((b ->> 'ini')::int + 1) / 2 - 1) from jsonb_array_elements(v_base -> 'colocadas') b
                      where (b ->> 'i')::int = any (array[v_x] || coalesce(
                        array(select (k)::int from jsonb_array_elements_text(coalesce(v_cands -> v_x::text, '[]'::jsonb)) k), '{}'::int[]))),
        'x', v_x);
    end loop;
    -- quem ficou sem saída sai da espera e a conta é refeita
    continue when cardinality(v_sem_q) <> v_n;
    -- as que não fazem X caber não ficam esperando a decisão: a conta é refeita só com as que deram opção (uma vez)
    if v_usadas is null and exists (
         select 1 from jsonb_each(v_cands) t(k, v), jsonb_array_elements_text(t.v) j
          where not exists (select 1 from jsonb_array_elements(v_perg) q, jsonb_array_elements(q -> 'opcoes') o
                             where (q ->> 'x')::int = t.k::int and (o ->> 'c')::int = j::int)) then
      select coalesce(jsonb_object_agg(q ->> 'x', coalesce((select jsonb_agg((o ->> 'c')::int) from jsonb_array_elements(q -> 'opcoes') o
                                                             where o ? 'c'), '[]'::jsonb)), '{}'::jsonb)
        into v_usadas from jsonb_array_elements(v_perg) q;
      continue;
    end if;
    exit;
  end loop;
  if cardinality(v_h) = 0 then
    v_xnc := '{}';
    v_xoc := '{}';
    v_perg := '[]'::jsonb;
    v_rf := v_r0;
    v_ctxf := public._agenda_ctx_com(v_ctx, v_rf -> 'colocadas');
    v_base := jsonb_build_object('colocadas', '[]'::jsonb);
  end if;

  -- ── 6. Os itens: o que sai, o que entra, o que espera a decisão ──
  -- (a) o que sai (a violação, o resto do meio-dia, o pedido do dono)
  v_itens := v_itens || coalesce((
    select jsonb_agg(jsonb_build_object(
             'op', 'cancelar', 'os', g.os, 'numero', g.numero, 'cliente_curto', g.cliente_curto, 'tipo', g.tipo,
             'motivo', g.motivo, 'violada', g.violada, 'alocacoes', g.alocs, 'de', g.de, 'ate', g.ate,
             'critica', null, 'decisao', v_decisao, 'aplicado', false,
             'texto', format('%s: sai %s — %s.', public._agenda_rotulo_da_os(g.os), public._agenda_dias_texto(g.dias),
                             case g.motivo when 'pessoa' then 'quem ia não está mais livre' when 'material' then 'o material não chega a tempo'
                                           when 'cliente' then 'o cliente ou o bem não está liberado' when 'os_saiu' then 'a OS saiu da carteira'
                                           when 'condicao_vencida' then 'a condição da reserva venceu' when 'dono' then 'você pediu outro dia'
                                           when 'espera' then coalesce('você pôs em espera até ' || public._dia_curto(
                                             (select pl.congelada_ate from public.os_planejamento pl where pl.service_order_id = g.os)),
                                             'você pôs em espera')
                                           else 'replanejado junto' end))
             order by g.numero, g.os, g.motivo)
      from (select (c ->> 'os')::uuid as os, min(v_info -> (c ->> 'os') -> 'pront' ->> 'numero') as numero,
                   min(v_info -> (c ->> 'os') -> 'pront' ->> 'cliente_curto') as cliente_curto,
                   case when bool_and(c ->> 'tipo' = 'reserva') then 'reserva' else min(c ->> 'tipo') end as tipo,
                   c ->> 'motivo' as motivo, bool_or((c ->> 'violada')::boolean) as violada,
                   jsonb_agg(jsonb_build_object('alocacao_id', c -> 'alocacao_id', 'payee_id', c -> 'payee_id',
                               'nome', (select public._agenda_nome_curto(py.name) from public.payees py where py.id = (c ->> 'payee_id')::uuid),
                               'dia', c -> 'dia', 'turno', c -> 'turno', 'presenca', c -> 'presenca', 'estado', c -> 'estado',
                               'fixado_por', c -> 'fixado_por')
                             order by c ->> 'dia', c ->> 'turno' = 'tarde', c ->> 'payee_id') as alocs,
                   array_agg((c ->> 'dia')::date) as dias, min((c ->> 'dia')::date) as de, max((c ->> 'dia')::date) as ate
              from jsonb_array_elements(v_canc) c
             group by (c ->> 'os')::uuid, c ->> 'motivo') g), '[]'::jsonb);
  -- FASE 7c: (7c P2, §5.2 4, §6.8) o que sai pela violação habilidade (a do P3: a equipe do meio-dia não tem quem o serviço pede) diz
  -- o porquê, no lugar do "replanejado junto"
  if exists (select 1 from jsonb_array_elements(v_itens) i where i ->> 'op' = 'cancelar' and i ->> 'motivo' = 'habilidade') then
    select coalesce(jsonb_agg(case when i ->> 'op' = 'cancelar' and i ->> 'motivo' = 'habilidade'
                                   then i || jsonb_build_object('texto', format('%s: sai %s — a equipe do dia não tinha quem o serviço pede.',
                                          public._agenda_rotulo_da_os((i ->> 'os')::uuid),
                                          public._agenda_dias_texto(array(select (a ->> 'dia')::date from jsonb_array_elements(i -> 'alocacoes') a))))
                                   else i end order by k), '[]'::jsonb)
      into v_itens
      from jsonb_array_elements(v_itens) with ordinality t(i, k);
  end if;
  -- FASE 7c: fim
  -- FASE 7d: (7d P4, §5.4 3, §6.2) o que sai pela violação local diz o porquê, no lugar do "replanejado junto"
  if exists (select 1 from jsonb_array_elements(v_itens) i where i ->> 'op' = 'cancelar' and i ->> 'motivo' = 'local') then
    select coalesce(jsonb_agg(case when i ->> 'op' = 'cancelar' and i ->> 'motivo' = 'local'
                                   then i || jsonb_build_object('texto', format('%s: sai %s — o local não recebe a equipe nesse dia.',
                                          public._agenda_rotulo_da_os((i ->> 'os')::uuid),
                                          public._agenda_dias_texto(array(select (a ->> 'dia')::date from jsonb_array_elements(i -> 'alocacoes') a))))
                                   else i end order by k), '[]'::jsonb)
      into v_itens
      from jsonb_array_elements(v_itens) with ordinality t(i, k);
  end if;
  -- FASE 7d: fim
  -- (b) a reserva que virou compromisso nesta proposta
  v_itens := v_itens || coalesce((
    select jsonb_agg(jsonb_build_object(
             'op', 'cancelar', 'os', g.os, 'numero', v_ent -> g.i ->> 'numero', 'cliente_curto', v_ent -> g.i ->> 'cliente_curto',
             'tipo', 'reserva', 'motivo', 'promovida', 'violada', false, 'alocacoes', g.alocs, 'de', g.de, 'ate', g.ate,
             'critica', null, 'decisao', v_decisao, 'aplicado', false,
             'texto', format('%s: a reserva vira compromisso.', public._agenda_rotulo_da_os(g.os)))
             order by v_ent -> g.i ->> 'numero')
      from (select b ->> 'i' as i, (v_ent -> (b ->> 'i') ->> 'os')::uuid as os,
                   (select jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'payee_id', a.payee_id, 'nome', public._agenda_nome_curto(py.name),
                                     'dia', a.dia, 'turno', a.turno, 'presenca', a.presenca, 'estado', a.estado, 'fixado_por', a.fixado_por)
                                     order by a.dia, a.turno = 'tarde', a.payee_id)
                      from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                     where a.service_order_id = (v_ent -> (b ->> 'i') ->> 'os')::uuid and a.estado in ('publicada', 'fixada')
                       and a.tipo = 'reserva' and a.reserva_de in ('teto', 'condicionada') and a.dia >= p_hoje
                       and not (a.id = any (v_ign))) as alocs,
                   (select min(a.dia) from public.agenda_alocacoes a where a.service_order_id = (v_ent -> (b ->> 'i') ->> 'os')::uuid
                       and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva' and a.dia >= p_hoje) as de,
                   (select max(a.dia) from public.agenda_alocacoes a where a.service_order_id = (v_ent -> (b ->> 'i') ->> 'os')::uuid
                       and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva' and a.dia >= p_hoje) as ate
              from jsonb_array_elements(v_rf -> 'colocadas') b
             where b ->> 'tipo' = 'compromisso' and coalesce((b ->> 'na_janela')::boolean, true)
               and (v_ent -> (b ->> 'i') ->> 'tem_reserva')::boolean and not ((b ->> 'i')::int = any (v_h))) g
     where g.alocs is not null), '[]'::jsonb);
  -- (c) o que entra: publicável sem esperar, ou (d) esperando a decisão (a X que não cabe sai da proposta)
  for v_b in
    select b || jsonb_build_object('espera', (b ->> 'i')::int = any (v_h) and b ->> 'tipo' = 'compromisso')
      from jsonb_array_elements(v_rf -> 'colocadas') b
     where coalesce((b ->> 'na_janela')::boolean, true)
       and not ((b ->> 'i')::int = any (v_xnc) and b ->> 'tipo' = 'compromisso')
  loop
    v_e := v_ent -> (v_b ->> 'i');
    v_os := (v_e ->> 'os')::uuid;
    v_ini_x := v_ini + ((v_b ->> 'ini')::int + 1) / 2 - 1;
    v_fim_x := v_ini + ((v_b ->> 'fim')::int + 1) / 2 - 1;
    v_fim_dep := greatest(v_fim_x, (v_e ->> 'kept_max')::date);
    v_canc_os := array(select (c ->> 'alocacao_id')::uuid from jsonb_array_elements(v_canc) c where (c ->> 'os')::uuid = v_os);
    v_ini_antes := (select min((c ->> 'dia')::date) from jsonb_array_elements(v_canc) c
                     where (c ->> 'os')::uuid = v_os and c ->> 'tipo' <> 'reserva');
    v_tipo := case when v_b ->> 'tipo' = 'reserva' or v_e ? 'fixar_de' then null
                   else public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_dep, v_ini_x, p_hoje,
                                                   v_canc_os, '{}') end;
    -- FASE 7: (7a P8) a zona travada, como no encaixe acima (o que espera a decisão de outra OS segue a de antes)
    if v_b ->> 'tipo' <> 'reserva' and not v_e ? 'fixar_de' and not coalesce((v_b ->> 'espera')::boolean, false)
       and public._agenda_gestor_regra('zona_travada') then
      v_f7_fora := public._agenda_zona_fora(v_canc, v_os, public._agenda_alocs_do_bloco(v_ctx, v_b));
      v_tipo := public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_dep, v_ini_x, p_hoje,
                                           v_canc_os, v_f7_fora);
    end if;
    -- FASE 7: fim
    -- quem espera a decisão de uma X: o tipo dela e a chave da pergunta
    v_chave := null;
    if (v_b ->> 'espera')::boolean then
      select q ->> 'chave', coalesce(v_tipo, q ->> 'tipo') into v_chave, v_tipo from jsonb_array_elements(v_perg) q
       where q -> 'os_ids' @> jsonb_build_array(v_os) order by q ->> 'chave' limit 1;
    elsif v_tipo is not null and v_decisao is null and not (v_os = any (v_aceitar)) then
      -- crítico sem pergunta (não deveria acontecer: a pergunta foi feita acima); fica esperando
      v_chave := format('%s:%s:%s', v_tipo, v_os, v0);
    end if;
    -- O pedido do dono num dia antes de o material estar garantido: fica (a decisão é dele), com o aviso na frase.
    v_aviso := case when v_e ? 'fixar_de' and v_b ->> 'tipo' <> 'reserva'
                    then public._agenda_aviso_do_material(v_info -> v_os::text -> 'pront', v_e ->> 'condicao_tipo', v_e ->> 'texto', v_ini_x) end;
    -- FASE 7c: (7c P2, §5.2 3, §3.1-3) com modo_habilidade ligado, onde o dono disse quem vai (o pedido com pessoa, a equipe dita), a
    -- palavra dele vale e o item ganha o aviso, ao lado do de material ("— mas João iria sozinho, e o último dia pede quem instala
    -- sozinho com 220 V ou banco de bateria")
    if cf.modo_habilidade = 'ligado' and v_b ->> 'tipo' <> 'reserva'
       and (v_e ? 'fixar_de' or coalesce((v_info -> v_os::text -> 'meios' ->> 'equipe_dita')::boolean, false)) then
      v_aviso := nullif(concat_ws('; ', v_aviso, public._agenda_aviso_da_habilidade(v_os, public._agenda_alocs_do_bloco(v_ctx, v_b), p_hoje)), '');
    end if;
    -- FASE 7c: fim
    v_txt := case
      when v_b ->> 'tipo' = 'reserva' then
        format('%s: %s, %s%s.',
               case v_b ->> 'reserva_de' when 'patio' then 'Reserva no pátio' when 'teto' then 'Reserva (acima da carga)' else 'Reserva' end
                 || ' ' || public._agenda_rotulo_da_os(v_os),
               public._agenda_faixa_texto(v_ini_x, case when (v_b ->> 'ini')::int % 2 = 1 then 'manha' else 'tarde' end,
                                          v_fim_x, case when (v_b ->> 'fim')::int % 2 = 1 then 'manha' else 'tarde' end),
               public._agenda_pessoas_texto(public._agenda_alocs_do_bloco(v_ctx, v_b), v_dono), '')
      else
        format('%s%s: %s, %s%s.', public._agenda_rotulo_da_os(v_os),
               case v_e ->> 'tipo_os' when 'diagnostico' then ', diagnóstico' when 'comissionamento' then ', comissionamento' else '' end,
               public._agenda_dias_texto(array(select distinct (a ->> 'dia')::date
                                                 from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) a)),
               public._agenda_pessoas_texto(public._agenda_alocs_do_bloco(v_ctx, v_b), v_dono),
               coalesce(' — mas ' || v_aviso, '')) end;
    -- FASE 7d: (correção O15) o feriado do município que o bloco atravessa diz o motivo, como o nacional ("sex 20 é Consciência Negra"): "ter 20 é feriado em Balneário Camboriú".
    -- local_txt só existe com o calendário ligado: sem ele, nenhuma leitura
    if v_e ? 'local_txt' and v_b ->> 'tipo' <> 'reserva' then
      v_7d_dt := public._agenda_dias_texto(array(select distinct (a ->> 'dia')::date from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) a));
      v_7d_mf := public._agenda_feriado_do_bloco(v_e -> 'local_txt', v_ini, v_ini_x, v_fim_x);
      if v_7d_mf is not null then
        v_txt := replace(v_txt, ': ' || v_7d_dt || ',', ': ' || case when right(v_7d_dt, 1) = ')' then left(v_7d_dt, -1) || ', ' || v_7d_mf || ')'
                                                                     else v_7d_dt || ' (' || v_7d_mf || ')' end || ',');
      end if;
    end if;
    -- FASE 7d: fim
    -- FASE 7: (7a P3, D7-1) o compromisso marcado pela estimativa do orçamento (a fonte 'orcamento' de agenda_meios_da_os, que
    -- só existe com a regra estimativa) diz isso no fim: "… com Roberto e João (estimativa minha: 6 dias)."
    if v_e ->> 'fonte' = 'orcamento' and v_b ->> 'tipo' <> 'reserva' and right(v_txt, 1) = '.' then
      v_txt := left(v_txt, -1) || format(' (estimativa minha: %s).', public._agenda_dias((v_e ->> 'dias')::numeric));
    end if;
    -- FASE 7: fim
    -- FASE 7b: (7b P4, §6.3, R4.3(a)(3)) ligado: o compromisso com o sábado diz qual e por quê (" — com sáb 14/11 de manhã (Rafael
    -- se ofereceu), para cumprir o prazo de qua 18/11."); o bloco de 1 pessoa da dupla inferida diz em que meios-dias a tarefa pede
    -- 2 e o que fazer (" Nos 2 primeiros meios-dias (qua 04/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex
    -- está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem qua 04/11)."). Em teste, nada aqui (a linha "Em teste" abaixo).
    if v_b ? 'sabado' and right(v_txt, 1) = '.' then
      select array_agg(distinct (a ->> 'dia')::date order by (a ->> 'dia')::date) into v_7b_dias
        from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) a
       where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno';
      v_7b_nomes := array(select y.x from (select a ->> 'nome' as x, min(o) as o
                                             from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) with ordinality t(a, o)
                                            where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno' group by 1) y
                           order by y.o);
      v_txt := left(v_txt, -1) || format(' — com %s de manhã (%s %s)%s.', public._agenda_dias_texto(v_7b_dias),
                 public._agenda_lista(v_7b_nomes), case when cardinality(v_7b_nomes) > 1 then 'se ofereceram' else 'se ofereceu' end,
                 case when v_e ? 'prazo' then ', para cumprir o prazo de ' || public._dia_curto((v_e ->> 'prazo')::date) else '' end);
    end if;
    if v_b ? 'dupla_falta' and cf.modo_dupla = 'ligado' and jsonb_array_length(v_b -> 'dupla_falta') > 0 then
      if v_7b_tec is null then
        v_7b_tec := public._agenda_tecnicos_da_grade(p_hoje);
      end if;
      -- os meios-dias de cada parte: "qua 04/11, manhã e tarde", "qua 04/11 de manhã"
      select public._agenda_lista(array(
               select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                     when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                 from (select v_ini + ((f ->> 'h')::int + 1) / 2 - 1 as d, case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end as t
                         from jsonb_array_elements(v_b -> 'dupla_falta') f where f ->> 'onde' in ('inicio', 'todos')) z
                group by z.d order by z.d)),
             public._agenda_lista(array(
               select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                     when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                 from (select v_ini + ((f ->> 'h')::int + 1) / 2 - 1 as d, case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end as t
                         from jsonb_array_elements(v_b -> 'dupla_falta') f where f ->> 'onde' = 'fim') z
                group by z.d order by z.d))
        into v_7b_x, v_7b_y;
      v_7b_n := (select count(*)::int from jsonb_array_elements(v_b -> 'dupla_falta') f where f ->> 'onde' = 'inicio');
      v_7b_z := case
        when coalesce((v_e ->> 'dupla_todos')::boolean, false)
          then format('O serviço todo pede 2 pessoas (%s) e %s: vai com 1 pessoa; se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                      coalesce(v_e ->> 'dupla_rot_todos', 'o orçamento previu 2 técnicos'),
                      case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre' else public._agenda_tecnicos_frase(v_7b_tec) end,
                      public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1))
        when v_7b_x <> '' and v_7b_y <> ''
          then format('%s (%s) %s e %s (%s) %s pedem 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                      case when v_7b_n = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_n) end, v_7b_x,
                      v_e ->> 'dupla_rot_ini',
                      case when jsonb_array_length(v_b -> 'dupla_falta') - v_7b_n = 1 then 'no último meio-dia'
                           else format('nos %s últimos meios-dias', jsonb_array_length(v_b -> 'dupla_falta') - v_7b_n) end, v_7b_y,
                      v_e ->> 'dupla_rot_fim',
                      case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre nesses meios-dias' else public._agenda_tecnicos_frase(v_7b_tec) end,
                      public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1))
        else format('%s (%s) %s pede 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                    case when v_7b_x <> '' then case when v_7b_n = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_n) end
                         when jsonb_array_length(v_b -> 'dupla_falta') = 1 then 'No último meio-dia'
                         else format('Nos %s últimos meios-dias', jsonb_array_length(v_b -> 'dupla_falta')) end,
                    case when v_7b_x <> '' then v_7b_x else v_7b_y end,
                    case when v_7b_x <> '' then v_e ->> 'dupla_rot_ini' else v_e ->> 'dupla_rot_fim' end,
                    case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre nesses meios-dias' else public._agenda_tecnicos_frase(v_7b_tec) end,
                    public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1)) end;
      -- (correção da revisão da 7b, achado 23) o exemplo diz todos os dias em que falta a 2ª pessoa, não só o 1º ("ex.: Mateus vem
      -- qua 18 e qui 19/11"): quem seguisse o exemplo ao pé da letra deixava os outros meios-dias sem a 2ª pessoa
      v_7bc_dias := array(select distinct v_ini + ((f ->> 'h')::int + 1) / 2 - 1 from jsonb_array_elements(v_b -> 'dupla_falta') f order by 1);
      if cardinality(v_7bc_dias) > 1 then
        v_7b_z := replace(v_7b_z, format('(ex.: Mateus vem %s).', public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1)),
                          format('(ex.: Mateus vem %s).', regexp_replace(public._agenda_dias_texto(v_7bc_dias), ' \([^()]*\)$', '')));
      end if;
      -- (correção da revisão da 7b: fim)
      -- o texto da ação (agenda_acoes.texto, até 400) junta os itens da mesma OS: com a frase da dupla, o item fica em até 320 — sem
      -- caber a frase inteira, a curta (sem os dias e sem quem está na equipe)
      if char_length(v_txt) + 1 + char_length(v_7b_z) > 320 then
        v_7b_n2 := jsonb_array_length(v_b -> 'dupla_falta') - v_7b_n;
        v_7b_z := case
          when coalesce((v_e ->> 'dupla_todos')::boolean, false) then 'O serviço todo pede 2 pessoas: se chamar um ajudante, me diga os dias dele.'
          when v_7b_x <> '' and v_7b_y <> ''
            then format('%s e %s pedem 2 pessoas: se chamar um ajudante, me diga os dias dele.',
                        case when v_7b_n = 1 then 'O primeiro meio-dia' else format('Os %s primeiros meios-dias', v_7b_n) end,
                        case when v_7b_n2 = 1 then 'o último' else format('os %s últimos', v_7b_n2) end)
          when v_7b_x <> ''
            then format('%s %s pede 2 pessoas: se chamar um ajudante, me diga os dias dele.',
                        case when v_7b_n = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_n) end, v_e ->> 'dupla_rot_ini')
          else format('%s %s pede 2 pessoas: se chamar um ajudante, me diga os dias dele.',
                      case when v_7b_n2 = 1 then 'No último meio-dia' else format('Nos %s últimos meios-dias', v_7b_n2) end, v_e ->> 'dupla_rot_fim') end;
      end if;
      v_txt := public._agenda_corta(v_txt || ' ' || v_7b_z, 320);
    end if;
    -- FASE 7b: fim
    -- FASE 7e: (7e P4, R7.5-14) a carga que vale na semana do 1º dia do bloco, com a folga ligada: é ela que entra em "não coube na carga de N%" e na troca pela frase do dono (os 2 pontos leem cf.carga_max; depois deles ninguém mais lê essa coluna). Fora de ligado, a mesma de sempre, byte a byte.
    cf.carga_max := case when v_b ->> 'reserva_de' = 'teto' and v_ctx ? 'carga_semana'
                         then coalesce((v_ctx -> 'carga_semana' ->> ((v_ctx -> 'sem' ->> (v_ini_x - v_ini))::int - 1))::numeric, v_7e_cm)
                         else v_7e_cm end;
    -- FASE 7e: fim
    v_itens := v_itens || jsonb_build_object(
      'op', 'criar', 'os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
      'tipo', case when v_b ->> 'tipo' = 'reserva' then 'reserva' else v_e ->> 'tipo_os' end,
      'reserva_de', v_b ->> 'reserva_de', 'alocacoes', public._agenda_alocs_do_bloco(v_ctx, v_b),
      'de', v_ini_x, 'ate', v_fim_x, 'fim_antes', v_e ->> 'fim_antes', 'fim_depois', v_fim_dep,
      'atraso_du', case when v_b ->> 'tipo' <> 'reserva' and v_e ->> 'fim_antes' is not null and v_fim_dep > (v_e ->> 'fim_antes')::date
                        then public.agenda_du_entre((v_e ->> 'fim_antes')::date, v_fim_dep) end,
      'condicao_tipo', case when v_b ->> 'reserva_de' = 'condicionada' then v_e ->> 'condicao_tipo' end,
      'critica', v_tipo, 'pergunta_chave', v_chave, 'decisao', v_decisao, 'espera', (v_b ->> 'espera')::boolean,
      'interrupcoes', (v_b ->> 'int')::int, 'meios_do_dono', (v_b ->> 'md')::int, 'fonte', v_e ->> 'fonte', 'dias', v_e -> 'dias',
      'evento_real', (v_e ->> 'evento_real')::boolean, 'fixar_dono', v_e ? 'fixar_de', 'aviso_material', v_aviso,
      'abre', (v_e ->> 'abre')::boolean and v_b ->> 'tipo' <> 'reserva', 'fecha', (v_e ->> 'fecha')::boolean and v_b ->> 'tipo' <> 'reserva',
      'motivos', to_jsonb(array_remove(array[
         case when v_e ->> 'classe' = '1' and not v_e ? 'fixar_de' then 'em andamento ou fixada' end,
         case when v_e ? 'fixar_de' then 'você pediu' end,
         case when (v_e ->> 'evento_real')::boolean then 'replanejado por um imprevisto de hoje ou amanhã' end,
         case when v_b ->> 'tipo' <> 'reserva' then v_e ->> 'texto' end,
         case when v_b ->> 'reserva_de' = 'teto' then 'não coube na carga de ' || public._agenda_num(cf.carga_max * 100, 0) || '%' end,
         case when v_b ->> 'reserva_de' = 'condicionada' then v_e ->> 'texto' end,
         case when v_b ->> 'reserva_de' = 'patio' then 'adiantar no pátio enquanto o bem está fora' end], null)),
      'texto', v_txt, 'aplicado', false);
    -- FASE 7d: (7d P4, §5.4 3, §6.2, R6.8-3) o item que entra ganha local_texto, suposicoes, viagem e imax_os (só com os modos ligados: é o que o 7g mostra;
    -- nada novo é gravado fora de agenda_propostas.itens). As 2 suposições que só o bloco sabe: "juntei com Kalmar (OS-00033) no mesmo dia, na
    -- Marina Itajaí" e "evitei pôr a mesma pessoa em Balneário Camboriú e em Penha no mesmo dia (temporada)"
    if v_e ? 'suposicoes' then
      v_7d_sup := array(select x from jsonb_array_elements_text(v_e -> 'suposicoes') x);
      if v_7d_ml and coalesce((v_b ->> 'mesmo')::boolean, false) and (v_ctx -> 'loc' ->> ((v_b ->> 'i')::int - 1))::int > 0 then
        select (v_ctx -> 'oss' ->> (z.x - 1))::uuid into v_7d_os
          from (select abs((v_ctxf -> 'fr' ->> ((m.h - 1) * 4 + s.s - 1))::int) as x, m.h, s.s
                  from (select distinct 2 * d.d - k.k as h
                          from (select distinct (hh + 1) / 2 as d from unnest(public._agenda_ints(v_b -> 'h')) hh) d, generate_series(0, 1) k(k)) m,
                       generate_series(1, 4) s(s)) z
         where z.x > 0 and z.x <> (v_b ->> 'i')::int
           and (v_ctx -> 'loc' ->> (z.x - 1))::int = (v_ctx -> 'loc' ->> ((v_b ->> 'i')::int - 1))::int
         order by z.h, z.s
         limit 1;
        if found then
          v_7d_sup := v_7d_sup || format('juntei com %s no mesmo dia, %s', public._agenda_rotulo_da_os(v_7d_os),
                                         v_e ->> 'local_curto');
        end if;
      end if;
      if v_b ? 'evitou' then
        v_7d_x := (v_ctx -> 'mun' ->> ((v_b ->> 'i')::int - 1))::int;
        v_7d_sup := v_7d_sup || format('evitei pôr a mesma pessoa em %s e em %s no mesmo dia (temporada)',
                                       v_ctx -> 'mun_nomes' ->> (v_7d_x - 1), v_ctx -> 'mun_nomes' ->> ((v_b ->> 'evitou')::int - 1));
      end if;
      v_itens := jsonb_set(v_itens, '{-1}', (v_itens -> -1) || jsonb_build_object('suposicoes', to_jsonb(v_7d_sup))
                 || jsonb_strip_nulls(jsonb_build_object('local_texto', v_e ->> 'local_texto', 'viagem', v_e ->> 'viagem', 'imax_os', v_e -> 'imax_os')));
    end if;
    -- FASE 7d: fim
    -- FASE 7c: (7c P2, §5.2 3, §6.8) os motivos do compromisso, nesta ordem: o que a OS pede e quem vai (com modo_habilidade ligado e
    -- algum meio-dia do bloco pedindo: "pede quem instala sozinho com 220 V ou banco de bateria, no último dia: vai Roberto" — quem
    -- vai é quem tem o que o meio-dia pede, ou você no turno), a troca avisada do responsável ("troquei o responsável: Roberto não
    -- está livre até qua 11/11; segui com João") e o responsável que saiu da equipe ("Roberto, o responsável, não está na equipe
    -- agora"). A troca e o responsável fora só existem com modo_lider ou modo_habilidade ligado.
    v_7c_mot := '{}';
    if v_b ->> 'tipo' <> 'reserva' then
      if cf.modo_habilidade = 'ligado' and v_e ->> 'exig_texto' is not null then
        v_7c_txt := public._agenda_lista(array(
          select y.nome
            from (select case when t.p = (v_ctx ->> 'dono')::int then 'você' else v_ctx -> 'nomes' ->> (t.p - 1) end as nome, min(t.h) as h
                    from unnest(public._agenda_ints(v_b -> 'p'), public._agenda_ints(v_b -> 'h'), public._agenda_ints(v_b -> 'pr'),
                                public._agenda_ints(v_b -> 'ex')) t(p, h, pr, ex)
                   where t.pr = 0 and coalesce(t.ex, 0) <> 0
                     and (t.p = (v_ctx ->> 'dono')::int
                          or (t.ex & 9 <> 0 and (v_ctx -> 'hab' ->> ((t.p - 1) * 4))::int >= cf.habilidade_nivel_energizado)
                          or (t.ex & 2 <> 0 and (v_ctx -> 'hab' ->> ((t.p - 1) * 4 + 1))::int >= cf.habilidade_nivel_comissionar)
                          or (t.ex & 8 <> 0 and (v_ctx -> 'hab' ->> ((t.p - 1) * 4 + 1))::int >= cf.habilidade_nivel_diagnostico)
                          or (t.ex & 4 <> 0 and (v_ctx -> 'hab' ->> ((t.p - 1) * 4 + 2))::int >= cf.habilidade_nivel_altura))
                   group by 1) y
           order by y.h, y.nome));
        if coalesce(v_7c_txt, '') <> '' then
          v_7c_mot := v_7c_mot || format('pede %s: vai %s', v_e ->> 'exig_texto', v_7c_txt);
        end if;
      end if;
      if coalesce((v_b ->> 'lt')::boolean, false) then
        -- o 1º dia, do início do bloco em diante, em que o responsável está livre de manhã ou de tarde na grade de antes do encaixe
        v_7c_lp := coalesce((v_e ->> 'lid')::int, 0);
        v_7c_d := null;
        if v_7c_lp > 0 then
          select min(g) into v_7c_d from generate_series(((v_b ->> 'ini')::int + 1) / 2, (v_ctx ->> 'nd')::int) g
           where ((v_ctx -> 'cap' ->> ((v_7c_lp - 1) * (v_ctx ->> 'nh')::int + 2 * g - 2))::int = 1
                  and (v_ctx -> 'ocup' ->> ((v_7c_lp - 1) * (v_ctx ->> 'nh')::int + 2 * g - 2))::int in (0, -(v_b ->> 'i')::int))
              or ((v_ctx -> 'cap' ->> ((v_7c_lp - 1) * (v_ctx ->> 'nh')::int + 2 * g - 1))::int = 1
                  and (v_ctx -> 'ocup' ->> ((v_7c_lp - 1) * (v_ctx ->> 'nh')::int + 2 * g - 1))::int in (0, -(v_b ->> 'i')::int));
        end if;
        v_7c_mot := v_7c_mot || format('troquei o responsável: %s não está livre %s; segui com %s', v_e ->> 'lid_nome',
                                       case when v_7c_d is null then format('nas próximas %s semanas', cf.horizonte_semanas)
                                            else 'até ' || public._dia_curto(v_ini + v_7c_d - 1) end,
                                       coalesce(nullif(public._agenda_lista(array(
                                         select y.nome from (select v_ctx -> 'nomes' ->> (t.p - 1) as nome, min(t.h) as h
                                                               from unnest(public._agenda_ints(v_b -> 'p'), public._agenda_ints(v_b -> 'h'),
                                                                           public._agenda_ints(v_b -> 'pr')) t(p, h, pr)
                                                              where t.pr = 0 and t.p <> (v_ctx ->> 'dono')::int group by 1) y
                                          order by y.h, y.nome)), ''), 'você'));
      end if;
      if coalesce((v_e ->> 'lid_fora')::boolean, false) then
        v_7c_mot := v_7c_mot || format('%s, o responsável, não está na equipe agora', v_e ->> 'lid_nome');
      end if;
    end if;
    if cardinality(v_7c_mot) > 0 then
      v_itens := jsonb_set(v_itens, '{-1,motivos}', coalesce(v_itens -> -1 -> 'motivos', '[]'::jsonb) || to_jsonb(v_7c_mot));
    end if;
    -- FASE 7c: fim
    -- FASE 7c: (7c correção, achado 9) a troca avisada do responsável também vai no TEXTO do item — o que vira a ação do "o que mudou",
    -- a linha "Mudei sozinho" do fechamento, o aviso do gestor e *agenda <OS>* —, não só nos motivos (que ninguém lia): "Edu (OS-97175):
    -- sex 06 e seg 09/11, você fecha, João os 2 dias, … — troquei o responsável: Roberto não está livre até qua 11/11; segui com João,
    -- Bruno e Alex." Sem caber em c_c9_max, a curta "— troquei o responsável (Roberto não está livre)". Só existe com modo_lider ou
    -- modo_habilidade ligado (o lt do bloco, que põe o motivo acima).
    v_c9_tr := (select x from unnest(v_7c_mot) x where x like 'troquei o responsável:%' limit 1);
    if v_c9_tr is not null and v_b ->> 'tipo' <> 'reserva' then
      v_c9_txt := rtrim(v_itens -> -1 ->> 'texto', '.') || ' — ' || v_c9_tr || '.';
      if char_length(v_c9_txt) > c_c9_max then
        v_c9_txt := rtrim(v_itens -> -1 ->> 'texto', '.') || format(' — troquei o responsável (%s não está livre).', v_e ->> 'lid_nome');
      end if;
      v_itens := jsonb_set(v_itens, '{-1,texto}', to_jsonb(public._agenda_corta(v_c9_txt, c_c9_max)));
    end if;
    -- FASE 7c: fim
    -- FASE 7b: (7b P4, §6.4) o item leva a dupla da OS (o texto do cartão e do foco), os meios-dias que pediam 2 e não têm a 2ª pessoa
    -- (dupla_falta [{dia, turno, onde}]) e o sábado usado; só com os modos da 7b
    if v_e ? 'dk' or v_b ? 'sabado' then
      v_itens := jsonb_set(v_itens, '{-1}', (v_itens -> -1) || jsonb_strip_nulls(jsonb_build_object(
        'dupla', v_e ->> 'dupla_texto', 'dupla_fonte', v_e ->> 'dupla_fonte',
        'dupla_falta', (select jsonb_agg(jsonb_build_object('dia', v_ini + ((f ->> 'h')::int + 1) / 2 - 1,
                                                           'turno', case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end,
                                                           'onde', f ->> 'onde') order by (f ->> 'h')::int)
                          from jsonb_array_elements(v_b -> 'dupla_falta') f),
        'sabado', case when v_b ? 'sabado' then true end)));
    end if;
    -- FASE 7b: fim
    -- CORREÇÃO FASE 6: (C1) item 14: a reserva por teto da OS que precisa do dono (abre, fecha ou o turno dele), com a
    -- capacidade do dono em uso abaixo da carga de todos (_agenda_carga_da_pessoa), diz a parte da semana DELE: "não coube na
    -- sua parte da semana (56%)", e não "na carga de 80%". Sem nada em uso, o item é o de antes, byte a byte.
    if v_b ->> 'reserva_de' = 'teto'
       and (coalesce((v_e ->> 'abre')::boolean, false) or coalesce((v_e ->> 'fecha')::boolean, false)
            or coalesce((v_e ->> 'dt_m')::boolean, false) or coalesce((v_e ->> 'dt_t')::boolean, false))
       and public._agenda_carga_da_pessoa(v_dono) < cf.carga_max then
      v_itens := jsonb_set(v_itens, '{-1,motivos}',
                   (select coalesce(jsonb_agg(case when m #>> '{}' = 'não coube na carga de ' || public._agenda_num(cf.carga_max * 100, 0) || '%'
                                                   then to_jsonb('não coube na sua parte da semana ('
                                                                 || public._agenda_num(public._agenda_carga_da_pessoa(v_dono) * 100, 0) || '%)')
                                                   else m end order by o), '[]'::jsonb)
                      from jsonb_array_elements(v_itens -> -1 -> 'motivos') with ordinality t(m, o)));
    end if;
    -- CORREÇÃO FASE 6: fim
    -- FASE 7e: (7e P4, §5.3 (a) e (b), R7.3-4) o compromisso da OS urgente ou puxada diz por quê. Ao dono, nunca "urgente" sozinho: a frase diz o motivo, e só fala em usar a folga quando a semana passou mesmo do teto de compromisso (a soma da equipe contra o teto dela; sem o teto da equipe, a pessoa contra o teto dela). A soma é a final, com o que o dono fixou.
    if v_b ->> 'tipo' <> 'reserva' and (v_e ? 'urgente' or v_e ? 'puxada') then
      select coalesce(bool_or(case when v_ctx ? 'teto_equipe'
               then (select coalesce(sum((v_ctxf -> 'uso_c' ->> ((p.p - 1) * (v_ctx ->> 'nw')::int + x.w - 1))::int), 0)
                       from generate_series(1, (v_ctx ->> 'np')::int) p(p) where p.p <> (v_ctx ->> 'dono')::int) > (v_ctx -> 'teto_equipe' ->> (x.w - 1))::int
               else (v_ctxf -> 'uso_c' ->> ((x.pp - 1) * (v_ctx ->> 'nw')::int + x.w - 1))::int > (v_ctx -> 'teto80' ->> ((x.pp - 1) * (v_ctx ->> 'nw')::int + x.w - 1))::int end), false)
        into v_7e_pas
        from (select distinct array_position(v_pes, (a ->> 'payee_id')::uuid) as pp, ((a ->> 'dia')::date - v_ini) / 7 + 1 as w
                from jsonb_array_elements(v_itens -> -1 -> 'alocacoes') a where a ->> 'presenca' = 'turno') x;
      v_7e_m := array_remove(array[case when v_e ? 'urgente' and v_7e_pas then format('urgente: %s; usei a folga da semana', v_e ->> 'urgente_texto') end,
                                   case when v_e ? 'puxada' then 'puxada para a folga que sobrou de amanhã' end], null);
      v_itens := jsonb_set(v_itens, '{-1}', (v_itens -> -1) || case when v_e ? 'urgente' then '{"urgente": true}'::jsonb else '{}'::jsonb end
                                            || jsonb_build_object('motivos', (v_itens -> -1 -> 'motivos') || to_jsonb(v_7e_m)));
    end if;
    -- FASE 7e: fim
  end loop;

  -- A condição e a data-limite das reservas condicionadas (do 1º dia de cada uma: o "compre até" daquele início).
  select coalesce(jsonb_agg(case when i ->> 'reserva_de' = 'condicionada' then
             i || x.c || jsonb_build_object('texto', rtrim(i ->> 'texto', '.') || ' — ' || (x.c ->> 'condicao') || '.')
           else i end order by k), '[]'::jsonb)
    into v_itens
    from jsonb_array_elements(v_itens) with ordinality t(i, k)
    cross join lateral (select case when i ->> 'reserva_de' = 'condicionada'
                                    then public._agenda_condicao_da_reserva((i ->> 'os')::uuid, i ->> 'condicao_tipo', (i ->> 'de')::date,
                                                                            v_info -> (i ->> 'os') -> 'pront', p_hoje) end as c) x;

  -- FASE 7c: (7c P2, §5.2 7) o "por que não cabe" lê os modos e os níveis da 7c no contexto (o que cada pessoa faz já está nele)
  v_ctx := v_ctx || jsonb_build_object('hab_modo', (cf.modo_habilidade = 'ligado')::int, 'n', v_par -> 'n',
                                       'fcobre', cf.habilidade_fechamento_cobre);
  -- FASE 7c: fim
  -- FASE 7d: (7d P4, §5.4) o "por que não cabe" lê o pátio como o motor o deixou
  if v_rf ? 'pat_int' then
    v_ctx := v_ctx || jsonb_build_object('pat_int', v_rf -> 'pat_int');
  end if;
  -- FASE 7d: fim
  -- ── 7. O que fica de fora, com quem trava ──
  for v_e in select e from jsonb_array_elements(v_fila) e order by (e ->> 'ordem')::int loop
    v_os := (v_e ->> 'os')::uuid;
    continue when exists (select 1 from jsonb_array_elements(v_itens) i where (i ->> 'os')::uuid = v_os and i ->> 'op' = 'criar');
    v_x := (v_e ->> 'i')::int;
    v_txt := null;
    v_chave := null;
    if v_x = any (v_xnc) and exists (select 1 from jsonb_array_elements(v_perg) q where (q ->> 'x')::int = v_x) then
      select q ->> 'chave' into v_chave from jsonb_array_elements(v_perg) q where (q ->> 'x')::int = v_x;
      v_txt := format('%s: não cabe até %s — preciso de você.', public._agenda_rotulo_da_os(v_os), public._dia_curto((v_e ->> 'precisa')::date));
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                             'motivo', 'nao_cabe', 'texto', v_txt, 'pergunta_chave', v_chave);
      continue;
    end if;
    if v_x = any (v_sem_q) then
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                 'motivo', 'sem_encaixe',
                 'texto', format('%s: sem encaixe com a equipe de hoje (nem atrasando outra OS).', public._agenda_rotulo_da_os(v_os)));
      continue;
    end if;
    if (v_e ->> 'classe')::int = 4 then
      v_txt := format('%s: %s.', public._agenda_rotulo_da_os(v_os), rtrim(v_e ->> 'texto', '.'));
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                             'motivo', v_e ->> 'motivo', 'texto', v_txt);
      continue;
    end if;
    continue when coalesce((v_e ->> 'passos')::int, 0) <= 0;
    -- FASE 7b: (7b P4, R4.3(c)) a dupla dita que só saiu da espera da classe 4 por quem vem sob demanda (dupla_sd) e não achou bloco:
    -- vai ao "fora" com o motivo dupla (o da classe 4: o aviso, o foco e o cartão dizem "falta a 2ª pessoa"), com as datas de quem
    -- vem — nunca o "sem lugar" calado.
    if coalesce((v_e ->> 'dupla_sd')::boolean, false)
       and exists (select 1 from jsonb_array_elements(v_rf -> 'fora') f where (f ->> 'i')::int = v_x and f ->> 'motivo' in ('sem_encaixe', 'sem_reserva')) then
      select public._agenda_lista(array_agg(format('%s só vem %s (%s)', x.nome, public._agenda_dias_texto(x.dias),
                                                  public._agenda_plural(x.n, 'meio-dia', 'meios-dias')) order by x.nome)),
             count(*)::int
        into v_7b_x, v_7b_n
        from (select k.pessoa as nome, k.payee_id, array_agg(distinct k.dia order by k.dia) as dias, count(*)::int as n
                from public.agenda_capacidade(p_hoje, p_hoje + 7 * cf.horizonte_semanas - 1, p_hoje) k
               where not k.eh_dono and k.situacao = 'livre' and public._agenda_e_sob_demanda(k.payee_id, p_hoje)
               group by k.pessoa, k.payee_id) x;
      v_txt := format('%s: precisa de %s pessoas em %s e %s: me diga mais dias %s ou chame outro ajudante.',
                      public._agenda_rotulo_da_os(v_os), v_e ->> 'dupla_n',
                      public._agenda_plural((v_e ->> 'dupla_meios_n')::int, 'meio-dia', 'meios-dias'),
                      coalesce(nullif(v_7b_x, ''), 'quem vem sob demanda não cobre'), case when v_7b_n > 1 then 'deles' else 'dele' end);
      -- (correção da revisão da 7b, achado 22) quando os dias de quem vem sob demanda são todos antes de a OS ficar pronta, o
      -- porquê é a data, não a falta de dias ("… e Mateus só vem seg 09 e qui 12/11 (4 meios-dias), antes de o serviço ficar pronto (qua
      -- 18/11): me diga dias dele a partir de qua 18/11 ou chame outro ajudante.")
      v_7bc_est := (public.os_prontidao(v_os, p_hoje) ->> 'est')::date;
      select max(k.dia) into v_7bc_max
        from public.agenda_capacidade(p_hoje, p_hoje + 7 * cf.horizonte_semanas - 1, p_hoje) k
       where not k.eh_dono and k.situacao = 'livre' and public._agenda_e_sob_demanda(k.payee_id, p_hoje);
      if v_7bc_est is not null and v_7bc_max is not null and v_7bc_max < v_7bc_est and nullif(v_7b_x, '') is not null then
        v_txt := format('%s: precisa de %s pessoas em %s e %s, antes de o serviço ficar pronto (%s): me diga dias %s a partir de %s ou chame outro ajudante.',
                        public._agenda_rotulo_da_os(v_os), v_e ->> 'dupla_n',
                        public._agenda_plural((v_e ->> 'dupla_meios_n')::int, 'meio-dia', 'meios-dias'), v_7b_x,
                        public._dia_curto(v_7bc_est), case when v_7b_n > 1 then 'deles' else 'dele' end, public._dia_curto(v_7bc_est));
      end if;
      -- (correção da revisão da 7b: fim)
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                             'motivo', 'dupla', 'texto', v_txt);
      continue;
    end if;
    -- FASE 7b: fim
    select f ->> 'motivo' into v_tipo from jsonb_array_elements(v_rf -> 'fora') f where (f ->> 'i')::int = v_x limit 1;
    if v_tipo is null then
      select b into v_b from jsonb_array_elements(v_rf -> 'colocadas') b where (b ->> 'i')::int = v_x and b ->> 'tipo' = 'compromisso';
      if v_b is not null and not coalesce((v_b ->> 'na_janela')::boolean, true) then
        v_tipo := 'depois';
        v_txt := format('%s: começa %s%s.', public._agenda_rotulo_da_os(v_os),
                        public._dia_curto(v_ini + ((v_b ->> 'ini')::int + 1) / 2 - 1),
                        coalesce(' (' || (select r ->> 'texto' from jsonb_array_elements(v_info -> v_os::text -> 'pront' -> 'restricoes') r
                                           where r ->> 'tipo' in ('bem', 'nao_antes') limit 1) || ')', ''));
      elsif v_x = any (v_h) then
        v_tipo := 'espera';
        v_txt := format('%s: espera a sua decisão.', public._agenda_rotulo_da_os(v_os));
      end if;
    end if;
    -- FASE 7c: (7c P2, §5.2 5, §6.8) o fora habilidade (do encaixe: não coube com quem o serviço pede, cabia sem ele): o que ela pede
    -- e que ninguém com isso fica livre junto no horizonte; no dia que o dono pediu, o "não cabe <dia>" de sempre, com o porquê do
    -- dia ("ninguém que sobe no teto fica livre nesse dia")
    if v_tipo = 'habilidade' and v_txt is null then
      v_txt := case when v_e ? 'fixar_de'
                    then format('%s: não cabe %s: %s.', public._agenda_rotulo_da_os(v_os), public._dia_curto(v_ini + (v_e ->> 'fixar_de')::int - 1),
                                public._agenda_por_que_nao(v_ctx, v_e, (v_e ->> 'fixar_de')::int, cf.wip_max))
                    else format('%s: pede %s e ninguém com isso fica livre junto nas próximas %s semanas.', public._agenda_rotulo_da_os(v_os),
                                concat_ws(' e ', public._agenda_exigencia_texto(nullif(coalesce((v_e ->> 'ext')::int, 0), 0),
                                                                                case when coalesce((v_e ->> 'passos')::int, 0) > 1 then 'todos' end),
                                                 public._agenda_exigencia_texto(nullif(coalesce((v_e ->> 'exu')::int, 0), 0), 'ultimo')),
                                cf.horizonte_semanas) end;
    end if;
    -- FASE 7c: fim
    -- FASE 7d: (7d P4, R6.3-7, §6.2) a OS que não coube no pátio: motivo sem_encaixe (o que a linha da semana conhece) com patio_cheio e o texto próprio.
    -- Sem vagas ditas, nem nasce.
    if v_tipo = 'sem_encaixe' and v_txt is null
       and exists (select 1 from jsonb_array_elements(v_rf -> 'fora') f where (f ->> 'i')::int = v_x and coalesce((f ->> 'patio_cheio')::boolean, false)) then
      v_7d_x := (v_ctx -> 'pat' ->> (v_x - 1))::int;
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
        'motivo', 'sem_encaixe', 'patio_cheio', true,
        'texto', format('%s: %s. Me diga se cabe mais um, ou quando outro motorhome sai.', public._agenda_rotulo_da_os(v_os),
                        public._agenda_patio_frase(v_ctx -> 'pat_nomes' ->> (v_7d_x - 1), (v_ctx -> 'pat_max' ->> (v_7d_x - 1))::int, false)));
      continue;
    end if;
    -- FASE 7d: fim
    -- FASE 7d: (correção O14) a viagem com pernoite que não coube: o motivo é a janela de dias seguidos, não "a equipe de hoje". A chave viagem só existe com o modo ligado
    if v_tipo = 'sem_encaixe' and v_txt is null and v_e ->> 'viagem' = 'pernoite' then
      v_txt := format('%s: a viagem precisa de %s seguidos com a mesma equipe, e não achei essa janela em %s semanas.', public._agenda_rotulo_da_os(v_os),
                      public._agenda_plural(ceil(coalesce((v_e ->> 'passos')::numeric, 0) / 2)::int, 'dia útil', 'dias úteis'), cf.horizonte_semanas);
    end if;
    -- FASE 7d: fim
    continue when v_tipo is null;
    v_txt := coalesce(v_txt, format('%s: %s.', public._agenda_rotulo_da_os(v_os), case v_tipo
      when 'padrao_do_dono' then 'falta você dizer quais dias fica em campo'
      when 'fixar_nao_cabe' then format('não cabe %s: %s', public._dia_curto(v_ini + (v_e ->> 'fixar_de')::int - 1),
                                        public._agenda_por_que_nao(v_ctx, v_e, (v_e ->> 'fixar_de')::int, cf.wip_max))
      when 'sem_reserva' then rtrim(v_e ->> 'texto', '.') || ' (sem lugar para a reserva nesta semana)'
      when 'so_com_voce' then rtrim(v_e ->> 'texto', '.') || ' (é só com você: entra quando isso estiver respondido)'
      else format('sem encaixe em %s semanas com a equipe de hoje', cf.horizonte_semanas) end));
    v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                           'motivo', v_tipo, 'texto', v_txt);
  end loop;
  -- (as que saíram da carteira e tinham plano)
  v_fora := v_fora || coalesce((
    select jsonb_agg(jsonb_build_object('os', x.os, 'numero', v_info -> x.os::text -> 'pront' ->> 'numero',
             'cliente_curto', v_info -> x.os::text -> 'pront' ->> 'cliente_curto', 'motivo', 'fora_da_carteira',
             'texto', format('%s: %s.', public._agenda_rotulo_da_os(x.os), v_info -> x.os::text -> 'pront' ->> 'estado_texto'))
             order by v_info -> x.os::text -> 'pront' ->> 'numero')
      from (select distinct (c ->> 'os')::uuid as os from jsonb_array_elements(v_canc) c where c ->> 'motivo' = 'os_saiu') x
     where not (x.os = any (v_escopo))), '[]'::jsonb);

  -- ── 8. A carga por pessoa e semana (o publicável sem esperar) ──
  select coalesce(jsonb_object_agg(p.id, jsonb_build_object('nome', p.nome, 'semanas', p.semanas)), '{}'::jsonb) into v_carga
    from (select (v_ctx -> 'pessoas' ->> (pp - 1)) as id, (v_ctx -> 'nomes' ->> (pp - 1)) as nome,
                 jsonb_agg(jsonb_build_object(
                   'semana', v_seg + 7 * (ww - 1),
                   'esperado', (v_ctxf -> 'esperado' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'teto80', (v_ctxf -> 'teto80' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'teto100', (v_ctxf -> 'teto100' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'compromisso', (v_ctxf -> 'uso_c' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'reserva', (v_ctxf -> 'uso_r' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1))) order by ww) as semanas
            from generate_series(1, (v_ctx ->> 'np')::int) pp
            cross join generate_series((v_de - v_seg) / 7 + 1, (v_ate - v_seg) / 7 + 1) ww
           group by pp) p;

  -- ── 9. A pontuação (para comparar alternativas) ──
  select jsonb_build_object(
           'atraso_dias', coalesce(sum(greatest((i ->> 'fim_depois')::date - (v_ent -> x.ii ->> 'precisa')::date, 0))
                                     filter (where v_ent -> x.ii ->> 'precisa' is not null), 0),
           'mudancas', (select count(*) from jsonb_array_elements(v_canc) c where not (c ->> 'violada')::boolean and c ->> 'motivo' = 'replanejado'),
           'meios_do_dono', coalesce(sum((i ->> 'meios_do_dono')::int), 0),
           'interrupcoes', coalesce(sum((i ->> 'interrupcoes')::int), 0),
           'fim', coalesce(sum((i ->> 'ate')::date - v_ini), 0))
    into v_pont
    from jsonb_array_elements(v_itens) i
    cross join lateral (select (select e ->> 'i' from jsonb_array_elements(v_fila) e where e ->> 'os' = i ->> 'os') as ii) x
   where i ->> 'op' = 'criar' and not coalesce((i ->> 'espera')::boolean, false);
  v_pont := v_pont || jsonb_build_object('total',
    (v_pont ->> 'atraso_dias')::bigint * c_peso_atraso + (v_pont ->> 'mudancas')::bigint * c_peso_mudanca
    + (v_pont ->> 'meios_do_dono')::bigint * c_peso_dono + (v_pont ->> 'interrupcoes')::bigint * c_peso_interr
    + (v_pont ->> 'fim')::bigint * c_peso_fim);

  -- ── 10. Os textos prontos ──
  v_feriados := array(select format('%s é %s', public._agenda_dia_sem_mes(g::date), public.agenda_feriado(g::date))
                        from generate_series(v_de - (extract(isodow from v_de)::int - 1), v_ate, interval '1 day') g
                       where extract(isodow from g)::int <= 5 and public.agenda_feriado(g::date) is not null order by g);
  v_titulo := case when p_escopo = 'semana'
    then format('Semana de %s a %s', to_char(v_de, 'DD'),
                to_char(coalesce((select max(g::date) from generate_series(v_de, v_ate, interval '1 day') g
                                   where public.agenda_dia_util(g::date)), v_ate), 'DD/MM'))
         || coalesce(' (' || nullif(array_to_string(v_feriados, ', '), '') || ')', '')
    else 'Mudanças na agenda' end;
  v_linhas := array(select i ->> 'texto' || case when coalesce((i ->> 'espera')::boolean, false) then ' (espera a sua decisão)' else '' end
                      from jsonb_array_elements(v_itens) with ordinality t(i, k)
                     order by i ->> 'op' = 'cancelar', (i ->> 'de')::date, i ->> 'numero' collate "C", k);
  v_tfora := array(select f ->> 'texto' from jsonb_array_elements(v_fora) with ordinality t(f, k) order by k);
  v_textos := jsonb_build_object('titulo', v_titulo, 'linhas', to_jsonb(v_linhas), 'fora', to_jsonb(v_tfora),
    'carga', to_jsonb(array(
      select format('%s: %s de %s meios-dias de serviço na semana de %s',
                    case when p.key::uuid is not distinct from v_dono then 'Você' else p.value ->> 'nome' end,
                    s ->> 'compromisso', s ->> 'teto80', to_char((s ->> 'semana')::date, 'DD/MM'))
        from jsonb_each(v_carga) p, jsonb_array_elements(p.value -> 'semanas') s
       where (s ->> 'esperado')::numeric > 0
       order by (s ->> 'semana')::date, p.key::uuid is not distinct from v_dono desc, p.value ->> 'nome')),
    'resumo', format('%s: %s, %s.', v_titulo,
                     public._agenda_plural((select count(distinct i ->> 'os')::int from jsonb_array_elements(v_itens) i
                                             where i ->> 'op' = 'criar' and not (i ->> 'espera')::boolean), 'serviço marcado', 'serviços marcados'),
                     public._agenda_plural(jsonb_array_length(v_fora), 'de fora', 'de fora')));
  -- CORREÇÃO 29/10 (P3): o marcado firme e o reservado separados no resumo e no título da semana (com a agenda automática
  -- ligada). A reserva só guarda o lugar da equipe (nada está marcado até a condição dela se cumprir), e o resumo de antes
  -- contava como "serviço marcado" toda OS que entra: com só a reserva do Lenine, "1 serviço marcado". Com reserva no que
  -- entra (sem o que espera a decisão), o resumo diz quem: "1 reservado (Lenine), nada marcado firme, 10 de fora"; e o título
  -- da semana diz quantos ("Semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme"): é ele que abre o
  -- "Publiquei a semana de …" da aplicação, do que mudou e do fechamento, que listam as OS logo depois. A OS com algum
  -- meio-dia firme conta como marcada. No resumo, o nome curto do cliente, com o número quando o nome se repete ("Kalmar
  -- OS-00032"); até 3 nomes, depois "e mais N". Sem reserva, ou fora de ligado, os dois são os de antes, byte a byte.
  if v_modo = 'ligado' then
    select coalesce(array_agg(x.nome order by x.de, x.numero collate "C") filter (where x.firme), '{}'::text[]),
           coalesce(array_agg(x.nome order by x.de, x.numero collate "C") filter (where not x.firme), '{}'::text[])
      into v_marc, v_resv
      from (select y.numero, y.de, y.firme,
                   case when count(*) over (partition by y.curto) > 1 then concat_ws(' ', y.curto, y.numero) else y.curto end as nome
              from (select min(i ->> 'numero') as numero, min((i ->> 'de')::date) as de, bool_or(i ->> 'tipo' <> 'reserva') as firme,
                           coalesce(public._agenda_nome_curto(min(i ->> 'cliente_curto')), min(i ->> 'numero')) as curto
                      from jsonb_array_elements(v_itens) i
                     where i ->> 'op' = 'criar' and not coalesce((i ->> 'espera')::boolean, false)
                     group by i ->> 'os') y) x;
  end if;
  if cardinality(v_resv) > 0 then
    v_contagem := case when cardinality(v_marc) > 0
                       then format('%s (%s), %s (%s)',
                                   public._agenda_plural(cardinality(v_marc), 'serviço marcado', 'serviços marcados'),
                                   public._agenda_lista(v_marc, 3),
                                   public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'), public._agenda_lista(v_resv, 3))
                       else format('%s (%s), nada marcado firme',
                                   public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'), public._agenda_lista(v_resv, 3))
                  end;
    v_textos := v_textos || jsonb_build_object('resumo', format('%s: %s, %s.', v_titulo, v_contagem,
                                                               public._agenda_plural(jsonb_array_length(v_fora), 'de fora', 'de fora')));
    if p_escopo = 'semana' then
      v_titulo := v_titulo || ' — '
                  || case when cardinality(v_marc) > 0
                          then format('%s, %s', public._agenda_plural(cardinality(v_marc), 'serviço marcado', 'serviços marcados'),
                                      public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'))
                          else format('%s, nada marcado firme', public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'))
                     end;
      v_textos := v_textos || jsonb_build_object('titulo', v_titulo);
    end if;
  end if;
  -- CORREÇÃO 29/10 (P3): fim
  v_texto := v_titulo
    || coalesce(E'\n' || nullif(array_to_string(array(select '• ' || x from unnest(v_linhas) x), E'\n'), ''), E'\nNada a mudar.')
    || coalesce(E'\nFora: ' || nullif(array_to_string(v_tfora, '; '), ''), '')
    || case when p_persistir then '' else E'\nÉ simulação: não muda nada.' end;

  -- FASE 7b: (7b P4, §6.3, R4.3(a)4) em teste, o que a 7b faria e não fez — o sábado ("Em teste: para cumprir o prazo de Vanderlei
  -- (qua 18/11), eu usaria sáb 14/11 de manhã com Rafael, que se ofereceu.") e a dupla de 1 pessoa ("Em teste: no Lenine eu pediria
  -- um ajudante em qua 04/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas."): textos.em_teste e no fim do texto.
  for v_7b_b in select e from jsonb_array_elements(coalesce(v_rf -> 'sab_teste', '[]'::jsonb)) e loop
    v_7b_e := v_ent -> (v_7b_b ->> 'i');
    select array_agg(distinct (a ->> 'dia')::date order by (a ->> 'dia')::date) into v_7b_dias
      from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_7b_b -> 'b')) a
     where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno';
    v_7b_nomes := array(select y.x from (select a ->> 'nome' as x, min(o) as o
                                           from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_7b_b -> 'b')) with ordinality t(a, o)
                                          where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno' group by 1) y
                         order by y.o);
    v_7b_teste := v_7b_teste || case when v_7b_e ? 'prazo'
      then format('Em teste: para cumprir o prazo de %s (%s), eu usaria %s de manhã com %s, que %s.',
                  public._agenda_nome_curto(v_7b_e ->> 'cliente_curto'), public._dia_curto((v_7b_e ->> 'prazo')::date),
                  public._agenda_dias_texto(v_7b_dias), public._agenda_lista(v_7b_nomes),
                  case when cardinality(v_7b_nomes) > 1 then 'se ofereceram' else 'se ofereceu' end)
      else format('Em teste: %s terminaria antes com %s de manhã (%s %s).', public._agenda_nome_curto(v_7b_e ->> 'cliente_curto'),
                  public._agenda_dias_texto(v_7b_dias), public._agenda_lista(v_7b_nomes),
                  case when cardinality(v_7b_nomes) > 1 then 'se ofereceram' else 'se ofereceu' end) end;
  end loop;
  if cf.modo_dupla = 'sombra' then
    for v_7b_b in select b from jsonb_array_elements(v_rf -> 'colocadas') b
                   where b ? 'dupla_falta' and jsonb_array_length(b -> 'dupla_falta') > 0 and coalesce((b ->> 'na_janela')::boolean, true)
                     and not ((b ->> 'i')::int = any (v_xnc) and b ->> 'tipo' = 'compromisso') loop
      v_7b_e := v_ent -> (v_7b_b ->> 'i');
      v_7b_teste := v_7b_teste || format('Em teste: no %s eu pediria um ajudante em %s: %s pede 2 pessoas.',
        public._agenda_nome_curto(v_7b_e ->> 'cliente_curto'),
        public._agenda_lista(array(
          select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ' (manhã e tarde)'
                                                when bool_or(z.t = 'manha') then ' (manhã)' else ' (tarde)' end
            from (select v_ini + ((f ->> 'h')::int + 1) / 2 - 1 as d, case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end as t
                    from jsonb_array_elements(v_7b_b -> 'dupla_falta') f) z
           group by z.d order by z.d)),
        coalesce(case when coalesce((v_7b_e ->> 'dupla_todos')::boolean, false) then v_7b_e ->> 'dupla_rot_todos' end,
                 nullif(public._agenda_lista(array_remove(array[nullif(v_7b_e ->> 'dupla_rot_ini', ''), nullif(v_7b_e ->> 'dupla_rot_fim', '')], null)), ''),
                 'a tarefa'));
    end loop;
  end if;
  if cardinality(v_7b_teste) > 0 then
    v_textos := v_textos || jsonb_build_object('em_teste', to_jsonb(v_7b_teste));
    v_texto := v_texto || E'\n' || array_to_string(v_7b_teste, E'\n');
  end if;
  -- FASE 7b: fim
  -- ── 11. A validação: proposta inválida nunca sai ──
  v_viol := public._agenda_validar_itens(v_itens, jsonb_build_object('p_restricoes', v_r), p_hoje, p_agora, false,
              (select jsonb_object_agg(k, x -> 'pront') from jsonb_each(v_info) t(k, x)));
  if jsonb_array_length(v_viol) > 0 then
    raise exception 'agenda_propor: a proposta saiu inválida (erro do motor): %', v_viol::text
      using errcode = 'P0001', detail = left(v_texto, 2000);
  end if;

  -- ── 12. Persistir ──
  if p_persistir then
    -- a aberta anterior do mesmo escopo e modo (e das mesmas OS, fora da semana) fica obsoleta; as alocações dela saem
    for v_q in
      select to_jsonb(pr) from public.agenda_propostas pr
       where pr.estado = 'aberta' and pr.escopo = p_escopo and pr.modo = v_modo
         and (p_escopo = 'semana' or pr.os_alvo && v_escopo)
       order by pr.criada_em, pr.id
    loop
      update public.agenda_propostas set estado = 'obsoleta', motivo_fim = 'refeita' where id = (v_q ->> 'id')::uuid;
      delete from public.agenda_alocacoes where proposta_id = (v_q ->> 'id')::uuid and estado = 'proposta';
    end loop;
    v_pid := gen_random_uuid();
    -- os ids das alocações novas entram no item (é por eles que o aplicar publica)
    select coalesce(jsonb_agg(case when i ->> 'op' = 'criar'
             then i || jsonb_build_object('alocacoes', (select jsonb_agg(a || jsonb_build_object('alocacao_id', gen_random_uuid()) order by j)
                                                          from jsonb_array_elements(i -> 'alocacoes') with ordinality u(a, j)))
             else i end order by k), '[]'::jsonb)
      into v_itens
      from jsonb_array_elements(v_itens) with ordinality t(i, k);
    v_expira := least(p_agora + cf.proposta_validade,
                      coalesce((select min(lower(public.agenda_periodo((a ->> 'dia')::date, a ->> 'turno', a ->> 'presenca')))
                                  from jsonb_array_elements(v_itens) i, jsonb_array_elements(i -> 'alocacoes') a
                                 where i ->> 'op' = 'criar'), p_agora + cf.proposta_validade));
    insert into public.agenda_propostas (id, escopo, periodo, os_alvo, versao_base, modo, estado, itens, fora, carga, textos,
                                         parametros, pontuacao, criada_por, autor, criada_em, expira_em)
    values (v_pid, p_escopo, daterange(v_de, v_ate, '[]'), v_escopo, v0, v_modo, 'aberta', v_itens, v_fora, v_carga, v_textos,
            jsonb_build_object('p_hoje', p_hoje, 'p_agora', p_agora, 'p_de', p_de, 'p_ate', p_ate, 'p_os', to_jsonb(p_os),
                               'p_restricoes', v_r, 'escopo', p_escopo, 'origem', p_origem, 'de', v_de, 'ate', v_ate),
            v_pont, p_origem, p_autor, p_agora, v_expira);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id,
                                         reserva_de, condicao, condicao_tipo, condicao_ate, motivos, criado_em)
    select (a ->> 'alocacao_id')::uuid, (i ->> 'os')::uuid, (a ->> 'payee_id')::uuid, (a ->> 'dia')::date, a ->> 'turno',
           a ->> 'presenca', i ->> 'tipo', 'proposta', case when (i ->> 'fixar_dono')::boolean then 'dono' else 'motor' end, v_pid,
           i ->> 'reserva_de', case when a ->> 'presenca' = 'turno' then i ->> 'condicao' end,
           case when a ->> 'presenca' = 'turno' then i ->> 'condicao_tipo' end,
           case when a ->> 'presenca' = 'turno' then (i ->> 'condicao_ate')::date end,
           coalesce(i -> 'motivos', '[]'::jsonb), p_agora
      from jsonb_array_elements(v_itens) with ordinality t(i, k), jsonb_array_elements(i -> 'alocacoes') with ordinality u(a, j)
     where i ->> 'op' = 'criar'
     order by k, j;
    -- as perguntas críticas (a mesma pergunta não abre duas vezes; a de uma versão anterior da mesma OS sai)
    for v_q in select q from jsonb_array_elements(v_perg) q loop
      update public.agenda_perguntas p
         set estado = 'descartada', resolvida_motivo = 'a agenda mudou: a pergunta foi refeita'
       where p.estado = 'aberta' and p.modo = v_modo and p.tipo = v_q ->> 'tipo'
         and p.service_order_id = (v_q ->> 'service_order_id')::uuid and p.chave <> v_q ->> 'chave';
      insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, recomendacao,
                                           recomendacao_texto, proposta_id, versao_base, modo, criada_em)
      values (v_q ->> 'tipo', v_q ->> 'chave', (v_q ->> 'service_order_id')::uuid,
              array(select x::uuid from jsonb_array_elements_text(v_q -> 'os_ids') x), null, (v_q ->> 'perda_em')::date,
              v_q ->> 'texto', v_q -> 'opcoes', (v_q ->> 'recomendacao')::smallint, v_q ->> 'recomendacao_texto', v_pid, v0, v_modo, p_agora)
      on conflict (chave, modo) where estado = 'aberta' do nothing;
    end loop;
  end if;

  return jsonb_build_object(
    'ok', true, 'proposta_id', v_pid, 'versao_base', v0, 'escopo', p_escopo, 'modo', v_modo,
    'periodo', jsonb_build_object('de', v_de, 'ate', v_ate), 'simulacao', not p_persistir,
    'itens', v_itens, 'fora', v_fora, 'carga', v_carga,
    'perguntas', (select coalesce(jsonb_agg(q - 'x' order by q ->> 'chave'), '[]'::jsonb) from jsonb_array_elements(v_perg) q),
    'pontuacao', v_pont, 'textos', v_textos, 'texto', v_texto);
end;
$function$;

comment on function public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): o motor — guloso serial determinístico (mesma entrada, mesma saída). Escopo semana (publica os blocos que COMEÇAM de segunda a sábado da semana seguinte), os ou replano (as OS de p_os, depois do congelado, no horizonte). Etapas: estabilidade (_agenda_violacoes: só sai o que não pode mais acontecer; o publicado não violado nunca vira "mover"), a fila por classe (_agenda_classe_da_os) na ordem (classe, prioridade do dono, razão crítica, sinal pago, aprovação, número), o encaixe (_agenda_encaixar: congelamento hoje + o próximo dia útil, salvo evento real e pedido do dono; ≤ wip_max frentes; o dono como tambor; teto de carga_max por pessoa e semana; multi-dia com no máximo interrupcoes_max dias parados), a sobrecarga (a OS com data dita que não cabe vira a pergunta crítica nao_cabe, com as opções simuladas e a recomendação; o banco nunca escolhe), o atraso crítico de quem já tinha plano (_agenda_criticidade), as reservas (teto, condicionada com a data-limite, pátio), a validação (_agenda_validar_itens: inválida nunca sai), o diff (itens), as OS de fora com quem trava, a carga, a pontuação e os textos. Restrições: {fixar:[{os, de, ate, pessoa}], tirar:[os], so_depois_de:[{os, dia}], atrasar:[os], aceitar_atraso:[os], acima_da_carga, decisao}. Com p_persistir: agenda_propostas (modo = modo_proposta; a aberta anterior fica obsoleta), as alocações em estado proposta e as perguntas críticas. Sem persistir, o texto termina com "É simulação: não muda nada.". Só service_role. CORREÇÃO FASE 6 (C1, item 14): a reserva por teto da OS que precisa do dono, com a capacidade dele em uso abaixo de carga_max, diz "não coube na sua parte da semana (56%)" (a carga de _agenda_carga_da_pessoa), e não "na carga de 80%". CORREÇÃO 29/10 (P3): (a) a entrada da fila da OS com reserva vigente (por teto ou condicionada, de hoje em diante: a que o item "a reserva vira compromisso" cancela) leva res_propria (a pessoa × semana de cada meio-dia reservado), e o encaixe do compromisso dela não conta a própria reserva no lugar até 100% — a promoção da reserva cabe com o teto apertado (o João, 4 de 4 na semana); a reserva das outras OS continua contando. (b) Com a agenda automática ligada e reserva no que entra, o resumo separa o marcado firme do reservado e diz quem ("Semana de 03 a 06/11 (seg 02 é Finados): 1 reservado (Lenine), nada marcado firme, 10 de fora."), e o título da semana diz quantos ("Semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme", que abre o "Publiquei a semana de …"); sem reserva, ou fora de ligado, os de antes. FASE 7 (7a P3): o item de compromisso com a fonte orcamento (a estimativa do orçamento como dias firmes, só com a regra estimativa) termina "(estimativa minha: 6 dias)."; a recomendação das críticas dia_avisado ("A equipe já tinha recebido a ficha desse dia: recomendo seguir e você avisar quem ia") e dia_prometido ("É um dia que o cliente já ouviu: recomendo seguir e você falar com ele hoje"), que só nascem com a zona travada do P8. FASE 7 (7a P8, spec §3.2 e §5.8): com a regra zona_travada, a criticidade de cada compromisso colocado é refeita com p_violadas = _agenda_zona_fora (o que não conta para o dia já avisado: a violação, o resto do meio-dia dela e o que volta igual neste encaixe; nunca o fixado pelo dono): o meio-dia de um dia já dito à equipe ou ao cliente que sairia sem ter ficado impossível, e o fim que passaria do prometido firme, viram as críticas dia_avisado e dia_prometido, com a pergunta e a recomendação de sempre. Sem a regra, a de antes, byte a byte. FASE 7b (P4, §5.3, §6.3, R4.3): só com os modos da 7b — a entrada da fila ganha dk (as pessoas dos passos que restam), dk_dono_conta, dupla_fonte e o texto da dupla; da dupla inferida, passos1 (o bloco de 1 pessoa: ligado, a soma do dk; em teste, os passos de antes), dupla_ni/dupla_nf/dupla_todos e os nomes do que a tarefa pede; prazo_h (o índice da tarde de least(precisa_ate, o prometido firme)) e prazo; e dupla_sd na dupla dita que só passa pela régua dos técnicos com quem vem sob demanda. p_par ganha sab_modo, sab_politica, dupla_modo e dupla_espera. Ligado, o item com o sábado diz qual e por quê (" — com sáb 14/11 de manhã (Rafael se ofereceu), para cumprir o prazo de qua 18/11.") e o bloco de 1 pessoa da dupla inferida diz em que meios-dias chamar um ajudante (" Nos 2 primeiros meios-dias (qua 04/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem qua 04/11)."); o item leva dupla (o texto do cartão), dupla_fonte, dupla_falta [{dia, turno, onde}] e sabado. A dupla dita com dupla_sd sem bloco vai ao fora com o motivo dupla ("Lenine (OS-00074): precisa de 2 pessoas em 6 meios-dias e Mateus só vem qua 11 e qui 12/11 (4 meios-dias): me diga mais dias dele ou chame outro ajudante."), nunca sem_encaixe. Em teste, textos.em_teste e o fim do texto: "Em teste: para cumprir o prazo de Vanderlei (qua 18/11), eu usaria sáb 14/11 de manhã com Rafael, que se ofereceu." e "Em teste: no Lenine eu pediria um ajudante em qua 04/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas.". Sem os modos da 7b, a de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 22 e 23): o exemplo da dupla de 1 pessoa diz todos os dias em que falta a 2ª pessoa ("ex.: Mateus vem qua 18 e qui 19/11"); a dupla dita que só passou da espera por quem vem sob demanda e cujos dias livres são todos antes de a OS ficar pronta (os_prontidao.est) vai ao fora dupla com "…, antes de o serviço ficar pronto (qua 18/11): me diga dias dele a partir de qua 18/11 ou chame outro ajudante.". FASE 7c (P2, §5.2, R5.10-12): a entrada da fila ganha ext, exu, exf e exig_texto (os_exigencias, em qualquer modo) e, com modo_lider ou modo_habilidade ligado, lid, lid_nome, lid_duro, lid_plan e lid_fora (_agenda_lider_da_os); p_par ganha hab_modo, lid_modo, n, fcobre e lid_espera (sempre: o critério de cada alocação vai no item e o gatilho agenda_alocacoes_criterio o grava). Ligado: os motivos "pede … : vai …", "troquei o responsável: … não está livre até …; segui com …" e "…, o responsável, não está na equipe agora"; o aviso de habilidade (_agenda_aviso_da_habilidade) ao lado do de material onde o dono disse quem vai; o cancelar habilidade ("a equipe do dia não tinha quem o serviço pede") e o fora habilidade ("pede … e ninguém com isso fica livre junto nas próximas 6 semanas"); o contexto do "por que não cabe" leva hab_modo, n e fcobre. Com os 3 modos fora de ligado, as pessoas, os dias, os turnos e as presenças de antes (a projeção); só o critério aparece. CORREÇÃO DA REVISÃO DA 7c (20261102100580, achado 9): com a troca avisada do responsável (o lt do bloco: modo_lider ou modo_habilidade ligado), o texto do item (o da ação do "o que mudou", do fechamento e do aviso) termina " — troquei o responsável: Roberto não está livre até qua 11/11; segui com João." (até 320; sem caber, " — troquei o responsável (Roberto não está livre)."). Sem troca, o de antes. FASE 7d (P4, §5.4, R6.7b, R6.8): com calendario, patio, viagem ou mesmo_local ligado por _agenda_local_modo (com o freio, em teste), cada OS da fila lê o local (_agenda_local_resolvido; em teste, nenhuma chamada): a máscara entra em bem e em fora_h, a entrada no EST, a retirada em bem, a viagem soma os meios de estrada aos passos e tira o abre e fecha fora da região. Com as chaves só nos modos ligados, o item da fila ganha fora_h, local_txt, viagem, imax_os, local_texto e suposicoes, o item que entra ganha os 4 últimos e v_par ganha mesmo_dia e troca (temporada_meses). A saída pela violação local diz "o local não recebe a equipe nesse dia", e a OS que não coube no pátio vai ao fora com sem_encaixe, patio_cheio e o texto próprio. Com os 6 modos fora de ligado, a saída de antes, byte a byte. FASE 7e (P4): com modo_urgencia ligado de verdade, a OS urgente (_agenda_os_urgente) vai até 100% da semana, sai em p_restricoes.urgentes e o item diz o motivo quando a semana passou do teto; a frase da carga usa a carga da semana (R7.5-14); com p_restricoes.puxar, a OS puxada (P4b). Fora de ligado, a saída de antes, byte a byte.';

-- _agenda_aprendizado_gravar (de 20261111100100_agenda_fase7e_medicao.sql:1617; md5 do corpo de antes 3dfa35d6aab18883e472a84f60a13925)
create or replace function public._agenda_aprendizado_gravar(p_item text, p_chave text, p_nivel text, p_calculado numeric,
                                                             p_n integer, p_amostra jsonb, p_padrao numeric, p_detalhe jsonb,
                                                             p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_hoje   date := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_lista  text := public._agenda_aprendizado_da_lista(p_item);
  v_nmin   int;
  r0       public.agenda_aprendizado;
  r        public.agenda_aprendizado;
  v_efet   numeric;
  v_estado text;
  v_d      jsonb;
  v_ops    jsonb;
  v_txt    text;
  v_acao   uuid;
  v_perg   uuid;
  v_aberta boolean := false;
  v_motivo text;
  v_antes  jsonb := '{}'::jsonb;
  v_depois jsonb := '{}'::jsonb;
  v_hist   jsonb;
  k        text;
  -- FASE 7e: (7e P2, §5.1, R7.6) o ramo dos itens da margem: o modo CRU (o freio não entra aqui: soltar o freio recomeçaria do padrão), o passo e o novo em uso
  v_7e_modo  text := public._agenda_margem_modo_cru(p_item);
  v_7e_passo numeric;
  v_7e_novo  numeric;
  -- FASE 7e: fim
  -- FASE 7e: (7e P4, §0-4, R7.4) a folga em uso que ficou sem medida volta ao padrão por passo
  v_7e_volta boolean := false;
  -- FASE 7e: fim
begin
  if p_item is null or p_chave is null or p_nivel is null or p_agora is null then
    raise exception 'Falta o item, a chave, o nível ou a hora.' using errcode = '22023';
  end if;
  v_nmin := case p_item
    when 'fator' then c.fator_n_min when 'mo' then c.mo_n_min when 'presenca' then c.presenca_n_min
    when 'fornecedor_atraso' then c.fornecedor_n_min when 'fornecedor_prazo' then c.fornecedor_n_min
    when 'capacidade_dono' then c.capacidade_semanas_min when 'cliente_pontualidade' then c.cliente_n_min
    when 'aviso_folga' then c.aviso_n_min when 'carga' then least(c.ppc_baixo_semanas, c.ppc_alto_semanas)
    when 'solver' then c.solver_semanas end;
  -- FASE 7e: (7e P2, §5.1) o mínimo e o passo de cada item da margem
  if v_7e_modo is not null then
    v_nmin := case p_item when 'vies' then c.vies_n_min when 'promessa' then c.promessa_n_min when 'folga_semana' then c.folga_semanas_min
                          when 'tempo_compra' then c.tempo_compra_n_min when 'folga_compra' then c.folga_compra_n_min
                          when 'prazo_sem_fornecedor' then c.prazo_sem_fornecedor_n_min end;
    v_7e_passo := case when p_item in ('vies', 'promessa') then c.fator_troca_max when p_item = 'folga_semana' then c.folga_semana_troca_max
                       when p_item in ('tempo_compra', 'folga_compra') then c.fornecedor_troca_max_du end;
  end if;
  -- FASE 7e: fim
  if v_nmin is null then
    raise exception 'Item de aprendizado desconhecido: %.', p_item using errcode = '22023';
  end if;

  -- A linha (nasce medindo) e a trava dela: duas rodadas não gravam a mesma chave ao mesmo tempo.
  insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, calculado_em)
  values (p_item, p_chave, p_nivel, p_padrao, v_nmin, p_agora)
  on conflict (item, chave) do nothing;
  select * into r0 from public.agenda_aprendizado where item = p_item and chave = p_chave for update;
  if r0.nivel <> p_nivel then
    raise exception 'A chave % de % é do nível %, não %.', p_chave, p_item, r0.nivel, p_nivel using errcode = '22023';
  end if;
  if r0.pergunta_id is not null then
    v_aberta := exists (select 1 from public.agenda_perguntas q where q.id = r0.pergunta_id and q.estado = 'aberta');
  end if;
  r := r0;
  r.padrao := p_padrao;
  r.calculado := p_calculado;
  r.n := coalesce(p_n, 0);
  r.n_min := v_nmin;
  r.amostra := case when jsonb_typeof(p_amostra) = 'array'
                    then coalesce((select jsonb_agg(x order by o) from jsonb_array_elements(p_amostra) with ordinality t(x, o)
                                    where o <= 60), '[]'::jsonb)
                    else '[]'::jsonb end;
  r.detalhe := case when jsonb_typeof(p_detalhe) = 'object' then p_detalhe else '{}'::jsonb end;
  r.calculado_em := p_agora;
  -- O que vale hoje: o em uso (também guardado na pergunta e na trava), senão o padrão.
  v_efet := coalesce(r0.em_uso, p_padrao);

  if p_calculado is null or r.n < v_nmin then
    -- 1. poucas medidas
    v_estado := 'medindo';
  elsif v_lista is null or c.modo_aprendizado <> 'ligado' or not (v_lista = any (c.aprendizado_ligados)) then
    -- 2. em teste (o modo, a lista; a pontualidade com o cliente é só medida)
    v_estado := 'sombra';
  elsif r0.estado = 'travado' and v_hoje <= r0.travado_ate
        and (p_calculado = r0.travado_valor
             or public._agenda_aprendizado_troca_cabe(p_item, p_nivel, r0.travado_valor, p_calculado)) then
    -- 3. o dono travou e o medido não andou mais que o limite (o item que sempre pergunta: o medido não mudou)
    v_estado := 'travado';
  elsif p_calculado = v_efet then
    -- 4. igual ao que vale
    v_estado := 'em_uso';
  elsif public._agenda_aprendizado_troca_cabe(p_item, p_nivel, v_efet, p_calculado) then
    -- 5. troca pequena: entra sozinha, com *desfaz*
    v_estado := 'em_uso';
  else
    -- 6. troca grande: pergunta
    v_estado := 'pergunta';
  end if;
  -- FASE 7e: (7e P2, §5.1) os itens da margem andam por passo e nunca perguntam: a cadeia de cima só deu medindo ou sombra para eles (v_lista nula). Aqui, de medindo não sai. Em teste continua: o modo geral, o interruptor, a promessa
  -- (AG7-32: nunca em uso), a folga da compra (R7.5-16: sem leitor nesta etapa, o texto "dou 2 dias a mais" seria mentira), o que é só medida e a chave dono: sem vies_corrige_dono. Dentro da trava, se o medido não andou mais que um passo; senão, em uso.
  if v_7e_modo is not null and v_estado <> 'medindo' then
    if c.modo_aprendizado <> 'ligado' or v_7e_modo <> 'ligado' or p_item in ('promessa', 'folga_compra', 'prazo_sem_fornecedor')
       or (p_item = 'vies' and p_chave like 'dono:%' and not c.vies_corrige_dono) then
      v_estado := 'sombra';
    elsif r0.estado = 'travado' and v_hoje <= r0.travado_ate and abs(p_calculado - r0.travado_valor) <= v_7e_passo then
      v_estado := 'travado';
    else
      v_estado := 'em_uso';
    end if;
  end if;
  -- FASE 7e: fim

  -- FASE 7e: (7e P4, §0-4, R7.4, R7.11) a folga da semana em uso que fica sem medida (σ = 0, poucas semanas ou poucos resíduos) não some de uma vez: em medindo o CHECK aprendizado_em_uso_coerente obriga em_uso nulo, e a carga da semana saltaria sem rastro. Continua em uso e anda um passo para o padrão, com a ação e o *desfaz* de sempre; dentro da trava, fica o que o dono decidiu. Com o interruptor fora de ligado a carga já é a de sempre: nada a trazer de volta. Modo cru, como o resto do gravador (R7.6). Quando chega ao padrão, cai em medindo sem mudar número nenhum.
  if p_item = 'folga_semana' and v_estado = 'medindo' and r0.em_uso <> p_padrao
     and c.modo_aprendizado = 'ligado' and v_7e_modo = 'ligado' then
    v_7e_volta := true;
    v_estado := case when r0.estado = 'travado' and v_hoje <= r0.travado_ate then 'travado' else 'em_uso' end;
  end if;
  -- FASE 7e: fim
  r.estado := v_estado;
  if v_estado in ('medindo', 'sombra') then
    r.em_uso := null;
    r.em_uso_desde := null;
  elsif v_estado = 'em_uso' then
    r.em_uso := p_calculado;
    r.em_uso_desde := case when r0.em_uso = p_calculado and r0.estado = 'em_uso' then coalesce(r0.em_uso_desde, p_agora)
                           else p_agora end;
  else
    -- pergunta e trava: o que vale continua valendo (nulo = o padrão)
    r.em_uso := case when r0.estado in ('em_uso', 'pergunta', 'travado') then r0.em_uso end;
  end if;
  -- FASE 7e: (7e P2, §5.1) o em uso anda um passo por rodada (o calculado guarda o alvo), arredondado como o item: 2 casas no multiplicador e no percentual, inteiro nos dias (para cima na folga da compra)
  if v_7e_modo is not null and v_estado = 'em_uso' then
    v_7e_novo := v_efet + greatest(-v_7e_passo, least(v_7e_passo, p_calculado - v_efet));
    r.em_uso := case p_item when 'folga_compra' then ceil(v_7e_novo) when 'tempo_compra' then round(v_7e_novo) else round(v_7e_novo, 2) end;
    r.em_uso_desde := case when r0.em_uso = r.em_uso and r0.estado = 'em_uso' then coalesce(r0.em_uso_desde, p_agora) else p_agora end;
  end if;
  -- FASE 7e: fim
  -- FASE 7e: (7e P4, §0-4) o passo da volta, com o padrão como alvo (o calculado é nulo: a conta de cima não serve aqui)
  if v_7e_volta and v_estado = 'em_uso' then
    r.em_uso := v_efet + greatest(-v_7e_passo, least(v_7e_passo, p_padrao - v_efet));
  end if;
  -- FASE 7e: fim
  if v_estado <> 'travado' then
    r.travado_ate := null;
    r.travado_valor := null;
  end if;

  v_d := jsonb_build_object('chave', p_chave, 'calculado', p_calculado, 'em_uso', r.em_uso, 'efetivo', v_efet,
                            'padrao', p_padrao, 'n', r.n, 'n_min', v_nmin,
                            'desde', (r.em_uso_desde at time zone 'America/Sao_Paulo')::date, 'travado_ate', r.travado_ate,
                            'trava_dias', c.aprender_trava_dias, 'detalhe', r.detalhe);
  -- FASE 7e: (7e P2, §6.2) o que os textos da margem precisam e o gravador tem (o texto é IMMUTABLE e não lê a linha da config)
  if v_7e_modo is not null then
    v_d := v_d || jsonb_build_object('passo', v_7e_passo, 'carga_max', c.carga_max, 'folga_material_du', c.folga_material_du, 'fator_percentil', c.fator_percentil);
  end if;
  -- FASE 7e: fim

  -- FASE 7e: (7e P2, §5.1) se havia pergunta aberta da chave da margem (não deveria), ela sai: o item nunca pergunta
  if v_7e_modo is not null and v_aberta then
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'O aprendizado agora anda aos poucos, sem pergunta.'
     where id = r0.pergunta_id and estado = 'aberta';
    v_aberta := false;
  end if;
  -- FASE 7e: fim
  -- A pergunta aberta desta chave: fica (a mesma troca), ou sai (o medido voltou, caiu abaixo do mínimo, saiu do uso, mudou).
  if v_aberta and not (v_estado = 'pergunta' and r0.estado = 'pergunta' and r0.calculado is not distinct from p_calculado) then
    v_motivo := case
      when v_estado = 'medindo' then 'Menos medidas que o mínimo: volto a medir.'
      when v_estado = 'sombra' then 'Esse aprendizado saiu do uso (em teste).'
      when v_estado = 'pergunta' then 'O medido mudou: perguntei de novo com o número novo.'
      else 'O medido voltou para perto do que vale.' end;
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = v_motivo
     where id = r0.pergunta_id and estado = 'aberta';
    v_aberta := false;
  end if;

  -- FASE 7e: (7e P2, §5.1, R7.5-19) a ação do item da margem: o em uso que muda é o do passo, o alvo fica em depois.alvo e o *desfaz* volta um passo. Nenhum item da margem passa pelo ramo da pergunta
  if v_7e_modo is not null and v_estado = 'em_uso' and r.em_uso is distinct from v_efet then
    insert into public.agenda_acoes (dia, executada, origem, tipo, texto, antes, depois, desfazivel_ate, criada_em)
    values (v_hoje, true, 'vigia', 'aprendizado',
            left(public._agenda_corta(public._agenda_aprendizado_texto(p_item, 'acao', v_d), 400), 400),
            jsonb_build_object('item', p_item, 'chave', p_chave, 'nivel', p_nivel, 'em_uso', r0.em_uso, 'valor', v_efet, 'estado', r0.estado),
            jsonb_build_object('item', p_item, 'chave', p_chave, 'nivel', p_nivel, 'em_uso', r.em_uso, 'n', r.n, 'alvo', p_calculado),
            p_agora + c.desfazer_validade, p_agora)
    returning id into v_acao;
    r.acao_id := v_acao;
  elsif v_7e_modo is null then
  -- FASE 7e: fim
  if v_estado = 'em_uso' and r.em_uso is distinct from v_efet then
    -- 5. a ação no "o que mudou" das 17:30, com *desfaz aprendizado*
    insert into public.agenda_acoes (dia, executada, origem, tipo, texto, antes, depois, desfazivel_ate, criada_em)
    values (v_hoje, true, 'vigia', 'aprendizado',
            left(public._agenda_corta(public._agenda_aprendizado_texto(p_item, 'acao', v_d), 400), 400),
            jsonb_build_object('item', p_item, 'chave', p_chave, 'nivel', p_nivel, 'em_uso', r0.em_uso, 'valor', v_efet,
                               'estado', r0.estado),
            jsonb_build_object('item', p_item, 'chave', p_chave, 'nivel', p_nivel, 'em_uso', p_calculado, 'n', r.n),
            p_agora + c.desfazer_validade, p_agora)
    returning id into v_acao;
    r.acao_id := v_acao;
  elsif v_estado = 'pergunta' and not v_aberta then
    -- 6. a pergunta crítica: 1 uso o medido (recomendo); 2 fico com o de agora; 3 volto ao padrão (só quando o que vale não é
    -- o padrão e o medido também não; a carga e o planejador só têm 1 e 2)
    v_ops := jsonb_build_array(
      jsonb_build_object('n', 1, 'texto', public._agenda_aprendizado_texto(p_item, 'opcao1', v_d),
                         'efeito', jsonb_build_object('em_uso', p_calculado)),
      jsonb_build_object('n', 2, 'texto', public._agenda_aprendizado_texto(p_item, 'opcao2', v_d),
                         'efeito', jsonb_build_object('travar', p_calculado)));
    if p_item not in ('carga', 'solver') and v_efet is distinct from p_padrao and p_calculado is distinct from p_padrao then
      v_ops := v_ops || jsonb_build_array(jsonb_build_object('n', 3, 'texto', public._agenda_aprendizado_texto(p_item, 'opcao3', v_d),
                                                             'efeito', jsonb_build_object('em_uso', null)));
    end if;
    select public._agenda_aprendizado_texto(p_item, 'pergunta', v_d) || ' '
           || string_agg(format('%s) %s%s', o ->> 'n', o ->> 'texto',
                                case when o ->> 'n' = '1' and o ->> 'texto' !~ 'recomend' then ' (recomendo)' else '' end),
                         '; ' order by (o ->> 'n')::int) || '.'
      into v_txt
      from jsonb_array_elements(v_ops) o;
    -- CORREÇÃO FASE 6: (C2) texto 5: na troca grande do R$ por diária a opção 1 não leva o "(recomendo)" — a conta inclui a mão
    -- de obra das OS em que o dono também trabalhou, e a decisão é dele, sem empurrão. A recomendação da pergunta continua 1
    -- (o CHECK critica_tem_opcoes pede uma); só o texto muda.
    if p_item = 'mo' then
      v_txt := replace(v_txt, format('1) %s (recomendo)', v_ops -> 0 ->> 'texto'), format('1) %s', v_ops -> 0 ->> 'texto'));
    end if;
    -- CORREÇÃO FASE 6: fim
    insert into public.agenda_perguntas (tipo, chave, dia, texto, opcoes, recomendacao, modo, criada_em)
    values ('aprendizado', left(format('aprendizado:%s:%s', p_item, p_chave), 200), v_hoje,
            left(public._agenda_corta(v_txt, 600), 600), v_ops, 1, 'ligado', p_agora)
    on conflict (chave, modo) where estado = 'aberta' do nothing
    returning id into v_perg;
    if v_perg is null then
      select q.id into v_perg from public.agenda_perguntas q
       where q.chave = left(format('aprendizado:%s:%s', p_item, p_chave), 200) and q.modo = 'ligado' and q.estado = 'aberta';
    end if;
    r.pergunta_id := v_perg;
  end if;
  -- FASE 7e: (7e P2) fecha o desvio do item da margem
  end if;
  -- FASE 7e: fim

  r.texto := left(public._agenda_corta(public._agenda_aprendizado_texto(p_item, 'foco_' || v_estado, v_d), 400), 400);

  -- O histórico: em uso, estado e calculado, quando mudam (os 20 mais novos).
  foreach k in array array['em_uso', 'estado', 'calculado'] loop
    if to_jsonb(r0) -> k is distinct from to_jsonb(r) -> k then
      v_antes := v_antes || jsonb_build_object(k, to_jsonb(r0) -> k);
      v_depois := v_depois || jsonb_build_object(k, to_jsonb(r) -> k);
    end if;
  end loop;
  v_hist := r0.historico;
  if v_antes <> '{}'::jsonb then
    v_hist := v_hist || jsonb_build_array(jsonb_build_object('em', p_agora, 'antes', v_antes, 'depois', v_depois));
    if jsonb_array_length(v_hist) > 20 then
      select jsonb_agg(x order by o) into v_hist
        from jsonb_array_elements(v_hist) with ordinality t(x, o) where o > jsonb_array_length(v_hist) - 20;
    end if;
  end if;

  update public.agenda_aprendizado
     set padrao = r.padrao, calculado = r.calculado, em_uso = r.em_uso, n = r.n, n_min = r.n_min, amostra = r.amostra,
         detalhe = r.detalhe, estado = r.estado, texto = r.texto, calculado_em = r.calculado_em, em_uso_desde = r.em_uso_desde,
         travado_ate = r.travado_ate, travado_valor = r.travado_valor, pergunta_id = r.pergunta_id, acao_id = r.acao_id,
         historico = v_hist
   where id = r0.id;

  return jsonb_build_object('item', p_item, 'chave', p_chave, 'nivel', p_nivel, 'estado', v_estado, 'estado_antes', r0.estado,
                            'calculado', p_calculado, 'em_uso', r.em_uso, 'vale', coalesce(r.em_uso, p_padrao),
                            'acao_id', v_acao, 'pergunta_id', case when v_estado = 'pergunta' then r.pergunta_id end,
                            'texto', r.texto);
end;
$function$;

comment on function public._agenda_aprendizado_gravar(text, text, text, numeric, integer, jsonb, numeric, jsonb, timestamptz) is
  'Agenda de Produção (Fase 6): o gravador único de agenda_aprendizado (spec-fase6 §5.1) — o upsert de (item, chave) e o estado, nesta ordem: 1 n < n_min → medindo; 2 modo fora de ligado, item fora de aprendizado_ligados ou só de medida → sombra; 3 travado e dentro da trava (a data e o limite de troca a partir do valor recusado) → fica; 4 o medido = o que vale → em uso; 5 troca dentro do limite (§3.2) → em uso + a ação aprendizado (origem vigia, desfazível por desfazer_validade); 6 troca grande → pergunta crítica aprendizado (chave aprendizado:<item>:<chave>, uma aberta por chave). Toda mudança de em uso, estado e calculado vai ao histórico. Definer, sem grant a ninguém. CORREÇÃO FASE 6 (C2, texto 5): na pergunta do R$ por diária a opção 1 sai sem o "(recomendo)" (a recomendação da pergunta continua 1, pelo CHECK). FASE 7e (P2): o ramo por passo dos itens da margem (vies, folga_semana, promessa, tempo_compra, folga_compra, prazo_sem_fornecedor): medindo; sombra (modo geral, interruptor CRU, promessa, folga_compra, só medida, chave dono: sem vies_corrige_dono); travado (na trava, medido a até um passo); em uso, com o em uso andando até o passo por rodada e o calculado como alvo. Nunca pergunta. A ação guarda antes.em_uso e depois.alvo. Os itens da Fase 6, como antes. FASE 7e (P4): só o item folga_semana: em uso fora do padrão e sem número medido (calculado nulo ou abaixo do mínimo), com os dois modos ligados (crus), não cai em medindo: anda um passo para o padrão (ação aprendizado com *desfaz*), e dentro da trava fica o que o dono decidiu. No padrão, cai em medindo sem mudar número nenhum.';

-- _agenda_aprendizado_texto (de 20261111100100_agenda_fase7e_medicao.sql:1065; md5 do corpo de antes d6efbf56237d8da99642b5411ba86930)
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
  -- FASE 7e: (7e P2, §6.2, §6.3, R7.3, R7.5-19, R7.5-20, R7.12-9) os textos dos 6 itens da margem, antes de todos (um item da margem nunca passa pelos de baixo). Sem jargão: "o do meio" é a mediana e "8 em cada 10" é o percentil 80. n = 0 diz
  -- "nenhuma ... ainda" (nunca "medi"). Promessa (AG7-32) e folga da compra (R7.5-16: sem leitor nesta etapa) só têm os textos de medindo e em teste: o gravador nunca as põe em uso. Tudo número daqui sai de p_d (o gravador).
  if p_item in ('vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor') then
    declare
      v_7e_chave text := regexp_replace(coalesce(p_d ->> 'chave', ''), '^(estimativa|dono):', '');
      v_7e_dono  boolean := coalesce(p_d ->> 'chave', '') like 'dono:%';
      v_7e_cls   text := public._agenda_classe_texto_do_nivel(v_7e_chave);
      v_7e_geral boolean := v_7e_chave = 'todas';
      v_7e_n     int := coalesce((p_d ->> 'n')::int, 0);
      v_7e_alvo  boolean := (p_d ->> 'em_uso')::numeric is not distinct from (p_d ->> 'calculado')::numeric;
      v_7e_sobe  boolean := (p_d ->> 'em_uso')::numeric > (p_d ->> 'efetivo')::numeric;
      v_7e_num   text := public._agenda_num((p_d ->> 'efetivo')::numeric, 1);
      v_7e_pnum  text := public._agenda_num((p_d ->> 'padrao')::numeric, 1);
      v_7e_lei   text;
      v_7e_guarda text;
      v_7e_resto text;
    begin
      if p_item = 'vies' then
        v_7e_lei := case when v_7e_dono then format('nos dias que você diz, as OS levam %s o que você combinou', v_calc)
                         else format('%s levam %s o que eu estimo pelo orçamento', coalesce(v_7e_cls, 'as OS'), v_calc) end;
        return case p_momento
          when 'foco_medindo' then
            case when v_7e_dono then format('Nos dias que você diz: %s; conto os seus dias como você disse.',
                                            case when v_7e_n = 0 then 'nenhuma OS medida ainda' else format('%s de %s OS medidas', v_n, v_nmin) end)
                 else format('Estimativa pelo valor: %s; marco os dias como saem do orçamento.',
                             case when v_7e_n = 0 then 'nenhuma OS medida ainda' else format('%s de %s OS medidas', v_n, v_nmin) end) end
          when 'foco_sombra' then
            case when v_7e_dono then format('Em teste: %s (%s OS medidas). Hoje conto os seus dias como você disse.', v_7e_lei, v_n)
                 when v_7e_geral then format('Em teste: %s (%s OS medidas). Hoje marco os dias como saem do orçamento.', v_7e_lei, v_n)
                 else format('Em teste: %s (%s OS medidas; junto com o geral das OS). Hoje marco os dias como saem do orçamento.', v_7e_lei, v_n) end
          when 'foco_em_uso' then
            case when v_7e_dono and v_7e_alvo then format('%s (%s OS medidas): corrijo os seus dias com %s desde %s, e digo sempre os dois números.', public._agenda_maiuscula(v_7e_lei), v_n, v_uso, v_desde)
                 when v_7e_dono then format('%s (%s OS medidas): corrijo os seus dias com %s desde %s e chego a %s aos poucos (até %s× por dia); digo sempre os dois números.',
                                            public._agenda_maiuscula(v_7e_lei), v_n, v_uso, v_desde, v_calc, public._agenda_num((p_d ->> 'passo')::numeric, 2))
                 when v_7e_alvo then format('%s (%s OS medidas): marco os dias delas com %s desde %s.', public._agenda_maiuscula(v_7e_lei), v_n, v_uso, v_desde)
                 else format('%s (%s OS medidas): marco com %s desde %s e chego a %s aos poucos (até %s× por dia).',
                             public._agenda_maiuscula(v_7e_lei), v_n, v_uso, v_desde, v_calc, public._agenda_num((p_d ->> 'passo')::numeric, 2)) end
          when 'foco_travado' then format('%s (%s OS medidas); fico com %s até %s, como você decidiu.', public._agenda_maiuscula(v_7e_lei), v_n, v_efet, v_trava)
          when 'acao' then
            case when v_7e_dono then format('Aprendi com as OS concluídas: %s (%s OS). Passei a contar os seus dias com %s (era %s), sempre dizendo os dois números, só nos serviços que eu ainda não marquei. *desfaz aprendizado* volta.',
                                            v_7e_lei, v_n, v_uso, v_efet)
                 when v_7e_alvo then format('Aprendi com as OS concluídas: %s (%s OS). Passei a marcar os dias delas com %s (era %s), só nos serviços que eu ainda não marquei. *desfaz aprendizado* volta.',
                                            v_7e_lei, v_n, v_uso, v_efet)
                 else format('Aprendi com as OS concluídas: %s (%s OS). Passei a marcar com %s (era %s) e %s até %s aos poucos, só nos serviços que eu ainda não marquei. *desfaz aprendizado* volta.',
                             v_7e_lei, v_n, v_uso, v_efet, case when v_7e_sobe then 'subo' else 'desço' end, v_calc) end
          -- R7.5-19 e 20: volta um passo só (o valor de p_d.volta, nunca o padrão de cabeça), e a OS já marcada guarda o valor que tinha
          when 'desfeito' then
            case when v_7e_dono then format('Desfeito: os seus dias voltam a %s, só nos serviços que eu ainda não marquei. Não troco de novo por %s dias, salvo se o medido mudar muito.', v_volta, v_dias)
                 else format('Desfeito: %s voltam a %s o que sai do orçamento, só nas que eu ainda não marquei. Não troco de novo por %s dias, salvo se o medido mudar muito.', coalesce(v_7e_cls, 'as OS'), v_volta, v_dias) end
        end;
      elsif p_item = 'folga_semana' then
        -- o total guardado (1 − carga_max) e a parte que não é medida (urgência e falta): o resto do padrão
        v_7e_guarda := round((1 - (p_d ->> 'carga_max')::numeric) * 100)::text || '%';
        v_7e_resto := round((1 - (p_d ->> 'carga_max')::numeric - (p_d ->> 'padrao')::numeric) * 100)::text || '%';
        -- (7e P4, R7.4, R7.9, §0-4; marca sem FASE porque está dentro do bloco do P2) sem número medido (calculado nulo). Com as semanas já no mínimo, o "N de M" da §6.2 diria "12 de 8" e não diz o que falta: aqui o que falta são as OS medidas (quem manda é o resíduo, R7.9) ou que elas mostrem variação (σ = 0). E a folga em uso que ficou sem medida volta ao padrão por passo: a linha e a ação dizem isso, e não "medi".
        if (p_d ->> 'calculado') is null then
          declare
            v_7e_res   int := coalesce((p_d #>> '{detalhe,residuos}')::int, 0);
            v_7e_rmin  int := (p_d #>> '{detalhe,residuos_min}')::int;
            v_7e_basta boolean := v_7e_n >= (p_d ->> 'n_min')::int;
            v_7e_igual boolean := (p_d ->> 'em_uso')::numeric = (p_d ->> 'padrao')::numeric;
            v_7e_falta text := case when not v_7e_basta then format('%s de %s semanas com serviço marcado medidas', v_n, v_nmin)
                                    when v_7e_res = 0 then 'nenhuma OS medida ainda'
                                    when v_7e_res < v_7e_rmin then format('%s de %s OS medidas', v_7e_res, v_7e_rmin)
                                    else format('as %s OS medidas ainda não mostraram variação', v_7e_res) end;
          begin
            if p_momento = 'foco_medindo' and v_7e_basta then
              return format('Folga da semana: as semanas já bastam (%s), mas falta saber o quanto as OS variam: %s; guardo %s da semana da equipe (%s para o serviço que passa do previsto e %s para urgência e falta).', v_n, v_7e_falta, v_7e_guarda, v_padrao, v_7e_resto);
            elsif p_momento = 'foco_em_uso' then
              return case when v_7e_igual then format('Sem medida para a folga da semana (%s): voltei a guardar os %s de sempre da semana para o serviço que passa do previsto.', v_7e_falta, v_padrao)
                          else format('Sem medida para a folga da semana (%s): guardo %s da semana para o serviço que passa do previsto desde %s e volto aos %s de sempre aos poucos.', v_7e_falta, v_uso, v_desde, v_padrao) end;
            elsif p_momento = 'foco_travado' then
              return format('Sem medida para a folga da semana (%s); fico com %s até %s, como você decidiu.', v_7e_falta, v_efet, v_trava);
            elsif p_momento = 'acao' then
              return case when v_7e_igual then format('Fiquei sem medida para a folga da semana (%s). Voltei a guardar os %s de sempre da semana para o serviço que passa do previsto (era %s). *desfaz aprendizado* volta.', v_7e_falta, v_padrao, v_efet)
                          else format('Fiquei sem medida para a folga da semana (%s). Passei a guardar %s da semana para o serviço que passa do previsto (era %s) e volto aos %s de sempre aos poucos. *desfaz aprendizado* volta.', v_7e_falta, v_uso, v_efet, v_padrao) end;
            end if;
          end;
        end if;
        -- (7e: fim)
        return case p_momento
          when 'foco_medindo' then format('Folga da semana: %s; guardo %s da semana da equipe (%s para o serviço que passa do previsto e %s para urgência e falta).',
                                          case when v_7e_n = 0 then 'nenhuma semana com serviço marcado medida ainda' else format('%s de %s semanas com serviço marcado medidas', v_n, v_nmin) end,
                                          v_7e_guarda, v_padrao, v_7e_resto)
          when 'foco_sombra' then format('Em teste: pelo quanto as OS variaram em %s semanas, %s da semana bastariam para o serviço que passa do previsto; hoje guardo %s.', v_n, v_calc, v_padrao)
          when 'foco_em_uso' then
            case when v_7e_alvo then format('Pelo quanto as OS variaram em %s semanas, guardo %s da semana para o serviço que passa do previsto desde %s (era %s).', v_n, v_uso, v_desde, v_padrao)
                 else format('Pelo quanto as OS variaram em %s semanas, guardo %s da semana para o serviço que passa do previsto desde %s e chego a %s aos poucos (era %s).', v_n, v_uso, v_desde, v_calc, v_padrao) end
          when 'foco_travado' then format('Pelo quanto as OS variaram em %s semanas, %s da semana bastariam para o serviço que passa do previsto; fico com %s até %s, como você decidiu.', v_n, v_calc, v_efet, v_trava)
          when 'acao' then format('Medi %s semanas de serviço marcado: as OS variaram %s do que eu contava. Passei a guardar %s da semana para o serviço que passa do previsto (era %s)%s. *desfaz aprendizado* volta.',
                                  v_n, case when v_7e_sobe then 'mais' else 'menos' end, v_uso, v_efet,
                                  case when (p_d #>> '{detalhe,proxima_semana}') is not null then ': ' || (p_d #>> '{detalhe,proxima_semana}') else '' end)
          when 'desfeito' then format('Desfeito: volto a guardar %s da semana para o serviço que passa do previsto. Não troco de novo por %s dias, salvo se o medido mudar muito.', v_volta, v_dias)
        end;
      elsif p_item = 'promessa' then
        -- só para o dono (AG7-32): o cliente não ouve data de pronto, e por isso não há "em uso" nem "em teste" aqui
        return case when v_7e_n = 0 then 'Prazo real: nenhuma OS medida ainda. Só para você: ao cliente não digo data de pronto.'
                    when (p_d ->> 'calculado') is null or v_7e_n < coalesce((p_d ->> 'n_min')::int, 1)
                      then format('Prazo real: %s de %s OS medidas. Só para você: ao cliente não digo data de pronto.', v_n, v_nmin)
                    else format('Prazo real: %s em cada 10 OS terminaram em até %s os dias planejados (%s OS). Com essa folga, um serviço de 5 dias acaba em até %s dias úteis. Só para você: ao cliente não digo data de pronto.',
                                round(coalesce((p_d ->> 'fator_percentil')::numeric, (p_d #>> '{detalhe,percentil}')::numeric) * 10),
                                public._agenda_aprendizado_valor('promessa', coalesce((p_d #>> '{detalhe,p80}')::numeric, (p_d ->> 'calculado')::numeric)),
                                v_n, round(5 * (p_d ->> 'calculado')::numeric)) end;
      elsif p_item = 'tempo_compra' then
        return case p_momento
          when 'foco_medindo' then format('Seu tempo para comprar: %s (da aprovação até a compra); no "compre até" conto %s (padrão).',
                                          case when v_7e_n = 0 then 'nenhuma OS medida ainda' else format('%s de %s OS medidas', v_n, v_nmin) end, v_padrao)
          when 'foco_sombra' then format('Em teste: da aprovação até a compra você levou %s (o do meio de %s OS); junto com o padrão de %s, eu contaria %s no "compre até". Hoje conto %s.',
                                         public._agenda_aprendizado_valor(p_item, (p_d #>> '{detalhe,percentil}')::numeric), v_n, v_7e_pnum, v_calc, v_7e_pnum)
          when 'foco_em_uso' then
            case when v_7e_alvo then format('Da aprovação até a compra você leva por volta de %s (%s OS medidas): é o que conto no "compre até" desde %s.', v_uso, v_n, v_desde)
                 else format('Da aprovação até a compra você leva por volta de %s (%s OS medidas): conto %s no "compre até" desde %s e chego lá aos poucos.', v_calc, v_n, v_uso, v_desde) end
          when 'foco_travado' then format('Da aprovação até a compra você leva por volta de %s (%s OS medidas); fico com %s no "compre até" até %s, como você decidiu.', v_calc, v_n, v_efet, v_trava)
          when 'acao' then format('Medi o seu tempo da aprovação até a compra (%s OS): passei a contar %s no "compre até" (era %s), só nas OS que eu ainda não marquei: o pedido de compra sai %s mais %s. *desfaz aprendizado* volta.',
                                  v_n, v_uso, v_7e_num, public._agenda_aprendizado_valor(p_item, abs((p_d ->> 'em_uso')::numeric - (p_d ->> 'efetivo')::numeric)),
                                  case when v_7e_sobe then 'cedo' else 'tarde' end)
          when 'desfeito' then format('Desfeito: volto a contar %s no "compre até", só nas OS que eu ainda não marquei. Não troco de novo por %s dias, salvo se o medido mudar muito.', v_volta, v_dias)
        end;
      elsif p_item = 'folga_compra' then
        return case when p_momento = 'foco_sombra' then
                 format('Em teste: nas OS marcadas antes da compra, a peça chegou até %s depois do que eu contava (%s OS; %s no prazo; %s começaram no dia marcado); eu daria %s a mais só a elas. Hoje não dou.',
                        public._agenda_aprendizado_valor(p_item, (p_d #>> '{detalhe,maior}')::numeric), v_n, coalesce(p_d #>> '{detalhe,no_prazo}', '0'), coalesce(p_d #>> '{detalhe,comecaram_no_dia}', '0'), v_calc)
               else format('OS marcadas antes da compra: %s; dou %s entre a chegada da peça e o 1º dia, como em todas.',
                           case when v_7e_n = 0 then 'nenhuma medida ainda' else format('%s de %s medidas', v_n, v_nmin) end,
                           public._agenda_aprendizado_valor(p_item, coalesce((p_d ->> 'folga_material_du')::numeric, 1))) end;
      else
        -- prazo_sem_fornecedor: só medida
        return case when p_momento = 'foco_sombra' then
                 format('Peças compradas sem fornecedor dito antes: chegaram em até %s depois da compra (%s compras); conto %s (o padrão é decisão sua).', v_calc, v_n, v_padrao)
               else format('Peças compradas sem fornecedor dito antes: %s; conto %s (padrão).',
                           case when v_7e_n = 0 then 'nenhuma compra medida ainda' else format('%s de %s compras medidas', v_n, v_nmin) end, v_padrao) end;
      end if;
    end;
  end if;
  -- FASE 7e: fim
  -- CORREÇÃO FASE 6: (C2) texto 5: a pergunta do R$ por diária (a troca grande do valor) diz que a conta inclui as OS em
  -- que o dono também trabalhou (a mão de obra delas entra; as diárias dele não); a opção 1 sai sem o "(recomendo)" (o
  -- gravador não o põe no valor: _agenda_aprendizado_gravar). O resto do valor, como antes (abaixo).
  if p_item = 'mo' and p_momento = 'pergunta' then
    return format('Medi a mão de obra por diária: cada diária rendeu %s (%s OS com diária ligada; inclui as OS em que você também trabalhou), e hoje eu uso %s para estimar os dias pelo valor. É uma troca grande.',
                  v_calc, v_n, v_efet);
  end if;
  -- CORREÇÃO FASE 6: fim
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
  -- FASE 6: (P3) o fornecedor (spec-fase6 §6.2 e §6.3): o atraso das entregas (padrão 0: a chegada no dia que o fornecedor
  -- diz) e o prazo da nota (da saída até a chegada; padrão = o prazo de hoje). O nome é o curto do cadastro (detalhe.nome),
  -- sem artigo; detalhe.no_prazo = as entregas no prazo; detalhe.dono = o prazo é o que o dono disse (só mede).
  if p_item in ('fornecedor_atraso', 'fornecedor_prazo') then
    declare
      v_nome  text := coalesce(p_d #>> '{detalhe,nome}', 'O fornecedor');
      v_np    text := coalesce(p_d #>> '{detalhe,no_prazo}', '0');
      v_dono  boolean := coalesce((p_d #>> '{detalhe,dono}')::boolean, false);
      v_cnum  numeric := coalesce((p_d ->> 'calculado')::numeric, 0);
      v_unum  numeric := coalesce((p_d ->> 'em_uso')::numeric, 0);
      v_vnum  numeric := coalesce((p_d ->> 'volta')::numeric, (p_d ->> 'padrao')::numeric, 0);
      -- "a chegada 2 dias úteis depois do que o fornecedor diz" / "a chegada no dia que o fornecedor diz"
      v_ccheg text := case when v_cnum > 0 then format('a chegada %s depois do que o fornecedor diz', v_calc)
                           else 'a chegada no dia que o fornecedor diz' end;
      v_ucheg text := case when v_unum > 0 then format('a chegada %s depois do que o fornecedor diz', v_uso)
                           else 'a chegada no dia que o fornecedor diz' end;
      v_echeg text := case when coalesce((p_d ->> 'efetivo')::numeric, 0) > 0
                           then format('a chegada %s depois do que o fornecedor diz', v_efet)
                           else 'a chegada no dia que o fornecedor diz' end;
      v_vcheg text := case when v_vnum > 0
                           then format('a chegada %s depois do que o fornecedor diz',
                                       public._agenda_aprendizado_valor('fornecedor_atraso', v_vnum))
                           else 'a chegada no dia que o fornecedor diz' end;
    begin
      if p_item = 'fornecedor_atraso' then
        return case p_momento
          when 'foco_medindo' then format('%s: %s de %s entregas medidas.', v_nome, v_n, v_nmin)
          when 'foco_sombra' then format('%s: %s de %s entregas no prazo%s (em teste).', v_nome, v_np, v_n,
                                         case when v_cnum > 0 then '; o atraso chega a ' || v_calc else '' end)
          when 'foco_em_uso' then format('%s: %s de %s entregas no prazo%s: conto %s (desde %s).', v_nome, v_np, v_n,
                                         case when v_unum > 0 then '; o atraso chega a ' || v_uso else '' end, v_ucheg, v_desde)
          when 'foco_pergunta' then format('%s: o atraso chega a %s (%s entregas), e hoje conto %s: a troca espera a sua resposta.',
                                           v_nome, v_calc, v_n, v_echeg)
          when 'foco_travado' then format('%s: o atraso chega a %s (%s entregas); fico com %s até %s, como você decidiu.',
                                          v_nome, v_calc, v_n, v_echeg, v_trava)
          when 'acao' then case when v_cnum > 0
                                then format('%s atrasou até %s em %s entregas: passei a contar %s. *desfaz aprendizado* volta.',
                                            v_nome, v_calc, v_n, v_ccheg)
                                else format('%s voltou a entregar no prazo (%s de %s entregas): passei a contar %s. *desfaz aprendizado* volta.',
                                            v_nome, v_np, v_n, v_ccheg) end
          when 'pergunta' then case when v_cnum > 0
                                    then format('Medi as entregas de %s: o atraso chega a %s (%s entregas), e hoje eu conto %s. É uma troca grande.',
                                                v_nome, v_calc, v_n, v_echeg)
                                    else format('Medi as entregas de %s: %s de %s no prazo, e hoje eu conto %s. É uma troca grande.',
                                                v_nome, v_np, v_n, v_echeg) end
          when 'opcao1' then format('Passo a contar %s', v_ccheg)
          when 'opcao2' then format('Fico com %s', v_echeg)
          when 'opcao3' then 'Volto ao padrão'
          when 'desfeito' then format('Desfeito: para %s volto a contar %s. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                      v_nome, v_vcheg, v_dias)
          when 'fico' then format('Combinado: para %s fico com %s. Volto a perguntar se o medido mudar muito.', v_nome, v_echeg)
        end;
      end if;
      -- o prazo da nota: da saída (despacho) até a chegada
      return case p_momento
        when 'foco_medindo' then case when v_dono
               then format('%s: você disse %s; medi %s notas da saída até a chegada (vale o que você disse).',
                           v_nome, coalesce(v_padrao, 'o prazo'), v_n)
               else format('%s: %s de %s notas medidas da saída até a chegada; conto %s (padrão).',
                           v_nome, v_n, v_nmin, coalesce(v_padrao, 'o prazo da classe')) end
        when 'foco_sombra' then format('Em teste: %s leva até %s da saída da nota até a chegada (%s notas); hoje conto %s (padrão).',
                                       v_nome, v_calc, v_n, coalesce(v_padrao, 'o prazo da classe'))
        when 'foco_em_uso' then format('%s leva até %s da saída da nota até a chegada (%s notas): é o prazo que uso desde %s.',
                                       v_nome, v_uso, v_n, v_desde)
        when 'foco_pergunta' then format('%s leva até %s da saída da nota até a chegada (%s notas), e hoje conto %s: a troca espera a sua resposta.',
                                         v_nome, v_calc, v_n, coalesce(v_efet, 'o prazo da classe'))
        when 'foco_travado' then format('%s leva até %s da saída da nota até a chegada (%s notas); fico com %s até %s, como você decidiu.',
                                        v_nome, v_calc, v_n, coalesce(v_efet, 'o prazo da classe'), v_trava)
        when 'acao' then format('Medi as notas de %s: da saída até a chegada levam até %s (%s notas). Passei a contar %s no lugar de %s. *desfaz aprendizado* volta.',
                                v_nome, v_calc, v_n, v_calc, coalesce(v_efet, 'o prazo da classe'))
        when 'pergunta' then format('Medi as notas de %s: da saída até a chegada levam até %s (%s notas), e hoje eu conto %s. É uma troca grande.',
                                    v_nome, v_calc, v_n, coalesce(v_efet, 'o prazo da classe'))
        when 'opcao1' then format('Passo a contar %s', v_calc)
        when 'opcao2' then format('Fico com %s', coalesce(v_efet, 'o prazo da classe'))
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: para %s volto a contar %s da saída da nota até a chegada. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                    v_nome, coalesce(v_volta, v_padrao, 'o prazo da classe'), v_dias)
        when 'fico' then format('Combinado: para %s fico com %s. Volto a perguntar se o medido mudar muito.',
                                v_nome, coalesce(v_efet, 'o prazo da classe'))
      end;
    end;
  end if;
  -- FASE 6: fim
  -- FASE 6: (P4) a capacidade do dono (spec-fase6 §6.2 e §6.3): quanto dos meios-dias dele marcados no plano ele fez (a
  -- mediana das semanas: detalhe.taxa; "7 de cada 10"), nas últimas detalhe.janela semanas, e a parte da semana dele que o
  -- motor marca (o padrão é carga_max, a de todos). "Seria" no singular só em teste (o spec); "seriam" na pergunta.
  if p_item = 'capacidade_dono' then
    declare
      v_taxa numeric := (p_d #>> '{detalhe,taxa}')::numeric;
      v_dez  text := coalesce(round(v_taxa * 10)::text, '?');
      v_ult  text := case when p_d #>> '{detalhe,janela}' is null then 'Nas últimas semanas'
                          else format('Nas últimas %s semanas', p_d #>> '{detalhe,janela}') end;
      v_sems text := public._agenda_plural(coalesce((p_d ->> 'n')::int, 0), 'semana medida', 'semanas medidas');
    begin
      return case p_momento
        when 'foco_medindo' then format('A sua semana no plano: %s de %s semanas medidas; marco até %s da sua semana (padrão).',
                                        v_n, v_nmin, coalesce(v_padrao, 'a parte de todos'))
        when 'foco_sombra' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano (%s). Hoje marco até %s da sua semana; pelo medido seria %s (em teste).',
                                       v_ult, v_dez, v_sems, coalesce(v_padrao, 'a parte de todos'), v_calc)
        when 'foco_em_uso' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano (%s): marco até %s da sua semana desde %s.',
                                       v_ult, v_dez, v_sems, v_uso, v_desde)
        when 'foco_pergunta' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano (%s). Hoje marco até %s da sua semana; pelo medido seriam %s: a troca espera a sua resposta.',
                                         v_ult, v_dez, v_sems, coalesce(v_efet, v_padrao), v_calc)
        when 'foco_travado' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano (%s). Pelo medido seriam %s; fico com %s da sua semana até %s, como você decidiu.',
                                        v_ult, v_dez, v_sems, v_calc, coalesce(v_efet, v_padrao), v_trava)
        when 'acao' then format('%s você fez %s de cada 10 meios-dias seus do plano: passei a marcar até %s da sua semana (era %s). *desfaz aprendizado* volta.',
                                v_ult, v_dez, v_calc, coalesce(v_efet, v_padrao))
        when 'pergunta' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano. Hoje marco até %s da sua semana; pelo medido seriam %s.',
                                    v_ult, v_dez, coalesce(v_efet, v_padrao), v_calc)
        when 'opcao1' then format('Passo a marcar até %s', v_calc)
        when 'opcao2' then format('Fico com %s', coalesce(v_efet, v_padrao))
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: volto a marcar até %s da sua semana. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                    coalesce(v_volta, v_padrao, 'a parte de todos'), v_dias)
        when 'fico' then format('Combinado: fico com %s da sua semana. Volto a perguntar se o medido mudar muito.',
                                coalesce(v_efet, v_padrao))
      end;
    end;
  end if;
  -- FASE 6: fim
  -- FASE 6: (P5) a pontualidade com o cliente (só medida: só a linha do foco) e a folga do aviso de atraso (spec-fase6 §6.2
  -- e §6.3). A pontualidade lê detalhe.no_prazo e detalhe.p80_atraso_du; a folga é a faixa do aviso "com 2 dias úteis a mais"
  -- (0 = a faixa do plano, o padrão)
  if p_item = 'cliente_pontualidade' and p_momento like 'foco_%' then
    if p_momento = 'foco_medindo' then
      return format('Pontualidade: %s de %s OS com a 1ª data dita ao cliente medidas.', v_n, v_nmin);
    end if;
    return format('Pontualidade: %s de %s OS ficaram prontas até o dia dito primeiro ao cliente%s.',
                  coalesce(p_d #>> '{detalhe,no_prazo}', '0'), v_n,
                  case when coalesce((p_d #>> '{detalhe,p80_atraso_du}')::numeric, 0) > 0
                       then '; o atraso chega a ' || public._agenda_aprendizado_valor('aviso_folga', (p_d #>> '{detalhe,p80_atraso_du}')::numeric)
                       else '' end);
  end if;
  if p_item = 'aviso_folga' then
    declare
      v_cn numeric := coalesce((p_d ->> 'calculado')::numeric, 0);
      -- "a faixa com 2 dias úteis a mais" / "a faixa do plano", de cada valor
      v_fc text := case when coalesce((p_d ->> 'calculado')::numeric, 0) > 0 then format('a faixa com %s a mais', v_calc)
                        else 'a faixa do plano' end;
      v_fu text := case when coalesce((p_d ->> 'em_uso')::numeric, 0) > 0 then format('a faixa com %s a mais', v_uso)
                        else 'a faixa do plano' end;
      v_fe text := case when coalesce((p_d ->> 'efetivo')::numeric, (p_d ->> 'padrao')::numeric, 0) > 0
                        then format('a faixa com %s a mais',
                                    public._agenda_aprendizado_valor('aviso_folga', coalesce((p_d ->> 'efetivo')::numeric, (p_d ->> 'padrao')::numeric)))
                        else 'a faixa do plano' end;
      v_fv text := case when coalesce((p_d ->> 'volta')::numeric, (p_d ->> 'padrao')::numeric, 0) > 0
                        then format('a faixa com %s a mais',
                                    public._agenda_aprendizado_valor('aviso_folga', coalesce((p_d ->> 'volta')::numeric, (p_d ->> 'padrao')::numeric)))
                        else 'a faixa do plano' end;
      v_terminou text := case when coalesce((p_d ->> 'calculado')::numeric, 0) > 0
                              then format('o serviço terminou até %s depois do fim que eu disse', v_calc)
                              else 'o serviço terminou dentro da faixa que eu disse' end;
    begin
      return case p_momento
        when 'foco_medindo' then format('Avisos de atraso: %s de %s avisos medidos; dou %s (padrão).', v_n, v_nmin, v_fe)
        when 'foco_sombra' then format('Avisos de atraso: em %s, %s (em teste: eu daria %s).', v_n, v_terminou, v_fc)
        when 'foco_em_uso' then format('Avisos de atraso: em %s, %s: dou %s desde %s.', v_n, v_terminou, v_fu, v_desde)
        when 'foco_pergunta' then format('Avisos de atraso: em %s, %s, e hoje dou %s: a troca espera a sua resposta.',
                                         v_n, v_terminou, v_fe)
        when 'foco_travado' then format('Avisos de atraso: em %s, %s; fico com %s até %s, como você decidiu.',
                                        v_n, v_terminou, v_fe, v_trava)
        when 'acao' then format('Os avisos de atraso erraram para %s (%s avisos): passei a dar %s%s. *desfaz aprendizado* volta.',
                                case when v_cn > coalesce((p_d ->> 'efetivo')::numeric, 0) then 'menos' else 'mais' end,
                                v_n, v_fc,
                                case when coalesce((p_d ->> 'efetivo')::numeric, 0) > 0 then format(' (era %s)', v_fe) else '' end)
        when 'pergunta' then format('Medi os avisos de atraso: em %s, %s, e hoje eu dou %s. É uma troca grande.', v_n, v_terminou, v_fe)
        when 'opcao1' then format('Passo a dar %s', v_fc)
        when 'opcao2' then format('Fico com %s', v_fe)
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: volto a dar %s. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                    v_fv, v_dias)
        when 'fico' then format('Combinado: fico com %s. Volto a perguntar se o medido mudar muito.', v_fe)
      end;
    end;
  end if;
  -- FASE 6: fim
  -- FASE 6: (P6) a carga de cada pessoa pelo plano cumprido (a revisão) e os gatilhos de um planejador mais forte (spec-fase6
  -- §6.2 e §6.3). A carga lê detalhe.mostrar (o plano cumprido das semanas que o texto diz, da mais antiga para a mais nova),
  -- detalhe.gatilho (baixo, alto ou nulo), detalhe.meta, detalhe.ppc_baixo e detalhe.ppc_alto; o planejador lê os números
  -- da semana (os_ativas, pessoas, valem, n_valem, total, limites), as semanas seguidas e a resposta da pergunta (uma vez só)
  if p_item = 'carga' then
    declare
      v_pcts  text[] := array(select public._agenda_aprendizado_valor('carga', x::numeric)
                                from jsonb_array_elements_text(coalesce(p_d #> '{detalhe,mostrar}', '[]'::jsonb))
                                     with ordinality t(x, o)
                               order by o);
      v_k     int := cardinality(array(select x from jsonb_array_elements_text(coalesce(p_d #> '{detalhe,mostrar}', '[]'::jsonb)) x));
      v_gat   text := p_d #>> '{detalhe,gatilho}';
      v_meta  text := public._agenda_aprendizado_valor('carga', (p_d #>> '{detalhe,meta}')::numeric);
      v_hoje  text := coalesce(v_efet, v_padrao);
      v_cumpr text;
    begin
      v_cumpr := case when v_k = 0 then 'O plano cumprido ainda não foi medido'
                      when v_k = 1 then format('O plano foi cumprido em %s na última semana (meta %s)', v_pcts[1], v_meta)
                      else format('O plano foi cumprido em %s nas últimas %s semanas (meta %s)', public._agenda_lista(v_pcts, null),
                                  v_k, v_meta) end;
      return case p_momento
        when 'foco_medindo' then format('O plano cumprido: %s de %s semanas medidas; marco até %s da semana de cada pessoa.',
                                        v_n, v_nmin, v_padrao)
        when 'foco_sombra' then v_cumpr || '.'
                                || case when (p_d ->> 'calculado')::numeric is distinct from (p_d ->> 'padrao')::numeric
                                        then format(' Em teste: eu perguntaria se passo a marcar até %s da semana de cada pessoa (hoje %s).',
                                                    v_calc, v_padrao)
                                        else '' end
        when 'foco_em_uso' then format('%s; marco até %s da semana de cada pessoa.', v_cumpr, v_uso)
        when 'foco_pergunta' then format('%s: perguntei se passo a marcar até %s da semana de cada pessoa (hoje %s); espera a sua resposta.',
                                         v_cumpr, v_calc, v_hoje)
        when 'foco_travado' then format('%s; fico com %s até %s, como você decidiu.', v_cumpr, v_hoje, v_trava)
        when 'acao' then format('Passei a marcar até %s da semana de cada pessoa (era %s), como você decidiu. *desfaz aprendizado* volta.',
                                v_calc, v_hoje)
        when 'pergunta' then case v_gat
          when 'alto' then format('O plano foi cumprido acima de %s em %s semanas seguidas: posso estar marcando pouco.',
                                  public._agenda_aprendizado_valor('carga', (p_d #>> '{detalhe,ppc_alto}')::numeric), v_k)
          else format('O plano foi cumprido abaixo de %s em %s semanas seguidas (%s). Recomendo marcar até %s da semana de cada pessoa (hoje %s).',
                      public._agenda_aprendizado_valor('carga', (p_d #>> '{detalhe,ppc_baixo}')::numeric), v_k,
                      array_to_string(v_pcts, ', '), v_calc, v_hoje) end
        when 'opcao1' then format('Passo para %s', v_calc)
        when 'opcao2' then format('Fico com %s', v_hoje)
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: volto a marcar até %s da semana de cada pessoa. Não pergunto de novo por %s dias, salvo se o plano cumprido mudar.',
                                    coalesce(v_volta, v_padrao), v_dias)
        when 'fico' then format('Combinado: fico com %s. Volto a perguntar em %s dias se o plano cumprido continuar assim.', v_hoje, v_dias)
      end;
    end;
  end if;
  if p_item = 'solver' then
    declare
      v_valem text[] := array(select x from jsonb_array_elements_text(coalesce(p_d #> '{detalhe,valem}', '[]'::jsonb)) x);
      v_base  text := format('Gatilhos de um planejador mais forte: %s de %s (%s OS ativas, %s pessoas)',
                             coalesce(p_d #>> '{detalhe,n_valem}', '0'), coalesce(p_d #>> '{detalhe,total}', '0'),
                             coalesce(p_d #>> '{detalhe,os_ativas}', '0'), coalesce(p_d #>> '{detalhe,pessoas}', '0'));
      v_resp  text := p_d #>> '{detalhe,resposta}';
      v_ja    boolean := coalesce((p_d #>> '{detalhe,perguntado}')::boolean, false);
      v_lista text;
    begin
      v_lista := public._agenda_lista(array(
        select 'de ' || case g
                 when 'os_ativas' then format('%s OS ativas', p_d #>> '{detalhe,limites,os_ativas}')
                 when 'pessoas' then format('%s pessoas', p_d #>> '{detalhe,limites,pessoas}')
                 when 'curtas_dia' then format('%s idas curtas suas por dia útil',
                                               public._agenda_num((p_d #>> '{detalhe,limites,curtas_dia}')::numeric, 1))
                 when 'descarte' then format('%s%% dos planos que eu sugeri descartados',
                                             round(100 * (p_d #>> '{detalhe,limites,descarte}')::numeric))
               end
          from unnest(v_valem) with ordinality u(g, o) order by o), null);
      return case p_momento
        when 'foco_medindo' then format('%s; medi %s de %s semanas.', v_base, v_n, v_nmin)
        when 'foco_sombra' then v_base || '.'
                                || case when (p_d ->> 'calculado')::numeric >= 1
                                        then ' Em teste: eu avisaria que vale estudar um planejador mais forte.' else '' end
        when 'foco_pergunta' then v_base || '. Perguntei se vale estudar um planejador mais forte; espera a sua resposta.'
        when 'foco_em_uso' then v_base || case when v_resp = '1' then '. Você quis ver isso; nada muda sozinho.'
                                               when v_resp = '2' then '. Você disse "agora não"; não pergunto de novo.'
                                               when v_ja then '. Já perguntei uma vez; não pergunto de novo.'
                                               else '.' end
        when 'foco_travado' then v_base || '. Você disse "agora não"; não pergunto de novo.'
        when 'pergunta' then format('Há %s semanas a agenda passa %s: vale estudar um planejador mais forte. Nada muda sozinho.',
                                    coalesce(p_d #>> '{detalhe,semanas_seguidas}', v_n), v_lista)
        when 'opcao1' then 'Quero ver isso'
        when 'opcao2' then 'Agora não'
        when 'opcao3' then 'Volto ao padrão'
        when 'acao' then 'Combinado: anotei que você quer ver um planejador mais forte. Nada muda sozinho na agenda.'
        when 'fico' then 'Combinado: agora não. Não pergunto de novo.'
        when 'desfeito' then 'Desfeito: volto a só medir os gatilhos de um planejador mais forte.'
      end;
    end;
  end if;
  -- FASE 6: fim
  -- O fator de campo (spec-fase6 §6.2 e §6.3).
  -- CORREÇÃO FASE 6: (C2) texto 1: a linha do fator no cartão e no foco diz para que o fator serve — o limiar do "o que
  -- falta?"; os dias do plano continuam os que o dono disse (a linha fica logo abaixo de "4 dias (você disse)" e fazia crer
  -- que o plano usa 1,7 × 4) —; com o valor em uso igual ao padrão, que é o mesmo de sempre (e não "desde sex 30/10"); em
  -- teste, com o medido igual ao padrão, sem o "hoje seria 1,5×, e vale 1,5×". Os outros momentos, como antes (abaixo).
  if p_item = 'fator' and v_nivel is not null and p_momento = 'foco_em_uso' then
    if (p_d ->> 'em_uso')::numeric is not distinct from (p_d ->> 'padrao')::numeric then
      return format('%s levam até %s o combinado (%s OS): é o mesmo que eu já usava.',
                    public._agenda_maiuscula(v_nivel), v_uso, v_n);
    end if;
    return format('%s levam até %s o combinado (%s OS): uso %s desde %s para perguntar o que falta (os dias do plano continuam os que você disse).',
                  public._agenda_maiuscula(v_nivel), v_uso, v_n, v_uso, v_desde);
  end if;
  if p_item = 'fator' and v_nivel is not null and p_momento = 'foco_sombra'
     and (p_d ->> 'calculado')::numeric is not distinct from (p_d ->> 'padrao')::numeric then
    return format('Em teste: %s levam até %s o combinado (%s OS): é o mesmo que eu já uso.', v_nivel, v_calc, v_n);
  end if;
  -- CORREÇÃO FASE 6: fim
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
  'Agenda de Produção (Fase 6): os textos do aprendizado ao dono, do banco — p_momento foco_<estado> (a linha do foco), acao (o que mudou sozinho), pergunta (a troca grande, sem as opções), opcao1/2/3, desfeito e fico. p_d: {chave, calculado, em_uso, efetivo (o que valia antes), padrao, volta, n, n_min, desde, travado_ate, trava_dias}. O fator tem os textos da spec-fase6 §6.2/§6.3; os outros itens, um texto provisório que o pacote de cada um recria (copiar DESTA definição). FASE 6 (P2): o R$ por diária (mo) e a presença do dono têm os textos da spec §6.2/§6.3 (a presença lê detalhe.k, as idas do dono). FASE 6 (P3): o atraso (fornecedor_atraso) e o prazo da nota (fornecedor_prazo) têm os textos da spec §6.2/§6.3 (o nome, as entregas no prazo e o "você disse" vêm do detalhe). FASE 6 (P4): a capacidade do dono (capacidade_dono) tem os textos da spec §6.2/§6.3 ("Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus marcados no plano …"; a taxa e a janela vêm do detalhe). FASE 6 (P5): a pontualidade com o cliente (cliente_pontualidade: só a linha do foco, "Pontualidade: 5 de 7 OS ficaram prontas até o dia dito primeiro ao cliente; o atraso chega a 2 dias úteis.") e a folga do aviso de atraso (aviso_folga: "a faixa com 2 dias úteis a mais"; 0 = a faixa do plano) têm os textos da spec §6.2/§6.3. FASE 6 (P6): a carga de cada pessoa pelo plano cumprido ("O plano foi cumprido em 52%, 55% e 48% nas últimas 3 semanas (meta 70%)."; a pergunta "abaixo de 60% em 3 semanas seguidas (…). Recomendo marcar até 70% …") e os gatilhos de um planejador mais forte ("Gatilhos de um planejador mais forte: 0 de 4 (9 OS ativas, 4 pessoas)."; a pergunta "Há 4 semanas a agenda passa de 25 OS ativas e de 6 pessoas: …") têm os textos da spec §6.2/§6.3. Todos os itens com o texto da spec. CORREÇÃO FASE 6 (C2, textos 1 e 5): o fator em uso diz "uso 1,7× desde … para perguntar o que falta (os dias do plano continuam os que você disse)", e "é o mesmo que eu já usava" com o valor do padrão; em teste, com o medido igual ao padrão, sem o "hoje seria X, e vale X"; a pergunta do R$ por diária diz que inclui as OS em que o dono também trabalhou. FASE 7e (P2): os textos da spec §6.2/§6.3 (com R7.3) para os 6 itens da margem. Nunca perguntam. O desfeito usa volta (um passo só) e diz que a OS marcada guarda o valor. FASE 7e (P4): folga_semana com calculado nulo: medindo com as semanas já bastando diz o que falta (as OS medidas ou a variação delas); em uso, travado e a ação dizem que ficou sem medida e que volta ao padrão aos poucos.';

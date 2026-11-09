-- Agenda de Produção, Fase 7, etapa 7e ("A margem que aprende"), pacote P5: o prazo real. O quanto as OS concluídas passam dos dias planejados, medido, e a data com folga de uma OS, só para o dono.
-- Spec: scratchpad agenda-pesquisa/spec-fase7e.md (o bloco R7, que vale sobre o corpo: R7.3-1, R7.6, R7.13; e §5.4, só nas 2 funções que sobram); nomes: fase7-registro.md; o registro do pacote: f7e/p5/notas.md.
-- Depende de 20261111100000 (P1) e 20261111100100 (P2: a razao_prazo, o gravador e o texto do item promessa). Não recria nenhuma função de antes.
--
-- ═══ NÃO APLICADA ═══ Existe para revisão e espera o OK (publicar/exec/aplicar.sh, nunca db push: esta versão fica antes das 20261116* que já estão em produção). 2 funções novas e o comentário de uma coluna; nenhuma coluna nem dado.
--
-- POR QUE: fator_promessa está na config desde a Fase 1 sem ninguém ler (NOVO-agenda-43). O dono respondeu que o cliente não ouve data de pronto (AG7-32, "Não incluir a data de pronto"), então a medida do prazo fica só para ele: quantas OS cabem nos dias planejados e, numa OS marcada, até quando ela iria com a folga do histórico.
--
-- O QUE MUDA:
--   1. _agenda_aprender_promessa: o passo da rodada do aprendizado (o P7 o põe em agenda_aprender; até lá, ninguém o chama). Sobre as razao_prazo da janela, o geral e cada classe fina: o P80 (fator_percentil), encolhido pela credibilidade (o geral para fator_promessa; a classe, para o geral sem arredondar), entre promessa_min e fator_max, 2 casas. Grava em agenda_aprendizado pelo gravador do P2, que nunca põe este item em uso.
--   2. agenda_promessa_da_os: a leitura para o dono. {ok, os, inicio, fim_plano, prazo_du, fator, fonte, chave, n, fim_com_folga}; sem plano, {ok: true, sem_plano: true}. Sem ramo de modo: o que ela devolve não depende de modo_promessa (R7.3-1).
--   3. O comentário de fator_promessa deixa de dizer "SEM LEITOR".
--
-- O QUE NÃO MUDA: nenhuma função de cliente, da equipe, do motor, da vigia ou da rodada. modo_promessa continua em sombra para sempre, e nada daqui chega ao cliente nem à equipe (AG7-32). Nenhuma mensagem, pergunta nem ação nova. Em produção a medição hoje dá 0 razões (R7.4): sem OS medida, o fator é o padrão.
--
-- DESFAZER (na ordem):
--   drop function if exists public.agenda_promessa_da_os(uuid, date);
--   drop function if exists public._agenda_aprender_promessa(date, timestamptz);
--   comment on column public.agenda_config.fator_promessa is 'Agenda de Produção (Fase 1): a folga da promessa ao cliente prevista no plano (fim + metade da duração). SEM LEITOR (NOVO-agenda-43): a M1 diz o início e os dias; o 1,5 que age é estouro_fator, e é ele que o fator de campo aprendido substitui (Fase 6).';

-- §5.4, R7.3-1: o passo da rodada. O molde é _agenda_aprender_vies (P3), com o P80 no lugar da mediana. O padrão das duas chaves é fator_promessa: a spec punha, na classe, o em uso do geral, mas este item nunca fica em uso (AG7-32).
create or replace function public._agenda_aprender_promessa(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  r        record;
  v        jsonb;
  v_geral  numeric;
  v_p80    numeric;
  v_cred   numeric;
  v_calc   numeric;
  v_est    jsonb := '{}'::jsonb;
  n_ch     int := 0;
  n_err    int := 0;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  for r in
    with med as (
      select m.service_order_id as os, so.service_order_number as numero, m.razao_prazo as razao, m.concluida_em,
             m.classe_bem || ':' || m.classe_sistema as fina
        from public.agenda_medidas_os m
        join public.service_orders so on so.id = m.service_order_id
       where m.razao_prazo is not null
         and m.concluida_em between p_hoje - c.aprender_janela_dias and p_hoje),
    chaves as (
      select med.*, x.chave, x.nivel, x.ordem
        from med
        cross join lateral (values ('todas', 'todas', 1), (med.fina, 'fina', 2)) x(chave, nivel, ordem)),
    recentes as (
      select ch.*, row_number() over (partition by ch.chave order by ch.concluida_em desc, ch.os) as rn
        from chaves ch),
    por_chave as (
      select rc.chave, rc.nivel, rc.ordem, count(*)::int as n,
             array_agg(rc.razao order by rc.concluida_em desc, rc.os) as razoes,
             jsonb_agg(jsonb_build_object('os', rc.os, 'numero', rc.numero, 'razao', rc.razao, 'em', rc.concluida_em)
                       order by rc.concluida_em desc, rc.os) as amostra
        from recentes rc
       where rc.rn <= c.fator_amostra_max
       group by rc.chave, rc.nivel, rc.ordem)
    select pc.chave, pc.nivel, pc.ordem, pc.n, pc.razoes, pc.amostra from por_chave pc
    union all
    -- a chave que já tem linha e ficou sem medida volta a medir
    select a.chave, a.nivel, case a.nivel when 'fina' then 2 else 1 end, 0, null::numeric[], '[]'::jsonb
      from public.agenda_aprendizado a
     where a.item = 'promessa' and not exists (select 1 from por_chave pc where pc.chave = a.chave)
     order by 3, 1
  loop
    n_ch := n_ch + 1;
    begin
      -- o geral vem antes das finas (order by) e é a base delas, preso nos limites e sem arredondar
      v_p80 := public._agenda_percentil(r.razoes, c.fator_percentil);
      v_cred := least(greatest(public._agenda_credibilidade(v_p80, r.n, case when r.nivel = 'todas' then c.fator_promessa else v_geral end, c.credibilidade_k),
                               c.promessa_min), c.fator_max);
      if r.nivel = 'todas' then
        v_geral := v_cred;
      end if;
      v_calc := case when v_p80 is not null then round(v_cred, 2) end;
      v := public._agenda_aprendizado_gravar('promessa', r.chave, r.nivel, v_calc, r.n, r.amostra, c.fator_promessa,
             jsonb_build_object('p80', round(v_p80, 4), 'z', round(r.n::numeric / (r.n + c.credibilidade_k), 4), 'n', r.n), p_agora);
      v_est := v_est || jsonb_build_object(v ->> 'estado', coalesce((v_est ->> (v ->> 'estado'))::int, 0) + 1);
    exception when others then
      perform public.log_app_error('db', format('aprendizado, prazo real %s: %s', r.chave, sqlerrm), 'agenda', 'aprender:promessa', 'error',
                                   jsonb_build_object('chave', r.chave, 'sqlstate', sqlstate, 'p_hoje', p_hoje));
      n_err := n_err + 1;
    end;
  end loop;
  return jsonb_build_object('chaves', n_ch, 'estados', v_est, 'erros', n_err);
end;
$function$;

comment on function public._agenda_aprender_promessa(date, timestamptz) is
  'Agenda de Produção (Fase 7e, P5; §5.4, R7.3-1): o passo do prazo real da rodada do aprendizado — sobre as razao_prazo na janela, as fator_amostra_max mais recentes por chave: o geral (P80 encolhido para fator_promessa pela credibilidade) e cada classe fina (encolhida para o geral sem arredondar), entre promessa_min e fator_max, 2 casas. O gravador nunca põe este item em uso (AG7-32): ele só mede, para o dono. Sem grant: quem chama é a rodada, a partir do P7. {chaves, estados, erros}.';

-- R7.3-1: a data com folga de uma OS, só para o dono (o molde de acesso é agenda_fator_de_campo). Sem ramo de modo. Lê o calculado (a classe, senão o geral, com medidas suficientes), senão fator_promessa.
create or replace function public.agenda_promessa_da_os(p_os uuid, p_hoje date default public._hoje_brt())
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
  v_pl    jsonb;
  v_ini   date;
  v_fim   date;
  a       public.agenda_aprendizado;
  v_fator numeric;
  v_prazo int;
  v_dias  int;
begin
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role. Um JWT de outro papel sem "sub" não vê.
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'O prazo real é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    if v_papel not in ('', 'service_role') then
      raise exception 'O prazo real é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  c := public._agenda_cfg();
  v_cl := public._agenda_classe_de_campo(p_os);
  if v_cl is null then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;
  v_pl := public._agenda_plano_da_os(p_os, p_hoje);
  v_ini := (v_pl ->> 'inicio')::date;
  v_fim := (v_pl ->> 'ultimo_dia')::date;
  -- sem alocação nenhuma o plano é nulo; só com reserva, o plano existe e não tem dia
  if v_ini is null or v_fim is null then
    return jsonb_build_object('ok', true, 'sem_plano', true);
  end if;
  select x.* into a
    from public.agenda_aprendizado x
   where x.item = 'promessa' and x.chave in (v_cl ->> 'chave', 'todas') and x.calculado is not null and x.n >= c.promessa_n_min
   order by case x.chave when 'todas' then 1 else 0 end
   limit 1;
  v_fator := coalesce(a.calculado, c.fator_promessa);
  v_prazo := public.agenda_du_entre(v_ini, v_fim) + 1;
  v_dias := round(v_prazo * v_fator)::int;
  return jsonb_build_object(
    'ok', true, 'os', p_os, 'inicio', v_ini, 'fim_plano', v_fim, 'prazo_du', v_prazo, 'fator', v_fator,
    'fonte', case when a.id is null then 'padrao' else 'aprendido' end,
    'chave', coalesce(a.chave, 'todas'),
    'n', coalesce(a.n, (select t.n from public.agenda_aprendizado t where t.item = 'promessa' and t.chave = 'todas'), 0),
    -- sem dia a mais, a data é a do plano: agenda_somar_du(sábado, 0) iria à segunda, e um plano que acaba no sábado não sairia antes dele
    'fim_com_folga', case when v_dias > v_prazo then public.agenda_somar_du(v_ini, v_dias - 1) else v_fim end);
end;
$function$;

comment on function public.agenda_promessa_da_os(uuid, date) is
  'Agenda de Produção (Fase 7e, P5; R7.3-1, AG7-32): só para o dono, nunca para o cliente nem para a equipe. {ok, os, inicio, fim_plano (o último dia do plano), prazo_du, fator, fonte (padrao|aprendido), chave, n, fim_com_folga}; sem plano, {ok: true, sem_plano: true}; OS que não existe, {ok: false, texto}. fator = o calculado da classe fina, senão o do geral (com n >= promessa_n_min), senão fator_promessa. Os dias com a folga = round(prazo × fator); fim_com_folga é o fim do plano quando a conta não acrescenta dia. O resultado não depende de modo_promessa nem do freio. Admin/financeiro ou service_role, senão 42501.';

revoke all on function public._agenda_aprender_promessa(date, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.agenda_promessa_da_os(uuid, date) from public, anon;
grant execute on function public.agenda_promessa_da_os(uuid, date) to authenticated, service_role;

-- A coluna ganha leitor: o comentário de antes dizia que ela não tinha nenhum (NOVO-agenda-43).
comment on column public.agenda_config.fator_promessa is
  'Agenda de Produção (Fase 7e, P5; AG7-32): o ponto de partida do prazo real que só o dono vê (agenda_promessa_da_os e _agenda_aprender_promessa). Nunca vai ao cliente: modo_promessa fica em sombra para sempre. O 1,5 do estouro continua sendo estouro_fator.';

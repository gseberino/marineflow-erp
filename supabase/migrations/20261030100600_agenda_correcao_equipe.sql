-- Agenda de Produção, correção de 30/10: quem é da equipe da agenda.
-- (4 funções recriadas, 1 comentário novo; nenhuma tabela, nenhum parâmetro, nenhum dado muda)
--
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/eqc/montar-migration.mjs. As 4 recriadas são
-- o corpo da definição MAIS NOVA (conferido a cada montagem em supabase/migrations): agenda_capacidade,
-- agenda_capacidade_semanal e agenda_resolver_pessoa de 20261024160400 (Fase 1, a única definição de cada uma);
-- _agenda_vigia_equipe_sem_dias de 20261030100500 (a revisão do lote, a única). As mudanças estão só nos blocos
-- "-- CORREÇÃO 30/10 (equipe): … -- CORREÇÃO 30/10 (equipe): fim". Quando um bloco troca linhas, cada linha de antes
-- fica nele como "-- antes: <a linha>" (o K de supabase/tests/agenda_correcao_2910_equipe.sql a devolve no lugar e
-- confere o resto, byte a byte).
--
-- ═══ O DEFEITO (produção, 30/10) ═══
--   Às 00:11 de sex 30/10 o dono tirou da agenda Roberto, João e Mickael e declarou o Alex Gonçalves Machado "todo dia
--   útil, manhã e tarde" (agenda_disponibilidade: dias {1,2,3,4,5}, o dia inteiro, disponível, origem dono; e a lista
--   da rotina, agenda_equipe_contato, incluído pelo dono). O Alex é prestador, ativo, sem work_profiles e sem telefone.
--   As três leituras que dizem quem é da equipe exigiam work_profiles vigente (a diária cadastrada):
--     · agenda_capacidade (a grade que o motor, a vigia, o livre e as telas leem): a equipe ficou vazia;
--     · agenda_capacidade_semanal (o único número de capacidade): 0;
--     · agenda_resolver_pessoa: "o Alex não vem amanhã" respondia "Não conheço ninguém chamado Alex na equipe."
--   E a revisão do lote (20261030100500) criou a pergunta equipe_sem_dias pedindo ao dono "o valor da diária para eu
--   cadastrar" — errado: work_profiles é o pagamento das diárias (Jornada e Diárias), o Alex trabalha todo dia útil e
--   pode nem ser diarista, e a agenda não deve depender do valor da diária para saber quem é da equipe.
--
-- ═══ A REGRA NOVA (uma só, nas 4) ═══
--   É da equipe a pessoa ativa, prestador, diarista ou funcionário, que tem a diária cadastrada vigente em p_hoje
--   (work_profiles, como antes) OU que o dono declarou (alguma linha vigente de agenda_disponibilidade com origem dono:
--   substituida_em nulo, de qualquer situação). Só no agenda_resolver_pessoa, também quem está na lista da rotina sem
--   ter parado (agenda_equipe_contato, parou_em nulo), para o dono poder falar de alguém da lista antes de dar os dias.
--   agenda_capacidade e agenda_capacidade_semanal continuam exigindo a disponibilidade em vigor, como antes. O sócio (o
--   dono) continua como estava. Quem tem a diária cadastrada continua na equipe como antes (no resolver, sem filtro de
--   tipo nesse caminho, como antes).
--   _agenda_vigia_equipe_sem_dias: quem é dito pelo nome passa a ser quem tem dias na agenda mas fica fora pela regra
--   nova (só dias de outra origem, como a semente do histórico, o assistente ou o técnico, e sem a diária: na prática,
--   quase nunca), e o texto pergunta os dias, não a diária: "Alex tem dias na agenda, mas não está na equipe. Se for,
--   me diga em que dias vem. Por exemplo: "Alex vem de segunda a sexta"." Sem ninguém assim, como antes: "Quem vem e
--   em que dias da semana?". _agenda_equipe_tem_dias (lê agenda_capacidade) ganha só o comentário novo.
--   Não muda: quem tem work_profiles e disponibilidade (a equipe de antes), o dono, o motor, a vigia fora deste passo,
--   o pagamento das diárias, a rotina da equipe (agenda_equipe_contato), a tela.
--
-- ═══ O QUE ESTA CORREÇÃO NÃO RESOLVE (medido na bancada, o cenário de produção de 30/10) ═══
--   Com ela o Alex entra (5 diárias por semana, 4 comprometíveis), mas o motor ainda não marca nada: as OS que esperam
--   uma reserva (Lenine e Giancarlo, "tem peça a comprar?") têm a estimativa pelo valor "com 2 pessoas"
--   (agenda_config.equipe_sugerida = 2), e uma pessoa só não cobre o meio-dia de 2 ("sem lugar para a reserva nesta
--   semana"); o resto espera material, cliente, sinal ou a resposta do dono. O dono não entra como o 2º técnico. Destrava
--   com a equipe dita por OS ("Lenine com o Alex") ou com mais gente na equipe.
--
-- Ordem de ligar: depois da 20261030100500 (a revisão do lote, que cria _agenda_vigia_equipe_sem_dias). Sem deploy de
-- edge function (nenhum TS mudou). Aplicar com o OK nomeado do dono. Prova: supabase/tests/agenda_correcao_2910_equipe.sql
-- (bancada).
--
-- DESFAZER: recriar as 4 funções com o corpo e o comentário da migration de origem de cada uma (acima:
--   agenda_capacidade, agenda_capacidade_semanal e agenda_resolver_pessoa de 20261024160400;
--   _agenda_vigia_equipe_sem_dias de 20261030100500) e devolver o comentário de _agenda_equipe_tem_dias (o de
--   20261030100500). As portas não mudam.
--
-- IDEMPOTENTE: create or replace function, comment, revoke e grant.

-- ── 1. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- CORREÇÃO 30/10 (equipe):") ──────
-- Fora dos blocos nenhuma linha muda; as linhas trocadas ficam no bloco como "-- antes: …" (o K de
-- supabase/tests/agenda_correcao_2910_equipe.sql confere). Quem recriar de novo qualquer uma delas copia DESTA migration.

-- agenda_capacidade (de 20261024160400_agenda_fase1_prontidao.sql)
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
  )
  select r.id, r.nome, r.dono, r.dia, r.turno,
         case
           when r.ei_id is not null then 'indisponivel'
           when r.ed_id is not null then 'livre'
           when r.rc_id is not null then 'indisponivel'
           when r.dow = 7 or (r.dow = 6 and not c.sabado_util) then 'fim_de_semana'
           when r.feriado is not null then 'feriado'
           when r.pi_id is not null then 'indisponivel'
           when r.pd_id is not null then 'livre'
           else 'sem_padrao' end,
         case
           when r.ei_id is not null then 0::numeric
           when r.ed_id is not null then 1::numeric
           when r.rc_id is not null or r.dow = 7 or (r.dow = 6 and not c.sabado_util) or r.feriado is not null
                or r.pi_id is not null then 0::numeric
           when r.pd_id is not null then case when r.pd_origem = 'historico' then coalesce(r.pd_freq, 0) else 1::numeric end
           else 0::numeric end,
         case
           when r.ei_id is not null then r.ei_origem
           when r.ed_id is not null then r.ed_origem
           when r.rc_id is not null or r.dow = 7 or (r.dow = 6 and not c.sabado_util) or r.feriado is not null then null
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
           when r.pi_id is not null then coalesce(r.pi_nota, 'não vem neste turno')
           when r.pd_id is not null then r.pd_nota
           when r.dono then 'você ainda não disse quais dias fica em campo'
           else 'sem padrão' end
    from regra r
   order by r.dono desc, r.nome, r.id, r.dia, r.ord;
end;
$function$;

comment on function public.agenda_capacidade(date, date, date) is
  'Agenda de Produção (Fase 1, P3): a grade por pessoa × dia × turno (manhã, tarde) — o dono e a equipe (diarista com cadastro vigente e disponibilidade em vigor). situacao: indisponivel (exceção da pessoa, recesso ou padrão "não vem neste turno"), livre (exceção "vem"/confirmada = 1 meio-dia; padrão do histórico = a frequência; padrão do dono = 1), fim_de_semana (domingo; sábado só por exceção, salvo agenda_config.sabado_util), feriado (o nome), sem_padrao. A exceção da pessoa vence o calendário; exceção indisponível > confirmada > disponível > padrão; o mais novo vence o empate. CORREÇÃO 30/10 (equipe): a equipe é quem está ativo (prestador, diarista ou funcionário), com disponibilidade em vigor e com a diária cadastrada vigente OU alguma linha vigente que o dono declarou (agenda_disponibilidade, origem dono): a diária cadastrada é do pagamento, não decide quem é da equipe.';

-- agenda_capacidade_semanal (de 20261024160400_agenda_fase1_prontidao.sql)
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
  'Agenda de Produção (Fase 1, P3): o ÚNICO número de capacidade — diarias_semana = Σ, por pessoa com padrão, dos meios-dias esperados da semana típica ÷ 2 (padrão do histórico = a frequência; do dono = 1; "não vem neste turno" = 0); comprometivel = diarias_semana × agenda_config.carga_max. O dono só entra quando tem padrão (conta_dono). Também: a última diária lançada, os dias úteis sem lançar e o aviso quando passam de 1. CORREÇÃO 30/10 (equipe): conta, além do dono com padrão, quem está ativo (prestador, diarista ou funcionário), tem padrão em vigor e tem a diária cadastrada vigente OU alguma linha vigente que o dono declarou (agenda_disponibilidade, origem dono) — a régua de agenda_capacidade.';

-- agenda_resolver_pessoa (de 20261024160400_agenda_fase1_prontidao.sql)
create or replace function public.agenda_resolver_pessoa(p_ref text, p_autor uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_ref    text := btrim(coalesce(p_ref, ''));
  v_norm   text := public._agenda_normal(p_ref);
  v_tokens text[];
  v_dono   uuid;
  v_n      int;
  v_achados jsonb;
  v_um     jsonb;
  v_opcoes text[];
  c_vazias constant text[] := array['o', 'a', 'do', 'da', 'de', 'com', 'e', 'seu', 'sua', 'sr', 'senhor', 'tecnico'];
begin
  if v_ref = '' then
    return jsonb_build_object('status', 'nao_achei', 'texto', 'Diga quem: "eu" ou o nome (por exemplo, Roberto).');
  end if;

  -- O sócio do login; sem ligação, o único sócio ativo.
  v_dono := coalesce(
    (select p.id from public.payees p
      where p_autor is not null and p.active and p.kind = 'socio' and p.app_user_id = p_autor
      order by p.created_at, p.id limit 1),
    (select min(p.id::text)::uuid from public.payees p where p.active and p.kind = 'socio' having count(*) = 1));

  if v_norm in ('eu', 'mim', 'comigo', 'voce', 'vc', 'eu mesmo', 'so eu', 'o dono', 'dono') then
    if v_dono is null then
      if exists (select 1 from public.payees p where p.active and p.kind = 'socio') then
        return jsonb_build_object('status', 'ambiguo',
          'texto', format('Qual sócio: %s?', public._agenda_lista(array(
            select public._agenda_nome_curto(p.name) from public.payees p
             where p.active and p.kind = 'socio' order by p.name, p.id), null)));
      end if;
      return jsonb_build_object('status', 'nao_achei', 'texto', 'Não achei você no cadastro de pessoas (sócio).');
    end if;
    return (select jsonb_build_object('status', 'ok', 'payee_id', p.id, 'nome_curto', public._agenda_nome_curto(p.name),
                                      'eh_dono', true, 'texto', 'você')
              from public.payees p where p.id = v_dono);
  end if;

  v_tokens := array(select t from unnest(string_to_array(v_norm, ' ')) with ordinality u(t, o)
                     where length(t) >= 2 and t <> all (c_vazias) order by o);
  if cardinality(v_tokens) = 0 then
    return jsonb_build_object('status', 'nao_achei', 'texto', format('Não conheço ninguém chamado %s na equipe.', v_ref));
  end if;

  -- CORREÇÃO 30/10 (equipe): o comentário diz a régua nova.
  -- antes: -- A equipe (cadastro de diarista vigente em p_hoje) e os sócios, pelo nome sem acento: todo token começa uma
  -- A equipe (a régua abaixo) e os sócios, pelo nome sem acento: todo token começa uma
  -- CORREÇÃO 30/10 (equipe): fim
  -- palavra do nome. O 1º nome igual vence o "começa com" ("Rob" acha o Roberto; "Roberto" acha só os Robertos).
  with gente as (
    select p.id, p.name, p.kind = 'socio' as socio,
           string_to_array(public._agenda_normal(p.name), ' ') as palavras
      from public.payees p
     where p.active
       and (p.kind = 'socio'
            -- CORREÇÃO 30/10 (equipe): além de quem tem a diária cadastrada vigente, quem o dono declarou (linha
            -- vigente de agenda_disponibilidade com origem dono) e quem está na lista da rotina sem ter
            -- parado (agenda_equipe_contato, parou_em nulo), para o dono poder falar de alguém da lista
            -- antes de dar os dias. Sem isso, "o Alex não vem amanhã" (o Alex sem work_profiles)
            -- respondia "Não conheço ninguém chamado Alex na equipe."
            -- antes: or exists (select 1 from public.work_profiles w
            -- antes:             where w.payee_id = p.id and w.vigencia_inicio <= p_hoje
            -- antes:               and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje)))
            or exists (select 1 from public.work_profiles w
                        where w.payee_id = p.id and w.vigencia_inicio <= p_hoje
                          and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje))
            or (p.kind in ('prestador', 'diarista', 'funcionario')
                and (exists (select 1 from public.agenda_disponibilidade d
                              where d.payee_id = p.id and d.substituida_em is null and d.origem = 'dono')
                     or exists (select 1 from public.agenda_equipe_contato c
                                 where c.payee_id = p.id and c.parou_em is null))))
            -- CORREÇÃO 30/10 (equipe): fim
  ),
  casam as (
    select g.*, g.palavras[1] = v_tokens[1] as exato from gente g
     where not exists (select 1 from unnest(v_tokens) t
                        where not exists (select 1 from unnest(g.palavras) w where w like t || '%'))
  ),
  melhor as (
    select c.* from casam c where c.exato or not exists (select 1 from casam x where x.exato)
  )
  select coalesce(jsonb_agg(jsonb_build_object('payee_id', m.id, 'nome', m.name,
                                               'nome_curto', public._agenda_nome_curto(m.name),
                                               'eh_dono', m.id is not distinct from v_dono)
                            order by m.name, m.id), '[]'::jsonb), count(*)
    into v_achados, v_n
    from melhor m;

  if v_n = 0 then
    return jsonb_build_object('status', 'nao_achei', 'texto', format('Não conheço ninguém chamado %s na equipe.', v_ref));
  end if;
  if v_n > 1 then
    v_opcoes := array(select e ->> 'nome' from jsonb_array_elements(v_achados) e);
    return jsonb_build_object('status', 'ambiguo', 'opcoes', v_achados,
      'texto', format('Qual %s: %s ou %s?', v_ref,
                      array_to_string(v_opcoes[1:cardinality(v_opcoes) - 1], ', '), v_opcoes[cardinality(v_opcoes)]));
  end if;
  v_um := v_achados -> 0;
  return jsonb_build_object('status', 'ok', 'payee_id', v_um ->> 'payee_id', 'nome_curto', v_um ->> 'nome_curto',
    'eh_dono', (v_um ->> 'eh_dono')::boolean,
    'texto', case when (v_um ->> 'eh_dono')::boolean then 'você' else v_um ->> 'nome_curto' end);
end;
$function$;

comment on function public.agenda_resolver_pessoa(text, uuid, date) is
  'Agenda de Produção (Fase 1, P3): quem o dono quis dizer. "eu", "mim", "comigo", "você" e o nome do sócio → o sócio ligado ao login (p_autor), senão o único sócio ativo; a equipe (cadastro de diarista vigente em p_hoje) pelo nome sem acento (o 1º nome igual vence o "começa com"). Devolve {status ok|ambiguo|nao_achei, payee_id, nome_curto, eh_dono, texto}. CORREÇÃO 30/10 (equipe): a equipe é quem tem a diária cadastrada vigente OU, sendo prestador, diarista ou funcionário ativo, alguma linha vigente que o dono declarou (agenda_disponibilidade, origem dono) ou está na lista da rotina sem ter parado (agenda_equipe_contato, parou_em nulo).';

-- _agenda_vigia_equipe_sem_dias (de 20261030100500_agenda_correcao_revisao.sql)
create or replace function public._agenda_vigia_equipe_sem_dias(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_seg   date := p_hoje - (extract(isodow from p_hoje)::int - 1);
  v_chave text;
  v_n     int;
  v_sem   text[];
  v_txt   text;
  v_perda date;
  v_saiu  boolean;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_vigia_equipe_sem_dias: sem o dia ou a hora' using errcode = '22004';
  end if;
  if cf.modo_vigia not in ('sombra', 'ligado') then
    return jsonb_build_object('criada', false, 'motivo', 'a vigia está desligada');
  end if;
  v_chave := 'equipe_sem_dias:' || v_seg;
  if exists (select 1 from public.agenda_perguntas q where q.chave = v_chave and q.modo = cf.modo_vigia) then
    return jsonb_build_object('criada', false, 'motivo', 'já perguntei nesta semana');
  end if;
  select count(*)::int into v_n from public.os_carteira(p_hoje);
  if v_n = 0 then
    return jsonb_build_object('criada', false, 'motivo', 'nenhum serviço esperando');
  end if;
  if public._agenda_equipe_tem_dias(p_hoje) then
    return jsonb_build_object('criada', false, 'motivo', 'a equipe tem dias');
  end if;
  -- CORREÇÃO 30/10 (equipe): o comentário diz a régua nova.
  -- antes: -- quem tem os dias na agenda mas não tem a diária cadastrada vigente (a régua de agenda_capacidade)
  -- quem tem os dias na agenda mas fica fora da equipe (a régua de agenda_capacidade)
  -- CORREÇÃO 30/10 (equipe): fim
  v_sem := array(select public._agenda_nome_curto(py.name)
                   from public.payees py
                  where py.active and py.kind in ('prestador', 'diarista', 'funcionario')
                    and exists (select 1 from public.agenda_disponibilidade d
                                 where d.payee_id = py.id and d.substituida_em is null
                                   and d.situacao in ('disponivel', 'confirmada'))
                    and not exists (select 1 from public.work_profiles w
                                     where w.payee_id = py.id and w.vigencia_inicio <= p_hoje
                                       and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje))
                    -- CORREÇÃO 30/10 (equipe): nem o dono a declarou (linha vigente de
                    -- agenda_disponibilidade com origem dono): quem ele declarou é da equipe
                    -- (agenda_capacidade), com ou sem a diária cadastrada. Sobra quem só tem dias de outra
                    -- origem (a semente do histórico, o assistente, o próprio técnico) e nem a diária: na
                    -- prática, quase nunca.
                    and not exists (select 1 from public.agenda_disponibilidade d
                                     where d.payee_id = py.id and d.substituida_em is null and d.origem = 'dono')
                    -- CORREÇÃO 30/10 (equipe): fim
                  order by py.name, py.id);
  v_txt := case when v_n = 1 then 'Não consigo marcar o serviço que espera: ninguém da equipe tem dias na agenda.'
                else format('Não consigo marcar nenhum dos %s serviços que esperam: ninguém da equipe tem dias na agenda.', v_n) end
           || case
                when cardinality(v_sem) = 1 then
                  -- CORREÇÃO 30/10 (equipe): o texto não pede a diária (ela é do
                  -- pagamento): pergunta os dias, que é o que põe a pessoa na equipe.
                  -- antes: format(' %s tem dias na agenda, mas não tem a diária cadastrada, e sem ela não entra na conta. Me diga o valor da diária para eu cadastrar.', v_sem[1])
                  format(' %s tem dias na agenda, mas não está na equipe. Se for, me diga em que dias vem. Por exemplo: "%s vem de segunda a sexta".', v_sem[1], v_sem[1])
                  -- CORREÇÃO 30/10 (equipe): fim
                when cardinality(v_sem) > 1 then
                  -- CORREÇÃO 30/10 (equipe): o mesmo, para mais de uma pessoa.
                  -- antes: format(' %s têm dias na agenda, mas não têm a diária cadastrada, e sem ela não entram na conta. Me diga o valor da diária de cada um para eu cadastrar.',
                  -- antes:        public._agenda_lista(v_sem, 3))
                  format(' %s têm dias na agenda, mas não estão na equipe. Se forem, me diga em que dias cada um vem. Por exemplo: "%s vem de segunda a sexta".',
                         public._agenda_lista(v_sem, 3), v_sem[1])
                  -- CORREÇÃO 30/10 (equipe): fim
                else ' Quem vem e em que dias da semana?' end;
  v_perda := v_seg + (cf.dia_do_plano - 1);
  if v_perda < p_hoje then
    v_perda := v_perda + 7;
  end if;
  v_saiu := public._agenda_vigia_perguntar('equipe_sem_dias', v_chave, null, null, null, v_perda, v_txt, cf.modo_vigia,
                                           p_agora, true);
  if v_saiu then
    update public.agenda_perguntas q set expira_em = (v_seg + 7)::timestamp at time zone 'America/Sao_Paulo'
     where q.chave = v_chave and q.modo = cf.modo_vigia and q.estado = 'aberta' and q.expira_em is null;
  end if;
  return jsonb_build_object('criada', v_saiu, 'motivo', 'ninguém da equipe tem dias', 'servicos', v_n,
                            'sem_diaria', to_jsonb(v_sem));
end;
$function$;

comment on function public._agenda_vigia_equipe_sem_dias(date, timestamptz) is
  'Agenda de Produção (correção de 29/10, revisão do lote): passo da vigia (agenda_vigiar, depois dos outros). Com serviço esperando (os_carteira) e ninguém da equipe com dias na agenda (_agenda_equipe_tem_dias), pergunta uma vez por semana (equipe_sem_dias:<a segunda>, modo_vigia, não crítica, perda_em = o próximo dia do plano, vence na segunda seguinte): "Não consigo marcar nenhum dos 11 serviços que esperam: ninguém da equipe tem dias na agenda. Alex tem dias na agenda, mas não tem a diária cadastrada, e sem ela não entra na conta. Me diga o valor da diária para eu cadastrar." (sem ninguém assim: "Quem vem e em que dias da semana?"). {criada, motivo, servicos?, sem_diaria?}. A limpeza a resolve quando a equipe volta a ter dias. CORREÇÃO 30/10 (equipe): quem é dito pelo nome é quem tem dias na agenda mas fica fora da equipe pela régua de agenda_capacidade (sem a diária cadastrada vigente e sem nenhuma linha vigente que o dono declarou), e o texto pergunta os dias, não a diária: "… Alex tem dias na agenda, mas não está na equipe. Se for, me diga em que dias vem. Por exemplo: "Alex vem de segunda a sexta"." O resto como acima (sem_diaria guarda os nomes).';

-- ── 2. _agenda_equipe_tem_dias: o corpo não muda (lê agenda_capacidade, que mudou acima); o comentário, sim ─────────
comment on function public._agenda_equipe_tem_dias(date) is
  'Agenda de Produção (correção de 29/10, revisão do lote): alguém da equipe, sem o dono, tem meio-dia esperado (agenda_capacidade: quem tem a diária cadastrada vigente ou o dono declarou, e os dias na agenda; CORREÇÃO 30/10 (equipe): antes, só a diária cadastrada) do 1º dia que a agenda ainda pode mudar (o dia útil depois do congelado) até horizonte_semanas depois? A pergunta equipe_sem_dias nasce quando não (_agenda_vigia_equipe_sem_dias) e resolve quando sim (_agenda_vigia_limpeza).';

-- ── Portas (as de antes; create or replace não mexe em grant, e repetir não custa) ───────────────────────────────────
-- As 3 leituras da Fase 1: security invoker (a RLS de quem lê vale), sem anon, para authenticated e service_role.
revoke all on function
  public.agenda_capacidade(date, date, date), public.agenda_capacidade_semanal(date),
  public.agenda_resolver_pessoa(text, uuid, date)
  from public, anon;
grant execute on function
  public.agenda_capacidade(date, date, date), public.agenda_capacidade_semanal(date),
  public.agenda_resolver_pessoa(text, uuid, date)
  to authenticated, service_role;
-- O passo da vigia é peça de dentro (só a agenda_vigiar, definer, o chama): ninguém de fora, nem o service_role.
revoke all on function public._agenda_vigia_equipe_sem_dias(date, timestamptz)
  from public, anon, authenticated, service_role;

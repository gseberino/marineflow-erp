-- Agenda de Produção, Fase 2 ("O gestor de agenda"), pacote P5: o que o dono LÊ passa a refletir o plano — o dia, o
-- fechamento, a conversa e o conflito de agenda.
-- Spec: scratchpad agenda-pesquisa/spec-fase2.md (§9, §11, §13; §3.1, §3.3 d18–d20). Decisões 23/10 (Autonomia).
-- Depende de 20261025100000..100400 (tabelas, porta, motor, conferência e vigia, rascunho) e da Fase 1 inteira.
--
-- ═══ DDL — OK NOMEADO ═══ (uma view e funções; nenhuma tabela, nenhum gatilho, nenhum dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: com a agenda automática ligada (modo_proposta = 'ligado') a OS passa a ter dias e meios-dias no plano
-- (agenda_alocacoes), e a janela antiga (scheduled_*) vira só o espelho. Tudo o que o dono lê — o "Hoje" da manhã, o
-- "Amanhã" e as linhas da agenda no fechamento das 17:30, a agenda_ver da conversa, o dia de uma pessoa, a my_agenda,
-- o panorama e o conflito de agenda da tela — tem de dizer o que o PLANO diz: quem vai, em que meio-dia, o dia n de N.
-- Fora de 'ligado' (desligado e sombra, como nasce) nada muda para ninguém.
--
-- O QUE MUDA:
--   1. v_agenda_dia (security_invoker = on): uma linha por dia e OS do plano vigente — o 1º início, quem vai (com os
--      turnos e a presença do dono), o dia n de N, a reserva com a condição, fixada, o cliente confirmou, o local. Quem
--      lê vê pela RLS de agenda_alocacoes (administrador e financeiro tudo; o técnico, o próprio payee); o nome da pessoa
--      vem de _agenda_pessoa (payees é fechada para o técnico).
--   2. agenda_linhas_do_dia(p_dia, p_max, p_hoje): o texto pronto de cada OS do dia para o "Hoje" e o "Amanhã" ("Lenine
--      (OS-00074), dia 1 de 2: você abre, Roberto o dia todo, João à tarde"; "Reserva: Caio (OS-00203), se …"), cortado em
--      p_max sem cortar no meio da palavra.
--   3. _agenda_marcados recriada (corpo de 160500, mudança marcada "-- FASE 2:"): em 'ligado' a OS marcada sai do plano
--      (os dias de verdade, com quem vai), não da janela antiga. Com isso agenda_semana, agenda_o_que_fazer, o dia do
--      dono (agenda hoje/amanhã) e a cauda do "Amanhã" do fechamento leem o publicado.
--   4. agenda_dia_da_pessoa recriada: em 'ligado' o dia da pessoa sai das alocações, com ou sem login (o Roberto não tem).
--   5. agenda_ver recriada (mesma assinatura): focos novos decisoes (as decisões numeradas por agenda_decisoes_abertas,
--      depois o que mais a agenda quer saber), mudancas (o que mudou sozinha desde ontem, com *desfaz <nome>*; em sombra
--      "Em teste (nada foi mudado)") e plano (o publicado do período, dia a dia, com quem vai; as montadas e não
--      publicadas numeradas por agenda_propostas_abertas; em sombra "Em teste: eu montaria assim").
--   6. agenda_textos_do_fechamento recriada (mesma assinatura): ganha linhas [{tipo, texto, perda, pergunta_id, acao_ids,
--      modo}] (decisao, dia, semana, mudancas, pergunta), na ordem da perda; com modo_proposta 'ligado' a projeção da
--      semana que vem (Fase 1) sai vazia: a linha semana do publicado a substitui.
--   7. agenda_estado_das_os(p_hoje): para o secretário — por OS da carteira, o estado, programada, fixada, o próximo
--      dia, parada e o que falta comprar até quando.
--   8. get_agenda_conflicts recriada (MESMA assinatura e ACL): a OS com alocação vigente ocupa só os turnos dela (não a
--      janela corrida); o ramo novo 'alocacao' mostra os meios-dias do payee ligado ao login em OS em que ele não é
--      técnico (é como o dono aparece: pelo payee sócio).
--   Auxiliares: _agenda_pessoa (nome curto e "é o dono", só para quem pode ver), _agenda_payees_do_usuario,
--   _agenda_pessoas_do_dia ("você abre, Roberto o dia todo"), _agenda_ver_decisoes, _agenda_ver_mudancas,
--   _agenda_ver_plano, _agenda_mudancas (o que a agenda mudou sozinha numa janela de dias), _agenda_linhas_do_fechamento.
--
-- CORREÇÕES SOBRE A SPEC (o teste fixa o que estas funções devolvem, byte a byte, com a fixture publicada):
--   · Quem vai, nas linhas do dia, é a frase do motor ("você abre, Roberto o dia todo, João à tarde"; o turno só aparece
--     quando a pessoa não está em todos os meios-dias da OS no dia), separada por vírgula: com o ";" da amostra
--     ("você abre; Roberto (dia) e João (tarde)"), a lista de OS do "Hoje" (que o secretário junta com ";") ficaria
--     ambígua.
--   · O corte em p_max tira primeiro as pessoas do fim ("…"), depois todas, depois encurta o nome do cliente; o número
--     da OS e o "dia n de N" nunca saem. A amostra dizia "o nome da unidade encurta primeiro", herdado do "Hoje" da Fase
--     0 (que mostrava o barco): a linha do plano não traz a unidade.
--   · Sem artigo antes do nome (o banco não sabe se é "o" ou "a", como no P3): "Qua 04/11, Roberto tem Vanderlei
--     (OS-00069) o dia todo (com você abrindo e fechando)." em vez de "o Roberto está no Vanderlei".
--   · agenda_ver e agenda_textos_do_fechamento mantêm as assinaturas (o PostgREST não escolheria entre duas). A janela
--     das mudanças é por dia (agenda_acoes.dia): na agenda_ver, ontem e hoje; no fechamento, o que ainda não foi contado
--     nos últimos 7 dias (o fechamento que não saiu, ou que não teve vaga, não perde a mudança). A hora (desfazer ainda
--     vale?) é now(); a bancada a fixa com set_config('agenda.agora', …, true), como o *grava* do P4.
--   · As linhas da agenda no fechamento existem com modo_leitura em sombra ou ligado (como o resto da agenda): com a
--     leitura desligada a agenda inteira cala, e a ordem de ligar (§16) liga a leitura antes da Fase 2.
--   · A decisão crítica aparece em todo fechamento até ser respondida (o perguntas_vezes_max vale só para as perguntas de
--     fato: chegou?, parada?, o que falta?, quantos dias?). Uma decisão que o dono não viu fica parada.
--   · O "Mudei sozinho" do fechamento conta só o que a agenda fez sozinha (motor e vigia), sem o status que acompanha a
--     publicação ou o replano da mesma OS no mesmo dia (vai junto, no acao_ids, para ficar contado): o que o dono pediu
--     (palavra, *grava*, tela) ele já sabe.
--   · Na linha da semana, o "Fora:" lista só o que estava pronto e não entrou (não cabe, começa depois, sem encaixe):
--     esperando o cliente, o sinal ou a conversão já aparecem em *agenda*, e a linha caberia mal no fechamento.
--   · v_agenda_dia ganha reserva_de e ultimo_fim (a reserva no pátio e o fim do dia para o conflito); o dia n de N do
--     técnico conta os dias dele na OS (a RLS só mostra as alocações dele).
--   · get_agenda_conflicts: a OS com alocação vigente ocupa os períodos das alocações dela (todas as pessoas, sem
--     repetir o mesmo período), não os da pessoa só — quem é técnico da OS conta como ocupado nos turnos dela, como antes
--     contava a janela inteira.
--
-- O QUE NÃO MUDA: nenhuma tabela, nenhum dado; o motor, a porta, a vigia e o rascunho (P1–P4); fora de 'ligado' todas
-- as leituras saem byte a byte como na Fase 1 (agenda_fase1_leituras.sql continua passando).
--
-- ORDEM DE LIGAR: depois de 20261025100400; antes do ai-daily-briefing, do ai-agent e do erp-mcp do P5 (o secretário,
-- a my_agenda, o panorama e as palavras chamam as funções daqui). get_agenda_conflicts tem a mesma assinatura: a tela de
-- hoje continua funcionando com ela.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase2_leituras.sql (begin/rollback; a carteira de 29/10 publicada
-- pela vigia: os textos byte a byte, a view com a RLS do técnico e do financeiro, o conflito por turno, o ramo do dono,
-- o determinismo, os focos novos, o fechamento em ligado e em sombra, o estado das OS e as portas). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261025100500
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261025100500_agenda_fase2_leituras.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261025100500', 'agenda_fase2_leituras');"
--
-- IDEMPOTENTE: create or replace view/function, revoke/grant e comment.

-- ── 0. Quem é a pessoa (para quem lê pela view) ─────────────────────────────────────────────────────────

-- O nome curto e "é o dono" de um payee — só para quem pode ver (sem login: service_role; administrador ou financeiro;
-- o próprio payee do login). payees tem RLS só para administrador e financeiro: sem esta função o técnico leria a
-- própria alocação sem o próprio nome.
create or replace function public._agenda_pessoa(p_payee uuid)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  select case when auth.uid() is null or public.is_admin_or_financial(auth.uid())
                   or p_payee = any (public._agenda_payees_do_login())
              then jsonb_build_object('nome', public._agenda_nome_curto(p.name),
                                      'eh_dono', p.id is not distinct from public._agenda_dono(null) or p.kind = 'socio')
              else jsonb_build_object('nome', null, 'eh_dono', false) end
    from public.payees p
   where p.id = p_payee;
$function$;

comment on function public._agenda_pessoa(uuid) is
  'Agenda de Produção (Fase 2, P5): {nome (curto), eh_dono} do payee — só para quem pode ver (sem login, administrador ou financeiro, ou o próprio payee do login); senão {nome: null, eh_dono: false}. A view v_agenda_dia lê o nome por aqui porque payees é fechada para o técnico.';

-- Os payees ativos ligados a um login (p_user), para quem pode saber: sem login, o próprio login, administrador ou
-- financeiro. O conflito de agenda e o "o que o Roberto faz" chegam à pessoa pelo payee (com ou sem login).
create or replace function public._agenda_payees_do_usuario(p_user uuid)
 returns uuid[]
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  select coalesce(array_agg(p.id order by p.id), '{}'::uuid[])
    from public.payees p
   where p_user is not null and p.app_user_id = p_user and p.active
     and (auth.uid() is null or auth.uid() = p_user or public.is_admin_or_financial(auth.uid()));
$function$;

comment on function public._agenda_payees_do_usuario(uuid) is
  'Agenda de Produção (Fase 2, P5): os payees ativos ligados ao login p_user — só para quem pode saber (sem login, o próprio, administrador ou financeiro); senão vazio.';

-- ── 1. O plano por dia ──────────────────────────────────────────────────────────────────────────────────

create or replace view public.v_agenda_dia
with (security_invoker = on) as
with
a as (
  select x.* from public.agenda_alocacoes x where x.estado in ('publicada', 'fixada')
),
dias as (
  select d.service_order_id, d.dia,
         (row_number() over (partition by d.service_order_id order by d.dia))::int as dia_n,
         (count(*) over (partition by d.service_order_id))::int as dias_total
    from (select distinct a.service_order_id, a.dia from a where a.tipo <> 'reserva') d
),
pp as (
  select a.dia, a.service_order_id, a.payee_id,
         array_agg(distinct a.turno order by a.turno) as turnos,
         case when bool_or(a.presenca = 'turno') then 'turno'
              when bool_or(a.presenca = 'abertura') and bool_or(a.presenca = 'fechamento') then 'abre_e_fecha'
              when bool_or(a.presenca = 'abertura') then 'abertura'
              else 'fechamento' end as presenca,
         min(lower(a.periodo)) as ini
    from a
   group by a.dia, a.service_order_id, a.payee_id
),
pe as (
  select pp.dia, pp.service_order_id,
         jsonb_agg(jsonb_build_object('payee_id', pp.payee_id, 'nome', x.j ->> 'nome',
                                      'eh_dono', coalesce((x.j ->> 'eh_dono')::boolean, false),
                                      'turnos', to_jsonb(pp.turnos), 'presenca', pp.presenca)
                   order by coalesce((x.j ->> 'eh_dono')::boolean, false) desc, pp.ini, x.j ->> 'nome', pp.payee_id) as pessoas
    from pp
   cross join lateral (select public._agenda_pessoa(pp.payee_id) as j) x
   group by pp.dia, pp.service_order_id
),
g as (
  select a.dia, a.service_order_id,
         bool_and(a.tipo = 'reserva') as reserva,
         case when bool_and(a.tipo = 'reserva') then 'reserva' else min(a.tipo) filter (where a.tipo <> 'reserva') end as tipo,
         min(a.reserva_de) filter (where a.tipo = 'reserva') as reserva_de,
         min(a.condicao) filter (where a.tipo = 'reserva') as condicao,
         min(a.condicao_ate) filter (where a.tipo = 'reserva') as condicao_ate,
         min(lower(a.periodo)) as primeiro_inicio,
         max(upper(a.periodo)) as ultimo_fim,
         bool_or(a.estado = 'fixada') as fixada
    from a
   group by a.dia, a.service_order_id
)
select g.dia, g.service_order_id, so.service_order_number as numero, public._agenda_nome_curto(cl.name) as cliente_curto,
       v.name as unidade, g.tipo, g.reserva, g.reserva_de, g.condicao, g.condicao_ate, g.primeiro_inicio, g.ultimo_fim,
       coalesce(pe.pessoas, '[]'::jsonb) as pessoas, d.dia_n, d.dias_total, g.fixada,
       coalesce((so.client_confirmed_for at time zone 'America/Sao_Paulo')::date = g.dia, false) as confirmado_cliente,
       coalesce(m.name, nullif(btrim(cl.city), '')) as local
  from g
  join public.service_orders so on so.id = g.service_order_id
  left join public.clients cl on cl.id = so.client_id
  left join public.vessels v on v.id = so.vessel_id
  left join public.marinas m on m.id = so.marina_id
  left join pe on pe.dia = g.dia and pe.service_order_id = g.service_order_id
  left join dias d on d.service_order_id = g.service_order_id and d.dia = g.dia;

comment on view public.v_agenda_dia is
  'Agenda de Produção (Fase 2, P5): o plano vigente (publicada/fixada) por dia e OS — numero, cliente_curto, unidade, tipo (execucao, diagnostico… ou reserva), reserva (o dia só tem reserva), reserva_de, condicao/condicao_ate (da reserva), primeiro_inicio e ultimo_fim, pessoas [{payee_id, nome, eh_dono, turnos, presenca (turno|abertura|fechamento|abre_e_fecha)}] (o dono primeiro), dia_n/dias_total (dias distintos com alocação que não é reserva), fixada, confirmado_cliente (client_confirmed_for no dia), local (marina, senão a cidade do cliente). security_invoker: a RLS de agenda_alocacoes de quem lê vale (o técnico vê só o próprio payee, e o dia n de N dele).';

-- "você abre, Roberto o dia todo, João à tarde": quem vai num dia de uma OS (as pessoas de v_agenda_dia). O turno só
-- aparece quando a pessoa não está em todos os meios-dias da OS no dia.
create or replace function public._agenda_pessoas_do_dia(p_pessoas jsonb)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_turnos text[];
  v_partes text[] := '{}';
  e        jsonb;
  v_t      text[];
  v_rel    text;
begin
  v_turnos := array(select distinct x from jsonb_array_elements(coalesce(p_pessoas, '[]'::jsonb)) p,
                                           jsonb_array_elements_text(p -> 'turnos') x
                     where p ->> 'presenca' = 'turno' order by x);
  for e in select x from jsonb_array_elements(coalesce(p_pessoas, '[]'::jsonb)) x loop
    v_t := array(select y from jsonb_array_elements_text(e -> 'turnos') y order by y);
    v_rel := case when v_t @> v_turnos and v_turnos @> v_t then case when cardinality(v_turnos) = 2 then ' o dia todo' else '' end
                  when v_t = array['manha'] then ' de manhã'
                  when v_t = array['tarde'] then ' à tarde'
                  else ' o dia todo' end;
    if coalesce((e ->> 'eh_dono')::boolean, false) then
      v_partes := v_partes || case e ->> 'presenca'
        when 'abertura' then 'você abre'
        when 'fechamento' then 'você fecha'
        when 'abre_e_fecha' then 'você abre e fecha'
        else 'você' || v_rel end;
    else
      v_partes := v_partes || (coalesce(e ->> 'nome', 'alguém da equipe') || v_rel);
    end if;
  end loop;
  return array_to_string(v_partes, ', ');
end;
$function$;

comment on function public._agenda_pessoas_do_dia(jsonb) is
  'Agenda de Produção (Fase 2, P5): quem vai num dia de uma OS (as pessoas de v_agenda_dia) — "você abre, Roberto o dia todo, João à tarde"; o turno só quando a pessoa não está em todos os meios-dias da OS no dia.';

-- As linhas do dia para o "Hoje" (manhã) e o "Amanhã" (fechamento): [{hora, texto, ord, os, numero, reserva, dia_n,
-- dias_total}] na ordem do 1º início. ord = o 1º início em UTC (o secretário ordena junto das tarefas pelo texto ISO).
create or replace function public.agenda_linhas_do_dia(p_dia date, p_max integer default null,
                                                       p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  r       record;
  v_out   jsonb := '[]'::jsonb;
  v_rot   text;
  v_dian  text;
  v_pes   text;
  v_itens text[];
  v_cands text[];
  v_txt   text;
  v_res   text;
  c       text;
  j       int;
begin
  if p_dia is null or p_hoje is null then
    raise exception 'agenda_linhas_do_dia: sem o dia' using errcode = '22004';
  end if;
  for r in select v.* from public.v_agenda_dia v where v.dia = p_dia
            order by v.primeiro_inicio, v.numero, v.service_order_id loop
    v_rot := coalesce(r.cliente_curto || ' (' || r.numero || ')', r.numero);
    v_pes := nullif(public._agenda_pessoas_do_dia(r.pessoas), '');
    if r.reserva then
      v_res := case r.reserva_de when 'patio' then 'Reserva no pátio: ' else 'Reserva: ' end;
      v_cands := array[v_res || v_rot || coalesce(', ' || r.condicao, ': ' || v_pes, ''), v_res || v_rot, v_res || r.numero];
    else
      v_dian := case when coalesce(r.dias_total, 1) > 1 then format(', dia %s de %s', r.dia_n, r.dias_total) else '' end;
      v_itens := coalesce(string_to_array(v_pes, ', '), '{}'::text[]);
      v_cands := array[v_rot || v_dian || coalesce(': ' || v_pes, '')];
      for j in reverse cardinality(v_itens) - 1 .. 1 loop
        v_cands := v_cands || (v_rot || v_dian || ': ' || array_to_string(v_itens[1:j], ', ') || '…');
      end loop;
      v_cands := v_cands || (v_rot || v_dian);
      if r.cliente_curto is not null then
        v_cands := v_cands || (public._agenda_corta(r.cliente_curto, 10) || ' (' || r.numero || ')' || v_dian);
      end if;
      v_cands := v_cands || (r.numero || v_dian);
    end if;
    v_txt := null;
    foreach c in array v_cands loop
      if p_max is null or char_length(c) <= p_max then
        v_txt := c;
        exit;
      end if;
    end loop;
    v_out := v_out || jsonb_build_object(
      'hora', to_char(r.primeiro_inicio at time zone 'America/Sao_Paulo', 'HH24:MI'),
      'texto', coalesce(v_txt, v_cands[cardinality(v_cands)]),
      'ord', to_char(r.primeiro_inicio at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"+00:00"'),
      'os', r.service_order_id, 'numero', r.numero, 'reserva', r.reserva, 'dia_n', r.dia_n, 'dias_total', r.dias_total);
  end loop;
  return v_out;
end;
$function$;

comment on function public.agenda_linhas_do_dia(date, integer, date) is
  'Agenda de Produção (Fase 2, P5): as OS do plano num dia, com o texto pronto para o "Hoje" da manhã e o "Amanhã" do fechamento — "Lenine (OS-00074), dia 1 de 2: você abre, Roberto o dia todo" / "Reserva: Caio (OS-00203), se … estiver na mão (compre até …)". Passou de p_max: saem as pessoas do fim ("…"), depois todas, depois o nome encurta; o número da OS e o "dia n de N" nunca. [{hora, texto, ord (o 1º início em UTC), os, numero, reserva, dia_n, dias_total}]; sem plano no dia = []. Leitura que falha lança.';

-- ── 2. O que está marcado num período (recriada: em 'ligado', o plano) ────────────────────────────────────
-- Corpo de 20261024160500 copiado; as mudanças estão marcadas "-- FASE 2:".

-- As janelas antigas (scheduled_*) das OS da carteira que cruzam [p_de, p_ate] — só as que têm p_tecnico como técnico,
-- se vier — e os compromissos com hora (agenda_tasks pending/in_progress com scheduled_start_at) de p_usuario.
-- Cada item: {tipo, de, ate, hora, nome, o, texto_semana ("ter 27/10 08:00 Lenine", "Flávio (OS-00104) de ter 06/10 a
-- qui 08/10"), texto_dia ("08:00 Lenine", "Flávio (OS-00104) (continua, até qui 08/10)")}, na ordem do dia e da hora.
-- FASE 2: com modo_proposta 'ligado' as OS saem do plano vigente (v_agenda_dia), não da janela antiga: os dias de
-- verdade ("Lenine (qua 04 a seg 09/11)"), a hora do 1º meio-dia e, no dia, quem vai ("Lenine às 08:00, dia 1 de 4
-- (você abre, João)"); a reserva diz que é reserva. p_tecnico = o login: vale o payee dele no plano.
create or replace function public._agenda_marcados(p_de date, p_ate date, p_hoje date, p_tecnico uuid default null,
                                                   p_usuario uuid default null)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with
  -- FASE 2: a agenda automática está ligada?
  lig as (select coalesce((public._agenda_cfg()).modo_proposta = 'ligado', false) as v),
  k as (
    select k.*, count(*) over (partition by public._agenda_normal(k.cliente_curto)) as n_nome
      from public.os_carteira(p_hoje) k
  ),
  -- FASE 2: o plano do período, uma linha por OS (os dias com alocação vigente dentro de [p_de, p_ate])
  pl as (
    select v.service_order_id, min(v.dia) as de, max(v.dia) as ate,
           array_agg(v.dia order by v.dia) as dias, bool_and(v.reserva) as reserva,
           (array_agg(to_char(v.primeiro_inicio at time zone 'America/Sao_Paulo', 'HH24:MI') order by v.dia))[1] as hora,
           (array_agg(v.dia_n order by v.dia))[1] as dia_n, max(v.dias_total) as dias_total,
           (array_agg(v.pessoas order by v.dia))[1] as pessoas,
           (array_agg(v.condicao order by v.dia))[1] as condicao,
           min(v.numero) as numero, min(v.cliente_curto) as curto
      from public.v_agenda_dia v, lig
     where lig.v and v.dia between p_de and p_ate
       and (p_tecnico is null
            or exists (select 1 from jsonb_array_elements(v.pessoas) e
                        where (e ->> 'payee_id')::uuid = any (public._agenda_payees_do_usuario(p_tecnico))))
     group by v.service_order_id
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
           k.numero as chave,
           null::text as ts, null::text as td
      from k
      join public.service_orders so on so.id = k.service_order_id
     where k.agendada_de is not null and k.agendada_de <= p_ate and coalesce(k.agendada_ate, k.agendada_de) >= p_de
       and (p_tecnico is null or exists (select 1 from public.service_order_technicians st
                                          where st.service_order_id = k.service_order_id and st.user_id = p_tecnico))
       -- FASE 2: em 'ligado' a janela antiga é só o espelho; quem diz o marcado é o plano (abaixo)
       and not (select lig.v from lig)
    union all
    -- FASE 2: o plano
    select 'os', pl.de, pl.ate, pl.hora, x.nome,
           jsonb_build_object('curto', pl.curto, 'numero', pl.numero, 'eh_orc', false, 'n_nome', coalesce(kk.n_nome, 1),
                              'os', pl.service_order_id, 'reserva', pl.reserva),
           pl.numero,
           case when pl.reserva then format('%s (reserva, %s)', x.nome, public._agenda_dias_texto(pl.dias))
                when cardinality(pl.dias) = 1 then format('%s (%s às %s)', x.nome, public._dia_curto(pl.de), pl.hora)
                else format('%s (%s)', x.nome, public._agenda_dias_texto(pl.dias)) end,
           case when pl.reserva then
                  x.nome || ' às ' || pl.hora || ', reserva'
                  || coalesce(' ' || pl.condicao, ' (' || nullif(public._agenda_pessoas_do_dia(pl.pessoas), '') || ')', '')
                else x.nome || ' às ' || pl.hora
                     || case when coalesce(pl.dias_total, 1) > 1 then format(', dia %s de %s', pl.dia_n, pl.dias_total) else '' end
                     || coalesce(' (' || nullif(public._agenda_pessoas_do_dia(pl.pessoas), '') || ')', '') end
      from pl
      left join k kk on kk.service_order_id = pl.service_order_id
     cross join lateral (select public._agenda_rotulo(jsonb_build_object('curto', pl.curto, 'numero', pl.numero, 'eh_orc', false,
                                                                         'n_nome', coalesce(kk.n_nome, 1)), 'np') as nome) x
    union all
    select 'compromisso', (t.scheduled_start_at at time zone 'America/Sao_Paulo')::date,
           (coalesce(t.scheduled_end_at, t.scheduled_start_at) at time zone 'America/Sao_Paulo')::date,
           case when not t.all_day and (t.scheduled_start_at at time zone 'America/Sao_Paulo')::date >= p_de
                then to_char(t.scheduled_start_at at time zone 'America/Sao_Paulo', 'HH24:MI') end,
           public._agenda_corta(t.title, 40), null, t.id::text, null, null
      from public.agenda_tasks t
     where p_usuario is not null and t.assignee_user_id = p_usuario
       and t.status in ('pending', 'in_progress') and t.scheduled_start_at is not null
       and (t.scheduled_start_at at time zone 'America/Sao_Paulo')::date <= p_ate
       and (coalesce(t.scheduled_end_at, t.scheduled_start_at) at time zone 'America/Sao_Paulo')::date >= p_de
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'tipo', i.tipo, 'de', i.de, 'ate', i.ate, 'hora', i.hora, 'nome', i.nome, 'o', i.o,
           'texto_semana', coalesce(i.ts, case when i.de = i.ate
                                then format('%s (%s%s)', i.nome, public._dia_curto(i.de), coalesce(' às ' || i.hora, ''))
                                else format('%s de %s a %s', i.nome, public._dia_curto(i.de), public._dia_curto(i.ate)) end),
           'texto_dia', coalesce(i.td, case when i.de >= p_de
                             then i.nome || coalesce(' às ' || i.hora, '')
                                  || case when i.ate > i.de then ' (até ' || public._dia_curto(i.ate) || ')' else '' end
                             else i.nome || case when i.ate > p_ate then ' (continua, até ' || public._dia_curto(i.ate) || ')'
                                                 else ' (último dia)' end end))
           order by greatest(i.de, p_de), i.hora nulls first, i.tipo desc, i.chave), '[]'::jsonb)
    from itens i;
$function$;

comment on function public._agenda_marcados(date, date, date, uuid, uuid) is 'Agenda de Produção (Fase 1, P4; Fase 2, P5): o que está marcado em [p_de, p_ate] — as OS (fora de ''ligado'', a janela antiga scheduled_* da carteira; em ''ligado'', o plano vigente de v_agenda_dia: os dias de verdade, a hora do 1º meio-dia, quem vai e a reserva) — só as de p_tecnico, se vier — e os compromissos com hora de p_usuario (agenda_tasks pending/in_progress com scheduled_start_at), com o texto da semana ("Lenine de ter 27/10 a qua 28/10" / no plano "Lenine (qua 04 a seg 09/11)") e o do dia ("Lenine às 08:00 (até qua 28/10)" / no plano "Lenine às 08:00, dia 1 de 4 (você abre, João)").';

-- ── 3. O dia de uma pessoa (recriada: em 'ligado', o plano, com ou sem login) ─────────────────────────────
-- Corpo de 20261024160500 copiado; as mudanças estão marcadas "-- FASE 2:".

-- FASE 2: a parte de uma pessoa num dia de OS, sem artigo: "o dia todo", "de manhã", "à tarde"; para o dono, "abrindo",
-- "fechando", "abrindo e fechando".
create or replace function public._agenda_parte_da_pessoa(p jsonb)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when coalesce((p ->> 'eh_dono')::boolean, false) and p ->> 'presenca' = 'abertura' then 'abrindo'
              when coalesce((p ->> 'eh_dono')::boolean, false) and p ->> 'presenca' = 'fechamento' then 'fechando'
              when coalesce((p ->> 'eh_dono')::boolean, false) and p ->> 'presenca' = 'abre_e_fecha' then 'abrindo e fechando'
              when p -> 'turnos' @> '["manha", "tarde"]'::jsonb then 'o dia todo'
              when p -> 'turnos' @> '["manha"]'::jsonb then 'de manhã'
              else 'à tarde' end;
$function$;

comment on function public._agenda_parte_da_pessoa(jsonb) is
  'Agenda de Produção (Fase 2, P5): a parte de uma pessoa (de v_agenda_dia.pessoas) num dia de OS — "o dia todo", "de manhã", "à tarde"; o dono "abrindo", "fechando", "abrindo e fechando".';

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
  -- FASE 2: o plano da pessoa no dia
  v_plano  jsonb := '[]'::jsonb;
  v_itens  text[] := '{}';
  r        record;
  e        jsonb;
  v_outros text[];
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

  if c.modo_proposta = 'ligado' then
    -- FASE 2: em 'ligado' o marcado da pessoa é o plano dela no dia (pelo payee, com ou sem login), com quem mais vai,
    -- e os compromissos com hora do login, se tiver.
    for r in select v.*, (select x from jsonb_array_elements(v.pessoas) x where (x ->> 'payee_id')::uuid = py.id limit 1) as eu
               from public.v_agenda_dia v
              where v.dia = p_dia
                and exists (select 1 from jsonb_array_elements(v.pessoas) x where (x ->> 'payee_id')::uuid = py.id)
              order by v.primeiro_inicio, v.numero, v.service_order_id loop
      v_outros := array(
        select case when coalesce((x ->> 'eh_dono')::boolean, false) then 'você ' else coalesce(x ->> 'nome', 'alguém da equipe') || ' ' end
               || public._agenda_parte_da_pessoa(x)
          from jsonb_array_elements(r.pessoas) with ordinality t(x, o)
         where (x ->> 'payee_id')::uuid is distinct from py.id
         order by o);
      v_itens := v_itens || (coalesce(r.cliente_curto || ' (' || r.numero || ')', r.numero) || ' '
                             || public._agenda_parte_da_pessoa(r.eu || jsonb_build_object('eh_dono', v_dono))
                             || case when r.reserva then ', reserva' else '' end
                             || coalesce(' (com ' || nullif(public._agenda_lista(v_outros, null), '') || ')', ''));
      v_plano := v_plano || jsonb_build_object('os', r.service_order_id, 'numero', r.numero, 'hora',
                                               to_char(r.primeiro_inicio at time zone 'America/Sao_Paulo', 'HH24:MI'),
                                               'turnos', r.eu -> 'turnos', 'presenca', r.eu ->> 'presenca', 'reserva', r.reserva);
    end loop;
    if py.app_user_id is not null then
      for e in select x from jsonb_array_elements(public._agenda_marcados(p_dia, p_dia, p_hoje, null, py.app_user_id)) x
                where x ->> 'tipo' = 'compromisso' loop
        v_itens := v_itens || (e ->> 'texto_dia');
      end loop;
    end if;
    v_marc := v_plano;
  else
    v_marc := case when py.app_user_id is null then '[]'::jsonb
                   else public._agenda_marcados(p_dia, p_dia, p_hoje, case when v_dono then null else py.app_user_id end,
                                                py.app_user_id) end;
    v_itens := array(select x ->> 'texto_dia' from jsonb_array_elements(v_marc) with ordinality t(x, o) order by o);
  end if;

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

  -- FASE 2: o texto sai de v_itens (o plano e os compromissos em 'ligado'; o marcado de sempre fora dele)
  if cardinality(v_itens) = 0 then
    l1 := public._agenda_dia_rotulo(p_dia, p_hoje) || ', ' || v_nome || ' não tem nada marcado';
  else
    l1 := public._agenda_dia_rotulo(p_dia, p_hoje) || ', ' || v_nome || ' tem ' || public._agenda_lista(v_itens, 5);
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
    'dados', jsonb_build_object('pessoa', v_nome, 'dia', p_dia, 'marcados', v_marc, 'situacao', v_sit, 'dias_semana', v_dias)
             -- FASE 2: o plano da pessoa no dia
             || case when c.modo_proposta = 'ligado' then jsonb_build_object('plano', v_plano) else '{}'::jsonb end);
end;
$function$;

comment on function public.agenda_dia_da_pessoa(uuid, date, date) is 'Agenda de Produção (Fase 1, P4; Fase 2, P5): "o que o Roberto faz amanhã?" — o marcado da pessoa no dia (fora de ''ligado'': OS em que é técnica, compromisso com hora; em ''ligado'': o plano dela pelo payee, com ou sem login, e quem mais vai — "Qua 04/11, Roberto tem Vanderlei (OS-00069) o dia todo (com você abrindo)" — e os compromissos do login), a situação pela grade (sábado só quando vocês combinam, domingo, feriado, não vem, só de manhã/à tarde, sem padrão) e o padrão de dias ("costuma vir de seg a sex (pelas diárias das últimas 8 semanas: 3 de 5 segundas)"). Sem artigo de gênero antes do nome. {ok, texto, dados}.';

-- ── 4. O que a agenda mudou sozinha ─────────────────────────────────────────────────────────────────────

-- As mudanças que a agenda fez SOZINHA (motor e vigia; na conversa também o replano da conferência) com agenda_acoes.dia
-- em [p_de, p_ate], em grupos: a publicação da semana (as ações publicar da mesma proposta) e cada outra ação; o status
-- que acompanha a publicação ou o replano da mesma OS no mesmo dia vai no grupo dela (fica contado junto, sem frase
-- própria). p_executada = false: o que a sombra teria feito. p_fechamento: só o que ainda não foi contado nem desfeito,
-- e só motor e vigia. [{grupo, tipo (publicacao|acao), proposta_id, acao_ids, itens (as frases), os, nome, numero,
-- desfazivel, desfeita, em}] na ordem em que aconteceram.
create or replace function public._agenda_mudancas(p_de date, p_ate date, p_executada boolean, p_fechamento boolean,
                                                   p_agora timestamptz default null)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with
  b as (
    select a.id, a.tipo, a.service_order_id as os, a.dia, a.proposta_id, a.texto, a.criada_em as em,
           a.desfazivel_ate is not null and a.desfeita_em is null and (p_agora is null or a.desfazivel_ate >= p_agora) as desfazivel,
           a.desfeita_em is not null as desfeita,
           coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as nome, so.service_order_number as numero
      from public.agenda_acoes a
      left join public.service_orders so on so.id = a.service_order_id
      left join public.clients cl on cl.id = so.client_id
     where a.dia between p_de and p_ate and a.executada = p_executada
       and a.tipo not in ('resultado', 'desfazer', 'fixar')
       and (a.origem in ('motor', 'vigia') or (not p_fechamento and a.origem = 'conferencia'))
       and (not p_fechamento or (a.contada_em is null and a.desfeita_em is null))
  ),
  dono as (
    select b.*, coalesce(case when b.tipo = 'publicar' then 'p:' || b.proposta_id end, 'a:' || b.id) as grupo, false as junto
      from b where b.tipo <> 'status'
  ),
  st as (
    select s.*, coalesce((select d.grupo from dono d where d.os = s.os and d.dia = s.dia order by d.em, d.id limit 1),
                         'a:' || s.id) as grupo
      from b s where s.tipo = 'status'
  ),
  todos as (
    select d.* from dono d
    union all
    select s.id, s.tipo, s.os, s.dia, s.proposta_id, s.texto, s.em, s.desfazivel, s.desfeita, s.nome, s.numero, s.grupo,
           s.grupo <> 'a:' || s.id
      from st s
  ),
  g as (
    select t.grupo,
           case when t.grupo like 'p:%' then 'publicacao' else 'acao' end as tipo,
           min(t.proposta_id::text) filter (where t.tipo = 'publicar') as proposta_id,
           jsonb_agg(t.id order by t.em, t.id) as acao_ids,
           coalesce(jsonb_agg(t.texto order by t.em, t.id) filter (where not t.junto), '[]'::jsonb) as itens,
           min(t.os::text) filter (where not t.junto) as os,
           min(t.nome) filter (where not t.junto) as nome,
           min(t.numero) filter (where not t.junto) as numero,
           coalesce(bool_or(t.desfazivel) filter (where not t.junto), false) as desfazivel,
           coalesce(bool_and(t.desfeita) filter (where not t.junto), false) as desfeita,
           min(t.em) as em, min(t.id::text) as desempate
      from todos t
     group by t.grupo
  )
  select coalesce(jsonb_agg(jsonb_build_object('grupo', g.grupo, 'tipo', g.tipo, 'proposta_id', g.proposta_id,
                                               'acao_ids', g.acao_ids, 'itens', g.itens, 'os', g.os, 'nome', g.nome,
                                               'numero', g.numero, 'desfazivel', g.desfazivel, 'desfeita', g.desfeita,
                                               'em', g.em)
                            order by g.em, g.desempate), '[]'::jsonb)
    from g;
$function$;

comment on function public._agenda_mudancas(date, date, boolean, boolean, timestamptz) is
  'Agenda de Produção (Fase 2, P5): o que a agenda mudou sozinha (motor e vigia; fora do fechamento também o replano da conferência) com agenda_acoes.dia em [p_de, p_ate], em grupos — a publicação da semana (as ações publicar da mesma proposta) e cada outra ação; o status que acompanha a publicação ou o replano da mesma OS no mesmo dia vai no grupo dela. p_executada false = o que a sombra teria feito; p_fechamento = só o não contado e não desfeito, só motor e vigia. [{grupo, tipo, proposta_id, acao_ids, itens, os, nome, numero, desfazivel, desfeita, em}].';

-- A frase de um grupo de mudanças (a conversa): "Publiquei a semana de 03 a 06/11 (seg 02 é Finados): <cada OS>
-- *desfaz semana* volta como estava." / "<a frase da ação> *desfaz Nelson* volta como estava." Na sombra, "Publicaria".
create or replace function public._agenda_mudanca_texto(p_g jsonb, p_sombra boolean default false)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when p_g ->> 'tipo' = 'publicacao' then
      case when p_sombra then 'Publicaria ' else 'Publiquei ' end
      || coalesce(regexp_replace(p.textos ->> 'titulo', '^Semana', 'a semana'), 'a semana')
      || ': ' || (select string_agg(x, ' ' order by o) from jsonb_array_elements_text(p_g -> 'itens') with ordinality t(x, o))
      || case when coalesce((p_g ->> 'desfeita')::boolean, false) then ' (já desfeito)'
              when coalesce((p_g ->> 'desfazivel')::boolean, false) then ' *desfaz semana* volta como estava.' else '' end
    else (select string_agg(x, ' ' order by o) from jsonb_array_elements_text(p_g -> 'itens') with ordinality t(x, o))
         || case when coalesce((p_g ->> 'desfeita')::boolean, false) then ' (já desfeito)'
                 when coalesce((p_g ->> 'desfazivel')::boolean, false)
                   then format(' *desfaz %s* volta como estava.', p_g ->> 'nome') else '' end end
    from (select 1) um
    left join public.agenda_propostas p on p.id = nullif(p_g ->> 'proposta_id', '')::uuid;
$function$;

comment on function public._agenda_mudanca_texto(jsonb, boolean) is
  'Agenda de Produção (Fase 2, P5): a frase de um grupo de _agenda_mudancas — a publicação ("Publiquei a semana de 03 a 06/11 (seg 02 é Finados): … *desfaz semana* volta como estava."; na sombra "Publicaria …") ou a ação ("<frase> *desfaz Nelson* volta como estava."), com "(já desfeito)" quando foi desfeita.';

-- ── 5. Os focos novos da agenda_ver ─────────────────────────────────────────────────────────────────────

-- "o que você precisa de mim?": as decisões críticas abertas, numeradas como o rascunho resolve "a 1"
-- (agenda_decisoes_abertas), e depois o que mais a agenda quer saber (uma linha cada). Na sombra: "Em teste".
create or replace function public._agenda_ver_decisoes(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_dec   jsonb := public.agenda_decisoes_abertas(p_agora);
  v_l     text[] := '{}';
  v_outra text[];
  v_som   text[];
  e       jsonb;
begin
  for e in select x from jsonb_array_elements(v_dec) x loop
    v_l := v_l || format('Decisão %s: %s', e ->> 'n', e ->> 'texto');
  end loop;
  v_outra := array(select q.texto from public.agenda_perguntas q
                    where not q.critica and q.estado = 'aberta' and q.modo = 'ligado'
                      and (q.expira_em is null or q.expira_em > p_agora)
                    order by q.perda_em nulls last, q.criada_em, q.id);
  if jsonb_array_length(v_dec) > 0 then
    v_l := array[case when jsonb_array_length(v_dec) = 1 then 'Uma decisão espera você na agenda:'
                      else format('%s decisões esperam você na agenda:', jsonb_array_length(v_dec)) end]
           || v_l
           || 'Para responder, diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2"). Eu não escolho por você.'::text;
  end if;
  if cardinality(v_outra) > 0 then
    v_l := v_l || array(select 'Também quero saber: ' || x from unnest(v_outra) with ordinality u(x, o) order by o);
  end if;
  if cardinality(v_l) = 0 then
    v_som := array(select q.texto from public.agenda_perguntas q
                    where q.estado = 'aberta' and q.modo = 'sombra' and (q.expira_em is null or q.expira_em > p_agora)
                    order by q.critica desc, q.perda_em nulls last, q.criada_em, q.id);
    if cardinality(v_som) > 0 and (cf.modo_proposta = 'sombra' or cf.modo_vigia = 'sombra') then
      v_l := array['Em teste (nada foi perguntado de verdade): eu perguntaria isto.']
             || array(select '• ' || x from unnest(v_som) with ordinality u(x, o) order by o);
    else
      v_l := array['Nada esperando você na agenda agora.'];
    end if;
  end if;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, cf.texto_max),
                            'dados', jsonb_build_object('decisoes', v_dec, 'outras', cardinality(v_outra)));
end;
$function$;

comment on function public._agenda_ver_decisoes(date, timestamptz) is
  'Agenda de Produção (Fase 2, P5): agenda_ver foco decisoes — as decisões críticas abertas numeradas por agenda_decisoes_abertas ("Decisão 1: <a pergunta com as opções e a recomendação>"), como responder, e o que mais a agenda quer saber (chegou?, parada?, o que falta?), uma linha cada; sem nada em ligado, o que a sombra perguntaria ("Em teste"); nada = "Nada esperando você na agenda agora.". {ok, texto, dados{decisoes, outras}}.';

-- "o que você mudou?": o que a agenda mudou sozinha de ontem para hoje, com *desfaz <nome>* no que ainda dá para desfazer.
-- Na sombra: "Em teste (nada foi mudado)" e o que ela teria feito.
create or replace function public._agenda_ver_mudancas(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf   public.agenda_config := public._agenda_cfg();
  v_g  jsonb := public._agenda_mudancas(p_hoje - 1, p_hoje, true, false, p_agora);
  v_s  jsonb;
  v_l  text[];
begin
  if jsonb_array_length(v_g) > 0 then
    v_l := array['O que mudei sozinho na agenda desde ontem:']
           || array(select '• ' || public._agenda_mudanca_texto(x, false) from jsonb_array_elements(v_g) with ordinality t(x, o) order by o);
  else
    v_s := case when cf.modo_proposta = 'sombra' then public._agenda_mudancas(p_hoje - 1, p_hoje, false, false, p_agora)
                else '[]'::jsonb end;
    if jsonb_array_length(v_s) > 0 then
      v_l := array['Em teste (nada foi mudado): desde ontem eu teria feito isto.']
             || array(select '• ' || public._agenda_mudanca_texto(x, true) from jsonb_array_elements(v_s) with ordinality t(x, o) order by o);
    elsif cf.modo_proposta = 'desligado' then
      v_l := array['A agenda automática está desligada: eu não mudo nada sozinho.'];
    else
      v_l := array['Não mudei nada na agenda desde ontem.'];
    end if;
  end if;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, cf.texto_max),
                            'dados', jsonb_build_object('mudancas', v_g, 'sombra', coalesce(v_s, '[]'::jsonb)));
end;
$function$;

comment on function public._agenda_ver_mudancas(date, timestamptz) is
  'Agenda de Produção (Fase 2, P5): agenda_ver foco mudancas — o que a agenda mudou sozinha de ontem para hoje (_agenda_mudancas), uma linha por grupo com *desfaz <nome>* (ou *desfaz semana*) no que ainda dá para desfazer e "(já desfeito)"; em sombra, "Em teste (nada foi mudado)" e o que ela teria feito; nada = "Não mudei nada na agenda desde ontem.". {ok, texto, dados}.';

-- "agenda plano": o publicado do período, dia a dia, com quem vai (agenda_linhas_do_dia); o feriado no meio aparece; as
-- montadas e não publicadas numeradas como o rascunho resolve "a última" (agenda_propostas_abertas). Na sombra: a última
-- semana que a sombra montou ("Em teste: eu montaria assim"). Sem período: de hoje ao sábado da semana que vem.
create or replace function public._agenda_ver_plano(p_de date, p_ate date, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_de   date := coalesce(p_de, p_hoje);
  v_ate  date := coalesce(p_ate, p_hoje - (extract(isodow from p_hoje)::int - 1) + 12);
  v_l    text[] := '{}';
  v_d    date;
  v_lin  jsonb;
  v_n    int := 0;
  v_ab   jsonb;
  p      record;
  v_fer  text;
begin
  if v_ate < v_de then
    raise exception 'agenda_ver: período invertido (% a %)', v_de, v_ate using errcode = '22023';
  end if;
  if cf.modo_proposta = 'ligado' then
    v_d := v_de;
    while v_d <= v_ate loop
      v_lin := public.agenda_linhas_do_dia(v_d, null, p_hoje);
      v_fer := public.agenda_feriado(v_d);
      if jsonb_array_length(v_lin) > 0 then
        v_n := v_n + jsonb_array_length(v_lin);
        v_l := v_l || (public._agenda_dia_rotulo(v_d, p_hoje) || ': '
                       || (select string_agg((x ->> 'hora') || ' ' || (x ->> 'texto'), '; ' order by o)
                             from jsonb_array_elements(v_lin) with ordinality t(x, o)) || '.');
      elsif v_fer is not null and extract(isodow from v_d) between 1 and 5 then
        v_l := v_l || (public._agenda_dia_rotulo(v_d, p_hoje) || ': ' || v_fer || '.');
      end if;
      v_d := v_d + 1;
    end loop;
    v_l := array[public._agenda_periodo_rotulo(v_de, v_ate, p_hoje)
                 || case when v_n = 0 then ': nada publicado na agenda.' else ', o que está publicado:' end] || v_l;
    v_ab := public.agenda_propostas_abertas(p_agora);
    if jsonb_array_length(v_ab) > 0 then
      v_l := v_l || ('Montei e ainda não publiquei: '
                     || (select string_agg(format('%s) %s', x ->> 'n', coalesce(x ->> 'titulo', 'uma mudança')), '; ' order by (x ->> 'n')::int)
                           from jsonb_array_elements(v_ab) x)
                     || '. Para publicar, diga "publica a 1".');
    end if;
  elsif cf.modo_proposta = 'sombra' then
    select pr.* into p from public.agenda_propostas pr
     where pr.modo = 'sombra' and pr.escopo = 'semana'
     order by pr.criada_em desc, pr.id desc limit 1;
    if p.id is null then
      v_l := array['Em teste: ainda não montei nenhuma semana.'];
    else
      v_l := array['Em teste (nada foi publicado): eu montaria assim — ' || coalesce(p.textos ->> 'titulo', 'a semana') || '.']
             || array(select x from jsonb_array_elements_text(coalesce(p.textos -> 'linhas', '[]'::jsonb)) with ordinality t(x, o) order by o)
             || array(select 'Fora: ' || regexp_replace(x, '\?\.$', '?')
                        from jsonb_array_elements_text(coalesce(p.textos -> 'fora', '[]'::jsonb)) with ordinality t(x, o)
                       order by o);
    end if;
  else
    v_l := array['A agenda automática está desligada: não há plano publicado.'];
  end if;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, cf.texto_max),
                            'dados', jsonb_build_object('de', v_de, 'ate', v_ate, 'linhas', v_n,
                                                        'abertas', coalesce(v_ab, '[]'::jsonb)));
end;
$function$;

comment on function public._agenda_ver_plano(date, date, date, timestamptz) is
  'Agenda de Produção (Fase 2, P5): agenda_ver foco plano — em ligado, o publicado de [p_de, p_ate] dia a dia ("Ter 03/11: 08:00 Vanderlei (OS-00069), dia 1 de 3: você abre, Roberto o dia todo; 13:00 …"), o feriado de dia útil no meio, e as montadas e não publicadas numeradas por agenda_propostas_abertas ("publica a 1"); em sombra, a última semana montada pela sombra ("Em teste (nada foi publicado): eu montaria assim — …"); desligado diz que não há plano. Sem período: de hoje ao sábado da semana que vem. {ok, texto, dados}.';

-- ── 6. O despacho único: agenda_ver (recriada, mesma assinatura) ────────────────────────────────────────
-- Corpo de 20261024160500 copiado; as mudanças estão marcadas "-- FASE 2:".

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
  -- FASE 2: a hora de agora (desfazer ainda vale? a decisão venceu?). now(); a bancada fixa com agenda.agora.
  v_agora   timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
begin
  -- FASE 2: os focos decisoes, mudancas e plano
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar', 'decisoes', 'mudancas', 'plano') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas ou plano)', p_foco
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
  -- FASE 2: o que espera o dono, o que mudou sozinho e o plano publicado
  elsif v_foco = 'decisoes' then
    v_rota := 'decisoes';
    v_r := public._agenda_ver_decisoes(p_hoje, v_agora);
  elsif v_foco = 'mudancas' then
    v_rota := 'mudancas';
    v_r := public._agenda_ver_mudancas(p_hoje, v_agora);
  elsif v_foco = 'plano' then
    v_rota := 'plano';
    v_r := public._agenda_ver_plano(v_de, v_ate, p_hoje, v_agora);
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

comment on function public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date) is 'Agenda de Produção (Fase 1, P4; Fase 2, P5): o despacho ÚNICO da ferramenta agenda_ver e dos comandos sem IA. os + simular_aprovacao → agenda_ctp; os + foco material → agenda_ver_material; os → a visão da OS; simular {dias, com_quem, dono} → agenda_simular; FASE 2: foco decisoes → as decisões numeradas (agenda_decisoes_abertas) e o que mais a agenda quer saber; mudancas → o que mudou sozinho desde ontem com *desfaz*; plano → o publicado do período dia a dia (sombra: "Em teste"); foco o_que_fazer → agenda_o_que_fazer (pessoa que não é o dono: o dia dela); atrasos/riscos → agenda_atrasos; material → agenda_ver_material(null); livre → resumo + livre de agenda_semana; aprontar → agenda_aprontar; pessoa (não o dono) + 1 dia → agenda_dia_da_pessoa; hoje/amanhã → o dia + o bloco 2 resumido; resto → agenda_semana (em ''ligado'' o marcado é o plano). periodo: hoje, amanha, semana, proxima_semana ou o que o dono disse. Referência que não existe (OS, pessoa, data) → {ok:false, texto:"Não encontrei …"/a pergunta}; foco fora da lista lança 22023. Devolve {ok, texto, dados, rota}.';

-- ── 7. As linhas da agenda no fechamento das 17:30 ──────────────────────────────────────────────────────

-- A linha da semana publicada (quinta): "Agenda: publiquei a semana de 03 a 06/11 (seg 02 é Finados): Vanderlei (ter 03 a
-- qui 05/11), Rodrigo OS-00096 (ter 03/11), … Fora: Nelson (preciso de você) e Giancarlo (começa qui 26/11). Depois desta
-- semana, só tem 6,5 dias de serviço pronto na fila. *agenda plano* mostra tudo; *desfaz semana* volta." Até 480
-- caracteres: passou, saem OS do fim ("e mais N"), depois o "Fora", depois a fila.
create or replace function public._agenda_linha_da_semana(p_proposta uuid, p_acao_ids jsonb, p_desfazivel boolean, p_hoje date)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c_max   constant int := 480;   -- estrutural: a linha da semana no fechamento (não é parâmetro de negócio)
  v_tit   text;
  v_fora  jsonb;
  v_itens text[];
  v_foras text[];
  v_back  text;
  v_cab   text;
  v_tail  text;
  v_txt   text;
  k       int;
  n       int;
begin
  select regexp_replace(coalesce(p.textos ->> 'titulo', 'Semana'), '^Semana', 'a semana'), p.fora into v_tit, v_fora
    from public.agenda_propostas p where p.id = p_proposta;
  v_itens := array(
    select case when q.reserva then 'reserva para ' || q.nome else q.nome end || ' (' || public._agenda_dias_texto(q.dias) || ')'
      from (select a.id,
                   public._agenda_rotulo(jsonb_build_object('curto', public._agenda_nome_curto(cl.name), 'numero', so.service_order_number,
                                                            'eh_orc', false, 'n_nome', coalesce(kk.n_nome, 1)), 'np') as nome,
                   array(select distinct (x ->> 'dia')::date from jsonb_array_elements(coalesce(a.depois -> 'alocacoes', '[]'::jsonb)) x
                          order by 1) as dias,
                   exists (select 1 from public.agenda_alocacoes al where al.id = any (a.alocacoes_criadas) and al.tipo = 'reserva') as reserva,
                   so.service_order_number as numero
              from public.agenda_acoes a
              join public.service_orders so on so.id = a.service_order_id
              left join public.clients cl on cl.id = so.client_id
              left join (select k.service_order_id, count(*) over (partition by public._agenda_normal(k.cliente_curto)) as n_nome
                           from public.os_carteira(p_hoje) k) kk on kk.service_order_id = a.service_order_id
             where a.id in (select x::uuid from jsonb_array_elements_text(coalesce(p_acao_ids, '[]'::jsonb)) x)
               and a.tipo = 'publicar') q
     order by q.reserva, q.dias[1], q.numero, q.id);
  v_foras := array(
    select coalesce(f ->> 'cliente_curto', f ->> 'numero') || ' ('
           || case when f ->> 'motivo' = 'nao_cabe' then 'preciso de você'
                   else regexp_replace(regexp_replace(coalesce(f ->> 'texto', ''), '^[^:]*: ', ''), '( \(| —|\.$).*$', '') end || ')'
      from jsonb_array_elements(coalesce(v_fora, '[]'::jsonb)) with ordinality t(f, o)
     where f ->> 'motivo' in ('nao_cabe', 'depois', 'sem_encaixe', 'so_com_voce', 'padrao_do_dono')
     order by o);
  select r.contagens #>> '{backlog,texto}' into v_back
    from public.agenda_vigia_rodadas r
   where r.p_hoje = $4 and nullif(r.contagens #>> '{backlog,texto}', '') is not null
   order by r.rodou_em desc, r.id desc limit 1;
  v_cab := 'Agenda: publiquei ' || v_tit || ': ';
  v_tail := ' *agenda plano* mostra tudo' || case when p_desfazivel then '; *desfaz semana* volta.' else '.' end;
  n := cardinality(v_itens);
  for k in reverse n .. 1 loop
    v_txt := v_cab || public._agenda_lista(v_itens, k) || '.'
             || coalesce(' Fora: ' || nullif(public._agenda_lista(v_foras, 3), '') || '.', '') || coalesce(' ' || v_back, '') || v_tail;
    exit when char_length(v_txt) <= c_max;
  end loop;
  if char_length(v_txt) > c_max then
    v_txt := v_cab || public._agenda_lista(v_itens, 1) || '.' || coalesce(' ' || v_back, '') || v_tail;
  end if;
  if char_length(v_txt) > c_max then
    v_txt := v_cab || public._agenda_lista(v_itens, 1) || '.' || v_tail;
  end if;
  return v_txt;
end;
$function$;

comment on function public._agenda_linha_da_semana(uuid, jsonb, boolean, date) is
  'Agenda de Produção (Fase 2, P5): a linha da semana publicada no fechamento — as OS com os dias (a reserva diz que é reserva), o que estava pronto e ficou fora (não cabe → "preciso de você"; começa depois), a fila curta da vigia e *agenda plano* / *desfaz semana*. Até 480 caracteres, tirando OS do fim, depois o "Fora", depois a fila.';

-- As linhas da agenda no fechamento: [{tipo, texto, perda (0–100), pergunta_id, acao_ids, modo}], da maior perda para a
-- menor. tipo: decisao (crítica: 100 se perde até amanhã útil, 80 até 2 dias úteis, 50 depois), dia (a conferência de
-- hoje e o que mudou sozinho: 70), semana (a publicação da quinta: 60), mudancas (o que mudou sozinho sem conferência:
-- 40), pergunta (chegou?, parada?, o que falta?, quantos dias?: 30, uma só, a que perde primeiro, com "e mais N em
-- *agenda pendências*"). modo = 'ligado' só quando o registro é de ligado E o modo que o governa está ligado agora
-- (decisão, semana e mudanças: modo_proposta; conferência e perguntas: modo_vigia); o resto é 'sombra' (o que diria).
-- A janela das mudanças: o que ainda não foi contado nos últimos 7 dias (o fechamento que não saiu não as perde).
create or replace function public._agenda_linhas_do_fechamento(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_max   constant int := 480;   -- estrutural: uma linha da agenda no fechamento
  v_ini   date;
  v_am1   date;
  v_am2   date;
  v_out   jsonb := '[]'::jsonb;
  q       record;
  g       jsonb;
  v_m     jsonb;
  v_ms    jsonb;
  v_conf  record;
  v_txts  text[];
  v_ids   jsonb;
  v_txt   text;
  v_mod   text;
  v_n     int;
  k       int;
  m       text;
begin
  if p_hoje is null then
    raise exception 'agenda: sem o dia de hoje' using errcode = '22004';
  end if;
  if cf.modo_proposta = 'desligado' and cf.modo_vigia = 'desligado' then
    return '[]'::jsonb;
  end if;
  v_ini := p_hoje - 6;
  v_am1 := public.agenda_somar_du(p_hoje, 1);
  v_am2 := public.agenda_somar_du(p_hoje, 2);

  -- (a) as decisões críticas abertas
  for q in select x.* from public.agenda_perguntas x where x.critica and x.estado = 'aberta'
            order by x.perda_em nulls last, x.criada_em, x.id loop
    v_out := v_out || jsonb_build_object('tipo', 'decisao',
      'texto', 'Agenda, preciso de você. ' || q.texto || ' Me responda aqui.',
      'perda', case when q.perda_em is not null and q.perda_em <= v_am1 then 100
                    when q.perda_em is not null and q.perda_em <= v_am2 then 80 else 50 end,
      'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when q.modo = 'ligado' and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- (b) o que mudou sozinho (de verdade e na sombra), ainda não contado
  v_m := public._agenda_mudancas(v_ini, p_hoje, true, true, null);
  v_ms := public._agenda_mudancas(v_ini, p_hoje, false, true, null);

  -- (c) a semana publicada
  for g in select x from jsonb_array_elements(v_m) x where x ->> 'tipo' = 'publicacao' loop
    v_out := v_out || jsonb_build_object('tipo', 'semana',
      'texto', public._agenda_linha_da_semana((g ->> 'proposta_id')::uuid, g -> 'acao_ids', (g ->> 'desfazivel')::boolean, p_hoje),
      'perda', 60, 'pergunta_id', null, 'acao_ids', g -> 'acao_ids',
      'modo', case when cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;
  for g in select x from jsonb_array_elements(v_ms) x where x ->> 'tipo' = 'publicacao' loop
    v_out := v_out || jsonb_build_object('tipo', 'semana',
      'texto', public._agenda_linha_da_semana((g ->> 'proposta_id')::uuid, g -> 'acao_ids', false, p_hoje),
      'perda', 60, 'pergunta_id', null, 'acao_ids', g -> 'acao_ids', 'modo', 'sombra');
  end loop;

  -- (d) a conferência de hoje, com o que mudou sozinho; sem ela, o que mudou numa linha só
  select x.* into v_conf from public.agenda_perguntas x
   where x.tipo = 'conferencia' and x.estado = 'aberta' and x.dia = p_hoje
   order by (x.modo = 'ligado') desc, x.criada_em desc, x.id desc limit 1;
  for m in select unnest(array['ligado', 'sombra']) loop
    v_txts := array(select public._agenda_mudanca_texto(x, false)
                      from jsonb_array_elements(case when m = 'ligado' then v_m else v_ms end) with ordinality t(x, o)
                     where x ->> 'tipo' = 'acao' order by o);
    v_ids := coalesce((select jsonb_agg(y order by o, o2)
                         from jsonb_array_elements(case when m = 'ligado' then v_m else v_ms end) with ordinality t(x, o),
                              jsonb_array_elements(x -> 'acao_ids') with ordinality u(y, o2)
                        where x ->> 'tipo' = 'acao'), '[]'::jsonb);
    v_mod := case when m = 'ligado' and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end;
    if v_conf.id is not null and v_conf.modo = m then
      -- a conferência governa pela vigia; o que mudou sozinho vai junto
      for k in reverse cardinality(v_txts) .. 0 loop
        v_txt := v_conf.texto
                 || case when k > 0 then ' Mudei sozinho: ' || array_to_string(v_txts[1:k], ' ')
                                         || case when k < cardinality(v_txts) then format(' (e mais %s em *o que mudou*)', cardinality(v_txts) - k) else '' end
                         when cardinality(v_txts) > 0 then format(' Mudei sozinho %s: *o que mudou* mostra.',
                                                                   public._agenda_plural(cardinality(v_txts), 'coisa', 'coisas'))
                         else '' end;
        exit when char_length(v_txt) <= c_max;
      end loop;
      v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', v_txt, 'perda', 70, 'pergunta_id', v_conf.id, 'acao_ids', v_ids,
        'modo', case when v_conf.modo = 'ligado' and cf.modo_vigia = 'ligado' and v_mod = 'ligado' then 'ligado' else 'sombra' end);
    elsif cardinality(v_txts) > 0 then
      for k in reverse cardinality(v_txts) .. 1 loop
        v_txt := 'Agenda, mudei sozinho. ' || array_to_string(v_txts[1:k], ' ')
                 || case when k < cardinality(v_txts) then format(' (e mais %s em *o que mudou*)', cardinality(v_txts) - k) else '' end;
        exit when char_length(v_txt) <= c_max;
      end loop;
      v_out := v_out || jsonb_build_object('tipo', 'mudancas', 'texto', v_txt, 'perda', 40, 'pergunta_id', null, 'acao_ids', v_ids,
                                           'modo', v_mod);
    end if;
  end loop;
  -- a conferência na sombra sem nada a contar junto, ou de um modo sem mudança (o laço acima já cobriu quem teve)
  -- (nada a fazer: o laço passa pelos dois modos)

  -- (e) uma pergunta de fato, a que perde primeiro (cada pergunta aparece em até perguntas_vezes_max fechamentos)
  for m in select unnest(array['ligado', 'sombra']) loop
    select count(*) into v_n from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       and x.mostrada_vezes < cf.perguntas_vezes_max;
    continue when v_n = 0;
    select x.* into q from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       and x.mostrada_vezes < cf.perguntas_vezes_max
     order by x.perda_em nulls last, x.criada_em, x.id limit 1;
    v_out := v_out || jsonb_build_object('tipo', 'pergunta',
      'texto', 'Agenda: ' || q.texto || case when v_n > 1 then format(' (e mais %s em *agenda pendências*)', v_n - 1) else '' end,
      'perda', 30, 'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when m = 'ligado' and cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  return coalesce((select jsonb_agg(x order by (x ->> 'perda')::int desc, x ->> 'tipo', x ->> 'texto')
                     from jsonb_array_elements(v_out) x), '[]'::jsonb);
end;
$function$;

comment on function public._agenda_linhas_do_fechamento(date) is
  'Agenda de Produção (Fase 2, P5): as linhas da agenda no fechamento das 17:30 — [{tipo (decisao|dia|semana|mudancas|pergunta), texto, perda, pergunta_id, acao_ids, modo}] da maior perda para a menor (decisão 100/80/50 pela perda_em; dia 70; semana 60; mudanças 40; pergunta 30). modo ligado só com o registro em ligado e o modo que o governa ligado agora; o resto sombra (o que diria). O secretário mostra as ligadas que cabem nas vagas (REGRAS.maxManha − as que ficaram) e registra o que saiu (agenda_fechamento_registrar).';

-- ── 8. O fechamento das 17:30 (recriada, mesma assinatura) ──────────────────────────────────────────────
-- Corpo de 20261024160500 copiado; as mudanças estão marcadas "-- FASE 2:".

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
                              'dia_do_plano', false,
                              -- FASE 2: com a leitura desligada a agenda inteira cala
                              'linhas', '[]'::jsonb);
  end if;
  v_dia := coalesce(p_dia, p_hoje + 1);
  v_pn := public._agenda_painel(p_hoje);
  v_plano := extract(isodow from p_hoje)::int = c.dia_do_plano;

  select coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> 'ordem')::int), '[]'::jsonb)
    into v_prontos from jsonb_array_elements(v_pn -> 'oss') e where e ->> 'grupo' = 'pronto';
  select count(*) into v_esp from jsonb_array_elements(v_pn -> 'oss') e where (e ->> 'dono_trava')::boolean;

  -- A cauda do "Amanhã" sem nada marcado. Se a agenda vê algo marcado no dia, não há cauda (o Secretário diz o dia).
  -- (FASE 2: em 'ligado' o marcado é o plano — _agenda_marcados.)
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
  -- FASE 2: com a agenda automática ligada a projeção não sai: a linha "semana" do publicado (linhas) a substitui.
  if v_plano and c.modo_proposta <> 'ligado' then
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
                                                        'fila', v_pn -> 'backlog', 'livre', v_pn -> 'livre'),
                            -- FASE 2: as linhas da agenda (decisões, o dia, a semana, o que mudou, uma pergunta)
                            'linhas', public._agenda_linhas_do_fechamento(p_hoje));
end;
$function$;

comment on function public.agenda_textos_do_fechamento(date, date) is 'Agenda de Produção (Fase 1, P4; Fase 2, P5): as linhas da agenda no fechamento das 17:30 — cauda_amanha (o "Amanhã" sem nada marcado: "nada marcado; nenhum serviço pronto, 7 esperando você (*agenda*)" ou "nada marcado; prontos para começar: …"; null quando a agenda vê algo marcado em p_dia — em ''ligado'', o plano), só quando isodow(p_hoje) = dia_do_plano e a agenda automática não está ligada, até 3 linhas "Semana que vem (projeção)" de até 160 caracteres, e (FASE 2) linhas [{tipo, texto, perda, pergunta_id, acao_ids, modo}] de _agenda_linhas_do_fechamento. modo_leitura desligado: nada. O Secretário decide o que publica (sombra × ligado; vagas de REGRAS.maxManha).';

-- ── 9. O estado das OS para o secretário ────────────────────────────────────────────────────────────────

-- Por OS da carteira (fora orçamento): o estado da prontidão, programada (tem dia no plano de hoje em diante), fixada, o
-- próximo dia (sem reserva), a 1ª reserva, parada (em andamento sem evidência e sem dia futuro — a regra da vigia), desde
-- quando (a última evidência) e o que falta comprar: {itens, compre_ate, para_dia, reserva, texto} (null = nada a comprar).
create or replace function public.agenda_estado_das_os(p_hoje date default public._hoje_brt())
 returns setof jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  k       record;
  p       jsonb;
  v_pl    jsonb;
  v_n     int;
  v_ate_i date;
  v_ate_r date;
  v_ate   date;
  v_prox  date;
  v_res   date;
  v_para  date;
  v_rot   text;
  v_comp  jsonb;
begin
  if p_hoje is null then
    raise exception 'agenda_estado_das_os: sem o dia de hoje' using errcode = '22004';
  end if;
  for k in select x.service_order_id, x.numero, x.cliente_curto from public.os_carteira(p_hoje) x
            where not x.eh_orcamento order by x.numero, x.service_order_id loop
    p := public.os_prontidao(k.service_order_id, p_hoje);
    v_pl := p -> 'plano';
    v_prox := (v_pl ->> 'proximo_dia')::date;
    v_res := (v_pl #>> '{reservas,0,dia}')::date;
    v_rot := coalesce(k.cliente_curto || ' (' || k.numero || ')', k.numero);
    select count(*), min((i ->> 'compre_ate')::date) into v_n, v_ate_i
      from jsonb_array_elements(coalesce(p #> '{material,itens}', '[]'::jsonb)) i
     where coalesce((i ->> 'critico')::boolean, true) and i ->> 'situacao' = 'falta';
    v_comp := null;
    if v_n > 0 then
      select min(a.condicao_ate) into v_ate_r from public.agenda_alocacoes a
       where a.service_order_id = k.service_order_id and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva'
         and a.condicao_tipo = 'compra' and a.dia >= p_hoje;
      v_ate := coalesce(v_ate_r, v_ate_i);
      v_para := case when v_prox is not null and (v_res is null or v_prox <= v_res) then v_prox else v_res end;
      v_comp := jsonb_build_object('itens', v_n, 'compre_ate', v_ate, 'para_dia', v_para,
        'reserva', v_para is not null and v_para is distinct from v_prox,
        'texto', v_rot || ': ' || public._agenda_plural(v_n, 'item', 'itens') || ' a comprar'
                 || case when v_ate is not null then ' até ' || public._dia_curto(v_ate) else '' end
                 || case when v_para is null then ''
                         when v_para is distinct from v_prox then ' para a reserva de ' || public._dia_curto(v_para)
                         else ' para o serviço de ' || public._dia_curto(v_para) end);
    end if;
    return next jsonb_build_object(
      'os', k.service_order_id, 'numero', k.numero, 'estado', p ->> 'estado',
      'programada', v_prox is not null or p ->> 'estado' in ('programada', 'fixada'),
      'fixada', coalesce((v_pl ->> 'fixada')::boolean, false),
      'proximo_dia', v_prox, 'reserva_dia', v_res,
      'parada', p ->> 'estado' = 'parada',
      'desde', coalesce(p ->> 'ultima_evidencia', p ->> 'ultima_diaria'),
      'compra', v_comp);
  end loop;
  return;
end;
$function$;

comment on function public.agenda_estado_das_os(date) is
  'Agenda de Produção (Fase 2, P5): para o secretário (os_parada e os_esperando_compra lendo o plano; as compras do "Amanhã") — uma linha por OS da carteira (fora orçamento): {os, numero, estado (os_prontidao), programada (tem dia no plano de hoje em diante), fixada, proximo_dia (sem reserva), reserva_dia, parada (a regra da vigia), desde (última evidência), compra {itens, compre_ate (o da reserva condicionada, senão o do item), para_dia, reserva, texto "Caio (OS-00203): 1 item a comprar até ter 03/11 para a reserva de qui 05/11"} ou null}.';

-- ── 10. O conflito de agenda da tela (recriada: mesma assinatura e ACL) ──────────────────────────────────

create or replace function public.get_agenda_conflicts(p_user_id uuid, p_start timestamp with time zone,
                                                       p_end timestamp with time zone, p_exclude_task uuid default null::uuid,
                                                       p_exclude_so uuid default null::uuid)
 returns table(source text, ref_id uuid, label text, starts_at timestamp with time zone, ends_at timestamp with time zone)
 language sql
 stable
 set search_path to 'public'
as $function$
  select 'task'::text, t.id, t.title, t.scheduled_start_at, t.scheduled_end_at
    from agenda_tasks t
   where t.assignee_user_id = p_user_id
     and t.kind = 'appointment'
     and t.status in ('pending', 'in_progress')
     and t.id is distinct from p_exclude_task
     and t.scheduled_start_at is not null and t.scheduled_end_at is not null
     and tstzrange(t.scheduled_start_at, t.scheduled_end_at) && tstzrange(p_start, p_end)
  union all
  -- FASE 2: a OS SEM alocação vigente ocupa a janela corrida, como antes
  select 'service_order'::text, so.id, so.service_order_number, so.scheduled_start_at, so.scheduled_end_at
    from service_orders so
    join service_order_technicians sot on sot.service_order_id = so.id
   where sot.user_id = p_user_id
     and so.status <> 'cancelled'
     and so.id is distinct from p_exclude_so
     and so.scheduled_start_at is not null and so.scheduled_end_at is not null
     and tstzrange(so.scheduled_start_at, so.scheduled_end_at) && tstzrange(p_start, p_end)
     and not exists (select 1 from agenda_alocacoes a where a.service_order_id = so.id and a.estado in ('publicada', 'fixada'))
  union all
  -- FASE 2: a OS COM alocação vigente ocupa só os períodos das alocações dela (o turno, não a janela corrida)
  select distinct 'service_order'::text, so.id, so.service_order_number, lower(a.periodo), upper(a.periodo)
    from service_orders so
    join service_order_technicians sot on sot.service_order_id = so.id
    join agenda_alocacoes a on a.service_order_id = so.id and a.estado in ('publicada', 'fixada')
   where sot.user_id = p_user_id
     and so.status <> 'cancelled'
     and so.id is distinct from p_exclude_so
     and a.periodo && tstzrange(p_start, p_end)
  union all
  -- FASE 2: o payee ligado ao login (o dono pelo sócio) alocado em OS em que ele não é técnico
  select distinct 'alocacao'::text, so.id, so.service_order_number, lower(a.periodo), upper(a.periodo)
    from agenda_alocacoes a
    join service_orders so on so.id = a.service_order_id
   where a.estado in ('publicada', 'fixada')
     and a.payee_id = any (public._agenda_payees_do_usuario(p_user_id))
     and so.status <> 'cancelled'
     and so.id is distinct from p_exclude_so
     and a.periodo && tstzrange(p_start, p_end)
     and not exists (select 1 from service_order_technicians sot where sot.service_order_id = so.id and sot.user_id = p_user_id);
$function$;

comment on function public.get_agenda_conflicts(uuid, timestamptz, timestamptz, uuid, uuid) is
  'Conflitos de agenda de um login no intervalo: compromissos (task) e OS em que é técnico (service_order). Agenda de Produção (Fase 2, P5): a OS com alocação vigente ocupa só os períodos das alocações dela (o turno, não a janela corrida); a sem alocação, a janela corrida; e o ramo alocacao traz os meios-dias do payee ligado ao login (o dono, pelo sócio) em OS em que ele não é técnico.';

-- ── Portas ─────────────────────────────────────────────────────────────────────────────────────────────
-- A view: authenticated (a RLS de agenda_alocacoes vale) e service_role; nunca anon.
revoke all on public.v_agenda_dia from public, anon, authenticated;
grant select on public.v_agenda_dia to authenticated, service_role;

-- Leituras e textos (security invoker, STABLE/IMMUTABLE) e as duas definer que só devolvem o que quem lê pode ver:
-- authenticated (o painel, a tela, a view) e service_role (o WhatsApp, o fechamento); nunca anon.
revoke all on function
  public._agenda_pessoa(uuid), public._agenda_payees_do_usuario(uuid), public._agenda_pessoas_do_dia(jsonb),
  public.agenda_linhas_do_dia(date, integer, date), public._agenda_marcados(date, date, date, uuid, uuid),
  public._agenda_parte_da_pessoa(jsonb), public.agenda_dia_da_pessoa(uuid, date, date),
  public._agenda_mudancas(date, date, boolean, boolean, timestamptz), public._agenda_mudanca_texto(jsonb, boolean),
  public._agenda_ver_decisoes(date, timestamptz), public._agenda_ver_mudancas(date, timestamptz),
  public._agenda_ver_plano(date, date, date, timestamptz),
  public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date),
  public._agenda_linha_da_semana(uuid, jsonb, boolean, date), public._agenda_linhas_do_fechamento(date),
  public.agenda_textos_do_fechamento(date, date), public.agenda_estado_das_os(date),
  public.get_agenda_conflicts(uuid, timestamptz, timestamptz, uuid, uuid)
  from public, anon;
grant execute on function
  public._agenda_pessoa(uuid), public._agenda_payees_do_usuario(uuid), public._agenda_pessoas_do_dia(jsonb),
  public.agenda_linhas_do_dia(date, integer, date), public._agenda_marcados(date, date, date, uuid, uuid),
  public._agenda_parte_da_pessoa(jsonb), public.agenda_dia_da_pessoa(uuid, date, date),
  public._agenda_mudancas(date, date, boolean, boolean, timestamptz), public._agenda_mudanca_texto(jsonb, boolean),
  public._agenda_ver_decisoes(date, timestamptz), public._agenda_ver_mudancas(date, timestamptz),
  public._agenda_ver_plano(date, date, date, timestamptz),
  public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date),
  public._agenda_linha_da_semana(uuid, jsonb, boolean, date), public._agenda_linhas_do_fechamento(date),
  public.agenda_textos_do_fechamento(date, date), public.agenda_estado_das_os(date),
  public.get_agenda_conflicts(uuid, timestamptz, timestamptz, uuid, uuid)
  to authenticated, service_role;

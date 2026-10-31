-- Agenda de Produção, Fase 7, etapa 7b ("os dias de verdade de quem trabalha e a dupla pela tarefa"), pacote P6: quem chamar e a
-- dupla completa — a sugestão de quem chamar (a dupla sem a 2ª pessoa, o prazo firme que só fecha com um ajudante junto do técnico e
-- o trabalho que passa a caber com mais uma pessoa), o passo que põe a 2ª pessoa na dupla quando o dono diz os dias do ajudante (e
-- marca a dupla dita que esperava) e o texto do corte que a dupla completa encurta.
-- Spec: scratchpad agenda-pesquisa/spec-fase7b.md (§R4.2(b), §R4.3(a)(f), §R4.4 inteiro, §R4.6, §R4.7 P6, §R4.9-4/5); nomes:
-- fase7-registro.md §1 e §2 (7b P6); respostas do dono: fase7-padroes.md (CONFIRMAÇÕES NO FIO: Mateus e Vinicius sob demanda, "o
-- gestor SUGERE quando chamar (ex.: dupla necessária, prazo apertado) e o dono confirma; nunca escala direto"; AG7-04 1 pessoa, dupla
-- só onde a tarefa pede).
-- Depende das Fases 1 a 6, do lote de 30/10, da 7a inteira (20261031100000 .. 100985 e o dado 100990) e do 7b P1 a P5
-- (20261101100000 .. 100400: modo_chamar, chamar_min_meios, chamar_max_os e agenda_gestor_dia.chamar do P1; a pergunta dias_semana e
-- _agenda_dias_semana_motivos do P3; o motor com o dk, o bloco de 1 pessoa, o fora dupla e o gancho agenda.pessoa_extra do P4;
-- _agenda_dupla_no_plano do P5).
--
-- ═══ DDL — OK NOMEADO ═══ (5 funções novas, 6 recriadas com as mesmas assinaturas; nenhuma tabela, coluna, lista ou dado)
-- NÃO APLICADA. Existe para revisão e espera o OK do dono. Este arquivo foi MONTADO por
-- scratchpad/agenda-pesquisa/f7b/p6/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (conferida a cada montagem:
-- o montador para se outra migration a definir depois da origem), e as mudanças estão só nos blocos "-- FASE 7b: … -- FASE 7b: fim"
-- (só acréscimo: nenhuma linha de antes muda; tirados os blocos, o corpo é o da origem, byte a byte).
--
-- POR QUE: com o Alex sozinho na equipe, o P4 marca a dupla pela tarefa com 1 pessoa e diz na marcação em que meios-dias chamar um
-- ajudante, e a dupla que o dono disse espera a 2ª pessoa. Faltava o resto do "o gestor sugere quem chamar": juntar num lugar só (o
-- foco *agenda gestor*, a pergunta da quinta e o *livre*) quantos meios-dias de mais uma pessoa fazem caber o que está sem lugar, e
-- quando um prazo firme só fecha com um ajudante junto do técnico; e, quando o dono diz os dias do ajudante ("Mateus vem ter 10/11"),
-- pôr o ajudante na dupla que ia com 1 (e marcar a dita que esperava) no tique seguinte, sem esperar a quinta. A pessoa a mais é só
-- simulação: nunca é gravada, e o gestor nunca escala ninguém.
--
-- O QUE MUDA:
--   1. Nova _agenda_dupla_faltando(p_os, p_hoje): os meios-dias do plano da dupla pela tarefa (fonte regra) sem a 2ª pessoa, de hoje
--      em diante, fora da reserva — o filtro de _agenda_dupla_no_plano (P5), com o motivo e o dia avisado (travado).
--   2. Nova _agenda_meios_frase(p_meios, p_conta): os meios-dias por extenso ("em ter 10/11 (manhã e tarde)", "de seg 16 a qua
--      18/11 (6 meios-dias)"), para as frases de quem chamar e do passo dupla.
--   3. Nova _agenda_quem_chamar(p_hoje, p_agora): a sugestão, sem gravar nada — a dupla (a pela tarefa marcada com 1 pessoa; a dita
--      que espera, pelo bloco que o técnico faria sozinho, agenda_encaixe_do_novo), o prazo (a OS com prazo firme que, com 1 pessoa,
--      passa dele e, com um ajudante junto do técnico, cumpre — a dupla rende 2) e a capacidade (o motor sem gravar sobre a carteira
--      sem compromisso; o que fica sem lugar; a mesma conta com mais uma pessoa que trabalhe sozinha, agenda.pessoa_extra =
--      tecnico; os meios-dias das OS que passam a caber). Os textos do foco, da pergunta da quinta e do *livre*.
--   4. Nova _agenda_gestor_chamar(p_hoje, p_agora): o passo diário chamar do agenda-gestor (depois de sombra): grava a sugestão no
--      diário do dia (agenda_gestor_dia.chamar). modo_chamar desligado = {pulado}.
--   5. Nova _agenda_gestor_dupla(p_hoje, p_agora): o passo de todo tique dupla: com modo_dupla e o gestor que marca ligados, põe a
--      2ª pessoa (quem o dono disse para a data, depois quem tem dias fixos; livre; validada pelas 14 regras) nos meios-dias da dupla
--      pela tarefa que foram com 1 (a ação reparar, desfazível) e marca a dupla dita que esperava e agora tem a 2ª pessoa por quem
--      vem sob demanda (_agenda_propor_e_aplicar); em teste, só conta.
--   6. agenda_gestor_rodar (de 20261031100800): o passo dupla em todo tique (com modo_dupla fora de desligado) e o chamar nos diários,
--      depois de sombra (com modo_chamar fora de desligado).
--   7. _agenda_gestor_dia_gravar (de 20261031100000): a chave chamar (objeto).
--   8. _agenda_ver_gestor (de 20261031100985): o bloco "Quem chamar" depois de "Perguntei antes de marcar"; com modo_dupla fora de
--      desligado, o "Pode precisar de dupla (…): … diga *Lenine com dupla*" do 7a vira a frase da dupla de 1 pessoa.
--   9. agenda_livre_de_verdade (de 20261031100980): com modo_chamar ligado, a linha "Sem lugar com a equipe de hoje: …" no fim.
--  10. _agenda_dias_semana_motivos (de 20261101100200, o P3): o motivo chamar, lido do diário de hoje.
--  11. _agenda_gestor_corte (de 20261031100980): o texto do corte quando a sobra vem da dupla completada ("com Mateus junto em ter
--      10/11, o serviço acaba antes (são as mesmas diárias)"), não "o orçamento mudou".
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7b_chamar.sql; registradas em notas-fase77b.md, P6):
--   · A 1ª conta do quem chamar aceita o atraso das OS com prazo firme (aceitar_atraso): o motor de verdade tira a OS que não cabe no
--     prazo e pergunta "não cabe" (sem bloco); sem isso não há o bloco de 1 pessoa que passa do prazo para medir o ajudante. A 2ª
--     conta (com a pessoa a mais) aceita o mesmo.
--   · O "Se chamar, diga: Mateus vem …" leva as DATAS ("Mateus vem seg 16 a qua 18/11"), não só os dias da semana: dito na quinta, o
--     rascunho lê "seg, ter e qua" como a 1ª semana em que os três ainda vêm (a semana que vem), não a do prazo.
--   · O depois.motivo = 'dupla_completa' da ação não existe: agenda_acoes é imutável depois de gravada e agenda_aplicar monta o depois
--     sem motivo. A marca fica na proposta (parametros.gestor.motivo = 'dupla_completa') e nas alocações (motivos ['dupla_completa']).
--   · O texto da pergunta e o do foco para a dupla e o prazo seguem o molde da spec; os que ela não dava (a dupla na pergunta da
--     quinta, a dita esperando, o dia já avisado, o "e mais N", a forma curta) foram escritos curtos, sem jargão.
--   · _agenda_meios_frase é nova (a spec não a nomeava): as frases do quem chamar e do passo dupla dizem os meios-dias do mesmo jeito.
--   · A 2ª pessoa da dupla é validada (e aplicada) acima da carga: o teto de 100% da pessoa, sem o teto da equipe-semana da 7a. O
--     bloco de 1 pessoa já ocupa a semana do técnico até o teto da equipe, e a dupla acrescenta o que a revisão do dia seguinte corta
--     no fim (as mesmas diárias-pessoa); sem isso, a dupla nunca se completaria na semana cheia (o Lenine com o Mateus: 10
--     meios-dias de serviço para 9).
--   · A dita que esperava é achada pela régua dos técnicos (a 2ª pessoa só por quem vem sob demanda: o dupla_sd do P4), não pela
--     última montagem que a citou: a dita pelo dono depois da última montagem (*Vanderlei com dupla*) também entra no tique seguinte.
--   · Na linha da dupla do foco, com alguém já livre nos meios-dias que faltam, "Mateus está livre nesses meios-dias." (o passo dupla
--     o põe), e não "só Alex está na equipe … Se chamar, diga"; no dia já avisado, só "Em ter 10/11 eu não mexo: o dia já foi avisado.".
--   · A dupla dita "o tempo todo" que o Mateus completa usa floor(pm / 2) meios-dias de 2 pessoas (o molde do P4); a sugestão do prazo,
--     ceil(pm / 2) (a spec): o aviso pede meio dia a mais, nunca a menos.
--   · O passo dupla, em teste, devolve {pulado, em_teste} (só conta): a saúde do P5 só conta o zero dupla_incompleta_com_gente_livre
--     depois de um tique que de fato completa (sem "pulado"). A dita que esperava só é refeita quando os dias de alguém mudam (a
--     marca fp das linhas de disponibilidade vivas na rodada): sem isso, a dita que não cabe (o fora dupla) viraria uma proposta nova
--     a cada 15 minutos.
--
-- ORDEM DE LIGAR: nada muda com modo_chamar e modo_dupla desligados (como a migration nasce): o agenda-gestor roda os passos de antes,
-- o foco e o *livre* são os de antes. O dado 20261101100900 (P5, OK nomeado) põe os modos em sombra: o foco *agenda gestor* mostra
-- "Em teste: quem chamar …"; o passo dupla só conta. "OK ligar quem chamar" (modo_chamar) junto do "OK ligar a dupla" (modo_dupla):
-- daí a pergunta da quinta e o *livre* levam a sugestão, e a dupla ganha a 2ª pessoa no tique seguinte ao *grava* dos dias dele.
--
-- PROVA: supabase/tests/agenda_fase7b_chamar.sql (na bancada: node scripts/bancada-agenda/rodar.mjs); depois do deploy, só leitura:
-- supabase/tests/agenda_fase7b_pos_deploy.sql.
-- APLICAR (só com o OK do dono, depois das do 7b P1 a P5): npx supabase@2.111.0 db push (ou o roteiro de publicar da etapa,
-- fila-do-dono/fase7b-oks.md).
--
-- DESFAZER: modo_chamar e modo_dupla em desligado (os passos saem da rodada; o foco, o *livre* e a pergunta da quinta voltam ao de
-- antes; a dupla completada fica: *desfaz <nome>* tira). Para tirar o código: recriar cada uma das 6 com o corpo da origem (o
-- comentário de cada uma diz qual), a cópia sem os blocos "-- FASE 7b:"; e
--   drop function if exists public._agenda_gestor_dupla(date, timestamptz), public._agenda_gestor_chamar(date, timestamptz),
--     public._agenda_quem_chamar(date, timestamptz), public._agenda_dupla_faltando(uuid, date), public._agenda_meios_frase(jsonb, boolean);
-- (só depois de recriar agenda_gestor_rodar sem o bloco, que as chama pelo nome do passo).
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.
-- Quem recriar depois copia DESTA migration (spec §R4.6, fim): _agenda_ver_gestor, agenda_livre_de_verdade (o 7g P4),
-- agenda_gestor_rodar, _agenda_gestor_dia_gravar, _agenda_dias_semana_motivos e _agenda_gestor_corte.

-- ── 1. As funções novas ────────────────────────────────────────────────────────────────────────────────────────

-- Os meios-dias por extenso (as frases de quem chamar e do passo dupla): um dia só, com os turnos ("em ter 10/11 (manhã e tarde)",
-- "em ter 10/11 de manhã"); vários dias inteiros, pelas datas e quantos meios-dias ("de seg 16 a qua 18/11 (6 meios-dias)", "em qua
-- 11 e qui 12/11 (4 meios-dias)"; sem p_conta, sem a conta; sem o parêntese do feriado entre dois dias seguidos que
-- _agenda_dias_texto acrescenta); senão, dia a dia com os turnos.
create or replace function public._agenda_meios_frase(p_meios jsonb, p_conta boolean default true)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  with m as (
    select distinct (e ->> 'dia')::date as d, e ->> 'turno' as t
      from jsonb_array_elements(case when jsonb_typeof(p_meios) = 'array' then p_meios else '[]'::jsonb end) e
     where e ->> 'dia' is not null and e ->> 'turno' in ('manha', 'tarde')
  ), g as (
    select m.d, bool_or(m.t = 'manha') as manha, bool_or(m.t = 'tarde') as tarde from m group by m.d
  )
  select case
    when (select count(*) from g) = 0 then ''
    when (select count(*) from g) = 1 then
      (select 'em ' || public._dia_curto(g.d)
              || case when g.manha and g.tarde then ' (manhã e tarde)' when g.manha then ' de manhã' else ' à tarde' end from g)
    when (select bool_and(g.manha and g.tarde) from g) then
      (select case when public._agenda_dias_texto(array_agg(g.d)) ~ '^\S+ \S+ a ' then 'de ' else 'em ' end
              || regexp_replace(public._agenda_dias_texto(array_agg(g.d)), ' \([^()]*\)$', '')
              || case when coalesce(p_conta, true)
                      then format(' (%s)', public._agenda_plural((count(*) * 2)::int, 'meio-dia', 'meios-dias')) else '' end
         from g)
    else 'em ' || public._agenda_lista(array(
           select public._dia_curto(g.d)
                  || case when g.manha and g.tarde then ' (manhã e tarde)' when g.manha then ' de manhã' else ' à tarde' end
             from g order by g.d), null) end;
$function$;

comment on function public._agenda_meios_frase(jsonb, boolean) is
  'Agenda de Produção (Fase 7b, P6; R4.4): os meios-dias [{dia, turno}] por extenso para as frases de quem chamar e do passo dupla — um dia só com os turnos ("em ter 10/11 (manhã e tarde)", "em ter 10/11 de manhã"); vários dias inteiros pelas datas (_agenda_dias_texto) e, com p_conta, quantos meios-dias ("de seg 16 a qua 18/11 (6 meios-dias)"); senão, dia a dia com os turnos. Vazio = texto vazio. STABLE, invoker, sem grant (só as funções do P6 a chamam).';

-- A dupla pela tarefa sem a 2ª pessoa no plano (R4.4 item 1): com modo_dupla fora de desligado e a dupla de fonte regra, os meios-dias
-- de turno vigentes que não são reserva, de hoje em diante, nas posições da dupla do molde (as ni primeiras e as nf últimas de turno da
-- OS, contando as cumpridas; o tempo todo = todas), com menos de 2 pessoas (o dono só conta com dk_dono_conta). É o filtro de
-- _agenda_dupla_no_plano (P5), que já faz a conta; aqui ganha o motivo (o que a tarefa pede) e o dia avisado (travado).
create or replace function public._agenda_dupla_faltando(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_pl jsonb;
  v_d  jsonb;
begin
  if p_os is null or p_hoje is null then
    raise exception '_agenda_dupla_faltando: sem a OS ou o dia de hoje' using errcode = '22004';
  end if;
  if (public._agenda_cfg()).modo_dupla = 'desligado' then
    return '[]'::jsonb;
  end if;
  v_pl := public._agenda_dupla_no_plano(p_os, p_hoje);
  if v_pl ->> 'fonte' is distinct from 'regra' then
    return '[]'::jsonb;
  end if;
  v_d := public._agenda_dupla_da_os(p_os);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'dia', e -> 'dia', 'turno', e -> 'turno', 'onde', e -> 'onde', 'pede', e -> 'pede', 'tem', e -> 'tem',
             'motivo', case when e ->> 'onde' = 'todos'
                            then (select m ->> 'frase' from jsonb_array_elements(coalesce(v_d -> 'motivos', '[]'::jsonb)) m
                                   where m ->> 'onde' = 'todos' limit 1)
                            else public._agenda_lista(array(select distinct on (m ->> 'motivo') m ->> 'frase'
                                                              from jsonb_array_elements(coalesce(v_d -> 'motivos', '[]'::jsonb)) m
                                                             where m ->> 'onde' = e ->> 'onde' order by m ->> 'motivo')) end,
             'travado', e -> 'travado', 'pessoas', e -> 'pessoas')
           order by (e ->> 'dia')::date, e ->> 'turno')
      from jsonb_array_elements(coalesce(v_pl -> 'faltam', '[]'::jsonb)) e
     where not coalesce((e ->> 'reserva')::boolean, false)), '[]'::jsonb);
end;
$function$;

comment on function public._agenda_dupla_faltando(uuid, date) is
  'Agenda de Produção (Fase 7b, P6; R4.4 item 1): os meios-dias do plano em que a dupla pela tarefa (fonte regra) está sem a 2ª pessoa — com modo_dupla fora de desligado, os de turno vigentes, fora da reserva, de hoje em diante, nas posições da dupla do molde (as ni primeiras e as nf últimas de turno da OS, contando as cumpridas; o tempo todo = todas), com menos de 2 pessoas (o dono só conta com dk_dono_conta): o filtro de _agenda_dupla_no_plano (P5). [{dia, turno, onde (inicio|fim|todos), pede 2, tem, motivo (o que a tarefa pede: "a troca do banco de baterias"; no tempo todo, "o orçamento previu 2 técnicos"), travado (o dia já dito à equipe ou ao cliente: a zona travada do 7a, _agenda_dia_avisado), pessoas (quem já está)}]. A dita pelo dono, desligado ou sem dupla = []. STABLE, invoker, sem grant (só _agenda_quem_chamar e _agenda_gestor_dupla a chamam).';

-- Quem chamar (R4.4 item 2): a sugestão do gestor, sem gravar nada. A dupla, o prazo e a capacidade; os textos do foco *agenda gestor*,
-- da pergunta da quinta (as partes, cada uma com os dias, para o motivo chamar) e do *livre*. Escreve a variável agenda.pessoa_extra
-- (só aqui, sempre de volta a vazio) e, com o gestor que marca em teste, agenda.gestor = sombra (as regras do gestor na conta, como a
-- sombra dele; de volta a vazio no fim).
create or replace function public._agenda_quem_chamar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_t0     timestamptz := clock_timestamp();
  v_dono   uuid := public._agenda_dono(null);
  -- com o gestor que marca em teste, a conta é a que ele faria (as regras dele valem só aqui dentro, como na sombra)
  v_simula boolean := public._agenda_gestor_modo('marcar') = 'sombra'
                      and coalesce(current_setting('agenda.gestor', true), '') <> 'sombra';
  v_cart   uuid[];
  v_prazos jsonb := '{}'::jsonb;
  v_restr  jsonb;
  v_p1     jsonb := '{}'::jsonb;
  v_p2     jsonb := '{}'::jsonb;
  v_tec    text[];
  v_tecf   text;
  v_tp     jsonb;
  v_hor    date;
  v_dupla  jsonb := '[]'::jsonb;
  v_prazo  jsonb := '[]'::jsonb;
  v_sem    jsonb := '[]'::jsonb;
  v_cabem  jsonb := '[]'::jsonb;
  v_extra  jsonb;
  v_partes jsonb := '[]'::jsonb;
  v_lin    text[] := '{}';
  v_perg   text[] := '{}';
  v_texto  text;
  v_livre  text;
  v_txt    text;
  v_pt     text;
  v_os     uuid;
  v_pz     date;
  v_m      jsonb;
  v_d      jsonb;
  v_e      jsonb;
  v_f      jsonb;
  v_bl     jsonb;
  v_sl     jsonb;
  v_pm     int;
  v_n2     int;
  v_n      int;
  v_k      int;
  v_meios  int;
  v_dias   numeric;
  v_ate    date;
  v_nomes  text[];
  v_ondes  text[];
  v_frases text[];
  v_dn     date[];
  v_dt     date[];
  v_semt   text;
  v_cabt   text;
  v_tlist  text;
  x        jsonb;
  y        jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_quem_chamar: sem o dia ou a hora' using errcode = '22004';
  end if;
  -- a carteira sem compromisso de hoje em diante (a mesma da sombra do gestor) e o prazo firme de cada OS (o que o cliente pediu ou
  -- o prometido firme, o que vier antes)
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k
                   where not public._agenda_os_tem_dia(k.service_order_id, p_hoje)
                   order by k.numero, k.service_order_id);
  select coalesce(jsonb_object_agg(pl.service_order_id::text, z.prazo), '{}'::jsonb) into v_prazos
    from public.os_planejamento pl
    cross join lateral (select least(pl.precisa_ate, case when pl.prometido_tipo = 'firme' then pl.prometido_ate end) as prazo) z
   where pl.service_order_id = any (v_cart) and z.prazo is not null;
  -- as duas contas aceitam o atraso de quem tem prazo firme: o motor de verdade tira a OS que não cabe no prazo e pergunta (não
  -- cabe); aqui ela entra, para o bloco de 1 pessoa que passa do prazo sair na conta
  v_restr := jsonb_build_object('aceitar_atraso', (select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from jsonb_object_keys(v_prazos) k));
  v_tec := public._agenda_tecnicos_da_grade(p_hoje);
  v_tecf := case when cardinality(v_tec) >= 2 then 'ninguém mais está livre nesses meios-dias' else public._agenda_tecnicos_frase(v_tec) end;
  -- o técnico da grade (o 1º de dias fixos, sem o dono): o bloco que ele faria sozinho na dita que espera
  v_tp := (select q.e from jsonb_array_elements(coalesce(public.agenda_capacidade_semanal(p_hoje) -> 'pessoas', '[]'::jsonb))
                           with ordinality q(e, o)
            where not coalesce((q.e ->> 'eh_dono')::boolean, false) order by q.o limit 1);

  begin
    if v_simula then
      perform set_config('agenda.gestor', 'sombra', true);
    end if;
    -- 1ª conta: a equipe de hoje, sem gravar nada
    if cardinality(v_cart) > 0 then
      v_p1 := public.agenda_propor('os', null, null, v_cart, v_restr, false, 'vigia', null, p_hoje, p_agora);
    end if;
    v_hor := greatest(p_hoje + 7 * cf.horizonte_semanas, coalesce((v_p1 #>> '{periodo,ate}')::date, p_hoje));

    -- (prazo) a OS com prazo firme cujo bloco de 1 pessoa passa dele: com um ajudante junto do técnico, a dupla rende 2 (d7) e o
    -- serviço leva ceil(pm / 2) meios-dias nos mesmos meios-dias, do início do bloco em diante; cumpre o prazo = a sugestão do
    -- prazo; senão, fica sem lugar (passa do prazo)
    for x in select e from jsonb_array_elements(coalesce(v_p1 -> 'itens', '[]'::jsonb)) e
              where e ->> 'op' = 'criar' and e ->> 'tipo' <> 'reserva' and v_prazos ? (e ->> 'os')
              order by e ->> 'numero', e ->> 'os' loop
      v_os := (x ->> 'os')::uuid;
      v_pz := (v_prazos ->> v_os::text)::date;
      continue when (x ->> 'ate')::date <= v_pz;
      v_m := public.agenda_meios_da_os(v_os, p_hoje);
      v_pm := coalesce((v_m #>> '{dupla,pm}')::int, (v_m ->> 'total')::int * coalesce((v_m ->> 'pessoas_sugeridas')::int, 1));
      select coalesce(jsonb_agg(jsonb_build_object('dia', s.dia, 'turno', s.turno) order by s.dia, s.turno), '[]'::jsonb) into v_bl
        from (select distinct (a ->> 'dia')::date as dia, a ->> 'turno' as turno
                from jsonb_array_elements(coalesce(x -> 'alocacoes', '[]'::jsonb)) a
               where coalesce(a ->> 'presenca', 'turno') = 'turno') s;
      v_nomes := array(select z.q from (select case when (a ->> 'payee_id')::uuid is not distinct from v_dono then 'você' else a ->> 'nome' end as q,
                                               min((a ->> 'dia')::date) as d0
                                          from jsonb_array_elements(coalesce(x -> 'alocacoes', '[]'::jsonb)) a
                                         where coalesce(a ->> 'presenca', 'turno') = 'turno' group by 1) z order by z.d0, z.q);
      v_n2 := ceil(coalesce(v_pm, 0)::numeric / 2)::int;
      if coalesce(v_pm, 0) >= 2 and jsonb_array_length(v_bl) >= v_n2 and (v_bl -> (v_n2 - 1) ->> 'dia')::date <= v_pz then
        v_prazo := v_prazo || jsonb_build_object(
          'os', v_os, 'numero', x ->> 'numero', 'cliente', x ->> 'cliente_curto', 'prazo', v_pz, 'fim_hoje', (x ->> 'ate')::date,
          'fim_com_ajudante', (v_bl -> (v_n2 - 1) ->> 'dia')::date, 'pm', v_pm, 'tecnicos', to_jsonb(v_nomes),
          'meios', (select jsonb_agg(b.e order by b.o) from jsonb_array_elements(v_bl) with ordinality b(e, o) where b.o <= v_n2));
      else
        v_sem := v_sem || jsonb_build_object('os', v_os, 'numero', x ->> 'numero', 'cliente', x ->> 'cliente_curto', 'pm', v_pm,
                                             'fim_hoje', (x ->> 'ate')::date, 'prazo', v_pz);
      end if;
    end loop;
    -- (capacidade) o que fica sem lugar no horizonte
    for x in select f from jsonb_array_elements(coalesce(v_p1 -> 'fora', '[]'::jsonb)) f
              where f ->> 'motivo' in ('sem_encaixe', 'nao_cabe') order by f ->> 'numero', f ->> 'os' loop
      v_os := (x ->> 'os')::uuid;
      v_m := public.agenda_meios_da_os(v_os, p_hoje);
      v_sem := v_sem || jsonb_build_object(
        'os', v_os, 'numero', x ->> 'numero', 'cliente', x ->> 'cliente_curto',
        'pm', coalesce((v_m #>> '{dupla,pm}')::int, (v_m ->> 'total')::int * coalesce((v_m ->> 'pessoas_sugeridas')::int, 1)),
        'fim_hoje', null, 'prazo', v_prazos -> v_os::text);
    end loop;
    select coalesce(jsonb_agg(s order by s ->> 'numero', s ->> 'os'), '[]'::jsonb) into v_sem from jsonb_array_elements(v_sem) s;

    -- 2ª conta: a mesma, com mais uma pessoa que trabalhe sozinha (o gancho do P4: nunca gravada; a variável volta a vazio). A conta
    -- é do trabalho que passa a caber, não do uso da pessoa a mais: o motor guloso pode pô-la em qualquer OS.
    if jsonb_array_length(v_sem) > 0 then
      perform set_config('agenda.pessoa_extra', 'tecnico', true);
      v_p2 := public.agenda_propor('os', null, null, v_cart, v_restr, false, 'vigia', null, p_hoje, p_agora);
      perform set_config('agenda.pessoa_extra', '', true);
    end if;

    -- (dupla, a dita que espera) a classe 4 dupla ou o "fora" dupla do R4.3(c): o bloco que o técnico da grade faria sozinho para a
    -- OS como ela é (os dias de 2 pessoas: agenda_meios_da_os.total / 2), os meios-dias da dupla nele, menos os que quem vem sob
    -- demanda já tem livres
    for x in select f from jsonb_array_elements(coalesce(v_p1 -> 'fora', '[]'::jsonb)) f
              where f ->> 'motivo' = 'dupla' order by f ->> 'numero', f ->> 'os' loop
      v_os := (x ->> 'os')::uuid;
      v_d := public._agenda_dupla_da_os(v_os);
      continue when v_d ->> 'fonte' is distinct from 'dono' or v_tp is null;
      v_m := public.agenda_meios_da_os(v_os, p_hoje);
      v_dias := coalesce((v_m ->> 'total')::numeric, 0) / 2;
      continue when v_dias <= 0;
      v_e := public.agenda_encaixe_do_novo(v_dias,
               jsonb_build_array(jsonb_build_object('payee_id', v_tp ->> 'payee_id', 'nome', v_tp ->> 'nome', 'eh_dono', false,
                                                    'turnos', 'dia')),
               case when v_m ->> 'presenca' in ('abre_e_fecha', 'sempre', 'nunca') then v_m ->> 'presenca' end, p_hoje);
      continue when not coalesce((v_e ->> 'cabe')::boolean, false);
      -- os meios-dias do bloco: manhã e tarde de cada dia, menos a manhã do 1º quando ele começa à tarde e a tarde do último que sobra
      v_n := ceil(v_dias * 2)::int;
      select coalesce(jsonb_agg(jsonb_build_object('dia', s.d, 'turno', s.t) order by s.d, s.t), '[]'::jsonb) into v_sl
        from (select dd::date as d, tt.t from jsonb_array_elements_text(coalesce(v_e -> 'dias', '[]'::jsonb)) dd,
                     unnest(array['manha', 'tarde']) tt(t)) s;
      if jsonb_array_length(v_sl) > v_n and coalesce(v_e ->> 'texto', '') like '%(começa à tarde)%' then
        v_sl := v_sl - 0;
      end if;
      while jsonb_array_length(v_sl) > v_n loop
        v_sl := v_sl - (jsonb_array_length(v_sl) - 1);
      end loop;
      select coalesce(jsonb_agg(b.e order by b.o), '[]'::jsonb) into v_sl
        from jsonb_array_elements(v_sl) with ordinality b(e, o)
       where coalesce((v_d ->> 'todos')::boolean, false) or b.o <= coalesce((v_d ->> 'inicio')::int, 0)
          or b.o > jsonb_array_length(v_sl) - coalesce((v_d ->> 'fim')::int, 0);
      select coalesce(jsonb_agg(b.e order by b.o), '[]'::jsonb) into v_sl
        from jsonb_array_elements(v_sl) with ordinality b(e, o)
       where not exists (select 1 from public.agenda_capacidade((b.e ->> 'dia')::date, (b.e ->> 'dia')::date, p_hoje) k
                          where not k.eh_dono and k.situacao = 'livre' and k.turno = b.e ->> 'turno'
                            and public._agenda_e_sob_demanda(k.payee_id, p_hoje)
                            and not exists (select 1 from public.agenda_alocacoes a
                                             where a.payee_id = k.payee_id and a.dia = k.dia and a.turno = k.turno
                                               and a.estado in ('publicada', 'fixada')));
      continue when jsonb_array_length(v_sl) = 0;
      v_dupla := v_dupla || jsonb_build_object(
        'os', v_os, 'numero', x ->> 'numero', 'cliente', x ->> 'cliente_curto', 'fonte', 'dono', 'marcada', false,
        'motivo', case when coalesce((v_d ->> 'todos')::boolean, false) then 'dupla o tempo todo'
                       when coalesce((v_d ->> 'inicio')::int, 0) = 1 then 'dupla no primeiro meio-dia'
                       when coalesce((v_d ->> 'inicio')::int, 0) > 1 then format('dupla nos %s primeiros meios-dias', v_d ->> 'inicio')
                       when coalesce((v_d ->> 'fim')::int, 0) = 1 then 'dupla no último meio-dia'
                       else format('dupla nos %s últimos meios-dias', v_d ->> 'fim') end,
        'cabe_de', v_e -> 'de', 'meios', v_sl);
    end loop;
  exception when others then
    perform set_config('agenda.pessoa_extra', '', true);
    if v_simula then
      perform set_config('agenda.gestor', '', true);
    end if;
    raise;
  end;
  if v_simula then
    perform set_config('agenda.gestor', '', true);
  end if;

  -- (capacidade) as OS sem lugar que passam a caber na 2ª conta (com prazo: até ele) e os meios-dias de turno delas (de quem for)
  for x in select s from jsonb_array_elements(v_sem) s loop
    y := (select i from jsonb_array_elements(coalesce(v_p2 -> 'itens', '[]'::jsonb)) i
           where i ->> 'os' = x ->> 'os' and i ->> 'op' = 'criar' and i ->> 'tipo' <> 'reserva' limit 1);
    continue when y is null or (x ->> 'prazo' is not null and (y ->> 'ate')::date > (x ->> 'prazo')::date);
    v_cabem := v_cabem || jsonb_build_object(
      'os', x -> 'os', 'numero', x ->> 'numero', 'cliente', x ->> 'cliente', 'de', y -> 'de', 'ate', y -> 'ate',
      'alocs', (select coalesce(jsonb_agg(jsonb_build_object('dia', a -> 'dia', 'turno', a -> 'turno')), '[]'::jsonb)
                  from jsonb_array_elements(coalesce(y -> 'alocacoes', '[]'::jsonb)) a where coalesce(a ->> 'presenca', 'turno') = 'turno'));
  end loop;
  v_meios := (select count(*) from jsonb_array_elements(v_cabem) c, jsonb_array_elements(c -> 'alocs') a)::int;
  if jsonb_array_length(v_cabem) > 0 and v_meios >= cf.chamar_min_meios then
    v_extra := jsonb_build_object(
      'meios_total', v_meios,
      'semanas', (select jsonb_agg(jsonb_build_object('seg', w.seg, 'meios', w.n) order by w.seg)
                    from (select (a ->> 'dia')::date - (extract(isodow from (a ->> 'dia')::date)::int - 1) as seg, count(*)::int as n
                            from jsonb_array_elements(v_cabem) c, jsonb_array_elements(c -> 'alocs') a group by 1) w),
      'os', (select jsonb_agg(jsonb_build_object('os', c -> 'os', 'de', c -> 'de', 'ate', c -> 'ate') order by c ->> 'numero')
               from jsonb_array_elements(v_cabem) c));
  end if;

  -- (dupla, a pela tarefa marcada com 1 pessoa) os meios-dias do plano sem a 2ª pessoa
  for v_os in select distinct a.service_order_id from public.agenda_alocacoes a
               where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno' and a.dia >= p_hoje
               order by 1 loop
    v_f := public._agenda_dupla_faltando(v_os, p_hoje);
    continue when jsonb_array_length(v_f) = 0;
    v_d := public._agenda_dupla_da_os(v_os);
    v_ondes := array(select distinct e ->> 'onde' from jsonb_array_elements(v_f) e);
    v_frases := array(select distinct on (m ->> 'motivo') m ->> 'frase' from jsonb_array_elements(coalesce(v_d -> 'motivos', '[]'::jsonb)) m
                       where m ->> 'onde' = any (v_ondes) and m ->> 'onde' <> 'todos' order by m ->> 'motivo');
    v_dupla := v_dupla || jsonb_build_object(
      'os', v_os, 'numero', (select so.service_order_number from public.service_orders so where so.id = v_os),
      'cliente', coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so join public.clients cl on cl.id = so.client_id
                            where so.id = v_os), (select so.service_order_number from public.service_orders so where so.id = v_os)),
      'fonte', 'regra', 'marcada', true,
      'motivo', case when 'todos' = any (v_ondes) then (select e ->> 'motivo' from jsonb_array_elements(v_f) e where e ->> 'onde' = 'todos' limit 1)
                     else public._agenda_lista(v_frases) end,
      'pede', case when 'todos' = any (v_ondes)
                   then format('o serviço todo pede 2 pessoas (%s)', (select e ->> 'motivo' from jsonb_array_elements(v_f) e where e ->> 'onde' = 'todos' limit 1))
                   else format('%s %s 2 pessoas', public._agenda_lista(v_frases), case when cardinality(v_frases) > 1 then 'pedem' else 'pede' end) end,
      'tecnicos', (select coalesce(jsonb_agg(z.q order by z.q), '[]'::jsonb)
                     from (select distinct case when p::uuid is not distinct from v_dono then 'você' else public._agenda_nome_curto(py.name) end as q
                             from jsonb_array_elements(v_f) e cross join lateral jsonb_array_elements_text(coalesce(e -> 'pessoas', '[]'::jsonb)) p
                             join public.payees py on py.id = p::uuid) z),
      'meios', (select jsonb_agg(jsonb_build_object('dia', e -> 'dia', 'turno', e -> 'turno', 'travado', e -> 'travado') order by o)
                  from jsonb_array_elements(v_f) with ordinality t(e, o)));
  end loop;
  -- a marcada antes (pelo 1º meio-dia), depois a dita que espera (pelo número)
  select coalesce(jsonb_agg(e order by not (e ->> 'marcada')::boolean, e #>> '{meios,0,dia}', e ->> 'numero'), '[]'::jsonb) into v_dupla
    from jsonb_array_elements(v_dupla) e;

  -- ── Os textos: o foco (uma linha por sugestão, até chamar_max_os por parte), a pergunta da quinta (as partes, com os dias) e o
  -- *livre*. Só sugere: quem chama é o dono ("Se chamar, diga: …" com as datas, que o rascunho lê como datas)
  v_k := 0;
  for x in select e from jsonb_array_elements(v_dupla) e loop
    v_k := v_k + 1;
    exit when v_k > cf.chamar_max_os;
    v_dn := array(select distinct (m ->> 'dia')::date from jsonb_array_elements(x -> 'meios') m
                   where not coalesce((m ->> 'travado')::boolean, false) order by 1);
    v_dt := array(select distinct (m ->> 'dia')::date from jsonb_array_elements(x -> 'meios') m
                   where coalesce((m ->> 'travado')::boolean, false) order by 1);
    if (x ->> 'marcada')::boolean then
      -- quem já está livre nos meios-dias que eu ainda posso completar (fora o dono e quem já vai): o passo dupla o põe; sem ninguém,
      -- quem a grade tem e o que o dono diz para chamar
      v_nomes := array(select distinct public._agenda_nome_curto(k.pessoa)
                         from jsonb_array_elements(x -> 'meios') m
                         cross join lateral public.agenda_capacidade((m ->> 'dia')::date, (m ->> 'dia')::date, p_hoje) k
                        where not coalesce((m ->> 'travado')::boolean, false) and k.turno = m ->> 'turno' and k.situacao = 'livre'
                          and not k.eh_dono and k.payee_id is distinct from v_dono
                          and not exists (select 1 from public.agenda_alocacoes a
                                           where a.payee_id = k.payee_id and a.estado in ('publicada', 'fixada')
                                             and a.periodo && public.agenda_periodo((m ->> 'dia')::date, m ->> 'turno', 'turno'))
                        order by 1);
      v_txt := format('• Ajudante para a dupla: %s %s — %s', x ->> 'cliente', public._agenda_meios_frase(x -> 'meios'), x ->> 'pede')
               || case when cardinality(v_dn) > 0 and cardinality(v_nomes) > 0
                       then format('; %s %s livre nesses meios-dias.', public._agenda_lista(v_nomes),
                                   case when cardinality(v_nomes) > 1 then 'estão' else 'está' end)
                       when cardinality(v_dn) > 0
                       then format(' e %s. Se chamar, diga: Mateus vem %s.', v_tecf,
                                   regexp_replace(public._agenda_dias_texto(v_dn), ' \([^()]*\)$', ''))
                       else '.' end
               || case when cardinality(v_dt) > 0
                       then format(' Em %s eu não mexo: %s.', regexp_replace(public._agenda_dias_texto(v_dt), ' \([^()]*\)$', ''),
                                   case when cardinality(v_dt) = 1 then 'o dia já foi avisado' else 'os dias já foram avisados' end)
                       else '' end;
      v_pt := format('%s precisa de um ajudante junto de %s %s: %s.', x ->> 'cliente',
                     coalesce(nullif(public._agenda_lista(array(select jsonb_array_elements_text(x -> 'tecnicos'))), ''), 'quem vai'),
                     public._agenda_meios_frase(x -> 'meios'), x ->> 'pede');
    else
      v_txt := format('• %s (você disse: %s) espera a 2ª pessoa: com um ajudante %s, ele cabe.', x ->> 'cliente', x ->> 'motivo',
                      public._agenda_meios_frase(x -> 'meios'));
      v_pt := format('%s (você disse: %s) só cabe com um ajudante %s.', x ->> 'cliente', x ->> 'motivo', public._agenda_meios_frase(x -> 'meios'));
    end if;
    v_lin := v_lin || v_txt;
    v_perg := v_perg || v_pt;
    v_partes := v_partes || jsonb_build_object('tipo', 'dupla', 'os', jsonb_build_array(x -> 'os'), 'nomes', jsonb_build_array(x ->> 'cliente'),
                                               'texto', v_pt, 'dias', (select coalesce(jsonb_agg(distinct m -> 'dia'), '[]'::jsonb)
                                                                        from jsonb_array_elements(x -> 'meios') m));
  end loop;
  if jsonb_array_length(v_dupla) > cf.chamar_max_os then
    v_lin := v_lin || format('• E mais %s com a dupla sem a 2ª pessoa.', jsonb_array_length(v_dupla) - cf.chamar_max_os);
  end if;
  v_k := 0;
  for x in select e from jsonb_array_elements(v_prazo) e loop
    v_k := v_k + 1;
    exit when v_k > cf.chamar_max_os;
    v_dn := array(select distinct (m ->> 'dia')::date from jsonb_array_elements(x -> 'meios') m order by 1);
    v_tlist := coalesce(nullif(public._agenda_lista(array(select jsonb_array_elements_text(x -> 'tecnicos'))), ''), 'quem vai');
    v_txt := format('• %s (prazo %s): com %s %s termina %s; com um ajudante junto %s %s, termina no prazo. Se chamar, diga: %s com dupla; Mateus vem %s.',
                    x ->> 'cliente', public._dia_curto((x ->> 'prazo')::date), v_tlist,
                    case when jsonb_array_length(x -> 'tecnicos') > 1 then 'sozinhos' else 'sozinho' end,
                    public._dia_curto((x ->> 'fim_hoje')::date), case when jsonb_array_length(x -> 'tecnicos') > 1 then 'deles' else 'dele' end,
                    public._agenda_meios_frase(x -> 'meios'), x ->> 'cliente',
                    regexp_replace(public._agenda_dias_texto(v_dn), ' \([^()]*\)$', ''));
    v_pt := format('%s só cumpre o prazo de %s com um ajudante junto de %s %s.', x ->> 'cliente', public._dia_curto((x ->> 'prazo')::date),
                   v_tlist, public._agenda_meios_frase(x -> 'meios', false));
    v_lin := v_lin || v_txt;
    v_perg := v_perg || v_pt;
    v_partes := v_partes || jsonb_build_object('tipo', 'prazo', 'os', jsonb_build_array(x -> 'os'), 'nomes', jsonb_build_array(x ->> 'cliente'),
                                               'texto', v_pt, 'dias', to_jsonb(v_dn));
  end loop;
  if jsonb_array_length(v_prazo) > cf.chamar_max_os then
    v_lin := v_lin || format('• E mais %s com prazo que só fecha com um ajudante.', jsonb_array_length(v_prazo) - cf.chamar_max_os);
  end if;
  if v_extra is not null then
    -- quem fica sem lugar até o horizonte; quem passa do prazo; as semanas; até quando as que passam a caber cabem
    v_nomes := array(select s ->> 'cliente' from jsonb_array_elements(v_sem) s where s ->> 'fim_hoje' is null order by s ->> 'numero', s ->> 'os');
    v_semt := concat_ws('; ',
      case when cardinality(v_nomes) > 0 then format('%s (só depois de %s)', public._agenda_lista(v_nomes, cf.chamar_max_os), to_char(v_hor, 'DD/MM')) end,
      nullif(public._agenda_lista(array(select format('%s (termina %s, depois do prazo de %s)', s ->> 'cliente',
                                                      public._dia_curto((s ->> 'fim_hoje')::date), public._dia_curto((s ->> 'prazo')::date))
                                          from jsonb_array_elements(v_sem) s where s ->> 'fim_hoje' is not null order by s ->> 'numero', s ->> 'os'),
                                    cf.chamar_max_os), ''));
    v_ate := (select max((c ->> 'ate')::date) from jsonb_array_elements(v_cabem) c);
    v_cabt := case when jsonb_array_length(v_cabem) = jsonb_array_length(v_sem)
                   then case jsonb_array_length(v_sem) when 1 then format('%s cabe até %s', v_sem -> 0 ->> 'cliente', to_char(v_ate, 'DD/MM'))
                                                       when 2 then format('os dois cabem até %s', to_char(v_ate, 'DD/MM'))
                                                       else format('os %s cabem até %s', jsonb_array_length(v_sem), to_char(v_ate, 'DD/MM')) end
                   else format('%s %s até %s', public._agenda_lista(array(select c ->> 'cliente' from jsonb_array_elements(v_cabem) c
                                                                           order by c ->> 'numero'), cf.chamar_max_os),
                               case when jsonb_array_length(v_cabem) = 1 then 'cabe' else 'cabem' end, to_char(v_ate, 'DD/MM')) end;
    v_txt := (select string_agg(case when w.o = 1 then 'semana de ' else 'de ' end || to_char((w.e ->> 'seg')::date, 'DD/MM') || ': ' || (w.e ->> 'meios'),
                                '; ' order by w.o)
                from jsonb_array_elements(v_extra -> 'semanas') with ordinality w(e, o));
    v_lin := v_lin || format('• Sem lugar com a equipe de hoje: %s. Com mais uma pessoa que trabalhe sozinha em %s (%s), %s.', v_semt,
                             public._agenda_plural(v_meios, 'meio-dia', 'meios-dias'), v_txt, v_cabt);
    v_nomes := array(select s ->> 'cliente' from jsonb_array_elements(v_sem) s order by s ->> 'numero', s ->> 'os');
    v_pt := format('Com a equipe de hoje, %s %s; com mais uma pessoa que trabalhe sozinha em %s (%s), %s.',
                   public._agenda_lista(v_nomes, cf.chamar_max_os),
                   case when not exists (select 1 from jsonb_array_elements(v_sem) s where s ->> 'fim_hoje' is not null)
                          then format('%s sem lugar até %s', case when cardinality(v_nomes) = 1 then 'fica' else 'ficam' end, to_char(v_hor, 'DD/MM'))
                        when not exists (select 1 from jsonb_array_elements(v_sem) s where s ->> 'fim_hoje' is null)
                          then case when cardinality(v_nomes) = 1 then 'passa do prazo' else 'passam do prazo' end
                        else 'ficam sem lugar ou passam do prazo' end,
                   public._agenda_plural(v_meios, 'meio-dia', 'meios-dias'), v_txt, v_cabt);
    v_perg := v_perg || v_pt;
    v_partes := v_partes || jsonb_build_object(
      'tipo', 'capacidade', 'os', (select jsonb_agg(c -> 'os' order by c ->> 'numero') from jsonb_array_elements(v_cabem) c),
      'nomes', to_jsonb(v_nomes), 'texto', v_pt,
      'dias', (select coalesce(jsonb_agg(distinct a -> 'dia'), '[]'::jsonb) from jsonb_array_elements(v_cabem) c, jsonb_array_elements(c -> 'alocs') a));
    v_livre := format('Sem lugar com a equipe de hoje: %s. Com mais uma pessoa %s, %s até %s (*agenda gestor* diz quando).',
                      public._agenda_lista(v_nomes, cf.chamar_max_os), public._agenda_plural(v_meios, 'meio-dia', 'meios-dias'),
                      case when jsonb_array_length(v_cabem) = jsonb_array_length(v_sem)
                           then case when jsonb_array_length(v_cabem) = 1 then 'cabe' else 'cabem' end
                           else public._agenda_lista(array(select c ->> 'cliente' from jsonb_array_elements(v_cabem) c order by c ->> 'numero'),
                                                     cf.chamar_max_os)
                                || case when jsonb_array_length(v_cabem) = 1 then ' cabe' else ' cabem' end end,
                      to_char(v_ate, 'DD/MM'));
  end if;
  v_texto := case when cardinality(v_lin) = 0 then 'Quem chamar: ninguém — a equipe de hoje dá conta da carteira que está pronta.'
                  else array_to_string(array['Quem chamar (só sugiro; quem chama é você):'] || v_lin, E'\n') end;

  return jsonb_build_object(
    'calculado_em', p_agora, 'modo', cf.modo_chamar, 'dupla', v_dupla,
    'capacidade', jsonb_build_object('sem_lugar', v_sem, 'extra', v_extra, 'horizonte', v_hor), 'prazo', v_prazo,
    'partes', v_partes, 'texto', v_texto,
    'texto_pergunta', case when cardinality(v_perg) > 0 then array_to_string(v_perg, ' ') || ' Quem chama é você.' end,
    'texto_livre', v_livre,
    'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$function$;

comment on function public._agenda_quem_chamar(date, timestamptz) is
  'Agenda de Produção (Fase 7b, P6; R4.4 item 2, R4.9-4): quem chamar — a sugestão do gestor, sem gravar nada. dupla: (i) as OS marcadas com a dupla pela tarefa sem a 2ª pessoa (_agenda_dupla_faltando) → {os, numero, cliente, fonte regra, marcada true, motivo, pede, tecnicos, meios [{dia, turno, travado}]}; (ii) a dupla dita que espera (a classe 4 dupla ou o fora dupla do R4.3(c) da 1ª conta) → o bloco que o técnico da grade faria sozinho (agenda_encaixe_do_novo com os dias de 2 pessoas, agenda_meios_da_os.total / 2), os meios-dias da dupla nele (todos; os primeiros ou os últimos dupla_meios), menos os que quem vem sob demanda já tem livres → {…, fonte dono, marcada false, cabe_de, meios}. prazo: a OS com prazo firme (precisa_ate ou o prometido firme) cujo bloco de 1 pessoa na 1ª conta passa do prazo e que, com um ajudante junto do técnico (ceil(pm / 2) meios-dias, a dupla rende 2; pm = dupla.pm ou total × pessoas), termina no prazo → {os, numero, cliente, prazo, fim_hoje, fim_com_ajudante, pm, tecnicos, meios}. capacidade: a 1ª conta (agenda_propor os sobre a carteira sem compromisso, sem gravar, com aceitar_atraso para quem tem prazo firme; as regras do gestor com ele em teste) → sem_lugar (o fora sem_encaixe e o que passa do prazo sem o ajudante resolver) [{os, numero, cliente, pm, fim_hoje (nulo = fora do horizonte), prazo}]; havendo, a 2ª conta com agenda.pessoa_extra = tecnico → extra {meios_total (os meios-dias de turno, de quem for, das OS de sem_lugar que passam a caber, com prazo até ele), semanas [{seg, meios}], os [{os, de, ate}]} só com meios_total >= chamar_min_meios; senão nulo. Textos (até chamar_max_os por parte, depois "e mais N"): texto (o foco: "Quem chamar (só sugiro; quem chama é você):" e uma linha por sugestão — "• Ajudante para a dupla: Lenine em ter 10/11 (manhã e tarde) — a troca do banco de baterias pede 2 pessoas e só Alex está na equipe. Se chamar, diga: Mateus vem ter 10/11." (com alguém já livre nesses meios-dias, "…; Mateus está livre nesses meios-dias."; no dia já avisado, "… Em ter 10/11 eu não mexo: o dia já foi avisado."), "• Lenine (você disse: dupla o tempo todo) espera a 2ª pessoa: com um ajudante de qua 11 a sex 13/11 (6 meios-dias), ele cabe.", "• Vanderlei (prazo …): com Alex sozinho termina …; com um ajudante junto dele de … (… meios-dias), termina no prazo. Se chamar, diga: Vanderlei com dupla; Mateus vem ….", "• Sem lugar com a equipe de hoje: Nelson e César (só depois de 15/12). Com mais uma pessoa que trabalhe sozinha em 9 meios-dias (semana de 09/11: 5; de 16/11: 4), os dois cabem até 20/11."; sem nada, "Quem chamar: ninguém — a equipe de hoje dá conta da carteira que está pronta."), texto_pergunta (as partes da pergunta da quinta e "Quem chama é você."; nulo sem sugestão), partes [{tipo, os, nomes, texto, dias}] (o motivo chamar de _agenda_dias_semana_motivos lê as que têm dia na semana perguntada ou depois), texto_livre (só com extra: "Sem lugar com a equipe de hoje: Nelson e César. Com mais uma pessoa 9 meios-dias, cabem até 20/11 (*agenda gestor* diz quando)."). {calculado_em, modo, dupla, capacidade {sem_lugar, extra, horizonte}, prazo, partes, texto, texto_pergunta, texto_livre, ms}. Escreve agenda.pessoa_extra só aqui (sempre de volta a vazio, também no erro) e, com o gestor que marca em teste, agenda.gestor = sombra só aqui dentro. VOLATILE, invoker, sem grant (só _agenda_gestor_chamar a chama).';

-- O passo diário chamar do agenda-gestor (R4.4 item 3; depois de sombra): a sugestão de quem chamar no diário do dia. O erro sobe ao
-- agenda_gestor_rodar, que o registra (app_error_logs, gestor:chamar) e segue; query_canceled para a rodada.
create or replace function public._agenda_gestor_chamar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf public.agenda_config := public._agenda_cfg();
  v  jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_chamar: sem o dia ou a hora' using errcode = '22004';
  end if;
  if cf.modo_chamar = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'quem chamar desligado');
  end if;
  v := public._agenda_quem_chamar(p_hoje, p_agora);
  perform public._agenda_gestor_dia_gravar(p_hoje, 'chamar', v, p_agora);
  return jsonb_build_object('modo', cf.modo_chamar, 'dupla', jsonb_array_length(v -> 'dupla'), 'prazo', jsonb_array_length(v -> 'prazo'),
                            'sem_lugar', jsonb_array_length(v #> '{capacidade,sem_lugar}'),
                            'extra_meios', v #> '{capacidade,extra,meios_total}', 'ms', v -> 'ms');
end;
$function$;

comment on function public._agenda_gestor_chamar(date, timestamptz) is
  'Agenda de Produção (Fase 7b, P6; R4.4 item 3): o passo diário chamar da rodada do gestor (agenda_gestor_rodar, depois de sombra, no 1º tique de dia útil a partir de gestor_hora_revisao: 16:53). modo_chamar desligado = {pulado}; senão _agenda_quem_chamar e o resultado inteiro (com calculado_em) no diário do dia (agenda_gestor_dia.chamar, por _agenda_gestor_dia_gravar) — o foco *agenda gestor*, o *livre* e o motivo chamar da pergunta da quinta leem dali. O erro sobe à rodada, que registra (app_error_logs, gestor:chamar) e segue; query_canceled para a rodada. {modo, dupla, prazo, sem_lugar, extra_meios, ms}. VOLATILE, invoker, sem grant (só a rodada do gestor o chama).';

-- O passo de todo tique dupla do agenda-gestor (R4.4 item 4): (i) a 2ª pessoa na dupla pela tarefa que foi com 1; (ii) a dupla dita
-- que esperava e agora tem a 2ª pessoa. Só com modo_dupla e o gestor que marca ligados (e a agenda automática ligada); em teste, só
-- conta.
create or replace function public._agenda_gestor_dupla(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_marc  text := public._agenda_gestor_modo('marcar');
  v_seco  boolean;
  v_dono  uuid := public._agenda_dono(null);
  v_cong  date;
  v_os    uuid;
  v_f     jsonb;
  v_d     jsonb;
  v_pront jsonb;
  v_novas jsonb;
  v_try   jsonb;
  v_item  jsonb;
  v_val   jsonb;
  v_tipo  text;
  v_fonte text;
  v_ult   date;
  v_ondes text[];
  v_frases text[];
  v_pede  text;
  v_cli   text;
  v_txt   text;
  v_pid   uuid;
  v_its   jsonb;
  v_exp   timestamptz;
  v_a     jsonb;
  v_usado jsonb := '[]'::jsonb;
  v_feitas jsonb := '[]'::jsonb;
  v_acoes jsonb := '[]'::jsonb;
  v_fp    text;
  v_fp0   text;
  v_ditas uuid[] := '{}';
  v_semtec int;
  v_r     jsonb;
  m       jsonb;
  c       record;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_dupla: sem o dia ou a hora' using errcode = '22004';
  end if;
  if cf.modo_dupla = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'dupla desligada');
  end if;
  if v_marc = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'o gestor desligado');
  end if;
  v_seco := cf.modo_dupla <> 'ligado' or v_marc <> 'ligado' or cf.modo_proposta <> 'ligado';
  perform set_config('agenda.hoje', p_hoje::text, true);
  if not v_seco then
    perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  end if;
  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);

  -- (i) a 2ª pessoa na dupla pela tarefa que foi com 1: em cada meio-dia de _agenda_dupla_faltando fora da zona travada, depois do
  -- congelado e que ainda não começou, a 1ª pessoa livre que não é o dono — primeiro quem o dono disse para aquela data, depois quem
  -- tem dias fixos —, sem outra coisa no meio-dia, validada pelas 14 regras (o teto) junto das outras já aceitas da OS. Nunca sozinha
  -- (o meio-dia já tem quem vai); nunca move o que já está.
  for v_os in select distinct a.service_order_id from public.agenda_alocacoes a
               where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno' and a.dia >= p_hoje
               order by 1 loop
    v_f := public._agenda_dupla_faltando(v_os, p_hoje);
    continue when jsonb_array_length(v_f) = 0;
    v_pront := public.os_prontidao(v_os, p_hoje);
    select min(a.tipo), min(a.duracao_fonte), max(a.dia) into v_tipo, v_fonte, v_ult
      from public.agenda_alocacoes a
     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje;
    v_novas := '[]'::jsonb;
    for m in select e from jsonb_array_elements(v_f) e
              where not coalesce((e ->> 'travado')::boolean, false) and (e ->> 'dia')::date > v_cong
                and lower(public.agenda_periodo((e ->> 'dia')::date, e ->> 'turno', 'turno')) > p_agora
              order by (e ->> 'dia')::date, e ->> 'turno' loop
      for c in
        select k.payee_id, public._agenda_nome_curto(k.pessoa) as nome
          from public.agenda_capacidade((m ->> 'dia')::date, (m ->> 'dia')::date, p_hoje) k
         where k.turno = m ->> 'turno' and k.situacao = 'livre' and not k.eh_dono and k.payee_id is distinct from v_dono
           and not (to_jsonb(k.payee_id::text) <@ coalesce(m -> 'pessoas', '[]'::jsonb))
           and not exists (select 1 from public.agenda_alocacoes x
                            where x.payee_id = k.payee_id and x.estado in ('publicada', 'fixada')
                              and x.periodo && public.agenda_periodo((m ->> 'dia')::date, m ->> 'turno', 'turno'))
           and not exists (select 1 from jsonb_array_elements(v_usado) u
                            where u ->> 'payee_id' = k.payee_id::text and u ->> 'dia' = m ->> 'dia' and u ->> 'turno' = m ->> 'turno')
           and (exists (select 1 from public.agenda_disponibilidade d
                         where d.payee_id = k.payee_id and d.substituida_em is null and d.origem = 'dono' and d.periodo is not null
                           and d.periodo @> (m ->> 'dia')::date and d.situacao in ('disponivel', 'confirmada')
                           and (d.turno is null or d.turno = m ->> 'turno'))
                or not public._agenda_e_sob_demanda(k.payee_id, p_hoje))
         order by exists (select 1 from public.agenda_disponibilidade d
                           where d.payee_id = k.payee_id and d.substituida_em is null and d.origem = 'dono' and d.periodo is not null
                             and d.periodo @> (m ->> 'dia')::date and d.situacao in ('disponivel', 'confirmada')
                             and (d.turno is null or d.turno = m ->> 'turno')) desc,
                  k.pessoa, k.payee_id
      loop
        v_try := v_novas || jsonb_build_object('payee_id', c.payee_id, 'nome', c.nome, 'dia', m -> 'dia', 'turno', m -> 'turno',
                                               'presenca', 'turno');
        v_item := jsonb_build_object(
          'op', 'criar', 'os', v_os, 'numero', v_pront ->> 'numero', 'cliente_curto', v_pront ->> 'cliente_curto',
          'tipo', v_tipo, 'reserva_de', null, 'alocacoes', v_try,
          'de', (select min(e ->> 'dia') from jsonb_array_elements(v_try) e), 'ate', (select max(e ->> 'dia') from jsonb_array_elements(v_try) e),
          'fim_antes', v_ult, 'fim_depois', v_ult, 'atraso_du', null, 'condicao_tipo', null, 'critica', null, 'pergunta_chave', null,
          'decisao', null, 'espera', false, 'interrupcoes', 0, 'meios_do_dono', 0, 'fonte', v_fonte, 'dias', v_pront -> 'dias',
          'evento_real', false, 'fixar_dono', false, 'aviso_material', null, 'abre', false, 'fecha', false,
          'motivos', jsonb_build_array('dupla_completa'), 'texto', null, 'aplicado', false);
        -- acima da carga: o teto de 100% da pessoa e sem o teto da equipe-semana da 7a — o bloco de 1 pessoa já ocupa a semana do
        -- técnico, e a dupla acrescenta o que a revisão do dia seguinte corta no fim (as mesmas diárias-pessoa); sem isso, a dupla
        -- nunca se completaria na semana cheia
        v_val := public._agenda_validar_itens(jsonb_build_array(v_item),
                                              jsonb_build_object('p_restricoes', jsonb_build_object('acima_da_carga', true)), p_hoje, p_agora,
                                              false, jsonb_build_object(v_os::text, v_pront));
        if jsonb_array_length(v_val) = 0 then
          v_novas := v_try;
          v_usado := v_usado || jsonb_build_object('payee_id', c.payee_id, 'dia', m -> 'dia', 'turno', m -> 'turno');
          exit;
        end if;
      end loop;
    end loop;
    continue when jsonb_array_length(v_novas) = 0;
    -- a frase (spec R4.4 item 4): "Pus Mateus com Alex no Lenine em ter 10/11 (manhã e tarde): a troca do banco de baterias pede 2
    -- pessoas. *desfaz Lenine* volta."
    v_d := public._agenda_dupla_da_os(v_os);
    v_ondes := array(select distinct e ->> 'onde' from jsonb_array_elements(v_f) e
                      where exists (select 1 from jsonb_array_elements(v_novas) n where n ->> 'dia' = e ->> 'dia' and n ->> 'turno' = e ->> 'turno'));
    v_frases := array(select distinct on (q ->> 'motivo') q ->> 'frase' from jsonb_array_elements(coalesce(v_d -> 'motivos', '[]'::jsonb)) q
                       where q ->> 'onde' = any (v_ondes) and q ->> 'onde' <> 'todos' order by q ->> 'motivo');
    v_pede := case when 'todos' = any (v_ondes)
                   then format('o serviço todo pede 2 pessoas (%s)', (select q ->> 'frase' from jsonb_array_elements(coalesce(v_d -> 'motivos', '[]'::jsonb)) q
                                                                        where q ->> 'onde' = 'todos' limit 1))
                   else format('%s %s 2 pessoas', public._agenda_lista(v_frases), case when cardinality(v_frases) > 1 then 'pedem' else 'pede' end) end;
    v_cli := coalesce(v_pront ->> 'cliente_curto', v_pront ->> 'numero');
    v_txt := format('Pus %s com %s no %s %s: %s. *desfaz %s* volta.',
                    public._agenda_lista(array(select z.n from (select n ->> 'nome' as n, min(o) as o from jsonb_array_elements(v_novas) with ordinality t(n, o)
                                                                group by 1) z order by z.o)),
                    coalesce(nullif(public._agenda_lista(array(
                      select distinct case when p::uuid is not distinct from v_dono then 'você' else public._agenda_nome_curto(py.name) end
                        from jsonb_array_elements(v_f) e cross join lateral jsonb_array_elements_text(coalesce(e -> 'pessoas', '[]'::jsonb)) p
                        join public.payees py on py.id = p::uuid
                       where exists (select 1 from jsonb_array_elements(v_novas) n where n ->> 'dia' = e ->> 'dia' and n ->> 'turno' = e ->> 'turno')
                       order by 1)), ''), 'quem vai'),
                    v_cli, public._agenda_meios_frase(v_novas), v_pede, v_cli);
    if v_seco then
      v_feitas := v_feitas || jsonb_build_object('os', v_os, 'numero', v_pront ->> 'numero', 'alocacoes', v_novas, 'texto', v_txt);
      continue;
    end if;
    -- a proposta só com as alocações novas, validada e aplicada por agenda_aplicar (o molde de _agenda_gestor_reparar): a ação
    -- reparar, desfazível; a marca dupla_completa na proposta e nas alocações
    v_its := jsonb_build_array(v_item - 'alocacoes' || jsonb_build_object(
               'alocacoes', (select jsonb_agg(a || jsonb_build_object('alocacao_id', gen_random_uuid()) order by j)
                               from jsonb_array_elements(v_novas) with ordinality u(a, j)),
               'de', (select min(e ->> 'dia') from jsonb_array_elements(v_novas) e), 'ate', (select max(e ->> 'dia') from jsonb_array_elements(v_novas) e),
               'texto', v_txt));
    v_pid := gen_random_uuid();
    v_exp := least(p_agora + cf.proposta_validade,
                   coalesce((select min(lower(public.agenda_periodo((a ->> 'dia')::date, a ->> 'turno', 'turno')))
                               from jsonb_array_elements(v_novas) a), p_agora + cf.proposta_validade));
    insert into public.agenda_propostas (id, escopo, periodo, os_alvo, versao_base, modo, estado, itens, fora, carga, textos,
                                         parametros, pontuacao, criada_por, autor, criada_em, expira_em)
    values (v_pid, 'replano',
            daterange((select min((e ->> 'dia')::date) from jsonb_array_elements(v_novas) e),
                      (select max((e ->> 'dia')::date) from jsonb_array_elements(v_novas) e), '[]'),
            array[v_os], cf.versao_plano, 'ligado', 'aberta', v_its, '[]'::jsonb, '{}'::jsonb,
            jsonb_build_object('titulo', 'Mudanças na agenda', 'linhas', jsonb_build_array(v_txt), 'fora', '[]'::jsonb, 'resumo', v_txt),
            jsonb_build_object('p_hoje', p_hoje, 'p_agora', p_agora, 'p_de', null, 'p_ate', null, 'p_os', jsonb_build_array(v_os),
                               'p_restricoes', jsonb_build_object('acima_da_carga', true), 'escopo', 'replano', 'origem', 'vigia',
                               'gestor', jsonb_build_object('tipo', 'reparar', 'motivo', 'dupla_completa',
                                                            'textos', jsonb_build_object(v_os::text, v_txt))),
            null, 'vigia', null, p_agora, v_exp);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id,
                                         duracao_fonte, motivos, criado_em)
    select (a ->> 'alocacao_id')::uuid, v_os, (a ->> 'payee_id')::uuid, (a ->> 'dia')::date, a ->> 'turno', 'turno', v_tipo,
           'proposta', 'motor', v_pid, v_fonte, jsonb_build_array('dupla_completa'), p_agora
      from jsonb_array_elements(v_its -> 0 -> 'alocacoes') with ordinality u(a, j)
     order by j;
    v_a := public.agenda_aplicar(v_pid, null, 'vigia', null, null, p_hoje, p_agora);
    if not coalesce((v_a ->> 'ok')::boolean, false) then
      perform public.agenda_descartar(v_pid, null, 'a dupla não passou no aplicar');
      perform public.log_app_error('db', 'agenda: a 2ª pessoa da dupla não aplicou: ' || coalesce(v_a ->> 'texto', '?'),
                                   'agenda', 'gestor:dupla', 'warn',
                                   jsonb_build_object('os', v_os, 'proposta', v_pid, 'violacoes', v_a -> 'violacoes',
                                                      'p_hoje', p_hoje, 'p_agora', p_agora));
      continue;
    end if;
    v_feitas := v_feitas || jsonb_build_object('os', v_os, 'numero', v_pront ->> 'numero', 'alocacoes', v_novas, 'texto', v_txt,
                                               'proposta_id', v_pid);
    v_acoes := v_acoes || coalesce(v_a -> 'acoes', '[]'::jsonb);
  end loop;

  -- (ii) a dupla dita (sem compromisso) que esperava a 2ª pessoa e agora a tem pela régua dos técnicos só por quem vem sob demanda (a
  -- classe não é mais a 4 dupla, mas os de dias fixos não bastam: o dupla_sd do P4, R4.3(c)): a montagem dela (_agenda_propor_e_aplicar,
  -- a vigia; a onda K vale). Só quando os dias de alguém mudaram desde o tique que fez isso por último (fp: as linhas de disponibilidade
  -- vivas) — a dita que continua sem bloco (o fora dupla do R4.3(c)) não vira uma proposta nova a cada tique.
  v_fp := md5(coalesce((select string_agg(d.id::text, ',' order by d.id) from public.agenda_disponibilidade d
                         where d.substituida_em is null and d.payee_id is distinct from v_dono), ''));
  select r.contagens #>> '{dupla,fp}' into v_fp0
    from public.agenda_vigia_rodadas r
   where r.rotina = 'gestor' and r.p_agora <= p_agora and jsonb_typeof(r.contagens -> 'dupla') = 'object' and (r.contagens -> 'dupla') ? 'fp'
   order by r.p_agora desc, r.rodou_em desc limit 1;
  if v_seco or v_fp is distinct from v_fp0 then
    v_semtec := (select count(*)::int from jsonb_array_elements(coalesce(public.agenda_capacidade_semanal(p_hoje) -> 'pessoas', '[]'::jsonb)) q
                  where not coalesce((q ->> 'eh_dono')::boolean, false));
    v_ditas := array(
      select z.os from (
        select k.service_order_id as os, k.numero, mm.v as m, public._agenda_classe_agora(k.service_order_id, p_hoje) as cl
          from public.os_carteira(p_hoje) k
          join public.os_planejamento pl on pl.service_order_id = k.service_order_id
          cross join lateral (select public.agenda_meios_da_os(k.service_order_id, p_hoje) as v) mm
         where pl.dupla_dita in ('todos', 'inicio', 'fim') and not public._agenda_os_tem_dia(k.service_order_id, p_hoje)) z
       where not coalesce((z.m ->> 'equipe_dita')::boolean, false)
         and not (z.cl ->> 'classe' = '4' and z.cl ->> 'motivo' = 'dupla')
         and v_semtec < greatest(coalesce((z.m #>> '{por_turno,manha,desejado}')::int, 0), coalesce((z.m #>> '{por_turno,tarde,desejado}')::int, 0),
                                 coalesce((select max(dd::int) from jsonb_array_elements_text(coalesce(z.m -> 'dk', '[]'::jsonb)) dd), 0)
                                 - case when coalesce((z.m ->> 'dk_dono_conta')::boolean, true)
                                             and (coalesce((z.m #>> '{dono_turno,manha}')::boolean, false)
                                                  or coalesce((z.m #>> '{dono_turno,tarde}')::boolean, false)) then 1 else 0 end)
       order by z.numero, z.os);
    if not v_seco and cardinality(v_ditas) > 0 then
      v_r := public._agenda_propor_e_aplicar('os', v_ditas, 'vigia', null, p_hoje, p_agora);
      v_acoes := v_acoes || coalesce(v_r -> 'acoes', '[]'::jsonb);
    end if;
  end if;

  if v_seco then
    return jsonb_build_object('pulado', true, 'motivo', 'em teste', 'em_teste', true,
                              'completaria', v_feitas, 'ditas', to_jsonb(v_ditas));
  end if;
  return jsonb_build_object('completadas', jsonb_array_length(v_feitas), 'os', v_feitas, 'acoes', v_acoes,
                            'ditas', to_jsonb(v_ditas),
                            'marcou', case when v_r is not null then jsonb_build_object('ok', v_r -> 'ok', 'texto', v_r -> 'texto',
                                                                                         'fora', v_r -> 'fora') end,
                            'fp', v_fp);
end;
$function$;

comment on function public._agenda_gestor_dupla(date, timestamptz) is
  'Agenda de Produção (Fase 7b, P6; R4.4 item 4, R4.9-5): o passo de todo tique dupla da rodada do gestor (barato: só as OS com dupla). modo_dupla desligado ou o gestor que marca desligado = {pulado}. (i) A 2ª pessoa na dupla pela tarefa que foi com 1: em cada meio-dia de _agenda_dupla_faltando fora da zona travada, depois do congelado e que ainda não começou, a 1ª pessoa livre que não é o dono (primeiro quem o dono disse para aquela data, depois quem tem dias fixos), sem outra coisa no meio-dia, validada pelas 14 regras com as outras já aceitas da OS e acima da carga (o teto de 100% da pessoa, sem o teto da equipe-semana: a revisão do dia seguinte corta o que a dupla encurta); nunca sozinha, nunca move o que já está. Uma proposta por OS (escopo replano, criada_por vigia, modo ligado; parametros.gestor {tipo reparar, motivo dupla_completa, textos}) só com as alocações novas (motivos [dupla_completa]), aplicada por agenda_aplicar: a ação reparar, desfazível — "Pus Mateus com Alex no Lenine em ter 10/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas. *desfaz Lenine* volta." Não passou no aplicar = descartada, app_error_logs gestor:dupla (warn). (ii) A dupla dita (sem compromisso) que esperava a 2ª pessoa e agora a tem pela régua dos técnicos só por quem vem sob demanda (a classe deixou de ser a 4 dupla, e os de dias fixos não bastam: o dupla_sd do P4): _agenda_propor_e_aplicar(os, …, vigia) — a onda K vale; só quando as linhas de disponibilidade vivas mudaram desde o tique que fez isso por último (fp na contagem da rodada). Em teste (modo_dupla ou o gestor em sombra, ou a agenda automática fora de ligado): {pulado, em_teste, completaria, ditas}, nada gravado. {completadas, os, acoes, ditas, marcou, fp}. VOLATILE, invoker, sem grant (só a rodada do gestor o chama).';

revoke all on function public._agenda_meios_frase(jsonb, boolean), public._agenda_dupla_faltando(uuid, date),
  public._agenda_quem_chamar(date, timestamptz), public._agenda_gestor_chamar(date, timestamptz),
  public._agenda_gestor_dupla(date, timestamptz)
  from public, anon, authenticated, service_role;

-- ── 2. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 7b:") ─────────────────────────
-- Fora dos blocos nenhuma linha muda (o C8 de supabase/tests/agenda_fase7b_chamar.sql confere). Quem recriar de novo qualquer uma
-- delas copia DESTA migration (spec-fase7b §R4.6: o 7g P4 copia agenda_livre_de_verdade daqui).

-- agenda_gestor_rodar (de 20261031100800_agenda_fase7a_compras.sql)
create or replace function public.agenda_gestor_rodar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_tique   constant text[] := array['vetos', 'encaixe', 'bem', 'sinal', 'puxar'];
  c_diarios constant text[] := array['perguntas', 'compre_ate', 'revisao', 'fichas', 'orcamentos', 'sabado', 'equipe', 'sombra'];
  cf        public.agenda_config;
  v_t0      timestamptz := clock_timestamp();
  v_modos   jsonb;
  v_diaria  boolean;
  v_passos  text[];
  v_passo   text;
  v_r       jsonb;
  v_cont    jsonb := '{}'::jsonb;
  v_erros   int := 0;
  v_falhas  jsonb := '[]'::jsonb;
  v_parou   text;
  v_estado  text;
  v_msg     text;
  v_acoes   int;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rodada do gestor.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  -- uma rodada por vez (o tique seguinte que chega com esta rodando não espera: sai)
  if not pg_try_advisory_xact_lock(hashtext('agenda_gestor')) then
    return jsonb_build_object('rodou', false, 'ocupado', true);
  end if;
  cf := public._agenda_cfg();
  v_modos := jsonb_build_object('marcar', public._agenda_gestor_modo('marcar'), 'encaixe', public._agenda_gestor_modo('encaixe'),
                                'revisao', public._agenda_gestor_modo('revisao'), 'compre_ate', public._agenda_gestor_modo('compre_ate'),
                                'vaga', public._agenda_gestor_modo('vaga'), 'so_propor', cf.gestor_so_propor);
  if v_modos ->> 'marcar' = 'desligado' and v_modos ->> 'encaixe' = 'desligado' and v_modos ->> 'revisao' = 'desligado'
     and v_modos ->> 'compre_ate' = 'desligado' then
    return jsonb_build_object('rodou', false, 'modos', v_modos);
  end if;
  -- os passos diários: no 1º tique de dia útil a partir de gestor_hora_revisao (o dia está numa rodada gestor com "diaria")
  v_diaria := public.agenda_dia_util(p_hoje)
              and (p_agora at time zone 'America/Sao_Paulo')::time >= cf.gestor_hora_revisao
              and not exists (select 1 from public.agenda_vigia_rodadas x
                               where x.rotina = 'gestor' and x.p_hoje = p_hoje and x.contagens ? 'diaria');
  v_passos := c_tique || case when v_diaria then c_diarios else '{}'::text[] end;
  -- FASE 7b: (7b P6, R4.4) os passos da 7b: dupla em todo tique, depois dos de sempre (só as OS com dupla: a 2ª pessoa na dupla
  -- pela tarefa que foi com 1 e a dupla dita que esperava), com modo_dupla fora de desligado; chamar nos diários, depois de sombra
  -- (quem chamar, gravado no diário do dia), com modo_chamar fora de desligado. Com os dois desligados, os passos de antes.
  v_passos := c_tique || case when cf.modo_dupla <> 'desligado' then array['dupla'] else '{}'::text[] end
              || case when v_diaria then c_diarios || case when cf.modo_chamar <> 'desligado' then array['chamar'] else '{}'::text[] end
                      else '{}'::text[] end;
  -- FASE 7b: fim
  -- FASE 7: (7a P10) o "compre até" também em todo tique fora dos diários (depois do encaixe), com o modo dele fora de
  -- desligado: a OS que o gestor ou a vigia acabou de marcar ganha o "compre até" gravado no mesmo dia — sem ele, a prontidão
  -- conta a compra a partir de amanhã e o publicado andaria um dia por dia. O passo só cobra e escreve o diário a partir de
  -- gestor_hora_revisao, em dia útil. Com o compre_ate desligado, nada muda.
  if not v_diaria and v_modos ->> 'compre_ate' <> 'desligado' then
    v_passos := v_passos || 'compre_ate'::text;
  end if;
  -- FASE 7: fim
  v_acoes := (select count(*) from public.agenda_acoes a where a.executada);

  foreach v_passo in array v_passos loop
    if to_regprocedure(format('public.%I(date, timestamp with time zone)', '_agenda_gestor_' || v_passo)) is null then
      v_cont := v_cont || jsonb_build_object(v_passo, jsonb_build_object('pulado', true, 'motivo', 'ainda não existe'));
      continue;
    end if;
    begin
      execute format('select public.%I($1, $2)', '_agenda_gestor_' || v_passo) into v_r using p_hoje, p_agora;
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb));
    exception
      when query_canceled then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_parou := v_passo;
        v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
        perform public.log_app_error('db', format('gestor da agenda, passo %s: o tempo da rodada acabou (%s)', v_passo, v_msg),
                                     'agenda', 'gestor:' || v_passo, 'error',
                                     jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora,
                                                        'tempo_max', cf.gestor_tempo_max::text));
        exit;
      when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
        perform public.log_app_error('db', format('gestor da agenda, passo %s: %s', v_passo, v_msg), 'agenda',
                                     'gestor:' || v_passo, 'error',
                                     jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
    end;
  end loop;

  v_acoes := (select count(*) from public.agenda_acoes a where a.executada) - v_acoes;
  -- os diários só contam como feitos se a rodada não parou no tempo (senão o tique seguinte tenta de novo)
  v_cont := v_cont || jsonb_build_object('modos', v_modos, 'falhas', v_falhas, 'acoes', v_acoes,
                                         'mudou', v_acoes > 0)
            || case when v_diaria and v_parou is null then jsonb_build_object('diaria', true) else '{}'::jsonb end
            || case when v_parou is not null then jsonb_build_object('parou_no', v_parou) else '{}'::jsonb end;
  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                           rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia, v_cont, least(v_erros, 32767),
          greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int), 'gestor', cf.modo_equipe, cf.modo_diaria);
  return jsonb_build_object('rodou', true, 'modos', v_modos, 'diaria', v_diaria and v_parou is null, 'parou_no', v_parou,
                            'acoes', v_acoes, 'erros', v_erros, 'falhas', v_falhas, 'contagens', v_cont);
end;
$function$;

comment on function public.agenda_gestor_rodar(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P7; spec §3.1 item 13, §5.7): a rodada do gestor da agenda (o job agenda-gestor do pg_cron, ''7,22,37,52 10-23 * * 1-6'', com o statement_timeout de gestor_tempo_max). Passos _agenda_gestor_<passo>(date, timestamptz) → jsonb: de todo tique vetos, encaixe, bem, sinal, puxar; diários (no 1º tique de dia útil a partir de gestor_hora_revisao, uma vez: a rodada gestor do dia com "diaria") perguntas, compre_ate, revisao, fichas, orcamentos, sabado, equipe, sombra. O passo cuja função ainda não existe = {pulado}. Erro de um passo → app_error_logs (gestor:<passo>) e segue; query_canceled → registra, grava a rodada (parou_no) e encerra (os diários tentam de novo no tique seguinte). Com marcar, encaixe, revisao e compre_ate desligados = {rodou: false} (nada gravado). Uma rodada por vez (pg_try_advisory_xact_lock: a outra sai com {rodou: false, ocupado}). Uma linha em agenda_vigia_rodadas (rotina gestor) com as contagens de cada passo, os modos, as falhas, as ações executadas na rodada (acoes, mudou), os erros e a duração. O aviso ao dono do que mudou sai pelo passo agenda-aviso do task-automations no tique seguinte (ele já conta toda ação de plano executada da vigia/motor ainda não contada). Security definer, só o service_role. FASE 7 (7a P10): o passo compre_ate também roda nos tiques fora dos diários, depois dos de todo tique (o encaixe): a OS que o gestor ou a vigia acabou de marcar ganha o "compre até" gravado no mesmo dia; o passo só cobra e escreve o diário a partir de gestor_hora_revisao, em dia útil. FASE 7b (P6, R4.4): com modo_dupla fora de desligado, o passo dupla (_agenda_gestor_dupla) em todo tique, depois dos de sempre; com modo_chamar fora de desligado, o passo chamar (_agenda_gestor_chamar) nos diários, depois de sombra. Com os dois desligados, os passos de antes, byte a byte.';

-- _agenda_gestor_dia_gravar (de 20261031100000_agenda_fase7a_base.sql)
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
  -- FASE 7b: (7b P6, R4.4) a chave chamar (o quem chamar do dia, de _agenda_gestor_chamar): um objeto, gravado como as outras (os
  -- modos na hora; o valor de antes no histórico quando muda, os 20 mais novos; o vazio não entra)
  if p_chave = 'chamar' then
    if v_novo is null or jsonb_typeof(v_novo) <> 'object' then
      raise exception '_agenda_gestor_dia_gravar: chamar é um objeto.' using errcode = '22023';
    end if;
    v_modos := jsonb_build_object('marcar', public._agenda_gestor_modo('marcar'), 'encaixe', public._agenda_gestor_modo('encaixe'),
                                  'revisao', public._agenda_gestor_modo('revisao'),
                                  'compre_ate', public._agenda_gestor_modo('compre_ate'),
                                  'vaga', public._agenda_gestor_modo('vaga'),
                                  'so_propor', (public._agenda_cfg()).gestor_so_propor);
    select * into r from public.agenda_gestor_dia where dia = p_dia for update;
    if not found then
      insert into public.agenda_gestor_dia (dia, calculado_em, modos, chamar) values (p_dia, p_agora, v_modos, v_novo);
      return;
    end if;
    update public.agenda_gestor_dia
       set calculado_em = p_agora,
           modos = v_modos,
           chamar = v_novo,
           historico = case when r.chamar is distinct from v_novo and r.chamar not in ('{}'::jsonb, 'null'::jsonb)
                            then (select coalesce(jsonb_agg(h order by o), '[]'::jsonb)
                                    from jsonb_array_elements(jsonb_build_array(jsonb_build_object('em', p_agora, 'chave', p_chave,
                                                                                                   'antes', r.chamar))
                                                              || historico) with ordinality t(h, o)
                                   where o <= 20)
                            else historico end
     where dia = p_dia;
    return;
  end if;
  -- FASE 7b: fim
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
  'Agenda de Produção (Fase 7a, P1): o gravador único de agenda_gestor_dia — upsert da chave do dia (sombra: objeto; orcamentos e compras: lista; texto_sombra: texto ≤ 640), com os modos efetivos na hora; o valor de antes vai para o histórico quando muda (os 20 mais novos; o vazio não entra). Chave fora da lista = 22023. Security definer, sem grant a ninguém (nem service_role): só os passos do gestor o chamam. FASE 7b (P6, R4.4): a chave chamar (objeto: o quem chamar do dia, _agenda_gestor_chamar), gravada como as outras (os modos na hora; o valor de antes no histórico quando muda). As outras chaves, byte a byte.';

-- _agenda_ver_gestor (de 20261031100985_agenda_fase77a_correcao2.sql)
create or replace function public._agenda_ver_gestor(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_ef    text := public._agenda_gestor_modo('marcar');
  v_l     text[] := '{}';
  v_desde date;
  v_sdia  date;
  v_s     jsonb;
  v_cart  uuid[];
  v_fora  jsonb := '[]'::jsonb;
  v_n     int;
  v_comp  jsonb;
  v_orc   jsonb;
  v_mo    numeric := public._agenda_mo_por_diaria_real();
  x       jsonb;
  r       record;
  -- (7a correção, achado 3) o "Como eu conto" à parte, sempre no fim
  v_como  text;
  v_k     int;
  -- FASE 7: (7a correção 2) quem a grade tem (a dupla sem a 2ª pessoa) e o fim do dia (o *desfaz* do dono)
  v_f72_tec   text[];
  v_f72_dup   text;
  v_f72_agora timestamptz;
  -- FASE 7: fim
  -- FASE 7b: (7b P6) a dupla de 1 pessoa no lugar do "Pode precisar de dupla" e o bloco "Quem chamar"
  v_7b_dupla boolean := (public._agenda_cfg()).modo_dupla <> 'desligado';
  v_7b_tf    text;
  v_7b_m     jsonb;
  v_7b_pl    jsonb;
  v_7b_d     jsonb;
  v_7b_fa    jsonb;
  v_7b_ni    int;
  v_7b_nf    int;
  v_7b_x     text;
  v_7b_y     text;
  v_7b_r1    text;
  v_7b_r2    text;
  v_7b_z     text;
  v_7b_ch    jsonb;
  v_7b_cdia  date;
  v_7b_cab   text;
  v_7b_pela  text;
  v_7b_bul   text[];
  -- FASE 7b: fim
begin
  if p_hoje is null then
    raise exception '_agenda_ver_gestor: sem o dia de hoje' using errcode = '22004';
  end if;

  -- 1. o estado (uma linha)
  if cf.gestor_so_propor then
    v_l := v_l || case when cf.gestor_so_propor_em is not null
                       then format('Desde %s você pediu *gestor, só propor*: eu só sugiro. *gestor, pode marcar* volta.',
                                   public._dia_curto((cf.gestor_so_propor_em at time zone 'America/Sao_Paulo')::date))
                       else 'Você pediu *gestor, só propor*: eu só sugiro. *gestor, pode marcar* volta.' end;
  elsif cf.modo_marcar_sozinho = 'ligado' then
    v_l := v_l || case when cf.marcar_sozinho_desde is not null
                       then format('Eu marco sozinho desde %s e te conto no fechamento; *desfaz <nome>* volta qualquer coisa que eu fiz.',
                                   public._dia_curto((cf.marcar_sozinho_desde at time zone 'America/Sao_Paulo')::date))
                       else 'Eu marco sozinho e te conto no fechamento; *desfaz <nome>* volta qualquer coisa que eu fiz.' end;
  elsif cf.modo_marcar_sozinho = 'sombra' then
    select min(g.dia) into v_desde from public.agenda_gestor_dia g
     where g.dia <= p_hoje and g.modos ->> 'marcar' = 'sombra'
       and g.dia > coalesce((select max(h.dia) from public.agenda_gestor_dia h
                              where h.dia <= p_hoje and h.modos ->> 'marcar' is distinct from 'sombra'), date '-infinity');
    v_l := v_l || case when v_desde is not null
                       then format('O gestor está em teste desde %s: calcula o que marcaria, mas não muda nada.', public._dia_curto(v_desde))
                       else 'O gestor está em teste: calcula o que marcaria, mas não muda nada.' end;
  else
    v_l := v_l || 'O gestor da agenda está desligado: não marco nada sozinho.'::text;
  end if;

  -- FASE 7: (7a correção 2, a dupla sem a 2ª pessoa) com menos de 2 técnicos na grade, o "Pode precisar de dupla" diz que falta a
  -- 2ª pessoa e o que fazer antes do *<nome> com dupla* (sem isso a palavra tirava a OS da agenda, calada)
  v_f72_tec := public._agenda_tecnicos_da_grade(p_hoje);
  v_f72_dup := case when cardinality(v_f72_tec) < 2
                    then replace(format('hoje %s: para ir dupla, chame um ajudante e ', public._agenda_tecnicos_frase(v_f72_tec)), '%', '%%')
                    else '' end;
  v_f72_agora := (p_hoje + 1)::timestamp at time zone 'America/Sao_Paulo';
  -- FASE 7: fim
  -- FASE 7b: (7b P6) quem a grade tem, na frase da dupla de 1 pessoa (a da marcação do P4)
  v_7b_tf := case when cardinality(v_f72_tec) >= 2 then 'ninguém mais está livre nesses meios-dias'
                  else public._agenda_tecnicos_frase(v_f72_tec) end;
  -- FASE 7b: fim
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k
                   where not public._agenda_os_tem_dia(k.service_order_id, p_hoje));

  if v_ef = 'sombra' then
    -- 2–4 em teste: a última conta do "eu marcaria assim" (o diário do gestor)
    select g.dia, g.sombra into v_sdia, v_s from public.agenda_gestor_dia g
     where g.dia <= p_hoje and g.sombra <> '{}'::jsonb order by g.dia desc limit 1;
    if v_s is null then
      v_l := v_l || 'Eu marcaria: ainda não fiz a conta (faço todo dia útil no fim da tarde).'::text;
    else
      if jsonb_array_length(coalesce(v_s -> 'itens', '[]'::jsonb)) = 0 and jsonb_array_length(coalesce(v_s -> 'reservas', '[]'::jsonb)) = 0 then
        v_l := v_l || ('Eu marcaria' || case when v_sdia <> p_hoje then format(' (pela conta de %s)', public._dia_curto(v_sdia)) else '' end
                       || ': nada agora.');
      else
        v_l := v_l || ('Eu marcaria' || case when v_sdia <> p_hoje then format(' (pela conta de %s)', public._dia_curto(v_sdia)) else '' end
                       || ':');
        for x in select e from jsonb_array_elements(coalesce(v_s -> 'itens', '[]'::jsonb)) with ordinality t(e, o) order by o loop
          v_l := v_l || format('• %s: %s, %s — %s (%s)%s.%s', x ->> 'cliente',
                               public._agenda_gestor_faixa((x ->> 'de')::date, (x ->> 'ate')::date), x ->> 'pessoas',
                               public._agenda_dias((x ->> 'dias')::numeric),
                               case x ->> 'fonte' when 'orcamento' then 'estimativa minha' else 'você disse' end,
                               case when x ->> 'compre_ate' is not null
                                    then format('; compre até %s: %s',
                                                case when (x ->> 'compre_ate')::date <= p_hoje then 'hoje'
                                                     else public._dia_curto((x ->> 'compre_ate')::date) end,
                                                public._agenda_itens((x ->> 'itens_a_comprar')::int))
                                    else '' end,
                               case when jsonb_typeof(x -> 'alerta_dupla') = 'object'
                                    then format(' Pode precisar de dupla (%s): ' || v_f72_dup || 'diga *%s com dupla*.',  -- (7a correção 2) a 2ª pessoa
                                                public._agenda_gestor_dupla_texto(x -> 'alerta_dupla'), x ->> 'cliente')
                                    else '' end);
          -- FASE 7b: (7b P6, R4.4 "agenda gestor") com modo_dupla fora de desligado, o "Pode precisar de dupla (…): … diga *Lenine com
          -- dupla*" do 7a sai: com a 7b, *com dupla* é "o tempo todo" e faz a OS esperar a 2ª pessoa. Em teste do gestor não há plano:
          -- a frase da dupla de 1 pessoa (R4.3(a)(3)) na forma curta, sem as datas ("Nos 2 primeiros meios-dias a troca do banco de
          -- baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga os dias dele."), pelos meios-dias do que
          -- a tarefa pede (_agenda_dupla_da_os: fora da simulação, o molde não tem o dk da regra uma_pessoa do gestor em teste)
          if v_7b_dupla and jsonb_typeof(x -> 'alerta_dupla') = 'object' then
            v_7b_m := public._agenda_dupla_da_os((x ->> 'os')::uuid);
            if v_7b_m ->> 'fonte' = 'regra' then
              v_7b_ni := coalesce((v_7b_m ->> 'inicio')::int, 0);
              v_7b_nf := coalesce((v_7b_m ->> 'fim')::int, 0);
              v_7b_x := public._agenda_lista(array(select distinct on (q ->> 'motivo') q ->> 'frase'
                                                     from jsonb_array_elements(coalesce(v_7b_m -> 'motivos', '[]'::jsonb)) q
                                                    where q ->> 'onde' = 'inicio' order by q ->> 'motivo'));
              v_7b_y := public._agenda_lista(array(select distinct on (q ->> 'motivo') q ->> 'frase'
                                                     from jsonb_array_elements(coalesce(v_7b_m -> 'motivos', '[]'::jsonb)) q
                                                    where q ->> 'onde' = 'fim' order by q ->> 'motivo'));
              v_7b_z := case
                when coalesce((v_7b_m ->> 'todos')::boolean, false)
                  then format(' O serviço todo pede 2 pessoas (%s) e %s: se chamar um ajudante, me diga os dias dele.',
                              coalesce((select q ->> 'rotulo' from jsonb_array_elements(coalesce(v_7b_m -> 'motivos', '[]'::jsonb)) q
                                         where q ->> 'onde' = 'todos' limit 1), 'o orçamento previu 2 técnicos'), v_7b_tf)
                when v_7b_ni > 0 and v_7b_nf > 0
                  then format(' %s %s e %s %s pedem 2 pessoas e %s: se chamar um ajudante, me diga os dias dele.',
                              case when v_7b_ni = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_ni) end, v_7b_x,
                              case when v_7b_nf = 1 then 'no último meio-dia' else format('nos %s últimos meios-dias', v_7b_nf) end, v_7b_y,
                              v_7b_tf)
                when v_7b_ni > 0
                  then format(' %s %s pede 2 pessoas e %s: se chamar um ajudante, me diga os dias dele.',
                              case when v_7b_ni = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_ni) end, v_7b_x,
                              v_7b_tf)
                when v_7b_nf > 0
                  then format(' %s %s pede 2 pessoas e %s: se chamar um ajudante, me diga os dias dele.',
                              case when v_7b_nf = 1 then 'No último meio-dia' else format('Nos %s últimos meios-dias', v_7b_nf) end, v_7b_y,
                              v_7b_tf)
                else '' end;
              v_l[cardinality(v_l)] := regexp_replace(v_l[cardinality(v_l)], ' Pode precisar de dupla \(.*$', '') || v_7b_z;
            end if;
          end if;
          -- FASE 7b: fim
        end loop;
        for x in select e from jsonb_array_elements(coalesce(v_s -> 'reservas', '[]'::jsonb)) with ordinality t(e, o) order by o loop
          v_l := v_l || format('• %s: reservaria %s, %s.', x ->> 'cliente',
                               public._agenda_gestor_faixa((x ->> 'de')::date, (x ->> 'ate')::date), x ->> 'pessoas');
        end loop;
      end if;
      if jsonb_array_length(coalesce(v_s -> 'perguntas', '[]'::jsonb)) > 0 then
        v_l := v_l || 'Antes de marcar eu perguntaria:'::text;
        for x in select e from jsonb_array_elements(v_s -> 'perguntas') with ordinality t(e, o) order by o loop
          v_l := v_l || (format('• %s: %s', x ->> 'cliente', x ->> 'curto')
                         || case when right(x ->> 'curto', 1) in ('?', '.') then '' else '.' end);
        end loop;
      end if;
      v_fora := coalesce(v_s -> 'fora', '[]'::jsonb);
    end if;
  elsif v_ef = 'ligado' then
    -- 2. o que o gestor marcou nos últimos 7 dias: as OS com compromisso vigente pela estimativa (duracao_fonte orcamento)
    v_n := 0;
    v_l := v_l || 'Marquei nos últimos 7 dias:'::text;
    for r in select a.service_order_id as os, min(a.dia) as de, max(a.dia) as ate,
                    count(*) filter (where a.presenca = 'turno') as meios,
                    jsonb_agg(jsonb_build_object('payee_id', a.payee_id, 'nome', public._agenda_nome_curto(py.name), 'dia', a.dia,
                                                 'turno', a.turno, 'presenca', a.presenca)) as alocs
               from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
              where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.duracao_fonte = 'orcamento'
                and a.dia >= p_hoje and a.resultado is null
              group by a.service_order_id
             having min((a.criado_em at time zone 'America/Sao_Paulo')::date) >= p_hoje - 7
              order by min(a.dia), a.service_order_id loop
      v_n := v_n + 1;
      v_l := v_l || format('• %s: %s, %s — %s (estimativa minha).%s',
                           coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                                       join public.clients cl on cl.id = so.client_id where so.id = r.os), 'serviço'),
                           public._agenda_gestor_faixa(r.de, r.ate), public._agenda_gestor_pessoas(r.alocs),
                           public._agenda_dias(r.meios::numeric / 2),
                           coalesce((select format(' Pode precisar de dupla (%s): ' || v_f72_dup || 'diga *%s com dupla*.',  -- (7a correção 2) a 2ª pessoa
                                                   public._agenda_gestor_dupla_texto(d.a), public._agenda_nome_curto(cl.name))
                                       from (select public.os_duracao_sugerida(r.os) -> 'alerta_dupla' as a) d,
                                            public.service_orders so join public.clients cl on cl.id = so.client_id
                                      where so.id = r.os and jsonb_typeof(d.a) = 'object'), ''));
      -- FASE 7b: (7b P6, R4.4 "agenda gestor") com modo_dupla fora de desligado, o "Pode precisar de dupla" do 7a vira a frase da dupla
      -- de 1 pessoa (R4.3(a)(3), a da marcação do P4) com as datas do plano: os meios-dias em que a dupla pela tarefa ainda está sem a
      -- 2ª pessoa (_agenda_dupla_no_plano, fora da reserva). Com a 2ª pessoa em todos (a dupla completa), nada.
      if v_7b_dupla and v_l[cardinality(v_l)] like '% Pode precisar de dupla (%' then
        v_7b_pl := public._agenda_dupla_no_plano(r.os, p_hoje);
        v_7b_d := public._agenda_dupla_da_os(r.os);
        select coalesce(jsonb_agg(e order by (e ->> 'dia')::date, e ->> 'turno'), '[]'::jsonb) into v_7b_fa
          from jsonb_array_elements(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) e
         where not coalesce((e ->> 'reserva')::boolean, false) and v_7b_pl ->> 'fonte' = 'regra';
        select public._agenda_lista(array(
                 select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                       when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                   from (select (e ->> 'dia')::date as d, e ->> 'turno' as t from jsonb_array_elements(v_7b_fa) e
                          where e ->> 'onde' in ('inicio', 'todos')) z
                  group by z.d order by z.d)),
               public._agenda_lista(array(
                 select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                       when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                   from (select (e ->> 'dia')::date as d, e ->> 'turno' as t from jsonb_array_elements(v_7b_fa) e where e ->> 'onde' = 'fim') z
                  group by z.d order by z.d))
          into v_7b_x, v_7b_y;
        v_7b_ni := (select count(*)::int from jsonb_array_elements(v_7b_fa) e where e ->> 'onde' = 'inicio');
        v_7b_nf := (select count(*)::int from jsonb_array_elements(v_7b_fa) e where e ->> 'onde' = 'fim');
        v_7b_r1 := public._agenda_lista(array(select distinct on (q ->> 'motivo') q ->> 'frase'
                                                from jsonb_array_elements(coalesce(v_7b_d -> 'motivos', '[]'::jsonb)) q
                                               where q ->> 'onde' = 'inicio' order by q ->> 'motivo'));
        v_7b_r2 := public._agenda_lista(array(select distinct on (q ->> 'motivo') q ->> 'frase'
                                                from jsonb_array_elements(coalesce(v_7b_d -> 'motivos', '[]'::jsonb)) q
                                               where q ->> 'onde' = 'fim' order by q ->> 'motivo'));
        v_7b_z := case
          when jsonb_array_length(v_7b_fa) = 0 then ''
          when exists (select 1 from jsonb_array_elements(v_7b_fa) e where e ->> 'onde' = 'todos')
            then format(' O serviço todo pede 2 pessoas (%s) e %s: vai com 1 pessoa; se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                        coalesce((select q ->> 'rotulo' from jsonb_array_elements(coalesce(v_7b_d -> 'motivos', '[]'::jsonb)) q
                                   where q ->> 'onde' = 'todos' limit 1), 'o orçamento previu 2 técnicos'), v_7b_tf,
                        public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date))
          when v_7b_x <> '' and v_7b_y <> ''
            then format(' %s (%s) %s e %s (%s) %s pedem 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                        case when v_7b_ni = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_ni) end, v_7b_x, v_7b_r1,
                        case when v_7b_nf = 1 then 'no último meio-dia' else format('nos %s últimos meios-dias', v_7b_nf) end, v_7b_y, v_7b_r2,
                        v_7b_tf, public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date))
          when v_7b_x <> ''
            then format(' %s (%s) %s pede 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                        case when v_7b_ni = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_ni) end, v_7b_x, v_7b_r1,
                        v_7b_tf, public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date))
          else format(' %s (%s) %s pede 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                      case when v_7b_nf = 1 then 'No último meio-dia' else format('Nos %s últimos meios-dias', v_7b_nf) end, v_7b_y, v_7b_r2,
                      v_7b_tf, public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date)) end;
        v_l[cardinality(v_l)] := regexp_replace(v_l[cardinality(v_l)], ' Pode precisar de dupla \(.*$', '') || v_7b_z;
      end if;
      -- FASE 7b: fim
    end loop;
    if v_n = 0 then
      v_l[cardinality(v_l)] := 'Marquei nos últimos 7 dias: nada.';
    end if;
    -- 3. o que ele perguntou antes de marcar (as abertas de verdade, com o prazo)
    v_n := 0;
    for r in select q.* from public.agenda_perguntas q
                     left join public.service_orders so on so.id = q.service_order_id
              where q.estado = 'aberta' and q.modo = 'ligado' and q.tipo in ('situacao', 'estimativa')
              order by q.veto_ate nulls last, so.service_order_number desc nulls last, q.id loop
      if v_n = 0 then
        v_l := v_l || 'Perguntei antes de marcar:'::text;
      end if;
      v_n := v_n + 1;
      v_l := v_l || format('• %s: %s — %s',
        -- (7a correção 2) o número da OS junto quando o nome se repete nas perguntas abertas (Kalmar OS-00032 e OS-00033)
        case when (select count(*) from public.agenda_perguntas q2
                     join public.service_orders s2 on s2.id = q2.service_order_id
                     left join public.clients c2 on c2.id = s2.client_id
                    where q2.estado = 'aberta' and q2.modo = 'ligado' and q2.tipo in ('situacao', 'estimativa')
                      and public._agenda_nome_curto(c2.name) is not distinct from
                          (select public._agenda_nome_curto(cl.name) from public.service_orders so
                             join public.clients cl on cl.id = so.client_id where so.id = r.service_order_id)) > 1
             then public._agenda_rotulo_da_os(r.service_order_id)
             else coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                              join public.clients cl on cl.id = so.client_id where so.id = r.service_order_id), 'serviço') end,
        coalesce(nullif(public._agenda_gestor_estimativa(r.service_order_id, p_hoje) ->> 'texto', ''),
                 case split_part(r.chave, ':', 3) when 'comecada' then 'já começou?' when 'rastro' then 'quanto falta?'
                                                  when 'parada' then 'ainda é para fazer?' when 'grande' then 'muitas diárias pela estimativa'
                                                  when 'embutida' then 'pode ter peça junto'
                                                  else 'não tem mão de obra separada' end),
        case when r.opcao_escolhida is not null then 'você vai me dizer os dias.'
             when r.veto_ate is not null
               then format('sem resposta até %s %s, marco assim.',
                           public._dia_curto((r.veto_ate at time zone 'America/Sao_Paulo')::date),
                           to_char(r.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI'))
             else 'espero você.' end);
    end loop;
    -- 4. quem fica de fora: o porquê da última conta do motor (a proposta de verdade mais nova que falou da OS, em 8 dias),
    -- das OS da carteira sem compromisso e sem pergunta aberta do gestor
    select coalesce(jsonb_agg(jsonb_build_object('os', t.os, 'cliente', t.cliente, 'motivo', t.motivo,
                                                 'grupo', public._agenda_gestor_motivo_texto(
                                                   -- (7a correção 2) a OS que o dono desfez: o porquê é o *desfaz*, não "sem lugar"
                                                   case when public._agenda_gestor_desfeito(t.os::uuid, v_f72_agora) then 'desfeito'
                                                        else t.motivo end)) order by t.numero), '[]'::jsonb)
      into v_fora
      from (select distinct on (f ->> 'os') f ->> 'os' as os, f ->> 'cliente_curto' as cliente, f ->> 'motivo' as motivo,
                   f ->> 'numero' as numero
              from public.agenda_propostas pr cross join lateral jsonb_array_elements(coalesce(pr.fora, '[]'::jsonb)) f
             where pr.modo = 'ligado' and pr.criada_em >= ((p_hoje - 8)::timestamp at time zone 'America/Sao_Paulo')
               and f ->> 'motivo' is distinct from 'fora_da_carteira'
               and (f ->> 'os')::uuid = any (v_cart)
               and not exists (select 1 from public.agenda_perguntas q
                                where q.estado = 'aberta' and q.modo = 'ligado' and q.tipo in ('situacao', 'estimativa')
                                  and q.service_order_id = (f ->> 'os')::uuid)
             order by f ->> 'os', pr.criada_em desc, pr.id desc) t;
  end if;

  -- FASE 7b: (7b P6, R4.4 "Onde aparece") o bloco "Quem chamar" (depois de "Perguntei antes de marcar"), só com modo_chamar fora de
  -- desligado: o que o passo diário chamar do gestor gravou (agenda_gestor_dia.chamar, a conta mais nova de até 3 dias; "pela conta de
  -- …" quando não é de hoje). Em teste, "Em teste:" na frente. Só sugere: quem chama é o dono.
  if cf.modo_chamar <> 'desligado' then
    select g.dia, g.chamar into v_7b_cdia, v_7b_ch from public.agenda_gestor_dia g
     where g.dia <= p_hoje and g.dia >= p_hoje - 3 and g.chamar ? 'calculado_em' order by g.dia desc limit 1;
    v_7b_cab := case when cf.modo_chamar = 'sombra' then 'Em teste: quem chamar' else 'Quem chamar' end;
    v_7b_pela := case when v_7b_cdia is not null and v_7b_cdia <> p_hoje then format('pela conta de %s', public._dia_curto(v_7b_cdia)) end;
    if v_7b_ch is null then
      v_l := v_l || (v_7b_cab || ': ainda não fiz a conta (faço todo dia útil no fim da tarde).');
    else
      v_7b_bul := array(select u.l from unnest(string_to_array(coalesce(v_7b_ch ->> 'texto', ''), E'\n')) with ordinality u(l, o)
                         where u.l like '•%' order by u.o);
      if cardinality(v_7b_bul) = 0 then
        v_l := v_l || (v_7b_cab || coalesce(' (' || v_7b_pela || ')', '') || ': ninguém — a equipe de hoje dá conta da carteira que está pronta.');
      else
        v_l := v_l || (v_7b_cab || ' (' || concat_ws('; ', v_7b_pela, 'só sugiro; quem chama é você') || '):') || v_7b_bul;
      end if;
    end if;
  end if;
  -- FASE 7b: fim
  -- 4. Fora: agrupado pelo porquê, os nomes (o número junto quando o nome se repete)
  if jsonb_array_length(v_fora) > 0 then
    v_l := v_l || ('Fora: ' || (
      select string_agg(g.grupo || ': ' || g.nomes, '; ' order by public._agenda_gestor_motivo_ordem(g.grupo), g.grupo)
        from (select h.grupo, public._agenda_lista(array_agg(h.nome || case when h.n > 1 then format(' (%s)', h.n) else '' end
                                                             order by h.primeiro), 4) as nomes
                from (select f ->> 'grupo' as grupo, f ->> 'cliente' as nome, count(*) as n, min(o) as primeiro
                        from jsonb_array_elements(v_fora) with ordinality t(f, o)
                       group by f ->> 'grupo', f ->> 'cliente') h
               group by h.grupo) g) || '.');
  end if;

  -- 5. as compras da semana (o diário do gestor; o P10 grava) e 6. os orçamentos que caberiam (o P12 grava): de até 3 dias
  select g.compras into v_comp from public.agenda_gestor_dia g
   where g.dia <= p_hoje and g.dia >= p_hoje - 3 and g.compras <> '[]'::jsonb order by g.dia desc limit 1;
  if jsonb_array_length(coalesce(v_comp, '[]'::jsonb)) > 0 then
    v_l := v_l || 'Compras da semana:'::text;
    -- (7a correção, achado 3) até 3 por seção: toda seção cabe com o "Como eu conto"
    v_l := v_l || array(select '• ' || (e ->> 'texto') from jsonb_array_elements(v_comp) with ordinality t(e, o)
                         where nullif(btrim(e ->> 'texto'), '') is not null order by o limit 3);
    v_k := (select count(*) from jsonb_array_elements(v_comp) e where nullif(btrim(e ->> 'texto'), '') is not null)::int;
    if v_k > 3 then
      v_l := v_l || format('(e mais %s em *agenda compras*)', v_k - 3);
    end if;
  end if;
  select g.orcamentos into v_orc from public.agenda_gestor_dia g
   where g.dia <= p_hoje and g.dia >= p_hoje - 3 and g.orcamentos <> '[]'::jsonb order by g.dia desc limit 1;
  if jsonb_array_length(coalesce(v_orc, '[]'::jsonb)) > 0 then
    v_l := v_l || 'Se aprovar:'::text;
    -- (7a correção, achado 3) até 3 (os de maior valor)
    v_l := v_l || array(select '• ' || (e ->> 'texto') from jsonb_array_elements(v_orc) with ordinality t(e, o)
                         where nullif(btrim(e ->> 'texto'), '') is not null order by o limit 3);
    v_k := (select count(*) from jsonb_array_elements(v_orc) e where nullif(btrim(e ->> 'texto'), '') is not null)::int;
    if v_k > 3 then
      v_l := v_l || format('(e mais %s %s)', v_k - 3, case when v_k - 3 = 1 then 'orçamento' else 'orçamentos' end);
    end if;
  end if;

  -- 7. como eu conto (todos os números dos parâmetros)
  -- (7a correção, achado 3) o "Como eu conto" à parte: entra sempre, no fim (_agenda_gestor_juntar)
  v_como := format('Como eu conto: estimativa pelo valor do orçamento (R$ %s de mão de obra por diária, sem deslocamento); '
                       || '%s por serviço (dupla quando você marcar); peça sem fornecedor: %s; peça abaixo de R$ %s: separar na '
                       || 'véspera; entre decidir e comprar: %s%s; pergunto antes acima de %s diárias e quando o serviço já começou.',
                       replace(to_char(round(v_mo), 'FM999,999,990'), ',', '.'),
                       case when cf.equipe_padrao = 1 then '1 pessoa' else cf.equipe_padrao || ' pessoas' end,
                       public._agenda_plural(cf.prazo_sem_fornecedor_du, 'dia útil', 'dias úteis'),
                       replace(to_char(round(cf.critico_valor_min), 'FM999,999,990'), ',', '.'),
                       public._agenda_plural(cf.compra_interna_du, 'dia útil', 'dias úteis'),
                       case when cf.compra_urgente_du > 0
                            then format(' (com o serviço a menos de %s, a compra é para hoje)',
                                        public._agenda_plural(cf.compra_urgente_du, 'dia útil', 'dias úteis'))
                            else '' end,
                       public._agenda_num(cf.estimativa_max_diarias));

  -- (7a correção, achado 3) o conteúdo até texto_max, e o "Como eu conto" (os parâmetros, spec §6.2 item 7) depois dele: as 7 seções
  -- da spec não cabem em texto_max com ele dentro, e era ele que sumia
  return jsonb_build_object('ok', true, 'texto', public._agenda_gestor_juntar(v_l, cf.texto_max + 1 + char_length(v_como), v_como),
                            'dados', jsonb_build_object('modo', v_ef, 'so_propor', cf.gestor_so_propor, 'conta_de', v_sdia,
                                                        'sombra', v_s, 'fora', v_fora));
end;
$function$;

comment on function public._agenda_ver_gestor(date) is
  'Agenda de Produção (Fase 7a, P7; spec §6.2): o foco gestor de agenda_ver — (1) o estado: "O gestor está em teste desde qui 29/10: calcula o que marcaria, mas não muda nada." / "Eu marco sozinho desde ter 03/11 e te conto no fechamento; *desfaz <nome>* volta qualquer coisa que eu fiz." / "Desde sex 06/11 você pediu *gestor, só propor*: eu só sugiro. *gestor, pode marcar* volta." / desligado; (2) em teste, "Eu marcaria:" pela última conta do diário (agenda_gestor_dia.sombra), um por linha ("• Lenine: ter 03 a ter 10/11, Roberto e João — 6 dias (estimativa minha). Pode precisar de dupla (banco de baterias): diga *Lenine com dupla*."); ligado, "Marquei nos últimos 7 dias:" (as OS com compromisso vigente pela estimativa); (3) "Antes de marcar eu perguntaria:" (teste) ou "Perguntei antes de marcar:" com o prazo ("• Giancarlo: 10 diárias pela estimativa — sem resposta até sex 30/10 18:00, marco assim."); (4) "Fora:" agrupado pelo porquê ("esperando o cliente: Kalmar (2) e Rodrigo; …"; ligado, pela última conta de verdade do motor em 8 dias); (5) "Compras da semana:" e (6) "Se aprovar:" pelo diário (agenda_gestor_dia.compras e .orcamentos, [{texto}], de até 3 dias; o P10 e o P12 gravam); (7) "Como eu conto:" com os parâmetros. {ok, texto (≤ texto_max), dados}. STABLE, invoker. CORREÇÃO DA 7a (revisão da etapa; achado 3): o "Como eu conto" entra sempre, no fim (_agenda_gestor_juntar: o corte é no meio, nunca num título sem linha embaixo, como o "Se aprovar:" vazio); as compras da semana e o "Se aprovar" mostram até 3 cada (o resto: "(e mais 3 orçamentos)", "(e mais N em *agenda compras*)"). CORREÇÃO 2 DA 7a (a 2ª revisão da etapa): (a dupla sem a 2ª pessoa) com menos de 2 técnicos na grade, "Pode precisar de dupla (banco de baterias): hoje só Alex está na equipe: para ir dupla, chame um ajudante e diga *Lenine com dupla*."; (o desfaz) ligado, a OS de fora que o dono desfez vai no grupo "você desfez (me diga os dias para eu marcar de novo)", não em "sem lugar na agenda"; (o número) em "Perguntei antes de marcar", o número da OS junto quando o nome se repete ("Kalmar (OS-00032)"). FASE 7b (P6, R4.4): com modo_chamar fora de desligado, o bloco "Quem chamar" depois de "Perguntei antes de marcar" — o que o passo diário chamar do gestor gravou (agenda_gestor_dia.chamar, a conta mais nova de até 3 dias; "pela conta de …" quando não é de hoje): "Quem chamar (só sugiro; quem chama é você):" e uma linha por sugestão, ou "Quem chamar: ninguém — a equipe de hoje dá conta da carteira que está pronta."; em teste, "Em teste: quem chamar …". Com modo_dupla fora de desligado, o "Pode precisar de dupla (…): … diga *Lenine com dupla*" do 7a vira a frase da dupla de 1 pessoa (R4.3(a)(3)): ligado, com as datas do plano (_agenda_dupla_no_plano: "Nos 2 primeiros meios-dias (ter 10/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem ter 10/11)."; com a dupla completa, nada); em teste do gestor, a forma curta sem as datas. Com modo_chamar e modo_dupla desligados, a de antes, byte a byte.';

-- agenda_livre_de_verdade (de 20261031100980_agenda_fase77a_correcao.sql)
create or replace function public.agenda_livre_de_verdade(p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  -- quantas semanas o livre mostra (a 1ª é a do 1º dia que a agenda ainda pode mudar) e quantas vão na linha da semana
  c_semanas  constant int := 3;
  c_na_linha constant int := 2;
  cf       public.agenda_config := public._agenda_cfg();
  v_uid    uuid := auth.uid();
  v_t0     timestamptz := clock_timestamp();
  v_g      jsonb;
  v_ctx    jsonb;
  v_ini    date;
  v_de     date;
  v_minh   int;
  v_nh     int;
  v_nw     int;
  v_np     int;
  v_dono   int;
  v_padrao boolean;
  v_util   boolean[];
  v_sem    int[];
  v_cap    int[];
  v_ocup   int[];
  v_t80    int[];
  v_t100   int[];
  v_uc     int[];
  v_ur     int[];
  v_pes    uuid[];
  v_nomes  text[];
  v_seg1   date;
  v_ate    date;
  v_seg    date;
  v_d0     date;
  v_d1     date;
  v_dsem   date;
  v_w      int;
  k        int;
  v_pessoas jsonb;
  v_semanas jsonb := '[]'::jsonb;
  v_quem   text;
  v_rot    text;
  v_plano  uuid[];
  v_ocupa  jsonb;
  v_pn     jsonb;
  v_trav   jsonb;
  v_pront  jsonb;
  v_andam  jsonb;
  v_parad  int;
  v_esp    int;
  v_lin    text[];
  v_curta  text[] := '{}';
  v_txt    text;
  v_linha  text;
  -- CORREÇÃO 29/10 (revisão): a 1ª semana da linha curta foi pela metade
  v_meia   boolean := false;
  -- CORREÇÃO 29/10 (revisão): fim
  -- FASE 7: (7a correção, achado 23) o teto da equipe-semana e o dono fora da conta de técnico
  v_f77_teq  boolean := public._agenda_gestor_regra('teto_equipe');
  v_f77_te   int[];
  v_f77_rest int;
  -- FASE 7: fim
  -- FASE 7b: (7b P6) a linha de quem chamar
  v_7b_liv text;
  -- FASE 7b: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_livre_de_verdade: sem o dia ou a hora de agora' using errcode = '22004';
  end if;
  -- Quem vê: com login, só administrador e financeiro; sem login, o service_role (o assistente pelo WhatsApp).
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  -- O plano só manda em 'ligado': fora disso, quem chama usa a projeção da Fase 1 (fila ÷ capacidade).
  if cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('fonte', 'projecao', 'motivo', 'a agenda automática não está ligada');
  end if;

  -- A grade do motor de agora (o plano vigente inteiro: o marcado e o reservado).
  v_g := public._agenda_grade_de_agora(p_hoje);
  v_ctx := v_g -> 'ctx';
  v_ini := (v_g ->> 'ini')::date;
  v_de := (v_g ->> 'de')::date;
  v_minh := (v_g ->> 'min_h')::int;
  v_nh := (v_ctx ->> 'nh')::int;
  v_nw := (v_ctx ->> 'nw')::int;
  v_np := (v_ctx ->> 'np')::int;
  v_dono := coalesce((v_ctx ->> 'dono')::int, 0);
  v_padrao := coalesce((v_ctx ->> 'dono_tem_padrao')::boolean, false);
  v_util := public._agenda_bools(v_ctx -> 'util');
  v_sem := public._agenda_ints(v_ctx -> 'sem');
  v_cap := public._agenda_ints(v_ctx -> 'cap');
  v_ocup := public._agenda_ints(v_ctx -> 'ocup');
  v_t80 := public._agenda_ints(v_ctx -> 'teto80');
  v_t100 := public._agenda_ints(v_ctx -> 'teto100');
  v_uc := public._agenda_ints(v_ctx -> 'uso_c');
  v_ur := public._agenda_ints(v_ctx -> 'uso_r');
  v_pes := array(select x::uuid from jsonb_array_elements_text(v_ctx -> 'pessoas') with ordinality t(x, o) order by o);
  v_nomes := array(select x from jsonb_array_elements_text(v_ctx -> 'nomes') with ordinality t(x, o) order by o);
  v_seg1 := v_de - (extract(isodow from v_de)::int - 1);
  v_ate := v_seg1 + 7 * (c_semanas - 1) + 5;

  -- ── As semanas: quantos meios-dias cada pessoa ainda pega (a conta do encaixe) ──
  for k in 0 .. c_semanas - 1 loop
    v_seg := v_seg1 + 7 * k;
    v_w := (v_seg - v_ini) / 7 + 1;
    exit when v_w > v_nw;
    -- o 1º e o último dia útil que contam (na 1ª semana, a partir do 1º dia que a agenda ainda pode mudar) e o 1º da semana
    select min(g::date) filter (where g::date >= v_de), max(g::date) filter (where g::date >= v_de), min(g::date)
      into v_d0, v_d1, v_dsem
      from generate_series(v_seg, v_seg + 5, interval '1 day') g
     where public.agenda_dia_util(g::date);
    continue when v_d0 is null;
    select coalesce(jsonb_agg(jsonb_build_object(
             'payee_id', v_pes[s.q], 'nome', case when s.q = v_dono then 'você' else v_nomes[s.q] end, 'eh_dono', s.q = v_dono,
             'meios', s.meios, 'celulas', s.cels, 'teto', s.t80, 'compromisso', s.uc, 'reserva', s.ur)
             order by s.meios desc, s.q), '[]'::jsonb)
      into v_pessoas
      from (select z.q, z.cels, z.t80, z.uc, z.ur, greatest(0, least(z.t80 - z.uc, z.t100 - z.uc - z.ur, z.cels)) as meios
              from (select q,
                           v_t80[(q - 1) * v_nw + v_w] as t80, v_t100[(q - 1) * v_nw + v_w] as t100,
                           v_uc[(q - 1) * v_nw + v_w] as uc, v_ur[(q - 1) * v_nw + v_w] as ur,
                           (select count(*)::int from generate_series(1, v_nh) h
                             where v_sem[(h + 1) / 2] = v_w and v_util[(h + 1) / 2] and h >= v_minh
                               and v_cap[(q - 1) * v_nh + h] = 1 and v_ocup[(q - 1) * v_nh + h] = 0) as cels
                      from generate_series(1, v_np) q
                     where q <> v_dono or v_padrao) z) s;
    -- FASE 7: (7a correção, achado 23) com a regra teto_equipe (o motor do gestor): o dono não é vaga de técnico — o motor nunca o
    -- põe no turno de um serviço novo, só para abrir, fechar e no diagnóstico —, então sai da conta mesmo com os dias dele em
    -- campo; e a equipe não pega na semana mais do que teto_equipe − o compromisso dela (a mesma conta do encaixe), repartido de
    -- quem tem mais para quem tem menos (a ordem de v_pessoas). Antes, com a linha do dono, o *livre* prometia "você 2 dias, Alex
    -- nada" e "Alex 1 dia" com a equipe já no teto.
    if v_f77_teq then
      v_f77_te := coalesce(v_f77_te, public._agenda_ints(v_ctx -> 'teto_equipe'));
      v_f77_rest := case when v_w <= coalesce(cardinality(v_f77_te), 0)
                         then greatest(0, v_f77_te[v_w] - (select coalesce(sum(v_uc[(q - 1) * v_nw + v_w]), 0)::int
                                                              from generate_series(1, v_np) q where q <> v_dono)) end;
      select coalesce(jsonb_agg(case when v_f77_rest is null then p.e
                                     else p.e || jsonb_build_object('meios', greatest(0, least(p.acum, v_f77_rest)
                                                                                       - least(p.acum - (p.e ->> 'meios')::int, v_f77_rest))) end
                                order by p.o), '[]'::jsonb)
        into v_pessoas
        from (select t.e, t.o, sum((t.e ->> 'meios')::int) over (order by t.o) as acum
                from jsonb_array_elements(v_pessoas) with ordinality t(e, o)
               where not coalesce((t.e ->> 'eh_dono')::boolean, false)) p;
    end if;
    -- FASE 7: fim
    v_quem := case
      when jsonb_array_length(v_pessoas) = 0 then 'ninguém da equipe tem os dias na agenda'
      when not exists (select 1 from jsonb_array_elements(v_pessoas) e where (e ->> 'meios')::int > 0) then 'ninguém livre'
      else array_to_string(array(select format('%s %s', e ->> 'nome', public._agenda_meios_texto((e ->> 'meios')::int))
                                   from jsonb_array_elements(v_pessoas) with ordinality t(e, o) order by o), ', ') end;
    -- (a 1ª semana pela metade: "De qua 04 a sex 06/11"; um dia só: "Sex 06/11")
    v_rot := case when v_d0 = v_dsem then public._agenda_titulo_da_semana(v_seg)
                  when v_d0 = v_d1 then public._agenda_maiuscula(public._dia_curto(v_d0))
                  else format('De %s a %s', case when to_char(v_d0, 'MM') = to_char(v_d1, 'MM') then public._agenda_dia_sem_mes(v_d0)
                                                 else public._dia_curto(v_d0) end, public._dia_curto(v_d1)) end;
    v_semanas := v_semanas || jsonb_build_object('seg', v_seg, 'de', v_d0, 'ate', v_d1, 'rotulo', v_rot, 'pessoas', v_pessoas,
                                                 'texto', format('• %s: %s.', v_rot, v_quem));
    if jsonb_array_length(v_semanas) <= c_na_linha then
      v_curta := v_curta || format('%s %s, %s', case when jsonb_array_length(v_semanas) = 1 then 'na semana de' else 'na de' end,
                                   to_char(v_d0, 'DD/MM'), v_quem);
    end if;
    -- CORREÇÃO 29/10 (revisão): a 1ª semana pela metade (o 1º dia que a agenda ainda pode mudar cai no meio dela) não
    -- é "a semana de 04/11" (04/11 é quarta): sai o rótulo do *livre* ("de qua 04 a sex 06/11"; um dia só, "na sex 06/11"), e a
    -- seguinte vira "na semana de 09/11".
    if jsonb_array_length(v_semanas) <= c_na_linha then
      if v_d0 <> v_dsem then
        v_curta[cardinality(v_curta)] := format('%s, %s', case when v_d0 = v_d1 then 'na ' || public._dia_curto(v_d0)
                                                               else 'de ' || substr(v_rot, 4) end, v_quem);
        v_meia := true;
      elsif v_meia and jsonb_array_length(v_semanas) = 2 then
        v_curta[cardinality(v_curta)] := format('na semana de %s, %s', to_char(v_d0, 'DD/MM'), v_quem);
      end if;
    end if;
    -- CORREÇÃO 29/10 (revisão): fim
  end loop;

  -- ── O que ocupa a equipe: o plano de hoje ao sábado da última semana, por OS, com quem fica o turno ──
  -- (o nome como nas outras listas da agenda: o número só quando o nome se repete na carteira, "Rodrigo OS-00096")
  v_pn := public._agenda_painel(p_hoje);
  v_plano := array(select distinct a.service_order_id from public.agenda_alocacoes a
                    where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje);
  select coalesce(jsonb_agg(jsonb_build_object(
           'os', z.os, 'numero', z.numero, 'reserva', z.reserva, 'dias', to_jsonb(z.dias), 'pessoas', z.pessoas,
           'texto', format('%s (%s%s%s)', z.nome, case when z.reserva then 'reserva, ' else '' end, public._agenda_dias_texto(z.dias),
                           coalesce(', com ' || nullif(z.pessoas, ''), '')))
           order by z.d1, z.numero collate "C"), '[]'::jsonb)
    into v_ocupa
    from (select y.*
            from (select v.service_order_id as os, min(v.numero) as numero,
                         coalesce((select public._agenda_rotulo(e, 'np') from jsonb_array_elements(coalesce(v_pn -> 'oss', '[]'::jsonb)) e
                                    where (e ->> 'os')::uuid = v.service_order_id limit 1),
                                  min(v.cliente_curto), min(v.numero)) as nome,
                         bool_and(v.reserva) as reserva, min(v.dia) as d1, array_agg(v.dia order by v.dia) as dias,
                         (select public._agenda_lista(array_agg(p.quem order by p.dono desc, p.primeiro, p.quem), null)
                            from (select case when coalesce((x ->> 'eh_dono')::boolean, false) then 'você' else x ->> 'nome' end
                                           as quem,
                                         bool_or(coalesce((x ->> 'eh_dono')::boolean, false)) as dono, min(v2.dia) as primeiro
                                    from public.v_agenda_dia v2
                                   cross join lateral jsonb_array_elements(v2.pessoas) x
                                   where v2.service_order_id = v.service_order_id and v2.dia between p_hoje and v_ate
                                     and x ->> 'presenca' = 'turno'
                                   group by 1) p
                           where p.quem is not null) as pessoas
                    from public.v_agenda_dia v
                   where v.dia between p_hoje and v_ate
                   group by v.service_order_id) y) z;

  -- ── O que não ocupa ninguém: a carteira fora do plano ──
  select coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> 'ordem')::int)
                    filter (where e ->> 'grupo' in ('quase', 'travado', 'esperando')), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> 'ordem')::int) filter (where e ->> 'grupo' = 'pronto'), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('o', e) order by (e ->> 'ordem')::int)
                    filter (where e ->> 'grupo' in ('andamento', 'marcado')), '[]'::jsonb),
         count(*) filter (where e ->> 'grupo' = 'parado')::int,
         count(*) filter (where e ->> 'grupo' = 'espera')::int
    into v_trav, v_pront, v_andam, v_parad, v_esp
    from jsonb_array_elements(coalesce(v_pn -> 'oss', '[]'::jsonb)) e
   where not ((e ->> 'os')::uuid = any (v_plano));

  -- ── O texto ──
  v_lin := array['Livre de verdade (pelo plano de agora e pelos dias que cada um vem):']
           || array(select e ->> 'texto' from jsonb_array_elements(v_semanas) with ordinality t(e, o) order by o);
  -- FASE 7: (7a correção, achado 23) com a regra teto_equipe, o dono com os dias em campo também fica fora da conta de técnico
  if v_dono > 0 and v_padrao and v_f77_teq then
    v_lin := v_lin || 'Você não entra na conta: em campo você acompanha, abre e fecha (o diagnóstico é com você).'::text;
  end if;
  -- FASE 7: fim
  if v_dono > 0 and not v_padrao then
    v_lin := v_lin || 'Você fica de fora da conta: não sei em que dias você fica em campo (é só me dizer, por exemplo, "fico em campo de segunda a sexta").'::text;
  end if;
  v_lin := v_lin || case
    when jsonb_array_length(v_ocupa) = 0 then format('Até %s, nada do plano ocupa a equipe.', public._dia_curto(v_ate))
    else 'Ocupa a equipe: '
         || public._agenda_lista(array(select e ->> 'texto' from jsonb_array_elements(v_ocupa) with ordinality t(e, o) order by o), 3)
         || case when jsonb_array_length(v_ocupa) > 3 then ' (*agenda plano* mostra tudo)' else '' end || '.' end;
  if jsonb_array_length(v_trav) > 0 or v_parad > 0 or v_esp > 0 then
    v_lin := v_lin || ('Não ocupam ninguém até destravar: '
                       || concat_ws('; ', nullif(public._agenda_nomes(v_trav, 3), ''),
                                    case when v_parad > 0 then public._agenda_plural(v_parad, 'parado no cliente', 'parados no cliente') end,
                                    case when v_esp > 0 then public._agenda_plural(v_esp, 'em espera (você pediu)', 'em espera (você pediu)') end)
                       || '.');
  end if;
  if jsonb_array_length(v_pront) > 0 then
    v_lin := v_lin || (case when jsonb_array_length(v_pront) = 1 then 'Pronto, mas ainda sem lugar no plano (não entra na conta): '
                            else 'Prontos, mas ainda sem lugar no plano (não entram na conta): ' end
                       || public._agenda_nomes(v_pront, 3) || '.');
  end if;
  if jsonb_array_length(v_andam) > 0 then
    v_lin := v_lin || ('Em andamento sem dia no plano (não entra na conta): ' || public._agenda_nomes(v_andam, 3) || '.');
  end if;
  v_lin := v_lin || 'Para um serviço novo, me diga quantos dias e com quem, que eu digo o 1º dia que cabe.'::text;
  -- FASE 7b: (7b P6, R4.4 "*livre*") com quem chamar ligado, no fim: o que fica sem lugar com a equipe de hoje e quantos meios-dias
  -- de mais uma pessoa fazem caber (o passo diário chamar do gestor, a conta mais nova de até 3 dias): "Sem lugar com a equipe de hoje:
  -- Nelson e César. Com mais uma pessoa 9 meios-dias, cabem até 20/11 (*agenda gestor* diz quando)."
  if cf.modo_chamar = 'ligado' then
    v_7b_liv := (select g.chamar ->> 'texto_livre' from public.agenda_gestor_dia g
                  where g.dia <= p_hoje and g.dia >= p_hoje - 3 and g.chamar ? 'calculado_em' order by g.dia desc limit 1);
    if nullif(btrim(coalesce(v_7b_liv, '')), '') is not null then
      v_lin := v_lin || v_7b_liv;
    end if;
  end if;
  -- FASE 7b: fim
  v_txt := public._agenda_juntar(v_lin, cf.texto_max);
  v_linha := 'Livre de verdade: '
             || coalesce(nullif(array_to_string(v_curta, '; '), ''), 'não tenho os dias da equipe nas próximas semanas') || '.';

  return jsonb_build_object(
    'fonte', 'simulacao', 'base', 'plano', 'de', v_de, 'ate', v_ate, 'semanas', v_semanas,
    'voce_fora', v_dono > 0 and not v_padrao, 'ocupa', v_ocupa,
    'nao_ocupam', jsonb_build_object(
      'travados', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb) from jsonb_array_elements(v_trav) with ordinality t(e, o)),
      'prontos', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb) from jsonb_array_elements(v_pront) with ordinality t(e, o)),
      'andamento', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb) from jsonb_array_elements(v_andam) with ordinality t(e, o)),
      'parados', v_parad, 'em_espera', v_esp),
    'texto', v_linha, 'texto_completo', v_txt,
    'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$function$;

comment on function public.agenda_livre_de_verdade(date, timestamptz) is
  'Agenda de Produção (Fase 3, P6; REESCRITA na correção de 29/10, P2): "quando a gente fica livre de verdade?" pelo plano e pelo teto de cada pessoa — só com modo_proposta ligado (fora disso {fonte: projecao}: quem chama usa a frase da Fase 1). Para cada uma das 3 semanas a partir do 1º dia que a agenda ainda pode mudar (o dia útil depois do congelado), os meios-dias que cada pessoa ainda pega num serviço novo, a mesma conta do encaixe: o menor entre teto80 − compromisso, teto100 − compromisso − reserva e os meios-dias dela livres na grade (_agenda_grade_de_agora: o marcado e o reservado ocupam); o dono só com os dias dele em campo (sem eles, voce_fora e a frase "Você fica de fora da conta"). Depois, o que ocupa a equipe (o plano de hoje ao sábado da última semana, por OS, com quem fica o turno), o que não ocupa ninguém até destravar (a carteira fora do plano: travados, esperando o dono, parados no cliente, em espera; o pronto sem lugar; o em andamento sem dia) e como perguntar de um serviço novo. {fonte: simulacao (o sinal de "use o texto daqui" para a agenda_ver e a agenda_tela_semana), base: plano, de, ate, semanas[{seg, de, ate, rotulo, pessoas[{payee_id, nome, eh_dono, meios, celulas, teto, compromisso, reserva}], texto}], voce_fora, ocupa[{os, numero, reserva, dias, pessoas, texto}], nao_ocupam{travados, prontos, andamento, parados, em_espera}, texto (a linha da semana e da tela: "Livre de verdade: na semana de 03/11, Roberto 1 dia e meio, João nada; na de 09/11, Roberto 3 dias, João 1 dia."), texto_completo (a resposta do *livre*, até texto_max), ms}. Nada é gravado. STABLE, definer (as peças do motor são só do service_role); administrador e financeiro com login, ou o service_role. CORREÇÃO 29/10 (revisão): na linha curta (texto), a 1ª semana pela metade sai com o rótulo do *livre* ("Livre de verdade: de qua 04 a sex 06/11, Roberto 1 dia, João nada; na semana de 09/11, …"; um dia só, "na sex 06/11"), não "na semana de 04/11". CORREÇÃO DA 7a (revisão da etapa; achado 23): com a regra teto_equipe do gestor, (1) o dono não entra na conta do livre como técnico, mesmo com os dias em campo (o motor só o põe para abrir, fechar e no diagnóstico): "Você não entra na conta: em campo você acompanha, abre e fecha (o diagnóstico é com você)."; (2) os meios-dias da equipe na semana não passam do teto da equipe-semana (teto_equipe − o compromisso da equipe nela), repartidos de quem tem mais para quem tem menos. Sem a regra, a de antes, byte a byte. FASE 7b (P6, R4.4): com modo_chamar ligado, no fim do texto_completo, a linha de quem chamar do diário do gestor (a conta mais nova de até 3 dias, chamar.texto_livre): "Sem lugar com a equipe de hoje: Nelson e César. Com mais uma pessoa 9 meios-dias, cabem até 20/11 (*agenda gestor* diz quando)." Sem ela, ou fora de ligado, a de antes, byte a byte.';

-- _agenda_dias_semana_motivos (de 20261101100200_agenda_fase7b_pergunta_semanal.sql)
create or replace function public._agenda_dias_semana_motivos(p_seg date, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  -- estrutural: a mesma janela da proposta que _agenda_vigia_padrao_do_dono lê (o "fora por padrao_do_dono" da última semana)
  c_fora_dias constant int := 7;
  cf       public.agenda_config := public._agenda_cfg();
  v_dono   uuid := public._agenda_dono(null);
  v_mot    text[] := '{}';
  v_partes jsonb := '[]'::jsonb;
  v_fora   jsonb;
  v_os     uuid[];
  v_itens  text[];
  r        record;
  -- FASE 7b: (7b P6) o motivo chamar
  v_7b_ch    jsonb;
  v_7b_ps    jsonb;
  v_7b_txt   text;
  v_7b_ini   text;
  v_7b_fim   text;
  v_7b_nomes text[];
  -- FASE 7b: fim
begin
  if p_seg is null or p_hoje is null then
    raise exception '_agenda_dias_semana_motivos: sem a semana ou o dia' using errcode = '22004';
  end if;
  if extract(isodow from p_seg)::int <> 1 then
    raise exception '_agenda_dias_semana_motivos: a semana começa na segunda (veio %)', p_seg using errcode = '22023';
  end if;

  -- dono_sem_padrao
  if 'dono_sem_padrao' = any (cf.dias_semana_motivos) and v_dono is not null
     and public._agenda_dias_declarados(v_dono, p_seg) ->> 'fonte' = 'nenhum'
     and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'padrao_do_dono' and q.estado = 'aberta') then
    select p.fora into v_fora from public.agenda_propostas p
     where p.modo = cf.modo_proposta and (p.criada_em at time zone 'America/Sao_Paulo')::date > p_hoje - c_fora_dias
     order by p.criada_em desc, p.id desc limit 1;
    select coalesce(array_agg(z.os order by z.dele desc, z.numero collate "C", z.os), '{}'::uuid[]),
           coalesce(array_agg(case when z.motivo is not null
                                   then regexp_replace(public._agenda_rotulo_da_os(z.os), '\)$', ', ' || z.motivo || ')')
                                   else public._agenda_rotulo_da_os(z.os) end
                              order by z.dele desc, z.numero collate "C", z.os), '{}'::text[])
      into v_os, v_itens
      from (select k.service_order_id as os, k.numero, m.x ->> 'presenca' as presenca, m.x ->> 'regra_motivo' as motivo,
                   coalesce(m.x ->> 'regra_motivo', '') in ('diagnóstico', 'comissionamento') as dele,
                   exists (select 1 from jsonb_array_elements(coalesce(v_fora, '[]'::jsonb)) f
                            where f ->> 'motivo' in ('padrao_do_dono', 'so_com_voce') and f ->> 'os' = k.service_order_id::text) as fora
              from public.os_carteira(p_hoje) k
              cross join lateral (select public.agenda_meios_da_os(k.service_order_id, p_hoje) as x) m) z
     where z.presenca in ('sempre', 'equipe') or z.dele or z.fora;
    if cardinality(v_os) > 0 then
      v_mot := v_mot || 'dono_sem_padrao'::text;
      v_partes := v_partes || jsonb_build_array(jsonb_build_object('motivo', 'dono_sem_padrao', 'os', to_jsonb(v_os),
        'texto', format('%s %s de você em campo e eu não sei seus dias: conto que você só abre e fecha.',
                        public._agenda_lista(v_itens, 2), case when cardinality(v_os) = 1 then 'precisa' else 'precisam' end)));
    end if;
  end if;

  -- semente
  if 'semente' = any (cf.dias_semana_motivos) then
    for r in select g.payee_id, g.pessoa, d.v
               from (select distinct k.payee_id, k.pessoa from public.agenda_capacidade(p_seg, p_seg + 5, p_hoje) k where not k.eh_dono) g
               cross join lateral (select public._agenda_dias_declarados(g.payee_id, p_seg) as v) d
              where d.v ->> 'fonte' = 'historico' and not public._agenda_equipe_tem_telefone(g.payee_id)
              order by g.pessoa, g.payee_id loop
      if not ('semente' = any (v_mot)) then
        v_mot := v_mot || 'semente'::text;
      end if;
      v_partes := v_partes || jsonb_build_array(jsonb_build_object('motivo', 'semente', 'payee', r.payee_id,
        'texto', format('%s (sem telefone): conto %s, pelo que veio nas últimas %s semanas.', r.pessoa, r.v ->> 'texto',
                        cf.medicao_semanas)));
    end loop;
  end if;

  -- FASE 7b: (7b P6, R4.2(b), R4.4) chamar: a sugestão de quem chamar (o passo diário chamar do gestor, 16:53) com meios-dias na
  -- semana p_seg ou depois, lida do diário de HOJE (agenda_gestor_dia.chamar com calculado_em de hoje; nunca calculada aqui), só com
  -- modo_chamar ligado. O texto: as partes da sugestão nessa semana ou depois, na ordem (a dupla, o prazo, a capacidade), e "Quem
  -- chama é você."; com a pergunta inteira (o começo da rodada da semana, as partes de antes, esta e o fim com as opções) acima de
  -- 600 letras, a forma curta ("Lenine e Nelson precisam de mais gente: *agenda gestor* diz quem chamar e quando.").
  if 'chamar' = any (cf.dias_semana_motivos) and cf.modo_chamar = 'ligado' then
    select g.chamar into v_7b_ch from public.agenda_gestor_dia g
     where g.dia = p_hoje and g.chamar ->> 'calculado_em' is not null
       and ((g.chamar ->> 'calculado_em')::timestamptz at time zone 'America/Sao_Paulo')::date = p_hoje;
    select coalesce(jsonb_agg(t.p order by t.o), '[]'::jsonb) into v_7b_ps
      from jsonb_array_elements(coalesce(v_7b_ch -> 'partes', '[]'::jsonb)) with ordinality t(p, o)
     where exists (select 1 from jsonb_array_elements_text(coalesce(t.p -> 'dias', '[]'::jsonb)) dd(d) where dd.d::date >= p_seg);
    if jsonb_array_length(v_7b_ps) > 0 then
      v_7b_txt := (select string_agg(t.p ->> 'texto', ' ' order by t.o) from jsonb_array_elements(v_7b_ps) with ordinality t(p, o))
                  || ' Quem chama é você.';
      v_7b_ini := format('Semana de %s: ', to_char(p_seg, 'DD/MM'))
        || coalesce((select 'conto com ' || public._agenda_lista(array_agg(z.item order by z.pessoa, z.payee_id), null) || '.'
                       from (select k.payee_id, k.pessoa,
                                    k.pessoa || ' ' || (d.v ->> 'texto')
                                    || case when d.v ->> 'fonte' = 'historico' then ' (pelo histórico)'
                                            when d.v ->> 'origem' = 'dono' then ' (você disse)'
                                            when d.v ->> 'origem' = 'diarista'
                                              then format(' (disse em %s)', to_char((d.v ->> 'dito_em')::timestamptz at time zone 'America/Sao_Paulo', 'DD/MM'))
                                            else '' end as item
                               from (select distinct c.payee_id, c.pessoa from public.agenda_capacidade(p_seg, p_seg + 5, p_hoje) c
                                      where not c.eh_dono) k
                               cross join lateral (select public._agenda_dias_declarados(k.payee_id, p_seg) as v) d
                              where d.v ->> 'fonte' <> 'nenhum'
                                and (jsonb_array_length(d.v -> 'dias') > 0 or (d.v ->> 'sabado')::boolean)) z
                     having count(*) > 0), 'não conto com ninguém da equipe.');
      v_7b_fim := ' Se mudar algo, me diga (ex.: fico em campo seg a qua; Mateus vem ter e qua).'
                  || case when 'dono_sem_padrao' = any (v_mot)
                          then ' 1) Fica assim; 2) Fico em campo de seg a sex (recomendo); 3) Nenhum dia: só abro e fecho.'
                          else ' 1) Fica assim.' end;
      if char_length(v_7b_ini || coalesce((select string_agg(' ' || (t.p ->> 'texto'), '' order by t.o)
                                             from jsonb_array_elements(v_partes) with ordinality t(p, o)), '')
                     || ' ' || v_7b_txt || v_7b_fim) > 600 then
        v_7b_nomes := array(select y.n from (select t2.n, min(t.o) as o
                                               from jsonb_array_elements(v_7b_ps) with ordinality t(p, o)
                                               cross join lateral jsonb_array_elements_text(coalesce(t.p -> 'nomes', '[]'::jsonb)) t2(n)
                                              group by t2.n) y order by y.o, y.n);
        v_7b_txt := format('%s %s de mais gente: *agenda gestor* diz quem chamar e quando.',
                           public._agenda_lista(v_7b_nomes, cf.chamar_max_os),
                           case when cardinality(v_7b_nomes) = 1 then 'precisa' else 'precisam' end);
      end if;
      v_mot := v_mot || 'chamar'::text;
      v_partes := v_partes || jsonb_build_array(jsonb_build_object('motivo', 'chamar', 'texto', v_7b_txt,
        'os', (select coalesce(jsonb_agg(o2.v), '[]'::jsonb) from jsonb_array_elements(v_7b_ps) t(p)
                cross join lateral jsonb_array_elements(coalesce(t.p -> 'os', '[]'::jsonb)) o2(v))));
    end if;
  end if;
  -- FASE 7b: fim
  -- sempre (o "toda quinta" do corpo da spec)
  if 'sempre' = any (cf.dias_semana_motivos) then
    v_mot := v_mot || 'sempre'::text;
  end if;
  return jsonb_build_object('motivos', to_jsonb(v_mot), 'partes', v_partes);
end;
$function$;

comment on function public._agenda_dias_semana_motivos(date, date) is
  'Agenda de Produção (Fase 7b, P3; R4.2(b), AG7-02/AG7-03): por que a pergunta dias_semana nasce para o dono na semana de p_seg — só os motivos de agenda_config.dias_semana_motivos: dono_sem_padrao (o dono sem dias para a semana, _agenda_dias_declarados fonte nenhum; alguma OS da carteira precisa dele o turno inteiro — diagnóstico, comissionamento, presença sempre ou equipe — ou ficou fora por padrao_do_dono/so_com_voce na proposta da última semana; e nenhuma pergunta padrao_do_dono aberta: a da vigia pergunta uma vez, a 7b não repete): "Rodrigo (OS-00096, diagnóstico) precisa de você em campo e eu não sei seus dias: conto que você só abre e fecha."; semente (alguém da grade sem telefone cujos dias da semana vêm só da semente do histórico): "Fulano (sem telefone): conto de ter a sex, pelo que veio nas últimas 8 semanas."; sempre (toda quinta). {motivos [...], partes [{motivo, texto, os | payee}]}; sem motivo, motivos vazio (nada nasce). O motivo chamar é do P6 (20261101100500), que recria ESTA função. STABLE, invoker, sem grant (só agenda_equipe_semana a chama). FASE 7b (P6, R4.2(b), R4.4): o motivo chamar — com modo_chamar ligado e chamar em dias_semana_motivos, a sugestão de quem chamar do diário de HOJE (agenda_gestor_dia.chamar, gravada pelo passo diário chamar do gestor; nunca calculada aqui) com meios-dias na semana p_seg ou depois: a parte {motivo chamar, texto: as partes da sugestão nessa semana ou depois e "Quem chama é você.", os}; com a pergunta inteira acima de 600 letras, a forma curta ("Lenine e Nelson precisam de mais gente: *agenda gestor* diz quem chamar e quando."). Sem o diário de hoje, sem a sugestão nessa semana ou com modo_chamar fora de ligado, os motivos de antes.';

-- _agenda_gestor_corte (de 20261031100980_agenda_fase77a_correcao.sql)
create or replace function public._agenda_gestor_corte(p_os uuid, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config;
  v_cong  date;
  v_dono  uuid;
  v_m     jsonb;
  v_pront jsonb;
  v_numero text;
  v_total int;
  v_feito numeric;
  v_n     int;
  v_k     int := 0;
  v_cut   jsonb := '[]'::jsonb;
  v_meios jsonb := '[]'::jsonb;
  v_fe    boolean := false;
  v_ult   record;
  v_itens jsonb;
  v_partes text[];
  v_txt   text;
  v_base  jsonb;
  v_val   jsonb;
  r       record;
  -- (7a correção, achado 16) a conta em pessoa-meio-dia
  v_pm    jsonb;
  v_sobra numeric;
  v_kpm   numeric := 0;
  v_npm   int;
  -- FASE 7b: (7b P6) a sobra que vem da dupla completada
  v_7b_ni    int;
  v_7b_nf    int;
  v_7b_todos boolean;
  v_7b_conta boolean;
  v_7b_prin  uuid;
  v_7b_extra int;
  v_7b_quem  uuid[];
  v_7b_dias  date[];
  -- FASE 7b: fim
begin
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_corte: faltam a OS, o dia ou a hora' using errcode = '22004';
  end if;
  select so.service_order_number into v_numero from public.service_orders so where so.id = p_os;
  v_m := public.agenda_meios_da_os(p_os, p_hoje);
  v_total := (v_m ->> 'total')::int;
  v_feito := coalesce((v_m ->> 'cumpridos')::numeric, 0) + coalesce((v_m ->> 'vigentes')::numeric, 0);
  v_base := jsonb_build_object('os', p_os, 'numero', v_numero, 'fonte', v_m ->> 'fonte', 'total', v_total, 'feitos', v_feito,
                               'cortar', 0, 'cortados', '[]'::jsonb, 'itens', '[]'::jsonb, 'texto', null);
  if not coalesce((v_m ->> 'ok')::boolean, false) or v_total is null then
    return v_base || jsonb_build_object('motivo', 'sem_dias');
  end if;
  -- (7a correção, achado 16) a sobra em pessoa-meio-dia (_agenda_gestor_pessoa_meios), não em meio-dia de calendário: o plano
  -- de 1 pessoa × 6 dias que ganhou a dupla dita (2 pessoas × 3 dias) tem o que a estimativa pede, e nada sai. v_n é o teto de
  -- meios-dias de calendário (cada um tem ao menos uma pessoa); o laço para quando as pessoas do meio-dia não cabem na sobra.
  v_pm := public._agenda_gestor_pessoa_meios(p_os, p_hoje, v_m);
  v_sobra := coalesce((v_pm ->> 'tem')::numeric - (v_pm ->> 'precisa')::numeric, 0);
  v_n := floor(v_sobra)::int;
  if v_n < 1 then
    return v_base || jsonb_build_object('sobra', greatest(v_n, 0), 'motivo', 'nada_a_cortar');
  end if;
  cf := public._agenda_cfg();
  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);
  v_dono := public._agenda_dono(null);

  -- do último meio-dia para trás: sai enquanto pode sair
  for r in
    select a.dia, a.turno,
           jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'payee_id', a.payee_id, 'nome', public._agenda_nome_curto(py.name),
                                        'dia', a.dia, 'turno', a.turno, 'presenca', a.presenca, 'estado', a.estado,
                                        'fixado_por', a.fixado_por, 'tipo', a.tipo)
                     order by a.presenca <> 'turno', a.payee_id) as alocs,
           bool_and(a.estado = 'publicada') as pub,
           bool_or(public._agenda_dia_avisado(a.payee_id, a.service_order_id, a.dia) is not null) as avisado,
           min(lower(a.periodo)) as ini,
           bool_or(a.presenca = 'fechamento' and a.payee_id is not distinct from v_dono) as fecha,
           min(a.tipo) as tipo
      from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
       and a.resultado is null
     group by a.dia, a.turno
     order by a.dia desc, a.turno = 'tarde' desc
  loop
    exit when v_k >= v_n;
    exit when not r.pub or r.avisado or r.dia <= v_cong or r.ini <= p_agora;
    -- (7a correção, achado 16) o meio-dia sai inteiro só se as pessoas de turno dele cabem na sobra em pessoa-meio-dia
    v_npm := (select count(*) from jsonb_array_elements(r.alocs) x where x ->> 'presenca' = 'turno')::int;
    exit when v_kpm + v_npm > v_sobra;
    v_kpm := v_kpm + v_npm;
    v_cut := v_cut || r.alocs;
    v_meios := v_meios || jsonb_build_object('dia', r.dia, 'turno', r.turno);
    v_fe := v_fe or r.fecha;
    v_k := v_k + 1;
  end loop;
  if v_k = 0 then
    return v_base || jsonb_build_object('sobra', v_n, 'ficou', v_n, 'motivo', 'nada_pode_sair');
  end if;
  v_pront := public.os_prontidao(p_os, p_hoje);
  v_itens := jsonb_build_array(jsonb_build_object(
    'op', 'cancelar', 'os', p_os, 'numero', v_numero, 'cliente_curto', v_pront ->> 'cliente_curto',
    'tipo', (select min(x ->> 'tipo') from jsonb_array_elements(v_cut) x), 'motivo', 'reestimada', 'violada', false,
    'alocacoes', v_cut, 'de', (select min(x ->> 'dia') from jsonb_array_elements(v_cut) x),
    'ate', (select max(x ->> 'dia') from jsonb_array_elements(v_cut) x), 'critica', null, 'decisao', null, 'aplicado', false,
    'texto', null));
  -- o fechamento do dono que saiu volta no novo último meio-dia de compromisso
  if v_fe then
    select a.dia, a.turno into v_ult
      from public.agenda_alocacoes a
     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
       and a.resultado is null and a.presenca = 'turno'
       and not exists (select 1 from jsonb_array_elements(v_cut) x where (x ->> 'alocacao_id')::uuid = a.id)
     order by a.dia desc, a.turno = 'tarde' desc limit 1;
    if v_ult.dia is not null
       and not exists (select 1 from public.agenda_alocacoes a
                        where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.dia = v_ult.dia
                          and a.turno = v_ult.turno and a.presenca = 'fechamento') then
      v_itens := v_itens || jsonb_build_object(
        'op', 'criar', 'os', p_os, 'numero', v_numero, 'cliente_curto', v_pront ->> 'cliente_curto',
        'tipo', (select min(x ->> 'tipo') from jsonb_array_elements(v_cut) x), 'reserva_de', null,
        'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_dono,
                       'nome', (select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_dono),
                       'dia', v_ult.dia, 'turno', v_ult.turno, 'presenca', 'fechamento')),
        'de', v_ult.dia, 'ate', v_ult.dia, 'fim_antes', null, 'fim_depois', v_ult.dia, 'atraso_du', null, 'condicao_tipo', null,
        'critica', null, 'pergunta_chave', null, 'decisao', null, 'espera', false, 'interrupcoes', 0, 'meios_do_dono', 0,
        'fonte', v_m ->> 'fonte', 'dias', v_m -> 'dias', 'evento_real', false, 'fixar_dono', false, 'aviso_material', null,
        'abre', false, 'fecha', true, 'motivos', jsonb_build_array('o fechamento vai para o novo último meio-dia'),
        'texto', null, 'aplicado', false);
    end if;
  end if;
  -- "Tirei sex 13/11" (o dia inteiro) ou "Tirei qui 12/11 à tarde" (um turno só)
  v_partes := array(select case when count(*) > 1 then public._dia_curto((x ->> 'dia')::date)
                                else public._agenda_meio_texto((x ->> 'dia')::date, min(x ->> 'turno')) end
                      from jsonb_array_elements(v_meios) x group by x ->> 'dia' order by x ->> 'dia');
  v_txt := format('%s: o orçamento mudou e agora estimo %s (eram %s). Tirei %s.', public._agenda_rotulo_da_os(p_os),
                  public._agenda_dias(v_total::numeric / 2), public._agenda_num(v_feito / 2), public._agenda_lista(v_partes));
  -- FASE 7b: (7b P6, R4.3(f)) a sobra que vem da dupla completada depois de marcar (o dono disse os dias do ajudante e o passo dupla
  -- do gestor o pôs junto do técnico): com a duração que conserva as diárias-pessoa (o dk do molde), a dupla rende 2 e o serviço
  -- acaba antes. Quando a sobra não passa das pessoas a mais nos meios-dias da dupla do molde (as ni primeiras e as nf últimas de turno
  -- da OS, contando as cumpridas; o tempo todo = todas; o dono só conta com dk_dono_conta), o texto diz isso, não "o orçamento mudou":
  -- "Lenine (OS-00074): com Mateus junto em ter 10/11, o serviço acaba antes (são as mesmas diárias). Tirei ter 17/11." O corte é o mesmo.
  if v_m ? 'dk' then
    v_7b_ni := coalesce((v_m #>> '{dupla,ni}')::int, 0);
    v_7b_nf := coalesce((v_m #>> '{dupla,nf}')::int, 0);
    v_7b_todos := coalesce((v_m #>> '{dupla,todos}')::boolean, false);
    v_7b_conta := coalesce((v_m ->> 'dk_dono_conta')::boolean, true);
    -- quem vai no serviço (a pessoa com mais meios-dias de turno nele): o "junto" são os outros
    select a.payee_id into v_7b_prin
      from public.agenda_alocacoes a
     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
       and a.resultado is distinct from 'nao_cumprido'
     group by a.payee_id order by count(*) desc, min(a.dia), a.payee_id limit 1;
    with s as (
      select a.dia, a.turno,
             count(distinct a.payee_id) filter (where a.payee_id is distinct from v_dono or v_7b_conta)::int as tem,
             array_agg(distinct a.payee_id) filter (where a.payee_id is distinct from v_7b_prin
                                                     and (a.payee_id is distinct from v_dono or v_7b_conta)) as juntos
        from public.agenda_alocacoes a
       where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
         and a.resultado is distinct from 'nao_cumprido'
       group by a.dia, a.turno
    ), k as (
      select s.*, row_number() over (order by s.dia, s.turno) as pos, count(*) over () as n from s
    ), d as (
      select k.* from k where v_7b_todos or k.pos <= v_7b_ni or k.pos > k.n - v_7b_nf
    )
    select coalesce(sum(greatest(d.tem - 1, 0)), 0)::int,
           array(select distinct j from d d2 cross join lateral unnest(coalesce(d2.juntos, '{}'::uuid[])) j where d2.tem >= 2),
           array(select distinct d2.dia from d d2 where d2.tem >= 2 order by 1)
      into v_7b_extra, v_7b_quem, v_7b_dias
      from d;
    if v_7b_extra > 0 and v_sobra <= v_7b_extra and cardinality(v_7b_quem) > 0 then
      v_txt := format('%s: com %s junto em %s, o serviço acaba antes (são as mesmas diárias). Tirei %s.', public._agenda_rotulo_da_os(p_os),
                      public._agenda_lista(array(select case when q = v_dono then 'você' else public._agenda_nome_curto(py.name) end
                                                  from unnest(v_7b_quem) q join public.payees py on py.id = q order by py.name, q)),
                      regexp_replace(public._agenda_dias_texto(v_7b_dias), ' \([^()]*\)$', ''), public._agenda_lista(v_partes));
    end if;
  end if;
  -- FASE 7b: fim
  v_val := public._agenda_validar_itens(v_itens, jsonb_build_object('p_restricoes', '{}'::jsonb), p_hoje, p_agora, false,
                                        jsonb_build_object(p_os::text, v_pront));
  if jsonb_array_length(v_val) > 0 then
    return v_base || jsonb_build_object('sobra', v_n, 'ficou', v_n, 'motivo', 'validacao', 'violacoes', v_val);
  end if;
  return v_base || jsonb_build_object('sobra', v_n, 'cortar', v_k, 'cortados', v_meios, 'ficou', v_n - v_k,
    'itens', (select jsonb_agg(i || jsonb_build_object('texto', v_txt) order by k) from jsonb_array_elements(v_itens) with ordinality t(i, k)),
    'texto', public._agenda_corta(v_txt, 400), 'motivo', null);
end;
$function$;

comment on function public._agenda_gestor_corte(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7a, P9; spec §5.9 item 1 e §6.4): o corte do reestimar, a conta, sem gravar — com o plano (os meios-dias feitos + os de hoje em diante) maior que agenda_meios_da_os.total, os N últimos meios-dias de compromisso saem (N = a sobra inteira), do fim para trás, parando no 1º que não pode sair (o congelado, o que começou, o fixado, o dia já dito à equipe ou ao cliente: esses ficam com o dono); o fechamento do dono que sai volta no novo último meio-dia. Validado pelas 14 regras (_agenda_validar_itens). {os, numero, fonte, total, feitos, sobra, cortar, cortados [{dia, turno}], ficou, itens (cancelar motivo reestimada; criar do fechamento), texto ("Nelson (OS-00112): o orçamento mudou e agora estimo 3 dias (eram 4). Tirei sex 13/11."), motivo?}. STABLE, invoker, sem grant. CORREÇÃO DA 7a (revisão da etapa; achado 16): a sobra é contada em pessoa-meio-dia (_agenda_gestor_pessoa_meios: o que o plano tem — os meios-dias de turno de cada pessoa, os passados pelo resultado — contra o que a estimativa pede — meios-dias × as pessoas dela), não em meio-dia de calendário: *<nome> com dupla* num serviço marcado com 1 pessoa não corta mais metade dos dias (as diárias são as mesmas; a dupla vale para a próxima marcação); o meio-dia de calendário só sai se as pessoas dele cabem na sobra. FASE 7b (P6, R4.3(f)): quando a sobra vem da dupla completada depois de marcar (com o dk do molde, a sobra não passa das pessoas a mais nos meios-dias da dupla: as ni primeiras e as nf últimas de turno da OS, contando as cumpridas; o tempo todo = todas), o texto diz isso — "Lenine (OS-00074): com Mateus junto em ter 10/11, o serviço acaba antes (são as mesmas diárias). Tirei ter 17/11." —, não "o orçamento mudou"; o corte é o mesmo. Sem dk, a de antes, byte a byte.';

-- ── Portas das recriadas: as de antes (create or replace mantém os grants; repetidos aqui para a migration se explicar sozinha) ─────
revoke all on function public.agenda_gestor_rodar(date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_gestor_rodar(date, timestamptz) to service_role;
revoke all on function public._agenda_gestor_dia_gravar(date, text, jsonb, timestamptz), public._agenda_dias_semana_motivos(date, date),
  public._agenda_gestor_corte(uuid, date, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public._agenda_ver_gestor(date), public.agenda_livre_de_verdade(date, timestamptz) from public, anon;
grant execute on function public._agenda_ver_gestor(date), public.agenda_livre_de_verdade(date, timestamptz) to authenticated, service_role;

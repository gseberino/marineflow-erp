-- Agenda de Produção, Fase 7, etapa 7b ("os dias de verdade de quem trabalha e a dupla pela tarefa"), pacote P4: o motor — a dupla
-- por meio-dia (a inferida pela tarefa vai com 1 pessoa quando falta a 2ª e diz em que meios-dias chamar um ajudante; a dita pelo
-- dono espera a 2ª pessoa, também em teste; o "fora" dupla quando quem vem sob demanda não cobre), o novato e quem vem sob demanda
-- nunca sozinhos, o dono técnico com o teto dele, o sábado de manhã de quem se ofereceu, o gancho da pessoa a mais (inerte) e a
-- revisão do dia seguinte que não corta o bloco de 1 pessoa nem a dupla.
-- Spec: scratchpad agenda-pesquisa/spec-fase7b.md (§R2, §R4.3, §R4.4 "o gancho no P4", §R4.5, §R4.6, §R4.7 P4, §R4.8 M3a–M12, §3.1,
-- §3.3 d5–d11, §5.3, §6.3, §6.4, §8.3 agenda_fase7b_motor.sql); nomes: fase7-registro.md §1 e §2 (7b P4); respostas do dono:
-- fase7-padroes.md (AG7-02 o dono em campo pela metade, nunca numa vaga de técnico; AG7-03 quem vem sob demanda nunca sozinho; AG7-04
-- 1 pessoa, dupla só onde a tarefa pede; AG7-08 sábado só quando precisar).
-- Depende das Fases 1 a 6, do lote de 30/10, da 7a inteira (20261031100000 .. 100985 e o dado 100990) e do 7b P1 a P3
-- (20261101100000: modo_dupla, modo_sabado, modo_dias, dupla_espera_max_du, dupla_tec_viagem_min, novato_*, sob_demanda_sozinho,
-- dono_carga_max, dono_como_tecnico; 20261101100100 e 100200: a disponibilidade e a pergunta da semana).
--
-- ═══ DDL — OK NOMEADO ═══ (4 funções novas e 13 recriadas, as mesmas assinaturas; nenhuma tabela, coluna, lista ou dado)
-- NÃO APLICADA. Existe para revisão e espera o OK do dono. Este arquivo foi MONTADO por
-- scratchpad/agenda-pesquisa/f7b/p4/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (conferida a cada montagem:
-- o montador para se outra migration a definir depois da origem), e as mudanças estão só nos blocos "-- FASE 7b: … -- FASE 7b: fim"
-- (só acréscimo: nenhuma linha de antes muda; tirados os blocos, o corpo é o da origem, byte a byte).
--
-- POR QUE: com o Alex sozinho na equipe, a dupla inferida pela tarefa (o banco de baterias do Lenine, a ligação em 127/220 V, o
-- gerador, o orçamento com 2 técnicos) não pode segurar nem tirar a OS do plano: ela vai com 1 pessoa, na duração de 1 pessoa, e o
-- texto diz em que meios-dias chamar um ajudante. A dupla que o DONO disse (o tempo todo, no início ou no fim) espera a 2ª pessoa e
-- diz o que falta — em teste também (sem isso, a dita "no início" sairia do plano calada). Quem vem sob demanda (Mateus, Vinicius) e
-- o novato nunca ficam sozinhos num meio-dia. O dono em campo conta pela metade (dono_carga_max 0,50), nunca numa vaga de técnico
-- (salvo dono_como_tecnico). O sábado de manhã só de quem se ofereceu e só para cumprir prazo firme. A revisão das 16:53 não corta o
-- bloco de 1 pessoa nem a dupla (antes ela compararia meios-dias × pessoas com a estimativa de 10 e cortaria 2 meios-dias, dizendo
-- "o orçamento mudou").
--
-- O QUE MUDA:
--   1. Novas: _agenda_dupla_da_os (a dupla da OS: a dita pelo dono — fonte dono — ou a regra pelo NOME do serviço de cada linha, os
--      dupla_gatilhos, a bateria pesada também pelo material, e o orçamento com dupla_tec_viagem_min técnicos = o tempo todo — fonte
--      regra —; as dupla_notas viram só nota; o texto do cartão); _agenda_e_novato (perfil de diária vigente há menos de novato_dias e
--      menos de novato_diarias diárias; nunca o dono); _agenda_e_sob_demanda (na grade sem padrão vivo: entra só pelas datas que o
--      dono diz; nunca o dono); _agenda_pessoa_extra_id (o id fixo da pessoa a mais da simulação de quem chamar, do P6).
--   2. os_duracao_sugerida: com modo_dupla ligado e sem a regra uma_pessoa do 7a, 1 pessoa (a dupla vem por meio-dia).
--   3. agenda_meios_da_os: com modo_dupla fora de desligado, sem a equipe dita e com 1 pessoa, a dupla por meio-dia — dk (as pessoas
--      de cada passo que resta), dk_dono_conta (o dono que fica o turno inteiro é uma das pessoas, fora a regra da correção 2 da 7a) e
--      dupla {…, ni, nf, pm, pk}; ligado e com os dias estimados, a duração conserva as diárias-pessoa (o meio-dia em dupla rende 2:
--      Lenine 12 → 10 meios-dias).
--   4. _agenda_classe_da_os: a dupla DITA (inicio/fim, que a correção 2 não via) com menos técnicos do que ela pede espera o dono
--      (classe 4 dupla), fora de desligado.
--   5. _agenda_tecnicos_da_grade: fora de desligado, também quem vem sob demanda com algum meio-dia livre no horizonte (a 2ª pessoa).
--   6. _agenda_carga_da_pessoa: com modo_dias fora de desligado, o dono → least(o aprendido ou dono_carga_max, dono_carga_max).
--   7. _agenda_gestor_pessoa_meios: com dk, o que a estimativa pede é o das diárias-pessoa (ligado) ou fica entre o de 1 pessoa e o
--      da dupla acrescentada (em teste): a revisão do dia seguinte não corta nem falta.
--   8. _agenda_contexto: o sábado da 7b (sab, sab_bonus), quem nunca fica sozinho (novato), o dono técnico (dono_tec) e o gancho da
--      pessoa a mais (agenda.pessoa_extra = tecnico); o sábado do 7a (agenda.sabado) só com modo_sabado desligado.
--   9. _agenda_tentar_bloco: as pessoas de cada passo pelo dk; o sábado só de manhã, nunca o 1º passo e sem contar como dia parado;
--      quem nunca fica sozinho ganha um companheiro ou é lacuna; o dono técnico por último.
--  10. _agenda_encaixar: a dupla inferida que não tem a 2ª pessoa (ou espera demais, ou passa do prazo firme) vai com o bloco de 1
--      pessoa e dupla_falta; o sábado de manhã para cumprir o prazo firme (ligado: vale; em teste: sab_teste).
--  11. _agenda_validar_itens: a pessoa a mais (só com a variável) e, com modo_sabado ligado, a regra 6 com a manhã de sábado oferecida.
--  12. _agenda_melhor: o sábado conta depois do fim (sem sábado, a ordem de antes).
--  13. agenda_propor: a entrada da fila com dk, o prazo firme e os parâmetros do sábado e da dupla; o texto da dupla de 1 pessoa e do
--      sábado; a dupla dita que só passou por quem vem sob demanda e não achou bloco vai ao "fora" com o motivo dupla e as datas; as
--      linhas "Em teste" do sábado e da dupla.
--  14. _agenda_gestor_sabado (7a): com modo_sabado ligado, {pulado: modo_sabado} (o motor usa o sábado sozinho, com o aviso no texto).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7b_motor.sql; registradas em notas-fase77b.md, P4):
--   · A dupla por meio-dia só existe com 1 pessoa por serviço (a regra uma_pessoa, ou modo_dupla ligado): com 2 ou mais, o meio-dia
--     de dupla já tem a 2ª pessoa e nada muda.
--   · dupla.pm = a soma das pessoas do molde (com os dias estimados e ligado, as diárias-pessoa da estimativa): a revisão compara com
--     ela e não fica pedindo meio meio-dia que o arredondamento do "o tempo todo" tirou.
--   · O dk desconta o dono (com dk_dono_conta) também na reserva, como o desejado de antes (a reserva guarda só os diaristas).
--   · O novato e quem vem sob demanda nunca sozinhos valem com modo_dupla fora de desligado (a segurança, como a dupla); o dono técnico,
--     com dono_como_tecnico e modo_dias fora de desligado.
--   · No sábado, o teto da equipe (7a) também ganha a manhã oferecida (senão o teto da equipe barraria o meio-dia que o teto da pessoa
--     deixa).
--   · O dono técnico vai no bloco como o dono no turno (fora da soma da equipe, contando nos turnos dele), nunca no 1º passo que ele
--     abre, no último que ele fecha nem no serviço "sem você"; o validador aceita o dono no turno do serviço em que ele só abre e fecha
--     quando dono_como_tecnico vale (a regra 4 recusava).
--   · Com os dias ditos pelo dono, sem a conservação: o bloco de 1 pessoa da dupla inferida tem os passos de antes.
--   · O texto da dupla de 1 pessoa vai inteiro com o item em até 320 letras; senão a forma curta (o texto da ação junta os itens da
--     mesma OS e vai até 400).
--   · O pátio (a reserva 2c) vai sem dk; o gancho do sábado do 7a é desligado guardando a grade antes dele e devolvendo-a depois.
--   · _agenda_dupla_da_os, _agenda_e_novato, _agenda_e_sob_demanda e _agenda_pessoa_extra_id têm authenticated e service_role: o
--     molde, a classe e os técnicos da grade são lidos pelo painel (invoker).
--
-- ORDEM DE LIGAR: nada muda com os 5 modos da 7b desligados (como a migration nasce). O dado 20261101100900 (P5, OK nomeado) põe os
-- modos em sombra: a dupla em teste só ACRESCENTA a 2ª pessoa onde a tarefa pede e ela está livre (d8), e a revisão não a corta; o
-- dono em campo conta pela metade (R4.5). O ligar é UPDATE do mesmo dia (AG7-01): "OK ligar a dupla" (modo_dupla, junto do
-- modo_chamar do P6) e "OK ligar o sábado" (modo_sabado).
--
-- PROVA: supabase/tests/agenda_fase7b_motor.sql (na bancada: node scripts/bancada-agenda/rodar.mjs).
-- APLICAR (só com o OK do dono, depois das do 7b P1 a P3): npx supabase@2.111.0 db push (ou o roteiro de publicar da etapa).
--
-- DESFAZER: os modos da 7b em desligado (modo_dupla, modo_sabado, modo_dias): com eles desligados, a saída de cada recriada é a de
-- antes. Para tirar o código: recriar cada função com o corpo da origem (o comentário de cada uma diz qual), a cópia sem os blocos
-- "-- FASE 7b:".
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. As funções novas ────────────────────────────────────────────────────────────────────────────────────────

-- O id fixo da pessoa a mais da simulação de quem chamar (R4.4: o P6 liga agenda.pessoa_extra = tecnico só dentro da conta, sem
-- gravar nada). Nenhuma tabela tem esse id: nenhum payee, nenhuma alocação.
create or replace function public._agenda_pessoa_extra_id()
 returns uuid
 language sql
 immutable
 set search_path to 'public'
as $function$
  select 'a6e0da00-7b00-4000-8000-0000000000e1'::uuid;
$function$;

comment on function public._agenda_pessoa_extra_id() is
  'Agenda de Produção (Fase 7b, P4; R4.4): o id fixo da "mais uma pessoa" da simulação de quem chamar — com agenda.pessoa_extra = tecnico (só _agenda_quem_chamar, do P6, a liga, sem gravar), _agenda_contexto a acrescenta livre em todo dia útil e _agenda_validar_itens a aceita. Nenhuma tabela tem esse id. IMMUTABLE.';

-- O novato (spec §5.3; AG7-04, AG7-10): perfil de diária vigente no dia, a 1ª vigência da pessoa há menos de novato_dias e menos de
-- novato_diarias diárias até o dia. O dono nunca. É a regra única do novato (o 7c usa esta, com a etiqueta).
create or replace function public._agenda_e_novato(p_payee uuid, p_dia date)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(p_payee is not null and p_dia is not null
     and p_payee is distinct from public._agenda_dono(null)
     and exists (select 1 from public.work_profiles w
                  where w.payee_id = p_payee and w.vigencia_inicio <= p_dia and (w.vigencia_fim is null or w.vigencia_fim >= p_dia))
     and (select min(w.vigencia_inicio) from public.work_profiles w where w.payee_id = p_payee)
         > p_dia - (public._agenda_cfg()).novato_dias
     and coalesce((select sum(ws.fracao) from public.work_shifts ws join public.work_profiles w on w.id = ws.work_profile_id
                    where w.payee_id = p_payee and ws.data <= p_dia and ws.tipo = 'diaria' and ws.fracao is not null), 0)
         < (public._agenda_cfg()).novato_diarias, false);
$function$;

comment on function public._agenda_e_novato(uuid, date) is
  'Agenda de Produção (Fase 7b, P4; spec §5.3, AG7-04/AG7-10): true para quem tem perfil de diária vigente em p_dia, a 1ª vigência há menos de novato_dias e menos de novato_diarias diárias (a soma das frações lançadas até p_dia). O dono nunca. O motor (_agenda_contexto, com modo_dupla fora de desligado) nunca o deixa sozinho num meio-dia. É a regra única do novato (o 7c a usa). STABLE, invoker.';

-- Quem vem sob demanda (R4.3(d); AG7-03): na grade (a régua da equipe de 30/10: prestador, diarista ou funcionário ativo, com perfil
-- de diária vigente ou declarado pelo dono, e alguma linha de disponibilidade viva) sem padrão vivo que vem (disponível ou
-- confirmada): os dias dele são só as datas que o dono diz. O dono nunca.
create or replace function public._agenda_e_sob_demanda(p_payee uuid, p_dia date)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(p_payee is not null and p_dia is not null
     and p_payee is distinct from public._agenda_dono(null)
     and exists (select 1 from public.payees py
                  where py.id = p_payee and py.active and py.kind in ('prestador', 'diarista', 'funcionario'))
     and (exists (select 1 from public.work_profiles w
                   where w.payee_id = p_payee and w.vigencia_inicio <= p_dia and (w.vigencia_fim is null or w.vigencia_fim >= p_dia))
          or exists (select 1 from public.agenda_disponibilidade d
                      where d.payee_id = p_payee and d.substituida_em is null and d.origem = 'dono'))
     and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = p_payee and d.substituida_em is null)
     and not exists (select 1 from public.agenda_disponibilidade d
                      where d.payee_id = p_payee and d.substituida_em is null and d.dias_semana is not null
                        and cardinality(d.dias_semana) > 0 and d.situacao in ('disponivel', 'confirmada')), false);
$function$;

comment on function public._agenda_e_sob_demanda(uuid, date) is
  'Agenda de Produção (Fase 7b, P4; R4.3(d), AG7-03): true para quem está na grade (a régua de agenda_capacidade de 30/10: prestador, diarista ou funcionário ativo, com perfil de diária vigente em p_dia ou linha viva de origem dono, e alguma linha de disponibilidade viva) sem padrão vivo que vem (dias_semana disponível ou confirmada): os dias dele são só as datas ditas pelo dono (Mateus, Vinicius). O dono nunca. Com sob_demanda_sozinho = false, o motor (_agenda_contexto) nunca o deixa sozinho num meio-dia nem no bloco de 1 pessoa; _agenda_tecnicos_da_grade o conta como a 2ª pessoa quando tem meio-dia livre no horizonte. STABLE, invoker.';

-- A dupla da OS (spec §5.3; AG7-04, §3.3 d5/d6): 1) a dita pelo dono (os_planejamento.dupla_dita: nao, todos, inicio/fim com
-- dupla_meios) — fonte dono; 2) senão, a regra: o NOME do serviço de cada linha (_agenda_nome_do_servico: o trecho antes de " — ", ":"
-- ou "("; o Starlink "… alimentado pelo banco de baterias" da ORÇ-00119 fica de fora) casando os dupla_gatilhos, e a descrição do
-- material só para a bateria pesada; início = o maior meios-dias dos gatilhos de início, fim = o dos de fim; o orçamento com
-- dupla_tec_viagem_min técnicos ou mais = o tempo todo — fonte regra; 3) as dupla_notas casadas viram notas (só aviso; não mudam
-- nada). O texto é o do cartão (§6.4), sem o modo (quem mostra diz "em teste").
create or replace function public._agenda_dupla_da_os(p_os uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  c_rot    constant jsonb := jsonb_build_object('banco_cc', 'troca do banco de baterias', 'bateria_pesada', 'bateria pesada',
                                                'ca_energizado', 'ligação em 127/220 V', 'icamento', 'peça pesada: gerador ou motor');
  c_fra    constant jsonb := jsonb_build_object('banco_cc', 'a troca do banco de baterias', 'bateria_pesada', 'a bateria pesada',
                                                'ca_energizado', 'a ligação em 127/220 V', 'icamento', 'a peça pesada (gerador ou motor)');
  v_dita   text;
  v_meios  int;
  v_tec    int;
  v_ini    int := 0;
  v_fim    int := 0;
  v_todos  boolean := false;
  v_mot    jsonb := '[]'::jsonb;
  v_notas  jsonb := '[]'::jsonb;
  v_fonte  text;
  v_txt    text;
  v_ri     text;
  v_rf     text;
  v_pi     text;
  v_pf     text;
  v_ws     text[];
  v_m      int;
  v_trecho text;
  r        record;
begin
  if p_os is null then
    raise exception '_agenda_dupla_da_os: sem a OS' using errcode = '22004';
  end if;
  select pl.dupla_dita, pl.dupla_meios into v_dita, v_meios from public.os_planejamento pl where pl.service_order_id = p_os;
  select so.technician_count_for_travel into v_tec from public.service_orders so where so.id = p_os;

  -- as notas (o espaço apertado: só aviso, em qualquer fonte), com o trecho como está escrito na linha
  for r in
    select g.e ->> 0 as motivo, s.id as linha, s.name_snapshot as nome,
           substring(s.nome_servico from '\m(' || (g.e ->> 1) || ')') as trecho
      from jsonb_array_elements(c.dupla_notas) with ordinality g(e, o)
      cross join lateral (
        select s0.id, s0.name_snapshot, s0.nome_servico
          from (select x.id, x.name_snapshot, x.line_total, x.created_at, public._agenda_nome_do_servico(x.name_snapshot) as nome_servico
                  from public.service_order_services x where x.service_order_id = p_os offset 0) s0
         where s0.nome_servico ~ ('\m(' || (g.e ->> 1) || ')')
         order by s0.line_total desc nulls last, s0.created_at, s0.id
         limit 1) s
     order by g.o
  loop
    v_trecho := r.trecho;
    v_ws := regexp_split_to_array(btrim(coalesce(r.nome, '')), '\s+');
    v_m := cardinality(regexp_split_to_array(btrim(r.trecho), '\s+'));
    for i in 1 .. greatest(coalesce(cardinality(v_ws), 0) - v_m + 1, 0) loop
      if public._agenda_normal(array_to_string(v_ws[i:i + v_m - 1], ' ')) = r.trecho then
        v_trecho := regexp_replace(lower(array_to_string(v_ws[i:i + v_m - 1], ' ')), '[[:punct:]]+$', '');
        exit;
      end if;
    end loop;
    v_notas := v_notas || jsonb_build_object('motivo', r.motivo, 'linha', r.linha, 'nome', r.nome, 'trecho', r.trecho,
                                             'texto', format('Atenção: %s — confira se precisa de duas pessoas.', v_trecho));
  end loop;

  if v_dita is not null then
    v_fonte := 'dono';
    v_todos := v_dita = 'todos';
    v_ini := case when v_dita = 'inicio' then coalesce(v_meios, 0) else 0 end;
    v_fim := case when v_dita = 'fim' then coalesce(v_meios, 0) else 0 end;
  else
    -- a regra: a 1ª linha que casa cada gatilho (o nome do serviço pela ordem do valor; a bateria pesada também no material)
    for r in
      select g.e ->> 0 as motivo, g.e ->> 2 as onde, (g.e ->> 3)::int as meios, x.linha, x.nome
        from jsonb_array_elements(c.dupla_gatilhos) with ordinality g(e, o)
        cross join lateral (
          select y.linha, y.nome
            from (select 1 as k, s0.id as linha, s0.name_snapshot as nome, s0.line_total as v, s0.created_at as em
                    from (select x0.id, x0.name_snapshot, x0.line_total, x0.created_at,
                                 public._agenda_nome_do_servico(x0.name_snapshot) as nome_servico
                            from public.service_order_services x0 where x0.service_order_id = p_os offset 0) s0
                   where s0.nome_servico ~ ('\m(' || (g.e ->> 1) || ')')
                  union all
                  select 2, m.id, m.descricao, null::numeric, null::timestamptz
                    from public.os_material m
                   where g.e ->> 0 = 'bateria_pesada' and m.service_order_id = p_os and m.situacao <> 'dispensado'
                     and public._agenda_normal(m.descricao) ~ ('\m(' || (g.e ->> 1) || ')')) y
           order by y.k, y.v desc nulls last, y.em, y.nome, y.linha
           limit 1) x
       order by g.o
    loop
      v_mot := v_mot || jsonb_build_object('motivo', r.motivo, 'onde', r.onde, 'meios', r.meios, 'linha', r.linha, 'nome', r.nome,
                                           'rotulo', c_rot ->> r.motivo, 'frase', c_fra ->> r.motivo);
      if r.onde = 'inicio' then v_ini := greatest(v_ini, r.meios); else v_fim := greatest(v_fim, r.meios); end if;
    end loop;
    if coalesce(v_tec, 0) >= c.dupla_tec_viagem_min then
      v_todos := true;
      v_mot := v_mot || jsonb_build_object('motivo', 'orcamento', 'onde', 'todos', 'meios', null, 'linha', null, 'nome', null,
                                           'rotulo', format('o orçamento previu %s técnicos', v_tec),
                                           'frase', format('o orçamento previu %s técnicos', v_tec));
    end if;
    v_fonte := case when v_todos or v_ini > 0 or v_fim > 0 then 'regra' else 'nenhuma' end;
  end if;

  -- o texto do cartão (§6.4): "1 pessoa; em dupla nos 2 primeiros meios-dias (troca do banco de baterias) — suposição minha."
  v_pi := case when v_ini = 1 then 'no primeiro meio-dia' else format('nos %s primeiros meios-dias', v_ini) end;
  v_pf := case when v_fim = 1 then 'no último meio-dia' else format('nos %s últimos meios-dias', v_fim) end;
  v_ri := public._agenda_lista(array(select distinct on (e ->> 'motivo') e ->> 'rotulo' from jsonb_array_elements(v_mot) e
                                      where e ->> 'onde' = 'inicio' order by e ->> 'motivo'));
  v_rf := public._agenda_lista(array(select distinct on (e ->> 'motivo') e ->> 'rotulo' from jsonb_array_elements(v_mot) e
                                      where e ->> 'onde' = 'fim' order by e ->> 'motivo'));
  v_txt := case
    when v_fonte = 'nenhuma' then '1 pessoa.'
    when v_fonte = 'dono' and v_todos then 'Em dupla o tempo todo (você disse).'
    when v_fonte = 'dono' and v_ini > 0 then format('Em dupla %s (você disse).', v_pi)
    when v_fonte = 'dono' and v_fim > 0 then format('Em dupla %s (você disse).', v_pf)
    when v_fonte = 'dono' then '1 pessoa (você disse).'
    when v_todos then format('Em dupla o tempo todo (%s) — suposição minha.',
                             (select e ->> 'rotulo' from jsonb_array_elements(v_mot) e where e ->> 'motivo' = 'orcamento'))
    when v_ini > 0 and v_fim > 0 then format('1 pessoa; em dupla %s (%s) e %s (%s) — suposição minha.', v_pi, v_ri,
                                             case when v_fim = 1 then 'no último' else format('nos %s últimos', v_fim) end, v_rf)
    when v_ini > 0 then format('1 pessoa; em dupla %s (%s) — suposição minha.', v_pi, v_ri)
    else format('1 pessoa; em dupla %s (%s) — suposição minha.', v_pf, v_rf) end;

  return jsonb_build_object('inicio', v_ini, 'fim', v_fim, 'todos', v_todos, 'motivos', v_mot, 'notas', v_notas, 'fonte', v_fonte,
                            'texto', v_txt);
end;
$function$;

comment on function public._agenda_dupla_da_os(uuid) is
  'Agenda de Produção (Fase 7b, P4; spec §5.3 e §6.4, AG7-04): a dupla da OS — 1) a dita pelo dono (os_planejamento.dupla_dita: nao, todos, inicio/fim com dupla_meios), fonte dono; 2) senão a regra: o nome do serviço de cada linha (_agenda_nome_do_servico) casando os dupla_gatilhos com ~ (''\m('' || expressão || '')''), a bateria pesada também na descrição do material; inicio = o maior meios-dias dos gatilhos de início, fim = o dos de fim; motivos [{motivo, onde, meios, linha, nome, rotulo, frase}] (a 1ª linha que casou cada gatilho, pela ordem do valor); technician_count_for_travel >= dupla_tec_viagem_min = o tempo todo (motivo orcamento), fonte regra; nada = fonte nenhuma; 3) as dupla_notas casadas viram notas [{motivo, linha, nome, trecho, texto: "Atenção: casa de máquinas — confira se precisa de duas pessoas."}] (só aviso). {inicio, fim, todos, motivos, notas, fonte, texto} — o texto do cartão: "1 pessoa; em dupla nos 2 primeiros meios-dias (troca do banco de baterias) — suposição minha.", "Em dupla o tempo todo (o orçamento previu 2 técnicos) — suposição minha.", "Em dupla nos 2 primeiros meios-dias (você disse).", "1 pessoa.". STABLE, invoker; authenticated e service_role (agenda_meios_da_os, que o painel lê, a chama).';

-- ── 2. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 7b:") ─────────────────────────
-- Fora dos blocos nenhuma linha muda (o M8 de supabase/tests/agenda_fase7b_motor.sql confere). Quem recriar de novo qualquer uma
-- delas copia DESTA migration (spec-fase7b §R4.6: o 7c P2 copia o motor daqui, com o gancho da pessoa a mais e o dk_dono_conta; o 7g
-- P5 copia _agenda_classe_da_os daqui; o 7e P3 copia os_duracao_sugerida e agenda_meios_da_os daqui).

-- os_duracao_sugerida (de 20261031100980_agenda_fase77a_correcao.sql)
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
  -- FASE 7: (7a P2) as regras do gestor da agenda na duração — o que saiu da mão de obra, a dupla dita, o aviso de dupla e o
  -- que a saída ganha (só com o portão; sem ele, nada disto é usado e a saída é a de antes)
  v_f7_fora   jsonb;
  v_f7_tot    numeric;
  v_f7_mat    numeric;
  v_f7_h      numeric;
  v_f7_dupla  text;
  v_f7_alerta jsonb;
  v_f7_pes    int;
  v_f7_extra  jsonb := '{}'::jsonb;
  -- FASE 7: fim
  -- FASE 7: (7a correção, memória da rodada; achado 10)
  v_f77_chave text;
  v_f77_memo  jsonb;
  v_f77_marca bigint;
  -- FASE 7: fim
begin
  if not exists (select 1 from public.service_orders where id = p_so_id) then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;
  -- FASE 7: (7a correção, memória da rodada; achado 10) dentro da rodada da vigia (agenda.rodada, posto por agenda_vigiar) e com
  -- alguma regra do gestor na duração, cada OS é calculada UMA vez e lembrada enquanto a transação não gravar nada no que ela lê
  -- (_agenda_rodada_marca, a mesma da prontidão) e o portão (agenda.gestor) for o mesmo. Com o gestor ligado, a mesma OS era
  -- calculada ~20 vezes por rodada (a prontidão, a estimativa, a situação, os meios, a classe). A conta é a de sempre (a chamada
  -- de dentro, com a memória em pausa); fora da rodada ou sem as regras, nada muda.
  if p_so_id is not null and coalesce(current_setting('agenda.rodada', true), '') <> ''
     and coalesce(current_setting('agenda.rodada_dur_em', true), '') = ''
     and (public._agenda_gestor_regra('uma_pessoa') or public._agenda_gestor_regra('mo_limpa')
          or public._agenda_gestor_regra('diagnostico')) then
    v_f77_chave := p_so_id::text || ':' || coalesce(current_setting('agenda.gestor', true), '');
    v_f77_memo := public._agenda_rodada_duracao_lembrar(v_f77_chave);
    if v_f77_memo is null then
      v_f77_marca := public._agenda_rodada_marca();
      perform set_config('agenda.rodada_dur_em', 'on', true);
      v_f77_memo := public.os_duracao_sugerida(p_so_id);
      perform set_config('agenda.rodada_dur_em', '', true);
      perform public._agenda_rodada_duracao_guardar(v_f77_chave, v_f77_marca, v_f77_memo);
    end if;
    return v_f77_memo;
  end if;
  -- FASE 7: fim

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
  -- FASE 7: (7a P2, regra mo_limpa) deslocamento, viagem, translado, visita técnica, km rodado e frete não são dias de
  -- serviço: a linha cujo nome do serviço (_agenda_nome_do_servico: o trecho antes do travessão, dos dois pontos ou do
  -- parêntese) casa mo_fora_regex sai do total, das horas e — se ela era material de texto livre — do material, para a mão de
  -- obra ficar a mesma conta sem ela. A saída ganha fora_da_mo [{linha, nome, valor, horas}] só quando tirou alguma coisa.
  if public._agenda_gestor_regra('mo_limpa') then
    select coalesce(jsonb_agg(jsonb_build_object('linha', s.id, 'nome', s.name_snapshot, 'valor', coalesce(s.line_total, 0),
                                                 'horas', case when s.billing_unit_snapshot = 'hour'
                                                               then trim_scale(coalesce(s.quantity, 0)) else 0 end)
                              order by s.line_total desc nulls last, s.created_at, s.id), '[]'::jsonb),
           coalesce(sum(s.line_total), 0),
           coalesce(sum(s.line_total) filter (
             where s.service_id is null and s.billing_unit_snapshot = 'unit' and coalesce(s.quantity, 0) > 0
               and public.free_text_is_material(s.name_snapshot)), 0),
           coalesce(sum(s.quantity) filter (where s.billing_unit_snapshot = 'hour'), 0)
      into v_f7_fora, v_f7_tot, v_f7_mat, v_f7_h
      from public.service_order_services s
     where s.service_order_id = p_so_id
       and public._agenda_nome_do_servico(s.name_snapshot) ~ c.mo_fora_regex;
    if jsonb_array_length(v_f7_fora) > 0 then
      v_total := v_total - v_f7_tot;
      v_mat := v_mat - v_f7_mat;
      v_horas := v_horas - v_f7_h;
      v_f7_extra := v_f7_extra || jsonb_build_object('fora_da_mo', v_f7_fora);
    end if;
  end if;
  -- FASE 7: fim
  v_mo := greatest(v_total - v_mat, 0);
  -- FASE 7: (7a P2, regra diagnostico) a OS de diagnóstico (service_type ou a linha de maior valor casa "diagnost": a mesma
  -- régua de os_presenca_do_dono) leva diagnostico_dias com 1 pessoa (2 só se o dono marcou a dupla), seja qual for o valor —
  -- depois o gestor reavalia. Vale também sem mão de obra separada: o diagnóstico tem o tempo dele.
  if public._agenda_gestor_regra('diagnostico')
     and (exists (select 1 from public.service_orders so where so.id = p_so_id and so.service_type = 'diagnosis')
          or coalesce((select public._agenda_normal(s.name_snapshot) from public.service_order_services s
                        where s.service_order_id = p_so_id
                        order by s.line_total desc nulls last, s.created_at, s.id limit 1), '') ~ 'diagnost') then
    select pl.dupla_dita into v_f7_dupla from public.os_planejamento pl where pl.service_order_id = p_so_id;
    v_f7_pes := case when v_f7_dupla = 'todos' and public._agenda_gestor_regra('uma_pessoa')
                     then greatest(c.equipe_sugerida, 2) else 1 end;
    return jsonb_build_object(
      'ok', true, 'sem_base', false, 'mo', v_mo, 'horas', trim_scale(v_horas),
      'dp_otimista', round(c.diagnostico_dias * v_f7_pes, 2), 'dp_realista', round(c.diagnostico_dias * v_f7_pes, 2),
      'pessoas', v_f7_pes, 'dias_otimista', trim_scale(c.diagnostico_dias), 'dias_realista', trim_scale(c.diagnostico_dias),
      'sugerida', trim_scale(c.diagnostico_dias),
      'diarias_otimista', trim_scale(c.diagnostico_dias * v_f7_pes), 'diarias_realista', trim_scale(c.diagnostico_dias * v_f7_pes),
      'texto', public._agenda_dias(c.diagnostico_dias) || ' de diagnóstico'
               || case when v_f7_pes = 1 then '' else format(' com %s pessoas', v_f7_pes) end
               || '; depois eu reavalio',
      'diagnostico', true,
      'pessoas_motivo', case when v_f7_pes = 1 then 'regra' else 'dupla_marcada' end) || v_f7_extra;
  end if;
  -- (mo_limpa) o que sobrou sem mão de obra nem horas depois de tirar o deslocamento é "sem base", dizendo o que saiu.
  if v_f7_extra ? 'fora_da_mo' and v_mo <= 0 and v_horas <= 0 then
    return jsonb_build_object('ok', true, 'sem_base', true, 'mo', v_mo, 'horas', v_horas,
                              'texto', 'sem base para estimar: quantos dias?') || v_f7_extra;
  end if;
  -- FASE 7: fim

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
  -- FASE 7b: (7b P4, §5.3, §R2) com a dupla por meio-dia ligada (modo_dupla) e sem a regra uma_pessoa do 7a, 1 pessoa por serviço:
  -- a dupla vem por meio-dia em agenda_meios_da_os (dk), só onde a tarefa pede. Com a regra uma_pessoa, vale o v_pes dela (logo
  -- abaixo). Fora de ligado, o de antes.
  if c.modo_dupla = 'ligado' and not public._agenda_gestor_regra('uma_pessoa') then
    v_pes := 1;
  end if;
  -- FASE 7b: fim
  -- FASE 7: (7a P2, regra uma_pessoa, AG7-04) 1 pessoa por serviço (equipe_padrao); a dupla (equipe_sugerida, nunca menos
  -- de 2) só quando o dono marcou *<nome> com dupla* (os_planejamento.dupla_dita = 'todos'; inicio/fim são do 7b, por
  -- meio-dia). O serviço de até 1 diária continua com 1 pessoa. Sem nada dito, o 1º gatilho de dupla_gatilhos (ou a 1ª nota de
  -- dupla_notas) que casar no nome do serviço de alguma linha vira o aviso alerta_dupla {motivo, nota, onde, linha, nome,
  -- trecho} — só aviso ao dono, nunca 2 pessoas sozinho (a dupla automática é o modo_dupla do 7b).
  if public._agenda_gestor_regra('uma_pessoa') then
    select pl.dupla_dita into v_f7_dupla from public.os_planejamento pl where pl.service_order_id = p_so_id;
    v_pes := case when v_f7_dupla = 'todos' then greatest(c.equipe_sugerida, 2)
                  when v_dp_re <= 1 then 1
                  else c.equipe_padrao end;
    v_f7_extra := v_f7_extra || jsonb_build_object('pessoas_motivo',
                                                   case when v_f7_dupla = 'todos' then 'dupla_marcada' else 'regra' end);
    if v_f7_dupla is null then
      select jsonb_build_object('motivo', g.e ->> 0, 'nota', g.nota, 'onde', case when not g.nota then g.e ->> 2 end,
                                'linha', s.id, 'nome', s.name_snapshot,
                                'trecho', substring(s.nome_servico from '\m(' || (g.e ->> 1) || ')'))
        into v_f7_alerta
        from (select t.e, t.o, false as nota from jsonb_array_elements(c.dupla_gatilhos) with ordinality t(e, o)
              union all
              select t.e, t.o, true from jsonb_array_elements(c.dupla_notas) with ordinality t(e, o)) g
        -- (7a correção, achado 10) o nome do serviço de cada linha calculado uma vez (antes, uma vez por gatilho)
        join (select s0.id, s0.name_snapshot, s0.line_total, s0.created_at,
                     public._agenda_nome_do_servico(s0.name_snapshot) as nome_servico
                from public.service_order_services s0 where s0.service_order_id = p_so_id offset 0) s
          on s.nome_servico ~ ('\m(' || (g.e ->> 1) || ')')
       order by g.nota, g.o, s.line_total desc nulls last, s.created_at, s.id
       limit 1;
      if v_f7_alerta is not null then
        v_f7_extra := v_f7_extra || jsonb_build_object('alerta_dupla', v_f7_alerta);
      end if;
    end if;
  end if;
  -- FASE 7: fim
  -- Dias de calendário arredondados ao meio dia; nunca menos de meio dia.
  v_d_ot := trim_scale(greatest(0.5, round(v_dp_ot / v_pes * 2) / 2));
  v_d_re := trim_scale(greatest(v_d_ot, round(v_dp_re / v_pes * 2) / 2));
  v_sug  := trim_scale(round(v_d_ot + v_d_re) / 2);
  -- FASE 7: (7a P2) com uma regra que mudou a saída (fora_da_mo, pessoas_motivo, alerta_dupla), a mesma saída de baixo (com o
  -- R$ por diária aprendido, quando em uso) mais as chaves novas; sem nada, as duas saídas de antes, byte a byte.
  if v_f7_extra <> '{}'::jsonb then
    return jsonb_build_object(
      'ok', true, 'sem_base', false, 'mo', v_mo, 'horas', trim_scale(v_horas),
      'dp_otimista', round(v_dp_ot, 2), 'dp_realista', round(v_dp_re, 2),
      'pessoas', v_pes, 'dias_otimista', v_d_ot, 'dias_realista', v_d_re, 'sugerida', v_sug,
      'diarias_otimista', trim_scale(v_d_ot * v_pes), 'diarias_realista', trim_scale(v_d_re * v_pes),
      'texto', public._agenda_faixa_dias(v_d_ot, v_d_re)
               || case when v_pes = 1 then ', 1 pessoa' else format(' com %s pessoas', v_pes) end
               || ' (estimativa minha, pelo valor)')
      || case when v_mo_fonte = 'aprendido' then jsonb_build_object('mo_fonte', 'aprendido', 'mo_por_diaria', v_mo_dia)
              else '{}'::jsonb end
      || v_f7_extra;
  end if;
  -- FASE 7: fim

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
  'Agenda de Produção (Fase 1, P3): a duração "pelo valor" (plano §4.2 com a correção do material). mo = linhas de serviço − material de texto livre que entra na compra; horas = linhas por hora; diárias-pessoa otimista = max(horas ÷ jornada_horas, mo ÷ mo_por_diaria_preco), realista = max(horas ÷ jornada_horas, mo ÷ mo_por_diaria_real); 1 pessoa se o realista ≤ 1, senão equipe_sugerida; dias arredondados ao meio dia; sugerida = o meio dia mais perto da média. Sem mão de obra nem horas: {sem_base:true, texto:"sem base para estimar: quantos dias?"}. Nunca é gravada. FASE 6 (P2): o realista usa _agenda_mo_por_diaria_real() (o R$ por diária aprendido em uso, senão mo_por_diaria_real); com o aprendido em uso a saída ganha mo_fonte = aprendido e mo_por_diaria (sem ele, a saída de antes). FASE 7 (7a P2), atrás do portão _agenda_gestor_regra (falso = a saída de antes, byte a byte): mo_limpa — a linha cujo nome do serviço (_agenda_nome_do_servico) casa mo_fora_regex sai da mão de obra e das horas (fora_da_mo); uma_pessoa (AG7-04) — pessoas = equipe_padrao (até 1 diária = 1), greatest(equipe_sugerida, 2) só com dupla_dita = todos (pessoas_motivo) e, sem nada dito, alerta_dupla pelo 1º gatilho de dupla_gatilhos/dupla_notas no nome do serviço; diagnostico — a OS de diagnóstico leva diagnostico_dias com 1 pessoa (diagnostico: true, "meio dia de diagnóstico; depois eu reavalio"). CORREÇÃO DA 7a (revisão da etapa; achado 10): dentro da rodada da vigia (agenda.rodada) e com alguma regra do gestor na duração (mo_limpa, uma_pessoa, diagnostico), a duração de cada OS é calculada uma vez e lembrada (_agenda_rodada_duracao_lembrar/_guardar, chave <OS>:<agenda.gestor>, a marca de _agenda_rodada_marca) enquanto a transação não grava nada no que ela lê; e o nome do serviço de cada linha é calculado uma vez por linha (antes, uma vez por gatilho de dupla). O resultado é o mesmo, byte a byte. FASE 7b (P4, §5.3): com modo_dupla ligado e a regra uma_pessoa falsa, pessoas = 1 (a dupla vem por meio-dia em agenda_meios_da_os, só onde a tarefa pede); com a regra, a do 7a; fora de ligado, a saída de antes, byte a byte.';

-- agenda_meios_da_os (de 20261031100985_agenda_fase77a_correcao2.sql)
create or replace function public.agenda_meios_da_os(p_so_id uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  p          public.os_planejamento%rowtype;
  v_dono     uuid := public._agenda_dono(null);
  v_status   text;
  v_pres     jsonb;
  v_sug      jsonb;
  v_fonte    text;
  v_dias     numeric;
  v_total    int;
  v_plano    jsonb;
  v_cump     numeric := 0;
  v_vig      int := 0;
  v_rest     numeric;
  v_dita     boolean;
  v_dono_t   text;
  v_presenca text;
  v_motivo   text;
  v_dt_m     boolean;
  v_dt_t     boolean;
  v_pm       jsonb;
  v_pt       jsonb;
  v_dm       int;
  v_dtd      int;
  v_pessoas  int;
  v_abre     boolean;
  v_fecha    boolean;
  v_molde    jsonb := '[]'::jsonb;
  v_papel    text[];
  v_t        text;
  k          int;
  -- FASE 7: (7a P2) a estimativa do gestor e o que a saída ganha com a regra estimativa
  v_est      jsonb;
  v_f7       jsonb;
  -- FASE 7: fim
  -- FASE 7b: (7b P4) a dupla por meio-dia: a da OS, os meios-dias dela no início e no fim, as pessoas de cada passo do molde
  v_7b_modo  text;
  v_7b_dup   jsonb;
  v_7b_ni    int := 0;
  v_7b_nf    int := 0;
  v_7b_pme   int;
  v_7b_pk    int[] := '{}';
  v_7b_conta boolean;
  v_7b_todos boolean;
  v_7b_n     int;
  -- FASE 7b: fim
begin
  select so.status into v_status from public.service_orders so where so.id = p_so_id;
  if not found then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;
  select * into p from public.os_planejamento where service_order_id = p_so_id;
  v_pres := public.os_presenca_do_dono(p_so_id);
  v_sug := public.os_duracao_sugerida(p_so_id);

  -- Os dias: o que o dono disse (ou aceitou); sem isso, o realista da sugestão (só para reserva e simulação).
  if p.dias is not null then
    v_fonte := p.estimativa_fonte;
    v_dias := p.dias;
  else
    v_fonte := 'sugerida';
    v_dias := case when coalesce((v_sug ->> 'sem_base')::boolean, false) then null
                   else (v_sug ->> 'dias_realista')::numeric end;
  end if;
  -- FASE 7: (7a P2, regra estimativa, D7-1) sem os dias ditos, a estimativa do orçamento vale como dias firmes: fonte
  -- 'orcamento' com o realista de _agenda_gestor_estimativa (calculada na leitura; nada é gravado). Quando o gestor não usa
  -- a estimativa (começada ou parada, sem mão de obra, acima de estimativa_max_diarias, peça embutida), a fonte continua
  -- 'sugerida' e a saída diz o porquê (estimativa_motivo; situacao_pendente). Os dias de fonte 'orcamento' GRAVADOS (a
  -- pergunta com prazo que venceu) com o portão falso são lidos como 'sugerida': desligar volta ao de antes.
  if p.dias is null then
    if public._agenda_gestor_regra('estimativa') then
      v_est := public._agenda_gestor_estimativa(p_so_id, p_hoje);
      if coalesce((v_est ->> 'usa')::boolean, false) then
        v_fonte := 'orcamento';
        v_dias := (v_est ->> 'dias')::numeric;
      end if;
      v_f7 := jsonb_build_object(
        'estimativa_motivo', case when coalesce((v_est ->> 'usa')::boolean, false) then null else v_est ->> 'motivo' end,
        'situacao_pendente', coalesce(v_est ->> 'motivo' = 'situacao', false));
    end if;
  elsif p.estimativa_fonte = 'orcamento' and not public._agenda_gestor_regra('estimativa') then
    v_fonte := 'sugerida';
  end if;
  -- FASE 7: fim

  -- A equipe dita: o dono (se está nela) e os diaristas por turno ("dia" vale nos dois).
  v_dita := exists (select 1 from public.os_planejamento_equipe e where e.service_order_id = p_so_id);
  select e.turnos into v_dono_t
    from public.os_planejamento_equipe e join public.payees py on py.id = e.payee_id
   where e.service_order_id = p_so_id and (e.payee_id = v_dono or py.kind = 'socio')
   order by e.payee_id is not distinct from v_dono desc, e.payee_id
   limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'nome', public._agenda_nome_curto(py.name))
                            order by e.turnos = 'dia' desc, py.name, e.payee_id)
                    filter (where e.turnos in ('dia', 'manha')), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'nome', public._agenda_nome_curto(py.name))
                            order by e.turnos = 'dia' desc, py.name, e.payee_id)
                    filter (where e.turnos in ('dia', 'tarde')), '[]'::jsonb)
    into v_pm, v_pt
    from public.os_planejamento_equipe e join public.payees py on py.id = e.payee_id
   where e.service_order_id = p_so_id and e.payee_id is distinct from v_dono and py.kind <> 'socio';

  -- A presença do dono: o que ele disse → ele na equipe dita (o turno inteiro nos turnos dele) → a regra d05.
  if v_pres ->> 'fonte' = 'dono' then
    v_presenca := v_pres ->> 'presenca';
    v_motivo := 'você disse';
  elsif v_dono_t is not null then
    v_presenca := 'equipe';
    v_motivo := 'você está na equipe';
  else
    v_presenca := coalesce(v_pres ->> 'presenca', 'abre_e_fecha');
    v_motivo := v_pres ->> 'motivo';
  end if;
  v_dt_m := v_presenca = 'sempre' or (v_presenca = 'equipe' and v_dono_t in ('dia', 'manha'));
  v_dt_t := v_presenca = 'sempre' or (v_presenca = 'equipe' and v_dono_t in ('dia', 'tarde'));

  -- Quantos diaristas por turno: os ditos; sem equipe dita, as pessoas da sugestão (o dono, quando fica o turno
  -- inteiro, é uma delas).
  v_pessoas := coalesce((v_sug ->> 'pessoas')::int, 1);
  if v_dita then
    v_dm := jsonb_array_length(v_pm);
    v_dtd := jsonb_array_length(v_pt);
  else
    v_dm := greatest(v_pessoas - case when v_dt_m then 1 else 0 end, 0);
    v_dtd := greatest(v_pessoas - case when v_dt_t then 1 else 0 end, 0);
    -- FASE 7: (7a correção 2; AG7-02, AG7-04) com a regra uma_pessoa, a pessoa da estimativa é o técnico: o dono que fica o turno
    -- inteiro (a marina nova, o "sempre" que ele disse) vai junto e não é uma delas — a regra de antes ("o dono é uma das pessoas")
    -- era com 2 pessoas; com 1, o motor marcava só o dono, sem o técnico (a Kalmar OS-00033 o turno inteiro só com você, o Alex
    -- parado e o Lenine empurrado). O diagnóstico e o comissionamento continuam com ele: o trabalho é dele (AG7-10).
    if public._agenda_gestor_regra('uma_pessoa') and (v_dt_m or v_dt_t)
       and coalesce(case when v_pres ->> 'fonte' = 'regra' then v_pres ->> 'motivo'
                         else (select case so.service_type when 'diagnosis' then 'diagnóstico' when 'commissioning' then 'comissionamento' end
                                 from public.service_orders so where so.id = p_so_id) end, '') not in ('diagnóstico', 'comissionamento') then
      v_dm := v_pessoas;
      v_dtd := v_pessoas;
    end if;
    -- FASE 7: fim
  end if;

  -- O que já foi feito e o que já está marcado (d20).
  v_plano := public._agenda_plano_da_os(p_so_id, p_hoje);
  v_cump := coalesce((v_plano ->> 'meios_cumpridos')::numeric, 0);
  v_vig := coalesce((v_plano ->> 'meios_vigentes')::int, 0);
  v_total := case when v_dias is null then null else (v_dias * 2)::int end;
  -- FASE 7b: (7b P4, §5.3, §3.1-8, R4.3) a dupla por meio-dia (modo_dupla fora de desligado), sem a equipe dita e com 1 pessoa por
  -- serviço (com 2 ou mais, o meio-dia de dupla já tem a 2ª pessoa): a dupla da OS (_agenda_dupla_da_os: a dita pelo dono ou a regra
  -- pela tarefa). Ligado e com os dias estimados (fonte sugerida ou orcamento), a duração conserva as diárias-pessoa: pm = as
  -- diárias-pessoa da estimativa em meios-dias; os meios-dias de dupla no início (ni) e no fim (nf) cabem com 2 × (ni + nf) <= pm
  -- (cortando primeiro o fim); o tempo todo = ni = ceil(pm / 2); total = pm − ni − nf (o meio-dia em dupla rende 2: Lenine 12 → 10).
  -- Em teste, ou com os dias ditos, o total é o de antes e ni/nf cabem dentro dele (em teste a dupla só acrescenta a 2ª pessoa).
  v_7b_modo := (public._agenda_cfg()).modo_dupla;
  if v_7b_modo <> 'desligado' and not v_dita and coalesce(v_total, 0) > 0 and v_pessoas = 1 then
    v_7b_dup := public._agenda_dupla_da_os(p_so_id);
    v_7b_todos := coalesce((v_7b_dup ->> 'todos')::boolean, false);
    if v_7b_todos or coalesce((v_7b_dup ->> 'inicio')::int, 0) > 0 or coalesce((v_7b_dup ->> 'fim')::int, 0) > 0 then
      if v_7b_modo = 'ligado' and coalesce(v_fonte, '') not in ('dono', 'aceita') then
        v_7b_pme := greatest(1, round(coalesce((v_sug ->> 'dp_realista')::numeric * 2, v_total)))::int;
        if v_7b_todos then
          v_7b_ni := (v_7b_pme + 1) / 2;
          v_7b_nf := 0;
        else
          v_7b_ni := coalesce((v_7b_dup ->> 'inicio')::int, 0);
          v_7b_nf := coalesce((v_7b_dup ->> 'fim')::int, 0);
          while 2 * (v_7b_ni + v_7b_nf) > v_7b_pme and v_7b_nf > 0 loop v_7b_nf := v_7b_nf - 1; end loop;
          while 2 * (v_7b_ni + v_7b_nf) > v_7b_pme and v_7b_ni > 0 loop v_7b_ni := v_7b_ni - 1; end loop;
        end if;
        v_total := greatest(v_7b_pme - v_7b_ni - v_7b_nf, 1);
      elsif v_7b_todos then
        v_7b_ni := v_total;
      else
        v_7b_ni := least(coalesce((v_7b_dup ->> 'inicio')::int, 0), v_total);
        v_7b_nf := least(coalesce((v_7b_dup ->> 'fim')::int, 0), v_total - v_7b_ni);
      end if;
    else
      v_7b_dup := null;
    end if;
  end if;
  -- FASE 7b: fim
  v_rest := case when v_total is null then null else greatest(v_total - v_cump - v_vig, 0) end;
  v_fecha := v_presenca = 'abre_e_fecha';
  v_abre := v_fecha and coalesce((v_plano ->> 'dias')::int, 0) = 0 and v_cump = 0 and v_status <> 'in_progress';

  -- O molde, como o dono disse e começando de manhã (o motor aplica o turno de verdade de cada meio-dia).
  for k in 1 .. coalesce(v_total, 0) loop
    v_t := case when k % 2 = 1 then 'manha' else 'tarde' end;
    v_papel := '{}';
    if (v_t = 'manha' and v_dt_m) or (v_t = 'tarde' and v_dt_t) then
      v_papel := array['turno'];
    else
      if k = 1 and v_fecha then v_papel := v_papel || 'abertura'::text; end if;
      if k = v_total and v_fecha then v_papel := v_papel || 'fechamento'::text; end if;
    end if;
    v_molde := v_molde || jsonb_build_object('k', k, 'turno', v_t,
      'pessoas_ditas', case when v_t = 'manha' then v_pm else v_pt end,
      'desejado', case when v_t = 'manha' then v_dm else v_dtd end,
      'dono', to_jsonb(v_papel));
  end loop;
  -- FASE 7b: (7b P4) as pessoas de cada passo do molde (pk: 2 nos meios-dias da dupla — os ni primeiros, os nf últimos, ou todos —,
  -- 1 nos outros; o dono que fica o turno inteiro conta como uma delas, fora a regra da correção 2 da 7a: dk_dono_conta), o dk (os
  -- passos que restam: os últimos "passos" do molde) e a dupla com ni, nf, pm (a soma das pessoas do molde: com a duração que
  -- conserva, as diárias-pessoa da estimativa) e pk. A saída de cima (a da regra estimativa) leva tudo junto; sem dupla, nada.
  if v_7b_dup is not null then
    for v_7b_n in 1 .. v_total loop
      v_7b_pk := v_7b_pk || case when v_7b_todos or v_7b_n <= v_7b_ni or v_7b_n > v_total - v_7b_nf
                                 then greatest(v_pessoas, 2) else v_pessoas end;
    end loop;
    v_7b_conta := not (public._agenda_gestor_regra('uma_pessoa') and (v_dt_m or v_dt_t)
      and coalesce(case when v_pres ->> 'fonte' = 'regra' then v_pres ->> 'motivo'
                        else (select case so.service_type when 'diagnosis' then 'diagnóstico' when 'commissioning' then 'comissionamento' end
                                from public.service_orders so where so.id = p_so_id) end, '') not in ('diagnóstico', 'comissionamento'));
    v_f7 := coalesce(v_f7, '{}'::jsonb) || jsonb_build_object(
      'dk', to_jsonb(v_7b_pk[v_total - (case when v_rest is null then 0 else ceil(v_rest)::int end) + 1 : v_total]),
      'dk_dono_conta', v_7b_conta,
      'dupla', v_7b_dup || jsonb_build_object('ni', v_7b_ni, 'nf', v_7b_nf, 'todos', v_7b_todos,
                                              'pm', (select sum(x)::int from unnest(v_7b_pk) x), 'pm_estimativa', v_7b_pme,
                                              'pk', to_jsonb(v_7b_pk), 'modo', v_7b_modo));
  end if;
  -- FASE 7b: fim
  -- FASE 7: (7a P2) com a regra estimativa, a mesma saída de baixo mais estimativa_motivo e situacao_pendente; sem a regra, a
  -- saída de baixo, byte a byte.
  if v_f7 is not null then
    return jsonb_build_object(
      'ok', true, 'os', p_so_id, 'fonte', v_fonte, 'dias', trim_scale(v_dias), 'sem_base', v_dias is null,
      'total', v_total, 'cumpridos', trim_scale(v_cump), 'vigentes', v_vig, 'restantes', trim_scale(v_rest),
      'passos', case when v_rest is null then 0 else ceil(v_rest)::int end,
      'presenca', v_presenca, 'presenca_motivo', v_motivo, 'abre', v_abre, 'fecha', v_fecha,
      -- o motivo da regra d05 (o tipo do meio-dia: diagnóstico, comissionamento), mesmo quando o dono disse a presença
      'regra_motivo', case when v_pres ->> 'fonte' = 'regra' then v_pres ->> 'motivo'
                           else (select case so.service_type when 'diagnosis' then 'diagnóstico' when 'commissioning' then 'comissionamento' end
                                   from public.service_orders so where so.id = p_so_id) end,
      'dono_turno', jsonb_build_object('manha', v_dt_m, 'tarde', v_dt_t),
      'equipe_dita', v_dita, 'pessoas_sugeridas', case when v_dita then null else v_pessoas end,
      'por_turno', jsonb_build_object('manha', jsonb_build_object('pessoas', v_pm, 'desejado', v_dm),
                                      'tarde', jsonb_build_object('pessoas', v_pt, 'desejado', v_dtd)),
      'molde', v_molde) || v_f7;
  end if;
  -- FASE 7: fim

  return jsonb_build_object(
    'ok', true, 'os', p_so_id, 'fonte', v_fonte, 'dias', trim_scale(v_dias), 'sem_base', v_dias is null,
    'total', v_total, 'cumpridos', trim_scale(v_cump), 'vigentes', v_vig, 'restantes', trim_scale(v_rest),
    'passos', case when v_rest is null then 0 else ceil(v_rest)::int end,
    'presenca', v_presenca, 'presenca_motivo', v_motivo, 'abre', v_abre, 'fecha', v_fecha,
    -- o motivo da regra d05 (o tipo do meio-dia: diagnóstico, comissionamento), mesmo quando o dono disse a presença
    'regra_motivo', case when v_pres ->> 'fonte' = 'regra' then v_pres ->> 'motivo'
                         else (select case so.service_type when 'diagnosis' then 'diagnóstico' when 'commissioning' then 'comissionamento' end
                                 from public.service_orders so where so.id = p_so_id) end,
    'dono_turno', jsonb_build_object('manha', v_dt_m, 'tarde', v_dt_t),
    'equipe_dita', v_dita, 'pessoas_sugeridas', case when v_dita then null else v_pessoas end,
    'por_turno', jsonb_build_object('manha', jsonb_build_object('pessoas', v_pm, 'desejado', v_dm),
                                    'tarde', jsonb_build_object('pessoas', v_pt, 'desejado', v_dtd)),
    'molde', v_molde);
end;
$function$;

comment on function public.agenda_meios_da_os(uuid, date) is
  'Agenda de Produção (Fase 2, P2): o molde dos meios-dias do que o dono disse — total = dias × 2 (meio dia = 1); por turno os diaristas ditos ("dia" vale nos dois) e quantos (desejado; sem equipe dita, as pessoas da sugestão, e o dono que fica o turno inteiro é uma delas); a presença do dono: o que ele disse → ele na equipe dita (turno nos turnos dele) → a regra d05 (sempre = turno em todos; abre_e_fecha = abertura no 1º e fechamento no último); restantes = total − cumpridos (cumprido/sem registro/passado sem resultado = 1, parcial = 0,5) − os meios-dias vigentes de hoje em diante. Sem os dias ditos: fonte sugerida (dias_realista), só para reserva e simulação. {ok, fonte, dias, total, restantes, passos, presenca, abre, fecha, dono_turno, por_turno, molde[{k, turno, pessoas_ditas, desejado, dono}]}. FASE 7 (7a P2): sem os dias ditos e com a regra estimativa (_agenda_gestor_regra), a fonte é ''orcamento'' com os dias de _agenda_gestor_estimativa quando ela usa (D7-1: a estimativa do orçamento vale como dias firmes; nada é gravado), e a saída ganha estimativa_motivo (por que não usa: situacao, sem_base, grande, embutida; null quando usa) e situacao_pendente; os dias de fonte ''orcamento'' gravados com o portão falso são lidos como ''sugerida''. Sem a regra, a saída de antes, byte a byte. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; AG7-02/AG7-04): com a regra uma_pessoa, o dono que fica o turno inteiro (presença sempre: a marina nova, o que ele disse) não é a pessoa da estimativa — os técnicos desejados por turno são as pessoas da sugestão, e ele vai junto; no diagnóstico e no comissionamento (dele), a de antes. Sem a regra, a de antes, byte a byte. FASE 7b (P4, §5.3, R4.3(e)): com modo_dupla fora de desligado, sem a equipe dita e com 1 pessoa por serviço, a dupla por meio-dia — dupla (a de _agenda_dupla_da_os: fonte dono ou regra) || {ni, nf, todos, pm (a soma das pessoas do molde), pm_estimativa, pk (as pessoas de cada passo do molde: 2 nos ni primeiros, nos nf últimos ou em todos, 1 nos outros), modo}, dk (as pessoas dos passos que restam) e dk_dono_conta (o dono que fica o turno inteiro é uma das pessoas, salvo a regra da correção 2 da 7a: presença sempre fora do diagnóstico e do comissionamento). Ligado e com os dias estimados, a duração conserva as diárias-pessoa: total = pm − ni − nf, com 2 × (ni + nf) <= pm (cortando primeiro o fim) e o tempo todo = ceil(pm / 2) meios-dias em dupla (Lenine 12 → 10; Vanderlei 15 → 13). Em teste ou com os dias ditos, o total é o de antes. O por_turno.desejado continua o de antes. Sem dupla (ou desligado), a saída de antes, byte a byte.';

-- _agenda_classe_da_os (de 20261031100985_agenda_fase77a_correcao2.sql)
create or replace function public._agenda_classe_da_os(p_pront jsonb, p_meios jsonb, p_hoje date,
                                                       p_tem_fixada boolean default false,
                                                       p_fora_do_horizonte boolean default false)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_est   text := p_pront ->> 'estado';
  v_r     jsonb := coalesce(p_pront -> 'restricoes', '[]'::jsonb);
  v_mat   text := p_pront #>> '{material,estado}';
  v_crit  jsonb;
  v_trava jsonb;
  v_cond  text[] := '{}';
  v_txt   text;
  v_mat_trava boolean;
  -- FASE 7: (7a correção 2, a dupla sem a 2ª pessoa) quantas pessoas o meio-dia pede e quem a grade tem
  v_f72_n    int;
  v_f72_tec  text[];
  -- FASE 7: fim
  -- FASE 7b: (7b P4, R4.3(b)) quantas pessoas a dupla dita pede num passo
  v_7b_n    int;
  -- FASE 7b: fim
begin
  if not coalesce((p_pront ->> 'ok')::boolean, false) then
    return jsonb_build_object('classe', 4, 'motivo', 'nao_achei', 'texto', 'não encontrei esse serviço');
  end if;
  if v_est in ('concluida', 'fora_da_carteira') then
    return jsonb_build_object('classe', 4, 'motivo', 'fora_da_carteira', 'texto', p_pront ->> 'estado_texto');
  end if;
  if v_est = 'congelada' then
    return jsonb_build_object('classe', 4, 'motivo', 'congelada', 'texto', p_pront ->> 'estado_texto');
  end if;

  select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_crit
    from jsonb_array_elements(coalesce(p_pront #> '{material,itens}', '[]'::jsonb)) with ordinality t(e, o)
   where coalesce((e ->> 'critico')::boolean, true) and e ->> 'nivel' is distinct from 'A';

  -- Material que trava de vez (nem reserva): previsão vencida, ou falta sem previsão que não é compra já combinada.
  v_mat_trava := v_mat = 'atrasado'
     or (v_mat = 'sem_previsao' and exists (
           select 1 from jsonb_array_elements(v_crit) e
            where coalesce((e ->> 'sem_data')::boolean, false)
              and not (e ->> 'situacao' = 'falta' and coalesce((e ->> 'compra_prevista_em')::date >= p_hoje, false))));

  -- Em execução (ou com meio-dia fixado): compromisso primeiro, se o material deixa.
  if v_est in ('em_execucao', 'parada') or p_tem_fixada then
    if v_mat_trava then
      select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
       where e ->> 'tipo' in ('atrasado', 'sem_previsao', 'comprado_sem_previsao') order by o limit 1;
      return jsonb_build_object('classe', 4, 'motivo', 'material',
                                'texto', coalesce(v_trava ->> 'texto', p_pront ->> 'estado_texto'));
    end if;
    -- FASE 7: (7a P3, regra situacao; AG7-11, §3.3 d6) a OS em andamento sem os dias ditos e sem plano (situacao_pendente de
    -- agenda_meios_da_os, só com a regra estimativa) também espera o "quanto falta?" antes de entrar no plano: sem isso, o motor
    -- a marcaria com a estimativa inteira (só a sugerida existe)
    if p_meios ->> 'situacao_pendente' = 'true' then
      return jsonb_build_object('classe', 4, 'motivo', 'situacao',
                                'texto', coalesce((select e ->> 'texto' from jsonb_array_elements(v_r) with ordinality t(e, o)
                                                    where e ->> 'tipo' = 'situacao' order by o limit 1), p_pront ->> 'estado_texto'));
    end if;
    -- FASE 7: fim
    return jsonb_build_object('classe', 1, 'motivo', case when p_tem_fixada then 'fixada' else 'em_execucao' end,
                              'texto', p_pront ->> 'estado_texto');
  end if;

  -- O que trava antes do material (quem destrava primeiro): orçamento, sinal, cliente, escopo; o bem ou o "não antes de"
  -- além do horizonte; depois o material que trava de vez.
  select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
   where e ->> 'tipo' in ('orcamento', 'sinal', 'cliente', 'escopo') order by o limit 1;
  -- FASE 7: (7a P12, regra sinal_cobrar; AG7-09 "marco e cobro o sinal", spec §R1 e §5.12) o sinal combinado e não pago não
  -- trava: a OS segue para a classe que teria sem ele (o compromisso, se o resto estiver pronto) — nada de reserva por sinal,
  -- e condicao_tipo não ganha 'sinal' — e o gestor lembra o dono de cobrar quando ela ganha dia (_agenda_gestor_sinal). O que
  -- trava depois do sinal na mesma lista (o orçamento, o cliente, o escopo) continua travando. Sem a regra, a de antes.
  if v_trava ->> 'tipo' = 'sinal' and public._agenda_gestor_regra('sinal_cobrar') then
    select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
     where e ->> 'tipo' in ('orcamento', 'cliente', 'escopo') order by o limit 1;
  end if;
  -- FASE 7: fim
  if v_trava is not null then
    return jsonb_build_object('classe', 4, 'motivo', v_trava ->> 'tipo', 'texto', v_trava ->> 'texto');
  end if;
  -- FASE 7b: (7b P4, R4.3(b)) a dupla DITA pelo dono (fonte dono: o tempo todo, no início ou no fim — a dita no início ou no fim
  -- a correção 2 não via, o desejado dela é 1) com modo_dupla fora de desligado (o dk só existe assim): pede o maior dk dos passos que
  -- restam (o dono que conta como uma das pessoas sai da conta); com menos técnicos na grade (_agenda_tecnicos_da_grade: com quem
  -- vem sob demanda, R4.3(c)) espera o dono, classe 4 dupla — também em teste: sem isso a dita no início sairia do plano calada. A
  -- dupla inferida pela tarefa (fonte regra) nunca segura a OS: vai com 1 pessoa (o encaixe).
  if p_meios ? 'dk' and p_meios #>> '{dupla,fonte}' = 'dono' and not coalesce((p_meios ->> 'equipe_dita')::boolean, false) then
    v_7b_n := coalesce((select max(x::int) from jsonb_array_elements_text(p_meios -> 'dk') x), 0)
              - case when coalesce((p_meios ->> 'dk_dono_conta')::boolean, true)
                          and (coalesce((p_meios #>> '{dono_turno,manha}')::boolean, false)
                               or coalesce((p_meios #>> '{dono_turno,tarde}')::boolean, false)) then 1 else 0 end;
    if v_7b_n >= 2 then
      v_f72_tec := public._agenda_tecnicos_da_grade(p_hoje);
      if cardinality(v_f72_tec) < v_7b_n then
        return jsonb_build_object('classe', 4, 'motivo', 'dupla',
          'texto', format('precisa de %s pessoas e %s: chame um ajudante e me diga os dias dele', v_7b_n,
                          public._agenda_tecnicos_frase(v_f72_tec)));
      end if;
    end if;
  end if;
  -- FASE 7b: fim
  -- FASE 7: (7a correção 2, a dupla sem a 2ª pessoa; AG7-04 e fase7-padroes: "o gestor SUGERE quando chamar (ex.: dupla
  -- necessária)") com a regra uma_pessoa, a OS que o dono disse que vai com dupla (um meio-dia que pede 2 pessoas em
  -- agenda_meios_da_os, sem a equipe dita) e a grade com menos técnicos do que isso espera o dono: classe 4, motivo dupla. Antes,
  -- com o Alex sozinho, o motor a tirava do plano calado ("sem lugar") e ela nunca voltava. A grade só é lida quando a OS pede 2.
  if public._agenda_gestor_regra('uma_pessoa') and not coalesce((p_meios ->> 'equipe_dita')::boolean, false) then
    v_f72_n := greatest(coalesce((p_meios #>> '{por_turno,manha,desejado}')::int, 0),
                        coalesce((p_meios #>> '{por_turno,tarde,desejado}')::int, 0));
    if v_f72_n >= 2 then
      v_f72_tec := public._agenda_tecnicos_da_grade(p_hoje);
      if cardinality(v_f72_tec) < v_f72_n then
        return jsonb_build_object('classe', 4, 'motivo', 'dupla',
          'texto', format('precisa de %s pessoas e %s: chame um ajudante e me diga os dias dele', v_f72_n,
                          public._agenda_tecnicos_frase(v_f72_tec)));
      end if;
    end if;
  end if;
  -- FASE 7: fim
  if p_fora_do_horizonte then
    select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
     where e ->> 'tipo' in ('bem', 'nao_antes') order by o limit 1;
    return jsonb_build_object('classe', 4, 'motivo', 'bem', 'texto', coalesce(v_trava ->> 'texto', p_pront ->> 'estado_texto'));
  end if;
  if v_mat_trava then
    select e into v_trava from jsonb_array_elements(v_r) with ordinality t(e, o)
     where e ->> 'tipo' in ('atrasado', 'sem_previsao', 'comprado_sem_previsao') order by o limit 1;
    return jsonb_build_object('classe', 4, 'motivo', 'material',
                              'texto', coalesce(v_trava ->> 'texto', p_pront ->> 'estado_texto'));
  end if;
  -- FASE 7: (7a P3) o que o gestor não marca sem perguntar antes (as chaves de agenda_meios_da_os, que só existem com a regra
  -- estimativa): a OS começada ou parada (situacao_pendente, AG7-11) e a estimativa que ele não usa sozinho — acima de
  -- estimativa_max_diarias, com peça embutida ou sem mão de obra separada (estimativa_motivo, com a fonte ainda 'sugerida').
  -- Antes de "sem base para estimar" (que, sem a regra, continua 'duracao'); o P4 pergunta por estes dois motivos.
  if p_meios ->> 'situacao_pendente' = 'true' then
    return jsonb_build_object('classe', 4, 'motivo', 'situacao',
                              'texto', coalesce((select e ->> 'texto' from jsonb_array_elements(v_r) with ordinality t(e, o)
                                                  where e ->> 'tipo' = 'situacao' order by o limit 1), p_pront ->> 'estado_texto'));
  end if;
  if p_meios ->> 'estimativa_motivo' in ('grande', 'embutida', 'sem_base') and p_meios ->> 'fonte' = 'sugerida' then
    return jsonb_build_object('classe', 4, 'motivo', 'estimativa',
                              'texto', coalesce((select e ->> 'texto' from jsonb_array_elements(v_r) with ordinality t(e, o)
                                                  where e ->> 'tipo' = 'duracao' order by o limit 1),
                                                'quantos dias e com quem? (o orçamento não dá base para estimar)'));
  end if;
  -- FASE 7: fim
  if coalesce((p_meios ->> 'sem_base')::boolean, false) or (p_meios ->> 'total') is null then
    return jsonb_build_object('classe', 4, 'motivo', 'duracao',
                              'texto', 'quantos dias e com quem? (o orçamento não dá base para estimar)');
  end if;

  -- O que só deixa reservar (classe 3), do que mais trava ao que menos.
  if exists (select 1 from jsonb_array_elements(v_crit) e where e ->> 'nivel' = 'D' and e ->> 'situacao' = 'falta') then
    v_cond := v_cond || 'compra'::text;
  end if;
  -- FASE 7: (7a P3, regra compra_firme; D7-2, AG7-07) a peça a comprar com "compre até" (vivo ou gravado) abaixo do teto de
  -- empurrões não segura a OS na reserva: ela fica no compromisso e a compra é cobrada (o item vem marcado compra_firme pela
  -- os_prontidao). Só sai a condição quando TODA falta de nível D é firme.
  if 'compra' = any (v_cond) and public._agenda_gestor_regra('compra_firme')
     and not exists (select 1 from jsonb_array_elements(v_crit) e
                      where e ->> 'nivel' = 'D' and e ->> 'situacao' = 'falta'
                        and not coalesce((e ->> 'compra_firme')::boolean, false)) then
    v_cond := array_remove(v_cond, 'compra'::text);
  end if;
  -- FASE 7: fim
  if v_mat = 'sem_previsao'
     or exists (select 1 from jsonb_array_elements(v_crit) e
                 where e ->> 'nivel' = 'D' and e ->> 'situacao' in ('comprado', 'a_caminho')) then
    v_cond := v_cond || 'material'::text;
  end if;
  if v_mat = 'nao_conferido' then
    v_cond := v_cond || 'conferir_material'::text;
  end if;
  if p_meios ->> 'fonte' = 'sugerida' then
    v_cond := v_cond || 'duracao'::text;
  end if;
  if cardinality(v_cond) = 0 then
    return jsonb_build_object('classe', 2, 'motivo', 'pronta', 'texto', p_pront ->> 'estado_texto');
  end if;

  select e ->> 'texto' into v_txt from jsonb_array_elements(v_r) with ordinality t(e, o)
   where e ->> 'tipo' = any (case v_cond[1]
           when 'compra' then array['compre_ate', 'sem_previsao']
           when 'material' then array['compra_sem_prazo', 'comprado_sem_previsao', 'sem_previsao']
           when 'conferir_material' then array['peca_embutida', 'material_nao_conferido']
           else array['duracao'] end)
   order by o limit 1;
  return jsonb_build_object('classe', 3, 'motivo', v_cond[1], 'condicao_tipo', v_cond[1], 'condicoes', to_jsonb(v_cond),
                            'texto', coalesce(v_txt, p_pront ->> 'estado_texto'));
end;
$function$;

comment on function public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean) is
  'Agenda de Produção (Fase 2, P2): a classe da OS para o motor, pelas restrições de os_prontidao e o molde de agenda_meios_da_os — 1 = em execução/parada ou com meio-dia fixado (compromisso, primeiro); 2 = pronta: dias ditos ou aceitos, sem orçamento/sinal/cliente/escopo travando e todo crítico em A, B ou C (compromisso); 3 = o que falta é só compra (D falta, o "compre até"), material comprado sem previsão ou compra combinada sem prazo, conferir o material (zero linhas ou peça embutida) ou dias só sugeridos (só reserva condicionada; condicao_tipo na ordem compra > material > conferir_material > duracao); 4 = nunca: fora da carteira, em espera, material atrasado ou sem previsão, orçamento, sinal, cliente, escopo, o bem ou o "não antes de" além do horizonte, sem base para os dias. {classe, motivo, texto (quem trava), condicao_tipo}. FASE 7 (7a P3), com as chaves de agenda_meios_da_os que só existem com a regra estimativa: a OS começada ou parada (situacao_pendente; também a em andamento sem plano nem dias) = classe 4 situacao; a estimativa que o gestor não usa sozinho (estimativa_motivo grande, embutida ou sem_base, com a fonte sugerida) = classe 4 estimativa, antes do "sem base" (que sem a regra continua duracao); com a regra compra_firme, a falta de nível D com compra_firme (os_prontidao) não entra na condição compra (a OS fica no compromisso). Sem o portão, a de antes. FASE 7 (7a P12; AG7-09 "marco e cobro o sinal"): com a regra sinal_cobrar, o sinal combinado e não pago sai da trava de antes do material e não entra em condição nenhuma (condicao_tipo não ganha sinal): a OS fica na classe que teria sem ele (o compromisso, se o resto estiver pronto); o orçamento, o cliente e o escopo continuam travando. O gestor lembra o dono de cobrar (_agenda_gestor_sinal). Sem a regra, a de antes. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; a dupla sem a 2ª pessoa, AG7-04): com a regra uma_pessoa, a OS que pede 2 pessoas num meio-dia (a dupla dita, sem a equipe dita) e a grade (_agenda_tecnicos_da_grade) com menos técnicos do que isso é classe 4, motivo dupla ("precisa de 2 pessoas e só Alex está na equipe: chame um ajudante e me diga os dias dele"): espera o dono em vez de sair do plano calada. Sem a regra, a de antes, byte a byte. FASE 7b (P4, R4.3(b)): com modo_dupla fora de desligado (sombra e ligado), a dupla DITA pelo dono (fonte dono em agenda_meios_da_os: o tempo todo, no início ou no fim) pede o maior dk dos passos que restam (menos o dono quando ele conta como uma das pessoas); com menos técnicos na grade (_agenda_tecnicos_da_grade, que fora de desligado conta quem vem sob demanda com meio-dia livre no horizonte), classe 4, motivo dupla ("precisa de 2 pessoas e só Alex está na equipe: chame um ajudante e me diga os dias dele"). A dupla inferida (fonte regra) nunca segura a OS. Desligado, a de antes, byte a byte.';

-- _agenda_tecnicos_da_grade (de 20261031100985_agenda_fase77a_correcao2.sql)
create or replace function public._agenda_tecnicos_da_grade(p_hoje date)
 returns text[]
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(array_agg(x ->> 'nome' order by o), '{}'::text[])
         -- FASE 7b: (7b P4, R4.3(c)) com modo_dupla fora de desligado, depois dos de padrão (a semanal, na ordem dela), quem está na grade
         -- sem padrão (vem sob demanda, _agenda_e_sob_demanda) com algum meio-dia livre de hoje a hoje + 7 × horizonte_semanas (as datas
         -- que o dono disse): é a 2ª pessoa que destrava a dupla dita. Desligado, a de antes.
         || case when (public._agenda_cfg()).modo_dupla = 'desligado' then '{}'::text[]
                 else coalesce((select array_agg(s.nome order by s.nome, s.payee_id)
                                  from (select distinct k.payee_id, k.pessoa as nome
                                          from public.agenda_capacidade(p_hoje, p_hoje + 7 * (public._agenda_cfg()).horizonte_semanas - 1,
                                                                        p_hoje) k
                                         where not k.eh_dono and k.situacao = 'livre') s
                                 where public._agenda_e_sob_demanda(s.payee_id, p_hoje)), '{}'::text[]) end
         -- FASE 7b: fim
    from jsonb_array_elements(coalesce(public.agenda_capacidade_semanal(p_hoje) -> 'pessoas', '[]'::jsonb)) with ordinality t(x, o)
   where not coalesce((x ->> 'eh_dono')::boolean, false);
$function$;

comment on function public._agenda_tecnicos_da_grade(date) is
  'Agenda de Produção (Fase 7a, correção 2 da revisão): os nomes curtos de quem a agenda conta na equipe (agenda_capacidade_semanal de p_hoje), sem o dono, na ordem dela. A dupla dita com menos técnicos do que ela pede espera o dono (_agenda_classe_da_os), e a palavra *<nome> com dupla* e o foco gestor dizem quem está. STABLE, invoker; authenticated e service_role (as leituras do painel e do foco chegam aqui). FASE 7b (P4, R4.3(c)): com modo_dupla fora de desligado, depois dos de padrão, quem está na grade sem padrão (_agenda_e_sob_demanda: vem sob demanda) com algum meio-dia livre de hoje a hoje + 7 × horizonte_semanas, pelo nome — é a 2ª pessoa que destrava a dupla dita (o Mateus dito "qua e qui"). Desligado, a de antes, byte a byte.';

-- _agenda_carga_da_pessoa (de 20261029100400_agenda_fase6_dono.sql)
create or replace function public._agenda_carga_da_pessoa(p_payee uuid)
 returns numeric
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c public.agenda_config := public._agenda_cfg();
  v numeric;
begin
  if p_payee is not null and p_payee = public._agenda_dono(null) then
    -- FASE 7b: (7b P4, R4.5; AG7-02, confirmado no fio) com modo_dias fora de desligado, o dono vai até dono_carga_max (a meia
    -- capacidade que ele disse): o aprendido (capacidade_dono) só abaixa, a palavra dele é o teto. Desligado, o de antes.
    if c.modo_dias <> 'desligado' then
      return least(coalesce(public._agenda_aprendido('capacidade_dono', 'dono'), c.dono_carga_max), c.dono_carga_max);
    end if;
    -- FASE 7b: fim
    v := public._agenda_aprendido('capacidade_dono', 'dono');
    if v is not null then
      return least(v, c.carga_max);
    end if;
  end if;
  return c.carga_max;
end;
$function$;

comment on function public._agenda_carga_da_pessoa(uuid) is
  'Agenda de Produção (Fase 6, P4): a parte da semana de uma pessoa que o motor compromete — o dono com capacidade_dono em uso (_agenda_aprendido: só com modo_aprendizado ligado e capacidade_dono na lista) → o valor, nunca acima de carga_max; os outros (e o dono sem nada em uso) → carga_max. Lida pelo teto80 de _agenda_contexto e pela regra 6 de _agenda_validar_itens. FASE 7b (P4, R4.5; AG7-02): com modo_dias fora de desligado, o dono → least(coalesce(o aprendido capacidade_dono, dono_carga_max), dono_carga_max): a meia capacidade que ele disse é o teto (com a linha seg–sex, 5 meios-dias de turno por semana); o aprendido só abaixa. Desligado, a de antes, byte a byte.';

-- _agenda_gestor_pessoa_meios (de 20261031100980_agenda_fase77a_correcao.sql)
create or replace function public._agenda_gestor_pessoa_meios(p_os uuid, p_hoje date, p_meios jsonb)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with p as (
    select coalesce((p_meios ->> 'pessoas_sugeridas')::int,
                    greatest(coalesce((p_meios #>> '{por_turno,manha,desejado}')::int, 0)
                             + case when coalesce((p_meios #>> '{dono_turno,manha}')::boolean, false) then 1 else 0 end, 1)) as pessoas
  )
  select jsonb_build_object(
           'pessoas', p.pessoas,
           'precisa', case when (p_meios ->> 'total') is null then null else (p_meios ->> 'total')::int * p.pessoas end,
           -- FASE 7b: (7b P4, R4.3(a)6) com a dupla por meio-dia (dk de agenda_meios_da_os) o que a estimativa pede não é total × pessoas
           -- (com a duração que conserva, o total já é menor): ligado, as diárias-pessoa do molde (dupla.pm: o bloco de 1 pessoa e o em
           -- dupla têm o mesmo, nada é cortado nem falta; a dupla completada depois corta o que ela encurtou); em teste, entre o de 1
           -- pessoa (total × pessoas) e o com a dupla acrescentada (dupla.pm): nem corte nem falta nessa faixa. A chave repetida vale
           -- (no jsonb, a última); sem dk, o de antes.
           'precisa', case when not (p_meios ? 'dk') or (p_meios ->> 'total') is null or (p_meios #>> '{dupla,pm}') is null
                             then case when (p_meios ->> 'total') is null then null else (p_meios ->> 'total')::int * p.pessoas end
                           when (public._agenda_cfg()).modo_dupla = 'ligado' then (p_meios #>> '{dupla,pm}')::int
                           else greatest((p_meios ->> 'total')::int * p.pessoas,
                                         least(floor((select coalesce(sum(case when a.resultado in ('cumprido', 'sem_registro') then 1
                                                                               when a.resultado = 'parcial' then 0.5
                                                                               when a.resultado = 'nao_cumprido' then 0
                                                                               else 1 end), 0)
                                                        from public.agenda_alocacoes a
                                                       where a.service_order_id = p_os and a.estado in ('publicada', 'fixada')
                                                         and a.tipo <> 'reserva' and a.presenca = 'turno'))::int,
                                               (p_meios #>> '{dupla,pm}')::int)) end,
           -- FASE 7b: fim
           'tem', (select trim_scale(coalesce(sum(case when a.resultado in ('cumprido', 'sem_registro') then 1
                                                     when a.resultado = 'parcial' then 0.5
                                                     when a.resultado = 'nao_cumprido' then 0
                                                     else 1 end), 0))
                     from public.agenda_alocacoes a
                    where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                      and a.presenca = 'turno'))
    from p;
$function$;

comment on function public._agenda_gestor_pessoa_meios(uuid, date, jsonb) is
  'Agenda de Produção (Fase 7a, correção da revisão; achado 16): {pessoas, precisa, tem} da OS em pessoa-meio-dia — precisa = agenda_meios_da_os.total × as pessoas da estimativa (pessoas_sugeridas; com a equipe dita, as da manhã, com o dono quando fica o turno); tem = os meios-dias de turno de cada pessoa no plano vigente, fora a reserva (cumprido e sem registro 1, parcial meio, não cumprido 0, o resto 1). A revisão diária e o corte do gestor comparam por aqui: a dupla dita depois de marcar não vira corte. STABLE, invoker, sem grant. FASE 7b (P4, R4.3(a)6): com a dupla por meio-dia (p_meios com dk), precisa = dupla.pm (ligado: as diárias-pessoa do molde — o bloco de 1 pessoa do Lenine, 12, e o em dupla, 2 × 2 + 8, não cortam nem faltam; a dupla completada depois, 14, corta 2) ou, em teste, greatest(total × pessoas, least(floor(tem), dupla.pm)) (entre o de 1 pessoa, 12, e o com a dupla acrescentada, 14, nada a cortar nem a acrescentar). Sem dk, a de antes, byte a byte.';

-- _agenda_contexto (de 20261031100400_agenda_fase7a_teto.sql)
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
    for f7_w in 1 .. v_nw loop
      v_f7_soma := 0;
      for f7_p in 1 .. coalesce(v_np, 0) loop
        continue when f7_p = v_dono;
        v_f7_soma := v_f7_soma + coalesce(v_espw[(f7_p - 1) * v_nw + f7_w], 0);
        v_t80[(f7_p - 1) * v_nw + f7_w] := v_t100[(f7_p - 1) * v_nw + f7_w];
      end loop;
      v_f7_te := v_f7_te || floor(cf.carga_max * v_f7_soma)::int;
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
  'Agenda de Produção (Fase 2, P2): a grade do motor em arrays (agenda_grade de p_d_ini a p_d_fim, sem as alocações de p_ignorar): pessoas (você primeiro), dias úteis, semana ISO de cada dia, quem está livre em cada meio-dia (cap), as pontas livres do dono (curta: 1 abertura, 2 fechamento), o que o vigente ocupa (ocup, frentes: o índice da OS em oss, negativo = reserva), o uso por pessoa e semana (compromisso e reserva) e os tetos floor(carga_max × esperado) e floor(esperado) — o esperado só de dia útil (o sábado combinado não sobe o teto). As OS de p_fila vêm primeiro em oss. FASE 6 (P4): o teto80 de cada pessoa usa _agenda_carga_da_pessoa (o dono com capacidade_dono em uso: floor(carga dele × esperado); os outros, carga_max) — a posição (pp − 1) × nw + ww é a pessoa v_pes[pp] na semana ww; fora de ligado, a saída de antes. FASE 7 (7a P5), atrás do portão _agenda_gestor_regra(''teto_equipe'') (falso = a saída de antes, byte a byte): cada pessoa da equipe (todas menos o dono) pode chegar a 100% do esperado dela na semana (teto80 = teto100); a equipe inteira, a teto_equipe[semana] = floor(carga_max × a soma do esperado da equipe), arredondado uma vez, na soma; o dono mantém o teto dele (_agenda_carga_da_pessoa) e fica fora da soma (é presença, não capacidade de técnico); a saída ganha teto_equipe (um número por semana, na ordem de sem). O gancho do sábado (AG7-08): só com a variável agenda.sabado = ''on'' (a decisão da pergunta crítica sabado a liga) e sabado_manha diferente de nunca, a manhã de cada sábado que ainda não é útil e não é feriado vira útil, com lugar só para quem tem o padrão de sábado de manhã (sem exceção nem recesso naquele dia); a tarde fica sem ninguém; o sábado não entra no esperado (o teto não sobe). Sem a variável, nada muda. FASE 7b (P4, §5.3, §R2, R4.4): (0) o gancho do sábado do 7a (agenda.sabado) só com modo_sabado desligado; (1) sab = os sábados do período sem feriado nem recesso de manhã e (2) sab_bonus por pessoa e semana = as manhãs de sábado livres dela (a que ela ofereceu), com modo_sabado fora de desligado e sabado_manha diferente de nunca; (3) novato = os índices de quem nunca fica sozinho — o novato (_agenda_e_novato, novato_sozinho falso) e quem vem sob demanda (_agenda_e_sob_demanda, sob_demanda_sozinho falso) —, com modo_dupla fora de desligado, nunca o dono; (4) dono_tec = dono_como_tecnico com modo_dias fora de desligado. O gancho da pessoa a mais (R4.4, inerte sem a variável): com agenda.pessoa_extra = tecnico, "mais uma pessoa" (_agenda_pessoa_extra_id) entra por último, livre nas manhãs e tardes de todo dia útil, não novato nem sob demanda, com o teto de carga_max e contada no teto da equipe. Os tetos não mudam. Sem os modos e sem a variável, a saída de antes, byte a byte.';

-- _agenda_tentar_bloco (de 20261031100400_agenda_fase7a_teto.sql)
create or replace function public._agenda_tentar_bloco(
  p_g jsonb, p_util boolean[], p_sem int[], p_cap int[], p_curta int[], p_ocup int[], p_fr int[],
  p_teto int[], p_uso int[], p_rest int[], p_loc int[], p_o jsonb, p_d0 int, p_reserva boolean, p_min_h int)
 returns jsonb
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_nh    int := (p_g ->> 'nh')::int;
  v_nd    int := (p_g ->> 'nd')::int;
  v_np    int := (p_g ->> 'np')::int;
  v_nw    int := (p_g ->> 'nw')::int;
  v_dono  int := (p_g ->> 'dono')::int;
  v_wip   int := (p_g ->> 'wip')::int;
  v_imax  int := (p_g ->> 'imax')::int;
  v_i     int := (p_o ->> 'i')::int;
  v_n     int := coalesce((p_o ->> 'passos')::int, 0);
  v_abre  boolean := not p_reserva and coalesce((p_o ->> 'abre')::boolean, false);
  v_fecha boolean := not p_reserva and coalesce((p_o ->> 'fecha')::boolean, false);
  v_dtm   boolean := not p_reserva and coalesce((p_o ->> 'dt_m')::boolean, false);
  v_dtt   boolean := not p_reserva and coalesce((p_o ->> 'dt_t')::boolean, false);
  v_dm    int := coalesce((p_o ->> 'dm')::int, 0);
  v_dtd   int := coalesce((p_o ->> 'dtd')::int, 0);
  v_pm    int[] := public._agenda_ints(p_o -> 'pm');
  v_pt    int[] := public._agenda_ints(p_o -> 'pt');
  v_fixa  int := coalesce((p_o ->> 'fixa')::int, 0);
  v_bem   int[] := public._agenda_ints(p_o -> 'bem');
  v_loc   int;
  v_uso   int[] := p_uso;
  v_rest  int[] := p_rest;   -- o que ainda cabe até 100% (compromisso + reserva), por pessoa e semana
  v_ap    int[] := '{}';
  v_ah    int[] := '{}';
  v_apr   int[] := '{}';
  v_prev  int[] := '{}';
  v_esc   int[];
  v_cand  int[];
  v_h     int;
  v_d     int;
  v_t     int;
  v_w     int;
  v_dia   int;
  v_prog  int := 0;
  v_trab  boolean := true;
  v_k     int := 0;
  v_ini   int;
  v_ult   int;
  v_fim   int;
  v_int   int := 0;
  v_md    int := 0;
  v_mesmo boolean := false;
  v_ok    boolean;
  v_role  int;
  v_need  int;
  v_nf    int;
  v_self  boolean;
  v_mh    boolean;
  v_cel   int;
  x       int;
  s       int;
  q       int;
  -- FASE 7: (7a P5) o teto da equipe-semana (teq, que o encaixe só manda no compromisso) e a soma da equipe (sem o dono) em
  -- cada semana, que anda com os diaristas postos no bloco
  v_teq   int[] := case when p_g ? 'teq' and not p_reserva then public._agenda_ints(p_g -> 'teq') end;
  v_equ   int[];
  -- FASE 7: fim
  -- FASE 7b: (7b P4, §5.3) as pessoas de cada passo (dk; o dono no turno só desconta quando conta como uma delas: dk_dono_conta), o
  -- sábado (os índices dos sábados: só na tentativa com ele), quem nunca fica sozinho (novato) e o dono técnico (dono_tec)
  v_dk    int[] := case when p_o ? 'dk' then public._agenda_ints(p_o -> 'dk') end;
  v_dkc   boolean := coalesce((p_o ->> 'dk_dono_conta')::boolean, true);
  v_sab   int[] := case when p_g ? 'sab' then public._agenda_ints(p_g -> 'sab') end;
  v_nov   int[] := case when p_g ? 'novato' then public._agenda_ints(p_g -> 'novato') end;
  v_dtec  boolean := coalesce((p_g ->> 'dono_tec')::boolean, false);
  v_nsab  int := 0;
  v_7b_x  int;
  -- FASE 7b: fim
begin
  if v_n <= 0 or p_d0 is null or p_d0 < 1 or p_d0 > v_nd then return null; end if;
  if not p_util[p_d0] or p_d0 = any (v_bem) then return null; end if;
  v_loc := coalesce(p_loc[v_i], 0);
  v_h := 2 * (p_d0 - 1) + 1;
  v_dia := p_d0;
  -- FASE 7: (7a P5) a soma da equipe na semana, de partida: o uso de compromisso de todos menos o dono (p_uso, o mesmo que o
  -- teto de cada um lê)
  if v_teq is not null then
    v_equ := array_fill(0, array[greatest(v_nw, 1)]);
    for f7_x in 1 .. v_np loop
      continue when f7_x = v_dono;
      for f7_w in 1 .. v_nw loop
        v_equ[f7_w] := v_equ[f7_w] + coalesce(p_uso[(f7_x - 1) * v_nw + f7_w], 0);
      end loop;
    end loop;
  end if;
  -- FASE 7: fim

  while v_k < v_n loop
    if v_h > v_nh then return null; end if;
    v_d := (v_h + 1) / 2;
    if v_d <> v_dia then
      if v_ini is null then return null; end if;                -- o 1º passo tem de sair no dia d0
      -- FASE 7b: (sábado) o sábado sem passo não conta como dia parado
      if v_sab is not null and v_dia = any (v_sab) then
        v_trab := false;
      end if;
      -- FASE 7b: fim
      if v_trab and v_prog = 0 then
        v_int := v_int + 1;
        if v_int > v_imax then return null; end if;
      end if;
      v_dia := v_d;
      v_prog := 0;
      v_trab := p_util[v_d] and not (v_d = any (v_bem));
      -- FASE 7b: (sábado) o sábado da grade é dia de trabalho na tentativa com ele (só a manhã, abaixo)
      if v_sab is not null and v_d = any (v_sab) and not (v_d = any (v_bem)) then
        v_trab := true;
      end if;
      -- FASE 7b: fim
    end if;
    if not v_trab or v_h < p_min_h then
      v_h := v_h + 1;
      continue;
    end if;
    -- FASE 7b: (sábado) só a manhã (a tarde é pulada sem contar) e nunca o 1º passo
    if v_sab is not null and v_d = any (v_sab) and (v_h % 2 = 0 or v_ini is null) then
      v_h := v_h + 1;
      continue;
    end if;
    -- FASE 7b: fim
    v_t := case when v_h % 2 = 1 then 1 else 2 end;
    v_w := p_sem[v_d];

    -- As frentes: a OS já tem um passo nesse meio-dia (no vigente) = não; senão no máximo wip_max OS distintas.
    v_nf := 0;
    v_self := false;
    v_mh := false;
    for s in 1 .. 4 loop
      x := p_fr[(v_h - 1) * 4 + s];
      continue when x = 0;
      if abs(x) = v_i then
        if x > 0 then v_self := true; end if;
      else
        v_nf := v_nf + 1;
        if v_loc > 0 and p_loc[abs(x)] = v_loc then v_mh := true; end if;
      end if;
    end loop;
    v_ok := not v_self and v_nf < v_wip;

    -- O dono: o turno inteiro (sempre, ou nos turnos em que ele está na equipe) ou a abertura do 1º passo.
    v_role := 0;
    if v_ok and ((v_t = 1 and v_dtm) or (v_t = 2 and v_dtt)) then
      v_cel := (v_dono - 1) * v_nh + v_h;
      if v_dono > 0 and p_cap[v_cel] = 1 and p_ocup[v_cel] in (0, -v_i)
         and v_uso[(v_dono - 1) * v_nw + v_w] < p_teto[(v_dono - 1) * v_nw + v_w]
         and v_rest[(v_dono - 1) * v_nw + v_w] > 0 then
        v_role := 1;
      else
        v_ok := false;
      end if;
    elsif v_ok and v_k = 0 and v_abre then
      if v_dono > 0 and (p_curta[v_h] & 1) = 1 then v_role := 2; else v_ok := false; end if;
    end if;

    -- A equipe: quem o dono disse para o turno; quem faltar é trocado por outro diarista livre (quem estava no
    -- meio-dia anterior desta OS, a menor carga na semana, a ordem do nome); abaixo do desejado = lacuna.
    if v_ok then
      v_need := case when v_t = 1 then v_dm else v_dtd end;
      -- FASE 7b: (dk) as pessoas deste passo do molde (k = v_k + 1); o dono no turno desconta 1 quando conta como uma delas (também
      -- na reserva, que guarda só os diaristas: o mesmo que o desejado de antes)
      if v_dk is not null and v_dk[v_k + 1] is not null then
        v_need := greatest(v_dk[v_k + 1] - case when v_dkc and ((v_t = 1 and coalesce((p_o ->> 'dt_m')::boolean, false))
                                                        or (v_t = 2 and coalesce((p_o ->> 'dt_t')::boolean, false))) then 1 else 0 end, 0);
      end if;
      -- FASE 7b: fim
      if v_fixa > 0 and v_fixa <> v_dono then v_need := greatest(v_need, 1); end if;
      if v_need = 0 and v_role <> 1 then v_ok := false; end if;
    end if;
    if v_ok then
      v_esc := '{}';
      if v_fixa > 0 and v_fixa <> v_dono then
        v_cel := (v_fixa - 1) * v_nh + v_h;
        if p_cap[v_cel] = 1 and p_ocup[v_cel] in (0, -v_i)
           and v_uso[(v_fixa - 1) * v_nw + v_w] < p_teto[(v_fixa - 1) * v_nw + v_w]
           and v_rest[(v_fixa - 1) * v_nw + v_w] > 0 then
          v_esc := array[v_fixa];
        else
          v_ok := false;
        end if;
      end if;
    end if;
    if v_ok then
      foreach q in array (case when v_t = 1 then v_pm else v_pt end) loop
        exit when cardinality(v_esc) >= v_need;
        continue when q = v_dono or q = any (v_esc);
        v_cel := (q - 1) * v_nh + v_h;
        if p_cap[v_cel] = 1 and p_ocup[v_cel] in (0, -v_i)
           and v_uso[(q - 1) * v_nw + v_w] < p_teto[(q - 1) * v_nw + v_w]
           and v_rest[(q - 1) * v_nw + v_w] > 0 then
          v_esc := v_esc || q;
        end if;
      end loop;
      if cardinality(v_esc) < v_need then
        select coalesce(array_agg(g.q order by (g.q = any (v_prev)) desc, (v_uso)[(g.q - 1) * v_nw + v_w], g.q), '{}'::int[])
          into v_cand
          from generate_series(1, v_np) g(q)
         where g.q <> v_dono and not (g.q = any (v_esc))
           and (p_cap)[(g.q - 1) * v_nh + v_h] = 1 and (p_ocup)[(g.q - 1) * v_nh + v_h] in (0, -v_i)
           and (v_uso)[(g.q - 1) * v_nw + v_w] < (p_teto)[(g.q - 1) * v_nw + v_w]
           and (v_rest)[(g.q - 1) * v_nw + v_w] > 0;
        -- FASE 7b: (quem nunca fica sozinho) o novato e quem vem sob demanda vão depois dos outros
        if v_nov is not null then
          v_cand := array(select u.c from unnest(v_cand) with ordinality u(c, o) order by u.c = any (v_nov), u.o);
        end if;
        -- FASE 7b: fim
        foreach q in array v_cand loop
          exit when cardinality(v_esc) >= v_need;
          v_esc := v_esc || q;
        end loop;
        -- FASE 7b: (o dono técnico, dono_como_tecnico) o dono entra por último, no lugar do diarista que falta: livre no meio-dia,
        -- abaixo do teto dele e sem estar já no meio-dia (nem no turno nem na abertura); nunca no último passo do serviço que ele fecha
        -- (o fechamento vai nele) nem no serviço "sem você" (dono_nunca). Ele vai como o dono no turno (o papel 1: conta nos turnos do
        -- dono e no teto dele, e fica fora da soma da equipe, como sempre).
        if v_dtec and cardinality(v_esc) = v_need - 1 and v_dono > 0 and v_role = 0 and not (v_dono = any (v_esc))
           and not (v_fecha and v_k + 1 = v_n) and not coalesce((p_o ->> 'dono_nunca')::boolean, false)
           and p_cap[(v_dono - 1) * v_nh + v_h] = 1 and p_ocup[(v_dono - 1) * v_nh + v_h] in (0, -v_i)
           and v_uso[(v_dono - 1) * v_nw + v_w] < p_teto[(v_dono - 1) * v_nw + v_w]
           and v_rest[(v_dono - 1) * v_nw + v_w] > 0 then
          v_role := 1;
          v_need := v_need - 1;
        end if;
        -- FASE 7b: fim
      end if;
      if cardinality(v_esc) < v_need then v_ok := false; end if;
    end if;

    -- FASE 7b: (quem nunca fica sozinho; R4.3(d)) o meio-dia que ficaria só com novatos ou quem vem sob demanda (e sem o dono no
    -- turno) ganha o 1º outro livre (vira dupla); sem ninguém, é lacuna. A equipe dita e a pessoa pedida pelo dono valem como ele disse.
    if v_ok and v_nov is not null and v_fixa = 0 and coalesce(cardinality(v_pm), 0) + coalesce(cardinality(v_pt), 0) = 0
       and v_role <> 1 and cardinality(v_esc) > 0 and not exists (select 1 from unnest(v_esc) e where not (e = any (v_nov))) then
      v_7b_x := null;
      select g.q into v_7b_x
        from generate_series(1, v_np) g(q)
       where g.q <> v_dono and not (g.q = any (v_esc)) and not (g.q = any (v_nov))
         and (p_cap)[(g.q - 1) * v_nh + v_h] = 1 and (p_ocup)[(g.q - 1) * v_nh + v_h] in (0, -v_i)
         and (v_uso)[(g.q - 1) * v_nw + v_w] < (p_teto)[(g.q - 1) * v_nw + v_w]
         and (v_rest)[(g.q - 1) * v_nw + v_w] > 0
       order by (g.q = any (v_prev)) desc, (v_uso)[(g.q - 1) * v_nw + v_w], g.q
       limit 1;
      if v_7b_x is null then
        v_ok := false;
      else
        v_esc := v_esc || v_7b_x;
      end if;
    end if;
    -- FASE 7b: fim
    -- FASE 7: (7a P5) o teto da equipe: os diaristas deste meio-dia só entram se a equipe (sem o dono) fica até o teto dela na
    -- semana — a soma de antes + os escolhidos agora <= teq, o mesmo que exigir, um a um, a soma abaixo do teto (o meio-dia é
    -- tudo ou nada: sem os diaristas que pede, é lacuna). Meio-dia sem diarista (só o dono no turno) não tem o que conferir.
    if v_ok and v_teq is not null and cardinality(v_esc) > 0
       and v_equ[v_w] + cardinality(v_esc) > coalesce(v_teq[v_w], 0) then
      v_ok := false;
    end if;
    -- FASE 7: fim
    if v_ok then
      if v_role = 1 then
        v_ap := v_ap || v_dono; v_ah := v_ah || v_h; v_apr := v_apr || 0;
        v_uso[(v_dono - 1) * v_nw + v_w] := v_uso[(v_dono - 1) * v_nw + v_w] + 1;
        v_rest[(v_dono - 1) * v_nw + v_w] := v_rest[(v_dono - 1) * v_nw + v_w] - 1;
        v_md := v_md + 1;
      elsif v_role = 2 then
        v_ap := v_ap || v_dono; v_ah := v_ah || v_h; v_apr := v_apr || 1;
      end if;
      foreach q in array v_esc loop
        v_ap := v_ap || q; v_ah := v_ah || v_h; v_apr := v_apr || 0;
        v_uso[(q - 1) * v_nw + v_w] := v_uso[(q - 1) * v_nw + v_w] + 1;
        v_rest[(q - 1) * v_nw + v_w] := v_rest[(q - 1) * v_nw + v_w] - 1;
      end loop;
      v_prev := v_esc;
      -- FASE 7: (7a P5) a soma da equipe na semana anda com os diaristas postos neste meio-dia
      if v_teq is not null then
        v_equ[v_w] := v_equ[v_w] + cardinality(v_esc);
      end if;
      -- FASE 7: fim
      if v_mh then v_mesmo := true; end if;
      v_k := v_k + 1;
      -- FASE 7b: (sábado) quantos meios-dias do bloco caem no sábado
      if v_sab is not null and v_d = any (v_sab) then
        v_nsab := v_nsab + 1;
      end if;
      -- FASE 7b: fim
      v_prog := v_prog + 1;
      if v_ini is null then v_ini := v_h; end if;
      v_ult := v_h;
    end if;
    v_h := v_h + 1;
  end loop;

  -- O fechamento do dono: na última ponta do último passo; ocupada, desliza para o próximo meio-dia útil com a ponta
  -- livre (o bloco termina ali).
  v_fim := v_ult;
  if v_fecha then
    if (p_curta[v_ult] & 2) = 2 then
      v_ap := v_ap || v_dono; v_ah := v_ah || v_ult; v_apr := v_apr || 2;
    else
      v_fim := null;
      v_h := v_ult + 1;
      while v_h <= v_nh loop
        v_d := (v_h + 1) / 2;
        if p_util[v_d] and not (v_d = any (v_bem)) and v_h >= p_min_h and (p_curta[v_h] & 2) = 2 then
          v_nf := 0;
          v_self := false;
          for s in 1 .. 4 loop
            x := p_fr[(v_h - 1) * 4 + s];
            continue when x = 0;
            if abs(x) = v_i then
              if x > 0 then v_self := true; end if;
            else
              v_nf := v_nf + 1;
            end if;
          end loop;
          if not v_self and v_nf < v_wip then
            v_ap := v_ap || v_dono; v_ah := v_ah || v_h; v_apr := v_apr || 2;
            v_fim := v_h;
            exit;
          end if;
        end if;
        v_h := v_h + 1;
      end loop;
      if v_fim is null then return null; end if;
    end if;
  end if;

  -- FASE 7b: (sábado) na tentativa com o sábado, a mesma saída mais sab (quantos meios-dias caíram nele)
  if v_sab is not null then
    return jsonb_build_object('d0', p_d0, 'ini', v_ini, 'fim', v_fim, 'int', v_int, 'md', v_md, 'mesmo', v_mesmo,
                              'p', to_jsonb(v_ap), 'h', to_jsonb(v_ah), 'pr', to_jsonb(v_apr), 'sab', v_nsab);
  end if;
  -- FASE 7b: fim
  return jsonb_build_object('d0', p_d0, 'ini', v_ini, 'fim', v_fim, 'int', v_int, 'md', v_md, 'mesmo', v_mesmo,
                            'p', to_jsonb(v_ap), 'h', to_jsonb(v_ah), 'pr', to_jsonb(v_apr));
end;
$function$;

comment on function public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer) is
  'Agenda de Produção (Fase 2, P2): tenta encaixar a OS p_o (i, passos, abre, fecha, dt_m/dt_t = o dono o turno inteiro, dm/dtd = diaristas desejados, pm/pt = os ditos por turno, fixa = a pessoa pedida, bem = dias com o bem fora) começando no dia p_d0. O bloco começa no 1º meio-dia de d0 em que o 1º passo sai inteiro; cada passo pede: no máximo wip_max OS no meio-dia (contando a própria), o dono conforme o molde (turno livre e abaixo do teto, ou a ponta da abertura no 1º), e os diaristas desejados (os ditos, senão trocados por quem estava no meio-dia anterior, a menor carga, o nome) livres, abaixo do teto (p_teto × p_uso) e com lugar na semana inteira (p_rest = 100% − compromisso − reserva); meio-dia sem o desejado = lacuna; dia útil inteiro sem passo depois de começar = interrupção (mais que interrupcoes_max = inválido); dia não útil e bem fora são pulados. O fechamento vai na última ponta ou desliza para a próxima ponta livre. Reserva (p_reserva) = só diaristas, sem o dono. Devolve {d0, ini, fim, int, md (turnos do dono), mesmo (local), p[], h[], pr[] (0 turno, 1 abertura, 2 fechamento)} ou null. FASE 7 (7a P5): com o teto da equipe em p_g (teq, que o encaixe só manda no compromisso da OS sem o teto de 100%) e fora da reserva, os diaristas de cada meio-dia só entram se a soma da equipe na semana (o uso de compromisso de todos menos o dono, o de partida e o já posto no bloco) mais eles fica até teq[semana]; senão o meio-dia é lacuna. Sem teq, o de antes. FASE 7b (P4, §5.3, R4.3(d)/(e)): dk (p_o) = as pessoas de cada passo do molde — o passo k pede dk[k], menos 1 quando o dono está no turno e conta como uma delas (dk_dono_conta; também na reserva, como o desejado de antes); sab (p_g, só na tentativa com o sábado) = o sábado é dia de trabalho só de manhã (a tarde é pulada sem contar), nunca o 1º passo e sem contar como dia parado, e o bloco devolve sab = quantos meios-dias caíram nele; novato (p_g) = quem nunca fica sozinho vai depois dos outros na escolha, e o meio-dia que ficaria só com eles (sem o dono no turno) ganha o 1º outro livre ou é lacuna (a equipe dita e a pessoa pedida valem como o dono disse); dono_tec (p_g) = o dono entra por último, livre no meio-dia, abaixo do teto dele e sem estar já nele. Sem essas chaves, o de antes, byte a byte.';

-- _agenda_melhor (de 20261025100200_agenda_fase2_motor.sql)
create or replace function public._agenda_melhor(p_a jsonb, p_b jsonb)
 returns boolean
 language sql
 immutable
 set search_path to 'public'
as $function$
  select row((p_a ->> 'fim')::int, (p_a ->> 'md')::int, (p_a ->> 'int')::int, not (p_a ->> 'mesmo')::boolean, (p_a ->> 'd0')::int)
       < row((p_b ->> 'fim')::int, (p_b ->> 'md')::int, (p_b ->> 'int')::int, not (p_b ->> 'mesmo')::boolean, (p_b ->> 'd0')::int);
  -- FASE 7b: (7b P4, §5.3) a ordem com o sábado: (fim, meios-dias no sábado, turnos do dono, interrupções, mesmo local, d0) — a
  -- função devolve o último select; sem sab nos dois blocos (0 = 0), a mesma ordem de antes.
  select row((p_a ->> 'fim')::int, coalesce((p_a ->> 'sab')::int, 0), (p_a ->> 'md')::int, (p_a ->> 'int')::int,
             not (p_a ->> 'mesmo')::boolean, (p_a ->> 'd0')::int)
       < row((p_b ->> 'fim')::int, coalesce((p_b ->> 'sab')::int, 0), (p_b ->> 'md')::int, (p_b ->> 'int')::int,
             not (p_b ->> 'mesmo')::boolean, (p_b ->> 'd0')::int);
  -- FASE 7b: fim
$function$;

comment on function public._agenda_melhor(jsonb, jsonb) is
  'Agenda de Produção (Fase 2, P2): o bloco p_a é melhor que p_b por (fim, meios-dias de turno do dono, interrupções, mesmo local primeiro, d0) — termina mais cedo primeiro. FASE 7b (P4, §5.3): row(fim, coalesce(sab, 0), md, int, not mesmo, d0) — o bloco que usa menos manhãs de sábado vence no mesmo fim; sem sab, a ordem de antes.';

-- _agenda_encaixar (de 20261031100400_agenda_fase7a_teto.sql)
create or replace function public._agenda_encaixar(p_ctx jsonb, p_fila jsonb, p_par jsonb)
 returns jsonb
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_nd     int := (p_ctx ->> 'nd')::int;
  v_dono   int := (p_ctx ->> 'dono')::int;
  v_util   boolean[] := public._agenda_bools(p_ctx -> 'util');
  v_sem    int[] := public._agenda_ints(p_ctx -> 'sem');
  v_cap    int[] := public._agenda_ints(p_ctx -> 'cap');
  v_curta  int[] := public._agenda_ints(p_ctx -> 'curta');
  v_ocup   int[] := public._agenda_ints(p_ctx -> 'ocup');
  v_fr     int[] := public._agenda_ints(p_ctx -> 'fr');
  v_t80    int[] := public._agenda_ints(p_ctx -> 'teto80');
  v_t100   int[] := public._agenda_ints(p_ctx -> 'teto100');
  v_uc     int[] := public._agenda_ints(p_ctx -> 'uso_c');
  v_ur     int[] := public._agenda_ints(p_ctx -> 'uso_r');
  v_loc    int[] := public._agenda_ints(p_ctx -> 'loc');
  v_g      jsonb := jsonb_build_object('nh', p_ctx -> 'nh', 'nd', p_ctx -> 'nd', 'np', p_ctx -> 'np', 'nw', p_ctx -> 'nw',
                                       'dono', p_ctx -> 'dono', 'wip', p_par -> 'wip', 'imax', p_par -> 'imax');
  v_inicios int := (p_par ->> 'inicios')::int;
  v_semana boolean := coalesce((p_par ->> 'semana')::boolean, false);
  v_jde    int := coalesce((p_par ->> 'jan_de')::int, 1);
  v_jate   int := coalesce((p_par ->> 'jan_ate')::int, (p_ctx ->> 'nd')::int);
  v_acima  boolean := coalesce((p_par ->> 'acima')::boolean, false);
  v_col    jsonb := '[]'::jsonb;
  v_fora   jsonb := '[]'::jsonb;
  v_pend   jsonb := '[]'::jsonb;
  o        jsonb;
  b        jsonb;
  v_best   jsonb;
  v_teto   int[];
  v_tot    int[];
  v_rest   int[];
  v_i      int;
  v_fixar  boolean;
  v_ini    int;
  v_janela boolean;
  -- CORREÇÃO 29/10 (P3): a pessoa × semana de cada meio-dia da reserva da própria OS (res_propria)
  v_k      int;
  -- CORREÇÃO 29/10 (P3): fim
  -- FASE 7b: (7b P4) o bloco de 1 pessoa da dupla inferida e o sábado de manhã
  v_7b_sab   int[] := public._agenda_ints(p_ctx -> 'sab');
  v_7b_bon   int[] := public._agenda_ints(p_ctx -> 'sab_bonus');
  v_7b_o1    jsonb;
  v_7b_b1    jsonb;
  v_7b_b2    jsonb;
  v_7b_ok    boolean;
  v_7b_hs    int[];
  v_7b_tb    int[];
  v_7b_rb    int[];
  v_7b_gs    jsonb;
  v_7b_teste jsonb := '[]'::jsonb;
  -- FASE 7b: fim
begin
  if v_inicios is null or p_par -> 'wip' is null or p_par -> 'imax' is null then
    raise exception 'agenda: faltam os parâmetros do encaixe (inícios, frentes, interrupções)' using errcode = '22023';
  end if;
  -- FASE 7b: (7b P4) quem nunca fica sozinho e o dono técnico valem em todo bloco (do contexto, que só os põe com os modos da 7b)
  if p_ctx ? 'novato' then
    v_g := v_g || jsonb_build_object('novato', p_ctx -> 'novato');
  end if;
  if p_ctx ? 'dono_tec' then
    v_g := v_g || jsonb_build_object('dono_tec', p_ctx -> 'dono_tec');
  end if;
  -- FASE 7b: fim

  -- 1. Compromisso, uma OS por vez, consumindo a grade.
  for o in select e from jsonb_array_elements(coalesce(p_fila, '[]'::jsonb)) e
            where (e ->> 'classe')::int in (1, 2) and not coalesce((e ->> 'tirar')::boolean, false)
            order by (e ->> 'ordem')::int, e ->> 'os'
  loop
    v_i := (o ->> 'i')::int;
    v_fixar := o ? 'fixar_de';
    continue when coalesce((o ->> 'passos')::int, 0) <= 0;
    if coalesce((o ->> 'dono_impossivel')::boolean, false) then
      v_fora := v_fora || jsonb_build_object('i', v_i, 'motivo', 'padrao_do_dono');
      continue;
    end if;
    v_teto := case when v_acima or coalesce((o ->> 'teto100')::boolean, false) then v_t100 else v_t80 end;
    v_rest := array(select t.x1 - t.x2 - t.x3 from unnest(v_t100, v_uc, v_ur) as t(x1, x2, x3));
    -- CORREÇÃO 29/10 (P3): a reserva desta mesma OS não conta contra ela. res_propria (da agenda_propor) é a pessoa × semana
    -- de cada meio-dia reservado dela: o lugar até 100% devolve esses meios-dias (o compromisso já podia usar a célula da
    -- própria reserva, ocup = −i; faltava a conta da semana). A reserva das OUTRAS continua contando. As próximas da fila
    -- continuam vendo a reserva (uso_r não muda aqui): quem a tira é a aplicação, que a cancela como promovida — o motor não
    -- presume a promoção antes de ela sair (a OS pode ficar esperando a decisão do dono, e a reserva fica).
    foreach v_k in array public._agenda_ints(o -> 'res_propria') loop
      v_rest[v_k] := v_rest[v_k] + 1;
    end loop;
    -- CORREÇÃO 29/10 (P3): fim
    -- FASE 7: (7a P5) o teto da equipe-semana (spec-fase7a §5.5): com teto_equipe no contexto (a regra teto_equipe do
    -- gestor, em _agenda_contexto), o compromisso da OS que não usa o teto de 100% (acima_da_carga, o pedido do dono) leva o
    -- teto da equipe ao bloco (teq): cada diarista posto num meio-dia exige a equipe (sem o dono) até o teto dela na semana.
    -- Sem teto_equipe, o v_g de sempre (tirar uma chave que não está lá não muda nada).
    if p_ctx ? 'teto_equipe' and not (v_acima or coalesce((o ->> 'teto100')::boolean, false)) then
      v_g := v_g || jsonb_build_object('teq', p_ctx -> 'teto_equipe');
    else
      v_g := v_g - 'teq';
    end if;
    -- FASE 7: fim
    v_best := public._agenda_melhor_bloco(v_g, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_teto, v_uc, v_rest, v_loc, o,
                case when v_fixar then (o ->> 'fixar_de')::int else (o ->> 'est')::int end,
                case when v_fixar then (o ->> 'fixar_ate')::int else v_nd end, v_inicios, false);
    -- FASE 7b: (só fora do pedido do dono: o dia dele vale como ele disse)
    if not v_fixar then
    -- FASE 7b: fim
    -- FASE 7b: (7b P4, R4.3(a)) a dupla inferida pela tarefa (fonte regra) nunca segura a OS: sem o bloco da dupla, com ele
    -- terminando mais de dupla_espera dias úteis depois do de 1 pessoa (em teste: depois dele), ou passando do prazo firme que o de
    -- 1 pessoa cumpre, vale o bloco de 1 pessoa em todos os meios-dias (passos1: o meio-dia que seria em dupla vai com 1 e rende 1),
    -- com dupla_falta = os meios-dias que pediam 2 ([{h, onde}]: os primeiros e os últimos de turno do bloco, ou todos). A dita pelo
    -- dono nunca cai aqui (espera a 2ª pessoa: a classe).
    if o ? 'dk' and o ->> 'dupla_fonte' = 'regra' and coalesce((o ->> 'passos1')::int, 0) > 0 then
      v_7b_o1 := (o - 'dk') || jsonb_build_object('passos', o -> 'passos1');
      v_7b_b1 := public._agenda_melhor_bloco(v_g, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_teto, v_uc, v_rest, v_loc, v_7b_o1,
                  case when v_fixar then (o ->> 'fixar_de')::int else (o ->> 'est')::int end,
                  case when v_fixar then (o ->> 'fixar_ate')::int else v_nd end, v_inicios, false);
      if v_7b_b1 is not null and (v_best is null
           or (p_par ->> 'dupla_modo' = 'sombra' and (v_best ->> 'fim')::int > (v_7b_b1 ->> 'fim')::int)
           or (p_par ->> 'dupla_modo' = 'ligado'
               and (select count(*) from generate_series(((v_7b_b1 ->> 'fim')::int + 1) / 2 + 1, ((v_best ->> 'fim')::int + 1) / 2) g
                     where v_util[g]) > coalesce((p_par ->> 'dupla_espera')::int, 0))
           or (o ? 'prazo_h' and (v_best ->> 'fim')::int > (o ->> 'prazo_h')::int
               and (v_7b_b1 ->> 'fim')::int <= (o ->> 'prazo_h')::int)) then
        v_7b_hs := array(select distinct x.h from unnest(public._agenda_ints(v_7b_b1 -> 'h'), public._agenda_ints(v_7b_b1 -> 'pr')) x(h, pr)
                          where x.pr = 0 order by x.h);
        v_best := v_7b_b1 || jsonb_build_object('um', true, 'dupla_falta', coalesce((
          select jsonb_agg(jsonb_build_object('h', v_7b_hs[k], 'onde', case when coalesce((o ->> 'dupla_todos')::boolean, false) then 'todos'
                                                                          when k <= coalesce((o ->> 'dupla_ni')::int, 0) then 'inicio'
                                                                          else 'fim' end) order by k)
            from generate_series(1, cardinality(v_7b_hs)) k
           where coalesce((o ->> 'dupla_todos')::boolean, false) or k <= coalesce((o ->> 'dupla_ni')::int, 0)
              or k > cardinality(v_7b_hs) - coalesce((o ->> 'dupla_nf')::int, 0)), '[]'::jsonb));
      end if;
    end if;
    -- FASE 7b: fim
    -- FASE 7b: (7b P4, §5.3, AG7-08) o sábado de manhã (modo_sabado fora de desligado, sabado_manha diferente de nunca): só de quem se
    -- ofereceu (a manhã livre na grade), nunca o 1º passo, nunca à tarde; so_prazo = só quando sem ele a OS passa do prazo firme e
    -- com ele cumpre; oferecido = quando ele termina antes. O teto de quem se ofereceu (e o da equipe, quando há) ganha as manhãs dele
    -- só nesta tentativa. Ligado: vale o bloco com o sábado (sabado true); em teste: fica o de sem sábado e o com sábado vai em
    -- sab_teste (a linha "Em teste"). As reservas nunca usam o sábado.
    if coalesce(p_par ->> 'sab_modo', 'desligado') <> 'desligado' and coalesce(p_par ->> 'sab_politica', 'nunca') <> 'nunca'
       and cardinality(v_7b_sab) > 0
       and (p_par ->> 'sab_politica' = 'oferecido'
            or (o ? 'prazo_h' and (v_best is null or (v_best ->> 'fim')::int > (o ->> 'prazo_h')::int))) then
      v_7b_tb := array(select t.x1 + coalesce(t.x2, 0) from unnest(v_teto, v_7b_bon) as t(x1, x2));
      v_7b_rb := array(select t.x1 + coalesce(t.x2, 0) from unnest(v_rest, v_7b_bon) as t(x1, x2));
      v_7b_gs := v_g || jsonb_build_object('sab', p_ctx -> 'sab');
      if v_7b_gs ? 'teq' then
        v_7b_gs := v_7b_gs || jsonb_build_object('teq', to_jsonb(array(
          select t.x + coalesce((select sum(v_7b_bon[(pp - 1) * (p_ctx ->> 'nw')::int + t.w]) from generate_series(1, (p_ctx ->> 'np')::int) pp
                                  where pp <> v_dono), 0)
            from unnest(public._agenda_ints(v_7b_gs -> 'teq')) with ordinality t(x, w) order by t.w)));
      end if;
      v_7b_b2 := public._agenda_melhor_bloco(v_7b_gs, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_7b_tb, v_uc, v_7b_rb, v_loc,
                   case when v_best ? 'um' then v_7b_o1 else o end, (o ->> 'est')::int, v_nd, v_inicios, false);
      v_7b_ok := v_7b_b2 is not null and coalesce((v_7b_b2 ->> 'sab')::int, 0) > 0
                 and case when p_par ->> 'sab_politica' = 'so_prazo' then (v_7b_b2 ->> 'fim')::int <= (o ->> 'prazo_h')::int
                          else v_best is null or public._agenda_melhor(v_7b_b2, v_best) end;
      if v_7b_ok then
        if p_par ->> 'sab_modo' = 'ligado' then
          -- (o bloco de 1 pessoa com o sábado: os meios-dias que pediam 2 são os deste bloco)
          if v_best ? 'um' then
            v_7b_hs := array(select distinct x.h from unnest(public._agenda_ints(v_7b_b2 -> 'h'), public._agenda_ints(v_7b_b2 -> 'pr')) x(h, pr)
                              where x.pr = 0 order by x.h);
            v_7b_b2 := v_7b_b2 || jsonb_build_object('um', true, 'dupla_falta', coalesce((
              select jsonb_agg(jsonb_build_object('h', v_7b_hs[k], 'onde', case when coalesce((o ->> 'dupla_todos')::boolean, false) then 'todos'
                                                                              when k <= coalesce((o ->> 'dupla_ni')::int, 0) then 'inicio'
                                                                              else 'fim' end) order by k)
                from generate_series(1, cardinality(v_7b_hs)) k
               where coalesce((o ->> 'dupla_todos')::boolean, false) or k <= coalesce((o ->> 'dupla_ni')::int, 0)
                  or k > cardinality(v_7b_hs) - coalesce((o ->> 'dupla_nf')::int, 0)), '[]'::jsonb));
          end if;
          v_best := v_7b_b2 || jsonb_build_object('sabado', true);
        else
          v_7b_teste := v_7b_teste || jsonb_build_object('i', v_i, 'b', v_7b_b2, 'prazo_h', o -> 'prazo_h');
        end if;
      end if;
    end if;
    -- (o fim do "fora do pedido do dono")
    end if;
    -- FASE 7b: fim
    if v_best is null then
      v_fora := v_fora || jsonb_build_object('i', v_i, 'motivo', case when v_fixar then 'fixar_nao_cabe' else 'sem_encaixe' end);
      if (o ->> 'classe')::int = 2 and not v_fixar and not coalesce((o ->> 'tem_reserva')::boolean, false) then
        v_pend := v_pend || o;
      end if;
      continue;
    end if;
    select x.p_ocup, x.p_curta, x.p_fr, x.p_uc, x.p_ur into v_ocup, v_curta, v_fr, v_uc, v_ur
      from public._agenda_ocupar(v_g, v_sem, v_best, v_i, false, v_ocup, v_curta, v_fr, v_uc, v_ur) x;
    v_ini := ((v_best ->> 'ini')::int + 1) / 2;
    -- (o evento real e o pedido do dono valem onde caírem, também antes da semana: é hoje ou amanhã)
    v_janela := not v_semana or v_ini between v_jde and v_jate
                or coalesce((o ->> 'evento_real')::boolean, false) or v_fixar;
    v_col := v_col || (v_best || jsonb_build_object('i', v_i, 'tipo', 'compromisso', 'na_janela', v_janela));
    if v_semana and v_ini > v_jate and (o ->> 'classe')::int = 2 and not v_fixar
       and not coalesce((o ->> 'tem_reserva')::boolean, false) then
      v_pend := v_pend || o;
    end if;
  end loop;

  -- FASE 7: (7a P5) as reservas não levam o teto da equipe (são até 100% de cada um, sem a carga)
  v_g := v_g - 'teq';
  -- FASE 7: fim
  -- 2a. Reserva por teto: a OS pronta que não coube nesta janela com 80% cabe com 100%? A equipe guarda o lugar.
  for o in select e from jsonb_array_elements(v_pend) e loop
    v_i := (o ->> 'i')::int;
    v_tot := array(select t.x1 + t.x2 from unnest(v_uc, v_ur) as t(x1, x2));
    v_rest := array(select t.x1 - t.x2 from unnest(v_t100, v_tot) as t(x1, x2));
    v_best := public._agenda_melhor_bloco(v_g, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_t100, v_tot, v_rest, v_loc, o,
                greatest((o ->> 'est')::int, case when v_semana then v_jde else 1 end),
                case when v_semana then v_jate else v_nd end, v_inicios, false);
    -- FASE 7b: (7b P4, R4.3(a)) a dupla inferida pela tarefa (fonte regra) nunca segura a OS: sem o bloco da dupla, com ele
    -- terminando mais de dupla_espera dias úteis depois do de 1 pessoa (em teste: depois dele), ou passando do prazo firme que o de
    -- 1 pessoa cumpre, vale o bloco de 1 pessoa em todos os meios-dias (passos1: o meio-dia que seria em dupla vai com 1 e rende 1),
    -- com dupla_falta = os meios-dias que pediam 2 ([{h, onde}]: os primeiros e os últimos de turno do bloco, ou todos). A dita pelo
    -- dono nunca cai aqui (espera a 2ª pessoa: a classe).
    if o ? 'dk' and o ->> 'dupla_fonte' = 'regra' and coalesce((o ->> 'passos1')::int, 0) > 0 then
      v_7b_o1 := (o - 'dk') || jsonb_build_object('passos', o -> 'passos1');
      v_7b_b1 := public._agenda_melhor_bloco(v_g, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_t100, v_tot, v_rest, v_loc, v_7b_o1,
                  greatest((o ->> 'est')::int, case when v_semana then v_jde else 1 end),
                  case when v_semana then v_jate else v_nd end, v_inicios, false);
      if v_7b_b1 is not null and (v_best is null
           or (p_par ->> 'dupla_modo' = 'sombra' and (v_best ->> 'fim')::int > (v_7b_b1 ->> 'fim')::int)
           or (p_par ->> 'dupla_modo' = 'ligado'
               and (select count(*) from generate_series(((v_7b_b1 ->> 'fim')::int + 1) / 2 + 1, ((v_best ->> 'fim')::int + 1) / 2) g
                     where v_util[g]) > coalesce((p_par ->> 'dupla_espera')::int, 0))
           or (o ? 'prazo_h' and (v_best ->> 'fim')::int > (o ->> 'prazo_h')::int
               and (v_7b_b1 ->> 'fim')::int <= (o ->> 'prazo_h')::int)) then
        v_7b_hs := array(select distinct x.h from unnest(public._agenda_ints(v_7b_b1 -> 'h'), public._agenda_ints(v_7b_b1 -> 'pr')) x(h, pr)
                          where x.pr = 0 order by x.h);
        v_best := v_7b_b1 || jsonb_build_object('um', true, 'dupla_falta', coalesce((
          select jsonb_agg(jsonb_build_object('h', v_7b_hs[k], 'onde', case when coalesce((o ->> 'dupla_todos')::boolean, false) then 'todos'
                                                                          when k <= coalesce((o ->> 'dupla_ni')::int, 0) then 'inicio'
                                                                          else 'fim' end) order by k)
            from generate_series(1, cardinality(v_7b_hs)) k
           where coalesce((o ->> 'dupla_todos')::boolean, false) or k <= coalesce((o ->> 'dupla_ni')::int, 0)
              or k > cardinality(v_7b_hs) - coalesce((o ->> 'dupla_nf')::int, 0)), '[]'::jsonb));
      end if;
    end if;
    -- FASE 7b: fim
    b := case when v_best is null then null else public._agenda_so_diaristas(v_best, v_dono) end;
    continue when b is null;
    select x.p_ocup, x.p_curta, x.p_fr, x.p_uc, x.p_ur into v_ocup, v_curta, v_fr, v_uc, v_ur
      from public._agenda_ocupar(v_g, v_sem, b, v_i, true, v_ocup, v_curta, v_fr, v_uc, v_ur) x;
    v_col := v_col || (b || jsonb_build_object('i', v_i, 'tipo', 'reserva', 'reserva_de', 'teto', 'na_janela', true));
  end loop;

  -- 2b. Reserva condicionada: a classe 3 no 1º encaixe depois do dia em que estaria pronta com a condição cumprida.
  for o in select e from jsonb_array_elements(coalesce(p_fila, '[]'::jsonb)) e
            where (e ->> 'classe')::int = 3 and not coalesce((e ->> 'tirar')::boolean, false)
              and not coalesce((e ->> 'tem_reserva')::boolean, false) and coalesce((e ->> 'passos')::int, 0) > 0
            order by (e ->> 'ordem')::int, e ->> 'os'
  loop
    v_i := (o ->> 'i')::int;
    -- o serviço que é só com o dono (nenhum diarista) não tem o que reservar: a equipe não guarda lugar para ele
    if coalesce((o ->> 'dm')::int, 0) = 0 and coalesce((o ->> 'dtd')::int, 0) = 0 then
      v_fora := v_fora || jsonb_build_object('i', v_i, 'motivo', 'so_com_voce');
      continue;
    end if;
    v_tot := array(select t.x1 + t.x2 from unnest(v_uc, v_ur) as t(x1, x2));
    v_rest := array(select t.x1 - t.x2 from unnest(v_t100, v_tot) as t(x1, x2));
    v_best := public._agenda_melhor_bloco(v_g, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_t100, v_tot, v_rest, v_loc, o,
                greatest((o ->> 'est_cond')::int, case when v_semana then v_jde else 1 end),
                case when v_semana then v_jate else v_nd end, v_inicios, true);
    -- FASE 7b: (7b P4, R4.3(a)) a dupla inferida pela tarefa (fonte regra) nunca segura a OS: sem o bloco da dupla, com ele
    -- terminando mais de dupla_espera dias úteis depois do de 1 pessoa (em teste: depois dele), ou passando do prazo firme que o de
    -- 1 pessoa cumpre, vale o bloco de 1 pessoa em todos os meios-dias (passos1: o meio-dia que seria em dupla vai com 1 e rende 1),
    -- com dupla_falta = os meios-dias que pediam 2 ([{h, onde}]: os primeiros e os últimos de turno do bloco, ou todos). A dita pelo
    -- dono nunca cai aqui (espera a 2ª pessoa: a classe).
    if o ? 'dk' and o ->> 'dupla_fonte' = 'regra' and coalesce((o ->> 'passos1')::int, 0) > 0 then
      v_7b_o1 := (o - 'dk') || jsonb_build_object('passos', o -> 'passos1');
      v_7b_b1 := public._agenda_melhor_bloco(v_g, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_t100, v_tot, v_rest, v_loc, v_7b_o1,
                  greatest((o ->> 'est_cond')::int, case when v_semana then v_jde else 1 end),
                  case when v_semana then v_jate else v_nd end, v_inicios, true);
      if v_7b_b1 is not null and (v_best is null
           or (p_par ->> 'dupla_modo' = 'sombra' and (v_best ->> 'fim')::int > (v_7b_b1 ->> 'fim')::int)
           or (p_par ->> 'dupla_modo' = 'ligado'
               and (select count(*) from generate_series(((v_7b_b1 ->> 'fim')::int + 1) / 2 + 1, ((v_best ->> 'fim')::int + 1) / 2) g
                     where v_util[g]) > coalesce((p_par ->> 'dupla_espera')::int, 0))
           or (o ? 'prazo_h' and (v_best ->> 'fim')::int > (o ->> 'prazo_h')::int
               and (v_7b_b1 ->> 'fim')::int <= (o ->> 'prazo_h')::int)) then
        v_7b_hs := array(select distinct x.h from unnest(public._agenda_ints(v_7b_b1 -> 'h'), public._agenda_ints(v_7b_b1 -> 'pr')) x(h, pr)
                          where x.pr = 0 order by x.h);
        v_best := v_7b_b1 || jsonb_build_object('um', true, 'dupla_falta', coalesce((
          select jsonb_agg(jsonb_build_object('h', v_7b_hs[k], 'onde', case when coalesce((o ->> 'dupla_todos')::boolean, false) then 'todos'
                                                                          when k <= coalesce((o ->> 'dupla_ni')::int, 0) then 'inicio'
                                                                          else 'fim' end) order by k)
            from generate_series(1, cardinality(v_7b_hs)) k
           where coalesce((o ->> 'dupla_todos')::boolean, false) or k <= coalesce((o ->> 'dupla_ni')::int, 0)
              or k > cardinality(v_7b_hs) - coalesce((o ->> 'dupla_nf')::int, 0)), '[]'::jsonb));
      end if;
    end if;
    -- FASE 7b: fim
    if v_best is null then
      v_fora := v_fora || jsonb_build_object('i', v_i, 'motivo', 'sem_reserva');
      continue;
    end if;
    select x.p_ocup, x.p_curta, x.p_fr, x.p_uc, x.p_ur into v_ocup, v_curta, v_fr, v_uc, v_ur
      from public._agenda_ocupar(v_g, v_sem, v_best, v_i, true, v_ocup, v_curta, v_fr, v_uc, v_ur) x;
    v_col := v_col || (v_best || jsonb_build_object('i', v_i, 'tipo', 'reserva', 'reserva_de', 'condicionada', 'na_janela', true));
  end loop;

  -- 2c. Reserva no pátio: o que dá para adiantar sem o bem, nos dias em que ele está fora, só a equipe.
  for o in select e from jsonb_array_elements(coalesce(p_fila, '[]'::jsonb)) e
            where coalesce((e ->> 'patio_passos')::int, 0) > 0 and not coalesce((e ->> 'tirar')::boolean, false)
            order by (e ->> 'ordem')::int, e ->> 'os'
  loop
    v_i := (o ->> 'i')::int;
    v_tot := array(select t.x1 + t.x2 from unnest(v_uc, v_ur) as t(x1, x2));
    v_rest := array(select t.x1 - t.x2 from unnest(v_t100, v_tot) as t(x1, x2));
    -- FASE 7b: (7b P4) no pátio, sem a dupla por meio-dia: os passos do pátio não são os do molde (o que dá para adiantar sem o bem)
    o := o - 'dk';
    -- FASE 7b: fim
    v_best := public._agenda_melhor_bloco(v_g, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_t100, v_tot, v_rest, v_loc,
                o || jsonb_build_object('passos', o -> 'patio_passos', 'bem', o -> 'patio_bem', 'abre', false, 'fecha', false),
                greatest((o ->> 'est_patio')::int, case when v_semana then v_jde else 1 end),
                case when v_semana then v_jate else v_nd end, v_inicios, true);
    continue when v_best is null;
    select x.p_ocup, x.p_curta, x.p_fr, x.p_uc, x.p_ur into v_ocup, v_curta, v_fr, v_uc, v_ur
      from public._agenda_ocupar(v_g, v_sem, v_best, v_i, true, v_ocup, v_curta, v_fr, v_uc, v_ur) x;
    v_col := v_col || (v_best || jsonb_build_object('i', v_i, 'tipo', 'reserva', 'reserva_de', 'patio', 'na_janela', true));
  end loop;

  -- FASE 7b: (7b P4) o sábado em teste (a linha "Em teste" do resumo da proposta)
  if jsonb_array_length(v_7b_teste) > 0 then
    return jsonb_build_object('colocadas', v_col, 'fora', v_fora, 'sab_teste', v_7b_teste);
  end if;
  -- FASE 7b: fim
  return jsonb_build_object('colocadas', v_col, 'fora', v_fora);
end;
$function$;

comment on function public._agenda_encaixar(jsonb, jsonb, jsonb) is
  'Agenda de Produção (Fase 2, P2): o guloso serial sobre a grade do contexto. 1) compromisso: classes 1 e 2 na ordem (ordem), cada uma no melhor início (_agenda_melhor_bloco) a partir do est (ou dentro de fixar_de..fixar_ate), com o teto de 80% (100% com acima_da_carga ou pedido do dono), gravando na grade; sem encaixe = fora (sem_encaixe, fixar_nao_cabe, padrao_do_dono). 2) reservas até 100%: teto (classe 2 que não coube na janela), condicionada (classe 3, a partir do est_cond) e pátio (patio_passos nos dias com o bem fora). Na semana (semana = true) só conta o que começa entre jan_de e jan_ate (na_janela). Devolve {colocadas[{i, tipo, reserva_de, d0, ini, fim, int, md, mesmo, p, h, pr, na_janela}], fora[{i, motivo}]}. CORREÇÃO 29/10 (P3): no compromisso, a OS com res_propria (a pessoa × semana de cada meio-dia da reserva DELA, da agenda_propor) tem esses meios-dias devolvidos ao lugar até 100% (teto100 − compromisso − reserva): a reserva dela não conta contra ela, e a promoção cabe. A reserva das outras continua contando; a grade das próximas da fila continua com a reserva (quem a tira é a aplicação). Sem res_propria, o de antes. FASE 7 (7a P5): com teto_equipe no contexto (a regra teto_equipe do gestor), o compromisso da OS que não usa o teto de 100% (acima_da_carga, o pedido do dono) leva o teto da equipe ao bloco (teq: a equipe, sem o dono, até o teto dela na semana; o teto de cada pessoa já vem a 100% do contexto). As reservas não levam. Sem teto_equipe, o de antes. FASE 7b (P4, R4.3(a), §5.3): quem nunca fica sozinho (novato) e o dono técnico (dono_tec) do contexto vão a todo bloco. A dupla inferida (dupla_fonte regra, com passos1), no compromisso e nas reservas por teto e condicionada: sem o bloco da dupla (dk), ou com ele terminando mais de dupla_espera dias úteis depois do bloco de 1 pessoa (em teste, depois dele), ou passando do prazo firme (prazo_h) que o de 1 pessoa cumpre, vale o bloco de 1 pessoa (sem o dk, passos1 passos) com um = true e dupla_falta [{h, onde}] (os primeiros dupla_ni e os últimos dupla_nf meios-dias de turno, ou todos) — a dupla inferida nunca segura nem tira a OS. O pátio, sem dk. O sábado de manhã (sab_modo e sab_politica em p_par; sab e sab_bonus no contexto), só no compromisso fora do pedido do dono: so_prazo = com prazo_h e o melhor bloco terminando depois dele (ou nenhum), a tentativa com o sábado (o teto de quem se ofereceu e o da equipe com as manhãs dele) vale se usa o sábado e termina até o prazo; oferecido = se usa o sábado e é melhor; ligado → o bloco com sabado = true; em teste → fica o de sem sábado e sai sab_teste [{i, b, prazo_h}]. Sem as chaves da 7b, o de antes, byte a byte.';

-- _agenda_validar_itens (de 20261031100900_agenda_fase7a_sinal_sabado.sql)
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
    end if;
  end if;
  -- FASE 7b: fim
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
  'Agenda de Produção (Fase 2, P2): as 14 regras duras sobre os itens (criar e cancelar) de uma proposta, contra o banco de agora — (1) pessoa ativa e livre no turno (a ponta livre na presença curta, sem compromisso com hora), sem feriado; (2) sem choque com o vigente nem dentro da proposta; (3) não antes do dia em que fica pronta; (4) a presença do dono conforme a regra; (5) alguém em cada meio-dia; (6) o teto por pessoa e semana; (7) nada no congelado (salvo evento real e pedido do dono) nem no que começou; (8) o fixado só sai autorizado; (9) a OS na carteira; (10) classe 4 nunca; (11) reserva condicionada não vira compromisso; (12) wip_max por meio-dia; (13) no máximo interrupcoes_max dias parados; (14) com p_aplicar, item crítico só com a pergunta respondida. Lista vazia = ok; cada violação {regra, os, numero, pessoa, dia, turno, texto}. FASE 6 (P4): a regra 6 usa a carga de cada pessoa (_agenda_carga_da_pessoa: o dono com capacidade_dono em uso; os outros, carga_max) no lugar de carga_max; o texto não muda. FASE 7 (7a P5), atrás do portão _agenda_gestor_regra(''teto_equipe''): a regra 6 faz a conta do encaixe — o compromisso de cada pessoa da equipe até 100% do esperado (o dono com o teto dele; a semana inteira com as reservas e o texto não mudam) e, por semana, a soma da equipe (as pessoas da grade menos o dono; o vigente menos o cancelado + o novo, sem reserva e sem o pedido do dono) até floor(carga_max × a soma do esperado dela): "A equipe passaria do limite da semana de 09/11: 11 meios-dias de serviço para 10." (pessoa nula). Só confere a semana com compromisso novo da equipe fora do pedido do dono; com acima_da_carga, sem a conta da equipe. Sem o portão, a regra 6 da Fase 6. FASE 7 (7a P12; AG7-08): com a variável agenda.sabado = on (só a decisão 1 da pergunta crítica sabado a liga, na transação dela) e sabado_manha diferente de nunca, o meio-dia de turno na manhã de um sábado sem feriado, de quem tem o padrão de sábado de manhã e que a grade dá como fim de semana, não viola a regra 1 (a mesma conta do gancho do sábado de _agenda_contexto). Sem a variável, a de antes. FASE 7b (P4, R4.4 e §5.3): o gancho da pessoa a mais (R4.4, inerte sem a variável) — com agenda.pessoa_extra = tecnico, a "mais uma pessoa" (_agenda_pessoa_extra_id) entra na grade lida aqui livre nas manhãs e tardes de todo dia útil: não viola a regra 1 e a regra 6 (e a soma da equipe) a contam com a semana inteira; e, com modo_sabado ligado e alguma manhã de sábado livre na grade (a que a pessoa ofereceu), a regra 6 é refeita somando essas manhãs aos dois tetos da semana da pessoa (o compromisso e a semana inteira) e, com o teto da equipe do 7a, ao da equipe — a conta do encaixe na tentativa com o sábado; o texto não muda. Sem a variável e sem o sábado, a de antes, byte a byte.';

-- agenda_propor (de 20261031100700_agenda_fase7a_encaixe.sql)
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
    v_fila := v_fila || v_e;
  end loop;

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
  'Agenda de Produção (Fase 2, P2): o motor — guloso serial determinístico (mesma entrada, mesma saída). Escopo semana (publica os blocos que COMEÇAM de segunda a sábado da semana seguinte), os ou replano (as OS de p_os, depois do congelado, no horizonte). Etapas: estabilidade (_agenda_violacoes: só sai o que não pode mais acontecer; o publicado não violado nunca vira "mover"), a fila por classe (_agenda_classe_da_os) na ordem (classe, prioridade do dono, razão crítica, sinal pago, aprovação, número), o encaixe (_agenda_encaixar: congelamento hoje + o próximo dia útil, salvo evento real e pedido do dono; ≤ wip_max frentes; o dono como tambor; teto de carga_max por pessoa e semana; multi-dia com no máximo interrupcoes_max dias parados), a sobrecarga (a OS com data dita que não cabe vira a pergunta crítica nao_cabe, com as opções simuladas e a recomendação; o banco nunca escolhe), o atraso crítico de quem já tinha plano (_agenda_criticidade), as reservas (teto, condicionada com a data-limite, pátio), a validação (_agenda_validar_itens: inválida nunca sai), o diff (itens), as OS de fora com quem trava, a carga, a pontuação e os textos. Restrições: {fixar:[{os, de, ate, pessoa}], tirar:[os], so_depois_de:[{os, dia}], atrasar:[os], aceitar_atraso:[os], acima_da_carga, decisao}. Com p_persistir: agenda_propostas (modo = modo_proposta; a aberta anterior fica obsoleta), as alocações em estado proposta e as perguntas críticas. Sem persistir, o texto termina com "É simulação: não muda nada.". Só service_role. CORREÇÃO FASE 6 (C1, item 14): a reserva por teto da OS que precisa do dono, com a capacidade dele em uso abaixo de carga_max, diz "não coube na sua parte da semana (56%)" (a carga de _agenda_carga_da_pessoa), e não "na carga de 80%". CORREÇÃO 29/10 (P3): (a) a entrada da fila da OS com reserva vigente (por teto ou condicionada, de hoje em diante: a que o item "a reserva vira compromisso" cancela) leva res_propria (a pessoa × semana de cada meio-dia reservado), e o encaixe do compromisso dela não conta a própria reserva no lugar até 100% — a promoção da reserva cabe com o teto apertado (o João, 4 de 4 na semana); a reserva das outras OS continua contando. (b) Com a agenda automática ligada e reserva no que entra, o resumo separa o marcado firme do reservado e diz quem ("Semana de 03 a 06/11 (seg 02 é Finados): 1 reservado (Lenine), nada marcado firme, 10 de fora."), e o título da semana diz quantos ("Semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme", que abre o "Publiquei a semana de …"); sem reserva, ou fora de ligado, os de antes. FASE 7 (7a P3): o item de compromisso com a fonte orcamento (a estimativa do orçamento como dias firmes, só com a regra estimativa) termina "(estimativa minha: 6 dias)."; a recomendação das críticas dia_avisado ("A equipe já tinha recebido a ficha desse dia: recomendo seguir e você avisar quem ia") e dia_prometido ("É um dia que o cliente já ouviu: recomendo seguir e você falar com ele hoje"), que só nascem com a zona travada do P8. FASE 7 (7a P8, spec §3.2 e §5.8): com a regra zona_travada, a criticidade de cada compromisso colocado é refeita com p_violadas = _agenda_zona_fora (o que não conta para o dia já avisado: a violação, o resto do meio-dia dela e o que volta igual neste encaixe; nunca o fixado pelo dono): o meio-dia de um dia já dito à equipe ou ao cliente que sairia sem ter ficado impossível, e o fim que passaria do prometido firme, viram as críticas dia_avisado e dia_prometido, com a pergunta e a recomendação de sempre. Sem a regra, a de antes, byte a byte. FASE 7b (P4, §5.3, §6.3, R4.3): só com os modos da 7b — a entrada da fila ganha dk (as pessoas dos passos que restam), dk_dono_conta, dupla_fonte e o texto da dupla; da dupla inferida, passos1 (o bloco de 1 pessoa: ligado, a soma do dk; em teste, os passos de antes), dupla_ni/dupla_nf/dupla_todos e os nomes do que a tarefa pede; prazo_h (o índice da tarde de least(precisa_ate, o prometido firme)) e prazo; e dupla_sd na dupla dita que só passa pela régua dos técnicos com quem vem sob demanda. p_par ganha sab_modo, sab_politica, dupla_modo e dupla_espera. Ligado, o item com o sábado diz qual e por quê (" — com sáb 14/11 de manhã (Rafael se ofereceu), para cumprir o prazo de qua 18/11.") e o bloco de 1 pessoa da dupla inferida diz em que meios-dias chamar um ajudante (" Nos 2 primeiros meios-dias (qua 04/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem qua 04/11)."); o item leva dupla (o texto do cartão), dupla_fonte, dupla_falta [{dia, turno, onde}] e sabado. A dupla dita com dupla_sd sem bloco vai ao fora com o motivo dupla ("Lenine (OS-00074): precisa de 2 pessoas em 6 meios-dias e Mateus só vem qua 11 e qui 12/11 (4 meios-dias): me diga mais dias dele ou chame outro ajudante."), nunca sem_encaixe. Em teste, textos.em_teste e o fim do texto: "Em teste: para cumprir o prazo de Vanderlei (qua 18/11), eu usaria sáb 14/11 de manhã com Rafael, que se ofereceu." e "Em teste: no Lenine eu pediria um ajudante em qua 04/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas.". Sem os modos da 7b, a de antes, byte a byte.';

-- _agenda_gestor_sabado (de 20261031100900_agenda_fase7a_sinal_sabado.sql)
create or replace function public._agenda_gestor_sabado(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config;
  v_modo   text;
  v_seco   boolean;
  v_sim    boolean := false;
  v_quem   int;
  v_hor    date;
  r        record;
  v_s0     jsonb;
  v_s1     jsonb;
  v_fim0   date;
  v_it     jsonb;
  v_sabs   date[];
  v_pes    text[];
  v_txt    text;
  v_ops    jsonb;
  v_chave  text;
  v_id     uuid;
  v_chaves text[] := '{}';
  v_lista  jsonb := '[]'::jsonb;
  v_cand   int := 0;
  v_novas  int := 0;
  v_res    int := 0;
  v_erros  int := 0;
  v_estado text;
  v_msg    text;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_sabado: sem o dia ou a hora' using errcode = '22004';
  end if;
  -- FASE 7b: (7b P4, §R2) com modo_sabado ligado, o motor usa o sábado de manhã sozinho (só de quem se ofereceu, para cumprir o prazo
  -- firme, com o aviso no texto da marcação): a pergunta crítica sabado do 7a não nasce mais (uma pergunta só, não duas).
  if (public._agenda_cfg()).modo_sabado = 'ligado' then
    return jsonb_build_object('pulado', 'modo_sabado');
  end if;
  -- FASE 7b: fim
  cf := public._agenda_cfg();
  v_modo := coalesce(public._agenda_modo_da_pergunta('sabado', null), 'desligado');
  if cf.sabado_manha = 'nunca' then
    v_modo := 'desligado';
  end if;
  v_seco := v_modo <> 'ligado';
  -- quem pode vir no sábado de manhã: a régua de _agenda_contexto (P5) — o padrão de sábado de manhã vigente
  v_quem := (select count(distinct d.payee_id) from public.agenda_disponibilidade d
              where d.payee_id is not null and d.substituida_em is null and d.dias_semana @> array[6]::smallint[]
                and d.situacao in ('disponivel', 'confirmada') and (d.turno is null or d.turno = 'manha'));
  v_hor := p_hoje + 7 * cf.horizonte_semanas;

  if v_modo <> 'desligado' and v_quem > 0 then
    -- em teste, a conta é a do gestor (a simulação da sombra), sem gravar nada
    if v_seco and coalesce(current_setting('agenda.gestor', true), '') <> 'sombra' then
      perform set_config('agenda.gestor', 'sombra', true);
      v_sim := true;
    end if;
    -- as OS com prazo firme (o que o cliente pediu: precisa_ate; o que ele ouviu: o prometido firme) no horizonte
    for r in
      select k.service_order_id as os, k.numero, coalesce(k.cliente_curto, k.numero) as cliente,
             least(pl.precisa_ate, case when pl.prometido_tipo = 'firme' then pl.prometido_ate end) as prazo,
             case when pl.prometido_tipo = 'firme' and pl.prometido_ate is not null
                       and (pl.precisa_ate is null or pl.prometido_ate <= pl.precisa_ate)
                  then 'o que o cliente ouviu' else 'o que o cliente pediu' end as rotulo
        from public.os_carteira(p_hoje) k
        join public.os_planejamento pl on pl.service_order_id = k.service_order_id
       where least(pl.precisa_ate, case when pl.prometido_tipo = 'firme' then pl.prometido_ate end) between p_hoje + 1 and v_hor
       order by 4, k.numero collate "C", k.service_order_id
    loop
      begin
        -- o fim que o motor dá sem o sábado: o compromisso novo dela (com o atraso, se houver), ou o da pergunta "não cabe";
        -- sem nada novo para ela (o plano que já tem fica) o sábado não muda nada; fora sem encaixe = não cabe
        v_s0 := public.agenda_propor('os', null, null, array[r.os], '{}'::jsonb, false, 'motor', null, p_hoje, p_agora);
        v_fim0 := (select max((i ->> 'fim_depois')::date) from jsonb_array_elements(coalesce(v_s0 -> 'itens', '[]'::jsonb)) i
                    where i ->> 'op' = 'criar' and i ->> 'tipo' <> 'reserva' and (i ->> 'os')::uuid = r.os);
        if v_fim0 is null then
          v_fim0 := (select (o -> 'espera' ->> r.os::text)::date
                       from jsonb_array_elements(coalesce(v_s0 -> 'perguntas', '[]'::jsonb)) q, jsonb_array_elements(q -> 'opcoes') o
                      where q ->> 'tipo' = 'nao_cabe' and (q ->> 'service_order_id')::uuid = r.os and (o ->> 'n')::int = 1
                      limit 1);
          continue when v_fim0 is null
                        and not exists (select 1 from jsonb_array_elements(coalesce(v_s0 -> 'perguntas', '[]'::jsonb)) q
                                         where q ->> 'tipo' = 'nao_cabe' and (q ->> 'service_order_id')::uuid = r.os)
                        and not exists (select 1 from jsonb_array_elements(coalesce(v_s0 -> 'fora', '[]'::jsonb)) f
                                         where (f ->> 'os')::uuid = r.os and f ->> 'motivo' = 'sem_encaixe');
        end if;
        continue when v_fim0 is not null and v_fim0 <= r.prazo;
        v_cand := v_cand + 1;
        -- com a manhã de sábado de quem tem o padrão (a variável só aqui dentro)
        perform set_config('agenda.sabado', 'on', true);
        v_s1 := public.agenda_propor('os', null, null, array[r.os], '{}'::jsonb, false, 'motor', null, p_hoje, p_agora);
        perform set_config('agenda.sabado', '', true);
        select i into v_it from jsonb_array_elements(coalesce(v_s1 -> 'itens', '[]'::jsonb)) i
         where i ->> 'op' = 'criar' and i ->> 'tipo' <> 'reserva' and (i ->> 'os')::uuid = r.os and i ->> 'critica' is null
           and (i ->> 'fim_depois')::date <= r.prazo
         order by (i ->> 'de')::date limit 1;
        continue when v_it is null;
        v_sabs := array(select distinct (a ->> 'dia')::date from jsonb_array_elements(v_it -> 'alocacoes') a
                         where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno' order by 1);
        continue when cardinality(v_sabs) = 0;
        v_pes := array(select a ->> 'nome' from jsonb_array_elements(v_it -> 'alocacoes') with ordinality t(a, o)
                        where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno'
                        group by a ->> 'nome' order by min(o));
        v_txt := format('Para %s ficar pronto até %s (%s), preciso %s de manhã com %s. Sábado custa mais. 1) Use o sábado (recomendo); 2) Não use: %s.',
                        r.cliente, public._dia_curto(r.prazo), r.rotulo,
                        case when cardinality(v_sabs) = 1 then 'do sábado ' || to_char(v_sabs[1], 'DD/MM')
                             else 'dos sábados ' || public._agenda_lista(array(select to_char(x, 'DD/MM') from unnest(v_sabs) x order by x)) end,
                        public._agenda_lista(v_pes),
                        case when v_fim0 is not null then 'o serviço termina ' || public._dia_curto(v_fim0)
                             else 'sem o sábado, ele não cabe na agenda de agora' end);
        v_ops := jsonb_build_array(
          jsonb_build_object('n', 1, 'texto', 'Use o sábado',
                             'efeito', jsonb_build_object('sabado', true, 'sabados', to_jsonb(v_sabs), 'prazo', r.prazo,
                                                          'fim', v_it -> 'fim_depois')),
          jsonb_build_object('n', 2, 'texto', 'Não use: ' || case when v_fim0 is not null then 'o serviço termina ' || public._dia_curto(v_fim0)
                                                                   else 'sem o sábado, ele não cabe na agenda de agora' end,
                             'efeito', jsonb_build_object('nao_usar', true, 'fim', v_fim0)));
        v_chave := format('sabado:%s:%s', r.os, v_sabs[1]);
        v_chaves := v_chaves || v_chave;
        v_id := null;
        if not v_seco then
          v_id := public._agenda_gestor_perguntar('sabado', v_chave, r.os, v_txt, v_ops, 1::smallint, null::timestamptz,
                                                  null::smallint, v_modo, p_agora);
          if v_id is not null then
            -- a pergunta não vale depois que o sábado começa (crítica, sem prazo: só some)
            update public.agenda_perguntas set expira_em = lower(public.agenda_periodo(v_sabs[1], 'manha'))
             where id = v_id and estado = 'aberta' and expira_em > lower(public.agenda_periodo(v_sabs[1], 'manha'));
            if exists (select 1 from public.agenda_perguntas q where q.id = v_id and q.criada_em = p_agora) then
              v_novas := v_novas + 1;
            end if;
          end if;
        end if;
        v_lista := v_lista || jsonb_build_object('os', r.os, 'numero', r.numero, 'prazo', r.prazo, 'sabados', to_jsonb(v_sabs),
                                                 'pessoas', to_jsonb(v_pes), 'fim_sem', v_fim0, 'fim_com', v_it -> 'fim_depois',
                                                 'chave', v_chave, 'pergunta_id', v_id, 'texto', v_txt);
      exception when others then
        -- o erro de uma OS fica consultável e as outras seguem (o tempo da rodada, query_canceled, sobe)
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        perform public.log_app_error('db', format('gestor da agenda, passo sabado (%s): %s', r.numero, v_msg), 'agenda',
                                     'gestor:sabado', 'error',
                                     jsonb_build_object('os', r.os, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
      end;
    end loop;
    if v_sim then
      perform set_config('agenda.gestor', '', true);
    end if;
  end if;

  -- a pergunta aberta (de verdade) que esta conta não refez não vale mais: o plano mudou, o sábado passou ou ninguém vem mais
  if not v_seco or v_modo = 'desligado' then
    with f as (
      update public.agenda_perguntas q set estado = 'resolvida', resolvida_motivo = 'não precisa mais: o plano mudou'
       where q.tipo = 'sabado' and q.estado = 'aberta' and q.modo = 'ligado' and not (q.chave = any (v_chaves))
      returning 1)
    select count(*)::int into v_res from f;
  end if;
  if v_modo = 'desligado' then
    return jsonb_build_object('pulado', true, 'resolvidas', v_res,
                              'motivo', case when cf.sabado_manha = 'nunca' then 'sábado: nunca' else 'o gestor está desligado' end);
  end if;
  return jsonb_build_object('modo', v_modo, 'simulacao', v_seco, 'quem_vem_sabado', v_quem, 'candidatas', v_cand,
                            'perguntas', jsonb_array_length(v_lista), 'novas', v_novas, 'resolvidas', v_res, 'erros', v_erros,
                            'lista', v_lista);
end;
$function$;

comment on function public._agenda_gestor_sabado(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P12; AG7-08 "sim, quando precisar", spec §3.3 d9, §5.12 e §6.3): o passo diário sabado da rodada do gestor. Com sabado_manha diferente de nunca e alguém com o padrão de sábado de manhã: para cada OS da carteira com prazo firme no horizonte (least(precisa_ate, o prometido firme)) cujo fim, pelo motor sem o sábado (agenda_propor escopo os, sem gravar: o compromisso novo dela, a pergunta "não cabe" ou o "sem encaixe"), passa do prazo, a mesma conta com a variável agenda.sabado = on (a manhã de sábado de quem tem o padrão, _agenda_contexto do P5); se assim ela cabe no prazo usando a manhã de sábado, a pergunta crítica sabado (chave sabado:<os>:<o 1º sábado>; sem prazo; expira quando o sábado começa): "Para Nelson ficar pronto até sex 13/11 (o que o cliente ouviu), preciso do sábado 07/11 de manhã com Roberto. Sábado custa mais. 1) Use o sábado (recomendo); 2) Não use: o serviço termina ter 17/11." ("o que o cliente pediu" pelo precisa_ate). O modo é o do gestor que marca (_agenda_modo_da_pergunta): em teste a conta é a da sombra, seca (só na saída do passo); desligado ou sabado_manha = nunca = {pulado}. A aberta que a conta do dia não refaz é resolvida ("não precisa mais: o plano mudou"). O erro de uma OS vai a app_error_logs (gestor:sabado) e as outras seguem. Hoje ninguém tem o padrão de sábado: 0 perguntas. O 7b (P4) recria esta função para {pulado} com modo_sabado ligado. {modo, simulacao, quem_vem_sabado, candidatas, perguntas, novas, resolvidas, erros, lista}. Invoker, sem grant (só a rodada do gestor o chama). FASE 7b (P4, §R2): com modo_sabado ligado, {pulado: modo_sabado} — o motor usa o sábado de manhã sozinho (só de quem se ofereceu, para cumprir o prazo firme) e avisa no texto da marcação; a pergunta crítica sabado não nasce. Fora de ligado, a de antes.';

-- ── 3. Portas ────────────────────────────────────────────────────────────────────────────────────────────────────
-- As 4 novas: invoker; authenticated e service_role (o molde, a classe e os técnicos da grade são lidos pelo painel e chegam a
-- elas); nunca anon (spec §3.1-10: revogar de public E de anon).
revoke all on function
  public._agenda_pessoa_extra_id(), public._agenda_e_novato(uuid, date), public._agenda_e_sob_demanda(uuid, date),
  public._agenda_dupla_da_os(uuid)
  from public, anon;
grant execute on function
  public._agenda_pessoa_extra_id(), public._agenda_e_novato(uuid, date), public._agenda_e_sob_demanda(uuid, date),
  public._agenda_dupla_da_os(uuid)
  to authenticated, service_role;

-- As recriadas mantêm as portas delas (create or replace não muda a ACL; repetidas aqui para a migration se bastar).
revoke all on function
  public.os_duracao_sugerida(uuid), public.agenda_meios_da_os(uuid, date),
  public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean), public._agenda_tecnicos_da_grade(date),
  public._agenda_carga_da_pessoa(uuid),
  public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb)
  from public, anon;
grant execute on function
  public.os_duracao_sugerida(uuid), public.agenda_meios_da_os(uuid, date),
  public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean), public._agenda_tecnicos_da_grade(date),
  public._agenda_carga_da_pessoa(uuid),
  public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb)
  to authenticated, service_role;
revoke all on function
  public._agenda_contexto(date, date, date, uuid[], uuid[]),
  public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer),
  public._agenda_melhor(jsonb, jsonb), public._agenda_encaixar(jsonb, jsonb, jsonb),
  public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)
  from public, anon, authenticated;
grant execute on function
  public._agenda_contexto(date, date, date, uuid[], uuid[]),
  public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer),
  public._agenda_melhor(jsonb, jsonb), public._agenda_encaixar(jsonb, jsonb, jsonb),
  public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)
  to service_role;
revoke all on function public._agenda_gestor_pessoa_meios(uuid, date, jsonb), public._agenda_gestor_sabado(date, timestamptz)
  from public, anon, authenticated, service_role;

-- Agenda de Produção, Fase 7, etapa 7a ("ele marca sozinho"), pacote P2: a duração — a estimativa do orçamento como dias firmes,
-- a mão de obra limpa (sem deslocamento), uma pessoa por serviço (a dupla só quando o dono marca), o diagnóstico de meio dia, a
-- situação da OS começada ou parada e o teto da estimativa (o que passa de estimativa_max_diarias vira pergunta).
-- Spec: scratchpad agenda-pesquisa/spec-fase7a.md (§R, §3.1, §5.2, §6.4); nomes: fase7-registro.md §1 e §2; respostas do dono:
-- fase7-padroes.md (D7-1 marca firme pela estimativa; AG7-04 uma pessoa, dupla só marcada; AG7-11 quanto falta).
-- Depende da 20261031100000 (7a P1: o portão _agenda_gestor_regra, as colunas e os parâmetros) e, antes dela, das Fases 1 a 6 e
-- do lote de correção de 30/10, todos em produção.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (5 funções novas e 2 recriadas; nenhuma tabela, coluna, lista, dado, cron ou tela muda)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7a/p2/montar-migration.mjs: as 2 recriadas são o corpo
-- da definição MAIS NOVA (conferido a cada montagem em supabase/migrations, também nas 20261030* do lote e na 20261031100000 do
-- P1, que não as recriam): os_duracao_sugerida de 20261029100200 e agenda_meios_da_os de 20261025100200. As mudanças estão só
-- nos blocos "-- FASE 7: … -- FASE 7: fim"; fora deles nenhuma linha muda (o D8 de supabase/tests/agenda_fase7a_duracao.sql
-- confere).
--
-- POR QUE: o gestor da agenda passa a marcar sozinho pela estimativa do orçamento (D7-1). Hoje, sem os dias ditos, a duração é
-- "sugerida" (só reserva e simulação) e sai com 2 pessoas (equipe_sugerida): com um técnico só na equipe, nada cabe ("sem lugar
-- para a reserva nesta semana", medição de 30/10). Este pacote faz a estimativa valer como dias firmes (fonte 'orcamento') e a
-- deixa realista e limpa; quem decide a classe (P3), as perguntas com prazo (P4) e o resto são os próximos pacotes.
--
-- O QUE MUDA (tudo atrás do portão _agenda_gestor_regra; com o portão falso, a saída de cada função recriada é a de antes, byte a
-- byte — a os_prontidao, o motor e o aprendizado embutem estas saídas):
--   1. os_duracao_sugerida (recriada), três regras:
--      · mo_limpa: a linha cujo nome do serviço casa mo_fora_regex (deslocamento, viagem, translado, visita técnica, km rodado,
--        frete) sai da mão de obra e das horas; a saída ganha fora_da_mo [{linha, nome, valor, horas}] (só quando tirou algo).
--        OS-00076: o "Deslocamento técnico" (R$ 200, 1 h) sai.
--      · uma_pessoa (AG7-04): pessoas = equipe_padrao (1); greatest(equipe_sugerida, 2) só com os_planejamento.dupla_dita =
--        'todos'; o serviço de até 1 diária continua com 1. A saída ganha pessoas_motivo (regra | dupla_marcada) e, sem nada
--        dito, alerta_dupla {motivo, nota, onde, linha, nome, trecho}: o 1º gatilho de dupla_gatilhos (ou nota de dupla_notas)
--        que casa no nome do serviço — aviso ao dono, nunca 2 pessoas sozinho. Lenine: 6 dias com 1 pessoa (era 3 com 2).
--      · diagnostico: a OS de diagnóstico (service_type ou a linha de maior valor, a régua de os_presenca_do_dono) leva
--        diagnostico_dias (meio dia) com 1 pessoa, diagnostico: true, "meio dia de diagnóstico; depois eu reavalio".
--   2. agenda_meios_da_os (recriada): sem os dias ditos e com a regra estimativa, fonte 'orcamento' com os dias de
--      _agenda_gestor_estimativa quando ela usa; a saída ganha estimativa_motivo (por que não usa) e situacao_pendente. Os dias
--      'orcamento' gravados (o prazo vencido do P4) com o portão falso são lidos como 'sugerida' (desligar volta ao de antes).
--   3. Novas: _agenda_nome_do_servico (o nome antes de " — ", " – ", ":" ou "("; o 7b usa), _agenda_peca_embutida (a mesma
--      consulta de v_embut da os_prontidao; paridade no teste), _agenda_os_situacao (começada/parada, o rastro, o que o gestor
--      faria sem resposta), _agenda_gestor_estimativa (usa ou o motivo: dito, regra_desligada, situacao, sem_base, grande,
--      embutida) e agenda_dupla_dita (a palavra *<nome> com dupla* / *sem dupla*: grava a marca, o histórico e a ação dupla).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7a_duracao.sql; registradas em notas-fase77a.md, P2):
--   · mo_limpa olha o NOME DO SERVIÇO (_agenda_nome_do_servico), não a linha inteira: na carteira de 29/10 a ORÇ-00123 tem
--     "Retirada e reinstalação do TM41 — retirada, embalagem e envio à Technomaster, frete de ida e volta…" (R$ 1.480), que pela
--     linha inteira sairia da mão de obra por causa do "frete" da descrição.
--   · uma_pessoa mantém "até 1 diária = 1 pessoa" (com equipe_padrao 1 não muda nada; com 2 ou 3, o serviço pequeno não ganha
--     gente). O alerta_dupla só nasce sem nada dito (dupla_dita nula): o que o dono já disse não vira aviso de novo.
--   · diagnostico vale também sem mão de obra separada (o diagnóstico tem o tempo dele) e com a dupla marcada leva a dupla.
--   · _agenda_os_situacao: sem estimativa (sem mão de obra), a proposta é sem_mo_dias; desde = o check-in ou a 1ª diária
--     ligada, senão o dia em que a OS entrou no status de agora (ai_lifecycle_events), senão a última atualização.
--   · agenda_dupla_dita usa agenda_resolver_os (o resolvedor do *desfaz*; a spec citava "_agenda_os_do_alvo", que não existe).
--     O ramo do *desfaz* da ação dupla é do P7 (spec §5.7).
--
-- O QUE NÃO MUDA: nenhuma tabela, coluna, lista fechada, dado, cron, tela ou função de borda. Com o portão falso (a linha de
-- agenda_config nasce com modo_marcar_sozinho = 'desligado'; em sombra, só dentro da simulação), nada muda para ninguém.
--
-- A MEMÓRIA DA VIGIA (lote de 30/10, P5): os_duracao_sugerida, embutida na prontidão, passa a chamar o portão, que lê a variável
-- da simulação (agenda.gestor). A prontidão lembrada continua certa porque nada da rodada da vigia escreve essa variável
-- (supabase/tests/agenda_correcao_2910_p5.sql: o G1 aceita só essa leitura, só no portão; o G3 prova que a vigia não a escreve).
-- O custo com o portão falso (bancada, por OS): os_duracao_sugerida 0,55 → 1,35 ms; agenda_meios_da_os 2,20 → 2,51 ms (a
-- prontidão inteira, ~15 ms, continua a conta que pesa).
--
-- ORDEM DE LIGAR: depois de 20261031100000 (P1); antes de 20261031100200 (P3), que lê estimativa_motivo e situacao_pendente.
-- Aplicar sozinha não muda nada (o portão é falso até o *ligar* do roteiro da §10 da spec).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7a_duracao.sql (begin/rollback; D1 a D8 e as portas). Na bancada:
-- node scripts/bancada-agenda/rodar.mjs --ate 20261031100100
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261031100100_agenda_fase7a_duracao.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261031100100', 'agenda_fase7a_duracao');"
--
-- DESFAZER: sem migration, o portão (spec §10: *gestor, só propor*, ou modo_marcar_sozinho fora de 'ligado', ou a regra fora
-- de marcar_regras): com ele falso, a saída é a de antes. Para tirar o código: recriar os_duracao_sugerida com o corpo de
-- 20261029100200 e agenda_meios_da_os com o de 20261025100200 (a cópia sem os blocos "-- FASE 7:"); as 5 funções novas podem
-- ficar. Depois do P4, antes disso, apagar os dias de fonte 'orcamento' gravados por prazo vencido: o corpo de antes os leria
-- como dias firmes.
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. As funções novas que a duração usa ─────────────────────────────────────────────────────────────────

-- O nome do serviço (o contrato da §2 do 7b, que usa esta): o trecho antes do 1º " — ", " – ", ":" ou "(", normalizado
-- (_agenda_normal: minúsculo, sem acento, pontuação vira espaço). Sem o corte, a Starlink da ORÇ-00119 ("… alimentado pelo banco
-- de baterias … funciona sem inversor ou gerador") casava três gatilhos de dupla, e o "frete de ida e volta" da descrição da
-- ORÇ-00123 tirava da mão de obra a retirada e a reinstalação do TM41. O hífen comum (" - ") não corta: "SUBSTITUIÇÃO BATERIAS -
-- CHUMBO PARA LITIO" é um nome só. IMMUTABLE: só texto.
create or replace function public._agenda_nome_do_servico(p_nome text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select public._agenda_normal(regexp_replace(coalesce(p_nome, ''), '( — | – |:|\().*$', ''));
$function$;

comment on function public._agenda_nome_do_servico(text) is
  'Agenda de Produção (Fase 7a, P2): o nome do serviço de uma linha — o trecho antes do 1º " — ", " – ", ":" ou "(", normalizado (_agenda_normal). A régua única de "o nome do serviço" para a mão de obra limpa (mo_fora_regex) e os gatilhos de dupla (dupla_gatilhos/dupla_notas) do 7a e do 7b: a descrição depois do travessão não conta. IMMUTABLE.';

-- As linhas que podem ter peça embutida (a MESMA consulta de v_embut da os_prontidao, corpo de 20261030100400: texto livre que NÃO
-- entra na compra e vale >= peca_embutida_acima, ou o classificador lê como material com unidade que não é 'unit', ou cita
-- peça/material; some quando o dono responde por ela ou diz "não tem peça a comprar" depois que a linha nasceu). Paridade provada em
-- supabase/tests/agenda_fase7a_duracao.sql (D6): mudar uma é mudar a outra. [{linha, nome, curto, valor}], a de maior valor primeiro.
create or replace function public._agenda_peca_embutida(p_os uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c       public.agenda_config := public._agenda_cfg();
  p       public.os_planejamento%rowtype;
  v_embut jsonb;
begin
  select * into p from public.os_planejamento where service_order_id = p_os;
  select coalesce(jsonb_agg(jsonb_build_object('linha', s.id, 'nome', s.name_snapshot,
                                               'curto', public._agenda_linha_curta(s.name_snapshot),
                                               'valor', s.line_total)
                            order by s.line_total desc nulls last, s.created_at, s.id), '[]'::jsonb)
    into v_embut
    from public.service_order_services s
   where s.service_order_id = p_os and s.service_id is null
     and not (s.billing_unit_snapshot = 'unit' and coalesce(s.quantity, 0) > 0 and public.free_text_is_material(s.name_snapshot))
     and (coalesce(s.line_total, 0) >= c.peca_embutida_acima
          or public.free_text_is_material(s.name_snapshot)
          or public._agenda_normal(s.name_snapshot) ~ '\m(peca|pecas|material)\M')
     and not exists (select 1 from public.os_material m
                      where m.service_order_id = p_os and m.origem = 'dono' and m.service_order_service_id = s.id)
     and not (p.material_conferido_em is not null and p.material_conferido_em > s.created_at);
  return v_embut;
end;
$function$;

comment on function public._agenda_peca_embutida(uuid) is
  'Agenda de Produção (Fase 7a, P2): as linhas da OS que podem ter peça embutida — a mesma consulta de v_embut da os_prontidao (20261030100400; paridade no teste D6 de agenda_fase7a_duracao.sql): texto livre que não entra na compra e vale >= peca_embutida_acima, ou é material pelo classificador, ou cita peça/material; some com a resposta do dono pela linha ou com o "não tem peça a comprar" depois dela. [{linha, nome, curto, valor}], a de maior valor primeiro; [] sem nenhuma. STABLE, invoker.';

-- ── 2. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 7:") ──────────────────────
-- Fora dos blocos nenhuma linha muda (o D8 de supabase/tests/agenda_fase7a_duracao.sql confere). Quem recriar de novo
-- qualquer uma delas copia DESTA migration (fase7-registro.md §2: o 7b P4 e o 7e P3).

-- os_duracao_sugerida (de 20261029100200_agenda_fase6_os.sql)
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
                                'trecho', substring(public._agenda_nome_do_servico(s.name_snapshot) from '\m(' || (g.e ->> 1) || ')'))
        into v_f7_alerta
        from (select t.e, t.o, false as nota from jsonb_array_elements(c.dupla_gatilhos) with ordinality t(e, o)
              union all
              select t.e, t.o, true from jsonb_array_elements(c.dupla_notas) with ordinality t(e, o)) g
        join public.service_order_services s
          on s.service_order_id = p_so_id
         and public._agenda_nome_do_servico(s.name_snapshot) ~ ('\m(' || (g.e ->> 1) || ')')
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
  'Agenda de Produção (Fase 1, P3): a duração "pelo valor" (plano §4.2 com a correção do material). mo = linhas de serviço − material de texto livre que entra na compra; horas = linhas por hora; diárias-pessoa otimista = max(horas ÷ jornada_horas, mo ÷ mo_por_diaria_preco), realista = max(horas ÷ jornada_horas, mo ÷ mo_por_diaria_real); 1 pessoa se o realista ≤ 1, senão equipe_sugerida; dias arredondados ao meio dia; sugerida = o meio dia mais perto da média. Sem mão de obra nem horas: {sem_base:true, texto:"sem base para estimar: quantos dias?"}. Nunca é gravada. FASE 6 (P2): o realista usa _agenda_mo_por_diaria_real() (o R$ por diária aprendido em uso, senão mo_por_diaria_real); com o aprendido em uso a saída ganha mo_fonte = aprendido e mo_por_diaria (sem ele, a saída de antes). FASE 7 (7a P2), atrás do portão _agenda_gestor_regra (falso = a saída de antes, byte a byte): mo_limpa — a linha cujo nome do serviço (_agenda_nome_do_servico) casa mo_fora_regex sai da mão de obra e das horas (fora_da_mo); uma_pessoa (AG7-04) — pessoas = equipe_padrao (até 1 diária = 1), greatest(equipe_sugerida, 2) só com dupla_dita = todos (pessoas_motivo) e, sem nada dito, alerta_dupla pelo 1º gatilho de dupla_gatilhos/dupla_notas no nome do serviço; diagnostico — a OS de diagnóstico leva diagnostico_dias com 1 pessoa (diagnostico: true, "meio dia de diagnóstico; depois eu reavalio").';

-- agenda_meios_da_os (de 20261025100200_agenda_fase2_motor.sql)
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
  end if;

  -- O que já foi feito e o que já está marcado (d20).
  v_plano := public._agenda_plano_da_os(p_so_id, p_hoje);
  v_cump := coalesce((v_plano ->> 'meios_cumpridos')::numeric, 0);
  v_vig := coalesce((v_plano ->> 'meios_vigentes')::int, 0);
  v_total := case when v_dias is null then null else (v_dias * 2)::int end;
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
  'Agenda de Produção (Fase 2, P2): o molde dos meios-dias do que o dono disse — total = dias × 2 (meio dia = 1); por turno os diaristas ditos ("dia" vale nos dois) e quantos (desejado; sem equipe dita, as pessoas da sugestão, e o dono que fica o turno inteiro é uma delas); a presença do dono: o que ele disse → ele na equipe dita (turno nos turnos dele) → a regra d05 (sempre = turno em todos; abre_e_fecha = abertura no 1º e fechamento no último); restantes = total − cumpridos (cumprido/sem registro/passado sem resultado = 1, parcial = 0,5) − os meios-dias vigentes de hoje em diante. Sem os dias ditos: fonte sugerida (dias_realista), só para reserva e simulação. {ok, fonte, dias, total, restantes, passos, presenca, abre, fecha, dono_turno, por_turno, molde[{k, turno, pessoas_ditas, desejado, dono}]}. FASE 7 (7a P2): sem os dias ditos e com a regra estimativa (_agenda_gestor_regra), a fonte é ''orcamento'' com os dias de _agenda_gestor_estimativa quando ela usa (D7-1: a estimativa do orçamento vale como dias firmes; nada é gravado), e a saída ganha estimativa_motivo (por que não usa: situacao, sem_base, grande, embutida; null quando usa) e situacao_pendente; os dias de fonte ''orcamento'' gravados com o portão falso são lidos como ''sugerida''. Sem a regra, a saída de antes, byte a byte.';

-- ── 3. A situação da OS, a estimativa do gestor e a palavra da dupla ────────────────────────────────────────────

-- A OS que já começou ou está parada (AG7-11): antes de contar a estimativa cheia, o gestor pergunta "quanto falta?". Só com o
-- portão situacao, sem os dias ditos (os_planejamento.dias: o *grava* do dono ou o prazo vencido tiram a pendência) e sem
-- alocação de compromisso vigente (publicada ou fixada; a reserva não conta). comecada = check-in OU status em andamento /
-- aguardando peças; parada = aberta, aprovada ou agendada sem nada (conversão, assinatura, atualização, evento, ação da
-- agenda) há mais de situacao_dias. rastro = check-in, em andamento ou diária ligada (v_dias_por_os_e_pessoa). O que o gestor
-- faria sem resposta (proposta_dias): com rastro, quanto_falta_dias (nunca mais que a estimativa inteira); sem rastro, os dias
-- da estimativa (sem mão de obra, sem_mo_dias). {pendente, tipo, rastro, desde, proposta_dias, pergunta_id, status, curto,
-- texto}; não pendente = {pendente: false}.
create or replace function public._agenda_os_situacao(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config;
  so       record;
  v_tipo   text;
  v_rastro boolean;
  v_desde  date;
  v_diaria date;
  v_ult    timestamptz;
  v_prop   numeric;
  v_sug    jsonb;
  v_est    numeric;
  v_pid    uuid;
  v_txt    text;
  v_curto  text;
  v_nada   constant jsonb := jsonb_build_object('pendente', false);
begin
  if p_hoje is null then
    raise exception '_agenda_os_situacao: sem o dia de hoje' using errcode = '22004';
  end if;
  if p_os is null or not public._agenda_gestor_regra('situacao') then
    return v_nada;
  end if;
  select o.id, o.status, o.check_in_at, o.converted_to_os_at, o.signed_at, o.updated_at
    into so from public.service_orders o where o.id = p_os;
  if not found then
    return v_nada;
  end if;
  if exists (select 1 from public.os_planejamento pl where pl.service_order_id = p_os and pl.dias is not null)
     or exists (select 1 from public.agenda_alocacoes a
                 where a.service_order_id = p_os and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada')) then
    return v_nada;
  end if;
  cf := public._agenda_cfg();

  select min(v.primeiro_dia) into v_diaria
    from public.v_dias_por_os_e_pessoa v
   where v.service_order_id = p_os and v.dias > 0 and v.primeiro_dia <= p_hoje;
  v_rastro := so.check_in_at is not null or so.status = 'in_progress' or v_diaria is not null;

  if so.check_in_at is not null or so.status in ('in_progress', 'awaiting_parts') then
    v_tipo := 'comecada';
    -- desde quando: o check-in ou a 1ª diária ligada; sem eles, o dia em que a OS entrou no status de agora (senão a
    -- última atualização)
    v_desde := least((so.check_in_at at time zone 'America/Sao_Paulo')::date, v_diaria);
    if v_desde is null then
      select (max(e.created_at) at time zone 'America/Sao_Paulo')::date into v_desde
        from public.ai_lifecycle_events e
       where e.entity_id = p_os and e.event_type = 'status_change' and e.new_value = so.status;
      v_desde := coalesce(v_desde, (so.updated_at at time zone 'America/Sao_Paulo')::date);
    end if;
  elsif so.status in ('open', 'approved', 'scheduled') then
    v_ult := greatest(so.converted_to_os_at, so.signed_at, so.updated_at,
                      (select max(e.created_at) from public.ai_lifecycle_events e where e.entity_id = p_os),
                      (select max(a.criada_em) from public.agenda_acoes a
                        where a.service_order_id = p_os or p_os = any (a.os_ids)));
    if v_ult is null or (v_ult at time zone 'America/Sao_Paulo')::date >= p_hoje - cf.situacao_dias then
      return v_nada;
    end if;
    v_tipo := 'parada';
    v_desde := (v_ult at time zone 'America/Sao_Paulo')::date;
  else
    return v_nada;
  end if;

  -- a estimativa inteira (com as regras da duração); o "quanto falta" nunca passa dela
  v_sug := public.os_duracao_sugerida(p_os);
  v_est := case when coalesce((v_sug ->> 'sem_base')::boolean, false) then null else (v_sug ->> 'dias_realista')::numeric end;
  if v_tipo = 'comecada' and v_rastro then
    v_prop := least(cf.quanto_falta_dias, coalesce(v_est, cf.quanto_falta_dias));
  else
    v_prop := coalesce(v_est, cf.sem_mo_dias);
  end if;
  select q.id into v_pid from public.agenda_perguntas q
   where q.tipo = 'situacao' and q.service_order_id = p_os and q.estado = 'aberta'
   order by q.criada_em desc, q.id desc limit 1;

  v_curto := case when v_tipo = 'parada' then 'parado desde ' || to_char(v_desde, 'DD/MM') else 'já começou?' end;
  v_txt := case
    when v_tipo = 'parada' then
      format('falta você dizer se ainda é para fazer o serviço inteiro (parado desde %s); sem resposta, conto o serviço inteiro (%s, estimativa minha)',
             to_char(v_desde, 'DD/MM'), public._agenda_dias(v_prop))
    when v_rastro then
      format('falta você dizer quanto falta (começou em %s); sem resposta, marco %s para terminar',
             to_char(v_desde, 'DD/MM'), public._agenda_dias(v_prop))
    else
      format('falta você dizer se o serviço já começou (está como "%s", sem check-in nem diária ligada); sem resposta, conto o serviço inteiro (%s, estimativa minha)',
             public._agenda_status_texto(so.status), public._agenda_dias(v_prop))
  end;
  return jsonb_build_object('pendente', true, 'tipo', v_tipo, 'rastro', v_rastro, 'desde', v_desde,
                            'proposta_dias', trim_scale(v_prop), 'pergunta_id', v_pid, 'status', so.status,
                            'curto', v_curto, 'texto', v_txt);
end;
$function$;

comment on function public._agenda_os_situacao(uuid, date) is
  'Agenda de Produção (Fase 7a, P2; AG7-11): a OS que começou ou parou, antes de o gestor contar a estimativa cheia. Só com o portão situacao, sem os_planejamento.dias e sem alocação de compromisso vigente. comecada = check-in ou status in_progress/awaiting_parts; parada = open/approved/scheduled sem atividade (conversão, assinatura, updated_at, ai_lifecycle_events, agenda_acoes) há mais de situacao_dias. rastro = check-in, in_progress ou diária ligada. proposta_dias = quanto_falta_dias com rastro (nunca mais que a estimativa inteira), senão os dias da estimativa (sem base: sem_mo_dias). {pendente, tipo, rastro, desde, proposta_dias, pergunta_id (a pergunta situacao aberta), status, curto (a linha curta do "eu perguntaria"), texto (a restrição ao dono)}; senão {pendente: false}. STABLE, invoker.';

-- A estimativa que o gestor usa como dias firmes (D7-1) ou o motivo de perguntar antes (AG7-11, §5.2), nesta ordem: os dias
-- ditos → 'dito'; portão estimativa falso → 'regra_desligada'; começada/parada → 'situacao'; sem mão de obra → 'sem_base'
-- (proposta sem_mo_dias); diárias-pessoa acima de estimativa_max_diarias → 'grande'; peça embutida com o portão
-- embutida_suposta → 'embutida'; senão usa o realista de os_duracao_sugerida (com as regras da duração). {usa, motivo, dias, dp,
-- pessoas, texto, proposta_dias, alerta_dupla, embutida} (+ situacao, quando o motivo é a situação). O texto do que usa é o rótulo
-- ao dono ("6 dias, 1 pessoa (estimativa minha, pelo valor do orçamento)"); o do que não usa é a linha curta do "antes de marcar
-- eu perguntaria" ("10 diárias pela estimativa", "já começou?", "parado desde 03/10", "não tem mão de obra separada", "pode ter
-- peça junto").
create or replace function public._agenda_gestor_estimativa(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config;
  v_dito numeric;
  v_sug  jsonb;
  v_sit  jsonb;
  v_emb  jsonb;
  v_dias numeric;
  v_pes  int;
  v_base jsonb;
begin
  if p_hoje is null then
    raise exception '_agenda_gestor_estimativa: sem o dia de hoje' using errcode = '22004';
  end if;
  select pl.dias into v_dito from public.os_planejamento pl where pl.service_order_id = p_os;
  if v_dito is not null then
    return jsonb_build_object('usa', false, 'motivo', 'dito');
  end if;
  if not public._agenda_gestor_regra('estimativa') then
    return jsonb_build_object('usa', false, 'motivo', 'regra_desligada');
  end if;
  cf := public._agenda_cfg();
  v_sug := public.os_duracao_sugerida(p_os);
  if not coalesce((v_sug ->> 'ok')::boolean, false) then
    return jsonb_build_object('usa', false, 'motivo', 'sem_os', 'texto', v_sug ->> 'texto');
  end if;
  v_dias := case when coalesce((v_sug ->> 'sem_base')::boolean, false) then null else (v_sug ->> 'dias_realista')::numeric end;
  v_pes := (v_sug ->> 'pessoas')::int;
  v_emb := public._agenda_peca_embutida(p_os);
  v_base := jsonb_build_object('usa', false, 'dias', trim_scale(v_dias), 'dp', (v_sug ->> 'dp_realista')::numeric,
                               'pessoas', v_pes, 'alerta_dupla', v_sug -> 'alerta_dupla', 'embutida', v_emb,
                               'proposta_dias', null);

  v_sit := public._agenda_os_situacao(p_os, p_hoje);
  if coalesce((v_sit ->> 'pendente')::boolean, false) then
    return v_base || jsonb_build_object('motivo', 'situacao', 'proposta_dias', v_sit -> 'proposta_dias',
                                        'texto', v_sit ->> 'curto', 'situacao', v_sit);
  end if;
  if v_dias is null then
    return v_base || jsonb_build_object('motivo', 'sem_base', 'proposta_dias', trim_scale(cf.sem_mo_dias),
                                        'texto', 'não tem mão de obra separada');
  end if;
  if (v_sug ->> 'dp_realista')::numeric > cf.estimativa_max_diarias then
    return v_base || jsonb_build_object('motivo', 'grande', 'proposta_dias', trim_scale(v_dias),
                                        'texto', public._agenda_num((v_sug ->> 'diarias_realista')::numeric) || ' diárias pela estimativa');
  end if;
  if jsonb_array_length(v_emb) > 0 and public._agenda_gestor_regra('embutida_suposta') then
    return v_base || jsonb_build_object('motivo', 'embutida', 'proposta_dias', trim_scale(v_dias),
                                        'texto', 'pode ter peça junto');
  end if;
  return v_base || jsonb_build_object('usa', true, 'motivo', null,
    'texto', case when coalesce((v_sug ->> 'diagnostico')::boolean, false) then v_sug ->> 'texto'
                  else public._agenda_dias(v_dias)
                       || case when v_pes = 1 then ', 1 pessoa' else format(' com %s pessoas', v_pes) end
                       || ' (estimativa minha, pelo valor do orçamento)' end);
end;
$function$;

comment on function public._agenda_gestor_estimativa(uuid, date) is
  'Agenda de Produção (Fase 7a, P2; D7-1, AG7-11): a estimativa do orçamento que o gestor usa como dias firmes, ou o motivo de perguntar antes — dito (os_planejamento.dias), regra_desligada (portão estimativa), situacao (_agenda_os_situacao pendente), sem_base (proposta sem_mo_dias), grande (dp_realista > estimativa_max_diarias), embutida (_agenda_peca_embutida com o portão embutida_suposta); senão usa (o dias_realista de os_duracao_sugerida). {usa, motivo, dias, dp, pessoas, texto, proposta_dias, alerta_dupla, embutida} (+ situacao). Nada é gravado: é leitura (agenda_meios_da_os, a prontidão e as perguntas do gestor leem daqui). STABLE, invoker.';

-- A palavra do dono *<nome> com dupla* / *<nome> sem dupla* (AG7-04; o 7a só escreve 'todos' e 'nao'; inicio/fim são do 7b). O
-- alvo pela régua do *desfaz* (agenda_resolver_os: número ou nome, só a carteira); grava os_planejamento.dupla_dita, dupla_meios
-- (nulo), dupla_motivo e dupla_em (cria a linha se faltar, dias nulo), com o histórico, e a ação dupla (desfazível por
-- desfazer_validade; o ramo do *desfaz* é do P7). Nada no plano muda na hora: a próxima proposta usa. Dizer de novo o que já está
-- = "já estava", sem gravar nada. Só o administrador (_autor_da_agenda).
create or replace function public.agenda_dupla_dita(p_autor uuid, p_alvo text, p_dupla boolean, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config;
  v_autor  uuid;
  v_ro     jsonb;
  v_os     uuid;
  v_nome   text;
  v_old    public.os_planejamento%rowtype;
  v_novo   text;
  v_com    text;
  v_motivo text;
  v_antes  jsonb;
  v_depois jsonb;
  v_txt    text;
  v_acao   uuid;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_dupla_dita: sem o dia ou a hora' using errcode = '22004';
  end if;
  if p_dupla is null then
    raise exception 'agenda_dupla_dita: diga com ou sem dupla' using errcode = '22004';
  end if;
  v_autor := public._autor_da_agenda(p_autor);
  cf := public._agenda_cfg();
  v_ro := public.agenda_resolver_os(p_alvo, p_hoje);
  if coalesce(v_ro ->> 'status', '') <> 'ok' then
    return jsonb_build_object('ok', false, 'status', coalesce(v_ro ->> 'status', 'nao_achei'), 'texto', v_ro ->> 'texto',
                              'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
  end if;
  v_os := (v_ro ->> 'id')::uuid;
  v_nome := v_ro ->> 'cliente_curto';
  v_novo := case when p_dupla then 'todos' else 'nao' end;
  v_com := case when p_dupla then 'com' else 'sem' end;

  insert into public.os_planejamento (service_order_id) values (v_os) on conflict (service_order_id) do nothing;
  select * into v_old from public.os_planejamento where service_order_id = v_os for update;
  if v_old.dupla_dita is not distinct from v_novo and v_old.dupla_meios is null then
    return jsonb_build_object('ok', true, 'mudou', false, 'os', v_os, 'dupla_dita', v_novo,
                              'texto', format('%s já estava %s dupla.', v_nome, v_com));
  end if;

  v_motivo := left(format('você disse: %s %s dupla', v_nome, v_com), 80);
  v_antes := jsonb_build_object('dupla_dita', v_old.dupla_dita, 'dupla_meios', v_old.dupla_meios,
                                'dupla_motivo', v_old.dupla_motivo, 'dupla_em', v_old.dupla_em);
  v_depois := jsonb_build_object('dupla_dita', v_novo, 'dupla_meios', null, 'dupla_motivo', v_motivo, 'dupla_em', p_agora);
  v_txt := case when p_dupla
                then format('%s com dupla: nas próximas vezes que eu marcar, vão %s pessoas em cada meio-dia. *desfaz %s* volta.',
                            v_nome, greatest(cf.equipe_sugerida, 2), v_nome)
                else format('%s sem dupla: volto a %s.', v_nome,
                            case when cf.equipe_padrao = 1 then '1 pessoa' else cf.equipe_padrao || ' pessoas' end) end;

  update public.os_planejamento
     set dupla_dita = v_novo, dupla_meios = null, dupla_motivo = v_motivo, dupla_em = p_agora,
         historico = public._os_material_historico(v_old.historico, jsonb_build_object(
           'em', p_agora, 'autor', v_autor, 'por', 'dono', 'trecho', public._agenda_corta(format('%s %s dupla', p_alvo, v_com), 500),
           'antes', v_antes, 'depois', v_depois)),
         atualizado_em = p_agora, atualizado_por = v_autor
   where service_order_id = v_os;

  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto,
                                   motivo, autor, desfazivel_ate)
  values (p_agora, p_hoje, true, 'dono', 'dupla', v_os, array[v_os], v_antes, v_depois, left(public._agenda_corta(v_txt, 400), 400),
          v_motivo, v_autor, p_agora + cf.desfazer_validade)
  returning id into v_acao;

  return jsonb_build_object('ok', true, 'mudou', true, 'os', v_os, 'dupla_dita', v_novo, 'acao_id', v_acao, 'texto', v_txt);
end;
$function$;

comment on function public.agenda_dupla_dita(uuid, text, boolean, date, timestamptz) is
  'Agenda de Produção (Fase 7a, P2; AG7-04): a palavra *<nome> com dupla* (dupla_dita = todos: greatest(equipe_sugerida, 2) pessoas em cada meio-dia nas próximas marcações) ou *<nome> sem dupla* (nao: equipe_padrao). O alvo pelo agenda_resolver_os (só a carteira; ambíguo, fora ou não achado = {ok: false, texto do resolvedor}); grava dupla_dita, dupla_meios nulo, dupla_motivo e dupla_em em os_planejamento (cria a linha se faltar), com o histórico, e a ação dupla (origem dono, desfazível por desfazer_validade). O que já estava = "já estava", sem gravar. O plano não muda na hora. Só o administrador; security definer; só service_role.';

-- ── 4. Portas ──────────────────────────────────────────────────────────────────────────────────────────────────
-- As leituras novas (o nome do serviço, a peça embutida, a situação e a estimativa) são lidas por os_duracao_sugerida e
-- agenda_meios_da_os, que o painel (authenticated) e o service_role executam: execute para os dois, nunca anon. A palavra da dupla
-- grava (definer): só o service_role (o WhatsApp, pelo comando do P7), com o administrador conferido dentro.
revoke all on function public._agenda_nome_do_servico(text), public._agenda_peca_embutida(uuid),
  public._agenda_os_situacao(uuid, date), public._agenda_gestor_estimativa(uuid, date)
  from public, anon;
grant execute on function public._agenda_nome_do_servico(text), public._agenda_peca_embutida(uuid),
  public._agenda_os_situacao(uuid, date), public._agenda_gestor_estimativa(uuid, date)
  to authenticated, service_role;
revoke all on function public.agenda_dupla_dita(uuid, text, boolean, date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_dupla_dita(uuid, text, boolean, date, timestamptz) to service_role;

-- As recriadas mantêm as portas de antes (create or replace não as muda; repetidas aqui para a migration valer sozinha).
revoke all on function public.os_duracao_sugerida(uuid), public.agenda_meios_da_os(uuid, date) from public, anon;
grant execute on function public.os_duracao_sugerida(uuid), public.agenda_meios_da_os(uuid, date) to authenticated, service_role;

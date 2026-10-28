-- Agenda de Produção, Fase 6 ("Aprendizado"), pacote P4: a capacidade do dono no motor — quanto dos meios-dias dele marcados
-- no plano ele fez (a conferência), e, com o item ligado, a parte da semana dele que o motor compromete.
-- Spec: scratchpad agenda-pesquisa/spec-fase6.md (§3.1, §3.2, §3.3 d6, §5.4, §5.9, §6.2, §6.3). Depende de 20261029100300.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (2 funções novas; 3 recriadas; nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f6p4/montar-migration.mjs (as partes escritas à mão
-- f6p4/parte-0-cabeca.sql, parte-1-novas.sql e parte-9-portas.sql + as 3 recriadas, cada uma com o corpo da definição MAIS NOVA,
-- conferida com grep a cada montagem: fora dos blocos "-- FASE 6:" nenhuma linha muda). Edite o montador, nunca este .sql.
--
-- POR QUE: o motor marca até carga_max (80%) da semana de cada pessoa, o dono inclusive. O dono diz a capacidade dele (d04)
-- e isso continua sendo a base (agenda_disponibilidade); mas a conferência mostra quanto dos meios-dias dele marcados no
-- plano ele de fato fez. Este pacote mede isso e, com o item ligado, o motor passa a comprometer só essa parte da semana
-- dele (nunca abaixo de capacidade_dono_min, nunca acima de carga_max). A equipe não muda. Nada muda com o modo de
-- aprendizado fora de ligado ou sem "capacidade_dono" em aprendizado_ligados: o leitor único (_agenda_aprendido) devolve nulo
-- e vale o de hoje, byte a byte.
--
-- O QUE MUDA:
--   1. _agenda_aprender_capacidade(hoje, agora): as capacidade_semanas semanas ISO completas antes de hoje; por semana, os
--      meios-dias do dono no plano (presença turno, sem reserva; o vigente com o resultado da conferência, ou o cancelado por
--      ele — cancelada_motivo dono ou pessoa — quando o meio-dia não tem vigente): cumprido 1, parcial 0,5, não cumprido 0 SÓ
--      com o motivo em capacidade_motivos (só a falta dele conta: material, cliente, chuva e o resto saem da conta, como o
--      sem resultado e o sem registro). A semana conta com ≥ capacidade_meios_min; com ≥ capacidade_semanas_min semanas,
--      calculado = mediana(feitos ÷ planejados) × carga_max, preso em [capacidade_dono_min, carga_max]. Pelo gravador: item
--      capacidade_dono, chave e nível dono, padrão carga_max, detalhe {janela, de, ate, taxa, semanas, fora_do_plano (os
--      meios-dias das idas ditas), voce_disse (agenda_disponibilidade do dono)}.
--   2. _agenda_carga_da_pessoa(pessoa): o dono com capacidade_dono em uso → o valor (nunca acima de carga_max); os outros →
--      carga_max.
--   3. Recriadas (o corpo da definição mais nova + blocos "-- FASE 6:"):
--      · _agenda_contexto (de 20261025100200): depois do teto80 de sempre, a pessoa com outra carga (só o dono, com o item em
--        uso) ganha o teto floor(carga × esperado) em cada semana. A pessoa pp é v_pes[pp] (a ordem da grade: você primeiro) e
--        a semana ww dela é a posição (pp − 1) × nw + ww do teto80, a ordem do array_agg do teto de sempre;
--      · _agenda_validar_itens (de 20261025100200): a regra 6 com a carga de cada pessoa (_agenda_carga_da_pessoa) no lugar
--        de carga_max; o texto ("Gustavo passaria do limite da semana de 09/11: 6 meios-dias de serviço para 5.") não muda.
--        A regra 6 de antes fica logo abaixo, sem rodar (if false), para a conferência da cópia;
--      · _agenda_aprendizado_texto (de 20261029100300): os textos da capacidade (spec §6.2/§6.3) antes dos do fornecedor.
--
-- DESVIOS DA SPEC (provados em supabase/tests/agenda_fase6_dono.sql):
--   · A regra 6 mora em _agenda_validar_itens, não em agenda_validar (a spec §5.4 diz agenda_validar): agenda_validar só lê a
--     proposta e chama _agenda_validar_itens, que é também a conferência do próprio motor (agenda_propor). Recriei
--     _agenda_validar_itens; agenda_validar fica como está.
--   · O teto80 não troca a linha de antes: um laço depois dela reescreve só as semanas da pessoa com outra carga. Em teste, ou
--     ligado sem o item, o laço não escreve nada (a saída é a de antes, byte a byte).
--   · Por meio-dia, não por alocação: o meio-dia com um vigente e um cancelado (a troca de OS) conta uma vez, pelo vigente.
--   · O cancelado só conta depois de publicado (o que nunca esteve no plano não é falta).
--   · O parcial conta 0,5 de 1 qualquer que seja o motivo (como a spec; só o não cumprido passa pelo filtro do motivo).
--   · _agenda_carga_da_pessoa nunca devolve mais que carga_max (se a revisão da carga do P6 baixar a de todos, a do dono não
--     fica acima).
--   · O passo recebe p_agora (como no P2 e no P3).
--
-- O QUE NÃO MUDA: o que já está publicado (a regra 6 conta o vigente, mas só pesa nas alocações novas; a estabilidade do motor
-- não olha o teto); a equipe; o texto "não coube na carga de 80%" da reserva por teto em agenda_propor (fala da carga de
-- todos); a agenda_capacidade e o comprometível da Fase 1; o que o dono disse (agenda_disponibilidade). Nada roda sozinho: a
-- rodada é do P6 (agenda_aprender).
--
-- ORDEM DE LIGAR: depois de 20261029100300; antes de 20261029100500. Aplicar sozinha não muda nada para ninguém.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase6_dono.sql (a fixture-fase6 só na bancada; as portas e as cópias em
-- qualquer lugar). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261029100400
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261029100400_agenda_fase6_dono.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261029100400', 'agenda_fase6_dono');"
--
-- DESFAZER: reaplicar, em ordem, as definições de 20261025100200 (_agenda_contexto, _agenda_validar_itens) e de 20261029100300
-- (_agenda_aprendizado_texto); as 2 novas podem ficar (ninguém de antes as chama).
--
-- IDEMPOTENTE: create or replace function; revoke/grant.

-- ── 1. A capacidade do dono medida pela conferência ─────────────────────────────────────────────────────
-- As capacidade_semanas semanas ISO completas antes de hoje; por semana, os meios-dias do dono no plano (presença turno, sem
-- reserva): o vigente com o resultado da conferência, ou o cancelado por ele (cancelada_motivo dono ou pessoa, depois de
-- publicado). Por meio-dia: cumprido = 1 de 1; parcial = 0,5 de 1; não cumprido = 0 de 1 SÓ com o motivo em
-- capacidade_motivos (o que depende dele: a equipe faltou, outra urgência, o trabalho de antes, esqueceu); o não cumprido
-- por material, cliente, chuva, estimativa… sai da conta; sem resultado ou sem registro também (não há o que medir). O
-- cancelado só entra quando o meio-dia não tem vigente dele (a troca de OS no mesmo meio-dia conta uma vez). A semana conta
-- com pelo menos capacidade_meios_min meios-dias na conta. calculado = a mediana (feitos ÷ planejados) das semanas que
-- contam × carga_max, preso em [capacidade_dono_min, carga_max]; o padrão é carga_max (o que o motor usa hoje para todos).
create or replace function public._agenda_aprender_capacidade(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_dono   uuid := public._agenda_dono(null);
  v_seg    date;
  v_de     date;
  v_ate    date;
  v_semanas jsonb;
  v_amostra jsonb;
  v_taxas  numeric[];
  v_n      int;
  v_taxa   numeric;
  v_calc   numeric;
  v_fora   int;
  v_disse  jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  if v_dono is null then
    -- sem saber quem é o dono não há o que medir (nada é gravado)
    return jsonb_build_object('item', 'capacidade_dono', 'pulado', 'sem_dono');
  end if;
  v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1);
  v_de := v_seg - 7 * c.capacidade_semanas;
  v_ate := v_seg - 1;

  with a as (
    select x.dia, x.turno, x.estado in ('publicada', 'fixada') as vig,
           case when x.estado = 'cancelada' then 1
                when x.resultado in ('cumprido', 'parcial') then 1
                when x.resultado = 'nao_cumprido' and x.motivo = any (c.capacidade_motivos) then 1
                else 0 end as plan,
           case when x.estado = 'cancelada' then 0
                when x.resultado = 'cumprido' then 1
                when x.resultado = 'parcial' then 0.5
                else 0 end as feito
      from public.agenda_alocacoes x
     where x.payee_id = v_dono and x.presenca = 'turno' and x.tipo <> 'reserva'
       and x.dia between v_de and v_ate
       and (x.estado in ('publicada', 'fixada')
            or (x.estado = 'cancelada' and x.publicada_em is not null and x.cancelada_motivo in ('dono', 'pessoa')))
  ),
  meio as (
    -- um por meio-dia: o vigente, se houver; senão o cancelado
    select a.dia, a.turno,
           case when bool_or(a.vig) then max(a.plan) filter (where a.vig) else max(a.plan) end as plan,
           case when bool_or(a.vig) then max(a.feito) filter (where a.vig and a.plan = 1) else 0 end as feito
      from a group by a.dia, a.turno
  ),
  sem as (
    select m.dia - (extract(isodow from m.dia)::int - 1) as semana, sum(m.plan)::int as planejados,
           coalesce(sum(m.feito) filter (where m.plan = 1), 0) as feitos
      from meio m
     group by 1
    having sum(m.plan) > 0
  )
  select coalesce(jsonb_agg(jsonb_build_object('semana', s.semana, 'planejados', s.planejados, 'feitos', trim_scale(s.feitos),
                                               'conta', s.planejados >= c.capacidade_meios_min)
                            order by s.semana desc), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('semana', s.semana, 'planejados', s.planejados, 'feitos', trim_scale(s.feitos),
                                               'taxa', round(s.feitos / s.planejados, 2))
                            order by s.semana desc) filter (where s.planejados >= c.capacidade_meios_min), '[]'::jsonb),
         array_agg(s.feitos / s.planejados) filter (where s.planejados >= c.capacidade_meios_min),
         count(*) filter (where s.planejados >= c.capacidade_meios_min)::int
    into v_semanas, v_amostra, v_taxas, v_n
    from sem s;

  v_taxa := public._agenda_percentil(v_taxas, 0.5);
  v_calc := case when v_taxa is null then null
                 else greatest(c.capacidade_dono_min, least(c.carga_max, round(v_taxa * c.carga_max, 2))) end;

  -- os meios-dias em que ele foi sem estar no plano (as idas ditas; uma por OS e dia; o dia todo = 2)
  select coalesce(sum(q.meios), 0)::int into v_fora
    from (select i.service_order_id, i.dia, max(case i.dita when 'dia' then 2 else 1 end) as meios
            from public.agenda_intervencoes_do_dono i
           where i.dia between v_de and v_ate and i.dita in ('manha', 'tarde', 'dia')
           group by 1, 2) q;
  -- o que ele disse da semana dele (a base: o aprendido só reduz quanto dela o motor compromete)
  select coalesce(jsonb_agg(jsonb_build_object('dias_semana', d.dias_semana, 'periodo', d.periodo::text, 'turno', d.turno,
                                               'situacao', d.situacao, 'trecho', d.trecho)
                            order by d.periodo nulls first, d.dias_semana, d.turno nulls first, d.situacao, d.criado_em, d.id),
                  '[]'::jsonb)
    into v_disse
    from public.agenda_disponibilidade d
   where d.payee_id = v_dono and d.origem = 'dono' and d.substituida_em is null
     and (d.periodo is null or d.periodo && daterange(v_de, v_ate, '[]'));

  return public._agenda_aprendizado_gravar('capacidade_dono', 'dono', 'dono', v_calc, coalesce(v_n, 0), v_amostra,
           c.carga_max,
           jsonb_build_object('janela', c.capacidade_semanas, 'de', v_de, 'ate', v_ate, 'taxa', round(v_taxa, 2),
                              'semanas', v_semanas, 'fora_do_plano', v_fora, 'voce_disse', v_disse),
           p_agora);
end;
$function$;

comment on function public._agenda_aprender_capacidade(date, timestamptz) is
  'Agenda de Produção (Fase 6, P4): o passo da capacidade do dono da rodada — nas capacidade_semanas semanas ISO completas antes de p_hoje, os meios-dias do dono no plano (presença turno, sem reserva; o vigente com o resultado, ou o cancelado por ele — dono/pessoa — quando o meio-dia não tem vigente): cumprido 1, parcial 0,5, não cumprido 0 só com o motivo em capacidade_motivos (o resto sai da conta, como o sem resultado). A semana conta com ≥ capacidade_meios_min. calculado = mediana(feitos ÷ planejados) × carga_max, preso em [capacidade_dono_min, carga_max]; padrão carga_max; item capacidade_dono, chave e nível dono; detalhe {janela, de, ate, taxa, semanas[{semana, planejados, feitos, conta}], fora_do_plano (os meios-dias das idas ditas), voce_disse (agenda_disponibilidade do dono)}. Devolve o que o gravador devolve; sem dono, {pulado: sem_dono}. Lança no erro (a rodada isola). Sem grant a ninguém.';

-- ── 2. A carga de cada pessoa no motor ──────────────────────────────────────────────────────────────────
-- O dono com capacidade_dono em uso (o leitor único: modo_aprendizado ligado e capacidade_dono na lista; em uso, ou guardado
-- na pergunta e na trava) → o valor, nunca acima de carga_max; todo o resto → carga_max (o de hoje).
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
    v := public._agenda_aprendido('capacidade_dono', 'dono');
    if v is not null then
      return least(v, c.carga_max);
    end if;
  end if;
  return c.carga_max;
end;
$function$;

comment on function public._agenda_carga_da_pessoa(uuid) is
  'Agenda de Produção (Fase 6, P4): a parte da semana de uma pessoa que o motor compromete — o dono com capacidade_dono em uso (_agenda_aprendido: só com modo_aprendizado ligado e capacidade_dono na lista) → o valor, nunca acima de carga_max; os outros (e o dono sem nada em uso) → carga_max. Lida pelo teto80 de _agenda_contexto e pela regra 6 de _agenda_validar_itens.';

-- ── 4. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 6:") ──────────────────
-- Fora dos blocos nenhuma linha muda (o D5 do teste confere). Quem recriar de novo qualquer uma delas copia DESTA migration.

-- _agenda_aprendizado_texto (de 20261029100300_agenda_fase6_fornecedor.sql)
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
  'Agenda de Produção (Fase 6): os textos do aprendizado ao dono, do banco — p_momento foco_<estado> (a linha do foco), acao (o que mudou sozinho), pergunta (a troca grande, sem as opções), opcao1/2/3, desfeito e fico. p_d: {chave, calculado, em_uso, efetivo (o que valia antes), padrao, volta, n, n_min, desde, travado_ate, trava_dias}. O fator tem os textos da spec-fase6 §6.2/§6.3; os outros itens, um texto provisório que o pacote de cada um recria (copiar DESTA definição). FASE 6 (P2): o R$ por diária (mo) e a presença do dono têm os textos da spec §6.2/§6.3 (a presença lê detalhe.k, as idas do dono). FASE 6 (P3): o atraso (fornecedor_atraso) e o prazo da nota (fornecedor_prazo) têm os textos da spec §6.2/§6.3 (o nome, as entregas no prazo e o "você disse" vêm do detalhe). FASE 6 (P4): a capacidade do dono (capacidade_dono) tem os textos da spec §6.2/§6.3 ("Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus marcados no plano …"; a taxa e a janela vêm do detalhe).';

-- _agenda_contexto (de 20261025100200_agenda_fase2_motor.sql)
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

  -- O local de cada OS (a marina, senão a cidade do cliente), para o desempate "mesmo local".
  select coalesce(array_agg(q.loc order by q.o), '{}'::int[]) into v_loc
    from (select k.o, case when k.chave is null then 0 else dense_rank() over (order by k.chave)::int end as loc
            from (select u.o, coalesce('m:' || so.marina_id::text, 'c:' || nullif(lower(btrim(cl.city)), '')) as chave
                    from unnest(v_oss) with ordinality u(os, o)
                    left join public.service_orders so on so.id = u.os
                    left join public.clients cl on cl.id = so.client_id) k) q;

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
  'Agenda de Produção (Fase 2, P2): a grade do motor em arrays (agenda_grade de p_d_ini a p_d_fim, sem as alocações de p_ignorar): pessoas (você primeiro), dias úteis, semana ISO de cada dia, quem está livre em cada meio-dia (cap), as pontas livres do dono (curta: 1 abertura, 2 fechamento), o que o vigente ocupa (ocup, frentes: o índice da OS em oss, negativo = reserva), o uso por pessoa e semana (compromisso e reserva) e os tetos floor(carga_max × esperado) e floor(esperado) — o esperado só de dia útil (o sábado combinado não sobe o teto). As OS de p_fila vêm primeiro em oss. FASE 6 (P4): o teto80 de cada pessoa usa _agenda_carga_da_pessoa (o dono com capacidade_dono em uso: floor(carga dele × esperado); os outros, carga_max) — a posição (pp − 1) × nw + ww é a pessoa v_pes[pp] na semana ww; fora de ligado, a saída de antes.';

-- _agenda_validar_itens (de 20261025100200_agenda_fase2_motor.sql)
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

  -- (6) O teto por pessoa e semana: compromisso até carga_max (100% com acima_da_carga ou pedido do dono); com a
  -- reserva, até 100%. A presença curta do dono não conta. Só a semana que a proposta toca.
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
  'Agenda de Produção (Fase 2, P2): as 14 regras duras sobre os itens (criar e cancelar) de uma proposta, contra o banco de agora — (1) pessoa ativa e livre no turno (a ponta livre na presença curta, sem compromisso com hora), sem feriado; (2) sem choque com o vigente nem dentro da proposta; (3) não antes do dia em que fica pronta; (4) a presença do dono conforme a regra; (5) alguém em cada meio-dia; (6) o teto por pessoa e semana; (7) nada no congelado (salvo evento real e pedido do dono) nem no que começou; (8) o fixado só sai autorizado; (9) a OS na carteira; (10) classe 4 nunca; (11) reserva condicionada não vira compromisso; (12) wip_max por meio-dia; (13) no máximo interrupcoes_max dias parados; (14) com p_aplicar, item crítico só com a pergunta respondida. Lista vazia = ok; cada violação {regra, os, numero, pessoa, dia, turno, texto}. FASE 6 (P4): a regra 6 usa a carga de cada pessoa (_agenda_carga_da_pessoa: o dono com capacidade_dono em uso; os outros, carga_max) no lugar de carga_max; o texto não muda.';


-- ── 9. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- A leitura nova (invoker: a RLS de quem lê vale; quem não lê agenda_aprendizado recebe carga_max) para authenticated e
-- service_role, como _agenda_validar_itens (authenticated e service_role) e _agenda_contexto (service_role), que a chamam.
-- Nunca anon.
revoke all on function public._agenda_carga_da_pessoa(uuid) from public, anon;
grant execute on function public._agenda_carga_da_pessoa(uuid) to authenticated, service_role;

-- O passo da rodada: sem grant a ninguém, nem service_role (quem chama é a rodada do P6, agenda_aprender, definer).
revoke all on function public._agenda_aprender_capacidade(date, timestamptz) from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas de antes (create or replace não as muda; repetidas aqui para a migration valer sozinha).
revoke all on function public._agenda_aprendizado_texto(text, text, jsonb),
  public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb)
  from public, anon;
grant execute on function public._agenda_aprendizado_texto(text, text, jsonb),
  public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb)
  to authenticated, service_role;
revoke all on function public._agenda_contexto(date, date, date, uuid[], uuid[]) from public, anon, authenticated;
grant execute on function public._agenda_contexto(date, date, date, uuid[], uuid[]) to service_role;

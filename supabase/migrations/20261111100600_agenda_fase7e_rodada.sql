-- Agenda de Produção, Fase 7, etapa 7e ("A margem que aprende"), pacote P7: a rodada, a saúde e as leituras. A rodada das 16:00 passa a rodar a medição das compras, o congelado da
-- marcação e os 6 passos da margem, com relógio; a saúde ganha a chave margem; o foco aprendizado ganha o bloco 8 "Margem"; o cartão da OS ganha a estimativa com o viés e o prazo real.
-- Spec: scratchpad agenda-pesquisa/spec-fase7e.md (§5.6, §6.2–6.4 e o bloco R7, que vale sobre o corpo: R7.1, R7.3, R7.5-17, R7.5-18, R7.6, R7.8-2, R7.12, R7.13, R7.R); nomes: fase7-registro.md;
-- o registro do pacote: notas-fase7e.md, seção "## P7". Depende de 20261111100000 (P1) a 20261111100500 (P6). Copiado das definições MAIS NOVAS: agenda_aprender 20261029100900_agenda_fase6_correcao_calculo.sql:2784; agenda_saude 20261109101100_agenda_fase7f_cliente.sql:2543; _agenda_ver_aprendizado 20261029100950_agenda_fase6_correcao_textos.sql:1624; os_plano_da_os 20261107100700_agenda_fase7d_leituras.sql:935; _agenda_mudancas 20261030100500_agenda_correcao_revisao.sql:715; agenda_desfazer_dito 20261029100950_agenda_fase6_correcao_textos.sql:155.
--
-- ═══ NÃO APLICADA ═══ Existe para revisão e espera o OK (publicar/exec/aplicar.sh, nunca db push: esta versão fica antes das 20261116* que já estão em produção). Nenhuma coluna nem tabela nova.
--
-- POR QUE: do P2 ao P6 os passos da margem existem, mas nada os chama (agenda_aprender é de antes da 7e), e o que eles gravam não aparece em lugar nenhum (o foco listava as linhas da margem
-- sem bloco, numa ordem com empate; a saúde da Fase 6 contava os itens da margem como erro).
--
-- O QUE MUDA:
--   1. agenda_aprender: depois de medir, medir_compras e congelar_marcacao, sempre; depois dos passos da Fase 6, os 6 da margem (o viés antes da folga da semana, que lê o medido dele), cada
--      um com o interruptor dele fora de desligado pelo modo CRU (R7.6; a peça sem fornecedor, que não tem interruptor, vai com o tempo de compra) ou com linha em uso (o interruptor
--      desligado devolve a linha ao "em teste" na rodada seguinte), e só com modo_aprendizado fora de desligado. O relógio (R7.8-2): passou de aprender_tempo_max entre os passos, os da
--      margem que faltam ficam para amanhã e a rodada grava parou_no. query_canceled (o corte de 30 s do service_role) num passo: registra, grava a rodada com parou_no e encerra, e o
--      tique seguinte não repete (antes, a rodada inteira se desfazia, sem linha, e tentava de novo a cada tique). contagens ganha modos_margem (os 6 interruptores).
--   2. _agenda_saude_margem (nova) e agenda_saude: a chave margem (os zeros da §5.6, sem o promessa_antes_do_plano do R7.3-1, e os números), com zeros_ok no ok. E os itens da margem saem
--      dos zeros e das métricas do aprendizado da Fase 6, que não os conhecem (com a margem ligada, o "em uso fora de ligado" e a "troca grande sem pergunta" contavam cada passo dela).
--   3. _agenda_ver_aprendizado: o bloco 8 "Margem" (§6.2), numa ordem total, com o corte da §5.6 (as linhas dele saem antes das dos blocos 1–7, salvo as em uso).
--   4. os_plano_da_os: duracao.estimativa (§6.4: os 2 números, como o motor marca) e duracao.promessa (R7.3-1: o prazo real, só para o dono), ausentes sem nada a dizer.
--   5. _agenda_mudancas e agenda_desfazer_dito: as palavras da margem (R7.5-18): *desfaz aprendizado dias*, *semana* e *compra*.
--
-- O QUE NÃO MUDA: agenda_vigiar, agenda_cliente_vigiar, agenda_propor, os_prontidao e o motor não são recriados. Com os 6 interruptores desligados (como a 20261111100000 os deixa até o dado
-- 20261111100900), a rodada só soma medir_compras e congelar_marcacao (as tabelas da medição e o congelado da OS; nenhum leitor de antes muda), e o foco, o cartão, o "o que mudou" e a
-- saúde são os de antes, byte a byte, fora a chave nova margem. Em teste, o foco ganha o bloco 8 ("Em teste: …"; §6.2) e o cartão a estimativa em teste, quando há medido. Nenhuma
-- mensagem nova ao dono, à equipe ou ao cliente: o foco e o cartão são leituras; o "o que mudou" só ganha a palavra de cada item. Nada de dinheiro.
--
-- DESFAZER (na ordem):
--   cada recriada volta à versão anterior pelo corpo da origem acima (agenda_saude: a 20261109101100; os_plano_da_os: a 20261107100700; o resto, as de cada origem); depois:
--   drop function if exists public._agenda_saude_margem(date, timestamptz);

-- ── 1. A saúde da margem (nova) ───────────────────────────────────────────────────────────────────

-- Molde: _agenda_saude_comunicacao (7f) e _agenda_saude_local (7d): a porta, os zeros que entram no ok e os números. Sem os modos dentro: a chave não muda de um modo para o outro (o que os
-- modos fazem aparece nos zeros e nos números, e os interruptores estão na linha da config e em contagens.modos_margem da rodada).
create or replace function public._agenda_saude_margem(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  -- estrutural: os 6 itens da margem (§3.2; a lista de agenda_aprendizado_item_check, 20261111100000)
  c_itens   constant text[] := array['vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor'];
  c_janela  constant int := 28;   -- estrutural: os números "em 28 dias" (§5.6)
  c_semanas constant int := 6;    -- estrutural: as 6 semanas da carga (§5.6), a desta e as 5 seguintes
  cf        public.agenda_config;
  v_uid     uuid := auth.uid();
  v_papel   text;
  v_seg     date;
  v_z       jsonb;
  v_n       jsonb;
begin
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role (a porta de _agenda_saude_comunicacao).
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'A saúde da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'A saúde da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_saude_margem: sem o dia de hoje ou a hora' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1);
  -- Os zeros obrigatórios (entram no ok). As janelas são as dos zeros do aprendizado (aprender_saude_dias, aprender_atraso_h).
  v_z := jsonb_build_object(
    -- o passo do gravador maior que o limite do item: pela ação (antes.valor é o que valia; depois.em_uso, o novo). O histórico da linha não guarda o que valia quando o em uso era nulo (o
    -- padrão da classe do viés anda com o geral), e a ação guarda. Desligar o interruptor (o em uso volta ao padrão de uma vez, por decisão do dono) não é passo: não tem ação.
    'passo_maior_que_o_limite', (
       select count(*) from public.agenda_acoes a
        where a.tipo = 'aprendizado' and a.executada and a.antes ->> 'item' = any (c_itens)
          and a.criada_em > p_agora - make_interval(days => cf.aprender_saude_dias)
          and a.depois ->> 'em_uso' is not null and a.antes ->> 'valor' is not null
          and round(abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric), 2)
              > case a.antes ->> 'item' when 'folga_semana' then cf.folga_semana_troca_max
                                        when 'tempo_compra' then cf.fornecedor_troca_max_du
                                        when 'folga_compra' then cf.fornecedor_troca_max_du
                                        else cf.fator_troca_max end),
    -- o viés fora de [vies_min, vies_max], o prazo real fora de [promessa_min, fator_max], a folga da semana fora de [0, folga_semana_max]: o medido ou o em uso
    'fora_dos_limites', (
       select count(*) from public.agenda_aprendizado a
        where (a.item = 'vies' and ((a.calculado is not null and a.calculado not between cf.vies_min and cf.vies_max)
                                     or (a.em_uso is not null and a.em_uso not between cf.vies_min and cf.vies_max)))
           or (a.item = 'promessa' and ((a.calculado is not null and a.calculado not between cf.promessa_min and cf.fator_max)
                                         or (a.em_uso is not null and a.em_uso not between cf.promessa_min and cf.fator_max)))
           or (a.item = 'folga_semana' and ((a.calculado is not null and a.calculado not between 0 and cf.folga_semana_max)
                                             or (a.em_uso is not null and a.em_uso not between 0 and cf.folga_semana_max)))),
    -- o item da margem em uso com o interruptor dele fora de ligado (o modo cru, R7.6) há mais de aprender_atraso_h: a rodada seguinte o devolve ao "em teste" (agenda_aprender roda o
    -- passo do item em uso também com o interruptor desligado); a linha que fica em uso passado esse tempo é a rodada que não rodou ou não limpou. O leitor já não a usa (_agenda_margem_em_uso)
    -- Com o aprendizado desligado não se conta: a rodada não roda passo nenhum do aprendizado (nem os da Fase 6), a linha fica como estava e o leitor também não a usa.
    'em_uso_com_interruptor_fora', (
       select count(*) from public.agenda_aprendizado a
        where cf.modo_aprendizado <> 'desligado'
          and a.item = any (c_itens) and a.estado in ('em_uso', 'pergunta', 'travado') and a.em_uso is not null
          and coalesce(public._agenda_margem_modo_cru(a.item), 'desligado') <> 'ligado'
          and a.calculado_em < p_agora - make_interval(hours => cf.aprender_atraso_h)),
    -- alguma das 6 semanas (a desta e as 5 seguintes) com a carga fora de [carga_semana_min, carga_semana_max]: a carga que o motor e o validador leem (_agenda_carga_da_semana)
    'carga_semana_fora', (
       select count(*) from generate_series(0, c_semanas - 1) k
        where (public._agenda_carga_da_semana(v_seg + 7 * k) ->> 'carga')::numeric not between cf.carga_semana_min and cf.carga_semana_max),
    -- o puxar (P4b, com o tudo ou nada do P4c): de verdade, a OS puxada tem o compromisso novo em D e só perde as reservas publicadas dela mesma (a que vira compromisso, a que viola);
    -- a OS que fica fora não tem ação. Conta a ação de uma proposta do puxar (p_restricoes com puxar) que cancelou sem criar nada, cancelou alocação fixada ou cancelou o que não é
    -- reserva da própria OS (o defeito que o P4c consertou: a reserva fixada pelo dono cancelada, e a OS "puxada" sem compromisso)
    'puxar_cancelou', (
       select count(*) from public.agenda_acoes a
         join public.agenda_propostas pr on pr.id = a.proposta_id
        where a.executada and a.criada_em > p_agora - make_interval(days => cf.aprender_saude_dias)
          and pr.parametros -> 'p_restricoes' ? 'puxar'
          and cardinality(a.alocacoes_canceladas) > 0
          and (cardinality(a.alocacoes_criadas) = 0
               or exists (select 1 from jsonb_array_elements(coalesce(a.antes -> 'alocacoes', '[]'::jsonb)) x
                           where x ->> 'estado' is distinct from 'publicada')
               or exists (select 1 from public.agenda_alocacoes y
                           where y.id = any (a.alocacoes_canceladas)
                             and (y.tipo <> 'reserva' or y.service_order_id is distinct from a.service_order_id)))),
    -- 2 rodadas do gestor que rodaram o puxar no mesmo dia (o passo confere "já rodou hoje" pela mesma marca: contagens.puxar.rodou)
    'puxar_duas_vezes', (
       select count(*) from (select x.p_hoje from public.agenda_vigia_rodadas x
                              where x.rotina = 'gestor' and x.p_hoje > p_hoje - cf.aprender_saude_dias and x.p_hoje <= p_hoje
                                and x.contagens -> 'puxar' ->> 'rodou' = 'true'
                              group by x.p_hoje having count(*) > 1) d),
    -- dia útil, o puxar ligado ou em teste (o portão dele: modo_urgencia e modo_proposta fora de desligado, na linha) e o gestor rodando (algum dos 4 modos dele fora de desligado), e
    -- nenhuma rodada do gestor de hoje com o puxar rodado até puxar_hora + 1 hora (estrutural, §5.6: o puxar entra no 1º tique depois de puxar_hora)
    'rodada_puxar_atrasada', case
       when cf.modo_urgencia = 'desligado' or cf.modo_proposta = 'desligado' then 0
       when not public.agenda_dia_util(p_hoje) then 0
       when (p_agora at time zone 'America/Sao_Paulo')::time < cf.puxar_hora + interval '1 hour' then 0
       when public._agenda_gestor_modo('marcar') = 'desligado' and public._agenda_gestor_modo('encaixe') = 'desligado'
            and public._agenda_gestor_modo('revisao') = 'desligado' and public._agenda_gestor_modo('compre_ate') = 'desligado' then 0
       when exists (select 1 from public.agenda_vigia_rodadas x
                     where x.rotina = 'gestor' and x.p_hoje = p_hoje and x.contagens -> 'puxar' ->> 'rodou' = 'true') then 0
       else 1 end,
    -- a medida de compra de um orçamento que não está aprovado (agenda_medir_compra só mede a OS aprovada; o orçamento que voltou atrás leva a medida junto)
    'medida_compra_sem_aprovacao', (
       select count(*) from public.agenda_medidas_compra m
         join public.service_orders so on so.id = m.service_order_id
        where so.status = 'draft' and coalesce(so.quote_status, '') not in ('approved', 'awaiting_deposit')));
  -- Os números (nenhum reprova): n e estado por item e chave; os passos e as desfeitas em 28 dias; as puxadas (de verdade e em teste) e as urgentes encaixadas em 28 dias; as OS marcadas
  -- antes da compra e quantas começaram no dia marcado; a última rodada do aprendizado (onde parou, se parou).
  v_n := jsonb_build_object(
    'itens', coalesce((select jsonb_object_agg(t.item, t.chaves)
                         from (select a.item, jsonb_object_agg(a.chave, jsonb_build_object('estado', a.estado, 'n', a.n, 'n_min', a.n_min,
                                                                                          'calculado', a.calculado, 'em_uso', a.em_uso)) as chaves
                                 from public.agenda_aprendizado a where a.item = any (c_itens) group by a.item) t), '{}'::jsonb),
    'trocas_28d', jsonb_build_object(
      'passos', (select count(*) from public.agenda_acoes a
                  where a.tipo = 'aprendizado' and a.executada and a.antes ->> 'item' = any (c_itens)
                    and a.criada_em > p_agora - make_interval(days => c_janela)),
      'desfeitas', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'aprendizado' and a.antes ->> 'item' = any (c_itens) and a.desfeita_em > p_agora - make_interval(days => c_janela))),
    'puxadas_28d', (select count(*) from public.agenda_acoes a
                      join public.agenda_propostas pr on pr.id = a.proposta_id
                     where a.executada and pr.parametros -> 'p_restricoes' ? 'puxar' and cardinality(a.alocacoes_criadas) > 0
                       and a.criada_em > p_agora - make_interval(days => c_janela)),
    'puxadas_em_teste_28d', coalesce((select sum((x.contagens #>> '{puxar,puxadas}')::int) from public.agenda_vigia_rodadas x
                                       where x.rotina = 'gestor' and x.p_hoje > p_hoje - c_janela and x.p_hoje <= p_hoje
                                         and x.contagens #>> '{puxar,em_teste}' = 'true'), 0),
    'urgentes_28d', (select count(distinct al.service_order_id) from public.agenda_alocacoes al
                      where al.criado_em > p_agora - make_interval(days => c_janela) and al.estado in ('publicada', 'fixada')
                        and exists (select 1 from jsonb_array_elements_text(coalesce(al.motivos, '[]'::jsonb)) mo where mo like 'urgente:%')),
    'compras', (select jsonb_build_object('os_marcadas_antes_da_compra', count(distinct m.service_order_id) filter (where m.marcada_em is not null),
                                          'comecaram_no_dia_marcado', count(distinct m.service_order_id) filter (where m.marcada_em is not null and m.primeiro_dia_cumprido))
                  from public.agenda_medidas_compra m),
    'os_com_compra_pendente', (select count(*) from public.agenda_medidas_os m where m.compra_pendente),
    'ultima_rodada', (select jsonb_build_object('p_hoje', x.p_hoje, 'parou_no', x.contagens ->> 'parou_no')
                        from public.agenda_vigia_rodadas x where x.rotina = 'aprender'
                       order by x.p_agora desc, x.rodou_em desc, x.id desc limit 1));
  return jsonb_build_object('zeros_ok', not exists (select 1 from jsonb_each(v_z) z where (z.value)::text <> '0'), 'numeros', v_n) || v_z;
end;
$function$;

comment on function public._agenda_saude_margem(date, timestamptz) is
  'Agenda de Produção (Fase 7e, P7; §5.6, R7.5-17, R7.3-1): a chave margem de agenda_saude — os zeros obrigatórios (entram no ok; zeros_ok): passo_maior_que_o_limite (a ação da margem com |depois.em_uso − antes.valor| > o passo do item, em aprender_saude_dias), fora_dos_limites (viés, prazo real e folga da semana), em_uso_com_interruptor_fora (em uso com o interruptor cru fora de ligado há mais de aprender_atraso_h, com o aprendizado fora de desligado), carga_semana_fora (as 6 semanas, pela _agenda_carga_da_semana), puxar_cancelou (a ação do puxar que cancelou sem criar, cancelou fixada ou o que não é reserva da própria OS), puxar_duas_vezes, rodada_puxar_atrasada (até puxar_hora + 1 hora, com o portão do puxar e o gestor rodando) e medida_compra_sem_aprovacao (sem o promessa_antes_do_plano: AG7-32); e os números (itens, trocas_28d, puxadas_28d, puxadas_em_teste_28d, urgentes_28d, compras, os_com_compra_pendente, ultima_rodada). Sem os modos: a chave existe em todos e não muda de um modo para o outro. Definer, a porta de _agenda_saude_comunicacao (admin/financeiro ou service_role; 42501); sem o dia ou a hora, 22004.';

-- ── 2. As recriadas ───────────────────────────────────────────────────────────────────────────────

-- agenda_aprender (de 20261029100900_agenda_fase6_correcao_calculo.sql:2784; md5 do corpo de antes cabfb9a21da9885a4ad63fba35e20f5b)
create or replace function public.agenda_aprender(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_medir   constant text[] := array['congelar', 'medir'];
  c_passos  constant text[] := array['fator', 'mo', 'presenca', 'fornecedor', 'capacidade', 'cliente'];
  c_semana  constant text[] := array['revisao', 'solver'];
  cf        public.agenda_config;
  v_t0      timestamptz := clock_timestamp();
  v_semanal boolean;
  v_passo   text;
  v_r       jsonb;
  v_cont    jsonb := '{}'::jsonb;
  v_erros   int := 0;
  v_falhas  jsonb := '[]'::jsonb;
  v_estado  text;
  v_msg     text;
  -- FASE 7e: (7e P7, §5.6, R7.8-2) os 2 passos da medição que rodam sempre (depois de medir), os 6 da margem e onde a rodada parou
  c_7e_medir  constant text[] := array['medir_compras', 'congelar_marcacao'];
  c_7e_margem constant text[] := array['vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor'];
  v_7e_p      text;
  v_7e_parou  text;
  -- FASE 7e: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rodada do aprendizado.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_aprender'));
  cf := public._agenda_cfg();
  if (p_agora at time zone 'America/Sao_Paulo')::time < cf.aprender_hora then
    return jsonb_build_object('rodou', false, 'cedo', true, 'modo', cf.modo_aprendizado, 'hora', cf.aprender_hora);
  end if;
  if exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'aprender' and x.p_hoje = p_hoje) then
    return jsonb_build_object('rodou', false, 'ja_rodou', true, 'modo', cf.modo_aprendizado);
  end if;
  v_semanal := extract(isodow from p_hoje)::int = cf.dia_do_plano;
  -- CORREÇÃO FASE 6: (C1) item 13: a revisão da carga e o planejador mais forte rodam no dia do plano OU depois dele na mesma
  -- semana ISO, enquanto não houve nesta semana rodada semanal com o modo e a lista de agora (a quinta que não rodou, ou o
  -- dono que ligou a revisão na sexta: não espera a quinta seguinte). Uma vez por semana com o mesmo modo e a mesma lista.
  v_semanal := extract(isodow from p_hoje)::int >= cf.dia_do_plano
               and not exists (select 1 from public.agenda_vigia_rodadas x
                                where x.rotina = 'aprender'
                                  and x.p_hoje >= p_hoje - (extract(isodow from p_hoje)::int - 1) and x.p_hoje < p_hoje
                                  and coalesce((x.contagens ->> 'semanal')::boolean, false)
                                  and x.contagens ->> 'modo_aprendizado' = cf.modo_aprendizado
                                  and x.contagens -> 'ligados' = to_jsonb(cf.aprendizado_ligados));
  -- CORREÇÃO FASE 6: fim

  -- (1) a medição: sempre, em qualquer modo (só escreve as tabelas da Fase 6); (2) o aprendido: fora de desligado; (3) a
  -- revisão e o planejador mais forte: fora de desligado, no dia do plano
  foreach v_passo in array c_medir
                           || case when cf.modo_aprendizado <> 'desligado' then c_passos else '{}'::text[] end
                           || case when cf.modo_aprendizado <> 'desligado' and v_semanal then c_semana else '{}'::text[] end loop
    begin
      if v_passo = any (c_medir) then
        execute format('select public.%I($1)', '_agenda_aprender_' || v_passo) into v_r using p_hoje;
      else
        execute format('select public.%I($1, $2)', '_agenda_aprender_' || v_passo) into v_r using p_hoje, p_agora;
      end if;
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb));
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('aprendizado, passo %s: %s', v_passo, v_msg), 'agenda',
                                   'aprender:' || v_passo, 'error',
                                   jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje,
                                                      'p_agora', p_agora));
      -- FASE 7e: (7e P7, R7.8-2) when others não pega query_canceled (o corte de 30 s do service_role): sem isto a rodada inteira se desfazia, sem linha em agenda_vigia_rodadas, e
      -- tentava de novo a cada tique, atrasando a vigia. Agora, no molde de agenda_gestor_rodar: registra, grava a rodada com parou_no e encerra; o tique seguinte vê a rodada do dia e não repete.
      when query_canceled then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        v_erros := v_erros + 1;
        v_7e_parou := v_passo;
        v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
        perform public.log_app_error('db', format('aprendizado, passo %s: o tempo da rodada acabou (%s)', v_passo, v_msg), 'agenda',
                                     'aprender:' || v_passo, 'error',
                                     jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora,
                                                        'tempo_max', cf.aprender_tempo_max::text));
        exit;
      -- FASE 7e: fim
    end;
    -- FASE 7e: (7e P7, §5.6) depois de medir: medir_compras (as compras críticas: agenda_medidas_compra) e congelar_marcacao (o valor que valeu na marcação da OS), nesta ordem e sempre,
    -- em qualquer modo, como a medição de antes: só escrevem as tabelas da medição e o congelado da OS. O fornecedor (logo abaixo, na Fase 6) já lê as compras medidas, e o viés lê a marcação.
    if v_passo = 'medir' then
      foreach v_7e_p in array c_7e_medir loop
        begin
          execute format('select public.%I($1)', '_agenda_aprender_' || v_7e_p) into v_r using p_hoje;
          v_cont := v_cont || jsonb_build_object(v_7e_p, coalesce(v_r, '{}'::jsonb));
        exception
          when query_canceled then
            get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
            v_erros := v_erros + 1;
            v_7e_parou := v_7e_p;
            v_falhas := v_falhas || jsonb_build_object('passo', v_7e_p, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
            perform public.log_app_error('db', format('aprendizado, passo %s: o tempo da rodada acabou (%s)', v_7e_p, v_msg), 'agenda',
                                         'aprender:' || v_7e_p, 'error',
                                         jsonb_build_object('passo', v_7e_p, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora,
                                                            'tempo_max', cf.aprender_tempo_max::text));
            exit;
          when others then
            get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
            v_erros := v_erros + 1;
            v_falhas := v_falhas || jsonb_build_object('passo', v_7e_p, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
            perform public.log_app_error('db', format('aprendizado, passo %s: %s', v_7e_p, v_msg), 'agenda',
                                         'aprender:' || v_7e_p, 'error',
                                         jsonb_build_object('passo', v_7e_p, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
        end;
      end loop;
      exit when v_7e_parou is not null;
    end if;
    -- FASE 7e: fim
  end loop;

  -- FASE 7e: (7e P7, §5.6, R7.6, R7.8-2) os 6 passos da margem, depois dos da Fase 6, com modo_aprendizado fora de desligado: o viés antes da folga da semana (que lê o medido dele).
  -- Cada um entra com o interruptor dele fora de desligado, pelo modo CRU (R7.6: com o freio, ligado conta; promessa só pelo da linha, porque o efetivo dela é sombra sempre), ou com linha
  -- dele em uso (o interruptor desligado devolve a linha ao "em teste" na rodada seguinte, e a saúde não fica acusando um em uso que ninguém lê). A peça sem fornecedor não tem
  -- interruptor (é só medida): vai com o tempo de compra, a família das compras, como o fornecedor pela compra do P6. Com os 6 desligados e nenhuma linha em uso, nenhum roda.
  -- O relógio (aprender_tempo_max, conferido antes de cada um): passou, os que faltam ficam para amanhã e a rodada grava parou_no. query_canceled: como nos passos de cima.
  if v_7e_parou is null and cf.modo_aprendizado <> 'desligado' then
    foreach v_passo in array c_7e_margem loop
      continue when coalesce(public._agenda_margem_modo_cru(case when v_passo = 'prazo_sem_fornecedor' then 'tempo_compra' else v_passo end), 'desligado') = 'desligado'
                    and not exists (select 1 from public.agenda_aprendizado a where a.item = v_passo and a.em_uso is not null);
      if clock_timestamp() - v_t0 > cf.aprender_tempo_max then
        v_7e_parou := v_passo;
        exit;
      end if;
      begin
        execute format('select public.%I($1, $2)', '_agenda_aprender_' || v_passo) into v_r using p_hoje, p_agora;
        v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb));
      exception
        when query_canceled then
          get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
          v_erros := v_erros + 1;
          v_7e_parou := v_passo;
          v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
          perform public.log_app_error('db', format('aprendizado, passo %s: o tempo da rodada acabou (%s)', v_passo, v_msg), 'agenda',
                                       'aprender:' || v_passo, 'error',
                                       jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora,
                                                          'tempo_max', cf.aprender_tempo_max::text));
          exit;
        when others then
          get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
          v_erros := v_erros + 1;
          v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
          perform public.log_app_error('db', format('aprendizado, passo %s: %s', v_passo, v_msg), 'agenda',
                                       'aprender:' || v_passo, 'error',
                                       jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
      end;
    end loop;
  end if;
  v_cont := v_cont || jsonb_build_object('modos_margem', jsonb_build_object('vies', cf.modo_vies, 'folga_semana', cf.modo_folga_semana, 'urgencia', cf.modo_urgencia,
                                                                          'promessa', cf.modo_promessa, 'tempo_compra', cf.modo_tempo_compra,
                                                                          'folga_compra', cf.modo_folga_compra))
            || case when v_7e_parou is not null then jsonb_build_object('parou_no', v_7e_parou) else '{}'::jsonb end;
  -- FASE 7e: fim
  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                           rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia,
          v_cont || jsonb_build_object('modo_aprendizado', cf.modo_aprendizado, 'ligados', to_jsonb(cf.aprendizado_ligados),
                                       'semanal', v_semanal, 'falhas', v_falhas),
          least(v_erros, 32767), greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int),
          'aprender', cf.modo_equipe, cf.modo_diaria);

  return jsonb_build_object('rodou', true, 'modo', cf.modo_aprendizado, 'ligados', to_jsonb(cf.aprendizado_ligados),
                            'semanal', v_semanal, 'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas);
end;
$function$;

comment on function public.agenda_aprender(date, timestamptz) is
  'Agenda de Produção (Fase 6, P6): a rodada diária do aprendizado (spec-fase6 §5.6), pelo task-automations a cada tique — roda uma vez por dia, no 1º tique a partir de aprender_hora (antes = {rodou: false, cedo}; o 2º = {rodou: false, ja_rodou}). Passos, cada um no seu bloco (o que falha vai a app_error_logs, context agenda, action aprender:<passo>, e os outros seguem): (1) sempre, até com modo_aprendizado desligado, congelar e medir; (2) fora de desligado, fator, mo, presenca, fornecedor, capacidade e cliente (pelo gravador: em teste tudo fica sombra e nada é usado); (3) fora de desligado e no dia_do_plano, revisao (a carga pelo plano cumprido) e solver. Uma linha em agenda_vigia_rodadas (rotina aprender). {rodou, modo, ligados, semanal, contagens, erros, falhas}. Nenhuma mensagem. Só service_role. CORREÇÃO FASE 6 (C1, item 13): a revisão e o solver rodam no dia_do_plano ou depois dele na mesma semana ISO, enquanto não houve rodada semanal nesta semana com o modo e a lista de agora (semanal = isso). FASE 7e (P7, §5.6, R7.6, R7.8-2): depois de medir, medir_compras e congelar_marcacao, sempre; depois dos passos da Fase 6, os 6 da margem (vies, folga_semana, promessa, tempo_compra, folga_compra, prazo_sem_fornecedor), com modo_aprendizado fora de desligado e o interruptor de cada um (o cru; a peça sem fornecedor vai com o tempo de compra) fora de desligado ou linha dele em uso. O relógio aprender_tempo_max, antes de cada passo da margem: passou, a rodada grava parou_no e o resto fica para amanhã. query_canceled num passo: app_error_logs (aprender:<passo>), a rodada grava parou_no e encerra, e o tique seguinte não repete. contagens.modos_margem: os 6 interruptores.';

-- agenda_saude (de 20261109101100_agenda_fase7f_cliente.sql:2543; md5 do corpo de antes f8fce4dc30ff533daa172709a9b7b437)
create or replace function public.agenda_saude(p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf        public.agenda_config := public._agenda_cfg();
  v_cart    uuid[];
  v_ult     record;
  v_vig     jsonb;
  v_hoje    jsonb;
  v_crit    jsonb;
  v_perg    jsonb;
  v_prop    jsonb;
  v_plano   jsonb;
  v_inv     jsonb;
  v_fech    jsonb;
  v_sem     int;
  v_regra   jsonb;
  v_leu     boolean;
  v_choques int;
  -- FASE 3
  v_rot     jsonb;
  v_eq      jsonb;
  v_dia     jsonb;
  v_conc    jsonb;
  v_marcos  jsonb;
  v_com     jsonb;
  v_teto    int;
  v_janela  int;
  v_semconf int;
  v_sobre   int;
  v_semrec  int;
  v_pay     int;
  -- FASE 4: o material e a mensagem ao fornecedor
  v_mrod    jsonb;
  v_rem     jsonb;
  v_mperg   jsonb;
  v_semdono int;
  v_semorig int;
  v_prec    jsonb;
  v_det     jsonb;
  v_fsombra int;
  v_ffora   int;
  v_fteto   int;
  v_fproib  int;
  v_forn    jsonb;
  v_cob     jsonb;
  v_med     numeric;
  v_zeros4  boolean;
  v_mat     jsonb;
  -- FASE 4: fim
  -- FASE 5: a mensagem ao cliente
  v_crod    jsonb;
  v_cmsg    jsonb;
  v_caprov  jsonb;
  v_cjan    int;
  v_cdom    int;
  v_cteto   int;
  v_cint    int;
  v_cproib  int;
  v_csombra int;
  v_csemap  int;
  v_ccrit   int;
  v_cvesp   int;
  v_cdepois int;
  v_caudio  int;
  v_cmet    jsonb;
  v_zeros5  boolean;
  v_cli     jsonb;
  -- FASE 5: fim
  -- FASE 6: o aprendizado
  v_arod    record;
  v_apeq    int;
  v_afora   int;
  v_agrande int;
  v_aatras  int;
  v_asemcl  int;
  v_afat    int;
  v_amet    jsonb;
  v_zeros6  boolean;
  v_apr     jsonb;
  -- FASE 6: fim
  -- CORREÇÃO FASE 6: (C2) item 12: os zeros de antes do aprendizado (para o ok sair com as janelas de agenda_config)
  v_z4_antes boolean;
  -- FASE 7: (7a P7) o gestor da agenda
  v_ges     jsonb;
  v_gz      jsonb;
  v_gzeros  boolean;
  v_gdesde  timestamptz;
  v_gmodos  jsonb;
  v_gult    record;
  v_gr      jsonb;
  -- FASE 7: fim
  -- CORREÇÃO FASE 6: fim
begin
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k);

  select max(x.p_agora) as ultima, max(x.rodou_em) as rodou_em,
         count(*) filter (where x.p_agora > p_agora - interval '1 day' and x.p_agora <= p_agora) as n24,
         (array_agg(x.erros order by x.p_agora desc, x.rodou_em desc))[1] as erros_ult
    into v_ult from public.agenda_vigia_rodadas x
   -- FASE 3: a rotina da equipe grava na mesma tabela (rotina = 'rotina'); a vigia é só a dela.
   where x.rotina = 'vigia';
  v_vig := jsonb_build_object(
    'ultima_rodada', v_ult.ultima, 'rodou_em', v_ult.rodou_em,
    'rodou_nas_ultimas_2h', coalesce(v_ult.ultima > p_agora - interval '2 hours', false),
    'rodadas_24h', coalesce(v_ult.n24, 0), 'erros_ultima_rodada', coalesce(v_ult.erros_ult, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'));

  select jsonb_build_object(
           'publicar', count(*) filter (where a.executada and a.tipo = 'publicar'),
           'criar', count(*) filter (where a.executada and a.tipo = 'criar'),
           'mover', count(*) filter (where a.executada and a.tipo = 'mover'),
           'cancelar', count(*) filter (where a.executada and a.tipo = 'cancelar'),
           'promover', count(*) filter (where a.executada and a.tipo = 'promover_reserva'),
           'soltar', count(*) filter (where a.executada and a.tipo = 'soltar_reserva'),
           'status', count(*) filter (where a.executada and a.tipo = 'status'),
           'resultado', count(*) filter (where a.executada and a.tipo = 'resultado'),
           'desfeitas', count(*) filter (where a.executada and a.tipo = 'desfazer'),
           'sombra', count(*) filter (where not a.executada))
    into v_hoje from public.agenda_acoes a where a.dia = p_hoje;

  -- A prova: nenhuma ação crítica executada sem a decisão registrada (o gatilho impede; isto confere).
  select count(*) into v_sem
    from public.agenda_acoes a left join public.agenda_perguntas q on q.id = a.pergunta_id
   where a.executada and a.critica and (q.id is null or q.estado <> 'respondida' or q.opcao_escolhida is null);
  -- E o erro de classificação: ação autônoma executada como não crítica que a regra diz crítica.
  select jsonb_build_object('n', count(*), 'acoes', coalesce(jsonb_agg(a.id order by a.criada_em, a.id), '[]'::jsonb)) into v_regra
    from public.agenda_acoes a
   where a.executada and not a.critica and a.origem in ('motor', 'vigia', 'conferencia')
     and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
     and public._agenda_criticidade_da_acao(a.id) is not null;
  v_crit := jsonb_build_object(
    'abertas', (select count(*) from public.agenda_perguntas q where q.critica and q.estado = 'aberta'),
    'respondidas_7d', (select count(*) from public.agenda_perguntas q
                        where q.critica and q.estado = 'respondida' and q.respondida_em > p_agora - interval '7 days'),
    'sem_decisao', v_sem, 'pela_regra_sem_decisao', (v_regra ->> 'n')::int, 'pela_regra_acoes', v_regra -> 'acoes');

  v_perg := jsonb_build_object(
    'abertas_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select q.tipo, count(*) as n from public.agenda_perguntas q where q.estado = 'aberta' group by q.tipo) t), '{}'::jsonb),
    'abertas_sombra', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.modo = 'sombra'),
    'mostradas_hoje', (select count(*) from public.agenda_perguntas q
                        where (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  select jsonb_build_object(
           'abertas', count(*) filter (where p.estado = 'aberta'),
           'obsoletas_7d', count(*) filter (where p.estado = 'obsoleta' and p.criada_em > p_agora - interval '7 days'),
           'aplicadas_7d', count(*) filter (where p.estado = 'aplicada' and p.criada_em > p_agora - interval '7 days'),
           'sombra_7d', count(*) filter (where p.modo = 'sombra' and p.criada_em > p_agora - interval '7 days'))
    into v_prop from public.agenda_propostas p;

  select jsonb_build_object(
           'alocacoes_vigentes_futuras', count(*) filter (where a.dia >= p_hoje and a.resultado is null),
           'os_programadas', count(distinct a.service_order_id) filter (where a.dia >= p_hoje and a.resultado is null and a.tipo <> 'reserva'),
           'reservas', count(*) filter (where a.dia >= p_hoje and a.tipo = 'reserva'),
           'sem_registro_7d', count(*) filter (where a.resultado = 'sem_registro' and a.dia > p_hoje - 7))
    into v_plano from public.agenda_alocacoes a where a.estado in ('publicada', 'fixada');

  select count(*) into v_choques
    from public.agenda_alocacoes a join public.agenda_alocacoes b
      on b.payee_id = a.payee_id and b.id > a.id and b.periodo && a.periodo
   where a.estado in ('publicada', 'fixada') and b.estado in ('publicada', 'fixada');
  v_inv := jsonb_build_object(
    'vigente_de_os_fora_da_carteira', (select count(distinct a.service_order_id) from public.agenda_alocacoes a
                                        where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
                                          and not (a.service_order_id = any (v_cart))),
    'espelho_divergente', case when cf.modo_proposta <> 'ligado' then 0 else (
       select count(*) from public.service_orders so
        cross join lateral (select min(lower(a.periodo)) as ini, max(upper(a.periodo)) as fim from public.agenda_alocacoes a
                             where a.service_order_id = so.id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                               and a.resultado is distinct from 'nao_cumprido') m
        where so.id = any (v_cart)
          and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = so.id)
          and (so.scheduled_start_at is distinct from m.ini or so.scheduled_end_at is distinct from m.fim)) end,
    'choques', v_choques);

  if to_regclass('public.resumo_tarde') is not null then
    execute $q$select exists (select 1 from public.resumo_tarde t
                               where t.dia = $1 and jsonb_typeof(t.detalhe -> 'agenda') = 'object'
                                 and (t.detalhe -> 'agenda' ? 'linhas_diria' or t.detalhe -> 'agenda' ? 'linhas'))$q$
      into v_leu using p_hoje;
  end if;
  v_fech := jsonb_build_object(
    'leu_o_plano_hoje', v_leu,
    'linhas_mostradas', (select count(*) from public.agenda_acoes a
                          where a.contada_via = 'fechamento' and (a.contada_em at time zone 'America/Sao_Paulo')::date = p_hoje)
                        + (select count(*) from public.agenda_perguntas q
                            where q.mostrada_via = 'fechamento' and (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  -- FASE 3: a rotina, a equipe, as diárias, a conclusão, os marcos e a comissão. Os "0 obrigatórios": acima do teto, fora
  -- da janela, diária sem confirmação, turno sobrescrito pela agenda, conclusão sem cobrança quando devia, pagamento de
  -- comissão de técnico.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'rotina:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_rot from public.agenda_vigia_rodadas x where x.rotina = 'rotina';
  select count(*) into v_teto
    from (select m.payee_id, (m.enviar_em at time zone 'America/Sao_Paulo')::date as dia, m.tipo = 'resposta' as resp, count(*) as n
            from public.agenda_equipe_mensagens m
           where m.modo = 'ligado' and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
           group by 1, 2, 3) t
   where t.n > case when t.resp then cf.equipe_respostas_dia_max else cf.equipe_proativas_dia_max end;
  -- (revisão C1) pela regra única da janela (_agenda_equipe_fora_da_janela): a resposta direta tem a dela
  select count(*) into v_janela
    from public.whatsapp_send_queue q
    left join public.agenda_equipe_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-equipe'
     and (x.id is null
          or public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.scheduled_for) is not null
          -- o que SAIU fora da janela (o worker atrasado): também conta
          or (q.sent_at is not null and public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.sent_at) is not null));
  v_eq := jsonb_build_object(
    'mensagens_hoje_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select m.tipo, count(*) as n from public.agenda_equipe_mensagens m
         where (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.tipo) t), '{}'::jsonb),
    'recusadas_hoje_por_motivo', coalesce((select jsonb_object_agg(t.recusa_motivo, t.n) from (
        select m.recusa_motivo, count(*) as n from public.agenda_equipe_mensagens m
         where m.estado = 'recusada' and (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.recusa_motivo) t), '{}'::jsonb),
    'acima_do_teto', v_teto, 'fora_da_janela', v_janela);
  select count(*) into v_semconf
    from public.agenda_acoes a
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono' and a.desfeita_em is null
     and coalesce(public._agenda_confirmacao_do_dia(a.payee_id, (a.depois ->> 'dia')::date) ->> 'estado', '') <> 'confirmada';
  select count(*) into v_sobre
    from public.agenda_acoes a left join public.work_shifts ws on ws.id = a.work_shift_id
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono'
     and (coalesce(jsonb_typeof(a.antes -> 'turno'), 'null') <> 'null' or (ws.id is not null and ws.origem <> 'agente'));
  v_dia := jsonb_build_object(
    -- (o dia de quem agiu: a.dia é o p_hoje dele; criada_em é o relógio do banco)
    'lancadas_7d', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'diaria' and a.executada and a.origem <> 'dono' and a.dia > p_hoje - 7),
    'sombra_7d', (select count(*) from public.agenda_acoes a
                   where a.tipo = 'diaria' and not a.executada and a.dia > p_hoje - 7),
    'perguntas_abertas', (select count(*) from public.agenda_perguntas q where q.tipo in ('diaria', 'diaria_ligar') and q.estado = 'aberta'),
    'sem_confirmacao', v_semconf, 'sobrescreveu_turno', v_sobre);
  -- a conclusão pela porta sem cobrança viva quando a regra da condição dá parcelas ou título (a releitura é só service_role)
  if has_function_privilege('public._os_recebiveis_da_conclusao(uuid, date)', 'execute') then
    select count(*) into v_semrec
      from (select distinct so.id, so.check_out_at
              from public.agenda_acoes a join public.service_orders so on so.id = a.service_order_id
             where a.tipo = 'concluir' and a.executada and a.desfeita_em is null and so.status in ('completed', 'invoiced')
               and so.check_out_at is not null
               and not exists (select 1 from public.receivables r where r.service_order_id = so.id and r.status <> 'cancelled')) t
     where public._os_recebiveis_da_conclusao(t.id, (t.check_out_at at time zone 'America/Sao_Paulo')::date) ->> 'motivo'
           in ('parcelas', 'titulo_unico');
  end if;
  v_conc := jsonb_build_object(
    'pela_agenda_7d', (select count(*) from public.agenda_acoes a
                        where a.tipo = 'concluir' and a.executada and a.origem in ('equipe', 'dono')
                          and a.dia > p_hoje - 7),
    'desfeitas_7d', (select count(*) from public.agenda_acoes a
                      where a.tipo = 'concluir' and a.desfeita_em > p_agora - interval '7 days'),
    'sem_recebivel_quando_devia', v_semrec);
  select jsonb_build_object(
           'concluidas_30d', count(*),
           'entregues_em_ate_5du', count(*) filter (where so.delivered_at is not null
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date,
                                        (so.delivered_at at time zone 'America/Sao_Paulo')::date) <= cf.entrega_aviso_du),
           'sem_entrega_ha_mais_de_5du', count(*) filter (where so.delivered_at is null and so.status = 'completed'
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date, p_hoje) > cf.entrega_aviso_du))
    into v_marcos
    from public.service_orders so
   where so.check_out_at > p_agora - interval '30 days'
     and exists (select 1 from public.agenda_acoes a
                  where a.service_order_id = so.id and a.tipo = 'concluir' and a.executada and a.desfeita_em is null);
  select count(*) into v_pay
    from public.payables pa
   where pa.origin = 'commission' and pa.created_at > p_agora - interval '7 days'
     and pa.payee_id in (select w.payee_id from public.work_profiles w where w.modo_pagamento = 'diaria' and w.payee_id is not null);
  v_com := jsonb_build_object('pagamento', (select c.pagamento from public.comissao_config c where c.id),
                              'payables_de_comissao_tecnico_7d', v_pay);
  -- FASE 3: fim
  -- FASE 4: o material (a nota, o Pix, o detector, o cadastro) e a mensagem ao fornecedor. Os "0 obrigatórios": linha
  -- ligada a nota ou Pix sem a palavra do dono (vinculo_sem_resposta_do_dono), previsão sem o original guardado, e na
  -- mensagem ao fornecedor: nada na fila em sombra (ou sem a mensagem registrada), nada saindo ou que saiu fora da janela,
  -- nada acima do teto, nada com valor, pagamento, OS, link ou o nome do cliente.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'material:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_mrod from public.agenda_vigia_rodadas x where x.rotina = 'material';
  select jsonb_build_object(
           'a_caminho', count(*) filter (where r.estado = 'a_caminho'),
           'sem_resposta', count(*) filter (where r.vinculo = 'sem_resposta' and r.estado <> 'descartada'),
           'ligadas_7d', count(*) filter (where r.vinculo = 'ligada' and r.respondida_em > p_agora - interval '7 days'),
           'sem_servico_7d', count(*) filter (where r.vinculo = 'sem_servico' and r.respondida_em > p_agora - interval '7 days'),
           'chegaram_7d', count(*) filter (where r.estado = 'chegou' and r.chegou_em > p_hoje - 7))
    into v_rem from public.material_remessas r;
  v_mperg := jsonb_build_object(
    'abertas_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select q.tipo, count(*) as n from public.agenda_perguntas q
         where q.estado = 'aberta'
           and q.tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo')
         group by q.tipo) t), '{}'::jsonb),
    -- o teto do Pix (pix_perguntas_semana_max por semana ISO, no total), no modo de agora
    'pix_na_semana', (select count(*) from public.agenda_perguntas q
                       where q.tipo = 'pix_material'
                         and q.modo = case when cf.modo_material = 'ligado' then 'ligado' else 'sombra' end
                         and (q.criada_em at time zone 'America/Sao_Paulo')::date
                             between date_trunc('week', p_hoje)::date and date_trunc('week', p_hoje)::date + 6));
  -- a linha que a agenda ligou a uma nota ou a um Pix tem de ter a palavra do dono (ou a compra que ele já ligou)
  select count(*) into v_semdono
    from public.os_material m
   where (m.remessa_id is not null or m.fonte in ('nfe', 'pix'))
     and coalesce(m.evidencia ->> 'vinculo_por', '') not in ('dono', 'compra_ligada');
  select count(*) into v_semorig from public.os_material m where m.previsao_ate is not null and m.previsao_original is null;
  -- a precisão do detector é do administrador e do financeiro (para outro login ela lançaria 42501)
  if (select auth.uid()) is null or public.is_admin_or_financial((select auth.uid())) then
    v_prec := public.agenda_detector_precisao(p_hoje - 13, p_hoje);
  end if;
  v_det := jsonb_build_object(
    'sinais_14d', v_prec -> 'sinais', 'julgados_14d', v_prec -> 'julgados', 'certos_14d', v_prec -> 'certos',
    'precisao_14d', v_prec -> 'precisao', 'pronto_para_ligar', coalesce((v_prec ->> 'pronto_para_ligar')::boolean, false),
    'aplicados_7d', (select count(*) from public.material_sinais s where s.estado = 'aplicado' and s.dia > p_hoje - 7),
    'desfeitos_7d', (select count(*) from public.material_sinais s join public.agenda_acoes a on a.id = s.acao_id
                      where a.desfeita_em > p_agora - interval '7 days'));
  -- a mensagem ao fornecedor: o que entrou na fila sem a mensagem registrada em ligado (nada sai em sombra)
  select count(*) into v_fsombra
    from public.whatsapp_send_queue q
    left join public.agenda_fornecedor_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-fornecedor' and (x.id is null or x.modo <> 'ligado');
  v_fsombra := v_fsombra + (select count(*) from public.agenda_fornecedor_mensagens x
                             where x.modo <> 'ligado' and (x.fila_id is not null or x.estado = 'enfileirada'));
  -- o que está na fila, saindo ou saiu fora da janela da mensagem (pela regra única); o que falhou não saiu
  select count(*) into v_ffora
    from public.whatsapp_send_queue q
    join public.agenda_fornecedor_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-fornecedor'
     and ((q.status in ('pending', 'sending', 'sent')
           and public._agenda_fornecedor_fora_da_janela(x.enviar_em, q.scheduled_for) is not null)
          or (q.sent_at is not null and public._agenda_fornecedor_fora_da_janela(x.enviar_em, q.sent_at) is not null));
  -- acima do teto: o que entrou na fila (ligado), por fornecedor no dia e na semana ISO, e no dia a todos
  with ent as (
    select x.fornecedor_id as f, (x.enviar_em at time zone 'America/Sao_Paulo')::date as dia
      from public.agenda_fornecedor_mensagens x
     where x.modo = 'ligado'
       and (x.fila_id is not null
            or exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-fornecedor' and q.source_ref_id = x.id))
  )
  select (select count(*) from (select e.f, e.dia from ent e group by 1, 2 having count(*) > cf.fornecedor_dia_max) a)
       + (select count(*) from (select e.f, date_trunc('week', e.dia) from ent e group by 1, 2
                                 having count(*) > cf.fornecedor_semana_max) b)
       + (select count(*) from (select e.dia from ent e group by 1 having count(*) > cf.fornecedor_total_dia_max) t)
    into v_fteto;
  select count(*) into v_fproib
    from public.agenda_fornecedor_mensagens x
   where public._agenda_fornecedor_texto_proibido(x.texto, x.service_order_id) is not null;
  select jsonb_build_object(
           'registradas_7d', count(*),
           'enfileiradas_7d', count(*) filter (where x.estado = 'enfileirada'),
           'em_teste_7d', count(*) filter (where x.modo = 'sombra'),
           'recusadas_7d_por_motivo', coalesce((
             select jsonb_object_agg(t.recusa_motivo, t.n) from (
               select y.recusa_motivo, count(*) as n from public.agenda_fornecedor_mensagens y
                where y.estado = 'recusada' and (y.enviar_em at time zone 'America/Sao_Paulo')::date > p_hoje - 7
                group by y.recusa_motivo) t), '{}'::jsonb))
    into v_forn
    from public.agenda_fornecedor_mensagens x
   where (x.enviar_em at time zone 'America/Sao_Paulo')::date > p_hoje - 7;
  -- a cobertura: os itens críticos das OS que começam nas próximas material_inicio_dias, e quantos têm data (nível A a D)
  select jsonb_build_object(
           'itens_criticos_proximos', count(*),
           'com_previsao', count(*) filter (where e ->> 'nivel' <> 'E'),
           'pct', case when count(*) > 0 then round(100 * (count(*) filter (where e ->> 'nivel' <> 'E'))::numeric / count(*)) end)
    into v_cob
    from (select k.id from unnest(v_cart) k(id)
           where public._agenda_inicio_previsto(k.id, p_hoje) between p_hoje and p_hoje + cf.material_inicio_dias) o
    cross join lateral jsonb_array_elements(coalesce(public.os_prontidao(o.id, p_hoje) #> '{material,itens}', '[]'::jsonb)) e
   where coalesce((e ->> 'critico')::boolean, false);
  -- a espera: a mediana dos dias corridos da aprovação (a régua de os_carteira) até a 1ª compra (o dia dito ou o da OC),
  -- das OS aprovadas nos últimos 90 dias que já compraram
  select percentile_cont(0.5) within group (order by t.d) into v_med
    from (select min(coalesce(m.comprado_em, (po.created_at at time zone 'America/Sao_Paulo')::date))
                 - (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date as d
            from public.service_orders so
            join public.os_material m on m.service_order_id = so.id
            left join public.purchase_order_items poi on poi.id = m.purchase_order_item_id
            left join public.purchase_orders po on po.id = poi.purchase_order_id and po.status <> 'cancelled'
           where so.merged_into_id is null and so.status <> 'cancelled'
             and (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date
                 between p_hoje - 90 and p_hoje
           group by so.id
          having min(coalesce(m.comprado_em, (po.created_at at time zone 'America/Sao_Paulo')::date)) is not null) t;
  v_zeros4 := v_semdono = 0 and v_semorig = 0 and v_fsombra = 0 and v_ffora = 0 and v_fteto = 0 and v_fproib = 0;
  v_mat := jsonb_build_object(
    'modos', jsonb_build_object('material', cf.modo_material, 'detector', cf.modo_detector, 'fornecedor', cf.modo_fornecedor),
    'ultima_rodada', v_mrod -> 'ultima_rodada', 'rodou_nas_ultimas_2h', v_mrod -> 'rodou_nas_ultimas_2h',
    'erros_24h', v_mrod -> 'erros_24h',
    'remessas', v_rem, 'perguntas', v_mperg,
    'vinculo_sem_resposta_do_dono', v_semdono, 'previsao_sem_original', v_semorig,
    'detector', v_det,
    'fornecedor', v_forn || jsonb_build_object('na_fila_em_sombra', v_fsombra, 'fora_da_janela', v_ffora,
                                               'acima_do_teto', v_fteto, 'com_valor_ou_cliente', v_fproib),
    'cobertura', v_cob,
    'espera', jsonb_build_object('mediana_ate_comprar_90d', v_med));
  -- FASE 4: fim
  -- FASE 5: a mensagem ao cliente — o modo, as ondas e os tipos liberados, a rodada, as mensagens e a aprovação em 7 dias.
  -- Os "0 obrigatórios" (entram no ok pelo v_zeros4, para o ok ficar igual linha a linha): nada fora da janela (nem o que
  -- saiu fora dela), nada em feriado ou domingo, nada acima do teto, nada a menos do intervalo de outra, nada com texto
  -- proibido, nada na fila em teste, nada enviado sem a aprovação dos primeiros dias, nada crítico enviado sem a opção 2,
  -- nenhuma véspera com a OS aguardando peça, nenhum aviso de atraso depois da data dita, nenhum áudio que confirmou. As
  -- métricas não reprovam.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'cliente:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_crod from public.agenda_vigia_rodadas x where x.rotina = 'cliente';
  select coalesce(jsonb_object_agg(t.tipo, jsonb_build_object('registradas', t.reg, 'aguardando', t.agu, 'enviadas', t.env,
                                                              'recusadas_por_motivo', t.rec)), '{}'::jsonb)
    into v_cmsg
    from (select m.tipo, count(*) as reg, count(*) filter (where m.estado = 'aguardando_dono') as agu,
                 count(*) filter (where m.enviada_em is not null) as env,
                 coalesce((select jsonb_object_agg(y.recusa_motivo, y.n)
                             from (select z.recusa_motivo, count(*) as n from public.agenda_cliente_mensagens z
                                    where z.tipo = m.tipo and z.estado = 'recusada' and z.criada_em > p_agora - interval '7 days'
                                    group by z.recusa_motivo) y), '{}'::jsonb) as rec
            from public.agenda_cliente_mensagens m
           where m.criada_em > p_agora - interval '7 days'
           group by m.tipo) t;
  select jsonb_build_object(
           'pedidas_abertas', count(*) filter (where m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')),
           'vencidas_7d', count(*) filter (where m.aprovacao = 'vencida' and m.criada_em > p_agora - interval '7 days'),
           'aprovadas_7d', count(*) filter (where m.aprovacao = 'aprovada' and m.aprovada_em > p_agora - interval '7 days'),
           'seguradas_7d', count(*) filter (where m.aprovacao = 'segurada' and m.aprovada_em > p_agora - interval '7 days'))
    into v_caprov from public.agenda_cliente_mensagens m where m.modo = 'ligado';
  -- a janela (a regra única): o que está na fila, saindo ou saiu fora da janela da mensagem; o feriado e o domingo à parte
  select count(*) filter (where t.f is not null), count(*) filter (where t.f in ('feriado', 'domingo'))
    into v_cjan, v_cdom
    from (select coalesce(case when q.status in ('pending', 'sending', 'sent')
                               then public._agenda_cliente_fora_da_janela(x.enviar_em, q.scheduled_for) end,
                          case when q.sent_at is not null then public._agenda_cliente_fora_da_janela(x.enviar_em, q.sent_at) end) as f
            from public.whatsapp_send_queue q
            join public.agenda_cliente_mensagens x on x.id = q.source_ref_id
           where q.source = 'agenda-cliente') t;
  -- o teto: o que entrou na fila (ligado), por cliente no dia e na semana ISO, e no dia a todos
  with ent as (
    select m.client_id as c, (m.enviar_em at time zone 'America/Sao_Paulo')::date as dia
      from public.agenda_cliente_mensagens m
     where m.modo = 'ligado' and m.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')
  )
  select (select count(*) from (select e.c, e.dia from ent e group by 1, 2 having count(*) > cf.cliente_dia_max) a)
       + (select count(*) from (select e.c, date_trunc('week', e.dia) from ent e group by 1, 2
                                 having count(*) > cf.cliente_semana_max) b)
       + (select count(*) from (select e.dia from ent e group by 1 having count(*) > cf.cliente_total_dia_max) t)
    into v_cteto;
  -- o intervalo: duas linhas agenda-cliente (na fila, saindo ou saídas) a menos de cliente_intervalo_min_s uma da outra
  select count(*) into v_cint
    from public.whatsapp_send_queue a
    join public.whatsapp_send_queue b
      on b.source = 'agenda-cliente' and b.id > a.id and b.status in ('pending', 'sending', 'sent')
     and abs(extract(epoch from coalesce(b.sent_at, b.scheduled_for) - coalesce(a.sent_at, a.scheduled_for)))
         < cf.cliente_intervalo_min_s
   where a.source = 'agenda-cliente' and a.status in ('pending', 'sending', 'sent');
  select count(*) into v_cproib
    from public.agenda_cliente_mensagens m where public._agenda_cliente_texto_proibido(m.texto) is not null;
  -- em teste nada entra na fila (nem linha da fila sem a mensagem registrada em ligado)
  select (select count(*) from public.whatsapp_send_queue q
            left join public.agenda_cliente_mensagens x on x.id = q.source_ref_id
           where q.source = 'agenda-cliente' and (x.id is null or x.modo <> 'ligado'))
       + (select count(*) from public.agenda_cliente_mensagens x
           where x.modo <> 'ligado' and (x.fila_id is not null or x.enviada_em is not null
                                         or x.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')))
    into v_csombra;
  -- enviada sem a aprovação do dono quando o tipo ainda não somava os dias aprovados (ou a preparada pelo dono)
  select count(*) into v_csemap
    from public.agenda_cliente_mensagens m
   where m.modo = 'ligado' and m.enviada_em is not null and m.aprovacao <> 'aprovada'
     and (m.origem <> 'rodada'
          or (cf.cliente_aprovacao_dias > 0
              and (select count(distinct (y.aprovada_em at time zone 'America/Sao_Paulo')::date)
                     from public.agenda_cliente_mensagens y
                    where y.tipo = m.tipo and y.aprovacao = 'aprovada' and y.origem = 'rodada' and y.modo = 'ligado'
                      and y.aprovada_em < m.criada_em) < cf.cliente_aprovacao_dias));
  -- a crítica enviada sem a decisão "2) eu mando o aviso escrito"
  select count(*) into v_ccrit
    from public.agenda_cliente_mensagens m
    left join public.agenda_perguntas q on q.id = m.pergunta_id
   where m.enviada_em is not null
     and (m.aprovacao = 'critica'
          or (q.tipo = 'cliente_aviso' and not (q.estado = 'respondida' and q.opcao_escolhida = 2)));
  -- a véspera (M2/M4) enviada com a OS aguardando peça (no registro, ou pela última mudança de status antes do envio)
  select count(*) into v_cvesp
    from public.agenda_cliente_mensagens m
   where m.tipo in ('vespera', 'acesso') and m.enviada_em is not null
     and (m.base ->> 'status' = 'awaiting_parts'
          or (select a.status_depois from public.agenda_acoes a
               where a.service_order_id = m.service_order_id and a.tipo = 'status' and a.executada
                 and a.criada_em <= m.enviada_em
               order by a.criada_em desc, a.id desc limit 1) = 'awaiting_parts');
  -- o aviso de atraso enviado depois da data que o cliente ouviu
  select count(*) into v_cdepois
    from public.agenda_cliente_mensagens m
   where m.tipo = 'pode_atrasar' and m.enviada_em is not null and m.base ? 'prometido_ate'
     and (m.enviada_em at time zone 'America/Sao_Paulo')::date > (m.base ->> 'prometido_ate')::date;
  select count(*) into v_caudio
    from public.agenda_cliente_respostas r where r.tipo_msg = 'audio' and r.efeito = 'confirmou';
  -- as métricas (para depois; nenhuma reprova)
  select jsonb_build_object(
    'm6_antes_da_data_pct_90d', (
      select case when count(*) > 0 then round(100 * (count(*) filter (
               where (m.enviada_em at time zone 'America/Sao_Paulo')::date <= (m.base ->> 'prometido_ate')::date))::numeric
               / count(*)) end
        from public.agenda_cliente_mensagens m
       where m.tipo = 'pode_atrasar' and m.enviada_em > p_agora - interval '90 days' and m.base ? 'prometido_ate'),
    'aprovadas_sem_segurar_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where m.aprovacao = 'aprovada'))::numeric / count(*)) end
        from public.agenda_cliente_mensagens m
       where m.modo = 'ligado' and m.aprovacao in ('aprovada', 'segurada') and m.aprovada_em > p_agora - interval '30 days'),
    'resposta_24h_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where r.recebida_em <= m.enviada_em + interval '1 day'))::numeric
               / count(*)) end
        from public.agenda_cliente_mensagens m
        left join public.agenda_cliente_respostas r on r.id = m.resposta_id
       where m.modo = 'ligado' and m.enviada_em > p_agora - interval '30 days'
         and m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')),
    'sim_automatico_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where r.efeito = 'confirmou'))::numeric / count(*)) end
        from public.agenda_cliente_respostas r
       where r.modo = 'ligado' and r.recebida_em > p_agora - interval '30 days' and r.intencao = 'confirma'),
    'opt_outs_30d', (select count(*) from public.agenda_cliente_respostas r
                      where r.intencao = 'opt_out' and r.recebida_em > p_agora - interval '30 days'),
    'falhas_de_entrega_30d', (select count(*) from public.whatsapp_send_queue q
                               where q.source = 'agenda-cliente' and q.status = 'failed'
                                 and q.created_at > p_agora - interval '30 days'),
    'idas_perdidas_por_acesso_90d', (
      select jsonb_build_object('com_aviso', count(*) filter (where t.avisado), 'sem_aviso', count(*) filter (where not t.avisado))
        from (select distinct a.service_order_id, a.dia,
                     exists (select 1 from public.agenda_cliente_mensagens m
                              where m.service_order_id = a.service_order_id and m.tipo in ('vespera', 'acesso')
                                and m.enviada_em is not null and coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) = a.dia) as avisado
                from public.agenda_alocacoes a
               where a.resultado = 'nao_cumprido' and a.motivo = 'cliente_ou_bem' and a.dia > p_hoje - 90 and a.dia <= p_hoje) t))
    into v_cmet;
  v_zeros5 := v_cjan = 0 and v_cdom = 0 and v_cteto = 0 and v_cint = 0 and v_cproib = 0 and v_csombra = 0 and v_csemap = 0
              and v_ccrit = 0 and v_cvesp = 0 and v_cdepois = 0 and v_caudio = 0;
  v_zeros4 := v_zeros4 and v_zeros5;
  v_cli := jsonb_build_object(
    'modo', cf.modo_cliente, 'tipos_ligados', to_jsonb(cf.cliente_tipos_ligados),
    'tipos_liberados', to_jsonb(array(select t from unnest(array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento',
                                                                  'pode_atrasar', 'nova_data', 'pronto', 'pronto_lembrete',
                                                                  'pos_servico', 'mudanca_no_dia']) t
                                       where public._agenda_cliente_tipo_liberado(t))),
    'ultima_rodada', v_crod -> 'ultima_rodada', 'rodou_nas_ultimas_2h', v_crod -> 'rodou_nas_ultimas_2h',
    'erros_24h', v_crod -> 'erros_24h',
    'mensagens_7d', jsonb_build_object('por_tipo', v_cmsg),
    'aprovacao', v_caprov,
    'fora_da_janela', v_cjan, 'em_feriado_ou_domingo', v_cdom, 'acima_do_teto', v_cteto, 'intervalo_curto', v_cint,
    'com_texto_proibido', v_cproib, 'na_fila_em_sombra', v_csombra, 'sem_aprovacao_no_periodo', v_csemap,
    'critica_sem_decisao', v_ccrit, 'vespera_com_os_aguardando_peca', v_cvesp, 'aviso_depois_da_data', v_cdepois,
    'audio_que_confirmou', v_caudio,
    'metricas', v_cmet);
  -- FASE 5: fim
  -- CORREÇÃO FASE 6: (C2) item 12: os zeros obrigatórios de antes do aprendizado (o bloco do aprendizado os junta aos dele; o
  -- bloco da C2 depois dele refaz essa junta com as janelas de agenda_config)
  v_z4_antes := v_zeros4;
  -- CORREÇÃO FASE 6: fim
  -- FASE 6: (P6) o aprendizado (spec-fase6 §11) — o modo, a lista, a rodada, os itens e as métricas. Os "0 obrigatórios"
  -- (entram no ok pelo v_zeros4, como os das Fases 4 e 5): nada em uso com menos medidas que o mínimo; nada que a ÚLTIMA
  -- rodada gravou em uso com o modo dela fora de ligado ou o item fora da lista dela (logo depois de o dono desligar, o leitor
  -- já devolve o padrão; a linha muda na rodada seguinte); nenhuma troca grande que entrou sozinha (as ações da vigia em 7 dias
  -- contra os limites de hoje: a regra de _agenda_aprendizado_troca_cabe, que não tem porta para quem lê a saúde); nenhuma
  -- rodada atrasada (depois da 1ª, nenhuma em 26 h); nenhuma medida sem classe; nenhum fator fora de [fator_min, fator_max].
  -- Os erros de aprender:% em 24 h e as métricas não reprovam.
  select x.p_agora, x.p_hoje, x.contagens into v_arod
    from public.agenda_vigia_rodadas x where x.rotina = 'aprender'
   order by x.p_agora desc, x.rodou_em desc, x.id desc limit 1;
  select count(*) into v_apeq
    from public.agenda_aprendizado a
   where a.estado in ('em_uso', 'pergunta', 'travado') and a.em_uso is not null and a.n < a.n_min;
  select count(*) into v_afora
    from public.agenda_aprendizado a
   where v_arod.p_agora is not null and a.estado = 'em_uso' and a.em_uso is not null and a.calculado_em >= v_arod.p_agora
     and (coalesce(v_arod.contagens ->> 'modo_aprendizado', '') <> 'ligado'
          or not coalesce(v_arod.contagens -> 'ligados' ? public._agenda_aprendizado_da_lista(a.item), false));
  select count(*) into v_agrande
    from public.agenda_acoes a
   where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada and a.criada_em > p_agora - interval '7 days'
     and not coalesce(case a.antes ->> 'item'
           when 'fator' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.fator_troca_max
           when 'mo' then (a.antes ->> 'valor')::numeric > 0
                          and abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                              / (a.antes ->> 'valor')::numeric <= cf.mo_troca_max
           when 'fornecedor_atraso' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                         <= cf.fornecedor_troca_max_du
           when 'fornecedor_prazo' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                        <= cf.fornecedor_troca_max_du
           when 'capacidade_dono' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                       <= cf.capacidade_troca_max
           when 'aviso_folga' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.aviso_troca_max_du
           when 'presenca' then a.antes ->> 'nivel' in ('fina', 'sistema')
         end, false);
  v_aatras := case when v_arod.p_agora is not null and v_arod.p_agora < p_agora - interval '26 hours' then 1 else 0 end;
  select count(*) into v_asemcl from public.agenda_medidas_os m where m.classe_bem is null or m.classe_sistema is null;
  select count(*) into v_afat
    from public.agenda_aprendizado a
   where a.item = 'fator'
     and ((a.calculado is not null and a.calculado not between cf.fator_min and cf.fator_max)
          or (a.em_uso is not null and a.em_uso not between cf.fator_min and cf.fator_max));
  -- as métricas (para depois; nenhuma reprova)
  select jsonb_build_object(
    'itens', coalesce((select jsonb_object_agg(t.item, jsonb_build_object('chaves', t.chaves, 'n_max', t.n_max, 'n_min', t.n_min,
                                                                         'estados', t.estados))
                         from (select a.item, count(*) as chaves, max(a.n) as n_max, max(a.n_min) as n_min,
                                      (select jsonb_object_agg(s.estado, s.n)
                                         from (select b.estado, count(*) as n from public.agenda_aprendizado b
                                                where b.item = a.item group by b.estado) s) as estados
                                 from public.agenda_aprendizado a group by a.item) t), '{}'::jsonb),
    'medidas', (select jsonb_build_object('total', count(*), 'validas', count(*) filter (where m.valida),
                                          'invalidas', coalesce((select jsonb_object_agg(y.motivo, y.n)
                                                                   from (select z.motivo, count(*) as n from public.agenda_medidas_os z
                                                                          where not z.valida
                                                                            and z.concluida_em > p_hoje - cf.aprender_janela_dias
                                                                          group by z.motivo) y), '{}'::jsonb))
                  from public.agenda_medidas_os m where m.concluida_em > p_hoje - cf.aprender_janela_dias),
    'trocas_30d', jsonb_build_object(
      'sozinhas', (select count(*) from public.agenda_acoes a
                    where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada and a.criada_em > p_agora - interval '30 days'),
      'perguntas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.criada_em > p_agora - interval '30 days'),
      'decididas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.estado = 'respondida' and q.respondida_em > p_agora - interval '30 days'),
      'desfeitas', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - interval '30 days')),
    -- o erro do fator: das OS válidas concluídas depois que o fator da classe delas passou a valer, quantas ficaram dentro dele
    'erro_do_fator', (select case when count(*) > 0 then jsonb_build_object('dentro', count(*) filter (where t.fator <= t.uso),
                                                                           'medidas', count(*),
                                                                           'pct', round(100 * (count(*) filter (where t.fator <= t.uso))::numeric / count(*))) end
                        from (select m.fator, u.em_uso as uso
                                from public.agenda_medidas_os m
                                cross join lateral (
                                  select a.em_uso, a.em_uso_desde from public.agenda_aprendizado a
                                   where a.item = 'fator' and a.estado = 'em_uso'
                                     and a.chave in (m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                     'bem:' || m.classe_bem, 'todas')
                                   order by array_position(array[m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                                 'bem:' || m.classe_bem, 'todas'], a.chave)
                                   limit 1) u
                               where m.valida and m.concluida_em >= (u.em_uso_desde at time zone 'America/Sao_Paulo')::date) t),
    -- a pontualidade com o cliente antes e depois de a folga do aviso valer
    'pontualidade_folga', (select case when f.desde is not null then jsonb_build_object(
                                     'desde', f.desde,
                                     'antes_pct', (select round(100 * avg((m.atraso_cliente_du <= 0)::int)) from public.agenda_medidas_os m
                                                    where m.atraso_cliente_du is not null and m.concluida_em < f.desde),
                                     'depois_pct', (select round(100 * avg((m.atraso_cliente_du <= 0)::int)) from public.agenda_medidas_os m
                                                     where m.atraso_cliente_du is not null and m.concluida_em >= f.desde)) end
                             from (select (min(a.em_uso_desde) at time zone 'America/Sao_Paulo')::date as desde
                                     from public.agenda_aprendizado a where a.item = 'aviso_folga' and a.em_uso is not null) f),
    -- parar (§11): o item que o dono desfez 2 vezes em 4 semanas (recomendar tirá-lo da lista; a decisão é dele)
    'desfeito_2x_em_4_semanas', coalesce((select jsonb_agg(t.item order by t.item)
                                            from (select a.antes ->> 'item' as item from public.agenda_acoes a
                                                   where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - interval '28 days'
                                                   group by 1 having count(distinct a.desfeita_em) >= 2) t), '[]'::jsonb))
    into v_amet;
  v_zeros6 := v_apeq = 0 and v_afora = 0 and v_agrande = 0 and v_aatras = 0 and v_asemcl = 0 and v_afat = 0;
  v_zeros4 := v_zeros4 and v_zeros6;
  v_apr := jsonb_build_object(
    'modo', cf.modo_aprendizado, 'ligados', to_jsonb(cf.aprendizado_ligados),
    'ultima_rodada', v_arod.p_agora,
    'rodou_hoje', exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'aprender' and x.p_hoje = p_hoje),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'aprender:%'
                     and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'em_uso_com_amostra_pequena', v_apeq, 'em_uso_fora_de_ligado', v_afora, 'troca_grande_sem_pergunta', v_agrande,
    'rodada_atrasada', v_aatras, 'medida_sem_classe', v_asemcl, 'fator_fora_dos_limites', v_afat,
    'metricas', v_amet);
  -- FASE 6: fim
  -- CORREÇÃO FASE 6: (C2) item 12: as janelas do aprendizado na saúde vêm de agenda_config (eram números escritos aqui): a
  -- troca grande que entrou sozinha, nas ações dos últimos aprender_saude_dias (era 7 dias); a rodada atrasada, sem rodada há
  -- mais de aprender_atraso_h (era 26 h); as trocas das métricas, nos últimos aprender_parar_dias (era 30 dias; a chave
  -- trocas_30d fica com o nome); o item desfeito 2 vezes dentro de aprender_trava_dias (era 28 dias, as "4 semanas" da §11).
  -- As contas de cima não valem mais: refeitas aqui com o parâmetro (com os DEFAULTs, o mesmo resultado), e com elas os
  -- zeros, o ok e o bloco aprendizado.
  select count(*) into v_agrande
    from public.agenda_acoes a
   where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada
     and a.criada_em > p_agora - make_interval(days => cf.aprender_saude_dias)
     and not coalesce(case a.antes ->> 'item'
           when 'fator' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.fator_troca_max
           when 'mo' then (a.antes ->> 'valor')::numeric > 0
                          and abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                              / (a.antes ->> 'valor')::numeric <= cf.mo_troca_max
           when 'fornecedor_atraso' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                         <= cf.fornecedor_troca_max_du
           when 'fornecedor_prazo' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                        <= cf.fornecedor_troca_max_du
           when 'capacidade_dono' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                       <= cf.capacidade_troca_max
           when 'aviso_folga' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.aviso_troca_max_du
           when 'presenca' then a.antes ->> 'nivel' in ('fina', 'sistema')
         end, false);
  v_aatras := case when v_arod.p_agora is not null
                        and v_arod.p_agora < p_agora - make_interval(hours => cf.aprender_atraso_h) then 1 else 0 end;
  v_amet := v_amet || jsonb_build_object(
    'trocas_30d', jsonb_build_object(
      'sozinhas', (select count(*) from public.agenda_acoes a
                    where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada
                      and a.criada_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'perguntas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.criada_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'decididas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.estado = 'respondida'
                       and q.respondida_em > p_agora - make_interval(days => cf.aprender_parar_dias)),
      'desfeitas', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - make_interval(days => cf.aprender_parar_dias))),
    'desfeito_2x_em_4_semanas', coalesce((select jsonb_agg(t.item order by t.item)
                                            from (select a.antes ->> 'item' as item from public.agenda_acoes a
                                                   where a.tipo = 'aprendizado'
                                                     and a.desfeita_em > p_agora - make_interval(days => cf.aprender_trava_dias)
                                                   group by 1 having count(distinct a.desfeita_em) >= 2) t), '[]'::jsonb));
  -- (7e P7; §5.6, R7.5-17, a correção do P4; marca sem FASE porque está dentro do bloco da correção C2 da Fase 6) os itens da margem têm os zeros e os números deles na chave margem
  -- (_agenda_saude_margem, no fim): aqui eles saem dos zeros e das métricas do aprendizado da Fase 6, que não os conhecem. Sem isso, com a margem ligada, o "em uso fora de ligado" contava
  -- todo item da margem recalculado na última rodada (_agenda_aprendizado_da_lista é nula para eles: nunca estão em aprendizado_ligados), a "troca grande sem pergunta" contava toda ação
  -- da margem (o case não os conhece) e o "em uso com amostra pequena" contava a folga da semana que volta ao padrão por passo sem medida (R7.4): o ok da saúde cairia a cada passo.
  -- Cada conta tira exatamente o que a de cima contou dos itens da margem (as mesmas condições). Sem linha nem ação da margem, tira 0 e as métricas são as de antes, byte a byte.
  v_apeq := v_apeq - (select count(*) from public.agenda_aprendizado a
                       where a.item = 'folga_semana' and a.calculado is null
                         and a.estado in ('em_uso', 'pergunta', 'travado') and a.em_uso is not null and a.n < a.n_min);
  v_afora := v_afora - (select count(*) from public.agenda_aprendizado a
                         where a.item in ('vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor')
                           and v_arod.p_agora is not null and a.estado = 'em_uso' and a.em_uso is not null and a.calculado_em >= v_arod.p_agora
                           and (coalesce(v_arod.contagens ->> 'modo_aprendizado', '') <> 'ligado'
                                or not coalesce(v_arod.contagens -> 'ligados' ? public._agenda_aprendizado_da_lista(a.item), false)));
  v_agrande := v_agrande - (select count(*) from public.agenda_acoes a
                             where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada
                               and a.criada_em > p_agora - make_interval(days => cf.aprender_saude_dias)
                               and a.antes ->> 'item' in ('vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor'));
  v_apr := v_apr || jsonb_build_object('em_uso_com_amostra_pequena', v_apeq, 'em_uso_fora_de_ligado', v_afora);
  v_amet := v_amet || jsonb_build_object(
    'itens', coalesce((select jsonb_object_agg(t.item, jsonb_build_object('chaves', t.chaves, 'n_max', t.n_max, 'n_min', t.n_min,
                                                                         'estados', t.estados))
                         from (select a.item, count(*) as chaves, max(a.n) as n_max, max(a.n_min) as n_min,
                                      (select jsonb_object_agg(s.estado, s.n)
                                         from (select b.estado, count(*) as n from public.agenda_aprendizado b
                                                where b.item = a.item group by b.estado) s) as estados
                                 from public.agenda_aprendizado a where a.item not in ('vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor') group by a.item) t), '{}'::jsonb));
  -- (7e: fim)
  v_zeros6 := v_apeq = 0 and v_afora = 0 and v_agrande = 0 and v_aatras = 0 and v_asemcl = 0 and v_afat = 0;
  v_zeros4 := v_z4_antes and v_zeros6;
  v_apr := v_apr || jsonb_build_object('troca_grande_sem_pergunta', v_agrande, 'rodada_atrasada', v_aatras, 'metricas', v_amet);
  -- CORREÇÃO FASE 6: fim
  -- FASE 7: (7a P7, spec §11) o bloco gestor: os modos efetivos, a última rodada (rotina gestor), os erros de gestor:% em 24 h, os
  -- zeros obrigatórios (entram no ok, salvo prazo_vencido_sem_mostrar, que só se conta: a pergunta fica aberta) e os números. Os
  -- zeros do que o gestor muda sozinho contam a partir do OK de ligar (marcar_sozinho_desde): antes dele não há o que contar.
  -- E (aviso do P6) o erro do fator só com as medidas que têm fator: a medida por estimativa é válida e não tem fator.
  v_gdesde := cf.marcar_sozinho_desde;
  v_gmodos := jsonb_build_object('marcar', public._agenda_gestor_modo('marcar'), 'encaixe', public._agenda_gestor_modo('encaixe'),
                                 'revisao', public._agenda_gestor_modo('revisao'), 'compre_ate', public._agenda_gestor_modo('compre_ate'),
                                 'vaga', public._agenda_gestor_modo('vaga'), 'so_propor', cf.gestor_so_propor, 'desde', v_gdesde);
  select max(x.p_agora) as ultima,
         count(*) filter (where x.p_agora > p_agora - interval '1 day' and x.p_agora <= p_agora) as n24,
         coalesce(bool_or(x.p_hoje = p_hoje and x.contagens ? 'diaria'), false) as diaria_hoje,
         (array_agg(x.erros order by x.p_agora desc, x.rodou_em desc))[1] as erros_ult
    into v_gult from public.agenda_vigia_rodadas x where x.rotina = 'gestor';
  v_gz := jsonb_build_object(
    -- o dia que o cliente ouviu e o dia que a equipe já sabia, mudados sem a pergunta crítica (a regra de _agenda_criticidade_da_acao)
    'zona_travada_mexida', (select count(*) from public.agenda_acoes a
                             where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                               and a.origem in ('motor', 'vigia', 'conferencia')
                               and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
                               and public._agenda_criticidade_da_acao(a.id) = 'dia_prometido'),
    'dia_avisado_sem_pergunta', (select count(*) from public.agenda_acoes a
                                  where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                                    and a.origem in ('motor', 'vigia', 'conferencia')
                                    and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
                                    and public._agenda_criticidade_da_acao(a.id) = 'dia_avisado'),
    -- marcada pela estimativa sem a pergunta que ela pedia (grande, começada/parada, sem mão de obra, peça embutida)
    'estimativa_sem_pergunta', case when not public._agenda_gestor_regra('estimativa') then 0 else (
       select count(*) from (select distinct a.service_order_id as os from public.agenda_alocacoes a
                               left join public.os_planejamento pl on pl.service_order_id = a.service_order_id
                              where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
                                and a.resultado is null and a.duracao_fonte = 'orcamento' and pl.dias is null) o
        where coalesce(public._agenda_gestor_estimativa(o.os, p_hoje) ->> 'motivo', '') in ('grande', 'situacao', 'sem_base', 'embutida')) end,
    'prazo_em_critica', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.critica and q.veto_ate is not null),
    'prazo_em_dia_prometido', (select count(*) from public.agenda_perguntas q
                                where q.estado = 'aberta' and q.veto_ate is not null and q.tipo = 'dia_prometido'),
    -- aprovada há mais de aprovada_sem_data_min sem dia, sem reserva, sem pergunta aberta e sem o motor ter dito por que fica de
    -- fora depois da aprovação (com o encaixe na aprovação ligado: antes dele, quem encaixa é a vigia e a publicação)
    'aprovada_sem_data', case when public._agenda_gestor_modo('encaixe') <> 'ligado' then 0 else (
       select count(*) from public.os_carteira(p_hoje) k join public.service_orders so on so.id = k.service_order_id
        where coalesce(so.converted_to_os_at, so.signed_at) is not null
          and coalesce(so.converted_to_os_at, so.signed_at) < p_agora - make_interval(mins => cf.aprovada_sem_data_min)
          and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = k.service_order_id
                           and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null)
          and not exists (select 1 from public.agenda_perguntas q where q.estado = 'aberta' and q.service_order_id = k.service_order_id)
          and not exists (select 1 from public.agenda_propostas pr cross join lateral jsonb_array_elements(coalesce(pr.fora, '[]'::jsonb)) f
                           where pr.criada_em >= coalesce(so.converted_to_os_at, so.signed_at)
                             and (f ->> 'os')::uuid = k.service_order_id)) end,
    -- sem rodada do gestor em 40 min, de 07:30 a 21:00 de dia útil, com algum modo do gestor fora de desligado
    'rodada_gestor_atrasada', case when (v_gmodos ->> 'marcar' <> 'desligado' or v_gmodos ->> 'encaixe' <> 'desligado'
                                         or v_gmodos ->> 'revisao' <> 'desligado' or v_gmodos ->> 'compre_ate' <> 'desligado')
                                        and public.agenda_dia_util(p_hoje)
                                        and (p_agora at time zone 'America/Sao_Paulo')::time between time '07:30' and time '21:00'
                                        and coalesce(v_gult.ultima < p_agora - interval '40 minutes', true) then 1 else 0 end,
    -- a mensagem ao cliente por estimativa que saiu sem o sim do dono antes de somar cliente_aprovacao_dias dias aprovados
    'cliente_estimativa_sem_aprovacao', (
       select count(*) from public.agenda_cliente_mensagens m
        where v_gdesde is not null and m.criada_em >= v_gdesde and m.base -> 'dados' ->> 'por_estimativa' = 'true'
          and m.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta') and m.aprovacao <> 'aprovada'
          and (select count(distinct (n.aprovada_em at time zone 'America/Sao_Paulo')::date) from public.agenda_cliente_mensagens n
                where n.tipo = m.tipo and n.base -> 'dados' ->> 'por_estimativa' = 'true' and n.aprovacao = 'aprovada'
                  and n.aprovada_em < m.criada_em) < cf.cliente_aprovacao_dias),
    -- a ficha de um dia por estimativa que saiu na janela de veto sem a pergunta ficha_estimativa mostrada (ou segurada com 2)
    'ficha_estimativa_sem_veto', (
       select count(*) from public.agenda_equipe_mensagens em
        where v_gdesde is not null and em.tipo = 'ficha' and em.modo = 'ligado'
          and em.estado in ('enfileirada', 'respondida', 'sem_resposta')
          and em.dia >= (v_gdesde at time zone 'America/Sao_Paulo')::date
          and em.dia < (v_gdesde at time zone 'America/Sao_Paulo')::date + cf.ficha_veto_dias
          and exists (select 1 from public.agenda_alocacoes a where a.payee_id = em.payee_id and a.dia = em.dia
                       and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.duracao_fonte = 'orcamento')
          and not exists (select 1 from public.agenda_perguntas q
                           where q.chave = 'ficha_estimativa:' || em.payee_id || ':' || em.dia and q.mostrada_vezes > 0
                             and q.opcao_escolhida is distinct from 2)),
    -- a rodada que mudou o dia de mais de gestor_k_os OS de uma vez sem a pergunta onda
    'onda_aplicada_sem_pergunta', (
       select count(*) from (select a.proposta_id from public.agenda_acoes a
                               where v_gdesde is not null and a.criada_em >= v_gdesde and a.executada and not a.critica
                                 and a.origem in ('motor', 'vigia') and a.tipo = 'mover' and a.proposta_id is not null
                               group by a.proposta_id having count(distinct a.service_order_id) > cf.gestor_k_os) p
        where not exists (select 1 from public.agenda_perguntas q where q.tipo = 'onda' and q.proposta_id = p.proposta_id)),
    -- o compromisso novo sem de onde veio a duração (o gatilho _agenda_alocacao_fonte grava em toda alocação nova)
    'alocacao_sem_fonte', (select count(*) from public.agenda_alocacoes a
                            where v_gdesde is not null and a.criado_em >= v_gdesde and a.tipo <> 'reserva' and a.duracao_fonte is null),
    -- a ação do gestor feita numa rodada em que o modo dela não estava ligado (estimar: marcar; reestimar e reparar: revisao)
    'regra_em_sombra_aplicada', (
       select count(*) from public.agenda_acoes a
        where a.executada and a.origem = 'vigia' and a.tipo in ('estimar', 'reestimar', 'reparar')
          and a.criada_em > p_agora - interval '7 days'
          and coalesce((select r.contagens -> 'modos' ->> case when a.tipo = 'estimar' then 'marcar' else 'revisao' end
                          from public.agenda_vigia_rodadas r
                         where r.rotina = 'gestor' and r.p_agora <= a.criada_em
                         order by r.p_agora desc, r.rodou_em desc limit 1), 'desligado') <> 'ligado'),
    -- a pergunta com prazo vencido que o dono nunca viu antes do prazo: fica aberta (aqui só se conta; não entra no ok)
    'prazo_vencido_sem_mostrar', (select count(*) from public.agenda_perguntas q
                                   where q.estado = 'aberta' and q.veto_ate is not null and q.veto_ate < p_agora
                                     and not coalesce(q.mostrada_vezes > 0 and q.mostrada_em < q.veto_ate, false)));
  -- (7f P7; R2, P2b, AG7-15; dentro do bloco do gestor da 7a: por isso a marca, não o bloco) prazo_em_critica: desde a 7f a crítica pode ter prazo e vencer (AG7-15, "sem resposta
  -- fica como ele propôs"). O zero passa a ser o prazo em crítica que nunca venceria: fora de veto_tipos ou com veto_espera. Hoje, 0 críticas na história: 0 nos dois jeitos.
  v_gz := v_gz || jsonb_build_object('prazo_em_critica', (select count(*) from public.agenda_perguntas q
                                                         where q.estado = 'aberta' and q.critica and q.veto_ate is not null
                                                           and (not q.tipo = any (cf.veto_tipos) or q.veto_espera is not null)));
  -- (7f: fim)
  v_gzeros := not exists (select 1 from jsonb_each(v_gz) z where z.key <> 'prazo_vencido_sem_mostrar' and (z.value)::text <> '0');
  v_ges := jsonb_build_object(
    'modos', v_gmodos, 'regras', to_jsonb(cf.marcar_regras),
    'ultima_rodada', v_gult.ultima, 'rodadas_24h', coalesce(v_gult.n24, 0), 'diaria_hoje', coalesce(v_gult.diaria_hoje, false),
    'erros_ultima_rodada', coalesce(v_gult.erros_ult, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'gestor:%' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'zeros_ok', v_gzeros,
    'numeros', jsonb_build_object(
      'os_por_estimativa', (select count(distinct a.service_order_id) from public.agenda_alocacoes a
                             where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
                               and a.resultado is null and a.duracao_fonte = 'orcamento'),
      'perguntas_com_prazo', jsonb_build_object(
        'abertas', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.veto_ate is not null),
        'vencidas', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.veto_ate is not null and q.veto_ate < p_agora),
        'respondidas_7d', (select count(*) from public.agenda_perguntas q where q.estado = 'respondida' and q.veto_ate is not null
                             and q.respondida_em > p_agora - interval '7 days'),
        'pelo_prazo_7d', (select count(*) from public.agenda_acoes a where a.tipo = 'estimar' and a.origem = 'vigia' and a.executada
                            and a.criada_em > p_agora - interval '7 days')),
      'compre_ate', jsonb_build_object(
        'gravados', (select count(*) from public.os_material m where m.compre_ate is not null),
        'cobrados', (select count(*) from public.os_material m where m.cobrado_vezes > 0),
        'empurrados', (select count(*) from public.os_material m where m.empurrada_vezes > 0)),
      'fichas_seguradas_7d', (select count(*) from public.agenda_equipe_mensagens em
                               where em.recusa_motivo = 'veto' and em.criada_em > p_agora - interval '7 days'))) || v_gz;
  v_amet := v_amet || jsonb_build_object(
    'erro_do_fator', (select case when count(*) > 0 then jsonb_build_object('dentro', count(*) filter (where t.fator <= t.uso),
                                                                           'medidas', count(*),
                                                                           'pct', round(100 * (count(*) filter (where t.fator <= t.uso))::numeric / count(*))) end
                        from (select m.fator, u.em_uso as uso
                                from public.agenda_medidas_os m
                                cross join lateral (
                                  select a.em_uso, a.em_uso_desde from public.agenda_aprendizado a
                                   where a.item = 'fator' and a.estado = 'em_uso'
                                     and a.chave in (m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                     'bem:' || m.classe_bem, 'todas')
                                   order by array_position(array[m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                                 'bem:' || m.classe_bem, 'todas'], a.chave)
                                   limit 1) u
                               where m.valida and m.fator is not null
                                 and m.concluida_em >= (u.em_uso_desde at time zone 'America/Sao_Paulo')::date) t));
  v_apr := v_apr || jsonb_build_object('metricas', v_amet);
  v_gr := jsonb_build_object(
    -- os zeros obrigatórios da execução (a Fase 3), do material e da mensagem ao fornecedor (a Fase 4) e os do gestor entram no ok
    'ok', v_sem = 0 and (v_regra ->> 'n')::int = 0 and v_choques = 0
          and v_teto = 0 and v_janela = 0 and v_semconf = 0 and v_sobre = 0 and coalesce(v_semrec, 0) = 0 and v_pay = 0
          and v_zeros4
          and v_gzeros,
    'modos', jsonb_build_object('leitura', cf.modo_leitura, 'proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
    'vigia', v_vig, 'hoje', v_hoje, 'criticas', v_crit, 'perguntas', v_perg, 'propostas', v_prop, 'plano', v_plano,
    'invariantes', v_inv, 'fechamento', v_fech,
    'rotina', v_rot, 'equipe', v_eq, 'diarias', v_dia, 'conclusao', v_conc, 'marcos', v_marcos, 'comissao', v_com,
    'modos_fase3', jsonb_build_object('equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
    'cliente', v_cli,
    'aprendizado', v_apr,
    'material', v_mat,
    'gestor', v_ges);
  -- FASE 7b (P5, §5.4, R4.3(g); dentro do bloco do gestor da 7a, que monta a saída e volta aqui — por isso sem os dois-pontos depois
  -- de "7b": os tiradores de antes tiram o bloco do gestor inteiro e não o leem como bloco próprio): a chave equipe_dias
  -- (_agenda_saude_equipe7b: as mensagens dias à equipe, a dupla no plano, quem nunca fica sozinho, o sábado, o dono numa vaga e a
  -- resposta gravada), com os zeros obrigatórios no ok. Sem os modos da 7b, os zeros são 0 e o ok é o de antes.
  v_gr := v_gr || jsonb_build_object('equipe_dias', public._agenda_saude_equipe7b(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{equipe_dias,zeros_ok}')::boolean, true)));
  -- FASE 7b (P5): fim
  -- (7d P8; §11, R6.3-11; dentro do bloco do gestor: por isso a marca, não o bloco) a chave local (_agenda_saude_local), com os zeros obrigatórios no ok. Sem os modos da 7d, os
  -- zeros são 0 e o ok é o de antes.
  v_gr := v_gr || jsonb_build_object('local', public._agenda_saude_local(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{local,zeros_ok}')::boolean, true)));
  -- O M11 na lista dos liberados (o recado do P6): aqui, e não na lista dos 11 lá em cima, que fica dentro do bloco da Fase 5
  if public._agenda_cliente_tipo_liberado('onde_fica') then
    v_gr := jsonb_set(v_gr, '{cliente,tipos_liberados}', (v_gr #> '{cliente,tipos_liberados}') || '["onde_fica"]'::jsonb);
  end if;
  -- (7d: fim)
  -- (7f P7; §11, R8.13; dentro do bloco do gestor: por isso a marca, não o bloco) a chave comunicacao (_agenda_saude_comunicacao), com os zeros obrigatórios no ok. Sem os modos
  -- da 7f e sem nada do que eles fazem, os zeros são 0 e o ok é o de antes.
  v_gr := v_gr || jsonb_build_object('comunicacao', public._agenda_saude_comunicacao(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{comunicacao,zeros_ok}')::boolean, true)));
  -- (7f: fim)
  -- (7f P6; dentro do bloco do gestor: por isso a marca, não o bloco) o M12 na lista dos liberados, como o M11 da 7d: aqui, e não na lista dos 11 lá em cima,
  -- que fica dentro do bloco da Fase 5. Só a contagem: a semana nunca entra em cliente_tipos_ligados por aqui (o ligar é do dono)
  if public._agenda_cliente_tipo_liberado('semana') then
    v_gr := jsonb_set(v_gr, '{cliente,tipos_liberados}', (v_gr #> '{cliente,tipos_liberados}') || '["semana"]'::jsonb);
  end if;
  -- (7f: fim)
  -- (7e P7; §5.6, R7.5-17; dentro do bloco do gestor: por isso a marca, não o bloco) a chave margem (_agenda_saude_margem), com os zeros obrigatórios no ok. Sem nada da margem (nenhuma
  -- linha nem ação dela, o puxar sem rodar fora de hora), os zeros são 0 e o ok é o de antes. A chave existe em todos os modos e não traz os modos (não muda de um para o outro).
  v_gr := v_gr || jsonb_build_object('margem', public._agenda_saude_margem(p_hoje, p_agora));
  v_gr := jsonb_set(v_gr, '{ok}', to_jsonb(coalesce((v_gr ->> 'ok')::boolean, false)
                                            and coalesce((v_gr #>> '{margem,zeros_ok}')::boolean, true)));
  -- (7e: fim)
  return v_gr;
  -- FASE 7: fim
  return jsonb_build_object(
    -- FASE 3: os zeros obrigatórios da execução entram no ok.
    'ok', v_sem = 0 and (v_regra ->> 'n')::int = 0 and v_choques = 0
          and v_teto = 0 and v_janela = 0 and v_semconf = 0 and v_sobre = 0 and coalesce(v_semrec, 0) = 0 and v_pay = 0
          -- FASE 4: os zeros obrigatórios do material e da mensagem ao fornecedor entram no ok.
          and v_zeros4,
          -- FASE 4: fim
    'modos', jsonb_build_object('leitura', cf.modo_leitura, 'proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
    'vigia', v_vig, 'hoje', v_hoje, 'criticas', v_crit, 'perguntas', v_perg, 'propostas', v_prop, 'plano', v_plano,
    'invariantes', v_inv, 'fechamento', v_fech,
    -- FASE 3
    'rotina', v_rot, 'equipe', v_eq, 'diarias', v_dia, 'conclusao', v_conc, 'marcos', v_marcos, 'comissao', v_com,
    'modos_fase3', jsonb_build_object('equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
    -- FASE 5: a mensagem ao cliente
    'cliente', v_cli,
    -- FASE 5: fim
    -- FASE 6: o aprendizado
    'aprendizado', v_apr,
    -- FASE 6: fim
    -- FASE 4: o material
    'material', v_mat);
    -- FASE 4: fim
end;
$function$;

comment on function public.agenda_saude(date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a conferência depois de cada deploy e o painel da sombra — {ok, modos, vigia (última rodada, rodou nas últimas 2 h, erros em 24 h no app_error_logs context agenda, rodadas em 24 h), hoje (publicar, criar, mover, cancelar, promover, soltar, status, resultado, desfeitas, sombra), criticas (abertas, respondidas em 7 dias, sem_decisao e pela_regra_sem_decisao — têm de ser 0), perguntas (abertas por tipo, mostradas hoje), propostas, plano (vigentes futuras, OS programadas, reservas, sem registro em 7 dias), invariantes (vigente de OS fora da carteira, espelho divergente em ligado, choques = 0), fechamento (leu o plano hoje: resumo_tarde.detalhe.agenda; linhas mostradas)}. Leitura (invoker): authenticated (a RLS do admin vale) e service_role. Fase 3: a vigia lê só as rodadas dela (rotina = vigia); blocos rotina (última rodada, rodou nas últimas 2 h, erros 24 h), equipe (mensagens e recusas de hoje; acima_do_teto e fora_da_janela — também o que saiu fora dela — têm de ser 0), diarias (lançadas e em teste em 7 dias, perguntas abertas; sem_confirmacao e sobrescreveu_turno têm de ser 0), conclusao (pela agenda e desfeitas em 7 dias; sem_recebivel_quando_devia = 0, só para quem lê a releitura), marcos (N4), comissao (pagamento desligado; payables de comissão de técnico em 7 dias = 0) e modos_fase3; o ok inclui esses zeros. Fase 4 (P5): o bloco material — modos (material, detector, fornecedor), a rodada do material (rotina = material: última, rodou nas últimas 2 h, erros 24 h em material:%), remessas (a caminho, sem resposta, ligadas/sem serviço/chegaram em 7 dias), perguntas (as abertas da Fase 4 por tipo; pix_na_semana), detector (agenda_detector_precisao dos últimos 14 dias — só para administrador/financeiro ou sem login —, aplicados e desfeitos em 7 dias), fornecedor (registradas, enfileiradas, em teste e recusadas por motivo em 7 dias), cobertura (itens críticos das OS que começam nas próximas material_inicio_dias e quantos têm data, nível A–D), espera (mediana da aprovação à 1ª compra, OS aprovadas em 90 dias); os zeros obrigatórios entram no ok: vinculo_sem_resposta_do_dono, previsao_sem_original e, do fornecedor, na_fila_em_sombra, fora_da_janela, acima_do_teto e com_valor_ou_cliente. Fase 5 (P3): o bloco cliente — modo, tipos_ligados, tipos_liberados (somaram cliente_aprovacao_dias dias aprovados), a rodada do cliente (rotina = cliente: última, rodou nas últimas 2 h, erros 24 h em cliente:%), mensagens_7d por tipo (registradas, aguardando, enviadas, recusadas por motivo), aprovacao (pedidas abertas, vencidas, aprovadas e seguradas em 7 dias) e as métricas (M6 antes da data, aprovadas sem segurar, resposta em 1 dia, SIM automático, opt-outs, falhas de entrega, idas perdidas por acesso com e sem véspera); os zeros obrigatórios entram no ok: fora_da_janela, em_feriado_ou_domingo, acima_do_teto, intervalo_curto, com_texto_proibido, na_fila_em_sombra, sem_aprovacao_no_periodo, critica_sem_decisao, vespera_com_os_aguardando_peca, aviso_depois_da_data e audio_que_confirmou. Fase 6 (P6): a chave aprendizado — o modo, a lista, a última rodada, os erros de aprender:% em 24 h, os 6 zeros (em_uso_com_amostra_pequena, em_uso_fora_de_ligado, troca_grande_sem_pergunta, rodada_atrasada, medida_sem_classe, fator_fora_dos_limites; entram no ok) e as métricas (itens, medidas, trocas em 30 dias, o erro do fator, a pontualidade antes e depois da folga, o item desfeito 2 vezes em 4 semanas). CORREÇÃO FASE 6 (C2, item 12): as janelas do aprendizado vêm de agenda_config — a troca grande em aprender_saude_dias, a rodada atrasada em aprender_atraso_h, as métricas das trocas em aprender_parar_dias e o desfeito 2 vezes em aprender_trava_dias. FASE 7 (7a P7, spec §11): a chave gestor — os modos efetivos (marcar, encaixe, revisao, compre_ate, vaga, so_propor, desde), as regras, a última rodada (rotina gestor), as rodadas em 24 h, se os passos diários rodaram hoje, os erros de gestor:% em 24 h, os zeros obrigatórios (entram no ok: zona_travada_mexida e dia_avisado_sem_pergunta pela regra de _agenda_criticidade_da_acao, estimativa_sem_pergunta, prazo_em_critica, prazo_em_dia_prometido, aprovada_sem_data, rodada_gestor_atrasada, cliente_estimativa_sem_aprovacao, ficha_estimativa_sem_veto, onda_aplicada_sem_pergunta, alocacao_sem_fonte, regra_em_sombra_aplicada; os do que o gestor muda sozinho contam a partir de marcar_sozinho_desde) e prazo_vencido_sem_mostrar (só se conta: fica fora do ok), e os números (OS por estimativa, perguntas com prazo abertas/vencidas/respondidas/aplicadas pelo prazo, compre até gravados/cobrados/empurrados, fichas seguradas). E o erro do fator (métricas do aprendizado) só com as medidas que têm fator (a medida por estimativa é válida e não tem fator). FASE 7b (P5, §5.4, R4.3(g)): a chave equipe_dias (_agenda_saude_equipe7b): modos (dias, dupla, sabado, cadastro, chamar), a última rodada da semana da equipe e os erros de equipe_semana:% em 24 h, os zeros obrigatórios (entram no ok: dias_fora_da_janela, dias_duas_na_semana, dia_acima_do_teto, ficha_recusada_por_teto_com_dias, dupla_com_uma_pessoa — só a dita —, dupla_incompleta_com_gente_livre, novato_sozinho, sabado_sem_prazo, sabado_tarde, dono_em_vaga_sem_ok, resposta_sem_gravar) e os números (perguntadas × respondidas na última semana fechada e o %, adiadas pelo teto em 7 dias, a dupla inferida esperando o ajudante, duplas inferidas × ditas, sábados usados e em teste, a semana passada por pessoa: declarada × usada × cumprida). Sem os modos da 7b, os zeros são 0 e o ok é o de antes. FASE 7d (P8; §11, R6.3-11): a chave local (_agenda_saude_local), com os zeros obrigatórios no ok (acesso_sem_preparo, feriado_local_marcado, patio_acima_das_vagas, viagem_quebrada, rodada_local_atrasada); onde_fica em tipos_liberados. Sem os modos da 7d, os zeros são 0 e o ok é o de antes. FASE 7f (P7; §11, R2, R8.13): a chave comunicacao (_agenda_saude_comunicacao: os modos crus, a rodada comunicar, os zeros obrigatórios no ok e os números da comunicação); e o zero prazo_em_critica do gestor passa a ser a crítica com prazo fora de veto_tipos ou com veto_espera (a crítica pode vencer, AG7-15). FASE 7f (P6): a semana entra em cliente.tipos_liberados quando somar os dias aprovados (como o M11). FASE 7e (P7, §5.6, R7.5-17): a chave margem (_agenda_saude_margem), com zeros_ok no ok; os itens da margem saem dos zeros e das métricas do aprendizado da Fase 6 (em uso com amostra pequena: a folga da semana que volta ao padrão; em uso fora de ligado; troca grande sem pergunta; metricas.itens): eles estão na margem.';

-- _agenda_ver_aprendizado (de 20261029100950_agenda_fase6_correcao_textos.sql:1624; md5 do corpo de antes 684e46d0b334f7b74a258d6d42538ab2)
create or replace function public._agenda_ver_aprendizado(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_uid    uuid := auth.uid();
  v_papel  text;
  c        public.agenda_config;
  v_linhas jsonb;
  v_blocos jsonb;
  v_max    int;
  v_cab    text;
  v_corpo  text[];
  v_fecho  text[];
  v_t      text;
  k        int;
  b        record;
  v_tot    int;
  v_val    int;
  v_inv    jsonb;
  v_motivos text;
  v_audio  int;
  v_naoent int;
  -- FASE 7e: (7e P7, §5.6, §6.2) o bloco 8 "Margem": as linhas dele, os interruptores fora de desligado e a temporada da segunda que vem
  v_7e_l    jsonb;
  v_7e_on   text[];
  v_7e_seg  date;
  v_7e_t    jsonb;
  v_7e_k    jsonb;
  v_7e_tx   text;
  v_7e_lig  boolean;
  -- FASE 7e: fim
begin
  if p_hoje is null then
    raise exception '_agenda_ver_aprendizado: sem o dia de hoje' using errcode = '22004';
  end if;
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role (o mesmo de agenda_fator_de_campo).
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

  -- As linhas, na ordem de cada bloco. Desligado: nenhuma (a rodada só mede; o que ficou gravado de antes não vale).
  with a as (
    select x.item, x.chave, x.nivel, x.estado, x.n, x.n_min, x.calculado, x.em_uso, x.texto, x.detalhe ->> 'nome' as nome,
           case x.item when 'fator' then 1 when 'presenca' then 2 when 'fornecedor_atraso' then 3 when 'fornecedor_prazo' then 3
                       when 'capacidade_dono' then 4 when 'mo' then 5 when 'cliente_pontualidade' then 6 when 'aviso_folga' then 6
                       when 'carga' then 7 when 'solver' then 7 end as bloco,
           case x.item when 'fornecedor_atraso' then 1 when 'fornecedor_prazo' then 2 when 'cliente_pontualidade' then 1
                       when 'aviso_folga' then 2 when 'carga' then 1 when 'solver' then 2 else 1 end as ir,
           case x.estado when 'pergunta' then 1 when 'em_uso' then 2 when 'travado' then 3 when 'sombra' then 4 else 5 end as er,
           case x.nivel when 'fina' then 1 when 'sistema' then 2 when 'bem' then 3 when 'todas' then 4 else 5 end as nr
      from public.agenda_aprendizado x
     where c.modo_aprendizado <> 'desligado' and nullif(btrim(x.texto), '') is not null
  ),
  f as (
    select a.* from a
     where not (a.item in ('fator', 'presenca') and (
             -- a chave ainda medindo só aparece como "as OS" (todas), e só enquanto nenhuma do item chegou ao mínimo
             (a.estado = 'medindo' and (a.nivel <> 'todas' or exists (select 1 from a o where o.item = a.item and o.estado <> 'medindo')))
             -- a mais larga que repete uma mais fina do mesmo item (a mesma amostra: o mesmo n, o mesmo medido, o mesmo estado)
             or exists (select 1 from a o
                         where o.item = a.item and o.nr < a.nr and o.n = a.n and o.estado = a.estado
                           and o.calculado is not distinct from a.calculado
                           and (a.nivel = 'todas'
                                or (a.nivel = 'sistema' and o.nivel = 'fina' and split_part(o.chave, ':', 2) = split_part(a.chave, ':', 2))
                                or (a.nivel = 'bem' and o.nivel = 'fina' and split_part(o.chave, ':', 1) = split_part(a.chave, ':', 2))))))
  ),
  -- o fator sem nenhuma linha ainda (a 1ª rodada não rodou ou não há OS concluída): "As OS: 0 de 6 OS medidas; …"
  vazio as (
    select 'fator'::text as item, 'todas'::text as chave, 'todas'::text as nivel, 'medindo'::text as estado, 0 as n,
           c.fator_n_min::int as n_min, null::numeric as calculado, null::numeric as em_uso,
           public._agenda_aprendizado_texto('fator', 'foco_medindo',
             jsonb_build_object('chave', 'todas', 'n', 0, 'n_min', c.fator_n_min, 'padrao', c.estouro_fator)) as texto,
           null::text as nome, 1 as bloco, 1 as ir, 5 as er, 4 as nr
     where c.modo_aprendizado <> 'desligado' and not exists (select 1 from a where a.item = 'fator')
  ),
  t as (select * from f union all select * from vazio)
  select coalesce(jsonb_agg(jsonb_build_object(
           'bloco', t.bloco, 'item', t.item, 'chave', t.chave, 'nivel', t.nivel, 'estado', t.estado, 'n', t.n, 'n_min', t.n_min,
           'calculado', t.calculado, 'em_uso', t.em_uso, 'texto', t.texto)
           order by t.bloco, case when t.bloco in (6, 7) then t.ir else 0 end, t.er, t.nr, t.n desc, t.nome nulls last, t.ir,
                    t.chave), '[]'::jsonb)
    into v_linhas
    from t;
  -- FASE 7e: (7e P7, §5.6, §6.2, R7.3-1; a conferência da integração P4–P6) os itens da margem saem dos blocos 1 a 7: sem bloco, eles caíam juntos no fim, com empate completo na ordem, e a
  -- ordem física das linhas decidia o que o corte por texto_max mostrava. Vão ao bloco 8 "Margem", depois do 7, numa ordem total: o item (o viés, a folga da semana, a temporada, o prazo
  -- real, o tempo de compra, a folga das OS com compra pendente, a peça sem fornecedor), a linha dentro dele (a geral, as classes, a do dono), o estado, o n e a chave (única no item).
  -- Cada item só com o interruptor dele fora de desligado, pelo modo cru (em teste também aparece, "Em teste: …", §6.2); a peça sem fornecedor, que é só medida, vai com o tempo de
  -- compra. Sem linha gravada, a linha de "nenhuma … ainda", como o fator faz. O viés: a geral, as classes (sem a que ainda mede e sem a que repete a geral: o mesmo estado e o mesmo
  -- medido) e a linha do dono (dono:todas). A temporada: a da segunda que vem; em teste, só quando ela muda o que eu marcaria (lição 5). Com os 6 interruptores desligados, o bloco não
  -- existe e o foco é o de antes, byte a byte.
  v_linhas := coalesce((select jsonb_agg(l order by o) from jsonb_array_elements(v_linhas) with ordinality e(l, o) where l ->> 'bloco' is not null), '[]'::jsonb);
  if c.modo_aprendizado <> 'desligado' then
    v_7e_on := array_remove(array[
      case when coalesce(public._agenda_margem_modo_cru('vies'), 'desligado') <> 'desligado' then 'vies' end,
      case when coalesce(public._agenda_margem_modo_cru('folga_semana'), 'desligado') <> 'desligado' then 'folga_semana' end,
      case when coalesce(public._agenda_margem_modo_cru('promessa'), 'desligado') <> 'desligado' then 'promessa' end,
      case when coalesce(public._agenda_margem_modo_cru('tempo_compra'), 'desligado') <> 'desligado' then 'tempo_compra' end,
      case when coalesce(public._agenda_margem_modo_cru('folga_compra'), 'desligado') <> 'desligado' then 'folga_compra' end,
      case when coalesce(public._agenda_margem_modo_cru('tempo_compra'), 'desligado') <> 'desligado' then 'prazo_sem_fornecedor' end], null);
    if 'folga_semana' = any (v_7e_on) then
      v_7e_seg := p_hoje + (8 - extract(isodow from p_hoje)::int);
      v_7e_t := public._agenda_temporada(v_7e_seg);
      v_7e_lig := public._agenda_margem_modo('folga_semana') = 'ligado';
      if v_7e_lig then
        v_7e_k := public._agenda_carga_da_semana(v_7e_seg);
        v_7e_tx := case when (v_7e_t ->> 'extra')::numeric > 0
                        then format('Temporada: na semana de %s guardo mais %s para urgência (%s): marco até %s da semana da equipe.', to_char(v_7e_seg, 'DD/MM'),
                                    round((v_7e_t ->> 'extra')::numeric * 100) || '%', v_7e_t ->> 'texto', round((v_7e_k ->> 'carga')::numeric * 100) || '%')
                        else format('Temporada: na semana de %s não guardo nada a mais para urgência: marco até %s da semana da equipe.', to_char(v_7e_seg, 'DD/MM'),
                                    round((v_7e_k ->> 'carga')::numeric * 100) || '%') end;
      else
        v_7e_k := public._agenda_carga_da_semana(v_7e_seg, true);
        if (v_7e_k ->> 'carga')::numeric <> c.carga_max then
          v_7e_tx := case when (v_7e_t ->> 'extra')::numeric > 0
                          then format('Em teste: na semana de %s eu guardaria mais %s para urgência (%s) e marcaria até %s da semana da equipe, e não %s.', to_char(v_7e_seg, 'DD/MM'),
                                      round((v_7e_t ->> 'extra')::numeric * 100) || '%', v_7e_t ->> 'texto', round((v_7e_k ->> 'carga')::numeric * 100) || '%', round(c.carga_max * 100) || '%')
                          else format('Em teste: na semana de %s eu marcaria até %s da semana da equipe, e não %s.', to_char(v_7e_seg, 'DD/MM'),
                                      round((v_7e_k ->> 'carga')::numeric * 100) || '%', round(c.carga_max * 100) || '%') end;
        end if;
      end if;
    end if;
    with m as (
      select x.item, x.chave, x.nivel, x.estado, x.n::int as n, x.n_min::int as n_min, x.calculado, x.em_uso, x.texto,
             array_position(array['vies', 'folga_semana', 'temporada', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor'], x.item) as io,
             case when x.chave in ('estimativa:todas', 'equipe', 'todas') then 1 when x.chave like 'dono:%' then 3 else 2 end as sub,
             case x.estado when 'pergunta' then 1 when 'em_uso' then 2 when 'travado' then 3 when 'sombra' then 4 else 5 end as er
        from public.agenda_aprendizado x
       where x.item = any (v_7e_on) and nullif(btrim(x.texto), '') is not null
    ),
    f as (
      select m.* from m
       where not (m.item = 'vies' and ((m.sub = 3 and m.chave <> 'dono:todas')
                                       or (m.sub = 2 and m.estado = 'medindo')
                                       or (m.sub = 2 and exists (select 1 from m g where g.item = 'vies' and g.chave = 'estimativa:todas'
                                                                   and g.estado = m.estado and g.calculado is not distinct from m.calculado))))
         and not (m.item <> 'vies' and m.sub <> 1)
    ),
    vazio as (
      select v.item, v.chave, v.nivel, 'medindo'::text as estado, 0 as n, v.n_min, null::numeric as calculado, null::numeric as em_uso, v.texto, v.io, 1 as sub, 5 as er
        from (values
          ('vies', 'estimativa:todas', 'todas', c.vies_n_min::int, 1,
           public._agenda_aprendizado_texto('vies', 'foco_medindo', jsonb_build_object('chave', 'estimativa:todas', 'n', 0, 'n_min', c.vies_n_min))),
          ('folga_semana', 'equipe', 'geral', c.folga_semanas_min::int, 2,
           public._agenda_aprendizado_texto('folga_semana', 'foco_medindo', jsonb_build_object('chave', 'equipe', 'n', 0, 'n_min', c.folga_semanas_min,
                                                                                              'padrao', c.folga_dispersao_padrao, 'carga_max', c.carga_max))),
          ('promessa', 'todas', 'todas', c.promessa_n_min::int, 4,
           public._agenda_aprendizado_texto('promessa', 'foco_medindo', jsonb_build_object('chave', 'todas', 'n', 0, 'n_min', c.promessa_n_min))),
          ('tempo_compra', 'todas', 'geral', c.tempo_compra_n_min::int, 5,
           public._agenda_aprendizado_texto('tempo_compra', 'foco_medindo', jsonb_build_object('chave', 'todas', 'n', 0, 'n_min', c.tempo_compra_n_min,
                                                                                              'padrao', c.compra_interna_du))),
          ('folga_compra', 'todas', 'geral', c.folga_compra_n_min::int, 6,
           public._agenda_aprendizado_texto('folga_compra', 'foco_medindo', jsonb_build_object('chave', 'todas', 'n', 0, 'n_min', c.folga_compra_n_min,
                                                                                              'folga_material_du', c.folga_material_du))),
          ('prazo_sem_fornecedor', 'todas', 'geral', c.prazo_sem_fornecedor_n_min::int, 7,
           public._agenda_aprendizado_texto('prazo_sem_fornecedor', 'foco_medindo', jsonb_build_object('chave', 'todas', 'n', 0, 'n_min', c.prazo_sem_fornecedor_n_min,
                                                                                                      'padrao', c.prazo_sem_fornecedor_du)))
        ) v(item, chave, nivel, n_min, io, texto)
       where v.item = any (v_7e_on) and not exists (select 1 from m where m.item = v.item and m.sub = 1)
    ),
    tmp as (
      select 'temporada'::text as item, v_7e_seg::text as chave, 'geral'::text as nivel, case when v_7e_lig then 'em_uso' else 'sombra' end as estado,
             null::int as n, null::int as n_min, (v_7e_k ->> 'carga')::numeric as calculado, case when v_7e_lig then (v_7e_k ->> 'carga')::numeric end as em_uso,
             v_7e_tx as texto, 3 as io, 1 as sub, case when v_7e_lig then 2 else 4 end as er
       where v_7e_tx is not null
    ),
    t8 as (select * from f union all select * from vazio union all select * from tmp)
    select jsonb_agg(jsonb_build_object('bloco', 8, 'item', t8.item, 'chave', t8.chave, 'nivel', t8.nivel, 'estado', t8.estado, 'n', t8.n, 'n_min', t8.n_min,
                                        'calculado', t8.calculado, 'em_uso', t8.em_uso, 'texto', t8.texto)
                     order by t8.io, t8.sub, t8.er, t8.n desc nulls last, t8.chave)
      into v_7e_l
      from t8;
    v_linhas := v_linhas || coalesce(v_7e_l, '[]'::jsonb);
  end if;
  -- FASE 7e: fim

  -- As medidas: quantas OS concluídas foram medidas, quantas valem e por que as outras não.
  select count(*)::int, count(*) filter (where m.valida)::int into v_tot, v_val from public.agenda_medidas_os m;
  select coalesce(jsonb_object_agg(x.motivo, x.n), '{}'::jsonb),
         string_agg(case x.motivo
                      when 'sem_inicio' then format('%s sem check-in', x.n)
                      when 'sem_dias_no_inicio' then format('%s sem os dias ditos no início', x.n)
                      when 'dias_sugeridos' then format('%s com os dias só estimados por mim', x.n)
                      when 'sem_plano' then format('%s sem plano nem diária', x.n)
                      when 'conferencia_incompleta' then format('%s sem conferência completa', x.n)
                      when 'sem_diaria' then format('%s sem diária ligada', x.n)
                      when 'reaberta' then public._agenda_plural(x.n, 'reaberta', 'reabertas')
                      -- CORREÇÃO FASE 6: (C2) sobra (b) da C1: o motivo sem_fim (a OS concluída sem check-out e sem a
                      -- conclusão pela porta) tem o rótulo dele, e não "por outro motivo"
                      when 'sem_fim' then format('%s sem a conclusão registrada', x.n)
                      -- CORREÇÃO FASE 6: fim
                      else format('%s por outro motivo', x.n) end,
                    '; ' order by x.n desc, x.o)
    into v_inv, v_motivos
    from (select m.motivo, count(*)::int as n,
                 array_position(array['sem_inicio', 'sem_dias_no_inicio', 'dias_sugeridos', 'sem_plano', 'conferencia_incompleta',
                                      'sem_diaria', 'reaberta'], m.motivo) as o
            from public.agenda_medidas_os m where not m.valida group by m.motivo) x;

  -- As respostas de cliente que foram ao dono por áudio ou sem a agenda entender, nos últimos 30 dias (d8: só a contagem).
  select count(*) filter (where r.intencao = 'audio')::int, count(*) filter (where r.intencao = 'outro')::int
    into v_audio, v_naoent
    from public.agenda_cliente_respostas r
   where r.efeito = 'ao_dono' and (r.recebida_em at time zone 'America/Sao_Paulo')::date between p_hoje - 29 and p_hoje;

  v_fecho := array[
    case when v_tot = 0 then 'Medidas: nenhuma OS concluída medida ainda.'
         else format('Medidas: %s OS (%s%s).', v_tot,
                     case when v_val = v_tot and v_tot > 1 then 'todas valem' when v_val = 0 then 'nenhuma vale'
                          when v_val = 1 then '1 vale' else v_val || ' valem' end,
                     coalesce('; ' || v_motivos, '')) end,
    format('Respostas de cliente que foram a você por áudio: %s em 30 dias%s.',
           case when v_audio = 0 then 'nenhuma' else v_audio::text end,
           case when v_naoent > 0 then format('; sem eu entender: %s', v_naoent) else '' end)];

  v_cab := case c.modo_aprendizado
    when 'desligado' then 'O aprendizado está desligado: meço as OS concluídas, mas não calculo nem uso nada.'
    when 'sombra' then 'O que a agenda aprendeu com o que aconteceu (em teste: nada disto muda o plano ainda):'
    else 'O que a agenda aprendeu com o que aconteceu:' end;

  -- Os blocos: as linhas de cada um e quantas são.
  select coalesce(jsonb_agg(jsonb_build_object('bloco', x.bloco, 'nome', x.nome, 'linhas', x.linhas) order by x.bloco), '[]'::jsonb)
    into v_blocos
    from (select (l ->> 'bloco')::int as bloco,
                 (array['fator', 'presenca', 'fornecedor', 'capacidade', 'mo', 'cliente', 'revisao'])[(l ->> 'bloco')::int] as nome,
                 jsonb_agg(l - 'bloco' order by o) as linhas
            from jsonb_array_elements(v_linhas) with ordinality e(l, o)
           group by 1) x;

  -- FASE 7e: (7e P7) o nome do bloco 8 nos dados (a lista de cima tem os 7 da Fase 6); sem o bloco 8, os blocos de antes, byte a byte
  v_blocos := coalesce((select jsonb_agg(case when (x ->> 'bloco')::int = 8 then x || jsonb_build_object('nome', 'margem') else x end order by o)
                          from jsonb_array_elements(v_blocos) with ordinality e(x, o)), '[]'::jsonb);
  -- FASE 7e: fim
  -- Cabe no teto: cada bloco mostra as k primeiras e "• e mais N"; o fecho fica sempre.
  v_max := coalesce((select max(jsonb_array_length(x -> 'linhas')) from jsonb_array_elements(v_blocos) x), 0);
  for k in reverse v_max .. 0 loop
    v_corpo := array[v_cab];
    for b in select x -> 'linhas' as linhas from jsonb_array_elements(v_blocos) with ordinality e(x, o) order by o loop
      v_corpo := v_corpo
        || array(select '• ' || (l ->> 'texto') from jsonb_array_elements(b.linhas) with ordinality y(l, o)
                  where o <= greatest(k, 1) order by o)
        || case when jsonb_array_length(b.linhas) > greatest(k, 1)
                then array[format('• e mais %s', jsonb_array_length(b.linhas) - greatest(k, 1))] else '{}'::text[] end;
    end loop;
    v_t := public._agenda_juntar(v_corpo || v_fecho, null);
    exit when char_length(v_t) <= c.texto_max or k <= 1;
  end loop;
  if char_length(v_t) > c.texto_max then
    -- nem com uma linha por bloco: o corpo encurta pelo fim ("(e mais N linhas)") e o fecho fica
    v_t := public._agenda_juntar(v_corpo, greatest(c.texto_max - char_length(public._agenda_juntar(v_fecho, null)) - 1, 1))
           || E'\n' || public._agenda_juntar(v_fecho, null);
  end if;

  -- CORREÇÃO FASE 6: (C2) itens 10 e 12. (item 12) a janela das respostas por áudio é agenda_config.aprender_respostas_dias
  -- (eram os 30 dias escritos acima): a contagem e a 2ª frase do fecho, refeitas. (item 10) quando o foco inteiro não cabe em
  -- texto_max, o corte não some com as perguntas abertas: tira primeiro, de cada bloco, as linhas depois da 1ª — as em teste
  -- e medindo antes das em uso e das travadas, do último bloco para o 1º e de baixo para cima —, cada bloco com "• e mais N"
  -- no lugar do que saiu; só então a 1ª linha de cada bloco, na mesma ordem (o bloco que sai inteiro vai à conta "(e mais N
  -- linhas)" do fim do corpo). A pergunta nunca sai por este corte. Se nem só as perguntas couberem, elas vêm primeiro e o
  -- corpo encurta pelo fim (o fecho fica). Cabendo tudo, o texto é o de cima, byte a byte (com o fecho de agora). O return de
  -- baixo não roda mais.
  declare
    v_l  jsonb;
    v_nt int;
    d    int;
    v_c  text[];
    v_fe text;
  begin
    select count(*) filter (where r.intencao = 'audio')::int, count(*) filter (where r.intencao = 'outro')::int
      into v_audio, v_naoent
      from public.agenda_cliente_respostas r
     where r.efeito = 'ao_dono'
       and (r.recebida_em at time zone 'America/Sao_Paulo')::date between p_hoje - (c.aprender_respostas_dias - 1) and p_hoje;
    v_fecho[2] := format('Respostas de cliente que foram a você por áudio: %s em %s dias%s.',
                         case when v_audio = 0 then 'nenhuma' else v_audio::text end, c.aprender_respostas_dias,
                         case when v_naoent > 0 then format('; sem eu entender: %s', v_naoent) else '' end);
    -- as linhas na ordem dos blocos, com a ordem de corte (r): primeiro as que não são a 1ª do bloco, depois as 1ªs; em cada
    -- uma, as em teste e medindo antes das em uso e das travadas, do último bloco para o 1º e de baixo para cima; a pergunta
    -- fica sem r (não sai por aqui)
    select coalesce(jsonb_agg(jsonb_build_object('b', y.bo, 'o', y.lo, 'p', y.e = 'pergunta', 't', y.t,
                                                 'r', case when y.e <> 'pergunta' then y.r end) order by y.bo, y.lo), '[]'::jsonb)
      into v_l
      from (select x.bo, x.lo, x.e, x.t,
                   row_number() over (partition by x.e = 'pergunta'
                                      order by (x.lo = 1), (x.e in ('sombra', 'medindo')) desc, x.bo desc, x.lo desc) as r
              from (select eb.bo, el.lo, el.v ->> 'estado' as e, el.v ->> 'texto' as t
                      from jsonb_array_elements(v_blocos) with ordinality eb(b, bo),
                           jsonb_array_elements(eb.b -> 'linhas') with ordinality el(v, lo)) x) y;
    -- (7e P7, §5.6; marca sem FASE porque está dentro do bloco da correção C2 da Fase 6) no corte, as linhas do bloco 8 (a margem) saem antes das dos blocos 1 a 7, salvo as em uso e as
    -- travadas (o que vale hoje: entram na ordem de cima, como as dos outros blocos); entre elas, a ordem de cima (as que não são a 1ª do bloco antes, de baixo para cima). Sem o bloco 8,
    -- v_l fica como saiu de cima, byte a byte.
    if exists (select 1 from jsonb_array_elements(v_blocos) z where (z ->> 'bloco')::int = 8) then
      select coalesce(jsonb_agg(jsonb_build_object('b', y.bo, 'o', y.lo, 'p', y.e = 'pergunta', 't', y.t,
                                                   'r', case when y.e <> 'pergunta' then y.r end) order by y.bo, y.lo), '[]'::jsonb)
        into v_l
        from (select x.bo, x.lo, x.e, x.t,
                     row_number() over (partition by x.e = 'pergunta'
                                        order by (x.b8 and x.e not in ('em_uso', 'travado')) desc, (x.lo = 1), (x.e in ('sombra', 'medindo')) desc,
                                                 x.bo desc, x.lo desc) as r
                from (select eb.bo, el.lo, el.v ->> 'estado' as e, el.v ->> 'texto' as t, (eb.b ->> 'bloco')::int = 8 as b8
                        from jsonb_array_elements(v_blocos) with ordinality eb(b, bo),
                             jsonb_array_elements(eb.b -> 'linhas') with ordinality el(v, lo)) x) y;
    end if;
    -- (7e: fim)
    v_nt := (select count(*) from jsonb_array_elements(v_l) z where z ->> 'r' is not null);
    for d in 0 .. v_nt loop
      v_c := array[v_cab] || array(
        select q.t
          from (select (z ->> 'b')::int as b, 0 as k, (z ->> 'o')::int as o, '• ' || (z ->> 't') as t
                  from jsonb_array_elements(v_l) z
                 where z ->> 'r' is null or (z ->> 'r')::int > d
                union all
                -- o bloco que ficou com alguma linha: "• e mais N" no fim dele
                select g.b, 1, 0, format('• e mais %s', g.fora)
                  from (select (z ->> 'b')::int as b,
                               count(*) filter (where (z ->> 'r')::int <= d) as fora,
                               count(*) filter (where z ->> 'r' is null or (z ->> 'r')::int > d) as ficam
                          from jsonb_array_elements(v_l) z
                         group by 1) g
                 where g.fora > 0 and g.ficam > 0) q
         order by q.b, q.k, q.o)
        -- os blocos que saíram inteiros: uma conta só, no fim do corpo
        || coalesce((select array[format('(e mais %s %s)', sum(g.fora), case when sum(g.fora) = 1 then 'linha' else 'linhas' end)]
                       from (select (z ->> 'b')::int as b,
                                    count(*) filter (where (z ->> 'r')::int <= d) as fora,
                                    count(*) filter (where z ->> 'r' is null or (z ->> 'r')::int > d) as ficam
                               from jsonb_array_elements(v_l) z
                              group by 1) g
                      where g.fora > 0 and g.ficam = 0
                     having count(*) > 0), '{}'::text[]);
      v_t := public._agenda_juntar(v_c || v_fecho, null);
      exit when char_length(v_t) <= c.texto_max;
    end loop;
    if char_length(v_t) > c.texto_max then
      v_fe := public._agenda_juntar(v_fecho, null);
      v_c := array[v_cab] || array(select '• ' || (z ->> 't') from jsonb_array_elements(v_l) z
                                    where (z ->> 'p')::boolean order by (z ->> 'b')::int, (z ->> 'o')::int);
      v_t := public._agenda_juntar(v_c, greatest(c.texto_max - char_length(v_fe) - 1, 1)) || E'\n' || v_fe;
    end if;
  end;
  return jsonb_build_object('ok', true, 'texto', v_t,
    'dados', jsonb_build_object(
      'modo', c.modo_aprendizado, 'ligados', to_jsonb(c.aprendizado_ligados), 'blocos', v_blocos,
      'medidas', jsonb_build_object('total', v_tot, 'validas', v_val, 'invalidas', v_inv),
      'respostas_ao_dono', jsonb_build_object('audio', v_audio, 'nao_entendidas', v_naoent, 'dias', c.aprender_respostas_dias)));
  -- CORREÇÃO FASE 6: fim
  return jsonb_build_object('ok', true, 'texto', v_t,
    'dados', jsonb_build_object(
      'modo', c.modo_aprendizado, 'ligados', to_jsonb(c.aprendizado_ligados), 'blocos', v_blocos,
      'medidas', jsonb_build_object('total', v_tot, 'validas', v_val, 'invalidas', v_inv),
      'respostas_ao_dono', jsonb_build_object('audio', v_audio, 'nao_entendidas', v_naoent, 'dias', 30)));
end;
$function$;

comment on function public._agenda_ver_aprendizado(date) is
  'Agenda de Produção (Fase 6, P8): agenda_ver foco aprendizado (spec-fase6 §5.8 e §6.2) — o que a agenda aprendeu, em 7 blocos (fator de campo por tipo de OS, presença do dono, fornecedores, capacidade do dono, R$ por diária, cliente, revisão da carga), uma linha por item e chave com o texto que a rodada do dia gravou em agenda_aprendizado.texto (nada é calculado aqui). O fator e a presença não repetem a chave mais larga que diz o mesmo que a mais fina (o mesmo n, medido e estado) e só mostram as que ainda medem como "as OS" enquanto nenhuma chegou ao mínimo; sem nenhuma linha do fator, "As OS: 0 de 6 OS medidas; …". Fecha com "Medidas: N OS (M valem; …)" e "Respostas de cliente que foram a você por áudio: N em 30 dias[; sem eu entender: K]." (d8). Desligado: só o cabeçalho e o fecho. Até texto_max: as linhas de cada bloco saem do fim ("• e mais N"), o fecho fica. {ok, texto, dados {modo, ligados, blocos [{bloco, nome, linhas [{item, chave, nivel, estado, n, n_min, calculado, em_uso, texto}]}], medidas {total, validas, invalidas}, respostas_ao_dono {audio, nao_entendidas, dias}}}. Invoker e STABLE: com login, só administrador e financeiro (senão 42501); sem login, só o service_role. CORREÇÃO FASE 6 (C2): (item 10) quando não cabe, o corte tira primeiro as linhas em teste e medindo, depois as em uso e as travadas, e nunca a pergunta (se nem só as perguntas couberem, elas vêm primeiro); (item 12) a janela das respostas por áudio é aprender_respostas_dias; (sobra b da C1) o motivo sem_fim tem o rótulo "sem a conclusão registrada". FASE 7e (P7, §5.6, §6.2, R7.3-1): o bloco 8 "Margem" (nome margem nos dados), numa ordem total (o item, a linha dentro dele, o estado, o n e a chave): o viés (a geral, as classes que não repetem a geral e a do dono), a folga da semana, a temporada da segunda que vem, o prazo real (só para você), o tempo de compra, a folga das OS com compra pendente e a peça sem fornecedor; cada item só com o interruptor dele fora de desligado (a peça sem fornecedor com o do tempo de compra), e a linha de "nenhuma … ainda" sem linha gravada. No corte por texto_max as linhas do bloco 8 saem antes das dos blocos 1–7, salvo as em uso e as travadas. Com os 6 interruptores desligados, o foco de antes.';

-- os_plano_da_os (de 20261107100700_agenda_fase7d_leituras.sql:935; md5 do corpo de antes fe0294cb045fb5d9c85f6917309e575e)
create or replace function public.os_plano_da_os(p_os uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid   uuid := auth.uid();
  so      record;
  p       jsonb;
  pl      public.os_planejamento%rowtype;
  v_pres  jsonb;
  v_fim   date;
  v_prec  date;
  v_folga int;
  v_dono  uuid := public._agenda_dono(null);
  -- FASE 6: (P8) a linha do que as OS parecidas levam (agenda_fator_de_campo) e a presença do dono com a aprendida
  v_campo text;
  v_pd    jsonb;
  -- FASE 6: fim
  -- FASE 7b: (7b P5) o bloco "Equipe" do cartão: o molde, a dupla da OS, a dupla no plano, quem está na grade, a classe, o "fora" da
  -- última montagem, as partes do texto
  v_7b_modo  text;
  v_7b_eq    jsonb;
  v_7b_m     jsonb;
  v_7b_d     jsonb;
  v_7b_pl    jsonb;
  v_7b_tec   text[];
  v_7b_tf    text;
  v_7b_cl    jsonb;
  v_7b_fora  jsonb;
  v_7b_pes   int;
  v_7b_txt   text;
  v_7b_esp   boolean := false;
  v_7b_fi    jsonb;
  v_7b_ff    jsonb;
  v_7b_ft    jsonb;
  v_7b_partes text[] := '{}';
  v_7b_nomes text[];
  -- FASE 7b: fim
  -- FASE 7d: (7d P8) o bloco "Local" do cartão
  v_7d_local jsonb;
  -- FASE 7d: fim
  -- FASE 7e: (7e P7) as 2 linhas novas da duração: a estimativa com o viés e o prazo real (só para o dono)
  v_7e_c    public.agenda_config;
  v_7e_m    jsonb;
  v_7e_sug  jsonb;
  v_7e_vi   numeric;
  v_7e_ch   text;
  v_7e_hj   numeric;
  v_7e_dd   numeric;
  v_7e_est  text;
  v_7e_pr   jsonb;
  v_7e_prom text;
  v_7e_dur  jsonb;
  -- FASE 7e: fim
begin
  if p_os is null or p_hoje is null then
    raise exception 'os_plano_da_os: sem a OS ou o dia de hoje' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'O plano da OS é com o administrador.' using errcode = '42501';
  end if;
  -- CORREÇÃO FASE 6: (C2) regressão B8: sem o "sub" no JWT (auth.uid() nulo) só passa o service_role, ou nenhum JWT (o banco
  -- por dentro: a rodada, o fechamento, os testes) — como agenda_fator_de_campo; o authenticated sem "sub" recebe 42501 (antes
  -- o portão de cima não rodava, e ele lia tudo). Os JWT do Supabase sempre têm "sub": hoje não é explorável.
  if v_uid is null then
    declare
      v_papel text;
    begin
      begin
        v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
      exception when others then
        v_papel := 'invalido';
      end;
      if v_papel not in ('', 'service_role') then
        raise exception 'O plano da OS é com o administrador.' using errcode = '42501';
      end if;
    end;
  end if;
  -- CORREÇÃO FASE 6: fim
  select s.id, s.service_order_number as numero, s.status, s.check_out_at, s.delivered_at into so
    from public.service_orders s where s.id = p_os;
  if not found then
    raise exception 'Não encontrei a OS.' using errcode = 'P0002';
  end if;
  p := public.os_prontidao(p_os, p_hoje);
  select * into pl from public.os_planejamento x where x.service_order_id = p_os;
  v_pres := p -> 'presenca_dono';
  v_fim  := (p #>> '{plano,fim_publicado}')::date;
  v_prec := pl.precisa_ate;
  v_folga := case when v_fim is not null and v_prec is not null then public.agenda_du_entre(v_fim, v_prec) end;
  -- FASE 6: (P8) (spec-fase6 §5.8) duracao.campo: a linha do fator de campo da classe desta OS ("Em teste: as OS de energia
  -- em motorhome levam até 1,7× o combinado (7 OS); …") — só com o aprendizado fora de desligado e na OS que ainda vai ser
  -- feita (a concluída, a faturada e a cancelada não têm o que perguntar). O 42501 de quem não vê o aprendizado vira nulo.
  if (public._agenda_cfg()).modo_aprendizado <> 'desligado' and so.status not in ('completed', 'invoiced', 'cancelled') then
    begin
      v_campo := public.agenda_fator_de_campo(p_os, p_hoje) ->> 'texto';
    exception when insufficient_privilege then
      v_campo := null;
    end;
  end if;
  -- presenca_dono com a aprendida (os_presenca_do_dono, fonte aprendida): o texto diz de onde veio — o de antes diria
  -- "(você disse)". A chave presenca_dono abaixo (a de antes) fica, e esta, que vem depois no mesmo objeto, vale; sem a
  -- aprendida, o texto é o de sempre.
  v_pd := jsonb_build_object(
    'valor', v_pres ->> 'presenca', 'pela_regra', coalesce(v_pres ->> 'fonte', 'regra') = 'regra',
    'aprendida', case when v_pres ->> 'fonte' = 'aprendida' then v_pres ->> 'motivo' end,
    'texto', case v_pres ->> 'presenca' when 'abre_e_fecha' then 'Você abre e fecha'
                                        when 'sempre' then 'Você fica o tempo todo'
                                        when 'nunca' then 'Você não precisa ir'
                                        else 'Sem regra' end
             || case when v_pres ->> 'fonte' = 'aprendida' then ' (pelo que medi: ' || (v_pres ->> 'motivo') || ')'
                     when coalesce(v_pres ->> 'fonte', 'regra') <> 'regra' then ' (você disse)'
                     when coalesce(v_pres ->> 'motivo', 'padrão') = 'padrão' then ' (pela regra)'
                     else ' (pela regra: ' || (v_pres ->> 'motivo') || ')' end);
  -- FASE 6: fim
  -- CORREÇÃO FASE 6: (C1) item 3: a presença guardada na 1ª publicação diz que é o que a agenda mediu quando planejou
  if coalesce((v_pres ->> 'guardada')::boolean, false) then
    v_pd := v_pd || jsonb_build_object('texto', replace(v_pd ->> 'texto', ' (pelo que medi: ', ' (pelo que medi quando planejei: '));
  end if;
  -- CORREÇÃO FASE 6: fim

  -- FASE 7b: (7b P5, §5.4, §6.4, R4.3, R4.4) o bloco "Equipe" do cartão — só com modo_dupla fora de desligado e na OS que ainda vai
  -- ser feita (desligado, ou a OS concluída, faturada ou cancelada: nulo, e o resto do cartão é o de antes). Quantas pessoas o serviço
  -- pede (pessoas: as da sugestão, ou 2 na dupla o tempo todo; com a equipe dita, as que você disse), a dupla da OS (_agenda_dupla_da_os:
  -- a que a tarefa pede, suposição minha, ou a que você disse), as notas (o espaço apertado), os meios-dias do plano em que a dupla
  -- está sem a 2ª pessoa (falta, de _agenda_dupla_no_plano), a dupla dita que espera a 2ª pessoa (espera: a classe 4 dupla, ou o
  -- "fora" dupla da última montagem que citou a OS, sem compromisso dela de hoje em diante) e o texto: "1 pessoa; nos 2 primeiros
  -- meios-dias (ter 10/11) a troca do banco de baterias pede 2 — falta a 2ª pessoa (só Alex está na equipe).", "Em dupla o tempo todo
  -- (você disse) — espero a 2ª pessoa: só Alex está na equipe.", em teste "Em teste: eu marcaria 1 pessoa, em dupla nos 2 primeiros
  -- meios-dias (troca do banco de baterias). Hoje marco 1 pessoa e ponho a 2ª nesses meios-dias quando alguém está livre."
  v_7b_modo := (public._agenda_cfg()).modo_dupla;
  if v_7b_modo <> 'desligado' and so.status not in ('completed', 'invoiced', 'cancelled') then
    v_7b_m := public.agenda_meios_da_os(p_os, p_hoje);
    v_7b_d := public._agenda_dupla_da_os(p_os);
    v_7b_pl := public._agenda_dupla_no_plano(p_os, p_hoje);
    v_7b_tec := public._agenda_tecnicos_da_grade(p_hoje);
    v_7b_tf := case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre nesses meios-dias'
                    else public._agenda_tecnicos_frase(v_7b_tec) end;
    v_7b_pes := case when coalesce((v_7b_m ->> 'equipe_dita')::boolean, false)
                       then greatest(coalesce((v_7b_m #>> '{por_turno,manha,desejado}')::int, 0),
                                     coalesce((v_7b_m #>> '{por_turno,tarde,desejado}')::int, 0))
                     when coalesce((v_7b_d ->> 'todos')::boolean, false) then 2
                     else coalesce((v_7b_m ->> 'pessoas_sugeridas')::int, 1) end;
    v_7b_fi := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) with ordinality t(e, o)
                         where e ->> 'onde' = 'inicio'), '[]'::jsonb);
    v_7b_ff := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) with ordinality t(e, o)
                         where e ->> 'onde' = 'fim'), '[]'::jsonb);
    v_7b_ft := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) with ordinality t(e, o)
                         where e ->> 'onde' = 'todos'), '[]'::jsonb);
    -- a dupla dita que espera a 2ª pessoa: a classe 4 dupla (a grade com menos técnicos do que ela pede), ou a que só passou pela régua
    -- com quem vem sob demanda e ficou no "fora" dupla da última montagem que citou a OS (R4.3(c)), sem compromisso dela de hoje em diante
    if v_7b_d ->> 'fonte' = 'dono' and not coalesce((v_7b_m ->> 'equipe_dita')::boolean, false) then
      v_7b_cl := public._agenda_classe_da_os(p, v_7b_m, p_hoje,
                   exists (select 1 from public.agenda_alocacoes a where a.service_order_id = p_os and a.estado = 'fixada' and a.dia >= p_hoje),
                   false);
      if (v_7b_cl ->> 'classe')::int = 4 and v_7b_cl ->> 'motivo' = 'dupla' then
        v_7b_esp := true;
        v_7b_txt := rtrim(v_7b_d ->> 'texto', '.') || ' — espero a 2ª pessoa: ' || public._agenda_tecnicos_frase(v_7b_tec) || '.';
      elsif not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = p_os and a.estado in ('publicada', 'fixada')
                          and a.tipo <> 'reserva' and a.dia >= p_hoje) then
        select x.f into v_7b_fora
          from (select pr.criada_em, pr.id, (select f from jsonb_array_elements(coalesce(pr.fora, '[]'::jsonb)) f
                                              where f ->> 'os' = p_os::text limit 1) as f,
                       exists (select 1 from jsonb_array_elements(coalesce(pr.itens, '[]'::jsonb)) i where i ->> 'os' = p_os::text) as no_plano
                  from public.agenda_propostas pr
                 where (pr.criada_em at time zone 'America/Sao_Paulo')::date <= p_hoje) x
         where x.f is not null or x.no_plano
         order by x.criada_em desc, x.id desc limit 1;
        if v_7b_fora ->> 'motivo' = 'dupla' then
          v_7b_esp := true;
          v_7b_txt := rtrim(v_7b_d ->> 'texto', '.') || ' — espero a 2ª pessoa: '
                      || case when position('): ' in v_7b_fora ->> 'texto') > 0
                              then substr(v_7b_fora ->> 'texto', position('): ' in v_7b_fora ->> 'texto') + 3)
                              else v_7b_fora ->> 'texto' end;
        end if;
      end if;
    end if;
    if v_7b_txt is null then
      if coalesce((v_7b_m ->> 'equipe_dita')::boolean, false) then
        v_7b_nomes := array(select y.nome from (select distinct on (x ->> 'payee_id') x ->> 'payee_id' as id, x ->> 'nome' as nome
                                                 from (select jsonb_array_elements(coalesce(v_7b_m #> '{por_turno,manha,pessoas}', '[]'::jsonb)) x
                                                       union all
                                                       select jsonb_array_elements(coalesce(v_7b_m #> '{por_turno,tarde,pessoas}', '[]'::jsonb))) z
                                                order by x ->> 'payee_id') y order by y.nome);
        v_7b_txt := format('Quem vai: %s (você disse).',
                           public._agenda_lista(case when v_7b_m ->> 'presenca' = 'equipe' then array['você'] else '{}'::text[] end || v_7b_nomes));
      elsif v_7b_d ->> 'fonte' = 'dono' then
        v_7b_txt := case when jsonb_array_length(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) = 0 then v_7b_d ->> 'texto'
                         else rtrim(v_7b_d ->> 'texto', '.') || ' — falta a 2ª pessoa em '
                              || public._agenda_dias_texto(array(select distinct (e ->> 'dia')::date from jsonb_array_elements(v_7b_pl -> 'faltam') e))
                              || ' (' || v_7b_tf || ').' end;
      elsif v_7b_modo = 'sombra' and v_7b_d ->> 'fonte' = 'regra' then
        v_7b_txt := replace(replace(v_7b_d ->> 'texto', ' — suposição minha.', ''), '1 pessoa; ', '1 pessoa, ');
        v_7b_txt := 'Em teste: eu marcaria ' || lower(left(v_7b_txt, 1)) || substr(v_7b_txt, 2) || '.'
                    || case when coalesce((v_7b_m ->> 'pessoas_sugeridas')::int, 1) >= 2 then ' Hoje marco 2 pessoas.'
                            else ' Hoje marco 1 pessoa e ponho a 2ª nesses meios-dias quando alguém está livre.' end;
      elsif v_7b_modo = 'sombra' and coalesce((v_7b_m ->> 'pessoas_sugeridas')::int, 1) >= 2 then
        v_7b_txt := 'Em teste: eu marcaria 1 pessoa. Hoje marco 2 pessoas.';
      elsif v_7b_d ->> 'fonte' = 'regra' and jsonb_array_length(v_7b_ft) > 0 then
        v_7b_txt := format('1 pessoa; o serviço todo pede 2 (%s) — falta a 2ª pessoa em %s (%s).',
                           coalesce((select e ->> 'rotulo' from jsonb_array_elements(v_7b_d -> 'motivos') e where e ->> 'onde' = 'todos' limit 1),
                                    'o orçamento previu 2 técnicos'),
                           public._agenda_plural(jsonb_array_length(v_7b_ft), 'meio-dia', 'meios-dias'), v_7b_tf);
      elsif v_7b_d ->> 'fonte' = 'regra' and jsonb_array_length(v_7b_fi) + jsonb_array_length(v_7b_ff) > 0 then
        if jsonb_array_length(v_7b_fi) > 0 then
          v_7b_partes := v_7b_partes || format('%s (%s) %s',
            case when jsonb_array_length(v_7b_fi) = coalesce((v_7b_pl ->> 'ni')::int, 0)
                   then case when jsonb_array_length(v_7b_fi) = 1 then 'no primeiro meio-dia'
                             else format('nos %s primeiros meios-dias', jsonb_array_length(v_7b_fi)) end
                 else format('em %s dos %s primeiros meios-dias', jsonb_array_length(v_7b_fi), v_7b_pl ->> 'ni') end,
            public._agenda_dias_texto(array(select distinct (e ->> 'dia')::date from jsonb_array_elements(v_7b_fi) e)),
            coalesce(nullif(public._agenda_lista(array(select distinct on (e ->> 'motivo') e ->> 'frase' from jsonb_array_elements(v_7b_d -> 'motivos') e
                                                        where e ->> 'onde' = 'inicio' order by e ->> 'motivo')), ''), 'a tarefa'));
        end if;
        if jsonb_array_length(v_7b_ff) > 0 then
          v_7b_partes := v_7b_partes || format('%s (%s) %s',
            case when jsonb_array_length(v_7b_ff) = coalesce((v_7b_pl ->> 'nf')::int, 0)
                   then case when jsonb_array_length(v_7b_ff) = 1 then 'no último meio-dia'
                             else format('nos %s últimos meios-dias', jsonb_array_length(v_7b_ff)) end
                 else format('em %s dos %s últimos meios-dias', jsonb_array_length(v_7b_ff), v_7b_pl ->> 'nf') end,
            public._agenda_dias_texto(array(select distinct (e ->> 'dia')::date from jsonb_array_elements(v_7b_ff) e)),
            coalesce(nullif(public._agenda_lista(array(select distinct on (e ->> 'motivo') e ->> 'frase' from jsonb_array_elements(v_7b_d -> 'motivos') e
                                                        where e ->> 'onde' = 'fim' order by e ->> 'motivo')), ''), 'a tarefa'));
        end if;
        v_7b_txt := '1 pessoa; ' || public._agenda_lista(v_7b_partes)
                    || case when cardinality(v_7b_partes) > 1 then ' pedem 2' else ' pede 2' end || ' — falta a 2ª pessoa (' || v_7b_tf || ').';
      else
        v_7b_txt := v_7b_d ->> 'texto';
      end if;
    end if;
    v_7b_eq := jsonb_build_object(
      'pessoas', v_7b_pes,
      'dupla', jsonb_build_object('inicio', v_7b_d -> 'inicio', 'fim', v_7b_d -> 'fim', 'todos', v_7b_d -> 'todos',
                                  'fonte', v_7b_d ->> 'fonte', 'texto', v_7b_d ->> 'texto'),
      'notas', coalesce((select jsonb_agg(n ->> 'texto' order by o) from jsonb_array_elements(coalesce(v_7b_d -> 'notas', '[]'::jsonb))
                                                                   with ordinality t(n, o)), '[]'::jsonb),
      'modo', v_7b_modo,
      'falta', coalesce((select jsonb_agg(jsonb_build_object('dia', e -> 'dia', 'turno', e -> 'turno', 'onde', e -> 'onde') order by o)
                           from jsonb_array_elements(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb),
      'espera', v_7b_esp,
      'texto', v_7b_txt);
  end if;
  -- FASE 7b: fim
  -- FASE 7d: (7d P8; §5.8, §6.2) o bloco "Local" do cartão: nulo com os 6 modos desligados e na OS que já foi feita (o resto do cartão é o de antes, byte a byte)
  if so.status not in ('completed', 'invoiced', 'cancelled') then
    v_7d_local := public._agenda_local_bloco(p_os, p_hoje);
  end if;
  -- FASE 7d: fim
  -- FASE 7e: (7e P7, §5.6, §6.4, R7.3-1, R7.3-2) duracao.estimativa e duracao.promessa, só na OS que ainda vai ser feita (como o campo, a equipe e o local):
  --   estimativa: com o viés aplicado ao que o motor marca (agenda_meios_da_os traz vies: ligado de verdade, o congelado na marcação ou o aprovado; o congelado vale também com o freio e
  --   com o interruptor desligado, R7.14), os 2 números ("Estimativa minha: 2,5 dias pelo valor do orçamento × 1,17 (…) = 3 dias."); nos dias do dono, o texto do P3 ("Você disse 3 dias;
  --   contei 3,5 …", AG7-33). Em teste (o interruptor fora de desligado, sem o viés em uso): o que eu marcaria pelo medido da classe da OS, senão do geral, só se o número muda (lição 5).
  --   Sem base, diagnóstico (R7.5-8) e os dias do dono em teste: nada. A leitura cara (agenda_meios_da_os) só roda com o interruptor fora de desligado ou com a OS marcada ou aprovada com viés.
  --   promessa: com modo_promessa fora de desligado (o cru: o efetivo dele é sombra sempre), o prazo real com folga (agenda_promessa_da_os; AG7-32: nunca ao cliente), só com o fator
  --   medido (com o padrão, "pela folga do histórico" seria falso, R7.12-9) e quando a folga acrescenta dia (o fim com folga depois do fim do plano, lição 5).
  -- Sem nada a dizer, as 2 chaves ficam ausentes. Abaixo, no retorno, a mesma conta de duracao com as 2 a mais (a última chave igual do objeto vale): sem elas, a de cima, byte a byte.
  if so.status not in ('completed', 'invoiced', 'cancelled') then
    v_7e_c := public._agenda_cfg();
    if v_7e_c.modo_vies <> 'desligado' or coalesce(pl.vies_marcado <> 1, false) or pl.aprovado_com_vies is not null then
      v_7e_m := public.agenda_meios_da_os(p_os, p_hoje);
      if v_7e_m ? 'vies' and v_7e_m ? 'texto_vies' then
        v_7e_est := v_7e_m ->> 'texto_vies';
      elsif v_7e_m ? 'vies' and v_7e_m ? 'dias_sem_vies' then
        v_7e_vi := (v_7e_m ->> 'vies')::numeric;
        v_7e_ch := case when v_7e_m ->> 'vies_fonte' = 'marcado' then pl.vies_marcado_chave else public._agenda_vies_da_os(p_os) ->> 'chave' end;
        v_7e_est := format('Estimativa minha: %s pelo valor do orçamento × %s (%s costumam levar %s) = %s%s.',
                           public._agenda_dias((v_7e_m ->> 'dias_sem_vies')::numeric), public._agenda_num(v_7e_vi, 2),
                           coalesce(public._agenda_classe_texto_do_nivel(regexp_replace(coalesce(v_7e_ch, ''), '^estimativa:', '')), 'as OS'),
                           case when v_7e_vi > 1 then 'mais' else 'um pouco menos' end, public._agenda_dias((v_7e_m ->> 'dias')::numeric),
                           case v_7e_m ->> 'vies_fonte' when 'marcado' then ' (o que valia quando marquei)' when 'aprovado' then ' (o que você aprovou)' else '' end);
      elsif v_7e_c.modo_aprendizado <> 'desligado' and v_7e_c.modo_vies <> 'desligado' and public._agenda_margem_modo('vies') <> 'ligado'
            and coalesce(pl.estimativa_fonte, '') not in ('dono', 'aceita') then
        select x.calculado, x.chave into v_7e_vi, v_7e_ch
          from public.agenda_aprendizado x
         where x.item = 'vies' and x.calculado is not null
           and x.chave in ('estimativa:' || (public._agenda_classe_de_campo(p_os) ->> 'chave'), 'estimativa:todas')
         order by x.chave = 'estimativa:todas', x.chave
         limit 1;
        if v_7e_vi is not null and v_7e_vi <> 1 then
          v_7e_sug := public.os_duracao_sugerida(p_os);
          if not coalesce((v_7e_sug ->> 'sem_base')::boolean, false) and public._agenda_margem_tipo_os(p_os) is distinct from 'diagnóstico' then
            v_7e_hj := (v_7e_m ->> 'dias')::numeric;
            v_7e_dd := case when pl.dias is not null then greatest(0.5, round(pl.dias * v_7e_vi * 2) / 2)
                            else (public._agenda_dias_com_vies(v_7e_sug, v_7e_vi) ->> 'dias')::numeric end;
            if v_7e_hj is not null and v_7e_dd <> v_7e_hj then
              v_7e_est := format('Em teste: com o que %s costumam levar, eu marcaria %s (hoje %s).',
                                 coalesce(public._agenda_classe_texto_do_nivel(regexp_replace(v_7e_ch, '^estimativa:', '')), 'as OS'),
                                 public._agenda_dias(v_7e_dd), public._agenda_num(v_7e_hj, 1));
            end if;
          end if;
        end if;
      end if;
    end if;
    if v_7e_c.modo_aprendizado <> 'desligado' and v_7e_c.modo_promessa <> 'desligado' then
      begin
        v_7e_pr := public.agenda_promessa_da_os(p_os, p_hoje);
      exception when insufficient_privilege then
        v_7e_pr := null;
      end;
      if coalesce((v_7e_pr ->> 'ok')::boolean, false) and not coalesce((v_7e_pr ->> 'sem_plano')::boolean, false)
         and v_7e_pr ->> 'fonte' = 'aprendido' and coalesce((v_7e_pr ->> 'n')::int, 0) >= 1
         and (v_7e_pr ->> 'fim_com_folga')::date > (v_7e_pr ->> 'fim_plano')::date then
        v_7e_prom := format('Pela folga do histórico, pronto até %s (só para você: ao cliente não digo data de pronto).',
                            public._dia_curto((v_7e_pr ->> 'fim_com_folga')::date));
      end if;
    end if;
  end if;
  v_7e_dur := jsonb_build_object(
      'campo', v_campo,
      'dias', p #> '{duracao,dias}', 'fonte', p #>> '{duracao,fonte}',
      'fonte_texto', case p #>> '{duracao,fonte}' when 'dono' then 'você disse' when 'aceita' then 'você aceitou a minha estimativa'
                                                  else 'estimativa minha' end,
      'faixa', jsonb_build_object('otimista', p #> '{duracao,dias_otimista}', 'realista', p #> '{duracao,dias_realista}'),
      'faixa_texto', case when p #>> '{duracao,dias_otimista}' is not null
                          then 'faixa ' || public._agenda_faixa_dias((p #>> '{duracao,dias_otimista}')::numeric,
                                                                    (p #>> '{duracao,dias_realista}')::numeric) end,
      'texto', p #>> '{duracao,texto}')
    || case when v_7e_est is not null then jsonb_build_object('estimativa', v_7e_est) else '{}'::jsonb end
    || case when v_7e_prom is not null then jsonb_build_object('promessa', v_7e_prom) else '{}'::jsonb end;
  -- FASE 7e: fim
  return jsonb_build_object(
    -- FASE 5: o bloco "Cliente" do cartão (o que foi dito, a confirmação, as mensagens desta OS e o que espera você;
    -- _agenda_cliente_da_os). null sem o cliente.
    'cliente', public._agenda_cliente_da_os(p_os, p_hoje),
    -- FASE 5: fim
    -- FASE 7b: (7b P5) o bloco "Equipe" do cartão (nulo com modo_dupla desligado e na OS concluída, faturada ou cancelada)
    'equipe', v_7b_eq,
    -- FASE 7b: fim
    -- FASE 7d: (7d P8) o bloco "Local" do cartão
    'local', v_7d_local,
    -- FASE 7d: fim
    'os', so.id, 'numero', so.numero, 'status', so.status, 'estado', p ->> 'estado_texto',
    'marcos', public.agenda_marcos_da_os(p_os, p_hoje),
    'pode_entregar', so.status = 'completed' and so.delivered_at is null,
    'duracao', jsonb_build_object(
      -- FASE 6: (P8) a linha do fator de campo (nula em desligado e na OS concluída)
      'campo', v_campo,
      -- FASE 6: fim
      'dias', p #> '{duracao,dias}', 'fonte', p #>> '{duracao,fonte}',
      'fonte_texto', case p #>> '{duracao,fonte}' when 'dono' then 'você disse' when 'aceita' then 'você aceitou a minha estimativa'
                                                  else 'estimativa minha' end,
      'faixa', jsonb_build_object('otimista', p #> '{duracao,dias_otimista}', 'realista', p #> '{duracao,dias_realista}'),
      'faixa_texto', case when p #>> '{duracao,dias_otimista}' is not null
                          then 'faixa ' || public._agenda_faixa_dias((p #>> '{duracao,dias_otimista}')::numeric,
                                                                    (p #>> '{duracao,dias_realista}')::numeric) end,
      'texto', p #>> '{duracao,texto}'),
    -- FASE 7e: (7e P7) a duração com a estimativa e o prazo real (calculada logo acima, a mesma conta de cima com as 2 chaves a mais): a última chave igual do objeto vale e substitui a de
    -- cima; sem as 2, é a de cima, byte a byte
    'duracao', v_7e_dur,
    -- FASE 7e: fim
    'presenca_dono', jsonb_build_object(
      'valor', v_pres ->> 'presenca', 'pela_regra', coalesce(v_pres ->> 'fonte', 'regra') = 'regra',
      'texto', case v_pres ->> 'presenca' when 'abre_e_fecha' then 'Você abre e fecha'
                                          when 'sempre' then 'Você fica o tempo todo'
                                          when 'nunca' then 'Você não precisa ir'
                                          else 'Sem regra' end
               || case when coalesce(v_pres ->> 'fonte', 'regra') <> 'regra' then ' (você disse)'
                       when coalesce(v_pres ->> 'motivo', 'padrão') = 'padrão' then ' (pela regra)'
                       else ' (pela regra: ' || (v_pres ->> 'motivo') || ')' end),
    -- FASE 6: (P8) a presença com a aprendida (a última chave igual do objeto vale: substitui a de cima)
    'presenca_dono', v_pd,
    -- FASE 6: fim
    'material', jsonb_build_object(
      'estado', p #>> '{material,estado}',
      'itens', coalesce((select jsonb_agg(jsonb_build_object(
                  'descricao', i ->> 'descricao', 'nivel', i ->> 'nivel',
                  'nivel_texto', case i ->> 'nivel' when 'A' then 'na mão'
                                                    when 'B' then 'previsão do fornecedor'
                                                    when 'C' then 'previsão sua'
                                                    when 'D' then 'sem previsão firme'
                                                    else 'a comprar, sem prazo' end,
                  'situacao', i ->> 'situacao', 'previsao', i ->> 'data_texto', 'trecho', i ->> 'trecho',
                  'critico', coalesce((i ->> 'critico')::boolean, true), 'fornecedor', i ->> 'fornecedor')
                  order by o)
                  from jsonb_array_elements(coalesce(p #> '{material,itens}', '[]'::jsonb)) with ordinality t(i, o)), '[]'::jsonb)),
    'janela', jsonb_build_object(
      'bem_indisponivel', (select r ->> 'texto' from jsonb_array_elements(coalesce(p -> 'restricoes', '[]'::jsonb)) r
                            where r ->> 'tipo' = 'bem' limit 1),
      'nao_antes_de', pl.nao_antes_de, 'motivo', pl.nao_antes_motivo, 'precisa_ate', v_prec,
      'nao_antes_texto', case when pl.nao_antes_de is not null
                              then format('não antes de %s: %s', public._dia_curto(pl.nao_antes_de), pl.nao_antes_motivo) end,
      'precisa_ate_texto', case when v_prec is not null then 'o cliente precisa até ' || public._dia_curto(v_prec) end),
    'prometido_planejado', jsonb_build_object(
      'precisa_ate', v_prec, 'fim_publicado', v_fim, 'folga_du', v_folga,
      'texto', case
        when v_fim is not null and v_prec is not null and v_folga = 0
          then format('O plano termina %s, o dia em que o cliente precisa.', public._dia_curto(v_fim))
        when v_fim is not null and v_prec is not null and v_folga > 0
          then format('O plano termina %s; o cliente precisa até %s (%s de folga).', public._dia_curto(v_fim),
                      public._dia_curto(v_prec), public._agenda_plural(v_folga, 'dia útil', 'dias úteis'))
        when v_fim is not null and v_prec is not null
          then format('O plano termina %s, %s depois do que o cliente precisa (%s).', public._dia_curto(v_fim),
                      public._agenda_plural(-v_folga, 'dia útil', 'dias úteis'), public._dia_curto(v_prec))
        when v_fim is not null then format('O plano termina %s; o cliente não deu data.', public._dia_curto(v_fim))
        when v_prec is not null then format('O cliente precisa até %s; ainda não há plano.', public._dia_curto(v_prec))
        end),
    'planejado_realizado', coalesce((
      select jsonb_agg(jsonb_build_object(
               'dia', d.dia, 'rotulo', public._agenda_maiuscula(public._dia_curto(d.dia)),
               'pessoas_texto', nullif(public._agenda_pessoas_do_dia(d.pessoas), ''),
               'dia_texto', case when coalesce(d.dias_total, 1) > 1 and d.dia_n is not null
                                 then format('dia %s de %s', d.dia_n, d.dias_total) end,
               'meios', r.meios, 'resultado', r.resultado,
               'resultado_texto', case r.resultado when 'cumprido' then 'feito' when 'parcial' then 'feito em parte'
                                                   when 'sem_registro' then 'sem registro'
                                                   when 'nao_cumprido' then 'não aconteceu'
                                                   else case when d.dia < p_hoje then 'sem conferência' else 'previsto' end end,
               'motivo_texto', public._agenda_motivo_texto(r.motivo),
               'diaria', case when r.diaristas = 0 then null
                              when r.diaristas = r.com_diaria then 'lançada'
                              when d.dia <= p_hoje then 'a confirmar' end)
             order by d.dia)
        from public.v_agenda_dia d
        cross join lateral (
          select count(distinct (a.payee_id, a.turno)) filter (where a.presenca = 'turno')::int as meios,
                 case when bool_and(a.resultado is null) then null
                      when bool_or(a.resultado = 'cumprido') then 'cumprido'
                      when bool_or(a.resultado = 'parcial') then 'parcial'
                      when bool_or(a.resultado = 'sem_registro') then 'sem_registro'
                      else 'nao_cumprido' end as resultado,
                 min(a.motivo) filter (where a.resultado in ('parcial', 'nao_cumprido')) as motivo,
                 count(distinct a.payee_id) filter (where a.payee_id is distinct from v_dono)::int as diaristas,
                 count(distinct a.payee_id) filter (
                   where a.payee_id is distinct from v_dono
                     and (a.work_shift_id is not null
                          or exists (select 1 from public.work_shifts w join public.work_profiles wp on wp.id = w.work_profile_id
                                      where wp.payee_id = a.payee_id and w.data = a.dia and w.tipo = 'diaria'
                                        and coalesce(w.fracao, 0) > 0)))::int as com_diaria
            from public.agenda_alocacoes a
           where a.service_order_id = p_os and a.dia = d.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva') r
       where d.service_order_id = p_os and not d.reserva), '[]'::jsonb),
    'intervencoes', coalesce((
      select jsonb_agg(jsonb_build_object('dia', i.dia,
               'texto', format('%s: você %s (no plano: %s)', public._agenda_maiuscula(public._dia_curto(i.dia)),
                               case i.dita when 'manha' then 'foi de manhã' when 'tarde' then 'foi à tarde'
                                           when 'dia' then 'ficou o dia todo' else 'passou lá' end,
                               case i.prevista when 'nenhuma' then 'nada' when 'abertura' then 'abrir'
                                               when 'fechamento' then 'fechar' when 'abre_e_fecha' then 'abrir e fechar'
                                               else 'o turno' end))
             order by i.dia, i.criado_em)
        from public.agenda_intervencoes_do_dono i where i.service_order_id = p_os), '[]'::jsonb));
end;
$function$;

comment on function public.os_plano_da_os(uuid, date) is
  'Agenda de Produção (Fase 3, P7a; Fase 5, P6): o cartão "Plano" da OS — {cliente (Fase 5: _agenda_cliente_da_os — o contato, o que foi dito ao cliente e se ainda vale, a confirmação, as 5 mensagens mais recentes desta OS e o que espera o dono; null sem o cliente), os, numero, status, estado, marcos (agenda_marcos_da_os), pode_entregar (concluída sem entrega), duracao {dias, fonte dono|aceita|sugerida, fonte_texto, faixa {otimista, realista}, faixa_texto, texto}, presenca_dono {valor, pela_regra, texto "Você abre e fecha (pela regra)"}, material {estado, itens:[{descricao, nivel A–E, nivel_texto, situacao, previsao, trecho, critico, fornecedor}]}, janela {bem_indisponivel, nao_antes_de, motivo, precisa_ate, nao_antes_texto, precisa_ate_texto}, prometido_planejado {precisa_ate, fim_publicado, folga_du, texto}, planejado_realizado:[{dia, rotulo, pessoas_texto, dia_texto, meios, resultado, resultado_texto, motivo_texto, diaria ("lançada" | "a confirmar" | null — nunca o valor)}], intervencoes:[{dia, texto}]}. Administrador e financeiro (com login) ou service_role; senão 42501. FASE 6 (P8): duracao.campo = a linha do fator de campo da classe da OS (agenda_fator_de_campo: "Em teste: as OS de energia em motorhome levam até 1,7× o combinado (7 OS); hoje seria 1,7×, e vale 1,5× (padrão).") — nula com modo_aprendizado desligado e na OS concluída, faturada ou cancelada; presenca_dono.aprendida = o motivo da presença aprendida ("você foi a 3 de 4 OS de energia em motorhome"; nulo sem ela), e o texto "Você fica o tempo todo (pelo que medi: …)". CORREÇÃO FASE 6 (C1, item 3): com a presença guardada na 1ª publicação, o texto diz "(pelo que medi quando planejei: …)". CORREÇÃO FASE 6 (C2, regressão B8): sem o sub no JWT, só o service_role (ou nenhum JWT); o authenticated sem sub recebe 42501. FASE 7b (P5, §5.4, §6.4, R4.3, R4.4): o bloco equipe {pessoas (as que o serviço pede fora da dupla: as da sugestão, 2 na dupla o tempo todo, as da equipe dita), dupla {inicio, fim, todos, fonte dono|regra|nenhuma, texto} (_agenda_dupla_da_os), notas [texto] (o espaço apertado: "Atenção: casa de máquinas — confira se precisa de duas pessoas."), modo, falta [{dia, turno, onde}] (os meios-dias do plano em que a dupla está sem a 2ª pessoa, de hoje em diante: _agenda_dupla_no_plano), espera (a dupla dita que espera a 2ª pessoa: a classe 4 dupla, ou o "fora" dupla da última montagem que citou a OS, sem compromisso dela de hoje em diante), texto} — o texto: a regra "1 pessoa; em dupla nos 2 primeiros meios-dias (troca do banco de baterias) — suposição minha."; com a 2ª pessoa faltando no plano "1 pessoa; nos 2 primeiros meios-dias (ter 10/11) a troca do banco de baterias pede 2 — falta a 2ª pessoa (só Alex está na equipe)." (o tempo todo: "1 pessoa; o serviço todo pede 2 (o orçamento previu 2 técnicos) — falta a 2ª pessoa em 12 meios-dias (só Alex está na equipe)."); a dita "Em dupla nos 2 primeiros meios-dias (você disse)." e, esperando, "Em dupla o tempo todo (você disse) — espero a 2ª pessoa: só Alex está na equipe."; a equipe dita "Quem vai: Roberto e João (você disse)."; em teste a regra "Em teste: eu marcaria 1 pessoa, em dupla nos 2 primeiros meios-dias (troca do banco de baterias). Hoje marco 1 pessoa e ponho a 2ª nesses meios-dias quando alguém está livre." (sem a regra uma_pessoa: "Hoje marco 2 pessoas."); nada "1 pessoa.". Nulo com modo_dupla desligado e na OS concluída, faturada ou cancelada (o resto do cartão é o de antes, byte a byte). FASE 7d (P8; §5.8, §6.2): o bloco local {texto, fonte, suposicao, tipo, nome, vagas, viagem_texto, bem_texto, perguntei, combinar [{texto, ate, vencido, em_teste}], notas []} (_agenda_local_bloco). Nulo com os 6 modos desligados e na OS concluída, faturada ou cancelada. Nunca valor. FASE 7e (P7, §5.6, §6.4, R7.3-1, R7.3-2): duracao.estimativa (com o viés aplicado ao que o motor marca, os 2 números; nos dias do dono, o texto do P3; em teste, o que eu marcaria, só se muda) e duracao.promessa (o prazo real com folga, só para o dono e só com o fator medido e dia a mais), ausentes sem nada a dizer; o resto de duracao igual.';

-- _agenda_mudancas (de 20261030100500_agenda_correcao_revisao.sql:715; md5 do corpo de antes 5a6ed8a5b67682beae32b68f520d9b00)
create or replace function public._agenda_mudancas(p_de date, p_ate date, p_executada boolean, p_fechamento boolean,
                                                   p_agora timestamptz default null)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with
  -- CORREÇÃO FASE 6: (C2) item 6 e texto 2: o que a agenda aprendeu sozinha (tipo aprendizado, origem motor/vigia), com a
  -- mesma régua de b (o período, executada, contada e desfeita), agrupado por ITEM do mesmo instante: o fator e a presença
  -- mudam várias classes de uma vez (um grupo só); o fornecedor e os outros, um grupo por chave. r = 1 é a linha do grupo
  -- (a classe mais fina ainda não desfeita); as outras entram nele (junto, em todos). O texto sem o "*desfaz aprendizado*
  -- volta…" da ação; palavra = a coisa do *desfaz aprendizado <coisa>* desta linha.
  ap as (
    select q.*, first_value(q.id) over w as cabeca, row_number() over w as r,
           min(q.id::text) over (partition by q.grupo) as min_id
           -- CORREÇÃO 29/10 (revisão): a ordem fixa do aprendizado (o fator, a presença, a folga, o valor, a capacidade, a
           -- carga e, por fornecedor, o atraso e o prazo). As linhas do aprendizado gravadas no mesmo instante desempatavam pelo id
           -- (aleatório): a cada rodada o corte de texto_max levava uma linha diferente (o R10g de agenda_fase6_rodada.sql falhava às
           -- vezes) e o "e mais N" do aviso do gestor também mudava.
           , case q.item when 'fator' then '1' when 'presenca' then '2' when 'aviso_folga' then '3' when 'mo' then '4'
                         when 'capacidade_dono' then '5' when 'carga' then '6'
                         when 'fornecedor_atraso' then '7:' || coalesce(q.chave, '') || ':1'
                         when 'fornecedor_prazo' then '7:' || coalesce(q.chave, '') || ':2'
                         else '9:' || coalesce(q.item, '') end as ordem
           -- CORREÇÃO 29/10 (revisão): fim
      from (select a.id, a.tipo, a.service_order_id as os, a.dia, a.proposta_id, a.criada_em as em,
                   a.antes ->> 'item' as item, a.antes ->> 'chave' as chave, (a.depois ->> 'em_uso')::numeric as valor,
                   regexp_replace(public._agenda_vence_no_dia(a.texto, a.dia, p_ate), '\s*\*desfaz aprendizado\* volta[^*]*$', '') as texto,
                   a.desfazivel_ate is not null and a.desfeita_em is null and (p_agora is null or a.desfazivel_ate >= p_agora) as desfazivel,
                   a.desfeita_em is not null as desfeita,
                   concat_ws(':', a.antes ->> 'item',
                             case when a.antes ->> 'item' not in ('fator', 'presenca') then a.antes ->> 'chave' end,
                             to_char(a.criada_em at time zone 'UTC', 'YYYYMMDDHH24MISSUS')) as grupo,
                   case a.antes ->> 'nivel' when 'fina' then 1 when 'sistema' then 2 when 'bem' then 3 when 'todas' then 4 else 5 end as nr,
                   case a.antes ->> 'item'
                     when 'fator' then 'fator' when 'presenca' then 'presença' when 'mo' then 'valor'
                     when 'aviso_folga' then 'folga' when 'capacidade_dono' then 'capacidade' when 'carga' then 'carga'
                     when 'fornecedor_atraso' then public._agenda_fornecedor_curto((a.antes ->> 'chave')::uuid)
                     -- (7e P7, R7.5-18) as palavras da margem: o tempo das OS (o viés: *desfaz aprendizado dias*), a folga da semana (*semana*) e o seu tempo de compra (*compra*); "folga" segue
                     -- sendo a do aviso de atraso. O viés só ganha a palavra quando é a única linha dele no instante: *desfaz aprendizado dias* volta todas as do viés juntas (o geral e as
                     -- classes), e o "volta só essa" de uma delas prometeria menos do que faz; com várias, a linha fica sem palavra (vale o *desfaz aprendizado*, que volta tudo).
                     when 'vies' then case when (select count(*) from public.agenda_acoes b
                                                  where b.tipo = 'aprendizado' and b.executada and b.criada_em = a.criada_em
                                                    and b.antes ->> 'item' = 'vies') = 1 then 'dias' end
                     when 'folga_semana' then 'semana' when 'tempo_compra' then 'compra'
                     -- (7e: fim)
                     when 'fornecedor_prazo' then public._agenda_fornecedor_curto((a.antes ->> 'chave')::uuid) end as palavra
              from public.agenda_acoes a
             where a.dia between p_de and p_ate and a.executada = p_executada and a.tipo = 'aprendizado'
               and a.origem in ('motor', 'vigia')
               and (not p_fechamento or (a.contada_em is null and a.desfeita_em is null))) q
    window w as (partition by q.grupo order by q.desfeita, q.nr, q.chave, q.id)
  ),
  -- CORREÇÃO FASE 6: fim
  b as (
    -- FASE 3 (revisão, item 5): o texto gravado noutro dia diz a data no lugar de "vence hoje" (p_ate é o hoje de quem lê:
    -- o foco mudancas, o fechamento e a tela passam p_hoje).
    select a.id, a.tipo, a.service_order_id as os, a.dia, a.proposta_id,
           public._agenda_vence_no_dia(a.texto, a.dia, p_ate) as texto, a.criada_em as em,
           a.desfazivel_ate is not null and a.desfeita_em is null and (p_agora is null or a.desfazivel_ate >= p_agora) as desfazivel,
           a.desfeita_em is not null as desfeita,
           coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as nome, so.service_order_number as numero
      from public.agenda_acoes a
      left join public.service_orders so on so.id = a.service_order_id
      left join public.clients cl on cl.id = so.client_id
     where a.dia between p_de and p_ate and a.executada = p_executada
       and a.tipo not in ('resultado', 'desfazer', 'fixar')
       and (a.origem in ('motor', 'vigia') or (not p_fechamento and a.origem = 'conferencia'))
       -- CORREÇÃO FASE 6: (C2) item 6 e texto 2: o que a agenda aprendeu sozinha vem do ramo dele (ap: uma linha por item)
       and a.tipo <> 'aprendizado'
       -- CORREÇÃO FASE 6: fim
       and (not p_fechamento or (a.contada_em is null and a.desfeita_em is null))
    -- FASE 5: o acorde da mensagem ao cliente (tipo cliente, origem vigia, depois.acorde) é um aviso ao dono, não uma
    -- mudança; e a ação do replano que o pedido do cliente causou (depois.replano_acoes da ação dele) vai no grupo da ação
    -- do cliente (filhos), nunca sozinha — sem contar duas vezes.
       and not (a.tipo = 'cliente' and a.origem = 'vigia' and coalesce((a.depois ->> 'acorde')::boolean, false))
       and not exists (select 1 from public.agenda_acoes c
                        where c.origem = 'cliente' and c.tipo = 'cliente' and c.depois -> 'replano_acoes' ? a.id::text)
    -- FASE 5: fim
    -- FASE 4: (P3) o material que a agenda registrou sozinha — a chegada pela nota importada (origem nota; P4: a previsão
    -- pela mensagem do fornecedor, origem fornecedor) — entra como as ações do motor e da vigia.
    union all
    select a.id, a.tipo, a.service_order_id as os, a.dia, a.proposta_id,
           public._agenda_vence_no_dia(a.texto, a.dia, p_ate) as texto, a.criada_em as em,
           a.desfazivel_ate is not null and a.desfeita_em is null and (p_agora is null or a.desfazivel_ate >= p_agora) as desfazivel,
           a.desfeita_em is not null as desfeita,
           coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as nome, so.service_order_number as numero
      from public.agenda_acoes a
      left join public.service_orders so on so.id = a.service_order_id
      left join public.clients cl on cl.id = so.client_id
     where a.dia between p_de and p_ate and a.executada = p_executada
       and a.tipo = 'material' and a.origem in ('nota', 'fornecedor')
       and (not p_fechamento or (a.contada_em is null and a.desfeita_em is null))
    -- FASE 4: fim
    -- FASE 5: o que a resposta do cliente mudou sozinho (origem cliente: o dia que ele confirmou, o pedido de outro dia, o
    -- acesso anotado, o opt-out) entra como as ações do motor e da vigia; o "*desfaz <nome>* volta como estava." que o
    -- texto já traz sai (a frase do grupo o põe enquanto ainda vale).
    union all
    select a.id, a.tipo, a.service_order_id as os, a.dia, a.proposta_id,
           regexp_replace(public._agenda_vence_no_dia(a.texto, a.dia, p_ate), '\s*\*desfaz [^*]+\* volta como estava\.$', '') as texto,
           a.criada_em as em,
           a.desfazivel_ate is not null and a.desfeita_em is null and (p_agora is null or a.desfazivel_ate >= p_agora) as desfazivel,
           a.desfeita_em is not null as desfeita,
           coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as nome, so.service_order_number as numero
      from public.agenda_acoes a
      left join public.service_orders so on so.id = a.service_order_id
      left join public.clients cl on cl.id = so.client_id
     where a.dia between p_de and p_ate and a.executada = p_executada
       and a.origem = 'cliente' and a.tipo in ('cliente', 'fixar')
       and (not p_fechamento or (a.contada_em is null and a.desfeita_em is null))
    -- FASE 5: fim
    -- CORREÇÃO FASE 6: (C2) item 6 e texto 2: o aprendizado, UMA linha por item do mesmo instante (ap, r = 1): o texto da
    -- classe mais fina e "Também nas OS de … e nas …" para as outras classes do item (com o valor de cada uma quando não é
    -- o mesmo de todas); sem o "*desfaz aprendizado* volta" de cada ação; na 1ª linha desfazível (a ordem dos grupos: em,
    -- o menor id), UMA vez, "*desfaz aprendizado* volta tudo; *desfaz aprendizado <coisa>* volta só essa" — com uma linha
    -- só, "*desfaz aprendizado* volta.". Sem nome: o "*desfaz <nome>* volta como estava." do grupo não se aplica (M1).
    -- NOTA (desvio): a frase vai no fim da 1ª linha, não da última — o fechamento (480 letras) e o foco (texto_max) cortam
    -- pelas últimas linhas, e no fim a frase sumiria em toda rodada com 3 trocas ou mais.
    union all
    select h.id, h.tipo, h.os, h.dia, h.proposta_id,
           h.texto
           || coalesce(' Também ' || nullif(public._agenda_lista(array(
                select case when o.chave = 'todas' then 'em todas as OS'
                            when o.r = 2 then 'n' || public._agenda_classe_texto_do_nivel(o.chave)
                            else 'n' || regexp_replace(public._agenda_classe_texto_do_nivel(o.chave), '^as OS ', 'as ') end
                       || case when exists (select 1 from ap v where v.grupo = h.grupo and v.valor is distinct from h.valor)
                               then ' (' || public._agenda_aprendizado_valor(o.item, o.valor) || ')' else '' end
                  from ap o
                 where o.grupo = h.grupo and o.r > 1
                 order by o.r), null), '') || '.', '')
           || case when h.desfazivel
                        -- CORREÇÃO 29/10 (revisão): a 1ª linha desfazível do aprendizado pela mesma ordem fixa.
                        -- antes: and h.id = (select f.id from ap f where f.r = 1 and f.desfazivel order by f.em, f.min_id limit 1)
                        and h.id = (select f.id from ap f where f.r = 1 and f.desfazivel order by f.em, f.ordem, f.min_id limit 1)
                        -- CORREÇÃO 29/10 (revisão): fim
                   then case when (select count(*) from ap f where f.r = 1 and f.desfazivel) > 1 and h.palavra is not null
                             then format(' *desfaz aprendizado* volta tudo; *desfaz aprendizado %s* volta só %s.', h.palavra,
                                         case when h.item in ('fornecedor_atraso', 'fornecedor_prazo')
                                              then 'o que é de ' || h.palavra else 'essa' end)
                             else ' *desfaz aprendizado* volta.' end
                   else '' end as texto,
           h.em, h.desfazivel, h.desfeita, null::text as nome, null::text as numero
      from ap h
     where h.r = 1
    -- CORREÇÃO FASE 6: fim
  ),
  -- FASE 5: as ações do replano que o pedido do cliente causou: no grupo da ação dele (contam com ela; frase só a dela)
  filhos as (
    select f.id, f.tipo, f.service_order_id as os, f.dia, f.proposta_id, f.texto, f.criada_em as em, false as desfazivel,
           f.desfeita_em is not null as desfeita, null::text as nome, null::text as numero, 'a:' || b.id as grupo
      from b
      join public.agenda_acoes c on c.id = b.id and c.origem = 'cliente' and c.tipo = 'cliente'
      cross join lateral jsonb_array_elements_text(coalesce(c.depois -> 'replano_acoes', '[]'::jsonb)) r(fid)
      join public.agenda_acoes f on f.id::text = r.fid
     where f.executada = p_executada and (not p_fechamento or (f.contada_em is null and f.desfeita_em is null))
  ),
  -- FASE 5: fim
  dono as (
    select b.*, coalesce(case when b.tipo = 'publicar' then 'p:' || b.proposta_id end, 'a:' || b.id) as grupo, false as junto
      from b where b.tipo <> 'status'
  ),
  st as (
    -- FASE 3: a mesma ordem (criada_em, OS, id) para achar o grupo
    select s.*, coalesce((select d.grupo from dono d where d.os = s.os and d.dia = s.dia order by d.em, d.os, d.id limit 1),
                         'a:' || s.id) as grupo
      from b s where s.tipo = 'status'
  ),
  todos as (
    select d.* from dono d
    union all
    select s.id, s.tipo, s.os, s.dia, s.proposta_id, s.texto, s.em, s.desfazivel, s.desfeita, s.nome, s.numero, s.grupo,
           s.grupo <> 'a:' || s.id
      from st s
    -- FASE 5: o replano pedido pelo cliente, junto da ação dele (sem frase própria)
    union all
    select f.id, f.tipo, f.os, f.dia, f.proposta_id, f.texto, f.em, f.desfazivel, f.desfeita, f.nome, f.numero, f.grupo, true
      from filhos f
    -- FASE 5: fim
    -- CORREÇÃO FASE 6: (C2) item 6 e texto 2: as outras classes do mesmo item do aprendizado, no grupo da linha dele (contam
    -- com ela e saem com ela; sem frase própria)
    union all
    select j.id, j.tipo, j.os, j.dia, j.proposta_id, j.texto, j.em, j.desfazivel, j.desfeita, null::text, null::text,
           'a:' || j.cabeca, true
      from ap j
     where j.r > 1
    -- CORREÇÃO FASE 6: fim
  ),
  g as (
    -- FASE 3: dentro do grupo, a ordem de gravação é criada_em, OS, id (o que entra na mesma transação tem o mesmo
    -- criada_em e o id é aleatório: o G10 de agenda_fase2_leituras.sql falhava cerca de 1 vez em 15)
    select t.grupo,
           case when t.grupo like 'p:%' then 'publicacao' else 'acao' end as tipo,
           min(t.proposta_id::text) filter (where t.tipo = 'publicar') as proposta_id,
           jsonb_agg(t.id order by t.em, t.os nulls last, t.id) as acao_ids,
           coalesce(jsonb_agg(t.texto order by t.em, t.os nulls last, t.id) filter (where not t.junto), '[]'::jsonb) as itens,
           min(t.os::text) filter (where not t.junto) as os,
           min(t.nome) filter (where not t.junto) as nome,
           min(t.numero) filter (where not t.junto) as numero,
           coalesce(bool_or(t.desfazivel) filter (where not t.junto), false) as desfazivel,
           coalesce(bool_and(t.desfeita) filter (where not t.junto), false) as desfeita,
           min(t.em) as em, min(t.os::text) as desempate_os, min(t.id::text) as desempate
           -- CORREÇÃO 29/10 (revisão): a ordem fixa do grupo do aprendizado (nula nos outros).
           , min((select f.ordem from ap f where f.id = t.id)) as ordem
           -- CORREÇÃO 29/10 (revisão): fim
      from todos t
     group by t.grupo
  )
  select coalesce(jsonb_agg(jsonb_build_object('grupo', g.grupo, 'tipo', g.tipo, 'proposta_id', g.proposta_id,
                                               'acao_ids', g.acao_ids, 'itens', g.itens, 'os', g.os, 'nome', g.nome,
                                               'numero', g.numero, 'desfazivel', g.desfazivel, 'desfeita', g.desfeita,
                                               'em', g.em)
                            -- FASE 3: entre os grupos, a mesma ordem (criada_em, OS, id)
                            -- CORREÇÃO 29/10 (revisão): entre os grupos do mesmo instante sem OS, o aprendizado pela ordem fixa (antes, o id).
                            -- antes: order by g.em, g.desempate_os nulls last, g.desempate), '[]'::jsonb)
                            order by g.em, g.desempate_os nulls last, g.ordem nulls first, g.desempate), '[]'::jsonb)
                            -- CORREÇÃO 29/10 (revisão): fim
    from g;
$function$;

comment on function public._agenda_mudancas(date, date, boolean, boolean, timestamptz) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6: a ordem de gravação criada_em, OS, id): o que a agenda mudou sozinha (motor e vigia; fora do fechamento também o replano da conferência) com agenda_acoes.dia em [p_de, p_ate], em grupos — a publicação da semana (as ações publicar da mesma proposta) e cada outra ação; o status que acompanha a publicação ou o replano da mesma OS no mesmo dia vai no grupo dela. Fase 4, P3: também a ação material da nota importada e da mensagem do fornecedor (origens nota e fornecedor). p_executada false = o que a sombra teria feito; p_fechamento = só o não contado e não desfeito, só motor e vigia. [{grupo, tipo, proposta_id, acao_ids, itens, os, nome, numero, desfazivel, desfeita, em}]. Fase 5, P5: também o que a resposta do cliente mudou (origem cliente: fixar e cliente — o dia confirmado, o pedido de outro dia, o acesso, o opt-out), com as ações do replano dele (depois.replano_acoes) no mesmo grupo (contadas juntas, a frase só a do cliente); o acorde da mensagem ao cliente (tipo cliente, origem vigia, depois.acorde) não é mudança e não entra. CORREÇÃO FASE 6 (C2, item 6 e texto 2): o aprendizado sai UMA linha por item do mesmo instante (o fator e a presença de várias classes juntos: a classe mais fina e "Também nas OS de …"; as outras ações no grupo, junto), sem o "*desfaz aprendizado* volta" de cada ação; na 1ª linha desfazível, uma vez, "*desfaz aprendizado* volta tudo; *desfaz aprendizado <coisa>* volta só essa". CORREÇÃO 29/10 (revisão): as linhas do aprendizado do mesmo instante saem numa ordem fixa (fator, presença, folga, valor, capacidade, carga e, por fornecedor, o atraso e o prazo), não pelo id aleatório; a frase do *desfaz aprendizado* vai na 1ª delas. FASE 7e (P7, R7.5-18): a palavra de cada item da margem no *desfaz aprendizado <coisa>*: dias (o viés, só quando é a única linha dele no instante), semana (a folga da semana) e compra (o tempo de compra). Assinatura e chaves iguais.';

-- agenda_desfazer_dito (de 20261029100950_agenda_fase6_correcao_textos.sql:155; md5 do corpo de antes 3c1982e2e441330deb7d12b278b9d739)
create or replace function public.agenda_desfazer_dito(p_autor uuid, p_alvo text default null, p_canal text default 'whatsapp',
                                                       p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor uuid := public._autor_da_agenda(p_autor);
  v_ref   jsonb;
  v_id    uuid;
  v_r     jsonb;
  v_txts  text[] := '{}';
  v_falha text;
  -- FASE 6: (P6) o alvo "aprendizado"
  v_aprend boolean := false;
  -- FASE 6: fim
begin
  -- CORREÇÃO FASE 6: (C2) item 6: *desfaz aprendizado <coisa>* desfaz só o que é daquela coisa — fator, presença, valor (ou
  -- diária), folga, capacidade (ou carga), fornecedor (o atraso e o prazo de todos) ou o nome de um fornecedor (os dois
  -- dele) —: das ações aprendizado ainda desfazíveis que são dela, as do instante mais novo (o mesmo lote), tudo ou nada.
  -- Cada uma trava só a sua chave (_agenda_desfazer_aprendizado); as outras do lote continuam em uso. *desfaz aprendizado*
  -- sozinho continua desfazendo o lote inteiro (abaixo). A coisa que não é item nem fornecedor = nao_achei.
  if public._agenda_normal(p_alvo) ~ '^(o )?aprendizado [a-z0-9]' then
    declare
      v_coisa text := regexp_replace(public._agenda_normal(p_alvo), '^(o )?aprendizado ', '');
      v_itens text[];
      v_ids   uuid[];
      v_de    text;
    begin
      v_itens := case v_coisa
                   when 'fator' then array['fator']
                   when 'presenca' then array['presenca']
                   when 'valor' then array['mo']
                   when 'diaria' then array['mo']
                   when 'folga' then array['aviso_folga']
                   when 'capacidade' then array['capacidade_dono', 'carga']
                   when 'carga' then array['capacidade_dono', 'carga']
                   when 'fornecedor' then array['fornecedor_atraso', 'fornecedor_prazo'] end;
      v_de := case v_coisa
                when 'fator' then 'do fator'
                when 'presenca' then 'da sua presença'
                when 'valor' then 'do valor por diária'
                when 'diaria' then 'do valor por diária'
                when 'folga' then 'da folga do aviso de atraso'
                when 'capacidade' then 'da carga da semana'
                when 'carga' then 'da carga da semana'
                when 'fornecedor' then 'dos fornecedores' end;
      -- (7e P7, R7.5-18; marca sem FASE porque está dentro do bloco da correção C2 da Fase 6) as palavras da margem: *desfaz aprendizado dias* (o tempo das OS: o viés, o geral, as
      -- classes e o dos seus dias), *semana* (a folga da semana) e *compra* (o seu tempo de compra). "folga" continua sendo a do aviso de atraso (aviso_folga), como antes.
      if v_itens is null then
        v_itens := case v_coisa when 'dias' then array['vies'] when 'semana' then array['folga_semana'] when 'compra' then array['tempo_compra'] end;
        v_de := case v_coisa when 'dias' then 'dos dias das OS' when 'semana' then 'da folga da semana' when 'compra' then 'do seu tempo de compra' end;
      end if;
      -- (7e: fim)
      if v_itens is null then
        -- o nome do fornecedor: o curto ("Kamell"), o de exibição, o fantasia ou a razão social, como o dono escreve
        select 'de ' || public._agenda_fornecedor_curto(s.id) into v_de
          from public.suppliers s
         where v_coisa in (public._agenda_normal(public._agenda_fornecedor_curto(s.id)), public._agenda_normal(s.display_name),
                           public._agenda_normal(s.trade_name), public._agenda_normal(s.name))
         order by s.active desc nulls last, s.id
         limit 1;
        if v_de is null then
          return jsonb_build_object('ok', false, 'mudou', false, 'status', 'nao_achei',
            'texto', 'Não achei isso no que eu aprendi. Diga *desfaz aprendizado* e fator, presença, valor, folga, capacidade ou o nome do fornecedor (ou só *desfaz aprendizado*, que volta tudo).');
        end if;
      end if;
      with m as (
        select a.id, a.criada_em, a.antes
          from public.agenda_acoes a
          left join public.suppliers s on a.antes ->> 'item' in ('fornecedor_atraso', 'fornecedor_prazo')
                                      and s.id::text = a.antes ->> 'chave'
         where a.tipo = 'aprendizado' and a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora
           and case when v_itens is not null then a.antes ->> 'item' = any (v_itens)
                    else s.id is not null
                         and v_coisa in (public._agenda_normal(public._agenda_fornecedor_curto(s.id)),
                                         public._agenda_normal(s.display_name), public._agenda_normal(s.trade_name),
                                         public._agenda_normal(s.name)) end)
      select array_agg(m.id order by m.antes ->> 'item', m.antes ->> 'chave', m.id) into v_ids
        from m
       where m.criada_em = (select max(x.criada_em) from m x);
      if coalesce(cardinality(v_ids), 0) = 0 then
        return jsonb_build_object('ok', false, 'mudou', false, 'status', 'nenhuma',
          'texto', format('Não tenho mudança do aprendizado %s para desfazer agora.', v_de));
      end if;
      begin
        foreach v_id in array v_ids loop
          v_r := public.agenda_desfazer(v_id, v_autor, 'dono', p_hoje, p_agora);
          if not coalesce((v_r ->> 'ok')::boolean, false) then
            v_falha := v_r ->> 'texto';
            raise exception using errcode = 'P0098', message = 'desfazer recusado';
          end if;
          v_txts := v_txts || (v_r ->> 'texto');
        end loop;
      exception when sqlstate 'P0098' then
        return jsonb_build_object('ok', false, 'mudou', false, 'texto', v_falha);
      end;
      return jsonb_build_object('ok', true, 'mudou', true, 'acoes', to_jsonb(v_ids), 'texto', array_to_string(v_txts, ' '));
    end;
  end if;
  -- CORREÇÃO FASE 6: fim
  -- FASE 6: (P6) *desfaz aprendizado* (spec-fase6 §5.6): o último lote de ações aprendizado desfazíveis — as do mesmo
  -- instante (o que a mesma rodada ou a mesma decisão mudou: o fator muda as 4 chaves de uma vez) —, tudo ou nada. Sem
  -- nenhuma, "não tenho". Os outros alvos seguem por agenda_acao_desfazivel, como antes
  if public._agenda_normal(p_alvo) in ('aprendizado', 'o aprendizado') then
    v_aprend := true;
    select jsonb_build_object('status', 'ok',
                              'acao_id', (array_agg(a.id order by a.antes ->> 'item', a.antes ->> 'chave', a.id))[1],
                              'acao_ids', jsonb_agg(a.id order by a.antes ->> 'item', a.antes ->> 'chave', a.id))
      into v_ref
      from public.agenda_acoes a
     where a.tipo = 'aprendizado' and a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora
       and a.criada_em = (select max(b.criada_em) from public.agenda_acoes b
                           where b.tipo = 'aprendizado' and b.executada and b.desfeita_em is null and b.desfazivel_ate >= p_agora)
    having count(*) > 0;
    v_ref := coalesce(v_ref, jsonb_build_object('status', 'nenhuma',
                                                'texto', 'Não tenho mudança do aprendizado para desfazer agora.'));
  else
  -- FASE 6: fim
  v_ref := public.agenda_acao_desfazivel(p_alvo, p_hoje, p_agora);
  -- FASE 6: (P6) o fim do "se é o aprendizado"
  end if;
  -- FASE 6: fim
  if v_ref ->> 'status' is distinct from 'ok' then
    return jsonb_build_object('ok', false, 'mudou', false, 'status', v_ref ->> 'status', 'texto', v_ref ->> 'texto',
                              'opcoes', v_ref -> 'opcoes');
  end if;
  -- "desfaz semana" são várias ações: tudo ou nada
  begin
    for v_id in select x::uuid from jsonb_array_elements_text(coalesce(v_ref -> 'acao_ids', jsonb_build_array(v_ref ->> 'acao_id'))) x loop
      v_r := public.agenda_desfazer(v_id, v_autor, 'dono', p_hoje, p_agora);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        v_falha := v_r ->> 'texto';
        raise exception using errcode = 'P0098', message = 'desfazer recusado';
      end if;
      v_txts := v_txts || (v_r ->> 'texto');
    end loop;
  exception when sqlstate 'P0098' then
    return jsonb_build_object('ok', false, 'mudou', false, 'texto', v_falha);
  end;
  -- FASE 6: (P6) o lote do aprendizado: os "Desfeito: …" um depois do outro (não é a publicação da semana)
  if v_aprend then
    return jsonb_build_object('ok', true, 'mudou', true, 'acoes', v_ref -> 'acao_ids', 'texto', array_to_string(v_txts, ' '));
  end if;
  -- FASE 6: fim
  return jsonb_build_object('ok', true, 'mudou', true, 'acoes', v_ref -> 'acao_ids',
    'texto', case when cardinality(v_txts) = 1 then v_txts[1]
                  else format('Desfiz a publicação da semana (%s): %s', public._agenda_plural(cardinality(v_txts), 'mudança', 'mudanças'),
                              array_to_string(v_txts, ' ')) end);
end;
$function$;

comment on function public.agenda_desfazer_dito(uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a palavra *desfaz* (+ o nome, o número ou "semana") — agenda_acao_desfazivel (ambíguo ou nada: a frase pronta, nada muda) + agenda_desfazer(via dono) de cada ação; "semana" é tudo ou nada. Executa direto: é a ordem exata do dono. Admin pelo _autor_da_agenda. Fase 6 (P6): o alvo "aprendizado" = o último lote de ações aprendizado desfazíveis (as do mesmo instante), tudo ou nada; o texto é o "Desfeito: …" de cada uma. CORREÇÃO FASE 6 (C2, item 6): *desfaz aprendizado <coisa>* (fator, presença, valor/diária, folga, capacidade/carga, fornecedor ou o nome de um fornecedor) desfaz só as ações daquela coisa do instante mais novo, tudo ou nada; cada uma trava só a sua chave; *desfaz aprendizado* sozinho continua o lote. A coisa desconhecida = nao_achei; sem mudança = nenhuma. FASE 7e (P7, R7.5-18): *desfaz aprendizado dias* (o viés), *semana* (a folga da semana) e *compra* (o tempo de compra). A recusa da coisa que não existe é a de antes (a saída é a mesma: *desfaz aprendizado* sozinho volta tudo).';

-- ── 3. Portas ─────────────────────────────────────────────────────────────────────────────────────
-- A nova tem a porta de _agenda_saude_comunicacao: agenda_saude é invoker e o administrador logado a chama. Nunca anon. As recriadas não mudam de porta.
revoke all on function public._agenda_saude_margem(date, timestamptz) from public, anon;
grant execute on function public._agenda_saude_margem(date, timestamptz) to authenticated, service_role;

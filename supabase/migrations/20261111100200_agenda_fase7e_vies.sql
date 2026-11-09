-- Agenda de Produção, Fase 7, etapa 7e ("A margem que aprende"), pacote P3: o viés na duração. O que as OS medidas ensinam sobre o quanto o estimador erra passa a ajustar os dias da OS que ainda
-- não foi marcada, e o que o dono disse passa a ser corrigido às claras (AG7-33: "Sim, pode corrigir").
-- Spec: scratchpad agenda-pesquisa/spec-fase7e.md (§5.2 e o bloco R7, que vale sobre o corpo: R7.1, R7.3-2, R7.5-8, 10, 11, 12, R7.6, R7.8, R7.12, R7.13); nomes: fase7-registro.md; o registro do pacote: notas-fase7e.md.
-- Depende de 20261111100000 (P1) e 20261111100100 (P2). Copiado das definições MAIS NOVAS: os_duracao_sugerida (20261101100300_agenda_fase7b_motor.sql:300), agenda_meios_da_os (20261101100300_agenda_fase7b_motor.sql:536), _agenda_aplicar_planejar (20261107100870_agenda_fase7d_correcao4.sql:901), _agenda_aprender_congelar (20261111100100_agenda_fase7e_medicao.sql:549), _agenda_aprender_congelar_marcacao (20261111100100_agenda_fase7e_medicao.sql:217), agenda_aplicar (20261031100750_agenda_fase7a_revisao.sql:1179).
--
-- ═══ NÃO APLICADA ═══ Existe para revisão e espera o OK (publicar/exec/aplicar.sh, nunca db push: esta versão fica antes das 20261116* que já estão em produção). Uma coluna nova (os_planejamento.aprovado_com_vies, nula) e funções; nenhum dado.
--
-- POR QUE: a estimativa pelo valor do orçamento erra de um jeito medível, e com o P2 a rodada mede esse erro; falta usar o que foi medido. O R7.3-2 pede também corrigir os dias que o dono diz, sempre mostrando os dois números, com saída.
--
-- O QUE MUDA, só com modo_vies ligado de verdade (o freio apaga: _agenda_margem_modo) e viés em uso diferente de 1 (fora isso, a saída de antes, byte a byte):
--   1. _agenda_aprender_vies: o passo da rodada (o P7 o liga), que grava vies por chave nos 2 grupos (estimativa e dono) com a credibilidade da §3.1-7.
--   2. os_duracao_sugerida: a saída ganha vies, vies_chave, dp_planejado, dias_planejado, pessoas_planejado e texto_vies pelas 3 saídas com dias (R7.5-8: viram uma, pela v_f7_extra). Os números de antes (dias_realista, dp_realista, pessoas...) NÃO mudam.
--   3. agenda_meios_da_os: dias, total e molde corrigidos no ramo da fonte do estimador, pelo congelado (vies_marcado) ou pelo de agora; a fonte orcamento GRAVADA corrige sobre p.dias (R7.5-11), a dupla ligada refaz o total com o viés (R7.5-10).
--      Os dias que o dono disse: pela chave dono:, com os dois números em texto_vies; acima de estimativa_max_diarias, a correção não entra (R7.3-2).
--   4. _agenda_aplicar_planejar: a saída do dono (R7.3-2, conflito 2d): repetir os dias grava vies_dono_fixo, vies_marcado 1,00 e marcado_em.
--   5. As correções da conferência (lições do P1 e do P2): _agenda_aprender_congelar lê o molde também sem o viés (agenda.sem_vies), para a medida não medir a si mesma; agenda_aplicar, na duração aprovada com o viés, grava o número sem o viés em dias (a medida lê esse) e o aprovado em aprovado_com_vies (o plano lê esse), sem mudar nada quando não há correção aplicada; _agenda_aprender_congelar_marcacao congela a correção dos dias do dono pela chave dono:.
--
-- O QUE NÃO MUDA: nada em agenda_vigiar, agenda_cliente_vigiar nem agenda_propor; em sombra, zero chamada nova (só leitura de variável de sessão e de campos já na mão), salvo 1 leitura de config na OS com dias do dono sem marcação (hoje, nenhuma). _agenda_aprendido NÃO é recriada (R7.5-7).
-- Nenhuma mensagem nova ao dono, à equipe ou ao cliente: os textos novos só aparecem em ligado, e quem os mostra é o P7. Nada de dinheiro.
--
-- DESFAZER (na ordem):
--   cada recriada volta à versão anterior pelo corpo da origem acima; depois, drop das 3 novas:
--   drop function if exists public._agenda_aprender_vies(date, timestamptz);
--   drop function if exists public._agenda_dias_com_vies(jsonb, numeric);
--   drop function if exists public._agenda_vies_dono_da_os(uuid);
--   alter table public.os_planejamento drop column if exists aprovado_com_vies;

-- ── 0. A coluna ───────────────────────────────────────────────────────────────────────────────────
-- Conferência do P3: a duração só sugerida que o dono aprova com o viés aplicado tem dois números. dias fica com o de sem o viés (fonte aceita: é o que a medida lê e o que o dono:, se vier, não corrige por cima); esta guarda o que foi aprovado e publicado (dias e total: com a dupla da 7b ligada o total não é dias × 2).
alter table public.os_planejamento add column if not exists aprovado_com_vies jsonb;
comment on column public.os_planejamento.aprovado_com_vies is 'Agenda de Produção (Fase 7e, P3; §3.1-10): a duração aprovada pelo dono quando a sugestão vinha com o viés — {dias, total, vies, em}. Nula em todo o resto. agenda_meios_da_os a lê no lugar de dias (o plano publicado não muda pelo aprendizado); a medida lê dias, sem o viés. Dizer os dias de novo apaga.';

-- ── 1. As novas ──────────────────────────────────────────────────────────────────────────────────

-- §5.2: dias pelo viés, sobre uma saída de os_duracao_sugerida (ou qualquer objeto com horas, mo e pessoas). As pessoas não se recalculam (R7.5-12). d12: o R$ é o da config, nunca o aprendido, porque o viés já corrige o estimador.
create or replace function public._agenda_dias_com_vies(p_sug jsonb, p_vies numeric)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_dp0    numeric;
  v_dp     numeric;
  v_pes    int := coalesce((p_sug ->> 'pessoas')::int, 1);
begin
  v_dp0 := greatest(coalesce((p_sug ->> 'horas')::numeric, 0) / c.jornada_horas, coalesce((p_sug ->> 'mo')::numeric, 0) / c.mo_por_diaria_real);
  v_dp := round(v_dp0 * p_vies, 2);
  return jsonb_build_object('dp', v_dp, 'pessoas', v_pes,
                            'dias', trim_scale(greatest(0.5, round(v_dp / v_pes * 2) / 2)),
                            'dias_padrao', trim_scale(greatest(0.5, round(v_dp0 / v_pes * 2) / 2)));
end;
$function$;

comment on function public._agenda_dias_com_vies(jsonb, numeric) is
  'Agenda de Produção (Fase 7e, P3; §5.2, R7.5-12, d12): os dias de uma OS com o viés — dp = max(horas ÷ jornada, MO ÷ mo_por_diaria_real) × viés (2 casas), pessoas = as da sugestão (não recalcula), dias = meio dia mais perto de dp ÷ pessoas, nunca menos de meio dia. {dp, pessoas, dias, dias_padrao (os dias com viés 1)}. STABLE, invoker; porta para authenticated e service_role (os leitores invoker).';

-- AG7-33 (R7.3-2): o viés dos dias que o dono disse, pela chave dono: — a fina, depois a geral —, pelo mesmo leitor que respeita o freio e o vies_corrige_dono. A irmã de _agenda_vies_da_os, que lê estimativa:.
create or replace function public._agenda_vies_dono_da_os(p_os uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_fina  text := 'dono:' || (public._agenda_classe_de_campo(p_os) ->> 'chave');
  v_geral text := 'dono:todas';
  v_uso   numeric;
  v_chave text;
  v_n     int;
begin
  v_uso := public._agenda_margem_em_uso('vies', v_fina);
  v_chave := case when v_uso is not null then v_fina end;
  if v_uso is null then
    v_uso := public._agenda_margem_em_uso('vies', v_geral);
    v_chave := case when v_uso is not null then v_geral end;
  end if;
  select a.n into v_n from public.agenda_aprendizado a where a.item = 'vies' and a.chave = v_chave;
  return jsonb_build_object('chave', v_chave, 'vies_em_uso', v_uso, 'n', v_n);
end;
$function$;

comment on function public._agenda_vies_dono_da_os(uuid) is
  'Agenda de Produção (Fase 7e, P3; AG7-33, R7.3-2): o viés da correção dos dias do dono — {chave (dono:<bem>:<sistema> ou dono:todas), vies_em_uso (nulo = sem correção), n}, por _agenda_margem_em_uso (que já pede o modo efetivo e vies_corrige_dono). STABLE, invoker; porta para authenticated e service_role.';

-- §5.2: o passo da rodada do aprendizado (o P7 o põe em agenda_aprender). Para cada grupo (estimativa, dono), o geral e cada classe fina, com a credibilidade (§3.1-7): com n medidas, Z = n ÷ (n + k), e o valor = Z × mediana + (1 − Z) × base. A base do geral é 1 (o orçamento acertou); a base da classe é o geral sem arredondar. Passo que falha numa chave registra e segue.
create or replace function public._agenda_aprender_vies(p_hoje date, p_agora timestamptz)
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
  v_med    numeric;
  v_cred   numeric;
  v_calc   numeric;
  v_pad    numeric;
  v_det    jsonb;
  v_est    jsonb := '{}'::jsonb;
  n_ch     int := 0;
  n_acao   int := 0;
  n_err    int := 0;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  for r in
    with med as (
      select g.grupo, m.service_order_id as os, so.service_order_number as numero,
             case g.grupo when 'estimativa' then m.razao_estimativa else m.razao_dono end as razao,
             m.concluida_em, m.classe_bem || ':' || m.classe_sistema as fina
        from public.agenda_medidas_os m
        join public.service_orders so on so.id = m.service_order_id
        cross join (values ('estimativa'), ('dono')) g(grupo)
       where m.motivo_razao is null
         and m.concluida_em between p_hoje - c.aprender_janela_dias and p_hoje),
    chaves as (
      select med.*, x.chave, x.nivel, x.ordem
        from med
        cross join lateral (values (med.grupo || ':todas', 'todas', 1),
                                   (med.grupo || ':' || med.fina, 'fina', 2)) x(chave, nivel, ordem)
       where med.razao is not null),
    recentes as (
      select ch.*, row_number() over (partition by ch.chave order by ch.concluida_em desc, ch.os) as rn
        from chaves ch),
    por_chave as (
      select rc.grupo, rc.chave, rc.nivel, rc.ordem, count(*)::int as n,
             array_agg(rc.razao order by rc.concluida_em desc, rc.os) as razoes,
             jsonb_agg(jsonb_build_object('os', rc.os, 'numero', rc.numero, 'razao', rc.razao, 'em', rc.concluida_em)
                       order by rc.concluida_em desc, rc.os) as amostra
        from recentes rc
       where rc.rn <= c.fator_amostra_max
       group by rc.grupo, rc.chave, rc.nivel, rc.ordem)
    select pc.grupo, pc.chave, pc.nivel, pc.ordem, pc.n, pc.razoes, pc.amostra from por_chave pc
    union all
    -- a chave que já tem linha e ficou sem medida volta a medir
    select split_part(a.chave, ':', 1), a.chave, a.nivel, case a.nivel when 'fina' then 2 else 1 end, 0, null::numeric[], '[]'::jsonb
      from public.agenda_aprendizado a
     where a.item = 'vies' and not exists (select 1 from por_chave pc where pc.chave = a.chave)
     order by 1, 4, 2
  loop
    n_ch := n_ch + 1;
    begin
      -- o geral vem antes das finas do mesmo grupo (order by), e é a base delas sem arredondar
      v_med := public._agenda_percentil(r.razoes, 0.5);
      if r.nivel = 'todas' then
        v_cred := public._agenda_credibilidade(v_med, r.n, 1, c.credibilidade_k);
        v_geral := v_cred;
        v_pad := 1;
      else
        v_cred := public._agenda_credibilidade(v_med, r.n, v_geral, c.credibilidade_k);
        v_pad := coalesce((select a.em_uso from public.agenda_aprendizado a where a.item = 'vies' and a.chave = r.grupo || ':todas'), 1);
      end if;
      v_calc := case when v_med is not null then round(least(greatest(v_cred, c.vies_min), c.vies_max), 2) end;
      v_det := jsonb_build_object('mediana', round(v_med, 4), 'z', round(r.n::numeric / (r.n + c.credibilidade_k), 4))
               || case when r.nivel = 'fina' then jsonb_build_object('geral', round(v_geral, 4)) else '{}'::jsonb end;
      v := public._agenda_aprendizado_gravar('vies', r.chave, r.nivel, v_calc, r.n, r.amostra, v_pad, v_det, p_agora);
      v_est := v_est || jsonb_build_object(v ->> 'estado', coalesce((v_est ->> (v ->> 'estado'))::int, 0) + 1);
      if v ->> 'acao_id' is not null then n_acao := n_acao + 1; end if;
    exception when others then
      perform public.log_app_error('db', format('aprendizado, viés %s: %s', r.chave, sqlerrm), 'agenda', 'aprender:vies', 'error',
                                   jsonb_build_object('chave', r.chave, 'sqlstate', sqlstate, 'p_hoje', p_hoje));
      n_err := n_err + 1;
    end;
  end loop;
  return jsonb_build_object('chaves', n_ch, 'estados', v_est, 'acoes', n_acao, 'erros', n_err);
end;
$function$;

comment on function public._agenda_aprender_vies(date, timestamptz) is
  'Agenda de Produção (Fase 7e, P3; §5.2): o passo do viés da rodada do aprendizado — para estimativa (razao_estimativa) e dono (razao_dono), sobre as medidas com motivo_razao nulo na janela, as fator_amostra_max mais recentes por chave: o geral (mediana encolhida para 1 pela credibilidade) e cada classe fina (encolhida para o geral sem arredondar), entre vies_min e vies_max, 2 casas; o gravador anda por passo. A chave sem medida volta a medir. {chaves, estados, acoes, erros}. Definer, sem grant a ninguém: o P7 a põe em agenda_aprender.';

-- ── 2. As recriadas (conforme a R7.1 e as lições das conferências) ───────────────────────────────

-- os_duracao_sugerida (de 20261101100300_agenda_fase7b_motor.sql:300; md5 do corpo de antes d9045ab0351f3c4bd2d5e8a3d3d4bef3)
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
  -- FASE 7e: (7e P3, §5.2) o viés
  v_7e_v    jsonb;
  v_7e_uso  numeric;
  v_7e_d    jsonb;
  v_7e_cls  text;
  -- FASE 7e: fim
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
  -- FASE 7e: (7e P3, §5.2, R7.5-8, R7.5-12, d12, R7.8) o viés na estimativa pelo valor: com modo_vies ligado na linha e o freio solto (a linha já está na mão: em sombra e com o freio, zero chamada nova) e viés em uso diferente de 1 (_agenda_vies_da_os, que passa pelo modo efetivo: com o freio, nulo).
  -- As 3 saídas com dias passam a sair por aqui: as chaves entram em v_f7_extra e a saída de cima já traz o R$ aprendido quando houver. Os números de antes não mudam: dias_realista, dp_realista e pessoas continuam os de sem o viés (quem lê a medida usa horas, mo e pessoas, que não mudam). O R$ aprendido fica de fora da conta do viés (d12).
  if c.modo_vies = 'ligado' and not c.gestor_so_propor then
    v_7e_v := public._agenda_vies_da_os(p_so_id);
    v_7e_uso := (v_7e_v ->> 'vies_em_uso')::numeric;
    if v_7e_uso is not null and v_7e_uso <> 1 then
      v_7e_d := public._agenda_dias_com_vies(jsonb_build_object('horas', v_horas, 'mo', v_mo, 'pessoas', v_pes), v_7e_uso);
      v_7e_cls := public._agenda_classe_texto_do_nivel(regexp_replace(coalesce(v_7e_v ->> 'chave', ''), '^estimativa:', ''));
      -- (o texto só quando o número muda: "3 dias × 1,02 = 3 dias" não diz nada)
      v_f7_extra := v_f7_extra || jsonb_build_object(
        'vies', v_7e_uso, 'vies_chave', v_7e_v ->> 'chave', 'dp_planejado', (v_7e_d ->> 'dp')::numeric, 'dias_planejado', (v_7e_d ->> 'dias')::numeric,
        'pessoas_planejado', (v_7e_d ->> 'pessoas')::int)
        || case when (v_7e_d ->> 'dias')::numeric <> (v_7e_d ->> 'dias_padrao')::numeric then jsonb_build_object(
        'texto_vies', format('Estimativa minha: %s pelo valor do orçamento × %s (%s costumam levar %s) = %s.',
                             public._agenda_dias((v_7e_d ->> 'dias_padrao')::numeric), public._agenda_num(v_7e_uso, 2), coalesce(v_7e_cls, 'as OS'),
                             case when v_7e_uso > 1 then 'mais' else 'um pouco menos' end, public._agenda_dias((v_7e_d ->> 'dias')::numeric))) else '{}'::jsonb end;
    end if;
  end if;
  -- FASE 7e: fim
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
  'Agenda de Produção (Fase 1, P3): a duração "pelo valor" (plano §4.2 com a correção do material). mo = linhas de serviço − material de texto livre que entra na compra; horas = linhas por hora; diárias-pessoa otimista = max(horas ÷ jornada_horas, mo ÷ mo_por_diaria_preco), realista = max(horas ÷ jornada_horas, mo ÷ mo_por_diaria_real); 1 pessoa se o realista ≤ 1, senão equipe_sugerida; dias arredondados ao meio dia; sugerida = o meio dia mais perto da média. Sem mão de obra nem horas: {sem_base:true, texto:"sem base para estimar: quantos dias?"}. Nunca é gravada. FASE 6 (P2): o realista usa _agenda_mo_por_diaria_real() (o R$ por diária aprendido em uso, senão mo_por_diaria_real); com o aprendido em uso a saída ganha mo_fonte = aprendido e mo_por_diaria (sem ele, a saída de antes). FASE 7 (7a P2), atrás do portão _agenda_gestor_regra (falso = a saída de antes, byte a byte): mo_limpa — a linha cujo nome do serviço (_agenda_nome_do_servico) casa mo_fora_regex sai da mão de obra e das horas (fora_da_mo); uma_pessoa (AG7-04) — pessoas = equipe_padrao (até 1 diária = 1), greatest(equipe_sugerida, 2) só com dupla_dita = todos (pessoas_motivo) e, sem nada dito, alerta_dupla pelo 1º gatilho de dupla_gatilhos/dupla_notas no nome do serviço; diagnostico — a OS de diagnóstico leva diagnostico_dias com 1 pessoa (diagnostico: true, "meio dia de diagnóstico; depois eu reavalio"). CORREÇÃO DA 7a (revisão da etapa; achado 10): dentro da rodada da vigia (agenda.rodada) e com alguma regra do gestor na duração (mo_limpa, uma_pessoa, diagnostico), a duração de cada OS é calculada uma vez e lembrada (_agenda_rodada_duracao_lembrar/_guardar, chave <OS>:<agenda.gestor>, a marca de _agenda_rodada_marca) enquanto a transação não grava nada no que ela lê; e o nome do serviço de cada linha é calculado uma vez por linha (antes, uma vez por gatilho de dupla). O resultado é o mesmo, byte a byte. FASE 7b (P4, §5.3): com modo_dupla ligado e a regra uma_pessoa falsa, pessoas = 1 (a dupla vem por meio-dia em agenda_meios_da_os, só onde a tarefa pede); com a regra, a do 7a; fora de ligado, a saída de antes, byte a byte. FASE 7e (P3): com modo_vies ligado (efetivo; o freio apaga) e viés em uso diferente de 1, a saída ganha vies, vies_chave, dp_planejado, dias_planejado, pessoas_planejado (R$ da config × viés, d12; as pessoas não mudam) e texto_vies; os números de sempre não mudam. O viés não entra na medida. Em sombra ou sem viés em uso, byte a byte a de antes.';

-- agenda_meios_da_os (de 20261101100300_agenda_fase7b_motor.sql:536; md5 do corpo de antes 33c1422c7bfdbcd66813b41f67abb82b)
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
  -- FASE 7e: (7e P3, §5.2, AG7-33) o viés na duração
  v_7e_dono  boolean;
  v_7e_vies  numeric;
  v_7e_fonte text;
  v_7e_v     jsonb;
  v_7e_c     public.agenda_config;
  v_7e_dv    jsonb;
  v_7e_dp    numeric;
  v_7e_bruto numeric;
  v_7e_cont  numeric;
  v_7e_n     int;
  v_7e_saida jsonb;
  v_7e_total int;
  v_7e_verbo text;
  -- FASE 7e: fim
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
  -- FASE 7e: (7e P3, §5.2, R7.5-11, R7.5-12, R7.3-2, §3.1-10) o viés na duração, depois de resolvida a fonte. Três contas, nenhuma muda a dupla dita (conflito 2a) e nenhuma mexe no que está gravado (a correção é na leitura):
  --   o aprovado com o viés (fonte aceita, aprovado_com_vies): os dias e o total que o dono aprovou, como foram publicados, sem somar outra correção (§3.1-10). p.dias guarda o número sem o viés, que é o que a medida lê.
  --   o dono (dias ditos por ele, fonte dono/aceita): chave dono:, "você disse 3; contei 3,5" ("você aceitou", na aceita); acima de estimativa_max_diarias, a correção não entra e o texto diz os dois (R7.3-2).
  --   a fonte orcamento GRAVADA (p.dias, "quanto falta", R7.5-11): sobre p.dias, nunca por v_sug.
  --   a estimativa (sugerida ou orcamento calculada): _agenda_dias_com_vies, com as pessoas da sugestão (R7.5-12); sem base ou diagnóstico, nada (R7.5-8).
  -- Só é correção o que muda o número: com o corrigido igual ao de antes (3 × 1,02 = 3), a saída é a de antes, sem chave nem texto, e repetir os dias não é a saída do dono.
  -- O valor: o congelado na marcação, se for da mesma conta (uma OS marcada pela estimativa não usa esse valor nos dias do dono, nem o contrário), senão o de agora. "agenda.sem_vies" = on: a medida pede o número sem o viés (_agenda_aprender_congelar, a mesma simulação de agenda.gestor; ver notas): o viés mede o estimador e o plano, nunca o que ele mesmo mudou.
  -- R7.8: em sombra, zero chamada nova: variável de sessão e campos já na mão. A exceção é a OS com dias do dono sem marcação, que lê a config 1 vez para saber se o modo está ligado (a estimativa lê v_sug, que já passou pelo modo efetivo).
  if coalesce(current_setting('agenda.sem_vies', true), '') <> 'on' then
    if v_fonte = 'aceita' and p.aprovado_com_vies is not null then
      v_7e_bruto := v_dias;
      v_dias := (p.aprovado_com_vies ->> 'dias')::numeric;
      v_7e_total := (p.aprovado_com_vies ->> 'total')::int;
      v_7e_saida := jsonb_build_object('vies', p.aprovado_com_vies -> 'vies', 'vies_fonte', 'aprovado', 'dias_sem_vies', trim_scale(v_7e_bruto));
    else
      v_7e_dono := coalesce(v_fonte in ('dono', 'aceita'), false);
      v_7e_vies := case when p.vies_marcado_chave is null then p.vies_marcado
                        when (p.vies_marcado_chave like 'dono:%') = v_7e_dono then p.vies_marcado end;
      v_7e_fonte := 'marcado';
      if v_7e_vies is null then
        v_7e_fonte := 'agora';
        if v_7e_dono then
          if (public._agenda_cfg()).modo_vies = 'ligado' then
            v_7e_v := public._agenda_vies_dono_da_os(p_so_id);
            v_7e_vies := (v_7e_v ->> 'vies_em_uso')::numeric;
          end if;
        elsif v_sug ? 'vies' then
          v_7e_vies := (v_sug ->> 'vies')::numeric;
        end if;
      end if;
      if v_7e_vies is not null and v_7e_vies <> 1 then
        v_7e_bruto := v_dias;
        if v_7e_dono then
          v_7e_cont := greatest(0.5, round(v_dias * v_7e_vies * 2) / 2);
          if v_7e_cont <> v_dias then
            v_7e_c := public._agenda_cfg();
            v_7e_n := coalesce((v_7e_v ->> 'n')::int, (select a.n from public.agenda_aprendizado a where a.item = 'vies' and a.chave = p.vies_marcado_chave), 0);
            v_7e_verbo := case when v_fonte = 'aceita' then 'aceitou' else 'disse' end;
            if v_7e_cont * coalesce((v_sug ->> 'pessoas')::int, 1) > v_7e_c.estimativa_max_diarias then
              v_7e_saida := jsonb_build_object('vies', v_7e_vies, 'vies_fonte', v_7e_fonte, 'vies_acima_max', true, 'dias_dono', trim_scale(v_7e_bruto), 'dias_corrigidos', trim_scale(v_7e_cont),
                'texto_vies', format('Você %s %s; pelo histórico dos seus dias seriam %s (nos serviços assim, os seus dias levaram %s×; %s OS), mas isso passa do que eu corrijo sozinho: fico com o seu número.',
                                     v_7e_verbo, public._agenda_dias(v_7e_bruto), public._agenda_dias(v_7e_cont), public._agenda_num(v_7e_vies, 2), v_7e_n));
            else
              v_dias := v_7e_cont;
              v_7e_saida := jsonb_build_object('vies', v_7e_vies, 'vies_fonte', v_7e_fonte, 'dias_dono', trim_scale(v_7e_bruto),
                'texto_vies', format('Você %s %s; contei %s (nos serviços assim, os seus dias levaram %s×; %s OS).',
                                     v_7e_verbo, public._agenda_dias(v_7e_bruto), public._agenda_num(v_dias, 1), public._agenda_num(v_7e_vies, 2), v_7e_n));
            end if;
          end if;
        elsif not coalesce((v_sug ->> 'sem_base')::boolean, false) and public._agenda_margem_tipo_os(p_so_id) is distinct from 'diagnóstico' then
          if p.dias is not null then
            v_7e_cont := greatest(0.5, round(p.dias * v_7e_vies * 2) / 2);
          else
            v_7e_dv := public._agenda_dias_com_vies(v_sug, v_7e_vies);
            v_7e_cont := (v_7e_dv ->> 'dias')::numeric;
            v_7e_dp := (v_7e_dv ->> 'dp')::numeric;
          end if;
          if v_7e_cont <> v_dias then
            v_dias := v_7e_cont;
            v_7e_saida := jsonb_build_object('vies', v_7e_vies, 'vies_fonte', v_7e_fonte, 'dias_sem_vies', trim_scale(v_7e_bruto));
          end if;
        end if;
      end if;
    end if;
    if v_7e_saida is not null then
      v_f7 := coalesce(v_f7, '{}'::jsonb) || v_7e_saida;
    end if;
  end if;
  -- FASE 7e: fim

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
  -- FASE 7e: (7e P3, §3.1-10) a OS aprovada com o viés: o total que foi publicado (com a dupla da 7b ligada, ele não é dias × 2), para o plano não encolher nem crescer depois de aprovado
  if v_7e_total is not null then
    v_total := v_7e_total;
  end if;
  -- FASE 7e: fim
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
        -- (7e P3, R7.5-10) a dupla ligada refaz o total por dp_realista: sem isto o viés sumia. Com o viés que entrou na conta acima: as diárias-pessoa já corrigidas (R$ da config, d12) ou, nos dias gravados, a mesma conta × viés.
        if v_7e_saida is not null then
          v_7b_pme := greatest(1, round(coalesce(v_7e_dp * 2, v_7b_pme * v_7e_vies)))::int;
        end if;
        -- (7e: fim)
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
  'Agenda de Produção (Fase 2, P2): o molde dos meios-dias do que o dono disse — total = dias × 2 (meio dia = 1); por turno os diaristas ditos ("dia" vale nos dois) e quantos (desejado; sem equipe dita, as pessoas da sugestão, e o dono que fica o turno inteiro é uma delas); a presença do dono: o que ele disse → ele na equipe dita (turno nos turnos dele) → a regra d05 (sempre = turno em todos; abre_e_fecha = abertura no 1º e fechamento no último); restantes = total − cumpridos (cumprido/sem registro/passado sem resultado = 1, parcial = 0,5) − os meios-dias vigentes de hoje em diante. Sem os dias ditos: fonte sugerida (dias_realista), só para reserva e simulação. {ok, fonte, dias, total, restantes, passos, presenca, abre, fecha, dono_turno, por_turno, molde[{k, turno, pessoas_ditas, desejado, dono}]}. FASE 7 (7a P2): sem os dias ditos e com a regra estimativa (_agenda_gestor_regra), a fonte é ''orcamento'' com os dias de _agenda_gestor_estimativa quando ela usa (D7-1: a estimativa do orçamento vale como dias firmes; nada é gravado), e a saída ganha estimativa_motivo (por que não usa: situacao, sem_base, grande, embutida; null quando usa) e situacao_pendente; os dias de fonte ''orcamento'' gravados com o portão falso são lidos como ''sugerida''. Sem a regra, a saída de antes, byte a byte. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; AG7-02/AG7-04): com a regra uma_pessoa, o dono que fica o turno inteiro (presença sempre: a marina nova, o que ele disse) não é a pessoa da estimativa — os técnicos desejados por turno são as pessoas da sugestão, e ele vai junto; no diagnóstico e no comissionamento (dele), a de antes. Sem a regra, a de antes, byte a byte. FASE 7b (P4, §5.3, R4.3(e)): com modo_dupla fora de desligado, sem a equipe dita e com 1 pessoa por serviço, a dupla por meio-dia — dupla (a de _agenda_dupla_da_os: fonte dono ou regra) || {ni, nf, todos, pm (a soma das pessoas do molde), pm_estimativa, pk (as pessoas de cada passo do molde: 2 nos ni primeiros, nos nf últimos ou em todos, 1 nos outros), modo}, dk (as pessoas dos passos que restam) e dk_dono_conta (o dono que fica o turno inteiro é uma das pessoas, salvo a regra da correção 2 da 7a: presença sempre fora do diagnóstico e do comissionamento). Ligado e com os dias estimados, a duração conserva as diárias-pessoa: total = pm − ni − nf, com 2 × (ni + nf) <= pm (cortando primeiro o fim) e o tempo todo = ceil(pm / 2) meios-dias em dupla (Lenine 12 → 10; Vanderlei 15 → 13). Em teste ou com os dias ditos, o total é o de antes. O por_turno.desejado continua o de antes. Sem dupla (ou desligado), a saída de antes, byte a byte. FASE 7e (P3): com o viés em uso de verdade ou congelado na marcação, os dias do estimador (sugerida, orcamento calculada: _agenda_dias_com_vies; orcamento gravada: sobre p.dias, R7.5-11) saem corrigidos, com vies, vies_fonte (marcado ou agora) e dias_sem_vies; a dupla ligada conserva o viés (R7.5-10). A aceita aprovada com o viés lê aprovado_com_vies (vies_fonte aprovado): os dias e o total publicados, sem somar outra correção. Os dias do dono (dono/aceita) corrigem pela chave dono: (AG7-33), com dias_dono e texto_vies dizendo os dois; acima de estimativa_max_diarias a correção não entra (vies_acima_max, dias_corrigidos). Correção que o arredondamento apaga não é correção: a saída é a de antes. agenda.sem_vies = on devolve a conta sem o viés (a medida). Fora disso, byte a byte a de antes.';

-- _agenda_aplicar_planejar (de 20261107100870_agenda_fase7d_correcao4.sql:901; md5 do corpo de antes 98673d30737ab66bfc48e0f9a3677bea)
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
  -- FASE 7d: (7d P7; §5.7) o que o dono disse do local e do bem: as chaves, a hora do *grava*, os autorizados, o antes e o depois da ação e as perguntas que ele fechou
  c_7d_chaves constant text[] := array['local_id', 'bem_situacao', 'bem_exige', 'descer_quem', 'entrada_em', 'retirada_em', 'viagem', 'autorizados'];
  v_7d_tem    boolean := coalesce(p_dados, '{}'::jsonb) ?| array['local_id', 'bem_situacao', 'bem_exige', 'descer_quem', 'entrada_em', 'retirada_em', 'viagem', 'autorizados'];
  v_7d_agora  timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  v_7d_ids    uuid[];
  v_7d_vig_a  uuid[];
  v_7d_vig_d  uuid[];
  v_7d_linhas jsonb;
  v_7d_lin_d  jsonb;
  v_7d_local  uuid;
  v_7d_antes  jsonb := '{}'::jsonb;
  v_7d_dep    jsonb := '{}'::jsonb;
  v_7d_q      public.agenda_perguntas%rowtype;
  v_7d_item   jsonb;
  v_7d_abert  uuid[];
  v_7d_fech   uuid[] := '{}';
  v_7d_trecho text;
  v_7d_lin    jsonb;   -- (correção O2, O3) a linha de agenda_locais que o *grava* achou ou criou
  v_7d_recolhido uuid; -- (correção G6) a linha que esta correção deixou sem uso
  -- FASE 7d: fim
  -- FASE 7e: (7e P3, AG7-33) a saída do dono
  v_7e_m     jsonb;
  v_7e_fixar boolean := false;
  -- FASE 7e: fim
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
    -- FASE 7d: (7d P7) com o local ou o bem na mesma linha, o resto da linha ainda grava: a volta de baixo só serve ao prometido sozinho
    if not (d ?| c_7d_chaves) then
    -- FASE 7d: fim
    if not (d ?| array['dias', 'equipe', 'dono', 'precisa_ate', 'bem', 'nao_antes_de', 'escopo_em_aberto', 'escopo_decidido',
                       'congelada_ate', 'prioridade', 'sem_material', 'adiantavel_patio', 'servico_cliente']) then
      return jsonb_build_object('antes', jsonb_build_object('prometido', v_prom_antes), 'depois', jsonb_build_object('prometido', v_prom));
    end if;
    -- FASE 7d: (7d P7) fecha o "com o local ou o bem na mesma linha"
    end if;
    -- FASE 7d: fim
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
  -- FASE 7e: (7e P3, AG7-33, R7.3-2, conflito 2d) a saída do dono: ele viu "Você disse 3 dias; contei 3,5" e repetiu 3 — ou disse o 3,5 que eu contei —: vale o número dele nesta OS, sem correção, e isso sobrevive ao soltar da marcação. Não é pergunta nem recusa: repetir é a resposta (R7.12-1). Vale só com correção em uso de fato (dias_dono na saída, a mesma conta que ele viu), e não acima do máximo, onde já não há correção a recusar.
  if d ? 'dias' then
    v_new.aprovado_com_vies := null;  -- o dono disse (ou aceitou) outra vez: o número aprovado com o viés deixa de valer
  end if;
  if d ? 'dias' and coalesce(d ->> 'estimativa_fonte', '') = 'dono' then
    v_7e_m := public.agenda_meios_da_os(p_os, p_hoje);
    if v_7e_m ? 'dias_dono' and not v_7e_m ? 'vies_acima_max' and v_new.dias in (v_old.dias, (v_7e_m ->> 'dias')::numeric) then
      v_new.vies_dono_fixo := true;
      v_new.vies_marcado := 1;
      v_new.vies_marcado_chave := null;
      v_new.marcado_em := coalesce(v_old.marcado_em, p_hoje);
      v_7e_fixar := true;
    end if;
  end if;
  -- FASE 7e: fim
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

  -- FASE 7d: (7d P7; §5.7) o que o dono disse do local e do bem, fonte dono. Vai para a linha aqui, antes de ler o local resolvido dos autorizados; o histórico abaixo guarda o antes
  -- e o depois (o update de antes não tem estas colunas). A chegada e a saída têm uma fonte só: entrada_coerente.
  if v_7d_tem then
    -- (correção O2, O3) o lugar novo e a casa do cliente viram linha de agenda_locais aqui, no *grava*, e daqui em diante são um local como os outros
    if coalesce((d ->> 'local_casa')::boolean, false) or nullif(d ->> 'local_novo', '') is not null then
      v_7d_lin := case when coalesce((d ->> 'local_casa')::boolean, false) then public._agenda_local_da_casa(p_os, p_autor)
                       else public._agenda_local_criar(d ->> 'local_novo', d ->> 'local_municipio', d ->> 'local_uf', p_autor) end;
      d := (d - 'local_novo') || jsonb_build_object('local_id', v_7d_lin ->> 'id', 'local_nome', v_7d_lin ->> 'nome');
      -- (correção G6) a casa sem cidade leva a que o dono disse ("na casa dele em Porto Belo"); o cadastro do cliente não muda
      -- (correção A1) só na linha da casa: o rascunho junta as frases, e "em Penha" depois da casa não pode levar a cidade dela
      if coalesce((d ->> 'local_casa')::boolean, false) and coalesce((d ->> 'local_casa_dita')::boolean, false) then
        update public.agenda_locais x set municipio = d ->> 'local_casa_em', uf = d ->> 'local_casa_uf', atualizado_por = p_autor
         where x.id = (v_7d_lin ->> 'id')::uuid;
      end if;
    end if;
    if d ? 'local_id' then
      -- (correção M8) a linha que saiu de uso entre a releitura e o *grava* volta, sob a trava de _agenda_local_criar: sem isso diz "Gravado" e aponta para uma linha inativa. A linha ativa não toma trava nova
      if exists (select 1 from public.agenda_locais x where x.id = (d ->> 'local_id')::uuid and not x.ativo and x.tipo in ('outro', 'casa_cliente')) then
        perform pg_advisory_xact_lock(hashtext('agenda_local_criar'));
        update public.agenda_locais x set ativo = true, atualizado_por = p_autor
         where x.id = (d ->> 'local_id')::uuid and not x.ativo and x.tipo in ('outro', 'casa_cliente');
      end if;
      v_new.local_id := (d ->> 'local_id')::uuid;
      v_new.local_fonte := case when d ->> 'local_id' is not null then 'dono' end;
      v_new.local_em := case when d ->> 'local_id' is not null then v_7d_agora end;
    end if;
    if d ? 'bem_situacao' then
      v_new.bem_situacao := d ->> 'bem_situacao';
      v_new.bem_situacao_fonte := 'dono';
      v_new.bem_situacao_em := v_7d_agora;
    end if;
    if d ? 'bem_exige' then v_new.bem_exige := d ->> 'bem_exige'; end if;
    if d ? 'descer_quem' then v_new.descer_quem := d ->> 'descer_quem'; end if;
    if d ? 'viagem' then v_new.viagem := d ->> 'viagem'; end if;
    if d ?| array['entrada_em', 'retirada_em'] then
      if d ? 'entrada_em' then v_new.entrada_em := (d ->> 'entrada_em')::date; end if;
      if d ? 'retirada_em' then v_new.retirada_em := (d ->> 'retirada_em')::date; end if;
      v_new.entrada_fonte := case when coalesce(v_new.entrada_em, v_new.retirada_em) is not null then 'dono' end;
      -- o que mudou entre a releitura e o *grava*: a frase dele, não "o banco recusou"
      if v_new.entrada_em >= v_new.retirada_em then
        raise exception 'a saída (%) tem de ser depois da chegada (%)', public._dia_curto(v_new.retirada_em), public._dia_curto(v_new.entrada_em) using errcode = 'P0001';
      end if;
    end if;
    update public.os_planejamento
       set local_id = v_new.local_id, local_fonte = v_new.local_fonte, local_em = v_new.local_em,
           bem_situacao = v_new.bem_situacao, bem_situacao_fonte = v_new.bem_situacao_fonte, bem_situacao_em = v_new.bem_situacao_em,
           bem_exige = v_new.bem_exige, descer_quem = v_new.descer_quem, viagem = v_new.viagem,
           entrada_em = v_new.entrada_em, retirada_em = v_new.retirada_em, entrada_fonte = v_new.entrada_fonte
     where service_order_id = p_os;
    -- (correção G6) corrigir limpa: a linha que saiu da OS, sem conferir e sem outro uso, fica inativa, pela regra do *desfaz*; o *desfaz* desta correção a reativa
    if v_old.local_id is not null and v_old.local_id is distinct from v_new.local_id and public._agenda_local_recolher(v_old.local_id, p_autor) then
      v_7d_recolhido := v_old.local_id;
    end if;
    -- A lista dita substitui a anterior, como a equipe: a linha nunca se apaga (quem saiu ganha revogado_em). O antes vai inteiro para a ação: o *desfaz* volta linha por linha.
    if d ? 'autorizados' then
      select coalesce(jsonb_agg(to_jsonb(x) order by x.payee_id), '[]'::jsonb) into v_7d_linhas
        from public.os_autorizados x where x.service_order_id = p_os;
      v_7d_vig_a := array(select x.payee_id from public.os_autorizados x where x.service_order_id = p_os and x.revogado_em is null order by 1);
      v_7d_ids := array(select distinct (e ->> 'payee_id')::uuid from jsonb_array_elements(d -> 'autorizados') e order by 1);
      update public.os_autorizados x set revogado_em = v_7d_agora
       where x.service_order_id = p_os and x.revogado_em is null and not (x.payee_id = any (v_7d_ids));
      if cardinality(v_7d_ids) > 0 then
        -- (correção O6) com o local suposto, a lista fica sem local (nulo = desta OS): ela sobrevive ao dono dizer o local depois
        select case when coalesce((x.r ->> 'suposicao')::boolean, false) then null else (x.r ->> 'local_id')::uuid end into v_7d_local
          from (select public._agenda_local_resolvido(p_os, p_hoje) as r) x;
        insert into public.os_autorizados (service_order_id, payee_id, local_id, valido_ate, fonte, trecho, criado_em, criado_por)
        select p_os, u.id, v_7d_local, null, 'dono', left(p_trecho, 300), v_7d_agora, p_autor from unnest(v_7d_ids) u(id)
        on conflict (service_order_id, payee_id) do update
          set local_id = excluded.local_id, valido_ate = null, fonte = excluded.fonte, trecho = excluded.trecho, revogado_em = null,
              criado_em = excluded.criado_em, criado_por = excluded.criado_por
          -- dizer de novo o que já está não mexe na linha
          where (os_autorizados.local_id, os_autorizados.valido_ate, os_autorizados.fonte, os_autorizados.revogado_em)
                is distinct from (excluded.local_id, null::date, excluded.fonte, null::timestamptz);
      end if;
      v_7d_vig_d := v_7d_ids;
      select coalesce(jsonb_agg(to_jsonb(x) order by x.payee_id), '[]'::jsonb) into v_7d_lin_d
        from public.os_autorizados x where x.service_order_id = p_os;
      -- a mesma lista pode ter mudado por dentro (o local, a validade, a fonte): a comparação é das linhas, não dos nomes
      if v_7d_linhas is distinct from v_7d_lin_d then
        v_antes := v_antes || jsonb_build_object('autorizados', to_jsonb(v_7d_vig_a));
        v_depois := v_depois || jsonb_build_object('autorizados', to_jsonb(v_7d_vig_d));
      end if;
    end if;
  end if;
  -- FASE 7d: fim
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
  -- FASE 7e: (7e P3, AG7-33) a saída do dono vai para a linha (o update acima é o de antes, sem estas colunas). O que a marcação congelaria e ainda não congelou fica congelado aqui: com marcado_em posto, a marcação não volta a esta OS (§3.1-10).
  if v_7e_fixar then
    update public.os_planejamento x
       set vies_dono_fixo = true, vies_marcado = 1, vies_marcado_chave = null, marcado_em = v_new.marcado_em,
           tempo_compra_marcado = coalesce(x.tempo_compra_marcado, public._agenda_tempo_interno_compra(p_os)), folga_compra_marcada = coalesce(x.folga_compra_marcada, 0)
     where x.service_order_id = p_os;
  end if;
  if d ? 'dias' and v_old.aprovado_com_vies is not null then
    update public.os_planejamento x set aprovado_com_vies = null where x.service_order_id = p_os;
  end if;
  -- FASE 7e: fim
  -- FASE 7d: (correção O21) "já está livre" (o bem sem indisponibilidade, modo livre) fecha a bem_livre mesmo sem campo do local na linha
  if d #>> '{bem,modo}' = 'livre' then
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'você disse que o bem está livre'
     where chave = 'bem_livre:' || p_os and estado = 'aberta';
  end if;
  -- FASE 7d: fim
  -- FASE 7d: (7d P7) o dono vence e o *desfaz* volta tudo.
  -- (a) A pergunta local aberta da OS: o sim dela gravaria depois, por cima do que o dono disse, o que o cliente falou. Fecha quando ele disse o que ela gravaria (a sem leitura, que
  -- pede "me diga onde é", com o local, o bem ou a chegada). "Tirei o local" não diz onde é: ela fica.
  -- (b) A combinar e a acesso: o sim é a palavra do próprio dono, com a data escrita, mas o que ele disse pode já ter resolvido; o tique levaria até 15 minutos. O mesmo resolvedor, agora.
  -- (c) A ação local: só o que mudou de fato, mais a pergunta que fechou. Sem as chaves novas, nada disto roda: os_planejar_pela_tela e as linhas de antes não têm ação.
  if v_7d_tem then
    select q.* into v_7d_q from public.agenda_perguntas q where q.chave = 'local:' || p_os and q.estado = 'aberta' limit 1;
    if found then
      v_7d_item := v_7d_q.opcoes -> 0 #> '{efeito,item}';
      if d ->> 'local_id' is not null or coalesce((d ->> 'local_casa')::boolean, false)
         or (d ? 'bem_situacao' and (v_7d_item is null or v_7d_item ->> 'situacao' is not null))
         or (d ? 'descer_quem' and v_7d_item ->> 'descer_quem' is not null)
         or (d ->> 'entrada_em' is not null and v_7d_item is null) then
        update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'você disse onde é' where id = v_7d_q.id;
        v_7d_fech := v_7d_fech || v_7d_q.id;
      end if;
    end if;
    -- (correção O21) a bem_livre fecha quando o dono diz onde o bem está: no pátio, ou num lugar em que ele não está com o cliente. O *desfaz* a devolve, como as outras
    v_7d_q := null;
    select q.* into v_7d_q from public.agenda_perguntas q where q.chave = 'bem_livre:' || p_os and q.estado = 'aberta' limit 1;
    if v_7d_q.id is not null
       and (d ->> 'bem_situacao' in ('patio', 'agua', 'seco', 'garagem_seca')
            or exists (select 1 from public.agenda_locais x where x.id = (d ->> 'local_id')::uuid and x.tipo like 'patio\_%')) then
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'você disse onde o bem está' where id = v_7d_q.id;
      v_7d_fech := v_7d_fech || v_7d_q.id;
    end if;
    v_7d_abert := array(select q.id from public.agenda_perguntas q where q.service_order_id = p_os and q.tipo in ('combinar', 'acesso') and q.estado = 'aberta');
    if cardinality(v_7d_abert) > 0 then
      perform public._agenda_local_resolver(p_hoje, v_7d_agora);
      v_7d_fech := v_7d_fech || array(select q.id from public.agenda_perguntas q where q.id = any (v_7d_abert) and q.estado <> 'aberta');
    end if;

    if (v_old.local_id, v_old.local_fonte) is distinct from (v_new.local_id, v_new.local_fonte) then
      v_7d_antes := v_7d_antes || jsonb_build_object('local_id', v_old.local_id, 'local_fonte', v_old.local_fonte, 'local_em', v_old.local_em);
      v_7d_dep := v_7d_dep || jsonb_build_object('local_id', v_new.local_id, 'local_fonte', v_new.local_fonte, 'local_em', v_new.local_em)
                  || case when v_7d_recolhido is not null then jsonb_build_object('local_recolhido', v_7d_recolhido) else '{}'::jsonb end;
    end if;
    if (v_old.bem_situacao, v_old.bem_situacao_fonte) is distinct from (v_new.bem_situacao, v_new.bem_situacao_fonte) then
      v_7d_antes := v_7d_antes || jsonb_build_object('bem_situacao', v_old.bem_situacao, 'bem_situacao_fonte', v_old.bem_situacao_fonte, 'bem_situacao_em', v_old.bem_situacao_em);
      v_7d_dep := v_7d_dep || jsonb_build_object('bem_situacao', v_new.bem_situacao, 'bem_situacao_fonte', v_new.bem_situacao_fonte, 'bem_situacao_em', v_new.bem_situacao_em);
    end if;
    if v_old.bem_exige is distinct from v_new.bem_exige then
      v_7d_antes := v_7d_antes || jsonb_build_object('bem_exige', v_old.bem_exige);
      v_7d_dep := v_7d_dep || jsonb_build_object('bem_exige', v_new.bem_exige);
    end if;
    if v_old.descer_quem is distinct from v_new.descer_quem then
      v_7d_antes := v_7d_antes || jsonb_build_object('descer_quem', v_old.descer_quem);
      v_7d_dep := v_7d_dep || jsonb_build_object('descer_quem', v_new.descer_quem);
    end if;
    if v_old.viagem is distinct from v_new.viagem then
      v_7d_antes := v_7d_antes || jsonb_build_object('viagem', v_old.viagem);
      v_7d_dep := v_7d_dep || jsonb_build_object('viagem', v_new.viagem);
    end if;
    if (v_old.entrada_em, v_old.retirada_em, v_old.entrada_fonte) is distinct from (v_new.entrada_em, v_new.retirada_em, v_new.entrada_fonte) then
      v_7d_antes := v_7d_antes || jsonb_build_object('entrada_em', v_old.entrada_em, 'retirada_em', v_old.retirada_em, 'entrada_fonte', v_old.entrada_fonte);
      v_7d_dep := v_7d_dep || jsonb_build_object('entrada_em', v_new.entrada_em, 'retirada_em', v_new.retirada_em, 'entrada_fonte', v_new.entrada_fonte);
    end if;
    if v_7d_linhas is distinct from v_7d_lin_d then
      v_7d_antes := v_7d_antes || jsonb_build_object('autorizados_linhas', v_7d_linhas);
      v_7d_dep := v_7d_dep || jsonb_build_object('autorizados', to_jsonb(v_7d_ids), 'autorizados_vigentes', to_jsonb(v_7d_vig_d));
    end if;
    if v_7d_antes <> '{}'::jsonb or cardinality(v_7d_fech) > 0 then
      select x.trecho into v_7d_trecho from public.os_planejamento x where x.service_order_id = p_os;
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, critica, antes, depois, texto, motivo, autor, desfazivel_ate)
      values (clock_timestamp(), p_hoje, true, 'dono', 'local', p_os, array[p_os], false, v_7d_antes || jsonb_build_object('trecho', v_old.trecho),
              v_7d_dep || jsonb_build_object('trecho', v_7d_trecho, 'efeito', 'planejar', 'perguntas_fechadas', to_jsonb(v_7d_fech),
                                             'item', jsonb_build_object('cliente', d ->> 'curto')),
              public._agenda_corta(concat_ws(': ', d ->> 'curto', array_to_string(public._agenda_planejar_linhas(d), ' ')), 400), 'você disse', p_autor,
              v_7d_agora + (public._agenda_cfg()).desfazer_validade);
    end if;
  end if;
  -- FASE 7d: fim
  return jsonb_build_object('antes', v_antes, 'depois', v_depois);
end;
$function$;

comment on function public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): grava em os_planejamento (e os_planejamento_equipe) uma linha de rascunho planejar — só os campos ditos (Fase 2: adiantavel_patio → adiantavel_patio_dias); a equipe dita substitui a anterior. Histórico {em, autor, trecho, antes, depois} com só o que mudou (os 20 mais novos). Só pelo agenda_rascunho_gravar; só service_role. Fase 5 (P5): prometido → os_planejamento.prometido_* pelo _agenda_cliente_gravar_prometido (fonte dono; o original só na 1ª vez; linha própria no histórico); servico_cliente → os_planejamento.servico_cliente. Fase 7b (P2): a dupla dita → os_planejamento.dupla_dita (nao | todos | inicio | fim), dupla_meios (só inicio/fim), dupla_motivo ("você disse: vai em dupla nos 2 primeiros meios-dias") e dupla_em (a hora do *grava*), no histórico com o antes e o depois; com o prometido na mesma linha, o resto da linha ainda grava. Fase 7d (P7; §5.7): o que o dono disse do local e do bem → local_id, local_fonte = dono e local_em; bem_situacao e a fonte; bem_exige; descer_quem; entrada_em, retirada_em e entrada_fonte = dono; viagem; e os_autorizados (fonte dono, local_id = o local resolvido, valido_ate nulo; a lista dita substitui a anterior; quem saiu ganha revogado_em). Tudo no histórico. A pergunta local aberta fecha (resolvida, "você disse onde é") quando ele disse o que ela gravaria: o dono vence. A combinar e a acesso da OS passam pelo _agenda_local_resolver na hora. Uma ação local (origem dono, efeito planejar), com o que mudou e as perguntas que fechou: o *desfaz* (_agenda_desfazer_local) volta só isso; dias, equipe e os outros campos da mesma linha não têm *desfaz*, como sempre. Sem essas chaves, a de antes, byte a byte, e nenhuma ação. FASE 7e (P3): a saída do dono (AG7-33, R7.3-2): repetir os dias dele (ou dizer o número corrigido que eu mostrei) numa OS com correção que muda o número grava vies_dono_fixo, vies_marcado 1,00, marcado_em e o que a marcação congelaria. Dizer os dias de novo apaga o aprovado_com_vies.';

-- _agenda_aprender_congelar (de 20261111100100_agenda_fase7e_medicao.sql:549; md5 do corpo de antes 1b5eb8c0b65b6d5ec4944286378e7ada)
create or replace function public._agenda_aprender_congelar(p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c   public.agenda_config := public._agenda_cfg();
  r   record;
  v   jsonb;
  n_c int := 0;
  n_s int := 0;
  -- FASE 7: (7a P6) a fonte orcamento só com o gestor ligado de verdade (a regra estimativa e o modo marcar ligado, fora da
  -- simulação da sombra)
  v_gestor boolean := public._agenda_gestor_regra('estimativa') and public._agenda_gestor_modo('marcar') = 'ligado';
  -- FASE 7: fim
  -- FASE 7e: (7e P2, §5.1, R7.4) o 2º laço: a estimativa do início
  r7       record;
  v_7e_sug jsonb;
  v_7e_m   jsonb;
  v_7e_ini date;
  v_7e_fim date;
  v_7e_dp  numeric;
  v_7e_pm  numeric;
  v_7e_pes int;
  v_7e_conta boolean;
  v_7e_gestor text;
  n_7e     int := 0;
  -- FASE 7e: fim
  -- FASE 7e: (7e P3) o valor anterior de agenda.sem_vies
  v_7e_sv text;
  -- FASE 7e: fim
begin
  if p_hoje is null then
    raise exception 'Falta o dia (p_hoje).' using errcode = '22023';
  end if;
  for r in
    select so.id as os, pl.service_order_id as tem_plano, pl.dias_no_inicio
      from public.service_orders so
      left join public.os_planejamento pl on pl.service_order_id = so.id
     where so.check_in_at is not null and so.merged_into_id is null
       and (so.check_in_at at time zone 'America/Sao_Paulo')::date between p_hoje - c.aprender_janela_dias and p_hoje
       and pl.dias_no_inicio is null
     order by so.check_in_at, so.id
  loop
    v := case when r.tem_plano is not null then public._agenda_dias_no_inicio(r.os) end;
    -- FASE 7: (7a P6) a fonte orcamento — a estimativa que o gestor usou (o 4º passo de _agenda_dias_no_inicio, também na OS sem
    -- linha de planejamento) ou os dias que ele gravou quando a pergunta com prazo venceu — congela uma vez, com as
    -- diárias-pessoa estimadas (dp_no_inicio; nulas nos dias gravados). A linha de planejamento nasce se faltar (os dias de
    -- agora continuam nulos: só os do início). Só com o gestor ligado de verdade; sem ele, a fonte orcamento não congela, como
    -- antes.
    if v_gestor then
      if r.tem_plano is null then
        v := public._agenda_dias_no_inicio(r.os);
      end if;
      if v ->> 'fonte' = 'orcamento' then
        insert into public.os_planejamento as x (service_order_id, dias_no_inicio, dias_no_inicio_fonte, dias_no_inicio_em,
                                                 dp_no_inicio)
        values (r.os, (v ->> 'dias')::numeric, 'orcamento', (v ->> 'em')::date, (v ->> 'dp')::numeric)
        on conflict (service_order_id) do update
          set dias_no_inicio = excluded.dias_no_inicio, dias_no_inicio_fonte = excluded.dias_no_inicio_fonte,
              dias_no_inicio_em = excluded.dias_no_inicio_em, dp_no_inicio = excluded.dp_no_inicio
          where x.dias_no_inicio is null;
        n_c := n_c + 1;
        continue;
      end if;
    end if;
    -- FASE 7: fim
    if v is null or coalesce(v ->> 'fonte', '') not in ('dono', 'aceita') then
      n_s := n_s + 1;
      continue;
    end if;
    update public.os_planejamento
       set dias_no_inicio = (v ->> 'dias')::numeric, dias_no_inicio_fonte = v ->> 'fonte',
           dias_no_inicio_em = (v ->> 'em')::date
     where service_order_id = r.os and dias_no_inicio is null;
    n_c := n_c + 1;
  end loop;
  -- FASE 7e: (7e P2, §5.1, R7.4, R7.5-9, R7.5-22) o 2º laço: toda OS que começou (check-in OU o 1º dia de alocação vigente não reserva, o menor dos dois) congela, uma vez, a estimativa do início. O 1º laço, acima, não muda. Sem base ou no
  -- diagnóstico, dp_bruto fica nulo e a data grava mesmo assim (uma vez só: a OS sai daqui). O erro de uma OS não derruba as outras nem o que o 1º laço gravou. atualizado_em nunca é tocado: a marca d'água do encaixe do gestor o lê.
  for r7 in
    select x.os, x.dia, x.criada
      from (select so.id as os, so.created_at as criada,
                   -- least ignora o nulo, e aqui é o certo: sem check-in, vale o 1º dia; sem alocação, vale o check-in
                   least((so.check_in_at at time zone 'America/Sao_Paulo')::date,
                         (select min(a.dia) from public.agenda_alocacoes a
                           where a.service_order_id = so.id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva')) as dia
              from public.service_orders so
              left join public.os_planejamento pl on pl.service_order_id = so.id
             where so.merged_into_id is null and pl.estimativa_no_inicio_em is null) x
     where x.dia between p_hoje - c.aprender_janela_dias and p_hoje
     order by x.dia, x.os
  loop
    begin
      -- A estimativa do gestor é a de sem o freio: com ele, _agenda_gestor_regra é falsa para tudo e o número que congela uma vez entraria torto no viés (MO com deslocamento, outras pessoas, outro molde). As 2 chamadas, e só elas, sob a simulação que já existe (o portão lê agenda.gestor); o valor de antes volta logo depois e, num erro, volta pelo rollback do bloco.
      v_7e_gestor := coalesce(current_setting('agenda.gestor', true), '');
      perform set_config('agenda.gestor', 'sombra', true);
      -- (7e P3) o viés fora da conta: "o viés mede o estimador, não o plano" (§3.1-4). agenda_meios_da_os lê o viés (o de agora, com o freio solto, e o congelado, mesmo com o freio) e o molde corrigido entraria em pm_plano_no_inicio: razao_dono e o próprio viés mediriam a si mesmos (AG7-33). agenda.gestor não cobre: _agenda_margem_modo lê o freio direto. Variável própria, no molde de agenda.gestor; os_duracao_sugerida não precisa dela (os números de sempre não mudam com o viés).
      v_7e_sv := coalesce(current_setting('agenda.sem_vies', true), '');
      perform set_config('agenda.sem_vies', 'on', true);
      -- (7e: fim)
      v_7e_sug := public.os_duracao_sugerida(r7.os);
      v_7e_m := public.agenda_meios_da_os(r7.os, r7.dia);
      perform set_config('agenda.gestor', v_7e_gestor, true);
      -- (7e P3) volta ao valor de antes (num erro, pelo rollback do bloco desta OS)
      perform set_config('agenda.sem_vies', v_7e_sv, true);
      -- (7e: fim)
      v_7e_dp := public._agenda_margem_dp_bruto(r7.os, v_7e_sug);
      v_7e_conta := public._agenda_margem_dono_e_pessoa(r7.os);
      -- os pessoa-meios do molde: o dono com o turno conta quando está sozinho no meio-dia, ou é uma das pessoas (R7.4)
      select nullif(coalesce(sum((e ->> 'desejado')::int + case when e -> 'dono' ? 'turno' and ((e ->> 'desejado')::int = 0 or v_7e_conta) then 1 else 0 end), 0), 0)
        into v_7e_pm
        from jsonb_array_elements(coalesce(v_7e_m -> 'molde', '[]'::jsonb)) e;
      v_7e_pes := case when coalesce((v_7e_m ->> 'equipe_dita')::boolean, false)
                       then (select max((e ->> 'desejado')::int + case when e -> 'dono' ? 'turno' then 1 else 0 end)
                               from jsonb_array_elements(coalesce(v_7e_m -> 'molde', '[]'::jsonb)) e)
                       else (v_7e_m ->> 'pessoas_sugeridas')::int end;
      v_7e_pes := case when v_7e_pes between 1 and 6 then v_7e_pes end;
      select min(a.dia), max(a.dia) into v_7e_ini, v_7e_fim
        from public.agenda_alocacoes a
       where a.service_order_id = r7.os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva';
      insert into public.os_planejamento as x (service_order_id, estimativa_no_inicio_em, dp_bruto_no_inicio, pessoas_no_inicio,
                                               pm_plano_no_inicio, inicio_plano_no_inicio, prazo_plano_no_inicio, atualizado_em)
      values (r7.os, r7.dia, v_7e_dp, v_7e_pes, v_7e_pm, v_7e_ini,
              case when v_7e_ini is not null then public.agenda_du_entre(v_7e_ini, v_7e_fim) + 1 end, r7.criada)
      on conflict (service_order_id) do update
        set estimativa_no_inicio_em = excluded.estimativa_no_inicio_em, dp_bruto_no_inicio = excluded.dp_bruto_no_inicio,
            pessoas_no_inicio = excluded.pessoas_no_inicio, pm_plano_no_inicio = excluded.pm_plano_no_inicio,
            inicio_plano_no_inicio = excluded.inicio_plano_no_inicio, prazo_plano_no_inicio = excluded.prazo_plano_no_inicio
        where x.estimativa_no_inicio_em is null;
      n_7e := n_7e + 1;
    exception when others then
      perform public.log_app_error('db', format('aprendizado, congelar a estimativa %s: %s', r7.os, sqlerrm), 'agenda', 'aprender:congelar', 'error',
                                   jsonb_build_object('os', r7.os, 'sqlstate', sqlstate, 'p_hoje', p_hoje));
    end;
  end loop;
  return jsonb_build_object('congeladas', n_c, 'sem_dias', n_s, 'estimativas_congeladas', n_7e);
  -- FASE 7e: fim
  return jsonb_build_object('congeladas', n_c, 'sem_dias', n_s);
end;
$function$;

comment on function public._agenda_aprender_congelar(date) is
  'Agenda de Produção (Fase 6): a rodada do aprendizado congela, uma vez, os dias ditos no início — toda OS com check-in até p_hoje (na janela aprender_janela_dias) e sem os_planejamento.dias_no_inicio recebe o de _agenda_dias_no_inicio (só fonte dono ou aceita; a sugestão do banco nunca). {congeladas, sem_dias}. Definer, sem grant a ninguém. FASE 7 (7a P6): com o gestor ligado de verdade (a regra estimativa e o modo marcar ligado, fora da simulação da sombra), congela também a fonte orcamento — a estimativa que o gestor usou no dia do check-in (o 4º passo de _agenda_dias_no_inicio, também na OS sem linha de planejamento) e os dias que ele gravou pelo prazo —, uma vez, com dp_no_inicio (as diárias-pessoa estimadas; nulas nos dias gravados); a linha de os_planejamento nasce se faltar (os dias de agora continuam nulos). Conta em congeladas. Sem o portão, a fonte orcamento não congela (sem_dias), como antes. FASE 7e (P2): o 2º laço congela, uma vez, a estimativa do início (estimativa_no_inicio_em = o menor de check-in e 1º dia de alocação vigente não reserva; dp_bruto_no_inicio, pessoas_no_inicio, pm_plano_no_inicio, inicio_plano_no_inicio, prazo_plano_no_inicio). Sem base ou no diagnóstico, dp_bruto fica nulo. A linha nasce se faltar e atualizado_em não muda. O erro de uma OS vai a app_error_logs. O retorno ganha estimativas_congeladas. A estimativa e o molde saem sob agenda.gestor = sombra (o resultado de sem o freio) e o valor anterior da variável volta logo depois; o 1º laço e v_gestor não mudam. FASE 7e (P3): o molde é lido também sem o viés (agenda.sem_vies), para a medida não medir a si mesma.';

-- _agenda_aprender_congelar_marcacao (de 20261111100100_agenda_fase7e_medicao.sql:217; md5 do corpo de antes 2d940a4694bf412f65ea40eb5d0d4166)
create or replace function public._agenda_aprender_congelar_marcacao(p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  r       record;
  v       jsonb;
  v_dia   date;
  v_vies  numeric;
  n_c     int := 0;
  n_s     int := 0;
begin
  if p_hoje is null then
    raise exception 'Falta o dia (p_hoje).' using errcode = '22023';
  end if;
  -- 1. A OS que tem compromisso (ou meio-dia feito) e ainda não tem o congelado: o valor que valeu desde a rodada anterior. Sem o que aprender, 1,00, o tempo interno de hoje e 0 (R7.5-16: a folga da compra não tem leitor nesta etapa).
  for r in
    select so.id as os, so.created_at as criada,
           (select min(a.publicada_em) from public.agenda_alocacoes a
             where a.service_order_id = so.id and a.tipo <> 'reserva' and a.publicada_em is not null) as prim
      from public.service_orders so
      left join public.os_planejamento pl on pl.service_order_id = so.id
     where so.merged_into_id is null and pl.marcado_em is null
       and exists (select 1 from public.agenda_alocacoes a
                    where a.service_order_id = so.id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                      and (a.dia >= p_hoje or a.resultado in ('cumprido', 'parcial')))
     order by so.id
  loop
    continue when r.prim is null;
    v_dia := (r.prim at time zone 'America/Sao_Paulo')::date;
    v := public._agenda_vies_da_os(r.os);
    -- FASE 7e: (7e P3, AG7-33, §3.1-10) os dias que o dono disse (fonte dono/aceita) congelam a correção pela chave dono:, não a do estimador: o publicado não muda pelo aprendizado também nos dias dele, e agenda_meios_da_os só usa o congelado da conta dele.
    if exists (select 1 from public.os_planejamento x where x.service_order_id = r.os and x.dias is not null and x.estimativa_fonte in ('dono', 'aceita') and x.aprovado_com_vies is null) then
      v := public._agenda_vies_dono_da_os(r.os);
    end if;
    -- FASE 7e: fim
    v_vies := coalesce((v ->> 'vies_em_uso')::numeric, 1);
    insert into public.os_planejamento as x (service_order_id, marcado_em, vies_marcado, vies_marcado_chave, tempo_compra_marcado,
                                             folga_compra_marcada, atualizado_em)
    values (r.os, v_dia, v_vies, v ->> 'chave', public._agenda_tempo_interno_compra(r.os), 0, r.criada)
    on conflict (service_order_id) do update
      set marcado_em = excluded.marcado_em, vies_marcado = excluded.vies_marcado, vies_marcado_chave = excluded.vies_marcado_chave,
          tempo_compra_marcado = excluded.tempo_compra_marcado, folga_compra_marcada = excluded.folga_compra_marcada
      where x.marcado_em is null;
    n_c := n_c + 1;
  end loop;

  -- 2. A OS que voltou à fila (nenhum compromisso vigente nem meio-dia feito): solta o congelado. A saída do dono (vies_dono_fixo) fica: sem isso se apagaria sozinha (R7.3-2).
  with x as (
    update public.os_planejamento p
       set marcado_em = null, vies_marcado = null, vies_marcado_chave = null, tempo_compra_marcado = null, folga_compra_marcada = null
     where p.marcado_em is not null and not p.vies_dono_fixo
       -- nenhuma alocação vigente não reserva: resultado só existe em vigente (CHECK resultado_so_vigente), então "nem meio-dia feito" já está aqui
       and not exists (select 1 from public.agenda_alocacoes a
                        where a.service_order_id = p.service_order_id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva')
    returning 1)
  select count(*)::int into n_s from x;
  return jsonb_build_object('congeladas', n_c, 'soltas', n_s);
end;
$function$;

comment on function public._agenda_aprender_congelar_marcacao(date) is
  'Agenda de Produção (Fase 7e, P2; §5.1, R7.3-2, R7.5-22): congela, uma vez, o que valeu quando a OS ganhou o 1º compromisso — marcado_em (o dia da 1ª publicada_em não reserva), vies_marcado e chave, tempo_compra_marcado e folga_compra_marcada (0) —, e solta o congelado da OS que voltou à fila, salvo vies_dono_fixo. A linha de os_planejamento nasce se faltar e atualizado_em não muda. {congeladas, soltas}. Definer, sem grant a ninguém. FASE 7e (P3): a OS com dias do dono congela a correção pela chave dono: (_agenda_vies_dono_da_os), para o publicado não mudar pelo aprendizado também nos dias dele.';

-- agenda_aplicar (de 20261031100750_agenda_fase7a_revisao.sql:1179; md5 do corpo de antes eb892b79d7f5683f9846f689c3b1b2c3)
create or replace function public.agenda_aplicar(p_proposta uuid, p_os uuid[] default null, p_via text default 'motor',
                                                 p_autor uuid default null, p_pergunta uuid default null,
                                                 p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config;
  v_p      public.agenda_propostas%rowtype;
  v_cong   date;
  v_sel    jsonb;
  v_viol   jsonb;
  v_nova   jsonb;
  v_via_p  text;
  v_origem text;
  v_va     bigint;
  v_vd     bigint;
  v_os     uuid;
  v_i      jsonb;
  v_a      jsonb;
  v_criadas uuid[];
  v_canc   uuid[];
  v_estado text;
  v_fix    text;
  v_acoes  uuid[] := '{}';
  v_acao   uuid;
  v_tipo   text;
  v_txt    text;
  v_linhas text[] := '{}';
  v_status text;
  v_porta  jsonb;
  v_desf   timestamptz;
  v_n_pub  int := 0;
  v_n_can  int := 0;
  v_motivo text;
  v_atraso int;
  v_tem    boolean;
  v_desfaz boolean := false;
  v_nomes  text[] := '{}';
  v_q      record;
  v_texto  text;
  -- FASE 7e: (7e P3) a sugestão aprovada com o viés
  v_7e_m     jsonb;
  -- FASE 7e: fim
  -- CORREÇÃO FASE 6: (C1) item 3: a presença aprendida de cada OS publicada pela 1ª vez
  v_pa     jsonb;
  -- CORREÇÃO FASE 6: fim
begin
  if p_via is null or p_via not in ('motor', 'vigia', 'conferencia', 'dono', 'tela', 'aprovacao') then
    raise exception 'Caminho desconhecido para aplicar: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  select * into v_p from public.agenda_propostas where id = p_proposta for update;
  if not found then
    raise exception 'Não encontrei esse plano.' using errcode = 'P0002';
  end if;
  if cf.modo_proposta <> 'ligado' or v_p.modo <> 'ligado' then
    return jsonb_build_object('ok', false, 'texto', 'A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada.');
  end if;
  if v_p.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', case v_p.estado
      when 'aplicada' then 'Esse plano já foi publicado.' when 'expirada' then 'Esse plano venceu. Peça de novo que eu monto outro.'
      when 'obsoleta' then 'Esse plano foi trocado por outro.' else 'Esse plano foi descartado.' end);
  end if;
  if p_agora > v_p.expira_em then
    update public.agenda_propostas set estado = 'expirada', motivo_fim = 'passou da validade' where id = p_proposta;
    delete from public.agenda_alocacoes where proposta_id = p_proposta and estado = 'proposta';
    return jsonb_build_object('ok', false, 'texto', 'Esse plano venceu. Peça de novo que eu monto outro.');
  end if;
  if v_p.versao_base <> cf.versao_plano then
    update public.agenda_propostas set estado = 'obsoleta', motivo_fim = 'a agenda mudou' where id = p_proposta;
    delete from public.agenda_alocacoes where proposta_id = p_proposta and estado = 'proposta';
    -- o motor refaz com os mesmos parâmetros e aplica a nova (uma vez só por chamada)
    if p_via = 'motor' and coalesce(current_setting('agenda.reaplicando', true), '') <> 'on' then
      v_nova := public.agenda_propor(v_p.escopo, (v_p.parametros ->> 'p_de')::date, (v_p.parametros ->> 'p_ate')::date,
                  case when v_p.parametros -> 'p_os' is null or jsonb_typeof(v_p.parametros -> 'p_os') <> 'array' then null
                       else array(select x::uuid from jsonb_array_elements_text(v_p.parametros -> 'p_os') x) end,
                  coalesce(v_p.parametros -> 'p_restricoes', '{}'::jsonb), true, v_p.criada_por, v_p.autor, p_hoje, p_agora);
      perform set_config('agenda.reaplicando', 'on', true);
      v_nova := public.agenda_aplicar((v_nova ->> 'proposta_id')::uuid, p_os, p_via, p_autor, p_pergunta, p_hoje, p_agora);
      perform set_config('agenda.reaplicando', 'off', true);
      return v_nova || jsonb_build_object('refeita', true);
    end if;
    return jsonb_build_object('ok', false, 'texto', 'A agenda mudou desde que eu montei: peça de novo que eu refaço.');
  end if;
  if p_pergunta is not null and not exists (select 1 from public.agenda_perguntas q
                                             where q.id = p_pergunta and q.critica and q.estado = 'respondida'
                                               and q.opcao_escolhida is not null) then
    return jsonb_build_object('ok', false, 'texto', 'Essa decisão ainda não foi respondida: nada foi feito.');
  end if;
  v_viol := public.agenda_validar(p_proposta, p_os, p_hoje, p_agora, p_pergunta);
  if jsonb_array_length(v_viol) > 0 then
    return jsonb_build_object('ok', false, 'violacoes', v_viol,
      'texto', 'Não mudei nada: ' || (select string_agg(e ->> 'texto', ' ' order by o) from jsonb_array_elements(v_viol) with ordinality t(e, o)));
  end if;

  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);
  v_sel := public._agenda_itens_escolhidos(v_p.itens, p_os, p_pergunta);
  v_via_p := case p_via when 'tela' then 'tela_agendar' else p_via end;
  v_origem := p_via;
  v_va := cf.versao_plano;

  -- 1. Sai o que sai (o fixado só com a chave, e só no item autorizado).
  for v_i in select e from jsonb_array_elements(v_sel) e where e ->> 'op' = 'cancelar' loop
    for v_a in select x from jsonb_array_elements(v_i -> 'alocacoes') x loop
      if v_a ->> 'estado' = 'fixada' then perform set_config('agenda.mexe_fixado', 'on', true); end if;
      update public.agenda_alocacoes
         set estado = 'cancelada', cancelada_motivo = v_i ->> 'motivo'
       where id = (v_a ->> 'alocacao_id')::uuid and estado in ('publicada', 'fixada');
      perform set_config('agenda.mexe_fixado', 'off', true);
      v_n_can := v_n_can + 1;
    end loop;
  end loop;
  -- CORREÇÃO FASE 6: (C1) item 3: a presença do dono com que cada OS entra no plano pela 1ª vez fica guardada
  -- (os_planejamento.presenca_publicada e _motivo, só quando nulas): é a que o motor usou para montar estes meios-dias. Lida
  -- ANTES de as alocações virarem publicadas (depois, _agenda_presenca_aprendida devolveria a guardada). Só a aprendida
  -- (a regra e o que o dono disse não precisam: continuam onde estão).
  for v_os in select distinct (e ->> 'os')::uuid from jsonb_array_elements(v_sel) e
               where e ->> 'op' = 'criar' and e ->> 'tipo' <> 'reserva' order by 1 loop
    v_pa := public._agenda_presenca_aprendida(v_os);
    if v_pa is not null and not coalesce((v_pa ->> 'guardada')::boolean, false) then
      insert into public.os_planejamento (service_order_id, presenca_publicada, presenca_publicada_motivo)
      values (v_os, v_pa ->> 'presenca', v_pa ->> 'motivo')
      on conflict (service_order_id) do update
        set presenca_publicada = excluded.presenca_publicada, presenca_publicada_motivo = excluded.presenca_publicada_motivo
        where public.os_planejamento.presenca_publicada is null;
    end if;
  end loop;
  -- CORREÇÃO FASE 6: fim
  -- 2. Entra o que entra: publicada; fixada no congelado (congelamento) e no pedido do dono (dono).
  for v_i in select e from jsonb_array_elements(v_sel) e where e ->> 'op' = 'criar' loop
    for v_a in select x from jsonb_array_elements(v_i -> 'alocacoes') x loop
      v_fix := case when (v_i ->> 'fixar_dono')::boolean and p_via in ('dono', 'tela', 'aprovacao') then 'dono'
                    when (v_a ->> 'dia')::date <= v_cong then 'congelamento' end;
      v_estado := case when v_fix is null then 'publicada' else 'fixada' end;
      update public.agenda_alocacoes
         set estado = v_estado, fixado_por = v_fix
       where id = (v_a ->> 'alocacao_id')::uuid and proposta_id = p_proposta and estado = 'proposta';
      if not found then
        raise exception 'agenda_aplicar: a alocação % da proposta sumiu.', v_a ->> 'alocacao_id';
      end if;
      v_n_pub := v_n_pub + 1;
    end loop;
  end loop;
  -- o que a proposta trazia e não foi escolhido sai (nunca vigorou)
  delete from public.agenda_alocacoes where proposta_id = p_proposta and estado = 'proposta';
  v_vd := (public._agenda_cfg()).versao_plano;

  -- 3. Por OS tocada: o status pela porta, o espelho das datas, a duração aceita e a ação (com o desfazer).
  for v_os in select distinct (e ->> 'os')::uuid from jsonb_array_elements(v_sel) e order by 1 loop
    v_criadas := array(select (x ->> 'alocacao_id')::uuid
                         from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                        where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar');
    v_canc := array(select (x ->> 'alocacao_id')::uuid
                      from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                     where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar');
    select so.status into v_status from public.service_orders so where so.id = v_os;
    v_tem := public._agenda_os_tem_dia(v_os, p_hoje);
    v_porta := null;
    if v_tem and v_status in ('open', 'approved', 'awaiting_parts', 'awaiting_client')
       and exists (select 1 from jsonb_array_elements(v_sel) e
                    where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar' and e ->> 'tipo' <> 'reserva') then
      v_porta := public.os_transicionar_status(v_os, 'scheduled', v_via_p, null, p_autor, null, p_hoje, p_agora);
    elsif not v_tem and v_status = 'scheduled' then
      v_motivo := (select e ->> 'motivo' from jsonb_array_elements(v_sel) e
                    where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar' order by e ->> 'motivo' = 'material' desc limit 1);
      v_porta := public.os_transicionar_status(v_os, case when v_motivo = 'material' then 'awaiting_parts' else 'approved' end,
                   case when p_via in ('motor', 'vigia') then p_via else 'dono' end, null, p_autor, null, p_hoje, p_agora);
    end if;
    perform public._agenda_espelhar_datas(v_os, p_hoje);
    -- FASE 7e: (7e P3, AG7-33, §3.1-10) a duração só sugerida que o dono aprova pode vir com o viés (o item leva os dias corrigidos por agenda_meios_da_os). Lido aqui, enquanto a OS não tem dias: dias_sem_vies só existe quando há correção aplicada de fato; sem ela, nada muda e grava-se o número do item, como sempre.
    v_7e_m := case when p_via in ('dono', 'tela', 'aprovacao')
                    and exists (select 1 from jsonb_array_elements(v_sel) e where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar' and e ->> 'tipo' <> 'reserva' and e ->> 'fonte' = 'sugerida')
                   then public.agenda_meios_da_os(v_os, p_hoje) end;
    -- FASE 7e: fim
    -- a duração só sugerida que o dono pediu para marcar fica aceita
    if p_via in ('dono', 'tela', 'aprovacao') then
      insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, atualizado_por)
      select v_os, (e ->> 'dias')::numeric, 'aceita', p_agora, p_autor
        from jsonb_array_elements(v_sel) e
       where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar' and e ->> 'tipo' <> 'reserva' and e ->> 'fonte' = 'sugerida'
         and (e ->> 'dias') is not null
       limit 1
      on conflict (service_order_id) do update
        set dias = excluded.dias, estimativa_fonte = 'aceita', estimativa_em = excluded.estimativa_em,
            atualizado_por = excluded.atualizado_por, atualizado_em = now()
        where public.os_planejamento.dias is null;
      -- FASE 7e: (7e P3, §3.1-10) aprovada com o viés: dias guarda o número sem o viés (é o que a medida lê: dias_no_inicio, pm_plano_no_inicio e razao_dono não medem a si mesmos) e aprovado_com_vies guarda o que foi aprovado, que é o que o plano continua lendo (agenda_meios_da_os), sem a correção do dono por cima. O total só vale se os dias de agora forem os do item; a proposta pode ter horas de vida.
      if v_7e_m ? 'dias_sem_vies' then
        update public.os_planejamento x
           set dias = (v_7e_m ->> 'dias_sem_vies')::numeric,
               aprovado_com_vies = jsonb_build_object('dias', x.dias, 'total', case when x.dias = (v_7e_m ->> 'dias')::numeric then (v_7e_m ->> 'total')::int else (x.dias * 2)::int end, 'vies', v_7e_m -> 'vies', 'em', p_hoje)
         where x.service_order_id = v_os and x.dias is distinct from (v_7e_m ->> 'dias_sem_vies')::numeric;
      end if;
      -- FASE 7e: fim
    end if;

    v_tipo := case
      when v_p.escopo = 'semana' and cardinality(v_criadas) > 0 then 'publicar'
      when cardinality(v_criadas) > 0 and cardinality(v_canc) > 0
           and not exists (select 1 from jsonb_array_elements(v_sel) e
                            where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar' and e ->> 'motivo' <> 'promovida') then 'promover_reserva'
      when cardinality(v_criadas) > 0 and cardinality(v_canc) > 0 then 'mover'
      when cardinality(v_criadas) > 0 then 'criar'
      when not exists (select 1 from jsonb_array_elements(v_sel) e
                        where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar' and e ->> 'motivo' <> 'condicao_vencida') then 'soltar_reserva'
      else 'cancelar' end;
    v_motivo := (select string_agg(distinct e ->> 'motivo', ', ') from jsonb_array_elements(v_sel) e
                  where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar');
    v_atraso := (select max((e ->> 'atraso_du')::int) from jsonb_array_elements(v_sel) e
                  where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar');
    v_txt := case
      when v_tipo = 'mover' then
        format('%s: de %s para %s%s.', public._agenda_rotulo_da_os(v_os),
               public._agenda_dias_texto(array(select (x ->> 'dia')::date from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                                                where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar')),
               public._agenda_dias_texto(array(select (x ->> 'dia')::date from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                                                where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar')),
               coalesce(' — ' || (select regexp_replace(e ->> 'texto', '^.* — ', '') from jsonb_array_elements(v_sel) e
                                   where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar' and (e ->> 'violada')::boolean limit 1), '')
               -- o dia pedido pelo dono antes de o material estar garantido: o aviso vai junto
               || coalesce(' — mas ' || (select e ->> 'aviso_material' from jsonb_array_elements(v_sel) e
                                          where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar' and e ->> 'aviso_material' is not null
                                          limit 1), ''))
      else (select string_agg(rtrim(e ->> 'texto', '.'), '; ' order by e ->> 'op' = 'cancelar', e ->> 'de')
              from jsonb_array_elements(v_sel) e where (e ->> 'os')::uuid = v_os) || '.' end;
    v_txt := regexp_replace(v_txt, '\.\.$', '.');
    -- FASE 7: (7a P9, spec §5.9 e §6.4) a proposta que o gestor monta sem o motor (a escada de reparo e o corte do reestimar)
    -- diz o tipo da ação (reparar, reestimar) e a frase dela, por OS, em parametros.gestor. Sem isso na proposta (o motor, a
    -- tela, o dono), nada muda.
    if v_p.parametros #>> '{gestor,tipo}' in ('reparar', 'reestimar') then
      v_tipo := v_p.parametros #>> '{gestor,tipo}';
      v_txt := coalesce(v_p.parametros #>> array['gestor', 'textos', v_os::text], v_txt);
    end if;
    -- FASE 7: fim
    v_desf := case when p_via in ('tela', 'aprovacao') then null
                   else least(p_agora + cf.desfazer_validade,
                              coalesce((select min(lower(a.periodo)) from public.agenda_alocacoes a where a.id = any (v_criadas)),
                                       p_agora + cf.desfazer_validade)) end;
    if v_desf is not null then
      v_desfaz := true;
      v_nomes := v_nomes || coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                                        join public.clients cl on cl.id = so.client_id where so.id = v_os), '');
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, proposta_id, pergunta_id,
                                     critica, versao_antes, versao_depois, alocacoes_criadas, alocacoes_canceladas,
                                     status_antes, status_depois, atraso_du, antes, depois, texto, motivo, autor, desfazivel_ate)
    values (clock_timestamp(), p_hoje, true, v_origem, v_tipo, v_os, array[v_os], p_proposta, p_pergunta,
            p_pergunta is not null, v_va, v_vd, v_criadas, v_canc,
            v_status, (select so.status from public.service_orders so where so.id = v_os), case when v_atraso > 0 then v_atraso end,
            jsonb_build_object('alocacoes', (select coalesce(jsonb_agg(x order by x ->> 'dia', x ->> 'turno'), '[]'::jsonb)
                                               from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                                              where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar'),
                               'fim', (select min(e ->> 'fim_antes') from jsonb_array_elements(v_sel) e
                                        where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar')),
            jsonb_build_object('alocacoes', (select coalesce(jsonb_agg(x order by x ->> 'dia', x ->> 'turno'), '[]'::jsonb)
                                               from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                                              where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar'),
                               'fim', (select max(e ->> 'fim_depois') from jsonb_array_elements(v_sel) e
                                        where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar'),
                               'porta', v_porta),
            left(v_txt, 400), left(v_motivo, 200), p_autor, v_desf)
    returning id into v_acao;
    update public.agenda_alocacoes set acao_id = v_acao where id = any (v_criadas);
    v_acoes := v_acoes || v_acao;
    v_linhas := v_linhas || v_txt;
  end loop;

  update public.agenda_propostas
     set estado = 'aplicada', decidida_em = p_agora,
         decidida_via = case p_via when 'tela' then 'tela' when 'aprovacao' then 'aprovacao' when 'dono' then null else 'motor' end,
         decidida_por = p_autor,
         itens = (select coalesce(jsonb_agg(case when exists (select 1 from jsonb_array_elements(v_sel) s where s = i)
                                                 then i || '{"aplicado": true}'::jsonb else i end order by k), '[]'::jsonb)
                    from jsonb_array_elements(v_p.itens) with ordinality t(i, k))
   where id = p_proposta;

  v_texto := case
    when cardinality(v_linhas) = 0 then 'Nada a mudar na agenda.'
    when v_p.escopo = 'semana' then format('Publiquei a %s: %s',
                                            lower(left(coalesce(v_p.textos ->> 'titulo', 'Semana'), 1))
                                            || substr(coalesce(v_p.textos ->> 'titulo', 'Semana'), 2),
                                            array_to_string(v_linhas, ' '))
    else 'Mudei: ' || array_to_string(v_linhas, ' ') end
    || case when not v_desfaz then ''
            when v_p.escopo = 'semana' then ' *desfaz semana* volta como estava.'
            when cardinality(v_nomes) = 1 then format(' *desfaz %s* volta como estava.', v_nomes[1])
            else ' *desfaz* e o nome volta como estava.' end;
  return jsonb_build_object('ok', true, 'texto', v_texto, 'acoes', to_jsonb(v_acoes), 'publicadas', v_n_pub, 'canceladas', v_n_can,
                            'fora', v_p.fora, 'proposta_id', p_proposta);
end;
$function$;

comment on function public.agenda_aplicar(uuid, uuid[], text, uuid, uuid, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): aplica uma proposta, só com modo_proposta ligado (fora dele: "ainda está em teste", nada muda). Trava o plano; proposta fechada, vencida (expirada) ou de outra versão do plano (obsoleta; com p_via motor, refaz com os mesmos parâmetros e aplica a nova, uma vez) não aplica. agenda_validar não vazia = recusa com a lista. Itens: os das OS de p_os (todas, sem lista), sem os críticos — esses só com p_pergunta respondida (e então toda ação sai critica = true com pergunta_id). Cancelar → cancelada (o fixado com agenda.mexe_fixado); criar → publicada, fixada no congelado (congelamento) e no pedido do dono pela tela, aprovação ou *grava* (dono); o que não foi escolhido é apagado. Por OS: a porta (agendada quando tem dia; de volta quando ficou sem nenhum, aguardando peças se foi o material), o espelho das datas, a duração só sugerida que o dono pediu fica aceita, e uma linha em agenda_acoes (publicar/criar/mover/cancelar/promover_reserva/soltar_reserva) com antes/depois, a frase e o desfazer (desfazer_validade, até o 1º meio-dia começar; não na tela nem na aprovação). Vias: motor, vigia, conferencia, dono, tela, aprovacao. CORREÇÃO FASE 6 (C1, item 3): antes de publicar, guarda em os_planejamento.presenca_publicada/_motivo (só quando nulas) a presença aprendida com que cada OS entra no plano pela 1ª vez. FASE 7 (7a P9, spec §5.9 e §6.4): a proposta que o gestor monta sem o motor (a escada de reparo, _agenda_gestor_reparar; o corte do reestimar, _agenda_gestor_reestimar) traz em parametros.gestor o tipo da ação (reparar, reestimar) e a frase dela por OS: a ação sai com esse tipo e essa frase (o resto do aplicar não muda: as 14 regras, a porta, o desfazer). Sem parametros.gestor, a de antes, byte a byte. FASE 7e (P3): a duração só sugerida aprovada pelo dono com o viés aplicado grava dias sem o viés e o aprovado em aprovado_com_vies; sem correção aplicada, o número do item, como sempre.';

-- ── 3. Portas ────────────────────────────────────────────────────────────────────────────────────
-- Nada de anon. O passo da rodada sem grant nenhum (o P7 o chama de agenda_aprender, definer); as de leitura, para os leitores invoker (os_prontidao, agenda_meios_da_os, os_duracao_sugerida), como no P1 e no P2.
revoke all on function public._agenda_aprender_vies(date, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public._agenda_dias_com_vies(jsonb, numeric), public._agenda_vies_dono_da_os(uuid) from public, anon;
grant execute on function public._agenda_dias_com_vies(jsonb, numeric), public._agenda_vies_dono_da_os(uuid) to authenticated, service_role;

-- Agenda de Produção, Fase 6 ("Aprendizado"), pacote P1: a medição e o gravador — a classe de campo de cada OS (bem × sistema,
-- sem IA), os dias que o dono disse no início (e o congelamento deles), a medida de cada OS concluída, o percentil, o leitor
-- único do que foi aprendido e o gravador único do que foi aprendido (com o estado, a ação desfazível e a pergunta crítica).
-- Spec: scratchpad agenda-pesquisa/spec-fase6.md (§3.1, §3.2, §5.1, §6.2, §6.3). Depende de 20261029100000.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (14 funções novas; nenhuma recriada; nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f6p1/montar-migration.mjs (a parte escrita à mão
-- f6p1/parte-medicao.sql, conferida: nenhuma função de antes recriada, search_path fixo e REVOKE de public e anon em cada uma).
--
-- POR QUE: o aprendizado começa pela medida. Cada OS concluída vira uma linha em agenda_medidas_os — quanto ela levou de verdade
-- (os meios-dias cumpridos e as diárias ligadas) contra o que o dono disse até o check-in, se a medida vale e por que não —, e
-- todo valor aprendido (P2 a P6) passa pelo mesmo gravador e pelo mesmo leitor. O banco mede, o banco calcula, o banco usa.
--
-- O QUE MUDA (só funções novas; quem as chama é a rodada do P6, agenda_aprender):
--   1. _agenda_classe_de_campo(os): {bem, sistema, chave, texto, linha} — o bem pelo tipo do bem (classe_bens), o sistema pela
--      linha de serviço de maior valor (classe_sistemas, na ordem). "energia em motorhome". _agenda_classe_nome e
--      _agenda_classe_texto_do_nivel(chave): "as OS de energia em motorhome", "as OS de energia", "as OS em motorhome", "as OS".
--   2. _agenda_dias_no_inicio(os): os dias ditos até o dia do check-in — a coluna congelada; senão o estado do dia do check-in
--      reconstruído do histórico do planejar (desfazendo o que mudou depois); senão os dias de agora, se foram ditos até o
--      check-in; senão nulo. _agenda_aprender_congelar(hoje) grava a coluna uma vez (só fonte dono ou aceita).
--   3. agenda_medir_os(os, hoje): a linha de agenda_medidas_os (spec §3.1, itens 5 e 6), gravada só quando muda (versão + 1 e o
--      histórico); a OS que voltou de concluída fica inválida (reaberta). _agenda_aprender_medir(hoje): mede as OS concluídas
--      na janela e as que têm medida e não estão mais concluídas; o erro de uma OS vai a app_error_logs (agenda / aprender:medir)
--      e o passo segue.
--   4. _agenda_percentil(valores, q): o percentil contínuo, em numeric exato (vazio = nulo).
--   5. _agenda_aprendido(item, chave): o valor em uso SÓ com modo_aprendizado ligado e o item na lista; senão nulo (= o padrão
--      de hoje). Todo leitor do P2 em diante passa por ele.
--   6. _agenda_aprendizado_gravar(item, chave, nível, calculado, n, amostra, padrão, detalhe, agora): o upsert e o estado (1 n
--      abaixo do mínimo → medindo; 2 modo fora de ligado ou item fora da lista → sombra; 3 travado e dentro da trava → fica;
--      4 igual ao que vale → fica; 5 troca dentro do limite → em uso + ação "aprendizado" com *desfaz*; 6 troca grande →
--      pergunta crítica "aprendizado", uma aberta por chave). Os textos saem de _agenda_aprendizado_texto (o fator completo,
--      §6.2/§6.3; os outros itens com um texto provisório que o pacote de cada item recria) e os valores de
--      _agenda_aprendizado_valor ("1,7×", "R$ 690", "2 dias úteis", "56%"). _agenda_aprendizado_da_lista (o item → a palavra
--      de aprendizado_ligados) e _agenda_aprendizado_troca_cabe (o limite de troca de cada item, §3.2).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase6_medicao.sql):
--   · _agenda_aprender_medir mede TODAS as OS concluídas da janela (e as reabertas) a cada rodada, em vez de só as que mudaram
--     depois de medida_em: agenda_medir_os só grava quando algo mudou, e assim a mensagem ao cliente, o planejar e a diária
--     ligada depois da conclusão também entram (nenhum deles tem um "atualizado em" confiável). O resultado é o mesmo.
--   · A medida sem alocação nenhuma mas com diária ligada VALE (os meios são os das diárias): 'sem_plano' é só a OS sem
--     alocação e sem diária. Os meios contam só a presença "turno" (a curta de abrir e fechar não aumenta o calendário).
--   · meios_sem_registro conta as alocações (por pessoa) até a conclusão sem resultado ou com sem_registro.
--   · A opção 3 da pergunta ("Volto ao padrão") só aparece quando o que vale hoje não é o padrão e o medido também não é
--     (§3.2); o exemplo da §6.3 a mostra com 1,5× em uso, que é o padrão — o texto daqui segue a regra.
--   · Pergunta e trava guardam o valor em uso (ver o cabeçalho da 20261029100000): _agenda_aprendido o devolve em em_uso,
--     pergunta e travado.
--   · A pergunta aberta de uma chave é resolvida sozinha quando o medido volta para dentro do limite, quando cai abaixo do
--     mínimo ou quando o item sai do uso; e é trocada por outra quando o medido muda (o texto diz o número).
--   · n_min de carga = o menor entre ppc_baixo_semanas e ppc_alto_semanas; de solver = solver_semanas; carga e solver vão à
--     lista como "revisao" (o P6 confere).
--
-- O QUE NÃO MUDA: nenhum leitor de antes muda (os_duracao_sugerida, os_presenca_do_dono, a vigia, a prontidão, o motor e a
-- rodada do cliente são recriados nos pacotes P2 a P5). Nada roda sozinho: a rodada é do P6.
--
-- ORDEM DE LIGAR: logo depois de 20261029100000; antes de 20261029100200. Aplicar sozinha não muda nada para ninguém.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase6_medicao.sql (a fixture-fase6 só na bancada) e agenda_fase6_base.sql
-- (as portas). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261029100100
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261029100100_agenda_fase6_medicao.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261029100100', 'agenda_fase6_medicao');"
--
-- IDEMPOTENTE: create or replace function; revoke/grant.

-- ── 1. A classe de campo ────────────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_classe_nome(p_eixo text, p_chave text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_eixo
           when 'bem' then case p_chave when 'rv' then 'motorhome' when 'barco' then 'barco' when 'outro' then 'outro bem' end
           when 'sistema' then case p_chave
             when 'diagnostico' then 'diagnóstico' when 'energia' then 'energia' when 'motor' then 'motor e gerador'
             when 'conectividade' then 'Starlink e eletrônicos' when 'conforto' then 'geladeira, ar e gás'
             when 'geral' then 'outros serviços' end
         end;
$function$;

comment on function public._agenda_classe_nome(text, text) is
  'Agenda de Produção (Fase 6): o nome da chave da classe de campo — bem (rv = motorhome, barco, outro = outro bem) ou sistema (diagnóstico, energia, motor e gerador, Starlink e eletrônicos, geladeira, ar e gás, outros serviços).';

create or replace function public._agenda_classe_de_campo(p_os uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c       public.agenda_config := public._agenda_cfg();
  v_tipo  text;
  v_linha text;
  v_bem   text := 'outro';
  v_sis   text := 'geral';
  e       jsonb;
begin
  select public._agenda_normal(v.asset_type) into v_tipo
    from public.service_orders so left join public.vessels v on v.id = so.vessel_id
   where so.id = p_os;
  if not found then
    return null;
  end if;
  -- A linha principal: a de maior valor (desempate: a mais antiga, depois o id).
  select public._agenda_normal(s.name_snapshot) into v_linha
    from public.service_order_services s
   where s.service_order_id = p_os
   order by s.line_total desc nulls last, s.created_at nulls last, s.id
   limit 1;
  -- As palavras casam no início de palavra do texto normalizado, na ordem da lista (a 1ª que casa vence).
  for e in select x from jsonb_array_elements(c.classe_bens) with ordinality t(x, o) order by o loop
    if coalesce(v_tipo, '') ~ ('\m(' || (e ->> 1) || ')') then
      v_bem := e ->> 0;
      exit;
    end if;
  end loop;
  for e in select x from jsonb_array_elements(c.classe_sistemas) with ordinality t(x, o) order by o loop
    if coalesce(v_linha, '') ~ ('\m(' || (e ->> 1) || ')') then
      v_sis := e ->> 0;
      exit;
    end if;
  end loop;
  return jsonb_build_object('bem', v_bem, 'sistema', v_sis, 'chave', v_bem || ':' || v_sis,
                            'texto', public._agenda_classe_nome('sistema', v_sis) || ' em ' || public._agenda_classe_nome('bem', v_bem),
                            'linha', v_linha);
end;
$function$;

comment on function public._agenda_classe_de_campo(uuid) is
  'Agenda de Produção (Fase 6): a classe de campo da OS, sem IA — {bem, sistema, chave, texto, linha}. Bem: vessels.asset_type normalizado casado com agenda_config.classe_bens (senão outro). Sistema: a linha de serviço de maior line_total (desempate created_at, id) casada NA ORDEM de classe_sistemas (senão geral). As palavras casam no início de palavra. texto = "energia em motorhome".';

create or replace function public._agenda_classe_texto_do_nivel(p_chave text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
           when p_chave = 'todas' then 'as OS'
           when p_chave like 'sistema:%' then 'as OS de ' || public._agenda_classe_nome('sistema', substr(p_chave, 9))
           when p_chave like 'bem:%' then 'as OS em ' || public._agenda_classe_nome('bem', substr(p_chave, 5))
           when p_chave ~ '^[a-z]+:[a-z]+$' then
             'as OS de ' || public._agenda_classe_nome('sistema', split_part(p_chave, ':', 2))
             || ' em ' || public._agenda_classe_nome('bem', split_part(p_chave, ':', 1))
         end;
$function$;

comment on function public._agenda_classe_texto_do_nivel(text) is
  'Agenda de Produção (Fase 6): a chave de uma classe dita ao dono — rv:energia → "as OS de energia em motorhome"; sistema:energia → "as OS de energia"; bem:rv → "as OS em motorhome"; todas → "as OS".';

-- ── 2. Os dias ditos no início ──────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_dias_no_inicio(p_os uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  pl      public.os_planejamento;
  v_ci    date;
  v_dias  numeric;
  v_fonte text;
  v_desfez boolean := false;
  v_disse  boolean := false;
  e       jsonb;
begin
  select (so.check_in_at at time zone 'America/Sao_Paulo')::date into v_ci from public.service_orders so where so.id = p_os;
  select * into pl from public.os_planejamento where service_order_id = p_os;
  if pl.dias_no_inicio is not null then
    return jsonb_build_object('dias', pl.dias_no_inicio, 'fonte', pl.dias_no_inicio_fonte, 'em', pl.dias_no_inicio_em,
                              'origem', 'coluna');
  end if;
  if v_ci is null or pl.service_order_id is null then
    return null;
  end if;
  -- O estado do dia do check-in: o de agora, desfazendo (do mais novo ao mais velho) o que o planejar mudou DEPOIS dele.
  v_dias := pl.dias;
  v_fonte := pl.estimativa_fonte;
  for e in select x from jsonb_array_elements(pl.historico) with ordinality t(x, o) order by o desc loop
    continue when coalesce(e ->> 'em', '') !~ '^\d{4}-\d{2}-\d{2}';
    if left(e ->> 'em', 10)::date > v_ci then
      if coalesce(e -> 'antes', '{}'::jsonb) ? 'dias' then
        v_dias := (e #>> '{antes,dias}')::numeric;
        v_desfez := true;
      end if;
      if coalesce(e -> 'antes', '{}'::jsonb) ? 'estimativa_fonte' then
        v_fonte := e #>> '{antes,estimativa_fonte}';
      end if;
    elsif coalesce(e -> 'depois', '{}'::jsonb) ? 'dias' then
      v_disse := true;
    end if;
  end loop;
  if v_dias is null or v_fonte is null then
    return null;
  end if;
  if v_desfez or v_disse then
    return jsonb_build_object('dias', v_dias, 'fonte', v_fonte, 'em', v_ci, 'origem', 'historico');
  end if;
  -- Sem rastro no histórico (o dono disse antes do histórico existir, ou por outro caminho): os dias de agora, se foram
  -- ditos até o dia do check-in.
  if pl.estimativa_em is not null and (pl.estimativa_em at time zone 'America/Sao_Paulo')::date <= v_ci then
    return jsonb_build_object('dias', v_dias, 'fonte', v_fonte, 'em', v_ci, 'origem', 'atual');
  end if;
  return null;
end;
$function$;

comment on function public._agenda_dias_no_inicio(uuid) is
  'Agenda de Produção (Fase 6): os dias que o dono disse (ou aceitou) até o dia do check-in — {dias, fonte, em, origem}: a coluna os_planejamento.dias_no_inicio (origem coluna); senão o estado do dia do check-in reconstruído do histórico do planejar, desfazendo o que mudou depois (historico); senão os dias de agora, se estimativa_em ≤ o check-in (atual); senão nulo. A sugestão do banco nunca entra (estimativa_fonte só é dono ou aceita).';

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
  return jsonb_build_object('congeladas', n_c, 'sem_dias', n_s);
end;
$function$;

comment on function public._agenda_aprender_congelar(date) is
  'Agenda de Produção (Fase 6): a rodada do aprendizado congela, uma vez, os dias ditos no início — toda OS com check-in até p_hoje (na janela aprender_janela_dias) e sem os_planejamento.dias_no_inicio recebe o de _agenda_dias_no_inicio (só fonte dono ou aceita; a sugestão do banco nunca). {congeladas, sem_dias}. Definer, sem grant a ninguém.';

-- ── 3. A medida de cada OS ──────────────────────────────────────────────────────────────────────────────
create or replace function public.agenda_medir_os(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  so      public.service_orders;
  pl      public.os_planejamento;
  m0      public.agenda_medidas_os;
  m       public.agenda_medidas_os;
  v_concl boolean;
  v_cls   jsonb;
  v_d     jsonb;
  v_sug   jsonb;
  v_dono  uuid := public._agenda_dono();
  v_aloc  int;
  v_doaloc int;
  v_meios numeric;
  v_novo  jsonb;
  v_velho jsonb;
  v_antes jsonb := '{}'::jsonb;
  v_depois jsonb := '{}'::jsonb;
  v_hist  jsonb;
  k       text;
begin
  if p_os is null or p_hoje is null then
    raise exception 'Falta a OS ou o dia.' using errcode = '22023';
  end if;
  select * into so from public.service_orders where id = p_os;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'nao_achei');
  end if;
  select * into m0 from public.agenda_medidas_os where service_order_id = p_os for update;
  v_concl := so.status in ('completed', 'invoiced') and so.merged_into_id is null;
  if not v_concl and m0.service_order_id is null then
    return jsonb_build_object('ok', true, 'medida', false, 'motivo', 'nao_concluida');
  end if;
  select * into pl from public.os_planejamento where service_order_id = p_os;
  v_sug := public.os_duracao_sugerida(p_os);

  m.service_order_id := p_os;
  v_cls := public._agenda_classe_de_campo(p_os);
  m.classe_bem := v_cls ->> 'bem';
  m.classe_sistema := v_cls ->> 'sistema';
  m.concluida_em := case when v_concl then (coalesce(so.check_out_at, so.updated_at) at time zone 'America/Sao_Paulo')::date
                         else m0.concluida_em end;
  m.entregue_em := (so.delivered_at at time zone 'America/Sao_Paulo')::date;

  -- Os dias: os ditos até o check-in; senão a duração sugerida (a medida não vale).
  v_d := case when pl.dias_no_inicio is not null
              then jsonb_build_object('dias', pl.dias_no_inicio, 'fonte', pl.dias_no_inicio_fonte)
              else public._agenda_dias_no_inicio(p_os) end;
  if v_d is null and not coalesce((v_sug ->> 'sem_base')::boolean, true) and (v_sug ->> 'sugerida') is not null then
    v_d := jsonb_build_object('dias', (v_sug ->> 'sugerida')::numeric, 'fonte', 'sugerida');
  end if;
  m.dias_no_inicio := (v_d ->> 'dias')::numeric;
  m.dias_fonte := v_d ->> 'fonte';
  m.meios_planejados := (m.dias_no_inicio * 2)::smallint;

  -- Os meios-dias que aconteceram: (dia, turno) distintos das alocações vigentes não reserva da presença "turno" até a
  -- conclusão (cumprido 1, parcial meio, o resto 0; o melhor das pessoas daquele meio-dia).
  select coalesce(sum(x.valor), 0) into v_meios
    from (select a.dia, a.turno,
                 max(case a.resultado when 'cumprido' then 1 when 'parcial' then 0.5 else 0 end) as valor
            from public.agenda_alocacoes a
           where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
             and a.presenca = 'turno' and a.dia <= m.concluida_em
           group by a.dia, a.turno) x;
  select count(*)::int,
         count(*) filter (where a.payee_id = v_dono)::int,
         count(*) filter (where a.presenca = 'turno' and (a.resultado is null or a.resultado = 'sem_registro'))::smallint
    into v_aloc, v_doaloc, m.meios_sem_registro
    from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
     and a.dia <= m.concluida_em;
  m.so_o_dono := v_aloc > 0 and v_aloc = v_doaloc;

  -- As diárias ligadas à OS em dia sem alocação dela (a fração daquele dia na OS: 1 = 2 meios, meia = 1).
  select coalesce(sum(greatest(1, round(x.f * 2))), 0)::smallint into m.meios_fora_do_plano
    from (select ws.data, max(ws.fracao / (select count(*) from public.work_shift_os w2 where w2.shift_id = ws.id)) as f
            from public.work_shift_os wo
            join public.work_shifts ws on ws.id = wo.shift_id
            join public.work_profiles wp on wp.id = ws.work_profile_id
            join public.payees p on p.id = wp.payee_id
           where wo.service_order_id = p_os and ws.fracao > 0 and wp.modo_pagamento = 'diaria'
             and p.kind is distinct from 'socio' and ws.data <= m.concluida_em
             and not exists (select 1 from public.agenda_alocacoes a
                              where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                                and a.dia = ws.data)
           group by ws.data) x;
  m.meios_cumpridos := v_meios + m.meios_fora_do_plano;
  select coalesce(sum(v.dias), 0) into m.diarias_ligadas from public.v_dias_por_os_e_pessoa v where v.service_order_id = p_os;
  m.mo := (v_sug ->> 'mo')::numeric;

  m.motivo := case
    when not v_concl then 'reaberta'
    when so.check_in_at is null then 'sem_inicio'
    when m.dias_no_inicio is null then 'sem_dias_no_inicio'
    when m.dias_fonte = 'sugerida' then 'dias_sugeridos'
    when v_aloc = 0 and m.diarias_ligadas = 0 then 'sem_plano'
    when m.meios_sem_registro > 0 then 'conferencia_incompleta'
    when m.diarias_ligadas = 0 and not m.so_o_dono then 'sem_diaria'
  end;
  m.valida := m.motivo is null;
  m.fator := case when m.valida and m.meios_planejados > 0
                  then least(round(m.meios_cumpridos / m.meios_planejados, 2), 99) end;

  -- O cliente: a 1ª promessa contra a conclusão; os avisos de atraso que saíram e o fim da faixa do último.
  m.prometido_primeiro_ate := coalesce(pl.prometido_primeiro_ate, pl.prometido_original_ate);
  m.atraso_cliente_du := public.agenda_du_entre(m.prometido_primeiro_ate, m.concluida_em);
  select count(*)::smallint into m.avisos_enviados
    from public.agenda_cliente_mensagens x
   where x.service_order_id = p_os and x.tipo in ('pode_atrasar', 'nova_data') and x.modo = 'ligado' and x.enviada_em is not null;
  select coalesce(x.faixa_ate, case when x.variante is distinct from 'peca_sem_data' then x.dia_alvo end) into m.aviso_faixa_ate
    from public.agenda_cliente_mensagens x
   where x.service_order_id = p_os and x.tipo = 'pode_atrasar' and x.modo = 'ligado' and x.enviada_em is not null
     and coalesce(x.faixa_ate, case when x.variante is distinct from 'peca_sem_data' then x.dia_alvo end) is not null
   order by x.enviada_em desc, x.id desc
   limit 1;
  m.aviso_estouro_du := public.agenda_du_entre(m.aviso_faixa_ate, m.concluida_em);

  -- Grava só quando muda.
  m.medida_em := now();
  v_novo := to_jsonb(m) - array['medida_em', 'versao', 'historico'];
  if m0.service_order_id is null then
    m.versao := 1;
    m.historico := '[]'::jsonb;
    insert into public.agenda_medidas_os select (m).*;
    return jsonb_build_object('ok', true, 'medida', true, 'nova', true, 'mudou', true, 'versao', 1, 'valida', m.valida,
                              'motivo', m.motivo, 'fator', m.fator, 'chave', v_cls ->> 'chave');
  end if;
  v_velho := to_jsonb(m0) - array['medida_em', 'versao', 'historico'];
  if v_novo = v_velho then
    return jsonb_build_object('ok', true, 'medida', true, 'nova', false, 'mudou', false, 'versao', m0.versao, 'valida', m0.valida,
                              'motivo', m0.motivo, 'fator', m0.fator, 'chave', v_cls ->> 'chave');
  end if;
  for k in select key from jsonb_each(v_novo) loop
    if v_novo -> k is distinct from v_velho -> k then
      v_antes := v_antes || jsonb_build_object(k, v_velho -> k);
      v_depois := v_depois || jsonb_build_object(k, v_novo -> k);
    end if;
  end loop;
  v_hist := m0.historico || jsonb_build_array(jsonb_build_object('em', p_hoje, 'versao', m0.versao,
                                                                  'antes', v_antes, 'depois', v_depois));
  if jsonb_array_length(v_hist) > 20 then
    select jsonb_agg(x order by o) into v_hist
      from jsonb_array_elements(v_hist) with ordinality t(x, o) where o > jsonb_array_length(v_hist) - 20;
  end if;
  update public.agenda_medidas_os
     set classe_bem = m.classe_bem, classe_sistema = m.classe_sistema, concluida_em = m.concluida_em,
         entregue_em = m.entregue_em, dias_no_inicio = m.dias_no_inicio, dias_fonte = m.dias_fonte,
         meios_planejados = m.meios_planejados, meios_cumpridos = m.meios_cumpridos,
         meios_fora_do_plano = m.meios_fora_do_plano, meios_sem_registro = m.meios_sem_registro,
         diarias_ligadas = m.diarias_ligadas, so_o_dono = m.so_o_dono, mo = m.mo, fator = m.fator, valida = m.valida,
         motivo = m.motivo, prometido_primeiro_ate = m.prometido_primeiro_ate, atraso_cliente_du = m.atraso_cliente_du,
         avisos_enviados = m.avisos_enviados, aviso_faixa_ate = m.aviso_faixa_ate, aviso_estouro_du = m.aviso_estouro_du,
         medida_em = m.medida_em, versao = m0.versao + 1, historico = v_hist
   where service_order_id = p_os;
  return jsonb_build_object('ok', true, 'medida', true, 'nova', false, 'mudou', true, 'versao', m0.versao + 1,
                            'valida', m.valida, 'motivo', m.motivo, 'fator', m.fator, 'chave', v_cls ->> 'chave');
end;
$function$;

comment on function public.agenda_medir_os(uuid, date) is
  'Agenda de Produção (Fase 6): a medida da OS concluída (spec-fase6 §3.1, itens 5 e 6) em agenda_medidas_os — a classe, os dias ditos no início (senão a sugerida: não vale), os meios-dias planejados e os que aconteceram, as diárias ligadas, se é só do dono, a mão de obra, o fator (só a válida), o motivo da inválida, a 1ª promessa ao cliente contra a conclusão e o último aviso de atraso. Grava só quando muda (versao + 1 e o que mudou no histórico). A OS que voltou de concluída fica inválida (reaberta). Definer, sem grant a ninguém.';

create or replace function public._agenda_aprender_medir(p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c     public.agenda_config := public._agenda_cfg();
  r     record;
  v     jsonb;
  n_olh int := 0;
  n_med int := 0;
  n_err int := 0;
  v_val int;
  v_inv jsonb;
begin
  if p_hoje is null then
    raise exception 'Falta o dia (p_hoje).' using errcode = '22023';
  end if;
  for r in
    select so.id, so.service_order_number
      from public.service_orders so
     where (so.status in ('completed', 'invoiced') and so.merged_into_id is null
            and (coalesce(so.check_out_at, so.updated_at) at time zone 'America/Sao_Paulo')::date
                between p_hoje - c.aprender_janela_dias and p_hoje)
        or exists (select 1 from public.agenda_medidas_os m where m.service_order_id = so.id)
     order by so.id
  loop
    n_olh := n_olh + 1;
    begin
      v := public.agenda_medir_os(r.id, p_hoje);
      if coalesce((v ->> 'mudou')::boolean, false) then
        n_med := n_med + 1;
      end if;
    exception when others then
      perform public.log_app_error('db', format('aprendizado, medir %s: %s', coalesce(r.service_order_number, r.id::text), sqlerrm),
                                   'agenda', 'aprender:medir', 'error',
                                   jsonb_build_object('os', r.id, 'sqlstate', sqlstate, 'p_hoje', p_hoje));
      n_err := n_err + 1;
    end;
  end loop;
  select count(*) filter (where m.valida)::int,
         coalesce(jsonb_object_agg(m.motivo, m.n) filter (where m.motivo is not null), '{}'::jsonb)
    into v_val, v_inv
    from (select x.valida, x.motivo, count(*) over (partition by x.motivo) as n
            from public.agenda_medidas_os x
           where x.concluida_em between p_hoje - c.aprender_janela_dias and p_hoje) m;
  return jsonb_build_object('olhadas', n_olh, 'medidas', n_med, 'validas', coalesce(v_val, 0),
                            'invalidas', coalesce(v_inv, '{}'::jsonb), 'erros', n_err);
end;
$function$;

comment on function public._agenda_aprender_medir(date) is
  'Agenda de Produção (Fase 6): o passo da medição da rodada — mede (agenda_medir_os) as OS concluídas nos aprender_janela_dias até p_hoje e as que têm medida (a reaberta). Só grava o que mudou. O erro de uma OS vai a app_error_logs (agenda / aprender:medir) e o passo segue. {olhadas, medidas (gravadas), validas, invalidas: {motivo: n}, erros} (as contagens das medidas da janela). Sem grant a ninguém.';

-- ── 4. O percentil ──────────────────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_percentil(p_valores numeric[], p_q numeric)
 returns numeric
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v   numeric[];
  n   int;
  pos numeric;
  i   int;
begin
  select array_agg(x order by x) into v from unnest(p_valores) x where x is not null;
  n := coalesce(cardinality(v), 0);
  if n = 0 or p_q is null then
    return null;
  end if;
  if p_q < 0 or p_q > 1 then
    raise exception 'O percentil vai de 0 a 1 (veio %).', p_q using errcode = '22023';
  end if;
  -- O contínuo (o mesmo de percentile_cont), em numeric exato: a posição (n − 1) × q entre os vizinhos.
  pos := (n - 1) * p_q;
  i := floor(pos)::int;
  if i + 1 >= n then
    return v[n];
  end if;
  return v[i + 1] + (pos - i) * (v[i + 2] - v[i + 1]);
end;
$function$;

comment on function public._agenda_percentil(numeric[], numeric) is
  'Agenda de Produção (Fase 6): o percentil contínuo (o de percentile_cont) de p_valores, em numeric exato; nulos fora; vazio = nulo. P80 de 1,0 1,0 1,25 1,5 1,5 1,75 2,0 = 1,7.';

-- ── 5. O leitor e o gravador do que foi aprendido ───────────────────────────────────────────────────────
create or replace function public._agenda_aprendizado_da_lista(p_item text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_item
           when 'fator' then 'fator' when 'mo' then 'mo' when 'presenca' then 'presenca'
           when 'fornecedor_atraso' then 'fornecedor' when 'fornecedor_prazo' then 'fornecedor'
           when 'capacidade_dono' then 'capacidade_dono' when 'aviso_folga' then 'aviso_cliente'
           when 'carga' then 'revisao' when 'solver' then 'revisao'
         end;
$function$;

comment on function public._agenda_aprendizado_da_lista(text) is
  'Agenda de Produção (Fase 6): o item de agenda_aprendizado → a palavra de agenda_config.aprendizado_ligados que o liga (fornecedor_atraso e _prazo → fornecedor; aviso_folga → aviso_cliente; carga e solver → revisao). cliente_pontualidade → nulo: só medida, nunca usada.';

create or replace function public._agenda_aprendido(p_item text, p_chave text)
 returns numeric
 language sql
 stable
 set search_path to 'public'
as $function$
  select a.em_uso
    from public.agenda_aprendizado a
    join public.agenda_config c on c.id
   where a.item = p_item and a.chave = p_chave
     and a.estado in ('em_uso', 'pergunta', 'travado') and a.em_uso is not null
     and c.modo_aprendizado = 'ligado'
     and public._agenda_aprendizado_da_lista(p_item) = any (c.aprendizado_ligados);
$function$;

comment on function public._agenda_aprendido(text, text) is
  'Agenda de Produção (Fase 6): o leitor único do que foi aprendido — o valor em uso de (item, chave) SÓ com modo_aprendizado ligado e o item em aprendizado_ligados (em uso, ou guardado na pergunta e na trava); senão nulo = o padrão de hoje. Pôr o modo em sombra devolve o padrão na hora em todo leitor.';

create or replace function public._agenda_aprendizado_troca_cabe(p_item text, p_nivel text, p_de numeric, p_para numeric)
 returns boolean
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c public.agenda_config := public._agenda_cfg();
begin
  if p_para is null then
    return false;
  end if;
  return coalesce(case p_item
    when 'fator' then abs(p_para - p_de) <= c.fator_troca_max
    when 'mo' then p_de > 0 and abs(p_para - p_de) / p_de <= c.mo_troca_max
    when 'fornecedor_atraso' then abs(p_para - p_de) <= c.fornecedor_troca_max_du
    when 'fornecedor_prazo' then abs(p_para - p_de) <= c.fornecedor_troca_max_du
    when 'capacidade_dono' then abs(p_para - p_de) <= c.capacidade_troca_max
    when 'aviso_folga' then abs(p_para - p_de) <= c.aviso_troca_max_du
    -- a presença numa classe entra sozinha; no geral é a regra d05 inteira: sempre pergunta
    when 'presenca' then p_nivel in ('fina', 'sistema')
    -- a carga de todos e o planejador mais forte sempre perguntam; a pontualidade nunca é usada
  end, false);
end;
$function$;

comment on function public._agenda_aprendizado_troca_cabe(text, text, numeric, numeric) is
  'Agenda de Produção (Fase 6): a troca de p_de para p_para do item entra sozinha? (spec-fase6 §3.2) fator |Δ| ≤ fator_troca_max; mo |Δ|/de ≤ mo_troca_max; fornecedor |Δ| ≤ fornecedor_troca_max_du; capacidade |Δ| ≤ capacidade_troca_max; aviso |Δ| ≤ aviso_troca_max_du; presença só na classe fina ou de sistema; carga, solver e o resto nunca.';

create or replace function public._agenda_aprendizado_valor(p_item text, p_v numeric)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
           when p_v is null then null
           when p_item = 'fator' then public._agenda_num(p_v, 2) || '×'
           when p_item = 'mo' then 'R$ ' || translate(to_char(round(p_v), 'FM999,999,990'), ',', '.')
           when p_item in ('capacidade_dono', 'carga', 'cliente_pontualidade') then round(p_v * 100)::text || '%'
           when p_item in ('fornecedor_atraso', 'fornecedor_prazo', 'aviso_folga') then
             case when p_v = 1 then '1 dia útil' else public._agenda_num(p_v, 1) || ' dias úteis' end
           when p_item = 'presenca' then case when p_v >= 1 then 'o dia todo' else 'abre e fecha' end
           else public._agenda_num(p_v, 2)
         end;
$function$;

comment on function public._agenda_aprendizado_valor(text, numeric) is
  'Agenda de Produção (Fase 6): um valor aprendido como o dono lê — fator "1,7×"; R$ por diária "R$ 690"; capacidade, carga e pontualidade "56%"; fornecedor e aviso "2 dias úteis"; presença "o dia todo" / "abre e fecha".';

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
  'Agenda de Produção (Fase 6): os textos do aprendizado ao dono, do banco — p_momento foco_<estado> (a linha do foco), acao (o que mudou sozinho), pergunta (a troca grande, sem as opções), opcao1/2/3, desfeito e fico. p_d: {chave, calculado, em_uso, efetivo (o que valia antes), padrao, volta, n, n_min, desde, travado_ate, trava_dias}. O fator tem os textos da spec-fase6 §6.2/§6.3; os outros itens, um texto provisório que o pacote de cada um recria (copiar DESTA definição).';

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
  if v_estado <> 'travado' then
    r.travado_ate := null;
    r.travado_valor := null;
  end if;

  v_d := jsonb_build_object('chave', p_chave, 'calculado', p_calculado, 'em_uso', r.em_uso, 'efetivo', v_efet,
                            'padrao', p_padrao, 'n', r.n, 'n_min', v_nmin,
                            'desde', (r.em_uso_desde at time zone 'America/Sao_Paulo')::date, 'travado_ate', r.travado_ate,
                            'trava_dias', c.aprender_trava_dias, 'detalhe', r.detalhe);

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
  'Agenda de Produção (Fase 6): o gravador único de agenda_aprendizado (spec-fase6 §5.1) — o upsert de (item, chave) e o estado, nesta ordem: 1 n < n_min → medindo; 2 modo fora de ligado, item fora de aprendizado_ligados ou só de medida → sombra; 3 travado e dentro da trava (a data e o limite de troca a partir do valor recusado) → fica; 4 o medido = o que vale → em uso; 5 troca dentro do limite (§3.2) → em uso + a ação aprendizado (origem vigia, desfazível por desfazer_validade); 6 troca grande → pergunta crítica aprendizado (chave aprendizado:<item>:<chave>, uma aberta por chave). Toda mudança de em uso, estado e calculado vai ao histórico. Definer, sem grant a ninguém.';

-- ── 6. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- Leituras e textos (não leem nada que o login não leia): authenticated e service_role. O resto é interno: sem grant a
-- ninguém, nem service_role (quem chama é a rodada do P6, agenda_aprender, definer). Nenhuma executa para anon.
revoke all on function public._agenda_classe_nome(text, text), public._agenda_classe_texto_do_nivel(text),
  public._agenda_percentil(numeric[], numeric), public._agenda_aprendizado_da_lista(text), public._agenda_aprendido(text, text),
  public._agenda_aprendizado_valor(text, numeric), public._agenda_aprendizado_texto(text, text, jsonb)
  from public, anon;
grant execute on function public._agenda_classe_nome(text, text), public._agenda_classe_texto_do_nivel(text),
  public._agenda_percentil(numeric[], numeric), public._agenda_aprendizado_da_lista(text), public._agenda_aprendido(text, text),
  public._agenda_aprendizado_valor(text, numeric), public._agenda_aprendizado_texto(text, text, jsonb)
  to authenticated, service_role;

revoke all on function public._agenda_classe_de_campo(uuid), public._agenda_dias_no_inicio(uuid),
  public._agenda_aprender_congelar(date), public.agenda_medir_os(uuid, date), public._agenda_aprender_medir(date),
  public._agenda_aprendizado_troca_cabe(text, text, numeric, numeric),
  public._agenda_aprendizado_gravar(text, text, text, numeric, integer, jsonb, numeric, jsonb, timestamptz)
  from public, anon, authenticated, service_role;

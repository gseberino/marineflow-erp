-- Agenda de Produção, Fase 7, etapa 7g ("Mostrar como pensou e provar o trabalho"), pacote P4: o *livre* de 4 semanas e o "se aprovar hoje" pelo encaixe.
-- "Se o cliente aprovar hoje, quando dá?" deixa de responder pela fila da Fase 1 ("Pela fila de hoje, começa entre qua 16/12 e ter 05/01", com o Alex sem
-- nada marcado) e passa a responder pelo encaixe do motor sobre o plano de agora, com as mesmas fontes que a agenda_propor usaria para a OS; e o *livre*
-- mostra livre_semanas semanas, com o que a equipe pode, o que está marcado, reservado, livre e a folga.
-- Spec: scratchpad agenda-pesquisa/spec-fase7g.md (§5.4, §6.3 e o bloco R9, que vale sobre o corpo: R9.3-2 (AG7-32), R9.4-6, R9.5-28, R9.7, R9.8, R9.12,
-- R9.13: "Encolhe — sem agenda_simular; só agenda_ctp, agenda_livre_de_verdade, agenda_encaixe_do_novo"); o registro do pacote: notas-fase7g.md (seção P4).
-- Depende das Fases 1 a 6, das etapas 7a a 7d, da 7f inteira, da 7e inteira e da 7g até o P3 (20261112100000: modo_explicar e livre_semanas).
--
-- ═══ DDL — OK NOMEADO ═══ (3 funções recriadas; 2 funções novas, SECURITY DEFINER com porta)
-- NÃO APLICADA. Existe para revisão e espera o OK.
--
-- POR QUE: com modo_proposta ligado desde 28/10, a única saída viva da projeção da Fase 1 é o agenda_ctp (R9.4-6). Ela conta a fila inteira como se ocupasse a
-- equipe e diz uma faixa de semanas que o plano não tem. O encaixe do motor (o mesmo de "um serviço de 2 dias, quando dá?") diz o 1º dia que cabe de verdade.
--
-- O QUE MUDA (com modo_explicar desligado, nada: as 3 recriadas respondem byte a byte o de antes; em sombra, o de antes e o novo só em dados.teste):
--   1. _agenda_encaixe_simulado (nova, SECURITY DEFINER, porta admin/financeiro ou service_role): o CORPO de agenda_encaixe_do_novo (recriada de 20261031100980_agenda_fase77a_correcao.sql:3928; md5 do corpo de antes e9333e07be2808185c3351698e50930c) com a entrada num jsonb
--      ({dias, gente, dono, passos, nao_antes_de, dm, dtd, rotulo}) e 3 trocas marcadas: os meios-dias vêm de passos (sem ele, dias × 2, como antes), o 1º
--      dia possível de nao_antes_de (sem ele, o 1º dia que a agenda ainda pode mudar, como antes) e as pessoas por turno de dm/dtd quando ninguém foi dito
--      (sem eles, a equipe sugerida, como antes). Sem as chaves novas, a mesma saída de antes.
--   2. agenda_encaixe_do_novo (recriada de 20261031100980_agenda_fase77a_correcao.sql:3928; md5 do corpo de antes e9333e07be2808185c3351698e50930c): depois das mesmas conferências de entrada e de quem vê,
--      devolve _agenda_encaixe_simulado({dias, gente, dono}, hoje): a conta mora num lugar só. A saída é a de antes, byte a byte, nos 3 modos.
--   3. _agenda_entrada_simulada_da_os (nova, SECURITY DEFINER, mesma porta): a entrada do encaixe para uma OS ou ORÇ, com as MESMAS fontes da agenda_propor
--      (os_prontidao: o 1º dia possível, com a compra contada como se aprovasse hoje; agenda_meios_da_os: os meios-dias, as pessoas por turno, a presença do dono).
--   4. agenda_ctp (recriada de 20261024160500_agenda_fase1_leituras.sql:1784; md5 do corpo de antes d7760665552fa30a76b34c30f3ecf605): com modo_explicar ligado, depois da duração e do material (que ficam), o
--      início vem do encaixe ("Pelo plano de agora, cabe em qui 12 a ter 17/11, com Alex; você abre e fecha."), e a frase ao cliente diz a semana e os dias de
--      serviço, sem o dia em que fica pronto (AG7-32): "semana de 09/11, uns 4 dias de serviço; confirmo a data quando as peças chegarem". Vai ao dono; nada
--      sai ao cliente. Em sombra: a resposta de antes e dados.teste = {de, ate, texto}. OS já aprovada: como hoje (diz o estado).
--   5. agenda_livre_de_verdade (recriada de 20261101100800_agenda_fase77b_correcao.sql:514; md5 do corpo de antes 79b284f05d99aadb3099649138e7d520): com modo_explicar ligado, livre_semanas semanas (no lugar das 3), cada uma
--      com totais = {pode, folga, marcado, reservado, livre} da equipe sem você (a folga pela regra de agenda_como_pensei, R9.7) e o texto do §6.3; texto_completo
--      no formato do §6.3: o título, as semanas, a folga fora da conta, as notas de você e como perguntar de um serviço novo (o que ocupa e o que não ocupa
--      ninguém ficam nos dados, fora do texto). A linha curta (texto: a da semana e da tela) e os meios-dias de cada pessoa ficam os de antes. Em sombra: a
--      resposta de antes e dados.teste = {semanas}.
--
-- O QUE NÃO MUDA: agenda_simular e as 3 condições de agenda_ver (R9.4-6), o motor, as propostas, o que se grava, as mensagens. Nenhum texto novo ao cliente;
-- nenhuma mensagem nova. Nada é gravado.
--
-- ORDEM DE LIGAR (spec R9.14): depois da 20261112100200. Aplicar sozinha não muda nada: modo_explicar fica como estiver (desligado até o dado 20261112100990).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7g_livre.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261112100300
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; pelo publicar/exec/aplicar.sh, nunca db push: esta versão fica antes das 20261116* que já estão em produção):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261112100300_agenda_fase7g_livre.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261112100300', 'agenda_fase7g_livre');"
--
-- DESFAZER (na ordem): agenda_encaixe_do_novo, agenda_ctp e agenda_livre_de_verdade voltam pelo corpo das origens (acima); depois
--   drop function if exists public._agenda_entrada_simulada_da_os(uuid, date), public._agenda_encaixe_simulado(jsonb, date);
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. O encaixe de um serviço simulado ──────────────────────────────────────────────────────────────
-- O corpo de agenda_encaixe_do_novo, com a entrada num jsonb lido para variáveis com os nomes dos parâmetros de lá (p_dias, p_gente, p_dono: o corpo de baixo é
-- o mesmo, byte a byte, fora os blocos -- FASE 7g) e 3 trocas: passos, nao_antes_de, dm/dtd. As mensagens de erro de entrada são as de lá (quem chama de dentro
-- já conferiu).
create or replace function public._agenda_encaixe_simulado(p_entrada jsonb, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  -- FASE 7g: (7g P4, §5.4) a entrada: dias, gente e dono com os nomes dos parâmetros de agenda_encaixe_do_novo (o corpo de baixo é o de lá); e as 3 trocas —
  -- passos (os meios-dias), nao_antes_de (o 1º dia possível) e dm/dtd (as pessoas por turno quando ninguém foi dito). Sem elas, a conta de antes.
  p_dias    numeric := (p_entrada ->> 'dias')::numeric;
  p_gente   jsonb := p_entrada -> 'gente';
  p_dono    text := p_entrada ->> 'dono';
  v_7g_pas  int := (p_entrada ->> 'passos')::int;
  v_7g_nad  date := (p_entrada ->> 'nao_antes_de')::date;
  v_7g_dm   int := (p_entrada ->> 'dm')::int;
  v_7g_dtd  int := (p_entrada ->> 'dtd')::int;
  -- FASE 7g: fim
  cf       public.agenda_config := public._agenda_cfg();
  v_uid    uuid := auth.uid();
  v_lista  jsonb := case when jsonb_typeof(coalesce(p_gente, '[]'::jsonb)) = 'array' then coalesce(p_gente, '[]'::jsonb)
                         else '[]'::jsonb end;
  v_g      jsonb;
  v_ctx    jsonb;
  v_ini    date;
  v_de     date;
  v_hor    date;
  v_pes    uuid[];
  v_nomes  text[];
  v_dono   int;
  v_padrao boolean;
  v_pm     int[] := '{}';
  v_pt     int[] := '{}';
  v_dtm    boolean := false;
  v_dtt    boolean := false;
  v_abre   boolean := false;
  v_fora   text[] := '{}';
  v_dm     int;
  v_dtd    int;
  v_passos int;
  v_e      jsonb;
  v_par    jsonb;
  v_r      jsonb;
  v_b      jsonb;
  v_acima  boolean := false;
  v_pontas_so boolean := false;
  v_dias   date[] := '{}';
  v_quem   text;
  v_pontas text;
  v_trocados text[] := '{}';
  v_bt     text;
  v_txt    text;
  v_msem   jsonb := '[]'::jsonb;
  e        jsonb;
  q        int;
begin
  if p_hoje is null then
    raise exception 'agenda_encaixe_do_novo: sem o dia de hoje' using errcode = '22004';
  end if;
  if p_dias is null or p_dias <= 0 then
    raise exception 'agenda_encaixe_do_novo: sem os dias do serviço' using errcode = '22023';
  end if;
  if p_dono is not null and p_dono not in ('abre_e_fecha', 'sempre', 'nunca') then
    raise exception 'agenda_encaixe_do_novo: presença do dono "%" não existe (abre_e_fecha, sempre ou nunca)', p_dono
      using errcode = '22023';
  end if;
  -- Quem vê: com login, só administrador e financeiro; sem login, o service_role (o assistente pelo WhatsApp).
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;

  v_g := public._agenda_grade_de_agora(p_hoje);
  v_ctx := v_g -> 'ctx';
  v_ini := (v_g ->> 'ini')::date;
  v_de := (v_g ->> 'de')::date;
  v_hor := (v_g ->> 'hor')::date;
  v_pes := array(select x::uuid from jsonb_array_elements_text(v_ctx -> 'pessoas') with ordinality t(x, o) order by o);
  v_nomes := array(select x from jsonb_array_elements_text(v_ctx -> 'nomes') with ordinality t(x, o) order by o);
  v_dono := coalesce((v_ctx ->> 'dono')::int, 0);
  v_padrao := coalesce((v_ctx ->> 'dono_tem_padrao')::boolean, false);

  -- Quem vai: o dono fica o turno dele; os outros pelo lugar na grade, por turno ("dia" vale nos dois).
  for e in select x from jsonb_array_elements(v_lista) with ordinality t(x, o) order by o loop
    if coalesce((e ->> 'eh_dono')::boolean, false) then
      v_dtm := v_dtm or coalesce(e ->> 'turnos', 'dia') in ('dia', 'manha');
      v_dtt := v_dtt or coalesce(e ->> 'turnos', 'dia') in ('dia', 'tarde');
      continue;
    end if;
    q := array_position(v_pes, nullif(e ->> 'payee_id', '')::uuid);
    if q is null then
      v_fora := v_fora || coalesce(e ->> 'nome', 'essa pessoa');
      continue;
    end if;
    if coalesce(e ->> 'turnos', 'dia') in ('dia', 'manha') and not (q = any (v_pm)) then v_pm := v_pm || q; end if;
    if coalesce(e ->> 'turnos', 'dia') in ('dia', 'tarde') and not (q = any (v_pt)) then v_pt := v_pt || q; end if;
  end loop;
  if cardinality(v_fora) > 0 then
    return jsonb_build_object('ok', true, 'cabe', false, 'motivo', 'sem_dias', 'sem_dias', to_jsonb(v_fora),
      'texto', format('não sei em que dias %s %s, então não consigo encaixar. É simulação: não marca nada.',
                      public._agenda_lista(v_fora, null), case when cardinality(v_fora) = 1 then 'vem' else 'vêm' end));
  end if;

  -- A presença do dono: a dita; sem ela, o turno dele quando está na lista; senão ele abre e fecha (o padrão da regra).
  if p_dono is not null then
    v_dtm := p_dono = 'sempre';
    v_dtt := v_dtm;
    v_abre := p_dono = 'abre_e_fecha';
  elsif not (v_dtm or v_dtt) then
    v_abre := true;
  end if;
  -- Quantos da equipe por turno: os ditos; sem ninguém dito, a equipe sugerida (o dono no turno é uma das pessoas).
  if jsonb_array_length(v_lista) = 0 then
    v_dm := greatest(cf.equipe_sugerida - case when v_dtm then 1 else 0 end, 0);
    v_dtd := greatest(cf.equipe_sugerida - case when v_dtt then 1 else 0 end, 0);
  else
    v_dm := cardinality(v_pm);
    v_dtd := cardinality(v_pt);
  end if;
  -- FASE 7: (7a correção, achado 5) sem gente dita e com a regra uma_pessoa do gestor (AG7-04), o serviço novo vai com
  -- equipe_padrao pessoas por turno, como o gestor o marcaria (a dupla só quando o dono diz); sem a regra, a de antes
  if jsonb_array_length(v_lista) = 0 and public._agenda_gestor_regra('uma_pessoa') then
    v_dm := greatest(cf.equipe_padrao - case when v_dtm then 1 else 0 end, 0);
    v_dtd := greatest(cf.equipe_padrao - case when v_dtt then 1 else 0 end, 0);
  end if;
  -- FASE 7: fim
  -- FASE 7g: (7g P4, §5.4) sem ninguém dito, as pessoas por turno que a OS pede (agenda_meios_da_os.por_turno.*.desejado: a dita, a da estimativa ou a regra
  -- uma_pessoa), como o motor as lê, no lugar da equipe sugerida
  if jsonb_array_length(v_lista) = 0 and v_7g_dm is not null and v_7g_dtd is not null then
    v_dm := greatest(v_7g_dm, 0);
    v_dtd := greatest(v_7g_dtd, 0);
  end if;
  -- FASE 7g: fim
  -- O dono o turno inteiro sem os dias dele em campo: o motor não marca (padrao_do_dono). Simula com ele só abrindo e
  -- fechando, e a frase diz por quê.
  if (v_dtm or v_dtt) and not v_padrao then
    v_pontas_so := true;
    v_dtm := false;
    v_dtt := false;
    v_abre := true;
  end if;
  v_abre := v_abre and v_dono > 0;
  -- Os meios-dias: dias × 2 com gente nos dois turnos; quem só vem num turno faz 1 por dia.
  v_passos := case when (v_dm > 0 or v_dtm) and (v_dtd > 0 or v_dtt) then ceil(p_dias * 2)::int
                   when v_dm > 0 or v_dtm or v_dtd > 0 or v_dtt then ceil(p_dias)::int
                   else 0 end;
  -- FASE 7g: (7g P4, §5.4) os meios-dias da OS (passos: o que o motor encaixa, agenda_meios_da_os.total menos o feito e o marcado) no lugar de dias × 2,
  -- quando há gente no serviço
  if v_passos > 0 and coalesce(v_7g_pas, 0) > 0 then
    v_passos := v_7g_pas;
  end if;
  -- FASE 7g: fim
  if v_passos = 0 then
    return jsonb_build_object('ok', true, 'cabe', false, 'motivo', 'sem_equipe', 'so_pontas', v_pontas_so,
      'texto', case when v_pontas_so
                    then 'com você o tempo todo não consigo encaixar: não sei em que dias você fica em campo, e sem você não fica ninguém da equipe no serviço. É simulação: não marca nada.'
                    else 'não fica ninguém da equipe no serviço: diga com quem. É simulação: não marca nada.' end);
  end if;

  -- A OS nova na fila do encaixe: compromisso (classe 2), a partir do 1º dia que a agenda ainda pode mudar, o índice depois
  -- das OS da grade (não é frente de nenhuma), sem bem fora, sem pátio, sem reserva.
  v_e := jsonb_build_object(
    'i', jsonb_array_length(coalesce(v_ctx -> 'oss', '[]'::jsonb)) + 1, 'os', null, 'numero', null,
    'classe', 2, 'ordem', 1, 'tipo_os', 'execucao', 'passos', v_passos,
    'abre', v_abre, 'fecha', v_abre, 'dt_m', v_dtm, 'dt_t', v_dtt, 'dm', v_dm, 'dtd', v_dtd,
    'pm', to_jsonb(v_pm), 'pt', to_jsonb(v_pt), 'fixa', 0,
    'est', v_de - v_ini + 1, 'est_cond', v_de - v_ini + 1, 'est_patio', v_de - v_ini + 1, 'min_h', (v_g ->> 'min_h')::int,
    'bem', '[]'::jsonb, 'patio_passos', 0, 'patio_bem', '[]'::jsonb,
    'tem_reserva', false, 'tem_fixada', false, 'evento_real', false, 'teto100', false, 'dono_impossivel', false);
  -- FASE 7g: (7g P4, §5.4) o 1º dia possível da OS (nao_antes_de: o est da prontidão, com a compra contada como se aprovasse hoje): o encaixe começa no maior
  -- entre ele e o 1º dia que a agenda ainda pode mudar, em est e est_cond, como o motor (agenda_propor: greatest(est da prontidão, o dia depois do congelado))
  if v_7g_nad is not null and v_7g_nad > v_de then
    v_e := v_e || jsonb_build_object('est', v_7g_nad - v_ini + 1, 'est_cond', v_7g_nad - v_ini + 1);
  end if;
  -- FASE 7g: fim
  v_par := jsonb_build_object('wip', cf.wip_max, 'imax', cf.interrupcoes_max, 'inicios', (v_ctx ->> 'nd')::int,
                              'semana', false, 'acima', false);
  v_r := public._agenda_encaixar(v_ctx, jsonb_build_array(v_e), v_par);
  v_b := (select b from jsonb_array_elements(coalesce(v_r -> 'colocadas', '[]'::jsonb)) b where b ->> 'tipo' = 'compromisso' limit 1);
  if v_b is null then
    v_r := public._agenda_encaixar(v_ctx, jsonb_build_array(v_e), v_par || jsonb_build_object('acima', true));
    v_b := (select b from jsonb_array_elements(coalesce(v_r -> 'colocadas', '[]'::jsonb)) b where b ->> 'tipo' = 'compromisso' limit 1);
    v_acima := v_b is not null;
  end if;

  if v_b is not null then
    -- os dias do bloco (as pontas do dono também), quem fica o turno (você primeiro, depois na ordem em que entra) e as pontas
    v_dias := array(select distinct v_ini + (h + 1) / 2 - 1 from unnest(public._agenda_ints(v_b -> 'h')) h order by 1);
    select public._agenda_lista(array_agg(case when z.p = v_dono then 'você' else v_nomes[z.p] end
                                          order by z.p = v_dono desc, z.h0, z.p), null)
      into v_quem
      from (select t.p, min(t.h) as h0
              from unnest(public._agenda_ints(v_b -> 'p'), public._agenda_ints(v_b -> 'h'), public._agenda_ints(v_b -> 'pr')) t(p, h, pr)
             where t.pr = 0 group by t.p) z;
    select case when bool_or(t.pr = 1) and bool_or(t.pr = 2) then 'você abre e fecha'
                when bool_or(t.pr = 1) then 'você abre'
                when bool_or(t.pr = 2) then 'você fecha' end
      into v_pontas
      from unnest(public._agenda_ints(v_b -> 'p'), public._agenda_ints(v_b -> 'h'), public._agenda_ints(v_b -> 'pr')) t(p, h, pr)
     where t.pr in (1, 2);
    -- os meios-dias de cada pessoa por semana (o turno inteiro): a conta que o livre de verdade mostra
    select coalesce(jsonb_agg(jsonb_build_object('payee_id', v_pes[z.p], 'seg', z.seg, 'meios', z.n) order by z.seg, z.p), '[]'::jsonb)
      into v_msem
      from (select t.p, (v_ini + (t.h + 1) / 2 - 1) - (extract(isodow from v_ini + (t.h + 1) / 2 - 1)::int - 1) as seg, count(*)::int as n
              from unnest(public._agenda_ints(v_b -> 'p'), public._agenda_ints(v_b -> 'h'), public._agenda_ints(v_b -> 'pr')) t(p, h, pr)
             where t.pr = 0 group by 1, 2) z;
    -- quem o dono disse e não ficou com lugar: o motor troca por outro diarista livre (a frase diz no lugar de quem)
    v_trocados := array(select v_nomes[d.q] from unnest(v_pm || v_pt) with ordinality d(q, o)
                         where not (d.q = any (public._agenda_ints(v_b -> 'p')))
                         group by d.q order by min(d.o));
    v_bt := public._agenda_dias_texto(v_dias)
            || case when (v_b ->> 'ini')::int % 2 = 0 then ' (começa à tarde)' else '' end
            || coalesce(', com ' || nullif(v_quem, ''), '')
            || coalesce(' (no lugar de ' || nullif(public._agenda_lista(v_trocados, null), '') || ')', '')
            || coalesce('; ' || v_pontas, '') || '.';
  end if;

  v_txt := case
    when v_b is null then format('não cabe até %s com a equipe de agora, nem acima da carga de sempre.', public._dia_curto(v_hor))
    when v_acima then format('na carga de sempre da equipe não cabe até %s; acima dela, cabe em %s', public._dia_curto(v_hor), v_bt)
    else 'pelo plano de agora, cabe em ' || v_bt end;
  if v_pontas_so then
    v_txt := 'com você o tempo todo não consigo encaixar: não sei em que dias você fica em campo. '
             || case when v_b is null then public._agenda_maiuscula(v_txt)
                     when v_abre then 'Com você só abrindo e fechando, ' || v_txt
                     else 'Sem você, ' || v_txt end;
  end if;
  v_txt := v_txt || ' É simulação: não marca nada.';

  return jsonb_build_object(
    'ok', true, 'cabe', v_b is not null, 'acima', v_acima, 'so_pontas', v_pontas_so,
    'motivo', case when v_b is null then 'sem_encaixe' end,
    'de', v_dias[1], 'ate', v_dias[cardinality(v_dias)], 'dias', to_jsonb(v_dias), 'pessoas', v_quem, 'pontas', v_pontas,
    'horizonte', v_hor, 'meios_por_semana', v_msem, 'texto', v_txt);
end;
$function$;

comment on function public._agenda_encaixe_simulado(jsonb, date) is
  'Agenda de Produção (Fase 7g, P4; §5.4, R9.4-6): o encaixe do motor (_agenda_encaixar, só leitura) sobre a grade de agora para um serviço descrito em p_entrada = {dias, gente, dono, passos, nao_antes_de, dm, dtd, rotulo} — o corpo de agenda_encaixe_do_novo com 3 trocas: os meios-dias de passos (sem ele, dias × 2), o 1º dia possível de nao_antes_de (sem ele, o 1º dia que a agenda ainda pode mudar) e as pessoas por turno de dm/dtd quando ninguém foi dito (sem eles, a equipe sugerida). Sem as chaves novas, a saída de agenda_encaixe_do_novo, byte a byte. Saída: {ok, cabe, acima, so_pontas, motivo, de, ate, dias, pessoas, pontas, horizonte, meios_por_semana, texto}. SECURITY DEFINER; com login, só admin/financeiro (42501); sem login, o service_role.';

-- ── 2. agenda_encaixe_do_novo (recriada) ─────────────────────────────────────────────────────────────
create or replace function public.agenda_encaixe_do_novo(p_dias numeric, p_gente jsonb default '[]'::jsonb,
                                                         p_dono text default null,
                                                         p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_uid    uuid := auth.uid();
  v_lista  jsonb := case when jsonb_typeof(coalesce(p_gente, '[]'::jsonb)) = 'array' then coalesce(p_gente, '[]'::jsonb)
                         else '[]'::jsonb end;
  v_g      jsonb;
  v_ctx    jsonb;
  v_ini    date;
  v_de     date;
  v_hor    date;
  v_pes    uuid[];
  v_nomes  text[];
  v_dono   int;
  v_padrao boolean;
  v_pm     int[] := '{}';
  v_pt     int[] := '{}';
  v_dtm    boolean := false;
  v_dtt    boolean := false;
  v_abre   boolean := false;
  v_fora   text[] := '{}';
  v_dm     int;
  v_dtd    int;
  v_passos int;
  v_e      jsonb;
  v_par    jsonb;
  v_r      jsonb;
  v_b      jsonb;
  v_acima  boolean := false;
  v_pontas_so boolean := false;
  v_dias   date[] := '{}';
  v_quem   text;
  v_pontas text;
  v_trocados text[] := '{}';
  v_bt     text;
  v_txt    text;
  v_msem   jsonb := '[]'::jsonb;
  e        jsonb;
  q        int;
begin
  if p_hoje is null then
    raise exception 'agenda_encaixe_do_novo: sem o dia de hoje' using errcode = '22004';
  end if;
  if p_dias is null or p_dias <= 0 then
    raise exception 'agenda_encaixe_do_novo: sem os dias do serviço' using errcode = '22023';
  end if;
  if p_dono is not null and p_dono not in ('abre_e_fecha', 'sempre', 'nunca') then
    raise exception 'agenda_encaixe_do_novo: presença do dono "%" não existe (abre_e_fecha, sempre ou nunca)', p_dono
      using errcode = '22023';
  end if;
  -- Quem vê: com login, só administrador e financeiro; sem login, o service_role (o assistente pelo WhatsApp).
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  -- FASE 7g: (7g P4, §5.4) a conta mora em _agenda_encaixe_simulado (o mesmo corpo, com a entrada num jsonb): depois das mesmas conferências de entrada e de
  -- quem vê, devolve o encaixe de um serviço novo (dias × 2, a gente e a presença ditas), a mesma saída de antes. O resto deste corpo é a cópia de antes (a
  -- origem, para o tirador) e não roda.
  return public._agenda_encaixe_simulado(jsonb_build_object('dias', p_dias, 'gente', p_gente, 'dono', p_dono), p_hoje);
  -- FASE 7g: fim

  v_g := public._agenda_grade_de_agora(p_hoje);
  v_ctx := v_g -> 'ctx';
  v_ini := (v_g ->> 'ini')::date;
  v_de := (v_g ->> 'de')::date;
  v_hor := (v_g ->> 'hor')::date;
  v_pes := array(select x::uuid from jsonb_array_elements_text(v_ctx -> 'pessoas') with ordinality t(x, o) order by o);
  v_nomes := array(select x from jsonb_array_elements_text(v_ctx -> 'nomes') with ordinality t(x, o) order by o);
  v_dono := coalesce((v_ctx ->> 'dono')::int, 0);
  v_padrao := coalesce((v_ctx ->> 'dono_tem_padrao')::boolean, false);

  -- Quem vai: o dono fica o turno dele; os outros pelo lugar na grade, por turno ("dia" vale nos dois).
  for e in select x from jsonb_array_elements(v_lista) with ordinality t(x, o) order by o loop
    if coalesce((e ->> 'eh_dono')::boolean, false) then
      v_dtm := v_dtm or coalesce(e ->> 'turnos', 'dia') in ('dia', 'manha');
      v_dtt := v_dtt or coalesce(e ->> 'turnos', 'dia') in ('dia', 'tarde');
      continue;
    end if;
    q := array_position(v_pes, nullif(e ->> 'payee_id', '')::uuid);
    if q is null then
      v_fora := v_fora || coalesce(e ->> 'nome', 'essa pessoa');
      continue;
    end if;
    if coalesce(e ->> 'turnos', 'dia') in ('dia', 'manha') and not (q = any (v_pm)) then v_pm := v_pm || q; end if;
    if coalesce(e ->> 'turnos', 'dia') in ('dia', 'tarde') and not (q = any (v_pt)) then v_pt := v_pt || q; end if;
  end loop;
  if cardinality(v_fora) > 0 then
    return jsonb_build_object('ok', true, 'cabe', false, 'motivo', 'sem_dias', 'sem_dias', to_jsonb(v_fora),
      'texto', format('não sei em que dias %s %s, então não consigo encaixar. É simulação: não marca nada.',
                      public._agenda_lista(v_fora, null), case when cardinality(v_fora) = 1 then 'vem' else 'vêm' end));
  end if;

  -- A presença do dono: a dita; sem ela, o turno dele quando está na lista; senão ele abre e fecha (o padrão da regra).
  if p_dono is not null then
    v_dtm := p_dono = 'sempre';
    v_dtt := v_dtm;
    v_abre := p_dono = 'abre_e_fecha';
  elsif not (v_dtm or v_dtt) then
    v_abre := true;
  end if;
  -- Quantos da equipe por turno: os ditos; sem ninguém dito, a equipe sugerida (o dono no turno é uma das pessoas).
  if jsonb_array_length(v_lista) = 0 then
    v_dm := greatest(cf.equipe_sugerida - case when v_dtm then 1 else 0 end, 0);
    v_dtd := greatest(cf.equipe_sugerida - case when v_dtt then 1 else 0 end, 0);
  else
    v_dm := cardinality(v_pm);
    v_dtd := cardinality(v_pt);
  end if;
  -- FASE 7: (7a correção, achado 5) sem gente dita e com a regra uma_pessoa do gestor (AG7-04), o serviço novo vai com
  -- equipe_padrao pessoas por turno, como o gestor o marcaria (a dupla só quando o dono diz); sem a regra, a de antes
  if jsonb_array_length(v_lista) = 0 and public._agenda_gestor_regra('uma_pessoa') then
    v_dm := greatest(cf.equipe_padrao - case when v_dtm then 1 else 0 end, 0);
    v_dtd := greatest(cf.equipe_padrao - case when v_dtt then 1 else 0 end, 0);
  end if;
  -- FASE 7: fim
  -- O dono o turno inteiro sem os dias dele em campo: o motor não marca (padrao_do_dono). Simula com ele só abrindo e
  -- fechando, e a frase diz por quê.
  if (v_dtm or v_dtt) and not v_padrao then
    v_pontas_so := true;
    v_dtm := false;
    v_dtt := false;
    v_abre := true;
  end if;
  v_abre := v_abre and v_dono > 0;
  -- Os meios-dias: dias × 2 com gente nos dois turnos; quem só vem num turno faz 1 por dia.
  v_passos := case when (v_dm > 0 or v_dtm) and (v_dtd > 0 or v_dtt) then ceil(p_dias * 2)::int
                   when v_dm > 0 or v_dtm or v_dtd > 0 or v_dtt then ceil(p_dias)::int
                   else 0 end;
  if v_passos = 0 then
    return jsonb_build_object('ok', true, 'cabe', false, 'motivo', 'sem_equipe', 'so_pontas', v_pontas_so,
      'texto', case when v_pontas_so
                    then 'com você o tempo todo não consigo encaixar: não sei em que dias você fica em campo, e sem você não fica ninguém da equipe no serviço. É simulação: não marca nada.'
                    else 'não fica ninguém da equipe no serviço: diga com quem. É simulação: não marca nada.' end);
  end if;

  -- A OS nova na fila do encaixe: compromisso (classe 2), a partir do 1º dia que a agenda ainda pode mudar, o índice depois
  -- das OS da grade (não é frente de nenhuma), sem bem fora, sem pátio, sem reserva.
  v_e := jsonb_build_object(
    'i', jsonb_array_length(coalesce(v_ctx -> 'oss', '[]'::jsonb)) + 1, 'os', null, 'numero', null,
    'classe', 2, 'ordem', 1, 'tipo_os', 'execucao', 'passos', v_passos,
    'abre', v_abre, 'fecha', v_abre, 'dt_m', v_dtm, 'dt_t', v_dtt, 'dm', v_dm, 'dtd', v_dtd,
    'pm', to_jsonb(v_pm), 'pt', to_jsonb(v_pt), 'fixa', 0,
    'est', v_de - v_ini + 1, 'est_cond', v_de - v_ini + 1, 'est_patio', v_de - v_ini + 1, 'min_h', (v_g ->> 'min_h')::int,
    'bem', '[]'::jsonb, 'patio_passos', 0, 'patio_bem', '[]'::jsonb,
    'tem_reserva', false, 'tem_fixada', false, 'evento_real', false, 'teto100', false, 'dono_impossivel', false);
  v_par := jsonb_build_object('wip', cf.wip_max, 'imax', cf.interrupcoes_max, 'inicios', (v_ctx ->> 'nd')::int,
                              'semana', false, 'acima', false);
  v_r := public._agenda_encaixar(v_ctx, jsonb_build_array(v_e), v_par);
  v_b := (select b from jsonb_array_elements(coalesce(v_r -> 'colocadas', '[]'::jsonb)) b where b ->> 'tipo' = 'compromisso' limit 1);
  if v_b is null then
    v_r := public._agenda_encaixar(v_ctx, jsonb_build_array(v_e), v_par || jsonb_build_object('acima', true));
    v_b := (select b from jsonb_array_elements(coalesce(v_r -> 'colocadas', '[]'::jsonb)) b where b ->> 'tipo' = 'compromisso' limit 1);
    v_acima := v_b is not null;
  end if;

  if v_b is not null then
    -- os dias do bloco (as pontas do dono também), quem fica o turno (você primeiro, depois na ordem em que entra) e as pontas
    v_dias := array(select distinct v_ini + (h + 1) / 2 - 1 from unnest(public._agenda_ints(v_b -> 'h')) h order by 1);
    select public._agenda_lista(array_agg(case when z.p = v_dono then 'você' else v_nomes[z.p] end
                                          order by z.p = v_dono desc, z.h0, z.p), null)
      into v_quem
      from (select t.p, min(t.h) as h0
              from unnest(public._agenda_ints(v_b -> 'p'), public._agenda_ints(v_b -> 'h'), public._agenda_ints(v_b -> 'pr')) t(p, h, pr)
             where t.pr = 0 group by t.p) z;
    select case when bool_or(t.pr = 1) and bool_or(t.pr = 2) then 'você abre e fecha'
                when bool_or(t.pr = 1) then 'você abre'
                when bool_or(t.pr = 2) then 'você fecha' end
      into v_pontas
      from unnest(public._agenda_ints(v_b -> 'p'), public._agenda_ints(v_b -> 'h'), public._agenda_ints(v_b -> 'pr')) t(p, h, pr)
     where t.pr in (1, 2);
    -- os meios-dias de cada pessoa por semana (o turno inteiro): a conta que o livre de verdade mostra
    select coalesce(jsonb_agg(jsonb_build_object('payee_id', v_pes[z.p], 'seg', z.seg, 'meios', z.n) order by z.seg, z.p), '[]'::jsonb)
      into v_msem
      from (select t.p, (v_ini + (t.h + 1) / 2 - 1) - (extract(isodow from v_ini + (t.h + 1) / 2 - 1)::int - 1) as seg, count(*)::int as n
              from unnest(public._agenda_ints(v_b -> 'p'), public._agenda_ints(v_b -> 'h'), public._agenda_ints(v_b -> 'pr')) t(p, h, pr)
             where t.pr = 0 group by 1, 2) z;
    -- quem o dono disse e não ficou com lugar: o motor troca por outro diarista livre (a frase diz no lugar de quem)
    v_trocados := array(select v_nomes[d.q] from unnest(v_pm || v_pt) with ordinality d(q, o)
                         where not (d.q = any (public._agenda_ints(v_b -> 'p')))
                         group by d.q order by min(d.o));
    v_bt := public._agenda_dias_texto(v_dias)
            || case when (v_b ->> 'ini')::int % 2 = 0 then ' (começa à tarde)' else '' end
            || coalesce(', com ' || nullif(v_quem, ''), '')
            || coalesce(' (no lugar de ' || nullif(public._agenda_lista(v_trocados, null), '') || ')', '')
            || coalesce('; ' || v_pontas, '') || '.';
  end if;

  v_txt := case
    when v_b is null then format('não cabe até %s com a equipe de agora, nem acima da carga de sempre.', public._dia_curto(v_hor))
    when v_acima then format('na carga de sempre da equipe não cabe até %s; acima dela, cabe em %s', public._dia_curto(v_hor), v_bt)
    else 'pelo plano de agora, cabe em ' || v_bt end;
  if v_pontas_so then
    v_txt := 'com você o tempo todo não consigo encaixar: não sei em que dias você fica em campo. '
             || case when v_b is null then public._agenda_maiuscula(v_txt)
                     when v_abre then 'Com você só abrindo e fechando, ' || v_txt
                     else 'Sem você, ' || v_txt end;
  end if;
  v_txt := v_txt || ' É simulação: não marca nada.';

  return jsonb_build_object(
    'ok', true, 'cabe', v_b is not null, 'acima', v_acima, 'so_pontas', v_pontas_so,
    'motivo', case when v_b is null then 'sem_encaixe' end,
    'de', v_dias[1], 'ate', v_dias[cardinality(v_dias)], 'dias', to_jsonb(v_dias), 'pessoas', v_quem, 'pontas', v_pontas,
    'horizonte', v_hor, 'meios_por_semana', v_msem, 'texto', v_txt);
end;
$function$;

comment on function public.agenda_encaixe_do_novo(numeric, jsonb, text, date) is
  'Agenda de Produção (correção de 29/10, P2): um serviço que ainda não existe ("2 dias, com o Roberto") no encaixe do motor (_agenda_encaixar, só leitura) sobre a grade de agora (_agenda_grade_de_agora: o marcado e o reservado ocupam), como uma OS nova entraria — compromisso (classe 2), a partir do 1º dia que a agenda ainda pode mudar, todos os inícios até o horizonte, o teto de compromisso (sem caber, acima dele, até 100%: acima = true). p_gente = a lista da agenda_simular [{payee_id, nome, eh_dono, turnos}]: o dono fica o turno dele, os outros por turno; sem ninguém, equipe_sugerida pessoas por turno. A presença do dono: p_dono (abre_e_fecha, sempre, nunca); senão o turno dele na lista; senão ele abre e fecha. O dono o turno inteiro sem os dias dele em campo o motor não marca: so_pontas = true, simula com ele só abrindo e fechando e a frase diz por quê. Meios-dias: dias × 2 (quem só vem num turno: 1 por dia). Pessoa fora da grade: motivo sem_dias. {ok, cabe, acima, so_pontas, motivo (sem_encaixe, sem_dias, sem_equipe), de, ate, dias, pessoas, pontas, horizonte, meios_por_semana[{payee_id, seg, meios}], texto ("pelo plano de agora, cabe em sex 13 e ter 17/11, com João e Roberto; você abre e fecha. É simulação: não marca nada.")}. Nada é gravado. STABLE, definer (as peças do motor são só do service_role); administrador e financeiro com login, ou o service_role. CORREÇÃO DA 7a (revisão da etapa; achado 5): sem gente dita e com a regra uma_pessoa do gestor, o serviço novo vai com equipe_padrao pessoas por turno (1), como o gestor marca; sem a regra, a de antes, byte a byte. FASE 7g (P4): a conta mora em _agenda_encaixe_simulado (o mesmo corpo, com a entrada num jsonb); depois das mesmas conferências de entrada e de quem vê, devolve _agenda_encaixe_simulado({dias, gente, dono}, p_hoje): a saída de antes, byte a byte, nos 3 modos.';

-- ── 3. A entrada do encaixe para uma OS ou ORÇ ───────────────────────────────────────────────────────
-- As mesmas fontes da agenda_propor (§4 "A grade e a fila", na 20261111100300): se a agenda_propor mudar de fonte, mudar aqui também (o L2 de
-- agenda_fase7g_livre.sql compara as duas).
--   passos        agenda_meios_da_os.total − os meios-dias cumpridos − os de compromisso que ela já tem de hoje em diante (o v_passos do motor)
--   dias          passos ÷ 2 (o encaixe exige os dias; com passos, eles não mudam a conta)
--   gente         as pessoas ditas por turno (agenda_meios_da_os.por_turno: manha e tarde; nas duas, o dia), na ordem do motor; você no turno quando está na
--                 equipe dita (presença "equipe")
--   dono          a presença do dono (abre_e_fecha, sempre, nunca), a de agenda_meios_da_os; com você na equipe dita, nula (vai pela gente)
--   dm, dtd       quantas pessoas por turno a OS pede (agenda_meios_da_os.por_turno.*.desejado: a dita, a da estimativa ou a regra uma_pessoa)
--   nao_antes_de  o 1º dia possível pela prontidão (os_prontidao.est, senão est_sem_material, senão hoje): o bem livre, o "não antes de" e a compra contada como
--                 se aprovasse hoje (o último crítico chega + folga_material_du), a mesma data com que o motor começa a OS
--   rotulo        "<número> (<cliente>)"
-- Sem prontidão (OS que não existe), nula. Sem base de duração (total nulo), passos e dias nulos: quem chama diz que não dá para estimar.
-- O que o motor faz e esta entrada não leva (R9.N): a dupla por meio-dia da 7b (dk), o líder e as exigências da 7c, o local e a viagem da 7d, a urgência e o
-- puxar da 7e, o prazo do sábado. O 1º dia é o mesmo quando nada disso pesa; com algum deles ligado, o encaixe é a conta de um serviço novo, não a do motor.
create or replace function public._agenda_entrada_simulada_da_os(p_os uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid   uuid := auth.uid();
  v_p     jsonb;
  v_m     jsonb;
  v_fut   int;
  v_pas   int;
  v_dt_m  boolean;
  v_dt_t  boolean;
  v_gente jsonb;
begin
  if p_os is null or p_hoje is null then
    raise exception '_agenda_entrada_simulada_da_os: sem a OS ou o dia de hoje' using errcode = '22004';
  end if;
  -- Quem vê: com login, só administrador e financeiro; sem login, o service_role (o assistente pelo WhatsApp), como a agenda_encaixe_do_novo.
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  v_p := public.os_prontidao(p_os, p_hoje);
  if not coalesce((v_p ->> 'ok')::boolean, false) then
    return null;
  end if;
  v_m := public.agenda_meios_da_os(p_os, p_hoje);
  -- o que ela já tem de compromisso de hoje em diante, sem resultado: o motor não encaixa de novo (o v_k.fut da agenda_propor)
  select count(distinct (a.dia, a.turno))::int into v_fut
    from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje and a.resultado is null;
  v_pas := case when (v_m ->> 'total') is null then null
                else ceil(greatest((v_m ->> 'total')::numeric - coalesce((v_m ->> 'cumpridos')::numeric, 0) - coalesce(v_fut, 0), 0))::int end;
  v_dt_m := coalesce((v_m #>> '{dono_turno,manha}')::boolean, false);
  v_dt_t := coalesce((v_m #>> '{dono_turno,tarde}')::boolean, false);
  -- a gente dita, na ordem do motor: a lista da manhã (quem vem nos 2 turnos vai como "dia"), depois quem só vem à tarde, na ordem da lista da tarde
  select coalesce(jsonb_agg(z.e order by z.k, z.o), '[]'::jsonb) into v_gente
    from (select jsonb_build_object('payee_id', m.e ->> 'payee_id', 'nome', m.e ->> 'nome', 'eh_dono', false,
                                    'turnos', case when exists (select 1 from jsonb_array_elements(coalesce(v_m #> '{por_turno,tarde,pessoas}', '[]'::jsonb)) t
                                                                 where t ->> 'payee_id' = m.e ->> 'payee_id') then 'dia' else 'manha' end) as e,
                 1 as k, m.o
            from jsonb_array_elements(coalesce(v_m #> '{por_turno,manha,pessoas}', '[]'::jsonb)) with ordinality m(e, o)
          union all
          select jsonb_build_object('payee_id', t.e ->> 'payee_id', 'nome', t.e ->> 'nome', 'eh_dono', false, 'turnos', 'tarde'), 2, t.o
            from jsonb_array_elements(coalesce(v_m #> '{por_turno,tarde,pessoas}', '[]'::jsonb)) with ordinality t(e, o)
           where not exists (select 1 from jsonb_array_elements(coalesce(v_m #> '{por_turno,manha,pessoas}', '[]'::jsonb)) m
                              where m ->> 'payee_id' = t.e ->> 'payee_id')) z;
  -- você na equipe dita: o turno inteiro nos seus turnos (a presença "equipe" de agenda_meios_da_os)
  if v_m ->> 'presenca' = 'equipe' and (v_dt_m or v_dt_t) then
    v_gente := v_gente || jsonb_build_array(jsonb_build_object('eh_dono', true, 'nome', 'você',
                                                               'turnos', case when v_dt_m and v_dt_t then 'dia' when v_dt_m then 'manha' else 'tarde' end));
  end if;
  return jsonb_build_object(
    'os', p_os, 'rotulo', format('%s (%s)', v_p ->> 'numero', v_p ->> 'cliente_curto'),
    'passos', v_pas, 'dias', case when v_pas > 0 then v_pas::numeric / 2 end,
    'gente', v_gente,
    'dono', case when v_m ->> 'presenca' in ('abre_e_fecha', 'sempre', 'nunca') then v_m ->> 'presenca' end,
    'dm', (v_m #>> '{por_turno,manha,desejado}')::int, 'dtd', (v_m #>> '{por_turno,tarde,desejado}')::int,
    'nao_antes_de', coalesce((v_p ->> 'est')::date, (v_p ->> 'est_sem_material')::date, p_hoje));
end;
$function$;

comment on function public._agenda_entrada_simulada_da_os(uuid, date) is
  'Agenda de Produção (Fase 7g, P4; §5.4, R9.5-28): a entrada de _agenda_encaixe_simulado para uma OS ou ORÇ, montada como a agenda_propor monta a da classe 2 — as mesmas fontes (§4 "A grade e a fila"; se a agenda_propor mudar de fonte, mudar aqui também): {os, rotulo, passos (agenda_meios_da_os.total − cumpridos − o compromisso que ela já tem), dias, gente (as pessoas ditas por turno; você quando está na equipe dita), dono (a presença: abre_e_fecha, sempre, nunca), dm, dtd (as pessoas por turno que a OS pede), nao_antes_de (os_prontidao.est: o bem, o "não antes de" e a compra contada como se aprovasse hoje)}. Nula para OS que não existe; passos e dias nulos sem base de duração. Não leva a dupla da 7b, o líder da 7c, o local da 7d nem a urgência da 7e. SECURITY DEFINER; com login, só admin/financeiro (42501); sem login, o service_role.';

-- ── 4. agenda_ctp (recriada) ─────────────────────────────────────────────────────────────────────────
create or replace function public.agenda_ctp(p_so_id uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config := public._agenda_cfg();
  v_pn     jsonb;
  v_p      jsonb;
  v_d      jsonb;
  v_n      int;
  v_e      int;
  v_maxd   date;
  v_imat   date;
  v_ot     date;
  v_re     date;
  v_dre    numeric;
  v_dur    text;
  v_falta  text;
  v_fila   text;
  v_cli    text;
  v_cond   boolean;
  l1 text; l2 text;
  -- FASE 7g: (7g P4, §5.4, §6.3) o início pelo encaixe do motor (com modo_explicar fora de desligado)
  c_7g_fim  constant text := ' É simulação: não marca nada.';
  v_7g_l1   text;
  v_7g_ent  jsonb;
  v_7g_s    jsonb;
  v_7g_fr   text;
  v_7g_cli  text;
  v_7g_de   date;
  v_7g_txt  text;
  -- FASE 7g: fim
begin
  if p_hoje is null then
    raise exception 'agenda_ctp: sem o dia de hoje' using errcode = '22004';
  end if;
  v_p := public.os_prontidao(p_so_id, p_hoje);
  if not coalesce((v_p ->> 'ok')::boolean, false) then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;
  if (v_p ->> 'na_carteira')::boolean then
    return jsonb_build_object('ok', true,
      'texto', format('%s (%s) já está %s: %s.', v_p ->> 'numero', v_p ->> 'cliente_curto',
                      case when (v_p ->> 'eh_orcamento')::boolean then 'aprovado' else 'aprovada' end, v_p ->> 'estado_texto'),
      'dados', jsonb_build_object('numero', v_p ->> 'numero', 'na_carteira', true, 'estado', v_p ->> 'estado'));
  end if;
  v_pn := public._agenda_painel(p_hoje);
  v_d := v_p -> 'duracao';

  -- A duração: o que o dono disse, ou a faixa pelo valor.
  v_dur := case when coalesce((v_d ->> 'sem_base')::boolean, false) then 'sem base para estimar os dias'
                else v_d ->> 'texto' end;
  v_dre := coalesce((v_d ->> 'dias_realista')::numeric, (v_d ->> 'dias')::numeric);

  -- O que falta comprar (críticos fora da mão): sem fornecedor = "de quem?"; com classe, "se comprar hoje, chegam …".
  select count(*) filter (where e ->> 'nivel' <> 'A'),
         count(*) filter (where e ->> 'nivel' <> 'A' and (e ->> 'sem_data')::boolean),
         max((e ->> 'data')::date) filter (where e ->> 'nivel' <> 'A')
    into v_n, v_e, v_maxd
    from jsonb_array_elements(v_p #> '{material,itens}') e where (e ->> 'critico')::boolean;
  v_falta := case
    when v_n = 0 and jsonb_array_length(v_p #> '{material,itens}') = 0 then 'o orçamento não tem peça'
    when v_n = 0 then 'o material está na mão'
    when v_e > 0 then public._agenda_plural(v_n, 'item', 'itens') || ' a comprar (de quem?)'
    else public._agenda_plural(v_n, 'item', 'itens') || ' a comprar (se comprar hoje, '
         || case when v_n = 1 then 'chega' else 'chegam' end || ' por volta de ' || public._dia_curto(v_maxd) || ')' end;
  v_cond := v_n > 0;
  if v_n > 0 and v_e = 0 and v_maxd is not null then
    v_imat := public.agenda_somar_du(v_maxd, c.folga_material_du);
  end if;

  l1 := format('%s (%s), se o cliente aprovar hoje: %s e %s.', v_p ->> 'numero', v_p ->> 'cliente_curto', v_dur, v_falta);
  -- FASE 7g: (7g P4) a frase da duração e do material (fica), antes da fila
  v_7g_l1 := l1;
  -- FASE 7g: fim

  if v_pn -> 'livre' is null or jsonb_typeof(v_pn -> 'livre') = 'null' then
    if (v_pn #>> '{backlog,n}')::int = 0 then
      v_ot := (v_pn ->> 'inicio_furando')::date; v_re := v_ot;
    end if;
  else
    v_ot := (v_pn #>> '{livre,ot}')::date; v_re := (v_pn #>> '{livre,re}')::date;
  end if;

  if v_ot is null then
    l1 := l1 || ' Pela fila: não sei o ritmo da equipe (não há diárias lançadas para medir).';
    l2 := 'É projeção: não reserva nada.';
  else
    v_ot := greatest(v_ot, v_imat); v_re := greatest(v_re, v_imat);
    v_fila := case when v_ot = v_re then 'começa por volta de ' || public._dia_curto(v_ot)
                   else format('começa entre %s e %s', public._dia_curto(v_ot), public._dia_curto(v_re)) end
              || case when (v_pn #>> '{cap,conta_dono}')::boolean then '' else ' (sem contar você)' end
              || case when v_n > 0 and v_e > 0 then ', e só depois que as peças chegarem' else '' end;
    l1 := l1 || ' Pela fila de hoje, ' || v_fila || '.';
    -- A frase ao cliente: em faixa ou condicional enquanto o material não está na mão (d09).
    if coalesce((v_d ->> 'sem_base')::boolean, false) then
      v_cli := 'Para o cliente, ainda não: o orçamento não dá base para estimar os dias.';
    else
      v_cli := format('Para o cliente: "a partir de %s, %s de serviço%s".', to_char(v_ot, 'DD/MM'),
                      case when v_dre <= 0.5 then 'meio dia'
                           when ceil(v_dre) = 1 then '1 dia'
                           else format('uns %s dias', ceil(v_dre)::int) end,
                      case when v_cond then '; confirmo a data quando as peças chegarem' else '' end);
    end if;
    l2 := v_cli || ' É projeção: não reserva nada.';
  end if;

  -- FASE 7g: (7g P4, §5.4, §6.3, R9.4-6, AG7-16, AG7-32) com modo_explicar fora de desligado, o "se aprovar hoje" pelo encaixe do motor sobre o plano de agora
  -- (_agenda_encaixe_simulado com a entrada da OS de _agenda_entrada_simulada_da_os: as mesmas fontes da agenda_propor), no lugar da fila de hoje. A duração e o
  -- material ficam (a frase de cima). A frase ao cliente diz a semana em que começa e os dias de serviço, nunca o dia em que fica pronto (AG7-32), e vai ao dono
  -- (nada sai ao cliente); "confirmo a data quando as peças chegarem" enquanto houver compra a fazer (AG7-16). Sem base de duração, pede os dias. Ligado: esse
  -- texto, inicio = o 1º dia do encaixe e dados.encaixe. Em sombra: a resposta de antes, byte a byte, e dados.teste = {de, ate, texto} (o que diria ligado).
  -- Desligado: nada disso é chamado. A falha da simulação não derruba a leitura (fora a porta, em ligado): diz que não conseguiu simular.
  if c.modo_explicar <> 'desligado' then
    begin
      v_7g_ent := public._agenda_entrada_simulada_da_os(p_so_id, p_hoje);
      if coalesce((v_d ->> 'sem_base')::boolean, false) or coalesce((v_7g_ent ->> 'passos')::int, 0) <= 0 then
        v_7g_fr := 'Pelo plano de agora: me diga quantos dias, que eu digo o 1º dia que cabe.';
        v_7g_cli := 'Para o cliente, ainda não: o orçamento não dá base para estimar os dias.';
      else
        v_7g_s := public._agenda_encaixe_simulado(v_7g_ent, p_hoje);
        v_7g_fr := v_7g_s ->> 'texto';
        v_7g_fr := public._agenda_maiuscula(case when right(v_7g_fr, char_length(c_7g_fim)) = c_7g_fim
                                                 then left(v_7g_fr, char_length(v_7g_fr) - char_length(c_7g_fim)) else v_7g_fr end)
                   || case when v_n > 0 and v_e > 0 and coalesce((v_7g_s ->> 'cabe')::boolean, false)
                           then ' Isso se as peças chegarem antes: falta saber de quem comprar.' else '' end;
        v_7g_de := (v_7g_s ->> 'de')::date;
        v_7g_cli := case when v_7g_de is null then 'Para o cliente, ainda não: pelo plano de agora não tenho a semana.'
                         else format('Para o cliente: "semana de %s, %s de serviço%s".',
                                     to_char(v_7g_de - (extract(isodow from v_7g_de)::int - 1), 'DD/MM'),
                                     case when coalesce(v_dre, (v_7g_ent ->> 'dias')::numeric) <= 0.5 then 'meio dia'
                                          when ceil(coalesce(v_dre, (v_7g_ent ->> 'dias')::numeric)) = 1 then '1 dia'
                                          else format('uns %s dias', ceil(coalesce(v_dre, (v_7g_ent ->> 'dias')::numeric))::int) end,
                                     case when v_cond then '; confirmo a data quando as peças chegarem' else '' end) end;
      end if;
    exception when others then
      if c.modo_explicar = 'ligado' and sqlstate = '42501' then
        raise;
      end if;
      v_7g_s := jsonb_build_object('erro', sqlstate);
      v_7g_de := null;
      v_7g_fr := 'Pelo plano de agora: não consegui simular agora.';
      v_7g_cli := 'Para o cliente, ainda não: não consegui simular agora.';
    end;
    v_7g_txt := public._agenda_juntar(array[v_7g_l1 || ' ' || v_7g_fr, v_7g_cli || c_7g_fim], (v_pn ->> 'texto_max')::int);
    if c.modo_explicar = 'ligado' then
      return jsonb_build_object('ok', true, 'texto', v_7g_txt,
        'dados', jsonb_build_object('numero', v_p ->> 'numero', 'duracao', v_d, 'faltam', v_n, 'sem_fornecedor', v_e,
                                    'inicio', jsonb_build_object('de', v_7g_de, 'ate', v_7g_de), 'condicional', v_cond, 'encaixe', v_7g_s - 'texto'));
    end if;
    -- em sombra: o return de baixo (a resposta de antes), com dados.teste
    return jsonb_set(jsonb_build_object('ok', true, 'texto', public._agenda_juntar(array[l1, l2], (v_pn ->> 'texto_max')::int),
      'dados', jsonb_build_object('numero', v_p ->> 'numero', 'duracao', v_d, 'faltam', v_n, 'sem_fornecedor', v_e,
                                  'inicio', jsonb_build_object('de', v_ot, 'ate', v_re), 'condicional', v_cond)),
      '{dados,teste}', jsonb_build_object('de', v_7g_s -> 'de', 'ate', v_7g_s -> 'ate', 'texto', v_7g_txt));
  end if;
  -- FASE 7g: fim
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(array[l1, l2], (v_pn ->> 'texto_max')::int),
    'dados', jsonb_build_object('numero', v_p ->> 'numero', 'duracao', v_d, 'faltam', v_n, 'sem_fornecedor', v_e,
                                'inicio', jsonb_build_object('de', v_ot, 'ate', v_re), 'condicional', v_cond));
end;
$function$;

comment on function public.agenda_ctp(uuid, date) is
  'Agenda de Produção (Fase 1, P4): "se o cliente aprovar hoje, quando dá?" — a duração (do dono ou pelo valor), o que falta comprar ("de quem?" ou "se comprar hoje, chegam …"), o início pela fila de hoje (a faixa do livre de verdade) e não antes do material (chegada + folga_material_du) quando há classe, e a frase pronta ao cliente, condicional enquanto o material não está na mão (d09). OS já aprovada: diz o estado. "É projeção: não reserva nada." FASE 7g (P4): com modo_explicar ligado, depois da duração e do material (que ficam), o início pelo encaixe do motor sobre o plano de agora (_agenda_encaixe_simulado com _agenda_entrada_simulada_da_os: as mesmas fontes da agenda_propor) no lugar da fila de hoje, e a frase ao cliente com a semana e os dias de serviço, sem o dia em que fica pronto (AG7-32; vai ao dono, nada sai ao cliente); "É simulação: não marca nada."; dados.inicio = o 1º dia do encaixe e dados.encaixe. Em sombra: a resposta de antes e dados.teste = {de, ate, texto}. Desligado: a de antes, byte a byte.';

-- ── 5. agenda_livre_de_verdade (recriada) ────────────────────────────────────────────────────────────
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
  -- FASE 7b: (correção da revisão da 7b, achados 15 e 25) a linha de quem chamar fora do corte
  v_7bc_liv text;
  -- FASE 7b: fim
  -- FASE 7g: (7g P4, §5.4, §6.3, R9.7) as livre_semanas semanas, com os totais da equipe e o texto do §6.3 (com modo_explicar fora de desligado)
  v_7g_sem  jsonb := '[]'::jsonb;
  v_7g_pes  jsonb;
  v_7g_k    int;
  v_7g_seg  date;
  v_7g_w    int;
  v_7g_d0   date;
  v_7g_d1   date;
  v_7g_ds   date;
  v_7g_rot  text;
  v_7g_rest int;
  v_7g_pode int;
  v_7g_fg   int;
  v_7g_uc   int;
  v_7g_ur   int;
  v_7g_liv  int;
  v_7g_voce int;
  v_7g_lis  text;
  v_7g_tp   int := 0;
  v_7g_tf   int := 0;
  v_7g_pct  int;
  v_7g_n    int;
  -- FASE 7g: fim
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
  -- FASE 7g: (7g P4, §5.4, §6.3, R9.7) com modo_explicar fora de desligado: livre_semanas semanas (no lugar das 3 de cima), com a MESMA conta de cada pessoa (o
  -- laço de cima, linha a linha, com as variáveis v_7g_*: as 3 primeiras semanas dão os mesmos meios-dias, o L1 de agenda_fase7g_livre.sql prova) e, por
  -- semana, totais = {pode Σ teto100, folga, marcado Σ uso_c, reservado Σ uso_r, livre Σ meios} da equipe sem você; a folga pela regra de agenda_como_pensei
  -- (R9.7: com a chave teto_equipe na grade, Σ teto100 − teto_equipe da semana; sem ela, com o freio, Σ (teto100 − teto80)); o texto da semana no formato do
  -- §6.3 ("• Semana de 09 a 13/11: a equipe pode 4 dias; nada marcado; reservado 1 dia; livre 2 dias e meio (Roberto 1 dia e meio, João 1 dia)."). Ligado:
  -- semanas passa a ser esta. Sombra: só em dados.teste (no fim). O que ocupa a equipe segue até o sábado da 3ª semana (v_ate, a conta de antes).
  if cf.modo_explicar <> 'desligado' then
    for v_7g_k in 0 .. cf.livre_semanas - 1 loop
      v_7g_seg := v_seg1 + 7 * v_7g_k;
      v_7g_w := (v_7g_seg - v_ini) / 7 + 1;
      exit when v_7g_w > v_nw;
      select min(g::date) filter (where g::date >= v_de), max(g::date) filter (where g::date >= v_de), min(g::date)
        into v_7g_d0, v_7g_d1, v_7g_ds
        from generate_series(v_7g_seg, v_7g_seg + 5, interval '1 day') g
       where public.agenda_dia_util(g::date);
      continue when v_7g_d0 is null;
      select coalesce(jsonb_agg(jsonb_build_object(
               'payee_id', v_pes[s.q], 'nome', case when s.q = v_dono then 'você' else v_nomes[s.q] end, 'eh_dono', s.q = v_dono,
               'meios', s.meios, 'celulas', s.cels, 'teto', s.t80, 'compromisso', s.uc, 'reserva', s.ur)
               order by s.meios desc, s.q), '[]'::jsonb)
        into v_7g_pes
        from (select z.q, z.cels, z.t80, z.uc, z.ur, greatest(0, least(z.t80 - z.uc, z.t100 - z.uc - z.ur, z.cels)) as meios
                from (select q,
                             v_t80[(q - 1) * v_nw + v_7g_w] as t80, v_t100[(q - 1) * v_nw + v_7g_w] as t100,
                             v_uc[(q - 1) * v_nw + v_7g_w] as uc, v_ur[(q - 1) * v_nw + v_7g_w] as ur,
                             (select count(*)::int from generate_series(1, v_nh) h
                               where v_sem[(h + 1) / 2] = v_7g_w and v_util[(h + 1) / 2] and h >= v_minh
                                 and v_cap[(q - 1) * v_nh + h] = 1 and v_ocup[(q - 1) * v_nh + h] = 0) as cels
                        from generate_series(1, v_np) q
                       where q <> v_dono or v_padrao) z) s;
      if v_f77_teq then
        v_f77_te := coalesce(v_f77_te, public._agenda_ints(v_ctx -> 'teto_equipe'));
        v_7g_rest := case when v_7g_w <= coalesce(cardinality(v_f77_te), 0)
                           then greatest(0, v_f77_te[v_7g_w] - (select coalesce(sum(v_uc[(q - 1) * v_nw + v_7g_w]), 0)::int
                                                                from generate_series(1, v_np) q where q <> v_dono)) end;
        select coalesce(jsonb_agg(case when v_7g_rest is null then p.e
                                       else p.e || jsonb_build_object('meios', greatest(0, least(p.acum, v_7g_rest)
                                                                                         - least(p.acum - (p.e ->> 'meios')::int, v_7g_rest))) end
                                  order by p.o), '[]'::jsonb)
          into v_7g_pes
          from (select t.e, t.o, sum((t.e ->> 'meios')::int) over (order by t.o) as acum
                  from jsonb_array_elements(v_7g_pes) with ordinality t(e, o)
                 where not coalesce((t.e ->> 'eh_dono')::boolean, false)) p;
      end if;
      -- os totais da equipe (sem você) nesta semana
      select coalesce(sum(z.t100), 0)::int, coalesce(sum(greatest(z.t100 - z.t80, 0)), 0)::int, coalesce(sum(z.uc), 0)::int, coalesce(sum(z.ur), 0)::int
        into v_7g_pode, v_7g_fg, v_7g_uc, v_7g_ur
        from (select coalesce(v_t100[(q - 1) * v_nw + v_7g_w], 0) as t100, coalesce(v_t80[(q - 1) * v_nw + v_7g_w], 0) as t80,
                     coalesce(v_uc[(q - 1) * v_nw + v_7g_w], 0) as uc, coalesce(v_ur[(q - 1) * v_nw + v_7g_w], 0) as ur
                from generate_series(1, v_np) q where q <> v_dono) z;
      if v_ctx ? 'teto_equipe' then
        v_7g_fg := greatest(v_7g_pode - coalesce((v_ctx -> 'teto_equipe' ->> (v_7g_w - 1))::int, 0), 0);
      end if;
      select coalesce(sum((e ->> 'meios')::int) filter (where not coalesce((e ->> 'eh_dono')::boolean, false)), 0)::int,
             sum((e ->> 'meios')::int) filter (where coalesce((e ->> 'eh_dono')::boolean, false))::int,
             case when count(*) filter (where not coalesce((e ->> 'eh_dono')::boolean, false)) > 1
                  then array_to_string(array_agg(format('%s %s', e ->> 'nome', public._agenda_meios_texto((e ->> 'meios')::int)) order by o)
                                         filter (where not coalesce((e ->> 'eh_dono')::boolean, false)), ', ') end
        into v_7g_liv, v_7g_voce, v_7g_lis
        from jsonb_array_elements(v_7g_pes) with ordinality t(e, o);
      v_7g_tp := v_7g_tp + v_7g_pode;
      v_7g_tf := v_7g_tf + v_7g_fg;
      v_7g_rot := case when v_7g_d0 = v_7g_ds then public._agenda_titulo_da_semana(v_7g_seg)
                       when v_7g_d0 = v_7g_d1 then public._agenda_maiuscula(public._dia_curto(v_7g_d0))
                       else format('De %s a %s', case when to_char(v_7g_d0, 'MM') = to_char(v_7g_d1, 'MM') then public._agenda_dia_sem_mes(v_7g_d0)
                                                      else public._dia_curto(v_7g_d0) end, public._dia_curto(v_7g_d1)) end;
      v_7g_sem := v_7g_sem || jsonb_build_object('seg', v_7g_seg, 'de', v_7g_d0, 'ate', v_7g_d1, 'rotulo', v_7g_rot, 'pessoas', v_7g_pes,
        'totais', jsonb_build_object('pode', v_7g_pode, 'folga', v_7g_fg, 'marcado', v_7g_uc, 'reservado', v_7g_ur, 'livre', v_7g_liv),
        'texto', '• ' || v_7g_rot || ': '
                 || case when v_7g_pode = 0 then 'ninguém da equipe tem os dias na agenda'
                         else case when jsonb_array_length(v_7g_sem) = 0 then 'a equipe pode ' else 'pode ' end || public._agenda_meios_texto(v_7g_pode)
                              || '; ' || case when v_7g_uc = 0 then 'nada marcado' else 'marcado ' || public._agenda_meios_texto(v_7g_uc) end
                              || case when v_7g_ur > 0 then '; reservado ' || public._agenda_meios_texto(v_7g_ur) else '' end
                              || '; ' || case when v_7g_liv = 0 then 'ninguém livre'
                                              else 'livre ' || public._agenda_meios_texto(v_7g_liv) || coalesce(' (' || v_7g_lis || ')', '') end end
                 || case when v_7g_voce > 0 then '; você ' || public._agenda_meios_texto(v_7g_voce) else '' end || '.');
    end loop;
    v_7g_pct := case when v_7g_tp > 0 then round(100 * v_7g_tf::numeric / v_7g_tp)::int end;
    if cf.modo_explicar = 'ligado' then
      v_semanas := v_7g_sem;
    end if;
  end if;
  -- FASE 7g: fim

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
  -- FASE 7g: (7g P4, §6.3) ligado: o título do §6.3 e, logo depois das semanas, a folga fora da conta (o número do dia: Σ folga ÷ Σ pode das semanas, R9.7)
  if cf.modo_explicar = 'ligado' then
    v_lin[1] := 'Livre de verdade (pelo plano de agora):';
    if v_7g_pct > 0 then
      v_lin := v_lin || format('Fora da conta: a folga de %s%% para imprevisto.', v_7g_pct);
    end if;
  end if;
  -- FASE 7g: fim
  -- FASE 7: (7a correção, achado 23) com a regra teto_equipe, o dono com os dias em campo também fica fora da conta de técnico
  if v_dono > 0 and v_padrao and v_f77_teq then
    v_lin := v_lin || 'Você não entra na conta: em campo você acompanha, abre e fecha (o diagnóstico é com você).'::text;
  end if;
  -- FASE 7: fim
  if v_dono > 0 and not v_padrao then
    v_lin := v_lin || 'Você fica de fora da conta: não sei em que dias você fica em campo (é só me dizer, por exemplo, "fico em campo de segunda a sexta").'::text;
  end if;
  -- FASE 7g: (7g P4, §6.3) até aqui, as linhas do §6.3: o título, as semanas, a folga fora da conta e as notas de você
  v_7g_n := cardinality(v_lin);
  -- FASE 7g: fim
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
  -- FASE 7b: (correção da revisão da 7b, achados 15 e 25) a linha de quem chamar (a última) não entra no corte do texto_max: o corte é
  -- do fim, e era ela que sumia ("(e mais 1 linha)"), também com o prazo que só fecha com um ajudante. O resto do *livre* continua com
  -- o texto_max inteiro, e ela vem depois.
  if nullif(btrim(coalesce(v_7b_liv, '')), '') is not null and cardinality(v_lin) > 0 and v_lin[cardinality(v_lin)] = v_7b_liv then
    v_lin := v_lin[1 : cardinality(v_lin) - 1];
    v_7bc_liv := v_7b_liv;
  end if;
  -- FASE 7b: fim
  -- FASE 7g: (7g P4, §6.3) ligado: o texto do §6.3 — as linhas de cima e, no fim, como perguntar de um serviço novo (a última linha de antes; a de quem chamar
  -- já saiu para depois do corte). O que ocupa a equipe e o que não ocupa ninguém saem do texto (as semanas já dizem o marcado e o reservado; com 4 semanas,
  -- o texto passava do texto_max e cortava o fim) e ficam nos dados (ocupa, nao_ocupam).
  if cf.modo_explicar = 'ligado' then
    v_lin := v_lin[1:v_7g_n] || v_lin[cardinality(v_lin)];
  end if;
  -- FASE 7g: fim
  v_txt := public._agenda_juntar(v_lin, cf.texto_max);
  -- FASE 7b: (correção da revisão da 7b, achados 15 e 25) e entra depois do corte, sempre
  if v_7bc_liv is not null then
    v_txt := v_txt || E'\n' || v_7bc_liv;
  end if;
  -- FASE 7b: fim
  v_linha := 'Livre de verdade: '
             || coalesce(nullif(array_to_string(v_curta, '; '), ''), 'não tenho os dias da equipe nas próximas semanas') || '.';

  -- FASE 7g: (7g P4) em sombra: o return de baixo (a resposta de antes, byte a byte) e as semanas novas só em dados.teste
  if cf.modo_explicar = 'sombra' then
    return jsonb_build_object(
      'fonte', 'simulacao', 'base', 'plano', 'de', v_de, 'ate', v_ate, 'semanas', v_semanas,
      'voce_fora', v_dono > 0 and not v_padrao, 'ocupa', v_ocupa,
      'nao_ocupam', jsonb_build_object(
        'travados', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb) from jsonb_array_elements(v_trav) with ordinality t(e, o)),
        'prontos', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb) from jsonb_array_elements(v_pront) with ordinality t(e, o)),
        'andamento', (select coalesce(jsonb_agg(e #>> '{o,numero}' order by o), '[]'::jsonb) from jsonb_array_elements(v_andam) with ordinality t(e, o)),
        'parados', v_parad, 'em_espera', v_esp),
      'texto', v_linha, 'texto_completo', v_txt,
      'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000))
      || jsonb_build_object('dados', jsonb_build_object('teste', jsonb_build_object('semanas', v_7g_sem)));
  end if;
  -- FASE 7g: fim
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
  'Agenda de Produção (Fase 3, P6; REESCRITA na correção de 29/10, P2): "quando a gente fica livre de verdade?" pelo plano e pelo teto de cada pessoa — só com modo_proposta ligado (fora disso {fonte: projecao}: quem chama usa a frase da Fase 1). Para cada uma das 3 semanas a partir do 1º dia que a agenda ainda pode mudar (o dia útil depois do congelado), os meios-dias que cada pessoa ainda pega num serviço novo, a mesma conta do encaixe: o menor entre teto80 − compromisso, teto100 − compromisso − reserva e os meios-dias dela livres na grade (_agenda_grade_de_agora: o marcado e o reservado ocupam); o dono só com os dias dele em campo (sem eles, voce_fora e a frase "Você fica de fora da conta"). Depois, o que ocupa a equipe (o plano de hoje ao sábado da última semana, por OS, com quem fica o turno), o que não ocupa ninguém até destravar (a carteira fora do plano: travados, esperando o dono, parados no cliente, em espera; o pronto sem lugar; o em andamento sem dia) e como perguntar de um serviço novo. {fonte: simulacao (o sinal de "use o texto daqui" para a agenda_ver e a agenda_tela_semana), base: plano, de, ate, semanas[{seg, de, ate, rotulo, pessoas[{payee_id, nome, eh_dono, meios, celulas, teto, compromisso, reserva}], texto}], voce_fora, ocupa[{os, numero, reserva, dias, pessoas, texto}], nao_ocupam{travados, prontos, andamento, parados, em_espera}, texto (a linha da semana e da tela: "Livre de verdade: na semana de 03/11, Roberto 1 dia e meio, João nada; na de 09/11, Roberto 3 dias, João 1 dia."), texto_completo (a resposta do *livre*, até texto_max), ms}. Nada é gravado. STABLE, definer (as peças do motor são só do service_role); administrador e financeiro com login, ou o service_role. CORREÇÃO 29/10 (revisão): na linha curta (texto), a 1ª semana pela metade sai com o rótulo do *livre* ("Livre de verdade: de qua 04 a sex 06/11, Roberto 1 dia, João nada; na semana de 09/11, …"; um dia só, "na sex 06/11"), não "na semana de 04/11". CORREÇÃO DA 7a (revisão da etapa; achado 23): com a regra teto_equipe do gestor, (1) o dono não entra na conta do livre como técnico, mesmo com os dias em campo (o motor só o põe para abrir, fechar e no diagnóstico): "Você não entra na conta: em campo você acompanha, abre e fecha (o diagnóstico é com você)."; (2) os meios-dias da equipe na semana não passam do teto da equipe-semana (teto_equipe − o compromisso da equipe nela), repartidos de quem tem mais para quem tem menos. Sem a regra, a de antes, byte a byte. FASE 7b (P6, R4.4): com modo_chamar ligado, no fim do texto_completo, a linha de quem chamar do diário do gestor (a conta mais nova de até 3 dias, chamar.texto_livre): "Sem lugar com a equipe de hoje: Nelson e César. Com mais uma pessoa 9 meios-dias, cabem até 20/11 (*agenda gestor* diz quando)." Sem ela, ou fora de ligado, a de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 15 e 25): a linha de quem chamar (com modo_chamar ligado) entra depois do corte do texto_max, sempre: o resto do *livre* continua com o texto_max inteiro (antes ela era a última linha e o corte do fim a tirava). FASE 7g (P4): com modo_explicar ligado, livre_semanas semanas (no lugar das 3), a mesma conta de cada pessoa e, por semana, totais = {pode, folga, marcado, reservado, livre} da equipe sem você (a folga pela regra de agenda_como_pensei, R9.7) e o texto do §6.3; texto_completo no formato do §6.3 (o título, as semanas, a folga fora da conta, as notas de você e como perguntar de um serviço novo; o que ocupa e o que não ocupa ninguém ficam só nos dados). texto (a linha da semana e da tela) fica o de antes. Em sombra: a resposta de antes e dados.teste = {semanas}. Desligado: a de antes, byte a byte.';

-- ── 6. As portas ─────────────────────────────────────────────────────────────────────────────────────
-- As 2 novas são definer com porta própria (R9.4-6): agenda_ctp é invoker e o painel a chama com o login do admin; sem o grant a authenticated, a leitura
-- daria 42501 (e a grade do motor, _agenda_grade_de_agora, é só do service_role). Nunca anon. As 3 recriadas mantêm as portas de antes (create or replace
-- não muda a ACL).
revoke all on function public._agenda_encaixe_simulado(jsonb, date), public._agenda_entrada_simulada_da_os(uuid, date) from public, anon;
grant execute on function public._agenda_encaixe_simulado(jsonb, date), public._agenda_entrada_simulada_da_os(uuid, date) to authenticated, service_role;

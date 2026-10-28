-- Agenda de Produção, Fase 6 (P8): as leituras do aprendizado — o foco aprendizado, o cartão "Plano" da OS e o foco
-- fornecedores com o prazo medido (spec-fase6 §5.8, §6.2 e §7).
-- (1 função nova; 3 recriadas; nenhuma tabela, coluna, CHECK nem parâmetro novo; nenhum dado muda)
--
-- NÃO APLICADA. Montada por scratchpad/agenda-pesquisa/f6p8/montar-migration.mjs (nunca editar este .sql: edite as partes ou o
-- montador). Cada função recriada é o corpo da definição MAIS NOVA (conferido com grep a cada montagem), com as mudanças só
-- em blocos "-- FASE 6: (P8) … -- FASE 6: fim"; fora deles nenhuma linha muda (o L6 do teste agenda_fase6_leituras.sql
-- confere). Quem recriar de novo qualquer uma delas copia DESTA migration.
--
-- O que muda:
--   1. _agenda_ver_aprendizado (nova): o foco aprendizado do agenda_ver — os 7 blocos (o fator de campo por tipo de OS, a
--      presença do dono, os fornecedores, a capacidade do dono, o R$ por diária, o cliente e a revisão da carga), uma linha
--      por item com o texto que a rodada gravou (spec §6.2) e o fecho ("Medidas: 18 OS (11 valem; 3 sem os dias ditos no
--      início; …)." e "Respostas de cliente que foram a você por áudio: N em 30 dias."). Nada é calculado na leitura.
--   2. agenda_ver (de 20261028100500): o foco aprendizado (com login, só administrador e financeiro; desligada a leitura, a
--      frase de sempre), antes da conferência dos 18 focos da Fase 5.
--   3. os_plano_da_os (de 20261028100600): duracao.campo = a linha do fator de campo da classe da OS
--      (agenda_fator_de_campo: "Em teste: as OS de energia em motorhome levam até 1,7× o combinado (7 OS); hoje seria 1,7×, e
--      vale 1,5× (padrão).") — só com modo_aprendizado fora de desligado e na OS que não está concluída, faturada nem
--      cancelada; e presenca_dono.aprendida = o motivo da presença aprendida ("você foi a 3 de 4 OS de energia em
--      motorhome"), com o texto "Você fica o tempo todo (pelo que medi: …)" — sem ele, a presença aprendida aparecia como
--      "(você disse)", que é falso. O resto do cartão não muda.
--   4. _agenda_ver_fornecedores (de 20261027100600): o grupo "Medido (pelas notas que chegaram):" — o fornecedor com o prazo
--      medido em uso (fonte medido de _agenda_prazo_do_fornecedor: só com modo_aprendizado ligado e fornecedor na lista)
--      sumia de "Você disse" e de "Meu chute" (o risco do P3). Fora disso, o foco sai byte a byte igual.
--
-- Ordem de ligar: esta migration vem depois das 20261029100000 a 100700 e antes da migration de dado 20261029101000 (o modo em
-- sombra). Aplicar com o OK nomeado do dono (fila-do-dono/fase6-oks.md, passo 1). Prova: supabase/tests/agenda_fase6_leituras.sql
-- (bancada) e agenda_fase6_pos_deploy.sql (produção, só SELECT).
--
-- DESFAZER: recriar cada função com o corpo da migration de onde ela foi copiada (a linha "-- <nome> (de <arquivo>)" acima de
-- cada uma); a nova pode ficar (ninguém a chama sem o agenda_ver desta migration) ou sair com
--   drop function if exists public._agenda_ver_aprendizado(date);

-- ── 1. A função nova: o foco aprendizado ────────────────────────────────────────────────────────────────────
-- _agenda_ver_aprendizado(p_hoje): o que a agenda aprendeu, em 7 blocos (o fator de campo por tipo de OS, a presença do dono,
-- os fornecedores, a capacidade do dono, o R$ por diária, o cliente e a revisão da carga), uma linha por item e chave com o
-- texto que a rodada gravou em agenda_aprendizado.texto (spec-fase6 §6.2), e o fecho: as medidas (quantas OS, quantas valem
-- e por que as outras não) e as respostas de cliente que foram ao dono por áudio ou sem a agenda entender (d8).
-- Nada é calculado aqui: o número de cada linha é o que a rodada do dia gravou. O fator e a presença não repetem a chave
-- mais larga quando ela diz o mesmo que a mais fina (o mesmo n, o mesmo medido e o mesmo estado), e as chaves que ainda medem
-- só aparecem como "as OS" (todas) enquanto nenhuma do item chegou ao mínimo; os fornecedores medindo aparecem ("Correa: 3
-- de 5 entregas medidas"). Cabe em texto_max: as linhas de cada bloco saem do fim ("• e mais N"), e o fecho fica sempre.
-- Invoker e STABLE: com login, só administrador e financeiro (senão 42501); sem login, só o service_role.
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

  return jsonb_build_object('ok', true, 'texto', v_t,
    'dados', jsonb_build_object(
      'modo', c.modo_aprendizado, 'ligados', to_jsonb(c.aprendizado_ligados), 'blocos', v_blocos,
      'medidas', jsonb_build_object('total', v_tot, 'validas', v_val, 'invalidas', v_inv),
      'respostas_ao_dono', jsonb_build_object('audio', v_audio, 'nao_entendidas', v_naoent, 'dias', 30)));
end;
$function$;

comment on function public._agenda_ver_aprendizado(date) is
  'Agenda de Produção (Fase 6, P8): agenda_ver foco aprendizado (spec-fase6 §5.8 e §6.2) — o que a agenda aprendeu, em 7 blocos (fator de campo por tipo de OS, presença do dono, fornecedores, capacidade do dono, R$ por diária, cliente, revisão da carga), uma linha por item e chave com o texto que a rodada do dia gravou em agenda_aprendizado.texto (nada é calculado aqui). O fator e a presença não repetem a chave mais larga que diz o mesmo que a mais fina (o mesmo n, medido e estado) e só mostram as que ainda medem como "as OS" enquanto nenhuma chegou ao mínimo; sem nenhuma linha do fator, "As OS: 0 de 6 OS medidas; …". Fecha com "Medidas: N OS (M valem; …)" e "Respostas de cliente que foram a você por áudio: N em 30 dias[; sem eu entender: K]." (d8). Desligado: só o cabeçalho e o fecho. Até texto_max: as linhas de cada bloco saem do fim ("• e mais N"), o fecho fica. {ok, texto, dados {modo, ligados, blocos [{bloco, nome, linhas [{item, chave, nivel, estado, n, n_min, calculado, em_uso, texto}]}], medidas {total, validas, invalidas}, respostas_ao_dono {audio, nao_entendidas, dias}}}. Invoker e STABLE: com login, só administrador e financeiro (senão 42501); sem login, só o service_role.';

-- ── 2. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 6: (P8)") ───────────────
-- Fora dos blocos nenhuma linha muda (o L6 do teste confere). Quem recriar de novo qualquer uma delas copia DESTA migration.
-- agenda_ver (de 20261028100500_agenda_fase5_leituras.sql)
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
  -- FASE 3: o livre de verdade (a simulação do motor) e o mês da comissão
  v_lv      jsonb;
  v_mes     date;
begin
  -- FASE 6: (P8) o foco aprendizado (spec-fase6 §5.8 e §6.2: o que a agenda aprendeu com o que aconteceu,
  -- _agenda_ver_aprendizado) e a conferência do foco com os 19 — antes da conferência dos 18 da Fase 5, que o foco
  -- aprendizado não alcança. Com login, só administrador e financeiro (42501, antes de ler a config); desligada a leitura, a
  -- frase de sempre.
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar', 'decisoes', 'mudancas', 'plano',
                    'ppc', 'diarias', 'marcos', 'comissao', 'equipe', 'compras', 'fornecedores', 'clientes', 'aprendizado') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras, fornecedores, clientes ou aprendizado)', p_foco
      using errcode = '22023';
  end if;
  if v_foco = 'aprendizado' then
    if p_hoje is null then
      raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
    end if;
    if auth.uid() is not null and not public.is_admin_or_financial(auth.uid()) then
      raise exception 'O que a agenda aprendeu é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
    if (public._agenda_cfg()).modo_leitura = 'desligado' then
      return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                                'texto', 'A agenda de produção está desligada agora.');
    end if;
    return public._agenda_ver_aprendizado(p_hoje) || jsonb_build_object('rota', 'aprendizado');
  end if;
  -- FASE 6: fim
  -- FASE 5: o foco clientes (a mensagem ao cliente: _agenda_ver_clientes, com ou sem a OS; a OS concluída também) e a
  -- conferência do foco com os 18 — antes da conferência dos 17 da Fase 4, que o foco clientes não alcança.
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar', 'decisoes', 'mudancas', 'plano',
                    'ppc', 'diarias', 'marcos', 'comissao', 'equipe', 'compras', 'fornecedores', 'clientes') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras, fornecedores ou clientes)', p_foco
      using errcode = '22023';
  end if;
  if v_foco = 'clientes' then
    if p_hoje is null then
      raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
    end if;
    if (public._agenda_cfg()).modo_leitura = 'desligado' then
      return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                                'texto', 'A agenda de produção está desligada agora.');
    end if;
    if nullif(btrim(p_os), '') is not null then
      v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
      if v_ro ->> 'status' in ('nao_achei', 'ambiguo') then
        return jsonb_build_object('ok', false, 'rota', 'os', 'texto', v_ro ->> 'texto',
                                  'pergunta', case when v_ro ->> 'status' = 'ambiguo' then v_ro ->> 'texto' end,
                                  'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
      end if;
      return public._agenda_ver_clientes((v_ro ->> 'id')::uuid, p_hoje) || jsonb_build_object('rota', 'clientes_os');
    end if;
    return public._agenda_ver_clientes(null, p_hoje) || jsonb_build_object('rota', 'clientes');
  end if;
  -- FASE 5: fim
  -- FASE 2: os focos decisoes, mudancas e plano
  -- FASE 3: os focos ppc, diarias, marcos, comissao e equipe
  -- FASE 4: os focos compras e fornecedores (a conferência e a mensagem com os 17)
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar', 'decisoes', 'mudancas', 'plano',
                    'ppc', 'diarias', 'marcos', 'comissao', 'equipe', 'compras', 'fornecedores') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras ou fornecedores)', p_foco
      using errcode = '22023';
  end if;
  -- FASE 4: fim
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
  -- FASE 3: a comissão lê o mês ("outubro", "mês passado"), não um período de dias.
  if v_foco = 'comissao' then
    begin
      v_mes := public._agenda_mes_dito(p_periodo, p_hoje);
    exception when sqlstate '22007' then
      return jsonb_build_object('ok', false, 'rota', 'periodo', 'texto', sqlerrm, 'pergunta', sqlerrm);
    end;
  else
    begin
      select x.de, x.ate into v_de, v_ate from public._agenda_periodo(p_periodo, p_hoje) x;
    exception when sqlstate '22007' then
      return jsonb_build_object('ok', false, 'rota', 'periodo', 'texto', sqlerrm, 'pergunta', sqlerrm);
    end;
  end if;

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
    -- FASE 3: os marcos da OS (dentro ou fora da carteira: a concluída e a entregue já saíram dela)
    elsif v_foco = 'marcos' then
      v_rota := 'marcos';
      v_r := public._agenda_ver_marcos((v_ro ->> 'id')::uuid, p_hoje);
    -- FASE 4: as compras e a espera de peça da OS (também fora da carteira: a concluída nos últimos 180 dias); os
    -- fornecedores não são de uma OS
    elsif v_foco = 'compras' then
      v_rota := 'compras_os';
      v_r := public._agenda_ver_compras((v_ro ->> 'id')::uuid, p_hoje);
    elsif v_foco = 'fornecedores' then
      v_rota := 'fornecedores';
      v_r := public._agenda_ver_fornecedores(p_hoje);
    -- FASE 4: fim
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
  -- FASE 3: os marcos pedem a OS
  elsif v_foco = 'marcos' then
    return jsonb_build_object('ok', false, 'rota', 'marcos',
      'texto', 'Diga qual OS: o nome do cliente ou o número (por exemplo, OS-00074).',
      'pergunta', 'Diga qual OS: o nome do cliente ou o número (por exemplo, OS-00074).');
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
  -- FASE 3: a semana medida, as diárias da agenda, a comissão do mês e o que a equipe respondeu
  elsif v_foco = 'ppc' then
    v_rota := 'ppc';
    v_r := public._agenda_ver_ppc(v_de, p_hoje);
  elsif v_foco = 'diarias' then
    v_rota := 'diarias';
    v_r := public._agenda_ver_diarias(v_de, v_ate, p_hoje);
  elsif v_foco = 'comissao' then
    v_rota := 'comissao';
    v_r := public._agenda_ver_comissao(v_mes, p_hoje);
  elsif v_foco = 'equipe' then
    v_rota := 'equipe';
    v_r := public._agenda_ver_equipe(p_hoje);
  -- FASE 4: o que comprar e até quando, as notas, o tempo até comprar e a pergunta ao fornecedor; como conto o prazo de
  -- cada fornecedor
  elsif v_foco = 'compras' then
    v_rota := 'compras';
    v_r := public._agenda_ver_compras(null, p_hoje);
  elsif v_foco = 'fornecedores' then
    v_rota := 'fornecedores';
    v_r := public._agenda_ver_fornecedores(p_hoje);
  -- FASE 4: fim
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
    -- FASE 3: com a agenda automática ligada, o livre de verdade sai da simulação do motor (fora disso, a projeção)
    if (public._agenda_cfg()).modo_proposta = 'ligado' then
      v_lv := public.agenda_livre_de_verdade(p_hoje, v_agora);
    end if;
    v_r := jsonb_build_object('ok', true,
      'texto', public._agenda_juntar(array[v_r #>> '{dados,textos,resumo}',
                                           case when v_lv ->> 'fonte' = 'simulacao' then v_lv ->> 'texto'
                                                else v_r #>> '{dados,textos,livre}' end],
                                     (select texto_max from public._agenda_cfg())),
      'dados', jsonb_build_object('fila', v_r #> '{dados,fila}', 'livre', v_r #> '{dados,livre}',
                                  'capacidade', v_r #> '{dados,capacidade}',
                                  'livre_de_verdade', coalesce(v_lv, jsonb_build_object('fonte', 'projecao'))));
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
    -- FASE 3: com a agenda automática ligada, a frase do livre da semana é a da simulação do motor
    if (public._agenda_cfg()).modo_proposta = 'ligado' and nullif(v_r #>> '{dados,textos,livre}', '') is not null
       and position((v_r #>> '{dados,textos,livre}') in (v_r ->> 'texto')) > 0 then
      v_lv := public.agenda_livre_de_verdade(p_hoje, v_agora);
      if v_lv ->> 'fonte' = 'simulacao' then
        v_r := jsonb_set(v_r, '{texto}', to_jsonb(replace(v_r ->> 'texto', v_r #>> '{dados,textos,livre}', v_lv ->> 'texto')));
        v_r := jsonb_set(v_r, '{dados,livre_de_verdade}', v_lv);
      end if;
    end if;
  end if;

  return v_r || jsonb_build_object('rota', v_rota);
end;
$function$;

comment on function public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date) is 'Agenda de Produção (Fase 1, P4; Fase 2, P5; Fase 3, P6; Fase 4, P6; Fase 5, P5): o despacho ÚNICO da ferramenta agenda_ver e dos comandos sem IA. os + simular_aprovacao → agenda_ctp; FASE 3: os + foco marcos → os 4 marcos (agenda_marcos_da_os, também fora da carteira); foco marcos sem os → pede a OS; FASE 4: os + foco compras → a espera de peça e o material da OS (_agenda_ver_compras, também fora da carteira); foco compras → o que comprar e até quando, as notas sem serviço dito, o tempo até comprar, a pergunta ao fornecedor e o detector em teste (_agenda_ver_compras); foco fornecedores → como conto o prazo de cada fornecedor (_agenda_ver_fornecedores; com ou sem os); os + foco material → agenda_ver_material; os → a visão da OS; simular {dias, com_quem, dono} → agenda_simular; FASE 2: foco decisoes → as decisões numeradas (agenda_decisoes_abertas; FASE 3: a da diária com as opções e as palavras) e o que mais a agenda quer saber; mudancas → o que mudou sozinho desde ontem com *desfaz*; plano → o publicado do período dia a dia (sombra: "Em teste"); FASE 3: ppc → agenda_ppc da semana do período; diarias → as diárias que a agenda lançou e as perguntas abertas; comissao → comissao_resumo_do_mes do mês dito em periodo ("outubro", "mês passado"; só a conta, nada é pago); equipe → o que a equipe respondeu hoje e no próximo dia útil; foco o_que_fazer → agenda_o_que_fazer (pessoa que não é o dono: o dia dela); atrasos/riscos → agenda_atrasos; material → agenda_ver_material(null); livre → resumo + livre de agenda_semana (FASE 3: com modo_proposta ligado, o livre de verdade pela simulação do motor, agenda_livre_de_verdade); aprontar → agenda_aprontar; pessoa (não o dono) + 1 dia → agenda_dia_da_pessoa; hoje/amanhã → o dia + o bloco 2 resumido; resto → agenda_semana (em ''ligado'' o marcado é o plano; FASE 3: e a frase do livre é a da simulação). periodo: hoje, amanha, semana, proxima_semana ou o que o dono disse. Referência que não existe (OS, pessoa, data, mês) → {ok:false, texto:"Não encontrei …"/a pergunta}; FASE 5: foco clientes (com ou sem os; a OS concluída também) → as mensagens ao cliente (_agenda_ver_clientes); foco fora da lista (os 18) lança 22023. Devolve {ok, texto, dados, rota}. FASE 6 (P8): foco aprendizado → o que a agenda aprendeu com o que aconteceu (_agenda_ver_aprendizado: o fator por tipo de OS, a presença do dono, os fornecedores, a capacidade do dono, o R$ por diária, o cliente e a revisão da carga, com o n de cada um, e as medidas); com login, só administrador e financeiro (42501). A lista dos focos passa a 19.';

-- os_plano_da_os (de 20261028100600_agenda_fase5_telas.sql)
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
begin
  if p_os is null or p_hoje is null then
    raise exception 'os_plano_da_os: sem a OS ou o dia de hoje' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'O plano da OS é com o administrador.' using errcode = '42501';
  end if;
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

  return jsonb_build_object(
    -- FASE 5: o bloco "Cliente" do cartão (o que foi dito, a confirmação, as mensagens desta OS e o que espera você;
    -- _agenda_cliente_da_os). null sem o cliente.
    'cliente', public._agenda_cliente_da_os(p_os, p_hoje),
    -- FASE 5: fim
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
  'Agenda de Produção (Fase 3, P7a; Fase 5, P6): o cartão "Plano" da OS — {cliente (Fase 5: _agenda_cliente_da_os — o contato, o que foi dito ao cliente e se ainda vale, a confirmação, as 5 mensagens mais recentes desta OS e o que espera o dono; null sem o cliente), os, numero, status, estado, marcos (agenda_marcos_da_os), pode_entregar (concluída sem entrega), duracao {dias, fonte dono|aceita|sugerida, fonte_texto, faixa {otimista, realista}, faixa_texto, texto}, presenca_dono {valor, pela_regra, texto "Você abre e fecha (pela regra)"}, material {estado, itens:[{descricao, nivel A–E, nivel_texto, situacao, previsao, trecho, critico, fornecedor}]}, janela {bem_indisponivel, nao_antes_de, motivo, precisa_ate, nao_antes_texto, precisa_ate_texto}, prometido_planejado {precisa_ate, fim_publicado, folga_du, texto}, planejado_realizado:[{dia, rotulo, pessoas_texto, dia_texto, meios, resultado, resultado_texto, motivo_texto, diaria ("lançada" | "a confirmar" | null — nunca o valor)}], intervencoes:[{dia, texto}]}. Administrador e financeiro (com login) ou service_role; senão 42501. FASE 6 (P8): duracao.campo = a linha do fator de campo da classe da OS (agenda_fator_de_campo: "Em teste: as OS de energia em motorhome levam até 1,7× o combinado (7 OS); hoje seria 1,7×, e vale 1,5× (padrão).") — nula com modo_aprendizado desligado e na OS concluída, faturada ou cancelada; presenca_dono.aprendida = o motivo da presença aprendida ("você foi a 3 de 4 OS de energia em motorhome"; nulo sem ela), e o texto "Você fica o tempo todo (pelo que medi: …)".';

-- _agenda_ver_fornecedores (de 20261027100600_agenda_fase4_leituras.sql)
create or replace function public._agenda_ver_fornecedores(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid     uuid := (select auth.uid());
  c         public.agenda_config;
  c_ordem   constant text[] := array['balcao', 'entrega_local', 'distribuidor_sc_pr', 'outro_estado', 'marketplace', 'importacao'];
  r         record;
  v_id      uuid;
  v_pr      jsonb;
  v_lista   jsonb := '[]'::jsonb;
  v_vistos  uuid[] := '{}';
  v_grupos  text[] := '{}';
  v_disse   text[];
  v_chute   text[];
  v_falta   text[] := '{}';
  g         record;
  v_ex      text[];
  v_cab     text;
  v_pe      text;
  v_linhas  text[];
  v_n       int;
  k         int;
  v_t       text;
  -- FASE 6: (P8) o prazo medido em uso (fonte medido)
  v_medido  text[];
  -- FASE 6: fim
begin
  if p_hoje is null then
    raise exception '_agenda_ver_fornecedores: sem o dia de hoje' using errcode = '22004';
  end if;
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  c := public._agenda_cfg();

  for r in
    select x.id, max(x.contas) as contas
      from (select p.fornecedor_id as id, p.contas from public._agenda_fornecedores_principais(p_hoje) p
            union all
            select m.fornecedor_id, 0
              from public.os_carteira(p_hoje) k
              join public.os_material m on m.service_order_id = k.service_order_id
             where m.fornecedor_id is not null and m.situacao in ('falta', 'comprado', 'a_caminho')) x
     group by x.id
     order by max(x.contas) desc, x.id
  loop
    v_id := r.id;
    v_pr := public._agenda_prazo_do_fornecedor(v_id);
    -- o cadastro que o dono já tirou de uso vale como o que ficou
    if not coalesce((select s.active from public.suppliers s where s.id = v_id), true) and v_pr ->> 'principal_id' is not null then
      v_id := (v_pr ->> 'principal_id')::uuid;
      v_pr := public._agenda_prazo_do_fornecedor(v_id);
    end if;
    continue when v_id = any (v_vistos);
    v_vistos := v_vistos || v_id;
    v_lista := v_lista || (jsonb_build_object(
      'fornecedor_id', v_id, 'nome', public._agenda_fornecedor_curto(v_id), 'contas', r.contas,
      'lugar', (select public._agenda_lugar_texto(s.city, s.state) from public.suppliers s where s.id = v_id),
      'sem_lugar_no_cadastro', (select nullif(btrim(coalesce(s.city, '')), '') is null and nullif(btrim(coalesce(s.state, '')), '') is null
                                  from public.suppliers s where s.id = v_id),
      'grupo', (select public._agenda_nome_de_grupo(coalesce(nullif(btrim(s.trade_name), ''), s.name)) from public.suppliers s where s.id = v_id),
      'frase', public._agenda_classe_texto(v_pr ->> 'classe', (v_pr ->> 'du')::int, (v_pr ->> 'corridos')::int))
      || v_pr);
  end loop;

  -- o rótulo: "Premel (Itajaí/SC)"; sem lugar, só o nome
  -- Você disse e o meu chute: uma linha por frase de prazo, na ordem das classes
  select array_agg(t.l order by t.o) into v_disse
    from (select '• ' || f.frase || ': ' || public._agenda_lista(array_agg(concat(f.nome, ' (' || f.lugar || ')') order by f.contas desc, f.nome), 6) || '.' as l,
                 min(array_position(c_ordem, f.classe)) as o
            from jsonb_to_recordset(v_lista) f(nome text, lugar text, contas int, classe text, fonte text, frase text)
           where f.fonte = 'dono' and f.classe is not null
           group by f.frase) t;
  select array_agg(t.l order by t.o, t.l) into v_chute
    from (select '• ' || f.frase || ': ' || public._agenda_lista(array_agg(concat(f.nome, ' (' || f.lugar || ')') order by f.contas desc, f.nome), 6) || '.' as l,
                 min(array_position(c_ordem, f.classe)) as o
            from jsonb_to_recordset(v_lista) f(nome text, lugar text, contas int, classe text, fonte text, frase text)
           where f.fonte in ('cidade', 'nome') and f.classe is not null
           group by f.frase) t;

  -- FASE 6: (P8) o prazo medido (spec-fase6 §5.3; o risco do P3): com fornecedor_prazo em uso (_agenda_prazo_do_fornecedor,
  -- fonte medido: só com o aprendizado ligado e fornecedor na lista), o fornecedor saía de "Você disse" e de "Meu chute" e
  -- sumia do foco. Agora vai a "Medido (pelas notas que chegaram):", com o texto do prazo ("outro estado, 6 dias úteis
  -- (medido em 5 notas)").
  select array_agg(t.l order by t.o, t.l) into v_medido
    from (select '• ' || concat(f.nome, ' (' || f.lugar || ')') || ': ' || f.texto || '.' as l,
                 array_position(c_ordem, f.classe) as o
            from jsonb_to_recordset(v_lista) f(nome text, lugar text, classe text, fonte text, texto text)
           where f.fonte = 'medido') t;
  -- FASE 6: fim
  -- Falta você dizer: sem lugar no cadastro; o cadastro repetido (uma linha por nome, com os lugares e o que vale)
  for r in select * from jsonb_to_recordset(v_lista) f(nome text, lugar text, classe text, duvida text, grupo text,
                                                        sem_lugar_no_cadastro boolean, principal_id uuid)
            order by f.nome loop
    if r.duvida = 'duplicado' then
      continue when r.grupo = any (v_grupos);
      v_grupos := v_grupos || r.grupo;
      -- os cadastros ativos do mesmo nome (o que vale primeiro) e o lugar do que vale
      select count(*) as n,
             public._agenda_lista(array_agg(coalesce(public._agenda_lugar_texto(s.city, s.state), 'sem cidade')
                                            order by (s.id = r.principal_id) desc, s.id), 4) as lugares
        into g
        from public.suppliers s
       where coalesce(s.active, true)
         and public._agenda_nome_de_grupo(coalesce(nullif(btrim(s.trade_name), ''), s.name)) = r.grupo;
      v_pe := (select public._agenda_lugar_texto(p.city, p.state) from public.suppliers p where p.id = r.principal_id);
      v_falta := v_falta || case when v_pe is not null
        then format('• %s: cadastrada %s vezes (%s); conto pela de %s. É a mesma?', r.nome, g.n, g.lugares, v_pe)
        else format('• %s: cadastrada %s vezes (%s) e não sei qual vale. Qual é a certa?', r.nome, g.n, g.lugares) end;
    elsif r.classe is null then
      v_falta := v_falta || case when r.sem_lugar_no_cadastro then format('• %s: sem cidade no cadastro.', r.nome)
                                 else format('• %s: não sei onde fica (%s).', r.nome, r.lugar) end;
    end if;
  end loop;

  -- como responder: com dois nomes da lista ("a Premel eu pego no balcão", "a Toli chega em 3 dias úteis")
  v_ex := array(select f.nome from jsonb_to_recordset(v_lista) f(nome text, contas int, classe text, fonte text)
                 where f.classe is not null and coalesce(f.fonte, '') <> 'dono'
                 order by array_position(c_ordem, f.classe), f.contas desc, f.nome limit 2);
  v_pe := case when cardinality(v_ex) = 2
               then format('Pode ser um áudio só: "a %s eu pego no balcão", "a %s chega em 3 dias úteis".', v_ex[1], v_ex[2])
               else 'Pode ser um áudio só, do seu jeito: "eu pego no balcão", "chega em 3 dias úteis".' end;

  v_cab := 'Como eu conto a chegada do material dos fornecedores principais:';
  if jsonb_array_length(v_lista) = 0 then
    return jsonb_build_object('ok', true,
      'texto', 'Ainda não tenho fornecedor principal: nenhuma conta de material no último ano nem compra a caminho.',
      'dados', jsonb_build_object('fornecedores', v_lista));
  end if;
  -- Cabe no teto: o chute sai do fim ("• e mais N"), nunca o que falta você dizer.
  v_n := coalesce(cardinality(v_chute), 0);
  for k in reverse v_n .. 0 loop
    v_linhas := array[v_cab]
                || case when coalesce(cardinality(v_disse), 0) = 0 then array['Você disse: nenhum ainda.']
                        else array['Você disse:'] || v_disse end
                -- FASE 6: (P8) o prazo medido, logo depois do que o dono disse (só aparece com fornecedor_prazo em uso)
                || case when coalesce(cardinality(v_medido), 0) > 0 then array['Medido (pelas notas que chegaram):'] || v_medido
                        else '{}'::text[] end
                -- FASE 6: fim
                || case when v_n > 0 then array['Meu chute (pela cidade ou pelo nome):'] || v_chute[1:k]
                                          || case when k < v_n then array[format('• e mais %s', v_n - k)] else '{}'::text[] end
                        else '{}'::text[] end
                || case when cardinality(v_falta) > 0 then array['Falta você dizer:'] || v_falta else '{}'::text[] end
                || array[v_pe];
    v_t := public._agenda_juntar(v_linhas, null);
    exit when char_length(v_t) <= c.texto_max;
  end loop;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_linhas, c.texto_max),
    'dados', jsonb_build_object('fornecedores', v_lista, 'disse', coalesce(cardinality(v_disse), 0), 'chute', v_n,
                                'falta', cardinality(v_falta)));
end;
$function$;

comment on function public._agenda_ver_fornecedores(date) is
  'Agenda de Produção (Fase 4, P6): agenda_ver foco fornecedores — como a agenda conta a chegada do material dos fornecedores principais (_agenda_fornecedores_principais) e dos das linhas da carteira ainda não na mão, pela fonte única (_agenda_prazo_do_fornecedor): "Você disse:" (suppliers.modalidade; vazio: "Você disse: nenhum ainda."), "Meu chute (pela cidade ou pelo nome):" uma linha por prazo ("• entrega local, 1 dia útil: Premel (Itajaí/SC) e Souper (Itajaí/SC)"), "Falta você dizer:" (sem cidade no cadastro; cadastro repetido: "• Kamell: cadastrada 2 vezes (Vila Velha/ES e Itajaí/SC); conto pela de Vila Velha/ES. É a mesma?") e "Pode ser um áudio só: …" com dois nomes da lista. O inativo vale como o que ficou. Até texto_max (o chute sai do fim com "• e mais N"). Definer (lê os principais, que são só do service_role): com login, só administrador e financeiro (senão 42501). {ok, texto, dados:{fornecedores, disse, chute, falta}}. FASE 6 (P8): o fornecedor com o prazo medido em uso (fonte medido de _agenda_prazo_do_fornecedor) vai ao grupo "Medido (pelas notas que chegaram):" ("• Kamell (Vila Velha/ES): outro estado, 6 dias úteis (medido em 5 notas)."), logo depois de "Você disse"; antes ele sumia do foco. Sem o medido em uso, o texto é o de antes.';


-- ── 9. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- A leitura nova (invoker, STABLE; confere quem vê antes de tudo): authenticated e service_role, nunca anon.
revoke all on function public._agenda_ver_aprendizado(date) from public, anon;
grant execute on function public._agenda_ver_aprendizado(date) to authenticated, service_role;

-- As recriadas mantêm as portas de antes (create or replace não muda a ACL; repetidas aqui para a migration valer sozinha).
revoke all on function
  public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date),
  public.os_plano_da_os(uuid, date),
  public._agenda_ver_fornecedores(date)
  from public, anon;
grant execute on function
  public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date),
  public.os_plano_da_os(uuid, date),
  public._agenda_ver_fornecedores(date)
  to authenticated, service_role;

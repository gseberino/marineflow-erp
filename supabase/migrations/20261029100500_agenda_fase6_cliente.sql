-- Agenda de Produção, Fase 6 ("Aprendizado"), pacote P5: o cliente no aprendizado — a 1ª data dita ao cliente (que nunca
-- zera), a pontualidade medida contra ela e a folga do aviso de atraso (a faixa do M6).
-- Spec: scratchpad agenda-pesquisa/spec-fase6.md (§3.1, §3.2, §3.3 d5, §5.5, §5.9, §6.2, §6.3). Depende de 20261029100400.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (1 função nova; 3 recriadas; o preenchimento da 1ª promessa das linhas que já existem — em
-- produção, nenhuma: prometido_* nasce com a Fase 5)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f6p5/montar-migration.mjs (as partes escritas à mão
-- f6p5/parte-0-cabeca.sql, parte-1-novas.sql, parte-5-primeira.sql e parte-9-portas.sql + as 3 recriadas, cada uma com o
-- corpo da definição MAIS NOVA, conferida com grep a cada montagem: fora dos blocos "-- FASE 6:" nenhuma linha muda). Edite o
-- montador, nunca este .sql.
--
-- POR QUE: a pontualidade com o cliente se mede contra a 1ª data que ele ouviu. Hoje ela mora em prometido_original_ate, que
-- o aviso "ainda faltam peças sem data" zera junto com o prometido (NOVO-agenda-44): justamente as OS que mais atrasaram
-- perderiam a 1ª promessa. E o aviso de atraso (M6) diz uma faixa nova; quando o serviço termina depois dela, a faixa errou
-- para menos. Este pacote guarda a 1ª promessa numa coluna que nunca zera, mede a pontualidade (só medida, nunca usada) e mede
-- quanto os avisos erraram; com o item ligado, a faixa do M6 de peça e de execução ganha essa folga. Nenhuma mensagem nova:
-- só a data dentro do modelo de sempre muda. Com o modo de aprendizado fora de ligado, ou sem "aviso_cliente" e "fator" em
-- aprendizado_ligados, o risco do cliente e as mensagens saem byte a byte as da Fase 5.
--
-- O QUE MUDA:
--   1. _agenda_aprender_cliente(hoje, agora): pelo gravador, nas medidas (agenda_medidas_os) das OS concluídas na janela
--      (aprender_janela_dias; a reaberta fica de fora):
--      · cliente_pontualidade, chave e nível todas (só medida: nunca em uso) — calculado = a fração das OS com a 1ª promessa
--        que ficaram prontas até ela (atraso_cliente_du ≤ 0), n ≥ cliente_n_min; detalhe {n, no_prazo, p80_atraso_du};
--      · aviso_folga, chave e nível todas — calculado = o P80 (fator_percentil) de aviso_estouro_du nas OS com aviso de
--        atraso enviado e com faixa, ao dia útil mais próximo, preso em [0, aviso_folga_max_du], n ≥ aviso_n_min; padrão 0;
--        detalhe {n, no_prazo, p50, maior}.
--      Cada item no seu bloco: o erro de um vai a app_error_logs (agenda / aprender:cliente) e o outro segue.
--   2. Recriadas (o corpo da definição mais nova + blocos "-- FASE 6:"):
--      · _agenda_cliente_gravar_prometido (de 20261028100100): prometido_primeiro_ate = coalesce(o de antes, o original, o
--        de agora) — a 1ª vez grava; depois não muda; o aviso sem data (_agenda_cliente_tirar_prometido) não a toca;
--      · _agenda_cliente_risco (de 20261028100800): (a) na execução, o estouro usa o fator de campo da OS
--        (agenda_fator_de_campo) no lugar de estouro_fator, só com o modo ligado e "fator" na lista — e quem não lê o
--        aprendizado (o técnico, 42501) fica com o padrão; (b) nas variantes peca e execucao, faixa_ate ganha a folga do aviso
--        (_agenda_aprendido('aviso_folga', 'todas'), nulo = 0) em dias úteis. faixa_de, fim_novo, risco e atraso não mudam;
--        o remarcado firme e o peca_sem_data também não;
--      · _agenda_aprendizado_texto (de 20261029100400): os textos da pontualidade e da folga do aviso (spec §6.2/§6.3).
--   3. O preenchimento: as linhas de os_planejamento sem prometido_primeiro_ate ganham a 1ª promessa pelo histórico (o
--      prometido_original_ate de antes do 1º aviso sem data), senão pelo prometido_original_ate, senão pela 1ª data gravada no
--      histórico. Só onde a coluna é nula (rodar 2× não muda nada).
--
-- DESVIOS DA SPEC (provados em supabase/tests/agenda_fase6_cliente.sql):
--   · O passo recebe p_agora (como P2 a P4).
--   · O P80 do aviso usa fator_percentil (não há um percentil do cliente em agenda_config; o estouro do aviso é estouro da
--     execução, o mesmo que o fator mede) e vai ao dia útil mais próximo (2,2 → 2: cobre 4 dos 5 avisos da fixture, os 80%; o
--     teto do fornecedor do P3 daria 3).
--   · A folga só entra no faixa_ate (o que o cliente ouve); o fim_novo, o risco e o atraso continuam os do plano. Assim, o M6
--     que sai com a folga vira o prometido, e o plano dentro dele não abre outro aviso.
--   · O fator só é lido com o modo ligado e "fator" na lista, e o 42501 de agenda_fator_de_campo (o técnico, que chega aqui
--     pelo _agenda_cliente_risco, que é de authenticated) vira o padrão. Em teste, nem é chamado.
--   · A pontualidade conta toda OS medida com a 1ª promessa (não só as válidas para o fator: a validade é da conferência e dos
--     dias ditos, que não mudam se o cliente foi atendido no dia).
--
-- O QUE NÃO MUDA: nenhuma mensagem nova (o montador recusa escrita em fila de mensagem); o modelo do M6 (só a data dentro
-- dele); a chave da mensagem (pelo faixa_de, que não muda); o prometido_original_ate e o _agenda_cliente_tirar_prometido da
-- Fase 5 (a coluna nova é que não zera). Nada roda sozinho: a rodada é do P6 (agenda_aprender).
--
-- O RISCO DA SPEC (o M6 registrado e ainda não enviado quando a folga liga), PROVADO no C6 do teste: o aviso vivo NÃO é
-- recusado — a chave e o dia (faixa_de) são os mesmos, e a revalidação refaz o texto com os dados do registro, que é o mesmo —
-- então ele sai com a faixa SEM a folga, e a rodada não registra outro (ja_existe). Depois de sair, o prometido é a faixa
-- dele e o risco some (o plano cabe nela): o cliente ouve a faixa de antes, como hoje. A folga vale do aviso seguinte em diante.
-- SAÍDA SEGURA AO LIGAR "aviso_cliente": ligar quando não houver aviso de atraso vivo (registrada, aguardando_dono ou
-- enfileirada) — select count(*) from agenda_cliente_mensagens where tipo = 'pode_atrasar' and estado in ('registrada',
-- 'aguardando_dono', 'enfileirada') — ou aceitar que o que já está registrado sai sem a folga.
--
-- ORDEM DE LIGAR: depois de 20261029100400; antes de 20261029100600. Aplicar sozinha não muda nada para ninguém (a coluna da
-- 1ª promessa passa a ser gravada, e só a medição a lê).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase6_cliente.sql (a fixture-fase6 só na bancada; as portas e as cópias em
-- qualquer lugar). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261029100500
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261029100500_agenda_fase6_cliente.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261029100500', 'agenda_fase6_cliente');"
--
-- DESFAZER: reaplicar, em ordem, as definições de 20261028100100 (_agenda_cliente_gravar_prometido), 20261028100800
-- (_agenda_cliente_risco) e 20261029100400 (_agenda_aprendizado_texto); a nova pode ficar (ninguém de antes a chama). A coluna
-- prometido_primeiro_ate preenchida não incomoda ninguém (só a medição a lê).
--
-- IDEMPOTENTE: create or replace function; revoke/grant; o preenchimento só onde a coluna é nula.

-- ── 1. O passo do cliente: a pontualidade e a folga do aviso ─────────────────────────────────────────────
-- Lê só agenda_medidas_os (o P1 mede cada OS concluída: a 1ª promessa, o atraso contra ela, os avisos de atraso enviados e
-- quanto o serviço passou da faixa do último deles). Escreve só pelo gravador (_agenda_aprendizado_gravar).
create or replace function public._agenda_aprender_cliente(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c       public.agenda_config := public._agenda_cfg();
  v_de    date;
  v_n     int;
  v_ok    int;
  v_vals  numeric[];
  v_amos  jsonb;
  v_p     numeric;
  v_calc  numeric;
  v_pont  jsonb;
  v_aviso jsonb;
  n_err   int := 0;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  v_de := p_hoje - c.aprender_janela_dias;

  -- (a) A pontualidade (só medida, nunca usada): das OS concluídas com a 1ª data dita ao cliente, quantas ficaram prontas
  -- até ela (o atraso em dias úteis ≤ 0). O "atraso chega a" é o P80 do atraso de todas, ao dia útil mais próximo, nunca < 0.
  begin
    select count(*), count(*) filter (where m.atraso_cliente_du <= 0),
           array_agg(m.atraso_cliente_du::numeric),
           coalesce(jsonb_agg(jsonb_build_object('os', m.service_order_id, 'numero', so.service_order_number,
                                                 'primeiro', m.prometido_primeiro_ate, 'concluida', m.concluida_em,
                                                 'atraso_du', m.atraso_cliente_du)
                              order by m.concluida_em desc, so.service_order_number), '[]'::jsonb)
      into v_n, v_ok, v_vals, v_amos
      from public.agenda_medidas_os m
      join public.service_orders so on so.id = m.service_order_id
     where m.concluida_em between v_de and p_hoje
       and m.motivo is distinct from 'reaberta'
       and m.prometido_primeiro_ate is not null and m.atraso_cliente_du is not null;
    v_p := public._agenda_percentil(v_vals, c.fator_percentil);
    v_calc := case when v_n > 0 then round(v_ok::numeric / v_n, 2) end;
    v_pont := public._agenda_aprendizado_gravar('cliente_pontualidade', 'todas', 'todas', v_calc, v_n, v_amos, null,
                jsonb_build_object('n', v_n, 'no_prazo', v_ok,
                                   'p80_atraso_du', case when v_p is not null then greatest(0, round(v_p)) end),
                p_agora);
  exception when others then
    perform public.log_app_error('db', format('aprendizado, pontualidade com o cliente: %s', sqlerrm), 'agenda',
                                 'aprender:cliente', 'error',
                                 jsonb_build_object('item', 'cliente_pontualidade', 'sqlstate', sqlstate, 'p_hoje', p_hoje));
    n_err := n_err + 1;
  end;

  -- (b) A folga do aviso de atraso: nas OS com aviso de atraso enviado (e com a faixa dele), quantos dias úteis o serviço
  -- terminou depois do fim da faixa; o P80, ao dia útil mais próximo, preso em [0, aviso_folga_max_du]. O padrão é 0 (a
  -- faixa do plano, sem folga).
  begin
    select count(*), count(*) filter (where m.aviso_estouro_du <= 0),
           array_agg(m.aviso_estouro_du::numeric),
           coalesce(jsonb_agg(jsonb_build_object('os', m.service_order_id, 'numero', so.service_order_number,
                                                 'faixa_ate', m.aviso_faixa_ate, 'concluida', m.concluida_em,
                                                 'avisos', m.avisos_enviados, 'estouro_du', m.aviso_estouro_du)
                              order by m.concluida_em desc, so.service_order_number), '[]'::jsonb)
      into v_n, v_ok, v_vals, v_amos
      from public.agenda_medidas_os m
      join public.service_orders so on so.id = m.service_order_id
     where m.concluida_em between v_de and p_hoje
       and m.motivo is distinct from 'reaberta'
       and m.avisos_enviados > 0 and m.aviso_faixa_ate is not null and m.aviso_estouro_du is not null;
    v_p := public._agenda_percentil(v_vals, c.fator_percentil);
    v_calc := case when v_p is not null then least(c.aviso_folga_max_du, greatest(0, round(v_p))) end;
    v_aviso := public._agenda_aprendizado_gravar('aviso_folga', 'todas', 'todas', v_calc, v_n, v_amos, 0,
                 jsonb_build_object('n', v_n, 'no_prazo', v_ok, 'p50', public._agenda_percentil(v_vals, 0.5),
                                    'maior', (select max(x) from unnest(v_vals) x)),
                 p_agora);
  exception when others then
    perform public.log_app_error('db', format('aprendizado, folga do aviso ao cliente: %s', sqlerrm), 'agenda',
                                 'aprender:cliente', 'error',
                                 jsonb_build_object('item', 'aviso_folga', 'sqlstate', sqlstate, 'p_hoje', p_hoje));
    n_err := n_err + 1;
  end;

  return jsonb_build_object('pontualidade', v_pont, 'aviso_folga', v_aviso, 'erros', n_err);
end;
$function$;

comment on function public._agenda_aprender_cliente(date, timestamptz) is
  'Agenda de Produção (Fase 6, P5): o passo do cliente da rodada — pelo gravador, nas medidas das OS concluídas na janela (aprender_janela_dias; sem a reaberta): cliente_pontualidade (chave todas; só medida, nunca em uso) = a fração das OS com a 1ª promessa (prometido_primeiro_ate) prontas até ela, n ≥ cliente_n_min, detalhe {n, no_prazo, p80_atraso_du}; aviso_folga (chave todas; padrão 0) = o P80 (fator_percentil) de quantos dias úteis o serviço passou do fim da faixa do último aviso de atraso enviado, ao dia útil mais próximo, preso em [0, aviso_folga_max_du], n ≥ aviso_n_min, detalhe {n, no_prazo, p50, maior}. Cada item no seu bloco (o erro vai a app_error_logs agenda / aprender:cliente). {pontualidade, aviso_folga, erros}. Sem grant a ninguém.';

-- ── 4. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 6:") ──────────────────
-- Fora dos blocos nenhuma linha muda (o C5 do teste confere). Quem recriar de novo qualquer uma delas copia DESTA migration.

-- _agenda_cliente_gravar_prometido (de 20261028100100_agenda_fase5_textos.sql)
create or replace function public._agenda_cliente_gravar_prometido(p_os uuid, p_tipo text, p_de date, p_ate date,
                                                                   p_fonte text, p_mensagem uuid, p_agora timestamptz,
                                                                   p_trecho text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  p        public.os_planejamento%rowtype;
  v_de     date := least(coalesce(p_de, p_ate), coalesce(p_ate, p_de));
  v_ate    date := greatest(coalesce(p_de, p_ate), coalesce(p_ate, p_de));
  v_antes  jsonb;
  v_depois jsonb;
begin
  if p_tipo not in ('condicional', 'faixa', 'firme') or v_ate is null then
    raise exception using errcode = '22023', message = 'O que foi dito ao cliente precisa do tipo e do dia.';
  end if;
  insert into public.os_planejamento (service_order_id) values (p_os) on conflict (service_order_id) do nothing;
  select * into p from public.os_planejamento where service_order_id = p_os for update;
  v_antes := jsonb_build_object('prometido_tipo', p.prometido_tipo, 'prometido_de', p.prometido_de,
                                'prometido_ate', p.prometido_ate, 'prometido_fonte', p.prometido_fonte);
  v_depois := jsonb_build_object('prometido_tipo', p_tipo, 'prometido_de', v_de, 'prometido_ate', v_ate,
                                 'prometido_fonte', p_fonte);
  update public.os_planejamento
     set prometido_tipo = p_tipo, prometido_de = v_de, prometido_ate = v_ate,
         prometido_original_ate = coalesce(p.prometido_original_ate, v_ate),
         -- FASE 6: (P5) a 1ª data dita ao cliente (NOVO-agenda-44; spec-fase6 §5.5): grava na 1ª vez e depois não muda. O
         -- aviso "ainda faltam peças sem data" (_agenda_cliente_tirar_prometido) zera o prometido e o original, não esta: a
         -- promessa seguinte acha a de antes aqui (a linha anterior à Fase 6 tem o original, ou o preenchimento da migration)
         prometido_primeiro_ate = coalesce(p.prometido_primeiro_ate, p.prometido_original_ate, v_ate),
         -- FASE 6: fim
         prometido_em = p_agora, prometido_fonte = p_fonte, prometido_mensagem_id = p_mensagem,
         historico = public._os_material_historico(p.historico, jsonb_build_object(
           'em', (p_agora at time zone 'America/Sao_Paulo')::date, 'autor', null,
           'trecho', public._agenda_corta(p_trecho, 500), 'antes', v_antes, 'depois', v_depois)),
         atualizado_em = p_agora
   where service_order_id = p_os;
  return jsonb_build_object('gravou', true, 'os', p_os, 'tipo', p_tipo, 'de', v_de, 'ate', v_ate,
                            'original_ate', coalesce(p.prometido_original_ate, v_ate),
                            'primeira_promessa', p.prometido_original_ate is null);
end;
$function$;

comment on function public._agenda_cliente_gravar_prometido(uuid, text, date, date, text, uuid, timestamptz, text) is
  'Agenda de Produção (Fase 5): grava o que foi dito ao cliente em os_planejamento (prometido_tipo/de/ate/em/fonte/mensagem_id), criando a linha da OS só com isso quando não existe. prometido_original_ate = o prometido_ate da 1ª vez (depois não muda). O histórico ganha {em, autor, trecho, antes, depois} (20 no máximo). Interna (sem grant): a chamam o envio (_agenda_cliente_prometer), o botão antigo (_agenda_cliente_prometer_confirmacao) e o *grava* do dono (P5). FASE 6 (P5): prometido_primeiro_ate = a 1ª data dita (coalesce do que já estava, do original e do de agora) — grava na 1ª vez e nunca zera (o aviso sem data zera o original, não ela; NOVO-agenda-44).';

-- _agenda_cliente_risco (de 20261028100800_agenda_fase5_correcao_rodada.sql)
create or replace function public._agenda_cliente_risco(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  p       public.os_planejamento%rowtype;
  v_status text;
  v_plano jsonb;
  v_pront jsonb;
  v_crit  jsonb;
  v_m     jsonb;
  v_conf  text;
  v_peca  date;
  v_n     int;
  v_causa text;
  v_tipo  text;
  v_var   text;
  v_de    date;
  v_ate   date;
  v_novo  date;
  v_est   boolean := false;
  -- FASE 6: o fator de campo da OS (o limiar do estouro) e a folga do aviso (em dias úteis)
  v_fat   numeric;
  v_folga int;
  -- FASE 6: fim
begin
  select * into p from public.os_planejamento where service_order_id = p_os;
  if not found or p.prometido_ate is null then
    return null;
  end if;
  select so.status into v_status from public.service_orders so where so.id = p_os;
  if v_status is null
     or v_status not in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client') then
    return null;
  end if;
  v_plano := public._agenda_plano_da_os(p_os, p_hoje);
  v_pront := public.os_prontidao(p_os, p_hoje);
  select coalesce(jsonb_agg(e), '[]'::jsonb) into v_crit
    from jsonb_array_elements(coalesce(v_pront #> '{material,itens}', '[]'::jsonb)) e
   where coalesce((e ->> 'critico')::boolean, false) and e ->> 'nivel' <> 'A';

  if jsonb_array_length(v_crit) > 0 then
    v_causa := 'material';
    v_var := 'peca';
    v_conf := v_pront #>> '{material,confianca}';
    v_tipo := case when v_conf in ('A', 'B') then 'faixa' else 'condicional' end;
    select max((e ->> 'data')::date) into v_peca from jsonb_array_elements(v_crit) e where e ->> 'data' is not null;
    v_n := greatest(1, ceil(coalesce((v_pront #>> '{duracao,dias}')::numeric, (v_plano ->> 'dias')::numeric, 1))::int);
    if v_peca is not null then
      v_de := public.agenda_somar_du(v_peca, cf.folga_material_du);
      v_ate := public.agenda_somar_du(v_peca, cf.folga_material_du + v_n - 1);
      v_novo := v_ate;
    end if;
  elsif v_status = 'in_progress' then
    v_causa := 'execucao';
    v_var := 'execucao';
    v_tipo := 'faixa';
    v_m := public.agenda_meios_da_os(p_os, p_hoje);
    v_est := coalesce(v_m ->> 'fonte' in ('dono', 'aceita'), false) and coalesce((v_m ->> 'total')::numeric, 0) > 0
             and coalesce((v_m ->> 'cumpridos')::numeric, 0) > cf.estouro_fator * (v_m ->> 'total')::numeric;
    -- FASE 6: (P5) o limiar do estouro é o fator de campo da classe da OS (spec-fase6 §5.5; o mesmo da vigia do P2): só com
    -- o modo de aprendizado ligado e "fator" na lista (fora disso o fator é estouro_fator e nem é lido: a linha de cima vale,
    -- byte a byte). agenda_fator_de_campo é de admin/financeiro e do service_role: quem chega aqui sem ler o aprendizado (o
    -- técnico — _agenda_cliente_risco é de authenticated) recebe 42501, e fica com o padrão, como a RLS faria
    v_fat := cf.estouro_fator;
    if cf.modo_aprendizado = 'ligado' and 'fator' = any (cf.aprendizado_ligados) then
      begin
        v_fat := coalesce((public.agenda_fator_de_campo(p_os, p_hoje) ->> 'fator')::numeric, cf.estouro_fator);
      exception when insufficient_privilege then
        v_fat := cf.estouro_fator;
      end;
    end if;
    v_est := coalesce(v_m ->> 'fonte' in ('dono', 'aceita'), false) and coalesce((v_m ->> 'total')::numeric, 0) > 0
             and coalesce((v_m ->> 'cumpridos')::numeric, 0) > v_fat * (v_m ->> 'total')::numeric;
    -- FASE 6: fim
    v_novo := greatest(coalesce((v_plano ->> 'ultimo_dia')::date, p_hoje),
                       case when v_est then public.agenda_somar_du(p_hoje, 1) end);
    v_de := v_novo;
    v_ate := public.agenda_somar_du(v_novo, 1);
  elsif (v_plano ->> 'proximo_dia') is not null and (v_plano ->> 'ultimo_dia') is not null then
    v_causa := 'replano';
    v_var := 'remarcado';
    v_tipo := 'firme';
    v_de := (v_plano ->> 'proximo_dia')::date;
    v_ate := (v_plano ->> 'ultimo_dia')::date;
    v_novo := v_ate;
  end if;

  -- CORREÇÃO FASE 5: (item 8) peça crítica ainda SEM data de chegada (algum crítico fora de A sem previsão, com outro que
  -- tem): a variante peca_sem_data, condicional, sem data nenhuma ao cliente (d09) — a faixa dos críticos com data fica
  -- aqui, para o dono e para a chave, mas não vai ao texto. (item 6) o remarcado com o MESMO início que o cliente ouviu (só o
  -- fim mudou): forma fim. (item 23) o 2º atraso conta só os avisos de atraso e as novas datas que SAÍRAM — o dia que o
  -- próprio cliente pediu (o prometido_original menor) não é atraso
  if v_causa = 'material' and v_peca is not null
     and exists (select 1 from jsonb_array_elements(v_crit) e where e ->> 'data' is null) then
    v_var := 'peca_sem_data';
    v_tipo := 'condicional';
  end if;
  -- FASE 6: (P5) a folga do aviso (spec-fase6 §5.5): o quanto os avisos de atraso erraram para menos (aviso_folga em uso:
  -- só com o modo ligado e "aviso_cliente" na lista; nulo = 0) entra no fim da faixa da peça e da execução, em dias úteis. O
  -- início da faixa (o dia da mensagem e a chave dela), o fim novo, o risco e o atraso não mudam; o remarcado firme e o
  -- peca_sem_data também não
  if v_var in ('peca', 'execucao') and v_ate is not null then
    v_folga := coalesce(round(public._agenda_aprendido('aviso_folga', 'todas'))::int, 0);
    if v_folga > 0 then
      v_ate := public.agenda_somar_du(v_ate, v_folga);
    end if;
  end if;
  -- FASE 6: fim
  return jsonb_build_object(
    'risco', coalesce(v_novo > p.prometido_ate, v_causa = 'material' and v_novo is null),
    'causa', v_causa, 'tipo', v_tipo, 'variante', v_var,
    'forma', case when v_causa = 'replano' and v_de = coalesce(p.prometido_de, p.prometido_ate) then 'fim' end,
    'faixa_de', v_de, 'faixa_ate', v_ate, 'fim_novo', v_novo, 'peca', v_peca, 'estouro', v_est,
    'dito_de', coalesce(p.prometido_de, p.prometido_ate), 'dito_ate', p.prometido_ate,
    'atraso_dias', v_novo - p.prometido_ate, 'atraso_du', public.agenda_du_entre(p.prometido_ate, v_novo),
    'passou', p.prometido_ate < p_hoje,
    'sem_data', v_causa = 'material' and v_novo is null,
    'segundo', exists (select 1 from public.agenda_cliente_mensagens m
                        where m.service_order_id = p_os and m.tipo in ('pode_atrasar', 'nova_data')
                          and m.enviada_em is not null));
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object(
    'risco', coalesce(v_novo > p.prometido_ate, v_causa = 'material' and v_novo is null),
    'causa', v_causa, 'tipo', v_tipo, 'variante', v_var,
    'faixa_de', v_de, 'faixa_ate', v_ate, 'fim_novo', v_novo, 'peca', v_peca, 'estouro', v_est,
    'dito_de', coalesce(p.prometido_de, p.prometido_ate), 'dito_ate', p.prometido_ate,
    'atraso_dias', v_novo - p.prometido_ate, 'atraso_du', public.agenda_du_entre(p.prometido_ate, v_novo),
    'passou', p.prometido_ate < p_hoje,
    'sem_data', v_causa = 'material' and v_novo is null,
    'segundo', coalesce(p.prometido_original_ate < p.prometido_ate, false)
               or exists (select 1 from public.agenda_cliente_mensagens m
                           where m.service_order_id = p_os and m.tipo in ('pode_atrasar', 'nova_data')
                             and m.enviada_em is not null));
end;
$function$;

comment on function public._agenda_cliente_risco(uuid, date) is
  'Agenda de Produção (Fase 5, P3): a data que o cliente ouviu (os_planejamento.prometido_*) ainda vale? null sem prometido_ate ou com a OS fora das ativas. {risco, causa (material: algum crítico fora de A — a chegada mais tarde dos críticos com data + folga_material_du dias úteis + os dias da OS, tipo faixa com o pior nível em A/B, senão condicional, sem data = sem_data; execucao: em andamento, o fim do plano, ou amanhã com o estouro; replano: o plano publicado com o material na mão, firme), tipo, variante (peca, execucao, remarcado), faixa_de, faixa_ate, fim_novo, peca, dito_de, dito_ate, atraso_dias (corridos), atraso_du (dias úteis), passou (prometido_ate antes de p_hoje), sem_data, segundo (já houve aviso de atraso ou nova data enviados, ou o prometido de agora passou do original)}. risco = o fim novo depois do prometido_ate. CORREÇÃO FASE 5 (C2): (item 8) variante peca_sem_data (condicional) quando algum crítico fora de A não tem data e outro tem; (item 6) forma = fim no replano com o mesmo início que o cliente ouviu; (item 23) segundo = só um aviso de atraso ou uma nova data já ENVIADOS nesta OS. FASE 6 (P5): na execução, o estouro usa o fator de campo da OS (agenda_fator_de_campo: só com modo_aprendizado ligado e fator na lista; quem não o lê fica com estouro_fator); nas variantes peca e execucao, faixa_ate ganha a folga do aviso (aviso_folga em uso, em dias úteis; nulo = 0). faixa_de, fim_novo, risco, atraso, o remarcado e o peca_sem_data não mudam.';

-- _agenda_aprendizado_texto (de 20261029100400_agenda_fase6_dono.sql)
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
  -- FASE 6: (P5) a pontualidade com o cliente (só medida: só a linha do foco) e a folga do aviso de atraso (spec-fase6 §6.2
  -- e §6.3). A pontualidade lê detalhe.no_prazo e detalhe.p80_atraso_du; a folga é a faixa do aviso "com 2 dias úteis a mais"
  -- (0 = a faixa do plano, o padrão)
  if p_item = 'cliente_pontualidade' and p_momento like 'foco_%' then
    if p_momento = 'foco_medindo' then
      return format('Pontualidade: %s de %s OS com a 1ª data dita ao cliente medidas.', v_n, v_nmin);
    end if;
    return format('Pontualidade: %s de %s OS ficaram prontas até o dia dito primeiro ao cliente%s.',
                  coalesce(p_d #>> '{detalhe,no_prazo}', '0'), v_n,
                  case when coalesce((p_d #>> '{detalhe,p80_atraso_du}')::numeric, 0) > 0
                       then '; o atraso chega a ' || public._agenda_aprendizado_valor('aviso_folga', (p_d #>> '{detalhe,p80_atraso_du}')::numeric)
                       else '' end);
  end if;
  if p_item = 'aviso_folga' then
    declare
      v_cn numeric := coalesce((p_d ->> 'calculado')::numeric, 0);
      -- "a faixa com 2 dias úteis a mais" / "a faixa do plano", de cada valor
      v_fc text := case when coalesce((p_d ->> 'calculado')::numeric, 0) > 0 then format('a faixa com %s a mais', v_calc)
                        else 'a faixa do plano' end;
      v_fu text := case when coalesce((p_d ->> 'em_uso')::numeric, 0) > 0 then format('a faixa com %s a mais', v_uso)
                        else 'a faixa do plano' end;
      v_fe text := case when coalesce((p_d ->> 'efetivo')::numeric, (p_d ->> 'padrao')::numeric, 0) > 0
                        then format('a faixa com %s a mais',
                                    public._agenda_aprendizado_valor('aviso_folga', coalesce((p_d ->> 'efetivo')::numeric, (p_d ->> 'padrao')::numeric)))
                        else 'a faixa do plano' end;
      v_fv text := case when coalesce((p_d ->> 'volta')::numeric, (p_d ->> 'padrao')::numeric, 0) > 0
                        then format('a faixa com %s a mais',
                                    public._agenda_aprendizado_valor('aviso_folga', coalesce((p_d ->> 'volta')::numeric, (p_d ->> 'padrao')::numeric)))
                        else 'a faixa do plano' end;
      v_terminou text := case when coalesce((p_d ->> 'calculado')::numeric, 0) > 0
                              then format('o serviço terminou até %s depois do fim que eu disse', v_calc)
                              else 'o serviço terminou dentro da faixa que eu disse' end;
    begin
      return case p_momento
        when 'foco_medindo' then format('Avisos de atraso: %s de %s avisos medidos; dou %s (padrão).', v_n, v_nmin, v_fe)
        when 'foco_sombra' then format('Avisos de atraso: em %s, %s (em teste: eu daria %s).', v_n, v_terminou, v_fc)
        when 'foco_em_uso' then format('Avisos de atraso: em %s, %s: dou %s desde %s.', v_n, v_terminou, v_fu, v_desde)
        when 'foco_pergunta' then format('Avisos de atraso: em %s, %s, e hoje dou %s: a troca espera a sua resposta.',
                                         v_n, v_terminou, v_fe)
        when 'foco_travado' then format('Avisos de atraso: em %s, %s; fico com %s até %s, como você decidiu.',
                                        v_n, v_terminou, v_fe, v_trava)
        when 'acao' then format('Os avisos de atraso erraram para %s (%s avisos): passei a dar %s%s. *desfaz aprendizado* volta.',
                                case when v_cn > coalesce((p_d ->> 'efetivo')::numeric, 0) then 'menos' else 'mais' end,
                                v_n, v_fc,
                                case when coalesce((p_d ->> 'efetivo')::numeric, 0) > 0 then format(' (era %s)', v_fe) else '' end)
        when 'pergunta' then format('Medi os avisos de atraso: em %s, %s, e hoje eu dou %s. É uma troca grande.', v_n, v_terminou, v_fe)
        when 'opcao1' then format('Passo a dar %s', v_fc)
        when 'opcao2' then format('Fico com %s', v_fe)
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: volto a dar %s. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                    v_fv, v_dias)
        when 'fico' then format('Combinado: fico com %s. Volto a perguntar se o medido mudar muito.', v_fe)
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
  'Agenda de Produção (Fase 6): os textos do aprendizado ao dono, do banco — p_momento foco_<estado> (a linha do foco), acao (o que mudou sozinho), pergunta (a troca grande, sem as opções), opcao1/2/3, desfeito e fico. p_d: {chave, calculado, em_uso, efetivo (o que valia antes), padrao, volta, n, n_min, desde, travado_ate, trava_dias}. O fator tem os textos da spec-fase6 §6.2/§6.3; os outros itens, um texto provisório que o pacote de cada um recria (copiar DESTA definição). FASE 6 (P2): o R$ por diária (mo) e a presença do dono têm os textos da spec §6.2/§6.3 (a presença lê detalhe.k, as idas do dono). FASE 6 (P3): o atraso (fornecedor_atraso) e o prazo da nota (fornecedor_prazo) têm os textos da spec §6.2/§6.3 (o nome, as entregas no prazo e o "você disse" vêm do detalhe). FASE 6 (P4): a capacidade do dono (capacidade_dono) tem os textos da spec §6.2/§6.3 ("Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus marcados no plano …"; a taxa e a janela vêm do detalhe). FASE 6 (P5): a pontualidade com o cliente (cliente_pontualidade: só a linha do foco, "Pontualidade: 5 de 7 OS ficaram prontas até o dia dito primeiro ao cliente; o atraso chega a 2 dias úteis.") e a folga do aviso de atraso (aviso_folga: "a faixa com 2 dias úteis a mais"; 0 = a faixa do plano) têm os textos da spec §6.2/§6.3.';

-- ── 5. A 1ª promessa das linhas que já existem ───────────────────────────────────────────────────────────
-- Em produção, nenhuma (prometido_* nasce com a Fase 5, publicada junto). Na ordem: o prometido_original_ate de antes do 1º
-- aviso "ainda faltam peças sem data" que o histórico guarda (o _agenda_cliente_tirar_prometido grava o de antes em
-- antes.prometido_original_ate); senão o prometido_original_ate de agora; senão a 1ª data gravada no histórico
-- (depois.prometido_ate do _agenda_cliente_gravar_prometido). Só onde a coluna é nula: rodar 2× não muda nada.
update public.os_planejamento pl
   set prometido_primeiro_ate = x.primeiro
  from (select p.service_order_id,
               coalesce(
                 (select (h.e #>> '{antes,prometido_original_ate}')::date
                    from jsonb_array_elements(case when jsonb_typeof(p.historico) = 'array' then p.historico
                                                   else '[]'::jsonb end) with ordinality h(e, o)
                   where h.e #>> '{antes,prometido_original_ate}' is not null
                   order by h.o limit 1),
                 p.prometido_original_ate,
                 (select (h.e #>> '{depois,prometido_ate}')::date
                    from jsonb_array_elements(case when jsonb_typeof(p.historico) = 'array' then p.historico
                                                   else '[]'::jsonb end) with ordinality h(e, o)
                   where h.e #>> '{depois,prometido_ate}' is not null
                   order by h.o limit 1)) as primeiro
          from public.os_planejamento p
         where p.prometido_primeiro_ate is null) x
 where pl.service_order_id = x.service_order_id
   and pl.prometido_primeiro_ate is null
   and x.primeiro is not null;


-- ── 9. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- O passo da rodada: sem grant a ninguém, nem service_role (quem chama é a rodada do P6, agenda_aprender, definer).
revoke all on function public._agenda_aprender_cliente(date, timestamptz) from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas de antes (create or replace não as muda; repetidas aqui para a migration valer sozinha).
-- O gravador do prometido: ninguém de fora (nem service_role) — só as funções security definer da agenda o chamam.
revoke all on function public._agenda_cliente_gravar_prometido(uuid, text, date, date, text, uuid, timestamptz, text)
  from public, anon, authenticated, service_role;
-- O risco e os textos do aprendizado: authenticated (a tela e o foco, com a RLS de quem lê) e service_role; nunca anon.
revoke all on function public._agenda_cliente_risco(uuid, date), public._agenda_aprendizado_texto(text, text, jsonb)
  from public, anon;
grant execute on function public._agenda_cliente_risco(uuid, date), public._agenda_aprendizado_texto(text, text, jsonb)
  to authenticated, service_role;

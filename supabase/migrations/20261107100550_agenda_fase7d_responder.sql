-- Agenda de Produção, Fase 7, etapa 7d ("onde, quando e com o bem em que estado"), pacote P6b: a pergunta com opções ganha resposta pela conversa
-- (o conserto do NOVO-agenda-91). Não está na spec: o pedido do fio principal é a spec (06/11/2026). Inventário e decisões: notas-fase7d.md, seção P6b.
-- Depende de 20261107100000 a 20261107100500.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (3 funções recriadas e 1 nova; nenhuma tabela, nenhuma coluna, nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7d/p6b/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (o montador para
-- se outra migration a definir depois da origem). agenda_rascunho_aplicar só ganha blocos "-- FASE 7d: … -- FASE 7d: fim" inseridos: tirados os blocos, é a de
-- 20261025100400, byte a byte. _agenda_ver_decisoes troca o miolo do bloco do P5. agenda_decisoes_abertas troca 3 linhas. O R0 de
-- supabase/tests/agenda_fase7d_responder.sql confere as três.
--
-- ESTE PACOTE MUDA O QUE O DONO VÊ HOJE, DE PROPÓSITO, AO CONTRÁRIO DO RESTO DA 7d. Só muda isto: quem tem opções, tem quem decida a opção e está ligado passa a ter
-- número e resposta. Nada novo a cliente ou equipe; nenhuma pergunta nasce nem fecha por causa disso.
--
-- POR QUE: agenda_rascunho_aplicar só acha decisão em agenda_decisoes_abertas, e essa lista filtrava q.critica. As perguntas com opções e não críticas pediam "responda
-- em *agenda pendências*", apareciam ali sem número, como "Também quero saber: …", e a resposta "1" dava "Não tenho decisão da agenda esperando você agora".
--
-- O QUE MUDA:
--   1. agenda_decisoes_abertas: entram as não críticas com opções cujo tipo tem efeito em agenda_decidir (lista fechada: combinar, local, situacao, estimativa, reavaliar,
--      reestimar, ficha_estimativa, dias_semana, equipe_cadastro, diaria_ligar). As críticas vêm PRIMEIRO: "Decisão 1" não muda para quem já tem crítica aberta. A que o dono
--      já respondeu "eu digo os dias" (opcao_escolhida) não ganha número: falta o fato, não a opção. A não crítica que não traz as opções no texto (diaria_ligar: "Me
--      responda aqui.") ganha as opções no fim, senão o número não teria o que responder.
--   2. _agenda_ver_decisoes: quem tem número sai de "Também quero saber", pelo id: uma pergunta nunca aparece duas vezes.
--   3. agenda_rascunho_aplicar: o que entrou na lista não pode virar pergunta errada aplicada (o "1" é o maior risco do pacote):
--      a. outra pergunta com opções e sem número (nfe_vincular, previsao_fornecedor) também conta como "esperando": com uma decisão só na lista, "1" pergunta qual;
--      b. com mais de uma esperando, os 2 números (ou o nome e a opção) têm de estar nas palavras do dono (_agenda_disse_os_numeros): "1" sozinho nunca vira decisão 1, opção 1;
--      c. a releitura da não crítica diz de qual pergunta é a opção: "Decisão: Está certo." não bastava para o *grava*;
--      d. a não crítica cujo modo não vale agora (o freio, em situacao, estimativa, reavaliar e reestimar) é recusada aqui, e não no *grava* com "a agenda mudou";
--      e. só com pergunta sem número: a recusa diz que é por palavras, em vez de "Não tenho decisão da agenda esperando você agora".
--   4. _agenda_disse_os_numeros (nova): os 2 números estão nas palavras do dono? Só agenda_rascunho_aplicar chama.
--
-- O QUE FICA DE FORA: nfe_vincular e previsao_fornecedor têm opções, mas agenda_decidir não sabe o que fazer com elas ("Essa pergunta não é de decisão."): a resposta é
-- material_informar com o aviso (agenda_rascunho_material). Seguem em "Também quero saber". NOVO-agenda-91 fica aberto só nisso.
--
-- O QUE NÃO MUDA: a tela (agenda_tela_semana só lê a lista, e "Esperando a sua decisão" continua verdade: front igual); o fechamento, a saúde, a carona e os avisos, que não
-- leem a lista; o motor e a vigia (a lista não está em nenhum caminho de tique); as críticas (a mesma ordem entre elas, a mesma releitura); _agenda_chave_telefone,
-- agenda_dia_util, agenda_somar_du, agenda_feriado, _agenda_cliente_dia e _agenda_nome_curto, que a sessão do retorno chama; nada em _shared/ai/prompt.ts (é do P8).
--
-- O FREIO (R6.7b): q.modo = 'ligado' continua sendo o filtro da lista, e nenhum caminho novo marca dia. Com *gestor, só propor*, situacao, estimativa, reavaliar e reestimar
-- têm número, mas a resposta é recusada como sempre foi (_agenda_gestor_decidir); as outras seguem respondíveis, e nenhuma delas mexe no plano.
--
-- PROVA: supabase/tests/agenda_fase7d_responder.sql na bancada (node scripts/bancada-agenda/rodar.mjs). APLICAR: só pelo roteiro de publicação da 7d, depois da
-- 20261107100500 e antes da 20261107100600. IDEMPOTENTE: create or replace function, revoke e comment.
--
-- DESFAZER: recriar agenda_decisoes_abertas e _agenda_ver_decisoes de 20261107100500 e agenda_rascunho_aplicar de 20261025100400; drop de _agenda_disse_os_numeros.
-- Quem recriar depois uma destas copia DESTA migration.

-- ── 1. As palavras do dono ─────────────────────────────────────────────────────────────────

-- Os 2 números estão nas palavras do dono? Com várias perguntas esperando, "1" sozinho não diz decisão nem opção: quando os 2 são iguais, ele tem de aparecer 2 vezes.
-- Sem a decisão (dita pelo nome), só a opção.
create or replace function public._agenda_disse_os_numeros(p_trecho text, p_decisao integer, p_opcao integer)
 returns boolean
 language sql
 immutable
 set search_path to 'public'
as $function$
  with d as (
    select case w when 'um' then 1 when 'uma' then 1 when 'primeira' then 1 when 'primeiro' then 1
                  when 'dois' then 2 when 'duas' then 2 when 'segunda' then 2 when 'segundo' then 2
                  when 'tres' then 3 when 'terceira' then 3 when 'terceiro' then 3
                  when 'quatro' then 4 when 'cinco' then 5
                  else case when w ~ '^\d{1,3}$' then w::int end end as n
      from regexp_split_to_table(public._agenda_normal(p_trecho), '[ /]+') w
  )
  select case when p_decisao is null then exists (select 1 from d where d.n = p_opcao)
              when p_decisao = p_opcao then (select count(*) from d where d.n = p_decisao) >= 2
              else exists (select 1 from d where d.n = p_decisao) and exists (select 1 from d where d.n = p_opcao) end;
$function$;

comment on function public._agenda_disse_os_numeros(text, integer, integer) is
  'Agenda de Produção (Fase 7d, P6b): os 2 números (a decisão e a opção) estão nas palavras do dono, em algarismo ou por extenso? Iguais, têm de aparecer 2 vezes: "1" sozinho não é a decisão 1, opção 1. Só agenda_rascunho_aplicar chama, com mais de uma pergunta esperando. "A segunda" conta como 2: o erro para esse lado passa ao *grava*, com a releitura; quarta e quinta não contam (são dias).';

-- ── 2. As recriadas ────────────────────────────────────────────────────────────────────────

-- agenda_decisoes_abertas (de 20261107100500_agenda_fase7d_cliente.sql): 3 linhas trocadas (o texto, a ordem e o where)
create or replace function public.agenda_decisoes_abertas(p_agora timestamptz default now())
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'n', x.n, 'id', x.id, 'tipo', x.tipo, 'os', x.service_order_id, 'os_ids', to_jsonb(x.os_ids),
           'texto', case when x.critica or x.texto ~ '(^|\s)\d\)\s' or jsonb_array_length(x.opcoes) < 2 then x.texto
                         else x.texto || ' ' || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                                                   from jsonb_array_elements(x.opcoes) o) || '.' end,
           'opcoes', x.opcoes, 'recomendacao', x.recomendacao, 'recomendacao_texto', x.recomendacao_texto,
           'perda_em', x.perda_em, 'versao_base', x.versao_base) order by x.n), '[]'::jsonb)
    from (select q.*, row_number() over (order by (not q.critica), q.perda_em nulls last, q.criada_em, q.id) as n
            from public.agenda_perguntas q
           where (q.critica
                  or (q.tipo in ('combinar', 'local', 'situacao', 'estimativa', 'reavaliar', 'reestimar', 'ficha_estimativa', 'dias_semana',
                                 'equipe_cadastro', 'diaria_ligar')
                      and q.opcao_escolhida is null
                      and case when jsonb_typeof(q.opcoes) = 'array' then jsonb_array_length(q.opcoes) > 0 else false end))
             and q.estado = 'aberta' and q.modo = 'ligado'
             and (q.expira_em is null or q.expira_em > p_agora)) x;
$function$;

comment on function public.agenda_decisoes_abertas(timestamptz) is
  'Agenda de Produção (Fase 2, P4): as decisões críticas abertas (modo ligado) numeradas — n = 1 é a que perde primeiro (perda_em, depois a mais antiga). [{n, id, tipo, os, os_ids, texto, opcoes, recomendacao, recomendacao_texto, perda_em, versao_base}]. O rascunho resolve "a 1" por aqui; agenda_ver (foco decisoes) numera igual. FASE 7d (P5): a pergunta combinar (não crítica, com opções) entra na lista: é só por aqui que uma pergunta chega a agenda_decidir pela conversa e pela tela. FASE 7d (P6): a pergunta local também entra: ela tem opções e nasce da resposta do cliente. FASE 7d (P6b, NOVO-agenda-91): a lista passa a levar as não críticas com opções cujo tipo tem efeito em agenda_decidir (combinar, local, situacao, estimativa, reavaliar, reestimar, ficha_estimativa, dias_semana, equipe_cadastro, diaria_ligar), sem a opção já escolhida. As críticas vêm primeiro: entre elas, a numeração de antes; depois as outras, pela mesma régua. opcoes que não é lista não entra (a guarda em case: jsonb_array_length lança em não-lista). nfe_vincular e previsao_fornecedor ficam de fora: agenda_decidir não as decide, a resposta é material_informar. A não crítica que não traz as opções no texto ganha as opções no fim.';

-- _agenda_ver_decisoes (de 20261107100500_agenda_fase7d_cliente.sql): o miolo do bloco do P5
create or replace function public._agenda_ver_decisoes(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_dec   jsonb := public.agenda_decisoes_abertas(p_agora);
  v_l     text[] := '{}';
  v_outra text[];
  v_som   text[];
  e       jsonb;
begin
  for e in select x from jsonb_array_elements(v_dec) x loop
    -- FASE 3: a da diária com as opções, a recomendação e as palavras
    v_l := v_l || format('Decisão %s: %s', e ->> 'n',
                         case when e ->> 'tipo' = 'diaria' then public._agenda_texto_da_diaria((e ->> 'id')::uuid) else e ->> 'texto' end);
  end loop;
  v_outra := array(select q.texto from public.agenda_perguntas q
                    where not q.critica and q.estado = 'aberta' and q.modo = 'ligado'
                      -- FASE 7d: (7d P5, P6, P6b) quem tem número já vem em v_dec (agenda_decisoes_abertas): pelo id, uma pergunta nunca aparece duas vezes. Quem não tem
                      -- número (sem opções, sem efeito em agenda_decidir ou com a opção já dita) segue aqui, como antes.
                      and not exists (select 1 from jsonb_array_elements(v_dec) x where x ->> 'id' = q.id::text)
                      -- FASE 7d: fim
                      and (q.expira_em is null or q.expira_em > p_agora)
                    order by q.perda_em nulls last, q.criada_em, q.id);
  if jsonb_array_length(v_dec) > 0 then
    v_l := array[case when jsonb_array_length(v_dec) = 1 then 'Uma decisão espera você na agenda:'
                      else format('%s decisões esperam você na agenda:', jsonb_array_length(v_dec)) end]
           || v_l
           || 'Para responder, diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2"). Eu não escolho por você.'::text;
  end if;
  if cardinality(v_outra) > 0 then
    v_l := v_l || array(select 'Também quero saber: ' || x from unnest(v_outra) with ordinality u(x, o) order by o);
  end if;
  if cardinality(v_l) = 0 then
    v_som := array(select q.texto from public.agenda_perguntas q
                    where q.estado = 'aberta' and q.modo = 'sombra' and (q.expira_em is null or q.expira_em > p_agora)
                    order by q.critica desc, q.perda_em nulls last, q.criada_em, q.id);
    if cardinality(v_som) > 0 and (cf.modo_proposta = 'sombra' or cf.modo_vigia = 'sombra') then
      v_l := array['Em teste (nada foi perguntado de verdade): eu perguntaria isto.']
             || array(select '• ' || x from unnest(v_som) with ordinality u(x, o) order by o);
    else
      v_l := array['Nada esperando você na agenda agora.'];
    end if;
  end if;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, cf.texto_max),
                            'dados', jsonb_build_object('decisoes', v_dec, 'outras', cardinality(v_outra)));
end;
$function$;

comment on function public._agenda_ver_decisoes(date, timestamptz) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6: a da diária com as opções e as palavras): agenda_ver foco decisoes — as decisões críticas abertas numeradas por agenda_decisoes_abertas ("Decisão 1: <a pergunta com as opções e a recomendação>"), como responder, e o que mais a agenda quer saber (chegou?, parada?, o que falta?), uma linha cada; sem nada em ligado, o que a sombra perguntaria ("Em teste"); nada = "Nada esperando você na agenda agora.". {ok, texto, dados{decisoes, outras}}. FASE 7d (P5): a combinar vem numerada, como decisão, e sai de "Também quero saber". FASE 7d (P6): a local também vem numerada. FASE 7d (P6b): quem tem número sai de "Também quero saber" pelo id; quem não tem segue lá.';

-- agenda_rascunho_aplicar (de 20261025100400_agenda_fase2_rascunho.sql)
create or replace function public.agenda_rascunho_aplicar(p_autor uuid, p_canal text, p_proposta text default null,
                                                          p_os text[] default null, p_decisao text default null,
                                                          p_opcao text default null, p_trecho text default null,
                                                          p_hoje date default public._hoje_brt(),
                                                          p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  v_rec    jsonb := public._agenda_pedido_recusa(p_canal, p_trecho, 'agenda_rascunho_aplicar');
  cf       public.agenda_config := public._agenda_cfg();
  v_lista  jsonb;
  v_q      jsonb;
  v_qs     jsonb;
  v_opc    jsonb;
  v_opcs   jsonb;
  v_ro     jsonb;
  v_n      int;
  v_ref    text;
  v_sim    jsonb;
  v_mud    text;
  v_p      public.agenda_propostas%rowtype;
  v_os     uuid[];
  v_x      text;
  v_viol   jsonb;
  v_sel    jsonb;
  v_frase  text;
  v_txt    text;
  -- FASE 7d: (7d P6b) as perguntas com opções e sem número, se mais de uma espera, a pergunta "qual?" e a linha da pergunta escolhida
  v_7d_fora   jsonb;
  v_7d_varias boolean;
  v_7d_qual   text;
  v_7d_linha  public.agenda_perguntas%rowtype;
  -- FASE 7d: fim
  v_ncanc  int;
begin
  if v_rec is not null then
    return v_rec;
  end if;
  if p_decisao is not null and p_proposta is not null then
    raise exception 'agenda_rascunho_aplicar: diga a proposta OU a decisão, não as duas' using errcode = '22023';
  end if;

  -- ── Responder uma decisão crítica ──
  if nullif(btrim(coalesce(p_decisao, '')), '') is not null or nullif(btrim(coalesce(p_opcao, '')), '') is not null then
    v_lista := public.agenda_decisoes_abertas(p_agora);
    -- FASE 7d: (7d P6b) quem também espera o dono sem ter número: tem opções, mas agenda_decidir não sabe o que fazer com elas (a nota e o aviso do fornecedor, que se
    -- respondem por material_informar) ou ele já escolheu "eu digo". "1" pode ser para ela: com mais de uma esperando, ninguém escolhe por ele.
    v_7d_fora := coalesce((select jsonb_agg(p.texto order by p.perda_em nulls last, p.criada_em, p.id)
                             from public.agenda_perguntas p
                            where p.estado = 'aberta' and p.modo = 'ligado'
                              and (p.expira_em is null or p.expira_em > p_agora)
                              and case when jsonb_typeof(p.opcoes) = 'array' then jsonb_array_length(p.opcoes) > 0 else false end
                              and not exists (select 1 from jsonb_array_elements(v_lista) e where e ->> 'id' = p.id::text)), '[]'::jsonb);
    if jsonb_array_length(v_lista) = 0 and jsonb_array_length(v_7d_fora) > 0 then
      return public._agenda_recusa('Essa pergunta não tem número de decisão: me responda com as suas palavras. '
        || (select string_agg(x, ' ') from jsonb_array_elements_text(v_7d_fora) x), 'sem_numero');
    end if;
    v_7d_varias := jsonb_array_length(v_lista) + jsonb_array_length(v_7d_fora) > 1;
    v_7d_qual := format('Qual decisão? %s. Diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2"). Eu não escolho por você.',
                        (select string_agg((q ->> 'n') || ') ' || rtrim(q ->> 'texto', '.'), '; ' order by (q ->> 'n')::int)
                           from jsonb_array_elements(v_lista) q))
                 || coalesce(' Sem número, responda com as suas palavras: '
                             || (select string_agg(x, ' ') from jsonb_array_elements_text(v_7d_fora) x), '');
    -- FASE 7d: fim
    if jsonb_array_length(v_lista) = 0 then
      return public._agenda_recusa('Não tenho decisão da agenda esperando você agora.', 'sem_decisao');
    end if;
    v_ref := btrim(coalesce(p_decisao, ''));
    if v_ref ~ '^\d{1,3}$' then
      select q into v_q from jsonb_array_elements(v_lista) q where (q ->> 'n')::int = v_ref::int;
      if v_q is null then
        return public._agenda_recusa(format('Não tenho a decisão %s. As que esperam você: %s.', v_ref,
          (select string_agg((q ->> 'n') || ') ' || rtrim(q ->> 'texto', '.'), '; ' order by (q ->> 'n')::int)
             from jsonb_array_elements(v_lista) q)), 'decisao_nao_existe');
      end if;
    elsif v_ref <> '' then
      v_ro := public.agenda_resolver_os(v_ref, p_hoje, false);
      if v_ro ->> 'status' <> 'ok' then
        return public._agenda_recusa_da_os(v_ro);
      end if;
      select coalesce(jsonb_agg(q order by (q ->> 'n')::int), '[]'::jsonb) into v_qs
        from jsonb_array_elements(v_lista) q
       where q ->> 'os' = v_ro ->> 'id' or (q -> 'os_ids') ? (v_ro ->> 'id');
      if jsonb_array_length(v_qs) = 0 then
        return public._agenda_recusa(format('Não tenho decisão esperando você sobre %s.', v_ro ->> 'cliente_curto'), 'decisao_nao_existe');
      end if;
      if jsonb_array_length(v_qs) > 1 then
        return public._agenda_recusa(format('Qual delas? %s.',
          (select string_agg((q ->> 'n') || ') ' || rtrim(q ->> 'texto', '.'), '; ' order by (q ->> 'n')::int)
             from jsonb_array_elements(v_qs) q)), 'decisao_ambigua');
      end if;
      v_q := v_qs -> 0;
    -- FASE 7d: (7d P6b) sem dizer qual: com a lista de uma só, mas outra pergunta com opções esperando, também pergunta qual
    elsif v_7d_varias then
      return public._agenda_recusa(v_7d_qual, 'decisao_ambigua');
    -- FASE 7d: fim
    elsif jsonb_array_length(v_lista) = 1 then
      v_q := v_lista -> 0;
    else
      return public._agenda_recusa(format('Qual decisão? %s.',
        (select string_agg((q ->> 'n') || ') ' || rtrim(q ->> 'texto', '.'), '; ' order by (q ->> 'n')::int)
           from jsonb_array_elements(v_lista) q)), 'decisao_ambigua');
    end if;

    -- FASE 7d: (7d P6b) com mais de uma esperando, a decisão e a opção têm de estar nas palavras do dono: "1" sozinho não é a decisão 1, opção 1, e a decisão pelo nome só
    -- vale com o nome dito. A opção pelo nome da OS ("pode atrasar o Nelson") não passa aqui: ela mesma diz qual.
    if v_7d_varias and btrim(coalesce(p_opcao, '')) ~ '^\d{1,2}$'
       and not (case when v_ref ~ '^\d{1,3}$' then public._agenda_disse_os_numeros(p_trecho, v_ref::int, btrim(p_opcao)::int)
                     else exists (select 1 from regexp_split_to_table(public._agenda_normal(v_ref), ' ') w
                                   where char_length(w) >= 3
                                     and public._agenda_normal(p_trecho) ~ ('(^| )' || w || '( |$)'))
                          and public._agenda_disse_os_numeros(p_trecho, null, btrim(p_opcao)::int) end) then
      return public._agenda_recusa(v_7d_qual, 'decisao_ambigua');
    end if;
    -- FASE 7d: fim
    -- A opção: o nº ou o nome da OS que aceita atrasar. Sem ela, a pergunta volta como está (o banco não escolhe).
    v_ref := btrim(coalesce(p_opcao, ''));
    if v_ref = '' then
      return public._agenda_recusa(rtrim(v_q ->> 'texto', ' ')
        || case when (v_q ->> 'texto') ~ '\d\)' then '' else ' ' || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; '
                                                                   order by (o ->> 'n')::int) from jsonb_array_elements(v_q -> 'opcoes') o) end,
        'sem_opcao',
        (select jsonb_agg((o ->> 'n') || ') ' || (o ->> 'texto') order by (o ->> 'n')::int) from jsonb_array_elements(v_q -> 'opcoes') o));
    end if;
    if v_ref ~ '^\d{1,2}$' then
      select o into v_opc from jsonb_array_elements(v_q -> 'opcoes') o where (o ->> 'n')::int = v_ref::int;
    else
      v_ro := public.agenda_resolver_os(v_ref, p_hoje, false);
      if v_ro ->> 'status' <> 'ok' then
        return public._agenda_recusa_da_os(v_ro);
      end if;
      select coalesce(jsonb_agg(o order by (o ->> 'n')::int), '[]'::jsonb) into v_opcs
        from jsonb_array_elements(v_q -> 'opcoes') o where o ->> 'os' = v_ro ->> 'id';
      if jsonb_array_length(v_opcs) > 1 then
        return public._agenda_recusa(format('Qual das opções? %s',
          (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
             from jsonb_array_elements(v_opcs) o)) || '.', 'opcao_ambigua');
      end if;
      v_opc := v_opcs -> 0;
    end if;
    if v_opc is null then
      return public._agenda_recusa('Essa opção não existe. As opções são: '
        || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
              from jsonb_array_elements(v_q -> 'opcoes') o) || '.', 'opcao_nao_existe',
        (select jsonb_agg((o ->> 'n') || ') ' || (o ->> 'texto') order by (o ->> 'n')::int) from jsonb_array_elements(v_q -> 'opcoes') o));
    end if;

    -- FASE 7d: (7d P6b, R6.7b) a não crítica cujo modo não vale agora: agenda_decidir recusaria no *grava*, e a frase seria "a agenda mudou". Com o freio, as do gestor têm
    -- número e não têm resposta, como sempre foi: nenhum caminho novo marca dia.
    select p.* into v_7d_linha from public.agenda_perguntas p where p.id = (v_q ->> 'id')::uuid;
    if not v_7d_linha.critica and coalesce(public._agenda_modo_da_pergunta(v_7d_linha.tipo, v_7d_linha.chave), 'desligado') <> 'ligado' then
      return public._agenda_recusa(
        case when cf.gestor_so_propor and v_7d_linha.tipo in ('situacao', 'estimativa', 'reavaliar', 'reestimar')
             then 'Com *gestor, só propor* essa resposta não muda nada agora. Se quiser, me diga com as suas palavras (por exemplo, os dias do serviço).'
             else 'Essa pergunta ainda está em teste: mostro como ficaria, mas não mudo nada.' end, 'em_teste');
    end if;
    -- FASE 7d: fim
    -- A agenda mudou desde a pergunta: o efeito da opção é refeito agora; se não termina como a opção dizia, a pergunta
    -- volta com os dias de agora (a mesma régua do agenda_decidir).
    if (v_q ->> 'versao_base')::bigint is distinct from cf.versao_plano and jsonb_typeof(v_opc -> 'espera') = 'object'
       and v_opc -> 'espera' <> '{}'::jsonb then
      v_sim := public.agenda_propor('replano', null, null, array(select x::uuid from jsonb_array_elements_text(v_q -> 'os_ids') x),
                                    coalesce(v_opc #> '{efeito,restricoes}', '{}'::jsonb), false, 'dono', v_autor, p_hoje, p_agora);
      select string_agg(format('%s termina %s (antes eu disse %s)', public._agenda_rotulo_da_os(e.key::uuid),
                               coalesce(public._dia_curto(x.fim), 'sem encaixe'), public._dia_curto((e.value #>> '{}')::date)), '; ')
        into v_mud
        from jsonb_each(v_opc -> 'espera') e
        left join lateral (select max((i ->> 'fim_depois')::date) as fim from jsonb_array_elements(v_sim -> 'itens') i
                            where i ->> 'op' = 'criar' and i ->> 'os' = e.key and i ->> 'tipo' <> 'reserva') x on true
       where x.fim is distinct from (e.value #>> '{}')::date;
      if v_mud is not null then
        return public._agenda_recusa('A agenda mudou desde a pergunta: ' || v_mud || '. Me responda de novo com os dias de agora.',
                                     'decisao_mudou');
      end if;
    end if;

    -- FASE 7d: (7d P6b) a releitura da não crítica diz de qual pergunta é a opção: "Está certo" sozinho não diz nada, e o *grava* é o único portão. A crítica, como sempre foi.
    if not v_7d_linha.critica then
      v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'aplicar', 'decisao:' || (v_q ->> 'id'),
                 nullif(v_q ->> 'os', '')::uuid,
                 jsonb_build_object('grupo', 'decisao:' || (v_q ->> 'id'), 'rotulo_grupo', 'Decisão', 'pergunta_id', v_q ->> 'id',
                                    'opcao', (v_opc ->> 'n')::int, 'opcao_texto', v_opc ->> 'texto',
                                    'frase_pronta', format('na pergunta "%s": %s', public._agenda_corta(v_7d_linha.texto, 90), rtrim(v_opc ->> 'texto', '.'))),
                 p_trecho, p_hoje);
      return jsonb_build_object('ok', true, 'item', v_txt,
                                'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
    end if;
    -- FASE 7d: fim
    v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'aplicar', 'decisao:' || (v_q ->> 'id'),
               nullif(v_q ->> 'os', '')::uuid,
               jsonb_build_object('grupo', 'decisao:' || (v_q ->> 'id'), 'rotulo_grupo', 'Decisão', 'pergunta_id', v_q ->> 'id',
                                  'opcao', (v_opc ->> 'n')::int, 'opcao_texto', v_opc ->> 'texto',
                                  'frase_pronta', rtrim(v_opc ->> 'texto', '.')),
               p_trecho, p_hoje);
    return jsonb_build_object('ok', true, 'item', v_txt,
                              'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
  end if;

  -- ── Publicar uma proposta aberta ──
  v_lista := public.agenda_propostas_abertas(p_agora);
  if jsonb_array_length(v_lista) = 0 then
    return public._agenda_recusa('Não tenho plano montado para publicar. Peça para eu montar (por exemplo, "monta a semana que vem").',
                                 'sem_proposta');
  end if;
  v_ref := public._agenda_normal(p_proposta);
  v_n := case when v_ref in ('', 'a ultima', 'ultima', 'essa', 'esta', 'a proposta', 'proposta', 'ela', 'isso', 'a semana', 'semana')
              then 1
              when v_ref ~ '^\d{1,3}$' then v_ref::int end;
  if v_n is null then
    return public._agenda_recusa(format('Qual plano? %s.',
      (select string_agg((p ->> 'n') || ') ' || coalesce(p ->> 'titulo', 'plano'), '; ' order by (p ->> 'n')::int)
         from jsonb_array_elements(v_lista) p)), 'proposta_ambigua');
  end if;
  select pr.* into v_p from public.agenda_propostas pr
   where pr.id = (select (p ->> 'id')::uuid from jsonb_array_elements(v_lista) p where (p ->> 'n')::int = v_n);
  if not found then
    return public._agenda_recusa(format('Não tenho o plano %s montado.', v_n), 'proposta_nao_existe');
  end if;
  if v_p.versao_base <> cf.versao_plano then
    return public._agenda_recusa('A agenda mudou desde que eu montei: peça de novo que eu refaço.', 'proposta_obsoleta');
  end if;

  -- só as OS ditas ("publica só o Lenine e o Flávio"), e só se estão na proposta
  if p_os is not null and cardinality(p_os) > 0 then
    v_os := '{}';
    foreach v_x in array p_os loop
      v_ro := public.agenda_resolver_os(v_x, p_hoje, false);
      if v_ro ->> 'status' <> 'ok' then
        return public._agenda_recusa_da_os(v_ro);
      end if;
      if not exists (select 1 from jsonb_array_elements(v_p.itens) i where i ->> 'os' = v_ro ->> 'id') then
        return public._agenda_recusa(format('%s não está nesse plano.', v_ro ->> 'cliente_curto'), 'os_fora_da_proposta');
      end if;
      v_os := v_os || (v_ro ->> 'id')::uuid;
    end loop;
    v_os := array(select distinct x from unnest(v_os) x order by 1);
  end if;

  v_viol := public.agenda_validar(v_p.id, v_os, p_hoje, p_agora);
  if jsonb_array_length(v_viol) > 0 then
    return public._agenda_recusa('Não dá para publicar: '
      || (select string_agg(e ->> 'texto', ' ' order by o) from jsonb_array_elements(v_viol) with ordinality t(e, o)), 'proposta_invalida');
  end if;
  v_sel := public._agenda_itens_escolhidos(v_p.itens, v_os, null);
  if not exists (select 1 from jsonb_array_elements(v_sel) i where i ->> 'op' = 'criar') and jsonb_array_length(v_sel) = 0 then
    return public._agenda_recusa('No plano que eu montei não há nada para publicar sem a sua decisão: veja o que a agenda precisa de você.',
                                 'so_critico');
  end if;
  v_ncanc := (select count(*) from jsonb_array_elements(v_sel) i where i ->> 'op' = 'cancelar');
  v_frase := case when v_p.escopo = 'semana'
                  then lower(left(coalesce(v_p.textos ->> 'titulo', 'a semana'), 1)) || substr(coalesce(v_p.textos ->> 'titulo', 'a semana'), 2) || ': '
                  else '' end
             || coalesce(nullif(array_to_string(array(
                  select regexp_replace(rtrim(i ->> 'texto', '.'), '^([^:]*): ', '\1, ')
                    from jsonb_array_elements(v_sel) with ordinality t(i, k)
                   where i ->> 'op' = 'criar'
                   order by (i ->> 'de')::date, i ->> 'numero' collate "C", k), '; '), ''), 'nada novo')
             || case when v_ncanc > 0 then format('; e tiro da agenda %s que não pode mais acontecer',
                                                   public._agenda_plural(v_ncanc, 'serviço', 'serviços')) else '' end;

  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'aplicar', 'aplicar:' || v_p.id::text, null,
             jsonb_build_object('grupo', 'aplicar:' || v_p.id::text, 'rotulo_grupo', 'Publico na agenda', 'proposta_id', v_p.id,
                                'os_ids', to_jsonb(v_os), 'frase_pronta', v_frase),
             p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_aplicar(uuid, text, text, text[], text, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P4): vira RASCUNHO (nada muda) — publicar uma proposta aberta ("pode publicar", "publica só o Lenine e o Flávio": p_proposta "a última" ou o nº de agenda_propostas_abertas, p_os as OS ditas; obsoleta, inválida ou só com crítico = recusa) ou responder uma decisão crítica (p_decisao = o nº de agenda_decisoes_abertas ou o nome da OS; p_opcao = o nº ou o nome da OS que aceita atrasar). Sem opção dita: a pergunta com as opções volta como está — o banco não escolhe. Se a agenda mudou desde a pergunta e o efeito da opção também, a pergunta volta com os dias de agora. Chave aplicar:<proposta> / decisao:<pergunta>; releitura "Publico na agenda: …" / "Decisão: …". O *grava* chama agenda_aplicar (via dono) ou agenda_decidir (respondida_via = o canal). FASE 7d (P6b, NOVO-agenda-91): com a lista levando as não críticas, responder por número não pode virar a pergunta errada. Contam como esperando a lista e as perguntas com opções e sem número (nfe_vincular, previsao_fornecedor, a com opção já escolhida). Com mais de uma: sem a decisão dita, "Qual decisão?" (decisao_ambigua), também com uma só na lista; com a decisão e a opção em número, os 2 têm de estar nas palavras do dono (_agenda_disse_os_numeros); pelo nome e a opção em número, o nome e o número no trecho. A opção pelo nome da OS não passa por isso. Só pergunta sem número: a recusa diz que é por palavras (sem_numero). A não crítica cujo modo não vale agora é recusada aqui (em_teste), não no *grava*; a releitura dela diz de qual pergunta é a opção. A crítica, como antes.';

-- ── 3. Portas ──────────────────────────────────────────────────────────────────────────────
-- A nova é interna: quem a alcança é agenda_rascunho_aplicar, definer. As recriadas mantêm as portas delas: create or replace não muda a ACL, e nenhuma é nova.
revoke all on function public._agenda_disse_os_numeros(text, integer, integer) from public, anon, authenticated, service_role;

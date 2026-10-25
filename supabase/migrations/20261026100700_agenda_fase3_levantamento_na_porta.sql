-- Agenda de Produção, Fase 3 ("A execução: equipe, diária, conclusão e telas"), pacote P7b (a amarração): a trava do
-- levantamento (D11) passa a valer na porta — em TODO caminho de conclusão.
-- Spec: scratchpad agenda-pesquisa/spec-fase3.md (§5.3, §13.6, §15 P7). Notas entre pacotes: notas-fase3.md ("Decisões do
-- coordenador depois do P3": D11 na porta, NOVO-agenda-24; "P7a — feito": o P7b copia a porta de 20261026100600).
-- Depende das Fases 1 e 2 inteiras e de 20261026100000 a 20261026100600 (a porta completa de 100100, o espelho do D11 de
-- 100200 — _os_levantamentos_pendentes e _os_texto_do_levantamento — e a porta lendo _os_porta_regra de 100600).
--
-- ═══ DDL — OK NOMEADO ═══ (a porta recriada; nenhuma função nova, nenhuma tabela, nenhuma coluna, nenhum dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: o dono decidiu em 17/09 que concluir exige o levantamento RESPONDIDO nos serviços marcados "exige levantamento"
-- (services.requires_survey). Até aqui a regra valia no botão Concluir do formulário (src/lib/levantamento-gate.ts) e, desde
-- o P3, na conversa e nas palavras (_os_levantamentos_pendentes, 20261026100200). A lista rápida de status, os dois kanbans,
-- a assinatura do cliente (se um dia ela concluir), a conclusão pela palavra do técnico (o gestor, via equipe) e o assistente
-- passavam pela porta, que não conferia (NOVO-agenda-24). Estender é aplicar a mesma decisão do dono, não uma regra nova.
--
-- O QUE MUDA:
--   1. os_transicionar_status recriada (corpo de 20261026100600, a definição mais nova; a mudança marcada
--      "-- FASE 3 (P7b):"): logo no começo da conclusão (ativo → concluída), com serviço que exige levantamento sem
--      levantamento fechado nesta OS, nada muda e a porta devolve {ok false, mudou false} com a frase do formulário, a que o
--      dono já conhece: "Para concluir, responda o levantamento de: <serviços>. Esses serviços estão marcados como "exige
--      levantamento"." Vale para toda via que conclui (tela, assinatura, equipe, dono, assistente, conferência) e para o
--      orçamento que converteria e concluiria na mesma chamada (a conversão também não fica). A entrega de uma OS ainda
--      aberta (os_registrar_marco 'entrega') conclui antes pela porta, então recusa igual.
--   A fonte da regra passa a ser a porta. As conferências de antes dela (o formulário, a conversa e as palavras) dizem a
--   mesma frase e ficam: o formulário cobre o front publicado antes desta migration (o plano B), e a conversa e as palavras
--   recusam antes de montar o rascunho (a releitura não oferece o que a porta recusaria).
--
-- REVISÃO DA FASE 3 (C2, 25/10): a cópia acompanha as trocas da 20261026100600 fora do bloco do D11 (o C1 do teste confere):
-- com login, a via não é de quem chama (R6); a regra recebe o modo da agenda automática e a recusa só por falta do motivo
-- devolve pede_motivo (R2); agendada → aberta pela tela vai para o status escolhido (R2).
--
-- O QUE NÃO MUDA: quem pode e as passagens (_os_porta_regra), as cobranças e a saída da conclusão, reabrir, faturar,
-- desfazer, a conversão sem conclusão, os status de agenda. A lista rápida e os kanbans continuam oferecendo "Concluída"
-- (o levantamento é dado: a porta decide na hora e o aviso traz a frase). Nenhuma frase das Fases 2 e 3 muda.
--
-- ORDEM DE LIGAR: depois de 20261026100600, junto das outras migrations de estrutura da Fase 3 (fila-do-dono/fase3-oks.md,
-- passo 1). O front pode sair antes ou depois: a tela já mostra a recusa da porta como aviso.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase3_levantamento_na_porta.sql (begin/rollback; os cenários só na
-- bancada, com fixture-fase3.sql; a regra da cópia e as portas rodam sempre). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261026100700
--
-- APLICAR (só com o OK nomeado do dono):
--   npx supabase db query --linked -f supabase/migrations/20261026100700_agenda_fase3_levantamento_na_porta.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261026100700', 'agenda_fase3_levantamento_na_porta');"
--
-- IDEMPOTENTE: create or replace function; revoke/grant e comment.

-- ── A porta, com o D11 na conclusão (corpo de 20261026100600; a mudança marcada "-- FASE 3 (P7b):") ──────

create or replace function public.os_transicionar_status(
  p_os        uuid,
  p_para      text,
  p_via       text,
  p_motivo    text        default null,
  p_autor     uuid        default null,
  p_check_in  timestamptz default null,
  p_hoje      date        default public._hoje_brt(),
  p_agora     timestamptz default now(),
  p_check_out timestamptz default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config;
  v_uid    uuid := auth.uid();
  v_papel  text;
  v_autor  uuid;
  v_os     record;
  v_de     text;
  v_para   text := p_para;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_nome   text;
  v_check  timestamptz;
  v_novo_check boolean := false;
  v_falta  text;
  v_antes  text;
  v_texto  text;
  v_origem text;
  v_acao   uuid;
  -- FASE 3: quem pode, a conversão, a conclusão e o desfazer dela.
  v_tipo      text;
  v_gestor    boolean := false;
  v_tecnico   boolean := false;
  v_vendedor  boolean := false;
  v_num_novo  text;
  v_acao_conv uuid;
  v_r         jsonb;
  v_conc      public.agenda_acoes%rowtype;
  v_saida     timestamptz;
  v_venc      jsonb;
  v_venc_cob  jsonb;
  v_com_antes uuid[];
  v_coms      uuid[];
  v_rec       jsonb;
  v_ids       uuid[];
  v_erro      text;
  v_cob       text;
  v_venc_dia  date;
  v_venc_soma numeric;
  -- FASE 3: fim
  -- FASE 3 (P7a): a regra que só depende do cargo, do status, do pedido e do caminho (_os_porta_regra).
  v_regra     jsonb;
begin
  if p_via is null or p_via not in ('tela_agendar', 'aprovacao', 'assistente', 'check_in', 'oc', 'motor', 'vigia',
                                    'conferencia', 'dono', 'desfazer',
                                    -- FASE 3: a tela (a mudança genérica de status), a assinatura do cliente e o gestor
                                    -- pela palavra do técnico.
                                    'tela', 'assinatura', 'equipe') then
    raise exception 'Caminho desconhecido para mudar o status: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  if p_para is null or p_para not in ('draft', 'scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client',
                                      'approved', 'completed', 'invoiced', 'cancelled') then
    raise exception 'Status desconhecido: "%".', coalesce(p_para, '') using errcode = '22023';
  end if;
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception 'Faltam a OS, o dia ou a hora para mudar o status.' using errcode = '22023';
  end if;

  perform set_config('agenda.hoje', p_hoje::text, true);
  c := public._agenda_cfg();

  select so.id, so.service_order_number as numero, so.status, so.check_in_at, cl.name as cliente,
         -- FASE 3: o que a conclusão, a entrega e a conversão leem.
         so.check_out_at, so.delivered_at, so.converted_to_os_at, so.grand_total, so.original_quote_amount
    into v_os
    from public.service_orders so
    left join public.clients cl on cl.id = so.client_id
   where so.id = p_os
     for update of so;
  if not found then
    raise exception 'Não encontrei a OS.' using errcode = 'P0002';
  end if;

  -- Quem pede: com login, o próprio login; sem login (service role, o próprio banco), p_autor — motor e vigia podem
  -- vir sem. Um JWT de outro papel sem login não ganha o direito de dizer quem é.
  if v_uid is not null then
    -- FASE 3: a assinatura do cliente vem só pela service_role (submit-signature), nunca com login. Revisão da Fase 3 (R6):
    -- com login, quem chama não escolhe a via — o motor, a vigia e o gestor (equipe) também são só do banco, e o dono e a
    -- conferência, só do administrador ou do financeiro.
    if p_via in ('assinatura', 'equipe', 'motor', 'vigia')
       or (p_via in ('dono', 'conferencia') and not public.is_admin_or_financial(v_uid)) then
      raise exception 'Você não pode mudar o status desta OS.' using errcode = '42501';
    end if;
    v_autor := v_uid;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    -- FASE 3: além do motor e da vigia, o gestor (equipe) e a assinatura do cliente vêm sem autor.
    if v_papel not in ('', 'service_role') or (p_autor is null and p_via not in ('motor', 'vigia', 'equipe', 'assinatura')) then
      raise exception 'Você não pode mudar o status desta OS.' using errcode = '42501';
    end if;
    -- FASE 3: a assinatura é do cliente: nunca tem autor.
    v_autor := case when p_via = 'assinatura' then null else p_autor end;
  end if;

  -- FASE 3: quem pode muda com o que se pede (spec-fase3 §5.3). A régua da Fase 2 (admin/financeiro ativo ou técnico ativo
  -- da OS, com a mesma frase) continua para o status de agenda, e o vendedor ativo entra nela pela tela; converter,
  -- concluir, faturar e reabrir têm a régua e a frase delas.
  if v_autor is not null then
    v_gestor   := public.is_admin_or_financial(v_autor);
    v_tecnico  := exists (select 1 from public.service_order_technicians t
                            join public.app_users u on u.id = t.user_id
                           where t.service_order_id = p_os and t.user_id = v_autor and u.active);
    v_vendedor := exists (select 1 from public.app_users u where u.id = v_autor and u.active and u.role = 'seller');
  end if;
  -- FASE 3 (P7a): o tipo do pedido, quem pode e as passagens que não dependem de dado vêm de _os_porta_regra — a mesma
  -- função que a tela (os_status_da_tela) lê para esconder da lista rápida e dos kanbans o que a porta recusa.
  v_regra := public._os_porta_regra(v_os.status, v_para, p_via, v_gestor, v_tecnico, v_vendedor, v_autor is not null,
                                    v_motivo is not null, c.modo_proposta = 'ligado');
  v_tipo := v_regra ->> 'tipo';
  if v_regra ->> 'recusa' = 'quem' then
    raise exception '%', v_regra ->> 'texto' using errcode = '42501';
  end if;
  -- FASE 3 (P7a): fim
  -- FASE 3: a origem de cada caminho (estava depois da escrita; a conclusão e a conversão também a usam).
  v_origem := case p_via
    when 'tela_agendar' then 'tela'
    when 'check_in'     then 'sistema'
    when 'oc'           then 'sistema'
    when 'desfazer'     then 'dono'
    when 'assinatura'   then 'sistema'
    else p_via end;
  -- FASE 3: fim

  v_de   := v_os.status;
  v_nome := coalesce(public._agenda_nome_curto(v_os.cliente) || ' (' || v_os.numero || ')', v_os.numero);

  -- FASE 3 (P7a): cancelada, faturada, cancelar, concluída, orçamento sem converter, voltar a orçamento, faturar antes de
  -- concluir, "já está", a OS que já começou, a agendada pela tela e o cliente que não liberou: a frase de _os_porta_regra
  -- (1 = o número, 2 = o nome, 3 = o status de agora, 4 = o pedido).
  if v_regra ->> 'recusa' = 'passagem' then
    return public._agenda_porta_fica((v_regra ->> 'fica')::boolean, v_de,
      format(v_regra ->> 'texto', v_os.numero, v_nome, public._agenda_status_texto(v_de), public._agenda_status_texto(v_para)))
      -- Revisão da Fase 3 (R2): só faltou o motivo (em andamento → aguardando, pelo dono ou pela tela): quem chama pede.
      || case when coalesce((v_regra ->> 'pede_motivo')::boolean, false) then jsonb_build_object('pede_motivo', true)
              else '{}'::jsonb end;
  end if;
  -- FASE 3 (P7a): fim

  -- FASE 3: encerrada, faturada, cancelada e orçamento. A Fase 2 recusava tudo aqui ("concluir é pela tela"); agora a
  -- conclusão, o faturamento, a reabertura e a conversão são da porta. Cancelar continua no botão Cancelar OS.
  -- FASE 3 (P7a): cancelada, faturada, cancelar e concluída sem ser faturar/reabrir/desfazer saíram para _os_porta_regra.
  if v_de = 'completed' then

    -- O desfazer da conclusão (só de dentro do agenda_desfazer, que diz qual ação desfaz em agenda.desfaz_conclusao):
    -- volta ao status de antes, e a saída sai se foi a conclusão que a gravou.
    if p_via = 'desfazer' then
      select a.* into v_conc
        from public.agenda_acoes a
       where a.id::text = coalesce(current_setting('agenda.desfaz_conclusao', true), '')
         and a.service_order_id = p_os and a.tipo = 'concluir' and a.executada and a.desfeita_em is null;
      if not found or v_conc.status_antes is distinct from v_para then
        return public._agenda_porta_fica(false, v_de,
          'Desfazer a conclusão é pelo *desfaz* da agenda; para reabrir, use a tela da OS.');
      end if;
      perform public._agenda_escrever_conclusao(p_os, v_para, null, (v_conc.antes ->> 'check_out_at') is null, null, null);
      v_texto := format('%s: de concluída para %s (desfeito).', v_nome, public._agenda_status_texto(v_para));
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                       status_depois, antes, depois, texto, autor)
      values (clock_timestamp(), p_hoje, true, v_origem, 'status', p_os, array[p_os], v_de, v_para,
              jsonb_build_object('status', v_de, 'check_out_at', v_os.check_out_at),
              jsonb_build_object('status', v_para, 'check_out_at', (select so.check_out_at from public.service_orders so where so.id = p_os),
                                 'via', p_via, 'desfaz_conclusao', v_conc.id),
              left(v_texto, 400), v_autor)
      returning id into v_acao;
      return jsonb_build_object('ok', true, 'mudou', true, 'de', v_de, 'para', v_para, 'texto', left(v_texto, 400),
                                'acao_id', v_acao, 'check_in_at', v_os.check_in_at,
                                'check_out_at', (select so.check_out_at from public.service_orders so where so.id = p_os));
    end if;

    if v_para = 'invoiced' then
      perform public._agenda_escrever_os(p_os, 'invoiced', null, null, null, false);
      v_texto := format('%s: faturada.', v_nome);
    else
      -- Reabrir (paridade com a tela: a saída e as cobranças ficam; o início, se faltava, como no "em andamento").
      if v_para = 'in_progress' and v_os.check_in_at is null then
        v_check := coalesce(p_check_in, p_agora);
        v_novo_check := true;
      end if;
      perform public._agenda_escrever_os(p_os, v_para, v_check, null, null, false);
      v_texto := format('Reabri o %s', v_nome)
        || case when exists (select 1 from public.receivables r where r.service_order_id = p_os and r.status <> 'cancelled')
                then '. As cobranças da conclusão continuam; se for o caso, ajuste no financeiro.'
                else ' (agora está ' || public._agenda_status_texto(v_para) || ').' end;
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                     status_depois, antes, depois, texto, motivo, autor)
    values (clock_timestamp(), p_hoje, true, v_origem, 'status', p_os, array[p_os], v_de, v_para,
            jsonb_build_object('status', v_de, 'check_in_at', v_os.check_in_at, 'check_out_at', v_os.check_out_at),
            jsonb_build_object('status', v_para, 'check_in_at', coalesce(v_os.check_in_at, v_check), 'via', p_via),
            left(v_texto, 400), left(v_motivo, 200), v_autor)
    returning id into v_acao;
    return jsonb_build_object('ok', true, 'mudou', true, 'de', v_de, 'para', v_para, 'texto', left(v_texto, 400),
                              'acao_id', v_acao, 'check_in_at', coalesce(v_os.check_in_at, v_check),
                              'check_out_at', v_os.check_out_at);
  end if;

  if v_de = 'draft' then
    -- FASE 3 (P7a): o orçamento sem conversão saiu para _os_porta_regra.
    -- A conversão: o número troca SÓ o prefixo (ORÇ-00119 → OS-00119), converted_to_os_at e original_quote_amount uma vez;
    -- depois, na mesma chamada, a regra de aprovada → X. Se o passo X recusar, a conversão também não fica.
    v_num_novo := case when v_os.numero like 'ORÇ-%' then 'OS-' || substr(v_os.numero, 5) else v_os.numero end;
    if v_num_novo <> v_os.numero
       and exists (select 1 from public.service_orders o2 where o2.service_order_number = v_num_novo and o2.id <> p_os) then
      return public._agenda_porta_fica(false, v_de, format('Não converti: o número %s já é de outra OS.', v_num_novo));
    end if;
    begin
      perform public._agenda_escrever_conclusao(p_os, 'approved', null, false, null,
        jsonb_build_object('numero', v_num_novo, 'converted_to_os_at', coalesce(v_os.converted_to_os_at, p_agora),
                           'original_quote_amount', coalesce(v_os.original_quote_amount, nullif(v_os.grand_total, 0))));
      v_texto := format('Orçamento %s virou a %s (aprovada).', v_os.numero, v_num_novo);
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                       status_depois, antes, depois, texto, autor)
      values (clock_timestamp(), p_hoje, true, v_origem, 'status', p_os, array[p_os], 'draft', 'approved',
              jsonb_build_object('status', 'draft', 'numero', v_os.numero, 'converted_to_os_at', v_os.converted_to_os_at),
              jsonb_build_object('status', 'approved', 'numero', v_num_novo, 'convertido', true, 'via', p_via),
              left(v_texto, 400), v_autor)
      returning id into v_acao_conv;
      if v_para = 'approved' then
        return jsonb_build_object('ok', true, 'mudou', true, 'de', 'draft', 'para', 'approved', 'texto', left(v_texto, 400),
                                  'acao_id', v_acao_conv, 'convertido', true, 'numero', v_num_novo,
                                  'numero_antes', v_os.numero, 'check_in_at', v_os.check_in_at);
      end if;
      v_r := public.os_transicionar_status(p_os, v_para, p_via, p_motivo, p_autor, p_check_in, p_hoje, p_agora, p_check_out);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0098', message = v_r::text;
      end if;
    exception when sqlstate 'P0098' then
      return sqlerrm::jsonb || jsonb_build_object('de', 'draft', 'para', 'draft', 'mudou', false);
    end;
    return v_r || jsonb_build_object('de', 'draft', 'mudou', true, 'convertido', true, 'numero', v_num_novo,
                                     'numero_antes', v_os.numero, 'acao_conversao', v_acao_conv,
                                     'acao_id', coalesce(v_r -> 'acao_id', to_jsonb(v_acao_conv)),
                                     'texto', left(v_texto || ' ' || coalesce(v_r ->> 'texto', ''), 400));
  end if;

  -- FASE 3 (P7a): voltar a orçamento e faturar antes de concluir saíram para _os_porta_regra.

  -- A conclusão (ativo → concluída): (1) a OS já está travada; (2) as cobranças ANTES do status, como a tela (o gatilho do
  -- vencimento "na entrega" roda depois e as acerta); (3) um UPDATE com o status e a saída; (4) a ação concluir com as
  -- cobranças criadas. Erro em (2) ou (3) = nada muda (a OS, as cobranças e a saída ficam como estavam) e o texto diz por quê.
  if v_para = 'completed' then
    -- FASE 3 (P7b): D11 (decisão do dono, 17/09/2026) em TODO caminho de conclusão — a tela (o formulário, a lista rápida,
    -- os kanbans), a assinatura, a equipe, as palavras e a conversa (os_registrar_marco), o assistente: concluir exige o
    -- levantamento RESPONDIDO nos serviços marcados "exige levantamento". Nada muda (nem a conversão do orçamento que vinha
    -- junto) e a frase é a do formulário, a que o dono já conhece (NOVO-agenda-24).
    if cardinality(public._os_levantamentos_pendentes(p_os)) > 0 then
      return public._agenda_porta_fica(false, v_de,
        public._os_texto_do_levantamento(public._os_levantamentos_pendentes(p_os)));
    end if;
    -- FASE 3 (P7b): fim
    -- O retrato do que a conclusão vai mexer, para o desfazer: os vencimentos "na entrega" que o gatilho move e as comissões
    -- que já existiam (a de vendedor nasce no gatilho).
    select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'due_date', r.due_date) order by r.id), '[]'::jsonb) into v_venc
      from public.receivables r
     where r.service_order_id = p_os and r.due_on_completion and r.status not in ('paid', 'cancelled');
    select coalesce(jsonb_agg(jsonb_build_object('id', cc.id, 'due_date', cc.due_date) order by cc.id), '[]'::jsonb) into v_venc_cob
      from public.collections cc
      join public.receivables r on r.id = cc.receivable_id
     where r.service_order_id = p_os and r.due_on_completion and cc.status = 'pending';
    v_com_antes := array(select cm.id from public.commissions cm where cm.service_order_id = p_os);
    v_saida := coalesce(v_os.check_out_at, p_check_out, p_agora);
    begin
      v_rec := public._os_criar_recebiveis_da_conclusao(p_os, p_hoje);
      perform public._agenda_escrever_conclusao(p_os, 'completed', v_saida, false, null, null);
    exception when others then
      get stacked diagnostics v_erro = message_text;
      return public._agenda_porta_fica(false, v_de, public._os_erro_da_conclusao(v_erro));
    end;
    v_ids  := coalesce(array(select (x #>> '{}')::uuid from jsonb_array_elements(v_rec -> 'criados') x), '{}');
    v_coms := array(select cm.id from public.commissions cm
                     where cm.service_order_id = p_os and not (cm.id = any (v_com_antes)) order by cm.id);

    if v_rec ->> 'motivo' in ('parcelas', 'titulo_unico') then
      v_cob := case when cardinality(v_ids) = 1 then 'Cobrança: ' else 'Cobranças: ' end
               || public._os_cobrancas_texto(v_ids, p_hoje, v_os.numero) || '.';
    elsif v_rec ->> 'motivo' = 'total_zero' then
      v_cob := 'Sem cobrança: o total da OS está zerado.';
    else
      select min(r.due_date), sum(r.amount) into v_venc_dia, v_venc_soma
        from public.receivables r
       where r.id in (select (x ->> 'id')::uuid from jsonb_array_elements(v_venc) x);
      v_cob := 'As cobranças já existiam'
        || case when exists (select 1 from public.receivables r where r.service_order_id = p_os and r.is_deposit
                                                                 and r.status in ('paid', 'partially_paid'))
                then ' (sinal pago)' else '' end
        || case when v_venc_dia is not null
                then format('; o saldo na entrega (%s) passa a vencer %s', public._brl(v_venc_soma),
                            case when v_venc_dia = p_hoje then 'hoje' else public._dia_curto(v_venc_dia) end)
                else '' end
        || '.';
    end if;
    v_texto := format('%s: concluída — saída %s %s.', v_nome,
                      public._dia_curto((v_saida at time zone 'America/Sao_Paulo')::date),
                      to_char(v_saida at time zone 'America/Sao_Paulo', 'HH24:MI'))
               || ' ' || v_cob;

    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                     status_depois, antes, depois, texto, motivo, autor, desfazivel_ate, receivable_ids)
    values (clock_timestamp(), p_hoje, true, v_origem, 'concluir', p_os, array[p_os], v_de, 'completed',
            jsonb_build_object('status', v_de, 'check_out_at', v_os.check_out_at, 'vencimentos', v_venc,
                               'cobrancas_vencimento', v_venc_cob),
            jsonb_build_object('status', 'completed', 'check_out_at', v_saida, 'via', p_via, 'cobrancas', v_rec ->> 'motivo',
                               'comissoes', to_jsonb(v_coms)),
            left(v_texto, 400), left(v_motivo, 200), v_autor,
            -- o gestor (equipe) e o dono (palavra, conversa) desfazem; a tela e a assinatura reabrem pela tela.
            case when v_origem in ('equipe', 'dono') then p_agora + c.desfazer_validade end,
            v_ids)
    returning id into v_acao;

    return jsonb_build_object('ok', true, 'mudou', true, 'de', v_de, 'para', 'completed', 'texto', left(v_texto, 400),
                              'acao_id', v_acao, 'check_in_at', v_os.check_in_at, 'check_out_at', v_saida,
                              'cobrancas', v_rec, 'cobrancas_texto', v_cob);
  end if;
  -- FASE 3: fim

  -- Igual: nada a fazer — menos o início que faltava numa OS em andamento. FASE 3 (P7a): o "já está" dos outros status
  -- sai de _os_porta_regra; aqui só chega a OS em andamento (o início que falta depende do dado).
  if v_para = v_de then
    if v_de = 'in_progress' and v_os.check_in_at is null then
      v_check := coalesce(p_check_in, p_agora);
      v_novo_check := true;
    else
      return public._agenda_porta_fica(true, v_de, format('%s já está %s.', v_nome, public._agenda_status_texto(v_de)));
    end if;
  end if;

  -- A regra de cada passagem (vale em todos os modos; a do dia no plano, só em 'ligado').
  if v_para = 'scheduled' then
    -- FASE 3 (P7a): a OS que já começou e o cliente que não liberou saíram para _os_porta_regra.
    if v_de = 'awaiting_parts' then
      v_falta := public._agenda_falta_material(p_os, p_hoje);
      if v_falta is not null then
        return public._agenda_porta_fica(true, v_de,
          format('%s: a OS continua aguardando peças.', v_falta));
      end if;
    end if;
    if c.modo_proposta = 'ligado' and not public._agenda_os_tem_dia(p_os, p_hoje) then
      return public._agenda_porta_fica(true, v_de,
        format('Sem dia no plano: a OS continua %s.', public._agenda_status_texto(v_de)));
    end if;

  elsif v_para = 'in_progress' then
    if v_os.check_in_at is null then
      v_check := coalesce(p_check_in, p_agora);
      v_novo_check := true;
    end if;

  -- FASE 3 (P7a): aguardar depois de começar (a OC, o "parou" sem o dono ou sem o motivo) saiu para _os_porta_regra.

  elsif v_para in ('open', 'approved') then
    -- FASE 3 (P7a): a OS que já começou e a agendada pela tela saíram para _os_porta_regra.
    if v_de = 'scheduled' then
      if public._agenda_os_tem_dia(p_os, p_hoje) then
        return public._agenda_porta_fica(false, v_de, 'A OS ainda tem dia no plano: tire o dia antes.');
      end if;
      -- Volta ao que era antes de agendar (aberta ou aprovada); sem registro, aprovada. Revisão da Fase 3 (R2): pela tela
      -- (o administrador ou o financeiro, com a agenda automática fora de ligado: _os_porta_regra), o status que ele
      -- escolheu.
      if p_via <> 'tela' then
        select a.status_antes into v_antes
          from public.agenda_acoes a
         where a.service_order_id = p_os and a.tipo = 'status' and a.executada and a.status_depois = 'scheduled'
         order by a.criada_em desc, a.id desc
         limit 1;
        v_para := case when v_antes in ('open', 'approved') then v_antes else 'approved' end;
      end if;
    elsif v_de = 'awaiting_parts' then
      v_falta := public._agenda_falta_material(p_os, p_hoje);
      if v_falta is not null then
        return public._agenda_porta_fica(true, v_de,
          format('%s: a OS continua aguardando peças.', v_falta));
      end if;
    -- FASE 3 (P7a): o cliente que não liberou saiu para _os_porta_regra.
    end if;
  end if;

  -- Grava (a única escrita) e registra.
  perform public._agenda_escrever_os(p_os, case when v_para <> v_de then v_para end, v_check, null, null, false);

  v_texto := case
    when v_para = v_de then format('%s: início registrado', v_nome)
    else format('%s: de %s para %s', v_nome, public._agenda_status_texto(v_de), public._agenda_status_texto(v_para)) end
    || case when v_novo_check
            then format(' (%s às %s)', public._dia_curto((v_check at time zone 'America/Sao_Paulo')::date),
                        to_char(v_check at time zone 'America/Sao_Paulo', 'HH24:MI'))
            else '' end
    || coalesce(' — ' || rtrim(v_motivo, '. '), '') || '.';
  -- FASE 3: a origem de cada caminho saiu daqui para antes das regras (a conclusão e a conversão também a usam).

  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                   status_depois, antes, depois, texto, motivo, autor, desfazivel_ate)
  values (clock_timestamp(), p_hoje, true, v_origem, 'status', p_os, array[p_os], v_de, v_para,
          jsonb_build_object('status', v_de, 'check_in_at', v_os.check_in_at),
          jsonb_build_object('status', v_para, 'check_in_at', coalesce(v_os.check_in_at, v_check), 'via', p_via),
          left(v_texto, 400), left(v_motivo, 200), v_autor,
          -- FASE 3: o gestor (equipe) desfaz como o motor e a vigia: é ação autônoma.
          case when v_origem in ('motor', 'vigia', 'equipe') then p_agora + c.desfazer_validade end)
  returning id into v_acao;

  return jsonb_build_object('ok', true, 'mudou', true, 'de', v_de, 'para', v_para, 'texto', left(v_texto, 400),
                            'acao_id', v_acao, 'check_in_at', coalesce(v_os.check_in_at, v_check));
end;
$function$;

comment on function public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz) is
  'Agenda de Produção (Fase 2; Fase 3: conclusão, faturamento, reabertura, conversão e p_check_out; Fase 3, P7a: as regras que só dependem do cargo, do status, do pedido e do caminho moram em _os_porta_regra, a mesma função que a tela lê; Fase 3, P7b: o D11 — concluir exige o levantamento respondido nos serviços marcados "exige levantamento", em todo caminho, com a frase do formulário): a porta única de status da OS. Vias: tela, tela_agendar, aprovacao, assistente, check_in, oc, motor, vigia, equipe, conferencia, dono, assinatura, desfazer. Status de agenda (todos os modos): em andamento nunca volta (agendada/aberta/aprovada) e só volta a aguardar com o motivo, pelo dono ou pela tela (admin/financeiro, técnico da OS; sem o motivo {ok false, pede_motivo true}) (a OC: ok, nada muda); aguardando peças só sai com o material completo; aguardando o cliente só sai pelo dono, a tela de agendar, a aprovação ou a assinatura do cliente; agendada só volta (para o status de antes) pela agenda ou pelo dono e sem dia no plano, e pela tela (para o status escolhido) só o admin/financeiro com a agenda automática fora de ligado; com login, as vias motor, vigia, equipe e assinatura são recusadas (42501), e dono e conferência só valem para admin/financeiro; em modo_proposta ligado, agendada só com dia no plano; check_in_at uma vez. Fase 3: concluir (ativo → concluída) exige o levantamento respondido (_os_levantamentos_pendentes vazio; senão nada muda e {ok false} com "Para concluir, responda o levantamento de: …"), cria as cobranças da condição (_os_criar_recebiveis_da_conclusao, paridade com a tela) ANTES do status e grava a saída num UPDATE só, tudo ou nada ({ok false} com o texto); faturar só concluída; reabrir concluída (tela, dono) mantém saída e cobranças; orçamento → X (tela, assistente, dono, aprovação, assinatura) converte trocando só o prefixo do número e aplica aprovada → X na mesma chamada (se X recusar, a conversão também não fica); cancelar é Cancelar OS. Quem pode: status de agenda = admin/financeiro, técnico da OS, vendedor pela tela; converter = admin/financeiro, vendedor (tela, assistente), assinatura; concluir = admin/financeiro, técnico da OS, assinatura, equipe; faturar/reabrir/desfazer a conclusão = admin/financeiro. Toda mudança: linha em agenda_acoes (status; concluir com receivable_ids; desfazível quando foi motor/vigia/equipe, e a conclusão pela equipe ou pelo dono). Devolve {ok, mudou, de, para, texto, acao_id, check_in_at, check_out_at; na conclusão cobrancas e cobrancas_texto; na conversão convertido, numero, numero_antes}.';

-- ── Portas (as mesmas de 20261026100600) ───────────────────────────────────────────────────────────────
revoke all on function public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz)
  from public, anon;
grant execute on function public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz)
  to authenticated, service_role;

-- Agenda de Produção, Fase 3 ("A execução: equipe, diária, conclusão e telas"), pacote P3: a conclusão nos caminhos — a
-- conversa (o rascunho do andamento ganha concluiu e entregou; o *grava* conclui pela porta), as palavras sem IA
-- *concluiu* e *entreguei* e o *desfaz* que acha a OS concluída. A tela, a assinatura do cliente e o assistente passam pela
-- porta no código (src/hooks/use-service-orders.ts, supabase/functions/submit-signature, _shared/ai/tools/service-orders.ts).
-- Spec: scratchpad agenda-pesquisa/spec-fase3.md (§6; §3.1 princípio 5, §3.3 d4–d6, d25, d27; §11; §13.4, §13.5).
-- Notas entre pacotes: notas-fase3.md ("P2 — feito": a porta de 9 argumentos, os_registrar_marco, o retorno da conclusão).
-- Depende de 20261026100100 (a porta completa, os_registrar_marco, _os_recebiveis_da_conclusao, o desfazer da conclusão)
-- e das Fases 1 e 2 inteiras.
--
-- ═══ DDL — OK NOMEADO ═══ (funções novas e recriadas; nenhuma tabela, nenhuma coluna, nenhum dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE (o D7, o resto): o P2 pôs a conclusão no banco (a saída e as cobranças da condição na mesma transação), mas
-- quem concluía ainda chegava por fora: a tela fazia o UPDATE dela, a assinatura do cliente fazia o dela, e o assistente
-- recusava ("concluir é pela tela"). Aqui a conversa e as palavras do dono concluem e entregam pela porta, sempre com a
-- releitura do que vai sair (a saída e as cobranças, calculadas agora pelo banco e sem gravar) ou com a ordem exata dele.
--
-- O QUE MUDA:
--   1. agenda_rascunho_andamento (corpo de 20261025100400, -- FASE 3:): os eventos concluiu (e "terminou", "acabou",
--      "finalizou", "pronto") e entregou (e "entregue") deixam de ser recusados e viram RASCUNHO pela
--      _agenda_rascunho_marco: a releitura "Concluo o Lenine (OS-00074) hoje (qui 29/10): fica registrada a saída, e
--      saem as cobranças da condição: Entrada 50% R$ 2.280,00 (vence hoje) · Saldo 50% R$ 2.280,00 (vence hoje)." (as
--      cobranças por _os_recebiveis_da_conclusao, sem gravar). Chave andamento:<os>:<dia>:concluiu|entregou.
--   2. _agenda_aplicar_pedido (corpo de 20261025100400, -- FASE 3:): concluiu/entregou → os_registrar_marco (via dono).
--      A recusa da porta (período fechado) é a exceção P0096 com a frase dela.
--   3. agenda_rascunho_gravar (corpo de 20261025100400, -- FASE 3:): concluir e entregar gravam em todos os modos (o
--      lote só com eles não é recusado "em teste"); P0096 → "Não gravei nada. Não concluí: o período de outubro está
--      fechado no financeiro (…)." e o lote inteiro volta.
--   4. agenda_concluir_dito(autor, alvo, canal, …) e agenda_entregar_dito(…): as palavras *concluiu [<alvo>]* e
--      *entreguei <alvo>* (executam direto: é a ordem exata do dono). Sem alvo, a OS do plano de hoje se for uma só; mais
--      de uma = a pergunta ("Qual? Vanderlei (OS-00069) ou Flávio (OS-00104)? Diga *concluiu Vanderlei*."). Alvo que o
--      banco não acha = {status nao_achei} (o turno segue ao modelo). Respostas: "Concluí o Lenine (OS-00074) hoje (qui
--      29/10, 16:30). Saíram as cobranças da condição: … *desfaz OS-00074* volta como estava." e "Lenine (OS-00074):
--      ainda estava agendada; concluí e marquei a entrega (…). …".
--   5. agenda_acao_desfazivel (corpo de 20261025100200, -- FASE 3:): a OS concluída ou entregue sai da carteira, e o
--      "desfaz <a OS>" passa a achá-la pelo id que o resolvedor devolve fora da carteira, quando ela tem mudança da agenda
--      ainda desfazível (a conclusão pela palavra ou pela conversa, por 24 h).
--   Auxiliares: _os_levantamentos_pendentes e _os_texto_do_levantamento (o D11, abaixo), _agenda_rascunho_marco (a
--   releitura de concluir/entregar), _agenda_os_da_entrega (a OS de "entreguei <nome>": antes as concluídas pela porta e
--   não entregues, depois a carteira), _agenda_cobrancas_da_releitura (as cobranças que sairiam hoje, em texto),
--   _agenda_cobrancas_da_palavra (o texto das cobranças da porta na voz das palavras).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase3_caminhos.sql):
--   · Concluir e entregar pela conversa e pelas palavras NÃO passam pela guarda "a agenda automática ainda está em teste"
--     (_agenda_pedido_recusa) nem pela do *grava* (modo_proposta fora de ligado): a §3.1 (5) diz que a conclusão pela porta
--     vale em todos os modos. Na Fase 2 o lote com qualquer andamento era recusado fora de ligado; os outros eventos
--     continuam assim.
--   · O dia de concluir e de entregar é sempre hoje: as cobranças da conclusão usam p_hoje (a régua da tela) e a saída é a
--     hora do *grava*. "O Lenine terminou ontem" = a pergunta ("A conclusão fica com a data de hoje …"), nada no rascunho.
--   · Orçamento não conclui pela conversa nem pela palavra ("Robson (ORÇ-00083) ainda é orçamento: converta em OS antes de
--     concluir."): a porta converteria e concluiria junto, pulando o sinal que o orçamento talvez ainda espere.
--   · "entreguei <nome>" procura primeiro a OS concluída e ainda não entregue (fora da carteira): o barco concluído na
--     sexta é entregue na segunda, e o nome só na carteira mandaria a entrega para outra OS do mesmo cliente. Primeiro só
--     as concluídas pela porta (com ação concluir): as conclusões de antes da Fase 3 não têm entrega registrada, e o nome
--     acharia todas. Sem nenhuma delas, a carteira; e, sem nada na carteira, a única OS do nome fora dela, se concluída.
--   · A dica do desfazer usa o NÚMERO (*desfaz OS-00074*), não o nome: com outra OS do mesmo cliente na carteira, o nome
--     acharia aquela e responderia "não tenho mudança minha". E agenda_acao_desfazivel passou a achar a OS que saiu da
--     carteira (item 5) — sem isso, nem o número desfazia.
--   · As cobranças nos textos seguem a régua da porta ("<rótulo> R$ X (vence hoje)"), não ", vence hoje" da spec.
--   · A trava do levantamento (D11 do dono, 17/09: concluir exige o levantamento respondido nos serviços marcados "exige
--     levantamento") só existia no formulário da OS (src/lib/levantamento-gate.ts), e o próprio comentário de lá pedia
--     que viesse junto quando a conversa voltasse a concluir. A spec não dizia: a conversa e as palavras recusam com a
--     frase do formulário (_os_levantamentos_pendentes). A porta (100100) não confere: a lista rápida e os kanbans
--     continuam sem a trava, como antes — fica para o dono decidir (pendência).
--
-- O QUE NÃO MUDA: a porta, o desfazer da conclusão e os marcos (20261026100100); a régua do dinheiro (a paridade com a
-- tela, inclusive o NOVO-agenda-22); os outros eventos do andamento, marcar, publicar, decidir e desfazer da Fase 2.
--
-- ORDEM DE LIGAR: depois de 20261026100100. O front (a tela pela porta), o submit-signature e o update_service_order_status
-- do assistente podem sair antes das migrations: sem a porta completa (100100), o plano B
-- (supabase/functions/_shared/porta-ausente.ts) os faz seguir pelo caminho de antes. As palavras *concluiu*/*entreguei* e o
-- concluir pela conversa (ai-agent, erp-mcp, whatsapp-webhook) dependem DESTA migration: publicar o código antes dela só
-- faz a palavra responder "Não consegui concluir agora" (a RPC não existe) e o andamento recusar como na Fase 2.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase3_caminhos.sql (begin/rollback; os cenários só na bancada, com
-- fixture-fase3.sql). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261026100200
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261026100200_agenda_fase3_caminhos.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261026100200', 'agenda_fase3_caminhos');"
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 0. A trava do levantamento (D11) ───────────────────────────────────────────────────────────────────────
-- D11 (decisão do dono, 17/09/2026): concluir exige o levantamento RESPONDIDO nos serviços marcados "exige levantamento"
-- (services.requires_survey). O espelho de levantamentosPendentesParaConcluir (src/lib/levantamento-gate.ts), que só o
-- formulário da OS conferia: os nomes dos serviços desta OS sem levantamento fechado (vazio = pode concluir). A conversa e
-- as palavras que concluem (abaixo) recusam com a mesma frase do formulário.
create or replace function public._os_levantamentos_pendentes(p_os uuid)
 returns text[]
 language sql
 stable
 set search_path to 'public'
as $function$
  -- (o mesmo serviço em duas linhas sai uma vez, na ordem em que entrou na OS)
  select coalesce(array_agg(x.nome order by x.primeira), '{}')
    from (select s.name_snapshot as nome, min(s.created_at) as primeira
            from public.service_order_services s
            join public.services sv on sv.id = s.service_id
           where s.service_order_id = p_os and sv.requires_survey
             and not exists (select 1 from public.service_surveys v
                              where v.service_order_id = p_os and v.service_id = s.service_id and v.status = 'closed')
           group by s.name_snapshot) x;
$function$;

comment on function public._os_levantamentos_pendentes(uuid) is
  'Agenda de Produção (Fase 3, P3): D11 — os serviços da OS marcados "exige levantamento" (services.requires_survey) sem levantamento fechado (service_surveys closed); vazio = pode concluir. Espelho de levantamentosPendentesParaConcluir (src/lib/levantamento-gate.ts).';

-- A frase do formulário para o D11.
create or replace function public._os_texto_do_levantamento(p_pendentes text[])
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select format('Para concluir, responda o levantamento de: %s. Esses serviços estão marcados como "exige levantamento".',
                array_to_string(p_pendentes, ', '));
$function$;

comment on function public._os_texto_do_levantamento(text[]) is
  'Agenda de Produção (Fase 3, P3): a frase do formulário da OS para o D11 ("Para concluir, responda o levantamento de: …").';

-- ── 1. Os textos das cobranças: a releitura (antes) e as palavras (depois) ──────────────────────────────────

-- As cobranças que a conclusão lançaria HOJE, sem gravar nada (a releitura do *grava*), na régua do texto da porta
-- (_os_cobrancas_texto: o rótulo da parcela, o valor e o vencimento):
--   "sai a cobrança da condição: Saldo R$ 2.800,00 (vence hoje)"
--   "saem as cobranças da condição: Entrada 50% R$ 2.280,00 (vence hoje) · Saldo 50% R$ 2.280,00 (vence hoje)"
--   "as cobranças já existem (sinal pago); o saldo na entrega (R$ 2.800,00) passa a vencer hoje"
--   "não sai cobrança: o total da OS está zerado"
create or replace function public._agenda_cobrancas_da_releitura(p_os uuid, p_hoje date)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_r     jsonb := public._os_recebiveis_da_conclusao(p_os, p_hoje);
  v_itens text[];
  v_soma  numeric;
  v_sinal boolean;
begin
  if v_r ->> 'motivo' in ('parcelas', 'titulo_unico') then
    v_itens := array(
      select coalesce(nullif(l ->> 'rotulo', '') || ' ', '') || public._brl((l ->> 'amount')::numeric)
             || ' (vence ' || case when (l ->> 'due_date')::date = p_hoje then 'hoje'
                                   else public._dia_curto((l ->> 'due_date')::date) end || ')'
        from jsonb_array_elements(v_r -> 'linhas') with ordinality t(l, o)
       order by o);
    return case when cardinality(v_itens) = 1 then 'sai a cobrança da condição: ' else 'saem as cobranças da condição: ' end
           || array_to_string(v_itens, ' · ');
  end if;
  if v_r ->> 'motivo' = 'total_zero' then
    return 'não sai cobrança: o total da OS está zerado';
  end if;
  -- Já tem (o sinal ou outra cobrança viva): nada nasce; o saldo "na entrega" passa a vencer no dia da saída (o gatilho).
  select sum((e ->> 'amount')::numeric) into v_soma
    from jsonb_array_elements(coalesce(v_r -> 'vencem_na_entrega', '[]'::jsonb)) e;
  v_sinal := exists (select 1 from public.receivables r
                      where r.service_order_id = p_os and r.is_deposit and r.status in ('paid', 'partially_paid'));
  return 'as cobranças já existem' || case when v_sinal then ' (sinal pago)' else '' end
         || case when v_soma is not null then format('; o saldo na entrega (%s) passa a vencer hoje', public._brl(v_soma))
                 else '' end;
end;
$function$;

comment on function public._agenda_cobrancas_da_releitura(uuid, date) is
  'Agenda de Produção (Fase 3, P3): as cobranças que a conclusão da OS lançaria hoje, sem gravar (_os_recebiveis_da_conclusao), em texto para a releitura: "sai a cobrança da condição: <rótulo> R$ X (vence hoje)", "saem as cobranças da condição: … · …", "as cobranças já existem (sinal pago); o saldo na entrega (R$ X) passa a vencer hoje" ou "não sai cobrança: o total da OS está zerado".';

-- O texto das cobranças que a porta devolve (cobrancas_texto) na voz das palavras: "Cobrança: X." → "Saiu a cobrança da
-- condição: X."; "Cobranças: X · Y." → "Saíram as cobranças da condição: X · Y."; o resto ("As cobranças já existiam…",
-- "Sem cobrança: …") como está.
create or replace function public._agenda_cobrancas_da_palavra(p_cob text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when p_cob like 'Cobrança: %'  then 'Saiu a cobrança da condição: ' || substr(p_cob, char_length('Cobrança: ') + 1)
    when p_cob like 'Cobranças: %' then 'Saíram as cobranças da condição: ' || substr(p_cob, char_length('Cobranças: ') + 1)
    else coalesce(p_cob, '') end;
$function$;

comment on function public._agenda_cobrancas_da_palavra(text) is
  'Agenda de Produção (Fase 3, P3): o cobrancas_texto da porta na voz das palavras — "Cobrança: X." vira "Saiu a cobrança da condição: X.", "Cobranças: …" vira "Saíram as cobranças da condição: …"; o resto fica.';

-- ── 2. A OS de "entreguei <alvo>" ──────────────────────────────────────────────────────────────────────────
-- O número (ou o id) acha a OS dentro ou fora da carteira, e a concluída (fora dela) vale. O nome procura ANTES as OS
-- concluídas pela porta (com ação concluir da agenda, não desfeita) e ainda não entregues — o barco concluído na sexta é
-- entregue na segunda —, e só sem nenhuma delas a carteira (a entrega de uma OS ainda aberta conclui junto). As duas
-- (ou mais de uma concluída) = a pergunta, nunca a escolha. Sem nenhuma à espera, a única OS do nome fora da carteira vale
-- se estiver concluída (a já entregue responde "já foi entregue"). A régua do nome é a de agenda_resolver_os (todo pedaço de 3+
-- letras começa uma palavra do nome do cliente ou do bem; as mesmas palavras vazias).
create or replace function public._agenda_os_da_entrega(p_ref text, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_ref    text := btrim(coalesce(p_ref, ''));
  v_norm   text := public._agenda_normal(p_ref);
  v_comp   text := regexp_replace(public._agenda_normal(p_ref), '[^a-z0-9]', '', 'g');
  v_ro     jsonb := public.agenda_resolver_os(p_ref, p_hoje, false);
  v_tokens text[];
  v_conc   jsonb;
  v_n      int;
  v_opcoes jsonb;
  c_vazias constant text[] := array['barco', 'lancha', 'veleiro', 'iate', 'motorhome', 'embarcacao', 'servico',
                                     'orcamento', 'cliente', 'ordem', 'dos', 'das', 'pro', 'pra', 'para'];
begin
  -- pelo número (ou id): o resolvedor já olha dentro e fora da carteira
  if v_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or v_comp ~ '^(orcamento|orc|os|ordem)?[0-9]{1,8}$' then
    if v_ro ->> 'status' = 'fora_da_carteira' and v_ro ->> 'situacao' in ('completed', 'invoiced') then
      return v_ro || jsonb_build_object('status', 'ok');
    end if;
    return v_ro;
  end if;

  v_tokens := array(select t from unnest(string_to_array(v_norm, ' ')) with ordinality u(t, o)
                     where length(regexp_replace(t, '[^a-z]', '', 'g')) >= 3 and t <> all (c_vazias)
                     order by o);
  if cardinality(v_tokens) = 0 then
    return v_ro;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', x.id, 'numero', x.numero, 'cliente_curto', x.curto, 'situacao', x.status,
           'texto', format('%s (%s, %s)', x.curto, x.numero, public._agenda_status_texto(x.status)))
           order by x.saida desc nulls last, x.id), '[]'::jsonb),
         count(*)
    into v_conc, v_n
    from (select so.id, so.service_order_number as numero, so.status, so.check_out_at as saida,
                 public._agenda_nome_curto(cl.name) as curto,
                 string_to_array(public._agenda_normal(concat_ws(' ', cl.name, cl.display_name, vs.name)), ' ') as palavras
            from public.service_orders so
            left join public.clients cl on cl.id = so.client_id
            left join public.vessels vs on vs.id = so.vessel_id
           where so.status in ('completed', 'invoiced') and so.delivered_at is null
             and exists (select 1 from public.agenda_acoes a
                          where a.service_order_id = so.id and a.tipo = 'concluir' and a.executada and a.desfeita_em is null)) x
   where not exists (select 1 from unnest(v_tokens) t
                      where not exists (select 1 from unnest(x.palavras) w where w like t || '%'));

  if v_n = 0 then
    -- nenhuma concluída pela porta à espera da entrega: a carteira (a entrega conclui junto) ou a única OS do nome fora
    -- dela, se estiver concluída (a já entregue responde "já foi entregue"; a concluída antes da Fase 3 também entrega)
    if v_ro ->> 'status' = 'fora_da_carteira' and v_ro ->> 'situacao' in ('completed', 'invoiced') then
      return v_ro || jsonb_build_object('status', 'ok');
    end if;
    return v_ro;
  end if;
  if v_n = 1 and v_ro ->> 'status' <> 'ok' then
    return (v_conc -> 0) || jsonb_build_object('status', 'ok', 'eh_orcamento', false, 'opcoes', '[]'::jsonb);
  end if;
  v_opcoes := v_conc
    || case when v_ro ->> 'status' = 'ok' then jsonb_build_array(jsonb_build_object(
         'id', v_ro ->> 'id', 'numero', v_ro ->> 'numero', 'cliente_curto', v_ro ->> 'cliente_curto',
         'texto', format('%s (%s, %s)', v_ro ->> 'cliente_curto', v_ro ->> 'numero',
                         public._agenda_status_texto((select so.status from public.service_orders so
                                                       where so.id = (v_ro ->> 'id')::uuid)))))
            else '[]'::jsonb end;
  return jsonb_build_object('status', 'ambiguo', 'opcoes', v_opcoes,
    'texto', format('Qual? %s? Diga *entreguei* e o número.',
                    (select string_agg(e ->> 'texto', ' ou ' order by o)
                       from jsonb_array_elements(v_opcoes) with ordinality t(e, o))));
end;
$function$;

comment on function public._agenda_os_da_entrega(text, date) is
  'Agenda de Produção (Fase 3, P3): a OS de "entreguei <alvo>" — o número (ou id) pelo agenda_resolver_os, valendo a concluída fora da carteira; o nome primeiro entre as concluídas pela porta (ação concluir da agenda) e ainda não entregues, depois na carteira; as duas, ou mais de uma concluída = {status ambiguo, texto "Qual? Lenine (OS-00074, concluída) ou Lenine (OS-00080, em andamento)? Diga *entreguei* e o número."}. Mesmo formato do agenda_resolver_os.';

-- ── 3. A releitura de concluir e de entregar (o rascunho; nada muda antes do *grava*) ─────────────────────
-- Chamada por agenda_rascunho_andamento com o evento já normalizado (concluiu | entregou) e o autor já conferido. Vale em
-- todos os modos da agenda (a conclusão pela porta é a correção do D7); pede só o canal e o trecho do dono. O dia é hoje.
create or replace function public._agenda_rascunho_marco(p_autor uuid, p_canal text, p_os text, p_evento text, p_dia text,
                                                          p_trecho text, p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_ro     jsonb;
  v_os     uuid;
  v_so     record;
  v_dt     jsonb;
  v_rotulo text;
  v_grupo  text;
  v_titulo text;
  v_frase  text;
  v_item   text;
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_rascunho_andamento: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;
  if p_evento is null or p_evento not in ('concluiu', 'entregou') then
    raise exception '_agenda_rascunho_marco: evento "%" não existe (concluiu ou entregou)', p_evento using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_trecho, '')), '') is null then
    return public._agenda_recusa('Me diga com as suas palavras o que aconteceu na OS.', 'sem_trecho');
  end if;

  -- O dia é sempre hoje: as cobranças da conclusão saem com a data de hoje (a régua da tela) e a saída é a hora do *grava*.
  if nullif(btrim(coalesce(p_dia, '')), '') is not null and public._agenda_normal(p_dia) <> 'hoje' then
    v_dt := public._agenda_data_conferida(p_dia, p_trecho, p_hoje, 'passado');
    if not (v_dt ->> 'ok')::boolean then
      return v_dt;
    end if;
    if (v_dt ->> 'de')::date is distinct from p_hoje or (v_dt ->> 'ate')::date is distinct from p_hoje then
      return public._agenda_recusa(case when p_evento = 'concluiu'
        then 'A conclusão fica com a data de hoje (é nela que entram a saída e as cobranças): me diga sem o dia.'
        else 'A entrega fica com a data de hoje: me diga sem o dia.' end, 'so_hoje');
    end if;
  end if;

  v_ro := case when p_evento = 'entregou' then public._agenda_os_da_entrega(p_os, p_hoje)
               else public.agenda_resolver_os(p_os, p_hoje, false) end;
  if v_ro ->> 'status' = 'fora_da_carteira' and v_ro ->> 'situacao' in ('completed', 'invoiced') then
    return public._agenda_recusa(format('%s (%s) já está %s.', v_ro ->> 'cliente_curto', v_ro ->> 'numero',
                                        public._agenda_status_texto(v_ro ->> 'situacao')), 'ja_concluida');
  end if;
  if v_ro ->> 'status' <> 'ok' then
    return public._agenda_recusa_da_os(v_ro);
  end if;
  v_os := (v_ro ->> 'id')::uuid;
  select so.status, so.check_out_at, so.delivered_at into v_so from public.service_orders so where so.id = v_os;
  v_rotulo := public._agenda_rotulo_da_os(v_os);
  -- Orçamento não conclui por aqui: a porta converteria e concluiria junto, pulando o sinal que ele talvez ainda espere.
  if v_so.status = 'draft' then
    return public._agenda_recusa(format('%s ainda é orçamento: converta em OS antes de concluir.', v_rotulo), 'orcamento');
  end if;
  -- D11: concluir (ou entregar o que ainda não foi concluído) exige o levantamento respondido.
  if (p_evento = 'concluiu' or v_so.status not in ('completed', 'invoiced'))
     and cardinality(public._os_levantamentos_pendentes(v_os)) > 0 then
    return public._agenda_recusa(public._os_texto_do_levantamento(public._os_levantamentos_pendentes(v_os)), 'levantamento');
  end if;
  if p_evento = 'entregou' and v_so.delivered_at is not null then
    return public._agenda_recusa(format('O %s já foi entregue em %s.', v_rotulo,
                                        public._dia_curto((v_so.delivered_at at time zone 'America/Sao_Paulo')::date)), 'ja_entregue');
  end if;

  if p_evento = 'concluiu' then
    v_grupo  := 'concluir:' || v_os;
    v_titulo := format('Concluo o %s hoje (%s)', v_rotulo, public._dia_curto(p_hoje));
    v_frase  := 'fica registrada a saída, e ' || public._agenda_cobrancas_da_releitura(v_os, p_hoje);
  else
    v_grupo  := 'entregar:' || v_os;
    v_titulo := format('Marco a entrega do %s hoje (%s)', v_rotulo, public._dia_curto(p_hoje));
    v_frase  := case when v_so.status in ('completed', 'invoiced')
      then 'a conclusão já está registrada'
           || coalesce(' (saída ' || public._dia_curto((v_so.check_out_at at time zone 'America/Sao_Paulo')::date) || ')', '')
      else format('ainda está %s, então concluo junto: fica registrada a saída, e %s', public._agenda_status_texto(v_so.status),
                  public._agenda_cobrancas_da_releitura(v_os, p_hoje)) end;
  end if;

  v_item := public._agenda_rascunho_salvar(p_autor, p_canal, 'andamento', format('andamento:%s:%s:%s', v_os, p_hoje, p_evento),
              v_os,
              jsonb_build_object('grupo', v_grupo, 'rotulo_grupo', v_titulo, 'os', v_os, 'dia', p_hoje, 'evento', p_evento,
                                 'frase_pronta', v_frase),
              p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_item,
                            'releitura', public.agenda_rascunho_ler(p_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public._agenda_rascunho_marco(uuid, text, text, text, text, text, date) is
  'Agenda de Produção (Fase 3, P3): concluiu/entregou da conversa vira RASCUNHO (nada muda) — a OS por agenda_resolver_os (concluir) ou _agenda_os_da_entrega (entregar); orçamento, levantamento pendente (D11), já concluída (concluir), já entregue (entregar), dia que não é hoje e sem trecho = a pergunta. Releitura: "Concluo o Lenine (OS-00074) hoje (qui 29/10): fica registrada a saída, e saem as cobranças da condição: …" / "Marco a entrega do Lenine (OS-00074) hoje (sex 30/10): a conclusão já está registrada (saída qui 29/10)" (ainda aberta: "ainda está agendada, então concluo junto: …"). Chave andamento:<os>:<dia>:concluiu|entregou. Vale em todos os modos.';

-- ── 4. O andamento da conversa: concluir e entregar viram rascunho ────────────────────────────────────────
-- Corpo de 20261025100400 copiado; as mudanças estão marcadas "-- FASE 3:".

create or replace function public.agenda_rascunho_andamento(p_autor uuid, p_canal text, p_os text, p_evento text,
                                                            p_dia text default null, p_quem text[] default null,
                                                            p_motivo text default null, p_trecho text default null,
                                                            p_hoje date default public._hoje_brt(),
                                                            p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor   uuid := public._autor_da_agenda(p_autor);
  v_ev      text := public._agenda_normal(p_evento);
  v_rec     jsonb;
  v_ro      jsonb;
  v_os      uuid;
  v_status  text;
  v_dia     date := p_hoje;
  v_dt      jsonb;
  v_rp      jsonb;
  v_x       text;
  v_pes     uuid[];
  v_nomes   text[] := '{}';
  v_quem    text;
  v_motivo  text;
  v_res     text;
  v_m       boolean;
  v_t       boolean;
  v_turnos  text;
  v_fora    text[];
  v_check   timestamptz;
  v_para    text;
  v_futuros date[];
  v_frase   text;
  v_chave   text;
  v_plural  boolean;
  v_txt     text;
begin
  -- FASE 3: concluir e entregar viram RASCUNHO com a releitura da saída e das cobranças da condição (o *grava* passa pela
  -- porta: os_registrar_marco, via dono), em todos os modos. "terminou", "acabou", "finalizou" e "pronto" são concluir;
  -- "entregue" é entregar.
  if v_ev in ('concluiu', 'concluida', 'concluido', 'terminou', 'acabou', 'finalizou', 'entregou', 'entregue', 'pronto', 'pronta') then
    return public._agenda_rascunho_marco(v_autor, p_canal, p_os,
                                         case when v_ev in ('entregou', 'entregue') then 'entregou' else 'concluiu' end,
                                         p_dia, p_trecho, p_hoje);
  end if;
  if v_ev not in ('trabalhou', 'parcial', 'nao foi', 'nao_foi', 'comecou', 'parou') then
    -- FASE 3: a lista do erro ganha concluiu e entregou.
    raise exception 'agenda_rascunho_andamento: evento "%" não existe (trabalhou, parcial, nao_foi, comecou, parou, concluiu ou entregou)', p_evento
      using errcode = '22023';
  end if;
  v_ev := replace(v_ev, ' ', '_');
  v_rec := public._agenda_pedido_recusa(p_canal, p_trecho, 'agenda_rascunho_andamento');
  if v_rec is not null then
    return v_rec;
  end if;

  v_ro := public.agenda_resolver_os(p_os, p_hoje, false);
  if v_ro ->> 'status' <> 'ok' then
    return public._agenda_recusa_da_os(v_ro);
  end if;
  v_os := (v_ro ->> 'id')::uuid;
  select so.status into v_status from public.service_orders so where so.id = v_os;

  if nullif(btrim(coalesce(p_dia, '')), '') is not null then
    v_dt := public._agenda_data_conferida(p_dia, p_trecho, p_hoje, 'passado');
    if not (v_dt ->> 'ok')::boolean then return v_dt; end if;
    if (v_dt ->> 'de') is distinct from (v_dt ->> 'ate') then
      return public._agenda_recusa('Diga um dia só (por exemplo "hoje", "ontem" ou "segunda").', 'um_dia');
    end if;
    v_dia := (v_dt ->> 'de')::date;
  end if;
  if v_dia > p_hoje then
    return public._agenda_recusa(public._agenda_maiuscula(public._dia_curto(v_dia)) || ' ainda não chegou: não dá para dizer como foi.',
                                 'dia_futuro');
  end if;

  if p_quem is not null and cardinality(p_quem) > 0 then
    v_pes := '{}';
    foreach v_x in array p_quem loop
      v_rp := public.agenda_resolver_pessoa(v_x, v_autor, p_hoje);
      if v_rp ->> 'status' <> 'ok' then
        return public._agenda_recusa(v_rp ->> 'texto', 'pessoa_' || (v_rp ->> 'status'),
          coalesce((select jsonb_agg(e ->> 'nome' order by o)
                      from jsonb_array_elements(coalesce(v_rp -> 'opcoes', '[]'::jsonb)) with ordinality t(e, o)), '[]'::jsonb));
      end if;
      continue when (v_rp ->> 'payee_id')::uuid = any (v_pes);
      v_pes := v_pes || (v_rp ->> 'payee_id')::uuid;
      v_nomes := v_nomes || case when coalesce((v_rp ->> 'eh_dono')::boolean, false) then 'você' else v_rp ->> 'nome_curto' end;
    end loop;
    v_quem := public._agenda_lista(v_nomes, null);
    v_plural := cardinality(v_pes) > 1;
  end if;

  v_motivo := public._agenda_motivo_dito(p_motivo);
  if v_ev in ('parcial', 'nao_foi') and v_motivo is null then
    return public._agenda_recusa('Me diga o motivo: material, cliente, equipe, clima, imprevisto, anterior, informação, estimativa, urgência ou esqueci.',
                                 'sem_motivo');
  end if;

  if v_ev in ('trabalhou', 'parcial', 'nao_foi') then
    v_res := case v_ev when 'trabalhou' then 'cumprido' when 'parcial' then 'parcial' else 'nao_cumprido' end;
    -- o plano do dia: quem estava, e (para feito e em parte) o que já começou
    if not exists (select 1 from public.agenda_alocacoes a
                    where a.service_order_id = v_os and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva') then
      return public._agenda_recusa(format('%s não estava no plano %s. Para a diária de quem trabalhou, me diga quem e quanto.',
                                          public._agenda_rotulo_da_os(v_os), public._agenda_dia_ref(v_dia, p_hoje)), 'fora_do_plano');
    end if;
    if v_pes is not null then
      v_fora := array(select n from unnest(v_pes, v_nomes) u(p, n)
                       where not exists (select 1 from public.agenda_alocacoes a
                                          where a.service_order_id = v_os and a.dia = v_dia and a.estado in ('publicada', 'fixada')
                                            and a.tipo <> 'reserva' and a.payee_id = u.p));
      if cardinality(v_fora) > 0 then
        return public._agenda_recusa(format('Pelo plano, %s não %s no %s %s.', public._agenda_lista(v_fora, null),
                                            case when cardinality(v_fora) > 1 then 'estavam' else 'estava' end,
                                            v_ro ->> 'cliente_curto', public._agenda_dia_ref(v_dia, p_hoje)), 'pessoa_fora_do_plano');
      end if;
    end if;
    if v_res <> 'nao_cumprido'
       and not exists (select 1 from public.agenda_alocacoes a
                        where a.service_order_id = v_os and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                          and (v_pes is null or a.payee_id = any (v_pes)) and lower(a.periodo) <= p_agora) then
      return public._agenda_recusa(format('Ainda não começou nada do plano do %s %s.', v_ro ->> 'cliente_curto',
                                          public._agenda_dia_ref(v_dia, p_hoje)), 'nao_comecou');
    end if;
    select bool_or(a.turno = 'manha'), bool_or(a.turno = 'tarde') into v_m, v_t
      from public.agenda_alocacoes a
     where a.service_order_id = v_os and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
       and (v_pes is null or a.payee_id = any (v_pes));
    v_turnos := case when v_m and v_t then ' o dia todo' when v_m then ' de manhã' when v_t then ' à tarde' else '' end;
    v_frase := case
      when v_ev = 'trabalhou' and v_quem is null then 'feito, com ' || public._agenda_quem(v_os, v_dia)
      when v_ev = 'trabalhou' then v_quem || case when v_plural then ' trabalharam' else ' trabalhou' end || v_turnos
      when v_ev = 'parcial' and v_quem is null then format('andou em parte (%s)', public._agenda_motivo_texto(v_motivo))
      when v_ev = 'parcial' then format('%s %s em parte (%s)', v_quem, case when v_plural then 'trabalharam' else 'trabalhou' end,
                                        public._agenda_motivo_texto(v_motivo))
      when v_quem is null then format('não andou (%s)', public._agenda_motivo_texto(v_motivo))
      else format('%s %s (%s)', v_quem, case when v_plural then 'não foram' else 'não foi' end, public._agenda_motivo_texto(v_motivo)) end;
    v_chave := format('andamento:%s:%s:%s', v_os, v_dia,
                      coalesce('p' || left(md5((select string_agg(x::text, ',' order by x) from unnest(v_pes) x)), 20), 'todos'));

  elsif v_ev = 'comecou' then
    if v_status = 'in_progress' then
      return public._agenda_recusa(format('%s já está em andamento.', public._agenda_rotulo_da_os(v_os)), 'ja_em_andamento');
    end if;
    if v_status not in ('open', 'approved', 'scheduled', 'awaiting_parts', 'awaiting_client') then
      return public._agenda_recusa(format('%s está %s: a agenda não muda o status dela.', public._agenda_rotulo_da_os(v_os),
                                          public._agenda_status_texto(v_status)), 'status');
    end if;
    -- o início é a manhã do dia dito (o banco deriva a hora; ninguém grava hora dita)
    v_check := lower(public.agenda_periodo(v_dia, 'manha'));
    v_frase := format('começou (início às %s)', to_char(v_check at time zone 'America/Sao_Paulo', 'HH24:MI'));
    v_chave := format('andamento:%s:%s:status', v_os, v_dia);

  else  -- parou
    if v_motivo is null or v_motivo not in ('material', 'cliente_ou_bem') then
      return public._agenda_recusa('Parou por quê? Se falta peça, diga material; se o cliente ou o barco não liberou, diga cliente.',
                                   'parou_motivo');
    end if;
    v_para := case when v_motivo = 'material' then 'awaiting_parts' else 'awaiting_client' end;
    if v_status = v_para then
      return public._agenda_recusa(format('%s já está %s.', public._agenda_rotulo_da_os(v_os), public._agenda_status_texto(v_para)),
                                   'ja_esta');
    end if;
    if v_status not in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client') then
      return public._agenda_recusa(format('%s está %s: a agenda não muda o status dela.', public._agenda_rotulo_da_os(v_os),
                                          public._agenda_status_texto(v_status)), 'status');
    end if;
    v_futuros := array(select distinct a.dia from public.agenda_alocacoes a
                        where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.resultado is null
                          and lower(a.periodo) > p_agora order by 1);
    v_frase := format('parou (%s): passa a %s%s', public._agenda_motivo_texto(v_motivo), public._agenda_status_texto(v_para),
                      case when cardinality(v_futuros) > 0
                           then ' e sai da agenda ' || public._agenda_dias_texto(v_futuros) else '' end);
    v_chave := format('andamento:%s:%s:status', v_os, v_dia);
  end if;

  v_txt := public._agenda_rascunho_salvar(v_autor, p_canal, 'andamento', v_chave, v_os,
             jsonb_build_object('grupo', format('andamento:%s:%s', v_os, v_dia),
                                'rotulo_grupo', public._agenda_maiuscula(public._agenda_dia_ref(v_dia, p_hoje)) || ', '
                                                || public._agenda_rotulo_da_os(v_os),
                                'os', v_os, 'dia', v_dia, 'evento', v_ev, 'resultado', v_res, 'pessoas', to_jsonb(v_pes),
                                'nomes', to_jsonb(v_nomes), 'motivo', v_motivo, 'status_para', v_para, 'check_in', v_check,
                                'frase_pronta', v_frase),
             p_trecho, p_hoje);
  return jsonb_build_object('ok', true, 'item', v_txt,
                            'releitura', public.agenda_rascunho_ler(v_autor, p_hoje) ->> 'texto');
end;
$function$;

comment on function public.agenda_rascunho_andamento(uuid, text, text, text, text, text[], text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P4): o que aconteceu na OS vira RASCUNHO (nada muda) — trabalhou · parcial · nao_foi (o resultado do meio-dia no plano: as pessoas ditas têm de estar no plano do dia; feito e em parte só no que já começou; parcial e não foi pedem o motivo LCI) · comecou (em andamento, com o início na manhã do dia dito) · parou (material → aguardando peças; cliente → aguardando o cliente; sai da agenda o que ainda não começou). Fase 3: concluiu (terminou, acabou, finalizou, pronto) e entregou (entregue) viram rascunho pela _agenda_rascunho_marco, em todos os modos ("Concluo o Lenine (OS-00074) hoje (qui 29/10): fica registrada a saída, e saem as cobranças da condição: …"; o *grava* conclui e entrega pela porta, via dono). O dia por agenda_data_dita (passado, dito no trecho; sem dia = hoje). Chave andamento:<os>:<dia>:<quem> (começou/parou: :status); a releitura junta os fatos da OS no dia ("Hoje (ter 03/11), Vanderlei (OS-00069): Roberto trabalhou o dia todo; João não foi (equipe)."). O *grava* chama agenda_registrar_dia (via conversa) ou a porta (via dono).';

-- ── 5. O *grava*: o que ele faz com cada pedido e o lote ─────────────────────────────────────────────────
-- Corpos de 20261025100400 copiados; as mudanças estão marcadas "-- FASE 3:".

create or replace function public._agenda_aplicar_pedido(p_autor uuid, p_tipo text, p_os uuid, p_dados jsonb, p_trecho text,
                                                         p_canal text, p_hoje date, p_agora timestamptz)
 returns text
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  d       jsonb := coalesce(p_dados, '{}'::jsonb);
  v_r     jsonb;
  v_os    uuid := coalesce(p_os, (d ->> 'os')::uuid);
  v_d1    date;
  v_d2    date;
  v_txts  text[] := '{}';
  v_x     text;
  v_canc  uuid[];
  v_antes jsonb;
  v_dias  date[];
  v_id    uuid;
  v_txt   text;
begin
  if p_tipo = 'marcar' then
    v_r := public.agenda_marcar_os(p_autor, v_os, (d ->> 'de')::date, (d ->> 'ate')::date, nullif(d ->> 'pessoa', '')::uuid,
                                   'dono', 'dono', p_hoje, p_agora);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0097', message = coalesce(v_r ->> 'texto', 'não coube');
    end if;
    -- o dono confirmou aqueles dias: a agenda tem de ter posto a OS neles
    select min(a.dia), max(a.dia) into v_d1, v_d2
      from public.agenda_acoes ac join public.agenda_alocacoes a on a.id = any (ac.alocacoes_criadas)
     where ac.id in (select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'acoes', '[]'::jsonb)) x)
       and a.service_order_id = v_os and a.tipo <> 'reserva';
    if v_d1 is distinct from (d #>> '{simulado,de}')::date or v_d2 is distinct from (d #>> '{simulado,ate}')::date then
      raise exception using errcode = 'P0097',
        message = format('%s ficaria %s, e não %s', public._agenda_rotulo_da_os(v_os),
                         coalesce(public._agenda_dias_texto(array[v_d1, v_d2]::date[]), 'fora da agenda'),
                         public._agenda_dias_texto(array[(d #>> '{simulado,de}')::date, (d #>> '{simulado,ate}')::date]::date[]));
    end if;
    return v_r ->> 'texto';
  end if;

  if p_tipo = 'aplicar' then
    if d ? 'pergunta_id' then
      v_r := public.agenda_decidir((d ->> 'pergunta_id')::uuid, (d ->> 'opcao')::smallint, p_autor, p_canal, p_trecho, p_hoje, p_agora);
    else
      v_r := public.agenda_aplicar((d ->> 'proposta_id')::uuid,
                                   case when jsonb_typeof(d -> 'os_ids') = 'array'
                                        then array(select x::uuid from jsonb_array_elements_text(d -> 'os_ids') x) end,
                                   'dono', p_autor, null, p_hoje, p_agora);
    end if;
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0097', message = coalesce(v_r ->> 'texto', 'não deu');
    end if;
    -- (o "Feito: " da decisão sobra depois do "Gravado. Agora:")
    return regexp_replace(v_r ->> 'texto', '^Feito: ', '');
  end if;

  if p_tipo = 'desfazer' then
    for v_x in select x from jsonb_array_elements_text(coalesce(d -> 'acao_ids', '[]'::jsonb)) x loop
      v_r := public.agenda_desfazer(v_x::uuid, p_autor, 'dono', p_hoje, p_agora);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0097', message = coalesce(v_r ->> 'texto', 'não deu para desfazer');
      end if;
      v_txts := v_txts || (v_r ->> 'texto');
    end loop;
    return array_to_string(v_txts, ' ');
  end if;

  if p_tipo = 'andamento' then
    -- FASE 3: concluir e entregar pela porta (os_registrar_marco, via dono): a saída e as cobranças da condição, tudo ou
    -- nada. A recusa da porta (período fechado) é a exceção P0096 com a frase dela: o lote inteiro volta, e o *grava* diz
    -- "Não gravei nada." e a frase (não "a agenda mudou desde a releitura": quem recusou foi o financeiro).
    if d ->> 'evento' in ('concluiu', 'entregou') then
      v_r := public.os_registrar_marco(v_os, case when d ->> 'evento' = 'concluiu' then 'conclusao' else 'entrega' end, 'dono',
                                       null, p_autor, p_trecho, p_hoje, p_agora);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0096', message = coalesce(v_r ->> 'texto', 'Não concluí.');
      end if;
      return v_r ->> 'texto';
    end if;
    if d ->> 'evento' in ('trabalhou', 'parcial', 'nao_foi') then
      v_r := public.agenda_registrar_dia(p_autor, (d ->> 'dia')::date, d ->> 'resultado', d ->> 'motivo', v_os,
                                         case when jsonb_typeof(d -> 'pessoas') = 'array'
                                              then array(select x::uuid from jsonb_array_elements_text(d -> 'pessoas') x) end,
                                         'conversa', p_trecho, p_hoje, p_agora, p_canal);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0097', message = coalesce(v_r ->> 'texto', 'não deu para anotar o dia');
      end if;
      return v_r ->> 'texto';
    end if;
    if d ->> 'evento' = 'comecou' then
      v_r := public.os_transicionar_status(v_os, 'in_progress', 'dono', null, p_autor, (d ->> 'check_in')::timestamptz, p_hoje, p_agora);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0097', message = coalesce(v_r ->> 'texto', 'não deu para marcar o início');
      end if;
      return v_r ->> 'texto';
    end if;
    if d ->> 'evento' = 'parou' then
      v_r := public.os_transicionar_status(v_os, d ->> 'status_para', 'dono',
                                           'parou (' || public._agenda_motivo_texto(d ->> 'motivo') || ')', p_autor, null, p_hoje, p_agora);
      if not coalesce((v_r ->> 'ok')::boolean, false)
         or (select so.status from public.service_orders so where so.id = v_os) <> d ->> 'status_para' then
        raise exception using errcode = 'P0097', message = coalesce(v_r ->> 'texto', 'não deu para parar a OS');
      end if;
      -- sai da agenda o que ainda não começou (foi o dono que disse: sem desfazer)
      perform set_config('agenda.hoje', p_hoje::text, true);
      perform pg_advisory_xact_lock(hashtext('agenda_plano'));
      select coalesce(array_agg(a.id order by a.dia, a.turno = 'tarde', a.payee_id, a.id), '{}'),
             coalesce(jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'payee_id', a.payee_id, 'dia', a.dia, 'turno', a.turno,
                                                   'presenca', a.presenca, 'tipo', a.tipo, 'estado', a.estado)
                                order by a.dia, a.turno = 'tarde', a.payee_id, a.id), '[]'::jsonb),
             coalesce(array_agg(distinct a.dia), '{}')
        into v_canc, v_antes, v_dias
        from public.agenda_alocacoes a
       where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.resultado is null and lower(a.periodo) > p_agora;
      foreach v_id in array v_canc loop
        if (select estado from public.agenda_alocacoes where id = v_id) = 'fixada' then
          perform set_config('agenda.mexe_fixado', 'on', true);
        end if;
        update public.agenda_alocacoes
           set estado = 'cancelada', cancelada_motivo = case when d ->> 'motivo' = 'material' then 'material' else 'cliente' end
         where id = v_id;
        perform set_config('agenda.mexe_fixado', 'off', true);
      end loop;
      v_txt := v_r ->> 'texto';
      if cardinality(v_canc) > 0 then
        v_txt := v_txt || format(' Tirei da agenda %s.', public._agenda_dias_texto(v_dias));
        insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_canceladas,
                                         status_antes, status_depois, antes, depois, texto, motivo, autor)
        values (clock_timestamp(), p_hoje, true, 'dono', 'cancelar', v_os, array[v_os], v_canc,
                v_r ->> 'de', v_r ->> 'para', jsonb_build_object('alocacoes', v_antes),
                jsonb_build_object('alocacoes', '[]'::jsonb, 'motivo', d ->> 'motivo'),
                left(format('%s: sai da agenda %s — parou (%s).', public._agenda_rotulo_da_os(v_os), public._agenda_dias_texto(v_dias),
                            public._agenda_motivo_texto(d ->> 'motivo')), 400),
                d ->> 'motivo', p_autor);
      end if;
      perform public._agenda_espelhar_datas(v_os, p_hoje);
      return v_txt;
    end if;
  end if;
  raise exception '_agenda_aplicar_pedido: tipo "%" / evento "%" desconhecido', p_tipo, d ->> 'evento' using errcode = '22023';
end;
$function$;

comment on function public._agenda_aplicar_pedido(uuid, text, uuid, jsonb, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P4): o que o *grava* faz com uma linha de pedido — marcar → agenda_marcar_os (via dono; a agenda tem de pôr a OS nos dias da releitura); aplicar → agenda_aplicar (via dono) ou agenda_decidir (respondida_via = o canal); desfazer → agenda_desfazer de cada ação; andamento → agenda_registrar_dia (via conversa), a porta (começou: em andamento com o início da releitura; parou: aguardando, com o motivo, e sai da agenda o que não começou, ação cancelar; Fase 3: concluiu/entregou → os_registrar_marco via dono, e a recusa dela é a exceção P0096). Qualquer recusa = exceção P0097 com a frase dela (o lote inteiro volta). Devolve a frase do que foi feito. Só pelo agenda_rascunho_gravar; só service_role.';

create or replace function public.agenda_rascunho_gravar(p_autor uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor   uuid := public._autor_da_agenda(p_autor);
  v_exp     int;
  v_exp_dia date;
  v_ids     uuid[];
  v_oss_mat uuid[];
  v_r       public.agenda_rascunho%rowtype;
  v_x       uuid;
  v_n       int := 0;
  v_item    text;
  v_estado  text;
  v_msg     text;
  v_linhas  text[] := '{}';
  v_g       record;
  v_p       jsonb;
  v_nome    int;
  -- FASE 2: a hora do *grava* (now(); a bancada fixa com set_config('agenda.agora', …, true), como agenda.hoje), a
  -- config, as frases do que a agenda fez com os pedidos e o tipo de cada linha.
  v_agora   timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  cf        public.agenda_config := public._agenda_cfg();
  v_f2      text[] := '{}';
  v_f2_item text;
begin
  perform pg_advisory_xact_lock(hashtext('agenda_rascunho:' || v_autor::text));

  -- O que passou da validade não grava (e fica marcado, mesmo se o resto falhar).
  with e as (
    update public.agenda_rascunho set estado = 'expirado'
     where autor = v_autor and estado = 'aberto' and expira_em <= now()
    returning criado_em)
  select count(*), max((e.criado_em at time zone 'America/Sao_Paulo')::date) into v_exp, v_exp_dia from e;

  -- FASE 2: primeiro os fatos (Fase 1), depois o andamento, marcar, publicar/decidir e desfazer — cada grupo na ordem em
  -- que o dono falou.
  select coalesce(array_agg(r.id order by case r.tipo when 'andamento' then 1 when 'marcar' then 2 when 'aplicar' then 3
                                                      when 'desfazer' then 4 else 0 end,
                                          (r.dados ->> 'ordem')::int, r.criado_em, r.id), '{}'),
         coalesce(array_agg(distinct r.service_order_id) filter (where r.tipo = 'material'), '{}')
    into v_ids, v_oss_mat
    from public.agenda_rascunho r
   where r.autor = v_autor and r.estado = 'aberto';

  if cardinality(v_ids) = 0 then
    return jsonb_build_object('ok', true, 'gravados', 0, 'expirados', v_exp,
      'texto', case when v_exp > 0 then format('A releitura de %s expirou; me diga de novo o que mudou.', public._dia_curto(v_exp_dia))
                    else 'Não tenho nada esperando para gravar.' end);
  end if;

  -- FASE 2: com a agenda automática fora de 'ligado', o pedido à agenda não grava — e o lote é tudo ou nada.
  -- FASE 3: menos concluir e entregar, que valem em todos os modos (a conclusão pela porta é a correção do D7).
  if cf.modo_proposta <> 'ligado'
     and exists (select 1 from public.agenda_rascunho r where r.id = any (v_ids) and r.tipo in ('marcar', 'aplicar', 'desfazer', 'andamento')
                    and not (r.tipo = 'andamento' and r.dados ->> 'evento' in ('concluiu', 'entregou'))) then
    return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'motivo', 'em_teste',
      'texto', 'Não gravei nada: a agenda automática ainda está em teste e o que você pediu mexe na agenda. Mande *descarta* e me diga de novo o resto.');
  end if;

  -- Tudo ou nada: um item que não passa desfaz o lote inteiro (as linhas continuam abertas para corrigir).
  begin
    foreach v_x in array v_oss_mat loop
      perform public.os_material_sincronizar(v_x, p_hoje);   -- as linhas espelho existem antes do fato
    end loop;

    -- O padrão novo de uma pessoa troca, UMA vez antes de entrar o lote, só o que ele realmente troca:
    --   · "vem" (seg a qui): as linhas de padrão dela (do histórico e do dono) que caem em algum desses dias; os
    --     outros dias da semana continuam como estavam;
    --   · "só de manhã", "só à tarde", "não vem" (terça): o "vem" fica; a linha indisponível do turno entra por cima
    --     (a capacidade põe o "não vem neste turno" acima do padrão "vem"). Só sai a restrição que o dono já tinha
    --     dito para os mesmos dias ("só à tarde às terças" e depois "só de manhã às terças").
    update public.agenda_disponibilidade a
       set substituida_em = now()
      from (select (r.dados ->> 'payee_id')::uuid as payee, r.dados ->> 'situacao' as situacao,
                   array(select jsonb_array_elements_text(r.dados -> 'dias_semana')::smallint) as dias
              from public.agenda_rascunho r
             where r.id = any (v_ids) and r.tipo = 'disponibilidade' and (r.dados ->> 'padrao')::boolean) n
     where a.substituida_em is null and a.dias_semana is not null and a.payee_id = n.payee
       and ((n.situacao = 'disponivel' and a.origem in ('historico', 'dono') and a.dias_semana && n.dias)
            or (n.situacao = 'indisponivel' and a.origem = 'dono' and a.situacao = 'indisponivel'
                and a.dias_semana <@ n.dias));

    foreach v_x in array v_ids loop
      select * into v_r from public.agenda_rascunho where id = v_x for update;
      v_item := v_r.texto;
      case v_r.tipo
        when 'planejar' then
          perform public._agenda_aplicar_planejar(v_autor, v_r.service_order_id, v_r.dados, v_r.trecho, p_hoje);
        when 'material' then
          perform public._agenda_aplicar_material(v_autor, v_r.service_order_id, v_r.dados, v_r.trecho, p_hoje);
        when 'disponibilidade' then
          perform public._agenda_aplicar_disponibilidade(v_autor, v_r.dados, v_r.trecho, p_hoje);
        else
          -- FASE 2: o pedido à agenda (marcar, aplicar/decidir, desfazer, andamento) pelas funções do motor.
          v_f2_item := public._agenda_aplicar_pedido(v_autor, v_r.tipo, v_r.service_order_id, v_r.dados, v_r.trecho, v_r.canal,
                                                     p_hoje, v_agora);
          if nullif(btrim(coalesce(v_f2_item, '')), '') is not null then
            v_f2 := v_f2 || v_f2_item;
          end if;
      end case;
      update public.agenda_rascunho set estado = 'gravado', gravado_em = now() where id = v_x;
      v_n := v_n + 1;
    end loop;

    foreach v_x in array v_oss_mat loop
      perform public.os_material_sincronizar(v_x, p_hoje);
    end loop;
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    -- FASE 3: a porta recusou concluir ou entregar (o período fechado no financeiro): a frase dela.
    if v_estado = 'P0096' then
      return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
        'texto', 'Não gravei nada. ' || btrim(v_msg));
    end if;
    -- FASE 2: a agenda recusou um pedido (a proposta ficou velha, a decisão mudou, não coube, já começou…).
    if v_estado = 'P0097' then
      return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
        'texto', format('Não gravei nada. A agenda mudou desde a releitura: %s. Me peça de novo.', rtrim(btrim(v_msg), '.')));
    end if;
    return jsonb_build_object('ok', false, 'gravados', 0, 'expirados', v_exp, 'erro', v_msg, 'sqlstate', v_estado,
      'texto', format('Não gravei nada: %s (%s). Corrija o que estiver errado, ou mande *descarta*, e depois *grava* de novo.',
                      case when v_estado = 'P0001' then v_msg else 'o banco recusou um item' end,
                      coalesce(v_item, 'o lote')));
  end;

  -- "Gravado. Agora:" — uma linha por OS (o estado da prontidão) e por pessoa, na ordem em que o dono falou.
  for v_g in
    select r.dados ->> 'grupo' as grupo, min((r.dados ->> 'ordem')::int) as ordem,
           (array_agg(r.service_order_id order by (r.dados ->> 'ordem')::int))[1] as os,
           (array_agg(r.dados order by (r.dados ->> 'ordem')::int))[1] as d,
           string_agg(r.dados ->> 'frase', '; ' order by (r.dados ->> 'ordem')::int) as frases
      from public.agenda_rascunho r
     where r.id = any (v_ids) and r.tipo in ('planejar', 'material', 'disponibilidade')   -- FASE 2: os pedidos vêm em v_f2
     group by r.dados ->> 'grupo'
     order by 2
  loop
    if v_g.os is not null then
      v_p := public.os_prontidao(v_g.os, p_hoje);
      select count(*) into v_nome from public.os_carteira(p_hoje) k where k.cliente_curto = v_p ->> 'cliente_curto';
      v_linhas := v_linhas || ('• ' || public._agenda_rotulo(jsonb_build_object(
                                 'curto', v_p ->> 'cliente_curto', 'numero', v_p ->> 'numero',
                                 'eh_orc', (v_p ->> 'eh_orcamento')::boolean, 'n_nome', v_nome))
                               || ': ' || (v_p ->> 'estado_texto') || '.');
    else
      v_linhas := v_linhas || ('• ' || (v_g.d ->> 'rotulo_grupo') || ': ' || v_g.frases || '.');
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'gravados', v_n, 'expirados', v_exp,
    'texto', 'Gravado. Agora:' || E'\n' || array_to_string(v_linhas || array(select '• ' || x from unnest(v_f2) x), E'\n')
             || case when v_exp > 0 then E'\n' || format('(A releitura de %s tinha expirado e não foi gravada.)', public._dia_curto(v_exp_dia))
                     else '' end);
end;
$function$;

comment on function public.agenda_rascunho_gravar(uuid, date) is
  'Agenda de Produção (Fase 1, P5; Fase 2, P4): o *grava* do dono — numa transação, tudo ou nada: marca expirado o que passou da validade; sincroniza o material das OS do lote; troca UMA vez, das pessoas com padrão novo, só os padrões que o "vem" cobre; aplica primeiro os fatos (_agenda_aplicar_planejar/_material/_disponibilidade), depois os pedidos à agenda da Fase 2 na ordem andamento, marcar, aplicar/decidir e desfazer (_agenda_aplicar_pedido: agenda_registrar_dia, a porta, agenda_marcar_os, agenda_aplicar, agenda_decidir, agenda_desfazer, com p_agora = a hora do *grava*); sincroniza de novo. Com modo_proposta fora de ligado, o lote com pedido à agenda não grava (Fase 3: menos concluir e entregar, que gravam em todos os modos; a recusa da porta = "Não gravei nada. Não concluí: …" e o lote volta). Devolve {ok, gravados, expirados, texto "Gravado. Agora:" + uma linha por OS (estado da prontidão), por pessoa e por pedido (a frase da agenda)}; item que não passa: {ok:false, texto "Não gravei nada: …" ou "Não gravei nada. A agenda mudou desde a releitura: …. Me peça de novo.", erro} e nada muda. Chamada só pelo comando sem IA "grava", nunca por ferramenta do modelo.';

-- ── 6. O desfazer acha a OS que saiu da carteira ─────────────────────────────────────────────────────────
-- Corpo de 20261025100200 copiado; a mudança está marcada "-- FASE 3:".

create or replace function public.agenda_acao_desfazivel(p_ref text, p_hoje date default public._hoje_brt(),
                                                         p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_ref  text := btrim(coalesce(p_ref, ''));
  v_norm text := public._agenda_normal(p_ref);
  v_ids  uuid[];
  v_ro   jsonb;
  v_dia  date;
  v_prop uuid;
begin
  if v_norm in ('semana', 'a semana', 'da semana', 'semana toda', 'a semana toda') then
    select a.proposta_id into v_prop from public.agenda_acoes a
     where a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora and a.tipo = 'publicar'
     order by a.criada_em desc, a.id desc limit 1;
    if v_prop is null then
      return jsonb_build_object('status', 'nenhuma', 'texto', 'Não tenho publicação da semana para desfazer agora.');
    end if;
    v_ids := array(select a.id from public.agenda_acoes a
                    where a.proposta_id = v_prop and a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora
                    order by a.criada_em, a.id);
    return jsonb_build_object('status', 'ok', 'acao_id', v_ids[1], 'acao_ids', to_jsonb(v_ids),
                              'texto', 'Desfaço a publicação da semana.');
  end if;
  if v_ref <> '' and v_norm not in ('a ultima', 'ultima', 'o ultimo', 'ultimo', 'isso', 'tudo') then
    v_ro := public.agenda_resolver_os(v_ref, p_hoje);
    -- FASE 3: a OS concluída ou entregue sai da carteira, mas a conclusão e a entrega da agenda ficam desfazíveis:
    -- "desfaz OS-00074" logo depois de "concluiu Lenine" acha a OS pelo id que o resolvedor devolve fora da carteira. Sem
    -- mudança desfazível dela, a resposta é a de antes (o "desfaz" pode ser de outra ferramenta).
    if v_ro ->> 'status' <> 'ok'
       and not (v_ro ->> 'status' = 'fora_da_carteira' and v_ro ->> 'id' is not null
                and exists (select 1 from public.agenda_acoes a
                             where a.service_order_id = (v_ro ->> 'id')::uuid and a.executada and a.desfeita_em is null
                               and a.desfazivel_ate >= p_agora and a.tipo <> 'desfazer')) then
      return jsonb_build_object('status', coalesce(v_ro ->> 'status', 'nao_achei'), 'texto', v_ro ->> 'texto', 'opcoes', v_ro -> 'opcoes');
    end if;
    v_ids := array(select a.id from public.agenda_acoes a
                    where a.service_order_id = (v_ro ->> 'id')::uuid and a.executada and a.desfeita_em is null
                      and a.desfazivel_ate >= p_agora and a.tipo <> 'desfazer'
                    order by a.criada_em desc, a.id desc limit 1);
    if cardinality(v_ids) = 0 then
      return jsonb_build_object('status', 'nenhuma',
               'texto', format('Não tenho mudança minha no %s para desfazer agora.', v_ro ->> 'cliente_curto'));
    end if;
    return jsonb_build_object('status', 'ok', 'acao_id', v_ids[1], 'acao_ids', to_jsonb(v_ids),
                              'texto', (select a.texto from public.agenda_acoes a where a.id = v_ids[1]));
  end if;
  -- sem nome: a última, se pediu; senão as contadas no último fechamento/acorde; senão todas as desfazíveis
  if v_norm in ('a ultima', 'ultima', 'o ultimo', 'ultimo') then
    v_ids := array(select a.id from public.agenda_acoes a
                    where a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora and a.tipo <> 'desfazer'
                    order by a.criada_em desc, a.id desc limit 1);
  else
    select max((a.contada_em at time zone 'America/Sao_Paulo')::date) into v_dia
      from public.agenda_acoes a
     where a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora and a.tipo <> 'desfazer' and a.contada_em is not null;
    v_ids := array(select a.id from public.agenda_acoes a
                    where a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora and a.tipo <> 'desfazer'
                      and (v_dia is null or (a.contada_em at time zone 'America/Sao_Paulo')::date = v_dia)
                    order by a.criada_em, a.id);
  end if;
  if cardinality(v_ids) = 0 then
    return jsonb_build_object('status', 'nenhuma', 'texto', 'Não tenho mudança minha para desfazer agora.');
  end if;
  if cardinality(v_ids) = 1 then
    return jsonb_build_object('status', 'ok', 'acao_id', v_ids[1], 'acao_ids', to_jsonb(v_ids),
                              'texto', (select a.texto from public.agenda_acoes a where a.id = v_ids[1]));
  end if;
  return jsonb_build_object('status', 'ambiguo', 'acao_ids', to_jsonb(v_ids),
    'texto', format('Qual? %s Diga *desfaz* e o nome.',
                    (select string_agg(coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) || ' (' || rtrim(
                              regexp_replace(a.texto, '^[^:]*: ', ''), '.') || ')', ' ou ' order by a.criada_em, a.id)
                       from public.agenda_acoes a
                       left join public.service_orders so on so.id = a.service_order_id
                       left join public.clients cl on cl.id = so.client_id
                      where a.id = any (v_ids)) || '?'));
end;
$function$;

comment on function public.agenda_acao_desfazivel(text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): resolve o que o dono quer desfazer — o nome ou o número da OS (agenda_resolver_os: a última ação desfazível dela), "semana" (a última publicação: todas as ações dela em acao_ids), "a última", ou nada (a única desfazível contada no último fechamento ou acorde; senão a única desfazível). Fase 3: a OS fora da carteira (concluída, entregue) com mudança desfazível da agenda também vale. Mais de uma = {status ambiguo, texto "Qual? Nelson (…) ou Vanderlei (…)? Diga *desfaz* e o nome."}; nenhuma = "Não tenho mudança minha para desfazer agora.". {status ok|ambiguo|nenhuma|nao_achei, acao_id, acao_ids, texto}.';

-- ── 7. As palavras *concluiu* e *entreguei* (executam direto: é a ordem exata do dono) ───────────────────────

create or replace function public.agenda_concluir_dito(p_autor uuid, p_alvo text default null, p_canal text default 'whatsapp',
                                                       p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  v_alvo   text := nullif(btrim(coalesce(p_alvo, '')), '');
  v_ro     jsonb;
  v_os     uuid;
  v_ids    uuid[];
  v_status text;
  v_rotulo text;
  v_r      jsonb;
  v_saida  timestamptz;
  v_quando text;
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_concluir_dito: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;

  if v_alvo is null then
    -- Sem alvo: a OS do plano de hoje, se for uma só (na ordem do dia: a que começa primeiro, depois o número).
    select coalesce(array_agg(x.os order by x.ini, x.numero), '{}') into v_ids
      from (select a.service_order_id as os, min(lower(a.periodo)) as ini, min(so.service_order_number) as numero
              from public.agenda_alocacoes a
              join public.service_orders so on so.id = a.service_order_id
             where a.dia = p_hoje and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
               and so.status not in ('draft', 'completed', 'invoiced', 'cancelled')
             group by a.service_order_id) x;
    if cardinality(v_ids) = 0 then
      return jsonb_build_object('ok', false, 'mudou', false, 'status', 'nenhuma',
        'texto', 'Hoje não tem serviço no plano para concluir. Diga *concluiu* e o nome do cliente.');
    end if;
    if cardinality(v_ids) > 1 then
      return jsonb_build_object('ok', false, 'mudou', false, 'status', 'ambiguo',
        'opcoes', (select jsonb_agg(public._agenda_rotulo_da_os(x) order by o) from unnest(v_ids) with ordinality u(x, o)),
        'texto', format('Qual? %s? Diga *concluiu %s*.',
                        (select string_agg(public._agenda_rotulo_da_os(x), ' ou ' order by o)
                           from unnest(v_ids) with ordinality u(x, o)),
                        (select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number)
                           from public.service_orders so left join public.clients cl on cl.id = so.client_id
                          where so.id = v_ids[1])));
    end if;
    v_os := v_ids[1];
  else
    v_ro := public.agenda_resolver_os(v_alvo, p_hoje, false);
    if v_ro ->> 'status' = 'fora_da_carteira' and v_ro ->> 'situacao' in ('completed', 'invoiced') then
      return jsonb_build_object('ok', true, 'mudou', false, 'status', 'ja_concluida',
        'texto', format('%s (%s) já está %s.', v_ro ->> 'cliente_curto', v_ro ->> 'numero',
                        public._agenda_status_texto(v_ro ->> 'situacao')));
    end if;
    if v_ro ->> 'status' <> 'ok' then
      -- nao_achei: o turno segue ao modelo ("concluiu a instalação" não é de OS nenhuma)
      return jsonb_build_object('ok', false, 'mudou', false, 'status', v_ro ->> 'status', 'texto', v_ro ->> 'texto',
                                'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
    end if;
    v_os := (v_ro ->> 'id')::uuid;
  end if;

  v_rotulo := public._agenda_rotulo_da_os(v_os);
  select so.status into v_status from public.service_orders so where so.id = v_os;
  if v_status = 'draft' then
    return jsonb_build_object('ok', false, 'mudou', false, 'status', 'orcamento',
      'texto', format('%s ainda é orçamento: converta em OS antes de concluir.', v_rotulo));
  end if;
  -- D11: concluir exige o levantamento respondido (a frase do formulário).
  if cardinality(public._os_levantamentos_pendentes(v_os)) > 0 then
    return jsonb_build_object('ok', false, 'mudou', false, 'status', 'levantamento',
                              'texto', public._os_texto_do_levantamento(public._os_levantamentos_pendentes(v_os)));
  end if;

  v_r := public.os_registrar_marco(v_os, 'conclusao', 'dono', null, v_autor,
                                   left('concluiu' || coalesce(' ' || v_alvo, ''), 200), p_hoje, p_agora);
  if not coalesce((v_r ->> 'ok')::boolean, false) or not coalesce((v_r ->> 'mudou')::boolean, false) then
    return v_r || jsonb_build_object('status', case when coalesce((v_r ->> 'ok')::boolean, false) then 'ja_concluida'
                                                    else 'recusada' end);
  end if;
  v_saida := (v_r ->> 'check_out_at')::timestamptz;
  v_quando := case when (v_saida at time zone 'America/Sao_Paulo')::date = p_hoje
                   then format('hoje (%s, %s)', public._dia_curto(p_hoje), to_char(v_saida at time zone 'America/Sao_Paulo', 'HH24:MI'))
                   else format('(saída %s, %s)', public._dia_curto((v_saida at time zone 'America/Sao_Paulo')::date),
                               to_char(v_saida at time zone 'America/Sao_Paulo', 'HH24:MI')) end;
  return v_r || jsonb_build_object('status', 'ok',
    'texto', left(format('Concluí o %s %s. %s *desfaz %s* volta como estava.', v_rotulo, v_quando,
                         public._agenda_cobrancas_da_palavra(v_r ->> 'cobrancas_texto'),
                         (select so.service_order_number from public.service_orders so where so.id = v_os)), 600));
end;
$function$;

comment on function public.agenda_concluir_dito(uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 3, P3): a palavra *concluiu [<alvo>]* — executa direto (é a ordem exata do dono) pela porta (os_registrar_marco conclusao, via dono: a saída e as cobranças da condição na mesma transação; desfazível). Sem alvo: a OS do plano de hoje se for uma só; nenhuma = "Hoje não tem serviço no plano para concluir…"; mais de uma = "Qual? Vanderlei (OS-00069) ou Flávio (OS-00104)? Diga *concluiu Vanderlei*.". Com alvo: agenda_resolver_os (ambíguo = a pergunta; nao_achei = o turno segue ao modelo; já concluída = "Lenine (OS-00074) já está concluída."). Orçamento não conclui; levantamento pendente (D11) = a frase do formulário. Texto: "Concluí o Lenine (OS-00074) hoje (qui 29/10, 16:30). Saíram as cobranças da condição: … *desfaz OS-00074* volta como estava."; recusa da porta = o texto dela. Vale em todos os modos. Admin pelo _autor_da_agenda.';

create or replace function public.agenda_entregar_dito(p_autor uuid, p_alvo text, p_canal text default 'whatsapp',
                                                       p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor  uuid := public._autor_da_agenda(p_autor);
  v_alvo   text := nullif(btrim(coalesce(p_alvo, '')), '');
  v_ro     jsonb;
  v_os     uuid;
  v_status text;
  v_rotulo text;
  v_r      jsonb;
  v_ent    timestamptz;
begin
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'agenda_entregar_dito: canal "%" inválido (whatsapp ou painel)', p_canal using errcode = '22023';
  end if;
  if v_alvo is null then
    return jsonb_build_object('ok', false, 'mudou', false, 'status', 'sem_alvo',
                              'texto', 'Diga qual: *entreguei* e o nome do cliente.');
  end if;
  v_ro := public._agenda_os_da_entrega(v_alvo, p_hoje);
  if v_ro ->> 'status' <> 'ok' then
    return jsonb_build_object('ok', false, 'mudou', false, 'status', v_ro ->> 'status', 'texto', v_ro ->> 'texto',
                              'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
  end if;
  v_os := (v_ro ->> 'id')::uuid;
  v_rotulo := public._agenda_rotulo_da_os(v_os);
  select so.status into v_status from public.service_orders so where so.id = v_os;
  if v_status = 'draft' then
    return jsonb_build_object('ok', false, 'mudou', false, 'status', 'orcamento',
      'texto', format('%s ainda é orçamento: converta em OS antes de concluir.', v_rotulo));
  end if;
  -- D11: a entrega de uma OS ainda aberta conclui junto, e concluir exige o levantamento respondido.
  if v_status not in ('completed', 'invoiced') and cardinality(public._os_levantamentos_pendentes(v_os)) > 0 then
    return jsonb_build_object('ok', false, 'mudou', false, 'status', 'levantamento',
                              'texto', public._os_texto_do_levantamento(public._os_levantamentos_pendentes(v_os)));
  end if;

  v_r := public.os_registrar_marco(v_os, 'entrega', 'dono', null, v_autor, left('entreguei ' || v_alvo, 200), p_hoje, p_agora);
  if not coalesce((v_r ->> 'ok')::boolean, false) or not coalesce((v_r ->> 'mudou')::boolean, false) then
    return v_r || jsonb_build_object('status', case when coalesce((v_r ->> 'ok')::boolean, false) then 'ja_entregue'
                                                    else 'recusada' end);
  end if;
  if coalesce((v_r ->> 'concluiu')::boolean, false) then
    v_ent := (v_r ->> 'delivered_at')::timestamptz;
    return v_r || jsonb_build_object('status', 'ok',
      'texto', left(format('%s: ainda estava %s; concluí e marquei a entrega (%s às %s). %s *desfaz %s* volta como estava.',
                           v_rotulo, public._agenda_status_texto(v_r #>> '{conclusao,de}'),
                           public._dia_curto((v_ent at time zone 'America/Sao_Paulo')::date),
                           to_char(v_ent at time zone 'America/Sao_Paulo', 'HH24:MI'),
                           public._agenda_cobrancas_da_palavra(v_r #>> '{conclusao,cobrancas_texto}'),
                           (select so.service_order_number from public.service_orders so where so.id = v_os)), 600));
  end if;
  return v_r || jsonb_build_object('status', 'ok');
end;
$function$;

comment on function public.agenda_entregar_dito(uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 3, P3): a palavra *entreguei <alvo>* — executa direto pela porta (os_registrar_marco entrega, via dono; desfazível). A OS por _agenda_os_da_entrega (o nome procura antes a concluída e não entregue; ambíguo = a pergunta; nao_achei = o turno segue ao modelo). Ainda aberta: conclui e entrega na mesma transação ("Lenine (OS-00074): ainda estava agendada; concluí e marquei a entrega (qui 29/10 às 16:30). Saíram as cobranças da condição: … *desfaz OS-00074* volta como estava."); já concluída: "Entregue: o Lenine (OS-00074), sex 30/10 às 09:40."; já entregue: "O Lenine (OS-00074) já foi entregue em …" (mudou false). Orçamento não; levantamento pendente (D11) numa OS ainda aberta = a frase do formulário. Admin pelo _autor_da_agenda.';

-- ── Portas ──────────────────────────────────────────────────────────────────────────────────────────────
-- As palavras do dono: o painel (authenticated, com o administrador conferido dentro) e o WhatsApp (service_role). Nunca anon.
revoke all on function public.agenda_concluir_dito(uuid, text, text, date, timestamptz),
  public.agenda_entregar_dito(uuid, text, text, date, timestamptz) from public, anon;
grant execute on function public.agenda_concluir_dito(uuid, text, text, date, timestamptz),
  public.agenda_entregar_dito(uuid, text, text, date, timestamptz) to authenticated, service_role;
-- As recriadas mantêm as portas de antes (create or replace não muda a ACL); repetidas para a migration valer sozinha.
revoke all on function public.agenda_rascunho_andamento(uuid, text, text, text, text, text[], text, text, date, timestamptz),
  public.agenda_rascunho_gravar(uuid, date), public.agenda_acao_desfazivel(text, date, timestamptz) from public, anon;
grant execute on function public.agenda_rascunho_andamento(uuid, text, text, text, text, text[], text, text, date, timestamptz),
  public.agenda_rascunho_gravar(uuid, date), public.agenda_acao_desfazivel(text, date, timestamptz)
  to authenticated, service_role;
-- As internas: só service_role (as funções security definer acima as chamam como dono).
revoke all on function public._agenda_aplicar_pedido(uuid, text, uuid, jsonb, text, text, date, timestamptz),
  public._agenda_rascunho_marco(uuid, text, text, text, text, text, date), public._agenda_os_da_entrega(text, date),
  public._agenda_cobrancas_da_releitura(uuid, date), public._agenda_cobrancas_da_palavra(text),
  public._os_levantamentos_pendentes(uuid), public._os_texto_do_levantamento(text[])
  from public, anon, authenticated;
grant execute on function public._agenda_aplicar_pedido(uuid, text, uuid, jsonb, text, text, date, timestamptz),
  public._agenda_rascunho_marco(uuid, text, text, text, text, text, date), public._agenda_os_da_entrega(text, date),
  public._agenda_cobrancas_da_releitura(uuid, date), public._agenda_cobrancas_da_palavra(text),
  public._os_levantamentos_pendentes(uuid), public._os_texto_do_levantamento(text[])
  to service_role;

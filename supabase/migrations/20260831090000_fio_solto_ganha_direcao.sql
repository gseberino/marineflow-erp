-- ─────────────────────────────────────────────────────────────────────────────
-- O fio solto passa a saber SE DEPENDE DE NÓS.
--
-- POR QUE: `entity_open_loops` nasceu para responder "o que está em aberto com esta
-- pessoa" e nunca distinguiu o que precisa de uma ação NOSSA do que está parado
-- esperando a contraparte. Medido em 30/08/2026: dos 68 fios abertos, a esmagadora
-- maioria é obrigação da própria HBR — "Enviar nota fiscal para Charline", "Gerar
-- orçamento para Vanderlei", "Ter o barco pronto para retirada".
--
-- Sem esse campo o dado convida ao engano: 4 dos fios de fornecedor são `payable`
-- (contas que a HBR DEVE, uma de R$ 37 mil). Qualquer recurso que "cobrasse a
-- contraparte" desses fios mandaria mensagem para quem a HBR precisa pagar.
--
-- ═══ O CRITÉRIO ═══
-- `direction` responde "PARA ESTE FIO ANDAR, quem precisa agir?", e não "de quem é a
-- obrigação". A diferença aparece no título vencido: a obrigação de pagar é do cliente,
-- mas o fio só destrava se ALGUÉM DAQUI cobrar — então é 'ours'. Já um orçamento
-- enviado e aguardando resposta é 'theirs': o próximo passo não está com a gente.
--   ours   → parado esperando uma ação nossa (executar, pagar, cobrar, responder).
--   theirs → a bola está com a contraparte; nada a fazer além de aguardar.
--
-- ═══ O BACKFILL ═══
-- Nada é adivinhado por texto. Os fios de ERP vêm do `kind`, que já carrega a natureza
-- do fato. Os de conversa vêm do DETECTOR original, preservado em
-- `agenda_suggestions.open_loop_id` — e aqui está o achado que tornou isto preciso: o
-- detector já classifica em 4 tipos, incluindo `third_party_deadline` ("o terceiro deu
-- um prazo"), mas o agenda-inbox-detector colapsa os 4 em 2 kinds na hora de gravar
-- (`p_kind: detector === 'client_request' ? 'request' : 'promise'`). A direção existia e
-- era jogada fora. Recuperamos 48 dos 55 fios de conversa por esse caminho.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.entity_open_loops
  add column if not exists direction text not null default 'ours';

alter table public.entity_open_loops
  drop constraint if exists entity_open_loops_direction_check;

alter table public.entity_open_loops
  add constraint entity_open_loops_direction_check
  check (direction in ('ours', 'theirs'));

comment on column public.entity_open_loops.direction is
  'Para o fio ANDAR, quem precisa agir: ours = ação nossa (executar/pagar/cobrar/responder); theirs = esperando a contraparte. Não é "de quem é a obrigação" — título vencido é ours, porque cobrar é ação nossa.';

-- ── Fios do ERP: o `kind` já diz de que fato se trata ────────────────────────
update public.entity_open_loops
set direction = case kind
    when 'service_order'  then 'ours'    -- a OS está aqui, esperando execução
    when 'payable'        then 'ours'    -- nós devemos pagar
    when 'receivable'     then 'ours'    -- o cliente deve, mas destravar exige COBRAR
    when 'quote'          then 'theirs'  -- orçamento já enviado; o cliente é que decide
    when 'purchase_order' then 'theirs'  -- o fornecedor é que tem de entregar
    when 'delivery'       then 'theirs'  -- material a receber: depende do fornecedor
    else 'ours'
  end
where source = 'erp';

-- ── Fios de conversa: recupera o detector original pela sugestão que os criou ──
update public.entity_open_loops l
set direction = case s.detector
    when 'third_party_deadline' then 'theirs'  -- foi o terceiro que deu o prazo
    else 'ours'                                 -- client_request, promise, followup
  end
from public.agenda_suggestions s
where s.open_loop_id = l.id
  and l.source = 'conversation';

-- Os poucos fios de conversa sem sugestão vinculada seguem o `kind`: `request` é sempre
-- um pedido que chegou à HBR, então é nosso. (O default da coluna já cobre, mas deixar
-- explícito documenta a regra para quem ler depois.)
update public.entity_open_loops
set direction = 'ours'
where source = 'conversation' and kind = 'request';

-- ── Índice da tela "Depende de você" ─────────────────────────────────────────
-- A consulta é sempre "fios abertos que dependem de nós, mais urgentes primeiro".
create index if not exists entity_open_loops_dependem_de_nos_idx
  on public.entity_open_loops (direction, status, due_at nulls last, opened_at)
  where status = 'open';

-- ── A origem: o fio de conversa passa a nascer com a direção certa ───────────
-- `record_conversation_loop` ganha p_direction com DEFAULT, para as chamadas existentes
-- continuarem válidas. No DO UPDATE a direção NÃO é sobrescrita: a segunda menção do
-- mesmo assunto só incrementa o contador, e uma correção manual do dono precisa
-- sobreviver ao próximo ciclo do detector.
CREATE OR REPLACE FUNCTION public.record_conversation_loop(
  p_entity_type text,
  p_entity_id uuid,
  p_loop_key text,
  p_kind text,
  p_title text,
  p_detail text DEFAULT NULL::text,
  p_service_order_id uuid DEFAULT NULL::uuid,
  p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_priority text DEFAULT 'normal'::text,
  p_evidence text DEFAULT NULL::text,
  p_evidence_at timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_source_message_id uuid DEFAULT NULL::uuid,
  p_direction text DEFAULT 'ours'::text
)
 RETURNS TABLE(loop_id uuid, criado boolean)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id uuid;
  v_new boolean;
BEGIN
  INSERT INTO entity_open_loops (
    entity_type, entity_id, loop_key, source, kind, title, detail,
    service_order_id, due_at, priority, evidence, evidence_at, source_message_id,
    direction, last_seen_at
  )
  VALUES (
    p_entity_type, p_entity_id, p_loop_key, 'conversation', p_kind, p_title, p_detail,
    p_service_order_id, p_due_at, coalesce(p_priority, 'normal'),
    p_evidence, p_evidence_at, p_source_message_id,
    case when p_direction in ('ours','theirs') then p_direction else 'ours' end,
    now()
  )
  ON CONFLICT (entity_type, entity_id, loop_key) WHERE status = 'open'
  DO UPDATE SET
    mentions          = entity_open_loops.mentions + 1,
    last_seen_at      = now(),
    evidence          = coalesce(EXCLUDED.evidence, entity_open_loops.evidence),
    evidence_at       = coalesce(EXCLUDED.evidence_at, entity_open_loops.evidence_at),
    source_message_id = coalesce(EXCLUDED.source_message_id, entity_open_loops.source_message_id),
    due_at            = coalesce(EXCLUDED.due_at, entity_open_loops.due_at),
    service_order_id  = coalesce(EXCLUDED.service_order_id, entity_open_loops.service_order_id),
    updated_at        = now()
  RETURNING id, (xmax = 0) INTO v_id, v_new;

  RETURN QUERY SELECT v_id, v_new;
END;
$function$;

REVOKE ALL ON FUNCTION public.record_conversation_loop(
  text, uuid, text, text, text, text, uuid, timestamptz, text, text, timestamptz, uuid, text
) FROM anon;

-- ── A consulta que a tela "Depende de você" precisa ──────────────────────────
-- Não existia listagem global: `get_entity_open_loops` é sempre por entidade, e o painel
-- só era montado na tela do cliente. Sem isto, os fios que dependem da HBR não têm
-- lugar nenhum onde serem vistos juntos.
--
-- O join com clients/suppliers é feito aqui, e não no PostgREST, porque `entity_id` não
-- tem foreign key (a mesma coluna aponta para duas tabelas) — o embed não funcionaria e
-- a tela ficaria com a coluna de nome vazia.
CREATE OR REPLACE FUNCTION public.get_open_loops(
  p_direction text DEFAULT 'ours',
  p_limit integer DEFAULT 100
)
RETURNS TABLE (
  id uuid, entity_type text, entity_id uuid, entity_name text,
  kind text, source text, direction text, title text, detail text,
  due_at timestamptz, priority text, service_order_id uuid,
  service_order_number text, mentions integer, evidence text,
  opened_at timestamptz, last_seen_at timestamptz, atrasado boolean
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $function$
  SELECT
    l.id, l.entity_type, l.entity_id,
    coalesce(c.name, s.name, '—') AS entity_name,
    l.kind, l.source, l.direction, l.title, l.detail,
    l.due_at, l.priority, l.service_order_id,
    so.service_order_number, l.mentions, l.evidence,
    l.opened_at, l.last_seen_at,
    (l.due_at IS NOT NULL AND l.due_at < now()) AS atrasado
  FROM entity_open_loops l
  LEFT JOIN clients   c  ON l.entity_type = 'client'   AND c.id = l.entity_id
  LEFT JOIN suppliers s  ON l.entity_type = 'supplier' AND s.id = l.entity_id
  LEFT JOIN service_orders so ON so.id = l.service_order_id
  WHERE l.status = 'open'
    AND (p_direction IS NULL OR l.direction = p_direction)
  -- Mesma ordenação da fila por entidade, para tela e agente enxergarem o mesmo:
  -- atrasado primeiro, depois urgência, depois prazo, depois o mais antigo.
  ORDER BY
    (l.due_at IS NOT NULL AND l.due_at < now()) DESC,
    CASE l.priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END,
    l.due_at NULLS LAST,
    l.opened_at
  LIMIT greatest(1, least(coalesce(p_limit, 100), 500));
$function$;

-- A view de fatos já vazou para `anon` uma vez (23 fios com valores de títulos, corrigido
-- na 20260727200000). Esta função lista TODOS os fios de TODOS os clientes num lugar só,
-- então fecha para anônimo na mesma migration em que nasce.
REVOKE ALL ON FUNCTION public.get_open_loops(text, integer) FROM anon;

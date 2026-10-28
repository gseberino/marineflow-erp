-- Agrupar ORDENS DE SERVIÇO (e desagrupar). 28/10/2026.
--
-- Caso real: o cliente tem duas ou três OS abertas para a mesma embarcação (OS-00100 + OS-00128 do
-- Giancarlo/Vitória Star, OS-00032 + OS-00033 do KALMAR, OS-00076 + OS-00096 do Rodrigo) e quer UMA OS só.
-- É o mesmo desenho do agrupar ORÇAMENTOS (20261015180000), estendido ao que uma OS já carrega: dinheiro,
-- cobrança, compra, técnico, tarefa e roteiro.
--
-- agrupar_os: N OS (2 a 10) do MESMO cliente e da MESMA embarcação, que AINDA NÃO COMEÇARAM a ser
-- executadas, viram UMA OS nova (OS-<seq>, mesmo document_number_seq do orçamento), numa transação só.
--   · Preços: os de cada linha (snapshot). Condição de pagamento, contato e comissão vêm da OS PRINCIPAL; a
--     comissão é recalculada sobre o total novo. Total da nova = soma das originais, conferido no fim.
--   · Situação da nova = a da principal (Aprovada, Aberta, Agendada...), com a data de atendimento da
--     principal. Escolha simples e previsível: o dono escolhe a principal sabendo que ela "manda"; se as
--     situações ou datas das outras forem diferentes, o retorno traz um aviso para conferir a agenda.
--   · O que é dinheiro/compromisso MUDA de OS (UPDATE da coluna, registrado em os_agrupamento_movidos para
--     o desagrupar devolver): recebíveis (sinal pago e saldo, sem mudar status nem valor), cobranças,
--     boletos/Pix, lançamentos do extrato conciliados, contas a pagar ligadas, pedidos de compra, cotações a
--     fornecedor (e os itens delas, remapeados para as linhas novas), comprovantes, anotações do extrato,
--     sugestões de conciliação pendentes, pendências abertas (entity_open_loops), sugestões de agenda
--     pendentes, tarefas MANUAIS pendentes, missões de acompanhamento vivas (ativas ou aguardando
--     resposta) e os lembretes de cobrança agendados (ligados a recebível).
--   · Saldo sem título: se alguma original já tinha conta a receber e a soma delas não cobre o total novo,
--     a nova ganha UM recebível pendente "Saldo — OS-N" pela diferença, vencendo na conclusão. Sem ele o
--     valor sumia: a conclusão (completion-receivables) não gera nada numa OS que já tem recebível vivo — a
--     mesma classe do OS-00112 (saldo-do-sinal.ts). O desagrupar cancela esse saldo (recusa se já recebeu).
--   · Chegada no barco (check_in_at/check_out_at) registrada numa original NÃO recusa (decisão pendente do
--     dono, 27/10) e NÃO é copiada: copiar daria à nova uma chegada antiga e impediria o registro da chegada
--     real (use-service-orders só grava check_in_at quando está vazio). Fica na original e o retorno avisa.
--   · O que é DOCUMENTO é copiado: serviços, peças (kit remapeado) e passos de roteiro (todos pendentes —
--     COPIADOS com o serviço remapeado, não regenerados: o roteiro pode ter sido ajustado à mão ou pela IA,
--     e regenerar dependeria da função do gerador fora desta transação). Técnicos: a nova recebe a união
--     (sem repetir pessoa); as originais ficam com os seus (histórico).
--   · As originais NÃO são apagadas: ficam canceladas como histórico, link desligado, apontando para a nova
--     (merged_into_id). Os totais, textos e descontos delas NÃO são tocados: numa OS assinada, mexer nesses
--     campos faria o gatilho de re-assinatura da OS dar a assinatura por superada. A assinatura fica na
--     original (o cliente assinou AQUELE documento) e a nova nasce sem assinatura: o retorno avisa.
--   · Recusa, com a mensagem do que fazer: OS em execução (hora apontada, despesa, passo iniciado, foto,
--     baixa de estoque, diária, jornada, ou situação em andamento/concluída/faturada), nota fiscal, fatura,
--     comissão lançada, item de nota de entrada, repasse da taxa do cartão, total desatualizado, deslocamento
--     em mais de uma, cliente/embarcação diferentes, já agrupada.
--   · Tarefas AUTOMÁTICAS (source='automation') ficam onde estão: o motor (task-automations/rules.ts) as dá
--     por resolvidas na original cancelada — R1/R16 olham merged_into_id, R2/R15 a situação — e as recria
--     na nova. Fechá-las aqui seria pior: o motor trata a tarefa que alguém fechou como "o dono já tratou" e
--     não a recriaria na original depois de um desagrupar.
--
-- desagrupar_os: desfaz enquanto a OS agrupada NÃO COMEÇOU a execução (a mesma regra do agrupar,
-- _os_execucao_iniciada) e não ganhou nada novo que prenderia (nota, fatura, comissão, assinatura,
-- recebível/cobrança/compra/lançamento ou anotação do extrato lançados depois de agrupar, pagamento no
-- saldo lançado pelo agrupar). Cada registro movido volta à sua OS, as originais voltam exatamente como
-- estavam (situação, situação do orçamento, link, cancelamento) e a agrupada fica cancelada como histórico
-- (não reabre). O que foi lançado na agrupada DEPOIS mas pertence a um recebível movido acompanha o
-- recebível de volta: o lançamento do extrato conciliado pelo pagamento dele e o lembrete de cobrança
-- dele. O mais que foi acrescentado/editado na agrupada NÃO volta.
--
-- Cada tabela com vínculo a service_orders, e o que o agrupar faz com ela (20261027, seção 3 da spec):
--   MOVE  receivables, collections, bank_charges (não cancelados/falhos), bank_transactions
--         (reconciled_service_order_id), payables.linked_service_order_id, purchase_orders, quote_requests
--         (+ quote_request_items.service_order_part_id/service_order_service_id), comprovantes.destino_os_id
--         (+ comprovantes.so_part_id), anotacoes_do_extrato.os_id, finance_review_queue pendentes,
--         entity_open_loops abertos, agenda_tasks manuais pendentes, agenda_suggestions pendentes,
--         ai_followup_missions ativas/aguardando resposta, whatsapp_scheduled_sends ligados a recebível.
--   CRIA  receivables: o "Saldo — OS-N" (ver acima), guardado em orcamento_agrupamentos.saldo_criado_id.
--   CANCELA  whatsapp_scheduled_sends do link da OS (sem recebível): o link antigo morreu (como orçamento).
--   COPIA  service_order_services, service_order_parts, service_order_steps (pendentes),
--          service_order_technicians (união).
--   RECUSA  issued_fiscal_documents (draft/queued/processing/authorized), invoices, commissions,
--           fiscal_note_items, time_entries, service_order_expenses, service_order_photos,
--           inventory_movements (baixa não estornada), diarias_reembolsos, work_shift_os / work_shifts,
--           service_order_steps fora de "pendente", service_order_services com situação de campo
--           (field_status fora de 'a_fazer' ou started_at/finished_at preenchidos).
--   FICA na original (histórico, não muda o que a nova faz): service_order_signatures, whatsapp_messages,
--        ai_operator_sessions/ai_operator_drafts, arquivos_dropbox/dropbox_envios (a pasta da original),
--        external_quotes.converted_service_order_id, maintenance_plans/maintenance_plan_events,
--        service_cases (só nasce na conclusão), service_surveys, agenda_tasks automáticas (o motor resolve),
--        ai_* .entity_id, inventory_movements de reserva (não existem: reserva é products.reserved_quantity,
--        recalculada no fim).
--
-- Reaproveita da 20261015180000: merged_into_id e as guardas da ORIGEM (agora com a palavra "OS" quando o
-- agrupamento é de OS — o texto de orçamento fica idêntico), o recebível recusado em origem agrupada, o
-- histórico orcamento_agrupamentos/_origens (com tipo = 'os'), _agrupar_orcamentos_juntar e _reais.
-- Auditoria usa ações que já existem ('cancel', 'reopen', 'update').

-- 0) Depende das migrations de agrupar orçamentos ----------------------------------------------------------
do $$
begin
  if to_regclass('public.orcamento_agrupamentos') is null
     or to_regclass('public.orcamento_agrupamento_origens') is null
     or to_regprocedure('public._agrupar_orcamentos_juntar(text[], text[])') is null
     or to_regprocedure('public._agrupar_orcamentos_reais(numeric)') is null
     or to_regprocedure('public.orcamentos_para_agrupar(uuid, uuid, uuid, uuid[])') is null then
    raise exception 'Aplique antes as migrations 20261015180000_agrupar_orcamentos e 20261015181000_agrupar_orcamentos_assistente.';
  end if;
end $$;

-- 1) Histórico: tipo do agrupamento e a situação de antes de cada origem ----------------------------------
alter table public.orcamento_agrupamentos
  add column if not exists tipo text not null default 'orcamento';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'orcamento_agrupamentos_tipo_check') then
    alter table public.orcamento_agrupamentos
      add constraint orcamento_agrupamentos_tipo_check check (tipo in ('orcamento', 'os'));
  end if;
end $$;
comment on column public.orcamento_agrupamentos.tipo is
  '''orcamento'' (agrupar_orcamentos) ou ''os'' (agrupar_os).';

alter table public.orcamento_agrupamento_origens
  add column if not exists status_antes text;
comment on column public.orcamento_agrupamento_origens.status_antes is
  'Situação (service_orders.status) da origem antes do agrupar. Usada pelo desagrupar_os; nula nos agrupamentos de orçamento (voltam a rascunho).';

-- O recebível "Saldo — OS-N" que o agrupar_os lançou na nova (nulo = não lançou). O desagrupar o cancela.
alter table public.orcamento_agrupamentos
  add column if not exists saldo_criado_id uuid;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'orcamento_agrupamentos_saldo_criado_id_fkey') then
    alter table public.orcamento_agrupamentos
      add constraint orcamento_agrupamentos_saldo_criado_id_fkey
      foreign key (saldo_criado_id) references public.receivables(id) on delete set null;
  end if;
end $$;
comment on column public.orcamento_agrupamentos.saldo_criado_id is
  'agrupar_os: recebível "Saldo — OS-N" lançado na OS nova quando as contas a receber das originais não cobriam o total; o desagrupar_os o cancela. Nulo nos demais.';

-- Cada registro que o agrupar_os MOVEU de uma origem para a OS nova (o desagrupar devolve exatamente estes).
--   coluna       a coluna que foi mudada (service_order_id, related_entity_id...)
--   origem_id    a OS original de onde o registro saiu
--   valor_antes  só nos vínculos a LINHA (itens de cotação, comprovante -> peça): o id da linha original;
--                nulo nos vínculos à OS (o valor de antes é origem_id)
create table if not exists public.os_agrupamento_movidos (
  agrupamento_id uuid not null
    constraint os_agrupamento_movidos_agrupamento_id_fkey references public.orcamento_agrupamentos(id) on delete cascade,
  tabela text not null,
  coluna text not null,
  registro_id uuid not null,
  origem_id uuid not null
    constraint os_agrupamento_movidos_origem_id_fkey references public.service_orders(id) on delete cascade,
  valor_antes uuid,
  primary key (agrupamento_id, tabela, coluna, registro_id)
);

comment on table public.os_agrupamento_movidos is
  'Registros que agrupar_os moveu de cada OS original para a OS nova; desagrupar_os devolve. Escrita só pelas funções.';

create index if not exists os_agrupamento_movidos_origem_idx on public.os_agrupamento_movidos (origem_id);

alter table public.os_agrupamento_movidos enable row level security;
drop policy if exists os_agrupamento_movidos_select on public.os_agrupamento_movidos;
create policy os_agrupamento_movidos_select on public.os_agrupamento_movidos
  for select to authenticated using ((select auth.uid()) is not null);
revoke all on public.os_agrupamento_movidos from public, anon, authenticated;
grant select on public.os_agrupamento_movidos to authenticated;
grant all on public.os_agrupamento_movidos to service_role;

-- 2) Tipo do agrupamento ATIVO de uma origem ('os' | 'orcamento' | null). security definer: as guardas leem
--    o histórico sem depender da RLS de quem grava.
create or replace function public._agrupamento_tipo_da_origem(p_origem uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select g.tipo
    from public.orcamento_agrupamento_origens x
    join public.orcamento_agrupamentos g on g.id = x.agrupamento_id
   where x.origem_id = p_origem and g.desfeito_em is null
   order by g.criado_em desc
   limit 1
$$;

-- 3) Guardas da ORIGEM (20261015180000): mesma regra; a palavra segue o tipo do agrupamento. O texto de
--    orçamento é IDÊNTICO ao de antes (os testes de orçamento conferem trechos dele).
create or replace function public._orcamento_agrupado_guarda()
returns trigger
language plpgsql
security definer   -- lê o tipo do agrupamento (histórico) sem depender da RLS/grants de quem grava
set search_path = ''
as $$
declare
  v_destino text;
  v_liberado boolean := coalesce(current_setting('marineflow.agrupar_orcamentos', true), '') = 'on';
  v_os boolean;
begin
  if tg_op = 'INSERT' then
    -- O "Duplicar" (tela e assistente) copia o cabeçalho com spread: a cópia nasceria travada.
    new.merged_into_id := null;
    return new;
  end if;

  if v_liberado then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  v_os := coalesce(public._agrupamento_tipo_da_origem(old.id), '') = 'os';

  if tg_op = 'UPDATE' and new.merged_into_id is distinct from old.merged_into_id then
    if v_os or old.converted_to_os_at is not null then
      raise exception 'Só as funções Agrupar/Desagrupar OS mudam o vínculo de agrupamento.'
        using errcode = '42501';
    end if;
    raise exception 'Só as funções Agrupar/Desagrupar orçamentos mudam o vínculo de agrupamento.'
      using errcode = '42501';
  end if;

  -- Daqui em diante OLD é origem de um agrupamento ativo: histórico.
  select d.service_order_number into v_destino from public.service_orders d where d.id = old.merged_into_id;
  if tg_op = 'DELETE' then
    if v_os then
      raise exception 'Esta OS foi agrupada em % e fica guardada como histórico: não pode ser apagada.',
        coalesce(v_destino, 'outra OS') using errcode = '42501';
    end if;
    raise exception 'Este orçamento foi agrupado em % e fica guardado como histórico: não pode ser apagado.',
      coalesce(v_destino, 'outro orçamento') using errcode = '42501';
  end if;
  if new.status is distinct from old.status
     or new.quote_status is distinct from old.quote_status
     or new.share_token is distinct from old.share_token
     or new.converted_to_os_at is distinct from old.converted_to_os_at
     or new.signed_at is distinct from old.signed_at
     or new.client_id is distinct from old.client_id
     or new.vessel_id is distinct from old.vessel_id then
    if v_os then
      raise exception 'Esta OS foi agrupada em % e não pode mais mudar de situação, link, cliente ou embarcação. Para mexer nela, desagrupe %.',
        coalesce(v_destino, 'outra OS'), coalesce(v_destino, 'a OS agrupada') using errcode = '42501';
    end if;
    raise exception 'Este orçamento foi agrupado em % e não pode mais mudar de situação, link, cliente ou embarcação. Para mexer nele, desagrupe %.',
      coalesce(v_destino, 'outro orçamento'), coalesce(v_destino, 'o agrupado') using errcode = '42501';
  end if;
  return new;
end $$;

-- Recebível numa ORIGEM agrupada (sinal tardio etc.): mesma regra, palavra pelo tipo.
create or replace function public._orcamento_agrupado_sem_dinheiro()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_destino text;
  v_os boolean;
begin
  if tg_op = 'UPDATE' then
    -- Só mudar o vínculo conta; editar um recebível antigo que já era da origem (ex.: cancelado) passa.
    if new.service_order_id is not distinct from old.service_order_id then
      return new;
    end if;
  end if;
  select d.service_order_number into v_destino
    from public.service_orders o
    join public.service_orders d on d.id = o.merged_into_id
   where o.id = new.service_order_id;
  if v_destino is not null then
    v_os := coalesce(public._agrupamento_tipo_da_origem(new.service_order_id), '') = 'os';
    if v_os then
      raise exception 'Esta OS foi agrupada em %: lance o sinal ou o recebimento na %.', v_destino, v_destino
        using errcode = '42501';
    end if;
    raise exception 'Este orçamento foi agrupado em %: lance o sinal ou o recebimento no %.', v_destino, v_destino
      using errcode = '42501';
  end if;
  return new;
end $$;

-- Reabrir um agrupado JÁ DESAGRUPADO: a mesma guarda (gatilho e WHEN de 20261015180000 intactos); a
-- palavra segue o tipo. O ramo de cancelar continua só para orçamento (o WHEN só o chama para rascunho não
-- convertido); a OS agrupada tem a guarda dela (4).
create or replace function public._orcamento_agrupado_guarda_destino()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_origens text;
  v_tipo text;
begin
  if coalesce(current_setting('marineflow.agrupar_orcamentos', true), '') = 'on' then
    return new;
  end if;

  if new.status = 'cancelled' then
    -- O WHEN já garante: saindo de rascunho, não convertido, sem signed_at. Falta a assinatura gravada
    -- só na tabela (a mesma regra do desagrupar).
    if exists (select 1 from public.service_order_signatures s where s.service_order_id = new.id) then
      return new;
    end if;
    select string_agg(x.numero, ', ' order by x.ordem) into v_origens
      from public.orcamento_agrupamentos g
      join public.orcamento_agrupamento_origens x on x.agrupamento_id = g.id
     where g.agrupado_id = new.id and g.desfeito_em is null;
    if v_origens is not null then
      raise exception 'Este orçamento reúne %. Para cancelá-lo, use "Desagrupar" primeiro: os originais voltam a valer e depois você decide o que fazer com eles.',
        v_origens using errcode = '42501';
    end if;
    return new;
  end if;

  -- Saindo de cancelado: agrupado já desfeito não volta
  select string_agg(x.numero, ', ' order by x.ordem), max(g.tipo) into v_origens, v_tipo
    from public.orcamento_agrupamentos g
    join public.orcamento_agrupamento_origens x on x.agrupamento_id = g.id
   where g.agrupado_id = old.id and g.desfeito_em is not null;
  if v_origens is not null then
    if v_tipo = 'os' then
      raise exception 'Esta OS foi desagrupada (as originais % voltaram a valer) e fica como histórico: não pode ser reaberta. Para juntar de novo, agrupe as originais.',
        v_origens using errcode = '42501';
    end if;
    raise exception 'Este orçamento foi desagrupado (os originais % voltaram a valer) e fica como histórico: não pode ser reaberto. Para juntar de novo, agrupe os originais.',
      v_origens using errcode = '42501';
  end if;
  return new;
end $$;

-- 4) O que já é EXECUÇÃO numa OS. Vazio = ainda não começou. A MESMA checagem no agrupar (cada origem) e no
--    desagrupar (a agrupada). Baixa de estoque = SALDO negativo, por produto, dos movimentos ligados à OS
--    (reference_type 'service_order': consumo, devolução, ajuste). A reserva não é movimento (é
--    products.reserved_quantity) e a baixa estornada (OS que voltou de concluída) já devolveu a peça — com o
--    vínculo reverses_movement_id (modelo novo) ou sem ele (a OS-00033 tem baixa −1 e devolução +1 de maio
--    sem o vínculo): pelo saldo, as duas contam igual.
create or replace function public._os_execucao_iniciada(p_os uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select concat_ws(', ',
    (select case so.status
              when 'in_progress' then 'está em andamento'
              when 'completed' then 'está concluída'
              when 'invoiced' then 'está faturada'
            end
       from public.service_orders so where so.id = p_os),
    case when exists (select 1 from public.time_entries x where x.service_order_id = p_os) then 'hora apontada' end,
    case when exists (select 1 from public.service_order_expenses x where x.service_order_id = p_os)
           or exists (select 1 from public.service_orders so where so.id = p_os and coalesce(so.operational_cost_total, 0) <> 0)
         then 'despesa lançada' end,
    case when exists (select 1 from public.service_order_steps x
                       where x.service_order_id = p_os
                         and (x.status <> 'pending' or x.started_at is not null or x.completed_at is not null
                              or coalesce(x.actual_minutes, 0) > 0))
         then 'passo do roteiro já iniciado' end,
    -- A situação de campo do serviço (feito, parcial, só levantar, aguarda peça, não feito) é o técnico
    -- dizendo o que fez na linha: execução, como o passo iniciado.
    case when exists (select 1 from public.service_order_services x
                       where x.service_order_id = p_os
                         and (coalesce(x.field_status, 'a_fazer') <> 'a_fazer' or x.started_at is not null
                              or x.finished_at is not null))
         then 'serviço com situação de campo' end,
    case when exists (select 1 from public.service_order_photos x where x.service_order_id = p_os) then 'foto de campo' end,
    case when exists (select 1 from public.inventory_movements m
                       where m.reference_type = 'service_order' and m.reference_id = p_os
                       group by m.product_id
                      having sum(m.quantity_delta) < 0)
         then 'baixa de estoque' end,
    case when exists (select 1 from public.diarias_reembolsos x where x.os_id = p_os) then 'reembolso de diária' end,
    case when exists (select 1 from public.work_shift_os x where x.service_order_id = p_os)
           or exists (select 1 from public.work_shifts x where x.service_order_id = p_os)
         then 'jornada de técnico ligada' end
  )
$$;

-- 5) O que prende uma OS no papel (fiscal/comissão). Vazio = livre.
create or replace function public._os_vinculos_que_impedem(p_os uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select concat_ws(', ',
    case when exists (select 1 from public.issued_fiscal_documents x where x.origin_type = 'service_order' and x.origin_id = p_os
                        and x.status in ('draft', 'queued', 'processing', 'authorized')) then 'nota fiscal emitida ou na fila' end,
    case when exists (select 1 from public.invoices x where x.service_order_id = p_os and x.status is distinct from 'cancelled') then 'fatura' end,
    case when exists (select 1 from public.commissions x where x.service_order_id = p_os) then 'comissão lançada' end,
    case when exists (select 1 from public.fiscal_note_items x where x.service_order_id = p_os) then 'item de nota de entrada' end
  )
$$;

-- 6) Por que UMA OS não pode entrar num agrupamento (as regras de cada uma, sem as que comparam as OS entre
--    si). Nulo = pode. A mensagem é a mesma que o agrupar levanta e a que a leitura (os_para_agrupar) mostra.
create or replace function public._os_impedimento_para_agrupar(p_os uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r public.service_orders;
  v_destino text;
  v_motivo text;
  v_calc numeric;
begin
  select so.* into r from public.service_orders so where so.id = p_os;
  if r.id is null then
    return 'OS não encontrada. Recarregue a tela.';
  end if;
  if r.merged_into_id is not null then
    select d.service_order_number into v_destino from public.service_orders d where d.id = r.merged_into_id;
    return format('%s já foi agrupada em %s.', r.service_order_number, coalesce(v_destino, 'outra OS'));
  end if;
  if r.status = 'draft' then
    return format('%s ainda é um orçamento (não virou OS). Para juntar orçamentos, use "Agrupar orçamentos".',
                  r.service_order_number);
  end if;
  if r.status = 'cancelled' then
    return format('%s está cancelada e não pode ser agrupada.', r.service_order_number);
  end if;
  v_motivo := public._os_execucao_iniciada(p_os);
  if v_motivo <> '' then
    return format('%s já começou a ser executada (%s). Agrupar só junta OS que ainda não começaram; cada OS executada mantém seu histórico.',
                  r.service_order_number, v_motivo);
  end if;
  if r.status not in ('scheduled', 'open', 'awaiting_parts', 'awaiting_client', 'approved') then
    return format('%s está numa situação que não permite agrupar (%s).', r.service_order_number, r.status);
  end if;
  if coalesce(r.card_fee_passthrough_enabled, false) then
    return format('%s repassa a taxa do cartão ao cliente. Desligue o repasse nela antes de agrupar (dá para ligar de novo na OS nova).',
                  r.service_order_number);
  end if;
  v_motivo := public._os_vinculos_que_impedem(p_os);
  if v_motivo <> '' then
    return format('%s tem %s. Uma OS com nota, fatura ou comissão não entra num agrupamento: resolva isso antes ou deixe-a de fora.',
                  r.service_order_number, v_motivo);
  end if;
  select c.grand_total into v_calc from public.calc_so_totals(r.id) c;
  if abs(coalesce(r.grand_total, 0) - coalesce(v_calc, 0)) > 0.005 then
    return format('O total gravado de %s (%s) está desatualizado (o certo é %s). Abra e salve essa OS antes de agrupar.',
                  r.service_order_number, public._agrupar_orcamentos_reais(r.grand_total), public._agrupar_orcamentos_reais(v_calc));
  end if;
  return null;
end $$;

-- 7) Por que uma OS AGRUPADA não pode ser desagrupada. Nulo = pode. Usada pelo desagrupar e pela leitura.
create or replace function public._os_impedimento_para_desagrupar(p_agrupado uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ag public.service_orders;
  v_grupo uuid;
  v_saldo uuid;
  v_destino text;
  v_motivo text;
begin
  select so.* into v_ag from public.service_orders so where so.id = p_agrupado;
  if v_ag.id is null then
    return 'OS não encontrada. Recarregue a tela.';
  end if;
  select g.id, g.saldo_criado_id into v_grupo, v_saldo from public.orcamento_agrupamentos g
   where g.agrupado_id = p_agrupado and g.desfeito_em is null and g.tipo = 'os';
  if v_grupo is null then
    return format('%s não é uma OS agrupada (ou já foi desagrupada).', v_ag.service_order_number);
  end if;
  if v_ag.merged_into_id is not null then
    select d.service_order_number into v_destino from public.service_orders d where d.id = v_ag.merged_into_id;
    return format('%s foi agrupada de novo em %s. Desagrupe %s primeiro.',
                  v_ag.service_order_number, coalesce(v_destino, 'outra OS'), coalesce(v_destino, 'essa'));
  end if;
  if v_ag.status = 'cancelled' then
    return format('%s está cancelada: não dá mais para desagrupar.', v_ag.service_order_number);
  end if;
  v_motivo := public._os_execucao_iniciada(p_agrupado);
  if v_motivo <> '' then
    return format('%s já começou a ser executada (%s): não dá mais para desagrupar. As originais ficam como histórico.',
                  v_ag.service_order_number, v_motivo);
  end if;
  if v_ag.signed_at is not null
     or exists (select 1 from public.service_order_signatures s where s.service_order_id = p_agrupado) then
    return format('%s já foi assinada pelo cliente: não dá para desagrupar.', v_ag.service_order_number);
  end if;
  v_motivo := public._os_vinculos_que_impedem(p_agrupado);
  if v_motivo <> '' then
    return format('%s tem %s: não dá para desagrupar.', v_ag.service_order_number, v_motivo);
  end if;
  -- O saldo que o próprio agrupar lançou é cancelado no desagrupar; com dinheiro recebido nele, não dá
  -- (o pagamento não tem original para onde voltar).
  if v_saldo is not null
     and exists (select 1 from public.receivables x where x.id = v_saldo and x.status is distinct from 'cancelled'
                   and (coalesce(x.paid_amount, 0) > 0 or x.status in ('paid', 'partially_paid'))) then
    return format('%s já recebeu pagamento no saldo que o agrupar lançou ("Saldo — %s"): não dá para desagrupar.',
                  v_ag.service_order_number, v_ag.service_order_number);
  end if;
  -- Lançado na agrupada DEPOIS de agrupar (não veio de nenhuma original): ficaria preso na agrupada cancelada.
  -- O lançamento do extrato conciliado pelo pagamento de um recebível MOVIDO não prende: volta com ele
  -- (_desagrupar_os_desfazer).
  select concat_ws(', ',
    case when exists (select 1 from public.receivables x where x.service_order_id = p_agrupado and x.status is distinct from 'cancelled'
                        and x.id is distinct from v_saldo
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'receivables' and m.registro_id = x.id)) then 'conta a receber' end,
    case when exists (select 1 from public.collections x where x.service_order_id = p_agrupado and x.status is distinct from 'cancelled'
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'collections' and m.registro_id = x.id)) then 'cobrança' end,
    case when exists (select 1 from public.bank_charges x where x.service_order_id = p_agrupado
                        and coalesce(x.status, '') not in ('cancelled', 'failed')
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'bank_charges' and m.registro_id = x.id)) then 'boleto/Pix de cobrança' end,
    case when exists (select 1 from public.payables x where x.linked_service_order_id = p_agrupado and x.status is distinct from 'cancelled'
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'payables' and m.registro_id = x.id)) then 'conta a pagar' end,
    case when exists (select 1 from public.purchase_orders x where x.service_order_id = p_agrupado and x.status is distinct from 'cancelled'
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'purchase_orders' and m.registro_id = x.id)) then 'pedido de compra' end,
    case when exists (select 1 from public.quote_requests x where x.service_order_id = p_agrupado and x.status is distinct from 'cancelled'
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'quote_requests' and m.registro_id = x.id)) then 'cotação a fornecedor' end,
    case when exists (select 1 from public.comprovantes x where x.destino_os_id = p_agrupado
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'comprovantes' and m.registro_id = x.id)) then 'comprovante' end,
    case when exists (select 1 from public.bank_transactions t where t.reconciled_service_order_id = p_agrupado
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'bank_transactions' and m.registro_id = t.id)
                        and not exists (select 1 from public.payments p
                                          join public.os_agrupamento_movidos m on m.agrupamento_id = v_grupo
                                           and m.tabela = 'receivables' and m.registro_id = p.receivable_id
                                         where p.id = t.reconciled_payment_id or p.bank_transaction_id = t.id))
         then 'lançamento do extrato conciliado' end,
    case when exists (select 1 from public.anotacoes_do_extrato x where x.os_id = p_agrupado and x.status is distinct from 'cancelada'
                        and not exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_grupo
                                          and m.tabela = 'anotacoes_do_extrato' and m.registro_id = x.id)) then 'anotação do extrato' end
  ) into v_motivo;
  if v_motivo <> '' then
    return format('%s ganhou %s depois de agrupar. Cancele ou mova isso para uma das originais antes de desagrupar.',
                  v_ag.service_order_number, v_motivo);
  end if;
  return null;
end $$;

-- 8) payment_status pela mesma conta do gatilho sync_service_order_payment_status (que, ao mudar o
--    service_order_id de um recebível, só recalcula a OS NOVA do recebível: a de onde ele saiu fica velha).
create or replace function public._os_recalcular_payment_status(p_os uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_total numeric;
  v_pago numeric;
  v_status text;
begin
  select coalesce(sum(r.amount), 0), coalesce(sum(r.paid_amount), 0) into v_total, v_pago
    from public.receivables r
   where r.service_order_id = p_os and r.status <> 'cancelled';
  v_status := case when v_total = 0 then 'unpaid'
                   when v_pago >= v_total then 'paid'
                   when v_pago > 0 then 'partially_paid'
                   else 'unpaid' end;
  update public.service_orders so set payment_status = v_status
   where so.id = p_os and so.payment_status is distinct from v_status;
  return v_status;
end $$;

-- 9) Mover registros de uma tabela para a OS nova, guardando cada um em os_agrupamento_movidos.
--    p_tabela/p_coluna/p_filtro vêm SÓ das funções desta migration (lista fechada abaixo), nunca do usuário.
create or replace function public._os_agrupar_mover(
  p_agrupamento uuid,
  p_tabela text,
  p_coluna text,
  p_origens uuid[],
  p_novo uuid,
  p_filtro text default 'true'
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  if p_tabela not in ('receivables', 'collections', 'bank_charges', 'bank_transactions', 'payables', 'purchase_orders',
                      'quote_requests', 'comprovantes', 'anotacoes_do_extrato', 'finance_review_queue', 'entity_open_loops',
                      'agenda_tasks', 'agenda_suggestions', 'ai_followup_missions', 'whatsapp_scheduled_sends') then
    raise exception 'Tabela fora da lista do agrupar OS: %', p_tabela;
  end if;
  execute format(
    'insert into public.os_agrupamento_movidos (agrupamento_id, tabela, coluna, registro_id, origem_id) '
    || 'select $1, %L, %L, x.id, x.%I from public.%I x where x.%I = any($2) and (%s)',
    p_tabela, p_coluna, p_coluna, p_tabela, p_coluna, p_filtro)
  using p_agrupamento, p_origens;
  get diagnostics v_n = row_count;
  if v_n > 0 then
    execute format(
      'update public.%I x set %I = $1 from public.os_agrupamento_movidos m '
      || 'where m.agrupamento_id = $2 and m.tabela = %L and m.coluna = %L and m.registro_id = x.id',
      p_tabela, p_coluna, p_tabela, p_coluna)
    using p_novo, p_agrupamento;
  end if;
  return v_n;
end $$;

-- 10) Montagem (recebe o número: o teste passa um fictício e não gasta o document_number_seq) --------------
create or replace function public._agrupar_os_montar(
  p_ids uuid[],
  p_base uuid,
  p_numero text,            -- null = gera OS- pelo document_number_seq DEPOIS de validar tudo
  p_autor uuid,
  p_total_esperado numeric  -- soma dos grand_total que a tela mostrou; null = não confere
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
  v_travados uuid[];
  v_ordem uuid[];
  v_numeros text[];
  v_n integer;
  v_base public.service_orders;
  v_desloc public.service_orders;
  r public.service_orders;
  v_bloqueio text;
  v_qtd integer;
  v_lista text;
  v_soma_gravada numeric := 0;
  v_soma_base numeric := 0;
  v_calc_base numeric;
  v_seq text;
  v_numero text;
  v_quem text;
  v_novo uuid;
  v_agrupamento uuid;
  v_novo_linha uuid;
  v_mapa_serv jsonb := '{}'::jsonb;
  v_mapa_peca jsonb := '{}'::jsonb;
  v_ts timestamptz := clock_timestamp();
  v_total numeric;
  v_motivo text;
  v_receb_antes numeric;
  v_receb_qtd integer;
  v_receb_movido numeric;
  v_pagamento text;
  v_pagamento_certo text;
  v_original numeric;
  v_avisos text[] := '{}';
  v_assinadas text;
  v_quote_status text;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_saldo_id uuid;
  v_saldo_valor numeric;
  v_receb_nova numeric;
  n_servicos integer := 0;
  n_pecas integer := 0;
  n_passos integer := 0;
  n_tecnicos integer := 0;
  n_envios integer := 0;
  n_receb integer := 0;
  n_cobr integer := 0;
  n_tarefas integer := 0;
  n_movidos integer := 0;
  n_x integer;
  t_problema text[]; t_achados text[]; t_diagnostico text[]; t_solucao text[]; t_escopo text[]; t_interno text[];
  t_instrucoes text[]; t_acesso text[]; t_financeiro text[]; t_notas_tec text[]; t_relatorio text[];
  v_desconto numeric; v_imposto numeric; v_subcontrato numeric; v_horas numeric;
  v_desc_serv numeric; v_desc_pecas numeric;
  s record;
  pc record;
  st record;
  v_produto uuid;
begin
  -- 0. Quem pede (a checagem mora aqui também: _montar nunca roda sem cargo)
  if p_autor is null then
    raise exception 'Faça login para agrupar OS.' using errcode = '42501';
  end if;
  if not public.is_admin_or_financial(p_autor) then
    raise exception 'Só administrador ou financeiro pode agrupar OS.' using errcode = '42501';
  end if;

  -- 1. Entrada
  if p_ids is null or cardinality(p_ids) = 0 or array_position(p_ids, null) is not null then
    raise exception 'Escolha pelo menos 2 OS para agrupar.' using errcode = '22023';
  end if;
  v_ids := array(select distinct x from unnest(p_ids) x);
  if cardinality(v_ids) <> cardinality(p_ids) then
    raise exception 'A mesma OS foi escolhida duas vezes.' using errcode = '22023';
  end if;
  v_n := cardinality(v_ids);
  if v_n < 2 then
    raise exception 'Escolha pelo menos 2 OS para agrupar.' using errcode = '22023';
  end if;
  if v_n > 10 then
    raise exception 'Agrupe no máximo 10 OS de uma vez.' using errcode = '22023';
  end if;

  -- 2. Trava as origens sempre na mesma ordem (dois agrupamentos simultâneos não se travam; o segundo
  --    espera o primeiro e cai em "já foi agrupada")
  select array_agg(t.id) into v_travados
    from (select so.id from public.service_orders so where so.id = any(v_ids) order by so.id for update) t;
  if coalesce(cardinality(v_travados), 0) <> v_n then
    raise exception 'Alguma OS escolhida não existe mais. Recarregue a tela.' using errcode = 'P0002';
  end if;

  select array_agg(so.id order by so.created_at, so.id),
         array_agg(so.service_order_number order by so.created_at, so.id)
    into v_ordem, v_numeros
    from public.service_orders so where so.id = any(v_ids);

  -- 3. Principal: contato, marina, prioridade, tipo, situação, data, condições de pagamento e comissão
  if p_base is not null and not (p_base = any(v_ids)) then
    raise exception 'A OS principal precisa estar entre as escolhidas.' using errcode = '22023';
  end if;
  select so.* into v_base from public.service_orders so where so.id = coalesce(p_base, v_ordem[1]);

  -- 4. Cada origem: as regras dela (as mesmas que a leitura mostra) e depois as que comparam com a principal
  for r in select so.* from public.service_orders so where so.id = any(v_ids) order by so.created_at, so.id loop
    v_bloqueio := public._os_impedimento_para_agrupar(r.id);
    if v_bloqueio is not null then
      raise exception '%', v_bloqueio using errcode = '22023';
    end if;
    if r.client_id <> v_base.client_id then
      raise exception 'Só dá para agrupar OS do mesmo cliente (% é de outro cliente).', r.service_order_number
        using errcode = '22023';
    end if;
    if r.vessel_id <> v_base.vessel_id then
      raise exception 'Só dá para agrupar OS da mesma embarcação (% é de outra). Uma OS tem uma embarcação só.',
        r.service_order_number using errcode = '22023';
    end if;
    select c.base into v_calc_base from public.calc_so_totals(r.id) c;
    v_soma_gravada := v_soma_gravada + coalesce(r.grand_total, 0);
    v_soma_base := v_soma_base + coalesce(v_calc_base, 0);
  end loop;

  -- 5. Deslocamento: no máximo um (somar cobraria a viagem duas vezes)
  select count(*), string_agg(so.service_order_number, ', ' order by so.created_at, so.id)
    into v_qtd, v_lista
    from public.service_orders so
   where so.id = any(v_ids)
     and (coalesce(so.travel_cost_total, 0) <> 0 or coalesce(so.travel_distance_km, 0) <> 0
          or coalesce(so.travel_hours, 0) <> 0 or coalesce(so.ferry_cost, 0) <> 0);
  if v_qtd > 1 then
    raise exception 'Mais de uma OS tem deslocamento (%). Deixe o deslocamento em uma só antes de agrupar, para não cobrar a viagem duas vezes.',
      v_lista using errcode = '22023';
  end if;
  select so.* into v_desloc from public.service_orders so
   where so.id = any(v_ids)
     and (coalesce(so.travel_cost_total, 0) <> 0 or coalesce(so.travel_distance_km, 0) <> 0
          or coalesce(so.travel_hours, 0) <> 0 or coalesce(so.ferry_cost, 0) <> 0)
   limit 1;   -- nenhuma: campos nulos -> padrões abaixo

  if p_total_esperado is not null and round(p_total_esperado, 2) <> round(v_soma_gravada, 2) then
    raise exception 'As OS mudaram desde que a tela abriu (soma agora %). Feche e abra o agrupamento de novo.',
      public._agrupar_orcamentos_reais(v_soma_gravada) using errcode = '22023';
  end if;

  -- Dinheiro das origens ANTES de mover (a conferência do fim compara com o que chegou na nova)
  select coalesce(sum(x.amount), 0), count(*) into v_receb_antes, v_receb_qtd
    from public.receivables x where x.service_order_id = any(v_ids) and x.status is distinct from 'cancelled';

  -- 6. Cabeçalho da nova
  select array_agg(so.problem_description order by so.created_at, so.id),
         array_agg(so.initial_findings order by so.created_at, so.id),
         array_agg(so.diagnosis order by so.created_at, so.id),
         array_agg(so.solution_applied order by so.created_at, so.id),
         array_agg(so.extra_notes order by so.created_at, so.id),
         array_agg(so.internal_notes order by so.created_at, so.id),
         array_agg(so.technician_instructions order by so.created_at, so.id),
         array_agg(so.site_access order by so.created_at, so.id),
         array_agg(so.financial_notes order by so.created_at, so.id),
         array_agg(so.technician_notes order by so.created_at, so.id),
         array_agg(so.customer_visible_report order by so.created_at, so.id),
         sum(coalesce(so.discount_amount, 0)), sum(coalesce(so.tax_amount, 0)),
         sum(coalesce(so.subcontract_cost_total, 0)), sum(coalesce(so.estimated_hours, 0)),
         -- Rótulo do desconto em lote no PDF: só copia se for igual em todas (mesma regra do orçamento)
         case when count(distinct so.discount_services_pct) = 1
                   and (bool_and(coalesce(so.discount_amount, 0) > 0) or bool_and(coalesce(so.discount_amount, 0) = 0))
              then max(so.discount_services_pct) else 0 end,
         case when count(distinct so.discount_parts_pct) = 1
                   and (bool_and(coalesce(so.discount_amount, 0) > 0) or bool_and(coalesce(so.discount_amount, 0) = 0))
              then max(so.discount_parts_pct) else 0 end,
         case when bool_or(so.original_quote_amount is not null)
              then sum(coalesce(so.original_quote_amount, so.grand_total, 0)) end
    into t_problema, t_achados, t_diagnostico, t_solucao, t_escopo, t_interno, t_instrucoes, t_acesso, t_financeiro,
         t_notas_tec, t_relatorio,
         v_desconto, v_imposto, v_subcontrato, v_horas, v_desc_serv, v_desc_pecas, v_original
    from public.service_orders so where so.id = any(v_ids);

  select u.full_name into v_quem from public.app_users u where u.id = p_autor;

  if p_numero is not null then
    v_numero := p_numero;
  else
    v_seq := public.next_document_number()::text;            -- só depois de tudo validado
    v_numero := 'OS-' || lpad(v_seq, greatest(5, length(v_seq)), '0');
  end if;

  -- Situação = a da principal; data de atendimento = a da principal. quote_status 'approved': é OS — salvo
  -- quando a principal ainda espera o sinal (awaiting_deposit, sinal sem pagamento): a nova herda o "falta o
  -- sinal", e o sinal movido, quando pago, a aprova (handle_quote_deposit_payment olha o recebível).
  -- converted_to_os_at no INSERT: o gatilho orcamento_aprovado_ao_converter é BEFORE UPDATE, não dispara.
  v_quote_status := case
    when v_base.quote_status = 'awaiting_deposit'
         and not exists (select 1 from public.receivables x where x.service_order_id = v_base.id and x.is_deposit
                           and x.status in ('paid', 'partially_paid'))
      then 'awaiting_deposit'
    else 'approved' end;
  insert into public.service_orders (
    service_order_number, client_id, vessel_id, marina_id, requested_by_contact_id, requested_by_name,
    status, quote_status, converted_to_os_at, priority, service_type, currency,
    scheduled_start_at, scheduled_end_at,
    problem_description, initial_findings, diagnosis, solution_applied, extra_notes, internal_notes,
    technician_instructions, site_access, financial_notes, technician_notes, customer_visible_report,
    hourly_rate, estimated_hours,
    travel_distance_km, travel_cost_per_km, technician_count_for_travel, travel_hours, ferry_cost,
    travel_type, is_travel_billable, travel_cost_total,
    subcontract_cost_total, operational_cost_total, discount_amount, tax_amount,
    discount_services_pct, discount_parts_pct,
    payment_conditions, payment_condition_preset_id, payment_method, payment_method_preferred,
    card_installments, custom_payment_installments, card_fee_passthrough_enabled,
    customer_po_number, customer_buyer_name,
    commission_rate, commissioned_user_id, commissioned_person,
    quote_validity_days, quote_validity_date, original_quote_amount, created_by
  ) values (
    v_numero, v_base.client_id, v_base.vessel_id, v_base.marina_id, v_base.requested_by_contact_id, v_base.requested_by_name,
    v_base.status, v_quote_status, now(), coalesce(v_base.priority, 'normal'), v_base.service_type, coalesce(v_base.currency, 'BRL'),
    v_base.scheduled_start_at, v_base.scheduled_end_at,
    coalesce(public._agrupar_orcamentos_juntar(v_numeros, t_problema), 'OS que reúne ' || array_to_string(v_numeros, ', ')),
    public._agrupar_orcamentos_juntar(v_numeros, t_achados),
    public._agrupar_orcamentos_juntar(v_numeros, t_diagnostico),
    public._agrupar_orcamentos_juntar(v_numeros, t_solucao),
    public._agrupar_orcamentos_juntar(v_numeros, t_escopo),
    concat_ws(E'\n\n',
      'Reúne ' || array_to_string(v_numeros, ', ') || ' — agrupadas em '
        || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') || ' por ' || coalesce(v_quem, 'sistema')
        || '. Preços mantidos como estavam em cada OS. Situação, data, condições de pagamento e comissão vêm da '
        || v_base.service_order_number || '.',
      public._agrupar_orcamentos_juntar(v_numeros, t_interno)),
    public._agrupar_orcamentos_juntar(v_numeros, t_instrucoes),
    public._agrupar_orcamentos_juntar(v_numeros, t_acesso),
    public._agrupar_orcamentos_juntar(v_numeros, t_financeiro),
    public._agrupar_orcamentos_juntar(v_numeros, t_notas_tec),
    public._agrupar_orcamentos_juntar(v_numeros, t_relatorio),
    v_base.hourly_rate, v_horas,
    coalesce(v_desloc.travel_distance_km, 0), coalesce(v_desloc.travel_cost_per_km, 0),
    coalesce(v_desloc.technician_count_for_travel, 1), coalesce(v_desloc.travel_hours, 0), coalesce(v_desloc.ferry_cost, 0),
    coalesce(v_desloc.travel_type, 'comercial'), coalesce(v_desloc.is_travel_billable, true), coalesce(v_desloc.travel_cost_total, 0),
    v_subcontrato, 0, v_desconto, v_imposto,
    coalesce(v_desc_serv, 0), coalesce(v_desc_pecas, 0),
    v_base.payment_conditions, v_base.payment_condition_preset_id, v_base.payment_method, v_base.payment_method_preferred,
    coalesce(v_base.card_installments, 1), v_base.custom_payment_installments, false,
    v_base.customer_po_number, v_base.customer_buyer_name,
    coalesce(v_base.commission_rate, 0), v_base.commissioned_user_id, v_base.commissioned_person,
    coalesce(v_base.quote_validity_days, 15), null, v_original, p_autor
  )
  returning id into v_novo;

  -- 7. Serviços: TODAS as colunas de composição (como orçamento). Fora: execução (started/finished/elapsed,
  --    field_status — nenhuma começou). created_at em sequência explícita: as telas ordenam por created_at.
  for s in
    select x.*, o.ord
      from public.service_order_services x
      join unnest(v_ordem) with ordinality as o(so_id, ord) on o.so_id = x.service_order_id
     order by o.ord, x.created_at nulls first, x.id
  loop
    v_ts := v_ts + interval '1 millisecond';
    insert into public.service_order_services (
      service_order_id, service_id, name_snapshot, description_snapshot, billing_unit_snapshot,
      quantity, unit_price_snapshot, line_total, discount_pct, discount_amount, notes,
      technician_user_id, warranty_days, warranty_months,
      service_system, service_verb, fiscal_verb, technician_instructions, created_at, updated_at
    ) values (
      v_novo, s.service_id, s.name_snapshot, s.description_snapshot, s.billing_unit_snapshot,
      s.quantity, s.unit_price_snapshot, s.line_total, s.discount_pct, s.discount_amount, s.notes,
      s.technician_user_id, s.warranty_days, s.warranty_months,
      s.service_system, s.service_verb, s.fiscal_verb, s.technician_instructions, v_ts, v_ts
    )
    returning id into v_novo_linha;
    v_mapa_serv := v_mapa_serv || jsonb_build_object(s.id::text, v_novo_linha);
    n_servicos := n_servicos + 1;
  end loop;

  -- 8. Peças: idem + source e o vínculo peça->serviço (kit) remapeado para a linha nova
  for pc in
    select x.*, o.ord
      from public.service_order_parts x
      join unnest(v_ordem) with ordinality as o(so_id, ord) on o.so_id = x.service_order_id
     order by o.ord, x.created_at nulls first, x.id
  loop
    v_ts := v_ts + interval '1 millisecond';
    insert into public.service_order_parts (
      service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot, currency_snapshot,
      line_total_cost, line_total_sale, discount_pct, discount_amount, notes,
      warranty_days, warranty_months, serial_number, source, service_order_service_id, created_at, updated_at
    ) values (
      v_novo, pc.product_id, pc.quantity, pc.unit_cost_snapshot, pc.unit_sale_snapshot, pc.currency_snapshot,
      pc.line_total_cost, pc.line_total_sale, pc.discount_pct, pc.discount_amount, pc.notes,
      pc.warranty_days, pc.warranty_months, pc.serial_number, pc.source,
      nullif(v_mapa_serv ->> (pc.service_order_service_id::text), '')::uuid, v_ts, v_ts
    )
    returning id into v_novo_linha;
    v_mapa_peca := v_mapa_peca || jsonb_build_object(pc.id::text, v_novo_linha);
    n_pecas := n_pecas + 1;
  end loop;

  -- 9. Passos de roteiro (todos pendentes: o _os_execucao_iniciada garantiu). Copiados com o serviço
  --    remapeado; seq renumerado em sequência (a ordem de cada OS, uma depois da outra).
  for st in
    select x.*, o.ord
      from public.service_order_steps x
      join unnest(v_ordem) with ordinality as o(so_id, ord) on o.so_id = x.service_order_id
     order by o.ord, x.seq, x.created_at, x.id
  loop
    n_passos := n_passos + 1;
    v_ts := v_ts + interval '1 millisecond';
    insert into public.service_order_steps (
      service_order_id, service_order_service_id, template_id, seq, block, title, detail, kind, mode,
      standard_minutes, is_killer, requires_photo, requires_measure, measure_unit, status, assigned_user_id,
      origin, ai_confidence, ai_source, approved_by, approved_at, notes, block_key, block_note, created_at, updated_at
    ) values (
      v_novo, nullif(v_mapa_serv ->> (st.service_order_service_id::text), '')::uuid, st.template_id, n_passos,
      st.block, st.title, st.detail, st.kind, st.mode,
      st.standard_minutes, st.is_killer, st.requires_photo, st.requires_measure, st.measure_unit, 'pending', st.assigned_user_id,
      st.origin, st.ai_confidence, st.ai_source, st.approved_by, st.approved_at, st.notes, st.block_key, st.block_note, v_ts, v_ts
    );
  end loop;

  -- 10. Técnicos: a união, sem repetir pessoa (a principal primeiro, depois a ordem das OS)
  insert into public.service_order_technicians (service_order_id, user_id, role_in_order)
  select distinct on (t.user_id) v_novo, t.user_id, t.role_in_order
    from public.service_order_technicians t
    join unnest(v_ordem) with ordinality as o(so_id, ord) on o.so_id = t.service_order_id
   order by t.user_id, (t.service_order_id = v_base.id) desc, o.ord, t.created_at
  on conflict do nothing;
  get diagnostics n_tecnicos = row_count;

  -- 11. Totais pelo banco + comissão da principal sobre o total novo (mesma fórmula do orçamento)
  perform public.recalc_so_totals(v_novo);
  update public.service_orders so
     set commission_amount = case when coalesce(so.commission_rate, 0) > 0
                                  then round(coalesce(so.grand_total, 0) * so.commission_rate / 100, 2) else 0 end
   where so.id = v_novo
  returning so.grand_total into v_total;

  -- 12. Conferência dura do total (tolerância só para o arredondamento de cada origem a 2 casas)
  if v_total is null or abs(v_total - round(v_soma_base, 2)) > 0.005 * v_n then
    raise exception 'Conferência falhou: a OS agrupada deu % e a soma das originais é %. Nada foi gravado.',
      public._agrupar_orcamentos_reais(v_total), public._agrupar_orcamentos_reais(v_soma_base);
  end if;

  -- 13. Histórico do agrupamento (o "antes" de cada origem, para o desagrupar)
  insert into public.orcamento_agrupamentos (agrupado_id, criado_por, tipo) values (v_novo, p_autor, 'os')
  returning id into v_agrupamento;
  insert into public.orcamento_agrupamento_origens (
    agrupamento_id, origem_id, ordem, numero, quote_status_antes, share_token_antes,
    cancelled_at_antes, cancellation_reason_antes, grand_total_antes, status_antes
  )
  select v_agrupamento, so.id, o.ord, so.service_order_number, so.quote_status, so.share_token,
         so.cancelled_at, so.cancellation_reason, so.grand_total, so.status
    from public.service_orders so
    join unnest(v_ordem) with ordinality as o(so_id, ord) on o.so_id = so.id;

  -- 14. Mover para a nova o que é dinheiro/compromisso (cada registro guardado para o desagrupar)
  n_receb := public._os_agrupar_mover(v_agrupamento, 'receivables', 'service_order_id', v_ids, v_novo,
                                      'x.status is distinct from ''cancelled''');
  n_cobr := public._os_agrupar_mover(v_agrupamento, 'collections', 'service_order_id', v_ids, v_novo,
                                     'x.status is distinct from ''cancelled''');
  n_movidos := n_receb + n_cobr;
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'bank_charges', 'service_order_id', v_ids, v_novo,
                                     'coalesce(x.status, '''') not in (''cancelled'', ''failed'')');
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'bank_transactions', 'reconciled_service_order_id', v_ids, v_novo);
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'payables', 'linked_service_order_id', v_ids, v_novo,
                                     'x.status is distinct from ''cancelled''');
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'purchase_orders', 'service_order_id', v_ids, v_novo,
                                     'x.status is distinct from ''cancelled''');
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'quote_requests', 'service_order_id', v_ids, v_novo,
                                     'x.status is distinct from ''cancelled''');
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'comprovantes', 'destino_os_id', v_ids, v_novo);
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'anotacoes_do_extrato', 'os_id', v_ids, v_novo,
                                     'x.status is distinct from ''cancelada''');
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'finance_review_queue', 'suggested_service_order_id', v_ids, v_novo,
                                     'x.status = ''pending''');
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'entity_open_loops', 'service_order_id', v_ids, v_novo,
                                     'x.status = ''open''');
  n_tarefas := public._os_agrupar_mover(v_agrupamento, 'agenda_tasks', 'related_entity_id', v_ids, v_novo,
                                     'x.related_entity_type in (''service_order'', ''quote'') and x.source <> ''automation'' '
                                     || 'and x.status in (''pending'', ''in_progress'')');
  n_movidos := n_movidos + n_tarefas;
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'agenda_suggestions', 'related_entity_id', v_ids, v_novo,
                                     'x.related_entity_type = ''service_order'' and x.status = ''pending''');
  -- Missões vivas: ativas e as que esperam a resposta do cliente (as duas seguem acompanhando a OS)
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'ai_followup_missions', 'service_order_id', v_ids, v_novo,
                                     'x.status in (''active'', ''waiting_reply'')');
  -- Lembrete de cobrança agendado (ligado a recebível) acompanha o recebível
  n_movidos := n_movidos + public._os_agrupar_mover(v_agrupamento, 'whatsapp_scheduled_sends', 'service_order_id', v_ids, v_novo,
                                     'x.receivable_id is not null and x.status in (''pending'', ''processing'')');

  -- Vínculos a LINHA dos registros movidos: para a linha nova (valor_antes = a linha original)
  insert into public.os_agrupamento_movidos (agrupamento_id, tabela, coluna, registro_id, origem_id, valor_antes)
  select v_agrupamento, 'quote_request_items', 'service_order_part_id', i.id, p.service_order_id, i.service_order_part_id
    from public.quote_request_items i
    join public.service_order_parts p on p.id = i.service_order_part_id
   where p.service_order_id = any(v_ids)
     and exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_agrupamento
                   and m.tabela = 'quote_requests' and m.registro_id = i.quote_request_id);
  update public.quote_request_items i
     set service_order_part_id = (v_mapa_peca ->> m.valor_antes::text)::uuid
    from public.os_agrupamento_movidos m
   where m.agrupamento_id = v_agrupamento and m.tabela = 'quote_request_items' and m.coluna = 'service_order_part_id'
     and m.registro_id = i.id;
  insert into public.os_agrupamento_movidos (agrupamento_id, tabela, coluna, registro_id, origem_id, valor_antes)
  select v_agrupamento, 'quote_request_items', 'service_order_service_id', i.id, s2.service_order_id, i.service_order_service_id
    from public.quote_request_items i
    join public.service_order_services s2 on s2.id = i.service_order_service_id
   where s2.service_order_id = any(v_ids)
     and exists (select 1 from public.os_agrupamento_movidos m where m.agrupamento_id = v_agrupamento
                   and m.tabela = 'quote_requests' and m.registro_id = i.quote_request_id);
  update public.quote_request_items i
     set service_order_service_id = (v_mapa_serv ->> m.valor_antes::text)::uuid
    from public.os_agrupamento_movidos m
   where m.agrupamento_id = v_agrupamento and m.tabela = 'quote_request_items' and m.coluna = 'service_order_service_id'
     and m.registro_id = i.id;
  insert into public.os_agrupamento_movidos (agrupamento_id, tabela, coluna, registro_id, origem_id, valor_antes)
  select v_agrupamento, 'comprovantes', 'so_part_id', c.id, p.service_order_id, c.so_part_id
    from public.comprovantes c
    join public.service_order_parts p on p.id = c.so_part_id
   where p.service_order_id = any(v_ids);
  update public.comprovantes c
     set so_part_id = (v_mapa_peca ->> m.valor_antes::text)::uuid
    from public.os_agrupamento_movidos m
   where m.agrupamento_id = v_agrupamento and m.tabela = 'comprovantes' and m.coluna = 'so_part_id'
     and m.registro_id = c.id;

  -- 14b. Saldo sem título. Alguma original já tinha conta a receber e a soma delas não cobre o total novo
  --      (OS-A com sinal pago + OS-B que seria cobrada só na conclusão): a conclusão não gera nada numa OS
  --      que já tem recebível vivo (completion-receivables), e a diferença nunca seria cobrada. Um título
  --      pendente pela diferença, vencendo na conclusão — a mesma saída do assistente quando o sinal não
  --      bate com a condição (saldo-do-sinal.ts, "saldo que some é dinheiro que ninguém cobra"). Tolerância
  --      de R$ 1 (a mesma de lá): centavos de arredondamento das parcelas não viram título. Nenhuma original
  --      com recebível: nada aqui, a conclusão gera o plano inteiro da condição.
  if v_receb_qtd > 0 and round(v_total - v_receb_antes, 2) > 1 then
    v_saldo_valor := round(v_total - v_receb_antes, 2);
    insert into public.receivables (
      client_id, service_order_id, description, issue_date, due_date, amount, balance_amount, paid_amount,
      status, is_deposit, due_on_completion, notes
    ) values (
      v_base.client_id, v_novo, 'Saldo — ' || v_numero, v_hoje,
      coalesce((v_base.scheduled_end_at at time zone 'America/Sao_Paulo')::date, v_hoje + 30),
      v_saldo_valor, v_saldo_valor, 0, 'pending', false, true,
      'Lançado ao agrupar ' || array_to_string(v_numeros, ', ') || ': as OS somavam '
        || public._agrupar_orcamentos_reais(v_total) || ' e as contas a receber delas, '
        || public._agrupar_orcamentos_reais(v_receb_antes) || '.'
    )
    returning id into v_saldo_id;
    update public.orcamento_agrupamentos g set saldo_criado_id = v_saldo_id where g.id = v_agrupamento;
  end if;

  -- 15. Auditoria (antes de mudar as origens, para guardar o "antes")
  v_motivo := 'Agrupada em ' || v_numero || ' (reúne ' || array_to_string(v_numeros, ', ') || ')';
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason,
                                triggered_by_table, triggered_by_id)
  select 'service_orders', so.id, 'cancel', coalesce(v_quem, 'sistema'),
         jsonb_build_object('status', so.status, 'quote_status', so.quote_status, 'grand_total', so.grand_total,
                            'payment_status', so.payment_status),
         jsonb_build_object('status', 'cancelled', 'merged_into_id', v_novo,
                            'merged_into_number', v_numero, 'link_publico', 'desligado'),
         v_motivo, 'service_orders', v_novo
    from public.service_orders so where so.id = any(v_ids);
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('service_orders', v_novo, 'update', coalesce(v_quem, 'sistema'), null,
          jsonb_build_object('agrupa', to_jsonb(v_numeros), 'origens', to_jsonb(v_ordem), 'grand_total', v_total,
                             'principal', v_base.service_order_number, 'tipo', 'os',
                             'recebiveis_movidos', n_receb, 'registros_movidos', n_movidos,
                             'saldo_lancado', v_saldo_valor, 'saldo_receivable_id', v_saldo_id),
          'Criada agrupando ' || array_to_string(v_numeros, ', '));

  -- 16. Origens: histórico, link morto, apontando para a nova. Só situação/cancelamento/link/vínculo — NUNCA
  --     totais, textos ou descontos (assinatura!). A situação muda -> so_status_stock recalcula as reservas.
  perform set_config('marineflow.agrupar_orcamentos', 'on', true);
  update public.service_orders so
     set status = 'cancelled',
         cancelled_at = now(),
         cancellation_reason = v_motivo,
         share_token = null,
         merged_into_id = v_novo
   where so.id = any(v_ids);
  perform set_config('marineflow.agrupar_orcamentos', '', true);

  -- 17. Envios agendados com o link antigo (sem recebível): cancelados, como no orçamento
  update public.whatsapp_scheduled_sends w
     set status = 'cancelled', last_error = 'Cancelado: OS agrupada em ' || v_numero, updated_at = now()
   where w.service_order_id = any(v_ids) and w.status in ('pending', 'processing') and w.receivable_id is null;
  get diagnostics n_envios = row_count;

  -- 18. Situação de pagamento: a nova pelos recebíveis que chegaram; as origens ficaram sem nenhum
  v_pagamento := public._os_recalcular_payment_status(v_novo);
  for r in select so.* from public.service_orders so where so.id = any(v_ids) loop
    perform public._os_recalcular_payment_status(r.id);
  end loop;

  -- 19. Reserva de estoque dos produtos das linhas envolvidas (a nova reserva pela situação dela)
  if public.stock_model_v2_on() then
    for v_produto in
      select distinct p.product_id from public.service_order_parts p
       where p.service_order_id = any(v_ids || v_novo) and p.product_id is not null
    loop
      perform public.recompute_product_reservations(v_produto);
    end loop;
  end if;

  -- 20. Conferências duras do dinheiro (senão nada é gravado)
  select coalesce(sum(x.amount), 0) into v_receb_movido
    from public.receivables x
    join public.os_agrupamento_movidos m on m.registro_id = x.id and m.agrupamento_id = v_agrupamento and m.tabela = 'receivables'
   where x.service_order_id = v_novo;
  if n_receb <> v_receb_qtd or round(v_receb_movido, 2) <> round(v_receb_antes, 2) then
    raise exception 'Conferência falhou: os recebíveis das originais somavam % e chegaram % na OS agrupada. Nada foi gravado.',
      public._agrupar_orcamentos_reais(v_receb_antes), public._agrupar_orcamentos_reais(v_receb_movido);
  end if;
  if exists (select 1 from public.receivables x where x.service_order_id = any(v_ids) and x.status is distinct from 'cancelled')
     or exists (select 1 from public.collections x where x.service_order_id = any(v_ids) and x.status is distinct from 'cancelled')
     or exists (select 1 from public.bank_charges x where x.service_order_id = any(v_ids)
                  and coalesce(x.status, '') not in ('cancelled', 'failed')) then
    raise exception 'Conferência falhou: ficou recebível ou cobrança ativa numa OS original. Nada foi gravado.';
  end if;
  -- Com recebível em alguma original, os da nova cobrem o total (o saldo do 14b fecha a diferença)
  select coalesce(sum(x.amount), 0) into v_receb_nova
    from public.receivables x where x.service_order_id = v_novo and x.status is distinct from 'cancelled';
  if v_receb_qtd > 0 and v_receb_nova < v_total - 1 then
    raise exception 'Conferência falhou: as contas a receber da OS agrupada (%) não cobrem o total (%). Nada foi gravado.',
      public._agrupar_orcamentos_reais(v_receb_nova), public._agrupar_orcamentos_reais(v_total);
  end if;
  select case when coalesce(sum(x.amount), 0) = 0 then 'unpaid'
              when coalesce(sum(x.paid_amount), 0) >= sum(x.amount) then 'paid'
              when coalesce(sum(x.paid_amount), 0) > 0 then 'partially_paid'
              else 'unpaid' end
    into v_pagamento_certo
    from public.receivables x where x.service_order_id = v_novo and x.status <> 'cancelled';
  if (select so.payment_status from public.service_orders so where so.id = v_novo) is distinct from v_pagamento_certo then
    raise exception 'Conferência falhou: a situação de pagamento da OS agrupada não bate com os recebíveis. Nada foi gravado.';
  end if;

  -- 21. Avisos para a tela/assistente mostrarem depois de agrupar
  select string_agg(so.service_order_number, ', ' order by so.created_at, so.id) into v_assinadas
    from public.service_orders so
   where so.id = any(v_ids)
     and (so.signed_at is not null or exists (select 1 from public.service_order_signatures g where g.service_order_id = so.id));
  if v_assinadas is not null then
    v_avisos := v_avisos || ('As assinaturas ficaram nas OS originais (' || v_assinadas || '): a ' || v_numero
                             || ' nasce sem assinatura. Se precisar, peça ao cliente para assinar a OS nova.');
  end if;
  v_avisos := v_avisos || ('Condição de pagamento, contato e comissão vêm da ' || v_base.service_order_number
                           || '; a comissão foi recalculada sobre o total novo.');
  select string_agg(so.service_order_number, ', ' order by so.created_at, so.id) into v_lista
    from public.service_orders so
    join public.orcamento_agrupamento_origens x on x.origem_id = so.id and x.agrupamento_id = v_agrupamento
   where x.status_antes is distinct from v_base.status;
  if v_lista is not null then
    v_avisos := v_avisos || ('As OS estavam em situações diferentes: a ' || v_numero
                             || ' ficou com a situação da principal (' || v_base.service_order_number || ').');
  end if;
  select string_agg(so.service_order_number || ' (' || to_char(so.scheduled_start_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') || ')',
                    ', ' order by so.created_at, so.id) into v_lista
    from public.service_orders so
   where so.id = any(v_ids) and so.id <> v_base.id and so.scheduled_start_at is not null
     and so.scheduled_start_at is distinct from v_base.scheduled_start_at;
  if v_lista is not null then
    v_avisos := v_avisos || ('Tinha atendimento marcado em outra data: ' || v_lista || '. A ' || v_numero
                             || ' ficou com a data da principal: confira a agenda.');
  end if;
  if v_saldo_id is not null then
    v_avisos := v_avisos || ('As OS somavam ' || public._agrupar_orcamentos_reais(v_total) || ', mas só '
                             || public._agrupar_orcamentos_reais(v_receb_antes) || ' tinham conta a receber: a ' || v_numero
                             || ' ganhou o recebível "Saldo — ' || v_numero || '" de ' || public._agrupar_orcamentos_reais(v_saldo_valor)
                             || ', pendente, que vence na conclusão. Confira as parcelas no financeiro.');
  end if;
  -- Chegada no barco registrada numa original: fica nela (não é copiada; ver o cabeçalho)
  select string_agg(so.service_order_number || ' ('
                    || to_char(coalesce(so.check_in_at, so.check_out_at) at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || ')',
                    ', ' order by so.created_at, so.id) into v_lista
    from public.service_orders so
   where so.id = any(v_ids) and (so.check_in_at is not null or so.check_out_at is not null);
  if v_lista is not null then
    v_avisos := v_avisos || ('Já houve chegada no barco registrada em ' || v_lista || ': o registro fica na original, e a '
                             || v_numero || ' começa sem chegada registrada.');
  end if;
  v_avisos := array_append(v_avisos, 'Na hora da nota: uma NFS-e cobre um tomador, um código de serviço e uma competência.');

  return jsonb_build_object(
    'service_order_id', v_novo, 'numero', v_numero, 'agrupamento_id', v_agrupamento,
    'origens', to_jsonb(v_numeros), 'principal', v_base.service_order_number,
    'servicos', n_servicos, 'pecas', n_pecas, 'passos', n_passos,
    'recebiveis_movidos', n_receb, 'cobrancas_movidas', n_cobr, 'tarefas_movidas', n_tarefas,
    'registros_movidos', n_movidos, 'tecnicos', n_tecnicos, 'envios_cancelados', n_envios,
    'total_geral', v_total, 'payment_status', v_pagamento,
    'saldo_lancado', v_saldo_valor,
    'comissao', (select so.commission_amount from public.service_orders so where so.id = v_novo),
    'avisos', to_jsonb(v_avisos));
end $$;

-- 11) Desmontagem: cada registro movido volta; as originais voltam como estavam; a agrupada fica cancelada
create or replace function public._desagrupar_os_desfazer(p_agrupado uuid, p_autor uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ag public.service_orders;
  v_grupo public.orcamento_agrupamentos;
  v_bloqueio text;
  v_quem text;
  v_numeros text[];
  v_ids uuid[];
  v_qtd integer;
  v_motivo text;
  n_envios integer := 0;
  n_reativados integer := 0;
  n_devolvidos integer := 0;
  n_x integer;
  o record;
  m record;
  v_produto uuid;
begin
  if p_autor is null then
    raise exception 'Faça login para desagrupar OS.' using errcode = '42501';
  end if;
  if not public.is_admin_or_financial(p_autor) then
    raise exception 'Só administrador ou financeiro pode desagrupar OS.' using errcode = '42501';
  end if;
  if p_agrupado is null then
    raise exception 'Escolha a OS agrupada.' using errcode = '22023';
  end if;

  select so.* into v_ag from public.service_orders so where so.id = p_agrupado for update;
  if v_ag.id is null then
    raise exception 'OS não encontrada. Recarregue a tela.' using errcode = 'P0002';
  end if;

  select g.* into v_grupo from public.orcamento_agrupamentos g
   where g.agrupado_id = p_agrupado and g.desfeito_em is null and g.tipo = 'os'
   for update;
  if v_grupo.id is null then
    raise exception '% não é uma OS agrupada (ou já foi desagrupada).', v_ag.service_order_number
      using errcode = '22023';
  end if;

  v_bloqueio := public._os_impedimento_para_desagrupar(p_agrupado);
  if v_bloqueio is not null then
    raise exception '%', v_bloqueio using errcode = '22023';
  end if;

  -- Trava as origens (mesma ordem do agrupar) e confere que seguem presas a esta agrupada
  select array_agg(t.id) into v_ids
    from (select so.id from public.service_orders so
            join public.orcamento_agrupamento_origens x on x.origem_id = so.id and x.agrupamento_id = v_grupo.id
           order by so.id for update of so) t;
  select count(*) into v_qtd from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id;
  if coalesce(cardinality(v_ids), 0) <> v_qtd or v_qtd = 0 then
    raise exception 'Alguma OS original deste agrupamento não existe mais. Nada foi desfeito.' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.service_orders so where so.id = any(v_ids)
              and (so.merged_into_id is distinct from v_ag.id or so.status <> 'cancelled')) then
    raise exception 'As originais de % não estão mais como o agrupamento deixou. Nada foi desfeito.',
      v_ag.service_order_number using errcode = '22023';
  end if;

  select array_agg(x.numero order by x.ordem) into v_numeros
    from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id;
  select u.full_name into v_quem from public.app_users u where u.id = p_autor;
  v_motivo := 'Desagrupada em ' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')
           || ' por ' || coalesce(v_quem, 'sistema') || ': voltaram a valer ' || array_to_string(v_numeros, ', ');

  -- Auditoria antes de mexer (guarda o "antes")
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason,
                                triggered_by_table, triggered_by_id)
  select 'service_orders', x.origem_id, 'reopen', coalesce(v_quem, 'sistema'),
         jsonb_build_object('status', 'cancelled', 'merged_into_id', v_ag.id, 'merged_into_number', v_ag.service_order_number),
         jsonb_build_object('status', x.status_antes, 'quote_status', x.quote_status_antes, 'link_publico', 'religado'),
         'Desagrupada de ' || v_ag.service_order_number, 'service_orders', v_ag.id
    from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id;
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('service_orders', v_ag.id, 'cancel', coalesce(v_quem, 'sistema'),
          jsonb_build_object('status', v_ag.status, 'quote_status', v_ag.quote_status, 'grand_total', v_ag.grand_total),
          jsonb_build_object('status', 'cancelled', 'desagrupado', to_jsonb(v_numeros), 'link_publico', 'desligado'),
          v_motivo);

  perform set_config('marineflow.agrupar_orcamentos', 'on', true);
  -- Origens PRIMEIRO (limpar merged_into_id): a guarda do recebível recusa recebível em origem agrupada
  for o in select x.* from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id order by x.ordem loop
    update public.service_orders so
       set status = coalesce(o.status_antes, 'approved'),
           quote_status = o.quote_status_antes,
           cancelled_at = o.cancelled_at_antes,
           cancellation_reason = o.cancellation_reason_antes,
           share_token = coalesce(o.share_token_antes, gen_random_uuid()),
           merged_into_id = null
     where so.id = o.origem_id;
  end loop;

  -- Cada registro movido volta à sua OS (só se ainda está na agrupada; vínculo a linha volta à linha original)
  for m in select x.* from public.os_agrupamento_movidos x where x.agrupamento_id = v_grupo.id
            order by x.tabela, x.coluna, x.registro_id loop
    if m.valor_antes is not null then
      execute format('update public.%I x set %I = $1 where x.id = $2', m.tabela, m.coluna)
        using m.valor_antes, m.registro_id;
    else
      execute format('update public.%I x set %I = $1 where x.id = $2 and x.%I = $3', m.tabela, m.coluna, m.coluna)
        using m.origem_id, m.registro_id, v_ag.id;
    end if;
    get diagnostics n_x = row_count;
    n_devolvidos := n_devolvidos + n_x;
  end loop;

  -- Lançamento do extrato conciliado na agrupada DEPOIS de agrupar, pagando um recebível que acabou de voltar
  -- (o Pix do saldo conciliado na OS-N): segue o recebível — senão o extrato diria "conciliado com a OS-N
  -- (cancelada)". O impedimento já garantiu que os demais lançamentos conciliados na agrupada vieram das origens.
  update public.bank_transactions t
     set reconciled_service_order_id = r.service_order_id
    from public.payments p
    join public.receivables r on r.id = p.receivable_id
   where (t.reconciled_payment_id = p.id or p.bank_transaction_id = t.id)
     and t.reconciled_service_order_id = v_ag.id
     and r.service_order_id is not null and r.service_order_id <> v_ag.id;
  get diagnostics n_x = row_count;
  n_devolvidos := n_devolvidos + n_x;

  -- Origem que esperava o sinal (awaiting_deposit) e cujo sinal, movido, foi pago na agrupada: o gatilho
  -- handle_quote_deposit_payment só age quando o recebível MUDA de situação, então quem acerta é aqui.
  update public.service_orders so
     set quote_status = 'approved'
   where so.id = any(v_ids) and so.quote_status = 'awaiting_deposit'
     and exists (select 1 from public.receivables x where x.service_order_id = so.id and x.is_deposit
                   and x.status in ('paid', 'partially_paid'));

  -- O saldo que o agrupar lançou não tem original: cancelado (o impedimento garantiu que nada foi pago nele)
  if v_grupo.saldo_criado_id is not null then
    update public.receivables x
       set status = 'cancelled',
           notes = concat_ws(E'\n', x.notes, 'Cancelado: ' || v_ag.service_order_number || ' desagrupada.')
     where x.id = v_grupo.saldo_criado_id and x.status is distinct from 'cancelled';
  end if;

  -- Agrupada: cancelada como histórico, link desligado (a guarda da agrupada deixa passar só aqui)
  update public.service_orders so
     set status = 'cancelled',
         cancelled_at = now(),
         cancellation_reason = v_motivo,
         share_token = null
   where so.id = v_ag.id;
  perform set_config('marineflow.agrupar_orcamentos', '', true);

  -- Totais das origens pelo banco (alguém pode ter mexido numa linha enquanto estavam canceladas; numa
  -- original assinada, só um total que MUDOU de fato supera a assinatura — e aí ela tem mesmo de ser refeita)
  for o in select x.origem_id from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id loop
    perform public.recalc_so_totals(o.origem_id);
    perform public._os_recalcular_payment_status(o.origem_id);
  end loop;
  perform public._os_recalcular_payment_status(v_ag.id);

  if public.stock_model_v2_on() then
    for v_produto in
      select distinct p.product_id from public.service_order_parts p
       where p.service_order_id = any(v_ids || v_ag.id) and p.product_id is not null
    loop
      perform public.recompute_product_reservations(v_produto);
    end loop;
  end if;

  -- Envios agendados das origens que o agrupar cancelou voltam (o link voltou), se a hora ainda não passou
  update public.whatsapp_scheduled_sends w
     set status = 'pending', last_error = null, updated_at = now()
   where w.service_order_id = any(v_ids) and w.status = 'cancelled'
     and w.last_error = 'Cancelado: OS agrupada em ' || v_ag.service_order_number
     and w.next_run_at > now();
  get diagnostics n_reativados = row_count;

  -- Lembrete de cobrança criado na agrupada DEPOIS de agrupar para um recebível que voltou: acompanha o
  -- recebível (o cliente continua sendo cobrado). Os de link da agrupada, e os do saldo cancelado, morrem.
  update public.whatsapp_scheduled_sends w
     set service_order_id = r.service_order_id, updated_at = now()
    from public.receivables r
   where w.receivable_id = r.id and w.service_order_id = v_ag.id
     and w.status in ('pending', 'processing')
     and r.service_order_id is not null and r.service_order_id <> v_ag.id
     and r.status is distinct from 'cancelled';
  get diagnostics n_x = row_count;
  n_devolvidos := n_devolvidos + n_x;

  update public.whatsapp_scheduled_sends w
     set status = 'cancelled', last_error = 'Cancelado: OS desagrupada', updated_at = now()
   where w.service_order_id = v_ag.id and w.status in ('pending', 'processing');
  get diagnostics n_envios = row_count;

  update public.orcamento_agrupamentos g
     set desfeito_em = now(), desfeito_por = p_autor
   where g.id = v_grupo.id;

  return jsonb_build_object(
    'agrupado_id', v_ag.id, 'agrupado', v_ag.service_order_number,
    'origens', to_jsonb(v_numeros), 'origens_ids', (select to_jsonb(array_agg(x.origem_id order by x.ordem))
                                                      from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id),
    'registros_devolvidos', n_devolvidos,
    'envios_cancelados', n_envios, 'envios_reativados', n_reativados);
end $$;

-- 12) Guarda da OS AGRUPADA: cancelar pelo caminho normal (menu, seletor, cancel_service_order_cascade,
--     assistente) ENQUANTO ela ainda pode ser desagrupada deixaria as originais canceladas para sempre:
--     recusado, desagrupe primeiro. Depois de começar a execução (ou ganhar nota/assinatura...) cancela como
--     qualquer outra e as originais ficam como histórico. Reabrir a já desagrupada: a guarda de 20261015180000
--     (ramo "saindo de cancelado") já recusa, com a palavra OS. O gatilho de orçamento não muda.
create or replace function public._os_agrupada_guarda_destino()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_origens text;
begin
  if coalesce(current_setting('marineflow.agrupar_orcamentos', true), '') = 'on' then
    return new;
  end if;
  select string_agg(x.numero, ', ' order by x.ordem) into v_origens
    from public.orcamento_agrupamentos g
    join public.orcamento_agrupamento_origens x on x.agrupamento_id = g.id
   where g.agrupado_id = new.id and g.desfeito_em is null and g.tipo = 'os';
  if v_origens is null then
    return new;
  end if;
  -- A mesma regra do desagrupar, olhando a OS como estava ANTES de cancelar
  if public._os_impedimento_para_desagrupar(new.id) is null then
    raise exception 'Esta OS reúne %. Para cancelá-la, use "Desagrupar" primeiro: as originais voltam a valer e depois você decide o que fazer com elas.',
      v_origens using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists trg_os_agrupada_guarda_destino on public.service_orders;
create trigger trg_os_agrupada_guarda_destino
  before update of status on public.service_orders
  for each row when (new.status = 'cancelled' and old.status is distinct from 'cancelled' and old.converted_to_os_at is not null)
  execute function public._os_agrupada_guarda_destino();

-- 13) Leitura para a tela e o assistente (só leitura) -------------------------------------------------------
--   os               as OS ATIVAS da embarcação (e do cliente, se dito), não agrupadas, do mais NOVO para o
--                    mais antigo (as 20 mais novas + p_incluir), com elegível/motivo (a MESMA mensagem que o
--                    agrupar levanta), o que acompanha (recebíveis, tarefas manuais, compras, técnicos),
--                    assinatura e data de atendimento.
--   fora_da_lista    as 5 OS mais recentes da embarcação que não estão ativas (agrupada, concluída, faturada,
--                    cancelada) — o assistente avisa o dono se ele contava com elas.
--   agrupados_ativos as OS desta embarcação que reúnem outras (tipo 'os'), com as origens e se dá para desagrupar.
create or replace function public.os_para_agrupar(
  p_vessel_id uuid,
  p_client_id uuid default null,
  p_autor uuid default null,
  p_incluir uuid[] default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_autor uuid := coalesce(auth.uid(), p_autor);
  v_barco_id uuid;
  v_barco_nome text;
  v_barco_cliente uuid;
  v_cliente_id uuid;
  v_cliente_nome text;
  v_ativas integer;
  v_os jsonb;
  v_fora jsonb;
  v_agrupados jsonb;
begin
  if v_autor is null then
    raise exception 'Faça login para ver as OS a agrupar.' using errcode = '42501';
  end if;
  if not public.is_admin_or_financial(v_autor) then
    raise exception 'Só administrador ou financeiro pode agrupar OS.' using errcode = '42501';
  end if;
  if p_vessel_id is null then
    raise exception 'Diga de qual embarcação são as OS.' using errcode = '22023';
  end if;

  select v.id, v.name, v.client_id into v_barco_id, v_barco_nome, v_barco_cliente
    from public.vessels v where v.id = p_vessel_id;
  if v_barco_id is null then
    raise exception 'Embarcação não encontrada.' using errcode = 'P0002';
  end if;
  select c.id, c.name into v_cliente_id, v_cliente_nome
    from public.clients c where c.id = coalesce(p_client_id, v_barco_cliente);
  if p_client_id is not null and v_cliente_id is null then
    raise exception 'Cliente não encontrado.' using errcode = 'P0002';
  end if;

  select count(*) into v_ativas
    from public.service_orders so
   where so.vessel_id = p_vessel_id
     and (p_client_id is null or so.client_id = p_client_id)
     and so.status in ('approved', 'scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client')
     and so.merged_into_id is null;

  select coalesce(jsonb_agg(t.item order by t.criado desc, t.id desc), '[]'::jsonb)
    into v_os
    from (
      select so.id, so.created_at as criado,
             jsonb_build_object(
               'id', so.id,
               'numero', so.service_order_number,
               'criado_em', so.created_at,
               'data', to_char(so.created_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
               'cliente_id', so.client_id,
               'cliente', c.name,
               'status', so.status,
               -- os rótulos da tela (supabase/functions/_shared/service-order-status.ts)
               'situacao', case so.status
                             when 'scheduled' then 'Agendada'
                             when 'open' then 'Aberta'
                             when 'in_progress' then 'Em andamento'
                             when 'awaiting_parts' then 'Aguardando peças'
                             when 'awaiting_client' then 'Aguardando cliente'
                             when 'approved' then 'Aprovada'
                             else so.status
                           end,
               'total', coalesce(so.grand_total, 0),
               'elegivel', m.motivo is null,
               'motivo', m.motivo,
               'resumo', nullif(left(btrim(regexp_replace(coalesce(so.problem_description, ''), '\s+', ' ', 'g')), 160), ''),
               'tem_deslocamento', (coalesce(so.travel_cost_total, 0) <> 0 or coalesce(so.travel_distance_km, 0) <> 0
                                    or coalesce(so.travel_hours, 0) <> 0 or coalesce(so.ferry_cost, 0) <> 0),
               'assinada', (so.signed_at is not null
                            or exists (select 1 from public.service_order_signatures g where g.service_order_id = so.id)),
               'agendada_para', so.scheduled_start_at,
               'desconto', coalesce(so.discount_amount, 0),
               'comissao_pct', coalesce(so.commission_rate, 0),
               'comissionado', nullif(btrim(coalesce(so.commissioned_person, '')), ''),
               'condicao_pagamento', coalesce(pc.label, nullif(btrim(coalesce(so.payment_conditions, '')), '')),
               'payment_status', so.payment_status,
               'recebiveis', jsonb_build_object('quantidade', rec.qtd, 'total', rec.total, 'pago', rec.pago),
               'tarefas_manuais', (select count(*) from public.agenda_tasks a
                                    where a.related_entity_id = so.id and a.related_entity_type in ('service_order', 'quote')
                                      and a.source <> 'automation' and a.status in ('pending', 'in_progress')),
               'compras', (select count(*) from public.purchase_orders p
                            where p.service_order_id = so.id and p.status is distinct from 'cancelled'),
               'tecnicos', (select count(*) from public.service_order_technicians t where t.service_order_id = so.id),
               'reune', ag.origens
             ) as item
        from public.service_orders so
        left join public.clients c on c.id = so.client_id
        left join public.payment_condition_presets pc on pc.id = so.payment_condition_preset_id
        cross join lateral (select public._os_impedimento_para_agrupar(so.id) as motivo) m
        cross join lateral (
          select count(*) as qtd, coalesce(sum(r.amount), 0) as total, coalesce(sum(r.paid_amount), 0) as pago
            from public.receivables r where r.service_order_id = so.id and r.status is distinct from 'cancelled'
        ) rec
        left join lateral (
          select jsonb_agg(x.numero order by x.ordem) as origens
            from public.orcamento_agrupamentos g
            join public.orcamento_agrupamento_origens x on x.agrupamento_id = g.id
           where g.agrupado_id = so.id and g.desfeito_em is null
        ) ag on true
       where so.id in (
               (select x.id
                  from public.service_orders x
                 where x.vessel_id = p_vessel_id
                   and (p_client_id is null or x.client_id = p_client_id)
                   and x.status in ('approved', 'scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client')
                   and x.merged_into_id is null
                 order by x.created_at desc, x.id desc
                 limit 20)
               union
               (select x.id
                  from public.service_orders x
                 where x.id = any(coalesce(p_incluir, '{}'::uuid[]))
                   and x.vessel_id = p_vessel_id
                   and (p_client_id is null or x.client_id = p_client_id)
                   and x.status in ('approved', 'scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client')
                   and x.merged_into_id is null))
    ) t;

  select coalesce(jsonb_agg(t.item order by t.criado desc, t.id desc), '[]'::jsonb)
    into v_fora
    from (
      select so.id, so.created_at as criado,
             jsonb_build_object(
               'numero', so.service_order_number,
               'criado_em', so.created_at,
               'data', to_char(so.created_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
               'total', coalesce(so.grand_total, 0),
               'por_que', case
                            when so.merged_into_id is not null
                              then 'já agrupada em ' || coalesce(d.service_order_number, 'outra OS')
                            when so.status = 'cancelled' then 'cancelada'
                            when so.status = 'completed' then 'concluída'
                            when so.status = 'invoiced' then 'faturada'
                            else so.status
                          end
             ) as item
        from public.service_orders so
        left join public.service_orders d on d.id = so.merged_into_id
       where so.vessel_id = p_vessel_id
         and (p_client_id is null or so.client_id = p_client_id)
         and so.status <> 'draft'
         and not (so.status in ('approved', 'scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client')
                  and so.merged_into_id is null)
         -- origens de agrupamento de ORÇAMENTO são orçamentos cancelados: não entram
         and (so.converted_to_os_at is not null or so.status in ('completed', 'invoiced'))
       order by so.created_at desc, so.id desc
       limit 5
    ) t;

  select coalesce(jsonb_agg(t.item order by t.quando desc), '[]'::jsonb)
    into v_agrupados
    from (
      select g.criado_em as quando,
             jsonb_build_object(
               'id', so.id,
               'numero', so.service_order_number,
               'agrupado_em', g.criado_em,
               'data', to_char(g.criado_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
               'total', coalesce(so.grand_total, 0),
               'origens', (select jsonb_agg(x.numero order by x.ordem)
                             from public.orcamento_agrupamento_origens x where x.agrupamento_id = g.id),
               'pode_desagrupar', d.motivo is null,
               'motivo', d.motivo
             ) as item
        from public.orcamento_agrupamentos g
        join public.service_orders so on so.id = g.agrupado_id
        cross join lateral (select public._os_impedimento_para_desagrupar(so.id) as motivo) d
       where g.desfeito_em is null
         and g.tipo = 'os'
         and so.vessel_id = p_vessel_id
         and (p_client_id is null or so.client_id = p_client_id)
    ) t;

  return jsonb_build_object(
    'embarcacao', jsonb_build_object('id', v_barco_id, 'nome', v_barco_nome),
    'cliente', case when v_cliente_id is null then null else jsonb_build_object('id', v_cliente_id, 'nome', v_cliente_nome) end,
    'ordem', 'do mais novo para o mais antigo',
    'ativas', v_ativas,
    'mostrando', jsonb_array_length(v_os),
    'os', v_os,
    'fora_da_lista', v_fora,
    'agrupados_ativos', v_agrupados);
end $$;

comment on function public.os_para_agrupar(uuid, uuid, uuid, uuid[]) is
  'Só leitura. OS ativas da embarcação (do mais novo ao mais antigo; as 20 mais novas + p_incluir) com elegibilidade e motivo para agrupar (a mesma mensagem do agrupar_os), as OS recentes fora da lista e as OS agrupadas ativas (com pode_desagrupar/motivo). Autor = auth.uid() ou p_autor; só admin/financeiro.';

-- 14) A leitura de ORÇAMENTOS (20261015181000) não lista agrupamentos de OS em agrupados_ativos (lá o
--     motivo diria "já virou OS" e o desagrupar de orçamento não serve para eles). Única mudança: g.tipo.
create or replace function public.orcamentos_para_agrupar(
  p_vessel_id uuid,
  p_client_id uuid default null,
  p_autor uuid default null,
  p_incluir uuid[] default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_autor uuid := coalesce(auth.uid(), p_autor);
  v_barco_id uuid;
  v_barco_nome text;
  v_barco_cliente uuid;
  v_cliente_id uuid;
  v_cliente_nome text;
  v_em_aberto integer;
  v_orcamentos jsonb;
  v_fora jsonb;
  v_agrupados jsonb;
begin
  if v_autor is null then
    raise exception 'Faça login para ver os orçamentos a agrupar.' using errcode = '42501';
  end if;
  if not public.is_admin_or_financial(v_autor) then
    raise exception 'Só administrador ou financeiro pode agrupar orçamentos.' using errcode = '42501';
  end if;
  if p_vessel_id is null then
    raise exception 'Diga de qual embarcação são os orçamentos.' using errcode = '22023';
  end if;

  select v.id, v.name, v.client_id into v_barco_id, v_barco_nome, v_barco_cliente
    from public.vessels v where v.id = p_vessel_id;
  if v_barco_id is null then
    raise exception 'Embarcação não encontrada.' using errcode = 'P0002';
  end if;
  select c.id, c.name into v_cliente_id, v_cliente_nome
    from public.clients c where c.id = coalesce(p_client_id, v_barco_cliente);
  if p_client_id is not null and v_cliente_id is null then
    raise exception 'Cliente não encontrado.' using errcode = 'P0002';
  end if;

  -- Quantos estão em aberto (a lista mostra os 20 mais novos + os pedidos: o assistente avisa se cortou)
  select count(*) into v_em_aberto
    from public.service_orders so
   where so.vessel_id = p_vessel_id
     and (p_client_id is null or so.client_id = p_client_id)
     and so.status = 'draft'
     and so.converted_to_os_at is null
     and so.merged_into_id is null;

  -- Os orçamentos em aberto, do mais novo para o mais antigo. O motivo segue a ordem de
  -- _agrupar_orcamentos_montar: reprovado, assinado, repasse do cartão, vínculos, total desatualizado.
  select coalesce(jsonb_agg(t.item order by t.criado desc, t.id desc), '[]'::jsonb)
    into v_orcamentos
    from (
      select so.id, so.created_at as criado,
             jsonb_build_object(
               'id', so.id,
               'numero', so.service_order_number,
               'criado_em', so.created_at,
               'data', to_char(so.created_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
               'atualizado_em', so.updated_at,
               'cliente_id', so.client_id,
               'cliente', c.name,
               'total', coalesce(so.grand_total, 0),
               'quote_status', coalesce(so.quote_status, 'draft'),
               -- os rótulos da tela (src/lib/constants.ts, quoteStatusConfig)
               'situacao', case coalesce(so.quote_status, 'draft')
                             when 'draft' then 'Em elaboração'
                             when 'sent' then 'Enviado'
                             when 'awaiting_approval' then 'Aguardando aprovação'
                             when 'approved' then 'Aprovado'
                             when 'awaiting_deposit' then 'Aguardando sinal'
                             when 'rejected' then 'Reprovado'
                             else so.quote_status
                           end,
               'reprovado', coalesce(so.quote_status, '') = 'rejected',
               -- só a data registrada da reprovação; null = não registrada
               'reprovado_em', case when so.quote_status = 'rejected' then rep.quando end,
               'reprovado_em_data', case when so.quote_status = 'rejected' and rep.quando is not null
                                         then to_char(rep.quando at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') end,
               'elegivel', m.motivo is null,
               'motivo', m.motivo,
               'impedimento_se_voltar', case when so.quote_status = 'rejected' then o.outro end,
               'resumo', nullif(left(btrim(regexp_replace(coalesce(so.problem_description, ''), '\s+', ' ', 'g')), 160), ''),
               'tem_deslocamento', (coalesce(so.travel_cost_total, 0) <> 0 or coalesce(so.travel_distance_km, 0) <> 0
                                    or coalesce(so.travel_hours, 0) <> 0 or coalesce(so.ferry_cost, 0) <> 0),
               'desconto', coalesce(so.discount_amount, 0),
               'imposto', coalesce(so.tax_amount, 0),
               'comissao_pct', coalesce(so.commission_rate, 0),
               'comissionado', nullif(btrim(coalesce(so.commissioned_person, '')), ''),
               'condicao_pagamento', coalesce(pc.label, nullif(btrim(coalesce(so.payment_conditions, '')), '')),
               'reune', ag.origens
             ) as item
        from public.service_orders so
        left join public.clients c on c.id = so.client_id
        left join public.payment_condition_presets pc on pc.id = so.payment_condition_preset_id
        cross join lateral (
          select (so.signed_at is not null
                  or exists (select 1 from public.service_order_signatures g where g.service_order_id = so.id)) as assinado,
                 public._orcamento_vinculos_que_prendem(so.id) as vinculos,
                 (select k.grand_total from public.calc_so_totals(so.id) k) as calculado
        ) v
        cross join lateral (
          select case
                   when v.assinado then 'assinado pelo cliente'
                   when coalesce(so.card_fee_passthrough_enabled, false) then 'repassa a taxa do cartão'
                   when coalesce(v.vinculos, '') <> '' then 'ligado a: ' || v.vinculos
                   when abs(coalesce(so.grand_total, 0) - coalesce(v.calculado, 0)) > 0.005 then 'total gravado desatualizado'
                 end as outro
        ) o
        cross join lateral (
          select case when so.quote_status = 'rejected' then 'reprovado pelo cliente (desistência)' else o.outro end as motivo
        ) m
        left join lateral (
          select max(a.changed_at) as quando
            from public.audit_log a
           where a.table_name = 'service_orders'
             and a.record_id = so.id
             and a.action = 'update'
             and a.new_value ->> 'quote_status' = 'rejected'
        ) rep on so.quote_status = 'rejected'
        left join lateral (
          select jsonb_agg(x.numero order by x.ordem) as origens
            from public.orcamento_agrupamentos g
            join public.orcamento_agrupamento_origens x on x.agrupamento_id = g.id
           where g.agrupado_id = so.id and g.desfeito_em is null
        ) ag on true
       where so.id in (
               (select x.id
                  from public.service_orders x
                 where x.vessel_id = p_vessel_id
                   and (p_client_id is null or x.client_id = p_client_id)
                   and x.status = 'draft'
                   and x.converted_to_os_at is null
                   and x.merged_into_id is null
                 order by x.created_at desc, x.id desc
                 limit 20)
               union
               (select x.id
                  from public.service_orders x
                 where x.id = any(coalesce(p_incluir, '{}'::uuid[]))
                   and x.vessel_id = p_vessel_id
                   and (p_client_id is null or x.client_id = p_client_id)
                   and x.status = 'draft'
                   and x.converted_to_os_at is null
                   and x.merged_into_id is null))
    ) t;

  -- Os mais recentes que NÃO estão em aberto: "os N últimos" pula esses — o dono pode estar contando com eles
  select coalesce(jsonb_agg(t.item order by t.criado desc, t.id desc), '[]'::jsonb)
    into v_fora
    from (
      select so.id, so.created_at as criado,
             jsonb_build_object(
               'numero', so.service_order_number,
               'criado_em', so.created_at,
               'data', to_char(so.created_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
               'total', coalesce(so.grand_total, 0),
               'por_que', case
                            when so.merged_into_id is not null
                              then 'já agrupado em ' || coalesce(d.service_order_number, 'outro orçamento')
                            when so.status = 'cancelled' then 'cancelado'
                            -- fora de rascunho é OS (há antigas sem converted_to_os_at: ORÇ-00070, concluída)
                            else 'virou OS'
                          end
             ) as item
        from public.service_orders so
        left join public.service_orders d on d.id = so.merged_into_id
       where so.vessel_id = p_vessel_id
         and (p_client_id is null or so.client_id = p_client_id)
         and not (so.status = 'draft' and so.converted_to_os_at is null and so.merged_into_id is null)
       order by so.created_at desc, so.id desc
       limit 5
    ) t;

  -- Agrupados ainda ativos desta embarcação (o que o desagrupar desfaz)
  select coalesce(jsonb_agg(t.item order by t.quando desc), '[]'::jsonb)
    into v_agrupados
    from (
      select g.criado_em as quando,
             jsonb_build_object(
               'id', so.id,
               'numero', so.service_order_number,
               'agrupado_em', g.criado_em,
               'data', to_char(g.criado_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
               'total', coalesce(so.grand_total, 0),
               'origens', (select jsonb_agg(x.numero order by x.ordem)
                             from public.orcamento_agrupamento_origens x where x.agrupamento_id = g.id),
               'pode_desagrupar', so.status = 'draft' and so.converted_to_os_at is null and so.merged_into_id is null
                                  and so.signed_at is null
                                  and not exists (select 1 from public.service_order_signatures s where s.service_order_id = so.id)
                                  and public._orcamento_vinculos_que_prendem(so.id) = '',
               'motivo', case
                           when so.merged_into_id is not null then 'foi agrupado de novo em outro orçamento: desagrupe aquele primeiro'
                           when so.status <> 'draft' or so.converted_to_os_at is not null then 'já virou OS ou foi cancelado'
                           when so.signed_at is not null
                                or exists (select 1 from public.service_order_signatures s where s.service_order_id = so.id)
                             then 'assinado pelo cliente'
                           when public._orcamento_vinculos_que_prendem(so.id) <> ''
                             then 'ligado a: ' || public._orcamento_vinculos_que_prendem(so.id)
                         end
             ) as item
        from public.orcamento_agrupamentos g
        join public.service_orders so on so.id = g.agrupado_id
       where g.desfeito_em is null
         and g.tipo = 'orcamento'
         and so.vessel_id = p_vessel_id
         and (p_client_id is null or so.client_id = p_client_id)
    ) t;

  return jsonb_build_object(
    'embarcacao', jsonb_build_object('id', v_barco_id, 'nome', v_barco_nome),
    'cliente', case when v_cliente_id is null then null else jsonb_build_object('id', v_cliente_id, 'nome', v_cliente_nome) end,
    'ordem', 'do mais novo para o mais antigo',
    'em_aberto', v_em_aberto,
    'mostrando', jsonb_array_length(v_orcamentos),
    'orcamentos', v_orcamentos,
    'fora_da_lista', v_fora,
    'agrupados_ativos', v_agrupados);
end $$;

-- 15) Portas públicas: só resolvem o autor --------------------------------------------------------------------
-- Na tela vale o usuário da sessão e p_autor é IGNORADO (ninguém se passa por outro).
-- Sem sessão só chega o service role (anon/public não executam): vale p_autor (assistente).
create or replace function public.agrupar_os(
  p_os uuid[],
  p_base uuid default null,
  p_total_esperado numeric default null,
  p_autor uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  return public._agrupar_os_montar(p_os, p_base, null, coalesce(auth.uid(), p_autor), p_total_esperado);
end $$;

create or replace function public.desagrupar_os(
  p_agrupado uuid,
  p_autor uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  return public._desagrupar_os_desfazer(p_agrupado, coalesce(auth.uid(), p_autor));
end $$;

comment on function public.agrupar_os(uuid[], uuid, numeric, uuid) is
  'Agrupa 2 a 10 OS que ainda não começaram (mesmo cliente e embarcação) numa OS nova; as originais ficam canceladas como histórico. Autor = auth.uid() ou p_autor (service role); só admin/financeiro.';
comment on function public.desagrupar_os(uuid, uuid) is
  'Desfaz agrupar_os enquanto a OS agrupada não começou a execução: cada registro movido volta, as originais voltam como estavam e a agrupada fica cancelada. Autor = auth.uid() ou p_autor; só admin/financeiro.';

-- 16) Privilégios + prova ---------------------------------------------------------------------------------------
revoke all on function public._agrupamento_tipo_da_origem(uuid) from public, anon, authenticated;
revoke all on function public._os_execucao_iniciada(uuid) from public, anon, authenticated;
revoke all on function public._os_vinculos_que_impedem(uuid) from public, anon, authenticated;
revoke all on function public._os_impedimento_para_agrupar(uuid) from public, anon, authenticated;
revoke all on function public._os_impedimento_para_desagrupar(uuid) from public, anon, authenticated;
revoke all on function public._os_recalcular_payment_status(uuid) from public, anon, authenticated;
revoke all on function public._os_agrupar_mover(uuid, text, text, uuid[], uuid, text) from public, anon, authenticated;
revoke all on function public._os_agrupada_guarda_destino() from public, anon, authenticated;
revoke all on function public._orcamento_agrupado_guarda() from public, anon, authenticated;
revoke all on function public._orcamento_agrupado_guarda_destino() from public, anon, authenticated;
revoke all on function public._orcamento_agrupado_sem_dinheiro() from public, anon, authenticated;
revoke all on function public._agrupar_os_montar(uuid[], uuid, text, uuid, numeric) from public, anon, authenticated;
revoke all on function public._desagrupar_os_desfazer(uuid, uuid) from public, anon, authenticated;
revoke all on function public.agrupar_os(uuid[], uuid, numeric, uuid) from public, anon;
revoke all on function public.desagrupar_os(uuid, uuid) from public, anon;
revoke all on function public.os_para_agrupar(uuid, uuid, uuid, uuid[]) from public, anon;
grant execute on function public._agrupar_os_montar(uuid[], uuid, text, uuid, numeric) to service_role;
grant execute on function public._desagrupar_os_desfazer(uuid, uuid) to service_role;
grant execute on function public.agrupar_os(uuid[], uuid, numeric, uuid) to authenticated, service_role;
grant execute on function public.desagrupar_os(uuid, uuid) to authenticated, service_role;
grant execute on function public.os_para_agrupar(uuid, uuid, uuid, uuid[]) to authenticated, service_role;

do $$
declare
  v_ag text := 'public.agrupar_os(uuid[], uuid, numeric, uuid)';
  v_des text := 'public.desagrupar_os(uuid, uuid)';
  v_mon text := 'public._agrupar_os_montar(uuid[], uuid, text, uuid, numeric)';
  v_dfz text := 'public._desagrupar_os_desfazer(uuid, uuid)';
  v_ler text := 'public.os_para_agrupar(uuid, uuid, uuid, uuid[])';
  v_mov text := 'public._os_agrupar_mover(uuid, text, text, uuid[], uuid, text)';
  v_f text;
begin
  foreach v_f in array array[v_mon, v_dfz, v_mov, 'public._os_execucao_iniciada(uuid)', 'public._os_vinculos_que_impedem(uuid)',
                             'public._os_impedimento_para_agrupar(uuid)', 'public._os_impedimento_para_desagrupar(uuid)',
                             'public._os_recalcular_payment_status(uuid)', 'public._agrupamento_tipo_da_origem(uuid)',
                             'public._os_agrupada_guarda_destino()'] loop
    if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute') then
      raise exception 'Privilégios errados em agrupar OS: % executável por anon/authenticated', v_f;
    end if;
  end loop;
  if has_function_privilege('anon', v_ag, 'execute')
     or has_function_privilege('anon', v_des, 'execute')
     or has_function_privilege('anon', v_ler, 'execute')
     or not has_function_privilege('authenticated', v_ag, 'execute')
     or not has_function_privilege('authenticated', v_des, 'execute')
     or not has_function_privilege('authenticated', v_ler, 'execute')
     or not has_function_privilege('service_role', v_mon, 'execute')
     or not has_function_privilege('service_role', v_dfz, 'execute')
     or (select p.provolatile from pg_proc p where p.oid = v_ler::regprocedure) <> 's'
     or has_table_privilege('anon', 'public.os_agrupamento_movidos', 'select')
     or not has_table_privilege('authenticated', 'public.os_agrupamento_movidos', 'select')
     or has_table_privilege('authenticated', 'public.os_agrupamento_movidos', 'insert, update, delete')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.os_agrupamento_movidos'::regclass)
  then
    raise exception 'Privilégios errados em agrupar/desagrupar OS';
  end if;
end $$;

notify pgrst, 'reload schema';

insert into supabase_migrations.schema_migrations (version, name)
values ('20261028120000', 'agrupar_os')
on conflict do nothing;

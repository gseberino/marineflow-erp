-- Cobrança, fatia 2 (24/11/2026): a conta a RECEBER de NF-e é BAIXADA quando o banco mostra o crédito do boleto que o
-- cliente pagou. É o espelho, do lado do cliente, da "baixa pelo boleto" das contas a pagar (20270222100000).
--
-- De onde vem: medido em 24/11 — as parcelas da NF-e (duplicata, boleto emitido no banco) eram pagas no dia e no valor
-- exatos e continuavam "vencidas" até o dono responder "é este" na fila do Extrato. Duas parcelas (R$ 5.237,99 de 16/10
-- e R$ 5.238,02 de 13/11) estavam assim, e a manhã recomendou "ligar hoje" para o cliente 50 vezes com o boleto no
-- banco desde o vencimento. Nenhuma entrada da fila recebia decisão desde 28/09.
--
-- A regra que isto ABRE EXCEÇÃO: decisão do dono de 26/09/2026 — ligar dinheiro a OS, conta ou pagamento "deve sempre
-- questionar" (_shared/banking/vinculo.ts, vinculoAutomatico devolve sempre null). Em 24/11/2026 o dono liberou ("sim,
-- quero") a exceção estrita abaixo, a mesma que ele já tinha aberto em 22/11 para o boleto que a empresa paga. Todo o
-- resto continua sendo pergunta.
--
-- O crédito de boleto NÃO traz nome nem documento de quem pagou: a identidade é o valor no centavo + o dia do
-- vencimento + a conta ser de NF-e com duplicata/boleto + não haver NADA parecido por perto. Por isso as condições são
-- mais duras que as do lado de pagar. Faltando UMA, a linha fica na fila como estava:
--
--   A LINHA DO BANCO
--   · entrada de conta de banco conectada, já efetivada (POSTED), com a descrição exata "CREDITO DE BOLETO" (lista
--     fechada, por igualdade: outro texto do banco só entra com decisão do dono) e proposta pendente na fila;
--   · sem lançamento, pagamento ou registro de conciliação de qualquer tipo — linha em que alguém já mexeu (casou,
--     desfez, estornou, cancelou) é do dono e nunca vai sozinha;
--   · sem anotação do dono, comprovante ou pagador guardado; sem outra proposta para ela na fila;
--   · fora das reservadas da rodada; mês do crédito aberto.
--   A CONTA
--   · em aberto, inteira (nada pago, saldo = valor), sem linha do banco, sem OS, sem fatura, sem ser sinal nem saldo de
--     orçamento agrupado;
--   · nascida de NF-e autorizada de produção, do mesmo cliente, com forma de pagamento duplicata (14) ou boleto (15);
--   · valor igual no centavo e VENCIMENTO NO DIA DO CRÉDITO (boleto pago com atraso ou que vence em fim de semana
--     continua pergunta — no histórico, 1 em cada 3);
--   · sem nenhum pagamento na vida (nem estornado) e sem registro de conciliação — conta em que uma baixa foi desfeita
--     nunca mais é baixada sozinha, por nenhuma linha;
--   · mês da nota aberto (o desfazer recusa pelo mês da emissão: só se baixa sozinho o que dá para desfazer).
--   UNICIDADE
--   · UMA conta candidata só;
--   · nenhuma OUTRA conta a receber em aberto, de qualquer origem, com o mesmo valor (ou saldo) vencida até o dia do
--     crédito — o cliente pode estar pagando a parcela atrasada no dia da seguinte;
--   · nenhum OUTRO crédito de banco solto com o mesmo valor em 45 dias para cada lado, com qualquer descrição;
--   · a fila não discorda: cliente sugerido vazio ou o da conta; vínculo sugerido vazio ou esta mesma conta (sugestão de
--     saldo de OS ou de sinal de orçamento também é discordar).
--
-- O que acontece na baixa: a mesma função de sempre (conciliar_lancamento) registra o pagamento na data do banco; a
-- proposta da fila fica "aprovada" com automatica = 'boleto' (aparece em "Lançados sozinhos") e SEM created_receivable_id
-- — com ele, o desfazer cancelaria a duplicata da nota em vez de devolvê-la para em aberto; o registro da conciliação
-- ganha "Baixa automática pelo boleto". Nada é recebido nem cobrado: isto só reconhece o que o banco já mostrou.
-- Desfazer: desfazer_aprovacao('receivable', conta) — a conta volta a ficar em aberto, o pagamento é estornado e a linha
-- volta para a fila na análise seguinte, como pergunta.
-- Chave de desligar: app_settings.boleto_recebido_baixa_modo = 'desligado' (ausente = ligado).
-- p_simular = true devolve o que seria baixado sem gravar nada, olhando cada linha contra o estado de agora: não conta o
-- efeito de uma baixa sobre as linhas seguintes da mesma rodada (duas parcelas de mesmo valor com vencimentos a mais de
-- 45 dias um do outro, cada uma com o seu crédito: a simulação mostra 1 baixada + 1 ambígua, a rodada baixa as 2). Nunca
-- promete mais do que a rodada faz.
--
-- Sem dados e sem mudança de tabela (a marca 'boleto' já cabe em finance_review_queue.automatica desde 20270222100000).
-- Quem chama: finance-review (varredura), depois da baixa das contas a pagar e antes do "lançar sozinho".

-- 1. As contas que um crédito de boleto pode estar pagando --------------------------------------------------------
create or replace function public._contas_que_o_credito_de_boleto_paga(p_transacao uuid)
returns table (id uuid, client_id uuid, cliente text, descricao text, due_date date, amount numeric)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.client_id,
         coalesce(nullif(btrim(c.name), ''), 'cliente não informado') as cliente,
         coalesce(nullif(btrim(r.description), ''), 'conta a receber') as descricao,
         r.due_date, r.amount
    from public.bank_transactions t
    join public.receivables r
      on r.status in ('pending', 'overdue')
     and coalesce(r.paid_amount, 0) = 0
     and abs(coalesce(r.balance_amount, r.amount) - r.amount) < 0.005
     and r.bank_transaction_id is null
     and r.payment_method in ('14', '15')
     and r.service_order_id is null
     and r.invoice_id is null
     and coalesce(r.is_deposit, false) = false
     and abs(r.amount - t.amount) < 0.005
     and r.due_date = t.transaction_date
     and not public.periodo_esta_fechado(r.issue_date)
     -- conta em que já houve pagamento (mesmo estornado) ou conciliação é do dono
     and not exists (select 1 from public.payments x where x.receivable_id = r.id)
     and not exists (select 1 from public.reconciliation_log g where g.receivable_id = r.id)
     and not exists (select 1 from public.orcamento_agrupamentos o where o.saldo_criado_id = r.id)
    join public.issued_fiscal_documents d
      on d.id = r.issued_fiscal_document_id
     and d.document_type = 'nfe'
     and d.status = 'authorized'
     and d.environment = 'producao'
     and d.client_id = r.client_id
    join public.clients c on c.id = r.client_id
   where t.id = p_transacao
     and t.transaction_type = 'credit'
     and t.source_type = 'bank'
     and t.bank_connection_id is not null
     and t.tx_status = 'POSTED'
     and upper(btrim(t.description)) = 'CREDITO DE BOLETO'
     and coalesce(t.payment_method, 'OTHER') in ('OTHER', 'BOLETO');
$$;

revoke all on function public._contas_que_o_credito_de_boleto_paga(uuid) from public;
revoke all on function public._contas_que_o_credito_de_boleto_paga(uuid) from anon;
revoke all on function public._contas_que_o_credito_de_boleto_paga(uuid) from authenticated;
grant execute on function public._contas_que_o_credito_de_boleto_paga(uuid) to service_role;

-- 2. A baixa -----------------------------------------------------------------------------------------------------
create or replace function public.baixar_recebido_pelo_boleto(
  p_exceto uuid[] default '{}'::uuid[],
  p_hoje date default public._hoje_brt(),
  p_simular boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_modo text;
  l record;
  c record;
  v_contas int;
  v_baixadas int := 0;
  v_ambiguas int := 0;
  v_barradas int := 0;
  v_erros text[] := '{}';
  v_itens jsonb := '[]'::jsonb;
  v_item jsonb;
begin
  select lower(btrim(value)) into v_modo from public.app_settings where key = 'boleto_recebido_baixa_modo';
  if v_modo = 'desligado' then
    return jsonb_build_object('pulado', true);
  end if;
  -- duas rodadas ao mesmo tempo (cron, a disparada pela sincronização do banco, o botão da tela): a segunda sai
  if not p_simular and not pg_try_advisory_xact_lock(hashtext('baixar_recebido_pelo_boleto')) then
    return jsonb_build_object('pulado', true);
  end if;

  for l in
    select t.id, t.transaction_date, t.amount, q.id as fila_id, q.suggested_client_id,
           -- saldo de OS e sinal de orçamento não têm lancamentoId: o destino sugerido fica em principal.id
           coalesce(q.vinculo_sugerido -> 'principal' ->> 'lancamentoId', q.vinculo_sugerido -> 'principal' ->> 'id') as vinculo
      from public.finance_review_queue q
      join public.bank_transactions t on t.id = q.bank_transaction_id
     where q.status = 'pending' and q.kind = 'create_receivable'
       and t.transaction_type = 'credit' and t.source_type = 'bank'
       and t.bank_connection_id is not null
       and t.tx_status = 'POSTED'
       and upper(btrim(t.description)) = 'CREDITO DE BOLETO'
       and coalesce(t.payment_method, 'OTHER') in ('OTHER', 'BOLETO')
       and t.reconciled is not true and t.dismissed_kind is null
       and t.reconciled_payment_id is null and t.reconciled_service_order_id is null
       and t.transaction_date <= p_hoje
       and not public.periodo_esta_fechado(t.transaction_date)
       and not (t.id = any (coalesce(p_exceto, '{}'::uuid[])))
       and not exists (select 1 from public.payables p where p.bank_transaction_id = t.id)
       and not exists (select 1 from public.receivables r where r.bank_transaction_id = t.id)
       and not exists (select 1 from public.payments x where x.bank_transaction_id = t.id)
       -- linha em que alguém já mexeu (casou, desfez, estornou, cancelou): nunca mais sozinha
       and not exists (select 1 from public.reconciliation_log g where g.bank_transaction_id = t.id)
       and not exists (select 1 from public.finance_review_queue q2
                        where q2.bank_transaction_id = t.id and q2.id <> q.id
                          and (q2.status in ('pending', 'approved', 'rejected') or q2.automatica is not null))
       and not exists (select 1 from public.finance_review_queue q3
                        where q3.related_transaction_id = t.id and q3.status = 'pending')
       -- o que o dono já disse sobre a linha
       and not exists (select 1 from public.anotacoes_do_extrato a where a.bank_transaction_id = t.id)
       and not exists (select 1 from public.comprovantes k where k.bank_transaction_id = t.id)
       and not exists (select 1 from public.pagadores_do_cliente g where g.bank_transaction_id = t.id)
     order by t.transaction_date, t.id
  loop
    select count(*) into v_contas from public._contas_que_o_credito_de_boleto_paga(l.id);
    if v_contas = 0 then
      continue;
    end if;
    if v_contas > 1 then
      v_ambiguas := v_ambiguas + 1;
      continue;
    end if;
    select k.* into c from public._contas_que_o_credito_de_boleto_paga(l.id) k;

    if
      -- outra conta em aberto de mesmo valor (ou saldo) vencida até o dia: pode ser a parcela atrasada
      exists (select 1 from public.receivables r2
               where r2.id <> c.id
                 and r2.status in ('pending', 'overdue', 'partially_paid')
                 and (abs(r2.amount - l.amount) < 0.005 or abs(coalesce(r2.balance_amount, 0) - l.amount) < 0.005)
                 and r2.due_date <= l.transaction_date)
      -- outro crédito de banco solto de mesmo valor por perto, com qualquer descrição
      or exists (select 1 from public.bank_transactions t2
                  where t2.id <> l.id
                    and t2.transaction_type = 'credit' and t2.source_type = 'bank'
                    and t2.reconciled is not true and t2.dismissed_kind is null
                    and abs(t2.amount - l.amount) < 0.005
                    and t2.transaction_date between l.transaction_date - 45 and l.transaction_date + 45)
      -- a fila discorda: sugeriu outro cliente ou outra conta
      or (l.suggested_client_id is not null and l.suggested_client_id <> c.client_id)
      or (l.vinculo is not null and l.vinculo <> c.id::text)
    then
      v_ambiguas := v_ambiguas + 1;
      continue;
    end if;

    v_item := jsonb_build_object(
      'transacao', l.id, 'conta', c.id, 'cliente', c.cliente, 'descricao', c.descricao, 'valor', l.amount,
      'vencimento', c.due_date, 'pago_em', l.transaction_date);

    if p_simular then
      v_baixadas := v_baixadas + 1;
      v_itens := v_itens || v_item;
      continue;
    end if;

    begin
      -- a conta ainda é a mesma de quando foi escolhida? (conciliar_lancamento não confere valor nem estado)
      perform 1 from public.receivables r
        where r.id = c.id and r.status in ('pending', 'overdue') and coalesce(r.paid_amount, 0) = 0
          and r.bank_transaction_id is null and abs(r.amount - l.amount) < 0.005
        for update;
      if not found then
        continue;
      end if;

      perform public.conciliar_lancamento('receivable', c.id, l.id, null);
      -- conciliar_lancamento fecha a proposta como 'superseded': aqui ela vira a marca da baixa (pelo id, sem status)
      update public.finance_review_queue
         set status = 'approved', automatica = 'boleto', decided_by = null, decided_at = now(),
             -- o cliente na frente: a tela corta a linha, e o título da proposta é só "Receita: CREDITO DE BOLETO"
             decision_note = left(left(c.cliente, 40) || ' — recebimento baixado sozinho pelo boleto: ' || c.descricao
                                  || ', vencimento ' || to_char(c.due_date, 'DD/MM/YYYY')
                                  || ' (mesmo valor, crédito no dia do vencimento)', 300)
       where id = l.fila_id;
      update public.reconciliation_log
         set detalhe = left('Baixa automática pelo boleto · ' || coalesce(detalhe, ''), 300)
       where bank_transaction_id = l.id and receivable_id = c.id and acao = 'conciliou'
         and coalesce(detalhe, '') not like 'Baixa automática pelo boleto%';
      v_baixadas := v_baixadas + 1;
      v_itens := v_itens || v_item;
    exception when others then
      v_barradas := v_barradas + 1;
      v_erros := v_erros || left(sqlstate || ': ' || sqlerrm, 200);
    end;
  end loop;

  return jsonb_build_object(
    'baixadas', v_baixadas, 'ambiguas', v_ambiguas, 'barradas', v_barradas,
    'erros', to_jsonb(v_erros), 'itens', v_itens)
    || case when p_simular then jsonb_build_object('simulado', true) else '{}'::jsonb end;
end;
$$;

revoke all on function public.baixar_recebido_pelo_boleto(uuid[], date, boolean) from public;
revoke all on function public.baixar_recebido_pelo_boleto(uuid[], date, boolean) from anon;
revoke all on function public.baixar_recebido_pelo_boleto(uuid[], date, boolean) from authenticated;
grant execute on function public.baixar_recebido_pelo_boleto(uuid[], date, boolean) to service_role;

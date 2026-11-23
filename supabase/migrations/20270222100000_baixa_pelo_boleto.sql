-- O que vence, fatia 2 (22/11/2026): a conta com boleto conhecido é BAIXADA quando o banco mostra o pagamento.
--
-- De onde vem: a fatia 1 (20270221100000) cria a conta a pagar a partir do boleto do e-mail. Sem esta fatia, a conta
-- paga continuava "em aberto" até o dono responder "é este" na fila do Extrato — medido em 22/11: duas parcelas da TSD
-- (R$ 785,07 em 20/10 e R$ 784,82 em 17/11) pagas por boleto e ainda vencidas, numa fila com 284 itens parados.
--
-- A regra que isto ABRE EXCEÇÃO: decisão do dono de 26/09/2026 — ligar dinheiro a OS, conta ou pagamento "deve sempre
-- questionar" (_shared/banking/vinculo.ts, vinculoAutomatico devolve sempre null). Em 22/11/2026 o dono liberou, nomeando
-- essa regra, a exceção estrita abaixo ("A: baixar sozinho só no caso seguro"). Todo o resto continua sendo pergunta.
--
-- O caso seguro (todas as condições; faltando uma, a linha fica na fila como estava):
--   · a linha do banco é uma SAÍDA paga por BOLETO, com proposta pendente na fila, sem lançamento nem pagamento ligado,
--     fora das reservadas da rodada (comprovante, anotação) e que nunca teve uma baixa desfeita;
--   · a conta está em aberto, inteira (nada pago), sem linha do banco, e tem a linha digitável de um boleto de banco
--     (47 dígitos; arrecadação de 48 dígitos não traz o banco e fica de fora);
--   · valor igual no centavo;
--   · o banco do boleto (3 primeiros dígitos da linha) é o banco que a saída informa (counterparty_bank);
--   · pagamento entre 45 dias antes e 30 dias depois do vencimento;
--   · quando o fornecedor da conta tem documento e o banco informa o do favorecido, a raiz do CNPJ tem de bater;
--   · as contas candidatas são de UM mesmo fornecedor; entre parcelas de valor igual, vale a de vencimento mais próximo
--     do pagamento — e ela tem de ser única (empate = pergunta);
--   · não há mais pagamentos iguais esperando do que contas iguais em aberto.
--
-- O que acontece na baixa: a mesma função de sempre (conciliar_lancamento) registra o pagamento na data do banco; a
-- proposta da fila fica "aprovada" com automatica = 'boleto' (aparece em "Lançados sozinhos"); o registro da conciliação
-- ganha "Baixa automática pelo boleto". Nada é pago: isto só reconhece o que o banco já mostrou.
-- Desfazer: desfazer_aprovacao('payable', conta) — a conta volta a ficar em aberto, o pagamento é estornado e a linha
-- volta para a fila na varredura seguinte; a linha que teve baixa desfeita nunca mais é baixada sozinha.
-- Chave de desligar: app_settings.boleto_baixa_modo = 'desligado' (ausente = ligado).
--
-- Sem dados. Quem chama: finance-review (varredura), antes do "lançar sozinho".

-- 1. A marca "boleto" ao lado de "regra" e "confianca" -----------------------------------------------------------
alter table public.finance_review_queue drop constraint if exists finance_review_queue_automatica_check;
alter table public.finance_review_queue add constraint finance_review_queue_automatica_check
  check (automatica = any (array['regra'::text, 'confianca'::text, 'boleto'::text]));

-- 2. As contas que uma saída por boleto pode estar pagando -------------------------------------------------------
create or replace function public._contas_que_o_boleto_paga(p_transacao uuid)
returns table (id uuid, due_date date, quem text, nome text, distancia int)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.due_date,
         coalesce(p.supplier_id::text, lower(btrim(coalesce(p.supplier_name, '')))) as quem,
         coalesce(nullif(btrim(p.supplier_name), ''), 'fornecedor não informado') as nome,
         abs(p.due_date - t.transaction_date) as distancia
    from public.bank_transactions t
    join public.payables p
      on p.status in ('pending', 'overdue')
     and p.bank_transaction_id is null
     and coalesce(p.paid_amount, 0) = 0
     and p.boleto_linha ~ '^[0-9]{47}$'
     and left(p.boleto_linha, 3) = lpad(regexp_replace(coalesce(t.counterparty_bank, ''), '\D', '', 'g'), 3, '0')
     and abs(p.amount - t.amount) < 0.01
     and t.transaction_date between p.due_date - 45 and p.due_date + 30
    left join public.suppliers s on s.id = p.supplier_id
   where t.id = p_transacao
     and t.transaction_type = 'debit'
     and t.payment_method = 'BOLETO'
     and regexp_replace(coalesce(t.counterparty_bank, ''), '\D', '', 'g') <> ''
     -- documento conhecido dos dois lados e diferente: não é este fornecedor (raiz do CNPJ, para matriz e filial)
     and not (
       regexp_replace(coalesce(s.cnpj_cpf, ''), '\D', '', 'g') <> ''
       and regexp_replace(coalesce(t.counterparty_document, ''), '\D', '', 'g') <> ''
       and case
             when length(regexp_replace(s.cnpj_cpf, '\D', '', 'g')) = 14
              and length(regexp_replace(t.counterparty_document, '\D', '', 'g')) = 14
               then left(regexp_replace(s.cnpj_cpf, '\D', '', 'g'), 8) <> left(regexp_replace(t.counterparty_document, '\D', '', 'g'), 8)
             else regexp_replace(s.cnpj_cpf, '\D', '', 'g') <> regexp_replace(t.counterparty_document, '\D', '', 'g')
           end
     );
$$;

revoke all on function public._contas_que_o_boleto_paga(uuid) from public;
revoke all on function public._contas_que_o_boleto_paga(uuid) from anon;
revoke all on function public._contas_que_o_boleto_paga(uuid) from authenticated;
grant execute on function public._contas_que_o_boleto_paga(uuid) to service_role;

-- 3. A baixa -----------------------------------------------------------------------------------------------------
create or replace function public.baixar_pelo_boleto(
  p_exceto uuid[] default '{}'::uuid[],
  p_hoje date default public._hoje_brt()
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
  v_fornecedores int;
  v_empatadas int;
  v_concorrentes int;
  v_min date;
  v_max date;
  v_baixadas int := 0;
  v_ambiguas int := 0;
  v_barradas int := 0;
  v_erros text[] := '{}';
  v_itens jsonb := '[]'::jsonb;
begin
  select lower(btrim(value)) into v_modo from public.app_settings where key = 'boleto_baixa_modo';
  if v_modo = 'desligado' then
    return jsonb_build_object('pulado', true);
  end if;

  for l in
    select t.id, t.transaction_date, t.amount, q.id as fila_id,
           lpad(regexp_replace(coalesce(t.counterparty_bank, ''), '\D', '', 'g'), 3, '0') as banco
      from public.finance_review_queue q
      join public.bank_transactions t on t.id = q.bank_transaction_id
     where q.status = 'pending' and q.kind = 'create_payable'
       and t.transaction_type = 'debit' and t.payment_method = 'BOLETO'
       and t.reconciled is not true and t.dismissed_kind is null
       and coalesce(t.tx_status, '') <> 'PENDING'
       and t.transaction_date <= p_hoje
       and not (t.id = any (coalesce(p_exceto, '{}'::uuid[])))
       and not exists (select 1 from public.payables p where p.bank_transaction_id = t.id)
       and not exists (select 1 from public.receivables r where r.bank_transaction_id = t.id)
       and not exists (select 1 from public.payments x where x.bank_transaction_id = t.id and x.status = 'confirmed')
       -- a linha em que o dono já desfez um vínculo é dele: nunca mais sozinha
       and not exists (select 1 from public.reconciliation_log g where g.bank_transaction_id = t.id and g.acao = 'desconciliou')
     order by t.transaction_date, t.id
  loop
    select count(*), count(distinct k.quem), min(k.due_date), max(k.due_date)
      into v_contas, v_fornecedores, v_min, v_max
      from public._contas_que_o_boleto_paga(l.id) k;
    if v_contas = 0 then
      continue;
    end if;

    -- a mais próxima do dia do pagamento; a mais antiga só desempata na ordem, o empate é contado abaixo
    select k.* into c from public._contas_que_o_boleto_paga(l.id) k order by k.distancia, k.due_date, k.id limit 1;
    select count(*) into v_empatadas from public._contas_que_o_boleto_paga(l.id) k where k.distancia = c.distancia;

    -- pagamentos iguais (valor, banco) esperando na fila, na janela dessas contas — esta linha entra na conta
    select count(*) into v_concorrentes
      from public.finance_review_queue q2
      join public.bank_transactions t2 on t2.id = q2.bank_transaction_id
     where q2.status = 'pending' and q2.kind = 'create_payable'
       and t2.transaction_type = 'debit' and t2.payment_method = 'BOLETO'
       and t2.reconciled is not true and t2.dismissed_kind is null
       and abs(t2.amount - l.amount) < 0.01
       and lpad(regexp_replace(coalesce(t2.counterparty_bank, ''), '\D', '', 'g'), 3, '0') = l.banco
       and t2.transaction_date between v_min - 45 and v_max + 30;

    if v_fornecedores > 1 or v_empatadas > 1 or v_concorrentes > v_contas then
      v_ambiguas := v_ambiguas + 1;
      continue;
    end if;

    begin
      perform public.conciliar_lancamento('payable', c.id, l.id, null);
      update public.finance_review_queue
         set status = 'approved', automatica = 'boleto', decided_by = null, decided_at = now(),
             decision_note = left('Baixada sozinha pelo boleto: ' || c.nome || ', vencimento ' || to_char(c.due_date, 'DD/MM/YYYY')
                                  || ' — mesmo valor e mesmo banco do boleto', 300)
       where id = l.fila_id;
      update public.reconciliation_log
         set detalhe = left('Baixa automática pelo boleto · ' || coalesce(detalhe, ''), 300)
       where bank_transaction_id = l.id and payable_id = c.id and acao = 'conciliou'
         and coalesce(detalhe, '') not like 'Baixa automática pelo boleto%';
      v_baixadas := v_baixadas + 1;
      v_itens := v_itens || jsonb_build_object(
        'transacao', l.id, 'conta', c.id, 'fornecedor', c.nome, 'valor', l.amount,
        'vencimento', c.due_date, 'pago_em', l.transaction_date);
    exception when others then
      v_barradas := v_barradas + 1;
      v_erros := v_erros || left(sqlstate || ': ' || sqlerrm, 200);
    end;
  end loop;

  return jsonb_build_object(
    'baixadas', v_baixadas, 'ambiguas', v_ambiguas, 'barradas', v_barradas,
    'erros', to_jsonb(v_erros), 'itens', v_itens);
end;
$$;

revoke all on function public.baixar_pelo_boleto(uuid[], date) from public;
revoke all on function public.baixar_pelo_boleto(uuid[], date) from anon;
revoke all on function public.baixar_pelo_boleto(uuid[], date) from authenticated;
grant execute on function public.baixar_pelo_boleto(uuid[], date) to service_role;

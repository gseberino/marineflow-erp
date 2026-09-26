-- Decisões do dono de 26/09/2026 (respostas às 20 perguntas do "Financeiro no Lugar").
--
-- Tudo por id explícito ou critério estreito, com guarda pelo valor antigo (rodar duas vezes
-- não muda nada) e trilha em reconciliation_log.

-- ── 0. Histórico: a 20260926200000 foi aplicada sem o registro de migration ──
insert into supabase_migrations.schema_migrations (version, name)
values ('20260926200000', 'debito_de_cartao_nao_e_fatura')
on conflict do nothing;

-- ── 1. Cancelar um lançamento do Caixa estorna a linha do Caixa ──
-- Resposta 2 ("o almoço foi teste"): cancelar o almoço mostrou um furo. O lançamento do Caixa
-- não nasce da fila do Extrato, então a linha dele voltava para a fila (viraria proposta de
-- despesa) e continuava contando no saldo do Caixa. Agora a linha do Caixa é marcada
-- 'estornada': sai do saldo, não volta para a fila e fica visível com o motivo.
create or replace function public.cancelar_lancamento(p_tipo text, p_id uuid, p_motivo text, p_autor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_antes jsonb;
  v_tx uuid;
  v_nasceu boolean;
  v_caixa boolean;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_nota text;
  v_destino text := null;
begin
  if p_tipo not in ('payable', 'receivable') then
    raise exception 'Tipo de lançamento inválido: % (use payable ou receivable).', p_tipo;
  end if;
  if v_motivo is null or length(v_motivo) < 3 then
    raise exception 'Diga por que o lançamento está sendo cancelado.';
  end if;

  if p_tipo = 'payable' then
    select to_jsonb(p) into v_antes from public.payables p where p.id = p_id for update;
  else
    select to_jsonb(r) into v_antes from public.receivables r where r.id = p_id for update;
  end if;
  if v_antes is null then raise exception 'Lançamento não encontrado.'; end if;
  if v_antes ->> 'status' = 'cancelled' then raise exception 'Este lançamento já está cancelado.'; end if;
  perform public._recusa_se_mes_fechado((v_antes ->> 'issue_date')::date, 'cancelar este lançamento');

  v_tx := (v_antes ->> 'bank_transaction_id')::uuid;
  v_nasceu := v_tx is not null and public._nasceu_do_extrato(p_tipo, p_id);
  v_caixa := v_tx is not null and exists (
    select 1 from public.bank_transactions t
     where t.id = v_tx and (t.bank_ref_id like 'caixa:%' or t.source_type = 'cash'));
  v_nota := '[' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || '] Cancelado: ' || v_motivo;

  update public.payments
     set status = 'cancelled', cancelled_at = now(), cancellation_reason = left('Lançamento cancelado: ' || v_motivo, 200)
   where status = 'confirmed'
     and ((p_tipo = 'payable' and payable_id = p_id) or (p_tipo = 'receivable' and receivable_id = p_id));

  if p_tipo = 'payable' then
    update public.payables set status = 'cancelled', bank_transaction_id = null,
           notes = btrim(coalesce(notes, '') || ' ' || v_nota) where id = p_id;
    update public.finance_review_queue set status = 'superseded', decision_note = v_nota
     where created_payable_id = p_id;
  else
    update public.receivables set status = 'cancelled', bank_transaction_id = null,
           notes = btrim(coalesce(notes, '') || ' ' || v_nota) where id = p_id;
    update public.finance_review_queue set status = 'superseded', decision_note = v_nota
     where created_receivable_id = p_id;
  end if;

  if v_tx is not null then
    if v_caixa then
      -- Linha do Caixa: quem a criou foi o lançamento; cancelado ele, o dinheiro não saiu (ou
      -- não entrou). Sai do saldo e não vai para a fila do Extrato.
      update public.bank_transactions set
        reconciled = true, reconciled_payment_id = null,
        dismissed_kind = 'estornada',
        dismissed_reason = left('Lançamento do Caixa cancelado: ' || v_motivo, 300),
        dismissed_at = now(),
        dismissed_by = v_autor
      where id = v_tx;
      v_destino := 'caixa_estornado';
    elsif v_nasceu then
      update public.bank_transactions set
        reconciled = true, reconciled_payment_id = null,
        dismissed_kind = 'manual',
        dismissed_reason = left('Lançamento cancelado: ' || v_motivo, 300),
        dismissed_at = now(),
        dismissed_by = v_autor
      where id = v_tx;
      v_destino := 'fora_da_fila';
    else
      update public.bank_transactions set reconciled = false, reconciled_payment_id = null where id = v_tx;
      v_destino := 'fila';
    end if;
  end if;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, receivable_id, valor, detalhe, antes, depois)
  values (
    'cancelou_lancamento', v_autor, v_tx,
    case when p_tipo = 'payable' then p_id end,
    case when p_tipo = 'receivable' then p_id end,
    (v_antes ->> 'amount')::numeric,
    left(v_motivo || ' · ' || coalesce(v_antes ->> 'description', ''), 300),
    jsonb_build_object('status', v_antes ->> 'status', 'bank_transaction_id', v_tx, 'paid_amount', v_antes -> 'paid_amount'),
    jsonb_build_object('status', 'cancelled', 'linha_do_extrato', v_destino)
  );

  return jsonb_build_object(
    'ok', true,
    'linha_do_extrato', v_destino,
    'message', 'Lançamento cancelado.'
      || case v_destino
           when 'caixa_estornado' then ' O Caixa deixou de contar este valor.'
           when 'fora_da_fila' then ' A linha do extrato foi para "Fora da fila" com o mesmo motivo; de lá ela pode voltar.'
           when 'fila' then ' A linha do extrato voltou para a fila.'
           else '' end
  );
end;
$$;
revoke all on function public.cancelar_lancamento(text, uuid, text, uuid) from public, anon;
grant execute on function public.cancelar_lancamento(text, uuid, text, uuid) to authenticated, service_role;

-- O saldo do Caixa e o extrato com saldo deixam de contar a linha estornada.
create or replace function public.saldo_do_caixa()
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select round(coalesce(c.saldo_base, 0) + coalesce(sum(case when t.transaction_type = 'credit' then t.amount else -t.amount end), 0), 2)
    from public.bank_connections c
    left join public.bank_transactions t
      on t.bank_connection_id = c.id and coalesce(t.tx_status, '') <> 'PENDING'
     and coalesce(t.dismissed_kind, '') not in ('duplicata', 'estornada')
   where c.id = public._conta_caixa()
   group by c.saldo_base;
$$;
revoke all on function public.saldo_do_caixa() from public, anon, authenticated;
grant execute on function public.saldo_do_caixa() to service_role;

create or replace function public.extrato_da_conta(p_conexao uuid, p_de date, p_ate date)
returns table(id uuid, data date, descricao text, contraparte text, documento text, tipo text, valor numeric, saldo_apos numeric, situacao text, pendente boolean, lancamento_tipo text, lancamento_id uuid, lancamento_descricao text, categoria text, quem text, tipo_fora text, motivo_fora text, proposta_id uuid)
language sql
stable
set search_path = public
as $$
  with base as (
    select c.saldo_base from public.bank_connections c where c.id = p_conexao
  ),
  mov as (
    select t.*,
           (coalesce(t.tx_status, '') <> 'PENDING' and coalesce(t.dismissed_kind, '') not in ('duplicata', 'estornada')) as conta_no_saldo,
           case when t.transaction_type = 'credit' then t.amount else -t.amount end as com_sinal
      from public.bank_transactions_situacao t
     where t.bank_connection_id = p_conexao
       and coalesce(t.source_type, 'bank') in ('bank', 'cash')
  ),
  acumulado as (
    select m.*,
           sum(case when m.conta_no_saldo then m.com_sinal else 0 end)
             over (order by m.transaction_date, m.created_at, m.id rows unbounded preceding) as soma_ate_aqui
      from mov m
  )
  select a.id, a.transaction_date, a.description,
         coalesce(a.counterparty_name, a.merchant_name), a.counterparty_document, a.transaction_type,
         a.com_sinal,
         case when (select saldo_base from base) is null then null
              else round((select saldo_base from base) + a.soma_ate_aqui, 2) end,
         a.situacao, coalesce(a.tx_status, '') = 'PENDING',
         case when p.id is not null then 'payable' when r.id is not null then 'receivable' end,
         coalesce(p.id, r.id),
         coalesce(p.description, r.description),
         coalesce(p.expense_category, r.category),
         coalesce(s.name, pe.name, cl.name, p.supplier_name),
         a.dismissed_kind, a.dismissed_reason,
         q.id
    from acumulado a
    left join public.payables p on p.bank_transaction_id = a.id and p.status <> 'cancelled'
    left join public.receivables r on r.bank_transaction_id = a.id and r.status <> 'cancelled'
    left join public.suppliers s on s.id = p.supplier_id
    left join public.payees pe on pe.id = p.payee_id
    left join public.clients cl on cl.id = r.client_id
    left join lateral (
      select fq.id from public.finance_review_queue fq
       where fq.bank_transaction_id = a.id and fq.status = 'pending'
       order by fq.created_at desc limit 1
    ) q on true
   where a.transaction_date between p_de and p_ate
   order by a.transaction_date desc, a.created_at desc, a.id desc;
$$;

-- ── 2. Lançar sozinho só com 90% ou mais (resposta 14) ──
update public.app_settings set value = '90'
 where key = 'finance_auto_approve_min_confidence' and value is distinct from '90';

-- ── 3. Regras (resposta 7): "rest" vira "RESTAURANTE"; COREMMA é Ferramentas ──
update public.finance_rules set match_value = 'RESTAURANTE'
 where id = 'a2cb9773-c3c2-4a63-835b-cf4bae2369c7' and match_value = 'rest';
update public.finance_rules set set_category = 'Ferramentas e equipamentos', set_dre_group = 'despesa_operacional'
 where id = 'd40d319d-e341-4fbc-9d19-c591e19d2f6a' and set_category = 'Peças e materiais';

-- ── 4. Hospedagem é custo do serviço (resposta 8), não juros e tarifas ──
update public.financial_categories set dre_group = 'custo_direto'
 where id = '924167ca-7f4a-4fb4-b9e6-b66c4c305511' and dre_group = 'financeiro';

-- ── 5. Cobrança de teste cancelada (resposta 10) ──
-- As outras duas de teste já estavam canceladas; a real (João Luiz Hang, OS-00051) continua.
update public.collections set status = 'cancelled', auto_rule_enabled = false,
       notes = btrim(coalesce(notes, '') || ' [26/09/2026] Cancelada: cobrança de teste no nome do dono.')
 where id = 'fd446b9d-4463-4a5f-8181-38106520f060' and status <> 'cancelled';

-- ── 6. Pró-labore separado da retirada de lucro (resposta 9) ──
-- A categoria "Pró-labore e retirada" misturava despesa (pró-labore) com retirada de lucro, que
-- não é despesa. Daqui para frente: "Pró-labore" (despesa, no DRE) e "Retirada de sócio" (fora do
-- resultado, que já existia). Os lançamentos antigos passam a se chamar "Pró-labore" — o total do
-- DRE não muda — e a contadora diz quais eram retirada. A marca de categoria restrita fica na
-- linha da categoria e acompanha a troca de nome.
update public.financial_categories
   set name = 'Pró-labore',
       description = 'Remuneração dos sócios pelo trabalho (despesa). Retirada de lucro vai em "Retirada de sócio", fora do resultado.'
 where id = '8464cad3-7bd9-4e22-939f-699170b42578' and name = 'Pró-labore e retirada';
update public.payables set expense_category = 'Pró-labore' where expense_category = 'Pró-labore e retirada';
update public.finance_rules set set_category = 'Pró-labore' where set_category = 'Pró-labore e retirada';
update public.payees set default_category = 'Pró-labore' where default_category = 'Pró-labore e retirada';
update public.finance_review_queue set suggested_category = 'Pró-labore' where suggested_category = 'Pró-labore e retirada';
update public.anotacoes_do_extrato set categoria = 'Pró-labore' where categoria = 'Pró-labore e retirada';
update public.service_order_expenses set category = 'Pró-labore' where category = 'Pró-labore e retirada';


-- Fechamento de folha: sócio vai para "Pró-labore"; CLT, para "Salários e encargos".
create or replace function public.gravar_fechamento_de_folha(p_de date, p_ate date, p_descricao text, p_linhas jsonb, p_ator uuid DEFAULT NULL::uuid, p_vencimento date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ator        uuid;
  v_periodo_id  uuid;
  v_linha       jsonb;
  v_payable_id  uuid;
  v_perfil      record;
  v_categoria   text;
  v_nome        text;
  v_bruto       numeric;
  v_liquido     numeric;
  v_retencoes   numeric;
  v_turnos      uuid[];
  v_venc        date := coalesce(p_vencimento, p_ate + 5);
  v_geradas     int := 0;
  v_puladas     int := 0;
  v_total       numeric := 0;
  v_resultado   jsonb := '[]'::jsonb;
begin
  -- Quem está autenticado MANDA; `p_ator` só vale quando não há sessão — que é o caso do canal
  -- WhatsApp, onde a Edge Function roda com service-role e `auth.uid()` é nulo. Assim um usuário
  -- comum não escapa do próprio uid passando o UUID de um admin, e o canal continua funcionando.
  v_ator := coalesce(auth.uid(), p_ator);
  if not public.pode_ver_folha(v_ator) then
    raise exception 'Sem permissão para fechar folha.' using errcode = '42501';
  end if;

  if p_ate < p_de then
    raise exception 'Período inválido: fim (%) anterior ao início (%).', p_ate, p_de using errcode = '22007';
  end if;

  if jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) = 0 then
    raise exception 'Nada a fechar: nenhuma linha apurada no período.' using errcode = '22023';
  end if;

  insert into public.payroll_periods (de, ate, descricao, status, fechado_por, fechado_em)
  values (p_de, p_ate, p_descricao, 'fechado', v_ator, now())
  returning id into v_periodo_id;

  for v_linha in select * from jsonb_array_elements(p_linhas)
  loop
    v_bruto     := coalesce((v_linha->>'valor_bruto')::numeric, 0);
    v_retencoes := coalesce((v_linha->>'retencoes')::numeric, 0);
    v_liquido   := round(v_bruto - v_retencoes, 2);

    select wp.payee_id, wp.app_user_id, wp.tipo_vinculo
      into v_perfil
      from public.work_profiles wp
     where wp.id = (v_linha->>'work_profile_id')::uuid;
    if not found then
      raise exception 'Perfil de pagamento % não existe.', v_linha->>'work_profile_id' using errcode = '23503';
    end if;

    v_nome := coalesce(
      v_linha->>'nome',
      (select p.name from public.payees   p where p.id = v_perfil.payee_id),
      (select u.full_name from public.app_users u where u.id = v_perfil.app_user_id),
      'equipe');

    -- Categoria vem do VÍNCULO, não de texto livre: é o que mantém o DRE legível depois. Todas já
    -- existem no histórico de `payables` — nenhuma categoria nova é inventada aqui.
    v_categoria := case v_perfil.tipo_vinculo
                     when 'socio' then 'Pró-labore'
                     -- CLT é salário, não pró-labore (separação de 26/09/2026).
                     when 'clt'   then 'Salários e encargos'
                     else 'Serviços de terceiros'
                   end;

    -- Linha zerada não vira conta a pagar de R$ 0,00 para alguém conferir depois.
    if v_liquido <= 0 then
      v_puladas := v_puladas + 1;
      continue;
    end if;

    insert into public.payables (
      description, issue_date, due_date, amount, balance_amount, status,
      expense_category, origin, payee_id, supplier_name, notes
    ) values (
      format('Folha %s a %s — %s', to_char(p_de,'DD/MM'), to_char(p_ate,'DD/MM/YYYY'), v_nome),
      current_date, v_venc, v_liquido, v_liquido, 'pending',
      v_categoria, 'folha', v_perfil.payee_id, v_nome,
      format('Fechamento de folha. Bruto R$ %s, retenções R$ %s. Memória de cálculo na linha da folha.',
             to_char(v_bruto,'FM999G999D00'), to_char(v_retencoes,'FM999G999D00'))
    ) returning id into v_payable_id;

    insert into public.payroll_lines (
      payroll_period_id, work_profile_id,
      horas_normais, horas_extras, horas_noturnas, horas_domingo,
      diarias_inteiras, diarias_meias,
      valor_normais, valor_extras, valor_noturnas, valor_domingo,
      valor_diarias, valor_mensal, valor_comissoes, valor_dsr,
      descontos, valor_bruto, retencoes, valor_liquido,
      nfse_numero, nfse_valor, detalhamento, payable_id, observacao
    ) values (
      v_periodo_id, (v_linha->>'work_profile_id')::uuid,
      coalesce((v_linha->>'horas_normais')::numeric, 0),   coalesce((v_linha->>'horas_extras')::numeric, 0),
      coalesce((v_linha->>'horas_noturnas')::numeric, 0),  coalesce((v_linha->>'horas_domingo')::numeric, 0),
      coalesce((v_linha->>'diarias_inteiras')::numeric, 0),coalesce((v_linha->>'diarias_meias')::numeric, 0),
      coalesce((v_linha->>'valor_normais')::numeric, 0),   coalesce((v_linha->>'valor_extras')::numeric, 0),
      coalesce((v_linha->>'valor_noturnas')::numeric, 0),  coalesce((v_linha->>'valor_domingo')::numeric, 0),
      coalesce((v_linha->>'valor_diarias')::numeric, 0),   coalesce((v_linha->>'valor_mensal')::numeric, 0),
      coalesce((v_linha->>'valor_comissoes')::numeric, 0), coalesce((v_linha->>'valor_dsr')::numeric, 0),
      coalesce((v_linha->>'descontos')::numeric, 0),       v_bruto, v_retencoes, v_liquido,
      v_linha->>'nfse_numero', (v_linha->>'nfse_valor')::numeric,
      v_linha->'detalhamento', v_payable_id, v_linha->>'observacao'
    );

    -- Turnos viram 'pago' — é o que impede o mesmo dia de entrar num segundo fechamento. Só sobem
    -- os que a linha declarou e que estavam aprovados: turno de outra pessoa não é tocado, e turno
    -- em rascunho não é pago sem alguém ter aprovado.
    v_turnos := coalesce(
      (select array_agg(t.x::uuid)
         from jsonb_array_elements_text(coalesce(v_linha->'turno_ids','[]'::jsonb)) as t(x)),
      '{}'::uuid[]);
    if array_length(v_turnos, 1) is not null then
      update public.work_shifts
         set status = 'pago', updated_at = now()
       where id = any(v_turnos) and status = 'aprovado';
    end if;

    v_geradas := v_geradas + 1;
    v_total   := v_total + v_liquido;
    v_resultado := v_resultado || jsonb_build_object(
      'nome', v_nome, 'liquido', v_liquido, 'categoria', v_categoria, 'payable_id', v_payable_id);
  end loop;

  if v_geradas = 0 then
    raise exception 'Nenhuma linha com valor a pagar no período — nada foi fechado.' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'periodo_id', v_periodo_id,
    'de', p_de, 'ate', p_ate,
    'vencimento', v_venc,
    'pessoas', v_geradas,
    'linhas_zeradas_puladas', v_puladas,
    'total_liquido', v_total,
    'linhas', v_resultado
  );
end;
$function$;
revoke all on function public.gravar_fechamento_de_folha(date, date, text, jsonb, uuid, date) from public, anon;
grant execute on function public.gravar_fechamento_de_folha(date, date, text, jsonb, uuid, date) to authenticated, service_role;

-- Trilha das decisões aplicadas aqui (o que mudou e por quê, num lugar consultável).
insert into public.reconciliation_log (acao, autor, detalhe, depois)
select 'decisao_do_dono', null, left(d.detalhe, 300), d.depois
  from (values
    ('Lançar sozinho só com confiança de 90% ou mais', jsonb_build_object('finance_auto_approve_min_confidence', '90')),
    ('Regra "rest" passa a ser "RESTAURANTE" (pegava PRESTAÇÃO)', jsonb_build_object('regra', 'a2cb9773')),
    ('Regra COREMMA passa a Ferramentas e equipamentos', jsonb_build_object('regra', 'd40d319d')),
    ('Hospedagem e Hotelaria passa a custo do serviço', jsonb_build_object('dre_group', 'custo_direto')),
    ('"Pró-labore e retirada" vira "Pró-labore"; retirada de lucro vai em "Retirada de sócio"', jsonb_build_object('categoria', 'Pró-labore')),
    ('Busca do banco às 06h e às 15h; análise do Extrato 10 min depois de cada busca', jsonb_build_object('banking-sync', '0 9,18 * * *', 'finance-review-generate', '10 9,18 * * *'))
  ) as d(detalhe, depois)
 where not exists (select 1 from public.reconciliation_log l where l.acao = 'decisao_do_dono' and l.detalhe = left(d.detalhe, 300));

-- ── 7. Rotinas (resposta 16): a segunda busca do banco passa das 18h para as 15h, para o que
-- chega à tarde ser visto no mesmo dia; a análise do Extrato roda 10 min depois de CADA busca
-- (às 6h ela rodava no mesmo minuto da busca e só pegava o que chegara na véspera).
select cron.alter_job(18, schedule := '0 9,18 * * *') where exists (select 1 from cron.job where jobid = 18 and jobname = 'banking-sync-daily');
select cron.alter_job(25, schedule := '10 9,18 * * *') where exists (select 1 from cron.job where jobid = 25 and jobname = 'finance-review-generate');

insert into supabase_migrations.schema_migrations (version, name)
values ('20260926210000', 'decisoes_do_dono')
on conflict do nothing;

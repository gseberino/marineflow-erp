-- Fase 4 da Jornada: fechar o período deixa de ser um relatório e vira dinheiro a pagar.
--
-- Até aqui `apurar_pagamento` calculava e mandava "use a tela de Folha" — uma tela que não existe.
-- Cálculo certo que não vira conta a pagar não paga ninguém: alguém relê o número e digita à mão no
-- financeiro, que é exatamente onde o valor diverge da apuração.
--
-- ONDE MORA A REGRA DE CÁLCULO: em `_shared/payroll/calculo.ts` (TypeScript, 17 testes), e continua
-- lá. Esta função NÃO recalcula nada — recebe as linhas já apuradas e cuida só do que precisa ser
-- ATÔMICO: criar o período, gravar as linhas, gerar um `payable` por pessoa e marcar os turnos como
-- pagos. Reimplementar a CLT em PL/pgSQL criaria duas verdades, que divergem no primeiro feriado.

-- ── 1. `folha` passa a ser origem legítima de conta a pagar ─────────────────────────────────────
-- `chk_payables_origin` é lista fechada: sem isto, todo insert de folha falha com 23514. É a mesma
-- armadilha do CHECK de `agenda_tasks` — valor novo sobe sem efeito e o erro morre num catch.
alter table public.payables drop constraint if exists chk_payables_origin;
alter table public.payables add constraint chk_payables_origin
  check (origin = any (array['manual','service_order_expense','bank_reconciliation','fiscal_note',
                             'commission','purchase_order','folha']));

-- ── 2. Um período por intervalo ─────────────────────────────────────────────────────────────────
-- Fechar o mesmo intervalo duas vezes é o erro provável (a conversa cai, o dono repete o comando) e
-- pagaria a equipe duas vezes. O índice impede no banco, não na boa vontade de quem chama.
-- Sem WHERE parcial de propósito: `payroll_periods_status_check` só admite aberto/fechado/pago —
-- não existe status cancelado para excluir, e um predicado sempre-verdadeiro só enganaria a leitura.
create unique index if not exists payroll_periods_intervalo_unico
  on public.payroll_periods (de, ate);

comment on column public.payroll_lines.payable_id is
  'Conta a pagar gerada por este fechamento. Preenchida por gravar_fechamento_de_folha; e o caminho de volta (payable -> quem trabalhou, quando, quantas horas) de que a Fase 5 precisa para o custo real por OS.';

-- ── 3. O fechamento ─────────────────────────────────────────────────────────────────────────────
create or replace function public.gravar_fechamento_de_folha(
  p_de          date,
  p_ate         date,
  p_descricao   text,
  p_linhas      jsonb,          -- [{work_profile_id, nome, valor_bruto, ..., detalhamento, turno_ids:[]}]
  p_ator        uuid default null,
  p_vencimento  date default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
                     when 'socio' then 'Pró-labore e retirada'
                     when 'clt'   then 'Pró-labore e retirada'
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
$$;

comment on function public.gravar_fechamento_de_folha(date, date, text, jsonb, uuid, date) is
  'Fecha um periodo de folha de forma atomica: cria o periodo, grava as linhas ja apuradas, gera uma conta a pagar por pessoa (origin=folha, ligada ao payee, categoria pelo tipo de vinculo) e marca os turnos aprovados como pagos. NAO calcula nada: a regra vive em _shared/payroll/calculo.ts e as linhas chegam prontas. Exige pode_ver_folha() do usuario autenticado, ou de p_ator quando nao ha sessao (canal WhatsApp).';

-- Function nova nasce com EXECUTE para public por ALTER DEFAULT PRIVILEGES — revogar de anon pelo
-- nome é o que de fato fecha a porta.
revoke all on function public.gravar_fechamento_de_folha(date, date, text, jsonb, uuid, date) from public, anon;
grant execute on function public.gravar_fechamento_de_folha(date, date, text, jsonb, uuid, date) to authenticated, service_role;

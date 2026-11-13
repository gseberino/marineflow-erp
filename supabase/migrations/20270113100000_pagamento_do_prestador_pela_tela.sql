-- Pagamento ao prestador por serviço pela TELA (13/11/2026).
--
-- O "Registrar pagamento" da aba Diárias chama registrar_pagamento_do_freelancer, que só aceitava quem tem
-- perfil de diária: para o Alex (prestador com CNPJ e conta corrente desde 23/10, migration
-- 20270105102000_servicos_do_prestador) o banco recusava com "Freelancer de diária não encontrado". O
-- assistente já lançava o pagamento dele em "Serviços de terceiros" (anotar_transacao / lancar_no_caixa).
--
-- Agora a função aceita também o prestador ou comissionado COM conta corrente (o mesmo critério do
-- resumo_freelancers e do assistente) e lança na categoria dele, "Serviços de terceiros" — a que o
-- _abate_diarias desconta do saldo. A descrição padrão vira "Pagamento de serviços — <nome>".
--
-- Para o diarista NADA muda: mesmas rotas, mesma categoria, mesmas mensagens. A divisão com reembolso de
-- comprovante continua só do diarista (as partes de _diarias_partes são "Diárias de freelancers"): para o
-- prestador o banco recusa e diz o que fazer.
--
-- Desfazer: reaplicar a definição de 20261011301000_diarias_reembolsos.sql (a de produção até 13/11/2026).

CREATE OR REPLACE FUNCTION public.registrar_pagamento_do_freelancer(p_favorecido_id uuid, p_valor numeric, p_data date, p_forma text, p_socio_id uuid, p_reembolsos uuid[], p_descricao text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_fav record;
  v_ids uuid[] := coalesce((select array_agg(distinct x) from unnest(p_reembolsos) x where x is not null), '{}'::uuid[]);
  v_div jsonb;
  v_desc text;
  v_r jsonb;
  v_d jsonb;
  v_divisao uuid;
  v_anot uuid;
  v_pay uuid;
  v_primeiro uuid;
  v_lancs uuid[] := '{}';
  v_parte jsonb;
  v_msg text;
  v_diarista boolean;
  v_prestador boolean;
  v_cat text;
begin
  if v_autor is null then
    raise exception 'Diga quem está registrando o pagamento.' using errcode = '42501';
  end if;
  select p.id, p.name, p.active, p.kind, p.conta_corrente_desde into v_fav from public.payees p where p.id = p_favorecido_id;
  v_diarista := exists (select 1 from public.work_profiles wp where wp.payee_id = p_favorecido_id and wp.modo_pagamento = 'diaria');
  -- o prestador por serviço (o Alex): sem perfil de diária, com conta corrente (13/11/2026)
  v_prestador := not v_diarista and v_fav.kind in ('prestador', 'comissionado') and v_fav.conta_corrente_desde is not null;
  if v_fav.id is null or not coalesce(v_fav.active, false) or not (v_diarista or coalesce(v_prestador, false)) then
    raise exception 'Freelancer de diária não encontrado (ou desativado).' using errcode = '22023';
  end if;
  v_cat := case when v_prestador then 'Serviços de terceiros' else 'Diárias de freelancers' end;
  if p_forma is null or p_forma not in ('pix', 'dinheiro', 'socio') then
    raise exception 'Como foi pago: pix, dinheiro ou socio.' using errcode = '22023';
  end if;
  -- a data não dita: o Pix vai sem ela (anotar_transacao anota com a janela larga, D-3..D+7 — "paguei o
  -- Roberto" sem dizer quando pode ser o Pix de anteontem); dinheiro e bolso do sócio, hoje (o padrão do
  -- lancar_no_caixa)
  if p_data > (now() at time zone 'America/Sao_Paulo')::date then
    raise exception 'Pagamento no futuro não se lança: lance quando pagar.' using errcode = '22023';
  end if;
  if p_forma = 'socio' and (p_socio_id is null
                            or not exists (select 1 from public.payees s where s.id = p_socio_id and s.kind = 'socio')) then
    raise exception 'Diga qual sócio pagou, para o reembolso ficar no nome dele.' using errcode = '22023';
  end if;
  if v_prestador and cardinality(v_ids) > 0 then
    raise exception 'Reembolso de comprovante só se divide no pagamento de diarista. Registre o pagamento de % sem marcar reembolso e lance a despesa à parte.',
      split_part(btrim(v_fav.name), ' ', 1) using errcode = '22023';
  end if;
  v_div := public._diarias_partes(p_favorecido_id, p_valor, v_ids, null);
  v_desc := left(coalesce(nullif(btrim(coalesce(p_descricao, '')), ''),
                          case when v_prestador then 'Pagamento de serviços — ' else 'Pagamento de diárias — ' end
                          || split_part(btrim(v_fav.name), ' ', 1)), 200);

  if p_forma = 'pix' then
    v_r := public.anotar_transacao('saida', p_valor, p_data, null, null, null, p_favorecido_id, null,
                                   v_cat, null, v_desc, v_autor);
    if not coalesce((v_r->>'ok')::boolean, false) then
      -- a rota não anotou (linha já lançada, ambígua…): nada de divisão; a mensagem dela diz o que fazer
      return jsonb_build_object('ok', false, 'forma', p_forma, 'anotacao_id', null, 'payable_id', v_r->'lancamento_id',
        'divisao', public._diarias_divisao_saida(null, 'nenhuma', public._diarias_partes(p_favorecido_id, p_valor, '{}', null)),
        'message', coalesce(v_r->>'message', 'O Pix não foi anotado.')
                   || case when cardinality(v_ids) > 0 and coalesce((v_r->>'ja_lancada')::boolean, false)
                           then ' Para separar o reembolso, use "Dividir" na linha desse pagamento nas Diárias.' else '' end);
    end if;
    v_anot := (v_r->>'id')::uuid;
    if cardinality(v_ids) > 0 then
      insert into public.diarias_pagamentos_divididos (favorecido_id, anotacao_id, reembolsos, partes, status, criado_por)
      values (p_favorecido_id, v_anot, v_ids, v_div->'partes', 'pendente', v_autor)
      returning id into v_divisao;
    end if;
    v_msg := coalesce(v_r->>'message', 'Pix anotado.')
             || case when v_divisao is not null
                     then ' Divido quando a linha do banco for aprovada: Diárias ' || public._brl((v_div->>'diarias')::numeric)
                          || ' · Reembolso de despesas pagas pelo técnico ' || public._brl((v_div->>'reembolsos')::numeric) || '.'
                     else '' end;
    -- o que a anotação diz além do ok (a tela avisa por 15 s quando trocou uma anotação igual: o caso do
    -- dono de 06/10/2026, "dois R$ 100 ao Roberto", um sumiu)
    return jsonb_build_object('ok', true, 'forma', p_forma, 'anotacao_id', v_anot, 'payable_id', null,
      'divisao', public._diarias_divisao_saida(v_divisao, case when v_divisao is null then 'nenhuma' else 'pendente' end, v_div),
      'message', v_msg,
      'substituidas', coalesce((v_r->>'substituidas')::integer, 0),
      'falta_quem', coalesce((v_r->>'falta_quem')::boolean, false),
      'outra_contraparte', v_r->'outra_contraparte');

  elsif p_forma = 'dinheiro' then
    v_r := public.lancar_no_caixa('saida', p_valor, v_desc, p_data, v_cat, null, p_favorecido_id, null,
                                  null, 'caixa', null, v_autor);
    v_pay := (v_r->>'lancamento_id')::uuid;
    if cardinality(v_ids) > 0 then
      v_d := public._diarias_dividir(v_pay, v_ids, v_autor, null);
    end if;
    return jsonb_build_object('ok', true, 'forma', p_forma, 'anotacao_id', null, 'payable_id', v_pay,
      'divisao', coalesce(v_d->'divisao', public._diarias_divisao_saida(null, 'nenhuma', v_div)),
      'message', coalesce(v_r->>'message', 'Lançado no Caixa.')
                 || case when v_d is not null
                         then ' Dividido: Diárias ' || public._brl((v_div->>'diarias')::numeric)
                              || ' · Reembolso de despesas pagas pelo técnico ' || public._brl((v_div->>'reembolsos')::numeric) || '.'
                         else '' end);
  end if;

  -- bolso do sócio: uma conta ao sócio por parte (o técnico de beneficiário). A divisão guarda as contas
  -- das partes de REEMBOLSO (vale enquanto todas valem): cancelar a do reembolso devolve os reembolsos ao
  -- "em aberto". Sem linha do banco não há "Desfazer a divisão" pela tela: cancelam-se as contas.
  for v_parte in select e from jsonb_array_elements(v_div->'partes') with ordinality as t(e, o) order by o loop
    v_r := public.lancar_no_caixa('saida', (v_parte->>'valor')::numeric,
                                  case when v_parte->>'categoria' = 'Diárias de freelancers' and jsonb_array_length(v_parte->'codigos') = 0
                                       then v_desc
                                       else left(public._diarias_rotulo_do_reembolso(v_parte->'codigos') || ' · ' || v_fav.name, 200) end,
                                  p_data,
                                  case when v_parte->>'categoria' = 'Diárias de freelancers' then v_cat else v_parte->>'categoria' end,
                                  null, p_favorecido_id, null, null, 'socio', p_socio_id, v_autor);
    v_primeiro := coalesce(v_primeiro, (v_r->>'lancamento_id')::uuid);
    if jsonb_array_length(coalesce(v_parte->'codigos', '[]'::jsonb)) > 0 or v_parte->>'categoria' <> 'Diárias de freelancers' then
      v_lancs := v_lancs || (v_r->>'lancamento_id')::uuid;
    end if;
  end loop;
  if cardinality(v_ids) > 0 then
    insert into public.diarias_pagamentos_divididos (favorecido_id, payable_id, reembolsos, partes, status, criado_por, aplicada_em,
                                                     lancamentos)
    values (p_favorecido_id, v_primeiro, v_ids, v_div->'partes', 'aplicada', v_autor, now(), v_lancs)
    returning id into v_divisao;
  end if;
  return jsonb_build_object('ok', true, 'forma', p_forma, 'anotacao_id', null, 'payable_id', v_primeiro,
    'divisao', public._diarias_divisao_saida(v_divisao, case when v_divisao is null then 'nenhuma' else 'aplicada' end, v_div),
    'message', case when v_divisao is null then 'Lançado como reembolso a pagar ao sócio.'
                    else 'Lançado como reembolso a pagar ao sócio, em ' || jsonb_array_length(v_div->'partes')
                         || ' contas: Diárias ' || public._brl((v_div->>'diarias')::numeric)
                         || ' · Reembolso de despesas pagas pelo técnico ' || public._brl((v_div->>'reembolsos')::numeric) || '.' end);
end $function$;

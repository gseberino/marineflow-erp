-- Diárias: o recibo sai do Pix que zera a conta — 27/10/2026 (fase 2 da revisão de 24/10).
--
-- Antes o acerto fechava ANTES de pagar ("a pagar R$ X") e o recibo dizia "recebi" um valor que
-- ainda não tinha sido pago; dias e pagamentos eram cortados na mesma data. Proposta aprovada pelo
-- dono (24/10): um papel só, "Recibo de pagamento de serviços nº N", no Pix que zera a conta.
--
--   * fechar_acerto_diarias ganha p_pix_id (o Pix de quitação: um lançamento, não anotação nem linha
--     da fila) e p_de (início do PRIMEIRO recibo; os seguintes começam no dia seguinte ao anterior).
--     Dias e reembolsos vão de "de" até "ate" (último dia de serviço; padrão: o dia do Pix); os
--     pagamentos, do dia seguinte ao Pix do recibo anterior até o Pix deste. Sem p_pix_id, escolhe o
--     último Pix que zera a conta. Com p_simular devolve a prévia, os Pix candidatos e as travas.
--   * Trava (não fecha, diz o porquê, todas de uma vez): sem CPF; empresa sem razão social/CNPJ;
--     pagamento do período ainda anotado à mão ou na fila (aprovar antes); pagamento sem categoria;
--     adicional ou desconto sem motivo; pendência do assistente esperando "sim" para ele; conta que
--     não zera (falta pagar, ou pago adiantado: adiantado não gera recibo).
--   * A foto do recibo fica congelada em acertos_diarias.documento (empresa, prestador, serviço,
--     diária, Pix com o E2E, totais e as linhas) com o hash sha256: reimprimir o nº N mostra sempre
--     o mesmo papel. Colunas novas também para o papel assinado (assinado_em, assinatura_arquivo).
--   * payees.nit e work_profiles.servico: o NIT/PIS do prestador e a espécie do serviço, que o recibo
--     imprime quando há (nunca "a informar").
--
-- Os acertos antigos (documento nulo, como o nº 0004 do João de 26/10) ficam como estão e seguem
-- saindo no recibo antigo. O "próximo recibo começa em zero" vem da regra do período, não de dado.
-- Teste: supabase/tests/diarias_recibo_de_servicos.sql.

alter table public.acertos_diarias
  add column if not exists pagos_ate date,
  add column if not exists pix_quitacao_id uuid,
  add column if not exists documento jsonb,
  add column if not exists hash text,
  add column if not exists assinado_em timestamptz,
  add column if not exists assinatura_arquivo text;

comment on column public.acertos_diarias.pagos_ate is 'F2 (27/10/2026): dia do Pix de quitação; os pagamentos do recibo vão até ele (os dias, até "ate").';
comment on column public.acertos_diarias.pix_quitacao_id is 'F2: o lançamento (payables.id) do Pix que zerou a conta.';
comment on column public.acertos_diarias.documento is 'F2: a foto congelada do recibo (empresa, prestador, serviço, Pix, totais, linhas). Nulo = acerto do modelo antigo.';
comment on column public.acertos_diarias.hash is 'F2: sha256 do documento, para provar que o papel reimpresso é o mesmo.';
comment on column public.acertos_diarias.assinado_em is 'F2: quando o papel assinado foi anexado.';
comment on column public.acertos_diarias.assinatura_arquivo is 'F2: caminho no Storage da foto/PDF do papel assinado.';

alter table public.payees add column if not exists nit text;
comment on column public.payees.nit is 'NIT/PIS do prestador autônomo: vai no recibo de serviços quando preenchido.';
alter table public.work_profiles add column if not exists servico text;
comment on column public.work_profiles.servico is 'Espécie do serviço que o recibo imprime ("Instalação e manutenção elétrica em embarcações").';

-- ---------------------------------------------------------------------------------------------
-- 1. _previa_do_recibo: o que um recibo com este Pix seria (interna; sem gravar)
-- ---------------------------------------------------------------------------------------------
create or replace function public._previa_do_recibo(
  p_favorecido_id uuid,
  p_de date,
  p_de_pag date,
  p_ate date,
  p_pix_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_pix record;
  v_inicial numeric;
  r jsonb;
begin
  select l.* into v_pix from public._conta_corrente_linhas(p_favorecido_id) l
   where l.tipo = 'pagamento' and l.id = p_pix_id;
  if v_pix.id is null then return null; end if;
  select coalesce(saldo_anterior, 0) into v_inicial from public.payees where id = p_favorecido_id;

  with l as (
    select l.*, row_number() over (order by l.data, case l.tipo when 'dia' then 0 else 1 end, l.criado_em, l.id) as ordem
      from public._conta_corrente_linhas(p_favorecido_id) l
  ), dentro as (
    select * from l
     where (l.tipo in ('dia', 'reembolso') and l.data between p_de and p_ate)
        or (l.tipo = 'pagamento' and l.data >= p_de_pag
            and (l.data, l.criado_em, l.id) <= (v_pix.data, v_pix.criado_em, v_pix.id))
  ), antes as (
    select * from l
     where (l.tipo in ('dia', 'reembolso') and l.data < p_de) or (l.tipo = 'pagamento' and l.data < p_de_pag)
  )
  select jsonb_build_object(
    'de', p_de, 'de_pagamentos', p_de_pag, 'ate', p_ate, 'pagos_ate', v_pix.data,
    'saldo_anterior', round(v_inicial + coalesce((select sum(a.trabalhado - a.pago) from antes a), 0), 2),
    'dias', coalesce((select sum(d.fracao) from dentro d where d.tipo = 'dia'), 0),
    'trabalhado', round(coalesce((select sum(d.trabalhado) from dentro d where d.tipo = 'dia'), 0), 2),
    'reembolsos', round(coalesce((select sum(d.trabalhado) from dentro d where d.tipo = 'reembolso'), 0), 2),
    'pago', round(coalesce((select sum(d.pago) from dentro d where d.tipo = 'pagamento'), 0), 2),
    'pix', jsonb_build_object('id', v_pix.id, 'data', v_pix.data, 'valor', v_pix.pago, 'conta', v_pix.conta,
                              'descricao', v_pix.descricao, 'aguardando', v_pix.aguardando),
    'linhas', coalesce((select jsonb_agg(jsonb_build_object(
                 'data', d.data, 'tipo', d.tipo, 'id', d.id, 'jornada', d.jornada, 'fracao', d.fracao,
                 'valor_diaria', d.valor_diaria, 'extras', d.extras, 'descontos', d.descontos,
                 'trabalhado', d.trabalhado, 'pago', d.pago, 'descricao', d.descricao, 'conta', d.conta,
                 'categoria', d.categoria, 'observacao', d.observacao, 'os', d.os,
                 'aguardando', d.aguardando, 'quitacao', d.id = v_pix.id) order by d.ordem)
               from dentro d), '[]'::jsonb)
  ) into r;
  return r || jsonb_build_object('saldo_final', round((r ->> 'saldo_anterior')::numeric + (r ->> 'trabalhado')::numeric
                                                      + (r ->> 'reembolsos')::numeric - (r ->> 'pago')::numeric, 2));
end;
$$;

revoke all on function public._previa_do_recibo(uuid, date, date, date, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 2. fechar_acerto_diarias: o recibo do Pix que zera (assinatura nova: + p_pix_id, + p_de)
-- ---------------------------------------------------------------------------------------------
drop function if exists public.fechar_acerto_diarias(uuid, date, boolean, uuid);

create or replace function public.fechar_acerto_diarias(
  p_favorecido_id uuid,
  p_ate date default null,
  p_simular boolean default false,
  p_autor uuid default null,
  p_pix_id uuid default null,
  p_de date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_hoje date := public._hoje_brt();
  v_fav record;
  v_perfil record;
  v_ultimo record;
  v_emp record;
  v_de date;
  v_de_pag date;
  v_pix uuid := p_pix_id;
  v_candidatos jsonb := '[]'::jsonb;
  v_cand record;
  c jsonb;
  pr jsonb;
  v_travas text[] := '{}';
  v_linha jsonb;
  v_bt record;
  v_quem text;
  v_doc jsonb;
  v_hash text;
  v_id uuid;
  v_numero integer;
  v_pendentes integer;
  v_final numeric;
  v_resumo text;
begin
  if v_autor is null and not coalesce(p_simular, false) then raise exception 'Diga quem está fechando o recibo.'; end if;
  select id, name, document, nit, pix_key, conta_corrente_desde into v_fav from public.payees where id = p_favorecido_id;
  if v_fav.id is null then raise exception 'Freelancer não encontrado entre os favorecidos.'; end if;
  if p_ate is not null and p_ate > v_hoje then raise exception 'Serviços no futuro (%): o recibo vai até hoje.', to_char(p_ate, 'DD/MM/YYYY'); end if;

  -- O período: o próximo recibo começa no dia seguinte ao anterior (dias) e ao Pix dele (pagamentos).
  select numero, ate, pagos_ate into v_ultimo from public.acertos_diarias
   where favorecido_id = p_favorecido_id and status = 'fechado' order by ate desc, numero desc limit 1;
  if v_ultimo.numero is not null then
    v_de := v_ultimo.ate + 1;
    v_de_pag := coalesce(v_ultimo.pagos_ate, v_ultimo.ate) + 1;
    if p_de is not null and p_de <> v_de then
      raise exception 'O próximo recibo de % começa em % (dia seguinte ao nº %).', v_fav.name, to_char(v_de, 'DD/MM/YYYY'),
        lpad(v_ultimo.numero::text, 4, '0');
    end if;
  else
    v_de := greatest(coalesce(p_de, v_fav.conta_corrente_desde, (select min(l.data) from public._conta_corrente_linhas(p_favorecido_id) l), v_hoje),
                     coalesce(v_fav.conta_corrente_desde, date '1900-01-01'));
    v_de_pag := v_de;
  end if;

  -- Os Pix candidatos: cada pagamento depois do recibo anterior, com o saldo que sobraria fechando nele.
  for v_cand in
    select l.id, l.data, l.pago, l.conta, l.aguardando
      from public._conta_corrente_linhas(p_favorecido_id) l
     where l.tipo = 'pagamento' and l.data >= v_de_pag and l.data <= v_hoje
     order by l.data, l.criado_em, l.id
  loop
    pr := public._previa_do_recibo(p_favorecido_id, v_de, v_de_pag, greatest(coalesce(p_ate, v_cand.data), v_de), v_cand.id);
    v_candidatos := v_candidatos || jsonb_build_object('id', v_cand.id, 'data', v_cand.data, 'valor', v_cand.pago,
      'conta', v_cand.conta, 'aguardando', v_cand.aguardando, 'saldo_final', pr -> 'saldo_final',
      'zera', abs((pr ->> 'saldo_final')::numeric) < 0.005);
  end loop;

  if v_pix is null then
    select (x ->> 'id')::uuid into v_pix from jsonb_array_elements(v_candidatos) x
     where (x ->> 'zera')::boolean order by x ->> 'data' desc limit 1;
  elsif not exists (select 1 from jsonb_array_elements(v_candidatos) x where (x ->> 'id')::uuid = v_pix) then
    raise exception 'Esse pagamento não é de % depois do último recibo.', v_fav.name;
  end if;

  if v_pix is null then
    -- Sem Pix que zere: diz quanto falta (ou sobra) hoje, para o dono saber o que pagar.
    c := public.conta_corrente_freelancer(p_favorecido_id, null, null, p_autor);
    v_final := (c ->> 'saldo_final')::numeric;
    v_travas := v_travas || case
      when v_final > 0.005 then 'Falta pagar ' || public._brl(v_final) || ' a ' || v_fav.name || ': o recibo sai no Pix que zera a conta.'
      when v_final < -0.005 then v_fav.name || ' está adiantado em ' || public._brl(-v_final) || ': adiantado não gera recibo; ele sai quando os dias cobrirem.'
      else 'Nenhum pagamento depois do último recibo: nada a quitar.' end;
    if coalesce(p_simular, false) then
      return jsonb_build_object('ok', false, 'simulacao', true, 'favorecido', v_fav.name, 'de', v_de, 'de_pagamentos', v_de_pag,
        'candidatos', v_candidatos, 'previa', null, 'travas', to_jsonb(v_travas), 'saldo_hoje', round(v_final, 2));
    end if;
    raise exception '%', array_to_string(v_travas, ' ');
  end if;

  pr := public._previa_do_recibo(p_favorecido_id, v_de, v_de_pag,
          greatest(coalesce(p_ate, (select (x ->> 'data')::date from jsonb_array_elements(v_candidatos) x where (x ->> 'id')::uuid = v_pix)), v_de),
          v_pix);

  -- ── As travas ─────────────────────────────────────────────────────────────────────────────
  if nullif(regexp_replace(coalesce(v_fav.document, ''), '\D', '', 'g'), '') is null then
    v_travas := v_travas || ('Falta o CPF de ' || v_fav.name || ' no cadastro.');
  end if;
  select legal_name, cnpj, street, number, complement, district, city_name, state_code into v_emp
    from public.company_fiscal_settings limit 1;
  if nullif(btrim(coalesce(v_emp.legal_name, '')), '') is null or nullif(btrim(coalesce(v_emp.cnpj, '')), '') is null then
    v_travas := v_travas || 'Falta a razão social ou o CNPJ da empresa (Configurações › Fiscal).'::text;
  end if;
  for v_linha in select x from jsonb_array_elements(pr -> 'linhas') x loop
    if v_linha ->> 'tipo' = 'pagamento' and coalesce((v_linha ->> 'aguardando')::boolean, false) then
      v_travas := v_travas || ('Pix de ' || to_char((v_linha ->> 'data')::date, 'DD/MM') || ' (' || public._brl((v_linha ->> 'pago')::numeric) || ') '
        || case when v_linha ->> 'conta' = 'No banco — falta aprovar na fila' then 'está na fila: aprove antes do recibo.'
                else 'foi anotado à mão e o banco ainda não trouxe.' end);
    elsif v_linha ->> 'tipo' = 'pagamento' and v_linha ->> 'categoria' is null then
      v_travas := v_travas || ('Pagamento de ' || to_char((v_linha ->> 'data')::date, 'DD/MM') || ' (' || public._brl((v_linha ->> 'pago')::numeric)
        || ') sem categoria: diga se é diária.');
    elsif v_linha ->> 'tipo' = 'dia' and (coalesce((v_linha ->> 'extras')::numeric, 0) > 0 or coalesce((v_linha ->> 'descontos')::numeric, 0) > 0)
          and nullif(btrim(coalesce(v_linha ->> 'observacao', '')), '') is null then
      v_travas := v_travas || ('Dia ' || to_char((v_linha ->> 'data')::date, 'DD/MM') || ': diga o motivo do '
        || case when coalesce((v_linha ->> 'extras')::numeric, 0) > 0 then 'adicional' else 'desconto' end || '.');
    end if;
  end loop;
  select count(*) into v_pendentes from public.ai_operator_pending_actions
   where status = 'pending' and (expires_at is null or expires_at > now())
     and action_name in ('registrar_diaria', 'registrar_pagamento_freelancer', 'dividir_pagamento_freelancer')
     and payload ->> 'freelancer' ilike split_part(v_fav.name, ' ', 1) || '%';
  if v_pendentes > 0 then
    v_travas := v_travas || ('Há ' || v_pendentes || ' lançamento(s) de ' || split_part(v_fav.name, ' ', 1) || ' esperando o "sim" no assistente.');
  end if;
  v_final := (pr ->> 'saldo_final')::numeric;
  if v_final > 0.005 then
    v_travas := v_travas || ('Com o Pix de ' || to_char((pr -> 'pix' ->> 'data')::date, 'DD/MM') || ' ainda falta pagar ' || public._brl(v_final) || '.');
  elsif v_final < -0.005 then
    v_travas := v_travas || ('Com o Pix de ' || to_char((pr -> 'pix' ->> 'data')::date, 'DD/MM') || ' ele fica adiantado em ' || public._brl(-v_final)
      || ': escolha o serviço até uma data mais tarde ou espere os próximos dias.');
  end if;
  if (pr ->> 'trabalhado')::numeric = 0 and (pr ->> 'reembolsos')::numeric = 0 and (pr ->> 'saldo_anterior')::numeric <= 0 then
    v_travas := v_travas || 'Nenhum dia nem saldo a quitar no período.'::text;
  end if;

  v_resumo := v_fav.name || ' · serviços de ' || to_char((pr ->> 'de')::date, 'DD/MM') || ' a ' || to_char((pr ->> 'ate')::date, 'DD/MM')
    || ' · ' || replace(rtrim(rtrim(to_char((pr ->> 'dias')::numeric, 'FM9999990.99'), '0'), '.'), '.', ',') || ' diária(s) '
    || public._brl((pr ->> 'trabalhado')::numeric)
    || case when (pr ->> 'reembolsos')::numeric <> 0
            then ' · reembolso de despesas pagas pelo técnico ' || public._brl((pr ->> 'reembolsos')::numeric) else '' end
    || case when (pr ->> 'saldo_anterior')::numeric <> 0 then ' · saldo anterior ' || public._brl((pr ->> 'saldo_anterior')::numeric) else '' end
    || ' · já recebido ' || public._brl((pr ->> 'pago')::numeric - (pr -> 'pix' ->> 'valor')::numeric)
    || ' · Pix de ' || to_char((pr -> 'pix' ->> 'data')::date, 'DD/MM') || ' ' || public._brl((pr -> 'pix' ->> 'valor')::numeric);

  if coalesce(p_simular, false) then
    -- As chaves de antes (tela, assistente e testes) continuam, agora com o Pix de quitação à parte.
    return jsonb_build_object('ok', cardinality(v_travas) = 0, 'simulacao', true, 'favorecido', v_fav.name,
      'de', pr -> 'de', 'ate', pr -> 'ate', 'de_pagamentos', v_de_pag, 'pagos_ate', pr -> 'pagos_ate',
      'saldo_anterior', pr -> 'saldo_anterior', 'dias', pr -> 'dias', 'trabalhado', pr -> 'trabalhado',
      'reembolsos', pr -> 'reembolsos',
      'reembolsos_itens', coalesce((select jsonb_agg(jsonb_build_object('data', x ->> 'data', 'valor', (x ->> 'trabalhado')::numeric,
                                     'descricao', x ->> 'descricao', 'codigo', x ->> 'conta'))
                                    from jsonb_array_elements(pr -> 'linhas') x where x ->> 'tipo' = 'reembolso'), '[]'::jsonb),
      'vales', coalesce((select jsonb_agg(jsonb_build_object('data', x ->> 'data', 'valor', (x ->> 'pago')::numeric,
                           'descricao', x ->> 'descricao', 'aguardando', coalesce((x ->> 'aguardando')::boolean, false)))
                          from jsonb_array_elements(pr -> 'linhas') x
                         where x ->> 'tipo' = 'pagamento' and not coalesce((x ->> 'quitacao')::boolean, false)), '[]'::jsonb),
      'pago_no_periodo', (pr ->> 'pago')::numeric - (pr -> 'pix' ->> 'valor')::numeric,
      'valor_do_acerto', (pr -> 'pix' ->> 'valor')::numeric, 'pix', pr -> 'pix', 'saldo_final', pr -> 'saldo_final',
      'candidatos', v_candidatos, 'previa', pr, 'travas', to_jsonb(v_travas), 'resumo', v_resumo);
  end if;
  if cardinality(v_travas) > 0 then raise exception '%', array_to_string(v_travas, ' '); end if;

  -- ── A foto congelada ──────────────────────────────────────────────────────────────────────
  select p.payee_id, p.bank_transaction_id, soc.name as socio into v_bt
    from public.payables p left join public.payees soc on soc.id = p.payee_id and p.payee_id <> p_favorecido_id
   where p.id = v_pix;
  select * into v_perfil from public.work_profiles
   where payee_id = p_favorecido_id and modo_pagamento = 'diaria' and vigencia_inicio <= (pr ->> 'ate')::date
   order by vigencia_inicio desc limit 1;
  v_quem := case when v_bt.payee_id = p_favorecido_id then null else coalesce(v_bt.socio, 'sócio') end;

  v_doc := jsonb_build_object(
    'versao', 1,
    'empresa', jsonb_build_object('nome', btrim(v_emp.legal_name), 'cnpj', v_emp.cnpj,
                 'endereco', concat_ws(', ', nullif(btrim(concat_ws(', ', v_emp.street, v_emp.number)), ''), nullif(v_emp.complement, '')),
                 'bairro', v_emp.district, 'cidade', v_emp.city_name, 'uf', v_emp.state_code),
    'prestador', jsonb_build_object('id', v_fav.id, 'nome', v_fav.name, 'cpf', v_fav.document, 'nit', v_fav.nit, 'pix', v_fav.pix_key),
    'servico', coalesce(nullif(btrim(v_perfil.servico), ''), 'Prestação de serviços por dia'),
    'diaria', v_perfil.valor_diaria,
    'pix', (pr -> 'pix') || jsonb_build_object('e2e', (select bt.pix_end_to_end_id from public.bank_transactions bt where bt.id = v_bt.bank_transaction_id),
                                               'pelo_socio', v_quem),
    'de', pr -> 'de', 'ate', pr -> 'ate', 'pagos_ate', pr -> 'pagos_ate',
    'saldo_anterior', pr -> 'saldo_anterior', 'dias', pr -> 'dias', 'trabalhado', pr -> 'trabalhado',
    'reembolsos', pr -> 'reembolsos', 'pago', pr -> 'pago', 'linhas', pr -> 'linhas');
  v_hash := encode(sha256(convert_to(v_doc::text, 'UTF8')), 'hex');

  insert into public.acertos_diarias (favorecido_id, de, ate, pagos_ate, pix_quitacao_id, saldo_anterior, dias, trabalhado, reembolsos,
                                      pago_no_periodo, valor_do_acerto, documento, hash, criado_por)
  values (p_favorecido_id, (pr ->> 'de')::date, (pr ->> 'ate')::date, (pr ->> 'pagos_ate')::date, v_pix,
          (pr ->> 'saldo_anterior')::numeric, (pr ->> 'dias')::numeric, (pr ->> 'trabalhado')::numeric, (pr ->> 'reembolsos')::numeric,
          (pr ->> 'pago')::numeric - (pr -> 'pix' ->> 'valor')::numeric, (pr -> 'pix' ->> 'valor')::numeric, v_doc, v_hash, v_autor)
  returning id, numero into v_id, v_numero;

  return jsonb_build_object('ok', true, 'id', v_id, 'numero', v_numero, 'favorecido', v_fav.name,
    'de', pr -> 'de', 'ate', pr -> 'ate', 'valor_do_acerto', (pr -> 'pix' ->> 'valor')::numeric, 'hash', v_hash,
    'message', 'Recibo nº ' || lpad(v_numero::text, 4, '0') || ' fechado: ' || v_resumo
      || '. Os dias até ' || to_char((pr ->> 'ate')::date, 'DD/MM') || ' ficam travados; imprima e colha a assinatura.');
end;
$$;

revoke all on function public.fechar_acerto_diarias(uuid, date, boolean, uuid, uuid, date) from public, anon;
grant execute on function public.fechar_acerto_diarias(uuid, date, boolean, uuid, uuid, date) to authenticated, service_role;

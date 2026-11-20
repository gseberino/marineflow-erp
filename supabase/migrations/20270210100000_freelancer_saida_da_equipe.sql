-- Diárias: "Saiu da equipe" — 20/11/2026 (decisão do dono, Fase 1 do cartão dos freelancers).
--
-- O problema: desativar o freelancer nos Favorecidos sumia com a dívida dele da tela (o resumo só
-- lia quem está ativo — o Mickael saiu em setembro com R$ 280 a receber e, desativado, esse valor
-- sairia do "a pagar"); e nada impedia lançar um dia depois que a pessoa saiu.
--
-- O desenho usa o que já existe: work_profiles.vigencia_fim. É ele que o sistema inteiro já lê para
-- saber se a pessoa está na equipe NUMA DATA — registrar_diaria (o perfil vigente na data), a agenda
-- (capacidade, pergunta da diária, vigia de equipe sem dias, habilidades), os comprovantes e a
-- comissão. Registrar a saída = fechar a vigência no último dia; depois dele nenhum dia entra e a
-- agenda deixa de contar com a pessoa. "Voltou para a equipe" = reabrir a vigência.
--
-- O que a saída NÃO faz (decisões do dono):
--   * não desativa o favorecido nem pausa regras do extrato — o Pix para ele continua abatendo a conta;
--   * não zera o saldo: a receber ou adiantado (Roberto: "cobrar / descontar se ele voltar") fica na
--     conta; se ele voltar, os dias novos abatem;
--   * não reativa nada ao desfazer: favorecido desativado continua desativado (a volta pede reativar antes).
--
-- O resumo passa a mostrar quem saiu (com saiu_em) e também o desativado que ainda tem saldo — a tela
-- os põe na seção "Saíram da equipe" até a conta zerar. Desativado com a conta zerada continua fora.
--
-- Funções novas: _saida_da_equipe, registrar_saida_da_equipe, desfazer_saida_da_equipe.
-- Redefinidas (mesma assinatura): registrar_diaria (só a mensagem de recusa depois da saída) e
-- resumo_freelancers (quem entra + saiu_em, ativo, ultimo_dia_trabalhado).
-- Teste: supabase/tests/freelancer_saida_da_equipe.sql.

-- ── O último dia de quem saiu (null = está na equipe, ou não tem diária) ──────────────────────────
-- A vigência do perfil de diária MAIS NOVO. Uma troca de valor da diária fecha o perfil antigo e abre
-- outro; por isso vale só o mais novo.
create or replace function public._saida_da_equipe(p_favorecido_id uuid)
returns date
language sql
stable
security definer
set search_path = public
as $$
  select wp.vigencia_fim
    from public.work_profiles wp
   where wp.payee_id = p_favorecido_id and wp.modo_pagamento = 'diaria'
   order by wp.vigencia_inicio desc, wp.created_at desc
   limit 1;
$$;

revoke all on function public._saida_da_equipe(uuid) from public, anon, authenticated;
grant execute on function public._saida_da_equipe(uuid) to service_role;

-- ── A frase do saldo na saída e na volta (o banco diz; a IA não calcula) ─────────────────────────
create or replace function public._frase_do_saldo_da_saida(p_saldo numeric, p_volta boolean default false)
returns text
language sql
stable
set search_path = public
as $$
  select case
    when coalesce(p_saldo, 0) > 0 and not p_volta then
      'Saldo hoje: ' || public._brl(p_saldo) || ' a receber — ele fica em "Saíram da equipe" até a conta zerar; o Pix para ele continua abatendo.'
    when coalesce(p_saldo, 0) < 0 and not p_volta then
      'Saldo hoje: ' || public._brl(-p_saldo) || ' adiantado (ele deve dias) — fica registrado; se ele voltar, os dias novos abatem.'
    when coalesce(p_saldo, 0) > 0 then 'Você deve ' || public._brl(p_saldo) || ' a ele.'
    when coalesce(p_saldo, 0) < 0 then 'Ele está com ' || public._brl(-p_saldo) || ' adiantado: os dias novos abatem.'
    when not p_volta then 'A conta dele está zerada.'
    else ''
  end;
$$;

revoke all on function public._frase_do_saldo_da_saida(numeric, boolean) from public, anon, authenticated;
grant execute on function public._frase_do_saldo_da_saida(numeric, boolean) to service_role;

-- ── Saiu da equipe ───────────────────────────────────────────────────────────────────────────────
create or replace function public.registrar_saida_da_equipe(
  p_favorecido_id uuid,
  p_ultimo_dia date,
  p_simular boolean default false,
  p_autor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_simular boolean := coalesce(p_simular, false);
  v_fav public.payees%rowtype;
  v_perfil public.work_profiles%rowtype;
  v_depois text;
  v_n int;
  v_acao text;
  v_saldo numeric;
  v_nome text;
  v_msg text;
begin
  -- Simular não grava nada: o assistente monta a confirmação antes de saber quem vai dizer "sim".
  if v_autor is null and not v_simular then raise exception 'Diga quem está registrando a saída.'; end if;

  select * into v_fav from public.payees where id = p_favorecido_id;
  if v_fav.id is null then raise exception 'Freelancer não encontrado entre os favorecidos.'; end if;
  v_nome := v_fav.name;

  select * into v_perfil from public.work_profiles
   where payee_id = p_favorecido_id and modo_pagamento = 'diaria'
   order by vigencia_inicio desc, created_at desc
   limit 1
   for update;
  if v_perfil.id is null then
    raise exception '% não recebe por diária: a saída da equipe é para quem tem diária cadastrada.', v_nome;
  end if;

  if p_ultimo_dia is null then raise exception 'Diga o último dia de trabalho de %.', v_nome; end if;
  if p_ultimo_dia > public._hoje_brt() then
    raise exception 'Último dia no futuro (%): registre a saída no último dia de trabalho ou depois.', to_char(p_ultimo_dia, 'DD/MM/YYYY');
  end if;
  if p_ultimo_dia < v_perfil.vigencia_inicio then
    raise exception 'O último dia (%) é antes do começo da diária atual de % (%).', to_char(p_ultimo_dia, 'DD/MM/YYYY'), v_nome,
      to_char(v_perfil.vigencia_inicio, 'DD/MM/YYYY');
  end if;

  -- Dia lançado depois do último dia: ou o último dia está errado, ou o dia foi lançado por engano.
  select count(*), string_agg(public._dia_curto(ws.data), ', ' order by ws.data)
    into v_n, v_depois
    from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
   where wp.payee_id = p_favorecido_id and ws.fracao is not null and ws.data > p_ultimo_dia;
  if v_n > 0 then
    raise exception 'Há % dia(s) de % lançado(s) depois de %: %. Apague esses dias antes (se foram por engano) ou diga outro último dia.',
      v_n, v_nome, public._dia_curto(p_ultimo_dia), v_depois;
  end if;

  v_acao := case when v_perfil.vigencia_fim is null then 'saiu'
                 when v_perfil.vigencia_fim = p_ultimo_dia then 'sem_mudanca'
                 else 'mudou_a_data' end;

  if not v_simular and v_acao <> 'sem_mudanca' then
    -- O perfil mais novo e qualquer outro de diária ainda aberto depois do último dia: nenhum perfil
    -- pode deixar uma data depois da saída "com diária" (registrar_diaria e a agenda acham o vigente).
    update public.work_profiles
       set vigencia_fim = p_ultimo_dia
     where payee_id = p_favorecido_id and modo_pagamento = 'diaria'
       and (id = v_perfil.id or ((vigencia_fim is null or vigencia_fim > p_ultimo_dia) and vigencia_inicio <= p_ultimo_dia));
  end if;

  v_saldo := coalesce((public.conta_corrente_freelancer(p_favorecido_id, null, null, p_autor, null) ->> 'saldo_final')::numeric, 0);

  v_msg := case v_acao
    when 'sem_mudanca' then format('%s já saiu da equipe com último dia %s: nada muda.', v_nome, public._dia_curto(p_ultimo_dia))
    when 'mudou_a_data' then format('%s já tinha saído (último dia %s): o último dia %s %s.', v_nome,
      public._dia_curto(v_perfil.vigencia_fim), case when v_simular then 'passa a ser' else 'passou a ser' end, public._dia_curto(p_ultimo_dia))
    else format('%s %s da equipe: último dia %s. Depois disso nenhum dia entra para ele, e a agenda deixa de contar com ele. O cadastro continua ativo.',
      v_nome, case when v_simular then 'sai' else 'saiu' end, public._dia_curto(p_ultimo_dia))
  end || ' ' || public._frase_do_saldo_da_saida(v_saldo);

  return jsonb_build_object(
    'ok', true,
    'simulado', v_simular,
    'acao', v_acao,
    'favorecido_id', v_fav.id,
    'favorecido', v_nome,
    'ultimo_dia', p_ultimo_dia,
    'ultimo_dia_antes', v_perfil.vigencia_fim,
    'saldo', v_saldo,
    'message', v_msg
  );
end;
$$;

revoke all on function public.registrar_saida_da_equipe(uuid, date, boolean, uuid) from public, anon;
grant execute on function public.registrar_saida_da_equipe(uuid, date, boolean, uuid) to authenticated, service_role;

-- ── Voltou para a equipe ─────────────────────────────────────────────────────────────────────────
create or replace function public.desfazer_saida_da_equipe(
  p_favorecido_id uuid,
  p_simular boolean default false,
  p_autor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_simular boolean := coalesce(p_simular, false);
  v_fav public.payees%rowtype;
  v_perfil public.work_profiles%rowtype;
  v_saldo numeric;
begin
  if v_autor is null and not v_simular then raise exception 'Diga quem está registrando a volta.'; end if;

  select * into v_fav from public.payees where id = p_favorecido_id;
  if v_fav.id is null then raise exception 'Freelancer não encontrado entre os favorecidos.'; end if;

  select * into v_perfil from public.work_profiles
   where payee_id = p_favorecido_id and modo_pagamento = 'diaria'
   order by vigencia_inicio desc, created_at desc
   limit 1
   for update;
  if v_perfil.id is null then
    raise exception '% não recebe por diária: não há saída da equipe para desfazer.', v_fav.name;
  end if;
  if v_perfil.vigencia_fim is null then
    raise exception '% não saiu da equipe: nada a desfazer.', v_fav.name;
  end if;
  -- A saída não reativa nada (decisão do dono): favorecido desativado volta pelos Favorecidos.
  if not v_fav.active then
    raise exception '% está desativado nos favorecidos: reative o cadastro antes (Favorecidos), depois registre a volta.', v_fav.name;
  end if;

  if not v_simular then
    update public.work_profiles set vigencia_fim = null where id = v_perfil.id;
  end if;

  v_saldo := coalesce((public.conta_corrente_freelancer(p_favorecido_id, null, null, p_autor, null) ->> 'saldo_final')::numeric, 0);

  return jsonb_build_object(
    'ok', true,
    'simulado', v_simular,
    'acao', 'voltou',
    'favorecido_id', v_fav.id,
    'favorecido', v_fav.name,
    'ultimo_dia_antes', v_perfil.vigencia_fim,
    'saldo', v_saldo,
    'message', btrim(format('%s %s para a equipe (tinha saído com último dia %s): os dias voltam a entrar, com a diária do cadastro (%s). %s',
      v_fav.name, case when v_simular then 'volta' else 'voltou' end, public._dia_curto(v_perfil.vigencia_fim),
      public._brl(v_perfil.valor_diaria), public._frase_do_saldo_da_saida(v_saldo, true)))
  );
end;
$$;

revoke all on function public.desfazer_saida_da_equipe(uuid, boolean, uuid) from public, anon;
grant execute on function public.desfazer_saida_da_equipe(uuid, boolean, uuid) to authenticated, service_role;

-- ── registrar_diaria: a recusa depois da saída diz o motivo certo ────────────────────────────────
-- Antes, um dia depois da saída cairia em "não tem diária cadastrada: cadastre o valor da diária" —
-- e cadastrar de novo é o caminho errado. Só a mensagem muda; o resto é o que está no ar
-- (pg_get_functiondef de 20/11/2026).
create or replace function public.registrar_diaria(p_favorecido_id uuid, p_data date, p_jornada text, p_os_ids uuid[] DEFAULT NULL::uuid[], p_observacao text DEFAULT NULL::text, p_extras numeric DEFAULT NULL::numeric, p_descontos numeric DEFAULT NULL::numeric, p_valor_diaria numeric DEFAULT NULL::numeric, p_origem text DEFAULT 'painel'::text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_fav record;
  v_perfil record;
  v_antes record;
  v_depois record;
  v_fracao numeric;
  v_tipo text;
  v_id uuid;
  v_acao text;
  v_os_antes text[];
  v_os_depois text[];
  v_resumo text;
  v_saiu date;
begin
  if v_autor is null then raise exception 'Diga quem está registrando a diária.'; end if;
  if p_data is null then raise exception 'Informe a data do dia trabalhado.'; end if;
  if p_data > public._hoje_brt() then raise exception 'Data no futuro (%): registre a diária no dia trabalhado ou depois.', to_char(p_data, 'DD/MM/YYYY'); end if;
  v_fracao := case lower(btrim(coalesce(p_jornada, ''))) when 'inteiro' then 1 when 'meio' then 0.5 when 'faltou' then 0 end;
  if v_fracao is null then raise exception 'Jornada inválida: "%". Use inteiro, meio ou faltou.', p_jornada; end if;
  v_tipo := case when v_fracao = 0 then 'falta' else 'diaria' end;
  if coalesce(p_origem, '') not in ('whatsapp', 'painel', 'agente', 'importado') then raise exception 'Origem inválida: %.', p_origem; end if;
  if coalesce(p_extras, 0) < 0 or coalesce(p_descontos, 0) < 0 then raise exception 'Extras e descontos não podem ser negativos.'; end if;
  if p_valor_diaria is not null and p_valor_diaria <= 0 then raise exception 'O valor da diária precisa ser maior que zero.'; end if;

  select id, name into v_fav from public.payees where id = p_favorecido_id;
  if v_fav.id is null then raise exception 'Freelancer não encontrado entre os favorecidos.'; end if;

  -- O perfil vigente NA DATA do dia (não o de hoje): a diária de agosto é a de agosto.
  select * into v_perfil from public.work_profiles
   where payee_id = p_favorecido_id and modo_pagamento = 'diaria'
     and vigencia_inicio <= p_data and (vigencia_fim is null or vigencia_fim >= p_data)
   order by vigencia_inicio desc limit 1;
  if v_perfil.id is null then
    -- 20/11/2026: depois da saída da equipe não entra dia (e cadastrar de novo não é o caminho).
    v_saiu := public._saida_da_equipe(p_favorecido_id);
    if v_saiu is not null and p_data > v_saiu then
      raise exception '% saiu da equipe (último dia %): depois disso não entra dia para ele. Se ele voltou, registre a volta ("Voltou para a equipe").',
        v_fav.name, to_char(v_saiu, 'DD/MM/YYYY');
    end if;
    raise exception '% não tem diária cadastrada em %: cadastre o valor da diária antes.', v_fav.name, to_char(p_data, 'DD/MM/YYYY');
  end if;

  if p_os_ids is not null and exists (
       select 1 from unnest(p_os_ids) o(id) where not exists (select 1 from public.service_orders so where so.id = o.id)) then
    raise exception 'Uma das OS informadas não existe.';
  end if;

  select ws.* into v_antes
    from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
   where wp.payee_id = p_favorecido_id and ws.data = p_data and ws.fracao is not null
   for update of ws;

  select coalesce(array_agg(so.service_order_number order by so.service_order_number), '{}') into v_os_antes
    from public.work_shift_os wo join public.service_orders so on so.id = wo.service_order_id
   where wo.shift_id = v_antes.id;

  if v_antes.id is null then
    insert into public.work_shifts (work_profile_id, data, tipo, origem, status, observacao, registrado_por,
                                    aprovado_por, aprovado_em, fracao, valor_diaria, extras, descontos)
    values (v_perfil.id, p_data, v_tipo, p_origem, 'aprovado', nullif(btrim(coalesce(p_observacao, '')), ''), v_autor,
            v_autor, now(), v_fracao, round(coalesce(p_valor_diaria, v_perfil.valor_diaria), 2),
            round(coalesce(p_extras, 0), 2), round(coalesce(p_descontos, 0), 2))
    returning id into v_id;
    v_acao := 'criado';
  else
    v_id := v_antes.id;
    update public.work_shifts set
      tipo = v_tipo,
      fracao = v_fracao,
      valor_diaria = round(coalesce(p_valor_diaria, valor_diaria), 2),
      extras = round(coalesce(p_extras, extras), 2),
      descontos = round(coalesce(p_descontos, descontos), 2),
      observacao = case when p_observacao is null then observacao else nullif(btrim(p_observacao), '') end,
      status = 'aprovado', aprovado_por = v_autor, aprovado_em = now()
    where id = v_id;
    v_acao := 'atualizado';
  end if;

  if p_os_ids is not null then
    delete from public.work_shift_os where shift_id = v_id and not (service_order_id = any (p_os_ids));
    insert into public.work_shift_os (shift_id, service_order_id)
    select v_id, x.os from (select distinct unnest(p_os_ids) as os) x
    on conflict do nothing;
  end if;

  select ws.* into v_depois from public.work_shifts ws where ws.id = v_id;
  select coalesce(array_agg(so.service_order_number order by so.service_order_number), '{}') into v_os_depois
    from public.work_shift_os wo join public.service_orders so on so.id = wo.service_order_id
   where wo.shift_id = v_id;

  if v_acao = 'atualizado'
     and v_antes.fracao = v_depois.fracao and v_antes.valor_dia = v_depois.valor_dia
     and v_antes.observacao is not distinct from v_depois.observacao and v_os_antes = v_os_depois then
    v_acao := 'sem_mudanca';
  end if;

  v_resumo := v_fav.name || ' · ' || public._dia_curto(p_data) || ' · ' || public._rotulo_jornada(v_depois.fracao)
              || ' · ' || public._brl(v_depois.valor_dia)
              || case when cardinality(v_os_depois) > 0 then ' · OS ' || array_to_string(v_os_depois, ', ') else '' end;

  return jsonb_build_object(
    'ok', true,
    'acao', v_acao,
    'diaria_id', v_id,
    'favorecido_id', v_fav.id,
    'favorecido', v_fav.name,
    'data', p_data,
    'jornada', case v_depois.fracao when 1 then 'inteiro' when 0.5 then 'meio' else 'faltou' end,
    'valor_diaria', v_depois.valor_diaria,
    'valor_dia', v_depois.valor_dia,
    'os', to_jsonb(v_os_depois),
    'antes', case when v_antes.id is null then null else jsonb_build_object(
               'jornada', case v_antes.fracao when 1 then 'inteiro' when 0.5 then 'meio' else 'faltou' end,
               'valor_dia', v_antes.valor_dia, 'os', to_jsonb(v_os_antes)) end,
    'message', v_resumo || case v_acao
      when 'criado' then ' — registrado.'
      when 'sem_mudanca' then ' — já estava assim.'
      else ' — atualizado (era ' || public._rotulo_jornada(v_antes.fracao) || ', ' || public._brl(v_antes.valor_dia) || ').' end
  );
end;
$function$;

-- ── O resumo: quem saiu continua na conta até zerar ──────────────────────────────────────────────
create or replace function public.resumo_freelancers(p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_autor uuid DEFAULT NULL::uuid, p_atalho text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_pessoas jsonb := '[]'::jsonb;
  f record;
  c jsonb;
  v_ultimo date;
  v_ultimo_dia date;
begin
  for f in
    select p.id, p.name, p.active
      from public.payees p
     where exists (select 1 from public.work_profiles wp where wp.payee_id = p.id and wp.modo_pagamento = 'diaria')
           -- 12/11: o prestador por serviço (Alex) — com conta corrente começada
        or (p.kind in ('prestador', 'comissionado') and p.conta_corrente_desde is not null)
     order by p.name
  loop
    c := public.conta_corrente_freelancer(f.id, p_de, p_ate, p_autor, p_atalho);
    -- 20/11/2026: desativado nos favorecidos só sai do resumo com a conta zerada — antes sumia com a dívida
    if not f.active and coalesce((c ->> 'saldo_final')::numeric, 0) = 0 then continue; end if;
    select max(l.data) into v_ultimo
      from public._conta_corrente_linhas(f.id) l
     where l.tipo = 'pagamento'
       and l.data <= coalesce((c ->> 'ate')::date, date '9999-12-31')
       and l.data >= coalesce((c ->> 'de')::date, date '1900-01-01');
    select max(ws.data) into v_ultimo_dia
      from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
     where wp.payee_id = f.id and ws.fracao > 0;
    v_pessoas := v_pessoas || jsonb_build_object(
      'id', f.id, 'nome', f.name,
      'diaria', c -> 'favorecido' -> 'diaria',
      'modo', c -> 'favorecido' -> 'modo',
      'desde', c -> 'favorecido' -> 'desde',
      'de', c -> 'de', 'ate', c -> 'ate',
      'dias', c -> 'dias', 'trabalhado', c -> 'trabalhado', 'reembolsos', c -> 'reembolsos', 'pago', c -> 'pago',
      'servicos', c -> 'servicos', 'n_servicos', c -> 'n_servicos',
      'aguardando_cliente', c -> 'aguardando_cliente',
      'pago_aguardando_banco', c -> 'pago_aguardando_banco',
      'pago_falta_aprovar', c -> 'pago_falta_aprovar',
      'ultimo_pagamento', v_ultimo,
      'saldo_final', c -> 'saldo_final', 'estado', c -> 'estado',
      -- 20/11/2026: saída da equipe (último dia) e o cadastro ativo nos favorecidos
      'saiu_em', public._saida_da_equipe(f.id),
      'ativo', f.active,
      'ultimo_dia_trabalhado', v_ultimo_dia);
  end loop;

  return jsonb_build_object(
    'pessoas', v_pessoas,
    'atalho', p_atalho,
    'trabalhado', coalesce((select sum((x ->> 'trabalhado')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'reembolsos', coalesce((select sum((x ->> 'reembolsos')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'pago', coalesce((select sum((x ->> 'pago')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'dias', coalesce((select sum((x ->> 'dias')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'deve', coalesce((select sum(greatest((x ->> 'saldo_final')::numeric, 0)) from jsonb_array_elements(v_pessoas) x), 0),
    'adiantado', coalesce((select sum(greatest(-(x ->> 'saldo_final')::numeric, 0)) from jsonb_array_elements(v_pessoas) x), 0)
  );
end;
$function$;

insert into supabase_migrations.schema_migrations (version, name) values ('20270210100000','freelancer_saida_da_equipe');

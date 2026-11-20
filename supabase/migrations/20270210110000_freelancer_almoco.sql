-- Diárias: "Trouxe o almoço" — 20/11/2026 (decisão do dono, Fase 2 do cartão dos freelancers).
--
-- O problema: o almoço de quem traz o próprio virava um extra de R$ 20 digitado à mão, quase sempre
-- sem motivo — e o recibo (fechar_acerto_diarias) TRAVA dia com adicional sem motivo (6 dos 7 dias com
-- extra estão assim em 20/11). Agora é uma caixa ao lançar o dia (no WhatsApp: "trouxe almoço"): o
-- valor vem da configuração e o motivo "Alimentação (trouxe o almoço)" é escrito sozinho em
-- work_shifts.observacao, então o recibo não trava.
--
-- O desenho:
--   * work_shifts.almoco = quanto do extra do dia é o almoço (0 = sem). O extra continua sendo o TOTAL
--     (almoço + outros): valor_dia, extrato, recibo, CSV e o lucro por OS não mudam nada.
--   * O valor vem de UM lugar: app_settings.diarias_valor_almoco (R$ 20, o que o dono disse). A tela
--     (rótulo da caixa) e o assistente (o "sim") leem a mesma chave. Sem a chave, o banco recusa —
--     não há valor escondido no código. O almoço já gravado num dia guarda o valor daquele dia.
--   * registrar_diaria ganha p_almoco (true = trouxe, false = tira, null = como está). Com p_almoco
--     dito, p_extras são os OUTROS extras (sem o almoço); sem p_almoco, p_extras continua sendo o
--     total do dia como sempre foi (o almoço que já estava fica dentro dele, se couber).
--   * apagar_diaria devolve o almoço (o Desfazer da tela recoloca igual); conta_corrente_freelancer
--     manda o almoço de cada dia (a tela de correção mostra a caixa marcada); o lote aceita "almoco".
--
-- registrar_diaria muda de assinatura (parâmetro novo no FIM, com default): DROP + CREATE e os mesmos
-- grants de antes. Quem chama com 10 argumentos posicionais (agenda: _agenda_decidir_diaria,
-- agenda_diaria_dita; registrar_diarias_em_lote) continua igual.
-- Teste: supabase/tests/freelancer_almoco.sql.

-- ── A coluna ──────────────────────────────────────────────────────────────────────────────────────
alter table public.work_shifts add column if not exists almoco numeric(12,2) not null default 0;
alter table public.work_shifts drop constraint if exists work_shifts_almoco_dentro_dos_extras;
alter table public.work_shifts add constraint work_shifts_almoco_dentro_dos_extras check (almoco >= 0 and almoco <= extras);
comment on column public.work_shifts.almoco is
  'Quanto do extra do dia é o almoço que o freelancer trouxe (0 = sem). Já está DENTRO de extras; o motivo vai em observacao.';

-- ── O valor (uma fonte só) ───────────────────────────────────────────────────────────────────────
insert into public.app_settings (key, value, description)
values ('diarias_valor_almoco', '20',
        'Diárias: valor do almoço quando o freelancer traz o próprio (caixa "Trouxe o almoço" ao lançar o dia), em reais.')
on conflict (key) do nothing;

create or replace function public._valor_do_almoco()
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select nullif(replace(btrim(value), ',', '.'), '')::numeric
    from public.app_settings where key = 'diarias_valor_almoco';
$$;

revoke all on function public._valor_do_almoco() from public, anon, authenticated;
grant execute on function public._valor_do_almoco() to service_role;

-- ── O motivo escrito sozinho: "Alimentação (trouxe o almoço)" no começo da observação ─────────────
-- Tira o motivo que já estava (para não repetir nem sobrar quando o almoço sai) e põe de novo se há almoço.
create or replace function public._observacao_com_almoco(p_observacao text, p_almoco boolean)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_almoco then 'Alimentação (trouxe o almoço)' || coalesce('; ' || x.resto, '')
    else x.resto
  end
  from (select nullif(btrim(regexp_replace(coalesce(p_observacao, ''),
                                           '^\s*Alimentação \(trouxe o almoço\)\s*;?\s*', '')), '') as resto) x;
$$;

revoke all on function public._observacao_com_almoco(text, boolean) from public, anon, authenticated;
grant execute on function public._observacao_com_almoco(text, boolean) to service_role;

-- ── registrar_diaria com p_almoco ────────────────────────────────────────────────────────────────
drop function if exists public.registrar_diaria(uuid, date, text, uuid[], text, numeric, numeric, numeric, text, uuid);

create function public.registrar_diaria(p_favorecido_id uuid, p_data date, p_jornada text, p_os_ids uuid[] DEFAULT NULL::uuid[], p_observacao text DEFAULT NULL::text, p_extras numeric DEFAULT NULL::numeric, p_descontos numeric DEFAULT NULL::numeric, p_valor_diaria numeric DEFAULT NULL::numeric, p_origem text DEFAULT 'painel'::text, p_autor uuid DEFAULT NULL::uuid, p_almoco boolean DEFAULT NULL::boolean)
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
  v_almoco_antes numeric;
  v_outros_antes numeric;
  v_almoco numeric;
  v_outros numeric;
  v_obs text;
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

  -- 20/11/2026: o almoço (o extra que ele ganha quando traz o próprio). Com p_almoco dito, p_extras são
  -- os OUTROS extras; sem p_almoco, p_extras é o total do dia, como sempre foi.
  v_almoco_antes := coalesce(v_antes.almoco, 0);
  v_outros_antes := coalesce(v_antes.extras, 0) - v_almoco_antes;
  if p_almoco is null then
    v_almoco := v_almoco_antes;
    if p_extras is null then
      v_outros := v_outros_antes;
    elsif p_extras >= v_almoco_antes then
      v_outros := p_extras - v_almoco_antes;      -- o total dito já inclui o almoço que estava
    else
      v_almoco := 0;                              -- o total dito é menor que o almoço: o almoço sai
      v_outros := p_extras;
    end if;
  else
    v_almoco := case when not p_almoco then 0
                     when v_almoco_antes > 0 then v_almoco_antes   -- o almoço já lançado guarda o valor daquele dia
                     else public._valor_do_almoco() end;
    if p_almoco and coalesce(v_almoco, 0) <= 0 then
      raise exception 'O valor do almoço não está configurado (app_settings diarias_valor_almoco): diga quanto é o almoço.';
    end if;
    v_outros := coalesce(p_extras, v_outros_antes);
  end if;
  if v_fracao = 0 and v_almoco > 0 then raise exception 'Almoço é de quem trabalhou: o dia sem trabalho não tem almoço.'; end if;

  -- A observação: a dita (ou a que já estava); com almoço, o motivo vai na frente, escrito pelo sistema
  -- (o recibo trava adicional sem motivo).
  v_obs := case when v_antes.id is null or p_observacao is not null then nullif(btrim(coalesce(p_observacao, '')), '')
                else v_antes.observacao end;
  v_obs := public._observacao_com_almoco(v_obs, v_almoco > 0);

  if v_antes.id is null then
    insert into public.work_shifts (work_profile_id, data, tipo, origem, status, observacao, registrado_por,
                                    aprovado_por, aprovado_em, fracao, valor_diaria, extras, descontos, almoco)
    values (v_perfil.id, p_data, v_tipo, p_origem, 'aprovado', v_obs, v_autor,
            v_autor, now(), v_fracao, round(coalesce(p_valor_diaria, v_perfil.valor_diaria), 2),
            round(v_outros + v_almoco, 2), round(coalesce(p_descontos, 0), 2), round(v_almoco, 2))
    returning id into v_id;
    v_acao := 'criado';
  else
    v_id := v_antes.id;
    update public.work_shifts set
      tipo = v_tipo,
      fracao = v_fracao,
      valor_diaria = round(coalesce(p_valor_diaria, valor_diaria), 2),
      extras = round(v_outros + v_almoco, 2),
      almoco = round(v_almoco, 2),
      descontos = round(coalesce(p_descontos, descontos), 2),
      observacao = v_obs,
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
              || case when v_depois.almoco > 0 then ' (com almoço ' || public._brl(v_depois.almoco) || ')' else '' end
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
    'almoco', v_depois.almoco,
    'os', to_jsonb(v_os_depois),
    'antes', case when v_antes.id is null then null else jsonb_build_object(
               'jornada', case v_antes.fracao when 1 then 'inteiro' when 0.5 then 'meio' else 'faltou' end,
               'valor_dia', v_antes.valor_dia, 'almoco', v_antes.almoco, 'os', to_jsonb(v_os_antes)) end,
    'message', v_resumo || case v_acao
      when 'criado' then ' — registrado.'
      when 'sem_mudanca' then ' — já estava assim.'
      else ' — atualizado (era ' || public._rotulo_jornada(v_antes.fracao) || ', ' || public._brl(v_antes.valor_dia) || ').' end
  );
end;
$function$;

revoke all on function public.registrar_diaria(uuid, date, text, uuid[], text, numeric, numeric, numeric, text, uuid, boolean) from public, anon;
grant execute on function public.registrar_diaria(uuid, date, text, uuid[], text, numeric, numeric, numeric, text, uuid, boolean) to authenticated, service_role;

-- ── O lote aceita "almoco" em cada dia ───────────────────────────────────────────────────────────
create or replace function public.registrar_diarias_em_lote(p_favorecido_id uuid, p_dias jsonb, p_origem text DEFAULT 'agente'::text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  d jsonb;
  r jsonb;
  v_res jsonb := '[]'::jsonb;
  v_data date;
begin
  if p_dias is null or jsonb_typeof(p_dias) <> 'array' or jsonb_array_length(p_dias) = 0 then
    raise exception 'Nenhum dia para registrar.';
  end if;
  if jsonb_array_length(p_dias) > 62 then
    raise exception 'Dias demais num pedido só (%): até 62.', jsonb_array_length(p_dias);
  end if;
  if (select count(*) <> count(distinct x ->> 'data') from jsonb_array_elements(p_dias) x) then
    raise exception 'O mesmo dia aparece duas vezes no pedido: diga cada dia uma vez só.';
  end if;

  for d in select x from jsonb_array_elements(p_dias) x order by x ->> 'data' loop
    v_data := (d ->> 'data')::date;
    begin
      r := public.registrar_diaria(
        p_favorecido_id, v_data, d ->> 'jornada',
        case when jsonb_typeof(d -> 'os_ids') = 'array' then array(select jsonb_array_elements_text(d -> 'os_ids')::uuid) end,
        d ->> 'observacao', (d ->> 'extras')::numeric, (d ->> 'descontos')::numeric, (d ->> 'valor_diaria')::numeric,
        coalesce(p_origem, 'agente'), p_autor,
        -- 20/11/2026: "trouxe almoço" naquele dia (true/false; ausente = como está)
        case when jsonb_typeof(d -> 'almoco') = 'boolean' then (d ->> 'almoco')::boolean end);
    exception when others then
      raise exception 'Nada foi gravado: o dia % foi recusado (%).', to_char(v_data, 'DD/MM'), sqlerrm;
    end;
    v_res := v_res || jsonb_build_array(r);
  end loop;

  return jsonb_build_object('ok', true, 'quantos', jsonb_array_length(v_res), 'dias', v_res);
end;
$function$;

-- ── apagar_diaria devolve o almoço (o Desfazer recoloca o dia igual) ─────────────────────────────
create or replace function public.apagar_diaria(p_diaria_id uuid, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v record;
  v_os uuid[];
begin
  if v_autor is null then raise exception 'Diga quem está apagando a diária.'; end if;
  select ws.*, wp.payee_id, p.name as nome into v
    from public.work_shifts ws
    join public.work_profiles wp on wp.id = ws.work_profile_id
    join public.payees p on p.id = wp.payee_id
   where ws.id = p_diaria_id and ws.fracao is not null
   for update of ws;
  if v.id is null then raise exception 'Diária não encontrada (talvez já tenha sido apagada).'; end if;

  select coalesce(array_agg(service_order_id), '{}') into v_os from public.work_shift_os where shift_id = p_diaria_id;
  delete from public.work_shifts where id = p_diaria_id;

  return jsonb_build_object(
    'ok', true,
    'apagado', jsonb_build_object(
      'favorecido_id', v.payee_id, 'data', v.data,
      'jornada', case v.fracao when 1 then 'inteiro' when 0.5 then 'meio' else 'faltou' end,
      'valor_diaria', v.valor_diaria, 'extras', v.extras, 'descontos', v.descontos, 'almoco', v.almoco,
      'observacao', v.observacao, 'os_ids', to_jsonb(v_os)),
    'message', 'Diária de ' || v.nome || ' em ' || public._dia_curto(v.data) || ' apagada.'
  );
end;
$function$;

-- ── conta_corrente_freelancer manda o almoço de cada dia (a tela de correção mostra a caixa marcada) ──
-- Só a linha do almoço muda; o resto é o que está no ar (pg_get_functiondef de 20/11/2026).
CREATE OR REPLACE FUNCTION public.conta_corrente_freelancer(p_favorecido_id uuid, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_autor uuid DEFAULT NULL::uuid, p_atalho text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_fav record;
  v_perfil record;
  v_de date := p_de;
  v_ate date := p_ate;
  v_anterior numeric;
  v_linhas jsonb;
  v_dias numeric;
  v_trab numeric;
  v_serv numeric;
  v_n_serv int;
  v_reemb numeric;
  v_pago numeric;
  v_aguardando numeric;
  v_falta_aprovar numeric;
  v_final numeric;
  v_dias_tudo numeric;
  v_pago_tudo numeric;
  v_aguardando_cliente jsonb;
begin
  select id, name, kind, conta_corrente_desde, saldo_anterior into v_fav
    from public.payees where id = p_favorecido_id;
  if v_fav.id is null then raise exception 'Freelancer não encontrado entre os favorecidos.'; end if;

  if p_atalho is not null then
    select x.de, x.ate into v_de, v_ate from public._periodo_do_atalho(p_favorecido_id, p_atalho) x;
  end if;

  v_de := greatest(coalesce(v_de, v_fav.conta_corrente_desde, date '1900-01-01'),
                   coalesce(v_fav.conta_corrente_desde, date '1900-01-01'));
  v_ate := coalesce(v_ate, date '9999-12-31');
  if v_ate < v_de then raise exception 'Período invertido: % a %.', to_char(v_de, 'DD/MM/YYYY'), to_char(v_ate, 'DD/MM/YYYY'); end if;

  select * into v_perfil from public.work_profiles
   where payee_id = p_favorecido_id and modo_pagamento = 'diaria'
     and vigencia_inicio <= least(v_ate, public._hoje_brt())
   order by vigencia_inicio desc limit 1;

  select v_fav.saldo_anterior + coalesce(sum(l.trabalhado - l.pago), 0) into v_anterior
    from public._conta_corrente_linhas(p_favorecido_id) l where l.data < v_de;

  with l as (
    select * from public._conta_corrente_linhas(p_favorecido_id) where data between v_de and v_ate
  ), o as (
    select l.*, v_anterior + sum(l.trabalhado - l.pago) over (
             order by l.data, case l.tipo when 'dia' then 0 when 'servico' then 0 else 1 end, l.criado_em, l.id
             rows between unbounded preceding and current row) as saldo,
           row_number() over (order by l.data, case l.tipo when 'dia' then 0 when 'servico' then 0 else 1 end,
                              l.criado_em, l.id) as ordem
      from l
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'data', o.data, 'tipo', o.tipo, 'id', o.id, 'jornada', o.jornada, 'fracao', o.fracao,
           'valor_diaria', o.valor_diaria, 'extras', o.extras, 'descontos', o.descontos,
           'trabalhado', o.trabalhado, 'pago', o.pago, 'descricao', o.descricao, 'conta', o.conta,
           'categoria', o.categoria, 'observacao', o.observacao, 'os', o.os, 'saldo', round(o.saldo, 2),
           'aguardando', o.aguardando, 'criado_em', o.criado_em,
           -- 20/11/2026: quanto do extra do dia é o almoço (0 = sem)
           'almoco', case when o.tipo = 'dia' then coalesce((select ws.almoco from public.work_shifts ws where ws.id = o.id), 0) end)
           order by o.ordem), '[]'::jsonb),
         coalesce(sum(o.fracao) filter (where o.tipo = 'dia'), 0),
         -- 12/11: "trabalhado" = diárias + serviços (o crédito pelo trabalho); "servicos" à parte
         coalesce(sum(o.trabalhado) filter (where o.tipo in ('dia', 'servico')), 0),
         coalesce(sum(o.trabalhado) filter (where o.tipo = 'servico'), 0),
         count(*) filter (where o.tipo = 'servico'),
         coalesce(sum(o.trabalhado) filter (where o.tipo = 'reembolso'), 0),
         coalesce(sum(o.pago), 0),
         -- 1a: só o que o banco ainda não trouxe; o que já está no banco vai à parte
         coalesce(sum(o.pago) filter (where o.aguardando and o.conta = 'Anotado — aguardando o banco'), 0),
         coalesce(sum(o.pago) filter (where o.aguardando and o.conta = 'No banco — falta aprovar na fila'), 0)
    into v_linhas, v_dias, v_trab, v_serv, v_n_serv, v_reemb, v_pago, v_aguardando, v_falta_aprovar
    from o;

  v_final := v_anterior + v_trab + v_reemb - v_pago;

  -- 12/11: o que ele já fez e espera o cliente pagar a OS (fora do saldo)
  select coalesce(jsonb_agg(x order by x ->> 'numero'), '[]'::jsonb) into v_aguardando_cliente
    from jsonb_array_elements(public.servicos_do_prestador(p_favorecido_id, p_autor)) x
   where x ->> 'situacao' = 'aguardando_cliente';

  -- 12/11: o serviço (na conta ou esperando o cliente) conta como "trabalho lançado" para o estado: pago
  -- antes de o cliente pagar é "adiantado", não "pagamento sem dia lançado"
  select coalesce(sum(l.fracao) filter (where l.tipo = 'dia'), 0) + count(*) filter (where l.tipo = 'servico')
           + jsonb_array_length(v_aguardando_cliente),
         coalesce(sum(l.pago), 0)
    into v_dias_tudo, v_pago_tudo
    from public._conta_corrente_linhas(p_favorecido_id) l where l.data <= v_ate;

  return jsonb_build_object(
    'favorecido', jsonb_build_object('id', v_fav.id, 'nome', v_fav.name,
                                     'desde', v_fav.conta_corrente_desde, 'saldo_inicial', v_fav.saldo_anterior,
                                     'diaria', v_perfil.valor_diaria,
                                     'modo', case when v_perfil.id is not null then 'diaria' else 'servico' end),
    'atalho', p_atalho,
    'de', case when v_de = date '1900-01-01' then null else v_de end,
    'ate', case when v_ate = date '9999-12-31' then null else v_ate end,
    'saldo_anterior', round(v_anterior, 2),
    'linhas', v_linhas,
    'dias', v_dias,
    'trabalhado', round(v_trab, 2),
    'servicos', round(v_serv, 2),
    'n_servicos', v_n_serv,
    'reembolsos', round(v_reemb, 2),
    'pago', round(v_pago, 2),
    'pago_aguardando_banco', round(v_aguardando, 2),
    'pago_falta_aprovar', round(v_falta_aprovar, 2),
    'saldo_final', round(v_final, 2),
    'estado', public._estado_do_saldo(v_final, v_dias_tudo, v_pago_tudo),
    'aguardando_cliente', round(coalesce((select sum((x ->> 'valor')::numeric) from jsonb_array_elements(v_aguardando_cliente) x), 0), 2),
    'servicos_aguardando_cliente', v_aguardando_cliente
  );
end;
$function$;


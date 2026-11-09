-- Retorno rápido ao cliente, F4 (P3): a regra de ouro do parceiro e o vínculo OS × parceiro. Nada liga aqui.
--
-- 1. parceiro_os_visivel(vínculo, agora) → {"visivel", "motivo"} (C-OURO): a regra de ouro numa função só, chamada ao
--    montar e de novo no envio. A 1ª condição que falha decide: sem_linha, parceiro_inativo, anfitria (nunca aparece),
--    nao_confirmado (papel nulo, situação diferente de confirmado ou confirmado depois de agora), veto (NÃO MP ou veto do
--    dono, até agora), retido (resposta ao aviso que pode ser um "não"), opt_out (opt-out ou canal bloqueado do cliente),
--    sem_aviso, antes_de_24h, os_fora (regra 8, lista positiva da F2) e cliente_fora (inativo ou genérico).
--    _parceiro_os_visivel tem o mesmo corpo com as condições 6 e 7 opcionais: só o destino do PDF (P12.2) as pula, e
--    só com pdf_sem_espera_ligado.
-- 2. _parceiro_os_viva (a regra 8): OS sem merged_into_id, criada até agora, e na carteira (os_carteira), ou rascunho
--    pedido por este parceiro (origem_parceiro_id), ou concluída com a palavra do dono ou da equipe dentro de
--    fato_pronto_idade, ou liberada para retirada dentro de liberado_validade e sem delivered_at.
-- 3. parceiro_os_visiveis: as OS que o parceiro pode ver agora (só papel comercial, nunca anfitriã).
-- 4. parceiro_lote_candidatos: o lote de vínculos por sinal objetivo (numero_do_pedido, unidade_anterior, propria,
--    carteira), nunca por nome nem pela placa sozinha. Exclui par com linha em qualquer situação, cliente com veto e OS
--    fora da regra 8. A carteira nasce sem papel.
-- 5. parceiro_propor (o lote vira proposto e entra na fila), _parceiro_confirmar (só pelo cartão), parceiro_requalificar
--    (opção B e PDF à mão) e parceiro_vinculo_cortar (item corte). Autor: só o dono (_comprovante_dono), senão 42501.
-- 6. parceiro_destino_do_pdf (P12.2): a regra do documento, separada da de status, e o número único que recebe o PDF.
-- 7. parceiro_semear: a semente dos números que o dono confirmou (seção 8.2), idempotente, com a exclusão do detector da
--    agenda em cada forma do telefone.
-- 8. parceiro_numeros_fora_da_ia (P12.4): as chaves dos números confirmados enquanto parceiro_historico_na_ia é falso.
--
-- _parceiro_confirmar chama parceiro_aviso_agendar (P6, migration posterior): plpgsql, que só compila na 1ª execução. O
-- caminho com e sem telefone é testado em P6.2-15.
--
-- Sem dado: só funções novas. Nada é chamado enquanto o dono não mandar *parceiro* (P8) e a semente não rodar.
-- Reverter: drop function das funções desta migration (parceiro_*, _parceiro_os_visivel, _parceiro_os_viva,
-- _parceiro_veto_de, _parceiro_confirmar). As tabelas da P1 ficam.

-- ── 1. A regra de ouro ─────────────────────────────────────────────────────────────────────────────────────────────────────

-- O veto do par cliente × parceiro, até agora: a linha de parceiro_vetos (NÃO MP ou veto do dono) ou o veto gravado em
-- algum vínculo do par. Nulo: sem veto. Ninguém olha o futuro.
create or replace function public._parceiro_veto_de(p_client uuid, p_parceiro uuid, p_agora timestamptz)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  select min(x.em)
    from (select v.em
            from public.parceiro_vetos v
           where v.client_id = p_client
             and v.parceiro_id = p_parceiro
             and v.em <= coalesce(p_agora, now())
          union all
          select oi.veto_do_cliente_em
            from public.os_interessados oi
           where oi.client_id = p_client
             and oi.parceiro_id = p_parceiro
             and oi.veto_do_cliente_em is not null
             and oi.veto_do_cliente_em <= coalesce(p_agora, now())) x;
$$;

comment on function public._parceiro_veto_de(uuid, uuid, timestamptz) is
  'Retorno F4 (P3.1): o veto do par cliente × parceiro até p_agora (parceiro_vetos ou veto_do_cliente_em de algum vínculo do par), ou nulo. Vale para as OS seguintes: parceiro_vetos não tem OS.';

revoke all on function public._parceiro_veto_de(uuid, uuid, timestamptz) from public, anon, authenticated;

-- A regra 8: a OS está viva para este parceiro? Lista positiva, a mesma da F2 (retorno_fatos_do_contato), mais o rascunho
-- que o próprio parceiro pediu. delivered_at sozinho não tira nem põe.
create or replace function public._parceiro_os_viva(p_os uuid, p_parceiro uuid, p_agora timestamptz)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_so record;
begin
  if v_cfg.id is null or p_os is null then
    return false;
  end if;
  select so.id, so.status, so.merged_into_id, so.origem_parceiro_id, so.delivered_at, so.liberado_retirada_em, so.created_at
    into v_so
    from public.service_orders so
   where so.id = p_os;
  if not found or v_so.merged_into_id is not null or v_so.created_at > v_agora then
    return false;
  end if;
  -- Na carteira de hoje (no dia de Brasília).
  if exists (select 1 from public.os_carteira((v_agora at time zone c_fuso)::date) k where k.service_order_id = p_os) then
    return true;
  end if;
  -- O rascunho pedido por este parceiro (C13).
  if v_so.status = 'draft' and p_parceiro is not null and v_so.origem_parceiro_id = p_parceiro then
    return true;
  end if;
  -- Concluída com a palavra do dono ou da equipe dentro de fato_pronto_idade (o status sozinho não é fato).
  if v_so.status in ('completed', 'invoiced')
     and exists (select 1 from public.agenda_acoes a
                  where a.service_order_id = p_os
                    and a.tipo = 'concluir'
                    and a.executada
                    and a.desfeita_em is null
                    and a.origem in ('dono', 'equipe')
                    and a.criada_em <= v_agora
                    and a.criada_em >= v_agora - v_cfg.fato_pronto_idade) then
    return true;
  end if;
  -- Liberada para retirada dentro de liberado_validade, sem entrega registrada (a da carteira já voltou acima).
  if v_so.status in ('completed', 'invoiced')
     and v_so.liberado_retirada_em is not null
     and v_so.liberado_retirada_em <= v_agora
     and v_so.liberado_retirada_em > v_agora - v_cfg.liberado_validade
     and v_so.delivered_at is null then
    return true;
  end if;
  return false;
end;
$$;

comment on function public._parceiro_os_viva(uuid, uuid, timestamptz) is
  'Retorno F4 (P3.1, regra 8): a OS existe, sem merged_into_id, criada até p_agora e viva: na carteira de hoje; ou rascunho com origem_parceiro_id deste parceiro; ou concluída/faturada com palavra de conclusão do dono ou da equipe dentro de fato_pronto_idade; ou liberada para retirada dentro de liberado_validade, sem delivered_at.';

revoke all on function public._parceiro_os_viva(uuid, uuid, timestamptz) from public, anon, authenticated;

-- A regra de ouro, com as condições 6 e 7 (aviso e 24 h) opcionais. p_sem_espera só é verdadeiro no destino do PDF com
-- pdf_sem_espera_ligado (P12.2): painel, pátio, eco e repassar seguem a regra inteira.
create or replace function public._parceiro_os_visivel(p_interessado uuid, p_agora timestamptz, p_sem_espera boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_oi public.os_interessados;
  v_pa public.parceiros;
  v_cl public.clients;
begin
  -- 1. A linha existe.
  select * into v_oi from public.os_interessados oi where oi.id = p_interessado;
  if not found then
    return jsonb_build_object('visivel', false, 'motivo', 'sem_linha');
  end if;
  -- 2. O parceiro está ativo.
  select * into v_pa from public.parceiros pa where pa.id = v_oi.parceiro_id;
  if not found or not v_pa.ativo then
    return jsonb_build_object('visivel', false, 'motivo', 'parceiro_inativo');
  end if;
  -- 3. Só papel comercial: a anfitriã nunca aparece; papel nulo é proposto de carteira.
  if v_oi.papel = 'anfitria' then
    return jsonb_build_object('visivel', false, 'motivo', 'anfitria');
  end if;
  if v_oi.papel is null or v_oi.papel not in ('indicou', 'contratante', 'pagador') then
    return jsonb_build_object('visivel', false, 'motivo', 'nao_confirmado');
  end if;
  -- 4. Confirmado pelo dono até agora.
  if v_oi.situacao is distinct from 'confirmado' or v_oi.confirmado_em is null or v_oi.confirmado_em > v_agora then
    return jsonb_build_object('visivel', false, 'motivo', 'nao_confirmado');
  end if;
  -- 5. Sem veto do par até agora (NÃO MP ou veto do dono, em qualquer OS do cliente).
  if public._parceiro_veto_de(v_oi.client_id, v_oi.parceiro_id, v_agora) is not null then
    return jsonb_build_object('visivel', false, 'motivo', 'veto');
  end if;
  -- 5a. Sem resposta ao aviso que pode ser um "não", à espera do dono.
  if v_oi.retido_em is not null and v_oi.retido_em <= v_agora then
    return jsonb_build_object('visivel', false, 'motivo', 'retido');
  end if;
  -- 5b. O cliente sem opt-out: é aqui que o PARAR dito depois do aviso fecha a OS.
  select * into v_cl from public.clients c where c.id = v_oi.client_id;
  if coalesce(v_cl.opt_out_whatsapp, false)
     or public.canal_bloqueado(coalesce(nullif(btrim(v_cl.whatsapp), ''), v_cl.phone)) is not null then
    return jsonb_build_object('visivel', false, 'motivo', 'opt_out');
  end if;
  if not coalesce(p_sem_espera, false) then
    -- 6. O cliente foi avisado (mensagem, pessoalmente, pela revenda ou a própria parceira), até agora.
    if v_oi.aviso_ao_cliente = 'nao_avisado' or v_oi.aviso_em is null or v_oi.aviso_em > v_agora then
      return jsonb_build_object('visivel', false, 'motivo', 'sem_aviso');
    end if;
    -- 7. As 24 h depois do aviso já passaram.
    if (v_oi.aviso_em + v_cfg.parceiro_aviso_espera <= v_agora) is not true then
      return jsonb_build_object('visivel', false, 'motivo', 'antes_de_24h');
    end if;
  end if;
  -- 8. A OS viva, e ainda do cliente do vínculo.
  if not public._parceiro_os_viva(v_oi.service_order_id, v_oi.parceiro_id, v_agora)
     or not exists (select 1 from public.service_orders so
                     where so.id = v_oi.service_order_id and so.client_id = v_oi.client_id) then
    return jsonb_build_object('visivel', false, 'motivo', 'os_fora');
  end if;
  -- 9. O cliente ativo e não genérico.
  if v_cl.id is null or not coalesce(v_cl.active, false) or coalesce(v_cl.generico, false) then
    return jsonb_build_object('visivel', false, 'motivo', 'cliente_fora');
  end if;
  -- 10.
  return jsonb_build_object('visivel', true, 'motivo', null);
end;
$$;

comment on function public._parceiro_os_visivel(uuid, timestamptz, boolean) is
  'Retorno F4 (P3.1): o corpo da regra de ouro. p_sem_espera pula só as condições 6 (sem_aviso) e 7 (antes_de_24h), e só o destino do PDF o passa, com pdf_sem_espera_ligado. Só lê.';

revoke all on function public._parceiro_os_visivel(uuid, timestamptz, boolean) from public, anon, authenticated;

create or replace function public.parceiro_os_visivel(p_interessado uuid, p_agora timestamptz default now())
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select public._parceiro_os_visivel(p_interessado, coalesce(p_agora, now()), false);
$$;

comment on function public.parceiro_os_visivel(uuid, timestamptz) is
  'Retorno F4 (C-OURO): {"visivel", "motivo"}. A 1ª que falha decide: sem_linha, parceiro_inativo, anfitria, nao_confirmado, veto, retido, opt_out, sem_aviso, antes_de_24h, os_fora, cliente_fora. Sem exceção para painel, pátio, eco, repassar e recibo que cita cliente. Só lê.';

revoke all on function public.parceiro_os_visivel(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_os_visivel(uuid, timestamptz) to service_role;

-- As OS que o parceiro pode ver agora: só vínculo comercial confirmado que passa na regra de ouro.
create or replace function public.parceiro_os_visiveis(p_parceiro uuid, p_agora timestamptz default now())
returns table (interessado_id uuid, service_order_id uuid, client_id uuid, vessel_id uuid, papel text)
language sql
stable
security definer
set search_path = public
as $$
  select oi.id, oi.service_order_id, oi.client_id, so.vessel_id, oi.papel
    from public.os_interessados oi
    join public.service_orders so on so.id = oi.service_order_id
   where oi.parceiro_id = p_parceiro
     and oi.situacao = 'confirmado'
     and oi.papel in ('indicou', 'contratante', 'pagador')
     and (public.parceiro_os_visivel(oi.id, coalesce(p_agora, now())) ->> 'visivel')::boolean is true
   order by so.service_order_number collate "C", oi.id;
$$;

comment on function public.parceiro_os_visiveis(uuid, timestamptz) is
  'Retorno F4 (P3.1): os vínculos do parceiro que passam em parceiro_os_visivel agora (nunca anfitriã, sem aviso, pausado ou de cliente genérico), na ordem do número da OS.';

revoke all on function public.parceiro_os_visiveis(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_os_visiveis(uuid, timestamptz) to service_role;

-- ── 2. O lote de vínculos, por sinal objetivo ──────────────────────────────────────────────────────────────────────────────

-- Um candidato por OS, pelo sinal mais forte (numero_do_pedido, unidade_anterior, propria, carteira). Nunca por nome e nunca
-- pela placa sozinha. Fora: par com linha em qualquer situação (o recusado nunca volta), cliente com veto do par, cliente
-- inativo ou genérico, e OS fora da regra 8. A carteira é só motorhome, para parceiro com pátio, e nasce sem papel: o pátio
-- não prova indicação (ag7-patio).
create or replace function public.parceiro_lote_candidatos(p_parceiro uuid, p_agora timestamptz default now(),
                                                           p_limite integer default 50)
returns table (service_order_id uuid, client_id uuid, sinal text, numero text, bem text, tem_telefone boolean,
               papel_proposto text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_pa public.parceiros;
  v_limite integer := least(greatest(coalesce(p_limite, 50), 0), 500);
begin
  select * into v_pa from public.parceiros pa where pa.id = p_parceiro;
  if not found or not v_pa.ativo then
    return;
  end if;

  return query
  with carteira as (
    select k.service_order_id as id from public.os_carteira((v_agora at time zone c_fuso)::date) k
  ), base as (
    select so.id, so.client_id, so.vessel_id, so.service_order_number, so.origem_parceiro_id, so.created_at,
           v.name as bem_nome,
           public._texto_simples(btrim(coalesce(v.asset_type, ''))) in ('motorhome', 'motor home') as motorhome,
           so.id in (select c.id from carteira c) as na_carteira,
           (select oi2.papel
              from public.os_interessados oi2
              join public.service_orders so2 on so2.id = oi2.service_order_id
             where oi2.parceiro_id = p_parceiro
               and oi2.situacao = 'confirmado'
               and oi2.papel in ('indicou', 'contratante', 'pagador')
               and oi2.client_id = so.client_id
               and so2.client_id = so.client_id
               and so2.vessel_id = so.vessel_id
               and so2.id <> so.id
               and so2.created_at < so.created_at
             order by so2.created_at desc, oi2.id
             limit 1) as papel_anterior,
           cl.whatsapp, cl.phone
      from public.service_orders so
      join public.clients cl on cl.id = so.client_id
      left join public.vessels v on v.id = so.vessel_id
     where so.merged_into_id is null
       and so.created_at <= v_agora
       and cl.active
       and not coalesce(cl.generico, false)
       and not exists (select 1 from public.os_interessados oi
                        where oi.service_order_id = so.id and oi.parceiro_id = p_parceiro)
       and (so.origem_parceiro_id = p_parceiro
            or (v_pa.client_id is not null and so.client_id = v_pa.client_id)
            or so.id in (select c.id from carteira c)
            or (so.vessel_id is not null
                and exists (select 1 from public.os_interessados oi3
                              join public.service_orders so3 on so3.id = oi3.service_order_id
                             where oi3.parceiro_id = p_parceiro
                               and oi3.situacao = 'confirmado'
                               and oi3.papel in ('indicou', 'contratante', 'pagador')
                               and so3.vessel_id = so.vessel_id
                               and so3.client_id = so.client_id)))
  ), sinais as (
    select b.*,
           case
             when b.origem_parceiro_id = p_parceiro then 'numero_do_pedido'
             when b.papel_anterior is not null then 'unidade_anterior'
             when v_pa.client_id is not null and b.client_id = v_pa.client_id then 'propria'
             when b.na_carteira and b.motorhome and v_pa.tipo in ('revenda_e_patio', 'patio') then 'carteira'
           end as o_sinal
      from base b
  )
  select s.id, s.client_id, s.o_sinal, s.service_order_number, s.bem_nome,
         public._agenda_chave_telefone(coalesce(nullif(btrim(s.whatsapp), ''), s.phone)) is not null,
         case s.o_sinal
           when 'numero_do_pedido' then 'indicou'
           when 'unidade_anterior' then s.papel_anterior
           when 'propria' then 'contratante'
         end
    from sinais s
   where s.o_sinal is not null
     and public._parceiro_veto_de(s.client_id, p_parceiro, v_agora) is null
     and public._parceiro_os_viva(s.id, p_parceiro, v_agora)
   order by case s.o_sinal when 'numero_do_pedido' then 1 when 'unidade_anterior' then 2 when 'propria' then 3 else 4 end,
            s.service_order_number collate "C" desc, s.id
   limit v_limite;
end;
$$;

comment on function public.parceiro_lote_candidatos(uuid, timestamptz, integer) is
  'Retorno F4 (C-LOTE): um candidato por OS, pelo sinal mais forte: numero_do_pedido (indicou), unidade_anterior (o papel do vínculo comercial confirmado da mesma unidade e cliente), propria (contratante), carteira (motorhome, parceiro com pátio, sem papel). Nunca por nome nem pela placa sozinha. Exclui par com linha, veto do par, cliente inativo ou genérico e OS fora da regra 8. bem é vessels.name: só o dono lê.';

revoke all on function public.parceiro_lote_candidatos(uuid, timestamptz, integer) from public, anon, authenticated;
grant execute on function public.parceiro_lote_candidatos(uuid, timestamptz, integer) to service_role;

-- O lote vira proposto, e cada vínculo novo entra na fila do cartão (vinculo). Nunca confirma. O par com linha em qualquer
-- situação nunca é regravado: a chamada é idempotente, e o recusado nunca volta.
create or replace function public.parceiro_propor(p_itens jsonb, p_autor uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_propostos jsonb := '[]'::jsonb;
  v_recusados jsonb := '[]'::jsonb;
  v_item jsonb;
  v_os uuid;
  v_parceiro uuid;
  v_client uuid;
  v_origem text;
  v_papel text;
  v_pessoa uuid;
  v_so record;
  v_id uuid;
  v_agora timestamptz := now();
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    raise exception using errcode = '42501', message = 'parceiro_propor: só o dono';
  end if;
  if jsonb_typeof(p_itens) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'parceiro_propor: p_itens tem de ser uma lista';
  end if;

  for v_item in select e from jsonb_array_elements(p_itens) e loop
    if jsonb_typeof(v_item) is distinct from 'object' then
      raise exception using errcode = '22023', message = 'parceiro_propor: item que não é objeto';
    end if;
    v_os := nullif(v_item ->> 'service_order_id', '')::uuid;
    v_parceiro := nullif(v_item ->> 'parceiro_id', '')::uuid;
    v_client := nullif(v_item ->> 'client_id', '')::uuid;
    v_origem := v_item ->> 'origem';
    v_papel := nullif(v_item ->> 'papel', '');
    v_pessoa := nullif(v_item ->> 'pessoa_id', '')::uuid;
    if v_os is null or v_parceiro is null
       or v_origem is null or v_origem not in ('numero_do_pedido', 'unidade_anterior', 'propria', 'carteira', 'dono') then
      raise exception using errcode = '22023', message = 'parceiro_propor: falta OS, parceiro ou origem válida';
    end if;
    -- O papel nulo só vale na carteira e no *parceiro 74*: o dono escolhe pela letra.
    if (v_papel is null and v_origem not in ('carteira', 'dono'))
       or (v_papel is not null and v_papel not in ('indicou', 'contratante', 'pagador')) then
      raise exception using errcode = '22023', message = 'parceiro_propor: papel fora da regra para a origem';
    end if;

    select so.id, so.client_id into v_so from public.service_orders so where so.id = v_os;
    if not found or v_so.client_id is null or (v_client is not null and v_client is distinct from v_so.client_id) then
      v_recusados := v_recusados || jsonb_build_array(jsonb_build_object('service_order_id', v_os, 'motivo', 'os_fora'));
      continue;
    end if;
    v_client := v_so.client_id;
    if exists (select 1 from public.os_interessados oi where oi.service_order_id = v_os and oi.parceiro_id = v_parceiro) then
      v_recusados := v_recusados || jsonb_build_array(jsonb_build_object('service_order_id', v_os, 'motivo', 'ja_decidido'));
      continue;
    end if;
    if public._parceiro_veto_de(v_client, v_parceiro, v_agora) is not null then
      v_recusados := v_recusados || jsonb_build_array(jsonb_build_object('service_order_id', v_os, 'motivo', 'veto'));
      continue;
    end if;
    if not exists (select 1 from public.parceiros pa where pa.id = v_parceiro and pa.ativo)
       or not public._parceiro_os_viva(v_os, v_parceiro, v_agora) then
      v_recusados := v_recusados || jsonb_build_array(jsonb_build_object('service_order_id', v_os, 'motivo', 'os_fora'));
      continue;
    end if;

    v_id := null;
    insert into public.os_interessados (service_order_id, parceiro_id, client_id, pessoa_id, papel, situacao, origem)
    values (v_os, v_parceiro, v_client, v_pessoa, v_papel, 'proposto', v_origem)
    on conflict do nothing
    returning id into v_id;
    if v_id is null then
      v_recusados := v_recusados || jsonb_build_array(jsonb_build_object('service_order_id', v_os, 'motivo', 'ja_decidido'));
      continue;
    end if;
    perform public._parceiro_fila_por('vinculo', v_parceiro, v_id, 'vinculo:' || v_id, null,
                                      jsonb_build_object('service_order_id', v_os, 'origem', v_origem));
    v_propostos := v_propostos || jsonb_build_array(jsonb_build_object('service_order_id', v_os, 'interessado_id', v_id));
  end loop;

  return jsonb_build_object('propostos', v_propostos, 'recusados', v_recusados);
end;
$$;

comment on function public.parceiro_propor(jsonb, uuid) is
  'Retorno F4 (P3.1): grava cada item como proposto (nunca confirmado) e põe vinculo na fila do cartão. Só o dono (42501). Papel nulo só com origem carteira ou dono. Par com linha em qualquer situação → recusados/ja_decidido; veto do par → veto; OS fora da regra 8, de outro cliente ou parceiro inativo → os_fora. Idempotente.';

revoke all on function public.parceiro_propor(jsonb, uuid) from public, anon, authenticated;
grant execute on function public.parceiro_propor(jsonb, uuid) to service_role;

-- ── 3. Confirmar, requalificar e cortar (só pelo cartão do dono, P8) ──────────────────────────────────────────────────────

-- O vínculo proposto vira confirmado com o papel final. Anfitriã: sem aviso. OS da própria parceira: o aviso é ela mesma
-- (proprio_parceiro), antes de qualquer tentativa de aviso. Com telefone utilizável: parceiro_aviso_agendar (P6). Sem ele:
-- a letra (pessoalmente ou pela revenda) grava o aviso agora; sem letra, fica nao_avisado e o item aviso entra na fila.
create or replace function public._parceiro_confirmar(p_interessado uuid, p_autor uuid, p_aviso text, p_agora timestamptz,
                                                      p_papel text default null, p_pessoa uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_oi public.os_interessados;
  v_pa public.parceiros;
  v_cl public.clients;
  v_so record;
  v_papel text;
  v_av jsonb;
  v_aviso text;
begin
  -- 1. Só o dono.
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    raise exception using errcode = '42501', message = 'parceiro_confirmar: só o dono';
  end if;
  if p_aviso is not null and p_aviso not in ('pessoalmente', 'pela_revenda') then
    raise exception using errcode = '22023', message = 'parceiro_confirmar: aviso fora da lista';
  end if;
  if p_papel is not null and p_papel not in ('indicou', 'contratante', 'pagador', 'anfitria') then
    raise exception using errcode = '22023', message = 'parceiro_confirmar: papel fora da lista';
  end if;

  -- 2. O vínculo proposto, a OS na regra 8, o cliente na regra 9 e o papel final.
  select * into v_oi from public.os_interessados oi where oi.id = p_interessado for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sem_vinculo');
  end if;
  if v_oi.situacao is distinct from 'proposto' then
    return jsonb_build_object('ok', false, 'motivo', 'nao_proposto');
  end if;
  select * into v_pa from public.parceiros pa where pa.id = v_oi.parceiro_id;
  if not found or not v_pa.ativo then
    return jsonb_build_object('ok', false, 'motivo', 'parceiro_inativo');
  end if;
  if not public._parceiro_os_viva(v_oi.service_order_id, v_oi.parceiro_id, v_agora) then
    return jsonb_build_object('ok', false, 'motivo', 'os_fora');
  end if;
  select so.id, so.client_id into v_so from public.service_orders so where so.id = v_oi.service_order_id;
  select * into v_cl from public.clients c where c.id = v_oi.client_id;
  if v_cl.id is null or not coalesce(v_cl.active, false) or coalesce(v_cl.generico, false)
     or v_so.client_id is distinct from v_oi.client_id then
    return jsonb_build_object('ok', false, 'motivo', 'cliente_fora');
  end if;
  if public._parceiro_veto_de(v_oi.client_id, v_oi.parceiro_id, v_agora) is not null then
    return jsonb_build_object('ok', false, 'motivo', 'veto');
  end if;
  v_papel := coalesce(p_papel, v_oi.papel);
  if v_papel is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_papel');
  end if;

  update public.os_interessados oi
     set situacao = 'confirmado',
         papel = v_papel,
         pacote = case when v_papel in ('contratante', 'pagador') then 'completo' else 'status' end,
         pessoa_id = coalesce(p_pessoa, oi.pessoa_id),
         confirmado_por = p_autor,
         confirmado_em = v_agora
   where oi.id = v_oi.id;

  -- 3. A anfitriã: confirma sem aviso, e a OS nunca aparece.
  if v_papel = 'anfitria' then
    return jsonb_build_object('ok', true, 'interessado_id', v_oi.id, 'papel', v_papel, 'aviso', 'nenhum');
  end if;

  -- 4. A OS da própria parceira: ela nunca recebe NÃO MP sobre si mesma. Vem antes dos passos 5 e 6.
  if v_pa.client_id is not null and v_so.client_id = v_pa.client_id then
    update public.os_interessados oi
       set aviso_ao_cliente = 'proprio_parceiro', aviso_em = v_agora
     where oi.id = v_oi.id;
    return jsonb_build_object('ok', true, 'interessado_id', v_oi.id, 'papel', v_papel, 'aviso', 'proprio_parceiro');
  end if;

  -- 5. Com telefone utilizável, o aviso ao cliente (P6); o vínculo segue nao_avisado até a mensagem sair.
  v_av := public.parceiro_aviso_agendar(v_oi.id, v_agora);
  if coalesce((v_av ->> 'ok')::boolean, false) then
    return jsonb_build_object('ok', true, 'interessado_id', v_oi.id, 'papel', v_papel, 'aviso', 'agendado',
                              'saida_id', v_av -> 'saida_id');
  end if;

  -- 6. Sem telefone utilizável: a letra registra o aviso agora; sem letra, o item aviso entra na fila.
  if p_aviso is not null then
    update public.os_interessados oi
       set aviso_ao_cliente = p_aviso, aviso_em = v_agora
     where oi.id = v_oi.id;
    v_aviso := p_aviso;
  else
    perform public._parceiro_fila_por('aviso', v_oi.parceiro_id, v_oi.id, 'aviso:' || v_oi.id, null,
                                      jsonb_build_object('service_order_id', v_oi.service_order_id));
    v_aviso := 'pendente';
  end if;
  return jsonb_build_object('ok', true, 'interessado_id', v_oi.id, 'papel', v_papel, 'aviso', v_aviso,
                            'motivo_aviso', v_av ->> 'motivo');
end;
$$;

comment on function public._parceiro_confirmar(uuid, uuid, text, timestamptz, text, uuid) is
  'Retorno F4 (P3.1): confirma o vínculo proposto (só o dono, 42501). Papel final = coalesce(p_papel, papel); nulo → {ok: false, motivo: sem_papel}. Anfitriã sem aviso; OS da própria parceira → proprio_parceiro e aviso_em agora; com telefone, parceiro_aviso_agendar (P6); sem telefone, p_aviso pessoalmente/pela_revenda grava o aviso agora, e sem letra o item aviso entra na fila.';

revoke all on function public._parceiro_confirmar(uuid, uuid, text, timestamptz, text, uuid) from public, anon, authenticated;

-- A opção B e o PDF à mão: troca o papel (e o pacote) de um vínculo confirmado. Nunca passa de proposto a confirmado; recusa
-- a anfitriã nos dois sentidos. Audita com action 'update' (audit_log_action_check não tem 'insert').
create or replace function public.parceiro_requalificar(p_interessado uuid, p_papel text, p_autor uuid,
                                                        p_base text default 'decisao_do_dono',
                                                        p_agora timestamptz default now(), p_pessoa uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_oi public.os_interessados;
  v_novo public.os_interessados;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    raise exception using errcode = '42501', message = 'parceiro_requalificar: só o dono';
  end if;
  if p_papel is null or p_papel not in ('indicou', 'contratante', 'pagador', 'anfitria') then
    raise exception using errcode = '22023', message = 'parceiro_requalificar: papel fora da lista';
  end if;
  if p_base is null or p_base not in ('legitimo_interesse', 'contrato', 'consentimento', 'decisao_do_dono') then
    raise exception using errcode = '22023', message = 'parceiro_requalificar: base fora da lista';
  end if;
  select * into v_oi from public.os_interessados oi where oi.id = p_interessado for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sem_vinculo');
  end if;
  if v_oi.situacao is distinct from 'confirmado' then
    return jsonb_build_object('ok', false, 'motivo', 'nao_confirmado');
  end if;
  if v_oi.papel = 'anfitria' or p_papel = 'anfitria' then
    return jsonb_build_object('ok', false, 'motivo', 'anfitria');
  end if;

  update public.os_interessados oi
     set papel = p_papel,
         pacote = case when p_papel in ('contratante', 'pagador') then 'completo'
                       when oi.pacote = 'completo' then 'status'
                       else oi.pacote end,
         base = p_base,
         pessoa_id = coalesce(p_pessoa, oi.pessoa_id),
         decidido_motivo = left('requalificado pelo dono: ' || coalesce(oi.papel, '') || ' → ' || p_papel, 500)
   where oi.id = v_oi.id
   returning * into v_novo;

  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('os_interessados', v_oi.id, 'update', 'dono',
          jsonb_build_object('papel', v_oi.papel, 'pacote', v_oi.pacote, 'base', v_oi.base, 'pessoa_id', v_oi.pessoa_id),
          jsonb_build_object('papel', v_novo.papel, 'pacote', v_novo.pacote, 'base', v_novo.base, 'pessoa_id', v_novo.pessoa_id),
          'Retorno F4: vínculo do parceiro requalificado pelo dono');

  return jsonb_build_object('ok', true, 'interessado_id', v_oi.id, 'papel', v_novo.papel, 'pacote', v_novo.pacote,
                            'base', v_novo.base);
end;
$$;

comment on function public.parceiro_requalificar(uuid, text, uuid, text, timestamptz, uuid) is
  'Retorno F4 (P3.1): troca o papel e o pacote (completo se contratante ou pagador) de um vínculo confirmado, grava a base (padrão decisao_do_dono) e a pessoa, e audita (audit_log, action update, changed_by dono). Só o dono (42501). Recusa proposto e anfitriã.';

revoke all on function public.parceiro_requalificar(uuid, text, uuid, text, timestamptz, uuid) from public, anon, authenticated;
grant execute on function public.parceiro_requalificar(uuid, text, uuid, text, timestamptz, uuid) to service_role;

-- O item corte: pausar, retomar, recusar (para sempre) ou o veto do dono (vale para as OS seguintes do cliente). Em qualquer
-- parceiro_modo. As saídas agendadas caem pela regra de ouro na rodada seguinte.
create or replace function public.parceiro_vinculo_cortar(p_interessado uuid, p_acao text, p_autor uuid,
                                                          p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_oi public.os_interessados;
  v_novo public.os_interessados;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    raise exception using errcode = '42501', message = 'parceiro_vinculo_cortar: só o dono';
  end if;
  if p_acao is null or p_acao not in ('pausar', 'retomar', 'recusar', 'veto_dono') then
    raise exception using errcode = '22023', message = 'parceiro_vinculo_cortar: ação fora da lista';
  end if;
  select * into v_oi from public.os_interessados oi where oi.id = p_interessado for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sem_vinculo');
  end if;

  if p_acao = 'pausar' then
    if v_oi.situacao is distinct from 'confirmado' then
      return jsonb_build_object('ok', false, 'motivo', 'nao_confirmado');
    end if;
    update public.os_interessados oi set situacao = 'pausado' where oi.id = v_oi.id returning * into v_novo;
  elsif p_acao = 'retomar' then
    if v_oi.situacao is distinct from 'pausado' then
      return jsonb_build_object('ok', false, 'motivo', 'nao_pausado');
    end if;
    -- volta a confirmado com o aviso de antes: aviso_em não muda
    update public.os_interessados oi set situacao = 'confirmado' where oi.id = v_oi.id returning * into v_novo;
  elsif p_acao = 'recusar' then
    update public.os_interessados oi
       set situacao = 'recusado', decidido_motivo = 'recusado pelo dono'
     where oi.id = v_oi.id
     returning * into v_novo;
  else
    insert into public.parceiro_vetos (client_id, parceiro_id, em, origem)
    values (v_oi.client_id, v_oi.parceiro_id, v_agora, 'dono')
    on conflict (client_id, parceiro_id) do nothing;
    update public.os_interessados oi
       set veto_do_cliente_em = coalesce(oi.veto_do_cliente_em, v_agora)
     where oi.client_id = v_oi.client_id and oi.parceiro_id = v_oi.parceiro_id;
    select * into v_novo from public.os_interessados oi where oi.id = v_oi.id;
  end if;

  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('os_interessados', v_oi.id, 'update', 'dono',
          jsonb_build_object('situacao', v_oi.situacao, 'veto_do_cliente_em', v_oi.veto_do_cliente_em),
          jsonb_build_object('situacao', v_novo.situacao, 'veto_do_cliente_em', v_novo.veto_do_cliente_em, 'acao', p_acao),
          'Retorno F4: vínculo do parceiro cortado pelo dono (' || p_acao || ')');

  return jsonb_build_object('ok', true, 'interessado_id', v_oi.id, 'situacao', v_novo.situacao, 'acao', p_acao);
end;
$$;

comment on function public.parceiro_vinculo_cortar(uuid, text, uuid, timestamptz) is
  'Retorno F4 (C-CORTE): pausar (confirmado → pausado), retomar (pausado → confirmado, aviso_em não muda), recusar (recusado, para sempre) ou veto_dono (parceiro_vetos origem dono + veto_do_cliente_em em todos os vínculos do par). Só o dono (42501). Audita com action update. Vale em qualquer parceiro_modo.';

revoke all on function public.parceiro_vinculo_cortar(uuid, text, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_vinculo_cortar(uuid, text, uuid, timestamptz) to service_role;

-- ── 4. O destino do PDF ao parceiro (P12.2) ────────────────────────────────────────────────────────────────────────────────

-- A regra do documento, separada da de status: papel contratante ou pagador, confirmado e as condições 1 a 5, 5a, 5b, 8 e 9
-- da regra de ouro; aviso e 24 h também, salvo pdf_sem_espera_ligado (dúvida 9). O número é um só: pagador, o número
-- financeiro do parceiro; contratante, o recebe_documento da pessoa do vínculo (sem pessoa, o único do parceiro). Nenhum ou
-- mais de um: destino_ambiguo. Nunca por nome.
create or replace function public.parceiro_destino_do_pdf(p_os uuid, p_autor uuid, p_parceiro uuid default null,
                                                          p_agora timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_oi public.os_interessados;
  v_pa public.parceiros;
  v_n integer;
  v_vis jsonb;
  v_motivo text;
  v_num record;
  v_qtd integer;
  v_so_cliente uuid;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    raise exception using errcode = '42501', message = 'parceiro_destino_do_pdf: só o dono';
  end if;
  if v_cfg.id is null or not v_cfg.pdf_parceiro_ligado then
    return jsonb_build_object('ok', false, 'motivo', 'desligado',
                              'frase', 'O envio de PDF ao parceiro está desligado; nada saiu.');
  end if;

  -- O vínculo comercial da OS (p_parceiro nulo só com um).
  select count(*) into v_n
    from public.os_interessados oi
   where oi.service_order_id = p_os
     and oi.papel is distinct from 'anfitria'
     and (p_parceiro is null or oi.parceiro_id = p_parceiro);
  if v_n = 0 then
    return jsonb_build_object('ok', false, 'motivo', 'sem_vinculo',
                              'frase', 'Esta OS não tem vínculo com o parceiro; nada saiu.');
  end if;
  if v_n > 1 then
    return jsonb_build_object('ok', false, 'motivo', 'destino_ambiguo',
                              'frase', 'Esta OS tem mais de um parceiro; diga qual. Nada saiu.');
  end if;
  select * into v_oi
    from public.os_interessados oi
   where oi.service_order_id = p_os
     and oi.papel is distinct from 'anfitria'
     and (p_parceiro is null or oi.parceiro_id = p_parceiro);
  select * into v_pa from public.parceiros pa where pa.id = v_oi.parceiro_id;

  if v_oi.papel is null or v_oi.papel not in ('contratante', 'pagador') then
    return jsonb_build_object('ok', false, 'motivo', 'papel',
                              'frase', format('A %s só indicou este cliente: o PDF com valor não vai a ela. Nada saiu.', v_pa.sigla));
  end if;
  v_vis := public._parceiro_os_visivel(v_oi.id, v_agora, v_cfg.pdf_sem_espera_ligado);
  if not coalesce((v_vis ->> 'visivel')::boolean, false) then
    v_motivo := v_vis ->> 'motivo';
    return jsonb_build_object('ok', false, 'motivo', v_motivo,
      'frase', case v_motivo
                 when 'veto' then format('O cliente pediu que a %s não acompanhe. Nada saiu.', v_pa.sigla)
                 when 'opt_out' then 'O cliente pediu para não receber mensagens. Nada saiu.'
                 when 'nao_confirmado' then format('O vínculo com a %s ainda não foi confirmado. Nada saiu.', v_pa.sigla)
                 when 'sem_aviso' then format('O PDF à %s só sai depois do aviso ao cliente e de 24 h. Nada saiu.', v_pa.sigla)
                 when 'antes_de_24h' then format('O PDF à %s só sai depois do aviso ao cliente e de 24 h. Nada saiu.', v_pa.sigla)
                 else format('Esta OS não está liberada para a %s. Nada saiu.', v_pa.sigla)
               end);
  end if;

  -- O número: exatamente um, confirmado, de pessoa ativa.
  if v_oi.papel = 'pagador' then
    select count(*) into v_qtd
      from public.parceiro_numeros n join public.parceiro_pessoas p on p.id = n.pessoa_id
     where p.parceiro_id = v_pa.id and p.ativo and n.situacao = 'confirmado' and n.uso = 'financeiro';
    select n.phone_normalized, n.chave, n.rotulo, p.nome into v_num
      from public.parceiro_numeros n join public.parceiro_pessoas p on p.id = n.pessoa_id
     where p.parceiro_id = v_pa.id and p.ativo and n.situacao = 'confirmado' and n.uso = 'financeiro'
     order by n.id
     limit 1;
  else
    select count(*) into v_qtd
      from public.parceiro_numeros n join public.parceiro_pessoas p on p.id = n.pessoa_id
     where p.parceiro_id = v_pa.id and p.ativo and n.situacao = 'confirmado' and n.recebe_documento
       and (v_oi.pessoa_id is null or n.pessoa_id = v_oi.pessoa_id);
    select n.phone_normalized, n.chave, n.rotulo, p.nome into v_num
      from public.parceiro_numeros n join public.parceiro_pessoas p on p.id = n.pessoa_id
     where p.parceiro_id = v_pa.id and p.ativo and n.situacao = 'confirmado' and n.recebe_documento
       and (v_oi.pessoa_id is null or n.pessoa_id = v_oi.pessoa_id)
     order by n.id
     limit 1;
  end if;
  if v_qtd is distinct from 1 then
    return jsonb_build_object('ok', false, 'motivo', 'destino_ambiguo',
                              'frase', format('Não sei qual número da %s recebe este PDF; nada saiu.', v_pa.sigla));
  end if;

  select so.client_id into v_so_cliente from public.service_orders so where so.id = p_os;
  return jsonb_build_object(
    'ok', true,
    'phone', v_num.phone_normalized,
    'chave8', v_num.chave,
    'rotulo', format('%s (%s, ••%s)', v_pa.sigla,
                     coalesce(nullif(btrim(v_num.rotulo), ''), nullif(btrim(v_num.nome), ''), 'comercial'), right(v_num.chave, 4)),
    'papel', v_oi.papel,
    'interessado_id', v_oi.id,
    'parceiro_id', v_pa.id,
    -- na OS da própria parceira os dados são dela: a via não precisa ser reduzida
    'reduzir', v_so_cliente is distinct from v_pa.client_id);
end;
$$;

comment on function public.parceiro_destino_do_pdf(uuid, uuid, uuid, timestamptz) is
  'Retorno F4 (C-DESTINO, P12.2): {"ok": true, "phone", "chave8", "rotulo", "papel", "interessado_id", "parceiro_id", "reduzir"} ou {"ok": false, "motivo", "frase"}. Só o dono (42501); desligado sem pdf_parceiro_ligado. Papel contratante ou pagador, a regra de ouro (aviso e 24 h dispensáveis só com pdf_sem_espera_ligado) e exatamente um número: pagador → uso financeiro; contratante → recebe_documento da pessoa do vínculo (sem pessoa, o único do parceiro). Senão destino_ambiguo.';

revoke all on function public.parceiro_destino_do_pdf(uuid, uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_destino_do_pdf(uuid, uuid, uuid, timestamptz) to service_role;

-- ── 5. A semente dos números (seção 8.2) ───────────────────────────────────────────────────────────────────────────────────

-- Chamada uma vez pela sessão que coordena, com os números que o dono confirmou. Idempotente: parceiro pela sigla
-- (_texto_simples), pessoa por parceiro, papel e nome, número pela chave viva. Cada número vira confirmado e entra em
-- agenda_detector_exclusions em cada forma do telefone (as de whatsapp_messages com a mesma chave e a de 13 dígitos), sem
-- número solto no repositório. Item recusado não derruba os outros.
create or replace function public.parceiro_semear(p_itens jsonb, p_autor uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_parceiros integer := 0;
  v_pessoas integer := 0;
  v_numeros integer := 0;
  v_atualizados integer := 0;
  v_recusados jsonb := '[]'::jsonb;
  v_par jsonb;
  v_pes jsonb;
  v_num jsonb;
  v_sigla text;
  v_nome text;
  v_tipo text;
  v_client uuid;
  v_parceiro uuid;
  v_pessoa uuid;
  v_pnome text;
  v_ppapel text;
  v_tel text;
  v_fone text;
  v_chave text;
  v_ddd text;
  v_final text;
  v_existente record;
  v_achou boolean;
  v_forma text;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    raise exception using errcode = '42501', message = 'parceiro_semear: só o dono';
  end if;
  if jsonb_typeof(p_itens) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'parceiro_semear: p_itens tem de ser uma lista';
  end if;

  for v_par in select e from jsonb_array_elements(p_itens) e loop
    v_sigla := btrim(v_par ->> 'sigla');
    v_nome := btrim(v_par ->> 'nome');
    v_tipo := v_par ->> 'tipo';
    v_client := nullif(v_par ->> 'client_id', '')::uuid;
    if jsonb_typeof(v_par) is distinct from 'object' or coalesce(v_nome, '') = ''
       or coalesce(v_sigla, '') !~ '^[A-Za-zÀ-ÿ]{2,12}$'
       or v_tipo is null or v_tipo not in ('revenda', 'revenda_e_patio', 'patio', 'seguradora')
       or jsonb_typeof(v_par -> 'pessoas') is distinct from 'array' then
      v_recusados := v_recusados || jsonb_build_array(jsonb_build_object('final', null, 'motivo', 'campo_faltando'));
      continue;
    end if;

    select pa.id into v_parceiro from public.parceiros pa where public._texto_simples(pa.sigla) = public._texto_simples(v_sigla);
    if found then
      update public.parceiros pa
         set nome = v_nome, tipo = v_tipo, client_id = coalesce(v_client, pa.client_id), ativo = true
       where pa.id = v_parceiro;
    else
      insert into public.parceiros (nome, sigla, tipo, client_id) values (v_nome, v_sigla, v_tipo, v_client)
      returning id into v_parceiro;
      v_parceiros := v_parceiros + 1;
    end if;

    for v_pes in select e from jsonb_array_elements(v_par -> 'pessoas') e loop
      v_pnome := nullif(btrim(v_pes ->> 'nome'), '');
      v_ppapel := v_pes ->> 'papel';
      if jsonb_typeof(v_pes) is distinct from 'object'
         or v_ppapel is null or v_ppapel not in ('comercial', 'financeiro', 'dono', 'recepcao')
         or jsonb_typeof(v_pes -> 'numeros') is distinct from 'array' then
        v_recusados := v_recusados || jsonb_build_array(jsonb_build_object('final', null, 'motivo', 'campo_faltando'));
        continue;
      end if;
      select p.id into v_pessoa
        from public.parceiro_pessoas p
       where p.parceiro_id = v_parceiro and p.papel = v_ppapel and coalesce(p.nome, '') = coalesce(v_pnome, '')
       order by p.criado_em, p.id
       limit 1;
      if not found then
        insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_parceiro, v_pnome, v_ppapel)
        returning id into v_pessoa;
        v_pessoas := v_pessoas + 1;
      else
        update public.parceiro_pessoas p set ativo = true where p.id = v_pessoa;
      end if;

      for v_num in select e from jsonb_array_elements(v_pes -> 'numeros') e loop
        v_tel := regexp_replace(coalesce(v_num ->> 'telefone', ''), '\D', '', 'g');
        v_final := case when v_tel <> '' then '••' || right(v_tel, 4) end;
        -- uso, recebe_painel e recebe_documento são obrigatórios
        if jsonb_typeof(v_num) is distinct from 'object'
           or coalesce(v_num ->> 'uso', '') not in ('comercial', 'pessoal', 'financeiro')
           or jsonb_typeof(v_num -> 'recebe_painel') is distinct from 'boolean'
           or jsonb_typeof(v_num -> 'recebe_documento') is distinct from 'boolean'
           or char_length(coalesce(v_num ->> 'rotulo', '')) > 60 then
          v_recusados := v_recusados || jsonb_build_array(jsonb_build_object('final', v_final, 'motivo', 'campo_faltando'));
          continue;
        end if;
        if v_tel !~ '^[0-9]{10,13}$' or public._ddd_do_telefone(v_tel) is null then
          v_recusados := v_recusados || jsonb_build_array(jsonb_build_object('final', v_final, 'motivo', 'telefone_invalido'));
          continue;
        end if;
        v_fone := case when v_tel ~ '^55[0-9]{10,11}$' then v_tel else '55' || v_tel end;
        v_chave := public._agenda_chave_telefone(v_fone);
        v_ddd := public._ddd_do_telefone(v_fone);
        -- o número da equipe nunca é de parceiro
        if exists (select 1 from public.app_users u
                    where u.active
                      and (public._mesmo_telefone(v_fone, u.phone_normalized) or public._mesmo_telefone(v_fone, u.phone)))
           or exists (select 1 from public.payees py where py.active and public._mesmo_telefone(v_fone, py.phone)) then
          v_recusados := v_recusados || jsonb_build_array(jsonb_build_object('final', v_final, 'motivo', 'numero_da_equipe'));
          continue;
        end if;

        select n.id, p.parceiro_id into v_existente
          from public.parceiro_numeros n
          join public.parceiro_pessoas p on p.id = n.pessoa_id
         where n.chave = v_chave and n.situacao in ('proposto', 'confirmado', 'pausado')
         limit 1;
        v_achou := found;
        if v_achou and v_existente.parceiro_id is distinct from v_parceiro then
          v_recusados := v_recusados || jsonb_build_array(jsonb_build_object('final', v_final, 'motivo', 'numero_de_outro_parceiro'));
          continue;
        end if;

        begin
          if v_achou then
            update public.parceiro_numeros n
               set pessoa_id = v_pessoa, phone_normalized = v_fone, ddd = v_ddd,
                   rotulo = nullif(btrim(v_num ->> 'rotulo'), ''), uso = v_num ->> 'uso',
                   recebe_painel = (v_num ->> 'recebe_painel')::boolean,
                   recebe_documento = (v_num ->> 'recebe_documento')::boolean,
                   situacao = 'confirmado', confirmado_por = coalesce(n.confirmado_por, p_autor),
                   confirmado_em = coalesce(n.confirmado_em, now())
             where n.id = v_existente.id;
            v_atualizados := v_atualizados + 1;
          else
            insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, rotulo, uso, recebe_painel,
                                                 recebe_documento, situacao, confirmado_por, confirmado_em)
            values (v_pessoa, v_fone, v_chave, v_ddd, nullif(btrim(v_num ->> 'rotulo'), ''), v_num ->> 'uso',
                    (v_num ->> 'recebe_painel')::boolean, (v_num ->> 'recebe_documento')::boolean, 'confirmado', p_autor, now());
            v_numeros := v_numeros + 1;
          end if;
        exception when unique_violation then
          -- dois números que recebem documento na mesma pessoa, ou a chave que outro número tomou entre a leitura e a escrita
          v_recusados := v_recusados || jsonb_build_array(jsonb_build_object('final', v_final, 'motivo', 'conflito'));
          continue;
        end;

        -- O detector da agenda compara phone_normalized por igualdade: uma linha por forma (13 e 12 dígitos).
        for v_forma in
          select distinct w.phone_normalized
            from public.whatsapp_messages w
           where public._agenda_chave_telefone(w.phone_normalized) = v_chave
             and w.phone_normalized is not null
          union
          select '55' || v_ddd || '9' || v_chave
          union
          select v_fone
        loop
          insert into public.agenda_detector_exclusions (phone_normalized, label, reason, created_by)
          values (v_forma, 'parceiro', 'Retorno F4: número de parceiro confirmado pelo dono (semente)', p_autor)
          on conflict (phone_normalized) do nothing;
        end loop;
      end loop;
    end loop;
  end loop;

  return jsonb_build_object('ok', true, 'parceiros', v_parceiros, 'pessoas', v_pessoas, 'numeros', v_numeros,
                            'atualizados', v_atualizados, 'recusados', v_recusados);
end;
$$;

comment on function public.parceiro_semear(jsonb, uuid) is
  'Retorno F4 (P3.1, seção 8.2): grava parceiros, pessoas e números confirmados a partir do JSON do dono. Só o dono (42501). Idempotente (sigla, pessoa por papel e nome, número pela chave viva: atualiza rótulo, uso, recebe_painel e recebe_documento). Recusados por número, com o final ••nnnn: telefone_invalido, numero_de_outro_parceiro, numero_da_equipe, campo_faltando (e conflito, unique de recebe_documento). Cada forma do telefone entra em agenda_detector_exclusions.';

revoke all on function public.parceiro_semear(jsonb, uuid) from public, anon, authenticated;
grant execute on function public.parceiro_semear(jsonb, uuid) to service_role;

-- ── 6. Os números fora do assistente (P12.4) ───────────────────────────────────────────────────────────────────────────────

-- Vazio com parceiro_historico_na_ia verdadeiro; senão as chaves dos números confirmados. Sem a linha de configuração: as
-- chaves (falha fecha). Não lê corpo nem telefone do chamador.
create or replace function public.parceiro_numeros_fora_da_ia()
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select case
    when coalesce((select c.parceiro_historico_na_ia from public.retorno_config c where c.id), false) then '{}'::text[]
    else coalesce((select array_agg(distinct n.chave order by n.chave)
                     from public.parceiro_numeros n
                    where n.situacao = 'confirmado'), '{}'::text[])
  end;
$$;

comment on function public.parceiro_numeros_fora_da_ia() is
  'Retorno F4 (P12.4): as chaves de 8 dígitos dos números de parceiro confirmados, que o assistente não lê enquanto retorno_config.parceiro_historico_na_ia é falso (o padrão). Vazio com a chave verdadeira.';

revoke all on function public.parceiro_numeros_fora_da_ia() from public, anon, authenticated;
grant execute on function public.parceiro_numeros_fora_da_ia() to service_role;

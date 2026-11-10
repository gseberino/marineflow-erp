-- Retorno rápido ao cliente, F4 (P6): o aviso ao cliente final e o NÃO MP. Nada liga aqui.
--
-- 1. parceiro_aviso_agendar (C-AVISO): o aviso ao cliente (Q01–Q05) de um vínculo confirmado, um por par cliente ×
--    parceiro. Antes de agendar, o telefone do cliente passa por quem_escreve: segue só com papel 'cliente' e o mesmo
--    cliente, e nunca com o número em parceiro_numeros. Sem telefone, número compartilhado ou sem nome: recusa, e o vínculo
--    nao_avisado vai ao item aviso da fila do cartão (P8.1). Já havendo aviso enviado do par, o vínculo herda aviso_saida_id
--    (e aviso_em, se nao_avisado) e nada sai de novo. Enquanto o 1º não sai, a chave do par barra o 2º, e o vínculo novo
--    entra nas listas da saída que espera.
-- 2. parceiro_aviso_rodada (no vigia): avisa os vínculos com telefone e sem aviso real, inclusive o registrado
--    "pessoalmente" ou "pela revenda" que ganhou telefone (sem nova carência), e põe na fila o item
--    aviso:<interessado>:<saida> de todo aviso real recusado ou incerto. Nunca tenta de novo sozinha.
-- 3. parceiro_aviso_reenviar (letra C, só o dono): nova saída com a chave :r1 ou :r2; a 3ª recusa.
-- 4. parceiro_aviso_registrar (letras A e B, só o dono): "pessoalmente" ou "pela revenda", com aviso_em agora.
-- 5. parceiro_veto_dito: o NÃO <sigla> do cliente, pela chave e nunca pelo nome; o veto vale para as OS seguintes
--    (parceiro_vetos não tem OS). Resposta Q03/Q03b só com parceiro_modo diferente de 'desligado'.
-- 6. parceiro_reter_resposta: o "não" ao aviso nas últimas parceiro_aviso_espera segura os vínculos (retido_em) até o dono
--    decidir, com o item retido na fila.
--
-- Sem dado: só funções novas. _parceiro_confirmar (P3) já chama parceiro_aviso_agendar; com parceiro_modo = 'desligado'
-- (o padrão) nada é agendado (a rodada avisa quando a F4 sair do desligado).
-- Reverter: drop function das funções desta migration. As tabelas da P1 ficam.

-- ── 1. O telefone do cliente e a saída do aviso ─────────────────────────────────────────────────────────────────────────

-- O telefone do cliente para o aviso: o whatsapp, senão o phone (como a condição 5b da regra de ouro). Sem os 8 dígitos,
-- nulo.
create or replace function public._parceiro_fone_do_cliente(p_client uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select x.f
    from (select coalesce(nullif(btrim(c.whatsapp), ''), c.phone) as f from public.clients c where c.id = p_client) x
   where public._agenda_chave_telefone(x.f) is not null;
$$;

comment on function public._parceiro_fone_do_cliente(uuid) is
  'Retorno F4 (P6.1): o telefone do aviso ao cliente (coalesce(whatsapp, phone)), só com chave de 8 dígitos; senão nulo.';

revoke all on function public._parceiro_fone_do_cliente(uuid) from public, anon, authenticated;

-- O corpo comum do aviso e do reenvio. p_sufixo nulo: o aviso do par (parceiro:aviso:<client>:<parceiro>); 'r1' ou 'r2':
-- o reenvio. Devolve {ok, saida_id?, motivo?, herdou?}. A recusa por telefone, número compartilhado ou nome põe o vínculo
-- nao_avisado no item aviso da fila (só no aviso, não no reenvio).
create or replace function public._parceiro_aviso_saida(p_interessado uuid, p_agora timestamptz, p_sufixo text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_oi public.os_interessados;
  v_cl public.clients;
  v_fone text;
  v_chave text;
  v_q jsonb;
  v_motivo text;
  v_herda public.retorno_saidas;
  v_s public.retorno_saidas;
  v_ids jsonb;
  v_papel text;
  v_vessel uuid;
  v_dedupe text;
  v_id uuid;
begin
  if p_sufixo is not null and p_sufixo !~ '^r[12]$' then
    raise exception using errcode = '22023', message = 'parceiro_aviso: sufixo fora da lista';
  end if;
  select * into v_oi from public.os_interessados oi where oi.id = p_interessado for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sem_vinculo');
  end if;
  if v_oi.papel = 'anfitria' then
    return jsonb_build_object('ok', false, 'motivo', 'anfitria');
  end if;
  if v_oi.situacao is distinct from 'confirmado' or v_oi.papel is null or v_oi.papel not in ('indicou', 'contratante', 'pagador') then
    return jsonb_build_object('ok', false, 'motivo', 'nao_confirmado');
  end if;
  -- A OS da própria parceira não tem aviso (o aviso é ela mesma); o vínculo já avisado por mensagem não manda outro.
  if v_oi.aviso_ao_cliente = 'proprio_parceiro' then
    return jsonb_build_object('ok', true, 'motivo', 'proprio_parceiro');
  end if;
  if v_oi.aviso_saida_id is not null then
    return jsonb_build_object('ok', true, 'saida_id', v_oi.aviso_saida_id, 'motivo', 'ja_avisado');
  end if;
  if not exists (select 1 from public.parceiros pa where pa.id = v_oi.parceiro_id and pa.ativo) then
    return jsonb_build_object('ok', false, 'motivo', 'parceiro_inativo');
  end if;
  if public._parceiro_veto_de(v_oi.client_id, v_oi.parceiro_id, v_agora) is not null then
    return jsonb_build_object('ok', false, 'motivo', 'veto');
  end if;
  if v_oi.retido_em is not null then
    return jsonb_build_object('ok', false, 'motivo', 'retido');
  end if;
  select * into v_cl from public.clients c where c.id = v_oi.client_id;
  if not found or coalesce(v_cl.opt_out_whatsapp, false)
     or public.canal_bloqueado(coalesce(nullif(btrim(v_cl.whatsapp), ''), v_cl.phone)) is not null then
    return jsonb_build_object('ok', false, 'motivo', 'opt_out');
  end if;

  -- O telefone: só com papel 'cliente' e o mesmo cliente em quem_escreve, e nunca com o número de um parceiro.
  v_fone := public._parceiro_fone_do_cliente(v_oi.client_id);
  v_chave := public._agenda_chave_telefone(v_fone);
  if v_fone is null then
    v_motivo := 'sem_telefone';
  else
    v_q := public.quem_escreve(v_fone);
    if v_q ->> 'papel' is distinct from 'cliente'
       or nullif(v_q ->> 'cliente_id', '')::uuid is distinct from v_oi.client_id
       or exists (select 1 from public.parceiro_numeros n where n.chave = v_chave and n.situacao <> 'recusado') then
      v_motivo := 'numero_compartilhado';
    elsif public._retorno_nome(v_oi.client_id) is null then
      v_motivo := 'sem_nome';
    end if;
  end if;
  if v_motivo is not null then
    -- o caminho sem telefone: o item aviso do vínculo (só o aviso; o reenvio é a letra C do item que já existe)
    if p_sufixo is null and v_oi.aviso_ao_cliente = 'nao_avisado' then
      perform public._parceiro_fila_por('aviso', v_oi.parceiro_id, v_oi.id, 'aviso:' || v_oi.id, null,
                                        jsonb_build_object('service_order_id', v_oi.service_order_id, 'motivo', v_motivo));
    end if;
    return jsonb_build_object('ok', false, 'motivo', v_motivo);
  end if;

  -- Um aviso por par: com aviso já enviado (incerta não conta), o vínculo herda e nada sai de novo.
  select * into v_herda
    from public.retorno_saidas s
   where s.emissor = 'parceiro'
     and s.tipo = 'parceiro_aviso_cliente'
     and s.estado = 'enviada'
     and s.enviada_em <= v_agora
     and s.dados ->> 'client_id' = v_oi.client_id::text
     and s.dados ->> 'parceiro_id' = v_oi.parceiro_id::text
   order by s.enviada_em desc, s.id
   limit 1;
  if found then
    update public.os_interessados oi
       set aviso_saida_id = v_herda.id,
           aviso_ao_cliente = case when oi.aviso_ao_cliente = 'nao_avisado' then 'mensagem' else oi.aviso_ao_cliente end,
           aviso_em = case when oi.aviso_ao_cliente = 'nao_avisado' then v_herda.enviada_em else oi.aviso_em end
     where oi.id = v_oi.id;
    return jsonb_build_object('ok', true, 'saida_id', v_herda.id, 'herdou', true);
  end if;

  -- A F4 desligada não agenda nada: a rodada avisa quando ela sair do desligado (o vínculo não vai ao item aviso).
  if v_cfg.id is null or v_cfg.parceiro_modo = 'desligado' then
    if p_sufixo is null then
      return jsonb_build_object('ok', true, 'saida_id', null, 'motivo', 'parceiro_desligado');
    end if;
    return jsonb_build_object('ok', false, 'motivo', 'parceiro_desligado');
  end if;

  -- Os dados: os vínculos do par que o aviso cobre (confirmados, sem aviso_saida_id), o papel mais forte e a unidade do
  -- vínculo mais antigo.
  select coalesce(jsonb_agg(oi.id order by oi.confirmado_em, oi.id), '[]'::jsonb),
         (case when bool_or(oi.papel = 'contratante') then 'contratante'
               when bool_or(oi.papel = 'pagador') then 'pagador'
               else 'indicou' end)
    into v_ids, v_papel
    from public.os_interessados oi
   where oi.client_id = v_oi.client_id
     and oi.parceiro_id = v_oi.parceiro_id
     and oi.situacao = 'confirmado'
     and oi.papel in ('indicou', 'contratante', 'pagador')
     and oi.aviso_saida_id is null
     and oi.retido_em is null
     and oi.aviso_ao_cliente in ('nao_avisado', 'pessoalmente', 'pela_revenda');
  select so.vessel_id into v_vessel
    from public.os_interessados oi
    join public.service_orders so on so.id = oi.service_order_id
   where oi.client_id = v_oi.client_id
     and oi.parceiro_id = v_oi.parceiro_id
     and oi.papel is distinct from 'anfitria'
   order by oi.proposto_em, oi.id
   limit 1;

  v_dedupe := 'parceiro:aviso:' || v_oi.client_id || ':' || v_oi.parceiro_id || coalesce(':' || p_sufixo, '');
  v_id := public.parceiro_agendar('parceiro_aviso_cliente', null, null, null,
                                  jsonb_build_object('client_id', v_oi.client_id, 'parceiro_id', v_oi.parceiro_id,
                                                     'interessado_ids', v_ids, 'papel', v_papel, 'vessel_id', v_vessel),
                                  v_agora, v_dedupe, 'aviso', v_fone);
  if v_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_telefone');
  end if;
  select * into v_s from public.retorno_saidas s where s.id = v_id for update;

  -- A chave já tinha saída: a que ainda espera passa a cobrir este vínculo (e o papel mais forte do par); a que caiu
  -- (recusada, cancelada ou incerta) não renasce sozinha: o item aviso:<interessado>:<saida> vem da rodada.
  if v_s.estado in ('recusada', 'cancelada', 'incerta') then
    return jsonb_build_object('ok', false, 'motivo', 'aviso_nao_saiu', 'saida_id', v_s.id);
  end if;
  if v_s.estado = 'agendada' then
    update public.retorno_saidas s
       set dados = s.dados || jsonb_build_object(
                     'interessado_ids', (select coalesce(jsonb_agg(x.v order by x.o), '[]'::jsonb)
                                           from (select e.v, min(e.o) as o
                                                   from (select a.v, a.o
                                                           from jsonb_array_elements(case when jsonb_typeof(s.dados -> 'interessado_ids') = 'array'
                                                                                          then s.dados -> 'interessado_ids' else '[]'::jsonb end)
                                                                with ordinality a(v, o)
                                                         union all
                                                         select b.v, 1000 + b.o
                                                           from jsonb_array_elements(v_ids) with ordinality b(v, o)) e
                                                  group by e.v) x),
                     'papel', (case when 'contratante' in (s.dados ->> 'papel', v_papel) then 'contratante'
                                    when 'pagador' in (s.dados ->> 'papel', v_papel) then 'pagador'
                                    else 'indicou' end)),
           atualizada_em = now()
     where s.id = v_s.id;
  end if;
  return jsonb_build_object('ok', true, 'saida_id', v_s.id);
end;
$$;

comment on function public._parceiro_aviso_saida(uuid, timestamptz, text) is
  'Retorno F4 (P6.1): o corpo comum de parceiro_aviso_agendar (p_sufixo nulo) e parceiro_aviso_reenviar (r1, r2). {ok, saida_id?, motivo?, herdou?}; motivos: sem_vinculo, anfitria, nao_confirmado, proprio_parceiro (ok), ja_avisado (ok), parceiro_inativo, veto, retido, opt_out, sem_telefone, numero_compartilhado, sem_nome, parceiro_desligado, aviso_nao_saiu.';

revoke all on function public._parceiro_aviso_saida(uuid, timestamptz, text) from public, anon, authenticated;

create or replace function public.parceiro_aviso_agendar(p_interessado uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  return public._parceiro_aviso_saida(p_interessado, coalesce(p_agora, now()), null);
end;
$$;

comment on function public.parceiro_aviso_agendar(uuid, timestamptz) is
  'Retorno F4 (C-AVISO, P6.1): {ok, saida_id?, motivo?}. Agenda o aviso ao cliente (parceiro_aviso_cliente, classe aviso, origem retorno_aviso, chave parceiro:aviso:<client>:<parceiro>, com :sombra em sombra), um por par. Recusa sem_telefone, numero_compartilhado (quem_escreve diferente de cliente, outro cliente ou número de parceiro) e sem_nome, com o vínculo nao_avisado no item aviso. Com aviso enviado do par, herda. Com parceiro_modo desligado, nada agenda (ok, motivo parceiro_desligado).';

revoke all on function public.parceiro_aviso_agendar(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_aviso_agendar(uuid, timestamptz) to service_role;

-- ── 2. A rodada do aviso (no vigia) ─────────────────────────────────────────────────────────────────────────────────────

create or replace function public.parceiro_aviso_rodada(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_r jsonb;
  r record;
  v_agendados integer := 0;
  v_herdados integer := 0;
  v_recusados integer := 0;
  v_itens integer := 0;
  v_erros integer := 0;
begin
  if v_cfg.id is null or v_cfg.parceiro_modo = 'desligado' then
    return jsonb_build_object('ok', true, 'rodou', false);
  end if;

  -- A. Os vínculos com telefone e sem aviso real: os nao_avisado e os registrados que ganharam telefone.
  for r in
    select oi.id
      from public.os_interessados oi
      join public.parceiros pa on pa.id = oi.parceiro_id and pa.ativo
     where oi.situacao = 'confirmado'
       and oi.papel in ('indicou', 'contratante', 'pagador')
       and oi.aviso_saida_id is null
       and oi.retido_em is null
       and oi.aviso_ao_cliente in ('nao_avisado', 'pessoalmente', 'pela_revenda')
       and oi.confirmado_em <= v_agora
       and public._parceiro_fone_do_cliente(oi.client_id) is not null
     order by oi.confirmado_em, oi.id
  loop
    begin
      v_r := public.parceiro_aviso_agendar(r.id, v_agora);
      if coalesce((v_r ->> 'herdou')::boolean, false) then
        v_herdados := v_herdados + 1;
      elsif coalesce((v_r ->> 'ok')::boolean, false) then
        v_agendados := v_agendados + 1;
      else
        v_recusados := v_recusados + 1;
      end if;
    exception when others then
      v_erros := v_erros + 1;
      perform public._retorno_log('parceiro_aviso', 'parceiro_aviso_rodada: ' || sqlerrm, 'error',
                                  jsonb_build_object('interessado', r.id, 'sqlstate', sqlstate));
    end;
  end loop;

  -- B. O aviso real recusado ou incerto não tenta de novo sozinho: cada vínculo do par ainda sem aviso ganha o item
  --    aviso:<interessado>:<saida> (chave nova a cada saída), uma vez.
  for r in
    select s.id as saida_id, oi.id as interessado_id, oi.parceiro_id, oi.service_order_id, s.estado, s.motivo
      from public.retorno_saidas s
      join public.os_interessados oi
        on oi.client_id::text = s.dados ->> 'client_id'
       and oi.parceiro_id::text = s.dados ->> 'parceiro_id'
     where s.emissor = 'parceiro'
       and s.tipo = 'parceiro_aviso_cliente'
       and s.estado in ('recusada', 'incerta')
       and s.motivo is distinct from 'parceiro_desligado'
       and s.dedupe_key !~ ':sombra(:|$)'
       and s.decidida_em <= v_agora
       and oi.situacao = 'confirmado'
       and oi.papel in ('indicou', 'contratante', 'pagador')
       and oi.aviso_saida_id is null
       and oi.retido_em is null
       and public._parceiro_veto_de(oi.client_id, oi.parceiro_id, v_agora) is null
       and not exists (select 1 from public.parceiro_fila f where f.chave = 'aviso:' || oi.id || ':' || s.id)
     order by s.decidida_em, s.id, oi.id
  loop
    begin
      perform public._parceiro_fila_por('aviso', r.parceiro_id, r.interessado_id, 'aviso:' || r.interessado_id || ':' || r.saida_id,
                                        null, jsonb_build_object('saida_id', r.saida_id, 'service_order_id', r.service_order_id,
                                                                 'estado', r.estado, 'motivo', r.motivo));
      v_itens := v_itens + 1;
    exception when others then
      v_erros := v_erros + 1;
      perform public._retorno_log('parceiro_aviso', 'parceiro_aviso_rodada (item): ' || sqlerrm, 'error',
                                  jsonb_build_object('saida', r.saida_id, 'sqlstate', sqlstate));
    end;
  end loop;

  return jsonb_build_object('ok', v_erros = 0, 'rodou', true, 'agendados', v_agendados, 'herdados', v_herdados,
                            'recusados', v_recusados, 'itens', v_itens, 'erros', v_erros);
end;
$$;

comment on function public.parceiro_aviso_rodada(timestamptz) is
  'Retorno F4 (P6.1): no vigia. A: parceiro_aviso_agendar em todo vínculo confirmado comercial, sem aviso_saida_id e sem retenção, com telefone (nao_avisado ou registrado pessoalmente/pela revenda), na ordem da confirmação. B: aviso real recusado ou incerto → item aviso:<interessado>:<saida> na fila, uma vez. Nunca reenvia sozinha. Com parceiro_modo desligado, não roda.';

revoke all on function public.parceiro_aviso_rodada(timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_aviso_rodada(timestamptz) to service_role;

-- ── 3. As letras do item aviso (só o dono) ──────────────────────────────────────────────────────────────────────────────

-- Letra C: manda o aviso de novo, com a chave :r1 ou :r2. A 3ª recusa (limite).
create or replace function public.parceiro_aviso_reenviar(p_interessado uuid, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_oi public.os_interessados;
  v_n integer;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    raise exception using errcode = '42501', message = 'parceiro_aviso_reenviar: só o dono';
  end if;
  select * into v_oi from public.os_interessados oi where oi.id = p_interessado;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sem_vinculo');
  end if;
  if v_oi.aviso_saida_id is not null then
    return jsonb_build_object('ok', false, 'motivo', 'ja_avisado');
  end if;
  select count(*) + 1 into v_n
    from public.retorno_saidas s
   where s.emissor = 'parceiro'
     and s.tipo = 'parceiro_aviso_cliente'
     and s.dedupe_key ~ ('^parceiro:aviso:' || v_oi.client_id || ':' || v_oi.parceiro_id || ':r[0-9]+(:|$)');
  if v_n > 2 then
    return jsonb_build_object('ok', false, 'motivo', 'limite');
  end if;
  return public._parceiro_aviso_saida(v_oi.id, coalesce(p_agora, now()), 'r' || v_n);
end;
$$;

comment on function public.parceiro_aviso_reenviar(uuid, uuid, timestamptz) is
  'Retorno F4 (P6.1): letra C do item aviso. Só o dono (42501). Nova saída parceiro:aviso:<client>:<parceiro>:r<n>, n de 1 a 2; a 3ª dá {ok: false, motivo: limite}. Mesmas travas do aviso.';

revoke all on function public.parceiro_aviso_reenviar(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_aviso_reenviar(uuid, uuid, timestamptz) to service_role;

-- Letras A e B: o dono avisou o cliente pessoalmente ou pela revenda (cliente sem telefone). Grava o aviso agora.
create or replace function public.parceiro_aviso_registrar(p_interessado uuid, p_como text, p_autor uuid,
                                                           p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_oi public.os_interessados;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    raise exception using errcode = '42501', message = 'parceiro_aviso_registrar: só o dono';
  end if;
  if p_como is null or p_como not in ('pessoalmente', 'pela_revenda') then
    raise exception using errcode = '22023', message = 'parceiro_aviso_registrar: como fora da lista';
  end if;
  select * into v_oi from public.os_interessados oi where oi.id = p_interessado for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sem_vinculo');
  end if;
  if v_oi.situacao is distinct from 'confirmado' or v_oi.papel is null or v_oi.papel not in ('indicou', 'contratante', 'pagador') then
    return jsonb_build_object('ok', false, 'motivo', 'nao_confirmado');
  end if;
  if v_oi.aviso_ao_cliente is distinct from 'nao_avisado' then
    return jsonb_build_object('ok', false, 'motivo', 'ja_avisado');
  end if;
  update public.os_interessados oi
     set aviso_ao_cliente = p_como, aviso_em = coalesce(p_agora, now())
   where oi.id = v_oi.id;
  return jsonb_build_object('ok', true, 'interessado_id', v_oi.id, 'aviso', p_como);
end;
$$;

comment on function public.parceiro_aviso_registrar(uuid, text, uuid, timestamptz) is
  'Retorno F4 (P6.1): letras A e B do item aviso. Só o dono (42501). Grava aviso_ao_cliente (pessoalmente ou pela_revenda) e aviso_em = agora em vínculo confirmado comercial ainda nao_avisado.';

revoke all on function public.parceiro_aviso_registrar(uuid, text, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_aviso_registrar(uuid, text, uuid, timestamptz) to service_role;

-- ── 4. O NÃO MP e a resposta que pode ser um "não" ──────────────────────────────────────────────────────────────────────

-- O NÃO <sigla> do cliente, pela chave (quem_escreve), nunca pelo nome. Situações (P6.1):
--   cliente com vínculo (ou com aviso à chave): veto, Q03 (com_nome; sem nome, Q03b) e consome;
--   cliente_ambiguo com ao menos um vínculo: veto em todos da lista com vínculo, 1 saída Q03b à chave e consome;
--   cliente sem vínculo e sem aviso: veto (para as OS futuras), sem resposta e sem consumir; o ambíguo sem vínculo, o
--   mesmo em todos da lista (na dúvida, cala o parceiro);
--   número desconhecido (ou de outro papel): nada.
-- Idempotente. A resposta nunca sai com parceiro_modo = 'desligado'; o veto vale em qualquer modo.
create or replace function public.parceiro_veto_dito(p_chave text, p_fone text, p_sigla text, p_msg uuid, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_pa public.parceiros;
  v_q jsonb;
  v_chave text := public._agenda_chave_telefone(p_fone);
  v_clientes uuid[];
  v_com uuid[];
  v_alvo uuid[];
  v_aviso boolean;
  v_responde boolean;
  v_c uuid;
  v_n integer := 0;
  v_k integer;
  v_nome text;
  v_saida uuid;
begin
  select * into v_pa
    from public.parceiros pa
   where pa.ativo and public._texto_simples(pa.sigla) = public._texto_simples(btrim(coalesce(p_sigla, '')))
   order by pa.criado_em, pa.id
   limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'consumida', false, 'acao', 'nada', 'motivo', 'sem_parceiro');
  end if;
  if v_chave is null or (p_chave is not null and p_chave is distinct from v_chave) then
    return jsonb_build_object('ok', false, 'consumida', false, 'acao', 'nada', 'motivo', 'chave');
  end if;

  v_q := public.quem_escreve(p_fone);
  if v_q ->> 'papel' = 'cliente' then
    v_clientes := array[(v_q ->> 'cliente_id')::uuid];
  elsif v_q ->> 'papel' = 'cliente_ambiguo' then
    v_clientes := array(select x::uuid from jsonb_array_elements_text(v_q -> 'clientes') x);
  else
    return jsonb_build_object('ok', true, 'consumida', false, 'acao', 'nada', 'motivo', 'desconhecido');
  end if;

  v_com := array(select c from unnest(v_clientes) c
                  where exists (select 1 from public.os_interessados oi where oi.client_id = c and oi.parceiro_id = v_pa.id));
  v_aviso := exists (select 1 from public.retorno_saidas s
                      where s.emissor = 'parceiro' and s.tipo = 'parceiro_aviso_cliente' and s.estado = 'enviada'
                        and s.chave = v_chave and s.dados ->> 'parceiro_id' = v_pa.id::text
                        and s.enviada_em <= v_agora);
  if cardinality(v_com) > 0 then
    v_alvo := v_com;
    v_responde := true;
  elsif v_aviso then
    v_alvo := v_clientes;
    v_responde := true;
  else
    v_alvo := v_clientes;
    v_responde := false;
  end if;

  foreach v_c in array v_alvo loop
    insert into public.parceiro_vetos (client_id, parceiro_id, em, origem, whatsapp_message_id)
    values (v_c, v_pa.id, v_agora, 'nao_mp', p_msg)
    on conflict (client_id, parceiro_id) do nothing;
    get diagnostics v_k = row_count;
    v_n := v_n + v_k;
    update public.os_interessados oi
       set veto_do_cliente_em = coalesce(oi.veto_do_cliente_em, v_agora)
     where oi.client_id = v_c and oi.parceiro_id = v_pa.id;
  end loop;

  if v_responde and v_cfg.id is not null and v_cfg.parceiro_modo is distinct from 'desligado' then
    if v_q ->> 'papel' = 'cliente' then
      v_nome := public._retorno_nome(v_alvo[1]);
      v_saida := public.parceiro_agendar('parceiro_nao_mp_ok', case when v_nome is null then 'sem_nome' else 'com_nome' end,
                                         null, null, jsonb_build_object('client_id', v_alvo[1], 'parceiro_id', v_pa.id),
                                         v_agora, 'parceiro:nao_mp:' || v_alvo[1] || ':' || v_pa.id, 'resposta_imediata', p_fone);
    else
      -- o telefone é um só, e o nome não pode ser escolhido: uma saída Q03b à chave
      v_saida := public.parceiro_agendar('parceiro_nao_mp_ok', 'sem_nome', null, null,
                                         jsonb_build_object('parceiro_id', v_pa.id, 'clientes', to_jsonb(v_alvo)),
                                         v_agora, 'parceiro:nao_mp:chave:' || v_chave || ':' || v_pa.id, 'resposta_imediata', p_fone);
    end if;
  end if;

  return jsonb_build_object('ok', true, 'consumida', v_responde, 'acao', 'veto', 'parceiro_id', v_pa.id,
                            'vetados', v_n, 'saida_id', v_saida);
end;
$$;

comment on function public.parceiro_veto_dito(text, text, text, uuid, timestamptz) is
  'Retorno F4 (P6.1): o NÃO <sigla> pela chave. Cliente com vínculo (ou aviso à chave): parceiro_vetos + veto_do_cliente_em, Q03 (ou Q03b sem nome), consome. Ambíguo com vínculo: veto em todos da lista com vínculo, uma Q03b à chave, consome. Sem vínculo e sem aviso: só o veto, sem resposta e sem consumir. Desconhecido: nada. Resposta nunca com parceiro_modo desligado. Idempotente.';

revoke all on function public.parceiro_veto_dito(text, text, text, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_veto_dito(text, text, text, uuid, timestamptz) to service_role;

-- O cliente respondeu ao aviso com algo que pode ser um "não": os vínculos confirmados dele (todos os da lista, no número
-- ambíguo) cujo aviso por mensagem saiu a esta chave nas últimas parceiro_aviso_espera ficam retidos até o dono decidir,
-- com o item retido na fila. Lê só o telefone da mensagem, nunca o corpo.
create or replace function public.parceiro_reter_resposta(p_chave text, p_msg uuid, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_fone text;
  v_chave text;
  v_q jsonb;
  v_clientes uuid[];
  r record;
  v_n integer := 0;
begin
  if v_cfg.id is null then
    return jsonb_build_object('ok', false, 'retidos', 0, 'motivo', 'sem_config');
  end if;
  select w.phone_normalized into v_fone from public.whatsapp_messages w where w.id = p_msg;
  v_chave := public._agenda_chave_telefone(v_fone);
  if v_chave is null or (p_chave is not null and p_chave is distinct from v_chave) then
    return jsonb_build_object('ok', false, 'retidos', 0, 'motivo', 'chave');
  end if;
  v_q := public.quem_escreve(v_fone);
  if v_q ->> 'papel' = 'cliente' then
    v_clientes := array[(v_q ->> 'cliente_id')::uuid];
  elsif v_q ->> 'papel' = 'cliente_ambiguo' then
    v_clientes := array(select x::uuid from jsonb_array_elements_text(v_q -> 'clientes') x);
  else
    return jsonb_build_object('ok', true, 'retidos', 0, 'motivo', 'desconhecido');
  end if;

  for r in
    select oi.id, oi.parceiro_id, oi.service_order_id
      from public.os_interessados oi
      join public.retorno_saidas s on s.id = oi.aviso_saida_id
     where oi.client_id = any (v_clientes)
       and oi.situacao = 'confirmado'
       and oi.papel in ('indicou', 'contratante', 'pagador')
       and oi.retido_em is null
       and s.estado = 'enviada'
       and s.chave = v_chave
       and s.enviada_em <= v_agora
       and s.enviada_em > v_agora - v_cfg.parceiro_aviso_espera
     order by oi.id
     for update of oi
  loop
    update public.os_interessados oi set retido_em = v_agora where oi.id = r.id;
    perform public._parceiro_fila_por('retido', r.parceiro_id, r.id, 'retido:' || r.id, null,
                                      jsonb_build_object('service_order_id', r.service_order_id, 'msg_id', p_msg));
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'retidos', v_n);
end;
$$;

comment on function public.parceiro_reter_resposta(text, uuid, timestamptz) is
  'Retorno F4 (P6.1): grava retido_em nos vínculos confirmados do cliente (ambíguo: todos da lista) com aviso por mensagem enviado a esta chave nas últimas parceiro_aviso_espera, e põe o item retido na fila. Só lê o telefone da mensagem.';

revoke all on function public.parceiro_reter_resposta(text, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_reter_resposta(text, uuid, timestamptz) to service_role;

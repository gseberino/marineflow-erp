-- Retorno rápido (12/11/2026): UPDATE de retorno_config sem WHERE quebrava pelo PostgREST.
--
-- O Supabase carrega o pg_safeupdate nas sessões do PostgREST: todo UPDATE/DELETE sem WHERE é recusado com
-- "UPDATE requires a WHERE clause" (HTTP 400). retorno_config tem UMA linha (id boolean = true), e as funções abaixo
-- faziam "update public.retorno_config set ...;" sem WHERE. Pelo cron (pg_cron, sem o safeupdate) e na bancada (CLI)
-- passava; pelo assistente (ai-agent → rpc) falhava sempre:
--   - retorno_carona: a carona do retorno nunca saiu (6 chamadas com HTTP 400 entre 11/11 14:51 e 21:57);
--   - retorno_dito: *segura recibos*, *segura tudo*, *segura pátio*, *libera* e *fora até* falhariam;
--   - _retorno_dito_pessoal: a volta do *pessoal N*.
--
-- Gerada de pg_get_functiondef (a definição no ar, a da F4) por scripts/gerar_update_com_where.cjs; a ÚNICA mudança
-- é " where id" antes do ';' de cada um desses UPDATE. CREATE OR REPLACE mantém donos e grants.
-- Teste: supabase/tests/retorno_update_com_where.sql (nenhuma função retorno/parceiro com UPDATE/DELETE sem WHERE).
--
-- Reverter: reaplicar as definições de 20261123100700_retorno_f2_carona.sql e 20270105100700_retorno_f4_cartao.sql
-- (voltam a falhar pelo PostgREST).
-- _retorno_dito_pessoal(integer,uuid,timestamp with time zone): 1 update(s) com "where id"
CREATE OR REPLACE FUNCTION public._retorno_dito_pessoal(p_n integer, p_autor uuid, p_agora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_vivo jsonb;
  v_cartao uuid;
  v_vivos integer;
  v_item public.retorno_cartao_itens;
  v_ab public.retorno_aberturas;
  v_antes text;
  v_rotulo text;
begin
  v_vivo := public.retorno_cartao_vivo(p_agora);
  if v_vivo is null then
    return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end if;
  v_cartao := (v_vivo ->> 'id')::uuid;

  select count(*) into v_vivos from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo';
  if p_n is null then
    if v_vivos = 0 then
      return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
    end if;
    if v_vivos > 1 then
      return jsonb_build_object('ok', true, 'texto', 'Qual? *pessoal 2*.');
    end if;
    select * into v_item from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo';
  else
    select * into v_item from public.retorno_cartao_itens i
     where i.cartao_id = v_cartao and i.n = p_n and i.estado = 'vivo';
    if not found then
      return jsonb_build_object('ok', true, 'texto', format('Não há caso %s nesta lista. Mande *retorno*.', p_n));
    end if;
  end if;

  select * into v_ab from public.retorno_aberturas a where a.id = v_item.abertura_id;
  v_rotulo := public._retorno_rotulo(v_ab.id, p_agora);

  select l.lead_tipo into v_antes from public.whatsapp_leads l where l.phone_normalized = v_ab.phone_normalized;
  insert into public.whatsapp_leads (phone_normalized, status, lead_tipo)
  values (v_ab.phone_normalized, 'discarded', 'pessoal')
  on conflict (phone_normalized) do update set lead_tipo = 'pessoal', updated_at = now();

  update public.retorno_saidas s
     set estado = 'cancelada', motivo = 'pessoal', decidida_em = p_agora, atualizada_em = now()
   where s.abertura_id = v_ab.id and s.estado = 'agendada';

  update public.retorno_aberturas a
     set estado = 'fechada', fechada_em = p_agora, fechada_motivo = 'nada', atualizada_em = now()
   where a.id = v_ab.id and a.estado <> 'fechada';

  update public.retorno_cartao_itens i
     set estado = 'caiu', caiu_motivo = 'caso_fechado', decidido_em = p_agora
   where i.id = v_item.id;

  update public.retorno_cartoes c
     set texto = public._retorno_cartao_texto(c.id, null)
   where c.id = v_cartao;

  update public.retorno_config
     set pessoal_ultimo = jsonb_build_object('phone', v_ab.phone_normalized, 'lead_tipo_antes', v_antes, 'em', p_agora),
         atualizado_em = now(), atualizado_por = p_autor where id;

  perform public._retorno_auditar_palavra(p_autor, jsonb_build_object('lead_tipo', v_antes),
    jsonb_build_object('lead_tipo', 'pessoal', 'abertura', v_ab.id), '*pessoal* do dono');
  perform public._retorno_toque('pessoal', v_cartao, v_ab.id, p_agora);

  return jsonb_build_object('ok', true,
    'texto', format('%s: anotado como pessoal. Esse número nunca mais recebe automático, e cancelei o que estava agendado. *pessoal não* desfaz.', v_rotulo));
end;
$function$;

-- retorno_carona(uuid,timestamp with time zone): 1 update(s) com "where id"
CREATE OR REPLACE FUNCTION public.retorno_carona(p_autor uuid, p_agora timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_vivo jsonb;
  v_n integer;
  v_caso uuid;
  v_rotulo text;
  v_prazo text;
  v_texto text;
begin
  if v_cfg.id is null or not v_cfg.carona_ligada or v_cfg.modo = 'desligado' then
    return null;
  end if;
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return null;
  end if;
  if v_cfg.carona_em is not null and v_cfg.carona_em > v_agora - v_cfg.carona_intervalo then
    return null;
  end if;

  v_vivo := public.retorno_cartao_vivo(v_agora);
  if v_vivo ->> 'estado' = 'vivo' then
    v_n := jsonb_array_length(v_vivo -> 'itens');
    if v_n = 0 then
      return null;
    end if;
    v_texto := format('Retorno: cartão aberto, %s %s · *retorno*', v_n, case when v_n = 1 then 'caso' else 'casos' end);
  else
    select count(*), (array_agg(c.abertura_id))[1] into v_n, v_caso from public._retorno_cartao_casos(v_agora, null) c;
    if v_n = 0 then
      return null;
    end if;
    v_rotulo := public._retorno_rotulo(v_caso, v_agora);
    v_prazo := public._retorno_prazo_curto(v_caso, v_agora);
    v_texto := case
      when v_prazo like 'prometi até %' then
        format('Retorno: %s esperando (%s, prometido até %s) · *retorno*', v_n, v_rotulo, substr(v_prazo, char_length('prometi até ') + 1))
      else
        format('Retorno: %s esperando (%s, desde %s) · *retorno*', v_n, v_rotulo,
               (select to_char(a.aberta_em at time zone 'America/Sao_Paulo', 'HH24:MI') from public.retorno_aberturas a where a.id = v_caso))
    end;
  end if;

  update public.retorno_config set carona_em = v_agora where id;
  return jsonb_build_object('texto', v_texto);
end;
$function$;

-- retorno_dito(jsonb,uuid,timestamp with time zone): 9 update(s) com "where id"
CREATE OR REPLACE FUNCTION public.retorno_dito(p_comando jsonb, p_autor uuid, p_agora timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (v_agora at time zone c_fuso)::date;
  v_cmd text := p_comando ->> 'comando';
  v_alvo text := p_comando ->> 'alvo';
  v_cfg public.retorno_config;
  v_texto text;
  v_user text;
  v_r jsonb;
  v_ate date;
  v_ate_ts timestamptz;
  v_k integer;
  v_antes jsonb;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return jsonb_build_object('ok', false, 'motivo', 'nao_e_o_dono');
  end if;
  v_cfg := public._retorno_cfg();
  if v_cfg.id is null then
    return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end if;

  case v_cmd
    when 'retorno' then
      v_r := public.retorno_cartao_abrir('puxar', v_agora);
      return jsonb_build_object('ok', true,
        'texto', coalesce(v_r ->> 'texto', 'Ninguém esperando agora.'),
        'cartao_id', v_r ->> 'cartao_id',
        'historico', v_r -> 'historico');

    when 'ver' then
      return public.retorno_ver_caso((p_comando ->> 'n')::integer, p_autor, v_agora);

    when 'segura' then
      if v_alvo = 'recibos' then
        update public.retorno_config set segura_recibos = true, atualizado_em = now(), atualizado_por = p_autor where id;
        v_texto := 'Segurei os recibos: quem escrever agora não recebe recibo, saudação nem coleta, nem depois que você soltar. *solta recibos* vale para as próximas mensagens.';
      elsif v_alvo = 'tudo' then
        v_ate_ts := v_agora + interval '24 hours';
        update public.retorno_config set segura_tudo_ate = v_ate_ts, atualizado_em = now(), atualizado_por = p_autor where id;
        v_texto := format('Segurei tudo por 24 h, até %s às %s: nada automático do retorno sai ao cliente. *solta tudo* volta antes.',
                          public._retorno_quando((v_ate_ts at time zone c_fuso)::date, v_hoje),
                          to_char(v_ate_ts at time zone c_fuso, 'HH24:MI'));
        if not exists (select 1 from pg_proc p where p.proname = '_agenda_retorno_segurou') then
          v_texto := v_texto || ' A agenda ainda manda o que já estava aprovado: *segura cliente* segura.';
        end if;
      elsif v_alvo in ('patio', 'pátio') then
        -- F4 (P8): *segura pátio*. O *pátio* do parceiro é recusado sem resposta (segura_patio) e o recibo sai sem o pátio.
        v_alvo := 'patio';
        update public.retorno_config set segura_patio = true, atualizado_em = now(), atualizado_por = p_autor where id;
        v_texto := 'Segurei o pátio: o parceiro que mandar *pátio* não recebe a lista, e o recibo sai sem o pátio de hoje. *solta pátio* volta.';
      else
        return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
      end if;
      v_user := 'segura ' || v_alvo;
      perform public._retorno_auditar_palavra(p_autor, jsonb_build_object('segura_recibos', v_cfg.segura_recibos, 'segura_tudo_ate', v_cfg.segura_tudo_ate),
        jsonb_build_object('alvo', v_alvo), '*segura* do dono');
      -- F4 (P8): o antes do pátio também fica na auditoria.
      if v_alvo = 'patio' then
        perform public._retorno_auditar_palavra(p_autor, jsonb_build_object('segura_patio', v_cfg.segura_patio),
          jsonb_build_object('alvo', v_alvo), '*segura pátio* do dono');
      end if;

    when 'solta' then
      if v_alvo = 'recibos' then
        update public.retorno_config set segura_recibos = false, atualizado_em = now(), atualizado_por = p_autor where id;
        v_texto := 'Recibos soltos: valem para as próximas mensagens.';
      elsif v_alvo = 'tudo' then
        update public.retorno_config
           set segura_tudo_ate = null, segura_recibos = false, atualizado_em = now(), atualizado_por = p_autor where id;
        update public.retorno_saidas s
           set enviar_em = v_agora, atualizada_em = now()
         where s.estado = 'agendada' and s.dados ? 'segurada';
        get diagnostics v_k = row_count;
        v_texto := case when v_k = 0 then 'Soltei: o automático volta a sair.'
                        else format('Soltei: o automático volta a sair. %s que ficaram no meio saem agora; quem escreveu há mais de 12 h fica com você.', v_k) end;
      elsif v_alvo in ('patio', 'pátio') then
        -- F4 (P8): *solta pátio*. Vale para os próximos pedidos de *pátio* e para o próximo recibo.
        v_alvo := 'patio';
        update public.retorno_config set segura_patio = false, atualizado_em = now(), atualizado_por = p_autor where id;
        v_texto := 'Pátio solto: o parceiro volta a receber a lista quando mandar *pátio*.';
      else
        return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
      end if;
      v_user := 'solta ' || v_alvo;
      perform public._retorno_auditar_palavra(p_autor, jsonb_build_object('segura_recibos', v_cfg.segura_recibos, 'segura_tudo_ate', v_cfg.segura_tudo_ate),
        jsonb_build_object('alvo', v_alvo), '*solta* do dono');
      -- F4 (P8): o antes do pátio também fica na auditoria.
      if v_alvo = 'patio' then
        perform public._retorno_auditar_palavra(p_autor, jsonb_build_object('segura_patio', v_cfg.segura_patio),
          jsonb_build_object('alvo', v_alvo), '*solta pátio* do dono');
      end if;

    when 'fora_ate' then
      begin
        v_r := public.agenda_data_dita(p_comando ->> 'dia', v_hoje, 'futuro');
        v_ate := (v_r ->> 'ate')::date;
      exception when data_exception then
        v_ate := null;
      end;
      v_user := 'fora até ' || coalesce(p_comando ->> 'dia', '');
      if v_ate is null or v_ate < v_hoje then
        return jsonb_build_object('ok', true, 'texto', 'Não entendi o dia. Diga *fora até quarta* ou *fora até 25/11*.');
      end if;
      if v_ate = v_hoje then
        update public.retorno_config set fora_ate = null, atualizado_em = now(), atualizado_por = p_autor where id;
        v_texto := 'Anotado: você voltou, e o recibo volta ao normal.';
      else
        update public.retorno_config set fora_ate = v_ate, atualizado_em = now(), atualizado_por = p_autor where id;
        v_texto := format('Anotado: até %1$s o recibo diz que você está fora e que retorna %2$s. *fora até hoje* desfaz.',
                          public._retorno_quando(v_ate, v_hoje),
                          public._retorno_quando_fala(public._retorno_quando(v_ate, v_hoje), public._retorno_hora(v_cfg.promessa_manha)));
      end if;
      perform public._retorno_auditar_palavra(p_autor, jsonb_build_object('fora_ate', v_cfg.fora_ate),
        jsonb_build_object('fora_ate', case when v_ate = v_hoje then null else v_ate end), '*fora até* do dono');

    when 'libera' then
      v_r := public._retorno_dito_libera(p_comando, p_autor, v_agora);
      if coalesce((v_r ->> 'ok')::boolean, false) is false then
        return v_r;
      end if;
      perform public._retorno_toque('libera', null, null, v_agora);
      v_texto := v_r ->> 'texto';
      v_user := 'libera ' || coalesce(v_alvo, '');

    when 'errado' then
      v_r := public._retorno_dito_errado(upper(coalesce(p_comando ->> 'letra', '')), v_agora);
      v_texto := v_r ->> 'texto';
      v_user := 'errado ' || coalesce(p_comando ->> 'letra', '');

    when 'pessoal' then
      v_r := public._retorno_dito_pessoal((p_comando ->> 'n')::integer, p_autor, v_agora);
      if coalesce((v_r ->> 'ok')::boolean, false) is false then
        return v_r;
      end if;
      v_texto := v_r ->> 'texto';
      v_user := 'pessoal';

    when 'resolvido' then
      v_r := public._retorno_dito_resolvido((p_comando ->> 'n')::integer, p_autor, v_agora);
      if coalesce((v_r ->> 'ok')::boolean, false) is false then
        return v_r;
      end if;
      v_texto := v_r ->> 'texto';
      v_user := 'resolvido ' || coalesce(p_comando ->> 'n', '');

    when 'pessoal_desfaz' then
      v_antes := v_cfg.pessoal_ultimo;
      if v_antes is null or v_agora - (v_antes ->> 'em')::timestamptz > interval '24 hours' then
        return jsonb_build_object('ok', true, 'texto', 'Não há *pessoal* recente para desfazer.');
      end if;
      update public.whatsapp_leads l
         set lead_tipo = v_antes ->> 'lead_tipo_antes', updated_at = now()
       where l.phone_normalized = v_antes ->> 'phone';
      update public.retorno_config set pessoal_ultimo = null, atualizado_em = now(), atualizado_por = p_autor where id;
      perform public._retorno_auditar_palavra(p_autor, v_antes, jsonb_build_object('lead_tipo', v_antes ->> 'lead_tipo_antes'),
        '*pessoal não* do dono');
      v_texto := 'Pronto: esse número volta a receber automático.';
      v_user := 'pessoal não';

    else
      return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end case;

  return jsonb_build_object('ok', true, 'texto', v_texto,
    'historico', jsonb_build_object('user', v_user, 'assistant', v_texto));
end;
$function$;

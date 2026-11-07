-- Retorno rápido ao cliente, F2 (P4): as palavras do dono no banco.
--
-- retorno_dito(comando, autor, agora) é a porta única das palavras sem cartão: *retorno*, *ver N*, *pessoal*, *pessoal não*,
-- *fora até*, *segura* e *solta*, *libera*, *errado*. A camada (P3) lê a forma; aqui se confere o autor, se resolve o alvo,
-- se grava e se devolve o texto exato. Nenhum texto do cliente sai pelo campo "historico".
--
-- O que *segura* faz com o que está no meio:
--   - *segura tudo* não queima a saída: a P10 faz a saída agendada esperar segura_tudo_ate (dados.segurada), e *solta tudo*
--     traz o enviar_em para agora. Sem a P10 no ar, k = 0 e a frase curta diz a verdade;
--   - *segura recibos* corta o tipo, e o que estava no meio NÃO sai depois: vira sombra, como a F1 já faz.
--
-- *libera* só marca, não manda nada. Por nome, cada palavra do alvo tem de ser palavra inteira do cadastro, porque
-- agenda_resolver_os casa por prefixo: "libera Rod" pergunta, em vez de marcar o Rodrigo.
--
-- *pessoal* nunca é regex: só a palavra do dono. Tem volta em 24 h (*pessoal não*).
--
-- *segura tudo* ainda não segura a agenda (pedido 11): a frase R03a diz isso enquanto _agenda_retorno_segurou não existir.
-- Quando a agenda publicar essa função, a frase some sem deploy daqui.
--
-- Reverter: drop function public.retorno_dito(jsonb, uuid, timestamptz), public._retorno_dito_libera(jsonb, uuid, timestamptz),
-- public._retorno_dito_pessoal(integer, uuid, timestamptz), public._retorno_dito_errado(text, timestamptz),
-- public._retorno_toque(text, uuid, uuid, timestamptz), public._retorno_tipo_curto(text),
-- public._retorno_auditar_palavra(uuid, jsonb, jsonb, text). A camada trata a função ausente como "segue como sempre".

create or replace function public._retorno_auditar_palavra(p_autor uuid, p_antes jsonb, p_depois jsonb, p_motivo text)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('retorno_config', p_autor, 'update', 'dono', p_antes, p_depois, p_motivo);
$$;

comment on function public._retorno_auditar_palavra(uuid, jsonb, jsonb, text) is
  'Retorno F2 (P4): a linha de audit_log das palavras do dono. record_id = o autor, porque a coluna é uuid obrigatório e retorno_config não tem uuid.';

revoke all on function public._retorno_auditar_palavra(uuid, jsonb, jsonb, text) from public, anon, authenticated;

-- Cada resposta do dono é um toque novo (meta: 3 ou menos por dia útil).
create or replace function public._retorno_toque(p_palavra text, p_cartao uuid, p_abertura uuid, p_agora timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_enviado timestamptz;
  v_latencia integer;
begin
  if p_cartao is not null then
    select c.enviado_em into v_enviado from public.retorno_cartoes c where c.id = p_cartao;
  end if;
  if v_enviado is not null then
    v_latencia := greatest(0, floor(extract(epoch from p_agora - v_enviado)))::integer;
  end if;
  insert into public.retorno_toques (em, cartao_id, abertura_id, palavra, latencia_s, rapido)
  values (p_agora, p_cartao, p_abertura, p_palavra, v_latencia,
          coalesce(v_latencia < (public._retorno_cfg()).fadiga_s, false));
end;
$$;

comment on function public._retorno_toque(text, uuid, uuid, timestamptz) is
  'Retorno F2 (P4): grava um toque do dono em retorno_toques, com a latência desde o envio do cartão e a marca de rápido (menos de fadiga_s).';

revoke all on function public._retorno_toque(text, uuid, uuid, timestamptz) from public, anon, authenticated;

create or replace function public._retorno_tipo_curto(p_tipo text)
returns text
language sql
immutable
set search_path = public
as $$
  select case p_tipo
    when 'modelo_aguarda_peca' then 'aguardando peça'
    when 'modelo_peca_chegou' then 'peça chegou'
    when 'modelo_pronto' then 'pronto'
    when 'modelo_em_servico' then 'em serviço'
    when 'modelo_liberado' then 'liberado'
    when 'modelo_retirada_nao' then 'retirada ainda não'
  end;
$$;

comment on function public._retorno_tipo_curto(text) is
  'Retorno F2 (P4): o nome curto do tipo de modelo, para as frases ao dono.';

revoke all on function public._retorno_tipo_curto(text) from public, anon, authenticated;

-- *libera <alvo>* e *libera <alvo> não*. Devolve o corpo da resposta de retorno_dito.
create or replace function public._retorno_dito_libera(p_comando jsonb, p_autor uuid, p_agora timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_vazias constant text[] := array['barco', 'lancha', 'veleiro', 'iate', 'motorhome', 'embarcacao', 'servico', 'orcamento',
                                    'cliente', 'ordem', 'dos', 'das', 'pro', 'pra', 'para'];
  v_alvo text := btrim(coalesce(p_comando ->> 'alvo', ''));
  v_desfaz boolean := coalesce((p_comando ->> 'desfaz')::boolean, false);
  v_hoje date := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_r jsonb;
  v_status text;
  v_situacao text;
  v_id uuid;
  v_numero text;
  v_rotulo text;
  v_por_numero boolean;
  v_palavras text[];
  v_token text;
  v_dias integer;
  v_antes timestamptz;
begin
  v_r := public.agenda_resolver_os(v_alvo, v_hoje, false);
  v_status := v_r ->> 'status';

  if v_status = 'ambiguo' then
    return jsonb_build_object('ok', true, 'texto', v_r ->> 'texto');
  end if;
  if v_status = 'nao_achei' then
    return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end if;

  v_id := (v_r ->> 'id')::uuid;
  v_numero := v_r ->> 'numero';
  v_rotulo := format('%s (%s)', v_r ->> 'cliente_curto', v_numero);
  select so.status into v_situacao from public.service_orders so where so.id = v_id;

  -- Fora da carteira, só a OS concluída ou faturada: é o caso de quem vem buscar. O resto recebe a frase da agenda.
  if v_status <> 'ok' and not (v_status = 'fora_da_carteira' and v_situacao in ('completed', 'invoiced')) then
    return jsonb_build_object('ok', true, 'texto', v_r ->> 'texto');
  end if;

  if v_desfaz then
    select so.liberado_retirada_em into v_antes from public.service_orders so where so.id = v_id;
    update public.service_orders set liberado_retirada_em = null, liberado_retirada_por = null where id = v_id;
    insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
    values ('service_orders', v_id, 'update', 'dono', jsonb_build_object('liberado_retirada_em', v_antes),
            jsonb_build_object('liberado_retirada_em', null), 'Retorno: *libera* desfeito pelo dono');
    return jsonb_build_object('ok', true, 'texto', format('Retirada não liberada: %s.', v_rotulo));
  end if;

  -- Por nome, agenda_resolver_os casa por prefixo. Aqui a marca exige a palavra inteira.
  v_por_numero := regexp_replace(public._agenda_normal(v_alvo), '[^a-z0-9]', '', 'g') ~ '^(orcamento|orc|os|ordem)?[0-9]{1,8}$';
  if not v_por_numero then
    select string_to_array(public._agenda_normal(concat_ws(' ', cl.name, cl.display_name, vs.name)), ' ') into v_palavras
      from public.service_orders so
      left join public.clients cl on cl.id = so.client_id
      left join public.vessels vs on vs.id = so.vessel_id
     where so.id = v_id;
    foreach v_token in array string_to_array(public._agenda_normal(v_alvo), ' ') loop
      continue when length(regexp_replace(v_token, '[^a-z]', '', 'g')) < 3 or v_token = any (c_vazias);
      if not v_token = any (coalesce(v_palavras, '{}')) then
        return jsonb_build_object('ok', true,
          'texto', format('Você quis dizer %s? Mande *libera %s*.', v_rotulo, v_numero));
      end if;
    end loop;
  end if;

  update public.service_orders
     set liberado_retirada_em = p_agora, liberado_retirada_por = p_autor
   where id = v_id;
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('service_orders', v_id, 'update', 'dono', jsonb_build_object('liberado_retirada_em', null),
          jsonb_build_object('liberado_retirada_em', p_agora), 'Retorno: *libera* do dono');

  v_dias := greatest(1, floor(extract(epoch from (public._retorno_cfg()).liberado_validade) / 86400))::integer;
  return jsonb_build_object('ok', true,
    'texto', format('Liberei a retirada: %s. Vale por %s dias. *libera %s não* desfaz.', v_rotulo, v_dias, v_alvo));
end;
$$;

comment on function public._retorno_dito_libera(jsonb, uuid, timestamptz) is
  'Retorno F2 (P4): *libera <alvo>* e o desfaz. Vale OS da carteira ou concluída/faturada. Por nome, cada palavra do alvo tem de ser palavra inteira do cadastro; só prefixo pergunta e nada grava. Só marca: não manda nada.';

revoke all on function public._retorno_dito_libera(jsonb, uuid, timestamptz) from public, anon, authenticated;

-- *pessoal*, *pessoal N*. Vale sobre o que retorno_cartao_vivo devolve.
create or replace function public._retorno_dito_pessoal(p_n integer, p_autor uuid, p_agora timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
         atualizado_em = now(), atualizado_por = p_autor;

  perform public._retorno_auditar_palavra(p_autor, jsonb_build_object('lead_tipo', v_antes),
    jsonb_build_object('lead_tipo', 'pessoal', 'abertura', v_ab.id), '*pessoal* do dono');
  perform public._retorno_toque('pessoal', v_cartao, v_ab.id, p_agora);

  return jsonb_build_object('ok', true,
    'texto', format('%s: anotado como pessoal. Esse número nunca mais recebe automático, e cancelei o que estava agendado. *pessoal não* desfaz.', v_rotulo));
end;
$$;

comment on function public._retorno_dito_pessoal(integer, uuid, timestamptz) is
  'Retorno F2 (P4): *pessoal [N]*. Marca o lead do telefone do caso (cria discarded/pessoal se não houver), cancela as saídas agendadas, fecha o caso e tira o item do cartão. Só a palavra do dono marca; *pessoal não* volta em 24 h.';

revoke all on function public._retorno_dito_pessoal(integer, uuid, timestamptz) from public, anon, authenticated;

-- *errado <letra>*: a letra é a gravada no envio, e vale até o fechamento seguinte ao letra_dia.
create or replace function public._retorno_dito_errado(p_letra text, p_agora timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_hoje date := (p_agora at time zone c_fuso)::date;
  v_cfg public.retorno_config := public._retorno_cfg();
  v_s public.retorno_saidas;
  v_dia date;
  v_limite timestamptz;
  v_i integer;
begin
  select s.* into v_s
    from public.retorno_saidas s
   where s.letra = p_letra
     and s.letra_dia <= v_hoje
     and not s.dados ? 'errado_em'
   order by s.letra_dia desc, s.decidida_em desc nulls last, s.id
   limit 1;
  if found then
    v_dia := v_s.letra_dia;
    for v_i in 1 .. 10 loop
      v_dia := v_dia + 1;
      exit when public._retorno_dia_de_tarde(v_dia);
    end loop;
    v_limite := (v_dia + v_cfg.ponto_fechamento) at time zone c_fuso;
  end if;
  if not found or p_agora >= v_limite then
    return jsonb_build_object('ok', true, 'texto', format('Não achei a letra %s no último "Mandei sozinho".', p_letra));
  end if;

  perform public._retorno_rebaixar(v_s.tipo, 'errado', p_agora);
  update public.retorno_saidas s
     set dados = s.dados || jsonb_build_object('errado_em', p_agora), atualizada_em = now()
   where s.id = v_s.id;
  perform public._retorno_toque('errado', null, v_s.abertura_id, p_agora);

  return jsonb_build_object('ok', true,
    'texto', format('Anotei: ''%s'' voltou ao cartão e não sai mais sozinho. Se quiser corrigir com %s, responda pelo celular.',
                    public._retorno_tipo_curto(v_s.tipo), public._retorno_rotulo(v_s.abertura_id, p_agora)));
end;
$$;

comment on function public._retorno_dito_errado(text, timestamptz) is
  'Retorno F2 (P4 e P13): *errado <letra>*. Acha a saída sozinha pela letra gravada no envio, rebaixa o tipo e marca dados.errado_em. Vale até o fechamento seguinte ao letra_dia.';

revoke all on function public._retorno_dito_errado(text, timestamptz) from public, anon, authenticated;

create or replace function public.retorno_dito(p_comando jsonb, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
        update public.retorno_config set segura_recibos = true, atualizado_em = now(), atualizado_por = p_autor;
        v_texto := 'Segurei os recibos: quem escrever agora não recebe recibo, saudação nem coleta, nem depois que você soltar. *solta recibos* vale para as próximas mensagens.';
      elsif v_alvo = 'tudo' then
        v_ate_ts := v_agora + interval '24 hours';
        update public.retorno_config set segura_tudo_ate = v_ate_ts, atualizado_em = now(), atualizado_por = p_autor;
        v_texto := format('Segurei tudo por 24 h, até %s às %s: nada automático do retorno sai ao cliente. *solta tudo* volta antes.',
                          public._retorno_quando((v_ate_ts at time zone c_fuso)::date, v_hoje),
                          to_char(v_ate_ts at time zone c_fuso, 'HH24:MI'));
        if not exists (select 1 from pg_proc p where p.proname = '_agenda_retorno_segurou') then
          v_texto := v_texto || ' A agenda ainda manda o que já estava aprovado: *segura cliente* segura.';
        end if;
      else
        return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
      end if;
      v_user := 'segura ' || v_alvo;
      perform public._retorno_auditar_palavra(p_autor, jsonb_build_object('segura_recibos', v_cfg.segura_recibos, 'segura_tudo_ate', v_cfg.segura_tudo_ate),
        jsonb_build_object('alvo', v_alvo), '*segura* do dono');

    when 'solta' then
      if v_alvo = 'recibos' then
        update public.retorno_config set segura_recibos = false, atualizado_em = now(), atualizado_por = p_autor;
        v_texto := 'Recibos soltos: valem para as próximas mensagens.';
      elsif v_alvo = 'tudo' then
        update public.retorno_config
           set segura_tudo_ate = null, segura_recibos = false, atualizado_em = now(), atualizado_por = p_autor;
        update public.retorno_saidas s
           set enviar_em = v_agora, atualizada_em = now()
         where s.estado = 'agendada' and s.dados ? 'segurada';
        get diagnostics v_k = row_count;
        v_texto := case when v_k = 0 then 'Soltei: o automático volta a sair.'
                        else format('Soltei: o automático volta a sair. %s que ficaram no meio saem agora; quem escreveu há mais de 12 h fica com você.', v_k) end;
      else
        return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
      end if;
      v_user := 'solta ' || v_alvo;
      perform public._retorno_auditar_palavra(p_autor, jsonb_build_object('segura_recibos', v_cfg.segura_recibos, 'segura_tudo_ate', v_cfg.segura_tudo_ate),
        jsonb_build_object('alvo', v_alvo), '*solta* do dono');

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
        update public.retorno_config set fora_ate = null, atualizado_em = now(), atualizado_por = p_autor;
        v_texto := 'Anotado: você voltou, e o recibo volta ao normal.';
      else
        update public.retorno_config set fora_ate = v_ate, atualizado_em = now(), atualizado_por = p_autor;
        v_texto := format('Anotado: até %1$s o recibo diz que você está fora e que responde %1$s até as %2$s. *fora até hoje* desfaz.',
                          public._retorno_quando(v_ate, v_hoje), public._retorno_hora(v_cfg.promessa_manha));
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

    when 'pessoal_desfaz' then
      v_antes := v_cfg.pessoal_ultimo;
      if v_antes is null or v_agora - (v_antes ->> 'em')::timestamptz > interval '24 hours' then
        return jsonb_build_object('ok', true, 'texto', 'Não há *pessoal* recente para desfazer.');
      end if;
      update public.whatsapp_leads l
         set lead_tipo = v_antes ->> 'lead_tipo_antes', updated_at = now()
       where l.phone_normalized = v_antes ->> 'phone';
      update public.retorno_config set pessoal_ultimo = null, atualizado_em = now(), atualizado_por = p_autor;
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
$$;

comment on function public.retorno_dito(jsonb, uuid, timestamptz) is
  'Retorno F2 (C-PAL): as palavras do dono sem cartão. {"ok", "texto", "historico"?, "cartao_id"?, "seguir_ao_modelo"?}. Só o dono: outro autor recebe {"ok": false, "motivo": "nao_e_o_dono"}. O historico nunca leva texto do cliente.';

revoke all on function public.retorno_dito(jsonb, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_dito(jsonb, uuid, timestamptz) to service_role;

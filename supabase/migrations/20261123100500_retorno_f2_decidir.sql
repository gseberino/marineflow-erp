-- Retorno rápido ao cliente, F2 (P8): decidir e executar o cartão.
--
-- retorno_decidir_dito lê a palavra do dono sobre o cartão vivo: as letras, *só*, *sem*, *não N* e *dita N*. Nada aqui manda
-- mensagem. *só* e *sem* só marcam selecionado, e *retorno* restaura: *só 2* como resposta a outra coisa não custa nada.
--
-- As letras B e C (a peça chegou, a previsão) passam pelo caminho do *grava* da agenda: agenda_rascunho_material e
-- agenda_rascunho_gravar, na mesma transação. Com rascunho aberto do dono, recusa: gravar misturaria os dois.
--
-- retorno_cartao_executar roda no *sim <PIN>*, pela pendência. O texto que sai é o que o dono viu, byte a byte (trava por hash).
-- Ditado substitui o modelo do item: os dois juntos seriam 2 mensagens ao cliente. "Vai sair", nunca "Mandei": a saída ainda passa
-- pelo validador, pelo canal e pela regra 2.
--
-- O telefone sai do caso, nunca de argumento.
--
-- A aprovação do tipo conta na saída enviada (P10), não aqui: o que o validador recusou não ensina nada.
--
-- Reverter: drop das funções abaixo. A camada trata função ausente como "segue como sempre".

-- Remonta o item com o fato de agora, regrava as linhas e o texto do cartão.
create or replace function public._retorno_item_remontar(p_item uuid, p_agora timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_i public.retorno_cartao_itens;
  v jsonb;
begin
  select * into v_i from public.retorno_cartao_itens i where i.id = p_item;
  v := public._retorno_item_montar(v_i.abertura_id, v_i.n, p_agora);
  update public.retorno_cartao_itens i
     set tipo_item = v ->> 'tipo_item', modelo_tipo = v ->> 'modelo_tipo', service_order_id = (v ->> 'service_order_id')::uuid,
         texto_mostrado = v ->> 'texto_mostrado', opcoes = v -> 'opcoes', fatos = v -> 'fatos', hash = v ->> 'hash', escolha = null
   where i.id = p_item;
  update public.retorno_cartoes c
     set dados = jsonb_set(c.dados, array['linhas', v_i.n::text], v -> 'linhas', true)
   where c.id = v_i.cartao_id;
  update public.retorno_cartoes c set texto = public._retorno_cartao_texto(c.id, null) where c.id = v_i.cartao_id;
  return v;
end;
$$;

comment on function public._retorno_item_remontar(uuid, timestamptz) is
  'Retorno F2 (P8): remonta o item do cartão com o fato de agora, depois de uma letra.';

revoke all on function public._retorno_item_remontar(uuid, timestamptz) from public, anon, authenticated;

-- "só o 3", "1 e 3", "1, 2 e 3".
create or replace function public._retorno_lista_de_casos(p_ns integer[])
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when cardinality(p_ns) = 1 then 'só o ' || p_ns[1]
    when cardinality(p_ns) = 2 then p_ns[1] || ' e ' || p_ns[2]
    else array_to_string(p_ns[1:cardinality(p_ns) - 1], ', ') || ' e ' || p_ns[cardinality(p_ns)]
  end;
$$;

revoke all on function public._retorno_lista_de_casos(integer[]) from public, anon, authenticated;

-- Fecha o cartão pelo *não*: pendência rejeitada, ponteiro limpo só se for o dele, pergunta fechada.
create or replace function public._retorno_cartao_recusar(p_cartao uuid, p_agora timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c public.retorno_cartoes;
begin
  select * into v_c from public.retorno_cartoes c where c.id = p_cartao;
  update public.retorno_cartoes c
     set estado = 'decidido', decidido_em = p_agora, decidido_por = 'nao'
   where c.id = p_cartao;
  update public.retorno_cartao_itens i set estado = 'fora' where i.cartao_id = p_cartao and i.estado = 'vivo';
  if v_c.pendencia_id is not null then
    update public.ai_operator_pending_actions p
       set status = 'rejected', rejected_at = p_agora
     where p.id = v_c.pendencia_id and p.status = 'pending';
    update public.ai_operator_sessions s
       set metadata = s.metadata - 'pending_confirm_action_id'
     where s.id = v_c.sessao_id and s.metadata ->> 'pending_confirm_action_id' = v_c.pendencia_id::text;
  end if;
  if v_c.pergunta_id is not null then
    perform public._pergunta_fechar(v_c.pergunta_id, 'cancelada', 'cartao_recusado', null);
  end if;
end;
$$;

revoke all on function public._retorno_cartao_recusar(uuid, timestamptz) from public, anon, authenticated;

-- A linha de material pelo caminho do *grava*. Devolve {ok, texto}: ok falso deixa tudo como estava.
create or replace function public._retorno_material(p_dono uuid, p_numero text, p_situacao text, p_quando text, p_trecho text, p_hoje date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  v := public.agenda_rascunho_material(p_dono, 'whatsapp', p_numero, array['tudo'], p_situacao, p_quando, null, null, false, p_trecho, p_hoje);
  if not coalesce((v ->> 'ok')::boolean, false) then
    return jsonb_build_object('ok', false, 'texto', coalesce(v ->> 'texto', 'Não consegui anotar agora.'));
  end if;
  v := public.agenda_rascunho_gravar(p_dono, p_hoje);
  if not coalesce((v ->> 'ok')::boolean, false) then
    return jsonb_build_object('ok', false, 'texto', coalesce(v ->> 'texto', 'Não consegui gravar agora.'));
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

comment on function public._retorno_material(uuid, text, text, text, text, date) is
  'Retorno F2 (P8.3): a peça pelo caminho do *grava* da agenda: agenda_rascunho_material e agenda_rascunho_gravar, nada paralelo. ok falso traz o texto da agenda ao dono.';

revoke all on function public._retorno_material(uuid, text, text, text, text, date) from public, anon, authenticated;

create or replace function public._retorno_decidir_letra(p_item public.retorno_cartao_itens, p_comando jsonb, p_dono uuid, p_agora timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_hoje date := (p_agora at time zone c_fuso)::date;
  v_letra text := upper(coalesce(p_comando ->> 'letra', ''));
  v_resto text := nullif(btrim(p_comando ->> 'resto'), '');
  v_op jsonb;
  v_rotulo text := public._retorno_rotulo(p_item.abertura_id, p_agora);
  v_r jsonb;
  v_item jsonb;
  v_m jsonb;
  v_nivel text;
  v_texto text;
  v_dia date;
  v_prov uuid;
  v_ves uuid;
begin
  select o into v_op from jsonb_array_elements(p_item.opcoes) o where o ->> 'letra' = v_letra limit 1;
  if v_op is null then
    return jsonb_build_object('ok', true, 'texto', format('O caso %s não tem a opção %s, e nada foi feito.', p_item.n, v_letra));
  end if;

  case v_op ->> 'acao'
    when 'chegou', 'previsao' then
      if v_op ->> 'acao' = 'previsao' and v_resto is null then
        return jsonb_build_object('ok', true, 'texto', format('Diga a previsão: *%s C dia 14*.', p_item.n));
      end if;
      if exists (select 1 from public.agenda_rascunho r where r.autor = p_dono and r.estado = 'aberto' and r.expira_em > p_agora) then
        return jsonb_build_object('ok', true, 'texto', 'Tem um rascunho aberto: mande *grava* ou *descarta* antes.');
      end if;
      if v_op ->> 'acao' = 'chegou' then
        v_r := public._retorno_material(p_dono, v_op ->> 'os', 'na_mao', null, format('cartão do retorno: %s B', p_item.n), v_hoje);
      else
        v_r := public._retorno_material(p_dono, v_op ->> 'os', 'a_caminho', v_resto,
                                        format('cartão do retorno: %s C %s', p_item.n, v_resto), v_hoje);
      end if;
      if not (v_r ->> 'ok')::boolean then
        return jsonb_build_object('ok', true, 'texto', v_r ->> 'texto');
      end if;

      if v_op ->> 'acao' = 'previsao' then
        select max(m.previsao_ate) into v_dia from public.os_material m
         where m.service_order_id = p_item.service_order_id and m.critico and m.situacao = 'a_caminho';
        perform public._retorno_item_remontar(p_item.id, p_agora);
        return jsonb_build_object('ok', true,
          'texto', format('Anotei: previsão %s. Só você vê: ao cliente não vai data.', coalesce(to_char(v_dia, 'DD/MM'), 'anotada')));
      end if;

      v_item := public._retorno_item_remontar(p_item.id, p_agora);
      v_m := public._retorno_modelo_do_caso(p_item.abertura_id, p_agora);
      select t.nivel into v_nivel from public.retorno_modelo_tipos t where t.tipo = 'modelo_peca_chegou';
      if v_m ->> 'modelo' = 'modelo_peca_chegou' and v_nivel = 'cartao' then
        return jsonb_build_object('ok', true, 'precisa_pin', true,
          'texto', format('Anotei: chegou hoje. Mando a %s: ''%s''? *sim <PIN>*', v_rotulo, v_item ->> 'texto_mostrado'));
      elsif v_m ->> 'modelo' = 'modelo_peca_chegou' and v_nivel = 'sozinho' then
        perform public._retorno_agendar_modelo(p_item.abertura_id, v_m, p_agora);
        return jsonb_build_object('ok', true, 'texto', format('Anotei: chegou hoje. Vai sair a %s.', v_rotulo));
      end if;
      return jsonb_build_object('ok', true, 'texto', 'Anotei: chegou hoje. A agenda avisa o cliente quando marcar o dia.');

    when 'responder' then
      v_texto := public._retorno_texto_do_modelo(p_item.abertura_id,
        jsonb_build_object('modelo', v_op ->> 'modelo', 'os_id', v_op ->> 'os_id'), null, p_agora);
      update public.retorno_cartao_itens i
         set texto_mostrado = v_texto, modelo_tipo = v_op ->> 'modelo', escolha = v_letra, selecionado = true
       where i.id = p_item.id;
      update public.retorno_cartoes c set texto = public._retorno_cartao_texto(c.id, null) where c.id = p_item.cartao_id;
      return jsonb_build_object('ok', true, 'precisa_pin', true,
        'texto', format('Vou mandar a %s: ''%s''. *sim <PIN>* manda.', v_rotulo, v_texto));

    when 'cliente' then
      -- Vale só para este caso: não vincula o número nem regrava mensagem.
      update public.retorno_aberturas a
         set client_id = (v_op ->> 'client_id')::uuid, papel = 'cliente', atualizada_em = now()
       where a.id = p_item.abertura_id;
      v_item := public._retorno_item_remontar(p_item.id, p_agora);
      return jsonb_build_object('ok', true, 'texto', (select string_agg(l, E'\n') from jsonb_array_elements_text(v_item -> 'linhas') l));

    when 'desfaz_cadastro' then
      v_prov := (v_op ->> 'client_id')::uuid;
      select (a.new_value ->> 'vessel_id')::uuid into v_ves
        from public.audit_log a
       where a.table_name = 'clients' and a.record_id = v_prov and a.new_value ->> 'caso' = p_item.abertura_id::text
       limit 1;
      update public.clients c set active = false where c.id = v_prov;
      update public.vessels v set active = false where v.id = v_ves;
      insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
      values ('clients', v_prov, 'update', 'dono', jsonb_build_object('active', true), jsonb_build_object('active', false),
              'Cadastro provisório desfeito pelo dono no cartão do retorno');
      return jsonb_build_object('ok', true, 'texto', 'Cadastro provisório desfeito. Nada foi apagado.');

    else
      return jsonb_build_object('ok', true, 'texto', format('O caso %s não tem a opção %s, e nada foi feito.', p_item.n, v_letra));
  end case;
end;
$$;

comment on function public._retorno_decidir_letra(public.retorno_cartao_itens, jsonb, uuid, timestamptz) is
  'Retorno F2 (P8.3): a letra escolhida no item: chegou e previsão pelo caminho do *grava*, responder (precisa de *sim <PIN>*), cliente do número ambíguo (só neste caso) e desfazer o cadastro provisório.';

revoke all on function public._retorno_decidir_letra(public.retorno_cartao_itens, jsonb, uuid, timestamptz) from public, anon, authenticated;

create or replace function public.retorno_decidir_dito(p_comando jsonb, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cmd text := p_comando ->> 'comando';
  v_n integer := (p_comando ->> 'n')::integer;
  v_ns integer[] := case when jsonb_typeof(p_comando -> 'ns') = 'array'
                         then array(select (x)::integer from jsonb_array_elements_text(p_comando -> 'ns') x) end;
  v_vivo jsonb;
  v_cartao uuid;
  v_k integer;
  v_item public.retorno_cartao_itens;
  v_r jsonb;
  v_sel integer[];
  v_texto text;
  v_ditado text;
  v_aviso text;
  v_palavra text;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return jsonb_build_object('ok', false, 'motivo', 'nao_e_o_dono');
  end if;
  v_vivo := public.retorno_cartao_vivo(v_agora);
  if v_vivo is null then
    return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end if;
  if v_vivo ->> 'estado' = 'lista' then
    return jsonb_build_object('ok', true, 'texto', 'Esta lista é só para consulta. Mande *retorno* quando o pedido aberto terminar.');
  end if;
  v_cartao := (v_vivo ->> 'id')::uuid;

  select count(*) into v_k from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo';
  if (v_n is not null and not exists (select 1 from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = v_n and i.estado = 'vivo'))
     or (v_ns is not null and exists (select 1 from unnest(v_ns) x
                                       where not exists (select 1 from public.retorno_cartao_itens i
                                                          where i.cartao_id = v_cartao and i.n = x and i.estado = 'vivo'))) then
    return jsonb_build_object('ok', true, 'texto', format('O cartão tem %s casos.', v_k));
  end if;
  if v_n is not null then
    select * into v_item from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = v_n;
  end if;

  case v_cmd
    when 'escolher' then
      v_palavra := 'letra';
      v_r := public._retorno_decidir_letra(v_item, p_comando, p_autor, v_agora);
      perform public._retorno_toque(v_palavra, v_cartao, v_item.abertura_id, v_agora);
      return v_r || jsonb_build_object('historico', jsonb_build_object('user', format('(escolheu %s no caso %s)', upper(p_comando ->> 'letra'), v_n),
                                                                       'assistant', format('(anotei a escolha do caso %s)', v_n)));

    when 'so', 'sem' then
      update public.retorno_cartao_itens i
         set selecionado = case when v_cmd = 'so' then i.n = any (v_ns) else not (i.n = any (v_ns)) end
       where i.cartao_id = v_cartao and i.estado = 'vivo';
      select array_agg(i.n::integer order by i.n) into v_sel
        from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo' and i.selecionado;
      perform public._retorno_toque(v_cmd, v_cartao, null, v_agora);
      if v_sel is null then
        return jsonb_build_object('ok', true, 'texto', 'Nada ficou selecionado. *retorno* volta ao cartão inteiro.',
          'historico', jsonb_build_object('user', format('(%s)', v_cmd), 'assistant', '(nada selecionado no cartão)'));
      end if;
      v_texto := format('Fica %s. *sim <PIN>* manda. *retorno* volta ao cartão inteiro.', public._retorno_lista_de_casos(v_sel));
      return jsonb_build_object('ok', true, 'precisa_pin', true, 'texto', v_texto,
        'historico', jsonb_build_object('user', format('(%s %s)', v_cmd, array_to_string(v_ns, ' ')), 'assistant', v_texto));

    when 'tirar' then
      update public.retorno_cartao_itens i set selecionado = false where i.cartao_id = v_cartao and i.estado = 'vivo' and i.n = any (v_ns);
      perform public._retorno_toque('tirar', v_cartao, null, v_agora);
      if not exists (select 1 from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo' and i.selecionado) then
        perform public._retorno_cartao_recusar(v_cartao, v_agora);
        return jsonb_build_object('ok', true, 'texto', 'Cartão fechado: nada foi mandado.',
          'historico', jsonb_build_object('user', '(tirou os casos do cartão)', 'assistant', 'Cartão fechado: nada foi mandado.'));
      end if;
      v_texto := case when cardinality(v_ns) = 1 then format('Tirei o %s. O relógio dele continua.', v_ns[1])
                      else format('Tirei o %s. O relógio deles continua.', array_to_string(v_ns, ' e o ')) end;
      return jsonb_build_object('ok', true, 'texto', v_texto,
        'historico', jsonb_build_object('user', format('(não %s)', array_to_string(v_ns, ' ')), 'assistant', v_texto));

    when 'ditar' then
      v_ditado := btrim(coalesce(p_comando ->> 'texto', ''));
      if v_ditado = '' then
        return jsonb_build_object('ok', true, 'texto', format('Diga o texto: *dita %s pode buscar amanhã*.', v_n));
      end if;
      update public.retorno_cartao_itens i
         set texto_ditado = v_ditado, ditado_via = 'dita', selecionado = true
       where i.id = v_item.id;
      update public.retorno_cartoes c set texto = public._retorno_cartao_texto(c.id, null) where c.id = v_cartao;
      perform public._retorno_toque('dita', v_cartao, v_item.abertura_id, v_agora);
      v_aviso := case when v_ditado ~* '(R\$|\yreais\y|[0-9]+[[:space:]]*mil\y)' then ' (tem valor no texto)' else '' end;
      return jsonb_build_object('ok', true, 'precisa_pin', true,
        'texto', format('Vou mandar a %s, exatamente: ''%s''.%s', public._retorno_rotulo(v_item.abertura_id, v_agora), v_ditado, v_aviso)
                 || E'\n' || format('*sim <PIN>* manda o que está no cartão · *dita %1$s …* troca · *não %1$s* tira.', v_n),
        'historico', jsonb_build_object('user', format('(ditou a resposta do caso %s)', v_n),
                                        'assistant', format('(anotei o ditado do caso %s)', v_n)));

    else
      return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end case;
end;
$$;

comment on function public.retorno_decidir_dito(jsonb, uuid, timestamptz) is
  'Retorno F2 (C-DEC): as palavras sobre o cartão vivo. {"ok", "texto", "precisa_pin"?, "historico"?}. Nada aqui manda mensagem, e o historico nunca leva o texto do cliente nem o ditado.';

revoke all on function public.retorno_decidir_dito(jsonb, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_decidir_dito(jsonb, uuid, timestamptz) to service_role;

create or replace function public.retorno_cartao_executar(p_cartao uuid, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_c public.retorno_cartoes;
  v_i public.retorno_cartao_itens;
  v_ab public.retorno_aberturas;
  v_conf jsonb;
  v_frases text[] := '{}';
  v_ditados jsonb := '[]'::jsonb;
  v_rotulos text[] := '{}';
  v_n integer := 0;
  v_saida uuid;
  v_op jsonb;
  v_aviso text;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return jsonb_build_object('ok', false, 'aviso', 'Só o dono executa o cartão.');
  end if;
  select * into v_c from public.retorno_cartoes c where c.id = p_cartao for update;
  if not found or v_c.estado <> 'vivo' then
    return jsonb_build_object('ok', false, 'aviso', 'Esse cartão já foi decidido.');
  end if;

  update public.retorno_cartao_itens i set estado = 'fora' where i.cartao_id = p_cartao and i.estado = 'vivo' and not i.selecionado;

  for v_i in select i.* from public.retorno_cartao_itens i where i.cartao_id = p_cartao and i.estado = 'vivo' order by i.n loop
    v_conf := public._retorno_item_conferir(v_i.id, v_agora, true);
    if not (v_conf ->> 'ok')::boolean then
      update public.retorno_cartao_itens i set estado = 'caiu', caiu_motivo = v_conf ->> 'motivo', decidido_em = v_agora where i.id = v_i.id;
      v_frases := v_frases || (v_conf ->> 'texto');
      continue;
    end if;
    select * into v_ab from public.retorno_aberturas a where a.id = v_i.abertura_id;

    if v_i.texto_ditado is not null then
      v_ditados := v_ditados || jsonb_build_array(jsonb_build_object(
        'item_id', v_i.id, 'phone', v_ab.phone_normalized, 'texto', v_i.texto_ditado,
        'dedupe_key', 'retorno:' || v_ab.id || ':ditado:' || md5(v_i.texto_ditado)));
      v_n := v_n + 1;
      v_rotulos := v_rotulos || public._retorno_rotulo(v_ab.id, v_agora);
    elsif v_i.modelo_tipo is not null then
      if v_cfg.modo <> 'ligado' then
        v_frases := v_frases || 'O retorno está em teste: não mandei.'::text;
      elsif v_cfg.segura_tudo_ate is not null and v_cfg.segura_tudo_ate > v_agora then
        v_frases := v_frases || '*segura tudo* está ligado: não mandei.'::text;
      elsif exists (select 1 from public.retorno_saidas s
                     where s.abertura_id = v_ab.id and s.tipo like 'modelo\_%' escape '\'
                       and s.estado in ('agendada', 'preparada', 'enviando')) then
        v_frases := v_frases || format('o %s já está saindo', v_i.n);
      else
        select o into v_op from jsonb_array_elements(v_i.opcoes) o where o ->> 'letra' = v_i.escolha limit 1;
        insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, client_id, modo, estado,
                                           enviar_em, dados, dedupe_key)
        values (v_ab.id, v_i.modelo_tipo, 'aprovado', 'retorno_modelo', 'resposta_imediata', v_ab.chave, v_ab.phone_normalized, v_ab.client_id,
                'ligado', 'agendada', v_agora,
                jsonb_build_object('aprovada', true, 'aprovada_em', v_agora, 'cartao_id', p_cartao, 'item_id', v_i.id,
                                   'texto_aprovado', v_i.texto_mostrado, 'hash', v_i.hash, 'os_id', v_i.service_order_id,
                                   'marca_liberado', coalesce((v_op ->> 'marca_liberado')::boolean, false)),
                'retorno:' || v_ab.id || ':modelo:' || v_i.id)
        returning id into v_saida;
        update public.retorno_cartao_itens i set saida_id = v_saida where i.id = v_i.id;
        if coalesce((v_op ->> 'marca_liberado')::boolean, false) and v_i.service_order_id is not null then
          update public.service_orders so
             set liberado_retirada_em = v_agora, liberado_retirada_por = p_autor
           where so.id = v_i.service_order_id;
        end if;
        v_n := v_n + 1;
        v_rotulos := v_rotulos || public._retorno_rotulo(v_ab.id, v_agora);
      end if;
    else
      update public.retorno_cartao_itens i set estado = 'fora' where i.id = v_i.id;
      continue;
    end if;

    update public.retorno_cartao_itens i set estado = 'feito', decidido_em = v_agora where i.id = v_i.id;
  end loop;

  update public.retorno_cartoes c
     set estado = 'decidido', decidido_em = v_agora, decidido_por = 'sim_pin'
   where c.id = p_cartao;
  perform public._retorno_toque('sim_pin', p_cartao, null, v_agora);

  if v_n > 0 then
    v_aviso := format('Vai sair %s: %s.', v_n, array_to_string(v_rotulos, ', '));
  elsif cardinality(v_frases) = 0 then
    v_aviso := 'Nada para mandar neste cartão. *retorno* abre de novo: use *dita N* ou a letra antes do *sim*.';
  end if;
  v_aviso := concat_ws(' ', v_aviso, nullif(array_to_string(v_frases, ' · '), ''),
                       case when v_c.mais > 0 then format('Mais %s esperando: *retorno*.', v_c.mais) end);

  return jsonb_build_object('ok', true, 'aviso', v_aviso, 'ditados', v_ditados, 'vai_sair', v_n);
end;
$$;

comment on function public.retorno_cartao_executar(uuid, uuid, timestamptz) is
  'Retorno F2 (C-EXEC): executa o cartão no *sim <PIN>*. Item que caiu sai com a frase; ditado substitui o modelo; o modelo vira saída agendada com o texto aprovado. {"ok", "aviso", "ditados", "vai_sair"}. O aviso só leva rótulos.';

revoke all on function public.retorno_cartao_executar(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_cartao_executar(uuid, uuid, timestamptz) to service_role;

create or replace function public.retorno_item_enviado(p_item uuid, p_ok boolean, p_wa_id text default null, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_i public.retorno_cartao_itens;
begin
  select * into v_i from public.retorno_cartao_itens i where i.id = p_item for update;
  if not found then
    return jsonb_build_object('ok', false);
  end if;
  if not p_ok then
    update public.retorno_cartao_itens i set estado = 'fora' where i.id = p_item;
    return jsonb_build_object('ok', true);
  end if;
  -- Ditado curto não cumpre pela régua da F1 (15 caracteres), e o cliente ouviria o adiamento depois da resposta do dono.
  update public.retorno_aberturas a
     set cumprida_em = coalesce(a.cumprida_em, v_agora), cumprida_por = coalesce(a.cumprida_por, 'cartao'),
         estado = 'fechada', fechada_em = coalesce(a.fechada_em, v_agora), fechada_motivo = coalesce(a.fechada_motivo, 'conteudo'),
         atualizada_em = now()
   where a.id = v_i.abertura_id;
  update public.retorno_saidas s
     set estado = 'cancelada', motivo = 'caso_fechado', decidida_em = v_agora, atualizada_em = now()
   where s.abertura_id = v_i.abertura_id and s.estado = 'agendada';
  return jsonb_build_object('ok', true);
end;
$$;

comment on function public.retorno_item_enviado(uuid, boolean, text, timestamptz) is
  'Retorno F2 (C-ITEM): depois de cada ditado. ok cumpre e fecha o caso e cancela as agendadas; falha devolve o item a fora, e o relógio continua.';

revoke all on function public.retorno_item_enviado(uuid, boolean, text, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_item_enviado(uuid, boolean, text, timestamptz) to service_role;

-- *ver N* ganha o que se sabe e as opções: as linhas do item depois da primeira.
create or replace function public.retorno_ver_caso(p_n integer, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_vivo jsonb;
  v_cartao uuid;
  v_item public.retorno_cartao_itens;
  v_recebidas text;
  v_extras text;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return jsonb_build_object('ok', false, 'motivo', 'nao_e_o_dono');
  end if;
  v_vivo := public.retorno_cartao_vivo(v_agora);
  if v_vivo is null then
    return jsonb_build_object('ok', true, 'texto', 'Não há lista aberta. Mande *retorno*.');
  end if;
  v_cartao := (v_vivo ->> 'id')::uuid;
  select * into v_item from public.retorno_cartao_itens i
   where i.cartao_id = v_cartao and i.n = p_n and i.estado = 'vivo';
  if not found then
    return jsonb_build_object('ok', true, 'texto', format('Não há caso %s nesta lista. Mande *retorno*.', p_n));
  end if;

  select string_agg(x.linha, E'\n' order by x.recebida_em, x.id)
    into v_recebidas
    from (select m.recebida_em, m.whatsapp_message_id as id,
                 to_char(m.recebida_em at time zone 'America/Sao_Paulo', 'HH24:MI') || ' '
                   || public._retorno_trecho(w.body, w.message_type, m.audio_pendente, 300) as linha
            from public.retorno_mensagens m
            join public.whatsapp_messages w on w.id = m.whatsapp_message_id
           where m.abertura_id = v_item.abertura_id and m.recebida_em <= v_agora
           order by m.recebida_em desc, m.whatsapp_message_id desc
           limit 5) x;

  select string_agg(btrim(l.linha), E'\n' order by l.ord)
    into v_extras
    from public.retorno_cartoes c
    cross join lateral jsonb_array_elements_text(coalesce(c.dados -> 'linhas' -> p_n::text, '[]'::jsonb)) with ordinality as l(linha, ord)
   where c.id = v_cartao and l.ord > 1;

  perform public._retorno_toque('ver', v_cartao, v_item.abertura_id, v_agora);

  return jsonb_build_object('ok', true,
    'texto', concat_ws(E'\n', format('%s · %s', public._retorno_rotulo(v_item.abertura_id, v_agora),
                                     public._retorno_prazo_curto(v_item.abertura_id, v_agora)),
                       v_recebidas, v_extras),
    'historico', jsonb_build_object('user', format('(ver %s)', p_n),
                                    'assistant', format('(mostrei o caso %s ao dono)', p_n)));
end;
$$;

revoke all on function public.retorno_ver_caso(integer, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_ver_caso(integer, uuid, timestamptz) to service_role;

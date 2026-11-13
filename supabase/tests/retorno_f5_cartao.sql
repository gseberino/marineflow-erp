-- Retorno F5 (P7): o cartão. Gerado por script (scripts/gerar_f5.cjs cartao) a partir de scripts/f5_sql/p7_teste_cartao.sql: as
-- cópias de antes da F5 no início são o corpo vigente de retorno_cartao_abrir e _retorno_cartao_texto (20261208100400),
-- renomeadas para pg_temp e sem security definer (a referência do nº 1: o cartão byte a byte igual sem a F5). Roda só pela
-- bancada (grupo 8, F5_ONDA=5, F5_TESTES=retorno_f5_cartao). Termina em ROLLBACK; cada cenário roda no seu sub-bloco, que se
-- desfaz sozinho (raise 'f5c_cenario'). Só confere as próprias linhas sintéticas: telefones inventados 55479000099xx (a chave sai
-- do telefone: 000099xx), nomes inventados (Ana, João, Pedro, Caio, Bia, Rodrigo), documentos inventados (ORÇ-996xx), frases
-- inventadas. Nenhuma mensagem real é lida. Relógio antes do 1º caso real (11/11/2026): o orçamento vai na seg 19/10/2026 10:00
-- (validade seg 26/10), o "Pode fazer." é de ter 20/10 14:05 e o cartão abre na qua 21/10 09:30; o lembrete espera de qua 21/10
-- até qui 22/10. O *sim 7391* (o PIN é de teste) chega ao banco como retorno_cartao_executar(cartão, dono): o PIN é conferido
-- no TS antes; aqui ele nunca é lido nem comparado. O id do dono vem de _comprovante_dono (só o id e o telefone, para a sessão).
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- As cópias de antes da F5, com o nome pg_temp.f5c_antes_*. Não são chamadas em produção.

create or replace function pg_temp.f5c_antes_cartao_texto(p_cartao uuid, p_cabeca text)
returns text
language plpgsql
stable
as $$
declare
  v_c public.retorno_cartoes;
  v_vivos integer;
  v_cabeca text;
  v_corpo text;
  v_primeiro smallint;
  v_mandam smallint[];
  v_faz text;
  v_rodape text;
  v_max boolean;
  -- F3 (P5)
  v_orc smallint[];
  v_orc_acao text;
  v_tem_proposta boolean;
  v_final text;
  v_lim integer;
begin
  select * into v_c from public.retorno_cartoes c where c.id = p_cartao;
  select count(*), min(i.n) into v_vivos, v_primeiro
    from public.retorno_cartao_itens i where i.cartao_id = p_cartao and i.estado = 'vivo';

  v_cabeca := coalesce(p_cabeca, case when v_c.gatilho = 'meio_dia' then format('Retorno · meio-dia · %s esperando', v_vivos + v_c.mais)
                                      else format('Retorno · %s esperando', v_vivos + v_c.mais) end);

  select string_agg(l.linha, E'\n' order by i.n, l.ord)
    into v_corpo
    from public.retorno_cartao_itens i
    cross join lateral jsonb_array_elements_text(coalesce(v_c.dados -> 'linhas' -> i.n::text, '[]'::jsonb))
         with ordinality as l(linha, ord)
   where i.cartao_id = p_cartao and i.estado = 'vivo';

  if v_c.estado = 'vivo' then
    select array_agg(i.n order by i.n) into v_mandam
      from public.retorno_cartao_itens i
     where i.cartao_id = p_cartao and i.estado = 'vivo' and (i.modelo_tipo is not null or i.texto_ditado is not null);
    -- F3 (P5): item com acao_sim, sem ditado e sem provisório entra no que o *sim <PIN>* faz. Item com provisório e item com texto_ditado, não.
    select array_agg(i.n order by i.n), min(i.acao_sim)
      into v_orc, v_orc_acao
      from public.retorno_cartao_itens i
      left join public.retorno_previa p on p.id = i.previa_id
     where i.cartao_id = p_cartao and i.estado = 'vivo' and i.acao_sim is not null and i.texto_ditado is null
       and (i.acao_sim = 'pdf' or coalesce(p.provisorios_n, 0) = 0);
    if v_orc is not null then
      select array_agg(x order by x) into v_mandam
        from (select unnest(v_mandam) as x union select unnest(v_orc)) t;
    end if;
    select exists (select 1 from public.retorno_cartao_itens i where i.cartao_id = p_cartao and i.estado = 'vivo' and i.previa_id is not null)
      into v_tem_proposta;
    if cardinality(v_mandam) > 0 then
      v_faz := case when cardinality(v_mandam) = 1 then format('o %s', v_mandam[1])
                    when cardinality(v_mandam) = 2 then format('o %s e o %s', v_mandam[1], v_mandam[2])
                    else 'os 3' end;
      -- F3 (P5): um item só de orçamento diz o que o *sim <PIN>* faz.
      if cardinality(v_mandam) = 1 and v_orc is not null then
        v_faz := v_faz || case when v_orc_acao = 'pdf' then ' (manda o PDF)' else ' (cria o orçamento e manda o PDF)' end;
      end if;
      v_rodape := format('*sim <PIN>* faz %s · *só %s* · *ver %s* · *não* · ou dite por áudio', v_faz, v_mandam[1], v_primeiro);
    elsif v_primeiro is null then
      v_rodape := 'Nada mais neste cartão. *retorno* abre de novo.';
    else
      v_rodape := format('*ver %1$s* · *dita %1$s …* · *não* · ou dite por áudio', v_primeiro);
    end if;
    -- F3 (P5): com proposta, o áudio dita o que mudar nela.
    if v_tem_proposta then
      v_rodape := replace(v_rodape, 'ou dite por áudio', 'ou dite o que mudar');
    end if;
    begin
      v_max := public.ai_claude_max_disponivel();
      if v_max is false then
        v_rodape := v_rodape || E'\n' || '(Seu assistente está fora: responda com as letras ou pelo celular.)';
      end if;
    exception when others then
      null;   -- erro ao ler: a linha não aparece
    end;
  else
    v_rodape := v_c.dados ->> 'rodape';
  end if;

  v_final := concat_ws(E'\n', v_cabeca, v_corpo,
                       case when v_c.mais > 0 then format('e mais %s: *retorno*', v_c.mais) end,
                       v_rodape);
  -- F3 (P5): retorno_cartoes.texto tem CHECK de 3.500 (estourar derruba o *retorno* inteiro). As linhas C30 (as que começam com "   · ") são as primeiras a sair.
  if char_length(v_final) > 3500 then
    foreach v_lim in array array[8, 6, 4, 2, 0] loop
      select string_agg(case when not x.c30 or x.k30 <= v_lim then x.linha
                             else format('   · e mais %s: *ver %s*', x.total30 - v_lim, x.n) end,
                        E'\n' order by x.n, x.ord)
        into v_corpo
        from (select i.n, l.ord, l.linha, l.linha like '   · %' as c30,
                     count(*) filter (where l.linha like '   · %') over (partition by i.n order by l.ord) as k30,
                     count(*) filter (where l.linha like '   · %') over (partition by i.n) as total30
                from public.retorno_cartao_itens i
                cross join lateral jsonb_array_elements_text(coalesce(v_c.dados -> 'linhas' -> i.n::text, '[]'::jsonb))
                     with ordinality as l(linha, ord)
               where i.cartao_id = p_cartao and i.estado = 'vivo') x
       where not x.c30 or x.k30 <= v_lim + 1;
      v_final := concat_ws(E'\n', v_cabeca, v_corpo,
                           case when v_c.mais > 0 then format('e mais %s: *retorno*', v_c.mais) end,
                           v_rodape);
      exit when char_length(v_final) <= 3500;
    end loop;
  end if;
  return v_final;
end;
$$;

create or replace function pg_temp.f5c_antes_cartao_abrir(p_gatilho text, p_agora timestamptz default now(), p_aviso uuid default null)
returns jsonb
language plpgsql
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (v_agora at time zone c_fuso)::date;
  v_cfg public.retorno_config := public._retorno_cfg();
  v_vivo jsonb;
  v_cartao uuid;
  v_total integer;
  v_mais integer;
  v_n smallint := 0;
  v_caso record;
  v_item jsonb;
  v_linhas jsonb := '{}'::jsonb;
  v_hashes text := '';
  v_rotulos text[] := '{}';
  v_nomes text[] := '{}';
  v_texto text;
  v_k integer;
  v_dono uuid;
  v_phone text;
  v_o jsonb;
  v_ocupado boolean;
  v_sessao uuid;
  v_pend uuid;
  v_perg jsonb;
  v_expira timestamptz;
  v_chave_aviso text;
begin
  if v_cfg.id is null or v_cfg.modo = 'desligado' or p_gatilho is null or p_gatilho not in ('puxar', 'meio_dia', 'acorde') then
    return jsonb_build_object('acao', 'vazio');
  end if;
  perform pg_advisory_xact_lock(hashtext('retorno:cartao'));

  v_vivo := public.retorno_cartao_vivo(v_agora);
  -- Revisão da F3: cartão vivo sem item não reapresenta nem prende os casos novos: fecha, e segue como se não houvesse cartão.
  if v_vivo ->> 'estado' = 'vivo' and public._retorno_cartao_fechar_se_vazio((v_vivo ->> 'id')::uuid, v_agora) then
    v_vivo := null;
  end if;
  if v_vivo is not null and v_vivo ->> 'estado' = 'vivo' then
    v_cartao := (v_vivo ->> 'id')::uuid;
    if p_gatilho = 'puxar' then
      update public.retorno_cartao_itens i set selecionado = true where i.cartao_id = v_cartao and i.estado = 'vivo';
      -- F3 (P5): é o que faz a unidade recém-criada aparecer no *retorno*. Item com acao_sim não remonta: o *sim <PIN>* vale sobre o que o dono leu.
      if v_cfg.previa_ditado_ligado or v_cfg.previa_modo = 'ligado' then
        for v_caso in
          select i.id from public.retorno_cartao_itens i
           where i.cartao_id = v_cartao and i.estado = 'vivo' and i.tipo_item in ('orcamento', 'adicional', 'numero_novo')
             and i.acao_sim is null and i.escolha is null and i.texto_ditado is null
        loop
          perform public._retorno_item_remontar(v_caso.id, v_agora);
        end loop;
      end if;
      v_texto := pg_temp.f5c_antes_cartao_texto(v_cartao, null);
      update public.retorno_cartoes c set texto = v_texto where c.id = v_cartao;
      return jsonb_build_object('acao', 'reapresenta', 'cartao_id', v_cartao, 'texto', v_texto);
    elsif p_gatilho = 'meio_dia' then
      select count(*) into v_k
        from public.retorno_aberturas a
       where a.estado in ('aberta', 'vencida') and a.cumprida_em is null and a.prometido_fonte = 'meio_dia'
         and (a.prometido_ate at time zone c_fuso)::date = v_hoje;
      v_texto := format('Retorno · meio-dia: %s promessa(s) até as %s. O cartão aberto já tem: *retorno*.', v_k,
                        public._retorno_hora(v_cfg.promessa_meio_dia));
      insert into public.retorno_cartoes (gatilho, dia, estado, aviso_id, hash, texto, criado_em, expira_em, dados)
      values ('meio_dia', v_hoje, 'lista', p_aviso, md5(v_texto), v_texto, v_agora, v_agora + v_cfg.cartao_validade, '{"so_aviso": true}')
      returning id into v_cartao;
      select d.phone into v_phone from public._comprovante_dono() d;
      perform public.aviso_registrar(jsonb_build_object('phone', v_phone, 'modo', public._retorno_modo_da_voz(), 'fonte', 'cliente',
        'chave', 'retorno:meio_dia:' || v_hoje, 'assunto', 'retorno:meio_dia', 'destino', 'deixar', 'texto', v_texto, 'agora', v_agora));
      return jsonb_build_object('acao', 'lista', 'cartao_id', v_cartao, 'texto', v_texto, 'phone', v_phone);
    else
      perform public._retorno_a01_na_fila(p_aviso, v_agora);
      return jsonb_build_object('acao', 'ja_vivo');
    end if;
  end if;

  select count(*) into v_total from public._retorno_cartao_casos(v_agora, null);
  if v_total = 0 then
    -- O acorde que esperava o cartão: sem nada a mostrar, o aviso vai pela fila e o minuto seguinte não repete.
    if p_gatilho = 'acorde' then
      perform public._retorno_a01_na_fila(p_aviso, v_agora);
    end if;
    return jsonb_build_object('acao', 'vazio', 'texto', 'Ninguém esperando agora.');
  end if;
  v_mais := greatest(0, v_total - v_cfg.cartao_max_itens);

  select d.id, d.phone into v_dono, v_phone from public._comprovante_dono() d;
  v_o := public.pergunta_ocupado(v_phone);
  v_ocupado := coalesce((v_o ->> 'ocupado')::boolean, false);
  if v_ocupado and p_gatilho = 'acorde' then
    perform public._retorno_a01_na_fila(p_aviso, v_agora);
    return jsonb_build_object('acao', 'ocupado');
  end if;

  v_expira := v_agora + v_cfg.cartao_validade;
  insert into public.retorno_cartoes (gatilho, dia, estado, aviso_id, hash, texto, mais, criado_em, expira_em, dados)
  values (p_gatilho, v_hoje, 'lista', p_aviso, '', '', v_mais, v_agora, v_expira,
          jsonb_build_object('rodape', case
            when not v_cfg.cartao_ligado then '*ver 1* · *resolvido 1* · *pessoal 1*'
            when v_ocupado then 'Tem um pedido aberto antes deste: responda a ele e mande *retorno* de novo.' end))
  returning id into v_cartao;

  for v_caso in select c.abertura_id from public._retorno_cartao_casos(v_agora, v_cfg.cartao_max_itens) c loop
    v_n := v_n + 1;
    v_item := public._retorno_item_montar(v_caso.abertura_id, v_n, v_agora);
    insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, modelo_tipo, service_order_id, texto_mostrado,
                                             opcoes, fatos, hash, previa_id, acao_sim)
    values (v_cartao, v_n, v_caso.abertura_id, v_item ->> 'tipo_item', v_item ->> 'modelo_tipo',
            (v_item ->> 'service_order_id')::uuid, v_item ->> 'texto_mostrado', v_item -> 'opcoes', v_item -> 'fatos',
            v_item ->> 'hash', (v_item ->> 'previa_id')::uuid, v_item ->> 'acao_sim');   -- F3 (P5)
    v_linhas := v_linhas || jsonb_build_object(v_n::text, v_item -> 'linhas');
    v_hashes := v_hashes || (v_item ->> 'hash');
    v_rotulos := v_rotulos || format('%s = %s', v_n, public._retorno_rotulo(v_caso.abertura_id, v_agora));
    v_nomes := v_nomes || public._retorno_rotulo(v_caso.abertura_id, v_agora);
  end loop;

  update public.retorno_cartoes c
     set hash = md5(v_hashes), dados = c.dados || jsonb_build_object('linhas', v_linhas)
   where c.id = v_cartao;

  if not v_cfg.cartao_ligado or v_ocupado then
    v_texto := pg_temp.f5c_antes_cartao_texto(v_cartao, null);
    update public.retorno_cartoes c set texto = v_texto where c.id = v_cartao;
    if p_gatilho = 'meio_dia' then
      v_chave_aviso := 'retorno:meio_dia:' || v_hoje;
      perform public.aviso_registrar(jsonb_build_object('phone', v_phone, 'modo', public._retorno_modo_da_voz(), 'fonte', 'cliente',
        'chave', v_chave_aviso, 'assunto', 'retorno:meio_dia', 'destino', 'deixar', 'texto', split_part(v_texto, E'\n', 1), 'agora', v_agora));
    end if;
    return jsonb_build_object('acao', 'lista', 'cartao_id', v_cartao, 'texto', v_texto, 'phone', v_phone,
      'historico', jsonb_build_object('user', '(retorno)',
        'assistant', format('Mostrei a lista do retorno: %s caso(s). %s. O que os clientes escreveram fica fora desta conversa.',
                            v_total, array_to_string(v_rotulos, ', '))));
  end if;

  -- Cartão vivo: sessão, pendência, ponteiro por merge, registro da pergunta, par da conversa e auditoria.
  v_sessao := public._retorno_sessao_do_dono(v_dono, v_phone, v_agora);
  insert into public.ai_operator_pending_actions (session_id, requested_by_user_id, action_name, risk_level, risk_reason, title, summary,
                                                  payload, status, expires_at)
  values (v_sessao, v_dono, 'retorno_executar_cartao', 'high', 'manda mensagem ao cliente', 'Cartão do retorno',
          format('Cartão do retorno: %s casos (%s). Mande *retorno* para ver.', v_n, array_to_string(v_nomes, ', ')),
          jsonb_build_object('cartao_id', v_cartao), 'pending', v_expira)
  returning id into v_pend;

  update public.ai_operator_sessions s
     set metadata = coalesce(s.metadata, '{}'::jsonb)
                    || jsonb_build_object('pending_confirm_action_id', v_pend, 'pin_attempts', 0, 'pendencia_herdada', false),
         last_activity_at = v_agora
   where s.id = v_sessao;

  v_perg := public.pergunta_registrar_externa(jsonb_build_object('phone', v_phone, 'origem', 'acompanhar_conversa', 'tipo', 'confirmacao',
    'referencia_id', v_pend, 'titulo', 'Cartão do retorno'));

  insert into public.ai_operator_messages (session_id, role, content, source) values
    (v_sessao, 'user', format('🤖 Cartão do retorno (aviso automático): %s casos.', v_n), 'whatsapp'),
    (v_sessao, 'assistant', format('Cartão do retorno aberto (pendência %s). Casos: %s. O que os clientes escreveram fica fora desta conversa; para ler, use retorno_ler_caso.',
                                   v_pend, array_to_string(v_rotulos, ', ')), 'whatsapp');

  insert into public.ai_operator_audit (session_id, pending_action_id, actor_user_id, actor_kind, event_type, event_category, payload)
  values (v_sessao, v_pend, v_dono, 'system', 'retorno:cartao:proposto', 'channel',
          jsonb_build_object('cartao_id', v_cartao, 'itens', v_n, 'gatilho', p_gatilho));

  update public.retorno_cartoes c
     set estado = 'vivo', sessao_id = v_sessao, pendencia_id = v_pend, pergunta_id = (v_perg ->> 'id')::uuid
   where c.id = v_cartao;
  v_texto := pg_temp.f5c_antes_cartao_texto(v_cartao, null);
  update public.retorno_cartoes c set texto = v_texto where c.id = v_cartao;

  if p_gatilho = 'meio_dia' then
    perform public.aviso_registrar(jsonb_build_object('phone', v_phone, 'modo', public._retorno_modo_da_voz(), 'fonte', 'cliente',
      'chave', 'retorno:meio_dia:' || v_hoje, 'assunto', 'retorno:meio_dia', 'destino', 'deixar', 'texto', split_part(v_texto, E'\n', 1), 'agora', v_agora));
  elsif p_gatilho = 'acorde' then
    update public.retorno_saidas s set dados = s.dados - 'aguarda_cartao', atualizada_em = now()
     where s.tipo = 'acorde' and s.dados ->> 'aviso_id' = p_aviso::text;
  end if;

  return jsonb_build_object('acao', 'cartao', 'cartao_id', v_cartao, 'phone', v_phone, 'texto', v_texto, 'pergunta_id', v_perg ->> 'id');
end;
$$;

create or replace function pg_temp.f5c_cli(p_nome text, p_fone text) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, p_fone) returning id
$f$;

create or replace function pg_temp.f5c_msg(p_fone text, p_corpo text, p_em timestamptz) returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
  values ('inbound', p_fone, 'text', p_corpo, 'received', '{"data": {}}'::jsonb, p_em, p_em)
  returning id
$f$;

-- O orçamento enviado ao número do cliente pela tela na seg 19/10 10:00, com validade seg 26/10, e o registro do envio.
create or replace function pg_temp.f5c_orc(p_cliente uuid, p_fone text, p_numero text, p_desc text, p_total numeric) returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type) values (p_cliente, 'Unidade ' || p_numero, 'Motorhome') returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, problem_description,
                                     created_at, updated_at, grand_total, quote_validity_days, quote_validity_date,
                                     orcamento_enviado_em, orcamento_enviado_via, orcamento_enviado_chave)
  values (p_numero, p_cliente, v_v, 'draft', 'sent', 'repair', p_desc, '2026-10-16 10:00-03', '2026-10-16 10:00-03', p_total, 7,
          date '2026-10-26', '2026-10-19 10:00-03', 'tela', public._agenda_chave_telefone(p_fone))
  returning id into v_id;
  insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em, marcou)
  values (v_id, p_cliente, 'tela', public._agenda_chave_telefone(p_fone), true, '2026-10-19 10:00-03', true);
  return v_id;
end $f$;

-- O caso da F1/F2, aberto por uma mensagem inventada.
create or replace function pg_temp.f5c_caso(p_cliente uuid, p_fone text, p_corpo text, p_aberta timestamptz, p_papel text default 'cliente',
                                            p_estado text default 'aberta', p_nivel text default 'recibo') returns uuid
language plpgsql as $f$
declare
  v_chave text := public._agenda_chave_telefone(p_fone);
  v_msg uuid;
  v_id uuid;
begin
  v_msg := pg_temp.f5c_msg(p_fone, p_corpo, p_aberta);
  -- O caso fechado tem fechada_em (CHECK retorno_aberturas_fechada); o de nível nada tem o motivo (retorno_aberturas_motivo).
  insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, clientes, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, motivo, tipo_recibo, estado, fechada_em, fechada_motivo,
                                        modo)
  values (v_chave, p_fone, '47', p_papel, jsonb_build_object('papel', p_papel), p_cliente, '{}', v_msg, v_msg, p_aberta,
          p_aberta, p_aberta, p_aberta, p_nivel, (case when p_nivel = 'nada' then 'nao_pede_resposta' end), 'recibo_cliente', p_estado,
          (case when p_estado = 'fechada' then p_aberta + interval '4 hours' end), (case when p_estado = 'fechada' then 'nada' end),
          'sombra')
  returning id into v_id;
  insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, sinais, pede_resposta)
  values (v_msg, v_id, v_chave, p_aberta, p_aberta, md5(p_corpo), public._retorno_sinais(p_corpo), true);
  return v_id;
end $f$;

-- O aceite como a P6 grava: sem caso, a mensagem nasce aqui; com caso, é a 1ª mensagem do caso.
create or replace function pg_temp.f5c_aceite(p_cliente uuid, p_fone text, p_os uuid, p_em timestamptz, p_estado text default 'detectado',
                                              p_caso uuid default null, p_corpo text default 'Pode fazer.', p_cands uuid[] default null,
                                              p_resultado jsonb default '{}'::jsonb) returns uuid
language plpgsql as $f$
declare
  v_m uuid;
  v_id uuid;
begin
  if p_caso is not null then
    select a.primeira_msg_id into v_m from public.retorno_aberturas a where a.id = p_caso;
  else
    v_m := pg_temp.f5c_msg(p_fone, p_corpo, p_em);
  end if;
  insert into public.orcamento_aceites (abertura_id, whatsapp_message_id, client_id, chave, candidatos, service_order_id, sinal_lido, estado,
                                        total_visto, resultado, criado_em)
  values (p_caso, v_m, p_cliente, public._agenda_chave_telefone(p_fone), coalesce(p_cands, array[p_os]), p_os, 'pode fazer', p_estado,
          (select so.grand_total from public.service_orders so where so.id = p_os), p_resultado, p_em + interval '3 minutes')
  returning id into v_id;
  return v_id;
end $f$;

-- O acompanhamento ligado e o passo à espera do *sim* (aguarda_sim, de qua 21/10 até qui 22/10).
create or replace function pg_temp.f5c_passo(p_cliente uuid, p_fone text, p_os uuid, p_passo text default 'lembrete',
                                             p_dia date default '2026-10-21', p_ate date default '2026-10-22') returns uuid
language plpgsql as $f$
declare
  v_a uuid;
  v_p uuid;
begin
  insert into public.orcamento_acompanhamentos (service_order_id, client_id, chave, enviado_em, validade_ate, modo, estado, criado_em)
  values (p_os, p_cliente, public._agenda_chave_telefone(p_fone), '2026-10-19 10:00-03', date '2026-10-26', 'ligado', 'ativo',
          '2026-10-19 10:05-03')
  returning id into v_a;
  insert into public.orcamento_passos (acompanhamento_id, passo, tipo, dia, ate, estado)
  values (v_a, p_passo, 'orc_' || p_passo, p_dia, p_ate, 'aguarda_sim')
  returning id into v_p;
  return v_p;
end $f$;

create or replace function pg_temp.f5c_limpar() returns void
language sql as $f$
  update public.ai_operator_pending_actions set status = 'expired' where status = 'pending';
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste' where status = 'aberta';
  update public.retorno_cartoes set estado = 'decidido', decidido_em = now(), decidido_por = 'nao' where estado = 'vivo';
$f$;

-- O cartão vivo, aberto pelo *retorno*.
create or replace function pg_temp.f5c_cartao(p_agora timestamptz default '2026-10-21 09:30-03') returns uuid
language plpgsql as $f$
declare
  v_r jsonb;
begin
  perform pg_temp.f5c_limpar();
  v_r := public.retorno_cartao_abrir('puxar', p_agora);
  if v_r ->> 'acao' is distinct from 'cartao' then
    raise exception 'o cartão não abriu: %', v_r;
  end if;
  return (v_r ->> 'cartao_id')::uuid;
end $f$;

create or replace function pg_temp.f5c_dito(p_cmd jsonb, p_agora timestamptz default '2026-10-21 09:35-03') returns jsonb
language sql as $f$
  select public.retorno_decidir_dito(p_cmd, (select d.id from public._comprovante_dono() d), p_agora)
$f$;

-- O *sim 7391*: o TS confere o PIN e chama a execução com o dono.
create or replace function pg_temp.f5c_sim(p_cartao uuid, p_agora timestamptz default '2026-10-21 09:40-03') returns jsonb
language sql as $f$
  select public.retorno_cartao_executar(p_cartao, (select d.id from public._comprovante_dono() d), p_agora)
$f$;

create or replace function pg_temp.f5c_item(p_cartao uuid, p_n integer) returns public.retorno_cartao_itens
language sql as $f$
  select i from public.retorno_cartao_itens i where i.cartao_id = p_cartao and i.n = p_n
$f$;

create or replace function pg_temp.f5c_ac(p_aceite uuid) returns public.orcamento_aceites
language sql as $f$
  select a from public.orcamento_aceites a where a.id = p_aceite
$f$;

create or replace function pg_temp.f5c_px(p_passo uuid) returns text
language sql as $f$
  select p.estado || '/' || coalesce(p.motivo, '-') from public.orcamento_passos p where p.id = p_passo
$f$;

create or replace function pg_temp.f5c_texto(p_cartao uuid) returns text
language sql as $f$
  select c.texto from public.retorno_cartoes c where c.id = p_cartao
$f$;

-- Os itens do cartão sem os ids (o que o nº 1 compara com o cartão de antes).
create or replace function pg_temp.f5c_itens(p_cartao uuid) returns jsonb
language sql as $f$
  select coalesce(jsonb_agg(jsonb_build_object('n', i.n, 'abertura_id', i.abertura_id, 'tipo_item', i.tipo_item, 'modelo_tipo', i.modelo_tipo,
                                               'service_order_id', i.service_order_id, 'texto_mostrado', i.texto_mostrado, 'opcoes', i.opcoes,
                                               'fatos', i.fatos, 'hash', i.hash, 'estado', i.estado, 'selecionado', i.selecionado,
                                               'previa_id', i.previa_id, 'acao_sim', i.acao_sim, 'passo_id', i.passo_id,
                                               'aceite_id', i.aceite_id) order by i.n), '[]'::jsonb)
    from public.retorno_cartao_itens i where i.cartao_id = p_cartao
$f$;

create or replace function pg_temp.f5c_retrato(p_cartao uuid) returns jsonb
language sql as $f$
  select jsonb_build_object('gatilho', c.gatilho, 'estado', c.estado, 'mais', c.mais, 'hash', c.hash, 'dados', c.dados, 'texto', c.texto,
                            'resumo', (select p.summary from public.ai_operator_pending_actions p where p.id = c.pendencia_id))
    from public.retorno_cartoes c where c.id = p_cartao
$f$;

-- A lista (C-LISTA) como texto: "tipo:abertura|aceite|passo" na ordem.
create or replace function pg_temp.f5c_lista(p_agora timestamptz default '2026-10-21 09:30-03', p_limite integer default null) returns text
language sql as $f$
  select coalesce(string_agg(l.tipo || ':' || coalesce(l.abertura_id::text, '-') || '|' || coalesce(l.aceite_id::text, '-') || '|'
                             || coalesce(l.passo_id::text, '-'), ' ; ' order by l.ordem), '')
    from public._orcamento_cartao_lista(p_agora, p_limite) l
$f$;

create or replace function pg_temp.f5c_letras(p_item jsonb) returns text
language sql as $f$
  select coalesce(string_agg(o ->> 'letra', ',' order by o ->> 'letra'), '') from jsonb_array_elements(p_item -> 'opcoes') o
$f$;

create or replace function pg_temp.f5c_igual(p_rot text, p_valor text, p_esp text) returns void
language plpgsql as $f$
begin
  if p_valor is distinct from p_esp then
    raise exception '%: %, esperava %', p_rot, coalesce(p_valor, '∅'), coalesce(p_esp, '∅');
  end if;
end $f$;

create or replace function pg_temp.f5c_tem(p_rot text, p_texto text, p_trecho text) returns void
language plpgsql as $f$
begin
  if p_texto is null or strpos(p_texto, p_trecho) = 0 then
    raise exception '%: sem o trecho "%" em: %', p_rot, p_trecho, coalesce(p_texto, '∅');
  end if;
end $f$;

do $cartao$
declare
  c_msg constant timestamptz := '2026-10-20 14:05-03';    -- ter, o "Pode fazer." da Ana
  c_agora constant timestamptz := '2026-10-21 09:30-03';  -- qua, o cartão
  c_dita constant timestamptz := '2026-10-21 09:35-03';   -- as palavras do dono
  c_sim constant timestamptz := '2026-10-21 09:40-03';    -- o *sim 7391*
  c_amanha constant timestamptz := '2026-10-22 09:00-03'; -- qui, ainda dentro do prazo do lembrete
  c_ana constant text := '5547900009971';
  c_joao constant text := '5547900009972';
  c_pedro constant text := '5547900009973';
  c_caio constant text := '5547900009974';
  c_bia constant text := '5547900009975';
  c_rodrigo constant text := '5547900009976';
  c_novo constant text := '5547900009977';
  c_sem_nome constant text := '5547900009978';
  c_lembrete constant text := 'Oi, João! Aqui é a Claudia, assistente virtual da HBR. Conseguiu ver o orçamento das baterias que o Gustavo te mandou? Se tiver alguma dúvida ou quiser ajustar algo, é só responder por aqui que eu passo a ele.';
  c_novas constant text[] := array['_orcamento_assunto', '_orcamento_razao_nao_saiu', '_orcamento_item_rotulo', '_orcamento_texto_do_passo',
    '_orcamento_cartao_passos', '_orcamento_cartao_lista', '_orcamento_item_montar_passo', '_orcamento_item_aceite', '_orcamento_item_dados',
    '_orcamento_item_conferir', '_orcamento_passo_aprovar', '_orcamento_item_executar', '_orcamento_cartao_tirados', '_orcamento_decidir_letra',
    '_orcamento_ver_item', '_orcamento_item_resolvido', '_orcamento_item_pessoal', '_orcamento_ditado_enviado'];
  v_dono uuid;
  v_phone text;
  v_max boolean;
  v_suf text;
  v_ana uuid; v_joao uuid; v_pedro uuid; v_caio uuid; v_bia uuid; v_rodrigo uuid; v_sn uuid;
  v_os uuid; v_os2 uuid; v_os3 uuid; v_os4 uuid; v_os5 uuid;
  v_ac uuid; v_ac2 uuid; v_ac3 uuid; v_ac4 uuid;
  v_k1 uuid; v_k2 uuid; v_k3 uuid; v_k4 uuid;
  v_p uuid; v_p2 uuid;
  v_cartao uuid;
  v_i public.retorno_cartao_itens;
  v_a public.orcamento_aceites;
  v_item jsonb;
  v_r jsonb;
  v_ref_texto text;
  v_ref_itens jsonb;
  v_ref_retrato jsonb;
  v_esperado text;
  v text;
  v_n integer;
  v_rec record;
  v_n_fun integer := 0;
begin
  begin
  select d.id, d.phone into v_dono, v_phone from public._comprovante_dono() d;
  if v_dono is null then
    raise exception '0: sem o dono (_comprovante_dono): o cartão não abre';
  end if;
  update public.ai_operator_sessions set metadata = metadata - 'pendencias_guardadas' where external_thread_key = v_phone;
  perform pg_temp.f5c_limpar();
  -- A configuração de cada cenário: o retorno e o orçamento ligados, o cartão ligado com 3 vagas, o aceite no cartão, os dados
  -- da nota desligados (o padrão; os cenários que precisam ligam), a F3 desligada, a janela comercial do K7.
  update public.retorno_config
     set modo = 'ligado', tipos_ligados = '{}', cartao_ligado = true, cartao_max_itens = 3, carona_ligada = false, carona_em = null,
         meio_dia_ligado = false, previa_modo = 'desligado', previa_ditado_ligado = false, orcamento_modo = 'ligado',
         validade_envio_ligada = true, aceite_modo = 'cartao', aceite_audio = false, dados_nota_ligado = false, orcamento_segura = false,
         cadencia_hora = '10:00', cadencia_inicio = '09:00', cadencia_fim = '17:00', segura_tudo_ate = null, so_reativo = false,
         proximo_envio_em = null
   where id;
  update public.retorno_modelo_tipos set nivel = 'cartao' where tipo in ('orc_lembrete', 'orc_vespera', 'orc_encerramento');
  update public.agenda_config set sabado_util = false where id;
  update public.agenda_disponibilidade d
     set substituida_em = now()
   where d.payee_id is null and d.situacao = 'indisponivel' and d.turno is null and d.substituida_em is null
     and d.periodo && daterange(date '2026-10-01', date '2026-11-10');
  -- A linha do assistente fora (a F2 a põe no fim do rodapé): o texto byte a byte a leva junto quando ela aparece.
  begin
    v_max := public.ai_claude_max_disponivel();
  exception when others then
    v_max := null;
  end;
  v_suf := (case when v_max is false then E'\n(Seu assistente está fora: responda com as letras ou pelo celular.)' else '' end);

  -- ── 1 e 18. Sem a F5 (aceite e cadência desligados, ou o aceite em sombra), o cartão é o de antes, byte a byte ──
  begin
    update public.retorno_config set aceite_modo = 'desligado' where id;
    update public.retorno_modelo_tipos set nivel = 'desligado' where tipo in ('orc_lembrete', 'orc_vespera', 'orc_encerramento');
    v_rodrigo := pg_temp.f5c_cli('Rodrigo Cartao F5 Teste', c_rodrigo);
    v_k1 := pg_temp.f5c_caso(v_rodrigo, c_rodrigo, 'preciso trocar as baterias da lancha, quanto custa?', '2026-10-21 08:00-03');
    v_bia := pg_temp.f5c_cli('Bia Cartao F5 Teste', c_bia);
    v_k2 := pg_temp.f5c_caso(v_bia, c_bia, 'bom dia', '2026-10-21 08:10-03');
    v_k3 := pg_temp.f5c_caso(null, c_novo, 'oi, tudo bem?', '2026-10-21 08:20-03', 'numero_novo');
    -- A F5 no banco, com as chaves desligadas: o aceite detectado e o passo à espera não entram.
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg);
    v_joao := pg_temp.f5c_cli('João Cartao F5 Teste', c_joao);
    v_os2 := pg_temp.f5c_orc(v_joao, c_joao, 'ORÇ-99672', 'Troca das baterias da lancha', 3200);
    v_p := pg_temp.f5c_passo(v_joao, c_joao, v_os2);

    -- 1a. A lista da F5 é a da F2: os mesmos casos, na mesma ordem, e nada da F5.
    if (select count(*) from public._orcamento_cartao_aceites(c_agora)) is distinct from 0::bigint
       or (select count(*) from public._orcamento_cartao_passos(c_agora, null)) is distinct from 0::bigint then
      raise exception '1a: a lista de aceites ou de passos não está vazia com a F5 desligada';
    end if;
    if (select jsonb_agg(jsonb_build_array(l.ordem, l.tipo, l.abertura_id, l.aceite_id, l.passo_id, l.prioridade, l.rotulo) order by l.ordem)
          from public._orcamento_cartao_lista(c_agora, null) l)
       is distinct from (select jsonb_agg(jsonb_build_array(c.ord, 'caso', c.abertura_id, null, null, c.prioridade, null) order by c.ord)
                           from public._retorno_cartao_casos(c_agora, null) with ordinality as c(abertura_id, prioridade, ord)) then
      raise exception '1a: a lista da F5 difere da F2';
    end if;
    if (select count(*) from public._orcamento_cartao_lista(c_agora, null) l where l.abertura_id in (v_k1, v_k2, v_k3)) is distinct from 3::bigint then
      raise exception '1a: os 3 casos de exemplo não estão na lista';
    end if;
    -- 1b. O cartão de antes (as cópias) e o da F5: o retorno, o texto, os itens, o cartão e o resumo da pendência.
    begin
      v_r := pg_temp.f5c_antes_cartao_abrir('puxar', c_agora);
      v_ref_texto := v_r ->> 'texto';
      v_ref_itens := pg_temp.f5c_itens((v_r ->> 'cartao_id')::uuid);
      v_ref_retrato := pg_temp.f5c_retrato((v_r ->> 'cartao_id')::uuid);
      raise exception 'f5c_desfaz' using errcode = 'P0001';
    exception when others then
      if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_desfaz' then
        raise;
      end if;
    end;
    if v_ref_texto is null or jsonb_array_length(v_ref_itens) is distinct from 3 then
      raise exception '1b: o cartão de antes não abriu com os 3 casos (%)', v_ref_itens;
    end if;
    v_r := public.retorno_cartao_abrir('puxar', c_agora);
    v_cartao := (v_r ->> 'cartao_id')::uuid;
    perform pg_temp.f5c_igual('1b acao', v_r ->> 'acao', 'cartao');
    perform pg_temp.f5c_igual('1b texto', v_r ->> 'texto', v_ref_texto);
    perform pg_temp.f5c_igual('1b itens', pg_temp.f5c_itens(v_cartao)::text, v_ref_itens::text);
    perform pg_temp.f5c_igual('1b cartão', pg_temp.f5c_retrato(v_cartao)::text, v_ref_retrato::text);
    -- 1c. O texto do mesmo cartão pela função de antes e pela da F5.
    perform pg_temp.f5c_igual('1c', public._retorno_cartao_texto(v_cartao, null), pg_temp.f5c_antes_cartao_texto(v_cartao, null));

    -- 18a. O aceite em sombra (aceites sombra de todo tipo, inclusive seria = agenda): o mesmo cartão, byte a byte.
    perform pg_temp.f5c_limpar();
    update public.retorno_config set aceite_modo = 'sombra' where id;
    update public.orcamento_aceites set estado = 'sombra', resultado = '{"seria": "detectado"}' where id = v_ac;
    v_pedro := pg_temp.f5c_cli('Pedro Cartao F5 Teste', c_pedro);
    v_os3 := pg_temp.f5c_orc(v_pedro, c_pedro, 'ORÇ-99673', 'Revisão do inversor', 1500);
    v_os4 := pg_temp.f5c_orc(v_pedro, c_pedro, 'ORÇ-99674', 'Troca da geladeira', 2500);
    perform pg_temp.f5c_aceite(v_pedro, c_pedro, null, '2026-10-20 15:00-03', 'sombra', null, 'Fechado!', array[v_os3, v_os4],
                               '{"seria": "duvida"}');
    v_caio := pg_temp.f5c_cli('Caio Cartao F5 Teste', c_caio);
    v_os5 := pg_temp.f5c_orc(v_caio, c_caio, 'ORÇ-99675', 'Antena starlink', 1800);
    perform pg_temp.f5c_aceite(v_caio, c_caio, v_os5, '2026-10-20 16:00-03', 'sombra', null, 'pode marcar', null,
                               '{"seria": "agenda", "os_agenda": "OS-99690"}');
    v_r := public.retorno_cartao_abrir('puxar', c_agora);
    v_cartao := (v_r ->> 'cartao_id')::uuid;
    perform pg_temp.f5c_igual('18a texto', v_r ->> 'texto', v_ref_texto);
    perform pg_temp.f5c_igual('18a itens', pg_temp.f5c_itens(v_cartao)::text, v_ref_itens::text);

    -- 18b. aceite_modo = 'cartao' com um detectado vivo: ele entra; a chave volta a desligado: a lista fica sem ele na hora.
    perform pg_temp.f5c_limpar();
    update public.orcamento_aceites set estado = 'detectado', resultado = '{}' where id = v_ac;
    update public.retorno_config set aceite_modo = 'cartao' where id;
    perform pg_temp.f5c_tem('18b com cartao', pg_temp.f5c_lista(), 'aceite:-|' || v_ac || '|-');
    update public.retorno_config set aceite_modo = 'desligado' where id;
    if strpos(pg_temp.f5c_lista(), v_ac::text) > 0 then
      raise exception '18b: o aceite continuou na lista com a chave desligada';
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 2, 2b e 16. A lista (C-LISTA): a prioridade 3, o caso que não aparece duas vezes, o aceite e os dados sem caso ──
  begin
    v_pedro := pg_temp.f5c_cli('Pedro Cartao F5 Teste', c_pedro);
    v_k1 := pg_temp.f5c_caso(v_pedro, c_pedro, 'cadê o meu motorhome?', '2026-10-20 08:00-03', 'cliente', 'vencida');   -- 1: vencido
    v_caio := pg_temp.f5c_cli('Caio Cartao F5 Teste', c_caio);
    v_k2 := pg_temp.f5c_caso(v_caio, c_caio, 'me liga quando puder', '2026-10-21 07:00-03', 'cliente', 'aberta', 'passagem');   -- 2
    v_k3 := pg_temp.f5c_caso(null, c_novo, 'oi, tudo bem?', '2026-10-21 08:20-03', 'numero_novo');   -- 4: pedido novo
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_k4 := pg_temp.f5c_caso(v_ana, c_ana, 'Pode fazer.', c_msg);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg, 'detectado', v_k4);
    -- 2. vencido, passagem, o aceite (com o caso da Ana como referência), o pedido novo; o caso da Ana não aparece como caso.
    perform pg_temp.f5c_igual('2 a ordem', pg_temp.f5c_lista(),
      format('caso:%s|-|- ; caso:%s|-|- ; aceite:%s|%s|- ; caso:%s|-|-', v_k1, v_k2, v_k4, v_ac, v_k3));
    if (select l.prioridade from public._orcamento_cartao_lista(c_agora, null) l where l.aceite_id = v_ac) is distinct from 3::smallint
       or (select l.rotulo from public._orcamento_cartao_lista(c_agora, null) l where l.aceite_id = v_ac) is not null then
      raise exception '2: a prioridade ou o rótulo do aceite com caso';
    end if;

    -- 16. 2 casos (prioridades 1 e 4), 1 aceite e 1 passo, 3 vagas: o caso 1, o aceite e o passo; o caso de prioridade 4 no "mais 1".
    update public.retorno_aberturas set estado = 'fechada', fechada_em = now(), fechada_motivo = 'expirou' where id = v_k2;
    v_joao := pg_temp.f5c_cli('João Cartao F5 Teste', c_joao);
    v_os2 := pg_temp.f5c_orc(v_joao, c_joao, 'ORÇ-99672', 'Troca das baterias da lancha', 3200);
    v_p := pg_temp.f5c_passo(v_joao, c_joao, v_os2);
    -- O passo de um cadastro sem nome não se monta: vira pulado/sem_nome e fica fora.
    insert into public.clients (type, name, whatsapp) values ('company', 'EMPRESA SEM NOME CARTAO F5 TESTE', c_sem_nome) returning id into v_sn;
    v_os5 := pg_temp.f5c_orc(v_sn, c_sem_nome, 'ORÇ-99678', 'Troca das baterias', 900);
    v_p2 := pg_temp.f5c_passo(v_sn, c_sem_nome, v_os5);
    perform pg_temp.f5c_igual('16 a lista inteira', pg_temp.f5c_lista(),
      format('caso:%s|-|- ; aceite:%s|%s|- ; caso:%s|-|- ; cadencia:-|-|%s', v_k1, v_k4, v_ac, v_k3, v_p));
    perform pg_temp.f5c_igual('16 sem nome', pg_temp.f5c_px(v_p2), 'pulado/sem_nome');
    perform pg_temp.f5c_igual('16 a lista de 3', pg_temp.f5c_lista(c_agora, 3),
      format('caso:%s|-|- ; aceite:%s|%s|- ; cadencia:-|-|%s', v_k1, v_k4, v_ac, v_p));
    v_cartao := pg_temp.f5c_cartao(c_agora);
    if (select c.mais from public.retorno_cartoes c where c.id = v_cartao) is distinct from 1
       or (pg_temp.f5c_item(v_cartao, 1)).abertura_id is distinct from v_k1
       or (pg_temp.f5c_item(v_cartao, 2)).tipo_item is distinct from 'aceite' or (pg_temp.f5c_item(v_cartao, 2)).aceite_id is distinct from v_ac
       or (pg_temp.f5c_item(v_cartao, 2)).abertura_id is distinct from v_k4
       or (pg_temp.f5c_item(v_cartao, 3)).tipo_item is distinct from 'cadencia' or (pg_temp.f5c_item(v_cartao, 3)).passo_id is distinct from v_p
       or (pg_temp.f5c_item(v_cartao, 3)).abertura_id is not null then
      raise exception '16: o cartão (%)', pg_temp.f5c_itens(v_cartao);
    end if;
    perform pg_temp.f5c_tem('16 o mais', pg_temp.f5c_texto(v_cartao), 'e mais 1: *retorno*');
    perform pg_temp.f5c_tem('16 o resumo da pendência', (pg_temp.f5c_retrato(v_cartao)) ->> 'resumo', 'João, lembrete do ORÇ-99672');
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  begin
    -- 2b. O aceite de "Fechado!" sem caso: item com letras; o aceite cujo caso (nível nada) o vigia da F1 fechou continua; os
    --     dados da nota com o caso do aceite já cumprido pelo "Fechado" enviado entram.
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg, 'detectado', null, 'Fechado!');
    v_item := public._orcamento_item_aceite(null, v_ac, 1::smallint, c_agora);
    perform pg_temp.f5c_igual('2b-1 letras', pg_temp.f5c_letras(v_item), 'A,B');
    perform pg_temp.f5c_igual('2b-1 rótulo', v_item ->> 'rotulo', 'Ana, aceite do ORÇ-99671');
    perform pg_temp.f5c_igual('2b-1 linha', v_item -> 'linhas' ->> 0, '1. Ana · 14:05 · ''Fechado!''');
    v_pedro := pg_temp.f5c_cli('Pedro Cartao F5 Teste', c_pedro);
    v_os3 := pg_temp.f5c_orc(v_pedro, c_pedro, 'ORÇ-99673', 'Revisão do inversor', 1500);
    v_k1 := pg_temp.f5c_caso(v_pedro, c_pedro, 'Fechado, obrigado', '2026-10-20 15:00-03', 'cliente', 'fechada', 'nada');
    v_ac2 := pg_temp.f5c_aceite(v_pedro, c_pedro, v_os3, '2026-10-20 15:00-03', 'detectado', v_k1);
    v_joao := pg_temp.f5c_cli('João Cartao F5 Teste', c_joao);
    v_os2 := pg_temp.f5c_orc(v_joao, c_joao, 'ORÇ-99672', 'Troca das baterias da lancha', 3200);
    v_k2 := pg_temp.f5c_caso(v_joao, c_joao, 'Pode seguir.', '2026-10-20 10:00-03');
    update public.retorno_aberturas set cumprida_em = '2026-10-20 10:30-03', cumprida_por = 'cartao' where id = v_k2;
    v_ac3 := pg_temp.f5c_aceite(v_joao, c_joao, v_os2, '2026-10-20 10:00-03', 'com_sinal', v_k2);
    update public.orcamento_aceites
       set dados_estado = 'lidos', dados_msg_id = pg_temp.f5c_msg(c_joao, 'O CPF é 529.982.247-25 e o CEP 88330-000', '2026-10-20 11:00-03')
     where id = v_ac3;
    perform pg_temp.f5c_igual('2b-2 a lista', pg_temp.f5c_lista(),
      format('dados_nota:%s|%s|- ; aceite:-|%s|- ; aceite:%s|%s|-', v_k2, v_ac3, v_ac, v_k1, v_ac2));
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 3. As letras do aceite de 1 candidato ──
  begin
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg);
    -- 3a. Dados da nota desligados: A e B.
    v_item := public._orcamento_item_aceite(null, v_ac, 1::smallint, c_agora);
    perform pg_temp.f5c_igual('3a letras', pg_temp.f5c_letras(v_item), 'A,B');
    perform pg_temp.f5c_igual('3a opcoes', (v_item -> 'opcoes')::text, '[{"acao": "aceite_com_sinal", "letra": "A"}, {"acao": "aceite_sem_sinal", "letra": "B"}]');
    -- 3b. Ligados e com faltas (cadastro sem documento nem endereço): A a D, "pede CPF e endereço".
    update public.retorno_config set dados_nota_ligado = true where id;
    v_item := public._orcamento_item_aceite(null, v_ac, 1::smallint, c_agora);
    perform pg_temp.f5c_igual('3b letras', pg_temp.f5c_letras(v_item), 'A,B,C,D');
    perform pg_temp.f5c_igual('3b linha', v_item -> 'linhas' ->> 3, '   *1 C* = A e pede CPF e endereço · *1 D* = B e pede CPF e endereço · *não 1* não era');
    if (select count(*) from jsonb_array_elements(v_item -> 'opcoes') o where (o ->> 'pedir_dados')::boolean) is distinct from 2::bigint then
      raise exception '3b: C e D sem pedir_dados (%)', v_item -> 'opcoes';
    end if;
    -- 3c. Só o endereço falta: "pede o endereço"; só o CEP: "pede o CEP".
    update public.clients set cpf_cnpj = '529.982.247-25' where id = v_ana;
    v_item := public._orcamento_item_aceite(null, v_ac, 1::smallint, c_agora);
    perform pg_temp.f5c_tem('3c endereço', v_item -> 'linhas' ->> 3, '*1 C* = A e pede o endereço');
    update public.clients set address_line_1 = 'Rua das Flores, 10', neighborhood = 'Centro', city = 'Itapema', state = 'SC' where id = v_ana;
    v_item := public._orcamento_item_aceite(null, v_ac, 1::smallint, c_agora);
    perform pg_temp.f5c_tem('3c CEP', v_item -> 'linhas' ->> 3, '*1 C* = A e pede o CEP');
    -- 3d. Sem faltas: só A e B.
    update public.clients set postal_code = '88220-000' where id = v_ana;
    v_item := public._orcamento_item_aceite(null, v_ac, 1::smallint, c_agora);
    perform pg_temp.f5c_igual('3d letras', pg_temp.f5c_letras(v_item), 'A,B');
    -- 3e. A OS em andamento do mesmo cliente ganha a linha.
    insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, grand_total)
    select 'OS-99679', v_ana, so.vessel_id, 'scheduled', 'approved', 'repair', '2026-10-10 10:00-03', '2026-10-10 10:00-03', 100
      from public.service_orders so where so.id = v_os;
    v_item := public._orcamento_item_aceite(null, v_ac, 1::smallint, c_agora);
    perform pg_temp.f5c_tem('3e andamento', v_item ->> 'linhas', 'A OS-99679 está em andamento: para juntar, use a tela.');
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 4. duvida e agenda sem letra; a letra que o item não tem; a letra com resto ──
  begin
    update public.retorno_config set dados_nota_ligado = true where id;
    v_pedro := pg_temp.f5c_cli('Pedro Cartao F5 Teste', c_pedro);
    v_os3 := pg_temp.f5c_orc(v_pedro, c_pedro, 'ORÇ-99673', 'Revisão do inversor', 1500);
    v_os4 := pg_temp.f5c_orc(v_pedro, c_pedro, 'ORÇ-99674', 'Troca da geladeira', 2500);
    v_ac := pg_temp.f5c_aceite(v_pedro, c_pedro, null, '2026-10-20 12:00-03', 'duvida', null, 'Fechado!', array[v_os3, v_os4]);
    v_caio := pg_temp.f5c_cli('Caio Cartao F5 Teste', c_caio);
    v_os5 := pg_temp.f5c_orc(v_caio, c_caio, 'ORÇ-99675', 'Antena starlink', 1800);
    v_ac2 := pg_temp.f5c_aceite(v_caio, c_caio, v_os5, '2026-10-20 13:00-03', 'agenda', null, 'pode marcar', null, '{"os_agenda": "OS-99690"}');
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac3 := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg);
    v_cartao := pg_temp.f5c_cartao(c_agora);
    v_i := pg_temp.f5c_item(v_cartao, 1);
    perform pg_temp.f5c_igual('4 duvida opcoes', v_i.opcoes::text, '[]');
    perform pg_temp.f5c_tem('4 duvida linha', pg_temp.f5c_texto(v_cartao),
      '   O cliente tem 2 orçamentos enviados: ORÇ-99673 (inversor, seg 19/10) e ORÇ-99674 (geladeira, seg 19/10). A dúvida é sua: responda pelo assistente, ou *não 1* se não era.');
    perform pg_temp.f5c_igual('4 agenda opcoes', (pg_temp.f5c_item(v_cartao, 2)).opcoes::text, '[]');
    perform pg_temp.f5c_tem('4 agenda linha', pg_temp.f5c_texto(v_cartao),
      '   O cliente tem 1 orçamento enviado: ORÇ-99675 (antena Starlink, seg 19/10). A agenda também espera resposta do cliente sobre a OS-99690. A dúvida é sua: responda pelo assistente, ou *não 2* se não era.');
    v_r := pg_temp.f5c_dito('{"comando": "escolher", "n": 1, "letra": "A", "resto": null}');
    perform pg_temp.f5c_igual('4 letra na duvida', v_r ->> 'texto', 'O 1 não tem a opção A, e nada foi feito.');
    perform pg_temp.f5c_igual('4 sem precisa_pin', v_r ->> 'precisa_pin', null);
    v_r := pg_temp.f5c_dito('{"comando": "escolher", "n": 2, "letra": "B", "resto": null}');
    perform pg_temp.f5c_igual('4 letra na agenda', v_r ->> 'texto', 'O 2 não tem a opção B, e nada foi feito.');
    v_r := pg_temp.f5c_dito('{"comando": "escolher", "n": 3, "letra": "C", "resto": "amanha"}');
    perform pg_temp.f5c_igual('4 letra com resto', v_r ->> 'texto', 'A letra do 3 vai sozinha: *3 C*.');
    perform pg_temp.f5c_igual('4 a letra com resto não grava', (pg_temp.f5c_item(v_cartao, 3)).escolha, null);
    v_r := pg_temp.f5c_dito('{"comando": "escolher", "n": 3, "letra": "C", "resto": null}');
    perform pg_temp.f5c_igual('4 C', v_r ->> 'texto',
      'Anotei *3 C*: o ORÇ-99671 fica aprovado, aguardando o sinal, e peço a Ana o CPF e o endereço. *sim <PIN>* faz.');
    perform pg_temp.f5c_igual('4 C precisa_pin', v_r ->> 'precisa_pin', 'true');
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 4b. O rodapé, byte a byte: 1 aceite sem letra e 1 lembrete; depois de *1 B*; só o aceite com *1 B* ──
  begin
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg);
    v_joao := pg_temp.f5c_cli('João Cartao F5 Teste', c_joao);
    v_os2 := pg_temp.f5c_orc(v_joao, c_joao, 'ORÇ-99672', 'Troca das baterias da lancha', 3200);
    v_p := pg_temp.f5c_passo(v_joao, c_joao, v_os2);
    perform pg_temp.f5c_igual('4b o nome', public._retorno_nome(v_ana), 'Ana');
    perform pg_temp.f5c_igual('4b a variante', public._orcamento_texto_do_passo(v_p, c_agora) ->> 'variante', 'padrao_apresentacao');
    v_cartao := pg_temp.f5c_cartao(c_agora);
    v_esperado := concat_ws(E'\n',
      'Retorno · 2 esperando',
      '1. Ana · 14:05 · ''Pode fazer.''',
      '   O cliente tem 1 orçamento enviado: ORÇ-99671 (energia solar, seg 19/10) · R$ 9.840 · vale até seg 26/10',
      '   Era aprovação? *1 A* aprova e fica aguardando o sinal · *1 B* converte em OS sem sinal (tudo na conclusão) · *não 1* não era',
      '2. Lembrete do ORÇ-99672 · João · baterias · enviado seg 19/10 · sem resposta do cliente desde então · espera até qui 22/10',
      '   ''' || c_lembrete || '''',
      '   *sim <PIN>* manda hoje às 10h (ou agora; depois das 17h, no próximo dia útil) · *não 2* não manda',
      '*sim <PIN>* faz o 2 · *só 2* · *ver 1* · *não* · ou dite por áudio',
      'O 1 espera a sua letra (*1 A* · *1 B*) antes do *sim*.') || v_suf;
    perform pg_temp.f5c_igual('4b o cartão', pg_temp.f5c_texto(v_cartao), v_esperado);
    perform pg_temp.f5c_igual('4b o texto do item', (pg_temp.f5c_item(v_cartao, 2)).texto_mostrado, c_lembrete);
    v_r := pg_temp.f5c_dito('{"comando": "escolher", "n": 1, "letra": "B", "resto": null}');
    perform pg_temp.f5c_igual('4b a frase do B', v_r ->> 'texto',
      'Anotei *1 B*: converto o ORÇ-99671 em OS sem sinal e mando o ''Fechado'' a Ana. *sim <PIN>* faz.');
    v_esperado := concat_ws(E'\n',
      'Retorno · 2 esperando',
      '1. Ana · 14:05 · ''Pode fazer.''',
      '   O cliente tem 1 orçamento enviado: ORÇ-99671 (energia solar, seg 19/10) · R$ 9.840 · vale até seg 26/10',
      '   Era aprovação? *1 A* aprova e fica aguardando o sinal · *1 B* converte em OS sem sinal (tudo na conclusão) · *não 1* não era',
      '2. Lembrete do ORÇ-99672 · João · baterias · enviado seg 19/10 · sem resposta do cliente desde então · espera até qui 22/10',
      '   ''' || c_lembrete || '''',
      '   *sim <PIN>* manda hoje às 10h (ou agora; depois das 17h, no próximo dia útil) · *não 2* não manda',
      '*sim <PIN>* faz o 1 e o 2 · *só 1* · *ver 1* · *não* · ou dite por áudio') || v_suf;
    perform pg_temp.f5c_igual('4b depois do 1 B', pg_temp.f5c_texto(v_cartao), v_esperado);
    -- Só o aceite, com *1 B*.
    perform pg_temp.f5c_limpar();
    update public.orcamento_passos set estado = 'pulado', motivo = 'tirado' where id = v_p;
    v_cartao := pg_temp.f5c_cartao(c_agora);
    perform pg_temp.f5c_dito('{"comando": "escolher", "n": 1, "letra": "B", "resto": null}');
    perform pg_temp.f5c_tem('4b só o aceite', pg_temp.f5c_texto(v_cartao),
      E'\n*sim <PIN>* faz o 1 (converte o ORÇ-99671 em OS sem sinal) · *só 1* · *ver 1* · *não* · ou dite por áudio');
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 5. O *sim 7391* com a letra: B (a ferramenta converte), A (registrado na hora), a recusa no meio, C e D; e a cadência
  --        no mesmo cartão sem 23502 ──
  begin
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg);
    v_joao := pg_temp.f5c_cli('João Cartao F5 Teste', c_joao);
    v_os2 := pg_temp.f5c_orc(v_joao, c_joao, 'ORÇ-99672', 'Troca das baterias da lancha', 3200);
    v_p := pg_temp.f5c_passo(v_joao, c_joao, v_os2);
    v_cartao := pg_temp.f5c_cartao(c_agora);
    perform pg_temp.f5c_dito('{"comando": "escolher", "n": 1, "letra": "B", "resto": null}');
    v_r := pg_temp.f5c_sim(v_cartao);
    -- 5a. B: o aceite vai à ferramenta (sem_sinal, com a mensagem) e fica detectado com executado_em e decidido_por.
    if (v_r ->> 'ok')::boolean is not true or jsonb_array_length(v_r -> 'aceites') is distinct from 1
       or v_r -> 'aceites' -> 0 ->> 'escolha' is distinct from 'sem_sinal'
       or v_r -> 'aceites' -> 0 ->> 'msg_id' is distinct from (pg_temp.f5c_ac(v_ac)).whatsapp_message_id::text
       or v_r -> 'aceites' -> 0 ->> 'service_order_id' is distinct from v_os::text
       or v_r -> 'aceites' -> 0 ->> 'pedir_dados' is distinct from 'false' or v_r -> 'aceites' -> 0 ? 'feito' then
      raise exception '5a: os aceites (%)', v_r;
    end if;
    v_a := pg_temp.f5c_ac(v_ac);
    if v_a.estado is distinct from 'detectado' or v_a.executado_em is distinct from c_sim or v_a.decidido_por is distinct from v_dono then
      raise exception '5a: o aceite (%, %, %)', v_a.estado, v_a.executado_em, v_a.decidido_por;
    end if;
    perform pg_temp.f5c_igual('5a o item', (pg_temp.f5c_item(v_cartao, 1)).estado, 'feito');
    -- 5e. A cadência no mesmo cartão: a saída agendada com o texto aprovado, e nenhum 23502.
    perform pg_temp.f5c_igual('5e o passo', pg_temp.f5c_px(v_p), 'agendado/-');
    if not exists (select 1 from public.retorno_saidas s join public.orcamento_passos p on p.saida_id = s.id
                    where p.id = v_p and s.emissor = 'orcamento' and s.estado = 'agendada' and s.dados ->> 'por' = 'sim'
                      and s.dados ->> 'texto_aprovado' = c_lembrete and s.abertura_id is null and s.chave = '00009972') then
      raise exception '5e: a saída do lembrete';
    end if;
    perform pg_temp.f5c_igual('5e vai sair', v_r ->> 'vai_sair', '1');
    perform pg_temp.f5c_tem('5e o aviso', v_r ->> 'aviso', 'Vai sair 1: o lembrete do ORÇ-99672 (João).');
    -- O orçamento convertido pela ferramenta (aqui, pela bancada): o vigia logo depois não derruba o aceite.
    update public.service_orders set status = 'open', converted_to_os_at = c_sim + interval '1 minute', quote_status = 'approved',
                                     service_order_number = 'OS-99671'
     where id = v_os;
    perform public.orcamento_vigia(c_sim + interval '5 minutes');
    perform pg_temp.f5c_igual('5a o vigia não derruba', (pg_temp.f5c_ac(v_ac)).estado, 'detectado');
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  begin
    -- 5b. A: na mesma execução, awaiting_deposit, o aceite com_sinal e o "Fechado" agendado; o vigia não muda nada.
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg);
    v_cartao := pg_temp.f5c_cartao(c_agora);
    perform pg_temp.f5c_dito('{"comando": "escolher", "n": 1, "letra": "A", "resto": null}');
    v_r := pg_temp.f5c_sim(v_cartao);
    if v_r -> 'aceites' -> 0 ->> 'escolha' is distinct from 'com_sinal' or v_r -> 'aceites' -> 0 ->> 'feito' is distinct from 'true'
       or v_r -> 'aceites' -> 0 -> 'registrado' ->> 'fechado' is distinct from 'agendada'
       or v_r -> 'aceites' -> 0 -> 'registrado' ->> 'dados' is distinct from 'false'
       or v_r -> 'aceites' -> 0 ->> 'quote_status' is distinct from 'awaiting_deposit' then
      raise exception '5b: os aceites (%)', v_r;
    end if;
    perform pg_temp.f5c_igual('5b o funil', (select so.quote_status from public.service_orders so where so.id = v_os), 'awaiting_deposit');
    perform pg_temp.f5c_igual('5b o aceite', (pg_temp.f5c_ac(v_ac)).estado, 'com_sinal');
    if not exists (select 1 from public.retorno_saidas s
                    where s.emissor = 'orcamento' and s.tipo = 'orc_fechado' and s.estado = 'agendada' and s.dados ->> 'aceite_id' = v_ac::text) then
      raise exception '5b: o "Fechado" não foi agendado';
    end if;
    perform public.orcamento_vigia(c_sim + interval '5 minutes');
    if (pg_temp.f5c_ac(v_ac)).estado is distinct from 'com_sinal'
       or (select so.quote_status from public.service_orders so where so.id = v_os) is distinct from 'awaiting_deposit' then
      raise exception '5b: o vigia mudou o aceite ou o funil';
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  begin
    -- 5c. A com o registro recusando no meio (a conferência passou): o item cai, e o funil não muda (o sub-bloco desfez).
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg);
    v_cartao := pg_temp.f5c_cartao(c_agora);
    perform pg_temp.f5c_dito('{"comando": "escolher", "n": 1, "letra": "A", "resto": null}');
    create or replace function public.orcamento_aceite_registrar(p_aceite uuid, p_ok boolean, p_resultado jsonb, p_autor uuid,
                                                                 p_pedir_dados boolean, p_agora timestamptz default now())
    returns jsonb language sql as $falso$ select '{"ok": false, "motivo": "estado"}'::jsonb $falso$;
    v_r := pg_temp.f5c_sim(v_cartao);
    perform pg_temp.f5c_tem('5c o aviso', v_r ->> 'aviso', 'o 1 caiu: não consegui registrar o aceite; nada mudou');
    perform pg_temp.f5c_igual('5c os aceites', (v_r -> 'aceites')::text, '[]');
    perform pg_temp.f5c_igual('5c o funil', (select so.quote_status from public.service_orders so where so.id = v_os), 'sent');
    perform pg_temp.f5c_igual('5c o aceite', (pg_temp.f5c_ac(v_ac)).estado, 'detectado');
    perform pg_temp.f5c_igual('5c o item', (pg_temp.f5c_item(v_cartao, 1)).estado || '/' || (pg_temp.f5c_item(v_cartao, 1)).caiu_motivo, 'caiu/fato_mudou');
    if exists (select 1 from public.audit_log l where l.table_name = 'service_orders' and l.record_id = v_os) then
      raise exception '5c: o audit_log da aprovação ficou';
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  begin
    -- 5d. C e D com os dados da nota ligados: C registra e agenda o pedido de dados; D vai à ferramenta com pedir_dados.
    update public.retorno_config set dados_nota_ligado = true where id;
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg);
    v_pedro := pg_temp.f5c_cli('Pedro Cartao F5 Teste', c_pedro);
    v_os3 := pg_temp.f5c_orc(v_pedro, c_pedro, 'ORÇ-99673', 'Revisão do inversor', 1500);
    v_ac2 := pg_temp.f5c_aceite(v_pedro, c_pedro, v_os3, '2026-10-20 15:00-03');
    v_cartao := pg_temp.f5c_cartao(c_agora);
    perform pg_temp.f5c_dito('{"comando": "escolher", "n": 1, "letra": "C", "resto": null}');
    v_r := pg_temp.f5c_dito('{"comando": "escolher", "n": 2, "letra": "D", "resto": null}');
    perform pg_temp.f5c_igual('5d a frase do D', v_r ->> 'texto',
      'Anotei *2 D*: converto o ORÇ-99673 em OS sem sinal, mando o ''Fechado'' e peço a Pedro o CPF e o endereço. *sim <PIN>* faz.');
    v_r := pg_temp.f5c_sim(v_cartao);
    if jsonb_array_length(v_r -> 'aceites') is distinct from 2
       or v_r -> 'aceites' -> 0 ->> 'escolha' is distinct from 'com_sinal' or v_r -> 'aceites' -> 0 ->> 'pedir_dados' is distinct from 'true'
       or v_r -> 'aceites' -> 0 -> 'registrado' ->> 'dados' is distinct from 'true'
       or v_r -> 'aceites' -> 1 ->> 'escolha' is distinct from 'sem_sinal' or v_r -> 'aceites' -> 1 ->> 'pedir_dados' is distinct from 'true' then
      raise exception '5d: os aceites (%)', v_r;
    end if;
    if not exists (select 1 from public.retorno_saidas s
                    where s.emissor = 'orcamento' and s.tipo = 'orc_dados_nota' and s.estado = 'agendada' and s.dados ->> 'aceite_id' = v_ac::text)
       or (pg_temp.f5c_ac(v_ac)).pedir_dados is not true then
      raise exception '5d: o pedido de dados do C';
    end if;
    if (pg_temp.f5c_ac(v_ac2)).executado_em is distinct from c_sim then
      raise exception '5d: o D sem executado_em';
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  begin
    -- 5f (P7.2 nº 5b). O *sim* com o aceite sem letra: o item vai a 'fora', o aceite continua detectado e volta na lista.
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg);
    v_cartao := pg_temp.f5c_cartao(c_agora);
    v_r := pg_temp.f5c_sim(v_cartao);
    perform pg_temp.f5c_tem('5f o aviso', v_r ->> 'aviso', 'o 1 ficou sem letra: continua na lista');
    perform pg_temp.f5c_igual('5f o item', (pg_temp.f5c_item(v_cartao, 1)).estado, 'fora');
    perform pg_temp.f5c_igual('5f o aceite', (pg_temp.f5c_ac(v_ac)).estado, 'detectado');
    perform pg_temp.f5c_tem('5f volta', pg_temp.f5c_lista(c_sim + interval '1 hour'), v_ac::text);
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 6. *não 1*: com outro item no cartão, num cartão de um item só, e o *não* sem número ──
  begin
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_k4 := pg_temp.f5c_caso(v_ana, c_ana, 'Pode fazer.', c_msg);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg, 'detectado', v_k4);
    v_joao := pg_temp.f5c_cli('João Cartao F5 Teste', c_joao);
    v_os2 := pg_temp.f5c_orc(v_joao, c_joao, 'ORÇ-99672', 'Troca das baterias da lancha', 3200);
    v_p := pg_temp.f5c_passo(v_joao, c_joao, v_os2);
    v_cartao := pg_temp.f5c_cartao(c_agora);
    v_r := pg_temp.f5c_dito('{"comando": "tirar", "ns": [1]}');
    perform pg_temp.f5c_igual('6a a resposta', v_r ->> 'texto', 'Tirei o 1: com o *sim <PIN>*, anoto que não era aprovação.');
    perform pg_temp.f5c_igual('6a ainda detectado', (pg_temp.f5c_ac(v_ac)).estado, 'detectado');
    v_r := pg_temp.f5c_sim(v_cartao);
    v_a := pg_temp.f5c_ac(v_ac);
    if v_a.estado is distinct from 'nao_era' or v_a.decidido_por is distinct from v_dono or v_a.decidido_em is distinct from c_sim then
      raise exception '6a: o aceite (%, %)', v_a.estado, v_a.decidido_por;
    end if;
    -- O caso volta à lista da F2, sem a prioridade 3.
    if not exists (select 1 from public._orcamento_cartao_lista(c_sim + interval '1 minute', null) l
                    where l.tipo = 'caso' and l.abertura_id = v_k4 and l.prioridade is distinct from 3::smallint) then
      raise exception '6a: o caso não voltou à lista como caso';
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  begin
    -- 6b. *não 1* num cartão de um item só: o cartão fecha (T-DIT-2), e o aceite fica nao_era.
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg);
    v_cartao := pg_temp.f5c_cartao(c_agora);
    v_r := pg_temp.f5c_dito('{"comando": "tirar", "ns": [1]}');
    perform pg_temp.f5c_igual('6b a resposta', v_r ->> 'texto', 'Cartão fechado: nada foi mandado.');
    perform pg_temp.f5c_igual('6b o aceite', (pg_temp.f5c_ac(v_ac)).estado, 'nao_era');
    -- 6c. O *não* sem número (a recusa do cartão, pela confirmação): nada muda no aceite.
    update public.orcamento_aceites set estado = 'detectado', decidido_em = null, decidido_por = null where id = v_ac;
    v_cartao := pg_temp.f5c_cartao(c_agora);
    update public.ai_operator_pending_actions p set status = 'rejected'
     where p.id = (select c.pendencia_id from public.retorno_cartoes c where c.id = v_cartao);
    perform public.retorno_cartao_vivo(c_sim);
    perform pg_temp.f5c_igual('6c o item', (pg_temp.f5c_item(v_cartao, 1)).estado, 'fora');
    perform pg_temp.f5c_igual('6c o aceite', (pg_temp.f5c_ac(v_ac)).estado, 'detectado');
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 6b. *só* e *sem* não decidem nada ──
  for v_n in 1 .. 5 loop
    begin
      v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
      v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
      v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg);
      v_joao := pg_temp.f5c_cli('João Cartao F5 Teste', c_joao);
      v_os2 := pg_temp.f5c_orc(v_joao, c_joao, 'ORÇ-99672', 'Troca das baterias da lancha', 3200);
      v_p := pg_temp.f5c_passo(v_joao, c_joao, v_os2);
      v_cartao := pg_temp.f5c_cartao(c_agora);
      if v_n = 1 then
        -- *só 2*: o lembrete sai; o aceite continua detectado e volta no próximo *retorno*.
        perform pg_temp.f5c_dito('{"comando": "so", "ns": [2]}');
      elsif v_n = 2 then
        -- *1 B*, *só 1*: o aceite é decidido pela letra; o passo continua à espera e volta no dia seguinte, dentro do prazo.
        perform pg_temp.f5c_dito('{"comando": "escolher", "n": 1, "letra": "B", "resto": null}');
        perform pg_temp.f5c_dito('{"comando": "so", "ns": [1]}');
      elsif v_n = 3 then
        -- *sem 1*: o mesmo que *só 2*.
        perform pg_temp.f5c_dito('{"comando": "sem", "ns": [1]}');
      elsif v_n = 4 then
        -- *não 1* e depois *só 2*: a marca do *não* some.
        perform pg_temp.f5c_dito('{"comando": "tirar", "ns": [1]}');
        perform pg_temp.f5c_dito('{"comando": "so", "ns": [2]}');
        perform pg_temp.f5c_igual('6b-4 a marca', (pg_temp.f5c_item(v_cartao, 1)).tirado_em::text, null);
      else
        -- *não 1*, *retorno* (o item volta selecionado) e *sim*: tratado como selecionado, sem letra.
        perform pg_temp.f5c_dito('{"comando": "tirar", "ns": [1]}');
        perform public.retorno_cartao_abrir('puxar', c_dita + interval '1 minute');
      end if;
      v_r := pg_temp.f5c_sim(v_cartao);
      if v_n = 2 then
        perform pg_temp.f5c_igual('6b-2 o aceite', (pg_temp.f5c_ac(v_ac)).executado_em::text, c_sim::text);
        perform pg_temp.f5c_igual('6b-2 o item 2', (pg_temp.f5c_item(v_cartao, 2)).estado, 'fora');
        perform pg_temp.f5c_igual('6b-2 o passo', pg_temp.f5c_px(v_p), 'aguarda_sim/-');
        perform pg_temp.f5c_tem('6b-2 volta amanhã', pg_temp.f5c_lista(c_amanha), v_p::text);
      else
        perform pg_temp.f5c_igual(format('6b-%s o aceite', v_n), (pg_temp.f5c_ac(v_ac)).estado, 'detectado');
        perform pg_temp.f5c_igual(format('6b-%s o item 1', v_n), (pg_temp.f5c_item(v_cartao, 1)).estado, 'fora');
        perform pg_temp.f5c_tem(format('6b-%s volta', v_n), pg_temp.f5c_lista(c_sim + interval '1 hour'), v_ac::text);
        if v_n = 5 then
          perform pg_temp.f5c_tem('6b-5 sem letra', v_r ->> 'aviso', 'o 1 ficou sem letra: continua na lista');
          perform pg_temp.f5c_igual('6b-5 o passo', pg_temp.f5c_px(v_p), 'agendado/-');
        else
          perform pg_temp.f5c_igual(format('6b-%s o passo', v_n), pg_temp.f5c_px(v_p), 'agendado/-');
        end if;
      end if;
      raise exception 'f5c_cenario' using errcode = 'P0001';
    exception when others then
      if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
        raise;
      end if;
    end;
  end loop;

  -- ── 6c. Os antigos do mesmo cliente pelo cartão (_orcamento_aceite_fechar_antigos): *não 1* + *sim*, *resolvido 1*, o ditado
  --        que saiu e *pessoal 1* ──
  for v_n in 1 .. 4 loop
    begin
      v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
      v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
      v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, '2026-10-20 10:00-03');
      if v_n >= 3 then
        v_k4 := pg_temp.f5c_caso(v_ana, c_ana, 'Pode fazer, sim.', '2026-10-20 11:00-03');
        v_ac2 := pg_temp.f5c_aceite(v_ana, c_ana, v_os, '2026-10-20 11:00-03', 'detectado', v_k4);
      else
        v_ac2 := pg_temp.f5c_aceite(v_ana, c_ana, v_os, '2026-10-20 11:00-03', 'detectado', null, 'Pode fazer, sim.');
      end if;
      v_joao := pg_temp.f5c_cli('João Cartao F5 Teste', c_joao);
      v_os2 := pg_temp.f5c_orc(v_joao, c_joao, 'ORÇ-99672', 'Troca das baterias da lancha', 3200);
      v_p := pg_temp.f5c_passo(v_joao, c_joao, v_os2);
      -- O cartão mostra só o das 11:00.
      v_cartao := pg_temp.f5c_cartao(c_agora);
      perform pg_temp.f5c_igual(format('6c-%s só o das 11:00', v_n), (pg_temp.f5c_item(v_cartao, 1)).aceite_id::text, v_ac2::text);
      if strpos(pg_temp.f5c_itens(v_cartao)::text, v_ac::text) > 0 then
        raise exception '6c-%: o das 10:00 está no cartão', v_n;
      end if;
      if v_n = 1 then
        perform pg_temp.f5c_dito('{"comando": "tirar", "ns": [1]}');
        perform pg_temp.f5c_sim(v_cartao);
        v_esperado := 'nao_era/substituido';
      elsif v_n = 2 then
        v_r := public._retorno_dito_resolvido(1, v_dono, c_dita);
        perform pg_temp.f5c_igual('6c-2 a resposta', v_r ->> 'texto', 'o aceite do ORÇ-99671 (Ana): resolvido, saiu da lista.');
        v_esperado := 'nao_era/substituido';
      elsif v_n = 3 then
        perform pg_temp.f5c_dito('{"comando": "ditar", "n": 1, "texto": "Ana, te passo a data amanhã"}');
        v_r := pg_temp.f5c_sim(v_cartao);
        perform public.retorno_item_enviado((pg_temp.f5c_item(v_cartao, 1)).id, true, null, c_sim + interval '1 minute');
        v_esperado := 'respondido/substituido';
      else
        v_r := public._retorno_dito_pessoal(1, v_dono, c_dita);
        v_esperado := 'caiu/caiu';
      end if;
      perform pg_temp.f5c_igual(format('6c-%s os dois', v_n), (pg_temp.f5c_ac(v_ac2)).estado || '/' || (pg_temp.f5c_ac(v_ac)).estado, v_esperado);
      if v_n = 4 and ((pg_temp.f5c_ac(v_ac)).resultado ->> 'motivo' is distinct from 'pessoal'
                      or (pg_temp.f5c_ac(v_ac2)).resultado ->> 'motivo' is distinct from 'pessoal') then
        raise exception '6c-4: o motivo pessoal';
      end if;
      if v_n < 4 and (pg_temp.f5c_ac(v_ac)).resultado ->> 'substituido_por' is distinct from v_ac2::text then
        raise exception '6c-%: o substituido_por', v_n;
      end if;
      -- O próximo *retorno* não mostra o das 10:00.
      if strpos(pg_temp.f5c_lista(c_sim + interval '1 hour'), v_ac::text) > 0 then
        raise exception '6c-%: o das 10:00 voltou à lista', v_n;
      end if;
      raise exception 'f5c_cenario' using errcode = 'P0001';
    exception when others then
      if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
        raise;
      end if;
    end;
  end loop;

  -- ── 7 e 17. O total mudou entre montar e executar; o item órfão ──
  begin
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg);
    v_cartao := pg_temp.f5c_cartao(c_agora);
    perform pg_temp.f5c_dito('{"comando": "escolher", "n": 1, "letra": "A", "resto": null}');
    update public.service_orders set grand_total = 9900 where id = v_os;
    v_r := pg_temp.f5c_sim(v_cartao);
    perform pg_temp.f5c_tem('7 o aviso', v_r ->> 'aviso', 'o 1 caiu: o ORÇ-99671 mudou desde o cartão; não fiz nada');
    perform pg_temp.f5c_igual('7 o item', (pg_temp.f5c_item(v_cartao, 1)).estado || '/' || (pg_temp.f5c_item(v_cartao, 1)).caiu_motivo,
                              'caiu/orcamento_mudou');
    v_a := pg_temp.f5c_ac(v_ac);
    if v_a.estado is distinct from 'caiu' or v_a.resultado ->> 'motivo' is distinct from 'orcamento_mudou'
       or (v_a.resultado ->> 'total_agora')::numeric is distinct from 9900::numeric then
      raise exception '7: o aceite (%, %)', v_a.estado, v_a.resultado;
    end if;
    perform pg_temp.f5c_igual('7 o funil', (select so.quote_status from public.service_orders so where so.id = v_os), 'sent');
    perform pg_temp.f5c_igual('7 nada converte', (v_r -> 'aceites')::text, '[]');
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  begin
    -- 17. O item órfão (o orçamento apagado: service_order_id nulo no item e no aceite): orcamento_mudou, e o *sim* derruba os
    --     dois sem 23502 e sem conversão.
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg);
    v_cartao := pg_temp.f5c_cartao(c_agora);
    perform pg_temp.f5c_dito('{"comando": "escolher", "n": 1, "letra": "B", "resto": null}');
    update public.orcamento_aceites set service_order_id = null where id = v_ac;
    update public.retorno_cartao_itens set service_order_id = null where cartao_id = v_cartao and n = 1;
    v_r := public._retorno_item_conferir((pg_temp.f5c_item(v_cartao, 1)).id, c_sim, false);
    perform pg_temp.f5c_igual('17 a conferência', (v_r ->> 'ok') || '/' || (v_r ->> 'motivo'), 'false/orcamento_mudou');
    v_r := pg_temp.f5c_sim(v_cartao);
    perform pg_temp.f5c_igual('17 o item', (pg_temp.f5c_item(v_cartao, 1)).estado, 'caiu');
    perform pg_temp.f5c_igual('17 o aceite', (pg_temp.f5c_ac(v_ac)).estado, 'caiu');
    perform pg_temp.f5c_igual('17 nada converte', (v_r -> 'aceites')::text, '[]');
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 8 e 9. O item da cadência: a última vaga, o *sim*, o *não 3*, o dia seguinte; o cliente que escreveu antes do *sim* ──
  for v_n in 1 .. 3 loop
    begin
      v_rodrigo := pg_temp.f5c_cli('Rodrigo Cartao F5 Teste', c_rodrigo);
      perform pg_temp.f5c_caso(v_rodrigo, c_rodrigo, 'bom dia', '2026-10-21 08:00-03');
      v_bia := pg_temp.f5c_cli('Bia Cartao F5 Teste', c_bia);
      perform pg_temp.f5c_caso(v_bia, c_bia, 'boa tarde', '2026-10-21 08:10-03');
      v_caio := pg_temp.f5c_cli('Caio Cartao F5 Teste', c_caio);
      perform pg_temp.f5c_caso(v_caio, c_caio, 'oi', '2026-10-21 08:20-03');
      v_joao := pg_temp.f5c_cli('João Cartao F5 Teste', c_joao);
      v_os2 := pg_temp.f5c_orc(v_joao, c_joao, 'ORÇ-99672', 'Troca das baterias da lancha', 3200);
      v_p := pg_temp.f5c_passo(v_joao, c_joao, v_os2);
      v_cartao := pg_temp.f5c_cartao(c_agora);
      -- 8a. 3 casos vivos e o passo, 3 vagas: a 3ª vaga é do passo, e o 3º caso fica no "mais".
      if (pg_temp.f5c_item(v_cartao, 3)).passo_id is distinct from v_p
         or (select c.mais from public.retorno_cartoes c where c.id = v_cartao) is distinct from 1 then
        raise exception '8a: a vaga do passo (%)', pg_temp.f5c_itens(v_cartao);
      end if;
      if v_n = 1 then
        -- 8b. *sim*: a saída agendada com por = sim e o texto aprovado; o passo aprovado pelo dono.
        v_r := pg_temp.f5c_sim(v_cartao);
        if not exists (select 1 from public.orcamento_passos p join public.retorno_saidas s on s.id = p.saida_id
                        where p.id = v_p and p.estado = 'agendado' and p.aprovado_por = v_dono and p.aprovado_em = c_sim
                          and p.texto_aprovado = c_lembrete and s.dados ->> 'por' = 'sim' and s.dados ->> 'texto_aprovado' = c_lembrete
                          and s.enviar_em = timestamptz '2026-10-21 10:00-03') then
          raise exception '8b: a saída do passo aprovado (%)', pg_temp.f5c_px(v_p);
        end if;
        perform pg_temp.f5c_igual('8b o item', (pg_temp.f5c_item(v_cartao, 3)).estado, 'feito');
        if (pg_temp.f5c_item(v_cartao, 3)).saida_id is null then
          raise exception '8b: o item sem a saída';
        end if;
      elsif v_n = 2 then
        -- 8c. *não 3* + *sim*: pulado/tirado.
        v_r := pg_temp.f5c_dito('{"comando": "tirar", "ns": [3]}');
        perform pg_temp.f5c_igual('8c a resposta', v_r ->> 'texto', 'Tirei o 3: com o *sim <PIN>*, essa mensagem do orçamento não sai.');
        perform pg_temp.f5c_sim(v_cartao);
        perform pg_temp.f5c_igual('8c o passo', pg_temp.f5c_px(v_p), 'pulado/tirado');
      else
        -- 9. O cliente escreveu depois de o item ser montado e antes do *sim*: o item cai, e nada sai.
        perform pg_temp.f5c_msg(c_joao, 'Oi, vi sim, vou ver com a minha esposa', c_dita);
        v_r := pg_temp.f5c_sim(v_cartao);
        perform pg_temp.f5c_tem('9 o aviso', v_r ->> 'aviso', 'o 3 caiu: o cliente escreveu depois do envio; não mandei');
        perform pg_temp.f5c_igual('9 o item', (pg_temp.f5c_item(v_cartao, 3)).caiu_motivo, 'cliente_escreveu');
        perform pg_temp.f5c_igual('9 o passo', pg_temp.f5c_px(v_p), 'aguarda_sim/-');
        if exists (select 1 from public.retorno_saidas s where s.emissor = 'orcamento' and s.dados ->> 'passo_id' = v_p::text) then
          raise exception '9: saiu a mensagem do passo';
        end if;
      end if;
      raise exception 'f5c_cenario' using errcode = 'P0001';
    exception when others then
      if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
        raise;
      end if;
    end;
  end loop;
  begin
    -- 8d. O passo que não foi aprovado (de fora por *só*) volta ao cartão no dia seguinte, dentro do prazo.
    v_joao := pg_temp.f5c_cli('João Cartao F5 Teste', c_joao);
    v_os2 := pg_temp.f5c_orc(v_joao, c_joao, 'ORÇ-99672', 'Troca das baterias da lancha', 3200);
    v_p := pg_temp.f5c_passo(v_joao, c_joao, v_os2);
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg);
    v_cartao := pg_temp.f5c_cartao(c_agora);
    perform pg_temp.f5c_dito('{"comando": "so", "ns": [1]}');
    perform pg_temp.f5c_sim(v_cartao);
    v_cartao := pg_temp.f5c_cartao(c_amanha);
    if not exists (select 1 from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.passo_id = v_p and i.estado = 'vivo') then
      raise exception '8d: o passo não voltou ao cartão no dia seguinte';
    end if;
    perform pg_temp.f5c_tem('8d espera até', pg_temp.f5c_texto(v_cartao), 'espera até qui 22/10');
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 10. *ver*, *pessoal*, *resolvido*, *dita* e o ditado por áudio nos itens sem caso ──
  begin
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg);
    v_joao := pg_temp.f5c_cli('João Cartao F5 Teste', c_joao);
    v_os2 := pg_temp.f5c_orc(v_joao, c_joao, 'ORÇ-99672', 'Troca das baterias da lancha', 3200);
    v_p := pg_temp.f5c_passo(v_joao, c_joao, v_os2);
    v_cartao := pg_temp.f5c_cartao(c_agora);
    v_r := public.retorno_ver_caso(2, v_dono, c_dita);
    perform pg_temp.f5c_tem('10 ver 2', v_r ->> 'texto', 'Texto inteiro: ''' || c_lembrete || '''');
    perform pg_temp.f5c_tem('10 ver 2 os passos', v_r ->> 'texto', 'Os passos: lembrete qua 21/10 (à espera do sim)');
    v_r := public.retorno_ver_caso(1, v_dono, c_dita);
    perform pg_temp.f5c_tem('10 ver 1 a mensagem', v_r ->> 'texto', '''Pode fazer.''');
    perform pg_temp.f5c_tem('10 ver 1 o orçamento', v_r ->> 'texto', 'O cliente tem 1 orçamento enviado: ORÇ-99671');
    v_r := public._retorno_dito_pessoal(2, v_dono, c_dita);
    perform pg_temp.f5c_igual('10 pessoal 2', v_r ->> 'texto', 'O 2 não é uma conversa: *pessoal* vale só para caso. Use *não 2*.');
    v_r := pg_temp.f5c_dito('{"comando": "ditar", "n": 1, "texto": "Ana, te passo a data amanhã"}');
    perform pg_temp.f5c_igual('10 dita 1', v_r ->> 'texto', 'Este item não tem conversa aberta: responda pelo assistente.');
    perform pg_temp.f5c_igual('10 dita 1 não gravou', (pg_temp.f5c_item(v_cartao, 1)).texto_ditado, null);
    v_r := public.retorno_destino_do_item(1, v_dono, c_dita);
    perform pg_temp.f5c_igual('10 o áudio', v_r ->> 'erro', 'Este item não tem conversa aberta: responda pelo assistente.');
    v_r := public._retorno_dito_resolvido(2, v_dono, c_dita);
    perform pg_temp.f5c_igual('10 resolvido 2', v_r ->> 'texto', 'o lembrete do ORÇ-99672 (João): resolvido, saiu da lista.');
    perform pg_temp.f5c_igual('10 resolvido 2 o passo', pg_temp.f5c_px(v_p), 'pulado/tirado');
    perform pg_temp.f5c_igual('10 resolvido 2 o item', (pg_temp.f5c_item(v_cartao, 2)).estado, 'caiu');
    v_r := public._retorno_dito_resolvido(1, v_dono, c_dita);
    perform pg_temp.f5c_igual('10 resolvido 1', v_r ->> 'texto', 'o aceite do ORÇ-99671 (Ana): resolvido, saiu da lista.');
    perform pg_temp.f5c_igual('10 resolvido 1 o aceite', (pg_temp.f5c_ac(v_ac)).estado, 'nao_era');
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 10b, 10c e 10d. O aceite com caso: o ditado, o *pessoal*, e o ditado depois da letra (e a letra depois do ditado) ──
  for v_n in 1 .. 4 loop
    begin
      v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
      v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
      v_k4 := pg_temp.f5c_caso(v_ana, c_ana, 'Pode fazer.', c_msg);
      v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg, 'detectado', v_k4);
      v_cartao := pg_temp.f5c_cartao(c_agora);
      if v_n <= 2 then
        -- 10b. *1 B* e depois *dita 1 …*: a letra some; o *sim* manda o ditado pelo caso; com p_ok, respondido; sem, detectado.
        perform pg_temp.f5c_dito('{"comando": "escolher", "n": 1, "letra": "B", "resto": null}');
        perform pg_temp.f5c_dito('{"comando": "ditar", "n": 1, "texto": "Ana, te passo a data amanhã"}');
        perform pg_temp.f5c_igual('10b a letra some', (pg_temp.f5c_item(v_cartao, 1)).escolha, null);
        v_r := pg_temp.f5c_sim(v_cartao);
        if jsonb_array_length(v_r -> 'ditados') is distinct from 1 or v_r -> 'ditados' -> 0 ->> 'phone' is distinct from c_ana
           or v_r -> 'ditados' -> 0 ->> 'texto' is distinct from 'Ana, te passo a data amanhã'
           or (v_r -> 'aceites')::text is distinct from '[]' then
          raise exception '10b: o ditado (%)', v_r;
        end if;
        perform pg_temp.f5c_tem('10b o aviso', v_r ->> 'aviso', 'o 1: mandei o seu texto a Ana; o ORÇ-99671 ficou como estava (converta pela tela ou pelo assistente)');
        perform public.retorno_item_enviado((pg_temp.f5c_item(v_cartao, 1)).id, v_n = 1, null, c_sim + interval '1 minute');
        if v_n = 1 then
          v_a := pg_temp.f5c_ac(v_ac);
          if v_a.estado is distinct from 'respondido' or v_a.decidido_por is distinct from v_dono
             or v_a.resultado ->> 'ditado' is distinct from 'true' then
            raise exception '10b: o aceite respondido (%)', v_a.estado;
          end if;
          perform pg_temp.f5c_igual('10b o orçamento', (select so.quote_status from public.service_orders so where so.id = v_os), 'sent');
        else
          perform pg_temp.f5c_igual('10b sem p_ok o aceite', (pg_temp.f5c_ac(v_ac)).estado, 'detectado');
          perform pg_temp.f5c_igual('10b sem p_ok o item', (pg_temp.f5c_item(v_cartao, 1)).estado, 'fora');
        end if;
      elsif v_n = 3 then
        -- 10c. *pessoal 1*: a F2 fecha o caso e marca o número; o aceite cai por pessoal.
        v_r := public._retorno_dito_pessoal(1, v_dono, c_dita);
        perform pg_temp.f5c_igual('10c o caso', (select a.estado from public.retorno_aberturas a where a.id = v_k4), 'fechada');
        perform pg_temp.f5c_igual('10c o número', (select l.lead_tipo from public.whatsapp_leads l where l.phone_normalized = c_ana), 'pessoal');
        perform pg_temp.f5c_igual('10c o aceite', (pg_temp.f5c_ac(v_ac)).estado || '/' || ((pg_temp.f5c_ac(v_ac)).resultado ->> 'motivo'),
                                  'caiu/pessoal');
      else
        -- 10d. *dita 1 …* e depois *1 B*: o ditado sai do item; o *sim* manda só o "Fechado" (a ferramenta), nada em ditados.
        perform pg_temp.f5c_dito('{"comando": "ditar", "n": 1, "texto": "Ana, te passo a data amanhã"}');
        v_r := pg_temp.f5c_dito('{"comando": "escolher", "n": 1, "letra": "B", "resto": null}');
        perform pg_temp.f5c_igual('10d a frase', v_r ->> 'texto',
          'Anotei *1 B*: converto o ORÇ-99671 em OS sem sinal e mando o ''Fechado'' a Ana. *sim <PIN>* faz. O texto que você ditou saiu do item.');
        v_i := pg_temp.f5c_item(v_cartao, 1);
        if v_i.texto_ditado is not null or v_i.ditado_via is not null or v_i.escolha is distinct from 'B' then
          raise exception '10d: o item (%, %)', v_i.texto_ditado, v_i.escolha;
        end if;
        v_r := pg_temp.f5c_sim(v_cartao);
        if v_r -> 'aceites' -> 0 ->> 'escolha' is distinct from 'sem_sinal' or (v_r -> 'ditados')::text is distinct from '[]' then
          raise exception '10d: o *sim* (%)', v_r;
        end if;
      end if;
      raise exception 'f5c_cenario' using errcode = 'P0001';
    exception when others then
      if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
        raise;
      end if;
    end;
  end loop;

  -- ── 11, 12, 13 e 19. O cartão vivo com item sem caso; _retorno_tem_orcamento; nada do cliente na conversa; o rodapé ──
  begin
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg, 'detectado', null, 'Fechado! FRASE-MARCADA-F5C');
    v_cartao := pg_temp.f5c_cartao(c_agora);
    -- 11. retorno_cartao_vivo devolve o item de abertura nula, com as letras.
    v_r := public.retorno_cartao_vivo(c_dita);
    if v_r -> 'itens' -> 0 ->> 'abertura_id' is not null or v_r -> 'itens' -> 0 ->> 'tipo_item' is distinct from 'aceite'
       or (v_r -> 'letras' -> '1')::text is distinct from '["A", "B"]' then
      raise exception '11: o cartão vivo (%)', v_r;
    end if;
    -- 19. O rodapé sem *dita* no item sem caso, e a linha da letra.
    perform pg_temp.f5c_tem('19 sem dita', pg_temp.f5c_texto(v_cartao),
      E'\n*ver 1* · *não* · ou responda pelo assistente\nO 1 espera a sua letra (*1 A* · *1 B*) antes do *sim*.' || v_suf);
    -- 13. O trecho do cliente vai só ao WhatsApp do dono (o cartão), nunca à conversa do assistente.
    perform pg_temp.f5c_tem('13 no cartão', pg_temp.f5c_texto(v_cartao), 'FRASE-MARCADA-F5C');
    if (select count(*) from public.ai_operator_messages m
         where m.session_id = (select c.sessao_id from public.retorno_cartoes c where c.id = v_cartao)
           and m.content like '%FRASE-MARCADA-F5C%') is distinct from 0::bigint then
      raise exception '13: o texto do cliente foi à conversa do assistente';
    end if;
    v_r := public.retorno_ver_caso(1, v_dono, c_dita);
    if strpos(v_r ->> 'historico', 'FRASE-MARCADA') > 0 then
      raise exception '13: o texto do cliente no histórico do *ver*';
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  begin
    -- 19b. Com o 1º item com caso, o rodapé de hoje (o *dita* vale nele).
    v_pedro := pg_temp.f5c_cli('Pedro Cartao F5 Teste', c_pedro);
    perform pg_temp.f5c_caso(v_pedro, c_pedro, 'cadê o meu motorhome?', '2026-10-20 08:00-03', 'cliente', 'vencida');
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg, 'detectado', null, 'Fechado!');
    v_cartao := pg_temp.f5c_cartao(c_agora);
    perform pg_temp.f5c_tem('19b o rodapé', pg_temp.f5c_texto(v_cartao),
      E'\n*ver 1* · *dita 1 …* · *não* · ou dite por áudio\nO 2 espera a sua letra (*2 A* · *2 B*) antes do *sim*.' || v_suf);
    -- 12. _retorno_tem_orcamento: o rascunho com envio registrado não está "em preparação"; sem envio, está.
    v_caio := pg_temp.f5c_cli('Caio Cartao F5 Teste', c_caio);
    v_k1 := pg_temp.f5c_caso(v_caio, c_caio, 'e o orçamento?', '2026-10-21 08:30-03');
    v_os5 := pg_temp.f5c_orc(v_caio, c_caio, 'ORÇ-99675', 'Antena starlink', 1800);
    update public.service_orders set quote_status = 'draft' where id = v_os5;
    perform pg_temp.f5c_igual('12 com envio', public._retorno_tem_orcamento(v_k1, c_agora)::text, 'false');
    delete from public.orcamento_envios where service_order_id = v_os5;
    perform pg_temp.f5c_igual('12 sem envio', public._retorno_tem_orcamento(v_k1, c_agora)::text, 'true');
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 14. Os dados da nota: o CPF mascarado; A grava na ficha só o que está vazio ──
  begin
    v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
    v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
    v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg, 'com_sinal');
    update public.orcamento_aceites
       set dados_estado = 'lidos', dados_msg_id = pg_temp.f5c_msg(c_ana, 'Meu CPF é 529.982.247-25 e o CEP 88330-000', '2026-10-20 15:10-03')
     where id = v_ac;
    v_cartao := pg_temp.f5c_cartao(c_agora);
    perform pg_temp.f5c_igual('14 o item', (pg_temp.f5c_item(v_cartao, 1)).tipo_item, 'dados_nota');
    perform pg_temp.f5c_tem('14 a linha', pg_temp.f5c_texto(v_cartao),
      '1. Ana · 15:10 · respondeu ao pedido dos dados da nota · lido: CPF •••.•••.•••-25 (válido) · CEP 88330-000');
    perform pg_temp.f5c_tem('14 a letra', pg_temp.f5c_texto(v_cartao), '   *1 A* grava na ficha o que está vazio · rua, bairro e cidade: pela tela');
    if strpos(pg_temp.f5c_texto(v_cartao), '529.982') > 0 or strpos(pg_temp.f5c_texto(v_cartao), '52998') > 0 then
      raise exception '14: o CPF inteiro no cartão';
    end if;
    v_r := pg_temp.f5c_dito('{"comando": "escolher", "n": 1, "letra": "A", "resto": null}');
    perform pg_temp.f5c_igual('14 a frase', v_r ->> 'texto', 'Anotei *1 A*: gravo na ficha de Ana só o que está vazio. *sim <PIN>* faz.');
    perform pg_temp.f5c_tem('14 o rodapé', pg_temp.f5c_texto(v_cartao), '*sim <PIN>* faz o 1 (grava na ficha)');
    v_r := pg_temp.f5c_sim(v_cartao);
    perform pg_temp.f5c_tem('14 o aviso', v_r ->> 'aviso', 'Gravei na ficha de Ana: CPF e CEP.');
    if (select c.cpf_cnpj || '|' || c.postal_code from public.clients c where c.id = v_ana) is distinct from '529.982.247-25|88330-000'
       or (pg_temp.f5c_ac(v_ac)).dados_estado is distinct from 'gravados' then
      raise exception '14: a ficha ou o estado dos dados';
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 15. A carona com item da F5 (o teste mora aqui pela regra de ordem: a carona da P8 chama _orcamento_cartao_lista) ──
  for v_n in 1 .. 3 loop
    begin
      perform pg_temp.f5c_limpar();
      update public.retorno_config set carona_ligada = true, carona_em = null where id;
      if v_n = 1 then
        v_joao := pg_temp.f5c_cli('João Cartao F5 Teste', c_joao);
        v_os2 := pg_temp.f5c_orc(v_joao, c_joao, 'ORÇ-99672', 'Troca das baterias da lancha', 3200);
        perform pg_temp.f5c_passo(v_joao, c_joao, v_os2);
        v_esperado := 'Retorno: 1 esperando (João, lembrete do ORÇ-99672) · *retorno*';
      elsif v_n = 2 then
        v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
        v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
        perform pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg, 'detectado', null, 'Fechado!');
        v_esperado := 'Retorno: 1 esperando (Ana, aceite do ORÇ-99671) · *retorno*';
      else
        v_pedro := pg_temp.f5c_cli('Pedro Cartao F5 Teste', c_pedro);
        perform pg_temp.f5c_caso(v_pedro, c_pedro, 'cadê o meu motorhome?', '2026-10-20 08:00-03', 'cliente', 'vencida');
        v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
        v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
        perform pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg, 'detectado', null, 'Fechado!');
        v_esperado := 'Retorno: 2 esperando (Pedro, desde 08:00) · *retorno*';
      end if;
      v_r := public.retorno_carona(v_dono, c_agora);
      perform pg_temp.f5c_igual(format('15-%s a carona', v_n), v_r ->> 'texto', v_esperado);
      raise exception 'f5c_cenario' using errcode = 'P0001';
    exception when others then
      if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
        raise;
      end if;
    end;
  end loop;

  -- ── 21. O aviso do "Fechado" que não saiu: o texto pelo motivo, sem letra, e a marca nao_saiu_fechado_em ao sair da lista ──
  for v_n in 1 .. 4 loop
    begin
      v_ana := pg_temp.f5c_cli('Ana Cartao F5 Teste', c_ana);
      v_os := pg_temp.f5c_orc(v_ana, c_ana, 'ORÇ-99671', 'Instalação de energia solar', 9840);
      v_ac := pg_temp.f5c_aceite(v_ana, c_ana, v_os, c_msg, 'com_sinal', null, 'Pode fazer.', null,
        (case v_n when 3 then '{"saida_nao_saiu": "incerta", "saida_nao_saiu_tipo": "orc_fechado"}'
                  when 4 then '{"saida_nao_saiu": "pessoal", "saida_nao_saiu_tipo": "orc_dados_nota"}'
                  else '{"saida_nao_saiu": "numero_compartilhado", "saida_nao_saiu_tipo": "orc_fechado"}' end)::jsonb);
      v_joao := pg_temp.f5c_cli('João Cartao F5 Teste', c_joao);
      v_os2 := pg_temp.f5c_orc(v_joao, c_joao, 'ORÇ-99672', 'Troca das baterias da lancha', 3200);
      v_p := pg_temp.f5c_passo(v_joao, c_joao, v_os2);
      v_cartao := pg_temp.f5c_cartao(c_agora);
      v_i := pg_temp.f5c_item(v_cartao, 1);
      if v_i.tipo_item is distinct from 'aceite' or v_i.aceite_id is distinct from v_ac or v_i.opcoes::text is distinct from '[]' then
        raise exception '21-%: o item (%)', v_n, pg_temp.f5c_itens(v_cartao);
      end if;
      perform pg_temp.f5c_tem(format('21-%s o texto', v_n), pg_temp.f5c_texto(v_cartao), (case v_n
        when 3 then '   ORÇ-99671 aprovado, aguardando o sinal · o ''Fechado'' pode não ter saído: confira a conversa.'
        when 4 then '   ORÇ-99671 aprovado, aguardando o sinal · o pedido de dados da nota não saiu: o número está como pessoal; responda você.'
        else '   ORÇ-99671 aprovado, aguardando o sinal · o ''Fechado'' não saiu: o número é de outra pessoa com os mesmos 8 dígitos; responda você.' end));
      if v_n = 2 then
        -- De fora pelo *não 1*: o aviso também sai da lista.
        perform pg_temp.f5c_dito('{"comando": "tirar", "ns": [1]}');
      elsif v_n = 3 then
        -- De fora pelo *só 2*: o aviso volta uma vez só.
        perform pg_temp.f5c_dito('{"comando": "so", "ns": [2]}');
      end if;
      v_r := pg_temp.f5c_sim(v_cartao);
      if (pg_temp.f5c_ac(v_ac)).resultado ->> 'nao_saiu_fechado_em' is null then
        raise exception '21-%: sem a marca nao_saiu_fechado_em', v_n;
      end if;
      perform pg_temp.f5c_igual(format('21-%s o aceite', v_n), (pg_temp.f5c_ac(v_ac)).estado, 'com_sinal');
      if strpos(pg_temp.f5c_lista(c_sim + interval '1 hour'), v_ac::text) > 0 then
        raise exception '21-%: o aviso voltou à lista', v_n;
      end if;
      raise exception 'f5c_cenario' using errcode = 'P0001';
    exception when others then
      if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
        raise;
      end if;
    end;
  end loop;

  -- ── 20. As funções: as novas SECURITY DEFINER com search_path e fechadas a anon e authenticated; as geradas com os grants de
  --        antes; a C-LISTA com as colunas do contrato ──
  foreach v in array c_novas loop
    for v_rec in
      select p.oid, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = v
    loop
      v_n_fun := v_n_fun + 1;
      if v_rec.prosecdef is not true or not exists (select 1 from unnest(v_rec.config) o where o ~ '^search_path=') then
        raise exception '20a: % não é SECURITY DEFINER com search_path', v_rec.nome;
      end if;
      if has_function_privilege('anon', v_rec.oid, 'execute') or has_function_privilege('authenticated', v_rec.oid, 'execute') then
        raise exception '20b: % aberta a anon ou authenticated', v_rec.nome;
      end if;
    end loop;
  end loop;
  if v_n_fun is distinct from 18 then
    raise exception '20c: achei % das 18 funções novas', v_n_fun;
  end if;
  for v_rec in
    select x.f, x.servico, p.oid
      from (values ('public.retorno_cartao_abrir(text, timestamptz, uuid)', true),
                   ('public._retorno_cartao_texto(uuid, text)', false),
                   ('public._retorno_item_conferir(uuid, timestamptz, boolean)', false),
                   ('public._retorno_decidir_letra(public.retorno_cartao_itens, jsonb, uuid, timestamptz)', false),
                   ('public.retorno_decidir_dito(jsonb, uuid, timestamptz)', true),
                   ('public.retorno_cartao_executar(uuid, uuid, timestamptz)', true),
                   ('public.retorno_ver_caso(integer, uuid, timestamptz)', true),
                   ('public.retorno_destino_do_item(integer, uuid, timestamptz)', true),
                   ('public._retorno_dito_pessoal(integer, uuid, timestamptz)', false),
                   ('public._retorno_dito_resolvido(integer, uuid, timestamptz)', false),
                   ('public.retorno_item_enviado(uuid, boolean, text, timestamptz)', true),
                   ('public._retorno_tem_orcamento(uuid, timestamptz)', false)) as x(f, servico)
      left join pg_proc p on p.oid = to_regprocedure(x.f)
  loop
    if v_rec.oid is null then
      raise exception '20d: a gerada % não existe', v_rec.f;
    end if;
    if has_function_privilege('anon', v_rec.oid, 'execute') or has_function_privilege('authenticated', v_rec.oid, 'execute')
       or (v_rec.servico and not has_function_privilege('service_role', v_rec.oid, 'execute')) then
      raise exception '20d: os grants de %', v_rec.f;
    end if;
  end loop;
  if pg_get_function_result('public._orcamento_cartao_lista(timestamptz, integer)'::regprocedure)
     is distinct from 'TABLE(ordem integer, tipo text, abertura_id uuid, aceite_id uuid, passo_id uuid, prioridade smallint, rotulo text)' then
    raise exception '20e: as colunas da C-LISTA (%)', pg_get_function_result('public._orcamento_cartao_lista(timestamptz, integer)'::regprocedure);
  end if;

  raise exception 'retorno_f5_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f5_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f5_cartao', true, '{}');
end
$cartao$;

select arquivo, ok, numeros from _bancada order by em;
rollback;

-- Retorno rápido ao cliente, F2 (P7A): a lista. É o piso do Plano B: *retorno*, *ver N* e *pessoal N* funcionando sem
-- pendência, sem letra e sem modelo.
--
-- retorno_cartao_abrir mostra quem espera (até cartao_max_itens casos), grava um cartão em estado 'lista' e NÃO cria
-- pendência. A P7B substitui _retorno_item_montar, _retorno_cartao_texto e retorno_cartao_abrir por create or replace; o resto
-- continua valendo.
--
-- O texto do cartão tem palavras do cliente e fica só em retorno_cartoes e no WhatsApp do dono. O "historico" devolvido só
-- leva rótulos e contagens.
--
-- Ninguém olha o futuro: toda leitura para em p_agora.
--
-- Cartão órfão: retorno_cartao_vivo fecha o cartão vivo cuja pendência já acabou. 'approved' não é órfão: é o instante
-- entre o PIN certo e o fim da execução, e fechar ali mataria o cartão que o dono acabou de aprovar.
--
-- Reverter: drop das funções abaixo. retorno_dito passa a responder erro, e a camada segue como sempre.

create or replace function public.retorno_cartao_vivo(p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_c public.retorno_cartoes;
  v_status text;
  v_itens jsonb;
  v_letras jsonb;
begin
  select c.* into v_c from public.retorno_cartoes c where c.estado = 'vivo' for update;
  if found and v_c.pendencia_id is not null then
    select p.status into v_status from public.ai_operator_pending_actions p where p.id = v_c.pendencia_id;
    if v_status in ('rejected', 'expired', 'executed', 'failed') then
      update public.retorno_cartoes c
         set estado = case when v_status = 'expired' then 'expirou' else 'decidido' end,
             decidido_em = case when v_status = 'expired' then c.decidido_em else coalesce(c.decidido_em, v_agora) end,
             decidido_por = case when v_status = 'rejected' then coalesce(c.decidido_por, 'nao')
                                 when v_status = 'expired' then c.decidido_por
                                 else coalesce(c.decidido_por, 'sim_pin') end
       where c.id = v_c.id;
      update public.retorno_cartao_itens i set estado = 'fora' where i.cartao_id = v_c.id and i.estado = 'vivo';
      v_c.id := null;
    end if;
  end if;

  if v_c.id is null then
    select c.* into v_c
      from public.retorno_cartoes c
     where c.estado = 'lista'
       and c.criado_em <= v_agora
       and c.criado_em > v_agora - interval '24 hours'
       and not coalesce((c.dados ->> 'so_aviso')::boolean, false)
     order by c.criado_em desc, c.id
     limit 1;
    if not found then
      return null;
    end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('n', i.n, 'abertura_id', i.abertura_id, 'tipo_item', i.tipo_item) order by i.n), '[]'::jsonb),
         coalesce(jsonb_object_agg(i.n::text,
                    (select coalesce(jsonb_agg(o ->> 'letra'), '[]'::jsonb) from jsonb_array_elements(i.opcoes) o)), '{}'::jsonb)
    into v_itens, v_letras
    from public.retorno_cartao_itens i
   where i.cartao_id = v_c.id and i.estado = 'vivo';

  return jsonb_build_object('id', v_c.id, 'estado', v_c.estado, 'pendencia_id', v_c.pendencia_id, 'itens', v_itens,
                            'letras', v_letras, 'expira_em', v_c.expira_em);
end;
$$;

comment on function public.retorno_cartao_vivo(timestamptz) is
  'Retorno F2 (C-VIVO): o cartão vivo ou, sem ele, a lista mais recente com menos de 24 h. Antes de responder fecha o cartão cuja pendência acabou (rejected, expired, executed, failed); approved não é órfão.';

revoke all on function public.retorno_cartao_vivo(timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_cartao_vivo(timestamptz) to service_role;

create or replace function public._retorno_cartao_casos(p_agora timestamptz, p_limite integer)
returns table (abertura_id uuid, prioridade smallint)
language sql
stable
security definer
set search_path = public
as $$
  with vivos as (
    select a.id, a.aberta_em, a.prometido_ate,
           (case
              when a.estado = 'vencida' or a.topo_dia <= (p_agora at time zone 'America/Sao_Paulo')::date then 1
              when a.nivel = 'passagem' then 2
              when a.papel = 'numero_novo' then 4
              when a.prometido_ate is not null then 5
              else 6
            end)::smallint as prioridade
      from public.retorno_aberturas a
     where a.estado in ('aberta', 'vencida')
       and a.nivel in ('recibo', 'passagem')
       and a.cumprida_em is null
       and a.papel in ('cliente', 'cliente_ambiguo', 'numero_novo')
       and a.aberta_em <= p_agora
       and not exists (select 1
                         from public.retorno_cartao_itens i
                         join public.retorno_cartoes c on c.id = i.cartao_id
                        where i.abertura_id = a.id and i.estado = 'vivo' and c.estado = 'vivo')
  )
  select v.id, v.prioridade
    from vivos v
   order by v.prioridade, case when v.prioridade = 5 then v.prometido_ate end, v.aberta_em, v.id
   limit p_limite;
$$;

comment on function public._retorno_cartao_casos(timestamptz, integer) is
  'Retorno F2 (P7A): quem entra no cartão, em ordem: venceu, passagem, reservada ao aceite (F5), pedido novo, com promessa, o resto. Nunca parceiro, fornecedor, contato conhecido, vendedor ou robô. Fora os itens vivos de cartão vivo: os de lista não contam, senão o 2º *retorno* diria que não há ninguém.';

revoke all on function public._retorno_cartao_casos(timestamptz, integer) from public, anon, authenticated;

-- {prazo} da linha do cartão. "Prometi" só com a promessa ouvida: a mesma regra do "ouviu" do resumo da F1.
create or replace function public._retorno_prazo_curto(p_abertura uuid, p_agora timestamptz)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_primeiras constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'saudacao_numero_novo'];
  c_dias constant text[] := array['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
  v_ab public.retorno_aberturas;
  v_prazo timestamptz;
  v_hoje date := (p_agora at time zone c_fuso)::date;
  v_dia date;
  v_hora text;
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  if not found then
    return 'sem promessa';
  end if;
  v_prazo := coalesce(v_ab.segundo_prazo, v_ab.prometido_ate);
  if v_prazo is null or not exists (
       select 1 from public.retorno_saidas s
        where s.abertura_id = p_abertura
          and s.tipo = any (c_primeiras)
          and s.estado in ('enviada', 'incerta')
          and s.decidida_em <= p_agora) then
    return 'sem promessa';
  end if;

  v_dia := (v_prazo at time zone c_fuso)::date;
  if v_prazo < p_agora or v_ab.estado = 'vencida' then
    return case when v_dia = v_hoje then 'venceu hoje'
                when v_dia = v_hoje - 1 then 'venceu ontem'
                else 'venceu ' || to_char(v_dia, 'DD/MM') end;
  end if;
  v_hora := public._retorno_hora((v_prazo at time zone c_fuso)::time);
  return case when v_dia = v_hoje then 'prometi até ' || v_hora
              when v_dia = v_hoje + 1 then 'prometi até amanhã ' || v_hora
              else 'prometi até ' || c_dias[extract(isodow from v_dia)::integer] || ' ' || v_hora end;
end;
$$;

comment on function public._retorno_prazo_curto(uuid, timestamptz) is
  'Retorno F2 (P7A): o prazo na linha do cartão: prometi até 14h, prometi até amanhã 10h, prometi até seg 10h, venceu ontem, sem promessa. "Prometi" só com recibo enviado ou incerto.';

revoke all on function public._retorno_prazo_curto(uuid, timestamptz) from public, anon, authenticated;

-- O texto de uma mensagem para a linha do cartão: sem quebra de linha, cortado na palavra.
create or replace function public._retorno_trecho(p_corpo text, p_tipo text, p_pendente boolean, p_max integer)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v text := btrim(regexp_replace(coalesce(p_corpo, ''), '\s+', ' ', 'g'));
  v_corte text;
begin
  if coalesce(p_pendente, false) or lower(v) = '[audio]' or (p_tipo = 'audio' and v = '') then
    return '(áudio ainda sem transcrição)';
  end if;
  if v = '' or v ~ '^\[[^]]*\]$' then
    return case p_tipo
      when 'image' then '(foto)'
      when 'video' then '(vídeo)'
      when 'document' then '(documento)'
      when 'audio' then '(áudio ainda sem transcrição)'
      else '(sem texto)'
    end;
  end if;
  if char_length(v) <= p_max then
    return '''' || v || '''';
  end if;
  v_corte := left(v, p_max);
  if substr(v, p_max + 1, 1) <> ' ' and v_corte ~ ' ' then
    v_corte := regexp_replace(v_corte, '\s+\S*$', '');
  end if;
  return '''' || rtrim(v_corte) || '…''';
end;
$$;

comment on function public._retorno_trecho(text, text, boolean, integer) is
  'Retorno F2 (P7A): o trecho da mensagem do cliente para o dono: entre aspas simples, quebras viradas em espaço, cortado na palavra. Mídia e áudio sem transcrição viram marcação entre parênteses.';

revoke all on function public._retorno_trecho(text, text, boolean, integer) from public, anon, authenticated;

-- O {pedido}: a 1ª mensagem do caso que pede resposta, até p_agora.
create or replace function public._retorno_pedido_do_caso(p_abertura uuid, p_agora timestamptz)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select public._retorno_trecho(w.body, w.message_type, m.audio_pendente, 140)
       from public.retorno_mensagens m
       join public.whatsapp_messages w on w.id = m.whatsapp_message_id
      where m.abertura_id = p_abertura and m.pede_resposta and m.recebida_em <= p_agora
      order by m.recebida_em, m.whatsapp_message_id
      limit 1),
    '(sem texto)');
$$;

comment on function public._retorno_pedido_do_caso(uuid, timestamptz) is
  'Retorno F2 (P7A): o trecho da 1ª mensagem do caso que pede resposta, gravada até p_agora.';

revoke all on function public._retorno_pedido_do_caso(uuid, timestamptz) from public, anon, authenticated;

-- Quantas automáticas do retorno a chave já ouviu no dia local de p_agora.
create or replace function public._retorno_automaticas_hoje(p_chave text, p_agora timestamptz)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
    from public.retorno_saidas s
   where s.chave = p_chave
     and s.emissor = 'retorno'
     and s.estado in ('enviada', 'incerta')
     and s.decidida_em <= p_agora
     and s.decidida_em >= ((p_agora at time zone 'America/Sao_Paulo')::date)::timestamp at time zone 'America/Sao_Paulo';
$$;

comment on function public._retorno_automaticas_hoje(text, timestamptz) is
  'Retorno F2 (P7A): saídas automáticas do retorno enviadas ou incertas à chave no dia local de p_agora.';

revoke all on function public._retorno_automaticas_hoje(text, timestamptz) from public, anon, authenticated;

-- Versão da lista: sempre 'livre', sem modelo e sem opção. A P7B substitui.
create or replace function public._retorno_item_montar(p_abertura uuid, p_n smallint, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ab public.retorno_aberturas;
  v_linha text;
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  v_linha := format('%s. %s · %s · %s · %s', p_n, public._retorno_rotulo(p_abertura, p_agora),
                    to_char(v_ab.aberta_em at time zone 'America/Sao_Paulo', 'HH24:MI'),
                    public._retorno_prazo_curto(p_abertura, p_agora),
                    public._retorno_pedido_do_caso(p_abertura, p_agora));
  return jsonb_build_object(
    'tipo_item', 'livre', 'modelo_tipo', null, 'service_order_id', null, 'texto_mostrado', null,
    'opcoes', '[]'::jsonb, 'fatos', '{}'::jsonb, 'linhas', jsonb_build_array(v_linha),
    'hash', md5(concat_ws('|', v_ab.phone_normalized, null, null, '{}',
                          public._retorno_automaticas_hoje(v_ab.chave, p_agora))));
end;
$$;

comment on function public._retorno_item_montar(uuid, smallint, timestamptz) is
  'Retorno F2 (P7A): monta um item da lista: sempre livre, sem modelo e sem opção. A P7B substitui.';

revoke all on function public._retorno_item_montar(uuid, smallint, timestamptz) from public, anon, authenticated;

-- O texto do cartão, regravado a cada mudança. As linhas de cada item ficam em dados.linhas; só as dos itens vivos entram.
create or replace function public._retorno_cartao_texto(p_cartao uuid, p_cabeca text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_c public.retorno_cartoes;
  v_vivos integer;
  v_cabeca text;
  v_corpo text;
begin
  select * into v_c from public.retorno_cartoes c where c.id = p_cartao;
  select count(*) into v_vivos from public.retorno_cartao_itens i where i.cartao_id = p_cartao and i.estado = 'vivo';

  v_cabeca := coalesce(p_cabeca, format('Retorno · %s esperando', v_vivos + v_c.mais));

  select string_agg(l.linha, E'\n' order by i.n, l.ord)
    into v_corpo
    from public.retorno_cartao_itens i
    cross join lateral jsonb_array_elements_text(coalesce(v_c.dados -> 'linhas' -> i.n::text, '[]'::jsonb))
         with ordinality as l(linha, ord)
   where i.cartao_id = p_cartao and i.estado = 'vivo';

  return concat_ws(E'\n', v_cabeca, v_corpo,
                   case when v_c.mais > 0 then format('e mais %s: *retorno*', v_c.mais) end,
                   v_c.dados ->> 'rodape');
end;
$$;

comment on function public._retorno_cartao_texto(uuid, text) is
  'Retorno F2 (P7A): cabeçalho, linhas dos itens vivos, "e mais k" e rodapé. Sem cabeçalho dado, usa "Retorno · n esperando".';

revoke all on function public._retorno_cartao_texto(uuid, text) from public, anon, authenticated;

-- Versão da lista: só puxar, sem pendência. A P7B substitui.
create or replace function public.retorno_cartao_abrir(p_gatilho text, p_agora timestamptz default now(), p_aviso uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_total integer;
  v_cartao uuid;
  v_n smallint := 0;
  v_caso record;
  v_item jsonb;
  v_linhas jsonb := '{}'::jsonb;
  v_hashes text := '';
  v_rotulos text[] := '{}';
  v_mais integer;
  v_texto text;
begin
  if v_cfg.id is null or v_cfg.modo = 'desligado' or p_gatilho is distinct from 'puxar' then
    return jsonb_build_object('acao', 'vazio');
  end if;

  select count(*) into v_total from public._retorno_cartao_casos(v_agora, null);
  if v_total = 0 then
    return jsonb_build_object('acao', 'vazio', 'texto', 'Ninguém esperando agora.');
  end if;
  v_mais := greatest(0, v_total - v_cfg.cartao_max_itens);

  insert into public.retorno_cartoes (gatilho, dia, estado, hash, texto, mais, criado_em, expira_em, dados)
  values (p_gatilho, (v_agora at time zone c_fuso)::date, 'lista', '', '', v_mais, v_agora, v_agora + v_cfg.cartao_validade,
          jsonb_build_object('rodape', '*ver 1* · *resolvido 1* · *pessoal 1*'))
  returning id into v_cartao;

  for v_caso in select c.abertura_id from public._retorno_cartao_casos(v_agora, v_cfg.cartao_max_itens) c loop
    v_n := v_n + 1;
    v_item := public._retorno_item_montar(v_caso.abertura_id, v_n, v_agora);
    insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, modelo_tipo, service_order_id, texto_mostrado,
                                             opcoes, fatos, hash)
    values (v_cartao, v_n, v_caso.abertura_id, v_item ->> 'tipo_item', v_item ->> 'modelo_tipo',
            (v_item ->> 'service_order_id')::uuid, v_item ->> 'texto_mostrado', v_item -> 'opcoes', v_item -> 'fatos',
            v_item ->> 'hash');
    v_linhas := v_linhas || jsonb_build_object(v_n::text, v_item -> 'linhas');
    v_hashes := v_hashes || (v_item ->> 'hash');
    v_rotulos := v_rotulos || format('%s = %s', v_n, public._retorno_rotulo(v_caso.abertura_id, v_agora));
  end loop;

  update public.retorno_cartoes c
     set hash = md5(v_hashes), dados = c.dados || jsonb_build_object('linhas', v_linhas)
   where c.id = v_cartao;
  v_texto := public._retorno_cartao_texto(v_cartao, null);
  update public.retorno_cartoes c set texto = v_texto where c.id = v_cartao;

  return jsonb_build_object('acao', 'lista', 'cartao_id', v_cartao, 'texto', v_texto,
    'historico', jsonb_build_object('user', '(retorno)',
      'assistant', format('Mostrei a lista do retorno: %s caso(s). %s. O que os clientes escreveram fica fora desta conversa.',
                          v_total, array_to_string(v_rotulos, ', '))));
end;
$$;

comment on function public.retorno_cartao_abrir(text, timestamptz, uuid) is
  'Retorno F2 (C-CARTAO, versão da lista): grava um cartão lista com até cartao_max_itens casos, sem pendência. {"acao": "lista"|"vazio", "cartao_id"?, "texto"?, "historico"?}. O historico só leva rótulos e contagem.';

revoke all on function public.retorno_cartao_abrir(text, timestamptz, uuid) from public, anon, authenticated;
grant execute on function public.retorno_cartao_abrir(text, timestamptz, uuid) to service_role;

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

  perform public._retorno_toque('ver', v_cartao, v_item.abertura_id, v_agora);

  return jsonb_build_object('ok', true,
    'texto', concat_ws(E'\n', format('%s · %s', public._retorno_rotulo(v_item.abertura_id, v_agora),
                                     public._retorno_prazo_curto(v_item.abertura_id, v_agora)),
                       v_recebidas),
    'historico', jsonb_build_object('user', format('(ver %s)', p_n),
                                    'assistant', format('(mostrei o caso %s ao dono)', p_n)));
end;
$$;

comment on function public.retorno_ver_caso(integer, uuid, timestamptz) is
  'Retorno F2 (P7A): *ver N*: até 5 últimas recebidas do caso e o que se sabe. O texto vai ao dono; o historico não leva texto do cliente.';

revoke all on function public.retorno_ver_caso(integer, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_ver_caso(integer, uuid, timestamptz) to service_role;

-- Retorno rápido ao cliente, F2 (P5.2 e P6): quando o modelo cabe, e os textos.
--
-- _retorno_modelo_do_caso decide se um caso pode ser respondido por um modelo com fato. A 1ª regra que falha devolve null com
-- o motivo. Nunca responde ambíguo, passagem, pedido misturado, nem cliente com duas OS vivas.
--
-- sinais.pedido fica fora das regras, de propósito: _retorno_sinais liga essa marca em toda frase com "?", e "como tá o
-- motorhome?" é exatamente o que o modelo responde. As regras 3, 4 e 6 cobrem o caso real ("como tá? e preciso trocar a
-- bateria" não fecha com modelo).
--
-- A intenção não muda o nível do caso nem a triagem da F1: só escolhe a variante e monta o item do cartão.
--
-- _retorno_texto da F1 não muda. As variantes novas ficam em _retorno_texto_f2, e só valem com retorno_config.variantes_ligadas
-- (P10): com a chave desligada, o que sai ao cliente é o texto da F1.
--
-- "vou confirmar" é variante de recibo, não modelo com tipo: não afirma fato nenhum, e não dispensa a hora.
--
-- Reverter: drop das funções abaixo; _retorno_cartao_casos volta à versão da 100150.

-- A intenção de uma frase, já no texto de busca. p_liberado dispensa a palavra do bem na retirada.
create or replace function public._retorno_intencao_da_frase(p_busca text, p_sinais jsonb, p_liberado boolean)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  s jsonb := coalesce(p_sinais, '{}'::jsonb);
  b text := coalesce(p_busca, '');
begin
  if b ~ '\y(retirar|buscar|pegar)\y' and (coalesce((s ->> 'bem')::boolean, false) or p_liberado) then
    return 'retirada';
  end if;
  if b ~ '\y(quando fica pronto|quando termina|quando vai ficar|qual a previsao|qual o prazo)\y' then
    return 'quando_pronto';
  end if;
  if b ~ '\y(peca|pecas|material|materiais)\y' and b ~ '\y(chegou|chegaram|ja veio|ja vieram|chega|chegando)\y' then
    return 'peca';
  end if;
  if b ~ '\y(como (esta|ta|anda|ficou)|como que (esta|ta)|ja ficou|ficou pronto|ta pronto|esta pronto|terminou|ja terminaram|novidade|novidades|tem previsao|andamento)\y' then
    return 'status';
  end if;
  if b ~ '\y(aproveita|aproveitando|servico extra|mais um servico|ve tambem|tambem ve)\y' then
    return 'adicional';
  end if;
  if coalesce((s ->> 'pede_preco')::boolean, false)
     or (coalesce((s ->> 'servico')::boolean, false) and coalesce((s ->> 'pedido')::boolean, false)) then
    return 'orcamento';
  end if;
  return null;
end;
$$;

comment on function public._retorno_intencao_da_frase(text, jsonb, boolean) is
  'Retorno F2 (P6.1): a 1ª intenção que casa, nesta ordem: retirada, quando_pronto, peca, status, adicional, orcamento.';

revoke all on function public._retorno_intencao_da_frase(text, jsonb, boolean) from public, anon, authenticated;

-- A OS do contato tem *libera* válido? Falha fecha: erro = não.
create or replace function public._retorno_tem_liberado(p_fone text, p_agora timestamptz)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return exists (select 1
                   from jsonb_array_elements(public.retorno_fatos_do_contato(p_fone, p_agora) -> 'os') o
                  where o -> 'fatos' -> 'liberado' <> 'null'::jsonb);
exception when others then
  return false;
end;
$$;

revoke all on function public._retorno_tem_liberado(text, timestamptz) from public, anon, authenticated;

create or replace function public._retorno_intencao_do_caso(p_abertura uuid, p_agora timestamptz)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_ordem constant text[] := array['retirada', 'quando_pronto', 'peca', 'status', 'adicional', 'orcamento'];
  v_ab public.retorno_aberturas;
  v_lib boolean;
  v_intencoes text[];
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  if not found or v_ab.nivel <> 'recibo' then
    return null;
  end if;
  v_lib := public._retorno_tem_liberado(v_ab.phone_normalized, p_agora);
  select array_agg(public._retorno_intencao_da_frase(public._retorno_busca(w.body), public._retorno_sinais(w.body), v_lib))
    into v_intencoes
    from public.retorno_mensagens m
    join public.whatsapp_messages w on w.id = m.whatsapp_message_id
   where m.abertura_id = p_abertura and m.pede_resposta and m.recebida_em <= p_agora;
  return (select o.i from unnest(c_ordem) with ordinality o(i, ord) where o.i = any (coalesce(v_intencoes, '{}')) order by o.ord limit 1);
end;
$$;

comment on function public._retorno_intencao_do_caso(uuid, timestamptz) is
  'Retorno F2 (P6.1): status, peca, retirada, quando_pronto, adicional, orcamento ou null, sobre as mensagens do caso que pedem resposta, gravadas até p_agora. Passagem dá null. Não muda a triagem da F1.';

revoke all on function public._retorno_intencao_do_caso(uuid, timestamptz) from public, anon, authenticated;

create or replace function public._retorno_tem_orcamento(p_abertura uuid, p_agora timestamptz)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.retorno_aberturas a
      join public.service_orders so on so.client_id = a.client_id
     where a.id = p_abertura
       and so.status = 'draft'
       and so.quote_status = 'draft'
       and so.merged_into_id is null
       and so.created_at >= a.aberta_em - interval '14 days'
       and so.created_at <= p_agora);
$$;

comment on function public._retorno_tem_orcamento(uuid, timestamptz) is
  'Retorno F2 (P6.1): há rascunho de orçamento do cliente do caso, criado a partir de 14 dias antes da abertura e até p_agora. É a marca tem_proposta do validador.';

revoke all on function public._retorno_tem_orcamento(uuid, timestamptz) from public, anon, authenticated;

create or replace function public._retorno_modelo_do_caso(p_abertura uuid, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_barrar constant text[] := array['reclamacao', 'risco', 'quer_dono', 'lgpd', 'pede_preco', 'servico'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_ab public.retorno_aberturas;
  v_intencao text;
  v_lib boolean;
  v_fatos jsonb;
  v_os jsonb;
  v_f jsonb;
  v_modelo text;
  v_fato jsonb;
  v_familia text[];
  r record;
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  if not found or v_ab.papel <> 'cliente' or v_ab.client_id is null then
    return jsonb_build_object('modelo', null, 'motivo', 'papel');
  end if;
  if v_ab.nivel <> 'recibo' then
    return jsonb_build_object('modelo', null, 'motivo', 'passagem');
  end if;

  v_lib := public._retorno_tem_liberado(v_ab.phone_normalized, v_agora);

  -- Regras 3, 4 e 6, mensagem a mensagem.
  v_intencao := public._retorno_intencao_do_caso(p_abertura, v_agora);
  for r in
    select public._retorno_busca(w.body) as busca, public._retorno_sinais(w.body) as sinais
      from public.retorno_mensagens m
      join public.whatsapp_messages w on w.id = m.whatsapp_message_id
     where m.abertura_id = p_abertura and m.recebida_em <= v_agora
  loop
    if exists (select 1 from unnest(c_barrar) c where coalesce((r.sinais ->> c)::boolean, false)) then
      return jsonb_build_object('modelo', null, 'motivo', 'sinal');
    end if;
    if r.busca ~ '\y(preciso|precisava|quero|queria|gostaria|orcar|orcamento)\y'
       or public._retorno_intencao_da_frase(r.busca, r.sinais, v_lib) = 'adicional' then
      return jsonb_build_object('modelo', null, 'motivo', 'outro_pedido');
    end if;
  end loop;

  if v_intencao is null or v_intencao not in ('status', 'peca', 'retirada') then
    return jsonb_build_object('modelo', null, 'motivo', 'sem_intencao');
  end if;

  if exists (
    select 1
      from public.retorno_mensagens m
      join public.whatsapp_messages w on w.id = m.whatsapp_message_id
     where m.abertura_id = p_abertura and m.pede_resposta and m.recebida_em <= v_agora
       and not coalesce((public._retorno_sinais(w.body) ->> 'saudacao')::boolean, false)
       and public._retorno_intencao_da_frase(public._retorno_busca(w.body), public._retorno_sinais(w.body), v_lib)
           is distinct from v_intencao) then
    return jsonb_build_object('modelo', null, 'motivo', 'misturado');
  end if;

  begin
    v_fatos := public.retorno_fatos_do_contato(v_ab.phone_normalized, v_agora);
  exception when others then
    return jsonb_build_object('modelo', null, 'motivo', 'sem_fato');
  end;
  if jsonb_array_length(v_fatos -> 'os') = 0 then
    return jsonb_build_object('modelo', null, 'motivo', 'os_0');
  end if;
  if jsonb_array_length(v_fatos -> 'os') > 1 then
    return jsonb_build_object('modelo', null, 'motivo', 'os_varias');
  end if;
  v_os := v_fatos -> 'os' -> 0;
  v_f := v_os -> 'fatos';

  if v_intencao = 'status' and v_f -> 'pronto' <> 'null'::jsonb then
    v_modelo := 'modelo_pronto';
    v_fato := v_f -> 'pronto';
  elsif v_intencao = 'status' and v_f -> 'em_servico' <> 'null'::jsonb then
    v_modelo := 'modelo_em_servico';
    v_fato := v_f -> 'em_servico';
  elsif v_intencao in ('status', 'peca') and v_f -> 'peca_chegou' <> 'null'::jsonb
        and not (v_f -> 'peca_chegou' ->> 'faltam_outras')::boolean then
    v_modelo := 'modelo_peca_chegou';
    v_fato := v_f -> 'peca_chegou';
  elsif v_intencao in ('status', 'peca') and v_f -> 'aguarda_peca' <> 'null'::jsonb then
    v_modelo := 'modelo_aguarda_peca';
    -- só o que o texto ao cliente pode usar: a previsão nunca entra
    v_fato := jsonb_build_object('valor', true, 'linhas', jsonb_array_length(v_f -> 'aguarda_peca' -> 'linhas'));
  elsif v_intencao = 'retirada' and v_f -> 'liberado' <> 'null'::jsonb then
    v_modelo := 'modelo_liberado';
    v_fato := v_f -> 'liberado';
  else
    return jsonb_build_object('modelo', null, 'motivo', 'sem_fato', 'os_id', v_os ->> 'id');
  end if;

  v_familia := case v_modelo
    when 'modelo_peca_chegou' then array['material_chegou', 'nova_data']
    when 'modelo_pronto' then array['pronto', 'pronto_lembrete']
    when 'modelo_aguarda_peca' then array['pode_atrasar']
    else '{}'::text[] end;
  if exists (select 1 from public.agenda_cliente_mensagens a
              where a.service_order_id = (v_os ->> 'id')::uuid
                and a.tipo = any (v_familia)
                and a.enviada_em <= v_agora
                and a.enviada_em > v_agora - v_cfg.modelo_repete_fato) then
    return jsonb_build_object('modelo', null, 'motivo', 'agenda_ja_disse', 'os_id', v_os ->> 'id');
  end if;

  if exists (select 1 from public.retorno_saidas s
              where s.chave = v_ab.chave
                and s.tipo = v_modelo
                and s.estado in ('enviada', 'incerta')
                and s.decidida_em <= v_agora
                and s.decidida_em > v_agora - v_cfg.modelo_repete_fato) then
    return jsonb_build_object('modelo', null, 'motivo', 'repete', 'os_id', v_os ->> 'id');
  end if;

  return jsonb_build_object('modelo', v_modelo, 'os_id', v_os ->> 'id', 'fato', v_fato, 'intencao', v_intencao, 'motivo', null);
end;
$$;

comment on function public._retorno_modelo_do_caso(uuid, timestamptz) is
  'Retorno F2 (P5.2): {"modelo", "os_id", "fato", "intencao", "motivo"}. A 1ª regra que falha dá modelo nulo: papel, passagem, sinal, outro_pedido, sem_intencao, misturado, os_0, os_varias, sem_fato, agenda_ja_disse, repete.';

revoke all on function public._retorno_modelo_do_caso(uuid, timestamptz) from public, anon, authenticated;

-- A ordem da spec muda só a prioridade 4: pedido novo também é quem pede orçamento.
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
              when a.papel = 'numero_novo' or public._retorno_intencao_do_caso(a.id, p_agora) = 'orcamento' then 4
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

revoke all on function public._retorno_cartao_casos(timestamptz, integer) from public, anon, authenticated;

create or replace function public._retorno_corpo_do_modelo(p_tipo text, p_dados jsonb)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  d jsonb := case when jsonb_typeof(p_dados) = 'object' then p_dados else '{}'::jsonb end;
  v_no_bem text := nullif(btrim(d ->> 'no_bem'), '');
  v_dia text := nullif(btrim(d ->> 'dia_peca'), '');
begin
  case p_tipo
    when 'modelo_aguarda_peca' then
      if v_no_bem is null then raise exception 'modelo: falta no_bem' using errcode = '22023'; end if;
      return format('o serviço %s está aguardando a chegada de uma peça. %s', v_no_bem,
                    case when coalesce((d ->> 'te_aviso')::boolean, false) then 'Assim que ela chegar, aviso você por aqui.'
                         else 'Assim que ela chegar, o Gustavo avisa você.' end);
    when 'modelo_peca_chegou' then
      if v_dia is null or v_dia !~ '^[0-9]{2}/[0-9]{2}$' then raise exception 'modelo: falta dia_peca' using errcode = '22023'; end if;
      return case when d ->> 'intencao' = 'status'
                  then format('a peça do serviço chegou no dia %s. Agora o Gustavo vai marcar o dia do serviço.', v_dia)
                  else format('a peça chegou sim, no dia %s. Agora o Gustavo vai marcar o dia do serviço.', v_dia) end;
    when 'modelo_pronto' then
      if v_no_bem is null then raise exception 'modelo: falta no_bem' using errcode = '22023'; end if;
      return format('o serviço %s está pronto. Qual o melhor dia para você buscar? O Gustavo combina o horário por aqui.', v_no_bem);
    when 'modelo_em_servico' then
      if v_no_bem is null then raise exception 'modelo: falta no_bem' using errcode = '22023'; end if;
      return format('o serviço %s está em andamento hoje. O Gustavo passa as novidades por aqui.', v_no_bem);
    when 'modelo_liberado' then
      return 'pode sim: o serviço está liberado para retirada. É só combinar o horário com o Gustavo por aqui.';
    when 'modelo_retirada_nao' then
      return 'ainda não dá para retirar, porque o serviço não terminou. O Gustavo chama você para combinar.';
    else
      raise exception 'modelo: tipo desconhecido' using errcode = '22023';
  end case;
end;
$$;

comment on function public._retorno_corpo_do_modelo(text, jsonb) is
  'Retorno F2 (P6): o corpo M01 a M06, começando em minúscula: a abertura decide a maiúscula. Falta de dado = 22023.';

revoke all on function public._retorno_corpo_do_modelo(text, jsonb) from public, anon, authenticated;

create or replace function public._retorno_abertura_do_modelo(p_variante text, p_dados jsonb)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_corpo text := nullif(btrim(p_dados ->> 'corpo'), '');
  v_nome text := nullif(btrim(p_dados ->> 'nome'), '');
  v_maior text;
begin
  if v_corpo is null then
    raise exception 'abertura: falta o corpo' using errcode = '22023';
  end if;
  v_maior := upper(left(v_corpo, 1)) || substr(v_corpo, 2);
  if p_variante in ('padrao', 'padrao_apresentacao', 'apos_recibo') and v_nome is null then
    raise exception 'abertura: falta o nome' using errcode = '22023';
  end if;
  return case p_variante
    when 'padrao' then format('Oi, %s! %s', v_nome, v_maior)
    when 'padrao_apresentacao' then format('Oi, %s! Aqui é a Claudia, assistente virtual da HBR. %s', v_nome, v_maior)
    when 'sem_nome' then 'Olá! Aqui é a Claudia, assistente virtual da HBR. ' || v_maior
    when 'apos_recibo' then format('%s, %s', v_nome, v_corpo)
    when 'apos_recibo_sem_nome' then v_maior
  end;
end;
$$;

comment on function public._retorno_abertura_do_modelo(text, jsonb) is
  'Retorno F2 (P6): a abertura do modelo em volta do corpo. padrao, padrao_apresentacao e sem_nome no lugar do recibo; apos_recibo e apos_recibo_sem_nome quando o cliente já ouviu o recibo do caso.';

revoke all on function public._retorno_abertura_do_modelo(text, jsonb) from public, anon, authenticated;

-- O texto do modelo do caso. A variante vem de quem chama; sem ela, a do cartão: depois do recibo, ou no lugar dele.
create or replace function public._retorno_texto_do_modelo(p_abertura uuid, p_modelo jsonb, p_variante text, p_agora timestamptz)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_ab public.retorno_aberturas;
  v_tipo text := p_modelo ->> 'modelo';
  v_ctx jsonb;
  v_nome text;
  v_ouviu boolean;
  v_var text := p_variante;
  v_dia date;
  v_te_aviso boolean := false;
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  v_nome := public._retorno_nome(v_ab.client_id);

  if p_modelo ->> 'os_id' is not null then
    v_ctx := public._agenda_cliente_contexto((p_modelo ->> 'os_id')::uuid, (p_agora at time zone c_fuso)::date);
  end if;
  if v_tipo = 'modelo_peca_chegou' then
    v_dia := (p_modelo -> 'fato' ->> 'em')::date;
  elsif v_tipo = 'modelo_aguarda_peca' then
    v_te_aviso := 'material_chegou' = any ((public._agenda_cfg()).cliente_tipos_ligados)
      and exists (select 1 from public.os_material m
                   where m.service_order_id = (p_modelo ->> 'os_id')::uuid
                     and m.critico
                     and m.situacao in ('comprado', 'a_caminho')
                     and (m.situacao = 'a_caminho' or m.previsao_ate is not null));
  end if;

  if v_var is null then
    v_ouviu := exists (select 1 from public.retorno_saidas s
                        where s.abertura_id = p_abertura
                          and s.tipo in ('recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'saudacao_numero_novo')
                          and s.estado in ('enviada', 'incerta')
                          and s.decidida_em <= p_agora);
    v_var := case when v_ouviu then case when v_nome is null then 'apos_recibo_sem_nome' else 'apos_recibo' end
                  when v_nome is null then 'sem_nome'
                  else 'padrao' end;
  end if;

  return public._retorno_abertura_do_modelo(v_var, jsonb_build_object(
    'nome', v_nome,
    'corpo', public._retorno_corpo_do_modelo(v_tipo, jsonb_build_object(
      'no_bem', v_ctx ->> 'no_bem', 'dia_peca', to_char(v_dia, 'DD/MM'), 'te_aviso', v_te_aviso,
      'intencao', p_modelo ->> 'intencao'))));
end;
$$;

comment on function public._retorno_texto_do_modelo(uuid, jsonb, text, timestamptz) is
  'Retorno F2 (P6, P7B): o texto do modelo do caso. {no_bem} vem de _agenda_cliente_contexto, {dia_peca} do fato. Sem variante: apos_recibo se o cliente ouviu o recibo, senão padrao ou sem_nome.';

revoke all on function public._retorno_texto_do_modelo(uuid, jsonb, text, timestamptz) from public, anon, authenticated;

create or replace function public._retorno_texto_f2(p_tipo text, p_variante text, p_dados jsonb)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  c_dia constant text := '^(hoje|amanhã|(segunda|terça|quarta|quinta|sexta|sábado|domingo) \([0-9]{2}/[0-9]{2}\))$';
  c_hora constant text := '^[0-9]{1,2}h$|^[0-9]{2}:[0-9]{2}$';
  d jsonb := case when jsonb_typeof(p_dados) = 'object' then p_dados else '{}'::jsonb end;
  v_modelo text;
  v_texto text;
  v_campo text;
  v_valor text;
begin
  v_modelo := case p_tipo || '/' || p_variante
    when 'recibo_cliente/retirada' then -- T29
      'Oi, {nome}! Retirar antes depende de como está o serviço, e quem confirma é o Gustavo. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/adicional' then -- T30
      'Anotado, {nome}! Passei ao Gustavo como serviço extra: ele avalia e informa o valor antes de fazer qualquer coisa. Ele retorna para você {quando_fala}.'
    when 'recibo_cliente/vou_confirmar' then -- T31
      'Oi, {nome}! Vou confirmar com o Gustavo, e ele retorna para você {quando_fala}.'
    when 'recibo_cliente/orcamento' then -- T32
      'Oi, {nome}! Seu orçamento já está em preparação com o Gustavo, e ele retorna para você {quando_fala}.'
    when 'adiamento/orcamento' then -- T33
      '{nome}, seu orçamento está em preparação e o Gustavo está conferindo os valores. Ele retorna para você ainda hoje.'
    when 'adiamento/orcamento_sem_nome' then -- T34
      'Seu orçamento está em preparação e o Gustavo está conferindo os valores. Ele retorna para você ainda hoje.'
    when 'coleta_numero_novo/nome_orcamento' then -- T35
      'Obrigada! Seu orçamento já está em preparação com o Gustavo. Como posso chamar você?'
  end;
  if v_modelo is null then
    raise exception 'texto F2: par desconhecido' using errcode = '22023';
  end if;

  v_texto := v_modelo;
  for v_campo in select distinct (regexp_matches(v_modelo, '\{([a-z_]+)\}', 'g'))[1] loop
    -- {quando_fala} sai de quando + hora (VOZ-2), conferidos aqui.
    if v_campo = 'quando_fala' then
      if coalesce(btrim(d ->> 'quando'), '') !~ c_dia or coalesce(btrim(d ->> 'hora'), '') !~ c_hora then
        raise exception 'texto F2: quando ou hora ausente ou inválido' using errcode = '22023';
      end if;
      v_valor := public._retorno_quando_fala(btrim(d ->> 'quando'), btrim(d ->> 'hora'));
      if v_valor is null then
        raise exception 'texto F2: quando ou hora ausente ou inválido' using errcode = '22023';
      end if;
      v_texto := replace(v_texto, '{quando_fala}', v_valor);
      continue;
    end if;
    v_valor := nullif(btrim(d ->> v_campo), '');
    if v_valor is null
       or (v_campo = 'quando' and v_valor !~ c_dia)
       or (v_campo = 'hora' and v_valor !~ c_hora) then
      raise exception 'texto F2: campo % ausente ou inválido', v_campo using errcode = '22023';
    end if;
    v_texto := replace(v_texto, '{' || v_campo || '}', v_valor);
  end loop;
  return v_texto;
end;
$$;

comment on function public._retorno_texto_f2(text, text, jsonb) is
  'Retorno F2 (P6): as variantes T29 a T35. Só com retorno_config.variantes_ligadas: com a chave desligada, sai o texto da F1. Falta de dado = 22023.';

revoke all on function public._retorno_texto_f2(text, text, jsonb) from public, anon, authenticated;

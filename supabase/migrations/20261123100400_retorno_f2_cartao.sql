-- Retorno rápido ao cliente, F2 (P7B): o cartão único.
--
-- Até 3 casos numa mensagem só, no mecanismo que já pede *sim <PIN>*: pendência, ponteiro da sessão e whatsapp_perguntas. A
-- pendência é a ação retorno_executar_cartao, de risco alto, fora da lista do modelo. No máximo 1 cartão vivo.
--
-- O que substitui a P7A: _retorno_item_montar, _retorno_cartao_texto e retorno_cartao_abrir.
--
-- Fora do histórico do modelo. O texto do cliente só existe em retorno_cartoes.texto, em retorno_cartoes.dados e no WhatsApp do
-- dono. summary, title, o par da conversa e a auditoria levam só rótulos e contagens.
--
-- Cartão que cai sozinho: _retorno_item_conferir é a única fonte da queda. A regra 2 só olha o que veio DEPOIS do envio: um "ok,
-- já vejo" de antes é justamente o que deixa o caso esperando conteúdo, e por isso ele entra no cartão. A regra 3 só roda no *sim*:
-- remontar o item a cada minuto custaria a leitura de fatos inteira.
--
-- Desvio da spec, achado na bancada de 07/11: _retorno_resposta_humana devolve a PRIMEIRA saída humana depois da abertura. Com um
-- "ok, já vejo" antes do cartão, a resposta de verdade depois dele não aparecia, e o modelo sairia por cima dela. A regra 2 usa
-- _retorno_resposta_depois, que olha só o que veio depois do instante dado. A função da F1 não muda.
--
-- Decisão de leitura, com o motivo: {prazo} e {fato} usam os dados de retorno_fatos_do_contato. A previsão aparece só aqui,
-- ao dono; o modelo nunca a recebe.
--
-- O ramo do acorde chama _retorno_a01_na_fila, que nasce no pacote 2 (20261201100000). Sem ele, _retorno_cartao_devido nunca
-- devolve 'acorde', então o ramo não é alcançado.
--
-- Reverter sem deploy: update public.retorno_config set cartao_ligado = false. O cartão vivo cai pela regra de sempre:
-- update public.ai_operator_pending_actions set status = 'rejected' where action_name = 'retorno_executar_cartao' and status = 'pending'.

create or replace function public._retorno_modo_da_voz()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when coalesce((select btrim(s.value, '"') from public.app_settings s where s.key = 'voz_unica'), '') = 'ligado'
     and coalesce((select btrim(s.value, '"') from public.app_settings s where s.key = 'resumo_formato'), '') = 'novo'
     and coalesce((select btrim(s.value, '"') from public.app_settings s where s.key = 'fechamento_formato'), '') = 'ligado'
    then 'ligado' else 'sombra' end;
$$;

comment on function public._retorno_modo_da_voz() is
  'Retorno F2 (P11): ligado só com voz_unica ligado, resumo_formato novo e fechamento_formato ligado, a regra de vozEfetiva; senão sombra.';

revoke all on function public._retorno_modo_da_voz() from public, anon, authenticated;

-- A sessão do dono: a regra de resolveOrCreateWhatsAppSession em SQL. Não herda pendência: pergunta_ocupado já disse que não há viva.
create or replace function public._retorno_sessao_do_dono(p_dono uuid, p_phone text, p_agora timestamptz)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_ultima timestamptz;
  v_meta jsonb;
begin
  select s.id, s.last_activity_at, s.metadata into v_id, v_ultima, v_meta
    from public.ai_operator_sessions s
   where s.channel = 'whatsapp' and s.external_thread_key = p_phone and s.status = 'open'
   order by s.last_activity_at desc
   limit 1;
  if v_id is not null and v_ultima >= p_agora - interval '4 hours' then
    return v_id;
  end if;
  insert into public.ai_operator_sessions (channel, channel_provider, owner_user_id, external_thread_key, status, metadata)
  values ('whatsapp', 'evolution', p_dono, p_phone, 'open',
          case when v_meta ? 'pendencias_guardadas'
               then jsonb_build_object('pendencias_guardadas', v_meta -> 'pendencias_guardadas')
               else '{}'::jsonb end)
  returning id into v_id;
  return v_id;
end;
$$;

comment on function public._retorno_sessao_do_dono(uuid, text, timestamptz) is
  'Retorno F2 (P7B): a sessão aberta do dono com atividade há menos de 4 h, senão uma nova, copiando pendencias_guardadas.';

revoke all on function public._retorno_sessao_do_dono(uuid, text, timestamptz) from public, anon, authenticated;

-- O que sei: sempre com fonte e data. Com previsão, porque aqui é só o dono quem lê.
create or replace function public._retorno_fato_texto(p_fatos jsonb, p_retirada boolean, p_os uuid, p_rotulo text, p_agora timestamptz)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  f jsonb := coalesce(p_fatos, '{}'::jsonb);
  v_hoje date := (p_agora at time zone c_fuso)::date;
  v_em timestamptz;
  v_dia date;
  v_quando text;
  v_linhas jsonb;
  v_prev jsonb;
  v_nomes text;
  v_partes text[] := '{}';
  v_saldo numeric;
  v_n integer;
begin
  if p_retirada then
    if f -> 'em_servico' <> 'null'::jsonb and f -> 'em_servico' ->> 'etapa' is not null then
      v_partes := v_partes || format('etapa: %s', f -> 'em_servico' ->> 'etapa');
    end if;
    v_partes := v_partes || case when f -> 'aguarda_peca' <> 'null'::jsonb then 'faltam peças' else 'material completo' end;
    begin
      select sum(r.balance_amount), count(*) into v_saldo, v_n
        from public.receivables r
       where r.service_order_id = p_os and r.status in ('pending', 'partially_paid');
      v_partes := v_partes || case when v_n = 0 then 'sem recebível lançado'
                                   else format('a receber: R$ %s (só você vê)',
                                               replace(to_char(round(v_saldo), 'FM999G999G990'), ',', '.')) end;
    exception when others then
      null;   -- a parte some, nunca vira R$ 0
    end;
    return array_to_string(v_partes, ' · ');
  end if;

  if f -> 'pronto' <> 'null'::jsonb then
    v_em := (f -> 'pronto' ->> 'em')::timestamptz;
    v_dia := (v_em at time zone c_fuso)::date;
    v_quando := case when v_dia = v_hoje then 'hoje' when v_dia = v_hoje - 1 then 'ontem' else to_char(v_dia, 'DD/MM') end;
    return format('%s disse *concluiu* %s às %s', case when f -> 'pronto' ->> 'fonte' = 'equipe' then 'a equipe' else 'você' end,
                  v_quando, to_char(v_em at time zone c_fuso, 'HH24:MI'));
  end if;
  if f -> 'concluida_sem_palavra' <> 'null'::jsonb then
    return format('o banco diz concluída desde %s, sem a sua palavra; confirma? *concluiu %s*',
                  to_char((f -> 'concluida_sem_palavra' ->> 'desde')::date, 'DD/MM'), p_rotulo);
  end if;
  if f -> 'em_servico' <> 'null'::jsonb then
    v_em := (f -> 'em_servico' ->> 'em')::timestamptz;
    return concat_ws(' · ',
      case f -> 'em_servico' ->> 'fonte' when 'check_in' then format('em serviço (check-in às %s)', to_char(v_em at time zone c_fuso, 'HH24:MI'))
                                         else 'em serviço hoje (técnico confirmou)' end,
      nullif(f -> 'em_servico' ->> 'etapa', ''));
  end if;
  if f -> 'peca_chegou' <> 'null'::jsonb then
    v_n := (f -> 'peca_chegou' ->> 'linhas')::integer;
    return format('%s em %s (%s)%s',
                  case when v_n > 1 then v_n || ' peças chegaram' else 'a peça chegou' end,
                  to_char((f -> 'peca_chegou' ->> 'em')::date, 'DD/MM'),
                  case f -> 'peca_chegou' ->> 'fonte' when 'nfe' then 'nota' when 'oc' then 'compra' when 'dono' then 'você disse' else 'fornecedor' end,
                  case when (f -> 'peca_chegou' ->> 'faltam_outras')::boolean then '; faltam outras' else '' end);
  end if;
  if f -> 'aguarda_peca' <> 'null'::jsonb then
    v_linhas := f -> 'aguarda_peca' -> 'linhas';
    v_prev := f -> 'previsao';
    select string_agg(e ->> 'descricao', ', ' order by ord) into v_nomes
      from jsonb_array_elements(v_linhas) with ordinality as x(e, ord) where ord <= 2;
    if jsonb_array_length(v_linhas) > 2 then
      v_nomes := format('%s e mais %s', v_nomes, jsonb_array_length(v_linhas) - 2);
    end if;
    return format('aguardando %s (%s)', v_nomes,
      case
        when v_prev is null or v_prev = 'null'::jsonb then
          format('em falta desde %s, sem previsão', to_char((v_linhas -> 0 ->> 'desde')::date, 'DD/MM'))
        when (v_prev ->> 'padrao')::boolean then
          format('em falta, previsão padrão %s, %s dias úteis', to_char((v_prev ->> 'ate')::date, 'DD/MM'),
                 (public._agenda_cfg()).prazo_sem_fornecedor_du)
        else
          format('%s, previsão %s', case v_linhas -> 0 ->> 'situacao' when 'a_caminho' then 'a caminho' when 'comprado' then 'comprado' else 'em falta' end,
                 to_char((v_prev ->> 'ate')::date, 'DD/MM'))
      end);
  end if;
  return null;
end;
$$;

comment on function public._retorno_fato_texto(jsonb, boolean, uuid, text, timestamptz) is
  'Retorno F2 (P7B): a linha "O que sei" do cartão, sempre com fonte e data. Só o dono lê: pode ter previsão e o que falta receber.';

revoke all on function public._retorno_fato_texto(jsonb, boolean, uuid, text, timestamptz) from public, anon, authenticated;

create or replace function public._retorno_item_montar(p_abertura uuid, p_n smallint, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_letras constant text[] := array['A', 'B', 'C', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'P', 'Q', 'R', 'T', 'U'];
  v_ab public.retorno_aberturas;
  v_rotulo text;
  v_fatos jsonb;
  v_os jsonb;
  v_f jsonb;
  v_m jsonb;
  v_nivel text;
  v_int text;
  v_tipo text;
  v_modelo text;
  v_texto text;
  v_opcoes jsonb := '[]'::jsonb;
  v_frases text[] := '{}';
  v_fato_txt text;
  v_linhas jsonb;
  v_k integer;
  v_clientes uuid[];
  v_c uuid;
  v_i integer := 0;
  v_numero text;
  v_retrato jsonb := '{}'::jsonb;
  v_prov uuid;
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  v_rotulo := public._retorno_rotulo(p_abertura, p_agora);
  v_k := public._retorno_automaticas_hoje(v_ab.chave, p_agora);
  v_int := public._retorno_intencao_do_caso(p_abertura, p_agora);

  begin
    if v_ab.papel = 'cliente' then
      v_fatos := public.retorno_fatos_do_contato(v_ab.phone_normalized, p_agora);
    end if;
  exception when others then
    v_fatos := null;   -- sem fato, nunca "não há peça"
  end;
  if v_fatos is not null and jsonb_array_length(v_fatos -> 'os') = 1 then
    v_os := v_fatos -> 'os' -> 0;
    v_f := v_os -> 'fatos';
    v_numero := v_os ->> 'numero';
  end if;

  v_m := public._retorno_modelo_do_caso(p_abertura, p_agora);
  if v_m ->> 'modelo' is not null then
    select t.nivel into v_nivel from public.retorno_modelo_tipos t where t.tipo = v_m ->> 'modelo';
  end if;

  if v_ab.papel = 'cliente_ambiguo' then
    v_tipo := 'ambiguo';
    v_clientes := case when cardinality(v_ab.clientes) > 0 then v_ab.clientes
                       else array(select (e)::uuid from jsonb_array_elements_text(coalesce(v_ab.quem -> 'clientes', '[]'::jsonb)) e) end;
    foreach v_c in array v_clientes loop
      v_i := v_i + 1;
      exit when v_i > cardinality(c_letras);
      v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object(
        'letra', c_letras[v_i], 'acao', 'cliente', 'client_id', v_c, 'rotulo', coalesce(public._retorno_nome(v_c), 'sem nome')));
      v_frases := v_frases || format('*%s %s* = %s', p_n, c_letras[v_i], coalesce(public._retorno_nome(v_c), 'sem nome'));
    end loop;
  elsif v_ab.papel = 'numero_novo' then
    v_tipo := 'numero_novo';
    select a.record_id into v_prov
      from public.audit_log a
     where a.table_name = 'clients' and a.new_value ->> 'caso' = p_abertura::text
     limit 1;
    if v_prov is not null then
      v_opcoes := jsonb_build_array(jsonb_build_object('letra', 'D', 'acao', 'desfaz_cadastro', 'client_id', v_prov, 'rotulo', 'desfaz o cadastro'));
      v_frases := array[format('*%s D* = desfaz o cadastro', p_n)];
    end if;
  elsif v_m ->> 'modelo' is not null and v_nivel in ('cartao', 'sozinho') then
    v_tipo := 'modelo';
    v_modelo := v_m ->> 'modelo';
    v_texto := public._retorno_texto_do_modelo(p_abertura, v_m, null, p_agora);
    v_retrato := jsonb_build_object('fato', v_m -> 'fato', 'intencao', v_m ->> 'intencao');
    if v_modelo = 'modelo_aguarda_peca' then
      v_opcoes := jsonb_build_array(
        jsonb_build_object('letra', 'B', 'acao', 'chegou', 'os', v_numero, 'rotulo', 'a peça chegou'),
        jsonb_build_object('letra', 'C', 'acao', 'previsao', 'os', v_numero, 'rotulo', 'dite a previsão'));
      v_frases := array[format('*%s B* = %s', p_n, case when jsonb_array_length(v_f -> 'aguarda_peca' -> 'linhas') > 1 then 'chegou tudo' else 'a peça chegou' end),
                        format('*%s C* = dite a previsão', p_n)];
    end if;
  elsif (v_f is not null and v_f -> 'aguarda_peca' <> 'null'::jsonb)
        or (v_int = 'peca' and (v_f is null or v_f -> 'peca_chegou' = 'null'::jsonb)) then
    v_tipo := 'peca_sem_registro';
    if v_numero is not null then
      v_opcoes := jsonb_build_array(
        jsonb_build_object('letra', 'B', 'acao', 'chegou', 'os', v_numero, 'rotulo', 'a peça chegou'),
        jsonb_build_object('letra', 'C', 'acao', 'previsao', 'os', v_numero, 'rotulo', 'dite a previsão'));
      v_frases := array[format('*%s B* = %s', p_n,
                               case when v_f is not null and v_f -> 'aguarda_peca' <> 'null'::jsonb
                                         and jsonb_array_length(v_f -> 'aguarda_peca' -> 'linhas') > 1
                                    then 'chegou tudo' else 'a peça chegou' end),
                        format('*%s C* = dite a previsão', p_n)];
    end if;
  elsif v_f is not null and v_f -> 'concluida_sem_palavra' <> 'null'::jsonb then
    v_tipo := 'pronto_sem_palavra';
  elsif v_int = 'retirada' then
    v_tipo := 'retirada';
    v_opcoes := jsonb_build_array(
      jsonb_build_object('letra', 'A', 'acao', 'responder', 'modelo', 'modelo_liberado', 'marca_liberado', true, 'rotulo', 'pode retirar', 'os_id', v_os ->> 'id'),
      jsonb_build_object('letra', 'B', 'acao', 'responder', 'modelo', 'modelo_retirada_nao', 'rotulo', 'ainda não dá', 'os_id', v_os ->> 'id'));
    v_frases := array[format('*%s A* = pode retirar', p_n), format('*%s B* = ainda não dá', p_n)];
  elsif v_int = 'orcamento' then
    v_tipo := 'orcamento';
  elsif v_int = 'adicional' then
    v_tipo := 'adicional';
  else
    v_tipo := 'livre';
  end if;

  v_linhas := jsonb_build_array(format('%s. %s%s%s · %s · %s · %s', p_n, v_rotulo,
    case when v_numero is not null then ' · ' || v_numero else '' end,
    case when v_os ->> 'bem' is not null then ' · ' || (v_os ->> 'bem') else '' end,
    to_char(v_ab.aberta_em at time zone c_fuso, 'HH24:MI'),
    public._retorno_prazo_curto(p_abertura, p_agora),
    public._retorno_pedido_do_caso(p_abertura, p_agora)));

  v_fato_txt := public._retorno_fato_texto(v_f, v_tipo = 'retirada', (v_os ->> 'id')::uuid, v_rotulo, p_agora);
  if v_fato_txt is not null then
    v_linhas := v_linhas || jsonb_build_array('   O que sei: ' || v_fato_txt);
  end if;
  if v_modelo is not null then
    v_linhas := v_linhas || jsonb_build_array(format('   Modelo: ''%s''', v_texto));
  end if;
  if cardinality(v_frases) > 0 then
    v_linhas := v_linhas || jsonb_build_array('   ' || array_to_string(v_frases, ' · '));
  end if;
  if v_k >= 1 then
    v_linhas := v_linhas || jsonb_build_array(format('   Ele já recebeu %s automáticas hoje.', v_k));
  end if;

  return jsonb_build_object(
    'tipo_item', v_tipo, 'modelo_tipo', v_modelo, 'service_order_id', v_os ->> 'id', 'texto_mostrado', v_texto,
    'opcoes', v_opcoes, 'fatos', v_retrato, 'linhas', v_linhas,
    'hash', md5(concat_ws('|', v_ab.phone_normalized, v_modelo, v_texto, v_retrato::text, v_k)));
end;
$$;

comment on function public._retorno_item_montar(uuid, smallint, timestamptz) is
  'Retorno F2 (P7B): monta um item do cartão. A 1ª linha que casa decide o tipo: ambiguo, numero_novo, modelo (com o tipo em cartao ou sozinho), peca_sem_registro, pronto_sem_palavra, retirada, orcamento, adicional, livre. fatos guarda só o retrato usado no hash.';

revoke all on function public._retorno_item_montar(uuid, smallint, timestamptz) from public, anon, authenticated;

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
  v_primeiro smallint;
  v_mandam smallint[];
  v_faz text;
  v_rodape text;
  v_max boolean;
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
    if cardinality(v_mandam) > 0 then
      v_faz := case when cardinality(v_mandam) = 1 then format('o %s', v_mandam[1])
                    when cardinality(v_mandam) = 2 then format('o %s e o %s', v_mandam[1], v_mandam[2])
                    else 'os 3' end;
      v_rodape := format('*sim <PIN>* faz %s · *só %s* · *ver %s* · *não* · ou dite por áudio', v_faz, v_mandam[1], v_primeiro);
    else
      v_rodape := format('*ver %1$s* · *dita %1$s …* · *não* · ou dite por áudio', v_primeiro);
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

  return concat_ws(E'\n', v_cabeca, v_corpo,
                   case when v_c.mais > 0 then format('e mais %s: *retorno*', v_c.mais) end,
                   v_rodape);
end;
$$;

comment on function public._retorno_cartao_texto(uuid, text) is
  'Retorno F2 (P7B): cabeçalho, linhas dos itens vivos, "e mais k" e rodapé. Cartão vivo com o que mandar: *sim <PIN>*; sem nada a mandar: *dita*. A linha do assistente fora só quando ai_claude_max_disponivel() é falso; erro ao ler, ela não aparece.';

revoke all on function public._retorno_cartao_texto(uuid, text) from public, anon, authenticated;

create or replace function public.retorno_cartao_abrir(p_gatilho text, p_agora timestamptz default now(), p_aviso uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
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
  if v_vivo is not null and v_vivo ->> 'estado' = 'vivo' then
    v_cartao := (v_vivo ->> 'id')::uuid;
    if p_gatilho = 'puxar' then
      update public.retorno_cartao_itens i set selecionado = true where i.cartao_id = v_cartao and i.estado = 'vivo';
      v_texto := public._retorno_cartao_texto(v_cartao, null);
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
            when not v_cfg.cartao_ligado then '*ver 1* · *pessoal 1*'
            when v_ocupado then 'Tem um pedido aberto antes deste: responda a ele e mande *retorno* de novo.' end))
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
    v_nomes := v_nomes || public._retorno_rotulo(v_caso.abertura_id, v_agora);
  end loop;

  update public.retorno_cartoes c
     set hash = md5(v_hashes), dados = c.dados || jsonb_build_object('linhas', v_linhas)
   where c.id = v_cartao;

  if not v_cfg.cartao_ligado or v_ocupado then
    v_texto := public._retorno_cartao_texto(v_cartao, null);
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
  v_texto := public._retorno_cartao_texto(v_cartao, null);
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

comment on function public.retorno_cartao_abrir(text, timestamptz, uuid) is
  'Retorno F2 (C-CARTAO): {"acao": "cartao"|"lista"|"reapresenta"|"ocupado"|"ja_vivo"|"vazio", ...}. Só 1 cartão vivo. Com cartao_ligado falso ou o telefone ocupado, lista sem pendência. O texto do cliente fica fora de pendência, conversa e auditoria.';

revoke all on function public.retorno_cartao_abrir(text, timestamptz, uuid) from public, anon, authenticated;
grant execute on function public.retorno_cartao_abrir(text, timestamptz, uuid) to service_role;

create or replace function public.retorno_cartao_enviado(p_cartao uuid, p_ok boolean, p_wa_id text default null, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_c public.retorno_cartoes;
begin
  select * into v_c from public.retorno_cartoes c where c.id = p_cartao for update;
  if not found then
    return jsonb_build_object('ok', false);
  end if;
  if p_ok then
    update public.retorno_cartoes c set enviado_em = coalesce(c.enviado_em, v_agora) where c.id = p_cartao;
    if v_c.pergunta_id is not null and p_wa_id is not null then
      perform public.pergunta_marcar_enviada(v_c.pergunta_id, p_wa_id);
    end if;
    return jsonb_build_object('ok', true);
  end if;

  update public.retorno_cartoes c
     set tentativas = c.tentativas + 1, estado = 'falhou'
   where c.id = p_cartao;
  update public.retorno_cartao_itens i set estado = 'fora' where i.cartao_id = p_cartao and i.estado = 'vivo';
  if v_c.pendencia_id is not null then
    update public.ai_operator_pending_actions p
       set status = 'rejected', rejected_at = v_agora
     where p.id = v_c.pendencia_id and p.status = 'pending';
    update public.ai_operator_sessions s
       set metadata = s.metadata - 'pending_confirm_action_id'
     where s.id = v_c.sessao_id and s.metadata ->> 'pending_confirm_action_id' = v_c.pendencia_id::text;
  end if;
  if v_c.pergunta_id is not null then
    perform public._pergunta_fechar(v_c.pergunta_id, 'cancelada', 'cartao_nao_enviado', null);
  end if;
  if v_c.aviso_id is not null then
    perform public.aviso_reabrir(jsonb_build_object('id', v_c.aviso_id, 'agora', v_agora));
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

comment on function public.retorno_cartao_enviado(uuid, boolean, text, timestamptz) is
  'Retorno F2 (C-ENVIADO): ok grava enviado_em e marca a pergunta. Falha: cartão falhou, pendência rejeitada, ponteiro limpo só se for o do cartão, pergunta cancelada e aviso reaberto.';

revoke all on function public.retorno_cartao_enviado(uuid, boolean, text, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_cartao_enviado(uuid, boolean, text, timestamptz) to service_role;

-- A 1ª saída humana à chave depois de p_desde, gravada até p_agora, com a mesma régua de _retorno_resposta_humana.
create or replace function public._retorno_resposta_depois(p_abertura uuid, p_desde timestamptz, p_agora timestamptz)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  select min(h.real)
    from (select public._retorno_hora_real(o) as real, o.occurred_at
            from public.retorno_aberturas a
            join public.whatsapp_messages o on public._agenda_chave_telefone(o.phone_normalized) = a.chave
           where a.id = p_abertura
             and o.direction = 'outbound'
             and o.occurred_at <= p_agora
             and o.occurred_at > p_desde - interval '10 minutes'
             and coalesce(o.saida_humana, public._saida_e_humana(o.direction, o.raw_payload, o.sent_by))) h
   where h.real > p_desde or h.occurred_at > p_desde;
$$;

comment on function public._retorno_resposta_depois(uuid, timestamptz, timestamptz) is
  'Retorno F2 (P7B.3): a 1ª saída humana à chave depois de p_desde, gravada até p_agora. _retorno_resposta_humana só devolve a primeira depois da abertura, e um "ok" antes do cartão esconderia a resposta de verdade.';

revoke all on function public._retorno_resposta_depois(uuid, timestamptz, timestamptz) from public, anon, authenticated;

create or replace function public._retorno_item_conferir(p_item uuid, p_agora timestamptz, p_executar boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_i public.retorno_cartao_itens;
  v_c public.retorno_cartoes;
  v_ab public.retorno_aberturas;
  v_resp timestamptz;
  v_quem jsonb;
begin
  select * into v_i from public.retorno_cartao_itens i where i.id = p_item;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'caso_fechado', 'texto', 'o item já não existe; não mandei');
  end if;
  select * into v_c from public.retorno_cartoes c where c.id = v_i.cartao_id;
  select * into v_ab from public.retorno_aberturas a where a.id = v_i.abertura_id;

  if v_ab.estado = 'fechada' then
    return jsonb_build_object('ok', false, 'motivo', 'caso_fechado', 'texto', format('o %s já estava resolvido; não mandei', v_i.n));
  end if;

  if v_c.enviado_em is not null then
    v_resp := public._retorno_resposta_depois(v_ab.id, v_c.enviado_em, p_agora);
  end if;
  if v_resp is not null then
    return jsonb_build_object('ok', false, 'motivo', 'respondida_pelo_dono',
      'texto', format('o %s caiu: você já respondeu às %s; não mandei', v_i.n, to_char(v_resp at time zone c_fuso, 'HH24:MI')));
  end if;

  if p_executar and v_i.modelo_tipo is not null
     and (public._retorno_item_montar(v_ab.id, v_i.n, p_agora) ->> 'hash') is distinct from v_i.hash then
    return jsonb_build_object('ok', false, 'motivo', 'fato_mudou',
      'texto', format('o %s mudou desde o cartão: mande *retorno* para ver de novo; não mandei', v_i.n));
  end if;

  if v_ab.papel = 'cliente' then
    v_quem := public.quem_escreve(v_ab.phone_normalized);
    if (v_quem ->> 'cliente_id')::uuid is distinct from v_ab.client_id then
      return jsonb_build_object('ok', false, 'motivo', 'telefone_mudou', 'texto', format('o %s mudou de número; não mandei', v_i.n));
    end if;
  end if;

  if public.canal_bloqueado(v_ab.phone_normalized) is not null
     or v_ab.nivel = 'nada'
     or exists (select 1 from public.whatsapp_leads l
                 where l.lead_tipo = 'pessoal' and public._agenda_chave_telefone(l.phone_normalized) = v_ab.chave) then
    return jsonb_build_object('ok', false, 'motivo', 'canal_bloqueado',
      'texto', format('o %s pediu para não receber mensagem automática: responda pelo celular se for preciso; não mandei', v_i.n));
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

comment on function public._retorno_item_conferir(uuid, timestamptz, boolean) is
  'Retorno F2 (P7B.3): a única fonte da queda do item. {"ok": true} ou {"ok": false, "motivo", "texto"}: caso_fechado, respondida_pelo_dono (só depois do envio do cartão), fato_mudou (só com p_executar), telefone_mudou, canal_bloqueado.';

revoke all on function public._retorno_item_conferir(uuid, timestamptz, boolean) from public, anon, authenticated;

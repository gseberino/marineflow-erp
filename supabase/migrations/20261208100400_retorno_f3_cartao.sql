-- Retorno rápido ao cliente, F3 (P5): a proposta no cartão. Gerada por script (scripts/gerar_f3.cjs cartao) a partir do corpo vigente;
-- só os trechos marcados -- F3 são novos, e é nisso que o teste de regressão se apoia.
--
-- Só em vigor com previa_ditado_ligado = true ou previa_modo = 'ligado'. Com as duas desligadas, o cartão sai idêntico ao da F2, byte a byte.
--
-- O item ganha previa_id e acao_sim ('orcar' cria o orçamento e manda o PDF; 'pdf' manda o PDF de um rascunho que já existe; nulo é a regra
-- da F2). O *sim <PIN>* continua no mecanismo da F2: _retorno_item_conferir compara hash, proposta e orçamento com o que o dono leu.
--
-- A linha C30 de cada item é a primeira a sair quando o cartão passaria de 3.500 caracteres.
-- Reverter: reaplicar as versões de _retorno_cartao_casos (20261123100300), _retorno_item_montar, _retorno_cartao_texto, retorno_cartao_abrir e
-- _retorno_item_conferir (20261123100400), _retorno_item_remontar e retorno_ver_caso (20261123100500). Sem deploy, basta previa_ditado_ligado = false
-- e previa_modo <> 'ligado': o bloco inteiro deixa de rodar.

-- ── 1. Auxiliares novas ─────────────────────────────────────────────────────────────────────────────

-- "ago/26": três letras em português, minúsculas. Nunca "preço de hoje".
create or replace function public._retorno_mes_aa(p date)
returns text
language sql
immutable
set search_path = public
as $$
  select case when p is null then null else
    (array['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'])[extract(month from p)::int] || '/' || to_char(p, 'YY') end;
$$;

comment on function public._retorno_mes_aa(date) is
  'Retorno F3 (P5): a data como aparece no cartão, "ago/26".';

revoke all on function public._retorno_mes_aa(date) from public, anon, authenticated;

-- A marca de visita a combinar só cede ao ato do dono: orçamento ditado ou rascunho feito depois dela (rr-f1-10).
create or replace function public._retorno_visita_em_aberto(p_abertura uuid, p_agora timestamptz)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_marca timestamptz;
  v_rasc jsonb;
begin
  select a.visita_a_combinar_em into v_marca from public.retorno_aberturas a where a.id = p_abertura;
  if v_marca is null then
    return false;
  end if;
  if exists (select 1 from public.retorno_previa p
              where p.abertura_id = p_abertura and p.estado = 'proposta' and p.origem = 'ditado') then
    return false;
  end if;
  v_rasc := public._retorno_rascunho_do_caso(p_abertura, p_agora);
  if v_rasc is not null and (v_rasc ->> 'criado_em')::timestamptz > v_marca then
    return false;
  end if;
  return true;
end;
$$;

comment on function public._retorno_visita_em_aberto(uuid, timestamptz) is
  'Retorno F3 (P5): o caso tem a marca de visita a combinar, sem proposta ditada viva nem rascunho criado depois da marca. Com ela verdadeira, o cartão só lembra da visita (linha 0) e o caso vai para o fim da fila.';

revoke all on function public._retorno_visita_em_aberto(uuid, timestamptz) from public, anon, authenticated;

-- ── 2. Gerado do corpo vigente, com os trechos -- F3 ──────────────────────────────────────────────────

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
              -- F3 (P5): a visita a combinar não toma a vaga de orçamento novo, mas continua na lista (rr-f1-10). O orçamento ditado depois dela sai daqui.
              when public._retorno_visita_em_aberto(a.id, p_agora) then 7
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
  -- F3 (P5)
  v_cfg public.retorno_config := public._retorno_cfg();
  v_hoje date;
  v_pv public.retorno_previa;
  v_cad jsonb;
  v_cli uuid;
  v_unidades jsonb;
  v_vessel uuid;
  v_vessel_nome text;
  v_rasc jsonb;
  v_ato boolean;
  v_int_ok boolean;
  v_acao text;
  v_previa uuid;
  v_so_f3 uuid;
  v_so_total text;
  v_hash_f3 text;
  v_f3_linhas text[] := '{}';
  v_pedacos text[] := '{}';
  v_nomes_un text[] := '{}';
  v_n_cat integer;
  v_n_dito integer;
  v_nome_cat text;
  v_nome_velho text;
  v_c20 text;
  v_precos text;
  v_partes text[];
  v_confira text;
  v_alt jsonb;
  v_sem_preco text[];
  v_n_desc integer;
  v_inativos text[];
  r record;
  i integer;
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

  -- F3 (P5): a proposta no cartão. Só em vigor com previa_ditado_ligado = true ou previa_modo = 'ligado'; com as duas desligadas, o
  -- item é byte a byte o da F2. previa_modo = 'ligado' exige previa_ditado_ligado (check da P1): aqui as duas valem juntas.
  if v_cfg.previa_ditado_ligado or v_cfg.previa_modo = 'ligado' then
    v_hoje := (p_agora at time zone c_fuso)::date;
    select p.* into v_pv from public.retorno_previa p where p.abertura_id = p_abertura and p.estado = 'proposta' limit 1;
    v_cad := public._retorno_cadastro_do_caso(p_abertura);
    v_cli := (v_cad ->> 'client_id')::uuid;
    v_unidades := public._retorno_unidades_do_cliente(v_cli);
    v_vessel := coalesce(v_pv.vessel_id, (public._retorno_unidade_do_caso(p_abertura, v_cli, p_agora) ->> 'vessel_id')::uuid);
    v_rasc := public._retorno_rascunho_do_caso(p_abertura, p_agora);
    v_ato := (v_pv.id is not null and (v_pv.origem = 'ditado' or coalesce((v_pv.dados ->> 'ajustada_por_ditado')::boolean, false)))
             or (v_rasc is not null
                 and exists (select 1 from public.service_orders so
                              where so.id = (v_rasc ->> 'service_order_id')::uuid and so.origem_chave8 = v_ab.chave));
    v_int_ok := coalesce(v_int in ('orcamento', 'adicional'), false);

    if public._retorno_visita_em_aberto(p_abertura, p_agora) then
      -- Linha 0, em qualquer tipo: só lembra da visita. Não mexe nas opções da F2.
      v_f3_linhas := array[format('   Visita a combinar desde %s. *resolvido %s* tira da lista.',
                                  to_char(v_ab.visita_a_combinar_em at time zone c_fuso, 'DD/MM'), p_n)];
    elsif v_ato or (v_tipo in ('orcamento', 'adicional', 'numero_novo') and v_int_ok) then
      -- O ato do dono vale mais que a intenção adivinhada: nenhum modelo nem letra da F2 sobra neste caso.
      v_modelo := null;
      v_texto := null;
      v_retrato := '{}'::jsonb;
      if v_tipo <> 'numero_novo' then
        v_opcoes := '[]'::jsonb;
        v_frases := '{}';
      end if;
      v_vessel_nome := (select left(v.name, 30) from public.vessels v where v.id = v_vessel);

      if v_rasc is not null then
        -- Linhas 1 e 1b: o rascunho exato que está na mesa, com número, data e unidade à vista.
        v_so_f3 := (v_rasc ->> 'service_order_id')::uuid;
        v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'L', 'acao', 'responder', 'modelo', 'modelo_ver_no_local', 'os_id', null, 'rotulo', 'precisa ver no local'));
        if coalesce((v_rasc ->> 'total')::numeric, 0) > 0 and (v_rasc ->> 'linhas_n')::integer > 0 and (v_rasc ->> 'linhas_sem_preco')::integer = 0 then
          v_acao := 'pdf';
          v_so_total := v_rasc ->> 'total';
          v_f3_linhas := array[format('   Rascunho %s de %s%s: %s · R$ %s · vale até %s se sair hoje',
            v_rasc ->> 'numero',
            to_char((v_rasc ->> 'criado_em')::timestamptz at time zone c_fuso, 'DD/MM'),
            case when v_rasc ->> 'unidade' is not null then ' · ' || left(v_rasc ->> 'unidade', 30) else '' end,
            case when (v_rasc ->> 'linhas_n')::integer = 1 then '1 item' else (v_rasc ->> 'linhas_n') || ' itens' end,
            public._retorno_brl((v_rasc ->> 'total')::numeric),
            public._retorno_quando(public._retorno_validade_do_envio(p_agora), v_hoje))];
        else
          v_f3_linhas := array[format('   Rascunho %s de %s está sem valor: complete na tela. *%s L* precisa ver no local.',
            v_rasc ->> 'numero', to_char((v_rasc ->> 'criado_em')::timestamptz at time zone c_fuso, 'DD/MM'), p_n)];
        end if;

      elsif v_pv.id is not null then
        -- Linhas 2 a 5b: a proposta viva.
        v_previa := v_pv.id;
        v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'L', 'acao', 'responder', 'modelo', 'modelo_ver_no_local', 'os_id', null, 'rotulo', 'precisa ver no local'));

        select count(*) filter (where l.preco_fonte = 'catalogo'),
               count(*) filter (where l.preco_fonte = 'dito'),
               (array_agg(left(l.nome, 40) order by l.ordem) filter (where l.preco_fonte = 'catalogo'))[1],
               (array_agg(left(l.nome, 40) order by l.preco_em, l.ordem) filter (where l.preco_em is not null))[1]
          into v_n_cat, v_n_dito, v_nome_cat, v_nome_velho
          from public.retorno_previa_linhas l where l.previa_id = v_pv.id;

        if v_pv.origem = 'ditado' then
          v_c20 := format('   Proposta ditada%s: %s · R$ %s · %s %s %s por você',
            case when v_vessel_nome is not null then ' · ' || v_vessel_nome else '' end,
            case when v_pv.linhas_n = 1 then '1 item' else v_pv.linhas_n || ' itens' end,
            public._retorno_brl(v_pv.total),
            v_n_dito,
            case when v_n_dito = 1 then 'preço' else 'preços' end,
            case when v_n_dito = 1 then 'dito' else 'ditos' end);
        else
          if v_pv.linhas_n > 0 and v_n_cat = v_pv.linhas_n then
            v_precos := 'preços de catálogo, sem data';
          elsif v_pv.linhas_n > 0 and v_n_dito = v_pv.linhas_n then
            v_precos := 'preços ditados por você';
          else
            v_partes := '{}';
            if v_pv.preco_mais_antigo is not null then
              v_partes := v_partes || ('preços de ' || public._retorno_mes_aa(v_pv.preco_mais_antigo));
            end if;
            if v_n_cat > 0 then
              v_partes := v_partes || format('%s de catálogo, sem data', v_n_cat);
            end if;
            if v_n_dito > 0 then
              v_partes := v_partes || format('%s %s por você', v_n_dito, case when v_n_dito = 1 then 'dito' else 'ditos' end);
            end if;
            v_precos := array_to_string(v_partes, ' e ');
          end if;
          v_confira := case
            when v_pv.preco_mais_antigo is not null and v_pv.preco_mais_antigo < (v_hoje - v_cfg.previa_preco_velho)::date then v_nome_velho
            when v_n_cat > 0 then v_nome_cat
          end;
          v_c20 := format('   Proposta com base no %s%s%s: %s · R$ %s%s%s',
            v_pv.fonte_numero,
            case when not coalesce((v_pv.dados ->> 'fonte_aprovada')::boolean, false) then ' (não aprovado)' else '' end,
            case when v_vessel_nome is not null then ' · ' || v_vessel_nome else '' end,
            case when v_pv.linhas_n = 1 then '1 item' else v_pv.linhas_n || ' itens' end,
            public._retorno_brl(v_pv.total),
            case when coalesce(v_precos, '') <> '' then ' · ' || v_precos else '' end,
            case when v_confira is not null then ': confira o preço de ' || v_confira else '' end);
        end if;
        v_f3_linhas := array[v_c20];

        if v_vessel is not null then
          -- Linhas 2, 2b e 3: a proposta com unidade definida.
          v_acao := 'orcar';
          v_hash_f3 := public._retorno_previa_hash_efetivo(v_pv.id, p_agora);
          v_alt := v_pv.dados -> 'alternativas' -> 0;
          if v_alt is not null and v_alt ->> 'os_id' is not null then
            v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'B', 'acao', 'parecido', 'os_id', v_alt ->> 'os_id', 'numero', v_alt ->> 'numero', 'rotulo', 'usa o ' || (v_alt ->> 'numero')));
            v_pedacos := v_pedacos || format('*%s B* usa o %s', p_n, v_alt ->> 'numero');
          end if;

          if v_pv.provisorios_n > 0 then
            -- Linha 3: o que falta completar aparece aqui, e o *sim <PIN>* não cria nada enquanto faltar (P6).
            select coalesce(array_agg(left(l.nome, 40) order by l.ordem) filter (where l.estado = 'provisorio' and l.motivo in ('sem_preco', 'preco_invalido')), '{}'),
                   count(*) filter (where l.estado = 'provisorio' and l.motivo = 'nome_com_dado_de_outro'),
                   coalesce(array_agg(left(l.nome, 40) order by l.ordem) filter (where l.estado = 'provisorio' and l.motivo = 'inativo'), '{}')
              into v_sem_preco, v_n_desc, v_inativos
              from public.retorno_previa_linhas l where l.previa_id = v_pv.id;
            if cardinality(v_sem_preco) > 0 then
              v_f3_linhas := v_f3_linhas || format('   Falta preço em %s: %s. Dite o valor antes do *sim*.',
                                                   cardinality(v_sem_preco), array_to_string(v_sem_preco[1:2], ', '));
            end if;
            if v_n_desc > 0 then
              v_f3_linhas := v_f3_linhas || format('   Falta descrever %s %s: diga o que é cada um antes do *sim*.',
                                                   v_n_desc, case when v_n_desc = 1 then 'serviço' else 'serviços' end);
            end if;
            if cardinality(v_inativos) > 0 then
              v_f3_linhas := v_f3_linhas || format('   Fora de linha no cadastro: %s. Troque ou tire antes do *sim*.', array_to_string(v_inativos[1:2], ', '));
            end if;
          elsif v_pv.origem <> 'ditado' and not coalesce((v_pv.dados ->> 'forte')::boolean, false) then
            -- Linha 2b: fora de mesmo cliente com família idêntica, o dono lê as linhas antes do PIN. O corte pelo teto de 3.500 é de _retorno_cartao_texto.
            for r in select l.* from public.retorno_previa_linhas l where l.previa_id = v_pv.id order by l.ordem limit v_cfg.previa_max_linhas loop
              v_f3_linhas := v_f3_linhas || format('   · %s · %s × R$ %s · %s', left(r.nome, 40), public._retorno_qtd(r.quantidade),
                                                   public._retorno_brl(r.preco), public._retorno_rotulo_do_preco(r.preco_fonte, r.preco_em, true));
            end loop;
          end if;
        elsif jsonb_array_length(v_unidades) >= 2 then
          -- Linha 4: 2 ou mais unidades e nenhuma definida.
          for i in 1 .. least(jsonb_array_length(v_unidades), 4) loop
            v_nomes_un := v_nomes_un || format('*%s %s* %s', p_n, (array['C', 'F', 'G', 'H'])[i], v_unidades -> (i - 1) ->> 'nome');
            v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', (array['C', 'F', 'G', 'H'])[i], 'acao', 'unidade',
              'vessel_id', v_unidades -> (i - 1) ->> 'vessel_id', 'rotulo', v_unidades -> (i - 1) ->> 'nome'));
          end loop;
          v_f3_linhas := v_f3_linhas || ('   Qual unidade? ' || array_to_string(v_nomes_un, ' · '));
        elsif v_cli is not null then
          -- Linha 5: cliente no cadastro, inclusive provisório, sem unidade.
          v_f3_linhas := v_f3_linhas || format('   Falta cadastrar a unidade: diga o nome e o tipo (*cadastra a lancha Brisa no %s*) ou crie no app, e mande *retorno*.', p_n);
        else
          -- Linha 5b: número novo sem cadastro.
          v_f3_linhas := v_f3_linhas || '   Cadastro incompleto: o orçamento só sai depois que ele responder.'::text;
        end if;

        -- C23: só o que existe. *ver N* só com proposta viva.
        v_pedacos := v_pedacos || format('*%s L* precisa ver no local', p_n);
        v_pedacos := v_pedacos || format('*ver %s* mostra os itens', p_n);
        v_f3_linhas := v_f3_linhas || ('   ' || array_to_string(v_pedacos, ' · '));

      elsif v_int_ok then
        -- Linhas 6a a 6d: sem proposta viva (sem parecido, ou proposta só em sombra). Nunca diz "sem parecido".
        v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'L', 'acao', 'responder', 'modelo', 'modelo_ver_no_local', 'os_id', null, 'rotulo', 'precisa ver no local'));
        if v_cli is null then
          v_f3_linhas := array[format('   Cadastro incompleto: o orçamento aparece aqui quando ele responder. *%s L* precisa ver no local.', p_n)];
        elsif v_vessel is not null then
          v_f3_linhas := array[format('   Dite o orçamento em áudio. *%s L* precisa ver no local.', p_n)];
        elsif jsonb_array_length(v_unidades) >= 2 then
          for i in 1 .. least(jsonb_array_length(v_unidades), 4) loop
            v_nomes_un := v_nomes_un || format('*%s %s* %s', p_n, (array['C', 'F', 'G', 'H'])[i], v_unidades -> (i - 1) ->> 'nome');
            v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', (array['C', 'F', 'G', 'H'])[i], 'acao', 'unidade',
              'vessel_id', v_unidades -> (i - 1) ->> 'vessel_id', 'rotulo', v_unidades -> (i - 1) ->> 'nome'));
          end loop;
          v_f3_linhas := array[format('   Qual unidade? %s. Depois dite o orçamento em áudio. *%s L* precisa ver no local.', array_to_string(v_nomes_un, ' · '), p_n)];
        else
          v_f3_linhas := array[format('   Falta cadastrar a unidade: diga o nome e o tipo (*cadastra a lancha Brisa no %s*) ou crie no app, e mande *retorno*.', p_n),
                               format('   *%s L* precisa ver no local', p_n)];
        end if;
      end if;
    end if;
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
  -- F3 (P5): as linhas da proposta vêm depois das frases da F2 (a letra D do número novo fica) e antes do "Ele já recebeu".
  if cardinality(v_f3_linhas) > 0 then
    v_linhas := v_linhas || to_jsonb(v_f3_linhas);
  end if;
  if v_k >= 1 then
    v_linhas := v_linhas || jsonb_build_array(format('   Ele já recebeu %s automáticas hoje.', v_k));
  end if;

  return jsonb_build_object(
    'tipo_item', v_tipo, 'modelo_tipo', v_modelo, 'service_order_id', coalesce(v_so_f3::text, v_os ->> 'id'), 'texto_mostrado', v_texto,
    'opcoes', v_opcoes, 'fatos', v_retrato, 'linhas', v_linhas,
    'previa_id', v_previa, 'acao_sim', v_acao,   -- F3 (P5)
    -- F3 (P5): com acao_sim, o hash inclui a proposta (efetiva) ou o total do rascunho, e v_k sai: um adiamento automático com o cartão aberto não dá fato_mudou.
    'hash', md5(concat_ws('|', v_ab.phone_normalized, v_modelo, v_texto, v_retrato::text,
                          case when v_acao is null then v_k end, v_hash_f3, v_so_total)));
end;
$$;

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
         texto_mostrado = v ->> 'texto_mostrado', opcoes = v -> 'opcoes', fatos = v -> 'fatos', hash = v ->> 'hash', escolha = null,
         previa_id = (v ->> 'previa_id')::uuid, acao_sim = v ->> 'acao_sim'   -- F3 (P5): senão a letra B e o ditado perderiam a marca
   where i.id = p_item;
  update public.retorno_cartoes c
     set dados = jsonb_set(c.dados, array['linhas', v_i.n::text], v -> 'linhas', true)
   where c.id = v_i.cartao_id;
  update public.retorno_cartoes c set texto = public._retorno_cartao_texto(c.id, null) where c.id = v_i.cartao_id;
  return v;
end;
$$;

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
  v_atual jsonb;   -- F3 (P5)
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

  -- F3 (P5): o *sim <PIN>* vale sobre o que o dono leu. Compara também a proposta e o orçamento, que o hash sozinho não pega (outro previa_id com as mesmas linhas).
  -- Item com texto_ditado segue a regra da F2: o executor manda só o texto ditado, e a proposta não entra.
  if p_executar and v_i.acao_sim is not null and v_i.modelo_tipo is null and v_i.texto_ditado is null then
    v_atual := public._retorno_item_montar(v_ab.id, v_i.n, p_agora);
    if (v_atual ->> 'hash') is distinct from v_i.hash
       or (v_atual ->> 'previa_id')::uuid is distinct from v_i.previa_id
       or (v_atual ->> 'service_order_id')::uuid is distinct from v_i.service_order_id
       or (v_i.acao_sim = 'orcar' and not exists (select 1 from public.retorno_previa p where p.id = v_i.previa_id and p.estado = 'proposta')) then
      return jsonb_build_object('ok', false, 'motivo', 'fato_mudou',
        'texto', format('o %s mudou desde o cartão: mande *retorno* para ver de novo; não mandei', v_i.n));
    end if;
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
  -- F3 (P5)
  c_fuso constant text := 'America/Sao_Paulo';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_pv public.retorno_previa;
  v_cli uuid;
  v_unidades jsonb;
  v_lista text;
  v_validade text;
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
   where c.id = v_cartao and l.ord > 1
     and l.linha not like '   · %';   -- F3 (P5): as linhas C30 já vêm na lista completa, logo acima

  -- F3 (P5): a proposta viva, linha a linha, com o rótulo honesto de cada preço. Sem proposta, *ver* continua como na F2.
  if v_cfg.previa_ditado_ligado or v_cfg.previa_modo = 'ligado' then
    select p.* into v_pv from public.retorno_previa p where p.abertura_id = v_item.abertura_id and p.estado = 'proposta' limit 1;
    if found then
      select string_agg(l.ordem || '. ' || l.nome
                        || case when l.preco is not null then ' · ' || public._retorno_qtd(l.quantidade) || ' × R$ ' || public._retorno_brl(l.preco) else '' end
                        || ' · ' || public._retorno_rotulo_do_preco(l.preco_fonte, l.preco_em),
                        E'\n' order by l.ordem)
        into v_lista
        from public.retorno_previa_linhas l where l.previa_id = v_pv.id;
      v_validade := public._retorno_quando(public._retorno_validade_do_envio(v_agora), (v_agora at time zone c_fuso)::date);
      v_lista := concat_ws(E'\n',
        case when v_pv.fonte_numero is not null
             then format('Proposta com base no %s (%s):', v_pv.fonte_numero, public._retorno_mes_aa((v_pv.fonte_em at time zone c_fuso)::date))
             else 'Proposta ditada:' end,
        v_lista,
        format('Total: R$ %s · vale até %s, contado do envio', public._retorno_brl(v_pv.total), v_validade));
      v_cli := (public._retorno_cadastro_do_caso(v_item.abertura_id) ->> 'client_id')::uuid;
      v_unidades := public._retorno_unidades_do_cliente(v_cli);
      if v_pv.vessel_id is null and (public._retorno_unidade_do_caso(v_item.abertura_id, v_cli, v_agora) ->> 'vessel_id') is null
         and jsonb_array_length(v_unidades) >= 2 then
        v_lista := v_lista || E'\n' || 'Unidades: '
          || (select string_agg(format('%s. %s', u ->> 'numero', u ->> 'nome'), ' · ' order by (u ->> 'numero')::integer) from jsonb_array_elements(v_unidades) u);
      end if;
    end if;
  end if;

  perform public._retorno_toque('ver', v_cartao, v_item.abertura_id, v_agora);

  return jsonb_build_object('ok', true,
    'texto', concat_ws(E'\n', format('%s · %s', public._retorno_rotulo(v_item.abertura_id, v_agora),
                                     public._retorno_prazo_curto(v_item.abertura_id, v_agora)),
                       v_recebidas, v_lista, v_extras),
    'historico', jsonb_build_object('user', format('(ver %s)', p_n),
                                    'assistant', format('(mostrei o caso %s ao dono)', p_n)));
end;
$$;

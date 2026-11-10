-- Retorno rápido ao cliente, F4 (P7): o painel, o pátio, a pausa, o eco, a ativação, a releitura do veto e o vigia do
-- parceiro. Nada liga aqui.
--
-- 1. _parceiro_fato_da_os: o fato de uma OS pelas mesmas fontes de retorno_fatos_do_contato (lista positiva da F2), sem
--    resolver por telefone (o cliente do parceiro pode não ter). previsao, descricao da peça e o nome da unidade nunca saem.
-- 2. _parceiro_cliente_ouviu: "o parceiro nunca sabe mais que o cliente". O marco ouvido pelo cliente (retorno_saidas
--    modelo_* e agenda_cliente_mensagens enviadas; a incerta não conta) ou dito pelo dono (parceiro_cliente_sabe).
-- 3. parceiro_linhas: uma linha por OS visível, pela tabela de P7.2 (pronto, peca_chegou, aguarda_peca, em_servico,
--    orcamento, andamento, andamento_sem_data ou fora por sem_fato), com a data de cada estado no fuso de Brasília e nunca
--    no futuro. Cada OS roda em bloco próprio: a que dá erro sai sozinha (fora_por = 'erro'). Nome nulo ou que colide com
--    outro cliente do parceiro: fora_por = 'nome_ambiguo'. Só as linhas que saem ganham n, na ordem dos estados.
-- 4. parceiro_estados_sombra: só contagens por estado, sem as condições 6 e 7 da regra de ouro; nunca gera saída.
-- 5. parceiro_painel_montar e parceiro_painel_rodada: o painel do dia (17:30), sem_mudanca fora de sexta, o estado pelo
--    modo (sombra, aguardando com o item painel na fila, aprovado), as saídas entre 17:45 e 18:30 por número que recebe o
--    resumo, e o aguardando que vence às 18:30 sem sair.
-- 6. parceiro_patio_pedido: o *pátio* pedido. Fora de 07:00–21:59, acima de patio_dia_max ou com segura pátio: recusada,
--    sem resposta. Sem linha: P10 vazio. Com linhas: o item patio na fila (patio_nivel 'cartao') ou o P10 direto.
-- 7. parceiro_eco_rodada: o eco de pronto, peça que chegou e atraso (só pode_atrasar com variante peca), depois de o
--    cliente ouvir, a cliente com telefone e OS visível; um por OS e marco.
-- 8. parceiro_ler_mensagem (C-LER): o leitor único de palavras externas (NÃO <sigla>, a resposta que pode ser um "não",
--    *pátio*, *pausar*, *retomar*). O NÃO <sigla> vale em qualquer parceiro_modo; as palavras do parceiro, não no desligado.
-- 9. parceiro_ativar e parceiro_ativacao_rodada (P01, uma vez por número), parceiro_reler_vetos (a rede do webhook que
--    caiu, só a linha do veto) e parceiro_vigia (cada passo isolado; os de onda posterior só com a função no banco).
--
-- Sem dado: só funções novas. Nada é chamado enquanto o cron não chamar parceiro_vigia (P14) e o webhook não chamar
-- parceiro_ler_mensagem (P13). Com parceiro_modo = 'desligado' (o padrão), o vigia só relê o veto.
-- Reverter: drop function das funções desta migration. As tabelas da P1 ficam.

-- ── 1. O fato da OS e o que o cliente ouviu ─────────────────────────────────────────────────────────────────────────────

-- lista positiva (a mesma de retorno_fatos_do_contato, 20261123100200): service_orders, vessels (só para nada: o nome da
-- unidade não sai), os_material (sem previsao e sem descricao na saída), agenda_acoes, agenda_alocacoes,
-- agenda_disponibilidade, os_tarefas (a etapa só no fato, nunca na linha), os_tarefas_dia, agenda_cliente_mensagens.
create or replace function public._parceiro_fato_da_os(p_os uuid, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_cfg public.retorno_config := public._retorno_cfg();
  r record;
  v_liberada boolean;
  v_pronto jsonb;
  v_sem_palavra jsonb;
  v_servico jsonb;
  v_chegou jsonb;
  v_aguarda jsonb;
  v_liberado jsonb;
  v_ouviu timestamptz;
  v_etapa text;
  v_conf timestamptz;
  v_faltam boolean;
  v_n integer;
  v_em date;
  v_fonte text;
begin
  if v_cfg.id is null then
    raise exception 'parceiro_fato_da_os: sem retorno_config' using errcode = '55000';
  end if;

  select so.id, so.service_order_number, so.vessel_id, so.status, so.check_in_at, so.delivered_at, so.liberado_retirada_em,
         so.check_out_at as concluida_desde, so.merged_into_id, so.created_at,
         exists (select 1 from public.os_carteira(v_hoje) k where k.service_order_id = so.id) as na_carteira,
         p.criada_em as palavra_em, p.origem as palavra_fonte
    into r
    from public.service_orders so
    left join lateral (
      select a.criada_em, a.origem
        from public.agenda_acoes a
       where a.service_order_id = so.id
         and a.tipo = 'concluir'
         and a.executada
         and a.desfeita_em is null
         and a.origem in ('dono', 'equipe')
         and a.criada_em <= v_agora
       order by a.criada_em desc
       limit 1) p on true
   where so.id = p_os;
  if not found or r.merged_into_id is not null or r.created_at > v_agora then
    return null;
  end if;

  v_liberada := r.liberado_retirada_em is not null
                and r.liberado_retirada_em <= v_agora
                and r.liberado_retirada_em > v_agora - v_cfg.liberado_validade
                and r.delivered_at is null
                and (r.status in ('completed', 'invoiced') or r.na_carteira);

  if r.palavra_em is not null and r.palavra_em >= v_agora - v_cfg.fato_pronto_idade then
    v_pronto := jsonb_build_object('valor', true, 'fonte', r.palavra_fonte, 'em', r.palavra_em,
                                   'idade_h', floor(extract(epoch from v_agora - r.palavra_em) / 3600)::integer);
  elsif r.status in ('completed', 'invoiced') and r.palavra_em is null then
    v_sem_palavra := jsonb_build_object('desde', (r.concluida_desde at time zone c_fuso)::date);
  end if;

  -- A etapa só com as tarefas ligadas (fica no fato; a linha do parceiro nunca a usa).
  select t.texto into v_etapa
    from public.os_tarefas_dia d
    join public.os_tarefas t on t.id = d.tarefa_id
   where d.service_order_id = r.id and d.dia = v_hoje and d.modo = 'ligado' and t.estado <> 'cancelada'
   order by d.posicao nulls last, d.id
   limit 1;

  if r.check_in_at is not null and r.check_in_at <= v_agora and r.check_in_at > v_agora - v_cfg.fato_servico_idade then
    v_servico := jsonb_build_object('valor', true, 'fonte', 'check_in', 'em', r.check_in_at, 'etapa', v_etapa);
  else
    select max(c.criado_em) into v_conf
      from public.agenda_alocacoes al
      join public.agenda_disponibilidade c
        on c.payee_id = al.payee_id and c.situacao = 'confirmada' and c.substituida_em is null and c.periodo @> v_hoje
     where al.service_order_id = r.id
       and al.dia = v_hoje
       and al.estado in ('publicada', 'fixada')
       and al.tipo <> 'reserva'
       and c.criado_em <= v_agora;
    if v_conf is not null then
      v_servico := jsonb_build_object('valor', true, 'fonte', 'tecnico', 'em', v_conf, 'etapa', v_etapa);
    end if;
  end if;

  select exists (select 1 from public.os_material m
                  where m.service_order_id = r.id and m.critico and m.situacao in ('falta', 'comprado', 'a_caminho'))
    into v_faltam;

  select count(*), max(m.chegou_em), (array_agg(m.fonte order by m.chegou_em desc, m.id))[1]
    into v_n, v_em, v_fonte
    from public.os_material m
   where m.service_order_id = r.id
     and m.critico
     and m.situacao = 'na_mao'
     and m.fonte in ('dono', 'nfe', 'oc', 'fornecedor')
     and m.chegou_em <= v_hoje
     and m.chegou_em >= ((v_agora - v_cfg.fato_peca_idade) at time zone c_fuso)::date;
  if v_n > 0 then
    v_chegou := jsonb_build_object('valor', true, 'fonte', v_fonte, 'em', v_em, 'linhas', v_n, 'faltam_outras', v_faltam);
  end if;

  if v_faltam then
    -- a ordem é a da F2 (pela descrição), mas a descrição não sai
    select jsonb_agg(jsonb_build_object('id', m.id, 'situacao', m.situacao,
                                        'desde', coalesce(m.comprado_em, (m.atualizado_em at time zone c_fuso)::date))
                     order by m.descricao, m.id)
      into v_aguarda
      from public.os_material m
     where m.service_order_id = r.id and m.critico and m.situacao in ('falta', 'comprado', 'a_caminho');
    v_aguarda := jsonb_build_object('valor', true, 'linhas', v_aguarda);
  end if;

  if v_liberada then
    v_liberado := jsonb_build_object('em', r.liberado_retirada_em, 'vale_ate', r.liberado_retirada_em + v_cfg.liberado_validade);
  end if;

  select max(a.enviada_em) into v_ouviu
    from public.agenda_cliente_mensagens a
   where a.service_order_id = r.id
     and a.tipo in ('material_chegou', 'nova_data')
     and a.enviada_em <= v_agora;

  return jsonb_build_object(
    'id', r.id, 'numero', r.service_order_number, 'status', r.status,
    'fatos', jsonb_build_object('pronto', v_pronto, 'em_servico', v_servico, 'peca_chegou', v_chegou, 'aguarda_peca', v_aguarda,
                                'liberado', v_liberado, 'concluida_sem_palavra', v_sem_palavra, 'ouviu_material', v_ouviu));
end;
$$;

comment on function public._parceiro_fato_da_os(uuid, timestamptz) is
  'Retorno F4 (P7.1): o fato de uma OS, pelas mesmas fontes e regras de retorno_fatos_do_contato (F2), sem resolver por telefone. Igual ao item da F2 sem bem (o nome da unidade), sem previsao e sem a descricao das peças que faltam. Nulo para OS agrupada, inexistente ou criada depois de p_agora. Só lê; erro sobe.';

revoke all on function public._parceiro_fato_da_os(uuid, timestamptz) from public, anon, authenticated;

-- O cliente ouviu o marco? A hora mais recente, até agora: pronto (modelo_pronto; agenda pronto e pronto_lembrete),
-- peca_chegou (modelo_peca_chegou; agenda material_chegou), aguarda_peca (modelo_aguarda_peca; agenda pode_atrasar
-- variante peca), atraso (só agenda pode_atrasar variante peca). Em pronto, peca_chegou e aguarda_peca conta também a
-- palavra do dono (parceiro_cliente_sabe). Cliente sem telefone: só essa palavra. Marco fora da lista: nulo.
create or replace function public._parceiro_cliente_ouviu(p_os uuid, p_marco text, p_agora timestamptz)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cl uuid;
  v_sabe timestamptz;
  v_saida timestamptz;
  v_agenda timestamptz;
begin
  if p_os is null or p_marco is null or p_marco not in ('pronto', 'peca_chegou', 'aguarda_peca', 'atraso') then
    return null;
  end if;
  select so.client_id into v_cl from public.service_orders so where so.id = p_os;
  if not found then
    return null;
  end if;
  if p_marco in ('pronto', 'peca_chegou', 'aguarda_peca') then
    select cs.em into v_sabe
      from public.parceiro_cliente_sabe cs
     where cs.service_order_id = p_os and cs.marco = p_marco and cs.em <= v_agora;
  end if;
  if public._parceiro_fone_do_cliente(v_cl) is null then
    return v_sabe;
  end if;

  if p_marco in ('pronto', 'peca_chegou', 'aguarda_peca') then
    select max(s.enviada_em) into v_saida
      from public.retorno_saidas s
     where s.estado = 'enviada'
       and s.enviada_em <= v_agora
       and s.tipo = 'modelo_' || p_marco
       and s.dados ->> 'os_id' = p_os::text;
  end if;
  select max(a.enviada_em) into v_agenda
    from public.agenda_cliente_mensagens a
   where a.service_order_id = p_os
     and a.enviada_em <= v_agora
     and ((p_marco = 'pronto' and a.tipo in ('pronto', 'pronto_lembrete'))
          or (p_marco = 'peca_chegou' and a.tipo = 'material_chegou')
          or (p_marco in ('aguarda_peca', 'atraso') and a.tipo = 'pode_atrasar' and a.variante = 'peca'));
  return greatest(v_saida, v_agenda, v_sabe);
end;
$$;

comment on function public._parceiro_cliente_ouviu(uuid, text, timestamptz) is
  'Retorno F4 (P7.1): a hora mais recente (até p_agora) em que o cliente ouviu o marco (pronto, peca_chegou, aguarda_peca, atraso) por retorno_saidas modelo_* enviada ou agenda_cliente_mensagens enviada (atraso: só pode_atrasar/peca), ou em que o dono disse que ele sabe (parceiro_cliente_sabe, menos atraso). Cliente sem telefone: só a palavra do dono. Nulo = não ouviu.';

revoke all on function public._parceiro_cliente_ouviu(uuid, text, timestamptz) from public, anon, authenticated;

-- ── 2. A linha do painel (P7.2) ─────────────────────────────────────────────────────────────────────────────────────────

-- A linha de um vínculo, sem o nome: {interessado_id, service_order_id, client_id, estado, desde, rotulo, retida_por,
-- fora_por}. A primeira que serve, na ordem de P7.2; o marco que o cliente não ouviu fica em retida_por, e a linha cai ao
-- estado seguinte. Toda data é o dia de Brasília e nunca passa de hoje. Erro sobe (quem chama isola a OS).
create or replace function public._parceiro_linha_da_os(p_interessado uuid, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_oi public.os_interessados;
  v_so record;
  v_f jsonb;
  v_fatos jsonb;
  v_estado text;
  v_desde date;
  v_retida text;
  v_fora text;
  v_ouviu_peca timestamptz;
  v_d1 date;
  v_d2 date;
  v_d3 date;
begin
  select * into v_oi from public.os_interessados oi where oi.id = p_interessado;
  if not found then
    raise exception using errcode = '22023', message = 'parceiro_linha_da_os: vínculo desconhecido';
  end if;
  select so.service_order_number, so.status, so.origem_parceiro_id, so.check_in_at, so.converted_to_os_at, so.signed_at
    into v_so
    from public.service_orders so where so.id = v_oi.service_order_id;

  v_f := public._parceiro_fato_da_os(v_oi.service_order_id, v_agora);
  v_fatos := coalesce(v_f -> 'fatos', '{}'::jsonb);

  -- 1. pronto: a palavra do dono ou da equipe, e o cliente ouviu
  if jsonb_typeof(v_fatos -> 'pronto') = 'object' then
    if public._parceiro_cliente_ouviu(v_oi.service_order_id, 'pronto', v_agora) is not null then
      v_estado := 'pronto';
    else
      v_retida := 'pronto';
    end if;
  end if;
  -- 2. peca_chegou: até fato_peca_idade, o cliente ouviu, e com a data
  v_ouviu_peca := public._parceiro_cliente_ouviu(v_oi.service_order_id, 'peca_chegou', v_agora);
  if v_estado is null and jsonb_typeof(v_fatos -> 'peca_chegou') = 'object' then
    if v_ouviu_peca is not null then
      v_desde := nullif(v_fatos -> 'peca_chegou' ->> 'em', '')::date;
      if v_desde > v_hoje then
        v_desde := null;
      end if;
      if v_desde is not null then
        v_estado := 'peca_chegou';
      end if;
    else
      v_retida := coalesce(v_retida, 'peca_chegou');
    end if;
  end if;
  -- 3. aguarda_peca: a maior desde entre as que faltam (sem data, a linha sai sem o trecho da data)
  if v_estado is null and jsonb_typeof(v_fatos -> 'aguarda_peca') = 'object' then
    if public._parceiro_cliente_ouviu(v_oi.service_order_id, 'aguarda_peca', v_agora) is not null then
      v_estado := 'aguarda_peca';
      select max(nullif(l ->> 'desde', '')::date) into v_desde
        from jsonb_array_elements(case when jsonb_typeof(v_fatos -> 'aguarda_peca' -> 'linhas') = 'array'
                                       then v_fatos -> 'aguarda_peca' -> 'linhas' else '[]'::jsonb end) l
       where nullif(l ->> 'desde', '')::date <= v_hoje;
    else
      v_retida := coalesce(v_retida, 'aguarda_peca');
    end if;
  end if;
  -- 4. em_servico
  if v_estado is null and jsonb_typeof(v_fatos -> 'em_servico') = 'object' then
    v_estado := 'em_servico';
    v_desde := null;
  end if;
  -- 5. orcamento: o rascunho pedido por este parceiro
  if v_estado is null and v_so.status = 'draft' and v_so.origem_parceiro_id = v_oi.parceiro_id then
    v_estado := 'orcamento';
    v_desde := null;
  end if;
  -- 6 a 8. andamento (com data), andamento_sem_data (só em in_progress) ou fora
  if v_estado is null then
    v_d1 := case when v_so.check_in_at <= v_agora then (v_so.check_in_at at time zone c_fuso)::date end;
    if v_ouviu_peca is not null then
      select max(m.chegou_em) into v_d2
        from public.os_material m
       where m.service_order_id = v_oi.service_order_id and m.chegou_em <= v_hoje;
    end if;
    v_d3 := case when coalesce(v_so.converted_to_os_at, v_so.signed_at) <= v_agora
                 then (coalesce(v_so.converted_to_os_at, v_so.signed_at) at time zone c_fuso)::date end;
    v_desde := greatest(case when v_d1 <= v_hoje then v_d1 end,
                        case when v_d2 <= v_hoje then v_d2 end,
                        case when v_d3 <= v_hoje then v_d3 end);
    if v_desde is not null then
      v_estado := 'andamento';
    elsif v_so.status = 'in_progress' then
      v_estado := 'andamento_sem_data';
    else
      v_fora := 'sem_fato';
    end if;
  end if;

  return jsonb_build_object('interessado_id', v_oi.id, 'service_order_id', v_oi.service_order_id, 'client_id', v_oi.client_id,
                            'estado', v_estado, 'desde', v_desde, 'rotulo', v_so.service_order_number,
                            'retida_por', v_retida, 'fora_por', v_fora);
end;
$$;

comment on function public._parceiro_linha_da_os(uuid, timestamptz) is
  'Retorno F4 (P7.2): o estado e a data de um vínculo pela tabela de P7.2, com retida_por (o marco que o cliente não ouviu) e fora_por sem_fato. Datas no dia de Brasília, nunca depois de hoje; o chegou_em só entra no andamento com o cliente tendo ouvido a peça. Não confere a regra de ouro nem o nome. Erro sobe.';

revoke all on function public._parceiro_linha_da_os(uuid, timestamptz) from public, anon, authenticated;

-- A impressão do painel: md5 das linhas que saem (fora_por nulo), só service_order_id, estado e desde. n, rotulo, retida_por
-- e as linhas fora não entram: mudar o nome no cadastro ou a ordem não é novidade.
create or replace function public._parceiro_impressao(p_linhas jsonb)
returns text
language sql
immutable
set search_path = public
as $$
  select coalesce(md5(string_agg((l ->> 'service_order_id') || ':' || coalesce(l ->> 'estado', '') || ':'
                                 || coalesce(to_char(nullif(l ->> 'desde', '')::date, 'YYYY-MM-DD'), ''),
                                 '|' order by l ->> 'service_order_id')), md5(''))
    from jsonb_array_elements(case when jsonb_typeof(p_linhas) = 'array' then p_linhas else '[]'::jsonb end) l
   where jsonb_typeof(l) = 'object' and l ->> 'fora_por' is null;
$$;

comment on function public._parceiro_impressao(jsonb) is
  'Retorno F4 (P7.2): md5 de service_order_id:estado:desde das linhas com fora_por nulo, na ordem do service_order_id. É o "mudou" do painel.';

revoke all on function public._parceiro_impressao(jsonb) from public, anon, authenticated;

-- As linhas do parceiro agora: uma por OS de parceiro_os_visiveis, cada uma no seu bloco (exceção = fora_por 'erro', e o
-- resto segue). Nome nulo ou que colide com outro cliente do parceiro (o mesmo "João S.", ou "João" sozinho):
-- fora_por 'nome_ambiguo'. Só as que saem ganham n, pelo estado e depois o número da OS. As fora ficam com n nulo, sem
-- texto. Chaves: n, interessado_id, service_order_id, estado, desde, rotulo, retida_por, fora_por.
create or replace function public.parceiro_linhas(p_parceiro uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  r record;
  v_l jsonb;
  v_todas jsonb := '[]'::jsonb;
  v_saem uuid[];
  v_outros text[];
  v_forma text;
  v_primeiro text;
  v_res jsonb := '[]'::jsonb;
begin
  for r in select * from public.parceiro_os_visiveis(p_parceiro, v_agora) loop
    begin
      v_l := public._parceiro_linha_da_os(r.interessado_id, v_agora);
      if v_l ->> 'fora_por' is null and public._parceiro_nome_curto(r.client_id) is null then
        v_l := v_l || jsonb_build_object('fora_por', 'nome_ambiguo');
      end if;
    exception when others then
      v_l := jsonb_build_object('interessado_id', r.interessado_id, 'service_order_id', r.service_order_id, 'client_id', r.client_id,
                                'estado', null, 'desde', null,
                                'rotulo', (select so.service_order_number from public.service_orders so where so.id = r.service_order_id),
                                'retida_por', null, 'fora_por', 'erro');
      perform public._retorno_log('parceiro_linhas', 'parceiro_linhas: ' || sqlerrm, 'error',
                                  jsonb_build_object('interessado', r.interessado_id, 'sqlstate', sqlstate));
    end;
    v_todas := v_todas || jsonb_build_array(v_l);
  end loop;

  -- A colisão de nomes (P4.2, item 4): os outros são os clientes do parceiro (em qualquer situação) fora das linhas que
  -- saem. Uma passada basta.
  v_saem := array(select distinct (l ->> 'client_id')::uuid from jsonb_array_elements(v_todas) l where l ->> 'fora_por' is null);
  v_outros := array(select distinct public._texto_simples(btrim(public._parceiro_nome_curto(oi.client_id)))
                      from public.os_interessados oi
                     where oi.parceiro_id = p_parceiro
                       and not (oi.client_id = any (v_saem))
                       and public._parceiro_nome_curto(oi.client_id) is not null);
  for v_l in select l from jsonb_array_elements(v_todas) l loop
    if v_l ->> 'fora_por' is null then
      v_forma := public._parceiro_nome_curto((v_l ->> 'client_id')::uuid);
      v_primeiro := public._agenda_nome_curto(v_forma);
      if public._texto_simples(btrim(v_forma)) = any (v_outros) or public._texto_simples(btrim(v_primeiro)) = any (v_outros) then
        v_l := v_l || jsonb_build_object('fora_por', 'nome_ambiguo');
      end if;
    end if;
    v_res := v_res || jsonb_build_array(v_l - 'client_id');
  end loop;

  -- A ordem e o n: só as que saem, pelo estado, o número da OS (collate "C") e o id.
  return (
    with x as (
      select l,
             case l ->> 'estado' when 'pronto' then 1 when 'peca_chegou' then 2 when 'aguarda_peca' then 3 when 'em_servico' then 4
                                 when 'orcamento' then 5 when 'andamento' then 6 when 'andamento_sem_data' then 7 else 9 end as ord,
             (l ->> 'fora_por') is null as sai
        from jsonb_array_elements(v_res) l
    ), y as (
      select x.*,
             case when x.sai then row_number() over (partition by x.sai order by x.ord, x.l ->> 'rotulo' collate "C",
                                                                                  x.l ->> 'service_order_id') end as n
        from x
    )
    select coalesce(jsonb_agg(jsonb_build_object('n', y.n, 'interessado_id', y.l -> 'interessado_id',
                                                 'service_order_id', y.l -> 'service_order_id', 'estado', y.l -> 'estado',
                                                 'desde', y.l -> 'desde', 'rotulo', y.l -> 'rotulo',
                                                 'retida_por', y.l -> 'retida_por', 'fora_por', y.l -> 'fora_por')
                              order by (not y.sai), y.n, y.l ->> 'rotulo' collate "C", y.l ->> 'service_order_id'), '[]'::jsonb)
      from y);
end;
$$;

comment on function public.parceiro_linhas(uuid, timestamptz) is
  'Retorno F4 (P7.2): as linhas do parceiro agora, uma por OS visível (parceiro_os_visiveis): [{n, interessado_id, service_order_id, estado, desde, rotulo, retida_por, fora_por}]. Exceção numa OS = fora_por erro; nome nulo ou colisão com outro cliente do parceiro = nome_ambiguo; sem fato = sem_fato. n só nas que saem, pela ordem dos estados; nenhuma linha tem texto.';

revoke all on function public.parceiro_linhas(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_linhas(uuid, timestamptz) to service_role;

-- A foto de estados para o portão de ligar (8.4): só contagens, sem as condições 6 e 7 (aviso e 24 h); nunca gera saída.
create or replace function public.parceiro_estados_sombra(p_parceiro uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  r record;
  v_l jsonb;
  v_chave text;
  v_estados jsonb := '{}'::jsonb;
  v_total integer := 0;
begin
  for r in
    select oi.id
      from public.os_interessados oi
     where oi.parceiro_id = p_parceiro
       and oi.situacao = 'confirmado'
       and oi.papel in ('indicou', 'contratante', 'pagador')
       and (public._parceiro_os_visivel(oi.id, v_agora, true) ->> 'visivel')::boolean is true
  loop
    begin
      v_l := public._parceiro_linha_da_os(r.id, v_agora);
      v_chave := coalesce(case when v_l ->> 'fora_por' is null then v_l ->> 'estado' end, 'fora_' || (v_l ->> 'fora_por'));
    exception when others then
      v_chave := 'fora_erro';
    end;
    v_estados := v_estados || jsonb_build_object(v_chave, coalesce((v_estados ->> v_chave)::integer, 0) + 1);
    v_total := v_total + 1;
  end loop;
  return jsonb_build_object('parceiro_id', p_parceiro, 'total', v_total, 'estados', v_estados);
end;
$$;

comment on function public.parceiro_estados_sombra(uuid, timestamptz) is
  'Retorno F4 (P7.1, 8.4): {parceiro_id, total, estados: {estado: n, fora_<motivo>: n}} dos vínculos confirmados que passam na regra de ouro sem as condições 6 e 7. Só contagens; nunca gera saída nem grava painel.';

revoke all on function public.parceiro_estados_sombra(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_estados_sombra(uuid, timestamptz) to service_role;

-- ── 3. O painel do dia ──────────────────────────────────────────────────────────────────────────────────────────────────

-- Monta o painel do parceiro no dia (só dia útil de segunda a sexta). Linha vazia (nenhuma que sai): não grava. mudou =
-- impressão diferente do último painel enviado (no caminho de sombra, do último enviado ou em sombra). Sem mudança e fora
-- de sexta: sem_mudanca. Estado: sombra (parceiro_modo sombra, ou ligado sem o tipo, sem item no cartão), aguardando
-- (ligado + fechamento: o item painel na fila, válido até painel_janela_fim) ou aprovado (ligado + sozinho). Um por dia.
create or replace function public.parceiro_painel_montar(p_parceiro uuid, p_dia date, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_pp public.parceiro_paineis;
  v_linhas jsonb;
  v_saem integer;
  v_imp text;
  v_ligado boolean;
  v_ultimo text;
  v_mudou boolean;
  v_estado text;
  v_id uuid;
begin
  if v_cfg.id is null or v_cfg.parceiro_modo = 'desligado' then
    return jsonb_build_object('ok', false, 'motivo', 'desligado');
  end if;
  if p_dia is null or extract(isodow from p_dia) not between 1 and 5 or not public.agenda_dia_util(p_dia) then
    return jsonb_build_object('ok', false, 'motivo', 'dia_nao_util');
  end if;
  if not exists (select 1 from public.parceiros pa where pa.id = p_parceiro and pa.ativo) then
    return jsonb_build_object('ok', false, 'motivo', 'parceiro_inativo');
  end if;
  select * into v_pp from public.parceiro_paineis pp where pp.parceiro_id = p_parceiro and pp.dia = p_dia;
  if found then
    return jsonb_build_object('ok', true, 'painel_id', v_pp.id, 'estado', v_pp.estado, 'ja_existia', true);
  end if;

  v_linhas := public.parceiro_linhas(p_parceiro, v_agora);
  select count(*) into v_saem from jsonb_array_elements(v_linhas) l where l ->> 'fora_por' is null;
  if v_saem = 0 then
    return jsonb_build_object('ok', true, 'gravado', false, 'motivo', 'sem_linha');
  end if;
  v_imp := public._parceiro_impressao(v_linhas);

  v_ligado := v_cfg.parceiro_modo = 'ligado' and 'parceiro_painel' = any (v_cfg.parceiro_tipos_ligados);
  select pp.impressao into v_ultimo
    from public.parceiro_paineis pp
   where pp.parceiro_id = p_parceiro
     and pp.dia < p_dia
     and (pp.estado = 'enviado' or (not v_ligado and pp.estado = 'sombra'))
   order by pp.dia desc
   limit 1;
  v_mudou := v_ultimo is distinct from v_imp;

  v_estado := case
    when not v_mudou and extract(isodow from p_dia) <> 5 then 'sem_mudanca'
    when not v_ligado then 'sombra'
    when v_cfg.painel_nivel = 'sozinho' then 'aprovado'
    else 'aguardando'
  end;

  insert into public.parceiro_paineis (parceiro_id, dia, estado, mudou, linhas, impressao, aprovado_em, criado_em)
  values (p_parceiro, p_dia, v_estado, v_mudou, v_linhas, v_imp, case when v_estado = 'aprovado' then v_agora end, v_agora)
  on conflict (parceiro_id, dia) do nothing
  returning id into v_id;
  if v_id is null then
    select * into v_pp from public.parceiro_paineis pp where pp.parceiro_id = p_parceiro and pp.dia = p_dia;
    return jsonb_build_object('ok', true, 'painel_id', v_pp.id, 'estado', v_pp.estado, 'ja_existia', true);
  end if;
  if v_estado = 'aguardando' then
    perform public._parceiro_fila_por('painel', p_parceiro, v_id, 'painel:' || v_id,
                                      (p_dia + v_cfg.painel_janela_fim) at time zone c_fuso,
                                      jsonb_build_object('dia', p_dia, 'painel_id', v_id));
  end if;
  return jsonb_build_object('ok', true, 'painel_id', v_id, 'estado', v_estado, 'mudou', v_mudou, 'linhas', v_saem,
                            'fora', jsonb_array_length(v_linhas) - v_saem);
end;
$$;

comment on function public.parceiro_painel_montar(uuid, date, timestamptz) is
  'Retorno F4 (P7.1): grava o painel do dia (um por parceiro e dia, só dia útil de seg a sex): sem_mudanca (sem mudança fora de sexta), sombra, aguardando (com o item painel na fila até painel_janela_fim) ou aprovado (sozinho). Sem linha que sai, não grava. Não cria saída: quem agenda é parceiro_painel_rodada.';

revoke all on function public.parceiro_painel_montar(uuid, date, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_painel_montar(uuid, date, timestamptz) to service_role;

-- A rodada do painel, no vigia: o aguardando vence às painel_janela_fim (e nada sai naquele dia); em dia útil, de
-- painel_fechamento_hora a painel_janela_fim monta o painel do dia de cada parceiro com número que recebe o resumo; de
-- painel_hora a painel_janela_fim agenda as saídas de todo painel aprovado (ou em sombra, com a chave de sombra), uma por
-- número que recebe o resumo, só com as linhas que saem.
create or replace function public.parceiro_painel_rodada(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_t time := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::time;
  v_cfg public.retorno_config := public._retorno_cfg();
  r record;
  n record;
  v_linhas jsonb;
  v_vencidos integer := 0;
  v_montados integer := 0;
  v_saidas integer := 0;
  v_erros integer := 0;
begin
  if v_cfg.id is null or v_cfg.parceiro_modo = 'desligado' then
    return jsonb_build_object('ok', true, 'rodou', false);
  end if;

  -- O aguardando sem resposta vence às painel_janela_fim (e o de dia anterior também).
  update public.parceiro_paineis pp
     set estado = 'vencido'
   where pp.estado = 'aguardando'
     and (pp.dia < v_hoje or (pp.dia = v_hoje and v_t >= v_cfg.painel_janela_fim));
  get diagnostics v_vencidos = row_count;

  if extract(isodow from v_hoje) not between 1 and 5 or not public.agenda_dia_util(v_hoje) then
    return jsonb_build_object('ok', true, 'rodou', true, 'vencidos', v_vencidos, 'motivo', 'dia_nao_util');
  end if;

  -- Monta o painel do dia, a partir das painel_fechamento_hora.
  if v_t >= v_cfg.painel_fechamento_hora and v_t < v_cfg.painel_janela_fim then
    for r in
      select pa.id
        from public.parceiros pa
       where pa.ativo
         and exists (select 1 from public.parceiro_numeros nn join public.parceiro_pessoas pe on pe.id = nn.pessoa_id and pe.ativo
                      where pe.parceiro_id = pa.id and nn.situacao = 'confirmado' and nn.recebe_painel)
         and not exists (select 1 from public.parceiro_paineis pp where pp.parceiro_id = pa.id and pp.dia = v_hoje)
       order by pa.criado_em, pa.id
    loop
      begin
        perform public.parceiro_painel_montar(r.id, v_hoje, v_agora);
        v_montados := v_montados + 1;
      exception when others then
        v_erros := v_erros + 1;
        perform public._retorno_log('parceiro_painel', 'parceiro_painel_rodada (montar): ' || sqlerrm, 'error',
                                    jsonb_build_object('parceiro', r.id, 'sqlstate', sqlstate));
      end;
    end loop;
  end if;

  -- As saídas do aprovado (e do painel em sombra, sempre com a chave de sombra), de painel_hora a painel_janela_fim.
  if v_t >= v_cfg.painel_hora and v_t < v_cfg.painel_janela_fim then
    for r in
      select pp.* from public.parceiro_paineis pp
        join public.parceiros pa on pa.id = pp.parceiro_id and pa.ativo
       where pp.dia = v_hoje and pp.estado in ('aprovado', 'sombra')
       order by pp.criado_em, pp.id
    loop
      begin
        v_linhas := (select coalesce(jsonb_agg(jsonb_build_object('n', (l ->> 'n')::integer, 'interessado_id', l -> 'interessado_id',
                                                                  'service_order_id', l -> 'service_order_id', 'estado', l -> 'estado',
                                                                  'desde', l -> 'desde')
                                               order by (l ->> 'n')::integer), '[]'::jsonb)
                       from jsonb_array_elements(r.linhas) l
                      where l ->> 'fora_por' is null and coalesce(l ->> 'n', '') ~ '^[0-9]{1,3}$');
        if jsonb_array_length(v_linhas) = 0 then
          continue;
        end if;
        for n in
          select nn.id
            from public.parceiro_numeros nn
            join public.parceiro_pessoas pe on pe.id = nn.pessoa_id and pe.ativo
           where pe.parceiro_id = r.parceiro_id and nn.situacao = 'confirmado' and nn.recebe_painel
           order by nn.criado_em, nn.id
        loop
          perform public.parceiro_agendar(
            'parceiro_painel', 'padrao', n.id, null,
            jsonb_build_object('painel_id', r.id, 'dia', r.dia, 'linhas', v_linhas,
                               'os_ids', (select jsonb_agg(l -> 'service_order_id' order by (l ->> 'n')::integer) from jsonb_array_elements(v_linhas) l),
                               'interessado_ids', (select jsonb_agg(l -> 'interessado_id' order by (l ->> 'n')::integer) from jsonb_array_elements(v_linhas) l)),
            greatest(v_agora, (v_hoje + v_cfg.painel_hora) at time zone c_fuso),
            'parceiro:painel:' || r.id || ':' || n.id || (case when r.estado = 'sombra' then ':sombra' else '' end),
            'resumo_parceiro');
          v_saidas := v_saidas + 1;
        end loop;
      exception when others then
        v_erros := v_erros + 1;
        perform public._retorno_log('parceiro_painel', 'parceiro_painel_rodada (saídas): ' || sqlerrm, 'error',
                                    jsonb_build_object('painel', r.id, 'sqlstate', sqlstate));
      end;
    end loop;
  end if;

  return jsonb_build_object('ok', v_erros = 0, 'rodou', true, 'vencidos', v_vencidos, 'montados', v_montados,
                            'saidas', v_saidas, 'erros', v_erros);
end;
$$;

comment on function public.parceiro_painel_rodada(timestamptz) is
  'Retorno F4 (P7.1): no vigia. aguardando → vencido às painel_janela_fim (nada sai naquele dia); de painel_fechamento_hora a painel_janela_fim, parceiro_painel_montar de cada parceiro ativo com número que recebe o resumo; de painel_hora a painel_janela_fim, parceiro_agendar (parceiro_painel, chave parceiro:painel:<painel>:<numero>, :sombra no painel em sombra) por número que recebe o resumo, só com as linhas que saem. Idempotente pela chave.';

revoke all on function public.parceiro_painel_rodada(timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_painel_rodada(timestamptz) to service_role;

-- ── 4. O pátio pedido ───────────────────────────────────────────────────────────────────────────────────────────────────

-- O *pátio* do parceiro. Fora de 07:00–21:59 (a janela da resposta imediata), com segura pátio ou acima de patio_dia_max
-- respostas no dia: registrada como recusada, sem resposta. Sem linha: P10 vazio (em qualquer nível). Com linhas:
-- patio_nivel 'cartao' põe o item patio na fila (patio:<numero>:<dia>, válido até 21:59; o 2º pedido do dia só atualiza
-- msg_id e a hora); 'direto' agenda o P10 com as linhas. A mesma mensagem duas vezes não responde duas vezes.
create or replace function public.parceiro_patio_pedido(p_numero uuid, p_msg uuid, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_desde timestamptz := ((coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date)::timestamp at time zone 'America/Sao_Paulo';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_num record;
  v_dedupe text;
  v_motivo text;
  v_n integer;
  v_linhas jsonb;
  v_id uuid;
  v_fila uuid;
begin
  if v_cfg.id is null or v_cfg.parceiro_modo = 'desligado' then
    return jsonb_build_object('ok', false, 'consumida', false, 'acao', 'nada', 'motivo', 'desligado');
  end if;
  select nn.id, nn.chave, nn.phone_normalized, pe.parceiro_id into v_num
    from public.parceiro_numeros nn
    join public.parceiro_pessoas pe on pe.id = nn.pessoa_id and pe.ativo
    join public.parceiros pa on pa.id = pe.parceiro_id and pa.ativo
   where nn.id = p_numero and nn.situacao = 'confirmado';
  if not found then
    return jsonb_build_object('ok', false, 'consumida', false, 'acao', 'nada', 'motivo', 'numero');
  end if;
  if p_msg is not null then
    v_dedupe := 'parceiro:patio:' || p_msg;
    select s.id into v_id from public.retorno_saidas s where s.dedupe_key in (v_dedupe, v_dedupe || ':sombra') limit 1;
    if v_id is not null then
      return jsonb_build_object('ok', true, 'consumida', true, 'acao', 'repetida', 'saida_id', v_id);
    end if;
  else
    v_dedupe := 'parceiro:patio:' || v_num.id || ':' || to_char(v_agora at time zone c_fuso, 'YYYYMMDDHH24MISS');
  end if;

  -- as respostas de pátio do dia a este número (a hora da decisão, ou a do pedido enquanto agendada; nunca criada_em,
  -- que é a hora real da gravação)
  select count(*) into v_n
    from public.retorno_saidas s
   where s.emissor = 'parceiro' and s.tipo = 'parceiro_patio' and s.chave = v_num.chave
     and s.estado in ('agendada', 'preparada', 'enviando', 'sombra', 'enviada', 'incerta')
     and coalesce(s.decidida_em, s.enviar_em) >= v_desde and coalesce(s.decidida_em, s.enviar_em) <= v_agora;
  v_motivo := case
    when not coalesce((public._retorno_janela('resposta_imediata', v_agora, v_num.chave) ->> 'dentro')::boolean, false) then 'fora_da_janela'
    when v_cfg.segura_patio then 'segura_patio'
    when v_n >= v_cfg.patio_dia_max then 'teto_patio'
  end;
  if v_motivo is not null then
    v_id := public.parceiro_agendar('parceiro_patio', null, v_num.id, null, jsonb_build_object('msg_id', p_msg, 'pedido_em', v_agora),
                                    v_agora, v_dedupe, 'resposta_imediata');
    if v_id is not null then
      perform public._parceiro_pegar_fechar(v_id, 'recusada', v_motivo, null, v_agora);
    end if;
    return jsonb_build_object('ok', true, 'consumida', true, 'acao', 'recusada', 'motivo', v_motivo, 'saida_id', v_id);
  end if;

  v_linhas := (select coalesce(jsonb_agg(jsonb_build_object('n', (l ->> 'n')::integer, 'interessado_id', l -> 'interessado_id',
                                                            'service_order_id', l -> 'service_order_id', 'estado', l -> 'estado',
                                                            'desde', l -> 'desde')
                                         order by (l ->> 'n')::integer), '[]'::jsonb)
                 from jsonb_array_elements(public.parceiro_linhas(v_num.parceiro_id, v_agora)) l
                where l ->> 'fora_por' is null and coalesce(l ->> 'n', '') ~ '^[0-9]{1,3}$');
  if jsonb_array_length(v_linhas) = 0 then
    v_id := public.parceiro_agendar('parceiro_patio', 'vazio', v_num.id, null,
                                    jsonb_build_object('msg_id', p_msg, 'sem_linhas', true, 'dia', v_hoje),
                                    v_agora, v_dedupe, 'resposta_imediata');
    return jsonb_build_object('ok', true, 'consumida', true, 'acao', 'vazio', 'saida_id', v_id);
  end if;
  if v_cfg.patio_nivel = 'cartao' then
    v_fila := public._parceiro_fila_por('patio', v_num.parceiro_id, v_num.id, 'patio:' || v_num.id || ':' || v_hoje,
                                        (v_hoje + time '21:59') at time zone c_fuso,
                                        jsonb_build_object('msg_id', p_msg, 'pedido_em', v_agora, 'dia', v_hoje));
    return jsonb_build_object('ok', true, 'consumida', true, 'acao', 'cartao', 'fila_id', v_fila);
  end if;
  v_id := public.parceiro_agendar('parceiro_patio', 'direto', v_num.id, null,
                                  jsonb_build_object('msg_id', p_msg, 'dia', v_hoje, 'linhas', v_linhas,
                                                     'os_ids', (select jsonb_agg(l -> 'service_order_id' order by (l ->> 'n')::integer) from jsonb_array_elements(v_linhas) l),
                                                     'interessado_ids', (select jsonb_agg(l -> 'interessado_id' order by (l ->> 'n')::integer) from jsonb_array_elements(v_linhas) l)),
                                  v_agora, v_dedupe, 'resposta_imediata');
  return jsonb_build_object('ok', true, 'consumida', true, 'acao', 'direto', 'saida_id', v_id);
end;
$$;

comment on function public.parceiro_patio_pedido(uuid, uuid, timestamptz) is
  'Retorno F4 (P7.1): o *pátio* do número confirmado. Fora da janela da resposta imediata (07:00–21:59), segura_patio ou acima de patio_dia_max: recusada com o motivo (fora_da_janela, segura_patio, teto_patio), sem resposta. Sem linha: parceiro_patio vazio. Com linhas: item patio na fila (cartao, até 21:59) ou parceiro_patio direto. Sempre consumida.';

revoke all on function public.parceiro_patio_pedido(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_patio_pedido(uuid, uuid, timestamptz) to service_role;

-- ── 5. O eco ────────────────────────────────────────────────────────────────────────────────────────────────────────────

-- O eco de pronto, peca_chegou e atraso: OS visível, cliente com telefone (sem telefone não há eco: o texto diz "o
-- cliente já foi avisado"; vai pelo repassar) e o cliente tendo ouvido o marco nas últimas 24 h. Um eco por OS e marco no
-- mesmo modo (o lembrete não repete o pronto; a sombra não gasta o real). Vai ao 1º número que recebe o resumo, com a
-- pessoa sem pausa. O teto (eco_dia_max) é a linha 4 do parceiro_pegar: os demais ficam só no painel.
create or replace function public.parceiro_eco_rodada(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  pa record;
  r record;
  v_num uuid;
  v_marco text;
  v_ouviu timestamptz;
  v_sombra boolean;
  v_n integer := 0;
  v_erros integer := 0;
begin
  if v_cfg.id is null or v_cfg.parceiro_modo = 'desligado' then
    return jsonb_build_object('ok', true, 'rodou', false);
  end if;
  v_sombra := v_cfg.parceiro_modo is distinct from 'ligado' or not ('parceiro_eco' = any (v_cfg.parceiro_tipos_ligados))
              or v_cfg.eco_modo is distinct from 'ligado';

  for pa in select p.id from public.parceiros p where p.ativo order by p.criado_em, p.id loop
    v_num := null;   -- o número é deste parceiro, nunca o da volta anterior
    select nn.id into v_num
      from public.parceiro_numeros nn
      join public.parceiro_pessoas pe on pe.id = nn.pessoa_id and pe.ativo
     where pe.parceiro_id = pa.id and nn.situacao = 'confirmado' and nn.recebe_painel
       and (pe.pausado_em is null or pe.pausado_em > v_agora)
     order by nn.criado_em, nn.id
     limit 1;
    if v_num is null then
      continue;
    end if;
    for r in select * from public.parceiro_os_visiveis(pa.id, v_agora) loop
      begin
        if public._parceiro_fone_do_cliente(r.client_id) is null then
          continue;
        end if;
        foreach v_marco in array array['pronto', 'peca_chegou', 'atraso'] loop
          v_ouviu := public._parceiro_cliente_ouviu(r.service_order_id, v_marco, v_agora);
          if v_ouviu is null or v_ouviu <= v_agora - interval '24 hours' then
            continue;
          end if;
          if exists (select 1 from public.retorno_saidas s
                      where s.emissor = 'parceiro' and s.tipo = 'parceiro_eco' and s.variante = v_marco
                        and s.dados -> 'os_ids' ->> 0 = r.service_order_id::text
                        and (s.dedupe_key ~ ':sombra(:|$)') = v_sombra) then
            continue;
          end if;
          perform public.parceiro_agendar(
            'parceiro_eco', v_marco, v_num, null,
            jsonb_build_object('os_ids', jsonb_build_array(r.service_order_id), 'interessado_ids', jsonb_build_array(r.interessado_id),
                               'service_order_id', r.service_order_id, 'marco', v_marco, 'ouvido_em', v_ouviu),
            v_agora,
            'parceiro:eco:' || r.service_order_id || ':' || v_marco || ':' || to_char(v_ouviu at time zone c_fuso, 'YYYY-MM-DD'),
            'aviso');
          v_n := v_n + 1;
        end loop;
      exception when others then
        v_erros := v_erros + 1;
        perform public._retorno_log('parceiro_eco', 'parceiro_eco_rodada: ' || sqlerrm, 'error',
                                    jsonb_build_object('interessado', r.interessado_id, 'sqlstate', sqlstate));
      end;
    end loop;
  end loop;
  return jsonb_build_object('ok', v_erros = 0, 'rodou', true, 'agendados', v_n, 'erros', v_erros);
end;
$$;

comment on function public.parceiro_eco_rodada(timestamptz) is
  'Retorno F4 (P7.1): no vigia. Para cada OS visível de cliente com telefone e cada marco (pronto, peca_chegou, atraso) que o cliente ouviu nas últimas 24 h, agenda parceiro_eco (chave parceiro:eco:<os>:<marco>:<dia em que ouviu>) ao 1º número que recebe o resumo, uma vez por OS e marco no mesmo modo. O teto é do parceiro_pegar.';

revoke all on function public.parceiro_eco_rodada(timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_eco_rodada(timestamptz) to service_role;

-- ── 6. O leitor de palavras externas ────────────────────────────────────────────────────────────────────────────────────

-- A normalização de _e_pedido_de_parar: _texto_simples, o que não é [a-z0-9 ] vira espaço, e os espaços se juntam.
create or replace function public._parceiro_texto_normal(p_corpo text)
returns text
language sql
immutable
set search_path = public
as $$
  select btrim(regexp_replace(regexp_replace(public._texto_simples(coalesce(p_corpo, '')), '[^a-z0-9 ]', ' ', 'g'), '\s+', ' ', 'g'));
$$;

comment on function public._parceiro_texto_normal(text) is
  'Retorno F4 (P7.1): a normalização do leitor (a de _e_pedido_de_parar): sem acento, minúsculo, só [a-z0-9 ] e um espaço entre as palavras.';

revoke all on function public._parceiro_texto_normal(text) from public, anon, authenticated;

-- A sigla do NÃO <sigla> (só de parceiro ativo), ou nula: ^nao( quero)?( a| o)? <sigla>( por favor| pf)?$ sobre o texto já
-- normalizado. A sigla é só de letras (check de parceiros.sigla), então entra no padrão sem escape.
create or replace function public._parceiro_sigla_do_veto(p_normal text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select pa.sigla
    from public.parceiros pa
   where pa.ativo
     and public._texto_simples(pa.sigla) ~ '^[a-z]{2,12}$'
     and coalesce(p_normal, '') ~ ('^nao( quero)?( a| o)? ' || public._texto_simples(pa.sigla) || '( por favor| pf)?$')
   order by pa.criado_em, pa.id
   limit 1;
$$;

comment on function public._parceiro_sigla_do_veto(text) is
  'Retorno F4 (P7.1): a sigla do parceiro ativo cujo NÃO <sigla> casa o texto normalizado, ou nulo.';

revoke all on function public._parceiro_sigla_do_veto(text) from public, anon, authenticated;

-- O leitor único de palavras externas (C-LER), chamado pelo webhook antes dos outros leitores. Só texto recebido de até
-- 60 caracteres. Cliente (ou ambíguo): NÃO <sigla> → parceiro_veto_dito (em qualquer parceiro_modo, desde que exista
-- parceiro ativo); "não"/"prefiro" sem sigla → parceiro_reter_resposta, sem consumir. Parceiro (fora do desligado):
-- *pátio*, *pausar*, *retomar*, consumidas. O resto: nada. Exceção: nada consumido (a mensagem segue o caminho de sempre, e
-- a releitura do veto pega o NÃO <sigla>). O corpo nunca vai a log.
create or replace function public.parceiro_ler_mensagem(p_msg uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_w record;
  v_txt text;
  v_q jsonb;
  v_sigla text;
  v_r jsonb;
  v_numero uuid;
  v_pessoa uuid;
begin
  begin
    select w.id, w.direction, w.phone_normalized, w.message_type, w.body into v_w
      from public.whatsapp_messages w where w.id = p_msg;
    if not found or v_w.direction is distinct from 'inbound' or v_w.message_type is distinct from 'text'
       or v_w.body is null or char_length(v_w.body) > 60 then
      return jsonb_build_object('consumida', false, 'acao', 'nada', 'motivo', 'fora');
    end if;
    if v_cfg.id is null or not exists (select 1 from public.parceiros pa where pa.ativo) then
      return jsonb_build_object('consumida', false, 'acao', 'nada', 'motivo', 'sem_parceiro');
    end if;
    v_txt := public._parceiro_texto_normal(v_w.body);
    v_q := public.quem_escreve(v_w.phone_normalized);

    if v_q ->> 'papel' in ('cliente', 'cliente_ambiguo') then
      v_sigla := public._parceiro_sigla_do_veto(v_txt);
      if v_sigla is not null then
        v_r := public.parceiro_veto_dito(v_q ->> 'chave', v_w.phone_normalized, v_sigla, v_w.id, v_agora);
        return jsonb_build_object('consumida', coalesce((v_r ->> 'consumida')::boolean, false), 'acao', 'veto', 'motivo', null);
      end if;
      if v_txt ~ '^(nao|prefiro)( |$)' then
        v_r := public.parceiro_reter_resposta(v_q ->> 'chave', v_w.id, v_agora);
        if coalesce((v_r ->> 'retidos')::integer, 0) > 0 then
          return jsonb_build_object('consumida', false, 'acao', 'retido', 'motivo', null);
        end if;
      end if;
      return jsonb_build_object('consumida', false, 'acao', 'nada', 'motivo', null);
    end if;

    if v_q ->> 'papel' = 'parceiro' and v_cfg.parceiro_modo is distinct from 'desligado' then
      v_numero := nullif(v_q ->> 'numero_id', '')::uuid;
      v_pessoa := nullif(v_q ->> 'pessoa_id', '')::uuid;
      if v_txt ~ '^(ver )?(o )?patio$' then
        v_r := public.parceiro_patio_pedido(v_numero, v_w.id, v_agora);
        return jsonb_build_object('consumida', true, 'acao', 'patio', 'motivo', v_r ->> 'acao');
      end if;
      if v_txt ~ '^(pausar|pausa)( painel| resumo)?$' then
        update public.parceiro_pessoas pe set pausado_em = coalesce(pe.pausado_em, v_agora) where pe.id = v_pessoa;
        perform public.parceiro_agendar('parceiro_pausa', 'pausar', v_numero, null, jsonb_build_object('msg_id', v_w.id),
                                        v_agora, 'parceiro:pausa:' || v_w.id, 'resposta_imediata');
        return jsonb_build_object('consumida', true, 'acao', 'pausar', 'motivo', null);
      end if;
      if v_txt ~ '^(retomar|retoma)( painel| resumo)?$' then
        update public.parceiro_pessoas pe set pausado_em = null where pe.id = v_pessoa;
        perform public.parceiro_agendar('parceiro_pausa', 'retomar', v_numero, null, jsonb_build_object('msg_id', v_w.id),
                                        v_agora, 'parceiro:pausa:' || v_w.id, 'resposta_imediata');
        return jsonb_build_object('consumida', true, 'acao', 'retomar', 'motivo', null);
      end if;
    end if;
    return jsonb_build_object('consumida', false, 'acao', 'nada', 'motivo', null);
  exception when others then
    perform public._retorno_log('parceiro_ler', 'parceiro_ler_mensagem: falhou', 'error',
                                jsonb_build_object('mensagem', p_msg, 'sqlstate', sqlstate));
    return jsonb_build_object('consumida', false, 'acao', 'nada', 'motivo', 'erro');
  end;
end;
$$;

comment on function public.parceiro_ler_mensagem(uuid, timestamptz) is
  'Retorno F4 (C-LER, P7.1): {consumida, acao, motivo}; acao em veto, retido, patio, pausar, retomar, nada. Cliente: NÃO <sigla> (qualquer parceiro_modo) e a retenção do "não" (sem consumir). Parceiro, fora do desligado: pátio, pausar, retomar (consumidas). Só texto recebido de até 60 caracteres. Erro: nada consumido.';

revoke all on function public.parceiro_ler_mensagem(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_ler_mensagem(uuid, timestamptz) to service_role;

-- A rede do webhook que caiu: as recebidas de texto dos últimos 10 minutos, de até 60 caracteres, sem veto gravado com o
-- id delas, passam só pela linha do veto (NÃO <sigla>). Nunca repete pátio, pausar, retomar ou retenção. Vale em qualquer
-- parceiro_modo. Idempotente (parceiro_veto_dito). O corpo fica dentro da função.
create or replace function public.parceiro_reler_vetos(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  w record;
  v_sigla text;
  v_q jsonb;
  v_n integer := 0;
  v_erros integer := 0;
begin
  if not exists (select 1 from public.parceiros pa where pa.ativo) then
    return jsonb_build_object('ok', true, 'vetos', 0);
  end if;
  for w in
    select m.id, m.phone_normalized, m.body
      from public.whatsapp_messages m
     where m.direction = 'inbound'
       and m.message_type = 'text'
       and m.occurred_at > v_agora - interval '10 minutes'
       and m.occurred_at <= v_agora
       and m.body is not null
       and char_length(m.body) <= 60
       and not exists (select 1 from public.parceiro_vetos v where v.whatsapp_message_id = m.id)
     order by m.occurred_at, m.id
  loop
    begin
      v_sigla := public._parceiro_sigla_do_veto(public._parceiro_texto_normal(w.body));
      if v_sigla is null then
        continue;
      end if;
      v_q := public.quem_escreve(w.phone_normalized);
      if coalesce(v_q ->> 'papel', '') not in ('cliente', 'cliente_ambiguo') then
        continue;
      end if;
      perform public.parceiro_veto_dito(v_q ->> 'chave', w.phone_normalized, v_sigla, w.id, v_agora);
      v_n := v_n + 1;
    exception when others then
      v_erros := v_erros + 1;
      perform public._retorno_log('parceiro_reler', 'parceiro_reler_vetos: falhou', 'error',
                                  jsonb_build_object('mensagem', w.id, 'sqlstate', sqlstate));
    end;
  end loop;
  return jsonb_build_object('ok', v_erros = 0, 'vetos', v_n, 'erros', v_erros);
end;
$$;

comment on function public.parceiro_reler_vetos(timestamptz) is
  'Retorno F4 (P7.1): a releitura do NÃO <sigla> das recebidas de texto dos últimos 10 min (até 60 caracteres) sem veto gravado com o id delas, por parceiro_veto_dito. Só a linha do veto; qualquer parceiro_modo; idempotente. O corpo não vai a log.';

revoke all on function public.parceiro_reler_vetos(timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_reler_vetos(timestamptz) to service_role;

-- ── 7. A ativação (P01) ─────────────────────────────────────────────────────────────────────────────────────────────────

-- Agenda a P01 uma vez por número confirmado que recebe o resumo (chave parceiro:ativacao:<numero>, :sombra em sombra).
-- p_autor nulo é o vigia; com valor, só o dono (42501).
create or replace function public.parceiro_ativar(p_parceiro uuid, p_autor uuid default null, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  n record;
  v_id uuid;
  v_saidas jsonb := '[]'::jsonb;
begin
  if p_autor is not null and p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    raise exception using errcode = '42501', message = 'parceiro_ativar: só o dono';
  end if;
  if v_cfg.id is null or v_cfg.parceiro_modo = 'desligado' then
    return jsonb_build_object('ok', false, 'motivo', 'desligado');
  end if;
  if not exists (select 1 from public.parceiros pa where pa.id = p_parceiro and pa.ativo) then
    return jsonb_build_object('ok', false, 'motivo', 'parceiro_inativo');
  end if;
  for n in
    select nn.id
      from public.parceiro_numeros nn
      join public.parceiro_pessoas pe on pe.id = nn.pessoa_id and pe.ativo
     where pe.parceiro_id = p_parceiro and nn.situacao = 'confirmado' and nn.recebe_painel
     order by nn.criado_em, nn.id
  loop
    v_id := public.parceiro_agendar('parceiro_ativacao', 'padrao', n.id, null, '{}'::jsonb, v_agora,
                                    'parceiro:ativacao:' || n.id, 'aviso');
    if v_id is not null then
      v_saidas := v_saidas || to_jsonb(v_id);
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'saidas', v_saidas);
end;
$$;

comment on function public.parceiro_ativar(uuid, uuid, timestamptz) is
  'Retorno F4 (P7.1): agenda a P01 (parceiro_ativacao, classe aviso) uma vez por número confirmado com recebe_painel, chave parceiro:ativacao:<numero> (com :sombra em sombra). p_autor nulo = vigia; com valor, só o dono (42501).';

revoke all on function public.parceiro_ativar(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_ativar(uuid, uuid, timestamptz) to service_role;

-- O chamador único de parceiro_ativar: cada parceiro ativo com número que recebe o resumo e ainda sem a chave real.
-- Em sombra grava a linha :sombra uma vez; ligado o tipo, o minuto seguinte cria a real, uma só.
create or replace function public.parceiro_ativacao_rodada(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  r record;
  v_n integer := 0;
  v_erros integer := 0;
begin
  if v_cfg.id is null or v_cfg.parceiro_modo = 'desligado' then
    return jsonb_build_object('ok', true, 'rodou', false);
  end if;
  for r in
    select pa.id
      from public.parceiros pa
     where pa.ativo
       and exists (select 1 from public.parceiro_numeros nn join public.parceiro_pessoas pe on pe.id = nn.pessoa_id and pe.ativo
                    where pe.parceiro_id = pa.id and nn.situacao = 'confirmado' and nn.recebe_painel
                      and not exists (select 1 from public.retorno_saidas s where s.dedupe_key = 'parceiro:ativacao:' || nn.id))
     order by pa.criado_em, pa.id
  loop
    begin
      perform public.parceiro_ativar(r.id, null, v_agora);
      v_n := v_n + 1;
    exception when others then
      v_erros := v_erros + 1;
      perform public._retorno_log('parceiro_ativacao', 'parceiro_ativacao_rodada: ' || sqlerrm, 'error',
                                  jsonb_build_object('parceiro', r.id, 'sqlstate', sqlstate));
    end;
  end loop;
  return jsonb_build_object('ok', v_erros = 0, 'rodou', true, 'parceiros', v_n, 'erros', v_erros);
end;
$$;

comment on function public.parceiro_ativacao_rodada(timestamptz) is
  'Retorno F4 (P7.1): no vigia, o chamador único de parceiro_ativar(id, null, agora) para cada parceiro ativo com número que recebe o resumo sem a saída de chave real parceiro:ativacao:<numero>.';

revoke all on function public.parceiro_ativacao_rodada(timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_ativacao_rodada(timestamptz) to service_role;

-- ── 8. O vigia do parceiro ──────────────────────────────────────────────────────────────────────────────────────────────

-- Chamado pelo cron retorno-minuto depois do retorno_vigia (P14). Cada passo isolado. Em qualquer modo: a releitura do
-- veto, o passo do cartão (P8) e a retenção das 04:00 (P14), os dois últimos só com a função no banco. Com
-- parceiro_modo = 'desligado' sai aí. Depois: aviso, ativação, painel, eco, PDF à mão e repassar (P9) e o pedido (P10),
-- os de migration posterior só com a função no banco (sem 42883 a cada minuto nas ondas antes delas).
create or replace function public.parceiro_vigia(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_local time := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::time;
  v_cfg public.retorno_config := public._retorno_cfg();
  v_passos jsonb := '{}'::jsonb;
  v_erros text[] := '{}'::text[];
  v_r jsonb;
begin
  if v_cfg.id is null then
    return jsonb_build_object('ok', true, 'rodou', false, 'motivo', 'sem_config');
  end if;

  -- Em qualquer modo.
  begin
    v_r := public.parceiro_reler_vetos(v_agora);
    v_passos := v_passos || jsonb_build_object('reler_vetos', v_r);
  exception when others then
    v_erros := v_erros || 'reler_vetos';
    perform public._retorno_log('parceiro_vigia', 'parceiro_vigia (reler_vetos): ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
  end;
  if to_regprocedure('public.parceiro_vigia_cartao(timestamptz)') is not null then
    begin
      v_r := public.parceiro_vigia_cartao(v_agora);
      v_passos := v_passos || jsonb_build_object('cartao', v_r);
    exception when others then
      v_erros := v_erros || 'cartao';
      perform public._retorno_log('parceiro_vigia', 'parceiro_vigia (cartao): ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
    end;
  end if;
  if v_local >= time '04:00' and v_local < time '04:01'
     and to_regprocedure('public.parceiro_retencao_rodada(timestamptz)') is not null then
    begin
      v_r := public.parceiro_retencao_rodada(v_agora);
      v_passos := v_passos || jsonb_build_object('retencao', v_r);
    exception when others then
      v_erros := v_erros || 'retencao';
      perform public._retorno_log('parceiro_vigia', 'parceiro_vigia (retencao): ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
    end;
  end if;

  if v_cfg.parceiro_modo = 'desligado' then
    return jsonb_build_object('ok', cardinality(v_erros) = 0, 'rodou', true, 'modo', 'desligado', 'passos', v_passos,
                              'erros', to_jsonb(v_erros));
  end if;

  begin
    v_passos := v_passos || jsonb_build_object('aviso', public.parceiro_aviso_rodada(v_agora));
  exception when others then
    v_erros := v_erros || 'aviso';
    perform public._retorno_log('parceiro_vigia', 'parceiro_vigia (aviso): ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
  end;
  begin
    v_passos := v_passos || jsonb_build_object('ativacao', public.parceiro_ativacao_rodada(v_agora));
  exception when others then
    v_erros := v_erros || 'ativacao';
    perform public._retorno_log('parceiro_vigia', 'parceiro_vigia (ativacao): ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
  end;
  begin
    v_passos := v_passos || jsonb_build_object('painel', public.parceiro_painel_rodada(v_agora));
  exception when others then
    v_erros := v_erros || 'painel';
    perform public._retorno_log('parceiro_vigia', 'parceiro_vigia (painel): ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
  end;
  begin
    v_passos := v_passos || jsonb_build_object('eco', public.parceiro_eco_rodada(v_agora));
  exception when others then
    v_erros := v_erros || 'eco';
    perform public._retorno_log('parceiro_vigia', 'parceiro_vigia (eco): ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
  end;
  if to_regprocedure('public.parceiro_detectar_pdf(timestamptz)') is not null then
    begin
      v_passos := v_passos || jsonb_build_object('pdf_mao', public.parceiro_detectar_pdf(v_agora));
    exception when others then
      v_erros := v_erros || 'pdf_mao';
      perform public._retorno_log('parceiro_vigia', 'parceiro_vigia (pdf_mao): ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
    end;
  end if;
  if to_regprocedure('public.parceiro_repassar_rodada(timestamptz)') is not null then
    begin
      v_passos := v_passos || jsonb_build_object('repassar', public.parceiro_repassar_rodada(v_agora));
    exception when others then
      v_erros := v_erros || 'repassar';
      perform public._retorno_log('parceiro_vigia', 'parceiro_vigia (repassar): ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
    end;
  end if;
  if to_regprocedure('public.parceiro_pedido_rodada(timestamptz)') is not null then
    begin
      v_passos := v_passos || jsonb_build_object('pedido', public.parceiro_pedido_rodada(v_agora));
    exception when others then
      v_erros := v_erros || 'pedido';
      perform public._retorno_log('parceiro_vigia', 'parceiro_vigia (pedido): ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
    end;
  end if;

  return jsonb_build_object('ok', cardinality(v_erros) = 0, 'rodou', true, 'modo', v_cfg.parceiro_modo, 'passos', v_passos,
                            'erros', to_jsonb(v_erros));
end;
$$;

comment on function public.parceiro_vigia(timestamptz) is
  'Retorno F4 (P7.1): o vigia do parceiro, cada passo isolado. Em qualquer modo: parceiro_reler_vetos, parceiro_vigia_cartao (P8) e às 04:00 parceiro_retencao_rodada (P14), estes dois só com a função no banco. Com parceiro_modo desligado, para aí. Depois: parceiro_aviso_rodada, parceiro_ativacao_rodada, parceiro_painel_rodada, parceiro_eco_rodada, parceiro_detectar_pdf e parceiro_repassar_rodada (P9) e parceiro_pedido_rodada (P10), os de migration posterior só com a função no banco.';

revoke all on function public.parceiro_vigia(timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_vigia(timestamptz) to service_role;

-- Retorno rápido ao cliente, F4 (P10): o C13, pedido de orçamento feito pelo parceiro para um cliente dele (K9).
-- Gerada por script (scripts/gerar_f4.cjs c13): as funções novas vêm de scripts/f4_sql/p10_c13.sql, escritas à mão; do corpo
-- vigente, só com os trechos marcados -- F4: retorno_previa_montar (20261208100200_retorno_f3_previa.sql) e retorno_previa_rodada
-- (20261208100200_retorno_f3_previa.sql); e os corpos próprios parceiro_previa_preparar, parceiro_previa_soltar, parceiro_previa_caiu e
-- parceiro_previa_pdf, gerados de retorno_previa_preparar, _soltar, _caiu e _pdf (20261208100500_retorno_f3_decidir.sql), que não mudam.
--
-- 1. _parceiro_cadastro_liga (a chave do cadastro) e _parceiro_veiculo_rotulo (o rótulo do bem da F1, ou o modelo).
-- 2. parceiro_coleta_ler: veículo, 1º nome e número autorizado, sem modelo e sem consultar clients; _parceiro_fone_da_casa
--    descarta o número da própria parceira ou da casa (revisão de 10/11).
-- 3. parceiro_cadastro_provisorio: nada | perguntar (duplicado por telefone) | criaria | criado. Só grava com a chave.
-- 4. parceiro_pedido_rodada (no parceiro_vigia): a máquina de estados automática do pedido.
-- 5. _parceiro_rascunho_do_pedido, _parceiro_legenda_do_orcamento (P16) e _parceiro_previa_recusa.
-- 6. parceiro_pedido_montar: o item pedido do cartão do parceiro (P8).
-- 7. parceiro_pedido_desfazer (letra D) e parceiro_vinculo_do_pedido (o vínculo nos dois destinos, tudo ou nada).
-- 8. Gerados: retorno_previa_montar e retorno_previa_rodada aceitam o caso do parceiro só com o pedido em cadastrado ou
--    cartao e client_id; parceiro_previa_preparar (abertura do pedido, item do parceiro, rascunho do pedido, regra 6
--    pulada, legenda P16 ao parceiro, origem retorno_parceiro), parceiro_previa_soltar (o pedido volta a cartao e a fila a
--    espera), parceiro_previa_caiu e parceiro_previa_pdf (sobre o cartão do parceiro).
--
-- Só escrevem em parceiro_pedidos.estado: _parceiro_triar (cria), parceiro_pedido_rodada, parceiro_cartao_executar,
-- parceiro_pedido_desfazer e parceiro_previa_soltar.
--
-- Sem dado. Tudo nasce desligado: parceiro_modo = 'desligado' (a rodada não roda), parceiro_cadastro_ligado = false (nenhum
-- clients ou vessels real nasce), previa_modo = 'desligado' (nenhuma proposta). Reverter: reaplicar retorno_previa_montar
-- e retorno_previa_rodada de 20261208100200_retorno_f3_previa.sql; drop das funções desta migration.

-- ── 1. A chave do cadastro e o rótulo do veículo ─────────────────────────────────────────────────────────────────────────

-- O cadastro real (clients e vessels) só nasce com as três: parceiro_cadastro_ligado, parceiro_modo = 'ligado' e
-- 'parceiro_coleta' em parceiro_tipos_ligados. Com a coleta em sombra, o pedido anda até o cartão com cadastro_simulado.
create or replace function public._parceiro_cadastro_liga()
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_cfg public.retorno_config := public._retorno_cfg();
begin
  return v_cfg.id is not null
         and coalesce(v_cfg.parceiro_cadastro_ligado, false)
         and v_cfg.parceiro_modo = 'ligado'
         and coalesce('parceiro_coleta' = any (v_cfg.parceiro_tipos_ligados), false);
end;
$$;

comment on function public._parceiro_cadastro_liga() is
  'Retorno F4 (P10.1): verdadeira só com parceiro_cadastro_ligado, parceiro_modo = ligado e parceiro_coleta em parceiro_tipos_ligados. Falsa: nenhum clients ou vessels real nasce do pedido do parceiro.';

revoke all on function public._parceiro_cadastro_liga() from public, anon, authenticated;

-- O veículo do pedido: o rótulo do bem pela tabela da F1 (retorno_abrir, coleta do número novo) ou, sem bem dito, o
-- modelo como a F1 o lê ("Daily", "Ducato"). Nulo quando nada foi dito.
create or replace function public._parceiro_veiculo_rotulo(p_bem_palavra text, p_modelo text)
returns text
language sql
immutable
set search_path = public
as $$
  select left(coalesce(
    case p_bem_palavra
      when 'lancha' then 'Lancha' when 'veleiro' then 'Veleiro' when 'catamara' then 'Catamarã'
      when 'jet ski' then 'Moto aquática' when 'moto aquatica' then 'Moto aquática'
      when 'barco' then 'Barco' when 'embarcacao' then 'Embarcação' when 'escuna' then 'Escuna'
      when 'traineira' then 'Traineira' when 'bote' then 'Bote'
      when 'motorhome' then 'Motorhome' when 'trailer' then 'Trailer' when 'camper' then 'Camper'
      when 'van' then 'Van' when 'onibus' then 'Ônibus' when 'caminhao' then 'Caminhão' when 'picape' then 'Picape'
      when 'automovel' then 'Automóvel' when 'carro' then 'Automóvel' when 'veiculo' then 'Veículo'
    end,
    nullif(btrim(p_modelo), '')), 40);
$$;

comment on function public._parceiro_veiculo_rotulo(text, text) is
  'Retorno F4 (P10.1): o rótulo do bem pela tabela da F1 (motorhome → Motorhome, carro → Automóvel, veiculo → Veículo…) ou, sem bem, o modelo como foi escrito (Daily, Ducato). Até 40 caracteres.';

revoke all on function public._parceiro_veiculo_rotulo(text, text) from public, anon, authenticated;

-- ── 2. A leitura do pedido (C13, passo 2) ──────────────────────────────────────────────────────────────────────────────

-- Revisão de 10/11 (seguranca-c13): o número que a parceira passa como o do cliente nunca é dela nem da casa: a chave do
-- caso (quem escreveu), um número de parceiro que não foi recusado (de qualquer parceiro), a equipe (app_users) ou um
-- favorecido (payees), como quem_escreve os separa. Verdadeiro: o número não serve ao cliente. Sem chave de 8 dígitos,
-- falso (quem chama já recusa). Nunca consulta clients.
create or replace function public._parceiro_fone_da_casa(p_fone text, p_abertura uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select x.chave is not null
         and (x.chave is not distinct from (select a.chave from public.retorno_aberturas a where a.id = p_abertura)
              or exists (select 1 from public.parceiro_numeros n where n.chave = x.chave and n.situacao <> 'recusado')
              or exists (select 1 from public.app_users u
                          where u.active
                            and (public._mesmo_telefone(p_fone, u.phone_normalized) or public._mesmo_telefone(p_fone, u.phone)))
              or exists (select 1 from public.payees p where p.active and public._mesmo_telefone(p_fone, p.phone)))
    from (select public._agenda_chave_telefone(p_fone) as chave) x;
$$;

comment on function public._parceiro_fone_da_casa(text, uuid) is
  'Retorno F4 (P10.1; revisão de 10/11, seguranca-c13): o número passado pela parceira é dela ou da casa? Verdadeiro quando a chave é a do caso, a de um número de parceiro não recusado, ou o telefone é da equipe (app_users ativo) ou de um favorecido (payees ativo). Sem chave, falso. Nunca consulta clients. Chamada por parceiro_coleta_ler (descarta o número) e por parceiro_cartao_executar (não copia e, ao cliente, nada sai).';

revoke all on function public._parceiro_fone_da_casa(text, uuid) from public, anon, authenticated;

-- O que dá para ler do pedido, sem nenhum modelo e sem nome de cadastro. Bem e modelo pela janela do caso
-- (_retorno_pedido_de_servico desde aberta_em, como a regra 7); o 1º nome só na forma "do/da/cliente/nome + Nome" no texto
-- como foi escrito, descartando bem, as palavras fixas (Gustavo, Claudia, HBR, cliente), a sigla e os nomes do próprio
-- parceiro; o número só com autorização escrita na mesma mensagem, e nunca o da própria parceira ou da casa
-- (_parceiro_fone_da_casa; o 1º número que serve, na ordem da mensagem). Preenche só campo nulo, e só em coleta. completo_em
-- é a hora real da mensagem que completou veículo e nome. Nunca consulta clients. Devolve só marcas, nunca o nome nem o número.
create or replace function public.parceiro_coleta_ler(p_abertura uuid, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_re_nome constant text := '\y(?:[Dd][oa]|[Cc]liente|[Nn]ome)\s+([A-ZÀ-ÖØ-Þ][a-zß-öø-ÿ]{1,39})\y';
  c_re_bem constant text := '\y(barco|lancha|veleiro|catamara|embarcacao|jet ski|moto aquatica|escuna|traineira|bote|motorhome|motor home|trailer|camper|van|onibus|caminhao|picape|automovel|veiculo|carro|ducato|sprinter|iveco|daily|master|boxer)\y';
  c_re_autoriza constant text := '\y(autoriz[a-z]*|pode (passar|chamar|ligar|falar|mandar|contatar)|liberou|liberado|liberada)\y';
  c_re_fone constant text := '(?:\+?55[ .-]*)?\(?[1-9][0-9]\)?[ .-]*9?[0-9]{4}[ .-]*[0-9]{4}';
  v_agora timestamptz := coalesce(p_agora, now());
  v_ab public.retorno_aberturas;
  v_ped public.parceiro_pedidos;
  v_novo public.parceiro_pedidos;
  v_fora text[];
  v_pd jsonb;
  v_veiculo text;
  v_vei_em timestamptz;
  v_nome text;
  v_nome_em timestamptz;
  v_fone text;
  v_ultima timestamptz;
  v_s jsonb;
  v_m text;
  v_dig text;
  v_completo timestamptz;
  r record;
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  if not found or v_ab.papel is distinct from 'parceiro' then
    return jsonb_build_object('ok', false, 'motivo', 'sem_caso');
  end if;
  select * into v_ped from public.parceiro_pedidos pp where pp.abertura_id = p_abertura for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sem_pedido');
  end if;
  if v_ped.estado is distinct from 'coleta' then
    return jsonb_build_object('ok', true, 'mudou', false, 'motivo', 'fora_da_coleta');
  end if;

  -- As palavras que nunca são o 1º nome do cliente: as fixas, a sigla, o nome do parceiro e as pessoas dele.
  select array['gustavo', 'claudia', 'hbr', 'cliente']
         || coalesce(array_agg(distinct x.p) filter (where x.p is not null and x.p <> ''), '{}'::text[])
    into v_fora
    from (select public._texto_simples(btrim(pa.sigla)) as p from public.parceiros pa where pa.id = v_ped.parceiro_id
          union all
          select public._texto_simples(btrim(split_part(btrim(pa.nome), ' ', 1))) from public.parceiros pa where pa.id = v_ped.parceiro_id
          union all
          select public._texto_simples(btrim(split_part(btrim(pe.nome), ' ', 1)))
            from public.parceiro_pessoas pe where pe.parceiro_id = v_ped.parceiro_id) x;

  -- Bem e modelo: a janela do caso, nunca as 24 h do número.
  v_pd := public._retorno_pedido_de_servico(v_ab.chave, v_ab.aberta_em, v_agora, null);
  v_veiculo := public._parceiro_veiculo_rotulo(v_pd ->> 'bem_palavra', v_pd ->> 'modelo');

  -- Mensagem a mensagem, na ordem da janela: quando o veículo apareceu, o 1º nome e o número autorizado.
  for r in
    select w.id, w.body, coalesce(rm.recebida_em, public._retorno_hora_real(w)) as em
      from jsonb_array_elements_text(case when jsonb_typeof(v_pd -> 'msgs') = 'array' then v_pd -> 'msgs' else '[]'::jsonb end)
           with ordinality as x(id, ord)
      join public.whatsapp_messages w on w.id = x.id::uuid
      left join public.retorno_mensagens rm on rm.whatsapp_message_id = w.id
     order by x.ord
  loop
    v_s := public._retorno_sinais(r.body);
    if v_vei_em is null and public._parceiro_veiculo_rotulo(v_s ->> 'bem_palavra', v_s ->> 'modelo') is not null then
      v_vei_em := r.em;
    end if;
    if v_nome is null then
      select y.nome into v_nome
        from (select t.m[1] as nome, t.o
                from regexp_matches(coalesce(r.body, ''), c_re_nome, 'g') with ordinality as t(m, o)) y
       where not (public._retorno_busca(y.nome) ~ c_re_bem)
         and public._texto_simples(y.nome) <> all (v_fora)
       order by y.o
       limit 1;
      if v_nome is not null then
        v_nome_em := r.em;
      end if;
    end if;
    if v_fone is null and public._retorno_busca(r.body) ~ c_re_autoriza then
      -- revisão de 10/11 (seguranca-c13): cada número da mensagem, na ordem; o da própria parceira ou da casa
      -- (_parceiro_fone_da_casa: a chave do caso, um número de parceiro, a equipe ou um favorecido) é descartado, e a
      -- leitura segue para o próximo
      for v_m in
        select t.m[1] from regexp_matches(coalesce(r.body, ''), '(' || c_re_fone || ')', 'g') with ordinality as t(m, o) order by t.o
      loop
        v_dig := regexp_replace(coalesce(v_m, ''), '\D', '', 'g');
        if length(v_dig) in (10, 11) then
          v_dig := '55' || v_dig;
        end if;
        if length(v_dig) in (12, 13) and v_dig like '55%' and public._agenda_chave_telefone(v_dig) is not null
           and not public._parceiro_fone_da_casa(v_dig, p_abertura) then
          v_fone := v_dig;
          exit;
        end if;
      end loop;
    end if;
  end loop;

  -- A última mensagem do caso até agora: a régua do silêncio (parceiro_coleta_espera).
  select max(rm.recebida_em) into v_ultima
    from public.retorno_mensagens rm
   where rm.abertura_id = p_abertura and rm.gravada_em <= v_agora;

  v_completo := case when coalesce(v_ped.veiculo, v_veiculo) is not null and coalesce(v_ped.primeiro_nome, v_nome) is not null
                     then coalesce(greatest(v_vei_em, v_nome_em), v_agora) end;

  update public.parceiro_pedidos pp
     set veiculo = coalesce(pp.veiculo, v_veiculo),
         primeiro_nome = coalesce(pp.primeiro_nome, v_nome),
         autoriza_whatsapp = case when pp.whatsapp_informado is null and v_fone is not null then true else pp.autoriza_whatsapp end,
         whatsapp_informado = coalesce(pp.whatsapp_informado, v_fone),
         completo_em = coalesce(pp.completo_em, v_completo),
         atualizado_em = greatest(pp.atualizado_em, v_ultima)
   where pp.id = v_ped.id
   returning * into v_novo;

  return jsonb_build_object(
    'ok', true,
    'mudou', (v_novo.veiculo, v_novo.primeiro_nome, v_novo.whatsapp_informado, v_novo.completo_em)
             is distinct from (v_ped.veiculo, v_ped.primeiro_nome, v_ped.whatsapp_informado, v_ped.completo_em),
    'veiculo', v_novo.veiculo is not null,
    'primeiro_nome', v_novo.primeiro_nome is not null,
    'numero', v_novo.whatsapp_informado is not null,
    'completo', v_novo.completo_em is not null);
end;
$$;

comment on function public.parceiro_coleta_ler(uuid, timestamptz) is
  'Retorno F4 (P10.1, passo 2): lê do pedido do parceiro, só em coleta e só para campo nulo: o veículo (rótulo do bem da F1 ou o modelo, pela janela do caso), o 1º nome (só "do/da/cliente/nome + Nome", fora de bem e de palavra fixa) e o número com autorização escrita na mesma mensagem (o 1º que não é da parceira nem da casa: _parceiro_fone_da_casa). completo_em = hora real da mensagem que completou veículo e nome. Nunca consulta clients. Devolve só marcas ({ok, mudou, veiculo, primeiro_nome, numero, completo}).';

revoke all on function public.parceiro_coleta_ler(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_coleta_ler(uuid, timestamptz) to service_role;

-- ── 3. O cadastro provisório (C13, passo 5) ────────────────────────────────────────────────────────────────────────────

-- p_executar falso nunca grava: devolve o que criaria, ou "perguntar" com quantos clientes ativos já têm o número que a
-- parceira passou (por nome, nunca: nome igual cria igual). Verdadeiro só grava com _parceiro_cadastro_liga (2ª trava,
-- mesmo chamada direto). O cliente nasce provisório, origem retorno, sem WhatsApp (o número só vai ao cadastro no *sim
-- <PIN>* do item); a unidade sempre existe: rótulo de bem → asset_type e name iguais; só o modelo → Veículo e o modelo no
-- name. O audit_log tem a forma da F1 (new_value.caso), e _retorno_cadastro_do_caso acha sem mudança.
create or replace function public.parceiro_cadastro_provisorio(p_pedido uuid, p_executar boolean default false)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_rotulos constant text[] := array['Lancha', 'Veleiro', 'Catamarã', 'Moto aquática', 'Barco', 'Embarcação', 'Escuna', 'Traineira',
                                     'Bote', 'Motorhome', 'Trailer', 'Camper', 'Van', 'Ônibus', 'Caminhão', 'Picape', 'Automóvel',
                                     'Veículo'];
  v_ped public.parceiro_pedidos;
  v_sigla text;
  v_chave text;
  v_dup integer;
  v_nome text;
  v_tipo text;
  v_unidade text;
  v_cliente uuid;
  v_vessel uuid;
begin
  select * into v_ped from public.parceiro_pedidos pp where pp.id = p_pedido;
  if not found then
    return jsonb_build_object('acao', 'nada', 'motivo', 'sem_pedido');
  end if;
  if coalesce(p_executar, false) and not public._parceiro_cadastro_liga() then
    return jsonb_build_object('acao', 'nada', 'motivo', 'desligado');
  end if;
  if v_ped.client_id is not null then
    return jsonb_build_object('acao', 'nada', 'motivo', 'ja_cadastrado');
  end if;
  v_unidade := nullif(btrim(v_ped.veiculo), '');
  if v_unidade is null then
    return jsonb_build_object('acao', 'nada', 'motivo', 'sem_veiculo');
  end if;

  -- Duplicado só pelo telefone que a parceira passou, sobre os clientes ativos. Nunca pelo nome.
  v_chave := public._agenda_chave_telefone(v_ped.whatsapp_informado);
  if v_chave is not null then
    select count(*) into v_dup
      from public.clients c
     where c.active
       and v_chave in (public._agenda_chave_telefone(c.phone), public._agenda_chave_telefone(c.whatsapp));
    if v_dup > 0 then
      return jsonb_build_object('acao', 'perguntar', 'duplicados', v_dup);
    end if;
  end if;

  select pa.sigla into v_sigla from public.parceiros pa where pa.id = v_ped.parceiro_id;
  v_nome := coalesce(nullif(btrim(v_ped.primeiro_nome), ''), 'Cliente pela ' || coalesce(v_sigla, 'parceira'));
  v_tipo := case when v_unidade = any (c_rotulos) then v_unidade else 'Veículo' end;

  if not coalesce(p_executar, false) then
    return jsonb_build_object('acao', 'criaria', 'nome', v_nome,
                              'unidade', jsonb_build_object('asset_type', v_tipo, 'name', v_unidade));
  end if;

  insert into public.clients (type, name, whatsapp, provisorio, origem, active)
  values ('individual', v_nome, null, true, 'retorno', true)
  returning id into v_cliente;
  insert into public.vessels (client_id, name, asset_type, active)
  values (v_cliente, v_unidade, v_tipo, true)
  returning id into v_vessel;
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('clients', v_cliente, 'lead_converted', 'retorno', null,
          jsonb_build_object('provisorio', true, 'origem', 'retorno', 'caso', v_ped.abertura_id, 'vessel_id', v_vessel,
                             'parceiro_id', v_ped.parceiro_id, 'pedido_id', v_ped.id),
          'Cadastro provisório pelo parceiro (caso ' || v_ped.abertura_id || ')');

  return jsonb_build_object('acao', 'criado', 'client_id', v_cliente, 'vessel_id', v_vessel);
end;
$$;

comment on function public.parceiro_cadastro_provisorio(uuid, boolean) is
  'Retorno F4 (P10.1, passo 5): {acao: nada (sem_pedido, desligado, ja_cadastrado, sem_veiculo), perguntar (duplicados: n, pelo telefone que a parceira passou), criaria (nome, unidade {asset_type, name}) ou criado (client_id, vessel_id)}. p_executar só grava com _parceiro_cadastro_liga. Cliente provisório, origem retorno, sem WhatsApp; unidade sempre (rótulo da F1 ou Veículo com o modelo); audit_log na forma da F1 (new_value.caso). Nunca procura por nome.';

revoke all on function public.parceiro_cadastro_provisorio(uuid, boolean) from public, anon, authenticated;
grant execute on function public.parceiro_cadastro_provisorio(uuid, boolean) to service_role;

-- ── 4. A rodada do pedido (no parceiro_vigia): o único dono das transições automáticas ──────────────────────────────────

-- Cada pedido no seu próprio begin … exception (erro vira log e o próximo segue). Ordem: caso fechado; cadastrado → cartao
-- (os que já estavam cadastrados antes desta rodada); cartao vencido; coleta. Toda saída de coleta grava completo_em.
create or replace function public.parceiro_pedido_rodada(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_decididas constant text[] := array['sombra', 'enviada', 'incerta'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_liga boolean;
  v_cad jsonb;
  v_vencida boolean;
  v_pronto boolean;
  v_fechados integer := 0;
  v_cadastrados integer := 0;
  v_cartao integer := 0;
  v_sem_resposta integer := 0;
  v_validade integer := 0;
  v_erros integer := 0;
  r record;
begin
  if v_cfg.id is null or v_cfg.parceiro_modo = 'desligado' then
    return jsonb_build_object('rodou', false, 'motivo', 'desligado');
  end if;
  perform pg_advisory_xact_lock(hashtext('parceiro:pedido'));
  v_liga := public._parceiro_cadastro_liga();

  -- 1. O caso fechou (o dono respondeu, *resolvido* ou silêncio): coleta, cadastrado e cartao caem, e o item da fila cai.
  for r in
    select pp.id, pp.estado
      from public.parceiro_pedidos pp
      join public.retorno_aberturas a on a.id = pp.abertura_id
     where pp.estado in ('coleta', 'cadastrado', 'cartao')
       and a.estado = 'fechada'
       and coalesce(a.fechada_em, v_agora) <= v_agora
     order by pp.criado_em, pp.id
  loop
    begin
      update public.parceiro_pedidos pp
         set estado = 'caiu', caiu_motivo = 'caso_fechado', completo_em = coalesce(pp.completo_em, v_agora), atualizado_em = v_agora
       where pp.id = r.id and pp.estado = r.estado;
      update public.parceiro_fila f
         set estado = 'caiu', decidido_em = v_agora
       where f.chave = 'pedido:' || r.id and f.estado = 'espera';
      v_fechados := v_fechados + 1;
    exception when others then
      v_erros := v_erros + 1;
      perform public._retorno_log('parceiro_pedido', 'parceiro_pedido_rodada (caso fechado): ' || sqlerrm, 'error',
                                  jsonb_build_object('pedido', r.id, 'sqlstate', sqlstate));
    end;
  end loop;

  -- 2. cadastrado → cartao, na rodada seguinte à do cadastro: o pedido vai à fila do cartão.
  for r in
    select pp.* from public.parceiro_pedidos pp
     where pp.estado = 'cadastrado' and pp.criado_em <= v_agora
     order by pp.criado_em, pp.id
  loop
    begin
      update public.parceiro_pedidos pp
         set estado = 'cartao', completo_em = coalesce(pp.completo_em, v_agora), atualizado_em = v_agora
       where pp.id = r.id and pp.estado = 'cadastrado';
      perform public._parceiro_fila_por('pedido', r.parceiro_id, r.id, 'pedido:' || r.id, r.criado_em + v_cfg.parceiro_pedido_validade,
                                        jsonb_build_object('abertura_id', r.abertura_id));
      v_cartao := v_cartao + 1;
    exception when others then
      v_erros := v_erros + 1;
      perform public._retorno_log('parceiro_pedido', 'parceiro_pedido_rodada (cadastrado): ' || sqlerrm, 'error',
                                  jsonb_build_object('pedido', r.id, 'sqlstate', sqlstate));
    end;
  end loop;

  -- 3. cartao vencido (criado_em + parceiro_pedido_validade): cai, e a pergunta vai à fila (o caso segue com o dono).
  for r in
    select pp.*, a.estado as caso_estado, a.ultima_msg_id, a.ultima_em
      from public.parceiro_pedidos pp
      join public.retorno_aberturas a on a.id = pp.abertura_id
     where pp.estado = 'cartao' and pp.criado_em + v_cfg.parceiro_pedido_validade <= v_agora
     order by pp.criado_em, pp.id
  loop
    begin
      update public.parceiro_pedidos pp
         set estado = 'caiu', caiu_motivo = 'validade', completo_em = coalesce(pp.completo_em, v_agora), atualizado_em = v_agora
       where pp.id = r.id and pp.estado = 'cartao';
      update public.parceiro_fila f
         set estado = 'caiu', decidido_em = v_agora
       where f.chave = 'pedido:' || r.id and f.estado = 'espera';
      if r.caso_estado is distinct from 'fechada' then
        perform public._parceiro_fila_por('pergunta', r.parceiro_id, r.abertura_id, 'pergunta:' || r.abertura_id, null,
                                          jsonb_build_object('ultima_msg_id', r.ultima_msg_id, 'ultima_em', r.ultima_em));
      end if;
      v_validade := v_validade + 1;
    exception when others then
      v_erros := v_erros + 1;
      perform public._retorno_log('parceiro_pedido', 'parceiro_pedido_rodada (validade): ' || sqlerrm, 'error',
                                  jsonb_build_object('pedido', r.id, 'sqlstate', sqlstate));
    end;
  end loop;

  -- 4. coleta. Sem veículo e com o silêncio vencido: cai sem resposta, sem cadastro. Pronto para decidir (veículo lido e
  --    número informado, ou P04 decidido há parceiro_carencia, ou o silêncio vencido): o cadastro (real só com a chave) e
  --    cadastrado, ou cartao com cadastro_simulado (o "criaria" ou o "perguntar").
  for r in
    select pp.*, a.estado as caso_estado, a.ultima_msg_id, a.ultima_em
      from public.parceiro_pedidos pp
      join public.retorno_aberturas a on a.id = pp.abertura_id
     where pp.estado = 'coleta' and pp.criado_em <= v_agora
     order by pp.criado_em, pp.id
  loop
    begin
      v_vencida := r.atualizado_em + v_cfg.parceiro_coleta_espera <= v_agora;
      if r.veiculo is null then
        if v_vencida then
          update public.parceiro_pedidos pp
             set estado = 'caiu', caiu_motivo = 'sem_resposta', completo_em = coalesce(pp.completo_em, v_agora), atualizado_em = v_agora
           where pp.id = r.id and pp.estado = 'coleta';
          if r.caso_estado is distinct from 'fechada' then
            perform public._parceiro_fila_por('pergunta', r.parceiro_id, r.abertura_id, 'pergunta:' || r.abertura_id, null,
                                              jsonb_build_object('ultima_msg_id', r.ultima_msg_id, 'ultima_em', r.ultima_em));
          end if;
          v_sem_resposta := v_sem_resposta + 1;
        end if;
        continue;
      end if;
      v_pronto := r.whatsapp_informado is not null
                  or v_vencida
                  or exists (select 1 from public.retorno_saidas s
                              where s.abertura_id = r.abertura_id and s.emissor = 'parceiro'
                                and s.tipo = 'parceiro_coleta' and s.variante = 'whatsapp'
                                and s.estado = any (c_decididas)
                                and s.decidida_em + v_cfg.parceiro_carencia <= v_agora);
      if not v_pronto then
        continue;
      end if;
      v_cad := public.parceiro_cadastro_provisorio(r.id, v_liga);
      if v_cad ->> 'acao' = 'criado' then
        update public.parceiro_pedidos pp
           set estado = 'cadastrado', client_id = (v_cad ->> 'client_id')::uuid, vessel_id = (v_cad ->> 'vessel_id')::uuid,
               completo_em = coalesce(pp.completo_em, v_agora), atualizado_em = v_agora
         where pp.id = r.id and pp.estado = 'coleta';
        v_cadastrados := v_cadastrados + 1;
      else
        update public.parceiro_pedidos pp
           set estado = 'cartao', cadastro_simulado = v_cad, completo_em = coalesce(pp.completo_em, v_agora), atualizado_em = v_agora
         where pp.id = r.id and pp.estado = 'coleta';
        perform public._parceiro_fila_por('pedido', r.parceiro_id, r.id, 'pedido:' || r.id, r.criado_em + v_cfg.parceiro_pedido_validade,
                                          jsonb_build_object('abertura_id', r.abertura_id));
        v_cartao := v_cartao + 1;
      end if;
    exception when others then
      v_erros := v_erros + 1;
      perform public._retorno_log('parceiro_pedido', 'parceiro_pedido_rodada (coleta): ' || sqlerrm, 'error',
                                  jsonb_build_object('pedido', r.id, 'sqlstate', sqlstate));
    end;
  end loop;

  return jsonb_build_object('rodou', true, 'fechados', v_fechados, 'cadastrados', v_cadastrados, 'cartao', v_cartao,
                            'sem_resposta', v_sem_resposta, 'validade', v_validade, 'erros', v_erros);
end;
$$;

comment on function public.parceiro_pedido_rodada(timestamptz) is
  'Retorno F4 (P10.1): a máquina de estados automática do pedido do parceiro, no parceiro_vigia. Caso fechado → caiu/caso_fechado; cadastrado → cartao (rodada seguinte) e pedido na fila; cartao vencido → caiu/validade e pergunta; coleta sem veículo e com o silêncio vencido → caiu/sem_resposta, sem cadastro, e pergunta; coleta pronta → parceiro_cadastro_provisorio(id, _parceiro_cadastro_liga()): criado → cadastrado; senão cartao com cadastro_simulado. Com parceiro_modo desligado, não roda.';

revoke all on function public.parceiro_pedido_rodada(timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_pedido_rodada(timestamptz) to service_role;

-- ── 5. O rascunho, a legenda e a recusa do preparo do parceiro ─────────────────────────────────────────────────────────

-- O mesmo formato de _retorno_rascunho_do_caso, sobre o orçamento em rascunho mais recente do cliente provisório do pedido,
-- de até 14 dias, nunca do futuro. Rascunho com a origem de outro parceiro não serve; o deste parceiro vem primeiro.
create or replace function public._parceiro_rascunho_do_pedido(p_pedido uuid, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_ped public.parceiro_pedidos;
  v_so public.service_orders;
  v_n_pecas integer;
  v_n_serv integer;
  v_sem_preco integer;
  v_unidade text;
begin
  select * into v_ped from public.parceiro_pedidos pp where pp.id = p_pedido;
  if not found or v_ped.client_id is null
     or not exists (select 1 from public.clients c where c.id = v_ped.client_id and c.active) then
    return null;
  end if;

  select so.* into v_so
    from public.service_orders so
   where so.client_id = v_ped.client_id
     and so.status = 'draft'
     and so.quote_status = 'draft'
     and so.merged_into_id is null
     and so.created_at >= v_agora - interval '14 days'
     and so.created_at <= v_agora
     and (so.origem_parceiro_id is null or so.origem_parceiro_id = v_ped.parceiro_id)
   order by (so.origem_parceiro_id is not distinct from v_ped.parceiro_id) desc, so.created_at desc, so.id
   limit 1;
  if not found then
    return null;
  end if;

  select count(*), count(*) filter (where p.unit_sale_snapshot <= 0) into v_n_pecas, v_sem_preco
    from public.service_order_parts p where p.service_order_id = v_so.id;
  select count(*), count(*) filter (where s.unit_price_snapshot <= 0) + v_sem_preco into v_n_serv, v_sem_preco
    from public.service_order_services s where s.service_order_id = v_so.id;
  select v.name into v_unidade from public.vessels v where v.id = v_so.vessel_id;

  return jsonb_build_object(
    'service_order_id', v_so.id,
    'numero', v_so.service_order_number,
    'criado_em', v_so.created_at,
    'unidade', v_unidade,
    'total', coalesce(v_so.grand_total, 0),
    'linhas_n', v_n_pecas + v_n_serv,
    'linhas_sem_preco', v_sem_preco);
end;
$$;

comment on function public._parceiro_rascunho_do_pedido(uuid, timestamptz) is
  'Retorno F4 (P10.1): o rascunho do pedido do parceiro, no formato de _retorno_rascunho_do_caso: o orçamento em rascunho mais recente do cliente provisório do pedido, ativo, de até 14 dias e até p_agora; origem de outro parceiro não serve, a deste vem primeiro. Nulo quando não há.';

revoke all on function public._parceiro_rascunho_do_pedido(uuid, timestamptz) from public, anon, authenticated;

-- A legenda do PDF à parceira (P16), no formato de retorno_legenda_do_orcamento: {texto, validade_data, contexto}. O nome é o
-- 1º nome que a parceira disse (ou, de cliente que deixou de ser provisório, o do cadastro); o contexto é o do validador
-- do parceiro (audiência parceiro, nomes_da_lista com o {João}). Sem nome ou sem número: 22023, e o preparo recusa.
create or replace function public._parceiro_legenda_do_orcamento(p_pedido uuid, p_client uuid, p_vessel uuid, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_ped public.parceiro_pedidos;
  v_ab public.retorno_aberturas;
  v_prov boolean;
  v_primeiro text;
  v_num uuid;
  v_n integer;
  v_nomes jsonb;
  v_validade_data date;
  v_ddmm text;
  v_texto text;
begin
  select * into v_ped from public.parceiro_pedidos pp where pp.id = p_pedido;
  if not found then
    raise exception using errcode = '22023', message = 'parceiro_legenda: pedido desconhecido';
  end if;
  select * into v_ab from public.retorno_aberturas a where a.id = v_ped.abertura_id;
  select coalesce(c.provisorio, false) into v_prov from public.clients c where c.id = p_client;
  v_primeiro := coalesce(nullif(btrim(v_ped.primeiro_nome), ''),
                         case when not coalesce(v_prov, true)
                              then public._agenda_nome_curto(public._parceiro_nome_curto(p_client)) end);

  -- O número que recebe: o recebe_documento da pessoa do pedido, se for um só; senão o número do caso.
  select count(*), min(n.id::text)::uuid into v_n, v_num
    from public.parceiro_numeros n
   where n.pessoa_id = v_ped.pessoa_id and n.situacao = 'confirmado' and n.recebe_documento;
  if v_n is distinct from 1 then
    v_num := nullif(v_ab.quem ->> 'numero_id', '')::uuid;
  end if;

  v_validade_data := public._retorno_validade_do_envio(v_agora);
  v_ddmm := to_char(v_validade_data, 'DD/MM');
  v_nomes := public._parceiro_nomes_do_contexto(v_ped.parceiro_id, array[p_client], v_ped.pessoa_id);
  v_texto := public._parceiro_texto('parceiro_legenda', 'padrao', jsonb_build_object(
               'abertura', public._parceiro_abertura(v_num, v_nomes -> 'nomes_de_outros', v_agora),
               'bem', public._parceiro_bem(p_vessel),
               'primeiro_nome', v_primeiro,
               'validade', v_ddmm));

  return jsonb_build_object(
    'texto', v_texto,
    'validade_data', v_validade_data,
    'contexto', public._parceiro_contexto_do_validador(null, v_texto, jsonb_build_object(
                  'tipo', 'parceiro_legenda', 'parceiro_id', v_ped.parceiro_id, 'pessoa_id', v_ped.pessoa_id, 'numero_id', v_num,
                  'primeiro_nome', v_primeiro, 'validade', v_ddmm, 'abertura_id', v_ped.abertura_id), v_agora));
end;
$$;

comment on function public._parceiro_legenda_do_orcamento(uuid, uuid, uuid, timestamptz) is
  'Retorno F4 (P10.1, P16): a legenda do PDF à parceira, {texto, validade_data, contexto}: "{abertura}Segue o orçamento do {bem} de {João}, válido até {dd/mm}." com o contexto do validador do parceiro (nomes_da_lista com o 1º nome). O número é o recebe_documento da pessoa do pedido (um só) ou o do caso. Sem 1º nome: 22023.';

revoke all on function public._parceiro_legenda_do_orcamento(uuid, uuid, uuid, timestamptz) from public, anon, authenticated;

-- A recusa do preparo do parceiro (o par de _retorno_previa_recusa sobre parceiro_cartao_itens). Regra 0 (a chave do
-- orçamento desligada): o pedido volta ao cartão pela porta de sempre (parceiro_previa_soltar). Regra 1: nada. Regras 2 a
-- 7: o item feito cai com o motivo, e o caso aberto volta à fila como pergunta (fica com o dono até *resolvido*); o pedido
-- fica decidido. Regra 5: a proposta cai.
create or replace function public._parceiro_previa_recusa(p_pedido uuid, p_abertura uuid, p_previa uuid, p_item uuid, p_regra integer,
                                                          p_motivo text, p_frase text, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_i public.parceiro_cartao_itens;
  v_ab public.retorno_aberturas;
  v_ped public.parceiro_pedidos;
  v_rotulo text := coalesce(public._retorno_rotulo(p_abertura, p_agora), 'parceiro');
begin
  if p_item is not null then
    select * into v_i from public.parceiro_cartao_itens i where i.id = p_item;
    if found then
      if p_regra = 0 then
        perform public.parceiro_previa_soltar(p_item, v_agora);
      elsif p_regra between 2 and 7 and v_i.estado = 'feito' then
        update public.parceiro_cartao_itens i
           set estado = 'caiu', caiu_motivo = p_motivo, decidido_em = coalesce(i.decidido_em, v_agora)
         where i.id = p_item;
        select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
        select * into v_ped from public.parceiro_pedidos pp where pp.id = p_pedido;
        if v_ab.id is not null and v_ab.estado is distinct from 'fechada' and v_ped.id is not null then
          perform public._parceiro_fila_por('pergunta', v_ped.parceiro_id, v_ab.id, 'pergunta:' || v_ab.id, null,
                                            jsonb_build_object('ultima_msg_id', v_ab.ultima_msg_id, 'ultima_em', v_ab.ultima_em));
        end if;
      end if;
    end if;
  end if;
  if p_regra = 5 and p_previa is not null then
    update public.retorno_previa p
       set estado = 'caiu', decidida_em = v_agora, atualizada_em = v_agora
     where p.id = p_previa and p.estado = 'proposta';
  end if;
  return jsonb_build_object('ok', false, 'motivo', p_motivo, 'frase', p_frase, 'rotulo', v_rotulo);
end;
$$;

revoke all on function public._parceiro_previa_recusa(uuid, uuid, uuid, uuid, integer, text, text, timestamptz) from public, anon, authenticated;

-- ── 6. O item pedido do cartão do parceiro (P8.1, linha pedido) ────────────────────────────────────────────────────────

-- O trecho do pedido com todo número de telefone trocado por ••NNNN: o número que a parceira passou só aparece assim no
-- cartão, mesmo dentro da frase dela.
create or replace function public._parceiro_sem_fone(p_texto text)
returns text
language sql
immutable
set search_path = public
as $$
  select regexp_replace(
           regexp_replace(coalesce(p_texto, ''), '(?:\+?55[ .-]*)?\(?[1-9][0-9]\)?[ .-]*9?[0-9]{4}[ .-]*([0-9]{4})', '••\1', 'g'),
           '[0-9]{4,5}[ .-]?([0-9]{4})', '••\1', 'g');
$$;

comment on function public._parceiro_sem_fone(text) is
  'Retorno F4 (P10.1): troca cada telefone (com DDD, com ou sem 55, e qualquer sequência de 8 ou 9 dígitos) por ••NNNN, os 4 últimos.';

revoke all on function public._parceiro_sem_fone(text) from public, anon, authenticated;

-- O item de um pedido em cartao, no contrato de _parceiro_item_montar: {tipo, pedido_id, abertura_id, service_order_id,
-- texto_mostrado, opcoes [{letra, rotulo, acao: cliente|parceiro|desfazer}], retrato {exige_letra, acao: orcar|pdf, previa_id,
-- service_order_id, numero, …}, selecionado, hash}. Três formas: duplicado por telefone (só *resolvido*), sem cadastro (só
-- *resolvido*) e com cadastro (A ao cliente, B à parceira, D desfaz). O número que a parceira passou só aparece como ••NNNN.
create or replace function public.parceiro_pedido_montar(p_pedido uuid, p_n smallint, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_ped public.parceiro_pedidos;
  v_sigla text;
  v_rotulo text;
  v_trecho text;
  v_nome text;
  v_vei text;
  v_mais text := '';
  v_quatro text;
  v_cli public.clients;
  v_tel text;
  v_pv public.retorno_previa;
  v_rasc jsonb;
  v_acao text;
  v_so uuid;
  v_numero text;
  v_linha text;
  v_partes text[] := '{}';
  v_opcoes jsonb := '[]'::jsonb;
  v_ja_comercial boolean := false;
  v_rot_b text;
  v_texto text;
  v_forma text;
  v_mostrou boolean := false;
begin
  select * into v_ped from public.parceiro_pedidos pp where pp.id = p_pedido;
  if not found then
    raise exception using errcode = '22023', message = 'parceiro_pedido_montar: pedido desconhecido';
  end if;
  if v_ped.estado is distinct from 'cartao' then
    raise exception using errcode = '22023', message = 'parceiro_pedido_montar: o pedido não está no cartão';
  end if;
  select pa.sigla into v_sigla from public.parceiros pa where pa.id = v_ped.parceiro_id;
  v_rotulo := coalesce(public._retorno_rotulo(v_ped.abertura_id, v_agora), coalesce(v_sigla, 'parceiro'));

  -- O trecho do pedido: a 1ª mensagem do caso que pede resposta (o próprio pedido), até agora.
  select public._retorno_trecho(w.body, w.message_type, rm.audio_pendente, 300) into v_trecho
    from public.retorno_mensagens rm
    join public.whatsapp_messages w on w.id = rm.whatsapp_message_id
   where rm.abertura_id = v_ped.abertura_id and rm.recebida_em <= v_agora
   order by rm.pede_resposta desc, rm.recebida_em, rm.whatsapp_message_id
   limit 1;
  v_trecho := public._parceiro_sem_fone(coalesce(v_trecho, '(sem texto)'));
  v_nome := coalesce(nullif(btrim(v_ped.primeiro_nome), ''), 'cliente sem nome');
  v_vei := coalesce(nullif(btrim(v_ped.veiculo), ''), 'veículo não dito');
  v_quatro := right(regexp_replace(coalesce(v_ped.whatsapp_informado, ''), '\D', '', 'g'), 4);
  if v_ped.mais_pedidos > 0 then
    v_mais := format(' · +%s pedidos nesta conversa, ainda sem dados: leia no celular', v_ped.mais_pedidos);
  end if;

  if coalesce(v_ped.cadastro_simulado ->> 'acao', '') = 'perguntar' and v_ped.client_id is null then
    -- Duplicado por telefone: nada foi criado, e o cadastro que já existe nunca é usado por conta própria.
    v_forma := 'duplicado';
    v_texto := format('%s. Pedido da %s para cliente dela · %s · %s · %s · o número que a %s passou (••%s) já é de um cliente cadastrado; nada foi criado: responda pelo celular ou orce na tela para ele.%s *resolvido %s*',
                      p_n, v_rotulo, v_nome, v_vei, v_trecho, coalesce(v_sigla, 'parceira'), v_quatro, v_mais, p_n);
  elsif v_ped.client_id is null then
    v_forma := 'sem_cadastro';
    v_texto := format('%s. Pedido da %s para cliente dela · %s (sem cadastro) · %s · %s%s · Sem cadastro, nada foi criado: responda pelo celular. *resolvido %s*',
                      p_n, v_rotulo, v_nome, v_vei, v_trecho, v_mais, p_n);
  else
    v_forma := 'cadastro';
    select * into v_cli from public.clients c where c.id = v_ped.client_id;

    -- A proposta (com previa_modo ligado) ou o rascunho do cliente provisório.
    if v_cfg.previa_modo = 'ligado' then
      select p.* into v_pv
        from public.retorno_previa p
       where p.abertura_id = v_ped.abertura_id and p.estado = 'proposta'
       order by p.criada_em desc, p.id
       limit 1;
    end if;
    if v_pv.id is not null then
      if v_pv.provisorios_n = 0 and v_pv.linhas_n > 0 and v_pv.total > 0 then
        v_acao := 'orcar';
        v_linha := format('Proposta%s: %s · R$ %s',
                          case when v_pv.origem = 'ditado' then ' ditada'
                               when v_pv.fonte_numero is not null then ' com base no ' || v_pv.fonte_numero else '' end,
                          case when v_pv.linhas_n = 1 then '1 item' else v_pv.linhas_n || ' itens' end,
                          public._retorno_brl(v_pv.total));
      else
        v_linha := 'Proposta incompleta: dite ao assistente o que falta ou orce na tela; o PDF volta aqui.';
      end if;
    else
      v_rasc := public._parceiro_rascunho_do_pedido(p_pedido, v_agora);
      if v_rasc is null then
        v_linha := 'Sem proposta. Dite ao assistente ou orce na tela; o PDF volta aqui.';
      elsif coalesce((v_rasc ->> 'total')::numeric, 0) > 0 and (v_rasc ->> 'linhas_n')::integer > 0
            and (v_rasc ->> 'linhas_sem_preco')::integer = 0 then
        v_acao := 'pdf';
        v_so := (v_rasc ->> 'service_order_id')::uuid;
        v_numero := v_rasc ->> 'numero';
        v_linha := format('Rascunho %s de %s: %s · R$ %s', v_numero,
                          to_char((v_rasc ->> 'criado_em')::timestamptz at time zone c_fuso, 'DD/MM'),
                          case when (v_rasc ->> 'linhas_n')::integer = 1 then '1 item' else (v_rasc ->> 'linhas_n') || ' itens' end,
                          public._retorno_brl((v_rasc ->> 'total')::numeric));
      else
        v_linha := format('Rascunho %s está sem valor: complete na tela; o PDF volta aqui.', v_rasc ->> 'numero');
      end if;
    end if;

    if v_acao is not null then
      -- A: ao cliente, com o número do cadastro ou o que a parceira passou com autorização (o *sim* copia ao cadastro).
      v_tel := coalesce(nullif(btrim(v_cli.whatsapp), ''), nullif(btrim(v_cli.phone), ''));
      if v_tel is not null then
        v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'A', 'acao', 'cliente',
                      'rotulo', format('ao cliente ••%s', right(regexp_replace(v_tel, '\D', '', 'g'), 4))));
      elsif v_ped.whatsapp_informado is not null then
        v_mostrou := true;
        v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'A', 'acao', 'cliente',
                      'rotulo', format('ao cliente ••%s (passado pela %s)', v_quatro, coalesce(v_sigla, 'parceira'))));
      else
        v_partes := v_partes || 'ao cliente: quando tiver o número'::text;
      end if;
      -- B: à parceira, só com o PDF ao parceiro ligado. Só indicou: requalifica no *sim* (decisão do dono).
      if v_cfg.pdf_parceiro_ligado then
        v_ja_comercial := v_so is not null and exists (
          select 1 from public.os_interessados oi
           where oi.service_order_id = v_so and oi.parceiro_id = v_ped.parceiro_id
             and oi.situacao = 'confirmado' and oi.papel in ('contratante', 'pagador'));
        v_rot_b := format('à %s', coalesce(v_sigla, 'parceira'))
                   || case when not v_ja_comercial then ' (ela contrata?)' else '' end
                   || case when not v_cfg.pdf_sem_espera_ligado then ' (o PDF só sai depois do aviso e de 24 h)' else '' end;
        v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'B', 'acao', 'parceiro', 'rotulo', v_rot_b));
      end if;
    end if;
    -- D: desfaz o cadastro, só com o cliente sem nenhuma OS.
    if not exists (select 1 from public.service_orders so where so.client_id = v_ped.client_id) then
      v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'D', 'acao', 'desfazer', 'rotulo', 'desfaz o cadastro'));
    end if;

    v_texto := format('%s. Pedido da %s para cliente dela · %s (cadastro provisório) · %s · %s', p_n, v_rotulo, v_nome, v_vei, v_trecho)
               || case when v_ped.whatsapp_informado is not null and not v_mostrou
                       then format(' · número passado pela %s: ••%s', coalesce(v_sigla, 'parceira'), v_quatro) else '' end
               || v_mais
               || E'\n   ' || v_linha
               || coalesce(E'\n   ' || nullif((select string_agg(format('*%s %s* %s', p_n, o ->> 'letra', o ->> 'rotulo'), ' · ' order by k)
                                                  from jsonb_array_elements(v_opcoes) with ordinality t(o, k)), ''), '')
               || case when cardinality(v_partes) > 0 then ' · ' || array_to_string(v_partes, ' · ') else '' end
               || case when exists (select 1 from jsonb_array_elements(v_opcoes) o where o ->> 'letra' = 'B') and not v_ja_comercial
                       then format(' · o PDF à %s leva preço e Pix de %s; fica registrado como decisão sua', coalesce(v_sigla, 'parceira'), v_nome)
                       else '' end;
  end if;

  return jsonb_build_object(
    'tipo', 'pedido', 'pedido_id', v_ped.id, 'abertura_id', v_ped.abertura_id, 'service_order_id', v_so,
    'texto_mostrado', v_texto, 'opcoes', v_opcoes,
    'retrato', jsonb_build_object('exige_letra', true, 'forma', v_forma, 'acao', v_acao, 'previa_id', v_pv.id,
                                  'service_order_id', v_so, 'numero', v_numero, 'mais_pedidos', v_ped.mais_pedidos),
    'selecionado', true,
    'hash', public._parceiro_item_impressao('pedido', v_ped.id, v_agora));
end;
$$;

comment on function public.parceiro_pedido_montar(uuid, smallint, timestamptz) is
  'Retorno F4 (P10.1, P8.1): o item pedido do cartão do parceiro. Duplicado por telefone ou sem cadastro: só *resolvido N*, sem letras. Com cadastro: a proposta (orcar, com previa_modo ligado) ou o rascunho do cliente provisório (pdf); A ao cliente (cadastro ou número passado pela parceira, só ••NNNN), B à parceira (só com pdf_parceiro_ligado; "ela contrata?" quando ainda não é contratante ou pagadora), D desfaz o cadastro (cliente sem OS). Sem orcar nem pdf, A e B não existem.';

revoke all on function public.parceiro_pedido_montar(uuid, smallint, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_pedido_montar(uuid, smallint, timestamptz) to service_role;

-- ── 7. A letra D: desfazer o cadastro (chamada só pelo parceiro_cartao_executar) ───────────────────────────────────────

create or replace function public.parceiro_pedido_desfazer(p_pedido uuid, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_ped public.parceiro_pedidos;
  v_ab public.retorno_aberturas;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    raise exception using errcode = '42501', message = 'parceiro_pedido_desfazer: só o dono';
  end if;
  select * into v_ped from public.parceiro_pedidos pp where pp.id = p_pedido for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sem_pedido');
  end if;
  if v_ped.client_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_cadastro');
  end if;
  if v_ped.estado is distinct from 'cartao' then
    return jsonb_build_object('ok', false, 'motivo', 'fora_do_cartao');
  end if;
  if exists (select 1 from public.service_orders so where so.client_id = v_ped.client_id) then
    return jsonb_build_object('ok', false, 'motivo', 'tem_os');
  end if;

  update public.clients c set active = false where c.id = v_ped.client_id;
  update public.vessels v set active = false where v.client_id = v_ped.client_id;
  update public.parceiro_pedidos pp
     set whatsapp_informado = null, estado = 'caiu', caiu_motivo = 'desfeito',
         completo_em = coalesce(pp.completo_em, v_agora), atualizado_em = v_agora
   where pp.id = v_ped.id;
  select * into v_ab from public.retorno_aberturas a where a.id = v_ped.abertura_id;
  if v_ab.id is not null and v_ab.estado is distinct from 'fechada' then
    perform public._parceiro_fila_por('pergunta', v_ped.parceiro_id, v_ab.id, 'pergunta:' || v_ab.id, null,
                                      jsonb_build_object('ultima_msg_id', v_ab.ultima_msg_id, 'ultima_em', v_ab.ultima_em));
  end if;
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('clients', v_ped.client_id, 'update', 'dono', jsonb_build_object('active', true),
          jsonb_build_object('active', false, 'pedido_id', v_ped.id, 'caso', v_ped.abertura_id),
          'Retorno F4: cadastro provisório do pedido do parceiro desfeito pelo dono (letra D)');
  return jsonb_build_object('ok', true, 'pedido_id', v_ped.id);
end;
$$;

comment on function public.parceiro_pedido_desfazer(uuid, uuid, timestamptz) is
  'Retorno F4 (P10.1, letra D): só o dono (42501). Pedido em cartao, com client_id e cliente sem nenhuma OS: desativa cliente e unidades, zera whatsapp_informado, leva o pedido a caiu/desfeito, põe a pergunta na fila e audita (clients, update, dono). Depois disso _retorno_cadastro_do_caso dá nulo.';

revoke all on function public.parceiro_pedido_desfazer(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_pedido_desfazer(uuid, uuid, timestamptz) to service_role;

-- ── 8. O vínculo do pedido (Ordem no *sim <PIN>*, passo 3) ────────────────────────────────────────────────────────────

-- Nos dois destinos, com a OS já criada (ramo orcar) ou o rascunho (ramo pdf). Tudo ou nada: o rascunho do cliente do
-- pedido sem origem ganha a origem do parceiro (com audit_log); o vínculo proposto (indicou, numero_do_pedido, a pessoa do
-- pedido) é confirmado; só com destino parceiro, requalificado a contratante (decisao_do_dono). Falha em qualquer passo:
-- nada fica gravado, e o dono ouve a frase.
create or replace function public.parceiro_vinculo_do_pedido(p_pedido uuid, p_so uuid, p_autor uuid, p_destino text,
                                                             p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_ped public.parceiro_pedidos;
  v_so record;
  v_sigla text;
  v_oi public.os_interessados;
  v_id uuid;
  v_r jsonb;
  v_q jsonb;
  v_papel text;
  v_motivo text;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    raise exception using errcode = '42501', message = 'parceiro_vinculo_do_pedido: só o dono';
  end if;
  if p_destino is null or p_destino not in ('cliente', 'parceiro') then
    raise exception using errcode = '22023', message = 'parceiro_vinculo_do_pedido: destino fora da lista';
  end if;
  select * into v_ped from public.parceiro_pedidos pp where pp.id = p_pedido for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sem_pedido', 'frase', 'não achei o pedido; nada saiu');
  end if;
  select pa.sigla into v_sigla from public.parceiros pa where pa.id = v_ped.parceiro_id;
  select so.id, so.client_id, so.status, so.origem_parceiro_id, so.merged_into_id into v_so
    from public.service_orders so where so.id = p_so for update;
  if v_so.id is null or v_so.merged_into_id is not null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_os', 'frase', 'não achei o orçamento; nada saiu');
  end if;
  if v_ped.client_id is null or v_so.client_id is distinct from v_ped.client_id then
    return jsonb_build_object('ok', false, 'motivo', 'outro_cliente', 'frase', 'esse orçamento é de outro cliente; nada saiu');
  end if;
  if v_so.origem_parceiro_id is not null and v_so.origem_parceiro_id is distinct from v_ped.parceiro_id then
    return jsonb_build_object('ok', false, 'motivo', 'outro_parceiro',
                              'frase', 'esse orçamento está ligado a outro parceiro; nada saiu');
  end if;

  begin
    -- O rascunho do cliente nascido deste pedido, feito na tela ou ditado, ganha a origem: sem ela, a regra 8 recusaria.
    if v_so.origem_parceiro_id is null and v_so.status = 'draft' then
      update public.service_orders so set origem_parceiro_id = v_ped.parceiro_id where so.id = v_so.id;
      insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
      values ('service_orders', v_so.id, 'update', 'dono', jsonb_build_object('origem_parceiro_id', null),
              jsonb_build_object('origem_parceiro_id', v_ped.parceiro_id, 'pedido_id', v_ped.id),
              'Retorno F4: o orçamento do pedido do parceiro ganhou a origem dele no *sim <PIN>* do dono');
    end if;

    select * into v_oi
      from public.os_interessados oi
     where oi.service_order_id = v_so.id and oi.parceiro_id = v_ped.parceiro_id and oi.papel is distinct from 'anfitria'
     for update;
    if found then
      if v_oi.situacao = 'proposto' then
        v_r := public._parceiro_confirmar(v_oi.id, p_autor, null, v_agora, coalesce(v_oi.papel, 'indicou'), v_ped.pessoa_id);
      elsif v_oi.situacao = 'confirmado' then
        v_r := jsonb_build_object('ok', true, 'interessado_id', v_oi.id, 'papel', v_oi.papel, 'aviso', 'ja_confirmado');
      else
        raise exception using errcode = 'P0001', message = 'vinculo_' || v_oi.situacao;
      end if;
    else
      if public._parceiro_veto_de(v_so.client_id, v_ped.parceiro_id, v_agora) is not null then
        raise exception using errcode = 'P0001', message = 'veto';
      end if;
      insert into public.os_interessados (service_order_id, parceiro_id, client_id, pessoa_id, papel, situacao, origem)
      values (v_so.id, v_ped.parceiro_id, v_so.client_id, v_ped.pessoa_id, 'indicou', 'proposto', 'numero_do_pedido')
      returning id into v_id;
      v_r := public._parceiro_confirmar(v_id, p_autor, null, v_agora, 'indicou', v_ped.pessoa_id);
    end if;
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0001', message = coalesce(v_r ->> 'motivo', 'erro');
    end if;
    v_papel := v_r ->> 'papel';
    -- Só com destino parceiro: valor nunca a quem só indicou. O *sim <PIN>* é o ato; a base fica decisao_do_dono.
    if p_destino = 'parceiro' and coalesce(v_papel, '') not in ('contratante', 'pagador') then
      v_q := public.parceiro_requalificar((v_r ->> 'interessado_id')::uuid, 'contratante', p_autor, 'decisao_do_dono', v_agora,
                                          v_ped.pessoa_id);
      if not coalesce((v_q ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0001', message = 'requalificar_' || coalesce(v_q ->> 'motivo', 'erro');
      end if;
      v_papel := v_q ->> 'papel';
    end if;
  exception when raise_exception then
    v_motivo := sqlerrm;
    return jsonb_build_object('ok', false, 'motivo', v_motivo,
      'frase', case when v_motivo = 'veto' then format('o cliente pediu que a %s não acompanhe; nada saiu', coalesce(v_sigla, 'parceira'))
                    when v_motivo = 'os_fora' then format('o orçamento não está em andamento para a %s; nada saiu', coalesce(v_sigla, 'parceira'))
                    else format('não consegui ligar o orçamento à %s (%s); nada saiu', coalesce(v_sigla, 'parceira'),
                                replace(v_motivo, '_', ' ')) end);
  end;

  return jsonb_build_object('ok', true, 'interessado_id', v_r ->> 'interessado_id', 'papel', v_papel, 'aviso', v_r ->> 'aviso',
                            'requalificado', v_q is not null);
end;
$$;

comment on function public.parceiro_vinculo_do_pedido(uuid, uuid, uuid, text, timestamptz) is
  'Retorno F4 (P10.1, passo 3, C-PEDIDO): só o dono (42501). Com a OS do cliente do pedido (outro cliente ou origem de outro parceiro recusa): rascunho sem origem ganha origem_parceiro_id (audit_log); vínculo proposto indicou (numero_do_pedido, pessoa do pedido) e _parceiro_confirmar (com telefone, o aviso sai como na P6); só com destino parceiro, parceiro_requalificar a contratante (decisao_do_dono). Tudo ou nada: {ok, interessado_id, papel, aviso, requalificado} ou {ok: false, motivo, frase}.';

revoke all on function public.parceiro_vinculo_do_pedido(uuid, uuid, uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_vinculo_do_pedido(uuid, uuid, uuid, text, timestamptz) to service_role;

-- ── 9. Gerados do corpo vigente, com os trechos -- F4 ─────────────────────────────────────────────────────────────────────

create or replace function public.retorno_previa_montar(p_abertura uuid, p_agora timestamptz default now(), p_fonte uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_ab public.retorno_aberturas;
  v_int text;
  v_cad jsonb;
  v_cliente uuid;
  v_familias text[];
  v_un jsonb;
  v_vessel uuid;
  v_unidades jsonb;
  v_classe text;
  v_bem text;
  v_n_classes integer;
  v_alguma_nula boolean;
  v_par record;
  v_fonte_client uuid;
  v_fonte_vessel uuid;
  r record;
  v_ordem integer := 0;
  v_nome text;
  v_limpo text;
  v_p jsonb;
  v_preco numeric;
  v_fonte_preco text;
  v_em date;
  v_estado_linha text;
  v_motivo text;
  v_linhas jsonb := '[]'::jsonb;
  v_iniciais jsonb := '[]'::jsonb;
  v_total numeric(14,2) := 0;
  v_prov integer := 0;
  v_antigo date;
  v_titulo text;
  v_hash text;
  v_estado_vivo text;
  v_viva public.retorno_previa;
  v_alternativas jsonb;
  v_id uuid;
begin
  -- 1. A chave geral e a trava do caso. p_fonte só vale em 'ligado'.
  if v_cfg.previa_modo = 'desligado' or (p_fonte is not null and v_cfg.previa_modo <> 'ligado') then
    return jsonb_build_object('acao', 'nada', 'motivo', 'desligado');
  end if;
  perform pg_advisory_xact_lock(hashtext('retorno:previa:' || p_abertura));

  -- 2. Caso vivo, papel, áudio, visita.
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  if not found or v_ab.estado not in ('aberta', 'vencida') or v_ab.cumprida_em is not null then
    return jsonb_build_object('acao', 'nada', 'motivo', 'caso_fechado');
  end if;
  -- F4 (P10): o caso do parceiro só com o pedido em cadastrado ou cartao e o client_id preenchido (o cadastro provisório).
  if v_ab.papel not in ('cliente', 'numero_novo')
     and not (v_ab.papel = 'parceiro'
              and exists (select 1 from public.parceiro_pedidos pp
                           where pp.abertura_id = v_ab.id and pp.estado in ('cadastrado', 'cartao') and pp.client_id is not null)) then
    return jsonb_build_object('acao', 'nada', 'motivo', 'papel');
  end if;
  if exists (select 1 from public.retorno_mensagens m
              where m.abertura_id = p_abertura and m.audio_pendente and m.recebida_em <= v_agora) then
    return jsonb_build_object('acao', 'nada', 'motivo', 'aguarda_transcricao');
  end if;
  if v_ab.visita_a_combinar_em is not null
     or exists (select 1 from public.retorno_previa p where p.abertura_id = p_abertura and p.estado = 'ver_no_local') then
    return jsonb_build_object('acao', 'nada', 'motivo', 'visita_a_combinar');
  end if;

  -- 3. Intenção.
  v_int := public._retorno_intencao_do_caso(p_abertura, v_agora);
  if v_int is null or v_int not in ('orcamento', 'adicional') then
    return jsonb_build_object('acao', 'nada', 'motivo', 'intencao');
  end if;

  -- 4. Cadastro.
  v_cad := public._retorno_cadastro_do_caso(p_abertura);
  v_cliente := (v_cad ->> 'client_id')::uuid;
  if v_cliente is not null and exists (select 1 from public.clients c where c.id = v_cliente and c.generico) then
    return jsonb_build_object('acao', 'nada', 'motivo', 'cliente_final');
  end if;
  if v_cliente is null and v_ab.papel = 'cliente' then
    return jsonb_build_object('acao', 'nada', 'motivo', 'sem_cliente');
  end if;

  -- 5. Rascunho do caso: o cartão oferece o PDF dele.
  if public._retorno_rascunho_do_caso(p_abertura, v_agora) is not null then
    return jsonb_build_object('acao', 'nada', 'motivo', 'ja_tem_orcamento');
  end if;

  -- 6. Famílias do caso: as mensagens que pedem resposta e o que o número novo disse (servico e detalhes da coleta).
  select public._retorno_familias(public._retorno_busca(
           coalesce(string_agg(w.body, ' '), '') || ' ' || coalesce(v_ab.coleta ->> 'servico', '') || ' ' || coalesce(v_ab.coleta ->> 'detalhes', '')))
    into v_familias
    from public.retorno_mensagens m
    join public.whatsapp_messages w on w.id = m.whatsapp_message_id
   where m.abertura_id = p_abertura and m.pede_resposta and m.recebida_em <= v_agora;
  if v_familias is null or cardinality(v_familias) = 0 then
    return jsonb_build_object('acao', 'nada', 'motivo', 'sem_familia');
  end if;

  -- 7. Classe e unidade.
  v_un := public._retorno_unidade_do_caso(p_abertura, v_cliente, v_agora);
  v_vessel := (v_un ->> 'vessel_id')::uuid;
  v_unidades := '[]'::jsonb;
  if v_vessel is not null then
    select public._retorno_classe_do_bem(v.asset_type) into v_classe from public.vessels v where v.id = v_vessel;
  elsif jsonb_array_length(coalesce(v_un -> 'unidades', '[]'::jsonb)) > 0 then
    v_unidades := v_un -> 'unidades';
    select count(distinct public._retorno_classe_do_bem(v.asset_type)),
           bool_or(public._retorno_classe_do_bem(v.asset_type) is null),
           min(public._retorno_classe_do_bem(v.asset_type))
      into v_n_classes, v_alguma_nula, v_classe
      from jsonb_array_elements(v_unidades) u
      join public.vessels v on v.id = (u ->> 'vessel_id')::uuid;
    if coalesce(v_alguma_nula, true) or v_n_classes <> 1 then
      return jsonb_build_object('acao', 'nada', 'motivo', 'unidades_mistas');
    end if;
  else
    -- 0 unidades: a classe sai do que o cliente disse. Sem unidade no cadastro, nunca se cria unidade aqui.
    select s.palavra into v_bem
      from (select public._retorno_sinais(w.body) ->> 'bem_palavra' as palavra, m.recebida_em, m.whatsapp_message_id
              from public.retorno_mensagens m
              join public.whatsapp_messages w on w.id = m.whatsapp_message_id
             where m.abertura_id = p_abertura and m.recebida_em <= v_agora) s
     where s.palavra is not null
     order by s.recebida_em desc, s.whatsapp_message_id
     limit 1;
    v_classe := public._retorno_classe_do_bem(coalesce(v_bem, v_ab.coleta ->> 'tipo'));
  end if;
  if v_classe is null then
    return jsonb_build_object('acao', 'nada', 'motivo', 'sem_classe');
  end if;

  -- 8. O parecido. O que nasceu depois da abertura do caso não serve.
  if p_fonte is null then
    select * into v_par
      from public.retorno_parecidos(v_familias, v_classe, v_cliente, v_vessel, v_ab.aberta_em, v_agora, 2)
     limit 1;
  else
    select * into v_par
      from public.retorno_parecidos(v_familias, v_classe, v_cliente, v_vessel, v_ab.aberta_em, v_agora, 20) p
     where p.os_id = p_fonte;
  end if;
  if not found then
    return jsonb_build_object('acao', 'nada', 'motivo', 'sem_parecido');
  end if;
  select so.client_id, so.vessel_id into v_fonte_client, v_fonte_vessel from public.service_orders so where so.id = v_par.os_id;

  -- 9 e 10. As linhas em memória: peças antes, depois serviços; dentro do grupo por created_at e id da fonte.
  for r in
    select x.* from (
      select 1 as grupo, p.created_at as momento, p.id as linha_id, 'peca'::text as tipo, p.product_id, null::uuid as service_id,
             pr.name::text as nome_cat, pr.active as ativo, p.quantity as qtd, null::text as nome_fonte
        from public.service_order_parts p
        join public.products pr on pr.id = p.product_id
       where p.service_order_id = v_par.os_id
      union all
      select 2, s.created_at, s.id, 'servico', null::uuid, s.service_id, sv.name, coalesce(sv.active, true), s.quantity, s.name_snapshot
        from public.service_order_services s
        left join public.services sv on sv.id = s.service_id
       where s.service_order_id = v_par.os_id
    ) x
    order by x.grupo, x.momento nulls last, x.linha_id
  loop
    if r.qtd is null or r.qtd <= 0 then
      continue;   -- retorno_previa_linhas exige quantidade > 0: linha sem quantidade não entra
    end if;
    v_ordem := v_ordem + 1;
    v_estado_linha := 'ok';
    v_motivo := null;
    v_preco := null;
    v_fonte_preco := 'sem_preco';
    v_em := null;
    v_p := null;

    if r.tipo = 'peca' then
      v_nome := left(r.nome_cat, 200);
      if not r.ativo then
        v_estado_linha := 'provisorio';
        v_motivo := 'inativo';
      else
        v_p := public._retorno_preco_da_peca(r.product_id, v_cliente, v_agora);
      end if;
    elsif r.service_id is not null then
      -- O nome de catálogo pode ter nascido de uma mão de obra ditada (ai_servico_pendente_catalogo): passa pela mesma limpeza da linha livre.
      if public._retorno_nome_limpo(r.nome_cat, v_fonte_client, v_fonte_vessel) is null then
        v_nome := 'Serviço a descrever';
        v_estado_linha := 'provisorio';
        v_motivo := 'nome_com_dado_de_outro';
      else
        v_nome := left(r.nome_cat, 200);
        if not r.ativo then
          v_estado_linha := 'provisorio';
          v_motivo := 'inativo';
        else
          v_p := public._retorno_preco_do_servico(r.service_id, r.nome_cat, v_cliente, v_agora);
        end if;
      end if;
    else
      v_limpo := public._retorno_nome_limpo(r.nome_fonte, v_fonte_client, v_fonte_vessel);
      if v_limpo is null then
        v_nome := 'Serviço a descrever';
        v_estado_linha := 'provisorio';
        v_motivo := 'nome_com_dado_de_outro';
      else
        v_nome := left(v_limpo, 200);
        v_p := public._retorno_preco_do_servico(null, v_limpo, v_cliente, v_agora);
      end if;
    end if;

    if v_p is not null then
      v_preco := (v_p ->> 'preco')::numeric;
      v_fonte_preco := v_p ->> 'fonte';
      v_em := (v_p ->> 'em')::date;
      if v_preco is null or v_fonte_preco = 'sem_preco' then
        v_preco := null;
        v_fonte_preco := 'sem_preco';
        v_em := null;
        v_estado_linha := 'provisorio';
        v_motivo := 'sem_preco';
      end if;
    end if;

    if v_preco is not null then
      v_total := v_total + round(r.qtd * v_preco, 2);
    end if;
    if v_estado_linha = 'provisorio' then
      v_prov := v_prov + 1;
    end if;
    v_antigo := case when v_em is not null then least(coalesce(v_antigo, v_em), v_em) else v_antigo end;

    v_linhas := v_linhas || jsonb_build_array(jsonb_build_object(
      'ordem', v_ordem, 'tipo', r.tipo, 'product_id', r.product_id, 'service_id', r.service_id, 'nome', v_nome,
      'quantidade', r.qtd, 'preco', v_preco, 'preco_fonte', v_fonte_preco, 'preco_em', v_em, 'estado', v_estado_linha, 'motivo', v_motivo));
    v_iniciais := v_iniciais || jsonb_build_array(jsonb_build_object(
      'tipo', r.tipo, 'product_id', r.product_id, 'service_id', r.service_id, 'nome', v_nome, 'quantidade', r.qtd, 'preco', v_preco));
  end loop;

  if v_ordem = 0 then
    return jsonb_build_object('acao', 'nada', 'motivo', 'sem_parecido');
  end if;

  v_titulo := public._retorno_familia_rotulo(v_familias) ->> 'titulo';
  v_hash := public._retorno_previa_hash(v_vessel, v_titulo, v_linhas);

  -- 11. A viva do estado que este modo governa.
  v_estado_vivo := case when v_cfg.previa_modo = 'sombra' then 'sombra' else 'proposta' end;
  select * into v_viva from public.retorno_previa p where p.abertura_id = p_abertura and p.estado = v_estado_vivo for update;
  if found then
    -- O cliente que apareceu entra sem mexer no hash: a comparação da P11 procura o ORÇ pelo cliente.
    if v_viva.client_id is null and v_cliente is not null then
      update public.retorno_previa p set client_id = v_cliente where p.id = v_viva.id;
    end if;
    if p_fonte is null and v_viva.vessel_id is null and v_vessel is not null then
      update public.retorno_previa p
         set vessel_id = v_vessel,
             hash = public._retorno_previa_hash(v_vessel, v_viva.titulo, public._retorno_previa_linhas_json(v_viva.id)),
             atualizada_em = v_agora
       where p.id = v_viva.id;
      return jsonb_build_object('acao', 'mantida', 'previa_id', v_viva.id);
    end if;
    if p_fonte is null and coalesce((v_viva.dados ->> 'travada')::boolean, false) then
      update public.retorno_previa p set atualizada_em = v_agora where p.id = v_viva.id;
      return jsonb_build_object('acao', 'mantida', 'previa_id', v_viva.id);
    end if;
    if v_viva.hash = v_hash then
      update public.retorno_previa p set atualizada_em = v_agora where p.id = v_viva.id;
      return jsonb_build_object('acao', 'mantida', 'previa_id', v_viva.id);
    end if;
    update public.retorno_previa p set estado = 'descartada', atualizada_em = v_agora where p.id = v_viva.id;
  end if;

  -- 12. Nova proposta. As alternativas são os outros parecidos: depois de *B*, volta o original.
  select coalesce(jsonb_agg(jsonb_build_object('os_id', x.os_id, 'numero', x.numero, 'em', x.criada_em) order by x.ord), '[]'::jsonb)
    into v_alternativas
    from public.retorno_parecidos(v_familias, v_classe, v_cliente, v_vessel, v_ab.aberta_em, v_agora, 2)
         with ordinality as x(os_id, numero, criada_em, mesma_unidade, mesmo_cliente, familia_igual, aprovado, linhas_n, ord)
   where x.os_id <> v_par.os_id;

  insert into public.retorno_previa (abertura_id, chave, client_id, vessel_id, origem, fonte_os_id, fonte_numero, fonte_em, familias, titulo,
                                     estado, modo, total, linhas_n, provisorios_n, preco_mais_antigo, linhas_iniciais, hash, dados, criada_em, atualizada_em)
  values (p_abertura, v_ab.chave, v_cliente, v_vessel, 'historico', v_par.os_id, v_par.numero, v_par.criada_em, v_familias, v_titulo,
          v_estado_vivo, v_cfg.previa_modo, v_total, v_ordem, v_prov, v_antigo, v_iniciais, v_hash,
          jsonb_build_object('alternativas', v_alternativas, 'unidades', v_unidades, 'motivo', v_un ->> 'motivo',
                             'forte', v_par.mesmo_cliente and v_par.familia_igual, 'fonte_aprovada', v_par.aprovado,
                             'travada', p_fonte is not null),
          v_agora, v_agora)
  returning id into v_id;

  insert into public.retorno_previa_linhas (previa_id, ordem, tipo, product_id, service_id, nome, quantidade, preco, preco_fonte, preco_em, estado, motivo)
  select v_id, (l ->> 'ordem')::smallint, l ->> 'tipo', (l ->> 'product_id')::uuid, (l ->> 'service_id')::uuid, l ->> 'nome',
         (l ->> 'quantidade')::numeric, (l ->> 'preco')::numeric, l ->> 'preco_fonte', (l ->> 'preco_em')::date, l ->> 'estado', l ->> 'motivo'
    from jsonb_array_elements(v_linhas) l;

  return jsonb_build_object('acao', 'criada', 'previa_id', v_id);
end;
$$;

create or replace function public.retorno_previa_rodada(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_estado text;
  r record;
  v_res jsonb;
  v_casos integer := 0;
  v_criadas integer := 0;
  v_mantidas integer := 0;
  v_erros integer := 0;
begin
  if v_cfg.previa_modo = 'desligado' then
    return jsonb_build_object('casos', 0, 'criadas', 0, 'mantidas', 0, 'erros', 0);
  end if;
  v_estado := case when v_cfg.previa_modo = 'sombra' then 'sombra' else 'proposta' end;

  for r in
    select a.id
      from public.retorno_aberturas a
     where a.estado in ('aberta', 'vencida')
       and a.cumprida_em is null
       and (a.papel in ('cliente', 'numero_novo') or (a.papel = 'parceiro' and exists (select 1 from public.parceiro_pedidos pp where pp.abertura_id = a.id and pp.estado in ('cadastrado', 'cartao') and pp.client_id is not null)))   -- F4 (P10)
       and a.visita_a_combinar_em is null
       and not exists (select 1 from public.retorno_previa v where v.abertura_id = a.id and v.estado = 'ver_no_local')
       and (not exists (select 1 from public.retorno_previa v where v.abertura_id = a.id and v.estado = v_estado)
            or exists (select 1 from public.retorno_previa v where v.abertura_id = a.id and v.estado = v_estado
                        and (v.atualizada_em < a.ultima_em or v.vessel_id is null)))
     order by a.ultima_em desc, a.id
     limit 20
  loop
    v_casos := v_casos + 1;
    begin
      v_res := public.retorno_previa_montar(r.id, v_agora);
      if v_res ->> 'acao' = 'criada' then
        v_criadas := v_criadas + 1;
      elsif v_res ->> 'acao' = 'mantida' then
        v_mantidas := v_mantidas + 1;
      end if;
    exception when others then
      v_erros := v_erros + 1;
      perform public._retorno_log('previa_rodada', 'retorno_previa_rodada: ' || sqlerrm, 'error', jsonb_build_object('abertura_id', r.id));
    end;
  end loop;

  -- As vivas de caso que fechou saem de cena.
  update public.retorno_previa p
     set estado = 'descartada', atualizada_em = v_agora
    from public.retorno_aberturas a
   where a.id = p.abertura_id and a.estado = 'fechada' and p.estado in ('sombra', 'proposta');

  return jsonb_build_object('casos', v_casos, 'criadas', v_criadas, 'mantidas', v_mantidas, 'erros', v_erros);
end;
$$;

create or replace function public.parceiro_previa_preparar(p_pedido uuid, p_previa uuid, p_item uuid, p_autor uuid, p_so uuid, p_destino text,
                                                         p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_pv public.retorno_previa;
  v_i public.parceiro_cartao_itens;   -- F4 (P10): o item é do cartão do parceiro
  v_ped public.parceiro_pedidos;      -- F4 (P10)
  v_ab public.retorno_aberturas;
  v_abertura uuid;
  v_rasc jsonb;
  v_so public.service_orders;
  v_cad jsonb;
  v_cli uuid;
  v_ves uuid;
  v_unidades jsonb;
  v_fone text;
  v_quatro text;
  v_nomes text;
  v_acao text := case when p_so is not null then 'pdf' else 'orcar' end;
  v_legenda jsonb;
  v_previa_pdf uuid;
  v_origem text;
  v_items jsonb;
  v_labor jsonb;
  v_args jsonb;
  v_saida jsonb;
begin
  if p_previa is not null then
    select * into v_pv from public.retorno_previa p where p.id = p_previa;
  end if;
  if p_item is not null then
    select * into v_i from public.parceiro_cartao_itens i where i.id = p_item;   -- F4
  end if;
  -- F4 (P10): a abertura vem do pedido; o destino é o cliente ou a parceira.
  if p_destino is null or p_destino not in ('cliente', 'parceiro') then
    raise exception using errcode = '22023', message = 'parceiro_previa_preparar: destino fora da lista';
  end if;
  select * into v_ped from public.parceiro_pedidos pp where pp.id = p_pedido;
  v_abertura := v_ped.abertura_id;
  select * into v_ab from public.retorno_aberturas a where a.id = v_abertura;

  -- Regra 0: a flag da ação.
  if not public._retorno_previa_liberada(v_acao, v_pv.origem) then
    return public._parceiro_previa_recusa(p_pedido, v_abertura, p_previa, p_item, 0, 'desligado',
      'não saiu, porque o orçamento pelo cartão foi desligado; não criei nada', v_agora);
  end if;

  -- Regra 1: só o dono. Sem mexer em nada: outro autor não pode derrubar o item de ninguém.
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return public._parceiro_previa_recusa(p_pedido, v_abertura, p_previa, p_item, 1, 'nao_e_o_dono',
      'não saiu, porque só o dono pode fazer isso; não criei nada', v_agora);
  end if;

  -- Regra 2: proposta viva e caso aberto. No ramo do rascunho, o rascunho tem de ser exatamente o que o cartão oferece.
  if v_acao = 'orcar' then
    if v_ab.id is null or v_ab.estado = 'fechada' or v_pv.id is null or v_pv.estado <> 'proposta'
       -- F4 (P10): a proposta e o item têm de ser deste pedido
       or v_pv.abertura_id is distinct from v_abertura or (p_item is not null and v_i.pedido_id is distinct from p_pedido) then
      return public._parceiro_previa_recusa(p_pedido, v_abertura, p_previa, p_item, 2, 'caso_fechado', 'já não está aberto; não criei nada', v_agora);
    end if;
  else
    v_rasc := public._parceiro_rascunho_do_pedido(p_pedido, v_agora);   -- F4 (P10): o rascunho do cliente provisório
    if v_ab.id is null or v_ab.estado = 'fechada' or v_rasc is null or (v_rasc ->> 'service_order_id')::uuid is distinct from p_so
       or (p_item is not null and v_i.pedido_id is distinct from p_pedido) then   -- F4
      return public._parceiro_previa_recusa(p_pedido, v_abertura, p_previa, p_item, 2, 'caso_fechado', 'já não está aberto; não criei nada', v_agora);
    end if;
    select * into v_so from public.service_orders so where so.id = p_so;
  end if;

  -- Regra 3: nada provisório; nenhum total zerado.
  if v_acao = 'orcar' then
    if v_pv.provisorios_n > 0 then
      select string_agg(left(l.nome, 40), ', ' order by l.ordem) into v_nomes
        from public.retorno_previa_linhas l where l.previa_id = v_pv.id and l.estado = 'provisorio';
      return public._parceiro_previa_recusa(p_pedido, v_abertura, p_previa, p_item, 3, 'item_provisorio',
        format('tem item a completar (%s): não criei nada. Mande *retorno* e dite o que falta', v_nomes), v_agora);
    end if;
    if v_pv.linhas_n <= 0 or v_pv.total <= 0 then
      return public._parceiro_previa_recusa(p_pedido, v_abertura, p_previa, p_item, 3, 'item_provisorio',
        'está sem nenhum item: dite o que entra; não criei nada', v_agora);
    end if;
  else
    if coalesce((v_rasc ->> 'total')::numeric, 0) <= 0 or (v_rasc ->> 'linhas_n')::integer <= 0 or (v_rasc ->> 'linhas_sem_preco')::integer > 0 then
      return public._parceiro_previa_recusa(p_pedido, v_abertura, p_previa, p_item, 3, 'rascunho_sem_valor',
        format('ficou com o rascunho %s sem valor: complete na tela; não mandei', v_rasc ->> 'numero'), v_agora);
    end if;
  end if;

  -- Regra 4: cliente e unidade definidos e ativos. No rascunho, sempre os de service_orders, nunca os do caso.
  if v_acao = 'orcar' then
    v_cad := public._retorno_cadastro_do_caso(v_abertura);
    v_cli := (v_cad ->> 'client_id')::uuid;
    if v_cli is null then
      return public._parceiro_previa_recusa(p_pedido, v_abertura, p_previa, p_item, 4, 'sem_cadastro',
        'ainda não tem cadastro completo: mande *retorno* quando ele responder; não criei nada', v_agora);
    end if;
    v_ves := coalesce(v_pv.vessel_id, (public._retorno_unidade_do_caso(v_abertura, v_cli, v_agora) ->> 'vessel_id')::uuid);
    if v_ves is null or not exists (select 1 from public.vessels v where v.id = v_ves and v.active and v.client_id = v_cli) then
      v_unidades := public._retorno_unidades_do_cliente(v_cli);
      if jsonb_array_length(v_unidades) >= 2 then
        return public._parceiro_previa_recusa(p_pedido, v_abertura, p_previa, p_item, 4, 'sem_cadastro',
          'está sem unidade escolhida: mande *retorno* e a letra; não criei nada', v_agora);
      end if;
      return public._parceiro_previa_recusa(p_pedido, v_abertura, p_previa, p_item, 4, 'sem_cadastro',
        'está sem unidade no cadastro: cadastre e mande *retorno*; não criei nada', v_agora);
    end if;
  else
    v_cli := v_so.client_id;
    v_ves := v_so.vessel_id;
    if not exists (select 1 from public.clients c where c.id = v_cli and c.active) then
      return public._parceiro_previa_recusa(p_pedido, v_abertura, p_previa, p_item, 4, 'sem_cadastro',
        'ainda não tem cadastro completo: mande *retorno* quando ele responder; não criei nada', v_agora);
    end if;
    if v_ves is null or not exists (select 1 from public.vessels v where v.id = v_ves and v.active) then
      return public._parceiro_previa_recusa(p_pedido, v_abertura, p_previa, p_item, 4, 'sem_cadastro',
        'está sem unidade no cadastro: cadastre e mande *retorno*; não criei nada', v_agora);
    end if;
  end if;

  -- Regra 5: Cliente Final. A proposta cai (a regra 5 de _parceiro_previa_recusa). -- F4
  if exists (select 1 from public.clients c where c.id = v_cli and c.generico) then
    return public._parceiro_previa_recusa(p_pedido, v_abertura, p_previa, p_item, 5, 'cliente_final', 'está no Cliente Final: use o celular; não criei nada', v_agora);
  end if;

  -- F4 (P10): a regra 6 é pulada. O caso é da parceira, e o destino é decidido no envio: parceiro_destino_do_pdf, ou o
  -- clients.whatsapp que o *sim <PIN>* do item gravou.

  -- Regra 7: canal livre. A mesma expressão da regra 5 de _retorno_item_conferir: o ditado com cartão caído não passa pelo conferir.
  if public.canal_bloqueado(v_ab.phone_normalized) is not null
     or v_ab.nivel = 'nada'
     or exists (select 1 from public.whatsapp_leads l
                 where l.lead_tipo = 'pessoal' and public._agenda_chave_telefone(l.phone_normalized) = v_ab.chave) then
    return public._parceiro_previa_recusa(p_pedido, v_abertura, p_previa, p_item, 7, 'canal_bloqueado',
      'pediu para não receber mensagem automática; não criei nada', v_agora);
  end if;

  -- Passou. A legenda decide nome, apresentação e a data que vai ao PDF: legenda e documento nunca calculam separado.
  if v_acao = 'pdf' then
    v_previa_pdf := p_previa;
    if v_previa_pdf is null then
      select p.id into v_previa_pdf from public.retorno_previa p
       where p.service_order_id = p_so and p.estado = 'virou_orc'
       order by p.criada_em desc, p.id
       limit 1;
    end if;
    -- F4 (P10): à parceira, a P16 (validador do parceiro); ao cliente, a legenda da F3.
    if p_destino = 'parceiro' then
      begin
        v_legenda := public._parceiro_legenda_do_orcamento(p_pedido, v_cli, v_ves, v_agora);
      exception when sqlstate '22023' then
        return public._parceiro_previa_recusa(p_pedido, v_abertura, p_previa, p_item, 4, 'sem_cadastro',
          'não saiu, porque a legenda à parceira precisa do primeiro nome do cliente e do número dela; não criei nada', v_agora);
      end;
    else
      v_legenda := public.retorno_legenda_do_orcamento(v_abertura, v_previa_pdf, v_agora, v_cli);
    end if;
    return jsonb_build_object('ok', true, 'acao', 'pdf', 'previa_id', v_previa_pdf, 'abertura_id', v_abertura,
      'parceiro_id', v_ped.parceiro_id, 'pedido_id', p_pedido, 'destino', p_destino,   -- F4
      'rotulo', public._retorno_rotulo(v_abertura, v_agora), 'chave8', v_ab.chave,
      'total', coalesce(v_so.grand_total, 0), 'numero', v_so.service_order_number,
      'validade_data', v_legenda ->> 'validade_data', 'legenda', v_legenda);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('product_id', l.product_id, 'quantity', l.quantidade, 'unit_price', l.preco, 'keyword', l.nome) order by l.ordem), '[]'::jsonb)
    into v_items
    from public.retorno_previa_linhas l
   where l.previa_id = v_pv.id and l.tipo = 'peca';
  select coalesce(jsonb_agg(jsonb_build_object('service_id', l.service_id, 'description', l.nome, 'price', l.preco, 'quantity', l.quantidade,
                                               'billing_unit', coalesce(s.billing_unit, 'unit')) order by l.ordem), '[]'::jsonb)
    into v_labor
    from public.retorno_previa_linhas l
    left join public.services s on s.id = l.service_id
   where l.previa_id = v_pv.id and l.tipo = 'servico';

  v_origem := 'retorno_parceiro';   -- F4 (P10, P12.1): o ORÇ nasce com a origem do parceiro e origem_parceiro_id
  v_args := jsonb_build_object('client_id', v_cli, 'vessel_id', v_ves, 'title', v_pv.titulo, 'items', v_items, 'labor', v_labor,
                               'payment_conditions', v_pv.condicao_pagamento, 'origem', v_origem);

  -- F4 (P10): à parceira, a P16 (validador do parceiro); ao cliente, a legenda da F3.
  if p_destino = 'parceiro' then
    begin
      v_legenda := public._parceiro_legenda_do_orcamento(p_pedido, v_cli, v_ves, v_agora);
    exception when sqlstate '22023' then
      return public._parceiro_previa_recusa(p_pedido, v_abertura, p_previa, p_item, 4, 'sem_cadastro',
        'não saiu, porque a legenda à parceira precisa do primeiro nome do cliente e do número dela; não criei nada', v_agora);
    end;
  else
    v_legenda := public.retorno_legenda_do_orcamento(v_abertura, v_pv.id, v_agora);
  end if;
  v_saida := jsonb_build_object('ok', true, 'acao', 'orcar', 'previa_id', v_pv.id, 'abertura_id', v_abertura,
    'parceiro_id', v_ped.parceiro_id, 'pedido_id', p_pedido, 'destino', p_destino,   -- F4
    'rotulo', public._retorno_rotulo(v_abertura, v_agora), 'chave8', v_ab.chave, 'total', v_pv.total,
    'validade_data', v_legenda ->> 'validade_data', 'legenda', v_legenda, 'args', v_args);
  return v_saida;
end;
$$;

create or replace function public.parceiro_previa_soltar(p_item uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_i public.parceiro_cartao_itens;   -- F4 (P10)
  v_ped public.parceiro_pedidos;      -- F4 (P10)
  v_vivo boolean;
begin
  select * into v_i from public.parceiro_cartao_itens i where i.id = p_item for update;   -- F4
  if not found then
    return jsonb_build_object('ok', false);
  end if;
  select c.estado = 'vivo' into v_vivo from public.parceiro_cartoes c where c.id = v_i.cartao_id;   -- F4
  if v_i.estado = 'vivo' and v_vivo then
    null;   -- F4 (P10): o item do parceiro não remonta; o cartão vivo segue com ele, e o dono decide de novo.
  elsif v_i.estado = 'feito' then
    -- O cartão já foi decidido: o caso volta no próximo *retorno*, e decidido_em fica: é o ato do dono que a P11 conta.
    update public.parceiro_cartao_itens i set estado = 'fora' where i.id = p_item;   -- F4
    -- F4 (P10): o orçamento não terminou: o pedido decidido volta a cartao, e a linha da fila de feito a espera, pela porta
    -- (_parceiro_fila_por com p_reabrir). Quem chama nunca passa por aqui no sem_enviar do parceiro (P12.1).
    select * into v_ped from public.parceiro_pedidos pp where pp.id = v_i.pedido_id for update;
    if v_ped.id is not null and v_ped.estado = 'decidido' then
      update public.parceiro_pedidos pp set estado = 'cartao', atualizado_em = v_agora where pp.id = v_ped.id and pp.estado = 'decidido';
      perform public._parceiro_fila_por('pedido', v_ped.parceiro_id, v_ped.id, 'pedido:' || v_ped.id,
                                        v_ped.criado_em + (public._retorno_cfg()).parceiro_pedido_validade,
                                        jsonb_build_object('abertura_id', v_ped.abertura_id), true);
    end if;
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.parceiro_previa_caiu(p_previa uuid, p_item uuid, p_motivo text, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cartao uuid;
begin
  if p_item is not null then
    update public.parceiro_cartao_itens i   -- F4 (P10)
       set estado = 'caiu', caiu_motivo = p_motivo, decidido_em = coalesce(i.decidido_em, v_agora)
     where i.id = p_item and i.estado in ('vivo', 'feito')
     returning i.cartao_id into v_cartao;
    -- Revisão da F3: o último item vivo saiu pelo ditado: o cartão não fica vivo sem nada.
    if v_cartao is not null and not public._parceiro_cartao_fechar_se_vazio(v_cartao, v_agora) then   -- F4
      update public.parceiro_cartoes c set texto = public._parceiro_cartao_texto(c.id, null) where c.id = v_cartao and c.estado = 'vivo';
    end if;
  end if;
  if p_previa is not null then
    update public.retorno_previa p
       set estado = 'caiu', decidida_em = v_agora, atualizada_em = v_agora
     where p.id = p_previa and p.estado = 'proposta';
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.parceiro_previa_pdf(p_previa uuid, p_ok boolean, p_chave text, p_agora timestamptz default now(),
                                                     p_so uuid default null, p_abertura uuid default null, p_item uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_id uuid := p_previa;
  v_abertura uuid := p_abertura;
  v_so public.service_orders;
  v_ab public.retorno_aberturas;
  v_n integer;
  v_cartao uuid;
begin
  if not coalesce(p_ok, false) then
    return jsonb_build_object('ok', true);   -- p_ok falso não grava nada: o ORÇ volta ao cartão pela linha 1
  end if;

  if v_id is null and p_so is not null then
    select p.id into v_id from public.retorno_previa p
     where p.service_order_id = p_so and p.estado = 'virou_orc'
     order by p.criada_em desc, p.id
     limit 1;
  end if;

  if v_id is not null then
    update public.retorno_previa p
       set pdf_em = coalesce(p.pdf_em, v_agora), pdf_chave = coalesce(p_chave, p.pdf_chave), atualizada_em = v_agora
     where p.id = v_id
     returning p.abertura_id into v_abertura;
  elsif p_so is not null then
    -- PDF de rascunho sem proposta: a linha origem 'rascunho' existe para a medida e para a apresentação, e só o PDF que saiu a cria.
    select * into v_so from public.service_orders so where so.id = p_so;
    select * into v_ab from public.retorno_aberturas a where a.id = v_abertura;
    if v_so.id is not null and v_ab.id is not null then
      select (select count(*) from public.service_order_parts p where p.service_order_id = p_so)
           + (select count(*) from public.service_order_services s where s.service_order_id = p_so)
        into v_n;
      insert into public.retorno_previa (abertura_id, chave, client_id, vessel_id, origem, estado, modo, service_order_id, titulo, familias, total,
                                         linhas_n, provisorios_n, linhas_iniciais, hash, pdf_em, pdf_chave, decidida_em, criada_em, atualizada_em)
      values (v_ab.id, v_ab.chave, v_so.client_id, v_so.vessel_id, 'rascunho', 'virou_orc', 'ligado', p_so,
              left('Rascunho ' || coalesce(v_so.service_order_number, ''), 120), '{}', coalesce(v_so.grand_total, 0),
              coalesce(v_n, 0), 0, '[]', '', v_agora, p_chave, v_agora, v_agora, v_agora);
    end if;
  end if;

  if p_item is not null then
    update public.parceiro_cartao_itens i   -- F4 (P10)
       set estado = 'feito', decidido_em = coalesce(i.decidido_em, v_agora)
     where i.id = p_item and i.estado = 'vivo'
     returning i.cartao_id into v_cartao;
    if v_cartao is not null then
      -- Revisão da F3: decide antes de refazer o texto. Era o último caso? O cartão não fica vivo sem item.
      perform public._parceiro_cartao_fechar_se_vazio(v_cartao, v_agora);   -- F4
      update public.parceiro_cartoes c set texto = public._parceiro_cartao_texto(c.id, null) where c.id = v_cartao;
    end if;
  elsif v_abertura is not null then
    -- O cartão caiu antes do *sim <PIN>*: quem fecha o caso é o PDF que saiu.
    update public.retorno_aberturas a
       set cumprida_em = coalesce(a.cumprida_em, v_agora), cumprida_por = coalesce(a.cumprida_por, 'cartao'),
           estado = 'fechada', fechada_em = coalesce(a.fechada_em, v_agora), fechada_motivo = coalesce(a.fechada_motivo, 'conteudo'),
           atualizada_em = now()
     where a.id = v_abertura;
    update public.retorno_saidas s
       set estado = 'cancelada', motivo = 'caso_fechado', decidida_em = v_agora, atualizada_em = now()
     where s.abertura_id = v_abertura and s.estado = 'agendada';
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

comment on function public.retorno_previa_montar(uuid, timestamptz, uuid) is
  'Retorno F3 (P3, C-MONTAR) e F4 (P10): monta a proposta do caso. O caso do parceiro só entra com o pedido em cadastrado ou cartao e client_id preenchido.';
revoke all on function public.retorno_previa_montar(uuid, timestamptz, uuid) from public, anon, authenticated;
grant execute on function public.retorno_previa_montar(uuid, timestamptz, uuid) to service_role;

comment on function public.retorno_previa_rodada(timestamptz) is
  'Retorno F3 (P3, C-RODADA) e F4 (P10): até 20 casos vivos sem proposta do estado do modo, com mensagem nova ou com proposta sem unidade; o caso do parceiro só com o pedido em cadastrado ou cartao e client_id. Erro num caso vira log e o próximo segue. Fecha as propostas vivas de caso fechado. Nunca passa p_fonte.';
revoke all on function public.retorno_previa_rodada(timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_previa_rodada(timestamptz) to service_role;

comment on function public.parceiro_previa_preparar(uuid, uuid, uuid, uuid, uuid, text, timestamptz) is
  'Retorno F4 (P10.1, C-PEDIDO): o preparo do orçamento do item pedido, gerado de retorno_previa_preparar. A abertura vem do pedido, o item é do cartão do parceiro, o rascunho é _parceiro_rascunho_do_pedido, a regra 6 é pulada e a recusa marca o item do parceiro. p_destino parceiro: legenda P16 (validador do parceiro); cliente: a legenda da F3. Devolve o formato de retorno_previa_preparar, com parceiro_id, pedido_id e destino; args.origem = retorno_parceiro.';
revoke all on function public.parceiro_previa_preparar(uuid, uuid, uuid, uuid, uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_previa_preparar(uuid, uuid, uuid, uuid, uuid, text, timestamptz) to service_role;

comment on function public.parceiro_previa_soltar(uuid, timestamptz) is
  'Retorno F4 (P10.1): o orçamento do item pedido não terminou. Item feito vai a fora, o pedido decidido volta a cartao e a linha da fila de feito a espera (_parceiro_fila_por com p_reabrir). Nunca no sem_enviar do parceiro.';
revoke all on function public.parceiro_previa_soltar(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_previa_soltar(uuid, timestamptz) to service_role;

comment on function public.parceiro_previa_caiu(uuid, uuid, text, timestamptz) is
  'Retorno F4 (P10.1): o par de retorno_previa_caiu sobre parceiro_cartao_itens e parceiro_cartoes: o item cai com o motivo e a proposta cai.';
revoke all on function public.parceiro_previa_caiu(uuid, uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_previa_caiu(uuid, uuid, text, timestamptz) to service_role;

comment on function public.parceiro_previa_pdf(uuid, boolean, text, timestamptz, uuid, uuid, uuid) is
  'Retorno F4 (P10.1): o par de retorno_previa_pdf sobre parceiro_cartao_itens e parceiro_cartoes: grava pdf_em e a chave que recebeu; rascunho sem proposta ganha a linha origem rascunho; o item vivo vira feito.';
revoke all on function public.parceiro_previa_pdf(uuid, boolean, text, timestamptz, uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.parceiro_previa_pdf(uuid, boolean, text, timestamptz, uuid, uuid, uuid) to service_role;

-- Retorno F3 (P3): montar a proposta. Roda só pela bancada (grupo 5).
-- Termina em ROLLBACK, e cada bloco se desfaz sozinho. Fixtures em 2040, longe de qualquer orçamento real da janela de 18 meses.
-- Telefones de teste 55479009NNNNN; frases e nomes inventados.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- O caso, com uma mensagem. p_n numera o telefone, que precisa ser único entre os vivos.
create or replace function pg_temp.f3v_caso(p_n integer, p_papel text, p_cliente uuid, p_corpo text,
                                            p_aberta timestamptz default '2040-06-15 09:00-03', p_audio boolean default false,
                                            p_coleta jsonb default null) returns uuid
language plpgsql as $f$
declare
  v_fone text := '55479' || lpad(p_n::text, 8, '0');
  v_chave text := public._agenda_chave_telefone(v_fone);
  v_msg uuid;
  v_id uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
  values ('inbound', v_fone, 'text', p_corpo, 'received', '{"data": {}}'::jsonb, p_aberta, p_aberta)
  returning id into v_msg;
  insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, estado, modo, coleta)
  values (v_chave, v_fone, '47', p_papel, jsonb_build_object('papel', p_papel), p_cliente, v_msg, v_msg, p_aberta,
          p_aberta, p_aberta, p_aberta, 'recibo', 'recibo_cliente', 'aberta', 'sombra', p_coleta)
  returning id into v_id;
  insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, sinais, pede_resposta, audio_pendente)
  values (v_msg, v_id, v_chave, p_aberta, p_aberta, md5(p_corpo), public._retorno_sinais(p_corpo), true, p_audio);
  return v_id;
end $f$;

create or replace function pg_temp.f3v_cli(p_nome text) returns uuid
language sql as $f$
  insert into public.clients (type, name) values ('individual', p_nome) returning id;
$f$;

create or replace function pg_temp.f3v_un(p_cli uuid, p_nome text, p_tipo text default 'Lancha') returns uuid
language sql as $f$
  insert into public.vessels (client_id, name, asset_type) values (p_cli, p_nome, p_tipo) returning id;
$f$;

create or replace function pg_temp.f3v_prod(p_nome text, p_preco numeric default null, p_ativo boolean default true) returns uuid
language sql as $f$
  insert into public.products (name, stock_quantity, sale_price, active) values (p_nome, 0, p_preco, p_ativo) returning id;
$f$;

create or replace function pg_temp.f3v_serv(p_nome text, p_preco numeric default null, p_ativo boolean default true) returns uuid
language sql as $f$
  insert into public.services (name, billing_unit, default_price, active) values (p_nome, 'hour', p_preco, p_ativo) returning id;
$f$;

create or replace function pg_temp.f3v_os(p_num text, p_cli uuid, p_un uuid, p_status text, p_quote text, p_em timestamptz, p_desc text) returns uuid
language sql as $f$
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, problem_description, created_at, updated_at, grand_total)
  values (p_num, p_cli, p_un, p_status, p_quote, 'repair', p_desc, p_em, p_em, 100)
  returning id;
$f$;

create or replace function pg_temp.f3v_peca(p_os uuid, p_prod uuid, p_qtd numeric, p_preco numeric, p_em timestamptz) returns void
language sql as $f$
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot, line_total_cost, line_total_sale, created_at)
  values (p_os, p_prod, p_qtd, 1, p_preco, p_qtd, p_qtd * p_preco, p_em);
$f$;

create or replace function pg_temp.f3v_lin(p_os uuid, p_serv uuid, p_nome text, p_qtd numeric, p_preco numeric, p_em timestamptz) returns void
language sql as $f$
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (p_os, p_serv, p_nome, 'visit', p_qtd, p_preco, p_qtd * p_preco, p_em);
$f$;

-- Falha fecha: toda checagem junta o rótulo, o valor e o esperado.
create or replace function pg_temp.f3v_igual(p_rot text, p_valor text, p_esp text) returns void
language plpgsql as $f$
begin
  if p_valor is distinct from p_esp then
    raise exception '%: %, esperava %', p_rot, coalesce(p_valor, '∅'), coalesce(p_esp, '∅');
  end if;
end $f$;

do $previa$
declare
  c_agora constant timestamptz := '2040-06-15 10:00-03';
  c_passado constant timestamptz := '2040-02-01 10:00-03';
  v_cli uuid; v_cli2 uuid; v_un uuid; v_un2 uuid; v_un3 uuid;
  v_p1 uuid; v_p2 uuid; v_p3 uuid; v_s1 uuid; v_s2 uuid; v_s3 uuid; v_s_cat uuid;
  v_os uuid; v_os2 uuid; v_os3 uuid;
  v_caso uuid; v_caso2 uuid; v_caso3 uuid;
  v_id uuid; v_id2 uuid; v_id3 uuid;
  v_gen uuid;
  v_r jsonb; v_r2 jsonb; v_a jsonb;
  v_prev public.retorno_previa;
  v_prev2 public.retorno_previa;
  v_lin public.retorno_previa_linhas;
  v_n integer; v_t text; v_t2 text; v_d text;
  i integer;
begin
  begin
    update public.retorno_config set previa_modo = 'sombra', previa_ditado_ligado = true;

    -- ═══ 1, 2. Caso simples: 3 linhas, preços reprecificados, data mais antiga, hash, foto inicial.
    v_cli := pg_temp.f3v_cli('Lucas Previa Teste');
    v_un := pg_temp.f3v_un(v_cli, 'Brisa Simples');
    v_p1 := pg_temp.f3v_prod('TF3V Bateria 200');
    v_p2 := pg_temp.f3v_prod('TF3V Cabo 50mm');
    v_s1 := pg_temp.f3v_serv('TF3V Instalação do banco');
    v_os := pg_temp.f3v_os('TF3V-FONTE-1', v_cli, v_un, 'draft', 'approved', c_passado, 'troca de baterias');
    perform pg_temp.f3v_peca(v_os, v_p1, 2, 400, c_passado);
    perform pg_temp.f3v_peca(v_os, v_p2, 1, 150, c_passado + interval '1 minute');
    perform pg_temp.f3v_lin(v_os, v_s1, 'TF3V Instalação do banco', 1, 300, c_passado);
    -- Preço mais novo da mesma peça ao mesmo cliente, em OS sem família nenhuma (não concorre como parecido).
    v_os2 := pg_temp.f3v_os('TF3V-NOVO-1', v_cli, v_un, 'draft', 'approved', '2040-03-10 10:00-03', 'serviço geral');
    perform pg_temp.f3v_peca(v_os2, v_p1, 1, 450, '2040-03-10 10:00-03');

    v_caso := pg_temp.f3v_caso(1, 'cliente', v_cli, 'preciso trocar as baterias da lancha, quanto custa?');
    v_r := public.retorno_previa_montar(v_caso, c_agora);
    perform pg_temp.f3v_igual('1a acao', v_r ->> 'acao', 'criada');
    v_id := (v_r ->> 'previa_id')::uuid;
    select * into v_prev from public.retorno_previa where id = v_id;
    perform pg_temp.f3v_igual('1b estado', v_prev.estado, 'sombra');
    perform pg_temp.f3v_igual('1c modo', v_prev.modo, 'sombra');
    perform pg_temp.f3v_igual('1d origem', v_prev.origem, 'historico');
    perform pg_temp.f3v_igual('1e fonte', v_prev.fonte_numero, 'TF3V-FONTE-1');
    perform pg_temp.f3v_igual('1f vessel', v_prev.vessel_id::text, v_un::text);
    perform pg_temp.f3v_igual('1g titulo', v_prev.titulo, 'Baterias');
    if v_prev.linhas_n <> 3 or v_prev.provisorios_n <> 0 or v_prev.total <> 1350 then
      raise exception '1h: % linhas, % provisórios, total %', v_prev.linhas_n, v_prev.provisorios_n, v_prev.total;
    end if;
    perform pg_temp.f3v_igual('1i data mais antiga', v_prev.preco_mais_antigo::text, '2040-02-01');
    if v_prev.hash is null or v_prev.hash = '' then
      raise exception '1j: hash vazio';
    end if;
    if not coalesce((v_prev.dados ->> 'forte')::boolean, false) or not coalesce((v_prev.dados ->> 'fonte_aprovada')::boolean, false) then
      raise exception '1k: dados %', v_prev.dados;
    end if;
    -- A linha 1 (peça p1): preço mais novo a este cliente (450, não os 400 do parecido).
    select * into v_lin from public.retorno_previa_linhas where previa_id = v_id and ordem = 1;
    perform pg_temp.f3v_igual('2a preco p1', v_lin.preco::text, '450.00');
    perform pg_temp.f3v_igual('2b fonte p1', v_lin.preco_fonte, 'praticado_cliente');
    perform pg_temp.f3v_igual('2c data p1', v_lin.preco_em::text, '2040-03-10');
    perform pg_temp.f3v_igual('2d nome p1', v_lin.nome, 'TF3V Bateria 200');
    if v_lin.product_id is distinct from v_p1 or v_lin.quantidade <> 2 or v_lin.estado <> 'ok' then
      raise exception '2e: linha p1 %', row_to_json(v_lin);
    end if;
    select * into v_lin from public.retorno_previa_linhas where previa_id = v_id and ordem = 3;
    perform pg_temp.f3v_igual('2f nome serviço', v_lin.nome, 'TF3V Instalação do banco');
    if v_lin.service_id is distinct from v_s1 or v_lin.tipo <> 'servico' then
      raise exception '2g: linha serviço %', row_to_json(v_lin);
    end if;
    -- linhas_iniciais igual às linhas.
    select count(*) into v_n from jsonb_array_elements(v_prev.linhas_iniciais) x
     where x ->> 'nome' = 'TF3V Bateria 200' and (x ->> 'preco')::numeric = 450 and (x ->> 'quantidade')::numeric = 2
       and x ->> 'tipo' = 'peca' and x ->> 'product_id' = v_p1::text;
    if v_n <> 1 or jsonb_array_length(v_prev.linhas_iniciais) <> 3 then
      raise exception '2h: linhas_iniciais %', v_prev.linhas_iniciais;
    end if;

    -- ═══ 3. Zero não é preço: snapshot 0 e catálogo 0 → provisório.
    v_cli2 := pg_temp.f3v_cli('Zero Previa Teste');
    v_un2 := pg_temp.f3v_un(v_cli2, 'Zero Barco');
    v_p3 := pg_temp.f3v_prod('TF3V Bateria Zero', 0);
    v_os3 := pg_temp.f3v_os('TF3V-FONTE-ZERO', v_cli2, v_un2, 'draft', 'approved', c_passado, 'troca de baterias');
    perform pg_temp.f3v_peca(v_os3, v_p3, 1, 0, c_passado);
    v_caso2 := pg_temp.f3v_caso(2, 'cliente', v_cli2, 'preciso trocar as baterias do barco, quanto custa?');
    v_r := public.retorno_previa_montar(v_caso2, c_agora);
    perform pg_temp.f3v_igual('3a acao', v_r ->> 'acao', 'criada');
    v_id2 := (v_r ->> 'previa_id')::uuid;
    select * into v_prev from public.retorno_previa where id = v_id2;
    if v_prev.provisorios_n <> 1 or v_prev.total <> 0 then
      raise exception '3b: % provisórios, total %', v_prev.provisorios_n, v_prev.total;
    end if;
    select * into v_lin from public.retorno_previa_linhas where previa_id = v_id2;
    if v_lin.preco is not null or v_lin.estado <> 'provisorio' or v_lin.motivo <> 'sem_preco' or v_lin.preco_fonte <> 'sem_preco' then
      raise exception '3c: linha %', row_to_json(v_lin);
    end if;

    -- ═══ 4, 18a. Nome sujo: Serviço a descrever, sem preço, nada do nome original.
    v_cli := pg_temp.f3v_cli('Paulo Sujo Teste');
    v_un := pg_temp.f3v_un(v_cli, 'Brisa Suja');
    v_cli2 := pg_temp.f3v_cli('Outro Sujo Teste');
    v_un2 := pg_temp.f3v_un(v_cli2, 'Vento Limpo');
    v_os := pg_temp.f3v_os('TF3V-FONTE-SUJA', v_cli, v_un, 'draft', 'approved', '2040-05-20 10:00-03', 'troca de baterias');
    perform pg_temp.f3v_lin(v_os, null, 'Troca de baterias da Brisa do Paulo', 1, 800, '2040-05-20 10:00-03');
    v_caso := pg_temp.f3v_caso(3, 'cliente', v_cli2, 'preciso trocar as baterias do barco, quanto custa?');
    v_r := public.retorno_previa_montar(v_caso, c_agora);
    perform pg_temp.f3v_igual('4a acao', v_r ->> 'acao', 'criada');
    v_id := (v_r ->> 'previa_id')::uuid;
    select * into v_lin from public.retorno_previa_linhas where previa_id = v_id;
    perform pg_temp.f3v_igual('4b nome', v_lin.nome, 'Serviço a descrever');
    perform pg_temp.f3v_igual('18a motivo', v_lin.motivo, 'nome_com_dado_de_outro');
    if v_lin.preco is not null or v_lin.preco_fonte <> 'sem_preco' or v_lin.estado <> 'provisorio' then
      raise exception '18b: linha %', row_to_json(v_lin);
    end if;
    select * into v_prev from public.retorno_previa where id = v_id;
    v_t := v_prev.linhas_iniciais::text || v_prev.dados::text || v_prev.titulo || v_lin.nome;
    if v_t ~* 'paulo|brisa' then
      raise exception '4c: nome original vazou: %', v_t;
    end if;
    -- Com o nome do cliente da fonte só no display_name, também barra.
    v_cli2 := pg_temp.f3v_cli('Roberta Fantasia Teste');
    update public.clients set display_name = 'Marcelo Apelido' where id = v_cli2;
    v_un2 := pg_temp.f3v_un(v_cli2, 'Sereia Teste');
    v_t := public._retorno_nome_limpo('Revisão geral do Marcelo', v_cli2, v_un2);
    if v_t is not null then
      raise exception '4d: display_name não barrou: %', v_t;
    end if;
    -- Telefone, CPF e placa barram; serviço comum passa; "lancha" no nome da unidade não barra o nome da peça.
    if public._retorno_nome_limpo('Atendimento 47 99999-1234', null, null) is not null
       or public._retorno_nome_limpo('Serviço CPF 123.456.789-09', null, null) is not null
       or public._retorno_nome_limpo('Instalação ABC-1D23', null, null) is not null then
      raise exception '4e: dado pessoal passou';
    end if;
    perform pg_temp.f3v_igual('4f nome comum', public._retorno_nome_limpo('Instalação de banco de baterias', v_cli2, v_un2), 'Instalação de banco de baterias');

    -- ═══ Revisão da F3. Nome de catálogo com dado da fonte (serviço pendente criado de mão de obra ditada) também vira "Serviço a descrever".
    v_cli := pg_temp.f3v_cli('Paulo Catalogo Teste');
    v_un := pg_temp.f3v_un(v_cli, 'Brisa Catalogo');
    v_s_cat := pg_temp.f3v_serv('Instalação na Brisa Catalogo do Paulo', 300);
    v_os := pg_temp.f3v_os('TF3V-FONTE-CAT', v_cli, v_un, 'draft', 'approved', '2040-05-21 10:00-03', 'troca de baterias');
    perform pg_temp.f3v_lin(v_os, v_s_cat, 'Instalação na Brisa Catalogo do Paulo', 1, 300, '2040-05-21 10:00-03');
    v_cli2 := pg_temp.f3v_cli('Outro Catalogo Teste');
    perform pg_temp.f3v_un(v_cli2, 'Vento Catalogo');
    v_caso := pg_temp.f3v_caso(4, 'cliente', v_cli2, 'preciso trocar as baterias do barco, quanto custa?');
    v_r := public.retorno_previa_montar(v_caso, c_agora);
    perform pg_temp.f3v_igual('4r1 acao', v_r ->> 'acao', 'criada');
    select * into v_lin from public.retorno_previa_linhas where previa_id = (v_r ->> 'previa_id')::uuid;
    perform pg_temp.f3v_igual('4r2 nome', v_lin.nome, 'Serviço a descrever');
    perform pg_temp.f3v_igual('4r3 motivo', v_lin.motivo, 'nome_com_dado_de_outro');
    if v_lin.preco is not null or v_lin.estado <> 'provisorio' then
      raise exception '4r4: linha %', row_to_json(v_lin);
    end if;

    -- ═══ 5. Motivos de nada: Cliente Final, papel, sem família, sem parecido, áudio, intenção, bem desconhecido.
    update public.retorno_config set previa_modo = 'ligado';
    select id into v_gen from public.clients where generico limit 1;
    if v_gen is null then
      raise exception '5: o Cliente Final não existe no banco de teste';
    end if;
    v_caso := pg_temp.f3v_caso(10, 'cliente', v_gen, 'preciso trocar as baterias da lancha, quanto custa?');
    perform pg_temp.f3v_igual('5a cliente final', public.retorno_previa_montar(v_caso, c_agora) ->> 'motivo', 'cliente_final');
    v_caso := pg_temp.f3v_caso(11, 'fornecedor', v_cli, 'preciso trocar as baterias da lancha, quanto custa?');
    perform pg_temp.f3v_igual('5b papel', public.retorno_previa_montar(v_caso, c_agora) ->> 'motivo', 'papel');
    v_cli2 := pg_temp.f3v_cli('Sem Familia Teste');
    v_un2 := pg_temp.f3v_un(v_cli2, 'Sem Familia Barco');
    v_caso := pg_temp.f3v_caso(12, 'cliente', v_cli2, 'quanto custa um pneu da carreta?');
    perform pg_temp.f3v_igual('5c sem família', public.retorno_previa_montar(v_caso, c_agora) ->> 'motivo', 'sem_familia');
    -- Sem parecido: janela de 2030, antes de qualquer fixture e bem depois do histórico real em 18 meses.
    v_caso := pg_temp.f3v_caso(13, 'cliente', v_cli2, 'preciso trocar as baterias do barco, quanto custa?', '2030-01-10 09:00-03');
    perform pg_temp.f3v_igual('5d sem parecido', public.retorno_previa_montar(v_caso, '2030-01-10 10:00-03') ->> 'motivo', 'sem_parecido');
    v_caso := pg_temp.f3v_caso(14, 'cliente', v_cli2, 'preciso trocar as baterias do barco, quanto custa?', p_audio => true);
    perform pg_temp.f3v_igual('5e áudio', public.retorno_previa_montar(v_caso, c_agora) ->> 'motivo', 'aguarda_transcricao');
    v_caso := pg_temp.f3v_caso(15, 'cliente', v_cli2, 'como está o serviço?');
    perform pg_temp.f3v_igual('5f intenção', public.retorno_previa_montar(v_caso, c_agora) ->> 'motivo', 'intencao');
    v_cli := pg_temp.f3v_cli('Sem Classe Teste');
    v_un := pg_temp.f3v_un(v_cli, 'Unidade xyz', 'xyz');
    v_caso := pg_temp.f3v_caso(16, 'cliente', v_cli, 'preciso trocar as baterias, quanto custa?');
    perform pg_temp.f3v_igual('5g sem classe', public.retorno_previa_montar(v_caso, c_agora) ->> 'motivo', 'sem_classe');

    -- ═══ 6. Número novo: lê o audit_log; cadastro desativado devolve nulo.
    v_cli := pg_temp.f3v_cli('Numero Novo Teste');
    update public.clients set provisorio = true, origem = 'retorno' where id = v_cli;
    v_un := pg_temp.f3v_un(v_cli, 'Novo Barco');
    v_caso := pg_temp.f3v_caso(20, 'numero_novo', null, 'preciso trocar as baterias do barco, quanto custa?');
    insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
    values ('clients', v_cli, 'lead_converted', 'retorno', null,
            jsonb_build_object('provisorio', true, 'origem', 'retorno', 'caso', v_caso, 'vessel_id', v_un), 'teste');
    v_r := public._retorno_cadastro_do_caso(v_caso);
    perform pg_temp.f3v_igual('6a client', v_r ->> 'client_id', v_cli::text);
    perform pg_temp.f3v_igual('6b vessel', v_r ->> 'vessel_id', v_un::text);
    if not (v_r ->> 'provisorio')::boolean then
      raise exception '6c: provisório %', v_r;
    end if;
    update public.clients set active = false where id = v_cli;
    if public._retorno_cadastro_do_caso(v_caso) is not null then
      raise exception '6d: cadastro desativado devolveu %', public._retorno_cadastro_do_caso(v_caso);
    end if;
    update public.clients set active = true where id = v_cli;
    update public.vessels set active = false where id = v_un;
    v_r := public._retorno_cadastro_do_caso(v_caso);
    if v_r ->> 'vessel_id' is not null then
      raise exception '6e: unidade inativa ficou %', v_r;
    end if;
    update public.vessels set active = true where id = v_un;
    -- Papel 'cliente' com client_id: o audit_log nem é olhado.
    v_cli2 := pg_temp.f3v_cli('Cliente Direto Teste');
    v_caso2 := pg_temp.f3v_caso(21, 'cliente', v_cli2, 'bom dia');
    perform pg_temp.f3v_igual('6f direto', public._retorno_cadastro_do_caso(v_caso2) ->> 'client_id', v_cli2::text);

    -- ═══ 7. Duas unidades e nenhum nome casando: dados.unidades; nome parcial não casa.
    v_cli := pg_temp.f3v_cli('Duas Unidades Teste');
    v_un := pg_temp.f3v_un(v_cli, 'Brisa Mar');
    v_un2 := pg_temp.f3v_un(v_cli, 'Maresia Sul');
    v_os := pg_temp.f3v_os('TF3V-FONTE-2UN', v_cli, v_un, 'draft', 'approved', c_passado, 'troca de baterias');
    perform pg_temp.f3v_lin(v_os, null, 'Serviço de bateria para teste', 1, 800, c_passado);
    v_caso := pg_temp.f3v_caso(30, 'cliente', v_cli, 'preciso trocar as baterias da Bri, quanto custa?');
    v_r := public._retorno_unidade_do_caso(v_caso, v_cli, c_agora);
    if v_r ->> 'vessel_id' is not null or jsonb_array_length(v_r -> 'unidades') <> 2 then
      raise exception '7a: unidade %', v_r;
    end if;
    v_r := public.retorno_previa_montar(v_caso, c_agora);
    perform pg_temp.f3v_igual('7b acao', v_r ->> 'acao', 'criada');
    select * into v_prev from public.retorno_previa where id = (v_r ->> 'previa_id')::uuid;
    if v_prev.vessel_id is not null or jsonb_array_length(v_prev.dados -> 'unidades') <> 2 then
      raise exception '7c: proposta %', row_to_json(v_prev);
    end if;
    -- Unidades com classes diferentes: mistas.
    v_cli2 := pg_temp.f3v_cli('Mistas Teste');
    perform pg_temp.f3v_un(v_cli2, 'Primeira Mista', 'Lancha');
    perform pg_temp.f3v_un(v_cli2, 'Segunda Mista', 'Motorhome');
    v_caso := pg_temp.f3v_caso(31, 'cliente', v_cli2, 'preciso trocar as baterias, quanto custa?');
    perform pg_temp.f3v_igual('7d mistas', public.retorno_previa_montar(v_caso, c_agora) ->> 'motivo', 'unidades_mistas');

    -- ═══ 8. Modo: sombra grava estado sombra; desligado não grava, nem com p_fonte; p_fonte só vale em ligado.
    update public.retorno_config set previa_modo = 'desligado', previa_ditado_ligado = false;
    v_caso := pg_temp.f3v_caso(40, 'cliente', v_cli, 'preciso trocar as baterias da Brisa, quanto custa?');
    perform pg_temp.f3v_igual('8a desligado', public.retorno_previa_montar(v_caso, c_agora) ->> 'motivo', 'desligado');
    perform pg_temp.f3v_igual('8b desligado com fonte', public.retorno_previa_montar(v_caso, c_agora, v_os) ->> 'motivo', 'desligado');
    if exists (select 1 from public.retorno_previa p where p.abertura_id = v_caso) then
      raise exception '8c: desligado gravou proposta';
    end if;
    update public.retorno_config set previa_modo = 'sombra', previa_ditado_ligado = true;
    perform pg_temp.f3v_igual('8d sombra com fonte', public.retorno_previa_montar(v_caso, c_agora, v_os) ->> 'motivo', 'desligado');
    v_r := public.retorno_previa_montar(v_caso, c_agora);
    perform pg_temp.f3v_igual('8e sombra acao', v_r ->> 'acao', 'criada');
    select * into v_prev from public.retorno_previa where id = (v_r ->> 'previa_id')::uuid;
    perform pg_temp.f3v_igual('8f estado sombra', v_prev.estado, 'sombra');
    update public.retorno_config set previa_modo = 'ligado';
    v_r := public.retorno_previa_montar(v_caso, c_agora);
    perform pg_temp.f3v_igual('8g ligado cria proposta', v_r ->> 'acao', 'criada');
    select * into v_prev from public.retorno_previa where id = (v_r ->> 'previa_id')::uuid;
    perform pg_temp.f3v_igual('8h estado proposta', v_prev.estado, 'proposta');
    perform pg_temp.f3v_igual('8i modo ligado', v_prev.modo, 'ligado');

    raise exception 'retorno_f3_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f3_desfaz' then
      raise;
    end if;
  end;

  -- Rodada e proposta travada num bloco próprio: cada bloco refaz o mínimo que precisa.
  begin
    update public.retorno_config set previa_modo = 'sombra', previa_ditado_ligado = true;
    v_cli := pg_temp.f3v_cli('Rodada Teste');
    v_un := pg_temp.f3v_un(v_cli, 'Rodada Barco');
    v_os := pg_temp.f3v_os('TF3V-FONTE-RODA', v_cli, v_un, 'draft', 'approved', c_passado, 'troca de baterias');
    perform pg_temp.f3v_lin(v_os, null, 'Serviço rodada', 1, 500, c_passado);
    v_caso := pg_temp.f3v_caso(50, 'cliente', v_cli, 'preciso trocar as baterias do barco, quanto custa?');

    -- ═══ 10. Rodada: cria; a 2ª passada sem mensagem nova não recria; mensagem nova com as mesmas linhas mantém o id; linhas diferentes criam outra.
    v_r := public.retorno_previa_rodada(c_agora);
    if (v_r ->> 'criadas')::int < 1 or (v_r ->> 'erros')::int <> 0 then
      raise exception '10a: %', v_r;
    end if;
    select id into v_id from public.retorno_previa where abertura_id = v_caso and estado = 'sombra';
    if v_id is null then
      raise exception '10b: rodada não criou';
    end if;
    v_r := public.retorno_previa_rodada(c_agora);
    select count(*) into v_n from public.retorno_previa where abertura_id = v_caso;
    if v_n <> 1 then
      raise exception '10c: 2ª passada recriou (% linhas)', v_n;
    end if;
    update public.retorno_aberturas set ultima_em = c_agora + interval '1 hour' where id = v_caso;
    v_r := public.retorno_previa_rodada(c_agora + interval '1 hour');
    select count(*) into v_n from public.retorno_previa where abertura_id = v_caso;
    if v_n <> 1 or not exists (select 1 from public.retorno_previa where id = v_id and estado = 'sombra') then
      raise exception '10d: mensagem nova com as mesmas linhas recriou (% linhas)', v_n;
    end if;
    perform pg_temp.f3v_lin(v_os, null, 'Serviço extra de bateria', 1, 200, c_passado);
    update public.retorno_aberturas set ultima_em = c_agora + interval '2 hours' where id = v_caso;
    v_r := public.retorno_previa_rodada(c_agora + interval '2 hours');
    select count(*) into v_n from public.retorno_previa where abertura_id = v_caso and estado = 'sombra';
    if v_n <> 1 or exists (select 1 from public.retorno_previa where id = v_id and estado = 'sombra') then
      raise exception '10e: linhas diferentes não criaram outra';
    end if;
    if not exists (select 1 from public.retorno_previa where id = v_id and estado = 'descartada') then
      raise exception '10f: a anterior não foi descartada';
    end if;

    -- ═══ 11. Rodada não toca em proposta travada, e em ligado não apaga a sombra viva.
    update public.retorno_config set previa_modo = 'ligado';
    v_caso2 := pg_temp.f3v_caso(51, 'cliente', v_cli, 'preciso trocar as baterias do barco, quanto custa?');
    insert into public.retorno_previa (abertura_id, chave, client_id, vessel_id, origem, titulo, estado, modo, total, linhas_n, hash, dados)
    select v_caso2, a.chave, v_cli, v_un, 'ditado', 'Ditado', 'proposta', 'ligado', 100, 1, 'hash-travado', '{"travada": true}'::jsonb
      from public.retorno_aberturas a where a.id = v_caso2
    returning id into v_id2;
    insert into public.retorno_previa_linhas (previa_id, ordem, tipo, nome, quantidade, preco, preco_fonte, estado)
    values (v_id2, 1, 'servico', 'Serviço ditado', 1, 100, 'dito', 'ok');
    insert into public.retorno_previa (abertura_id, chave, client_id, origem, titulo, estado, modo, hash)
    select v_caso2, a.chave, v_cli, 'historico', 'Sombra', 'sombra', 'sombra', 'hash-sombra'
      from public.retorno_aberturas a where a.id = v_caso2
    returning id into v_id3;
    v_r := public.retorno_previa_rodada(c_agora);
    select * into v_prev from public.retorno_previa where id = v_id2;
    if v_prev.estado <> 'proposta' or v_prev.hash <> 'hash-travado' or v_prev.titulo <> 'Ditado' then
      raise exception '11a: rodada mexeu na travada: %', row_to_json(v_prev);
    end if;
    select count(*) into v_n from public.retorno_previa_linhas where previa_id = v_id2 and nome = 'Serviço ditado';
    if v_n <> 1 then
      raise exception '11b: linhas da travada mudaram';
    end if;
    if not exists (select 1 from public.retorno_previa where id = v_id3 and estado = 'sombra') then
      raise exception '11c: rodada em ligado apagou a sombra viva';
    end if;

    -- Fecha as vivas de caso fechado (descartada).
    update public.retorno_aberturas set estado = 'fechada', fechada_em = c_agora, fechada_motivo = 'nada' where id = v_caso2;
    v_r := public.retorno_previa_rodada(c_agora);
    if exists (select 1 from public.retorno_previa where abertura_id = v_caso2 and estado in ('sombra', 'proposta')) then
      raise exception '11d: viva de caso fechado continuou viva';
    end if;

    raise exception 'retorno_f3_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f3_desfaz' then
      raise;
    end if;
  end;

  -- ═══ 9. A rodada com exceção forçada num caso segue para o outro. O override de função fica só neste bloco.
  begin
    update public.retorno_config set previa_modo = 'sombra', previa_ditado_ligado = true;
    v_cli := pg_temp.f3v_cli('Erro Forcado Teste');
    v_un := pg_temp.f3v_un(v_cli, 'Erro Forcado Barco');
    v_cli2 := pg_temp.f3v_cli('Sadio Rodada Teste');
    v_un2 := pg_temp.f3v_un(v_cli2, 'Sadio Barco');
    v_os := pg_temp.f3v_os('TF3V-FONTE-ERR', v_cli2, v_un2, 'draft', 'approved', c_passado, 'troca de baterias');
    perform pg_temp.f3v_lin(v_os, null, 'Serviço sadio', 1, 500, c_passado);
    v_caso := pg_temp.f3v_caso(60, 'cliente', v_cli, 'preciso trocar as baterias do barco, quanto custa?');
    v_caso2 := pg_temp.f3v_caso(61, 'cliente', v_cli2, 'preciso trocar as baterias do barco, quanto custa?');
    execute format($d$create or replace function public._retorno_intencao_do_caso(p_abertura uuid, p_agora timestamptz)
      returns text language plpgsql stable security definer set search_path = public as $b$
      begin
        if p_abertura = %L then raise exception 'teste forcado'; end if;
        return 'orcamento';
      end $b$;$d$, v_caso);
    v_r := public.retorno_previa_rodada(c_agora);
    if (v_r ->> 'erros')::int < 1 or (v_r ->> 'casos')::int < 2 then
      raise exception '9a: %', v_r;
    end if;
    if not exists (select 1 from public.retorno_previa where abertura_id = v_caso2 and estado = 'sombra') then
      raise exception '9b: o caso sadio não foi montado depois do erro';
    end if;
    if exists (select 1 from public.retorno_previa where abertura_id = v_caso) then
      raise exception '9c: o caso com erro gravou proposta';
    end if;
    raise exception 'retorno_f3_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f3_desfaz' then
      raise;
    end if;
  end;

  -- ═══ 12, 13, 14, 15, 16, 17, 18b, 19, 20, 23: preço, rascunho, unidade por palavra inteira, sem unidade, visita, parecido, ordem.
  begin
    update public.retorno_config set previa_modo = 'ligado', previa_ditado_ligado = true;

    -- ═══ 12. Preço de peça: aprovado a outro antes de orçado a este; cancelado e do futuro não contam; catálogo com data nula.
    v_cli := pg_temp.f3v_cli('Preco Peca Teste');
    v_un := pg_temp.f3v_un(v_cli, 'Preco Barco');
    v_cli2 := pg_temp.f3v_cli('Outro Preco Teste');
    v_un2 := pg_temp.f3v_un(v_cli2, 'Outro Preco Barco');
    v_p1 := pg_temp.f3v_prod('TF3V Peca Preco', 99);
    -- aprovado a outro, antigo
    v_os := pg_temp.f3v_os('TF3V-P-OUTRO', v_cli2, v_un2, 'draft', 'approved', '2040-01-01 10:00-03', 'peça');
    perform pg_temp.f3v_peca(v_os, v_p1, 1, 300, '2040-01-01 10:00-03');
    -- não aprovado a este, mais novo
    v_os := pg_temp.f3v_os('TF3V-P-ESTE', v_cli, v_un, 'draft', 'draft', '2040-02-01 10:00-03', 'peça');
    perform pg_temp.f3v_peca(v_os, v_p1, 1, 350, '2040-02-01 10:00-03');
    -- cancelado, mais novo que todos
    v_os := pg_temp.f3v_os('TF3V-P-CANC', v_cli, v_un, 'cancelled', 'approved', '2040-03-01 10:00-03', 'peça');
    perform pg_temp.f3v_peca(v_os, v_p1, 1, 999, '2040-03-01 10:00-03');
    -- do futuro em relação a p_agora
    v_os := pg_temp.f3v_os('TF3V-P-FUT', v_cli, v_un, 'draft', 'approved', '2040-07-01 10:00-03', 'peça');
    perform pg_temp.f3v_peca(v_os, v_p1, 1, 888, '2040-07-01 10:00-03');
    v_r := public._retorno_preco_da_peca(v_p1, v_cli, c_agora);
    if (v_r ->> 'preco')::numeric <> 300 then
      raise exception '12a: %', v_r;
    end if;
    perform pg_temp.f3v_igual('12b fonte', v_r ->> 'fonte', 'praticado_outro');
    perform pg_temp.f3v_igual('12c data', v_r ->> 'em', '2040-01-01');
    -- sem histórico: catálogo sem data
    v_p2 := pg_temp.f3v_prod('TF3V Peca So Catalogo', 77.5);
    v_r := public._retorno_preco_da_peca(v_p2, v_cli, c_agora);
    if (v_r ->> 'preco')::numeric <> 77.5 or v_r ->> 'fonte' <> 'catalogo' or v_r ->> 'em' is not null then
      raise exception '12d: %', v_r;
    end if;
    -- O serviço: aprovado a este; depois o catálogo; sem nada, sem_preco.
    v_s1 := pg_temp.f3v_serv('TF3V Servico Preco', 111);
    v_r := public._retorno_preco_do_servico(v_s1, 'TF3V Servico Preco', v_cli, c_agora);
    if v_r ->> 'fonte' <> 'catalogo' or (v_r ->> 'preco')::numeric <> 111 then
      raise exception '12e: %', v_r;
    end if;
    v_r := public._retorno_preco_do_servico(null, 'Serviço sem nome conhecido em lugar nenhum', v_cli, c_agora);
    if v_r ->> 'preco' is not null or v_r ->> 'fonte' <> 'sem_preco' then
      raise exception '12f: %', v_r;
    end if;
    -- Liga por nome normalizado quando não há service_id.
    v_os := pg_temp.f3v_os('TF3V-P-NOME', v_cli, v_un, 'draft', 'approved', '2040-02-02 10:00-03', 'serviço');
    perform pg_temp.f3v_lin(v_os, null, 'Serviço Por Nome Único', 2, 150, '2040-02-02 10:00-03');
    v_r := public._retorno_preco_do_servico(null, 'serviço por nome único', v_cli, c_agora);
    if v_r ->> 'fonte' <> 'praticado_cliente' or (v_r ->> 'preco')::numeric <> 150 then
      raise exception '12g: %', v_r;
    end if;

    -- ═══ 13a. Nome de 346 caracteres vira 200, sem exceção.
    v_cli := pg_temp.f3v_cli('Nome Longo Teste');
    v_un := pg_temp.f3v_un(v_cli, 'Longo Barco');
    v_os := pg_temp.f3v_os('TF3V-FONTE-LONGA', v_cli, v_un, 'draft', 'approved', c_passado, 'baterias');
    perform pg_temp.f3v_lin(v_os, null, repeat('Serviço de bateria ', 18) || 'fim', 1, 800, c_passado);
    v_caso := pg_temp.f3v_caso(70, 'cliente', v_cli, 'preciso trocar as baterias do barco, quanto custa?');
    v_r := public.retorno_previa_montar(v_caso, c_agora);
    select * into v_lin from public.retorno_previa_linhas where previa_id = (v_r ->> 'previa_id')::uuid;
    if char_length(v_lin.nome) <> 200 then
      raise exception '13a: nome com % caracteres', char_length(v_lin.nome);
    end if;

    -- ═══ 13b, 14. Unidade por palavra inteira e os rascunhos.
    v_cli := pg_temp.f3v_cli('Unidades Teste');
    v_un := pg_temp.f3v_un(v_cli, 'Brisa');
    v_un2 := pg_temp.f3v_un(v_cli, 'Maresia');
    v_un3 := pg_temp.f3v_un(v_cli, 'S.I. 8.5 2016', 'Lancha');
    perform pg_temp.f3v_un(v_cli, 'Lancha');   -- nome igual ao tipo não identifica
    v_caso := pg_temp.f3v_caso(71, 'cliente', v_cli, 'a Brisamar precisa de bateria, quanto custa?');
    v_r := public._retorno_unidade_do_caso(v_caso, v_cli, c_agora);
    if v_r ->> 'vessel_id' is not null or jsonb_array_length(v_r -> 'unidades') <> 4 then
      raise exception '14a: Brisa casou em Brisamar: %', v_r;
    end if;
    v_caso2 := pg_temp.f3v_caso(72, 'cliente', v_cli, 'o s.i. 8.5 2016 precisa de bateria, quanto custa?');
    v_r := public._retorno_unidade_do_caso(v_caso2, v_cli, c_agora);
    perform pg_temp.f3v_igual('14b S.I.', v_r ->> 'vessel_id', v_un3::text);
    perform pg_temp.f3v_igual('14c origem', v_r ->> 'origem', 'mensagem');
    v_caso3 := pg_temp.f3v_caso(73, 'cliente', v_cli, 'preciso ver a lancha, quanto custa a bateria?');
    v_r := public._retorno_unidade_do_caso(v_caso3, v_cli, c_agora);
    if v_r ->> 'vessel_id' is not null then
      raise exception '14d: nome igual ao tipo casou: %', v_r;
    end if;
    -- unidade_escolhida_id vence a busca; com a unidade inativa é ignorada.
    update public.retorno_aberturas set unidade_escolhida_id = v_un where id = v_caso2;
    v_r := public._retorno_unidade_do_caso(v_caso2, v_cli, c_agora);
    perform pg_temp.f3v_igual('14e dono', v_r ->> 'vessel_id', v_un::text);
    perform pg_temp.f3v_igual('14f origem', v_r ->> 'origem', 'dono');
    update public.vessels set active = false where id = v_un;
    v_r := public._retorno_unidade_do_caso(v_caso2, v_cli, c_agora);
    perform pg_temp.f3v_igual('14g inativa ignorada', v_r ->> 'vessel_id', v_un3::text);
    update public.vessels set active = true where id = v_un;
    -- Rascunho: outra unidade não casa; origem_chave8 vem antes do mais novo; número novo casa pelo audit_log.
    update public.retorno_aberturas set unidade_escolhida_id = v_un2 where id = v_caso;
    v_os := pg_temp.f3v_os('TF3V-RASC-OUTRA', v_cli, v_un, 'draft', 'draft', c_agora - interval '2 days', 'x');
    if public._retorno_rascunho_do_caso(v_caso, c_agora) is not null then
      raise exception '13b: rascunho de outra unidade casou';
    end if;
    v_os := pg_temp.f3v_os('TF3V-RASC-NOVO', v_cli, v_un2, 'draft', 'draft', c_agora - interval '1 day', 'x');
    v_os2 := pg_temp.f3v_os('TF3V-RASC-CHAVE', v_cli, v_un2, 'draft', 'draft', c_agora - interval '3 days', 'x');
    update public.service_orders set origem_chave8 = (select chave from public.retorno_aberturas where id = v_caso) where id = v_os2;
    v_r := public._retorno_rascunho_do_caso(v_caso, c_agora);
    perform pg_temp.f3v_igual('13c origem_chave8 primeiro', v_r ->> 'numero', 'TF3V-RASC-CHAVE');
    perform pg_temp.f3v_igual('13d unidade', v_r ->> 'unidade', 'Maresia');
    update public.service_orders set grand_total = 0 where id = v_os2;
    perform pg_temp.f3v_lin(v_os2, null, 'Sem preço', 1, 0, c_passado);
    v_r := public._retorno_rascunho_do_caso(v_caso, c_agora);
    if (v_r ->> 'linhas_sem_preco')::int <> 1 or (v_r ->> 'linhas_n')::int <> 1 or (v_r ->> 'total')::numeric <> 0 then
      raise exception '13e: %', v_r;
    end if;
    v_cli2 := pg_temp.f3v_cli('Novo Rascunho Teste');
    v_un2 := pg_temp.f3v_un(v_cli2, 'Novo Rascunho Barco');
    v_caso2 := pg_temp.f3v_caso(74, 'numero_novo', null, 'preciso de orçamento de bateria');
    insert into public.audit_log (table_name, record_id, action, changed_by, new_value, reason)
    values ('clients', v_cli2, 'lead_converted', 'retorno', jsonb_build_object('caso', v_caso2, 'vessel_id', v_un2), 'teste');
    perform pg_temp.f3v_os('TF3V-RASC-NN', v_cli2, v_un2, 'draft', 'draft', c_agora - interval '1 hour', 'x');
    perform pg_temp.f3v_igual('13f número novo', public._retorno_rascunho_do_caso(v_caso2, c_agora) ->> 'numero', 'TF3V-RASC-NN');
    -- Com rascunho, montar devolve ja_tem_orcamento.
    perform pg_temp.f3v_igual('13g ja tem', public.retorno_previa_montar(v_caso2, c_agora) ->> 'motivo', 'ja_tem_orcamento');
    -- Rascunho fora dos 14 dias não conta.
    update public.service_orders set created_at = c_agora - interval '20 days' where service_order_number = 'TF3V-RASC-NN';
    if public._retorno_rascunho_do_caso(v_caso2, c_agora) is not null then
      raise exception '13h: rascunho de 20 dias casou';
    end if;

    -- ═══ 15. Cliente com 0 unidades: classe pela palavra do bem, vessel nulo, dados.unidades vazio; sem a palavra, sem_classe.
    v_cli := pg_temp.f3v_cli('Sem Unidade Teste');
    v_un2 := pg_temp.f3v_un(pg_temp.f3v_cli('Fonte Classe Teste'), 'Fonte Classe Barco');
    v_os := pg_temp.f3v_os('TF3V-FONTE-15', (select client_id from public.vessels where id = v_un2), v_un2, 'draft', 'approved', c_passado, 'troca de baterias');
    perform pg_temp.f3v_lin(v_os, null, 'Serviço de bateria fonte', 1, 700, c_passado);
    v_caso := pg_temp.f3v_caso(80, 'cliente', v_cli, 'a lancha precisa de bateria nova, quanto custa?');
    v_r := public.retorno_previa_montar(v_caso, c_agora);
    perform pg_temp.f3v_igual('15a acao', v_r ->> 'acao', 'criada');
    v_id := (v_r ->> 'previa_id')::uuid;
    select * into v_prev from public.retorno_previa where id = v_id;
    if v_prev.vessel_id is not null or v_prev.dados -> 'unidades' is distinct from '[]'::jsonb then
      raise exception '15b: %', row_to_json(v_prev);
    end if;
    v_caso2 := pg_temp.f3v_caso(81, 'cliente', v_cli, 'preciso de bateria nova, quanto custa?');
    perform pg_temp.f3v_igual('15c sem classe', public.retorno_previa_montar(v_caso2, c_agora) ->> 'motivo', 'sem_classe');

    -- ═══ 16. Proposta com vessel nulo e unidade criada depois: mantém id e linhas, grava vessel, muda hash, vale com travada.
    update public.retorno_previa set dados = dados || '{"travada": true}'::jsonb where id = v_id;
    select hash into v_t from public.retorno_previa where id = v_id;
    v_un := pg_temp.f3v_un(v_cli, 'Unidade Depois');
    v_t2 := public._retorno_previa_hash_efetivo(v_id, c_agora);
    v_r := public.retorno_previa_montar(v_caso, c_agora);
    perform pg_temp.f3v_igual('16a acao', v_r ->> 'acao', 'mantida');
    perform pg_temp.f3v_igual('16b id', v_r ->> 'previa_id', v_id::text);
    select * into v_prev from public.retorno_previa where id = v_id;
    perform pg_temp.f3v_igual('16c vessel', v_prev.vessel_id::text, v_un::text);
    if v_prev.hash = v_t then
      raise exception '16d: hash não mudou';
    end if;
    if not coalesce((v_prev.dados ->> 'travada')::boolean, false) then
      raise exception '16e: travada perdida';
    end if;
    select count(*) into v_n from public.retorno_previa_linhas where previa_id = v_id;
    if v_n <> 1 then
      raise exception '16f: linhas mudaram';
    end if;
    perform pg_temp.f3v_igual('16g hash efetivo igual', public._retorno_previa_hash_efetivo(v_id, c_agora), v_t2);
    perform pg_temp.f3v_igual('16h efetivo = hash', v_prev.hash, v_t2);
    -- client_id nulo e cadastro que apareceu: grava o cliente, sem mudar o hash.
    v_caso3 := pg_temp.f3v_caso(82, 'numero_novo', null, 'a lancha precisa de bateria nova, quanto custa?');
    v_r := public.retorno_previa_montar(v_caso3, c_agora);
    perform pg_temp.f3v_igual('16i acao', v_r ->> 'acao', 'criada');
    v_id3 := (v_r ->> 'previa_id')::uuid;
    select hash into v_t from public.retorno_previa where id = v_id3;
    select client_id into v_cli2 from public.retorno_previa where id = v_id3;
    if v_cli2 is not null then
      raise exception '16j: nasceu com cliente';
    end if;
    v_cli2 := pg_temp.f3v_cli('Cadastro Depois Teste');
    insert into public.audit_log (table_name, record_id, action, changed_by, new_value, reason)
    values ('clients', v_cli2, 'lead_converted', 'retorno', jsonb_build_object('caso', v_caso3), 'teste');
    v_r := public.retorno_previa_montar(v_caso3, c_agora);
    perform pg_temp.f3v_igual('16k acao', v_r ->> 'acao', 'mantida');
    select client_id, hash into v_cli3, v_t2 from public.retorno_previa where id = v_id3;
    perform pg_temp.f3v_igual('16l cliente', v_cli3::text, v_cli2::text);
    perform pg_temp.f3v_igual('16m hash igual', v_t2, v_t);

    -- ═══ 17. Visita: marca ou proposta ver_no_local dão nada/visita_a_combinar; a rodada não recria.
    v_cli := pg_temp.f3v_cli('Visita Teste');
    v_un := pg_temp.f3v_un(v_cli, 'Visita Barco');
    v_caso := pg_temp.f3v_caso(90, 'cliente', v_cli, 'preciso trocar as baterias do barco, quanto custa?');
    update public.retorno_aberturas set visita_a_combinar_em = c_agora - interval '1 hour' where id = v_caso;
    perform pg_temp.f3v_igual('17a marca', public.retorno_previa_montar(v_caso, c_agora) ->> 'motivo', 'visita_a_combinar');
    update public.retorno_aberturas set visita_a_combinar_em = null where id = v_caso;
    insert into public.retorno_previa (abertura_id, chave, client_id, origem, titulo, estado, modo, hash)
    select v_caso, a.chave, v_cli, 'historico', 'Visita', 'ver_no_local', 'ligado', 'hash-visita'
      from public.retorno_aberturas a where a.id = v_caso;
    perform pg_temp.f3v_igual('17b proposta ver_no_local', public.retorno_previa_montar(v_caso, c_agora) ->> 'motivo', 'visita_a_combinar');
    update public.retorno_config set previa_modo = 'sombra', previa_ditado_ligado = true;
    v_r := public.retorno_previa_rodada(c_agora);
    select count(*) into v_n from public.retorno_previa where abertura_id = v_caso and estado in ('proposta', 'sombra');
    if v_n <> 0 then
      raise exception '17c: rodada recriou proposta de visita';
    end if;
    update public.retorno_config set previa_modo = 'ligado';

    -- ═══ 18b. Produto e serviço inativos: provisório, motivo inativo, sem preço.
    v_cli := pg_temp.f3v_cli('Inativo Teste');
    v_un := pg_temp.f3v_un(v_cli, 'Inativo Barco');
    v_p1 := pg_temp.f3v_prod('TF3V Peca Inativa', 500, false);
    v_s1 := pg_temp.f3v_serv('TF3V Servico Inativo', 500, false);
    v_os := pg_temp.f3v_os('TF3V-FONTE-INAT', v_cli, v_un, 'draft', 'approved', c_passado, 'troca de baterias');
    perform pg_temp.f3v_peca(v_os, v_p1, 1, 500, c_passado);
    perform pg_temp.f3v_lin(v_os, v_s1, 'TF3V Servico Inativo', 1, 500, c_passado);
    v_caso := pg_temp.f3v_caso(91, 'cliente', v_cli, 'preciso trocar as baterias do barco, quanto custa?');
    v_r := public.retorno_previa_montar(v_caso, c_agora);
    select count(*) into v_n from public.retorno_previa_linhas l
     where l.previa_id = (v_r ->> 'previa_id')::uuid and l.estado = 'provisorio' and l.motivo = 'inativo' and l.preco is null and l.preco_fonte = 'sem_preco';
    if v_n <> 2 then
      raise exception '18b: % linhas inativas marcadas', v_n;
    end if;
    select count(*) into v_n from public.retorno_previa_linhas l
     where l.previa_id = (v_r ->> 'previa_id')::uuid and l.nome in ('TF3V Peca Inativa', 'TF3V Servico Inativo');
    if v_n <> 2 then
      raise exception '18c: nome atual sumiu (%)', v_n;
    end if;

    -- ═══ 19. Parecido: o que nasceu depois da abertura não serve; alternativas depois de B.
    v_cli := pg_temp.f3v_cli('Parecido Teste');
    v_un := pg_temp.f3v_un(v_cli, 'Parecido Barco');
    v_cli2 := pg_temp.f3v_cli('Parecido Outro Teste');
    v_un2 := pg_temp.f3v_un(v_cli2, 'Parecido Outro Barco');
    -- fonte principal: mesmo cliente.
    v_os := pg_temp.f3v_os('TF3V-PAR-A', v_cli, v_un, 'draft', 'approved', '2040-04-01 10:00-03', 'troca de baterias');
    perform pg_temp.f3v_lin(v_os, null, 'Serviço parecido a', 1, 100, '2040-04-01 10:00-03');
    -- segunda opção: outro cliente.
    v_os2 := pg_temp.f3v_os('TF3V-PAR-B', v_cli2, v_un2, 'draft', 'approved', '2040-03-01 10:00-03', 'troca de baterias');
    perform pg_temp.f3v_lin(v_os2, null, 'Serviço parecido b', 1, 200, '2040-03-01 10:00-03');
    -- criado entre a abertura e p_agora: não serve.
    v_os3 := pg_temp.f3v_os('TF3V-PAR-TARDE', v_cli, v_un, 'draft', 'approved', '2040-06-15 09:30-03', 'troca de baterias');
    perform pg_temp.f3v_lin(v_os3, null, 'Serviço parecido tarde', 1, 300, '2040-06-15 09:30-03');
    v_caso := pg_temp.f3v_caso(92, 'cliente', v_cli, 'preciso trocar as baterias do barco, quanto custa?');
    v_r := public.retorno_previa_montar(v_caso, c_agora);
    select * into v_prev from public.retorno_previa where id = (v_r ->> 'previa_id')::uuid;
    perform pg_temp.f3v_igual('19a fonte', v_prev.fonte_numero, 'TF3V-PAR-A');
    if not exists (select 1 from jsonb_array_elements(v_prev.dados -> 'alternativas') e where e ->> 'numero' = 'TF3V-PAR-B') then
      raise exception '19b: alternativa B faltou: %', v_prev.dados;
    end if;
    if exists (select 1 from jsonb_array_elements(v_prev.dados -> 'alternativas') e where e ->> 'numero' = 'TF3V-PAR-TARDE') then
      raise exception '19c: o de depois da abertura serviu: %', v_prev.dados;
    end if;
    -- Letra B: força o outro parecido; a original aparece nas alternativas; travada.
    v_r := public.retorno_previa_montar(v_caso, c_agora, v_os2);
    perform pg_temp.f3v_igual('19d acao B', v_r ->> 'acao', 'criada');
    select * into v_prev2 from public.retorno_previa where id = (v_r ->> 'previa_id')::uuid;
    perform pg_temp.f3v_igual('19e fonte B', v_prev2.fonte_numero, 'TF3V-PAR-B');
    if not coalesce((v_prev2.dados ->> 'travada')::boolean, false) then
      raise exception '19f: B não travou';
    end if;
    if not exists (select 1 from jsonb_array_elements(v_prev2.dados -> 'alternativas') e where e ->> 'numero' = 'TF3V-PAR-A') then
      raise exception '19g: a original não voltou às alternativas: %', v_prev2.dados;
    end if;
    if exists (select 1 from public.retorno_previa where id = v_prev.id and estado <> 'descartada') then
      raise exception '19h: a anterior não foi descartada';
    end if;
    -- B com fonte que não está na lista: sem_parecido.
    perform pg_temp.f3v_igual('19i fonte fora', public.retorno_previa_montar(v_caso, c_agora, v_os3) ->> 'motivo', 'sem_parecido');

    -- ═══ 20. Total com quantidade fracionada: round por linha.
    v_cli := pg_temp.f3v_cli('Fracao Teste');
    v_un := pg_temp.f3v_un(v_cli, 'Fracao Barco');
    v_p1 := pg_temp.f3v_prod('TF3V Peca Fracao');
    v_os := pg_temp.f3v_os('TF3V-FONTE-FRAC', v_cli, v_un, 'draft', 'approved', c_passado, 'troca de baterias');
    perform pg_temp.f3v_peca(v_os, v_p1, 1.5, 333.33, c_passado);
    v_caso := pg_temp.f3v_caso(93, 'cliente', v_cli, 'preciso trocar as baterias do barco, quanto custa?');
    v_r := public.retorno_previa_montar(v_caso, c_agora);
    select * into v_prev from public.retorno_previa where id = (v_r ->> 'previa_id')::uuid;
    if v_prev.total <> 500.00 then
      raise exception '20: total %', v_prev.total;
    end if;

    -- ═══ 23. Ordem das linhas: mesmo created_at sai pelo id; duas montagens dão o mesmo hash.
    v_cli := pg_temp.f3v_cli('Ordem Teste');
    v_un := pg_temp.f3v_un(v_cli, 'Ordem Barco');
    v_p1 := pg_temp.f3v_prod('TF3V Ordem Um');
    v_p2 := pg_temp.f3v_prod('TF3V Ordem Dois');
    v_os := pg_temp.f3v_os('TF3V-FONTE-ORDEM', v_cli, v_un, 'draft', 'approved', c_passado, 'troca de baterias');
    perform pg_temp.f3v_peca(v_os, v_p1, 1, 10, c_passado);
    perform pg_temp.f3v_peca(v_os, v_p2, 1, 20, c_passado);
    v_caso := pg_temp.f3v_caso(94, 'cliente', v_cli, 'preciso trocar as baterias do barco, quanto custa?');
    v_r := public.retorno_previa_montar(v_caso, c_agora);
    v_id := (v_r ->> 'previa_id')::uuid;
    select hash into v_t from public.retorno_previa where id = v_id;
    v_r2 := public.retorno_previa_montar(v_caso, c_agora + interval '1 hour');
    perform pg_temp.f3v_igual('23a mantida', v_r2 ->> 'acao', 'mantida');
    perform pg_temp.f3v_igual('23b mesmo id', v_r2 ->> 'previa_id', v_id::text);
    select hash into v_t2 from public.retorno_previa where id = v_id;
    perform pg_temp.f3v_igual('23c hash igual', v_t2, v_t);
    -- A ordem respeita o id das linhas da fonte.
    select string_agg(l.nome, ',' order by l.ordem) into v_d from public.retorno_previa_linhas l where l.previa_id = v_id;
    select string_agg(pr.name, ',' order by p.id) into v_t
      from public.service_order_parts p join public.products pr on pr.id = p.product_id where p.service_order_id = v_os;
    perform pg_temp.f3v_igual('23d ordem pelo id', v_d, v_t);

    raise exception 'retorno_f3_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f3_desfaz' then
      raise;
    end if;
  end;

  -- ═══ 21, 24. Dinheiro, quantidade, hash e rótulos (funções puras).
  perform pg_temp.f3v_igual('21a brl', public._retorno_brl(1320), '1.320');
  perform pg_temp.f3v_igual('21b brl', public._retorno_brl(1320.5), '1.320,50');
  perform pg_temp.f3v_igual('21c brl', public._retorno_brl(0.5), '0,50');
  perform pg_temp.f3v_igual('21d brl', public._retorno_brl(1000000), '1.000.000');
  perform pg_temp.f3v_igual('21e qtd', public._retorno_qtd(1.000), '1');
  perform pg_temp.f3v_igual('21f qtd', public._retorno_qtd(1.500), '1,5');
  perform pg_temp.f3v_igual('21g qtd', public._retorno_qtd(2.25), '2,25');
  if public._retorno_previa_hash(null, 'T', '[{"ordem": 1, "nome": "X", "quantidade": 2, "preco": 10, "estado": "ok"}]')
     is distinct from public._retorno_previa_hash(null, 'T', '[{"ordem": 1, "nome": "X", "quantidade": 2.000, "preco": 10.00, "estado": "ok"}]') then
    raise exception '21h: 2 e 2.000 deram hash diferente';
  end if;
  if public._retorno_previa_hash(null, 'T', '[{"ordem": 1, "nome": "X", "quantidade": 2, "preco": 10, "estado": "ok"}]')
     = public._retorno_previa_hash(null, 'T', '[{"ordem": 1, "nome": "X", "quantidade": 3, "preco": 10, "estado": "ok"}]') then
    raise exception '21i: quantidade diferente deu hash igual';
  end if;

  perform pg_temp.f3v_igual('24a', public._retorno_rotulo_do_preco('praticado_cliente', '2026-08-12'), 'praticado em 12/08/26');
  perform pg_temp.f3v_igual('24b', public._retorno_rotulo_do_preco('praticado_cliente', '2026-08-12', true), '12/08/26');
  perform pg_temp.f3v_igual('24c', public._retorno_rotulo_do_preco('praticado_outro', '2026-08-12'), 'praticado a outro cliente em 12/08/26');
  perform pg_temp.f3v_igual('24d', public._retorno_rotulo_do_preco('praticado_outro', '2026-08-12', true), 'outro cliente 12/08/26');
  perform pg_temp.f3v_igual('24e', public._retorno_rotulo_do_preco('orcado_cliente', '2026-08-12'), 'orçado em 12/08/26 (não aprovado)');
  perform pg_temp.f3v_igual('24f', public._retorno_rotulo_do_preco('orcado_cliente', '2026-08-12', true), 'orçado 12/08/26');
  perform pg_temp.f3v_igual('24g', public._retorno_rotulo_do_preco('orcado_outro', '2026-08-12'), 'orçado a outro cliente em 12/08/26 (não aprovado)');
  perform pg_temp.f3v_igual('24h', public._retorno_rotulo_do_preco('orcado_outro', '2026-08-12', true), 'orçado a outro 12/08/26');
  perform pg_temp.f3v_igual('24i', public._retorno_rotulo_do_preco('catalogo', null), 'preço de catálogo, sem data');
  perform pg_temp.f3v_igual('24j', public._retorno_rotulo_do_preco('catalogo', null, true), 'catálogo');
  perform pg_temp.f3v_igual('24k', public._retorno_rotulo_do_preco('dito', null), 'você disse');
  perform pg_temp.f3v_igual('24l', public._retorno_rotulo_do_preco('dito', null, true), 'dito');
  perform pg_temp.f3v_igual('24m', public._retorno_rotulo_do_preco('sem_preco', null), 'sem preço');
  perform pg_temp.f3v_igual('24n', public._retorno_rotulo_do_preco('sem_preco', null, true), 'sem preço');

  -- ═══ 22. retorno_previa_precos: a ordem e a chave voltam iguais; zero dá sem_preco; orcado nunca traz "praticado"; 41 itens dão 22023; cliente nulo só traz outro/catálogo/sem.
  begin
    v_cli := pg_temp.f3v_cli('Precos Teste');
    v_un := pg_temp.f3v_un(v_cli, 'Precos Barco');
    v_p1 := pg_temp.f3v_prod('TF3V Precos Peca', 42);
    v_p2 := pg_temp.f3v_prod('TF3V Precos Zero', 0);
    v_os := pg_temp.f3v_os('TF3V-PRECOS-ORC', v_cli, v_un, 'draft', 'draft', '2040-02-01 10:00-03', 'x');
    perform pg_temp.f3v_peca(v_os, v_p1, 1, 55, '2040-02-01 10:00-03');
    v_a := public.retorno_previa_precos(v_cli, jsonb_build_array(
      jsonb_build_object('chave', '0', 'tipo', 'peca', 'product_id', v_p1),
      jsonb_build_object('chave', 'x1', 'tipo', 'peca', 'product_id', v_p2),
      jsonb_build_object('chave', 'x2', 'tipo', 'servico', 'nome', 'Serviço inexistente na base'),
      jsonb_build_object('chave', 'x3', 'tipo', 'peca')
    ), c_agora);
    perform pg_temp.f3v_igual('22a chave 0', v_a -> 0 ->> 'chave', '0');
    perform pg_temp.f3v_igual('22b chave x3', v_a -> 3 ->> 'chave', 'x3');
    perform pg_temp.f3v_igual('22c fonte orcado', v_a -> 0 ->> 'fonte', 'orcado_cliente');
    if (v_a -> 0 ->> 'preco')::numeric <> 55 then
      raise exception '22d: %', v_a -> 0;
    end if;
    if (v_a -> 0 ->> 'rotulo') like '%praticado%' or (v_a -> 0 ->> 'rotulo') not like '%orçado%' then
      raise exception '22e: rótulo %', v_a -> 0 ->> 'rotulo';
    end if;
    if v_a -> 1 ->> 'preco' is not null or v_a -> 1 ->> 'fonte' <> 'sem_preco' then
      raise exception '22f: zero %', v_a -> 1;
    end if;
    if v_a -> 2 ->> 'preco' is not null or v_a -> 3 ->> 'preco' is not null or v_a -> 2 ->> 'fonte' <> 'sem_preco' then
      raise exception '22g: serviço/peça sem id %', v_a;
    end if;
    v_a := public.retorno_previa_precos(null, jsonb_build_array(jsonb_build_object('chave', 'a', 'tipo', 'peca', 'product_id', v_p1)), c_agora);
    if v_a -> 0 ->> 'fonte' not in ('orcado_outro', 'praticado_outro', 'catalogo', 'sem_preco') then
      raise exception '22h: cliente nulo trouxe %', v_a -> 0 ->> 'fonte';
    end if;
    begin
      perform public.retorno_previa_precos(v_cli, (select jsonb_agg(jsonb_build_object('chave', g::text, 'tipo', 'peca')) from generate_series(1, 41) g), c_agora);
      raise exception '22i: 41 itens passaram' using errcode = 'P0002';
    exception when others then
      if sqlstate <> '22023' then
        raise;
      end if;
    end;
    begin
      perform public.retorno_previa_precos(v_cli, '[{"chave": "a", "tipo": "outro"}]'::jsonb, c_agora);
      raise exception '22j: tipo inválido passou' using errcode = 'P0002';
    exception when others then
      if sqlstate <> '22023' then
        raise;
      end if;
    end;

    raise exception 'retorno_f3_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f3_desfaz' then
      raise;
    end if;
  end;

  insert into _bancada (arquivo, ok, numeros) values ('retorno_f3_previa', true, '{}');
end
$previa$;

select arquivo, ok, numeros from _bancada order by em;
rollback;

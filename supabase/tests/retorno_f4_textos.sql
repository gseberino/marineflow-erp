-- Retorno F4 (P4): o catálogo do parceiro (_parceiro_texto) literal, a abertura {comigo}/{pessoa}, o nome curto, a palavra do
-- bem, as listas de nomes do validador, o gênero, a apresentação ao cliente final e o contexto do validador (sem a linha
-- pronto, que chama a P7 e é testada em P7.3-16). Roda só pela bancada (grupo 7, F4_ONDA=2). Termina em ROLLBACK.
-- Telefones de teste 55479000142xx; nomes e siglas inventados.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- Um cliente de teste com uma unidade (do tipo pedido) e uma OS em rascunho. Devolve o cliente.
create or replace function pg_temp.retorno_f4_textos_cliente(p_nome text, p_tipo text default 'individual',
                                                            p_bem text default 'Motorhome') returns uuid
language plpgsql as $f$
declare
  v_c uuid;
  v_v uuid;
begin
  insert into public.clients (type, name) values (p_tipo, p_nome) returning id into v_c;
  insert into public.vessels (client_id, name, asset_type) values (v_c, 'Unidade ' || left(md5(p_nome), 6), p_bem) returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, grand_total)
    values ('ORÇ-TF4-TXT-' || left(md5(p_nome || clock_timestamp()::text), 8), v_c, v_v, 'draft', 'draft', 'repair', 0);
  return v_c;
end $f$;

-- Liga a OS mais recente do cliente ao parceiro, proposta (qualquer situação conta como "outro" para os nomes).
create or replace function pg_temp.retorno_f4_textos_liga(p_parceiro uuid, p_cliente uuid, p_situacao text default 'proposto')
returns uuid
language plpgsql as $f$
declare
  v uuid;
begin
  insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, situacao, origem, confirmado_em)
  select so.id, p_parceiro, p_cliente,
         case when p_situacao = 'confirmado' then 'indicou' end, p_situacao, 'carteira',
         case when p_situacao = 'confirmado' then now() end
    from public.service_orders so where so.client_id = p_cliente order by so.created_at desc, so.id limit 1
  returning id into v;
  return v;
end $f$;

-- Roda p_sql e devolve 'passou' (desfazendo o que fez) ou o SQLSTATE do erro.
create or replace function pg_temp.retorno_f4_textos_erro(p_sql text) returns text
language plpgsql as $f$
begin
  begin
    execute p_sql;
    raise exception 'retorno_f4_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate = 'P0001' and sqlerrm = 'retorno_f4_desfaz' then
      return 'passou';
    end if;
    return sqlstate;
  end;
end $f$;

do $textos$
declare
  c_t constant timestamptz := '2027-01-12 15:00-03';
  c_base constant jsonb := '{"quando": "hoje", "hora": "19h", "bem": "motorhome", "primeiro_nome": "João", "validade": "15/01", "nomes_de_outros": []}';
  v_parc uuid;
  v_carla uuid;
  v_compart uuid;
  v_num_carla uuid;
  v_num_compart uuid;
  v_abre text;
  v_t text;
  v_r record;
  v_todos text[] := '{}';
  v_n integer := 0;
  v_j jsonb;
  v jsonb;
  -- nomes do validador
  v_pa uuid; v_pb uuid; v_pc uuid; v_pd uuid; v_pe uuid; v_pf uuid; v_pg uuid;
  v_j1 uuid; v_j2 uuid; v_j3 uuid; v_j4 uuid;
  v_c1 uuid; v_c2 uuid; v_c3 uuid;
  v_pessoa_e uuid; v_pessoa_f uuid;
  v_k uuid;
  v_vinculo uuid;
  v_s text;
  v_n_fun integer := 0;
begin
  begin
  -- Arranjo: a revenda de teste com Carla (número 14201) e o número compartilhado sem nome (14202).
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Textos F4', 'RTF', 'revenda_e_patio') returning id into v_parc;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_parc, 'Carla', 'comercial') returning id into v_carla;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_parc, null, 'comercial') returning id into v_compart;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em)
    values (v_carla, '5547900014201', '00014201', '47', 'confirmado', c_t - interval '30 days') returning id into v_num_carla;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em)
    values (v_compart, '5547900014202', '00014202', '47', 'confirmado', c_t - interval '30 days') returning id into v_num_compart;

  -- 1. As 20 combinações de {comigo}/{pessoa} em P02, P03, P14, P15 e P16, literais (P4.1).
  for v_r in
    select * from (values
      ('P02', 'parceiro_recibo', null::text, 'carla', true, 'Carla, aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para vocês ainda hoje.'),
      ('P02', 'parceiro_recibo', null, 'compart', true, 'Aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para vocês ainda hoje.'),
      ('P02', 'parceiro_recibo', null, 'carla', false, 'Oi, Carla! Já passei sua mensagem ao Gustavo, e ele retorna para vocês ainda hoje.'),
      ('P02', 'parceiro_recibo', null, 'compart', false, 'Já passei sua mensagem ao Gustavo, e ele retorna para vocês ainda hoje.'),
      ('P03', 'parceiro_coleta', 'veiculo_nome', 'carla', true, 'Carla, aqui é a Claudia, assistente virtual da HBR. Já passei seu pedido ao Gustavo, e ele retorna para vocês ainda hoje. Para adiantar: qual é o veículo e o primeiro nome do cliente?'),
      ('P03', 'parceiro_coleta', 'veiculo_nome', 'compart', true, 'Aqui é a Claudia, assistente virtual da HBR. Já passei seu pedido ao Gustavo, e ele retorna para vocês ainda hoje. Para adiantar: qual é o veículo e o primeiro nome do cliente?'),
      ('P03', 'parceiro_coleta', 'veiculo_nome', 'carla', false, 'Oi, Carla! Já passei seu pedido ao Gustavo, e ele retorna para vocês ainda hoje. Para adiantar: qual é o veículo e o primeiro nome do cliente?'),
      ('P03', 'parceiro_coleta', 'veiculo_nome', 'compart', false, 'Já passei seu pedido ao Gustavo, e ele retorna para vocês ainda hoje. Para adiantar: qual é o veículo e o primeiro nome do cliente?'),
      ('P14', 'parceiro_repassar', null, 'carla', true, 'Carla, aqui é a Claudia, assistente virtual da HBR. João não tem WhatsApp com a gente. Pode repassar esta mensagem? "João, o serviço no seu motorhome terminou. O Gustavo combina com você o melhor dia para buscar." Se o cliente autorizar, me passa o WhatsApp que o Gustavo fala direto.'),
      ('P14', 'parceiro_repassar', null, 'compart', true, 'Aqui é a Claudia, assistente virtual da HBR. João não tem WhatsApp com a gente. Pode repassar esta mensagem? "João, o serviço no seu motorhome terminou. O Gustavo combina com você o melhor dia para buscar." Se o cliente autorizar, me passa o WhatsApp que o Gustavo fala direto.'),
      ('P14', 'parceiro_repassar', null, 'carla', false, 'Oi, Carla! João não tem WhatsApp com a gente. Pode repassar esta mensagem? "João, o serviço no seu motorhome terminou. O Gustavo combina com você o melhor dia para buscar." Se o cliente autorizar, me passa o WhatsApp que o Gustavo fala direto.'),
      ('P14', 'parceiro_repassar', null, 'compart', false, 'João não tem WhatsApp com a gente. Pode repassar esta mensagem? "João, o serviço no seu motorhome terminou. O Gustavo combina com você o melhor dia para buscar." Se o cliente autorizar, me passa o WhatsApp que o Gustavo fala direto.'),
      ('P15', 'parceiro_recibo', 'orcamento', 'carla', true, 'Carla, aqui é a Claudia, assistente virtual da HBR. O orçamento do motorhome de João está com o Gustavo; ele retorna para vocês ainda hoje.'),
      ('P15', 'parceiro_recibo', 'orcamento', 'compart', true, 'Aqui é a Claudia, assistente virtual da HBR. O orçamento do motorhome de João está com o Gustavo; ele retorna para vocês ainda hoje.'),
      ('P15', 'parceiro_recibo', 'orcamento', 'carla', false, 'Oi, Carla! O orçamento do motorhome de João está com o Gustavo; ele retorna para vocês ainda hoje.'),
      ('P15', 'parceiro_recibo', 'orcamento', 'compart', false, 'O orçamento do motorhome de João está com o Gustavo; ele retorna para vocês ainda hoje.'),
      ('P16', 'parceiro_legenda', null, 'carla', true, 'Carla, aqui é a Claudia, assistente virtual da HBR. Segue o orçamento do motorhome de João, válido até 15/01.'),
      ('P16', 'parceiro_legenda', null, 'compart', true, 'Aqui é a Claudia, assistente virtual da HBR. Segue o orçamento do motorhome de João, válido até 15/01.'),
      ('P16', 'parceiro_legenda', null, 'carla', false, 'Oi, Carla! Segue o orçamento do motorhome de João, válido até 15/01.'),
      ('P16', 'parceiro_legenda', null, 'compart', false, 'Segue o orçamento do motorhome de João, válido até 15/01.')
    ) as x(modelo, tipo, variante, numero, primeira, esperado)
  loop
    update public.parceiro_numeros
       set apresentada_em = case when v_r.primeira then null else c_t - interval '1 day' end
     where id in (v_num_carla, v_num_compart);
    v_abre := public._parceiro_abertura(case when v_r.numero = 'carla' then v_num_carla else v_num_compart end, '[]'::jsonb, c_t);
    v_t := public._parceiro_texto(v_r.tipo, v_r.variante, c_base || jsonb_build_object('abertura', v_abre));
    if v_t is distinct from v_r.esperado then
      raise exception '1: % (%, 1ª = %) saiu: %', v_r.modelo, v_r.numero, v_r.primeira, v_t;
    end if;
    v_todos := v_todos || v_t;
    v_n := v_n + 1;
  end loop;
  if v_n is distinct from 20 then
    raise exception '1: % combinações, esperava 20', v_n;
  end if;

  -- 2. P01: só {comigo}; depois da 1ª, começa em "A partir de agora" (nunca "Oi, Carla! A partir…").
  update public.parceiro_numeros set apresentada_em = null where id = v_num_carla;
  v_t := public._parceiro_texto('parceiro_ativacao', null,
                                jsonb_build_object('abertura', public._parceiro_abertura(v_num_carla, '[]'::jsonb, c_t)));
  if v_t is distinct from 'Carla, aqui é a Claudia, assistente virtual da HBR. A partir de agora, no fim de cada dia útil em que algo mudar, mando um resumo dos motorhomes dos clientes de vocês que estão com a gente: o que andou e o próximo passo. Valores e dados ficam com cada cliente. A qualquer hora, mande *pátio*. Para pausar, mande *pausar*.' then
    raise exception '2a: P01 na 1ª mensagem: %', v_t;
  end if;
  v_todos := v_todos || v_t;
  update public.parceiro_numeros set apresentada_em = c_t - interval '1 day' where id = v_num_carla;
  v_t := public._parceiro_texto('parceiro_ativacao', null,
                                jsonb_build_object('abertura', public._parceiro_abertura(v_num_carla, '[]'::jsonb, c_t)));
  if v_t is distinct from 'A partir de agora, no fim de cada dia útil em que algo mudar, mando um resumo dos motorhomes dos clientes de vocês que estão com a gente: o que andou e o próximo passo. Valores e dados ficam com cada cliente. A qualquer hora, mande *pátio*. Para pausar, mande *pausar*.' then
    raise exception '2b: P01 depois da 1ª: %', v_t;
  end if;

  -- 3. Apresentação só na 1ª; {comigo} no número compartilhado sem nome; pessoa_ok falso tira o nome; número desconhecido 22023.
  update public.parceiro_numeros set apresentada_em = null where id in (v_num_carla, v_num_compart);
  if public._parceiro_ja_apresentada(v_num_carla, c_t) then
    raise exception '3a: número sem apresentada_em deu apresentado';
  end if;
  update public.parceiro_numeros set apresentada_em = c_t + interval '1 hour' where id = v_num_carla;
  if public._parceiro_ja_apresentada(v_num_carla, c_t) then
    raise exception '3b: apresentação do futuro valeu (ninguém olha o futuro)';
  end if;
  update public.parceiro_numeros set apresentada_em = c_t - interval '400 days' where id = v_num_carla;
  if public._parceiro_ja_apresentada(v_num_carla, c_t) then
    raise exception '3c: apresentação de mais de um ano valeu';
  end if;
  update public.parceiro_numeros set apresentada_em = c_t - interval '1 day' where id = v_num_carla;
  if not public._parceiro_ja_apresentada(v_num_carla, c_t) then
    raise exception '3d: apresentação de ontem não valeu';
  end if;
  if public._parceiro_abertura(v_num_compart, '[]'::jsonb, c_t) is distinct from 'Aqui é a Claudia, assistente virtual da HBR. ' then
    raise exception '3e: {comigo} do número compartilhado sem nome';
  end if;
  if public._parceiro_abertura(v_num_carla, '["Carla"]'::jsonb, c_t) is distinct from '' then
    raise exception '3f: pessoa_ok falso não tirou o nome depois da 1ª';
  end if;
  update public.parceiro_numeros set apresentada_em = null where id = v_num_carla;
  if public._parceiro_abertura(v_num_carla, '["carla"]'::jsonb, c_t) is distinct from 'Aqui é a Claudia, assistente virtual da HBR. '
     or public._parceiro_abertura(v_num_carla, null, c_t) is distinct from 'Aqui é a Claudia, assistente virtual da HBR. ' then
    raise exception '3g: pessoa_ok falso (ou lista ausente) não tirou o nome na 1ª';
  end if;
  if pg_temp.retorno_f4_textos_erro(format('select public._parceiro_abertura(%L::uuid, %L::jsonb, %L::timestamptz)',
                                           gen_random_uuid(), '[]', c_t)) is distinct from '22023' then
    raise exception '3h: número desconhecido não deu 22023';
  end if;

  -- 4. Os outros modelos ao parceiro, literais.
  for v_r in
    select * from (values
      ('P04', 'parceiro_coleta', 'whatsapp', '{"primeiro_nome": "João", "nomes_de_outros": []}'::jsonb,
       'Obrigada! João tem WhatsApp? Se o cliente autorizar, me passa o número que o Gustavo fala direto.'),
      ('P04 sem nome', 'parceiro_coleta', 'whatsapp', '{}'::jsonb,
       'O cliente tem WhatsApp? Se autorizar, me passa o número que o Gustavo fala direto.'),
      ('P04 com nome de outro', 'parceiro_coleta', 'whatsapp', '{"primeiro_nome": "João", "nomes_de_outros": ["João"]}'::jsonb,
       'O cliente tem WhatsApp? Se autorizar, me passa o número que o Gustavo fala direto.'),
      ('P05', 'parceiro_recado', null, '{"nome": "Carla"}'::jsonb,
       'Anotado, Carla. Antes de começar, confirmo com o cliente e com o Gustavo e te aviso.'),
      ('P05 sem nome', 'parceiro_recado', null, '{}'::jsonb,
       'Anotado. Antes de começar, confirmo com o cliente e com o Gustavo e aviso vocês.'),
      ('P07', 'parceiro_eco', 'pronto', '{"bem": "motorhome", "cliente": "João S."}'::jsonb,
       'Pátio HBR: o motorhome de João S. ficou pronto. O cliente já foi avisado para combinar a retirada.'),
      ('P08', 'parceiro_eco', 'atraso', '{"bem": "motorhome", "cliente": "João S."}'::jsonb,
       'Pátio HBR: o serviço no motorhome de João S. vai atrasar porque uma peça não chegou. O cliente já foi avisado.'),
      ('P09', 'parceiro_eco', 'peca_chegou', '{"bem": "motorhome", "cliente": "João S."}'::jsonb,
       'Pátio HBR: a peça do motorhome de João S. chegou. O cliente já foi avisado.'),
      ('P10 vazio', 'parceiro_patio', 'vazio', '{}'::jsonb,
       'Pátio HBR: nenhum veículo dos clientes de vocês por aqui agora.'),
      ('P10 direto', 'parceiro_patio', 'direto', '{"dia": "2027-01-12", "linhas": ["1. Motorhome de Ana B.: em serviço."]}'::jsonb,
       E'Pátio HBR · 12/01\n1. Motorhome de Ana B.: em serviço.'),
      ('P12', 'parceiro_pausa', 'pausar', '{}'::jsonb,
       'Combinado: o resumo fica pausado. Para voltar, mande *retomar*.'),
      ('P13', 'parceiro_pausa', 'retomar', '{}'::jsonb,
       'Pronto: o resumo volta no próximo dia útil em que algo mudar.'),
      ('P15 com nome de outro', 'parceiro_recibo', 'orcamento',
       '{"abertura": "", "quando": "hoje", "hora": "19h", "bem": "motorhome", "primeiro_nome": "João", "nomes_de_outros": ["Pedro", "joão"]}'::jsonb,
       'O orçamento do motorhome do cliente está com o Gustavo; ele retorna para vocês ainda hoje.'),
      ('P15 sem nome', 'parceiro_recibo', 'orcamento', '{"abertura": "", "quando": "hoje", "hora": "19h", "bem": "veículo"}'::jsonb,
       'O orçamento do veículo do cliente está com o Gustavo; ele retorna para vocês ainda hoje.'),
      ('P02 com bloco P11', 'parceiro_recibo', null,
       '{"abertura": "", "quando": "hoje", "hora": "19h", "bloco_linhas": ["1. Motorhome de Ana B.: em serviço hoje.", "2. Motorhome de Bruno C.: sem novidade desde 02/01."], "bloco_mais": 1}'::jsonb,
       E'Já passei sua mensagem ao Gustavo, e ele retorna para vocês ainda hoje.\nEnquanto isso, o pátio de hoje:\n1. Motorhome de Ana B.: em serviço hoje.\n2. Motorhome de Bruno C.: sem novidade desde 02/01.\nE mais 1 veículo.')
    ) as x(modelo, tipo, variante, dados, esperado)
  loop
    v_t := public._parceiro_texto(v_r.tipo, v_r.variante, v_r.dados);
    if v_t is distinct from v_r.esperado then
      raise exception '4: % saiu: %', v_r.modelo, v_t;
    end if;
    v_todos := v_todos || v_t;
  end loop;

  -- 5. As linhas do painel, uma por estado, e o painel (P06) com "E mais" e o rodapé.
  for v_r in
    select * from (values
      ('{"n": 1, "bem": "motorhome", "cliente": "João S.", "estado": "pronto"}'::jsonb, '1. Motorhome de João S.: pronto; o cliente já foi avisado para combinar a retirada.'),
      ('{"n": 2, "bem": "motorhome", "cliente": "Ana B.", "estado": "peca_chegou", "desde": "2027-01-03"}', '2. Motorhome de Ana B.: a peça chegou em 03/01.'),
      ('{"n": 3, "bem": "trailer", "cliente": "Bruno C.", "estado": "aguarda_peca", "desde": "2027-01-02"}', '3. Trailer de Bruno C.: aguardando uma peça; sem novidade desde 02/01.'),
      ('{"n": 4, "bem": "camper", "cliente": "Caio D.", "estado": "aguarda_peca"}', '4. Camper de Caio D.: aguardando uma peça.'),
      ('{"n": 5, "bem": "motorhome", "cliente": "Davi E.", "estado": "em_servico"}', '5. Motorhome de Davi E.: em serviço hoje.'),
      ('{"n": 6, "bem": "veículo", "cliente": "Edu F.", "estado": "orcamento"}', '6. Veículo de Edu F.: orçamento pedido por vocês; com o Gustavo.'),
      ('{"n": 7, "bem": "motorhome", "cliente": "Fábio G.", "estado": "andamento", "desde": "2026-12-28"}', '7. Motorhome de Fábio G.: sem novidade desde 28/12.'),
      ('{"n": 8, "bem": "barco", "cliente": "Gil H.", "estado": "andamento_sem_data"}', '8. Barco de Gil H.: em serviço.')
    ) as x(dados, esperado)
  loop
    v_t := public._parceiro_texto('parceiro_painel', 'linha', v_r.dados);
    if v_t is distinct from v_r.esperado then
      raise exception '5a: linha % saiu: %', v_r.dados ->> 'estado', v_t;
    end if;
    if public._parceiro_texto('parceiro_patio', 'linha', v_r.dados) is distinct from v_r.esperado then
      raise exception '5b: a linha do pátio difere da do painel em %', v_r.dados ->> 'estado';
    end if;
  end loop;
  v_t := public._parceiro_texto('parceiro_painel', null, jsonb_build_object('dia', '2027-01-12',
           'linhas', jsonb_build_array('1. Motorhome de João S.: aguardando uma peça; sem novidade desde 02/01.')));
  if v_t is distinct from E'Pátio HBR · ter (12/01)\n1. Motorhome de João S.: aguardando uma peça; sem novidade desde 02/01.\nPara ver de novo, mande *pátio*.' then
    raise exception '5c: P06 saiu: %', v_t;
  end if;
  v_todos := v_todos || v_t;
  v_t := public._parceiro_texto('parceiro_painel', null, jsonb_build_object('dia', '2027-01-16',
           'linhas', jsonb_build_array('1. Motorhome de Ana B.: em serviço.'), 'mais', 6, 'rodape', true));
  if v_t is distinct from E'Pátio HBR · sáb (16/01)\n1. Motorhome de Ana B.: em serviço.\nE mais 6 veículos.\nPara ver de novo, mande *pátio*.\nValores e dados ficam com cada cliente.' then
    raise exception '5d: P06 com E mais e rodapé saiu: %', v_t;
  end if;
  v_todos := v_todos || v_t;

  -- 6. Ao cliente final: Q01/Q02 com indicou, Q04/Q05 com contratante ou pagador; Q03 e Q03b.
  for v_r in
    select * from (values
      ('Q01', 'parceiro_aviso_cliente', 'com_apresentacao', 'indicou',
       'João, aqui é a Claudia, assistente virtual da HBR. Como você veio pela MP, ela também acompanha o andamento do seu motorhome, sem valores. Se preferir que não, responda NÃO MP.'),
      ('Q02', 'parceiro_aviso_cliente', 'seguinte', 'indicou',
       'João, como você veio pela MP, ela também acompanha o andamento do seu motorhome, sem valores. Se preferir que não, responda NÃO MP.'),
      ('Q04', 'parceiro_aviso_cliente', 'com_apresentacao', 'contratante',
       'João, aqui é a Claudia, assistente virtual da HBR. Este serviço no seu motorhome está sendo feito por meio da MP, e ela acompanha o andamento. Se preferir que não, responda NÃO MP.'),
      ('Q05', 'parceiro_aviso_cliente', 'seguinte', 'pagador',
       'João, este serviço no seu motorhome está sendo feito por meio da MP, e ela acompanha o andamento. Se preferir que não, responda NÃO MP.'),
      ('Q04 pela variante', 'parceiro_aviso_cliente', 'contrata_com_apresentacao', 'contratante',
       'João, aqui é a Claudia, assistente virtual da HBR. Este serviço no seu motorhome está sendo feito por meio da MP, e ela acompanha o andamento. Se preferir que não, responda NÃO MP.'),
      ('Q05 pela variante', 'parceiro_aviso_cliente', 'contrata_seguinte', 'contratante',
       'João, este serviço no seu motorhome está sendo feito por meio da MP, e ela acompanha o andamento. Se preferir que não, responda NÃO MP.'),
      ('Q03', 'parceiro_nao_mp_ok', 'com_nome', null, 'Combinado, João: o andamento fica só entre nós.'),
      ('Q03b', 'parceiro_nao_mp_ok', 'sem_nome', null, 'Combinado: o andamento fica só entre nós.')
    ) as x(modelo, tipo, variante, papel, esperado)
  loop
    v_t := public._parceiro_texto(v_r.tipo, v_r.variante,
                                  jsonb_build_object('nome', 'João', 'sigla', 'MP', 'bem', 'motorhome', 'papel', v_r.papel));
    if v_t is distinct from v_r.esperado then
      raise exception '6: % saiu: %', v_r.modelo, v_t;
    end if;
    v_todos := v_todos || v_t;
  end loop;
  if public._parceiro_texto('parceiro_nao_mp_ok', 'sem_nome', '{}'::jsonb) ~ 'João' then
    raise exception '6b: Q03b levou nome';
  end if;

  -- 7. Dado faltando ou fora da lista: 22023.
  for v_r in
    select * from (values
      ('P02 sem quando', 'select public._parceiro_texto(''parceiro_recibo'', null, ''{"abertura": "", "hora": "19h"}'')'),
      ('P02 sem abertura', 'select public._parceiro_texto(''parceiro_recibo'', null, ''{"quando": "hoje", "hora": "19h"}'')'),
      ('P02 com abertura torta', 'select public._parceiro_texto(''parceiro_recibo'', null, ''{"abertura": "Olá! ", "quando": "hoje", "hora": "19h"}'')'),
      ('P16 sem validade', 'select public._parceiro_texto(''parceiro_legenda'', null, ''{"abertura": "", "bem": "motorhome", "primeiro_nome": "João"}'')'),
      ('P16 sem nome', 'select public._parceiro_texto(''parceiro_legenda'', null, ''{"abertura": "", "bem": "motorhome", "validade": "15/01"}'')'),
      ('P07 com placa no bem', 'select public._parceiro_texto(''parceiro_eco'', ''pronto'', ''{"bem": "ABC1D23", "cliente": "João S."}'')'),
      ('P07 com telefone no nome', 'select public._parceiro_texto(''parceiro_eco'', ''pronto'', ''{"bem": "motorhome", "cliente": "João 4799991234"}'')'),
      ('Q sem papel', 'select public._parceiro_texto(''parceiro_aviso_cliente'', ''com_apresentacao'', ''{"nome": "João", "sigla": "MP", "bem": "motorhome"}'')'),
      ('Q indicou contrata', 'select public._parceiro_texto(''parceiro_aviso_cliente'', ''contrata_seguinte'', ''{"nome": "João", "sigla": "MP", "bem": "motorhome", "papel": "indicou"}'')'),
      ('P04 sem lista de outros', 'select public._parceiro_texto(''parceiro_coleta'', ''whatsapp'', ''{"primeiro_nome": "João"}'')'),
      ('linha andamento sem data', 'select public._parceiro_texto(''parceiro_painel'', ''linha'', ''{"n": 1, "bem": "motorhome", "cliente": "Ana B.", "estado": "andamento"}'')'),
      ('linha peça sem data', 'select public._parceiro_texto(''parceiro_painel'', ''linha'', ''{"n": 1, "bem": "motorhome", "cliente": "Ana B.", "estado": "peca_chegou"}'')'),
      ('linha estado estranho', 'select public._parceiro_texto(''parceiro_painel'', ''linha'', ''{"n": 1, "bem": "motorhome", "cliente": "Ana B.", "estado": "pronto_hoje"}'')'),
      ('linha data inválida', 'select public._parceiro_texto(''parceiro_painel'', ''linha'', ''{"n": 1, "bem": "motorhome", "cliente": "Ana B.", "estado": "andamento", "desde": "2027-13-40"}'')'),
      ('linha sem_inicio com parceiro_sem_inicio_ligado desligada ou ausente (R2)',
       'select public._parceiro_texto(''parceiro_painel'', ''linha'', ''{"n": 1, "bem": "motorhome", "cliente": "Ana B.", "estado": "sem_inicio"}'')'),
      ('painel sem linhas', 'select public._parceiro_texto(''parceiro_painel'', null, ''{"dia": "2027-01-12", "linhas": []}'')'),
      ('painel com 15 linhas', format('select public._parceiro_texto(''parceiro_painel'', null, %L)',
         jsonb_build_object('dia', '2027-01-12', 'linhas', (select jsonb_agg(i || '. Motorhome de Ana B.: em serviço.') from generate_series(1, 15) i)))),
      ('bloco com 6 linhas', format('select public._parceiro_texto(''parceiro_recibo'', null, %L)',
         jsonb_build_object('abertura', '', 'quando', 'hoje', 'hora', '19h',
                            'bloco_linhas', (select jsonb_agg(i || '. Motorhome de Ana B.: em serviço.') from generate_series(1, 6) i)))),
      ('modelo desconhecido', 'select public._parceiro_texto(''parceiro_inventado'', null, ''{}'')')
    ) as x(caso, sql)
  loop
    v_s := pg_temp.retorno_f4_textos_erro(v_r.sql);
    if v_s is distinct from '22023' then
      raise exception '7: % deu % (esperava 22023)', v_r.caso, v_s;
    end if;
  end loop;

  -- 8. Nenhum texto começa com espaço, tem dois espaços seguidos ou repete o nome da pessoa.
  foreach v_t in array v_todos loop
    if v_t ~ '^[[:space:]]' or v_t ~ '  ' then
      raise exception '8a: espaço sobrando em: %', v_t;
    end if;
    if (char_length(v_t) - char_length(replace(v_t, 'Carla', ''))) / char_length('Carla') > 1 then
      raise exception '8b: o nome da pessoa se repetiu em: %', v_t;
    end if;
  end loop;

  -- 9. _parceiro_nome_curto.
  for v_r in
    select * from (values
      ('Paulo Henrique Souza', 'individual', false, 'Paulo S.'),
      ('João da Silva', 'individual', false, 'João S.'),
      ('Maria', 'individual', false, 'Maria'),
      ('ana beatriz dos santos', 'individual', false, 'Ana S.'),
      ('João e', 'individual', false, 'João'),
      ('MP MOTOR HOMES', 'company', false, 'MP'),
      ('Pedro Teste Provisório', 'individual', true, 'Pedro')
    ) as x(nome, tipo, provisorio, esperado)
  loop
    insert into public.clients (type, name, provisorio, origem)
      values (v_r.tipo, v_r.nome, v_r.provisorio, case when v_r.provisorio then 'retorno' end)
      returning id into v_k;
    v_t := public._parceiro_nome_curto(v_k);
    if v_t is distinct from v_r.esperado then
      raise exception '9a: nome curto de "%" saiu %', v_r.nome, v_t;
    end if;
  end loop;
  insert into public.clients (type, name, display_name) values ('individual', 'Roberto Carlos Lima', 'Beto') returning id into v_k;
  if public._parceiro_nome_curto(v_k) is distinct from 'Beto' then
    raise exception '9b: o display_name não valeu';
  end if;
  update public.clients set generico = true where id = v_k;
  if public._parceiro_nome_curto(v_k) is not null then
    raise exception '9c: cliente genérico ganhou nome';
  end if;

  -- 10. _parceiro_bem e _parceiro_bem_do_par. A placa no nome da unidade nunca sai.
  for v_r in
    select * from (values ('Motorhome', 'ABC1D23', 'motorhome'), ('Trailer', 'Apolo', 'trailer'), ('Camper', 'Bege', 'camper'),
                          ('Lancha', 'Netuno', 'barco'), ('Moto aquática', 'Jet', 'barco'), ('Catamarã', 'Duas', 'barco'),
                          ('Van', 'Ducato', 'veículo'), (null, 'Sem tipo', 'veículo')) as x(tipo, nome, esperado)
  loop
    insert into public.clients (type, name) values ('individual', 'Dono Bem F4 ' || v_r.nome) returning id into v_k;
    insert into public.vessels (client_id, name, asset_type) values (v_k, v_r.nome, v_r.tipo) returning id into v_j1;
    v_t := public._parceiro_bem(v_j1);
    if v_t is distinct from v_r.esperado or v_t ~* 'abc|1d23' then
      raise exception '10a: bem de % saiu %', coalesce(v_r.tipo, '(nulo)'), v_t;
    end if;
  end loop;
  if public._parceiro_bem(null) is distinct from 'veículo' or public._parceiro_bem(gen_random_uuid()) is distinct from 'veículo' then
    raise exception '10b: unidade nula ou inexistente não deu veículo';
  end if;
  v_k := pg_temp.retorno_f4_textos_cliente('Par Bem F4', 'individual', 'Motorhome');
  perform pg_temp.retorno_f4_textos_liga(v_parc, v_k, 'confirmado');
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, grand_total)
    select 'ORÇ-TF4-TXT-PAR2', v.client_id, v.id, 'draft', 'draft', 'repair', 0 from public.vessels v where v.client_id = v_k limit 1;
  insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, situacao, origem, confirmado_em)
    select so.id, v_parc, v_k, 'contratante', 'confirmado', 'propria', now()
      from public.service_orders so where so.service_order_number = 'ORÇ-TF4-TXT-PAR2';
  if public._parceiro_bem_do_par(v_k, v_parc) is distinct from 'motorhome' then
    raise exception '10c: duas OS de motorhome no par não deram motorhome';
  end if;
  insert into public.vessels (client_id, name, asset_type) values (v_k, 'Netuno Par', 'Lancha') returning id into v_j1;
  insert into public.parceiros (nome, sigla, tipo) values ('Pátio Bem F4', 'PBF', 'patio') returning id into v_pg;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, grand_total)
    values ('ORÇ-TF4-TXT-PAR3', v_k, v_j1, 'draft', 'draft', 'repair', 0);
  insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, situacao, origem, confirmado_em)
    select so.id, v_parc, v_k, 'indicou', 'confirmado', 'carteira', now()
      from public.service_orders so where so.service_order_number = 'ORÇ-TF4-TXT-PAR3';
  if public._parceiro_bem_do_par(v_k, v_parc) is distinct from 'veículo' then
    raise exception '10d: palavras diferentes no par não deram veículo';
  end if;
  if public._parceiro_bem_do_par(v_k, v_pg) is distinct from 'veículo' then
    raise exception '10e: par sem vínculo confirmado não deu veículo';
  end if;

  -- 11. _parceiro_nomes_do_contexto nos casos de P4.2, cada um com o seu parceiro (homônimos inventados).
  insert into public.parceiros (nome, sigla, tipo) values ('Nomes A F4', 'NAF', 'revenda') returning id into v_pa;
  insert into public.parceiros (nome, sigla, tipo) values ('Nomes B F4', 'NBF', 'revenda') returning id into v_pb;
  insert into public.parceiros (nome, sigla, tipo) values ('Nomes C F4', 'NCF', 'revenda') returning id into v_pc;
  insert into public.parceiros (nome, sigla, tipo) values ('Nomes D F4', 'NDF', 'revenda') returning id into v_pd;
  insert into public.parceiros (nome, sigla, tipo) values ('Nomes E F4', 'NEF', 'revenda') returning id into v_pe;
  insert into public.parceiros (nome, sigla, tipo) values ('Nomes F F4', 'NFF', 'revenda') returning id into v_pf;
  v_j1 := pg_temp.retorno_f4_textos_cliente('João Silva');
  v_j2 := pg_temp.retorno_f4_textos_cliente('João Souza');
  v_j3 := pg_temp.retorno_f4_textos_cliente('João');
  v_j4 := pg_temp.retorno_f4_textos_cliente('João Almeida');
  -- (a) João S. na lista e João S. fora: o de fora sai de nomes_de_outros (a colisão se resolve na linha, P7.2).
  perform pg_temp.retorno_f4_textos_liga(v_pa, v_j1); perform pg_temp.retorno_f4_textos_liga(v_pa, v_j2);
  v := public._parceiro_nomes_do_contexto(v_pa, array[v_j1], null);
  if v -> 'nomes_da_lista' is distinct from '["João S."]'::jsonb or v -> 'nomes_de_outros' is distinct from '[]'::jsonb then
    raise exception '11a: (%)', v;
  end if;
  -- (b) João S. na lista e João fora.
  perform pg_temp.retorno_f4_textos_liga(v_pb, v_j1); perform pg_temp.retorno_f4_textos_liga(v_pb, v_j3);
  v := public._parceiro_nomes_do_contexto(v_pb, array[v_j1], null);
  if v -> 'nomes_da_lista' is distinct from '["João S."]'::jsonb or v -> 'nomes_de_outros' is distinct from '["João"]'::jsonb then
    raise exception '11b: (%)', v;
  end if;
  -- (c) João S. na lista e João A. fora, que não colide.
  perform pg_temp.retorno_f4_textos_liga(v_pc, v_j1); perform pg_temp.retorno_f4_textos_liga(v_pc, v_j4, 'recusado');
  v := public._parceiro_nomes_do_contexto(v_pc, array[v_j1], null);
  if v -> 'nomes_da_lista' is distinct from '["João S."]'::jsonb or v -> 'nomes_de_outros' is distinct from '["João A."]'::jsonb then
    raise exception '11c: (%)', v;
  end if;
  -- (d) dois João S. na lista: uma entrada só, e nenhum outro.
  v := public._parceiro_nomes_do_contexto(v_pa, array[v_j1, v_j2], null);
  if v -> 'nomes_da_lista' is distinct from '["João S."]'::jsonb or v -> 'nomes_de_outros' is distinct from '[]'::jsonb then
    raise exception '11d: (%)', v;
  end if;
  -- (e) pessoa Carla e cliente Carla fora: pessoa_ok falso. (f) cliente Carla A. fora: pessoa_ok verdadeiro.
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_pe, 'Carla', 'comercial') returning id into v_pessoa_e;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_pf, 'Carla', 'comercial') returning id into v_pessoa_f;
  v_c1 := pg_temp.retorno_f4_textos_cliente('Carla');
  v_c2 := pg_temp.retorno_f4_textos_cliente('Carla Alves');
  perform pg_temp.retorno_f4_textos_liga(v_pe, v_c1, 'pausado');
  perform pg_temp.retorno_f4_textos_liga(v_pf, v_c2);
  v := public._parceiro_nomes_do_contexto(v_pe, '{}'::uuid[], v_pessoa_e);
  if (v ->> 'pessoa_ok')::boolean is not false or v ->> 'nome_permitido' is distinct from 'Carla' then
    raise exception '11e: (%)', v;
  end if;
  v := public._parceiro_nomes_do_contexto(v_pf, '{}'::uuid[], v_pessoa_f);
  if (v ->> 'pessoa_ok')::boolean is not true or v -> 'nomes_de_outros' is distinct from '["Carla A."]'::jsonb
     or v -> 'nomes_da_lista' ? 'Carla' then
    raise exception '11f: (%)', v;
  end if;
  -- (g) clientes de nome único Gustavo, Claudia, HBR e a sigla do parceiro nunca entram em nomes_de_outros.
  v_c1 := pg_temp.retorno_f4_textos_cliente('Gustavo');
  v_c2 := pg_temp.retorno_f4_textos_cliente('Claudia');
  v_c3 := pg_temp.retorno_f4_textos_cliente('Ndf');
  perform pg_temp.retorno_f4_textos_liga(v_pd, v_c1); perform pg_temp.retorno_f4_textos_liga(v_pd, v_c2);
  perform pg_temp.retorno_f4_textos_liga(v_pd, v_c3); perform pg_temp.retorno_f4_textos_liga(v_pd, v_j4);
  v := public._parceiro_nomes_do_contexto(v_pd, '{}'::uuid[], null);
  if v -> 'nomes_de_outros' is distinct from '["João A."]'::jsonb then
    raise exception '11g: palavras fixas entraram em nomes_de_outros (%)', v;
  end if;
  -- P04 e P15 pelo parceiro: o nome que é entrada inteira de nomes_de_outros (João, no parceiro B) sai na forma sem nome.
  v_t := public._parceiro_texto('parceiro_coleta', 'whatsapp', jsonb_build_object('primeiro_nome', 'João', 'parceiro_id', v_pb));
  if v_t is distinct from 'O cliente tem WhatsApp? Se autorizar, me passa o número que o Gustavo fala direto.' then
    raise exception '11h: P04 com João fora: %', v_t;
  end if;
  v_t := public._parceiro_texto('parceiro_coleta', 'whatsapp', jsonb_build_object('primeiro_nome', 'Pedro', 'parceiro_id', v_pb));
  if v_t is distinct from 'Obrigada! Pedro tem WhatsApp? Se o cliente autorizar, me passa o número que o Gustavo fala direto.' then
    raise exception '11i: P04 com Pedro: %', v_t;
  end if;
  v_t := public._parceiro_texto('parceiro_recibo', 'orcamento', jsonb_build_object('abertura', '', 'quando', 'hoje', 'hora', '19h',
                                'bem', 'motorhome', 'primeiro_nome', 'João', 'parceiro_id', v_pb));
  if v_t is distinct from 'O orçamento do motorhome do cliente está com o Gustavo; ele retorna para vocês ainda hoje.' then
    raise exception '11j: P15 com João fora: %', v_t;
  end if;

  -- 12. Gênero: a busca no catálogo e o nome feminino inventado.
  v_t := pg_get_functiondef('public._parceiro_texto(text, text, jsonb)'::regprocedure);
  if v_t ~ ' do \{(?!bem\})' or v_t ~* '\yele já' or v_t ~* '\ya ele\y' or v_t ~* '\ydele\y' then
    raise exception '12a: o catálogo à MP tem " do {", "ele já", "a ele" ou "dele"';
  end if;
  for v_r in
    select * from (values
      ('P04', 'parceiro_coleta', 'whatsapp', '{"primeiro_nome": "Maria C.", "nomes_de_outros": []}'::jsonb, 'Maria C. tem WhatsApp'),
      ('P06', 'parceiro_painel', 'linha', '{"n": 1, "bem": "motorhome", "cliente": "Maria C.", "estado": "em_servico"}'::jsonb, 'Motorhome de Maria C.:'),
      ('P07', 'parceiro_eco', 'pronto', '{"bem": "motorhome", "cliente": "Maria C."}'::jsonb, 'motorhome de Maria C. ficou'),
      ('P14', 'parceiro_repassar', null, '{"abertura": "", "bem": "motorhome", "primeiro_nome": "Maria C."}'::jsonb, '"Maria C., o serviço'),
      ('P15', 'parceiro_recibo', 'orcamento', '{"abertura": "", "quando": "hoje", "hora": "19h", "bem": "motorhome", "primeiro_nome": "Maria C.", "nomes_de_outros": []}'::jsonb, 'motorhome de Maria C. está'),
      ('P16', 'parceiro_legenda', null, '{"abertura": "", "bem": "motorhome", "primeiro_nome": "Maria C.", "validade": "15/01"}'::jsonb, 'motorhome de Maria C., válido')
    ) as x(modelo, tipo, variante, dados, trecho)
  loop
    v_t := public._parceiro_texto(v_r.tipo, v_r.variante, v_r.dados);
    if strpos(v_t, v_r.trecho) = 0 or v_t ~ 'do Maria' or v_t ~* '\yele já' or v_t ~* '\ya ele\y' or v_t ~* '\ydele\y' then
      raise exception '12b: gênero em %: %', v_r.modelo, v_t;
    end if;
  end loop;

  -- 13. _cliente_ja_apresentada: o aviso ao cliente final enviado conta como apresentação; o agendado não.
  insert into public.clients (type, name, whatsapp) values ('individual', 'Kátia Apresentada F4', '5547900014299') returning id into v_k;
  if public._cliente_ja_apresentada(v_k, '00014299', (c_t at time zone 'America/Sao_Paulo')::date) then
    raise exception '13a: cliente novo já apresentado';
  end if;
  insert into public.retorno_saidas (emissor, tipo, variante, origem, classe, chave, phone_normalized, client_id, modo, estado,
                                     enviar_em, decidida_em, texto, dedupe_key)
    values ('parceiro', 'parceiro_aviso_cliente', 'com_apresentacao', 'retorno_aviso', 'aviso', '00014299', '5547900014299', v_k,
            'ligado', 'agendada', c_t - interval '1 day', null, null, 'teste-f4-textos:13:agendado');
  if public._cliente_ja_apresentada(v_k, '00014299', (c_t at time zone 'America/Sao_Paulo')::date) then
    raise exception '13b: aviso só agendado contou como apresentação';
  end if;
  insert into public.retorno_saidas (emissor, tipo, variante, origem, classe, chave, phone_normalized, client_id, modo, estado,
                                     enviar_em, decidida_em, enviada_em, texto, dedupe_key)
    values ('parceiro', 'parceiro_aviso_cliente', 'com_apresentacao', 'retorno_aviso', 'aviso', '00014299', '5547900014299', v_k,
            'ligado', 'enviada', c_t - interval '1 day', c_t - interval '1 day', c_t - interval '1 day',
            'Texto de teste do aviso ao cliente.', 'teste-f4-textos:13:enviado');
  if not public._cliente_ja_apresentada(v_k, '00014299', (c_t at time zone 'America/Sao_Paulo')::date) then
    raise exception '13c: aviso enviado não contou como apresentação';
  end if;
  if not public._cliente_ja_apresentada(null, '00014299', (c_t at time zone 'America/Sao_Paulo')::date) then
    raise exception '13d: aviso enviado não contou pela chave';
  end if;

  -- 14. O contexto do validador (sem linha pronto: essa chama a P7 e é testada em P7.3-16).
  v := public._parceiro_contexto_do_validador(null, 'Combinado, João: o andamento fica só entre nós.',
                                              '{"tipo": "parceiro_nao_mp_ok", "nome": "João"}', c_t);
  if v ->> 'audiencia' is distinct from 'cliente' or v -> 'nomes_de_outros' is distinct from '[]'::jsonb
     or v ->> 'nome_permitido' is distinct from 'João'
     or v -> 'trechos_do_modelo' is distinct from '["Combinado, ", ": o andamento fica só entre nós."]'::jsonb then
    raise exception '14a: contexto do Q03 (%)', v;
  end if;
  update public.parceiro_numeros set apresentada_em = c_t - interval '1 day' where id = v_num_carla;
  v_t := 'Oi, Carla! Já passei sua mensagem ao Gustavo, e ele retorna para vocês ainda hoje.';
  v := public._parceiro_contexto_do_validador(null, v_t,
         jsonb_build_object('tipo', 'parceiro_recibo', 'numero_id', v_num_carla, 'quando', 'hoje', 'hora', '19h'), c_t);
  if v ->> 'audiencia' is distinct from 'parceiro' or v ->> 'nome_permitido' is distinct from 'Carla'
     or not (v -> 'datas_permitidas' ? 'ainda hoje') or jsonb_typeof(v -> 'papel_do_parceiro') is distinct from 'null'
     or (v -> 'marcas' ->> 'cliente_ouviu')::boolean is not false or v -> 'nomes_da_lista' is distinct from '[]'::jsonb
     or v -> 'trechos_do_modelo' is distinct from '["Oi, ", "! Já passei sua mensagem ao Gustavo, e ele retorna para vocês ", "."]'::jsonb
     or jsonb_typeof(v -> 'nomes_de_outros') is distinct from 'array' then
    raise exception '14b: contexto do P02 (%)', v;
  end if;
  -- Com um vínculo contratante citado: o papel mais forte e o nome da linha na lista.
  v_vinculo := (select oi.id from public.os_interessados oi where oi.parceiro_id = v_parc and oi.papel = 'contratante' limit 1);
  v := public._parceiro_contexto_do_validador(null, 'Pátio HBR · ter (12/01)',
         jsonb_build_object('tipo', 'parceiro_painel', 'parceiro_id', v_parc, 'pessoa_id', v_carla,
                            'interessado_ids', jsonb_build_array(v_vinculo), 'dia', '2027-01-12',
                            'linhas', jsonb_build_array(jsonb_build_object('n', 1, 'estado', 'andamento', 'desde', '2027-01-02',
                                                                            'interessado_id', v_vinculo))), c_t);
  if v ->> 'papel_do_parceiro' is distinct from 'contratante' or v -> 'nomes_da_lista' is distinct from '["Par F."]'::jsonb
     or not (v -> 'datas_permitidas' ?& array['ter (12/01)', '12/01', '02/01'])
     or (v -> 'marcas' ->> 'cliente_ouviu')::boolean is not false then
    raise exception '14c: contexto do painel sem linha pronto (%)', v;
  end if;

  -- 15. A varredura do parceiro: as funções novas fechadas a anon e authenticated, com search_path.
  for v_r in
    select p.oid, p.proname, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname ~ '^_?parceiro_'
  loop
    v_n_fun := v_n_fun + 1;
    if has_function_privilege('anon', v_r.oid, 'execute') or has_function_privilege('authenticated', v_r.oid, 'execute') then
      raise exception '15: % aberta a anon/authenticated', v_r.nome;
    end if;
    if v_r.proname !~ '^_' and not has_function_privilege('service_role', v_r.oid, 'execute') then
      raise exception '15: % sem execute para o service_role', v_r.nome;
    end if;
    if v_r.prosecdef and not exists (select 1 from unnest(v_r.config) o where o ~ '^search_path=') then
      raise exception '15: % é SECURITY DEFINER sem search_path', v_r.nome;
    end if;
  end loop;
  if v_n_fun < 9 then
    raise exception '15: a varredura achou só % funções do parceiro', v_n_fun;
  end if;

  raise exception 'retorno_f4_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f4_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f4_textos', true, '{}');
end
$textos$;

select arquivo, ok, numeros from _bancada order by em;
rollback;

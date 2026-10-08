-- Cadastro das pastas de clientes do Dropbox (07/10/2026), conforme as respostas do dono
-- DBX-01..DBX-16 na página "Respostas do Diário".
--   - liga cada pasta ao cliente/embarcação (pastas_dropbox);
--   - cria a embarcação que faltava nos clientes já cadastrados;
--   - cria cliente + embarcação para as pastas sem cadastro (só nome; sem telefone e documento);
--   - separa o barco do nome do cliente (DBX-03), guardando o nome anterior nas observações;
--   - desativa o cadastro duplicado "JUNIOR CV450 / XF-06" (sem nenhum uso) — é o Edson Rudek Junior;
--   - barco sem dono conhecido fica como pasta "dono_a_identificar" (embarcação exige cliente).
-- Usa ids fixos conferidos no banco em 07/10. Idempotente: rodar de novo não duplica nada.
-- Depende de 20261007230000_pastas_dropbox.sql.

create or replace function pg_temp.barco_existente(_cli uuid, _nome text) returns uuid
language plpgsql as $$
declare _ids uuid[];
begin
  select array_agg(id) into _ids from public.vessels where client_id = _cli and name = _nome;
  if coalesce(array_length(_ids, 1), 0) <> 1 then
    raise exception 'esperava 1 embarcação "%" no cliente %, achei %', _nome, _cli, coalesce(array_length(_ids, 1), 0);
  end if;
  return _ids[1];
end $$;

create or replace function pg_temp.barco(_cli uuid, _nome text, _fab text, _mod text, _tipo text) returns uuid
language plpgsql as $$
declare _ids uuid[]; _id uuid;
begin
  select array_agg(id) into _ids from public.vessels where client_id = _cli and name = _nome;
  if coalesce(array_length(_ids, 1), 0) > 1 then
    raise exception 'embarcação "%" repetida no cliente %', _nome, _cli;
  end if;
  _id := _ids[1];
  if _id is null then
    insert into public.vessels (client_id, name, manufacturer, model, asset_type)
    values (_cli, _nome, _fab, _mod, _tipo) returning id into _id;
  end if;
  return _id;
end $$;

-- Cliente novo a partir de uma pasta: se a pasta já foi cadastrada, devolve o mesmo cliente.
create or replace function pg_temp.cliente_novo(_dbx text, _nome text, _nota text) returns uuid
language plpgsql as $$
declare _id uuid;
begin
  select client_id into _id from public.pastas_dropbox where dropbox_id = _dbx and client_id is not null;
  if _id is null then
    insert into public.clients (type, name, notes)
    values ('individual', _nome, concat_ws(' ', 'Cadastrado a partir da pasta do Dropbox (07/10/2026); sem telefone e documento.', _nota))
    returning id into _id;
  end if;
  return _id;
end $$;

create or replace function pg_temp.anotar(_cli uuid, _texto text) returns void
language sql as $$
  update public.clients set notes = concat_ws(E'\n', nullif(notes, ''), _texto)
   where id = _cli and coalesce(notes, '') not like '%' || _texto || '%';
$$;

create or replace function pg_temp.renomear(_cli uuid, _antigo text, _novo text) returns void
language plpgsql as $$
begin
  update public.clients
     set name = _novo,
         notes = concat_ws(E'\n', nullif(notes, ''), 'Nome anterior: ' || _antigo || ' (07/10/2026: o barco saiu do nome e virou embarcação).')
   where id = _cli and name = _antigo;
  if not exists (select 1 from public.clients where id = _cli and name = _novo) then
    raise exception 'cliente % não está nem como "%" nem como "%"', _cli, _antigo, _novo;
  end if;
end $$;

create or replace function pg_temp.pasta(_dbx text, _caminho text, _cli uuid, _ves uuid, _cod text,
                                         _sit text, _nome text, _obs text) returns void
language sql as $$
  insert into public.pastas_dropbox (dropbox_id, caminho, client_id, vessel_id, codigo_projeto, situacao, nome_na_pasta, observacao)
  values (_dbx, _caminho, _cli, _ves, _cod, _sit, _nome, _obs)
  on conflict (dropbox_id) do update
     set caminho = excluded.caminho, client_id = excluded.client_id, vessel_id = excluded.vessel_id,
         codigo_projeto = excluded.codigo_projeto, situacao = excluded.situacao,
         nome_na_pasta = excluded.nome_na_pasta, observacao = excluded.observacao;
$$;

do $$
declare
  b2c constant text := '/MANAGEMENT/COMMERCIAL/B2C/';
  b2b constant text := '/MANAGEMENT/COMMERCIAL/B2B/';
  c uuid;
  v uuid;
begin
  -- -------------------------------------------------------------------------------------------
  -- DBX-03: separar o barco do nome do cliente (antes de criar as embarcações)
  -- -------------------------------------------------------------------------------------------
  perform pg_temp.renomear('15d32bf7-8c87-4e5b-999f-cce3242f7715', 'NEWTON (MOTORHOME - SC)', 'Newton');
  perform pg_temp.renomear('4d3c02cb-675d-4212-be7f-06f961ca8c60', 'PEDRO ZETA 260', 'Pedro');
  perform pg_temp.renomear('c37ddf3f-4edf-46c8-bb0e-70b7e9de49bb', 'SERGIO (PHANTOM 500 - SEA BROTHERS)', 'Sergio');
  perform pg_temp.renomear('b1355ab6-6630-43b1-91f1-a98d7ce937f9', 'Rodrigo (AZIMUT 56 - JJBALAK)', 'Rodrigo');
  perform pg_temp.renomear('248f7eb5-df2e-4c3b-bb5e-d412ce48a926', 'LUCIANO (TRAILER - APOLO 3000 / VEÍCULO HILUX 2015)', 'Luciano');
  perform pg_temp.renomear('1e5d9949-a566-4811-8b20-89b6aa1bc78d', 'DESCONHECIDO MCP 76 ASTA X', 'Marcelo Almeida');
  perform pg_temp.renomear('ab806aab-c137-4a15-8b19-1fe2258aa7d7', 'Jose - Renault Master Homebus', 'José');
  perform pg_temp.renomear('55beacf3-3550-4a91-9b82-7ba5f57334f0', 'Lírio - S.I. 8.5 2016', 'Lírio');
  perform pg_temp.renomear('259c7584-dfb2-496a-8036-8d32cf80873e', 'Nelson - S.I. 7.8', 'Nelson');
  perform pg_temp.anotar('b1355ab6-6630-43b1-91f1-a98d7ce937f9', 'Comandante do JJ Balak (Azimut 56).');
  perform pg_temp.anotar('248f7eb5-df2e-4c3b-bb5e-d412ce48a926', 'Veículo: Hilux 2015.');
  perform pg_temp.anotar('15d32bf7-8c87-4e5b-999f-cce3242f7715', 'Cliente indicado pelo Kamel; SC.');

  -- -------------------------------------------------------------------------------------------
  -- DBX-01: cliente e embarcação já cadastrados — só liga a pasta
  -- -------------------------------------------------------------------------------------------
  c := '9f3c85a6-71a8-411e-9ace-d0ceb70e0d54';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACeQQ', b2c || 'Jose Carlos - CAMPER DUARON', c, pg_temp.barco_existente(c, 'Duaron'), null, 'vinculada', null, null);
  c := 'ea0790b3-7d1e-4feb-abc9-51f335822903';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACSTg', b2c || '0016.013.25_Dona V', c, pg_temp.barco_existente(c, 'Donna V'), '0016.013.25', 'vinculada', null, null);
  c := 'd41fd55a-4aff-48e6-a76d-23d21a2d5da7';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACcrA', b2c || '0022.003.26_Maddu_I', c, pg_temp.barco_existente(c, 'Madu I'), '0022.003.26', 'vinculada', null, null);
  c := '0025cc98-9708-453c-a6ed-cb0acbf526e5';
  v := pg_temp.barco_existente(c, 'La Osadia');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACbKQ', b2c || '0020.001.26_La_Osadia', c, v, '0020.001.26', 'vinculada', null, null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACalg', b2c || 'LA OSADIA - Jose Antonio Yege', c, v, null, 'vinculada', null, 'Duplicada da 0020.001.26_La_Osadia: juntar nela (DBX-18).');
  c := '0075f723-9ff6-4a16-9d5d-cca6b5bee522';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAPgQ', b2c || 'CELIO (PORTO FINO 35 - DONDOCA)', c, pg_temp.barco_existente(c, 'Dondoka'), null, 'vinculada', null, null);
  c := '4a4632c1-4bca-400c-b4df-2e2e3b562560';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACVfg', b2c || 'MH. Clovis', c, pg_temp.barco_existente(c, 'S.I. 8.5 Iveco'), null, 'vinculada', null, null);
  c := 'e3f1e177-6ab4-4d02-a049-2a66e79d903d';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACeKA', b2c || 'MH - Sidemir Souza S.I. 8.5', c, pg_temp.barco_existente(c, 'S.I 8.5'), null, 'vinculada', null, null);
  c := '0a39bab4-01a6-4800-83dd-9ad31fe40bc7';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACeEA', b2c || 'ARIA - AZ56', c, pg_temp.barco_existente(c, 'Aria'), null, 'vinculada', null, null);
  c := '0ab58682-2191-4c65-9b13-3b11959f095d';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABu_w', '/MANAGEMENT/BARCOS - REFORMAS/LADY VIC - BAYLINER 19', c, pg_temp.barco_existente(c, 'Lady Vic'), null, 'vinculada', null, null);

  -- DBX-13: a Charline (parente da Lucenira) cuida do S.I. 8.5 Automático
  c := '05451834-67f4-4937-87b2-69c61e41652b';
  v := pg_temp.barco_existente(c, 'S.I. 8.5 Automatico');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACeUg', b2c || 'MH - S.I. 8.5 AUTOM. 2025 - Charline Bombinhas', c, v, null, 'vinculada', null, null);
  insert into public.vessel_contacts (vessel_id, full_name, role, notes)
  select v, 'Charline', 'Responsável', 'Parente da Lucenira; cuida de tudo do motorhome (Bombinhas).'
   where not exists (select 1 from public.vessel_contacts where vessel_id = v and full_name = 'Charline');

  -- -------------------------------------------------------------------------------------------
  -- DBX-02 e DBX-04..12: cliente já cadastrado; cria a embarcação quando a pasta diz qual é
  -- -------------------------------------------------------------------------------------------
  c := 'bf809f8f-81d0-40dd-9da9-b57ef81ac630';  -- Antônio Pradi: um serviço no gerador, sem barco
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABvXA', b2c || 'ANTONIO PRADI - GERADOR ITAJAI', c, null, null, 'vinculada', null, 'Um serviço no gerador; sem embarcação.');
  c := '0d426b2f-79ad-4a5c-87ae-2749fff75b40';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAWHA', b2c || 'HENRIQUE ARAÚJO (MOTORHOME - ARCO VERDE-PE)', c, pg_temp.barco(c, 'Motorhome', null, null, 'Motorhome'), null, 'vinculada', null, null);
  c := 'eda226b7-58de-4633-930a-ad84c8d57903';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAWZg', b2c || '0012.009.25_MONTANHA (MH - SÃO JOSÉ)', c, pg_temp.barco(c, 'Motorhome', null, null, 'Motorhome'), '0012.009.25', 'vinculada', null, null);
  c := '6295de42-3b44-4cd1-b6cb-1bf099b9bda8';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABuzQ', b2c || '0001.001.24_Roberto BARDDAL MOTORHOME NVT (OVERLAND TRUCK)', c, pg_temp.barco(c, 'Motorhome NVT', 'NVT', 'Overland Truck', 'Motorhome'), '0001.001.24', 'vinculada', null, null);
  c := 'bd0c509e-4865-4d40-bd29-3a2c77ab2a21';
  perform pg_temp.anotar(c, 'Parceiro de trabalho: cuida de vários barcos e também faz elétrica.');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABfiw', b2c || 'MAICON LEONEL', c, null, null, 'vinculada', null, 'Parceiro; vários barcos.');
  c := '1fe80793-c92c-4777-b11b-39f47d20cf2e';
  perform pg_temp.anotar(c, 'Administra vários barcos no Paraguai.');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAZSg', b2c || 'Maykon Albano - PARAGUAY', c, null, null, 'vinculada', null, 'Administrador de vários barcos no Paraguai.');
  c := '368b4c2b-62fe-4755-b4e7-f0127fe99132';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAYmg', b2c || 'SERGIO L. KEINERT FILHO - BELLA SKF', c, pg_temp.barco(c, 'Bella SKF', null, null, 'Lancha'), null, 'vinculada', null, null);
  c := 'c1ee13ec-9cbe-487a-8a62-ff73c6e82f9f';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACRPA', b2c || '0015.012.25_Sandro_Poeta_Motorhome', c, pg_temp.barco(c, 'Motorhome', null, null, 'Motorhome'), '0015.012.25', 'vinculada', null, null);
  c := '7624e5bf-a5b1-4128-9a13-9fa128c9649f';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAVvg', b2c || 'MARUJO DESPACHANTE (FOCKER)', c, pg_temp.barco(c, 'Focker', null, null, 'Lancha'), null, 'vinculada', null, null);
  c := '43ef220e-a34c-4fd1-92a6-96ac9dfcb4d0';  -- "Porto Fino 35 - Caju": nome do cliente fica até o dono dizer quem é
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAB8Rw', b2c || 'CAJU - PORTO FINO FLY 35', c, pg_temp.barco(c, 'Caju', 'Porto Fino', 'Fly 35', 'Lancha'), null, 'vinculada', null, null);
  c := '7d4264b7-37e4-44b8-b662-48b7b121614c';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAWEQ', b2c || 'MOTORHOME - ITAPEMA MYHOUSE', c, null, null, 'vinculada', null, null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABv-A', b2b || 'MY HOUSE - MOTORHOMES', c, null, null, 'vinculada', null, 'Parceiro (B2B).');
  c := '15d32bf7-8c87-4e5b-999f-cce3242f7715';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAWRw', b2c || 'NEWTON (MH - SC) Cliente kamel', c, pg_temp.barco(c, 'Motorhome', null, null, 'Motorhome'), null, 'vinculada', null, null);
  c := '4d3c02cb-675d-4212-be7f-06f961ca8c60';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAC9Q', b2c || 'PEDRO (ZETA 260)', c, pg_temp.barco(c, 'Zeta 260', null, 'Zeta 260', 'Lancha'), null, 'vinculada', null, null);
  c := 'c37ddf3f-4edf-46c8-bb0e-70b7e9de49bb';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAONg', b2c || 'SERGIO (SEA BROTHERS - PHANTOM 500)', c, pg_temp.barco(c, 'Sea Brothers', null, 'Phantom 500', 'Lancha'), null, 'vinculada', null, null);
  c := '27b8f895-8f9e-473c-9498-651ed5fff15a';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAASeg', b2c || 'UNIQUE (ALFREDO HERING)', c, pg_temp.barco(c, 'Unique', null, null, 'Lancha'), null, 'vinculada', null, null);
  c := 'b1355ab6-6630-43b1-91f1-a98d7ce937f9';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABvCQ', b2c || 'JJBALAK (AZIMUT 56) - Comandante Rodrigo', c, pg_temp.barco(c, 'JJ Balak', 'Azimut', '56', 'Lancha'), null, 'vinculada', null, 'Rodrigo é o comandante; dono do barco não informado.');
  c := 'f865bfd7-5d9e-4d53-be94-8f5153cb3653';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAYqw', b2c || 'DARBI MENIN - SENNA 48', c, pg_temp.barco(c, 'Senna 48', null, null, 'Lancha'), null, 'vinculada', null, null);
  c := 'b9155385-3b8c-440d-b727-026632a00dbd';  -- "FALCON 115 - EMBAIXADOR": o dono não está no nome; fica até ele dizer
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABwBQ', b2c || 'FALCON 115 - EMBAIXADOR', c, pg_temp.barco(c, 'Embaixador', null, 'Falcon 115', 'Lancha'), null, 'vinculada', null, null);
  c := 'ce561cb5-c23b-46ef-b64f-cfdb7ae0e9e1';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAPQg', b2c || 'BLISS CIA MARITIMA LTDA (FARLINE 52 - BLISS)', c, pg_temp.barco(c, 'Bliss', 'Farline', '52', 'Lancha'), null, 'vinculada', null, null);
  c := '2055995e-4b0b-4e13-af80-accd438eb046';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAYzw', b2c || 'MARCIO AGUILAR - NX290 (MARBELLA)', c, pg_temp.barco(c, 'Marbella', 'NX Boats', 'NX 290', 'Lancha'), null, 'vinculada', null, null);
  c := 'd226459e-8794-46d6-adf2-42bff950fbc0';
  perform pg_temp.anotar(c, 'Indicação do Kamel.');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAZuw', b2c || 'James Franco - Indicação Kamell', c, null, null, 'vinculada', null, null);
  c := '248f7eb5-df2e-4c3b-bb5e-d412ce48a926';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAWWA', b2c || 'LUCIANO (TRAILER APOLO 3000 - HILUX 2015)', c, pg_temp.barco(c, 'Trailer Apolo 3000', 'Apolo', '3000', 'Trailer'), null, 'vinculada', null, null);
  c := 'a7e4bd0f-f64b-4d81-89aa-699e16fb0f94';
  perform pg_temp.anotar(c, 'Contatos: Vitor e Cleide.');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAV1A', b2c || 'CIA LAKE SC - ITAJAI (VITOR e CLEIDE)', c, null, null, 'vinculada', null, 'Há um 2º cadastro: CIALAKE Negócios e Lazer EIRELI.');
  c := 'defa89f2-97d1-499c-bcc6-3fcfaf759b44';  -- "RIBAS AZ 30 METRI - COMANDANTE ZEPI": nome fica até o dono dizer quem é quem
  v := pg_temp.barco(c, 'Azimut 30 Metri', 'Azimut', '30 Metri', 'Lancha');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABvoA', b2c || 'COMANDANTE ZEPI - AZ 30 METRI - RIBAS', c, v, null, 'vinculada', null, 'Mesmo barco da 0005.002.25_AZIMUT 30 METRI.');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAB-pw', b2c || '0005.002.25_AZIMUT 30 METRI', c, v, '0005.002.25', 'vinculada', null, null);
  c := 'f5f90e7b-0272-4558-8162-8fbdd331f775';  -- DBX-04
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAYEQ', b2c || 'Marcos Gusmão Reitz', c, null, null, 'vinculada', null, 'A pasta diz Marcos; é o Marcelo Gusmão Reitz.');
  c := '5d8afb8b-c0f8-4a3d-a25d-a355b3d437b6';  -- DBX-05
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAFYA', b2c || 'JAIR (INTERMARINE 480 PALM BEACH)', c, pg_temp.barco(c, 'Intermarine 480 Palm Beach', 'Intermarine', '480', 'Lancha'), null, 'vinculada', null, null);
  c := '4162bd4a-3275-4d88-b294-0de07df13fce';  -- DBX-06
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAAcg', b2c || 'IVAN PORTO BELO (TECNOMARINE 45)', c, pg_temp.barco(c, 'Tecnomarine 45', 'Tecnomarine', '45', 'Lancha'), null, 'vinculada', null, null);
  c := '1e5d9949-a566-4811-8b20-89b6aa1bc78d';  -- DBX-07
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAFUw', b2c || 'MARCELO ALMEIDA (MCP 76 ASTA X)', c, pg_temp.barco(c, 'Asta X', null, 'MCP 76', 'Lancha'), null, 'vinculada', null, null);
  c := 'd7631633-99c6-4be2-9540-09e1d890e51f';  -- DBX-09
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAZTA', b2c || 'BENITO - DOLPHIN 460 (CIRANDA)', c, pg_temp.barco(c, 'Ciranda', null, 'Dolphin 460', 'Lancha'), null, 'vinculada', null, null);
  c := '7a970d4f-a204-46c3-8863-f0e43c80a3a9';  -- DBX-10
  perform pg_temp.anotar(c, 'Marinheiro: Rogerinho.');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAAcA', b2c || 'ANDREAS (ROGERINHO)', c, null, null, 'vinculada', null, 'Rogerinho é o marinheiro.');
  c := 'f7d1656e-d5bb-4193-a41c-8a59dfed7aac';  -- DBX-11
  perform pg_temp.anotar(c, 'Serviço via Mecatron (empresa intermediária).');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAN2g', b2c || 'MECATRON (CAPITANIA DOS PORTOS PARANAGUA)', c, null, null, 'vinculada', null, 'Mecatron foi a intermediária.');

  -- DBX-12: "JUNIOR CV450 / XF-06" é o Edson Rudek Junior (2 barcos). O duplicado não tem uso.
  c := 'd41fd55a-4aff-48e6-a76d-23d21a2d5da7';
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAB6IQ', b2c || 'JUNIOR CV405 - XF.06', c, pg_temp.barco(c, 'XF-06', 'Sedna', null, 'Lancha'), null, 'vinculada', null, null);
  update public.clients
     set active = false,
         notes = concat_ws(E'\n', nullif(notes, ''), 'Duplicado do Edson Luiz Rudek Junior (07/10/2026); desativado. Barcos: Madu I e XF-06.')
   where id = '7e43122a-b4df-4aa8-8dc6-31f8261c0fd8' and active;

  -- -------------------------------------------------------------------------------------------
  -- DBX-15: pastas sem cadastro — cliente + embarcação só com o nome da pasta
  -- -------------------------------------------------------------------------------------------
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAACITQ', 'Diego', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACITQ', b2c || 'Diego - Next Sunset', c, pg_temp.barco(c, 'Next Sunset', null, null, 'Lancha'), null, 'vinculada', null, null);
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAAAPbw', 'Fred Saldanha', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAPbw', b2c || 'FRED SALDANHA - (BOTE ALFANAS II)', c, pg_temp.barco(c, 'Alfanas II', null, 'Bote', 'Lancha'), null, 'vinculada', null, null);
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAABfhA', 'Eduardo Macedo', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABfhA', b2c || 'Eduardo Macedo - Motor Home', c, pg_temp.barco(c, 'Motorhome', null, null, 'Motorhome'), null, 'vinculada', null, null);
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAAAFQA', 'Carlos Nas', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAFQA', b2c || 'PV AZIMUT CARLOS NAS (AZIMUT 88 TITANIUM)', c, pg_temp.barco(c, 'Titanium', 'Azimut', '88', 'Lancha'), null, 'vinculada', null, null);
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAAB6KA', 'Janio Machado', 'Veio por indicação.');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAB6KA', b2c || 'JANIO MACHADO - MH INDICACAO', c, pg_temp.barco(c, 'Motorhome', null, null, 'Motorhome'), null, 'vinculada', null, null);
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAAAXpA', 'Alberto', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAXpA', b2c || 'ALBERTO (COSTA BRAVA II - BAYLINER 350)', c, pg_temp.barco(c, 'Costa Brava II', 'Bayliner', '350', 'Lancha'), null, 'vinculada', null, null);
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAAAYbQ', 'Juan A. Steinihorst', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAYbQ', b2c || 'JUAN A STEINIHORST - LUZ DA LUA (CARBRASMAR 38)', c, pg_temp.barco(c, 'Luz da Lua', 'Carbrasmar', '38', 'Lancha'), null, 'vinculada', null, null);
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAAAWSA', 'Helcio', 'Indicação do Kamel.');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAWSA', b2c || 'HELCIO - MH (INDICAÇÃO KAMELL)', c, pg_temp.barco(c, 'Motorhome', null, null, 'Motorhome'), null, 'vinculada', null, null);
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAAAWuA', 'Rogério', 'Cliente do Kamel; Paraná.');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAWuA', b2c || 'ROGÉRIO (MH - PARANÁ) Cliente Kamel', c, pg_temp.barco(c, 'Motorhome', null, null, 'Motorhome'), null, 'vinculada', null, null);
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAABu1w', 'Luis F. Zanata', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABu1w', b2c || 'LUIS F. ZANATA - VAGABOND', c, pg_temp.barco(c, 'Vagabond', null, null, 'Lancha'), null, 'vinculada', null, null);
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAABuUw', 'Gabriel Zanette', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABuUw', b2c || 'GABRIEL ZANETTE - CAT370 YPOA', c, pg_temp.barco(c, 'Ypoa', null, 'CAT370', 'Catamarã'), null, 'vinculada', null, null);
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAACDKQ', 'Rosangela', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACDKQ', b2c || 'MH - Rosangela', c, pg_temp.barco(c, 'Motorhome', null, null, 'Motorhome'), null, 'vinculada', null, null);
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAACbew', 'Cris e Talyta', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACbew', b2c || '0021.002.26_Onibus_Cris_e_Talyta', c, pg_temp.barco(c, 'Ônibus', null, null, 'Motorhome'), '0021.002.26', 'vinculada', null, null);
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAAAILA', 'Ari', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAILA', b2c || 'ARI (PHANTOM 300 - GIANINNA)', c, pg_temp.barco(c, 'Gianinna', null, 'Phantom 300', 'Lancha'), null, 'vinculada', null, null);
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAAAPbg', 'Riad Yassaf', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAPbg', b2c || 'RIAD YASSAF (AZ70 - HABIB SARAH 1)', c, pg_temp.barco(c, 'Habib Sarah 1', 'Azimut', '70', 'Lancha'), null, 'vinculada', null, null);
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAAAYrw', 'Thiago Barros', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAYrw', b2c || 'THIAGO BARROS - SETTEMARI', c, pg_temp.barco(c, 'Settemari', null, null, 'Lancha'), null, 'vinculada', null, null);
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAAANmA', 'Marcos Bertaia', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAANmA', b2c || 'MARCOS BERTAIA (SEDNA 36 - LADY GATA)', c, pg_temp.barco(c, 'Lady Gata', 'Sedna', '36', 'Lancha'), null, 'vinculada', null, null);
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAACalA', 'Rafael Casagrande', null);
  v := pg_temp.barco(c, 'Lobo do Mar', null, null, 'Lancha');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACalA', b2c || 'LOBO DO MAR - Rafael Casagrande', c, v, null, 'vinculada', null, null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAAaw', b2c || 'CASAGRANDE - LOBO DO MAR', c, v, null, 'vinculada', null, 'Duplicada de LOBO DO MAR - Rafael Casagrande: juntar (DBX-18).');
  c := pg_temp.cliente_novo('id:sZCHZmtLl2AAAAAAAAB1ag', 'Carrard', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAB1ag', b2c || '0004.001.25_AZIMUT 83 - AZVLIK (CARRARD)', c, pg_temp.barco(c, 'Azvlik', 'Azimut', '83', 'Lancha'), '0004.001.25', 'vinculada', null, null);

  -- Barco conhecido, dono não (DBX-08, DBX-14 e as pastas "dono?" da DBX-15)
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAZdQ', b2c || 'ANTARES - AZIMUT 42', null, null, null, 'dono_a_identificar', 'Antares (Azimut 42)', 'O dono não lembra se Antares é o barco ou a Assistência Náutica Antares.');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAC9A', b2c || 'MAICON (WELLCRAFT 280)', null, null, null, 'dono_a_identificar', 'Wellcraft 280', 'O dono não lembra de qual Maicon é.');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAAbg', b2c || 'TOPLINE 410HT ALDEBARAN (INCENDIO)', null, null, null, 'dono_a_identificar', 'Aldebaran (Topline 410HT)', 'Reforma após incêndio.');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABfjQ', b2c || '0017.014.25_Bayliner 27 - WILD ONE', null, null, '0017.014.25', 'dono_a_identificar', 'Wild One (Bayliner 27)', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAPbQ', b2c || 'BASTIANA (SEM DADOS CLIENTE)', null, null, null, 'dono_a_identificar', 'Bastiana', 'A pasta já dizia: sem dados do cliente.');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAPiw', b2c || 'BIG MOUSE (PHANTOM 360)', null, null, null, 'dono_a_identificar', 'Big Mouse (Phantom 360)', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACXTQ', b2c || '0018.015.25_STARK', null, null, '0018.015.25', 'dono_a_identificar', 'Stark', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABfUg', b2c || 'LADY JU - (IATE CLUBE PORTO BELO)', null, null, null, 'dono_a_identificar', 'Lady Ju', 'Iate Clube Porto Belo.');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABu_A', b2c || '0007.004.25_SELENE - AZIMUT 83', null, null, '0007.004.25', 'dono_a_identificar', 'Selene (Azimut 83)', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABuUg', b2c || 'MY DREAM - FERRETI 83', null, null, null, 'dono_a_identificar', 'My Dream (Ferretti 83)', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACIhA', b2c || '0008.004.25_AZUL MARINHO', null, null, '0008.004.25', 'dono_a_identificar', 'Azul Marinho', 'Número do ano repetido com a 0007.004.25.');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAB_wA', b2c || '0006.003.25_BARCO PEQUENO PORTE', null, null, '0006.003.25', 'dono_a_identificar', 'Barco de pequeno porte', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACO7Q', b2c || 'DAY OFF', null, null, null, 'dono_a_identificar', 'Day Off', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAWCg', b2c || 'BELEM DO PARÁ - PLATAFORMAS', null, null, null, 'dono_a_identificar', 'Plataformas (Belém do Pará)', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAGUA', b2c || 'REBOCADOR NVT', null, null, null, 'dono_a_identificar', 'Rebocador NVT', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACXbA', b2c || 'Cllientes Bruno Cs Náutica', null, null, null, 'dono_a_identificar', 'Clientes do Bruno (CS Náutica)', 'Pasta com vários clientes de um parceiro.');

  -- -------------------------------------------------------------------------------------------
  -- DBX-16: B2B — liga os já cadastrados; o resto é prospecção
  -- -------------------------------------------------------------------------------------------
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAYAg', b2b || 'VENTURA MARINE (LOJA ITAJAÍ)', 'b8b15171-4788-4e26-95f1-7f72362583d0', null, null, 'vinculada', null, 'Parceiro (B2B).');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAXog', b2b || 'APOLO TRAILER', '45baa2f5-5bb7-40c8-abb2-3a316bf5c89d', null, null, 'vinculada', null, 'Parceiro (B2B).');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAONw', b2b || 'FORTRO NAUTICA', '0ca417b8-711b-481c-9d3d-5b9c629cd99a', null, null, 'vinculada', null, 'Parceiro (B2B).');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAOEA', b2b || 'MARINE CENTER', 'df47b2a5-0f70-4566-9c3b-055699c49dcd', null, null, 'vinculada', null, 'Parceiro (B2B).');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAZNA', b2b || 'Eurovale Motorhomes', 'a2492973-7578-41a5-9715-08f2220a189c', null, null, 'vinculada', null, 'Parceiro (B2B).');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACHnQ', b2b || 'MURANO YACHTS', '6025d3f7-ed78-41e4-96f5-dd6faa6d1d5e', null, null, 'vinculada', null, 'Parceiro (B2B).');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAACiQ', b2b || 'SEDNA YACHTS', 'eba12498-d621-41c8-8efb-4634c40bd0ce', null, null, 'vinculada', null, 'Parceiro (B2B). Há 2 cadastros da Sedna Group; ligado ao que tem CNPJ.');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAAeQ', b2b || 'NX BOATS', '4db8027d-49d0-4eae-a574-43dfd065252e', null, null, 'vinculada', null, 'Parceiro (B2B).');
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAIQA', b2b || 'FIBRAFORT', null, null, null, 'prospeccao', 'Fibrafort', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAATrA', b2b || 'MOTOR HOME E BARCOS', null, null, null, 'prospeccao', 'Motor Home e Barcos', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAAZQ', b2b || 'FLORIDA MARINE', null, null, null, 'prospeccao', 'Florida Marine', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABwQA', b2b || 'MONDONEX - (GUILHERME GALDOLFI RIBEIRO)', null, null, null, 'prospeccao', 'Mondonex (Guilherme Galdolfi Ribeiro)', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACRIA', b2b || 'LIPPEL', null, null, null, 'prospeccao', 'Lippel', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABv9g', b2b || 'STUDIO NAVAL - FRANK', null, null, null, 'prospeccao', 'Studio Naval (Frank)', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAXbA', b2b || 'CONSTRUTORA - PORTO 5', null, null, null, 'prospeccao', 'Construtora Porto 5', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACSLQ', b2b || 'BLACK MARINE', null, null, null, 'prospeccao', 'Black Marine', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAAag', b2b || 'ATTALUS BOATS', null, null, null, 'prospeccao', 'Attalus Boats', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAAeg', b2b || 'WELLCRAFT BOATS', null, null, null, 'prospeccao', 'Wellcraft Boats', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAUzw', b2b || 'Triton', null, null, null, 'prospeccao', 'Triton', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAACPYw', b2b || 'FS YACHTS', null, null, null, 'prospeccao', 'FS Yachts', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABuZw', b2b || 'Fountaine Pajot - Sailing Yachts Catamarans', null, null, null, 'prospeccao', 'Fountaine Pajot', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAABzcQ', b2b || 'TMG Boats - Fabricio Bonaldo', null, null, null, 'prospeccao', 'TMG Boats (Fabricio Bonaldo)', null);
  perform pg_temp.pasta('id:sZCHZmtLl2AAAAAAAAAAeA', b2b || 'GRAND OCEAN BOATS', null, null, null, 'prospeccao', 'Grand Ocean Boats', null);
end $$;
